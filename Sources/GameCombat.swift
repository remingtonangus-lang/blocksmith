import Foundation
import simd

// Shields, crossbows, tridents and fishing (reference timings and numbers).

// A cast fishing bobber.
final class Bobber {
    var pos: V3
    var vel: V3
    var inWater = false
    var wait: Float                // seconds until fish start approaching
    var approach: Float = 0        // seconds of a fish swimming in
    var bite: Float = 0            // > 0 while a fish is on the hook
    weak var hooked: Mob?
    init(_ p: V3, _ v: V3, wait: Float) { pos = p; vel = v; self.wait = wait }
}

extension Game {
    // MARK: Shield

    var shieldInHand: Bool { Items.key(held.item) == "shield" || (Items.key(inventory.offhand[0].item) == "shield" && !heldHasUse) }
    var heldHasUse: Bool {
        let d = held.def
        let k = d.name
        return d.food != nil || d.drink || k == "bow" || k == "crossbow" || k == "trident" || k.hasSuffix("_spear") || k == "fishing_rod" || d.block != nil
    }

    // Returns true if the shield took the hit.
    func shieldBlocks(_ amount: Int, from src: V3, type: DamageType, attacker: Mob?) -> Bool {
        guard blocking, type == .generic || type == .projectile || type == .explosion else { return false }
        var to = src - player.pos
        to.y = 0
        let l = simd_length(to)
        guard l > 0.01 else { return false }
        let look = simd_normalize(V3(player.look.x, 0, player.look.z))
        guard simd_dot(look, to / l) > 0 else { return false }
        if type == .projectile { achieve("deflect") }
        // Shield wear: 1 + floor(damage) for hits of 3 or more.
        let slotIsMain = Items.key(held.item) == "shield"
        var s = slotIsMain ? held : inventory.offhand[0]
        if amount >= 3 && survival && !Enchant.wearSkipped(s) {
            s.damage += 1 + amount
            if s.damage >= s.def.durability { s = .empty; sfx(.shieldBreak, 0.9) }
            if slotIsMain { inventory.held = s } else { inventory.offhand[0] = s }
        }
        sfx(.shieldBlock, 0.9, at: player.pos + V3(0, 1, 0))
        // Axes (brigands, players) disable the shield for 5 s.
        if let a = attacker, a.kind == .vindicator || a.kind == .piglinBrute { shieldCooldown = 5; blocking = false; sfx(.shieldBreak, 0.7) }
        if let a = attacker, a.kind == .ravager { a.stun = 2 }
        if let a = attacker, type == .generic { a.hit(from: player.pos, damage: 0, knockback: 0.5) }
        return true
    }

    // MARK: Crossbow

    // Charge by holding use; once loaded, the next use fires (multishot: three arrows).
    func crossbowUse(_ useHeld: Bool, _ useNow: Bool, _ dt: Float) -> Bool {
        var h = held
        guard Items.key(h.item) == "crossbow" else { crossbowCharge = 0; return false }
        if h.tag != 0 {
            guard useNow else { return true }
            let multi = Enchant.level(.multishot, h) > 0
            let pierce = Enchant.level(.piercing, h)
            // The ammo by name (contents survive a save; the raw ItemID in `tag` shifts when items are added).
            let ammo = h.contents?.first?.item ?? ItemID(h.tag)
            let angles: [Float] = multi ? [0, -0.17, 0.17] : [0]
            for (i, a) in angles.enumerated() {
                let dir = simd_normalize(player.look + V3(cosf(player.yaw), 0, -sinf(player.yaw)) * tanf(a))
                if Items.key(ammo) == "firework_rocket" {
                    let rk = h.contents?.first ?? ItemStack(ammo, 1)
                    rockets.append(Rocket(at: player.eye + dir * 0.5, dir: dir, flight: rk.tag, stars: rk.contents ?? [], crossbow: true))
                    continue
                }
                let arrow = projectiles.shoot(from: player.eye, dir: dir, speed: 63, fromPlayer: true, damage: 2)
                arrow.pierce = pierce
                arrow.crit = true                                // crossbow bolts always crit (reference: 7-11)
                if Potions.potion(of: ammo) != nil { arrow.tip = ammo }
                arrow.pickup = survival && i == 0
            }
            h.tag = 0
            h.contents = nil
            inventory.held = h
            sfx(.crossbowShoot, 1)
            damageHeld(multi ? 3 : 1)
            swing = 1
            return true
        }
        let qc = Enchant.level(.quickCharge, h)
        let need = max(0, 1.25 - 0.25 * Float(qc))
        let rocketOff = Items.key(inventory.offhand[0].item) == "firework_rocket"
        if useHeld, let slot = rocketOff ? -2 : (arrowSlot() ?? (survival ? nil : -1)) {
            crossbowCharge += dt
            if crossbowCharge >= need {
                crossbowCharge = 0
                if slot == -2 {
                    // Rockets load from the off hand.
                    var r = inventory.offhand[0]
                    h.tag = Int(r.item)
                    h.contents = [r.with(count: 1)]
                    if survival { r.count -= 1; inventory.offhand[0] = r.count > 0 ? r : .empty }
                } else if slot >= 0 {
                    h.tag = Int(inventory.main[slot].item)
                    h.contents = [inventory.main[slot].with(count: 1)]
                    if survival { var s = inventory.main[slot]; s.count -= 1; inventory.main[slot] = s }
                } else {
                    h.tag = Int(Items.id("arrow"))
                    h.contents = [ItemStack(Items.id("arrow"), 1)]
                }
                inventory.held = h
                sfx(.crossbowLoad, 0.8)
            }
            return true
        }
        crossbowCharge = 0
        return false
    }

    // MARK: Trident

    // Hold to raise, release after 0.5 s to throw (riptide: launch yourself instead when wet).
    func tridentUse(_ useHeld: Bool, _ dt: Float) -> Bool {
        let h = held
        guard Items.key(h.item) == "trident" else { tridentCharge = 0; return false }
        if useHeld { tridentCharge += dt; return true }
        guard tridentCharge > 0 else { return false }
        let charged = tridentCharge >= 0.5
        tridentCharge = 0
        guard charged else { return true }
        let rip = Enchant.level(.riptide, h)
        if rip > 0 {
            guard player.inWater || isRainingAt(player.pos) else { return true }
            let f = 3 * Float(1 + rip) / 4
            player.vel = player.look * f * 20
            player.airPeak = player.pos.y
            damageHeld(1)
            sfx(.riptide, 0.9)
            return true
        }
        let a = projectiles.shoot(from: player.eye, dir: player.look, speed: 50, fromPlayer: true, damage: 8 / 2.5)
        a.trident = h
        a.pickup = survival
        if survival { inventory.held = .empty }
        sfx(.tridentThrow, 0.9)
        swing = 1
        return true
    }

    // Loyalty tridents fly back; channeling calls lightning on a mob hit in a thunderstorm.
    func tridentHit(_ a: Arrow, mob: Mob?) {
        guard let t = a.trident else { return }
        if let m = mob {
            if Enchant.level(.channeling, t) > 0 && weather.thunder > 0.5 && skyExposed(Int(floor(m.pos.x)), Int(floor(m.pos.y + 1)), Int(floor(m.pos.z))) {
                strike(m.pos)
            }
            let imp = Enchant.level(.impaling, t)
            if imp > 0 && Enchant.aquatic(m) {
                m.hit(from: a.pos, damage: Int(2.5 * Float(imp)), knockback: 0)
            }
        }
        if Enchant.level(.loyalty, t) > 0 { a.returning = true; a.stuck = false }
    }

    // MARK: Fishing

    func fishingUse(_ useNow: Bool) -> Bool {
        guard Items.key(held.item) == "fishing_rod" else { return false }
        guard useNow else { return true }
        if let b = bobber {
            // Reel in.
            if b.bite > 0 { catchFish(b) }
            else if let m = b.hooked { m.vel += simd_normalize(player.pos - m.pos + V3(0, 1e-3, 0)) * 8 + V3(0, 3, 0); damageHeld(3) }
            else if !b.inWater && Blocks.collide[Int(world.block(Int(floor(b.pos.x)), Int(floor(b.pos.y - 0.1)), Int(floor(b.pos.z))))] { damageHeld(2) }
            bobber = nil
            sfx(.fishReel, 0.5)
            swing = 1
            return true
        }
        let lure = Enchant.level(.lure, held)
        let wait = max(1, Rand.float(in: 5...30) - 5 * Float(lure))
        bobber = Bobber(player.eye + player.look * 0.5, player.look * 18 + V3(0, 3, 0), wait: wait)
        sfx(.fishCast, 0.6)
        swing = 1
        return true
    }

    func bobberTick(_ dt: Float) {
        guard let b = bobber else { return }
        if Items.key(held.item) != "fishing_rod" || simd_length(b.pos - player.pos) > 32 { bobber = nil; return }
        let cell = world.block(Int(floor(b.pos.x)), Int(floor(b.pos.y)), Int(floor(b.pos.z)))
        b.inWater = Blocks.fluidKind[Int(cell)] == 1
        if let m = b.hooked {
            b.pos = m.pos + V3(0, m.height * 0.8, 0)
            if m.health <= 0 { b.hooked = nil }
            return
        }
        if b.inWater {
            // Float at the surface.
            b.vel.y += (b.pos.y.truncatingRemainder(dividingBy: 1) < 0.85 ? 6 : -2) * dt
            b.vel *= expf(-4 * dt)
            b.wait -= dt
            if b.wait <= 0 && b.approach <= 0 && b.bite <= 0 {
                b.approach = Rand.float(in: 1...4)
            }
            if b.approach > 0 {
                b.approach -= dt
                if Rand.float(in: 0..<1) < dt * 20 { particles.smoke(at: b.pos + V3(Rand.float(in: -1...1) * b.approach * 0.4, -0.1, Rand.float(in: -1...1) * b.approach * 0.4), dark: false) }
                if b.approach <= 0 {
                    b.bite = Rand.float(in: 1...2)
                    b.vel.y = -3
                    sfx(.fishSplash, 0.8, at: b.pos)
                }
            } else if b.bite > 0 {
                b.bite -= dt
                if b.bite <= 0 { b.wait = Rand.float(in: 5...30) - 5 * Float(Enchant.level(.lure, held)) }
            }
        } else {
            b.vel.y -= 20 * dt
            b.vel *= expf(-0.5 * dt)
            if Blocks.collide[Int(cell)] { b.vel = .zero; b.pos.y = floor(b.pos.y) + 1 }
            if let h = mobs.raycast(b.pos, simd_normalize(b.vel + V3(0, 1e-4, 0)), maxDist: simd_length(b.vel) * dt + 0.2) {
                b.hooked = h.0
                h.0.hit(from: b.pos, damage: 0, knockback: 0)
            }
        }
        b.pos += b.vel * dt
    }

    // Reference fishing loot: fish / junk / treasure by Luck of the Sea and Luck.
    func catchFish(_ b: Bobber) {
        achieve("fish")
        let luck = Float(Enchant.level(.luckOfTheSea, held) + effects.level(.luck))
        let junkW = max(0, 10 - 2 * luck), treasureW = 5 + 2 * luck, fishW = max(0, 85 - luck)
        var r = Rand.float(in: 0..<(junkW + treasureW + fishW))
        var out: ItemStack
        if r < fishW {
            let f: [(String, Int)] = [("cod", 60), ("salmon", 25), ("tropical_fish", 2), ("pufferfish", 13)]
            out = ItemStack(Items.id(weighted(f)), 1)
        } else if r < fishW + junkW {
            r = 0
            let j: [(String, Int)] = [("lily_pad", 17), ("leather_boots", 10), ("leather", 10), ("bone", 10), ("potion_water", 10), ("string", 5),
                                      ("fishing_rod", 2), ("bowl", 10), ("stick", 5), ("ink_sac", 1), ("tripwire_hook", 10), ("rotten_flesh", 10)]
            out = ItemStack(Items.id(weighted(j.filter { Items.has($0.0) })), 1)
            if out.def.durability > 0 { out.damage = Int(Float(out.def.durability) * Rand.float(in: 0.1...0.9)) }
        } else {
            let t: [(String, Int)] = [("bow", 1), ("enchanted_book", 1), ("fishing_rod", 1), ("name_tag", 1), ("nautilus_shell", 1), ("saddle", 1)]
            let k = weighted(t)
            if k == "enchanted_book" { out = Enchant.withLevels(Items.id("book"), 30, treasure: true) }
            else if k == "bow" || k == "fishing_rod" {
                out = Enchant.withLevels(Items.id(k), 30, treasure: true)
                out.damage = Int(Float(out.def.durability) * Rand.float(in: 0...0.25))
            } else { out = ItemStack(Items.id(k), 1) }
        }
        let dir = player.pos + V3(0, 1, 0) - b.pos
        drops.spawn(out, at: b.pos + V3(0, 0.3, 0), vel: dir * 1.1 + V3(0, sqrtf(simd_length(dir)) * 1.6, 0))
        addXP(Rand.int(in: 1...6))
        damageHeld(1)
        sfx(.fishSplash, 0.6, at: b.pos)
    }

    private func weighted(_ t: [(String, Int)]) -> String {
        let total = t.reduce(0) { $0 + $1.1 }
        var r = Rand.int(in: 0..<max(1, total))
        for e in t { r -= e.1; if r < 0 { return e.0 } }
        return t.first?.0 ?? "cod"
    }

    // Fishing line and bobber.
    func writeBobber(_ wr: inout EntityWriter, eye: V3, right: V3, up: V3) {
        guard let b = bobber else { return }
        let white = Int(Tex.id("smoke"))
        let r35: V3 = right * 0.35
        let u25: V3 = up * 0.25
        let l6: V3 = player.look * 0.6
        let hand: V3 = player.eye + r35 - u25 + l6
        var prev: V3 = hand
        let n = 12
        let span: V3 = b.pos - hand
        let sag: Float = 0.4 * min(1, simd_length(span) / 8)
        for i in 1...n {
            let t = Float(i) / Float(n)
            var q: V3 = hand + span * t
            q.y -= sinf(t * .pi) * sag
            let a: V3 = prev - eye
            let c: V3 = q - eye
            let cr: V3 = simd_cross(c - a, player.look) + V3(1e-5, 0, 0)
            let side: V3 = simd_normalize(cr) * 0.01
            wr.quad([a - side, a + side, c + side, c - side], [V2(0.4, 0.4), V2(0.6, 0.4), V2(0.6, 0.6), V2(0.4, 0.6)], white, V4(0.1, 0.1, 0.1, 1))
            prev = q
        }
        let c = b.pos - eye
        wr.sprite(center: c, half: 0.1, right: right, up: up, layer: white, light: 1, tint: V3(1.4, 0.3, 0.3))
    }
}
