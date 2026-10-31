import Foundation
import simd

// P499 (Oct 30 20:01, "a little block floating at the top" of the Donnerkeil Service Rifle): every held gun's parts,
// and every upgrade fitting on it, touch the rest of the gun (a box clear of all the others floats in the hand).
enum GunFittingsCheck {
    static func touches(_ a: Part, _ b: Part, slack: Float = 0.06) -> Bool {
        a.mn.x <= b.mx.x + slack && b.mn.x <= a.mx.x + slack && a.mn.y <= b.mx.y + slack && b.mn.y <= a.mx.y + slack
            && a.mn.z <= b.mx.z + slack && b.mn.z <= a.mx.z + slack
    }

    // A part's box as drawn: its corners turned about its pivot, boxed again (a bipod leg, a turned barrel).
    static func placed(_ p: Part) -> Part {
        guard p.rotX != 0 || p.rotY != 0 || p.rotZ != 0 else { return p }
        let r = p.rotation
        var mn = V3(repeating: .greatestFiniteMagnitude), mx = -mn
        for i in 0..<8 {
            let c = V3(i & 1 == 0 ? p.mn.x : p.mx.x, i & 2 == 0 ? p.mn.y : p.mx.y, i & 4 == 0 ? p.mn.z : p.mx.z)
            let w = p.place(c, r)
            mn = simd_min(mn, w); mx = simd_max(mx, w)
        }
        var q = p
        q.mn = mn; q.mx = mx; q.rotX = 0; q.rotY = 0; q.rotZ = 0
        return q
    }

    // Parts not joined to the largest connected group (parts touching, transitively).
    static func loose(_ parts0: [Part]) -> [Int] {
        guard !parts0.isEmpty else { return [] }
        let parts = parts0.map(placed)
        var group = [Int](repeating: -1, count: parts.count)
        var sizes: [Int] = []
        for s in parts.indices where group[s] < 0 {
            let g = sizes.count
            sizes.append(0)
            var stack = [s]; group[s] = g
            while let i = stack.popLast() {
                sizes[g] += 1
                for j in parts.indices where group[j] < 0 && touches(parts[i], parts[j]) { group[j] = g; stack.append(j) }
            }
        }
        let main = sizes.indices.max { sizes[$0] < sizes[$1] }!
        return parts.indices.filter { group[$0] != main }
    }

    // A loose part's box and how far it lies from the nearest other part (pixels), for the log.
    static func describe(_ parts0: [Part], _ i: Int) -> String {
        let parts = parts0.map(placed), a = parts[i]
        var gap = Float.greatestFiniteMagnitude
        for (j, b) in parts.enumerated() where j != i {
            let d = simd_max(simd_max(b.mn - a.mx, a.mn - b.mx), V3(repeating: 0))
            gap = min(gap, simd_length(d))
        }
        return String(format: "[%.2f %.2f %.2f .. %.2f %.2f %.2f] %.2f px from the rest", a.mn.x, a.mn.y, a.mn.z, a.mx.x, a.mx.y, a.mx.z, gap)
    }

    static func run(_ check: (Bool, String) -> Void) {
        var bad: [String] = [], detail: [String] = []
        let ups: [(Ench, String)] = [(.stability, "scope"), (.penetration, "band"), (.incendiary, "band"), (.quickReload, "lever"), (.extendedMag, "mag")]
        for gi in Guns.all.indices where Guns.current(gi) == gi {
            let base = Guns.models[gi]
            for i in loose(base) { bad.append("\(Guns.all[gi].key) part \(i)"); detail.append("\(Guns.all[gi].key) part \(i) " + describe(base, i)) }
            for (e, what) in ups {
                let extra = Guns.upgradeParts(gi, Enchant.pack([(e, 1)]), magOut: false)
                guard !extra.isEmpty else { continue }
                let all = base + extra
                for i in loose(all) where i >= base.count {
                    bad.append("\(Guns.all[gi].key) \(what) part \(i - base.count)")
                    detail.append("\(Guns.all[gi].key) \(what) part \(i - base.count) " + describe(all, i))
                }
            }
        }
        for line in detail { print("gunfittings: " + line) }
        print("gunfittings: \(bad.isEmpty ? "every held gun part and upgrade fitting touches the gun" : "loose: " + bad.joined(separator: ", "))")
        check(bad.isEmpty, "P499: no held gun part or upgrade fitting floats clear of the gun (\(bad.count) loose)")
    }
}
