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
    static let stationReachFar = 18, stationUpFar = 16          // (the second, wider look)
    // (the last look, for a gun with no room near it at all, the Stormwarden's mast-top gun: its computer is wherever the
    // hull has room nearest it, worked from there as any fire control)
    static let stationReachLast = 40, stationUpLast = 48

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
        let collide = Blocks.collide, kinds = ShipParts.kinds, consoles = ShipParts.console
        func solid(_ x: Int, _ y: Int, _ z: Int) -> Bool { collide[Int(gr.get(x, y, z))] && !consoles[Int(gr.get(x, y, z))] }
        func open(_ x: Int, _ y: Int, _ z: Int) -> Bool { gr.get(x, y, z) == AIR }
        // The helms (and any console already in the hull): a station keeps 3 blocks clear of them, so the man at the helm
        // keeps his stand (P512: a chair on the Stormwarden's helm stand put him off command).
        var helms: [IVec3] = []
        for y in 0..<gr.sy { for z in 0..<gr.sz { for x in 0..<gr.sx {
            let b = Int(gr.get(x, y, z))
            if b != Int(AIR) && (kinds[b] == .helm || consoles[b]) { helms.append(IVec3(x, y, z)) }
        } } }
        func nearHelm(_ c: IVec3) -> Bool { helms.contains { abs($0.x - c.x) <= 3 && abs($0.z - c.z) <= 3 && abs($0.y - c.y) <= 2 } }
        // Nor on a stair, landing or doorway's way (the boarding check's walk to the helm was stopped on the Stormwarden's
        // upper landing by a chair beside its stair): no stair, ladder, door or hatch within two blocks.
        let wayT = Walkways.wayT
        func byWay(_ c: IVec3) -> Bool {
            for y in (c.y - 1)...(c.y + 1) { for z in (c.z - 2)...(c.z + 2) { for x in (c.x - 2)...(c.x + 2) where wayT[Int(gr.get(x, y, z))] { return true } } }
            return false
        }
        // (dx, dz) toward the console -> the chair's facing state name
        let dirs: [(Int, Int, String)] = [(0, -1, ""), (0, 1, "[south]"), (-1, 0, "[west]"), (1, 0, "[east]")]
        var placed: [IVec3] = []
        // Near the mount under a low roof first; a gun with no room there (a keel gun over a tall hangar, a mast-top gun)
        // looks wider, under a higher roof.
        var served = [Bool](repeating: false, count: rings.count)
        for (reach, up, roofMax) in [(stationReach, 10, 6), (stationReachFar, stationUpFar, 14), (stationReachLast, stationUpLast, 30)] {
            for (ri, ring) in rings.enumerated() where !served[ri] {
                var cands: [(IVec3, IVec3, String, Float)] = []
                for y in thru(max(1, ring.y - up), max(1, min(gr.sy - 3, ring.y + up))) {
                    for z in thru(max(1, ring.z - reach), max(1, min(gr.sz - 2, ring.z + reach))) {
                        for x in thru(max(1, ring.x - reach), max(1, min(gr.sx - 2, ring.x + reach))) {
                            guard open(x, y, z), open(x, y + 1, z), solid(x, y - 1, z) else { continue }
                            // Under a roof (inside the hull, not on a deck in the open).
                            var roof = false
                            for k in 2...roofMax where y + k < gr.sy { if solid(x, y + k, z) { roof = true; break } }
                            guard roof else { continue }
                            let c = IVec3(x, y, z)
                            guard !placed.contains(where: { abs($0.x - x) + abs($0.y - y) + abs($0.z - z) < 4 }), !nearHelm(c), !byWay(c) else { continue }
                            let dist = simd_length(V3(Float(x - ring.x), Float(y - ring.y), Float(z - ring.z)))
                            var best: (IVec3, String, Float)?
                            for (dx, dz, face) in dirs {
                                let k = IVec3(x + dx, y, z + dz)
                                guard open(k.x, k.y, k.z), solid(k.x, k.y - 1, k.z), open(k.x, k.y + 1, k.z), !byWay(k) else { continue }
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
                    // A station never cuts a way through: round it, the largest stretch of walkable floor loses no more
                    // than its own cells and a nook behind it.
                    let lo = c - IVec3(20, 12, 20), hi = c + IVec3(20, 12, 20)
                    let before = Walkways(gr, lo, hi).largest
                    gr.set(c.x, c.y, c.z, Blocks.id(chairKey + face))
                    gr.set(k.x, k.y, k.z, console)
                    if Walkways(gr, lo, hi).largest >= before - 8 { placed.append(c); served[ri] = true; break }
                    gr.set(c.x, c.y, c.z, AIR)
                    gr.set(k.x, k.y, k.z, AIR)
                }
            }
        }
        return placed.count
    }

    // The hull's floor a crewman can stand on (open, two high, on something solid) and walk between, inside the box lo...hi:
    // level, a step up or down (stairs), up and down ladders, through doors. `largest`: the cells of its biggest stretch.
    struct Walkways {
        var largest = 0
        // Per block state: walked through, climbed, stood on.
        static let passT: [Bool] = (0..<Blocks.count).map { let sh = Blocks.shape[$0]; return !Blocks.collide[$0] || sh == "door" || sh == "gate" || sh == "trapdoor" }
        static let ladderT: [Bool] = (0..<Blocks.count).map { Blocks.shape[$0] == "ladder" }
        static let wayT: [Bool] = (0..<Blocks.count).map { let sh = Blocks.shape[$0]; return sh == "stairs" || sh == "ladder" || sh == "door" || sh == "trapdoor" }
        static let floorT: [Bool] = (0..<Blocks.count).map { let sh = Blocks.shape[$0]; return Blocks.collide[$0] && sh != "door" && sh != "trapdoor" }
        init(_ gr: ShipGrid, _ lo0: IVec3, _ hi0: IVec3) {
            let passT = Walkways.passT, ladderT = Walkways.ladderT, floorT = Walkways.floorT
            let lo = IVec3(max(0, lo0.x), max(1, lo0.y), max(0, lo0.z))
            let hi = IVec3(min(gr.sx - 1, hi0.x), min(gr.sy - 2, hi0.y), min(gr.sz - 1, hi0.z))
            guard lo.x <= hi.x, lo.y <= hi.y, lo.z <= hi.z else { return }
            let bx = hi.x - lo.x + 1, by = hi.y - lo.y + 1, bz = hi.z - lo.z + 1
            func pass(_ x: Int, _ y: Int, _ z: Int) -> Bool { passT[Int(gr.get(x, y, z))] }
            func ladder(_ x: Int, _ y: Int, _ z: Int) -> Bool { ladderT[Int(gr.get(x, y, z))] }
            func stand(_ x: Int, _ y: Int, _ z: Int) -> Bool {
                guard x >= lo.x, y >= lo.y, z >= lo.z, x <= hi.x, y <= hi.y, z <= hi.z, pass(x, y, z), pass(x, y + 1, z) else { return false }
                return floorT[Int(gr.get(x, y - 1, z))] || ladder(x, y, z) || ladder(x, y - 1, z)
            }
            var seen = [Bool](repeating: false, count: bx * by * bz)
            func idx(_ x: Int, _ y: Int, _ z: Int) -> Int { ((y - lo.y) * bz + (z - lo.z)) * bx + (x - lo.x) }
            var queue: [IVec3] = []
            queue.reserveCapacity(4096)
            for y in lo.y...hi.y { for z in lo.z...hi.z { for x in lo.x...hi.x {
                guard !seen[idx(x, y, z)], stand(x, y, z) else { continue }
                seen[idx(x, y, z)] = true
                queue.removeAll(keepingCapacity: true)
                queue.append(IVec3(x, y, z))
                var head = 0
                while head < queue.count {
                    let c = queue[head]; head += 1
                    for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        for dy in [0, 1, -1] {
                            let nx = c.x + dx, ny = c.y + dy, nz = c.z + dz
                            // (a step up needs headroom over him where he stands)
                            if dy == 1 && !pass(c.x, c.y + 2, c.z) { continue }
                            guard stand(nx, ny, nz) else { continue }
                            if !seen[idx(nx, ny, nz)] { seen[idx(nx, ny, nz)] = true; queue.append(IVec3(nx, ny, nz)) }
                            break
                        }
                    }
                    if ladder(c.x, c.y, c.z) || ladder(c.x, c.y - 1, c.z) {
                        for dy in [1, -1] where stand(c.x, c.y + dy, c.z) && !seen[idx(c.x, c.y + dy, c.z)] {
                            seen[idx(c.x, c.y + dy, c.z)] = true; queue.append(IVec3(c.x, c.y + dy, c.z))
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
        let r = Capital.stationReachLast, up = Capital.stationUpLast
        let rNear = Capital.stationReachFar, upNear = Capital.stationUpFar
        var lo = IVec3(Int.max, Int.max, Int.max), hi = IVec3(Int.min, Int.min, Int.min)
        for c in rings {
            lo = IVec3(min(lo.x, c.x - r), min(lo.y, c.y - up), min(lo.z, c.z - r))
            hi = IVec3(max(hi.x, c.x + r), max(hi.y, c.y + up), max(hi.z, c.z + r))
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
        // Nearest pairs first within the near reach; then a gun still without one takes the nearest free station within
        // the last look's reach (the mast-top gun's computer down in the hull).
        var gunDone = Set<Int>(), seatDone = Set<Int>()
        for (rr, uu) in [(rNear, upNear), (r, up)] {
            var pairs: [(Float, Int, Int)] = []
            for (ti, c) in rings.enumerated() where !gunDone.contains(ti) {
                for (si, st) in stations.enumerated() where !seatDone.contains(si) {
                    let d = st.0 - c
                    guard abs(d.x) <= rr, abs(d.z) <= rr, abs(d.y) <= uu else { continue }
                    pairs.append((simd_length(V3(Float(d.x), Float(d.y), Float(d.z))), ti, si))
                }
            }
            pairs.sort { $0.0 < $1.0 }
            for (_, ti, si) in pairs where !gunDone.contains(ti) && !seatDone.contains(si) {
                gunDone.insert(ti); seatDone.insert(si)
                stationCache[turrets[ti].id] = .some((stations[si].0, stations[si].1))
            }
        }
    }
}
