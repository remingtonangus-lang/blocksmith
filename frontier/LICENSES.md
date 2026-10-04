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
