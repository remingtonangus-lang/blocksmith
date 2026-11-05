import Foundation

// Lazily built per-block-state tables, built on the loading thread instead of on the game thread the first time
// something needs them (the first footstep built SoundMats inside a game tick: a ~7 ms spike in the questcheck
// profile, a missed frame on the headset). Swift's lazy globals are thread-safe, so touching them here is enough.
enum QuestWarmup {
    // Returns the total time and the tables that took over a millisecond (for the load log).
    @discardableResult
    static func run() -> (ms: Double, slow: [String]) {
        var slow: [String] = []
        let t0 = CFAbsoluteTimeGetCurrent()
        func touch(_ name: String, _ f: () -> Int) {
            let a = CFAbsoluteTimeGetCurrent()
            _ = f()
            let ms = (CFAbsoluteTimeGetCurrent() - a) * 1000
            if ms > 1 { slow.append(String(format: "%@ %.1f ms", name, ms)) }
        }
        touch("SoundMats") { SoundMats.count }
        touch("emitters") { Game.emitters.count }
        touch("probeDirs") { Game.probeDirs.count }
        touch("fallingIDs") { World.fallingIDs.count }
        touch("groundBlock") { ShipManager.groundBlock.count }
        touch("ShipParts") { ShipParts.kinds.count + ShipParts.mass.count + ShipParts.natural.count }
        touch("Circuit.kinds") { Circuit.kinds.count }
        touch("Enchant.defs") { Enchant.defs.count }
        touch("Potions") { Potions.types.count + Potions.mixes.count }
        touch("Copper.index") { Copper.index.count }
        touch("smeltingExtra") { Recipes.smeltingExtra.count }
        touch("PlantSupport") { Int(PlantSupport.ruleOf(AIR)) }           // built on the first block change (5 ms)
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        print(String(format: "warmup: %.1f ms", ms) + (slow.isEmpty ? "" : " (" + slow.joined(separator: ", ") + ")"))
        return (ms, slow)
    }

    // P400 step 3: what the game's first once-a-second ticks plan the first time, done on the loading thread so the
    // first seconds of play don't stall (host: trains 68-167 ms, the Greywall alarm 25-40 ms on the first tick).
    // The rail lines within the trains' reach (Railways' plans, cached for the tick), the alarm's block table, and the
    // nearby bases' starts handed to a worker (nearestIfReady), so the base ticks find them ready.
    static func world(_ game: Game) {
        let tc = CFAbsoluteTimeGetCurrent()
        // The disk mesh cache opened (its folder listed) here, not by the first block change or far-chunk scan of the
        // first ticks (World.meshCache is lazy).
        let cached = game.world.meshCache?.count ?? 0
        let t0 = CFAbsoluteTimeGetCurrent()
        let rails = Trains.tracksNear(game, game.player.pos, 140).count
        let t1 = CFAbsoluteTimeGetCurrent()
        _ = Greywall.scanKinds.count
        if let sc = game.world.gen.structures {
            let x = Int(game.player.pos.x), z = Int(game.player.pos.z)
            for kind in [Greywall.kind, "military_base", BorealStation.kind] { _ = sc.nearestIfReady(kind, x: x, z: z) }
        }
        let t2 = CFAbsoluteTimeGetCurrent()
        let plans = structures(game)
        // (Store review, the town soak: the first greeting read the 36 MB voice bank on the frame thread, a 38-56 ms
        // frame on the host; read here, with the loading scene up.)
        TownVoice.ensure()
        lines()
        print(String(format: "warmup: world: mesh cache %d files %.1f ms, %d rail lines %.1f ms, bases %.1f ms, starts round him %.0f ms", cached, (t0 - tc) * 1000,
                     rails, (t1 - t0) * 1000, (t2 - t1) * 1000, plans))
    }

    // Nov 4 (the town soak under callgrind: one townsperson's line took 54 M instructions on the frame thread, about
    // 15 ms on the host): what each line of talk needs to be true (LineTruth.needs: the hour, the weather, a horse...) is
    // read from its words the first time the line is a candidate, about 1.2 M instructions a line, and a greeting weighs
    // dozens of candidates; the 2,000-odd lines' needs are read here once, on a worker while the world loads and the
    // first minutes play (the answers are cached, under LineTruth's lock).
    static var linesWarmed = false
    static func lines() {
        guard !linesWarmed else { return }
        linesWarmed = true
        DispatchQueue.global(qos: .utility).async {
            let t0 = CFAbsoluteTimeGetCurrent()
            var n = 0
            for t in TownVoice.takes { _ = LineTruth.needs(t.text); n += 1 }
            for t in TownLines.all { _ = LineTruth.needs(t); n += 1 }
            _ = TownLines.pools.count
            print(String(format: "warmup: %d lines' needs read in %.0f ms (a worker)", n, (CFAbsoluteTimeGetCurrent() - t0) * 1000))
        }
    }

    // Store review (the frame soak's "starts planned on the frame thread": the first seconds' town, map-fog, hunting
    // and mob lookups planned villages, temples and bases on the frame thread, 1-15 ms each, racing the worker that
    // plans ahead of him): every kind's starts a region round him are planned here, with the loading scene up.
    @discardableResult
    static func structures(_ game: Game) -> Double {
        guard let sc = game.world.gen.structures, game.player.pos.x.isFinite, game.player.pos.z.isFinite else { return 0 }
        let t0 = CFAbsoluteTimeGetCurrent()
        sc.prefetch(x: Int(floor(game.player.pos.x)), z: Int(floor(game.player.pos.z)), ring: 1)
        StructureCache.prefetchQueue.sync {}
        return (CFAbsoluteTimeGetCurrent() - t0) * 1000
    }
}
