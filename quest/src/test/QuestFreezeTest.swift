import Foundation
import simd
import Metal

// P416 steps 1, 4: the Oct 23 freezes in the Greywall base (seed 7456738112706637949, about -1560 73 -2985): opening a
// bulkhead door dropped the game to 6-12 fps for seconds, mining a block there ran at 22 fps. A Polygons world at that
// spot with the garrison as the game spawns it, him in survival among them; then a door opened, closed, and a wall block broken, each
// followed by 3 s of ticks at 72 Hz. Reports the worst and average tick and the slowest stage of the worst one.
//   questcheck --freezetest [--rd 8]     target (step 4): no frame over 20 ms after a door or a break
enum QuestFreezeTest {
    static func arg(_ k: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: k), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        World.fluidSeconds = 0.002; World.handoverSeconds = 0.0015; World.lodNear = 99; World.leafNear = 99   // (QuestApp)
        StructureCache.plansOffThread = true            // (as in the game: the headless default plans bases in the tick, 295 ms here)
        defer { StructureCache.plansOffThread = false }
        let rd = Int(arg("--rd") ?? "") ?? 8
        TextureGen.registerAll()
        let w = World(seed: 7456738112706637949, device: sharedSystemDevice, save: nil)
        FieldTerrain.newWorlds = true; w.makeFieldWorld()
        w.renderDistance = rd
        let g = Game(world: w, save: nil, persistent: false)
        g.smoothTerrain = true
        SmoothTerrain.use(world: true, world: w)
        g.paused = false; g.menu = nil
        g.survival = true
        g.input.captured = true
        g.time = 0.4 * DAY_LENGTH
        g.player.pos = V3(-1562.2, Float(73 + YOFF), -2984.5)
        _ = w.loadSync(center: g.player.pos, radius: rd)
        g.tick(1.0 / 72)                                   // (the garrison comes in from the structure as the game admits it)
        // The doors and a wall block near him.
        var doors: [IVec3] = []
        let c = IVec3(-1562, 73 + YOFF, -2985)
        for dy in -3...3 { for dz in -12...12 { for dx in -12...12 {
            let p = IVec3(c.x + dx, c.y + dy, c.z + dz)
            if Blocks.key(Blocks.groupBase[Int(w.materialAt(p.x, p.y, p.z))]) == "bulkhead_door",
               Blocks.key(Blocks.groupBase[Int(w.materialAt(p.x, p.y - 1, p.z))]) != "bulkhead_door" { doors.append(p) }
        } } }
        doors.sort { simd_length(V3(Float($0.x - c.x), 0, Float($0.z - c.z))) < simd_length(V3(Float($1.x - c.x), 0, Float($1.z - c.z))) }
        print("freezetest: rd \(rd), \(g.mobs.mobs.count) mobs (\(g.mobs.mobs.filter { $0.kind.steelhold }.count) Steelhold), \(doors.count) bulkhead doors near")
        guard let door = doors.first else { print("FAIL freezetest: no bulkhead door near the note's spot"); return 1 }
        g.player.pos = V3(Float(door.x) + 0.5, Float(door.y), Float(door.z) + 2.5)
        var checks0 = Structure.checks
        Structure.tally = [:]
        func phase(_ name: String, seconds: Double = 3) -> Double {
            var worst = 0.0, sum = 0.0, n = 0, over = 0
            var worstStage = "-"
            var slowBy: [String: Int] = [:]
            for _ in 0..<Int(seconds * 72) {
                g.menu = nil
                g.health = 20; g.alive = true             // (the garrison is on him: he stands)
                let a = CFAbsoluteTimeGetCurrent()
                g.tick(1.0 / 72)
                let ms = (CFAbsoluteTimeGetCurrent() - a) * 1000
                sum += ms; n += 1
                if ms > 20 {
                    over += 1
                    let lead = TickProf.summary()
                    slowBy[String(lead.prefix(while: { !$0.isNumber }).trimmingCharacters(in: .whitespaces)), default: 0] += 1
                }
                if ms > worst { worst = ms; worstStage = TickProf.summary() }
            }
            print(String(format: "freezetest: %@: worst %.1f ms (%@), average %.1f ms, %d of %d frames over 20 ms; load checks %d (worst %.1f ms), queued %d", name, worst, worstStage, sum / Double(n), over, n,
                         Structure.checks - checks0, Structure.worstMs, g.world.loadQueue.count))
            checks0 = Structure.checks; Structure.worstMs = 0
            let slow = slowBy.sorted { $0.value > $1.value }.prefix(4).map { "\($0.key) x\($0.value)" }
            if !slow.isEmpty { print("freezetest:   slow frames led by " + slow.joined(separator: ", ")) }
            let top = (Structure.tally ?? [:]).sorted { $0.value > $1.value }.prefix(4).map { "\($0.key) x\($0.value)" }
            if !top.isEmpty { print("freezetest:   queued by " + top.joined(separator: ", ")) }
            Structure.tally = [:]
            return worst
        }
        _ = phase("settle", seconds: 4)
        _ = phase("among the garrison")
        // (P419 (b): why soldiers near him stand idle: their side, alert and what holds their fire)
        for m in g.mobs.mobs where m.kind.steelhold && m.health > 0 && simd_length(m.pos - g.player.pos) < 40 {
            let b = m.soldierBrain
            print(String(format: "freezetest: soldier %@ %.0f blocks: faction %d posse %d aggro %d lock %.0f sees %d allied %d sheltered %d disguised %d hired %d leash %d",
                         m.kind.key, simd_length(m.pos - g.player.pos), Int(m.faction), Int(m.posse), m.aggro ? 1 : 0, m.lockTime, b.sees ? 1 : 0,
                         g.repAllied(m) ? 1 : 0, GarrisonTown.shelters(g, m) ? 1 : 0, Disguise.covers(g, m) ? 1 : 0, m.hired ? 1 : 0, m.leash == nil ? 0 : 1))
            let e = m.pos + V3(0, m.height * 0.9, 0), pe = g.player.eye
            print(String(format: "freezetest:   dy %.1f, its eye in a block %d, his eye in a block %d, line of sight %d, station %d",
                         m.pos.y - g.player.pos.y, w.opaqueAt(Int(floor(e.x)), Int(floor(e.y)), Int(floor(e.z))) ? 1 : 0,
                         w.opaqueAt(Int(floor(pe.x)), Int(floor(pe.y)), Int(floor(pe.z))) ? 1 : 0, w.canSee(e, pe) ? 1 : 0, b.station.rawValue))
        }
        var worst = 0.0
        g.openBlock(door); worst = max(worst, phase("door opened at \(door.x) \(door.y - YOFF) \(door.z)"))
        g.openBlock(door); worst = max(worst, phase("door closed"))
        // A wall block beside the door (the 21:26:40 note mined the base's concrete).
        var wall: IVec3? = nil
        for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1), IVec3(2, 0, 0), IVec3(-2, 0, 0)] {
            let p = IVec3(door.x + d.x, door.y + 1, door.z + d.z)
            let b = w.block(p.x, p.y, p.z)
            if b != AIR && Blocks.key(Blocks.groupBase[Int(w.materialAt(p.x, p.y, p.z))]) != "bulkhead_door" { wall = p; break }
        }
        if let p = wall {
            g.breakBlock(p, w.block(p.x, p.y, p.z), drop: false)
            worst = max(worst, phase("wall block broken"))
        }
        // (the target is 20 ms on the headset's optimized build; this host build is unoptimized (-Onone), several times
        // slower, so it fails only past 100 ms: a freeze, not a slow frame)
        let limit = ProcessInfo.processInfo.environment["BS_FREEZE_MS"].flatMap { Double($0) } ?? 100
        if worst > limit { print(String(format: "FAIL freezetest: a frame took %.1f ms after a door or a break (limit %.0f)", worst, limit)); return 1 }
        return 0
    }
}
