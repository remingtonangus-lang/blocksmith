import Foundation
import simd

// P478's check (questcheck --p478): townsfolk say "good to see you again" only to someone they met on an earlier day
// and speak of his horse only when one is with him; a shopkeeper he has never met greets him with none of those; hyper
// flight in creative covers ten times fast flight's ground; the Void Chest is out of the creative palette; town streets
// run only as far as their buildings.
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
        check(!CreativeMenu.every.contains(Items.id(VehiclePresets.itemKey))
              && Fireworks.tooltip(VehiclePresets.stack(2)).joined(separator: " ").contains("Gun Truck"),
              "the blank Vehicle Blueprint is out of the creative palette; a real one's tooltip names its vehicle")
        // Streets only as far as the buildings along them (new ground: the harness world has no save).
        var places = 0, roads0 = 0, roads1 = 0, cols0 = 0, cols1 = 0
        Village.pathsLog = { r0, c0, r1, c1 in places += 1; roads0 += r0; roads1 += r1; cols0 += c0; cols1 += c1 }
        for (x, z) in [(0, 0), (4000, 0), (0, 4000), (-4000, 0), (0, -4000), (4000, 4000)] {
            _ = g.world.gen.structures?.nearest("village", x: x, z: z, maxRegions: 16)
        }
        Village.pathsLog = nil
        // Ghost towns: each laid out from its seed (P478 "not algorithmic enough"): three of them differ.
        var towns: [String] = []
        for (x, z) in [(3000, -2000), (-3000, 2500), (5000, 5000), (-5000, -5000), (2000, 6000), (-6000, 1000)] where towns.count < 3 {
            guard let st = g.world.gen.structures?.nearest(FrontierSites.kind, x: x, z: z, maxRegions: 8, accept: { $0.kind == "ghost_town" }),
                  !towns.contains(where: { $0.hasPrefix("\(st.anchor.x),\(st.anchor.z) ") }) else { continue }
            let a = st.anchor
            _ = g.world.loadSync(center: V3(Float(a.x), Float(a.y), Float(a.z)), radius: 2)
            var solid = 0, boxes = 0
            let r = FrontierSites.ghostReach
            for dz in -r...r { for dx in -r...r { for dy in 0...8 where g.world.block(a.x + dx, a.y + dy, a.z + dz) != AIR { solid += 1 } } }
            for (q, _) in g.world.blockEntities where abs(q.x - a.x) <= r && abs(q.z - a.z) <= r && abs(q.y - a.y) <= 8 { boxes += 1 }
            towns.append("\(a.x),\(a.z) \(solid) blocks \(boxes) chests")
        }
        let shapes = Set(towns.map { $0.split(separator: " ").dropFirst().joined(separator: " ") })
        check(towns.count >= 2 && shapes.count == towns.count && !towns.contains { $0.hasSuffix(" 0 chests") },
              "ghost towns: \(towns.count) found, each its own layout (\(towns.joined(separator: "; ")))")
        check(places > 0 && cols1 < cols0 && roads1 > 0,
              "places: \(places) towns' streets trimmed to their buildings: \(roads0) -> \(roads1) streets, \(cols0 / 3) -> \(cols1 / 3) street steps")
    }
}
