import Foundation
import simd
import Metal

// The Oct 12 afternoon playtest fixes (backlog P107-P139), `questcheck --p12pm-only [P1xx]`: one check per item.
enum PlaytestOct12PMTests {
    static func run(_ g: Game, only: String?, check: (Bool, String) -> Void) {
        let all: [(String, (Game, (Bool, String) -> Void) -> Void)] = [
            ("P107", p107), ("P108", p108), ("P109", p109), ("P110", p110), ("P111", p111), ("P112", p112), ("P114", p114), ("P115", p115), ("P116", p116), ("P117", p117), ("P118", p118), ("P119", p119), ("P120", p120), ("P121", p121), ("P122", p122), ("P123", p123),
        ]
        for (k, f) in all where only == nil || only == k { f(g, check) }
    }

    // P107: a smooth world reopens smooth. A new world's meta is written at creation; a meta holding a non-finite float
    // (it made JSONEncoder throw and world.json was never written) still saves and loads.
    static func p107(_ g: Game, _ check: (Bool, String) -> Void) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("p107-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let was = SmoothTerrain.enabled
        defer { SmoothTerrain.set(was, world: nil) }
        let dir = root.appendingPathComponent("Smooth World", isDirectory: true)
        guard let req = WorldRequest.create(action: "create:1:2:1:Smooth World:4242") else { check(false, "P107: create action"); return }
        // First visit: a new world, created smooth.
        SmoothTerrain.set(false, world: nil)
        let save = SaveManager(dir: dir)
        let w = World(seed: req.seed ?? 1, device: g.world.device, save: save)
        w.renderDistance = 2
        let g1 = Game(world: w, save: save, persistent: true)
        req.setUp(g1, meta: save.loadMeta())
        SaveIO.flush()
        let early = SaveManager(dir: dir).loadMeta()?.extra?["terrain"] == "smooth"
        _ = w.loadSync(center: g1.player.pos, radius: 1)
        g1.absorption = .infinity                       // a non-finite float in the meta
        g1.saveNow(); SaveIO.flush()
        // The app closes; the next launch opens the world by name (no options on the request) in cubic mode.
        SmoothTerrain.set(false, world: nil)
        let save2 = SaveManager(dir: dir)
        let meta = save2.loadMeta()
        let w2 = World(seed: meta?.seed ?? 99, device: g.world.device, save: save2)
        w2.renderDistance = 2
        let g2 = Game(world: w2, save: save2, persistent: true)
        WorldRequest(name: "Smooth World").setUp(g2, meta: meta)
        check(early && meta != nil && meta?.seed == 4242 && g2.smoothTerrain && SmoothTerrain.enabled == (SmoothTerrain.forced ?? true),
              "P107 smooth world reopens smooth: meta written at creation \(early), loads with a non-finite float \(meta != nil), seed \(meta?.seed ?? 0), option \(g2.smoothTerrain), mesher \(SmoothTerrain.enabled)")
    }

    // P108: no HUD line (the button prompts, the wallet, the combat gauges...) overlaps the hotbar, gun in hand, at
    // every HUD scale on the headset's panel and on the Mac's window.
    static func p108(_ g: Game, _ check: (Bool, String) -> Void) {
        let st = Settings.shared
        let hints = st.buttonHints, secs = st.hintSeconds, scale0 = HudLayout.userScale
        let held = g.inventory.main[g.inventory.selected], surv = g.survival
        defer { st.buttonHints = hints; st.hintSeconds = secs; HudLayout.userScale = scale0; g.inventory.main[g.inventory.selected] = held; g.survival = surv }
        st.buttonHints = true; st.hintSeconds = 0; g.survival = true
        var hits: [String] = [], screens = 0
        for gun in [Guns.all[0].key, Guns.all.last!.key, "diamond_pickaxe"] where Items.has(gun) {
            g.inventory.main[g.inventory.selected] = ItemStack(Items.id(gun), 1)
            for (W, H) in [(1024, 640), (1280, 800), (1920, 1080)] as [(Float, Float)] {
                for k in 0...4 {
                    HudLayout.userScale = k
                    let L = HudLayout(W, H)
                    screens += 1
                    let x0 = L.hotbarX0, x1 = L.hotbarX0 + L.slot * 9, y0 = L.hotbarY0, y1 = L.hotbarY0 + L.slot
                    for l in HudExtras.lines(g, L) where !(l.text.isEmpty && l.box == nil) {
                        let w = l.box?.x ?? Float(Font.width(l.text)) * l.scale, h = l.box?.y ?? 8 * l.scale
                        if l.x < x1 && l.x + w > x0 && l.y < y1 && l.y + h > y0 { hits.append("\(Int(W))x\(Int(H)) s\(Int(L.s)) \(gun): \"\(l.text)\"") }
                    }
                }
            }
        }
        check(hits.isEmpty, "P108 nothing on the HUD overlaps the hotbar (\(screens) screens and scales, gun in hand): \(hits.prefix(3))")
    }

    // P109: with a gun in hand (not full, rounds in the pack) a left grip held out in front of the waist steps the hotbar
    // (VRReload takes nothing); only a hand down at the side by the hip takes a magazine. Checked at four body headings.
    static func p109(_ g: Game, _ check: (Bool, String) -> Void) {
        let held0 = g.inventory.held, inv = g.inventory.main.slots, surv = g.survival, yaw0 = g.player.yaw
        defer { g.inventory.main.slots = inv; g.inventory.held = held0; g.survival = surv; g.arms.magInHand = false; g.player.yaw = yaw0 }
        g.survival = true
        var gun = ItemStack(Items.id("gun_rifle"), 1); gun.tag = 0
        g.inventory.held = gun
        let slot = (0..<36).first { $0 != g.selected && g.inventory.main[$0].isEmpty } ?? 20
        g.inventory.main[slot] = ItemStack(Items.id("capital_rounds"), 64)
        var front: [VRReload.Event] = [], side: [VRReload.Event] = []
        for yaw in [Float(0), 1.2, 2.6, -2.0] {
            g.player.yaw = yaw
            g.arms.magInHand = false
            let f = V3(-sinf(yaw), 0, -cosf(yaw)), r = V3(-f.z, 0, f.x)
            let head = g.player.eye, gunHand = head + r * 0.2 + f * 0.35 + V3(0, -0.35, 0)
            // In front of the waist, a little to the left: the usual pose for pressing the grip.
            let waist = head + f * 0.3 - r * 0.15 + V3(0, -0.6, 0)
            front.append(VRReload.tick(g, offHand: waist, gunHand: gunHand, head: head, grip: true, gripWas: false))
            // Down by the left hip.
            let hip = head - r * 0.25 + f * 0.02 + V3(0, -0.8, 0)
            side.append(VRReload.tick(g, offHand: hip, gunHand: gunHand, head: head, grip: true, gripWas: false))
            g.arms.magInHand = false
        }
        check(front.allSatisfy { $0 == .none } && side.allSatisfy { $0 == .grabbed },
              "P109 left grip with a gun: in front of the waist \(front) (the hotbar steps); at the hip \(side) (a magazine)")
    }

    // P110: inventory icons draw the block's front (furnace, dispenser, dropper, observer: the +Z face the icon shows on
    // its left), the observer has its new lens face, and a bed icon has both halves (headboard at the back).
    static func p110(_ g: Game, _ check: (Bool, String) -> Void) {
        let fronts = [("furnace", "furnace_front"), ("dispenser", "dispenser_front"), ("dropper", "dropper_front"),
                      ("observer", "observer_front"), ("chest", "chest_front")]
        var wrong: [String] = []
        for (b, f) in fronts {
            let s = Blocks.iconState(Blocks.id(b))
            if Blocks.groupBase[Int(s)] != Blocks.id(b) || Blocks.tex[Int(s) * 6 + 4] != Tex.id(f) { wrong.append(b) }
        }
        let head = Blocks.has("red_bed_head[south]") ? Blocks.boxes[Int(Blocks.id("red_bed_head[south]"))] : []
        let board = head.max { Int($0.y1) < Int($1.y1) }
        let backBoard = board.map { $0.z1 <= 2 } ?? false
        check(wrong.isEmpty && Blocks.iconState(Blocks.id("red_bed")) == Blocks.id("red_bed[south]") && backBoard,
              "P110 icons: the front shows for every faced block (wrong: \(wrong)); the bed icon pairs the foot with its head, headboard at the back \(backBoard)")
    }

    // P111: the web and the amethyst block are painted again (their imported art replaced the looks he liked); granite
    // sharpened and stone given the deepslate rock's look are art files (Resources/Textures, texpack.bin).
    static func p111(_ g: Game, _ check: (Bool, String) -> Void) {
        check(TextureGen.painted.contains("cobweb") && TextureGen.painted.contains("amethyst_block"),
              "P111 textures: the cobweb and the amethyst block use their painters (\(TextureGen.painted.sorted()))")
    }

    // P112: small cave pools: over 24 chunks there are some, and every one is held (rock below and round it).
    static func p112(_ g: Game, _ check: (Bool, String) -> Void) {
        let gen = WorldGen(seed: 12345)
        var pools = 0, cells = 0, leaks = 0
        for cz in 0..<4 { for cx in 0..<6 {
            let b = gen.generate(cx: cx * 3 - 7, cz: cz * 3 + 2)
            for y in max(3, YOFF - 40)..<(SEA - 10) { for lz in 3..<(CS - 3) { for lx in 3..<(CS - 3) {
                let i = Chunk.index(lx, y, lz)
                guard b[i] == WATER, b[i + CSQ] == AIR else { continue }
                cells += 1
                let sides = [1, -1, CS, -CS].map { b[i + $0] }
                if !sides.contains(WATER) || sides.filter({ $0 == WATER }).count == 1 && b[i - 1] != WATER && b[i - CS] != WATER { pools += 1 }
                if sides.contains(AIR) || !Blocks.opaque[Int(b[i - CSQ])] && b[i - CSQ] != WATER { leaks += 1 }
            } } }
        } }
        check(cells >= 6 && leaks == 0, "P112 cave water: \(cells) pool cells (about \(pools) pools) on cave floors in 24 chunks; \(leaks) open to the air at the side")
    }
    // P114: lava. A block goes into lava with nothing solid in reach; a dropped item in lava burns up; fluid cells near
    // the player tick before a backlog of far ones; water poured beside a lava source makes obsidian on the next lava tick.
    static func p114(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let pos0 = g.player.pos, yaw0 = g.player.yaw, pitch0 = g.player.pitch, held0 = g.inventory.held, fly0 = g.player.flying
        let focus0 = World.focus
        var cells: [IVec3] = []
        defer {
            for c in cells { w.setBlock(c.x, c.y, c.z, AIR) }
            g.player.pos = pos0; g.player.yaw = yaw0; g.player.pitch = pitch0; g.inventory.held = held0; g.player.flying = fly0
            World.focus = focus0
        }
        let surv0 = g.survival
        defer { g.survival = surv0 }
        g.survival = true
        g.player.flying = true
        g.player.pos = V3(Float(Int(pos0.x)) + 0.5, 330, Float(Int(pos0.z)) + 0.5)
        g.player.yaw = 0; g.player.pitch = 0
        _ = w.loadSync(center: g.player.pos, radius: 2)
        let eye = g.player.eye
        let c = IVec3(Int(floor(eye.x)), Int(floor(eye.y)), Int(floor(eye.z)) - 3)
        cells.append(c)
        w.setBlock(c.x, c.y, c.z, LAVA)
        g.inventory.held = ItemStack(Items.id("cobblestone"), 8)
        let placed = g.placeIntoLava() && w.block(c.x, c.y, c.z) == COBBLE && g.inventory.held.count == 7
        // Items burn.
        let c2 = IVec3(c.x + 3, c.y, c.z)
        cells.append(c2)
        w.setBlock(c2.x, c2.y, c2.z, LAVA)
        let b0 = g.drops.burned
        g.drops.spawn(ItemStack(Items.id("oak_planks"), 5), at: V3(Float(c2.x) + 0.5, Float(c2.y) + 0.3, Float(c2.z) + 0.5), vel: .zero, delay: 9)
        g.drops.spawn(ItemStack(Items.id("netherite_ingot"), 1), at: V3(Float(c2.x) + 0.5, Float(c2.y) + 0.3, Float(c2.z) + 0.5), vel: .zero, delay: 9)
        _ = g.drops.update(0.05, game: g)
        let burnt = g.drops.burned == b0 + 1
            && g.drops.items.contains { $0.stack.def.name == "netherite_ingot" } && !g.drops.items.contains { $0.stack.def.name == "oak_planks" }
        g.drops.items.removeAll { simd_length($0.pos - V3(Float(c2.x), Float(c2.y), Float(c2.z))) < 3 }
        // The queue: near first.
        World.focus = IVec3(0, 100, 0)
        var q = FluidQueue()
        for i in 0..<500 { q.insert(IVec3(1000 + i, 100, 0)) }
        q.insert(IVec3(3, 100, 2))
        let first = q.take(4)
        let nearFirst = first.count == 1 && first.first == IVec3(3, 100, 2) && q.count == 500
        // Obsidian.
        World.focus = IVec3(c.x, c.y, c.z)
        let c3 = IVec3(c.x - 3, c.y, c.z), c4 = IVec3(c.x - 4, c.y, c.z)
        cells.append(contentsOf: [c3, c4])
        w.setBlock(c3.x, c3.y, c3.z, LAVA)
        w.setBlock(c4.x, c4.y, c4.z, WATER)
        w.scheduleFluid(around: c4)
        w.fluidTick(lava: true)
        let obsidian = w.block(c3.x, c3.y, c3.z) == OBSIDIAN
        check(placed && burnt && nearFirst && obsidian,
              "P114 lava: a block goes into lava with nothing solid in reach \(placed); dropped planks burn, Duskium doesn't \(burnt); near cells tick first \(nearFirst); water beside a source hardens it on the next tick \(obsidian)")
    }

    // P115: bounty hunters never set out while you're underground; on the surface an outlaw draws five or more, and they
    // come at most every three days.
    static func p115(_ g: Game, _ check: (Bool, String) -> Void) {
        let pos0 = g.player.pos, mobs0 = g.mobs.mobs, hon0 = Honour.value, chance0 = BountyHunters.chancePerSecond
        let surv0 = g.survival, diff0 = g.difficulty, law0 = TownLaw.state, inTown0 = TownLaw.inTown, fly0 = g.player.flying
        defer {
            g.player.pos = pos0; g.mobs.mobs = mobs0; Honour.value = hon0; BountyHunters.chancePerSecond = chance0
            g.survival = surv0; g.difficulty = diff0; TownLaw.state = law0; TownLaw.inTown = inTown0; g.player.flying = fly0
        }
        g.survival = true; g.difficulty = 2; g.player.flying = false
        TownLaw.inTown = nil; TownLaw.state.huntersDay = nil
        Honour.value = -90
        BountyHunters.chancePerSecond = 1
        let x = Int(floor(pos0.x)), z = Int(floor(pos0.z))
        _ = g.world.loadSync(center: pos0, radius: 3)
        let top = g.world.topY(x, z)
        g.player.pos = V3(Float(x) + 0.5, Float(top - 20), Float(z) + 0.5)
        g.mobs.mobs = []
        BountyHunters.tick(g)
        let none = !g.mobs.mobs.contains { $0.customName == BountyHunters.name }
        g.player.pos = V3(Float(x) + 0.5, Float(top + 1), Float(z) + 0.5)
        Rand.seed(4242)
        BountyHunters.tick(g)
        let n = g.mobs.mobs.filter { $0.customName == BountyHunters.name }.count
        g.mobs.mobs = []
        let day = Int(g.time / DAY_LENGTH)
        TownLaw.state.huntersDay = day - 2
        BountyHunters.tick(g)
        let wait = g.mobs.mobs.isEmpty
        check(none && n >= 5 && wait && chance0 <= 1.0 / 600,
              "P115 bounty hunters: none sent underground \(none); on the surface \(n) ride in for an outlaw; not again two days later \(wait); chance a second 1/\(Int(1 / chance0))")
    }

    // P117: the bonded horse doesn't come when called from underground.
    static func p117(_ g: Game, _ check: (Bool, String) -> Void) {
        let pos0 = g.player.pos, bond0 = g.horseBond, mobs0 = g.mobs.mobs, call0 = g.horseCall
        defer { g.player.pos = pos0; g.horseBond = bond0; g.mobs.mobs = mobs0; g.horseCall = call0 }
        let x = Int(floor(pos0.x)), z = Int(floor(pos0.z))
        _ = g.world.loadSync(center: pos0, radius: 3)
        let top = g.world.topY(x, z)
        let h = Mob(.horse, at: V3(Float(x) + 20.5, Float(top + 1), Float(z) + 0.5))
        h.owner = true; h.bond = 77; h.customName = "Ginger"
        g.mobs.mobs = [h]; g.horseBond = 77
        g.player.pos = V3(Float(x) + 0.5, Float(top - 20), Float(z) + 0.5)
        g.horseCall = 0
        let answered = g.callHorse()
        let below = g.horseCall == 0
        g.player.pos = V3(Float(x) + 0.5, Float(top + 1), Float(z) + 0.5)
        _ = g.callHorse()
        let above = g.horseCall > 0
        check(answered && below && above, "P117 horse call: from underground Ginger stays put \(below); on the surface she comes \(above)")
    }

    // P118: a pick in gravel sounds like pebbles knocking, not water: its envelope is spiky (sparse grains) where a
    // splash is a smooth hiss.
    static func p118(_ g: Game, _ check: (Bool, String) -> Void) {
        // The share of the sound's energy in its loudest tenth of 1 ms windows: knocks and clicks are near 1, a hiss low.
        func spiky(_ s: Snd) -> Float {
            var syn = Synth(seed: 7)
            let a = syn.render(s, pitch: 1)
            let win = Int(Synth.sr / 1000)
            var env: [Float] = []
            var i = 0
            while i + win <= a.count { var e: Float = 0; for k in i..<(i + win) { e += a[k] * a[k] }; env.append(e); i += win }
            let total = env.reduce(0, +)
            let top = env.sorted(by: >).prefix(max(1, env.count / 10)).reduce(0, +)
            return total > 0 ? top / total : 0
        }
        let gravel = spiky(.hit(.gravel)), splash = spiky(.splash), stone = spiky(.hit(.stone))
        check(gravel > 0.5 && gravel > splash * 1.3, String(format: "P118 gravel hit: energy in the loudest tenth %.2f (a splash %.2f, stone %.2f)", gravel, splash, stone))
    }

    // P116: the journal keeps messages and documents (not hotbar names or quick repeats), newest first, through a save,
    // and opens from the pause menu as a book.
    static func p116(_ g: Game, _ check: (Bool, String) -> Void) {
        let j0 = g.journal, menu0 = g.menu
        defer { g.journal = j0; if g.menu !== menu0 { g.closeMenu() } }
        g.journal = []
        g.onToast?("Bounty hunters are after the $50 on your head: 5 riding in from the north")
        g.onToast?(Items.def(Items.id("cobblestone")).display)
        g.onToast?("Bounty hunters are after the $50 on your head: 5 riding in from the north")
        g.onToast?("Your horse can't hear you down here")
        var doc = ItemStack(Items.id("written_book"), 1); doc.label = "Orders"; doc.pages = ["March on the ford at dawn."]
        g.openMenu(BookMenu(game: g, stack: doc, source: .hand(-1)))
        g.closeMenu()
        let kept = g.journal.map { $0.text }
        let saved = g.saveExtra()
        g.journal = []
        g.loadExtra(saved)
        let back = g.journal.map { $0.text } == kept
        let pages = g.journalPages
        g.openJournal()
        let opened = (g.menu as? BookMenu)?.title == "Journal"
        check(kept.count == 3 && kept.last?.hasPrefix("Orders: March") == true && back && pages.first?.contains("Orders") == true && opened,
              "P116 journal: \(kept.count) entries kept (\(kept.map { String($0.prefix(24)) })), through a save \(back), newest first, opens as a book \(opened)")
    }

    // P119: 30 loose Capital rounds and an iron nugget pack into a magazine in the crafting book (16 to a slot); a gun
    // loads from magazines (an opened one leaves its spare rounds loose); in the headset the reload button and the
    // empty-trigger reload are gone (the hip is the reload) and the prompts don't offer one.
    static func p119(_ g: Game, _ check: (Bool, String) -> Void) {
        let inv = g.inventory.main.slots, held0 = g.inventory.held, surv = g.survival, aim0 = g.vrAim
        defer { g.inventory.main.slots = inv; g.inventory.held = held0; g.survival = surv; g.vrAim = aim0; g.arms.reload = 0 }
        g.survival = true
        for i in 0..<g.inventory.main.count { g.inventory.main[i] = .empty }
        g.inventory.main[9] = ItemStack(Items.id("capital_rounds"), 64)
        g.inventory.main[10] = ItemStack(Items.id("iron_nugget"), 4)
        var gun = ItemStack(Items.id("gun_sidearm"), 1); gun.tag = 0
        g.inventory.held = gun
        guard let r = Recipes.all.first(where: { Items.key($0.result.item) == "capital_magazine" }) else { check(false, "P119: no magazine recipe"); return }
        let inBook = CraftingBookMenu.catalogue(3).values.contains { $0.contains { Recipes.all[$0].result.item == r.result.item } }
        let made = CraftBook.craft(r, times: 2, game: g)
        let mags = g.inventory.main.slots.filter { Items.key($0.item) == "capital_magazine" }.reduce(0) { $0 + $1.count }
        let loose = g.inventory.main.slots.filter { Items.key($0.item) == "capital_rounds" }.reduce(0) { $0 + $1.count }
        let packed = made == 2 && mags == 2 && loose == 4 && g.ammoCount("capital_rounds") == 64
        // Loading an 18-round sidearm from 4 loose rounds and the magazines: 4 loose, then one magazine opened (16 spare).
        g.loadMagazine(Guns.index(Items.id("gun_sidearm"))!)
        let mags2 = g.inventory.main.slots.filter { Items.key($0.item) == "capital_magazine" }.reduce(0) { $0 + $1.count }
        let loose2 = g.inventory.main.slots.filter { Items.key($0.item) == "capital_rounds" }.reduce(0) { $0 + $1.count }
        let tag = g.held.tag
        let loaded = tag == 18 && mags2 == 1 && loose2 == 16
        // The headset: no reload button, no empty-trigger reload, no "Reload" prompt.
        g.vrAim = (g.player.eye, g.player.look)
        g.inventory.held.tag = 0
        let none = PadSnapshot()
        var xPad = PadSnapshot(); xPad.x = true
        _ = g.gunInteract(xPad, none, fire: false, firePressed: false, aim: false, dt: 0.05)
        let noButton = g.arms.reload <= 0
        _ = g.gunInteract(none, none, fire: true, firePressed: true, aim: false, dt: 0.05)
        let noTrigger = g.arms.reload <= 0
        let prompts = ContextPrompts.items(g).joined(separator: " ")
        check(inBook && packed && loaded && noButton && noTrigger && !prompts.contains("Reload"),
              "P119 magazines: in the crafting book \(inBook); 64 rounds + nuggets -> \(mags) magazines and \(loose) loose; a sidearm loads \(tag) leaving \(mags2) magazine and \(loose2) loose; headset: no reload button \(noButton), no trigger reload \(noTrigger), prompts \"\(prompts)\"")
    }

    // P120: Capital rounds can be crafted (steel cases: a steel ingot, copper and two gunpowder make 12).
    static func p120(_ g: Game, _ check: (Bool, String) -> Void) {
        let r = Recipes.all.first { Items.key($0.result.item) == "capital_rounds" }
        let inBook = r.map { rr in CraftingBookMenu.catalogue(3).values.contains { $0.contains { Recipes.all[$0].result.item == rr.result.item } } } ?? false
        check(r != nil && inBook && r!.result.count == 12 && r!.shapeless.contains("steel_ingot"),
              "P120 Capital rounds: a recipe \(r != nil) in the crafting book \(inBook): \(r?.shapeless ?? []) -> \(r?.result.count ?? 0)")
    }

    // P121: a chunk drops rails over air and amethyst touching no solid block; a cluster on rock stays; a cluster whose
    // rock is mined out pops.
    static func p121(_ g: Game, _ check: (Bool, String) -> Void) {
        var b = [BlockID](repeating: AIR, count: CSQ * CH)
        let rail = Blocks.id("rail"), cl = Blocks.id("amethyst_cluster")
        b[Chunk.index(5, 300, 5)] = rail
        b[Chunk.index(5, 300, 9)] = rail; b[Chunk.index(5, 299, 9)] = STONE
        b[Chunk.index(8, 300, 8)] = cl
        b[Chunk.index(10, 300, 10)] = cl; b[Chunk.index(10, 301, 10)] = STONE
        let n = PlantSupport.dropFloating(&b)
        let gen = n == 2 && b[Chunk.index(5, 300, 5)] == AIR && b[Chunk.index(8, 300, 8)] == AIR
            && b[Chunk.index(5, 300, 9)] == rail && b[Chunk.index(10, 300, 10)] == cl
        check(gen && PlantSupport.ruleOf(cl) == 5, "P121 floating pieces: \(n) dropped (a rail over air, a lone cluster); a railed track and a cluster on rock stay \(gen)")
    }

    // P122: a block put under your feet in mid-jump lifts you onto it (when there is head room).
    static func p122(_ g: Game, _ check: (Bool, String) -> Void) {
        let pos0 = g.player.pos, fly0 = g.player.flying
        defer { g.player.pos = pos0; g.player.flying = fly0 }
        g.player.flying = false
        let c = IVec3(Int(floor(pos0.x)), 330, Int(floor(pos0.z)))
        g.player.pos = V3(Float(c.x) + 0.5, Float(c.y) + 0.6, Float(c.z) + 0.5)
        let lifted = g.liftOnto(c) && abs(g.player.pos.y - Float(c.y + 1)) < 0.01 && !g.player.intersectsBlock(c)
        g.world.setBlock(c.x, c.y + 2, c.z, STONE)
        g.player.pos = V3(Float(c.x) + 0.5, Float(c.y) + 0.6, Float(c.z) + 0.5)
        let blocked = !g.liftOnto(c)
        g.world.setBlock(c.x, c.y + 2, c.z, AIR)
        check(lifted && blocked, "P122 placing in a jump: lifted onto the block \(lifted); not with a block over the head \(blocked)")
    }

    // P123: the armour bars left of the hotbar carry their pieces' icons and an "Armour" heading.
    static func p123(_ g: Game, _ check: (Bool, String) -> Void) {
        let arm = g.inventory.armor.slots, surv = g.survival
        defer { g.inventory.armor.slots = arm; g.survival = surv }
        g.survival = true
        for (i, k) in ["iron_boots", "iron_leggings", "iron_chestplate", "iron_helmet"].enumerated() { g.inventory.armor[i] = ItemStack(Items.id(k), 1) }
        let L = HudLayout(1280, 800)
        let lines = CombatHUD.shared.lines(g, L)
        let icons = lines.filter { $0.item.map { $0.def.durability > 0 } ?? false }.count
        let head = lines.contains { $0.text == "Armour" }
        check(icons == 4 && head, "P123 armour bars: \(icons) piece icons beside the bars, headed \"Armour\" \(head)")
    }
}
