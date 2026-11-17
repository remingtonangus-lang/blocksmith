import Foundation
import simd

// Ledger 214 (Remington, Nov 16 15:03 UTC: "on those long sea bridges you get hunted by subs and frigates and they are
// constantly blowing up the bridge as you traverse it and because of physics the bridge collapses in the water as it
// loses supports. Also, frigates and subs, make equation of one per every x sq blocks of ocean surface and when you
// destroy it no other respawns in that area").
//
// THE RULE: the sea is cut into areas of 512 by 512 blocks. An area holds one hunter (a navy submarine where the water
// is deep, else a Skyward Frigate; which comes first is the area's own). Sink it (the submarine gives up or is lost,
// the frigate is wrecked) and the area is spent for good: its key goes in ShipManager.spawnedRegions ("sea:cx,cz"),
// which the save keeps. A hunter left behind is not spent: the area sends another next time.
//
// ON A SEA BRIDGE: riding a train over a trestle with water under it, the area's hunter comes at once (no wait, no
// dice) ahead of the train, keeps pace, and every few seconds puts a torpedo or a shell into a pier ahead of the
// locomotive.
//
// THE COLLAPSE: twice a second the trestle round the train is weighed. A leg stands while it is timber all the way
// down to the bed; a deck cell stands while a standing leg is within 3 cells along the track. What no longer stands
// (deck, rail, the leg stumps hanging under it) falls through Structure.drop, so it topples into the water like
// anything else that loses its footing. The rail cells that fell are remembered ("gap:x,y,z", saved the same way):
// a train stops short of a gap (Trains.place) instead of running out over the air.
//
// BS_NOBRIDGEHUNT=1: none of this (the before: no hunters come for a train, a trestle stands on nothing).
enum BridgeHunt {
    static var on = Env.all["BS_NOBRIDGEHUNT"] != "1"
    static let area = 512
    static let reach = 2                         // cells along the track a pier carries the deck (a pier: a standing leg in the
                                                 // cell's own 3 by 3, so a leg holds the deck 3 cells either way)
    static let fireEvery: Float = 5
    static var owner: ObjectIdentifier?
    static var hunter: [String: Int] = [:]       // area key -> its hunter's ship id
    static var gaps = Set<IVec3>()               // rail cells that fell
    static var fireCD: [Int: Float] = [:]
    static var acc: Float = 0
    static weak var last: Trains.Train?
    static var lastAt: Double = -1e9
    static var onBridge = false                  // he rides a train over a sea trestle now (EnemySubs: she stays on him)
    static var spawned = 0, sunk = 0, shots = 0, fell = 0      // counters (checks)
    static var notes: [String] = []              // (checks: the first rail cells weigh() dropped and why)
    // Ledger 214 (Fable, Nov 16): only a trestle with evidence of damage is weighed. A trestle log or plank broken by a
    // blast or by his hand is a hurt cell; weigh() judges the track cells within `hurtReach` of one and forgets it after
    // two passes over it in which nothing near it fell. No hurt cell: nothing is weighed (an untouched bridge can't fall).
    static var hurt: [IVec3: Int] = [:]          // cell -> quiet passes over it
    static let hurtReach = 8
    static var oldLegRule = Env.all["BS_OLDLEGRULE"] == "1"   // (before: a leg stood only on a block that collides)
    static var anySpan = Env.all["BS_ANYSPAN"] == "1"      // (before: any unheld cell near a hurt one falls, damaged span or not)
    static let deckGroup = Blocks.groupBase[Int(Blocks.id("spruce_planks"))]
    static let legGroup = Blocks.groupBase[Int(Blocks.id("spruce_log"))]
    @inline(__always) static func broke(_ b: BlockID, _ x: Int, _ y: Int, _ z: Int) {
        guard on, b != AIR else { return }
        let gb = Blocks.groupBase[Int(b)]
        guard gb == deckGroup || gb == legGroup else { return }
        if hurt.count >= 4096 { hurt.removeAll() }
        hurt[IVec3(x, y, z)] = 0
    }

    static func key(_ x: Int, _ z: Int) -> String { "sea:\(floorDiv(x, area)),\(floorDiv(z, area))" }
    static func gapKey(_ c: IVec3) -> String { "gap:\(c.x),\(c.y),\(c.z)" }

    static func reset(_ ships: ShipManager) {
        owner = ObjectIdentifier(ships)
        hunter = [:]; fireCD = [:]; gaps = []; hurt = [:]; acc = 0; last = nil; lastAt = -1e9; onBridge = false
        for k in ships.spawnedRegions where k.hasPrefix("gap:") {
            let p = k.dropFirst(4).split(separator: ",").compactMap { Int($0) }
            if p.count == 3 { gaps.insert(IVec3(p[0], p[1], p[2])) }
        }
    }

    static func hunts(_ s: Ship) -> Bool { EnemySub.hunting(s) || (s.role == "frigate" && s.parent == nil && !s.wrecked) }

    // The area's key when it may send a hunter: not spent, and none of its own alive (one found living in it is its own).
    static func free(_ ships: ShipManager, _ x: Int, _ z: Int) -> String? {
        guard on else { return "" }
        if owner != ObjectIdentifier(ships) { reset(ships) }
        let k = key(x, z)
        if ships.spawnedRegions.contains(k) { return nil }
        if let id = hunter[k], ships.list.contains(where: { $0.id == id && hunts($0) }) { return nil }
        for s in ships.list where hunts(s) && key(Int(floor(s.pos.x)), Int(floor(s.pos.z))) == k && !hunter.values.contains(s.id) {
            hunter[k] = s.id
            return nil
        }
        return k
    }
    static func claim(_ s: Ship, _ k: String) { if on, !k.isEmpty { hunter[k] = s.id; spawned += 1 } }
    // She dived off, left behind: the area may send another.
    static func left(_ s: Ship) { for (k, id) in hunter where id == s.id { hunter[k] = nil } }

    // A train stops short of a rail cell that fell (while it is still gone).
    static func gap(_ g: Game, _ c: IVec3) -> Bool {
        guard on, !gaps.isEmpty, gaps.contains(c) else { return false }
        return !Rails.isRail(g.world.block(c.x, c.y, c.z))
    }

    @inline(__always) static func isLeg(_ b: BlockID, _ leg: BlockID) -> Bool { b != AIR && Blocks.groupBase[Int(b)] == leg }

    // A trestle leg under (x, y, z): 0 none, 1 standing (timber down to the bed, or the full 47 a land trestle's leg
    // is given), 2 cut (it ends over air or water).
    static func legState(_ w: World, _ x: Int, _ y: Int, _ z: Int, _ leg: BlockID) -> Int {
        guard isLeg(w.block(x, y, z), leg) else { return 0 }
        var yy = y - 1, n = 1
        while yy > 1 {
            let b = w.block(x, yy, z)
            if isLeg(b, leg) { yy -= 1; n += 1; continue }
            // (it stands on anything but air or a liquid: grass, snow, a slab, leaves carry it as the ground under them does)
            if oldLegRule { return Blocks.collide[Int(b)] || n >= 47 ? 1 : 2 }
            if (b != AIR && !Blocks.isLiquid(b)) || n >= 47 { return 1 }
            // (a sea pier: the writer ran it down to the bed as it saw the bed, and the field draws the bed's top cell as
            // water (an open-country trestle's 32-long legs at seed 1000 end over it). The bed within 3 cells
            // under it, through water only, carries it; a leg cut by a blast has air or its own lower stump there.)
            guard Blocks.isLiquid(b) else { return 2 }
            for d in 1...3 {
                let u = w.block(x, yy - d, z)
                if Blocks.isLiquid(u) { continue }
                return u != AIR && !isLeg(u, leg) ? 1 : 2
            }
            return 2
        }
        return 1
    }

    // The water's top under a trestle cell (looked for just off the deck's edge), or nil over land.
    static func water(_ w: World, _ c: IVec3) -> Int? {
        for (dx, dz) in [(3, 0), (-3, 0), (0, 3), (0, -3)] {
            var y = c.y - 2
            while y > max(1, c.y - 60) {
                let b = w.block(c.x + dx, y, c.z + dz)
                if Blocks.fluidKind[Int(b)] == 1 { return y }
                if Blocks.collide[Int(b)] { break }
                y -= 1
            }
        }
        return nil
    }

    // The train he rides (a car's seat, or a coach's hull under his feet).
    static func train(_ g: Game) -> Trains.Train? {
        let on = g.world.ships.aboardOrPilot
        guard g.riding != nil || on != nil else { return nil }
        for tr in Trains.trains.values {
            for m in tr.cars where m === g.riding || (on != nil && TrainHulls.hull(m) === on) { return tr }
        }
        return nil
    }

    // Weighs the trestle round a point of the track and drops what no longer stands. Returns the cells that fell.
    @discardableResult
    static func weigh(_ g: Game, _ t: Trains.Track, at s0: Float, back: Int = 70, fwd: Int = 90, limit: Int = 24) -> Int {
        guard !hurt.isEmpty else { return 0 }
        let w = g.world
        let deck = deckGroup, leg = legGroup
        let n = back + fwd + 1
        // 0 nothing there (a hole), 1 deck over a standing leg, 2 deck or stump with no standing leg, 3 on the ground
        // (a bank, a tunnel floor, ground not loaded): 1 and 3 carry their neighbours.
        var cells = [IVec3](), state = [UInt8](repeating: 3, count: n)
        var cutLeg = [Bool](repeating: false, count: n)
        cells.reserveCapacity(n)
        let total = t.cells.count, i0 = Int(s0.rounded())
        for k in 0..<n {
            // (past a track's own end nothing is weighed: the end carries)
            let i = i0 + k - back
            let c = t.cyclic ? t.cells[((i % total) + total) % total] : t.cells[max(0, min(total - 1, i))]
            cells.append(c)
            guard t.cyclic || (i >= 0 && i < total), w.chunkAt(c.x, c.z) != nil else { continue }
            var planks = false, stands = false, any = false
            for dz in -1...1 { for dx in -1...1 {
                if !planks, Blocks.groupBase[Int(w.block(c.x + dx, c.y - 1, c.z + dz))] == deck { planks = true }
                let st = legState(w, c.x + dx, c.y - 2, c.z + dz, leg)
                if st == 1 { stands = true }
                if st != 0 { any = true }
            } }
            if stands { state[k] = planks ? 1 : 0 }
            else if any { state[k] = 2; cutLeg[k] = true }
            else if planks { state[k] = Blocks.collide[Int(w.block(c.x, c.y - 2, c.z))] ? 3 : 2 }
            else { state[k] = Blocks.collide[Int(w.block(c.x, c.y - 1, c.z))] ? 3 : 0 }
        }
        // (the hurt cells this window passes over, and the track cells near one: only those are judged)
        func near(_ c: IVec3, _ h: IVec3) -> Bool { abs(c.x - h.x) <= hurtReach && abs(c.z - h.z) <= hurtReach && h.y <= c.y + 2 && h.y >= c.y - 140 }
        var inWindow: [IVec3] = []
        for h in hurt.keys where cells.contains(where: { near($0, h) }) { inWindow.append(h) }
        guard !inWindow.isEmpty else { return 0 }
        var judged = [Bool](repeating: false, count: n)
        for k in 0..<n where state[k] == 2 { judged[k] = inWindow.contains { near(cells[k], $0) } }
        // Fable (Nov 16): a cell no pier holds falls only when its own span is damaged: a cut leg or a hurt cell lies
        // between it and the nearest standing pier on one side at least. (A trestle drawn before the diagonal lines'
        // legs, centre piers 8 apart, keeps the untouched spans beside one that was hit.)
        var damaged = [Bool](repeating: false, count: n)
        for k in 0..<n where state[k] != 1 && state[k] != 3 {
            let c = cells[k]
            damaged[k] = cutLeg[k] || inWindow.contains { abs($0.x - c.x) <= 1 && abs($0.z - c.z) <= 1 && $0.y <= c.y + 2 && $0.y >= c.y - 140 }
        }
        func spanDamaged(_ k: Int, _ step: Int) -> Bool {
            var j = k
            while j >= 0 && j < n && state[j] != 1 && state[j] != 3 { if damaged[j] { return true }; j += step }
            return false
        }
        var out = [IVec3](), seen = Set<IVec3>(), rails = 0
        for k in reach..<(n - reach) where state[k] == 2 && judged[k] {
            var held = false
            for j in (k - reach)...(k + reach) where state[j] == 1 || state[j] == 3 { held = true; break }
            if held { continue }
            if !BridgeHunt.anySpan && !spanDamaged(k, -1) && !spanDamaged(k, 1) { continue }
            let c = cells[k]
            if notes.count < 6 {
                let win = (max(0, k - 4)...min(n - 1, k + 4)).map { String(state[$0]) }.joined()
                var col: [String] = []
                for dz in -1...1 { for dx in -1...1 {
                    var y = c.y - 2, d = 0
                    while y > 1, isLeg(w.block(c.x + dx, y, c.z + dz), leg) { y -= 1; d += 1 }
                    if d > 0 { col.append("\(dx),\(dz): \(d) legs on " + (0...4).map { Blocks.key(w.block(c.x + dx, y - $0, c.z + dz)) }.joined(separator: ",")) }
                } }
                notes.append("\(c.x) \(c.y) \(c.z) states \(win) under \(Blocks.key(w.block(c.x, c.y - 1, c.z)))/\(Blocks.key(w.block(c.x, c.y - 2, c.z))) water \(water(w, c).map { String($0) } ?? "none") legs [\(col.joined(separator: "; "))]")
            }
            if Rails.isRail(w.block(c.x, c.y, c.z)) {
                w.setBlock(c.x, c.y, c.z, AIR)
                if gaps.insert(c).inserted { w.ships.spawnedRegions.insert(gapKey(c)) }
            }
            for dz in -1...1 { for dx in -1...1 {
                let x = c.x + dx, z = c.z + dz
                if Blocks.groupBase[Int(w.block(x, c.y - 1, z))] == deck, seen.insert(IVec3(x, c.y - 1, z)).inserted { out.append(IVec3(x, c.y - 1, z)) }
                var y = c.y - 2
                while y > 1, isLeg(w.block(x, y, z), leg), legState(w, x, y, z, leg) == 2 {
                    if seen.insert(IVec3(x, y, z)).inserted { out.append(IVec3(x, y, z)) }
                    y -= 1
                }
            } }
            rails += 1
            if rails >= limit { break }
        }
        if !out.isEmpty {
            for c in out { broke(w.block(c.x, c.y, c.z), c.x, c.y, c.z) }       // (what falls hurts its neighbours: the fall runs on)
            Structure.drop(g, out); fell += out.count
        }
        // (a hurt cell nothing near fell from on two passes is forgotten)
        for h in inWindow {
            if out.contains(where: { abs($0.x - h.x) <= hurtReach && abs($0.z - h.z) <= hurtReach }) { hurt[h] = 0; continue }
            let q = (hurt[h] ?? 0) + 1
            hurt[h] = q >= 2 ? nil : q
        }
        return out.count
    }

    // The first pier with a standing leg ahead of the train: where its leg meets the water.
    static func pier(_ g: Game, _ t: Trains.Track, _ s0: Float, _ dir: Float) -> V3? {
        let w = g.world
        let leg = Blocks.groupBase[Int(Blocks.id("spruce_log"))]
        for k in stride(from: 14, through: 60, by: 1) {
            let c = t.cell(t.advance(s0, by: dir * Float(k)))
            guard w.chunkAt(c.x, c.z) != nil else { continue }
            for dz in -1...1 { for dx in -1...1 where legState(w, c.x + dx, c.y - 2, c.z + dz, leg) == 1 {
                guard let top = water(w, c) else { continue }
                return V3(Float(c.x + dx) + 0.5, Float(top), Float(c.z + dz) + 0.5)
            } }
        }
        return nil
    }
}

extension Game {
    // Every tick (submarinesTick).
    func bridgeHuntTick(_ dt: Float) {
        guard BridgeHunt.on, dim.dim == .overworld else { return }
        let ships = world.ships
        if BridgeHunt.owner != ObjectIdentifier(ships) { BridgeHunt.reset(ships) }
        BridgeHunt.acc += dt
        guard BridgeHunt.acc >= 0.5 else { return }
        let step = BridgeHunt.acc
        BridgeHunt.acc = 0
        // Hunters sunk: their areas are spent for good.
        for (k, id) in BridgeHunt.hunter {
            let s = ships.list.first { $0.id == id }
            if let s = s, BridgeHunt.hunts(s) { continue }
            ships.spawnedRegions.insert(k)
            BridgeHunt.hunter[k] = nil
            BridgeHunt.fireCD[id] = nil
            BridgeHunt.sunk += 1
        }
        var tr = BridgeHunt.train(self)
        let riding = tr != nil
        if let t = tr { BridgeHunt.last = t; BridgeHunt.lastAt = clock } else if clock - BridgeHunt.lastAt < 60 { tr = BridgeHunt.last }
        BridgeHunt.onBridge = false
        guard let tr = tr, tr.cars.first != nil else { return }
        let t = tr.track
        let (s0, dir, _) = Trains.now(tr)
        let sHead = tr.layout.isEmpty ? s0 : tr.lastS
        BridgeHunt.weigh(self, t, at: sHead)
        guard riding, survival, difficulty > 0, alive, !Reckoning.won else { return }
        let c = t.cell(sHead)
        let deck = Blocks.groupBase[Int(Blocks.id("spruce_planks"))]
        guard world.chunkAt(c.x, c.z) != nil, Blocks.groupBase[Int(world.block(c.x, c.y - 1, c.z))] == deck,
              let top = BridgeHunt.water(world, c) else { return }
        BridgeHunt.onBridge = true
        let here = t.point(sHead)
        let aheadS = t.advance(sHead, by: dir * 80)
        let ahead = t.point(aheadS)
        var along = V3(ahead.x - here.x, 0, ahead.z - here.z)
        along = simd_length(along) > 1 ? simd_normalize(along) : V3(1, 0, 0)
        let side = V3(-along.z, 0, along.x)
        // The area's hunter comes.
        let px = Int(floor(player.pos.x)), pz = Int(floor(player.pos.z))
        if let k = BridgeHunt.free(ships, px, pz), !k.isEmpty {
            let cx = floorDiv(px, BridgeHunt.area), cz = floorDiv(pz, BridgeHunt.area)
            var s: Ship?
            let subFirst = (cx &* 31 &+ cz &* 17) & 1 == 0
            for pass in 0..<2 where s == nil {
                if (pass == 0) == subFirst {
                    for off: Float in [45, -45, 60, -60, 30, -30] where s == nil {
                        s = spawnEnemySub(at: ahead + side * off, facing: here)
                    }
                } else {
                    let at = ahead + side * 55
                    let home = IVec3(Int(floor(at.x)), top + 18, Int(floor(at.z)))
                    s = ships.spawnVessel("frigate", home: home, game: self)
                }
            }
            if let s = s {
                BridgeHunt.claim(s, k)
                BridgeHunt.fireCD[s.id] = 4
                if s.role != "frigate" { onToast?("Sonar contact: a navy submarine is hunting you") }
                sfx(.sonarPing, 1.3, at: player.pos)
            }
        }
        // Each hunter near keeps pace and shoots the piers ahead of the locomotive.
        let target = BridgeHunt.pier(self, t, sHead, dir)
        for (k, id) in BridgeHunt.hunter {
            guard let s = ships.list.first(where: { $0.id == id }), BridgeHunt.hunts(s) else { continue }
            if s.role == "frigate" {
                // (she keeps to her own area: its edge is where she turns back)
                let want = here + along * 40 + side * 30
                let p = k.dropFirst(4).split(separator: ",").compactMap { Int($0) }
                if p.count == 2, let h = s.home {
                    let lo = V2(Float(p[0] * BridgeHunt.area), Float(p[1] * BridgeHunt.area)), hi = lo + V2(Float(BridgeHunt.area), Float(BridgeHunt.area))
                    s.home = V3(max(lo.x, min(hi.x, want.x)), h.y, max(lo.y, min(hi.y, want.z)))
                }
            }
            var cd = (BridgeHunt.fireCD[id] ?? BridgeHunt.fireEvery) - step
            defer { BridgeHunt.fireCD[id] = cd }
            guard cd <= 0, let aim = target else { continue }
            if s.role == "frigate" {
                let from = s.pos + V3(0, -3, 0)
                let d = aim + V3(0, 1, 0) - from
                let dist = simd_length(d)
                guard dist < 150 else { continue }
                let time = max(0.6, dist / 50)
                let sh = Shell(pos: from, vel: d / time + V3(0, 10 * time, 0), owner: s.id, power: 3)
                sh.life = time + 2
                ships.shells.append(sh)
                sfx(.shipCannon, 1.2, at: from)
            } else {
                guard s.submerged > 1 else { continue }
                let bow = s.toWorld(V3(0, 1.5, -5.5))
                let d = aim + V3(0, -1, 0) - bow
                let dist = simd_length(d)
                let f = s.dirToWorld(s.fwd)
                guard dist < 110, dist > 4, simd_dot(simd_normalize(V3(f.x, 0, f.z) + V3(1e-5, 0, 0)), simd_normalize(V3(d.x, 0, d.z) + V3(1e-5, 0, 0))) > 0.3 else { continue }
                let sh = Shell(pos: bow, vel: d / dist * Submarine.torpedoSpeed, owner: s.id, power: 3)
                sh.kind = 4; sh.gravity = 0; sh.life = dist / Submarine.torpedoSpeed + 1.5
                ships.shells.append(sh)
                EnemySub.torpedoes += 1
                sfx(.splash, 0.8, at: bow)
            }
            cd = BridgeHunt.fireEvery
            BridgeHunt.shots += 1
        }
    }
}
