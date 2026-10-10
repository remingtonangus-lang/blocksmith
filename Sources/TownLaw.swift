import Foundation
import simd

// Town law: stealing, vandalism and assault in a town, the town's anger, and the sheriff.
//
// Offences only count when a townsperson notices (within 6 blocks, or within 20 with a clear line of sight) and the
// spot belongs to a town (within 72 blocks of a village's anchor) and wasn't built by the player (blocks the player
// places in towns are remembered). Each offence adds heat to that town (taking from a town chest or barrel 1-3 by how
// much, breaking town property 1, hurting a townsperson 2); heat cools by 1 every 90 s.
//   heat < 2: the witness warns you ("Hey! That's not yours."), the witnesses think a little less of you.
//   heat 2-4: the law warns you (the sheriff or a deputy calls out and comes over), more lost standing.
//   heat >= 4: the town turns on you for 150 s: big loss of standing with everyone near (prices up to +25%, keepers
//              refuse to serve while it lasts), everyone armed fights, the rest run, and the sheriff calls his
//              challenge and draws 2.5 s later.
// The sheriff (role "sheriff", save key "villager:sheriff") replaces the iron golem as the town protector: new towns
// get him on the square instead of a golem, older towns get one sent the first time you're there (and a new one three
// days after he falls). He patrols the square day and night, fights monsters and the player with a revolver (hitscan,
// a 70% hit chance at range), and can be fought and killed. Townsfolk no longer summon golems; golems already in old
// towns stay (removing mobs from a save would be destructive) and keep defending as before.
enum TownLaw {
    static let golemsAllowed = false
    static let hostileHeat: Float = 4
    static let hostileSeconds: Float = 150

    // Per-world state (reset and loaded by Game.loadExtra; saved by saveExtra as extra["townLaw"]).
    struct Saved: Codable {
        var heat: [String: Float] = [:]
        var hostile: [String: Float] = [:]          // seconds of open hostility left
        var appointed: [String: Int] = [:]          // town -> the day its sheriff was last seen or sent
        var placed: [[Int]] = []                    // player-placed blocks in towns (newest last, capped)
    }
    static var state = Saved()
    static var placedSet = Set<IVec3>()

    // Live (not saved).
    static var inTown: String?                      // the town the player is in (townsfolk within 48), every second
    static var forceTown: Bool?                     // tests: treat every spot as town (true) or none (false)
    static var lastTick: Double = -1
    static var lastAmbient: Double = -100
    static var openPos: IVec3?
    static var openCount = 0
    static var openStart: Double = 0
    static var pending: [(Mob, Double)] = []        // sheriffs about to draw (after their challenge)
    static var offences = 0                         // counted (TownTests)

    static func reset() {
        state = Saved(); placedSet = []; inTown = nil; pending = []; openPos = nil; offences = 0; lastTick = -1
    }
    static func save(_ d: inout [String: String]) {
        state.placed = placedSet.suffix(4096).map { [$0.x, $0.y, $0.z] }
        if let e = try? JSONEncoder().encode(state), let s = String(data: e, encoding: .utf8) { d["townLaw"] = s }
    }
    static var worldSeed: UInt64?                  // the world this state belongs to (a new world starts clean)
    static func load(_ d: [String: String], seed: UInt64) {
        reset()
        worldSeed = seed
        if let s = d["townLaw"], let data = s.data(using: .utf8), let st = try? JSONDecoder().decode(Saved.self, from: data) {
            state = st
            placedSet = Set(st.placed.compactMap { $0.count == 3 ? IVec3($0[0], $0[1], $0[2]) : nil })
        }
    }

    // MARK: Where and who

    static func isTownSpot(_ g: Game, _ p: IVec3) -> Bool {
        if let f = forceTown { return f }
        guard g.dim.dim == .overworld, let sc = g.world.gen.structures,
              let s = sc.nearest("village", x: p.x, z: p.z, maxRegions: 1) else { return false }
        return abs(s.anchor.x - p.x) < 72 && abs(s.anchor.z - p.z) < 72
    }

    static func isTownsperson(_ m: Mob) -> Bool { m.kind == .villager && m.health > 0 && m.villager?.person != nil }
    static func isLaw(_ m: Mob) -> Bool { m.villager?.role == "sheriff" || m.villager?.role == "deputy" }

    // Townsfolk who notice something the player does at p.
    static func witnesses(_ g: Game, at p: V3) -> [Mob] {
        var out: [Mob] = []
        for o in g.mobs.mobs where isTownsperson(o) && !o.lying {
            let d = simd_length(o.eye - g.player.eye)
            if d < 6 || (d < 20 && g.world.canSee(o.eye, g.player.eye)) || simd_length(o.eye - p) < 4 { out.append(o) }
        }
        return out.sorted { simd_length($0.pos - g.player.pos) < simd_length($1.pos - g.player.pos) }
    }

    static func town(of m: Mob, _ g: Game) -> String { m.villager?.town ?? Townsfolk.town(g, at: m.home ?? m.pos) }
    static func heat(_ town: String) -> Float { state.heat[town] ?? 0 }
    static func isHostile(_ town: String) -> Bool { (state.hostile[town] ?? 0) > 0 }
    static func isHostile(_ g: Game, _ m: Mob) -> Bool { isHostile(town(of: m, g)) }

    // MARK: Hooks from the game

    // Game.interact after placing a block: the player's own, never theft.
    static func placed(_ g: Game, _ p: IVec3) {
        guard isTownSpot(g, p) else { return }
        placedSet.insert(p)
        if placedSet.count > 6000 { placedSet = Set(placedSet.prefix(4096)) }
    }

    // What counts as town property (crops, buildings, fittings, containers), per block state.
    static let property: [Bool] = (0..<Blocks.count).map { i in
        let k = Blocks.key(Blocks.groupBase[i])
        if ["wheat", "carrots", "potatoes", "beetroots", "melon", "pumpkin", "hay_block", "farmland", "bell", "dirt_path"].contains(k) { return true }
        let words = ["planks", "door", "glass", "_bed", "chest", "barrel", "fence", "lantern", "torch", "sign", "wool", "carpet", "terracotta",
                     "cobblestone", "stairs", "slab", "bookshelf", "furnace", "smoker", "composter", "lectern", "loom", "cauldron",
                     "_table", "stand", "stonecutter", "grindstone", "anvil", "bricks", "wall", "pane", "bars", "flower_pot",
                     "jukebox", "iron_block", "stripped_", "smooth_stone", "chain"]
        return words.contains { k.contains($0) }
    }

    // Game.breakBlock (the player broke b at p).
    static func broke(_ g: Game, _ p: IVec3, _ b: BlockID) {
        guard Int(b) < property.count, property[Int(b)] else { return }
        if placedSet.remove(p) != nil { return }
        guard isTownSpot(g, p) else { return }
        offence(g, heat: 1, at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5))
    }

    // Game.openBlock: remember which block's menu is about to open (chests, barrels).
    static func opening(_ g: Game, _ p: IVec3) {
        openPos = p; openStart = g.clock; openCount = -1
    }
    // Game.openMenu: a container menu from a town chest or barrel: count what's inside.
    static func opened(_ g: Game, _ m: Menu) {
        guard let p = openPos, g.clock - openStart < 0.5, m is ChestMenu || m is DoubleChestMenu,
              !placedSet.contains(p), isTownSpot(g, p) else { openPos = nil; return }
        openCount = containerItems(g, m)
    }
    // Per second while the menu is open, and when it closes: items gone from the container are theft.
    static func checkTaking(_ g: Game, _ m: Menu) {
        guard let p = openPos, openCount >= 0 else { return }
        let now = containerItems(g, m)
        if now < openCount {
            let n = openCount - now
            offence(g, heat: 1 + min(2, Float(n) / 16), at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5))
        }
        openCount = now
    }
    static func closed(_ g: Game, _ m: Menu) {
        if openPos != nil { checkTaking(g, m) }
        openPos = nil
    }
    static func containerItems(_ g: Game, _ m: Menu) -> Int {
        var n = 0
        for s in m.slots where !s.isPlayerInv && !s.isHotbar {
            guard let c = s.container, s.index < c.count, c !== g.inventory.main else { continue }
            n += c[s.index].count
        }
        return n
    }

    // townAlarm: the player hurt a townsperson (the victim always notices).
    static func assault(_ g: Game, _ victim: Mob) {
        offence(g, heat: 2, at: victim.eye, victim: victim, speak: false)
    }

    // MARK: Escalation

    static func offence(_ g: Game, heat add: Float, at p: V3, victim: Mob? = nil, speak: Bool = true) {
        guard g.dim.dim == .overworld else { return }
        var ws = witnesses(g, at: p)
        if let v = victim, !ws.contains(where: { $0 === v }) { ws.insert(v, at: 0) }
        guard let first = ws.first else { return }
        let town = town(of: first, g)
        let h = heat(town) + add
        state.heat[town] = h
        offences += 1
        let law = g.mobs.mobs.filter { isTownsperson($0) && isLaw($0) && simd_length($0.pos - g.player.pos) < 40 }
            .min { simd_length($0.pos - g.player.pos) < simd_length($1.pos - g.player.pos) }
        if h >= hostileHeat {
            turnHostile(g, town, at: p, witness: first)
            return
        }
        for w in ws { if var v = w.villager { v.addGossip(.minorNeg, h >= 2 ? 12 : 6); w.villager = v } }
        guard speak else { return }
        if h >= 2, let l = law {
            if simd_length(l.pos - g.player.pos) > 4 { l.wanderGoal = g.player.pos; l.moving = true; l.aiTimer = 4 }
            l.face(g.player.pos)
            Townsfolk.townLastLine = -100
            TownVoice.speak(g, l, isLawWithin(l, g, 14) ? .theft : .challenge)
        } else {
            first.face(g.player.pos)
            Townsfolk.townLastLine = -100
            TownVoice.speak(g, first, .theft)
        }
    }
    static func isLawWithin(_ m: Mob, _ g: Game, _ r: Float) -> Bool { simd_length(m.pos - g.player.pos) < r }

    static func turnHostile(_ g: Game, _ town: String, at p: V3, witness: Mob) {
        let fresh = !isHostile(town)
        state.hostile[town] = hostileSeconds
        state.heat[town] = hostileHeat
        for o in g.mobs.mobs where isTownsperson(o) && simd_length(o.pos - p) < 64 {
            if var v = o.villager, fresh { v.addGossip(.majorNeg, 12); o.villager = v }
            if o.villager?.role == "sheriff" {
                if fresh { o.face(g.player.pos); pending.append((o, g.clock + 2.5)); Townsfolk.townLastLine = -100; TownVoice.speak(g, o, .challenge) }
                else { o.town.anger = max(o.town.anger, hostileSeconds) }
            } else if o.townWeapon != .none && !o.baby {
                o.town.anger = max(o.town.anger, 60)
            } else {
                o.panic = max(o.panic, 8)
            }
        }
        if fresh {
            if witness.villager?.role != "sheriff" { Townsfolk.townLastLine = -100; TownVoice.speak(g, witness, .angry) }
            g.onToast?("\(town) has turned on you!")
        }
    }

    // MARK: Every frame (from HudExtras.tick); real work once a second.

    static func tick(_ g: Game) {
        if worldSeed != g.world.seed { reset(); worldSeed = g.world.seed }
        // Sheriffs draw after their challenge.
        if !pending.isEmpty {
            pending.removeAll { (m, t) in
                guard g.clock >= t else { return false }
                if m.health > 0 { m.town.anger = max(m.town.anger, hostileSeconds) }
                return true
            }
        }
        guard g.clock - lastTick >= 1 || lastTick < 0 else { return }
        let dt = Float(lastTick < 0 ? 1 : min(5, g.clock - lastTick))
        lastTick = g.clock
        if let m = g.menu, openPos != nil { checkTaking(g, m) }
        // Heat cools; hostility runs out.
        for (t, h) in state.heat where !isHostile(t) {
            let n = h - dt / 90
            state.heat[t] = n > 0 ? n : nil
        }
        for (t, s) in state.hostile {
            let n = s - dt
            if n <= 0 {
                state.hostile[t] = nil
                state.heat[t] = 1
                g.onToast?("\(t) has calmed down.")
            } else {
                state.hostile[t] = n
            }
        }
        // Which town the player is in.
        guard g.dim.dim == .overworld, g.alive else { inTown = nil; return }
        var nearest: Mob?
        var nd: Float = 48
        var sheriffHere: Mob?
        for o in g.mobs.mobs where isTownsperson(o) {
            let d = simd_length(o.pos - g.player.pos)
            if d < nd && !o.baby { nd = d; nearest = o }
            if o.villager?.role == "sheriff" && d < 160 { sheriffHere = o }
        }
        guard let near = nearest else { inTown = nil; return }
        let here = town(of: near, g)
        inTown = here
        let day = Int(g.time / DAY_LENGTH)
        if let s = sheriffHere, town(of: s, g) == here { state.appointed[here] = day }
        else if day - (state.appointed[here] ?? -99) >= 3, isTownSpot(g, IVec3(Int(floor(near.pos.x)), Int(floor(near.pos.y)), Int(floor(near.pos.z)))) {
            appointSheriff(g, here, near: near)
        }
        // A hostile town keeps its armed folk on you while you're about.
        if isHostile(here) {
            for o in g.mobs.mobs where isTownsperson(o) && o.townWeapon != .none && !o.baby && simd_length(o.pos - g.player.pos) < 32 {
                o.town.anger = max(o.town.anger, 3)
            }
        }
        ambientChatter(g)
    }

    // A sheriff for a town that has none (older towns, or three days after the last one fell): next to the deputy
    // or a townsperson, on open ground.
    static func appointSheriff(_ g: Game, _ town: String, near: Mob) {
        let anchor = g.mobs.mobs.first { isTownsperson($0) && $0.villager?.role == "deputy" && TownLaw.town(of: $0, g) == town } ?? near
        let c = anchor.home ?? anchor.pos
        let w = g.world
        for k in 0..<16 {
            let a = Float(k) * 2.4
            let r: Float = 2 + Float(k % 4)
            let x = Int(floor(c.x + cosf(a) * r)), z = Int(floor(c.z + sinf(a) * r))
            var y = Int(floor(c.y)) + 3
            while y > Int(floor(c.y)) - 4 && !(Blocks.collide[Int(w.block(x, y - 1, z))] && !Blocks.collide[Int(w.block(x, y, z))]) { y -= 1 }
            guard y > Int(floor(c.y)) - 4, !Blocks.isLiquid(w.block(x, y, z)) else { continue }
            let m = Mob(.villager, at: V3(Float(x) + 0.5, Float(y), Float(z) + 0.5))
            if m.collides(m.pos, w) { continue }
            m.home = anchor.home ?? m.pos
            m.persistent = true
            Townsfolk.setup(m, tag: "sheriff", game: g)
            if var v = m.villager { v.town = town; m.villager = v }
            g.mobs.mobs.append(m)
            state.appointed[town] = Int(g.time / DAY_LENGTH)
            return
        }
    }

    // Now and then a townsperson near the player says something (one voice at a time, ~20 s apart).
    static func ambientChatter(_ g: Game) {
        guard g.menu == nil, g.clock - Townsfolk.townLastLine > 20, g.clock - lastAmbient > 20, Rand.float(in: 0..<1) < 0.12 else { return }
        let cands = g.mobs.mobs.filter {
            isTownsperson($0) && !$0.lying && $0.town.anger <= 0 && $0.panic <= 0 && simd_length($0.pos - g.player.pos) < 14
                && simd_length($0.pos - g.player.pos) > 3 && g.world.canSee($0.eye, g.player.eye)
        }
        guard let m = cands.randomElement() else { return }
        lastAmbient = g.clock
        if let inT = inTown, isHostile(inT) { TownVoice.speak(g, m, .angry); return }
        TownVoice.speak(g, m, g.dayFraction > 0.5 ? .night : .chatter)
    }

    // The sheriff's role (Townsfolk.setup with the "sheriff" tag): a man's name, so his voice fits.
    static func deputize(_ v: inout VillagerData) {
        v.role = "sheriff"; v.locked = true; v.profession = "none"
        if Townsfolk.isWoman(v), let p = v.person {
            let men = Townsfolk.firstNames.filter { !Townsfolk.women.contains($0) }
            let last = p.split(separator: " ").last.map(String.init) ?? "Hale"
            v.person = "\(men[(v.look ?? 0) % men.count]) \(last)"
        }
    }

    // MARK: The sheriff's revolver (from townDefend)

    static func shoot(_ m: Mob, _ g: Game) {
        let foe = m.town.foe
        let target = foe?.eye ?? g.player.eye
        let muzzle = m.eye + m.forward * 0.5 + V3(0, -0.2, 0)
        g.sfx(.gun(WeaponAudio.sidearmSlot), 1, at: muzzle)
        g.particles.smoke(at: muzzle)
        guard g.world.canSee(muzzle, target) else { return }
        let d = simd_length(target - muzzle)
        let chance: Float = d < 6 ? 0.85 : 0.7
        guard Rand.float(in: 0..<1) < chance else {
            if foe == nil { g.sfx(.bulletWhizz, 0.8, at: g.player.eye) }
            return
        }
        if let f = foe {
            f.hit(from: m.pos, damage: 8, knockback: 0.3)
        } else {
            g.hurtPlayer(TownWeapon.revolver.damage, from: m.pos, cause: "was shot by Sheriff \(m.villager?.person ?? "")", knockback: 0.4, attacker: m)
        }
    }
}

extension Mob {
    // Every villager is a townsperson: one without a name or town (made by a path that doesn't set one up: breeding,
    // a cure, an egg, a raid, a pre-town save) becomes one the first frame it's updated (MobManager.update), before
    // it's drawn or talked to, instead of at its first job check up to 5 s later.
    func becomeTownsperson(_ g: Game) {
        if villager == nil {
            var v = VillagerData()
            v.type = Villagers.type(for: g.world.gen.column(Int(floor(pos.x)), Int(floor(pos.z))).biome)
            if !baby && Rand.float(in: 0..<1) < 0.12 { v.profession = "nitwit" }
            villager = v
        }
        Townsfolk.setup(self, game: g)
    }
}

extension Game {
    // Spoken greeting (TownVoice) for the proximity hello and a tap: recorded lines most of the time, the older
    // text lines (the hour, the town's mood, raids) otherwise.
    func townGreet(_ m: Mob, _ v: VillagerData) {
        if TownLaw.isHostile(self, m) { TownVoice.speak(self, m, .angry); return }
        if v.reputation > -60 && raid == nil && Rand.float(in: 0..<1) < 0.7 {
            let ctx: TownVoice.Ctx = dayFraction > 0.5 ? .night : (Rand.float(in: 0..<1) < 0.55 ? .greet : .chatter)
            if TownVoice.speak(self, m, ctx) != nil { return }
        }
        Townsfolk.say(self, m, Townsfolk.greeting(v, self))
    }
}
