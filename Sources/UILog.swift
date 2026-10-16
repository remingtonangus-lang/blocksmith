import Foundation

// `--uilog PATH` (snapshot harness): every HUD/menu text run and opaque panel rect of the last built HUD frame is
// written to PATH as JSON (screen pixels), for the text overflow detector tools/uioverflow.py
// (docs/STORE_QUALITY.md objective 8). Off unless the flag is given; Renderer.buildHUD records through it.
enum UILog {
    static let path: String? = arg("--uilog")
    static var w: Float = 0, h: Float = 0
    static var texts: [(String, Float, Float, Float, Float)] = []
    static var rects: [(Float, Float, Float, Float)] = []
    static func begin(_ W: Float, _ H: Float) { w = W; h = H; texts.removeAll(); rects.removeAll() }
    static func flush() {
        guard let path else { return }
        let j: [String: Any] = ["w": w, "h": h,
                                "texts": texts.map { ["s": $0.0, "x": $0.1, "y": $0.2, "w": $0.3, "h": $0.4] as [String: Any] },
                                "rects": rects.map { [$0.0, $0.1, $0.2, $0.3] }]
        if let d = try? JSONSerialization.data(withJSONObject: j) { try? d.write(to: URL(fileURLWithPath: path)) }
    }
}
