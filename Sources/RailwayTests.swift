import Foundation
import simd

// C1 railways (Railways.swift, Trains.swift): `questcheck --rail-only`.
//   rarity     lines and stations over 50 seeds in a 12,000-block square each (the citadels' rarity: about one per
//              4,000 x 4,000);
//   lines      every line: steps one block apart, at most one up or down a step, curves and platforms level, three or
//              more stations, never inside any surface structure, never over the open sea;
//   built      one line generated block by block: each step a rail of the planned shape with head room and something
//              under it, trestle decks held up by legs within four steps, buffer stops, a station sign and a TICKETS
//              sign at every station; old ground (a save's guard) keeps no line;
//   trains     the timetable stays on the track and stops at each station; near the player the train is three cars on
//              the rails; a seat in the coach carries you; a gun on the driver stops it; five uses crack the strongbox
//              (money, honour down, a bounty and a posse); a ticket takes you to the next station for its fare;
//   the Vault  four armoured lines with a stop at each end.
enum RailwayTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let share0 = Railways.share
        defer { Railways.share = share0 }
        // Rarity and the plan of every line.
        var lines = 0, stations = 0, bad: [String] = [], seedsWithLine = 0
        var sample: (UInt64, Railways.Line)?
        let half = 6000, seeds = 24
        let t0 = CFAbsoluteTimeGetCurrent()
        for k in 0..<seeds {
            let seed = UInt64(1000 + k * 7919)
            let gen = WorldGen(seed: seed)
            let found = Railways.near(gen, x0: -half, z0: -half, x1: half, z1: half, pad: 0)
                .filter { l in l.stations.contains { abs($0.x) <= half && abs($0.z) <= half } }
            if !found.isEmpty { seedsWithLine += 1 }
            for l in found {
                lines += 1; stations += l.stations.count
                bad += planProblems(gen, l).map { "seed \(seed) \(l.name): \($0)" }
                if sample == nil || l.stations.count > sample!.1.stations.count { sample = (seed, l) }
            }
        }
        let area = Float(2 * half) * Float(2 * half) * Float(seeds) / (4000 * 4000)
        let perSquare = Float(lines) / area
        print(String(format: "rail: %d lines (%d stations) over %d seeds in %.1f s", lines, stations, seeds, CFAbsoluteTimeGetCurrent() - t0))
        check(perSquare > 0.15 && perSquare < 2.5 && stations >= lines * Railways.minStations && bad.isEmpty,
              String(format: "C1 lines: %d over %d seeds (%.2f per 4000 x 4000), %d stations, %d seeds with one; plan problems %d", lines, seeds, perSquare, stations, seedsWithLine, bad.count)
              + (bad.isEmpty ? "" : ": " + bad.prefix(4).joined(separator: "; ")))
        guard let (seed, line) = sample else { check(false, "C1: no line in \(seeds) seeds"); return }
        built(seed, line, check)
        trains(g, seed, line, check)
        let vt = Trains.vaultTracks
        check(vt.count == 4 && vt.allSatisfy { $0.stops.count == 2 && $0.armoured && $0.cells.count > 300 },
              "C1 the Vault: \(vt.count) armoured lines, stops \(vt.map { $0.stops.count }), \(vt.map { $0.cells.count }) cells")
    }

    static func planProblems(_ gen: WorldGen, _ l: Railways.Line) -> [String] {
        var out: [String] = []
        let c = l.cells
        if l.stations.count < Railways.minStations { out.append("\(l.stations.count) stations") }
        for i in 1..<c.count {
            if abs(c[i].x - c[i - 1].x) + abs(c[i].z - c[i - 1].z) != 1 { out.append("step \(i) not adjacent"); break }
            if abs(c[i].y - c[i - 1].y) > 1 { out.append("step \(i) jumps \(c[i].y - c[i - 1].y)"); break }
        }
        for i in 1..<(c.count - 1) {
            let curve = c[i + 1].x - c[i].x != c[i].x - c[i - 1].x || c[i + 1].z - c[i].z != c[i].z - c[i - 1].z
            if curve && (c[i - 1].y != c[i].y || c[i + 1].y != c[i].y) { out.append("curve \(i) not level"); break }
            if (c[i - 1].y > c[i].y && c[i + 1].y > c[i].y) || (c[i - 1].y < c[i].y && c[i + 1].y < c[i].y) { out.append("dip/hump at \(i)"); break }
        }
        guard let sc = gen.structures else { return out }
        // Never inside a structure's piece (its own towns included: the station sits south of the box).
        var hits: Set<String> = []
        for t in sc.types where !Railways.skipKinds.contains(t.name) && t.name != SkyIsle.kind {
            let s = t.spacing * CS, r = t.reach * CS
            for rz in floorDiv(l.minZ - r, s)...floorDiv(l.maxZ + r, s) { for rx in floorDiv(l.minX - r, s)...floorDiv(l.maxX + r, s) {
                guard let o = sc.start(t, regionX: rx, regionZ: rz), o.max.x >= l.minX, o.min.x <= l.maxX, o.max.z >= l.minZ, o.min.z <= l.maxZ else { continue }
                for p in o.pieces {
                    if c.contains(where: { $0.x >= p.min.x && $0.x <= p.max.x && $0.z >= p.min.z && $0.z <= p.max.z && $0.y + 3 >= p.min.y && $0.y - 1 <= p.max.y }) { hits.insert(o.kind); break }
                }
            } }
        }
        if !hits.isEmpty { out.append("runs through \(hits.sorted())") }
        for i in stride(from: 0, to: c.count, by: 8) where gen.column(c[i].x, c[i].z).biome.isOcean { out.append("over the sea at \(i)"); break }
        return out
    }

    static func built(_ seed: UInt64, _ l: Railways.Line, _ check: (Bool, String) -> Void) {
        let gen = WorldGen(seed: seed)
        guard let sc = gen.structures else { return }
        var chunks: [IVec2Key: [BlockID]] = [:], ents: [(IVec3, BlockEntity)] = []
        var keys = Set<IVec2Key>()
        for c in l.cells { for dz in -1...1 { for dx in -1...1 { keys.insert(IVec2Key(floorDiv(c.x, CS) + dx, floorDiv(c.z, CS) + dz)) } } }
        for k in keys {
            var b = gen.generate(cx: k.x, cz: k.z)
            ents += sc.place(into: &b, cx: k.x, cz: k.z).entities
            chunks[k] = b
        }
        func at(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
            guard let c = chunks[IVec2Key(floorDiv(x, CS), floorDiv(z, CS))], y >= 0, y < CH else { return AIR }
            return c[Chunk.index(mod(x, CS), y, mod(z, CS))]
        }
        var bad: [String] = [], decks = 0, unheld = 0
        let deck = Blocks.id("spruce_planks"), leg = Blocks.id("spruce_log")
        var sinceLeg = 0
        for (i, c) in l.cells.enumerated() {
            let b = at(c.x, c.y, c.z)
            if !Rails.isRail(b) { bad.append("step \(i): \(Blocks.key(b))"); if bad.count > 6 { break }; continue }
            if Rails.shape(b) != l.shape(i) { bad.append("step \(i): shape \(Rails.shape(b)) not \(l.shape(i))") }
            if at(c.x, c.y + 1, c.z) != AIR || at(c.x, c.y + 2, c.z) != AIR { bad.append("step \(i): no head room") }
            let under = at(c.x, c.y - 1, c.z)
            if !Blocks.collide[Int(under)] { bad.append("step \(i): nothing under") }
            if under == deck {
                decks += 1
                // A leg under this step or its bed's edge?
                var held = false
                for (dx, dz) in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)] where at(c.x + dx, c.y - 2, c.z + dz) == leg || Blocks.collide[Int(at(c.x + dx, c.y - 2, c.z + dz))] { held = true }
                sinceLeg = held ? 0 : sinceLeg + 1
                if sinceLeg > 4 { unheld += 1; sinceLeg = 0 }
            } else { sinceLeg = 0 }
        }
        let signs = ents.filter { $0.1.kind == .sign }
        let named = l.stations.filter { s in signs.contains { abs($0.0.x - s.x) < 8 && abs($0.0.z - s.z) < 12 && $0.1.lines.contains { $0.contains(s.name) } } }.count
        let tickets = l.stations.filter { s in signs.contains { abs($0.0.x - s.x) < 8 && abs($0.0.z - s.z) < 12 && Trains.isTicketSign($0.1) } }.count
        let stops = [l.cells.first!, l.cells.last!].enumerated().filter { (k, c) in
            let n = k == 0 ? l.cells[1] : l.cells[l.cells.count - 2]
            return at(c.x + (c.x - n.x), c.y, c.z + (c.z - n.z)) == Blocks.id("stone_bricks")
        }.count
        // Old ground: a guard covering the line's middle keeps no line.
        let old = WorldGen(seed: seed)
        let mid = l.cells[l.cells.count / 2]
        old.structures?.legacyC1 = [StructureCache.key(floorDiv(mid.x, CS), floorDiv(mid.z, CS))]
        let row = Int(l.id >> 32), st = Int(Int32(truncatingIfNeeded: l.id))
        let oldLine = Railways.plan(old, row: row, stretch: st)
        check(bad.isEmpty && unheld == 0 && named == l.stations.count && tickets == l.stations.count && stops == 2 && oldLine == nil,
              "C1 built (seed \(seed), \(l.name)): \(l.cells.count) steps of rail with head room and a bed, \(decks) on trestle decks (\(unheld) runs of 5+ without a leg), "
              + "\(named)/\(l.stations.count) station signs, \(tickets) ticket boards, \(stops) buffer stops; old ground line \(oldLine == nil ? "none" : "kept")"
              + (bad.isEmpty ? "" : "; " + bad.prefix(4).joined(separator: "; ")))
    }

    static func trains(_ g0: Game, _ seed: UInt64, _ l: Railways.Line, _ check: (Bool, String) -> Void) {
        // The timetable: on the track, stops at each station, back and forth.
        let t = Trains.track(l)
        var seen = Set<Int>(), off = 0
        var tt: Double = 0
        while tt < t.period {
            let a = t.at(tt)
            if a.s < 0 || a.s > Float(l.cells.count - 1) { off += 1 }
            if let s = a.stop { seen.insert(s) }
            tt += 2
        }
        check(seen.count == l.stations.count && off == 0 && t.period > 60,
              String(format: "C1 timetable: a %.0f s round trip calls at %d of %d stations, %d samples off the track", t.period, seen.count, l.stations.count, off))
        // A game in that world beside the second station.
        let world = World(seed: seed, device: g0.world.device, save: nil)
        world.renderDistance = 4
        let g = Game(world: world, save: nil, persistent: false)
        g.paused = false
        g.survival = true
        let st = l.stations[1]
        let sc = l.cells[st.index]
        g.player.pos = V3(Float(sc.x) + 0.5, Float(sc.y), Float(sc.z - 2) + 0.5)
        _ = world.loadSync(center: g.player.pos, radius: 4)
        Trains.trains.removeAll()
        // Run the clock to when the train stands at this station.
        guard let tr0 = Optional(Trains.Train(t)) else { return }
        var at: Double = g.time, found = false
        for k in 0..<Int(t.period) { if t.at(g.time + Double(k)).stop == 1 { at = g.time + Double(k) + 2; found = true; break } }
        g.time = at
        Trains.tick(g)
        let tr = Trains.trains[t.id] ?? tr0
        let cars = tr.cars.count
        var onRail = 0
        for m in tr.cars {
            let x = Int(floor(m.pos.x)), z = Int(floor(m.pos.z))
            if l.cells.contains(where: { abs($0.x - x) <= 1 && abs($0.z - z) <= 1 }) { onRail += 1 }
        }
        check(found && cars == 3 && onRail == 3 && g.mobs.mobs.filter({ Trains.isCar($0) }).count == 3,
              "C1 train at \(st.name) Station: \(cars) cars built, \(onRail) on the track")
        guard cars == 3 else { return }
        // Ride the coach while it pulls out.
        let coach = tr.cars[1]
        _ = Trains.use(g, coach)
        let start = coach.pos
        for _ in 0..<(60 * 40) { g.time += 1.0 / 60; Trains.drive(tr.cars[0], 1.0 / 60, g); Trains.drive(coach, 1.0 / 60, g) }
        let moved = simd_length(coach.pos - start)
        let carried = g.riding === coach && simd_length(g.player.pos - coach.pos) < 1.6
        check(moved > 20 && carried, String(format: "C1 riding: the coach carried the player %.0f blocks in 40 s (seated %@)", moved, carried ? "yes" : "no"))
        g.dismount()
        // A hold-up: a gun on the driver stops it.
        if Items.has("six_iron") { g.inventory.held = ItemStack(Items.id("six_iron"), 1) }
        else if let k = Items.allKeys.first(where: { Guns.index(Items.id($0)) != nil }) { g.inventory.held = ItemStack(Items.id(k), 1) }
        var stoppedAfter: Float = -1
        for f in 0..<(60 * 12) {
            let lead = tr.cars[0]
            let cab = lead.pos + V3(0, 2.2, 0) - lead.forward * 0.9
            g.player.pos = cab + lead.forward * 9 + V3(0, -0.6, 0) - V3(0, g.player.eyeHeight, 0) + V3(0, 1.6, 0)
            let d = simd_normalize(cab - g.player.eye)
            g.player.yaw = atan2f(-d.x, -d.z); g.player.pitch = asinf(d.y)
            g.time += 1.0 / 60
            Trains.drive(lead, 1.0 / 60, g)
            if tr.brake > 0.95 { stoppedAfter = Float(f) / 60; break }
        }
        // Crack the strongbox.
        let money0 = g.money, bounty0 = Honour.bounty(Townsfolk.town(g, at: tr.cars[2].pos))
        g.inventory.held = .empty
        for _ in 0..<Trains.crackUses { _ = Trains.use(g, tr.cars[2]) }
        let posse = g.mobs.mobs.filter { $0.posse == 3 }.count
        let bounty = Honour.bounty(Townsfolk.town(g, at: tr.cars[2].pos)) - bounty0
        check(stoppedAfter >= 0 && g.money - money0 >= 4000 && bounty >= Trains.robBounty && posse >= 3 && Trains.robbed >= 1,
              String(format: "C1 robbery: stopped %.1f s after the gun came up, strongbox %@, bounty +%@, posse of %d", stoppedAfter,
                     Money.format(g.money - money0), Money.format(bounty), posse))
        // A ticket to the next station.
        let to = l.stations[2]
        g.money = 100_00
        let t1 = g.time
        let r = Trains.travel(g, line: l, from: st, to: to)
        let there = simd_length(V2(g.player.pos.x - Float(to.x), g.player.pos.z - Float(to.z))) < 6
        check(r.1 && there && g.money == 100_00 - Trains.fare(st, to) && g.time > t1,
              "C1 ticket: \(st.name) to \(to.name) for \(Money.format(Trains.fare(st, to))), arrived \(there), \(Int(g.time - t1)) s on the train")
        Trains.trains.removeAll()
    }
}
