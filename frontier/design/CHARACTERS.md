# Frontier — human character pipeline

Scripted, reproducible pipeline (no GUI) that turns CC0 MakeHuman data + original procedural garments + CMU motion
capture into period humans and one shared animation library that Godot loads at runtime.

```
tools/characters/fetch_sources.sh   pinned sources -> build/charsrc/{mpfb2,extra-targets,system_assets,cmu-mocap}
tools/characters/generate.py        roster -> assets/characters_out/ (or ext/characters in CI)
   appearance.py   seeded specs (body macros, face/body targets, skin, hair, beard, ordered 1899 outfit)
   build_character.py + mhcore.py   MPFB2 headless (bpy module): body, rig, bodyparts, face shapes, export .glb
   garments.py     procedural garments, hats, beards, belts
   retarget.py + bvh.py             CMU BVH -> game rig -> animations.glb + animations.json
src/actors/character_factory.gd     CharacterFactory.spawn(seed, role) / spawn_id(id)
src/actors/character.gd             FrontierCharacter: play(), set_viseme(), set_expression(), blink(), look_at_point()
src/actors/character_look.gd        gaze SkeletonModifier3D (neck/head/eyes, limits, smoothing)
src/actors/character_materials.gd   swaps glTF materials for shaders/characters/{skin,hair,cloth}.gdshader
src/tests/character_shots.gd        lineup / animation / face close-up renders (scenes/character_shots.tscn)
```

## How to run
Local (cloud session or Mac; Python 3.11 + Godot 4.7.1):
```
bash frontier/tools/characters/run.sh --import            # venv + sources + all characters + animations, reimport
bash frontier/tools/characters/run.sh --only ruth_caddell --no-anims
bash frontier/tools/characters/run.sh --shots /tmp/shots  # also renders lineup / walk / faces
```
`run.sh` creates `frontier/build/charvenv` (`pip install bpy==5.0.1 "numpy<2" pillow` — Blender as a Python module,
no Blender install needed), runs `fetch_sources.sh` (pinned commits; the MakeHuman system assets zip comes from
mirror1.makehuman.net / files2.makehumancommunity.org — when those hosts are blocked, point `FRONTIER_MH_ASSETS` at an
unmodified copy of the CC0 pack), then `generate.py`. A full run (38 characters + 65 clips) takes ~5 min on 4 cores.
Godot must re-import after regeneration (`godot --headless --import`, done by `--import`), otherwise stale imported
copies of the .glb files are used.

Renders: `godot --path frontier --resolution 1280x540 res://scenes/character_shots.tscn -- --out DIR
--ids a,b,c [--clips idle,walk] [--mode lineup|faces|anim|all] [--pose rest] [--yaw 20] [--turn 90] [--zoom 0.6]`
(run under `xvfb-run -a` in the cloud session).

CI: `.github/workflows/frontier-assets.yml` job `characters` (ubuntu, Python 3.11) runs the same scripts on every push
touching `frontier/tools/characters/**` (or `workflow_dispatch` mode `characters` / `all`) and uploads
`characters.zip` (+ `characters.log`) to the `frontier-assets` release. `bash frontier/tools/fetch_assets.sh
characters` downloads it into `frontier/assets/ext/characters/`, which CharacterFactory searches first
(`assets/characters_out/` is the local fallback; both gitignored).

## Rig choice: MPFB `game_engine`, renamed to Godot's SkeletonProfileHumanoid
- 53 deform bones (pelvis, 3 spine, neck, head, clavicles, arms, 3 joints per finger and thumb, legs, ball) map
  one-to-one onto Godot's humanoid profile (Hips, Spine, Chest, UpperChest, Neck, Head, LeftShoulder ... LeftToes,
  LeftThumbMetacarpal/Proximal/Distal, Left{Index,Middle,Ring,Little}{Proximal,Intermediate,Distal}), plus
  `LeftEye`/`RightEye` added at the MakeHuman eye joints (eye meshes weighted 100 % to them) and `Root` at the ground.
  Bone names *are* the profile names, so `BoneMap`/`SkeletonProfileHumanoid` retargeting is the identity and any
  Godot-humanoid animation (or the RetargetModifier3D) works with no mapping file.
- Why not `cmu_mb`: it mirrors the CMU skeleton (LHipJoint, Neck/Neck1, LowerBack, no fingers or eyes) — nice for a
  1:1 copy of CMU data but it doesn't fit the Godot profile and has no fingers for gun handling. CMU retargeting onto
  `game_engine` is clean anyway because retarget.py transfers *world-space* rotation deltas (chain-length
  differences such as Neck+Neck1 -> Neck disappear), after a per-bone rest alignment to the BVH's frame-0 T-pose.
- Weights: MPFB's game_engine weights for the body; MakeHuman bodyparts interpolate them via their mhclo fitting;
  procedural shells copy the weights of the body vertices they were made from; tubes (skirts, coat tails) blend
  pelvis -> thighs -> calves with depth; hats 100 % Head. Limited to 4 influences, normalised.

## What a character .glb contains
`Rig` (Skeleton3D: humanoid bones + `LeftEye`/`RightEye` + garment spring chains `<garment>_c<k>_<i>`) with meshes
`Body` (skin incl. scalp/neck/eyes/corneas + garments, one surface per material, plus the parts of teeth/brows/beard no
face shape moves), `Face` (only what the face shapes move: skin around eyes/mouth/jaw, brows, lashes, teeth, tongue,
beard — the only mesh with blend shapes; deltas under 0.2 mm are dropped so the scalp stays out), `Hair` (MakeHuman
hair or a procedural updo), `Hat` (hideable: `set_hat_visible(false)`), and `LOD1` (~8 k tris) / `LOD2` (~2.5 k
tris): every part joined and decimated, no blend
shapes. CharacterMaterials sets visibility ranges (LOD0 < 16 m < LOD1 < 42 m < LOD2). Vertex colour: skin r cavity
occlusion, g oily T-zone, b stubble mask; cloth r fold occlusion, g wear, b distance to the hem. UV2 = metres for
fabric tiling. Materials are named `skin`, `eyes`, `cornea`, `brows`, `lashes`, `teeth`, `tongue`, `hair`,
`hair_updo`, `beard`, `cloth:<garment>:<fabric>`, `leather:<garment>:leather`; CharacterMaterials builds:
- skin.gdshader: MakeHuman CC0 albedo × tint, SSS, three-octave procedural pore / fine-crease micro-normal (deeper
  with age) fading with distance, cavity AO, shinier T-zone, sun weathering, stubble dots, global `wetness`.
- cloth.gdshader (double-sided, insides darker): Poly Haven CC0 fabric tiled on UV2 and re-tinted, garment detail,
  procedural drape wrinkles in model space, turned-hem crease + running stitch near every hem, wear, dust rising from
  the ground, fold AO, wool sheen, wetness. Seed variants re-roll garment colours from their palettes.
- hair.gdshader: luminance-preserving recolour, alpha scissor + A2C, anisotropic highlight; beards and updos use the
  vertex colour (shell occlusion / hairline fade).
- cornea: additive clear dome over each iris (specular highlight and reflections only) — wet eyes.

Garment construction (garments.py): body-derived shells cut *exactly* along their edges with bmesh bisect (collar
plane under the chin, sleeve and trouser planes perpendicular to the limb, V-neck and armhole planes, coat lapel
opening), then rim thickness; ease grows away from fitted parts; drape passes: under-bust / chest hang (no anatomy
under bodices and shirts; `smooth_chest` tops get a corseted 1899 front: the bust is smoothed, then pushed out to the
convex hull of every vertical column and horizontal slice and feathered into the flanks, allowed to sink into the
deleted skin), coats hang plumb from the chest and shoulder blades, shirts blouse over the belt, trousers break over
shoes or bunch above boot tops, fold displacement along the cloth's own normal at elbows, cuffs, knees and hems; layer
separation keeps every garment outside the ones beneath (aprons clear the skirt's flare); a relax pass removes dents
left by masked drape passes. Skin weights are blurred over the torso and torso cloth below the armpit drops its
upper-arm weight (no creases when the arms move). Hem vertices carry a `keep_edge` group so decimation collapses
them last (straight hems at NPC budgets).
Skirts, frock-coat tails and duster tails carry spring-bone chains: FrontierCharacter builds a SpringBoneSimulator3D
(one setting per chain, stiffness/drag/gravity tuned per garment) with thigh/calf capsule colliders, active within
30 m of the camera. Women's period hair: procedural updos (hair cap swept up from a soft hairline + low chignon,
top-knot, or Gibson-girl pompadour) with a generated strand texture.

Face blend shapes (38): `blink_L/R`, `squint_L/R`, `wide_L/R`, `brow_raise`, `brow_inner_up`, `brow_furrow`,
`jaw_open`, `smile_L/R`, `frown`, `sneer_L/R`, `pucker`, `funnel`, `press`, `cheek_puff`, `look_up_L/R`,
`look_down_L/R` (eyelids follow vertical gaze, driven by CharacterLook), visemes `vis_PP FF TH DD kk CH SS nn RR aa
E I O U` (`vis_sil` = basis). Built from the CC0 ARKit face units + Meta-style visemes
(makehumancommunity/extra-targets), boosted where the autogenerated units are subtle, and transferred to teeth,
tongue, lashes, brows and beard through the mhclo fitting weights. API aliases: `set_viseme("AA"|"E"|"I"|"O"|"U"|
"MBP"|"FV"|"L"|"TH"|"CH"|"SS"|"DD"|"KK"|"RR"|"rest")`, `set_expression("smile"|"frown"|"brow_raise"|"brow_furrow"|
"sneer"|"squint"|"wide"|"jaw_open"|...)`. Auto-blink runs by default.

Lip-sync: FrontierCharacter listens to `Game.audio` (`voice_started`, `viseme`, `voice_finished`). When a line plays
on the character or any ancestor (the Human / Player node MissionDirector.say() passes), its viseme events drive the
mouth (audio names sil PP FF TH DD kk CH SS nn RR aa E ih oh ou -> our visemes) and the line's emotion tag holds an
expression for the line (warm, amused, angry, afraid/scared, sad, tired, tense, dry, shout, whisper, calm). Lines
without viseme timing fall back to a text-driven viseme timeline. `speak(line_id)` plays a line on the character.
Beards: five alpha shells with per-vertex length jitter, dense dark roots to sparse light tips.

## Roster (appearance.py)
36 NPCs from seeds 0..35 over 12 roles — rancher, cowhand, townsman, gentleman, worker, drifter, lawman, elder,
townswoman, lady, ranchwoman, matron — with an 1899 ethnic mix (Anglo, Irish, Hispano, Black, Chinese, Native),
ages 17-80, randomised MakeHuman macros (weight, muscle, height, proportions) and ~60 face/body modelling targets
each, age/sex/ethnicity-matched CC0 skins with tints, hair/eye/brow/lash choices, beards (full, short, chin, mutton
chops, moustache) and stubble. Plus `ruth_caddell` (34, lean, weathered, auburn braid, grey eyes; linen shirt,
leather vest, canvas trousers, tall boots, gun belt, cattleman hat; hero LOD) and `ruth_caddell_duster`.
Garments: shirts (rolled or full sleeves, high band collar), vests (V neck), trousers (tucked into tall boots or over
shoes), boots, waist and gun belts, sack coats, frock coats (coat + tails), dusters (coat + long split tails), women's
bodices with corseted fronts, floor-length skirts, aprons, sashes; hats: cattleman, plainsman, slouch, bowler, flat
cap, straw boater. Tags (`rider`, `ranch`, `townsfolk`, `wealthy`, `labour`, `outlaw`, `law`, `hero`, role, sex) drive
`CharacterFactory.spawn(seed, role)`.

Budgets (tris, LOD0, enforced by the builder): NPCs <= 24 k (face decimated with its blend shapes kept, beard shells
and teeth decimated, the body takes the remaining cut), Ruth <= 39 k (subdivided eyes, 2 K skin). LOD1 ~8 k, LOD2
~2.5 k. Textures: hero skin 2 K; NPC skin 1 K, hair and MakeHuman shoes 512, eyes 512, brows/lashes/teeth/tongue 256.

## Memory (8 GB M1, Quest)
- Textures ship pre-extracted next to each .glb (`<id>_<image>.png/.jpg`, the names Godot's "Extract Textures" uses)
  with `.import` sidecars asking for VRAM compression (`compress/mode=2`: S3TC/BPTC on desktop, ETC2/ASTC for the
  Quest; normal maps flagged), and `<id>.glb.import` turns off Godot's auto LODs and shadow meshes (the generator
  ships LOD1/LOD2). `mhcore.godot_sidecars()` writes them and keeps the uid of an earlier import. Without the
  pre-extracted file Godot re-extracts an uncompressed copy; with a sidecar but no file the scene embeds textures
  (that was the "scene doubled" in the first experiment).
- Blend shapes live on `Face` only, at its minimum vertex count (~4–5 k verts for an NPC incl. 5 beard shells).
- Materials are built once per look and shared by its instances (CharacterMaterials caches by id); seed variants
  re-colour garments through instance uniforms (`cloth.gdshader` `tint_0..7`, a material names its `tint_slot`).
- Spring-bone simulators are built within 30 m of the camera and freed beyond 40 m; the gaze modifier runs within
  30 m.
- `--charmem` report: `godot [--headless] --path frontier res://scenes/character_shots.tscn -- --charmem
  [--ids a,b] [--instances 30] [--out DIR]` prints per-look RSS / static / video deltas and analytic texture,
  mesh, blend-shape and LOD MB, then the per-instance cost, and writes `charmem.json`.
- Measured (software Vulkan, 2026-10-05): per NPC look 6.2 MB video + 1.1 MB CPU (was ~17 + 15); Ruth 13.5 MB video;
  per instance 0.49 MB video + 0.35 MB CPU (1.1 MB RSS). Headless per look 5.6–7.5 MB CPU. Headless town bot:
  characters add ~150 MB peak RSS (16 looks + 28 instances + clips). llvmpipe additionally JIT-compiles every
  pipeline variant on first use (~350 MB once), which a hardware driver doesn't.

## Animation library (retarget.py -> animations.glb, animations.json)
CMU mocap (cgspeed BVH) retargeted onto the canonical rig, 30 fps, in place with root motion on `Root`
(FrontierCharacter sets `root_motion_track = Skeleton:Root`; read `anim.get_root_motion_position()` to drive a body,
or use `clip_info(clip).speed` × `motion_scale()`), `Skeleton3D.motion_scale` adapts hips/root translation to each
body's leg length. Loops are cut at the best-matching cycle (pose + velocity distance) with the residual seam spread
over the clip; locomotion is straightened to a constant-velocity root along model forward. `animations.json`
lists per clip: frames, duration, loop, speed (m/s), root motion, foot contacts (normalised intervals per foot from
toe/heel height + speed), source take.

Clips: idle, idle_shift, idle_wait, idle_crouch; walk, walk_brisk, walk_relaxed, walk_old, walk_wounded, walk_crouch,
sneak, jog, run, sprint, carry_walk; walk/jog/run start and stop; walk_turn_90_L/R, jog_turn_90_L/R,
turn_in_place_L/R; talk_1, talk_2, talk_directions, shrug, wave, handshake; sit_down, sit_idle, stand_up; lean_rail,
lean_wall*; drink, drink_smoke; pistol_draw, pistol_shoot, gun_shoot_2, pistol_aim*, pistol_aim_two_hand*,
rifle_aim*; hit_front*, hit_back*, hit_left*, hit_right*, hit_head*; death_forward, death_back, death_collapse
(reversed get-up), get_up_front, get_up_back; climb_ladder, ladder_up_down, climb_over; jump, jump_forward,
run_jump; pick_up, pick_up_box, push_heavy; revolver_reload**, lever_reload**, holster**, unholster**;
ride_idle**, ride_walk**, ride_trot** (posting), ride_canter**, ride_gallop** (two-point), mount_left**,
dismount_left**. (* = procedural on a mocap base pose; ** = keyframed by code with two-bone IK for hands/feet:
rifle_aim has the support hand on the forend, rein hands, stirrup feet.)

Riding clips: the character origin is the saddle seat point and the hips joint sits 0.09 m above it at x = y = 0
(pelvis at the origin — parent the rider to the seat). Because horse.gd currently puts the rider's origin 0.78 m below
the seat, FrontierCharacter raises its model by `ride_seat_drop` (0.78) while riding; set it to 0 when parenting to the
seat. mount/dismount start/end standing 0.72 m to the horse's left, ground 1.30 m below the seat.

Gameplay driver (character.gd, AnimationTree): `set_locomotion(speed, state)` (state "ride"/"mounted" blends to the
ride blend space by horse speed), `set_aim("pistol"|"rifle")`, `hit(info)`, `die(info)`, `revive()`, plus
`play_action(clip, upper_body)` (one-shots: full body or upper body over locomotion), `reload(kind)`, `holster()`,
`unholster()`.

## Licences
See `frontier/LICENSES.md` ("Characters and animation") and `characters/LICENSES.json`: MakeHuman assets CC0 (MPFB2
GPL code only executed as a tool), extra-targets CC0, CMU mocap free for commercial use with acknowledgement,
everything else original.

## Gaps / next steps
- Garments are offset shells and lofted tubes with procedural drape — no real cloth simulation; only skirts and coat
  tails swing (spring bones). Layered garments can clip in extreme poses (deep crouch, sitting in long coats).
- Updos are a sculpted cap + bun with a strand texture (no hair cards); beards are alpha shells, flat in macro
  close-ups. No eyebrow/eyelash variety beyond the CC0 pack.
- Faces: ARKit units are autogenerated and coarse (no wrinkle maps or corrective shapes); eyes are low-poly MakeHuman
  eyes + an additive cornea (no refraction, no tear line).
- Riding and reload/holster clips are code-keyframed approximations (no props: guns/reins are not in the clips);
  mount/dismount assume a 1.30 m seat height and the left side only. CMU has no swim or ladder-top transitions.
- Quest 3: use LOD1/LOD2 + a cheaper skin shader variant (no SSS) — not done.
