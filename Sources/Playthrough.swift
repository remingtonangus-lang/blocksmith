import Foundation
import Metal
import simd

// Scripted playthrough (`Blocksmith --playthrough [--seed N] [--only overworld,emberdeep,...]`): drives the real
// Game (tick, input, mining, crafting recipes, furnaces, portals, mobs, projectiles) from a fresh world to the
// credits and through the Blight, the way a player would. Every step prints PASS / FAIL / INFO; the process exits
// non-zero when any hard check fails, so CI catches anything that blocks progression.
//
// Where a real player repeats the same action many times (chopping 20 logs, mining 10 obsidian) the test does it
// for real once or twice and adds the rest to the inventory, logged as "bulk".
final class Playthrough {
    let game: Game
    var fails: [String] = []
    var infos: [String] = []
    let t0 = CFAbsoluteTimeGetCurrent()
    var simSeconds: Double = 0
    var damageTaken = 0          // health the player lost while the test kept topping it up

    init(game: Game) { self.game = game }
    var world: World { game.world }
    var inv: ItemContainer { game.inventory.main }

    // MARK: Reporting

    func check(_ ok: Bool, _ what: String) {
        print("\(ok ? "PASS" : "FAIL") \(what)")
        if !ok { fails.append(what) }
    }
    func info(_ s: String) { print("INFO \(s)"); infos.append(s) }
    func section(_ s: String) { print(String(format: "---- %@ (%.1f s wall, %.0f s game)", s, CFAbsoluteTimeGetCurrent() - t0, simSeconds)) }

    // MARK: Ticking

    // Real frames through Game.tick. `pin` holds the player still (hovering) between frames; `keepAlive` tops up
    // health / hunger and counts the damage a real player would have had to heal.
    @discardableResult
    func tick(_ seconds: Double, pin: V3? = nil, keepAlive: Bool = true, until done: (() -> Bool)? = nil) -> Bool {
        let n = max(1, Int(seconds * 20))
        for _ in 0..<n {
            let before = game.health
            game.tick(0.05)
            simSeconds += 0.05
            if keepAlive {
                if game.health < before { damageTaken += before - game.health }
                handleDeath()
                game.health = max(game.health, 20)
                game.hunger = 20
                game.saturation = 5
                game.air = 15
                game.onFire = 0
            }
            if let p = pin { game.player.pos = p; game.player.vel = .zero }
            if let d = done, d() { return true }
        }
        return done == nil
    }

    // One real frame; health topped up and the death screen handled like tick() does.
    func frame(pin: V3? = nil) {
        let before = game.health
        game.tick(0.05)
        simSeconds += 0.05
        if game.health < before { damageTaken += before - game.health }
        handleDeath()
        game.health = max(game.health, 20)
        if let p = pin { game.player.pos = p; game.player.vel = .zero }
    }

    // The death screen: log what killed the player, get up where they fell and pick their things back up.
    var deaths = 0
    var inDeath = false
    func handleDeath() {
        guard !inDeath, let dm = game.menu as? DeathMenu else { return }
        inDeath = true
        defer { inDeath = false }
        deaths += 1
        if deaths > 25 {
            // A death loop: stop here with the report rather than running into the CI timeout.
            check(false, "no death loop (\(deaths) deaths, last: \(dm.message))")
            print("playthrough: aborted, \(fails.count) failed checks")
            for f in fails { print("  failed: \(f)") }
            exit(1)
        }
        let at = game.player.pos
        info(String(format: "died (%@) at %.0f %.0f %.0f in %@", dm.message, at.x, at.y - Float(YOFF), at.z, game.dim.dim.rawValue))
        game.menu = nil
        game.alive = true
        game.health = 20
        damageTaken += 20
        collect(near: at, 16)
        if game.inventory.armorPoints > 0 || count("diamond_chestplate") > 0 { wearArmor() }
    }

    // MARK: Inventory

    func id(_ n: String) -> ItemID { Items.has(n) ? Items.id(n) : 0 }
    func count(_ n: String) -> Int { Items.has(n) ? inv.countOf(Items.id(n)) : 0 }
    // Keeps a few slots free: a real player drops mob junk (flesh, bones, string, blocks) when the bag fills up.
    static let keepWords = ["pickaxe", "sword", "bow", "arrow", "_axe", "shovel", "helmet", "chestplate", "leggings", "boots", "elytra",
                            "ender_pearl", "ender_eye", "dragon_egg", "torch", "soul_sand", "skull", "obsidian", "flint_and_steel", "blaze",
                            "nether_star", "diamond", "iron_ingot", "bucket", "crafting_table", "furnace", "glass", "shield", "bread",
                            "cooked", "golden", "stick", "planks", "log", "cobblestone", "raw_iron", "coal"]
    func makeRoom(_ need: Int = 4) {
        var free = (0..<36).filter { inv[$0].isEmpty }.count
        guard free < need else { return }
        var dropped: [String] = []
        for i in (0..<36).reversed() where free < need + 4 && !inv[i].isEmpty && i != game.selected {
            let k = Items.key(inv[i].item)
            if Playthrough.keepWords.contains(where: { k.contains($0) }) { continue }
            dropped.append("\(inv[i].count) \(k)")
            inv[i] = .empty
            free += 1
        }
        if !dropped.isEmpty { info("bag full: dropped \(dropped.joined(separator: ", "))") }
    }

    func give(_ n: String, _ c: Int, bulk: String? = nil) {
        guard Items.has(n) else { check(false, "item \(n) exists"); return }
        makeRoom()
        var left = c
        while left > 0 {
            let k = min(left, Items.def(Items.id(n)).maxStack)
            game.inventory.add(ItemStack(Items.id(n), k))
            left -= k
        }
        if let b = bulk { info("bulk: +\(c) \(n) (\(b))") }
    }
    func hold(_ n: String) -> Bool {
        guard Items.has(n), let i = (0..<36).first(where: { inv[$0].item == Items.id(n) && inv[$0].count > 0 }) else { return false }
        if i != game.selected {
            let a = inv[game.selected]
            inv[game.selected] = inv[i]
            inv[i] = a
        }
        return true
    }
    func holdNothing() {
        let s = inv[game.selected]
        if s.isEmpty { return }
        if let e = (0..<36).first(where: { $0 != game.selected && inv[$0].isEmpty }) { inv[e] = s; inv[game.selected] = .empty }
    }

    // Crafting through the recipe table (the same Recipes.match the crafting screens use): rows over a 3x3 grid.
    @discardableResult
    func craft(_ rows: [String], _ key: [Character: String], _ expect: String, times: Int = 1) -> Bool {
        var grid = [ItemID](repeating: 0, count: 9)
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch != " " {
                guard let n = key[ch], Items.has(n) else { check(false, "craft \(expect): ingredient '\(ch)' known"); return false }
                grid[x + y * 3] = Items.id(n)
            }
        }
        var need: [ItemID: Int] = [:]
        for g in grid where g != 0 { need[g, default: 0] += 1 }
        for _ in 0..<times {
            guard let r = Recipes.match(grid, 3, 3) else { check(false, "craft \(expect): recipe matches"); return false }
            guard Items.key(r.result.item) == expect else { check(false, "craft \(expect): got \(Items.key(r.result.item))"); return false }
            for (g, n) in need where inv.countOf(g) < n {
                check(false, "craft \(expect): have \(n) \(Items.key(g)) (have \(inv.countOf(g)))"); return false
            }
            for (g, n) in need { inv.remove(g, n) }
            game.inventory.add(r.result)
        }
        return true
    }

    // MARK: World helpers

    func key(_ p: IVec3) -> String { Blocks.key(world.block(p.x, p.y, p.z)) }
    func baseKey(_ b: BlockID) -> String { Blocks.key(Blocks.groupBase[Int(b)]) }
    func clear(_ p: IVec3) -> Bool { let b = world.block(p.x, p.y, p.z); return !Blocks.collide[Int(b)] && !Blocks.isLiquid(b) }
    func carvable(_ p: IVec3) -> Bool {
        let b = world.block(p.x, p.y, p.z)
        let k = baseKey(b)
        return Blocks.hardness[Int(b)] >= 0 && !["end_portal_frame", "end_portal", "spawner", "chest", "nether_portal", "dragon_egg"].contains(k)
            && b != PORTAL_X && b != PORTAL_Z && b != LAVA
    }
    func center(_ p: IVec3) -> V3 { V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5) }

    func aim(at c: V3) {
        let d = c - game.player.eye
        game.player.yaw = atan2f(-d.x, -d.z)
        game.player.pitch = atan2f(d.y, simd_length(V2(d.x, d.z)))
    }

    // Hovers the player beside block `p` with the eye level with it (a player standing on a ledge / pillar next
    // to it), clearing the two cells the body needs if nothing better is open. Returns the pinned feet position.
    @discardableResult
    func standBeside(_ p: IVec3) -> V3 {
        let dirs = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)]
        var pick: IVec3?
        for d in dirs where pick == nil { let n = p + d; if clear(n) && clear(n + IVec3(0, -1, 0)) { pick = n } }
        for d in dirs where pick == nil { let n = p + d; if clear(n) && carvable(n + IVec3(0, -1, 0)) { pick = n } }
        for d in dirs where pick == nil { let n = p + d; if carvable(n) && carvable(n + IVec3(0, -1, 0)) { pick = n } }
        let n = pick ?? p + IVec3(1, 0, 0)
        for q in [n, n + IVec3(0, -1, 0)] where !clear(q) { world.setBlock(q.x, q.y, q.z, AIR) }
        game.player.flying = true
        let feet = V3(Float(n.x) + 0.5, Float(n.y) - 0.99, Float(n.z) + 0.5)
        game.player.pos = feet
        game.player.vel = .zero
        clearMobs(near: feet, 5)
        aim(at: center(p))
        return feet
    }

    func clearMobs(near p: V3, _ r: Float) {
        game.mobs.mobs.removeAll { !$0.persistent && $0.kind.spec.behavior != .dragon && simd_length($0.pos - p) < r }
    }

    // Mines a block with the held item by holding the attack button (real interact / mining code).
    @discardableResult
    func mine(_ p: IVec3, maxSeconds: Double = 40) -> Bool {
        let b0 = world.block(p.x, p.y, p.z)
        let feet = standBeside(p)
        let inp = game.input
        var ok = false
        for i in 0..<Int(maxSeconds * 20) {
            aim(at: center(p))
            inp.leftDown = true
            if i == 0 { inp.leftClicked = true }
            game.tick(0.05)
            simSeconds += 0.05
            game.player.pos = feet; game.player.vel = .zero
            game.health = max(game.health, 20)
            handleDeath()
            if world.block(p.x, p.y, p.z) != b0 { ok = true; break }
        }
        inp.leftDown = false
        game.tick(0.05)
        return ok
    }

    // Right-click on a block face (real interact / placement code). `face` is the clicked face's normal.
    func use(on p: IVec3) {
        standBeside(p)
        aim(at: center(p))
        game.input.rightClicked = true
        game.input.rightDown = true
        game.tick(0.05)
        game.input.rightDown = false
        game.tick(0.05)
        simSeconds += 0.1
    }

    // Walks (teleports) over every dropped item within `r` blocks so it gets picked up.
    func collect(near c: V3, _ r: Float = 12) {
        makeRoom(6)
        _ = tick(0.6)
        for _ in 0..<3 {
            let items = game.drops.items.filter { simd_length($0.pos - c) < r }
            if items.isEmpty { break }
            for e in items {
                game.player.pos = e.pos
                game.player.vel = .zero
                _ = tick(0.1, pin: e.pos)
            }
        }
    }

    func findBlock(near c: IVec3, radius r: Int, yRange: ClosedRange<Int>, _ match: (String) -> Bool) -> IVec3? {
        var best: IVec3?
        var bd = Int.max
        for y in yRange { for z in (c.z - r)...(c.z + r) { for x in (c.x - r)...(c.x + r) {
            let b = world.block(x, y, z)
            if b == AIR { continue }
            if match(baseKey(b)) {
                let d = (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y) + (z - c.z) * (z - c.z)
                if d < bd { bd = d; best = IVec3(x, y, z) }
            }
        } } }
        return best
    }

    // Real bow shot at a point: hold use for a full draw, release.
    func shoot(at c: V3, from feet: V3) { shoot(from: feet) { c } }

    // Tracks a moving mob while drawing: aims at its centre, led by its velocity over the arrow's flight time.
    func shoot(at m: Mob, from feet: V3, height: Float = 0.5) {
        shoot(from: feet) {
            let c = m.pos + V3(0, m.height * height, 0)
            return c + m.vel * (simd_length(c - self.game.player.eye) / 58)
        }
    }

    func shoot(from feet: V3, target: () -> V3) {
        if !hold("bow") { give("bow", 1, bulk: "a new bow"); _ = hold("bow") }
        if count("arrow") < 4 { give("arrow", 64) }
        let inp = game.input
        for _ in 0..<22 {
            // Aim over the target to allow for the drop (gravity 20 b/s², 60 b/s at full draw).
            let c = target()
            let t = simd_length(c - game.player.eye) / 58
            aim(at: c + V3(0, 10 * t * t, 0))
            inp.rightDown = true
            frame(pin: feet)
        }
        inp.rightDown = false
        frame(pin: feet)
    }

    // Melee swing at a mob with a full attack charge (real interact attack path). Without `feet` the player
    // follows the mob at `offset` (chasing it) while the swing charges.
    func swing(at m: Mob, from feet: V3? = nil, offset: V3 = V3(2, 0, 0)) {
        let inp = game.input
        for _ in 0..<13 {
            frame(pin: feet ?? chaseSpot(m, offset))
        }
        aim(at: m.pos + V3(0, min(m.height * 0.5, 1.5), 0))
        inp.leftClicked = true
        frame(pin: feet ?? chaseSpot(m, offset))
    }

    // Where a chasing player would stand to hit a mob: the preferred side if the body fits there, else another.
    func chaseSpot(_ m: Mob, _ pref: V3) -> V3 {
        func cell(_ p: V3) -> IVec3 { IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))) }
        let sides = [pref, V3(-pref.x, pref.y, -pref.z), V3(pref.z, pref.y, pref.x), V3(-pref.z, pref.y, -pref.x)]
        for o in sides {
            let f = m.pos + o
            if clear(cell(f + V3(0, 0.3, 0))) && clear(cell(f + V3(0, 1.62, 0))) { return f }
        }
        return m.pos + V3(0, m.height + 0.3, 0)
    }

    // MARK: Run

    static func run() -> Int32 {
        guard let device = MTLCreateSystemDefaultDevice() else { print("no Metal device"); return 1 }
        let seed = UInt64(arg("--seed") ?? "") ?? 12345
        // A real (temporary) save folder: chunks the player changed survive dimension changes as in the game.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("blocksmith-playthrough-\(seed)", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        let save = SaveManager(dir: dir)
        let world = World(seed: seed, device: device, save: save, dim: .overworld)
        world.renderDistance = 8
        let game = Game(world: world, save: save, persistent: true)
        let t = Playthrough(game: game)
        let only = Set((arg("--only") ?? "").split(separator: ",").map(String.init))
        func want(_ s: String) -> Bool { only.isEmpty || only.contains(s) }
        print("playthrough: seed \(seed)")
        t.start()
        if want("overworld") { t.overworld() } else { t.kit(["diamond_pickaxe", "flint_and_steel", "diamond_sword", "bow"]); t.give("arrow", 64); t.give("obsidian", 10) }
        if want("emberdeep") { t.emberdeep() } else { t.give("blaze_rod", 7, bulk: "stage skipped"); t.give("ender_pearl", 12, bulk: "stage skipped") }
        if want("stronghold") { t.eyesAndStronghold() }
        if want("end") { t.theHollow() }
        if want("blight") { t.blight() }
        t.advancementsCheck(only.isEmpty)
        t.section("summary")
        t.info("deaths: \(t.deaths), damage healed by the test: \(t.damageTaken) half-hearts")
        print(String(format: "playthrough: %ld failed checks, %.0f s of game time in %.1f s wall", t.fails.count, t.simSeconds, CFAbsoluteTimeGetCurrent() - t.t0))
        for f in t.fails { print("  failed: \(f)") }
        return t.fails.isEmpty ? 0 : 1
    }

    func kit(_ names: [String]) { for n in names { give(n, 1) }; wearArmor() }

    func wearArmor() {
        let pieces = ["golden_helmet", "diamond_chestplate", "diamond_leggings", "diamond_boots"]
        for (slot, n) in pieces.enumerated() {
            if count(n) == 0 { give(n, 1, bulk: "armour") }
            if let i = (0..<36).first(where: { Items.key(inv[$0].item) == n }) { game.inventory.armor[slot] = inv[i]; inv[i] = .empty }
        }
        check(game.inventory.armorPoints >= 17, "armour: \(game.inventory.armorPoints) armour points worn")
    }

    // The story advancements a full run must have earned.
    func advancementsCheck(_ full: Bool) {
        section("advancements")
        tick(1.1)
        let must = ["nether/obtain_blaze_rod", "end/root", "end/kill_dragon", "end/dragon_egg", "end/enter_end_gateway", "nether/summon_wither"]
        for id in must where Advancements.index[id] != nil {
            if full { check(game.advancements.contains(id), "advancement \(id)") } else { info("advancement \(id): \(game.advancements.contains(id))") }
        }
        info("\(game.advancements.count) advancements earned: \(game.advancements.sorted().joined(separator: ", "))")
    }

    func start() {
        section("spawn")
        game.paused = false
        game.closeMenu()
        game.survival = true
        game.difficulty = 2
        game.time = DAY_LENGTH * 0.3
        for i in 0..<36 { inv[i] = .empty }
        let sp = game.spawnPoint
        _ = world.loadSync(center: sp, radius: 4)
        let top = world.topY(Int(floor(sp.x)), Int(floor(sp.z)))
        game.player.pos = V3(sp.x, Float(top + 1), sp.z)
        game.player.flying = false
        _ = tick(3)
        let p = game.player.pos
        let under = world.block(Int(floor(p.x)), Int(floor(p.y - 0.05)), Int(floor(p.z)))
        check(game.player.onGround && Blocks.collide[Int(under)], "spawn: standing on solid ground (\(baseKey(under)) at y \(Int(floor(p.y)) - YOFF))")
        check(!Blocks.isLiquid(world.block(Int(floor(p.x)), Int(floor(p.y + 0.2)), Int(floor(p.z)))), "spawn: not in water or lava")
        check(game.alive && game.health == 20, "spawn: alive and healthy")
    }

    // MARK: Overworld: wood, stone, iron, diamonds, obsidian, a lit portal

    func overworld() {
        section("gather + craft")
        let sp = game.player.pos
        let home = IVec3(Int(floor(sp.x)), Int(floor(sp.y)), Int(floor(sp.z)))
        // Wood by hand.
        var logs = 0
        for _ in 0..<3 {
            var near = findBlock(near: home, radius: 40, yRange: max(0, home.y - 8)...min(CH - 1, home.y + 20), { $0.hasSuffix("_log") })
            if near == nil {
                // Open country (the realistic terrain has treeless plains and steppe): walk further for a tree.
                _ = world.loadSync(center: V3(Float(home.x), Float(home.y), Float(home.z)), radius: 7)
                near = findBlock(near: home, radius: 100, yRange: max(0, home.y - 30)...min(CH - 1, home.y + 40), { $0.hasSuffix("_log") })
                if let n = near { info("nearest tree is \(Int(simd_length(V2(Float(n.x - home.x), Float(n.z - home.z))))) blocks away") }
            }
            guard let lp = near else { break }
            holdNothing()
            let lk = baseKey(world.block(lp.x, lp.y, lp.z))
            if mine(lp) { collect(near: center(lp)) }
            logs = (0..<36).reduce(0) { $0 + (Items.key(inv[$1].item).hasSuffix("_log") ? inv[$1].count : 0) }
            if logs == 0 { info("log \(lk) at \(lp.x) \(lp.y - YOFF) \(lp.z) gave no log item") }
        }
        check(logs >= 1, "gather: logs mined by hand (\(logs))")
        let logSlot = (0..<36).first { Items.key(inv[$0].item).hasSuffix("_log") }
        let logKey = logSlot.map { Items.key(inv[$0].item) } ?? "oak_log"
        if logs < 6 { give(logKey, 6 - logs, bulk: "more trees") }
        // Planks from whatever wood this was.
        var planks = "oak_planks"
        if let r = Recipes.match([id(logKey), 0, 0, 0, 0, 0, 0, 0, 0], 3, 3) { planks = Items.key(r.result.item) }
        craft(["L"], ["L": logKey], planks, times: 6)
        check(count(planks) >= 24, "craft: \(count(planks)) \(planks)")
        craft(["P", "P"], ["P": planks], "stick", times: 5)
        craft(["PP", "PP"], ["P": planks], "crafting_table")
        craft(["PPP", " S ", " S "], ["P": planks, "S": "stick"], "wooden_pickaxe")
        check(count("wooden_pickaxe") == 1 && count("crafting_table") == 1, "craft: crafting table + wooden pickaxe")

        // Stone with the wooden pickaxe (and not by hand).
        section("stone age")
        guard let st = findBlock(near: home, radius: 12, yRange: max(1, home.y - 14)...home.y, { $0 == "stone" }) else {
            check(false, "stone near spawn"); return
        }
        holdNothing()
        let handTime = Mining.breakSeconds(world.block(st.x, st.y, st.z), .empty, onGround: true, inWater: false)
        check(hold("wooden_pickaxe"), "hold wooden pickaxe")
        var mined = 0
        var cur = st
        for _ in 0..<3 {
            if mine(cur) { mined += 1; collect(near: center(cur), 24) }       // a drop can fall into a cave below
            cur = findBlock(near: cur, radius: 3, yRange: (cur.y - 2)...(cur.y + 1), { $0 == "stone" }) ?? cur
        }
        check(count("cobblestone") >= 2, "mine: \(count("cobblestone")) cobblestone with a wooden pickaxe (\(mined) mined; bare hand would take \(handTime) s and drop nothing)")
        if count("cobblestone") < 11 { give("cobblestone", 11 - count("cobblestone"), bulk: "more stone") }
        craft(["CCC", " S ", " S "], ["C": "cobblestone", "S": "stick"], "stone_pickaxe")
        craft(["CCC", "C C", "CCC"], ["C": "cobblestone"], "furnace")
        check(count("stone_pickaxe") == 1 && count("furnace") == 1, "craft: stone pickaxe + furnace")

        // Iron: find ore, mine with the stone pickaxe, smelt in a placed furnace.
        section("iron age")
        let r = 4 * CS
        let ironOre = findBlock(near: home, radius: r, yRange: 1...min(CH - 1, home.y), { $0 == "iron_ore" || $0 == "deepslate_iron_ore" })
        check(ironOre != nil, "worldgen: iron ore within \(r) blocks of spawn")
        if let io = ironOre {
            // A wooden pickaxe can't harvest it.
            check(!Mining.canHarvest(world.block(io.x, io.y, io.z), ItemStack(id("wooden_pickaxe"), 1)), "rules: wooden pickaxe can't harvest iron ore")
            // Up to four ore blocks (one can sit in water or over a drop the item falls into).
            var tried: [IVec3] = []
            var next: IVec3? = io
            while let o = next, tried.count < 4, count("raw_iron") == 0 {
                tried.append(o)
                let held = hold("stone_pickaxe")
                let k = baseKey(world.block(o.x, o.y, o.z))
                let ok = mine(o)
                if ok { collect(near: center(o)) }
                if count("raw_iron") == 0 {
                    info(String(format: "iron attempt %ld at %ld %ld %ld (%@, pickaxe %@): mined %@, now %@, %ld drops near",
                                tried.count, o.x, o.y - YOFF, o.z, k, held ? "held" : "missing", ok ? "yes" : "no",
                                baseKey(world.block(o.x, o.y, o.z)), game.drops.items.filter { simd_length($0.pos - self.center(o)) < 12 }.count))
                }
                next = findBlock(near: home, radius: r, yRange: 1...min(CH - 1, home.y), { $0 == "iron_ore" || $0 == "deepslate_iron_ore" })
                if let n = next, tried.contains(n) { next = nil }
            }
            check(count("raw_iron") >= 1, "mine: raw iron with a stone pickaxe (\(count("raw_iron")))")
        }
        if let co = findBlock(near: home, radius: r, yRange: 1...min(CH - 1, home.y), { $0 == "coal_ore" || $0 == "deepslate_coal_ore" }) {
            _ = hold("stone_pickaxe")
            if mine(co) { collect(near: center(co)) }
        }
        info("coal from ore: \(count("coal"))")
        if count("raw_iron") < 6 { give("raw_iron", 6 - count("raw_iron"), bulk: "more iron ore") }
        // Place the furnace with a right click on the ground next to spawn, then smelt.
        // (The first solid block: shrubs, grass and leaf litter on top don't count; the furnace replaces them.)
        var fy = world.topY(home.x + 2, home.z)
        while fy > 1 && !Blocks.collide[Int(world.block(home.x + 2, fy, home.z))] { fy -= 1 }
        let fp = IVec3(home.x + 2, fy + 1, home.z)
        // A clear pad: open air around the spot and the player's line of sight, solid ground under it (spawn can be a
        // tree canopy, whose leaves would catch the click).
        for dx in -1...1 { for dz in -1...3 { for dy in 0...4 { world.setBlock(fp.x + dx, fp.y + dy, fp.z + dz, AIR) } } }
        world.setBlock(fp.x, fp.y - 1, fp.z, STONE)
        _ = hold("furnace")
        standBeside(fp + IVec3(0, -1, 0))
        game.player.pos = V3(Float(fp.x) + 0.5, Float(fp.y) + 1.5, Float(fp.z) + 2.5)
        aim(at: V3(Float(fp.x) + 0.5, Float(fp.y), Float(fp.z) + 0.5))
        game.input.rightClicked = true
        game.tick(0.05)
        let placed = baseKey(world.block(fp.x, fp.y, fp.z)).hasSuffix("furnace")
        check(placed, "place: furnace placed with a right click (\(key(fp)))")
        if let be = world.blockEntities[fp], placed {
            be.container[0] = ItemStack(id("raw_iron"), 6)
            inv.remove(id("raw_iron"), 6)
            be.container[1] = count("coal") > 0 ? ItemStack(id("coal"), 1) : ItemStack(id(planks), 5)
            _ = tick(62, pin: game.player.pos) { be.container[2].count >= 6 }
            check(be.container[2].count >= 6 && Items.key(be.container[2].item) == "iron_ingot", "smelt: \(be.container[2].count) iron ingots after \(Int(simSeconds)) s")
            game.inventory.add(be.container[2]); be.container[2] = .empty
        } else {
            check(false, "furnace block entity")
            give("iron_ingot", 6, bulk: "no furnace")
        }
        craft(["III", " S ", " S "], ["I": "iron_ingot", "S": "stick"], "iron_pickaxe")
        give("flint", 1, bulk: "gravel")
        craft(["I ", " F"], ["I": "iron_ingot", "F": "flint"], "flint_and_steel")
        check(count("iron_pickaxe") == 1 && count("flint_and_steel") == 1, "craft: iron pickaxe + flint and steel")

        // Diamonds with the iron pickaxe.
        section("diamonds")
        var dia: IVec3?
        for rr in [4 * CS, 5 * CS] where dia == nil {
            _ = world.loadSync(center: sp, radius: rr / CS)
            dia = findBlock(near: IVec3(home.x, 0, home.z), radius: rr, yRange: 1...(YOFF + 16), { $0 == "diamond_ore" || $0 == "deepslate_diamond_ore" })
        }
        check(dia != nil, "worldgen: diamond ore within 80 blocks of spawn")
        if let d = dia {
            check(!Mining.canHarvest(world.block(d.x, d.y, d.z), ItemStack(id("stone_pickaxe"), 1)), "rules: stone pickaxe can't harvest diamond ore")
            // Up to four ores: a drop can fall into lava or a crevice down there (the iron step retries the same way).
            var next: IVec3? = d
            var attempts = 0
            while let o = next, count("diamond") == 0, attempts < 4 {
                attempts += 1
                _ = hold("iron_pickaxe")
                let ok = mine(o)
                if ok { collect(near: center(o)) }
                if count("diamond") == 0 {
                    info(String(format: "diamond attempt %ld at %ld %ld %ld: mined %@, now %@, %ld drops near", attempts, o.x, o.y - YOFF, o.z,
                                ok ? "yes" : "no", baseKey(world.block(o.x, o.y, o.z)), game.drops.items.filter { simd_length($0.pos - self.center(o)) < 12 }.count))
                    if baseKey(world.block(o.x, o.y, o.z)).hasSuffix("diamond_ore") { world.setBlock(o.x, o.y, o.z, STONE) }
                    next = findBlock(near: IVec3(home.x, 0, home.z), radius: 5 * CS, yRange: 1...(YOFF + 16), { $0 == "diamond_ore" || $0 == "deepslate_diamond_ore" })
                }
            }
            check(count("diamond") >= 1, "mine: diamond with an iron pickaxe at y \(d.y - YOFF) (\(count("diamond")), \(attempts) ore\(attempts == 1 ? "" : "s"))")
        }
        if count("diamond") < 5 { give("diamond", 5 - count("diamond"), bulk: "more diamonds") }
        craft(["DDD", " S ", " S "], ["D": "diamond", "S": "stick"], "diamond_pickaxe")
        craft(["D", "D", "S"], ["D": "diamond", "S": "stick"], "diamond_sword")
        give("string", 3, bulk: "spiders")
        craft([" SX", "S X", " SX"], ["S": "stick", "X": "string"], "bow")
        give("flint", 4, bulk: "gravel"); give("feather", 4, bulk: "chickens")
        craft(["F", "S", "E"], ["F": "flint", "S": "stick", "E": "feather"], "arrow", times: 4)
        check(count("diamond_pickaxe") == 1 && count("bow") == 1 && count("arrow") >= 16, "craft: diamond pickaxe, sword, bow, \(count("arrow")) arrows")
        // Armour for the Emberdeep: diamond, with a golden helmet so boarlings stay calm.
        give("diamond", 19, bulk: "more diamonds"); give("gold_ingot", 5, bulk: "gold ore")
        craft(["DDD", "D D"], ["D": "gold_ingot"], "golden_helmet")
        craft(["D D", "DDD", "DDD"], ["D": "diamond"], "diamond_chestplate")
        craft(["DDD", "D D", "D D"], ["D": "diamond"], "diamond_leggings")
        craft(["D D", "D D"], ["D": "diamond"], "diamond_boots")
        wearArmor()

        // Obsidian (lava + water) needs the diamond pickaxe.
        section("obsidian + portal")
        let op = IVec3(home.x - 3, world.topY(home.x - 3, home.z + 3) + 1, home.z + 3)
        world.setBlock(op.x, op.y, op.z, LAVA)
        world.setBlock(op.x, op.y + 1, op.z, WATER)
        _ = tick(3, pin: game.player.pos)
        let formed = key(op)
        check(formed == "obsidian", "fluids: water on a lava source makes obsidian (got \(formed))")
        if formed != "obsidian" { world.setBlock(op.x, op.y, op.z, OBSIDIAN) }
        world.setBlock(op.x, op.y + 1, op.z, AIR)
        let obsidian = world.block(op.x, op.y, op.z)
        check(!Mining.canHarvest(obsidian, ItemStack(id("iron_pickaxe"), 1)), "rules: iron pickaxe can't harvest obsidian")
        _ = hold("diamond_pickaxe")
        let secs = Mining.breakSeconds(obsidian, ItemStack(id("diamond_pickaxe"), 1), onGround: true, inWater: false)
        check(abs(secs - 9.4) < 0.2, "rules: obsidian takes 9.4 s with a diamond pickaxe (\(secs))")
        if mine(op, maxSeconds: 15) { collect(near: center(op)) }
        check(count("obsidian") >= 1, "mine: obsidian with a diamond pickaxe (\(count("obsidian")))")
        if count("obsidian") < 10 { give("obsidian", 10 - count("obsidian"), bulk: "more obsidian") }
        // Frame: 4 wide, 5 tall, no corners, built on flat ground a few blocks away.
        let bx = home.x + 6, bz = home.z - 6
        let gy = world.topY(bx, bz) + 1
        for dx in -1...4 { for dy in 0...6 { for dz in -2...2 { world.setBlock(bx + dx, gy + dy, bz + dz, AIR) } } }
        for dx in -1...4 { for dz in -2...2 { world.setBlock(bx + dx, gy - 1, bz + dz, STONE) } }
        var frame: [IVec3] = []
        for dx in 1...2 { frame.append(IVec3(bx + dx, gy, bz)); frame.append(IVec3(bx + dx, gy + 4, bz)) }
        for dy in 1...3 { frame.append(IVec3(bx, gy + dy, bz)); frame.append(IVec3(bx + 3, gy + dy, bz)) }
        for q in frame { world.setBlock(q.x, q.y, q.z, OBSIDIAN) }
        inv.remove(id("obsidian"), 10)
        // Light it: right-click the top of a bottom frame block from inside the frame.
        _ = hold("flint_and_steel")
        game.player.flying = true
        game.player.pos = V3(Float(bx) + 1.5, Float(gy) + 1.0, Float(bz) + 2.5)
        aim(at: V3(Float(bx) + 1.5, Float(gy) + 1.0, Float(bz) + 0.5))
        game.input.rightClicked = true
        game.tick(0.05)
        let lit = world.block(bx + 1, gy + 1, bz) == PORTAL_X || world.block(bx + 1, gy + 1, bz) == PORTAL_Z
        check(lit, "portal: flint and steel lights the frame (\(key(IVec3(bx + 1, gy + 1, bz))))")
        if !lit { _ = game.tryLightPortal(at: IVec3(bx + 1, gy + 1, bz)) }
        // Step in and wait (4 s in survival).
        game.player.flying = false
        let inside = V3(Float(bx) + 1.5, Float(gy + 1), Float(bz) + 0.5)
        game.player.pos = inside
        let went = tick(8, pin: nil) { self.game.dim.dim == .nether }
        check(went, "portal: standing in the portal for 4 s goes to the Emberdeep")
        overworldPortal = IVec3(bx + 1, gy + 1, bz)
    }
    var overworldPortal: IVec3?

    // MARK: Emberdeep: fortress, cinder rods, void pearls, the way home

    func emberdeep() {
        section("emberdeep")
        if game.dim.dim != .nether {
            check(false, "in the Emberdeep")
            game.changeDimension(to: .nether, at: V3(0.5, Float(YOFF + 70), 0.5))
        }
        let arrival = game.player.pos
        let ap = IVec3(Int(floor(arrival.x)), Int(floor(arrival.y)), Int(floor(arrival.z)))
        check(world.block(ap.x, ap.y, ap.z) == PORTAL_X || world.block(ap.x, ap.y, ap.z) == PORTAL_Z, "emberdeep: arrived inside a portal")
        _ = tick(2)
        check(game.alive && !Blocks.isLiquid(world.block(ap.x, ap.y, ap.z)), "emberdeep: arrival portal is safe")
        guard let fort = world.gen.structures?.nearest("fortress", x: ap.x, z: ap.z, maxRegions: 8) else {
            check(false, "emberdeep: a cinder fortress exists"); return
        }
        let fd = Int(simd_length(V2(Float(fort.anchor.x - ap.x), Float(fort.anchor.z - ap.z))))
        check(fd < 1500, "emberdeep: nearest fortress \(fd) blocks from the portal")
        let fc = V3(Float(fort.anchor.x) + 0.5, Float(fort.anchor.y), Float(fort.anchor.z) + 0.5)
        _ = world.loadSync(center: fc, radius: 5)
        game.player.flying = true
        game.player.pos = fc
        let spawners = world.blockEntities.filter { $0.value.kind == .spawner && $0.value.mob == "blaze" && fort.contains($0.key.x, $0.key.y, $0.key.z) }
        check(!spawners.isEmpty, "fortress: \(spawners.count) cinderwisp spawner(s)")
        guard let spos = spawners.first?.key else { return }
        // Stand on the spawner platform and let it spawn; fight what comes (full-charge sword hits).
        let feet = V3(Float(spos.x) + 3.5, Float(spos.y) - 1, Float(spos.z) + 0.5)
        game.player.pos = feet
        game.applyEffect(.fireResistance, amp: 0, seconds: 600)
        _ = hold("diamond_sword")
        var kills = 0, rods = count("blaze_rod")
        var spawned = false
        let startT = simSeconds
        // Up to 20 minutes: the spawner brings ~14 cinderwisps per 10 minutes and a 50% drop left 6 rods from 14
        // kills 40% of the time (run 350 failed on that, not on a bug).
        while rods < 7 && simSeconds - startT < 1200 {
            _ = tick(1, pin: feet)
            let blazes = game.mobs.mobs.filter { $0.kind == .blaze && $0.health > 0 && simd_length($0.pos - feet) < 20 }
            if !blazes.isEmpty { spawned = true }
            for b in blazes {
                // Close in and swing until it drops (the test player chases it).
                var n = 0
                while b.health > 0 && n < 12 {
                    swing(at: b, offset: V3(2, 0, 0))
                    n += 1
                }
                if b.health <= 0 { kills += 1 }
            }
            collect(near: feet, 20)
            // Rods that fell off the bridge: go down for those only (other drops would keep the player from the spawner).
            var fallen: [ItemEntity] = []
            for e in game.drops.items where !e.stack.isEmpty && Items.key(e.stack.item) == "blaze_rod" {
                let d: Float = simd_length(e.pos - feet)
                if d < 48 { fallen.append(e) }
            }
            for e in fallen {
                game.player.pos = e.pos
                game.player.vel = .zero
                _ = tick(0.1, pin: e.pos)
            }
            game.player.pos = feet
            rods = count("blaze_rod")
        }
        check(spawned, "fortress: the spawner makes cinderwisps")
        check(rods >= 7, "fortress: \(rods) cinder rods from \(kills) cinderwisps in \(Int(simSeconds - startT)) s")
        if kills > 0 { info(String(format: "cinder rod rate %.2f per kill (reference 0.5 without looting)", Float(rods) / Float(kills))) }
        if kills >= 10 {
            let rate: Float = Float(rods) / Float(kills)
            check(rate > 0.15 && rate < 0.9, String(format: "fortress: cinder rod rate %.2f per kill is plausible (reference 0.5)", rate))
        }
        if rods < 7 { give("blaze_rod", 7 - rods, bulk: "missing rods") }

        // Void pearls from voidwalkers (warped forests / night surface); melee kills.
        section("void pearls")
        var pearls = count("ender_pearl"), vw = 0
        while pearls < 12 && vw < 80 {
            let at = feet + V3(0, 0, 3)
            let m = Mob(.enderman, at: at + V3(0, 0, 2))
            m.aggro = false
            game.mobs.mobs.append(m)
            var n = 0
            while m.health > 0 && n < 12 {
                swing(at: m, offset: V3(0, 0, -2))
                n += 1
            }
            if m.health <= 0 { vw += 1 }
            let died = m.pos                            // strolls and hit teleports move it away from where it appeared
            game.mobs.mobs.removeAll { $0 === m && $0.health > 0 }
            collect(near: died, 8)
            pearls = count("ender_pearl")
        }
        check(pearls >= 12, "voidwalkers: \(pearls) void pearls from \(vw) kills")
        if pearls < 12 { give("ender_pearl", 12 - pearls, bulk: "missing pearls") }

        // Home through the arrival portal (it must still be there and lead back to the one we built).
        section("back to the surface")
        game.player.flying = false
        _ = world.loadSync(center: arrival, radius: 2)
        game.player.pos = arrival
        let home = tick(10) { self.game.dim.dim == .overworld }
        check(home, "portal: back to the Surface through the arrival portal")
        if let op = overworldPortal, home {
            let d = simd_length(V2(game.player.pos.x - Float(op.x), game.player.pos.z - Float(op.z)))
            check(d < 4, "portal: returned to the portal we built (\(Int(d)) blocks off)")
        }
        if !home { game.changeDimension(to: .overworld, at: game.spawnPoint) }
        // Step out of the portal.
        game.player.pos += V3(0, 0, 2)
        _ = tick(1)
    }

    // MARK: Seeker eyes, stronghold, hollow gate

    func eyesAndStronghold() {
        section("seeker eyes")
        if game.dim.dim != .overworld { game.changeDimension(to: .overworld, at: game.spawnPoint) }
        if count("blaze_rod") < 6 { give("blaze_rod", 6 - count("blaze_rod"), bulk: "stage setup") }
        if count("ender_pearl") < 12 { give("ender_pearl", 12 - count("ender_pearl"), bulk: "stage setup") }
        craft(["R"], ["R": "blaze_rod"], "blaze_powder", times: 6)
        craft(["PB"], ["P": "ender_pearl", "B": "blaze_powder"], "ender_eye", times: 12)
        check(count("ender_eye") >= 12, "craft: \(count("ender_eye")) seeker eyes")
        guard let sh = world.gen.structures?.nearest("stronghold", x: Int(game.player.pos.x), z: Int(game.player.pos.z)) else {
            check(false, "worldgen: a stronghold exists"); return
        }
        let shd = simd_length(V2(Float(sh.anchor.x), Float(sh.anchor.z)))
        check(shd > 1100 && shd < 3000, "worldgen: nearest stronghold \(Int(shd)) blocks from the origin (first ring 1280-2816)")
        // Throw one: it flies toward the stronghold.
        _ = hold("ender_eye")
        game.player.flying = false
        let from = game.player.pos
        let target = V2(Float(sh.anchor.x), Float(sh.anchor.z))
        let d0 = simd_length(V2(from.x, from.z) - target)
        game.player.pitch = 0.3
        game.input.rightClicked = true
        _ = tick(0.05)
        check(!game.eyes.isEmpty, "seeker eye: thrown with a right click")
        _ = tick(1.4)
        if let e = game.eyes.first {
            let d1 = simd_length(V2(e.pos.x, e.pos.z) - target)
            check(d0 - d1 > 8, String(format: "seeker eye: flew %.1f blocks toward the stronghold", d0 - d1))
        }
        _ = tick(2)
        collect(near: from, 16)
        check(game.eyes.isEmpty, "seeker eye: drops or shatters after its flight")
        if count("ender_eye") < 12 { give("ender_eye", 12 - count("ender_eye"), bulk: "eye shattered") }

        section("stronghold")
        let sc = V3(Float(sh.anchor.x) + 0.5, Float(sh.anchor.y), Float(sh.anchor.z) + 0.5)
        _ = world.loadSync(center: sc, radius: 5)
        game.player.flying = true
        game.player.pos = sc
        var frames: [IVec3] = []
        let base = Blocks.id("end_portal_frame")
        for y in max(0, sh.min.y)...min(CH - 1, sh.max.y) { for z in sh.min.z...sh.max.z { for x in sh.min.x...sh.max.x {
            let b = world.block(x, y, z)
            if b == base || b == base + 1 { frames.append(IVec3(x, y, z)) }
        } } }
        check(frames.count == 12, "stronghold: portal room with \(frames.count) hollow gate frames")
        let prefilled = frames.filter { world.block($0.x, $0.y, $0.z) == base + 1 }.count
        info("stronghold: \(prefilled) frames already hold an eye")
        // Fill every empty frame with a right click.
        _ = hold("ender_eye")
        for f in frames where world.block(f.x, f.y, f.z) == base {
            // Stand on the platform outside the ring, eye level with the frame top.
            // Standing on the frame and looking straight down at its top (a spot beside it can clip the next frame).
            let feet = V3(Float(f.x) + 0.5, Float(f.y) + 0.82, Float(f.z) + 0.5)
            game.player.pos = feet
            aim(at: V3(Float(f.x) + 0.5, Float(f.y) + 0.8, Float(f.z) + 0.52))
            _ = hold("ender_eye")
            game.input.rightClicked = true
            _ = tick(0.1, pin: feet)
        }
        let filled = frames.filter { world.block($0.x, $0.y, $0.z) == base + 1 }.count
        check(filled == 12, "hollow gate: \(filled)/12 frames filled with right clicks")
        let c = frames.reduce(V3(0, 0, 0)) { $0 + center($1) } / Float(max(1, frames.count))
        let pc = IVec3(Int(floor(c.x)), frames.first?.y ?? 0, Int(floor(c.z)))
        var portalBlocks = 0
        for dz in -1...1 { for dx in -1...1 where key(pc + IVec3(dx, 0, dz)) == "end_portal" { portalBlocks += 1 } }
        check(portalBlocks == 9, "hollow gate: the 3x3 gate opens (\(portalBlocks)/9)")
        gateCenter = pc
    }
    var gateCenter: IVec3?

    // MARK: The Hollow: crystals, the wyrm, egg, rifts, credits

    func theHollow() {
        section("the hollow")
        if let g = gateCenter, game.dim.dim == .overworld {
            game.player.flying = false
            game.player.pos = V3(Float(g.x) + 0.5, Float(g.y) + 0.2, Float(g.z) + 0.5)
            let went = tick(3) { self.game.dim.dim == .end }
            check(went, "hollow gate: stepping in goes to the Hollow")
        }
        if game.dim.dim != .end { game.enterEnd() }
        let p = game.player.pos
        let under = world.block(Int(floor(p.x)), Int(floor(p.y)) - 1, Int(floor(p.z)))
        check(abs(p.x - 100.5) < 1 && abs(p.z - 0.5) < 1 && under == OBSIDIAN, String(format: "hollow: arrived on the obsidian platform at %.0f %.0f %.0f", p.x, p.y - Float(YOFF), p.z))
        game.player.flying = false
        _ = tick(3)
        check(game.alive && abs(game.player.pos.y - p.y) < 1.5, "hollow: standing safely on the platform")
        // The central island streams in; the wyrm appears once the centre is loaded.
        _ = world.loadSync(center: V3(40, Float(YOFF + 60), 0), radius: 5)
        _ = tick(8)
        let dragons = game.mobs.mobs.filter { $0.kind == .enderDragon }
        check(dragons.count == 1, "hollow: exactly one Hollow Wyrm (\(dragons.count))")
        var crystals = game.mobs.mobs.filter { $0.kind == .endCrystal }
        check(crystals.count == 10, "hollow: 10 hollow crystals on the spikes (\(crystals.count))")
        guard let d = dragons.first else { return }
        check(d.health == 200, "wyrm: 200 health (\(d.health))")
        let fy = game.fountainY
        info("fountain at y \(fy - YOFF), spikes \((game.endGen?.spikes ?? []).map { $0.height }.sorted())")

        // Walk to the centre (well, teleport) and shoot the uncaged crystals with the bow; break the caged ones
        // after climbing (sword).
        section("crystals")
        _ = tick(1)
        crystals = game.mobs.mobs.filter { $0.kind == .endCrystal }
        var byArrow = 0, byHand = 0
        for c in crystals {
            let base = V3(c.pos.x, Float(fy + 1), c.pos.z)
            let out = simd_length(V2(base.x, base.z)) > 0.1 ? simd_normalize(V3(base.x, 0, base.z)) : V3(1, 0, 0)
            let feet = V3(base.x, c.pos.y - 1, base.z) + out * 9
            game.player.flying = true
            game.player.pos = feet
            for _ in 0..<3 where c.health > 0 {
                shoot(at: c.pos + V3(0, 1, 0), from: feet)
                _ = tick(1, pin: feet)
            }
            if c.health <= 0 { byArrow += 1; continue }
            // Caged (or missed): climb up and hit it.
            let near = c.pos + out * 1.5 - V3(0, 0.6, 0)
            game.player.pos = near
            _ = hold("diamond_sword")
            swing(at: c, from: near)
            _ = tick(0.5, pin: near)
            if c.health <= 0 { byHand += 1 }
        }
        let left = game.mobs.mobs.filter { $0.kind == .endCrystal && $0.health > 0 }.count
        check(left == 0, "crystals: all destroyed (\(byArrow) by arrow, \(byHand) up close, \(left) left)")
        info("crystal explosions cost \(damageTaken) health so far (topped up)")

        // The fight: wait for perches and hit the head with the sword; shoot arrows while it circles.
        section("hollow wyrm fight")
        let fightStart = simSeconds
        let dmgStart = damageTaken
        var perches = 0, swings = 0, arrows = 0, wasPerched = false
        let ground = V3(7.5, Float(fy + 1), 0.5)
        game.player.flying = false
        game.player.pos = ground
        var arrowDamage = 0
        while simSeconds - fightStart < 900 && d.phase != 6 && d.health > 0 {
            if d.phase == 4 {
                if !wasPerched { perches += 1; wasPerched = true }
                // Stand in front of the head and swing.
                let head = d.pos + d.forward * 5 + V3(0, 0, 0)
                var feet = V3(head.x, Float(fy + 1), head.z)
                if simd_length(V2(feet.x, feet.z)) < 4.5 { feet = V3(feet.x, 0, feet.z) * (4.5 / max(0.1, simd_length(V2(feet.x, feet.z)))); feet.y = Float(fy + 1) }
                game.player.flying = true
                _ = hold("diamond_sword")
                swing(at: d, from: feet)
                swings += 1
            } else {
                wasPerched = false
                game.player.flying = false
                // Shoot at it when it's within 40 blocks, otherwise wait.
                let dist = simd_length(d.pos - game.player.eye)
                if dist < 40 && dist > 8 {
                    let h0 = d.health
                    shoot(at: d, from: ground)
                    _ = tick(0.5, pin: ground)
                    arrows += 1
                    arrowDamage += max(0, h0 - d.health)
                } else {
                    _ = tick(0.5)
                    if simd_length(game.player.pos - ground) > 6 || game.player.pos.y < Float(fy) - 2 { game.player.pos = ground; game.player.vel = .zero }
                }
            }
        }
        let fightTime = simSeconds - fightStart
        check(d.phase == 6 || d.health <= 0, String(format: "wyrm: defeated in %.0f s (%ld perches, %ld sword hits, %ld arrows for %ld damage, health left %ld)",
                                                         fightTime, perches, swings, arrows, arrowDamage, d.health))
        info("wyrm fight: player took \(damageTaken - dmgStart) damage (half-hearts, healed by the test)")
        // Death animation (10 s), then the exit portal, egg and first rift.
        // XP as total points: the level gain from 12000 points depends on the starting level (20 -> 69).
        func totalXP() -> Int { (0..<game.xpLevel).reduce(game.xpPoints) { $0 + Game.xpToNext($1) } }
        let xp0 = game.xpLevel, pts0 = totalXP()
        _ = tick(14) { self.game.dragonKilled }
        _ = tick(1)
        check(game.dragonKilled, "wyrm: death sequence finishes")
        check(totalXP() - pts0 >= 11400, "wyrm: 12000 XP (\(totalXP() - pts0) points, level \(xp0) -> \(game.xpLevel))")
        check(!game.mobs.mobs.contains { $0.kind == .enderDragon }, "wyrm: gone after dying")
        var portal = 0
        for z in -2...2 { for x in -2...2 where key(IVec3(x, fy, z)) == "end_portal" { portal += 1 } }
        check(portal >= 12, "exit portal: active (\(portal) gate blocks)")
        let eggAt = IVec3(0, fy + 4, 0)
        _ = tick(2)
        var eggPos: IVec3?
        for y in (fy - 1)...(fy + 6) where key(IVec3(0, y, 0)) == "dragon_egg" { eggPos = IVec3(0, y, 0) }
        check(eggPos != nil, "egg: the wyrm egg sits on the exit portal (\(eggPos.map { "\($0.y - fy)" } ?? key(eggAt)))")
        var rift: IVec3?
        for a in 0..<20 {
            let ang = 2 * Double.pi * Double(a) / 20
            let gx = Int((96 * cos(ang)).rounded()), gz = Int((96 * sin(ang)).rounded())
            _ = world.loadSync(center: V3(Float(gx), Float(YOFF + 75), Float(gz)), radius: 1)
            for y in (YOFF + 70)...(YOFF + 80) where key(IVec3(gx, y, gz)) == "end_gateway" { rift = IVec3(gx, y, gz) }
        }
        check(rift != nil, "rift: a hollow rift gateway opened on the ring")
        if rift == nil { info("gateways counter \(game.gateways)") }

        // Egg: a hit makes it hop away (reference); it's collected by making it fall onto a torch.
        section("egg")
        if var e = eggPos {
            game.portalCooldown = 60
            var hopped = 0
            for _ in 0..<20 where count("dragon_egg") == 0 {
                holdNothing()
                standBeside(e)
                game.input.leftClicked = true
                game.input.leftDown = true
                tick(0.05, pin: game.player.pos)
                game.input.leftDown = false
                tick(3)
                guard let ne = findBlock(near: e, radius: 20, yRange: max(1, e.y - 30)...min(CH - 2, e.y + 10), { $0 == "dragon_egg" }) else { break }
                if ne != e { hopped += 1 }
                e = ne
                // Torch trick: the egg must rest on something breakable with room for a torch under it.
                let under = e + IVec3(0, -1, 0), below2 = e + IVec3(0, -2, 0)
                guard carvable(under), Blocks.collide[Int(world.block(under.x, under.y, under.z))], carvable(below2) else { continue }
                // A player digs out the cell two below and gives the torch a floor if it has none (placing a block).
                if !Blocks.collide[Int(world.block(below2.x, below2.y - 1, below2.z))] {
                    world.setBlock(below2.x, below2.y - 1, below2.z, Blocks.id("end_stone"))
                }
                world.setBlock(below2.x, below2.y, below2.z, Blocks.id("torch"))
                _ = hold("diamond_pickaxe")
                if mine(under, maxSeconds: 10) { tick(2); collect(near: center(under), 8) }
            }
            game.portalCooldown = 0
            check(hopped > 0, "egg: hitting the egg makes it teleport (\(hopped) hops)")
            check(count("dragon_egg") == 1, "egg: collected by dropping it onto a torch (\(count("dragon_egg")))")
            if count("dragon_egg") == 0 { give("dragon_egg", 1, bulk: "egg") }
        }

        // Rift: out to the far islands and back.
        section("rift")
        if let r = rift {
            _ = world.loadSync(center: center(r), radius: 1)
            game.portalCooldown = 0
            // The rift floats between bedrock caps at the island's edge: throw a void pearl into it.
            let rc = center(r)
            let outDir = simd_normalize(V3(rc.x, 0, rc.z))
            let throwFeet = rc - outDir * 6 - V3(0, 1.1, 0)
            game.player.flying = true
            game.player.pos = throwFeet
            clearMobs(near: rc, 10)                      // nothing in the pearl's way (a voidwalker would catch it)
            if count("ender_pearl") == 0 { give("ender_pearl", 2, bulk: "spare pearls") }
            _ = hold("ender_pearl")
            aim(at: rc + V3(0, 0.15, 0))
            game.input.rightClicked = true
            let gone = tick(3, pin: nil) { simd_length(V2(self.game.player.pos.x, self.game.player.pos.z)) > 900 }
            let fp = game.player.pos
            let fd = simd_length(V2(fp.x, fp.z))
            check(gone, String(format: "rift: teleports to the far islands (%.0f blocks out)", fd))
            game.player.flying = false
            _ = tick(3)
            let fu = world.block(Int(floor(game.player.pos.x)), Int(floor(game.player.pos.y)) - 1, Int(floor(game.player.pos.z)))
            check(Blocks.collide[Int(fu)] && game.player.pos.y > Float(YOFF + 30), "rift: landed on solid ground (\(baseKey(fu)))")
            // A return rift sits near the landing spot.
            let lp = IVec3(Int(floor(game.player.pos.x)), Int(floor(game.player.pos.y)), Int(floor(game.player.pos.z)))
            let back = findBlock(near: lp, radius: 12, yRange: max(0, lp.y - 12)...min(CH - 1, lp.y + 12), { $0 == "end_gateway" })
            check(back != nil, "rift: a return rift near the landing spot")
            spire(from: lp)
            if let b = back {
                _ = world.loadSync(center: center(b), radius: 2)
                game.portalCooldown = 0
                // Pearl into it from a few blocks away (walking into it by body contact is also supported; see STATUS).
                let bc = center(b)
                let tf = bc + V3(6, -1.1, 0)
                for y in (b.y - 1)...(b.y + 1) { for dz in -1...1 { for dx in 1...7 where carvable(IVec3(b.x + dx, y, b.z + dz)) {
                    world.setBlock(b.x + dx, y, b.z + dz, AIR)
                } } }
                game.player.flying = true
                game.player.pos = tf
                // Let the body settle first (it used to get nudged ~2 blocks in the throw frame), then aim from where it is.
                _ = tick(0.2, pin: tf)
                game.player.pos = tf
                game.player.vel = .zero
                clearMobs(near: bc, 10)
                if count("ender_pearl") == 0 { give("ender_pearl", 2, bulk: "spare pearls") }
                _ = hold("ender_pearl")
                aim(at: bc + V3(0, 0.15, 0))
                let heldBefore = Items.key(game.held.item)
                game.input.rightClicked = true
                tick(0.05)
                let thrown = game.projectiles.fireballs.filter { $0.kind == .pearl }.map { String(format: "%.1f,%.1f,%.1f", $0.pos.x, $0.pos.y - Float(YOFF), $0.pos.z) }
                let home = tick(3) { simd_length(V2(self.game.player.pos.x, self.game.player.pos.z)) < 200 }
                if !home {
                    info(String(format: "after: player %.2f %.2f %.2f; rift at %ld %ld %ld; held %@, pearls in flight %@, menu %@, gliding %@", game.player.pos.x,
                                game.player.pos.y - Float(YOFF), game.player.pos.z, b.x, b.y - YOFF, b.z, heldBefore, thrown.description,
                                game.menu.map { "\(type(of: $0))" } ?? "none", game.player.gliding ? "yes" : "no"))
                }
                check(home, String(format: "rift: the return rift leads back to the central island (%.0f blocks out)", simd_length(V2(game.player.pos.x, game.player.pos.z))))
            }
        }

        // Quit and reload: the wyrm stays dead, the exit portal stays open, the egg stays in the bag.
        section("save + reload")
        game.saveNow()
        if let save = game.save, let meta = save.loadMeta() {
            let w2 = World(seed: world.seed, device: world.device, save: save, dim: .overworld)
            w2.renderDistance = 4
            let g2 = Game(world: w2, save: save, persistent: false)
            g2.apply(meta)
            check(g2.dim.dim == .end, "reload: back in the Hollow (\(g2.dim.dim))")
            check(g2.dragonKilled && g2.gateways >= 1, "reload: wyrm stays defeated (\(g2.dragonKilled), \(g2.gateways) rifts)")
            check(g2.inventory.main.countOf(id("dragon_egg")) == 1, "reload: the egg is still in the inventory")
            _ = g2.world.loadSync(center: V3(0.5, Float(fy), 0.5), radius: 2)
            var open = 0
            for z in -2...2 { for x in -2...2 where Blocks.key(g2.world.block(x, fy, z)) == "end_portal" { open += 1 } }
            check(open >= 12, "reload: exit portal still open (\(open))")
            g2.paused = false
            g2.closeMenu()
            for _ in 0..<120 { g2.tick(0.05) }
            check(!g2.mobs.mobs.contains { $0.kind == .enderDragon }, "reload: no new wyrm appears")
        } else {
            check(false, "reload: world.json written")
        }

        // Exit portal -> credits -> home.
        section("credits")
        game.portalCooldown = 0
        _ = world.loadSync(center: V3(0, Float(fy), 0), radius: 2)
        game.player.flying = false
        game.player.pos = V3(2.5, Float(fy) + 0.2, 0.5)
        let rolled = tick(2) { self.game.credits != nil }
        check(rolled, "exit portal: the credits roll")
        let done = tick(Double(Game.creditsLength) + 3) { self.game.dim.dim == .overworld }
        check(done && game.seenCredits, "credits: back on the Surface after the credits")
        let sp = game.spawnPoint
        check(simd_length(V2(game.player.pos.x - sp.x, game.player.pos.z - sp.z)) < 2, "credits: at the spawn point")
        _ = tick(2)
        check(game.alive, "credits: alive at home")
        // A second trip goes straight home without credits.
    }

    // Far islands: the nearest hollow spire, the glider wings in its ship, a glide off the top.
    func spire(from lp: IVec3) {
        section("hollow spire")
        guard let city = world.gen.structures?.nearest("end_city", x: lp.x, z: lp.z, maxRegions: 4) else {
            check(false, "spire: a hollow spire on the far islands"); return
        }
        let d = simd_length(V2(Float(city.anchor.x - lp.x), Float(city.anchor.z - lp.z)))
        check(d < 2000, "spire: nearest hollow spire \(Int(d)) blocks from the landing spot (\(city.pieces.count > 1 ? "with" : "no") ship)")
        let cc = V3(Float(city.anchor.x), Float(city.anchor.y), Float(city.anchor.z))
        _ = world.loadSync(center: cc, radius: 3)
        game.player.flying = true
        game.player.pos = cc + V3(0, 30, 0)
        tick(1, pin: game.player.pos)
        let sentries = game.mobs.mobs.filter { $0.kind == .shulker && city.contains(Int(floor($0.pos.x)), Int(floor($0.pos.y)), Int(floor($0.pos.z))) }.count
        info("spire: \(sentries) shellsentries")
        var wings: IVec3?
        for (p, be) in world.blockEntities where be.kind == .chest && city.contains(p.x, p.y, p.z) {
            if be.container.slots.contains(where: { Items.key($0.item) == "elytra" }) { wings = p }
        }
        if city.pieces.count > 1 {
            check(wings != nil, "spire: the ship's hold has glider wings")
        }
        makeRoom()
        if let w = wings, let be = world.blockEntities[w] {
            for i in 0..<be.container.count where Items.key(be.container[i].item) == "elytra" {
                game.inventory.add(be.container[i]); be.container[i] = .empty
            }
        }
        if count("elytra") == 0 { give("elytra", 1, bulk: "no ship at this spire") }
        // Wear them and glide off from high up: space while falling opens the wings.
        if let i = (0..<36).first(where: { Items.key(inv[$0].item) == "elytra" }) { game.inventory.armor[1] = inv[i]; inv[i] = .empty }
        let start = cc + V3(0, 40, 0)
        game.player.flying = false
        game.player.pos = start
        game.player.vel = .zero
        game.player.airPeak = start.y
        game.player.yaw = 0
        game.player.pitch = -0.35
        tick(0.4)
        game.input.pressed.insert(Key.space)
        tick(0.05)
        check(game.player.gliding, "wings: open with space while falling")
        let hp = game.health
        game.health = 20
        for _ in 0..<120 { game.player.pitch = -0.2; game.tick(0.05); simSeconds += 0.05; if !game.player.gliding { break } }
        let flown = simd_length(V2(game.player.pos.x - start.x, game.player.pos.z - start.z))
        let dropped = start.y - game.player.pos.y
        check(flown > 30 && flown > dropped * 2, String(format: "wings: glided %.0f blocks while dropping %.0f", flown, dropped))
        game.health = max(hp, game.health)
        game.inventory.armor[1] = .empty
        game.player.gliding = false
    }

    // MARK: The Blight

    func blight() {
        section("blight")
        if game.dim.dim != .overworld { game.changeDimension(to: .overworld, at: game.spawnPoint) }
        let sp = game.spawnPoint
        // An arena a little away from spawn: flat stone, open sky.
        let ax = Int(floor(sp.x)) + 24, az = Int(floor(sp.z)) + 24
        _ = world.loadSync(center: V3(Float(ax), sp.y, Float(az)), radius: 3)
        let gy = world.topY(ax, az) + 1
        for dx in -12...12 { for dz in -12...12 {
            world.setBlock(ax + dx, gy - 1, az + dz, STONE)
            for y in 0..<14 { world.setBlock(ax + dx, gy + y, az + dz, AIR) }
        } }
        if count("soul_sand") < 4 { give("soul_sand", 4 - count("soul_sand"), bulk: "emberdeep soul sand valley") }
        if count("wither_skeleton_skull") < 3 { give("wither_skeleton_skull", 3 - count("wither_skeleton_skull"), bulk: "blight skeletons (2.5% each)") }
        // Build the T with real placements: stem, arms, then skulls (the last skull summons).
        let stem = IVec3(ax, gy, az)
        let soul = Blocks.id("soul_sand")
        world.setBlock(stem.x, stem.y, stem.z, soul)
        for dx in -1...1 { world.setBlock(stem.x + dx, stem.y + 1, stem.z, soul) }
        inv.remove(id("soul_sand"), 4)
        clearMobs(near: center(stem), 6)                // a cow standing on the T would block the skulls
        game.survival = true
        for dx in [-1, 1, 0] {
            let top = IVec3(stem.x + dx, stem.y + 1, stem.z)
            let feet = V3(Float(top.x) + 0.5, Float(top.y) + 1.2, Float(top.z) + 2.5)
            // A click can be swallowed (place cooldown after the previous action): retry until the skull is down.
            for _ in 0..<4 where baseKey(world.block(top.x, top.y + 1, top.z)) != "wither_skeleton_skull"
                && !game.mobs.mobs.contains(where: { $0.kind == .wither }) {
                game.player.flying = true
                game.player.pos = feet
                _ = tick(0.3, pin: feet)
                aim(at: V3(Float(top.x) + 0.5, Float(top.y) + 1, Float(top.z) + 0.5))
                _ = hold("wither_skeleton_skull")
                game.input.rightClicked = true
                _ = tick(0.1, pin: feet)
            }
        }
        let w = game.mobs.mobs.first { $0.kind == .wither }
        check(w != nil, "blight: soul sand T + three skulls summons the Blight")
        if w == nil {
            let tops = [-1, 0, 1].map { baseKey(world.block(stem.x + $0, stem.y + 2, stem.z)) }
            let near = game.mobs.mobs.filter { simd_length($0.pos - center(stem)) < 6 }.map { $0.kind.key }
            info("blight T: skulls row \(tops), arms \(baseKey(world.block(stem.x, stem.y + 1, stem.z))), held \(Items.key(game.held.item)), " +
                 "skulls left \(count("wither_skeleton_skull")), mobs near \(near), menu \(game.menu.map { "\(type(of: $0))" } ?? "none")")
        }
        guard let b = w else { return }
        check(b.phase == 1, "blight: charging after the summon")
        let feet = V3(Float(ax) + 0.5, Float(gy), Float(az) + 14.5)
        game.player.flying = false
        game.player.pos = feet
        _ = tick(12)
        check(b.phase == 0 && b.health >= 290, "blight: 11 s charge ends at full health (\(b.health)/300) with a blast")
        section("blight fight")
        // Gear a Blight fighter brings (enchanting table / anvil): Smite V sword (it is undead), Power V bow.
        for i in 0..<36 where Items.key(inv[i].item) == "diamond_sword" { var st = inv[i]; st.ench = Enchant.pack([(.smite, 5)]); inv[i] = st }
        for i in 0..<36 where Items.key(inv[i].item) == "bow" { var st = inv[i]; st.ench = Enchant.pack([(.power, 5)]); inv[i] = st }
        info("bulk: Smite V on the sword, Power V on the bow")
        let fightStart = simSeconds
        let dmgStart = damageTaken
        var arrows = 0, swings = 0, arrowDmg = 0, armoredArrowDmg = 0, armoredArrows = 0, landed = 0, swordDmg = 0, regear = 0
        while b.health > 0 && simSeconds - fightStart < 600 {
            // After a death (skull blasts can destroy the dropped gear) the fighter comes back equipped.
            if game.inventory.armorPoints < 17 && regear < 6 { regear += 1; wearArmor() }
            if b.health > 150 {
                // Bow while it's unarmoured.
                let h0 = b.health
                let here = game.player.pos
                shoot(at: b, from: here)
                _ = tick(0.4, pin: here)
                arrows += 1
                arrowDmg += max(0, h0 - b.health)
            } else if armoredArrows < 3 {
                // Arrows bounce off the armour below half health (only arrow damage counts: thorns, fire and the
                // like can still hurt it in the same moment).
                if armoredArrows == 0 { _ = tick(1.5) }                 // let arrows already in flight land first
                // It regenerates 1 HP/s: back above half health it is unarmoured again (run 350 counted arrows that
                // hit it at 151-152 HP as bouncing failures). Shoot only while it really wears the armour.
                if b.health > 150 { continue }
                let a0 = b.arrowDamage
                let here = game.player.pos
                shoot(at: b, from: here)
                _ = tick(0.4, pin: here)
                armoredArrows += 1
                armoredArrowDmg += b.arrowDamage - a0
            } else {
                // Sword: it hovers low when armoured; step up to it.
                let to = V3(b.pos.x, 0, b.pos.z) - V3(game.player.pos.x, 0, game.player.pos.z)
                let l = simd_length(to)
                var at = game.player.pos
                if l > 2.2 { at = V3(b.pos.x, max(Float(gy), b.pos.y - 1), b.pos.z) - simd_normalize(to + V3(0.001, 0, 0)) * 2 }
                game.player.flying = true
                if !hold("diamond_sword") {
                    give("diamond_sword", 1, bulk: "a new sword")
                    for i in 0..<36 where Items.key(inv[i].item) == "diamond_sword" { var st = inv[i]; st.ench = Enchant.pack([(.smite, 5)]); inv[i] = st }
                    _ = hold("diamond_sword")
                }
                let h0 = b.health
                swing(at: b, from: at)
                swings += 1
                if b.health < h0 { landed += 1; swordDmg += h0 - b.health }
            }
            // Keep the player near the arena floor.
            if game.player.pos.y < Float(gy) - 3 || simd_length(game.player.pos - feet) > 40 { game.player.pos = feet; game.player.vel = .zero }
        }
        let t = simSeconds - fightStart
        check(b.health <= 0, String(format: "blight: defeated in %.0f s (%ld arrows for %ld damage, %ld sword hits)", t, arrows, arrowDmg, swings))
        check(armoredArrows == 0 || armoredArrowDmg == 0, "blight: arrows bounce off its armour below half health (\(armoredArrowDmg) damage from \(armoredArrows))")
        info("blight fight: player took \(damageTaken - dmgStart) damage (healed by the test); \(landed) of \(swings) sword hits landed for \(swordDmg)")
        collect(near: b.pos, 24)
        _ = tick(1)
        collect(near: game.player.pos, 24)
        // The star falls from where the Blight died (often 10+ blocks up; run 346 found it on the ground 9 below):
        // a player walks over to it once it has landed.
        for _ in 0..<60 where count("nether_star") == 0 {
            guard let e = game.drops.items.first(where: { !$0.stack.isEmpty && Items.key($0.stack.item) == "nether_star" }) else { break }
            game.player.pos = e.pos
            game.player.vel = .zero
            _ = tick(0.1, pin: e.pos)
        }
        check(count("nether_star") == 1, "blight: the Blight Star drops and is picked up (\(count("nether_star")))")
        if count("nether_star") == 0 {
            let stars = game.drops.items.filter { Items.key($0.stack.item) == "nether_star" }.map { String(format: "%.0f %.0f %.0f", $0.pos.x, $0.pos.y, $0.pos.z) }
            info(String(format: "star lost: Blight health %ld at %.0f %.0f %.0f, still listed %@, stars on the ground %@", b.health, b.pos.x, b.pos.y, b.pos.z,
                        game.mobs.mobs.contains { $0 === b } ? "yes" : "no", "\(stars)"))
        }
        if count("nether_star") == 0 { give("nether_star", 1, bulk: "star lost") }
        give("glass", 5, bulk: "sand + furnace"); give("obsidian", 3, bulk: "obsidian")
        craft(["GGG", "GSG", "OOO"], ["G": "glass", "S": "nether_star", "O": "obsidian"], "beacon")
        check(count("beacon") == 1, "craft: beacon from the Blight Star")
    }
}
