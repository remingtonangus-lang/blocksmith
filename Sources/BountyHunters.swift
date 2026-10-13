import Foundation
import simd

// Bounty hunters (the gap pass: "bounty hunters at very low honour"). An outlaw, or anyone with $25 or more on their
// head across the towns, is now and then ridden down out in the wild: two or three hunters (a Brigand with a
// crossbowman, a third when the price is $50+) turn up 22-30 blocks off, out of sight, and come straight for them.
// At most once an in-game day (TownLaw.Saved.huntersDay), never in a town, never in creative. Killing them is no
// crime and earns no honour (Honour.mobDied). Paying your bounties or your fine stops them: hunters ride off (are
// removed) once you're no longer wanted, or when they've been out five minutes and are far from you. Never on Peaceful.
enum BountyHunters {
    static let name = "Bounty Hunter"
    // P115 (Oct 12 PM: "much rarer, but when they come they are many and a real problem"): about once every quarter
    // hour out in the wild while wanted, at most once every three in-game days, and never while you're underground.
    static var chancePerSecond: Float = 1.0 / 900
    static let daysBetween = 3
    static let minBounty = 2500

    static var totalBounty: Int { (TownLaw.state.bounty ?? [:]).values.reduce(0, +) }
    static func wanted() -> Bool { Honour.isOutlaw || totalBounty >= minBounty }

    // TownLaw.tick, once a second.
    static func tick(_ g: Game) {
        leave(g)
        Riders.tick(g)
        // Gunmen (hunters, posses) stay on you while they're out (townsfolk anger fades on its own).
        let lost = below(g)
        for m in g.mobs.mobs where m.posse == 3 && m.customName == name && lost { m.lockTime = 0; m.aggro = false; m.target = nil }
        for m in g.mobs.mobs where m.posse == 3 && m.kind == .villager && simd_length(m.pos - g.player.pos) < SixIron.chase && !lost { m.town.anger = max(m.town.anger, 5) }
        track(g)
        guard g.survival, g.difficulty > 0, g.dim.dim == .overworld, TownLaw.inTown == nil, !Reckoning.won, wanted() else { return }   // (P98: peace)
        let day = Int(g.time / DAY_LENGTH)
        guard TownLaw.state.trackers == nil, day - (TownLaw.state.huntersDay ?? -99) >= daysBetween, !below(g),
              Rand.float(in: 0..<1) < chancePerSecond, g.clock - FactionRaids.lastAssault > FactionRaids.quiet else { return }   // (P215)
        setOut(g)
        TownLaw.state.huntersDay = day
        FactionRaids.lastAssault = g.clock
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
        g.onToast?("Bounty hunters have picked up your trail \(Int(r)) blocks to the \(dir). They're on the map. Outride them, or go to ground")
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
            if send(g, toward: at) > 0 { TownLaw.state.trackers = nil }
        }
    }

    // Spawns the posse; returns how many came.
    @discardableResult
    static func send(_ g: Game, toward: V2? = nil) -> Int {
        let w = g.world
        // P88 (Oct 12 AM, "bounty hunters must be a big deal, like RDR2"): a bigger, harder posse (three, four at $50 or
        // as an outlaw, five as an outlaw with $50 on you), two of them with six-irons, all tougher; they ride in from
        // further off, show on the map and minimap (MapDraw.markers) and the music turns (Game.combatTick).
        // P115: rarer, so a real crowd: five to eight, four of them with six-irons.
        let big = totalBounty >= 5000
        let n = Honour.isOutlaw ? (big ? 8 : 7) : (big ? 6 : 5)
        var placed = 0
        var from: V3?
        for k in 0..<(n * 12) where placed < n {           // (12 tries a rider: the P88 ring is wider and has more water)
            // O8: from the trackers' side when they ride in (a spread of +-35 degrees round it).
            let base = toward.map { atan2f($0.x - g.player.pos.x, $0.y - g.player.pos.z) }
            let a = base.map { $0 + Rand.float(in: -0.6...0.6) } ?? Rand.float(in: 0..<(2 * .pi)), r = Rand.float(in: 30...42)
            let x = Int(floor(g.player.pos.x + sinf(a) * r)), z = Int(floor(g.player.pos.z + cosf(a) * r))
            guard w.isLoaded(x, z) else { continue }
            let y = w.topY(x, z) + 1
            guard !Blocks.isLiquid(w.block(x, y - 1, z)), !Blocks.isLiquid(w.block(x, y, z)) else { continue }
            let at = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
            // Out of the player's sight if we can (the first few tries), so they ride in.
            if k < 16 && w.canSee(at + V3(0, 1.6, 0), g.player.eye) { continue }
            // P51: the first hunter carries a six-iron (an armed townsperson, Riders.gunman); the others are Brigands.
            let m: Mob
            if placed < 4 { m = Riders.gunman(g, at: w.freeSpawn(at), role: "posse", name: name); m.health = m.spec.health * 2 }
            else {
                m = Mob(placed % 2 == 0 ? .pillager : .vindicator, at: w.freeSpawn(at))
                m.customName = name
                m.posse = 3; m.posseSince = g.clock
                m.aggro = true; m.lockTime = 30         // they know where you are (Brigands track inside 32 blocks)
                m.health = m.spec.health * 2
            }
            if placed == 0 { from = at }
            if m.collides(m.pos, w) { continue }
            g.mobs.mobs.append(m)
            placed += 1
        }
        if placed > 0 {
            sent += 1
            let side = from.map { " from the " + TownBoard.direction($0.x - g.player.pos.x, $0.z - g.player.pos.z) } ?? ""
            g.onToast?((Honour.isOutlaw ? "Bounty hunters are on your trail, outlaw" : "Bounty hunters are after the \(Money.format(totalBounty)) on your head") + ": \(placed) riding in\(side)")
            g.sfx(.goatHorn, 0.5)
        }
        return placed
    }
    static var sent = 0

    // Below ground (P115: "they must not find him underground"): rock 4+ blocks over the head, or no daylight reaching
    // him. No posse sets out then, and one already out loses him: it stops coming on (lockTime 0) until he's back up.
    static func below(_ g: Game) -> Bool {
        let p = g.player.pos, x = Int(floor(p.x)), y = Int(floor(p.y)), z = Int(floor(p.z))
        guard g.world.isLoaded(x, z) else { return false }
        return g.world.topY(x, z) >= y + 4 || g.world.lightAt(x, y + 1, z).sky < 8
    }
    static func isHunter(_ m: Mob) -> Bool { m.posse == 3 && m.health > 0 && m.customName == name }
    static let lifetime: Double = 300

    // P51: killed with hunters or a posse on you, they collect: every bounty is paid off and your purse is gone.
    static func claim(_ g: Game) {
        guard g.survival, g.mobs.mobs.contains(where: { $0.posse == 3 && $0.health > 0 && simd_length($0.pos - g.player.pos) < 48 }),
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
            guard m.posse == 3, m.health > 0 else { return false }
            let far = simd_length(m.pos - g.player.pos) > 48
            return (paid && far) || (far && (m.posseSince < 0 || g.clock - m.posseSince > lifetime))
                || simd_length(m.pos - g.player.pos) > 128
        }
    }
}
