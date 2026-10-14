import Foundation
import simd

// D2: wild horse herds, rare coats and a legendary horse.
//   herds       wild horses spawn in herds of 3 to 7 of one breed and keep together: a herd member's strolls stay
//               within 8 blocks of the herd's middle (the untamed horses of its kind within 32 blocks), and when one
//               takes fright the rest bolt with it.
//   rare coats  about one wild horse in 25 wears a rare coat: Palomino (gold, cream mane), Silver Dapple (dark with a
//               silver mane, dappled), Leopard (white with dark spots) or Cremello (cream). Saved in variant bits 12-14.
//   legendary   about one herd in 150 runs with the Silver Wraith: storm grey, white mane, the fastest and highest
//               jumping a horse can be. You hear of it as you come near (a toast once a session).
enum HorseHerds {
    static let names = ["", "Palomino", "Silver Dapple", "Leopard", "Cremello", "", "", "Silver Wraith"]
    static let legendary = 7
    static let legendName = "Silver Wraith"
    static var told = false

    static func rare(_ m: Mob) -> Int { m.kind == .horse ? (m.variant >> 12) & 7 : 0 }

    // Sets a horse's rare coat, keeping its base coat (variant % 5) as it was.
    static func setRare(_ m: Mob, _ r: Int) {
        let coat = m.variant % 5
        var v = (m.variant & 0xFF0) | (r << 12)                      // speed and jump bits (4-11) kept
        v |= (coat - v % 5 + 5) % 5
        m.variant = v
    }

    // Body and mane colours of a rare coat (nil: the ordinary coat).
    static func colours(_ m: Mob) -> (body: V3, mane: V3, dapple: Bool)? {
        switch rare(m) {
        case 1: return (V3(0.86, 0.67, 0.34), V3(0.95, 0.9, 0.76), false)
        case 2: return (V3(0.3, 0.28, 0.28), V3(0.82, 0.82, 0.84), true)
        case 3: return (V3(0.9, 0.88, 0.84), V3(0.3, 0.27, 0.25), true)
        case 4: return (V3(0.93, 0.87, 0.72), V3(0.97, 0.94, 0.86), false)
        case 7: return (V3(0.55, 0.58, 0.63), V3(0.97, 0.97, 0.98), true)
        default: return nil
        }
    }

    // A wild herd at spawn (MobManager.spawnAnimalPack): one breed, a few rare coats, now and then the legend.
    static func spawned(_ herd: [Mob]) {
        guard let first = herd.first else { return }
        let breed = HorseBreed.allCases.randomElement() ?? .mustang
        for m in herd {
            HorseLife.roll(m, breed: breed)
            if Rand.int(in: 0..<25) == 0 { setRare(m, Rand.int(in: 1...4)) }
        }
        if Rand.int(in: 0..<150) == 0 {
            first.baby = false; first.scale = 1
            first.variant = (15 << 4) | (15 << 8)
            setRare(first, legendary)
            first.customName = legendName
            first.health = 30
            first.temper = 0
        }
    }
}

extension Mob {
    // Wild herd life, once per stroll decision (Animals.animalAI): keep near the herd, bolt with it.
    func herdTick(_ g: Game) {
        var sum = V3(0, 0, 0), n = 0
        var fright = false
        for o in g.mobs.mobs where o !== self && o.kind == kind && !o.tamed && !o.leashed && o.health > 0 {
            let d = simd_length(o.pos - pos)
            guard d < 32 else { continue }
            sum += o.pos; n += 1
            if o.panic > 0.5 && d < 16 { fright = true }
        }
        if fright { panic = max(panic, 3) }
        strollArea = n >= 1 ? ((sum + pos) / Float(n + 1), 8) : nil
        if HorseHerds.rare(self) == HorseHerds.legendary && !HorseHerds.told && g.alive && simd_length(g.player.pos - pos) < 48 {
            HorseHerds.told = true
            g.onToast?("A legendary horse runs with this herd: the \(HorseHerds.legendName)")
        }
    }
}
