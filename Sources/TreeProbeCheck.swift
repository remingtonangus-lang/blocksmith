import Foundation
import simd

// P478 (Remington, Oct 27 18:46-18:47, New World (8) seed 7639458412018979794, snowy taiga at 3946 76 -1731).
//   questcheck --treeprobe [SEED,X,Y,Z]: "I've got a log detached from a tree... I see a few more just like that". Grows
//     that ground as a field world (as his headset does) and looks for logs that hang free: a group of touching logs
//     (faces, edges and corners) with no log on the ground or on a built block other than a tree's. Prints the groups and
//     a side view of each (Y is the shown height, as his notes give it).
//   questcheck --fellcheck: "trees disappear when they hit another root"; "really weird physics when I stand on top of the
//     logs". Two spruces on flat ground, the first cut so it falls into the second; then him standing on the fallen trunk.
enum TreeProbeCheck {
    static func run(_ g0: Game, _ arg: String?, _ check: (Bool, String) -> Void) {
        var seed: UInt64 = 7639458412018979794
        var at = V3(3946.5, 76 + 64, -1730.5)
        if let a = arg {
            let p = a.split(separator: ",").map { String($0) }
            if p.count >= 4, let s = UInt64(p[0]), let x = Float(p[1]), let y = Float(p[2]), let z = Float(p[3]) {
                seed = s; at = V3(x, y + 64, z)
            }
        }
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let w = World(seed: seed, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 4; w.activeDistance = 4
        _ = w.loadSync(center: at, radius: 4)
        let leaf: [Bool] = (0..<Blocks.count).map { Blocks.key(Blocks.groupBase[$0]).hasSuffix("_leaves") }
        func isLog(_ b: BlockID) -> Bool { ShapeTrunks.isLog[Int(b)] }
        // Something that holds a log up: the ground, a root, or a built block that is no part of a tree.
        func holds(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            if w.groundAt(x, y, z) { return true }
            let b = w.builtBlock(x, y, z)
            if ShapeTrunks.isRoot[Int(b)] { return true }
            return b != AIR && Blocks.collide[Int(b)] && !isLog(b) && !leaf[Int(b)]
        }
        let r = 3 * CS
        let cx = Int(floor(at.x)), cz = Int(floor(at.z))
        var seen = Set<IVec3>()
        var loose: [(IVec3, Int)] = []
        var groups = 0
        for z in (cz - r)...(cz + r) { for x in (cx - r)...(cx + r) {
            guard w.isLoaded(x, z) else { continue }
            for y in 64..<300 {
                let p = IVec3(x, y, z)
                guard isLog(w.builtBlock(x, y, z)), !seen.contains(p) else { continue }
                groups += 1
                var stack = [p], held = false, n = 0, low = p
                seen.insert(p)
                while let q = stack.popLast() {
                    n += 1
                    if q.y < low.y { low = q }
                    if holds(q.x, q.y - 1, q.z) || holds(q.x + 1, q.y, q.z) || holds(q.x - 1, q.y, q.z)
                        || holds(q.x, q.y, q.z + 1) || holds(q.x, q.y, q.z - 1) { held = true }
                    for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 || dz != 0 {
                        let o = IVec3(q.x + dx, q.y + dy, q.z + dz)
                        guard abs(o.x - cx) <= r + 8, abs(o.z - cz) <= r + 8, !seen.contains(o), isLog(w.builtBlock(o.x, o.y, o.z)) else { continue }
                        seen.insert(o); stack.append(o)
                    } } }
                }
                if !held { loose.append((low, n)) }
            }
        } }
        loose.sort { abs($0.0.x - cx) + abs($0.0.z - cz) < abs($1.0.x - cx) + abs($1.0.z - cz) }
        for (p, n) in loose.prefix(8) {
            let below = Blocks.key(Blocks.groupBase[Int(w.builtBlock(p.x, p.y - 1, p.z))])
            let gnd = (0..<12).first { w.groundAt(p.x, p.y - 1 - $0, p.z) } ?? -1
            print("treeprobe: loose \(n) logs, lowest \(p.x) \(p.y - 64) \(p.z) (\(Blocks.key(Blocks.groupBase[Int(w.builtBlock(p.x, p.y, p.z))]))) on \(below), ground \(gnd) below")
            slice(w, p, leaf)
        }
        check(loose.isEmpty, "treeprobe: \(loose.count) of \(groups) log groups within \(r) of \(cx) \(Int(at.y) - 64) \(cz) hang free")
    }

    // Side views (x across, y up) of the 3 rows of z round p: L log, r root, * leaves, # ground, b other built block.
    static func slice(_ w: World, _ p: IVec3, _ leaf: [Bool]) {
        for z in (p.z - 1)...(p.z + 1) {
            print("  z \(z):")
            for y in stride(from: p.y + 6, through: p.y - 3, by: -1) {
                var s = ""
                for x in (p.x - 6)...(p.x + 6) {
                    let b = w.builtBlock(x, y, z)
                    s += ShapeTrunks.isLog[Int(b)] ? "L" : ShapeTrunks.isRoot[Int(b)] ? "r" : leaf[Int(b)] ? "*"
                        : b != AIR ? "b" : w.groundAt(x, y, z) ? "#" : "."
                }
                print("   \(String(format: "%4d", y - 64)) \(s)")
            }
        }
    }

    // His own trees (the --treeprobe ground): a few real trees, each cut so it falls toward a neighbour 3-7 away (root
    // flares and all). Each must still be there after 10 s, whole, not sunk into the ground, the neighbour standing.
    static func fellReal(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let at = V3(3946.5, 76 + 64, -1730.5)
        let w = World(seed: 7639458412018979794, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 3; w.activeDistance = 3
        let g = Game(world: w, save: nil, persistent: false)
        g.paused = false; g.survival = false
        g.player.pos = at
        _ = w.loadSync(center: at, radius: 3)
        func isLog(_ b: BlockID) -> Bool { ShapeTrunks.isLog[Int(b)] }
        // Trunk feet: a log on the ground or a root, with logs going up at least 4.
        var feet: [IVec3] = []
        let cx = Int(floor(at.x)), cz = Int(floor(at.z))
        for z in (cz - 24)...(cz + 24) { for x in (cx - 24)...(cx + 24) {
            for y in 100..<260 where isLog(w.builtBlock(x, y, z)) && !isLog(w.builtBlock(x, y - 1, z))
                && (w.groundAt(x, y - 1, z) || ShapeTrunks.isRoot[Int(w.builtBlock(x, y - 1, z))])
                && (1...4).allSatisfy({ isLog(w.builtBlock(x, y + $0, z)) }) { feet.append(IVec3(x, y, z)); break }
        } }
        var pairs: [(IVec3, IVec3)] = []
        var used = Set<IVec3>()
        for a in feet where !used.contains(a) {
            guard let b = feet.first(where: { !used.contains($0) && $0 != a && abs($0.y - a.y) < 4
                && (9...49).contains(($0.x - a.x) * ($0.x - a.x) + ($0.z - a.z) * ($0.z - a.z)) }) else { continue }
            pairs.append((a, b)); used.insert(a); used.insert(b)
            for f in feet where max(abs(f.x - a.x), abs(f.z - a.z)) < 3 || max(abs(f.x - b.x), abs(f.z - b.z)) < 3 { used.insert(f) }
            if pairs.count >= 4 { break }
        }
        var bad: [String] = []
        for (a, b) in pairs {
            let dir = simd_normalize(V3(Float(b.x - a.x), 0, Float(b.z - a.z)))
            g.player.pos = V3(Float(a.x) + 0.5, Float(a.y), Float(a.z) + 0.5) - dir * 2.5
            let cut = w.builtBlock(a.x, a.y, a.z)
            let n0 = Felling.felled
            w.setBlock(a.x, a.y, a.z, AIR)
            g.fellCheck(a, cut)
            guard Felling.felled > n0, let s = w.ships.list.last(where: { Felling.isFelled($0) }) else {
                bad.append("\(a.x) \(a.y - 64) \(a.z): did not fall"); continue
            }
            let blocks0 = s.blockCount
            var t: Float = 0, gone = false, top: Float = 0
            while t < 10 {
                w.ships.update(1.0 / 60, game: g); g.fellingTick(1.0 / 60); t += 1.0 / 60
                if !w.ships.list.contains(where: { $0 === s }) { gone = true; break }
                top = max(top, simd_length(s.vel))
            }
            var groundTop = Int(s.pos.y) + 8
            let px = Int(floor(s.pos.x)), pz = Int(floor(s.pos.z))
            while groundTop > 1 && !w.groundAt(px, groundTop, pz) { groundTop -= 1 }
            let sunk = Float(groundTop + 1) - s.worldMax.y
            let standing = isLog(w.builtBlock(b.x, b.y + 2, b.z))
            let lean = TreeProbeCheck.lean(s)
            let line = String(format: "%d %d %d toward %d %d %d: %@, %d of %d blocks, %.0f degrees over, top speed %.1f, body top %.1f above the ground, neighbour %@",
                              a.x, a.y - 64, a.z, b.x, b.y - 64, b.z, gone ? "GONE" : "there", gone ? 0 : s.blockCount, blocks0, lean, top,
                              -sunk, standing ? "standing" : "down")
            print("fellreal: " + line)
            if gone || s.blockCount < blocks0 || sunk > 0 || top > 16 || lean < 20 { bad.append(line) }
            w.ships.remove(s)
        }
        check(!pairs.isEmpty && bad.isEmpty, "fellreal: \(pairs.count) of his trees felled into a neighbour go over and stay whole and above the ground (\(bad.joined(separator: "; ")))")
        // His 18:46 spruce (3921 76 -1716), cut at its foot from where he stood: it dropped onto the ground under the cut
        // and stood there upright as a body, 4 degrees over, for good. It must go over and lie down.
        do {
            let foot = IVec3(3921, 76 + 64, -1716)
            g.player.pos = V3(3922.2, 75.8 + 64, -1719.8)
            let cut = w.builtBlock(foot.x, foot.y, foot.z), n0 = Felling.felled
            w.setBlock(foot.x, foot.y, foot.z, AIR)
            g.fellCheck(foot, cut)
            if Felling.felled > n0, let s = w.ships.list.last(where: { Felling.isFelled($0) }) {
                var t: Float = 0
                while t < 8 { w.ships.update(1.0 / 60, game: g); g.fellingTick(1.0 / 60); t += 1.0 / 60 }
                let lean = TreeProbeCheck.lean(s)
                let there = w.ships.list.contains { $0 === s }
                check(there && lean > 60, String(format: "fellreal: his 18:46 spruce cut at its foot goes over and lies down (%.0f degrees over after 8 s, %@)", lean, there ? "there" : "GONE"))
                w.ships.remove(s)
            } else { check(false, "fellreal: his 18:46 spruce cut at its foot falls (\(cut == AIR ? "no log there" : Blocks.key(cut)))") }
        }
    }

    // How far over a felled trunk lies, in degrees from upright: its lowest log to its highest as it stood.
    static func lean(_ s: Ship) -> Float {
        var lo: IVec3?, hi: IVec3?
        let g = s.grid
        for y in 0..<g.sy { for z in 0..<g.sz { for x in 0..<g.sx where CapitalBase.isLog(g.get(x, y, z)) {
            if lo == nil || y < lo!.y { lo = IVec3(x, y, z) }
            if hi == nil || y > hi!.y { hi = IVec3(x, y, z) }
        } } }
        guard let a = lo, let b = hi, b.y > a.y else { return 0 }
        func w(_ c: IVec3) -> V3 { s.toWorld(V3(Float(c.x), Float(c.y), Float(c.z)) + 0.5) }
        let d = simd_normalize(w(b) - w(a))
        return acosf(max(-1, min(1, d.y))) * 180 / .pi
    }

    static func fell(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let w = World(seed: 4242, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 3; w.activeDistance = 3
        let g = Game(world: w, save: nil, persistent: false)
        g.paused = false; g.survival = false
        let ox = 40, oz = 40
        g.player.pos = V3(Float(ox) - 4.5, 200, Float(oz) + 0.5)
        _ = w.loadSync(center: g.player.pos, radius: 3)
        let stone = FieldMat.index[Int(STONE)]
        func set(_ x: Int, _ y: Int, _ z: Int, _ on: Bool) {
            guard let c = w.chunkAt(x, z) else { return }
            c.blocks.setDensity(Chunk.index(mod(x, CS), y, mod(z, CS)), on ? 32 : -32, material: on ? stone : nil)
        }
        var top = CH - 2
        while top > 1 && !w.groundAt(ox, top, oz) { top -= 1 }
        let y0 = top + 1
        // A flat field 30 x 14 round both trees, nothing standing on it.
        for z in (oz - 7)...(oz + 7) { for x in (ox - 8)...(ox + 22) {
            for y in (y0 - 6)..<y0 { set(x, y, z, true) }
            for y in y0..<(y0 + 24) { set(x, y, z, false); if w.builtBlock(x, y, z) != AIR { w.setBlock(x, y, z, AIR) } }
        } }
        let log = Blocks.id("spruce_log"), leaves = Blocks.has("spruce_leaves") ? Blocks.id("spruce_leaves") : LEAVES
        func spruce(_ x: Int, _ z: Int) {
            for k in 0..<9 { w.setBlock(x, y0 + k, z, log) }
            for k in 3...9 {
                let rr = k < 5 ? 2 : (k < 8 ? 1 : 0)
                for dz in -rr...rr { for dx in -rr...rr where !(dx == 0 && dz == 0 && k < 9) && abs(dx) + abs(dz) <= rr + 1 {
                    if w.builtBlock(x + dx, y0 + k, z + dz) == AIR { w.setBlock(x + dx, y0 + k, z + dz, leaves) }
                } }
            }
        }
        spruce(ox, oz)
        spruce(ox + 3, oz + 2)                              // crowns through each other, trunks 3 and 2 apart
        // (the second's own crown: leaves nearer its trunk than the first's)
        func theirs() -> Int {
            var n = 0
            for y in y0...(y0 + 10) { for z in (oz - 1)...(oz + 5) { for x in (ox)...(ox + 6) where CapitalBase.isLeaf(w.builtBlock(x, y, z)) {
                let a = (x - ox) * (x - ox) + (z - oz) * (z - oz), b = (x - ox - 3) * (x - ox - 3) + (z - oz - 2) * (z - oz - 2)
                if b < a { n += 1 }
            } } }
            return n
        }
        let crown0 = theirs()
        // He chops the first at its foot from the west: it goes over east, its crown through the second's (P478: the
        // second's trunk inside its crown held it standing; its own trunk passes the second's by).
        let felled0 = Felling.felled
        w.setBlock(ox, y0, oz, AIR)
        g.fellCheck(IVec3(ox, y0, oz), log)
        let fell = Felling.felled > felled0
        guard fell, let s = w.ships.list.last(where: { Felling.isFelled($0) }) else {
            check(false, "fellcheck: the cut spruce fell (\(fell))"); return
        }
        let n0 = s.blockCount, p0 = s.pos
        var top2: Float = 0, gone = false, t: Float = 0
        while t < 10 {
            w.ships.update(1.0 / 60, game: g)
            g.fellingTick(1.0 / 60)
            t += 1.0 / 60
            if !w.ships.list.contains(where: { $0 === s }) { gone = true; break }
            top2 = max(top2, simd_length(s.vel))
        }
        let moved = simd_length(V3(s.pos.x - p0.x, 0, s.pos.z - p0.z))
        let standing = (0..<9).allSatisfy { w.builtBlock(ox + 3, y0 + $0, oz + 2) == log }
        let lean = TreeProbeCheck.lean(s)
        if lean < 60 {                          // (what holds it up: hull cells within 0.5 of a solid block)
            var touch: [String] = []
            for l in s.hull {
                let p = s.toWorld(l)
                for y in Int(floor(p.y - 0.5))...Int(floor(p.y + 0.5)) { for z in Int(floor(p.z - 0.5))...Int(floor(p.z + 0.5)) { for x in Int(floor(p.x - 0.5))...Int(floor(p.x + 0.5)) {
                    let b = w.block(x, y, z)
                    let q = simd_clamp(p, V3(Float(x), Float(y), Float(z)), V3(Float(x + 1), Float(y + 1), Float(z + 1)))
                    if (Blocks.collide[Int(b)] || w.groundAt(x, y, z)) && simd_length(p - q) < 0.5 && touch.count < 16 {
                        touch.append(String(format: "%d,%d,%d %@ on %@ at %d,%d,%d", Int(floor(p.x)) - ox, Int(floor(p.y)) - y0, Int(floor(p.z)) - oz,
                                            Blocks.key(s.grid.get(Int(floor(l.x)), Int(floor(l.y)), Int(floor(l.z)))), Blocks.key(b), x - ox, y - y0, z - oz))
                    }
                } } }
            }
            print("fellcheck: held at \(Int(lean)) degrees (body turned \(Int(acosf(max(-1, min(1, s.rot.act(V3(0, 1, 0)).y))) * 180 / .pi))) by " + touch.joined(separator: "; "))
        }
        // (P478: it must also have gone over: held up by its neighbour's leaves it stood where it was, a body.)
        let crown1 = theirs()
        check(!gone && s.blockCount == n0 && top2 < 14 && moved < 9 && standing && lean > 60 && crown1 == crown0,
              String(format: "fellcheck: a spruce felled through its neighbour's crown goes over, lies down and stays (gone %@, %d of %d blocks, %.0f degrees over, top speed %.1f, came to rest %.1f from where it stood; the neighbour stands %@ with %d of its %d leaves)",
                     gone ? "yes" : "no", s.blockCount, n0, lean, top2, moved, standing ? "yes" : "no", crown1, crown0))
        guard !gone else { return }
        // He steps up onto the fallen trunk and stands still for 4 s: he stays on it and it stays put.
        let mid = s.toWorld(s.com)
        var stand = mid + V3(0, 3, 0)
        var bx: [(V3, V3)] = []
        for _ in 0..<60 {
            bx.removeAll()
            w.ships.boxes(stand - V3(0.3, 0, 0.3), stand + V3(0.3, 0.1, 0.3), &bx)
            if !bx.isEmpty { break }
            stand.y -= 0.1
        }
        g.player.pos = stand + V3(0, 0.1, 0); g.player.vel = .zero; g.player.flying = false
        let log0 = s.pos
        var drift: Float = 0, worst: Float = 0, settle: Float = 0, aboard = 0
        let start = g.player.pos
        t = 0
        while t < 4 {
            w.ships.update(1.0 / 60, game: g)
            g.fellingTick(1.0 / 60)
            g.shipPlayerUpdate(1.0 / 60, MoveInput())
            if w.ships.aboard === s { aboard += 1 }
            t += 1.0 / 60
            let d = simd_length(V3(g.player.pos.x - start.x, 0, g.player.pos.z - start.z))
            // (P504: the first half second is him settling from the spot found over the trunk's boxes onto its bark, a
            // drop of a few tenths at falling speed; a bounce is any speed up or down after that.)
            if t < 0.5 { settle = max(settle, abs(g.player.vel.y)) } else { worst = max(worst, abs(g.player.vel.y)) }
            drift = d
        }
        let logMoved = simd_length(s.pos - log0)
        check(drift < 0.3 && logMoved < 0.3 && worst < 3 && g.player.pos.y > start.y - 1,
              String(format: "fellcheck: standing on the fallen trunk 4 s he drifts %.2f, bounces up to %.1f b/s once on it (settling %.1f), ends %.2f from his start height, the trunk moves %.2f (aboard %d of 240 ticks)",
                     drift, worst, settle, g.player.pos.y - start.y, logMoved, aboard))
    }

    // P504 (Nov 1 07:25, "This tree should have fallen"): his Ash Vault dark oak at 2914 -33 -3051, a 2x2 trunk. One foot
    // cut, it stands on the other three; a second cut through the same trunk (half its section) fells it, and it goes
    // over (it stood on its last foot until all four were cut).
    static func fellHalf(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let w = World(seed: 5663059916303033239, device: g0.world.device, save: nil, dim: .deep)
        w.makeFieldWorld()
        w.renderDistance = 3; w.activeDistance = 3
        let g = Game(world: w, save: nil, persistent: false)
        g.paused = false; g.survival = false
        g.player.pos = V3(2910.8, 31, -3051.0)
        _ = w.loadSync(center: g.player.pos, radius: 3)
        func isLog(_ b: BlockID) -> Bool { CapitalBase.isLog(b) }
        var feet: [IVec3] = []
        for z in -3053...(-3049) { for x in 2912...2916 {
            for y in 25...40 where isLog(w.builtBlock(x, y, z)) && !isLog(w.builtBlock(x, y - 1, z)) && isLog(w.builtBlock(x, y + 1, z))
                && isLog(w.builtBlock(x, y + 3, z)) { feet.append(IVec3(x, y, z)); break }
        } }
        print("fellhalf: feet " + feet.map { "\($0.x) \($0.y - 64) \($0.z)" }.joined(separator: ", "))
        guard let a = feet.first(where: { $0.x == 2914 && $0.z == -3051 }) ?? feet.first,
              let b = feet.first(where: { $0 != a && $0.y == a.y && Felling.sameTrunk($0, a) }) else {
            check(false, "fellhalf: his dark oak at 2914 -33 -3051 has a 2x2 foot (\(feet.count) feet found)"); return
        }
        let n0 = Felling.felled
        let cutA = w.builtBlock(a.x, a.y, a.z)
        w.setBlock(a.x, a.y, a.z, AIR)
        g.fellCheck(a, cutA)
        let firstStands = Felling.felled == n0
        let cutB = w.builtBlock(b.x, b.y, b.z)
        w.setBlock(b.x, b.y, b.z, AIR)
        g.fellCheck(b, cutB)
        guard Felling.felled > n0, let s = w.ships.list.last(where: { Felling.isFelled($0) }) else {
            check(false, "fellhalf: his dark oak cut on two feet of four falls (first cut stands: \(firstStands))"); return
        }
        var t: Float = 0
        while t < 8 { w.ships.update(1.0 / 60, game: g); g.fellingTick(1.0 / 60); t += 1.0 / 60 }
        let there = w.ships.list.contains { $0 === s }
        let over = TreeProbeCheck.lean(s)
        check(firstStands && there && over > 45,
              String(format: "fellhalf: his dark oak stands on three feet of four (%@), falls cut on two and goes over (%.0f degrees after 8 s, %@)",
                     firstStands ? "yes" : "no", over, there ? "there" : "GONE"))
    }
}
