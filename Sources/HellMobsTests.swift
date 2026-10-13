import Foundation
import simd

// Hell's own mobs and the gate into hell (backlog B6; HellMobs.swift, HellGate.swift; docs/status/hell-mobs.md).
// `questcheck --hell-only` runs just these.
enum HellMobsTests {
    static var arena: V3?                         // the stone arena the checks fought on (the questcheck lineup shot)
    static var arenaBox: (x: Int, z: Int, y: Int)?

    static func remesh(_ w: World, _ x: Int, _ z: Int, _ y: Int) {
        w.remeshArea(x0: x - 17, z0: z - 17, x1: x + 17, z1: z + 17, y0: y - 1, y1: y + 15)
    }

    // Takes the arena away (after the lineup shot).
    static func cleanup(_ g: Game) {
        guard let a = arenaBox else { return }
        let w = g.world
        w.deferRemesh = true
        for z in (a.z - 16)...(a.z + 16) { for x in (a.x - 16)...(a.x + 16) { for y in a.y...(a.y + 14) where w.block(x, y, z) != AIR { w.setBlock(x, y, z, AIR) } } }
        w.deferRemesh = false
        remesh(w, a.x, a.z, a.y)
        arenaBox = nil; arena = nil
    }

    // Every hell mob side by side on the arena, facing the camera, the knights in their telling poses.
    static func lineup(_ g: Game) -> [Mob] {
        guard let c = arena else { return [] }
        let kinds = MobKind.allCases.filter { $0.hellOwn }
        var out: [Mob] = []
        for (i, k) in kinds.enumerated() {
            let m = Mob(k, at: c + V3(Float(i) * 1.7 - 5.1, k == .searwing ? 1.4 : 0, -2.5))
            m.yaw = .pi
            switch k {
            case .brandKnight: m.hellState.s = .windup
            case .brandChampion: m.hellState.s = .aim
            case .slagthrower: m.hellState.s = .windup
            default: break
            }
            m.walkPhase = 1.2
            g.mobs.mobs.append(m)
            out.append(m)
        }
        return out
    }

    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let t0 = CFAbsoluteTimeGetCurrent()
        let w = g.world
        let wasPos = g.player.pos, wasSurvival = g.survival, wasHealth = g.health, wasDiff = g.difficulty
        let wasInv = g.inventory.main.slots, wasSel = g.inventory.selected
        let hellKinds = MobKind.allCases.filter { $0.hellOwn }
        defer {
            g.mobs.mobs.removeAll { $0.kind.hellOwn }
            g.hell.slag.removeAll(); g.hell.charges.removeAll()
            g.player.pos = wasPos; g.player.vel = .zero; g.survival = wasSurvival; g.health = wasHealth; g.difficulty = wasDiff
            g.inventory.main.slots = wasInv; g.inventory.selected = wasSel
            g.onFire = 0
            print(String(format: "hell: %.1f s", CFAbsoluteTimeGetCurrent() - t0))
        }

        // The roster: seven kinds with names, keys, a model in every pose, a voice, and they save and load.
        var bad: [String] = []
        for k in hellKinds {
            let m = Mob(k, at: V3(0, 100, 0))
            if MobKind.named(k.key) != k || k.spec.name.isEmpty || !k.hostile { bad.append("\(k.key): registry") }
            var parts = 0
            for s in [HellState.S.idle, .windup, .recover, .stagger, .aim, .charge, .dive, .climb] {
                m.hellState.s = s
                let n = hellParts(m, swing: 0.3).count
                if n == 0 || n > 60 { bad.append("\(k.key): \(n) parts in \(s)") }
                parts = max(parts, n)
            }
            if MobVoice.profile(k).family == .silent { bad.append("\(k.key): silent") }
            m.health = 5
            let back = (try? JSONEncoder().encode(m.record)).flatMap { try? JSONDecoder().decode(MobRecord.self, from: $0) }.flatMap { Mob.from($0) }
            if back?.kind != k || back?.health != 5 { bad.append("\(k.key): save") }
        }
        check(hellKinds.count == 7 && bad.isEmpty,
              "hell: \(hellKinds.map { $0.spec.name }.joined(separator: ", ")): registered, drawn in every pose, voiced, saved\(bad.isEmpty ? "" : " -- \(bad.prefix(4))")")

        // An arena well away from the spawn (it mustn't shade the later checks' views), high up: stone, 33 x 33, open sky.
        // HellMobsTests.cleanup takes it away again.
        let sx = Int(floor(g.player.pos.x)) + 176, sz = Int(floor(g.player.pos.z))
        _ = w.loadSync(center: V3(Float(sx), 200, Float(sz)), radius: 3)
        let Y = min(CH - 30, w.topY(sx, sz) + 50)
        let stone = Blocks.id("stone")
        w.deferRemesh = true
        for z in (sz - 16)...(sz + 16) { for x in (sx - 16)...(sx + 16) {
            w.setBlock(x, Y, z, stone)
            for y in (Y + 1)...(Y + 14) where w.block(x, y, z) != AIR { w.setBlock(x, y, z, AIR) }
        } }
        w.deferRemesh = false
        remesh(w, sx, sz, Y)
        arenaBox = (sx, sz, Y)
        let floorY = Float(Y + 1)
        let centre = V3(Float(sx) + 0.5, floorY, Float(sz) + 0.5)
        arena = centre
        g.survival = true; g.difficulty = 2
        g.player.pos = centre; g.player.vel = .zero
        let dt: Float = 1.0 / 72
        func heal() { g.health = 20; g.onFire = 0; g.player.vel = .zero; g.lastHurtAt = -10; g.lastHurtAmount = 0 }
        func spawn(_ k: MobKind, _ off: V3) -> Mob {
            let m = Mob(k, at: centre + off)
            m.persistent = true
            m.face(g.player.pos); m.yaw = atan2f(-(g.player.pos.x - m.pos.x), -(g.player.pos.z - m.pos.z))
            g.mobs.mobs.append(m)
            return m
        }
        func clear() { g.mobs.mobs.removeAll { $0.kind.hellOwn }; g.hell.slag.removeAll() }
        // Ticks `m` (and slag) for up to `secs`; `stop` ends early.
        @discardableResult
        func tick(_ m: Mob, _ secs: Float, stop: (() -> Bool)? = nil) -> Bool {
            for _ in 0..<Int(secs / dt) {
                m.update(dt, game: g); g.slagTick(dt)
                if g.health < 8 { heal() }
                if let s = stop, s() { return true }
            }
            return false
        }
        func facing(_ m: Mob) { m.yaw = atan2f(-(g.player.pos.x - m.pos.x), -(g.player.pos.z - m.pos.z)) }

        // The shield: a frontal blade or arrow does nothing, a blade from behind lands, a bullet is cut down.
        do {
            clear(); heal()
            let k = spawn(.brandKnight, V3(0, 0, -2)); facing(k)
            let hp = k.health
            Mob.playerMelee = true
            k.hit(from: g.player.pos, damage: 6)
            let front = k.health
            k.hellState.s = .idle                               // (a riposte it may have started, P185)
            k.hit(from: k.pos - k.forward * 2, damage: 6)
            let behind = k.health
            Mob.playerMelee = false
            k.hellState.guardLeft = k.orderGuardMax
            k.hit(from: g.player.pos, damage: 3)                // an arrow
            let arrow = k.health
            k.hit(from: g.player.pos, damage: 12)               // a rifle round
            let bullet = k.health
            check(front == hp && behind < front && arrow == behind && bullet == arrow - 3,
                  "hell: a knight's shield takes a frontal blade and arrow (\(hp) -> \(front), \(behind) -> \(arrow)), not one from behind (\(front) -> \(behind)), and cuts a 12 round to \(arrow - bullet)")
        }

        // The guard: a squire's breaks on the third blocked hit, and then a hit lands half again.
        do {
            clear()
            let s = spawn(.brandSquire, V3(0, 0, -2)); facing(s)
            Mob.playerMelee = true
            Mob.playerMeleePower = 0.2
            for _ in 0..<5 { s.hit(from: g.player.pos, damage: 4) }        // taps: they clang off and don't wear it
            let tapped = s.hellState.guardLeft == s.orderGuardMax && s.health == s.spec.health
            Mob.playerMeleePower = 1
            for _ in 0..<s.orderGuardMax { s.hit(from: g.player.pos, damage: 4) }
            let broke = s.hellState.s == .stagger, hp = s.health
            s.hit(from: g.player.pos, damage: 4)
            Mob.playerMelee = false
            check(tapped && broke && hp == s.spec.health && s.health == hp - 6, "hell: taps clang off a squire's guard; it breaks after \(s.orderGuardMax) full blows; the next hit lands for \(hp - s.health) of 4")
        }

        // The parry: a knight winds up in reach (the blade high, shield aside); a blade then staggers it for half again.
        do {
            clear(); heal()
            let k = spawn(.brandKnight, V3(0, 0, -1.6)); facing(k)
            k.hellState.cool = 99
            let wound = tick(k, 3) { k.hellState.s == .windup }
            k.hellState.feint = false                           // (P185: a feint is met by the blade instead)
            let parries = HellStats.parries
            let hp = k.health
            Mob.playerMelee = true
            k.hit(from: g.player.pos, damage: 6)
            Mob.playerMelee = false
            let staggered = k.hellState.s == .stagger
            let hp2 = k.health
            tick(k, 0.05)
            check(wound && staggered && HellStats.parries == parries + 1 && hp - hp2 == 9 && g.advancements.contains("adventure/brand_parry"),
                  "hell: a hit in the knight's wind-up parries it (stagger, \(hp - hp2) for a 6 hit, Riposte)")
            // Left alone, the swing lands.
            clear(); heal()
            let k2 = spawn(.brandKnight, V3(0, 0, -1.6)); facing(k2)
            k2.hellState.cool = 99
            let h0 = g.health
            tick(k2, 3) { g.health < h0 }
            check(g.health < h0, "hell: an unanswered wind-up lands (\(h0) -> \(g.health) health)")
        }

        // The charge: sidestepped, the knight skids past and stands dazed; taken, it hits hard and throws you back.
        do {
            clear(); heal()
            let k = spawn(.brandKnight, V3(0, 0, -10)); facing(k)
            k.hellState.cool = 0
            let aimed = tick(k, 3) { k.hellState.s == .charge }
            g.player.pos.x += 3                                 // the sidestep
            let dodged = HellStats.dodged
            tick(k, 3) { k.hellState.s != .charge }
            let dazed = k.hellState.s == .dazed
            g.player.pos = centre
            check(aimed && dazed && HellStats.dodged == dodged + 1, "hell: a sidestepped charge leaves the knight dazed")
            clear(); heal()
            let k2 = spawn(.brandKnight, V3(0, 0, -10)); facing(k2)
            k2.hellState.cool = 0
            let hits = HellStats.chargeHits
            let h0 = g.health
            var thrown: Float = 0
            tick(k2, 4) {
                thrown = max(thrown, simd_length(V2(g.player.vel.x, g.player.vel.z)))
                return HellStats.chargeHits > hits
            }
            thrown = max(thrown, simd_length(V2(g.player.vel.x, g.player.vel.z)))
            check(HellStats.chargeHits == hits + 1 && h0 - g.health >= 4 && thrown > 4,
                  String(format: "hell: a charge that connects hits for %d and throws the player back (%.1f b/s)", h0 - g.health, thrown))
        }

        // The Commander: at half health his horn calls a knight and two squires, he goes berserk, and he has a boss bar.
        do {
            clear(); heal()
            let c = spawn(.brandCommander, V3(0, 0, -6)); facing(c)
            let n0 = g.mobs.mobs.filter { $0.kind.brandOrder }.count
            let bar = g.hellBossBar()
            _ = c.hellState                                     // met at full health
            c.health = c.spec.health / 2 - 1
            tick(c, 0.05)
            let n1 = g.mobs.mobs.filter { $0.kind.brandOrder }.count
            check(bar?.0 == "Brand Commander" && c.scale > 1.2 && n1 == n0 + 3 && c.hellState.raged && c.orderGuardMax == 16,
                  "hell: the Brand Commander (boss bar, \(c.spec.health) health) calls \(n1 - n0) of his order at half health and rages")
            // Saved past half: no second horn.
            let back = Mob.from(c.record)
            check(back?.hellState.called == true, "hell: a Commander saved past half health doesn't call again")
        }

        // The Searwing circles high, winds up, dives at the head and climbs away slowly.
        do {
            clear(); heal()
            let s = spawn(.searwing, V3(4, 2, 0))
            s.hellState.cool = 3                                // circles a while first
            let d0 = HellStats.dives, hits = HellStats.diveHits
            var sawClimb = false, maxY: Float = 0
            tick(s, 10) {
                if s.hellState.s == .climb { sawClimb = true }
                maxY = max(maxY, s.pos.y - floorY)
                return sawClimb && HellStats.diveHits > hits
            }
            check(HellStats.dives > d0 && HellStats.diveHits > hits && sawClimb && maxY > 6,
                  String(format: "hell: the Searwing circles (up to %.0f blocks), dives at the head and climbs away", maxY))
        }

        // Natural spawns: patrols, packs, lone throwers and fliers, within their caps.
        do {
            clear()
            var groups: [MobKind: Int] = [:], packMax = 0
            for _ in 0..<300 {
                let before = g.mobs.mobs.count
                if g.mobs.hellOwnSpawn(g, at: centre + V3(Float(Rand.int(in: -8...8)), 0, Float(Rand.int(in: -8...8)))) {
                    let added = g.mobs.mobs[before...]
                    if let f = added.first { groups[f.kind.brandOrder ? .brandKnight : f.kind, default: 0] += 1 }
                    packMax = max(packMax, added.filter { $0.kind == .scorchling }.count)
                }
                if g.mobs.mobs.filter({ $0.kind.hellOwn }).count > 24 { clear() }
            }
            var over: [String] = []
            for k in hellKinds where g.mobs.mobs.filter({ $0.kind == k }).count > HellMobs.caps[k.hellIndex] { over.append(k.key) }
            check(groups.count == 4 && packMax >= 5 && over.isEmpty,
                  "hell: hell spawns order patrols (\(groups[.brandKnight] ?? 0)), Scorchling packs (\(groups[.scorchling] ?? 0), up to \(packMax)), Slagthrowers (\(groups[.slagthrower] ?? 0)) and Searwings (\(groups[.searwing] ?? 0)) within caps")
            clear()
        }

        // The Slagthrower's slag lands on a target standing still and misses one that walks away.
        do {
            clear(); heal()
            let t = spawn(.slagthrower, V3(0, 0, -12)); facing(t)
            t.hellState.cool = 0
            var hits = HellStats.slagHits, lobs = HellStats.lobs
            tick(t, 4) { HellStats.lobs > lobs && g.hell.slag.isEmpty }
            let still = HellStats.slagHits > hits
            heal()
            hits = HellStats.slagHits; lobs = HellStats.lobs
            t.hellState.cool = 0
            tick(t, 4) { HellStats.lobs > lobs }
            g.player.pos.x += 5
            tick(t, 3) { g.hell.slag.isEmpty }
            let moved = HellStats.slagHits == hits
            g.player.pos = centre
            check(still && moved, "hell: the Slagthrower's slag lands on a target standing still and misses one that walks away")
            clear()
        }

        // 30 of hell's own around the player: the mob tick stays cheap.
        do {
            clear(); heal()
            var crowd: [Mob] = []
            for i in 0..<30 {
                let k = hellKinds[i % hellKinds.count] == .brandCommander ? MobKind.brandKnight : hellKinds[i % hellKinds.count]
                let a = Float(i) * 0.7
                crowd.append(spawn(k, V3(cosf(a) * 10, k == .searwing ? 6 : 0, sinf(a) * 10)))
            }
            let tt = CFAbsoluteTimeGetCurrent()
            let n = 144
            for _ in 0..<n { for m in crowd { m.update(dt, game: g) }; g.slagTick(dt); if g.health < 8 { heal() } }
            let ms = (CFAbsoluteTimeGetCurrent() - tt) * 1000 / Double(n)
            check(ms < 1.5, String(format: "hell: 30 hell mobs fighting cost %.2f ms a tick", ms))
            clear()
        }

        // The gate: the surface floor is Wardstone, and no pickaxe or blast breaks it.
        do {
            var floorOK = true
            for dz in -4...4 { for dx in -4...4 { for y in 0..<HellGate.floorTop where w.block(sx + dx, y, sz + dz) != WARDSTONE { floorOK = false } } }
            let netherite = ItemStack(Items.id("netherite_pickaxe"), 1), sunder = ItemStack(Items.id(DeepSeal.pickaxe), 1)
            let tN = Mining.breakSeconds(WARDSTONE, netherite, onGround: true, inWater: false)
            let tS = Mining.breakSeconds(WARDSTONE, sunder, onGround: true, inWater: false)
            let bx = sx + 6, bz = sz + 6
            Explosion.explode(at: V3(Float(bx) + 0.5, 3.5, Float(bz) + 0.5), power: 6, game: g, breakBlocks: true)
            check(floorOK && tN.isInfinite && tS.isInfinite && w.block(bx, 2, bz) == WARDSTONE,
                  "hell: the surface's bottom \(HellGate.floorTop) layers are Wardstone: no pickaxe (even Sunderite) or blast breaks it")
            // An Ember Charge on it: a 3x3 shaft, and the seam carries the player through it.
            g.inventory.selected = 0
            g.inventory.main[0] = ItemStack(Items.id(HellGate.chargeKey), 1)
            let used = g.useEmberCharge(on: (hit: IVec3(bx, 2, bz), normal: IVec3(0, 1, 0)))
            for _ in 0..<Int(3.4 / dt) { g.hellTick(dt) }
            var open = 0
            for dz in -1...1 { for dx in -1...1 { for y in 0..<HellGate.floorTop where w.block(bx + dx, y, bz + dz) == AIR { open += 1 } } }
            let home = g.player.pos
            g.player.pos = V3(Float(bx) + 0.5, 0.3, Float(bz) + 0.5)
            g.deepTick(0.05)
            let through = g.dim.dim == .deep
            if through { g.changeDimension(to: .overworld, at: home); g.player.pos = home }
            // Beside the shaft the floor holds.
            g.player.pos = V3(Float(bx) + 4.5, 0.3, Float(bz) + 0.5)
            g.deepTick(0.05)
            let held = g.dim.dim == .overworld
            if !held { g.changeDimension(to: .overworld, at: home) }
            g.player.pos = home
            check(used && open == 27 && g.inventory.main[0].isEmpty && through && held && g.advancements.contains("adventure/break_ward"),
                  "hell: an Ember Charge blasts a 3x3 shaft through the Wardstone (\(open)/27 blocks) and the seam carries you down it, not through the floor beside it")
        }

        // Portals: on the surface flint and steel can't wake a frame; an Ember Charge does.
        do {
            let ox = sx - 10, oz = sz - 10, oy = Y + 1
            w.deferRemesh = true
            for x in 0...3 { for y in 0...4 where x == 0 || x == 3 || y == 0 || y == 4 { w.setBlock(ox + x, oy + y, oz, OBSIDIAN) } }
            w.deferRemesh = false
            let inside = IVec3(ox + 1, oy + 1, oz)
            let locked = g.portalLocked(inside)
            g.survival = false
            let creative = g.portalLocked(inside)
            g.survival = true
            g.inventory.main[0] = ItemStack(Items.id(HellGate.chargeKey), 1)
            let lit = g.useEmberCharge(on: (hit: IVec3(ox + 1, oy, oz), normal: IVec3(0, 1, 0)))
            let portal = w.block(ox + 1, oy + 2, oz)
            check(locked && !creative && lit && (portal == PORTAL_X || portal == PORTAL_Z) && g.inventory.main[0].isEmpty,
                  "hell: a surface portal frame stays cold to flint and steel in survival; an Ember Charge wakes it")
            g.breakPortal(near: inside)
            for x in 0...3 { for y in 0...4 { w.setBlock(ox + x, oy + y, oz, AIR) } }
        }

        // Ember Charges are base loot: every command chest holds one, vaults one or two, and no recipe makes one.
        do {
            var cmd = 0, vault = 0
            for s in 0..<20 {
                for (t, n) in [("steelhold_command", 0), ("steelhold_vault", 1)] {
                    let c = ItemContainer(27)
                    var rng = SRng(UInt64(s * 31 + n + 1))
                    Loot.fill(c, table: t, rng: &rng)
                    if c.countOf(Items.id(HellGate.chargeKey)) >= 1 { if n == 0 { cmd += 1 } else { vault += 1 } }
                }
            }
            let crafted = Recipes.all.contains { $0.result.item == Items.id(HellGate.chargeKey) }
            check(cmd == 20 && vault == 20 && !crafted, "hell: Ember Charges come from base command rooms (\(cmd)/20) and vaults (\(vault)/20), never a recipe")
        }

        // Saved surface chunks from before the floor get it; a chunk already floored keeps its blasted shafts.
        do {
            var old = [BlockID](repeating: EMBERSLATE, count: CSQ * CH)
            old[5] = AIR; old[CSQ + 7] = LAVA; old[9] = Blocks.id("amethyst_block"); old[CSQ + 1] = Blocks.id("ladder")
            let chest = Blocks.id("chest")
            old[CSQ * 2 + 3] = chest
            HellGate.stamp(&old)
            let stamped = old[5] == WARDSTONE && old[CSQ + 7] == WARDSTONE && old[9] == WARDSTONE && old[CSQ + 1] == WARDSTONE && old[CSQ * 2 + 3] == chest && old[CSQ * 3] == EMBERSLATE
            var cut = [BlockID](repeating: WARDSTONE, count: CSQ * CH)
            cut[0] = AIR
            HellGate.stamp(&cut)
            check(stamped && cut[0] == AIR, "hell: saved surface chunks get the Wardstone floor (a player's chest stays); a blasted shaft stays open")
        }
    }
}
