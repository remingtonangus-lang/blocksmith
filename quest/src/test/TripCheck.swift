import Foundation
import simd
import Metal

// Nov 6: the perf scenes' vault flight crossed out of the Deep's top and the tick that did it took 10.8 s (build 204,
// the "deep" stage: Game.crossSeam -> changeDimension, all on the frame). Every way between dimensions goes through
// changeDimension: a portal, the Deep's seam (dug or climbed through), its gates and lifts, the Hollow's gate.
//   questcheck --triptest [--rd 12]      (BS_TRIPSYNC=r: chunks loaded before play goes on, 4 by default)
// A persistent field world as the headset opens it, him standing 3 s; then down through the seam into the Deep, back
// up, through a portal to the Emberdeep and back, each followed by 3 s of ticks at 72 Hz. Per trip: the trip's own
// tick and where its time went, the worst tick after it, and how long until the ground within 3 chunks is drawn.
enum TripCheck {
    static func arg(_ k: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: k), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        QuestApp.headsetWorld()
        let rd = Int(arg("--rd") ?? "") ?? 12
        TextureGen.registerAll()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("triptest-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        defer { SaveIO.flush(); try? FileManager.default.removeItem(at: root) }
        let save = SaveManager(dir: root.appendingPathComponent("Trip", isDirectory: true))
        let w = World(seed: 12345, device: sharedSystemDevice, save: save)
        FieldTerrain.newWorlds = true; w.makeFieldWorld()
        w.renderDistance = rd
        let g = Game(world: w, save: save, persistent: true)
        g.smoothTerrain = true
        SmoothTerrain.use(world: true, world: w)
        g.paused = false; g.menu = nil
        g.survival = true
        g.input.captured = true
        g.time = 0.3 * DAY_LENGTH
        g.saveNow()
        let home = g.spawnPoint
        g.player.pos = home
        _ = w.loadSync(center: home, radius: min(3, rd))
        print("triptest: seed 12345 field world, rd \(rd), sync radius \(Game.tripSync), at \(Int(home.x)) \(Int(home.y) - YOFF) \(Int(home.z))")

        func tick() -> Double {
            g.menu = nil
            g.health = 20; g.hunger = 20; g.alive = true
            let a = CFAbsoluteTimeGetCurrent()
            g.tick(1.0 / 72)
            return (CFAbsoluteTimeGetCurrent() - a) * 1000
        }
        // The ground within 3 chunks of him meshed (what he sees round him first).
        func nearDrawn() -> Bool {
            let cx = floorDiv(Int(floor(g.player.pos.x)), CS), cz = floorDiv(Int(floor(g.player.pos.z)), CS)
            for dz in -3...3 { for dx in -3...3 where dx * dx + dz * dz <= 9 {
                guard let c = g.world.chunkAt((cx + dx) * CS, (cz + dz) * CS), !c.needsMesh else { return false }
            } }
            return true
        }
        var worstTrip = 0.0
        func settle(_ name: String, tripMs: Double, stages: String) {
            var worst = 0.0, worstStage = "-", drawnAt = -1.0
            for i in 0..<(3 * 72) {
                let ms = tick()
                if ms > worst { worst = ms; worstStage = TickProf.summary() }
                if drawnAt < 0 && nearDrawn() { drawnAt = Double(i) / 72 }
            }
            worstTrip = max(worstTrip, tripMs)
            print(String(format: "  %@: the trip's tick %.0f ms (%@) [%@]; then worst tick %.1f ms (%@); ground within 3 chunks drawn %@",
                         name, tripMs, Game.tripLaps, stages, worst, worstStage, drawnAt < 0 ? "not in 3 s" : String(format: "after %.2f s", drawnAt)))
        }
        func trip(_ name: String, _ go: () -> Void) {
            let a = CFAbsoluteTimeGetCurrent()
            go()
            g.tick(1.0 / 72)
            let ms = (CFAbsoluteTimeGetCurrent() - a) * 1000
            settle(name + " (in \(g.dim.dim))", tripMs: ms, stages: TickProf.summary())
        }
        for _ in 0..<(3 * 72) { _ = tick() }

        // Down through the seam (dug through the surface's lowest layer), as Game.deepTick does it.
        trip("down the seam into the Deep") { g.player.pos.y = 0.3; g.player.vel = .zero; g.crossSeam(down: true) }
        // Back up through the Deep's top layer.
        trip("up the seam to the surface") { g.player.pos.y = Float(CH - 1); g.player.vel = .zero; g.crossSeam(down: false) }
        g.player.pos = home
        for _ in 0..<(1 * 72) { _ = tick() }
        // Through a portal to the Emberdeep and back (Portal.travelThroughPortal: the trip, then the portal's search).
        trip("a portal to the Emberdeep") { g.travelThroughPortal() }
        trip("a portal back to the surface") { g.travelThroughPortal() }
        // The Deep a second time (its world kept from the first trip, as in play).
        trip("down the seam again") { g.player.pos.y = 0.3; g.player.vel = .zero; g.crossSeam(down: true) }

        print(String(format: "triptest: slowest trip %.0f ms (a frame on the headset is 13.9 ms)", worstTrip))
        return 0
    }
}
