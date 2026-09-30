import Foundation
import simd

// End crystals as items (placed on obsidian or bedrock) and the dragon respawn ritual: four crystals
// on the exit portal's rim rebuild the spike crystals, then the dragon returns (reference sequence).
extension Game {
    func placeEndCrystal(_ t: (hit: IVec3, normal: IVec3)) -> Bool {
        guard Items.key(held.item) == "end_crystal", t.normal.y == 1 else { return false }
        let b = world.block(t.hit.x, t.hit.y, t.hit.z)
        guard b == OBSIDIAN || b == BEDROCK else { return false }
        let at = V3(Float(t.hit.x) + 0.5, Float(t.hit.y + 1), Float(t.hit.z) + 0.5)
        guard world.block(t.hit.x, t.hit.y + 1, t.hit.z) == AIR, world.block(t.hit.x, t.hit.y + 2, t.hit.z) == AIR,
              !mobs.mobs.contains(where: { $0.kind == .endCrystal && simd_length($0.pos - at) < 1 }) else { return false }
        let c = Mob(.endCrystal, at: at)
        c.persistent = true
        mobs.mobs.append(c)
        if survival { consumeHeld() }
        swing = 1
        checkDragonRespawn()
        return true
    }

    func checkDragonRespawn() {
        guard dim.dim == .end, dragonKilled, respawnTimer <= 0, !mobs.mobs.contains(where: { $0.kind == .enderDragon }) else { return }
        let fy = fountainY
        let spots = [V3(3.5, Float(fy + 1), 0.5), V3(-2.5, Float(fy + 1), 0.5), V3(0.5, Float(fy + 1), 3.5), V3(0.5, Float(fy + 1), -2.5)]
        let placed = spots.compactMap { s in mobs.mobs.first { $0.kind == .endCrystal && $0.health > 0 && simd_length($0.pos - s) < 0.8 } }
        guard placed.count == 4 else { return }
        respawnTimer = 12
        respawnCrystals = placed
        // The exit portal closes while the dragon is back.
        HollowGen.fountainBlocks(fy, active: false) { x, y, z, b in world.setBlockAsync(x, y, z, b) }
        sfx(.mobBlight, 0.6)
    }

    // Runs the ~12 s summoning: pillar crystals come back one by one, then the dragon.
    func dragonRespawnTick(_ dt: Float) {
        guard respawnTimer > 0 else { return }
        respawnTimer -= dt
        if let eg = endGen {
            let n = eg.spikes.count
            let doneBefore = Int((12 - (respawnTimer + dt)) / 10 * Float(n))
            let doneNow = Int((12 - respawnTimer) / 10 * Float(n))
            if doneNow > doneBefore {
                for i in max(0, doneBefore)..<min(n, doneNow) {
                    let s = eg.spikes[i]
                    let top = YOFF + s.height
                    let p = V3(Float(s.x) + 0.5, Float(top + 2), Float(s.z) + 0.5)
                    world.setBlock(s.x, top + 1, s.z, BEDROCK)
                    if !mobs.mobs.contains(where: { $0.kind == .endCrystal && simd_length($0.pos - p) < 1 }) {
                        let c = Mob(.endCrystal, at: p); c.persistent = true; mobs.mobs.append(c)
                    }
                    particles.explosion(at: p, power: 0.6)
                    sfx(.explode, 0.5, at: p)
                }
            }
        }
        if respawnTimer <= 0 {
            for c in respawnCrystals { c.health = 0 }
            respawnCrystals = []
            let d = Mob(.enderDragon, at: V3(0.5, Float(fountainY + 40), 0.5))
            d.persistent = true
            mobs.mobs.append(d)
            dragonKilled = false
            sfx(.mobWailer, 1.2)
            achieve("respawn_dragon")
        }
    }
}
