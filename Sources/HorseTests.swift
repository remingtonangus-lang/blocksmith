import Foundation
import simd

// Horse handling checks (`Blocksmith --horsetests` on the Mac, and part of every questcheck run): the objectives in
// docs/status/horses.md measured on a flat test strip built high in the sky over the spawn, riding through the mob's
// own update (Mob.update -> updateRidden -> gaitStep), plus one pass through Game.tick with the Touch-pad snapshot.
//   gaits      walk / trot / canter / gallop speeds; time to a gallop; stopping time; no lurch above 12.5 b/s^2
//   turning    a walk turns at least twice as fast as a gallop
//   stamina    a level-1 gallop lasts 10-25 s; a blown horse drops to a trot and rears when spurred; it refills at a walk
//   bond       points from riding, pats, brushing and treats; levels; saddlebags at level 2; saved with the horse
//   footing    stops at the strip's end (a sheer drop) and before lava; rides down a staircase and off a 3-block step
//   crash      a flat-out gallop into a wall stumbles; level 1 throws the rider, level 2 doesn't
//   nerves     a blast, a cannon and a monster beside it make it rear; the rider's own gunshot doesn't; level 4 never
//              throws; a pat while it rears calms it
//   others     camels keep their old pace; the Quest spur (stick click) through Game.tick steps the gait up
enum HorseTests {
    static func run(game g: Game, check: (Bool, String) -> Void) {
        let t0 = CFAbsoluteTimeGetCurrent()
        let w = g.world
        let wasRiding = g.riding, wasPos = g.player.pos, wasBond = g.horseBond, wasSurvival = g.survival
        defer {
            g.riding = wasRiding; g.player.pos = wasPos; g.horseBond = wasBond; g.survival = wasSurvival
            g.player.moveYaw = nil; g.rideInput = MoveInput()
            print(String(format: "horsetests: %.1f s", CFAbsoluteTimeGetCurrent() - t0))
        }
        // The strip: stone, 7 wide along -z (the way a horse at yaw 0 faces), 128 long, at Y; air for 6 above.
        let sx = Int(floor(g.player.pos.x)), sz = Int(floor(g.player.pos.z))
        _ = w.loadSync(center: V3(Float(sx), 200, Float(sz)), radius: 5)
        let Y = min(CH - 24, (w.topY(sx, sz)) + 60)
        let stone = Blocks.id("stone")
        let z0 = sz + 63, z1 = sz - 64                                  // start (south) and the end (north) edge
        w.deferRemesh = true
        for z in z1...z0 { for x in sx - 3...sx + 3 {
            w.setBlock(x, Y, z, stone)
            for y in Y + 1...Y + 6 where w.block(x, y, z) != AIR { w.setBlock(x, y, z, AIR) }
        } }
        w.deferRemesh = false
        let lane0 = V3(Float(sx) + 0.5, Float(Y + 1), Float(z0) - 1.5)
        g.survival = true

        func horse(top: Int = 15, xp: Float = 0) -> Mob {
            let h = Mob(.horse, at: lane0)
            h.variant = (top << 4) | (8 << 8)
            h.owner = true; h.saddled = true; h.persistent = true; h.health = 30
            h.hs.bondXP = xp
            h.yaw = 0
            return h
        }
        func mount(_ h: Mob) {
            g.riding = h; g.player.yaw = 0; g.player.moveYaw = nil
            g.player.pos = h.pos + V3(0, h.height * 0.75, 0)
        }
        let dt: Float = 1.0 / 72
        // Ticks the ridden horse with this stick push; a spur on the given ticks; wraps it back along the strip when
        // `loop` (a treadmill: speed kept) so long gallops fit. Returns the worst horizontal acceleration seen.
        @discardableResult
        func ride(_ h: Mob, _ secs: Float, push: Float, spurAt: Set<Int> = [], loop: Bool = false, each: ((Int) -> Bool)? = nil) -> Float {
            var worst: Float = 0
            var last = V2(h.vel.x, h.vel.z)
            let n = Int(secs / dt)
            for i in 0..<n {
                var mi = MoveInput(forward: push)
                mi.spur = spurAt.contains(i)
                g.rideInput = mi
                h.update(dt, game: g)
                let v = V2(h.vel.x, h.vel.z)
                if h.onGround { worst = max(worst, simd_length(v - last) / dt) }
                last = v
                if loop && h.pos.z < Float(z1) + 30 { h.pos.z += 90; g.player.pos.z += 90 }
                if let e = each, e(i) { break }
                if g.riding !== h { break }
            }
            return worst
        }
        func speed(_ h: Mob) -> Float { simd_length(V2(h.vel.x, h.vel.z)) }

        // Gaits and momentum (a top-speed horse: 16 b/s).
        do {
            let h = horse(); mount(h)
            ride(h, 2.5, push: 0.5)
            let walk = speed(h)
            ride(h, 2.5, push: 1)
            let trot = speed(h)
            h.pos = lane0; h.vel = .zero; h.hs.speed = 0; h.hs.gait = .stand
            var tGallop: Float = -1
            var tick = 0
            let lurch = ride(h, 3, push: 1, spurAt: [2, 12], loop: true) { i in
                tick = i
                if tGallop < 0 && speed(h) > 0.95 * h.topSpeed { tGallop = Float(i) * dt }
                return false
            }
            _ = tick
            let gallop = speed(h)
            var tStop: Float = -1
            let lurch2 = ride(h, 3, push: 0, loop: true) { i in
                if tStop < 0 && speed(h) < 0.5 { tStop = Float(i) * dt }
                return tStop >= 0
            }
            check(walk > 1 && walk <= 2.7 && abs(trot - 8) < 0.4 && abs(gallop - 16) < 0.5,
                  String(format: "horse gaits: walk %.1f, trot %.1f, gallop %.1f b/s (top 16)", walk, trot, gallop))
            check(tGallop >= 1 && tGallop <= 2.2, String(format: "horse: standstill to gallop in %.2f s (1-2.2)", tGallop))
            check(tStop >= 0.6 && tStop <= 1.6, String(format: "horse: gallop to a stop in %.2f s (0.6-1.6)", tStop))
            check(max(lurch, lurch2) <= 12.5, String(format: "horse: no lurch (worst %.1f b/s^2 on the ground, comfort limit 12.5)", max(lurch, lurch2)))
            // Turning: the rider looks 90 degrees aside; the horse comes round fast at a walk, slowly at a gallop.
            func turnRate(_ push: Float, spurs: Set<Int>) -> Float {
                h.pos = lane0; h.vel = .zero; h.hs.speed = 0; h.hs.gait = .stand; h.yaw = 0; g.player.yaw = 0
                ride(h, 2.2, push: push, spurAt: spurs, loop: true)
                let y0 = h.yaw
                g.player.yaw = .pi / 2
                ride(h, 0.15, push: push, loop: true)
                g.player.yaw = 0
                return (h.yaw - y0) / 0.15
            }
            let rw = turnRate(0.5, spurs: []), rg = turnRate(1, spurs: [2, 12])
            check(rw > 2 * rg && rg > 0.8, String(format: "horse turning: %.1f rad/s at a walk, %.1f at a gallop", rw, rg))
        }

        // Stamina.
        do {
            let h = horse(); mount(h)
            var tSpent: Float = -1
            ride(h, 40, push: 1, spurAt: [2, 12], loop: true) { i in
                if tSpent < 0 && h.hs.spent { tSpent = Float(i) * dt }
                return tSpent >= 0
            }
            check(tSpent >= 10 && tSpent <= 25, String(format: "horse stamina: a level-1 gallop lasts %.1f s (10-25)", tSpent))
            ride(h, 2, push: 1, loop: true)
            let blown = speed(h)
            let spurs = h.hs.spurCount
            ride(h, 0.1, push: 1, spurAt: [1], loop: true)
            let reared = h.hs.rear > 0 && h.hs.gait != .gallop && h.hs.spurCount == spurs + 1
            check(blown <= h.gaitSpeed(.trot) + 0.3 && reared,
                  String(format: "horse blown: %.1f b/s (trot %.1f), spurring it rears: %@", blown, h.gaitSpeed(.trot), reared ? "yes" : "no"))
            let s0 = h.stamina
            ride(h, 5, push: 0.5, loop: true)
            check(h.stamina > s0 + 30, String(format: "horse stamina refills at a walk: %.0f -> %.0f in 5 s", s0, h.stamina))
        }

        // Bond: riding, pats, brushing, treats; levels, saddlebags, saved.
        do {
            check(HorseFeel.level(0) == 1 && HorseFeel.level(99) == 1 && HorseFeel.level(100) == 2 && HorseFeel.level(300) == 3
                  && HorseFeel.level(700) == 4, "horse bond levels at 0 / 100 / 300 / 700 points")
            let h = horse(); mount(h)
            ride(h, 4, push: 1, loop: true)                         // a trot: 8 b/s
            let ridden = h.hs.bondXP
            check(g.horseBond != 0 && h.bond == g.horseBond && ridden >= 1.5,
                  String(format: "horse bond: %.0f points from 4 s of trotting (1 per 12 blocks; bonded %@, %.1f blocks toward the next)", ridden,
                         h.bond == g.horseBond && h.bond != 0 ? "yes" : "no", h.hs.rideAccum))
            let held = g.inventory.held
            g.inventory.held = .empty
            let b0 = h.hs.bondXP
            _ = g.horseUse(h); _ = g.horseUse(h)                    // a pat, then one inside the 15 s cooldown
            let patted = h.hs.bondXP - b0
            g.inventory.held = ItemStack(Items.id("brush"), 1)
            let b1 = h.hs.bondXP
            _ = g.horseUse(h)
            let brushed = h.hs.bondXP - b1
            g.inventory.held = ItemStack(Items.id("apple"), 4)
            h.stamina = 10
            let b2 = h.hs.bondXP
            let fed = g.horseUse(h)
            let treat = (h.hs.bondXP - b2, h.stamina)
            g.inventory.held = held
            check(patted == 4 && brushed == 15 && fed && treat.0 == 3 && treat.1 >= 34,
                  String(format: "horse care: pat +%.0f (once per 15 s), brush +%.0f, apple +%.0f and stamina 10 -> %.0f", patted, brushed, treat.0, treat.1))
            h.hs.bondXP = 99
            let bagsBefore = h.saddlebags
            h.addBond(1, g)
            let bags = h.saddlebags && MountMenu.opens(h) && g.packContainer(h).count == 9
            check(!bagsBefore && bags && h.staminaMax == 115, "horse bond level 2: saddlebags (9 slots) and 115 stamina")
            g.packContainer(h)[0] = ItemStack(Items.id("apple"), 3)
            let back = Mob.from(h.record)
            check(back?.hs.bondXP == 100 && back?.saddlebags == true && back?.cargo?[0].count == 3,
                  "horse bond points and saddlebags saved with the horse")
            g.riding = nil
        }

        // Footing: the strip's north end is a sheer drop; lava; a staircase; a 3-block step.
        do {
            let h = horse(); mount(h)
            h.pos = V3(lane0.x, lane0.y, Float(z1) + 40)
            var fell = false
            ride(h, 8, push: 1, spurAt: [2, 12]) { _ in if h.pos.y < Float(Y + 1) - 0.2 { fell = true }; return fell }
            let edgeGap = h.pos.z - h.halfW - Float(z1)
            check(!fell && speed(h) < 0.2 && edgeGap >= -0.05 && edgeGap < 2.5,
                  String(format: "horse refuses the cliff: stopped %.2f blocks short of the edge at a gallop, fell: %@", edgeGap, fell ? "yes" : "no"))
            // Lava two blocks deep in a pit across the strip.
            let lz = z0 - 50
            w.deferRemesh = true
            for x in sx - 3...sx + 3 { w.setBlock(x, Y, lz, Blocks.id("lava")); w.setBlock(x, Y, lz - 1, Blocks.id("lava")) }
            w.deferRemesh = false
            h.pos = lane0; h.vel = .zero; h.hs.speed = 0; h.hs.gait = .stand; h.stamina = h.staminaMax
            var burned = false
            ride(h, 8, push: 1, spurAt: [2, 12]) { _ in if h.pos.z - h.halfW < Float(lz) + 1 { burned = true }; return burned }
            check(!burned && speed(h) < 0.2, String(format: "horse refuses lava: stopped %.2f blocks short", h.pos.z - h.halfW - Float(lz + 1)))
            w.deferRemesh = true
            for x in sx - 3...sx + 3 { w.setBlock(x, Y, lz, stone); w.setBlock(x, Y, lz - 1, stone) }
            // A staircase down (1 block every 2) of 8 steps, then a 3-block step, then flat; built off the strip's
            // middle by lowering the strip itself.
            let top = z0 - 30
            for k in 0..<56 { for x in sx - 3...sx + 3 {
                let z = top - k
                let drop = min(8, k / 2) + (k >= 24 ? 3 : 0)
                w.setBlock(x, Y, z, AIR)
                w.setBlock(x, Y - drop, z, stone)
            } }
            w.deferRemesh = false
            h.pos = lane0; h.vel = .zero; h.hs.speed = 0; h.hs.gait = .stand; h.stamina = h.staminaMax
            var minFast: Float = 99
            var reached = false
            ride(h, 8, push: 1, spurAt: [2, 12]) { i in
                if Float(i) * dt > 2.5 && !reached { minFast = min(minFast, speed(h)) }
                if h.pos.z < Float(top - 50) { reached = true }
                return reached
            }
            check(reached && minFast > 9, String(format: "horse rides down a staircase and a 3-block step at a gallop (slowest %.1f b/s, at z %.1f of %d)",
                                                 minFast, h.pos.z, top - 50))
            w.deferRemesh = true
            for k in 0..<56 { for x in sx - 3...sx + 3 {
                let z = top - k
                let drop = min(8, k / 2) + (k >= 24 ? 3 : 0)
                if drop > 0 { w.setBlock(x, Y - drop, z, AIR) }
                w.setBlock(x, Y, z, stone)
            } }
            w.deferRemesh = false
            g.riding = nil
        }

        // Crashes: a 3-high wall across the strip.
        do {
            let wz = z0 - 40
            w.deferRemesh = true
            for x in sx - 3...sx + 3 { for y in Y + 1...Y + 3 { w.setBlock(x, y, wz, stone) } }
            w.deferRemesh = false
            var results: [(Int, Bool, Float)] = []
            for xp: Float in [0, 100] {
                let h = horse(xp: xp); mount(h)
                var top: Float = 0
                ride(h, 6, push: 1, spurAt: [2, 12]) { _ in top = max(top, speed(h)); return h.hs.stumbles > 0 }
                results.append((h.hs.stumbles, g.riding === h, top))
                g.riding = nil
            }
            check(results[0].0 == 1 && !results[0].1 && results[1].0 == 1 && results[1].1,
                  "horse crash: a gallop into a wall stumbles (\(results[0].0), \(results[1].0) at \(Int(results[0].2)) b/s); level 1 throws the rider (\(results[0].1 ? "kept" : "thrown")), level 2 keeps them (\(results[1].1 ? "kept" : "thrown"))")
            w.deferRemesh = true
            for x in sx - 3...sx + 3 { for y in Y + 1...Y + 3 { w.setBlock(x, y, wz, AIR) } }
            w.deferRemesh = false
        }

        // Nerves.
        do {
            let h = horse(xp: 700); mount(h)                       // level 4: never throws, so every fright is seen
            ride(h, 0.5, push: 0)
            g.baseNoise(at: g.player.pos, kind: .gunshot)
            let own = h.hs.rear > 0
            g.baseNoise(at: h.pos + V3(5, 0, 0), kind: .explosion, power: 4)
            let blast = h.hs.rear > 0
            h.hs.rear = 0; h.hs.spookCool = 0; h.hs.rearThrow = false
            g.baseNoise(at: h.pos + V3(18, 4, 0), kind: .cannon)
            let cannon = h.hs.rear > 0
            ride(h, 1.5, push: 0)
            h.hs.spookCool = 0
            let z = Mob(.zombie, at: h.pos + V3(1.6, 0, 0))
            g.mobs.mobs.append(z)
            ride(h, 0.6, push: 0)
            let monster = h.hs.rear > 0
            g.mobs.mobs.removeAll { $0 === z }
            ride(h, 1.5, push: 0)
            h.hs.spookCool = 0
            g.sfx(.gun(0), 1, at: h.pos + V3(4, 1, 0))               // anyone's gun (the sheriff's, a soldier's) via its sound
            let heard = h.hs.rear > 0
            ride(h, 1.5, push: 0)
            h.hs.spookCool = 0
            for k in [6, 8, 10, 11, 12] { g.sfx(.gun(k), 0.5, at: h.pos + V3(5, 1, 0)) }   // ricochet, alarm, radio, charge-up
            check(h.hs.rear == 0, "horse nerves: ricochets (the rider's own rounds), alarms, radios and charge-ups don't spook it")
            check(heard, "horse nerves: a gunshot 4 blocks off (through its sound) makes it rear")
            check(!own && blast && cannon && monster, "horse nerves: rears at a blast \(blast), a cannon \(cannon), a monster beside it \(monster); not at the rider's own gunshot (\(own ? "reared" : "steady"))")
            // Throw odds by level: 40 frights each.
            func throwsOf(_ xp: Float, pat: Bool) -> Int {
                var n = 0
                for _ in 0..<40 {
                    let m = horse(xp: xp); mount(m)
                    m.spook(g)
                    if pat { g.horsePat(m) }
                    ride(m, 1.4, push: 0)
                    if g.riding !== m { n += 1 }
                    g.riding = nil
                }
                return n
            }
            let l1 = throwsOf(0, pat: false), l4 = throwsOf(700, pat: false), calmed = throwsOf(0, pat: true)
            check(l1 >= 6 && l1 <= 32 && l4 == 0 && calmed == 0,
                  "horse frights: level 1 throws \(l1)/40 (45 %), level 4 \(l4)/40, patted while rearing \(calmed)/40")
        }

        // Verifier regressions (2026-10-10): a fright near a cliff; backing toward one; care cooldowns off the saddle;
        // a dead pack animal's cargo drops once.
        do {
            var fellAt: [Int] = []
            for d in stride(from: 5, through: 15, by: 2) {
                let h = horse(xp: 700); mount(h)
                h.pos = V3(lane0.x, lane0.y, Float(z1) + 60)
                var spooked = false, fell = false
                ride(h, 9, push: 1, spurAt: [2, 12], loop: false) { _ in
                    if !spooked && h.pos.z - Float(z1) < Float(d) { h.spook(g); spooked = true }
                    if h.pos.y < Float(Y + 1) - 0.2 { fell = true }
                    return fell
                }
                if fell { fellAt.append(d) }
                g.riding = nil
            }
            // How hard a fright stops a gallop: within the comfort limit.
            let hb = horse(xp: 700); mount(hb)
            ride(hb, 3, push: 1, spurAt: [2, 12], loop: true)
            hb.spook(g)
            let lurch = ride(hb, 0.5, push: 1, loop: true)
            g.riding = nil
            check(lurch <= 12.5, String(format: "horse: a fright brakes a gallop at %.1f b/s^2 (comfort limit 12.5)", lurch))
            check(fellAt.isEmpty, "horse: a fright 5-15 blocks from a cliff at a gallop never carries it over (fell at \(fellAt))")
            let h = horse(); mount(h)
            h.pos = V3(lane0.x, lane0.y, Float(z1) + 1.5); h.yaw = .pi; g.player.yaw = .pi       // facing away from the edge
            var fell = false
            ride(h, 4, push: -1) { _ in fell = h.pos.y < Float(Y + 1) - 0.2; return fell }
            check(!fell, String(format: "horse: backing up stops at a cliff (%.2f blocks short)", h.pos.z - h.halfW - Float(z1)))
            g.riding = nil
            h.hs.brushCool = 120
            for _ in 0..<(121 * 10) { h.update(0.1, game: g) }
            check(h.hs.brushCool == 0, "horse: the grooming cooldown runs out off the saddle too")
            let d = Mob(.donkey, at: lane0); d.owner = true; d.chested = true
            g.packContainer(d)[0] = ItemStack(Items.id("apple"), 5)
            let before = g.drops.items.count
            g.mobDied(d)
            let dropped = g.drops.items.count - before
            check(d.cargo.map { $0.slots.allSatisfy { $0.isEmpty } } ?? true && dropped >= 1,
                  "a dead donkey's pack drops once (\(dropped) stacks dropped, pack emptied)")
        }

        // Others: a camel's pace is unchanged.
        do {
            let c = Mob(.camel, at: lane0); c.owner = true; c.saddled = true; c.yaw = 0
            g.riding = c; g.player.yaw = 0
            ride(c, 2, push: 1)
            check(abs(speed(c) - 3.8) < 0.3, String(format: "camel unchanged: %.1f b/s (3.8)", speed(c)))
            g.riding = nil
        }

        // Through Game.tick with the Touch pad: full push, a stick click, gallop on the second click.
        do {
            let h = horse(); mount(h)
            g.mobs.mobs.append(h)
            let pm = PadManager.shared
            let wasPaused = g.paused, wasMenu = g.menu
            g.paused = false
            var gaits: [Gait] = []
            for i in 0..<120 {
                var p = PadSnapshot()
                p.ly = 1
                if (i >= 10 && i < 12) || (i >= 40 && i < 42) { p.l3 = true }
                pm.simulated = p
                g.tick(Double(dt))
                if i == 30 || i == 110 { gaits.append(h.hs.gait) }
                if h.pos.z < Float(z1) + 30 { h.pos.z += 90 }
            }
            pm.simulated = nil
            g.paused = wasPaused
            if wasMenu == nil && g.menu != nil { g.closeMenu() }
            g.mobs.mobs.removeAll { $0 === h }
            check(gaits == [.canter, .gallop], "horse spurs through Game.tick (pad stick click): \(gaits.map(\.name))")
            // Use with a treat: aimed ahead it is the rider's own use (eat/place), aimed down at the horse it feeds it.
            let held = g.inventory.held
            g.inventory.held = ItemStack(Items.id("apple"), 4)
            g.mobs.mobs.append(h); g.paused = false
            defer { g.mobs.mobs.removeAll { $0 === h }; g.paused = wasPaused }
            func press(_ pitch: Float) -> Float {
                for i in 0..<60 {
                    var p = PadSnapshot()
                    if i == 50 || i == 51 { p.lt = 1 }
                    pm.simulated = p
                    g.player.pitch = pitch
                    if i == 49 { h.stamina = 20 }
                    g.tick(Double(dt))
                }
                pm.simulated = nil
                return h.stamina
            }
            let ahead = press(0), down = press(-1.5)
            g.inventory.held = held
            g.eatProgress = 0
            check(ahead < 30 && down >= 40, String(format: "horse treats only when aimed at the horse: stamina 20 -> %.0f aimed ahead, -> %.0f aimed down at it", ahead, down))
            g.riding = nil
        }
        // Tidy: the strip goes.
        w.deferRemesh = true
        for z in z1...z0 { for x in sx - 3...sx + 3 { w.setBlock(x, Y, z, AIR) } }
        w.deferRemesh = false
    }
}
