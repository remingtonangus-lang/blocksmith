import Foundation

// P447 (Remington, Oct 25 08:59, Quest World, a forest at -1134 68 -43: "we still have the procedural attachment of the
// things. Gotta get rid of that. I already asked for that. It wasn't removed"; 09:00 "make sure the leaves don't break
// off either"). P433 (#470) took every design with a second stem off the trunk or a kink out of the generator, but only
// new land grows new trees: a chunk saved before then (any chunk where water settled, grass spread or he built) still
// has the old twin birches, leaning oaks and kinked trunks. Each chunk read from disk is tidied as it loads:
//  - a second stem: an upright run of 3+ logs whose foot leans on a bigger trunk's lowest 3 logs while that trunk goes
//    on up past it (twin birch, tall twin birch, a stem off the base) is taken out with its limbs, and the leaves that
//    were its crown (near its logs, near no log left) go with it, so no clump of leaves is left hanging;
//  - a kink: a trunk whose top log stands beside the foot of the trunk carrying on up (leaning oak, kinked birch, the
//    leaning swamp oak, the saltpalm kink: two trunks side by side for a block) loses that top log, so it is one trunk
//    leaning over by a block (drawn as one bent trunk, as an acacia's lean).
// 2x2 trunks (dark oaks, giant spruces and jungle trees) are left alone, and so is anything touching the chunk's edge
// (its other half is in the next chunk). The current designs have neither (questcheck --treerepair checks every one).
// Not saved back: the same tidy runs every time the chunk loads, and finds nothing the second time once he builds there.
enum TreeRepair {
    static var enabled = ProcessInfo.processInfo.environment["BS_TREEREPAIR"] != "0"
    static var stems = 0, kinks = 0                  // (checks: taken out since start)
    private static let lock = NSLock()

    private struct Run { let x: Int, z: Int, y0: Int, y1: Int; var h: Int { y1 - y0 + 1 } }

    // Tidies a chunk's blocks (x + z * 16 + y * 256); returns how many logs and leaves it took out.
    @discardableResult
    static func tidy(_ b: inout [BlockID]) -> Int {
        guard enabled else { return 0 }
        let H = b.count / CSQ
        guard H > 2 else { return 0 }
        @inline(__always) func at(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
            guard x >= 0 && x < CS && z >= 0 && z < CS && y >= 0 && y < H else { return AIR }
            return b[x + z * CS + y * CSQ]
        }
        @inline(__always) func upright(_ id: BlockID) -> Bool { ShapeTrunks.isLog[Int(id)] && ShapeTrunks.axisOf[Int(id)] == 1 }
        // Upright runs of logs, by column.
        var runs: [Run] = []
        var runAt: [Int: Int] = [:]                  // cell index -> run
        for z in 0..<CS { for x in 0..<CS {
            var y = 0
            while y < H {
                guard upright(b[x + z * CS + y * CSQ]) else { y += 1; continue }
                var y1 = y
                while y1 + 1 < H && upright(b[x + z * CS + (y1 + 1) * CSQ]) { y1 += 1 }
                let r = Run(x: x, z: z, y0: y, y1: y1)
                for yy in y...y1 { runAt[x + z * CS + yy * CSQ] = runs.count }
                runs.append(r)
                y = y1 + 1
            }
        } }
        guard runs.count > 1 else { return 0 }
        // The bigger of two runs (the one that stays): taller, then lower, then by place.
        func bigger(_ p: Run, _ r: Run) -> Bool {
            if p.h != r.h { return p.h > r.h }
            if p.y0 != r.y0 { return p.y0 < r.y0 }
            return (p.x, p.z) < (r.x, r.z)
        }
        // Part of a 2x2 trunk at this height: a square of upright logs holding the column.
        func wide(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            for (ox, oz) in [(0, 0), (-1, 0), (0, -1), (-1, -1)] {
                if upright(at(x + ox, y, z + oz)) && upright(at(x + ox + 1, y, z + oz)) && upright(at(x + ox, y, z + oz + 1)) && upright(at(x + ox + 1, y, z + oz + 1)) { return true }
            }
            return false
        }
        var gone = Set<Int>()                        // log cells taken out
        var stemLogs: [IVec3] = []                   // (the second stems' logs: their crowns go with them)
        for (ri, r) in runs.enumerated() where r.h >= 3 {
            guard r.x > 0 && r.x < CS - 1 && r.z > 0 && r.z < CS - 1, !wide(r.x, r.y0, r.z) else { continue }
            // The trunk its foot leans on.
            var parent: Run?
            for dy in -1...0 { for dz in -1...1 { for dx in -1...1 where dx != 0 || dz != 0 {
                let x = r.x + dx, y = r.y0 + dy, z = r.z + dz
                guard x >= 0 && x < CS && z >= 0 && z < CS && y >= 0, let pi = runAt[x + z * CS + y * CSQ], pi != ri else { continue }
                let p = runs[pi]
                if bigger(p, r) && (parent.map { bigger(p, $0) } ?? true) { parent = p }
            } } }
            guard let p = parent, !wide(p.x, p.y0, p.z) else { continue }
            let att = r.y0 - p.y0
            if att >= 0 && att <= 2 && p.y1 >= r.y0 + 3 {
                // A second stem off the base.
                for y in r.y0...r.y1 { gone.insert(r.x + r.z * CS + y * CSQ); stemLogs.append(IVec3(r.x, y, r.z)) }
                lock.lock(); stems += 1; lock.unlock()
            }
        }
        // Kinks: the trunk carrying on up (r) stands with its foot beside the top log of the trunk under it (p). Not in
        // acacias and cherries: their rising limbs step up the same way, and that is their look.
        let stepped: Set<BlockID> = [Blocks.id("acacia_log"), Blocks.id("cherry_log")].reduce(into: []) { set, b in
            var s = Int(Blocks.groupBase[Int(b)])
            while s < Blocks.count && Blocks.groupBase[s] == Blocks.groupBase[Int(b)] { set.insert(BlockID(s)); s += 1 }
        }
        for (ri, r) in runs.enumerated() where r.h >= 2 {
            guard r.x > 0 && r.x < CS - 1 && r.z > 0 && r.z < CS - 1, !wide(r.x, r.y0, r.z), !gone.contains(r.x + r.z * CS + r.y0 * CSQ),
                  !stepped.contains(b[r.x + r.z * CS + r.y0 * CSQ]) else { continue }
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                guard let pi = runAt[r.x + dx + (r.z + dz) * CS + r.y0 * CSQ], pi != ri else { continue }
                let p = runs[pi]
                guard p.y1 == r.y0 && p.y0 < r.y0 && !wide(p.x, p.y1, p.z) else { continue }
                gone.insert(p.x + p.z * CS + p.y1 * CSQ)
                lock.lock(); kinks += 1; lock.unlock()
                break
            }
        }
        guard !gone.isEmpty else { return 0 }
        // A second stem's limbs: logs joined to it (not another trunk's run of 3+), nearer it than any trunk left.
        var queue = stemLogs
        let kept = runs.enumerated().filter { $0.element.h >= 3 && !gone.contains($0.element.x + $0.element.z * CS + $0.element.y0 * CSQ) }.map { $0.element }
        while let c = queue.popLast() {
            for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 || dz != 0 {
                let x = c.x + dx, y = c.y + dy, z = c.z + dz
                guard x >= 0 && x < CS && z >= 0 && z < CS && y >= 0 && y < H else { continue }
                let i = x + z * CS + y * CSQ
                guard !gone.contains(i), ShapeTrunks.isLog[Int(b[i])] else { continue }
                if let ri = runAt[i], runs[ri].h >= 3 { continue }
                let mine = stemLogs.map { max(abs($0.x - x), abs($0.z - z)) }.min() ?? 99
                let theirs = kept.map { max(abs($0.x - x), abs($0.z - z)) }.min() ?? 99
                guard mine < theirs else { continue }
                gone.insert(i); stemLogs.append(IVec3(x, y, z)); queue.append(IVec3(x, y, z))
            } } }
        }
        // Its crown: leaves within 3 of a log taken out and 3 or more from every log left.
        var leaves: [Int] = []
        for c in stemLogs {
            for dy in -3...3 { for dz in -3...3 { for dx in -3...3 {
                let x = c.x + dx, y = c.y + dy, z = c.z + dz
                guard x >= 0 && x < CS && z >= 0 && z < CS && y >= 0 && y < H else { continue }
                let i = x + z * CS + y * CSQ
                if Mesher.leafT[Int(b[i])] { leaves.append(i) }
            } } }
        }
        var n = 0
        for i in gone { b[i] = AIR; n += 1 }
        var seen = Set<Int>()
        for i in leaves where seen.insert(i).inserted {
            let x = i % CS, z = (i / CS) % CS, y = i / CSQ
            var near = false
            for dy in -2...2 where !near { for dz in -2...2 where !near { for dx in -2...2 where !near {
                if ShapeTrunks.isLog[Int(at(x + dx, y + dy, z + dz))] { near = true }
            } } }
            if !near { b[i] = AIR; n += 1 }
        }
        return n
    }
}
