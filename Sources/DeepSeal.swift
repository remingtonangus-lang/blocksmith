import Foundation
import simd

// The Deep expansion (docs/status/the-deep-expansion.md): Sealrock, an 8-layer floor under the hell band that no
// pickaxe, explosion, piston or mob can break, so the Ash Vault below is shut off. Only Sunderite breaks it: a
// Sunderite Pickaxe mines it a block at a time and a Sunder Charge blasts a 3x3 shaft straight through. Sunderite Ore
// exists only in the strongrooms of the Brimstone Keeps (BrimstoneKeep.swift); processing: Raw Sunderite x2 + Cinder
// Powder -> Sunderite Flux (crafting) -> Sunderite Ingot (blast furnace only) -> the pickaxe (Duskium Pickaxe + 3
// ingots) or the charge (ingot + TNT).
enum DeepSeal {
    static let top = DeepGen.hellBase                  // first layer above the seal (the hell band's floor)
    static let bottom = DeepGen.hellBase - 8           // lowest seal layer
    static func inBand(_ y: Int) -> Bool { y >= bottom && y < top }
    // True when a move from y0 to y1 (internal y) would pass through the seal.
    static func crosses(_ y0: Float, _ y1: Float) -> Bool {
        let a = min(y0, y1), b = max(y0, y1)
        return a < Float(top) && b >= Float(bottom)
    }

    static let pickaxe = "sunderite_pickaxe"
    static let pickHardness: Float = 25                // how hard Sealrock is to a Sunderite Pickaxe (~3 s a block)
    static let chargeFuse: Float = 3
    static let chargeRadius = 1                        // 3x3 shaft
    static var moments = 0

    // What the generator ever put in the band's layers (lower crust rock, ores, lava pockets, caves): the only blocks
    // the seal replaces in a saved chunk and the only ones a charge blows open past the seal. Anything else there was
    // built by a player (a chest keeps its contents, a wall stays a wall).
    static let natural: [Bool] = {
        var t = [Bool](repeating: false, count: Blocks.count)
        t[Int(AIR)] = true
        for k in ["air", "lava", "emberslate", "blackstone", "basalt", "magma_block", "deepslate_gold_ore", "deepslate_diamond_ore",
                  "ancient_debris", "netherrack", "cobbled_emberslate", "gravel", "soul_sand", "soul_soil", "crimson_nylium",
                  "warped_nylium", "nether_gold_ore", "nether_quartz_ore"] where Blocks.has(k) { t[Int(Blocks.id(k))] = true }
        for i in 0..<Blocks.count where Blocks.fluidKind[i] == 2 { t[i] = true }
        return t
    }()

    // Saved Deep chunks from before the seal: the band's natural blocks become Sealrock, unless the chunk already holds
    // some (it was generated with the seal, and any gap in it was cut by the player with Sunderite).
    static func stamp(_ b: inout [BlockID]) {
        let seal = Blocks.id("sealrock")
        let lo = bottom * CSQ, hi = top * CSQ
        guard b.count >= hi else { return }
        for i in lo..<hi where b[i] == seal { return }
        for i in lo..<hi where natural[Int(b[i])] { b[i] = seal }
    }
}

extension BlockRegistry {
    func registerDeepExpansionBlocks() {
        if !has("sealrock") {
            var d = BlockDef("sealrock", "Sealrock")
            d.tex = ["sealrock"]
            d.hardness = -1; d.resistance = 3_600_000
            d.tool = .pickaxe; d.requiresTool = true; d.harvestLevel = 5; d.sound = .stone
            add(d)
        }
        if !has("sunderite_ore") {
            var d = BlockDef("sunderite_ore", "Sunderite Ore")
            d.tex = ["sunderite_ore"]
            d.hardness = 30; d.resistance = 1200
            d.tool = .pickaxe; d.requiresTool = true; d.harvestLevel = 3; d.sound = .stone; d.emit = 6
            add(d)
        }
    }
}

extension ItemRegistry {
    func registerDeepExpansionItems() {
        func item(_ n: String, _ disp: String, _ mask: String, _ color: UInt32, _ extras: [Character: UInt32] = [:], stack: Int = 64) {
            guard !has(n) else { return }
            var d = ItemDef(n, disp)
            d.sprite = Sprite(mask: mask, base: color, extras: extras)
            d.maxStack = stack
            add(d)
        }
        item("raw_sunderite", "Raw Sunderite", "lump", 0x8E2F4A)
        item("sunderite_flux", "Sunderite Flux", "dust", 0xC0485E)
        item("sunderite_ingot", "Sunderite Ingot", "ingot", 0xB03A55)
        item("sunder_charge", "Sunder Charge", "module", 0x3A2228, ["c": 0xE0485A, "d": 0xFFB060], stack: 16)
        if !has(DeepSeal.pickaxe) {
            var d = ItemDef(DeepSeal.pickaxe, "Sunderite Pickaxe")
            d.sprite = Sprite(mask: "pickaxe", base: 0xB03A55, extras: [:])
            d.maxStack = 1
            d.tool = .pickaxe
            d.tier = 5
            d.durability = 2400
            d.toolSpeed = 10
            d.attack = 7
            d.attackSpeed = 1.2
            add(d)
        }
    }
}

extension Recipes {
    static func deepRecipes() -> [Recipe?] {
        [shapeless(["raw_sunderite", "raw_sunderite", "blaze_powder"], "sunderite_flux"),
         shapeless(["netherite_pickaxe", "sunderite_ingot", "sunderite_ingot", "sunderite_ingot"], DeepSeal.pickaxe),
         shapeless(["sunderite_ingot", "tnt"], "sunder_charge")]
    }
}

extension TextureGen {
    static func deepPainters(_ p: inout [String: Painter]) {
        // Sealrock: near-black glassy rock, cracked with thin dull-red seams that never quite meet.
        p["sealrock"] = { x, y in
            let n = r(x / 2, y / 2, 4101) * 0.6 + r(x, y, 4102) * 0.4
            let seam = abs(Float((x * 3 + y * 5) % 11) - 5) < 0.6 && r(x / 3, y / 3, 4103) > 0.45
            if seam { return hex(0x6A1A22, 0.85 + 0.3 * r(x, y, 4104)) }
            return hex(0x15121A, 0.8 + 0.4 * n)
        }
        // Sunderite ore: emberslate-dark rock with glowing crimson crystals.
        p["sunderite_ore"] = { x, y in
            let cx = [3, 10, 6, 12], cy = [4, 2, 10, 11]
            for i in 0..<4 {
                let d = abs(x - cx[i]) + abs(y - cy[i])
                if d <= 1 { return hex(i % 2 == 0 ? 0xFF6A80 : 0xE04060, 1.0 - 0.1 * Float(d)) }
                if d == 2 && r(x, y, 4110 + i) > 0.4 { return hex(0x8E2F4A) }
            }
            return hex(0x2A2226, 0.85 + 0.3 * r(x / 2, y / 2, 4105))
        }
    }
}

extension Game {
    // A Sunder Charge pressed onto Sealrock: it burns for a few seconds, then blows a 3x3 shaft through the whole seal.
    func useSunderCharge(on hit: (hit: IVec3, normal: IVec3)?) -> Bool {
        guard Items.key(held.item) == "sunder_charge" else { return false }
        guard dim.dim == .deep, let t = hit, Blocks.key(world.block(t.hit.x, t.hit.y, t.hit.z)) == "sealrock",
              DeepSeal.inBand(t.hit.y) else {
            onToast?("A Sunder Charge only works pressed against Sealrock")
            return true
        }
        consumeHeld()
        sunderCharges.append((at: t.hit, t: DeepSeal.chargeFuse))
        sfx(.click, 0.8, at: V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) + 0.5)
        onToast?("Sunder Charge set: stand clear")
        return true
    }

    // Burns down placed charges (from deepTick).
    func sunderTick(_ dt: Float) {
        guard !sunderCharges.isEmpty else { return }
        for i in sunderCharges.indices.reversed() {
            sunderCharges[i].t -= dt
            let at = sunderCharges[i].at
            let c = V3(Float(at.x), Float(at.y), Float(at.z)) + 0.5
            if Rand.float(in: 0..<1) < 0.4 { particles.smoke(at: c + V3(0, 0.6, 0)) }
            if sunderCharges[i].t <= 0 {
                sunderCharges.remove(at: i)
                sunderBlast(at)
            }
        }
    }

    // The blast: every Sealrock block in the 3x3 columns around the charge goes, through all eight layers, plus the
    // ordinary rock one layer past each face so the shaft opens into the crust below and the hell band above.
    @discardableResult
    func sunderBlast(_ at: IVec3) -> Int {
        let seal = Blocks.id("sealrock")
        let r = DeepSeal.chargeRadius
        var removed = 0
        for z in (at.z - r)...(at.z + r) { for x in (at.x - r)...(at.x + r) {
            for y in (DeepSeal.bottom - 1)...DeepSeal.top {
                let b = world.block(x, y, z)
                if b == seal { world.setBlock(x, y, z, AIR); removed += 1 }
                else if (y == DeepSeal.bottom - 1 || y == DeepSeal.top) && b != AIR && DeepSeal.natural[Int(b)] && !Blocks.isLiquid(b) {
                    world.setBlock(x, y, z, AIR)
                }
            }
        } }
        let c = V3(Float(at.x), Float(at.y), Float(at.z)) + 0.5
        Explosion.explode(at: c, power: 2.6, game: self, breakBlocks: false)
        if removed > 0 {
            achieve("break_seal")
            sealBreakMoment(at: c)
            sealShafts.append(at)
        }
        return removed
    }

    // The seal breaking is a big moment (the gap pass, DE6): a deep boom and the debris after it, a light column up the
    // shaft from the vault's glow below, a hard shake, rock raining down the shaft and the vault named.
    func sealBreakMoment(at c: V3) {
        sfx(.explodeLarge, 1.7, at: c)
        sfx(.debrisRain, 1.3, at: c)
        sfx(.mainGunRumble, 0.8, at: c)
        for k in 0..<6 { addFlash(at: c + V3(0, Float(k * 6) - 12, 0), color: V3(7, 3.2, 1.4), radius: 40, life: 1.6) }
        addShake(simd_length(player.pos - c) < 24 ? 1 : 0.5)
        for _ in 0..<160 {
            let o = V3(Rand.float(in: -1.6...1.6), Rand.float(in: -2...14), Rand.float(in: -1.6...1.6))
            particles.add(Particle(pos: c + o, vel: V3(Rand.float(in: -0.8...0.8), Rand.float(in: -6 ... -1), Rand.float(in: -0.8...0.8)),
                                   life: 2.4, maxLife: 2.4, layer: Int(Tex.id("sealrock")), uv0: V2(Rand.float(in: 0..<0.75), Rand.float(in: 0..<0.75)),
                                   uvSize: 0.25, size: Rand.float(in: 0.08...0.2), gravity: 14, color: V3(1, 1, 1), collide: true))
        }
        for _ in 0..<24 { particles.smoke(at: c + V3(Rand.float(in: -1.5...1.5), Rand.float(in: -8...4), Rand.float(in: -1.5...1.5))) }
        DeepSeal.moments += 1
        onToast?("The seal breaks. Far below, the Ash Vault glows")
    }

    // Hitting Sealrock with anything but Sunderite says what it takes (once a minute at most).
    func sealHint() {
        guard clock - sealHintAt > 60 else { return }
        sealHintAt = clock
        onToast?("Sealrock: only Sunderite breaks it. Brimstone Keeps in the fire above hold the ore")
    }
}
