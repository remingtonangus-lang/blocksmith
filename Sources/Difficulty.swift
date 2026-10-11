import Foundation

// Difficulty levels (backlog G19; docs/status/difficulty.md): Easy, Normal (the "medium" of the ask) and Hard, chosen
// when the world is made and locked afterwards (a Peaceful world stays Peaceful). Each level scales the monsters'
// damage (the reference formula, Game.damage), their toughness, their speed, how fast hunger drains and how many
// monsters the spawner keeps around the player.
enum Difficulty {
    struct Row { let toughness: Float, speed: Float, hunger: Float, spawns: Float }
    //                       peaceful                                           easy
    static let rows: [Row] = [Row(toughness: 1, speed: 1, hunger: 0.6, spawns: 0), Row(toughness: 0.75, speed: 0.9, hunger: 0.75, spawns: 0.65),
    //                       normal                                             hard
                              Row(toughness: 1, speed: 1, hunger: 1, spawns: 1), Row(toughness: 1.4, speed: 1.12, hunger: 1.3, spawns: 1.35)]
    // The level the mobs read each update (MobManager.update sets it from the game, like Mob.hardMode).
    static var level = 2
    static var row: Row { rows[max(0, min(3, level))] }

    // A monster's share of a hit at this level: an Easy monster drops in three quarters of the blows, a Hard one takes
    // 1.4 times as many. Fractions round at random so the average holds; every landed hit does at least 1.
    static func scaleHit(_ damage: Int, _ m: Mob) -> Int {
        guard damage > 0, m.kind.hostile, m.kind.category == .monster else { return damage }
        let t = row.toughness * m.vary.tough
        guard t != 1 else { return damage }
        let d = Float(damage) / t, whole = floorf(d)
        return max(1, Int(whole) + (Rand.float(in: 0..<1) < d - whole ? 1 : 0))
    }
}

// P55 (Oct 11 evening playtest): monsters differ one from the next: each rolls its own speed, hit strength, toughness
// and (archers) aim when it first acts, so one zombie lumbers while the next runs you down, and one skeleton's arrows
// spray while another's land. Spreads are wide but every roll stays inside the reference feel.
struct MobVary {
    var speed: Float = 1, damage: Float = 1, tough: Float = 1, aim: Float = 0
    static let plain = MobVary()
    // Off in the headless checks (their fixtures count exact blows and steps); the P55 check turns it on.
    static var on = true
    static func roll(_ m: Mob) -> MobVary {
        guard on, m.kind.hostile, m.kind.category == .monster else { return .plain }
        return MobVary(speed: Rand.float(in: 0.8...1.25), damage: Rand.float(in: 0.7...1.4), tough: Rand.float(in: 0.75...1.35),
                       aim: Rand.float(in: 0...0.12))
    }
    // A damage value scaled by this mob's strength, rounding at random so the average holds (at least 1).
    func hit(_ base: Int) -> Int {
        guard base > 0, damage != 1 else { return base }
        let d = Float(base) * damage, whole = floorf(d)
        return max(1, Int(whole) + (Rand.float(in: 0..<1) < d - whole ? 1 : 0))
    }
}
