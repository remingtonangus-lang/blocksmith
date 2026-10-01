import Foundation
import simd

// Small helpers the rest of the game calls: block sound materials (with overrides for blocks whose
// definitions predate the extra materials), openables, container menus, hurt and death sounds.

// Sound material per block id: the block definition's material, refined by name for metal, wool,
// gravel, slime, mud, bone, amethyst, soul sand and sculk.
private let metalKeys: Set<String> = ["iron_block", "iron_door", "iron_trapdoor", "iron_bars", "gold_block", "netherite_block", "chain", "cauldron",
                                      "hopper", "bell", "rail", "lightning_rod"]

let SoundMats: [SoundMat] = {
    var t: [SoundMat] = []
    t.reserveCapacity(Blocks.count)
    for i in 0..<Blocks.count {
        let id = BlockID(i)
        let k = Blocks.key(Blocks.groupBase[i])
        var m = Blocks.def(id).sound
        if k.hasSuffix("_wool") || k.hasSuffix("_carpet") || k == "honeycomb_block" || k.hasSuffix("_bed") { m = .wool }
        else if k == "gravel" || k == "suspicious_gravel" { m = .gravel }
        else if (k.contains("copper") && !k.hasSuffix("_ore")) || metalKeys.contains(k) || k.hasSuffix("anvil") || k.hasSuffix("lantern") || k.hasSuffix("_rail") || k.hasPrefix("raw_") { m = .metal }
        else if k == "bone_block" { m = .bone }
        else if k.contains("amethyst") { m = .amethyst }
        else if k == "slime_block" || k == "honey_block" { m = .slime }
        else if k == "mud" || k == "muddy_mangrove_roots" { m = .mud }
        else if k == "soul_sand" || k == "soul_soil" { m = .soul }
        else if k.hasPrefix("sculk") { m = .sculk }
        else if k == "netherrack" || k.hasPrefix("nether_") && k.hasSuffix("_ore") || k.hasSuffix("_nylium") { m = .netherrack }
        else if m == .stone && (k.contains("deepslate") || k.contains("basalt") || k.contains("blackstone") || k.hasPrefix("tuff") || k.contains("_tuff")) { m = .deepslate }
        else if k == "powder_snow" || k == "snow_block" || k == "snow" { m = .snow }
        t.append(m)
    }
    return t
}()

func soundMat(_ id: BlockID) -> SoundMat { Int(id) < SoundMats.count ? SoundMats[Int(id)] : .stone }

extension Game {
    // Doors, trapdoors and fence gates (player use or a circuit).
    func audioOpenable(shape: String, base: BlockID, opening: Bool, at p: IVec3) {
        audioOpenable(shape: shape, iron: Blocks.key(base).hasPrefix("iron"), opening: opening, at: p)
    }
    func audioOpenable(shape: String, iron: Bool, opening: Bool, at p: IVec3) {
        let s: Snd
        switch shape {
        case "door": s = iron ? (opening ? .ironDoorOpen : .ironDoorClose) : (opening ? .doorOpen : .doorClose)
        case "trapdoor": s = iron ? (opening ? .ironTrapdoorOpen : .ironTrapdoorClose) : (opening ? .trapdoorOpen : .trapdoorClose)
        default: s = opening ? .gateOpen : .gateClose
        }
        blockSound(s, at: p, 0.8)
    }

    // Container menus open and close with their own lids; everything else gets the interface blip.
    func audioMenuOpened(_ m: Menu) {
        let t = m.title
        if m is ShellBoxMenu { sfx(.shulkerOpen, 0.7) }
        else if m is ChestMenu || m is DoubleChestMenu {
            if t == "Barrel" { sfx(.barrelOpen, 0.7) }
            else if t == "Void Chest" { sfx(.enderChestOpen, 0.7) }
            else { sfx(.chestOpen, 0.7) }
        } else { sfx(.open, 0.6) }
    }
    func audioMenuClosed(_ m: Menu) {
        let t = m.title
        if m is ShellBoxMenu { sfx(.shulkerClose, 0.7) }
        else if m is ChestMenu || m is DoubleChestMenu {
            if t == "Barrel" { sfx(.barrelClose, 0.7) }
            else if t == "Void Chest" { sfx(.enderChestClose, 0.7) }
            else { sfx(.chestClose, 0.7) }
        } else if m is PauseMenu || m is DeathMenu {
            // silent
        } else { sfx(.uiBack, 0.5) }
    }

    // Break sound with a few block-specific ones (paintings, pots, glass panes use the glass material already).
    func audioBreakSound(_ b: BlockID) -> Snd {
        let k = Blocks.key(Blocks.groupBase[Int(b)])
        if k == "painting" { return .paintingBreak }
        if k == "decorated_pot" { return .potBreak }
        if k.hasSuffix("ice") && k != "blue_ice" { return .glassBreak }
        return .breakBlock(soundMat(b))
    }

    // 0 leather (and anything soft), 1 chain, 2 iron, 3 gold, 4 diamond, 5 duskium.
    static func armorSoundTier(_ key: String) -> Int {
        if key.hasPrefix("chainmail") { return 1 }
        if key.hasPrefix("iron") { return 2 }
        if key.hasPrefix("golden") { return 3 }
        if key.hasPrefix("diamond") { return 4 }
        if key.hasPrefix("netherite") { return 5 }
        return 0
    }

    func audioHurt(_ type: DamageType) {
        // Rate-limit so a burst of damage ticks does not stack grunts.
        if Float(clock) - audio.lastHurtSound < 0.25 { return }
        audio.lastHurtSound = Float(clock)
        switch type {
        case .fall: sfx(.hurtFall)
        case .drown: sfx(.hurtDrown)
        case .fire: sfx(.hurtFire)
        default: sfx(.hurt)
        }
    }

    func audioMobDied(_ m: Mob) {
        let at = m.pos + V3(0, m.height * 0.6, 0)
        switch m.kind {
        case .enderDragon: sfx(.dragonDeath, 2, at: at)
        case .wither: sfx(.witherDeath, 2, at: at)
        case .endCrystal: sfx(.crystalBreak, 1.2, at: at)
        default:
            if MobVoice.profile(m.kind).family != .silent { sfx(m.baby ? .babyMob(m.kind, .death) : .mob(m.kind, .death), 0.9, at: at) }
        }
    }
}
