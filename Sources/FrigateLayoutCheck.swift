import Foundation
import simd

// P472 (Oct 26 19:44-19:45 and 20:14, inside a Meridian frigate: "there's a hallway that doesn't connect to anything else.
// It's just a hallway. And I had to break through a wall to find other hallways... Why doesn't this lead to the engine
// room?... So if I find the frigate and I want to find the helm, I can fight my way to it"): `questcheck --frigatelayout`
// walks the frigate's plan from the boarding hangar (doors open, ladders and stairs climbed, never through a wall) and
// reports what can't be reached, then prints each deck's plan.
enum FrigateLayoutCheck {
    // The standing cells inside the hull (floor under, room for him) that the walk didn't reach, as connected pockets.
    static func pockets(_ hb: HullBuilder, _ reached: Set<IVec3>, ys: [Int]) -> [(cells: Int, lo: IVec3, hi: IVec3)] {
        var left: Set<IVec3> = []
        for y in ys { for z in 0..<hb.sz { for gx in 0..<hb.sx {
            let x = gx - hb.ox
            let c = IVec3(x, y, z)
            guard !reached.contains(c), hb.get(x, y, z) == AIR, hb.get(x, y + 1, z) == AIR, Blocks.collide[Int(hb.get(x, y - 1, z))] else { continue }
            // Inside: hull above within 12 (not the open top of the spine or the booms).
            var roof = false
            for k in 2...12 where Blocks.collide[Int(hb.get(x, y + k, z))] { roof = true; break }
            if roof { left.insert(c) }
        } } }
        var out: [(Int, IVec3, IVec3)] = []
        while let s = left.first {
            left.remove(s)
            var q = [s], i = 0, lo = s, hi = s
            while i < q.count {
                let c = q[i]; i += 1
                lo = IVec3(min(lo.x, c.x), min(lo.y, c.y), min(lo.z, c.z)); hi = IVec3(max(hi.x, c.x), max(hi.y, c.y), max(hi.z, c.z))
                for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)] where left.contains(c + d) { left.remove(c + d); q.append(c + d) }
            }
            out.append((q.count, lo, hi))
        }
        return out.sorted { $0.0 > $1.0 }
    }

    // One walking level as text, bow at the top: '.' reached floor, 'o' floor not reached, '#' wall, 'D' door, 'H' ladder,
    // '/' stairs, 'c' chest, 'k' console or cabinet, '*' helm, ' ' outside.
    static func plan(_ hb: HullBuilder, _ reached: Set<IVec3>, y: Int, z0: Int, z1: Int) -> [String] {
        var rows: [String] = []
        for z in z0...z1 {
            var row = String(format: "%3d ", z)
            for gx in 0..<hb.sx {
                let x = gx - hb.ox
                let b = hb.get(x, y, z), key = Blocks.key(Blocks.groupBase[Int(b)]), sh = Blocks.shape[Int(b)]
                let ch: Character
                if reached.contains(IVec3(x, y, z)) { ch = "." }
                else if b == AIR { ch = Blocks.collide[Int(hb.get(x, y - 1, z))] && hb.get(x, y + 1, z) == AIR ? "o" : " " }
                else if sh == "door" { ch = "D" } else if key == "ladder" { ch = "H" } else if sh == "stairs" { ch = "/" }
                else if key.hasSuffix("chest") { ch = "c" } else if key == "command_console" || key == "data_cabinet" { ch = "k" }
                else if key == "ship_helm" { ch = "*" } else { ch = "#" }
                row.append(ch)
            }
            rows.append(row)
        }
        return rows
    }

    static func run(_ check: (Bool, String) -> Void) {
        let t0 = CFAbsoluteTimeGetCurrent()
        let hb = Capital.capitalFrigate()
        print(String(format: "frigatelayout: the frigate built in %.0f ms (with its walk-through doors)", (CFAbsoluteTimeGetCurrent() - t0) * 1000))
        let hangar = IVec3(-6, 9, 106)
        let reached = Capital.walkable(hb, from: hangar)
        let helm = IVec3(0, 25, 75), engine = IVec3(0, 9, 140), bridgeDeck = IVec3(0, 25, 82)
        let ys = [3, 9, 15, 21, 25]
        if ProcessInfo.processInfo.environment["FRIGATE_PLANS"] != nil {
            for y in ys { print("frigatelayout: walk level y \(y)"); for r in plan(hb, reached, y: y, z0: 0, z1: hb.sz - 1) { print(r) } }
        }
        check(reached.contains(helm) || reached.contains(bridgeDeck), "frigatelayout: from the boarding hangar he walks to the helm (\(reached.contains(helm)))")
        check(reached.contains(engine), "frigatelayout: ... and down to the engine room")
        // P472 (20:14, "Design a ship like a ship would be designed... intuitively designed"): one stairwell from the hangar
        // to the bridge, no ladder on the way.
        let byStairs = Capital.walkable(hb, from: hangar, ladders: false)
        check(byStairs.contains(helm) || byStairs.contains(bridgeDeck), "frigatelayout P472: hangar to the helm by stairs alone, no ladder (\(byStairs.count) cells that way)")
        let pk = pockets(hb, reached, ys: ys)
        let big = pk.filter { $0.cells >= 6 }
        for p in big.prefix(12) { print("frigatelayout: unreached \(p.cells) cells, x \(p.lo.x)...\(p.hi.x) y \(p.lo.y) z \(p.lo.z)...\(p.hi.z)") }
        // P476: fifty aboard, every post a cell he can walk to.
        let posts = hb.crew.map { IVec3(Int(floor($0.x)) - hb.ox, Int($0.y), Int(floor($0.z))) }
        let onFoot = posts.filter { reached.contains($0) }.count
        check(hb.crew.count == 50 && onFoot >= 45, "frigatelayout P476: \(hb.crew.count) crew posts aboard, \(onFoot) of them on the walk from the hangar")
        check(big.isEmpty, "frigatelayout: every room and hallway inside is reached from the hangar without breaking a wall (\(reached.count) cells reached, \(big.count) pockets of 6+ not)")
        // P504 (Nov 1 07:43, "how are the engines floating in space inside the ship?"): every block of the hull joins
        // the rest face to face (the old upper engines hung in the air over the catwalk), and the engine room is
        // machinery: the drive's engine blocks, a reactor core, field coils, conduits and gauges.
        do {
            var seen = [Bool](repeating: false, count: hb.blocks.count)
            let start = hb.blocks.firstIndex { $0 != AIR } ?? 0
            var stack = [start], joined = 0
            seen[start] = true
            while let i = stack.popLast() {
                joined += 1
                let x = i % hb.sx, z = (i / hb.sx) % hb.sz, y = i / (hb.sx * hb.sz)
                for (dx, dy, dz) in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
                    let nx = x + dx, ny = y + dy, nz = z + dz
                    guard nx >= 0 && nx < hb.sx && ny >= 0 && ny < hb.sy && nz >= 0 && nz < hb.sz else { continue }
                    let j = nx + nz * hb.sx + ny * hb.sx * hb.sz
                    if !seen[j] && hb.blocks[j] != AIR { seen[j] = true; stack.append(j) }
                }
                // (a flight of stairs is one piece: each step meets the next along its edge, a block up and a block on)
                if Blocks.shape[Int(hb.blocks[i])] == "stairs" {
                    for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { for dy in [1, -1] {
                        let nx = x + dx, ny = y + dy, nz = z + dz
                        guard nx >= 0 && nx < hb.sx && ny >= 0 && ny < hb.sy && nz >= 0 && nz < hb.sz else { continue }
                        let j = nx + nz * hb.sx + ny * hb.sx * hb.sz
                        if !seen[j] && Blocks.shape[Int(hb.blocks[j])] == "stairs" { seen[j] = true; stack.append(j) }
                    } }
                }
            }
            let solid = hb.blocks.filter { $0 != AIR }.count
            if joined < solid {
                // Where the loose blocks are, by kind (blueprint x as the layout's own, centred on 0).
                var loose: [String: (Int, IVec3, IVec3)] = [:]
                for (i, bl) in hb.blocks.enumerated() where bl != AIR && !seen[i] {
                    let c = IVec3(i % hb.sx - hb.ox, i / (hb.sx * hb.sz), (i / hb.sx) % hb.sz)
                    let k = Blocks.key(bl)
                    let e = loose[k] ?? (0, c, c)
                    loose[k] = (e.0 + 1, IVec3(min(e.1.x, c.x), min(e.1.y, c.y), min(e.1.z, c.z)), IVec3(max(e.2.x, c.x), max(e.2.y, c.y), max(e.2.z, c.z)))
                }
                for (k, e) in loose.sorted(by: { $0.value.0 > $1.value.0 }).prefix(12) {
                    print("frigatelayout: loose \(e.0) \(k), x \(e.1.x)...\(e.2.x) y \(e.1.y)...\(e.2.y) z \(e.1.z)...\(e.2.z)")
                }
                // (each loose cell of the smaller groups, with what is round it)
                var shown = 0
                for (i, bl) in hb.blocks.enumerated() where bl != AIR && !seen[i] && (loose[Blocks.key(bl)]?.0 ?? 0) <= 20 && shown < 40 {
                    let c = IVec3(i % hb.sx - hb.ox, i / (hb.sx * hb.sz), (i / hb.sx) % hb.sz)
                    let round = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)].map { d -> String in
                        let b = hb.get(c.x + d.0, c.y + d.1, c.z + d.2); return b == AIR ? "-" : Blocks.key(b) }
                    print("frigatelayout:   \(Blocks.key(bl)) at \(c.x),\(c.y),\(c.z): +x \(round[0]), -x \(round[1]), up \(round[2]), down \(round[3]), +z \(round[4]), -z \(round[5])")
                    shown += 1
                }
            }
            // (bloom: the other capital hulls, how many loose pieces they hold, and the cost of joining them)
            for (name, mk) in [("Stormwarden Frigate", { Capital.frigate() }), ("Ironback Crawler", { Capital.crawler() })] as [(String, () -> HullBuilder)] {
                HullBuilder.keepIslands = true
                let h = mk()
                HullBuilder.keepIslands = false
                // (what floats, by kind, before the join)
                do {
                    var seen = [Bool](repeating: false, count: h.blocks.count)
                    var best: [Int] = []
                    for i in 0..<h.blocks.count where h.blocks[i] != AIR && !seen[i] {
                        var stack = [i], comp: [Int] = []
                        seen[i] = true
                        while let k = stack.popLast() {
                            comp.append(k)
                            let x = k % h.sx, z = (k / h.sx) % h.sz, y = k / (h.sx * h.sz)
                            for (dx, dy, dz) in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
                                let nx = x + dx, ny = y + dy, nz = z + dz
                                guard nx >= 0 && nx < h.sx && ny >= 0 && ny < h.sy && nz >= 0 && nz < h.sz else { continue }
                                let j = nx + nz * h.sx + ny * h.sx * h.sz
                                if !seen[j] && h.blocks[j] != AIR { seen[j] = true; stack.append(j) }
                            }
                        }
                        if comp.count > best.count { best = comp }
                    }
                    var main = [Bool](repeating: false, count: h.blocks.count)
                    for k in best { main[k] = true }
                    var loose: [String: (Int, IVec3, IVec3)] = [:]
                    for (i, bl) in h.blocks.enumerated() where bl != AIR && !main[i] {
                        let c = IVec3(i % h.sx - h.ox, i / (h.sx * h.sz), (i / h.sx) % h.sz)
                        let e = loose[Blocks.key(bl)] ?? (0, c, c)
                        loose[Blocks.key(bl)] = (e.0 + 1, IVec3(min(e.1.x, c.x), min(e.1.y, c.y), min(e.1.z, c.z)), IVec3(max(e.2.x, c.x), max(e.2.y, c.y), max(e.2.z, c.z)))
                    }
                    for (k, e) in loose.sorted(by: { $0.value.0 > $1.value.0 }).prefix(14) {
                        print("frigatelayout: \(name) loose \(e.0) \(k), x \(e.1.x)...\(e.2.x) y \(e.1.y)...\(e.2.y) z \(e.1.z)...\(e.2.z)")
                    }
                }
                let t1 = CFAbsoluteTimeGetCurrent()
                let n = h.joinIslands()
                print(String(format: "frigatelayout: the %@ (%dx%dx%d) as drawn has %d loose pieces (%.0f ms to find and join them, on the builder's worker)", name, h.sx, h.sy, h.sz, n,
                             (CFAbsoluteTimeGetCurrent() - t1) * 1000))
                let again = h.joinIslands()
                check(again == 0, "frigatelayout P504: the \(name) as built has no loose piece (\(n) joined, \(again) left)")
            }
            var kinds: [String: Int] = [:]
            for z in 121...154 { for y in 0..<hb.sy { for x in -13...13 {
                let k = Blocks.key(hb.get(x, y, z))
                if ["ship_engine", "frigate_reactor", "frigate_coil", "frigate_conduit", "frigate_gauge"].contains(k) { kinds[k, default: 0] += 1 }
            } } }
            let parts = kinds.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
            check(joined == solid && kinds.count == 5 && (kinds["ship_engine"] ?? 0) >= 1000,
                  "frigatelayout P504: \(joined) of \(solid) blocks join the hull (none float); the engine room holds \(parts)")
        }
    }
}
