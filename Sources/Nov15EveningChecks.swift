import Foundation
import simd

// Fable's set from the Nov 15 evening playtest (docs/playtests/2026-11-15/voice-notes.md, build 39e0d988): the checks
// for ledger rows 190 on. The map pin's checks are in PlaytestOct12Tests.mapClickPin (beside the P73 ones) and the
// laser press's in the suite (quest/src/headless/main.swift, PullAim).
enum Nov15EveningChecks {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        attachPin(g, check)
        shipChair(g, check)
        fittings(check)
        buildsTogether(g, check)
        buildsOwnGround(g, check)
        provingOrder(check)
        ghostTowns(g, check)
        hullLeaves(g, check)
    }

    // Ledger 210 (the host check ledger 197 lacked): leaves standing in a craft's cell, where the cell's own block (a
    // slab) leaves room. Aimed through the slab's empty half at the leaves, a break press goes to the world's leaves
    // with the fix, and to the hull block behind them without it (BS_OLDHULLLEAVES=1). Both ways are run here.
    static func hullLeaves(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let p0 = g.player.pos, yaw0 = g.player.yaw, pitch0 = g.player.pitch, held0 = g.inventory.held, aim0 = g.vrAim
        let lx = Int(floor(p0.x)) + 3, lz = Int(floor(p0.z)) - 6
        let ly = min(CH - 8, w.topY(lx, lz) + 12)
        let leaves = Blocks.id("spruce_leaves"), was = w.block(lx, ly, lz)
        w.setBlock(lx, ly, lz, leaves)
        // The craft: two cells north to south, a slab (bottom half) in the leaves' cell, planks behind it, on the grid.
        let gr = ShipGrid(sx: 1, sy: 1, sz: 2)
        gr.set(0, 0, 1, Blocks.id("oak_slab")); gr.set(0, 0, 0, Blocks.id("oak_planks"))
        let s = Ship(id: -210, grid: gr)
        s.rebuild()
        s.pos = V3(Float(lx), Float(ly), Float(lz - 1)) + s.com
        s.updateBounds()
        w.ships.add(s)
        let old0 = Game.oldHullLeaves
        defer {
            Game.oldHullLeaves = old0
            w.ships.remove(s, turrets: false)
            w.setBlock(lx, ly, lz, was)
            g.player.pos = p0; g.player.yaw = yaw0; g.player.pitch = pitch0; g.player.vel = .zero
            g.inventory.held = held0; g.vrAim = aim0; g.target = nil; w.ships.target = nil
        }
        // He stands 3.5 south of the leaves, eye level with the slab's empty top half, looking north at them.
        func press(old: Bool) -> (ship: Bool, handled: Bool) {
            Game.oldHullLeaves = old
            g.vrAim = nil; g.inventory.held = .empty
            g.player.yaw = 0; g.player.pitch = 0
            g.player.pos = V3(Float(lx) + 0.5, Float(ly) + 0.75, Float(lz) + 4.5) - (g.player.eye - g.player.pos)
            g.target = (hit: IVec3(lx, ly, lz), normal: IVec3(0, 0, 1))
            w.ships.target = nil
            let handled = g.shipInteract(breakHeld: true, breakNow: true, useNow: false, sneak: false, dt: 1.0 / 72)
            return (w.ships.target?.0 === s, handled)
        }
        let after = press(old: false), before = press(old: true)        // (the fix's way first: the old press may break the hull)
        check(before.ship && before.handled && !after.ship && !after.handled,
              "Ledger 210 hull leaves: leaves in a craft's slab cell, struck through the slab's empty half: before (BS_OLDHULLLEAVES) the press went to the hull (\(before.ship ? "hull" : "world")), with ledger 197 to the leaves (\(after.ship ? "hull" : "world"))")
    }

    // Ledger 207 (21:00:20-21:00:26, "make it a normal village, but the village is abandoned... chain modify each village
    // building so it's abandoned"): ghost towns are towns' layouts (lots along streets, the towns' own buildings), each
    // building ruined by its own draw; nobody lives there, no light burns, cobwebs hang inside; no two alike.
    static func ghostTowns(_ g0: Game, _ check: (Bool, String) -> Void) {
        // A world of its own on the suite's seed: three towns thousands of blocks out loaded (and pictured) in the suite's
        // world left him there flying and its ground loaded far off for every group after.
        let w = World(seed: g0.world.seed, device: g0.world.device, save: nil)
        w.renderDistance = 4; w.activeDistance = 4
        let g = Game(world: w, save: nil, persistent: false)
        guard !GhostVillage.old, let sc = w.gen.structures else { return }
        var towns: [StructureStart] = []
        for (x, z) in [(3000, -2000), (-3000, 2500), (5000, 5000), (-5000, -5000), (2000, 6000), (-6000, 1000), (6000, -3000), (-2000, -6000),
                       (8000, 0), (0, 8000), (-8000, 0), (0, -8000)] where towns.count < 3 {
            guard let st = sc.nearest(FrontierSites.kind, x: x, z: z, maxRegions: 8, accept: { $0.kind == "ghost_town" && $0.info["lots"] != nil }),
                  !towns.contains(where: { $0 === st }) else { continue }
            towns.append(st)
        }
        var lines: [String] = [], rules = Set<Int>(), ok = !towns.isEmpty, shapes = Set<String>()
        for (i, st) in towns.enumerated() {
            let a = st.anchor, mid = V3(Float(st.min.x + st.max.x) / 2, Float(a.y), Float(st.min.z + st.max.z) / 2)
            _ = w.loadSync(center: mid, radius: 4)
            for k in 0..<5 where (st.info["rule\(k)"] ?? 0) > 0 { rules.insert(k) }
            var lights = 0, beds = 0, webs = 0, built = 0, folk = 0
            for y in (a.y - 4)...(a.y + 16) { for z in st.min.z...st.max.z { for x in st.min.x...st.max.x {
                let b = w.block(x, y, z)
                guard b != AIR else { continue }
                let k = Blocks.key(Blocks.groupBase[Int(b)])
                if GhostVillage.dead[Int(b)] { if Blocks.shape[Int(b)] == "bed" || k.hasSuffix("_bed") { beds += 1 } else { lights += 1 } }
                if b == GhostVillage.web { webs += 1 }
                if !SmoothTerrain.natural[Int(b)] { built += 1 }
            } } }
            func inBox(_ p: V3) -> Bool { p.x >= Float(st.min.x) && p.x <= Float(st.max.x + 1) && p.z >= Float(st.min.z) && p.z <= Float(st.max.z + 1) }
            folk = w.pendingMobs.filter { inBox($0.1) }.count + g.mobs.mobs.filter { inBox($0.pos) && $0.kind == .villager }.count
            let houses = st.far.filter { $0.tone != .roof }.count
            let rl = (0..<5).map { "\(st.info["rule\($0)"] ?? 0)" }.joined(separator: "/")
            lines.append("\(a.x),\(a.z): \(st.info["lots"] ?? 0) lots, \(houses) buildings (rules \(rl)), \(built) built blocks, \(webs) cobwebs, \(lights) lights, \(beds) beds, \(folk) folk")
            shapes.insert("\(built)/\(webs)")
            ok = ok && houses >= 3 && lights == 0 && beds == 0 && folk == 0 && webs > 0
            if let shot = CircuitWorkshopTests.shot {
                let eye = V3(Float(st.min.x) - 10, Float(a.y) + 22, Float(st.max.z) + 10)
                shot(g, "ghost_town_\(i)", eye, atan2f(-(mid.x - eye.x), -(mid.z - eye.z)), -0.5)
                let low = V3(mid.x + 4, Float(a.y) + 3, mid.z + 3)
                shot(g, "ghost_street_\(i)", low, atan2f(-(Float(a.x) - low.x), -(Float(a.z) - low.z)) + 0.4, -0.12)
            }
        }
        check(ok && towns.count >= 2 && rules.count >= 3 && shapes.count == towns.count,
              "Ledger 207 ghost towns: \(towns.count) laid out as towns (\(GhostVillage.laid) laid, \(GhostVillage.tooBig) layouts past the site), \(rules.count) of 5 ruin rules among them, no two alike: \(lines.joined(separator: "; "))")
    }

    // Ledger 204 (20:35-20:37, the Proving Grounds: "no vehicle circuits nor guns here... Giant flat thing"): the build
    // lays a gun and a vehicle by him within its first steps, not after the deck round him for 200 blocks.
    static func provingOrder(_ check: (Bool, String) -> Void) {
        let b = ProvingGrounds.plan(IVec3(0, ProvingGrounds.deckY, 0))
        let gun = b.kinds.firstIndex(of: "gun") ?? 9999, car = b.kinds.firstIndex(of: "vehicle") ?? 9999, circuit = b.kinds.firstIndex(of: "circuit") ?? 9999
        let decks = b.kinds.filter { $0 == "deck" }.count
        check(gun <= 8 && car <= 12 && circuit < b.steps.count / 2,
              "Ledger 204 proving order: of \(b.steps.count) steps (\(decks) deck tiles), the first gun is step \(gun), the first vehicle \(car), the first circuit \(circuit)")
    }

    // Ledger 201: a lantern hung under a top slab floats (the gate's, Nov 15 20:41); under a full block it touches.
    // Every lantern, torch and sign in the six agent builds touches what holds it (their drafts: under the floor, the
    // footing).
    static func fittings(_ check: (Bool, String) -> Void) {
        let hang = Blocks.id("lantern") + 1, top = Blocks.id("stone_brick_slab") + 1, brick = Blocks.id("stone_bricks")
        let p = IVec3(0, 0, 0)
        let underSlab = Attach.flush({ $0 == p ? hang : ($0 == IVec3(0, 1, 0) ? top : AIR) }, p)
        let underBrick = Attach.flush({ $0 == p ? hang : ($0 == IVec3(0, 1, 0) ? brick : AIR) }, p)
        var loose: [String] = [], n = 0
        for bp in BuildersGrounds.blueprints() {
            let d = bp.draft
            n += d.cells.values.filter { Attach.fitting[Int($0)] }.count
            loose += Attach.loose(Array(d.cells.keys)) { q in d.cells[q] ?? (q.y < 0 ? STONE : AIR) }.map { "\(bp.key): \($0)" }
        }
        check(!underSlab && underBrick && n >= 10 && loose.isEmpty,
              "Ledger 201 fittings: a lantern under a top slab floats (\(!underSlab)), under a brick it hangs (\(underBrick)); the six builds' \(n) lanterns, torches and signs all touch what holds them (\(loose.prefix(4).joined(separator: "; ")))")
    }

    // Ledger 202 (20:37-20:42, "where are the builds? ... put them right in front of my face when I spawn in"): in the
    // Builders' Grounds world, the six sites lie together, none touching another, and he starts facing their middle
    // with every build within 40 of him.
    static func buildsTogether(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let w = World(seed: BuildersGrounds.seed, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 4; w.activeDistance = 4
        let g = Game(world: w, save: nil, persistent: false)
        let bps = BuildersGrounds.blueprints()
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let c = BuildersGrounds.findCluster(w, centre: g.findSpawn(), kinds: bps.map { $0.ground }) else {
            check(false, "Ledger 202 builds together: no place for the six (\(BuildersGrounds.lastWhy))"); return
        }
        let secs = CFAbsoluteTimeGetCurrent() - t0
        let sites = bps.compactMap { c.sites[$0.ground] }
        var touching = 0
        for i in 0..<sites.count { for j in (i + 1)..<sites.count where abs(sites[i].x - sites[j].x) < BuildersGrounds.apart && abs(sites[i].z - sites[j].z) < BuildersGrounds.apart { touching += 1 } }
        let dists = sites.map { simd_length(SIMD2<Float>(Float($0.x) + 5 - c.spawn.x, Float($0.z) + 5 - c.spawn.z)) }
        let far = dists.max() ?? 999, close = dists.min() ?? 0
        let look = V2(-sinf(c.yaw), -cosf(c.yaw)), toMid = simd_normalize(V2(c.middle.x - c.spawn.x, c.middle.z - c.spawn.z))
        let facing = simd_dot(look, toMid) > 0.99
        check(sites.count == bps.count && touching == 0 && far <= BuildersGrounds.near && close >= 9 && facing,
              String(format: "Ledger 202 builds together: %d sites (%d on their own kind of ground: %@), %d touching, the builds %.1f to %.1f from where he starts, facing their middle %@ (found in %.1f s)",
                     sites.count, c.own.count, c.own.sorted().joined(separator: ", "), touching, close, far, facing ? "yes" : "no", secs))
        // The six as the world puts them up (BuildersWorld: every job applied, the trees round them cleared), 20 s later:
        // every block where it was put; the pictures from where he starts and from the four sides, at noon.
        var plans: [BuildersGrounds.Placement] = []
        for bp in bps { guard let st = c.sites[bp.ground] else { continue }
            _ = w.loadSync(center: V3(Float(st.x), 120, Float(st.z)), radius: 1)
            plans.append(BuildersGrounds.place(bp, on: w, at: st)) }
        let mids = plans.map { V3(Float($0.lo.x + $0.hi.x) / 2, 0, Float($0.lo.z + $0.hi.z) / 2) }
        let m = mids.reduce(V3.zero, +) / Float(max(1, mids.count))
        let reach = (mids.map { simd_length(V2($0.x - m.x, $0.z - m.z)) } + [simd_length(V2(c.spawn.x - m.x, c.spawn.z - m.z))]).max() ?? 30
        _ = w.loadSync(center: V3(m.x, 100, m.z), radius: Int(reach / Float(CS)) + 2)
        let felled = BuildersGrounds.clearTrees(w, middle: m, radius: reach + 10)
        for pl in plans { for j in pl.jobs { BuildersGrounds.apply(g, j) } }
        g.player.pos = c.spawn + V3(0, 8, 0); g.player.flying = true
        for _ in 0..<400 { g.tick(0.05) }
        var wrong: [String] = []
        for pl in plans { for j in pl.jobs where j.want != AIR && !BuildersGrounds.holds(w, j) { wrong.append(pl.bp.key) } }
        let byBuild = Dictionary(grouping: wrong, by: { $0 }).map { "\($0.key) \($0.value.count)" }.sorted()
        check(wrong.isEmpty,
              "Ledger 202/203 builds put up as the world does: \(plans.reduce(0) { $0 + $1.jobs.count }) jobs, \(felled) tree cells cleared round them, 20 s later \(wrong.count) blocks not where they were put (\(byBuild.joined(separator: ", ")))")
        if let shot = CircuitWorkshopTests.shot {
            g.time = 0.3 * DAY_LENGTH
            w.renderDistance = 8
            let floors = plans.map { Float($0.origin.y) }.sorted(), mid = floors[floors.count / 2]
            let ey = max(c.spawn.y + 2, mid + 10)
            shot(g, "builders_start", V3(c.spawn.x, ey + 1.6, c.spawn.z), c.yaw, -atan2f(ey - mid - 3, simd_length(V2(c.middle.x - c.spawn.x, c.middle.z - c.spawn.z))))
            for (name, a) in [("south", Float(0)), ("east", Float.pi / 2), ("north", Float.pi), ("west", -Float.pi / 2)] {
                let p = V3(m.x + sinf(a) * 46, 0, m.z + cosf(a) * 46)
                let y = Float(max(BuildersGrounds.groundY(w, Int(p.x), Int(p.z)), SEA)) + 22
                shot(g, "builders_\(name)", V3(p.x, y, p.z), atan2f(-(m.x - p.x), -(m.z - p.z)), -0.32)
            }
        }
    }

    // Ledger 211 (Fable's D): on the Builders' Grounds seed and two others, the six as the world puts them (together,
    // the trees round them cleared, the sites dressed): each on the kind of ground its name asks for. Each build's line:
    // its biome, the height spread under it, rock and sand under it, trunks round it, water near, lower ground round it.
    static func buildsOwnGround(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let bps = BuildersGrounds.blueprints()
        for seed in [BuildersGrounds.seed, 88314448595278, 20261116] as [UInt64] {
            let w = World(seed: seed, device: g0.world.device, save: nil)
            w.makeFieldWorld()
            w.renderDistance = 4; w.activeDistance = 4
            let g = Game(world: w, save: nil, persistent: false)
            let t0 = CFAbsoluteTimeGetCurrent()
            guard let c = BuildersGrounds.findCluster(w, centre: g.findSpawn(), kinds: bps.map { $0.ground }) else {
                check(false, "Ledger 211 builds on their own ground, seed \(seed): no place for the six (\(BuildersGrounds.lastWhy))"); continue
            }
            let secs = CFAbsoluteTimeGetCurrent() - t0
            var plans: [BuildersGrounds.Placement] = []
            for bp in bps { guard let st = c.sites[bp.ground] else { continue }
                _ = w.loadSync(center: V3(Float(st.x), 120, Float(st.z)), radius: 2)
                plans.append(BuildersGrounds.place(bp, on: w, at: st)) }
            let mids = plans.map { V3(Float($0.lo.x + $0.hi.x) / 2, 0, Float($0.lo.z + $0.hi.z) / 2) }
            let m = mids.reduce(V3.zero, +) / Float(max(1, mids.count))
            let reach = (mids.map { simd_length(V2($0.x - m.x, $0.z - m.z)) } + [simd_length(V2(c.spawn.x - m.x, c.spawn.z - m.z))]).max() ?? 30
            _ = w.loadSync(center: V3(m.x, 100, m.z), radius: Int(reach / Float(CS)) + 3)
            _ = BuildersGrounds.clearTrees(w, middle: m, radius: reach + 10)
            let dressed = g.dressBuildSites(plans, start: c.spawn)
            g.player.pos = c.spawn + V3(0, 8, 0); g.player.flying = true
            for _ in 0..<40 { g.tick(0.05) }
            var lines: [String] = [], mine = 0
            for pl in plans { let (ok, r) = BuildersGrounds.own(w, pl); if ok { mine += 1 }; lines.append(BuildersGrounds.line(pl, ok, r)) }
            for l in lines { print("builds own ground \(seed): " + l) }
            check(plans.count == bps.count && mine == plans.count,
                  String(format: "Ledger 211 builds on their own ground, seed %@: %d of %d (natural there: %@; dressed: %@; found in %.1f s)",
                         "\(seed)", mine, plans.count, c.own.sorted().joined(separator: ", "), dressed.isEmpty ? "none" : dressed.joined(separator: "; "), secs))
        }
    }

    // Ledger 196 (21:14:15, "Why can't I get in this chair?"): a chair on a craft's deck seats him, holds him on it as the
    // craft moves and turns, and a step stands him up beside it on the deck.
    static func shipChair(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let pos0 = g.player.pos, yaw0 = g.player.yaw
        let s = w.ships.spawn(AshWrecks.salvagedFighter(), at: g.player.pos + V3(0, 12, 30), yaw: 0, name: "Seat Test", role: "capplane")
        defer { ChairSeat.shared.release(); w.ships.remove(s, turrets: false); g.player.pos = pos0; g.player.yaw = yaw0; g.player.vel = .zero }
        // A deck cell with air over it, and a chair on it.
        var seat: IVec3?
        let g0 = s.grid
        search: for y in stride(from: g0.sy - 1, through: 1, by: -1) { for z in 1..<(g0.sz - 1) { for x in 1..<(g0.sx - 1) {
            if Blocks.collide[Int(g0.get(x, y, z))] && g0.get(x, y + 1, z) == AIR && g0.get(x, y + 2, z) == AIR { seat = IVec3(x, y + 1, z); break search }
        } } }
        guard let c = seat, Blocks.has("oak_chair") else { check(false, "Ledger 196 ship chair: no deck cell on the test craft"); return }
        w.ships.setBlock(s, c, Blocks.id("oak_chair") + 1)              // facing south
        let sat = ChairSeat.shared.sitShip(g, s, c)
        var mi = MoveInput()
        _ = ChairSeat.shared.tick(g, mi)
        let on0 = simd_length(g.player.pos - ChairSeat.shipSeatPos(s, c, top: 10 / 16))
        // The craft moves 6 blocks and turns a quarter: he stays on the seat.
        s.pos += V3(6, 0, -2)
        s.rot = simd_quatf(angle: .pi / 2, axis: V3(0, 1, 0)) * s.rot
        _ = ChairSeat.shared.tick(g, mi)
        let on1 = simd_length(g.player.pos - ChairSeat.shipSeatPos(s, c, top: 10 / 16))
        let held = ChairSeat.shared.seatedOnShip
        mi.forward = 1
        _ = ChairSeat.shared.tick(g, mi)
        let up = !ChairSeat.shared.seatedOnShip
        let off = simd_length(g.player.pos - s.toWorld(V3(Float(c.x), Float(c.y), Float(c.z)) + 0.5))
        check(sat && on0 < 0.01 && held && on1 < 0.01 && up && off < 1.8,
              "Ledger 196 ship chair: a chair on a craft's deck seats him (\(sat)), he stays on it as the craft moves 6 and turns 90 (\(String(format: "%.3f", on1)) off), and a step stands him up beside it (\(up), \(String(format: "%.2f", off)) from it)")
    }

    // Ledger 191 (20:45:34, "the wire is not perfectly flush with material under it"): copper wire on a natural block at
    // the corner of a 3x3 stone pad in the air: the block's four top corners stay on its flat top (pinned), while the
    // pad's opposite corner block, bare, rounds away (so the check means something).
    static func attachPin(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, was = SmoothTerrain.enabled, field0 = SmoothTerrain.fromField
        SmoothTerrain.enabled = true; SmoothTerrain.fromField = false
        defer { SmoothTerrain.enabled = was; SmoothTerrain.fromField = field0 }
        let p0 = g.player.pos
        let x0 = (Int(floor(p0.x)) & ~15) + 8, z0 = (Int(floor(p0.z)) & ~15) + 8       // mid-chunk: no neighbour sections
        _ = w.loadSync(center: V3(Float(x0), p0.y, Float(z0)), radius: 1)
        let y0 = min(CH - 40, ((w.topY(x0, z0) + 24) & ~15) + 7)                           // mid-section
        let stone = Blocks.id("stone"), wire = Blocks.id("redstone_wire")
        var placed: [IVec3] = []
        for dz in -1...1 { for dx in -1...1 { w.setBlock(x0 + dx, y0, z0 + dz, stone); placed.append(IVec3(x0 + dx, y0, z0 + dz)) } }
        w.setBlock(x0 - 1, y0 + 1, z0 - 1, wire); placed.append(IVec3(x0 - 1, y0 + 1, z0 - 1))
        defer { for q in placed.reversed() { w.setBlock(q.x, q.y, q.z, AIR) } }
        var cells: [SIMD3<Int>: SIMD3<Float>] = [:]
        SmoothTerrain.vertexHook = { a, b, c, p in cells[SIMD3<Int>(a, b, c)] = p }
        if let ch = w.chunkAt(x0, z0), let nb = w.neighbourhood(ch) { _ = Mesher.buildSection(nb.0, nb.1, sy: y0 >> 4) }
        SmoothTerrain.vertexHook = nil
        // The dual cell of the corner (x, y, z) is (x - 1, y - 1, z - 1), section-local.
        func cornerY(_ x: Int, _ z: Int) -> Float? {
            cells[SIMD3<Int>(mod(x, CS) - 1, mod(y0 + 1, 16) - 1, mod(z, CS) - 1)].map { $0.y - Float(mod(y0 + 1, 16)) }
        }
        let wired = [(x0 - 1, z0 - 1), (x0, z0 - 1), (x0 - 1, z0), (x0, z0)].map { cornerY($0.0, $0.1) }
        let bare = cornerY(x0 + 2, z0 + 2)
        let flush = wired.allSatisfy { $0 != nil && abs($0!) < 1e-4 }
        let rounds = (bare ?? 0) < -0.05
        func f(_ v: Float?) -> String { v.map { String(format: "%.3f", $0) } ?? "none" }
        check(flush && rounds,
              "Ledger 191 wire flush: copper wire on a natural block at a pad's corner keeps its four top corners on the block's top (\(wired.map(f).joined(separator: ", ")) blocks off); the bare far corner rounds (\(f(bare)))")
    }
}
