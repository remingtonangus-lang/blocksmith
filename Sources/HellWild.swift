import Foundation
import simd

// P506 (Remington, Nov 1 08:07:22 in the Cinder Plains: "I think we still need some more mob types"). Hell had its
// order, its imps, its brutes and its fliers, each land's own two of them (HellBiomeMobs), but nothing that simply
// lived there. Three creatures of its own, each living the way its kind does (the frontier's predator and herd ways,
// Predators.swift and HerdGame.swift, made for fire):
//   Cinderhorn  the Cinder Plains and the Ash Dunes, in herds of three to five: a heavy, low grazer with a basalt hide
//               cracked over a glow and two horns swept back. It hardly minds you (7 blocks), but hurt one and the herd
//               stampedes while its bulls charge, horns hot enough to set you burning. Meat and hide.
//   Ember Asp   the Charwood Thicket and the Ghostglass Spires: an ember-red snake, banded black, that lies coiled. Come
//               within 5 blocks and it rears, hood spread and hissing; inside 1.8 it strikes and the bite burns.
//   Slagmaw     wherever the lava comes to the shore: a broad, flat lizard crusted like cooling slag, lying awash in the
//               lava. Within 9 blocks it surges out at you and bites hard, then slides back.
// They spawn with hell's own (trySpawnEmberdeep), by land, with caps of their own.
extension MobKind {
    var hellWild: Bool { self == .cinderhorn || self == .emberAsp || self == .slagmaw }
}

enum HellWild {
    static var spawned = [0, 0, 0]                      // (tests) herds, asps, slagmaws
    static let caps: [MobKind: Int] = [.cinderhorn: 8, .emberAsp: 3, .slagmaw: 2]

    static func lavaNear(_ w: World, _ p: V3, reach: Int = 4) -> V3? {
        let x = Int(floor(p.x)), y = Int(floor(p.y)), z = Int(floor(p.z))
        for dz in stride(from: -reach, through: reach, by: 2) { for dx in stride(from: -reach, through: reach, by: 2) {
            for dy in -2...0 where LAVA_FLOW.contains(w.builtBlock(x + dx, y + dy, z + dz)) {
                return V3(Float(x + dx) + 0.5, Float(y + dy + 1), Float(z + dz) + 0.5)
            }
        } }
        return nil
    }

    // One spawn attempt at a hidden standing spot (trySpawnEmberdeep): true when it put something there.
    static func spawn(_ g: Game, at p: V3, land: Biome) -> Bool {
        let w = g.world
        func room(_ k: MobKind, _ n: Int) -> Bool {
            var c = 0
            for m in g.mobs.mobs where m.kind == k && simd_length_squared(m.pos - p) < 128 * 128 { c += 1 }
            return c + n <= caps[k] ?? 0
        }
        func put(_ k: MobKind, _ q: V3) -> Mob? {
            guard let s = MobManager.groundSpot(w, near: q) else { return nil }
            let m = Mob(k, at: s)
            g.mobs.mobs.append(m)
            return m
        }
        if lavaNear(w, p) != nil, Rand.float(in: 0..<1) < 0.5, room(.slagmaw, 1) {
            guard put(.slagmaw, p) != nil else { return false }
            spawned[2] += 1
            return true
        }
        guard Rand.float(in: 0..<1) < 0.3 else { return false }
        switch land {
        case .netherWastes, .soulSandValley:
            let n = Rand.int(in: 3...5)
            guard room(.cinderhorn, n) else { return false }
            var any = false
            for i in 0..<n {
                let q = p + V3(Float(i % 3) - 1, 0, Float(i / 3) - 0.5) * 2.4
                if let m = put(.cinderhorn, q) { m.variant = i == 0 ? 1 : 2; any = true }        // the first a bull
            }
            if any { spawned[0] += 1 }
            return any
        case .crimsonForest, .basaltDeltas:
            guard room(.emberAsp, 1), put(.emberAsp, p) != nil else { return false }
            spawned[1] += 1
            return true
        default:
            return false
        }
    }
}

// Models (1/16 block, facing -z). Glowing parts are pattern 9.
func hellWildParts(_ m: Mob, swing: Float) -> [Part] {
    func leg(_ x: Float, _ z: Float, _ w: Float, _ h: Float, _ ph: Float, _ c: V3) -> Part {
        Part(mn: V3(x - w / 2, 0, z - w / 2), mx: V3(x + w / 2, h, z + w / 2), pivot: V3(x, h, z), rotX: swing * ph, color: c)
    }
    let hot = V3(2.4, 0.8, 0.14), bone = V3(0.78, 0.72, 0.6)
    switch m.kind {
    case .cinderhorn:
        let hide = V3(0.13, 0.12, 0.12), ash = V3(0.36, 0.33, 0.31), dark = V3(0.06, 0.05, 0.05)
        let run: Float = m.fleeTime > 0 || m.phase == 1 ? 1.4 : 1
        let head: Float = m.phase == 1 ? -2.5 : 0                                       // head down in a charge
        let big: Float = m.bull ? 1 : 0.88
        var p: [Part] = [
            Part(mn: V3(-6 * big, 9, -10 * big), mx: V3(6 * big, 21 * big, 11 * big), color: hide, pattern: 12),   // the body
            box(-5.5 * big, 8.5, -8, 11 * big, 1, 17, ash),                              // the belly
            box(-4, 7 + head, -18, 8, 8, 8, hide, 12),                                   // the low, broad head
            box(-3, 6 + head, -20, 6, 4, 2.5, ash),                                      // the muzzle
            box(-2.6, 11 + head, -18.2, 1.4, 1, 0.3, hot).withPattern(9),               // the eyes
            box(1.2, 11 + head, -18.2, 1.4, 1, 0.3, hot).withPattern(9),
            box(-0.5, 9, 11, 1, 6, 1, dark),                                             // the tail
        ]
        // The cracks down each flank and along the spine, glowing.
        for side: Float in [-1, 1] {
            let x = side * 6 * big - (side > 0 ? 0.3 : 0)
            p.append(box(x, 13, -7, 0.3, 1, 7, hot).withPattern(9))
            p.append(box(x, 15, 1, 0.3, 1, 6, hot).withPattern(9))
            p.append(box(x, 11, 5, 0.3, 4, 0.8, hot).withPattern(9))
        }
        p.append(box(-0.5, 21 * big, -8, 1, 0.3, 16, hot).withPattern(9))
        // The horns: out from the head, then swept back and up (a bull's longer).
        let hl: Float = m.bull ? 5 : 3
        for side: Float in [-1, 1] {
            let x0 = side < 0 ? -4 - hl : 4
            p.append(box(x0, 13 + head, -16, hl, 1.6, 1.6, bone))
            p.append(box(side < 0 ? -4 - hl : 2.4 + hl, 13.5 + head, -15, 1.6, 1.6, hl, bone))
            p.append(box(side < 0 ? -4 - hl : 2.4 + hl, 15 + head, -15 + hl - 1.6, 1.6, 2.4, 1.6, bone))
        }
        p += [leg(-4, -7, 3.2, 9, run, hide), leg(4, -7, 3.2, 9, -run, hide), leg(-4, 8, 3, 9, -run, hide), leg(4, 8, 3, 9, run, hide)]
        return p
    case .emberAsp:
        let red = V3(0.62, 0.14, 0.06), black = V3(0.07, 0.05, 0.05)
        var p: [Part] = []
        for i in 0..<10 {
            let a = Float(i) * 0.68 + m.walkPhase * 0.3
            let r: Float = 5.4 - Float(i) * 0.3
            p.append(box(cosf(a) * r - 1.3, 0, sinf(a) * r - 1.3, 2.6, 2.2, 2.6, i % 3 == 2 ? black : red, 12))
            if i % 3 != 2 { p.append(box(cosf(a) * r - 0.4, 2.2, sinf(a) * r - 0.4, 0.8, 0.2, 0.8, hot).withPattern(9)) }   // a glowing scale
        }
        let rear: Float = m.aggro ? 5 : 2
        p.append(box(-1.2, 2, -4, 2.4, rear + 1, 2.4, red))                            // the raised neck
        if m.aggro {
            p.append(box(-3, 1.5 + rear, -4.6, 6, 3.5, 0.8, red))                       // the hood spread
            p.append(box(-2.2, 2.2 + rear, -4.7, 4.4, 2, 0.2, hot * 0.7).withPattern(9))
        }
        p.append(box(-1.6, 2 + rear, -7, 3.2, 2, 4, black, 12))                          // the head
        p.append(box(-1.1, 3.2 + rear, -7.2, 0.6, 0.6, 0.3, hot).withPattern(9))
        p.append(box(0.5, 3.2 + rear, -7.2, 0.6, 0.6, 0.3, hot).withPattern(9))
        return p
    default:
        let crust = V3(0.17, 0.14, 0.13), seam = V3(2.2, 0.62, 0.1), belly = V3(0.32, 0.22, 0.16)
        let jaw: Float = m.phase == 1 ? 0.5 : 0.06
        var p: [Part] = [
            Part(mn: V3(-7, 3, -10), mx: V3(7, 8, 13), color: crust, pattern: 12),
            box(-6.5, 2.5, -9, 13, 0.8, 21, belly),
            box(-4.5, 3.5, -21, 9, 4, 11, crust, 12),                                    // the snout
            Part(mn: V3(-4.2, 2.5, -21), mx: V3(4.2, 3.8, -10), pivot: V3(0, 3.5, -10), rotX: -jaw, color: belly),   // the lower jaw
            box(-3.8, 3.4, -20.5, 7.6, 0.4, 9, seam).withPattern(9),                     // the maw's glow
            box(-3.6, 7.5, -13, 2, 1.5, 2, crust), box(1.6, 7.5, -13, 2, 1.5, 2, crust),
            box(-3.3, 8.2, -12.6, 1, 0.8, 0.3, seam).withPattern(9), box(2.3, 8.2, -12.6, 1, 0.8, 0.3, seam).withPattern(9),
            Part(mn: V3(-4.5, 3, 13), mx: V3(4.5, 7, 23), pivot: V3(0, 5, 13), rotX: 0, color: crust, pattern: 12),
            Part(mn: V3(-2.5, 3, 22), mx: V3(2.5, 5.5, 33), pivot: V3(0, 4, 22), rotX: sinf(m.walkPhase) * 0.1, color: crust, pattern: 12),
        ]
        // Crust plates down its back with the lava showing between them.
        for k in 0..<6 {
            let z = -9 + Float(k) * 3.6
            p.append(box(-5, 8, z, 10, 1, 2.6, crust * 1.3))
            p.append(box(-4.5, 8, z + 2.6, 9, 0.6, 1, seam).withPattern(9))
        }
        p += [leg(-7.5, -6, 3, 3.5, 1, crust), leg(7.5, -6, 3, 3.5, -1, crust), leg(-7.5, 9, 3, 3.5, -1, crust), leg(7.5, 9, 3, 3.5, 1, crust)]
        return p
    }
}

// questcheck suite (after the hell mobs): the three on an arena of their own, with a lava pool for the Slagmaw.
enum HellWildTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let w = g.world
        let kinds: [MobKind] = [.cinderhorn, .emberAsp, .slagmaw]
        let wasPos = g.player.pos, wasSurvival = g.survival, wasHealth = g.health, wasDiff = g.difficulty
        var box: (x: Int, z: Int, y: Int)?
        defer {
            g.mobs.mobs.removeAll { $0.kind.hellWild }
            if let b = box {
                w.deferRemesh = true
                for z in (b.z - 13)...(b.z + 13) { for x in (b.x - 13)...(b.x + 13) { for y in (b.y - 1)...(b.y + 6) where !w.isAir(x, y, z) { w.setBlock(x, y, z, AIR) } } }
                w.deferRemesh = false
                w.remeshArea(x0: b.x - 14, z0: b.z - 14, x1: b.x + 14, z1: b.z + 14, y0: b.y - 1, y1: b.y + 7)
            }
            g.player.pos = wasPos; g.player.vel = .zero; g.survival = wasSurvival; g.health = wasHealth; g.difficulty = wasDiff
            g.onFire = 0
        }
        // The roster: keys, models in both poses, a voice, fire-proof, saved and loaded.
        var bad: [String] = []
        for k in kinds {
            let m = Mob(k, at: V3(0, 100, 0))
            if MobKind.named(k.key) != k || k.spec.name.isEmpty { bad.append("\(k.key): registry") }
            for ph in [0, 1] {
                m.phase = ph; m.aggro = ph == 1; m.variant = ph + 1
                let n = hellWildParts(m, swing: 0.3).count
                if n == 0 || n > 70 { bad.append("\(k.key): \(n) parts") }
            }
            if MobVoice.profile(k).family == .silent { bad.append("\(k.key): silent") }
            if !k.spec.fireImmune { bad.append("\(k.key): burns") }
            m.phase = 0; m.health = 5
            let back = (try? JSONEncoder().encode(m.record)).flatMap { try? JSONDecoder().decode(MobRecord.self, from: $0) }.flatMap { Mob.from($0) }
            if back?.kind != k || back?.health != 5 { bad.append("\(k.key): save") }
        }
        check(bad.isEmpty, "hell wildlife: \(kinds.map { $0.spec.name }.joined(separator: ", ")): registered, drawn, voiced, fire-proof, saved\(bad.isEmpty ? "" : " -- \(bad.prefix(4))")")

        // An arena: stone 25 x 25 with a 5 x 5 lava pool on its east side.
        let sx = Int(floor(g.player.pos.x)) - 176, sz = Int(floor(g.player.pos.z))
        _ = w.loadSync(center: V3(Float(sx), 200, Float(sz)), radius: 2)
        let Y = min(CH - 20, w.topY(sx, sz) + 40)
        let stone = Blocks.id("stone")
        w.deferRemesh = true
        for z in (sz - 12)...(sz + 12) { for x in (sx - 12)...(sx + 12) {
            let pool = x >= sx + 6 && x <= sx + 10 && abs(z - sz) <= 2
            w.setBlock(x, Y, z, stone)
            for y in (Y + 1)...(Y + 6) where !w.isAir(x, y, z) { w.setBlock(x, y, z, AIR) }
            if pool { w.setBlock(x, Y - 1, z, stone); w.setBlock(x, Y, z, LAVA) }      // (sunk level with the floor)
        } }
        w.deferRemesh = false
        w.remeshArea(x0: sx - 13, z0: sz - 13, x1: sx + 13, z1: sz + 13, y0: Y - 1, y1: Y + 7)
        box = (sx, sz, Y)
        let floorY = Float(Y + 1), centre = V3(Float(sx) + 0.5, floorY, Float(sz) + 0.5)
        g.survival = true; g.difficulty = 2
        let dt: Float = 1.0 / 72
        func heal() { g.health = 20; g.onFire = 0; g.player.vel = .zero; g.lastHurtAt = -10; g.lastHurtAmount = 0 }
        func run(_ ms: [Mob], _ secs: Float, stop: () -> Bool) -> Bool {
            for _ in 0..<Int(secs / dt) {
                for m in ms { m.update(dt, game: g) }
                if stop() { return true }
                if g.health < 8 { heal() }
            }
            return false
        }

        // The Ember Asp: coiled, it rears when you come near and its strike sets you burning.
        heal()
        g.player.pos = centre
        let asp = Mob(.emberAsp, at: centre + V3(-1.6, 0, 0)); asp.persistent = true
        g.mobs.mobs.append(asp)
        let s0 = Predators.strikes
        let burnt = run([asp], 4) { g.onFire > 0 && Predators.strikes > s0 }
        check(burnt, "hell wildlife: an Ember Asp 1.6 blocks off struck and its bite set the player burning (\(burnt))")
        g.mobs.mobs.removeAll { $0 === asp }

        // The Slagmaw: lying in the lava pool, it surges out at a player on the shore and bites.
        heal()
        g.player.pos = V3(Float(sx) + 3.5, floorY, Float(sz) + 0.5)
        let maw = Mob(.slagmaw, at: V3(Float(sx) + 8.5, Float(Y), Float(sz) + 0.5)); maw.persistent = true
        g.mobs.mobs.append(maw)
        let u0 = Predators.surges, h0 = g.health
        let bit = run([maw], 6) { Predators.surges > u0 && g.health < h0 }
        check(bit && maw.health == maw.spec.health, String(format: "hell wildlife: a Slagmaw in the lava surged at the player 5 blocks off and bit (%@), unhurt by the lava (%d/%d)",
                                                           bit ? "yes" : "no", maw.health, maw.spec.health))
        g.mobs.mobs.removeAll { $0 === maw }

        // A Cinderhorn herd: grazing, it lets you walk up; hurt the bull and the herd stampedes while he charges.
        heal()
        g.player.pos = centre + V3(-11, 0, 0)
        var herd: [Mob] = []
        for i in 0..<4 {
            // (twelve blocks off: a bison-like herd takes fright inside 7, and the wind's scent can carry that half again)
            let m = Mob(.cinderhorn, at: centre + V3(Float(i % 2) * 2.6 + 1, 0, Float(i / 2) * 2.6 - 1.3)); m.persistent = true
            m.variant = i == 0 ? 1 : 2
            herd.append(m); g.mobs.mobs.append(m)
        }
        _ = run(herd, 2) { false }
        let calm = herd.allSatisfy { $0.fleeTime <= 0 && $0.phase == 0 }
        let c0 = HerdGame.charges, h1 = g.health
        herd[0].hit(from: g.player.pos, damage: 2)
        var ran = Set<ObjectIdentifier>()                  // (those that ran at any moment: a stampede is over in seconds)
        let charged = run(herd, 9) {
            for m in herd.dropFirst() where m.fleeTime > 0 || m.fleeGoal != nil { ran.insert(ObjectIdentifier(m)) }
            return HerdGame.charges > c0 && g.health < h1 && ran.count >= 2
        }
        let fled = ran.count
        check(calm && charged && fled >= 2, "hell wildlife: a Cinderhorn herd grazed 12 blocks off (\(calm ? "calm" : "spooked")); hurt, the bull charged and gored (\(charged)) and \(fled) of 3 stampeded")
    }
}
