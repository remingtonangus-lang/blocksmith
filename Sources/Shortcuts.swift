import Foundation
import simd

// Pause menu > Shortcuts: teleports to the nearest notable structure (the same search as /locate) and back to spawn.
extension Game {
    static let shortcutList: [(String, String)] = [
        ("military_base", "Capital Citadel"), ("capital_city", "Capital City"), ("crawler", "Ironback Crawler"), ("frigate", "Meridian Frigate"),
        ("warfrigate", "Stormwarden Frigate"), ("carriage", "Siege Carriage"), ("village", "Village"),
        ("pillager_outpost", "Marauder Watchtower"), ("mansion", "Forest Manor"), ("monument", "Sea Temple"),
        ("temple", "Temple"), ("great_ruin", "Ancient Spire"), ("ancient_city", "Buried Citadel"),
        ("trial_chambers", "Proving Halls"), ("stronghold", "Stronghold")]

    // The nearest start of a shortcut target (x, z), nil if none is near.
    private func shortcutTarget(_ key: String) -> (Int, Int)? {
        let px = Int(player.pos.x), pz = Int(player.pos.z)
        if ["warfrigate", "crawler", "frigate", "carriage"].contains(key) {
            let R = Vessels.region
            let rx = floorDiv(px, R), rz = floorDiv(pz, R)
            var best: (IVec3, Float)?
            for r in 0...12 { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
                guard let e = Vessels.encounter(seed: world.seed, rx: rx + dx, rz: rz + dz, gen: world.gen) else { continue }
                let match = e.0 == key || (e.0 == "battle" && (key == "warfrigate" || key == "crawler"))
                if !match { continue }
                let d = simd_length(V2(Float(e.1.x) - player.pos.x, Float(e.1.z) - player.pos.z))
                if best == nil || d < best!.1 { best = (e.1, d) }
            } }
            if best != nil && r >= 2 { break } }
            return best.map { ($0.0.x, $0.0.z) }
        }
        guard let s = world.gen.structures?.nearest(key, x: px, z: pz) else { return nil }
        return (s.anchor.x, s.anchor.z)
    }

    private func shortcutLand(_ x: Int, _ z: Int, on: V3? = nil) {
        let g = world.gen.column(x, z).0
        let p = settleSpawn(on ?? V3(Float(x) + 0.5, Float(g + 2), Float(z) + 0.5))
        player.pos = p
        player.vel = .zero
        player.airPeak = p.y
    }

    func shortcutTeleport(_ key: String) {
        guard dim.dim == .overworld else { onToast?("Shortcuts work in the overworld"); return }
        if key == "spawn" {
            shortcutLand(Int(spawnPoint.x), Int(spawnPoint.z), on: spawnPoint)
            onToast?("Back at spawn")
            return
        }
        let name = Game.shortcutList.first { $0.0 == key }?.1 ?? key
        guard let (x, z) = shortcutTarget(key) else { onToast?("No \(name) found nearby"); return }
        shortcutLand(x, z)
        onToast?("Teleported to the \(name)")
    }
}
