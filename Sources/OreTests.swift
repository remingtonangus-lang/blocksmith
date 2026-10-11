import Foundation
import simd

// L3 ores (docs/status/ground-l3.md): every overworld ore is told apart by colour AND shape, not just tint. Each HD ore
// texture is painted against its own bare stone; the ore pixels (those the painter changed) are measured: their mean
// colour, how many separate pieces they make, their mean size and how stretched and which way the pieces run.
enum OreTests {
    struct Look { var colour: V3; var pieces: Int; var size: Float; var stretch: Float; var angle: Float; var cover: Float }

    static func measure(_ key: String, n: Int = 64, seed: Int = 1234) -> Look? {
        guard let gen = HDTex.table[key] else { return nil }
        let img = gen(n, seed), bare = HDTex.stone(HDTex.stoneGrey)(n, seed &+ 31)
        var mask = [Bool](repeating: false, count: n * n)
        var sum = V3(0, 0, 0), cnt = 0
        for i in 0..<(n * n) {
            let a = img.px[i], b = bare.px[i]
            let d = abs(a.x - b.x) + abs(a.y - b.y) + abs(a.z - b.z)
            // The crystal itself (not just its darkened rim): changed and not a uniform darkening of the stone.
            let ratio = b.x + b.y + b.z > 0.01 ? (a.x + a.y + a.z) / (b.x + b.y + b.z) : 1
            if d > 0.06 && !(abs(ratio - 0.68) < 0.02) { mask[i] = true; sum += V3(a.x, a.y, a.z); cnt += 1 }
        }
        guard cnt > 0 else { return nil }
        // Pieces: 4-connected, wrapping (the texture tiles).
        var seen = [Bool](repeating: false, count: n * n)
        var pieces = 0, sizes: Float = 0, stretches: Float = 0, angSin: Float = 0, angCos: Float = 0, weight: Float = 0
        for start in 0..<(n * n) where mask[start] && !seen[start] {
            var stack = [start], pts: [(Float, Float)] = []
            seen[start] = true
            let sx = start % n, sy = start / n
            while let i = stack.popLast() {
                let x = i % n, y = i / n
                // Unwrapped relative to the piece's first pixel, so a piece across the edge stays whole.
                var ux = x - sx, uy = y - sy
                if ux > n / 2 { ux -= n } else if ux < -n / 2 { ux += n }
                if uy > n / 2 { uy -= n } else if uy < -n / 2 { uy += n }
                pts.append((Float(ux), Float(uy)))
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let j = ((y + dy + n) % n) * n + (x + dx + n) % n
                    if mask[j] && !seen[j] { seen[j] = true; stack.append(j) }
                }
            }
            guard pts.count >= 4 else { continue }                  // stray pixels are noise, not a piece
            pieces += 1
            let m = Float(pts.count)
            let mx = pts.reduce(0) { $0 + $1.0 } / m, my = pts.reduce(0) { $0 + $1.1 } / m
            var sxx: Float = 0, syy: Float = 0, sxy: Float = 0
            for (x, y) in pts { sxx += (x - mx) * (x - mx); syy += (y - my) * (y - my); sxy += (x - mx) * (y - my) }
            sxx /= m; syy /= m; sxy /= m
            let tr = sxx + syy, det = sxx * syy - sxy * sxy
            let disc = max(0, tr * tr / 4 - det).squareRoot()
            let l1 = tr / 2 + disc, l2 = max(0.05, tr / 2 - disc)
            sizes += m
            stretches += (l1 / l2).squareRoot() * m
            let th = 0.5 * atan2f(2 * sxy, sxx - syy)               // the long axis (0 = along x, pi/2 = along y)
            angSin += sinf(2 * th) * m; angCos += cosf(2 * th) * m; weight += m
        }
        guard pieces > 0 else { return nil }
        let angle = abs(0.5 * atan2f(angSin, angCos))
        return Look(colour: sum / Float(cnt), pieces: pieces, size: sizes / Float(pieces) / Float(n * n),
                    stretch: stretches / weight, angle: angle, cover: Float(cnt) / Float(n * n))
    }

    static func run(check: (Bool, String) -> Void) {
        let ores = ["coal_ore", "iron_ore", "copper_ore", "gold_ore", "lapis_ore", "emerald_ore", "diamond_ore"]
        var looks: [String: Look] = [:]
        for k in ores { if let l = measure(k) { looks[k] = l } }
        guard looks.count == ores.count else { check(false, "ores: every overworld ore has an HD texture with ore in it (\(looks.keys.sorted()))"); return }
        func f(_ x: Float) -> String { String(format: "%.2f", x) }
        let table = ores.map { k -> String in let l = looks[k]!; return "\(k.replacingOccurrences(of: "_ore", with: "")) \(l.pieces)x\(f(l.size * 100))% stretch \(f(l.stretch)) at \(Int(l.angle * 180 / .pi)) deg" }
        print("ores: " + table.joined(separator: "; "))
        // The shapes: iron in long slanting streaks, lapis in flat lenses, emerald in upright prisms, gold in many small
        // nuggets, coal and copper in round lumps.
        let i = looks["iron_ore"]!, la = looks["lapis_ore"]!, e = looks["emerald_ore"]!, g = looks["gold_ore"]!
        let c = looks["coal_ore"]!, cu = looks["copper_ore"]!
        let deg: (Float) -> Float = { $0 * 180 / .pi }
        check(i.stretch > 2 && deg(i.angle) > 15 && deg(i.angle) < 75, "ores: iron lies in long slanting streaks (stretch \(f(i.stretch)), \(Int(deg(i.angle))) deg)")
        check(la.stretch > 2.2 && deg(la.angle) < 20, "ores: lapis lies in flat lenses (stretch \(f(la.stretch)), \(Int(deg(la.angle))) deg)")
        check(e.stretch > 1.9 && deg(e.angle) > 65, "ores: emerald stands in upright prisms (stretch \(f(e.stretch)), \(Int(deg(e.angle))) deg)")
        check(g.pieces >= max(c.pieces, cu.pieces) + 4 && g.size < c.size / 2, "ores: gold is a scatter of small nuggets (\(g.pieces) pieces of \(f(g.size * 100))% vs coal's \(c.pieces) of \(f(c.size * 100))%)")
        check(c.stretch < 1.8 && cu.stretch < 1.8, "ores: coal and copper sit in round lumps (stretch \(f(c.stretch)), \(f(cu.stretch)))")
        // Every pair told apart by colour (mean ore colour) or shape (stretch, direction or piece size).
        var same: [String] = []
        for a in 0..<ores.count { for b in (a + 1)..<ores.count {
            let p = looks[ores[a]]!, q = looks[ores[b]]!
            let colour = simd_length(p.colour - q.colour)
            let shape = abs(p.stretch - q.stretch) > 0.7 || (min(p.stretch, q.stretch) > 1.8 && abs(p.angle - q.angle) > 0.5)
                || max(p.size, q.size) / max(1e-4, min(p.size, q.size)) > 2.2
            if colour < 0.18 && !shape { same.append("\(ores[a])/\(ores[b])") }
            // Colour alone isn't enough for the pairs a player mixes up at a glance (the warm metals).
            if ["iron_ore", "copper_ore", "gold_ore"].contains(ores[a]) && ["iron_ore", "copper_ore", "gold_ore"].contains(ores[b]) && !shape {
                same.append("\(ores[a])/\(ores[b]) (same shape)")
            }
        } }
        check(same.isEmpty, "ores: every overworld ore differs from every other by colour and the warm metals by shape too (\(same.isEmpty ? "all 21 pairs" : same.joined(separator: ", ")))")
    }
}
