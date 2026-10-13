import Foundation
import simd
import Metal

// The Oct 12 afternoon playtest fixes (backlog P107-P139), `questcheck --p12pm-only [P1xx]`: one check per item.
enum PlaytestOct12PMTests {
    static func run(_ g: Game, only: String?, check: (Bool, String) -> Void) {
        let all: [(String, (Game, (Bool, String) -> Void) -> Void)] = [
            ("P107", p107), ("P108", p108), ("P109", p109), ("P110", p110), ("P111", p111), ("P112", p112),
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
}
