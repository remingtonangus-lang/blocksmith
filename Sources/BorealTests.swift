import Foundation
import Metal
import simd

// Boreal Station checks (`Blocksmith --borealtest`, and part of every questcheck run on Linux): real stations from
// several seeds, generated through the world's own structure path, held to what the station promises a player:
//   found       a station exists within reach of spawn on every seed (the shortcut / locate search radius)
//   structcheck StructCheck's walk model finds no issue (doors, chests, mobs in blocks, floating, unsupported torches)
//   route       a walker from outside the gate reaches the uplink hall floor through the doors and down the stairwell
//   lit         every bunker floor cell a player can stand on gets block light >= 8 (a flood fill of the emitters)
//   look        the bunker is concrete (walls/floors/ceilings mostly station concrete), blue corner lamps every few
//               blocks of corridor, 12 bulkhead doors below and 3 on the surface, no snow underground or indoors,
//               snow on most of the yard
//   garrison    the structure's soldiers all stand in open cells
//   cost        generating a station chunk costs no more than a few ordinary chunks
enum BorealTests {
    static func run(device: MTLDevice, check: (Bool, String) -> Void) {
        let seeds: [UInt64] = (arg("--boreal-seeds") ?? "12345,777,424242").split(separator: ",").compactMap { UInt64($0) }
        let t0 = CFAbsoluteTimeGetCurrent()
        PathFinder.doors = true
        defer { PathFinder.doors = false }
        for seed in seeds {
            let world = World(seed: seed, device: device, save: nil)
            guard let sc = world.gen.structures else { check(false, "boreal \(seed): no structure cache"); continue }
            let o = Game.spawnOrigin(seed: seed)
            guard let s = sc.nearest(BorealStation.kind, x: o.0, z: o.2, maxRegions: 6) else {
                check(false, "boreal \(seed): no station within 6 regions of spawn"); continue
            }
            let cx = (s.min.x + s.max.x) / 2, cz = (s.min.z + s.max.z) / 2
            let dist = Int(simd_length(V2(Float(cx - o.0), Float(cz - o.2))))
            check(dist < 6 * 28 * CS, "boreal \(seed): station at \(cx) \(cz), \(dist) blocks from spawn (biome \(world.gen.column(cx, cz).biome))")

            // StructCheck's walk model over the real chunks.
            let tg = CFAbsoluteTimeGetCurrent()
            let r = StructCheck.check(world, s, typeName: BorealStation.kind, seed: seed)
            let genMs = (CFAbsoluteTimeGetCurrent() - tg) * 1000
            let byClass = Dictionary(grouping: r.issues, by: { $0.cls }).map { "\($0.key) \($0.value.count)" }.sorted().joined(separator: ", ")
            check(r.issues.isEmpty, "boreal \(seed): structcheck \(r.doors) doors, \(r.pois) chests, \(r.mobs) mobs, issues: \(byClass.isEmpty ? "none" : byClass)")
            for i in r.issues.prefix(8) { print("  \(i.cls) at \(i.pos.x) \(i.pos.y - YOFF) \(i.pos.z): \(i.detail)") }

            // Where the station's parts are: the surface level S is the blockhouse floor row.
            let S = BorealStation.levels(world, s)?.S ?? -1
            check(S > 0, "boreal \(seed): blockhouse floor found (S = \(S - YOFF))")
            guard S > 0 else { continue }
            let F = S - BorealStation.depth

            // Route: from outside the gate to every room (doors open, stairs walked).
            let start = IVec3(s.anchor.x, s.anchor.y, s.anchor.z)
            let seedsCells: [IVec3] = StructCheck.standNear(world, start.x, start.y, start.z, up: 2, down: 4).map { [IVec3(start.x, $0.0, start.z)] } ?? []
            let lo = IVec3(cx - 40, F - 2, cz - 40), hi = IVec3(cx + 40, S + 40, cz + 40)
            // (The walk model reads a stair as a full block, so climbing stairs counts as jumping.)
            let walk = StructCheck.walkOrder(world, seeds: seedsCells, lo: lo, hi: hi, jump: true).seen
            var hallReached = 0
            for dz in -6...6 { for dx in -6...6 where walk.contains(StructCheck.key(cx + dx, F + 1, cz + dz)) { hallReached += 1 } }
            var roomsReached: [String] = []
            let probes: [(String, Int, Int)] = [("control", 0, -22), ("archive", -21, 0), ("cells walk", 17, 0), ("armory", 18, -12),
                                                ("generator", 17, 11), ("mess", -16, 12), ("barracks", -20, -16), ("catwalk", 6, -6)]
            for (n, dx, dz) in probes {
                let y = n == "catwalk" ? F + 6 : F + 1
                if walk.contains(StructCheck.key(cx + dx, y, cz + dz)) { roomsReached.append(n) }
            }
            check(!seedsCells.isEmpty && hallReached > 100 && roomsReached.count == probes.count,
                  "boreal \(seed): walking in from the gate reaches \(hallReached) hall floor cells and \(roomsReached.count)/\(probes.count) rooms (\(roomsReached.joined(separator: ", ")))")

            // Light: flood block light from the emitters over the bunker and blockhouse (the mesher's rule: -1 per
            // cell through cells that don't block light).
            let x0 = cx - BorealStation.B - 16, z0 = cz - BorealStation.B - 16, nx = 2 * (BorealStation.B + 16) + 1
            let y0 = F - 2, ny = S + 8 - y0
            var light = [UInt8](repeating: 0, count: nx * nx * ny)
            @inline(__always) func li(_ x: Int, _ y: Int, _ z: Int) -> Int { ((y - y0) * nx + (z - z0)) * nx + (x - x0) }
            var queue: [(Int, Int, Int)] = []
            for y in y0..<(y0 + ny) { for z in z0..<(z0 + nx) { for x in x0..<(x0 + nx) {
                let e = Blocks.emit[Int(world.block(x, y, z))]
                if e > 0 { light[li(x, y, z)] = e; queue.append((x, y, z)) }
            } } }
            var head = 0
            while head < queue.count {
                let (x, y, z) = queue[head]; head += 1
                let l = light[li(x, y, z)]
                guard l > 1 else { continue }
                for (ox, oy, oz) in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
                    let qx = x + ox, qy = y + oy, qz = z + oz
                    guard qx >= x0, qx < x0 + nx, qz >= z0, qz < z0 + nx, qy >= y0, qy < y0 + ny else { continue }
                    guard !Blocks.lightOpaque[Int(world.block(qx, qy, qz))], light[li(qx, qy, qz)] < l - 1 else { continue }
                    light[li(qx, qy, qz)] = l - 1
                    queue.append((qx, qy, qz))
                }
            }
            var standCells = 0, dim: [IVec3] = []
            var minLight = 15
            for dz in -23...23 { for dx in -23...23 {
                let x = cx + dx, z = cz + dz
                guard BorealStation.open(dx, 1, dz) != 0, !Blocks.collide[Int(world.block(x, F + 1, z))] else { continue }
                standCells += 1
                let l = Int(light[li(x, F + 1, z)])
                minLight = min(minLight, l)
                if l < 8 { dim.append(IVec3(x, F + 1 - YOFF, z)); if dim.count <= 20 { print("  dim cell \(dx) \(dz) (from the centre): light \(l)") } }
            } }
            // The stairwell and the blockhouse: every cell a player can stand in (open, on something solid).
            var stairCells = 0, stairDim = 0, stairMin = 15
            for dz in 15...22 { for dx in -7...6 { for y in (F + 1)...(S + 1) {
                let x = cx + dx, z = cz + dz
                guard !Blocks.collide[Int(world.block(x, y, z))], !Blocks.collide[Int(world.block(x, y + 1, z))],
                      Blocks.collide[Int(world.block(x, y - 1, z))] else { continue }
                stairCells += 1
                let l = Int(light[li(x, y, z)])
                stairMin = min(stairMin, l)
                if l < 8 { stairDim += 1; if stairDim <= 12 { print("  dim stair cell \(dx) \(y - F) \(dz) (from the centre, rows above the bunker floor): light \(l)") } }
            } } }
            check(stairCells > 60 && stairDim == 0, "boreal \(seed): stairwell and blockhouse: \(stairCells) standing cells, darkest block light \(stairMin) (>= 8)")
            // Landings clear at head height (a light panel once hung in the east landing's walkway).
            var blocked = 0
            for dz in 16...21 {
                for (dx, y) in [(-6, F + 1), (-5, F + 1), (4, F + 9), (5, F + 9), (-6, S + 1), (-5, S + 1)] {
                    for yy in y...(y + 1) where Blocks.collide[Int(world.block(cx + dx, yy, cz + dz))] { blocked += 1 }
                }
            }
            check(blocked == 0, "boreal \(seed): stair landings clear to head height (\(blocked) blocked cells)")
            check(standCells > 900 && dim.isEmpty, "boreal \(seed): \(standCells) bunker floor cells, darkest block light \(minLight) (>= 8), \(dim.count) dim" + (dim.isEmpty ? "" : " e.g. \(dim.prefix(4).map { "\($0.x) \($0.y) \($0.z)" })"))

            // Look.
            var surf = 0, concrete = 0, lamps = 0, doorsLow = 0, snowInside = 0
            let concreteKeys: Set<String> = ["bunker_concrete", "bunker_concrete_dark", "bunker_floor", "bunker_concrete_stairs", "bunker_concrete_slab"]
            for dz in -24...24 { for dx in -24...24 {
                let x = cx + dx, z = cz + dz
                for ly in -1...11 {
                    let y = F + ly
                    let b = world.block(x, y, z)
                    let k = Blocks.key(Blocks.groupBase[Int(b)])
                    if k == "corner_lamp" { lamps += 1 }
                    if k == "bulkhead_door" && (Int(b - Blocks.groupBase[Int(b)]) & 8) == 0 { doorsLow += 1 }
                    if k == "snow" || k == "snow_block" { snowInside += 1 }
                    // A wall, floor or ceiling cell: solid with an open room cell beside, above or below it.
                    guard BorealStation.open(dx, ly, dz) == 0, Blocks.opaque[Int(b)] else { continue }
                    let faces = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
                    if faces.contains(where: { BorealStation.open(dx + $0.0, ly + $0.1, dz + $0.2) != 0 }) {
                        surf += 1
                        if concreteKeys.contains(k) { concrete += 1 }
                    }
                }
            } }
            let ratio = surf > 0 ? Float(concrete) / Float(surf) : 0
            check(ratio > 0.8, String(format: "boreal %llu: %.0f%% of %d bunker wall/floor/ceiling faces are station concrete", seed, ratio * 100, surf))
            check(lamps >= 250, "boreal \(seed): \(lamps) blue corner lamps in the bunker")
            check(doorsLow == 12, "boreal \(seed): \(doorsLow) bulkhead doors in the bunker (12 expected)")
            check(snowInside == 0, "boreal \(seed): no snow in the bunker (\(snowInside))")
            var surfDoors = 0, roofSnow = 0, roofs = 0, yardTops = 0, yardSnow = 0
            for dz in -30...30 { for dx in -30...30 {
                let x = cx + dx, z = cz + dz
                for y in (S + 1)...(S + 3) {
                    let b = world.block(x, y, z)
                    if Blocks.key(Blocks.groupBase[Int(b)]) == "bulkhead_door" && (Int(b - Blocks.groupBase[Int(b)]) & 8) == 0 { surfDoors += 1 }
                }
                var y = S + 30
                while y > S - 2 && world.block(x, y, z) == AIR { y -= 1 }
                let top = Blocks.key(world.block(x, y, z))
                if y > S + 1 { roofs += 1; if top == "snow" { roofSnow += 1 } }
                else { yardTops += 1; if top == "snow" { yardSnow += 1 } }       // a layer on top, not just snow ground
            } }
            // Drifts bank against walls on the north/west even when the wall stands in the next chunk (the
            // writer can't read across chunks; the build asks BorealStation.surfaceWall instead).
            var driftWant = 0, drifts = 0, edgeWant = 0, edgeDrifts = 0
            for dz in -30...30 { for dx in -30...30 where !BorealStation.surfaceWall(dx, dz) {
                let wn = BorealStation.surfaceWall(dx, dz - 1), ww = BorealStation.surfaceWall(dx - 1, dz)
                guard wn || ww, world.block(cx + dx, S, cz + dz) == SNOW, hashf(dx, dz, 43, 0xB0E) < 0.6 else { continue }
                var top = S + 30                                              // open to the sky (not under a platform)
                while top > S + 1 && world.block(cx + dx, top, cz + dz) == AIR { top -= 1 }
                if top > S + 2 || (top == S + 2 && Blocks.key(world.block(cx + dx, top, cz + dz)) != "snow") { continue }
                let across = (wn && mod(cz + dz, CS) == 0) || (ww && mod(cx + dx, CS) == 0)
                let d = world.block(cx + dx, S + 1, cz + dz) == SNOW
                driftWant += 1; if d { drifts += 1 }
                if across { edgeWant += 1; if d { edgeDrifts += 1 } }
            } }
            check(driftWant > 0 && drifts >= driftWant - 2 && edgeDrifts == edgeWant,
                  "boreal \(seed): \(drifts)/\(driftWant) planned wall-side drifts, \(edgeDrifts)/\(edgeWant) against a wall in the next chunk")
            check(surfDoors == 3, "boreal \(seed): \(surfDoors) bulkhead doors on the surface (blockhouse pair + gatehouse)")
            check(roofs > 0 && Float(roofSnow) / Float(max(1, roofs)) > 0.5 && Float(yardSnow) / Float(max(1, yardTops)) > 0.75,
                  "boreal \(seed): snow on \(roofSnow)/\(roofs) roof and mast tops, \(yardSnow)/\(yardTops) yard cells")
            // Nothing between the bunker and the blockhouse floor is snow (indoors stays clean).
            var indoorSnow = 0
            for dz in 15...22 { for dx in -7...6 { for y in (F + 1)...(S + 5) where Blocks.key(world.block(cx + dx, y, cz + dz)).hasPrefix("snow") { indoorSnow += 1 } } }
            check(indoorSnow == 0, "boreal \(seed): no snow in the stairwell or blockhouse (\(indoorSnow))")

            // Garrison.
            var mobs = 0, stuck = 0
            for (k, p) in world.pendingMobs {
                guard s.contains(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))) || simd_length(V2(p.x - Float(cx), p.z - Float(cz))) < 40 else { continue }
                mobs += 1
                let b = world.block(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
                let head = world.block(Int(floor(p.x)), Int(floor(p.y)) + 1, Int(floor(p.z)))
                if Blocks.fullCollide[Int(b)] || Blocks.fullCollide[Int(head)] { stuck += 1; print("  \(k) inside \(Blocks.key(b))/\(Blocks.key(head)) at \(p)") }
            }
            check(mobs >= 20 && stuck == 0, "boreal \(seed): \(mobs) garrison mobs, \(stuck) inside blocks")

            // Cost: the station chunks against ordinary chunks of the same world.
            let tc = CFAbsoluteTimeGetCurrent()
            for k in 0..<4 { _ = world.gen.generate(cx: floorDiv(cx, CS) + (k % 2), cz: floorDiv(cz, CS) + (k / 2)) }
            let stationMs = (CFAbsoluteTimeGetCurrent() - tc) * 1000 / 4
            let tp = CFAbsoluteTimeGetCurrent()
            for k in 0..<4 { _ = world.gen.generate(cx: floorDiv(cx, CS) + 40 + k, cz: floorDiv(cz, CS) + 40) }
            let plainMs = (CFAbsoluteTimeGetCurrent() - tp) * 1000 / 4
            check(stationMs < plainMs * 4 + 20, String(format: "boreal %llu: station chunk gen %.1f ms vs %.1f ms elsewhere (structcheck pass %.0f ms)", seed, stationMs, plainMs, genMs))
            world.unloadAll()
            world.pendingMobs.removeAll()
        }
        print(String(format: "borealtest: %.1f s", CFAbsoluteTimeGetCurrent() - t0))
    }
}
