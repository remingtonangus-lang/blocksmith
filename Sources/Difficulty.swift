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
        let t = row.toughness
        guard damage > 0, t != 1, m.kind.hostile, m.kind.category == .monster else { return damage }
        let d = Float(damage) / t, whole = floorf(d)
        return max(1, Int(whole) + (Rand.float(in: 0..<1) < d - whole ? 1 : 0))
    }
}
