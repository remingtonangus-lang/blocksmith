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

    // Q2c-console-70: a card of lines (the first a gold title), left-aligned on the same dark backing, centred in a
    // w x h pixel panel, one font pixel = `scale` pixels.
    static func card(_ lines: [String], width w: Float, height h: Float, scale: Float) -> [HudVert] {
        var v: [HudVert] = []
        let lh = 10 * scale, pad = 5 * scale
        let tw = lines.map { Float(Font.width($0)) * scale }.max() ?? 0
        let bw = min(w, tw + pad * 2), bh = min(h, Float(lines.count) * lh + pad * 2)
        let bx = floor((w - bw) / 2), by = floor((h - bh) / 2)
        func quad(_ p: [V2], _ c: V4) {
            for i in [0, 1, 2, 0, 2, 3] { v.append(HudVert(pos: p[i], uv: .zero, color: c, extra: V4(-1, 0, 0, 0))) }
        }
        let bg = V4(0.05, 0.06, 0.08, 0.85)
        quad([V2(bx + scale, by), V2(bx + bw - scale, by), V2(bx + bw - scale, by + bh), V2(bx + scale, by + bh)], bg)
        quad([V2(bx, by + scale), V2(bx + bw, by + scale), V2(bx + bw, by + bh - scale), V2(bx, by + bh - scale)], bg)
        for (i, line) in lines.enumerated() {
            // Each line drawn by the label code (centred in a strip as wide as the card) and moved to its row, left-aligned.
            let lw = Float(Font.width(line)) * scale
            let strip = verts(line, width: lw + 8 * scale, height: lh, scale: scale)
            let dx = bx + pad - 4 * scale, dy = by + pad + Float(i) * lh - 4 * scale      // (verts sets text 5 px down)
            for var hv in strip where hv.extra.x >= 0 {                       // the glyphs, not the strip's own backing
                hv.pos += V2(dx, dy)
                if i == 0 { hv.color = V4(1, 0.85, 0.4, hv.color.w) * V4(hv.color.x > 0.5 ? 1 : 0.25, hv.color.x > 0.5 ? 1 : 0.25, hv.color.x > 0.5 ? 1 : 0.25, 1) }
                v.append(hv)
            }
        }
        return v
    }

    // Width in pixels of the label's backing for `str` (to size the panel quad).
    static func width(_ str: String, scale: Float) -> Float { Float(Font.width(str)) * scale + 8 * scale }
}
