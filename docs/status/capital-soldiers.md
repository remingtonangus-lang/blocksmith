# Stream D: Capital soldiers (claude/bs-capital-soldiers)

Owner: session D. Scope: soldier models (dress uniforms, ranks, gear, weapons), their animations, the
crew-station pose hooks, and the backwards-arms bug. Not in scope (other streams): base layouts, ship hulls,
vehicle physics, controller code.

## State (2026-10-04, standing order: never stop; queue = soldiers -> reactive bases -> aircraft -> bug hunting)
- Soldiers: DONE and merged into claude/blocksmith-playtest (d3a9c7c). posecheck 474 checks green.
- Reactive bases (Future ideas #2): first pass on claude/bs-capital-soldiers, being tuned through --basetest.
- Aircraft (Future ideas #8): first pass on claude/bs-capital-soldiers, being tuned through --flighttest traces.

## What exists (code map)
- `Sources/SoldierRig.swift`: the jointed soldier model and all stances.
  - Skeleton: hips + knees (thigh/shin chain), torso lean (rotX) + twist (rotY) about the pelvis, shoulders and
    elbows solved by two-bone IK (`ik`) toward hand targets, a head that pitches/yaws on its own.
  - `SoldierPose` is decided in `pose()` from what the soldier is doing, in this order: crew station, grenade throw,
    reload (progress from `brain.reload / brain.reloadTotal`), aim (`brain.aimHold` > 0, recoil kick from
    `brain.recoil`), alerted low ready / jog (officer points while `brain.pointT` > 0), march / patrol, standing
    guard (attention, parade rest about 40 % of the time, officers hands behind the back).
  - `body()` draws the uniform per rank (levels of detail: full < 14 blocks, medium < 34, low beyond; the mob
    vertex buffer is 4 MB, about 87 k vertices for every mob on screen); `weapon()` places the gun model by its
    anchors; `muzzleWorld()` is where shots and the marksman's laser start.
  - `stage()` handles the harness tokens for still shots (see snap.sh `soldier_*`).
- `Sources/CapitalArms.swift`: the seven gun models (Capital finish) with hand anchors (grip, fore, butt, muzzle,
  magazine well, bolt) and scale; `Guns.models` (first person) uses the same boxes.
- `Sources/Soldiers.swift`: ranks/specs/AI (unchanged behaviour plus the animation timers in `SoldierBrain`,
  officer reaction boost, `Soldier.voice`, `Soldier.garrison` officer promotion). The HeavyTurret section at the end
  belongs to the integration stream.
- `Sources/PoseCheck.swift` (`--posecheck`): the pose oracle (runs in the fast lane and with `--mobtests`).
- Shaders: mob patterns 6 dress cloth, 7 enamel (sun highlight), 8 polished metal, 9 emissive, 10 polished leather,
  11 smoked glass (Shaders.swift `mobPattern` / `mobSheen`, VibrantShaders.swift `mobVibFS`).

## Ranks (save keys never change)
| key | name | look | weapons |
| --- | --- | --- | --- |
| soldier_recruit | Capital Trooper | crested white enamel helmet, open face, grey crossbelts, enamel pack | service rifle / chatter gun |
| soldier_trooper | Capital Vanguard | visored full helm, enamel cuirass, pauldrons, vambraces, knee guards | breach shotgun / rifle |
| soldier_marksman | Capital Marksman | grey beret, glowing monocular, long coat tails, capelet, bandolier | farsight rifle / rifle |
| soldier_ironclad | Capital Bulwark | tall crested helm with a glowing slit, full plate, power cell (x1.12) | launcher / arc lance |
| soldier_officer (new) | Capital Officer | peaked cap, half cape, sash, aiguillette, medals, sabre, holster | Capital Sidearm |
| soldier_crew (new) | Capital Pilot | white flight helmet + smoked visor, grey flight suit, harness, chest holster | sidearm / chatter gun |

Stormwarden / Ironback crews use the same models in their own colours (`Livery.of`).

## Crew-station pose hooks (for stream B, vehicle riding / crews aboard)
```swift
m.station = .seated        // driver / pilot: hands forward on the controls (visor down for pilots)
m.station = .passenger     // troop seat: rifle upright between the knees
m.station = .gunner        // standing at a gun's handles; m.soldierBrain.pitch steers the head
m.station = .console       // standing at a console, hands at waist height
m.station = .attention     // on parade: strict attention whatever the AI is doing
m.station = .none          // back to the soldier's own stances
m.stationSeat = 0.5        // seat top above the mob's feet, in blocks (seated / passenger)
```
Only the model changes: the caller places the mob (pos, yaw, deck) at its station and keeps it there. Seated legs
slope down until the boots reach the floor, so any seat height works. `soldier_crew` is the natural kind for
drivers, pilots and gunners (CapitalShips crew posts currently spawn vanguards / marksmen there).

## Reactive citadels (CapitalBases.swift, CapitalBasesWork.swift, BaseTests.swift)
- Noise bus: `Game.baseNoise(at:kind:power:hostile:)` from player guns (Ballistics.fireHeldGun), every explosion
  (Explosion.explode), player-manned turrets (VehicleControls), ship cannon (ShipCombat.fire), other factions'
  soldiers. The Capital's own shells/grenades are quiet (`bases.quiet` set round them in Ballistics.detonate and
  ShipCombat shell blasts). Hearing: gunfire 96, cannon 200, blasts 64 + 24 x power blocks.
- `BaseRecord` per citadel (key `citadel:cx,cz`, saved in world.json `extra["bases"]`): alert calm / suspicious /
  alert / lockdown (stands down 120 / 90 / 60 s after the last hostile noise, never while a soldier is fighting),
  patrol (target, phase), crawler patrol, blast spheres to rebuild, dropship cooldown.
- Patrol: officer + 3 (fresh ones from the barracks if the garrison is thin) muster at the gate, march waypoint
  by waypoint (18 blocks; the path finder reaches ~48) at low ready in a wedge, search 30 s, walk back to posts.
  Soldiers obey `SoldierBrain.order / orderStation / orderRun / orderFace / ready` (Soldiers.swift soldierAI calm
  branch -> Mob.followOrder). Crawler patrol for blasts/cannon over 70 blocks out: `spawnCapital("crawler",
  faction: .steelhold)` from the motor pool (centre + 92 south), `CapitalState.goal` drives it, removed on return.
- Lockdown: alarm, garrison aggro toward the source, 2 crewmen per 42 cm turret in the gunner stance behind the
  barbette, up to 2 `ShipManager.callDropship(faction:from:to:)` Capital dropships landing troops in the plaza.
- Rebuild: once calm, `BaseWatch.blueprint` regenerates the citadel's chunks on a worker thread (gen.generate +
  structures.place) and restores only cells that are now air / liquid / fire with their original block, bottom up,
  ~1 block/s per pilot (2 pilots at the site in the console stance); time away is caught up on return. Wrecks,
  debris and player builds in a crater are left alone.
- Cost: `BaseWatch.tickMs` (once-a-second update) 0.25 ms avg in the unoptimized CI build; worst 19 ms when a
  dropship hull is built on the main thread (CapitalShips.callDropship): TODO build it off-thread like spawnCapital.
- Checks: `--basetest patrol|crawler|lockdown|rebuild` (and `...shot` variants for pictures). The unoptimized fast
  lane runs ~88 ms a tick with a full garrison, so only patrol/lockdown fit a fast-lane run; crawler and rebuild
  belong to the heavy lane (snap.sh shots shard).

## Aircraft (FlightModel.swift, Aircraft.swift, FlightTests.swift)
- `Ship.flight` (FlightModel) for ships with rotor heads (helicopters) or role "capplane"; older wing builds keep
  the arcade model. Hook in ShipPhysics.integrateForces after the airfoils; the generic steering / keep-upright /
  aircraft pitch blocks are skipped for flight-model ships.
- Fixed wing: per airfoil cell CL(alpha) with stall at 0.3 rad, CD0 + k CL^2, elevator = tail cells (negative
  incidence, pushes the tail down to raise the nose), ailerons = outer cells, virtual fin (weathervane + rudder),
  dihedral. Helicopter: thrust collective x 2.1 weights x rpm^2 (+ ground effect, translational lift) along the
  cyclic-tilted disk over the centre of mass, hub moment, stability augmentation, rotor torque vs tail rotor + pedals.
- Autopilots: `fm.hold` (position) / `fm.holdYaw` / `fm.holdSpeed`. Player: collective Space/Ctrl RT/LT, cyclic
  WASD / left stick, heading follows the view, LB/RB pedals (VehicleControls kind .helicopter).
- Blocks: `ship_rotor` (Rotor Head; blades drawn to the rotor diameter from the render-only `ship_rotor_blade`),
  `capital_airframe` (0.3 t). Designs: Capital Kestrel (helicopter, pilot + 4 seats), Capital Heron (twin-prop,
  wheels, role capplane). `Aircraft.spawn(kind, at:, yaw:, game:, troops:)` seats a Capital pilot (FlightCrew keeps
  seated crews in their seats; seated soldiers don't walk).
- Checks: `--flighttest heli|plane|all` with a `flighttrace` line per second (height, speed, attitude, controls).
