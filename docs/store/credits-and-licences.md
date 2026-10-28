# Credits and licences (draft)

## Credits
- **A game by:** Remington Wilbur, Noobmaster Industries
- **Made with:** Claude, by Anthropic (the code, the world, the art, the sound and the music; P479)
- **Engine, game code, procedural textures, synthesized sound and music:** written for Sunderfall. All game code is
  original, with no third-party gameplay code.
- **Design reference:** genre conventions of block-building survival games. Every name, text, texture and sound in
  Sunderfall is Sunderfall's own (see docs/status/ip-renames.md).

## Third-party software in the Quest build
| Component | Use | Licence |
|---|---|---|
| Swift standard library, Foundation (swift-corelibs-foundation), Dispatch | Language runtime on the headset | Apache 2.0 with Runtime Library Exception |
| Khronos OpenXR loader | VR session | Apache 2.0 |
| Vulkan headers | Rendering API definitions | Apache 2.0 / MIT |
| Android NDK system libraries (libc, AAudio, android) | Platform | Platform-provided |
| Platform entitlement loader (store builds, once enabled) | Ownership check | Platform SDK licence |

In the app: Options > Interface > About and Licences (Sources/AboutMenu.swift) lists these components with their
licences and copyright lines, and where to read the full texts. Before submission, check the APK's lib/ folder against
this table, add any NOTICE file text a component requires, and keep AboutMenu.parts in step with it.

## Assets
Corrected for P439 (Oct 24): the old text said every asset was made in code, which is no longer true.

| Asset | Source | Licence to confirm before submission |
|---|---|---|
| Block and item textures (Resources/Textures, packed into Resources/texpack.bin) | Generated with Google Gemini image models from prompts written for Sunderfall (tools/gemini_textures.py, tools/texture_prompts.json), then cleaned up in code; the rest painted procedurally (Textures.swift) | Google's generative AI terms for the account used: commercial use of outputs |
| Sound effects (Resources/Sounds/real, 914 files) | ElevenLabs sound generation, commercial licence (commit e47e0aad) | The ElevenLabs plan in force when they were made |
| Townsfolk voices (Resources/voices.bin) | ElevenLabs voices through OpenRouter's speech endpoint (tools/townvoice_gen.py) | ElevenLabs terms for speech made through OpenRouter: commercial use |
| Music (Resources/Music/sunderfall, 40 tracks) | Made by Remington in Google Flow Music, Oct 16-17 | Google Flow Music terms: commercial use and distribution in a paid app |
| Everything else (models, mobs, sky, particles, synthesized sounds) | Original, in code | |

No asset comes from another game. Generated assets are listed here so the store's AI-content questions can be answered
from one place.
