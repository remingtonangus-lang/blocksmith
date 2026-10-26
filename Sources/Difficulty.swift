import Foundation

// Difficulty levels (backlog G19; docs/status/difficulty.md), chosen when the world is made and changeable at any time
// afterwards (P369: the pause menu's Difficulty row).
// P302 (Oct 15, "easy is too hard"; "easy all but instakilled him"): five fighting levels with big steps between them,
// Very Easy, Easy, Normal, Hard, Very Hard, plus Peaceful. Easy is a cakewalk even for a new player (a few deaths at
// most), Normal is the reference game a seasoned player still dies in while learning, Hard and Very Hard are for a
// struggle. Enemy health is realistic and the SAME on every level; what changes is the player's side (how much of a
// blow lands, how much armour stops, the biggest single hit, how fast health comes back, hunger) and the enemy's
// edge (speed, aim, how often they strike, how far they notice you, how many are about). Fliers (Searwings and the
// rest) are easy kills on the easy levels: hits on them count for more and knock them down within reach.
//
// Game.diffLevel holds the level (0...5). Game.difficulty stays the older four-step band (0 peaceful, 1 easy, 2 normal,
// 3 hard) the rest of the game keys on (patrol sizes, door breaking, starving floors...): Very Easy and Easy read as
// band 1, Hard and Very Hard as band 3. A world saved before P302 keeps its level: Easy -> Easy, Normal -> Normal,
// Hard -> Hard.
enum Difficulty {
    static let names = ["Peaceful", "Very Easy", "Easy", "Normal", "Hard", "Very Hard"]
    // One line per level for the Create World page and the settings (what the level means for you).
    static let help = [
        "Peaceful: no monsters or raiders, and hunger never harms you.",
        "Very Easy: blows barely scratch you and none takes more than a heart and a half; enemies are slow, miss a lot and are few. Fliers fall to a hit or two.",
        "Easy: enemies hit softly (never more than two and a half hearts at once), aim poorly, strike slowly and come in small numbers; armour helps more. Fliers are easy kills.",
        "Normal: the game as intended. Enemies hit, aim and move as they should; expect to die a few times while learning.",
        "Hard: blows land half again as hard and armour helps less; enemies are faster, sharper shots, quicker to strike and more numerous.",
        "Very Hard: double damage, armour helps little, health returns slowly; enemies are fast, accurate, relentless and everywhere.",
    ]
    struct Row {
        let taken: Float      // share of an attack's damage that lands on the player
        let cap: Int          // most half-hearts one attack can take (0: no limit)
        let armour: Float     // how much armour helps (its stopping power times this)
        let regen: Float      // how fast health comes back
        let hunger: Float     // hunger drain
        let speed: Float      // enemy speed
        let aim: Float        // enemy gun spread (more is wider)
        let pace: Float       // how often enemies strike or fire
        let sight: Float      // how far enemies notice the player
        let spawns: Float     // how many monsters the spawner keeps about
        let flier: Float      // what a hit on a hostile flier counts for
        var rate: Int = 0     // P358: most half-hearts the player can lose in any one second (0: no limit)
        var blow: Int = 0     // P413: most half-hearts one attack can take on the levels without `cap` (0: no limit)
    }
    static let rows: [Row] = [
        // peaceful
        Row(taken: 0, cap: 0, armour: 1, regen: 1.5, hunger: 0.6, speed: 1, aim: 1, pace: 1, sight: 1, spawns: 0, flier: 1),
        // very easy
        Row(taken: 0.2, cap: 3, armour: 1.3, regen: 2, hunger: 0.5, speed: 0.75, aim: 2.4, pace: 0.5, sight: 0.6, spawns: 0.4, flier: 2.5, rate: 3),
        // easy
        Row(taken: 0.35, cap: 5, armour: 1.15, regen: 1.5, hunger: 0.7, speed: 0.88, aim: 1.7, pace: 0.7, sight: 0.8, spawns: 0.65, flier: 1.8, rate: 5),
        // normal (P413, Oct 22 22:16: "whatever hit me near well killed me... it has to be like on very hard mode or it was
        // too much": a Greywall gun's shell took 21 half-hearts at once; one blow takes at most half his health here, 7
        // hearts on Hard, and only Very Hard has no limit; attacks only: a fall or lava still kills)
        Row(taken: 1, cap: 0, armour: 1, regen: 1, hunger: 1, speed: 1, aim: 1, pace: 1, sight: 1, spawns: 1, flier: 1, blow: 10),
        // hard
        Row(taken: 1.5, cap: 0, armour: 0.85, regen: 0.85, hunger: 1.25, speed: 1.12, aim: 0.75, pace: 1.2, sight: 1.15, spawns: 1.35, flier: 1, blow: 14),
        // very hard
        Row(taken: 2, cap: 0, armour: 0.7, regen: 0.7, hunger: 1.5, speed: 1.25, aim: 0.55, pace: 1.45, sight: 1.3, spawns: 1.7, flier: 1),
    ]
    // P358 (Oct 16 21:42, "easy is too hard", asked many times): the numbers now reach the player on every path.
    //   Every way damage reaches him goes through the level's row (Game.levelShare): attacks (mobs, rounds, blasts,
    //   artillery, vehicle guns: hurtPlayer) and everything else (falls, fire, lava, drowning, freezing, cactus, berry
    //   bushes, lightning, crashes, magic, wither, hell's heat: Game.damage), the void and starving aside. On the easy
    //   levels a single blow is capped and, new, so is the total in any one second (a machine gun's stream was a dozen
    //   capped hits a second): Very Easy 1.5 hearts a second, Easy 2.5; Very Easy takes a fifth of a blow, Easy a third.
    //   Soldiers die like people (Ballistics.impactMob): one round to the head, one heavy rifle round (9 or more) to
    //   the body, two rifle or pistol rounds, a short burst (four) of light rounds, any direct rocket or shell.
    // The level the mobs read each update (MobManager.update sets it from the game, like Mob.hardMode).
    static var level = 3
    static var row: Row { rows[clamp(level)] }
    static func clamp(_ l: Int) -> Int { max(0, min(5, l)) }
    // P302: the older band (0 peaceful, 1 easy, 2 normal, 3 hard) of a level, and the level a band (an old save, an
    // old create action, a co-op host on an older build) stands for.
    static func band(_ l: Int) -> Int { [0, 1, 1, 2, 3, 3][clamp(l)] }
    static func level(band b: Int) -> Int { [0, 2, 3, 4][max(0, min(3, b))] }
    static func name(_ l: Int) -> String { names[clamp(l)] }

    // The share of a hit a mob takes. Enemy health is fixed across levels (P302); only the mob's own build roll
    // (MobVary) and, on the easy levels, a hostile flier's frailty change it. Fractions round at random so the average
    // holds; every landed hit does at least 1.
    // P435 (Oct 24 16:01, "that guy's damn tough... what the hell is he made of? I'm on easy difficulty"): on Very Easy
    // and Easy no enemy rolls tougher than plain (MobVary's brutes and elites still run faster and hit harder), the
    // Deep's veterans lose the doubled health they carry on Normal and up (a hit on one counts twice), and the Marshal
    // and the Chancellor take twice (Very Easy) or half again (Easy) what a hit does on Normal.
    // P465 (Oct 25 20:17-20:25, Hannibal troopers: "not tough enough. It should be way tougher"; "They just need to be
    // tougher. That's my only complaint"): a Hannibal trooper shrugs off twice what it did, on top of its plate.
    static func tough(_ m: Mob) -> Float { m.troop == 3 ? toughBase(m) * 2 : toughBase(m) }
    private static func toughBase(_ m: Mob) -> Float {
        let t = m.vary.tough
        guard level == 1 || level == 2 else { return t }
        if m.kind == .ashMarshal || m.kind == .ashChancellor { return min(t, 1) * (level == 1 ? 0.5 : 0.67) }
        if m.faction == Faction.ashguard.rawValue && Soldier.rank(m.kind) != nil && !m.kind.ash { return min(t, 1) * 0.5 }
        return min(t, 1)
    }

    static func scaleHit(_ damage: Int, _ m: Mob) -> Int {
        guard damage > 0 else { return damage }
        let flier: Float = m.kind.hostile && m.spec.flying ? row.flier : 1
        let t = tough(m) / flier
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
