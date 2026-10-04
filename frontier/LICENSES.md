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
