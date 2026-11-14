import Foundation
import simd

// Checks for the Nov 13 playtest's fixes that need no world of their own (questcheck suite).
enum Nov13Checks {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        scopeEyepiece(check)
        helmHold(g, check)
        LetterCheck.run(check)
        commandant(g, check)
        parachute(g, check)
    }

    // Nov 14 ("Add parachutes"): on the ground a use does nothing; falling, it opens; it steers forward, sinks at its
    // rate, lands him with no fall to take, and folds away on the ground.
    static func parachute(_ g: Game, _ check: (Bool, String) -> Void) {
        let p = g.player, w = g.world
        let save = (p.pos, p.vel, p.flying, p.yaw)
        defer { p.pos = save.0; p.vel = save.1; p.flying = save.2; p.yaw = save.3; p.parachute = false; p.airPeak = p.pos.y }
        let x = Int(floor(p.pos.x)), z = Int(floor(p.pos.z))
        let top = w.topY(x, z)
        p.flying = false; p.yaw = 0
        p.pos = V3(Float(x) + 0.5, Float(top + 1), Float(z) + 0.5); p.vel = .zero
        for _ in 0..<15 { p.update(dt: 1.0 / 30, input: MoveInput(), world: w) }
        let groundUse = g.openParachute()
        p.parachute = false
        // 60 blocks up, already falling fast.
        p.pos = V3(Float(x) + 0.5, Float(top + 61), Float(z) + 0.5); p.vel = V3(0, -25, 0); p.onGround = false; p.airPeak = p.pos.y
        let opened = g.openParachute()
        // Three seconds stick forward, then held back the rest of the way down.
        var steps = 0, sink: Float = 0, fwd: Float = 0, gap: Float = 99, landed = false
        while steps < 30 * 60 {
            let back = steps >= 90
            p.update(dt: 1.0 / 30, input: MoveInput(forward: back ? -1 : 1), world: w)
            steps += 1
            if steps == 90 { fwd = simd_length(V2(p.vel.x, p.vel.z)) }
            if steps > 60 && !p.onGround { sink = max(sink, -p.vel.y) }
            if p.onGround { landed = true; gap = p.airPeak - p.pos.y; break }
        }
        p.update(dt: 1.0 / 30, input: MoveInput(), world: w)
        // A soldier dropped from 40 up opens his and lands unhurt; a cow doesn't have one.
        let sx = x + 6, stop = w.topY(sx, z)
        let m = Mob(.soldierTrooper, at: V3(Float(sx) + 0.5, Float(stop + 41), Float(z) + 0.5))
        m.persistent = true
        let hp0 = m.health
        var mChute = false, mSteps = 0
        while mSteps < 20 * 40 && !(m.onGround && mSteps > 5) { m.update(0.05, game: g); mChute = mChute || m.chute; mSteps += 1 }
        let mHurt = m.health < hp0, mFolded = !m.chute
        check(mChute && m.onGround && !mHurt && mFolded,
              String(format: "parachute: a soldier dropped from 40 blocks opens his (%@), lands after %.1f s unhurt (%@), folds it (%@)",
                     mChute ? "yes" : "no", Float(mSteps) * 0.05, mHurt ? "hurt" : "yes", mFolded ? "yes" : "no"))
        check(!groundUse && opened && landed && sink < Parachute.sink + 0.3 && fwd > 4.5 && gap < 1 && !p.parachute,
              String(format: "parachute: a use on the ground does nothing (%@); falling at 25 b/s it opens (%@), sinks at %.1f b/s at worst, drifts %.1f b/s stick forward, lands after %.1f s with %.1f blocks of fall to take, folds away (%@)",
                     groundUse ? "it opened" : "yes", opened ? "yes" : "no", sink, fwd, Float(steps) / 30, gap, p.parachute ? "still open" : "yes"))
    }

    // 12:45:04-12:45:10, a Capital side tower's top floor: its commandant, tough, carrying two Sunder Charges.
    static func commandant(_ g: Game, _ check: (Bool, String) -> Void) {
        guard let m = Mob.structureMob("soldier_officer:commandant^180", at: g.player.pos + V3(0, 0, 6)) else {
            check(false, "commandant: the structure key makes a mob"); return
        }
        let sunder = m.spec.drops.first { $0.0 == "sunder_charge" }?.1 ?? 0
        check(m.commandant && m.health >= 90 && sunder == 2 && m.customName == Mob.commandantName && m.persistent,
              "commandant: a Capital tower's commandant (\(m.customName ?? "-"), \(m.health) health, \(sunder) Sunder Charges carried)")
    }

    // 12:38-12:40, the Mahlwerk with a scope fitted ("Not sure where the scope is in this thing, but it ain't really
    // working"): the VR scope judged his eye at the gun's own sight line (0.44 m behind the grip, a rifle's cheek); the
    // fitted scope is drawn over the barrels. Upgrades.scopeEyepiece is the drawn scope's rear, and on the Mahlwerk it
    // sits far from where the eye was looked for.
    static func scopeEyepiece(_ check: (Bool, String) -> Void) {
        let gi = Guns.rotary
        let ench = Enchant.pack([(.stability, 1)])
        let parts = Guns.upgradeParts(gi, ench, magOut: false)
        guard let tube = parts.first, let e = Upgrades.scopeEyepiece(Guns.models[gi], ench) else {
            check(false, "scope eyepiece: the Mahlwerk with a scope fitted has a drawn scope and an eyepiece (\(parts.count) parts)"); return
        }
        let onTube = abs(e.z - tube.mx.z) < 0.01 && e.x > tube.mn.x && e.x < tube.mx.x && e.y > tube.mn.y && e.y < tube.mx.y
        // The old eye point in the model's pixels (QuestControls.heldGunShift at the held scale 1: 0.04 m a pixel).
        let k: Float = 0.0125 * 3.2
        let oldEye = V3(0, 0.085, 0.44) / k
        let apart = simd_length(e - oldEye) * k
        let none = Upgrades.scopeEyepiece(Guns.models[gi], 0) == nil
        check(onTube && apart > 0.3 && none,
              String(format: "scope eyepiece: the Mahlwerk's fitted scope's eyepiece is the drawn scope's rear (%@), %.2f m from the rifle-cheek point the VR scope looked for; no scope, no eyepiece (%@)",
                     onTube ? "yes" : "no", apart, none ? "yes" : "no"))
    }

    // 12:56:29-12:57:11, an Ironback Crawler ("Why is the helm locked?... They're not holding it right now, though"):
    // the driver holds the helm while at it; off at the far end of the hull fighting, the helm is free; a post not yet
    // manned still holds it.
    static func helmHold(_ g: Game, _ check: (Bool, String) -> Void) {
        let ships = g.world.ships
        let s = ships.spawn(AshWrecks.salvagedFighter(), at: g.player.pos + V3(0, 40, 30), yaw: 0, name: "helm hold", role: "test")
        defer { ships.remove(s, turrets: false) }
        guard let h = s.helm else { check(false, "helm hold: the test hull has a helm"); return }
        let st = CapitalState()
        st.crew = [V3(Float(h.x) + 0.5, Float(h.y), Float(h.z) + 1.5)]
        st.crewRoles = [.driver]
        let unmanned = ships.helmHeld(s, st)
        st.crewDone = [0]
        let m = Mob(.soldierTrooper, at: s.toWorld(st.crew[0]))
        st.crewMobs[0] = m
        let atHelm = ships.helmHeld(s, st)
        m.pos = s.toWorld(V3(Float(h.x) + 0.5, Float(h.y), Float(h.z) + 9))
        let away = ships.helmHeld(s, st)
        m.pos = s.toWorld(st.crew[0]); m.health = 0
        let dead = ships.helmHeld(s, st)
        check(unmanned && atHelm && !away && !dead,
              "helm hold: a crawler's helm is held by its driver's post not yet manned (\(unmanned)), by the driver at it (\(atHelm)); not by a driver 8 blocks off (\(!away ? "free" : "held")) or a dead one (\(!dead ? "free" : "held"))")
    }
}
