import Foundation
import simd

// P92 (Oct 12 AM playtest): "Capital trains: a procedurally generated rail line leading out of a base with a train on
// it". A citadel on ground first generated with this rule lays a rail spur from its east or west edge: up to 150
// blocks of track that follow the land at most one block up or down per block (cuttings through hills, a trestle on
// timber legs over dips and water), a ballast bed, buffer stops at both ends, a platform with lamps at the citadel end
// and a parked train there: a Capital locomotive (a furnace cart: coal sets it running) and two freight cars with
// supply crates. The spur stops short of any village, temple, outpost, mansion or ruin in its way, and only exists
// where no save had generated any of its ground (WorldRules.p69), so nothing explored grows half a railway.
// Folded into C1 (railways between towns) later: the same profile and writer.
enum CapitalRail {
    static let length = 150
    static let startOff = CapitalBase.A + 11         // the first rail, blocks from the citadel's centre (the spur's box,
                                                     // buffer stop included, starts past the citadel's: A + 8)
    static let lineZ = -24                           // north of the centre (the garrison row is to the south)
    static let reach = 14                            // chunks from its region's corner: covers the whole spur
    static let kind = "capital_rail"

    // A kind of its own (not pieces of the citadel's start, whose box many readers take as the citadel: the base
    // record's centre, map markers, the garrison test, and older ground decisions that ask how big a citadel is).
    // Same grid as the citadels, so each region's spur belongs to that region's citadel. Nothing looks spurs up,
    // so the spur may ask about any other kind without a loop.
    static func type(_ gen: WorldGen) -> StructureType {
        StructureType(name: kind, spacing: 40, separation: 14, salt: 70411993 ^ 0x5A11, reach: reach) { [unowned gen] seed, cx0, cz0 in
            guard let sc = gen.structures, let mt = sc.types.first(where: { $0.name == "military_base" }),
                  let base = sc.start(mt, regionX: floorDiv(cx0, 40), regionZ: floorDiv(cz0, 40)) else { return nil }
            let x = base.anchor.x, z = base.anchor.z - CapitalBase.podium - 8
            let cx = floorDiv(x, CS), cz = floorDiv(z, CS)
            // On ground first generated with banks (the citadel's own rule) and with none of the spur's ground saved.
            guard WorldRules.p69(gen, cx, cz, reach: 6), let l = plan(gen, x, z, seed) else { return nil }
            let mid = l.x(l.level.count / 2)
            guard WorldRules.p69(gen, floorDiv(mid, CS), floorDiv(l.z, CS), reach: 9) else { return nil }
            let st = StructureStart(kind: kind, pieces: [piece(l, seed ^ 0x7A11)], anchor: IVec3(l.x0, l.level[0], l.z))
            st.plan = Plan(l)
            return st
        }
    }

    final class Plan { let line: Line; init(_ l: Line) { line = l } }

    struct Line {
        let x0: Int, z: Int, dir: Int                 // first rail at (x0, z), running dir (+1 east, -1 west)
        let level: [Int]                              // rail y at each step
        func x(_ i: Int) -> Int { x0 + dir * i }
    }

    // The spur for a citadel centred at (x, z) on floor y0, or nil where there is no room for one.
    static func plan(_ gen: WorldGen, _ x: Int, _ z: Int, _ seed: UInt64) -> Line? {
        let dir = hashf(x >> 4, z >> 4, 9201, UInt32(truncatingIfNeeded: seed)) < 0.5 ? 1 : -1
        let x0 = x + dir * startOff, lz = z + lineZ
        // Stop short of other surface structures in the way.
        var n = length
        if let sc = gen.structures {
            let lo = min(x0, x0 + dir * length), hi = max(x0, x0 + dir * length)
            for k in ["village", "temple", "pillager_outpost", "mansion", "trail_ruins", "desert_well", "shipwreck", "ocean_ruin", "monument"] {
                guard let o = sc.nearest(k, x: (lo + hi) / 2, z: lz, maxRegions: 2) else { continue }
                guard o.min.z - 4 <= lz + 2 && o.max.z + 4 >= lz - 2, o.max.x + 4 >= lo, o.min.x - 4 <= hi else { continue }
                let edge = dir > 0 ? o.min.x - 6 - x0 : x0 - (o.max.x + 6)
                n = min(n, edge)
            }
        }
        guard n >= 40 else { return nil }
        // The land along the line; the track climbs or drops at most one block a step, never below sea level + 2.
        var target: [Int] = []
        for i in 0..<n {
            let c = gen.column(x0 + dir * i, lz)
            target.append(max(SEA + 2, (c.biome.isOcean || c.biome == .river ? SEA : gen.groundY(x0 + dir * i, lz)) + 1))
        }
        var r = [target[0]]
        for i in 1..<n { r.append(r[i - 1] + max(-1, min(1, target[i] - r[i - 1]))) }
        // No single-block dips or humps (a slope can't turn back up in one block).
        for _ in 0..<2 { for i in 1..<(n - 1) {
            if r[i - 1] > r[i] && r[i + 1] > r[i] { r[i] += 1 }
            if r[i - 1] < r[i] && r[i + 1] < r[i] { r[i] -= 1 }
        } }
        // Too wild (a cliff or a deep valley the whole way): no spur.
        var off = 0
        for i in 0..<n { off = max(off, abs(r[i] - target[i])) }
        guard off <= 24 else { return nil }
        return Line(x0: x0, z: lz, dir: dir, level: r)
    }

    static func piece(_ l: Line, _ seed: UInt64) -> Piece {
        let n = l.level.count
        let lo = min(l.x(0), l.x(n - 1)), hi = max(l.x(0), l.x(n - 1))
        let ymin = (l.level.min() ?? SEA) - 40, ymax = (l.level.max() ?? SEA) + 6
        return Piece(min: IVec3(lo - 1, ymin, l.z - 3), max: IVec3(hi + 1, ymax, l.z + 4), build: { w in build(&w, l, seed) })
    }

    // Rail shape at step i: flat east-west, or a slope ascending east (2) / west (3).
    static func shape(_ l: Line, _ i: Int) -> Int {
        let r = l.level, n = r.count
        if i + 1 < n && r[i + 1] == r[i] + 1 { return l.dir > 0 ? 2 : 3 }
        if i > 0 && r[i - 1] == r[i] + 1 { return l.dir > 0 ? 3 : 2 }
        return 1
    }

    static func build(_ w: inout StructWriter, _ l: Line, _ seed: UInt64) {
        func g(_ n: String, _ f: BlockID) -> BlockID { Blocks.has(n) ? Blocks.id(n) : f }
        let rail = g("rail", AIR), ballast = g("gravel", STONE), deck = g("spruce_planks", PLANKS), leg = g("spruce_log", LOG)
        let stop = g("capital_stone_trim", g("iron_block", STONE)), plat = g("capital_stone", g("smooth_stone", STONE))
        let lamp = g("lantern", AIR), post = g("spruce_fence", leg)
        guard rail != AIR else { return }
        let n = l.level.count
        for i in 0..<n {
            let x = l.x(i), y = l.level[i]
            guard x >= w.bx - 1 && x <= w.bx + CS else { continue }
            for dz in -1...1 {
                let z = l.z + dz
                // Cutting: three clear blocks over the track and its shoulders.
                for yy in y...(y + 3) { w.set(x, yy, z, AIR) }
                let ground = w.get(x, y - 1, z)
                let solid = Blocks.opaque[Int(ground)] && Blocks.collide[Int(ground)]
                if solid { w.set(x, y - 1, z, ballast) }
                else {
                    w.set(x, y - 1, z, deck)                                  // trestle deck
                    if i % 4 == 0 && dz != 0 { w.pillarDown(x, y - 2, z, leg, minY: y - 40) }
                }
            }
            w.set(x, y, l.z, rail + BlockID(shape(l, i)))
        }
        // Buffer stops at both ends.
        for i in [0, n - 1] {
            let x = l.x(i) - l.dir * (i == 0 ? 1 : -1), y = l.level[i]
            w.set(x, y - 1, l.z, stop); w.set(x, y, l.z, stop)
        }
        // The platform at the citadel end (north of the track), with lamps.
        for i in 0..<min(16, n) {
            let x = l.x(i), y = l.level[i]
            for dz in 2...3 {
                w.set(x, y - 1, l.z - dz, plat)
                for yy in y...(y + 3) { w.set(x, yy, l.z - dz, AIR) }
                if dz == 3 { w.pillarDown(x, y - 2, l.z - dz, plat, minY: y - 30) }
            }
            if i % 6 == 1 { w.set(x, y, l.z - 3, post); w.set(x, y + 1, l.z - 3, post); w.set(x, y + 2, l.z - 3, lamp) }
        }
        // The train, parked at the platform: the locomotive in front (toward the line), two freight cars behind.
        for (i, tag) in [(6, l.dir > 0 ? "loco_e" : "loco_w"), (4, "freight"), (2, "freight")] where i < n {
            let x = l.x(i), y = l.level[i]
            w.mob("minecart:\(tag)", V3(Float(x) + 0.5, Float(y), Float(l.z) + 0.5))
        }
    }

    // Structure mob tags (Mob.structureMob): the locomotive (a furnace cart facing out along the line) and a
    // freight car (a chest cart with Capital supplies).
    static func setupCar(_ m: Mob, tag: String) {
        guard m.kind == .minecart else { return }
        if tag.hasPrefix("loco") {
            m.variant = 4
            m.yaw = tag == "loco_e" ? -.pi / 2 : .pi / 2
            m.customName = "Capital Locomotive"
        } else if tag == "freight" {
            m.variant = 1
            m.customName = "Capital Freight Car"
            let c = ItemContainer(27)
            var rng = SRng(UInt64(bitPattern: Int64(Int(m.pos.x) &* 73856093 ^ Int(m.pos.z) &* 19349663)))
            Loot.fill(c, table: "steelhold_supply", rng: &rng)
            m.cargo = c
        }
    }
}
