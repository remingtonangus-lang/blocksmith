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
        print(String(format: "warmup: world: mesh cache %d files %.1f ms, %d rail lines %.1f ms, bases %.1f ms", cached, (t0 - tc) * 1000,
                     rails, (t1 - t0) * 1000, (t2 - t1) * 1000))
    }
}
