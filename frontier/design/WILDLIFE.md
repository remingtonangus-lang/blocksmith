# Frontier — wildlife models

Generated, rigged and animated animals for `src/actors/animal.gd`, built by the same quadruped pipeline as the
horse (design/HORSES.md). Everything is original and procedural. The bar is QUALITY_BAR.md §7 (wildlife) and §4
(animation).

## Pipeline
`tools/animals/quadruped.py` is the generator engine. It started as horse_gen.py and was generalised without
changing the horse: the engine rebuilds the same horse, and `tools/animals/glb_compare.py` checks this. Old and new
builds have identical positions, normals, UVs, weights and animation data; only the eyes' triangle order differs,
and repeat builds of the same code vary in that way anyway.
`tools/animals/horse_gen.py` is now a thin wrapper around it. Each species is a parameter file in
`tools/animals/species/`:

| File | What it holds |
|---|---|
| `horse.py` | the hand-tuned horse anatomy, gaits (unchanged) |
| `common.py` | shared building blocks: bone template, trunk/neck/head lofts from side-profile key points, legs and feet (`hoof`, `cloven`, `paw`, `plantigrade`), ears/eyes snapped onto the skull, tails, antler/horn tube builder, gait helper + footfall tables (lateral walk, diagonal trot, transverse and rotary gallop, half-bound, pronk), generic actions |
| `mule_deer.py` | buck (antlers hidden for does), walk / trot / transverse gallop / stot |
| `elk.py` | bull (6x6 antlers, hidden for cows), throat mane |
| `pronghorn.py` | pronged black horns, big eyes, slender legs |
| `bison.py` | hump, deep chest, low massive head, beard and cape, short horns, tufted tail |
| `wolf.py` | canid template: deep narrow chest, digitigrade paws with claws, bushy tail, rotary gallop |
| `coyote.py`, `fox.py` | scaled/reshaped from the wolf (fox: long body, short legs, very bushy tail) |
| `cougar.py` | felid: round head, short muzzle, long tail with an upturned tip, big round paws |
| `black_bear.py` | ursid: plantigrade, heavy, short tail; its attack rears into a swipe |
| `raccoon.py` | reshaped from the bear: hunched back, ringed bushy tail (mask in the coat shader) |
| `rabbit.py` | black-tailed jackrabbit (the game's "rabbit"): huge ears, long hind feet, hop + bound |

All species share one bone layout with the horse: spine, 4 neck bones, head, jaw, ears, 6 tail bones and
scapula/humerus/forearm/fcannon/fpastern/fhoof plus femur/tibia/hcannon/hpastern/hhoof per side. That way
HorseVisual, HorseIK (foot IK + foot locking) and HorseGaitOracle work unchanged for every animal. For paws,
"cannon" means the metapodials, "pastern" the toes and "hoof" the pad.

Measurements come from standard adult references. Shoulder height (m): mule deer 1.0, elk 1.5, pronghorn 0.87,
bison 1.8 at the hump, wolf 0.8, coyote 0.58, fox 0.4, cougar 0.7, black bear 0.9, raccoon 0.3, jackrabbit 0.3.
The heights match `Animal.SPECIES` sizes. Each species gets:
- **Body mesh:** a narrow-band SDF evaluation, then marching cubes, then decimation. Hero is 7k–20k triangles
  depending on size, with Body_LOD1 (about 30 %) and Body_LOD2 (about 8 %).
- **Antlers and horns:** separate capped tube meshes on the head bone, with a burr at each antler base.
- **Eyes:** sunk into a socket with upper and lower lids. Each eye carries iris coordinates (the position projected
  onto the eye's outward tangent plane; lateral for prey, turned forward for predators via `eye_fwd`), which
  `shaders/animal_eye.gdshader` paints per species (`AnimalCoats.EYES`):
  - dark brown, nearly all iris, horizontal pupils: deer, elk, pronghorn, bison
  - amber: wolf and coyote; amber with slit pupils: fox
  - gold: cougar
- **Skin data:** skinned weights, and rest-space UVs plus AO/curvature for the coat shader.
- **Gaits** (in-place cycles with stride, speed, duty factor, footfalls, beats and gait type in `<species>_gaits.json`):
  - walk (all species except the rabbit)
  - trot (all except the rabbit)
  - gallop: transverse for cervids/bovids, rotary for canids, felids, bears and raccoons
  - stot (mule deer)
  - hop and bound (rabbit)
  - **Gait fitting** (`fit_gait` in quadruped.py; wildlife only, the horse is untouched). The species files give
    reference strides and duty factors. A planted sole that the leg cannot reach would skate, so the builder:
    1. measures the worst stance IK error;
    2. shifts the fore and hind stance centres (reach offsets, which change neither timing nor speed);
    3. then shortens the stride, keeping the cycle time, until the error is within 2 % of shoulder height.
    It logs `fit <gait> worst stance error A -> B mm` per gait, and the fitted stride and speed go into the json.
    Cycles shorter than 24 frames are keyed between frames, so a 0.27 s fox gallop still has 24 poses.
- **Idles:** idle, graze (grazers) or sniff (carnivores), alert (head high, ears pricked, fore-foot stamp),
  look (scanning left/right).
- **One-shots:** flee_start (crouch and spring), attack (predators lunge with jaws open; the bear rears and
  swipes), death (buckle and roll onto the side), carcass (the lying pose, held).
- **Gaits json extras:** `anchors` (poll, nose, tail, eye, belly/back/knee/hock heights) for the coat shader and
  hit zones; `run_gait`, `flee_gait` and `walk_gait`; `variants` (does and cows: hide the antlers, scale down).

Build: `python3 frontier/tools/animals/quadruped.py --species all|mule_deer,elk,... [--quick] [--preview]`,
output to `frontier/assets/animals_out/` (gitignored). The CI job `animals` in frontier-assets.yml runs
`--species all` and publishes `animals.zip`. Fetch it with `bash frontier/tools/fetch_assets.sh animals`, which
unpacks to `assets/ext/animals/`.

## Runtime (src/actors/animal.gd)
- **Model loading:** `HorseVisual.model_path_for(species)` loads the model if present; otherwise the old stand-in
  body is used.
- **Coat:** `AnimalCoats.roll(species, seed)` sets coat colours with per-animal jitter, using
  `shaders/animal_coat.gdshader`. The shader paints:
  - countershading and a dorsal saddle
  - agouti grizzle
  - leg points
  - rump patch and tail tip
  - pronghorn throat bands
  - raccoon mask and tail rings
  - bison cape
  - nose pad and muzzle ring
  - mud, blood, wet, and a skinned-carcass state
- **Animation from ecology state and speed:**
  - calm: idle / graze / look, chosen at random every 4–10 s
  - ALERT: alert
  - moving: walk, then trot, then run gait, chosen by ground speed against the authored gait speeds; playback
    speed is ground speed / authored speed
  - fleeing at mid speed: flee gait (mule deer stot)
  - ATTACK: plays `attack` and calls `Horse.alarm()`
  - death: `dead` (the death clip, held)
  - skinning: carcass pose plus the shader's `skinned`
- **LOD:** foot IK runs only within about 35 m (scaled by body size); the AnimationTree stops beyond
  60 m + 150 m × size, so far animals hold a pose; mesh LODs switch by distance, scaled by size.
- **Hit zones ride on bones:**
  - chest: a box on `body`, sized from the trunk anchors
  - head: a sphere on `head`
  - legs: capsules on the forearm and tibia bones
  - They follow grazing heads and the death roll. The body collider now turns with the heading.
- **Predators:** wolves, coyotes, foxes, cougars and bears join group `predator`; horses already fear that group
  within 25 m.

## Oracles
- `wildlife_test.tscn`: runs every species' gait animations through `HorseGaitOracle.analyse_animation` and prints
  `GAIT <species>/<gait>` lines and `WILDLIFE ORACLE PASS|FAIL`.
  - Each gait is checked against the reference sequence for its *type* (`REF_TYPES`: walk_lateral, trot_diagonal,
    canter, gallop_transverse, gallop_rotary, bound, pronk).
  - Contact thresholds scale with body size.
- `--bot hunt`: also runs the per-species gait oracle and fails on a mismatch; it skips this when no models were
  fetched.

## Look-dev
`xvfb-run -a godot --path frontier --resolution 1280x540 res://scenes/wildlife_test.tscn -- --out DIR`
`[--only lineup,closeups,strips,actions] [--species a,b]`. It renders a line-up of all species, a 3/4 view and a
head close-up per species, gait strips and action poses.

## Gaps
- No fur geometry (shells or cards). Fur is shading only: grizzle, streaks and rim. Up close the wolf, bear and
  bison read as smooth.
- The wild turkey (a bird) still uses the stand-in.
- Antlers and horns are tube-built: plausible silhouettes, but with no burr texture or palmation detail.
- Gaits and actions are procedural (planar IK + style curves).
  - After fitting, the worst stance error is about 2 % of shoulder height on the worst frame; in-game foot
    locking hides it.
  - Fitted run speeds are below real sprint speeds (wolf about 7.7 m/s, pronghorn about 9 m/s); faster animals
    play the gait up to 1.8x.
  - Turning is yaw plus the gait. Wildlife has no dedicated turn-on-the-spot clips.
- Faces are simple: no lids, nostril detail or teeth. The attack's jaw opens on a solid mouth.
