import Foundation
import simd

// L3 part 2 (VRCombatFeel.swift, docs/status/vr-combat-feel.md): enemy wind-ups (dodge, parry, off the headset none),
// the hit-stop, hit feel by material, the blade trail, the bow's nock, creak and string shiver, Reclined's aim assist
// (hostiles only), the crossbow from the aiming hand, the new sounds and the tutorials. questcheck and the Mac
// `--swingtest` run it; the device path (QuestControls) is in the Quest sim.
enum VRCombatFeelTests {
    static func run(_ game: Game, check: (Bool, String) -> Void) {
        pure(check)
        play(game, check)
    }

    static func pure(_ check: (Bool, String) -> Void) {
        // The blade trail: fast samples make a ribbon that fades within its life; slow ones make none.
        var t = BladeTrail()
        for i in 0..<5 { t.add(base: V3(Float(i) * 0.1, 1, 0), tip: V3(Float(i) * 0.1, 1, -1.5), speed: 5, now: 10 + Double(i) / 72) }
        let now = 10 + 4.0 / 72
        let fresh = t.segmentCount(now: now), later = t.segmentCount(now: now + 0.2)
        var slow = BladeTrail()
        for i in 0..<5 { slow.add(base: .zero, tip: V3(0, 0, -1), speed: 1, now: 10 + Double(i) / 72) }
        check(fresh == 4 && later == 0 && slow.segmentCount(now: now) == 0,
              "combat feel: the blade trail has \(fresh) segments behind a fast blade, \(later) after 0.2 s, \(slow.segmentCount(now: now)) for a slow one")
        // P77 (09:25, "a white strobing flicker when moving the sword"): a steady sword move whose tracked tip speed
        // jitters around the hit threshold keeps one trail, never popping on and off from frame to frame.
        var jit = BladeTrail()
        var drops = 0, litFrames = 0, was = false
        for i in 0..<72 {
            let v: Float = 2.1 + (i % 2 == 0 ? 0.55 : -0.55) + 0.15 * sinf(Float(i) * 1.7)
            jit.add(base: V3(Float(i) * 0.03, 1, 0), tip: V3(Float(i) * 0.03, 1, -1.2), speed: v, now: 20 + Double(i) / 72)
            let on = jit.segmentCount(now: 20 + Double(i) / 72) > 0
            if on { litFrames += 1 }
            if was && !on { drops += 1 }
            was = on
        }
        check(drops == 0 && litFrames > 60 && BladeTrail.peakAlpha <= 0.35,
              "P77 sword trail: a jittery steady move keeps one trail (\(drops) drop-outs over \(litFrames) lit frames of 72), faint at the blade (alpha \(BladeTrail.peakAlpha))")
        // The bow: the arrow slides onto the string, the limbs creak at 35/65/90 %, the string shivers then rests.
        let creaks = [VRBow.creak(from: 0.2, to: 0.4), VRBow.creak(from: 0.4, to: 0.5), VRBow.creak(from: 0.6, to: 0.95), VRBow.creak(from: 0.9, to: 0.5)]
        let wob = (0..<20).map { abs(VRBow.stringWobble(Float($0) * 0.005, draw: 1)) }.max() ?? 0
        check(VRBow.nockSlide(0) > 0.2 && VRBow.nockSlide(VRBow.nockTime) == 0 && creaks[0] == 0.35 && creaks[1] == nil && creaks[2] == 0.65 && creaks[3] == nil
              && wob > 0.01 && VRBow.stringWobble(0.5, draw: 1) == 0 && VRBow.stringWobble(0.01, draw: 0) == 0,
              "combat feel: the arrow slides " + String(format: "%.2f m", VRBow.nockSlide(0)) + " onto the string, creaks at 35/65/90 %, the string shivers " + String(format: "%.1f cm", wob * 100) + " and stops")
        // The sounds: in the bank, each passing the sound check, each with a subtitle.
        var bad: [String] = []
        for s in [Snd.meleeWindUp, .parryClang, .bowCreak, .bowNock] {
            let c = SoundBank.check(s, SoundBank.render(s, variant: 0))
            if !c.ok || !SoundBank.allSounds.contains(where: { $0.name == s.name }) { bad.append("\(s.name): " + c.problems.joined(separator: ", ")) }
        }
        check(bad.isEmpty, "combat feel: wind-up, parry clang, bow creak and nock sounds in the bank (\(bad.isEmpty ? "all 4" : bad.joined(separator: "; ")))")
        let swing = VRMelee.swingTutorial.joined(separator: " "), reclined = VRMelee.reclinedTutorial.joined(separator: " ")
        // Each line is one toast: it must fit the Quest HUD (1024 px at scale 2: 512 units, with its backing margin).
        let widest = (VRMelee.swingTutorial + VRMelee.reclinedTutorial).map { Font.width($0) }.max() ?? 0
        check(swing.contains("dodge") && swing.contains("parry") && reclined.contains("Melee") && widest <= 480
              && Double(VRMelee.swingTutorial.count) * VRMelee.tutorialGap < 12,
              "combat feel: the Swing tutorial teaches the dodge and the parry, the Reclined one where to switch; each toast fits (widest \(widest) of 480 units)")
        check(Float(Font.width(VRMelee.reclinedPostureHelp)) <= 2 * 232 / 0.85,
              "combat feel: the Lying Down View help (\(Font.width(VRMelee.reclinedPostureHelp)) units) fits the pause menu's two lines")
    }

    static func play(_ game: Game, _ check: (Bool, String) -> Void) {
        let p = game.player
        let save = (game.inventory.held, p.yaw, p.pitch, game.paused, p.pos, p.flying, game.survival, game.health, game.vrHead, game.swingMelee)
        defer {
            (game.inventory.held, p.yaw, p.pitch, game.paused, p.pos, p.flying, game.survival, game.health, game.vrHead, game.swingMelee) = save
            game.vrAim = nil; game.audio.record = nil
        }
        let P = V3(floorf(p.pos.x) + 0.5, floorf(p.pos.y) + 70, floorf(p.pos.z) + 0.5)
        let fy = Int(floorf(P.y)) - 1, fx = Int(floorf(P.x)), fz = Int(floorf(P.z))
        // The arena is put back afterwards (the sky checks later look up from this spot).
        var was: [(Int, Int, Int, BlockID)] = []
        for dz in -5...5 { for dx in -5...5 { for k in 0...4 { was.append((fx + dx, fy + k, fz + dz, game.world.block(fx + dx, fy + k, fz + dz))) } } }
        defer { for (x, y, z, b) in was { game.world.setBlock(x, y, z, b) } }
        for dz in -5...5 { for dx in -5...5 {
            game.world.setBlock(fx + dx, fy, fz + dz, STONE)
            for k in 0...3 { game.world.setBlock(fx + dx, fy + 1 + k, fz + dz, AIR) }
        } }
        game.paused = false; game.survival = true; game.health = 20; p.flying = false
        p.pos = P; p.vel = .zero; p.yaw = 0; p.pitch = 0
        var spawned: [Mob] = []
        func mob(_ k: MobKind, _ at: V3) -> Mob { let m = Mob(k, at: at); m.equip = nil; game.mobs.mobs.append(m); spawned.append(m); return m }
        defer { game.mobs.mobs.removeAll { m in spawned.contains { $0 === m } } }

        // 1. Hit feel: flesh, armour, bone.
        let z = mob(.zombie, P + V3(0, 0, -1.6))
        let armoured = Mob(.zombie, at: P); armoured.equip = [.empty, ItemStack(Items.id("iron_chestplate"), 1), .empty, .empty, .empty]
        let feels = [HitFeel.of(z), HitFeel.of(armoured), HitFeel.of(Mob(.skeleton, at: P)), HitFeel.of(Mob(.ironGolem, at: P))]
        let hz = feels.map { $0.haptic(power: 1).2 }
        check(feels == [.flesh, .armour, .hard, .hard] && Set(hz).count == 3,
              "combat feel: a zombie is flesh, one in an iron chestplate armour, a skeleton and a golem hard; haptics at \(hz.map { Int($0) }) Hz")

        // 2. Off the headset nothing changes: the strike lands at once.
        game.vrHead = nil
        z.attackCooldown = 0
        check(game.meleeStrike(z, reach: z.halfW + 1.3) && z.windUp == 0, "combat feel: off VR a zombie in reach strikes at once (no wind-up)")

        // 3. VR: it winds up (a sound), then strikes if you're still there...
        game.vrHead = p.eye
        game.audio.record = [:]
        z.attackCooldown = 0
        let first = game.meleeStrike(z, reach: z.halfW + 1.3)
        let wound = z.windUp
        let grunt = game.audio.record?[Snd.meleeWindUp.name] ?? 0
        // The zombie's own AI lands the strike when the wind-up ends (the player's health drops then, not before).
        game.health = 20
        var landed = false, t: Float = 0
        while t < 1, !landed { z.update(1.0 / 60, game: game); z.pos = P + V3(0, 0, -1.6); z.vel = .zero; t += 1.0 / 60; landed = game.health < 20 }
        check(!first && wound == VRMelee.windUpTime && grunt == 1 && landed && t >= VRMelee.windUpTime - 0.02 && t < VRMelee.windUpTime + 0.2,
              "combat feel: in VR a zombie winds up (" + String(format: "%.2f s", wound) + ", grunt \(grunt)) and strikes after " + String(format: "%.2f s", t))
        // ... and misses if you stepped back.
        z.attackCooldown = 0; z.windUp = 0; z.windUpDone = false
        _ = game.meleeStrike(z, reach: z.halfW + 1.3)
        let d0 = game.dodges
        z.windUp = 0; z.windUpDone = true
        p.pos = P + V3(0, 0, 2.5); game.vrHead = p.eye                  // the body (and headset) stepped back
        let hitAway = game.meleeStrike(z, reach: z.halfW + 1.3)
        p.pos = P; game.vrHead = p.eye
        check(!hitAway && game.dodges == d0 + 1 && z.attackCooldown > 0, "combat feel: stepping out of reach during the wind-up dodges the strike")
        // A finished wind-up the AI didn't use (it stopped targeting you) is dropped, so it can't strike later unwarned.
        z.windUp = 0.01; z.windUpDone = false
        game.survival = false
        for _ in 0..<12 { z.update(1.0 / 60, game: game); z.pos = P + V3(0, 0, -1.6); z.vel = .zero }
        game.survival = true
        check(!z.windUpDone && z.windUp == 0, "combat feel: an unused wind-up is dropped, never kept for a later unwarned strike")

        // 4. A parry: the blade meets it high while it winds up; low, or not winding up, is a normal hit.
        z.attackCooldown = 0; z.windUp = 0; z.windUpDone = false
        _ = game.meleeStrike(z, reach: z.halfW + 1.3)
        let low = game.tryParry(z, at: z.pos + V3(0, 0.3, 0), along: V3(1, 0, 0))
        let hp0 = z.health
        let high = game.tryParry(z, at: z.pos + V3(0, z.height * 0.8, 0), along: V3(1, 0, 0))
        let idle = game.tryParry(z, at: z.pos + V3(0, z.height * 0.8, 0), along: V3(1, 0, 0))
        check(!low && high && !idle && z.windUp == 0 && z.attackCooldown >= VRMelee.parryStagger - 0.01 && z.health == hp0 && z.hitStop > 0,
              "combat feel: a blade high on a winding-up zombie parries (no damage, staggered " + String(format: "%.1f s", z.attackCooldown) + "); low or idle it doesn't")

        // 5. The hit-stop: a frozen mob doesn't move until it ends.
        z.hitStop = VRMelee.hitStop; z.vel = V3(4, 0, 0)
        let x0 = z.pos.x
        game.mobs.update(1.0 / 60, game: game)
        let frozen = abs(z.pos.x - x0) < 1e-4
        for _ in 0..<6 { game.mobs.update(1.0 / 60, game: game) }
        check(frozen && z.hitStop <= 0 && abs(z.pos.x - x0) > 0.01, "combat feel: a landed blade freezes the mob for the hit-stop, then it moves")

        // 6. Reclined aim assist: a zombie 8 degrees off the laser is picked; a villager there isn't; Swing melee has none.
        game.mobs.mobs.removeAll { m in spawned.contains { $0 === m } }; spawned.removeAll()
        game.inventory.held = ItemStack(Items.id("iron_sword"), 1)
        game.swingMelee = false
        p.pos = P; p.yaw = 0; p.pitch = 0
        let off: Float = 8 * .pi / 180
        let at = p.eye + V3(sinf(off), 0, -cosf(off)) * 2.5 - V3(0, 0.9, 0)
        let zz = mob(.zombie, at)
        let picked = game.reclinedAssist(reach: 3.5)?.0 === zz
        game.mobs.mobs.removeAll { $0 === zz }
        let vil = mob(.villager, at)
        let friendly = game.reclinedAssist(reach: 3.5) == nil
        game.mobs.mobs.removeAll { $0 === vil }
        _ = mob(.zombie, at)
        game.swingMelee = true
        let swingNone = game.reclinedAssist(reach: 3.5) == nil
        game.swingMelee = false
        check(picked && friendly && swingNone, "combat feel: Reclined aim assist picks a zombie 8 degrees off the laser (\(picked)), never a villager (\(friendly)), not in Swing melee (\(swingNone))")

        // 7. The crossbow shoots from the aiming hand along its ray (VR), not from the eyes.
        var cb = ItemStack(Items.id("crossbow"), 1)
        cb.tag = Int(Items.id("arrow")); cb.contents = [ItemStack(Items.id("arrow"), 1)]
        game.inventory.held = cb
        let hand = p.eye + V3(0.3, -0.4, -0.2), dir = simd_normalize(V3(0.2, 0.1, -1))
        game.vrAim = (hand, dir)
        let n0 = game.projectiles.arrows.count
        _ = game.crossbowUse(true, true, 1.0 / 60)
        let arrow = game.projectiles.arrows.count > n0 ? game.projectiles.arrows.last : nil
        let fromHand = arrow.map { simd_length($0.pos - (hand + dir * 0.3)) < 0.5 && simd_dot(simd_normalize($0.vel), dir) > 0.99 } ?? false
        check(fromHand, "combat feel: the crossbow shoots from the aiming hand along its ray")
        if let a = arrow { game.projectiles.arrows.removeAll { $0 === a } }
    }
}
