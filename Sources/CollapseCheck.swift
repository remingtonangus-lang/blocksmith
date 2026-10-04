import Foundation
import Metal
import simd

// `Blocksmith --collapsecheck [--scenes bridge,tower,frigate,wreck] [--seed N] [--out DIR]`: destruction physics and
// persistent wrecks through the real Game.tick (Destruction.swift, Debris.swift, Wrecks.swift). Scenes:
//   bridge   a stone-brick bridge on three piers; the middle pier is blasted: the span it held falls, the rest stands
//   mine     the same bridge with its middle pier mined out block by block (Game.breakBlock), not blasted
//   tower    a hollow 5x5 tower 30 high; its base is blasted on one side: it breaks above the base and topples
//   stands   a hollow 5x5 tower 60 high with a balcony on one side (heavier than its base bears, lopsided): one block
//            mined at its foot and a small blast in its wall bring nothing down
//   massive  a solid 30x12x30 brick block (bigger than one support search): a blast on it brings nothing down and the
//            capped search stays within its time budget
//   desert   blasts in a real desert (sand over the sandstone sheet): terrain never falls, the search stays small
//   frigate  a Capital frigate cut through its middle by a ring of blasts: it breaks in two, both halves fall, settle
//            and stay as wrecks
//   dropship a dropship shot down over the plains: it falls, crashes and stays as a wreck (no vanishing fireball)
//   wreck    a crawler disabled on the plains settles into a wreck: world blocks, salvage crates, sheltered spots;
//            three weeks later it has rusted and overgrown
// Oracles: the right part falls, no floating leftovers (the support analysis over the whole scene finds nothing
// unsupported), every debris body laid back into the world, nothing inside the player, tick time within budget.
// Snapshot harness: `--collapse bridge|tower|frigate|wreck --at SECONDS` stages the same scene for a shot.
enum CollapseCheck {
    final class Stage {
        let game: Game
        let world: World
        var origin = IVec3(0, 0, 0)
        var box = (IVec3(0, 0, 0), IVec3(0, 0, 0))       // the scene's region (for the floating-leftovers oracle)
        var ship: Ship?
        var watch: [IVec3] = []                            // cells expected to fall
        var blasts: [(V3, Float)] = []                     // set off at time 0
        var mine: [IVec3] = []                             // blocks broken as a player mines them, at time 0
        var view = (V3(0, 0, 0), Float(0), Float(0))      // camera: position, yaw, pitch
        init(game: Game, world: World) { self.game = game; self.world = world }
    }

    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        guard let device = MTLCreateSystemDefaultDevice() else { print("collapsecheck: no Metal device"); return 2 }
        PrefsSandbox.begin()
        defer { PrefsSandbox.end() }
        let out = arg("--out") ?? "snaps"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let seed = UInt64(arg("--seed") ?? "") ?? 12345
        let names = (arg("--scenes") ?? "bridge,mine,tower,stands,massive,desert,frigate,wreck,dropship").split(separator: ",").map(String.init)
        let r = RideCheck.Report()
        r.md = ["# Collapse check", "", "Seed \(seed). Destruction physics and persistent wrecks through Game.tick.", ""]
        let t0 = CFAbsoluteTimeGetCurrent()
        for n in names {
            r.scene = n
            r.md.append("## \(n)")
            let ts = CFAbsoluteTimeGetCurrent()
            let (world, game) = Agent.makeWorld(device: device, seed: seed, botSeed: 1, rd: 6)
            World.deterministic = false
            let st = Stage(game: game, world: world)
            prepare(st)
            guard build(n, st) else { r.check(false, "the \(n) scene could be built"); continue }
            switch n {
            case "wreck": wreckScene(r, st)
            case "dropship": dropshipScene(r, st)
            default: collapseScene(r, st, name: n)
            }
            r.note(String(format: "scene took %.0f s", CFAbsoluteTimeGetCurrent() - ts))
            r.md.append("")
        }
        let summary = String(format: "collapsecheck: %@ (%ld scenes in %.0f s)", r.fails == 0 ? "PASS" : "\(r.fails) FAILED", names.count, CFAbsoluteTimeGetCurrent() - t0)
        r.md.insert(summary, at: 2)
        try? (r.md.joined(separator: "\n") + "\n").write(toFile: "\(out)/collapsecheck.md", atomically: true, encoding: .utf8)
        print(summary)
        return r.fails == 0 ? 0 : 3
    }

    // A creative game on flat land, nothing else moving.
    static func prepare(_ st: Stage) {
        let g = st.game, w = st.world
        g.survival = false
        g.difficulty = 0
        w.ships.encounters = false
        let spot = RideCheck.land(w, near: g.player.pos, rough: false, verify: true)
        _ = w.loadSync(center: V3(Float(spot.0), 100, Float(spot.1)), radius: 5)
        st.origin = IVec3(spot.0, w.topY(spot.0, spot.1) + 1, spot.1)
    }

    static func fill(_ w: World, _ a: IVec3, _ b: IVec3, _ id: BlockID) {
        for y in min(a.y, b.y)...max(a.y, b.y) { for z in min(a.z, b.z)...max(a.z, b.z) { for x in min(a.x, b.x)...max(a.x, b.x) {
            _ = w.setBlockAsync(x, y, z, id)
        } } }
    }

    // Builds a scene round st.origin (world blocks, or a capital ship) and says what it expects. False if it can't.
    static func build(_ kind: String, _ st: Stage) -> Bool {
        let w = st.world, g = st.game, o = st.origin
        let brick = Blocks.id("stone_bricks")
        switch kind {
        case "bridge", "mine":
            // Three 3x3 piers 10 apart, a 3-wide deck 12 up over 25 blocks: every deck block within 4 of a pier.
            let deckY = o.y + 12
            for px in [0, 10, 20] { for dz in -1...1 { for dx in -1...1 {
                let x = o.x + px + dx, z = o.z + dz
                fill(w, IVec3(x, w.topY(x, z) + 1, z), IVec3(x, deckY - 1, z), brick)
            } } }
            fill(w, IVec3(o.x - 2, deckY, o.z - 1), IVec3(o.x + 22, deckY, o.z + 1), brick)
            for x in (o.x - 2)...(o.x + 22) { for z in [o.z - 1, o.z + 1] { _ = w.setBlockAsync(x, deckY + 1, z, Blocks.id("stone_brick_wall")) } }
            st.box = (IVec3(o.x - 4, o.y - 2, o.z - 4), IVec3(o.x + 24, deckY + 3, o.z + 4))
            var span: [IVec3] = []
            for dx in 8...12 { for dz in -1...1 { span.append(IVec3(o.x + dx, deckY, o.z + dz)) } }
            st.watch = span
            if kind == "mine" {
                // The middle pier's top layer under the deck, mined out: the deck over it has nothing below it there.
                for dz in -1...1 { for dx in -1...1 { st.mine.append(IVec3(o.x + 10 + dx, deckY - 1, o.z + dz)) } }
                for y in stride(from: deckY - 2, through: o.y, by: -1) { for dz in -1...1 { for dx in -1...1 { st.mine.append(IVec3(o.x + 10 + dx, y, o.z + dz)) } } }
            } else {
                st.blasts = [(V3(Float(o.x + 10) + 0.5, Float(deckY - 2), Float(o.z) + 0.5), 4),
                             (V3(Float(o.x + 10) + 0.5, Float(deckY - 6), Float(o.z) + 0.5), 4),
                             (V3(Float(o.x + 10) + 0.5, Float(o.y + 2), Float(o.z) + 0.5), 4)]
            }
            st.view = (V3(Float(o.x + 10), Float(o.y + 8), Float(o.z + 34)), 0, -0.12)
        case "tower":
            // A hollow 5x5 stone-brick tower 30 high with a floor every 6; blasted at its base on the +x side.
            let h = 30
            for y in 0..<h { for dz in -2...2 { for dx in -2...2 where abs(dx) == 2 || abs(dz) == 2 || y % 6 == 5 {
                _ = w.setBlockAsync(o.x + dx, o.y + y, o.z + dz, brick)
            } } }
            st.box = (IVec3(o.x - 30, o.y - 2, o.z - 30), IVec3(o.x + 30, o.y + h + 2, o.z + 30))
            var top: [IVec3] = []
            for dz in -2...2 { for dx in -2...2 where abs(dx) == 2 || abs(dz) == 2 { top.append(IVec3(o.x + dx, o.y + h - 1, o.z + dz)) } }
            st.watch = top
            let bx = Float(o.x + 3), by = Float(o.y + 1), bz = Float(o.z) + 0.5
            st.blasts = [(V3(bx, by, bz), 4), (V3(bx, by, bz - 2), 3.5), (V3(bx, by, bz + 2), 3.5)]
            st.view = (V3(Float(o.x + 4), Float(o.y + 14), Float(o.z + 46)), 0, -0.2)
        case "stands":
            let h = 60
            for y in 0..<h { for dz in -2...2 { for dx in -2...2 where abs(dx) == 2 || abs(dz) == 2 || y % 6 == 5 {
                _ = w.setBlockAsync(o.x + dx, o.y + y, o.z + dz, brick)
            } } }
            // A balcony four out on the +x side near the top.
            fill(w, IVec3(o.x + 3, o.y + h - 3, o.z - 1), IVec3(o.x + 6, o.y + h - 3, o.z + 1), brick)
            st.box = (IVec3(o.x - 8, o.y - 2, o.z - 8), IVec3(o.x + 8, o.y + h + 2, o.z + 8))
            var all: [IVec3] = []
            for y in stride(from: 5, to: h, by: 6) { for dz in -2...2 { for dx in -2...2 { all.append(IVec3(o.x + dx, o.y + y, o.z + dz)) } } }
            st.watch = all
            st.mine = [IVec3(o.x - 2, o.y, o.z)]
            st.blasts = [(V3(Float(o.x) + 0.5, Float(o.y + 20) + 0.5, Float(o.z + 3) + 0.2), 2)]
            st.view = (V3(Float(o.x + 4), Float(o.y + 20), Float(o.z + 60)), 0, 0.3)
        case "massive":
            for y in 0..<12 { for z in -15..<15 { for x in -15..<15 {
                let gx = o.x + x, gz = o.z + z
                // Down to the ground under each column (flat land, but a dip would leave the block resting on air).
                if y == 0 { fill(w, IVec3(gx, w.topY(gx, gz) + 1, gz), IVec3(gx, o.y, gz), brick) }
                _ = w.setBlockAsync(gx, o.y + y, gz, brick)
            } } }
            st.box = (IVec3(o.x - 18, o.y - 2, o.z - 18), IVec3(o.x + 18, o.y + 14, o.z + 18))
            st.blasts = [(V3(Float(o.x) + 0.5, Float(o.y + 12), Float(o.z) + 0.5), 4), (V3(Float(o.x + 15) + 0.5, Float(o.y + 6), Float(o.z) + 0.5), 4)]
            st.view = (V3(Float(o.x), Float(o.y), Float(o.z + 40)), 0, 0.1)
        case "desert":
            guard let p = Snapshot.findBiome(w.gen, "desert", interior: true) else { return false }
            let x = Int(floor(p.x)), z = Int(floor(p.z))
            _ = w.loadSync(center: V3(Float(x), 100, Float(z)), radius: 5)
            let top = w.topY(x, z)
            st.origin = IVec3(x, top + 1, z)
            st.blasts = [(V3(Float(x) + 0.5, Float(top - 2), Float(z) + 0.5), 4), (V3(Float(x + 7) + 0.5, Float(top), Float(z) + 0.5), 4),
                         (V3(Float(x) + 0.5, Float(top - 5), Float(z + 7) + 0.5), 4)]
            st.box = (IVec3(x - 20, top - 14, z - 20), IVec3(x + 20, top + 6, z + 20))
            st.view = (V3(Float(x), Float(top + 1), Float(z + 30)), 0, -0.1)
        case "frigate":
            // A Capital frigate hovering low over the plains, cut through amidships by a ring of blasts.
            w.ships.spawnCapital("capfrigate", home: IVec3(o.x, 0, o.z), yaw: 0.4, region: nil, sync: true)
            guard let s = w.ships.capitals.first(where: { $0.role == "capfrigate" }), let cs = w.ships.capState[s.id] else { return false }
            cs.crewDone = Set(0..<cs.crew.count)
            cs.crewless = true
            cs.testTurn = 0
            cs.testSpeed = 0
            st.ship = s
            let mid: Float = 76
            var bl: [(V3, Float)] = []
            for zz in [mid - 1.5, mid + 1.5] {
                for y in stride(from: Float(1), through: 31, by: 3) { for x in stride(from: Float(1), through: 30, by: 3) {
                    bl.append((s.toWorld(V3(x, y, zz)), 4))
                } }
            }
            st.blasts = bl
            st.box = (IVec3(o.x - 120, o.y - 4, o.z - 120), IVec3(o.x + 120, o.y + 90, o.z + 120))
            let side = s.dirToWorld(V3(1, 0, 0))
            let at = s.pos + side * 45 + V3(0, -10, 0)
            st.view = (at, atan2f(side.x, side.z), -0.05)
        case "dropship":
            // Built in place 30 above the ground (as a frigate launches one), shot down at once (trigger).
            let hb = Capital.dropship()
            let ids = (0..<2).map { _ in w.ships.newId() }
            let ships = Capital.makeShips(hb, ids: ids, name: "Stormwarden Dropship", role: "dropship", faction: .stormwarden)
            let d = ships[0]
            d.pos = V3(Float(o.x) + 0.5, Float(o.y + 30), Float(o.z) + 0.5)
            d.prevPos = d.pos; d.prevRot = d.rot
            d.home = d.pos
            d.initialBlocks = d.blockCount
            d.updateBounds()
            for t in ships.dropFirst() { t.followParent(0); t.prevPos = t.pos; t.prevRot = t.rot }
            let ds = CapitalState()
            ds.groundOffset = d.com.y - d.localMin.y
            ds.phase = 4
            w.ships.installCapital((ships, ds))
            st.ship = d
            st.box = (IVec3(o.x - 40, o.y - 4, o.z - 40), IVec3(o.x + 40, o.y + 40, o.z + 40))
            st.view = (V3(Float(o.x + 24), Float(o.y + 6), Float(o.z + 24)), atan2f(24, 24), 0.1)
        case "wreck":
            w.ships.spawnCapital("crawler", home: IVec3(o.x, 0, o.z), yaw: 0.4, region: nil, sync: true)
            guard let s = w.ships.capitals.first(where: { $0.role == "crawler" }), let cs = w.ships.capState[s.id] else { return false }
            cs.crewDone = Set(0..<cs.crew.count)
            cs.crewless = true
            cs.testTurn = 0
            cs.testSpeed = 3
            st.ship = s
            st.box = (IVec3(o.x - 80, o.y - 4, o.z - 80), IVec3(o.x + 80, o.y + 40, o.z + 80))
            st.view = (s.pos + V3(40, 20, 40), atan2f(40, 40), -0.35)
        default:
            return false
        }
        w.remeshArea(x0: st.box.0.x, z0: st.box.0.z, x1: st.box.1.x, z1: st.box.1.z, y0: max(0, st.box.0.y), y1: min(CH - 1, st.box.1.y))
        // The camera / bot: standing on the ground at the view point (creative, never in harm's way).
        let p = g.player
        p.flying = kind == "frigate"
        p.pos = st.view.0
        if !p.flying {
            let x = Int(floor(p.pos.x)), z = Int(floor(p.pos.z))
            _ = w.loadSync(center: p.pos, radius: 2)
            p.pos.y = Float(w.topY(x, z) + 1)
        }
        p.yaw = st.view.1
        p.pitch = st.view.2
        p.vel = .zero
        p.lastUpdatePos = p.pos
        p.airPeak = p.pos.y
        return true
    }

    // Sets off the scene's blasts (and disables a crawler for the wreck scene, shoots down the dropship).
    static func trigger(_ st: Stage) {
        if let s = st.ship, s.role == "dropship" { s.wrecked = true }
        for (c, pw) in st.blasts { Explosion.explode(at: c, power: pw, game: st.game) }
        for c in st.mine {
            let b = st.world.rawBlock(c.x, c.y, c.z)
            if b != AIR { st.game.breakBlock(c, b, drop: false) }
        }
        if let s = st.ship, s.role == "crawler", let cs = st.world.ships.capState[s.id] {
            let kinds = ShipParts.kinds
            var cells: [(IVec3, BlockID)] = []
            for wh in cs.wheels where wh.lo.x < s.grid.sx / 2 {
                for y in wh.lo.y...wh.hi.y { for z in wh.lo.z...wh.hi.z { for x in wh.lo.x...wh.hi.x where kinds[Int(s.grid.get(x, y, z))] == .wheel {
                    cells.append((IVec3(x, y, z), AIR))
                } } }
            }
            st.world.ships.setBlocks(s, cells)
        }
    }

    // Built blocks left with nothing holding them in the scene's region (the support analysis seeded with all of them).
    // Wrecks are left out: a wreck is laid down whole as a rigid hulk (Wrecks.swift), not held block by block.
    static func inBox(_ c: IVec3, _ lo: IVec3, _ hi: IVec3) -> Bool {
        let inX = c.x >= lo.x - 1 && c.x <= hi.x + 1
        let inY = c.y >= lo.y - 1 && c.y <= hi.y + 1
        let inZ = c.z >= lo.z - 1 && c.z <= hi.z + 1
        return inX && inY && inZ
    }

    static func floating(_ st: Stage) -> (Int, String) {
        let w = st.world
        var seeds: [IVec3] = []
        let (lo, hi) = st.box
        let wrecks = w.ships.wrecks.map { (IVec3($0.lo[0], $0.lo[1], $0.lo[2]), IVec3($0.hi[0], $0.hi[1], $0.hi[2])) }
        for y in max(1, lo.y)...min(CH - 2, hi.y) { for z in lo.z...hi.z { for x in lo.x...hi.x where w.isLoaded(x, z) {
            if Collapse.built(w.rawBlock(x, y, z)) && !wrecks.contains(where: { inBox(IVec3(x, y, z), $0.0, $0.1) }) {
                seeds.append(IVec3(x, y, z))
            }
        } } }
        let res = Collapse.analyze(w, around: [], seeds: seeds, cap: 60000)
        let n = res.falling.reduce(0) { $0 + $1.count } + res.tip.reduce(0) { $0 + $1.cells.count }
        var at = ""
        if let p = res.falling.first?.first {
            var kinds: [String: Int] = [:]
            var bl = p, bh = p
            for piece in res.falling { for c in piece {
                kinds[Blocks.key(Blocks.groupBase[Int(w.rawBlock(c.x, c.y, c.z))]), default: 0] += 1
                bl = IVec3(min(bl.x, c.x), min(bl.y, c.y), min(bl.z, c.z)); bh = IVec3(max(bh.x, c.x), max(bh.y, c.y), max(bh.z, c.z))
            } }
            let top = kinds.sorted { $0.value > $1.value }.prefix(4).map { "\($0.key) \($0.value)" }.joined(separator: ", ")
            at = "\(p.x),\(p.y - YOFF),\(p.z) (\(Blocks.key(w.rawBlock(p.x, p.y, p.z)))); \(res.falling.count) pieces in \(bl.x),\(bl.y - YOFF),\(bl.z) to \(bh.x),\(bh.y - YOFF),\(bh.z): \(top)"
        }
        return (n, at)
    }

    static func collapseScene(_ r: RideCheck.Report, _ st: Stage, name: String) {
        let w = st.world, g = st.game
        let idle = RideCheck.Bot()
        let agent = Agent(game: g, world: w)
        for _ in 0..<30 { agent.step(idle) }
        let before = floating(st)
        r.check(before.0 == 0, "the scene stands before the blast (\(before.0) unsupported\(before.1.isEmpty ? "" : " at " + before.1))")
        let built0 = st.watch.filter { Collapse.built(w.rawBlock($0.x, $0.y, $0.z)) }.count
        let t0 = CFAbsoluteTimeGetCurrent()
        trigger(st)
        let blastMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        var maxBodies = 0, ticks: [Double] = [], inside = 0
        var halfY0: Float = 0, lowest: Float = .greatestFiniteMagnitude
        let limit = name == "frigate" ? 150 : 40
        var settledFor = 0
        for i in 0..<(limit * 60) {
            let a = CFAbsoluteTimeGetCurrent()
            agent.step(idle)
            ticks.append((CFAbsoluteTimeGetCurrent() - a) * 1000)
            let bodies = w.ships.list.filter { $0.debris }
            maxBodies = max(maxBodies, bodies.count)
            if let sec = bodies.max(by: { $0.blockCount < $1.blockCount }), name == "frigate" {
                if halfY0 == 0 { halfY0 = sec.pos.y }
                lowest = min(lowest, sec.pos.y)
            }
            let p = g.player
            if w.collides(V3(p.pos.x - 0.25, p.pos.y + 0.05, p.pos.z - 0.25), V3(p.pos.x + 0.25, p.pos.y + 1.7, p.pos.z + 0.25)) { inside += 1 }
            let busy = bodies.isEmpty && (name != "frigate" || w.ships.capitals.isEmpty)
            settledFor = busy ? settledFor + 1 : 0
            if i > 120 && settledFor > 120 { break }
        }
        ticks.sort()
        let mean = ticks.reduce(0, +) / Double(max(1, ticks.count))
        let p95 = ticks.isEmpty ? 0 : ticks[min(ticks.count - 1, Int(Double(ticks.count) * 0.95))]
        let worst = ticks.last ?? 0
        let ms = w.ships
        r.note(String(format: "blasts %.0f ms; %ld collapses, %ld hull splits, up to %ld debris bodies, %ld blocks laid back; tick mean %.2f p95 %.2f worst %.1f ms over %ld ticks; last analysis %.1f ms",
                      blastMs, ms.collapses, ms.hullSplits, maxBodies, ms.bakedBlocks, mean, p95, worst, ticks.count, ms.collapseMs))
        let left = st.watch.filter { Collapse.built(w.rawBlock($0.x, $0.y, $0.z)) }.count
        switch name {
        case "frigate":
            r.note("after: \(ms.capitals.count) still flying (\(ms.capitals.map { "\($0.name) engines \($0.engines), helm \($0.helm == nil ? "gone" : "kept"), wrecked \($0.wrecked)" }.joined(separator: "; "))), wrecks \(ms.wrecks.map { $0.kind }.joined(separator: ", "))")
            r.check(ms.hullSplits >= 1, "the cut hull breaks in two (\(ms.hullSplits) splits)")
            r.check(halfY0 - lowest > 20, String(format: "the severed half falls (%.0f blocks)", halfY0 - lowest))
            r.check(ms.capitals.isEmpty && ms.wrecks.count >= 2, "both halves come down and stay as wrecks (\(ms.wrecks.count) wrecks, \(ms.capitals.count) still flying)")
        case "massive":
            r.check(maxBodies == 0, "a crater in a solid block brings nothing down (\(maxBodies) debris bodies)")
            r.check(ms.collapseMs < 15, String(format: "a search that hits its cap stays within budget (%.1f ms under 15)", ms.collapseMs))
        case "desert":
            r.check(maxBodies == 0, "terrain blasts bring nothing down (\(maxBodies) debris bodies)")
            r.check(ms.collapseMs < 8, String(format: "the support search round the craters stays small (%.1f ms)", ms.collapseMs))
        case "stands":
            r.check(built0 > 0 && left == built0, "the tower stands (\(left) of \(built0) floor blocks left)")
            r.check(maxBodies == 0, "nothing falls (\(maxBodies) debris bodies)")
        default:
            r.check(built0 > 0 && left * 4 <= built0, "the part that lost its support falls (\(left) of \(built0) watched blocks left)")
            r.check(ms.collapses >= 1 && maxBodies >= 1, "it falls as a moving body (\(maxBodies) at once)")
        }
        r.check(maxBodies <= Collapse.maxDebris, "debris bodies stay under the cap (\(maxBodies) of \(Collapse.maxDebris))")
        r.check(!w.ships.list.contains { $0.debris }, "every piece is laid back into the world once it rests")
        let after = floating(st)
        r.check(after.0 == 0, "no floating leftovers (\(after.0) unsupported blocks\(after.1.isEmpty ? "" : ", first at " + after.1))")
        r.check(inside == 0, "nothing ends up inside the player (\(inside) ticks)")
        r.check(p95 < 16 && worst < 120, String(format: "tick time within budget during the collapse (p95 %.2f ms under 16, worst %.1f under 120)", p95, worst))
    }

    static func wreckScene(_ r: RideCheck.Report, _ st: Stage) {
        let w = st.world, g = st.game
        let idle = RideCheck.Bot()
        let agent = Agent(game: g, world: w)
        for _ in 0..<(4 * 60) { agent.step(idle) }
        trigger(st)
        var t: Float = 0
        while t < 60 && !(w.ships.capitals.isEmpty && !w.ships.wrecks.isEmpty) {
            agent.step(idle)
            t += 1.0 / 60
        }
        guard let rec = w.ships.wrecks.first else { r.check(false, "the disabled crawler becomes a wreck (after \(Int(t)) s)"); return }
        r.check(w.ships.capitals.isEmpty, "the disabled crawler becomes a wreck in the world (after \(Int(t)) s)")
        let lo = IVec3(rec.lo[0], rec.lo[1], rec.lo[2]), hi = IVec3(rec.hi[0], rec.hi[1], rec.hi[2])
        func count(_ f: (BlockID) -> Bool) -> Int {
            var n = 0
            for y in max(0, lo.y - 1)...min(CH - 1, hi.y + 1) { for z in (lo.z - 2)...(hi.z + 2) { for x in (lo.x - 2)...(hi.x + 2) where f(w.rawBlock(x, y, z)) { n += 1 } } }
            return n
        }
        let hull = count { Wrecks.rusts($0) }
        r.check(hull > 1500, "its hull is world blocks now (\(hull) plates)")
        var crates = 0, filled = 0
        for (c, be) in w.blockEntities where c.x >= lo.x && c.x <= hi.x && c.y >= lo.y && c.y <= hi.y && c.z >= lo.z && c.z <= hi.z {
            crates += 1
            if be.container.slots.contains(where: { !$0.isEmpty }) { filled += 1 }
        }
        r.check(crates >= 2 && filled >= 2, "salvage to be had: \(crates) containers, \(filled) with loot")
        // Sheltered floor (air under a roof within 6, on a solid block): where mobs settle in a wreck.
        var shelter = 0
        for y in lo.y...hi.y { for z in lo.z...hi.z { for x in lo.x...hi.x where w.rawBlock(x, y, z) == AIR && w.rawBlock(x, y + 1, z) == AIR {
            guard Blocks.fullCollide[Int(w.rawBlock(x, y - 1, z))] else { continue }
            var roofed = false
            for k in 2...6 where Blocks.collide[Int(w.rawBlock(x, y + k, z))] { roofed = true; break }
            if roofed { shelter += 1 }
        } } }
        r.check(shelter > 40, "sheltered floor inside it for mobs to move into (\(shelter) cells)")
        let rust0 = count { Blocks.key($0) == "rusted_plating" }, moss0 = count { Blocks.key($0) == "moss_carpet" || Blocks.key($0) == "vine" }
        // Three weeks on.
        g.time += 21 * DAY_LENGTH
        for _ in 0..<(70 * 60) { agent.step(idle) }
        let rust1 = count { Blocks.key($0) == "rusted_plating" }, moss1 = count { Blocks.key($0) == "moss_carpet" || Blocks.key($0) == "vine" }
        let steps = w.ships.wrecks.first?.steps ?? 0
        r.note("overgrowth: \(steps) steps; rusted plates \(rust0) -> \(rust1), moss and vines \(moss0) -> \(moss1)")
        r.check(steps >= Wrecks.maxSteps, "three weeks of overgrowth catch up while the player is near (\(steps) steps)")
        r.check(rust1 >= 60 && moss1 >= 40, "it has rusted and overgrown (\(rust1) rusted plates, \(moss1) moss and vines)")
        let enc = (try? JSONEncoder().encode(w.ships.wrecks)).flatMap { try? JSONDecoder().decode([WreckRecord].self, from: $0) }
        r.check(enc?.count == w.ships.wrecks.count, "wreck records survive a save round trip")
    }

    static func dropshipScene(_ r: RideCheck.Report, _ st: Stage) {
        let w = st.world, g = st.game
        let idle = RideCheck.Bot()
        let agent = Agent(game: g, world: w)
        for _ in 0..<60 { agent.step(idle) }
        guard let d = st.ship else { r.check(false, "the dropship was built"); return }
        let y0 = d.pos.y
        trigger(st)
        var t: Float = 0, lowest = y0
        while t < 40 && w.ships.wrecks.isEmpty {
            agent.step(idle)
            t += 1.0 / 60
            if w.ships.list.contains(where: { $0 === d }) { lowest = min(lowest, d.pos.y) }
        }
        r.note(String(format: "fell %.0f blocks, a wreck after %.1f s; %ld wrecks", y0 - lowest, t, w.ships.wrecks.count))
        r.check(y0 - lowest > 20, String(format: "the shot-down dropship falls (%.0f blocks)", y0 - lowest))
        r.check(!w.ships.list.contains(where: { $0 === d }) && w.ships.wrecks.count == 1, "it stays where it fell as a wreck (\(w.ships.wrecks.count) wrecks)")
        if let rec = w.ships.wrecks.first {
            var n = 0
            for y in rec.lo[1]...rec.hi[1] { for z in rec.lo[2]...rec.hi[2] { for x in rec.lo[0]...rec.hi[0] where Collapse.built(w.rawBlock(x, y, z)) { n += 1 } } }
            r.check(n > 150, "its hull is world blocks now (\(n) blocks)")
        }
    }

    // Snapshot harness: stages the scene in the harness's game and runs it `at` seconds (0: before the blast).
    static func shot(_ kind: String, game g: Game, at: Float) -> V3 {
        let st = Stage(game: g, world: g.world)
        prepare(st)
        guard build(kind, st) else { print("collapse: unknown scene \(kind)"); return g.player.pos }
        if at > 0 {
            trigger(st)
            let n = Int(at * 60)
            for _ in 0..<n {
                g.world.ships.update(1.0 / 60, game: g)
                g.mobs.update(1.0 / 60, game: g)
                g.world.update(center: g.player.pos)
            }
        }
        let p = g.player
        p.pos = st.view.0
        p.yaw = st.view.1
        p.pitch = st.view.2
        print("collapse \(kind) at \(at) s: \(g.world.ships.list.filter { $0.debris }.count) debris bodies, \(g.world.ships.collapses) collapses, \(g.world.ships.wrecks.count) wrecks")
        return p.pos
    }
}
