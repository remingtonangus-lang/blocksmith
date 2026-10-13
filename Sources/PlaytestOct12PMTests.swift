import Foundation
import simd
import Metal

// The Oct 12 afternoon playtest fixes (backlog P107-P139), `questcheck --p12pm-only [P1xx]`: one check per item.
enum PlaytestOct12PMTests {
    static func run(_ g: Game, only: String?, check: (Bool, String) -> Void) {
        let all: [(String, (Game, (Bool, String) -> Void) -> Void)] = [
            ("P107", p107), ("P108", p108), ("P109", p109), ("P110", p110), ("P111", p111), ("P112", p112), ("P114", p114), ("P115", p115), ("P116", p116), ("P117", p117), ("P118", p118), ("P119", p119), ("P120", p120), ("P121", p121), ("P122", p122), ("P123", p123), ("P124", p124), ("P125", p125), ("P126", p126), ("P127", p127), ("P128", p128), ("P129", p129), ("P130", p130), ("P131", p131), ("P132", p132), ("P133", p133), ("P134", p134), ("P135", p135), ("P136", p136), ("P137", p137), ("P138", p138), ("P139", p139),
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

    // P124: no frame-thread freeze walking new ground in a saved survival world: every tick timed for a walk and a
    // stand (autosaves included); the slowest ticks listed with their stages.
    static func p124(_ g: Game, _ check: (Bool, String) -> Void) {
        // The structure cache no longer empties at once when full: the starts in use round the player stay made.
        let gen = WorldGen(seed: 77)
        var kept = false, wiped = false
        if let sc = gen.structures, let vt = sc.types.first(where: { $0.name == "village" }) {
            let cap0 = StructureCache.cap
            StructureCache.cap = 300
            defer { StructureCache.cap = cap0 }
            _ = sc.start(vt, regionX: 0, regionZ: 0)
            kept = true
            for i in 0..<1200 {
                _ = sc.start(vt, regionX: 1000 + i % 40, regionZ: i / 40)
                if i % 25 == 0 { _ = sc.start(vt, regionX: 0, regionZ: 0) }        // the frame thread asking each second
                if !sc.isCached(vt, regionX: 0, regionZ: 0) { kept = false }
            }
            wiped = !sc.isCached(vt, regionX: 1000 + 1199 % 40, regionZ: 1199 / 40)
        }
        check(kept && !wiped && StructureCache.evictions > 0, "P124 structure cache: the start in use stays made through \(StructureCache.evictions) evictions \(kept); the newest kept \(!wiped)")
        // The Greywall base scan (the 620 ms tick the walk caught): the same finds, chunk by chunk, in a few ms.
        if let sc = g.world.gen.structures, let s = sc.nearest(Greywall.kind, x: Int(g.player.pos.x), z: Int(g.player.pos.z), maxRegions: 4) {
            let (cx, cz) = Greywall.centre(s)
            let pos0 = g.player.pos
            defer { g.player.pos = pos0 }
            let tier = Greywall.Tier.of(s)
            _ = g.world.loadSync(center: V3(Float(cx), 100, Float(cz)), radius: tier.half / CS + 2)
            var a = GreywallAlarmState.Site(cx: cx, cz: cz, S: Greywall.yardY(s), tier: tier), b = a
            let t0 = CFAbsoluteTimeGetCurrent()
            let okOld = Greywall.scanOld(g.world, &a)
            let t1 = CFAbsoluteTimeGetCurrent()
            let okNew = Greywall.scan(g.world, &b)
            let t2 = CFAbsoluteTimeGetCurrent()
            func set(_ l: [IVec3]) -> Set<IVec3> { Set(l) }
            let same = set(a.lamps) == set(b.lamps) && set(a.panels) == set(b.panels) && set(a.consoles) == set(b.consoles)
                && set(a.turrets) == set(b.turrets) && set(a.flags) == set(b.flags)
            check(okOld && okNew && same && !b.lamps.isEmpty && (t2 - t1) < (t1 - t0),
                  String(format: "P124 Greywall scan: %d lamps, %d panels, %d turrets found alike %@; %.1f ms (was %.1f ms)", b.lamps.count, b.panels.count, b.turrets.count,
                         "\(same)", (t2 - t1) * 1000, (t1 - t0) * 1000))
        } else { check(false, "P124: no Greywall base near the test spawn") }
        let r = HitchProbe.run(device: g.world.device, seed: 1012, walk: 150, stand: 75, speed: 14)
        for s in r.slow.prefix(12) { print(String(format: "  P124 slow tick %.1f ms at %.1f s: %@", s.ms, s.at, s.stages)) }
        let worst = r.slow.first?.ms ?? 0
        check(worst < 250 && r.save < 30 && StructureCache.offThreadPlans > 0,
              String(format: "P124 hitches: %d ticks, %d over 40 ms, worst %.0f ms (%@); autosave on the frame thread %.1f ms; %d base-site starts planned on a worker",
                     r.ticks, r.slow.count, worst, r.slow.first?.stages ?? "-", r.save, StructureCache.offThreadPlans))
    }

    // P125: the lanternvine. Generated vines carry glowing pods on their tips and some segments (lit), plain strands give
    // no light; using a pod picks Lumen Pods and the strand regrows them.
    static func p125(_ g: Game, _ check: (Bool, String) -> Void) {
        let base = Blocks.id("cave_vines"), pod = base + 1
        var plain = 0, podded = 0, tipsLit = 0, tips = 0
        let gen = WorldGen(seed: 4242)
        var k = 0
        while (plain + podded) < 60 && k < 120 {
            let b = gen.generate(cx: (k % 12) * 5 - 30, cz: (k / 12) * 5 - 25); k += 1
            for i in CSQ..<(b.count - CSQ) where Blocks.groupBase[Int(b[i])] == base {
                if b[i] == pod { podded += 1 } else { plain += 1 }
                if Blocks.groupBase[Int(b[i - CSQ])] != base { tips += 1; if b[i] == pod { tipsLit += 1 } }
            }
        }
        let light = Blocks.emit[Int(pod)] == 12 && Blocks.emit[Int(base)] == 0
        let w = g.world
        let c = IVec3(Int(floor(g.player.pos.x)) + 3, 330, Int(floor(g.player.pos.z)))
        let held0 = g.inventory.main.slots
        defer { g.inventory.main.slots = held0; w.setBlock(c.x, c.y, c.z, AIR); w.setBlock(c.x, c.y + 1, c.z, AIR) }
        w.setBlock(c.x, c.y + 1, c.z, STONE); w.setBlock(c.x, c.y, c.z, pod)
        let before = g.inventory.main.countOf(Items.id("glow_berries"))
        g.pickLumenPods(c)
        let picked = w.block(c.x, c.y, c.z) == base && g.inventory.main.countOf(Items.id("glow_berries")) == before + 1
        var regrew = false
        for _ in 0..<300 where !regrew { g.randomTick(c, w.block(c.x, c.y, c.z)); regrew = w.block(c.x, c.y, c.z) == pod }
        let name = Items.def(Items.id("glow_berries")).display
        check(podded > 0 && plain > 0 && tips > 0 && tipsLit == tips && light && picked && regrew && name == "Lumen Pods",
              "P125 lanternvine: \(podded) podded and \(plain) plain segments over \(k) chunks, \(tipsLit) of \(tips) tips lit; light \(light); picked \(picked) (\(name)); regrows \(regrew)")
    }

    // P126: sneaking never walks off a ledge: a diagonal walk off a single block's corner (each axis alone kept a toe on
    // it), and a roomscale step, both stop at the edge; without sneaking the same walk falls.
    static func p126(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, pl = g.player
        let pos0 = pl.pos, yaw0 = pl.yaw, pitch0 = pl.pitch, fly0 = pl.flying, surv0 = g.survival
        let c = IVec3(Int(floor(pos0.x)) + 6, 330, Int(floor(pos0.z)) + 6)
        defer {
            w.setBlock(c.x, c.y, c.z, AIR); g.input.keys.removeAll(); g.input.shift = false
            pl.pos = pos0; pl.yaw = yaw0; pl.pitch = pitch0; pl.flying = fly0; g.survival = surv0; pl.vel = .zero
        }
        w.setBlock(c.x, c.y, c.z, STONE)
        func walk(sneak: Bool) -> Float {
            pl.pos = V3(Float(c.x) + 0.5, Float(c.y + 1), Float(c.z) + 0.5); pl.vel = .zero; pl.flying = false
            pl.yaw = -.pi / 4 - .pi / 2          // toward +x +z (forward = (-sin, 0, -cos))
            g.survival = true
            g.input.keys = [KeyBinds.key(.forward)]; g.input.shift = sneak
            for _ in 0..<180 { g.tick(1.0 / 60) }
            g.input.keys.removeAll(); g.input.shift = false
            return pl.pos.y
        }
        let kept = walk(sneak: true) > Float(c.y + 1) - 0.01
        let fell = walk(sneak: false) < Float(c.y)
        pl.pos = V3(Float(c.x) + 0.5, Float(c.y + 1), Float(c.z) + 0.5); pl.vel = .zero; pl.onGround = true
        let d = pl.edgeClamp(V3(0.7, 0, -0.7), w)
        let room = !pl.collides(at: pl.pos + d + V3(0, -0.06, 0), w) ? false : true
        check(kept && fell && room && simd_length(d) > 0.2,
              String(format: "P126 sneaking at an edge: a diagonal walk stays on the block %@ (without sneaking it falls %@); a roomscale step is cut to %.2f and still stands %@", "\(kept)", "\(fell)", simd_length(d), "\(room)"))
    }

    // P127: beds work from sunset; a furnace catches up the time slept through (or spent away) when it next runs.
    static func p127(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let c = IVec3(Int(floor(g.player.pos.x)) - 6, 330, Int(floor(g.player.pos.z)) - 6)
        let time0 = g.time, sleep0 = g.sleeping, spawn0 = g.spawnPoint, toast0 = g.onToast
        var toasts: [String] = []
        g.onToast = { toasts.append($0) }
        defer {
            g.time = time0; g.sleeping = sleep0; g.spawnPoint = spawn0; g.onToast = toast0
            w.blockEntities[c] = nil; w.setBlock(c.x, c.y, c.z, AIR)
        }
        let day = floor(g.time / DAY_LENGTH) * DAY_LENGTH
        g.time = day + DAY_LENGTH * 0.3; g.sleeping = 0
        g.trySleep(at: c)
        let refused = g.sleeping == 0 && toasts.contains { $0.contains("dusk") }
        g.time = day + DAY_LENGTH * 0.505                  // 18:07, the sun just down
        g.trySleep(at: c)
        let slept = g.sleeping > 0
        g.sleeping = 0
        // Furnace: 8 raw iron, 1 coal (8 items' worth); 10 minutes skipped.
        w.setBlock(c.x, c.y, c.z, Blocks.id("furnace"))
        let be = w.entity(c, .furnace)
        w.blockEntities[c] = be
        be.container[0] = ItemStack(Items.id("raw_iron"), 8)
        be.container[1] = ItemStack(Items.id("coal"), 1)
        g.tick(0.05); g.tick(0.05)
        g.time += 600
        g.tick(0.05); g.tick(0.05)
        let out = be.container[2]
        let done = Items.key(out.item) == "iron_ingot" && out.count == 8 && be.container[0].isEmpty
        var kept = false
        if let d = try? JSONEncoder().encode(be), let back = try? JSONDecoder().decode(BlockEntity.self, from: d) { kept = abs(back.last - be.last) < 1e-6 && back.last > 0 }
        check(refused && slept && done && kept,
              "P127 sleep and timed work: refused in the afternoon with a hint \(refused); allowed at 18:07 \(slept); a furnace left 10 minutes smelted \(out.count) iron \(done); its clock kept through a save \(kept)")
    }

    // P128: a double door opens outward to both posts, so the middle of the doorway is clear, whichever door opens first.
    static func p128(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let c = IVec3(Int(floor(g.player.pos.x)) + 10, 330, Int(floor(g.player.pos.z)) - 10)
        let door = Blocks.id("oak_door")
        var cells: [IVec3] = []
        defer { for p in cells { w.setBlock(p.x, p.y, p.z, AIR) } }
        var results: [Bool] = []
        for order in [[0, 1], [1, 0]] {
            for dx in -1...2 { w.setBlock(c.x + dx, c.y - 1, c.z, STONE); cells.append(IVec3(c.x + dx, c.y - 1, c.z)) }
            for dx in 0...1 {
                w.setBlock(c.x + dx, c.y, c.z, door); w.setBlock(c.x + dx, c.y + 1, c.z, door + 8)
                cells += [IVec3(c.x + dx, c.y, c.z), IVec3(c.x + dx, c.y + 1, c.z)]
            }
            for dx in order { g.toggleOpenable(IVec3(c.x + dx, c.y, c.z)) }
            let seam = Float(c.x + 1)
            let clear = !w.collides(V3(seam - 0.45, Float(c.y), Float(c.z) - 0.5), V3(seam + 0.45, Float(c.y) + 1.8, Float(c.z) + 1.5))
            let open = (0...1).allSatisfy { Int(w.block(c.x + $0, c.y, c.z) - door) & 4 != 0 && Int(w.block(c.x + $0, c.y + 1, c.z) - door) & 4 != 0 }
            results.append(clear && open)
            for dx in 0...1 { g.toggleOpenable(IVec3(c.x + dx, c.y, c.z)) }
        }
        let shut = (0...1).allSatisfy { Int(w.block(c.x + $0, c.y, c.z) - door) & 4 == 0 }
        check(results == [true, true] && shut, "P128 double door: the middle 0.9 blocks clear once open (left first \(results[0]), right first \(results[1])); both close again \(shut)")
    }

    // P129: the crafting book doesn't craft by accident: a grip / right click on a tile only selects it, a click in the
    // first moment after it opens does nothing, and in the headset holding A over a tile crafts nothing.
    static func p129(_ g: Game, _ check: (Bool, String) -> Void) {
        let inv0 = g.inventory.main.slots, menu0 = g.menu, head0 = g.vrHead, clock0 = g.clock
        defer { g.inventory.main.slots = inv0; g.menu = menu0; g.vrHead = head0; g.clock = clock0 }
        for i in 0..<g.inventory.main.slots.count { g.inventory.main[i] = .empty }
        g.inventory.main[0] = ItemStack(Items.id("oak_planks"), 24)
        let m = CraftingBookMenu(game: g)
        g.openMenu(m)
        m.query = "oak stairs"; m.refresh()
        let stairs = Items.id("oak_stairs")
        guard let k = (0..<CraftingBookMenu.perPage).first(where: { m.recipe(at: $0).map { Recipes.all[$0].result.item == stairs } ?? false }) else {
            check(false, "P129: no oak stairs tile"); return
        }
        let tile = m.slots[CraftCategory.allCases.count + k]
        func made() -> Int { g.inventory.main.countOf(stairs) }
        m.mouseClick = true; m.click(tile, button: 0, shift: false); m.mouseClick = false
        let early = made()
        g.clock += 1
        m.mouseClick = true; m.click(tile, button: 1, shift: false); m.mouseClick = false
        let grip = made()
        g.vrHead = V3(0, 0, 0)
        g.menuHover = tile
        for _ in 0..<120 { m.padHold(true, 1.0 / 60) }
        let held = made()
        m.mouseClick = true; m.click(tile, button: 0, shift: false); m.mouseClick = false
        let one = made()
        check(early == 0 && grip == 0 && held == 0 && one == 4 && m.selected != nil,
              "P129 crafting book: a click as it opens made \(early); a grip / right click made \(grip) (selects); A held 2 s in the headset made \(held); a trigger click made \(one) stairs")
    }

    // P130: steady digging. A titanium shovel through a row of sand breaks one block every pause + break time, evenly,
    // with no chips on blocks that go that fast.
    static func p130(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, pl = g.player
        let pos0 = pl.pos, yaw0 = pl.yaw, pitch0 = pl.pitch, fly0 = pl.flying, surv0 = g.survival, inv0 = g.inventory.main.slots, sel0 = g.inventory.selected
        let c = IVec3(Int(floor(pos0.x)) - 12, 330, Int(floor(pos0.z)) + 12)
        var cells: [IVec3] = []
        defer {
            for p in cells { w.setBlock(p.x, p.y, p.z, AIR) }
            pl.pos = pos0; pl.yaw = yaw0; pl.pitch = pitch0; pl.flying = fly0; g.survival = surv0; g.inventory.main.slots = inv0; g.inventory.selected = sel0
            g.input.leftDown = false
        }
        for dz in -1...7 { for dx in -1...1 { w.setBlock(c.x + dx, c.y - 1, c.z - dz, STONE); cells.append(IVec3(c.x + dx, c.y - 1, c.z - dz)) } }
        for dz in 1...5 { for dy in 0...1 { w.setBlock(c.x, c.y + dy, c.z - dz, SAND); cells.append(IVec3(c.x, c.y + dy, c.z - dz)) } }
        g.inventory.selected = 0
        g.inventory.main[0] = ItemStack(Items.id("diamond_shovel"), 1)
        g.survival = true; pl.flying = false
        pl.pos = V3(Float(c.x) + 0.5, Float(c.y), Float(c.z) + 0.5); pl.vel = .zero
        pl.yaw = 0; pl.pitch = -0.08                     // forward is -z, aiming at the upper row
        func upper() -> Int { (1...5).filter { w.block(c.x, c.y + 1, c.z - $0) == SAND }.count }
        var times: [Double] = [], chipped = 0
        var left = upper(), t = 0.0
        g.input.leftDown = true
        while t < 3 && left > 0 {
            pl.pos = V3(Float(c.x) + 0.5, Float(c.y), Float(c.z) + 0.5); pl.yaw = 0; pl.pitch = -0.08
            g.tick(1.0 / 72); t += 1.0 / 72
            for dz in 1...5 where w.damageLevel(IVec3(c.x, c.y + 1, c.z - dz)) > 0 { chipped += 1 }
            let n = upper()
            if n < left { times.append(t); left = n }
        }
        g.input.leftDown = false
        let gaps = zip(times.dropFirst(), times).map { $0 - $1 }
        let mean = gaps.isEmpty ? 0 : gaps.reduce(0, +) / Double(gaps.count)
        let spread = gaps.map { abs($0 - mean) }.max() ?? 1
        check(times.count == 5 && spread <= 2.0 / 72 && mean >= MineSteady.pause && chipped == 0,
              String(format: "P130 shovel through sand: %d blocks, a break every %.3f s (spread %.3f s), chipped frames %d", times.count, mean, spread, chipped))
    }

    // P131: a way home. With the bed far off, the minimap holds a house marker on its edge toward it, a line gives the
    // distance and heading, and the world map names it; near home without a compass the line goes away.
    static func p131(_ g: Game, _ check: (Bool, String) -> Void) {
        let sp0 = g.spawnPoint, mm0 = Settings.shared.minimap, en0 = HudExtras.enabled, menu0 = g.menu, held0 = g.inventory.held
        defer { g.spawnPoint = sp0; Settings.shared.minimap = mm0; HudExtras.enabled = en0; g.menu = menu0; g.inventory.held = held0 }
        Settings.shared.minimap = true; HudExtras.enabled = true; g.menu = nil
        g.inventory.held = .empty
        let p = g.player.pos
        g.spawnPoint = V3(floorf(p.x) - 400 + 0.5, floorf(p.y) + 0.6, floorf(p.z) - 400 + 0.5)       // a bed 566 blocks NW
        let line = HomeFinder.line(g) ?? "-"
        let L = HudLayout(1280, 800)
        let lines = Minimap.lines(g, L)
        let marker = lines.first { $0.text == "H" }
        let box = lines.first.map { ($0.x, $0.y, $0.box?.x ?? 0) }
        var onEdge = false
        if let m = marker, let b = box { onEdge = m.x < b.0 + 8 * L.s && m.y < b.1 + 8 * L.s }      // the top-left corner: north-west
        let shown = lines.contains { $0.text == line }
        g.spawnPoint = V3(floorf(p.x) + 20.5, floorf(p.y) + 0.6, floorf(p.z) + 0.5)
        let nearHidden = HomeFinder.line(g) == nil
        g.inventory.held = ItemStack(Items.id("compass"), 1)
        let compass = HomeFinder.line(g)?.hasPrefix("Home 20 E") ?? false
        check(line.hasPrefix("Home 56") && line.hasSuffix("NW") && shown && onEdge && nearHidden && compass,
              "P131 home finder: \"\(line)\" under the minimap \(shown); the house marker on the minimap's north-west edge \(onEdge); near home hidden \(nearHidden), with a compass \(compass)")
    }

    static func p132(_ g: Game, _ check: (Bool, String) -> Void) {
        let pos0 = g.player.pos, yaw0 = g.player.yaw, held0 = g.inventory.held, surv0 = g.survival, money0 = g.money
        let marks0 = MapCache.shared.marks, menu0 = g.menu, time0 = g.time
        defer {
            g.riding = nil; g.player.pos = pos0; g.player.yaw = yaw0; g.inventory.held = held0; g.survival = surv0; g.money = money0
            MapCache.shared.replaceMarks(marks0); g.menu = menu0; g.time = time0; g.riderPush = 0
        }
        let w = g.world
        g.survival = true
        // The engine cart: an item, a recipe, fuel.
        let recipe = Recipes.match(["minecart", "furnace", "piston", "copper_ingot", "", "", "", "", ""].map { $0.isEmpty ? ItemID(0) : Items.id($0) }, 3, 3)
        let crafted = recipe.map { Items.key($0.result.item) } ?? "-"
        // A straight test line in the air: stone and rails along +x.
        let x0 = Int(floor(pos0.x)) - 40, y0 = 300, z0 = Int(floor(pos0.z))
        _ = w.loadSync(center: V3(Float(x0 + 40), Float(y0), Float(z0)), radius: 5)
        for x in x0..<(x0 + 90) {
            w.setBlock(x, y0, z0, STONE)
            w.setBlock(x, y0 + 1, z0, x < x0 + 80 ? Blocks.id("rail") : AIR)
            for h in 2...4 { w.setBlock(x, y0 + h, z0, AIR) }
        }
        for x in x0..<(x0 + 80) { Rails.autoShape(w, IVec3(x, y0 + 1, z0), recurse: false) }
        func run(fuel: Bool) -> (Float, Float, Float) {
            let cart = Mob(.minecart, at: V3(Float(x0) + 2.5, Float(y0 + 1) + 0.0625, Float(z0) + 0.5))
            cart.variant = Carts.engine; cart.jobTimer = 0; cart.vel = .zero
            g.inventory.held = ItemStack(Items.id("coal"), 4)
            var used = false
            if fuel { used = g.useCart(cart) }
            let f0 = cart.jobTimer
            g.inventory.held = .empty
            g.riding = cart
            g.player.yaw = -Float.pi / 2                                    // facing +x
            var top: Float = 0
            for _ in 0..<80 { g.riderPush = 1; cart.updateMinecart(0.05, g); top = max(top, simd_length(cart.vel)) }
            g.riding = nil
            return (used ? f0 : -1, top, cart.jobTimer)
        }
        let (fuel0, fast, left) = run(fuel: true)
        let (_, slow, _) = run(fuel: false)
        check(crafted == "engine_cart" && Items.has("engine_cart") && fuel0 >= 119 && fast > 11 && fast <= Carts.engineTop + 0.01
              && left < fuel0 && slow < 8.5,
              String(format: "P132 engine cart: crafted %@; coal gives %.0f s of fuel; driven 4 s it reaches %.1f blocks/s (fuel left %.0f s); with no fuel only %.1f", crafted, fuel0, fast, left, slow))

        // Laying track from the cart: a rail goes down past the end of the line.
        let end = x0 + 80
        let cart = Mob(.minecart, at: V3(Float(end) - 0.5, Float(y0 + 1) + 0.0625, Float(z0) + 0.5))
        cart.vel = V3(2, 0, 0)
        g.riding = cart
        g.inventory.held = ItemStack(Items.id("rail"), 8)
        let laid0 = CartTrack.laid
        g.cartLayTrack(cart, use: true)
        g.cartLayTrack(cart, use: true)                                     // the next one waits for the cart to roll on
        let laidRail = Rails.isRail(w.block(end, y0 + 1, z0)) && CartTrack.laid == laid0 + 1
        let spent = g.inventory.held.count == 7
        g.inventory.held = .empty
        g.cartLayTrack(cart, use: true)
        g.riding = nil
        check(laidRail && spent && CartTrack.laid == laid0 + 1,
              "P132 track laying: riding with rails in hand lays the next rail ahead \(laidRail), one rail spent \(spent); without rails nothing")

        // The network: a found station on another line is sold from this line's ticket office.
        var net = "no two lines with stations near spawn"
        var ok = false
        if let gen = w.gen as? WorldGen {
            let px = Int(pos0.x), pz = Int(pos0.z)
            let lines = Railways.near(gen, x0: px - 6000, z0: pz - 6000, x1: px + 6000, z1: pz + 6000, pad: 0).filter { !$0.stations.isEmpty }
            if lines.count >= 2, let a = lines.first {
                let b = lines[1], far = b.stations[0]
                MapCache.shared.replaceMarks([MapCache.Mark(kind: "station", x: far.x, z: far.z, name: "\(far.name) Station")])
                let menu = TicketMenu(game: g, line: a, from: a.stations[0])
                let rows = menu.rows
                g.money = 1_000_000
                let m0 = g.money
                menu.pressed(rows.count - 1)
                let c = b.cells[far.index]
                let arrived = abs(g.player.pos.x - Float(c.x)) < 4 && abs(g.player.pos.z - Float(c.z)) < 5
                let paid = m0 - g.money
                ok = rows.count == a.stations.count && arrived && paid == Trains.networkFare(Trains.crowFlies(a.stations[0], MapCache.shared.marks[0]))
                net = "from \(a.stations[0].name) on the \(a.name): \(rows.count) tickets (\(rows.last?.name ?? "-") \(rows.last?.value ?? "")); arrived \(arrived), paid \(Money.format(paid))"
            }
        }
        check(ok, "P132 network: \(net)")

        // The mine: each level's two drifts join round the shaft on rails.
        var linked = "no mining town near spawn"
        var lok = false
        if let sc = w.gen.structures, let vt = sc.types.first(where: { $0.name == "village" }) {
            let rx0 = floorDiv(floorDiv(Int(pos0.x), CS), vt.spacing), rz0 = floorDiv(floorDiv(Int(pos0.z), CS), vt.spacing)
            var mine: Mine? = nil
            for rz in (rz0 - 3)...(rz0 + 3) { for rx in (rx0 - 3)...(rx0 + 3) where mine == nil {
                if let m = sc.start(vt, regionX: rx, regionZ: rz)?.plan as? Mine { mine = m }
            } }
            if let m = mine {
                g.player.pos = V3(Float(m.shaft.x) + 0.5, Float(m.shaft.y + 1), Float(m.shaft.z) + 0.5)
                _ = w.loadSync(center: g.player.pos, radius: 4)
                var rails = 0, cells = 0
                for (a, b) in [(m.drifts[0], m.drifts[1]), (m.drifts[2], m.drifts[3])] {
                    for c in MiningTowns.link(a, b) { cells += 1; if Rails.isRail(w.block(c.x, c.y, c.z)) { rails += 1 } }
                }
                lok = rails == cells
                linked = "\(rails) of \(cells) link cells railed"
            }
        }
        check(lok, "P132 mine links: \(linked)")
    }


    static func p133(_ g: Game, _ check: (Bool, String) -> Void) {
        // Supply chests carry sundries now and then; the barrels' own table is mostly sundries with rations kept.
        func sample(_ table: String, _ n: Int) -> (Int, Int, Int) {
            var withSundry = 0, sundries = 0, food = 0
            for k in 0..<n {
                let c = ItemContainer(27)
                var rng = SRng(UInt64(9000 + k * 7919))
                Loot.fill(c, table: table, rng: &rng)
                let keys = c.slots.filter { !$0.isEmpty }.map { Items.key($0.item) }
                let s = keys.filter { BaseSundries.keys.contains($0) }.count
                if s > 0 { withSundry += 1 }
                sundries += s
                food += keys.filter { $0 == "capital_ration" || $0 == "baked_potato" }.count
            }
            return (withSundry, sundries, food)
        }
        let supply = BaseSundries.supplyTables.map { sample($0, 40).0 }
        let barrel = sample("base_sundries", 40)
        // Barrels in a built base hold them.
        var barrels = 0, filled = 0, kinds = Set<String>()
        let barrelID = Blocks.id("barrel")
        for cz in -3...2 { for cx in -3...2 {
            var b = [BlockID](repeating: STONE, count: CS * CS * CH)
            for i in (CS * CS * 200)..<(CS * CS * CH) { b[i] = AIR }
            b.withUnsafeMutableBufferPointer { buf in
                var w = StructWriter(bx: cx * CS, bz: cz * CS, blocks: buf.baseAddress!)
                BorealStation.build(&w, 0, 200, 0, 77)
                for (p, be) in w.entities where buf[Chunk.index(p.x - cx * CS, p.y, p.z - cz * CS)] == barrelID {
                    barrels += 1
                    let keys = be.container.slots.filter { !$0.isEmpty }.map { Items.key($0.item) }
                    if !keys.isEmpty { filled += 1 }
                    kinds.formUnion(keys.filter { BaseSundries.keys.contains($0) })
                }
            }
        } }
        let held0 = g.inventory.held
        var toasts: [String] = []
        let t0 = g.onToast
        g.onToast = { toasts.append($0) }
        g.inventory.held = ItemStack(Items.id("rubber_stamp"), 1)
        let used = g.sundryUse()
        g.onToast = t0; g.inventory.held = held0
        let worth = (Economy.value["rubber_stamp"] ?? 0) > 0 && (Economy.value["rubber_stamp"] ?? 0) < 10
        check(supply.allSatisfy { $0 >= 12 && $0 <= 34 } && barrel.0 >= 34 && barrel.2 >= 10 && barrels >= 6 && filled * 10 >= barrels * 9 && kinds.count >= 5
              && used && toasts.first?.contains("APPROVED") == true && worth,
              "P133 base sundries: supply chests with some \(supply) of 40; barrels \(barrel.0) of 40 with sundries (\(barrel.1) sundries, \(barrel.2) rations or potatoes); a built station's barrels \(filled) of \(barrels) filled, \(kinds.count) kinds; using one reads \"\(toasts.first ?? "-")\"; worth a few cents \(worth)")
    }


    static func p134(_ g: Game, _ check: (Bool, String) -> Void) {
        let was = MobVary.on
        MobVary.on = true
        let zs = (0..<300).map { _ in Mob(.zombie, at: g.player.pos).vary }
        MobVary.on = was
        let runners = zs.filter { $0.build == .runner }.count, brutes = zs.filter { $0.build == .brute }.count
        let sp = zs.map { $0.speed }, dm = zs.map { $0.damage }
        let spread = sp.max()! / sp.min()!, hit = dm.max()! / dm.min()!
        let fastWeak = zs.filter { $0.build == .runner }.allSatisfy { $0.speed > 1.3 && $0.damage < 0.85 }
        let slowHard = zs.filter { $0.build == .brute }.allSatisfy { $0.speed < 0.85 && $0.damage > 1.35 }
        check(runners >= 40 && runners <= 85 && brutes >= 40 && brutes <= 85 && spread > 2.3 && hit > 3.2 && fastWeak && slowHard,
              String(format: "P134 mob builds: of 300 zombies %d runners and %d brutes; speed x%.2f-%.2f (%.1f times), hits x%.2f-%.2f (%.1f times)", runners, brutes, sp.min()!, sp.max()!, spread, dm.min()!, dm.max()!, hit))

        // A Powderwight on your trail runs (a sky platform, 14 blocks off).
        let pos0 = g.player.pos, surv0 = g.survival, alive0 = g.alive, diff0 = g.difficulty, mobs0 = g.mobs.mobs, flying0 = g.player.flying
        defer { g.player.pos = pos0; g.survival = surv0; g.alive = alive0; g.difficulty = diff0; g.mobs.mobs = mobs0; g.player.flying = flying0 }
        let w = g.world
        let x0 = Int(floor(pos0.x)), z0 = Int(floor(pos0.z)), y0 = 320
        _ = w.loadSync(center: V3(Float(x0 + 10), Float(y0), Float(z0)), radius: 3)
        for x in (x0 - 2)...(x0 + 24) { for z in (z0 - 2)...(z0 + 2) {
            w.setBlock(x, y0, z, STONE)
            for h in 1...3 { w.setBlock(x, y0 + h, z, AIR) }
        } }
        g.survival = true; g.alive = true; g.difficulty = 2; g.player.flying = false
        g.player.pos = V3(Float(x0) + 0.5, Float(y0 + 1), Float(z0) + 0.5)
        let m = Mob(.creeper, at: V3(Float(x0 + 14) + 0.5, Float(y0 + 1), Float(z0) + 0.5))
        g.mobs.mobs = [m]
        for _ in 0..<10 { m.update(0.05, game: g) }
        let a = m.pos
        for _ in 0..<20 { m.update(0.05, game: g) }
        let v = simd_length(V2(m.pos.x - a.x, m.pos.z - a.z)) / 1.0
        check(v > 3.6, String(format: "P134 Powderwight run: %.1f blocks a second toward you (walking pace was %.1f)", v, m.spec.speed))
    }


    static func p135(_ g: Game, _ check: (Bool, String) -> Void) {
        let pos0 = g.player.pos, surv0 = g.survival, alive0 = g.alive, diff0 = g.difficulty, hp0 = g.health, flying0 = g.player.flying
        let slugs0 = g.arms.slugs
        defer { g.player.pos = pos0; g.survival = surv0; g.alive = alive0; g.difficulty = diff0; g.health = hp0; g.player.flying = flying0; g.arms.slugs = slugs0 }
        let w = g.world
        let x0 = Int(floor(pos0.x)), z0 = Int(floor(pos0.z)), y0 = 330
        _ = w.loadSync(center: V3(Float(x0), Float(y0), Float(z0 + 20)), radius: 4)
        for x in (x0 - 3)...(x0 + 3) { for z in (z0 - 3)...(z0 + 3) {
            w.setBlock(x, y0, z, STONE)
            for h in 1...3 { w.setBlock(x, y0 + h, z, AIR) }
        } }
        g.survival = true; g.alive = true; g.difficulty = 2; g.player.flying = false; g.health = 20
        g.player.pos = V3(Float(x0) + 0.5, Float(y0 + 1), Float(z0) + 0.5)
        g.arms.slugs = []
        // A launcher 50 blocks off: the missile climbs, turns and comes down on the player.
        let n0 = SmallMissiles.launched
        SmallMissiles.launch(g, from: g.player.pos + V3(0, 6, 50), at: g.player.pos, by: "test")
        var closest: Float = 999, turned = false, t: Float = 0
        while t < SmallMissiles.life + 0.2 && g.arms.slugs.contains(where: { !$0.dead }) {
            g.player.pos = V3(Float(x0) + 0.5, Float(y0 + 1), Float(z0) + 0.5); g.player.vel = .zero
            g.arms.update(0.05, g)
            if let m = g.arms.slugs.first(where: { !$0.dead }) {
                closest = min(closest, simd_length(m.pos - g.player.pos))
                if m.vel.z < -5 { turned = true }
            }
            g.arms.slugs.removeAll { $0.dead }
            t += 0.05
        }
        let hurt = g.health < 20
        check(SmallMissiles.launched == n0 + 1 && turned && closest < 3 && hurt && t < 5,
              String(format: "P135 small missile: launched 50 blocks off, turned toward the player %@, came within %.1f blocks in %.1f s, the player hurt %@ (health %.0f)",
                     turned ? "yes" : "no", closest, t, hurt ? "yes" : "no", Float(g.health)))
        // A citadel on alert fires its limited load, spaced out, and restocks while calm.
        g.health = 20
        var r = BaseRecord(key: "p135", cx: x0, cz: z0 + 70, y0: y0 - 40)
        w.setBlock(x0, y0 + 8, z0 + 70, STONE)                                              // the keep's top, level with the player
        r.alert = .lockdown
        let l0 = SmallMissiles.launched
        for _ in 0..<120 { g.baseMissiles(&r, 1); g.arms.slugs = [] }
        let fired = SmallMissiles.launched - l0
        r.alert = .calm
        for _ in 0..<70 { g.baseMissiles(&r, 10) }
        let restocked = r.missiles ?? -1
        g.player.pos = V3(Float(x0) + 0.5, Float(y0 + 1), Float(z0 + 60) + 0.5)          // too close: the guns' work
        r.alert = .lockdown; r.missileCD = 0
        let l1 = SmallMissiles.launched
        for _ in 0..<20 { g.baseMissiles(&r, 1); g.arms.slugs = [] }
        check(fired == SmallMissiles.baseLoad && (r.missiles ?? 0) >= 2 && restocked == 2 && SmallMissiles.launched == l1,
              "P135 citadel missiles: \(fired) fired in two minutes of lockdown (the load is \(SmallMissiles.baseLoad)), \(restocked) back after twelve calm minutes; none at 10 blocks")
    }


    static func p136(_ game: Game, _ check: (Bool, String) -> Void) {
        // Linear in tip speed, a wind-up bonus, the head zone.
        let lin = abs(VRMelee.power(8) / VRMelee.power(4) - 2) < 0.01 && abs(VRMelee.power(6) - VRMelee.power(3) * 2) < 0.01
        let jab = VRMelee.travelBonus(0.15), arc = VRMelee.travelBonus(1.0), full = VRMelee.travelBonus(3)
        let z = Mob(.zombie, at: V3(0, 0, 0)), cow = Mob(.cow, at: V3(0, 0, 0))
        cow.yaw = 0                                                      // facing -z
        let zHead = VRMelee.headHit(z, at: V3(0, z.height - 0.15, 0)), zBody = VRMelee.headHit(z, at: V3(0, z.height * 0.55, 0))
        let cHead = VRMelee.headHit(cow, at: V3(0, cow.height * 0.8, -cow.halfW)), cRump = VRMelee.headHit(cow, at: V3(0, cow.height * 0.8, cow.halfW))
        check(lin && jab == 1 && arc > 1.2 && arc < 1.3 && abs(full - 1.4) < 0.01 && zHead && !zBody && cHead && !cRump,
              String(format: "P136 swing damage: linear in tip speed (x%.2f at 4 m/s, x%.2f at 8); wind-up x%.2f for a jab, x%.2f for a 1 m arc, x%.2f most; head zone: a zombie's head %@, its chest %@, a cow's head %@, its rump %@",
                     VRMelee.power(4), VRMelee.power(8), jab, arc, full, zHead ? "yes" : "no", zBody ? "yes" : "no", cHead ? "yes" : "no", cRump ? "yes" : "no"))

        // A charged swing to the head deals half again what one to the chest does.
        let p = game.player
        let save = (game.inventory.held, p.yaw, p.pitch, game.paused, p.pos, p.flying, game.survival, game.health, game.bufferAttacks)
        defer {
            (game.inventory.held, p.yaw, p.pitch, game.paused, p.pos, p.flying, game.survival, game.health, game.bufferAttacks) = save
            game.swingMelee = false; game.swingMob = nil; game.swingPower = 0; game.swingPoint = nil
        }
        let P = V3(floorf(p.pos.x) + 0.5, floorf(p.pos.y) + 60, floorf(p.pos.z) + 0.5)
        let fy = Int(floorf(P.y)) - 1, fx = Int(floorf(P.x)), fz = Int(floorf(P.z))
        for dz in -4...4 { for dx in -4...4 {
            game.world.setBlock(fx + dx, fy, fz + dz, STONE)
            for k in 0...3 { game.world.setBlock(fx + dx, fy + 1 + k, fz + dz, AIR) }
        } }
        game.paused = false; game.bufferAttacks = true; game.survival = false; p.flying = false
        p.yaw = 0; p.pitch = -0.35
        game.inventory.held = ItemStack(Items.id("iron_sword"), 1)
        game.swingMelee = true
        func ticks(_ n: Int, _ body: () -> Void = {}) { for _ in 0..<n { p.pos = P; p.vel = .zero; body(); game.tick(1.0 / 60) } }
        func dealt(head: Bool) -> Int {
            let m = Mob(.husk, at: P + V3(0, 0, -2))
            m.equip = nil
            game.mobs.mobs.append(m)
            defer { game.mobs.mobs.removeAll { $0 === m } }
            ticks(90) { m.pos = P + V3(0, 0, -2); m.vel = .zero }
            let h = m.health
            ticks(1) {
                m.pos = P + V3(0, 0, -2); m.vel = .zero
                game.swingPower = 1; game.swingMob = m
                game.swingPoint = m.pos + V3(0, head ? m.height - 0.12 : m.height * 0.55, 0.3)
            }
            ticks(30) { m.pos = P + V3(0, 0, -2); m.vel = .zero }
            return h - m.health
        }
        let h0 = VRMelee.headHits
        let body = dealt(head: false), head = dealt(head: true)
        check(body > 0 && Float(head) >= Float(body) * 1.3 && VRMelee.headHits == h0 + 1,
              "P136 head hits: a charged iron sword swing deals \(body) to the chest, \(head) to the head")
    }


    static func p137(_ g: Game, _ check: (Bool, String) -> Void) {
        let iron = Items.id("iron_ingot")
        let sword = Items.id("iron_sword"), d = Items.def(sword).durability
        var plain = ItemStack(sword, 1); plain.damage = d - 1
        var fitted = plain
        fitted.ench = Enchant.pack([(.sharpness, 3), (.unbreaking, 2)])
        let a = Enchant.combine(plain, ItemStack(iron, 64), rename: nil, creative: false)
        let b = Enchant.combine(fitted, ItemStack(iron, 64), rename: nil, creative: false)
        var half = fitted; half.damage = d / 2
        let c = Enchant.combine(half, ItemStack(iron, 64), rename: nil, creative: false)
        check(a?.rightUsed == 4 && a?.out.damage == 0 && b?.rightUsed == 9 && b?.out.damage == 0 && (b?.cost ?? 0) > (a?.cost ?? 0) && c?.rightUsed == 5,
              "P137 repair cost: a worn-out iron sword takes \(a?.rightUsed ?? -1) iron to repair, with Edge III and Head II \(b?.rightUsed ?? -1) (half worn \(c?.rightUsed ?? -1)); experience \(a?.cost ?? -1) -> \(b?.cost ?? -1)")
    }

    static func p138(_ g: Game, _ check: (Bool, String) -> Void) {
        let on0 = Blueprints.on, known0 = Blueprints.known, seed0 = Blueprints.seedPending
        let surv0 = g.survival, xp0 = g.xpLevel, held0 = g.inventory.held, sel = g.inventory.selected
        let main0 = g.inventory.main.slots
        var toasts: [String] = []
        let t0 = g.onToast
        defer {
            Blueprints.on = on0; Blueprints.known = known0; Blueprints.seedPending = seed0
            g.survival = surv0; g.xpLevel = xp0; g.inventory.main.slots = main0; g.inventory.held = held0; g.inventory.selected = sel; g.onToast = t0
        }
        Blueprints.on = true; Blueprints.known = []; Blueprints.seedPending = false
        g.survival = true; g.xpLevel = 30
        g.onToast = { toasts.append($0) }
        for i in 0..<g.inventory.main.count { g.inventory.main[i] = .empty }
        g.inventory.main[1] = ItemStack(Items.id("iron_sword"), 1)
        g.inventory.main[2] = ItemStack(Items.id("iron_ingot"), 64)
        g.inventory.main[3] = ItemStack(Items.id("flint"), 64)
        // Without the blueprint the bench refuses; reading one learns it; then it fits.
        let refused = Upgrades.fit(g, g.inventory.main, 1, .sharpness)
        g.inventory.selected = 0
        g.inventory.main[0] = Blueprints.stack(.sharpness)
        let label = g.inventory.main[0].displayName
        let read = g.blueprintUse() && Blueprints.known.contains("sharpness") && g.inventory.main[0].isEmpty
        let fitted = Upgrades.fit(g, g.inventory.main, 1, .sharpness)
        // Chests: about one in four of many tables carry one.
        var chests = 0, with = 0, lines = Set<Int>()
        for table in ["village_house", "steelhold_supply", "shipwreck_supply", "dungeon", "desert_pyramid", "camp_traders"] {
            for k in 0..<60 {
                let c = ItemContainer(27)
                var rng = SRng(UInt64(4100 + k * 131))
                Loot.fill(c, table: table, rng: &rng)
                chests += 1
                if let s = c.slots.first(where: { Blueprints.line($0) != nil }) { with += 1; lines.insert(s.tag) }
            }
        }
        let share = Float(with) / Float(max(1, chests))
        // An older save learns what the carried items already have.
        Blueprints.known = []; Blueprints.seedPending = true
        var worn = ItemStack(Items.id("iron_sword"), 1); worn.ench = Enchant.pack([(.looting, 1)])
        g.inventory.main[5] = worn
        let seeded = Blueprints.knows(g, .looting) && !Blueprints.knows(g, .fireAspect)
        check(!refused.1 && refused.0.contains("blueprint") && label == "Blueprint: " + Enchant.def(.sharpness).name && read && fitted.1 && share > 0.17 && share < 0.33
              && lines.count >= 12 && seeded,
              String(format: "P138 blueprints: without one the bench says \"%@\"; \"%@\" read %@, then fitted %@; %d of %d chests hold one (%d lines); an older save knows its carried upgrades %@",
                     refused.0, label, read ? "yes" : "no", fitted.1 ? "yes" : "no", with, chests, lines.count, seeded ? "yes" : "no"))
    }


    static func p139(_ g: Game, _ check: (Bool, String) -> Void) {
        let adv0 = g.advancements, surv0 = g.survival, main0 = g.inventory.main.slots, marks0 = MapCache.shared.marks
        let t0 = g.onToast, hint0 = g.hell.hintAt
        var toasts: [String] = []
        defer {
            g.advancements = adv0; g.survival = surv0; g.inventory.main.slots = main0; MapCache.shared.replaceMarks(marks0)
            g.onToast = t0; g.hell.hintAt = hint0
        }
        g.survival = true
        for i in 0..<g.inventory.main.count { g.inventory.main[i] = .empty }
        let p = Goals.path(g)
        guard let k = p.firstIndex(where: { $0.id == "ember_charge" }) else { check(false, "P139: no Ember Charge step"); return }
        g.advancements = Set(p[..<k].map { $0.id } + ["goal/wood", "goal/pickaxe", "goal/furnace"])
        let before = Goals.next(g)
        g.inventory.main[0] = ItemStack(Items.id("ember_charge"), 1)
        let after = Goals.next(g)
        g.onToast = { toasts.append($0) }
        MapCache.shared.replaceMarks([])
        g.hell.hintAt = -1000
        g.wardHint()
        let hint = toasts.last ?? "-"
        let marked = MapCache.shared.marks.contains { $0.kind == "military_base" }
        check(before?.id == "ember_charge" && before?.text.contains("Ember Charge") == true && after?.id == "enter_the_nether"
              && hint.contains("no pickaxe, ore") && hint.contains("marked on your map") && marked,
              "P139 next step: after Obsidian the goal is \"\(before?.text ?? "-")\", then \"\(after?.text ?? "-")\"; hitting Wardstone: \"\(hint)\" (citadel on the map \(marked))")
    }

}
