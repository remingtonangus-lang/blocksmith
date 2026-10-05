# Frontier — horses

Everything about the horse is original and procedural: no scanned meshes, no mocap, no external textures.
Bar: QUALITY_BAR.md §5 (horses), §4 (animation), §12 (performance).

## Files
| File | What |
|---|---|
| `tools/animals/quadruped.py` + `species/horse.py` | Blender-5-as-a-module generator (shared with the wildlife, design/WILDLIFE.md): anatomy SDF → mesh → rig → weights → hair → tack → gaits/actions → `horse.glb` + `horse_gaits.json`; `tools/animals/horse_gen.py` is the horse-only wrapper |
| `src/actors/rider_ik.gd` (`RiderIK`) | procedural riding pose for a FrontierCharacter rider (hips in the seat, feet in the stirrups, hands on the reins) |
| `src/actors/horse.gd` (`Horse`) | riding controller, cores, fear, bond, care, whistle, hitching, mount/dismount, ride camera, road following |
| `src/actors/horse_visual.gd` (`HorseVisual`) | loads the model, coat/hair materials, LOD ranges, AnimationTree, seat transform, hoof sole positions, stand-in when the model is missing |
| `src/actors/horse_ik.gd` (`HorseIK`) | SkeletonModifier3D: per-hoof terrain IK (two-bone on humerus+forearm / femur+tibia) |
| `src/actors/horse_coats.gd` (`HorseCoats`) | 15 coats, 7 breeds (stats + coat weights), white markings, all from a seed |
| `src/actors/horse_gait_oracle.gd` (`HorseGaitOracle`) | footfall beats/order vs the reference table + foot-slide metric |
| `shaders/horse_coat.gdshader`, `shaders/horse_hair.gdshader` | coat (rest-space patterns, markings, dirt/mud/wet/sweat), mane/tail cards |
| `src/tests/horse_bot.gd` | `--bot ride`, `--bot gaits` (called from `bot_runner.gd`) |
| `src/tests/horse_test.gd`, `scenes/horse_test.tscn` | look-dev scene: poses, gait strips, coat line-up, actions, head close-ups; animation-only gait oracle |

## Generator pipeline (`horse_gen.py`)
Run: `python3 frontier/tools/animals/horse_gen.py [--out DIR] [--quick] [--preview] [--no-anim] [--no-tack]`
(default out: `frontier/assets/animals_out/`, gitignored). `--preview` writes Cycles clay renders, an orthographic
silhouette sheet with a 10 cm grid and side-view gait strips to `OUT/preview/`. Deterministic (fixed seeds).
Full build ≈ 6–8 min on 4 cores; `--quick` ≈ 3 min.

1. **Anatomy.** One landmark table `J` (metres; Blender axes +X right, +Y forward, +Z up, ground 0) for a
   15.2 hh stock horse (withers 1.555 m, body 1.75 m point of shoulder→buttock, girth depth 0.72 m, head 0.62 m).
   ~150 signed-distance primitives built from it: *lofts* (generalised cylinders with superellipse cross-sections
   from side-profile top/bottom lines and half widths) for trunk, neck, head and thighs; tapered capsules and
   ellipsoids for muscles (scapular group, triceps, pectorals, brachiocephalic, gluteals, quadriceps, gaskin,
   forearm extensors), bony landmarks (point of shoulder/hip/hock/elbow, withers, knee, accessory carpal, ergots),
   tendons, fetlocks, pasterns; a hoof primitive (sloped dorsal wall, upright heels, flat sole); subtractions for
   eye sockets, nostrils, mouth line and ear hollows. Smooth unions blend them.
2. **Mesh.** Narrow-band field evaluation (coarse pass + exact values near the surface) → marching cubes
   (scikit-image) → Blender decimate: hero 26k tris, `Body_LOD1` 8k, `Body_LOD2` 2k (weights carried through).
   Per-vertex: `UV0 = rest (x, y)`, `UV1.x = rest z` (exact metres; the exporter's V flip is pre-compensated),
   `COLOR = (AO from BVH ray casts, mean curvature, hoof mask, 1)`.
3. **Rig** (49 bones): `root`, `body` (COM, carries the gait bob), `spine_lumbar`, `pelvis`, `tail_1..6`,
   `spine_thorax` (saddle), `spine_withers`, `neck_1..4`, `head`, `jaw`, `ear_L/R`; fore legs
   `scapula, humerus, forearm, fcannon, fpastern, fhoof`; hind legs `femur, tibia, hcannon, hpastern, hhoof`
   (`_L/_R`). Every bone's local X is the horse's lateral axis, so flexion is a pure local-X rotation.
4. **Skin weights** come from the primitives themselves: each vertex gets a soft-min membership to every
   primitive, each primitive distributes it among its candidate bones by distance to their segments, then
   Laplacian smoothing and a 4-influence limit. (Blender's heat weighting is not used: it fails on
   decimated marching-cubes meshes and bleeds between legs and barrel.)
5. **Hair**: mane (2 layers, ~128 cards rooted on the crest, falling to the off side and kept off the neck
   surface), forelock (9 cards), tail (70 cards around the dock incl. crossed cards for volume) with a painted
   256×512 strand texture (alpha = strands, tapered tips). Skinned to neck/head/tail bones.
6. **Eyes**: glossy spheres in the sockets (head bone).
7. **Tack** (period Western stock saddle), built as SDF shells conforming to the body field: wool blanket with an
   original woven pattern, skirts, seat/tree with swells, horn and cantle, fenders, wooden box stirrups on
   straps, canvas cinch, saddlebags with flaps, bedroll; bridle straps projected onto the head (crown piece +
   throatlatch, cheek pieces, browband), bit bar + rings, reins sagging from the bit to the horn (weights blend
   head → neck → withers so they follow the neck).
8. **Gaits** (see below) and **actions** keyed on the armature; exported as glTF actions.

## Gaits
Authored as in-place cycles from footfall phase tables. Per frame: trunk motion (bob, pitch, lumbar flexion,
neck nod, head counter-rotation, tail carriage/swing, ears) is analytic; each leg gets a hoof target (stance:
planted, moving back at ground speed, breakover rotating about the toe; swing: cycloid forward with lift) and
joint "style" angles (carpal/hock/fetlock flexion curves), solved by a planar least-squares IK with joint limits.
Stance hooves are exact to < 1 mm except the touchdown frame of the fastest gaits.

| Gait | Beats | Footfalls (phase of contact) | Duty fore/hind | Stride | Cycle | Speed |
|---|---|---|---|---|---|---|
| walk | 4 lateral | LH 0, LF .25, RH .50, RF .75 | .62/.62 | 1.75 m | 1.05 s | 1.67 m/s |
| trot | 2 diagonal | LH+RF 0, RH+LF .50 | .42/.42 | 2.70 m | 0.72 s | 3.75 m/s |
| canter (left lead) | 3 | RH 0, LH+RF .27, LF .50 | .35/.37 | 3.50 m | 0.55 s | 6.36 m/s |
| gallop (left lead, transverse) | 4 | RH 0, LH .10, RF .38, LF .48 | .21/.22 | 6.00 m | 0.47 s | 12.8 m/s |
`canter_r` / `gallop_r` are the mirrored right leads (the controller picks the lead from the turn direction).
`horse_gaits.json` carries stride, cycle, speed, duty, footfalls, beats per gait and every action's length/loop,
so the game sets playback speed = ground speed / authored speed (no foot sliding).

Actions: `idle`, `idle_rest` (hind leg cocked), `graze`, `turn`, `swim` (loops); `head_shake`, `ear_flick`,
`tail_swish`, `skid_stop`, `rear`, `buck`, `jump`, `shy`, `stumble`, `refuse`, `death`, `getup` (one-shots).

## Runtime
- **AnimationTree**: blend tree `StateMachine(loco) → TimeScale → OneShot(action) → out`; loco states crossfade
  in 0.28 s; one-shots fade in/out over 0.18/0.3 s.
- **Body on terrain**: the controller samples the ground under the four hooves each tick → body pitch (front vs
  hind), damped roll, height; plus a lean into turns. **HorseIK** then plants each hoof: the offset between the
  real ground and the animation's ground plane moves the knee/hock with an analytic two-bone solve
  (stance: both ways, swing: lift only), cannon/pastern/hoof keep their animated orientation.
- **Controller**: floating CharacterBody3D (capsule along the body + neck sphere; terrain excluded, ground
  height from the heightmap + a structure raycast). Turning radius `r = 1.2 + 0.12 v²` (× breed handling),
  acceleration per breed; pace by tapping sprint (walk → trot → canter → gallop, hold/keep tapping to stay at a
  gallop, settles to a canter otherwise; stick released = stop, stick back = brake / back up, walk_toggle =
  walk); `ride_auto` (Z / D-pad down) follows the nearest road. Slopes: slower uphill, faster downhill, refuses
  > 40° up / > 48° down. Water: fords (slower) from 0.35 m, swims from 1.45 m (body floats, swim cycle).
  Collisions at speed: > 3.5 m/s into a wall stumbles, > 7 m/s falls and throws the rider. Jump (jump at trot+).
- **Cores**: health/stamina outer bars regenerate from inner cores; gallop drains stamina (~35 s flat out),
  exhausted horses won't gallop; `feed(hay|oats|carrot|apple|tonic)`.
- **Fear**: `Horse.alarm(pos, radius, strength, kind)` (gunfire, explosions) and nodes in group `predator`
  within 25 m; ridden horses rear (low bond may throw the rider), free horses shy and bolt.
- **Bond** levels 1–4 from riding distance, brushing, feeding: 2 = skid stop on brake at a gallop,
  3 = rear on command (jump while standing), higher levels are calmer.
- **Care**: dirt accumulates with distance, mud on wet ground / shallow water, wet in water / rain, sweat from
  galloping; all shown in the coat; `brush()` cleans.
- **Whistle** (H / D-pad up): the player's horse comes (gallop/canter/trot by distance, steers around steep
  ground and water, teleports out of sight if > 160 m or stuck).
- **Hitching**: `hitch(pos)` / `unhitch()`; auto-hitch on dismount within 5 m of a node in group `hitching_post`.
- **Mount/dismount** (F / Y within 2.8 m): side chosen from where the rider stands (or explicit); rider is
  attached at the saddle seat (bone `spine_thorax`), collisions off, `player.on_horse` set,
  `mounted`/`dismounted` signals; dismount checks the side for space/slope/water and falls back to the other.
  Ride camera: orbit behind, recentres when moving without look input, FOV widens with speed.

## API
```gdscript
var h := Horse.spawn(seed, "quarter")     # breeds: mustang morgan quarter thoroughbred appaloosa paint draft
add_child(h); h.global_position = p
h.mount(player, -1.0)    # -1 left (near side), +1 right, 0 = side the rider stands on
h.dismount()             # same side, falls back to the other
h.call_to(player); h.hitch(post_pos); h.unhitch(); h.brush(); h.feed("oats")
Horse.alarm(gun_pos, 40.0, 1.0, "gunfire")
h.info()                 # breed, coat, cores, bond, dirt, fear, speed, gait, state
Horse.player_horse       # the horse spawned beside the player (main.gd)
```

## Running
- Build the model locally: `python3 frontier/tools/animals/horse_gen.py` then `godot --headless --path frontier --import`.
- CI: `.github/workflows/frontier-assets.yml` job `animals` (ubuntu, `pip install bpy==5.0.1`) builds it and
  publishes `animals.zip` to the `frontier-assets` release; `bash frontier/tools/fetch_assets.sh animals`
  unpacks it to `frontier/assets/ext/animals/` (frontier.yml does this before importing).
- Look-dev: `xvfb-run -a godot --path frontier --resolution 960x540 res://scenes/horse_test.tscn -- --out DIR
  [--only rest,front34,head,head34,walk,trot,canter,gallop,coats,actions] [--seed N --breed B --coat C --notack] --oracle`
- Bots: `godot --headless --path frontier --fixed-fps 60 -- --bot ride|gaits [--seconds N] [--ride_to town]`
  (`--bot all` includes both).
- In-world shot: `... -- --shot out.png --at town:bitter_spring --horse 8 [--horse_yaw 90 --horse_anim gallop]`.

## Results (2026-10-05, local: 4 cores, software Vulkan)
Gait oracle on the bare animation (`horse_test.tscn --oracle`; model space, ground moving at the authored speed):
```
GAIT walk    PASS  beats=4  order=LH LF RH RF   slide=2.7 cm/stance
GAIT trot    PASS  beats=2  order=LH+RF LF+RH   slide=3.4 cm/stance
GAIT canter  PASS  beats=3  order=RH LH+RF LF   slide=4.3 cm/stance
GAIT gallop  PASS  beats=4  order=RH LH RF LF   slide=8.8 cm/stance
```
(raw keys only; the residual is the touchdown frame of the fast gaits and breakover). In the world, after foot IK +
foot locking (`--bot gaits`, samples taken after the IK modifier):
```
GAIT walk    PASS  beats=4  order=LH LF RH RF   slide=0.6 cm/stance (max 1.4)
GAIT trot    PASS  beats=2  order=LH+RF LF+RH   slide=0.4 cm/stance (max 1.7)
GAIT canter  PASS  beats=3  order=RH LH+RF LF   slide=0.8 cm/stance (max 3.7)
GAIT gallop  PASS  beats=4  order=RH LH RF LF   slide=0.9 cm/stance (max 5.6)
HORSE API: dismount right side=ok; whistle: arrived in 6.1 s; brush dirt=0.0; mounted right; gunfire fear 0.00 -> 1.01
BOT gaits: PASS
```
`--bot ride --seconds 420` (Bitter Spring -> Mesquite Wells, 2.8 km road, tapping to a gallop, easing to a canter
on low stamina): `ARRIVED 2774 m in 320 s (avg 8.7 m/s), waypoints 349/350, stuck 0, falls 0, stumbles 0`;
in-ride oracles `gallop PASS 1.2 cm/stance (184 stances)`, `canter PASS 4.5 cm/stance`. Look-dev renders take ~4 s
per shot (no world); an in-world 960x540 frame ~2.5 min on llvmpipe.

## Gaps / next
- Anatomy is convincing at gameplay distance and acceptable in close-up, but not reference tier: the head reads a
  little long/narrow from the front and the eyes are bare spheres (no lids/lashes); muscle definition comes from
  smooth primitives + baked curvature only (no sculpted veins/wrinkles, no normal map); the mane is thin from the
  near side. A sculpt pass via displacement from a painted height map would be the next step.
- Hair cards are skinned only (wind/motion flutter in the shader); SpringBoneSimulator3D on mane/tail bones would
  give real secondary motion.
- Gaits are procedural (IK + style curves), not mocap: walk/trot read well; canter/gallop poses are plausible but
  the swing phase is a little stiff; transitions are crossfades (no dedicated transition clips); turning in place
  uses a stepping loop + yaw.
- Lead changes are crossfades between `canter`/`gallop` and their `_r` mirror (no authored flying change).
- Rider: the player stand-in is placed on the seat; no rider animation set (reins, posting, mount/dismount clips).
- Tack is rigid (no cloth on the blanket/fenders, stirrups don't swing); saddlebag inventory is an array API only.
- Fear reacts to `Horse.alarm()` and group `predator`; the gunplay/wildlife sessions need to call/populate them.
- Swimming uses a paddle loop at a fixed float height; no splash VFX or hoof/breath sounds yet (audio session).
- Quest build: same model; LOD2 (2k tris) and hair cut-off distances are the knobs; not profiled on device.
