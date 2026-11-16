import Foundation
import simd

// Ledger 207 (Nov 15 21:00:20-21:00:26, a ghost town: "why don't we just make them like normal village generation...
// make it a normal village, but the village is abandoned, then you'll chain modify each village building so it's
// abandoned. That way, someone sees an abandoned village doesn't just look like the same thing every time"): a ghost
// town was its own generator, a street of wind-wrecked plank boxes. Now it is a town laid out as every town is
// (Village.layout: its streets, its lots and the same buildings, in the land's style), with nobody in it, and each
// building ruined by its own draw of rules:
//   roof    sound but for a hole, or caved in round a point (the roof and the wall top under it gone),
//   walls   a corner come down (the walls step down toward it) or a whole side down to its sill, or burnt to stumps,
//   doors   gone from their frames (or left), its windows broken (some or all), its stone gone to moss or cracked,
//   inside  cobwebs under the ceilings and in the corners; no lamp, torch or bed left; the crops dead.
// Every rule cuts a column from the top down, so what stands always stands on what is under it (no hanging walls,
// P388). Nobody lives there (no villagers, no sheriff, no animals); the dead walk its street at night as before
// (FrontierSites.tick). On ground no save had generated before it (structure-guard-l207.txt); BS_OLDGHOSTTOWNS=1:
// the old street of plank boxes.
enum GhostVillage {
    static let old = Env.all["BS_OLDGHOSTTOWNS"] == "1"
    static var laid = 0, tooBig = 0                       // (checks: villages laid as ghost towns, layouts past the reach)

    // One building's ruin, drawn from where it stands.
    struct House {
        let x0: Int, z0: Int, x1: Int, z1: Int, y: Int, tall: Int
        let rule: Int                                     // 0 a roof hole, 1 roof caved in, 2 a corner down, 3 a side down, 4 stumps
        let px: Float, pz: Float, r: Float                // the hole's middle and radius, or the fallen corner / side
        let slope: Float
        let doors: Float, glass: Float, moss: Float
        let s: UInt32

        init(_ a: IVec3, _ b: IVec3, seed: UInt32) {
            x0 = a.x; z0 = a.z; x1 = b.x; z1 = b.z; y = a.y; tall = b.y - a.y
            let s0 = seed ^ UInt32(truncatingIfNeeded: a.x &* 73_856_093 ^ a.z &* 19_349_663)
            s = s0
            func h(_ k: Int) -> Float { hashf(a.x, k, a.z, s0) }
            let u = h(1)
            let ru = u < 0.2 ? 0 : (u < 0.5 ? 1 : (u < 0.75 ? 2 : (u < 0.9 ? 3 : 4)))
            rule = ru
            let wx = Float(b.x - a.x), wz = Float(b.z - a.z)
            let cornerX: Float = h(2) < 0.5 ? Float(a.x) : Float(b.x) + 1, cornerZ: Float = h(3) < 0.5 ? Float(a.z) : Float(b.z) + 1
            switch ru {
            case 0, 1:
                px = Float(a.x) + 1.5 + h(2) * max(0, wx - 2); pz = Float(a.z) + 1.5 + h(3) * max(0, wz - 2)
                r = ru == 0 ? 1.2 + h(4) : 2.2 + h(4) * 2.2
            case 2:
                px = cornerX; pz = cornerZ; r = 0
            default:
                px = cornerX; pz = cornerZ; r = h(5) < 0.5 ? 0 : 1          // r: 0 an x side, 1 a z side
            }
            slope = 0.55 + h(6) * 0.5
            doors = h(7) < 0.7 ? 1 : 0
            glass = 0.45 + h(8) * 0.55
            moss = 0.15 + h(9) * 0.45
        }

        @inline(__always) func holds(_ x: Int, _ z: Int) -> Bool { x >= x0 - 1 && x <= x1 + 1 && z >= z0 - 1 && z <= z1 + 1 }

        // The highest cell a column of this building keeps (Int.max: all of it).
        func cut(_ x: Int, _ z: Int) -> Int {
            let n = Int(hashf(x, 77, z, s) * 2)           // a ragged edge, 0 or 1
            let fx = Float(x) + 0.5, fz = Float(z) + 0.5
            let top = y + tall + 1
            switch rule {
            case 0, 1:
                let d = simd_length(V2(fx - px, fz - pz))
                return d < r + Float(n) * 0.6 ? y + tall - 1 + n : Int.max
            case 2:
                let c = y + 1 + n + Int(simd_length(V2(fx - px, fz - pz)) * slope)
                return c >= top ? Int.max : c
            case 3:
                let c = y + 1 + n + Int((r == 0 ? abs(fx - px) : abs(fz - pz)) * slope * 1.4)
                return c >= top ? Int.max : c
            default:
                return y + 1 + Int(hashf(x, 78, z, s) * 2.6)
            }
        }
    }

    // What nobody left behind: lights, beds; what weather does to stone; what a dead field holds.
    static let dead: [Bool] = (0..<Blocks.count).map { i in
        let k = Blocks.key(Blocks.groupBase[i]), sh = Blocks.shape[i]
        return sh == "torch" || sh == "lantern" || sh == "bed" || k.hasSuffix("torch") || k.hasSuffix("lantern") || k.hasSuffix("_bed") || k.hasSuffix("campfire")
    }
    static let door: [Bool] = (0..<Blocks.count).map { Blocks.shape[$0] == "door" }
    static let glass: [Bool] = (0..<Blocks.count).map { Blocks.key(Blocks.groupBase[$0]).contains("glass") }
    static let crop: [Bool] = (0..<Blocks.count).map { ["wheat", "carrots", "potatoes", "beetroots"].contains(Blocks.key(Blocks.groupBase[$0])) }
    static let farmland: [Bool] = (0..<Blocks.count).map { Blocks.key(Blocks.groupBase[$0]) == "farmland" }
    static let weathered: [[BlockID]] = (0..<Blocks.count).map { i in
        func ids(_ ks: [String]) -> [BlockID] { ks.filter { Blocks.has($0) }.map { Blocks.id($0) } }
        guard Int(Blocks.groupBase[i]) == i else { return [] }
        switch Blocks.key(BlockID(i)) {
        case "cobblestone": return ids(["mossy_cobblestone"])
        case "stone_bricks": return ids(["mossy_stone_bricks", "cracked_stone_bricks"])
        case "bricks", "sandstone", "smooth_sandstone", "cut_sandstone": return ids(["cobblestone"])
        default: return []
        }
    }
    static let deadBush: BlockID = Blocks.has("dead_bush") ? Blocks.id("dead_bush") : AIR
    static let coarse: BlockID = Blocks.has("coarse_dirt") ? Blocks.id("coarse_dirt") : Blocks.id("dirt")
    static let web: BlockID = Blocks.has("cobweb") ? Blocks.id("cobweb") : AIR

    // The ruin of one cell a town piece writes.
    static func ruin(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID, _ hs: [House], _ s: UInt32) -> BlockID {
        let i = Int(b)
        if b == AIR || i >= dead.count { return b }
        if dead[i] { return AIR }
        if crop[i] { return hashf(x, y, z, s ^ 0xC20) < 0.3 ? deadBush : AIR }
        if farmland[i] { return coarse }
        for h in hs where h.holds(x, z) {
            if y > h.cut(x, z) { return AIR }
            if door[i] && h.doors > 0 { return AIR }
            if glass[i] && hashf(x, y, z, h.s ^ 0x61A) < h.glass { return AIR }
            let wv = weathered[i]
            if !wv.isEmpty && hashf(x, y, z, h.s ^ 0x3055) < h.moss { return wv[Int(hashf(x, y, z, h.s ^ 0x3056) * Float(wv.count)) % wv.count] }
            return b
        }
        if glass[i] && hashf(x, y, z, s ^ 0x61B) < 0.6 { return AIR }
        let wv = weathered[i]
        if !wv.isEmpty && hashf(x, y, z, s ^ 0x3057) < 0.3 { return wv[Int(hashf(x, y, z, s ^ 0x3058) * Float(wv.count)) % wv.count] }
        return b
    }

    // Cobwebs under a building's ceiling, thickest in the corners (cells of this chunk only).
    static func webs(_ w: inout StructWriter, _ h: House) {
        guard web != AIR else { return }
        let xa = max(h.x0 + 1, w.bx), xb = min(h.x1 - 1, w.bx + CS - 1)
        let za = max(h.z0 + 1, w.bz), zb = min(h.z1 - 1, w.bz + CS - 1)
        guard xa <= xb, za <= zb else { return }
        for z in za...zb { for x in xa...xb { for y in (h.y + 1)...(h.y + h.tall + 3) {
            guard w.get(x, y, z) == AIR, Blocks.collide[Int(w.get(x, y + 1, z))] else { continue }
            var sides = 0
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where Blocks.collide[Int(w.get(x + dx, y, z + dz))] { sides += 1 }
            if hashf(x, y, z, h.s ^ 0x3EB) < (sides >= 2 ? 0.45 : (sides == 1 ? 0.12 : 0.03)) { w.set(x, y, z, web) }
        } } }
    }

    // A ghost town at the frontier site's chunk: a town's layout in the land's style, ruined. Nil when no layout fits
    // the site's reach (the caller builds the old street then).
    static func start(_ gen: WorldGen, seed: UInt64, cx: Int, cz: Int, biome: Biome, reach: Int) -> StructureStart? {
        let ox = cx * CS + 8, oz = cz * CS + 8
        let style: Village.Style = Village.style(biome) ?? {
            switch biome {
            case .badlands, .woodedBadlands, .erodedBadlands: return .desert
            case .windsweptSavanna: return .savanna
            default: return .plains
            }
        }()
        let cy = gen.groundY(ox, oz)
        let lo = IVec3((cx - reach) * CS, 0, (cz - reach) * CS), hi = IVec3((cx + reach) * CS + CS - 1, 0, (cz + reach) * CS + CS - 1)
        var st: StructureStart?
        // The biggest of a village or a hamlet's plans that fits the site.
        for (size, bigger, biggest) in [(TownSize.village, false, true), (.village, true, false), (.hamlet, false, true), (.hamlet, true, false), (.hamlet, false, false)] {
            guard let v = Village.layout(gen, seed: seed, ox: ox, oz: oz, cy: cy, style: style, frontier: true, townsGap: true, wide: true,
                                         streets: true, townSize: size, r20: true, p354: true, bigger: bigger, p478: true, biggest: biggest,
                                         p499: true, l52: true) else { continue }
            if v.min.x < lo.x || v.min.z < lo.z || v.max.x > hi.x || v.max.z > hi.z { tooBig += 1; continue }
            st = v; break
        }
        guard let v = st else { return nil }
        let s32 = UInt32(truncatingIfNeeded: seed ^ (seed >> 29))
        var houses: [House] = []
        for f in v.far where f.tone != .roof { houses.append(House(f.min, f.max, seed: s32)) }
        let hs = houses
        let pieces = v.pieces.map { p -> Piece in
            let mine = hs.first { $0.x0 - 3 == p.min.x && $0.z0 - 3 == p.min.z }     // a lot's own piece (Village.layout)
            return Piece(min: p.min, max: p.max) { w in
                let m0 = w.mobs.count, e0 = w.entities.count
                w.ruin = { x, y, z, b in GhostVillage.ruin(x, y, z, b, hs, s32) }
                p.build(&w)
                w.ruin = nil
                if w.mobs.count > m0 { w.mobs.removeSubrange(m0...) }             // nobody lives here
                var k = e0
                while k < w.entities.count {
                    let (q, be) = w.entities[k]
                    if w.inside(q.x, q.y, q.z) && w.get(q.x, q.y, q.z) == AIR { w.entities.remove(at: k); continue }
                    if be.kind == .sign, be.lines.count > 2, be.lines[0] == "Welcome to" { be.lines[2] = "" }
                    k += 1
                }
                if let h = mine { webs(&w, h) }
            }
        }
        let out = StructureStart(kind: "ghost_town", pieces: pieces, anchor: v.anchor)
        for f in v.far {
            if f.tone == .roof, let h = hs.first(where: { $0.holds(f.min.x, f.min.z) }), h.rule != 0 { continue }   // (a caved roof: the far box has none)
            out.far.append(f)
        }
        out.info = ["lots": v.info["lots"] ?? 0]
        for h in hs { out.info["rule\(h.rule)", default: 0] += 1 }        // (checks: how each building was left)
        laid += 1
        return out
    }
}
