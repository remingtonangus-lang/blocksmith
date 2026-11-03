import Foundation
import simd

// P512 (Remington, Nov 2 12:22: "a seat for every frigate gun so crew can fire while he drives, and computers for every
// gun"): every gun of a capital hull (the Stormwarden and Meridian frigates, the crawlers) has its own gun station inside
// the hull near the gun's mount: a Command Console against a wall with a chair at it. When he commands a hull of his,
// his companions aboard or near it each take a station (VehicleGunners): they sit at the computer and work that gun,
// laying it on what is out for him and firing it, while he drives (GunCrew.gunCrewTick). Built with the hull
// (Capital.makeShips: new hulls; one taken before keeps its rooms as they were, and its crew stand at the guns instead).
extension Capital {
    static let stationReach = 12

    // Places a station for each mount ring (hull grid cells) where the hull has room: an open cell on a floor, under a
    // roof, with the console's cell beside it on the floor (backed by a wall where one is near). A station never cuts a
    // way through the hull: the largest stretch of floor a crewman can walk (stairs, ladders and doors included) loses
    // no more than the station's own cells and a nook behind it (the boarding check's bot was stuck on the frigate's
    // stairwell behind a chair the first time).
    @discardableResult
    static func addGunStations(_ gr: ShipGrid, rings: [IVec3]) -> Int {
        guard Blocks.has("command_console") else { return 0 }
        let console = Blocks.id("command_console")
        let chairKey = Blocks.has("dark_oak_chair") ? "dark_oak_chair" : "oak_chair"
        guard Blocks.has(chairKey) else { return 0 }
        let collide = Blocks.collide
        func solid(_ x: Int, _ y: Int, _ z: Int) -> Bool { collide[Int(gr.get(x, y, z))] && !ShipParts.console[Int(gr.get(x, y, z))] }
        func open(_ x: Int, _ y: Int, _ z: Int) -> Bool { gr.get(x, y, z) == AIR }
        // (dx, dz) toward the console -> the chair's facing state name
        let dirs: [(Int, Int, String)] = [(0, -1, ""), (0, 1, "[south]"), (-1, 0, "[west]"), (1, 0, "[east]")]
        var placed: [IVec3] = []
        let r = stationReach
        var walk = Walkways(gr)                       // (worked out again only when a station stands)
        for ring in rings {
            var cands: [(IVec3, IVec3, String, Float)] = []
            for y in max(1, ring.y - 10)...max(1, min(gr.sy - 3, ring.y + 10)) {
                for z in max(1, ring.z - r)...max(1, min(gr.sz - 2, ring.z + r)) {
                    for x in max(1, ring.x - r)...max(1, min(gr.sx - 2, ring.x + r)) {
                        guard open(x, y, z), open(x, y + 1, z), solid(x, y - 1, z) else { continue }
                        // Under a roof (inside the hull, not on a deck in the open).
                        var roof = false
                        for k in 2...6 where y + k < gr.sy { if solid(x, y + k, z) { roof = true; break } }
                        guard roof else { continue }
                        let c = IVec3(x, y, z)
                        guard !placed.contains(where: { abs($0.x - x) + abs($0.y - y) + abs($0.z - z) < 4 }) else { continue }
                        let d0 = V3(Float(x - ring.x), Float(y - ring.y), Float(z - ring.z))
                        let dist = simd_length(d0)
                        var best: (IVec3, String, Float)?
                        for (dx, dz, face) in dirs {
                            let k = IVec3(x + dx, y, z + dz)
                            guard open(k.x, k.y, k.z), solid(k.x, k.y - 1, k.z), open(k.x, k.y + 1, k.z) else { continue }
                            let wall = solid(k.x + dx, k.y, k.z + dz)
                            let score = dist + (wall ? 0 : 3)
                            if best == nil || score < best!.2 { best = (k, face, score) }
                        }
                        if let b = best { cands.append((c, b.0, b.1, b.2)) }
                    }
                }
            }
            cands.sort { $0.3 < $1.3 }
            for (c, k, face, _) in cands.prefix(12) {
                let before = walk.largest
                gr.set(c.x, c.y, c.z, Blocks.id(chairKey + face))
                gr.set(k.x, k.y, k.z, console)
                let after = Walkways(gr)
                if after.largest >= before - 8 { walk = after; placed.append(c); break }
                gr.set(c.x, c.y, c.z, AIR)
                gr.set(k.x, k.y, k.z, AIR)
            }
        }
        return placed.count
    }

    // The hull's floor a crewman can stand on (open, two high, on something solid) and walk between: level, a step up or
    // down (stairs), up and down ladders, through doors. `largest`: the cells of the biggest connected stretch.
    struct Walkways {
        var largest = 0
        // Per block state: walked through, climbed, stood on.
        static let passT: [Bool] = (0..<Blocks.count).map { let sh = Blocks.shape[$0]; return !Blocks.collide[$0] || sh == "door" || sh == "gate" || sh == "trapdoor" }
        static let ladderT: [Bool] = (0..<Blocks.count).map { Blocks.shape[$0] == "ladder" }
        static let floorT: [Bool] = (0..<Blocks.count).map { let sh = Blocks.shape[$0]; return Blocks.collide[$0] && sh != "door" && sh != "trapdoor" }
        init(_ gr: ShipGrid) {
            let passT = Walkways.passT, ladderT = Walkways.ladderT, floorT = Walkways.floorT
            let n = gr.sx * gr.sy * gr.sz
            func pass(_ x: Int, _ y: Int, _ z: Int) -> Bool { passT[Int(gr.get(x, y, z))] }
            func ladder(_ x: Int, _ y: Int, _ z: Int) -> Bool { ladderT[Int(gr.get(x, y, z))] }
            func stand(_ x: Int, _ y: Int, _ z: Int) -> Bool {
                guard x >= 0, y >= 1, z >= 0, x < gr.sx, y < gr.sy - 1, z < gr.sz, pass(x, y, z), pass(x, y + 1, z) else { return false }
                return floorT[Int(gr.get(x, y - 1, z))] || ladder(x, y, z) || ladder(x, y - 1, z)
            }
            var seen = [Bool](repeating: false, count: n)
            func idx(_ x: Int, _ y: Int, _ z: Int) -> Int { (y * gr.sz + z) * gr.sx + x }
            var queue: [Int32] = []
            queue.reserveCapacity(4096)
            for y in 1..<max(1, gr.sy - 1) { for z in 0..<gr.sz { for x in 0..<gr.sx {
                let i0 = idx(x, y, z)
                guard !seen[i0], stand(x, y, z) else { continue }
                seen[i0] = true
                queue.removeAll(keepingCapacity: true)
                queue.append(Int32(i0))
                var head = 0
                while head < queue.count {
                    let i = Int(queue[head]); head += 1
                    let cx = i % gr.sx, cz = (i / gr.sx) % gr.sz, cy = i / (gr.sx * gr.sz)
                    for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        for dy in [0, 1, -1] {
                            let x = cx + dx, y = cy + dy, z = cz + dz
                            // (a step up needs headroom over him where he stands)
                            if dy == 1 && !pass(cx, cy + 2, cz) { continue }
                            guard stand(x, y, z) else { continue }
                            let j = idx(x, y, z)
                            if !seen[j] { seen[j] = true; queue.append(Int32(j)) }
                            break
                        }
                    }
                    if ladder(cx, cy, cz) || ladder(cx, cy - 1, cz) {
                        for dy in [1, -1] where stand(cx, cy + dy, cz) {
                            let j = idx(cx, cy + dy, cz)
                            if !seen[j] { seen[j] = true; queue.append(Int32(j)) }
                        }
                    }
                }
                largest = max(largest, queue.count)
            } } }
        }
    }
}

extension VehicleGunners {
    // turret id -> its station in the hull (nil: none in reach). Worked out for all a hull's guns at once.
    static var stationCache: [Int: (chair: IVec3, console: IVec3)?] = [:]

    // The gun station of turret `t` on hull `v`: a chair with a console beside it, near its mount.
    static func station(_ t: Ship, on v: Ship, _ ships: ShipManager) -> (chair: IVec3, console: IVec3)? {
        let gr = v.grid
        func isChair(_ c: IVec3) -> Bool { ChairSeat.seatTop(Blocks.key(Blocks.groupBase[Int(gr.get(c.x, c.y, c.z))])) != nil }
        if let hit = stationCache[t.id] {
            guard let st = hit else { return nil }
            if isChair(st.chair) && ShipParts.console[Int(gr.get(st.console.x, st.console.y, st.console.z))] { return st }
        }
        assignStations(v, ships)
        return stationCache[t.id] ?? nil
    }

    // Every station on hull v (a chair with a console beside it) given to the hull's guns, nearest pairs first, each
    // within reach of its gun's mount; a gun with none in reach has none.
    static func assignStations(_ v: Ship, _ ships: ShipManager) {
        let gr = v.grid
        let turrets = ships.turrets(of: v)
        for t in turrets { stationCache[t.id] = .some(nil) }
        guard !turrets.isEmpty else { return }
        let rings = turrets.map { IVec3(Int(floor($0.mountLocal.x)), Int(floor($0.mountLocal.y)) - 1, Int(floor($0.mountLocal.z))) }
        let r = Capital.stationReach
        var lo = IVec3(Int.max, Int.max, Int.max), hi = IVec3(Int.min, Int.min, Int.min)
        for c in rings {
            lo = IVec3(min(lo.x, c.x - r), min(lo.y, c.y - 10), min(lo.z, c.z - r))
            hi = IVec3(max(hi.x, c.x + r), max(hi.y, c.y + 10), max(hi.z, c.z + r))
        }
        lo = IVec3(max(0, lo.x), max(0, lo.y), max(0, lo.z))
        hi = IVec3(min(gr.sx - 1, hi.x), min(gr.sy - 1, hi.y), min(gr.sz - 1, hi.z))
        guard lo.x <= hi.x, lo.y <= hi.y, lo.z <= hi.z else { return }
        var stations: [(IVec3, IVec3)] = []
        for y in lo.y...hi.y { for z in lo.z...hi.z { for x in lo.x...hi.x {
            guard ChairSeat.seatTop(Blocks.key(Blocks.groupBase[Int(gr.get(x, y, z))])) != nil else { continue }
            for (dx, dz) in [(0, -1), (0, 1), (-1, 0), (1, 0)] where ShipParts.console[Int(gr.get(x + dx, y, z + dz))] {
                stations.append((IVec3(x, y, z), IVec3(x + dx, y, z + dz))); break
            }
        } } }
        var pairs: [(Float, Int, Int)] = []
        for (ti, c) in rings.enumerated() {
            for (si, st) in stations.enumerated() {
                let d = st.0 - c
                guard abs(d.x) <= r, abs(d.z) <= r, abs(d.y) <= 10 else { continue }
                pairs.append((simd_length(V3(Float(d.x), Float(d.y), Float(d.z))), ti, si))
            }
        }
        pairs.sort { $0.0 < $1.0 }
        var gunDone = Set<Int>(), seatDone = Set<Int>()
        for (_, ti, si) in pairs where !gunDone.contains(ti) && !seatDone.contains(si) {
            gunDone.insert(ti); seatDone.insert(si)
            stationCache[turrets[ti].id] = .some((stations[si].0, stations[si].1))
        }
    }
}
