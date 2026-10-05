import Foundation
import simd

// Drinking, throwing and splashing potions; lingering clouds; tipped arrows; bottles and cauldrons.
extension Game {
    // Applies a potion type's effects to the player, scaled (splash distance / lingering / arrows).
    func applyPotion(_ t: PotionType, scale: Float, durationScale: Float = 1, instantScale: Float = 1) {
        for (e, secs, amp) in t.effects {
            if e.instant {
                if scale >= 0.5 || e == .instantHealth || e == .instantDamage {
                    let n = Int((Float(e == .instantHealth ? 4 << amp : 6 << amp) * scale * instantScale).rounded())
                    if e == .instantHealth { heal(n) } else if n > 0 { damage(n, "was killed by magic", bypassArmor: true, type: .magic) }
                }
            } else {
                let d = secs * durationScale * scale
                if d >= 1 { applyEffect(e, amp: amp, seconds: d) }
            }
        }
    }

    func applyPotion(_ t: PotionType, to m: Mob, scale: Float, durationScale: Float = 1) {
        for (e, secs, amp) in t.effects {
            if e.instant {
                if e == .instantHealth || e == .instantDamage {
                    // Scaled instant: approximate with the level when close to the centre.
                    if scale > 0.3 { m.applyEffect(e, amp: scale > 0.8 ? amp : max(0, amp - 1), seconds: 0, game: self) }
                }
            } else {
                let d = secs * durationScale * scale
                if d >= 1 { m.applyEffect(e, amp: amp, seconds: d, game: self) }
            }
        }
    }

    // A thrown potion (or bottle o' enchanting) lands.
    func potionImpact(_ item: ItemID, at: V3, direct: Mob?, hitPlayer: Bool) {
        sfx(.glassBreak, 0.8, at: at)
        if Items.key(item) == "experience_bottle" {
            addXPOrbs(3 + Rand.int(in: 0...4) + Rand.int(in: 0...4), at: at)
            particles.explosion(at: at, power: 0.3)
            return
        }
        guard case let (form, t)? = Potions.potion(of: item) else { return }
        let col = TextureGen.hex(t.color)
        for _ in 0..<24 {
            let d = simd_normalize(V3(Rand.float(in: -1...1), Rand.float(in: 0.2...1), Rand.float(in: -1...1)))
            particles.add(Particle(pos: at, vel: d * Rand.float(in: 1...3), life: 0.8, maxLife: 0.8, layer: Int(Tex.id("smoke")),
                                   uv0: V2(0, 0), uvSize: 1, size: 0.1, gravity: 2, color: V3(col.x, col.y, col.z), collide: false, glow: true))
        }
        if form == 2 {
            // Lingering: a 3-block cloud that shrinks over 30 s, applying a quarter duration per second.
            clouds.append(AcidCloud(pos: at - V3(0, 0.3, 0), radius: 3, time: 30, potion: item, maxTime: 30))
            return
        }
        // Splash: everything within 4 blocks, scaled by distance (a direct hit counts as full).
        let pd = simd_length(player.pos + V3(0, 0.9, 0) - at)
        if pd < 4 { applyPotion(t, scale: hitPlayer ? 1 : 1 - pd / 4) }
        for m in mobs.mobs {
            let d = simd_length(m.pos + V3(0, m.height / 2, 0) - at)
            if d < 4 || m === direct { applyPotion(t, to: m, scale: m === direct ? 1 : 1 - d / 4) }
        }
        // Water splash puts out fire.
        if t.key == "water" {
            if pd < 4 { onFire = 0 }
            let c = IVec3(Int(floor(at.x)), Int(floor(at.y)), Int(floor(at.z)))
            for dz in -1...1 { for dx in -1...1 { for dy in -1...1 where world.block(c.x + dx, c.y + dy, c.z + dz) == FIRE {
                world.setBlock(c.x + dx, c.y + dy, c.z + dz, AIR)
            } } }
        }
    }

    // Tipped arrow hit: 1/8 duration.
    func arrowEffects(_ tip: ItemID, onPlayer: Bool, mob: Mob?) {
        guard case let (_, t)? = Potions.potion(of: tip) else { return }
        if onPlayer { applyPotion(t, scale: 1, durationScale: 0.125) }
        if let m = mob { applyPotion(t, to: m, scale: 1, durationScale: 0.125) }
    }

    // Lingering potion and dragon breath clouds.
    func cloudTick(_ dt: Float) {
        guard !clouds.isEmpty else { return }
        for i in clouds.indices {
            clouds[i].time -= dt
            clouds[i].tick -= dt
            let c = clouds[i]
            var color = V3(0.75, 0.2, 0.9)
            var pt: PotionType?
            if c.potion != 0, case let (_, t)? = Potions.potion(of: c.potion) {
                pt = t
                let h = TextureGen.hex(t.color)
                color = V3(h.x, h.y, h.z)
                // Lingering clouds shrink as they age.
                clouds[i].radius = 3 * c.time / max(1, c.maxTime) - c.used
                if clouds[i].radius < 0.5 { clouds[i].time = 0 }          // used up
            } else if c.maxTime > 0 {
                // Wyrm fireball clouds spread out (3 -> 7) as they age.
                clouds[i].radius = 3 + 4 * (1 - max(0, c.time) / c.maxTime)
            }
            if Rand.float(in: 0..<1) < dt * 30 {
                let a = Rand.float(in: 0..<(2 * .pi)), r = Rand.float(in: 0..<c.radius)
                particles.add(Particle(pos: c.pos + V3(cosf(a) * r, 0.1, sinf(a) * r), vel: V3(0, 0.4, 0), life: 1, maxLife: 1,
                                       layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1, size: 0.12, gravity: -0.2,
                                       color: color, collide: false, glow: true))
            }
            guard c.tick <= 0 else { continue }
            clouds[i].tick = 1
            let radius = clouds[i].radius
            // Every player standing in it (split screen: player 2 too).
            coop.eachSeat(self) {
                let d = self.player.pos - c.pos
                guard simd_length(V2(d.x, d.z)) < radius && abs(d.y) < 2 else { return }
                // Lingering: a quarter of the duration, instant effects at half strength (reference: 2 heal, 3 harm).
                if let t = pt { self.applyPotion(t, scale: 1, durationScale: 0.25, instantScale: 0.5); self.clouds[i].used += 0.5 }
                else { self.hurtPlayer(6, from: c.pos, cause: "was killed by Wyrm's Breath", knockback: 0, type: .magic) }
            }
            if let t = pt {
                for m in mobs.mobs {
                    let md = m.pos - c.pos
                    if simd_length(V2(md.x, md.z)) < radius && abs(md.y) < 2 { applyPotion(t, to: m, scale: 1, durationScale: 0.25); clouds[i].used += 0.5 }
                }
            }
        }
        clouds.removeAll { $0.time <= 0 }
    }

    // Drinks the held potion / milk / honey (after the 1.6 s use time).
    func finishDrink(_ h: ItemStack) {
        let key = Items.key(h.item)
        sfx(.drink, 0.7)
        if case let (_, t)? = Potions.potion(of: h.item) {
            applyPotion(t, scale: 1)
            if survival { inventory.held = ItemStack(Items.id("glass_bottle"), 1) }
            return
        }
        if key == "milk_bucket" {
            foodEffects(key)
            if survival { inventory.held = ItemStack(Items.id("bucket"), 1) }
            return
        }
        if key == "honey_bottle" {
            foodEffects(key)
        }
        if key == "ominous_bottle" {
            applyEffect(.badOmen, amp: min(4, max(0, h.damage)), seconds: 6000)
            consumeHeld()
        }
    }

    // Throws the held splash / lingering potion or bottle o' enchanting.
    func throwHeld() -> Bool {
        let h = held
        let key = Items.key(h.item)
        let throwable = key == "experience_bottle" || Potions.potion(of: h.item).map { $0.form == 1 || $0.form == 2 } ?? false
        guard throwable else { return false }
        var d = player.look
        d.y += 0.1
        projectiles.fireball(from: player.eye + player.look * 0.4, dir: simd_normalize(d), big: false, byPlayer: true, potion: h.item)
        if let f = projectiles.fireballs.last { f.vel = simd_normalize(d) * (key == "experience_bottle" ? 14 : 10) }
        sfx(.potionThrow, 0.6)
        consumeHeld()
        swing = 1
        return true
    }

    // Experience orbs fly to the nearby player; modelled as going straight to them.
    func addXPOrbs(_ n: Int, at: V3) {
        if simd_length(player.pos - at) < 16 { addXP(n) }
    }

    // Glass bottles fill from water; cauldrons take and give water.
    func useBottleOrCauldron(_ t: (hit: IVec3, normal: IVec3)?) -> Bool {
        let key = Items.key(held.item)
        if let t = t {
            let b = world.block(t.hit.x, t.hit.y, t.hit.z)
            let bk = Blocks.key(Blocks.groupBase[Int(b)])
            let p = t.hit
            let at = V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5
            if bk == "cauldron" || bk == "water_cauldron" {
                let level = bk == "cauldron" ? 0 : Int(b - Blocks.groupBase[Int(b)]) + 1
                func setLevel(_ l: Int) {
                    world.setBlock(p.x, p.y, p.z, l == 0 ? Blocks.id("cauldron") : Blocks.id("water_cauldron") + BlockID(l - 1))
                }
                // Washing dye off leather armour (and banner layers) costs a level of water.
                if level > 0 && (held.def.name.hasPrefix("leather_") || Blocks.shape[Int(held.def.block ?? 0)] == "banner"), var h = Optional(held), h.pat != nil {
                    if Blocks.shape[Int(h.def.block ?? 0)] == "banner" { h.pat = (h.pat?.dropLast()).map(Array.init); if h.pat?.isEmpty == true { h.pat = nil } }
                    else { h.pat = nil }
                    inventory.held = h
                    setLevel(level - 1)
                    sfx(.splash, 0.4, at: at)
                    return true
                }
                if key == "water_bucket" {
                    setLevel(3); sfx(.splash, 0.4, at: at)
                    if survival { inventory.held = ItemStack(Items.id("bucket"), 1) }
                    return true
                }
                if key == "lava_bucket" && level == 0 {
                    world.setBlock(p.x, p.y, p.z, Blocks.id("lava_cauldron")); sfx(.fizz, 0.4, at: at)
                    if survival { inventory.held = ItemStack(Items.id("bucket"), 1) }
                    return true
                }
                if key == "bucket" && level == 3 {
                    setLevel(0); sfx(.splash, 0.4, at: at)
                    giveOrReplaceHeld(ItemStack(Items.id("water_bucket"), 1))
                    return true
                }
                if key == "glass_bottle" && level > 0 {
                    setLevel(level - 1); sfx(.splash, 0.3, at: at)
                    giveOrReplaceHeld(ItemStack(Potions.item(0, "water")!, 1))
                    return true
                }
                if case let (form, pt)? = Potions.potion(of: held.item), form == 0, pt.key == "water", level < 3 {
                    setLevel(level + 1); sfx(.splash, 0.3, at: at)
                    if survival { inventory.held = ItemStack(Items.id("glass_bottle"), 1) }
                    return true
                }
                // Washing dyed leather / banners would go here; leather armour is undyed in this game.
                return false
            }
            if bk == "lava_cauldron" && key == "bucket" {
                world.setBlock(p.x, p.y, p.z, Blocks.id("cauldron"))
                giveOrReplaceHeld(ItemStack(Items.id("lava_bucket"), 1))
                return true
            }
        }
        if key == "glass_bottle" {
            // Scoop water from the targeted water block (or the water the look ray crosses).
            var tt: Float = 0
            while tt < 5 {
                let q = player.eye + player.look * tt
                let c = IVec3(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z)))
                let b = world.block(c.x, c.y, c.z)
                if Blocks.fluidKind[Int(b)] == 1 {
                    sfx(.splash, 0.3)
                    giveOrReplaceHeld(ItemStack(Potions.item(0, "water")!, 1))
                    return true
                }
                if Blocks.targetable(b) { break }
                tt += 0.1
            }
        }
        return false
    }

    // One held item is used up and replaced by `s` (or `s` goes into the inventory).
    func giveOrReplaceHeld(_ s: ItemStack) {
        if !survival { let rest = inventory.add(s); if !rest.isEmpty { dropItem(rest) }; return }
        var h = held
        h.count -= 1
        if h.count <= 0 { inventory.held = s; return }
        inventory.held = h
        let rest = inventory.add(s)
        if !rest.isEmpty { dropItem(rest) }
    }

    // After consumeHeld(): put the container (bowl, bottle) back in the hand or the inventory.
    func giveOrReplaceHeldAfterConsume(_ s: ItemStack) {
        guard survival else { return }
        if held.isEmpty { inventory.held = s; return }
        let rest = inventory.add(s)
        if !rest.isEmpty { dropItem(rest) }
    }

    // First arrow (plain or tipped) in the inventory, hotbar first.
    func arrowSlot() -> Int? {
        let arrow = Items.id("arrow")
        for i in 0..<36 {
            let s = inventory.main[i]
            if s.isEmpty { continue }
            if s.item == arrow { return i }
            if case let (form, _)? = Potions.potion(of: s.item), form == 3 { return i }
        }
        return nil
    }
}
