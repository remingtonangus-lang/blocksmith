import Foundation
import simd

// P512 (Remington, Nov 2 12:22: tests showing that base revenge attacks, pirates and cruiser encounters all work).
// questcheck --encounters plays each one through the game's own ticks in a world with open sea (the naval soak's seed):
//   revenge   a base broken or taken is owed back about one time in four (FactionRaids.owe, rolled once a base); an owed
//             raid falls on his home once it is due and he is there: its dropship comes in, its troops get down by his
//             home and fight him; with none left after a minute the raid is beaten off;
//   sloop     out at sea, a roll brings a corsair sloop in from about 150 blocks off; it closes on him and fires;
//   cruiser   a roll brings the Corsair Cruiser (the destroyer's hull, corsair crew); it closes and fires volleys; two
//             blocks under the water its guns lose him; 400 blocks off it sails away;
//   never     no hunter comes ashore, in creative or on peaceful.
enum EncounterCheck {
    static let seaSeed: UInt64 = 3931512493184456980
    static let seaSpot = V3(11576.9, 62.8 + Float(YOFF), -12552.1)

    static func run(_ makeWorld: (UInt64) -> World, _ check: (Bool, String) -> Void) {
        let w = makeWorld(seaSeed)
        w.renderDistance = 8
        let g = Game(world: w, save: nil, persistent: false)
        g.paused = false
        g.time = 0.3 * DAY_LENGTH
        g.survival = true; g.difficulty = 2
        revenge(g, check)
        seaHunts(g, check)
    }

    // His home on land at the world's spawn.
    static func revenge(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let home = g.findSpawn()
        g.player.pos = home; g.player.flying = false; g.player.vel = .zero
        g.spawnPoint = home
        _ = w.loadSync(center: home, radius: 8)
        FactionRep.decode("")
        FactionRaids.owed = [:]; FactionRaids.settled = []; FactionRaids.active = nil
        // The roll: 400 bases broken, each rolled once.
        for k in 0..<400 { FactionRaids.owe("base:check\(k)", .steelhold, chance: FactionRaids.baseChance, clock: g.clock) }
        let owed = FactionRaids.owed.count
        for k in 0..<400 { FactionRaids.owe("base:check\(k)", .steelhold, chance: 1, clock: g.clock) }
        check(owed >= 70 && owed <= 130 && FactionRaids.owed.count == owed,
              "encounters: of 400 bases broken \(owed) are owed back (about one in four), and none is rolled twice (\(FactionRaids.owed.count))")
        FactionRaids.owed = [:]; FactionRaids.settled = []
        FactionRaids.owe("base:steelhold_check", .steelhold, chance: 1, clock: g.clock)
        guard let due = FactionRaids.owed["base:steelhold_check"]?.due else { check(false, "encounters: an owed raid was recorded"); return }
        let wait = due - g.clock
        // Not before it is due; then, once he's home, it comes.
        g.factionRaidsTick()
        let early = FactionRaids.active != nil
        g.clock = due + 1
        FactionRaids.lastAssault = -1e9
        let ships0 = Set(w.ships.list.map { ObjectIdentifier($0) })
        g.factionRaidsTick()
        let raid = FactionRaids.active
        for _ in 0..<30 { g.tick(1.0 / 30) }                       // (the dropship is built on a worker)
        let drops = w.ships.list.filter { !ships0.contains(ObjectIdentifier($0)) && $0.role == "dropship" }
        check(!early && wait >= 900 && wait <= 2400 && raid?.faction == .steelhold && raid?.place == "your home" && !drops.isEmpty,
              String(format: "encounters: a broken base's raid falls due %.0f min later (not before: %@), on his home (%@), %d dropship%@ inbound",
                     wait / 60, early ? "came early" : "held", raid?.place ?? "none", drops.count, drops.count == 1 ? "" : "s"))
        // Two minutes of play: the dropship lands, its troops come for him.
        let beaten0 = FactionRaids.beaten
        var hurt = 0, nearHome = 0, foes = 0
        for t in 0..<(120 * 30) {
            // (he holds his home: the rockets' knockback once threw him off past where the raid is counted)
            g.player.pos = home; g.player.vel = .zero
            g.tick(1.0 / 30)
            if g.health < 20 { hurt += 20 - g.health }
            g.health = 20; g.alive = true
            if t % 300 == 0 {
                let ds = w.ships.list.filter { $0.role == "dropship" && $0.parent == nil }
                let sol = g.mobs.mobs.filter { $0.health > 0 && Soldier.rank($0.kind) != nil }
                print(String(format: "encounters: t %3d s: %d dropship%@ %@, %d soldiers (%d of the raid's faction), raid %@", t / 30, ds.count, ds.count == 1 ? "" : "s",
                             ds.map { String(format: "%.0f off phase %d troops %d", simd_length($0.pos - home), w.ships.capState[$0.id]?.phase ?? -1, w.ships.capState[$0.id]?.troopsLeft ?? -1) }.joined(separator: "; "),
                             sol.count, sol.filter { $0.factionValue == .steelhold }.count, FactionRaids.active == nil ? "over" : "on")
                      + String(format: ", the raid's nearest %.0f off his home", sol.filter { $0.factionValue == .steelhold }.map { simd_length($0.pos - home) }.min() ?? -1))
            }
            if t % 30 == 0 {
                let raiders = g.mobs.mobs.filter { $0.health > 0 && !$0.hired && $0.factionValue == .steelhold && Soldier.rank($0.kind) != nil }
                nearHome = max(nearHome, raiders.filter { simd_length($0.pos - home) < 64 }.count)
                foes = max(foes, raiders.filter { $0.aggro }.count)
            }
        }
        check(nearHome > 0 && (hurt > 0 || foes > 0),
              "encounters: the raid's troops get down by his home (\(nearHome) within 64 blocks) and fight him (\(foes) out for him, \(hurt) half-hearts taken)")
        let early2 = FactionRaids.beaten - beaten0
        for m in g.mobs.mobs where m.factionValue == .steelhold { m.health = 0 }
        g.mobs.mobs.removeAll { $0.health <= 0 }
        let money0 = g.money
        g.clock += 61
        g.factionRaidsTick()
        check(early2 == 0 && FactionRaids.active == nil && g.money == money0 + FactionRaids.salvage && FactionRaids.beaten - beaten0 == 1,
              "encounters: the raid lasts while its troops are about (\(early2 == 0 ? "yes" : "beaten off with none landed")); with them down it is beaten off (+\(Money.format(g.money - money0)) salvage)")
        for s in w.ships.list where !ships0.contains(ObjectIdentifier(s)) { w.ships.remove(s) }
        FactionRaids.owed = [:]; FactionRaids.settled = []; FactionRaids.active = nil
    }

    // Out on the open sea, on a raft of stone.
    static func seaHunts(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, ships = w.ships
        // (the vessels' crews sail and fire in the encounter tick; nothing else spawns)
        ships.encounters = true
        ships.spawnEncounters = false
        let x = Int(floor(seaSpot.x)), z = Int(floor(seaSpot.z))
        _ = w.loadSync(center: V3(Float(x) + 0.5, Float(SEA + 1), Float(z) + 0.5), radius: 12)
        // His raft: two layers of stone over the water's surface, him on top (one layer at sea level left him in the
        // water, drowning, and the hunters' guns lost him as they do a diver).
        let surf = Submarine.surface(w, x + 10, z) ?? (SEA - 1)
        for dz in -3...3 { for dx in -3...3 { for y in surf...(surf + 1) { w.setBlock(x + dx, y, z + dz, STONE) } } }
        let raft = V3(Float(x) + 0.5, Float(surf + 2), Float(z) + 0.5)
        g.player.pos = raft
        g.player.vel = .zero; g.player.flying = false
        let atSea = SeaHunt.atSea(g)
        // Never in creative or on peaceful.
        SeaHunt.hunters = []
        let rolls0 = SeaHunt.rolls
        g.survival = false; SeaHunt.atSea = SeaHunt.every; g.seaHuntTick(0.05)
        g.survival = true; g.difficulty = 0; SeaHunt.atSea = SeaHunt.every; g.seaHuntTick(0.05)
        g.difficulty = 2
        check(atSea && SeaHunt.rolls == rolls0 && SeaHunt.hunters.isEmpty,
              "encounters: out at sea (\(atSea)), nothing hunts him in creative or on peaceful (\(SeaHunt.rolls - rolls0) rolls)")
        // Rolls until each kind comes (half the rolls bring one; one in four of those a cruiser).
        func hunter(cruiser: Bool) -> Ship? {
            for _ in 0..<200 {
                for s in ships.list where SeaHunt.isHunter(s) { ships.remove(s) }
                SeaHunt.hunters = []
                SeaHunt.atSea = SeaHunt.every
                // (and not "ashore" from the raid at his home: its count, left over a minute, sent the sloop off at the
                // first tick of the hunt, before a second at sea had reset it; at sea in play it reads 0)
                SeaHunt.ashore = 0
                g.seaHuntTick(0.05)
                if let s = ships.list.first(where: { SeaHunt.isHunter($0) }), SeaHunt.cruiser(s) == cruiser { return s }
            }
            return nil
        }
        // Plays `secs` at 30 ticks a second; his raft held, his health kept; returns (closest, rounds fired, hurt).
        var lastHurt = "nothing"
        let onDamage0 = Game.onDamage
        Game.onDamage = { _, cause in lastHurt = cause }
        defer { Game.onDamage = onDamage0 }
        func play(_ s: Ship, _ secs: Float, under: Bool = false) -> (Float, Int, Int) {
            var closest: Float = .infinity, hurt = 0
            var seen = Set<ObjectIdentifier>(), early = Set<ObjectIdentifier>()
            var blasts = 0, frame = 0
            Explosion.onExplode = { c, pw in
                if blasts < 6 {
                    print(String(format: "encounters: %@ frame %d: a power %.1f blast %.0f off the hull, %.0f off him (shells %d, crew %d)", s.name, frame, pw,
                                 simd_length(c - s.pos), simd_length(c - g.player.pos), ships.shells.count, g.mobs.mobs.filter { $0.deck === s }.count))
                }
                blasts += 1
            }
            defer { Explosion.onExplode = nil; if blasts > 0 { print("encounters: \(s.name): \(blasts) blasts in all") } }
            // (a turret or the hull taken away while it hunts him: by whom)
            let parts = Set([s.id] + ships.turrets(of: s).map { $0.id })
            print("encounters: \(s.name) made with \(ships.turrets(of: s).count) turrets, \(s.crewStations.count) crew posts, \(s.blockCount) blocks; mobs within 20: "
                  + g.mobs.mobs.filter { simd_length($0.pos - s.pos) < 20 }.map { "\($0.kind) \($0.health) deck \($0.deck === s ? "hers" : ($0.deck == nil ? "none" : "other"))" }.joined(separator: ", "))
            ShipManager.onRemove = { r in
                guard parts.contains(r.id) else { return }
                print("encounters: \(s.name): ship \(r.id) (\(r.role), parent \(r.parentId.map(String.init) ?? "none")) removed at frame \(frame)")
                for l in Thread.callStackSymbols.prefix(8) { print("encounters:    " + l) }
            }
            defer { ShipManager.onRemove = nil }
            for f in 0..<Int(secs * 30) {
                frame = f
                if f == 1 || f == 10 || f == 60 {
                    print(String(format: "encounters: %@ frame %d: %d turrets, %d blocks, at %.1f,%.1f,%.1f; ", s.name, f, ships.turrets(of: s).count, s.blockCount, s.pos.x, s.pos.y, s.pos.z)
                          + g.mobs.mobs.filter { simd_length($0.pos - s.pos) < 20 }.map { "\($0.kind) \($0.health) deck \($0.deck === s ? "hers" : ($0.deck == nil ? "none" : "other")) y \(Int($0.pos.y - s.pos.y))" }.joined(separator: ", "))
                }
                if f % 300 == 0 {
                    let ts = ships.turrets(of: s)
                    print(String(format: "encounters: %@ t %2d s: %.0f off, asleep %@, speed %.1f, autopilot %@, %d turrets (%d aimed), crew %d, engaged %@, timer %.1f",
                                 s.name, f / 30, simd_length(V2(s.pos.x - g.player.pos.x, s.pos.z - g.player.pos.z)), s.asleep ? "yes" : "no",
                                 simd_length(s.vel), s.autopilot.map { String(format: "%.1f,%.1f", $0.x, $0.y) } ?? "none", ts.count,
                                 ts.filter { $0.aimAt != nil }.count, g.mobs.mobs.filter { $0.deck === s && $0.health > 0 }.count,
                                 ships.gunsEngage(s, g) ? "yes" : "no", s.fireTimer)
                          + String(format: " (alive %@, survival %@, difficulty %d, won %@, %.0f off in 3D, last hurt by %@)", g.alive ? "yes" : "no",
                                   g.survival ? "yes" : "no", g.difficulty, Reckoning.won ? "yes" : "no", simd_length(g.player.pos + V3(0, 1, 0) - s.pos), lastHurt))
                }
                g.player.pos = under ? V3(Float(x) + 0.5, Float(surf - 4), Float(z) + 5.5) : raft
                g.player.vel = .zero
                g.tick(1.0 / 30)
                if g.health < 20 { hurt += 20 - g.health }
                g.health = 20; g.alive = true
                let ids = Set([s.id] + ships.turrets(of: s).map { $0.id })
                // (under the water, the rounds already on their way and the volley laid as he went down aren't counted)
                if !under || f >= 90 { for sh in ships.shells where ids.contains(sh.owner) && !early.contains(ObjectIdentifier(sh)) { seen.insert(ObjectIdentifier(sh)) } }
                else { for sh in ships.shells where ids.contains(sh.owner) { early.insert(ObjectIdentifier(sh)) } }
                closest = min(closest, simd_length(V2(s.pos.x - g.player.pos.x, s.pos.z - g.player.pos.z)))
            }
            return (closest, seen.count, hurt)
        }
        if let sl = hunter(cruiser: false) {
            let d0 = simd_length(V2(sl.pos.x - g.player.pos.x, sl.pos.z - g.player.pos.z))
            let (closest, fired, hurt) = play(sl, 90)
            check(sl.role == "sloop" && d0 > 100 && closest < d0 - 30 && fired > 0,
                  String(format: "encounters: a corsair sloop comes in from %.0f blocks, closes to %.0f in 90 s and fires %d rounds at him (%d half-hearts)", d0, closest, fired, hurt))
            ships.remove(sl)
        } else { check(false, "encounters: no corsair sloop came in 200 rolls") }
        // Week item 71 bloom (no pop-in): at view 12 the fog ends 180 out; the sails come in past it (they were made 150
        // off at any view), and stay awake on the way in.
        do {
            let rd0 = w.renderDistance
            w.renderDistance = 12
            defer { w.renderDistance = rd0 }
            _ = w.loadSync(center: raft, radius: 13)
            let fog = Float(w.renderDistance * CS - 12)
            if let sl = hunter(cruiser: false) {
                let d0 = simd_length(V2(sl.pos.x - g.player.pos.x, sl.pos.z - g.player.pos.z))
                for _ in 0..<300 { g.player.pos = raft; g.player.vel = .zero; g.tick(1.0 / 30); g.health = 20; g.alive = true }
                let d1 = simd_length(V2(sl.pos.x - g.player.pos.x, sl.pos.z - g.player.pos.z))
                check(d0 > fog && d1 < d0 - 10 && !sl.asleep,
                      String(format: "encounters: at view 12 a corsair sloop comes in from %.0f blocks (the fog ends %.0f out) and is %.0f off 10 s later (asleep %@)",
                             d0, fog, d1, sl.asleep ? "yes" : "no"))
                ships.remove(sl)
            } else { check(false, "encounters: at view 12 no corsair sloop came in 200 rolls") }
        }
        SeaHunt.hunters = []
        if let cr = hunter(cruiser: true) {
            let d0 = simd_length(V2(cr.pos.x - g.player.pos.x, cr.pos.z - g.player.pos.z))
            let corsairCrew = g.mobs.mobs.filter { $0.deck === cr }.count
            let (closest, fired, hurt) = play(cr, 90)
            check(cr.name == SeaHunt.cruiserName && d0 > 100 && closest < SeaHunt.reach && fired > 0,
                  String(format: "encounters: the Corsair Cruiser (%d crew) comes in from %.0f blocks, closes to %.0f and fires %d rounds (%d half-hearts)", corsairCrew, d0, closest, fired, hurt))
            // Under the water (head two blocks down): its guns lose him.
            let (_, firedUnder, _) = play(cr, 20, under: true)
            let hidden = SeaHunt.under(g)
            check(hidden && firedUnder <= 2, "encounters: two blocks under the water (\(hidden)) the cruiser's guns lose him (\(firedUnder) rounds after his first 3 s down, of 20)")
            // 450 blocks off (past it, away from it), it gives up and sails away.
            let away = simd_normalize(V2(g.player.pos.x - cr.pos.x, g.player.pos.z - cr.pos.z) + V2(1e-3, 0))
            g.player.pos = V3(cr.pos.x + away.x * 450, Float(surf + 1), cr.pos.z + away.y * 450)
            g.seaHuntTick(0.05)
            check(!ships.list.contains { $0 === cr }, "encounters: with him 450 blocks off the cruiser gives up the hunt")
        } else { check(false, "encounters: no Corsair Cruiser came in 200 rolls") }
        for s in ships.list where SeaHunt.isHunter(s) { ships.remove(s) }
        SeaHunt.hunters = []
    }
}
