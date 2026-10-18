# Credits and licences (draft)

## Credits
- **Created by:** Remington [surname]
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
| llama.cpp and ggml (libdirectorllm.so, P266; built by quest/tools/build-director-llm.sh) | The Director's on-device planner | MIT (Copyright The ggml authors) |
| Qwen2.5 Instruct model, 0.5B or 1.5B, Q4_K_M GGUF (optional download, not in the APK) | The Director's on-device planner | Apache 2.0 (Copyright Alibaba Cloud); ship its LICENSE with the download |

In the app: Options > Interface > About and Licences (Sources/AboutMenu.swift) lists these components with their
licences and copyright lines, and where to read the full texts. Before submission, check the APK's lib/ folder against
this table, add any NOTICE file text a component requires, and keep AboutMenu.parts in step with it.

## Assets
No third-party textures, models, sounds or music. Every texture is painted procedurally in code (Textures.swift and
related files), and every sound and piece of music is synthesized in code. Image requests in docs/art/image-requests.md
and recordings in docs/audio/sound-list.md will be commissioned or generated for Sunderfall. Record their source and
licence here as they arrive.
