import Foundation
import simd

// Wind charges, sponges, concrete powder hardening, powder snow (sinking + freezing, leather boots
// walk on it) and copper bulb toggling helpers.
extension Game {
    func throwWindCharge() {
        guard clock - lastWind > 0.5 else { return }
        lastWind = clock
        throwItem(.wind)
    }

    // Burst: knocks back everything within 2.5 blocks (the thrower included, which launches them).
    func windBurst(at c: V3) {
        sfx(.windCharge, 1, at: c)
        particles.explosion(at: c, power: 0.4)
        for m in mobs.mobs where m.health > 0 {
            let d = m.pos + V3(0, m.height / 2, 0) - c
            let l = simd_length(d)
            if l < 2.5 {
                let dir: V3 = l > 0.01 ? d / l : V3(0, 1, 0)
                let s: Float = (2.5 - l) * 6
                m.vel += dir * s + V3(0, 4, 0)
            }
        }
        let d = player.pos + V3(0, 0.9, 0) - c
        let l = simd_length(d)
        if l < 2.5 {
            let dir: V3 = l > 0.01 ? d / l : V3(0, 1, 0)
            let s: Float = (2.5 - l) * 7
            player.vel += dir * s + V3(0, 6, 0)
            player.airPeak = player.pos.y                   // no fall damage from the launch height
        }
        // Flips doors, trapdoors, gates, levers and buttons it touches.
        let p = IVec3(Int(floor(c.x)), Int(floor(c.y)), Int(floor(c.z)))
        for dz in -1...1 { for dy in -1...1 { for dx in -1...1 {
            let q = IVec3(p.x + dx, p.y + dy, p.z + dz)
            let s = Blocks.shape[Int(world.block(q.x, q.y, q.z))]
            if (s == "door" || s == "trapdoor" || s == "gate") && !Blocks.key(world.block(q.x, q.y, q.z)).hasPrefix("iron_") { toggleOpenable(q) }
        } } }
    }

    // Sponge: soaks up water within 7 blocks (taxicab), up to 65 blocks, and becomes wet.
    func spongeAbsorb(_ p: IVec3) {
        var queue = [(p, 0)]
        var seen: Set<IVec3> = [p]
        var soaked = 0
        var i = 0
        while i < queue.count && soaked < 65 {
            let (q, dist) = queue[i]; i += 1
            for d in BlockRegistry.dir6 {
                let n = q + d
                guard seen.insert(n).inserted, dist < 7 else { continue }
                let b = world.block(n.x, n.y, n.z)
                let wet = Blocks.fluidKind[Int(b)] == 1
                let k = Blocks.key(Blocks.groupBase[Int(b)])
                if wet || k == "kelp" || k == "kelp_plant" || k == "seagrass" || k == "tall_seagrass" {
                    world.setBlockAsync(n.x, n.y, n.z, AIR)
                    soaked += 1
                    queue.append((n, dist + 1))
                }
            }
        }
        if soaked > 0 {
            world.setBlock(p.x, p.y, p.z, Blocks.id("wet_sponge"))
            sfx(.bucketFill, 0.6, at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5))
        }
    }

    // Footsteps (not sneaking) are vibrations twice a second.
    func vibrationTick(_ dt: Float) {
        stepVibe -= dt
        if stepVibe <= 0 && player.onGround && !player.sneaking && simd_length(V2(player.vel.x, player.vel.z)) > 0.5 {
            stepVibe = 0.5
            world.redstone.vibrate(at: player.pos)
        }
    }

    // After placing a block: sponge / concrete powder reactions.
    func placedReactions(_ p: IVec3) {
        let k = Blocks.key(Blocks.groupBase[Int(world.block(p.x, p.y, p.z))])
        if k == "sponge" { spongeAbsorb(p) }
        if k.hasSuffix("_concrete_powder") { hardenConcrete(p) }
        if k == "wet_sponge" && dim.dim == .nether {
            world.setBlock(p.x, p.y, p.z, Blocks.id("sponge"))
            sfx(.fizz, 0.8)
        }
    }

    // Powder snow: sink slowly unless wearing leather boots; freezing after 7 s inside.
    func powderSnowTick(_ dt: Float) {
        let feet = IVec3(Int(floor(player.pos.x)), Int(floor(player.pos.y + 0.1)), Int(floor(player.pos.z)))
        let below = IVec3(feet.x, Int(floor(player.pos.y - 0.05)), feet.z)
        let snow = Blocks.id("powder_snow")
        let boots = Items.key(inventory.armor[3].item) == "leather_boots"
        if boots && world.block(below.x, below.y, below.z) == snow && player.vel.y <= 0 && world.block(feet.x, feet.y, feet.z) != snow {
            player.pos.y = Float(below.y + 1)
            player.vel.y = 0
            player.onGround = true
            player.airPeak = player.pos.y
            achieve("powder_walk")
        }
        let inside = world.block(feet.x, feet.y, feet.z) == snow || world.block(feet.x, feet.y + 1, feet.z) == snow
        if inside {
            player.vel.y = max(player.vel.y, -1.5)
            if !boots { player.airPeak = player.pos.y }
            // Any piece of leather armour keeps the cold out (reference; only the boots counted).
            let leather = inventory.armor.slots.contains { Items.key($0.item).hasPrefix("leather_") }
            if !leather { freeze = min(7, freeze + dt) }
        } else {
            freeze = max(0, freeze - 2 * dt)
        }
        if freeze >= 7 && survival {
            freezeTick += dt
            if freezeTick >= 2 { freezeTick = 0; damage(1, "froze to death", bypassArmor: true, type: .generic) }
        } else { freezeTick = 0 }
    }
}
