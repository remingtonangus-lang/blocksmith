import Foundation
import simd

// Behaviour for the newer blocks: campfires, beehives, rebirth anchors, sea pickles, turtle eggs,
// frogspawn, frosted ice, cocoa, conduits, lightning rods, murk shriekers (deep stalker) and catalysts.
extension Game {
    // Right-click handling; returns true if used.
    func useNewBlock(_ t: (hit: IVec3, normal: IVec3)) -> Bool {
        let p = t.hit
        let b = world.block(p.x, p.y, p.z)
        let base = Blocks.groupBase[Int(b)]
        let bk = Blocks.key(base)
        let st = Int(b - base)
        let key = Items.key(held.item)
        let c = V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5
        switch bk {
        case "campfire", "soul_campfire":
            let lit = st == 0
            if !lit && (key == "flint_and_steel" || key == "fire_charge") { world.setBlock(p.x, p.y, p.z, base); if key == "fire_charge" { consumeHeld() } else { damageHeld(1) }; return true }
            if lit && key.hasSuffix("_shovel") { world.setBlock(p.x, p.y, p.z, base + 1); sfx(.fireExtinguish, 0.7, at: c); damageHeld(1); return true }
            // Put raw food on it (up to four items, 30 s each).
            if lit, Recipes.smelt(held.item) != nil, held.def.food != nil {
                let be = world.entity(p, .campfire)
                world.blockEntities[p] = be
                if let i = (0..<4).first(where: { be.container[$0].isEmpty }) {
                    be.container[i] = ItemStack(held.item, 1)
                    be.cooks[i] = 600
                    consumeHeld()
                    return true
                }
            }
        case "bee_nest", "beehive":
            guard st == 5 else { return false }
            if key == "shears" {
                drops.spawn(ItemStack(Items.id("honeycomb"), 3), at: c + V3(0, 0.6, 0))
                world.setBlock(p.x, p.y, p.z, base)
                damageHeld(1)
                angerBees(near: c)
                return true
            }
            if key == "glass_bottle" {
                giveOrReplaceHeld(ItemStack(Items.id("honey_bottle"), 1))
                world.setBlock(p.x, p.y, p.z, base)
                angerBees(near: c)
                return true
            }
        case "respawn_anchor":
            if key == "glowstone" && st < 4 {
                world.setBlock(p.x, p.y, p.z, b + 1); consumeHeld(); sfx(.respawnAnchorCharge, 0.8, at: c)
                if st + 1 == 4 { achieve("anchor_full") }
                return true
            }
            if st > 0 {
                if dim.dim == .nether {
                    anchorSpawn = p
                    onToast?("Respawn point set")
                } else {
                    // Anchors explode outside the Emberdeep.
                    world.setBlock(p.x, p.y, p.z, AIR)
                    Explosion.explode(at: c, power: 5, game: self, fire: true)
                }
                return true
            }
        case "sea_pickle":
            if key == "sea_pickle" && st < 3 { world.setBlock(p.x, p.y, p.z, b + 1); consumeHeld(); return true }
        case "turtle_egg":
            if key == "turtle_egg" && st < 3 { world.setBlock(p.x, p.y, p.z, b + 1); consumeHeld(); return true }
        case "cocoa":
            if key == "bone_meal" && st < 2 { world.setBlock(p.x, p.y, p.z, b + 1); consumeHeld(); particles.hearts(at: c); return true }
        case "jukebox":
            return useJukebox(p)
        case "vault":
            // A proving key opens a vault once.
            let be = world.entity(p, .chest)
            world.blockEntities[p] = be
            guard key == "trial_key" && !be.used else { sfx(.vaultReject, 0.6, at: c); return true }
            be.used = true
            consumeHeld()
            let tmp = ItemContainer(9)
            var rng = SRng(Rand.u64(in: 1...UInt64.max))
            Loot.fill(tmp, table: "trial_vault", rng: &rng)
            for s in tmp.slots where !s.isEmpty { drops.spawn(s, at: c + V3(0, 0.7, 0), vel: V3(0, 3, 0)) }
            sfx(.vaultOpen, 0.8, at: c)
            return true
        case "lodestone":
            if key == "compass" { onToast?("Lodestone compass linked"); return true }
        default: break
        }
        return false
    }

    func angerBees(near c: V3) {
        beeHiveDisturbed(c)
    }

    // 20 Hz: campfires cook and hurt, frost walker freezes, conduits power players in water.
    func blockEntityTicks() {
        for (p, be) in world.blockEntities where be.kind == .campfire {
            for i in 0..<4 where !be.container[i].isEmpty {
                be.cooks[i] -= 1
                if be.cooks[i] <= 0 {
                    if let out = Recipes.smelt(be.container[i].item) { drops.spawn(ItemStack(out, 1), at: V3(Float(p.x) + 0.5, Float(p.y) + 1, Float(p.z) + 0.5)) }
                    be.container[i] = .empty
                }
            }
        }
    }

    // Once a second.
    func blockSecondTick() {
        let pp = player.pos
        // Campfire smoke and contact damage.
        let feet = IVec3(Int(floor(pp.x)), Int(floor(pp.y - 0.1)), Int(floor(pp.z)))
        let fb = world.block(feet.x, feet.y, feet.z)
        let fk = Blocks.key(fb)
        if (fk == "campfire" || fk == "soul_campfire") && survival && !player.sneaking {
            damage(fk == "soul_campfire" ? 2 : 1, "went up in flames", type: .fire)
        }
        // Frost walker: freeze still water around the player's feet.
        let fw = Enchant.level(.frostWalker, inventory.armor[3])
        if fw > 0 && player.onGround, Blocks.has("frosted_ice") {
            let r = 2 + fw
            let fi = Blocks.id("frosted_ice")
            for dz in -r...r { for dx in -r...r where dx * dx + dz * dz <= r * r {
                let q = IVec3(feet.x + dx, feet.y, feet.z + dz)
                if world.block(q.x, q.y, q.z) == WATER && world.block(q.x, q.y + 1, q.z) == AIR { world.setBlockAsync(q.x, q.y, q.z, fi) }
            } }
        }
        // Conduits: a tidestone frame (16+ blocks within 2) in water gives Conduit Power (16 blocks per 7 frame blocks).
        let conduit = Blocks.has("conduit") ? Blocks.id("conduit") : AIR
        if conduit != AIR, player.inWater {
            let c = IVec3(Int(floor(pp.x)), Int(floor(pp.y)), Int(floor(pp.z)))
            outer: for dy in -24...24 where dy % 2 == 0 { for dz in stride(from: -24, through: 24, by: 1) { for dx in stride(from: -24, through: 24, by: 1) {
                guard abs(dx) + abs(dy) + abs(dz) < 48, world.block(c.x + dx, c.y + dy, c.z + dz) == conduit else { continue }
                let q = IVec3(c.x + dx, c.y + dy, c.z + dz)
                var frame = 0
                for fz in -2...2 { for fy in -2...2 { for fx in -2...2 {
                    let k = Blocks.key(world.block(q.x + fx, q.y + fy, q.z + fz))
                    if k == "prismarine" || k == "prismarine_bricks" || k == "dark_prismarine" || k == "sea_lantern" { frame += 1 }
                } } }
                if frame >= 16 && simd_length(V3(Float(dx), Float(dy), Float(dz))) < Float(frame / 7 * 16) {
                    applyEffect(.conduitPower, amp: 0, seconds: 13, ambient: true)
                    break outer
                }
            } } }
        }
        // Murk shriekers: walking (not sneaking) near a sensor/shrieker raises the warning level; the 4th shriek calls a deep stalker.
        if survival && !player.sneaking && simd_length(player.vel) > 1 && dim.dim == .overworld && pp.y < Float(YOFF + 10) {
            shriekCooldown -= 1
            if shriekCooldown <= 0 {
                let c = IVec3(Int(floor(pp.x)), Int(floor(pp.y)), Int(floor(pp.z)))
                var found = false
                for dy in -4...4 { for dz in -8...8 { for dx in -8...8 {
                    let k = Blocks.key(world.block(c.x + dx, c.y + dy, c.z + dz))
                    if k == "sculk_shrieker" || k == "sculk_sensor" || k == "calibrated_sculk_sensor" { found = true }
                } } }
                if found {
                    shriekCooldown = 10
                    warningLevel += 1
                    sfx(.sculkShriek, 1.2, at: V3(Float(c.x), Float(c.y), Float(c.z)) + 0.5)
                    applyEffect(.darkness, amp: 0, seconds: 12)
                    if warningLevel >= 4 {
                        warningLevel = 0
                        if !mobs.mobs.contains(where: { $0.kind == .warden }) {
                            let a = Rand.float(in: 0..<(2 * .pi))
                            let x = Int(floor(pp.x + cosf(a) * 6)), z = Int(floor(pp.z + sinf(a) * 6))
                            var y = c.y + 3
                            while y > c.y - 6 && !Blocks.collide[Int(world.block(x, y - 1, z))] { y -= 1 }
                            let w = Mob(.warden, at: V3(Float(x) + 0.5, Float(y), Float(z) + 0.5))
                            w.anger = 80
                            w.emergeTime = 6.7
                            mobs.mobs.append(w)
                            sfx(.wardenEmerge, 2, at: w.pos)
                        }
                    }
                }
            }
        }
        if shriekDecay > 0 { shriekDecay -= 1 } else { shriekDecay = 600; warningLevel = max(0, warningLevel - 1) }
    }

    // Murk catalysts spread murk where mobs die nearby (XP-sized bloom).
    func sculkBloom(at pos: V3, xp: Int) {
        guard xp > 0, Blocks.has("sculk_catalyst") else { return }
        let cat = Blocks.id("sculk_catalyst")
        let c = IVec3(Int(floor(pos.x)), Int(floor(pos.y)), Int(floor(pos.z)))
        var near = false
        for dy in -8...8 { for dz in -8...8 { for dx in -8...8 where world.block(c.x + dx, c.y + dy, c.z + dz) == cat { near = true } } }
        guard near else { return }
        let sculk = Blocks.id("sculk")
        var n = min(20, xp)
        for _ in 0..<60 where n > 0 {
            let q = IVec3(c.x + Rand.int(in: -3...3), c.y - 1 + Rand.int(in: -1...0), c.z + Rand.int(in: -3...3))
            let b = world.block(q.x, q.y, q.z)
            if Blocks.opaque[Int(b)] && b != sculk && Blocks.hardness[Int(b)] >= 0 && world.block(q.x, q.y + 1, q.z) == AIR {
                world.setBlockAsync(q.x, q.y, q.z, sculk); n -= 1
            }
        }
    }

    // Random ticks for the new blocks.
    func newBlockRandomTick(_ p: IVec3, _ b: BlockID, _ key: String) {
        let base = Blocks.groupBase[Int(b)]
        let st = Int(b - base)
        switch key {
        case "frosted_ice":
            if st < 3 { world.setBlockAsync(p.x, p.y, p.z, b + 1) } else { world.setBlockAsync(p.x, p.y, p.z, WATER) }
        case "cocoa":
            if st < 2 && Rand.int(in: 0..<5) == 0 { world.setBlockAsync(p.x, p.y, p.z, b + 1) }
        case "turtle_egg":
            // Hatch at night after a few cracks.
            if daylight < 0.4 && Rand.int(in: 0..<3) == 0 {
                world.setBlockAsync(p.x, p.y, p.z, st > 0 ? b - 1 : AIR)
                let t = Mob(.turtle, at: V3(Float(p.x) + 0.5, Float(p.y), Float(p.z) + 0.5))
                t.baby = true; t.scale = 0.3
                t.home = t.pos
                mobs.mobs.append(t)
            }
        case "frogspawn":
            if Rand.int(in: 0..<4) == 0 {
                world.setBlockAsync(p.x, p.y, p.z, AIR)
                for _ in 0..<Rand.int(in: 2...5) { mobs.mobs.append(Mob(.tadpole, at: V3(Float(p.x) + 0.5, Float(p.y) - 0.5, Float(p.z) + 0.5))) }
            }
        case "dried_ghast":
            // Next to water it soaks up a stage every few random ticks (about 20 minutes to hatch); dry, it shrivels back.
            var wet = false
            for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)] where !wet {
                wet = Blocks.fluidKind[Int(world.block(p.x + d.x, p.y + d.y, p.z + d.z))] == 1
            }
            if wet && Rand.int(in: 0..<4) == 0 {
                if st < 3 { world.setBlockAsync(p.x, p.y, p.z, b + 1) }
                else {
                    world.setBlockAsync(p.x, p.y, p.z, AIR)
                    let w = Mob(.happyGhast, at: V3(Float(p.x) + 0.5, Float(p.y), Float(p.z) + 0.5))
                    w.baby = true; w.scale = 0.25; w.persistent = true
                    mobs.mobs.append(w)
                    sfx(.mob(.happyGhast, .ambient), 0.8, at: w.pos)
                }
            } else if !wet && st > 0 && Rand.int(in: 0..<6) == 0 {
                world.setBlockAsync(p.x, p.y, p.z, b - 1)
            }
        case "sniffer_egg":
            if Rand.int(in: 0..<20) == 0 {
                world.setBlockAsync(p.x, p.y, p.z, AIR)
                let s = Mob(.sniffer, at: V3(Float(p.x) + 0.5, Float(p.y), Float(p.z) + 0.5)); s.baby = true; s.scale = 0.5
                mobs.mobs.append(s)
            }
        case "bee_nest", "beehive":
            break                                           // honey comes from bees returning with nectar (Bees.swift)
        case "torchflower_crop":
            if st < 1 { world.setBlockAsync(p.x, p.y, p.z, b + 1) } else { world.setBlockAsync(p.x, p.y, p.z, Blocks.id("torchflower")) }
        case "pitcher_crop":
            if st < 4 { world.setBlockAsync(p.x, p.y, p.z, b + 1) } else if Blocks.has("pitcher_plant") { world.setBlockAsync(p.x, p.y, p.z, Blocks.id("pitcher_plant")) }
        default: break
        }
    }
}
