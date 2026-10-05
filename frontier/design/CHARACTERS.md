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
`Rig` (Skeleton3D) with meshes `Body` (skin + garments, one surface per material, decimated 50 % for NPCs), `Head`
(face skin, eyes, brows, lashes, teeth, tongue, beard — the only mesh with blend shapes, so blend-shape memory stays
small), `Hair`, `Hat` (hideable: `set_hat_visible(false)`). Vertex colour: r occlusion, g wear, b stubble mask;
UV2 = metres for fabric tiling. Materials are named `skin`, `eyes`, `brows`, `lashes`, `teeth`, `tongue`, `hair`,
`beard`, `cloth:<garment>:<fabric>`, `leather:<garment>:leather`; CharacterMaterials builds:
- skin.gdshader: MakeHuman CC0 albedo × tint, SSS, procedural pore/fine-wrinkle micro-normal that fades with distance,
  sun weathering (tan, redness, roughness break-up), stubble dots from the mask, global `wetness`.
- cloth.gdshader: Poly Haven CC0 fabric (assets/ext/cloth: denim, linen, wool, canvas, leather) tiled on UV2 and
  re-tinted to the garment colour, wear (lighter fibres at elbows/knees/hems), dust rising from the ground, fold AO,
  wool sheen, wetness. Seed variants re-roll the garment colour from its palette (`spawn(seed)` with seed != 0).
- hair.gdshader: luminance-preserving recolour, alpha scissor + A2C, anisotropic highlight.

Face blend shapes (34): `blink_L/R`, `squint_L/R`, `wide_L/R`, `brow_raise`, `brow_inner_up`, `brow_furrow`,
`jaw_open`, `smile_L/R`, `frown`, `sneer_L/R`, `pucker`, `funnel`, `press`, `cheek_puff`, visemes `vis_PP FF TH DD
kk CH SS nn RR aa E I O U` (`vis_sil` = basis). Built from the CC0 ARKit face units + Meta-style visemes
(makehumancommunity/extra-targets), boosted where the autogenerated units are subtle, and transferred to teeth,
tongue, lashes, brows and beard through the mhclo fitting weights. API aliases: `set_viseme("AA"|"E"|"I"|"O"|"U"|
"MBP"|"FV"|"L"|"TH"|"CH"|"SS"|"DD"|"KK"|"RR"|"rest")`, `set_expression("smile"|"frown"|"brow_raise"|"brow_furrow"|
"sneer"|"squint"|"wide"|"jaw_open"|...)`. Auto-blink runs by default.

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

Budgets (tris, LOD0): NPCs 23-35 k (Head 11-17 k incl. teeth/beard shells, Body 10-15 k after 50 % decimation, hair
1-4 k, hat 1.4-1.8 k); Ruth ~45 k (no decimation, subdivided eyes, 2 K skin). Textures 1 K (NPC) / 2 K (hero).
Godot's importer generates distance LODs for imported .glb files.

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
run_jump; pick_up, pick_up_box, push_heavy. (* = procedural: keyframed by code on a mocap base pose.)

## Licences
See `frontier/LICENSES.md` ("Characters and animation") and `characters/LICENSES.json`: MakeHuman assets CC0 (MPFB2
GPL code only executed as a tool), extra-targets CC0, CMU mocap free for commercial use with acknowledgement,
everything else original.

## Gaps / next steps
- Garments are body-offset shells and lofted tubes: no cloth simulation, folds are procedural displacement; hems
  are snapped but some necklines/armholes stay slightly jagged; layered garments can still clip in extreme poses
  (deep crouch, sitting with long coats/skirts). Skirts/tails are skinned, not simulated — add SpringBone/jiggle or
  Godot physics for skirt and duster tails.
- No period updos/buns (women wear braids, ponytails, loose hair from the CC0 pack); no hair cards for beards (alpha
  shells read well at mid distance, flat in extreme close-ups); no eyebrow/eyelash variety beyond the pack.
- Faces: autogenerated ARKit units are coarse — expressions are boosted but lack wrinkle maps; no corrective
  shapes; lip-sync needs a phoneme -> viseme driver (the API is ready). Eyes are low-poly MakeHuman eyes with a
  glossy material (no separate cornea/refraction).
- Animation: CMU has no real hit reactions, rifle handling, reloads, mounting, swimming or ladder-top transitions;
  those are procedural approximations or missing. Foot IK/slope adaptation and turn-rate control belong in the
  controller (TwoBoneIK3D with the contact metadata). Some takes carry the source performer's quirks.
- Budgets: NPC LOD0 is above the 25 k target when a beard + duster are present; a head-mesh decimation pass that
  respects blend shapes is in `mhcore.decimate` but is not enabled for faces yet.
- Quest 3: use Godot LODs + a cheaper skin shader variant (no SSS) — not done.
