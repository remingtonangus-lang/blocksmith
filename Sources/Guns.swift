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
        GunSpec(key: "gun_rifle", name: "Capital Service Rifle", ammo: "rifle_rounds", mag: 45, interval: 0.12, auto: true, damage: 5, pellets: 1,
                spread: 0.022, aimSpread: 0.005, speed: 160, recoil: 0.013, reload: 2.0, range: 110, durability: 1200, zoom: 0.78,
                shot: .bullet, sound: 0, accent: V3(0.9, 0.9, 0.88)),
        GunSpec(key: "gun_smg", name: "Chatter Gun", ammo: "rifle_rounds", mag: 60, interval: 0.07, auto: true, damage: 3, pellets: 1,
                spread: 0.045, aimSpread: 0.026, speed: 130, recoil: 0.009, reload: 1.6, range: 70, durability: 1500, zoom: 0.9,
                shot: .bullet, sound: 1, accent: V3(0.9, 0.9, 0.88)),
        GunSpec(key: "gun_shotgun", name: "Breach Shotgun", ammo: "shotgun_shells", mag: 10, interval: 0.85, auto: false, damage: 3, pellets: 9,
                spread: 0.09, aimSpread: 0.07, speed: 110, recoil: 0.07, reload: 2.6, range: 40, durability: 500, zoom: 0.9,
                shot: .bullet, sound: 2, accent: V3(0.9, 0.9, 0.88)),
        GunSpec(key: "gun_sniper", name: "Farsight Rifle", ammo: "heavy_rounds", mag: 8, interval: 1.3, auto: false, damage: 24, pellets: 1,
                spread: 0.06, aimSpread: 0.0006, speed: 320, recoil: 0.09, reload: 2.8, range: 260, durability: 400, zoom: 0.22,
                shot: .bullet, sound: 3, accent: V3(0.9, 0.9, 0.88)),
        GunSpec(key: "gun_launcher", name: "Skybreaker Launcher", ammo: "rocket_ammo", mag: 2, interval: 1.0, auto: false, damage: 0, pellets: 1,
                spread: 0.02, aimSpread: 0.008, speed: 34, recoil: 0.12, reload: 2.6, range: 160, durability: 150, zoom: 0.85,
                shot: .rocket, sound: 4, accent: V3(0.9, 0.9, 0.88)),
        GunSpec(key: "gun_arc", name: "Arc Lance", ammo: "arc_cell", mag: 12, interval: 0.9, auto: false, damage: 14, pellets: 1,
                spread: 0.01, aimSpread: 0, speed: 0, recoil: 0.05, reload: 2.4, range: 48, durability: 300, zoom: 0.75,
                shot: .beam, sound: 5, accent: V3(0.86, 0.88, 0.92)),
        // The Capital officers' and pilots' sidearm (CapitalArms.swift); its own sound slot (WeaponAudio 13).
        GunSpec(key: "gun_sidearm", name: "Capital Sidearm", ammo: "rifle_rounds", mag: 18, interval: 0.22, auto: false, damage: 4, pellets: 1,
                spread: 0.03, aimSpread: 0.009, speed: 140, recoil: 0.03, reload: 1.4, range: 60, durability: 900, zoom: 0.88,
                shot: .bullet, sound: 13, accent: V3(0.9, 0.9, 0.88)),
    ]
    static let rifle = 0, smg = 1, shotgun = 2, sniper = 3, launcher = 4, arc = 5, pistol = 6
    static let ammo: [(String, String)] = [("rifle_rounds", "Rifle Rounds"), ("shotgun_shells", "Shotgun Shells"), ("heavy_rounds", "Heavy Rounds"),
                                           ("rocket_ammo", "Rocket"), ("arc_cell", "Arc Cell")]
    static let rocketPower: Float = 2.5

    private(set) static var byItem: [ItemID: Int] = [:]
    static func index(_ i: ItemID) -> Int? { byItem[i] }

    static func register(_ reg: ItemRegistry) {
        for (n, disp) in ammo where !reg.has(n) {
            var d = ItemDef(n, disp)
            d.texKey = "item_" + n
            d.maxStack = n == "rocket_ammo" ? 16 : 64
            reg.add(d)
        }
        for (i, g) in all.enumerated() where !reg.has(g.key) {
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
         Recipes.shapeless(["paper", "gunpowder", "iron_nugget", "iron_nugget"], "shotgun_shells", 6),
         Recipes.shapeless(["iron_ingot", "iron_ingot", "gunpowder", "gunpowder"], "heavy_rounds", 5),
         Recipes.shaped([" I ", "ITI", "IGI"], ["I": "iron_ingot", "T": "tnt", "G": "gunpowder"], "rocket_ammo", 2),
         Recipes.shapeless(["copper_ingot", "redstone", "redstone", "gold_nugget"], "arc_cell", 4),
         // Guns (task 23): only with components from Capital citadels (FactionGear.swift).
         Recipes.shapeless(["steel_ingot", "steel_ingot", "firing_mechanism"], "gun_sidearm"),
         Recipes.shapeless(["steel_ingot", "steel_ingot", "steel_ingot", "steel_ingot", "firing_mechanism"], "gun_rifle"),
         Recipes.shapeless(["steel_ingot", "steel_ingot", "steel_ingot", "copper_ingot", "firing_mechanism"], "gun_smg"),
         Recipes.shapeless(["steel_ingot", "steel_ingot", "steel_ingot", "iron_ingot", "iron_ingot", "firing_mechanism"], "gun_shotgun"),
         Recipes.shapeless(["steel_ingot", "steel_ingot", "steel_ingot", "steel_ingot", "firing_mechanism", "targeting_optic"], "gun_sniper"),
         Recipes.shapeless(["steel_ingot", "steel_ingot", "steel_ingot", "steel_ingot", "steel_ingot", "tnt", "firing_mechanism", "targeting_optic"], "gun_launcher"),
         Recipes.shapeless(["steel_ingot", "steel_ingot", "redstone", "redstone", "gold_ingot", "firing_mechanism", "targeting_optic"], "gun_arc"),
         Recipes.shapeless(["radar_module", "compass", "steel_ingot", "steel_ingot", "redstone"], "radar_set")]
    }

    // Enchantment-adjusted numbers (Extended Magazine, Quick Reload, Stability); NPC guns carry no enchantments.
    static func magSize(_ s: ItemStack) -> Int {
        guard let gi = index(s.item) else { return 0 }
        let base = all[gi].mag
        let l = Enchant.level(.extendedMag, s)
        guard l > 0 else { return base }
        return max(base + 1, Int((Float(base) * (1 + 0.25 * Float(l))).rounded(.up)))
    }
    static func reloadTime(_ s: ItemStack, _ gi: Int) -> Float { all[gi].reload * (1 - 0.18 * Float(Enchant.level(.quickReload, s))) }
    static func steadiness(_ s: ItemStack) -> Float { 1 - 0.18 * Float(Enchant.level(.stability, s)) }

    // Tooltip lines for a gun: loaded rounds, ammunition, damage and fire rate.
    static func tooltip(_ s: ItemStack) -> [String] {
        guard let gi = index(s.item) else { return [] }
        let g = all[gi]
        let ammoName = Items.has(g.ammo) ? Items.def(Items.id(g.ammo)).display : g.ammo
        var out = ["Loaded: \(s.tag) / \(magSize(s))", "Ammo: \(ammoName)"]
        switch g.shot {
        case .bullet:
            let dmg = g.pellets > 1 ? "\(Int(g.damage)) x \(g.pellets)" : "\(Int(g.damage))"
            out.append("Damage: \(dmg)")
        case .rocket: out.append("Explosive rockets")
        case .beam: out.append("Damage: \(Int(g.damage)), ignites")
        }
        out.append(g.auto ? String(format: "Automatic, %.0f rounds/s", 1 / g.interval) : String(format: "%.1f shots/s", 1 / g.interval))
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
    // Ammo light on the left of the receiver (the shooter's side): cyan with rounds in, red when empty.
    static let indicator: [Part] = CapitalArms.models.map { m in
        let r = m.parts[0]
        let y = r.mn.y + (r.mx.y - r.mn.y) * 0.62
        return Part(mn: V3(r.mn.x - 0.12, y, r.mn.z + 1.2), mx: V3(r.mn.x + 0.02, y + 0.55, r.mn.z + 4.2), color: CapitalArms.glow, pattern: CapitalArms.pGlow)
    }
    static let order = [0, 1, 2, 0, 2, 3]
    static let faceShade: [Float] = [0.8, 0.8, 1.0, 0.55, 0.68, 0.68]

    // First-person gun, written straight into a mob-pipeline vertex buffer (view space).
    /// `rounds` 0 hides the magazine and turns the ammo light red; `scale` enlarges the model (Quest: held in the hand).
    static func writeFirstPerson(_ gi: Int, aim: Float, kick: Float, lower: Float, bob: V3, light: Float, rounds: Int = 1,
                                 scale: Float = 1, into out: UnsafeMutablePointer<MobVert>) -> Int {
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
        for (pi, p0) in (models[gi] + [ind]).enumerated() {
            if rounds <= 0 && magParts[gi].contains(pi) { continue }            // empty: the magazine is out
            let p = p0
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
        "shotgun_shells": ["................", "................", "................", "................", "...rrr...rrr....",
                           "...rrr...rrr....", "...rrr...rrr....", "...rrr...rrr....", "...rrr...rrr....", "...rrr...rrr....",
                           "...yyy...yyy....", "...yyy...yyy....", "................", "................", "................", "................"],
        "heavy_rounds": ["................", "................", ".....b.....b....", "....bbb...bbb...", "....bbb...bbb...",
                         "....bbb...bbb...", "....yyy...yyy...", "....yyy...yyy...", "....yyy...yyy...", "....yyy...yyy...",
                         "....yyy...yyy...", "....yyy...yyy...", "....yyy...yyy...", "....ddd...ddd...", "................", "................"],
        "rocket_ammo": ["................", "..............rr", ".............rrr", "............aaar", "...........aaa..",
                        "..........aaa...", ".........aaa....", "........aaa.....", ".......aaa......", "......aaa.......",
                        ".....aaa........", "...ddaa.........", "..dddd..........", "..ddd...........", "..yd............", ".yy............."],
        "gun_sidearm": ["................", "................", "................", "................", "................",
                        "...11111111111..", "...1dddddddddd1.", "...1aaaaaaaaaa1.", "...1aaa1m1111...", "...1aaa1.m1.....",
                        "..1aaa11.1......", "..1aaa1.........", "..1aaa1.........", "..11111.........", "................", "................"],
        "arc_cell": ["................", "................", "......1111......", ".....1mmmm1.....", "....1111111.....",
                     "....1gggggg1....", "....1gddddg1....", "....1gggggg1....", "....1gddddg1....", "....1gggggg1....",
                     "....1gddddg1....", "....1gggggg1....", "....11111111....", "................", "................", "................"],
    ]

    static func painters(_ p: inout [String: TextureGen.Painter]) {
        for (k, rows) in icons {
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
                case "g": return V4(0.45, 0.95, 1, 1)
                case "y": return V4(0.86 * h, 0.68 * h, 0.25 * h, 1)
                case "b": return V4(0.72 * h, 0.5 * h, 0.3 * h, 1)
                case "r": return V4(0.7 * h, 0.14 * h, 0.12 * h, 1)
                default: return TextureGen.clear
                }
            }
        }
    }

    static let soundCount = 16      // 14 loaded (bolt home), 15 last round (bolt locks open)
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
