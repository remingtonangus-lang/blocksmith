import Foundation
import simd

// Small text labels for world-space panels (the interact hint beside the laser dot): the HUD's pixel font and
// controller glyphs (Font.swift, Glyphs.swift) as HudVerts, centred on a dark rounded backing.
enum QuestLabel {
    // Vertices for `str` centred in a w x h pixel panel, one font pixel = `scale` pixels.
    static func verts(_ str: String, width w: Float, height h: Float, scale: Float) -> [HudVert] {
        var v: [HudVert] = []
        func quad(_ p: [V2], _ uv: [V2], _ c: V4, _ layer: Float) {
            for i in [0, 1, 2, 0, 2, 3] { v.append(HudVert(pos: p[i], uv: uv[i], color: c, extra: V4(layer, 0, 0, 0))) }
        }
        func rect(_ x: Float, _ y: Float, _ rw: Float, _ rh: Float, _ c: V4) {
            quad([V2(x, y), V2(x + rw, y), V2(x + rw, y + rh), V2(x, y + rh)], [V2](repeating: .zero, count: 4), c, -1)
        }
        func text(_ s: String, _ x: Float, _ y: Float, _ sc: Float, _ color: V4, _ shadow: Bool) {
            var cx = x
            for u in s.unicodeScalars {
                let code = Int(u.value)
                let adv = Float(Font.advance(code))
                if Glyphs.isGlyph(code) {
                    Glyphs.draw(code, cx, y, sc, color.w, rect: rect) { t, tx, ty, ts, tc, sh in text(t, tx, ty, ts, tc, sh) }
                } else if code > 32 && code < 127 {
                    let gw = Float(Font.glyphs[code - 32][0])
                    let rows = Float(Font.rows(code))
                    let layer = Float(Font.layerBase + code - 32)
                    let uv = [V2(0, 0), V2(gw / 16, 0), V2(gw / 16, rows / 16), V2(0, rows / 16)]
                    func g(_ ox: Float, _ oy: Float, _ c: V4) {
                        let a = V2(cx + ox, y + oy)
                        quad([a, a + V2(gw * sc, 0), a + V2(gw * sc, rows * sc), a + V2(0, rows * sc)], uv, c, layer)
                    }
                    if shadow { g(sc, sc, V4(color.x * 0.25, color.y * 0.25, color.z * 0.25, color.w)) }
                    g(0, 0, color)
                }
                cx += adv * sc
            }
        }
        let tw = Float(Font.width(str)) * scale
        let th = 9 * scale
        let pad = 4 * scale
        let bw = min(w, tw + pad * 2), bh = min(h, th + pad * 2)
        let bx = (w - bw) / 2, by = (h - bh) / 2
        let back = V4(0.05, 0.06, 0.08, 0.78)
        rect(bx + scale, by, bw - 2 * scale, bh, back)
        rect(bx, by + scale, bw, bh - 2 * scale, back)
        text(str, floor((w - tw) / 2), floor(by + pad + scale), scale, V4(1, 1, 1, 1), true)
        return v
    }

    // Width in pixels of the label's backing for `str` (to size the panel quad).
    static func width(_ str: String, scale: Float) -> Float { Float(Font.width(str)) * scale + 8 * scale }
}
