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
