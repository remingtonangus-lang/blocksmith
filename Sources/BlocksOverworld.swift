import Foundation

// Surface block expansion for the biome/terrain rework: the other wood types, ground and stone
// blocks, surface plants (incl. two-tall plants), water plants, cave blocks and badlands terracotta.
extension BlockRegistry {
    static let extraWoods: [(String, String)] = [("acacia", "Acacia"), ("dark_oak", "Dark Oak"), ("jungle", "Jungle"),
                                                 ("mangrove", "Mangrove"), ("cherry", "Cherry")]

    func registerOverworldBlocks() {
        func cube(_ n: String, _ disp: String, _ t: String? = nil, h: Float = 1.5, tool: ToolType = .pickaxe, lvl: Int = 0,
                  req: Bool = false, snd: SoundMat = .stone, emit: UInt8 = 0) {
            var d = BlockDef(n, disp)
            d.tex = [t ?? n]; d.hardness = h; d.tool = tool; d.harvestLevel = lvl; d.requiresTool = req; d.sound = snd; d.emit = emit
            add(d)
        }
        func sided(_ n: String, _ disp: String, side: String, top: String, bottom: String, h: Float, tool: ToolType, snd: SoundMat, req: Bool = false) {
            var d = BlockDef(n, disp)
            d.tex = [side, side, top, bottom, side, side]; d.hardness = h; d.tool = tool; d.sound = snd; d.requiresTool = req
            add(d)
        }
        func plant(_ n: String, _ disp: String, tint: UInt8 = 0, emit: UInt8 = 0, water: Bool = false) {
            var d = BlockDef(n, disp)
            d.tex = [n]; d.render = .cross; d.layer = .cutout; d.opaque = false; d.collide = false
            d.hardness = 0; d.sound = .plant; d.replaceable = emit == 0 && !water; d.tint = tint; d.emit = emit; d.skyStop = false
            if water { d.fluid = 0; d.fluidKind = 1; d.skyStop = true }       // grows inside water (acts as water)
            add(d)
        }
        // Two-block-tall plant: lower and upper states in one group.
        func tall(_ n: String, _ disp: String, tint: UInt8 = 0) {
            for upper in [false, true] {
                var d = BlockDef(upper ? "\(n)[upper]" : n, disp)
                d.tex = [upper ? "\(n)_top" : "\(n)_bottom"]; d.render = .cross; d.layer = .cutout; d.opaque = false
                d.collide = false; d.hardness = 0; d.sound = .plant; d.replaceable = true; d.tint = tint; d.skyStop = false
                d.group = n; d.hidden = upper
                add(d)
            }
        }

        // Woods.
        for (w, disp) in BlockRegistry.extraWoods {
            pillar("\(w)_log", "\(disp) Log", side: "\(w)_log", top: "\(w)_log_top")
            var lv = BlockDef("\(w)_leaves", "\(disp) Leaves")
            lv.tex = ["\(w)_leaves"]; lv.opaque = false; lv.layer = .cutout; lv.hardness = 0.2; lv.tool = .hoe; lv.sound = .plant
            lv.tint = w == "cherry" ? 0 : 2
            add(lv)
            cube("\(w)_planks", "\(disp) Planks", h: 2, tool: .axe, snd: .wood)
            var sap = BlockDef(w == "mangrove" ? "mangrove_propagule" : "\(w)_sapling", w == "mangrove" ? "Mangrove Propagule" : "\(disp) Sapling")
            sap.tex = [sap.name]; sap.render = .cross; sap.layer = .cutout; sap.opaque = false; sap.collide = false
            sap.hardness = 0; sap.sound = .plant; sap.randomTicks = true; sap.skyStop = false
            add(sap)
        }
        var roots = BlockDef("mangrove_roots", "Mangrove Roots")
        roots.tex = ["mangrove_roots"]; roots.opaque = false; roots.layer = .cutout; roots.hardness = 0.7; roots.tool = .axe; roots.sound = .wood
        add(roots)

        // Ground.
        sided("podzol", "Podzol", side: "podzol_side", top: "podzol_top", bottom: "dirt", h: 0.5, tool: .shovel, snd: .dirt)
        cube("coarse_dirt", "Coarse Dirt", h: 0.5, tool: .shovel, snd: .dirt)
        cube("rooted_dirt", "Rooted Dirt", h: 0.5, tool: .shovel, snd: .dirt)
        sided("mycelium", "Mycelium", side: "mycelium_side", top: "mycelium_top", bottom: "dirt", h: 0.6, tool: .shovel, snd: .dirt)
        cube("mud", "Mud", h: 0.5, tool: .shovel, snd: .dirt)
        cube("packed_mud", "Packed Mud", h: 1, tool: .pickaxe, snd: .dirt)
        cube("mud_bricks", "Mud Bricks", h: 1.5, req: true)
        var ice = BlockDef("ice", "Ice")
        ice.tex = ["ice"]; ice.opaque = false; ice.layer = .translucent; ice.hardness = 0.5; ice.tool = .pickaxe; ice.sound = .glass
        ice.cullSame = true; ice.skyStop = true
        add(ice)
        cube("packed_ice", "Packed Ice", h: 0.5, snd: .glass)
        cube("blue_ice", "Blue Ice", h: 2.8, snd: .glass)
        var layer = BlockDef("snow", "Snow")
        layer.tex = ["snow_block"]; layer.render = .model; layer.opaque = false; layer.hardness = 0.1; layer.tool = .shovel
        layer.sound = .snow; layer.replaceable = true; layer.boxes = [Box(0, 0, 0, 16, 2, 16)]; layer.skyStop = false
        layer.noCollideBoxes = true; layer.collide = false
        add(layer)
        var ps = BlockDef("powder_snow", "Powder Snow")
        ps.tex = ["snow_block"]; ps.hardness = 0.25; ps.tool = .shovel; ps.sound = .snow; ps.collide = false
        add(ps)
        cube("calcite", "Calcite", h: 0.75, req: true)
        cube("dripstone_block", "Driprock Block", h: 1.5, req: true)
        var drip = BlockDef("pointed_dripstone", "Pointed Driprock")
        drip.tex = ["pointed_dripstone"]; drip.render = .cross; drip.layer = .cutout; drip.opaque = false; drip.hardness = 1.5
        drip.tool = .pickaxe; drip.damage = 0; drip.skyStop = false; drip.collide = false
        add(drip)
        cube("moss_block", "Moss Block", h: 0.1, tool: .hoe, snd: .plant)
        var moss = BlockDef("moss_carpet", "Moss Carpet")
        moss.tex = ["moss_block"]; moss.render = .model; moss.opaque = false; moss.hardness = 0.1; moss.sound = .plant
        moss.boxes = [Box(0, 0, 0, 16, 1, 16)]; moss.replaceable = false; moss.skyStop = false
        add(moss)
        sided("red_sandstone", "Red Sandstone", side: "red_sandstone", top: "red_sandstone_top", bottom: "red_sandstone_top", h: 0.8, tool: .pickaxe, snd: .stone, req: true)
        for c in ["white", "orange", "yellow", "brown", "red", "light_gray"] {
            cube("\(c)_terracotta", "\(c.replacingOccurrences(of: "_", with: " ").capitalized) Terracotta", h: 1.25, req: true)
        }
        cube("smooth_basalt", "Smooth Basalt", h: 1.25, req: true)
        cube("amethyst_block", "Block of Amethyst", h: 1.5, req: true, snd: .glass)
        cube("budding_amethyst", "Budding Amethyst", h: 1.5, snd: .glass)
        var cluster = BlockDef("amethyst_cluster", "Amethyst Cluster")
        cluster.tex = ["amethyst_cluster"]; cluster.render = .cross; cluster.layer = .cutout; cluster.opaque = false
        cluster.hardness = 1.5; cluster.emit = 5; cluster.collide = false; cluster.sound = .glass; cluster.skyStop = false
        add(cluster)
        cube("sculk", "Murk", h: 0.2, tool: .hoe, snd: .plant)
        var shrieker = BlockDef("sculk_shrieker", "Murk Shrieker")
        shrieker.tex = ["sculk_shrieker_side", "sculk_shrieker_side", "sculk_shrieker_top", "sculk", "sculk_shrieker_side", "sculk_shrieker_side"]
        shrieker.render = .model; shrieker.opaque = false; shrieker.hardness = 3; shrieker.boxes = [Box(0, 0, 0, 16, 8, 16)]
        add(shrieker)
        var reinforced = BlockDef("reinforced_deepslate", "Reinforced Deeprock")
        reinforced.tex = ["reinforced_deepslate"]; reinforced.hardness = 55; reinforced.resistance = 1200
        add(reinforced)
        cube("polished_deepslate", "Polished Deeprock", h: 3.5, req: true)
        cube("deepslate_bricks", "Deeprock Bricks", h: 3.5, req: true)
        cube("deepslate_tiles", "Deeprock Tiles", h: 3.5, req: true)

        // Plants.
        plant("fern", "Fern", tint: 1)
        tall("tall_grass", "Tall Grass", tint: 1)
        tall("large_fern", "Large Fern", tint: 1)
        tall("sunflower", "Sunflower")
        tall("lilac", "Lilac")
        tall("rose_bush", "Rose Bush")
        tall("peony", "Peony")
        for (n, d) in [("allium", "Allium"), ("azure_bluet", "Azure Bluet"), ("red_tulip", "Red Tulip"), ("orange_tulip", "Orange Tulip"),
                       ("white_tulip", "White Tulip"), ("pink_tulip", "Pink Tulip"), ("oxeye_daisy", "Oxeye Daisy"),
                       ("lily_of_the_valley", "Lily of the Valley"), ("blue_orchid", "Blue Orchid"), ("dead_bush", "Dead Bush"),
                       ("brown_mushroom", "Brown Mushroom"), ("red_mushroom", "Red Mushroom"), ("pink_petals", "Pink Petals")] {
            plant(n, d)
        }
        for st in 0...3 {
            var b = BlockDef(st == 0 ? "sweet_berry_bush" : "sweet_berry_bush_\(st)", "Sweet Berry Bush")
            b.tex = [st < 2 ? "sweet_berry_bush_stage\(st)" : "sweet_berry_bush_stage\(st)"]; b.render = .cross; b.layer = .cutout
            b.opaque = false; b.collide = false; b.hardness = 0; b.sound = .plant; b.randomTicks = true; b.group = "sweet_berry_bush"
            b.hidden = st != 0; b.damage = st > 0 ? 1 : 0; b.skyStop = false
            add(b)
        }
        sided("mushroom_stem", "Mushroom Stem", side: "mushroom_stem", top: "mushroom_block_inside", bottom: "mushroom_block_inside", h: 0.2, tool: .axe, snd: .wood)
        cube("brown_mushroom_block", "Brown Mushroom Block", h: 0.2, tool: .axe, snd: .wood)
        cube("red_mushroom_block", "Red Mushroom Block", h: 0.2, tool: .axe, snd: .wood)
        var lily = BlockDef("lily_pad", "Lily Pad")
        lily.tex = ["lily_pad"]; lily.render = .model; lily.layer = .cutout; lily.opaque = false; lily.hardness = 0
        lily.boxes = [Box(0, 0, 0, 16, 1, 16)]; lily.tint = 2; lily.sound = .plant; lily.skyStop = false
        add(lily)
        var vine = BlockDef("vine", "Vines")
        vine.tex = ["vine"]; vine.render = .cross; vine.layer = .cutout; vine.opaque = false; vine.collide = false
        vine.hardness = 0.2; vine.tool = .shears; vine.tint = 2; vine.sound = .plant; vine.replaceable = true; vine.skyStop = false
        add(vine)
        var bamboo = BlockDef("bamboo", "Bamboo")
        bamboo.tex = ["bamboo_stalk"]; bamboo.render = .model; bamboo.opaque = false; bamboo.hardness = 1; bamboo.tool = .axe
        bamboo.boxes = [Box(6, 0, 6, 10, 16, 10)]; bamboo.sound = .wood; bamboo.skyStop = false; bamboo.randomTicks = true
        add(bamboo)
        sided("melon", "Melon", side: "melon_side", top: "melon_top", bottom: "melon_top", h: 1, tool: .axe, snd: .wood)
        sided("pumpkin", "Pumpkin", side: "pumpkin_side", top: "pumpkin_top", bottom: "pumpkin_top", h: 1, tool: .axe, snd: .wood)
        var azalea = BlockDef("azalea", "Azalea")
        azalea.tex = ["azalea_side", "azalea_side", "azalea_top", "azalea_side", "azalea_side", "azalea_side"]
        azalea.render = .model; azalea.layer = .cutout; azalea.opaque = false; azalea.hardness = 0; azalea.sound = .plant
        azalea.boxes = [Box(0, 8, 0, 16, 16, 16), Box(7, 0, 7, 9, 8, 9)]; azalea.skyStop = false
        add(azalea)
        var berries = BlockDef("cave_vines", "Cave Vines")
        berries.tex = ["cave_vines"]; berries.render = .cross; berries.layer = .cutout; berries.opaque = false; berries.collide = false
        berries.hardness = 0; berries.sound = .plant; berries.emit = 14; berries.skyStop = false
        add(berries)

        // Water plants (they count as water for swimming and flow).
        plant("seagrass", "Seagrass", water: true)
        plant("kelp", "Kelp", water: true)
        for c in ["tube", "brain", "bubble", "fire", "horn"] {
            cube("\(c)_coral_block", "\(c.capitalized) Coral Block", h: 1.5, req: true)
            plant("\(c)_coral", "\(c.capitalized) Coral", water: true)
        }
        cube("sea_lantern", "Tide Lantern", h: 0.3, snd: .glass, emit: 15)
        cube("prismarine", "Tidestone", h: 1.5, req: true)
        cube("prismarine_bricks", "Tidestone Bricks", h: 1.5, req: true)
        cube("dark_prismarine", "Dark Tidestone", h: 1.5, req: true)
        var sponge = BlockDef("wet_sponge", "Wet Sponge")
        sponge.tex = ["wet_sponge"]; sponge.hardness = 0.6; sponge.tool = .hoe; sponge.sound = .plant
        add(sponge)
        cube("sponge", "Sponge", h: 0.6, tool: .hoe, snd: .plant)
    }
}
