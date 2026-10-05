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
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        print(String(format: "warmup: %.1f ms", ms) + (slow.isEmpty ? "" : " (" + slow.joined(separator: ", ") + ")"))
        return (ms, slow)
    }
}
