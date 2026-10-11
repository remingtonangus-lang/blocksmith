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
    static var chancePerSecond: Float = 1.0 / 240      // about once every four minutes out in the wild while wanted
    static let minBounty = 2500

    static var totalBounty: Int { (TownLaw.state.bounty ?? [:]).values.reduce(0, +) }
    static func wanted() -> Bool { Honour.isOutlaw || totalBounty >= minBounty }

    // TownLaw.tick, once a second.
    static func tick(_ g: Game) {
        leave(g)
        Riders.tick(g)
        // Gunmen (hunters, posses) stay on you while they're out (townsfolk anger fades on its own).
        for m in g.mobs.mobs where m.posse == 3 && m.kind == .villager && simd_length(m.pos - g.player.pos) < SixIron.chase { m.town.anger = max(m.town.anger, 5) }
        guard g.survival, g.difficulty > 0, g.dim.dim == .overworld, TownLaw.inTown == nil, wanted() else { return }
        let day = Int(g.time / DAY_LENGTH)
        guard (TownLaw.state.huntersDay ?? -99) < day, Rand.float(in: 0..<1) < chancePerSecond else { return }
        if send(g) > 0 { TownLaw.state.huntersDay = day }
    }

    // Spawns the posse; returns how many came.
    @discardableResult
    static func send(_ g: Game) -> Int {
        let w = g.world
        let n = totalBounty >= 5000 || (Honour.isOutlaw && totalBounty >= minBounty) ? 3 : 2
        var placed = 0
        for k in 0..<24 where placed < n {
            let a = Rand.float(in: 0..<(2 * .pi)), r = Rand.float(in: 22...30)
            let x = Int(floor(g.player.pos.x + sinf(a) * r)), z = Int(floor(g.player.pos.z + cosf(a) * r))
            guard w.isLoaded(x, z) else { continue }
            let y = w.topY(x, z) + 1
            guard !Blocks.isLiquid(w.block(x, y - 1, z)), !Blocks.isLiquid(w.block(x, y, z)) else { continue }
            let at = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
            // Out of the player's sight if we can (the first few tries), so they ride in.
            if k < 16 && w.canSee(at + V3(0, 1.6, 0), g.player.eye) { continue }
            // P51: the first hunter carries a six-iron (an armed townsperson, Riders.gunman); the others are Brigands.
            let m: Mob
            if placed == 0 { m = Riders.gunman(g, at: w.freeSpawn(at), role: "posse", name: name) }
            else {
                m = Mob(placed == 1 ? .pillager : .vindicator, at: w.freeSpawn(at))
                m.customName = name
                m.posse = 3; m.posseSince = g.clock
                m.aggro = true; m.lockTime = 30         // they know where you are (Brigands track inside 32 blocks)
                m.health = m.spec.health * 5 / 4
            }
            if m.collides(m.pos, w) { continue }
            g.mobs.mobs.append(m)
            placed += 1
        }
        if placed > 0 {
            sent += 1
            g.onToast?(Honour.isOutlaw ? "Bounty hunters are on your trail, outlaw" : "Bounty hunters are after the \(Money.format(totalBounty)) on your head")
            g.sfx(.goatHorn, 0.5)
        }
        return placed
    }
    static var sent = 0
    static let lifetime: Double = 300

    // P51: killed with hunters or a posse on you, they collect: every bounty is paid off and your purse is gone.
    static func claim(_ g: Game) {
        guard g.survival, g.mobs.mobs.contains(where: { $0.posse == 3 && $0.health > 0 && simd_length($0.pos - g.player.pos) < 48 }),
              totalBounty > 0 || g.money > 0 else { return }
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
