import Foundation
import simd

// The Deep's way home and back (the gap pass, docs/status/the-deep-expansion.md "Gap pass", rows D2b, DE4, DE7):
//   Ember Gates   every Brimstone Keep has one in its courtyard: a frame of gate stone, the Deep's stand-in for a portal.
//                 It sleeps until the keep's Warden falls; then a glowing veil fills it, and stepping in carries you to
//                 the surface (your bed or the world spawn).
//   Gate Shard    the Warden's drop (or crafted: a Sunderite Ingot and a Rift Pearl): used on the surface, it carries
//                 you back down to the last gate or lift you rode up. It is not used up.
//   Deep Lift     a plate you craft (a Sunderite Ingot, a piston, an iron block) and set down anywhere in the Deep:
//                 standing on it carries you up the same way, so the vault below the seal has a way home before the
//                 Marshal falls (his command-bunker lift, AshWar.swift, still opens after victory).
//   The Warden    the keep's mini-boss (a Boarling Brute, huge and armoured, with a boss bar): calls the wall guards at
//                 half health and goes berserk; drops the Gate Shard and the Warden's Brand (the hell band's trophy).
enum DeepGates {
    static let frameKey = "gate_stone", veilKey = "ember_gate", liftKey = "deep_lift"
    // The gate in a keep's courtyard, north of the keep: frame x ox-2...ox+2, y f+1...f+7, at z oz-gateBack.
    static let gateBack = 14
    static let cooldown: Float = 4

    static func keyFor(_ k: StructureStart) -> String { "\(k.anchor.x),\(k.anchor.z)" }
    // The keep's centre and floor from its start (anchor = ox, f + 1, oz + 15).
    static func centre(_ k: StructureStart) -> (ox: Int, oz: Int, f: Int) { (k.anchor.x, k.anchor.z - 15, k.anchor.y - 1) }
    // Where you step out of a gate (south of it, facing the keep) and its veil cells.
    static func front(_ k: StructureStart) -> V3 {
        let c = centre(k)
        return V3(Float(c.ox) + 0.5, Float(c.f + 1), Float(c.oz - gateBack + 2) + 0.5)
    }
    static func veil(_ k: StructureStart) -> [IVec3] {
        let c = centre(k)
        var v: [IVec3] = []
        for y in (c.f + 2)...(c.f + 6) { for x in (c.ox - 1)...(c.ox + 1) { v.append(IVec3(x, y, c.oz - gateBack)) } }
        return v
    }

    // The frame, built with the keep (BrimstoneKeep.build): a plinth, two pillars, a lintel, lamps; the veil cells left
    // as air until the Warden falls.
    static func build(_ w: inout StructWriter, ox: Int, oz: Int, f: Int) {
        let frame = Blocks.id(frameKey), lamp = Blocks.id("ash_lamp"), trim = Blocks.id("polished_blackstone")
        let z = oz - gateBack
        w.fill(ox - 3, f, z - 1, ox + 3, f, z + 1, trim)
        w.fill(ox - 2, f + 1, z, ox + 2, f + 7, z, frame)
        w.fill(ox - 1, f + 2, z, ox + 1, f + 6, z, AIR)
        w.set(ox - 3, f + 1, z, lamp); w.set(ox + 3, f + 1, z, lamp)
        w.set(ox, f + 8, z, frame)
    }

    static var woken = 0, rodeUp = 0, rodeDown = 0
    static let holdTime: Float = 1.5
}

extension BlockRegistry {
    func registerDeepGateBlocks() {
        if !has(DeepGates.frameKey) {
            var d = BlockDef(DeepGates.frameKey, "Gate Stone")
            d.tex = ["gate_stone"]
            d.hardness = -1; d.resistance = 3_600_000; d.sound = .stone; d.emit = 3
            add(d)
        }
        if !has(DeepGates.veilKey) {
            var d = BlockDef(DeepGates.veilKey, "Ember Gate")
            d.tex = ["ember_gate"]; d.render = .model; d.layer = .translucent; d.opaque = false; d.collide = false
            d.boxes = [Box(0, 0, 6, 16, 16, 10)]; d.emit = 13; d.hardness = -1; d.hidden = true; d.skyStop = false
            add(d)
        }
        if !has("sealbound_bricks") {
            var d = BlockDef("sealbound_bricks", "Sealbound Bricks")
            d.tex = ["sealbound_bricks"]
            d.hardness = 12; d.resistance = 1200; d.tool = .pickaxe; d.requiresTool = true; d.harvestLevel = 3; d.sound = .stone
            add(d)
        }
        if !has(DeepGates.liftKey) {
            var d = BlockDef(DeepGates.liftKey, "Hell Lift")
            d.tex = ["deep_lift_side", "deep_lift_side", "deep_lift", "deep_lift_side", "deep_lift_side", "deep_lift_side"]
            d.render = .model; d.opaque = false; d.boxes = [Box(0, 0, 0, 16, 3, 16)]
            d.hardness = 4; d.tool = .pickaxe; d.sound = .metal; d.emit = 9
            add(d)
        }
    }
}

extension ItemRegistry {
    func registerDeepGateItems() {
        func item(_ n: String, _ disp: String, _ mask: String, _ color: UInt32, _ extras: [Character: UInt32] = [:], stack: Int = 64) {
            guard !has(n) else { return }
            var d = ItemDef(n, disp)
            d.sprite = Sprite(mask: mask, base: color, extras: extras)
            d.maxStack = stack
            add(d)
        }
        item("gate_shard", "Gate Shard", "gem", 0xFF7A3C, stack: 1)
        // Trophies, one per layer (DE13): the hell band's, the seal's and the vault's.
        item("warden_brand", "Castellan's Brand", "rod", 0xD8502A, stack: 1)
        item("sealrock_shard", "Sealrock Shard", "lump", 0x2A2232)
        // Worn like a helmet: a little better than Duskium (armour 3, toughness 3).
        if !has("marshal_cap") {
            var d = ItemDef("marshal_cap", "The Marshal's Cap")
            d.sprite = Sprite(mask: "helmet", base: 0x1C1C20, extras: [:])
            d.maxStack = 1; d.armorSlot = .head; d.armor = 3; d.toughness = 3; d.durability = 500
            add(d)
        }
    }
}

extension Recipes {
    static func deepGateRecipes() -> [Recipe?] {
        [shapeless(["sunderite_ingot", "ender_pearl"], "gate_shard"),
         shapeless(["sunderite_ingot", "piston", "iron_block"], DeepGates.liftKey),
         shapeless(["sealrock_shard", "sealrock_shard", "sealrock_shard", "sealrock_shard"], "sealbound_bricks")]
    }
}

extension TextureGen {
    static func deepGatePainters(_ p: inout [String: Painter]) {
        // Gate stone: dark carved blocks with a dim ember inlay running round the edge.
        p["gate_stone"] = { x, y in
            if x == 1 || y == 1 || x == 14 || y == 14 { return hex(0xC0461E, 0.8 + 0.3 * r(x, y, 4201)) }
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x141016) }
            return hex(0x2A2028, 0.85 + 0.25 * r(x / 2, y / 2, 4202))
        }
        // The veil: a hot shimmering orange sheet.
        p["ember_gate"] = { x, y in
            let w = sinf(Float(x) * 0.8 + Float(y) * 0.35) * 0.5 + 0.5
            return hex(w > 0.5 ? 0xFF8A3A : 0xE0461E, 0.85 + 0.3 * r(x, y / 2, 4203))
        }
        p["deep_lift"] = { x, y in
            let d = max(abs(Float(x) - 7.5), abs(Float(y) - 7.5))
            if d > 6.5 { return hex(0x2A2A30) }
            if d > 5 { return hex(0xB03A55) }
            return hex(0xFFC890, 0.9 + 0.1 * r(x, y, 4204))
        }
        p["deep_lift_side"] = { x, y in y < 13 ? hex(0x101012) : hex(0x3A3A40, 0.9 + 0.15 * r(x, y, 4205)) }
        p["sealbound_bricks"] = { x, y in
            if y % 8 == 0 || (x + (y / 8 % 2) * 8) % 16 == 0 { return hex(0x0C0A10) }
            let seam = (x * 3 + y * 5) % 13 == 0
            return seam ? hex(0x7A2030) : hex(0x1E1824, 0.85 + 0.3 * r(x / 2, y / 2, 4206))
        }
    }
}

extension Mob {
    // The keep's mini-boss. `loading`: a saved Warden keeps the health it was saved with.
    func makeKeepWarden(loading: Bool = false) {
        warden = true
        customName = "Keep Castellan"
        scale = 1.35
        persistent = true
        spec.health = 240
        spec.speed *= 0.9
        spec.drops = [("gate_shard", 1, 1), ("warden_brand", 1, 1), ("gold_ingot", 3, 6), ("netherite_scrap", 1, 2)]
        spec.xp = 120
        if !loading { health = spec.health }
        // Saved past half health: still raging (no second bellow, no second speed-up).
        if loading && !wardenRaged && health * 2 < spec.health { wardenRaged = true; spec.speed *= 1.3 }
        power = max(power, 1.8)
    }

    // Once a tick from the brute's own AI: at half health it bellows, calls the wall guards and goes berserk.
    func wardenTick(_ dt: Float, _ g: Game) {
        guard warden, health > 0 else { return }
        if !wardenRaged && Float(health) < Float(spec.health) * 0.5 {
            wardenRaged = true
            spec.speed *= 1.3
            g.sfx(.mob(kind, .hurt), 1.6, at: pos)
            for o in g.mobs.mobs where o !== self && o.health > 0 && o.kind.hostile && simd_length(o.pos - pos) < 40 {
                o.aggro = true
            }
            g.onToast?("The Keep Castellan bellows for the wall guards")
        }
    }
}

extension Game {
    // The Warden's (or the Marshal's) boss bar when near.
    func wardenBossBar() -> (String, Float)? {
        guard dim.dim == .deep else { return nil }
        guard let m = mobs.mobs.first(where: { $0.warden && $0.health > 0 && simd_length($0.pos - player.pos) < 48 }) else { return nil }
        return ("Keep Castellan", Float(m.health) / Float(m.spec.health))
    }

    // The keep a place belongs to (its courtyard or close round it).
    func keepAt(_ p: V3) -> StructureStart? {
        guard dim.dim == .deep, let sc = world.gen.structures,
              let k = sc.nearest("brimstone_keep", x: Int(p.x), z: Int(p.z), maxRegions: 1) else { return nil }
        let c = DeepGates.centre(k)
        return abs(Float(c.ox) - p.x) < 80 && abs(Float(c.oz) - p.z) < 80 ? k : nil
    }

    // The Warden fell: the keep's gate wakes (its veil fills now and whenever its ground loads again).
    func wardenDied(_ m: Mob) {
        guard m.warden, let k = keepAt(m.pos) else { return }
        if m.killedByPlayer { achieve("keep_warden") }
        let key = DeepGates.keyFor(k)
        if !wokenGates.contains(key) {
            wokenGates.append(key)
            DeepGates.woken += 1
            onToast?("The Ember Gate in the courtyard wakes: step in to go home. The Gate Shard brings you back")
        }
        fillGate(k)
    }

    func fillGate(_ k: StructureStart) {
        let v = Blocks.id(DeepGates.veilKey)
        for c in DeepGates.veil(k) where world.isLoaded(c.x, c.z) && world.block(c.x, c.y, c.z) == AIR { world.setBlock(c.x, c.y, c.z, v) }
    }

    // Once a tick in the Deep (deepTick): woken gates refill as they load, and the player stepping into a veil or onto a
    // Deep Lift rides up.
    func gatesTick(_ dt: Float) {
        gateCooldown = max(0, gateCooldown - dt)
        gateFillT -= dt
        if gateFillT <= 0 {
            gateFillT = 1                                      // a structure lookup: once a second is plenty
            if !wokenGates.isEmpty, let k = keepAt(player.pos), wokenGates.contains(DeepGates.keyFor(k)) { fillGate(k) }
        }
        guard gateCooldown <= 0, alive, riding == nil else { return }
        let f = player.pos
        let x = Int(floor(f.x)), y = Int(floor(f.y + 0.1)), z = Int(floor(f.z))
        let veil = Blocks.id(DeepGates.veilKey), lift = Blocks.id(DeepGates.liftKey)
        if world.block(x, y, z) == veil || world.block(x, y + 1, z) == veil {
            // Stand in it a moment to ride (the gate stands on the north path: walking through doesn't send you home).
            if gateHold == 0 { onToast?("Stay in the Ember Gate to ride up") }
            gateHold += dt
            if gateHold >= DeepGates.holdTime, let k = keepAt(f) {
                gateHold = 0
                rideUp(from: DeepGates.front(k), how: "The Ember Gate carries you up to the surface")
            }
            return
        }
        gateHold = 0
        if world.block(x, y, z) == lift || (world.block(x, y - 1, z) == lift && f.y - Float(y) < 0.3) {
            rideUp(from: V3(Float(x) + 0.5, Float(world.block(x, y, z) == lift ? y : y - 1) + 0.25, Float(z) + 1.5), how: "The Hell Lift carries you up to the surface")
        }
    }

    // Up to the bed or world spawn; the Gate Shard remembers where you left.
    func rideUp(from: V3, how: String) {
        deepReturn = from
        DeepGates.rodeUp += 1
        gateCooldown = DeepGates.cooldown
        let to = spawnPoint
        changeDimension(to: .overworld, at: to)
        player.pos = to
        player.vel = .zero
        player.airPeak = to.y
        onToast?(how)
    }

    // The Gate Shard: back down to the last gate or lift you rode up (from the surface; not used up).
    func useGateShard() -> Bool {
        guard Items.key(held.item) == "gate_shard" else { return false }
        guard dim.dim == .overworld else {
            onToast?(dim.dim == .deep ? "The Gate Shard is warm: it works from the surface" : "The Gate Shard is cold here")
            return true
        }
        guard let to = deepReturn else {
            onToast?("The Gate Shard has no gate to find yet: wake an Ember Gate or ride a Hell Lift up first")
            return true
        }
        gateCooldown = DeepGates.cooldown
        DeepGates.rodeDown += 1
        changeDimension(to: .deep, at: to)
        // Land on the nearest open standing spot round the gate or lift (never digging out what was built there); only
        // with none within 3 blocks is the landing cell itself cleared.
        var land = to
        let bx = Int(floor(to.x)), by = Int(floor(to.y)), bz = Int(floor(to.z))
        func open(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            !Blocks.collide[Int(world.block(x, y, z))] && !Blocks.collide[Int(world.block(x, y + 1, z))] && Blocks.collide[Int(world.block(x, y - 1, z))]
        }
        search: for r in 0...3 { for dy in [0, 1, -1, 2] { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
            if open(bx + dx, by + dy, bz + dz) { land = V3(Float(bx + dx) + 0.5, Float(by + dy), Float(bz + dz) + 0.5); break search }
        } } } }
        if land == to && !open(bx, by, bz) {
            for y in by...(by + 1) where Blocks.collide[Int(world.block(bx, y, bz))] { world.setBlock(bx, y, bz, AIR) }
        }
        player.pos = land
        player.vel = .zero
        player.airPeak = land.y
        sfx(.click, 0.8)
        onToast?("The Gate Shard pulls you down into Hell")
        return true
    }
}
