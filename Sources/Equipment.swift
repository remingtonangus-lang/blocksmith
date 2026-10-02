import Foundation
import simd

// Mob equipment (armor worn by zombies / skeletons, reference spawn odds and drop chances), armour
// damage reduction for mobs, the armour overlay model, and armor stands.
enum ArmorLook {
    static func color(_ item: ItemID) -> V3? {
        let k = Items.key(item)
        let mats: [(String, V3)] = [("leather_", V3(0.55, 0.35, 0.2)), ("chainmail_", V3(0.55, 0.55, 0.58)), ("iron_", V3(0.86, 0.86, 0.86)),
                                    ("golden_", V3(0.95, 0.82, 0.25)), ("diamond_", V3(0.3, 0.88, 0.84)), ("netherite_", V3(0.3, 0.27, 0.28)),
                                    ("turtle_", V3(0.3, 0.6, 0.25)), ("copper_", V3(0.78, 0.48, 0.33))]
        for (p, c) in mats where k.hasPrefix(p) { return c }
        if k == "carved_pumpkin" { return V3(0.9, 0.55, 0.1) }
        if k.hasSuffix("_head") || k.hasSuffix("_skull") { return V3(0.8, 0.8, 0.75) }
        return nil
    }
    // Biped models the overlay fits (zombie layout: legs 0-12, body 12-24, head 24-32).
    static func fits(_ k: MobKind) -> Bool {
        [.zombie, .husk, .drowned, .skeleton, .stray, .bogged, .zombieVillager, .armorStand].contains(k)
    }
}

extension Mob {
    // Reference: armour chance 0.15 x clamped regional difficulty; tier 0/1 then +1 with 9.5% three times
    // (leather, gold, chain, iron, diamond); boots always, each further piece stops with 25% (10% on hard).
    func rollEquipment(difficulty: Int, regional: Float) {
        guard ArmorLook.fits(kind), kind != .armorStand, difficulty > 0 else { return }
        guard Rand.float(in: 0..<1) < 0.15 * regional else { return }
        var tier = Rand.int(in: 0...1)
        for _ in 0..<3 where Rand.float(in: 0..<1) < 0.095 { tier += 1 }
        let mat = ["leather", "golden", "chainmail", "iron", "diamond"][tier]
        let stop: Float = difficulty == 3 ? 0.1 : 0.25
        var eq = [ItemStack](repeating: .empty, count: 5)
        for slot in [3, 2, 1, 0] {
            if slot != 3 && Rand.float(in: 0..<1) < stop { break }
            let piece = ["helmet", "chestplate", "leggings", "boots"][slot]
            let n = "\(mat)_\(piece)"
            if Items.has(n) {
                let d = Items.def(Items.id(n)).durability
                eq[slot] = ItemStack(Items.id(n), 1)
                if d > 1 { eq[slot].damage = Rand.int(in: 0..<max(1, d - 1)) }
            }
        }
        // Zombies: 1% (5% hard) carry an iron sword (1/3) or shovel.
        if [.zombie, .husk, .drowned].contains(kind) && Rand.float(in: 0..<1) < (difficulty == 3 ? 0.05 : 0.01) {
            let n = Rand.int(in: 0..<3) == 0 ? "iron_sword" : "iron_shovel"
            if Items.has(n) { eq[4] = ItemStack(Items.id(n), 1) }
        }
        if eq.contains(where: { !$0.isEmpty }) { equip = eq }
    }

    var armorPoints: (Int, Float) {
        var (pts, tough) = steelholdArmor
        guard let e = equip else { return (pts, tough) }
        for s in e.prefix(4) where !s.isEmpty { pts += s.def.armor; tough += s.def.toughness }
        return (pts, tough)
    }

    // Reference armour formula applied to a hit on a mob.
    func armorReduced(_ damage: Int) -> Int {
        let (pts, t) = armorPoints
        guard pts > 0 else { return damage }
        let d = Float(damage), a = Float(pts)
        let f = min(20, max(a / 5, a - d / (2 + t / 4))) / 25
        let r = d * (1 - f)
        let whole = floor(r)
        return Int(whole) + (Rand.float(in: 0..<1) < r - whole ? 1 : 0)
    }

    // A held weapon adds its attack damage to melee hits.
    var weaponBonus: Int {
        guard let e = equip, e.count > 4, !e[4].isEmpty else { return 0 }
        return max(0, Int(e[4].def.attack) - 1)
    }
}

// Armour overlay boxes, slightly inflated around a zombie-layout biped.
func equipmentParts(_ m: Mob) -> [Part] {
    guard let e = m.equip, ArmorLook.fits(m.kind) else { return [] }
    let swing = m.kind == .armorStand ? 0 : sinf(m.walkPhase) * 0.7 * m.walkAmount
    let zombieLike = m.kind == .zombie || m.kind == .husk || m.kind == .drowned || m.kind == .zombieVillager
    let armFwd: Float = zombieLike ? -1.45 : 0
    let armAngle = armFwd + (armFwd == 0 ? swing : 0)
    let limb: Float = [.skeleton, .stray, .bogged, .armorStand].contains(m.kind) ? 2 : 4
    var p: [Part] = []
    func dyed(_ s: ItemStack, _ c: V3) -> V3 {
        guard Items.key(s.item).hasPrefix("leather_"), let v = s.pat?.first else { return c }
        return V3(Float((v >> 16) & 255) / 255, Float((v >> 8) & 255) / 255, Float(v & 255) / 255)
    }
    if !e[0].isEmpty, let c0 = ArmorLook.color(e[0].item) {
        let c = dyed(e[0], c0)
        let k = Items.key(e[0].item)
        if k == "carved_pumpkin" || k.hasSuffix("_head") || k.hasSuffix("_skull") {
            p.append(box(-4.4, 23.6, -4.4, 8.8, 8.8, 8.8, c))
            if k == "carved_pumpkin" { p.append(box(-3, 27, -4.6, 6, 2, 0.3, V3(0.2, 0.1, 0))) }
        } else {
            p.append(box(-4.6, 28.5, -4.6, 9.2, 4.1, 9.2, c))
            p.append(box(-4.6, 25, -4.6, 0.6, 3.5, 9.2, c))
            p.append(box(4, 25, -4.6, 0.6, 3.5, 9.2, c))
            p.append(box(-4, 25, 4, 8, 3.5, 0.6, c))
        }
    }
    if !e[1].isEmpty, let c1 = ArmorLook.color(e[1].item) {
        let c = dyed(e[1], c1)
        p.append(box(-4.6, 11.6, -2.6, 9.2, 12.8, 5.2, c))
        let px = 4 + limb / 2
        p.append(Part(mn: V3(-4 - limb - 0.6, 16, -limb / 2 - 0.6), mx: V3(-3.9, 24.6, limb / 2 + 0.6), pivot: V3(-px, 22, 0), rotX: armAngle, color: c))
        p.append(Part(mn: V3(3.9, 16, -limb / 2 - 0.6), mx: V3(4 + limb + 0.6, 24.6, limb / 2 + 0.6), pivot: V3(px, 22, 0),
                      rotX: armFwd == 0 ? -armAngle : armAngle, color: c))
    }
    if !e[2].isEmpty, let c2 = ArmorLook.color(e[2].item) {
        let c = dyed(e[2], c2)
        p.append(box(-4.4, 10, -2.4, 8.8, 3, 4.8, c * 0.9))
        p.append(Part(mn: V3(-limb - 0.5, 4, -limb / 2 - 0.5), mx: V3(0, 12, limb / 2 + 0.5), pivot: V3(-limb / 2, 12, 0), rotX: swing, color: c * 0.9))
        p.append(Part(mn: V3(0, 4, -limb / 2 - 0.5), mx: V3(limb + 0.5, 12, limb / 2 + 0.5), pivot: V3(limb / 2, 12, 0), rotX: -swing, color: c * 0.9))
    }
    if !e[3].isEmpty, let c3 = ArmorLook.color(e[3].item) {
        let c = dyed(e[3], c3)
        p.append(Part(mn: V3(-limb - 0.6, -0.1, -limb / 2 - 0.6), mx: V3(0, 4, limb / 2 + 0.6), pivot: V3(-limb / 2, 12, 0), rotX: swing, color: c * 0.8))
        p.append(Part(mn: V3(0, -0.1, -limb / 2 - 0.6), mx: V3(limb + 0.6, 4, limb / 2 + 0.6), pivot: V3(limb / 2, 12, 0), rotX: -swing, color: c * 0.8))
    }
    if e.count > 4 && !e[4].isEmpty {
        // Held tool: a blade / handle sticking out of the right hand.
        let k = Items.key(e[4].item)
        let head = ArmorLook.color(e[4].item) ?? V3(0.8, 0.8, 0.82)
        let handY: Float = 13
        let r = armFwd == 0 ? -armAngle : armAngle
        p.append(Part(mn: V3(4 + limb / 2 - 0.5, handY - 1, -5), mx: V3(4 + limb / 2 + 0.5, handY, 1), pivot: V3(4 + limb / 2, 22, 0), rotX: r, color: V3(0.4, 0.28, 0.15)))
        p.append(Part(mn: V3(4 + limb / 2 - 0.5, handY - 1, k.hasSuffix("_sword") ? -14 : -8), mx: V3(4 + limb / 2 + 0.5, handY, -5),
                      pivot: V3(4 + limb / 2, 22, 0), rotX: r, color: head))
    }
    return p
}

// Armor stand model: stone base plate, wooden sticks (no arms, like the reference default).
func armorStandParts(_ m: Mob) -> [Part] {
    let wood = V3(0.62, 0.48, 0.3), stone = V3(0.62, 0.62, 0.62)
    return [
        box(-6, 0, -6, 12, 1, 12, stone),
        box(-3, 1, -1, 2, 11, 2, wood), box(1, 1, -1, 2, 11, 2, wood),
        box(-4, 12, -1, 8, 2, 2, wood),
        box(-3, 14, -1, 2, 7, 2, wood), box(1, 14, -1, 2, 7, 2, wood),
        box(-6, 21, -1.5, 12, 3, 3, wood),
        box(-1, 24, -1, 2, 7, 2, wood),
    ]
}

extension Game {
    func placeArmorStand(_ t: (hit: IVec3, normal: IVec3)) -> Bool {
        guard Items.key(held.item) == "armor_stand", t.normal.y == 1 else { return false }
        let at = t.hit + t.normal
        guard !Blocks.collide[Int(world.block(at.x, at.y, at.z))], !Blocks.collide[Int(world.block(at.x, at.y + 1, at.z))] else { return false }
        let m = Mob(.armorStand, at: V3(Float(at.x) + 0.5, Float(at.y), Float(at.z) + 0.5))
        // Faces the player, snapped to 45 degrees.
        let step = Float.pi / 4
        m.yaw = ((player.yaw + .pi) / step).rounded() * step
        m.persistent = true
        mobs.mobs.append(m)
        if survival { consumeHeld() }
        sfx(.place(.wood), 0.8, at: m.pos)
        swing = 1
        return true
    }

    // Right-click an armor stand: put on / swap the held armour or item, or take one off (by the height clicked).
    func useArmorStand(_ m: Mob) -> Bool {
        guard m.kind == .armorStand else { return false }
        var eq = m.equip ?? [ItemStack](repeating: .empty, count: 5)
        let h = held
        var slot: Int
        if !h.isEmpty {
            if let s = h.def.armorSlot { slot = s.rawValue }
            else if h.def.name == "carved_pumpkin" || h.def.name.hasSuffix("_head") || h.def.name.hasSuffix("_skull") { slot = 0 }
            else { slot = 4 }
        } else {
            let t = m.rayHit(player.eye, player.look, maxDist: 5) ?? 0
            let y = player.eye.y + player.look.y * t - m.pos.y
            slot = y > 1.6 ? 0 : (y > 1.2 ? 1 : (y > 0.6 ? 2 : 3))
            if eq[slot].isEmpty, let any = [4, 0, 1, 2, 3].first(where: { !eq[$0].isEmpty }) { slot = any }
            if eq[slot].isEmpty { return false }
        }
        let old = eq[slot]
        var one = h
        if !one.isEmpty { one.count = 1 }
        eq[slot] = one
        if !h.isEmpty {
            if survival || h.count > 1 { var rest = h; rest.count -= 1; inventory.held = rest.count > 0 ? rest : .empty }
            if !old.isEmpty {
                if inventory.held.isEmpty { inventory.held = old } else { let r = inventory.add(old); if !r.isEmpty { dropItem(r) } }
            }
        } else {
            inventory.held = old
        }
        m.equip = eq.contains(where: { !$0.isEmpty }) ? eq : nil
        sfx(.armorEquip(2), 0.7, at: m.pos)
        return true
    }
}

extension Mob {
    func updateArmorStand(_ dt: Float, _ g: Game) {
        vel.x *= 0.5; vel.z *= 0.5
        vel.y -= 28 * dt
        let hit = g.world.moveBody(&pos, halfW: halfW, height: height, vel * dt, step: 0, onGround: onGround)
        if hit.y { onGround = vel.y < 0; vel.y = 0 }
        if hit.x { vel.x = 0 }
        if hit.z { vel.z = 0 }
    }
}

extension Game {
    // Reference clamped regional difficulty (0...1): grows with world age and time spent in the area
    // (world time stands in for chunk inhabited time); halved on easy, always 0 early on normal.
    var regionalDifficulty: Float {
        let r = effectiveDifficulty
        return r < 2 ? 0 : (r > 4 ? 1 : (r - 2) / 2)
    }

    // Unclamped regional difficulty (0 peaceful ... 6.75 on hard): patrol sizes, spawn buffs.
    var effectiveDifficulty: Float {
        let ticks = Float(time * 20)
        var f: Float = 0.75
        let h = max(0, min(1, (ticks - 72000) / 1_440_000)) * 0.25
        f += h
        var i = max(0, min(1, ticks / 3_600_000)) * (difficulty == 3 ? 1 : 0.75)
        i += min(0.125, h)
        if difficulty == 1 { i *= 0.5 }
        f += i
        return Float(difficulty) * f
    }
}
