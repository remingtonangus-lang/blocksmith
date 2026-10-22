import Foundation
import simd

// P402 (3): the loading scene's picture of the two Quest controllers (QuestApp.recordLoading draws it on the words'
// plane, 2.3 m ahead, either side of the pedestal). Each control is tinted and a line runs from it to a small pixel
// picture of what it does (no words, NO TEXT; the button letters are the controllers' own). Right hand: the trigger
// mines, the stick turns, B goes back, A jumps, the grip steps the hotbar on; left hand: the trigger places, the stick
// walks, Y opens the inventory, X picks the block aimed at, the grip steps the hotbar back. Dominant Hand Left swaps the
// pictures between the controllers. `questcheck --controllerpic OUT.svg` writes it as a picture (P402 (5) shots).
enum ControllerPicture {
    struct Poly { var pts: [V2]; var dz: Float; var col: V4 }

    static let pick = [".#####.", "#..#..#", "...#...", "...#...", "...#...", "...#...", "...#..."]
    static let block = ["#######", "#.....#", "#.###.#", "#.###.#", "#.###.#", "#.....#", "#######"]
    static let jump = ["...#...", "..###..", ".#####.", "#######", "...#...", "...#...", "...#..."]
    static let back = ["..#....", ".##....", "#######", ".##...#", "..#...#", "......#", "..#####"]
    static let chest = ["#######", "#.....#", "#######", "#..#..#", "#.....#", "#.....#", "#######"]
    static let aim = ["...#...", ".#####.", ".#...#.", "##.#.##", ".#...#.", ".#####.", "...#..."]
    static let move = ["...#...", "..###..", ".#.#.#.", "#######", ".#.#.#.", "..###..", "...#..."]
    static let turn = ["..#.#..", ".##.##.", "###.###", ".##.##.", "..#.#..", ".......", "......."]
    static let next = ["#######", "#.#.#.#", "#######", ".......", "....#..", ".#####.", "....#.."]
    static let prev = ["#######", "#.#.#.#", "#######", ".......", "..#....", ".#####.", "..#...."]
    // (trigger, stick, upper button, lower button, grip)
    static let tints = [V4(1, 0.62, 0.3, 1), V4(0.45, 0.85, 0.4, 1), V4(0.45, 0.7, 1, 1), V4(0.95, 0.85, 0.35, 1), V4(0.8, 0.55, 0.95, 1)]

    static func build(centreY cyAll: Float, leftHanded: Bool) -> [Poly] {
        var out: [Poly] = []
        func rect(_ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float, _ dz: Float, _ col: V4) {
            out.append(Poly(pts: [V2(x0, y0), V2(x1, y0), V2(x1, y1), V2(x0, y1)], dz: dz, col: col))
        }
        func disc(_ cx: Float, _ cy: Float, _ rx: Float, _ ry: Float, _ dz: Float, _ col: V4) {
            var p: [V2] = []
            for k in 0..<20 { let a = Float(k) / 20 * 2 * .pi; p.append(V2(cx + cosf(a) * rx, cy + sinf(a) * ry)) }
            out.append(Poly(pts: p, dz: dz, col: col))
        }
        func pixels(_ m: [String], _ x: Float, _ y: Float, _ px: Float, _ col: V4, shadow: Bool) {
            let w = Float(m.first?.count ?? 0), h = Float(m.count)
            for (r, row) in m.enumerated() { for (c, ch) in row.enumerated() where ch == "#" {
                let x0 = x + (Float(c) - w / 2) * px, y0 = y + (h / 2 - Float(r)) * px
                if shadow { rect(x0 + px * 0.3, x0 + px * 1.3, y0 - px * 1.3, y0 - px * 0.3, 0.002, V4(0.05, 0.06, 0.1, 0.85)) }
                rect(x0, x0 + px, y0 - px, y0, 0.006, col)
            } }
        }
        // A button's letter in the game's pixel font, centred on (x, y).
        func letter(_ s: Character, _ x: Float, _ y: Float) {
            guard let code = s.unicodeScalars.first.map({ Int($0.value) }), code >= 32 && code < 127 else { return }
            let g = Font.glyphs[code - 32]
            var m: [String] = []
            for r in 0..<(g.count - 1) { m.append(String((0..<g[0]).map { g[r + 1] & (1 << $0) != 0 ? "#" : "." })) }
            pixels(m, x, y, 0.0035, V4(0.08, 0.08, 0.1, 1), shadow: false)
        }
        for side in [-1, 1] as [Float] {
            let dominant = (side > 0) != leftHanded
            let cx: Float = side * 0.92, cy = cyAll
            let icons = dominant ? [pick, turn, back, jump, next] : [block, move, chest, aim, prev]
            let letters: [Character] = side > 0 ? ["B", "A"] : ["Y", "X"]
            let body = V4(0.16, 0.17, 0.2, 1), edge = V4(0.3, 0.31, 0.36, 1)
            // The handle with its grip, the rounded head with the trigger's tab over its inner edge.
            let hx = cx - side * 0.01
            disc(hx, cy - 0.12, 0.05, 0.1, -0.004, edge)
            disc(hx, cy - 0.12, 0.042, 0.092, -0.002, body)
            rect(hx - 0.045, hx + 0.045, cy - 0.17, cy - 0.06, -0.001, tints[4])
            disc(cx, cy + 0.02, 0.105, 0.085, 0, edge)
            disc(cx, cy + 0.02, 0.097, 0.077, 0.001, body)
            rect(cx - side * 0.06 - 0.03, cx - side * 0.06 + 0.03, cy + 0.095, cy + 0.12, -0.003, tints[0])
            let stick = V2(cx - side * 0.035, cy + 0.035), up = V2(cx + side * 0.035, cy + 0.055), lo = V2(cx + side * 0.045, cy)
            disc(stick.x, stick.y, 0.03, 0.03, 0.002, tints[1])
            disc(stick.x, stick.y, 0.02, 0.02, 0.003, V4(0.1, 0.1, 0.12, 1))
            disc(up.x, up.y, 0.018, 0.018, 0.002, tints[2])
            disc(lo.x, lo.y, 0.018, 0.018, 0.002, tints[3])
            letter(letters[0], up.x, up.y)
            letter(letters[1], lo.x, lo.y)
            // Lines (behind the controller) out to a column of pictures beside it.
            // (each line's own upright, so none crosses another: the pictures run top to bottom in the order the
            // controls do)
            let ix = cx + side * 0.27
            let rows: [(V2, Float, Float)] = [(V2(cx - side * 0.06, cy + 0.11), cy + 0.17, 0.13), (stick, cy - 0.02, 0.15),
                                              (up, cy + 0.075, 0.15), (lo, cy - 0.115, 0.13), (V2(hx, cy - 0.12), cy - 0.21, 0.11)]
            for (k, (from, iy, vx)) in rows.enumerated() {
                let lx = cx + side * vx
                let line = tints[k] * V4(1, 1, 1, 0.8)
                rect(min(from.x, lx), max(from.x, lx), from.y - 0.002, from.y + 0.002, -0.003, line)
                rect(lx - 0.002, lx + 0.002, min(from.y, iy) - 0.002, max(from.y, iy) + 0.002, -0.003, line)
                rect(min(lx, ix), max(lx, ix), iy - 0.002, iy + 0.002, -0.003, line)
                pixels(icons[k], ix + side * 0.045, iy, 0.011, tints[k], shadow: true)
            }
        }
        return out
    }

    // The picture as an SVG (harness shots): polygons back to front, metres scaled to pixels, y up.
    static func svg(leftHanded: Bool) -> String {
        let polys = build(centreY: 0, leftHanded: leftHanded).enumerated().sorted { $0.element.dz != $1.element.dz ? $0.element.dz < $1.element.dz : $0.offset < $1.offset }
        let s: Float = 700, w: Float = 2000, h: Float = 400
        var out = "<svg xmlns='http://www.w3.org/2000/svg' width='\(Int(w))' height='\(Int(h))'><rect width='100%' height='100%' fill='#d6bda3'/>"
        for (_, p) in polys {
            let pts = p.pts.map { String(format: "%.1f,%.1f", w / 2 + $0.x * s, h / 2 - $0.y * s) }.joined(separator: " ")
            out += String(format: "<polygon points='%@' fill='rgb(%d,%d,%d)' fill-opacity='%.2f'/>", pts,
                          Int(p.col.x * 255), Int(p.col.y * 255), Int(p.col.z * 255), p.col.w)
        }
        return out + "</svg>"
    }
}
