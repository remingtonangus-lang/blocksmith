import Foundation
import simd

// Capital firearms: seven original guns found in the Capital's citadels and carried by their garrison.
// The attack button fires (hold it for the automatic ones), use aims down the sights (tighter spread,
// softer recoil, zoom), R or pad X reloads (also automatic when the magazine runs dry). Each gun feeds
// on its own ammunition from the inventory; the loaded count lives in the stack's tag.

enum ShotKind { case bullet, rocket, beam }

struct GunSpec {
    let key: String
    let name: String
    let ammo: String
    let mag: Int
    let interval: Float       // seconds between shots
    let auto: Bool
    let damage: Float         // per projectile (half-hearts); rockets use `power`
    let pellets: Int
    let spread: Float         // hip-fire cone (radians)
    let aimSpread: Float      // aimed cone
    let speed: Float          // blocks per second
    let recoil: Float         // upward kick per shot (radians)
    let reload: Float         // seconds
    let range: Float          // blocks before the round is spent
    let durability: Int
    let zoom: Float           // FOV scale while aiming
    let shot: ShotKind
    let sound: Int            // Snd.gun index
    let accent: V3
}

enum Guns {
    static let all: [GunSpec] = [
        GunSpec(key: "gun_rifle", name: "Donnerkeil Service Rifle", ammo: "capital_rounds", mag: 45, interval: 0.12, auto: true, damage: 5, pellets: 1,
                spread: 0.022, aimSpread: 0.005, speed: 160, recoil: 0.013, reload: 2.0, range: 110, durability: 1200, zoom: 0.78,
                shot: .bullet, sound: 0, accent: V3(0.9, 0.9, 0.88)),
        GunSpec(key: "gun_smg", name: "Hummel Machine Gun", ammo: "capital_rounds", mag: 60, interval: 0.07, auto: true, damage: 3, pellets: 1,
                spread: 0.045, aimSpread: 0.026, speed: 130, recoil: 0.009, reload: 1.6, range: 70, durability: 1500, zoom: 0.9,
                shot: .bullet, sound: 1, accent: V3(0.9, 0.9, 0.88)),
        // Hits as hard as it looks (Oct 11 playtest P30: "way too powerful [looking] for what it actually is"): 4 a pellet
        // (was 3) in a tighter pattern (most pellets missed past a few blocks).
        GunSpec(key: "gun_shotgun", name: "Brecher Shotgun", ammo: "shotgun_shells", mag: 10, interval: 0.85, auto: false, damage: 4, pellets: 9,
                spread: 0.065, aimSpread: 0.045, speed: 110, recoil: 0.07, reload: 2.6, range: 45, durability: 500, zoom: 0.9,
                shot: .bullet, sound: 2, accent: V3(0.9, 0.9, 0.88)),
        GunSpec(key: "gun_sniper", name: "Fernblick Rifle", ammo: "heavy_rounds", mag: 8, interval: 1.3, auto: false, damage: 24, pellets: 1,
                spread: 0.06, aimSpread: 0.0006, speed: 320, recoil: 0.09, reload: 2.8, range: 260, durability: 400, zoom: 0.22,
                shot: .bullet, sound: 3, accent: V3(0.9, 0.9, 0.88)),
        GunSpec(key: "gun_launcher", name: "Himmelsturm Launcher", ammo: "rocket_ammo", mag: 2, interval: 1.0, auto: false, damage: 0, pellets: 1,
                spread: 0.02, aimSpread: 0.008, speed: 34, recoil: 0.12, reload: 2.6, range: 160, durability: 150, zoom: 0.85,
                shot: .rocket, sound: 4, accent: V3(0.9, 0.9, 0.88)),
        // H7 ("the shock weapon is as strong as it looks"): 28 a bolt (P312; was 22, before that 14, under a rifle's two shots), and the bolt
        // jumps on to two more targets nearby (Armory.beam).
        GunSpec(key: "gun_arc", name: "Blitzlanze Arc Gun", ammo: "arc_cell", mag: 12, interval: 0.9, auto: false, damage: 28, pellets: 1,
                spread: 0.01, aimSpread: 0, speed: 0, recoil: 0.05, reload: 2.4, range: 48, durability: 300, zoom: 0.75,
                shot: .beam, sound: 5, accent: V3(0.9, 0.9, 0.88)),
        // The Capital officers' and pilots' sidearm (CapitalArms.swift); its own sound slot (WeaponAudio 13). P501 (Oct 31,
        // "semi-automatic, but needs to have a higher rate of fire"): back for the next pull in 0.12 s (was 0.22).
        GunSpec(key: "gun_sidearm", name: "Falke Pistol", ammo: "capital_rounds", mag: 18, interval: 0.12, auto: false, damage: 4, pellets: 1,
                spread: 0.03, aimSpread: 0.009, speed: 140, recoil: 0.03, reload: 1.4, range: 60, durability: 900, zoom: 0.88,
                shot: .bullet, sound: 13, accent: V3(0.9, 0.9, 0.88)),
        // The six-iron: the six-shot frontier revolver every town sheriff carries (SixIron.swift); a killed sheriff drops
        // it a quarter of the time (Honour.sheriffDrops). Never sold, so it's a trophy. Slow, heavy single shots.
        GunSpec(key: "gun_revolver", name: "Sechser Revolver", ammo: "rifle_rounds", mag: 6, interval: 0.42, auto: false, damage: 7, pellets: 1,
                spread: 0.026, aimSpread: 0.006, speed: 150, recoil: 0.065, reload: 2.4, range: 70, durability: 700, zoom: 0.86,
                shot: .bullet, sound: 13, accent: V3(0.36, 0.2, 0.1)),
        // The Ashguard's arms (backlog B7, AshArms.swift): walnut and blued steel, carried by the army in the Ash Vault and
        // dropped by its soldiers; never crafted. Each has its own sound slot (WeaponAudio 16-19). P326 (c, Oct 15 19:04:
        // "their real WWII weapons by name"): the period's own names (docs/status/ip-renames.md).
        GunSpec(key: "gun_kessel", name: "Kessel Bolt Rifle", ammo: "heavy_rounds", mag: 5, interval: 1.15, auto: false, damage: 16, pellets: 1,
                spread: 0.03, aimSpread: 0.0012, speed: 280, recoil: 0.08, reload: 2.6, range: 220, durability: 900, zoom: 0.55,
                shot: .bullet, sound: 16, accent: V3(0.4, 0.22, 0.11)),
        GunSpec(key: "gun_hagel", name: "Hagel Machine Pistol", ammo: "rifle_rounds", mag: 32, interval: 0.11, auto: true, damage: 3, pellets: 1,
                spread: 0.05, aimSpread: 0.028, speed: 120, recoil: 0.008, reload: 1.9, range: 60, durability: 1100, zoom: 0.9,
                shot: .bullet, sound: 17, accent: V3(0.2, 0.2, 0.22)),
        GunSpec(key: "gun_sturmwind", name: "Sturmwind Carbine", ammo: "rifle_rounds", mag: 30, interval: 0.13, auto: true, damage: 4.5, pellets: 1,
                spread: 0.032, aimSpread: 0.008, speed: 150, recoil: 0.014, reload: 2.2, range: 100, durability: 1100, zoom: 0.8,
                shot: .bullet, sound: 18, accent: V3(0.4, 0.22, 0.11)),
        GunSpec(key: "gun_ashsaw", name: "Kettensturm Machine Gun", ammo: "rifle_rounds", mag: 75, interval: 0.055, auto: true, damage: 3.5, pellets: 1,
                spread: 0.075, aimSpread: 0.016, speed: 150, recoil: 0.011, reload: 4.2, range: 110, durability: 1600, zoom: 0.85,
                shot: .bullet, sound: 19, accent: V3(0.2, 0.2, 0.22)),
    ] + GreywallArms.specs + [               // (appended: soldiers keep their gun as an index)
        // P320 (Oct 15 18:54): the Faustrohr (P397: no real model names), the Ashguard's single-shot anti-tank launcher (AshArms.swift): one
        // warhead on the tube, a hard-hitting shaped charge (Slug.antiTank) and a crater, then a slow reload of the next.
        GunSpec(key: "gun_faust", name: "Faustrohr", ammo: "faust_warhead", mag: 1, interval: 1.0, auto: false, damage: 0, pellets: 1,
                spread: 0.03, aimSpread: 0.012, speed: 28, recoil: 0.1, reload: 3.4, range: 90, durability: 40, zoom: 0.9,
                shot: .rocket, sound: 4, accent: V3(0.34, 0.36, 0.22)),
        // P391 (Remington, Oct 21 15:18: "let one of the top classes have a GTA V style mini gun"): the Hannibal trooper's
        // Mahlwerk, a six-barrel rotary gun on a belt. The barrels spin up before the first round (Guns.rotarySpinUp) and
        // run down after the trigger lets go; at speed it puts out about 1700 rounds a minute.
        GunSpec(key: "gun_rotary", name: "Mahlwerk Rotary Gun", ammo: "capital_rounds", mag: 200, interval: 0.035, auto: true, damage: 3, pellets: 1,
                spread: 0.06, aimSpread: 0.04, speed: 150, recoil: 0.0035, reload: 5.0, range: 90, durability: 3000, zoom: 0.92,
                shot: .bullet, sound: 20, accent: V3(0.9, 0.9, 0.88)),
        // P499 (Oct 30 15:14, "Make a, uh, assault shotgun. Make that one of the top level troops guns. So just rapid fire
        // shotguns, shotgun shells"): the Sturmbrecher, a box-fed automatic shotgun the Hannibal troopers carry (a quarter
        // of them); eight pellets a shot, four shots a second, twenty in the box.
        GunSpec(key: "gun_autoshotgun", name: "Sturmbrecher Assault Shotgun", ammo: "shotgun_shells", mag: 20, interval: 0.24, auto: true, damage: 4,
                pellets: 8, spread: 0.075, aimSpread: 0.055, speed: 110, recoil: 0.05, reload: 3.0, range: 42, durability: 800, zoom: 0.9,
                shot: .bullet, sound: 2, accent: V3(0.9, 0.9, 0.88)),
    ]
    static let rifle = 0, smg = 1, shotgun = 2, sniper = 3, launcher = 4, arc = 5, pistol = 6, revolver = 7
    static let kessel = 8, hagel = 9, sturmwind = 10, ashsaw = 11
    static let faust = 12 + GreywallArms.specs.count                                         // P320
    static let rotary = faust + 1                                                            // P391
    static let autoShotgun = rotary + 1                                                      // P499
    // P391: seconds the Mahlwerk's barrels take to come up to speed and to run down; the player walks slower holding it.
    static let rotarySpinUp: Float = 0.5, rotarySpinDown: Float = 1.4, rotaryWalk: Float = 0.72
    static func isAshArm(_ gi: Int) -> Bool { (gi >= kessel && gi <= ashsaw) || gi == faust }
    static func isLauncher(_ gi: Int) -> Bool { gi == launcher || gi == faust }
    static let faustPower: Float = 3.4, faustAntiTank: Float = 90
    static let slatefall = 12, longwatch = 13, needle = 14, breaker = 15, repeater = 16      // Greywall's (GreywallArms.swift)
    static func isGreyArm(_ gi: Int) -> Bool { gi >= slatefall && gi <= repeater }
    // P217 (Oct 13 19:02, "several guns look identical; cut the roster to fewer, clearly different guns"; redone Oct 14:
    // "fewer, clearly different guns, not remapping"): eleven guns, one of each kind:
    //   Capital (white enamel)  Service Rifle (assault rifle), Brecher (pump shotgun), Fernblick (scoped marksman
    //                           rifle), Himmelsturm (rocket launcher), Blitzlanze (arc gun), Falke (service automatic)
    //   frontier / Ashguard     Sechser six-iron (single-action revolver), Kessel (bolt-action rifle), Sturmwind
    //                           (assault carbine with a curved magazine)
    //   Greywall                Slatefall (bullpup carbine), Slate Repeater (light machine gun)
    // The Hummel, Wren, Kettensturm, Longwatch and Breaker are gone: they are no longer items at all (not in creative,
    // chests, shops, drops or recipes). (P326: the machine pistol is back as the Ashguard's Hagel, its own look.) Their keys stay save IDs: a stack saved with one loads as its
    // replacement (SaveMigration.itemAliases), and a soldier saved carrying one is issued the replacement.
    //   capital rounds: Service Rifle, Falke Pistol          slate rounds: Slatefall Carbine, Slate Repeater
    //   heavy rounds: Fernblick, Kessel                      rifle rounds: Six-Iron, Sturmwind Carbine
    //   shotgun shells: Brecher Shotgun                      arc cells: Blitzlanze Arc Gun     rockets: launcher
    static let retired: [Int: Int] = [smg: rifle, needle: revolver, ashsaw: sturmwind, longwatch: kessel, breaker: revolver]
    static func current(_ gi: Int) -> Int { retired[gi] ?? gi }
    static let retiredKeys: [String: String] = ["gun_smg": "gun_rifle", "gun_needle": "gun_revolver",
                                                "gun_ashsaw": "gun_sturmwind", "gun_longwatch": "gun_kessel", "gun_breaker": "gun_revolver"]
    static func isRetired(_ gi: Int) -> Bool { retired[gi] != nil }
    static let revolverKey = "gun_revolver"
    // Held in one hand on the march, two when aimed (soldier rig, pose checks).
    static func isHandgun(_ gi: Int) -> Bool { gi == pistol || gi == revolver }
    // capital_rounds (P40): the Capital's service rifle, Chatter Gun and sidearm fire their own rounds, never sold (looted
    // from Capital soldiers and citadels); rifle rounds are the frontier's (the six-iron, the Ashguard's arms).
    static let ammo: [(String, String)] = [("rifle_rounds", "Rifle Rounds"), ("shotgun_shells", "Shotgun Shells"), ("heavy_rounds", "Heavy Rounds"),
                                           ("rocket_ammo", "Rocket"), ("arc_cell", "Arc Cell"), ("capital_rounds", "Capital Rounds"),
                                           (GreywallArms.ammo, "Slate Rounds"), ("faust_warhead", "Faustrohr Warhead")]
    static let rocketPower: Float = 2.5

    private(set) static var byItem: [ItemID: Int] = [:]
    static func index(_ i: ItemID) -> Int? { byItem[i] }

    static func register(_ reg: ItemRegistry) {
        for (n, disp) in ammo where !reg.has(n) {
            var d = ItemDef(n, disp)
            d.texKey = "item_" + n
            d.maxStack = n == "rocket_ammo" || n == "faust_warhead" ? 16 : 64
            reg.add(d)
        }
        for (k, to) in retiredKeys { SaveMigration.itemAliases[k] = to }
        for (i, g) in all.enumerated() where !reg.has(g.key) && !isRetired(i) {
            var d = ItemDef(g.key, g.name)
            d.texKey = "item_" + g.key
            d.maxStack = 1
            d.durability = g.durability
            d.attack = 2
            d.attackSpeed = 1.2
            byItem[reg.add(d)] = i
        }
    }

    // Ammunition is crafted; guns need components looted at Capital citadels.
    static func recipes() -> [Recipe?] {
        [Recipes.shapeless(["iron_ingot", "copper_ingot", "gunpowder"], "rifle_rounds", 16),
         // P120 (Oct 12 PM: "I'm gonna make some capital rounds, this is my favourite... I can't make them"): steel cases,
         // so dearer than rifle rounds.
         Recipes.shapeless(["steel_ingot", "copper_ingot", "gunpowder", "gunpowder"], "capital_rounds", 12),
         Recipes.shapeless(["paper", "gunpowder", "iron_nugget", "iron_nugget"], "shotgun_shells", 6),
         Recipes.shapeless(["iron_ingot", "iron_ingot", "gunpowder", "gunpowder"], "heavy_rounds", 5),
         Recipes.shaped([" I ", "ITI", "IGI"], ["I": "iron_ingot", "T": "tnt", "G": "gunpowder"], "rocket_ammo", 2),
         Recipes.shapeless(["copper_ingot", "redstone", "redstone", "gold_nugget"], "arc_cell", 4),
         // P320: the Faustrohr is a cheap tube anyone can make (no citadel parts); its warhead takes TNT.
         Recipes.shaped(["  I", "ILI", "I  "], ["I": "iron_ingot", "L": "lever"], "gun_faust"),
         Recipes.shapeless(["tnt", "iron_ingot", "iron_ingot", "copper_ingot"], "faust_warhead", 2),
         // Guns (task 23): only with components from Capital citadels (FactionGear.swift).
         Recipes.shapeless(["steel_ingot", "steel_ingot", "firing_mechanism"], "gun_sidearm"),
         Recipes.shapeless(["steel_ingot", "steel_ingot", "steel_ingot", "steel_ingot", "firing_mechanism"], "gun_rifle"),
         Recipes.shapeless(["steel_ingot", "steel_ingot", "steel_ingot", "iron_ingot", "iron_ingot", "firing_mechanism"], "gun_shotgun"),
         Recipes.shapeless(["steel_ingot", "steel_ingot", "steel_ingot", "steel_ingot", "firing_mechanism", "targeting_optic"], "gun_sniper"),
         Recipes.shapeless(["steel_ingot", "steel_ingot", "steel_ingot", "steel_ingot", "steel_ingot", "tnt", "firing_mechanism", "targeting_optic"], "gun_launcher"),
         Recipes.shapeless(["steel_ingot", "steel_ingot", "redstone", "redstone", "gold_ingot", "firing_mechanism", "targeting_optic"], "gun_arc"),
         Recipes.shapeless(["steel_ingot", "steel_ingot", "steel_ingot", "steel_ingot", "steel_ingot", "steel_ingot", "redstone", "firing_mechanism", "firing_mechanism"], "gun_rotary"),
         Recipes.shapeless(["steel_ingot", "steel_ingot", "steel_ingot", "steel_ingot", "steel_ingot", "iron_ingot", "firing_mechanism", "firing_mechanism"], "gun_autoshotgun"),
         Recipes.shapeless(["radar_module", "compass", "steel_ingot", "steel_ingot", "redstone"], "radar_set"),
         Recipes.shapeless(["radar_module", "copper_ingot", "copper_ingot", "redstone", "redstone"], Navy.pulseKey, 2)]
    }

    // Enchantment-adjusted numbers (Extended Magazine, Quick Reload, Stability); NPC guns carry no enchantments.
    static func magSize(_ s: ItemStack) -> Int {
        guard let gi = index(s.item) else { return 0 }
        let base = all[gi].mag
        let l = Enchant.level(.extendedMag, s)
        guard l > 0 else { return base }
        return max(base + 1, Int((Float(base) * (1 + 0.25 * Float(l))).rounded(.up)))
    }
    static func reloadTime(_ s: ItemStack, _ gi: Int) -> Float { all[gi].reload * (1 - 0.18 * Float(Enchant.level(.quickReload, s))) * GunGrade.reload(s) }
    // P454 (Oct 25 14:07, the Sturmwind: "shouldn't be a sight on the Sturmgewehr. This thing wouldn't have a sight"): the
    // Ashguard's automatic arms keep their iron sights: no scope is fitted (gunsmith, loot or an older save's).
    static let ironSightsOnly: Set<String> = ["gun_sturmwind", "gun_hagel", "gun_ashsaw"]
    static func steadiness(_ s: ItemStack) -> Float { (1 - 0.18 * Float(Enchant.level(.stability, s))) * Legendaries.recoilScale(s) * GunGrade.recoil(s) }

    // Tooltip lines for a gun: loaded rounds, ammunition, damage and fire rate.
    static func tooltip(_ s: ItemStack) -> [String] {
        guard let gi = index(s.item) else { return [] }
        let g = all[gi]
        let ammoName = Items.has(g.ammo) ? Items.def(Items.id(g.ammo)).display : g.ammo
        var out = ["Loaded: \(s.tag) / \(magSize(s))", "Takes: \(ammoName)"]          // (P328: no "Get it:" line)
        switch g.shot {
        case .bullet:
            let dmg = g.pellets > 1 ? "\(Int(g.damage)) x \(g.pellets)" : "\(Int(g.damage))"
            out.append("Damage: \(dmg)")
        case .rocket: out.append("Explosive rockets")
        case .beam: out.append("Damage: \(Int(g.damage)), ignites")
        }
        out.append(g.auto ? String(format: "Automatic, %.0f rounds/s", 1 / g.interval) : String(format: "%.1f shots/s", 1 / g.interval))
        if let q = GunGrade.tooltip(s) { out.append(q) }
        return out
    }

    // A direction inside a cone of half-angle `spread` around `d`.
    static func scatter(_ d: V3, _ spread: Float) -> V3 {
        guard spread > 0 else { return d }
        let ref = abs(d.y) < 0.95 ? V3(0, 1, 0) : V3(1, 0, 0)
        let a = simd_normalize(simd_cross(d, ref)), b = simd_cross(d, a)
        let r = spread * sqrtf(Rand.float(in: 0..<1)), t = Rand.float(in: 0..<(2 * .pi))
        return simd_normalize(d + a * (cosf(t) * r) + b * (sinf(t) * r))
    }

    // MARK: Models (pixels; grip at the origin, barrel towards -Z)

    static let metal = V3(0.25, 0.26, 0.28), dark = V3(0.12, 0.12, 0.14)

    // The Capital finish models (CapitalArms.swift), shared with the soldiers' hands.
    static let models: [[Part]] = CapitalArms.models.map { $0.parts }
    static let magParts: [Set<Int>] = CapitalArms.models.map { Set($0.mag) }
    static let slideParts: [Set<Int>] = CapitalArms.models.map { Set($0.slide) }      // P301
    static let spinParts: [Set<Int>] = CapitalArms.models.map { Set($0.spin) }        // P391
    // Ammo light on the left of the receiver (the shooter's side): warm white with rounds in, red when empty.
    static let indicator: [Part] = CapitalArms.models.map { m in
        let r = m.parts[0]
        let y = r.mn.y + (r.mx.y - r.mn.y) * 0.62
        return Part(mn: V3(r.mn.x - 0.12, y, r.mn.z + 1.2), mx: V3(r.mn.x + 0.02, y + 0.55, r.mn.z + 4.2), color: CapitalArms.glow, pattern: CapitalArms.pGlow)
    }
    static let order = [0, 1, 2, 0, 2, 3]
    static let faceShade: [Float] = [0.8, 0.8, 1.0, 0.55, 0.68, 0.68]

    // First-person gun, written straight into a mob-pipeline vertex buffer (view space).
    /// `rounds` 0 hides the magazine and turns the ammo light red; `scale` enlarges the model (Quest: held in the hand).
    /// P301: `slide` (0 home ... 1 back) draws a pistol's slide pulled back; an empty pistol shows it locked back.
    static func writeFirstPerson(_ gi: Int, aim: Float, kick: Float, lower: Float, bob: V3, light: Float, rounds: Int = 1,
                                 scale: Float = 1, upgrades: UInt64 = 0, slide: Float = 0, spin: Float = 0, into out: UnsafeMutablePointer<MobVert>) -> Int {
        let CT = Mesher.cornerTable
        let hip = V3(0.2, -0.2, -0.5), ads = V3(0, -0.085, -0.44)   // a little below the line of sight: the top and barrel show (at -0.05 only the stock's back face did: critic, run 385 gun_aim)
        let sway: V3 = bob * (1 - aim * 0.8)
        let recoil = V3(0, 0.012 * kick - 0.25 * lower, 0.06 * kick)
        let at: V3 = hip + (ads - hip) * aim + sway + recoil
        let yawR: Float = (1 - aim) * 0.07
        let pitchR: Float = kick * 0.07 - lower * 0.6
        let cy = cosf(yawR), sy = sinf(yawR), cp = cosf(pitchR), sp = sinf(pitchR)
        let s: Float = 0.0125 * scale
        var n = 0
        var ind = indicator[gi]
        if rounds <= 0 { ind.color = V3(1.9, 0.25, 0.18) }
        // R9 (Oct 13: "the six-iron looks nothing like one; not futuristic"): the glowing ammo light is the Capital's
        // (its energy-era arms only). On the six-iron it sat as a lit strip down the barrel's side, and the frontier,
        // Ashguard and Greywall guns carried it too; they show their state by the magazine alone.
        // P501 (Oct 31 09:47, the Falke: "there's parts floating in the air... it just doesn't look good"): the service
        // automatic is the classic pattern (P157), so its lit strip, which stood proud of the slide's top edge, is gone too.
        let lit = gi < Guns.pistol
        // Upgrades show (Upgrades.gunParts: a scope, a longer magazine, a band for special rounds, a loader lever).
        let extra = upgradeParts(gi, upgrades, magOut: rounds <= 0)
        let slid: Float = max(slide, rounds <= 0 ? 1 : 0) * CapitalArms.models[gi].slideTravel
        let indAt = models[gi].count + extra.count                               // (the ammo light sits on the slide)
        for (pi, p0) in (models[gi] + extra + (lit ? [ind] : [])).enumerated() {
            if rounds <= 0 && magParts[gi].contains(pi) { continue }            // empty: the magazine is out
            var p = p0
            if slid > 0 && (slideParts[gi].contains(pi) || pi == indAt) {        // P301: the slide drawn back
                p.mn.z += slid; p.mx.z += slid; p.pivot.z += slid
            }
            if spin != 0 && spinParts[gi].contains(pi) { p = CapitalArms.spun(p, spin, gi) }   // P391: the barrels turn
            let size = p.mx - p.mn
            let ca = cosf(p.rotX), sa = sinf(p.rotX)
            for f in 0..<6 {
                for k in order {
                    let ci = (f * 4 + k) * 3
                    let lp = p.mn + size * V3(Float(CT[ci]), Float(CT[ci + 1]), Float(CT[ci + 2]))
                    var q = lp - p.pivot
                    q = V3(q.x, q.y * ca - q.z * sa, q.y * sa + q.z * ca) + p.pivot
                    q = V3(q.x, q.y * cp - q.z * sp, q.y * sp + q.z * cp)
                    q = V3(q.x * cy + q.z * sy, q.y, -q.x * sy + q.z * cy)
                    out[n] = MobVert(pos: V4(at + q * s, p.pattern), color: V4(p.color, faceShade[f] * light), local: V4(lp * 2, 0))
                    n += 1
                }
            }
        }
        return n
    }

    // The upgrade parts per gun and upgrade set, made once (the first-person model is drawn every frame).
    private static var upgradeCache: [Int: [Part]] = [:]
    static func upgradeParts(_ gi: Int, _ ench: UInt64, magOut: Bool) -> [Part] {
        guard ench != 0 else { return [] }
        let key = Int(truncatingIfNeeded: ench &* 31 &+ UInt64(gi) &* 2 &+ (magOut ? 1 : 0))
        if let p = upgradeCache[key] { return p }
        let shown = ironSightsOnly.contains(all[gi].key) ? Enchant.pack(Enchant.list(ench).filter { $0.0 != .stability }) : ench
        var p = Upgrades.gunParts(models[gi], mag: magParts[gi], shown)
        if magOut { p = p.filter { q in !magParts[gi].contains { models[gi][$0].mn.x == q.mn.x && models[gi][$0].mx.x == q.mx.x && models[gi][$0].mn.z == q.mn.z } } }
        if upgradeCache.count > 64 { upgradeCache = [:] }
        upgradeCache[key] = p
        return p
    }

    // MARK: Icons and sounds

    static let icons: [String: [String]] = [
        "gun_rifle": ["................", "................", "................", "................", ".......1111.....",
                      ".11...1dddd1....", "1aa111mmmmm11111", "1aaammmmmmmaaa1.", ".1aa1mmmmmaaa1..", "..11.1d1dd111...",
                      ".....1d11dd1....", ".....1d1.dd1....", "......1..11.....", "................", "................", "................"],
        "gun_smg": ["................", "................", "................", "................", "................",
                    "......1111......", "....11mmmm1111..", "..11aaaaaammmm1.", "..1a1mmmmmm11...", "..11.1d1dd1.....",
                    ".....1d11dd1....", ".....111.dd1....", "........1dd1....", "........1dd1....", ".........11.....", "................"],
        "gun_shotgun": ["................", "................", "................", "................", "................",
                        "..............y.", "11.....11111111y", "aa11111mmmmmmmm1", "aaaaddddaaaaa11.", "1aa11d1d1aaaa1..",
                        ".11..1d1.1111...", ".....1d1........", "......1.........", "................", "................", "................"],
        "gun_sniper": ["................", "................", "................", "......11111.....", ".....1ddddg1....",
                       "......11111.....", "11...11mm1......", "aa111aaaa1111111", "aaaaaaaaammmmmd1", "1aa1d1d11111111.",
                       ".11.1d11d1......", "....1d1.1d1.....", ".....1..1.1.....", "................", "................", "................"],
        "gun_launcher": ["................", "................", "................", "................", "...1111111111...",
                         "..1aaaaaaaaaaa1.", "11aaaaaaaaaaaaa1", "1daaaaayyyaaaad1", "11aaaaaaaaaaaaa1", "..1aaaaaaaaaaa1.",
                         "...111d1111d1...", "......1d1..1d1..", "......111..111..", "................", "................", "................"],
        "gun_arc": ["................", "................", "................", "................", ".......1111.....",
                    "...111mmmmm1....", "..1aaagagagaa111", "..1aaagagagaaddd", "..1aa1gagag111..", "..11.1gg1.......",
                    ".....1gg1d1.....", "......11.dd1....", ".........11.....", "................", "................", "................"],
        "rifle_rounds": ["................", "................", "................", "....b.....b.....", "...bbb...bbb....",
                         "...bbb...bbb..b.", "...yyy...yyy.bbb", "...yyy...yyy.bbb", "...yyy...yyy.yyy", "...yyy...yyy.yyy",
                         "...yyy...yyy.yyy", "...ddd...ddd.yyy", ".............yyy", ".............ddd", "................", "................"],
        "capital_rounds": ["................", "................", "................", "....b.....b.....", "...bbb...bbb....",
                         "...bbb...bbb..b.", "...www...www.bbb", "...www...www.bbb", "...www...www.www", "...www...www.www",
                         "...www...www.www", "...ddd...ddd.www", ".............www", ".............ddd", "................", "................"],
        "shotgun_shells": ["................", "................", "................", "................", "...rrr...rrr....",
                           "...rrr...rrr....", "...rrr...rrr....", "...rrr...rrr....", "...rrr...rrr....", "...rrr...rrr....",
                           "...yyy...yyy....", "...yyy...yyy....", "................", "................", "................", "................"],
        "heavy_rounds": ["................", "................", ".....b.....b....", "....bbb...bbb...", "....bbb...bbb...",
                         "....bbb...bbb...", "....yyy...yyy...", "....yyy...yyy...", "....yyy...yyy...", "....yyy...yyy...",
                         "....yyy...yyy...", "....yyy...yyy...", "....yyy...yyy...", "....ddd...ddd...", "................", "................"],
        "faust_warhead": ["................", "................", "......1111......", ".....1aaaa1.....", "....1aaaaaa1....",
                          "....1aaayaa1....", "....1aaaaaa1....", ".....1aaaa1.....", "......1dd1......", "......1dd1......",
                          "......1dd1......", "......1dd1......", ".....11dd11.....", "....1d1dd1d1....", "....11.11.11....", "................"],
        "rocket_ammo": ["................", "..............rr", ".............rrr", "............aaar", "...........aaa..",
                        "..........aaa...", ".........aaa....", "........aaa.....", ".......aaa......", "......aaa.......",
                        ".....aaa........", "...ddaa.........", "..dddd..........", "..ddd...........", "..yd............", ".yy............."],
        "gun_sidearm": ["................", "................", "................", "................", "................",
                        "...11111111111..", "...1dddddddddd1.", "...1aaaaaaaaaa1.", "...1aaa1m1111...", "...1aaa1.m1.....",
                        "..1aaa11.1......", "..1aaa1.........", "..1aaa1.........", "..11111.........", "................", "................"],
        // (Oct 11 playtest P29: the grip sloped toward the muzzle, so it read as a gun held backwards.) Muzzle right
        // like the sidearm; the cylinder over the trigger; the grip raked back under the hammer.
        "gun_revolver": ["................", "................", "................", "................", ".1............1.",
                         "..111111111111..", ".1dd1mmmmmmmmm1.", ".1dddd11111111..", "..1dddd1.1......", "..1aa111m1......",
                         ".1aaa1.11.......", ".1aaa1..........", "1aaa1...........", "1111............", "................", "................"],
        "arc_cell": ["................", "................", "......1111......", ".....1mmmm1.....", "....1111111.....",
                     "....1gggggg1....", "....1gddddg1....", "....1gggggg1....", "....1gddddg1....", "....1gggggg1....",
                     "....1gddddg1....", "....1gggggg1....", "....11111111....", "................", "................", "................"],
    ]

    // P217 (Oct 13 18:35, "the gun in my hand doesn't match its icon"): a gun's icon is drawn from its own model,
    // side on (barrel to the left), each box in its colour with the near side over the far, and a dark outline. The
    // hand-drawn masks stay for ammunition.
    static func modelIcon(_ gi: Int) -> [[V4]] {
        let parts = models[gi]
        var lo = V2(1e9, 1e9), hi = V2(-1e9, -1e9)
        for q in parts { lo = simd_min(lo, V2(q.mn.z, q.mn.y)); hi = simd_max(hi, V2(q.mx.z, q.mx.y)) }
        var img = [[V4]](repeating: [V4](repeating: V4(0, 0, 0, 0), count: 16), count: 16)
        guard hi.x > lo.x, hi.y > lo.y else { return img }
        let k: Float = 14 / max(hi.x - lo.x, hi.y - lo.y)
        let ox: Float = (16 - (hi.x - lo.x) * k) / 2, oy: Float = (16 - (hi.y - lo.y) * k) / 2
        for q in parts.sorted(by: { $0.mn.x > $1.mn.x }) {       // (seen from -x: barrel left, the -x side nearest)
            let x0 = Int(floor((q.mn.z - lo.x) * k + ox)), x1 = max(x0, Int(ceil((q.mx.z - lo.x) * k + ox)) - 1)
            let y0 = Int(floor((hi.y - q.mx.y) * k + oy)), y1 = max(y0, Int(ceil((hi.y - q.mn.y) * k + oy)) - 1)
            let c = simd_min(q.color, V3(1, 1, 1))
            for y in max(0, y0)...min(15, max(0, y1)) { for x in max(0, x0)...min(15, max(0, x1)) {
                let top: Float = y == y0 ? 1.12 : 1                        // a lit top edge on each part
                img[y][x] = V4(simd_min(c * top, V3(1, 1, 1)), 1)
            } }
        }
        let filled = img.map { $0.map { $0.w > 0 } }
        for y in 0..<16 { for x in 0..<16 where !filled[y][x] {
            let n = (x > 0 && filled[y][x - 1]) || (x < 15 && filled[y][x + 1]) || (y > 0 && filled[y - 1][x]) || (y < 15 && filled[y + 1][x])
            if n { img[y][x] = V4(0.06, 0.06, 0.07, 1) }
        } }
        return img
    }

    // P217 redo (Oct 14, "the held model matches the icon"): at the GPU's texture size (128 px) the icon is drawn from
    // the held model itself instead of upscaling the 16 px one: every box side on in its own colour and finish, near
    // over far, lit from above (a bright top edge, a darker underside, grain on wood, a sheen on metal), outlined.
    // Even the trigger, sights and screws of the gun in the hand show in the hotbar.
    static func iconHD(_ gi: Int, _ n: Int) -> HDTex.Img {
        var img = HDTex.Img(n, V4(0, 0, 0, 0))
        let parts = models[gi]
        var lo = V2(1e9, 1e9), hi = V2(-1e9, -1e9)
        for q in parts { lo = simd_min(lo, V2(q.mn.z, q.mn.y)); hi = simd_max(hi, V2(q.mx.z, q.mx.y)) }
        guard hi.x > lo.x, hi.y > lo.y else { return img }
        let nf = Float(n)
        let edge = max(1, n / 48)
        let span: Float = max(hi.x - lo.x, hi.y - lo.y)
        let k: Float = (nf - Float(edge * 2 + 2)) / span
        let ox: Float = (nf - (hi.x - lo.x) * k) / 2, oy: Float = (nf - (hi.y - lo.y) * k) / 2
        for q in parts.sorted(by: { $0.mn.x > $1.mn.x }) {                 // seen from -x: barrel left, the near side last
            let fx0: Float = (q.mn.z - lo.x) * k + ox, fx1: Float = (q.mx.z - lo.x) * k + ox
            let fy0: Float = (hi.y - q.mx.y) * k + oy, fy1: Float = (hi.y - q.mn.y) * k + oy
            let x0 = Int(fx0.rounded(.down)), x1 = max(x0, Int(fx1.rounded(.up)) - 1)
            let y0 = Int(fy0.rounded(.down)), y1 = max(y0, Int(fy1.rounded(.up)) - 1)
            // P232: dark gunmetal lifted a little, so a black-finished gun still reads on the dark inventory slot.
            let base = simd_min(q.color * 0.82 + V3(repeating: 0.12), V3(1, 1, 1))
            let rows = Float(max(1, y1 - y0))
            for y in max(0, y0)...min(n - 1, max(0, y1)) {
                let t = Float(y - y0) / rows                                   // 0 top .. 1 bottom
                var shade: Float = 1.06 - 0.22 * t
                if y - y0 < edge { shade = 1.22 }                              // lit top edge
                if y1 - y < edge && y1 - y0 > edge * 3 { shade *= 0.72 }       // underside in shadow
                for x in max(0, x0)...min(n - 1, max(0, x1)) {
                    var s = shade
                    if q.pattern == 10 { s *= 0.9 + 0.12 * sinf(Float(x) * 0.21 + sinf(Float(y) * 0.9) * 1.6) }   // wood grain
                    if q.pattern == 8 && abs(t - 0.3) < 0.08 { s *= 1.12 }                                          // metal sheen
                    if q.pattern == 7 { s *= 0.98 + 0.04 * hashf(x / 3, y / 3, gi, 77) }                             // enamel
                    img[x, y] = V4(simd_min(base * s, V3(1, 1, 1)), 1)
                }
            }
        }
        // Outline: a dark rim round the silhouette, `edge` texels thick.
        let filled = img.px.map { $0.w > 0 }
        for y in 0..<n { for x in 0..<n where !filled[y * n + x] {
            var near = false
            for dy in -edge...edge where !near { for dx in -edge...edge {
                let xx = x + dx, yy = y + dy
                if xx >= 0, xx < n, yy >= 0, yy < n, filled[yy * n + xx] { near = true; break }
            } }
            if near { img[x, y] = V4(0.05, 0.05, 0.06, 1) }
        } }
        return img
    }

    static func painters(_ p: inout [String: TextureGen.Painter]) {
        for (gi, g) in all.enumerated() where !isRetired(gi) {
            let img = modelIcon(gi)
            p["item_" + g.key] = { x, y in
                guard y >= 0, y < 16, x >= 0, x < 16, img[y][x].w > 0 else { return TextureGen.clear }
                let h = 0.94 + 0.06 * hashf(x, y, 31, 4242)
                let c = img[y][x]
                return V4(c.x * h, c.y * h, c.z * h, 1)
            }
        }
        for (k, rows) in icons.merging(AshArms.icons, uniquingKeysWith: { a, _ in a }).merging(GreywallArms.icons, uniquingKeysWith: { a, _ in a })
            .merging([ShipShells.key: ShipShells.icon], uniquingKeysWith: { a, _ in a })
            where !all.contains(where: { $0.key == k }) {
            let accent = all.first { $0.key == k }?.accent ?? V3(0.35, 0.4, 0.25)
            let grid = rows.map { Array($0) }
            p["item_" + k] = { x, y in
                guard y < grid.count, x < grid[y].count else { return TextureGen.clear }
                let h = 0.92 + 0.08 * hashf(x, y, 31, 4242)
                switch grid[y][x] {
                case "1": return V4(0.08, 0.08, 0.09, 1)
                case "d": return V4(0.18 * h, 0.18 * h, 0.2 * h, 1)
                case "m": return V4(0.42 * h, 0.44 * h, 0.47 * h, 1)
                case "a": return V4(accent.x * h, accent.y * h, accent.z * h, 1)
                case "g": return V4(1, 0.93, 0.72, 1)                         // (P217: warm glow, no cyan)
                case "y": return V4(0.86 * h, 0.68 * h, 0.25 * h, 1)
                case "w": return V4(0.85 * h, 0.85 * h, 0.83 * h, 1)             // the Capital's white cases
                case "b": return V4(0.72 * h, 0.5 * h, 0.3 * h, 1)
                case "r": return V4(0.7 * h, 0.14 * h, 0.12 * h, 1)
                default: return TextureGen.clear
                }
            }
        }
    }

    static let soundCount = 23      // 14 loaded (bolt home), 15 last round (bolt locks open), 16-19 the Ashguard's arms, 20-22 the Mahlwerk (P391)
    static var sounds: [Snd] { (0..<soundCount).map { Snd.gun($0) } }
}

extension Synth {
    // 0 rifle, 1 chatter gun, 2 shotgun, 3 farsight, 4 rocket, 5 arc lance, 6 reload, 7 dry fire,
    // 8 ricochet, 9 deck gun, 10 alarm, 11 radio call, 12 turret whine.
    mutating func gunSound(_ k: Int, _ p: Float) -> [Float] {
        switch k {
        case 0: return Synth.mix(burst(0.25, lp: 3600 * p, hp: 140, attack: 0.001, decay: 0.04, gain: 3), burst(0.6, lp: 520, hp: 40, decay: 0.14, gain: 1.6))
        case 1: return Synth.mix(burst(0.14, lp: 4200 * p, hp: 320, attack: 0.001, decay: 0.022, gain: 2.6), burst(0.3, lp: 760, hp: 50, decay: 0.06, gain: 1.1))
        case 2:
            let blast = Synth.mix(burst(0.7, lp: 1500 * p, hp: 45, attack: 0.001, decay: 0.13, gain: 3.6), burst(0.2, lp: 5200, hp: 800, decay: 0.03, gain: 1.2))
            let pump = Synth.mix(modes(0.06, [(900 * p, 0.3, 0.012)]), modes(0.06, [(1300 * p, 0.3, 0.01)]), at: frames(0.12))
            return Synth.mix(blast, pump, at: frames(0.38))
        case 3: return Synth.mix(burst(0.12, lp: 9000, hp: 1600, attack: 0.0005, decay: 0.012, gain: 3), burst(1.5, lp: 380 * p, hp: 28, decay: 0.38, gain: 2.6))
        case 4: return Synth.mix(burst(0.3, lp: 900 * p, hp: 60, attack: 0.002, decay: 0.08, gain: 3), burst(1.3, lp: 3200, hp: 600, attack: 0.05, decay: 0.5, gain: 1.2))
        case 5: return Synth.mix(voice(0.42, f0: 1900 * p, f1: 320 * p, vib: 0.2, lp: 7000, gain: 0.8), burst(0.35, lp: 9000, hp: 2600, attack: 0.002, decay: 0.09, gain: 1.1))
        case 6:
            var out = modes(0.06, [(1400 * p, 0.3, 0.01)])
            out = Synth.mix(out, Synth.mix(burst(0.05, lp: 2500, hp: 400, decay: 0.01, gain: 0.8), modes(0.08, [(700 * p, 0.35, 0.02)])), at: frames(0.45))
            return Synth.mix(out, Synth.mix(modes(0.07, [(1700 * p, 0.3, 0.012)]), modes(0.07, [(1100 * p, 0.3, 0.012)]), at: frames(0.08)), at: frames(0.9))
        case 7: return modes(0.05, [(2400 * p, 0.3, 0.006), (3700 * p, 0.1, 0.004)])
        case 8: return Synth.mix(burst(0.08, lp: 6000, hp: 1500, attack: 0.001, decay: 0.012, gain: 1.2), voice(0.25, f0: 2600 * p, f1: 1300 * p, vib: 0, lp: 6000, gain: 0.25))
        case 9: return Synth.mix(burst(2.8, lp: 170 * p, hp: 14, attack: 0.002, decay: 0.85, gain: 5), burst(0.5, lp: 2600, hp: 200, decay: 0.08, gain: 1.6))
        case 10:
            let up = voice(0.9, f0: 560, f1: 880, vib: 0, lp: 3200, gain: 0.7)
            return Synth.mix(up, voice(0.9, f0: 560, f1: 880, vib: 0, lp: 3200, gain: 0.7), at: frames(1.0))
        case 11: return Synth.mix(voice(0.5, f0: 165 * p, f1: 140 * p, vib: 0.3, lp: 1700, gain: 0.9), burst(0.55, lp: 7000, hp: 2200, attack: 0.01, decay: 0.3, gain: 0.35))
        default: return voice(1.0, f0: 220 * p, f1: 760 * p, vib: 0.02, lp: 2400, gain: 0.5)
        }
    }
}
