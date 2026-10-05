import Foundation
import simd

// Gravity blocks (sand, gravel, concrete powder, anvils, wyrm eggs...) fall as entities when
// nothing supports them, and land as blocks (or pop as items on a non-full surface). Falling
// anvils hurt what they land on and may wear down; concrete powder hardens next to water.
final class FallingBlock {
    var pos: V3
    var vel = V3.zero
    let block: BlockID
    var start: Float
    var dead = false
    init(_ p: V3, _ b: BlockID) { pos = p; block = b; start = p.y }
}

extension Game {
    func gravityTick() {
        guard !world.gravityQueue.isEmpty else { return }
        let q = world.gravityQueue
        world.gravityQueue.removeAll(keepingCapacity: true)
        for p in q {
            if plantSupportCheck(p) { continue }          // plants that lost their support pop (PlantSupport.swift)
            let b = world.block(p.x, p.y, p.z)
            guard World.fallingIDs[Int(b)], p.y > 0 else {
                hardenConcrete(p)
                continue
            }
            let below = world.block(p.x, p.y - 1, p.z)
            guard below == AIR || Blocks.isLiquid(below) || (Blocks.replaceable[Int(below)] && !Blocks.collide[Int(below)]) || below == FIRE else {
                hardenConcrete(p)
                continue
            }
            world.setBlock(p.x, p.y, p.z, AIR)
            falling.append(FallingBlock(V3(Float(p.x) + 0.5, Float(p.y), Float(p.z) + 0.5), b))
        }
    }

    // Concrete powder touching water becomes concrete.
    func hardenConcrete(_ p: IVec3) {
        let b = world.block(p.x, p.y, p.z)
        let k = Blocks.key(b)
        guard k.hasSuffix("_concrete_powder") else { return }
        for d in World.allDirs where d.y >= 0 {
            if Blocks.fluidKind[Int(world.block(p.x + d.x, p.y + d.y, p.z + d.z))] == 1 {
                let c = String(k.dropLast("_powder".count))
                if Blocks.has(c) { world.setBlock(p.x, p.y, p.z, Blocks.id(c)) }
                return
            }
        }
    }

    func fallingTick(_ dt: Float) {
        guard !falling.isEmpty else { return }
        for f in falling {
            f.vel.y = max(-40, f.vel.y - 28 * dt)
            let next = f.pos + f.vel * dt
            let cell = IVec3(Int(floor(next.x)), Int(floor(next.y)), Int(floor(next.z)))
            let b = world.block(cell.x, cell.y, cell.z)
            if next.y < 0 { f.dead = true; continue }
            if Blocks.collide[Int(b)] && !Blocks.isLiquid(b) {
                // Land in the cell above.
                let at = IVec3(cell.x, cell.y + 1, cell.z)
                f.dead = true
                let key = Blocks.key(f.block)
                let fell = f.start - Float(at.y)
                if key.hasSuffix("anvil") && fell > 1 {
                    // Up to 40 damage (2 per block fallen) to whatever is below; 5% wear per block.
                    let dmg = min(40, Int(fell * 2))
                    let c = V3(Float(at.x) + 0.5, Float(at.y), Float(at.z) + 0.5)
                    if simd_length(V2(player.pos.x - c.x, player.pos.z - c.z)) < 0.8 && abs(player.pos.y - c.y) < 1.8 {
                        damage(dmg, "was squashed by a falling anvil")
                    }
                    for m in mobs.mobs where simd_length(V2(m.pos.x - c.x, m.pos.z - c.z)) < 0.5 + m.halfW && abs(m.pos.y - c.y) < 1.5 {
                        m.hit(from: c + V3(0, 2, 0), damage: dmg, knockback: 0)
                    }
                    sfx(.anvil, 0.8, at: c)
                }
                let there = world.block(at.x, at.y, at.z)
                if there == AIR || Blocks.replaceable[Int(there)] || Blocks.isLiquid(there) {
                    var place = f.block
                    if key.hasSuffix("anvil") && Rand.float(in: 0..<1) < 0.05 * fell {
                        place = key == "anvil" ? Blocks.id("chipped_anvil") : (key == "chipped_anvil" ? Blocks.id("damaged_anvil") : AIR)
                    }
                    world.setBlock(at.x, at.y, at.z, place)
                    if place != AIR { sfx(.place(soundMat(place)), 0.6, at: V3(Float(at.x), Float(at.y), Float(at.z)) + 0.5) }
                    hardenConcrete(at)
                } else {
                    for s in Mining.drops(f.block, ItemStack(Items.id("netherite_pickaxe"), 1)) { drops.spawn(s, at: f.pos) }
                }
                continue
            }
            f.pos = next
        }
        falling.removeAll { $0.dead }
    }

    func writeFalling(_ wr: inout EntityWriter, eye: V3) {
        for f in falling {
            let l = world.lightAt(Int(floor(f.pos.x)), Int(floor(f.pos.y + 0.5)), Int(floor(f.pos.z)))
            let light = max(0.15, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
            wr.cube(center: f.pos + V3(0, 0.5, 0) - eye, half: 0.5, yaw: 0, block: f.block, light: light)
        }
    }
}
