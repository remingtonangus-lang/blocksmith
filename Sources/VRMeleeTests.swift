import Foundation
import simd

// `--swingtest`: the shared half of the VR melee and bow redesign (VRMelee.swift, docs/status/vr-melee.md): the blade
// sweep geometry (no tunnelling, reach limit), Game.interact never mining / attacking from a swing without contact,
// the trigger never attacking in Swing melee, a melee weapon never mining with a mob near, mob melee measured to the
// real head position, the bow pose for both hands and the VR bow shot, and the options text fitting the pause menu.
// The device path (QuestControls) is covered by the Quest sim (quest/src/test/QuestSim.swift, Linux CI).
enum VRMeleeTests {
    static func run(_ game: Game) -> Int {
        var fails = 0
        func check(_ ok: Bool, _ msg: String) {
            print("swingtest: \(ok ? "ok  " : "FAIL") \(msg)")
            if !ok { fails += 1 }
        }
        geometry(check)
        bow(check)
        text(check)
        play(game, check)
        print("swingtest: \(fails) failures")
        return fails
    }

    static func geometry(_ check: (Bool, String) -> Void) {
        let mn = V3(-0.3, 0, -2.3), mx = V3(0.3, 1.95, -1.7)               // a zombie 2 m ahead
        check(VRMelee.segmentBox(V3(0, 1, 0), V3(0, 1, -3), mn, mx) != nil && VRMelee.segmentBox(V3(1, 1, 0), V3(1, 1, -3), mn, mx) == nil,
              "segment vs box: through hits, beside misses")
        // A fast swing: the blade is left of the mob one frame and right of it the next (neither pose touches it).
        let h = V3(0, 1.2, -0.5)
        let a0 = h, b0 = h + V3(-1.2, 0, -1.4), a1 = h, b1 = h + V3(1.2, 0, -1.4)
        let r = VRMelee.bladeRadius
        let ends = VRMelee.sweepHit(a0: a0, b0: b0, a1: a0, b1: b0, radius: r, mn: mn, mx: mx) == nil
            && VRMelee.sweepHit(a0: a1, b0: b1, a1: a1, b1: b1, radius: r, mn: mn, mx: mx) == nil
        let swept = VRMelee.sweepHit(a0: a0, b0: b0, a1: a1, b1: b1, radius: r, mn: mn, mx: mx)
        check(ends && swept != nil, "fast swing past a mob between two frames: end poses miss \(ends), the sweep hits \(swept.map { "\($0)" } ?? "nil")")
        // The sword's hit capsule: a bit longer than the drawn ~1.21 m blade; a fist is short.
        let (sb, st, sr) = VRMelee.blade(handPos: .zero, handRot: simd_quatf(angle: 0, axis: V3(0, 1, 0)), size: 0.55, tool: true)
        let (fb, ft, _) = VRMelee.blade(handPos: .zero, handRot: simd_quatf(angle: 0, axis: V3(0, 1, 0)), size: 0, tool: false)
        let len = simd_length(st), flen = simd_length(ft - fb)
        check(len > 1.4 && len < 1.8 && sr >= 0.2 && simd_length(sb) < 0.3 && flen < 0.25,
              String(format: "blade capsule: sword tip %.2f m from the hand (r %.2f), fist %.2f m", len, sr, flen))
        check(VRMelee.power(VRMelee.minTipSpeed) >= 0.6 && abs(VRMelee.power(4) - 1) < 0.01 && VRMelee.power(20) <= 1.3,
              "swing power: 0.6 at the minimum tip speed, 1 at 4 m/s, at most 1.3")
    }

    // The bow for both hands: the arrow points from the drawing hand through the grip, the nock follows the hand
    // (to a full draw), the limbs stand across the arrow with the grip foremost (not inverted).
    static func bow(_ check: (Bool, String) -> Void) {
        for left in [false, true] {
            let sx: Float = left ? -1 : 1
            let name = left ? "left-handed" : "right-handed"
            let grip = V3(0.2 * sx, 1.3, -0.45), rot = simd_quatf(angle: 0, axis: V3(0, 1, 0))
            let rest = VRBow.pose(grip: grip, handRot: rot, drawHand: nil)
            let atString = VRBow.restNock(grip: grip, handRot: rot)
            let nocked = VRBow.pose(grip: grip, handRot: rot, drawHand: atString)
            let hand = V3(0.15 * sx, 1.33, 0.13)                       // pulled back to the cheek
            let drawn = VRBow.pose(grip: grip, handRot: rot, drawHand: hand)
            let far = VRBow.pose(grip: grip, handRot: rot, drawHand: V3(0.1 * sx, 1.35, 0.6))
            let wantDir = simd_normalize(grip - hand)
            let notInverted = [rest, drawn].allSatisfy { p in
                simd_dot(p.grip - p.limb(1), p.dir) > 0.1 && simd_dot(p.grip - p.limb(-1), p.dir) > 0.1
                    && simd_dot(p.tipTop - p.grip, V3(0, 1, 0)) > 0.4 && simd_dot(p.tipBottom - p.grip, V3(0, 1, 0)) < -0.4
            }
            check(rest.draw == 0 && nocked.draw < 0.05 && simd_length(rest.nock - atString) < 1e-4,
                  "bow (\(name)): at rest the string sits \(VRBow.brace) m behind the grip, no draw")
            check(simd_dot(drawn.dir, wantDir) > 0.999 && simd_length(drawn.nock - hand) < 0.02 && drawn.draw > 0.7 && drawn.draw < 1,
                  String(format: "bow (%@): pulled back %.2f m: draw %.2f, nock on the hand (%.3f m), arrow from the hand through the grip",
                         name, simd_length(grip - hand), drawn.draw, simd_length(drawn.nock - hand)))
            check(far.draw == 1 && abs(simd_length(far.grip - far.nock) - VRBow.fullDraw) < 1e-3,
                  "bow (\(name)): pulled past a full draw the string stops at \(VRBow.fullDraw) m")
            check(notInverted, "bow (\(name)): limbs upright, bending back toward the archer from a foremost grip")
            let bend = simd_dot(drawn.grip - drawn.tipTop, drawn.dir) - simd_dot(rest.grip - rest.tipTop, rest.dir)
            check(bend > 0.03, String(format: "bow (%@): the tips bend back %.3f m more at the draw", name, bend))
        }
    }

    // The options text fits the pause menu: button labels without shrinking (224-unit buttons, 20 units of arrows),
    // help lines in the two-line wrap.
    static func text(_ check: (Bool, String) -> Void) {
        for r in VRMelee.touchRows + ["Melee: Reclined", "Melee: Swing"] {
            check(Font.width(r) <= 204, "options text: \"\(r)\" \(Font.width(r)) <= 204 units")
        }
        for h in [VRMelee.optionHelp, VRMelee.reclinedPostureHelp] {
            check(Float(Font.width(h)) <= 2 * 232 / 0.85, "options help: \(Font.width(h)) units fits two lines: \(h)")
        }
    }

    static func play(_ game: Game, _ check: (Bool, String) -> Void) {
        let p = game.player
        let save = (game.inventory.held, p.yaw, p.pitch, game.paused, p.pos, p.flying, game.survival, game.health, game.bufferAttacks)
        defer {
            (game.inventory.held, p.yaw, p.pitch, game.paused, p.pos, p.flying, game.survival, game.health, game.bufferAttacks) = save
            game.meleeContactOnly = false; game.vrHead = nil; game.vrBow = nil; game.swingMob = nil; game.swingPower = 0
            game.input.leftDown = false; game.input.rightDown = false
        }
        // An open-air stone platform 60 blocks up, a dirt block under the feet.
        let P = V3(floorf(p.pos.x) + 0.5, floorf(p.pos.y) + 60, floorf(p.pos.z) + 0.5)
        let fy = Int(floorf(P.y)) - 1, fx = Int(floorf(P.x)), fz = Int(floorf(P.z))
        for dz in -4...4 { for dx in -4...4 {
            game.world.setBlock(fx + dx, fy, fz + dz, STONE)
            for k in 0...3 { game.world.setBlock(fx + dx, fy + 1 + k, fz + dz, AIR) }
        } }
        let dirt = IVec3(fx, fy, fz)
        game.world.setBlock(dirt.x, dirt.y, dirt.z, Blocks.id("dirt"))
        game.paused = false
        game.bufferAttacks = true
        game.survival = false
        p.flying = false
        func place() { p.pos = P; p.vel = .zero }
        func zombie(_ at: V3) -> Mob {
            let z = Mob(.husk, at: at)
            z.equip = nil
            game.mobs.mobs.append(z)
            return z
        }
        func remove(_ z: Mob) { game.mobs.mobs.removeAll { $0 === z } }
        func ticks(_ n: Int, _ body: () -> Void = {}) { for _ in 0..<n { place(); body(); game.tick(1.0 / 60) } }
        let sword = ItemStack(Items.id("iron_sword"), 1)

        // 1. A swing without contact (power, no mob) looking down at the dirt: nothing breaks.
        game.inventory.held = sword
        game.meleeContactOnly = true
        p.yaw = 0; p.pitch = -1.55
        ticks(10) { game.swingPower = 1.2; game.swingMob = nil }
        check(game.world.block(dirt.x, dirt.y, dirt.z) == Blocks.id("dirt"), "a swing that touched nothing breaks nothing (creative)")

        // 2. The blade hitting a mob: damage, and the block under the laser stays.
        let z1 = zombie(P + V3(0, 0, -2))
        let h0 = z1.health
        ticks(1) { z1.pos = P + V3(0, 0, -2); game.swingPower = 1; game.swingMob = z1 }
        ticks(2) { z1.pos = P + V3(0, 0, -2) }
        check(z1.health < h0 && game.world.block(dirt.x, dirt.y, dirt.z) == Blocks.id("dirt"),
              "a blade hit damages the zombie (\(h0) -> \(z1.health)) and breaks nothing")
        remove(z1)

        // 3. Swing melee: the trigger aimed at a zombie never attacks it; Reclined: it does.
        for contact in [true, false] {
            game.meleeContactOnly = contact
            let z = zombie(P + V3(0, 0, -2))
            let hz = z.health
            p.pitch = -0.35
            ticks(40) { z.pos = P + V3(0, 0, -2); z.vel = .zero; game.input.leftClicked = true }
            check(contact ? z.health == hz : z.health < hz,
                  "\(contact ? "Swing" : "Reclined") melee: trigger at a zombie \(contact ? "doesn't attack" : "attacks") (\(hz) -> \(z.health))")
            remove(z)
        }

        // 4. Bladed contact through the world: a fast sweep past the zombie between frames finds it; out of reach or
        // behind a wall it doesn't.
        do {
            let eye = P + V3(0, 1.62, 0)
            let z = zombie(P + V3(0, 0, -2))
            z.pos = P + V3(0, 0, -2)
            let hnd = eye + V3(0, -0.3, -0.5)
            let a = hnd, b0 = hnd + V3(-1.2, 0, -1.4), b1 = hnd + V3(1.2, 0, -1.4)
            let hit = game.bladeContact(a0: a, b0: b0, a1: a, b1: b1, radius: VRMelee.bladeRadius, eye: eye, except: [])
            check(hit?.0 === z, "blade sweep past a zombie 2 blocks ahead hits it")
            let skip = game.bladeContact(a0: a, b0: b0, a1: a, b1: b1, radius: VRMelee.bladeRadius, eye: eye, except: [ObjectIdentifier(z)])
            check(skip == nil, "each mob once per swing (already hit: skipped)")
            z.pos = P + V3(0, 0, -3.6)
            let far = game.bladeContact(a0: a + V3(0, 0, -1.6), b0: b0 + V3(0, 0, -1.6), a1: a + V3(0, 0, -1.6), b1: b1 + V3(0, 0, -1.6),
                                        radius: VRMelee.bladeRadius, eye: eye, except: [])
            check(far == nil, "reach: a blade reaching a zombie 3.6 blocks away (contact > \(VRMelee.reach)) doesn't hit")
            remove(z)
        }

        // 5. A melee weapon never mines with a mob near; a pickaxe does; the sword mines once it is gone.
        do {
            game.meleeContactOnly = true
            p.pitch = -1.55
            let z = zombie(P + V3(2.5, 0, -2.5))
            ticks(20) { z.pos = P + V3(2.5, 0, -2.5); z.vel = .zero; game.input.leftDown = true }
            let guarded = game.world.block(dirt.x, dirt.y, dirt.z) == Blocks.id("dirt")
            game.inventory.held = ItemStack(Items.id("iron_pickaxe"), 1)
            ticks(20) { z.pos = P + V3(2.5, 0, -2.5); z.vel = .zero; game.input.leftDown = true }
            let pick = game.world.block(dirt.x, dirt.y, dirt.z) != Blocks.id("dirt")
            game.world.setBlock(dirt.x, dirt.y, dirt.z, Blocks.id("dirt"))
            remove(z)
            game.inventory.held = sword
            ticks(20) { game.input.leftDown = true }
            let alone = game.world.block(dirt.x, dirt.y, dirt.z) != Blocks.id("dirt")
            game.input.leftDown = false
            ticks(2)
            game.world.setBlock(dirt.x, dirt.y, dirt.z, Blocks.id("dirt"))
            check(guarded && pick && alone, "trigger mining: sword with a zombie near breaks nothing \(guarded), pickaxe mines \(pick), sword alone mines \(alone)")
        }

        // 6. Mob melee reaches the real head: leaning back out of reach dodges, leaning in gets hit, and without a
        // headset (or standing over the feet) the reach is unchanged.
        do {
            game.survival = true
            game.meleeContactOnly = false
            let keepDiff = game.difficulty
            game.difficulty = 2
            defer { game.difficulty = keepDiff }
            p.pitch = 0
            func hurt(zombieAt dz: Float, lean: Float?) -> Bool {
                game.health = 20
                let z = zombie(P + V3(0, 0, -dz))
                defer { remove(z) }
                var took = false, last = game.health
                ticks(91) {
                    if game.health < last { took = true }
                    game.health = 20; last = 20
                    z.pos = P + V3(0, 0, -dz); z.vel = .zero
                    game.vrHead = lean.map { P + V3(0, 1.62, -$0) }
                }
                game.vrHead = nil
                return took
            }
            let near = hurt(zombieAt: 1.4, lean: nil)
            let over = hurt(zombieAt: 1.4, lean: 0)
            let back = hurt(zombieAt: 1.4, lean: -0.35)
            let lean = hurt(zombieAt: 1.85, lean: 0.35)
            let far = hurt(zombieAt: 1.85, lean: nil)
            check(near && over, "zombie 1.4 blocks away hits (no headset \(near), head over the feet \(over))")
            check(!back, "leaning 35 cm back from a zombie 1.4 blocks away dodges its hit (hit: \(back))")
            check(lean && !far, "a zombie 1.85 blocks away: misses the feet \(!far), hits a head leaning 35 cm in \(lean)")
            game.survival = false
        }

        // 7. The VR bow shot: power from the physical draw, from the bow along the nocked arrow.
        do {
            game.inventory.held = ItemStack(Items.id("bow"), 1)
            p.pitch = 1.4
            let dir = simd_normalize(V3(1, 0.1, -1))
            let origin = P + V3(0.3, 1.3, -0.4)
            game.vrBow = (draw: 0.8, origin: origin, dir: dir)
            let before = game.projectiles.arrows.count
            ticks(20) { game.input.rightDown = true }
            ticks(1) { game.input.rightDown = false }
            let shot = game.projectiles.arrows.count > before ? game.projectiles.arrows.last : nil
            let v = shot?.vel ?? .zero
            check(shot != nil && simd_dot(simd_normalize(v + V3(0, 1e-6, 0)), dir) > 0.98 && abs(simd_length(v) - 48) < 4,
                  String(format: "VR bow: draw 0.8 shoots along the arrow (dot %.3f) at %.1f b/s (want 48)",
                         simd_dot(simd_normalize(v + V3(0, 1e-6, 0)), dir), simd_length(v)))
            if let s = shot { game.projectiles.arrows.removeAll { $0 === s } }
        }
    }
}
