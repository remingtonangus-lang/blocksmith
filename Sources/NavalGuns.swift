import Foundation
import simd

// Naval guns, Oct 12 noon voice notes:
// - P102 ("I hit another naval gun with a naval gun and nothing happened"): a heavy shell (a deck gun's, manned or
//   crewed) hurts the deck guns it lands near as plate on plate, past their armour: a direct hit from a manned gun
//   takes about 40 % of a turret, a crew's shell about a quarter. A hurt gun shows it: smoke from the gunhouse under
//   two thirds, fire under one third, the plates blackened and one barrel drooping (deckGunParts). Destroyed, it
//   leaves a wreck in blocks where it stood (a burnt heap of plate with its barrels fallen across it): no longer a gun.
// - P103 ("base walls take far too little damage from a naval gun shell"): a manned shell blows a breach as well as
//   its blast: a round hole of radius 5.5 through anything breakable (Capital stone included), carved a few hundred
//   blocks a frame (CraterJob) so the headset keeps its frame time.
enum NavalGuns {
    static let directShare: Float = 160               // plate damage at the burst's centre (a turret has 400)
    static let reach: Float = 7                       // ... falling off to nothing this far from it (the gunhouse is 14 wide)
    static let breachRadius: Float = 5.5
    static let breachCap = 650

    // A heavy shell burst at `at` (Armory.detonate, after the blast itself).
    static func heavyBurst(_ s: Slug, at: V3, shooter: Mob?, spares: Faction, _ g: Game) {
        guard s.kind == .shell, s.breaks else { return }
        let manned = s.breach.isFinite
        for m in g.mobs.mobs where m.kind == .deckGun && m.health > 0 && m !== shooter {
            if spares != .none && m.factionValue == spares { continue }
            let centre = m.pos + V3(0, HeavyTurret.trunnionY, 0)
            let d = simd_length(centre - at)
            guard d < reach else { continue }
            let k = 1 - d / reach
            let dmg = Int((directShare * k * (manned ? 1 : 0.6)).rounded())
            guard dmg > 0 else { continue }
            Mob.plateHit = true
            m.hit(from: at, damage: dmg, knockback: 0)
            Mob.plateHit = false
            if s.fromPlayer { m.killedByPlayer = true; m.provoke(g) }
            for _ in 0..<6 {
                g.particles.add(Particle(pos: at, vel: V3(Rand.float(in: -4...4), Rand.float(in: 1...6), Rand.float(in: -4...4)),
                                         life: 0.5, maxLife: 0.5, layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1, size: 0.08, gravity: 12,
                                         color: V3(2.4, 1.6, 0.6), collide: false, glow: true))
            }
        }
        if manned {
            g.arms.breaches.append(CraterJob(at: at, radius: breachRadius, cap: breachCap, game: g, quiet: true, depth: Int(breachRadius)))
        }
    }

    // Carves the open breaches a slice a frame.
    static func stepBreaches(_ g: Game) {
        guard !g.arms.breaches.isEmpty else { return }
        for j in g.arms.breaches { j.step(g, blocks: 150) }
        g.arms.breaches.removeAll { $0.done }
    }

    // Damage state 0 (whole), 1 (smoking: under 2/3), 2 (burning: under 1/3).
    static func state(_ m: Mob) -> Int {
        let f = Float(m.health) / Float(max(1, m.spec.health))
        return f < 1.0 / 3 ? 2 : (f < 2.0 / 3 ? 1 : 0)
    }

    // H13: gunhouse plates knocked off so far (one a tenth of its health lost).
    static func platesLost(_ m: Mob) -> Int {
        guard m.health > 0 else { return 0 }
        return max(0, min(10, Int((1 - Float(m.health) / Float(max(1, m.spec.health))) * 10)))
    }

    // Smoke and fire from a hurt gunhouse (once a frame from its update, manned or not).
    static func hurtEffects(_ m: Mob, _ dt: Float, _ g: Game) {
        // H13: each plate knocked off goes as debris, now and then a piece of plating worth picking up.
        let lost = platesLost(m)
        if lost > m.platesShed {
            let side = V3(cosf(m.yaw), 0, -sinf(m.yaw)), fwd = V3(-sinf(m.yaw), 0, -cosf(m.yaw))
            let k = HeavyTurret.scale(m)
            for _ in m.platesShed..<lost {
                let at = m.pos + V3(0, 3 * k, 0) + side * Rand.float(in: -5...5) * k + fwd * Rand.float(in: -4...5) * k
                let plate = Blocks.has("steel_plating") ? Blocks.id("steel_plating") : STONE
                g.particles.blockBreak(plate, at: IVec3(Int(floor(at.x)), Int(floor(at.y)), Int(floor(at.z))))
                g.sfx(.breakBlock(.stone), 0.9, at: at)
                if Rand.float(in: 0..<1) < 0.4 && Items.has("steel_plating") {
                    g.drops.spawn(ItemStack(Items.id("steel_plating"), 1), at: at, vel: side * Rand.float(in: -3...3) + V3(0, 4, 0), delay: 1)
                }
            }
        }
        m.platesShed = lost
        let st = state(m)
        guard st > 0, Rand.float(in: 0..<1) < dt * (st == 2 ? 14 : 5) else { return }
        let side = V3(cosf(m.yaw), 0, -sinf(m.yaw)), fwd = V3(-sinf(m.yaw), 0, -cosf(m.yaw))
        let at = m.pos + V3(0, 5.6, 0) + side * Rand.float(in: -5...5) + fwd * Rand.float(in: -4...5)
        g.particles.smoke(at: at, dark: true)
        if st == 2 { g.particles.flame(at: at) }
    }

    // The gun is destroyed: a wreck in blocks where it stood (not on a ship's deck: those just go up).
    static func wreck(_ m: Mob, _ g: Game) {
        guard m.deck == nil else { return }
        let w = g.world
        func b(_ n: String, _ f: BlockID) -> BlockID { Blocks.has(n) ? Blocks.id(n) : f }
        let plate = b("steel_plating", STONE), burnt = b("blackstone", STONE), coal = b("coal_block", STONE)
        let grate = b("steel_grating", plate), barrel = b("iron_block", plate), fire = b("fire", AIR)
        let ox = Int(floor(m.pos.x)), oy = Int(floor(m.pos.y)), oz = Int(floor(m.pos.z))
        let side = V2(cosf(m.yaw), -sinf(m.yaw)), fwd = V2(-sinf(m.yaw), -cosf(m.yaw))
        let salt = UInt32(truncatingIfNeeded: ox &* 31 &+ oz)
        func put(_ x: Int, _ y: Int, _ z: Int, _ id: BlockID) {
            let old = w.block(x, y, z)
            guard old == AIR || Blocks.replaceable[Int(old)] else { return }
            w.setBlockAsync(x, y, z, id)
        }
        // The collapsed gunhouse: a heap 11 x 13, highest in the middle, ragged at the edges.
        for lz in -6...7 { for lx in -5...5 {
            let rr = Float(lx * lx) / 30 + Float((lz - 1) * (lz - 1)) / 42
            guard rr < 1 else { continue }
            let p = V2(Float(ox) + 0.5, Float(oz) + 0.5) + side * Float(lx) + fwd * Float(-lz)
            let x = Int(floor(p.x)), z = Int(floor(p.y))
            let r = hashf(x, oy, z, salt)
            let h = Int((1 - rr) * 3.2 + r * 1.2)
            guard h > 0 else { continue }
            for dy in 0..<h {
                let pick = hashf(x, oy + dy, z, salt ^ 0x51)
                put(x, oy + dy, z, pick < 0.55 ? plate : (pick < 0.8 ? burnt : (pick < 0.9 ? grate : coal)))
            }
            if r < 0.12 && fire != AIR { put(x, oy + h, z, fire) }
        } }
        // The two barrels fallen forward off the heap, one lying flat, one leaning on it.
        for sx in [-2, 2] {
            for i in 0..<14 {
                let p = V2(Float(ox) + 0.5, Float(oz) + 0.5) + side * Float(sx) + fwd * Float(7 + i)
                let y = sx < 0 ? oy : oy + max(0, 2 - i / 4)
                put(Int(floor(p.x)), y, Int(floor(p.y)), barrel)
            }
        }
        g.onToast?(m.killedByPlayer ? "The turret is wrecked" : "A turret is wrecked")
        for _ in 0..<12 { g.particles.smoke(at: m.pos + V3(Rand.float(in: -5...5), Rand.float(in: 1...5), Rand.float(in: -5...5)), dark: true) }
    }
}
