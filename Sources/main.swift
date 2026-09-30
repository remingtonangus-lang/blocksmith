import AppKit
import Metal
import simd

// Headless test harness. Renders one frame offscreen to a PNG and prints timings, e.g.
//   Blocksmith --snapshot /tmp/shot.png --seed 42 --yaw 45 --pitch -20 --time 0.25 --up 30 --rd 8
// Angles in degrees; --time is a day fraction (0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight);
// --x/--z pick a world position (default: spawn); --up raises the camera above the terrain;
// --find <biome> (forest, desert, snowy, ...) spirals out from spawn to the middle of that biome.
enum Snapshot {
    static func findBiome(_ gen: TerrainGenerator, _ want: String) -> V3? {
        var x = 0, z = 0, dx = 0, dz = -1
        for _ in 0..<40000 {
            let wx = x * 16 + 8, wz = z * 16 + 8
            var ok = true
            for (ox, oz) in [(0, 0), (24, 0), (-24, 0), (0, 24), (0, -24)] where gen.column(wx + ox, wz + oz).biome.name != want {
                ok = false
                break
            }
            if ok {
                let h = gen.column(wx, wz).height
                return V3(Float(wx) + 0.5, Float(max(h, SEA) + 1), Float(wz) + 0.5)
            }
            if x == z || (x < 0 && x == -z) || (x > 0 && x == 1 - z) { (dx, dz) = (-dz, dx) }
            x += dx; z += dz
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
        let world = World(seed: seed, device: device, save: nil, dim: snapDim)
        world.renderDistance = rd
        let game = Game(world: world, save: nil, persistent: false)
        var pos = game.findSpawn()
        if let x = Float(arg("--x") ?? ""), let z = Float(arg("--z") ?? "") {
            let hgt = world.gen.column(Int(floor(x)), Int(floor(z))).height
            pos = V3(x, Float(max(hgt, SEA) + 1), z)
        }
        if let want = arg("--find"), let p = findBiome(world.gen, want) { pos = p }
        // --structure <kind>: stand above the start piece of the nearest structure of that kind.
        var frame: (yaw: Float, pitch: Float)?
        if let kind = arg("--structure"), let s = world.gen.structures?.nearest(kind, x: Int(pos.x), z: Int(pos.z)) {
            if arg("--frame") != nil {
                // Overview: from outside the footprint, aimed at its centre.
                let c = V3(Float(s.min.x + s.max.x) / 2, Float(s.anchor.y), Float(s.min.z + s.max.z) / 2)
                let ext = Float(max(s.max.x - s.min.x, s.max.z - s.min.z))
                let dist = max(14, ext * 0.75) * (Float(arg("--frame") ?? "") ?? 1)
                let p = c + V3(-dist * 0.7, dist * 0.55, -dist * 0.7)
                let d = c - p
                frame = (atan2f(-d.x, -d.z), atan2f(d.y, simd_length(V2(d.x, d.z))))
                pos = p
                print("structure \(kind) at \(s.anchor.x) \(s.anchor.y - YOFF) \(s.anchor.z) (\(s.pieces.count) pieces, framed)")
            } else {
            pos = V3(Float(s.anchor.x) + 0.5, Float(s.anchor.y), Float(s.anchor.z) + 0.5)
            print("structure \(kind) at \(s.anchor.x) \(s.anchor.y - YOFF) \(s.anchor.z) (\(s.pieces.count) pieces)")
            }
        }
        pos.y += Float(arg("--up") ?? "") ?? 0
        game.player.pos = pos
        game.player.yaw = frame?.yaw ?? (Float(arg("--yaw") ?? "") ?? 30) * .pi / 180
        game.player.pitch = frame?.pitch ?? (Float(arg("--pitch") ?? "") ?? -15) * .pi / 180
        game.player.flying = true
        game.time = (Double(arg("--time") ?? "") ?? 0.2) * DAY_LENGTH
        if let s = arg("--slot") { game.selected = Int(s) ?? 0 }
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
            case "death":
                game.openMenu(DeathMenu(game: game, message: "Player was blown up by Hisser"))
            case "commands":
                for c in ["/help", "/time set noon", "/give diamond 5", "/give hisser_head", "/locate sea_temple", "/summon hisser", "hello", "/tp ~ ~2 ~", "/xp 5L", "/bogus"] { game.command(c) }
                for l in game.commandLog { print("console: " + l) }
                let m = CommandMenu(game: game, prefill: "/give dia")
                m.complete()
                game.openMenu(m)
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
        if snapDim == .overworld && arg("--structure") == nil {
            // Stand on whatever is actually at the column (trees, overhangs), keeping --up.
            let up = Float(arg("--up") ?? "") ?? 0
            let ty = Float(world.topY(Int(floor(pos.x)), Int(floor(pos.z))) + 1)
            if ty + up > pos.y { pos.y = ty + up; game.player.pos = pos }
        }
        if snapDim == .nether {
            // Stand in the first open space above the lava sea.
            let x = Int(floor(pos.x)), z = Int(floor(pos.z))
            var y = YOFF + 33
            while y < YOFF + 120 && !(world.block(x, y, z) == AIR && world.block(x, y + 1, z) == AIR) { y += 1 }
            pos.y = Float(y) + (Float(arg("--up") ?? "") ?? 0)
            game.player.pos = pos
        } else if snapDim == .end {
            pos = V3(pos.x, Float(YOFF + 70) + (Float(arg("--up") ?? "") ?? 0), pos.z)
            game.player.pos = pos
        }
        // Structure mobs (crystals, boarlings...) that generation queued.
        for (name, mp) in world.pendingMobs {
            if let k = MobKind.named(name) { game.mobs.mobs.append(Mob(k, at: mp)) }
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
            let spots: [(MobKind, Float, Float)] = nether
                ? [(.zombifiedPiglin, 5, -2.5), (.piglin, 5, 0), (.witherSkeleton, 6, 2.5), (.blaze, 8, -3.5), (.magmaCube, 7, 3.5), (.ghast, 22, 2)]
                : CommandLine.arguments.contains("--hostile")
                ? [(.zombie, 5, -2.5), (.skeleton, 6, 0), (.creeper, 5, 2.5), (.spider, 9, -3.5), (.enderman, 10, 1), (.slime, 8, 4)]
                : [(.cow, 6, -2.5), (.sheep, 6, 1.5), (.chicken, 4, 0), (.pig, 10, 3), (.sheep, 9, -4), (.chicken, 5, 2.5)]
            for (i, spot) in spots.enumerated() {
                let p = pos + f * spot.1 + r * spot.2
                let x = Int(floor(p.x)), z = Int(floor(p.z))
                var y = game.mobs.grassSurface(world, x, z) ?? (world.gen.column(x, z).height + 1)
                if nether {
                    y = Int(floor(pos.y)) + 1
                    while y > Int(pos.y) - 12 && !Blocks.collide[Int(world.block(x, y - 1, z))] { y -= 1 }
                    if spot.0 == .ghast || spot.0 == .blaze { y += spot.0 == .ghast ? 5 : 2 }
                }
                let m = Mob(spot.0, at: V3(Float(x) + 0.5, Float(y), Float(z) + 0.5))
                if spot.0 == .slime || spot.0 == .magmaCube { m.makeSlime(size: 2) }
                m.yaw = game.player.yaw + .pi + Float(i) * 0.9
                m.walkPhase = Float(i) * 0.8
                m.walkAmount = 1
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
                st.pat = [[14, 4], [11, 3], [5, 0], [13, 5], [1, 2, 4]][i] + (i == 1 ? [16 + 0] : [])
                let rk = Rocket(at: pos + f * 22 + r * (Float(i) - 2) * 7 + V3(0, 10 + Float(i % 2) * 4, 0), dir: V3(0, 1, 0), flight: 1, stars: [st])
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
                let p = pos + f * 8 + r * (Float(i) - Float(sets.count - 1) / 2) * 1.6
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
            for (i, it) in ["diamond_sword", "apple"].enumerated() {
                let fp = front(-1 + i, 2)
                world.setBlock(fp.x, fp.y, fp.z, Blocks.id("item_frame") + BlockID(facing))
                let fb = BlockEntity(.frame); fb.container[0] = ItemStack(Items.id(it), 1); world.blockEntities[fp] = fb
            }
            game.placePainting(at: front(1, 1), facing: facing)
        }
        if let list = arg("--spawn") {
            // Mobs in a row 6 blocks in front of the camera, facing it ("kind" or "kind:profession").
            let f = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw)), r = V3(cosf(game.player.yaw), 0, -sinf(game.player.yaw))
            let names = list.split(separator: ",").map(String.init)
            for (i, n) in names.enumerated() {
                let parts = n.split(separator: ":").map(String.init)
                guard let k = MobKind.named(parts[0]) else { print("unknown mob \(n)"); continue }
                let p = pos + f * 6 + r * (Float(i) - Float(names.count - 1) / 2) * 2.2
                let x = Int(floor(p.x)), z = Int(floor(p.z))
                let m = Mob(k, at: V3(Float(x) + 0.5, Float(world.topY(x, z) + 1), Float(z) + 0.5))
                m.yaw = game.player.yaw
                if k == .boat {
                    m.variant = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
                    m.chested = parts.count > 2
                    m.yaw += Float(i) * 0.4
                } else if parts.count > 1 && ["leather", "golden", "chainmail", "iron", "diamond", "netherite"].contains(parts[1]) {
                    // "zombie:iron" / "armor_stand:diamond": a full set of that armour (+ a sword).
                    var eq = ["helmet", "chestplate", "leggings", "boots"].map { p -> ItemStack in
                        let n = parts[1] == "leather" && p == "helmet" ? "leather_helmet" : "\(parts[1])_\(p)"
                        return Items.has(n) ? ItemStack(Items.id(n), 1) : .empty
                    }
                    eq.append(Items.has("\(parts[1])_sword") ? ItemStack(Items.id("\(parts[1])_sword"), 1) : .empty)
                    m.equip = eq
                } else if parts.count > 1 { var d = VillagerData(); d.profession = parts[1]; m.villager = d }
                if k == .wither { m.phase = 0; m.pos.y += 2 }
                if k == .evoker { m.spellTimer = 4.5 }
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
                let p = pos + f * 4 + r * (Float(i) - Float(names.count - 1) / 2) * 1.5
                let x = Int(floor(p.x)), z = Int(floor(p.z))
                let gy = world.topY(x, z)
                world.setBlock(x, gy, z, Blocks.id("smooth_stone"))
                world.setBlock(x, gy + 1, z, Blocks.id(String(parts[0])) + BlockID(parts.count > 1 ? Int(parts[1]) ?? 0 : 0))
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
        if CommandLine.arguments.contains("--torches") {
            // Light test: a ring of torches plus a lamp around the camera, then remesh what changed.
            for k in 0..<10 {
                let a = Float(k) / 10 * 2 * .pi
                let x = Int(floor(pos.x + cosf(a) * 7)), z = Int(floor(pos.z + sinf(a) * 7))
                let h = world.gen.column(x, z).height
                if h >= SEA { world.setBlock(x, h + 1, z, TORCH) }
            }
            let lx = Int(floor(pos.x)) + 3, lz = Int(floor(pos.z))
            world.setBlock(lx, world.gen.column(lx, lz).height + 1, lz, LAMP)
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
                if i % 20 == 0 {
                    print(String(format: "  t=%.0f zombie %.1f,%.1f,%.1f ground %ld path %ld/%ld hp %ld", Float(i) * 0.05, z.pos.x - Float(bx), z.pos.y - Float(gy), z.pos.z - Float(bz),
                                 z.onGround ? 1 : 0, z.path.index, z.path.nodes.count, z.health))
                    print(String(format: "    vel %.2f,%.2f,%.2f yaw %.0f speedTarget %@ below %@ mount %@ mobs %ld", z.vel.x, z.vel.y, z.vel.z, z.yaw * 180 / .pi,
                                 z.faceGoal.map { String(format: "%.1f,%.1f,%.1f", $0.x - Float(bx), $0.y - Float(gy), $0.z - Float(bz)) } ?? "-",
                                 Blocks.key(world.block(Int(floor(z.pos.x)), Int(floor(z.pos.y - 0.1)), Int(floor(z.pos.z)))), z.mount == nil ? "no" : "yes", game.mobs.mobs.count))
                }
            }
            print(String(format: "pathtest: zombie start %.1f from player, end %.1f, reached %@", d0, simd_length(z.pos - to), reached < 0 ? "never" : String(format: "after %.1f s", reached)))
            game.player.pos = pos
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

        // Mesh benchmark: re-mesh the section at the camera a few times on one thread.
        let key = ChunkKey(x: floorDiv(Int(pos.x), CS), z: floorDiv(Int(pos.z), CS))
        var n9: [[BlockID]] = [], h9: [[Int16]] = []
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
        game.target = world.raycast(game.player.eye, game.player.look, maxDist: 5)
        _ = renderer.renderToPNG(path: out, width: w, height: h) // warm-up (pipeline + residency)
        let gpu = renderer.renderToPNG(path: out, width: w, height: h)

        print(String(format: "seed %llu  pos %.1f %.1f %.1f  rd %ld  chunks %ld  (drawn %ld)", seed, pos.x, pos.y, pos.z, rd, world.chunks.count, renderer.drawnChunks))
        print(String(format: "gen %.0f ms  mesh(all, parallel) %.0f ms  mesh(1 section) %.2f ms  quads %ld opaque / %ld water", t.gen * 1000, t.mesh * 1000, meshMs, quads, water))
        print(String(format: "frame (encode+GPU, offscreen) %.2f ms  biome %@", gpu * 1000, "\(world.gen.column(Int(pos.x), Int(pos.z)).biome)"))
        var meshBytes = 0
        for c in world.chunks.values { for sec in c.sections { meshBytes += (sec.opaqueBuf?.length ?? 0) + (sec.transBuf?.length ?? 0) } }
        print(String(format: "memory: resident %.0f MB  (section meshes %.0f MB)", residentMB(), Double(meshBytes) / 1_048_576))
        print("wrote \(out)")
        return 0
    }
}

if let dir = arg("--sounds") {
    // Synth check: render every sound effect (variant 0) to a WAV file.
    let t0 = CFAbsoluteTimeGetCurrent()
    let bank = SoundBank()
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var total = 0
    for s in SoundBank.allSounds {
        let c = bank.clip(s, variant: 0)
        total += c.count
        let name = String("\(s)".replacingOccurrences(of: "Blocksmith.SoundMat.", with: "").map { $0.isLetter || $0.isNumber ? $0 : "_" })
        SoundBank.writeWAV(c, to: "\(dir)/\(name).wav")
    }
    print(String(format: "synthesized %ld sounds (%.1f s of audio) in %.0f ms", SoundBank.allSounds.count, Double(total) / SoundBank.rate, (CFAbsoluteTimeGetCurrent() - t0) * 1000))
    exit(0)
}

if let out = arg("--snapshot") {
    exit(Snapshot.run(out))
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
