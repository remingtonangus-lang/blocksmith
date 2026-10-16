import Foundation
import simd

// Jetpack: worn in the chest slot. Its durability is the fuel tank (`damage` = fuel burnt, 1 per tick of thrust, 20 ticks/s);
// at 0 it doesn't break, it just stops. Hold jump while airborne to climb (~6 blocks/s, Player.update); a tap is still a
// plain jump because thrust only starts 0.15 s into the press. Refuel by crafting it with coal/charcoal (+300) or blaze
// powder (+600); only as many fuel items as fit are used.
enum Jetpack {
    static let tank = 1200
    static let fuelValue: [String: Int] = ["coal": 300, "charcoal": 300, "blaze_powder": 600]
    static let suitBurn: Float = 3                // P322 (c): the Hannibal plate's heavy thirst

    // The plate takes one fuel item from the pack (coal or charcoal first, then blaze powder): ticks of thrust, 0 if none.
    static func suitRefill(_ g: Game) -> Int {
        for k in ["coal", "charcoal", "blaze_powder"] where Items.has(k) {
            let id = Items.id(k)
            if g.inventory.main.countOf(id) > 0 && g.inventory.main.remove(id, 1) == 1 { return fuelValue[k] ?? 0 }
        }
        return 0
    }

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

    // Before Player.update: decide whether the jetpack (or the Hannibal plate, P322 c) thrusts this frame and burn fuel.
    // P322 (a, b): jump held thrusts; the move stick pushed forward with it leans the thrust where he looks (the headset's
    // gaze in VR), so he flies forward fast, not only straight up; fuel burns with the thrust: 1x hovering or climbing,
    // up to 2.5x at full forward thrust (3.2x sprinting). The plate burns three times as much, from coal, charcoal or
    // blaze powder in the pack.
    func jetpackTick(_ dt: Float, _ mi: MoveInput) {
        let p = player
        p.jetThrust = false
        var c = inventory.armor[1]
        let jet = Jetpack.isJetpack(c)
        let suit = !jet && PowerSuit.worn(self)
        guard jet || suit else { p.jetHold = 0; p.jetBoost = 0; return }
        p.jetHold = mi.jump ? p.jetHold + dt : 0
        let free = !p.flying && !p.gliding && !p.swimming && !p.inWater && !p.inLava && !p.onGround && riding == nil
        let lean = max(0, mi.forward)
        let boostWant: Float = mi.jump && free ? (lean > 0.2 ? min(1, (lean - 0.2) / 0.6) : 0) : 0
        p.jetBoost += (boostWant - p.jetBoost) * min(1, dt * 4)
        if p.jetBoost < 0.02 { p.jetBoost = 0 }
        let look = simd_normalize(p.moveLook ?? p.look)
        p.jetDir = simd_normalize(look + V3(0, 0.18, 0))
        if jet && Jetpack.fuel(c) > 0 { p.jetEmptyWarned = false }
        guard mi.jump && free && p.jetHold >= 0.15 else { if !mi.jump { p.jetBoost = 0 }; return }
        // (the plate takes its next fuel item from the pack only as it thrusts)
        if suit && survival && p.suitFuel <= 0 { p.suitFuel = Float(Jetpack.suitRefill(self)); if p.suitFuel > 0 { p.jetEmptyWarned = false } }
        let fuel = jet ? Jetpack.fuel(c) : (survival ? Int(p.suitFuel.rounded(.up)) : 1)
        guard fuel > 0 else {
            if !p.jetEmptyWarned { p.jetEmptyWarned = true; sfx(.fizz, 0.7, at: p.pos + V3(0, 1, 0)) }
            p.jetBoost = 0
            return
        }
        p.jetThrust = true
        if survival {
            let rate: Float = (1 + 1.5 * p.jetBoost * (p.sprinting ? 1.48 : 1)) * (suit ? Jetpack.suitBurn : 1)
            if suit { p.suitFuel = max(0, p.suitFuel - dt * 20 * rate) } else {
                p.jetBurn += dt * 20 * rate
                let n = Int(p.jetBurn)
                p.jetBurn -= Float(n)
                if n > 0 { c.damage = min(c.def.durability, c.damage + n); inventory.armor[1] = c }
            }
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
