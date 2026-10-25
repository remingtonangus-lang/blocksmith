import Foundation
import simd

// Pause menu > Shortcuts: teleports to the nearest notable structure (the same search as /locate) and back to spawn.
extension Game {
    static let shortcutList: [(String, String)] = [
        ("military_base", "Capital Citadel"), ("boreal_station", "Boreal Station"), ("capital_city", "Capital City"), ("crawler", "Ironback Crawler"), ("frigate", "Meridian Frigate"),
        ("warfrigate", "Stormwarden Frigate"), ("carriage", "Siege Carriage"), ("village", "Village"),
        ("pillager_outpost", "Marauder Watchtower"), ("mansion", "Brigand Roost"), ("monument", "Sunken Dreadnought"),
        ("temple", "Temple"), ("great_ruin", "Ancient Spire"), ("ancient_city", "Buried Citadel"),
        ("trial_chambers", "Sealed Armoury"), ("stronghold", "Stronghold")]

    // The nearest start of a shortcut target (x, z), nil if none is near.
    private func shortcutTarget(_ key: String) -> (Int, Int)? {
        let px = Int(player.pos.x), pz = Int(player.pos.z)
        if ["warfrigate", "crawler", "frigate", "carriage"].contains(key) {
            return vesselTarget(key).map { ($0.0.x, $0.0.z) }
        }
        guard let s = world.gen.structures?.nearest(key, x: px, z: pz) else { return nil }
        return (s.anchor.x, s.anchor.z)
    }

    // The nearest vessel of a kind (/locate, Shortcuts): one already out (P437: a crawler on patrol is rarely at its
    // home point), else the nearest encounter region's home that is out in the world yet (Vessels.out).
    func vesselTarget(_ key: String) -> (IVec3, Float, Bool)? {
        let role = key == "frigate" ? "capfrigate" : key
        var best: (IVec3, Float, Bool)?
        for s in world.ships.list where s.role == role && !s.wrecked {
            let d = simd_length(V2(s.pos.x - player.pos.x, s.pos.z - player.pos.z))
            if best == nil || d < best!.1 { best = (IVec3(Int(floor(s.pos.x)), Int(floor(s.pos.y)), Int(floor(s.pos.z))), d, true) }
        }
        if best != nil { return best }
        let R = Vessels.region
        let rx = floorDiv(Int(player.pos.x), R), rz = floorDiv(Int(player.pos.z), R)
        for r in 0...12 { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
            guard let e = Vessels.encounter(seed: world.seed, rx: rx + dx, rz: rz + dz, gen: world.gen),
                  Vessels.out(e.0, fleetSails: fleetSails) else { continue }
            let match = e.0 == key || (e.0 == "battle" && (key == "warfrigate" || key == "crawler"))
            if !match { continue }
            let d = simd_length(V2(Float(e.1.x) - player.pos.x, Float(e.1.z) - player.pos.z))
            if best == nil || d < best!.1 { best = (e.1, d, false) }
        } }
        if best != nil && r >= 2 { break } }
        return best
    }

    private func shortcutLand(_ x: Int, _ z: Int, on: V3? = nil) {
        let g = world.gen.column(x, z).0
        let p = settleSpawn(on ?? V3(Float(x) + 0.5, Float(g + 2), Float(z) + 0.5))
        player.pos = p
        player.vel = .zero
        player.airPeak = p.y
    }

    func shortcutTeleport(_ key: String) {
        guard dim.dim == .overworld else { onToast?("Shortcuts work on the Surface"); return }
        if key == "spawn" {
            shortcutLand(Int(spawnPoint.x), Int(spawnPoint.z), on: spawnPoint)
            onToast?("Back at spawn")
            return
        }
        let name = Game.shortcutList.first { $0.0 == key }?.1 ?? key
        guard let (x, z) = shortcutTarget(key) else {
            onToast?(key == "warfrigate" && !fleetSails ? "The Stormwarden Frigates sail once a Greywall Fortress falls" : "No \(name) found nearby")
            return
        }
        shortcutLand(x, z)
        onToast?("Teleported to the \(name)")
    }
}
