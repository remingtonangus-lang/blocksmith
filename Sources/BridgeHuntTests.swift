import Foundation
import simd

// Ledger 214 checks (`questcheck --bridgehunt-only`, and part of every questcheck run), on a trestle built over a
// walled pool high over the ground (64 cells of rail on a 3-wide plank deck, edge legs every 4 cells, a centre pier
// every 8, as Railways.draw builds a sea bridge):
//   stands    untouched, nothing falls
//   collapse  one row of legs cut: the deck over it falls and the rail cell is a remembered gap; the next row cut too:
//             the whole span between the standing legs falls; a train's blocked-line check sees the gap
//   area      an area with a living hunter sends no other; the hunter wrecked, the area is spent for good
//   hunt      riding a train over the bridge in survival a hunter comes, shoots a pier ahead, and deck falls
enum BridgeHuntTests {
    static func run(game g: Game, check: (Bool, String) -> Void) {
        let scope = SuiteScope(g); defer { scope.putBack(g) }   // (job 6: what the group adds goes, what it takes comes back)
        guard BridgeHunt.on else { return }
        defer { BridgeHunt.on = true }
        let w = g.world, ships = w.ships
        let pos0 = g.player.pos, surv0 = g.survival, fly0 = g.player.flying, enc0 = ships.encounters, toast0 = g.onToast
        let regions0 = ships.spawnedRegions, ships0 = Set(ships.list.map { ObjectIdentifier($0) }), mobs0 = Set(g.mobs.mobs.map { ObjectIdentifier($0) }), riding0 = g.riding, health0 = g.health
        var placed: [IVec3] = []
        let trackId: Int64 = -20900
        defer {
            Trains.trains[trackId] = nil
            g.riding = riding0
            // (every ship and mob the scenes brought, by identity: the list's order shifts as ships are let go, and a
            // hunter left behind with its marines shot at the suite's later walks, run 1 on build 22)
            while let s = ships.list.first(where: { !ships0.contains(ObjectIdentifier($0)) }) { ships.remove(s) }
            g.mobs.mobs.removeAll { !mobs0.contains(ObjectIdentifier($0)) }
            ships.shells.removeAll()
            g.falling.removeAll()
            for q in placed { w.setBlock(q.x, q.y, q.z, AIR) }
            ships.spawnedRegions = regions0
            BridgeHunt.reset(ships)
            g.player.pos = pos0; g.player.vel = .zero; g.survival = surv0; g.player.flying = fly0; ships.encounters = enc0
            g.onToast = toast0; g.health = health0
        }
        ships.encounters = false
        g.onToast = { _ in }
        BridgeHunt.reset(ships)
        let fx = Int(floor(pos0.x)) + 40, fz = Int(floor(pos0.z))
        let py = min(CH - 60, w.topY(fx, fz) + 24)
        _ = w.loadSync(center: V3(Float(fx + 32), Float(py), Float(fz)), radius: 6)
        // The pool: 68 long (x), 9 wide, 6 of water over a stone floor.
        for x in (fx - 2)...(fx + 65) { for z in (fz - 5)...(fz + 5) { for y in py...(py + 7) {
            let wall = x == fx - 2 || x == fx + 65 || z == fz - 5 || z == fz + 5 || y == py
            w.setBlock(x, y, z, wall ? STONE : (y <= py + 6 ? WATER : AIR)); placed.append(IVec3(x, y, z))
        } } }
        let rail = Blocks.id("rail"), deck = Blocks.id("spruce_planks"), leg = Blocks.id("spruce_log")
        let ry = py + 12                                   // the rail's y: the deck 4 over the water
        var cells: [IVec3] = []
        func put(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) { w.setBlock(x, y, z, b); placed.append(IVec3(x, y, z)) }
        for i in 0..<64 {
            let x = fx + i
            cells.append(IVec3(x, ry, fz))
            put(x, ry, fz, rail)
            for dz in -1...1 { put(x, ry - 1, fz + dz, deck) }
            if i % 4 == 0 { for dz in [-1, 1] { for y in (py + 1)...(ry - 2) { put(x, y, fz + dz, leg) } } }
            if i % 8 == 4 { for y in (py + 1)...(ry - 2) { put(x, y, fz, leg) } }
        }
        // (what falls lands in the pool: its cells are cleared with it)
        for x in (fx - 2)...(fx + 65) { for z in (fz - 5)...(fz + 5) { for y in (py + 8)...(ry + 2) { placed.append(IVec3(x, y, z)) } } }
        let t = Trains.Track(id: trackId, name: "check", cells: cells, slopes: [Bool](repeating: false, count: cells.count), stops: [],
                             stopNames: [], armoured: false, dim: .overworld)
        func rails() -> Int { cells.filter { Rails.isRail(w.block($0.x, $0.y, $0.z)) }.count }
        func hanging() -> Int {
            // deck cells of the track with no standing leg within reach
            var n = 0
            for (i, c) in cells.enumerated() where Blocks.groupBase[Int(w.block(c.x, c.y - 1, c.z))] == Blocks.groupBase[Int(deck)] {
                var held = false
                for j in max(0, i - BridgeHunt.reach - 1)...min(cells.count - 1, i + BridgeHunt.reach + 1) {
                    for dz in -1...1 where BridgeHunt.legState(w, cells[j].x, ry - 2, fz + dz, Blocks.groupBase[Int(leg)]) == 1 { held = true }
                }
                if !held { n += 1 }
            }
            return n
        }
        func settle() { for _ in 0..<8 { if BridgeHunt.weigh(g, t, at: 32, back: 40, fwd: 40) == 0 { break } } }
        let fell0 = BridgeHunt.weigh(g, t, at: 32, back: 40, fwd: 40)
        check(fell0 == 0 && rails() == 64, "bridge hunt: an untouched trestle stands (\(fell0) blocks fell, \(rails()) of 64 rail cells)")

        // One row of legs cut at the water (cell 16), then the next (cell 20; its centre pier is cell 20's own).
        // (cut as a blast cuts them: each log a hurt cell, BridgeHunt.broke)
        func cut(_ x: Int, _ y: Int, _ z: Int) { BridgeHunt.broke(w.block(x, y, z), x, y, z); w.setBlock(x, y, z, AIR) }
        for dz in [-1, 1] { for y in (py + 5)...(py + 8) { cut(fx + 16, y, fz + dz) } }
        let hang1 = hanging()
        settle()
        let one = rails(), gap1 = BridgeHunt.gap(g, cells[16]), kept = ships.spawnedRegions.contains(BridgeHunt.gapKey(cells[16]))
        check(hang1 == 1 && hanging() == 0 && one == 63 && gap1 && kept && Rails.isRail(w.block(fx + 14, ry, fz)),
              "bridge hunt: a row of legs cut, the deck over it falls (hanging \(hang1) before, \(hanging()) after; \(one) of 64 rail cells; gap remembered \(gap1), saved \(kept))")
        for dz in -1...1 { for y in (py + 5)...(py + 8) { cut(fx + 20, y, fz + dz) } }
        let hang2 = hanging()
        settle()
        let gone = (16...20).filter { !Rails.isRail(w.block(fx + $0, ry, fz)) }.count
        let stumps = (16...20).reduce(0) { n, i in n + (-1...1).filter { w.block(fx + i, ry - 2, fz + $0) != AIR }.count }
        check(hang2 >= 3 && hanging() == 0 && gone == 5 && stumps == 0 && Rails.isRail(w.block(fx + 22, ry, fz)) && BridgeHunt.fell > 0,
              "bridge hunt: two rows cut, the span between the standing legs falls (hanging \(hang2) before, \(hanging()) after; \(gone) of 5 rail cells gone, \(stumps) stumps left under it)")

        // The area rule.
        let ax = fx + 4000, az = fz
        let k = BridgeHunt.free(ships, ax, az)
        let fr = ships.spawnVessel("frigate", home: IVec3(fx + 20, py + 40, fz + 60), game: g)
        if let k = k { BridgeHunt.claim(fr, k) }
        let taken = BridgeHunt.free(ships, ax, az) == nil, other = BridgeHunt.free(ships, ax + BridgeHunt.area, az) != nil
        fr.wrecked = true
        g.bridgeHuntTick(0.6)
        let spent = k.map { ships.spawnedRegions.contains($0) } ?? false
        check(k != nil && taken && other && spent && BridgeHunt.free(ships, ax, az) == nil,
              "bridge hunt: one hunter to an area of sea (free \(k != nil), taken while she lives \(taken), the next area free \(other)); wrecked, the area is spent for good (\(spent))")
        ships.remove(fr)

        // The hunt: a driven train on the bridge's far half, he rides its car.
        let tr = Trains.Train(t)
        let car = Mob(.minecart, at: V3(Float(fx + 30) + 0.5, Float(ry), Float(fz) + 0.5))
        tr.cars = [car]; tr.driven = true; tr.driveS = 30; tr.driveFwd = 1; tr.driveV = 0
        Trains.trains[trackId] = tr
        g.riding = car
        g.survival = true
        g.player.flying = true
        g.player.pos = car.pos + V3(0, 0.5, 0); g.player.vel = .zero
        let railsBefore = rails()
        func hunt() -> (came: Bool, firstShot: Float, firstFall: Float, hunters: Int) {
            let spawned0 = BridgeHunt.spawned, shots0 = BridgeHunt.shots, fell1 = BridgeHunt.fell
            var came = false, firstShot: Float = -1, firstFall: Float = -1
            var time: Float = 0
            while time < 40 && firstFall < 0 {
                g.riding = car
                g.player.pos = car.pos + V3(0, 0.5, 0); g.player.vel = .zero
                g.health = 20
                g.bridgeHuntTick(1.0 / 60)
                ships.update(1.0 / 60, game: g)
                time += 1.0 / 60
                if BridgeHunt.spawned > spawned0 { came = true }
                if firstShot < 0 && BridgeHunt.shots > shots0 { firstShot = time }
                if BridgeHunt.fell > fell1 { firstFall = time }
            }
            return (came, firstShot, firstFall, ships.list.filter { !ships0.contains(ObjectIdentifier($0)) && BridgeHunt.hunts($0) }.count)
        }
        // (the before, BS_NOBRIDGEHUNT=1: the same 40 s ride over the same bridge)
        BridgeHunt.on = false
        let off = hunt()
        BridgeHunt.on = true
        print(String(format: "bridge hunt (before, BS_NOBRIDGEHUNT): riding the bridge 40 s, %d hunters came, %d shots, deck fell %@; %d of %d rail cells left",
                     off.hunters, off.firstShot > 0 ? 1 : 0, off.firstFall > 0 ? "yes" : "no", rails(), railsBefore))
        let (came, firstShot, firstFall, hunters) = hunt()
        check(came && hunters == 1 && firstShot > 0 && firstFall > 0 && rails() < railsBefore,
              String(format: "bridge hunt: riding the bridge a hunter comes (%d), shoots a pier ahead (first shot %.1f s) and the deck falls (%.1f s; %d of %d rail cells left)",
                     hunters, firstShot, firstFall, rails(), railsBefore))
    }
}

// Ledger 214, Fable's 3a: on generated bridges, untouched, a weigh pass along the whole span with a hurt cell every 8
// cells drops nothing (legState read on real legs): the river bridge the P379 (4) ride crosses (RailwayTests.ride) and
// a sea trestle of an open-country line (here).
extension BridgeHuntTests {
    // Weighs every run of `idx` (indices into t.cells) with fake hurt cells; returns (deck cells, blocks fell, notes).
    static func weighUntouched(_ g: Game, _ t: Trains.Track, _ idx: [Int]) -> (decks: Int, fell: Int, legs: Int, notes: [String]) {
        let w = g.world
        guard !idx.isEmpty else { return (0, 0, 0, []) }
        let hurt0 = BridgeHunt.hurt, notes0 = BridgeHunt.notes, gaps0 = BridgeHunt.gaps
        defer { BridgeHunt.hurt = hurt0; BridgeHunt.gaps = gaps0 }
        BridgeHunt.notes = []
        var runs: [[Int]] = [], cur: [Int] = []
        for i in idx.sorted() { if let l = cur.last, i != l + 1 { runs.append(cur); cur = [] }; cur.append(i) }
        if !cur.isEmpty { runs.append(cur) }
        var decks = 0, fell = 0, legs = 0
        for r in runs {
            for i in stride(from: r.first!, through: r.last!, by: 24) {
                let c = t.cells[i]
                _ = w.loadSync(center: V3(Float(c.x), Float(c.y), Float(c.z)), radius: 2)
            }
            for i in r {
                let c = t.cells[i]
                if Blocks.groupBase[Int(w.block(c.x, c.y - 1, c.z))] == BridgeHunt.deckGroup { decks += 1 }
                for dz in -1...1 { for dx in -1...1 where BridgeHunt.legState(w, c.x + dx, c.y - 2, c.z + dz, BridgeHunt.legGroup) != 0 { legs += 1 } }
            }
            BridgeHunt.hurt = [:]
            for i in stride(from: r.first!, through: r.last!, by: 8) { let c = t.cells[i]; BridgeHunt.hurt[IVec3(c.x, c.y - 2, c.z)] = 0 }
            let fell0 = BridgeHunt.fell
            for i in stride(from: r.first!, through: r.last!, by: 60) { BridgeHunt.weigh(g, t, at: Float(i), back: 70, fwd: 90, limit: 10_000) }
            fell += BridgeHunt.fell - fell0
        }
        let notes = BridgeHunt.notes
        BridgeHunt.notes = notes0
        return (decks, fell, legs, notes)
    }

    // A sea trestle of an open-country line: the longest run over the ocean among the lines round the origin.
    static func seaTrestle(_ g0: Game, check: (Bool, String) -> Void) {
        let scope = SuiteScope(g0); defer { scope.putBack(g0) }   // (job 6)
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        var pick: (UInt64, Railways.Line, [Int])?
        for k in 0..<3 where pick == nil {
            let seed = UInt64(1000 + k * 7919)
            let gen = WorldGen(seed: seed)
            gen.fieldWorld = true
            for row in -2...2 { for st in -2...2 {
                guard let l = Railways.line(gen, row: row, stretch: st), l.wild else { continue }
                var best: [Int] = [], run: [Int] = []
                for (i, c) in l.cells.enumerated() {
                    if gen.column(c.x, c.z).biome.isOcean && gen.groundY(c.x, c.z) < SEA - 3 && c.y > SEA { run.append(i) } else { if run.count > best.count { best = run }; run = [] }
                }
                if run.count > best.count { best = run }
                if best.count >= 24 && (pick == nil || best.count > pick!.2.count) { pick = (seed, l, Array(best.prefix(160))) }
            } }
        }
        guard let (seed, l, idx) = pick else { check(false, "bridge hunt: no open-country line with 24 cells over the sea round the origin (seeds 1000, 8919, 16838)"); return }
        let world = World(seed: seed, device: g0.world.device, save: nil)
        world.makeFieldWorld()
        world.renderDistance = 3; world.activeDistance = 3
        let g = Game(world: world, save: nil, persistent: false)
        g.survival = false
        let c0 = l.cells[idx[idx.count / 2]]
        g.player.pos = V3(Float(c0.x) + 0.5, Float(c0.y + 2), Float(c0.z) + 0.5); g.player.flying = true
        let t = Trains.track(l)
        let r = weighUntouched(g, t, idx)
        if r.fell > 0 { print("bridge hunt: sea trestle dropped: " + r.notes.joined(separator: " | ")) }
        let what = "bridge hunt: an untouched sea trestle (seed \(seed) \(l.name), \(idx.count) cells over the sea, \(r.decks) on a plank deck, \(r.legs) leg columns), weighed end to end with a hurt cell every 8: \(r.fell) blocks fell"
        if Railways.sparseLegs || BridgeHunt.oldLegRule { print("bridge hunt (before, BS_OLDTRESTLELEGS / BS_OLDLEGRULE): " + what) } else { check(r.decks > idx.count / 2 && r.legs > 0 && r.fell == 0, what) }
    }
}

// Fable (Nov 16): a trestle drawn before the diagonal lines' legs (centre piers only, 8 apart): one pier cut drops the
// two spans it carried, and the spans beside them, untouched, stand. Both ways (before: BridgeHunt.anySpan).
extension BridgeHuntTests {
    static func sparse(game g: Game, check: (Bool, String) -> Void) {
        let scope = SuiteScope(g); defer { scope.putBack(g) }   // (job 6)
        guard BridgeHunt.on else { return }
        let w = g.world, ships = w.ships
        let pos0 = g.player.pos, regions0 = ships.spawnedRegions, any0 = BridgeHunt.anySpan
        var placed: [IVec3] = []
        defer {
            g.falling.removeAll()
            for q in placed { w.setBlock(q.x, q.y, q.z, AIR) }
            ships.spawnedRegions = regions0
            BridgeHunt.anySpan = any0
            BridgeHunt.reset(ships)
        }
        BridgeHunt.reset(ships)
        let fx = Int(floor(pos0.x)) + 40, fz = Int(floor(pos0.z)) + 40
        let py = min(CH - 60, w.topY(fx, fz) + 24)
        _ = w.loadSync(center: V3(Float(fx + 32), Float(py), Float(fz)), radius: 6)
        let rail = Blocks.id("rail"), deck = Blocks.id("spruce_planks"), leg = Blocks.id("spruce_log")
        let ry = py + 12
        var cells: [IVec3] = []
        for i in 0..<64 { cells.append(IVec3(fx + i, ry, fz)) }
        let t = Trains.Track(id: -20901, name: "check", cells: cells, slopes: [Bool](repeating: false, count: cells.count), stops: [],
                             stopNames: [], armoured: false, dim: .overworld)
        func put(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) { w.setBlock(x, y, z, b); placed.append(IVec3(x, y, z)) }
        func build() {
            for x in (fx - 2)...(fx + 65) { for z in (fz - 5)...(fz + 5) { for y in py...(ry + 2) {
                let wall = x == fx - 2 || x == fx + 65 || z == fz - 5 || z == fz + 5 || y == py
                put(x, y, z, y > py + 7 ? AIR : wall ? STONE : (y <= py + 6 ? WATER : AIR))
            } } }
            for i in 0..<64 {
                put(fx + i, ry, fz, rail)
                for dz in -1...1 { put(fx + i, ry - 1, fz + dz, deck) }
                if i % 8 == 4 { for y in (py + 1)...(ry - 2) { put(fx + i, y, fz, leg) } }
            }
            g.falling.removeAll()
        }
        func run() -> (gone: [Int], fell: Int) {
            build()
            BridgeHunt.hurt = [:]; BridgeHunt.gaps = []
            // (the pier at cell 28 cut at the water, as a blast cuts it)
            for y in (py + 5)...(py + 8) { let x = fx + 28; BridgeHunt.broke(w.block(x, y, fz), x, y, fz); w.setBlock(x, y, fz, AIR) }
            let fell0 = BridgeHunt.fell
            for _ in 0..<8 { if BridgeHunt.weigh(g, t, at: 32, back: 40, fwd: 40) == 0 { break } }
            return ((0..<64).filter { !Rails.isRail(w.block(fx + $0, ry, fz)) }, BridgeHunt.fell - fell0)
        }
        BridgeHunt.anySpan = true
        let before = run()
        BridgeHunt.anySpan = false
        let after = run()
        func span(_ g: [Int]) -> String { g.isEmpty ? "none" : "\(g.count) (\(g.first!)-\(g.last!))" }
        print("bridge hunt (before, BS_ANYSPAN): centre piers 8 apart, the pier at 28 cut: rail cells gone \(span(before.gone)), \(before.fell) blocks fell")
        check(after.gone == Array(24...32) && Rails.isRail(w.block(fx + 16, ry, fz)) && Rails.isRail(w.block(fx + 40, ry, fz)),
              "bridge hunt: on a trestle of centre piers 8 apart one pier cut drops the two spans it carried (rail cells gone \(span(after.gone)), want 9 (24-32); \(after.fell) blocks fell) and the next spans' middles stand (16 \(Rails.isRail(w.block(fx + 16, ry, fz))), 40 \(Rails.isRail(w.block(fx + 40, ry, fz)))); before: \(span(before.gone))")
    }
}
