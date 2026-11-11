import Foundation
import simd

// Checks for people in the Capital's cities (CapitalTown.swift), run with the town checks (questcheck on the host,
// Mac `--towntests`):
//   plans:  three generated city plans each hold all eight shops on four market lots round the civic centre, flats
//           and offices, and every flat's residents get an office desk.
//   city:   one city generated for real: eight keepers (one per kind) behind counters, a sign per shop, the city's
//           name at the fountain, a bell, citizens with desks, a bed for every keeper and citizen, everyone and every
//           desk on a floor with head room.
//   day:    that city through Game.tick: citizens reach their desks in work hours, then citizens and keepers reach
//           their beds at night (the routine works on the terraces, ramps and walkways, not just on paper).
extension TownTests {
    static func capitals(_ makeWorld: () -> World, _ check: (Bool, String) -> Void) {
        let w = makeWorld()
        guard let sc = w.gen.structures else { check(false, "capitals: structures"); return }
        // Plans: three cities' layouts (no chunks generated).
        var seen: [IVec3] = [], starts: [StructureStart] = []
        var planned: [String] = [], badPlans: [String] = []
        for _ in 0..<3 {
            guard let s = sc.nearest("capital_city", x: 0, z: 0, maxRegions: 12, accept: { st in !seen.contains { $0 == st.anchor } }) else { break }
            seen.append(s.anchor); starts.append(s)
            guard let p = plan(s) else { badPlans.append("no plan at \(s.anchor.x) \(s.anchor.z)"); continue }
            let shops = p.shops.flatMap { $0 }
            let markets = p.kind.filter { $0 == 4 }.count
            var flats = 0, offices = 0, homeless = 0
            for j in -CapitalCity.N..<CapitalCity.N { for i in -CapitalCity.N..<CapitalCity.N where p.has(i, j) && p.kind[p.idx(i, j)] == 0 {
                if CapitalTown.isResidence(p, i, j) {
                    flats += 1
                    if CapitalTown.desk(p, i, j, 0) == nil { homeless += 1 }
                } else { offices += 1 }
            } }
            planned.append("\(markets) markets \(flats) flats \(offices) offices")
            if Set(shops).count != ShopKind.allCases.count || shops.count != 8 || markets != 4 { badPlans.append("shops \(shops.map { $0.rawValue })") }
            if flats == 0 || offices == 0 { badPlans.append("\(flats) flats \(offices) offices") }
            if homeless > flats / 3 { badPlans.append("\(homeless)/\(flats) flats have no office within two lots") }
        }
        check(seen.count >= 2 && badPlans.isEmpty, "capitals: \(seen.count) city plans hold all 8 shops on 4 market lots, flats and offices (\(planned.joined(separator: "; ")))"
              + (badPlans.isEmpty ? "" : " FAILED: " + badPlans.joined(separator: ", ")))
        guard let s = starts.first, let p = plan(s) else { return }

        // City: the nearest one generated.
        let centre = V3(Float(p.ox + CapitalCity.N * CapitalCity.lot), Float(s.anchor.y), Float(p.oz + CapitalCity.N * CapitalCity.lot))
        w.renderDistance = 8
        w.pendingMobs.removeAll()
        _ = w.loadSync(center: centre, radius: 7)
        // P510 (Nov 1 20:23:00, "Should be one Ember Charge somewhere in the capital"): the city holds one.
        let chargeItem = Items.id(HellGate.chargeKey)
        let charges = w.blockEntities.filter { abs($0.key.x - Int(centre.x)) < 120 && abs($0.key.z - Int(centre.z)) < 120 }
            .reduce(0) { $0 + $1.value.container.countOf(chargeItem) }
        check(charges == 1, "capitals: the city holds one Ember Charge (\(charges)), in the officer's strongbox by the fountain")
        var keepers: [ShopKind: Int] = [:], citizens = 0, desks = 0, blocked: [String] = []
        func room(_ q: V3) -> Bool {
            !w.collides(q + V3(-0.3, 0.01, -0.3), q + V3(0.3, 1.95, 0.3)) && w.collides(q + V3(-0.3, -0.2, -0.3), q + V3(0.3, -0.01, 0.3))
        }
        for (name, q) in w.pendingMobs where name.hasPrefix("villager") {
            if !room(q) { blocked.append("\(name.prefix(24)) at \(Int(q.x)) \(Int(q.y)) \(Int(q.z))") }
            if name.hasPrefix("villager:shop_"), let k = ShopKind(rawValue: String(name.dropFirst(14))) { keepers[k, default: 0] += 1 }
            if name.hasPrefix("villager:citizen") {
                citizens += 1
                if let at = name.split(separator: "@").dropFirst().first {
                    let c = at.split(separator: ",").compactMap { Int($0) }
                    if c.count == 3 {
                        desks += 1
                        let d = V3(Float(c[0]) + 0.5, Float(c[1]), Float(c[2]) + 0.5)
                        if !room(d) { blocked.append("desk at \(c[0]) \(c[1]) \(c[2])") }
                    }
                }
            }
        }
        var signs = 0, welcome = "", bells = 0, beds = 0
        let r = CapitalCity.N * CapitalCity.lot + 8
        for (q, be) in w.blockEntities where be.kind == .sign && abs(q.x - Int(centre.x)) < r && abs(q.z - Int(centre.z)) < r {
            // A sign counts when its block is still a sign (a later fill could have replaced it, leaving the text).
            if ShopKind.allCases.contains(where: { be.lines.contains($0.name) }) && Blocks.key(Blocks.groupBase[Int(w.materialAt(q.x, q.y, q.z))]).hasSuffix("_sign") { signs += 1 }
            else if ShopKind.allCases.contains(where: { be.lines.contains($0.name) }) { print("  sign entity without a sign block at \(q.x) \(q.y) \(q.z): \(Blocks.key(w.materialAt(q.x, q.y, q.z)))") }
            if be.lines.first == "Welcome to" { welcome = be.lines[1] }
        }
        if ProcessInfo.processInfo.environment["CAPITAL_DEBUG"] != nil, let (_, kp) = w.pendingMobs.first(where: { $0.0 == "villager:shop_general" }) {
            // The general store's front, rows from the roof down (v -1 then v 0), u across.
            let sx = Int(floor(kp.x)) - CapitalTown.storeW / 2, sz = Int(floor(kp.z)) - (CapitalTown.storeD - 3), y0 = Int(floor(kp.y))
            for v in [-1, 0] { for dy in stride(from: 6, through: 0, by: -1) {
                print("  front v\(v) dy\(dy): " + (-1...CapitalTown.storeW).map { u in
                    let k = Blocks.key(w.materialAt(sx + u, y0 + dy, sz + v)); return String((k == "air" ? "." : k).prefix(6)).padding(toLength: 7, withPad: " ", startingAt: 0)
                }.joined())
            } }
        }
        let bell = Blocks.id("bell")
        w.forEachBlock(around: IVec3(Int(centre.x), Int(centre.y), Int(centre.z)), r: r, ry: 24) { b, _, _, _ in
            if b == bell { bells += 1 }
            if VillageLife.isBedHead(b) { beds += 1 }
        }
        check(keepers.count == 8 && keepers.values.allSatisfy { $0 == 1 } && signs >= 8,
              "capitals: the city holds one keeper of each of the 8 shops (\(keepers.count) kinds) and \(signs) shop signs")
        check(!welcome.isEmpty && bells >= 1 && citizens >= 8 && desks >= citizens * 2 / 3 && beds >= citizens + 8,
              "capitals: \(welcome.isEmpty ? "no name sign" : "\"\(welcome)\""), \(bells) bells, \(citizens) citizens (\(desks) with a desk), \(beds) beds")
        if let (c, n) = CapitalCity.sampleTower { print("capitals: a tower of \(n) storeys, its stair shaft's newel at \(c.x) \(c.y) \(c.z)") }
        // P499 (Oct 30 15:10, "we need way more troops here... It should be 50"): the city's watch, each on a floor.
        let watch = w.pendingMobs.filter { $0.0.hasPrefix("soldier_") }
        let unstood = watch.filter { !room($0.1) }.count
        check(watch.count >= 40 && unstood * 10 <= watch.count,
              "capitals P499: the city keeps \(watch.count) soldiers on watch (\(unstood) without a floor and head room)")
        // P499 (Oct 30 15:10, up a tower: "each of the floors are empty"): a new city's tower floors are furnished; the
        // stair core and its doors are left as they were.
        func floorsOf(_ flat: Bool, _ fitted: Bool) -> (things: Int, core: [BlockID]) {
            var things = 0, core: [BlockID] = []
            let L = 100
            var r0 = SRng(4242)
            let fp = CapitalCity.footprint(0, 0, &r0)
            let plan = CapitalCity.Plan(ox: -200, oz: -200); plan.modern = true; plan.seed = 7
            let keys = ["chair", "bed", "bookshelf", "barrel", "lantern", "flower_pot", "chest", "birch_planks", "capital_stone_trim"]
            for cz in -1...3 { for cx in -1...3 {
                var buf = [BlockID](repeating: AIR, count: CS * CS * CH)
                buf.withUnsafeMutableBufferPointer { b in
                    var w = StructWriter(bx: cx * CS, bz: cz * CS, blocks: b.baseAddress!)
                    var rng = r0
                    CapitalCity.tower(&w, fp, L, &rng, home: flat ? (plan, 0, 0) : nil, fitted: fitted)
                }
                for lz in 0..<CS { for lx in 0..<CS {
                    let x = cx * CS + lx, z = cz * CS + lz
                    guard x > fp.bx0 && x < fp.bx0 + fp.bw - 1 && z > fp.bz0 && z < fp.bz0 + fp.bd - 1 else { continue }
                    let inCore = x >= fp.bx0 + fp.bw - 1 - 7 && z <= fp.bz0 + 5
                    for y in (L + 6)..<min(CH, L + 60) {
                        let b = buf[Chunk.index(lx, y, lz)]
                        if inCore { core.append(b); continue }
                        if b != AIR, (y - L) % 5 != 0, keys.contains(where: { Blocks.key(Blocks.groupBase[Int(b)]).contains($0) }) { things += 1 }
                    }
                } }
            } }
            return (things, core)
        }
        let office = floorsOf(false, true), officeOld = floorsOf(false, false), flats = floorsOf(true, true), flatsOld = floorsOf(true, false)
        check(office.things >= officeOld.things + 20 && flats.things >= 12 && flatsOld.things == 0
              && office.core == officeOld.core && flats.core == flatsOld.core,
              "capitals P499: a new tower's upper floors are furnished (offices \(office.things) things, was \(officeOld.things); flats \(flats.things), was \(flatsOld.things)); the stair core unchanged (\(office.core == officeOld.core && flats.core == flatsOld.core))")
        check(blocked.isEmpty, "capitals: every keeper, citizen and desk has a floor and head room" + (blocked.isEmpty ? "" : ": " + blocked.prefix(6).joined(separator: ", ")))
        day(w, centre, check)
    }

    static func plan(_ s: StructureStart) -> CapitalCity.Plan? { s.plan as? CapitalCity.Plan }

    // A city day through Game.tick: work hours, then night.
    static func day(_ w: World, _ centre: V3, _ check: (Bool, String) -> Void) {
        let wasDet = Rand.deterministic
        Rand.seed(12345)
        defer { Rand.deterministic = wasDet }
        let g = Game(world: w, save: nil, persistent: false)
        g.survival = false
        g.paused = false
        g.menu = nil
        g.player.flying = true
        g.time = 0.04 * DAY_LENGTH
        for (name, q) in w.pendingMobs { if let m = Mob.structureMob(name, at: q) { g.mobs.mobs.append(m) } }
        w.pendingMobs.removeAll()
        let people = g.mobs.mobs.filter { $0.kind == .villager }
        let t0 = CFAbsoluteTimeGetCurrent()
        func run(_ seconds: Double, _ each: () -> Void) {
            for i in 0..<Int(seconds / 0.05) {
                g.player.vel = .zero
                g.player.pos = centre + V3(0, 60, 0)        // out of the way, every lot within range
                g.tick(0.05)
                if i % 20 == 0 { each() }
            }
        }
        run(10) {}                                          // settle: identities, beds claimed
        // Work hours: each citizen's closest approach to their desk.
        g.time = (2050.0 / 24000) * DAY_LENGTH
        let workers = people.filter { $0.villager?.role == "citizen" && $0.villager?.jobSite != nil }
        var bestDesk = [Float](repeating: .infinity, count: workers.count)
        // Keepers in shop hours: how often one stands higher than their spot behind the counter (on the counter).
        let keepers = people.filter { $0.villager?.role == "shopkeeper" }
        var keeperSamples = 0, onCounter = 0
        run(180) {
            for (i, m) in workers.enumerated() {
                guard let j = m.villager?.jobSite else { continue }
                // At the desk: close, on its floor, and in the same room (a clear line, not through the office wall).
                let spot = V3(Float(j[0]) + 0.5, Float(j[1]), Float(j[2]) + 0.5)
                let d = simd_length(V2(spot.x - m.pos.x, spot.z - m.pos.z))
                if abs(spot.y - m.pos.y) < 0.6 && d < 3 && w.clearShot(m.pos + V3(0, 1.5, 0), spot + V3(0, 1.5, 0)) { bestDesk[i] = min(bestDesk[i], d) }
            }
            for m in keepers where m.villager?.shopKind != nil {
                guard let j = m.villager?.jobSite else { continue }
                keeperSamples += 1
                if m.pos.y > Float(j[1]) + 0.7 {
                    onCounter += 1
                    if ProcessInfo.processInfo.environment["CAPITAL_DEBUG"] != nil && onCounter % 7 == 1 {
                        print("  up: \(m.villager?.shop ?? "") at \(m.pos) spot \(j) on \(Blocks.key(w.materialAt(Int(floor(m.pos.x)), Int(floor(m.pos.y - 0.6)), Int(floor(m.pos.z))))) ground \(m.onGround) t \(Int(g.dayFraction * 24000)) goal \(m.path.goal) nodes \(m.path.nodes.dropFirst(m.path.index).prefix(4).map { "\($0.x),\($0.y),\($0.z)" }) partial \(m.path.partial) near \(g.mobs.mobs.filter { $0 !== m && simd_length($0.pos - m.pos) < 1.5 }.map { "\($0.villager?.role ?? "?")@\($0.pos)" })")
                        for y in j[1] - 1...j[1] + 1 { for z in j[2] - 3...j[2] + 3 {
                            print("   y\(y) z\(z): " + (j[0] - 3...j[0] + 3).map { String(Blocks.key(w.materialAt($0, y, z)).prefix(6)).padding(toLength: 7, withPad: " ", startingAt: 0) }.joined()) } }
                    }
                }
            }
        }
        // Lunch at the saloon (5600-6600): the diners stand on the customers' side, not round the barkeep (verifier: a
        // stool in front of the bar sent them behind it), and the barkeep stays off the bar.
        g.time = (5650.0 / 24000) * DAY_LENGTH
        let barkeep = keepers.first { $0.villager?.shop == ShopKind.saloon.rawValue }
        var behindBar = 0, lunchSamples = 0
        run(45) {
            guard let b = barkeep, let j = b.villager?.jobSite else { return }
            let spot = V3(Float(j[0]) + 0.5, Float(j[1]), Float(j[2]) + 0.5)
            for m in workers { lunchSamples += 1; if simd_length(m.pos - spot) < 1.6 { behindBar += 1 } }
            keeperSamples += 1
            if b.pos.y > Float(j[1]) + 0.7 { onCounter += 1 }
        }
        check(lunchSamples > 0 && behindBar * 50 <= lunchSamples,
              "capitals: lunch guests stay out from behind the bar (\(behindBar) of \(lunchSamples) samples beside the barkeep)")
        check(keeperSamples > 0 && onCounter * 50 <= keeperSamples,
              "capitals: keepers stay off their counters in shop hours (\(onCounter) of \(keeperSamples) samples up on something)")
        if ProcessInfo.processInfo.environment["CAPITAL_DEBUG"] != nil {
            for (i, m) in workers.enumerated() where bestDesk[i] >= 3 {
                print("  late \(m.villager?.person ?? "?") at \(m.pos) home \(m.home ?? .zero) desk \(m.villager?.jobSite ?? []) path \(m.path.nodes.count) idx \(m.path.index) partial \(m.path.partial) goal \(m.path.goal) gaveUp \(m.unreachableTimer) act \(m.activity(g.dayFraction))")
            }
        }
        let atWork = bestDesk.filter { $0 < 3 }.count
        let late = zip(workers, bestDesk).filter { $0.1 >= 3 }.prefix(4).map { m, d in
            "\(m.villager?.person ?? "?") \(d.isFinite ? String(format: "%.0f", d) : "never level") from desk"
        }
        check(!workers.isEmpty && atWork * 10 >= workers.count * 9,
              "capitals: \(atWork)/\(workers.count) citizens reach their office desks in work hours" + (late.isEmpty ? "" : " (\(late.joined(separator: ", ")))"))
        // Night: citizens and keepers in bed.
        g.time = 0.67 * DAY_LENGTH
        // (The barkeep minds the saloon all night: P456, "the saloon should always be open". The check counted him
        // from when the saloon shut at 0.66, so he stood awake in every run and left the rest a margin of two.)
        let sleepers = people.filter { ["citizen", "shopkeeper"].contains($0.villager?.role ?? "") && $0.villager?.shop != ShopKind.saloon.rawValue }
        var slept = Set<ObjectIdentifier>()
        // CAPITAL_DEBUG: each sleeper's way to bed, a line a second (printed for those who never lie down).
        let traceNight = ProcessInfo.processInfo.environment["CAPITAL_DEBUG"] != nil
        var nightLog: [ObjectIdentifier: [String]] = [:]
        var stuckDump: [ObjectIdentifier: String] = [:]
        var second = 0
        run(150) {
            for m in sleepers where m.lying { slept.insert(ObjectIdentifier(m)) }
            if traceNight {
                // The first time each one stands stalled on its path: the blocks round its next cell and a test step.
                for m in sleepers where !slept.contains(ObjectIdentifier(m)) && stuckDump[ObjectIdentifier(m)] == nil
                    && m.path.stallTime > 3 && m.path.index < m.path.nodes.count {
                    let n = m.path.nodes[m.path.index]
                    var d = String(format: "    stalled at %.3f %.3f %.3f (on the ground %@) for the cell %d,%d,%d\n", m.pos.x, m.pos.y, m.pos.z, m.onGround ? "yes" : "no", n.x, n.y, n.z)
                    for y in (n.y - 1)...(n.y + 2) { for z in (n.z - 1)...(n.z + 1) { for x in (n.x - 1)...(n.x + 1) {
                        let b = w.block(x, y, z)
                        var bx: [(V3, V3)] = []; w.collisionBoxes(x, y, z, &bx)
                        guard !bx.isEmpty || Blocks.key(b) != "air" || w.groundAt(x, y, z) else { continue }
                        d += "      \(x),\(y),\(z) \(Blocks.def(b).name)\(w.groundAt(x, y, z) ? " (ground)" : "") boxes " + bx.map { String(format: "[%.2f %.2f %.2f - %.2f %.2f %.2f]", $0.0.x, $0.0.y, $0.0.z, $0.1.x, $0.1.y, $0.1.z) }.joined(separator: " ") + "\n"
                    } } }
                    let to = V3(Float(n.x) + 0.5, m.pos.y, Float(n.z) + 0.5) - m.pos
                    let dir = simd_length(V2(to.x, to.z)) > 0.01 ? simd_normalize(V3(to.x, 0, to.z)) : V3(0, 0, -1)
                    var p0 = m.pos
                    let hit = w.moveBody(&p0, halfW: m.halfW, height: m.height, dir * 0.08, step: 0.6, onGround: true)
                    let lo = V3(m.pos.x - m.halfW, m.pos.y, m.pos.z - m.halfW), hi = V3(m.pos.x + m.halfW, m.pos.y + m.height, m.pos.z + m.halfW)
                    d += String(format: "      a test step of 0.08 toward it: moved %.3f %.3f %.3f (blocked x %@ y %@ z %@); room to rise %.3f, to fall %.3f",
                                p0.x - m.pos.x, p0.y - m.pos.y, p0.z - m.pos.z, hit.x ? "y" : "n", hit.y ? "y" : "n", hit.z ? "y" : "n",
                                w.sweep(lo, hi, axis: 1, 0.6), w.sweep(lo, hi, axis: 1, -0.6))
                    stuckDump[ObjectIdentifier(m)] = d
                }
                for m in sleepers where !slept.contains(ObjectIdentifier(m)) {
                    let f = m.path.nodes.first.map { "\($0.x),\($0.y),\($0.z)" } ?? "-", l = m.path.nodes.last.map { "\($0.x),\($0.y),\($0.z)" } ?? "-"
                    nightLog[ObjectIdentifier(m), default: []].append(String(format: "%3ds at %.1f %.1f %.1f yaw %.0f moving %@ path %d/%d %@..%@ partial %@ goal %.1f %.1f %.1f search %@ unreach %.1f stall %.1f",
                        second, m.pos.x, m.pos.y, m.pos.z, m.yaw * 180 / .pi, m.moving ? "y" : "n", m.path.index, m.path.nodes.count, f, l,
                        m.path.partial ? "y" : "n", m.path.goal.x, m.path.goal.y, m.path.goal.z, m.path.search == nil ? "n" : "y", m.unreachableTimer, m.path.stallTime))
                }
            }
            second += 1
        }
        if traceNight {
            for m in sleepers where !slept.contains(ObjectIdentifier(m)) {
                print("  night of \(m.villager?.person ?? "?"):"); for l in nightLog[ObjectIdentifier(m)] ?? [] { print("    " + l) }
                if let d = stuckDump[ObjectIdentifier(m)] { print(d) }
            }
        }
        let noBed = sleepers.filter { $0.villager?.bed == nil }.count
        let awake = sleepers.filter { !slept.contains(ObjectIdentifier($0)) }.prefix(4).map { m -> String in
            let b = m.villager?.bed.map { String(format: "%.0f", simd_length(V3(Float($0[0]) + 0.5, Float($0[1]), Float($0[2]) + 0.5) - m.pos)) } ?? "no"
            return "\(m.villager?.person ?? "?") (\(m.villager?.role ?? "?"), \(b) bed)"
        }
        if ProcessInfo.processInfo.environment["CAPITAL_DEBUG"] != nil {
            for m in sleepers where !slept.contains(ObjectIdentifier(m)) {
                let cx = Int(floor(m.pos.x)), cy = Int(floor(m.pos.y)), cz = Int(floor(m.pos.z))
                for dy in -1...2 {
                    print("    y\(cy + dy) (rows z \(cz - 2)...\(cz + 2), x \(cx - 3)...\(cx + 3)): " + (-2...2).map { dz in (-3...3).map { dx -> String in
                        let k = Blocks.key(w.materialAt(cx + dx, cy + dy, cz + dz))
                        return k == "air" ? "." : (k.contains("slab") ? "s" : (k.contains("stairs") ? "t" : (k.contains("fence") ? "f" : String(k.prefix(1)))))
                    }.joined() }.joined(separator: " | "))
                }
                print("    next " + m.path.nodes.dropFirst(m.path.index).prefix(4).map { "\($0.x),\($0.y),\($0.z)" }.joined(separator: " "))
                print("  awake \(m.villager?.person ?? "?") \(m.villager?.role ?? "") \(m.villager?.shop ?? "") at \(m.pos) bed \(m.villager?.bed ?? []) path \(m.path.nodes.count) idx \(m.path.index) partial \(m.path.partial) gaveUp \(m.unreachableTimer)")
                if let b = m.villager?.bed {
                    let goal = V3(Float(b[0]) + 0.5, Float(b[1]), Float(b[2]) + 0.5)
                    for n in [1500, 8000] {
                        let r = PathFinder.find(w, from: m.pos, to: goal, profile: m.pathProfile(g), maxNodes: n)
                        let end = r?.last.map { "\($0.x),\($0.y),\($0.z)" } ?? "none"
                        print("    a path to the bed within \(n) cells: \(r?.count ?? -1) steps, ending \(end)")
                    }
                }
                print("    foe \(m.town.foe.map { "\($0.kind)" } ?? "none") anger \(m.town.anger) handsUp \(m.town.handsUp) out \(m.town.out) brawl \(m.town.brawl) active \(w.activeHere(m.pos)) hurt \(m.hurt) panic \(m.panic)")
            }
            // Tick by tick: whether each one lies down and what gets them up again.
            let watch = sleepers.filter { !slept.contains(ObjectIdentifier($0)) }
            for i in 0..<12 where !watch.isEmpty {
                g.player.vel = .zero; g.player.pos = centre + V3(0, 60, 0)
                g.tick(0.05)
                print("    tick \(i): " + watch.map { m in String(format: "%@ lying %@ y %.3f z %.3f", m.villager?.person ?? "?", m.lying ? "yes" : "no", m.pos.y, m.pos.z) }.joined(separator: " | "))
            }
        }
        check(!sleepers.isEmpty && slept.count * 10 >= sleepers.count * 9 && noBed * 10 <= sleepers.count,
              "capitals: \(slept.count)/\(sleepers.count) citizens and keepers asleep in bed at night (\(noBed) without a bed)" + (awake.isEmpty ? "" : "; awake: " + awake.joined(separator: ", ")))
        print(String(format: "capitals: city day sim %.1f s for %d people", CFAbsoluteTimeGetCurrent() - t0, people.count))
    }
}
