import Foundation
import simd

// Horse checks for the gap pass (docs/status/cloud-gap-pass.md, area R; docs/status/horses.md "Gap pass"), run at the
// end of HorseTests on its sky strip:
//   breeds   each breed rolls inside its speed, jump and coat ranges; stamina and nerve differ by breed; old horses
//            get a breed from their speed
//   names    a new horse of yours is named; every horse you have ridden keeps its own bond
//   taming   sitting still and patting between bucks tames a wild horse; fighting the bucks gets you thrown
//   fear     a wolf nearby frightens a horse below bond level 3, not one at level 3
//   unlocks  a level-3 rear on command (no throw), a level-4 sliding stop shorter than level 1's, tighter turns
//   injury   a horse of yours that would die goes down; a Saddle Salve brings it back; left 5 minutes, it dies
//   stable   buy, stable, take out (here free, from another town for a fee), sell, rename; kept horses survive a save
//   calling  a stabled horse says where it is; a called horse finds its way round a wall; a horse left alone stays near
//   comfort  the ride vignette darkens more in a turn than a straight run; Steady Saddle eases a jump's lift; the
//            saddlebags open from a hand at the flank only
//   hooves   hoof sound classes by the ground; every class synthesizes a sound
extension HorseTests {
    static func gap(_ g: Game, _ check: (Bool, String) -> Void, lane0: V3, stripEnd: Int,
                    horse: (Int, Float) -> Mob, mount: (Mob) -> Void, ride: (Mob, Float, Float, Set<Int>) -> Void) {
        let dt: Float = 1.0 / 72
        let savedLaw = TownLaw.state, savedMoney = g.money, savedMobs = g.mobs.mobs, savedSaddle = g.steadySaddle
        defer {
            TownLaw.state = savedLaw; g.money = savedMoney; g.mobs.mobs = savedMobs; g.steadySaddle = savedSaddle
            g.riding = nil; g.horseCall = 0
            if g.menu != nil { g.closeMenu() }
        }
        func speed(_ h: Mob) -> Float { simd_length(V2(h.vel.x, h.vel.z)) }

        // Breeds.
        do {
            var ok = true
            for b in HorseBreed.allCases {
                for _ in 0..<20 {
                    let m = Mob(.horse, at: lane0)
                    HorseLife.roll(m, breed: b)
                    let bits = (m.variant >> 4) & 15, jump = (m.variant >> 8) & 15
                    if m.horseBreed != b || !b.speedBits.contains(bits) || !b.jump.contains(jump) || !b.coats.contains(m.variant % 5) { ok = false }
                }
            }
            check(ok, "horse gap: each of the \(HorseBreed.allCases.count) breeds rolls inside its speed, jump and coat ranges")
            let fast = HorseBreed.allCases.max { $0.speedBits.upperBound < $1.speedBits.upperBound }!
            let hardy = HorseBreed.allCases.max { $0.stamina < $1.stamina }!
            let brave = HorseBreed.allCases.max { $0.courage < $1.courage }!
            check(fast == .sandrunner && hardy == .draft && brave == .draft && HorseBreed.sandrunner.courage < HorseBreed.saddlebred.courage,
                  "horse gap: breeds differ (fastest \(fast.name), most stamina \(hardy.name), bravest \(brave.name), the sandrunner skittish)")
            let d = Mob(.horse, at: lane0); HorseLife.roll(d, breed: .draft); d.owner = true
            let s = Mob(.horse, at: lane0); HorseLife.roll(s, breed: .saddlebred); s.owner = true
            check(d.staminaMax > s.staminaMax, String(format: "horse gap: a draft horse has more wind than a saddlebred (%.0f vs %.0f)", d.staminaMax, s.staminaMax))
            let old = Mob(.horse, at: lane0); old.variant = 1 | (14 << 4) | (8 << 8); old.breed = -1   // an old save: no breed
            check(old.horseBreed == .sandrunner || old.horseBreed == .mustang, "horse gap: an old horse gets a breed from its speed (\(old.horseBreed.name))")
            var ex: [String: Float] = [:]
            d.saveExtra(&ex)
            let back = Mob(.horse, at: lane0); back.loadExtra(ex)
            check(back.horseBreed == .draft, "horse gap: the breed is saved (\(back.horseBreed.name))")
        }

        // Names and bonds: a first horse gets a name; a second one is current, the first keeps its bond.
        do {
            let a = horse(15, 0), b = horse(15, 0)
            a.customName = nil; b.customName = nil
            g.horseBond = 0
            mount(a); ride(a, 0.1, 0, [])
            let bondA = a.bond, nameA = a.customName
            g.riding = nil
            mount(b); ride(b, 0.1, 0, [])
            g.riding = nil
            check(nameA != nil && b.customName != nil && bondA != 0 && a.bond == bondA && b.bond != 0 && g.horseBond == b.bond && a.yours,
                  "horse gap: new horses are named (\(nameA ?? "-"), \(b.customName ?? "-")); the first keeps its bond when you ride another")
        }

        // Taming: sit still and pat it as it settles; fight it and you're thrown.
        do {
            let wild = Mob(.horse, at: lane0); HorseLife.roll(wild, breed: .mustang); wild.yaw = 0; wild.temper = 0
            g.mobs.mobs = [wild]
            mount(wild)
            var t: Float = 0
            while t < 90 && !wild.tamed && g.riding === wild {
                g.rideInput = MoveInput()
                wild.update(dt, game: g)
                if !wild.hs.bucking && Int(t * 72) % 72 == 0 { wild.tamePat(g) }
                wild.hs.patCool -= dt
                t += dt
            }
            check(wild.tamed && g.riding === wild, String(format: "horse gap: sitting still and patting between bucks tames a wild horse (%.0f s)", t))
            g.riding = nil
            let wild2 = Mob(.horse, at: lane0); HorseLife.roll(wild2, breed: .mustang); wild2.yaw = 0; wild2.temper = 0
            g.mobs.mobs = [wild2]
            mount(wild2)
            t = 0
            while t < 30 && g.riding === wild2 {
                g.rideInput = MoveInput(forward: 1)
                wild2.update(dt, game: g)
                t += dt
            }
            check(g.riding !== wild2 && !wild2.tamed, String(format: "horse gap: fighting the bucks gets you thrown (%.1f s)", t))
            g.riding = nil
            let wild3 = Mob(.horse, at: lane0); HorseLife.roll(wild3, breed: .mustang); wild3.yaw = 0; wild3.temper = 0
            g.mobs.mobs = [wild3]
            mount(wild3)
            t = 0
            while t < 60 && g.riding === wild3 && !wild3.tamed { g.rideInput = MoveInput(); wild3.update(dt, game: g); t += dt }
            check(g.riding !== wild3 && !wild3.tamed, String(format: "horse gap: sitting still without patting isn't enough: thrown after %.0f s (it takes timed pats)", t))
            g.riding = nil
        }

        // Fear: a wolf nearby frightens a young bond, not a level-3 one.
        do {
            func frightened(_ xp: Float) -> Bool {
                let h = horse(15, xp); mount(h)
                let wolf = Mob(.wolf, at: h.pos + V3(4, 0, 0))
                g.mobs.mobs = [h, wolf]
                var reared = false
                for _ in 0..<72 { g.rideInput = MoveInput(); h.update(dt, game: g); if h.hs.rear > 0 { reared = true }; wolf.pos = h.pos + V3(4, 0, 0); if g.riding !== h { reared = true; break } }
                g.riding = nil
                return reared
            }
            let young = frightened(0), steady = frightened(HorseFeel.levelXP[2])
            check(young && !steady, "horse gap: a wolf 4 blocks off frightens a level-1 horse (\(young)), not a level-3 one (\(steady))")
        }

        // Bond unlocks: a level-3 rear on command, a level-4 sliding stop, tighter turns.
        do {
            let h3 = horse(15, HorseFeel.levelXP[2]); mount(h3)
            g.mobs.mobs = [h3]
            ride(h3, 0.3, 0, [5])
            check(h3.hs.tricks == 1 && g.riding === h3, "horse gap: at bond level 3 a spur standing still rears on command, rider kept (\(h3.hs.tricks))")
            g.riding = nil
            func stopDistance(_ xp: Float) -> Float {
                let h = horse(15, xp); mount(h)
                g.mobs.mobs = [h]
                ride(h, 3, 1, [10, 40])
                let z0 = h.pos.z
                var n = 0
                while speed(h) > 0.2 && n < 72 * 6 { g.rideInput = MoveInput(); h.update(dt, game: g); n += 1 }
                g.riding = nil
                return abs(z0 - h.pos.z)
            }
            let s1 = stopDistance(0), s4 = stopDistance(HorseFeel.levelXP[3])
            check(s4 < s1 * 0.75, String(format: "horse gap: a level-4 horse stops in %.1f blocks, a level-1 in %.1f (a sliding stop)", s4, s1))
            func turned(_ xp: Float) -> Float {
                let h = horse(15, xp); mount(h)
                g.mobs.mobs = [h]
                let y0 = h.yaw
                for _ in 0..<36 { var mi = MoveInput(forward: 0.3); mi.strafe = 1; g.rideInput = mi; g.player.moveYaw = nil; g.player.yaw = h.yaw + 1.5; h.update(dt, game: g) }
                g.riding = nil
                return abs(h.yaw - y0)
            }
            let t1 = turned(0), t4 = turned(HorseFeel.levelXP[3])
            check(t4 > t1 * 1.2, String(format: "horse gap: a level-4 horse turns tighter (%.2f rad vs %.2f in half a second)", t4, t1))
        }

        // Injury: down, not dead; the reviver; left too long, gone.
        do {
            let h = horse(15, 0); h.bond = 12345; g.horseBond = 12345
            g.mobs.mobs = [h]
            h.health = 0
            g.mobs.update(0.05, game: g)
            let down = h.downed > 0 && h.health > 0 && g.mobs.mobs.contains { $0 === h }
            let held = g.inventory.held
            g.inventory.held = ItemStack(Items.id(HorseLife.reviverKey), 1)
            let used = g.useReviver(on: h)
            check(down && used && h.downed == 0 && h.health > 1 && g.inventory.held.isEmpty,
                  "horse gap: a horse of yours that would die goes down, and a Saddle Salve brings it back (\(h.health) hp)")
            // Down, it takes no more harm from anything (instant damage, a crushing hull) and still falls to the ground.
            h.health = 0
            g.mobs.update(0.05, game: g)
            h.health = -6
            let y0 = h.pos.y
            h.pos.y += 3
            for _ in 0..<72 { g.mobs.update(1.0 / 72, game: g) }
            check(h.downed > 0 && h.health > 0 && g.mobs.mobs.contains { $0 === h } && abs(h.pos.y - y0) < 0.1,
                  String(format: "horse gap: a downed horse can't be finished off and falls to the ground (%.2f from the strip)", h.pos.y - y0))
            for _ in 0..<Int(HorseLife.downTime / 5) + 2 { h.update(5, game: g) }
            g.mobs.update(0.05, game: g)
            check(h.health <= 0 && h.downed == 0 && !g.mobs.mobs.contains { $0 === h } && g.horseBond == 0,
                  "horse gap: a horse left down for \(Int(HorseLife.downTime)) s dies for good")
            g.inventory.held = held
            let wild = Mob(.horse, at: lane0)
            g.mobs.mobs = [wild]; wild.health = 0
            g.mobs.update(0.05, game: g)
            check(wild.downed == 0 && !g.mobs.mobs.contains { $0 === wild }, "horse gap: a wild horse just dies (no reviving someone else's)")
        }

        // The stable.
        do {
            TownLaw.reset()
            g.money = 10_000
            let keeper = TownTests.townPerson(g, lane0 + V3(0, 0, -6), tag: "shop_stable")
            keeper.villager?.town = "Cedar Ford"
            g.mobs.mobs = [keeper]
            g.player.pos = keeper.pos + V3(1, 0, 0)
            g.horseBond = 0
            let menu = StableMenu(game: g, keeper: keeper)
            g.openMenu(menu)
            let rows0 = menu.rows
            let buyRow = rows0.firstIndex { $0.name == "Buy a \(HorseBreed.draft.name)" }
            if let i = buyRow { menu.pressed(i) }
            let bought = g.mobs.mobs.first { $0.kind == .horse }
            check(buyRow != nil && bought?.horseBreed == .draft && bought?.yours == true && bought?.saddled == true && g.horseBond == bought?.bond
                  && g.money == 10_000 - HorseBreed.draft.price,
                  "horse gap: the stable sells a \(HorseBreed.draft.name), saddled and yours, for \(Money.format(HorseBreed.draft.price))")
            guard let h = bought else { return }
            h.hs.bondXP = HorseFeel.levelXP[1]
            let name0 = h.customName
            if let i = menu.rows.firstIndex(where: { $0.name.hasPrefix("Rename") }) { menu.pressed(i) }
            check(h.customName != nil && h.customName != name0 && h.customName == HorseLife.nextName(name0),
                  "horse gap: rename gives the next name from the list (\(name0 ?? "-") -> \(h.customName ?? "-"))")
            if let i = menu.rows.firstIndex(where: { $0.name.hasPrefix("Stable ") }) { menu.pressed(i) }
            check(Stable.kept.count == 1 && !g.mobs.mobs.contains { $0 === h }, "horse gap: stabling a horse keeps it in a stall (it leaves the world)")
            // Kept horses survive a save.
            let data = try? JSONEncoder().encode(TownLaw.state)
            let back = data.flatMap { try? JSONDecoder().decode(TownLaw.Saved.self, from: $0) }
            check(back?.stabled?.count == 1 && back?.stabled?.first?.rec.name == h.customName, "horse gap: stabled horses are saved")
            // A call while it's stabled says where it is.
            var toast = ""
            let wasToast = g.onToast
            g.onToast = { toast = $0 }
            _ = g.callHorse()
            g.onToast = wasToast
            check(toast.contains("stable at Cedar Ford"), "horse gap: calling a stabled horse says where it is (\(toast))")
            // Take it out here: free, the same horse (name, breed, bond).
            let m0 = g.money
            if let i = menu.rows.firstIndex(where: { $0.name.hasPrefix("Take out") }) { menu.pressed(i) }
            let out = g.mobs.mobs.first { $0.kind == .horse }
            check(out?.customName == h.customName && out?.horseBreed == .draft && out?.bond == h.bond && out?.bondLevel == 2 && g.money == m0 && Stable.kept.isEmpty
                  && g.horseBond == h.bond, "horse gap: taking it out here is free and it's the same horse (name, breed, bond level 2)")
            // Kept in another town: brought over for a fee.
            if let o = out { _ = Stable.store(g, o, town: "Dry Falls") }
            let m1 = g.money
            if let i = menu.rows.firstIndex(where: { $0.name.hasPrefix("Take out") }) { menu.pressed(i) }
            check(g.money == m1 - Stable.fetchFee && Stable.kept.isEmpty, "horse gap: a horse kept in another town is brought over for \(Money.format(Stable.fetchFee))")
            // Sell it.
            let m2 = g.money
            let ours = g.mobs.mobs.first { $0.kind == .horse }
            let value = ours.map { Stable.sellValue($0) } ?? 0
            if let i = menu.rows.firstIndex(where: { $0.name.hasPrefix("Sell") }) { menu.pressed(i) }
            check(value > 0 && value < HorseBreed.draft.price && g.money == m2 + value && !g.mobs.mobs.contains { $0.kind == .horse } && g.horseBond == 0,
                  "horse gap: selling a horse pays \(Money.format(value)) (less than it cost)")
            let second = horse(15, 0); second.bond = 99; g.mobs.mobs.append(second)
            let again = Stable.sell(g, second, town: "Cedar Ford")
            check(!again.1 && g.mobs.mobs.contains { $0 === second }, "horse gap: a stable buys one horse a day (no taming wild horses for a living)")
            g.mobs.mobs.removeAll { $0 === second }
            // A horse kept from before breeds: its breed worked out from its speed.
            var oldRec = second.record                              // (top speed 15: only the Sandrunner's range)
            oldRec.extra?["breed"] = nil
            let oldKept = StabledHorse(rec: oldRec, town: "Cedar Ford", day: 0)
            check(Stable.breed(oldKept) == .sandrunner, "horse gap: a horse stabled before breeds shows the breed its speed fits (\(Stable.breed(oldKept).name))")
            // Six stalls.
            for _ in 0..<Stable.maxKept { let x = horse(15, 0); x.bond = Float(Rand.int(in: 1...1000)); g.mobs.mobs.append(x); _ = Stable.store(g, x, town: "Cedar Ford") }
            let extra = horse(15, 0); extra.bond = 7
            g.mobs.mobs.append(extra)
            let full = Stable.store(g, extra, town: "Cedar Ford")
            check(!full.1 && Stable.kept.count == Stable.maxKept, "horse gap: the stable keeps \(Stable.maxKept) horses at most")
            let panel = menu.rows.count
            check(panel >= Stable.maxKept + HorseBreed.allCases.count, "horse gap: the stable lists stalls and breeds (\(panel) rows)")
            g.closeMenu()
            // The stablehand's counter has a Horses button (in shop hours: earlier checks tick the clock, and at night
            // the keeper only says the stable is shut).
            g.mobs.mobs = [keeper]
            let wasTime = g.time
            g.time = g.time - g.time.truncatingRemainder(dividingBy: DAY_LENGTH) + 0.25 * DAY_LENGTH
            _ = g.talkToTownsperson(keeper)
            g.time = wasTime
            let sm = g.menu as? ShopMenu
            check(sm?.extraTitle == "Horses", "horse gap: the stablehand's counter has a Horses button (\(sm?.extraTitle ?? "none"))")
            if g.menu != nil { g.closeMenu() }
        }

        // Calling round a wall; left alone, it stays near.
        do {
            let w = g.world
            let wallZ = Int(floor(lane0.z)) - 20, y = Int(floor(lane0.y)), x0 = Int(floor(lane0.x))
            for x in (x0 - 3)...x0 { for dy in 0...3 { w.setBlock(x, y + dy, wallZ, Blocks.id("stone")) } }
            defer { for x in (x0 - 3)...(x0 + 3) { for dy in 0...3 { w.setBlock(x, y + dy, wallZ, AIR) } } }
            let h = horse(15, 0); h.bond = 4242; g.horseBond = 4242
            h.pos = V3(lane0.x, lane0.y, Float(wallZ) - 6)            // beyond the wall
            g.mobs.mobs = [h]
            g.riding = nil
            g.player.pos = V3(lane0.x, lane0.y, Float(wallZ) + 8)
            _ = g.callHorse()
            let round0 = HorseLife.broughtRound
            var t: Float = 0
            // (through the mob list's update: it hands out the path finder's per-tick budget)
            while t < 25 && simd_length(h.pos - g.player.pos) > 3 { g.mobs.update(0.05, game: g); g.horseCall = max(g.horseCall, 1); t += 0.05 }
            check(simd_length(h.pos - g.player.pos) <= 3 && HorseLife.broughtRound == round0, String(format: "horse gap: a called horse finds its way round a wall (%.1f s, %.1f blocks off; at %.1f %.1f %.1f from %.1f %.1f %.1f; brought round %d)", t, simd_length(h.pos - g.player.pos), h.pos.x, h.pos.y, h.pos.z, lane0.x, lane0.y, Float(wallZ) - 6, HorseLife.broughtRound - round0))
            // A gap it can't get through (the wall closed): after 6 s stuck it is brought round to you, on your level
            // (the strip is high in the air: never onto the ground far below).
            for dy in 0...3 { for x in (x0 + 1)...(x0 + 3) { w.setBlock(x, y + dy, wallZ, Blocks.id("stone")) } }
            h.pos = V3(lane0.x, lane0.y, Float(wallZ) - 6); h.vel = .zero
            g.player.yaw = .pi / 2                                         // facing along x: "behind" is off the strip
            _ = g.callHorse()
            let round1 = HorseLife.broughtRound
            t = 0
            while t < 15 && simd_length(h.pos - g.player.pos) > 3 { g.mobs.update(0.05, game: g); g.horseCall = max(g.horseCall, 1); t += 0.05 }
            check(HorseLife.broughtRound > round1 && abs(h.pos.y - g.player.pos.y) < 1.5 && simd_length(h.pos - g.player.pos) < 6,
                  String(format: "horse gap: a called horse that can't get through is brought round to your level after 6 s (%.1f s, %.1f blocks off, %.1f below)", t, simd_length(h.pos - g.player.pos), g.player.pos.y - h.pos.y))
            g.player.yaw = 0
            g.horseCall = 0
            // Ridden somewhere else after the call (it waited where it arrived), then left: it waits where you got off.
            mount(h)
            ride(h, 1.5, 0.6, [])
            g.riding = nil
            let left = h.pos
            g.player.pos = left + V3(0, 0, 30)
            var far: Float = 0
            for _ in 0..<600 { g.mobs.update(0.05, game: g); far = max(far, simd_length(V2(h.pos.x - left.x, h.pos.z - left.z))) }
            check(far < 7, String(format: "horse gap: a horse left alone grazes near where you got off, not where it waited before (strayed %.1f blocks in 30 s)", far))
            // A wolf comes by a horse waiting at bond level 1: it bolts.
            let bolted0 = HorseLife.bolted
            let wolf = Mob(.wolf, at: h.pos + V3(3, 0, 0))
            g.mobs.mobs = [h, wolf]
            for _ in 0..<10 { g.mobs.update(0.05, game: g); wolf.pos = h.pos + V3(3, 0, 0) }
            check(HorseLife.bolted > bolted0 && h.panic > 0, "horse gap: a horse left waiting bolts from a wolf (until bond level 3)")
            g.mobs.mobs = [h]
        }

        // Comfort: the ride vignette, Steady Saddle, the saddlebags.
        do {
            let straight = RideComfort.vignette(speed: 10, turnRate: 0, accel: 0)
            let turning = RideComfort.vignette(speed: 10, turnRate: 2.5, accel: 0)
            let pulling = RideComfort.vignette(speed: 4, turnRate: 0, accel: 12)
            check(turning > straight + 0.3 && pulling > straight + 0.3 && straight < 0.4,
                  String(format: "horse gap: the ride vignette darkens in a turn (%.2f) and pulling up (%.2f) more than a straight run (%.2f)", turning, pulling, straight))
            func lift(_ steady: Bool) -> Float {
                let h = horse(15, 0); mount(h)
                g.steadySaddle = steady
                g.player.steadyY = nil
                g.updateViewStep(dt)
                let eye0 = h.pos.y + g.player.viewDY
                h.pos.y += 1.2                                          // a jump's lift in one tick
                g.updateViewStep(dt)
                let eye1 = h.pos.y + g.player.viewDY
                h.pos.y -= 1.2
                g.riding = nil
                return eye1 - eye0
            }
            let off = lift(false), on = lift(true)
            // A long climb at 3 blocks a second: the view keeps up (no head trailing into the hillside).
            do {
                let h = horse(15, 0); mount(h)
                g.steadySaddle = true; g.player.steadyY = nil
                g.updateViewStep(dt)
                for _ in 0..<144 { h.pos.y += 3 * dt; g.updateViewStep(dt) }
                let lag = -g.player.viewDY
                h.pos.y -= 6
                g.riding = nil
                check(abs(lag) < 0.15, String(format: "horse gap: Steady Saddle follows a long climb without lagging (%.2f blocks behind after 2 s at 3 b/s)", lag))
            }
            check(on < off * 0.3, String(format: "horse gap: Steady Saddle eases a 1.2-block jump (the view lifts %.2f, %.2f without)", on, off))
            let h = horse(15, 0); h.yaw = 0
            let fwd = V3(-sinf(h.yaw), 0, -cosf(h.yaw)), right = V3(-fwd.z, 0, fwd.x)
            let bag = h.pos + right * 0.55 - fwd * 0.4 + V3(0, 0.9, 0)
            let bagL = h.pos - right * 0.55 - fwd * 0.4 + V3(0, 0.9, 0)
            let ahead = h.pos + right * 0.55 + fwd * 0.9 + V3(0, 0.9, 0)
            let lap = h.pos - fwd * 0.2 + V3(0, 1.5, 0)
            check(HorseLife.reachesSaddlebag(h, hand: bag) && HorseLife.reachesSaddlebag(h, hand: bagL) && !HorseLife.reachesSaddlebag(h, hand: ahead)
                  && !HorseLife.reachesSaddlebag(h, hand: lap), "horse gap: the saddlebags open from a hand at either flank behind the saddle, not ahead or in the lap")
        }

        // Hooves.
        do {
            let ids = ["stone", "oak_planks", "grass_block", "sand", "snow_block", "water", "sandstone"].map { Blocks.id($0) }
            let classes = ids.map { HorseLife.surface($0) }
            check(classes == [0, 1, 2, 3, 4, 5, 0], "horse gap: hoof sounds by the ground (stone, wood, earth, sand, snow, water, sandstone: \(classes))")
            var synth = Synth(seed: 7)
            let loud = (0..<6).map { s -> Float in HorseLife.hoof(&synth, surface: s, p: 1).reduce(0) { max($0, abs($1)) } }
            check(loud.allSatisfy { $0 > 0.01 }, "horse gap: every hoof sound synthesizes (\(loud.map { String(format: "%.2f", $0) }.joined(separator: " ")))")
        }
    }
}
