import Foundation
import simd

// The gate into hell (backlog B6, docs/status/hell-mobs.md): hell comes after the military bases. Two ways in, both shut:
//   the Deep's hell band  the surface's bottom three layers are Wardstone, which nothing breaks (pickaxe, blast, frigate
//                         shell, piston, mob); an Ember Charge pressed onto it blasts a 3x3 shaft through to the Deep.
//   the Emberdeep         a portal frame on the surface no longer lights with flint and steel; an Ember Charge wakes it.
// Ember Charges are base loot (every command chest holds one, a vault one or two: Loot.extraPools) and, on the spine
// (Spine.swift), the strongroom of a fleet frigate sunk or seized; P249 added a dear recipe (DeepSeal.deepRecipes) so
// the way down never hangs on loot. The Ashguard's citadel stands under the world's centre (AshWar), so the hints say
// how far it is when the player is about to break through far from it.
// Saved surface chunks get the floor stamped in as they load (SaveManager.load), portals already lit stay lit, and the
// way up out of the Deep cuts through the floor (DeepSeam.crossSeam).
let WARDSTONE = Blocks.id("wardstone")

enum HellGate {
    static let floorTop = 3                    // Wardstone fills internal y 0 ..< 3 of the surface
    static let chargeKey = "ember_charge"
    static let chargeFuse: Float = 3
    static var blasts = 0, lit = 0             // harness counters
    static var wardHints = 0
    static var markedAt: Double = -100         // P317: the last time a refusal put the nearest citadel on the map

    // A freshly generated surface chunk's floor (WorldGen.generate, after the caves and lava).
    static func floor(_ b: inout [BlockID]) {
        let w = WARDSTONE
        for i in 0..<(CSQ * floorTop) { b[i] = w }
    }

    // What the stamp leaves alone in a saved chunk's floor layers: blocks that carry contents (a chest, a spawner, a
    // sign, a bed...). Everything else there becomes Wardstone, a shaft or ladder a player dug before the floor included,
    // so an old save has no way down without a charge either.
    static let keep: [Bool] = {
        var t = [Bool](repeating: false, count: Blocks.count)
        let words = ["chest", "barrel", "furnace", "smoker", "spawner", "hopper", "dispenser", "dropper", "shulker", "sign", "banner",
                     "lectern", "shelf", "pot", "crafter", "brewing", "beacon", "campfire", "bed", "vault", "jukebox", "frame"]
        for i in 0..<Blocks.count {
            let k = Blocks.key(BlockID(i))
            if words.contains(where: { k.contains($0) }) { t[i] = true }
        }
        return t
    }()

    // Saved surface chunks from before the floor: the floor layers become Wardstone, unless the chunk already holds
    // some (it was generated with the floor, and any gap in it was blasted by a player).
    static func stamp(_ b: inout [BlockID]) {
        let ward = WARDSTONE
        let n = CSQ * floorTop
        guard b.count >= n else { return }
        for i in 0..<n where b[i] == ward { return }
        for i in 0..<n where !keep[Int(b[i])] { b[i] = ward }
    }
}

extension BlockRegistry {
    func registerHellGateBlocks() {
        if !has("wardstone") {
            var d = BlockDef("wardstone", "Wardstone")
            d.tex = ["wardstone"]
            d.hardness = -1; d.resistance = 3_600_000
            d.tool = .pickaxe; d.requiresTool = true; d.harvestLevel = 5; d.sound = .stone
            add(d)
        }
    }
}

extension ItemRegistry {
    func registerHellItems() {
        if !has(HellGate.chargeKey) {
            var d = ItemDef(HellGate.chargeKey, "Ember Charge")
            d.sprite = Sprite(mask: "module", base: 0x3A1A12, extras: ["c": 0xFF7A2A, "d": 0xFFD070])
            d.maxStack = 16
            add(d)
        }
        if !has("brand_greatsword") {
            var d = ItemDef("brand_greatsword", "Brand Greatsword")
            d.sprite = Sprite(mask: "sword", base: 0x6A1022, extras: [:])
            d.maxStack = 1
            d.tool = .sword
            d.tier = 4
            d.durability = 1900
            d.attack = 9
            d.attackSpeed = 1.1
            add(d)
        }
    }
}

extension TextureGen {
    static func hellPainters(_ p: inout [String: Painter]) {
        // Wardstone: dense grey-black rock banded with faint ember-orange runes of light that never quite join.
        p["wardstone"] = { x, y in
            let n = r(x / 2, y / 2, 4301) * 0.55 + r(x, y, 4302) * 0.45
            let band = (y % 5 == 2) && r(x / 3, y, 4303) > 0.55
            if band { return hex(0x8A3A14, 0.8 + 0.35 * r(x, y, 4304)) }
            return hex(0x24201E, 0.8 + 0.4 * n)
        }
    }
}

extension Game {
    // An Ember Charge: against Wardstone it burns for a few seconds, then blows a 3x3 shaft through the floor; used on a
    // portal frame (the obsidian or the space inside it) it wakes the frame.
    // P317 (c): no words. Set on Wardstone it shows there with a hissing, sparking fuse; in a frame the frame lights;
    // anywhere else it fizzles (DeepSeal.chargeFizzle) and stays in the hand.
    func useEmberCharge(on hit: (hit: IVec3, normal: IVec3)?) -> Bool {
        guard !held.isEmpty, Items.key(held.item) == HellGate.chargeKey else { return false }
        guard let t = hit else {
            chargeFizzle(nil)
            return true
        }
        if world.block(t.hit.x, t.hit.y, t.hit.z) == WARDSTONE {
            consumeHeld()
            hell.charges.append((at: t.hit, t: HellGate.chargeFuse))
            showSetCharge(t)
            sfx(.tntFuse, 0.9, at: V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) + 0.5)
            return true
        }
        for p in [t.hit + t.normal, t.hit] where tryLightPortal(at: p, probe: true) {
            consumeHeld()
            _ = tryLightPortal(at: p)
            HellGate.lit += 1
            let c: V3 = V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5
            sfx(.ignite, 1, at: c)
            addFlash(at: c, color: V3(5, 2.2, 0.8), radius: 10, life: 0.6)
            return true
        }
        chargeFizzle(t)
        return true
    }

    // A whole frame around `p` that flint and steel can't light: the surface, in survival.
    func portalLocked(_ p: IVec3) -> Bool {
        dim.dim == .overworld && survival && tryLightPortal(at: p, probe: true)
    }

    // P317 (a, c): flint in a frame that only a charge wakes: the spark fizzles in it, no words. The nearest citadel
    // (where charges are kept) still goes on the map, as it did with the old hint.
    func coldFrameHint() {
        guard clock - hell.hintAt > 0.5 || clock < hell.hintAt else { return }
        hell.hintAt = clock
        if let t = target { chargeFizzle(t) }
        if clock - HellGate.markedAt > 60 || clock < HellGate.markedAt { HellGate.markedAt = clock; citadelPointer() }
    }

    // P139 put the nearest citadel on the map when Wardstone would not break; P317 (a): that stays, the words go. The
    // pick just clunks off it with a spark (DeepSeal.toolBounce).
    func wardHint() {
        guard clock - hell.hintAt > 0.5 || clock < hell.hintAt else { return }
        hell.hintAt = clock
        toolBounce()
        if clock - HellGate.markedAt > 60 || clock < HellGate.markedAt { HellGate.markedAt = clock; citadelPointer() }
        HellGate.wardHints += 1
    }

    // The nearest Capital citadel, put on the map (P328, NO TEXT: quietly, with no toast or bearing; the map shows it).
    func citadelPointer() {
        guard dim.dim == .overworld, let sc = world.gen.structures,
              let s = sc.nearest("military_base", x: Int(player.pos.x), z: Int(player.pos.z), maxRegions: 4) else { return }
        MapCache.shared.discover(self, kind: "military_base", x: (s.min.x + s.max.x) / 2, z: (s.min.z + s.max.z) / 2, silent: true)
    }
    // (P328: vaultPointer, the unused "go down near the world's centre" line, is gone.)

    // Burns down placed charges (from hellTick).
    func emberChargesTick(_ dt: Float) {
        guard !hell.charges.isEmpty else { return }
        for i in hell.charges.indices.reversed() {
            hell.charges[i].t -= dt
            let at = hell.charges[i].at
            let c = V3(Float(at.x), Float(at.y), Float(at.z)) + 0.5
            if Rand.float(in: 0..<1) < 0.5 { particles.flame(at: c + V3(0, 0.6, 0)) }
            if hell.charges[i].t <= 0 {
                hell.charges.remove(at: i)
                clearSetCharge(over: at)
                wardBlast(at)
            }
        }
    }

    // Every Wardstone block in the 3x3 columns round the charge goes, through the whole floor.
    @discardableResult
    func wardBlast(_ at: IVec3) -> Int {
        var removed = 0
        for z in (at.z - 1)...(at.z + 1) { for x in (at.x - 1)...(at.x + 1) {
            for y in 0..<HellGate.floorTop where world.block(x, y, z) == WARDSTONE {
                world.setBlock(x, y, z, AIR); removed += 1
            }
        } }
        let c = V3(Float(at.x), Float(at.y), Float(at.z)) + 0.5
        Explosion.explode(at: c, power: 2.4, game: self, breakBlocks: false)
        if removed > 0 {
            HellGate.blasts += 1
            achieve("break_ward")
            sfx(.explodeLarge, 1.4, at: c)
            addFlash(at: c + V3(0, -2, 0), color: V3(6, 2.4, 0.9), radius: 24, life: 1.2)
            addShake(simd_length(player.pos - c) < 16 ? 0.8 : 0.4)
            onToast?("The Wardstone gives way. Below it, Hell")
        }
        return removed
    }
}
