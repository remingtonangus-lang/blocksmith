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
            let tileKey = Blocks.key(world.block(cx - 6, S, cz + 22))
            check(S > 0 && tileKey == "bunker_floor", "boreal \(seed): blockhouse floor where the plan puts it (S = \(S - YOFF), \(tileKey))")
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

            // Sound: the ambience director, standing in the hall and in a corridor, plays the station hum (lamps and
            // data cabinets are its emitters) and no wildlife. First seed only (a Game of its own).
            if seed == seeds.first {
                // The hum itself: rendered like `Blocksmith --sounds` checks it (non-silent, unclipped, seamless loop),
                // and quieter than a beacon's drone (a bed under everything, not a feature).
                let hum = SoundBank.render(.stationHumLoop, variant: 0), hc = SoundBank.check(.stationHumLoop, hum)
                let beacon = SoundBank.check(.beaconLoop, SoundBank.render(.beaconLoop, variant: 0))
                check(hc.ok && hc.rms < beacon.rms, String(format: "boreal: station hum %.1f s, rms %.3f (beacon %.3f), peak %.2f %@",
                                                           hc.seconds, hc.rms, beacon.rms, hc.peak, hc.problems.joined(separator: ", ")))
            }
            if seed == seeds.first {
                let g = Game(world: world, save: nil, persistent: false)
                g.paused = false
                g.weather.raining = false; g.weather.rain = 0
                for (label, dx, dz) in [("hall", 0, 5), ("corridor", -12, 10)] {
                    g.player.pos = V3(Float(cx + dx) + 0.5, Float(F + 1), Float(cz + dz) + 0.5); g.player.vel = .zero
                    g.time = 0.25 * DAY_LENGTH
                    g.audio.record = [:]
                    var t: Float = 0
                    while t < 12 { g.audioAmbientTick(0.05); t += 0.05 }
                    let rec = g.audio.record ?? [:]
                    g.audio.record = nil
                    let wild = rec.keys.filter { k in ["birdCall", "owlHoot", "loop:crickets", "loop:jungle", "loop:wind"].contains { k.hasPrefix($0) } }
                    check((rec["loop:stationhum"] ?? 0) > 0 && wild.isEmpty,
                          "boreal \(seed): \(label) at noon hums (\(rec["loop:stationhum"] ?? 0) ticks), wildlife: \(wild.isEmpty ? "none" : wild.sorted().joined(separator: " "))")
                }
                // The alarm: a gunshot in the hall sets it off, the klaxon blares, the garrison turns on the
                // source, and it stands down once things have been quiet for a while.
                for (name, p) in world.pendingMobs { if let m = Mob.structureMob(name, at: p) { g.mobs.mobs.append(m) } }
                g.mobs.rebuildIndex()
                let hall = V3(Float(cx) + 0.5, Float(F + 1), Float(cz + 5) + 0.5)
                g.player.pos = hall
                g.audio.record = [:]
                g.baseNoise(at: hall, kind: .gunshot)
                for _ in 0..<10 { g.basesTick(1.0) }
                let site = g.borealAlarm.sites.values.first { abs($0.cx - cx) < 2 && abs($0.cz - cz) < 2 }
                let blares = g.audio.record?[Snd.gun(10).name] ?? 0
                let gar = g.mobs.mobs.filter { m in m.kind.steelhold && m.kind != .deckGun && (site.map { BorealStation.insideSite($0, m.pos) } ?? false) }
                let roused = gar.filter { $0.aggro }.count
                check(site?.on == true && blares >= 2 && gar.count >= 10 && roused == gar.count,
                      "boreal \(seed): a shot in the hall sets the alarm off (\(blares) klaxon blares in 10 s, \(roused)/\(gar.count) soldiers roused)")
                // Once soldiers have searched the spot (lastSeen cleared), a running alarm doesn't send them back.
                for m in gar { m.soldierBrain.lastSeen = nil }
                for _ in 0..<3 { g.basesTick(1.0) }
                let resent = gar.filter { $0.soldierBrain.lastSeen != nil && !$0.soldierBrain.sees }.count
                check(resent == 0, "boreal \(seed): soldiers who searched the spot stay free while the alarm runs (\(resent) sent back)")
                g.audio.record = nil
                g.player.pos = hall + V3(400, 40, 400)                          // away: nobody can see anyone
                for _ in 0..<Int(BorealAlarmState.standDown) + 5 { g.basesTick(1.0) }
                let after = g.borealAlarm.sites.values.first { abs($0.cx - cx) < 2 && abs($0.cz - cz) < 2 }
                check(after?.on == false, "boreal \(seed): the alarm stands down after \(Int(BorealAlarmState.standDown)) s of quiet (\(g.borealAlarm.log.joined(separator: "; ")))")
            }

            opsCheck(world, cx: cx, cz: cz, S: S, check: check)

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

    // The infiltration operation (BorealOps.swift), through the game's own entry points: a silent run (enter, copy
    // with an interruption, charge, extract before it blows, reward, the blast), then a loud one (the alarm locks the
    // uplink, the rating and reward drop, squads come down the stairwell, roused soldiers leave a shut room by its
    // bulkhead door), and the saved state round trip.
    static func sniperCount(_ g: Game) -> Int {
        let id = Items.id("gun_sniper")
        return g.inventory.main.countOf(id)
    }
    static func opsCheck(_ world: World, cx: Int, cz: Int, S: Int, check: (Bool, String) -> Void) {
        let F = S - BorealStation.depth
        let key = "boreal:\(cx),\(cz)"
        func at(_ dx: Float, _ y: Int, _ dz: Float) -> V3 { V3(Float(cx) + dx + 0.5, Float(y), Float(cz) + dz + 0.5) }
        let console = IVec3(cx, F + 2, cz - 24), gen = IVec3(cx + 19, F + 2, cz + 13)
        let ck = Blocks.key(Blocks.groupBase[Int(world.block(console.x, console.y, console.z))])
        let gk = Blocks.key(Blocks.groupBase[Int(world.block(gen.x, gen.y, gen.z))])
        check(ck == "command_console" && gk == "steel_plating", "boreal ops: control-room console (\(ck)) and generator (\(gk)) where the plan puts them")

        // Silent run: nobody in the station to see or hear.
        var g = Game(world: world, save: nil, persistent: false)
        g.paused = false; g.survival = true
        g.weather.raining = false; g.weather.rain = 0
        var toasts: [String] = []
        g.onToast = { toasts.append($0) }
        func secs(_ n: Int, _ body: () -> Void = {}) { for _ in 0..<n { body(); g.basesTick(1.0) } }
        g.player.pos = at(-5, S + 1, Float(BorealStation.yard + 8)); g.player.vel = .zero
        secs(2)
        check(g.stationOps[key]?.stage == 0 && g.stationOpBar() == nil, "boreal ops: outside the fence the operation waits (stage \(g.stationOps[key]?.stage ?? -1))")
        g.player.pos = at(-5, S + 1, Float(BorealStation.yard - 6))
        secs(1)
        let bar0 = g.stationOpBar()?.0 ?? "none"
        check(g.stationOps[key]?.stage == 1 && bar0.hasPrefix("Copy the uplink codes") && toasts.contains { $0.hasPrefix("Station operation") },
              "boreal ops: stepping inside starts the operation (bar \"\(bar0)\")")
        // Copy: two seconds, walk off (interrupted, progress kept), come back, finish.
        g.player.pos = at(0, F + 1, -21)
        let used = g.stationUse(console)
        secs(2)
        let part = g.stationOps[key]?.codes ?? 0
        let copyBar = g.stationOpBar()?.0 ?? "none"
        g.player.pos = at(0, F + 1, -12)
        secs(1)
        let kept = g.stationOps[key]?.codes ?? 0
        let stopped = g.stationOps[key]?.copyAt == nil
        g.player.pos = at(0, F + 1, -21)
        _ = g.stationUse(console)
        secs(Int(BorealStation.copySeconds) + 1)
        let codes = g.stationOps[key]?.codes ?? 0
        check(used && part > 0.2 && part < 0.3 && copyBar.hasPrefix("Copying uplink codes") && stopped && kept == part && codes >= 1,
              String(format: "boreal ops: the console copies (%.0f%% after 2 s, bar \"%@\"), walking off pauses it (%.0f%% kept), back at it the codes finish", part * 100, copyBar, kept * 100))
        // A desk console elsewhere in the station (the hall's screen wall) is not the uplink.
        check(!g.stationUse(IVec3(cx + 3, F + 3, cz - 8)), "boreal ops: the hall's screen wall is not an objective")
        // Charge, then out past the fence before it blows.
        g.player.pos = at(17, F + 1, 13)
        let planted = g.stationUse(gen)
        let inv0 = sniperCount(g), money0 = g.money
        secs(3)
        // A teleport (or a respawn) far off is not walking out.
        g.player.pos = at(0, S + 40, Float(BorealStation.yard + 120))
        secs(1)
        check(g.stationOps[key]?.stage == 1, "boreal ops: a teleport far from the station doesn't count as extraction (stage \(g.stationOps[key]?.stage ?? -1))")
        // Out over the fence on the station's lowest side (the ground can fall away well below the yard).
        var low = (V3(0, 0, 0), Int.max)
        for (sx, sz) in [(0, 1), (0, -1), (1, 0), (-1, 0)] {
            let d = BorealStation.yard + 6
            let x = cx + sx * d, z = cz + sz * d
            var y = S + 24
            while y > S - 60 && !Blocks.collide[Int(world.block(x, y, z))] { y -= 1 }
            if y < low.1 { low = (V3(Float(x) + 0.5, Float(y + 1), Float(z) + 0.5), y) }
        }
        g.player.pos = low.0
        secs(1)
        let op = g.stationOps[key]
        let rewarded = sniperCount(g) == inv0 + 1 && g.money == money0 + 25000
        check(planted && op?.stage == 2 && op?.silent == true && rewarded && g.advancements.contains("adventure/station_silent") && g.advancements.contains("adventure/station_op")
              && (g.stationOpBar()?.0 ?? "").hasSuffix("silent"),
              "boreal ops: charge set, out past the fence on the lowest side (ground \(low.1 - S) from the yard): complete and silent, Farsight Rifle and $250, both advancements (stage \(op?.stage ?? -1), bar \"\(g.stationOpBar()?.0 ?? "none")\")")
        var steel0 = 0, steel1 = 0
        func countGen() -> Int {
            var n = 0
            for dz in 13...19 { for dx in 18...21 { for ly in 1...4 where world.block(cx + dx, F + ly, cz + dz) != AIR { n += 1 } } }
            return n
        }
        steel0 = countGen()
        secs(Int(BorealStation.fuseSeconds))
        steel1 = countGen()
        check(g.stationOps[key]?.blown == true && steel1 < steel0 && g.stationOps[key]?.fuse == nil,
              "boreal ops: the charge blows the generator after \(Int(BorealStation.fuseSeconds)) s (\(steel0) -> \(steel1) machine blocks)")
        // Saved and loaded: a finished station stays finished.
        let saved = g.saveExtra()
        g = Game(world: world, save: nil, persistent: false)
        g.loadExtra(saved)
        check(g.stationOps[key]?.stage == 2 && g.stationOps[key]?.silent == true, "boreal ops: the finished operation survives a save and load (\(saved["stationOps"]?.count ?? 0) bytes)")
        g.onToast = { toasts.append($0) }
        g.player.pos = at(0, F + 1, -21)
        check(g.stationUse(console) && sniperCount(g) == 0, "boreal ops: a finished station pays only once")

        // Loud run: a fresh operation with the garrison in place.
        g = Game(world: world, save: nil, persistent: false)
        g.paused = false; g.survival = false                       // the soldiers can't target the observer
        g.weather.raining = false; g.weather.rain = 0
        g.onToast = { toasts.append($0) }
        for (name, p) in world.pendingMobs { if let m = Mob.structureMob(name, at: p) { g.mobs.mobs.append(m) } }
        g.mobs.rebuildIndex()
        let hall = at(0, F + 1, 5)
        g.player.pos = hall
        secs(1)
        g.player.pos = at(0, F + 1, -21)
        _ = g.stationUse(console)
        secs(2)
        let before = g.stationOps[key]?.codes ?? 0
        g.baseNoise(at: hall, kind: .gunshot)
        secs(2)
        let lockedA = g.stationOps[key]?.codes ?? 0
        g.stationOps[key]?.copyAt = nil
        toasts.removeAll()
        _ = g.stationUse(console)
        secs(1)
        let lockedBar = g.stationOpBar()?.0 ?? "none"
        check(g.borealAlarm.sites[key]?.on == true && g.stationOps[key]?.loud == true && lockedA == before && g.stationOps[key]?.copyAt == nil
              && toasts.contains { $0.hasPrefix("Uplink locked") } && lockedBar.hasSuffix("ALARM"),
              String(format: "boreal ops: the alarm locks the uplink (copy held at %.0f%%, bar \"%@\")", before * 100, lockedBar))
        // Squads come down the stairwell while the player is inside (three at most).
        let n0 = g.mobs.mobs.count
        secs(Int(BorealStation.waveEvery) + 1) { g.baseNoise(at: hall, kind: .gunshot) }
        let squad = g.mobs.mobs.suffix(from: n0).filter { $0.kind.steelhold && simd_length($0.pos - g.stationOps[key]!.stairFoot) < 4 }
        check(g.stationOps[key]?.waves == 1 && squad.count == 3 && squad.allSatisfy { $0.stationDoors && $0.aggro },
              "boreal ops: a squad of \(squad.count) comes down the stairwell \(Int(BorealStation.waveEvery)) s into the alarm (\(g.stationOps[key]?.waves ?? 0) waves)")
        secs(Int(BorealStation.waveEvery) * 4) { g.baseNoise(at: hall, kind: .gunshot) }
        check(g.stationOps[key]?.waves == BorealStation.maxWaves, "boreal ops: squads stop at \(BorealStation.maxWaves) (\(g.stationOps[key]?.waves ?? 0))")

        // Loud extraction: both jobs, then out; the smaller reward and no silent challenge. The generator is
        // already wrecked from the silent run (same world): that counts as the sabotage, no charge needed.
        g.stationOps[key]?.codes = 1
        secs(1)
        check(g.stationOps[key]?.planted == true && g.stationOps[key]?.blown == true, "boreal ops: a generator already wrecked counts as sabotaged (\(g.stationGeneratorLeft(g.stationOps[key]!)) machine blocks left)")
        let money1 = g.money
        g.player.pos = at(-5, S + 1, Float(BorealStation.yard + 8))
        secs(1)
        check(g.stationOps[key]?.stage == 2 && g.stationOps[key]?.silent == false && g.money == money1 + 10000
              && g.advancements.contains("adventure/station_op") && !g.advancements.contains("adventure/station_silent"),
              "boreal ops: a loud extraction pays $100 and no silent challenge (\(g.borealAlarm.log.filter { $0.hasPrefix(key) }.suffix(6).joined(separator: "; ")))")
        g.mobs.mobs.removeAll()

        // A roused soldier shut in the archive gets out through its bulkhead door (the game's own AI, 40 s).
        let g2 = Game(world: world, save: nil, persistent: false)
        g2.paused = false; g2.survival = true                        // soldiers only hunt a player they can hurt
        for (name, p) in world.pendingMobs { if let m = Mob.structureMob(name, at: p) { g2.mobs.mobs.append(m) } }
        g2.mobs.rebuildIndex()
        let archive = g2.mobs.mobs.filter { $0.kind.steelhold && $0.kind != .deckGun && $0.pos.x < Float(cx - 16) && abs($0.pos.z - Float(cz)) < 7 }
        let door = IVec3(cx - 15, F + 1, cz)
        let shut = Int(world.block(door.x, door.y, door.z) - Blocks.groupBase[Int(world.block(door.x, door.y, door.z))]) & 4 == 0
        var out = false, t: Float = 0
        g2.player.pos = hall
        g2.baseNoise(at: hall, kind: .gunshot)
        while t < 40 && !out {
            g2.tick(0.05); g2.player.pos = hall; g2.player.vel = .zero; g2.health = 20; g2.menu = nil; t += 0.05
            out = archive.contains { $0.pos.x > Float(cx - 14) }
        }
        // The alarm stands down once things are quiet (player gone): the soldiers keep to their rooms again.
        let doorsDuring = archive.allSatisfy { $0.stationDoors }
        g2.survival = false                                          // gone: nobody can be seen or fought
        var quiet: Float = 0
        while quiet < BorealAlarmState.standDown + 15 && g2.borealAlarm.sites[key]?.on != false {
            g2.tick(0.05); g2.player.pos = hall + V3(0, 0, Float(BorealStation.yard + 40)); g2.player.vel = .zero; g2.player.flying = true; g2.health = 20; g2.menu = nil
            quiet += 0.05
        }
        g2.basesTick(1.0)
        check(g2.borealAlarm.sites[key]?.on == false && !g2.mobs.mobs.contains { $0.stationDoors },
              "boreal ops: after the alarm stands down no soldier works the doors (\(g2.mobs.mobs.filter { $0.stationDoors }.count), alarm \(g2.borealAlarm.sites[key]?.on ?? false), \(g2.borealAlarm.log.suffix(4).joined(separator: "; ")))")
        if !out { for m in archive { print("  archive soldier at \(m.pos.x - Float(cx)) \(m.pos.y - Float(F)) \(m.pos.z - Float(cz)), aggro \(m.aggro), doors \(m.stationDoors), gave up \(m.gaveUp(hall)), lastSeen \(String(describing: m.soldierBrain.lastSeen)), path \(m.path.nodes.count) partial \(m.path.partial) door \(String(describing: m.path.door))") } }
        check(!archive.isEmpty && shut && out && doorsDuring,
              String(format: "boreal ops: a roused soldier leaves the shut archive through its bulkhead door (%d there, out after %.1f s)", archive.count, t))
        g2.mobs.mobs.removeAll()
    }
}
