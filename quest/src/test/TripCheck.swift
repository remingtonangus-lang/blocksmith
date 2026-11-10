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
        World.resultsProfile = true                          // (the slowest single hand-over after each trip)
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
            let ms = (CFAbsoluteTimeGetCurrent() - a) * 1000
            // (paced as the headset's frames are: the workers stream the world in real time while he waits; unpaced,
            // three seconds of ticks ran in a few milliseconds and nothing could arrive)
            if ms < 1000.0 / 72 { usleep(useconds_t((1000.0 / 72 - ms) * 1000)) }
            return ms
        }
        // The ground within 2 chunks of him drawn (what the hold waits for: Game.arrivalReady).
        var worstTrip = 0.0, worstAfter = 0.0, longestHold = 0.0
        func settle(_ name: String, tripMs: Double, stages: String) {
            var worst = 0.0, worstStage = "-", drawnAt = -1.0, heldFor = 0.0, worstHeld = 0.0
            World.resultsWorstMs = 0; World.resultsWorst = "-"
            for i in 0..<(3 * 72) {
                let held = g.arrivalSince != nil
                let ms = tick()
                if held { heldFor = Double(i + 1) / 72 }
                if held && i % 36 == 0 && ProcessInfo.processInfo.environment["BS_TRIPTRACE"] == "1" {
                    let w = g.world
                    let cx = floorDiv(Int(floor(g.player.pos.x)), CS), cz = floorDiv(Int(floor(g.player.pos.z)), CS)
                    var have = 0, drawn = 0
                    for dz in -2...2 { for dx in -2...2 where dx * dx + dz * dz <= 4 {
                        if let c = w.chunks[ChunkKey(x: cx + dx, z: cz + dz)] { have += 1; if c.meshedOnce { drawn += 1 } }
                    } }
                    print(String(format: "    held %.1f s: %d chunks loaded, %d jobs pending, made %d, meshed %d sections; within 2: %d of 13 there, %d drawn",
                                 Double(i) / 72, w.chunks.count, w.pendingJobs, w.perf.genChunks, w.perf.meshSections, have, drawn))
                    for (d, st) in g.dims { print("      \(d): \(st.world.debugState)\(st.world === w ? " (here)" : "")") }
                }
                if held { worstHeld = max(worstHeld, ms) } else if ms > worst { worst = ms; worstStage = TickProf.summary() }
                if drawnAt < 0 && g.arrivalReady() { drawnAt = Double(i) / 72 }
            }
            worstTrip = max(worstTrip, tripMs); worstAfter = max(worstAfter, worst); longestHold = max(longestHold, heldFor)
            print(String(format: "  %@: the trip's tick %.0f ms (%@) [%@]; held %.2f s (worst tick in it %.1f ms, the arrival's work %.1f ms); then worst tick %.1f ms (%@); ground within 2 chunks drawn %@; slowest hand-over %.1f ms (%@)",
                         name, tripMs, Game.tripLaps, stages, heldFor, worstHeld, Game.arrivalThenMs, worst, worstStage,
                         drawnAt < 0 ? "not in 3 s" : String(format: "after %.2f s", drawnAt), World.resultsWorstMs, World.resultsWorst))
            Game.arrivalThenMs = 0
            print(String(format: "    mesh slabs: %d made, %d of them ahead on a worker; the slowest made on the frame %.1f ms", MeshArena.shared.slabCount, MeshArena.shared.spareUsed, MeshArena.shared.slabMsWorst))
        }
        func trip(_ name: String, _ go: () -> Void) {
            let a = CFAbsoluteTimeGetCurrent()
            go()
            g.tick(1.0 / 72)
            let ms = (CFAbsoluteTimeGetCurrent() - a) * 1000
            g.portalCooldown = 3; g.portalTime = 0                 // (as portalTick sets them: no second trip while he stands in it)
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
        // The Hollow, and its rifts (the code reader's Nov 10 batch, 4: a rift loaded where it threw him on the frame).
        trip("into the Hollow") { g.enterEnd() }
        trip("a rift out to the far islands") { g.player.pos = V3(3.5, g.player.pos.y, 0.5); g.gatewayTeleport() }
        trip("a rift back to the middle") { g.gatewayTeleport() }

        print(String(format: "triptest: slowest trip %.0f ms, worst tick after one %.1f ms, longest hold %.2f s (hold %@; a frame on the headset is 13.9 ms)",
                     worstTrip, worstAfter, longestHold, Game.arrivalHold ? "on" : "off"))
        // With the hold (the headset): no trip's own frame over 50 ms on the host, and every hold let go in time.
        let ok = !Game.arrivalHold || worstTrip < 50 && longestHold < Game.arrivalMax
        print((ok ? "ok   " : "FAIL ") + "triptest")
        return ok ? 0 : 1
    }
}
