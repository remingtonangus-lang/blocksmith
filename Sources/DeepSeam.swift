import Foundation
import simd

// The seam between the surface and the Deep stacked under it (task 22). The surface has no bedrock floor: break through
// its lowest layer and you carry on digging at the top of the Deep (same x, z), and climb out of the Deep's top layer to
// come back up. The Ash Vault's hot updrafts slow long falls into it; below the vault floor is the molten core.
extension Game {
    func deepTick(_ dt: Float) {
        guard alive, world.frame == nil, riding == nil else { return }
        let p = player.pos
        switch dim.dim {
        case .overworld where p.y < 0.5:
            crossSeam(down: true)
        case .deep where p.y >= Float(CH - 1):
            crossSeam(down: false)
        case .deep:
            // Updrafts: a long drop into the vault floats down (no fall damage), so breaking through its roof is survivable.
            if DeepGen.inVault(p.y) && !player.onGround && !player.flying && player.vel.y < -6 {
                if !effects.has(.slowFalling) && !deepUpdraftHinted {
                    deepUpdraftHinted = true
                    onToast?("Hot air rising from the vault slows your fall")
                }
                applyEffect(.slowFalling, amp: 0, seconds: 1.5)
            }
        default: break
        }
    }

    // Moves the player across the seam and opens a two-block pocket where they arrive (as if they had dug into it),
    // standing on solid rock. Arrival is a block or two clear of the opposite trigger, so nobody bounces back.
    func crossSeam(down: Bool) {
        let x = Int(floor(player.pos.x)), z = Int(floor(player.pos.z))
        let feet = down ? CH - 3 : 1
        let to = V3(player.pos.x, Float(feet), player.pos.z)
        changeDimension(to: down ? .deep : .overworld, at: to)
        for y in feet...(feet + 1) where world.block(x, y, z) != AIR { world.setBlock(x, y, z, AIR) }
        if !Blocks.opaque[Int(world.block(x, feet - 1, z))] { world.setBlock(x, feet - 1, z, EMBERSLATE) }
        player.pos = to
        player.vel = .zero
        player.airPeak = to.y
        if down { achieve("deep_visit") }
        if down && !deepVisited {
            deepVisited = true
            onToast?("You broke through the bottom of the world")
        }
    }
}

extension MobManager {
    // The Deep's natural spawns: the hell band spawns like the Emberdeep (tougher: depth power); the solid crusts spawn
    // nothing, and the Ash Vault belongs to the Ashguard (their garrisons come with the sites, AshWar.swift).
    func trySpawnDeep(_ game: Game) {
        guard DeepGen.inHell(game.player.pos.y) else { return }
        let n = mobs.count
        trySpawnEmberdeep(game, base: DeepGen.hellBase)
        for m in mobs[n...] where m.kind.hostile { m.power = MobManager.depthPower(.deep, m.pos.y) }
    }
}
