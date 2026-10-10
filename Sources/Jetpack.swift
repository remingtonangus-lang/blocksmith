import Foundation
import simd

// Jetpack: worn in the chest slot. Its durability is the fuel tank (`damage` = fuel burnt, 1 per tick of thrust, 20 ticks/s);
// at 0 it doesn't break, it just stops. Hold jump while airborne to climb (~6 blocks/s, Player.update); a tap is still a
// plain jump because thrust only starts 0.15 s into the press. Refuel by crafting it with coal/charcoal (+300) or blaze
// powder (+600); only as many fuel items as fit are used.
enum Jetpack {
    static let tank = 1200
    static let fuelValue: [String: Int] = ["coal": 300, "charcoal": 300, "blaze_powder": 600]

    static func isJetpack(_ s: ItemStack) -> Bool { !s.isEmpty && Items.key(s.item) == "jetpack" }
    static func fuel(_ s: ItemStack) -> Int { max(0, s.def.durability - s.damage) }

    // Special craft (Fireworks.craft): jetpack + fuel items -> refuelled jetpack; surplus fuel slots are kept.
    static func refuel(_ g: [ItemStack]) -> (ItemStack, keep: Set<Int>)? {
        let used = g.enumerated().filter { !$0.element.isEmpty }
        let jets = used.filter { isJetpack($0.element) }
        guard jets.count == 1 else { return nil }
        let fuels = used.filter { !isJetpack($0.element) }
        guard !fuels.isEmpty, fuels.allSatisfy({ fuelValue[Items.key($0.element.item)] != nil }) else { return nil }
        var jet = jets[0].element.with(count: 1)
        guard jet.damage > 0 else { return nil }                  // already full
        var keep: Set<Int> = []
        for f in fuels {
            if jet.damage <= 0 { keep.insert(f.offset); continue }
            jet.damage = max(0, jet.damage - fuelValue[Items.key(f.element.item)]!)
        }
        return (jet, keep)
    }

    // Fuel gauge above the armour bars, left of the hotbar, while one is worn.
    static func gauge(_ g: Game, _ L: HudLayout) -> [HudLine] {
        let st = g.inventory.armor[1]
        guard isJetpack(st), !g.hideHUD else { return [] }
        let s = L.s
        let f = Float(fuel(st)) / Float(tank)
        let x = L.hotbarX0 - 30 * s, y = L.hotbarY0 - 10 * s
        let low = f < 0.2
        var out: [HudLine] = []
        out.append(HudLine(text: "", x: x, y: y, scale: s, bg: V4(0, 0, 0, 0.55), box: V2(22 * s, 6 * s)))
        let c = low ? Settings.shared.badColor : V4(1.0, 0.62, 0.22, 1)
        out.append(HudLine(text: "", x: x + s, y: y + s, scale: s, bg: c, box: V2(20 * s * f, 4 * s)))
        if g.player.jetThrust { out.append(HudLine(text: "", x: x + 21 * s, y: y + s, scale: s, bg: V4(1, 0.95, 0.6, 1), box: V2(s, 4 * s))) }
        return out
    }
}

extension Game {
    // Right-click with a held jetpack puts it on (swapping whatever was in the chest slot).
    func jetpackEquip() -> Bool {
        let h = inventory.held
        guard Jetpack.isJetpack(h) else { return false }
        inventory.held = inventory.armor[1]
        inventory.armor[1] = h
        sfx(.armorEquip(2), 0.8)
        return true
    }

    // Before Player.update: decide whether the jetpack thrusts this frame and burn fuel.
    func jetpackTick(_ dt: Float, _ mi: MoveInput) {
        let p = player
        p.jetThrust = false
        var c = inventory.armor[1]
        guard Jetpack.isJetpack(c) else { p.jetHold = 0; return }
        p.jetHold = mi.jump ? p.jetHold + dt : 0
        let free = !p.flying && !p.gliding && !p.swimming && !p.inWater && !p.inLava && !p.onGround && riding == nil
        let fuel = Jetpack.fuel(c)
        if fuel > 0 { p.jetEmptyWarned = false }
        guard mi.jump && free && p.jetHold >= 0.15 else { return }
        guard fuel > 0 else {
            if !p.jetEmptyWarned { p.jetEmptyWarned = true; onToast?("Jetpack out of fuel") }
            return
        }
        p.jetThrust = true
        if survival {
            p.jetBurn += dt * 20
            let n = Int(p.jetBurn)
            p.jetBurn -= Float(n)
            if n > 0 { c.damage = min(c.def.durability, c.damage + n); inventory.armor[1] = c }
        }
        // Flame and smoke from two nozzles low on the back.
        let back = V3(sinf(p.yaw), 0, cosf(p.yaw)), right = V3(cosf(p.yaw), 0, -sinf(p.yaw))
        for side: Float in [-1, 1] {
            let n = p.pos + back * 0.3 + right * (0.12 * side) + V3(0, 0.65, 0)
            particles.add(Particle(pos: n, vel: V3(Rand.float(in: -0.3...0.3), Rand.float(in: -5 ... -3), Rand.float(in: -0.3...0.3)) + V3(p.vel.x, 0, p.vel.z),
                                   life: Rand.float(in: 0.12...0.25), maxLife: 0.25, layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1,
                                   size: Rand.float(in: 0.08...0.14), gravity: 0, color: V3(1, 0.6, 0.18), collide: false, glow: true))
            if Rand.float(in: 0..<1) < 0.35 { particles.smoke(at: n - V3(0, 0.4, 0)) }
        }
    }
}
