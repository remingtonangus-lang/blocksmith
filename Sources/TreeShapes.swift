import Foundation

// P406 (Oct 22 22:05-22:24): "the trees should have their own types... you can paste the same type over and over again,
// but there should be different shapes of tree types that are not algorithmically generated"; "a lot of these trees
// are really fucked up" (stubs that look like 'supposed to be a branch', trunks 'turning into three logs each').
// Every living tree is now one of a few designs per species, drawn after real trees (a clear bole, limbs that carry the
// crown, the crown), pasted whole: turned a quarter at a time or mirrored, its bole now and then a block taller. A
// design looks the same wherever it grows (its crown's rough edge is part of the design, not the world position).
// `questcheck --render X --tree-shots DIR` draws every design (the contact sheet).
struct TreeShape {
    let name: String
    let id: UInt32              // (Nov 15: unique in the catalogue; it also seeds the crown's rough edge)
    let logs: [IVec3]           // trunk and limbs, from the foot (0, 0, 0) up
    let leaves: [IVec3]
    let roots: [IVec3]          // (mangrove roots: drawn in the root block)
    let rootTips: [IVec3]       // (mangrove: root ends that reach on down to the mud)
    let bole: Int               // the clear trunk under the first limb or tier: placement lengthens it by 0...stretch
    let stretch: Int
    let wide: Bool              // a 2x2 trunk at x 0...1, z 0...1 (turned about its middle)
    let top: Int                // the trunk's highest log
}

struct TreeDraft {
    let id: UInt32
    var logs = Set<IVec3>(), leaves = Set<IVec3>(), roots = Set<IVec3>(), tips: [IVec3] = []

    mutating func trunk(_ h: Int, wide: Bool = false, x: Int = 0, z: Int = 0, from y0: Int = 0) {
        for y in y0..<(y0 + h) {
            logs.insert(IVec3(x, y, z))
            if wide { logs.insert(IVec3(x + 1, y, z)); logs.insert(IVec3(x, y, z + 1)); logs.insert(IVec3(x + 1, y, z + 1)) }
        }
    }
    mutating func log(_ x: Int, _ y: Int, _ z: Int) { logs.insert(IVec3(x, y, z)) }
    mutating func leaf(_ x: Int, _ y: Int, _ z: Int) { leaves.insert(IVec3(x, y, z)) }
    // A limb from the log at (x, y, z) heading (dx, dz) for `len` steps, rising `rise` overall, each log touching the
    // last (it climbs before it steps: never a gap). Returns the tip.
    @discardableResult
    mutating func limb(_ x: Int, _ y: Int, _ z: Int, _ dx: Float, _ dz: Float, _ len: Int, rise: Int) -> IVec3 {
        var tip = IVec3(x, y, z)
        for i in thru(1, max(1, len)) {
            let t = Float(i)
            let lx = x + Int((dx * t).rounded()), lz = z + Int((dz * t).rounded())
            let ly = y + Int((Float(rise) * t / Float(max(1, len))).rounded())
            if ly > tip.y { for yy in (tip.y + 1)...ly { logs.insert(IVec3(tip.x, yy, tip.z)) } }
            logs.insert(IVec3(lx, ly, lz))
            tip = IVec3(lx, ly, lz)
        }
        return tip
    }
    // A leafy ellipsoid round (cx, cy, cz); its edge roughened by a fixed hash of the cell and the design.
    mutating func crown(_ cx: Float, _ cy: Float, _ cz: Float, _ rx: Float, _ ry: Float) {
        let ix = Int(rx.rounded(.up)) + 1, iy = Int(ry.rounded(.up)) + 1
        let bx = Int(cx.rounded(.down)), by = Int(cy.rounded(.down)), bz = Int(cz.rounded(.down))
        for y in (by - iy)...(by + iy) { for z in (bz - ix)...(bz + ix) { for x in (bx - ix)...(bx + ix) {
            let dx = Float(x) - cx, dy = Float(y) - cy, dz = Float(z) - cz
            let e: Float = (dx * dx + dz * dz) / (rx * rx) + dy * dy / (ry * ry)
            let rough: Float = (hashf(x, y, z, 0x7AEE ^ id) - 0.5) * 0.3
            if e <= 1 + rough { leaves.insert(IVec3(x, y, z)) }
        } } }
    }
    mutating func crown(_ c: IVec3, _ rx: Float, _ ry: Float) { crown(Float(c.x), Float(c.y), Float(c.z), rx, ry) }
    // One round layer of a conifer or a flat crown: radius r round (cx, cz) (0.5, 0.5 on a 2x2 trunk); `plus`: just the
    // trunk's four neighbours (a spire's tip).
    mutating func tier(_ y: Int, _ r: Int, cx: Float = 0, cz: Float = 0, plus: Bool = false) {
        let bx = Int(cx.rounded(.down)), bz = Int(cz.rounded(.down))
        let lim: Float = plus ? 1 : Float(r * r + 1)
        for z in (bz - r - 1)...(bz + r + 1) { for x in (bx - r - 1)...(bx + r + 1) {
            let dx = Float(x) - cx, dz = Float(z) - cz
            if dx * dx + dz * dz <= lim { leaves.insert(IVec3(x, y, z)) }
        } }
    }
    // A flat square of leaves round (x, z), its corners cut (an acacia's umbrella).
    mutating func disk(_ y: Int, _ x: Int, _ z: Int, _ r: Int) {
        for dz in -r...r { for dx in -r...r where !(abs(dx) == r && abs(dz) == r) { leaves.insert(IVec3(x + dx, y, z + dz)) } }
    }
    // A mangrove prop root from the trunk's foot out along (dx, dz), dropping a block a step; its end reaches the mud.
    mutating func propRoot(_ lift: Int, _ dx: Int, _ dz: Int, _ reach: Int) {
        for k in 0...reach { roots.insert(IVec3(dx * k, lift - k, dz * k)) }
        tips.append(IVec3(dx * reach, lift - reach, dz * reach))
    }
}

enum TreeShapes {
    static func make(_ name: String, _ id: UInt32, bole: Int, stretch: Int = 1, wide: Bool = false, _ f: (inout TreeDraft) -> Void) -> TreeShape {
        var d = TreeDraft(id: id)
        f(&d)
        func order(_ s: Set<IVec3>) -> [IVec3] { s.sorted { ($0.y, $0.z, $0.x) < ($1.y, $1.z, $1.x) } }
        return TreeShape(name: name, id: id, logs: order(d.logs), leaves: order(d.leaves.subtracting(d.logs).subtracting(d.roots)),
                         roots: order(d.roots.subtracting(d.logs)), rootTips: d.tips, bole: bole, stretch: stretch, wide: wide,
                         top: d.logs.map { $0.y }.max() ?? 0)
    }

    // MARK: The designs

    // Oaks: an English oak (three big limbs off a short bole), a broad field oak, a tall woodland oak drawn up by its
    // neighbours, and a young one.
    // P433 (Remington, Oct 24 21:01: "those trees with the weird second tree coming off close to its base? Get rid of
    // that and just anything like it"): no design has a second stem springing from a trunk's side or a fork low on the
    // bole (the leaning oak, forked oak, twin birches, kinked birch, leaning swamp oak and the palm's kink are gone):
    // every tree is one trunk from the ground, its limbs well up it.
    static let oaks: [TreeShape] = [
        make("English oak", 1, bole: 3) { d in
            d.trunk(6)
            do { let t = d.limb(0, 3, 0, 1, 0, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.3, 1.6) }
            do { let t = d.limb(0, 3, 0, -0.7, 0.7, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.2, 1.6) }
            do { let t = d.limb(0, 4, 0, -0.3, -1, 2, rise: 1); d.crown(t + IVec3(0, 1, 0), 2.0, 1.5) }
            d.crown(0, 6.5, 0, 2.8, 2.0)
        },
        make("field oak", 2, bole: 2) { d in
            d.trunk(5)
            do { let t = d.limb(0, 2, 0, 1, 0.2, 4, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.3, 1.5) }
            do { let t = d.limb(0, 2, 0, -1, -0.2, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.3, 1.5) }
            do { let t = d.limb(0, 3, 0, 0.2, 1, 3, rise: 1); d.crown(t + IVec3(0, 1, 0), 2.2, 1.4) }
            do { let t = d.limb(0, 3, 0, -0.2, -1, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.2, 1.4) }
            d.crown(0, 5.5, 0, 2.6, 1.8)
        },
        make("woodland oak", 3, bole: 5) { d in
            d.trunk(9)
            do { let t = d.limb(0, 5, 0, 1, 0, 1, rise: 1); d.crown(t + IVec3(1, 0, 0), 1.6, 1.4) }
            do { let t = d.limb(0, 6, 0, -1, 0.3, 1, rise: 1); d.crown(t + IVec3(-1, 0, 0), 1.5, 1.3) }
            d.crown(0, 8.5, 0, 2.3, 2.8)
        },
        make("young oak", 6, bole: 2) { d in
            d.trunk(5)
            d.crown(0, 4.5, 0, 2.0, 2.0)
        },
        // Nov 15 (the catalogue of 100): more oaks, every one a single trunk with its limbs at or above the bole.
        make("round oak", 201, bole: 3) { d in
            d.trunk(6)
            do { let t = d.limb(0, 3, 0, 1, 0.5, 2, rise: 1); d.crown(t + IVec3(0, 1, 0), 2.0, 1.4) }
            do { let t = d.limb(0, 3, 0, -1, -0.5, 2, rise: 1); d.crown(t + IVec3(0, 1, 0), 2.0, 1.4) }
            d.crown(0, 6, 0, 2.9, 2.2)
        },
        make("tall oak", 202, bole: 5) { d in
            d.trunk(10)
            do { let t = d.limb(0, 6, 0, 1, 0, 2, rise: 2); d.crown(t + IVec3(0, 1, 0), 1.8, 1.3) }
            do { let t = d.limb(0, 7, 0, -0.6, -0.8, 2, rise: 1); d.crown(t + IVec3(0, 1, 0), 1.8, 1.3) }
            d.crown(0, 10, 0, 2.4, 2.4)
        },
        make("wide oak", 203, bole: 3) { d in
            d.trunk(5)
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] as [(Float, Float)] {
                let t = d.limb(0, 3, 0, dx, dz, 4, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.2, 1.4)
            }
            d.crown(0, 5.5, 0, 2.4, 1.6)
        },
        make("oak with a high limb", 204, bole: 4) { d in
            d.trunk(8)
            do { let t = d.limb(0, 5, 0, 1, 0.3, 3, rise: 3); d.crown(t + IVec3(0, 1, 0), 2.0, 1.5) }
            d.crown(0, 8, 0, 2.5, 2.0)
        },
        make("parkland oak", 205, bole: 3) { d in
            d.trunk(7)
            do { let t = d.limb(0, 3, 0, 0.7, 0.7, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.2, 1.5) }
            do { let t = d.limb(0, 4, 0, -0.7, 0.7, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.2, 1.5) }
            do { let t = d.limb(0, 4, 0, 0, -1, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.2, 1.5) }
            d.crown(0, 7, 0, 2.7, 2.0)
        },
        make("hedgerow oak", 206, bole: 2) { d in
            d.trunk(5)
            do { let t = d.limb(0, 2, 0, 1, 0, 2, rise: 1); d.crown(t + IVec3(0, 1, 0), 1.8, 1.4) }
            do { let t = d.limb(0, 3, 0, -1, 0, 2, rise: 1); d.crown(t + IVec3(0, 1, 0), 1.8, 1.4) }
            d.crown(0, 5, 0, 2.2, 1.8)
        },
        make("oak sapling", 207, bole: 2) { d in
            d.trunk(4)
            d.crown(0, 4, 0, 1.6, 1.6)
        },
        make("broad old oak", 208, bole: 3) { d in
            d.trunk(7)
            do { let t = d.limb(0, 3, 0, 1, 0, 4, rise: 3); d.crown(t + IVec3(0, 1, 0), 2.4, 1.6) }
            do { let t = d.limb(0, 3, 0, -1, 0.3, 4, rise: 3); d.crown(t + IVec3(0, 1, 0), 2.4, 1.6) }
            do { let t = d.limb(0, 4, 0, 0.3, 1, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.4, 1.6) }
            do { let t = d.limb(0, 4, 0, -0.3, -1, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.4, 1.6) }
            d.crown(0, 7.5, 0, 3.0, 2.2)
        },
    ]
    // Birches: slender, the crown high and narrow; one with a side limb.
    static let birches: [TreeShape] = [
        make("silver birch", 11, bole: 4) { d in
            d.trunk(8)
            d.crown(0, 7, 0, 1.8, 2.6)
        },
        make("birch with a limb", 12, bole: 4) { d in
            d.trunk(9)
            do { let t = d.limb(0, 5, 0, 1, 0, 1, rise: 1); d.crown(t + IVec3(1, 1, 0), 1.4, 1.4) }
            d.crown(0, 8, 0, 1.7, 2.8)
        },
        make("paper birch", 211, bole: 5) { d in
            d.trunk(9)
            d.crown(0, 8, 0, 1.6, 3.0)
        },
        make("birch with two limbs", 212, bole: 4) { d in
            d.trunk(9)
            do { let t = d.limb(0, 5, 0, 1, 0, 1, rise: 1); d.crown(t + IVec3(1, 1, 0), 1.3, 1.3) }
            do { let t = d.limb(0, 6, 0, -1, 0, 1, rise: 1); d.crown(t + IVec3(-1, 1, 0), 1.3, 1.3) }
            d.crown(0, 8, 0, 1.7, 2.6)
        },
        make("young birch", 213, bole: 3) { d in
            d.trunk(6)
            d.crown(0, 5.5, 0, 1.5, 2.0)
        },
        make("broad birch", 214, bole: 4) { d in
            d.trunk(8)
            d.crown(0, 7, 0, 2.2, 2.4)
        },
    ]
    static let tallBirches: [TreeShape] = [
        make("tall birch", 15, bole: 8) { d in
            d.trunk(13)
            d.crown(0, 12, 0, 1.8, 3.4)
        },
        make("tall birch with limbs", 16, bole: 8) { d in
            d.trunk(14)
            do { let t = d.limb(0, 9, 0, 1, 0, 1, rise: 1); d.crown(t + IVec3(1, 1, 0), 1.4, 1.5) }
            do { let t = d.limb(0, 10, 0, -1, 0, 1, rise: 1); d.crown(t + IVec3(-1, 1, 0), 1.4, 1.5) }
            d.crown(0, 13, 0, 1.7, 3.0)
        },
        make("very tall birch", 216, bole: 9) { d in
            d.trunk(15)
            d.crown(0, 13.5, 0, 1.7, 3.6)
        },
        make("tall birch, broad crown", 217, bole: 8) { d in
            d.trunk(13)
            do { let t = d.limb(0, 9, 0, 0, 1, 1, rise: 1); d.crown(t + IVec3(0, 1, 1), 1.4, 1.4) }
            d.crown(0, 12, 0, 2.1, 3.0)
        },
    ]
    // Spruces: tiered cones (radii from the tip down), a narrow alpine one, a broad one and an old one bare below.
    static func cone(_ d: inout TreeDraft, _ h: Int, _ radii: [Int]) {
        d.trunk(h)
        d.leaf(0, h, 0)
        for (k, r) in radii.enumerated() { d.tier(h - 1 - k, r, plus: k == 0) }
    }
    static let spruces: [TreeShape] = [
        make("Norway spruce", 21, bole: 2) { d in cone(&d, 8, [1, 2, 1, 2, 3, 2]) },
        make("alpine spruce", 22, bole: 2) { d in cone(&d, 10, [1, 1, 1, 2, 1, 2, 2, 2]) },
        make("broad spruce", 23, bole: 1) { d in cone(&d, 7, [1, 2, 2, 3, 2, 3]) },
        make("old spruce", 24, bole: 5) { d in cone(&d, 11, [1, 2, 1, 2, 2, 3]) },
        make("young spruce", 221, bole: 1) { d in cone(&d, 5, [1, 1, 2, 2]) },
        make("slender spruce", 222, bole: 3) { d in cone(&d, 11, [1, 1, 2, 1, 2, 2, 2, 1]) },
        make("full spruce", 223, bole: 1) { d in cone(&d, 9, [1, 2, 2, 3, 2, 3, 3, 2]) },
        make("tall spruce", 224, bole: 4) { d in cone(&d, 13, [1, 1, 2, 1, 2, 2, 3, 2, 3]) },
        make("stout spruce", 225, bole: 1) { d in cone(&d, 6, [1, 2, 3, 2, 3]) },
    ]
    // Pines: long bare trunks, the crown in a few tufts at the top.
    static let pines: [TreeShape] = [
        make("Scots pine", 31, bole: 5) { d in cone(&d, 10, [1, 2, 1, 2, 1]) },
        make("tall pine", 32, bole: 6) { d in cone(&d, 12, [1, 1, 2, 1, 2, 1, 2]) },
        make("lodgepole pine", 33, bole: 7) { d in cone(&d, 11, [1, 2, 2, 1]) },
        make("red pine", 231, bole: 6) { d in cone(&d, 11, [1, 2, 2, 1, 2]) },
        make("young pine", 232, bole: 3) { d in cone(&d, 7, [1, 2, 1, 2]) },
        make("stone pine", 233, bole: 6) { d in
            d.trunk(9)
            d.leaf(0, 9, 0)
            d.tier(8, 2); d.tier(7, 3); d.tier(6, 2)
        },
        make("black pine", 234, bole: 5) { d in cone(&d, 10, [1, 2, 2, 2, 1]) },
    ]
    // The giant conifers on 2x2 trunks: a long cone, or a crown only at the top.
    static func megaCone(_ d: inout TreeDraft, _ h: Int, from start: Int) {
        d.trunk(h, wide: true)
        for y in start...(h + 1) {
            let fromTop = h + 1 - y
            d.tier(y, min(5, fromTop / 2 + fromTop % 2), cx: 0.5, cz: 0.5)
        }
    }
    static let megaSpruces: [TreeShape] = [
        make("giant spruce", 41, bole: 6, stretch: 2, wide: true) { d in megaCone(&d, 18, from: 6) },
        make("giant spruce, tall", 42, bole: 8, stretch: 2, wide: true) { d in megaCone(&d, 22, from: 8) },
        make("giant spruce, broad", 241, bole: 5, stretch: 2, wide: true) { d in megaCone(&d, 16, from: 5) },
    ]
    static let megaPines: [TreeShape] = [
        make("giant pine", 43, bole: 13, stretch: 2, wide: true) { d in megaCone(&d, 18, from: 13) },
        make("giant pine, tall", 44, bole: 16, stretch: 2, wide: true) { d in megaCone(&d, 22, from: 16) },
        make("giant pine, short", 243, bole: 11, stretch: 2, wide: true) { d in megaCone(&d, 16, from: 11) },
    ]
    // Jungle trees: a straight trunk under a wide crown, one with a limb, a short one; the giants on 2x2 trunks with
    // limbs up the trunk each holding its own crown.
    static let jungles: [TreeShape] = [
        make("jungle tree", 51, bole: 4) { d in
            d.trunk(8)
            d.crown(0, 8, 0, 2.5, 1.8)
        },
        make("jungle tree with a limb", 52, bole: 4) { d in
            d.trunk(10)
            do { let t = d.limb(0, 6, 0, 1, 0, 2, rise: 1); d.crown(t + IVec3(0, 1, 0), 1.8, 1.2) }
            d.crown(0, 10, 0, 2.4, 1.8)
        },
        make("short jungle tree", 53, bole: 3) { d in
            d.trunk(6)
            d.crown(0, 6, 0, 2.2, 1.6)
        },
        make("tall jungle tree", 251, bole: 6) { d in
            d.trunk(12)
            d.crown(0, 12, 0, 2.6, 2.0)
        },
        make("jungle tree with two limbs", 252, bole: 5) { d in
            d.trunk(11)
            do { let t = d.limb(0, 6, 0, 1, 0, 2, rise: 1); d.crown(t + IVec3(0, 1, 0), 1.8, 1.2) }
            do { let t = d.limb(0, 8, 0, -1, 0, 2, rise: 1); d.crown(t + IVec3(0, 1, 0), 1.8, 1.2) }
            d.crown(0, 11, 0, 2.4, 1.8)
        },
        make("broad jungle tree", 253, bole: 4) { d in
            d.trunk(9)
            d.crown(0, 9, 0, 3.0, 1.8)
        },
    ]
    static let megaJungles: [TreeShape] = [
        make("giant jungle tree", 54, bole: 7, stretch: 2, wide: true) { d in
            d.trunk(17, wide: true)
            do { let t = d.limb(1, 12, 0, 1, -0.5, 3, rise: 1); d.crown(t + IVec3(0, 1, 0), 2.4, 1.2) }
            do { let t = d.limb(0, 8, 1, -1, 0.5, 3, rise: 1); d.crown(t + IVec3(0, 1, 0), 2.4, 1.2) }
            d.crown(0.5, 17, 0.5, 4.2, 2.0)
        },
        make("giant jungle tree, tall", 55, bole: 7, stretch: 2, wide: true) { d in
            d.trunk(22, wide: true)
            do { let t = d.limb(1, 17, 1, 1, 0.5, 3, rise: 1); d.crown(t + IVec3(0, 1, 0), 2.4, 1.2) }
            do { let t = d.limb(0, 13, 0, -1, -0.5, 3, rise: 1); d.crown(t + IVec3(0, 1, 0), 2.4, 1.2) }
            do { let t = d.limb(1, 9, 0, 0.5, -1, 3, rise: 1); d.crown(t + IVec3(0, 1, 0), 2.3, 1.2) }
            d.crown(0.5, 22, 0.5, 4.3, 2.0)
        },
        make("giant jungle tree, spreading", 255, bole: 7, stretch: 2, wide: true) { d in
            d.trunk(18, wide: true)
            do { let t = d.limb(1, 13, 1, 1, 1, 3, rise: 1); d.crown(t + IVec3(0, 1, 0), 2.4, 1.2) }
            do { let t = d.limb(0, 10, 0, -1, -1, 3, rise: 1); d.crown(t + IVec3(0, 1, 0), 2.4, 1.2) }
            d.crown(0.5, 18, 0.5, 4.6, 2.0)
        },
    ]
    static let jungleBushes: [TreeShape] = [
        make("jungle bush", 56, bole: 0, stretch: 0) { d in d.trunk(1); d.crown(0, 1, 0, 2.4, 1.3) },
        make("low jungle bush", 57, bole: 0, stretch: 0) { d in d.trunk(1); d.crown(0.5, 1, 0, 2.0, 1.1) },
        make("wide jungle bush", 256, bole: 0, stretch: 0) { d in d.trunk(1); d.crown(0, 1, 0, 2.8, 1.2) },
    ]
    // Acacias: trunks that bend out under flat umbrella crowns.
    static let acacias: [TreeShape] = [
        make("acacia, two crowns", 61, bole: 2) { d in
            d.trunk(3)
            let a = d.limb(0, 2, 0, 1, 0, 2, rise: 2)
            d.log(a.x, a.y + 1, a.z)
            d.disk(a.y + 2, a.x, a.z, 3); d.disk(a.y + 3, a.x, a.z, 1)
            let b = d.limb(0, 2, 0, -1, 0, 2, rise: 1)
            d.disk(b.y + 1, b.x, b.z, 2)
        },
        make("acacia, one crown", 62, bole: 3) { d in
            d.trunk(4)
            let a = d.limb(0, 3, 0, 0.7, 0.7, 2, rise: 2)
            d.log(a.x, a.y + 1, a.z)
            d.disk(a.y + 2, a.x, a.z, 3); d.disk(a.y + 3, a.x, a.z, 1)
        },
        make("acacia, stepped", 63, bole: 1) { d in
            d.trunk(2)
            let a = d.limb(0, 1, 0, 1, 0, 3, rise: 3)
            d.disk(a.y + 1, a.x, a.z, 3); d.disk(a.y + 2, a.x, a.z, 1)
            let b = d.limb(0, 1, 0, 0, -1, 2, rise: 2)
            d.disk(b.y + 1, b.x, b.z, 2)
        },
        make("acacia, wide", 261, bole: 2) { d in
            d.trunk(3)
            let a = d.limb(0, 2, 0, 0, 1, 2, rise: 2)
            d.log(a.x, a.y + 1, a.z)
            d.disk(a.y + 2, a.x, a.z, 3); d.disk(a.y + 3, a.x, a.z, 2)
        },
        make("acacia, three crowns", 262, bole: 2) { d in
            d.trunk(3)
            let a = d.limb(0, 2, 0, 1, 0, 2, rise: 2)
            d.disk(a.y + 1, a.x, a.z, 2)
            let b = d.limb(0, 2, 0, -1, 0.5, 2, rise: 1)
            d.disk(b.y + 1, b.x, b.z, 2)
            let c = d.limb(0, 2, 0, 0, -1, 2, rise: 2)
            d.disk(c.y + 1, c.x, c.z, 2)
        },
        make("acacia, tall", 263, bole: 4) { d in
            d.trunk(5)
            let a = d.limb(0, 4, 0, 0.7, -0.7, 2, rise: 2)
            d.log(a.x, a.y + 1, a.z)
            d.disk(a.y + 2, a.x, a.z, 3); d.disk(a.y + 3, a.x, a.z, 1)
        },
        make("acacia, low", 264, bole: 1) { d in
            d.trunk(2)
            let a = d.limb(0, 1, 0, -1, 0, 2, rise: 1)
            d.disk(a.y + 1, a.x, a.z, 3); d.disk(a.y + 2, a.x, a.z, 1)
        },
    ]
    // Dark oaks: 2x2 trunks under broad, flat, heavy crowns.
    static func flatCrown(_ d: inout TreeDraft, _ top: Int, _ radii: [Int]) {
        for (k, r) in radii.enumerated() { d.tier(top - 1 + k, r, cx: 0.5, cz: 0.5) }
    }
    static let darkOaks: [TreeShape] = [
        make("dark oak", 71, bole: 4, wide: true) { d in d.trunk(7, wide: true); flatCrown(&d, 7, [3, 4, 2]) },
        make("dark oak with limbs", 72, bole: 3, wide: true) { d in
            d.trunk(6, wide: true)
            do { let t = d.limb(1, 4, 0, 1, -0.5, 2, rise: 1); d.crown(t + IVec3(0, 1, 0), 2.3, 1.2) }
            do { let t = d.limb(0, 4, 1, -1, 0.5, 2, rise: 1); d.crown(t + IVec3(0, 1, 0), 2.3, 1.2) }
            flatCrown(&d, 6, [3, 3, 2])
        },
        make("tall dark oak", 73, bole: 5, wide: true) { d in d.trunk(8, wide: true); flatCrown(&d, 8, [3, 3, 2]) },
        make("low dark oak", 271, bole: 3, wide: true) { d in d.trunk(6, wide: true); flatCrown(&d, 6, [3, 4, 3, 1]) },
        make("dark oak with broad limbs", 272, bole: 4, wide: true) { d in
            d.trunk(7, wide: true)
            do { let t = d.limb(1, 5, 0, 1, 0, 3, rise: 1); d.crown(t + IVec3(0, 1, 0), 2.3, 1.2) }
            do { let t = d.limb(0, 5, 1, -1, 0, 3, rise: 1); d.crown(t + IVec3(0, 1, 0), 2.3, 1.2) }
            flatCrown(&d, 7, [3, 4, 2])
        },
        make("dark oak, tall crown", 273, bole: 5, wide: true) { d in d.trunk(9, wide: true); flatCrown(&d, 9, [3, 3, 3, 2]) },
    ]
    static let paleOaks: [TreeShape] = [
        make("ashbark", 74, bole: 4, wide: true) { d in d.trunk(7, wide: true); flatCrown(&d, 7, [3, 3, 2]) },
        make("ashbark with a limb", 75, bole: 4, wide: true) { d in
            d.trunk(8, wide: true)
            do { let t = d.limb(1, 5, 1, 1, 1, 2, rise: 1); d.crown(t + IVec3(0, 1, 0), 2.2, 1.2) }
            flatCrown(&d, 8, [3, 3, 2])
        },
        make("low ashbark", 274, bole: 3, wide: true) { d in d.trunk(6, wide: true); flatCrown(&d, 6, [3, 4, 2]) },
        make("ashbark with two limbs", 275, bole: 4, wide: true) { d in
            d.trunk(8, wide: true)
            do { let t = d.limb(1, 5, 1, 1, 1, 2, rise: 1); d.crown(t + IVec3(0, 1, 0), 2.2, 1.2) }
            do { let t = d.limb(0, 6, 0, -1, -1, 2, rise: 1); d.crown(t + IVec3(0, 1, 0), 2.2, 1.2) }
            flatCrown(&d, 8, [3, 3, 2])
        },
    ]
    // Swamp oaks: short trunks under wide, low crowns (vines hung after).
    static let swampOaks: [TreeShape] = [
        make("swamp oak", 81, bole: 2) { d in
            d.trunk(5)
            for (k, r) in [3, 3, 2, 2].enumerated() { d.disk(2 + k, 0, 0, r) }
        },
        make("broad swamp oak", 281, bole: 2) { d in
            d.trunk(5)
            for (k, r) in [3, 4, 3, 2].enumerated() { d.disk(2 + k, 0, 0, r) }
        },
        make("tall swamp oak", 282, bole: 3) { d in
            d.trunk(6)
            for (k, r) in [3, 3, 2, 2].enumerated() { d.disk(3 + k, 0, 0, r) }
        },
        make("swamp oak with a limb", 283, bole: 3) { d in
            d.trunk(6)
            let t = d.limb(0, 3, 0, 1, 0, 2, rise: 1)
            d.disk(t.y + 1, t.x, t.z, 2)
            for (k, r) in [3, 3, 2, 1].enumerated() { d.disk(3 + k, 0, 0, r) }
        },
    ]
    // Mangroves. P499 (Oct 30 19:58 in a mangrove swamp: "all these trees have got to go... looks like a bunch of spider
    // trees... just get rid of the roots, make them look like normal trees"): a straight trunk from the mud (through
    // the water) under a round crown, a few roots gathered at its foot under the water; no arching prop roots.
    static let mangroves: [TreeShape] = [
        make("mangrove", 91, bole: 3) { d in
            d.trunk(8)
            d.tips.append(IVec3(0, 0, 0))
            d.crown(0, 8, 0, 3.0, 2.0)
        },
        make("mangrove, tall", 92, bole: 3) { d in
            d.trunk(9)
            d.tips.append(IVec3(0, 0, 0))
            d.crown(0, 9, 0, 2.6, 1.8)
        },
        make("mangrove, broad", 291, bole: 3) { d in
            d.trunk(7)
            d.tips.append(IVec3(0, 0, 0))
            d.crown(0, 7, 0, 3.3, 1.8)
        },
        make("mangrove, short", 292, bole: 2) { d in
            d.trunk(6)
            d.tips.append(IVec3(0, 0, 0))
            d.crown(0, 6, 0, 2.6, 1.7)
        },
    ]
    // Cherries: a short trunk splitting into arching limbs under wide pink crowns.
    static let cherries: [TreeShape] = [
        make("cherry", 101, bole: 3) { d in
            d.trunk(4)
            do { let t = d.limb(0, 3, 0, 1, 0, 3, rise: 3); d.crown(t + IVec3(0, 1, 0), 3.0, 1.8) }
            do { let t = d.limb(0, 3, 0, -1, 0, 2, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.6, 1.6) }
        },
        make("cherry, crossed", 102, bole: 3) { d in
            d.trunk(4)
            do { let t = d.limb(0, 3, 0, 0.7, 0.7, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.8, 1.7) }
            do { let t = d.limb(0, 3, 0, -0.7, -0.7, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.8, 1.7) }
        },
        make("cherry, weeping", 103, bole: 3) { d in
            d.trunk(5)
            do { let t = d.limb(0, 3, 0, 1, 0, 2, rise: 1); d.crown(t + IVec3(0, 0, 0), 2.6, 1.6) }
            d.crown(0, 5.5, 0, 2.6, 1.6)
        },
        make("cherry, three limbs", 301, bole: 3) { d in
            d.trunk(4)
            do { let t = d.limb(0, 3, 0, 1, 0, 3, rise: 3); d.crown(t + IVec3(0, 1, 0), 2.6, 1.6) }
            do { let t = d.limb(0, 3, 0, -0.5, 0.9, 2, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.4, 1.5) }
            do { let t = d.limb(0, 3, 0, -0.5, -0.9, 2, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.4, 1.5) }
        },
        make("cherry, tall", 302, bole: 4) { d in
            d.trunk(6)
            do { let t = d.limb(0, 4, 0, 1, 0.3, 2, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.4, 1.5) }
            d.crown(0, 6.5, 0, 2.6, 1.7)
        },
    ]
    // Palms: a slim straight trunk and a star of fronds drooping at their tips. (P433: the one-block kink is gone.)
    static func palm(_ d: inout TreeDraft, _ h: Int, bend: Int) {
        d.trunk(h)
        let tx = 0, top = h
        d.leaf(tx, top, 0)
        for (fx, fz) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)] {
            let reach = fx != 0 && fz != 0 ? 3 : 4
            for s in 1...reach {
                let droop = s <= 2 ? 0 : s - 2
                d.leaf(tx + fx * s, top - droop, fz * s)
                if s == reach { d.leaf(tx + fx * s, top - droop - 1, fz * s) }
            }
        }
    }
    static let palms: [TreeShape] = [
        make("saltpalm", 111, bole: 3) { d in palm(&d, 7, bend: 3) },
        make("saltpalm, tall", 112, bole: 4) { d in palm(&d, 9, bend: 5) },
        make("saltpalm, short", 113, bole: 2) { d in palm(&d, 6, bend: 2) },
        make("saltpalm, slender", 311, bole: 3) { d in palm(&d, 8, bend: 0) },
        make("saltpalm, very tall", 312, bole: 5) { d in palm(&d, 10, bend: 0) },
    ]
    // The rare old giants: a 2x2 trunk, heavy limbs all round, a broad crown.
    static let ancientOaks: [TreeShape] = [
        make("ancient oak", 121, bole: 6, wide: true) { d in
            d.trunk(10, wide: true)
            do { let t = d.limb(1, 7, 0, 1, -0.4, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.5, 1.8) }
            do { let t = d.limb(0, 6, 1, -1, 0.4, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.5, 1.8) }
            do { let t = d.limb(1, 8, 1, 0.4, 1, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.4, 1.8) }
            do { let t = d.limb(0, 7, 0, -0.4, -1, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.4, 1.8) }
            d.crown(0.5, 11, 0.5, 3.0, 2.2)
        },
        make("ancient oak, spreading", 122, bole: 5, wide: true) { d in
            d.trunk(9, wide: true)
            do { let t = d.limb(1, 5, 1, 1, 1, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.5, 1.7) }
            do { let t = d.limb(0, 6, 0, -1, -1, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.5, 1.7) }
            do { let t = d.limb(1, 6, 0, 1, -1, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.4, 1.7) }
            do { let t = d.limb(0, 5, 1, -1, 1, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.4, 1.7) }
            do { let t = d.limb(1, 7, 0, 1, 0, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.3, 1.6) }
            d.crown(0.5, 10, 0.5, 3.0, 2.0)
        },
        make("ancient oak, tall", 321, bole: 7, wide: true) { d in
            d.trunk(12, wide: true)
            do { let t = d.limb(1, 8, 0, 1, -0.4, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.4, 1.7) }
            do { let t = d.limb(0, 9, 1, -1, 0.4, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.4, 1.7) }
            do { let t = d.limb(1, 10, 1, 0.4, 1, 3, rise: 2); d.crown(t + IVec3(0, 1, 0), 2.4, 1.7) }
            d.crown(0.5, 13, 0.5, 3.0, 2.4)
        },
    ]
    // Dead snags: a broken trunk, at most one whole bare limb that turns up at its end (no stubs).
    static let deadOaks: [TreeShape] = [
        make("dead oak", 131, bole: 2) { d in
            d.trunk(5)
            let a = d.limb(0, 3, 0, 1, 0, 2, rise: 1)
            d.log(a.x, a.y + 1, a.z)
        },
        make("dead oak, broken", 132, bole: 2) { d in d.trunk(4) },
        make("dead oak, tall", 331, bole: 3) { d in
            d.trunk(7)
            let a = d.limb(0, 4, 0, -1, 0, 2, rise: 1)
            d.log(a.x, a.y + 1, a.z)
        },
    ]
    static let deadSpruces: [TreeShape] = [
        make("dead spruce", 133, bole: 3) { d in d.trunk(6) },
        make("dead spruce, broken", 134, bole: 2) { d in d.trunk(4) },
        make("dead spruce, tall", 333, bole: 4) { d in d.trunk(8) },
    ]

    // Every design (the contact sheet).
    static var all: [(String, TreeKind, [TreeShape])] {
        [("oak", .oak, oaks), ("birch", .birch, birches), ("tall birch", .tallBirch, tallBirches), ("spruce", .spruce, spruces),
         ("pine", .pine, pines), ("giant spruce", .megaSpruce, megaSpruces), ("giant pine", .megaPine, megaPines),
         ("jungle", .jungle, jungles), ("giant jungle", .megaJungle, megaJungles), ("jungle bush", .jungleBush, jungleBushes),
         ("acacia", .acacia, acacias), ("dark oak", .darkOak, darkOaks), ("ashbark", .paleOak, paleOaks),
         ("swamp oak", .swampOak, swampOaks), ("mangrove", .mangrove, mangroves), ("cherry", .cherry, cherries),
         ("saltpalm", .saltpalm, palms), ("ancient oak", .ancientOak, ancientOaks), ("dead oak", .deadOak, deadOaks),
         ("dead spruce", .deadSpruce, deadSpruces)]
    }

    // Nov 15 (Fable, the catalogue of 100): every design in a fixed order (the species in `all`'s order, each list's
    // designs in theirs). New designs go at the end of a species' list, so the ones a kind already picks keep their place.
    static let catalogue: [TreeShape] = all.flatMap { $0.2 }

    // What is wrong with the catalogue (empty: nothing): 100 designs, names and ids unique; every log joined to the foot
    // through logs (26 neighbours); every limb or trunk tip (a log with one log beside it, above the foot) touching
    // leaves, bare snags aside; nothing off the trunk under the bole (no low fork or second stem: placement lengthens
    // the bole, and a limb under it would be left behind); everything within the 7-block placement margin.
    static func catalogueProblems() -> [String] {
        var bad: [String] = []
        let cat = catalogue
        if cat.count != 100 { bad.append("\(cat.count) designs, not 100") }
        var names = Set<String>(), ids = Set<UInt32>()
        let dead: Set<String> = Set((deadOaks + deadSpruces).map { $0.name })
        for s in cat {
            if !names.insert(s.name).inserted { bad.append("\(s.name): name twice") }
            if !ids.insert(s.id).inserted { bad.append("\(s.name): id \(s.id) twice") }
            let logs = Set(s.logs), leaves = Set(s.leaves)
            func near(_ p: IVec3, _ set: Set<IVec3>) -> Int {
                var n = 0
                for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 || dz != 0 {
                    if set.contains(IVec3(p.x + dx, p.y + dy, p.z + dz)) { n += 1 }
                } } }
                return n
            }
            var seen = Set(s.logs.filter { $0.y == 0 }), stack = Array(seen)
            while let p = stack.popLast() {
                for dy in -1...1 { for dz in -1...1 { for dx in -1...1 {
                    let q = IVec3(p.x + dx, p.y + dy, p.z + dz)
                    if logs.contains(q) && seen.insert(q).inserted { stack.append(q) }
                } } }
            }
            if seen.count != logs.count { bad.append("\(s.name): \(logs.count - seen.count) logs not joined to the foot") }
            if !dead.contains(s.name) {
                let bare = s.logs.filter { $0.y > 0 && near($0, logs) == 1 && near($0, leaves) == 0 }
                if !bare.isEmpty { bad.append("\(s.name): \(bare.count) bare tips (\(bare[0].x) \(bare[0].y) \(bare[0].z))") }
            }
            let c = s.wide ? 1 : 0
            let low = s.logs.filter { $0.y < s.bole && !((0...c).contains($0.x) && (0...c).contains($0.z)) }
            if !low.isEmpty { bad.append("\(s.name): \(low.count) logs off the trunk under the bole") }
            let far = (s.logs + s.leaves).filter { max(abs(2 * $0.x - c), abs(2 * $0.z - c)) > 14 + c }
            if !far.isEmpty { bad.append("\(s.name): \(far.count) blocks past the 7-block margin") }
        }
        return bad
    }

    // MARK: Litter (Nov 15, Fable's list: the kinds that still fell through to the old placer)

    // Woodland litter as designs, beside the catalogue of 100 (not counted in it): shrubs, stumps and fallen oaks. Each
    // pastes whole like a tree. A shrub is a leaf mound on the ground round one hidden log; a stump is a log, now and then
    // with a root flare and moss (its "leaves": moss carpet); a fallen oak is its stump and, two blocks off, a trunk
    // of bark-all-round wood lying along the ground (its "roots": oak wood), laid only where the ground under it holds
    // (buildLitter). BS_OLDLITTER=1: the old placer.
    static let oldLitter = ProcessInfo.processInfo.environment["BS_OLDLITTER"] == "1"
    static let oldLitterMoss = ProcessInfo.processInfo.environment["BS_OLDLITTERMOSS"] == "1"
    static let oldLitterLie = ProcessInfo.processInfo.environment["BS_OLDLITTERLIE"] == "1"
    static let oldShrubs = ProcessInfo.processInfo.environment["BS_OLDSHRUBS"] == "1"
    static let shrubs: [TreeShape] = [
        make("knee shrub", 401, bole: 1, stretch: 0) { d in d.log(0, 0, 0); d.crown(0.3, 0.4, 0, 1.5, 1.1) },
        make("spreading shrub", 402, bole: 1, stretch: 0) { d in d.log(0, 0, 0); d.crown(0.5, 0.3, 0.3, 2.2, 1.0) },
        make("round shrub", 403, bole: 1, stretch: 0) { d in d.log(0, 0, 0); d.crown(0, 0.6, 0, 1.6, 1.3) },
    ]
    static let stumps: [TreeShape] = [
        make("stump", 411, bole: 1, stretch: 0) { d in d.log(0, 0, 0) },
        make("mossy stump", 412, bole: 1, stretch: 0) { d in d.log(0, 0, 0); d.leaf(0, 1, 0) },
        make("rooted stump", 413, bole: 1, stretch: 0) { d in d.log(0, 0, 0); d.log(1, 0, 0); d.log(0, 0, -1) },
        make("old stump", 414, bole: 2, stretch: 0) { d in d.log(0, 0, 0); d.log(0, 1, 0); d.log(-1, 0, 0); d.leaf(0, 2, 0) },
    ]
    static let fallenOaks: [TreeShape] = [4, 5, 6].map { len in
        make("fallen oak \(len)", UInt32(420 + len), bole: 1, stretch: 0) { d in
            d.log(0, 0, 0)
            for i in 2..<(2 + len) { d.roots.insert(IVec3(i, 0, 0)) }
            for i in 2..<(2 + len) where hashf(i, len, 0, 0xFA11) < 0.3 { d.leaf(i, 1, 0) }
        }
    }
    static func litter(_ kind: TreeKind) -> [TreeShape]? {
        if oldLitter { return nil }
        switch kind {
        case .shrubOak, .shrubSpruce, .shrubAcacia: return shrubs
        case .stumpOak, .stumpSpruce, .stumpBirch: return stumps
        case .fallenOak: return fallenOaks
        default: return nil
        }
    }
    // A piece of litter at (x, y, z): its design, turn and mirror from the tree's rng. A fallen trunk's lengths are laid
    // only on held ground (solid, not leaves) and into air or plants, decided per block, so every chunk agrees; the moss
    // over a length only where that length lies.
    static func buildLitter(_ w: TreeWriter, _ kind: TreeKind, _ set: [TreeShape], _ x: Int, _ y: Int, _ z: Int, _ rng: inout SRng) {
        let s = set[rng.int(set.count)]
        let turn = rng.int(4), mirror = rng.chance(0.5)
        let g = Blocks.id
        let log: BlockID, leaf: BlockID
        switch kind {
        case .shrubSpruce: (log, leaf) = (SPRUCE_LOG, SPRUCE_LEAVES)
        case .shrubAcacia: (log, leaf) = (g("acacia_log"), g("acacia_leaves"))
        case .stumpSpruce: (log, leaf) = (SPRUCE_LOG, g("moss_carpet"))
        case .stumpBirch: (log, leaf) = (BIRCH_LOG, g("moss_carpet"))
        case .stumpOak, .fallenOak: (log, leaf) = (LOG, g("moss_carpet"))
        default: (log, leaf) = (LOG, LEAVES)
        }
        // Nov 15 playtest (08:14:57-08:15:16 in a forest: "Why moss carpet... this looks like shit. No moss. You can just
        // delete the moss"): stumps and fallen trunks carried a moss carpet on top; they go bare (BS_OLDLITTERMOSS=1).
        let mossy = leaf == g("moss_carpet")
        guard kind == .fallenOak else {
            // Nov 15 playtest (08:17:53-08:17:57 at 164 111 127: "I don't think the preset trees are in yet... unless this
            // is a preset bush, like, wow. Like that. Hope not"): a shrub was a log with a cube of leaves on it, a tree
            // in miniature. A shrub is a bush now: the leafy bush plant, a few of them in a clump round its spot, each
            // only on ground in open air (decided per cell, so every chunk agrees). BS_OLDSHRUBS=1: as before.
            if [.shrubOak, .shrubSpruce, .shrubAcacia].contains(kind) && !TreeShapes.oldShrubs && Blocks.has("bush") {
                let bush = g("bush")
                for (dx, dz) in [(0, 0), (1, 0), (0, 1), (-1, 0), (0, -1), (1, 1), (-1, -1)] {
                    let bx = x + dx, bz = z + dz
                    guard (dx == 0 && dz == 0) || hashf(bx, y, bz, 0xB054) < 0.45, w.inside(bx, y, bz), w.inside(bx, y - 1, bz) else { continue }
                    let under = w.get(bx, y - 1, bz), here = w.get(bx, y, bz)
                    if Blocks.opaque[Int(under)] && !Mesher.leafT[Int(under)] && here == AIR { w.force(bx, y, bz, bush) }
                }
                return
            }
            if mossy && !TreeShapes.oldLitterMoss {
                let bare = TreeShape(name: s.name, id: s.id, logs: s.logs, leaves: [], roots: s.roots, rootTips: s.rootTips, bole: s.bole,
                                     stretch: s.stretch, wide: s.wide, top: s.top)
                paste(w, bare, x, y, z, turn: turn, mirror: mirror, grow: 0, log: log, leaf: leaf, root: log)
                return
            }
            paste(w, s, x, y, z, turn: turn, mirror: mirror, grow: 0, log: log, leaf: leaf, root: log)
            return
        }
        func at(_ p: IVec3) -> IVec3 {
            var u = p.x, v = p.z
            if mirror { u = -u }
            for _ in 0..<(turn & 3) { (u, v) = (-v, u) }
            return IVec3(x + u, y + p.y, z + v)
        }
        let wood = g("oak_wood")
        for p in s.logs { let q = at(p); w.log(q.x, q.y, q.z, log) }
        var laid = Set<IVec3>()
        // Nov 15 playtest (08:14:38-08:14:54: "This log was hovering and then it corrected to sitting down. That shows that
        // patch was used to make it lie down... We don't do patches. We fix the problem"): the trunk was upright wood laid
        // length by length wherever ground held it, so a dip left one or two lengths apart, drawn as blocks over the
        // ground, and a whole trunk was a lying log only once the mesher had guessed its run from its neighbours. Now
        // it is laid as a lying log along its own axis, and only whole: from the stump out, each length on held ground
        // into open air, three lengths at least, and all of it inside the chunk being written (a trunk across a chunk's
        // edge is not laid by either side, so both agree). BS_OLDLITTERLIE=1: as before.
        if !TreeShapes.oldLitterLie {
            let run = s.roots.sorted { $0.x < $1.x }.map { at($0) }
            guard let first = run.first, run.count >= 2 else { return }
            let alongX = run[1].x != first.x
            let lying = Blocks.has("oak_wood[x]") ? g(alongX ? "oak_wood[x]" : "oak_wood[z]") : wood
            var n = 0
            for q in run {
                guard w.inside(q.x, q.y, q.z), w.inside(q.x, q.y - 1, q.z) else { n = 0; break }
                let under = w.get(q.x, q.y - 1, q.z), here = w.get(q.x, q.y, q.z)
                guard Blocks.opaque[Int(under)] && !Mesher.leafT[Int(under)] && (here == AIR || Blocks.replaceable[Int(here)] && !Blocks.isLiquid(here)) else { break }
                n += 1
            }
            guard n >= 3, run.allSatisfy({ w.inside($0.x, $0.y, $0.z) }) else { return }
            for q in run.prefix(n) { w.force(q.x, q.y, q.z, lying) }
            return
        }
        for p in s.roots {
            let q = at(p)
            guard w.inside(q.x, q.y, q.z) else { continue }
            let under = w.get(q.x, q.y - 1, q.z), here = w.get(q.x, q.y, q.z)
            if Blocks.opaque[Int(under)] && !Mesher.leafT[Int(under)] && (here == AIR || Blocks.replaceable[Int(here)] && !Blocks.isLiquid(here)) {
                w.force(q.x, q.y, q.z, wood)
                laid.insert(IVec3(p.x, 0, p.z))
            }
        }
        for p in s.leaves where laid.contains(IVec3(p.x, 0, p.z)) && (!mossy || TreeShapes.oldLitterMoss) {
            let q = at(p)
            if w.get(q.x, q.y, q.z) == AIR { w.leaf(q.x, q.y, q.z, leaf) }
        }
    }

    // The designs the world grows a kind as. BS_OLDCATALOGUE=1: only the 49 designs from before the catalogue of 100
    // (ids under 200), so every tree stands where and as it stood before Nov 15 (checks that fell a tree of his compare).
    static var oldCatalogue = ProcessInfo.processInfo.environment["BS_OLDCATALOGUE"] == "1"     // (var: checks of his trees as they stood)
    static func planted(_ kind: TreeKind) -> [TreeShape]? {
        guard let set = designs(kind) else { return nil }
        guard oldCatalogue else { return set }
        let old = set.filter { $0.id < 200 }
        return old.isEmpty ? set : old
    }

    // The designs a kind grows as (nil: not a designed tree: shrubs, stumps, fallen trunks, ice spikes).
    static func designs(_ kind: TreeKind) -> [TreeShape]? {
        switch kind {
        case .oak: return oaks
        case .fancyOak: return [oaks[0], oaks[1]]
        case .smallOak: return [oaks[3]]
        case .birch: return birches
        case .tallBirch: return tallBirches
        case .spruce: return spruces
        case .pine: return pines
        case .megaSpruce: return megaSpruces
        case .megaPine: return megaPines
        case .jungle: return jungles
        case .megaJungle: return megaJungles
        case .jungleBush: return jungleBushes
        case .acacia: return acacias
        case .darkOak: return darkOaks
        case .paleOak: return paleOaks
        case .swampOak: return swampOaks
        case .mangrove: return mangroves
        case .cherry: return cherries
        case .saltpalm: return palms
        case .ancientOak: return ancientOaks
        case .deadOak: return deadOaks
        case .deadSpruce: return deadSpruces
        default: return nil
        }
    }

    static func materials(_ kind: TreeKind) -> (log: BlockID, leaf: BlockID) {
        let g = Blocks.id
        switch kind {
        case .birch, .tallBirch: return (BIRCH_LOG, BIRCH_LEAVES)
        case .spruce, .pine, .megaSpruce, .megaPine, .deadSpruce: return (SPRUCE_LOG, SPRUCE_LEAVES)
        case .jungle, .megaJungle, .saltpalm: return (g("jungle_log"), g("jungle_leaves"))
        case .jungleBush: return (g("jungle_log"), LEAVES)
        case .acacia: return (g("acacia_log"), g("acacia_leaves"))
        case .darkOak: return (g("dark_oak_log"), g("dark_oak_leaves"))
        case .paleOak: return (g("pale_oak_log"), g("pale_oak_leaves"))
        case .mangrove: return (g("mangrove_log"), g("mangrove_leaves"))
        case .cherry: return (g("cherry_log"), g("cherry_leaves"))
        default: return (LOG, LEAVES)
        }
    }

    // Pastes design `s` with its foot at (x, y, z): turned `turn` quarters (after a mirror), its bole `grow` taller.
    static func paste(_ w: TreeWriter, _ s: TreeShape, _ x: Int, _ y: Int, _ z: Int, turn: Int, mirror: Bool, grow: Int,
                      log: BlockID, leaf: BlockID, root: BlockID) {
        // (turned about the trunk's middle: (0, 0) for a one-block trunk, (0.5, 0.5) for a 2x2 one; in half blocks)
        let c = s.wide ? 1 : 0
        @inline(__always) func at(_ p: IVec3) -> IVec3 {
            var u = 2 * p.x - c, v = 2 * p.z - c
            if mirror { u = -u }
            for _ in 0..<(turn & 3) { (u, v) = (-v, u) }
            let ly = p.y >= s.bole ? p.y + grow : p.y
            return IVec3(x + (u + c) / 2, y + ly, z + (v + c) / 2)
        }
        // (a mangrove's trunk stands in the swamp's water: through it, as its roots are)
        let wading = s.name.hasPrefix("mangrove")
        for p in s.logs {
            let q = at(p)
            if wading && w.inside(q.x, q.y, q.z) && Blocks.isLiquid(w.get(q.x, q.y, q.z)) { w.force(q.x, q.y, q.z, log) } else { w.log(q.x, q.y, q.z, log) }
        }
        // (the lengthened bole: each trunk column carried on through the added blocks)
        if grow > 0 {
            for p in s.logs where p.y == s.bole - 1 && s.logs.contains(IVec3(p.x, s.bole, p.z)) {
                let q = at(p)
                for k in 1...grow { w.log(q.x, q.y + k, q.z, log) }
            }
            // P433: a trunk whose foot is at the bole itself (a mangrove's, lifted on its roots) keeps its foot where the
            // design put it: the added blocks go in under it. (It moved up with the bole and left a gap over the roots:
            // half the mangroves hung a block above their roots, and the polygon world drew the loose trunk as cut timber.)
            for p in s.logs where p.y == s.bole && (0...c).contains(p.x) && (0...c).contains(p.z) && !s.logs.contains(IVec3(p.x, s.bole - 1, p.z)) {
                let q = at(p)
                for k in 1...grow { w.log(q.x, q.y - k, q.z, log) }
            }
        }
        // P433: a prop root runs on through water (w.log leaves liquid alone, so every root cell over the swamp's water
        // was missing and its forced tip column stood in the water on its own).
        for p in s.roots {
            let q = at(p)
            if Blocks.isLiquid(w.get(q.x, q.y, q.z)) { w.force(q.x, q.y, q.z, root) } else { w.log(q.x, q.y, q.z, root) }
        }
        for p in s.rootTips {
            let q = at(p)
            var ry = q.y
            while ry > y - 3 && (w.get(q.x, ry - 1, q.z) == AIR || Blocks.isLiquid(w.get(q.x, ry - 1, q.z))) { ry -= 1; w.force(q.x, ry, q.z, root) }
        }
        for p in s.leaves { let q = at(p); w.leaf(q.x, q.y, q.z, leaf) }
        if w.inside(x, y - 1, z) && Blocks.key(w.get(x, y - 1, z)).contains("grass") { w.force(x, y - 1, z, DIRT) }
    }

    // A designed tree of `kind` at (x, y, z): which design, its turn, mirror and height from the tree's own rng (so
    // every chunk a tree crosses draws the same one), then what grows on it.
    static func build(_ w: TreeWriter, _ kind: TreeKind, _ set: [TreeShape], _ x: Int, _ y: Int, _ z: Int, _ rng: inout SRng) {
        let s = set[rng.int(set.count)]
        let turn = rng.int(4), mirror = rng.chance(0.5), grow = rng.int(s.stretch + 1)
        let (log, leaf) = materials(kind)
        let root = Blocks.has("mangrove_roots") ? Blocks.id("mangrove_roots") : log
        paste(w, s, x, y, z, turn: turn, mirror: mirror, grow: grow, log: log, leaf: leaf, root: root)
        let top = y + s.top + grow
        switch kind {
        case .jungle: TreePlacer.vines(w, x, top - 1, z, 2, &rng)
        case .megaJungle: TreePlacer.vines(w, x, top, z, 4, &rng)
        case .swampOak: TreePlacer.vines(w, x, top - 2, z, 3, &rng)
        case .paleOak:
            let moss = Blocks.id("pale_hanging_moss")
            if rng.chance(0.12) { w.force(x + rng.int(2), y + rng.range(2, max(2, s.bole - 1)), z + rng.int(2), Blocks.id("creaking_heart")) }
            for _ in 0..<10 {
                let dx = rng.range(-3, 4), dz = rng.range(-3, 4)
                let len = rng.range(1, 4)
                guard TreePlacer.hung(w, x + dx, top - 2, z + dz, sides: false) else { continue }     // (P490: under the crown)
                for k in 0..<len {
                    guard w.get(x + dx, top - 2 - k, z + dz) == AIR else { break }
                    w.leaf(x + dx, top - 2 - k, z + dz, moss)
                }
            }
        case .megaSpruce, .megaPine:
            let podzol = Blocks.id("podzol")
            for dz in -3...4 { for dx in -3...4 where hashf(x + dx, y, z + dz, 0x9D) < 0.6 {
                let key = Blocks.key(w.get(x + dx, y - 1, z + dz))
                if key == "grass_block" || key == "dirt" { w.force(x + dx, y - 1, z + dz, podzol) }
            } }
        default: break
        }
    }
}
