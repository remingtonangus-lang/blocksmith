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
- **Turn in place:** `turn_l` / `turn_r` loops (shared `anim_turn_dir` in quadruped.py, also built for the horse).
  The forelegs step across toward the turn and the hind legs away from it, in walk order, while the neck and head
  bend into the turn. The game yaws the body; `animal.gd` plays them when an animal turns faster than 0.6 rad/s
  below 0.15 m/s.
- **Face:**
  - A mouth slit at the lip line (60 % down the muzzle, from the mouth corner to the nose) separates the lips:
    - the lip band is decimated more gently;
    - faces that still join the lips are deleted, at LOD0 and in LOD1 (which the fur shells reuse);
    - a weights fix (`mouth_weights`) puts everything below the slit on the jaw and everything above it on the
      head.
    So the attack opens a real mouth.
  - Predators (wolf, coyote, fox, cougar, bear, raccoon) get upper and lower canines and incisors, and a tongue.
  - Ungulates get nostril pits.
  - Lids now have an inner canthus; the coat shader paints dark lid rims, a dark lip line and a red mouth
    interior.
- **One-shots:** flee_start (crouch and spring), attack (predators lunge with jaws open; the bear rears and
  swipes), death (buckle and roll onto the side), carcass (the lying pose, held).
- **Gaits json extras:** `anchors` (poll, nose, tail, eye, belly/back/knee/hock heights) for the coat shader and
  hit zones; `run_gait`, `flee_gait` and `walk_gait`; `variants` (does and cows: hide the antlers, scale down).

Build: `python3 frontier/tools/animals/quadruped.py --species all|mule_deer,elk,... [--quick] [--preview]`,
output to `frontier/assets/animals_out/` (gitignored). The CI job `animals` in frontier-assets.yml runs
`--species all` and publishes `animals.zip`. Fetch it with `bash frontier/tools/fetch_assets.sh animals`, which
unpacks to `assets/ext/animals/`.

## Birds
Four species bring the roster to 15: wild turkey, sage grouse, red-tailed hawk and crow.
- **Generator:** `tools/animals/bird.py`, built on the quadruped engine.
  - The body, head, beak, legs and toes are SDF; turkeys add a snood, wattle and breast beard.
  - Wings and tail are feather cards skinned to wing1/2/3 and tail_1.
  - An FK rig drives the clips: idle, walk (with the head-bob), peck, alert, flap, glide, soar, dive, fall
    (loops) and takeoff, land, death (one-shots).
  - Output: `<species>.glb` + `_gaits.json` with `"kind": "bird"`. The CI animals job builds them.
- **Shaders:** `shaders/bird_body.gdshader` paints countershading, a breast band, the head (the turkey's bare
  blue-and-red head), beak, legs, mottling, barring and iridescence. `shaders/bird_feather.gdshader` cuts the
  feather outlines with alpha:
  - scalloped trailing edges and splayed primaries (hawk, crow)
  - the grouse's spiky tail
  - pale undersides, bars, and the hawk's red tail with its dark band
  Colours are in `BirdLooks`.
- **Behaviour** (`src/actors/bird.gd`, class `Bird`): a cheap kinematic flight model with speed, heading
  (turn-rate limit), climb and bank; no physics body.
  - Turkeys run first and flush when pressed; grouse flush; both glide down 60–200 m away.
  - Crows forage in flocks and lift off at gunshots (`Game.noise`); they circle and land.
  - The hawk soars in 45 m circles 40–75 m up, and stoops on rabbits (or practice stoops), then climbs back.
  - A shot bird tumbles down and can be plucked for meat and feathers.
  - `wildlife.gd` keeps four flocks plus one hawk around the player.
- **Oracle:** `--bot birds` (see Results).

## Hunting
- **Tracks** (`src/systems/tracks.gd`): a pool of 320 ground decals (80 on quest) with painted textures.
  - Animals near the player leave prints along their path: cloven, paw, plantigrade, rabbit, bird.
  - A wounded animal drips blood (denser for worse wounds; a chest or head hit counts double) wherever it goes,
    so the trail leads to it; a pool marks where it dies.
  - Marks fade over about 10 game-minutes.
- **Skinning** (`SkinningTask`): Ruth kneels (crouch activity plus the reaching pick-up clip) for 3.2 s, held via
  `player.busy`. Then the carcass takes its lying pose and the skinned shader state, and the pelt and meat go
  into the satchel.
- **Carcass on the horse:** with the horse within 5 m, small and medium carcasses (deer, pronghorn, canids,
  cougar, raccoon, rabbit) are laid over its back behind the saddle, across the horse.
  - The weight (meat × 22 kg + 10 kg per metre of body; 47 kg for a pronghorn) slows the horse and drains its
    stamina faster.
  - "Take down" at the horse puts it back on the ground to skin.

## Ecology
- **Activity:** animals follow their hours (day, night, crepuscular) and bed down outside them. Herd members
  drift back to the leader first; predators rarely start a hunt while resting.
- **Oracle:** `--bot ecology` runs two in-game days on a compressed clock (the sky 10× faster, the engine 3×,
  about 3 real minutes) around a still observer. It measures population, predation, herd cohesion and activity
  by hour (see Results).

## Fur (shells)
`shaders/animal_fur_shell.gdshader`, set up by `HorseVisual._setup_fur()` for the wolf, coyote, fox, cougar,
black bear, bison, raccoon and the elk's neck mane (`AnimalCoats.FUR`: length, strand density, neck ruff, tail):
- **How it draws:** one extra skinned instance of the Body_LOD1 mesh ("FurShells", no shadow casting) with a
  `next_pass` chain of N shells.
  - Each shell pushes the skin out along the normal by `shell_h` × fur length, with a little droop, and keeps
    only the strands that reach that height, so tapered tufts build up.
  - Fur length per region comes from `fur_region()` in `shaders/inc/animal_coat.gdshaderinc`, which the skin
    shares:
    - bare: nose, lips, eye rims, hooves
    - short: face, ears, lower legs
    - long: tail, neck ruff, bison cape and head
  - Colour is the coat colour at that rest point, evaluated per vertex, darker at the roots.
  - The LOD0 skin under the shells is matte (`under_fur`), so glossy skin does not flash through the gaps.
- **Budget:**
  - Shells exist only within the LOD0 range (about 23 m × body size) and thin out over its last 40 %, so the
    switch to the bare LOD1 does not pop.
  - Shell counts per quality preset (`fur_shells`): low 4, medium 6, high 8, ultra 12, quest 0. `--fur_shells N`
    overrides it.
- **Cost:** `wildlife_test --only furbench` renders four animals 3–6 m from the camera with shells on and off and
  prints GPU time, primitives and draw calls (see Results).

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

- `wildlife_test --only turncheck`: over `turn_l` the head must swing left and the stepping forefeet must
  travel left while the hind feet travel right (mirrored for `turn_r`). It covers every species and the horse,
  printing `TURN <species>/<clip>` lines; a wrong direction fails the run.

## Look-dev
`xvfb-run -a godot --path frontier --resolution 1280x540 res://scenes/wildlife_test.tscn -- --out DIR`
`[--only lineup,closeups,strips,actions,fur,furbench,turncheck] [--species a,b] [--local_animals]`.
- It renders a line-up of all species, a 3/4 view, a head close-up and (for predators) an open-jaw attack close-up
  per species, gait strips, action poses, and fur on/off close-ups.
- `--local_animals` makes the local `assets/animals_out` build win over a fetched `assets/ext/animals`.

## Results (2026-10-05, local: 4 shared cores, software Vulkan)
- **Oracles:**
  - `WILDLIFE ORACLE PASS`: 33 gaits across 11 species.
  - 24 `TURN` checks pass (every species and the horse, left and right).
  - `--bot hunt` PASS.
- **Fur cost** (`--only furbench` at 640×360, high preset with 8 shells; four animals 3–6 m from the camera; GPU
  time is the minimum over 20 frames on llvmpipe, so only the ratio means anything):

  | Species | GPU time | Primitives | Draws |
  |---|---|---|---|
  | wolf | ×1.90 | 38k → 164k | 46 → 78 |
  | fox | ×1.83 | 11k → 53k | 46 → 70 |
  | black bear | ×1.77 | 55k → 215k | 46 → 78 |
  | bison | ×2.11 | 101k → 309k | 31 → 63 |

  That is the worst case, with fur filling the screen. Shells exist only within LOD0 range (about 12 m for a
  wolf), and the quest preset has none.

Round 4 (birds, hunting, ecology):
- **`--bot birds` PASS:**
  - all 18 ground birds on the ground before the shot
  - after one gunshot: crows 8/8, turkeys 5/5 and grouse 5/5 airborne
  - landed again within 14 s
  - hawk soaring at 55–58 m; one dive, climbing back to soaring
  - a turkey shot in the air falls and is plucked
  - the flight update costs 8 µs per bird per tick
- **`--bot hunt` PASS:**
  - clean kill gives pelt quality 3; skinning takes 3.2 s with Ruth held
  - a walking deer leaves 37 prints in 10 s
  - a wounded deer fleeing 150 m leaves a blood trail ending 0.3 m from it
  - pronghorn carcass on the horse (47 kg), unloaded again
- **`--bot ecology` PASS** (two compressed days):
  - population 26 / 28.7 / 30 (min / mean / max); CV 0.06; day 1 mean 28.1, day 2 mean 29.2
  - 10 predator chases and 8 kills (wolf 7, coyote 1); 17 hawk dives
  - herd cohesion 0.85
  - share of animals moving, in their active hours vs outside them:

  | Species type | Active | Inactive | Ratio |
  |---|---|---|---|
  | day | 0.70 | 0.03 | 23.6 |
  | night | 0.66 | 0.24 | 2.75 |
  | crepuscular | 0.47 | 0.04 | 11.0 |

## Gaps
- Fur is shells only, with no fins or cards:
  - At grazing angles in close-ups the layers can read as steps.
  - The strands are noise tufts, not individual hairs.
  - The mane and tail hair cards stay on the horse.
- The wild turkey (a bird) still uses the stand-in.
- Antlers and horns are tube-built: plausible silhouettes, but with no burr texture or palmation detail.
- Gaits and actions are procedural (planar IK + style curves).
  - After fitting, the worst stance error is about 2 % of shoulder height on the worst frame; in-game foot
    locking hides it.
  - Fitted run speeds are below real sprint speeds (wolf about 7.7 m/s, pronghorn about 9 m/s); faster animals
    play the gait up to 1.8x.
  - Turning while moving is yaw plus the gait; only standing turns have clips.
- Faces are still simple:
  - At rest the mouth slit reads as a pale seam along the muzzle.
  - A few thin slivers still stretch across the open mouth.
  - There is no gum or palate geometry, only the coat's red tint and a tongue.
  - The bison's head is a smooth blob.
