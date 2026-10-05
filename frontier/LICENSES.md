# Frontier — asset and dependency licences

Every asset in the shipped game is listed here with its source and licence. Rule: original work, CC0/public
domain, or a permissive open licence recorded below. No assets from other games, ever.

## Engine and code
| Item | Licence | Source |
|---|---|---|
| Godot Engine 4.7.1 (+ export templates) | MIT | https://godotengine.org |
| All Frontier code, shaders, scenes (frontier/) | Original work, same licence as this repository | this repo |
| Blender 5.0.1 as a Python module (`bpy`), build-time tool only (not shipped; its output is ours) | GPL-2.0-or-later | https://pypi.org/project/bpy/ |
| NumPy, SciPy, scikit-image, Pillow (build-time tools) | BSD / HPND | https://pypi.org |

## Generated in-house (original)
| Item | How |
|---|---|
| World terrain, rivers, roads, towns layout | `frontier/tools/worldgen.py` (procedural, seed 1899) |
| Buildings, props, vegetation meshes | Procedural generators in `frontier/src/` |
| Horse: mesh, rig, skin weights, gaits/actions, mane/tail hair cards + strand texture, eyes, saddle/tack, blanket and leather textures | `frontier/tools/animals/horse_gen.py` (signed-distance anatomy, Blender 5 `bpy` as a build tool, scikit-image marching cubes); no external data or references bundled |
| Horse coats and markings, hair shading | `frontier/shaders/horse_coat.gdshader`, `horse_hair.gdshader` (procedural) |
| Sky, clouds, weather, water shaders | Original shaders |
| Story, characters, dialogue, place names | Original writing (`frontier/design/`) |

## Third-party CC0 assets
Fetched by `.github/workflows/frontier-assets.yml` from `frontier/assets/manifest.json`; the per-asset list with
source URLs and authors ships as `assets/ext/LICENSES.json` and is mirrored below when assets are added.

| Asset (dest) | Source | Licence | Author |
|---|---|---|---|
| build/adobe | https://polyhaven.com/a/excavated_soil_wall | CC0 1.0 | Amal Kumar |
| build/adobe_stone | https://polyhaven.com/a/red_sandstone_wall | CC0 1.0 | Amal Kumar |
| build/brick | https://polyhaven.com/a/red_brick | CC0 1.0 | Rob Tuytel |
| build/carpet | https://polyhaven.com/a/dirty_carpet | CC0 1.0 | Rohit Seervi |
| build/corrugated | https://polyhaven.com/a/corrugated_iron_02 | CC0 1.0 | Jenelle van Heerden, Sergej Majboroda |
| build/dark_planks | https://polyhaven.com/a/dark_planks | CC0 1.0 | Rob Tuytel |
| build/fine_wood | https://polyhaven.com/a/fine_grained_wood | CC0 1.0 | Rob Tuytel |
| build/floor | https://polyhaven.com/a/dark_wooden_planks | CC0 1.0 | Amal Kumar |
| build/log_wall | https://polyhaven.com/a/beam_wall_01 | CC0 1.0 | Rob Tuytel |
| build/painted_planks_blue | https://polyhaven.com/a/blue_painted_planks | CC0 1.0 | Rob Tuytel |
| build/painted_planks_green | https://polyhaven.com/a/green_rough_planks | CC0 1.0 | Rob Tuytel |
| build/painted_planks_white | https://polyhaven.com/a/distressed_painted_planks | CC0 1.0 | Rob Tuytel |
| build/planks | https://polyhaven.com/a/weathered_planks | CC0 1.0 | Dario Barresi, Dimitrios Savva |
| build/planks_brown | https://polyhaven.com/a/weathered_brown_planks | CC0 1.0 | Dimitrios Savva, Rico Cilliers |
| build/planks_raw | https://polyhaven.com/a/brown_planks_03 | CC0 1.0 | Rob Tuytel |
| build/plaster | https://polyhaven.com/a/plastered_wall_02 | CC0 1.0 | Charlotte Baglioni |
| build/roof_planks | https://polyhaven.com/a/roof_planks | CC0 1.0 | Rob Tuytel |
| build/roof_shingles | https://ambientcg.com/view?id=WoodSiding013 | CC0 1.0 | ambientCG |
| build/rusty_metal | https://polyhaven.com/a/rusty_metal_02 | CC0 1.0 | Rob Tuytel |
| build/siding | https://polyhaven.com/a/weathered_plank_siding | CC0 1.0 | Dimitrios Savva |
| build/thatch | https://polyhaven.com/a/thatch_roof_angled | CC0 1.0 | Rob Tuytel, Dimitrios Savva |
| build/timber | https://polyhaven.com/a/weathered_peeling_timber | CC0 1.0 | Dimitrios Savva |
| build/wallpaper | https://polyhaven.com/a/decrepit_wallpaper | CC0 1.0 | Rob Tuytel |
| cloth/canvas | https://polyhaven.com/a/hessian_230 | CC0 1.0 | colormass, Rico Cilliers |
| cloth/denim | https://polyhaven.com/a/denim_fabric | CC0 1.0 | Rob Tuytel |
| cloth/leather | https://polyhaven.com/a/brown_leather | CC0 1.0 | Rob Tuytel |
| cloth/linen | https://polyhaven.com/a/rough_linen | CC0 1.0 | colormass, Rico Cilliers |
| cloth/wool | https://polyhaven.com/a/poly_wool_herringbone | CC0 1.0 | colormass, Rico Cilliers |
| nature/bark_cottonwood | https://polyhaven.com/a/bark_willow | CC0 1.0 | Dario Barresi, Dimitrios Savva |
| nature/bark_debris_01 | https://polyhaven.com/a/bark_debris_01 | CC0 1.0 | Greg Zaal, Jenelle van Heerden |
| nature/bark_pine | https://polyhaven.com/a/bark_brown_02 | CC0 1.0 | Rob Tuytel |
| nature/boulder_01 | https://polyhaven.com/a/boulder_01 | CC0 1.0 | Rico Cilliers |
| nature/celandine_01 | https://polyhaven.com/a/celandine_01 | CC0 1.0 | Rob Tuytel, Rico Cilliers |
| nature/dandelion_01 | https://polyhaven.com/a/dandelion_01 | CC0 1.0 | Rob Tuytel, Rico Cilliers |
| nature/dead_tree_trunk | https://polyhaven.com/a/dead_tree_trunk | CC0 1.0 | Rob Tuytel |
| nature/dead_tree_trunk_02 | https://polyhaven.com/a/dead_tree_trunk_02 | CC0 1.0 | Jenelle van Heerden, Rico Cilliers |
| nature/dry_branches_medium_01 | https://polyhaven.com/a/dry_branches_medium_01 | CC0 1.0 | Rico Cilliers |
| nature/fern_02 | https://polyhaven.com/a/fern_02 | CC0 1.0 | Rob Tuytel, Rico Cilliers |
| nature/fir_sapling | https://polyhaven.com/a/fir_sapling | CC0 1.0 | Rob Tuytel, Rico Cilliers |
| nature/fir_sapling_medium | https://polyhaven.com/a/fir_sapling_medium | CC0 1.0 | Rob Tuytel, Rico Cilliers |
| nature/fir_tree_01 | https://polyhaven.com/a/fir_tree_01 | CC0 1.0 | Rob Tuytel, Rico Cilliers |
| nature/grass_medium_01 | https://polyhaven.com/a/grass_medium_01 | CC0 1.0 | Rob Tuytel, Rico Cilliers |
| nature/grass_medium_02 | https://polyhaven.com/a/grass_medium_02 | CC0 1.0 | Rico Cilliers |
| nature/moss_01 | https://polyhaven.com/a/moss_01 | CC0 1.0 | Rob Tuytel |
| nature/namaqualand_boulder_02 | https://polyhaven.com/a/namaqualand_boulder_02 | CC0 1.0 | Greg Zaal, Rico Cilliers |
| nature/namaqualand_boulder_03 | https://polyhaven.com/a/namaqualand_boulder_03 | CC0 1.0 | Jenelle van Heerden, Dario Barresi |
| nature/namaqualand_boulder_05 | https://polyhaven.com/a/namaqualand_boulder_05 | CC0 1.0 | Jenelle van Heerden, Dario Barresi |
| nature/namaqualand_rocks_01 | https://polyhaven.com/a/namaqualand_rocks_01 | CC0 1.0 | Greg Zaal, Jenelle van Heerden |
| nature/nettle_plant | https://polyhaven.com/a/nettle_plant | CC0 1.0 | Rob Tuytel, Rico Cilliers |
| nature/pine_roots | https://polyhaven.com/a/pine_roots | CC0 1.0 | Rob Tuytel |
| nature/pine_sapling_medium | https://polyhaven.com/a/pine_sapling_medium | CC0 1.0 | Rob Tuytel, Rico Cilliers |
| nature/pine_tree_01 | https://polyhaven.com/a/pine_tree_01 | CC0 1.0 | Rob Tuytel, Rico Cilliers |
| nature/rock_07 | https://polyhaven.com/a/rock_07 | CC0 1.0 | Jenelle van Heerden |
| nature/rock_09 | https://polyhaven.com/a/rock_09 | CC0 1.0 | Jenelle van Heerden |
| nature/rock_face_01 | https://polyhaven.com/a/rock_face_01 | CC0 1.0 | Dario Barresi |
| nature/rock_face_02 | https://polyhaven.com/a/rock_face_02 | CC0 1.0 | Dario Barresi, Rico Cilliers |
| nature/rock_moss_set_01 | https://polyhaven.com/a/rock_moss_set_01 | CC0 1.0 | Kless Gyzen |
| nature/root_cluster_01 | https://polyhaven.com/a/root_cluster_01 | CC0 1.0 | Jenelle van Heerden, Rico Cilliers |
| nature/sand_rocks_small_01 | https://polyhaven.com/a/sand_rocks_small_01 | CC0 1.0 | Rob Tuytel, Rico Cilliers |
| nature/searsia_lucida | https://polyhaven.com/a/searsia_lucida | CC0 1.0 | James Ray Cock, Jenelle van Heerden |
| nature/shrub_01 | https://polyhaven.com/a/shrub_01 | CC0 1.0 | Rico Cilliers |
| nature/shrub_02 | https://polyhaven.com/a/shrub_02 | CC0 1.0 | Rico Cilliers |
| nature/shrub_03 | https://polyhaven.com/a/shrub_03 | CC0 1.0 | Rico Cilliers |
| nature/shrub_04 | https://polyhaven.com/a/shrub_04 | CC0 1.0 | Rico Cilliers |
| nature/tree_small_02 | https://polyhaven.com/a/tree_small_02 | CC0 1.0 | Rico Cilliers |
| nature/tree_stump_01 | https://polyhaven.com/a/tree_stump_01 | CC0 1.0 | Rob Tuytel |
| nature/tree_stump_02 | https://polyhaven.com/a/tree_stump_02 | CC0 1.0 | Rob Tuytel |
| nature/wild_rooibos_bush | https://polyhaven.com/a/wild_rooibos_bush | CC0 1.0 | James Ray Cock, Jenelle van Heerden |
| props/BarberShopChair_01 | https://polyhaven.com/a/BarberShopChair_01 | CC0 1.0 | Fernando Quinn |
| props/Barrel_01 | https://polyhaven.com/a/Barrel_01 | CC0 1.0 | Jorge Camacho |
| props/CashRegister_01 | https://polyhaven.com/a/CashRegister_01 | CC0 1.0 | Joe Seabuhr |
| props/Chandelier_02 | https://polyhaven.com/a/Chandelier_02 | CC0 1.0 | Kirill Sannikov |
| props/ClassicNightstand_01 | https://polyhaven.com/a/ClassicNightstand_01 | CC0 1.0 | Kirill Sannikov |
| props/Lantern_01 | https://polyhaven.com/a/Lantern_01 | CC0 1.0 | Rajil Jose Macatangay |
| props/Rockingchair_01 | https://polyhaven.com/a/Rockingchair_01 | CC0 1.0 | Jorge Camacho |
| props/WoodenChair_01 | https://polyhaven.com/a/WoodenChair_01 | CC0 1.0 | Jake Mobley |
| props/WoodenTable_01 | https://polyhaven.com/a/WoodenTable_01 | CC0 1.0 | Ethan Place |
| props/WoodenTable_02 | https://polyhaven.com/a/WoodenTable_02 | CC0 1.0 | Fran Calvente |
| props/WoodenTable_03 | https://polyhaven.com/a/WoodenTable_03 | CC0 1.0 | Gabriel Radić |
| props/barrel_03 | https://polyhaven.com/a/barrel_03 | CC0 1.0 | Serhii Khromov |
| props/brass_candleholders | https://polyhaven.com/a/brass_candleholders | CC0 1.0 | Tina |
| props/bull_head | https://polyhaven.com/a/bull_head | CC0 1.0 | Tina |
| props/folding_wooden_stool | https://polyhaven.com/a/folding_wooden_stool | CC0 1.0 | Ulan Cabanilla |
| props/gate_latch_01 | https://polyhaven.com/a/gate_latch_01 | CC0 1.0 | Desktoy |
| props/hanging_picture_frame_01 | https://polyhaven.com/a/hanging_picture_frame_01 | CC0 1.0 | James Ray Cock |
| props/hatchet | https://polyhaven.com/a/hatchet | CC0 1.0 | James Ray Cock, Ulan Cabanilla |
| props/jug_01 | https://polyhaven.com/a/jug_01 | CC0 1.0 | Kuutti Siitonen |
| props/ladder_sectioned_01 | https://polyhaven.com/a/ladder_sectioned_01 | CC0 1.0 | MP |
| props/lantern_chandelier_01 | https://polyhaven.com/a/lantern_chandelier_01 | CC0 1.0 | Kirill Sannikov |
| props/mantel_clock_01 | https://polyhaven.com/a/mantel_clock_01 | CC0 1.0 | Yann Kervran, Rico Cilliers |
| props/old_bed_frame | https://polyhaven.com/a/old_bed_frame | CC0 1.0 | Luca B |
| props/painted_wooden_cabinet | https://polyhaven.com/a/painted_wooden_cabinet | CC0 1.0 | Kirill Sannikov |
| props/painted_wooden_chair_01 | https://polyhaven.com/a/painted_wooden_chair_01 | CC0 1.0 | Kuutti Siitonen |
| props/painted_wooden_table | https://polyhaven.com/a/painted_wooden_table | CC0 1.0 | Kirill Sannikov |
| props/pocket_watch | https://polyhaven.com/a/pocket_watch | CC0 1.0 | PierreB3D |
| props/pot_enamel_01 | https://polyhaven.com/a/pot_enamel_01 | CC0 1.0 | Kuutti Siitonen |
| props/round_wooden_table_01 | https://polyhaven.com/a/round_wooden_table_01 | CC0 1.0 | Ulan Cabanilla |
| props/rusted_spade_01 | https://polyhaven.com/a/rusted_spade_01 | CC0 1.0 | Blemonade |
| props/spinning_wheel_01 | https://polyhaven.com/a/spinning_wheel_01 | CC0 1.0 | Sofia Pahaoja |
| props/stone_fire_pit | https://polyhaven.com/a/stone_fire_pit | CC0 1.0 | Sebastian Platen |
| props/treasure_chest | https://polyhaven.com/a/treasure_chest | CC0 1.0 | Rico Cilliers |
| props/vintage_binocular | https://polyhaven.com/a/vintage_binocular | CC0 1.0 | Luke |
| props/vintage_cabinet_01 | https://polyhaven.com/a/vintage_cabinet_01 | CC0 1.0 | Rico Cilliers |
| props/vintage_grandfather_clock_01 | https://polyhaven.com/a/vintage_grandfather_clock_01 | CC0 1.0 | Yann Kervran, James Ray Cock |
| props/vintage_oil_lamp | https://polyhaven.com/a/vintage_oil_lamp | CC0 1.0 | Monsta3D |
| props/vintage_suitcase | https://polyhaven.com/a/vintage_suitcase | CC0 1.0 | Maximilian Schuster |
| props/wicker_basket_01 | https://polyhaven.com/a/wicker_basket_01 | CC0 1.0 | Kuutti Siitonen |
| props/wine_barrel_01 | https://polyhaven.com/a/wine_barrel_01 | CC0 1.0 | James Ray Cock |
| props/wine_bottles_01 | https://polyhaven.com/a/wine_bottles_01 | CC0 1.0 | Rico Cilliers, Jurita Burger |
| props/wooden_axe | https://polyhaven.com/a/wooden_axe | CC0 1.0 | Ulan Cabanilla |
| props/wooden_barrels_01 | https://polyhaven.com/a/wooden_barrels_01 | CC0 1.0 | James Ray Cock |
| props/wooden_bookshelf_worn | https://polyhaven.com/a/wooden_bookshelf_worn | CC0 1.0 | Ulan Cabanilla |
| props/wooden_bowl_01 | https://polyhaven.com/a/wooden_bowl_01 | CC0 1.0 | Oliver Harries |
| props/wooden_bucket_01 | https://polyhaven.com/a/wooden_bucket_01 | CC0 1.0 | James Ray Cock |
| props/wooden_bucket_02 | https://polyhaven.com/a/wooden_bucket_02 | CC0 1.0 | James Ray Cock |
| props/wooden_candlestick | https://polyhaven.com/a/wooden_candlestick | CC0 1.0 | Josh Dean |
| props/wooden_crate_01 | https://polyhaven.com/a/wooden_crate_01 | CC0 1.0 | James Ray Cock |
| props/wooden_crate_02 | https://polyhaven.com/a/wooden_crate_02 | CC0 1.0 | James Ray Cock, Jurita Burger |
| props/wooden_display_shelves_01 | https://polyhaven.com/a/wooden_display_shelves_01 | CC0 1.0 | James Ray Cock |
| props/wooden_handle_saber | https://polyhaven.com/a/wooden_handle_saber | CC0 1.0 | Ulan Cabanilla |
| props/wooden_ladder | https://polyhaven.com/a/wooden_ladder | CC0 1.0 | Miroslav Turura |
| props/wooden_lantern_01 | https://polyhaven.com/a/wooden_lantern_01 | CC0 1.0 | James Ray Cock |
| props/wooden_military_crate | https://polyhaven.com/a/wooden_military_crate | CC0 1.0 | Prabhjinder Singh |
| props/wooden_picnic_table | https://polyhaven.com/a/wooden_picnic_table | CC0 1.0 | Ulan Cabanilla |
| props/wooden_stool_01 | https://polyhaven.com/a/wooden_stool_01 | CC0 1.0 | Kuutti Siitonen |
| props/wooden_stool_02 | https://polyhaven.com/a/wooden_stool_02 | CC0 1.0 | Kuutti Siitonen |
| terrain/desert | https://polyhaven.com/a/gravelly_sand | CC0 1.0 | Dario Barresi |
| terrain/dirt | https://polyhaven.com/a/dirt_floor | CC0 1.0 | eye-candy.xyz |
| terrain/forest_floor | https://polyhaven.com/a/forrest_ground_03 | CC0 1.0 | Rob Tuytel |
| terrain/grass_dry | https://polyhaven.com/a/withered_grass | CC0 1.0 | Charlotte Baglioni |
| terrain/grass_lush | https://polyhaven.com/a/leafy_grass | CC0 1.0 | Charlotte Baglioni |
| terrain/grass_sparse | https://polyhaven.com/a/sparse_grass | CC0 1.0 | Amal Kumar |
| terrain/mud | https://polyhaven.com/a/brown_mud_03 | CC0 1.0 | Rob Tuytel |
| terrain/pebbles | https://polyhaven.com/a/dry_river_pebbles | CC0 1.0 | Amal Kumar |
| terrain/red_rock | https://ambientcg.com/view?id=Rock029 | CC0 1.0 | ambientCG |
| terrain/red_sand | https://polyhaven.com/a/red_sand | CC0 1.0 | Rohit Seervi |
| terrain/road | https://polyhaven.com/a/dry_mud_field_001 | CC0 1.0 | Rob Tuytel, Rico Cilliers |
| terrain/rock | https://polyhaven.com/a/cliff_side | CC0 1.0 | James Ray Cock, Jenelle van Heerden, Dario Barresi |
| terrain/snow | https://polyhaven.com/a/snow_02 | CC0 1.0 | Rob Tuytel |

## Fonts (SIL Open Font License 1.1; licence texts ship next to the fonts in `assets/fonts/`)
| Font | Files | Author |
|---|---|---|
| IM FELL English (Roman, Italic, Small Caps) | IMFeENrm28P.ttf, IMFeENit28P.ttf, IMFeENsc28P.ttf | Igino Marini |
| Rye | Rye-Regular.ttf | Nicole Fally (Sorkin Type) |
| Sancreek | Sancreek-Regular.ttf | Vernon Adams (Sorkin Type) |
| Old Standard TT | OldStandard-Regular.ttf, OldStandard-Bold.ttf | Alexey Kryukov |

## Audio
All game audio is built by `frontier/tools/audio/` (locally, or in the `audio` job of
`.github/workflows/frontier-assets.yml`) and ships as `assets/ext/audio/` (release asset `audio.zip`). No audio from
other games or films is used, ever.

| Item | Licence | Source / how |
|---|---|---|
| Synthesized SFX and ambience (guns, mechanics, impacts, footsteps, hooves, tack, doors, glass, coins, UI, Nerve, wind, rain, thunder, water, fire, insects, birds, frogs, coyotes, wolves, elk, crowd babble, town sounds) | Original work (this repository) | `tools/audio/sfx_*.py`, numpy/scipy DSP, deterministic |
| Score: main theme, exploration (plains/desert/mountains, day/night), town, tension, combat, missions, stingers, saloon piano | Original compositions (this repository) | note data + arrangement rules in `tools/audio/music.py` |
| FluidR3_GM.sf2 soundfont (instrument samples heard in the rendered score) | MIT | Frank Wen et al.; Ubuntu package `fluid-soundfont-gm` |
| FluidSynth 2.x (renders the score at build time; not shipped) | LGPL-2.1 | https://www.fluidsynth.org (Ubuntu package `fluidsynth`) |
| Kokoro-82M TTS model + voice styles (renders the dialogue; the generated speech ships) | Apache-2.0 | hexgrad, https://huggingface.co/hexgrad/Kokoro-82M ; ONNX export + voices from https://github.com/thewh1teagle/kokoro-onnx (MIT), release `model-files-v1.0` |
| kokoro-onnx, onnxruntime, espeakng-loader / eSpeak NG phonemizer (build time only) | MIT / MIT / GPL-3.0 (tools, not shipped) | PyPI |
| Dialogue text (`design/dialogue/*.json`) and voice casting | Original writing (this repository) | |
| numpy, scipy, soundfile (libsndfile), mido, matplotlib (build time only) | BSD / BSD / LGPL-2.1 / MIT / PSF-style | PyPI |

### Field recordings (Wikimedia Commons, CC0 / public domain only)
Fetched by `tools/audio/commons.py` in CI. The licence of every file is checked through the Commons API
(`imageinfo` → `extmetadata` LicenseShortName / License must be CC0 or public domain; anything else is skipped). The
per-file table (target id, Commons file, author, licence, source page, processing) ships as
`assets/ext/audio/LICENSES_AUDIO.md` (+ `.json`) and as the release asset `LICENSES_AUDIO.md`; mirror it below with
`python3 frontier/tools/audio/commons.py --mirror-licenses frontier/assets/ext/audio`.

<!-- audio-recordings:begin -->
_Not yet mirrored: run the frontier-assets workflow with mode=audio, fetch audio.zip, then run the mirror command._
<!-- audio-recordings:end -->

## Characters and animation (frontier/tools/characters -> assets/ext/characters, release `characters.zip`)
The shipped character files (`<id>.glb`, `animations.glb`) are the *output* of a build pipeline: CC0 MakeHuman assets
combined with original procedural work and retargeted CMU motion capture. Every source was checked at its origin
(LICENSE / pack metadata / usage statement) on 2026-10-04; `characters/LICENSES.json` ships the same list.

| Source (pinned) | Used for | Licence (verified where) |
|---|---|---|
| MPFB2, github.com/makehumancommunity/mpfb2 @ d0a32e5 — `src/mpfb/data` | base mesh hm08, modelling targets (macros, face/body shape), `game_engine` rig + weights | Assets **CC0 1.0** (LICENSE.md section C, LICENSE.ASSETS.md). MPFB2 *code* is **GPL-3.0**: it is only executed as a build tool (Blender `bpy` module) and is never shipped; LICENSE.md section D: "no output from MPFB contains any trace of program logic ... no limitation on what you can do with this combined output". |
| MakeHuman system assets pack `makehuman_system_assets_cc0.zip` (mirror1.makehuman.net, fallback files2.makehumancommunity.org; URLs from makehuman2's `makehuman2_version.json`) | skins, eye meshes + iris textures, eyebrows, eyelashes, teeth, tongue, hair | **CC0 1.0** — `packs/makehuman_system_assets.json` lists all 94 assets with `"license": "CC0"`; mhmat headers state the CC0 release (Sept 2020). `fetch_sources.sh` aborts if any asset in the pack is not CC0. |
| makehumancommunity/extra-targets @ 7eaba34 (`faceunits01`, `visemes02`) | face blend shapes (ARKit-style units, visemes) | **CC0 1.0** (repo LICENSE; pack json `"license": "CC0"`) |
| CMU Graphics Lab Motion Capture Database, cgspeed BVH conversion by B. Hahne, via github.com/una-dinosauria/cmu-mocap @ 09a07f5 (51 clips, list in `retarget.py`) | animation library (`animations.glb`) | CMU: "free for use in research and commercial projects worldwide"; the BVH converter adds no restrictions (READMEFIRST.txt "USAGE RIGHTS"). Credit: *The data used in this project was obtained from mocap.cs.cmu.edu. The database was created with funding from NSF EIA-0196217.* |
| Poly Haven fabrics already in `assets/ext/cloth/*` | garment fabric textures (applied in Godot by `cloth.gdshader`) | CC0 (see the asset table) |
| Procedural garments (shirts, vests, trousers, coats, dusters, skirts, aprons, bodices, boots, belts), hats, beards, strand texture, skin/hair/cloth shaders, retargeter | — | Original work (`tools/characters/*.py`, `shaders/characters/*`) |

Not used: MakeHuman *community* assets (mixed CC0/CC-BY, per-asset licences) and the system pack's modern garments
(logo T-shirts, jeans, sneakers); no Mixamo or other commercial animation. Local development without access to the
MakeHuman mirrors can point `FRONTIER_MH_ASSETS` at any unmodified copy of the same CC0 pack.
