import Foundation
import simd

// Boats and chest boats (and the bamboo raft): placed on water or land, float at the surface,
// W/S paddle, A/D turn; fast on ice (packed ice ~40 b/s, blue ice ~70 b/s like the reference game).
// Chest boats carry a 27-slot inventory (also used by chested donkeys, mules and llamas).
enum Boats {
    static let woods: [(String, String, UInt32)] = [
        ("oak", "Oak", 0xA2824E), ("spruce", "Spruce", 0x735531), ("birch", "Birch", 0xC5B57A), ("jungle", "Jungle", 0xA07351),
        ("acacia", "Acacia", 0xAD5D32), ("dark_oak", "Dark Oak", 0x4F3218), ("mangrove", "Mangrove", 0x773631),
        ("cherry", "Cherry", 0xE2B2AC), ("bamboo", "Bamboo", 0xC8B25A),
    ]
    static func itemKey(_ variant: Int, chest: Bool) -> String {
        let w = woods[max(0, min(woods.count - 1, variant))].0
        if w == "bamboo" { return chest ? "bamboo_chest_raft" : "bamboo_raft" }
        return chest ? "\(w)_chest_boat" : "\(w)_boat"
    }
    static func parse(_ key: String) -> (variant: Int, chest: Bool)? {
        for i in woods.indices {
            if key == itemKey(i, chest: false) { return (i, false) }
            if key == itemKey(i, chest: true) { return (i, true) }
        }
        return nil
    }
    static func color(_ variant: Int) -> V3 {
        let c = woods[max(0, min(woods.count - 1, variant))].2
        return V3(Float((c >> 16) & 255) / 255, Float((c >> 8) & 255) / 255, Float(c & 255) / 255)
    }
    static func slipperiness(_ b: BlockID) -> Float {
        switch Blocks.key(Blocks.groupBase[Int(b)]) {
        case "ice", "packed_ice", "frosted_ice": return 0.98
        case "blue_ice": return 0.989
        default: return 0.6
        }
    }
}

extension Game {
    // Right-click with a boat: put it on the water surface (or the block) being looked at.
    func placeBoat() -> Bool {
        guard case let (variant, chest)? = Boats.parse(Items.key(held.item)) else { return false }
        let dir = player.look
        var t: Float = 0
        var spot: V3?
        while t < 5 {
            let q = player.eye + dir * t
            let c = IVec3(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z)))
            let b = world.block(c.x, c.y, c.z)
            if Blocks.fluidKind[Int(b)] == 1 { spot = V3(q.x, Float(c.y) + 0.6, q.z); break }
            if Blocks.targetable(b) && !Blocks.replaceable[Int(b)] {
                if let tg = target, tg.normal.y == 1 { spot = V3(q.x, Float(tg.hit.y + 1), q.z) }
                break
            }
            t += 0.05
        }
        guard let at = spot else { return false }
        let boat = Mob(.boat, at: at)
        boat.variant = variant
        boat.chested = chest
        if chest { boat.cargo = ItemContainer(27) }
        boat.yaw = player.yaw
        mobs.mobs.append(boat)
        if survival { consumeHeld() }
        sfx(.place(.wood), 0.7, at: at)
        swing = 1
        return true
    }

    // Right-click a boat: sit in it (sneak-click a chest boat opens its chest).
    func useBoat(_ m: Mob) -> Bool {
        guard m.kind == .boat else { return false }
        if m.chested && (input.shift || riding === m) {
            if m.cargo == nil { m.cargo = ItemContainer(27) }
            openMenu(ChestMenu(game: self, container: m.cargo!, title: "Chest Boat"))
            return true
        }
        if riding != nil { return false }
        riding = m
        player.pos = m.pos + V3(0, 0.1, 0)
        sfx(.place(.wood), 0.4, at: m.pos)
        return true
    }

    // Chested donkeys, mules and llamas: sneak-right-click opens their packs.
    func openPack(_ m: Mob) -> Bool {
        guard m.chested, [MobKind.donkey, .mule, .llama, .traderLlama].contains(m.kind), input.shift || riding === m else { return false }
        let slots = m.kind == .llama || m.kind == .traderLlama ? 3 * max(1, min(5, (m.variant >> 4) & 7)) : 15
        if m.cargo == nil || m.cargo!.count != slots {
            let c = ItemContainer(slots)
            if let old = m.cargo { for i in 0..<min(old.count, slots) { c[i] = old[i] } }
            m.cargo = c
        }
        openMenu(PackMenu(game: self, container: m.cargo!, title: m.customName ?? m.kind.name))
        return true
    }
}

// A pack animal's inventory: 5 columns x 3 rows (llamas 3-15 slots by strength).
final class PackMenu: Menu {
    init(game: Game, container: ItemContainer, title: String) {
        super.init(title, game: game)
        let cols = max(1, container.count / 3)
        for r in 0..<3 { for c in 0..<cols { slots.append(MenuSlot(80 + c * 18, 18 + r * 18, container, c + r * cols)) } }
        addPlayerInventory()
    }
}

extension Mob {
    func updateBoat(_ dt: Float, _ g: Game) {
        let w = g.world
        let ridden = g.riding === self
        // Water surface under / around the boat.
        let bx = Int(floor(pos.x)), bz = Int(floor(pos.z))
        var surface: Float?
        var y = Int(floor(pos.y + 0.8))
        let start = y
        while y > start - 3 {
            let b = w.block(bx, y, bz)
            if Blocks.fluidKind[Int(b)] == 1 {
                var top = y
                while Blocks.fluidKind[Int(w.block(bx, top + 1, bz))] == 1 && top < y + 8 { top += 1 }
                surface = Float(top) + 0.9
                break
            }
            y -= 1
        }
        let below = w.block(bx, Int(floor(pos.y - 0.05)), bz)
        let inLava = Blocks.fluidKind[Int(w.block(bx, Int(floor(pos.y + 0.2)), bz))] == 2
        if inLava { health = 0; return }
        // Friction per tick from what is under the boat (reference: water 0.9, land = block slipperiness).
        var friction: Float = 0.05
        if let s = surface {
            let target = s - 0.35
            let under = target - pos.y
            if under > 0.6 {
                // Deep under water: bob up (reference: boats pop up; a submerged ridden boat ejects the rider).
                vel.y = min(vel.y + 20 * dt, 3)
                if ridden && under > 1.2 { g.dismount() }
            } else {
                vel.y += (under * 30 - vel.y * 4) * dt
            }
            friction = 0.9
        } else {
            vel.y -= 28 * dt
            if onGround { friction = Boats.slipperiness(below) * 0.9 }
        }
        // Paddling: reference acceleration 0.04 b/tick forward, 0.005 backward, turn 1 deg/tick with 0.9 decay.
        if ridden {
            let inp = g.rideInput
            if abs(inp.strafe) > 0.2 { spin += (inp.strafe > 0 ? -1 : 1) * 20 * dt }
            var push: Float = 0
            if inp.forward > 0.2 { push += 0.04 }
            if inp.forward < -0.2 { push -= 0.005 }
            if abs(inp.strafe) > 0.2 && inp.forward <= 0.2 { push += 0.005 }
            vel += forward * push * 20 * 20 * dt
            walkPhase += (abs(inp.forward) + abs(inp.strafe)) * dt * 6
        }
        spin *= powf(0.9, dt * 20)
        yaw += spin * .pi / 180 * dt * 20
        // Per-tick friction scaled to the frame.
        let f = powf(friction, dt * 20)
        vel.x *= f
        vel.z *= f
        let hit = w.moveBody(&pos, halfW: halfW, height: height, vel * dt, step: 0, onGround: onGround)
        var landed = false
        if hit.y { if vel.y < 0 { landed = true }; vel.y = 0 }
        // Ramming a wall at speed breaks the boat (reference: falls > 3 blocks onto land also break it).
        if (hit.x || hit.z) && simd_length(V2(vel.x, vel.z)) > 12 && surface == nil { health = 0 }
        if hit.x { vel.x = 0 }
        if hit.z { vel.z = 0 }
        onGround = landed || (vel.y <= 0 && collides(pos - V3(0, 0.06, 0), w))
        if ridden {
            g.player.pos = pos + V3(0, 0.1, 0)
            g.player.vel = .zero
            g.player.airPeak = g.player.pos.y
        }
    }
}

// Boat model: flat bottom, four sides, two paddles (rowing while ridden). Faces -Z.
func boatParts(_ m: Mob) -> [Part] {
    let c = Boats.color(m.variant)
    let dark = c * 0.8
    var p: [Part] = [
        box(-8, 0, -14, 16, 3, 28, dark),
        box(-9, 3, -14, 1, 6, 28, c), box(8, 3, -14, 1, 6, 28, c),
        box(-8, 3, -15, 16, 6, 1, c), box(-8, 3, 14, 16, 6, 1, c),
    ]
    let row = sinf(m.walkPhase) * 0.6
    for s: Float in [-1, 1] {
        p.append(Part(mn: V3(s * 10 - 0.5, 6, -1), mx: V3(s * 10 + 0.5, 7, 14), pivot: V3(s * 10, 6.5, 2), rotX: row, color: dark))
    }
    if m.chested {
        let wood = V3(0.62, 0.45, 0.22)
        p.append(box(-6, 3, 3, 12, 10, 10, wood))
        p.append(box(-1, 8, 2.6, 2, 3, 0.4, V3(0.8, 0.8, 0.8)))
    }
    return p
}
