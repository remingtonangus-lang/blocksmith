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
