import Foundation
import Metal
import simd

// P388 checks (questcheck):
//   --loadtest    (7): test builds high over the ground on bedrock pads (bedrock is ground to a structure): a wool bridge
//                 at each span, a log beam reaching out, a plank house with and without titanium piled on its roof, a
//                 stone arch and a flat stone lintel; what of each falls.
//   --loadcheck [--seeds A,B --per N --kinds K,...] [--field]   (5): every structure type the generator builds, each
//                 built piece in it checked whole (no 4,096-block bound); what would fall, by kind.
extension Structure {
    static var tiDownAt = 0     // (the pile height that brought the test roof down: the in-play test piles that)
    static func loadTest(_ w: World, at base: IVec3) -> String {
        var lines = ["loadtest (P388): what falls of each test build (falls / blocks)"]
        var y = base.y
        func clear(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, _ z0: Int, _ z1: Int) {
            for yy in y0...y1 { for z in z0...z1 { for x in x0...x1 { w.setBlock(x, yy, z, AIR) } } }
        }
        func run(_ name: String, _ at: IVec3, _ build: () -> Void) -> Result {
            build()
            let r = analyse(w, at: at)
            lines.append(String(format: "  %@: %d / %d (reach %d, joints %d)", name, r.falls.count, r.cells, r.reachBreaks, r.jointBreaks))
            return r
        }
        let bx = base.x, bz = base.z
        let bedrock = Blocks.id("bedrock"), wool = Blocks.id("white_wool"), log = Blocks.id("oak_log"), plank = Blocks.id("oak_planks")
        let stoneB = Blocks.id("stone_bricks"), ti = Blocks.id("diamond_block")
        // Wool bridges between two pads, each span.
        var holds = 0, breaks = 0
        for span in 1...9 {
            clear(bx - 1, bx + 12, y, y + 1, bz, bz)
            w.setBlock(bx, y, bz, bedrock); w.setBlock(bx + span + 1, y, bz, bedrock)
            let r = run("wool bridge, span \(span)", IVec3(bx + 1, y, bz)) { for x in 1...span { w.setBlock(bx + x, y, bz, wool) } }
            if r.falls.isEmpty { holds = span } else if breaks == 0 { breaks = span }
        }
        lines.append("  wool bridge: holds up to a span of \(holds), breaks from \(breaks)")
        y += 4
        // A log beam out from a pad: 6 (its reach) and 8.
        for len in [6, 8] {
            clear(bx - 1, bx + 10, y, y, bz, bz)
            w.setBlock(bx, y, bz, bedrock)
            _ = run("log beam reaching out \(len)", IVec3(bx + 1, y, bz)) { for x in 1...len { w.setBlock(bx + x, y, bz, log) } }
        }
        // The same out of planks (reach 4) and stone (3).
        for (name, b, len) in [("plank beam reaching out", plank, 5), ("stone beam reaching out", stoneB, 4)] {
            clear(bx - 1, bx + 10, y, y, bz, bz)
            w.setBlock(bx, y, bz, bedrock)
            _ = run("\(name) \(len)", IVec3(bx + 1, y, bz)) { for x in 1...len { w.setBlock(bx + x, y, bz, b) } }
        }
        clear(bx - 1, bx + 10, y, y, bz, bz)
        y += 4
        // A plank house (7 x 7, walls 3 high, a flat plank roof) on a bedrock floor; then titanium piled 3 x 3 across the
        // middle of its roof, a course higher each time until the roof comes down.
        func house() {
            for z in 0..<7 { for x in 0..<7 {
                w.setBlock(bx + x, y, bz + z, bedrock)
                let edge = x == 0 || x == 6 || z == 0 || z == 6
                for h in 1...3 { w.setBlock(bx + x, y + h, bz + z, edge ? plank : AIR) }
                w.setBlock(bx + x, y + 4, bz + z, plank)
                for h in 5...17 { w.setBlock(bx + x, y + h, bz + z, AIR) }
            } }
        }
        _ = run("plank house", IVec3(bx + 3, y + 4, bz + 3)) { house() }
        var tiHolds = 0
        tiDownAt = 0
        for high in 1...12 {
            house()
            for h in 5..<(5 + high) { for z in 2...4 { for x in 2...4 { w.setBlock(bx + x, y + h, bz + z, ti) } } }
            let r = analyse(w, at: IVec3(bx + 3, y + 4, bz + 3))
            if r.falls.isEmpty { tiHolds = high; continue }
            tiDownAt = high
            lines.append(String(format: "  titanium piled 3 x 3 on a plank roof: holds %d high (%d blocks), comes down at %d high (%d blocks): %d / %d (reach %d, joints %d)",
                                tiHolds, tiHolds * 9, high, high * 9, r.falls.count, r.cells, r.reachBreaks, r.jointBreaks))
            break
        }
        if tiDownAt == 0 { lines.append("  titanium piled 3 x 3 on a plank roof: holds 12 high (108 blocks)") }
        _ = run("plank house with 4 titanium on its roof", IVec3(bx + 3, y + 4, bz + 3)) {
            house()
            for z in 3...4 { for x in 3...4 { w.setBlock(bx + x, y + 5, bz + z, ti) } }
        }
        clear(bx, bx + 6, y, y + 18, bz, bz + 6)
        y += 20
        // A stone arch: two pillars 4 high, 5 apart, closed by corbelled courses; and a flat lintel over 7 and 9.
        _ = run("stone arch over 5", IVec3(bx + 3, y + 6, bz)) {
            for h in 0...4 { w.setBlock(bx, y + h, bz, h == 0 ? bedrock : stoneB); w.setBlock(bx + 6, y + h, bz, h == 0 ? bedrock : stoneB) }
            for (x, h) in [(1, 4), (5, 4), (1, 5), (2, 5), (4, 5), (5, 5), (2, 6), (3, 6), (4, 6)] { w.setBlock(bx + x, y + h, bz, stoneB) }
        }
        clear(bx, bx + 6, y, y + 7, bz, bz)
        for span in [5, 9, 11, 13] {
            _ = run("stone lintel over \(span)", IVec3(bx + 1, y + 3, bz)) {
                for h in 0...3 { w.setBlock(bx, y + h, bz, h == 0 ? bedrock : stoneB); w.setBlock(bx + span + 1, y + h, bz, h == 0 ? bedrock : stoneB) }
                for x in 1...span { w.setBlock(bx + x, y + 3, bz, stoneB) }
            }
            clear(bx, bx + span + 1, y, y + 3, bz, bz)
        }
        return lines.joined(separator: "\n")
    }

    // (BS_LOAD_DEBUG: what broke in a piece, by block and reach, and a slice of the cells round the first)
    static func debugPiece(_ w: World, _ r: Result) {
        var by: [String: (n: Int, maxReach: Int, hang: Int)] = [:]
        for (c, d, h) in r.why {
            let k = Blocks.key(w.builtBlock(c.x, c.y, c.z))
            var e = by[k] ?? (0, 0, 0); e.n += 1; e.maxReach = max(e.maxReach, d); if h { e.hang += 1 }; by[k] = e
        }
        print("    broke: " + by.sorted { $0.value.n > $1.value.n }.prefix(8).map { "\($0.key) \($0.value.n) (reach to \($0.value.maxReach), \($0.value.hang) hanging)" }.joined(separator: ", "))
        for (c, share, cap) in r.joints.prefix(3) {
            print(String(format: "    joint at %d %d %d (%@): handed on %.0f, holds %.0f", c.x, c.y - YOFF, c.z, Blocks.key(w.builtBlock(c.x, c.y, c.z)), share, cap))
        }
        guard let f = r.why.first?.0 ?? r.joints.first?.0 else { return }
        // (the way it was reached from the ground: each step back toward a block that holds it)
        var idx: [IVec3: Int] = [:]
        for (i, c) in r.all.enumerated() { idx[c] = i }
        if var i = idx[f], i < r.dists.count {
            var steps: [String] = []
            while r.dists[i] > 0 && r.dists[i] != Int.max && steps.count < 40 {
                let c = r.all[i]
                var next: Int? = nil
                for (k, d) in nbrs.enumerated() {
                    guard let j = idx[c - d], j < r.dists.count, r.dists[j] != Int.max else { continue }
                    if r.dists[j] + stepCost[k] == r.dists[i] { next = j; break }
                }
                guard let j = next else { break }
                let q = r.all[j]
                steps.append("\(q.x - f.x),\(q.y - f.y),\(q.z - f.z) \(Blocks.key(w.builtBlock(q.x, q.y, q.z))) \(r.dists[j])")
                i = j
            }
            let c = r.all[i]
            let under = World.allDirs.first { anchor(w, c.x + $0.x, c.y + $0.y, c.z + $0.z) }.map { Blocks.key(w.builtBlock(c.x + $0.x, c.y + $0.y, c.z + $0.z)) + (w.groundAt(c.x + $0.x, c.y + $0.y, c.z + $0.z) ? " (ground)" : "") } ?? "none"
            print("    from \(f.x) \(f.y - YOFF) \(f.z), reach \(r.dists[idx[f]!]): " + steps.joined(separator: " < ") + "; held by \(under)")
        }
        if r.dists.isEmpty || idx[f].map({ r.dists[$0] == Int.max }) ?? true {
            print("    under it: " + (1...8).map { Blocks.key(w.builtBlock(f.x, f.y - $0, f.z)) }.joined(separator: ", "))
            if r.all.count <= 12 { print("    the piece: " + r.all.map { "\(Blocks.key(w.builtBlock($0.x, $0.y, $0.z))) \($0.x) \($0.y - YOFF) \($0.z)" }.joined(separator: ", ")) }
        }
        // (an x-y slice through it: '#' a structure block, 'X' one that broke, 'g' ground, '.' air)
        let broke = Set(r.why.map { $0.0 })
        print("    slice at z \(f.z) round \(f.x) \(f.y - YOFF) (\(Blocks.key(w.builtBlock(f.x, f.y, f.z)))):")
        for y in stride(from: f.y + 6, through: f.y - 8, by: -1) {
            var row = ""
            for x in (f.x - 20)...(f.x + 20) {
                let q = IVec3(x, y, f.z)
                row += broke.contains(q) ? "X" : part(w, x, y, f.z) != nil ? "#" : anchor(w, x, y, f.z) ? "g" : "."
            }
            print("      " + row)
        }
    }

    static func loadCheck(device: MTLDevice) -> Int32 {
        let seeds: [UInt64] = (arg("--seeds") ?? "12345,777").split(separator: ",").compactMap { UInt64($0) }
        let per = Int(arg("--per") ?? "") ?? 2
        let only: Set<String>? = arg("--kinds").map { Set($0.split(separator: ",").map(String.init)) }
        let t0 = CFAbsoluteTimeGetCurrent()
        var byKind: [String: (n: Int, pieces: Int, blocks: Int, falls: Int, held: Int, at: [String])] = [:]
        for seed in seeds {
            let world = World(seed: seed, device: device, save: nil, dim: .overworld)
            guard let cache = world.gen.structures else { continue }
            var kinds: [(String, [StructureStart])] = []
            for t in cache.types where only == nil || only!.contains(t.name) {
                var found: [StructureStart] = []
                var r = 0
                while found.count < per && r < 6 {
                    for rz in -r...r { for rx in -r...r where max(abs(rx), abs(rz)) == r && found.count < per {
                        if let s = cache.start(t, regionX: rx, regionZ: rz) { found.append(s) }
                    } }
                    r += 1
                }
                kinds.append((t.name, found))
            }
            for k in Set(cache.fixed.map { $0.kind }) where only == nil || only!.contains(k) {
                let fs = cache.fixed.filter { $0.kind == k }.sorted { abs($0.anchor.x) + abs($0.anchor.z) < abs($1.anchor.x) + abs($1.anchor.z) }
                kinds.append((k, Array(fs.prefix(per))))
            }
            for (name, starts) in kinds {
                for s in starts {
                    let lo = IVec3(s.min.x - 4, max(1, s.min.y - 4), s.min.z - 4), hi = IVec3(s.max.x + 4, min(CH - 2, s.max.y + 4), s.max.z + 4)
                    let cx0 = floorDiv(lo.x, CS), cz0 = floorDiv(lo.z, CS), cx1 = floorDiv(hi.x, CS), cz1 = floorDiv(hi.z, CS)
                    guard cx1 - cx0 <= 24 && cz1 - cz0 <= 24 else { continue }
                    world.loadBlocks(cx0: cx0 - 2, cz0: cz0 - 2, cx1: cx1 + 2, cz1: cz1 + 2)
                    var st = byKind[name] ?? (0, 0, 0, 0, 0, [])
                    st.n += 1
                    var seen = Set<IVec3>()
                    for y in lo.y...hi.y { for z in lo.z...hi.z { for x in lo.x...hi.x {
                        let q = IVec3(x, y, z)
                        guard !seen.contains(q), part(world, x, y, z) != nil else { continue }
                        let r = analyse(world, at: q, limit: 400_000, out: 600, collect: true)
                        if r.cells == 0 { st.held += 1; seen.insert(q); seen.formUnion(r.all); continue }
                        seen.formUnion(r.all)
                        st.pieces += 1; st.blocks += r.cells; st.falls += r.falls.count
                        if !r.falls.isEmpty, ProcessInfo.processInfo.environment["BS_LOAD_DEBUG"] != nil { debugPiece(world, r) }
                        if let f = r.falls.first, st.at.count < 6 {
                            st.at.append("seed \(seed) \(Blocks.key(world.builtBlock(f.x, f.y, f.z))) at \(f.x) \(f.y - YOFF) \(f.z): \(r.falls.count) of \(r.cells) (reach \(r.reachBreaks), joints \(r.jointBreaks))")
                        }
                    } } }
                    byKind[name] = st
                    world.unloadAll()
                    world.blockEntities.removeAll()
                    world.pendingMobs.removeAll()
                }
            }
        }
        var total = 0
        for k in byKind.keys.sorted() {
            let st = byKind[k]!
            total += st.falls
            print("loadcheck \(k): \(st.n) built, \(st.pieces) pieces, \(st.blocks) blocks, \(st.falls) would fall" + (st.held > 0 ? ", \(st.held) too big to check" : ""))
            for a in st.at { print("  \(a)") }
        }
        print(String(format: "loadcheck: %d blocks would fall in %.1f s (%@ world)", total, CFAbsoluteTimeGetCurrent() - t0, FieldTerrain.unsaved ? "field" : "block"))
        return total > 0 ? 2 : 0
    }
}
