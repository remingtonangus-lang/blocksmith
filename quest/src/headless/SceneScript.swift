import Foundation
import Metal
import simd

// questcheck --scene FILE [--seed S] [--headset] [--out DIR]: a voice note's bug played back from a text file, one
// command a line, against the game through the calls play uses (Game.tick at 72 Hz; the player's look, walk, break and
// place go through the bot's input path, Agent.apply, the same InputState the window fills). One result line a
// command; `expect` lines fail the run (exit 1). Blank lines and `#` comments are skipped.
//
// Coordinates are as the game shows them (a voice note's Position line): y is the displayed height (internal y - 64).
// `look YAW PITCH` takes the note's facing and pitch in degrees, as --view --look does.
//
//   at X Y Z / look YAW PITCH / load R / tick SECONDS / survival on|off / fly on|off / give ITEM [N]
//   block X Y Z / set X Y Z KEY / break X Y Z / place X Y Z / blast X Y Z [POWER] / dump X0 Y0 Z0 X1 Y1 Z1
//   shot NAME.png [W H]                          (the --view render at the eye; into --out DIR, never the repo)
//   spawn mob KIND / spawn vessel KIND / ride nearest train|ship / drive THROTTLE SECONDS / walk forward SECONDS
//   train at station                             (the nearest line's passenger train standing at its nearest station)
//   ride until step N MIN [SECONDS]              (play on until the floors' step at coach N's coupling is MIN either way)
//   stand in coach N / walk to coach N [SECONDS] (walk.there 1|0, walk.lowest: least height over the rail in the
//                                                 coach he is in, walk.step: the floors' step at the coupling)
//   print player|train|ship|fps|troops        (troops: soldiers within 96, stashed, taken away, died)
//   fly to X Z SECONDS [SPEED]                   (flying toward a point through the input path, at most SPEED b/s)
//   realtime on|off                              (each tick waits out its 1/72 s: generation keeps play's pace)
//   (--save: the world kept on disk as the headset keeps it; --active N: the active distance)
//   time FRAC / hold sneak|jump|use|attack|sprint SECONDS / face train car N / ride train car N
//   expect riding|aboard|player.ground|player.inblock|player.falling|train.dist|train.cars|coach OP N
//   expect block X Y Z == KEY | expect ground X Y Z == true | expect player.y > N | expect fps.worst < N ...
//
// Notes: `load` loads round the player (the game's own streaming also runs during ticks). A field world (--headset)
// keeps natural ground as density, not blocks: `block` prints the block or the ground's material and whether a cell
// holds ground; `expect ground X Y Z == false` checks a dug or blasted cell.
enum SceneScript {
    // A scene with a `shot` line needs the Vulkan device (lavapipe) set up before anything else is made.
    static func wantsShots(_ path: String?) -> Bool {
        guard let p = path, let t = try? String(contentsOfFile: p, encoding: .utf8) else { return false }
        return t.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("shot ") }
    }

    static func run(path: String, device: MTLDevice, ctx: VkContext?) -> Int32 {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { print("scene: can't read \(path)"); return 2 }
        let args = CommandLine.arguments
        func arg(_ n: String) -> String? { args.firstIndex(of: n).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        let seed = UInt64(arg("--seed") ?? "") ?? 12345
        let headset = args.contains("--headset")
        let outDir = arg("--out") ?? FileManager.default.temporaryDirectory.appendingPathComponent("scene-shots").path
        // The world as --view makes it; --headset: a field world with polygon ground, as the headset makes new worlds.
        if headset { FieldTerrain.newWorlds = true }
        // --save: a world kept on disk as the headset keeps one (a fresh temp folder): chunks past the active distance
        // become shells, edited chunks are saved, mobs leaving the loaded land are stashed in mobs.json's table
        let save: SaveManager? = args.contains("--save") ? SaveManager(dir: FileManager.default.temporaryDirectory.appendingPathComponent("scene-world-\(getpid())")) : nil
        var w = World(seed: seed, device: device, save: save)
        w.renderDistance = Int(arg("--rd") ?? "") ?? 4
        if let a = Int(arg("--active") ?? "") { w.activeDistance = a }
        if headset { w.makeFieldWorld() }
        var g = Game(world: w, save: save, persistent: save != nil)
        if headset { g.smoothTerrain = true; SmoothTerrain.use(world: true, world: w) }
        g.paused = false; g.survival = false
        g.time = 0.25 * DAY_LENGTH
        g.player.pos = g.findSpawn()
        var bot = Agent(game: g, world: w)
        TroopVanish.on = true; TroopVanish.reset()
        var held = AgentAction()                      // what the bot holds down between ticks (walk, attack)
        var tickMs: [Double] = []
        var fails = 0
        var ship: Ship?
        var train: Trains.Train?
        var walkThere: Float?, walkLowest: Float?, walkStep: Float?
        // (`stream on`: every second of play the land round him is loaded before the next tick, as a headset's streaming
        // keeps up in real time; the harness plays faster than real time and a train could run off the loaded land)
        var streamSync = false
        let loops0 = Railways.loopsOn
        defer { Railways.loopsOn = loops0 }
        func coachList() -> [Mob] { train?.cars.filter { $0.variant == Trains.coach } ?? [] }
        // The floors' step where coach b meets coach a: b's near end's aisle height in a's frame, less a's aisle (1.25).
        func coupling(_ sa: Ship, _ sb: Ship) -> Float {
            let e0 = sa.toLocal(sb.toWorld(V3(1.5, 1.25, 0))), e1 = sa.toLocal(sb.toWorld(V3(1.5, 1.25, Float(sb.grid.sz))))
            let mid = Float(sa.grid.sz) / 2
            return (abs(e0.z - mid) < abs(e1.z - mid) ? e0.y : e1.y) - 1.25
        }

        func Y(_ s: Substring) -> Int? { Int(s).map { $0 + YOFF } }
        func key(_ b: BlockID) -> String { Blocks.key(b) }
        func f1(_ v: Float) -> String { String(format: "%.2f", v) }
        // Every soldier seen in the world, and those that died (where, and how far from him then): `print troops`.
        var seenTroops: [ObjectIdentifier: Mob] = [:]
        var troopDeaths: [String] = []
        func watchTroops() {
            for m in g.mobs.mobs where m.kind.steelhold && m.kind != .deckGun && !m.kind.ashVehicle {
                if seenTroops[ObjectIdentifier(m)] == nil { seenTroops[ObjectIdentifier(m)] = m }
            }
            for (id, m) in seenTroops where m.health <= 0 {
                seenTroops.removeValue(forKey: id)
                troopDeaths.append(String(format: "%@ at %.0f %.0f %.0f (%.0f from him)", m.kind.key, m.pos.x, m.pos.y - Float(YOFF), m.pos.z, simd_length(m.pos - g.player.pos)))
            }
        }
        // (`realtime on`: each tick waits out its 1/72 s, so the workers' generation keeps the pace it keeps in play)
        var realtime = false
        func step(_ a: AgentAction) {
            bot.apply(a)
            let t0 = CFAbsoluteTimeGetCurrent()
            g.tick(1.0 / 72)
            let el = CFAbsoluteTimeGetCurrent() - t0
            tickMs.append(el * 1000)
            watchTroops()
            if realtime && el < 1.0 / 72 { usleep(useconds_t((1.0 / 72 - el) * 1_000_000)) }
        }
        func play(_ secs: Double, _ a: AgentAction? = nil) {
            tickMs.removeAll(keepingCapacity: true)
            for k in 0..<max(1, Int(secs * 72)) {
                if streamSync && k % 72 == 0 { _ = w.loadSync(center: g.player.pos, radius: max(4, w.renderDistance)) }
                step(a ?? held)
            }
        }
        // Turn the eye onto a point through the mouse path (one tick of look), as a player would.
        func aim(_ p: V3) {
            let d = p - g.player.eye
            let yaw = atan2f(-d.x, -d.z), pitch = atan2f(d.y, simd_length(V2(d.x, d.z)))
            var a = AgentAction()
            var dy = yaw - g.player.yaw
            while dy > .pi { dy -= 2 * .pi }; while dy < -.pi { dy += 2 * .pi }
            a.yaw = dy; a.pitch = pitch - g.player.pitch
            step(a)
            g.player.yaw = yaw; g.player.pitch = pitch      // (the mouse path clamps and scales: land exactly)
        }
        func cellText(_ x: Int, _ y: Int, _ z: Int) -> String {
            let b = w.block(x, y, z), m = w.materialAt(x, y, z), gr = w.groundAt(x, y, z)
            return b != AIR ? key(b) : (gr ? "ground(\(key(m)))" : key(b))
        }
        var lastChanged = 0, placedCount = 0, placedOff = 0
        func targetText() -> String {
            guard let tg = g.target else { return "aimed at nothing" }
            var s = "aimed at \(tg.hit.x) \(tg.hit.y - YOFF) \(tg.hit.z) face \(tg.normal.x) \(tg.normal.y) \(tg.normal.z) (\(cellText(tg.hit.x, tg.hit.y, tg.hit.z)))"
            if let gr = g.targetGround, gr.cell == tg.hit { s += ", ground point \(f1(gr.at.x)) \(f1(gr.at.y - Float(YOFF))) \(f1(gr.at.z)) normal \(f1(gr.normal.x)) \(f1(gr.normal.y)) \(f1(gr.normal.z))" }
            let fc = tg.hit + tg.normal
            s += ", face cell \(fc.x) \(fc.y - YOFF) \(fc.z) \(cellText(fc.x, fc.y, fc.z)) d \(f1(w.fieldDensity(fc.x, fc.y, fc.z)))"
            if !g.held.isEmpty, let bi = g.held.def.block { let c = g.placeCell(tg, for: bi); s += ", a block would go in \(c.x) \(c.y - YOFF) \(c.z)" }
            return s
        }
        func value(_ name: String) -> Float? {
            let p = g.player
            switch name {
            case "player.x": return p.pos.x
            case "player.y": return p.pos.y - Float(YOFF)
            case "player.z": return p.pos.z
            case "player.speed": return simd_length(p.vel)
            case "player.health": return Float(g.health)
            case "ship.speed": return ship.map { simd_length($0.vel) }
            case "ship.blocks": return ship.map { Float($0.blockCount) }
            case "ship.y": return ship.map { $0.pos.y - Float(YOFF) }
            // (ledgers 226-228: the felled trees lying or falling in the world: how many, the blocks in them, how far
            // from level the most tilted trunk is (0 lying flat, 1 standing or upside down), the fastest one's spin)
            case "felled.count": return Float(w.ships.list.filter { Felling.isFelled($0) }.count)
            case "felled.blocks": return Float(w.ships.list.filter { Felling.isFelled($0) }.reduce(0) { $0 + $1.blockCount })
            case "felled.tilt": return w.ships.list.filter { Felling.isFelled($0) }.map { abs($0.rot.act(V3(0, 1, 0)).y) }.max()
            case "felled.spin": return w.ships.list.filter { Felling.isFelled($0) }.map { simd_length($0.angVel) }.max()
            case "train.speed": return train?.blocksPerSec
            case "walk.there": return walkThere
            case "walk.lowest": return walkLowest
            case "walk.step": return walkStep
            case "fps.worst": return tickMs.max().map { Float($0) }
            case "use.changed": return Float(lastChanged)
            case "place.count": return Float(placedCount)
            case "place.off": return Float(placedOff)
            case "fps.avg": return tickMs.isEmpty ? nil : Float(tickMs.reduce(0, +) / Double(tickMs.count))
            // (round 1 of the bug hunt: riding, aboard, on the ground, stuck in blocks, the nearest car, the coach he is in)
            case "riding": return g.riding == nil ? 0 : 1
            case "aboard": return w.ships.aboard == nil ? 0 : 1
            case "player.ground": return p.onGround ? 1 : 0
            case "player.inblock":
                // (aboard a hull, in its frame: the world's test counts the hull he stands in as a whole box round it,
                // so standing in a coach's aisle read as stuck; seated, his body is in the seat by design: not read)
                if g.riding != nil { return nil }
                if let s = w.ships.aboard {
                    let l = s.toLocal(p.pos)
                    w.frame = s; defer { w.frame = nil }
                    return w.collides(l + V3(-0.25, 0.05, -0.25), l + V3(0.25, 1.7, 0.25)) ? 1 : 0
                }
                return w.collides(p.pos + V3(-0.25, 0.05, -0.25), p.pos + V3(0.25, 1.7, 0.25)) ? 1 : 0
            case "player.falling": return p.vel.y < -6 ? 1 : 0
            case "train.dist": return nearestTrain().map { simd_length($0.1.pos - p.pos) }
            // hud.clash: on the HUD's vehicle panels (1280x800), words that a gauge bar covers, plus every panel past the
            // first (two panels drawn at once)
            case "hud.clash":
                let L = HudLayout(1280, 800), s = L.s
                let ls = CombatHUD.shared.lines(g, L)
                let bars = ls.filter { $0.text.isEmpty && $0.item == nil && ($0.box?.y ?? 99 * s) <= 7 * s && ($0.box?.x ?? 0) > 0.5 }
                let panels = ls.filter { $0.text.isEmpty && ($0.box?.y ?? 0) > 20 * s && ($0.bg?.w ?? 0) <= 0.55 }.count
                var n = max(0, panels - 1)
                for t in ls where !t.text.isEmpty {
                    let x1 = t.x + Float(Font.width(t.text)) * t.scale, y1 = t.y + 7 * t.scale
                    for b in bars { if let bb = b.box, b.x < x1 - 0.5, b.x + bb.x > t.x + 0.5, b.y < y1 - 0.5, b.y + bb.y > t.y + 0.5 { n += 1 } }
                }
                return Float(n)
            case "train.cars": return train.map { Float($0.cars.count) }
            // troops.near: soldiers (not vehicles or deck guns) within 96 blocks of him; troops.stored: soldiers stashed
            // with unloaded ground within 96 blocks (they come back when it loads); troops.vanished: soldiers taken out
            // of the world without dying since the scene began (TroopVanish, every rule)
            case "troops.near": return Float(troops(96).count)
            case "troops.stored": return Float(storedTroops(96))
            case "troops.vanished": return Float(TroopVanish.counts.values.reduce(0) { $0 + $1.all })
            case "coach": return Float(coachList().firstIndex { c in
                    guard let h = TrainHulls.hull(c) else { return false }
                    let l = h.toLocal(p.pos)
                    return l.x > -0.2 && l.x < Float(h.grid.sx) + 0.2 && l.z > -0.2 && l.z < Float(h.grid.sz) + 0.2 && l.y > -0.5 && l.y < Float(h.grid.sy)
                }.map { $0 + 1 } ?? 0)
            default: return Float(name)
            }
        }
        func isTroop(_ k: MobKind) -> Bool { k.steelhold && k != .deckGun && !k.ashVehicle }
        func troops(_ r: Float) -> [Mob] {
            g.mobs.mobs.filter { isTroop($0.kind) && $0.health > 0 && simd_length(V2($0.pos.x - g.player.pos.x, $0.pos.z - g.player.pos.z)) < r }
        }
        func storedTroops(_ r: Float) -> Int {
            var n = 0
            for (_, rs) in g.mobs.stored { for rec in rs where rec.p.count == 3 {
                guard let k = MobKind.named(rec.k), isTroop(k), simd_length(V2(rec.p[0] - g.player.pos.x, rec.p[2] - g.player.pos.z)) < r else { continue }
                n += 1
            } }
            return n
        }
        func nearestTrain() -> (Trains.Train, Mob)? {
            var best: (Trains.Train, Mob)?, bd = Float.infinity
            for t in Trains.trains.values { for c in t.cars {
                let d = simd_length(c.pos - g.player.pos)
                if d < bd { bd = d; best = (t, c) }
            } }
            return best
        }

        for (n, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            if line.isEmpty { continue }
            let t = line.split(separator: " ", omittingEmptySubsequences: true)
            let ln = "scene \(n + 1): \(line):"
            func bad() { print("FAIL \(ln) can't read it"); fails += 1 }
            switch t[0] {
            case "at":
                guard t.count == 4, let x = Float(t[1]), let y = Float(t[2]), let z = Float(t[3]) else { bad(); continue }
                g.player.pos = V3(x, y + Float(YOFF), z); g.player.vel = .zero
                w.activeCenter = g.player.pos
                print("\(ln) player at \(f1(x)) \(f1(y)) \(f1(z))")
            case "look":
                guard t.count == 3, let yd = Float(t[1]), let pd = Float(t[2]) else { bad(); continue }
                g.player.yaw = -yd * .pi / 180; g.player.pitch = pd * .pi / 180
                print("\(ln) facing \(yd), pitch \(pd)")
            case "load":
                guard t.count == 2, let r = Int(t[1]) else { bad(); continue }
                let (gen, mesh) = w.loadSync(center: g.player.pos, radius: r)
                w.activeCenter = g.player.pos
                print("\(ln) \(w.chunks.count) chunks (gen \(f1(Float(gen))) s, mesh \(f1(Float(mesh))) s)")
            case "tick":
                guard t.count == 2, let s = Double(t[1]) else { bad(); continue }
                play(s)
                print("\(ln) \(tickMs.count) ticks, avg \(f1(Float(tickMs.reduce(0, +) / Double(max(1, tickMs.count))))) ms, worst \(f1(Float(tickMs.max() ?? 0))) ms")
            case "fly" where (t.count == 5 || t.count == 6) && t[1] == "to":
                // fly to X Z SECONDS: flying flat out (sprint held) toward a point through the input path, the eye kept
                // on it each tick, as he flies across the land in Creative; stops there or after SECONDS
                guard let tx = Float(t[2]), let tz = Float(t[3]), let secs = Double(t[4]) else { bad(); continue }
                let cap = t.count == 6 ? Float(t[5]) ?? .infinity : .infinity      // (SPEED: blocks a second at most, as he flew)
                g.player.flying = true
                let p0 = g.player.pos
                var k = 0
                tickMs.removeAll(keepingCapacity: true)
                while k < Int(secs * 72) {
                    let d = V2(tx - g.player.pos.x, tz - g.player.pos.z)
                    if simd_length(d) < 2 { break }
                    if streamSync && k % 72 == 0 { _ = w.loadSync(center: g.player.pos, radius: max(4, w.renderDistance)) }
                    let yaw = atan2f(-d.x, -d.y)
                    var a = AgentAction(); a.forward = simd_length(V2(g.player.vel.x, g.player.vel.z)) < cap ? 1 : 0; a.sprint = cap.isInfinite
                    var dy = yaw - g.player.yaw
                    while dy > .pi { dy -= 2 * .pi }; while dy < -.pi { dy += 2 * .pi }
                    a.yaw = dy; a.pitch = -g.player.pitch
                    step(a); g.player.yaw = yaw
                    k += 1
                }
                step(AgentAction())
                print("\(ln) flew \(f1(simd_length(g.player.pos - p0))) blocks in \(f1(Float(k) / 72)) s, at \(f1(g.player.pos.x)) \(f1(g.player.pos.y - Float(YOFF))) \(f1(g.player.pos.z)); \(w.chunks.count) chunks loaded")
            case "survival", "fly":
                guard t.count == 2 else { bad(); continue }
                if t[0] == "survival" { g.survival = t[1] == "on" } else { g.player.flying = t[1] == "on" }
                print("\(ln) \(t[0]) \(t[1])")
            case "give":
                guard t.count >= 2, Items.has(String(t[1])) else { bad(); continue }
                let s = ItemStack(Items.id(String(t[1])), t.count > 2 ? Int(t[2]) ?? 1 : 1)
                _ = g.inventory.add(g.inventory.held); g.inventory.held = s       // (in his hand; what he held goes to the pack)
                print("\(ln) holding \(g.held.isEmpty ? "nothing" : Items.key(g.held.item))")
            case "block":
                guard t.count == 4, let x = Int(t[1]), let y = Y(t[2]), let z = Int(t[3]) else { bad(); continue }
                print("\(ln) \(cellText(x, y, z))")
            case "set":
                guard t.count == 5, let x = Int(t[1]), let y = Y(t[2]), let z = Int(t[3]), Blocks.has(String(t[4])) else { bad(); continue }
                w.setBlock(x, y, z, Blocks.id(String(t[4])))
                print("\(ln) now \(cellText(x, y, z))")
            case "break":
                // The player's own break: the eye turned onto the cell's middle, the attack held until it is gone (10 s at most).
                guard t.count == 4, let x = Int(t[1]), let y = Y(t[2]), let z = Int(t[3]) else { bad(); continue }
                let was = cellText(x, y, z)
                aim(V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5))
                var a = AgentAction(); a.attack = true
                var k = 0
                while k < 720 && (w.block(x, y, z) != AIR || w.groundAt(x, y, z)) { step(a); k += 1 }
                step(AgentAction())
                print("\(ln) \(was) -> \(cellText(x, y, z)) after \(k) ticks (aimed at \(g.target.map { "\($0.hit.x) \($0.hit.y - YOFF) \($0.hit.z)" } ?? "nothing"))")
            case "place":
                // The held block placed as he places it: the eye on the top of the cell under X Y Z, one press of use.
                guard t.count == 4, let x = Int(t[1]), let y = Y(t[2]), let z = Int(t[3]) else { bad(); continue }
                aim(V3(Float(x) + 0.5, Float(y) - 0.02, Float(z) + 0.5))
                var a = AgentAction(); a.use = true
                step(a); step(AgentAction())
                print("\(ln) \(cellText(x, y, z)) (aimed at \(g.target.map { "\($0.hit.x) \($0.hit.y - YOFF) \($0.hit.z)" } ?? "nothing"))")
            case "aimat":
                // aimat X Y Z: the eye turned onto a point (floats, display y), as the mouse turns it; prints the target.
                guard t.count == 4, let x = Float(t[1]), let y = Float(t[2]), let z = Float(t[3]) else { bad(); continue }
                aim(V3(x, y + Float(YOFF), z)); step(AgentAction())
                print("\(ln) \(targetText())")
            case "use", "hit":
                // use: one press of use as he aims now (look / aimat); prints what was aimed at and every cell of the box
                // round it that changed (block or ground).
                var before: [IVec3: String] = [:]
                let c0 = g.target?.hit ?? IVec3(Int(floor(g.player.eye.x)), Int(floor(g.player.eye.y)), Int(floor(g.player.eye.z)))
                for dy in -3...3 { for dz in -3...3 { for dx in -3...3 { let c = c0 + IVec3(dx, dy, dz); before[c] = cellText(c.x, c.y, c.z) } } }
                let tt = targetText()
                // (where he pointed: the drawn ground's point, or the face of the block aimed at)
                let tg0 = g.target, gp0 = g.targetGround.flatMap { gr in gr.cell == tg0?.hit ? gr.at : nil }
                let heldKey = g.held.isEmpty ? "" : (g.held.def.block.map { key($0) } ?? "")
                var a = AgentAction()
                if t[0] == "hit" { a.attack = true } else { a.use = true }
                // (use|hit [SECONDS]: held that long, as a trigger pull; one tick by default)
                let holdTicks = t.count > 1 ? max(1, Int((Double(t[1]) ?? 0) * 72)) : 1
                for _ in 0..<holdTicks { step(a) }
                step(AgentAction())
                var ch: [String] = []
                for (c, was) in before.sorted(by: { ($0.key.y, $0.key.z, $0.key.x) < ($1.key.y, $1.key.z, $1.key.x) }) {
                    let now = cellText(c.x, c.y, c.z)
                    if now != was { ch.append("\(c.x) \(c.y - YOFF) \(c.z) \(was) -> \(now)") }
                }
                lastChanged = ch.count
                // A placed block is off when it is neither the cell past the face aimed at nor within half a block of the drawn point
                // he pointed at (ledger 260's sweep: the block went two cells along, or diagonal).
                if t[0] == "use", let tg = tg0, !heldKey.isEmpty,
                   let c = before.keys.sorted(by: { ($0.y, $0.z, $0.x) < ($1.y, $1.z, $1.x) }).first(where: { cellText($0.x, $0.y, $0.z) == heldKey && before[$0] != heldKey }) {
                    var off = c != tg.hit + tg.normal
                    if let p = gp0 {
                        let lo = V3(Float(c.x), Float(c.y), Float(c.z))
                        let e = simd_max(simd_max(lo - p, p - lo - 1), V3(repeating: 0)); let d = max(e.x, max(e.y, e.z))
                        off = off && d > 0.5          // (ledger 131 lays a block at the nearest floor: up to half a block over the surface)
                    }
                    placedCount += 1
                    if off { placedOff += 1; print("  (off: placed at \(c.x) \(c.y - YOFF) \(c.z))") }
                }
                print("\(ln) \(tt); \(ch.count) changed\(ch.isEmpty ? "" : ": " + ch.joined(separator: "; "))")
            case "probe":
                // probe X Y Z: the cell's two layers, its density, and the drawn surface over its column's middle.
                guard t.count == 4, let x = Int(t[1]), let y = Y(t[2]), let z = Int(t[3]) else { bad(); continue }
                let top = w.fieldRaySegment(V3(Float(x) + 0.5, Float(y) + 4, Float(z) + 0.5), V3(0, -1, 0), from: 0, to: 8)
                print("\(ln) block \(key(w.block(x, y, z))), built \(key(w.builtBlock(x, y, z))), ground \(w.groundAt(x, y, z)), material \(key(w.materialAt(x, y, z))), density \(f1(w.fieldDensity(x, y, z))), at middle \(f1(w.fieldDensity(at: V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)))), surface \(top.map { f1($0.at.y - Float(YOFF)) } ?? "none") (cell \(top.map { "\($0.cell.x) \($0.cell.y - YOFF) \($0.cell.z)" } ?? "-"))")
            case "blast":
                // As --blasts: the blast, then half a second of play, then the ground's weighings played out (a minute at most).
                guard t.count >= 4, let x = Float(t[1]), let y = Float(t[2]), let z = Float(t[3]) else { bad(); continue }
                let p = t.count > 4 ? Float(t[4]) ?? 4 : 4
                let f0 = GroundWeigh.fell
                Explosion.explode(at: V3(x, y + Float(YOFF), z), power: p, game: g)
                play(0.5)
                var extra = 0
                while w.groundWeigh.busy && extra < 60 * 72 { step(held); extra += 1 }
                print("\(ln) power \(p); \(GroundWeigh.fell - f0) ground cells came down; \(extra) more ticks till still")
            case "ground":
                // A box of natural ground (a field world's density, as the ground weigh checks make their fixtures) of
                // a material (dirt, stone...) or `air` to clear it; meshed again after.
                // (ground X0 Y0 Z0 X1 Y1 Z1 MAT DENSITY: the cells' centre density in blocks, e.g. 0.03 for the sliver a dig
                // used to leave; a whole cell, 1, by default)
                let dv: Int8 = t.count == 9 ? FieldTerrain.q(Float(t[8]) ?? 1) : 32
                guard t.count == 8 || t.count == 9, let x0 = Int(t[1]), let y0 = Y(t[2]), let z0 = Int(t[3]),
                      let x1 = Int(t[4]), let y1 = Y(t[5]), let z1 = Int(t[6]), w.fieldTerrain else { bad(); continue }
                let mat: UInt8? = t[7] == "air" ? nil : (Blocks.has(String(t[7])) ? FieldMat.index[Int(Blocks.id(String(t[7])))] : nil)
                guard t[7] == "air" || (mat ?? 0) != 0 else { print("FAIL \(ln) \(t[7]) is not a ground material"); fails += 1; continue }
                var cells = 0
                for z in min(z0, z1)...max(z0, z1) { for x in min(x0, x1)...max(x0, x1) {
                    guard let c = w.chunkAt(x, z) else { continue }
                    for y in min(y0, y1)...max(y0, y1) {
                        c.blocks.setDensity(Chunk.index(mod(x, CS), y, mod(z, CS)), mat != nil ? dv : -32, material: mat)
                        if mat == nil, w.builtBlock(x, y, z) != AIR { w.setBlock(x, y, z, AIR) }
                        cells += 1
                    }
                } }
                w.remeshArea(x0: min(x0, x1) - 1, z0: min(z0, z1) - 1, x1: max(x0, x1) + 1, z1: max(z0, z1) + 1, y0: min(y0, y1) - 1, y1: max(y0, y1) + 1)
                print("\(ln) \(cells) cells of \(t[7])")
            case "dump":
                guard t.count == 7, let x0 = Int(t[1]), let y0 = Y(t[2]), let z0 = Int(t[3]),
                      let x1 = Int(t[4]), let y1 = Y(t[5]), let z1 = Int(t[6]) else { bad(); continue }
                let xs = min(x0, x1)...max(x0, x1), ys = min(y0, y1)...max(y0, y1), zs = min(z0, z1)...max(z0, z1)
                guard xs.count * ys.count * zs.count <= 4096 else { print("FAIL \(ln) more than 4,096 cells"); fails += 1; continue }
                print("\(ln)")
                for y in ys.reversed() { for z in zs {
                    // one row a line, runs of the same cell joined: "x0..x1 key"
                    var runs: [String] = [], start = xs.lowerBound, last = cellText(start, y, z)
                    for x in xs.dropFirst() { let c = cellText(x, y, z); if c != last { runs.append("\(start)..\(x - 1) \(last)"); start = x; last = c } }
                    runs.append("\(start)..\(xs.upperBound) \(last)")
                    print("  y \(y - YOFF) z \(z): " + runs.joined(separator: ", "))
                } }
            case "shot":
                guard t.count >= 2 else { bad(); continue }
                guard let c = ctx else { print("FAIL \(ln) no Vulkan device (lavapipe)"); fails += 1; continue }
                try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
                let out = (outDir as NSString).appendingPathComponent(String(t[1]))
                let wd = t.count > 2 ? Int(t[2]) ?? 640 : 640, ht = t.count > 3 ? Int(t[3]) ?? 640 : 640
                do {
                    try RenderTest.render(game: g, ctx: c, path: out, width: wd, height: ht, yaw: g.player.yaw, pitch: g.player.pitch, fovDeg: 90)
                    print("\(ln) wrote \(out)")
                } catch { print("FAIL \(ln) \(error)"); fails += 1 }
            case "spawn":
                guard t.count == 3 else { bad(); continue }
                let ahead = g.player.pos + V3(-sinf(g.player.yaw), 0, -cosf(g.player.yaw)) * 6
                if t[1] == "mob" {
                    guard let k = MobKind.named(String(t[2])) else { print("FAIL \(ln) no mob kind \(t[2])"); fails += 1; continue }
                    g.mobs.mobs.append(Mob(k, at: w.freeSpawn(ahead)))
                    print("\(ln) a \(k.key) at \(f1(ahead.x)) \(f1(ahead.z))")
                } else if t[1] == "vessel" {
                    let helm = ShipTest.place(w, String(t[2]), near: ahead)
                    let (s, msg) = w.ships.assemble(at: helm, game: g)
                    ship = s
                    if let s = s { print("\(ln) \(s.name), \(s.blockCount) blocks, helm at \(helm.x) \(helm.y - YOFF) \(helm.z)") }
                    else { print("FAIL \(ln) \(msg)"); fails += 1 }
                } else { bad() }
            case "ride" where t.count >= 5 && t[1] == "until" && t[2] == "step":
                // ride until step N MIN [SECONDS]: play on (standing where he is) until the floors' step between coach N-1 and
                // coach N is MIN or more either way: the train on a change of grade.
                guard let k = Int(t[3]), let mn = Float(t[4]) else { bad(); continue }
                let secs = t.count > 5 ? Double(t[5]) ?? 120 : 120
                let cs = coachList()
                guard k >= 2, k <= cs.count, let sb = TrainHulls.hull(cs[k - 1]), let sa = TrainHulls.hull(cs[k - 2]) else {
                    print("FAIL \(ln) the train has \(cs.count) coaches with hulls"); fails += 1; continue
                }
                var i = 0, most: Float = 0
                while i < Int(secs * 72) {
                    step(held); i += 1
                    let st = coupling(sa, sb)
                    if abs(st) > abs(most) { most = st }
                    if abs(st) >= mn { break }
                }
                let st = coupling(sa, sb)
                if abs(st) < mn { print("FAIL \(ln) no such step in \(f1(Float(secs))) s (most \(f1(most)))"); fails += 1; continue }
                print("\(ln) step \(f1(st)) after \(f1(Float(i) / 72)) s; train \(f1(train?.blocksPerSec ?? 0)) b/s, aboard \(w.ships.aboard?.name ?? "none")")
            case "ride" where t.count != 4 || t[1] != "train":
                guard t.count == 3, t[1] == "nearest" else { bad(); continue }
                if t[2] == "train" {
                    guard let tc = nearestTrain() else { print("FAIL \(ln) no train"); fails += 1; continue }
                    let car = tc.1
                    train = tc.0; _ = Trains.use(g, car)          // (boarding as he boards: a seat, the cab)
                    print("\(ln) aboard a \(car.kind.key) \(f1(simd_length(car.pos - g.player.pos))) blocks off")
                } else if t[2] == "ship" {
                    guard let s = ship ?? w.ships.list.min(by: { simd_length($0.pos - g.player.pos) < simd_length($1.pos - g.player.pos) }) else {
                        print("FAIL \(ln) no ship"); fails += 1; continue
                    }
                    ship = s; g.startPiloting(s)
                    print("\(ln) at the helm of \(s.name)")
                } else { bad() }
            case "drive":
                // The throttle held (the helm's or the cab's regulator) for SECONDS of play.
                guard t.count == 3, let th = Float(t[1]), let s = Double(t[2]) else { bad(); continue }
                if g.riding != nil, let tr = train { tr.throttle = th; play(s) }
                else if ship != nil { var a = AgentAction(); a.forward = th; play(s, a) }
                else { print("FAIL \(ln) not driving anything"); fails += 1; continue }
                print("\(ln) \(ship.map { "ship speed \(f1(simd_length($0.vel)))" } ?? "train \(f1(train?.blocksPerSec ?? 0)) b/s")")
            case "train":
                // train at station: the nearest line's passenger train, its clock run on to when it stands at the station
                // nearest him (as --rail-only's ledger 141 check sets it up; the line's own out-and-back timetable).
                guard t.count == 3, t[1] == "at", t[2] == "station" else { bad(); continue }
                guard let gen = w.gen as? WorldGen else { print("FAIL \(ln) no railways in this world (a field world? drop --headset)"); fails += 1; continue }
                let px = Int(floor(g.player.pos.x)), pz = Int(floor(g.player.pos.z))
                var best: (Railways.Line, Int)?, bd = Int.max
                for l in Railways.near(gen, x0: px - 3000, z0: pz - 3000, x1: px + 3000, z1: pz + 3000, pad: 0) where !l.cells.isEmpty {
                    for (i, st) in l.stations.enumerated() where !st.site {
                        let d = abs(st.x - px) + abs(st.z - pz)
                        if d < bd { bd = d; best = (l, i) }
                    }
                }
                guard let (l, si) = best else { print("FAIL \(ln) no line within 3000 blocks"); fails += 1; continue }
                Railways.loopsOn = false
                let st = l.stations[si], sc = l.cells[st.index]
                g.player.pos = V3(Float(sc.x) + 0.5, Float(sc.y), Float(sc.z - 2) + 0.5); g.player.vel = .zero
                _ = w.loadSync(center: g.player.pos, radius: max(4, w.renderDistance))
                Trains.trains.removeAll()
                let tk = Trains.track(l)
                var found = false
                for k in 0..<Int(tk.period) where tk.at(g.time + Double(k)).stop == si { g.time += Double(k) + 2; found = true; break }
                Trains.forceKind = .passenger
                Trains.tick(g)
                Trains.forceKind = nil
                train = Trains.trains[tk.id]
                guard found, let tr = train else { print("FAIL \(ln) no train came to \(st.name)"); fails += 1; continue }
                print("\(ln) \(l.name): at \(st.name) Station (\(sc.x) \(sc.y - YOFF) \(sc.z), \(bd) blocks off), \(tr.cars.count) cars, \(coachList().count) coaches")
            case "stand":
                // stand in coach N: in coach N's aisle (counted from 1 along the train), aboard it.
                guard t.count == 4, t[1] == "in", t[2] == "coach", let k = Int(t[3]) else { bad(); continue }
                let cs = coachList()
                guard k >= 1, k <= cs.count, TrainHulls.hull(cs[k - 1]) != nil else { print("FAIL \(ln) the train has \(cs.count) coaches with hulls"); fails += 1; continue }
                w.ships.aboard = nil
                g.player.flying = false
                g.player.pos = Trains.seat(cs[k - 1]) + V3(0, 0.05, 0); g.player.vel = .zero
                play(6.0 / 72)
                print("\(ln) aboard \(w.ships.aboard === TrainHulls.hull(cs[k - 1]) ? "it" : w.ships.aboard == nil ? "nothing" : "another hull"), on ground \(g.player.onGround)")
            case "walk" where t.count >= 4 && t[1] == "to":
                // walk to coach N [SECONDS]: forward toward coach N each tick (as ledger 141's check walks) until he is in its
                // aisle; the least height over the rail in whichever coach he is in, and the floors' step at the coupling.
                guard t[2] == "coach", let k = Int(t[3]) else { bad(); continue }
                let secs = t.count > 4 ? Double(t[4]) ?? 12 : 12
                let cs = coachList()
                // (to coach 1: back from coach 2)
                let ka = k >= 2 ? k - 2 : 1
                guard k >= 1, k <= cs.count, ka < cs.count, let sb = TrainHulls.hull(cs[k - 1]), let sa = TrainHulls.hull(cs[ka]) else {
                    print("FAIL \(ln) the train has \(cs.count) coaches with hulls"); fails += 1; continue
                }
                walkStep = coupling(sa, sb)
                var a = AgentAction(); a.forward = 1
                var there = false, took = 0, lowest: Float = 9
                for i in 0..<Int(secs * 72) {
                    let d = cs[k - 1].pos - g.player.pos
                    g.player.yaw = atan2f(-d.x, -d.z)
                    step(a)
                    let lb = sb.toLocal(g.player.pos)
                    lowest = min(lowest, w.ships.aboard === sb ? lb.y : sa.toLocal(g.player.pos).y)
                    if lb.x > 0.2 && lb.x < 2.8 && lb.z > 2 && lb.z < Float(sb.grid.sz) - 2 && lb.y > 1.15 && lb.y < 1.6 { there = true; took = i + 1; break }
                }
                step(AgentAction())
                walkThere = there ? 1 : 0; walkLowest = lowest
                print("\(ln) \(there ? "there in \(f1(Float(took) / 72)) s" : "not there"), never lower than \(f1(lowest)) over the rail; the floors' step at the coupling \(f1(walkStep ?? 0)); train \(f1(train?.blocksPerSec ?? 0)) b/s")
            case "walk":
                guard t.count == 3, t[1] == "forward", let s = Double(t[2]) else { bad(); continue }
                let p0 = g.player.pos
                var a = AgentAction(); a.forward = 1
                play(s, a)
                print("\(ln) moved \(f1(simd_length(g.player.pos - p0))) blocks")
            case "aboard" where t.count == 2 && t[1] == "engine":
                // aboard engine: the locomotive's hull counts him aboard, as walking up into its cab before taking the
                // regulator leaves it (ledger 243)
                guard let tr = train, let eng = tr.cars.first(where: { Trains.isEngine($0) }), let h = TrainHulls.hull(eng) else {
                    print("FAIL \(ln) no engine hull"); fails += 1; continue
                }
                w.ships.aboard = h
                print("\(ln) aboard \(h.name)")
            case "print":
                guard t.count == 2 else { bad(); continue }
                let p = g.player
                switch t[1] {
                case "player":
                    print("\(ln) at \(f1(p.pos.x)) \(f1(p.pos.y - Float(YOFF))) \(f1(p.pos.z)), speed \(f1(simd_length(p.vel))), health \(g.health), held \(g.held.isEmpty ? "nothing" : Items.key(g.held.item)), riding \(g.riding?.kind.key ?? "nothing"), helm \(w.ships.pilot?.name ?? "none"), aboard \(w.ships.aboard?.name ?? "none")")
                    // (stuck: the cells whose boxes his body overlaps, with what is there)
                    let mn = p.pos + V3(-0.25, 0.05, -0.25), mx = p.pos + V3(0.25, 1.7, 0.25)
                    if w.collides(mn, mx) {
                        var hits: [String] = []
                        for y in Int(floor(mn.y))...Int(floor(mx.y)) { for z in Int(floor(mn.z))...Int(floor(mx.z)) { for x in Int(floor(mn.x))...Int(floor(mx.x)) {
                            let c0 = V3(Float(x), Float(y), Float(z))
                            if w.collides(simd_max(mn, c0), simd_min(mx, c0 + V3(1, 1, 1))) { hits.append("\(x) \(y - YOFF) \(z) \(cellText(x, y, z))") }
                        } } }
                        print("\(ln) in blocks: " + hits.joined(separator: "; "))
                    }
                case "train":
                    print("\(ln) " + (train.map { "\(f1($0.blocksPerSec)) b/s, throttle \(f1($0.throttle)), brake \(f1($0.brake)), \($0.cars.count) cars" } ?? "none"))
                case "ship":
                    print("\(ln) " + (ship.map { "\($0.name) at \(f1($0.pos.x)) \(f1($0.pos.y - Float(YOFF))) \(f1($0.pos.z)), speed \(f1(simd_length($0.vel))), hull \($0.blockCount) blocks" } ?? "none"))
                case "station":
                    // the Boreal Station nearest him: its centre, how far, the soldiers inside its fence and bunker
                    if let sc = w.gen.structures, let st = sc.nearest(BorealStation.kind, x: Int(p.pos.x), z: Int(p.pos.z), maxRegions: 4) {
                        let cx = (st.min.x + st.max.x) / 2, cz = (st.min.z + st.max.z) / 2
                        let site = BorealAlarmState.Site(cx: cx, cz: cz, S: st.min.y + BorealStation.depth + 4)
                        let n = g.mobs.mobs.filter { BorealMuster.soldier($0) && $0.health > 0 && BorealStation.insideSite(site, $0.pos) }.count
                        print("\(ln) station at \(cx) \(site.S - YOFF) \(cz), \(f1(simd_length(V2(Float(cx) - p.pos.x, Float(cz) - p.pos.z)))) away, \(BorealStation.insideSite(site, p.pos) ? "he is inside" : "he is outside"); \(n) soldiers inside; \(g.bases.boreal.log.suffix(3).joined(separator: "; "))")
                    } else { print("\(ln) no station") }
                case "troops":
                    // every soldier within 96 blocks by kind and side, the stashed ones, and what took any away
                    var by: [String: Int] = [:]
                    for m in troops(96) { by["\(m.kind.key)/\(m.factionValue)", default: 0] += 1 }
                    let guns = g.mobs.mobs.filter { $0.kind == .deckGun && simd_length(V2($0.pos.x - p.pos.x, $0.pos.z - p.pos.z)) < 96 }.count
                    print("\(ln) \(troops(96).count) soldiers within 96 (\(by.keys.sorted().map { "\($0) \(by[$0]!)" }.joined(separator: ", "))), \(guns) deck guns, \(storedTroops(96)) stashed; pending \(w.pendingMobs.count); gone: \(TroopVanish.line); died \(troopDeaths.count)\(troopDeaths.isEmpty ? "" : ": " + troopDeaths.prefix(8).joined(separator: "; "))")
                case "fps":
                    let avg = tickMs.isEmpty ? 0 : tickMs.reduce(0, +) / Double(tickMs.count)
                    print("\(ln) last \(tickMs.count) ticks: avg \(f1(Float(avg))) ms, worst \(f1(Float(tickMs.max() ?? 0))) ms")
                default: bad()
                }
            case "reopen" where t.count == 1:
                // reopen: the world saved and closed, then opened again from its save as the headset opens a world
                // (QuestApp.load: World + Game on the save, WorldRequest.setUp with its meta); needs --save
                guard let sv = save else { print("FAIL \(ln) no --save"); fails += 1; continue }
                g.saveNow(); SaveIO.flush()
                let rd = w.renderDistance, ad = w.activeDistance
                let w2 = World(seed: seed, device: device, save: sv)
                w2.renderDistance = rd
                let g2 = Game(world: w2, save: sv, persistent: true)
                WorldRequest(name: nil, seed: nil, survival: nil, difficulty: nil).setUp(g2, meta: sv.loadMeta())
                g2.world.renderDistance = rd; g2.world.activeDistance = ad
                g2.paused = false
                w = w2; g = g2; bot = Agent(game: g2, world: w2)
                seenTroops.removeAll()
                print("\(ln) reopened at \(f1(g.player.pos.x)) \(f1(g.player.pos.y - Float(YOFF))) \(f1(g.player.pos.z)); field world \(w.fieldTerrain); \(g.mobs.stored.values.reduce(0) { $0 + $1.count }) mobs stashed")
            case "realtime" where t.count == 2:
                realtime = t[1] == "on"
                print("\(ln) real time: \(realtime)")
            case "stream" where t.count == 2:
                streamSync = t[1] == "on"
                print("\(ln) streaming kept up: \(streamSync)")
            case "time":
                // time FRAC: the day's clock (0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight), the day kept
                guard t.count == 2, let f = Double(t[1]) else { bad(); continue }
                g.time = (floor(g.time / DAY_LENGTH) + f) * DAY_LENGTH
                print("\(ln) day \(Int(g.time / DAY_LENGTH)) at \(f1(Float(f)))")
            case "hold":
                // hold sneak|jump|use|attack|sprint SECONDS: the key held through the input path, then let go
                guard t.count == 3, let secs = Double(t[2]) else { bad(); continue }
                var a = AgentAction()
                switch t[1] { case "sneak": a.sneak = true; case "jump": a.jump = true; case "use": a.use = true
                              case "attack": a.attack = true; case "sprint": a.sprint = true; a.forward = 1; default: bad(); continue }
                play(secs, a); step(AgentAction())
                print("\(ln) riding \(g.riding?.kind.key ?? "nothing"), aboard \(w.ships.aboard?.name ?? "none"), at \(f1(g.player.pos.x)) \(f1(g.player.pos.y - Float(YOFF))) \(f1(g.player.pos.z))")
            case "face" where t.count == 4 && t[1] == "train" && t[2] == "car":
                // face train car N: turn onto car N's middle (counted from 1 along the train), as he would to use it
                guard let k = Int(t[3]), let tr = train ?? nearestTrain()?.0, k >= 1, k <= tr.cars.count else { bad(); continue }
                train = tr
                aim(tr.cars[k - 1].pos + V3(0, 1.2, 0))
                print("\(ln) a \(tr.cars[k - 1].kind.key), \(f1(simd_length(tr.cars[k - 1].pos - g.player.pos))) blocks off")
            case "ride" where t.count == 4 && t[1] == "train" && t[2] == "car":
                // ride train car N: board car N as he boards (Trains.use: a coach's seat, the cab)
                guard let k = Int(t[3]), let tr = train ?? nearestTrain()?.0, k >= 1, k <= tr.cars.count else { bad(); continue }
                train = tr
                let used = Trains.use(g, tr.cars[k - 1])
                print("\(ln) \(used ? "used" : "nothing happened"): riding \(g.riding?.kind.key ?? "nothing")")
            case "expect":
                // expect block X Y Z == KEY | expect ground X Y Z == true|false | expect NAME OP NUMBER
                let ops = ["==", "!=", "<=", ">=", "<", ">"]
                guard let oi = t.firstIndex(where: { ops.contains(String($0)) }), oi + 1 < t.count else { bad(); continue }
                let op = String(t[oi]), rhs = t[(oi + 1)...].joined(separator: " "), lhs = Array(t[1..<oi])
                var ok = false, got = ""
                if lhs.first == "block" || lhs.first == "ground", lhs.count == 4, let x = Int(lhs[1]), let y = Y(lhs[2]), let z = Int(lhs[3]) {
                    if lhs[0] == "ground" { got = w.groundAt(x, y, z) ? "true" : "false" }
                    else { let b = w.block(x, y, z); got = b != AIR ? key(b) : (w.groundAt(x, y, z) ? key(w.materialAt(x, y, z)) : "air") }
                    let base = got.split(separator: "[").first.map(String.init) ?? got
                    let eq = got == rhs || base == rhs
                    ok = op == "==" ? eq : op == "!=" ? !eq : false
                } else if lhs.count == 1, let a = value(String(lhs[0])), let b = Float(rhs) {
                    got = f1(a)
                    switch op { case "==": ok = a == b; case "!=": ok = a != b; case "<": ok = a < b; case ">": ok = a > b
                                case "<=": ok = a <= b; default: ok = a >= b }
                } else { got = "nothing to read" }
                print((ok ? "ok   " : "FAIL ") + "\(ln) (\(got))")
                if !ok { fails += 1 }
            default:
                bad()
            }
        }
        print(fails == 0 ? "scene: all checks passed" : "scene: \(fails) FAILED")
        return fails == 0 ? 0 : 1
    }
}
