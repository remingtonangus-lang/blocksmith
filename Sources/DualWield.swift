import Foundation
import simd

// D8 dual-wield revolvers. A handgun in the hand and another in the offhand slot: the off trigger (the left trigger
// in the headset, the right mouse button or left trigger elsewhere) fires the offhand gun instead of aiming down the
// sights. In the headset it shoots along the left hand's ray; elsewhere a hand's width left of the view. Each gun keeps
// its own cylinder, and the offhand gun cocks itself (a thumb on the hammer: GunActions is for the gun hand). Reloading
// in pairs: the VR hip reach with both hands full takes a speedloader for each gun (VRReload); the timed reload fills
// both. Both guns kick, so dual fire is fast and loose.
enum DualWield {
    static var leftAim: (origin: V3, dir: V3)?        // QuestControls, each frame
    static var cooldown: Float = 0
    static var wasDown = false
    static var shots = 0                               // (tests)

    // The offhand gun's index when both hands hold handguns.
    static func active(_ g: Game) -> Int? {
        guard let gi = g.heldGun, Guns.isHandgun(gi) else { return nil }
        let o = g.inventory.offhand[0]
        guard !o.isEmpty, let oi = Guns.index(o.item), Guns.isHandgun(oi) else { return nil }
        return oi
    }

    // Game.gunInteract, each frame while a gun is held: true when the off trigger belongs to the offhand gun.
    static func tick(_ g: Game, down: Bool, dt: Float) -> Bool {
        cooldown -= dt
        guard let oi = active(g) else { wasDown = down; return false }
        let pressed = down && !wasDown
        wasDown = down
        guard pressed, cooldown <= 0 else { return true }
        var o = g.inventory.offhand[0]
        let gs = Guns.all[oi]
        if o.tag <= 0 {
            g.sfx(.gun(7), 0.6)
            return true
        }
        let aim = leftAim ?? {
            let right = V3(cosf(g.player.yaw), 0, -sinf(g.player.yaw))
            return (g.player.eye - right * 0.25 - V3(0, 0.15, 0), g.player.look)
        }()
        let dir = Guns.scatter(aim.dir, gs.spread * 0.6)
        let muzzle = aim.origin + aim.dir * 0.3
        var s = Slug(pos: muzzle, vel: dir * gs.speed, kind: .bullet, damage: gs.damage * Legendaries.gunScale(o) * GunGrade.damage(o), fromPlayer: true,
                     shooter: nil, by: "Player", life: gs.range / gs.speed, gravity: 1.5)
        s.pierce = Int8(Enchant.level(.penetration, o))
        s.incendiary = Enchant.level(.incendiary, o) > 0
        g.arms.spawn(s)
        o.tag -= 1
        g.inventory.offhand[0] = o
        cooldown = gs.interval * 1.2
        let k = gs.recoil * 0.8
        g.player.pitch = min(1.55, g.player.pitch + k)
        g.arms.recoilDebt += k * 0.6
        g.arms.bloom = min(gs.spread, g.arms.bloom + gs.spread * 0.25)
        g.arms.shotsFired += 1
        g.sfx(.gun(gs.sound), 1)
        g.baseNoise(at: g.player.pos, kind: .gunshot)
        TownLaw.gunfire(g, at: g.player.pos)
        g.addFlash(at: muzzle + aim.dir * 0.4, color: V3(4, 3, 1.6), radius: 6, life: 0.06)
        shots += 1
        return true
    }

    // Loads the offhand gun from the pack (a speedloader, or the timed reload).
    static func reloadOff(_ g: Game) {
        guard let oi = active(g) else { return }
        let gs = Guns.all[oi]
        var o = g.inventory.offhand[0]
        let n = min(Guns.magSize(o) - o.tag, g.ammoCount(gs.ammo))
        guard n > 0 else { return }
        g.takeAmmo(gs.ammo, n)
        o.tag += n
        g.inventory.offhand[0] = o
    }

    static func offEmptyOrLow(_ g: Game) -> Bool {
        guard active(g) != nil else { return false }
        let o = g.inventory.offhand[0]
        return o.tag < Guns.magSize(o)
    }
}
