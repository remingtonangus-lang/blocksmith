import Foundation
import simd

// Composter (reference compost chances, level 7 -> ready after a second, bone meal out) and bells
// (ringing makes raiders within 48 blocks glow and sends villagers home).
enum Compost {
    static func chance(_ key: String) -> Float? {
        let k = key
        let c100 = ["cake", "pumpkin_pie"]
        let c85 = ["baked_potato", "bread", "cookie", "hay_block", "red_mushroom_block", "brown_mushroom_block", "nether_wart_block", "warped_wart_block", "pitcher_plant", "torchflower"]
        let c65 = ["apple", "beetroot", "carrot", "potato", "wheat", "cocoa_beans", "melon", "pumpkin", "carved_pumpkin", "lily_pad", "fern", "large_fern",
                   "brown_mushroom", "red_mushroom", "crimson_fungus", "warped_fungus", "crimson_roots", "warped_roots", "shroomlight", "sea_pickle",
                   "spore_blossom", "mushroom_stem", "weeping_vines", "twisting_vines", "big_dripleaf", "flowering_azalea"]
        let c50 = ["cactus", "melon_slice", "sugar_cane", "vine", "tall_grass", "nether_sprouts", "glow_lichen", "dried_kelp_block", "twisting_vines", "azalea"]
        let c30 = ["wheat_seeds", "beetroot_seeds", "melon_seeds", "pumpkin_seeds", "short_grass", "kelp", "dried_kelp", "sweet_berries", "glow_berries",
                   "seagrass", "moss_carpet", "hanging_roots", "mangrove_roots", "pink_petals", "small_dripleaf", "torchflower_seeds", "pitcher_pod"]
        if c100.contains(k) { return 1 }
        if c85.contains(k) { return 0.85 }
        if c65.contains(k) || ["dandelion", "poppy", "blue_orchid", "allium", "azure_bluet", "oxeye_daisy", "cornflower", "lily_of_the_valley",
                                "wither_rose", "sunflower", "lilac", "rose_bush", "peony"].contains(k) || k.hasSuffix("_tulip") { return 0.65 }
        if c50.contains(k) { return 0.5 }
        if c30.contains(k) || k.hasSuffix("_leaves") || k.hasSuffix("_sapling") || k == "mangrove_propagule" { return 0.3 }
        return nil
    }
}

extension Game {
    func useComposter(_ p: IVec3) {
        let b = world.block(p.x, p.y, p.z)
        let base = Blocks.groupBase[Int(b)]
        let lvl = Int(b - base)
        let c = V3(Float(p.x) + 0.5, Float(p.y) + 0.8, Float(p.z) + 0.5)
        if lvl == 8 {
            world.setBlock(p.x, p.y, p.z, base)
            drops.spawn(ItemStack(Items.id("bone_meal"), 1), at: c + V3(0, 0.4, 0))
            sfx(.composterFill, 0.8, at: c)
            return
        }
        guard lvl < 7, let ch = Compost.chance(Items.key(held.item)) else { return }
        if survival { consumeHeld() }
        swing = 1
        // The first item into an empty composter always counts.
        if lvl == 0 || Float.random(in: 0..<1) < ch {
            world.setBlock(p.x, p.y, p.z, base + BlockID(lvl + 1))
            if lvl + 1 == 7 { composterReady[p] = clock + 1 }
            sfx(.composterFill, 0.8, at: c)
        } else {
            sfx(.composterFill, 0.5, at: c)
        }
        for _ in 0..<4 { particles.smoke(at: c + V3(Float.random(in: -0.3...0.3), 0, Float.random(in: -0.3...0.3)), dark: false) }
    }

    func composterTick() {
        guard !composterReady.isEmpty else { return }
        for (p, t) in composterReady where clock >= t {
            composterReady[p] = nil
            let b = world.block(p.x, p.y, p.z)
            if Blocks.key(Blocks.groupBase[Int(b)]) == "composter" && Int(b - Blocks.groupBase[Int(b)]) == 7 {
                world.setBlock(p.x, p.y, p.z, Blocks.groupBase[Int(b)] + 8)
                sfx(.composterReady, 0.9, at: V3(Float(p.x) + 0.5, Float(p.y) + 0.8, Float(p.z) + 0.5))
            }
        }
    }

    func ringBell(_ p: IVec3) {
        let c = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
        for m in mobs.mobs where m.health > 0 && simd_length(m.pos - c) < 48 {
            if m.raider || [.pillager, .vindicator, .evoker, .ravager, .witch].contains(m.kind) {
                m.applyEffect(.glowing, amp: 0, seconds: 3, game: self)
            }
            if m.kind == .villager { m.panic = 8; m.aiTimer = 0 }
        }
    }
}
