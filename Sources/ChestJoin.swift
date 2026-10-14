import Foundation
import simd

// P264 (Oct 14 12:18, "two chests placed side by side join into one double chest"). The pairing itself was there (the
// chest screen, hoppers and comparators read two same-facing chests along their width as one); what was missing:
//   placing   a chest set beside a single chest of the same kind turns to match it, so they join whichever way he
//             faces (Game.place via `placedFacing`); sneaking keeps it apart; a third never joins a double (it turns away)
//   the look  each half's box runs to the shared edge (no gap), the faces along the seam use copies of their texture
//             with the frame opened on that side (`_join_*` layers, derived from whichever art is loaded: the imported
//             PNGs or the built-in painters, Mac and Quest alike), the front loses its own latch and one latch box
//             straddles the seam
//   feedback  the first join says so with a wooden clunk
// Pairing (here, the chest screen, Circuit.chestPartner): the neighbour of the same state on the +width side, else on
// the -width side.
enum ChestJoin {
    static let sources = ["chest_front", "chest_side", "chest_top", "trapped_chest_front"]
    static let suffix = ["_join_u0", "_join_u1", "_join_v0", "_join_v1"]      // the frame opened at u low / u high / v low / v high

    // Registers the derived layers (with the chests, before any texture is built).
    static func register() {
        for s in sources { for x in suffix { _ = Tex.id(s + x) } }
        _ = Tex.id("iron_block")
    }

    static func derived(_ name: String) -> (String, Int)? {
        guard name.contains("_join_") else { return nil }
        for (i, x) in suffix.enumerated() where name.hasSuffix(x) {
            let src = String(name.dropLast(x.count))
            if sources.contains(src) { return (src, i) }
        }
        return nil
    }

    // Where a derived texel takes its colour from in the source (n x n): the frame band on the open side repeats the
    // wood next to it; a front also loses its latch (the joined chest's one latch is a box on the seam).
    static func source(_ x: Int, _ y: Int, n: Int, side: Int, latch: Bool) -> (Int, Int) {
        let w = max(1, n * 3 / 16)
        var sx = x, sy = y
        switch side {
        case 0: if sx < w { sx += w }
        case 1: if sx >= n - w { sx -= w }
        case 2: if sy < w { sy += w }
        default: if sy >= n - w { sy -= w }
        }
        if latch && sx >= n * 5 / 16 && sx < n * 11 / 16 && sy >= n * 5 / 16 && sy < n * 11 / 16 { sx -= n * 6 / 16 }
        return (sx, sy)
    }
    static func open(_ px: [V4], n: Int, side: Int, latch: Bool) -> [V4] {
        var out = px
        for y in 0..<n { for x in 0..<n {
            let (sx, sy) = source(x, y, n: n, side: side, latch: latch)
            out[y * n + x] = px[sy * n + sx]
        } }
        return out
    }
    // The 16 px painters for the derived layers (the HD sizes are derived in TextureGen.base from the loaded art).
    static func addPainters(_ p: inout [String: TextureGen.Painter]) {
        let S = TextureGen.S
        for s in sources {
            guard let f = p[s] else { continue }
            for (i, x) in suffix.enumerated() {
                let latch = s.hasSuffix("_front")
                p[s + x] = { px, py in let (sx, sy) = source(px, py, n: S, side: i, latch: latch); return f(sx, sy) }
            }
        }
    }

    // MARK: Meshing (per block state, built once; read from the mesher's threads)

    static let joinable: [Bool] = (0..<Blocks.count).map { i in
        let k = Blocks.key(Blocks.groupBase[i])
        return (k == "chest" || k == "trapped_chest") && i - Int(Blocks.groupBase[i]) < 4
    }
    // Source layer -> its four derived layers.
    static let variants: [UInt16: [UInt16]] = {
        var v: [UInt16: [UInt16]] = [:]
        for s in sources { v[Tex.id(s)] = suffix.map { Tex.id(s + $0) } }
        return v
    }()
    static let latchLayer: UInt16 = Tex.id("iron_block")

    // The half's boxes when it has a partner (nil: a single chest, drawn as registered). `lo`/`hi`: the neighbours on
    // the -width / +width side (x for chests facing north or south, z for west or east).
    static func boxes(_ b: BlockID, lo: BlockID, hi: BlockID, base: [Box], tex: (Int) -> UInt16) -> [Box]? {
        guard let box0 = base.first else { return nil }
        let up = hi == b
        guard up || lo == b else { return nil }
        let facing = Int(b - Blocks.groupBase[Int(b)])
        let ax = facing < 2 ? 0 : 2
        var box = box0
        if ax == 0 { if up { box.x1 = 16 } else { box.x0 = 0 } } else { if up { box.z1 = 16 } else { box.z0 = 0 } }
        // A point on the seam and the centre, to see which way each face's texture runs into the seam.
        let seam = ax == 0 ? (up ? 16 : 0, 8, 8) : (8, 8, up ? 16 : 0)
        var t: [UInt16] = []
        for f in 0..<6 {
            let layer = tex(f)
            guard f / 2 != ax, let vs = variants[layer] else { t.append(layer); continue }
            let (su, sv) = Mesher.faceUV(f, seam.0, seam.1, seam.2)
            let (cu, cv) = Mesher.faceUV(f, 8, 8, 8)
            let side = su != cu ? (su > cu ? 1 : 0) : (sv > cv ? 3 : 2)
            t.append(vs[side])
        }
        box.tex = t
        // One latch across the seam on the front: half of it on each side.
        let lat: Box
        let a: Int = up ? 15 : 0
        switch facing {
        case 0: lat = Box(a, 6, 0, a + 1, 10, 1)
        case 1: lat = Box(a, 6, 15, a + 1, 10, 16)
        case 2: lat = Box(0, 6, a, 1, 10, a + 1)
        default: lat = Box(15, 6, a, 16, 10, a + 1)
        }
        var latch = lat
        latch.tex = Array(repeating: latchLayer, count: 6)
        return [box, latch] + base.dropFirst()
    }

    // MARK: Placing (b, e)

    // The facing a chest placed at `at` takes: its neighbour's when that is a single chest of the same kind it can
    // join along its width; turned a quarter when the facing he chose would make it a third beside a double chest.
    static func placedFacing(_ g: Game, _ item: BlockID, at: IVec3, chosen: Int) -> Int {
        let k = Blocks.key(item)
        guard k == "chest" || k == "trapped_chest" else { return chosen }
        let w = g.world
        func partner(_ p: IVec3) -> IVec3? {
            let b = w.block(p.x, p.y, p.z)
            guard Blocks.groupBase[Int(b)] == item, Int(b - item) < 4 else { return nil }
            let a = Int(b - item) < 2 ? IVec3(1, 0, 0) : IVec3(0, 0, 1)
            if w.block(p.x + a.x, p.y, p.z + a.z) == b { return p + a }
            if w.block(p.x - a.x, p.y, p.z - a.z) == b { return p - a }
            return nil
        }
        let sides = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)]
        if !g.player.sneaking {
            for d in sides {
                let q = at + d
                let b = w.block(q.x, q.y, q.z)
                guard Blocks.groupBase[Int(b)] == item, Int(b - item) < 4, partner(q) == nil else { continue }
                let f = Int(b - item)
                // It joins only along the neighbour's width (x for north/south, z for west/east).
                if (f < 2) == (d.x != 0) { return f }
            }
        }
        // Never a third onto a double: if the chosen facing pairs it with a chest that already has a partner, turn it.
        let a = chosen < 2 ? IVec3(1, 0, 0) : IVec3(0, 0, 1)
        for q in [at + a, at - a] {
            let b = w.block(q.x, q.y, q.z)
            if Blocks.groupBase[Int(b)] == item && Int(b - item) == chosen && partner(q) != nil { return chosen < 2 ? 2 + (chosen & 1) : chosen & 1 }
        }
        return chosen
    }

    // After placing: the first join is announced (e).
    static func placed(_ g: Game, at: IVec3) {
        let b = g.world.block(at.x, at.y, at.z)
        guard Int(b) < joinable.count, joinable[Int(b)] else { return }
        let a = Int(b - Blocks.groupBase[Int(b)]) < 2 ? IVec3(1, 0, 0) : IVec3(0, 0, 1)
        let joined = g.world.block(at.x + a.x, at.y, at.z + a.z) == b || g.world.block(at.x - a.x, at.y, at.z - a.z) == b
        guard joined else { return }
        g.sfx(.place(.wood), 1.1, at: V3(Float(at.x) + 0.5, Float(at.y) + 0.5, Float(at.z) + 0.5))
        if !Settings.shared.chestJoinTold {
            Settings.shared.chestJoinTold = true
            g.onToast?("Chests joined: a Large Chest, 54 slots (sneak while placing to keep them apart)")
        }
    }
}
