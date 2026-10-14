import Foundation
import simd

// D17 the saloon's drinks and its piano player.
//   drinks   the barkeep pours three soft drinks (comfort-safe: no liquor, nobody gets drunk): sarsaparilla (a fizz
//            of speed, 20 s), black coffee (haste, 30 s) and cold lemonade (a moment of regeneration). Each fills a
//            little and hands the bottle back.
//   piano    while the saloon is open, a piano player sits at its piano (the jukebox in the corner) and plays ragtime:
//            stride bass, a syncopated tune, a new piece each time one ends. Nearby you hear it through the jukebox
//            stream (the nearest playing one wins). Their piano can't be emptied; the player can be hired... by a tip
//            (use them: a dollar, and a cheer). The pianist is a townsperson who sits at the keys and stays put.
enum Saloon {
    static let drinks: [(key: String, name: String, color: UInt32, effect: Effect, amp: Int, secs: Float)] = [
        ("sarsaparilla_bottle", "Sarsaparilla", 0x5A2A14, .speed, 0, 20),
        ("coffee_bottle", "Black Coffee", 0x2A1A10, .haste, 0, 30),
        ("lemonade_bottle", "Cold Lemonade", 0xF2E27A, .regeneration, 0, 4),
    ]
    static let pianoPrefix = "saloon_piano"
    static var pieces = 0, tips = 0                    // (tests)

    static func isDrink(_ key: String) -> Bool { drinks.contains { $0.key == key } }
    static func drunk(_ g: Game, _ key: String) {
        guard let d = drinks.first(where: { $0.key == key }) else { return }
        g.applyEffect(d.effect, amp: d.amp, seconds: d.secs)
    }

    static func isPianist(_ m: Mob) -> Bool { m.kind == .villager && m.villager?.role == "pianist" }

    // Once a second (TownLaw.tick): the piano in the saloon the player is near.
    static func tick(_ g: Game) {
        guard g.dim.dim == .overworld, TownLaw.inTown != nil else { return }
        let p = g.player.pos
        guard let keep = g.mobs.mobs.first(where: { $0.kind == .villager && $0.health > 0
                                                && $0.villager?.shop == ShopKind.saloon.rawValue && simd_length($0.pos - p) < 48 }) else { return }
        guard let piano = findPiano(g, near: keep.pos) else { return }
        let f = Float(g.dayFraction)
        let open = f >= ShopKind.saloon.hours.0 && f < ShopKind.saloon.hours.1
        // Finished pieces come off; a new one starts while the player sits there.
        g.jukeboxes.removeAll { $0.disc.hasPrefix(pianoPrefix) && (!$0.playing || !open) }
        guard open else { return }
        let seat = V3(Float(piano.x) + 0.5, Float(piano.y), Float(piano.z) + 0.5)
        var pianist = g.mobs.mobs.first { isPianist($0) && $0.health > 0 && simd_length($0.pos - seat) < 20 }
        if pianist == nil {
            let m = Mob(.villager, at: g.world.freeSpawn(seat + V3(0, 0, 1)))
            Townsfolk.setup(m, game: g)
            if var v = m.villager { v.role = "pianist"; v.profession = "none"; v.locked = true; m.villager = v }
            m.persistent = true
            m.home = m.pos
            g.mobs.mobs.append(m)
            pianist = m
        }
        guard let pl = pianist, pl.town.anger <= 0, pl.panic <= 0, pl.town.brawl <= 0, pl.town.out <= 0 else { return }
        if !g.jukeboxes.contains(where: { $0.pos == piano }) {
            pieces += 1
            g.jukeboxes.append(JukeboxPlayer(piano, "\(pianoPrefix)_\(pieces % 64)"))
        }
    }

    // The saloon's piano: a jukebox within 14 blocks of the barkeep.
    static func findPiano(_ g: Game, near c: V3) -> IVec3? {
        let w = g.world
        guard Blocks.has("jukebox") else { return nil }
        let jb = Blocks.id("jukebox")
        let cx = Int(floor(c.x)), cy = Int(floor(c.y)), cz = Int(floor(c.z))
        var best: (Int, IVec3)?
        for dy in -2...2 { for dz in -14...14 { for dx in -14...14 {
            guard w.block(cx + dx, cy + dy, cz + dz) == jb else { continue }
            let d = dx * dx + dz * dz + dy * dy
            if d < (best?.0 ?? .max) { best = (d, IVec3(cx + dx, cy + dy, cz + dz)) }
        } } }
        return best?.1
    }

    // Mob.update: the pianist sits at the keys (nil when something else has their attention).
    static func pianistStep(_ m: Mob, _ g: Game) -> Float? {
        guard isPianist(m), m.town.anger <= 0, m.panic <= 0, m.town.brawl <= 0, m.town.out <= 0 else { return nil }
        guard let h = m.home else { return nil }
        if simd_length(V2(h.x - m.pos.x, h.z - m.pos.z)) > 0.6 { m.face(h); return 1.5 }
        if let j = g.jukeboxes.first(where: { $0.disc.hasPrefix(pianoPrefix) && simd_length($0.center - m.pos) < 3 }) {
            m.face(j.center)
            m.town.swing = (sinf(Float(g.clock) * 9) > 0.6) ? 0.2 : 0           // hands on the keys
        }
        return 0
    }

    // Using the pianist: a tip.
    static func tip(_ g: Game, _ m: Mob) -> Bool {
        guard isPianist(m) else { return false }
        if g.money >= 100 {
            g.money -= 100
            tips += 1
            Townsfolk.say(g, m, ["Much obliged!", "This next one's for you.", "Thank you kindly.", "A request? I only know the one."][tips % 4])
        } else {
            Townsfolk.say(g, m, "Just listening's fine, friend.")
        }
        return true
    }

    // A piece of ragtime: stride bass, off-beat chords, a syncopated tune over I-IV-I-V.
    static func ragtime(_ name: String) -> MusicScore {
        var h: UInt64 = 0x9E3779B97F4A7C15
        for b in name.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        var rng = SRng(h | 1)
        let bpm: Float = 104 + Float(rng.int(28))
        let beat: Float = 60 / bpm
        let root: Float = [60, 62, 65, 67][rng.int(4)]
        let prog: [[Float]] = [[0, 4, 7], [0, 4, 7], [5, 9, 12], [5, 9, 12], [0, 4, 7], [7, 11, 14], [0, 4, 7], [7, 11, 17]]
        var notes: [MusicNote] = []
        var t: Float = 0
        for _ in 0..<5 {
            for ch in prog {
                for b in 0..<4 {
                    let tb = t + Float(b) * beat
                    if b % 2 == 0 {
                        let low: Float = root - 24 + ch[0] + (b == 2 ? 7 : 0)
                        notes.append(MusicNote(t: tb, dur: beat * 0.85, inst: .harp, midi: low, vel: 0.55, pan: -0.25))
                    } else {
                        for c in ch { notes.append(MusicNote(t: tb, dur: beat * 0.45, inst: .harp, midi: root - 12 + c, vel: 0.3, pan: 0)) }
                    }
                }
                for e in 0..<8 where rng.chance(e % 2 == 1 ? 0.75 : 0.5) {
                    let pool: [Float] = ch + [ch[0] + 2, ch[1] + 1, ch[2] + 2]
                    let midi: Float = root + pool[rng.int(pool.count)]
                    let swingT: Float = e % 2 == 1 ? beat * 0.08 : 0
                    notes.append(MusicNote(t: t + Float(e) * beat / 2 + swingT, dur: beat * 0.42, inst: .harp, midi: midi,
                                           vel: 0.5 + rng.float() * 0.2, pan: 0.2))
                }
                t += beat * 4
            }
        }
        notes.sort { $0.t < $1.t }
        return MusicScore(mood: .day, notes: notes, length: t + 2, title: "Saloon Piano")
    }
}

extension ItemRegistry {
    func registerSaloonDrinks() {
        for d in Saloon.drinks where !has(d.key) {
            var def = ItemDef(d.key, d.name)
            def.sprite = Sprite(mask: "bottle", base: 0xD0DCF0, extras: ["c": d.color])
            def.food = FoodInfo(hunger: 2, saturation: 0.6)
            def.maxStack = 16
            add(def)
        }
    }
}
