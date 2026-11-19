import Foundation
import simd

// Ledger 342: the fierce polar bear (FierceBear.swift). In a walled snow field 71 across:
//   - a bot in full iron with an iron sword stands its ground and fights: the bear kills him, 3 of 3 duels;
//   - the same bot in full steel (still the iron sword: there is no steel blade, so the armour alone turns it) wins, 3 of 3;
//   - the bear sees him from 26 off, roars, stands, then charges faster than he can sprint, and a swipe throws him back;
//   - cubs, the legend, tamed bears and the other neutral animals are as they were (no harm in 5 s beside him);
//   - no bear spawns within 200 of the world's spawn point (every animal roll forced to a bear: none near it, some far);
//   - the warning and charge roars render (length, loudness) and the bear's own voice is the low one.
// BS_OLDBEAR=1 fails the duels, the notice and the spawn gap.
enum BearCheck {
    static func run(game g: Game, check: (Bool, String) -> Void) {
        let scope = SuiteScope(g); defer { scope.putBack(g) }
        let w = g.world
        let pos0 = g.player.pos, yaw0 = g.player.yaw, pitch0 = g.player.pitch, surv0 = g.survival, fly0 = g.player.flying
        let time0 = g.time, diff0 = g.difficulty, diffLevel0 = g.diffLevel, health0 = g.health, mobs0 = g.mobs.mobs
        let hunger0 = g.hunger, sat0 = g.saturation
        let armour0 = g.inventory.armor.slots, main0 = g.inventory.main.slots, sel0 = g.inventory.selected
        let enc0 = w.ships.encounters, menu0 = g.menu, weather0 = g.weather
        let paused0 = g.paused, head0 = g.vrHead, aim0 = g.vrAim
        let fx = Int(floor(pos0.x)), fz = Int(floor(pos0.z))
        let py = min(CH - 30, w.topY(fx, fz) + 24)
        var placed: [(IVec3, BlockID)] = []
        defer {
            for (q, b) in placed.reversed() { w.setBlock(q.x, q.y, q.z, b) }
            g.mobs.mobs = mobs0; w.pendingMobs.removeAll(); g.arms.slugs.removeAll(); g.drops.items.removeAll()
            g.player.pos = pos0; g.player.yaw = yaw0; g.player.pitch = pitch0; g.player.vel = .zero
            g.survival = surv0; g.player.flying = fly0; g.time = time0; g.difficulty = diff0; g.diffLevel = diffLevel0
            g.health = health0; g.alive = true; g.hunger = hunger0; g.saturation = sat0
            g.inventory.armor.slots = armour0; g.inventory.main.slots = main0; g.inventory.selected = sel0
            w.ships.encounters = enc0; g.menu = menu0; g.weather = weather0
            g.paused = paused0; g.vrHead = head0; g.vrAim = aim0
            MobManager.forceAnimal = nil
        }
        w.ships.encounters = false
        g.paused = false; g.vrHead = nil; g.vrAim = nil; g.riding = nil
        w.ships.pilot = nil; w.ships.aboard = nil
        g.survival = true; g.player.flying = false; g.diffLevel = 3                     // Normal
        let R = 35
        _ = w.loadSync(center: V3(Float(fx), Float(py), Float(fz)), radius: 4)
        // The field: snow on stone, walled three high, open to the sky; built once (only what differs is set).
        let snow = Blocks.id("snow_block")
        for z in (fz - R)...(fz + R) { for x in (fx - R)...(fx + R) { for y in (py - 1)...(py + 6) {
            let edge = x == fx - R || x == fx + R || z == fz - R || z == fz + R
            let want = y < py ? STONE : (y == py ? snow : (edge && y <= py + 3 ? STONE : AIR))
            let was = w.block(x, y, z)
            if was != want { placed.append((IVec3(x, y, z), was)); w.setBlock(x, y, z, want) }
        } } }
        let spot = V3(Float(fx) + 0.5, Float(py + 1), Float(fz) + 0.5)

        func gear(_ tier: String) {
            let pieces = ["helmet", "chestplate", "leggings", "boots"]
            for i in 0..<4 { g.inventory.armor[i] = ItemStack(Items.id("\(tier)_\(pieces[i])"), 1) }
            g.inventory.selected = 0
            g.inventory.main[0] = ItemStack(Items.id("iron_sword"), 1)
        }
        func reset() {
            g.mobs.mobs.removeAll(); w.pendingMobs.removeAll(); g.arms.slugs.removeAll(); g.drops.items.removeAll()
            g.player.pos = spot; g.player.vel = .zero; g.health = 20; g.alive = true; g.hunger = 20; g.saturation = 5
            g.time = DAY_LENGTH * 0.25
            g.weather.raining = false; g.weather.thundering = false; g.weather.rain = 0; g.weather.thunder = 0; g.weather.rainTime = 9000; g.weather.thunderTime = 9000
            g.menu = nil; for e in Effect.allCases { g.effects.remove(e) }
            g.player.yaw = 0; g.player.pitch = 0
        }
        func face(_ m: Mob) {
            let d = m.pos + V3(0, min(m.height * 0.5, 1.5), 0) - g.player.eye
            g.player.yaw = atan2f(-d.x, -d.z)
            g.player.pitch = atan2f(d.y, simd_length(V2(d.x, d.z)))
        }
        func flat(_ v: V3) -> Float { simd_length(V2(v.x, v.z)) }

        struct Duel { var died = false, won = false; var secs: Float = 0; var noticeAt: Float = -1; var standFor: Float = -1
                      var chargeSpeed: Float = 0; var swipes = 0; var throwSpeed: Float = 0; var bearLeft = 0; var swings = 0 }
        let swing = 1 / max(0.5, Items.def(Items.id("iron_sword")).attackSpeed)
        func duel(_ tier: String, _ n: Int) -> Duel {
            Rand.seed(0xBEA2_0000 + UInt64(n) * 0x101 + (tier == "steel" ? 0x77 : 0))
            reset(); gear(tier)
            let b = Mob(.polarBear, at: spot + V3(Float(n) - 1, 0, -26))
            b.face(spot)
            g.mobs.mobs = [b]
            let sw0 = FierceBear.swipes
            var d = Duel(), s: Float = 0, next: Float = 0, warnAt: Float = -1
            var chargeRun: Float = 0, chargeTime: Float = 0
            var last = b.pos
            while s < 90 && g.alive && b.health > 0 {
                face(b)
                let dist = flat(b.pos - g.player.pos)
                if dist < 3.6 && s >= next { g.input.leftClicked = true; next = s + swing; d.swings += 1 }
                let hp0 = g.health
                g.tick(0.05); s += 0.05
                g.input.leftClicked = false
                if g.health < hp0 { d.throwSpeed = max(d.throwSpeed, flat(g.player.vel)) }
                if warnAt < 0 && b.phase == 1 { warnAt = s; d.noticeAt = dist }
                if b.phase == 2 && d.standFor < 0 { d.standFor = warnAt >= 0 ? s - warnAt : 0 }
                if b.phase == 2 && dist > 5 { chargeRun += flat(b.pos - last); chargeTime += 0.05 }
                last = b.pos
                g.hunger = 20
                g.mobs.mobs.removeAll { $0 !== b }; w.pendingMobs.removeAll()
            }
            d.secs = s; d.died = !g.alive; d.won = b.health <= 0 && g.alive; d.bearLeft = max(0, Int(b.health))
            d.chargeSpeed = chargeTime > 0.3 ? chargeRun / chargeTime : 0
            d.swipes = FierceBear.swipes - sw0
            g.alive = true; g.health = 20; g.menu = nil
            return d
        }
        func line(_ d: Duel) -> String {
            String(format: "%@ in %.1f s (bear %d left, %d swipes, %d swings), saw him at %.0f, stood %.1f s, charged %.1f b/s, threw him %.1f b/s",
                   d.died ? "he died" : (d.won ? "he won" : "no end"), d.secs, d.bearLeft, d.swipes, d.swings, d.noticeAt, d.standFor, d.chargeSpeed, d.throwSpeed)
        }
        var iron: [Duel] = [], steel: [Duel] = []
        for n in 0..<3 { iron.append(duel("iron", n)); print("bear: iron \(n + 1): " + line(iron[n])) }
        for n in 0..<3 { steel.append(duel("steel", n)); print("bear: steel \(n + 1): " + line(steel[n])) }
        let ironDied = iron.filter { $0.died }.count, steelWon = steel.filter { $0.won }.count
        check(ironDied == 3, "ledger 342: a bot in full iron with an iron sword dies to the polar bear (\(ironDied) of 3)")
        check(steelWon == 3, "ledger 342: the same bot in full steel wins (\(steelWon) of 3)")
        let all = iron + steel
        let notice = all.map { $0.noticeAt }.min() ?? -1, stood = all.map { $0.standFor }.min() ?? -1
        let charge = all.map { $0.chargeSpeed }.min() ?? 0, thrown = all.map { $0.throwSpeed }.max() ?? 0
        let sprint = max(Player.sprintSpeed, Player.vrSprintSpeed)
        check(notice > 20 && stood >= 1.0 && charge > sprint && thrown > 3,
              String(format: "ledger 342: it sees him far off (nearest notice %.0f blocks), roars and stands (shortest %.1f s), charges faster than his sprint (slowest %.1f b/s against %.1f) and throws him back (%.1f b/s)",
                     notice, stood, charge, sprint, thrown))

        // Ledger 344: bigger, and its charge comes in bursts of 5 s at about his sprint with a winded lope between. He keeps
        // 12 ahead of it for 14 s (the bear brought back to the middle each tick, so the arena never ends); what it runs at
        // each tick is read off.
        do {
            reset(); gear("iron")
            let b = Mob(.polarBear, at: spot)
            g.mobs.mobs = [b]
            b.phase = 2; b.phaseTime = 0; b.aggro = true
            var speeds: [Float] = []
            for _ in 0..<280 {
                b.pos = spot; b.vel = .zero
                g.player.pos = spot + V3(0, 0, 12); g.player.vel = .zero; g.health = 20
                g.tick(0.05)
                speeds.append(FierceBear.lastSpeed)
                g.mobs.mobs.removeAll { $0 !== b }; w.pendingMobs.removeAll()
            }
            // (runs of the same speed: the bursts and the lopes)
            var runs: [(Float, Float)] = []
            for v in speeds { if let l = runs.last, l.0 == v { runs[runs.count - 1].1 += 0.05 } else { runs.append((v, 0.05)) } }
            let bursts = runs.filter { $0.0 > sprint }, rests = runs.filter { $0.0 < Player.sprintSpeed }
            let fullBursts = bursts.dropLast().map { $0.1 }                   // (the last may be cut off by the end)
            let fast = bursts.map { $0.0 }.max() ?? 0
            let ok = bursts.count >= 2 && !fullBursts.isEmpty && fullBursts.allSatisfy { abs($0 - 5) < 0.3 } && !rests.isEmpty
                && fast > sprint && fast < sprint * 1.25
            check(ok && b.height > 1.9 && b.scale > 1.4 && b.halfW < 0.8,
                  String(format: "ledger 344: the bear is half as big again (%.1f tall; its body %.1f wide, so it still gets between trees) and charges in bursts: %@ (b/s for s; his sprint %.1f)",
                         b.height, b.halfW * 2, runs.map { String(format: "%.1f for %.1f", $0.0, $0.1) }.joined(separator: ", "), sprint))
            g.mobs.mobs = []
        }
        // ...and running from it flat out (his headset sprint) does not shake it off: from 6 behind, mid-charge, it is on
        // him and swiping within 6 s (it dropped to its fighting pace alongside him and he ran clear).
        do {
            reset(); gear("iron")
            let dir = V3(0, 0, 1), run = Player.vrSprintSpeed
            g.player.pos = spot + V3(0, 0, -24)
            let b = Mob(.polarBear, at: g.player.pos - dir * 6)
            g.mobs.mobs = [b]
            b.phase = 2; b.phaseTime = 0; b.aggro = true
            let sw0 = FierceBear.swipes
            var s: Float = 0, hitAt: Float = -1, closest: Float = 99
            while s < 6 && hitAt < 0 {
                g.player.pos += dir * run * 0.05; g.player.vel = dir * run; g.health = 20
                g.tick(0.05); s += 0.05
                closest = min(closest, flat(b.pos - g.player.pos))
                if FierceBear.swipes > sw0 { hitAt = s }
                g.mobs.mobs.removeAll { $0 !== b }; w.pendingMobs.removeAll()
            }
            check(hitAt > 0, String(format: "ledger 344: he cannot outrun it at a sprint (%.1f b/s): from 6 behind it swipes him %@ (closest %.1f)",
                                    run, hitAt > 0 ? String(format: "after %.1f s", hitAt) : "never in 6 s", closest))
            g.mobs.mobs = []
        }

        // A cub, the wolf, panda and fox beside him leave him alone as before (no grown bear by the cub: its mother's rule
        // stands), and the fierce ways are a wild grown bear's alone (not a cub's, the legend's (Hunting.swift) or a tamed one's).
        reset(); gear("iron")
        var calm: [Mob] = []
        for (i, k) in [MobKind.polarBear, .wolf, .panda, .fox].enumerated() {
            let a = Float(i) * 1.5
            let m = Mob(k, at: spot + V3(cosf(a) * 6, 0, sinf(a) * 6))
            if i == 0 { m.baby = true }
            calm.append(m)
        }
        let legend = Mob(.polarBear, at: spot + V3(0, 0, 30)); legend.legend = 0
        let pet = Mob(.polarBear, at: spot + V3(0, 0, 30)); pet.owner = true
        let none = (calm + [legend, pet]).allSatisfy { $0.fierceBearAI(0.05, g, dist: 6) == nil }
        g.mobs.mobs = calm
        var s: Float = 0
        while s < 5 && g.health >= 20 { g.tick(0.05); s += 0.05; g.player.pos = spot; g.player.vel = .zero }
        check(none && g.health >= 20, "ledger 342: a cub, a wolf, a panda and a fox beside him leave him alone (health \(g.health) after \(String(format: "%.1f", s)) s); fierce ways only for a wild grown bear (not a cub, the legend or a tamed one): \(none ? "yes" : "no")")

        // No bear within 200 of the world's spawn point: every animal roll forced to a bear, rolled from his spot at the spawn
        // point and from 420 off.
        reset()
        let origin = Game.findSpawn(gen: w.gen, seed: w.seed)
        func rolls(at c: V3) -> (near: Int, far: Int) {
            g.mobs.mobs.removeAll()
            let top = Float(w.topY(Int(floor(c.x)), Int(floor(c.z))) + 1)
            g.player.pos = V3(c.x, top, c.z); g.player.vel = .zero
            _ = w.loadSync(center: g.player.pos, radius: 6)
            MobManager.forceAnimal = .polarBear
            let r0 = MobManager.forcedRolls, k0 = FierceBear.kept
            for _ in 0..<4000 { g.mobs.trySpawnPassive(g); if g.mobs.mobs.count > 200 { break } }
            MobManager.forceAnimal = nil
            print("bear: rolls from \(Int(c.x)), \(Int(c.z)): \(MobManager.forcedRolls - r0) bear rolls, \(FierceBear.kept - k0) kept off near the spawn point, \(g.mobs.mobs.count) placed (render \(w.renderDistance), active \(w.activeDistance), \(w.chunks.count) chunks)")
            let bears = g.mobs.mobs.filter { $0.kind == .polarBear }
            let near = bears.filter { flat($0.pos - origin) < FierceBear.spawnClear }.count
            return (near, bears.count - near)
        }
        let atSpawn = rolls(at: origin)
        // (from 420 off on land: the first of four ways that is not sea, so the rolls can place a bear at all)
        var out = (near: 0, far: 0)
        for d in [V3(420, 0, 0), V3(-420, 0, 0), V3(0, 0, 420), V3(0, 0, -420)] where out.far == 0 {
            let c = origin + d
            let col = w.gen.column(Int(c.x), Int(c.z))
            if col.biome.isOcean || col.height <= SEA + 1 { continue }
            out = rolls(at: c)
        }
        g.mobs.mobs.removeAll(); w.pendingMobs.removeAll()
        let gate = FierceBear.nearSpawn(g, Int(origin.x) + 150, Int(origin.z)) && !FierceBear.nearSpawn(g, Int(origin.x) + 250, Int(origin.z))
        check(atSpawn.near == 0 && out.far > 0 && gate,
              "ledger 342: no polar bear within 200 of the spawn point (forced bear rolls: \(atSpawn.near) near, \(atSpawn.far) past 200 from the spawn; \(out.far) from 420 off; 150 off refused, 250 off allowed: \(gate ? "yes" : "no"))")

        // Its sounds: the warning and charge roars render, and its voice is the low one.
        var sounds: [String] = []
        var loud = true
        for snd in [Snd.bearWarn, .bearCharge, .mob(.polarBear, .ambient), .mob(.polarBear, .hurt), .mob(.polarBear, .death)] {
            let x = SoundBank.render(snd, variant: 0)
            if let dir = Env.all["BEAR_WAV"] { SoundBank.writeWAV(x, to: (dir as NSString).appendingPathComponent(snd.name + ".wav")) }      // (for a clip)
            let secs = Float(x.count) / Synth.sr
            let peak = x.reduce(0) { max($0, abs($1)) }
            if peak < 0.05 || secs < 0.2 { loud = false }
            sounds.append(String(format: "%@ %.1f s peak %.2f", snd.name, secs, peak))
        }
        let voice = MobVoice.profile(.polarBear)
        let warnLen = Float(SoundBank.render(.bearWarn, variant: 0).count) / Synth.sr
        check(loud && voice.f0 < 100 && voice.size >= 2 && warnLen > 1.5, "ledger 342: the bear's five sounds render low and big (" + sounds.joined(separator: "; ") + String(format: "; voice f0 %.0f size %.1f)", voice.f0, voice.size))
        // (BEAR_FIND=1: the nearest snowy plains to the spawn point, for a scene)
        if Env.all["BEAR_FIND"] == "1" {
            var best: (Float, Int, Int)?
            for r in stride(from: 200, through: 4000, by: 32) where best == nil {
                for k in 0..<max(8, r / 8) {
                    let a = Float(k) / Float(max(8, r / 8)) * 2 * .pi
                    let x = Int(origin.x + cosf(a) * Float(r)), z = Int(origin.z + sinf(a) * Float(r))
                    if w.gen.column(x, z).biome == .snowyPlains { best = (Float(r), x, z); break }
                }
            }
            if let b = best { print("bear: snowy plains \(Int(b.0)) from the spawn point at \(b.1), \(b.2)") }
        }
        print("bear: \(FierceBear.warnings) warnings, \(FierceBear.charges) charges, \(FierceBear.swipes) swipes")
    }
}
