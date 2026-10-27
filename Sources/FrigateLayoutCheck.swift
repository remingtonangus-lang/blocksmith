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
        let helm = IVec3(0, 25, 75), engine = IVec3(0, 9, 130), bridgeDeck = IVec3(0, 25, 82)
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
    }
}
