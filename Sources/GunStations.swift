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
    // roof, with the console's cell beside it on the floor (backed by a wall where one is near). Returns how many.
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
        for ring in rings {
            var best: (IVec3, IVec3, String, Float)?
            for y in max(1, ring.y - 10)...min(gr.sy - 3, ring.y + 10) {
                for z in max(1, ring.z - r)...min(gr.sz - 2, ring.z + r) {
                    for x in max(1, ring.x - r)...min(gr.sx - 2, ring.x + r) {
                        guard open(x, y, z), open(x, y + 1, z), solid(x, y - 1, z) else { continue }
                        // Under a roof (inside the hull, not on a deck in the open).
                        var roof = false
                        for k in 2...6 where y + k < gr.sy { if solid(x, y + k, z) { roof = true; break } }
                        guard roof else { continue }
                        let c = IVec3(x, y, z)
                        guard !placed.contains(where: { abs($0.x - x) + abs($0.y - y) + abs($0.z - z) < 4 }) else { continue }
                        let d0 = V3(Float(x - ring.x), Float(y - ring.y), Float(z - ring.z))
                        let dist = simd_length(d0)
                        if let b = best, dist > b.3 { continue }
                        for (dx, dz, face) in dirs {
                            let k = IVec3(x + dx, y, z + dz)
                            guard open(k.x, k.y, k.z), solid(k.x, k.y - 1, k.z), open(k.x, k.y + 1, k.z) else { continue }
                            // (a hallway stays passable: the cell behind the chair is open, or the chair backs onto a wall)
                            let wall = solid(k.x + dx, k.y, k.z + dz)
                            let score = dist + (wall ? 0 : 3)
                            if best == nil || score < best!.3 { best = (c, k, face, score) }
                        }
                    }
                }
            }
            guard let (c, k, face, _) = best else { continue }
            gr.set(c.x, c.y, c.z, Blocks.id(chairKey + face))
            gr.set(k.x, k.y, k.z, console)
            placed.append(c)
        }
        return placed.count
    }
}

extension VehicleGunners {
    static var stationCache: [Int: (chair: IVec3, console: IVec3)] = [:]   // turret id -> its station in the hull

    // The gun station of turret `t` on hull `v`: the chair nearest its mount (within reach) with a console beside it.
    static func station(_ t: Ship, on v: Ship) -> (chair: IVec3, console: IVec3)? {
        let gr = v.grid
        func isChair(_ c: IVec3) -> Bool { ChairSeat.seatTop(Blocks.key(Blocks.groupBase[Int(gr.get(c.x, c.y, c.z))])) != nil }
        if let st = stationCache[t.id], isChair(st.chair), ShipParts.console[Int(gr.get(st.console.x, st.console.y, st.console.z))] { return st }
        stationCache[t.id] = nil
        let ring = IVec3(Int(floor(t.mountLocal.x)), Int(floor(t.mountLocal.y)) - 1, Int(floor(t.mountLocal.z)))
        let r = Capital.stationReach
        var best: (IVec3, IVec3)?, bd = Float.infinity
        for y in max(0, ring.y - 10)...max(0, min(gr.sy - 1, ring.y + 10)) {
            for z in max(0, ring.z - r)...max(0, min(gr.sz - 1, ring.z + r)) {
                for x in max(0, ring.x - r)...max(0, min(gr.sx - 1, ring.x + r)) {
                    let c = IVec3(x, y, z)
                    guard isChair(c) else { continue }
                    let d = simd_length(V3(Float(x - ring.x), Float(y - ring.y), Float(z - ring.z)))
                    guard d < bd else { continue }
                    for (dx, dz) in [(0, -1), (0, 1), (-1, 0), (1, 0)] where ShipParts.console[Int(gr.get(x + dx, y, z + dz))] {
                        // (a station another gun already holds is theirs)
                        let k = IVec3(x + dx, y, z + dz)
                        if stationCache.contains(where: { $0.key != t.id && $0.value.chair == c }) { continue }
                        best = (c, k); bd = d
                        break
                    }
                }
            }
        }
        guard let (c, k) = best else { return nil }
        stationCache[t.id] = (c, k)
        return (c, k)
    }
}
