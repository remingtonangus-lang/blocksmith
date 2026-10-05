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
| Firearm models + textures (10 weapons, finish variants; `weapons.zip` in the `frontier-assets` release) | `frontier/tools/weapons/gun_gen.py`: original fictional designs modelled procedurally in Blender (bpy) with procedurally synthesised PBR textures (no photo textures, no third-party meshes, no real maker's marks) |

Tools used only to *produce* original content (their licences do not apply to the output): Blender 5.0.1 as a
Python module (`pip install bpy`, GPL-2.0-or-later), NumPy / SciPy (BSD-3-Clause), Pillow (MIT-CMU).

## Third-party CC0 assets
Fetched by `.github/workflows/frontier-assets.yml` from `frontier/assets/manifest.json`; the per-asset list with
source URLs and authors ships as `assets/ext/LICENSES.json` and is mirrored below when assets are added.

| Asset (dest) | Source | Licence | Author |
|---|---|---|---|
