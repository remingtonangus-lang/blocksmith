import Foundation
import simd

// Ledger 209 checks (`questcheck --bridgehunt-only`, and part of every questcheck run), on a trestle built over a
// walled pool high over the ground (64 cells of rail on a 3-wide plank deck, edge legs every 4 cells, a centre pier
// every 8, as Railways.draw builds a sea bridge):
//   stands    untouched, nothing falls
//   collapse  one row of legs cut: the deck over it falls and the rail cell is a remembered gap; the next row cut too:
//             the whole span between the standing legs falls; a train's blocked-line check sees the gap
//   area      an area with a living hunter sends no other; the hunter wrecked, the area is spent for good
//   hunt      riding a train over the bridge in survival a hunter comes, shoots a pier ahead, and deck falls
enum BridgeHuntTests {
    static func run(game g: Game, check: (Bool, String) -> Void) {
        guard BridgeHunt.on else { return }
        let w = g.world, ships = w.ships
        let pos0 = g.player.pos, surv0 = g.survival, fly0 = g.player.flying, enc0 = ships.encounters, toast0 = g.onToast
        let regions0 = ships.spawnedRegions, ships0 = ships.list.count, riding0 = g.riding, health0 = g.health
        var placed: [IVec3] = []
        let trackId: Int64 = -20900
        defer {
            Trains.trains[trackId] = nil
            g.riding = riding0
            while ships.list.count > ships0, let s = ships.list.last { ships.remove(s) }
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
                for j in max(0, i - BridgeHunt.reach)...min(cells.count - 1, i + BridgeHunt.reach) {
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
        for dz in [-1, 1] { for y in (py + 5)...(py + 8) { w.setBlock(fx + 16, y, fz + dz, AIR) } }
        let hang1 = hanging()
        settle()
        let one = rails(), gap1 = BridgeHunt.gap(g, cells[16]), kept = ships.spawnedRegions.contains(BridgeHunt.gapKey(cells[16]))
        check(hang1 == 1 && hanging() == 0 && one == 63 && gap1 && kept && Rails.isRail(w.block(fx + 14, ry, fz)),
              "bridge hunt: a row of legs cut, the deck over it falls (hanging \(hang1) before, \(hanging()) after; \(one) of 64 rail cells; gap remembered \(gap1), saved \(kept))")
        for dz in -1...1 { for y in (py + 5)...(py + 8) { w.setBlock(fx + 20, y, fz + dz, AIR) } }
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
        let spawned0 = BridgeHunt.spawned, shots0 = BridgeHunt.shots, fell1 = BridgeHunt.fell, railsBefore = rails()
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
        let hunters = ships.list.dropFirst(ships0).filter { BridgeHunt.hunts($0) }.count
        check(came && hunters == 1 && firstShot > 0 && firstFall > 0 && rails() < railsBefore,
              String(format: "bridge hunt: riding the bridge a hunter comes (%d), shoots a pier ahead (first shot %.1f s) and the deck falls (%.1f s; %d of %d rail cells left)",
                     hunters, firstShot, firstFall, rails(), railsBefore))
    }
}
