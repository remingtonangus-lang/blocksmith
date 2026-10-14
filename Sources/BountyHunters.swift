import Foundation
import simd

// Bounty hunters (the gap pass: "bounty hunters at very low honour"). An outlaw, or anyone with a real price on their
// head across the towns, is now and then ridden down out in the wild. Never in a town, never in creative, never on
// Peaceful. Killing them is no crime and earns no honour (Honour.mobDied). Paying your bounties or your fine stops
// them: hunters ride off (are removed) once you're no longer wanted, or when they've been out five minutes and are far
// from you.
//
// R21 (Oct 13 evening, "bounty hunters: much rarer, never underground, and a real fight when they come"; reported
// again after P88/P115/O8 were marked done). What was really wrong:
//   - rate: the roll was 1 in 900 a second (a posse about every quarter hour in the open) with three in-game days
//     (one real hour) between, and any $25 on your head (one robbed rider) counted. Now: only real heat (an outlaw, or
//     $75+ across the towns: `worthHunting`), 1 in 2400 a second, six in-game days between, and an hour of play after
//     each posse is done (set out, came, or lost the trail) before the next can set out.
//   - underground: `below` read the heightmap, so a cave under an overhang the heightmap missed, or the bottom of a
//     ravine open to the sky, counted as the surface; and hunters already out kept chasing on sight into the cave
//     (only lockTime was cleared, and the AI re-acquired him at the mouth). Now below = natural rock over the head, no
//     daylight, or 12+ blocks under the land's own surface; while he's below the posse holds where it stands on the
//     surface (`holdOff`: their AI may not target him) and comes on again when he's back up. They spawn only on open
//     surface columns (sky light, not leaves, on his level), never in a cave or on a cliff top over him.
//   - the fight: five to eight townsfolk with six-irons and Brigands rushed in and died like any outlaw. Now a posse of
//     two to four on the soldier AI (Soldiers.swift: cover to reload, flanking, distance bands, suppressing fire,
//     reloads, callouts) with varied guns: a leader with a six-iron, a scattergun or repeater, a long rifle hanging
//     back, a second repeater or six-iron; 60 % more health than the rank, a tighter group than soldiers; they ride up
//     at low ready, call out when they spot you (a shout, then a beat before the first shot), and each carries a
//     bounty poster, cash and ammunition.
enum BountyHunters {
    static let name = "Bounty Hunter"
    static var chancePerSecond: Float = 1.0 / 10800      // P231: about once in three hours of play
    static let daysBetween = 6
    static let minBounty = 2500                     // wanted: hunters already out stay on you
    static let huntBounty = 7500                    // worth a posse setting out ($75)
    static let cooldown: Double = 10800             // seconds of play after a posse before the next sets out
    static var lastPosse: Double = -1e9
    static var holdOff = false                      // the player is below ground: the posse holds on the surface
    static var shouted = false                      // this posse has called out its challenge

    static var totalBounty: Int { (TownLaw.state.bounty ?? [:]).values.reduce(0, +) }
    static func wanted() -> Bool { Honour.isOutlaw || totalBounty >= minBounty }
    static func worthHunting() -> Bool { Honour.isOutlaw || totalBounty >= huntBounty }

    // TownLaw.tick, once a second.
    static func tick(_ g: Game) {
        leave(g)
        Riders.tick(g)
        // Gunmen (hunters, posses) stay on you while they're out (townsfolk anger fades on its own).
        let lost = below(g)
        holdOff = lost
        steer(g, hold: lost)
        for m in g.mobs.mobs where m.posse == 3 && m.kind == .villager && simd_length(m.pos - g.player.pos) < SixIron.chase && !lost { m.town.anger = max(m.town.anger, 5) }
        track(g)
        guard g.survival, g.difficulty > 0, g.dim.dim == .overworld, TownLaw.inTown == nil, !Reckoning.won, worthHunting() else { return }   // (P98: peace)
        let day = Int(g.time / DAY_LENGTH)
        guard TownLaw.state.trackers == nil, day - (TownLaw.state.huntersDay ?? -99) >= daysBetween, !lost,
              g.clock - lastPosse > cooldown, !g.mobs.mobs.contains(where: { isHunter($0) }),
              Rand.float(in: 0..<1) < chancePerSecond, g.clock - FactionRaids.lastAssault > FactionRaids.quiet else { return }   // (P215)
        setOut(g)
        TownLaw.state.huntersDay = day
        lastPosse = g.clock
        FactionRaids.lastAssault = g.clock
    }

    // The posse's orders, once a second: ride on toward the player (low ready, the soldier AI's march: followOrder)
    // until they spot him; while he's below ground, hold where they stand and forget him until he's back up.
    static func steer(_ g: Game, hold: Bool) {
        var anyAggro = false
        for m in g.mobs.mobs where isHunter(m) {
            let b = m.soldierBrain
            if hold {
                b.order = V3(m.pos.x, m.pos.y, m.pos.z)
                b.orderRun = false
                b.lastSeen = nil; b.hunt = nil
                m.aggro = false; m.lockTime = 0
                continue
            }
            b.order = g.player.pos
            b.orderRun = true
            if m.aggro { anyAggro = true }
        }
        // The challenge, once a posse (the soldier AI's own spotting gives each hunter a beat before his first shot).
        if anyAggro && !shouted {
            shouted = true
            let lines = ["\"That's the face on the poster! Drop your iron and come quiet!\"",
                         "\"Found you. There's paper on your head, and we mean to collect.\"",
                         "\"Spread out, boys! This one's worth more breathing, but not by much.\""]
            g.onToast?("Bounty hunter: " + lines[Rand.int(in: 0..<lines.count)])
            g.sfx(.goatHorn, 0.45)
        }
    }

    // O8: hunters track you across the map. When a posse is due it no longer appears out of nowhere: a party sets out
    // 450-600 blocks off and rides toward wherever you are at a canter (6 blocks a second: a galloping horse outruns
    // them, walking does not). They show on the map and minimap as a red ring, and when they close to 48 blocks the
    // posse rides in from their side. Underground they lose your trail and wait; in a town they wait outside it;
    // after twenty minutes out they give up. Pay your bounty and they turn back. Saved in TownLaw.state.trackers.
    static let trackSpeed: Float = 6
    static let trackSeconds: Float = 1200
    static let arriveAt: Float = 48

    static func setOut(_ g: Game) {
        let a = Rand.float(in: 0..<(2 * .pi)), r = Rand.float(in: 450...600)
        let x = g.player.pos.x + sinf(a) * r, z = g.player.pos.z + cosf(a) * r
        TownLaw.state.trackers = [x, z, trackSeconds]
        let dir = TownBoard.direction(x - g.player.pos.x, z - g.player.pos.z)
        g.onToast?("Bounty hunters have picked up your trail \(Int(r)) blocks to the \(dir) (\(Waymarks.side(g, V3(x, g.player.pos.y, z)))). They're on the map. Outride them, or go to ground")
        g.sfx(.goatHorn, 0.35)
    }

    // Where the party is (x, z), if one is out.
    static var party: V2? {
        guard let t = TownLaw.state.trackers, t.count >= 3 else { return nil }
        return V2(t[0], t[1])
    }

    // Once a second: the party rides on, waits or gives up; close enough, the posse comes.
    static func track(_ g: Game) {
        guard var t = TownLaw.state.trackers, t.count >= 3 else { return }
        if !wanted() || !g.survival || g.difficulty == 0 || Reckoning.won {
            TownLaw.state.trackers = nil
            return
        }
        guard g.dim.dim == .overworld else { return }          // they wait for you to come back
        t[2] -= 1
        if t[2] <= 0 {
            TownLaw.state.trackers = nil
            lastPosse = g.clock                                 // (the cooldown runs from the end of the hunt)
            g.onToast?("The bounty hunters have lost your trail")
            return
        }
        let p = V2(g.player.pos.x, g.player.pos.z)
        var at = V2(t[0], t[1])
        let off = p - at, d = simd_length(off)
        let hidden = below(g)
        if !hidden {
            // In a town they hold off at its edge (a posse never rides into one).
            let stop: Float = TownLaw.inTown != nil ? 96 : 0
            if d > stop { at += off / max(d, 1e-3) * min(trackSpeed, d - stop) }
        }
        t[0] = at.x; t[1] = at.y
        TownLaw.state.trackers = t
        let near = simd_length(p - at)
        if !hidden && near <= arriveAt && TownLaw.inTown == nil {
            if send(g, toward: at) > 0 {
                TownLaw.state.trackers = nil
                TownLaw.state.huntersDay = Int(g.time / DAY_LENGTH)
                lastPosse = g.clock
            }
        }
    }

    // The posse: two hunters for a bounty, three for an outlaw or $150+, four for an outlaw with $150+ on him.
    static func posseSize() -> Int {
        let big = totalBounty >= 15000
        return 2 + (Honour.isOutlaw ? 1 : 0) + (big ? 1 : 0)
    }

    // Who rides, in order: the leader with a six-iron (an officer: he points the others at you and quickens them),
    // a scattergun or repeater (a trooper: rushes in or swings round your flank), a long rifle (a marksman: keeps his
    // distance and moves after a shot), a repeater or six-iron (a recruit: falls back when hurt).
    static let roster: [(MobKind, [Int])] = [
        (.soldierOfficer, [Guns.revolver]),
        (.soldierTrooper, [Guns.shotgun, Guns.repeater]),
        (.soldierMarksman, [Guns.kessel]),
        (.soldierRecruit, [Guns.repeater, Guns.revolver]),
    ]

    static func makeHunter(_ g: Game, index i: Int, at p: V3) -> Mob {
        let (kind, guns) = roster[i % roster.count]
        let m = Mob(kind, at: p)
        m.variant = guns[Rand.int(in: 0..<guns.count)]
        m.customName = name
        m.spec.name = name
        m.spec.drops = [("bread", 0, 1)]
        m.posse = 3; m.posseSince = g.clock
        m.persistent = true
        m.home = p
        let hp = m.spec.health * 8 / 5
        m.spec.health = hp
        m.health = hp
        let b = m.soldierBrain
        b.ready = true
        b.order = g.player.pos
        b.orderRun = true
        m.aggro = false
        m.lockTime = 0
        m.face(g.player.pos)
        return m
    }

    // Spawns the posse; returns how many came.
    @discardableResult
    static func send(_ g: Game, toward: V2? = nil) -> Int {
        let w = g.world
        let n = posseSize()
        let pp = g.player.pos
        var placed = 0
        var from: V3?
        // O8: from the trackers' side when they ride in (a spread of +-35 degrees round it).
        let base = toward.map { atan2f($0.x - pp.x, $0.y - pp.z) }
        for k in 0..<(n * 16) where placed < n {
            let x: Int, z: Int
            if let f = from {
                // The rest ride in with the first, a few blocks round him.
                x = Int(floor(f.x + Rand.float(in: -6...6))); z = Int(floor(f.z + Rand.float(in: -6...6)))
            } else {
                let a = base.map { $0 + Rand.float(in: -0.6...0.6) } ?? Rand.float(in: 0..<(2 * .pi)), r = Rand.float(in: 30...42)
                x = Int(floor(pp.x + sinf(a) * r)); z = Int(floor(pp.z + cosf(a) * r))
            }
            guard w.isLoaded(x, z) else { continue }
            let top = w.topY(x, z), y = top + 1
            let ground = w.block(x, top, z)
            // Open ground on the surface, on his level: not water, not a tree's crown, not a cave or under a roof, not a
            // cliff top over a ravine he's in.
            guard Blocks.collide[Int(ground)], !Blocks.isLiquid(ground), !Blocks.isLiquid(w.block(x, y, z)),
                  !Blocks.key(Blocks.groupBase[Int(ground)]).hasSuffix("_leaves"),
                  w.lightAt(x, y, z).sky >= 12, abs(Float(y) - pp.y) < 12 else { continue }
            let at = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
            // Out of the player's sight if we can (the first few tries), so they ride in.
            if from == nil && k < 24 && w.canSee(at + V3(0, 1.6, 0), g.player.eye) { continue }
            let m = makeHunter(g, index: placed, at: w.freeSpawn(at))
            if m.collides(m.pos, w) { continue }
            if placed == 0 { from = at }
            g.mobs.mobs.append(m)
            placed += 1
        }
        if placed > 0 {
            sent += 1
            shouted = false
            let side = from.map { " from the " + TownBoard.direction($0.x - pp.x, $0.z - pp.z) } ?? ""
            g.onToast?((Honour.isOutlaw ? "Bounty hunters are on your trail, outlaw" : "Bounty hunters are after the \(Money.format(totalBounty)) on your head") + ": \(placed) riding in\(side)")
            g.sfx(.goatHorn, 0.5)
        }
        return placed
    }
    static var sent = 0

    // Below ground (P115, R21: "they must not find him underground"): natural rock over the head, no daylight reaching
    // him, or well under the land's own surface (a ravine floor, a pit). No posse sets out then, and one already out
    // holds on the surface (`holdOff`) until he's back up.
    static func below(_ g: Game) -> Bool {
        let p = g.player.pos, x = Int(floor(p.x)), y = Int(floor(p.y)), z = Int(floor(p.z))
        let w = g.world
        guard w.isLoaded(x, z) else { return false }
        if w.lightAt(x, y + 1, z).sky < 8 || Mob.underground(w, x, y, z) { return true }
        if g.dim.dim == .overworld {
            let land: Float = Float(w.gen.column(x, z).height)
            if land - p.y > 12 { return true }
        }
        return false
    }
    static func isHunter(_ m: Mob) -> Bool { m.posse == 3 && m.health > 0 && m.customName == name }
    static let lifetime: Double = 300

    // A hunter's body (Game.soldierDied): his copy of your poster, his purse and a little of what he carried.
    static func loot(_ g: Game, _ m: Mob, at: V3) {
        guard m.posse == 3, m.customName == name else { return }
        if Items.has("paper") {
            var poster = ItemStack(Items.id("paper"), 1)
            poster.label = "Bounty Poster (\(Money.format(max(totalBounty, huntBounty))))"
            g.drops.spawn(poster, at: at)
        }
        for (k, lo, hi) in [("gold_nugget", 2, 6), ("bread", 0, 2)] where Items.has(k) {
            let c = Rand.int(in: lo...hi)
            if c > 0 { g.drops.spawn(ItemStack(Items.id(k), c), at: at) }
        }
        if m.killedByPlayer && g.survival {
            let cash = Rand.int(in: 6...20) * 100
            g.money += cash
            g.onToast?("The hunter's purse: \(Money.format(cash))")
        }
    }

    // P51: killed with hunters or a posse on you, they collect: every bounty is paid off and your purse is gone.
    static func claim(_ g: Game) {
        guard g.survival, g.mobs.mobs.contains(where: { $0.posse == 3 && $0.health > 0 && !Director.owns($0) && simd_length($0.pos - g.player.pos) < 48 }),
              totalBounty > 0 || Honour.isOutlaw else { return }   // (nothing on your head: they have no claim)
        TownLaw.state.bounty = [:]
        g.money = 0
        g.onToast?("The hunters collect: your bounty is paid off with every cent you had")
    }

    // Hunters ride off when the job's gone (you paid up), or after five minutes out of sight range (they're named, so
    // they would never despawn on their own).
    static func leave(_ g: Game) {
        let paid = !wanted() || !g.survival || g.difficulty == 0
        g.mobs.mobs.removeAll { m in
            guard m.posse == 3, m.health > 0, !Director.owns(m) else { return false }     // (P266: the Director's gunmen stay)
            let far = simd_length(m.pos - g.player.pos) > 48
            return (paid && far) || (far && (m.posseSince < 0 || g.clock - m.posseSince > lifetime))
                || simd_length(m.pos - g.player.pos) > 128
        }
    }
}
