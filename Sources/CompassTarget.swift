import Foundation

extension Game {
    // Where a compass points: its lodestone (tag packed x/z), the world spawn, or (recovery) the last death.
    func compassTarget(_ s: ItemStack) -> V3 {
        if Items.key(s.item) == "recovery_compass", let d = lastDeath { return d }
        // In the Deep a compass finds the Ashguard citadel (x 0, z 0): every road leads there too.
        if dim.dim == .deep { return V3(0.5, player.pos.y, 0.5) }
        return spawnPoint
    }
}
