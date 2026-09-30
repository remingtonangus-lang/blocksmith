import Foundation
import simd

// Living-world rules: random ticks (crops, saplings, grass, farmland), leaf decay after logging,
// and the "use item on block/mob" interactions (hoe, seeds, bone meal, shears, breeding, milking, beds).
extension Game {
    // MARK: Random ticks (3 random blocks per 16^3 section per game tick, like the reference game)

    func randomTicks() {
        let w = world
        let pcx = floorDiv(Int(floor(player.pos.x)), CS), pcz = floorDiv(Int(floor(player.pos.z)), CS)
        let r = min(8, w.renderDistance)
        let rt = Blocks.randomTicks
        for dz in -r...r {
            for dx in -r...r {
                guard let c = w.chunks[ChunkKey(x: pcx + dx, z: pcz + dz)] else { continue }
                var hmax = 0
                for h in c.height where Int(h) > hmax { hmax = Int(h) }
                for sy in 0...min(NSEC - 1, (hmax + 1) >> 4) {
                    for _ in 0..<3 {
                        let lx = Int.random(in: 0..<16), ly = Int.random(in: 0..<16), lz = Int.random(in: 0..<16)
                        let y = sy * 16 + ly
                        let b = c.blocks[Chunk.index(lx, y, lz)]
                        if rt[Int(b)] { randomTick(IVec3(c.cx * CS + lx, y, c.cz * CS + lz), b) }
                    }
                }
            }
        }
        // Leaves whose tree was cut decay a few at a time.
        var n = 0
        while n < 4, let p = leafQueue.popLast() {
            n += 1
            let b = world.block(p.x, p.y, p.z)
            guard Blocks.key(b).hasSuffix("leaves"), !placedLeaves.contains(p) else { continue }
            if !logNearby(p, radius: 4) {
                world.setBlock(p.x, p.y, p.z, AIR)
                for s in Mining.drops(b, .empty) { drops.spawn(s, at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)) }
            }
        }
    }

    private func logNearby(_ p: IVec3, radius: Int) -> Bool {
        // BFS through leaves looking for a log within `radius` steps.
        var seen = Set<IVec3>([p])
        var frontier = [p]
        for _ in 0..<radius {
            var next: [IVec3] = []
            for q in frontier {
                for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)] {
                    let n = q + d
                    if seen.contains(n) { continue }
                    seen.insert(n)
                    let k = Blocks.key(world.block(n.x, n.y, n.z))
                    if k.hasSuffix("_log") || k.hasSuffix("_wood") { return true }
                    if k.hasSuffix("leaves") { next.append(n) }
                }
            }
            frontier = next
        }
        return false
    }

    func queueLeafDecay(around p: IVec3) {
        for dy in -4...4 { for dz in -4...4 { for dx in -4...4 {
            let q = IVec3(p.x + dx, p.y + dy, p.z + dz)
            if Blocks.key(world.block(q.x, q.y, q.z)).hasSuffix("leaves") { leafQueue.insert(q, at: Int.random(in: 0...leafQueue.count)) }
        } } }
    }

    func randomTick(_ p: IVec3, _ b: BlockID) {
        let key = Blocks.key(Blocks.groupBase[Int(b)])
        let stage = Int(b - Blocks.groupBase[Int(b)])
        switch key {
        case "wheat", "carrots", "potatoes", "beetroots":
            let maxStage = key == "beetroots" ? 3 : 7
            guard stage < maxStage else { return }
            let l = world.lightAt(p.x, p.y, p.z)
            guard max(l.sky, l.block) >= 9 else { return }
            let below = Blocks.key(world.block(p.x, p.y - 1, p.z))
            let f: Float = below == "farmland_moist" ? 4 : 2
            if Float.random(in: 0..<1) < 1 / (floorf(25 / f) + 1) {
                world.setBlock(p.x, p.y, p.z, b + 1)
            }
        case "nether_wart":
            if stage < 3 && Int.random(in: 0..<10) == 0 { world.setBlock(p.x, p.y, p.z, b + 1) }
        case "sugar_cane":
            // Grows to 3 tall, one block per ~16 random ticks.
            guard world.block(p.x, p.y + 1, p.z) == AIR, Int.random(in: 0..<16) == 0 else { return }
            var h = 1
            while h < 3 && world.block(p.x, p.y - h, p.z) == b { h += 1 }
            if h < 3 { world.setBlock(p.x, p.y + 1, p.z, b) }
        case "oak_sapling", "birch_sapling", "spruce_sapling":
            let l = world.lightAt(p.x, p.y + 1, p.z)
            if max(l.sky, l.block) >= 9 && Int.random(in: 0..<7) == 0 { growTree(p, key) }
        case "farmland":
            let wet = waterNear(p)
            let isWet = Blocks.key(b) == "farmland_moist"
            if wet && !isWet { world.setBlock(p.x, p.y, p.z, Blocks.id("farmland_moist")) }
            else if !wet && isWet { world.setBlock(p.x, p.y, p.z, Blocks.id("farmland")) }
            else if !wet && !Blocks.isPlant(world.block(p.x, p.y + 1, p.z)) && Blocks.render[Int(world.block(p.x, p.y + 1, p.z))] != RenderType.model.rawValue {
                if Int.random(in: 0..<4) == 0 { world.setBlock(p.x, p.y, p.z, DIRT) }
            }
        case "grass_block":
            // Dies under opaque blocks; spreads to nearby lit dirt.
            if Blocks.opaque[Int(world.block(p.x, p.y + 1, p.z))] { world.setBlock(p.x, p.y, p.z, DIRT); return }
            for _ in 0..<4 {
                let q = IVec3(p.x + Int.random(in: -1...1), p.y + Int.random(in: -3...1), p.z + Int.random(in: -1...1))
                if world.block(q.x, q.y, q.z) == DIRT && !Blocks.opaque[Int(world.block(q.x, q.y + 1, q.z))] && !Blocks.isLiquid(world.block(q.x, q.y + 1, q.z)) {
                    let l = world.lightAt(q.x, q.y + 1, q.z)
                    if max(l.sky, l.block) >= 9 { world.setBlockAsync(q.x, q.y, q.z, GRASS) }
                }
            }
        default: break
        }
    }

    private func waterNear(_ p: IVec3) -> Bool {
        for dy in 0...1 { for dz in -4...4 { for dx in -4...4 where Blocks.isLiquid(world.block(p.x + dx, p.y + dy, p.z + dz)) { return true } } }
        return false
    }

    // Saplings grow into trees if there is room.
    func growTree(_ p: IVec3, _ sapling: String) {
        let (log, leaf): (BlockID, BlockID)
        switch sapling {
        case "birch_sapling": (log, leaf) = (BIRCH_LOG, BIRCH_LEAVES)
        case "spruce_sapling": (log, leaf) = (SPRUCE_LOG, SPRUCE_LEAVES)
        default: (log, leaf) = (LOG, LEAVES)
        }
        let spruce = sapling == "spruce_sapling"
        let h = spruce ? Int.random(in: 6...9) : Int.random(in: 4...6) + (sapling == "birch_sapling" ? 1 : 0)
        for y in 1...(h + 1) where !Blocks.replaceable[Int(world.block(p.x, p.y + y, p.z))] && y > 0 { return }
        var set: [(IVec3, BlockID)] = []
        for y in 0..<h { set.append((IVec3(p.x, p.y + y, p.z), log)) }
        let top = p.y + h
        if spruce {
            set.append((IVec3(p.x, top, p.z), leaf))
            let pattern = [1, 1, 2, 1, 2, 3, 2, 3]
            var k = 0
            var y = top - 1
            while y >= p.y + 2 {
                let r = k < pattern.count ? pattern[k] : 2
                for dz in -r...r { for dx in -r...r where dx * dx + dz * dz <= r * r + 1 && !(dx == 0 && dz == 0) { set.append((IVec3(p.x + dx, y, p.z + dz), leaf)) } }
                y -= 1; k += 1
            }
        } else {
            for dy in -2...1 {
                let y = top + dy - 1
                let r = dy >= 0 ? 1 : 2
                for dz in -r...r { for dx in -r...r {
                    if dy == 1 && abs(dx) + abs(dz) > 1 { continue }
                    if r == 2 && abs(dx) == 2 && abs(dz) == 2 && Bool.random() { continue }
                    if dx == 0 && dz == 0 && dy < 1 { continue }
                    set.append((IVec3(p.x + dx, y, p.z + dz), leaf))
                } }
            }
        }
        for (q, b) in set where Blocks.replaceable[Int(world.block(q.x, q.y, q.z))] || q == p {
            world.setBlockAsync(q.x, q.y, q.z, b)
        }
        world.setBlock(p.x, p.y, p.z, log)
    }

    // MARK: Using items on blocks

    // Returns true if the use was handled.
    func useItemOnBlock(_ t: (hit: IVec3, normal: IVec3)) -> Bool {
        let h = held
        let key = Items.key(h.item)
        let b = world.block(t.hit.x, t.hit.y, t.hit.z)
        let bkey = Blocks.key(Blocks.groupBase[Int(b)])
        // Minecart onto a rail.
        if key == "minecart" && Rails.isRail(b) {
            let cart = Mob(.minecart, at: V3(Float(t.hit.x) + 0.5, Float(t.hit.y) + 0.0625, Float(t.hit.z) + 0.5))
            cart.yaw = player.yaw
            mobs.mobs.append(cart)
            consumeHeld()
            sfx(.place(.stone), 0.6, at: cart.pos)
            swing = 1
            return true
        }
        // Shears carve a pumpkin (face toward the clicked side) and drop 4 seeds.
        if key == "shears" && bkey == "pumpkin" && t.normal.y == 0 {
            let f = t.normal.z == -1 ? 0 : (t.normal.z == 1 ? 1 : (t.normal.x == -1 ? 2 : 3))
            world.setBlock(t.hit.x, t.hit.y, t.hit.z, Blocks.id("carved_pumpkin") + BlockID(f))
            drops.spawn(ItemStack(Items.id("pumpkin_seeds"), 4), at: V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) + 0.5 + V3(Float(t.normal.x), 0, Float(t.normal.z)) * 0.6)
            damageHeld(1)
            sfx(.step(.plant), 1)
            swing = 1
            return true
        }
        // Shovel: grass into a dirt path.
        if h.def.tool == .shovel && (b == GRASS || Blocks.key(b) == "podzol" || Blocks.key(b) == "coarse_dirt" || Blocks.key(b) == "mycelium")
            && t.normal.y == 1 && world.block(t.hit.x, t.hit.y + 1, t.hit.z) == AIR {
            world.setBlock(t.hit.x, t.hit.y, t.hit.z, Blocks.id("dirt_path"))
            sfx(.step(.dirt), 1, at: V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) + 0.5)
            damageHeld(1)
            swing = 1
            return true
        }
        // Hoe: till grass/dirt with air above.
        if h.def.tool == .hoe && (b == GRASS || b == DIRT) && world.block(t.hit.x, t.hit.y + 1, t.hit.z) == AIR {
            world.setBlock(t.hit.x, t.hit.y, t.hit.z, Blocks.id("farmland"))
            sfx(.step(.dirt), 1, at: V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) + 0.5)
            damageHeld(1)
            swing = 1
            return true
        }
        // Seeds / crops onto farmland.
        if let crop = h.def.plants, bkey == (crop == "nether_wart" ? "soul_sand" : "farmland"), t.normal.y == 1, world.block(t.hit.x, t.hit.y + 1, t.hit.z) == AIR {
            world.setBlock(t.hit.x, t.hit.y + 1, t.hit.z, Blocks.id(crop))
            sfx(.place(.plant), 1, at: V3(Float(t.hit.x), Float(t.hit.y + 1), Float(t.hit.z)) + 0.5)
            consumeHeld()
            swing = 1
            return true
        }
        // Bone meal: grows crops and saplings, sprouts grass and flowers on grass blocks.
        if key == "bone_meal" {
            var used = false
            if ["wheat", "carrots", "potatoes", "beetroots"].contains(bkey) {
                let maxStage = bkey == "beetroots" ? 3 : 7
                let st = Int(b - Blocks.groupBase[Int(b)])
                if st < maxStage {
                    world.setBlock(t.hit.x, t.hit.y, t.hit.z, Blocks.groupBase[Int(b)] + BlockID(min(maxStage, st + Int.random(in: 2...5))))
                    used = true
                }
            } else if bkey.hasSuffix("_sapling") {
                if Float.random(in: 0..<1) < 0.45 { growTree(t.hit, bkey) }
                used = true
            } else if b == GRASS {
                for _ in 0..<24 {
                    let q = IVec3(t.hit.x + Int.random(in: -3...3), t.hit.y, t.hit.z + Int.random(in: -3...3))
                    if world.block(q.x, q.y, q.z) == GRASS && world.block(q.x, q.y + 1, q.z) == AIR {
                        world.setBlockAsync(q.x, q.y + 1, q.z, Float.random(in: 0..<1) < 0.85 ? TALL_GRASS : [RED_FLOWER, YELLOW_FLOWER][Int.random(in: 0...1)])
                    }
                }
                used = true
            }
            if used {
                consumeHeld()
                particles.hearts(at: V3(Float(t.hit.x) + 0.5, Float(t.hit.y) + 1, Float(t.hit.z) + 0.5))
                swing = 1
            }
            return used
        }
        // Flint and steel: prime TNT, light a portal frame, or start a fire.
        if key == "flint_and_steel" {
            if bkey == "tnt" {
                world.setBlock(t.hit.x, t.hit.y, t.hit.z, AIR)
                tnts.prime(at: t.hit)
            } else {
                let at = t.hit + t.normal
                if !tryLightPortal(at: at) { world.placeFire(at) }
            }
            sfx(.fizz, 1, at: V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) + 0.5)
            damageHeld(1)
            swing = 1
            return true
        }
        // Beds: sleep through the night and set the respawn point.
        if bkey.hasSuffix("_bed") || bkey.hasSuffix("_bed_head") {
            trySleep(at: t.hit)
            return true
        }
        return false
    }

    // Right-click on a mob with the held item.
    func useItemOnMob(_ m: Mob) -> Bool {
        let key = Items.key(held.item)
        if m.kind == .minecart {
            if riding === m { return false }
            riding = m
            player.pos = m.pos + V3(0, 0.35, 0)
            sfx(.click, 0.5, at: m.pos)
            return true
        }
        if m.kind == .piglin && key == "gold_ingot" && m.admire <= 0 && !m.baby {
            m.admire = 6
            m.aggro = false
            consumeHeld()
            sfx(.mobPiglin, 1, at: m.pos + V3(0, 1.6, 0))
            return true
        }
        if let food = MobManager.breedFood[m.kind], food.contains(key) {
            guard !m.baby, m.breedCooldown <= 0, m.inLove <= 0 else { return false }
            m.inLove = 30
            consumeHeld()
            particles.hearts(at: m.pos + V3(0, m.height, 0))
            return true
        }
        if m.kind == .sheep && key == "shears" && !m.sheared && !m.baby {
            m.sheared = true
            let wool = "\(m.woolColor)_wool"
            if Items.has(wool) { drops.spawn(ItemStack(Items.id(wool), Int.random(in: 1...3)), at: m.pos + V3(0, 1, 0)) }
            damageHeld(1)
            sfx(.step(.plant), 1, at: m.pos)
            return true
        }
        if key == "name_tag", let l = held.label, !l.isEmpty {
            m.customName = l
            m.persistent = true
            consumeHeld()
            return true
        }
        if m.kind == .villager && !m.baby { return openTrading(m) }
        if startCure(m) { return true }
        if m.kind == .cow && key == "bucket" && !m.baby {
            consumeHeld()
            let rest = inventory.add(ItemStack(Items.id("milk_bucket"), 1))
            if !rest.isEmpty { dropItem(rest) }
            return true
        }
        return false
    }

    // MARK: Beds

    func trySleep(at p: IVec3) {
        let night = dayFraction > 0.52 && dayFraction < 0.98
        spawnPoint = V3(Float(p.x) + 0.5, Float(p.y) + 0.6, Float(p.z) + 0.5)
        onToast?("Respawn point set")
        guard night else { onToast?("You can only sleep at night"); return }
        if mobs.mobs.contains(where: { $0.kind.hostile && simd_length($0.pos - player.pos) < 8 }) {
            onToast?("You may not rest now; there are monsters nearby")
            return
        }
        sleeping = 0.001
    }

    // Placing a bed: foot where clicked, head one block further in the look direction.
    func placeBed(_ item: ItemDef, at foot: IVec3) -> Bool {
        let facing = BlockRegistry.facingToward(yaw: player.yaw)
        // Head goes away from the player (the look direction), i.e. opposite of the "front toward player" facing.
        let dirs = [IVec3(0, 0, 1), IVec3(0, 0, -1), IVec3(1, 0, 0), IVec3(-1, 0, 0)]
        let head = foot + dirs[facing]
        guard Blocks.replaceable[Int(world.block(head.x, head.y, head.z))],
              Blocks.opaque[Int(world.block(foot.x, foot.y - 1, foot.z))],
              let base = item.block else { return false }
        let headBase = Blocks.id(Blocks.key(base) + "_head")
        world.setBlock(foot.x, foot.y, foot.z, base + BlockID(facing))
        world.setBlock(head.x, head.y, head.z, headBase + BlockID(facing))
        return true
    }

    // Removing either half of a bed removes the other one too.
    func breakBedPartner(_ p: IVec3, _ b: BlockID) {
        let key = Blocks.key(Blocks.groupBase[Int(b)])
        guard key.hasSuffix("_bed") || key.hasSuffix("_bed_head") else { return }
        let facing = Int(b - Blocks.groupBase[Int(b)])
        let dirs = [IVec3(0, 0, 1), IVec3(0, 0, -1), IVec3(1, 0, 0), IVec3(-1, 0, 0)]
        let other = key.hasSuffix("_head") ? p - dirs[facing] : p + dirs[facing]
        let ok = Blocks.key(Blocks.groupBase[Int(world.block(other.x, other.y, other.z))])
        if ok.hasSuffix("_bed") || ok.hasSuffix("_bed_head") { world.setBlock(other.x, other.y, other.z, AIR) }
    }
}

extension Game {
    // Lava, fire, magma and cactus hurt; burning continues until water puts it out.
    func hazardTick(_ dt: Float) {
        let p = player.pos
        let feet = world.block(Int(floor(p.x)), Int(floor(p.y + 0.1)), Int(floor(p.z)))
        let body = world.block(Int(floor(p.x)), Int(floor(p.y + 1)), Int(floor(p.z)))
        let under = world.block(Int(floor(p.x)), Int(floor(p.y - 0.1)), Int(floor(p.z)))
        let inLava = Blocks.fluidKind[Int(feet)] == 2 || Blocks.fluidKind[Int(body)] == 2
        if player.inWater && !inLava { onFire = 0 }
        contactTimer -= dt
        if contactTimer <= 0 {
            var dmg = 0
            var cause = ""
            if inLava { dmg = 4; cause = "tried to swim in lava"; onFire = 15 }
            else if feet == FIRE || body == FIRE || Blocks.key(feet) == "soul_fire" { dmg = 1; cause = "went up in flames"; onFire = max(onFire, 8) }
            else if Blocks.key(under) == "magma_block" && !player.sneaking && player.onGround { dmg = 1; cause = "discovered the floor was lava" }
            else {
                // Cactus: touching any side.
                let mn = V3(p.x - 0.31, p.y, p.z - 0.31), mx = V3(p.x + 0.31, p.y + 1.8, p.z + 0.31)
                outer: for y in Int(floor(mn.y))...Int(floor(mx.y)) { for z in Int(floor(mn.z))...Int(floor(mx.z)) { for x in Int(floor(mn.x))...Int(floor(mx.x)) {
                    if world.block(x, y, z) == CACTUS {
                        let c = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
                        if abs(c.x - p.x) < 0.31 + 0.4375 && abs(c.z - p.z) < 0.31 + 0.4375 { dmg = 1; cause = "was pricked to death"; break outer }
                    }
                } } }
            }
            if dmg > 0 { damage(dmg, cause, type: cause == "was pricked to death" ? .generic : .fire); contactTimer = 0.5 }
        }
        if onFire > 0 {
            onFire -= dt
            fireDamageTimer -= dt
            if fireDamageTimer <= 0 { fireDamageTimer = 1; damage(1, "burned to death", type: .fire) }
            if effects.has(.fireResistance) && !player.inWater { onFire = min(onFire, 0.5) }
        }
    }

    // Piglin bartering (weights of the reference game's barter table, total 459; potions and
    // enchanted items are left out until brewing/enchanting exist).
    func barter(_ m: Mob) {
        let table: [(String, Int, Int, Int)] = [
            ("ender_pearl", 2, 4, 10), ("string", 3, 9, 20), ("quartz", 5, 12, 20), ("obsidian", 1, 1, 40),
            ("crying_obsidian", 1, 3, 40), ("fire_charge", 1, 1, 40), ("leather", 2, 4, 40), ("soul_sand", 2, 8, 40),
            ("nether_brick", 2, 8, 40), ("spectral_arrow", 6, 12, 40), ("gravel", 8, 16, 40), ("blackstone", 8, 16, 40),
            ("iron_nugget", 10, 36, 10),
        ].filter { Items.has($0.0) }
        let total = table.reduce(0) { $0 + $1.3 }
        var r = Int.random(in: 0..<max(1, total))
        for e in table {
            r -= e.3
            if r < 0 {
                let dir = simd_normalize(player.pos - m.pos + V3(0, 0.001, 0))
                drops.spawn(ItemStack(Items.id(e.0), Int.random(in: e.1...e.2)), at: m.eye, vel: dir * 3 + V3(0, 2, 0))
                break
            }
        }
        sfx(.mobPiglin, 0.8, at: m.pos + V3(0, 1.6, 0))
    }
}

extension IVec3 {
    static func - (a: IVec3, b: IVec3) -> IVec3 { IVec3(a.x - b.x, a.y - b.y, a.z - b.z) }
}
