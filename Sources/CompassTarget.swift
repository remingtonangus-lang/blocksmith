import Foundation

extension Game {
    // Where a compass points: its lodestone (tag packed x/z), the world spawn, or (recovery) the last death.
    func compassTarget(_ s: ItemStack) -> V3 {
        if Items.key(s.item) == "recovery_compass", let d = lastDeath { return d }
        return spawnPoint
    }
}
