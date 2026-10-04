# Stream D: Capital soldiers (claude/bs-capital-soldiers)

Owner: session D. Scope: soldier models (dress uniforms, ranks, gear, weapons), their animations, the
crew-station pose hooks, and the backwards-arms bug. Not in scope (other streams): base layouts, ship hulls,
vehicle physics, controller code.

## State
- WORK IN PROGRESS: see the log at the end.

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
