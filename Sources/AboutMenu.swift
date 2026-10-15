import Foundation

// Q2 (store readiness, docs/store/credits-and-licences.md): Options > Interface > About and Licences. Who made the game,
// and the open source parts the build carries with their licences. Press a row for its copyright line.
final class AboutMenu: ListMenu {
    struct Part { let name: String; let licence: String; let notice: String }
    static var parts: [Part] {
        var out = [Part(name: "Blocksmith", licence: "Code, textures, sound and music made for the game",
                        notice: "Every name, text, texture and sound in Blocksmith is its own"),
                   Part(name: "Swift runtime, Foundation, Dispatch", licence: "Apache License 2.0 with Runtime Library Exception",
                        notice: "Copyright Apple Inc. and the Swift project authors")]
        #if os(Android)
        out += [Part(name: "Khronos OpenXR loader", licence: "Apache License 2.0", notice: "Copyright The Khronos Group Inc."),
                Part(name: "Vulkan headers", licence: "Apache License 2.0 / MIT", notice: "Copyright The Khronos Group Inc.")]
        #endif
        // Q2c-console-13: the Director's on-device runner and model, when this build or device has them (P266).
        if DirectorLLM.open() {
            out.append(Part(name: "llama.cpp and ggml", licence: "MIT License", notice: "Copyright (c) 2023-2026 The ggml authors"))
        }
        if DirectorLLM.modelPath != nil {
            out.append(Part(name: "Qwen2.5 Instruct model (Director)", licence: "Apache License 2.0", notice: "Copyright Alibaba Cloud (Qwen team)"))
        }
        out.append(Part(name: "Privacy", licence: "Nothing leaves this device unless you choose to",
                        notice: "Only Play Together (your local network) or the Director's Cloud planner (a world summary) send anything. No account, no tracking"))
        out.append(Part(name: "Licence texts", licence: "apache.org/licenses/LICENSE-2.0  opensource.org/license/mit",
                        notice: "Each licence's full text is published at these addresses"))
        return out
    }

    init(game g: Game) {
        super.init("About and Licences", game: g)
        subtitle = "Blocksmith, and the open source parts it is built on"
        corner = ""
    }
    override var rows: [Row] {
        AboutMenu.parts.map { Row(name: $0.name, detail: $0.licence, value: "", enabled: true, good: true) }
    }
    override func pressed(_ i: Int) {
        let p = AboutMenu.parts
        guard i < p.count else { return }
        say(p[i].notice, good: true)
    }
}
