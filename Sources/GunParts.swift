import Foundation
import simd

// P372 (Oct 18 08:15-08:20, the Capital roof guns: "how do I get in the gun", "I should be able to control that gun",
// "those guns... should be made of components... something I can physically break"). Every emplacement gun (the
// battleship turrets, the casemate and monitor, Greywall's tower guns, the small AA, pom-pom and dual-purpose mounts and
// the flak gun) is built of parts that each take their own damage:
//   barrels   left and right: a broken one is gone from the model and that side no longer fires
//   breech    behind the guns: broken, the gun can't fire at all
//   shield    the gunhouse face and flanks (the open mounts' shields): broken, the plates are gone and the crew exposed
//   mount     the ring and base: broken, the gun no longer turns
// A blow lands on the part facing whoever struck it (in front and high: the barrels; in front or the flanks: the
// shield; low: the mount; from behind: the breech), at the blow's full weight (armour stops a blade on the whole gun,
// not on a barrel you hack at). A part that breaks comes away in a shower of plating, with a clang.
// Handles: two yellow-gripped spade handles on a post behind each gun (drawn in deckGunParts). On the headset, walking
// up and gripping them takes the gun (Turrets.mount); aim with the hand, fire with the trigger, let go to step off.
enum GunParts {
    static let leftBarrel = 0, rightBarrel = 1, breech = 2, shield = 3, mount = 4
    static let names = ["left barrel", "right barrel", "breech", "shield", "mount"]
    static let share: [Float] = [0.15, 0.15, 0.2, 0.2, 0.25]      // each part's strength, of the gun's whole health
    static var broke = 0                                         // (checks)

    static func strength(_ m: Mob, _ i: Int) -> Float { Float(max(1, m.spec.health)) * share[i] }
    static func broken(_ m: Mob, _ i: Int) -> Bool {
        guard m.kind == .deckGun, let d = m.gunParts else { return false }
        return d[i] >= strength(m, i)
    }
    static func brokenMask(_ m: Mob) -> Int {
        var k = 0
        for i in 0..<5 where broken(m, i) { k |= 1 << i }
        return k
    }

    // The side's barrel and the breech are whole (flak: one barrel, the left).
    static func canFire(_ m: Mob, _ sx: Float) -> Bool {
        !broken(m, breech) && !broken(m, sx > 0 ? rightBarrel : leftBarrel)
    }
    static func canFireAny(_ m: Mob) -> Bool {
        !broken(m, breech) && (!broken(m, leftBarrel) || (!HeavyTurret.isFlak(m) && !broken(m, rightBarrel)))
    }
    static func canTurn(_ m: Mob) -> Bool { !broken(m, mount) }

    // P465 (Oct 25 19:51, "this naval gun should have fallen because it destroyed the tower under it"): a gun on the
    // ground or a roof (not a ship's deck) stands while something solid is under its ring, in the two layers below it.
    static func supported(_ m: Mob, _ w: World) -> Bool {
        guard m.deck == nil else { return true }
        let r = max(1, Int((2 * HeavyTurret.scale(m)).rounded()))
        let x0 = Int(floor(m.pos.x)), y0 = Int(floor(m.pos.y + 0.01)), z0 = Int(floor(m.pos.z))
        for (dx, dz) in [(-r, -r), (r, -r), (-r, r), (r, r)] where w.chunkAt(x0 + dx, z0 + dz) == nil { return true }   // (not loaded: unknown)
        for dy in 1...2 { for dz in -r...r { for dx in -r...r where w.solidAt(x0 + dx, y0 - dy, z0 + dz) { return true } } }
        return false
    }
    // ... and without it the gun falls to whatever is under it and is wrecked there.
    static var falls = 0                                         // (checks)
    static func fall(_ m: Mob, _ g: Game) {
        falls += 1
        let w = g.world
        let x = Int(floor(m.pos.x)), z = Int(floor(m.pos.z))
        var y = Int(floor(m.pos.y + 0.01)) - 1
        while y > 1 && !w.solidAt(x, y, z) && Int(floor(m.pos.y)) - y < 60 { y -= 1 }
        m.pos.y = Float(y + 1)
        Mob.plateHit = true
        m.hit(from: m.pos + V3(0, 3, 0), damage: m.health + 1000, knockback: 0)
        Mob.plateHit = false
    }

    // Which part a blow from `src` lands on.
    static func part(_ m: Mob, from src: V3) -> Int {
        let k = HeavyTurret.scale(m)
        let d = src - m.pos
        let side = V3(cosf(m.yaw), 0, -sinf(m.yaw)), fwd = V3(-sinf(m.yaw), 0, -cosf(m.yaw))
        let lx = simd_dot(d, side), lz = simd_dot(d, fwd), ly = d.y
        let r: Float = 7 * k
        if ly < max(0.4, 0.7 * k) && abs(lz) < r * 1.2 { return mount }
        if lz > 0.3 * r {
            if ly > HeavyTurret.trunnionY * k * 0.5 && abs(lx) < HeavyTurret.spacing * k * 3 { return lx > 0 ? rightBarrel : leftBarrel }
            return shield
        }
        if lz < -0.3 * r { return breech }
        return shield
    }

    // From Mob.hit, before armour: the part facing the blow takes its full weight.
    static func hit(_ m: Mob, from src: V3, damage: Int) {
        guard m.kind == .deckGun, damage > 0, m.health > 0 else { return }
        var d = m.gunParts ?? [0, 0, 0, 0, 0]
        let i = part(m, from: src)
        d[i] += Float(damage)
        m.gunParts = d
    }

    // Once a frame from the gun's update: a part that has just broken comes away.
    static func update(_ m: Mob, _ g: Game) {
        let mask = brokenMask(m)
        guard mask != m.gunPartsShown else { return }
        let new = mask & ~m.gunPartsShown
        m.gunPartsShown = mask
        guard new != 0 else { return }
        let k = HeavyTurret.scale(m)
        let side = V3(cosf(m.yaw), 0, -sinf(m.yaw)), fwd = V3(-sinf(m.yaw), 0, -cosf(m.yaw))
        let plate = Blocks.has("steel_plating") ? Blocks.id("steel_plating") : STONE
        for i in 0..<5 where new & (1 << i) != 0 {
            var at = m.pos + V3(0, HeavyTurret.trunnionY * k, 0)
            switch i {
            case leftBarrel: at += fwd * 8 * k - side * HeavyTurret.spacing * k
            case rightBarrel: at += fwd * 8 * k + side * HeavyTurret.spacing * k
            case breech: at -= fwd * 3 * k
            case shield: at += fwd * 6 * k
            default: at = m.pos + V3(0, 0.5, 0)
            }
            for _ in 0..<3 { g.particles.blockBreak(plate, at: IVec3(Int(floor(at.x)), Int(floor(at.y)), Int(floor(at.z)))) }
            for _ in 0..<4 { g.particles.smoke(at: at, dark: true) }
            g.sfx(.breakBlock(.stone), 1.2, at: at)
            g.sfx(.anvilLand, 0.8, at: at)
            if Items.has("steel_plating") {
                g.drops.spawn(ItemStack(Items.id("steel_plating"), 1), at: at, vel: side * Rand.float(in: -3...3) + V3(0, 4, 0), delay: 1)
            }
            broke += 1
        }
    }

    // Which drawn parts belong to a broken component (the part list as deckGunParts makes it, before scaling: `k` is
    // that gun's scale so the small guns' already scaled lists read the same).
    static func keep(_ p: Part, _ m: Mob, mask: Int, tz: Float, ty: Float, k: Float) -> Bool {
        guard mask != 0 else { return true }
        let tz = tz * k
        let moving = p.pivot != .zero
        let cx = (p.mn.x + p.mx.x) / 2
        if moving {
            // Barrels and mantlets ride the trunnion: the breech is the part nearest it, the rest the barrel.
            let rear = p.mx.z > tz - 6 * k
            if rear && mask & (1 << breech) != 0 { return false }
            if !rear && mask & (1 << (cx > 0 ? rightBarrel : leftBarrel)) != 0 { return false }
            return true
        }
        if p.mx.y <= 10 * k { return mask & (1 << mount) == 0 }
        // The shield: what stands ahead of the trunnions (the face plates, a mount's shield).
        if p.mn.z < tz + 8 * k && p.mx.z < tz + 60 * k { return mask & (1 << shield) == 0 }
        return true
    }

    // The handles behind the gun (final model pixels): a post, a cross bar and two yellow spade grips, a hand's
    // height off the deck, at the back of whatever the gun is.
    static let gripColor = V3(0.95, 0.78, 0.12)
    static func handles(_ p: [Part]) -> [Part] {
        let rear = (p.map { $0.mx.z }.max() ?? 0) + 3
        let dark = V3(0.14, 0.15, 0.16)
        return [box(-2, -2, rear + 4, 4, 20, 4, dark), box(-10, 15, rear + 4, 20, 3, 3, dark),
                box(-12, 12, rear + 3, 3, 10, 4, gripColor), box(9, 12, rear + 3, 3, 10, 4, gripColor)]
    }
    // Where the grips are in the world (between them).
    static func handlePoint(_ m: Mob) -> V3 {
        let rear = (deckGunParts(m).filter { $0.color != gripColor }.map { $0.mx.z }.max() ?? 0) + 8
        let back = V3(sinf(m.yaw), 0, cosf(m.yaw))
        return m.pos + V3(0, 17 / 16, 0) + back * (rear / 16)
    }
}

// P372's check (questcheck --gunparts-only): a small AA mount and a battleship turret on a floor high over the ground.
// Blows from in front at barrel height break the right barrel (gone from the model, that side silent, the other still
// fires); blows low down break the mount (it no longer turns); both guns carry their handles, and a gun taken by its
// handles turns after the hand.
enum GunPartsCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let pos0 = g.player.pos, mobs0 = g.mobs.mobs, surv0 = g.survival
        defer { if Turrets.shared.manned != nil { Turrets.shared.leave(g) }; g.mobs.mobs = mobs0; g.player.pos = pos0; g.survival = surv0 }
        let fx = Int(floor(pos0.x)), fz = Int(floor(pos0.z)), py = min(CH - 30, w.topY(fx, fz) + 24)
        _ = w.loadSync(center: V3(Float(fx), Float(py), Float(fz)), radius: 3)
        g.survival = false
        func gun(_ variant: Int, _ dx: Float) -> Mob {
            let m = Mob(.deckGun, at: V3(Float(fx) + dx, Float(py), Float(fz) + 0.5))
            m.variant = variant; m.persistent = true; m.yaw = 0
            return m
        }
        for (name, variant) in [("AA mount", HeavyTurret.aaTwin), ("battleship turret", 1)] {
            let m = gun(variant, 0)
            g.mobs.mobs = [m]; g.mobs.rebuildIndex()
            let k = HeavyTurret.scale(m)
            let fwd = V3(-sinf(m.yaw), 0, -cosf(m.yaw)), side = V3(cosf(m.yaw), 0, -sinf(m.yaw))
            let n0 = deckGunParts(m).count
            let grips = deckGunParts(m).filter { $0.color == GunParts.gripColor }.count
            let front = m.pos + fwd * (9 * k + 1) + side * (HeavyTurret.spacing * k) + V3(0, HeavyTurret.trunnionY * k, 0)
            var blows = 0
            while !GunParts.broken(m, GunParts.rightBarrel) && blows < 200 { m.hit(from: front, damage: 7); m.health = m.spec.health; blows += 1 }
            GunParts.update(m, g)
            let n1 = deckGunParts(m).count
            check(grips == 2 && GunParts.broken(m, GunParts.rightBarrel) && !GunParts.canFire(m, 1) && GunParts.canFire(m, -1) && n1 < n0
                  && !GunParts.broken(m, GunParts.leftBarrel) && GunParts.broke >= 1,
                  "P372 \(name): two grips on its handles; \(blows) sword blows from the front break the right barrel (\(n0) -> \(n1) parts), that side can't fire, the left still can")
            let low = m.pos + fwd * (3 * k + 1) + V3(0, 0.2, 0)
            blows = 0
            while !GunParts.broken(m, GunParts.mount) && blows < 200 { m.hit(from: low, damage: 7); m.health = m.spec.health; blows += 1 }
            check(GunParts.broken(m, GunParts.mount) && !GunParts.canTurn(m), "P372 \(name): \(blows) blows low down break the mount: it can't turn")
        }
        // Taken by its handles: the hand turns it.
        let m = gun(HeavyTurret.aaTwin, 0)
        g.mobs.mobs = [m]; g.mobs.rebuildIndex()
        let hp = GunParts.handlePoint(m)
        Turrets.shared.mount(g, m); Turrets.shared.byGrip = true
        Turrets.shared.handAim = V3(-1, 0.2, 0)              // to the west and a little up
        for _ in 0..<40 { _ = Turrets.shared.tick(g, PadSnapshot(), PadSnapshot(), sneak: false, dt: 0.05) }
        let turned = m.yaw
        Turrets.shared.leave(g)
        check(simd_length(V2(hp.x - m.pos.x, hp.z - m.pos.z)) > 0.5 && turned > 0.5 && Turrets.shared.manned == nil,
              String(format: "P372 handles: %.1f blocks behind the mount; held by them the gun turned %.2f rad after the hand; letting go leaves it", simd_length(V2(hp.x - m.pos.x, hp.z - m.pos.z)), turned))
    }
}
