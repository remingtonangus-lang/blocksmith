import Foundation
import simd

// --audiotest: headless checks of the game-side audio director. With `audio.record` set, Game.audioAmbientTick
// runs without an audio device and counts the loops it asks for ("loop:<key>") and the sounds it plays, so
// the wiring (vehicles, vessels, terrain beds, weather, combat music) is tested, not just the renders.
enum AudioTests {
    static func run(game g: Game, at start: V3, rd: Int) -> Int {
        let w = g.world
        var fails = 0
        func check(_ ok: Bool, _ what: String, _ info: String = "") {
            print("audiotest \(ok ? "PASS" : "FAIL"): \(what)\(info.isEmpty ? "" : " (\(info))")")
            if !ok { fails += 1 }
        }
        // Runs the director for `seconds` (20 Hz), with `step` advancing the scene each tick.
        func listen(_ seconds: Float, _ step: () -> Void = {}) -> [String: Int] {
            g.audio.record = [:]
            var t: Float = 0
            while t < seconds { step(); g.audioAmbientTick(0.05); t += 0.05 }
            let r = g.audio.record ?? [:]
            g.audio.record = nil
            return r
        }
        func heard(_ r: [String: Int], _ prefix: String) -> Bool { r.keys.contains { $0.hasPrefix(prefix) } }
        func loops(_ r: [String: Int]) -> String { r.keys.filter { $0.hasPrefix("loop:") }.sorted().joined(separator: " ") }
        func clearShips() { for s in w.ships.list { w.ships.remove(s) }; w.ships.pilot = nil; w.ships.aboard = nil }
        let t0 = CFAbsoluteTimeGetCurrent()
        w.ships.encounters = false
        g.weather.raining = false; g.weather.rain = 0
        g.time = 0.25 * DAY_LENGTH

        // 1. A car under way: engine and wheels.
        _ = w.loadSync(center: start, radius: max(4, min(rd, 6)))
        if case let (car?, _) = w.ships.assemble(at: ShipTest.place(w, "car", near: start), game: g) {
            g.startPiloting(car)
            var mi = MoveInput()
            mi.forward = 1
            ShipTest.run(g, seconds: 2, input: mi)
            let r = listen(2) { ShipTest.run(g, seconds: 0.05, input: mi) }
            let k = "loop:ship\(car.id)"
            let info = String(format: "speed %.1f, %@", simd_length(car.vel), loops(r))
            check(heard(r, k + "eng"), "car: engine heard while driving", info)
            // Wheels need motion; the vehicle physics has its own tests (--physicstest).
            if simd_length(car.vel) > 0.5 && car.grounded { check(heard(r, k + "wheel"), "car: wheels rumble while rolling", info) }
            else { print("audiotest SKIP: car not rolling (\(info))") }
            check((r["engineStart"] ?? 0) == 1, "car: the engine starts once", "\(r["engineStart"] ?? 0) starts")
            g.leaveHelm()
        } else { check(false, "car assembles") }
        clearShips()

        // 2. A plane in fast flight: propellers and wind over the wings.
        if case let (plane?, _) = w.ships.assemble(at: ShipTest.place(w, "plane", near: start), game: g) {
            g.startPiloting(plane)
            plane.vel = plane.dirToWorld(plane.fwd) * 22
            var mi = MoveInput()
            mi.forward = 1
            let r = listen(1.5) { ShipTest.run(g, seconds: 0.05, input: mi) }
            let k = "loop:ship\(plane.id)"
            check(heard(r, k + "prop") && heard(r, k + "rush"), "plane: propellers and wing rush in flight",
                  String(format: "speed %.1f, %@", simd_length(plane.vel), loops(r)))
            g.leaveHelm()
        } else { check(false, "plane assembles") }
        clearShips()

        // 3. The Skyward Frigate: its drone carries far, and its guns score combat music.
        do {
            let x = Int(floor(start.x)), z = Int(floor(start.z)) - 30
            let ground = ShipTest.groundTop(w, x, z)
            let s = w.ships.spawnVessel("frigate", home: IVec3(x, max(ground, SEA) + 40, z), game: nil)
            g.survival = true; g.alive = true; g.difficulty = 2
            g.player.flying = true
            g.player.pos = s.pos + V3(120, 0, 0)
            var r = listen(1)
            check(heard(r, "loop:vessel\(s.id)"), "frigate: engine drone heard from 120 blocks", loops(r))
            g.audio.combatCheck = 0; g.combatTick(0.05)
            check(g.combatLevel() == 1, "frigate nearby: tension", "level \(g.combatLevel())")
            g.player.pos = s.pos + V3(40, -6, 0)
            r = listen(1)
            g.audio.combatCheck = 0; g.combatTick(0.05)
            check(g.combatLevel() == 2, "frigate in gun range: combat music", "level \(g.combatLevel())")
            g.survival = false
            g.audio.combatHold = 0; g.audio.combatCheck = 0; g.combatTick(0.05)
        }
        clearShips()
        g.mobs.mobs.removeAll()

        // 4. Terrain beds by biome, and weather on top.
        func visit(_ biome: String) -> Bool {
            guard let p = Snapshot.findBiome(w.gen, biome) else { print("audiotest SKIP: no \(biome) near spawn"); return false }
            _ = w.loadSync(center: p, radius: 3)
            let x = Int(floor(p.x)), z = Int(floor(p.z))
            g.player.flying = true
            g.player.pos = V3(p.x, Float(w.topY(x, z) + 3), p.z)
            g.player.vel = .zero
            g.audio.cave = 0
            g.audio.biomeTimer = 0
            return true
        }
        for (biome, key, what) in [("jagged_peaks", "loop:mountainwind", "mountain wind on the peaks"),
                                   ("snowy_plains", "loop:tundrawind", "tundra wind on the snowy plains"),
                                   ("swamp", "loop:swampbugs", "insects over the swamp")] {
            guard visit(biome) else { continue }
            let r = listen(3)
            check(heard(r, key), what, loops(r))
        }
        if visit("snowy_plains") {
            g.weather.raining = true; g.weather.rain = 1
            let r = listen(2)
            check(heard(r, "loop:snowwind"), "snow wind while it snows", loops(r))
            check(r["loop:rain"] == nil && r["loop:rainleaves"] == nil, "no rain patter while it snows")
            g.weather.raining = false; g.weather.rain = 0
        }
        print(String(format: "audiotest: %ld failed (%.1f s)", fails, CFAbsoluteTimeGetCurrent() - t0))
        return fails
    }
}
