import AppKit
import Metal
import simd

// Headless test harness. Renders one frame offscreen to a PNG and prints timings, e.g.
//   Blocksmith --snapshot /tmp/shot.png --seed 42 --yaw 45 --pitch -20 --time 0.25 --up 30 --rd 8
// Angles in degrees; --time is a day fraction (0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight);
// --x/--z pick a world position (default: spawn); --up raises the camera above the terrain;
// --find <biome> (forest, desert, snowy, ...) spirals out from spawn to the middle of that biome.
enum Snapshot {
    static func findBiome(_ gen: TerrainGenerator, _ want: String, interior: Bool = false) -> V3? {
        var x = 0, z = 0, dx = 0, dz = -1
        // Cave biomes live underground: match their climate rule (WorldGen.decorateCaves) instead.
        let cave: ((WorldGen.Climate) -> Bool)? = {
            switch want {
            case "lush_caves": return { $0.h > 0.55 }
            case "dripstone_caves": return { $0.c > 0.75 }
            case "deep_dark": return { $0.e < -0.6 }
            default: return nil
            }
        }()
        let wg = gen as? WorldGen
        // Biomes follow climate belts thousands of blocks wide: spiral out in 48-block steps (~6 km across).
        let stepB = 48
        // Two passes: first well inside the biome (centre and all eight points 40 blocks out: the desert shot stood on
        // a desert column at the coast and showed a grass hillside, run 370), then the frayed-edge rule.
        for strict in interior ? [true, false] : [false] {
        x = 0; z = 0; dx = 0; dz = -1
        for _ in 0..<(strict ? 12000 : 40000) {
            let wx = x * stepB + 8, wz = z * stepB + 8
            // Narrow biomes (rivers, shores) only need the centre column; others the centre and at least two
            // of four points 24 blocks out (biome edges are frayed).
            let narrow = ["river", "frozen_river", "beach", "snowy_beach", "stony_shore"].contains(want)
            let far: [(Int, Int)] = [(0, 0), (40, 0), (-40, 0), (0, 40), (0, -40), (40, 40), (-40, 40), (40, -40), (-40, -40)]
            let probes: [(Int, Int)] = narrow ? [(0, 0)] : (strict ? far : [(0, 0), (24, 0), (-24, 0), (0, 24), (0, -24)])
            var hits = 0
            for (k, p) in probes.enumerated() {
                let hit: Bool
                if let c = cave, let wg { hit = c(wg.climate(wx + p.0, wz + p.1)) } else { hit = gen.column(wx + p.0, wz + p.1).biome.name == want }
                if hit { hits += 1 } else if k == 0 || strict { break }
            }
            let ok = hits >= (narrow ? 1 : (strict ? probes.count : 3)) && hits > 0
            if ok {
                let h = gen.column(wx, wz).height
                return V3(Float(wx) + 0.5, Float(max(h, SEA) + 1), Float(wz) + 0.5)
            }
            if x == z || (x < 0 && x == -z) || (x > 0 && x == 1 - z) { (dx, dz) = (-dz, dx) }
            x += dx; z += dz
        }
        }
        print("biome \(want) not found")
        return nil
    }

    static func run(_ out: String) -> Int32 {
        guard let device = MTLCreateSystemDefaultDevice() else { print("no Metal device"); return 1 }
        let seed = UInt64(arg("--seed") ?? "") ?? 12345
        let rd = Int(arg("--rd") ?? "") ?? 8
        let w = Int(arg("--w") ?? "") ?? 1280
        let h = Int(arg("--h") ?? "") ?? 800
        let snapDim = Dim(rawValue: arg("--dim") ?? "") ?? .overworld
        if CommandLine.arguments.contains("--nolod") { World.lodNear = 99 }      // every chunk at full detail
        let world = World(seed: seed, device: device, save: nil, dim: snapDim)
        world.renderDistance = rd
        let game = Game(world: world, save: nil, persistent: false)
        var pos = game.findSpawn(varied: false)      // reference shots keep the old origin
        if let x = Float(arg("--x") ?? ""), let z = Float(arg("--z") ?? "") {
            let hgt = world.gen.column(Int(floor(x)), Int(floor(z))).height
            pos = V3(x, Float(max(hgt, SEA) + 1), z)
        }
        var faceYaw: Float? = nil
        if let want = arg("--find"), let p = findBiome(world.gen, want, interior: true) {
            pos = p
            // --yaw biome: face the way the biome runs furthest (the swamp shot looked out to sea from a coastal swamp
            // column: blind critic, run 373). 16 headings, matches counted at 12..72 blocks out.
            if arg("--yaw") == "biome" {
                var best = -1
                for i in 0..<16 {
                    let a = Float(i) / 16 * 2 * Float.pi
                    var n = 0
                    for d in stride(from: 12, through: 72, by: 12) {
                        let x = Int(p.x + cosf(a) * Float(d)), z = Int(p.z + sinf(a) * Float(d))
                        if world.gen.column(x, z).biome.name == want { n += 1 }
                    }
                    if n > best { best = n; faceYaw = atan2f(-cosf(a), -sinf(a)) }
                }
            }
        }
        // --feature lake|delta: the nearest lake or big river mouth from the river graph.
        if let f = arg("--feature"), let wg = world.gen as? WorldGen {
            if let (fx, fz) = wg.terrain.nearestFeature(f, x: Int(pos.x), z: Int(pos.z)) {
                pos = V3(Float(fx) + 0.5, Float(max(world.gen.column(fx, fz).height, SEA) + 1), Float(fz) + 0.5)
                // Stand back along the view so a camera --up above, pitched down, looks at the feature (not past it).
                let yawD = (Float(arg("--yaw") ?? "") ?? 0) * .pi / 180, pitchD = (Float(arg("--pitch") ?? "") ?? 0) * .pi / 180
                let upD = Float(arg("--up") ?? "") ?? 0
                if pitchD < -0.1 && upD > 0 {
                    let back: Float = upD / tanf(-pitchD)
                    pos.x += sinf(yawD) * back
                    pos.z += cosf(yawD) * back
                }
                // --back N: stand N blocks back along the view, on the ground (horizon views of a landmark).
                if let bk = Float(arg("--back") ?? "") {
                    pos.x += sinf(yawD) * bk
                    pos.z += cosf(yawD) * bk
                    pos.y = Float(max(world.gen.column(Int(pos.x), Int(pos.z)).height, SEA) + 1)
                }
                print("feature \(f) at \(fx) \(fz)")
            } else { print("feature \(f) not found") }
        }
        // --onland: if the start column is sea, spiral out to the nearest land at least 4 blocks above sea level.
        if CommandLine.arguments.contains("--onland") {
            var sx = 0, sz = 0, sdx = 0, sdz = -1
            for _ in 0..<20000 {
                let wx = Int(pos.x) + sx * 32, wz = Int(pos.z) + sz * 32
                let c = world.gen.column(wx, wz)
                if c.height > SEA + 4 && !c.biome.isOcean {
                    pos = V3(Float(wx) + 0.5, Float(c.height + 1), Float(wz) + 0.5)
                    break
                }
                if sx == sz || (sx < 0 && sx == -sz) || (sx > 0 && sx == 1 - sz) { (sdx, sdz) = (-sdz, sdx) }
                sx += sdx; sz += sdz
            }
        }
        // --structure <kind>: stand above the start piece of the nearest structure of that kind.
        var frame: (yaw: Float, pitch: Float)?
        var insideFrame: IVec3?
        var structBox: (IVec3, IVec3)?                   // --slice: the framed structure's box
        // --land: skip starts whose centre column is below sea level (ruined portals also generate under water).
        let landOnly = CommandLine.arguments.contains("--land")
        // --subkind <kind>: one variant of a type (temple -> desert_pyramid, jungle_temple, swamp_hut, igloo).
        let subkind = arg("--subkind")
        let onLand: (StructureStart) -> Bool = { s in
            (subkind == nil || s.kind == subkind) && (!landOnly || world.gen.column((s.min.x + s.max.x) / 2, (s.min.z + s.max.z) / 2).height > SEA)
        }
        if let kind = arg("--structure"), let s = world.gen.structures?.nearest(kind, x: Int(pos.x), z: Int(pos.z), maxRegions: landOnly || subkind != nil ? 16 : 6, accept: onLand) {
            structBox = (s.min, s.max)
            if arg("--frame") != nil {
                // Overview: from outside the footprint, aimed at its centre.
                let c = V3(Float(s.min.x + s.max.x) / 2, Float(s.anchor.y), Float(s.min.z + s.max.z) / 2)
                let ext = Float(max(s.max.x - s.min.x, s.max.z - s.min.z))
                // A buried structure (mineshaft) can't be seen from outside: stand at its start and look down the
                // longest open corridor instead (the outside view landed in a stone pocket: blind critic, run 395).
                let ground: Int = world.gen.column(s.anchor.x, s.anchor.z).height
                if ground > s.max.y + 3 { insideFrame = s.anchor }
                let dist = max(14, ext * 0.75) * (Float(arg("--frame") ?? "") ?? 1)
                let p = c + V3(-dist * 0.7, dist * 0.55, -dist * 0.7)
                let d = c - p
                frame = (atan2f(-d.x, -d.z), atan2f(d.y, simd_length(V2(d.x, d.z))))
                pos = p
                print("structure \(kind) at \(s.anchor.x) \(s.anchor.y - YOFF) \(s.anchor.z) (\(s.pieces.count) pieces, framed)")
            } else {
            pos = V3(Float(s.anchor.x) + 0.5, Float(s.anchor.y), Float(s.anchor.z) + 0.5)
            // --offset dx,dy,dz: a camera spot relative to the anchor (inside a structure).
            if let o = arg("--offset") {
                let v = o.split(separator: ",").compactMap { Float($0) }
                if v.count == 3 { pos += V3(v[0], v[1], v[2]) }
            }
            print("structure \(kind) at \(s.anchor.x) \(s.anchor.y - YOFF) \(s.anchor.z) (\(s.pieces.count) pieces)")
            }
        }
        pos.y += Float(arg("--up") ?? "") ?? 0
        game.player.pos = pos
        game.player.yaw = frame?.yaw ?? faceYaw ?? (Float(arg("--yaw") ?? "") ?? 30) * .pi / 180
        game.player.pitch = frame?.pitch ?? (Float(arg("--pitch") ?? "") ?? -15) * .pi / 180
        game.player.flying = true
        game.time = (Double(arg("--time") ?? "") ?? 0.2) * DAY_LENGTH
        if let s = arg("--slot") { game.selected = Int(s) ?? 0 }
        if let h = arg("--hold") {
            // --hold item[:aim]: put an item in the hand (guns come loaded; ":aim" aims down the sights).
            let parts = h.split(separator: ":").map(String.init)
            if Items.has(parts[0]) {
                var st = ItemStack(Items.id(parts[0]), 1)
                if let gi = Guns.index(st.item) { st.tag = Guns.all[gi].mag; game.arms.heldGun = gi; game.arms.heldSlot = game.selected }
                game.inventory.held = st
                if parts.count > 1 && parts[1] == "aim" { game.arms.aim = 1 }
            }
        }
        if let hp = arg("--survival") {
            game.survival = true
            game.health = Int(hp) ?? 20
            game.hunger = 13
            game.air = 7
        }
        if CommandLine.arguments.contains("--effects") {
            // Status-effect HUD test: absorption and health boost hearts, poison tint, icons.
            game.survival = true
            game.applyEffect(.healthBoost, amp: 1, seconds: 120)
            game.health = 24
            game.applyEffect(.absorption, amp: 1, seconds: 100)
            game.applyEffect(.poison, amp: 0, seconds: 20)
            game.applyEffect(.strength, amp: 1, seconds: 180)
            game.applyEffect(.nightVision, amp: 0, seconds: 300)
            game.applyEffect(.fireResistance, amp: 0, seconds: 5)
            game.applyEffect(.speed, amp: 0, seconds: 60)
            game.applyEffect(.slowness, amp: 3, seconds: 20)
        }
        if let c = arg("--camera") {
            // Third-person views: 1 behind, 2 in front. Wears a helmet and holds a pickaxe so the model shows gear.
            game.cameraMode = Int(c) ?? 1
            game.inventory.armor[0] = ItemStack(Items.id("iron_helmet"), 1)
            game.inventory.main[game.selected] = ItemStack(Items.id("iron_pickaxe"), 1)
            if CommandLine.arguments.contains("--swim") {
                game.player.flying = false
                game.player.swimming = true
                game.player.pos.y = Float(SEA) - 0.35
            }
        }
        if CommandLine.arguments.contains("--subtitles") {
            // Subtitle test: a few sounds around the camera (left, right, ahead, the player's own).
            AudioSettings.forceSubtitles = true
            let e = game.player.eye, r = V3(cosf(game.player.yaw), 0, -sinf(game.player.yaw))
            game.sfx(.mob(.cow, .ambient), at: e - r * 6)
            game.sfx(.explode, at: e + r * 10)
            game.sfx(.doorOpen, at: e + game.player.look * 5)
            game.sfx(.birdCall, at: e + r * 8 + V3(0, 4, 0))
            game.sfx(.hurt)
        }
        if let b = Float(arg("--bright") ?? "") { Settings.shared.brightnessOverride = max(0, min(1, b)) }
        if CommandLine.arguments.contains("--fast") {
            // Fast graphics for this shot only: keep the user's saved preference untouched.
            let saved = UserDefaults.standard.object(forKey: "fancyGraphics")
            game.fancyGraphics = false
            if let s = saved { UserDefaults.standard.set(s, forKey: "fancyGraphics") } else { UserDefaults.standard.removeObject(forKey: "fancyGraphics") }
        }
        if CommandLine.arguments.contains("--debug") {
            game.showDebug = true
            game.onToast?("Grass Block")
        }
        if let which = arg("--menu") {
            // Container screen test: some items in the inventory and a menu open.
            let give = ["iron_pickaxe", "diamond_sword", "bread", "coal", "raw_iron", "oak_log", "apple", "torch", "iron_chestplate"]
            for (i, n) in give.enumerated() where Items.has(n) { game.inventory.main[9 + i] = ItemStack(Items.id(n), n.hasSuffix("pickaxe") || n.hasSuffix("sword") || n.hasSuffix("plate") ? 1 : 12) }
            var s = game.inventory.main[9]; s.damage = 120; game.inventory.main[9] = s
            switch which {
            case "creative": game.openMenu(CreativeMenu(game: game))
            case "create":
                let pm = PauseMenu(game: game)
                game.openMenu(pm)
                pm.act("create", back: false); pm.newName = "Couch World"; pm.newSeed = "glacier"; pm.editing = 1; pm.build()
            case "death":
                game.openMenu(DeathMenu(game: game, message: "Player was blown up by Hisser"))
            case "commands":
                for c in ["/help", "/time set noon", "/give diamond sword 1", "/give hisser-head", "/locate sea temple", "/summon hisser", "hello", "/tp ~ ~2 ~", "/bogus", "/bases", "/rare"] { game.command(c) }
                for l in game.commandLog { print("console: " + l) }
                let m = CommandMenu(game: game, prefill: "/locate military")
                print("console: suggestions " + m.suggestions.joined(separator: ", "))
                game.openMenu(m)
            case "invsearch", "craftsearch":
                game.inventory.main[22] = ItemStack(Items.id("saddle"), 1)
                if which == "invsearch" {
                    let m = InventoryMenu(game: game); m.query = "sad"
                    game.openMenu(m)
                } else {
                    let m = CraftingBookMenu(game: game, size: 3); m.query = "sad"; m.searching = true; m.refresh()
                    game.openMenu(m)
                }
            case "craftbook", "craftbook_all", "craftbook2":
                // The crafting book (CraftingBook.swift) with a starter kit: logs, cobblestone, iron, sticks, string.
                for (i, (n, c)) in [("oak_log", 12), ("cobblestone", 30), ("iron_ingot", 9), ("stick", 8), ("string", 3), ("coal", 6),
                                    ("oak_planks", 20), ("redstone", 5)].enumerated() {
                    game.inventory.main[9 + i] = ItemStack(Items.id(n), c)
                }
                CraftingBookMenu.lastTab = which == "craftbook" ? .craftable : .building
                let m = CraftingBookMenu(game: game, size: which == "craftbook2" ? 2 : 3)
                game.openMenu(m)
                game.menuCursor = CraftCategory.allCases.count + 3           // a tile: the detail panel shows its recipe
                m.selected = m.recipe(at: 3)
            case "recipes":
                game.inventory.main[18] = ItemStack(Items.id("oak_log"), 8)
                game.inventory.main[19] = ItemStack(Items.id("cobblestone"), 20)
                game.inventory.main[20] = ItemStack(Items.id("iron_ingot"), 6)
                let m = CraftingTableMenu(game: game)
                game.openMenu(m)
                m.buttonPressed(490)
            case "title":
                let pm = PauseMenu(game: game); pm.page = .title; pm.build()
                game.openMenu(pm)
            case "credits":
                game.credits = 14
            case "pause":
                game.openMenu(PauseMenu(game: game))
            case "options":
                let pm = PauseMenu(game: game); pm.page = .options; pm.build()
                game.openMenu(pm)
            case "advancements":
                for id in ["root", "mine_stone", "upgrade_tools", "smelt_iron", "enter_the_nether", "mine_diamond", "adventure/trade", "nether/return_to_sender"] {
                    if let i = Advancements.index[id] { game.advancements.insert(Advancements.all[i].id) }
                }
                game.advToasts.append(("Shiny!", false, game.clock - 1))
                game.openMenu(AdvancementMenu(game: game))
            case "book":
                var b = ItemStack(Items.id("writable_book"), 1)
                b.pages = ["The first page of a travel log.\n\nDay 1: found a village by the river, traded wheat for emeralds. The librarian had mending!", "Day 2"]
                game.inventory.main[game.selected] = b
                game.openMenu(BookMenu(game: game, stack: b, source: .hand(game.selected)))
            case "loom":
                let m = LoomMenu(game: game)
                var ban = ItemStack(Items.id("blue_banner"), 1)
                ban.pat = [Banners.encode(28, 0)]
                m.box[0] = ban
                m.box[1] = ItemStack(Items.id("yellow_dye"), 4)
                m.selected = 9
                m.changed()
                game.inventory.main[9] = ItemStack(Items.id("red_banner"), 3)
                var om = ItemStack(Items.id("white_banner"), 1); om.pat = Banners.ominous
                game.inventory.main[10] = om
                game.openMenu(m)
            case "crafting":
                let m = CraftingTableMenu(game: game)
                for (i, n) in ["oak_planks", "oak_planks", "oak_planks", "", "stick", "", "", "stick", ""].enumerated() where !n.isEmpty {
                    m.craft.grid[i] = ItemStack(Items.id(n), 1)
                }
                m.changed()
                game.openMenu(m)
            case "furnace":
                let be = BlockEntity(.furnace)
                be.container[0] = ItemStack(Items.id("raw_iron"), 5)
                be.container[1] = ItemStack(Items.id("coal"), 3)
                be.container[2] = ItemStack(Items.id("iron_ingot"), 2)
                be.burn = 900; be.burnMax = 1600; be.cook = 120
                game.openMenu(FurnaceMenu(game: game, entity: be))
            case "brewing":
                let be = BlockEntity(.brewing)
                be.container[0] = ItemStack(Potions.item(0, "awkward")!, 1)
                be.container[1] = ItemStack(Potions.item(0, "strong_healing")!, 1)
                be.container[2] = ItemStack(Potions.item(1, "poison")!, 1)
                be.container[3] = ItemStack(Items.id("glistering_melon_slice"), 4)
                be.container[4] = ItemStack(Items.id("blaze_powder"), 2)
                be.fuel = 14; be.brewTime = 150; be.brewIngredient = be.container[3].item
                game.inventory.main[9] = ItemStack(Potions.item(2, "long_night_vision")!, 1)
                game.inventory.main[10] = ItemStack(Potions.item(3, "harming")!, 16)
                game.openMenu(BrewingMenu(game: game, entity: be))
            case "enchant":
                game.survival = true
                game.xpLevel = 30
                let m = EnchantMenu(game: game, at: IVec3(Int(floor(pos.x)), Int(floor(pos.y)), Int(floor(pos.z))))
                m.shelves = 15
                m.box[0] = ItemStack(Items.id("diamond_pickaxe"), 1)
                m.box[1] = ItemStack(Items.id("lapis_lazuli"), 12)
                m.changed()
                game.openMenu(m)
                var sword = ItemStack(Items.id("diamond_sword"), 1)
                sword.ench = Enchant.pack([(.sharpness, 5), (.looting, 3), (.unbreaking, 3), (.mending, 1), (.vanishingCurse, 1)])
                game.inventory.main[10] = sword
                game.menuCursor = 5 + 18 + 1
                game.menuHover = m.slots[game.menuCursor]
            case "trade":
                game.survival = true
                let v = Mob(.villager, at: pos + V3(2, 0, 0))
                var d = VillagerData()
                d.profession = arg("--profession") ?? "librarian"
                d.level = 3; d.xp = 90
                for l in 1...3 { Villagers.addOffers(&d, level: l) }
                if d.offers.count > 1 { d.offers[1].uses = d.offers[1].maxUses }
                v.villager = d
                game.mobs.mobs.append(v)
                game.inventory.main[9] = ItemStack(Items.id("emerald"), 40)
                game.inventory.main[10] = ItemStack(Items.id("paper"), 30)
                game.inventory.main[11] = ItemStack(Items.id("book"), 3)
                let mm = MerchantMenu(game: game, villager: v)
                game.openMenu(mm)
                mm.buttonPressed(0)
            case "anvil":
                game.survival = true
                game.xpLevel = 12
                let m = AnvilMenu(game: game, at: IVec3(0, 0, 0))
                var pick = ItemStack(Items.id("diamond_pickaxe"), 1); pick.damage = 900
                pick.ench = Enchant.pack([(.efficiency, 4)])
                var book = ItemStack(Items.id("enchanted_book"), 1)
                book.ench = Enchant.pack([(.efficiency, 4), (.fortune, 3)])
                m.box[0] = pick; m.box[1] = book
                m.name = "Digger"; m.editing = true
                m.changed()
                game.openMenu(m)
            default:
                game.survival = true
                game.applyEffect(.speed, amp: 1, seconds: 95)
                game.applyEffect(.regeneration, amp: 0, seconds: 30)
                game.applyEffect(.poison, amp: 0, seconds: 8)
                game.openMenu(InventoryMenu(game: game))
            }
            if !(game.menu is EnchantMenu) {
                let n = game.menu?.slots.count ?? 0
                game.menuCursor = min(12, max(0, n - 1))
                game.menuHover = n > 0 ? game.menu?.slots[game.menuCursor] : nil
            }
            game.input.mouseX = -1
        }
        var t = world.loadSync(center: pos, radius: rd)
        let caveFind = ["lush_caves", "dripstone_caves", "deep_dark"].contains(arg("--find") ?? "")
        if caveFind {
            // Down the column to the first open cave pocket with a floor (deep dark: below y 0); when the column has
            // none, the nearest column that does (the deep dark shot found no pocket in its column, stopped at the
            // search floor inside rock, and the solid-camera fallback moved it into a lush cave: run 370).
            let x0 = Int(floor(pos.x)), z0 = Int(floor(pos.z))
            let deep = arg("--find") == "deep_dark"
            let top = deep ? YOFF - 2 : SEA - 12
            // A dry pocket: two air blocks on a solid floor and no water or lava within 2 blocks of the floor or the
            // eye (lava next to the pocket flows in and the camera ended up inside it).
            func dryPocket(_ x: Int, _ y: Int, _ z: Int) -> Bool {
                guard world.block(x, y, z) == AIR && world.block(x, y + 1, z) == AIR && Blocks.collide[Int(world.block(x, y - 1, z))] else { return false }
                for dy in -1...3 { for dz in -2...2 { for dx in -2...2 where Blocks.fluidKind[Int(world.block(x + dx, y + dy, z + dz))] != 0 { return false } } }
                return true
            }
            var found: IVec3?
            search: for r in 0...40 { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r && (dx + dz) % 2 == 0 {
                let x = x0 + dx, z = z0 + dz
                if deep, let wg = world.gen as? WorldGen, wg.climate(x, z).e >= -0.6 { continue }
                var y = top
                while y > 8 && !dryPocket(x, y, z) { y -= 1 }
                if y > 8 { found = IVec3(x, y, z); break search }
            } } }
            if let f = found {
                pos = V3(Float(f.x) + 0.5, Float(f.y) + (Float(arg("--up") ?? "") ?? 0), Float(f.z) + 0.5)
                game.player.pos = pos
                print("cave pocket at \(f.x) \(f.y - YOFF) \(f.z)")
            } else { print("cave pocket: none within 40 blocks") }
        } else if snapDim == .overworld && arg("--structure") == nil && arg("--find") == nil && arg("--x") == nil {
            // Default spawn view: step off tree canopies onto open ground so the camera isn't in leaves.
            let bx = Int(floor(pos.x)), bz = Int(floor(pos.z))
            func openGround(_ x: Int, _ z: Int) -> Bool {
                let t = world.topY(x, z)
                let k = Blocks.key(world.block(x, t, z))
                if k.hasSuffix("_leaves") || k.hasSuffix("_log") || Blocks.isLiquid(world.block(x, t, z)) { return false }
                // Room to look around: nothing solid within 2 blocks of the eye (walls, portal frames).
                for dy in 1...3 { for dz in -2...2 { for dx in -2...2 where Blocks.collide[Int(world.block(x + dx, t + dy, z + dz))] { return false } } }
                return true
            }
            if !openGround(bx, bz) {
                search: for r in 1...24 { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r && openGround(bx + dx, bz + dz) {
                    pos.x = Float(bx + dx) + 0.5; pos.z = Float(bz + dz) + 0.5; break search
                } } }
            }
            let up = Float(arg("--up") ?? "") ?? 0
            pos.y = Float(world.topY(Int(floor(pos.x)), Int(floor(pos.z))) + 1) + up
            game.player.pos = pos
        }
        if snapDim == .overworld && arg("--structure") == nil && !caveFind {
            // Stand on whatever is actually at the column (trees, overhangs), keeping --up.
            let up = Float(arg("--up") ?? "") ?? 0
            let ty = Float(world.topY(Int(floor(pos.x)), Int(floor(pos.z))) + 1)
            if ty + up > pos.y { pos.y = ty + up; game.player.pos = pos }
        }
        if let n = Float(arg("--seabed") ?? "") {
            // Under the sea: the camera N blocks above the floor (the floor is often 25-35 blocks down).
            let x = Int(floor(pos.x)), z = Int(floor(pos.z))
            var y = SEA
            while y > 1 && !Blocks.collide[Int(world.block(x, y, z))] { y -= 1 }
            pos.y = Float(y + 1) + n
            game.player.pos = pos
            print("seabed at y \(y - YOFF), camera \(n) above")
        }
        if CommandLine.arguments.contains("--ground") {
            // Under the canopy: stand on the real ground (skip leaves, logs, plants).
            let x = Int(floor(pos.x)), z = Int(floor(pos.z))
            var y = world.topY(x, z)
            while y > 1 {
                let b = world.block(x, y, z), k = Blocks.key(b)
                if Blocks.collide[Int(b)] && !k.hasSuffix("_leaves") && !k.hasSuffix("_log") { break }
                y -= 1
            }
            pos.y = Float(y + 1) + (Float(arg("--up") ?? "") ?? 0)
            game.player.pos = pos
        }
        // --feet Y: the camera's feet at displayed height Y (structcheck issue views from inside a structure).
        if let fy = Float(arg("--feet") ?? "") { pos.y = fy + Float(YOFF); game.player.pos = pos }
        if let a = insideFrame {
            // Feet on the start piece's floor, facing the heading with the longest clear line at eye level.
            var fy = a.y + 3
            func free(_ x: Int, _ y: Int, _ z: Int) -> Bool { !Blocks.collide[Int(world.block(x, y, z))] }
            while fy > a.y - 6 && !(free(a.x, fy, a.z) && free(a.x, fy + 1, a.z) && !free(a.x, fy - 1, a.z)) { fy -= 1 }
            var bestYaw: Float = 0, bestRun = -1
            for h in 0..<16 {
                let yaw: Float = Float(h) * Float.pi / 8
                let dir = V3(-sinf(yaw), 0, -cosf(yaw))
                var run = 0
                for step in 1...80 {
                    let q: V3 = V3(Float(a.x) + 0.5, Float(fy) + 1.6, Float(a.z) + 0.5) + dir * (Float(step) * 0.5)
                    if !free(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z))) { break }
                    run = step
                }
                if run > bestRun { bestRun = run; bestYaw = yaw }
            }
            pos = V3(Float(a.x) + 0.5, Float(fy), Float(a.z) + 0.5)
            game.player.pos = pos
            game.player.yaw = bestYaw
            game.player.pitch = -6 * Float.pi / 180
            print("structure buried: camera at its start \(a.x) \(fy - YOFF) \(a.z), facing \(Int(bestYaw * 180 / Float.pi)) deg down a \(bestRun / 2)-block corridor")
        }
        // Never render from inside solid blocks: move to the nearest two-high air pocket.
        func solidAt(_ p: V3) -> Bool { Blocks.collide[Int(world.block(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))))] }
        if solidAt(game.player.eye) || solidAt(game.player.pos + V3(0, 0.1, 0)) {
            let b = IVec3(Int(floor(pos.x)), Int(floor(pos.y)), Int(floor(pos.z)))
            var best: IVec3?
            // Prefer a spot with a clear 3x3x3 around the eye (not pressed against a wall), else any 2-high pocket.
            func clear(_ q: IVec3) -> Bool {
                for dy in 0...2 { for dz in -1...1 { for dx in -1...1 where Blocks.collide[Int(world.block(q.x + dx, q.y + dy, q.z + dz))] { return false } } }
                return true
            }
            var pocket: IVec3?
            search: for r in 1...24 {
                for dy in [0] + (1...r).flatMap({ [$0, -$0] }) { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz), abs(dy)) == r {
                    let q = IVec3(b.x + dx, b.y + dy, b.z + dz)
                    if !Blocks.collide[Int(world.block(q.x, q.y, q.z))] && !Blocks.collide[Int(world.block(q.x, q.y + 1, q.z))] {
                        if pocket == nil { pocket = q }
                        if clear(q) { best = q; break search }
                    }
                } } }
            }
            if best == nil { best = pocket }
            if let q = best {
                print("camera in solid at \(b.x) \(b.y - YOFF) \(b.z): moved to \(q.x) \(q.y - YOFF) \(q.z)")
                pos = V3(Float(q.x) + 0.5, Float(q.y), Float(q.z) + 0.5)
                game.player.pos = pos
            } else { print("camera in solid: no air pocket nearby") }
        }
        if CommandLine.arguments.contains("--unblock") {
            // A view pressed against a wall or a canopy (night / dark_forest showed one leaf face: blind critic, run 395):
            // step back and up until the line of sight runs at least 12 blocks, keeping the best spot found.
            func clearAhead(_ p: V3) -> Float {
                let e = p + V3(0, 1.62, 0)
                if Blocks.collide[Int(world.block(Int(floor(e.x)), Int(floor(e.y)), Int(floor(e.z))))] { return 0 }
                if let h = world.raycast(e, game.player.look, maxDist: 32) {
                    return simd_length(V3(Float(h.hit.x) + 0.5, Float(h.hit.y) + 0.5, Float(h.hit.z) + 0.5) - e)
                }
                return 32
            }
            let back = simd_normalize(V3(-game.player.look.x, 0, -game.player.look.z))
            var bestP = pos, bestD = clearAhead(pos)
            if bestD < 12 {
                search: for up in 0...6 { for k in 0...10 {
                    let q = pos + back * Float(k) + V3(0, Float(up), 0)
                    let d = clearAhead(q)
                    if d > bestD + 0.5 { bestD = d; bestP = q }
                    if d >= 12 { break search }
                } }
                print(String(format: "unblock: moved %.1f blocks for a %.1f-block view", simd_length(bestP - pos), bestD))
                pos = bestP
                game.player.pos = pos
            }
        }
        if snapDim == .nether {
            // Stand in the first open space above the lava sea.
            let x = Int(floor(pos.x)), z = Int(floor(pos.z))
            var y = YOFF + 33
            while y < YOFF + 120 && !(world.block(x, y, z) == AIR && world.block(x, y + 1, z) == AIR) { y += 1 }
            pos.y = Float(y) + (Float(arg("--up") ?? "") ?? 0)
            game.player.pos = pos
        } else if snapDim == .deep {
            // The Ash Vault's floor, or with --hell the first open space above the hell band's lava sea.
            let x = Int(floor(pos.x)), z = Int(floor(pos.z))
            var y = (world.gen as? DeepGen)?.floorY(x, z) ?? 30
            if CommandLine.arguments.contains("--hell") {
                y = DeepGen.hellBase + 33
                while y < DeepGen.hellBase + 120 && !(world.block(x, y, z) == AIR && world.block(x, y + 1, z) == AIR) { y += 1 }
            } else { y += 1 }
            pos.y = Float(y) + (Float(arg("--up") ?? "") ?? 0)
            game.player.pos = pos
        } else if snapDim == .end {
            pos = V3(pos.x, Float(YOFF + 70) + (Float(arg("--up") ?? "") ?? 0), pos.z)
            game.player.pos = pos
        }
        // `--cavey Y`: stand in the nearest open cave space around internal y YOFF + Y (displayed y Y on the surface).
        if let cy = arg("--cavey").flatMap({ Int($0) }) {
            let x0 = Int(floor(pos.x)), z0 = Int(floor(pos.z)), y0 = cy + YOFF
            func open(_ x: Int, _ y: Int, _ z: Int) -> Bool {
                world.block(x, y, z) == AIR && world.block(x, y + 1, z) == AIR && Blocks.opaque[Int(world.block(x, y - 1, z))]
            }
            search: for r in stride(from: 0, through: 64, by: 2) { for dz in stride(from: -r, through: r, by: 2) { for dx in stride(from: -r, through: r, by: 2) where max(abs(dx), abs(dz)) == r {
                for dy in [0, -2, 2, -4, 4, -6, 6, -8, 8] where open(x0 + dx, y0 + dy, z0 + dz) {
                    pos = V3(Float(x0 + dx) + 0.5, Float(y0 + dy) + (Float(arg("--up") ?? "") ?? 0), Float(z0 + dz) + 0.5)
                    break search
                }
            } } }
            game.player.pos = pos
            print(String(format: "cavey: standing at %.0f %.0f %.0f", pos.x, pos.y - Float(YOFF), pos.z))
        }
        // Structure mobs (crystals, boarlings...) that generation queued.
        for (name, mp) in world.pendingMobs {
            if let m = Mob.structureMob(name, at: mp) { m.persistent = false; game.mobs.mobs.append(m) }
        }
        world.pendingMobs.removeAll()
        if CommandLine.arguments.contains("--dragon") {
            let f = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw))
            let d = Mob(.enderDragon, at: pos + f * 26 + V3(0, 2, 0))
            d.yaw = game.player.yaw + 1.2
            d.walkPhase = 0.7
            d.healTarget = game.mobs.mobs.filter { $0.kind == .endCrystal }.min { simd_length($0.pos - d.pos) < simd_length($1.pos - d.pos) }
            game.mobs.mobs.append(d)
        }
        if CommandLine.arguments.contains("--portal") {
            let f = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw))
            let c = pos + f * 6
            _ = game.buildPortal(near: IVec3(Int(floor(c.x)), 0, Int(floor(c.z))))
            let t2 = world.loadSync(center: pos, radius: rd)
            t.mesh += t2.mesh
        }
        if CommandLine.arguments.contains("--drops") {
            // A few dropped items and a half-broken block in front of the camera.
            let f = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw))
            for (i, n) in ["diamond", "oak_log", "iron_pickaxe", "apple", "cobblestone", "torch"].enumerated() {
                let p = pos + f * (3 + Float(i % 3)) + V3(Float(i / 3) * 1.2 - 0.6, 0, 0)
                let y = world.topY(Int(floor(p.x)), Int(floor(p.z))) + 1
                game.drops.spawn(ItemStack(Items.id(n), i == 4 ? 40 : 1), at: V3(p.x, Float(y), p.z), vel: .zero)
            }
            game.target = nil
            let tx = Int(floor(pos.x + f.x * 2)), tz = Int(floor(pos.z + f.z * 2))
            game.mining = IVec3(tx, world.topY(tx, tz), tz)
            game.mineProgress = 0.55
        }

        if CommandLine.arguments.contains("--flood") {
            // Fluid test: a spring on the ground and one hanging in the air, then simulate 12 s of flow.
            let bx = Int(floor(pos.x)), bz = Int(floor(pos.z)) - 8
            let h1 = world.gen.column(bx, bz).height
            world.setBlock(bx, h1 + 1, bz, WATER)
            let h2 = world.gen.column(bx + 6, bz + 2).height
            world.setBlock(bx + 6, h2 + 5, bz + 2, WATER)
            for _ in 0..<60 { world.fluidTick() }
            let t2 = world.loadSync(center: pos, radius: rd)
            t.mesh += t2.mesh
            print("fluid cells pending after 60 ticks: \(world.fluidPending.count)")
        }
        if CommandLine.arguments.contains("--mobs") {
            // A few animals standing in front of the camera, legs mid-stride.
            let f = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw)), r = V3(cosf(game.player.yaw), 0, -sinf(game.player.yaw))
            let nether = CommandLine.arguments.contains("--nethermobs")
            // --mobkind a,b: those kinds side by side 5 blocks ahead; --mobyaw DEG turns them (90 = side on), --mobwalk A sets
            // the stride (0 stands), --mobspeed S gives them a velocity (gallop poses), --saddled saddles them.
            let kindNames = arg("--mobkind")?.split(separator: ",").map(String.init) ?? []
            let mobKinds: [(MobKind, Float, Float)] = kindNames.compactMap { MobKind.named($0) }.enumerated().map { ($0.element, Float(5), Float($0.offset) * 3.5 - 1.75) }
            let spots: [(MobKind, Float, Float)] = nether
                ? [(.zombifiedPiglin, 5, -2.5), (.piglin, 5, 0), (.witherSkeleton, 6, 2.5), (.blaze, 8, -3.5), (.magmaCube, 7, 3.5), (.ghast, 22, 2)]
                : CommandLine.arguments.contains("--hostile")
                ? [(.zombie, 5, -2.5), (.skeleton, 6, 0), (.creeper, 5, 2.5), (.spider, 9, -3.5), (.enderman, 10, 1), (.slime, 8, 4)]
                : mobKinds.isEmpty == false ? mobKinds
                : [(.cow, 6, -2.5), (.sheep, 6, 1.5), (.chicken, 4, 0), (.pig, 10, 3), (.sheep, 9, -4), (.chicken, 5, 2.5)]
            for (i, spot) in spots.enumerated() {
                let p = pos + f * spot.1 + r * spot.2
                let x = Int(floor(p.x)), z = Int(floor(p.z))
                var y = game.mobs.grassSurface(world, x, z) ?? (world.gen.column(x, z).height + 1)
                // Underground (the surface well above the eye): on the floor below the camera, as in the Nether (in a
                // cave they stood on the ground above its ceiling: cave_dark_mobs drew the same image as lush_caves).
                if nether || y > Int(floor(pos.y)) + 4 {
                    y = Int(floor(pos.y)) + 1
                    while y > Int(pos.y) - 12 && !Blocks.collide[Int(world.block(x, y - 1, z))] { y -= 1 }
                    if spot.0 == .ghast || spot.0 == .blaze { y += spot.0 == .ghast ? 5 : 2 }
                }
                let m = Mob(spot.0, at: V3(Float(x) + 0.5, Float(y), Float(z) + 0.5))
                if spot.0 == .slime || spot.0 == .magmaCube { m.makeSlime(size: 2) }
                m.yaw = game.player.yaw + .pi + Float(i) * 0.9
                m.walkPhase = Float(i) * 0.8
                m.walkAmount = 1
                if !mobKinds.isEmpty {
                    m.yaw = game.player.yaw + (Float(arg("--mobyaw") ?? "90") ?? 90) * .pi / 180
                    m.walkAmount = Float(arg("--mobwalk") ?? "1") ?? 1
                    m.walkPhase = Float(i) * 1.3 + 0.8
                    let sp = Float(arg("--mobspeed") ?? "0") ?? 0
                    m.vel = V3(-sinf(m.yaw), 0, -cosf(m.yaw)) * sp
                    m.callTimer = CommandLine.arguments.contains("--mobgraze") ? 4 : 10
                    if CommandLine.arguments.contains("--saddled") { m.saddled = true }
                }
                game.mobs.mobs.append(m)
            }
        }
        if let wx = arg("--weather") {
            game.weather.raining = true; game.weather.rain = 1
            if wx == "thunder" {
                game.weather.thundering = true; game.weather.thunder = 1
                let f = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw))
                let sp = pos + f * 18
                game.strike(V3(sp.x, Float(world.topY(Int(floor(sp.x)), Int(floor(sp.z))) + 1), sp.z))
                game.lightningFlash = 0.3
            }
        }
        if CommandLine.arguments.contains("--fireworks") {
            // Five rockets bursting 20 blocks ahead: every shape, trails, twinkles, fades.
            let f = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw)), r = V3(cosf(game.player.yaw), 0, -sinf(game.player.yaw))
            for i in 0..<5 {
                var st = ItemStack(Items.id("firework_star"), 1)
                st.tag = i | (i % 2 == 0 ? 8 : 0) | (i == 3 ? 16 : 0) | (1 << 8)
                let pats: [[Int]] = [[14, 4], [11, 3], [5, 0], [13, 5], [1, 2, 4]]
                st.pat = pats[i] + (i == 1 ? [16] : [])
                let lift: Float = 10 + Float(i % 2) * 4
                let side: Float = (Float(i) - 2) * 7
                let at: V3 = pos + f * 22 + r * side + V3(0, lift, 0)
                let rk = Rocket(at: at, dir: V3(0, 1, 0), flight: 1, stars: [st])
                game.explode(rk)
            }
            game.particles.update(0.45, world)
        }
        if CommandLine.arguments.contains("--beacon") {
            // A four-layer iron/gold/diamond pyramid with a powered beacon 12 blocks ahead.
            let f = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw))
            let c = pos + f * 12
            let bx = Int(floor(c.x)), bz = Int(floor(c.z))
            let gy = world.topY(bx, bz) + 1
            let mats = ["iron_block", "gold_block", "diamond_block", "emerald_block"]
            for l in 1...4 {
                for dz in -l...l { for dx in -l...l { world.setBlock(bx + dx, gy + 4 - l, bz + dz, Blocks.id(mats[l - 1])) } }
            }
            for y in (gy + 5)..<CH { for dz in -1...1 { for dx in -1...1 where world.block(bx + dx, y, bz + dz) != AIR { world.setBlock(bx + dx, y, bz + dz, AIR) } } }
            let bp = IVec3(bx, gy + 4, bz)
            world.setBlock(bp.x, bp.y, bp.z, Blocks.id("beacon"))
            let be = BlockEntity(.beacon)
            be.mob = "speed"; be.secondary = "speed"
            world.blockEntities[bp] = be
            game.beaconTick()
            print("beacon level \(be.level), player speed \(game.effects.level(.speed))")
        }
        if CommandLine.arguments.contains("--map") {
            // Hold a freshly explored map.
            game.inventory.main[game.selected] = ItemStack(Items.id("map"), 1)
            _ = game.useEmptyMap()
            // Creative keeps the empty map; hold the new filled one.
            if let i = (0..<36).first(where: { Items.key(game.inventory.main[$0].item) == "filled_map" }) {
                game.inventory.main[game.selected] = game.inventory.main[i]
            }
            for _ in 0..<256 { game.mapTick() }
        }
        if CommandLine.arguments.contains("--banners") {
            // A row of standing banners 5 blocks ahead (the last one omen) plus two on a wall behind.
            let f = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw)), r = V3(cosf(game.player.yaw), 0, -sinf(game.player.yaw))
            let sets: [(String, [Int])] = [("red", [Banners.encode(10, 0)]), ("blue", [Banners.encode(27, 4), Banners.encode(29, 0)]),
                                           ("white", Banners.ominous), ("black", [Banners.encode(34, 5)]), ("yellow", [Banners.encode(30, 11), Banners.encode(36, 14)]),
                                           ("green", [Banners.encode(23, 0), Banners.encode(24, 0), Banners.encode(33, 12)])]
            for (i, st) in sets.enumerated() {
                let off: Float = (Float(i) - Float(sets.count - 1) / 2) * 1.6
                let p: V3 = pos + f * 8 + r * off
                let x = Int(floor(p.x)), z = Int(floor(p.z))
                let y = world.topY(x, z) + 1
                var a = (game.player.yaw + .pi) / (2 * .pi) * 16
                a = a.rounded()
                world.setBlock(x, y, z, Blocks.id("\(st.0)_banner") + BlockID(((Int(a) % 16) + 16) % 16))
                let be = BlockEntity(.banner); be.patterns = st.1
                world.blockEntities[IVec3(x, y, z)] = be
            }
        }
        if CommandLine.arguments.contains("--decor") {
            // A stone wall 5 blocks ahead with a sign, item frames and a painting on it.
            let f = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw))
            let c = pos + f * 5
            let bx = Int(floor(c.x)), bz = Int(floor(c.z))
            let gy = world.topY(bx, bz) + 1
            // Wall runs along x or z depending on the view; build it along x facing -z (north side visible from the camera if camera is north).
            let facing = abs(f.x) > abs(f.z) ? (f.x > 0 ? 2 : 3) : (f.z > 0 ? 0 : 1)
            let along = facing < 2 ? IVec3(1, 0, 0) : IVec3(0, 0, 1)
            let toward = [IVec3(0, 0, -1), IVec3(0, 0, 1), IVec3(-1, 0, 0), IVec3(1, 0, 0)][facing]
            for k in -4...4 { for dy in 0..<4 { world.setBlock(bx + along.x * k, gy + dy, bz + along.z * k, Blocks.id("stone_bricks")) } }
            func front(_ k: Int, _ dy: Int) -> IVec3 { IVec3(bx + along.x * k + toward.x, gy + dy, bz + along.z * k + toward.z) }
            let sp = front(-3, 1)
            world.setBlock(sp.x, sp.y, sp.z, Blocks.id("oak_sign") + BlockID(4 + facing))
            let sb = BlockEntity(.sign); sb.lines = ["Welcome to", "Blocksmith", "", "-- 2026 --"]; world.blockEntities[sp] = sb
            // A rifle too: the armory's gun racks drew empty frames (run 395); sword and apple draw.
            for (i, it) in ["diamond_sword", "apple", "gun_rifle"].enumerated() where Items.has(it) {
                let fp = i == 2 ? front(-2, 2) : front(-1 + i, 2)
                world.setBlock(fp.x, fp.y, fp.z, Blocks.id("item_frame") + BlockID(facing))
                let fb = BlockEntity(.frame); fb.container[0] = ItemStack(Items.id(it), 1); world.blockEntities[fp] = fb
            }
            game.placePainting(at: front(1, 1), facing: facing)
        }
        if CommandLine.arguments.contains("--chips") {
            // Progressive block damage: blocks 4 ahead chipped to levels 1...7 from the side facing the camera, in
            // three materials, on a floor.
            let f = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw))
            let c = pos + f * 5
            let bx = Int(floor(c.x)), bz = Int(floor(c.z))
            let gy = world.topY(bx, bz) + 1
            let xAxis = abs(f.z) > abs(f.x)
            let face = xAxis ? (f.z > 0 ? 5 : 4) : (f.x > 0 ? 1 : 0)
            for (row, name) in ["stone", "oak_planks", "bricks"].enumerated() {
                for k in 0..<8 {
                    let off = k - 4
                    let p = IVec3(bx + (xAxis ? off : 0), gy + row, bz + (xAxis ? 0 : off))
                    world.setBlock(p.x, p.y, p.z, Blocks.has(name) ? Blocks.id(name) : STONE)
                    if k > 0 { world.chip(p, level: k, face: face) }
                }
            }
            print("chips: \(world.damage.count) chipped blocks")
        }
        if CommandLine.arguments.contains("--stage") {
            // A flat grass stage in front of the camera (17 deep, 25 wide, open sky) so mob and item shots aren't hidden by
            // the realistic terrain's slopes, ravines and bushes.
            let f = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw)), r = V3(cosf(game.player.yaw), 0, -sinf(game.player.yaw))
            let up = Float(arg("--up") ?? "") ?? 0
            let gb = Int(floor(pos.y - up)) - 1                      // the ground block under the camera
            for sx in 0...16 { for t in -12...12 {
                let q: V3 = pos + f * Float(sx) + r * Float(t)
                let x = Int(floor(q.x)), z = Int(floor(q.z))
                for y in (gb + 1)...(gb + 16) { _ = world.setBlockAsync(x, y, z, AIR) }
                _ = world.setBlockAsync(x, gb, z, GRASS)
                for y in (gb - 3)..<gb where !Blocks.collide[Int(world.block(x, y, z))] { _ = world.setBlockAsync(x, y, z, Blocks.id("dirt")) }
            } }
            _ = world.loadSync(center: pos, radius: rd)
        }
        if let list = arg("--spawn") {
            // Mobs in a row 6 blocks in front of the camera, facing it ("kind" or "kind:profession").
            let f = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw)), r = V3(cosf(game.player.yaw), 0, -sinf(game.player.yaw))
            let names = list.split(separator: ",").map(String.init)
            for (i, n) in names.enumerated() {
                let parts = n.split(separator: ":").map(String.init)
                guard let k = MobKind.named(parts[0]) else { print("unknown mob \(n)"); continue }
                var off: Float = (Float(i) - Float(names.count - 1) / 2) * 2.2
                var ahead: Float = 6
                // "side=X" / "back=Y": an exact spot (blocks right of the view line / further away) for formations.
                for t in parts where t.hasPrefix("side=") || t.hasPrefix("back=") {
                    let v = Float(t.dropFirst(5)) ?? 0
                    if t.hasPrefix("side=") { off = v } else { ahead = 6 + v }
                }
                let p: V3 = pos + f * ahead + r * off
                let x = Int(floor(p.x)), z = Int(floor(p.z))
                let exact = parts.contains { $0.hasPrefix("side=") || $0.hasPrefix("back=") }
                var groundY = world.topY(x, z) + 1
                if CommandLine.arguments.contains("--spawnlevel") {
                    // On the floor at the camera's level, not on the roof above it (courtyards, halls, decks).
                    func solid(_ y: Int) -> Bool { Blocks.collide[Int(world.block(x, y, z))] }
                    if let y = stride(from: Int(floor(pos.y)) + 1, through: Int(floor(pos.y)) - 16, by: -1).first(where: { solid($0 - 1) && !solid($0) && !solid($0 + 1) }) { groundY = y }
                }
                let m = Mob(k, at: V3(exact ? p.x : Float(x) + 0.5, Float(groundY), exact ? p.z : Float(z) + 0.5))
                m.yaw = game.player.yaw
                if k == .boat {
                    m.variant = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
                    m.chested = parts.count > 2
                    m.yaw += Float(i) * 0.4
                } else if k == .copperGolem {
                    // "copper_golem:2" = weathered; ":carry" holds a load.
                    m.variant = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
                    m.cargo = ItemContainer(1)
                    if parts.contains("carry") { m.cargo![0] = ItemStack(Items.id("cobblestone"), 16) }
                } else if parts.count > 1 && ["leather", "golden", "chainmail", "iron", "diamond", "netherite", "copper"].contains(parts[1]) {
                    // "zombie:iron" / "armor_stand:diamond": a full set of that armour (+ a sword).
                    var eq = ["helmet", "chestplate", "leggings", "boots"].map { p -> ItemStack in
                        let n = parts[1] == "leather" && p == "helmet" ? "leather_helmet" : "\(parts[1])_\(p)"
                        return Items.has(n) ? ItemStack(Items.id(n), 1) : .empty
                    }
                    eq.append(Items.has("\(parts[1])_sword") ? ItemStack(Items.id("\(parts[1])_sword"), 1) : .empty)
                    m.equip = eq
                } else if parts.count > 1 && parts[1] == "captain" {
                    m.captain = true                                 // raid captain with the omen banner
                } else if parts.count > 1 && parts[1] == "aggro" {
                    m.aggro = true                                   // soldiers raise their guns
                    if parts.count > 2, let gi = Int(parts[2]) { m.variant = gi }
                } else if parts.count > 1, let v = Int(parts[1]) {
                    m.variant = v                                    // "cow:2" = a warm cow (FarmVariants), "cat:3"...
                } else if parts.count > 1 { var d = VillagerData(); d.profession = parts[1]; m.villager = d }
                if k == .wither { m.phase = 0; m.pos.y += 2 }
                if k == .evoker { m.spellTimer = 4.5 }
                if CommandLine.arguments.contains("--facecam") { m.yaw = game.player.yaw + .pi }
                if Soldier.rank(k) != nil { SoldierRig.stage(m, Array(parts.dropFirst()), world: world) }    // stance tokens
                game.mobs.mobs.append(m)
            }
        }
        if let list = arg("--place") {
            // Blocks in a row 4 blocks in front of the camera on a smooth stone strip ("name" or "name:state").
            let f = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw)), r = V3(cosf(game.player.yaw), 0, -sinf(game.player.yaw))
            let names = list.split(separator: ",").map(String.init)
            for (i, n) in names.enumerated() {
                let parts = n.split(separator: ":")
                guard Blocks.has(String(parts[0])) else { print("unknown block \(n)"); continue }
                let off: Float = (Float(i) - Float(names.count - 1) / 2) * 1.5
                let p: V3 = pos + f * 4 + r * off
                let x = Int(floor(p.x)), z = Int(floor(p.z))
                let gy = world.topY(x, z)
                world.setBlock(x, gy, z, Blocks.id("smooth_stone"))
                world.setBlock(x, gy + 1, z, Blocks.id(String(parts[0])) + BlockID(parts.count > 1 ? Int(parts[1]) ?? 0 : 0))
            }
        }
        if let list = arg("--gallery") {
            // Block gallery: a wall of up to 8 x 4 blocks, 7 blocks ahead, facing the camera (texture review).
            let f = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw)), r = V3(cosf(game.player.yaw), 0, -sinf(game.player.yaw))
            let names: [String] = list.split(separator: ",").map { String($0) }.filter { (n: String) -> Bool in Blocks.has(String(n.split(separator: ":")[0])) }
            let cols = min(8, max(1, names.count))
            let base = game.player.eye + f * 7
            for (i, n) in names.prefix(32).enumerated() {
                let parts = n.split(separator: ":")
                let col = i % cols, row = i / cols
                let p = base + r * (Float(col) - Float(cols - 1) / 2) + V3(0, 1.5 - Float(row), 0)
                world.setBlock(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)),
                               Blocks.id(String(parts[0])) + BlockID(parts.count > 1 ? Int(parts[1]) ?? 0 : 0))
            }
        }
        if CommandLine.arguments.contains("--redstone") {
            // A test bench on a stone platform east of the camera, then 3 s of sparkstone ticks.
            let bx = Int(floor(pos.x)) + 3, bz = Int(floor(pos.z)) - 6
            let gy = world.topY(bx + 6, bz + 5)
            func put(_ x: Int, _ z: Int, _ n: String, _ st: Int = 0, dy: Int = 1) { world.setBlock(bx + x, gy + dy, bz + z, Blocks.id(n) + BlockID(st)) }
            for z in -1...12 { for x in -1...14 {
                world.setBlock(bx + x, gy, bz + z, Blocks.id("smooth_stone"))
                for k in 1...5 { world.setBlock(bx + x, gy + k, bz + z, AIR) }
            } }
            // Row A: lever -> dust -> repeater -> dust -> lamp.
            put(0, 0, "lever", 3 + 12)                                   // floor lever, on
            for x in 1...5 { put(x, 0, "redstone_wire") }
            put(6, 0, "repeater", 3 + 4 * 2)                             // facing east, delay 3
            for x in 7...8 { put(x, 0, "redstone_wire") }
            put(9, 0, "redstone_lamp")
            // Row B: sparkstone block powering a sticky piston that pushes slime + stone.
            put(0, 3, "redstone_block")
            put(1, 3, "sticky_piston", 5)                                 // facing east
            put(2, 3, "cobblestone"); put(3, 3, "oak_planks")
            put(6, 3, "piston", 5); put(7, 3, "slime_block", dy: 1); put(7, 3, "stone", dy: 2) // unpowered for comparison
            // Row C: torch inverter: lever on a block, torch on its far side stays off; unpowered torch on the right.
            put(0, 6, "stone"); put(0, 6, "lever", 3 + 12, dy: 2)             // lever on top of the block, on
            put(1, 6, "redstone_torch", 2 + 3)                            // wall torch facing east (attached west)
            for x in 2...4 { put(x, 6, "redstone_wire") }
            put(5, 6, "redstone_lamp")
            put(8, 6, "redstone_torch"); for x in 9...10 { put(x, 6, "redstone_wire") }; put(11, 6, "redstone_lamp")
            // Row D: observer clock driving a lamp.
            put(0, 9, "observer", 5); put(1, 9, "observer", 4)
            put(2, 9, "redstone_wire"); put(3, 9, "redstone_lamp")
            // Row E: comparator reading a chest with items.
            put(6, 10, "chest")
            world.blockEntities[IVec3(bx + 6, gy + 1, bz + 10)] = { let b = BlockEntity(.chest); b.container[0] = ItemStack(Items.id("cobblestone"), 64); b.container[1] = ItemStack(Items.id("cobblestone"), 64); return b }()
            put(7, 10, "comparator", 3)
            for x in 8...11 { put(x, 10, "redstone_wire") }
            // Row F: a rail loop corner with a powered rail, a detector rail and a minecart.
            for x in 0...6 { put(x, 12, "rail") }
            put(7, 12, "rail"); put(7, 11, "rail")
            for x in 0...7 { Rails.autoShape(world, IVec3(bx + x, gy + 1, bz + 12)) }
            put(3, 12, "powered_rail", 1); put(2, 13, "redstone_block", dy: 1); put(5, 12, "detector_rail", 1)
            game.mobs.mobs.append(Mob(.minecart, at: V3(Float(bx) + 1.5, Float(gy + 1) + 0.0625, Float(bz) + 12.5)))
            for _ in 0..<60 { world.redstone.tick() }
            // Look at the bench from the south-west, above.
            pos = V3(Float(bx) - 5, Float(gy) + 11, Float(bz) + 16)
            game.player.pos = pos
            let c = V3(Float(bx) + 6, Float(gy), Float(bz) + 5)
            let d = c - pos
            game.player.yaw = atan2f(-d.x, -d.z)
            game.player.pitch = atan2f(d.y, simd_length(V2(d.x, d.z)))
            let t2 = world.loadSync(center: pos, radius: rd)
            t.mesh += t2.mesh
            let pp = IVec3(bx + 1, gy + 1, bz + 3)
            print("piston debug: power \(world.redstone.received(pp)) block west \(Blocks.key(world.block(pp.x - 1, pp.y, pp.z))) front \(Blocks.key(world.block(pp.x + 1, pp.y, pp.z))) kind \(Circuit.kind(world.block(pp.x, pp.y, pp.z)))")
            print("redstone bench: lamp A \(Blocks.key(world.block(bx + 9, gy + 1, bz))), piston \(Blocks.key(world.block(bx + 1, gy + 1, bz + 3))), lamp C \(Blocks.key(world.block(bx + 5, gy + 1, bz + 6))) / \(Blocks.key(world.block(bx + 11, gy + 1, bz + 6))), wire E \(Blocks.key(world.block(bx + 11, gy + 1, bz + 10)))")
        }
        if CommandLine.arguments.contains("--openview") {
            // Turn to the most open direction at this pitch (the cave light shot stood against a pillar: blind critic,
            // cave_torches showed a blurred wall and no torch).
            let eye = game.player.pos + V3(0, 1.62, 0)
            var best: Float = -1, bestYaw = game.player.yaw
            for k in 0..<24 {
                let yw: Float = Float(k) / 24 * 2 * Float.pi
                let dir = V3(-sinf(yw) * cosf(game.player.pitch), sinf(game.player.pitch), -cosf(yw) * cosf(game.player.pitch))
                var d: Float = 32
                if let h = world.raycast(eye, dir, maxDist: 32) {
                    d = simd_length(V3(Float(h.hit.x) + 0.5, Float(h.hit.y) + 0.5, Float(h.hit.z) + 0.5) - eye)
                }
                if d > best { best = d; bestYaw = yw }
            }
            game.player.yaw = bestYaw
            print(String(format: "openview: yaw %.0f, %.1f blocks clear", bestYaw * 180 / Float.pi, best))
        }
        if CommandLine.arguments.contains("--torches") {
            // Light test: a ring of torches plus a lamp around the camera, then remesh what changed.
            // Torches stand on the first floor below the camera (surface or cave), never in water.
            // Around the block the camera looks at (a ring round the camera stayed out of frame when it looked down at
            // a cave floor: blind critic, cave_torches showed no torch).
            var ringC = pos
            let eye = pos + V3(0, 1.62, 0)
            if let h = world.raycast(eye, game.player.look, maxDist: 32) {
                ringC = V3(Float(h.hit.x) + 0.5, Float(h.hit.y) + 1, Float(h.hit.z) + 0.5)
                // In a cave the ray ends on the far wall: centre the ring well short of it, in the open space being
                // looked at (round the wall cell, torches went behind it into another cave: cave_torches stayed dark).
                let d = simd_length(ringC - eye)
                if d > 8 { ringC = eye + game.player.look * (d * 0.6) }
            }
            // Only spots the eye can see (a torch behind a pillar lights nothing in frame).
            func seen(_ x: Int, _ y: Int, _ z: Int) -> Bool {
                let c = V3(Float(x) + 0.5, Float(y) + 0.4, Float(z) + 0.5)
                let to = c - eye
                let dist = simd_length(to)
                guard let h = world.raycast(eye, to / max(dist, 0.01), maxDist: dist) else { return true }
                return h.hit == IVec3(x, y, z) || h.hit == IVec3(x, y - 1, z)
            }
            func floorBelow(_ x: Int, _ z: Int) -> Int? {
                var y = min(Int(floor(ringC.y)) + 2, world.topY(x, z) + 1)
                let stop = y - 40
                while y > stop {
                    let here = world.block(x, y, z), below = world.block(x, y - 1, z)
                    if (here == AIR || Blocks.replaceable[Int(here)]) && !Blocks.isLiquid(here) && Blocks.opaque[Int(below)] { return y }
                    y -= 1
                }
                return nil
            }
            var placed = 0
            for k in 0..<10 {
                let a = Float(k) / 10 * 2 * Float.pi
                let x = Int(floor(ringC.x + cosf(a) * 5)), z = Int(floor(ringC.z + sinf(a) * 5))
                if let y = floorBelow(x, z), seen(x, y, z) { world.setBlock(x, y, z, TORCH); placed += 1 }
            }
            // Too few spots round the target (a cave pool: run 395 cave_torches showed no torch at all): a tighter ring
            // halfway between the camera and the target.
            if placed < 5 {
                let mid = (ringC + eye) * 0.5
                ringC = V3(mid.x, max(mid.y, ringC.y), mid.z)
                for k in 0..<8 {
                    let a = Float(k) / 8 * 2 * Float.pi + 0.2
                    let x = Int(floor(ringC.x + cosf(a) * 3)), z = Int(floor(ringC.z + sinf(a) * 3))
                    if let y = floorBelow(x, z), seen(x, y, z) { world.setBlock(x, y, z, TORCH); placed += 1 }
                }
            }
            let lx = Int(floor(ringC.x)) + 3, lz = Int(floor(ringC.z))
            if let y = floorBelow(lx, lz) { world.setBlock(lx, y, lz, LAMP) }
            print(String(format: "torches: %d placed round %.0f %.0f %.0f", placed, ringC.x, ringC.y - Float(YOFF), ringC.z))
            let t2 = world.loadSync(center: pos, radius: rd)
            t.mesh += t2.mesh
        }
        var quads = 0, water = 0
        for (_, c) in world.chunks { for sec in c.sections { quads += sec.opaqueQuads; water += sec.transQuads } }

        if CommandLine.arguments.contains("--pathtest") {
            // Navigation test: a stone arena with a 3-high wall between a zombie and the player, gap at one
            // end plus a one-block step; the zombie must walk around. Prints the path and the chase result.
            let bx = Int(floor(pos.x)), bz = Int(floor(pos.z)) - 8
            let gy = Int(floor(pos.y)) - 3
            for dx in -10...10 { for dz in -10...10 {
                world.setBlock(bx + dx, gy - 1, bz + dz, STONE)
                for k in 0..<6 { world.setBlock(bx + dx, gy + k, bz + dz, AIR) }
            } }
            for dx in -10...6 { for k in 0..<3 { world.setBlock(bx + dx, gy + k, bz, STONE_BRICKS) } }
            world.setBlock(bx + 8, gy, bz + 3, STONE)
            _ = world.loadSync(center: pos, radius: rd)
            let from = V3(Float(bx) + 0.5, Float(gy), Float(bz - 5) + 0.5), to = V3(Float(bx) + 0.5, Float(gy), Float(bz + 5) + 0.5)
            let route = PathFinder.find(world, from: from, to: to, tall: 2) ?? []
            print("path: \(route.count) nodes, ends \(route.last.map { "\($0.x - bx),\($0.y - gy),\($0.z - bz)" } ?? "-")")
            let z = Mob(.zombie, at: from)
            z.lockTime = 60                                   // already chasing (the wall hides the player)
            game.mobs.mobs.removeAll()
            game.mobs.mobs.append(z)
            game.paused = false
            game.survival = true
            game.player.flying = false
            game.player.pos = to
            let d0 = simd_length(z.pos - to)
            var reached: Float = -1
            for i in 0..<(20 * 20) {
                game.tick(0.05)
                game.player.pos = to; game.player.vel = .zero
                game.health = 20
                game.mobs.mobs.removeAll { $0 !== z }          // no night spawns in the way
                if reached < 0 && simd_length(z.pos - to) < 1.6 { reached = Float(i) * 0.05 }
            }
            print(String(format: "pathtest: zombie start %.1f from player, end %.1f, reached %@", d0, simd_length(z.pos - to), reached < 0 ? "never" : String(format: "after %.1f s", reached)))
            game.player.pos = pos
        }
        if CommandLine.arguments.contains("--mobtests") && !MobTests.run(game: game, world: world, pos: pos, rd: rd) { return 1 }
        if CommandLine.arguments.contains("--towntests") {
            var townFails = 0
            TownTests.run(game: game, makeWorld: { World(seed: world.seed, device: world.device, save: nil) }) { ok, what in
                print("towntest \(ok ? "ok  " : "FAIL") \(what)"); if !ok { townFails += 1 }
            }
            if townFails > 0 { return 1 }
        }
        if CommandLine.arguments.contains("--posecheck") && !PoseCheck.run(game: game) { return 1 }
        if let secs = Float(arg("--fortresstest") ?? ""), !MobTests.fortressFight(game: game, world: world, seconds: secs) { return 1 }
        if CommandLine.arguments.contains("--flighttest") {
            let ph = arg("--flighttest").flatMap { $0.hasPrefix("--") ? nil : $0 } ?? "all"
            if !FlightTests.run(game: game, phase: ph) && !ph.hasSuffix("shot") { return 1 }
            pos = game.player.pos                             // the world streamed along with the aircraft
        }
        if CommandLine.arguments.contains("--basetest") {
            let ph = arg("--basetest").flatMap { $0.hasPrefix("--") ? nil : $0 } ?? "all"
            if !BaseTests.run(game: game, world: world, phase: ph) && !ph.hasSuffix("shot") { return 1 }
        }
        if let secs = Double(arg("--fire") ?? "") {
            // Hold the trigger for a while (guns in flight, muzzle flash, soldiers answering), camera held still.
            let keep = (game.player.pos, game.player.yaw, game.player.pitch)
            game.paused = false
            game.player.flying = true
            for i in 0..<Int(secs * 20) {
                game.input.leftDown = true
                if i == 0 { game.input.leftClicked = true }
                game.tick(0.05)
                game.player.pos = keep.0; game.player.vel = .zero; game.player.yaw = keep.1; game.player.pitch = keep.2
                game.health = max(game.health, 20)
            }
            game.input.leftDown = false
            print("fired \(game.arms.shotsFired) shots, \(game.arms.hits) hits, \(game.arms.slugs.count) rounds in flight")
        }
        if let secs = Double(arg("--ticks") ?? "") {
            // Let the world run (mobs, sparkstone, villagers) with the camera held still.
            let keep = (game.player.pos, game.player.yaw, game.player.pitch)
            game.paused = false
            game.player.flying = true
            for _ in 0..<Int(secs * 20) {
                game.tick(0.05)
                game.player.pos = keep.0; game.player.vel = .zero; game.player.yaw = keep.1; game.player.pitch = keep.2
            }
            var jobs: [String: Int] = [:]
            for m in game.mobs.mobs where m.kind == .villager { jobs[m.villager?.profession ?? "?", default: 0] += 1 }
            print("after \(secs) s: \(game.mobs.mobs.count) mobs, villagers \(jobs.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
        }
        if CommandLine.arguments.contains("--padtest") { PadTest.run(game) }     // scripted controller menu tests
        if CommandLine.arguments.contains("--pad") { PadManager.shared.forcePad(true) }
        // --photo: photo mode at the harness camera (HUD hidden); --dof F: depth of field focused at F blocks.
        if CommandLine.arguments.contains("--photo") {
            game.togglePhotoMode()
            game.cine.followPlayer = true
            if let f = Float(arg("--dof") ?? "") { game.cine.dof = true; game.cine.autoFocus = false; game.cine.focus = f; game.cine.aperture = 0.7 }
        }
        if CommandLine.arguments.contains("--cinetest") && Cinematic.selfTest() > 0 { return 1 }   // draw prompts with pad glyphs
        if CommandLine.arguments.contains("--couch") || arg("--safe") != nil {
            // TV layout checks without touching the saved options (restored after the shot).
            PrefsSandbox.begin()
            if CommandLine.arguments.contains("--couch") { HudLayout.couch = true }
            if let sa = Int(arg("--safe") ?? "") { Settings.shared.safeArea = sa }
        }
        if let v = arg("--padview") { PadTest.view(game, v) }
        if CommandLine.arguments.contains("--hints") {
            // The minimap samples on a worker; fill its area now so the single frame shows it.
            MapCache.shared.prefill(world.gen, x: Int(game.player.pos.x), z: Int(game.player.pos.z), radius: 72, step: 4)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--structnear"), i + 3 < CommandLine.arguments.count {
            let a = CommandLine.arguments
            return Int32(StructScan.near(seed: UInt64(a[i + 1]) ?? 0, x: Int(a[i + 2]) ?? 0, z: Int(a[i + 3]) ?? 0))
        }
        if CommandLine.arguments.contains("--structscan") { return Int32(StructScan.run(seeds: Int(arg("--structscan") ?? "") ?? 24)) }
        if CommandLine.arguments.contains("--questbugs") { return QuestBugTests.run(game) > 0 ? 1 : 0 }   // task 20 checks
        if CommandLine.arguments.contains("--selftest") {
            // Crash smoke test: every mob kind, every block, the special crafting paths, bundles, and 3 s of ticks.
            game.paused = false
            game.survival = false          // stay alive next to deep stalkers and siegebeasts
            let f = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw))
            for (i, k) in MobKind.allCases.enumerated() where k != .enderDragon && k != .wither {
                let p = pos + f * 12 + V3(Float(i % 10) * 2 - 10, 0, Float(i / 10) * 2)
                let x = Int(floor(p.x)), z = Int(floor(p.z))
                game.mobs.mobs.append(Mob(k, at: V3(Float(x) + 0.5, Float(world.topY(x, z) + 1), Float(z) + 0.5)))
            }
            var placed = 0
            let by = Int(pos.y) + 40
            for b in 1..<Blocks.count where Int(Blocks.groupBase[b]) == b {
                let x = Int(pos.x) - 30 + (placed % 60), z = Int(pos.z) + 30 + (placed / 60) * 2
                world.setBlockAsync(x, by, z, BlockID(b))
                placed += 1
            }
            func st(_ n: String, _ c: Int = 1) -> ItemStack { Items.has(n) ? ItemStack(Items.id(n), c) : .empty }
            let grids: [[ItemStack]] = [
                [st("gunpowder"), st("red_dye"), st("fire_charge"), st("diamond"), .empty, .empty, .empty, .empty, .empty],
                [st("paper"), st("gunpowder"), st("gunpowder"), .empty, .empty, .empty, .empty, .empty, .empty],
                [st("leather_chestplate"), st("blue_dye"), st("yellow_dye"), .empty, .empty, .empty, .empty, .empty, .empty],
                [st("filled_map"), st("map"), .empty, .empty, .empty, .empty, .empty, .empty, .empty],
            ]
            var crafted = 0
            for g in grids where Fireworks.craft(g) != nil { crafted += 1 }
            var bundle = st("bundle")
            (bundle, _) = Bundles.insert(bundle, st("cobblestone", 32))
            (bundle, _) = Bundles.insert(bundle, st("iron_sword"))
            // Naming audit (the repo is public): no reference-game proper names in anything the player reads.
            let banned = ["Nether", "Ender", "End Stone", "End Rod", "End Crystal", "End Portal", "End Gateway", "Creeper", "Crimson", "Warped",
                          "Sculk", "Wither", "Piglin", "Blaze", "Ghast", "Shulker", "Elytra", "Redstone", "Glowstone", "Purpur",
                          "Prismarine", "Chorus", "Pillager", "Evoker", "Vindicator", "Ravager", "Warden", "Deepslate", "Blackstone",
                          "Hoglin", "Strider", "Zoglin", "Guardian", "Undying", "Mooshroom", "Allay", "Sniffer", "Bogged", "Endermite",
                          "Minecraft", "Mojang", "Overworld", "Nylium", "Shroomlight", "Pale Oak", "Creaking", "Eyeblossom", "Vex"]
            var shown: [String] = []
            for i in 0..<Blocks.count { shown.append(Blocks.name(BlockID(i))) }
            for i in 0..<Items.count { shown.append(Items.name(ItemID(i))) }
            for k in MobKind.allCases { shown.append(k.name) }
            for b in Biome.allCases { shown.append(b.displayName) }
            for a in Advancements.all { shown.append(a.title); shown.append(a.desc) }
            shown += Game.creditsLines
            let flagged = Set(shown.filter { n in banned.contains { n.contains($0) } }).sorted()
            print("naming audit: \(shown.count) names, \(flagged.count) flagged\(flagged.isEmpty ? "" : ": " + flagged.prefix(80).joined(separator: " | "))")
            print("selftest: \(placed) blocks, \(MobKind.allCases.count) mob kinds, \(crafted)/4 special recipes, bundle fill \(Bundles.fill(bundle))/64, \(Advancements.all.count) advancements")
            for _ in 0..<180 { game.tick(1.0 / 60) }
            print("selftest ok: \(game.mobs.mobs.count) mobs after 3 s")
            game.player.pos = pos
        }
        if let simSeconds = Double(arg("--sim") ?? "") {
            // Gameplay smoke test: scripted input through the real Game.tick (survival, walking, jumping,
            // breaking/placing, inventory, flowing water, mobs), timing the main-thread tick.
            game.player.flying = false
            game.paused = false
            game.survival = true
            let wx = Int(floor(pos.x)) + 3, wz = Int(floor(pos.z)) - 4
            world.setBlock(wx, world.gen.column(wx, wz).height + 1, wz, WATER)
            for k in 0..<5 {
                let kind = MobKind.allCases[k % 3]
                let x = Int(floor(pos.x)) + k * 2 - 4, z = Int(floor(pos.z)) - 6
                let y = game.mobs.grassSurface(world, x, z) ?? (world.gen.column(x, z).height + 1)
                game.mobs.mobs.append(Mob(kind, at: V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)))
            }
            let dt = 1.0 / 60
            var worst = 0.0, total = 0.0
            let frames = Int(simSeconds / dt)
            let inp = game.input
            for f in 0..<frames {
                inp.keys = [Key.w]
                if f % 100 == 0 { inp.keys.insert(Key.space); inp.pressed.insert(Key.space) }
                if f % 30 == 10 { inp.leftClicked = true }
                if f % 45 == 20 { inp.rightClicked = true }
                if f == 300 { inp.pressed.insert(Key.e) }
                if f > 300 && f < 360 && f % 10 == 0 { inp.pressed.insert(Key.arrowRight); inp.pressed.insert(Key.arrowDown) }
                if f == 380 { inp.pressed.insert(Key.e) }
                game.player.yaw += 0.003
                let t0 = CFAbsoluteTimeGetCurrent()
                game.tick(dt)
                let el = CFAbsoluteTimeGetCurrent() - t0
                total += el
                worst = max(worst, el)
            }
            _ = world.loadSync(center: game.player.pos, radius: rd)
            let p = game.player.pos
            print(String(format: "sim %.1f s: tick avg %.2f ms, worst %.2f ms | pos %.1f %.1f %.1f | health %ld hunger %ld | mobs %ld | fluid pending %ld | items held %ld, dropped %ld",
                         simSeconds, total / Double(max(1, frames)) * 1000, worst * 1000, p.x, p.y, p.z, game.health, game.hunger,
                         game.mobs.mobs.count, world.fluidPending.count,
                         game.inventory.main.slots.reduce(0) { $0 + $1.count }, game.drops.items.count))
        }

        // Ships (ShipTest.swift): a demo vessel under way, or the scripted physics checks.
        if let kind = arg("--ship") { pos = ShipTest.scene(kind, game: game, at: pos, rd: rd) }
        var shipFails = 0
        if let out = arg("--inputmatrix") { return InputMatrix.run(game: game, at: pos, out: out) > 0 ? 1 : 0 }   // STORE_QUALITY objective 3
        if let out = arg("--audioaudit") { return AudioAudit.run(game: game, out: out) > 0 ? 1 : 0 }   // STORE_QUALITY objective 5
        if CommandLine.arguments.contains("--audiotest") {
            if AudioTests.run(game: game, at: pos, rd: rd) > 0 { return 1 }
            pos = game.player.pos
        }
        if CommandLine.arguments.contains("--physicstest") { shipFails = ShipTest.physicsTest(game: game, rd: rd); pos = game.player.pos }
        if CommandLine.arguments.contains("--capitaltest") { shipFails += ShipTest.capitalTest(game: game, rd: rd); pos = game.player.pos }

        // Mesh benchmark: re-mesh the section at the camera a few times on one thread.
        let key = ChunkKey(x: floorDiv(Int(pos.x), CS), z: floorDiv(Int(pos.z), CS))
        var n9: [BlockStore] = [], h9: [[Int16]] = []
        for dz in -1...1 { for dx in -1...1 {
            let c = world.chunks[ChunkKey(x: key.x + dx, z: key.z + dz)]!
            n9.append(c.blocks); h9.append(c.height)
        } }
        let sy = max(0, min(NSEC - 1, (world.topY(Int(pos.x), Int(pos.z))) >> 4))
        let m0 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<5 { _ = Mesher.buildSection(n9, h9, sy: sy) }
        let meshMs = (CFAbsoluteTimeGetCurrent() - m0) / 5 * 1000

        let renderer: Renderer
        do { renderer = try Renderer(device: device, game: game, colorFormat: .bgra8Unorm) }
        catch { print("renderer init failed: \(error)"); return 1 }
        if CommandLine.arguments.contains("--nocull") { renderer.caveCulling = false }   // draw every section in the frustum
        if CommandLine.arguments.contains("--verifyworld") {
            // World data check: every loaded chunk against a fresh main-thread generation (race / nondeterminism),
            // and its stored heightmap against one recomputed from its blocks (skylight comes from the heightmap).
            var badGen = 0, badH = 0, total = 0, samples: [String] = []
            for (k, c) in world.chunks {
                total += 1
                var regen = world.gen.generate(cx: k.x, cz: k.z)
                if let st = world.gen.structures { _ = st.place(into: &regen, cx: k.x, cz: k.z) }
                let have = c.blocks.full()
                var diff = 0, lo = CH, hi = -1
                for i in 0..<min(have.count, regen.count) where have[i] != regen[i] {
                    diff += 1; let y = i / CSQ; lo = min(lo, y); hi = max(hi, y)
                }
                if diff > 0 {
                    badGen += 1
                    if samples.count < 8 { samples.append("chunk \(k.x),\(k.z): \(diff) blocks differ (y \(lo - YOFF)...\(hi - YOFF))") }
                }
                let h = Chunk.computeHeights(have)
                var hd = 0
                for i in 0..<CSQ where h[i] != c.height[i] { hd += 1 }
                if hd > 0 {
                    badH += 1
                    if samples.count < 12 { samples.append("chunk \(k.x),\(k.z): \(hd) heightmap columns differ") }
                }
            }
            print("verifyworld: \(total) chunks, \(badGen) differ from a fresh generation, \(badH) with a stale heightmap")
            for l in samples { print("verifyworld:   \(l)") }
        }
        game.target = world.raycast(game.player.eye, game.player.look, maxDist: 5)
        do {
            // Light probe: the eye cell and the first floor below it (debugging dark views).
            let e = game.player.eye
            let ex = Int(floor(e.x)), ey = Int(floor(e.y)), ez = Int(floor(e.z))
            var fy = ey
            while fy > ey - 40 && !Blocks.collide[Int(world.block(ex, fy - 1, ez))] { fy -= 1 }
            let le = world.lightAt(ex, ey, ez), lf = world.lightAt(ex, fy, ez)
            print("light probe: eye sky \(le.sky) block \(le.block) in \(Blocks.key(world.block(ex, ey, ez))); floor+1 (y \(fy - YOFF)) sky \(lf.sky) block \(lf.block) in \(Blocks.key(world.block(ex, fy, ez))), daylight \(game.daylight)")
        }
        if CommandLine.arguments.contains("--lodcheck") {
            // Cacti seen far away vanished and popped in close (Remington, playtest 2): the cactus sections' quads at
            // full and far detail, plus the live section's state.
            var n = 0
            for (k, c) in world.chunks where n < 6 {
                var found: Int?
                for i in 0..<(CS * CS * CH) where c.blocks[i] == CACTUS { found = i >> 8; break }
                guard let y = found else { continue }
                n += 1
                let sy = y >> 4
                let q = world.lodQuads(c, sy)
                let sec = c.sections[sy]
                let s0 = q.first.map { "\($0.0)+\($0.1)" } ?? "-", s1 = q.last.map { "\($0.0)+\($0.1)" } ?? "-"
                print("lodcheck: chunk \(k.x) \(k.z) cactus at y \(y - YOFF) (section \(sy)): quads near \(s0), far \(s1); live lod \(c.lod) quads \(sec.opaqueQuads) empty \(sec.empty) top \(c.topSec)")
            }
            if n == 0 { print("lodcheck: no cactus loaded") }
        }
        func sliceChar(_ b: BlockID) -> String {
            if b == AIR { return "." }
            if Blocks.isLiquid(b) { return "~" }
            let k = Blocks.key(b)
            if k.contains("fence") { return "f" }
            if k.contains("log") { return "|" }
            return Blocks.opaque[Int(b)] ? "#" : "+"
        }
        if CommandLine.arguments.contains("--slice"), let (mn, mx) = structBox {
            // Block maps of the structure at the sea surface and one above (what a flat tile in a shot really is):
            // ~ water, # planks/stone, f fence, | log, . air, + other.
            for y in [SEA - 1, SEA, SEA + 1] {
                print("slice y \(y - YOFF) x \(mn.x)...\(mx.x) z \(mn.z)...\(mx.z):")
                for z in mn.z...mx.z {
                    var row = ""
                    for x in mn.x...mx.x {
                        row += sliceChar(world.block(x, y, z))
                    }
                    print("  " + row)
                }
            }
        }
        if CommandLine.arguments.contains("--cactusprobe") {
            // Cacti at mid range vanish in play (Remington: seen near and far, not between): a pixel probe on the middle
            // of every cactus column 8-120 blocks off in front of the camera, nearest first, with its distance.
            let e = game.player.eye
            var found: [(Float, V3)] = []
            let r = 120
            let ex = Int(floor(e.x)), ez = Int(floor(e.z))
            for z in stride(from: ez - r, through: ez + r, by: 1) { for x in stride(from: ex - r, through: ex + r, by: 1) {
                guard world.isLoaded(x, z) else { continue }
                let top = world.topY(x, z)
                guard top > 0, world.block(x, top, z) == CACTUS else { continue }
                let c = V3(Float(x) + 0.5, Float(top) - 0.5, Float(z) + 0.5)          // middle of a 2-3 high column
                let d = simd_length(c - e)
                guard d > 8, d < Float(r), simd_dot(simd_normalize(c - e), game.player.look) > 0.8 else { continue }
                found.append((d, c))
            } }
            found.sort { $0.0 < $1.0 }
            // Spread over the distance range: every k-th one, at most 24.
            let step = max(1, found.count / 24)
            for (i, f) in found.enumerated() where i % step == 0 { renderer.probes.append((String(format: "cactus %.0f", f.0), f.1)) }
            print("cactusprobe: \(found.count) cacti in view 8-\(r) blocks off")
        }
        if CommandLine.arguments.contains("--listframes") {
            // Item frames within 16 blocks: block state and what they hold (the armory's gun racks drew empty: critic run 385).
            let e = game.player.eye
            var n = 0
            for (p, be) in world.blockEntities where be.kind == .frame {
                let d = simd_length(V3(Float(p.x), Float(p.y), Float(p.z)) - e)
                guard d < 16, n < 12 else { continue }
                n += 1
                let b = world.block(p.x, p.y, p.z)
                let it = be.container[0]
                let layer = it.isEmpty ? -1 : (Items.texLayer(it.item) ?? -2)
                print("frame at \(p.x) \(p.y - YOFF) \(p.z): \(Blocks.key(b)), item \(it.isEmpty ? "none" : Items.key(it.item)) layer \(layer)")
                // --framesword: swap the held item for a sword (is it the gun items, or these frames?).
                if CommandLine.arguments.contains("--framesword") { be.container[0] = ItemStack(Items.id("diamond_sword"), 1) }
                let st = Int(b - Blocks.groupBase[Int(b)])
                let fn = [IVec3(0, 0, -1), IVec3(0, 0, 1), IVec3(-1, 0, 0), IVec3(1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0)][min(st, 5)]
                print("  frame delay \(be.delay), light \(world.lightAt(p.x, p.y, p.z)); in front: \(Blocks.key(world.block(p.x + fn.x, p.y + fn.y, p.z + fn.z))), behind: \(Blocks.key(world.block(p.x - fn.x, p.y - fn.y, p.z - fn.z)))")
                // Pixel probes: the item's centre and the frame board's rim beside it (does the item reach the image?).
                let c = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5), nv = V3(Float(fn.x), Float(fn.y), Float(fn.z))
                let side = st < 4 ? V3(-nv.z, 0, nv.x) : V3(1, 0, 0)
                renderer.probes.append(("item \(p.x),\(p.z)", c - nv * 0.42))
                renderer.probes.append(("rim \(p.x),\(p.z)", c - nv * 0.44 + side * 0.33))
            }
            // A control frame placed like the decor scene's, beside the first listed one (do frames here draw at all?).
            if let first = world.blockEntities.first(where: { $0.value.kind == .frame && simd_length(V3(Float($0.key.x), Float($0.key.y), Float($0.key.z)) - e) < 16 }) {
                let q = IVec3(first.key.x + 1, first.key.y + 1, first.key.z)
                world.setBlock(q.x, q.y, q.z, world.block(first.key.x, first.key.y, first.key.z))
                let fb = BlockEntity(.frame); fb.container[0] = ItemStack(Items.id("apple"), 1); world.blockEntities[q] = fb
                print("control frame at \(q.x) \(q.y - YOFF) \(q.z) holding an apple")
                renderer.probes.append(("control apple", V3(Float(q.x) + 0.5, Float(q.y) + 0.5, Float(q.z) + 0.5) - V3(0, 0, 0.42)))
            }
            // Mip alpha of the sprites involved (frames empty past ~6 blocks): centre alpha and coverage per level.
            for it in ["apple", "gun_rifle", "#cactus_side", "#oak_leaves"] {
                let l: Int
                if it.hasPrefix("#") { l = Int(Tex.id(String(it.dropFirst()))) }
                else { guard Items.has(it), let k = Items.texLayer(Items.id(it)) else { continue }; l = k }
                let lv = TextureGen.mipChain(layers: l..<(l + 1))
                var line = "mips \(it) (layer \(l), \(Tex.names[l])):"
                var sz = TextureGen.size
                for (k, d) in lv.enumerated() where k < 6 {
                    let cA = d[((sz / 2) * sz + sz / 2) * 4 + 3]
                    var pass = 0
                    for i in 0..<(sz * sz) where d[i * 4 + 3] >= 128 { pass += 1 }
                    line += " L\(k) \(sz)px centre \(cA) pass \(pass * 100 / max(1, sz * sz))%"
                    sz = max(1, sz / 2)
                }
                print(line)
            }
            // A dropped apple two blocks ahead: does anything in the entity pass reach the image here?
            let side = V3(cosf(game.player.yaw), 0, -sinf(game.player.yaw))          // beside the crosshair, not under it
            let dropAt = e + game.player.look * 3 + side * 0.8 - V3(0, 0.25, 0)
            game.drops.spawn(ItemStack(Items.id("apple"), 1), at: dropAt, vel: .zero, delay: 100)
            renderer.probes.append(("dropped apple", dropAt + V3(0, 0.25, 0)))
            print("frames listed: \(n) (block entities \(world.blockEntities.count))")
        }
        if CommandLine.arguments.contains("--inlava") {
            // Lava view check: the camera inside a 5x4x5 lava pool (orange fog + overlay, not the underwater view).
            let e = game.player.eye
            let lava = Blocks.id("lava")
            for dy in -2...1 { for dz in -2...2 { for dx in -2...2 {
                world.setBlock(Int(floor(e.x)) + dx, Int(floor(e.y)) + dy, Int(floor(e.z)) + dz, lava)
            } } }
        }
        do {
            // The harness doesn't step the player: derive the in-water flags the renderer uses.
            let e = game.player.eye, f = game.player.pos
            let headKind = Blocks.fluidKind[Int(world.block(Int(floor(e.x)), Int(floor(e.y)), Int(floor(e.z))))]
            let feetKind = Blocks.fluidKind[Int(world.block(Int(floor(f.x)), Int(floor(f.y + 0.1)), Int(floor(f.z))))]
            game.player.headInWater = headKind == 1          // 1 water, 2 lava (lava gets its own view)
            game.player.headInLava = headKind == 2
            game.player.inWater = feetKind == 1
            game.player.inLava = feetKind == 2
        }
        if arg("--menu") == nil { game.advToasts.removeAll() }      // no "Advancement Made" toasts over test views
        if CommandLine.arguments.contains("--nightvision") { game.applyEffect(.nightVision, amp: 0, seconds: 300) }
        if CommandLine.arguments.contains("--treecheck") {
            // Tree species vs column biome: sample columns that have a log under the canopy.
            var checked = 0, bad: [String] = []
            let px = Int(floor(pos.x)), pz = Int(floor(pos.z))
            var rng = SRng(99)
            var tries = 0
            while checked < 200 && tries < 20000 {
                tries += 1
                let x = px + rng.range(-96, 96), z = pz + rng.range(-96, 96)
                let top = world.topY(x, z)
                guard top > 0 else { continue }
                var y = top, log = ""
                while y > top - 20 {
                    let k = Blocks.key(Blocks.groupBase[Int(world.block(x, y, z))])
                    if k.hasSuffix("_log") { log = k; break }
                    y -= 1
                }
                guard log == "pale_oak_log" || log == "dark_oak_log" else { continue }
                checked += 1
                let biome = world.gen.column(x, z).biome
                let ok = log == "pale_oak_log" ? biome == .paleGarden : (biome == .darkForest || biome == .paleGarden)
                if !ok { bad.append("\(log)@\(x),\(z)=\(biome)") }
            }
            print("treecheck: \(checked) trunks, \(bad.count) in the wrong biome\(bad.isEmpty ? "" : ": " + bad.prefix(12).joined(separator: " "))")
        }
        if let s = arg("--crack"), let t = game.target {
            game.mining = t.hit
            game.mineProgress = min(0.99, max(0.01, Float(s) ?? 0.6))
        }
        if CommandLine.arguments.contains("--swim") {
            game.player.flying = false
            game.player.swimming = true
            game.player.pos.y = Float(SEA) - 0.35
            print("swim pose: prone \(game.player.prone) eye \(game.player.eye.y - game.player.pos.y)")
        }
        if CommandLine.arguments.contains("--bugnotetest") {
            // Voice bug notes pipeline with a synthesized voice (BugNotes.selfTest).
            BugNotes.selfTest(game) { url in _ = renderer.renderToPNG(path: url.path, width: 640, height: 400) }
        }
        if CommandLine.arguments.contains("--boom") {
            // An explosion 9 blocks ahead (no block damage): flash light, smoke and debris mid-burst.
            let f = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw))
            var c = game.player.pos + f * 9
            c.y = Float(world.topY(Int(floor(c.x)), Int(floor(c.z))) + 1)
            Explosion.explode(at: c, power: 4, game: game, breakBlocks: false)
            game.particles.update(0.12, world)
        }
        if CommandLine.arguments.contains("--ambient") {
            // Two seconds of ambient block particles (torch smoke, campfire columns, lava sparks).
            for _ in 0..<40 { game.ambientParticles(0.05); game.emberMotes(0.05); game.particles.update(0.05, world) }
        }
        if CommandLine.arguments.contains("--underwater") {
            // Head under the sea surface (fog, overlay, water seen from below).
            game.player.pos.y = Float(SEA) - 4
            game.player.headInWater = true
        }
        if CommandLine.arguments.contains("--mobcheck") { shipFails += MobRenderCheck.run(game, renderer) }   // every mob kind draws
        if CommandLine.arguments.contains("--plantcheck") { shipFails += PlantCheck.run(game) }                 // stacked plants pop
        if CommandLine.arguments.contains("--rulescheck") { shipFails += RulesCheck.run(game) }                 // world rules (RulesCheck.swift)
        if CommandLine.arguments.contains("--coppertest") { shipFails += CopperTests.run(game) }               // copper circuit parity (docs/status/copper-parity.md)
        if CommandLine.arguments.contains("--musiccheck") { shipFails += MusicCheck.run(game) }                 // your own music folder
        if CommandLine.arguments.contains("--coop") {
            // Split screen: player 2 joins (a neutral simulated pad) a few blocks ahead, turned back to face player 1.
            game.coop.simulated[1] = PadSnapshot()
            game.coop.join(game, controller: nil)
            if CommandLine.arguments.contains("--splitside") { Settings.shared.splitSideBySide = true }   // with --couch (prefs sandboxed)
            if CommandLine.arguments.contains("--cooptest") { shipFails += CoopTest.run(game) }
            let p1 = game.player
            let fwd = V3(-sinf(p1.yaw), 0, -cosf(p1.yaw)), right = V3(cosf(p1.yaw), 0, -sinf(p1.yaw))
            game.coop.withSeat(1, game) {
                game.player.pos = game.settleSpawn(p1.pos + fwd * 4 + right * 1.2)
                game.player.yaw = p1.yaw + .pi
                game.player.pitch = -0.05
                game.player.flying = false
                game.selected = 3
            }
        }
        _ = renderer.renderToPNG(path: out, width: w, height: h) // warm-up (pipeline + residency)
        _ = renderer.renderToPNG(path: out, width: w, height: h)
        let gpu = renderer.medianFrame(30, width: w, height: h)
        // --pick x,y[;x,y...]: what a screen pixel shows - the first non-air block along its ray (water and lava count),
        // for questions like "what is that streak?" (volcano_far, run 470).
        if let picks = arg("--pick") {
            let (eye, yaw, pitch) = renderer.cameraEye()
            let fovY: Float = game.fovSetting * game.fovScale * .pi / 180
            let t: Float = tanf(fovY * 0.5), aspect: Float = Float(w) / Float(h)
            let f = V3(-sinf(yaw) * cosf(pitch), sinf(pitch), -cosf(yaw) * cosf(pitch))
            let r = V3(cosf(yaw), 0, -sinf(yaw))
            let u = simd_cross(r, f)
            for pair in picks.split(separator: ";") {
                let xy = pair.split(separator: ",").compactMap { Float($0) }
                guard xy.count == 2 else { continue }
                let nx: Float = xy[0] / Float(w) * 2 - 1, ny: Float = 1 - xy[1] / Float(h) * 2
                let side: V3 = r * (nx * t * aspect)
                let lift: V3 = u * (ny * t)
                let d = simd_normalize(f + side + lift)
                var hit = "nothing within 800"
                var s: Float = 0
                while s < 800 {
                    let q = eye + d * s
                    let b = world.block(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z)))
                    if b != AIR {
                        hit = String(format: "%@ at %d %d %d (%.0f blocks)", Blocks.key(b), Int(floor(q.x)), Int(floor(q.y)) - YOFF, Int(floor(q.z)), s)
                        break
                    }
                    s += 0.05
                }
                print("pick \(Int(xy[0])),\(Int(xy[1])): \(hit)")
            }
        }

        print(String(format: "seed %llu  pos %.1f %.1f %.1f  rd %ld  chunks %ld  (drawn %ld)", seed, pos.x, pos.y, pos.z, rd, world.chunks.count, renderer.drawnChunks))
        print(String(format: "gen %.0f ms  mesh(all, parallel) %.0f ms  mesh(1 section) %.2f ms  quads %ld opaque / %ld water", t.gen * 1000, t.mesh * 1000, meshMs, quads, water))
        print(String(format: "frame (encode+GPU, offscreen, median of 30) %.2f ms  biome %@", gpu * 1000, "\(world.gen.column(Int(pos.x), Int(pos.z)).biome)"))
        if caveFind {
            // Cave biomes aren't column biomes: report what is actually around the eye.
            let e = game.player.eye
            var moss = 0, drip = 0, sculk = 0
            for dy in -4...4 { for dz in -6...6 { for dx in -6...6 {
                let k = Blocks.key(Blocks.groupBase[Int(world.block(Int(floor(e.x)) + dx, Int(floor(e.y)) + dy, Int(floor(e.z)) + dz))])
                if k.hasPrefix("moss") || k.contains("azalea") || k.contains("cave_vines") || k == "clay" { moss += 1 }
                else if k.contains("dripstone") { drip += 1 }
                else if k.hasPrefix("sculk") { sculk += 1 }
            } } }
            let found = sculk >= 4 ? "deep_dark" : (moss >= 4 ? "lush_caves" : (drip >= 4 ? "dripstone_caves" : "none"))
            print("cave biome around the eye: \(found) (moss \(moss), dripstone \(drip), sculk \(sculk))\(found == arg("--find") ? "" : " - NOT the requested \(arg("--find") ?? "")")")
        }
        var meshBytes = 0
        for c in world.chunks.values { for sec in c.sections { meshBytes += (sec.opaqueBuf?.length ?? 0) + (sec.transBuf?.length ?? 0) } }
        let chunkBytes = Int(Bench.chunkMB(world) * 1_048_576)     // stored block sections + per-section light + heights + tints
        print(String(format: "mesh slabs %.0f MB, chunks %ld (block+light arrays %.0f MB), Metal allocated %.0f MB", Double(MeshArena.shared.slabBytes) / 1_048_576,
                     world.chunks.count, Double(chunkBytes) / 1_048_576, Double(device.currentAllocatedSize) / 1_048_576))
        print(String(format: "memory: resident %.0f MB  (section meshes %.0f MB)", residentMB(), Double(meshBytes) / 1_048_576))
        if CommandLine.arguments.contains("--listframes") {
            let st = renderer.entityStats
            print("entity pass: room \(st.cap) vertices, \(st.beforeDecor) before the decor, \(st.afterDecor) after")
        }
        print("wrote \(out)")
        return shipFails > 0 ? 1 : 0
    }
}

if CommandLine.arguments.contains("--smoke") {
    // Launch-and-play smoke test at one render distance (Smoke.swift, smoke.sh); exits non-zero on a failure.
    exit(Smoke.run())
}

if CommandLine.arguments.contains("--playthrough") {
    // Scripted start-to-credits playthrough + the Blight (Playthrough.swift); exits non-zero on a failed check.
    exit(Playthrough.run())
}

if let dir = arg("--sounds") {
    // Synth check: render every sound effect (take 0) to a WAV and verify it is non-silent, unclipped,
    // finite, the expected length, click-free and (for loops) seamless. Exit 1 on any failure.
    let t0 = CFAbsoluteTimeGetCurrent()
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var total = 0, failures = 0
    var list = SoundBank.allSounds
    for inst in 0..<16 { list.append(.note(inst, 12)) }
    if let only = ProcessInfo.processInfo.environment["SOUNDS_ONLY"] {   // e.g. SOUNDS_ONLY=step_,gun_ (prefixes)
        let pre = only.split(separator: ",").map(String.init)
        list = list.filter { s in pre.contains { s.name.hasPrefix($0) } }
    }
    var byCategory: [SoundCategory: Int] = [:]
    var slow: [(String, Double)] = []
    for s in list {
        let r0 = CFAbsoluteTimeGetCurrent()
        let c = SoundBank.render(s, variant: 0)
        slow.append((s.name, (CFAbsoluteTimeGetCurrent() - r0) * 1000))
        // Takes must differ (variation) and be deterministic (same seed, same samples).
        if SoundBank.variants(for: s) > 1 && SoundBank.render(s, variant: 1) == c { failures += 1; print("FAIL \(s.name): variants identical") }
        if s.name.hasPrefix("step_stone") && SoundBank.render(s, variant: 0) != c { failures += 1; print("FAIL \(s.name): not deterministic") }
        let chk = SoundBank.check(s, c)
        total += c.count
        byCategory[s.category, default: 0] += 1
        SoundBank.writeWAV(c, to: "\(dir)/\(s.name).wav")
        if !chk.ok { failures += 1; print("FAIL \(s.name): \(chk.problems.joined(separator: ", "))") }
    }
    for c in SoundCategory.allCases where byCategory[c] != nil { print("  \(c.label): \(byCategory[c]!) sounds") }
    // Soundscapes: 8 s mixes of the beds and stings the game layers in each place (for listening, not checked).
    let scapes: [(String, [(Snd, Float)], [(Snd, Float, Float)])] = [
        ("forest_day", [(.windLoop, 0.2)], [(.birdCall, 0.6, 0.35)]),
        ("forest_night", [(.cricketsLoop, 0.5)], [(.owlHoot, 0.7, 0.08)]),
        ("jungle", [(.jungleLoop, 0.7)], [(.birdCall, 0.5, 0.5)]),
        ("swamp_night", [(.swampLoop, 0.7), (.cricketsLoop, 0.3)], []),
        ("beach", [(.oceanLoop, 0.8), (.windLoop, 0.2)], []),
        ("rain", [(.rain, 0.8), (.rainRoof, 0.2)], [(.thunder, 0.7, 0.05)]),
        ("cave", [(.dripstoneLoop, 0.5), (.waterLoop, 0.2)], [(.caveAmbience, 0.6, 0.06), (.caveDrip, 0.4, 0.3)]),
        ("deep_dark", [(.deepDarkLoop, 0.7)], [(.wardenHeartbeat, 0.4, 0.3)]),
        ("lava_lake", [(.lavaLoop, 0.8), (.fireLoop, 0.3)], [(.lavaPop, 0.6, 0.8)]),
        ("emberdeep_wastes", [(.netherWastesLoop, 0.7), (.lavaLoop, 0.3)], [(.netherMood, 0.5, 0.08)]),
        ("ghost_valley", [(.soulValleyLoop, 0.8)], [(.netherMood, 0.4, 0.06)]),
        ("rustcap_forest", [(.crimsonLoop, 0.8)], []),
        ("tealcap_forest", [(.warpedLoop, 0.8)], []),
        ("basalt_deltas", [(.basaltLoop, 0.8)], []),
        ("hollow", [(.endLoop, 0.8)], [(.teleport, 0.3, 0.1)]),
        ("underwater", [(.underwaterLoop, 0.8)], [(.underwaterMood, 0.5, 0.08)]),
        ("portal", [(.portalLoop, 0.8)], []),
        ("meadow_night", [(.cricketsLoop, 0.4), (.fireflyLoop, 0.5)], [(.owlHoot, 0.5, 0.06)]),
        ("apiary", [(.hiveLoop, 0.7), (.windLoop, 0.15)], [(.birdCall, 0.4, 0.25), (.beePollinate, 0.5, 0.3)]),
        ("ashen_grove", [(.windLoop, 0.3)], [(.heartCreak, 0.7, 0.2), (.owlHoot, 0.4, 0.05)]),
        ("badlands", [(.windLoop, 0.6)], [(.dryGrassRustle, 0.5, 0.3)]),
        ("firefight", [(.windLoop, 0.2)], [(.gun(0), 0.7, 1.2), (.gun(1), 0.5, 1.0), (.gunDistant(2), 0.6, 0.3), (.bulletWhizz, 0.6, 0.8),
                                           (.bulletImpact(.stone), 0.5, 1.5), (.soldier(1, .alert), 0.7, 0.2), (.soldier(2, .attack), 0.6, 0.15), (.gun(9), 0.6, 0.12)]),
        ("steelhold_patrol", [(.windLoop, 0.3)], [(.soldierStep(1), 0.5, 1.6), (.soldierStep(3), 0.5, 0.8), (.soldier(0, .idle), 0.5, 0.2), (.gun(11), 0.4, 0.1)]),
        ("waterfall", [(.waterfallLoop, 0.9), (.riverLoop, 0.4)], [(.birdCall, 0.3, 0.2)]),
        ("mountain_pass", [(.mountainWindLoop, 0.8)], [(.rockfall, 0.5, 0.08), (.windGust, 0.4, 0.15)]),
        ("tundra", [(.tundraWindLoop, 0.8)], [(.iceCreak, 0.5, 0.15)]),
        ("snowstorm", [(.snowWindLoop, 0.8), (.tundraWindLoop, 0.4)], []),
        ("rain_forest", [(.rain, 0.5), (.rainLeavesLoop, 0.7)], [(.thunderFar, 0.6, 0.08)]),
        ("swamp_day", [(.swampInsectsLoop, 0.6), (.swampLoop, 0.4)], []),
        ("ship_at_sea", [(.oceanLoop, 0.6), (.hullWaterLoop, 0.6), (.engineFullLoop, 0.4)], [(.hullCreak, 0.5, 0.2)]),
        ("airship", [(.airshipWindLoop, 0.7), (.propFastLoop, 0.5)], [(.hullCreak, 0.4, 0.15)]),
        ("land_vehicle", [(.wheelRollLoop, 0.7), (.engineIdleLoop, 0.5)], [(.shipCollide, 0.5, 0.1)]),
        ("naval_battle", [(.oceanLoop, 0.5), (.engineFullLoop, 0.3), (.turretTraverseLoop, 0.3)],
         [(.shipCannon, 0.8, 0.4), (.explodeLarge, 0.5, 0.12), (.hullCreak, 0.4, 0.2)]),
        ("aircraft", [(.wingRushLoop, 0.8), (.propFastLoop, 0.5), (.engineFullLoop, 0.4)], []),
        ("frigate_overhead", [(.frigateDroneLoop, 0.9), (.windLoop, 0.3)], [(.shipCannon, 0.6, 0.15), (.hullCreak, 0.3, 0.1)]),
        ("siege_carriage", [(.carriageTreadLoop, 0.9), (.turretTraverseLoop, 0.3)], [(.gun(9), 0.6, 0.15)]),
        ("fortress_siege", [(.windLoop, 0.3)], [(.gun(9), 0.7, 0.2), (.gun(10), 0.4, 0.05), (.explodeSmall, 0.5, 0.3), (.gunDistant(0), 0.5, 0.8),
                                                (.debrisRain, 0.4, 0.15)]),
    ]
    let scapeLen = Int(8 * SoundBank.rate)
    var rng = SRng(2024)
    for (name, beds, stings) in scapes {
        var mix = [Float](repeating: 0, count: scapeLen)
        for (snd, v) in beds {
            let loop = SoundBank.render(snd, variant: 0)
            guard !loop.isEmpty else { continue }
            for i in 0..<scapeLen { mix[i] += loop[i % loop.count] * v }
        }
        for (snd, v, perSecond) in stings {
            var t: Float = 0.5
            while t < 7 {
                t += -logf(max(0.001, rng.float())) / perSecond
                if t >= 7 { break }
                let clip = SoundBank.render(snd, variant: rng.int(max(1, SoundBank.variants(for: snd))))
                let at = Int(t * Float(SoundBank.rate))
                for i in 0..<clip.count where at + i < scapeLen { mix[at + i] += clip[i] * v }
            }
        }
        var peak: Float = 0
        for x in mix { peak = max(peak, abs(x)) }
        if peak > 0.95 { let k = 0.95 / peak; for i in 0..<scapeLen { mix[i] *= k } }
        try? FileManager.default.createDirectory(atPath: "\(dir)/scapes", withIntermediateDirectories: true)
        SoundBank.writeWAV(mix, to: "\(dir)/scapes/scape_\(name).wav")
    }
    print("  wrote \(scapes.count) soundscapes to \(dir)/scapes")
    slow.sort { $0.1 > $1.1 }
    print("  slowest renders: " + slow.prefix(6).map { String(format: "%@ %.0f ms", $0.0 as NSString, $0.1) }.joined(separator: ", "))
    print(String(format: "synthesized %ld sounds (%.1f s of audio) in %.0f ms, %ld failed", list.count, Double(total) / SoundBank.rate, (CFAbsoluteTimeGetCurrent() - t0) * 1000, failures))
    exit(failures == 0 ? 0 : 1)
}

if let dir = arg("--music") {
    // Music check: compose a piece per mood (fixed seed), render the first 20 s and check it.
    let t0 = CFAbsoluteTimeGetCurrent()
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var failures = 0
    let seconds: Float = Float(arg("--seconds") ?? "") ?? 20
    for mood in MusicMood.allCases {
        let score = Composer.compose(mood, seed: 12345)
        let again = Composer.compose(mood, seed: 12345), other = Composer.compose(mood, seed: 999)
        if again.notes.count != score.notes.count || again.length != score.length { failures += 1; print("FAIL \(mood.rawValue): composer not deterministic") }
        if other.notes.count == score.notes.count && other.length == score.length && other.title == score.title { print("note \(mood.rawValue): seeds 12345 and 999 gave the same shape") }
        let want = min(score.length, seconds)
        let x = MusicRenderer.renderMono(score, seconds: want)
        var peak: Float = 0, sq: Float = 0, sum: Float = 0, nan = 0
        for v in x { if !v.isFinite { nan += 1; continue }; peak = max(peak, abs(v)); sq += v * v; sum += v }
        let rms = x.isEmpty ? 0 : sqrtf(sq / Float(x.count)), dc = x.isEmpty ? 0 : sum / Float(x.count)
        let secs = Float(x.count) / Float(SoundBank.rate)
        var problems: [String] = []
        if nan > 0 { problems.append("\(nan) non-finite samples") }
        if peak < 0.05 { problems.append(String(format: "silent (peak %.3f)", peak)) }
        if peak >= 0.999 { problems.append("clipped") }
        if rms < 0.005 { problems.append(String(format: "too quiet (rms %.4f)", rms)) }
        if abs(dc) > 0.03 { problems.append(String(format: "dc offset %.3f", dc)) }
        if abs(secs - want) > 0.5 { problems.append(String(format: "length %.1fs, wanted %.1fs", secs, want)) }
        if score.notes.count < 40 { problems.append("only \(score.notes.count) notes") }
        if score.length < 60 || score.length > 400 { problems.append(String(format: "piece length %.0fs", score.length)) }
        // Every note must be inside the piece with a sane pitch.
        for n in score.notes where n.t < 0 || n.t > score.length || n.midi < 20 || n.midi > 110 || n.dur <= 0 { problems.append("bad note at \(n.t)"); break }
        SoundBank.writeWAV(x, to: "\(dir)/music_\(mood.rawValue).wav")
        print(String(format: "%-12@ %4ld notes  %5.0f s  peak %.2f rms %.3f  \"%@\"%@", mood.rawValue as NSString, score.notes.count, score.length, peak, rms, score.title as NSString,
                     (problems.isEmpty ? "" : "  FAIL: " + problems.joined(separator: ", ")) as NSString))
        if !problems.isEmpty { failures += 1 }
    }
    print(String(format: "rendered %ld pieces in %.0f ms, %ld failed", MusicMood.allCases.count, (CFAbsoluteTimeGetCurrent() - t0) * 1000, failures))
    exit(failures == 0 ? 0 : 1)
}

if let out = arg("--bench") {
    exit(Bench.run(out))
}

if let dir = arg("--terrainmap") { exit(TerrainTools.maps(dir)) }
if CommandLine.arguments.contains("--genbench") { exit(TerrainTools.genBench()) }
if CommandLine.arguments.contains("--kelpcheck") { exit(TerrainTools.kelpCheck()) }
// Name check (tools/namecheck.py writes the list): every literal name the code looks up with Items.id / Blocks.id exists
// (an unknown name is a fatalError the first time its line runs, often in a rare event).
if let f = arg("--namecheck") {
    var bad = 0, n = 0
    let text = (try? String(contentsOfFile: f, encoding: .utf8)) ?? ""
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { continue }
        n += 1
        let name = String(parts[1])
        let ok: Bool = parts[0] == "item" ? Items.has(name) : Blocks.has(name)
        if !ok { bad += 1; print("namecheck: unknown \(parts[0]) \"\(name)\"" + (parts.count > 2 ? " at \(parts[2])" : "")) }
    }
    print("namecheck: \(n) names, \(bad) unknown")
    exit(n > 0 && bad == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--worldaudit") { exit(WorldAudit.run()) }   // STORE_QUALITY objective 7
if CommandLine.arguments.contains("--fidelitycheck") { exit(FidelityCheck.run()) }      // reference numbers (FidelityCheck.swift)
if arg("--agent") != nil { exit(AgentRun.run()) }
if CommandLine.arguments.contains("--ridecheck") { exit(RideCheck.run()) }
if CommandLine.arguments.contains("--behaviorsim") { exit(BehaviorSim.run()) }
if CommandLine.arguments.contains("--collisiontest") {
    guard let device = MTLCreateSystemDefaultDevice() else { print("no Metal device"); exit(1) }
    exit(CollisionTest.run(device: device))
}
if CommandLine.arguments.contains("--gencheck") {
    guard let device = MTLCreateSystemDefaultDevice() else { print("no Metal device"); exit(1) }
    exit(GenCheck.run(device: device))
}
if CommandLine.arguments.contains("--borealtest") {
    guard let device = MTLCreateSystemDefaultDevice() else { print("no Metal device"); exit(1) }
    var failed = 0
    BorealTests.run(device: device) { ok, what in print((ok ? "ok   " : "FAIL ") + what); if !ok { failed += 1 } }
    print(failed == 0 ? "borealtest: all checks passed" : "borealtest: \(failed) FAILED")
    exit(failed == 0 ? 0 : 1)
}
if CommandLine.arguments.contains("--structcheck") {
    guard let device = MTLCreateSystemDefaultDevice() else { print("no Metal device"); exit(1) }
    exit(StructCheck.run(device: device))
}

if let out = arg("--hdatlas") { exit(dumpHDAtlas(out)) }
if let out = arg("--atlas") {
    exit(dumpAtlas(out))
}

if let out = arg("--snapshot") {
    HudExtras.enabled = CommandLine.arguments.contains("--hints")
    let code = Snapshot.run(out)
    PrefsSandbox.end()
    exit(PadTest.failures > 0 ? 3 : code)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

// Resident memory of this process (phys_footprint, what Activity Monitor shows as Memory).
func residentMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
}
