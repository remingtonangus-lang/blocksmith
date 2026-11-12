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
        sites(check)
        let perSquare = Float(lines) / area
        print(String(format: "rail: %d lines (%d stations) over %d seeds in %.1f s", lines, stations, seeds, CFAbsoluteTimeGetCurrent() - t0))
        check(perSquare > 0.15 && perSquare < 4.5 && stations   // (P470: two stations make a line on new ground, about 3 a square)
               >= lines * Railways.minStations && bad.isEmpty,
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
        let named = l.stations.filter { s in signs.contains { abs($0.0.x - s.x) < 8 && abs($0.0.z - s.z) < 12 && $0.1.lines.joined(separator: " ").contains(s.name) } }.count   // (a long name runs over two lines)
        let tickets = l.stations.filter { s in signs.contains { abs($0.0.x - s.x) < 8 && abs($0.0.z - s.z) < 12 && Trains.isTicketSign($0.1) } }.count
        // (P510: an end a link runs on from has rail on past it, not a buffer stop)
        let open0 = Railways.openEnds(gen, l), lp = Railways.loops(gen, l)       // (P511: and an end that turns in a loop)
        let open = (west: open0.west || lp.west != nil, east: open0.east || lp.east != nil)
        var ends: [String] = []
        let stops = [l.cells.first!, l.cells.last!].enumerated().filter { (k, c) in
            let n = k == 0 ? l.cells[1] : l.cells[l.cells.count - 2]
            let past = at(c.x + (c.x - n.x), c.y, c.z + (c.z - n.z))
            let o = k == 0 ? open.west : open.east
            ends.append("\(k == 0 ? "west" : "east") \(o ? "linked" : "end"): \(Blocks.key(past)) past \(c.x) \(c.y) \(c.z)")
            return o ? Rails.isRail(past) : past == Blocks.id("stone_bricks")
        }.count
        // Old ground: a guard covering the line's middle keeps no line.
        let old = WorldGen(seed: seed)
        let mid = l.cells[l.cells.count / 2]
        old.structures?.legacyC1 = [StructureCache.key(floorDiv(mid.x, CS), floorDiv(mid.z, CS))]
        let row = Int(l.id >> 32), st = Int(Int32(truncatingIfNeeded: l.id))
        let oldLine = Railways.plan(old, row: row, stretch: st)
        check(bad.isEmpty && unheld == 0 && named == l.stations.count && tickets == l.stations.count && stops == 2 && oldLine == nil,
              "C1 built (seed \(seed), \(l.name)): \(l.cells.count) steps of rail with head room and a bed, \(decks) on trestle decks (\(unheld) runs of 5+ without a leg), "
              + "\(named)/\(l.stations.count) station signs, \(tickets) ticket boards, \(stops) buffer stops (\(ends.joined(separator: ", "))); old ground line \(oldLine == nil ? "none" : "kept")"
              + (bad.isEmpty ? "" : "; " + bad.prefix(4).joined(separator: "; ")))
    }

    // P379 step 1: lines call at the major sites in their rows (citadels, capital cities, Greywall bases, Boreal
    // stations): over the seeds, how many sites stand in a lined row's band and how many get a station.
    static func sites(_ check: (Bool, String) -> Void) {
        var lines = 0, siteStops = 0, towns = 0, kinds: [String: Int] = [:]
        for k in 0..<24 {
            let gen = WorldGen(seed: UInt64(1000 + k * 7919))
            for l in Railways.near(gen, x0: -6000, z0: -6000, x1: 6000, z1: 6000, pad: 0) {
                lines += 1
                for st in l.stations {
            guard st.site else { towns += 1; continue }
            siteStops += 1
            let kind = st.name.hasPrefix("Fort ") ? "citadel" : st.name.hasPrefix("Greywall ") ? "Greywall base"
                : st.name.hasSuffix(" Central") ? "capital city" : "Boreal station"
            kinds[kind, default: 0] += 1
        }
            }
        }
        print("rail sites: \(siteStops) site stations on \(lines) lines (\(towns) town stations); by name: \(kinds.sorted { $0.key < $1.key })")
        check(siteStops > 0, "P379 (1): \(siteStops) stations at citadels, capital cities, Greywall bases and Boreal stations on \(lines) lines")
    }

    // P379 step 4: a whole line ridden end to end from the locomotive's cab in a field world, through Game.tick: the
    // line chosen has a cutting (land 2+ blocks over the bed), a tunnel (land over the 4-block clearance) and a bridge
    // (a deck over water). The driver opens the regulator and rides from the first station to the last; the rider must
    // stay in the cab with clear air round the head, the train on the track, and every station passed. Then the brake:
    // with the regulator still open, the brake alone brings the train to a stand.
    static func ride(_ g0: Game, check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        // (one line end to end: its train stops at its last station; links and through trains: RailwayTests.through)
        Railways.linksOn = false
        defer { Railways.linksOn = true }
        let loops0 = Railways.loopsOn
        Railways.loopsOn = false
        defer { Railways.loopsOn = loops0 }
        struct Kinds { var cut = 0, tunnel = 0, bridge = 0 }
        func kinds(_ gen: WorldGen, _ l: Railways.Line) -> ([UInt8], Kinds) {
            var k = Kinds(), tag = [UInt8](repeating: 0, count: l.cells.count)
            for (i, c) in l.cells.enumerated() {
                let col = gen.column(c.x, c.z), gy = gen.groundY(c.x, c.z)
                if gy >= c.y + 4 { tag[i] = 2; k.tunnel += 1 }
                else if gy >= c.y + 1 { tag[i] = 1; k.cut += 1 }
                else if (col.biome == .river || gy < SEA) && c.y > gy + 2 { tag[i] = 3; k.bridge += 1 }
            }
            return (tag, k)
        }
        var pick: (UInt64, Railways.Line, [UInt8])?
        var tried = 0
        search: for k in 0..<60 {
            let seed = UInt64(1000 + k * 7919)
            let gen = WorldGen(seed: seed)
            gen.fieldWorld = true
            for l in Railways.near(gen, x0: -6000, z0: -6000, x1: 6000, z1: 6000, pad: 0) {
                tried += 1
                let (tag, n) = kinds(gen, l)
                if n.cut >= 4 && n.tunnel >= 4 && n.bridge >= 4 && (pick == nil || l.cells.count < pick!.1.cells.count) { pick = (seed, l, tag) }
            }
            if pick != nil && k >= 8 { break search }
        }
        guard let (seed, l, tag) = pick, let hs = l.heights else { check(false, "P379 (4): no line with a cutting, a tunnel and a bridge in \(tried) field-world lines"); return }
        print("rail ride: seed \(seed) \(l.name), \(l.cells.count) cells, \(l.stations.count) stations; cutting \(tag.filter { $0 == 1 }.count), tunnel \(tag.filter { $0 == 2 }.count), bridge \(tag.filter { $0 == 3 }.count) cells")
        // The planned grade (P379 step 3): at most 1 in 8 a step, the rails within half a block of it.
        var steep = 0, off = 0
        for i in 1..<hs.count where abs(hs[i] - hs[i - 1]) > Railways.grade + 0.01 { steep += 1 }
        for i in hs.indices where abs(hs[i] - Float(l.cells[i].y)) > 0.51 { off += 1 }
        check(steep == 0 && off == 0, "P379 (3): the line's grade at most 1 in 8 (\(steep) steeper steps), rails at the planned height (\(off) off)")
        let world = World(seed: seed, device: g0.world.device, save: nil)
        world.makeFieldWorld()
        world.renderDistance = 3; world.activeDistance = 3
        let g = Game(world: world, save: nil, persistent: false)
        g.paused = false; g.survival = false
        let t = Trains.track(l)
        let first = l.stations[0], last = l.stations[l.stations.count - 1]
        let c0 = l.cells[first.index]
        g.player.pos = V3(Float(c0.x) + 0.5, Float(c0.y), Float(c0.z - 2) + 0.5)
        _ = world.loadSync(center: g.player.pos, radius: 3)
        Trains.trains.removeAll()
        // The clock at the first station's dwell before the run east (the timetable starts there).
        var at = g.time
        for k in 0..<Int(t.period) { let a = t.at(g.time + Double(k)); if a.stop == 0 && a.dir > 0 { at = g.time + Double(k) + 1; break } }
        g.time = at
        Trains.forceKind = .passenger
        defer { Trains.forceKind = nil }
        Trains.tick(g)
        guard let tr = Trains.trains[t.id], let lead = tr.cars.first else { check(false, "P379 (4): no train built at \(first.name)"); return }
        _ = Trains.use(g, lead)
        tr.throttle = 2                                                       // (the driver's regulator wide open)
        let dt: Float = 1.0 / 60
        var passed = Set<UInt8>(), stops: Set<Int> = [0], headIn = 0, offTrack = 0, unseated = 0, frames = 0, worst = 0.0
        var lastLoad = g.time, maxS: Float = 0, stall = 0
        var bedSeen = Set<Int>(), shallowDecks = 0
        var peak: Float = 0, stood = 0                                   // (Nov 12: top speed; frames stood at a station)
        let plankDeck = Blocks.id("spruce_planks"), banked0 = Railways.banked
        let t1 = CFAbsoluteTimeGetCurrent()
        while frames < 60 * 900 {
            if g.time - lastLoad > 1.5 { _ = world.loadSync(center: g.player.pos, radius: 3); lastLoad = g.time }
            let f0 = CFAbsoluteTimeGetCurrent()
            g.tick(Double(dt))
            worst = max(worst, CFAbsoluteTimeGetCurrent() - f0)
            frames += 1
            guard let lead = tr.cars.first else { unseated += 1; break }
            if g.riding !== lead {
                if unseated < 3 {
                    print("rail ride: unseated at frame \(frames): riding \(g.riding.map { "\($0.variant) h\($0.health)" } ?? "nil"), lead \(lead.variant) h\(lead.health) "
                          + "in mobs \(g.mobs.mobs.contains { $0 === lead }), car of \(Trains.carOf[ObjectIdentifier(lead)] != nil), cars \(tr.cars.count), same train \(Trains.trains[t.id] === tr), trains \(Trains.trains.count)")
                }
                unseated += 1; _ = Trains.use(g, lead)
            }
            tr.throttle = 2
            let s = Trains.now(tr).s
            maxS = max(maxS, s)
            peak = max(peak, tr.blocksPerSec)
            let i = max(0, min(l.cells.count - 1, Int(s.rounded())))
            if tag[i] != 0 { passed.insert(tag[i]) }
            // P510 ("Wood is a block"): a plank deck over a shallow dry dip, where the bed should be banked with earth.
            if bedSeen.insert(i).inserted {
                let c = l.cells[i]
                if world.block(c.x, c.y - 1, c.z) == plankDeck {
                    for d in 2...5 {
                        let b = world.block(c.x, c.y - d, c.z)
                        if Blocks.fluidKind[Int(b)] != 0 { break }
                        if world.groundAt(c.x, c.y - d, c.z) || (Blocks.opaque[Int(b)] && Blocks.collide[Int(b)] && b != plankDeck) {
                            shallowDecks += 1
                            if shallowDecks <= 3 {
                                let col = (1...6).map { k in "\(Blocks.key(world.block(c.x, c.y - k, c.z)))\(world.groundAt(c.x, c.y - k, c.z) ? "*" : "")" }
                                Railways.noteLock.lock(); let saw = Railways.deckNotes["\(c.x) \(c.y) \(c.z)"] ?? "no note"; Railways.noteLock.unlock()
                                print("rail ride: a plank deck over a shallow dip at cell \(i) (\(c.x) \(c.y) \(c.z)), under it: \(col.joined(separator: ", ")); the writer saw \(saw)")
                            }
                            break
                        }
                    }
                }
            }
            if let st = Trains.now(tr).stop { stops.insert(st) }
            // (Nov 12: driven, the train runs through the stations: each one its head passes counts)
            // (within 0.6 of its cell: a frame at 28 b/s moves 0.47, so none is missed, and the last one ends the ride
            // with the head on it; standing counts once it has got going, not its start from the first)
            for (k, st) in l.stations.enumerated() where abs(s - Float(st.index)) < 0.6 {
                stops.insert(k)
                if tr.blocksPerSec < 0.05 && peak > 1 { stood += 1 }
            }
            let e = g.player.eye
            if world.solidAt(Int(floor(e.x)), Int(floor(e.y)), Int(floor(e.z))) {
                if headIn == 0 {
                    let b = world.block(Int(floor(e.x)), Int(floor(e.y)), Int(floor(e.z)))
                    print(String(format: "rail ride: head in %@ at frame %d, cell %d (tag %d), eye %.1f over the rail, cab %.1f %.1f %.1f, pitch %.2f",
                                 Blocks.key(b), frames, i, Int(tag[i]), e.y - hs[i], lead.pos.x, lead.pos.y, lead.pos.z, lead.trainPitch))
                }
                headIn += 1
            }
            let px = Int(floor(lead.pos.x)), pz = Int(floor(lead.pos.z))
            let li = tr.carS.isEmpty ? i : max(0, min(l.cells.count - 1, Int(tr.carS[0].rounded())))     // (P470: the cab's own place)
            if abs(px - l.cells[li].x) > 1 || abs(pz - l.cells[li].z) > 1 || abs(lead.pos.y - hs[li]) > 0.75 { offTrack += 1 }
            if stops.contains(l.stations.count - 1) { break }                // (the last station's dwell)
            // (a stall away from a station: what holds it, printed once)
            if tr.blocksPerSec < 0.05 && Trains.now(tr).stop == nil { stall += 1 } else { stall = 0 }
            if stall == 300 {
                let c = l.cells[i], a = l.cells[min(l.cells.count - 1, i + 3)]
                print("rail ride: stalled at cell \(i) (\(c.x) \(c.y) \(c.z)): held \(tr.heldBy) brake \(tr.brake) cab brake \(tr.cabBrake) regulator \(tr.throttle) pace \(tr.rate); 3 ahead \(Blocks.key(world.block(a.x, a.y, a.z)))")
            }
        }
        check(shallowDecks == 0 && Railways.banked > banked0,
              "P510 trains: the bed over shallow dry dips is banked earth, not a plank trestle (\(shallowDecks) plank steps over a dip of 4 or less, \(Railways.banked - banked0) cells banked)")
        // P510: riding, the chase view sits out behind the train and over it, not in the cab.
        if let o = g.chaseOffset, let lead = tr.cars.first {
            let run = t.point(tr.lastS + tr.dir * 2) - t.point(tr.lastS)
            check(simd_length(o) > 8 && o.y > 2 && simd_dot(V2(o.x, o.z), V2(run.x, run.z)) < 0,
                  String(format: "P510 trains: riding, the view is out behind the train (%.0f back, %.0f up), car %d", simd_length(V2(o.x, o.z)), o.y, lead.variant))
        } else { check(false, "P510 trains: riding, no chase view") }
        let wall = CFAbsoluteTimeGetCurrent() - t1
        print(String(format: "rail ride: %d frames (%.0f s of play, %.1f s wall), worst tick %.1f ms, reached cell %.0f of %d", frames, Float(frames) * dt, wall, worst * 1000, maxS, l.cells.count))
        check(maxS >= Float(last.index) - 0.5 && stops.count == l.stations.count && passed.count == 3 && unseated == 0 && headIn == 0 && offTrack == 0,
              "P379 (4): rode \(l.name) end to end from the cab: \(stops.count) of \(l.stations.count) stations, through cutting/tunnel/bridge \(passed.sorted()), unseated \(unseated), head in ground \(headIn) frames, off the track \(offTrack) frames")
        // P379 step 2, leaving the last station (after the ride: at full regulator it ran past the bridge before the ride was counted): the brake alone stops it, the regulator left open; let off, it runs again.
        let lead2 = tr.cars[0]
        // Nov 12: the cab is his (Trains.driveCab): at full regulator it reached 100 km/h and ran through every station.
        check(Trains.oldCab || (peak >= 26 && stood == 0),
              String(format: "Nov 12 trains: driven from the cab at full regulator it reached %.0f km/h and stood %d frames at the stations it passed", peak * 3.6, stood))
        var n = 0
        while Trains.now(tr).stop != nil && n < 60 * 60 { g.time += Double(dt); Trains.drive(lead2, dt, g); n += 1 }  // (the dwell)
        // (driven, it runs on to the line's buffers where no link runs on: near them, it backs for the brake's check)
        let tn = Float(tr.track.cells.count)
        if tr.driven && (tr.driveFwd > 0 ? tn - 1 - tr.driveS : tr.driveS) < 160 { tr.throttle = -1 }
        for _ in 0..<(60 * 12) { g.time += Double(dt); Trains.drive(lead2, dt, g); if tr.driven && tr.throttle >= 0 { tr.throttle = 2 } }   // (up to speed)
        let moving0 = tr.blocksPerSec
        var stopAfter: Float = -1
        g.rideInput = MoveInput(); g.rideInput.jump = true
        for f in 0..<(60 * 20) {
            g.time += Double(dt); Trains.drive(lead2, dt, g)
            if tr.blocksPerSec < 0.05 && Trains.now(tr).stop == nil { stopAfter = Float(f) / 60; break }
        }
        let braked = tr.cabBrake
        g.rideInput = MoveInput()
        for _ in 0..<(60 * 4) { g.time += Double(dt); Trains.drive(lead2, dt, g) }
        _ = world.loadSync(center: g.player.pos, radius: 3)
        check(moving0 > 1 && stopAfter > 0 && braked > 0.9 && tr.cabBrake < 0.1 && tr.blocksPerSec > 0.3,
              String(format: "P379 (2): regulator open at %.0f%%, the brake alone stopped the train from %.1f b/s in %.1f s; let off, it runs again (%.1f b/s)",
                     tr.throttle * 50, moving0, stopAfter, tr.blocksPerSec))
        // P510 (Nov 1 20:39, "Train's broken... Fix it"): a block on the rail that he didn't put there (a structure or a
        // tree drawn over the line) is cleared and the rail put back; one he placed still stops the train.
        // (on the train's own track: driven, it runs on through links, where the line's own cells no longer index it)
        func aheadCell(_ k: Float) -> IVec3 { tr.track.cell(tr.lastS + tr.dir * (tr.length / 2 + k)) }
        let stray = aheadCell(14)
        let stone = Blocks.id("stone")
        world.setBlock(stray.x, stray.y, stray.z, stone)
        Trains.placed[stray] = nil
        let cleared0 = Trains.cleared
        var strayHeld = false
        for _ in 0..<(60 * 6) {
            g.time += Double(dt); Trains.drive(lead2, dt, g)
            if tr.heldBy { strayHeld = true }
            if Trains.now(tr).stop != nil { break }
        }
        let strayRail = Rails.isRail(world.block(stray.x, stray.y, stray.z))
        // (under way again first: the stray loop can end at a station's dwell, and a train standing at a platform
        // never came to his block, suite 62)
        var under = 0
        while (Trains.now(tr).stop != nil || tr.blocksPerSec < 1) && under < 60 * 90 { g.time += Double(dt); Trains.drive(lead2, dt, g); under += 1 }
        let his = aheadCell(6)
        world.setBlock(his.x, his.y, his.z, stone)
        Trains.placed[his] = g.time
        var hisHeld = false
        for _ in 0..<(60 * 4) { g.time += Double(dt); Trains.drive(lead2, dt, g); if tr.heldBy { hisHeld = true; break } }
        world.setBlock(his.x, his.y, his.z, AIR); Trains.placed[his] = nil
        tr.heldBy = false; tr.brake = 0
        check(!strayHeld && strayRail && Trains.cleared > cleared0 && hisHeld,
              "P510 trains: a stray block on the rail is cleared and the rail put back (held \(strayHeld), rail back \(strayRail)); one he placed stops it (\(hisHeld))")
        // Nov 12: the pedal (the right trigger) opens the regulator; steam burns coal; with the tender empty the train
        // rolls to a stand; coal used on the engine from the cab starts it again.
        if !Trains.oldCab {
            g.survival = true
            defer { g.survival = false; g.seatPad = nil }
            for _ in 0..<(60 * 2) { g.time += Double(dt); Trains.drive(lead2, dt, g) }
            tr.throttle = 0
            var pad = PadSnapshot(); pad.rt = 1
            g.seatPad = pad
            for _ in 0..<(60 * 2) { g.time += Double(dt); Trains.drive(lead2, dt, g) }
            let pedal = tr.throttle
            g.seatPad = nil
            let tn2 = Float(tr.track.cells.count)
            tr.throttle = (tr.driveFwd > 0 ? tn2 - 1 - tr.driveS : tr.driveS) < 160 ? -1 : 2
            tr.coal = 0.4
            let burned0 = Trains.coalBurned
            var dryAfter: Float = -1
            for f in 0..<(60 * 60) {
                g.time += Double(dt); Trains.drive(lead2, dt, g)
                if tr.coal <= 0 && tr.blocksPerSec < 0.05 { dryAfter = Float(f) / 60; break }
            }
            g.inventory.held = ItemStack(Items.id("coal"), 5)
            let fed = Trains.use(g, lead2)
            // (it may have rolled up to the line's buffers while the fire was out: then it backs away)
            let room = tr.driveFwd > 0 ? tn2 - 1 - tr.driveS : tr.driveS
            tr.throttle = room < tr.length / 2 + 20 ? -1 : 2
            let tender = tr.coal, left = g.inventory.held.count
            for _ in 0..<(60 * 6) { g.time += Double(dt); Trains.drive(lead2, dt, g) }
            check(pedal > 1 && Trains.coalBurned > burned0 && dryAfter > 0 && fed && tender >= 5 && left == 0 && tr.blocksPerSec > 1,
                  String(format: "Nov 12 trains: the pedal opened the regulator to %.0f%%; the tender ran dry and the train came to a stand in %.0f s; 5 coal used on the engine (tender %.0f, %d left in hand) and it runs again (%.1f b/s)",
                         pedal * 50, dryAfter, tender, left, tr.blocksPerSec))
        }
        g.dismount()
        Trains.trains.removeAll()
    }

    static func trains(_ g0: Game, _ seed: UInt64, _ l: Railways.Line, _ check: (Bool, String) -> Void) {
        // (the line's own out-and-back timetable: P511's loops have their own check, RailLoopCheck)
        let loops0 = Railways.loopsOn
        Railways.loopsOn = false
        defer { Railways.loopsOn = loops0 }
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
        // (the first town after the first station: a robbery's posse rides out of a town)
        let si = l.stations.indices.dropFirst().first { !l.stations[$0].site } ?? 1
        let st = l.stations[si]
        let sc = l.cells[st.index]
        g.player.pos = V3(Float(sc.x) + 0.5, Float(sc.y), Float(sc.z - 2) + 0.5)
        _ = world.loadSync(center: g.player.pos, radius: 4)
        Trains.trains.removeAll()
        // Run the clock to when the train stands at this station.
        guard let tr0 = Optional(Trains.Train(t)) else { return }
        var at: Double = g.time, found = false
        for k in 0..<Int(t.period) { if t.at(g.time + Double(k)).stop == si { at = g.time + Double(k) + 2; found = true; break } }
        g.time = at
        Trains.forceKind = .passenger
        defer { Trains.forceKind = nil }
        Trains.tick(g)
        let tr = Trains.trains[t.id] ?? tr0
        let cars = tr.cars.count
        var onRail = 0
        for m in tr.cars {
            let x = Int(floor(m.pos.x)), z = Int(floor(m.pos.z))
            if l.cells.contains(where: { abs($0.x - x) <= 1 && abs($0.z - z) <= 1 }) { onRail += 1 }
        }
        check(found && cars >= 3 && onRail == cars && g.mobs.mobs.filter({ Trains.isCar($0) }).count == cars,
              "C1 train at \(st.name) Station: \(cars) cars built, \(onRail) on the track")
        guard cars >= 3, let coach = tr.cars.first(where: { $0.variant == Trains.coach }),
              let strong = tr.cars.first(where: { $0.variant == Trains.express }) else { return }
        TrainHullCheck.run(g, tr, check)                         // FAILURES 3: walking in, on the roof, from the cab
        // Ride the coach while it pulls out.
        _ = Trains.use(g, coach)
        let start = coach.pos
        for _ in 0..<(60 * 40) { g.time += 1.0 / 60; Trains.drive(tr.cars[0], 1.0 / 60, g); Trains.drive(coach, 1.0 / 60, g) }
        let moved = simd_length(coach.pos - start)
        let carried = g.riding === coach && simd_length(g.player.pos - Trains.seat(coach)) < 0.1
        check(moved > 20 && carried, String(format: "C1 riding: the coach carried the player %.0f blocks in 40 s (seated %@)", moved, carried ? "yes" : "no"))
        // P508 (one engine): the train's one engine is at its head, facing the way it runs.
        if let lead = Trains.lead(tr) {
            let way = simd_dot(lead.forward, coach.vel)
            let engines = tr.cars.filter { Trains.isEngine($0) }.count
            let ahead = simd_dot(lead.pos - coach.pos, coach.vel)
            check(way > 0 && engines == 1 && ahead > 0 && !Trains.isTrailing(lead),
                  String(format: "C1 engine: one engine (%d), at the head (%.1f ahead of the coach) facing the run (%.2f)", engines, ahead, way))
        }
        g.dismount()
        // A hold-up: a gun on the driver stops it.
        if Items.has("six_iron") { g.inventory.held = ItemStack(Items.id("six_iron"), 1) }
        else if let k = Items.allKeys.first(where: { Guns.index(Items.id($0)) != nil }) { g.inventory.held = ItemStack(Items.id(k), 1) }
        var stoppedAfter: Float = -1
        for f in 0..<(60 * 12) {
            guard let lead = Trains.lead(tr) else { break }
            let cab = Trains.cabPoint(lead)
            g.player.pos = cab + lead.forward * 9 + V3(0, -0.6, 0) - V3(0, g.player.eyeHeight, 0) + V3(0, 1.6, 0)
            let d = simd_normalize(cab - g.player.eye)
            g.player.yaw = atan2f(-d.x, -d.z); g.player.pitch = asinf(d.y)
            g.time += 1.0 / 60
            Trains.drive(tr.cars[0], 1.0 / 60, g)
            if tr.brake > 0.95 { stoppedAfter = Float(f) / 60; break }
        }
        // Crack the strongbox (stood at its side, out on the ground beside the stopped train).
        let side = V3(cosf(strong.yaw), 0, -sinf(strong.yaw)) * 2.6
        g.player.pos = world.freeSpawn(strong.pos + side)
        let money0 = g.money, bounty0 = Honour.bounty(Townsfolk.town(g, at: strong.pos))
        g.inventory.held = .empty
        for _ in 0..<Trains.crackUses { _ = Trains.use(g, strong) }
        let posse = g.mobs.mobs.filter { $0.posse == 3 }.count
        let bounty = Honour.bounty(Townsfolk.town(g, at: strong.pos)) - bounty0
        check(stoppedAfter >= 0 && g.money - money0 >= 4000 && bounty >= Trains.robBounty && posse >= 3 && Trains.robbed >= 1,
              String(format: "C1 robbery: stopped %.1f s after the gun came up, strongbox %@, bounty +%@, posse of %d", stoppedAfter,
                     Money.format(g.money - money0), Money.format(bounty), posse))
        // A ticket to the next station.
        let to = l.stations[si + 1 < l.stations.count ? si + 1 : si - 1]
        g.money = 100_00
        let t1 = g.time
        let r = Trains.travel(g, line: l, from: st, to: to)
        let there = simd_length(V2(g.player.pos.x - Float(to.x), g.player.pos.z - Float(to.z))) < 6
        check(r.1 && there && g.money == 100_00 - Trains.fare(st, to) && g.time > t1,
              "C1 ticket: \(st.name) to \(to.name) for \(Money.format(Trains.fare(st, to))), arrived \(there), \(Int(g.time - t1)) s on the train")
        // P508: an arrival comes down the line toward him from 170 blocks off; a military one in his town halts and shells it.
        Trains.forceKind = nil
        _ = world.loadSync(center: g.player.pos, radius: 4)
        if let atr = TrainArrivals.arrive(g, [t], kind: .cargo) {
            let near = l.cells.indices.min { simd_length(V2(Float(l.cells[$0].x) - g.player.pos.x, Float(l.cells[$0].z) - g.player.pos.z))
                                             < simd_length(V2(Float(l.cells[$1].x) - g.player.pos.x, Float(l.cells[$1].z) - g.player.pos.z)) } ?? 0
            let s0 = t.at(g.time - atr.delay).s
            for _ in 0..<20 { g.time += 1 }
            let s1 = t.at(g.time - atr.delay).s
            let closer = abs(s1 - Float(near)) < abs(s0 - Float(near))
            let along = TrainArrivals.alongFor(g)
            check(abs(abs(s0 - Float(near)) - along) < 25 && closer,
                  String(format: "P508 arrival: a train put %.0f blocks up the line from him (track cell %d; %.0f wanted at view %d), %.0f after 20 s", abs(s0 - Float(near)), near, along, g.world.renderDistance, abs(s1 - Float(near))))
            // Week item 71 (no pop-in): at view 16 (the fog ends 244 out) a train is made past the fog, and an arriving
            // one is put further up the line than that.
            let rd0 = world.renderDistance
            world.renderDistance = 16
            let fog = Float(16 * CS - 12), R = Trains.reach(g), up = TrainArrivals.alongFor(g)
            world.renderDistance = rd0
            check(R > fog && up > R,
                  String(format: "item 71: at view 16 a train is made %.0f blocks from him (the fog ends %.0f out) and an arrival is put %.0f up the line", R, fog, up))
        } else { check(false, "P508 arrival: no train could be put on the line") }
        // (the military arrival wants him in a town: the one nearest the line, when the station isn't one)
        if !TrainArrivals.inTown(g, g.player.pos), let sc = g.world.gen.structures {
            for (k, c) in l.cells.enumerated() where k % 8 == 0 {
                guard let v = sc.nearest("village", x: c.x, z: c.z, maxRegions: 1), abs(v.anchor.x - c.x) < 70 && abs(v.anchor.z - c.z) < 70 else { continue }
                g.player.pos = V3(Float(v.anchor.x) + 0.5, Float(v.anchor.y) + 1, Float(v.anchor.z) + 0.5)
                _ = world.loadSync(center: g.player.pos, radius: 4)
                break
            }
        }
        if !TrainArrivals.inTown(g, g.player.pos) { check(false, "P508 military arrival: no town on the line to stand in") }
        else if let mtr = TrainArrivals.arrive(g, [t], kind: .troop) {
            Trains.build(g, mtr)
            let gun = mtr.cars.first { $0.variant == Trains.gunCar }
            if let gun {
                // (the train brought up beside him: the shelling needs its engine within reach)
                for c in mtr.cars { c.pos = g.player.pos + (c.pos - (Trains.lead(mtr)?.pos ?? c.pos)) + V3(12, 0, 0) }
                let s0 = TrainArrivals.shells
                for k in 0..<12 { g.clock += 1; TrainArrivals.wreck(g, mtr, gun: gun, muzzle: gun.pos + V3(0, 3.45, 0)); _ = k }
                check(mtr.kind == .troop && mtr.roused && TrainArrivals.shells - s0 >= 3 && mtr.heldBy,
                      "P508 military arrival: a troop train in \(Townsfolk.town(g, at: g.player.pos)) halts (\(mtr.heldBy)) and shells the town (\(TrainArrivals.shells - s0) shells in 12 s)")
            } else { check(false, "P508 military arrival: no guard car") }
            TrainArrivals.kinds.removeAll(); TrainArrivals.wreckers.removeAll()
        } else { check(false, "P508 military arrival: no train could be put on the line") }
        // P510: a troop train taken from inside: aboard a troop car its soldiers stay in their compartments (none pile
        // out); the engine is refused while one still rides it; with them down he takes the engine, its guard car's gun
        // no longer fires on him, and he works that gun: a shell each time he fires it.
        Trains.trains.removeAll()
        if let mtr = TrainArrivals.arrive(g, [t], kind: .troop) {
            Trains.build(g, mtr)
            TrainArrivals.kinds.removeAll(); TrainArrivals.wreckers.removeAll()
            let car = mtr.cars.first { $0.variant == Trains.troopCar }, loco = mtr.cars.first { $0.variant == Trains.armouredLoco }
            let gun = mtr.cars.first { $0.variant == Trains.gunCar }
            if let car, let loco, let gun {
                g.survival = true; g.alive = true; g.health = 20
                let troops0 = MilitaryTrain.holding(mtr).count
                let boardedIn = Trains.use(g, car) && g.riding === car
                mtr.blocksPerSec = 0                                           // (stood still: on foot they'd pile out)
                for _ in 0..<3 { Trains.troopTick(g, mtr) }
                let stayed = MilitaryTrain.holding(mtr).count == troops0 && troops0 >= 4
                _ = Trains.use(g, loco)
                let refused = g.riding !== loco && !mtr.taken
                for m in mtr.troops { m.health = 0 }
                _ = Trains.use(g, loco)
                let took = mtr.taken && g.riding === loco
                let s0 = TrainGun.shared.shots, slugs0 = g.arms.slugs.count
                _ = Trains.use(g, gun)
                let manned = TrainGun.shared.car === gun && g.riding == nil
                TrainGun.shared.reload = 0
                TrainGun.shared.shoot(g, gun)
                let fired = TrainGun.shared.shots == s0 + 1 && g.arms.slugs.count > slugs0 && g.arms.slugs.last?.kind == .shell
                mtr.gunCool = 0; mtr.roused = true
                let gunSlugs = g.arms.slugs.count
                Trains.gunCar(g, mtr, 1.0 / 60)
                let quiet = g.arms.slugs.count == gunSlugs
                TrainGun.shared.leave(g)
                check(boardedIn && stayed && refused && took && manned && fired && quiet,
                      "P510 military train: aboard a troop car (\(boardedIn)) its \(troops0) soldiers stay in their places (\(stayed)); the engine is refused while they hold it (\(refused)); "
                      + "with them down he takes it (\(took)), its guard car's gun goes quiet on him (\(quiet)) and he works it (\(manned)), a shell a shot (\(fired))")
            } else { check(false, "P510 military train: no troop car, engine or guard car (\(mtr.cars.map { $0.variant }))") }
        } else { check(false, "P510 military train: no train could be put on the line") }
        Trains.trains.removeAll()
    }

    // P510 (Nov 1: "The train should never end... Goes on forever", "Why does the railroad stop here?", "It can't stop"):
    // lines run on by links to the next line along the row; the planned links join their lines end to end, a step at a
    // time, at their heights; the drawn line's end has rail on past it, no buffers; and a train he rides runs off its
    // line's end onto the link and on, never turning back at the last station.
    static func through(_ g0: Game, check: (Bool, String) -> Void) {
        let loops0 = Railways.loopsOn
        Railways.loopsOn = false
        defer { Railways.loopsOn = loops0 }
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        var lines = 0, linked = 0, bad: [String] = []
        var pick: (UInt64, Railways.Line, Railways.Line, Railways.Line)?
        let t0 = CFAbsoluteTimeGetCurrent()
        // (why a line has no link: tallied while the links are planned)
        var why: [String: Int] = [:]
        let whyLock = NSLock()
        let tally0 = Railways.tally
        Railways.tally = { k in whyLock.lock(); why[k, default: 0] += 1; whyLock.unlock() }
        defer { Railways.tally = tally0 }
        for k in 0..<12 {
            let seed = UInt64(1000 + k * 7919)
            let gen = WorldGen(seed: seed)
            gen.fieldWorld = true
            for l in Railways.near(gen, x0: -6000, z0: -6000, x1: 6000, z1: 6000, pad: 0) {
                lines += 1
                let (row, st) = Railways.rowStretch(l.id)
                guard let lk = Railways.link(gen, row: row, stretch: st), let b = Railways.linkTarget(gen, lk) else { continue }
                linked += 1
                // Joined end to end: a's last cell, the link's cells, b's first, each a step on from the one before, the
                // planned heights within a grade's step across both joins.
                let chain = [l.cells.last!] + lk.cells + [b.cells.first!]
                for i in 1..<chain.count where abs(chain[i].x - chain[i - 1].x) + abs(chain[i].z - chain[i - 1].z) != 1 {
                    bad.append("seed \(seed) \(lk.name): step \(i) not adjacent"); break
                }
                if abs(chain[1].x - chain[0].x) + abs(chain[1].z - chain[0].z) != 1, let a = Railways.line(gen, row: row, stretch: st) {
                    print("rail links: seed \(seed) row \(row) stretch \(st): the line's east end \(l.cells.last!) (\(l.cells.count) cells), the link from \(lk.cells.first!), "
                          + "the line asked again ends \(a.cells.last!) (\(a.cells.count) cells), the next line starts \(b.cells.first!)")
                }
                if let ha = l.heights, let hl = lk.heights, let hb = b.heights {
                    let hs = [ha.last!] + hl + [hb.first!]
                    for i in 1..<hs.count where abs(hs[i] - hs[i - 1]) > Railways.grade + 0.02 {
                        bad.append(String(format: "seed %llu %@: height jumps %.2f at %d", seed, lk.name, hs[i] - hs[i - 1], i)); break
                    }
                }
                if pick == nil || lk.cells.count < pick!.2.cells.count { pick = (seed, l, lk, b) }
            }
        }
        whyLock.lock()
        let whyText = why.filter { $0.key.hasPrefix("link") && !$0.key.hasPrefix("link route detail") }.sorted { $0.value > $1.value }.prefix(12).map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        for d in why.keys.filter({ $0.hasPrefix("link route detail") }).sorted().prefix(16) { print("rail links: " + d) }
        whyLock.unlock()
        print(String(format: "rail links: %d of %d lines run on to the next (%.1f s); no link: ", linked, lines, CFAbsoluteTimeGetCurrent() - t0) + whyText)
        // (Nov 4: this asked a third of the lines to link, and failed from build 62 on: links seldom fit (the next line is
        // over the sea or past a town, thousands of blocks on), and P511 made an end with no link turn in a loop
        // instead, so the train never stops either way; the P511 loops check counts every end (239 of 256 run on). Here:
        // some lines link, and every link that is laid joins its lines end to end.)
        check(linked > 0 && bad.isEmpty,
              "P510 links: \(linked) of \(lines) lines run on by a link to the next line along the row (the rest turn in P511's loops), joined end to end" + (bad.isEmpty ? "" : ": " + bad.prefix(3).joined(separator: "; ")))
        guard let (seed, l, lk, b) = pick else { check(false, "P510 through: no linked line to ride"); return }
        let world = World(seed: seed, device: g0.world.device, save: nil)
        world.makeFieldWorld()
        world.renderDistance = 3; world.activeDistance = 3
        let g = Game(world: world, save: nil, persistent: false)
        g.paused = false; g.survival = false
        // Drawn: the line's east end has rail on past it into the link, no buffer stop.
        let e = l.cells.last!
        _ = world.loadSync(center: V3(Float(e.x), Float(e.y), Float(e.z)), radius: 2)
        let on = (1...6).filter { Rails.isRail(world.block(lk.cells[$0].x, lk.cells[$0].y, lk.cells[$0].z)) }.count
        let buffer = world.block(e.x + 1, e.y, e.z) == Blocks.id("stone_bricks") || world.block(e.x + 1, e.y + 1, e.z) == Blocks.id("red_wool")
        check(on == 6 && !buffer, "P510 links: past \(l.name)'s east end the rails run on (\(on) of 6 drawn), no buffer stop (\(buffer))")
        // Ridden: from the last station but one, the train runs past the line's last station and on along the link.
        let t = Trains.track(l)
        let k0 = l.stations.count - 2
        let st0 = l.stations[k0]
        let c0 = l.cells[st0.index]
        g.player.pos = V3(Float(c0.x) + 0.5, Float(c0.y), Float(c0.z - 2) + 0.5)
        _ = world.loadSync(center: g.player.pos, radius: 3)
        Trains.trains.removeAll(); Trains.throughOut.removeAll()
        var at = g.time
        for k in 0..<Int(t.period * 4) { let a = t.at(g.time + Double(k) * 0.25); if a.stop == k0 && a.dir > 0 { at = g.time + Double(k) * 0.25 + 1; break } }
        g.time = at
        Trains.forceKind = .passenger
        defer { Trains.forceKind = nil }
        Trains.tick(g)
        guard let tr = Trains.trains[t.id], let lead = tr.cars.first(where: { Trains.isEngine($0) }) ?? tr.cars.first else { check(false, "P510 through: no train at \(st0.name)"); return }
        _ = Trains.use(g, lead)
        let splices0 = Trains.splices
        let dt: Float = 1.0 / 60
        var frames = 0, lastLoad = g.time, unseated = 0, turned = false
        let endX = Float(e.x)
        var maxX = g.player.pos.x
        while frames < 60 * 600 && maxX < endX + 80 {
            if g.time - lastLoad > 1.5 { _ = world.loadSync(center: g.player.pos, radius: 3); lastLoad = g.time }
            tr.throttle = 2
            g.tick(Double(dt))
            frames += 1
            if g.riding == nil || !(tr.cars.contains { $0 === g.riding! }) { unseated += 1; if unseated > 3 { break }; if let c = tr.cars.first { _ = Trains.use(g, c) } }
            if g.player.pos.x < maxX - 30 { turned = true; break }
            maxX = max(maxX, g.player.pos.x)
        }
        check(maxX >= endX + 80 && !turned && unseated == 0 && Trains.splices > splices0 && tr.track.through,
              String(format: "P510 through: riding %@ from %@, the train ran past its last station and %.0f blocks on along the link toward %@ (%d splices, turned back %@, unseated %d, %.0f s)",
                     l.name, st0.name, maxX - endX, b.name, Trains.splices - splices0, turned ? "yes" : "no", unseated, Float(frames) * dt))
        g.dismount()
        Trains.trains.removeAll(); Trains.throughOut.removeAll()
    }
}
