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
        guard damage > 0 else { return damage }
        let t = (m.kind.hostile && m.kind.category == .monster ? row.toughness : 1) * m.vary.tough
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
    // P134 (Oct 12 PM, "make them vary greatly in speed and damage"): a monster is one of three builds. Most are
    // middling (speed x0.8-1.25, hits x0.7-1.4); one in five is a runner (x1.35-1.7 fast, x0.5-0.8 hits) and one in
    // five a brute (x0.6-0.8 slow, x1.4-2 hits and tougher), so a pack mixes ones that run you down with ones that hurt.
    // R16 (Oct 13: "mob variety much wider in speed, damage and toughness, a lot more"): the spread was only on the
    // monster category (soldiers, hell's own, raiders, animals all identical) and narrow. Now every hostile rolls one of
    // four builds with wider ranges (an elite one in twelve), soldiers included (their stride, shot damage and armour),
    // and animals roll their own pace and hardiness.
    enum Build: Int { case middling, runner, brute, elite }
    var build = Build.middling
    static func roll(_ m: Mob) -> MobVary {
        guard on else { return .plain }
        if !m.kind.hostile {
            guard m.kind.category != .misc, m.kind != .deckGun else { return .plain }
            return MobVary(speed: Rand.float(in: 0.75...1.35), damage: Rand.float(in: 0.8...1.25), tough: Rand.float(in: 0.8...1.3), aim: 0)
        }
        if m.kind == .deckGun || m.kind.category == .misc { return .plain }
        let u = Rand.float(in: 0..<1)
        if u < 1.0 / 12 {
            return MobVary(speed: Rand.float(in: 1.15...1.45), damage: Rand.float(in: 1.6...2.3), tough: Rand.float(in: 1.7...2.5),
                           aim: Rand.float(in: 0...0.04), build: .elite)
        }
        if u < 0.3 {
            return MobVary(speed: Rand.float(in: 1.4...1.95), damage: Rand.float(in: 0.45...0.8), tough: Rand.float(in: 0.6...0.95),
                           aim: Rand.float(in: 0.04...0.16), build: .runner)
        }
        if u < 0.5 {
            return MobVary(speed: Rand.float(in: 0.5...0.8), damage: Rand.float(in: 1.5...2.4), tough: Rand.float(in: 1.3...1.9),
                           aim: Rand.float(in: 0...0.08), build: .brute)
        }
        return MobVary(speed: Rand.float(in: 0.75...1.3), damage: Rand.float(in: 0.6...1.5), tough: Rand.float(in: 0.7...1.45),
                       aim: Rand.float(in: 0...0.12))
    }
    // A damage value scaled by this mob's strength, rounding at random so the average holds (at least 1).
    func hit(_ base: Int) -> Int {
        guard base > 0, damage != 1 else { return base }
        let d = Float(base) * damage, whole = floorf(d)
        return max(1, Int(whole) + (Rand.float(in: 0..<1) < d - whole ? 1 : 0))
    }
}
