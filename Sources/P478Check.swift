import Foundation
import simd

// P478's check (questcheck --p478): townsfolk say "good to see you again" only to someone they met on an earlier day
// and speak of his horse only when one is with him; a shopkeeper he has never met greets him with none of those; hyper
// flight in creative covers ten times fast flight's ground; the Void Chest is out of the creative palette.
enum P478Check {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let m = TownTests.keeper(g, .general, at: g.player.pos + V3(2, 0, 0))
        let day = Int(g.time / DAY_LENGTH)
        m.villager?.metDay = nil
        let strangerOK = !TownVoice.fits(g, m, "Good to see you again.") && !TownVoice.fits(g, m, "Ah, a regular! Usual?")
        m.villager?.metDay = day
        let sameDayOK = !TownVoice.fits(g, m, "Good to see you again.")
        m.villager?.metDay = day - 1
        let metOK = TownVoice.fits(g, m, "Good to see you again.")
        check(strangerOK && sameDayOK && metOK, "lines: \"good to see you again\" never from someone he hasn't met (\(strangerOK)), nor met only today (\(sameDayOK)); from someone met on an earlier day (\(metOK))")
        // A stranger's greetings, 200 of them: none says it knows him.
        m.villager?.metDay = nil
        var familiar = 0
        for _ in 0..<200 {
            if let (t, _) = TownVoice.line(.greet, m, game: g), TownVoice.familiar.contains(t) { familiar += 1 }
        }
        check(familiar == 0, "lines: a shopkeeper he never met greets him 200 times, \(familiar) of them as an old friend")
        let noHorse = !TownVoice.hasHorse(g) && !TownVoice.fits(g, m, "Lock up your horse. Thieves love a moonless night.")
        let horse = Mob(.horse, at: g.player.pos + V3(4, 0, 0)); horse.owner = true
        g.mobs.mobs.append(horse)
        let withHorse = TownVoice.hasHorse(g) && TownVoice.fits(g, m, "Lock up your horse. Thieves love a moonless night.")
        g.mobs.mobs.removeAll { $0 === horse }
        check(noHorse && withHorse, "lines: \"lock up your horse\" only with his horse near (none: \(noHorse), his own 4 blocks off: \(withHorse))")

        // Hyper flight: one second, straight ahead, high in the air.
        let p = g.player, pos0 = p.pos, fly0 = p.flying
        func flown(_ hyper: Bool) -> Float {
            p.pos = V3(pos0.x, Float(CH - 20), pos0.z); p.vel = .zero; p.flying = true; p.hyperFlight = hyper
            var inp = MoveInput(); inp.forward = 1; inp.sprint = true
            let start = p.pos
            for _ in 0..<72 { p.update(dt: 1.0 / 72, input: inp, world: g.world) }
            return simd_length(V2(p.pos.x - start.x, p.pos.z - start.z))
        }
        let fast = flown(false), hyper = flown(true)
        p.hyperFlight = false; p.pos = pos0; p.flying = fly0; p.vel = .zero
        check(hyper > fast * 6 && hyper > 400, String(format: "hyper flight: %.0f blocks in a second (fast flight %.0f)", hyper, fast))
        check(!CreativeMenu.every.contains(Items.id("ender_chest")), "the Void Chest is out of the creative palette")
    }
}
