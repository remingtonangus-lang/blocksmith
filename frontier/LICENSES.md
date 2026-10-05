# Frontier — asset and dependency licences

Every asset in the shipped game is listed here with its source and licence. Rule: original work, CC0/public
domain, or a permissive open licence recorded below. No assets from other games, ever.

## Engine and code
| Item | Licence | Source |
|---|---|---|
| Godot Engine 4.7.1 (+ export templates) | MIT | https://godotengine.org |
| All Frontier code, shaders, scenes (frontier/) | Original work, same licence as this repository | this repo |

## Generated in-house (original)
| Item | How |
|---|---|
| World terrain, rivers, roads, towns layout | `frontier/tools/worldgen.py` (procedural, seed 1899) |
| Buildings, props, vegetation meshes | Procedural generators in `frontier/src/` |
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
| props/BarberShopChair_01 | https://polyhaven.com/a/BarberShopChair_01 | CC0 1.0 | Fernando Quinn |
| props/CashRegister_01 | https://polyhaven.com/a/CashRegister_01 | CC0 1.0 | Joe Seabuhr |
| props/ClassicNightstand_01 | https://polyhaven.com/a/ClassicNightstand_01 | CC0 1.0 | Kirill Sannikov |
| props/Rockingchair_01 | https://polyhaven.com/a/Rockingchair_01 | CC0 1.0 | Jorge Camacho |
| props/WoodenTable_02 | https://polyhaven.com/a/WoodenTable_02 | CC0 1.0 | Fran Calvente |
| props/WoodenTable_03 | https://polyhaven.com/a/WoodenTable_03 | CC0 1.0 | Gabriel Radić |
| props/barrel_03 | https://polyhaven.com/a/barrel_03 | CC0 1.0 | Serhii Khromov |
| props/bull_head | https://polyhaven.com/a/bull_head | CC0 1.0 | Tina |
| props/folding_wooden_stool | https://polyhaven.com/a/folding_wooden_stool | CC0 1.0 | Ulan Cabanilla |
| props/hanging_picture_frame_01 | https://polyhaven.com/a/hanging_picture_frame_01 | CC0 1.0 | James Ray Cock |
| props/jug_01 | https://polyhaven.com/a/jug_01 | CC0 1.0 | Kuutti Siitonen |
| props/lantern_chandelier_01 | https://polyhaven.com/a/lantern_chandelier_01 | CC0 1.0 | Kirill Sannikov |
| props/mantel_clock_01 | https://polyhaven.com/a/mantel_clock_01 | CC0 1.0 | Yann Kervran, Rico Cilliers |
| props/old_bed_frame | https://polyhaven.com/a/old_bed_frame | CC0 1.0 | Luca B |
| props/painted_wooden_cabinet | https://polyhaven.com/a/painted_wooden_cabinet | CC0 1.0 | Kirill Sannikov |
| props/painted_wooden_chair_01 | https://polyhaven.com/a/painted_wooden_chair_01 | CC0 1.0 | Kuutti Siitonen |
| props/painted_wooden_table | https://polyhaven.com/a/painted_wooden_table | CC0 1.0 | Kirill Sannikov |
| props/pot_enamel_01 | https://polyhaven.com/a/pot_enamel_01 | CC0 1.0 | Kuutti Siitonen |
| props/round_wooden_table_01 | https://polyhaven.com/a/round_wooden_table_01 | CC0 1.0 | Ulan Cabanilla |
| props/rusted_spade_01 | https://polyhaven.com/a/rusted_spade_01 | CC0 1.0 | Blemonade |
| props/stone_fire_pit | https://polyhaven.com/a/stone_fire_pit | CC0 1.0 | Sebastian Platen |
| props/vintage_binocular | https://polyhaven.com/a/vintage_binocular | CC0 1.0 | Luke |
| props/vintage_grandfather_clock_01 | https://polyhaven.com/a/vintage_grandfather_clock_01 | CC0 1.0 | Yann Kervran, James Ray Cock |
| props/vintage_oil_lamp | https://polyhaven.com/a/vintage_oil_lamp | CC0 1.0 | Monsta3D |
| props/vintage_suitcase | https://polyhaven.com/a/vintage_suitcase | CC0 1.0 | Maximilian Schuster |
| props/wicker_basket_01 | https://polyhaven.com/a/wicker_basket_01 | CC0 1.0 | Kuutti Siitonen |
| props/wine_barrel_01 | https://polyhaven.com/a/wine_barrel_01 | CC0 1.0 | James Ray Cock |
| props/wooden_axe | https://polyhaven.com/a/wooden_axe | CC0 1.0 | Ulan Cabanilla |
| props/wooden_barrels_01 | https://polyhaven.com/a/wooden_barrels_01 | CC0 1.0 | James Ray Cock |
| props/wooden_bowl_01 | https://polyhaven.com/a/wooden_bowl_01 | CC0 1.0 | Oliver Harries |
| props/wooden_bucket_01 | https://polyhaven.com/a/wooden_bucket_01 | CC0 1.0 | James Ray Cock |
| props/wooden_bucket_02 | https://polyhaven.com/a/wooden_bucket_02 | CC0 1.0 | James Ray Cock |
| props/wooden_crate_01 | https://polyhaven.com/a/wooden_crate_01 | CC0 1.0 | James Ray Cock |
| props/wooden_crate_02 | https://polyhaven.com/a/wooden_crate_02 | CC0 1.0 | James Ray Cock, Jurita Burger |
| props/wooden_display_shelves_01 | https://polyhaven.com/a/wooden_display_shelves_01 | CC0 1.0 | James Ray Cock |
| props/wooden_ladder | https://polyhaven.com/a/wooden_ladder | CC0 1.0 | Miroslav Turura |
| props/wooden_lantern_01 | https://polyhaven.com/a/wooden_lantern_01 | CC0 1.0 | James Ray Cock |
| props/wooden_military_crate | https://polyhaven.com/a/wooden_military_crate | CC0 1.0 | Prabhjinder Singh |
| props/wooden_stool_01 | https://polyhaven.com/a/wooden_stool_01 | CC0 1.0 | Kuutti Siitonen |
| props/hatchet | https://polyhaven.com/a/hatchet | CC0 1.0 | James Ray Cock, Ulan Cabanilla |
| props/pocket_watch | https://polyhaven.com/a/pocket_watch | CC0 1.0 | PierreB3D |

Used by the settlements (src/world/settlements.gd and the building kit): every `build/*` material and
`cloth/canvas` above as wall/roof/floor/awning textures; the listed `props/*` models furnish interiors and streets.
Excluded on purpose: `props/Barrel_01` (modern hazard markings).

## Fonts (SIL Open Font License 1.1)
Shipped in `frontier/assets/fonts/` with their licence texts (`OFL-*.txt`); rasterised at runtime into MSDF
atlases for painted sign lettering (`src/world/sign_text.gd`).

| Font | Copyright | Licence | Source |
|---|---|---|---|
| Rye | 2011 Sorkin Type Co, Reserved Font Name "Rye" | OFL 1.1 | https://github.com/google/fonts/tree/main/ofl/rye |
| Sancreek | 2011 The Sancreek Project Authors | OFL 1.1 | https://github.com/google/fonts/tree/main/ofl/sancreek |
| Old Standard TT (Regular, Bold) | 2011 The Old Standard Project Authors | OFL 1.1 | https://github.com/google/fonts/tree/main/ofl/oldstandardtt |
| Ewert | 2011 Johan Kallas, Mihkel Virkus, Reserved Font Name "Ewert" | OFL 1.1 | https://github.com/google/fonts/tree/main/ofl/ewert |
