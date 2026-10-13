import Foundation
import simd

// P131 (Oct 12 PM, "a way to find home when lost"): home is the respawn point, your bed once you have slept in one,
// else the world spawn. It shows as an orange house marker on the minimap (held on the minimap's edge in its
// direction when it is off the map) and on the world map with its name, and a line under the minimap gives the
// distance and heading ("Home 342 NW") whenever a compass is in either hand or you are over 200 blocks from it.
enum HomeFinder {
    static let colour = V4(1, 0.62, 0.2, 1)
    static let far: Float = 200

    static func isBed(_ g: Game) -> Bool { abs(g.spawnPoint.y - floorf(g.spawnPoint.y) - 0.6) < 0.01 }
    static func name(_ g: Game) -> String { isBed(g) ? "Home" : "Spawn" }

    static func compassInHand(_ g: Game) -> Bool {
        let keys = [g.inventory.held, g.inventory.offhand[0]].filter { !$0.isEmpty }.map { Items.key($0.item) }
        return keys.contains { $0 == "compass" || $0 == "recovery_compass" }
    }

    // "Home 342 NW" (nil in other dimensions, and near home without a compass in hand).
    static func line(_ g: Game) -> String? {
        guard g.dim.dim == .overworld else { return nil }
        let h = g.spawnPoint, p = g.player.pos
        let dx = h.x - p.x, dz = h.z - p.z
        let d = (dx * dx + dz * dz).squareRoot()
        guard compassInHand(g) || d > far else { return nil }
        if d < 4 { return "\(name(g)): here" }
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let ang: Float = atan2f(dx, -dz)
        let i = Int(((ang / (2 * .pi) * 8) + 8.5).rounded(.down)) % 8
        return "\(name(g)) \(Int(d)) \(dirs[i])"
    }
}
