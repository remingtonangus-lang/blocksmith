import Foundation
import simd

// D23: catch a fleeing witness before they reach the sheriff.
// Objectives:
//  - A crime seen only by ordinary townsfolk, with no lawman within 20 blocks, is not known to the law yet: the first
//    witness runs for the nearest sheriff or deputy of the town (up to 200 blocks), calling out as they go.
//  - If they get within 4 blocks of him, the crime is reported in full (TownLaw.offence, as if seen there).
//  - The player can stop it: catch them (come within 2.5 blocks), and they give up and keep quiet (a little honour
//    lost for the threat); or they fall. Either way nothing is reported. After 90 s they give up on their own and
//    report it anyway, wherever they are.
enum Witnesses {
    struct Run { weak var who: Mob?; weak var law: Mob?; var town: String; var heat: Float; var at: V3; var assault: Bool; var t: Float }
    static var runs: [Run] = []
    static var caught = 0, reported = 0
    static var reporting = false

    // From TownLaw.offence before the town hears of it. True when a witness ran instead.
    static func start(_ g: Game, witness w: Mob, town: String, heat: Float, at p: V3, victim: Mob?) -> Bool {
        guard !reporting, !TownLaw.isLaw(w), w !== victim, runs.count < 4, !runs.contains(where: { $0.who === w }) else { return false }
        let law = g.mobs.mobs.filter { TownLaw.isTownsperson($0) && TownLaw.isLaw($0) && TownLaw.town(of: $0, g) == town }
        if law.contains(where: { simd_length($0.pos - p) < 20 }) { return false }
        guard let l = law.filter({ simd_length($0.pos - w.pos) < 200 }).min(by: { simd_length($0.pos - w.pos) < simd_length($1.pos - w.pos) }) else { return false }
        runs.append(Run(who: w, law: l, town: town, heat: heat, at: p, assault: victim != nil, t: 0))
        Townsfolk.say(g, w, ["Sheriff! Sheriff!", "Somebody fetch the law!", "I saw that! I'm telling the sheriff!"][Rand.int(in: 0...2)])
        g.onToast?("A witness is running for the sheriff!")
        return true
    }

    static var lastClock: Double = 0
    static func tick(_ g: Game) {
        let dt = Float(max(0, min(0.25, g.clock - lastClock)))
        lastClock = g.clock
        guard !runs.isEmpty else { return }
        var keep: [Run] = []
        for var r in runs {
            r.t += dt
            guard let w = r.who, w.health > 0 else { continue }                // fell: nothing told
            if simd_length(w.pos - g.player.pos) < 2.5 {
                caught += 1
                w.panic = 0; w.wanderGoal = nil
                w.face(g.player.pos)
                Townsfolk.say(g, w, ["All right! I didn't see nothing.", "Please, I won't say a word.", "Fine, fine. I never saw you."][Rand.int(in: 0...2)])
                Honour.change(g, -0.5, "a frightened witness")
                g.onToast?("You caught the witness: they'll keep quiet")
                continue
            }
            let l = r.law
            if r.t > 90 || l == nil || l!.health <= 0 || simd_length(l!.pos - w.pos) < 4 {
                reported += 1
                reporting = true
                TownLaw.offence(g, heat: r.heat, at: l?.pos ?? w.pos, victim: nil, speak: true)
                reporting = false
                if let l { l.face(w.pos) }
                continue
            }
            // Keep running for him.
            w.panic = 0
            w.wanderGoal = l!.pos; w.moving = true; w.aiTimer = 2
            w.face(l!.pos)
            keep.append(r)
        }
        runs = keep
    }
}
