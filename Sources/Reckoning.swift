import Foundation
import simd

// The endgame (P46, reworked for P98, Oct 12 playtest). Once the Ashguard has fallen below hell and the player is back on
// the surface, every power in the land comes for them at once: big hunting groups of the Marauder clans, the Capital,
// Greywall Command, the Stormwarden Fleet's Aegis Marines and the restless dead march on the player from 450-700 blocks
// out and follow them across the whole surface. Going underground is the only escape: the groups lose the trail and
// wait where they last saw the player, and pick it up again when they come back up. The hunt ends only when every
// group is dead; then the surface is at peace for good (no Marauder patrols, bounty hunters, town raids or Capital
// patrols against the player). Not in creative or on Peaceful.
//
// Quest-safe: a group is a marker on the map (side, position, the units it still has) until it is within `near` of
// the player; then its units come in out of sight, at most `liveCap` alive at once over all groups, nearest groups
// first. A unit that falls `lost` behind goes back into its group. A death pushes every group `deathPush` back out.
// Saved as "reckoning" (stage, timer) and "reckoningHunts" (each group with the units it has left).
enum Reckoning {
    enum Side: Int, CaseIterable {
        case marauders = 0, capital, greywall, stormwarden, dead
        var name: String { ["Marauder clans", "the Capital", "Greywall Command", "Stormwarden Aegis Marines", "the restless dead"][rawValue] }
        var pace: Float { [5, 3.2, 3.2, 3.4, 2.4][rawValue] }          // blocks a second on the march (Marauders ride)
        var groups: Int { [2, 2, 1, 1, 2][rawValue] }
        // One group's units (mob keys); Greywall troops get their base suffix, the others a faction.
        var roster: [String] {
            switch self {
            case .marauders: return ["pillager", "pillager", "pillager", "pillager", "pillager", "vindicator", "vindicator", "vindicator",
                                     "pillager", "ravager", "vindicator", "pillager"]
            case .capital: return ["soldier_recruit", "soldier_recruit", "soldier_recruit", "soldier_trooper", "soldier_trooper", "soldier_trooper",
                                   "soldier_marksman", "soldier_marksman", "soldier_ironclad", "soldier_officer", "soldier_recruit", "soldier_trooper"]
            case .greywall: return ["soldier_recruit", "soldier_trooper", "soldier_trooper", "soldier_trooper", "soldier_marksman", "soldier_marksman",
                                    "soldier_ironclad", "soldier_ironclad", "soldier_officer", "soldier_trooper", "soldier_recruit", "soldier_recruit"]
            case .stormwarden: return ["soldier_trooper", "soldier_trooper", "soldier_trooper", "soldier_ironclad", "soldier_ironclad", "soldier_ironclad",
                                       "soldier_marksman", "soldier_trooper", "soldier_ironclad", "soldier_officer"]
            case .dead: return ["husk", "husk", "husk", "husk", "wither_skeleton", "wither_skeleton", "spider", "spider", "creeper", "creeper",
                                "husk", "wither_skeleton", "spider", "husk"]
            }
        }
        var faction: Faction { [.none, .steelhold, .greywall, .stormwarden, .none][rawValue] }
    }

    final class Hunt {
        let side: Side
        var pos: V2                     // the group (its marker; the centre of its units while they're in)
        var waiting: [String]           // units not in the world (still marching, or pulled back)
        var live: [Mob] = []            // units in the world now
        var trail: V2?                  // where it lost the player (underground): it waits there
        var tries = 0                   // spawn spots refused for being in plain sight
        var nextTry: Double = 0         // ... and when it may try again (g.clock)
        var landed = false              // T16: its dropship squad has been flown in (soldier bands)
        var warship = false             // T16: the Stormwarden band's frigate has come over
        init(side: Side, pos: V2, waiting: [String]) { self.side = side; self.pos = pos; self.waiting = waiting }
        var left: Int { waiting.count + live.filter { $0.health > 0 }.count }
    }

    static let posseBase = 10           // Mob.posse of a hunt's unit: posseBase + its group (saved with the mob)
    static let warning: Float = 60      // back on the surface to the groups setting out
    static let start: ClosedRange<Float> = 450...700
    static let near: Float = 72         // a group this close brings its units in
    static let lost: Float = 130        // a unit this far behind goes back into its group
    // P460 (Oct 25 17:05-17:08, the hunt in the jungle: "There's way too many red soldiers... I think they just keep
    // spawning", the frame rate down to 30): 14 at once (was 24); the rest stay in their groups until some fall.
    static let liveCap = 14             // units alive at once over every group
    static let reward = 25000           // $250
    static let deathPush: Float = 250

    static var stage = 0                // 0 not begun, 1 the warning, 2 hunted, 3 won
    static var timer: Float = 0         // the warning's seconds left
    static var hunts: [Hunt] = []
    static var underground = false      // the player is below the surface (the groups have lost the trail)
    static var won: Bool { stage == 3 }
    static var groupsLeft: Int { hunts.filter { $0.left > 0 }.count }
    private static var gameID: ObjectIdentifier?

    static func reset() { stage = 0; timer = 0; hunts = []; underground = false }
    static func own(_ g: Game) {
        let id = ObjectIdentifier(g)
        if gameID != id { reset(); gameID = id }
    }

    static func save(_ d: inout [String: String]) {
        guard stage > 0 else { return }
        d["reckoning"] = "\(stage),\(timer)"
        // Units in the world are saved back into their groups (they come in again out of sight after a load).
        d["reckoningHunts"] = hunts.map { h in
            let units = h.waiting + h.live.filter { $0.health > 0 }.map { $0.kind.key }
            return "\(h.side.rawValue),\(Int(h.pos.x)),\(Int(h.pos.y)),\(units.joined(separator: "|"))"
        }.joined(separator: ";")
    }
    static func load(_ d: [String: String], game: Game) {
        gameID = ObjectIdentifier(game)
        reset()
        let p = (d["reckoning"] ?? "").split(separator: ",").map(String.init)
        stage = p.count > 0 ? max(0, min(3, Int(p[0]) ?? 0)) : 0
        if p.count == 4 { stage = stage == 2 ? 3 : (stage == 1 ? 2 : stage) }    // a P46 save: won stays won, mid-waves is hunted
        timer = p.count == 2 ? Float(p[1]) ?? warning : 0
        for s in (d["reckoningHunts"] ?? "").split(separator: ";") {
            let f = s.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 4, let r = Int(f[0]), let side = Side(rawValue: r), let x = Float(f[1]), let z = Float(f[2]) else { continue }
            let units = f[3].split(separator: "|").map(String.init)
            if !units.isEmpty { hunts.append(Hunt(side: side, pos: V2(x, z), waiting: units)) }
        }
        if stage == 2 && hunts.isEmpty && d["reckoningHunts"] == nil { begin(game) }      // a P46 save mid-waves: new groups
    }

    static func isHunter(_ m: Mob) -> Bool { m.posse >= posseBase && m.posse < posseBase + 40 }
    static func members(_ g: Game) -> [Mob] { hunts.flatMap { $0.live }.filter { $0.health > 0 } }

    // The groups set out from all around, `start` blocks off.
    static func begin(_ g: Game) {
        hunts = []
        let p = V2(g.player.pos.x, g.player.pos.z)
        let n = Side.allCases.reduce(0) { $0 + $1.groups }
        let a0 = Rand.float(in: 0..<(2 * .pi))
        let scale: Float = [0, 0.75, 1, 1.25][max(0, min(3, g.difficulty))]
        var i = 0
        for side in Side.allCases { for _ in 0..<side.groups {
            let a = a0 + Float(i) * 2 * .pi / Float(n) + Rand.float(in: -0.2...0.2), r = Rand.float(in: start)
            var roster = side.roster
            let keep = max(6, Int((Float(roster.count) * scale).rounded()))
            if keep < roster.count { roster.removeLast(roster.count - keep) } else { roster += roster.prefix(keep - roster.count) }
            hunts.append(Hunt(side: side, pos: p + V2(sinf(a), cosf(a)) * r, waiting: roster))
            i += 1
        } }
    }

    // Once a second (Game.ashTick's slot).
    static func tick(_ g: Game, _ dt: Float) {
        own(g)
        guard g.ashVictory, stage < 3, g.survival, g.difficulty > 0 else { return }
        // Strays: hunt units no group knows (saved with the world: their group has them back as waiting) go.
        g.mobs.mobs.removeAll { m in (m.posse == 4 && m.persistent) || isHunter(m) && !hunts.contains { h in h.live.contains { $0 === m } } }   // (4: P46's waves)
        guard g.dim.dim == .overworld else { return }
        if !g.alive {
            let p = V2(g.player.pos.x, g.player.pos.z)
            for h in hunts {
                pullBack(g, h)
                let off = h.pos - p, d = simd_length(off)
                if d < deathPush { h.pos = p + (d > 1 ? off / d : V2(1, 0)) * deathPush }
            }
            return
        }
        switch stage {
        case 0:
            stage = 1; timer = warning
            g.onToast?("Word of the Ashguard's fall has spread. Every army in the land is marching on you")
            g.sfx(.goatHorn, 0.7)
        case 1:
            timer -= dt
            guard timer <= 0 else { return }
            stage = 2; begin(g)
            g.onToast?("\(hunts.count) war bands are hunting you")
            g.sfx(.goatHorn, 0.9)
        default:
            hunt(g, dt)
        }
    }

    static func isUnderground(_ g: Game) -> Bool {
        let p = g.player.pos, x = Int(floor(p.x)), y = Int(floor(p.y)), z = Int(floor(p.z))
        guard g.world.isLoaded(x, z) else { return false }
        return g.world.topY(x, z) >= y + 6 && g.world.lightAt(x, y + 1, z).sky == 0
    }

    static func hunt(_ g: Game, _ dt: Float) {
        let p = V2(g.player.pos.x, g.player.pos.z)
        let down = isUnderground(g)
        if down != underground {
            underground = down
            g.onToast?(down ? "Underground: the war bands have lost your trail" : "Back on the surface: the war bands pick up your trail")
            for h in hunts { h.trail = down ? p : nil }
        }
        for h in hunts {
            // Units unloaded with their chunks (gone from the mob list alive) go back into the group; the dead are gone.
            for m in h.live where m.health > 0 && !g.mobs.mobs.contains(where: { $0 === m }) { h.waiting.append(m.kind.key); m.health = 0 }
            // Far behind: back into the group.
            for m in h.live where m.health > 0 && simd_length(V2(m.pos.x, m.pos.z) - p) > lost {
                h.waiting.append(m.kind.key); m.health = 0
                g.mobs.mobs.removeAll { $0 === m }
            }
            h.live.removeAll { $0.health <= 0 }
            // March and track.
            if !h.live.isEmpty {
                var c = V2(0, 0)
                for m in h.live { c += V2(m.pos.x, m.pos.z) }
                h.pos = c / Float(h.live.count)
            } else {
                let goal = h.trail ?? p, to = goal - h.pos, d = simd_length(to)
                let stop: Float = h.trail == nil ? near * 0.8 : 4
                if d > stop { h.pos += to / d * min(d - stop, h.side.pace * dt) }
            }
            for m in h.live {
                if down { m.aggro = false; m.lockTime = 0; continue }
                m.aggro = true; m.lockTime = max(m.lockTime, 10)
                if m.kind.key.hasPrefix("soldier_") { m.soldierBrain.lastSeen = g.player.eye; m.soldierBrain.seenAgo = min(m.soldierBrain.seenAgo, 1) }
            }
        }
        // T16 (P98 leftover: "no dropship arrivals or navy ships in the Reckoning"): a soldier band closing in flies its
        // first squad in by dropship (up to six of its waiting troops land beside the player, as a base alarm's do),
        // and the Stormwarden band brings its warship: a frigate set over the band, hunting the player from the air.
        if !down {
            for h in hunts where h.side.faction != .none {
                let d = simd_length(h.pos - p)
                if !h.landed && d < near * 2.2 && h.waiting.count >= 4 {
                    let n = min(6, h.waiting.count - 2)
                    let from = V3(h.pos.x, g.player.pos.y + 40, h.pos.y)
                    if g.world.ships.callDropship(faction: h.side.faction, from: from, to: g.player.pos, game: g, troops: n) {
                        h.landed = true
                        h.waiting.removeLast(n)
                        g.onToast?("A \(h.side == .greywall ? "Greywall" : h.side == .capital ? "Capital" : "Stormwarden") dropship is coming in with a squad")
                    } else { h.landed = g.stormGrounds ? false : true }          // (a storm: it tries again when it clears)
                }
                if h.side == .stormwarden && !h.warship && d < 260 {
                    h.warship = true
                    let at = h.pos + simd_normalize(h.pos - p + V2(0.01, 0)) * 60
                    g.world.ships.spawnCapital("warfrigate", home: IVec3(Int(at.x), 0, Int(at.y)), yaw: atan2f(-(p.x - at.x), -(p.y - at.y)),
                                               region: nil, faction: .stormwarden)
                    g.onToast?("A Stormwarden warship joins the hunt")
                }
            }
        }
        // Bring units in, nearest groups first, while the player is on the surface.
        var alive = hunts.reduce(0) { $0 + $1.live.count }
        if !down {
            for h in hunts.sorted(by: { simd_length($0.pos - p) < simd_length($1.pos - p) }) {
                guard alive < liveCap, simd_length(h.pos - p) < near else { break }
                var tries = 0
                while let k = h.waiting.last, alive < liveCap, tries < 12 {
                    tries += 1
                    guard let m = spawn(g, h, k) else { if g.clock < h.nextTry { break }; continue }
                    h.waiting.removeLast()
                    h.live.append(m); alive += 1
                }
            }
        }
        // Groups wiped out.
        for (i, h) in hunts.enumerated().reversed() where h.left == 0 {
            hunts.remove(at: i)
            if !hunts.isEmpty { g.onToast?("A band of \(h.side.name) is wiped out. \(hunts.count) left hunting you") }
        }
        // Units keep their group's number in posse (after removals the indices move).
        for (i, h) in hunts.enumerated() { for m in h.live { m.posse = posseBase + i } }
        if hunts.isEmpty {
            stage = 3
            g.money += reward
            g.onToast?("The last war band is destroyed. The land is at peace with you for good (+\(Money.format(reward)))")
            g.sfx(.goatHorn, 1)
        }
    }

    // One unit in out of sight, 36-56 blocks from the player on the group's side.
    static func spawn(_ g: Game, _ h: Hunt, _ k: String) -> Mob? {
        let w = g.world, p = V2(g.player.pos.x, g.player.pos.z)
        let off = h.pos - p, d = simd_length(off)
        let dir = d > 1 ? off / d : V2(1, 0)
        let a = atan2f(dir.x, dir.y) + Rand.float(in: -0.7...0.7), r = Rand.float(in: 36...56)
        let x = Int(floor(p.x + sinf(a) * r)), z = Int(floor(p.y + cosf(a) * r))
        guard w.isLoaded(x, z) else { return nil }
        let y = w.topY(x, z) + 1
        guard !Blocks.isLiquid(w.builtBlock(x, y - 1, z)), !Blocks.isLiquid(w.builtBlock(x, y, z)) else { return nil }
        let at = w.freeSpawn(V3(Float(x) + 0.5, Float(y), Float(z) + 0.5))
        // Not in plain sight: a unit appearing from nowhere 40 blocks off reads as a pop-in (they come over a rise,
        // round a wall or out of the trees). After a few tries a band takes what ground it gets.
        // (One look a band a second: a refused spot holds the band back a second, and the fifth in a row is taken.)
        if g.clock < h.nextTry { return nil }
        if h.tries < 5 && w.canSee(g.player.eye, at + V3(0, 1.5, 0)) { h.tries += 1; h.nextTry = g.clock + 1; return nil }
        h.tries = 0
        let m: Mob
        if h.side == .greywall {
            guard let gm = Mob.structureMob("\(k)@grey", at: at) else { return nil }
            m = gm
        } else {
            guard let kind = MobKind.named(k) else { return nil }
            m = Mob(kind, at: at)
            if h.side.faction != .none { m.faction = h.side.faction.rawValue }
            if h.side == .stormwarden && kind == .soldierIronclad { m.variant = Guns.arc }
        }
        if m.collides(m.pos, w) { return nil }
        m.posse = posseBase + (hunts.firstIndex { $0 === h } ?? 0)
        m.persistent = true
        m.aggro = true; m.lockTime = 30
        if m.kind.key.hasPrefix("soldier_") { m.soldierBrain.lastSeen = g.player.eye; m.soldierBrain.seenAgo = 0 }
        g.mobs.mobs.append(m)
        return m
    }

    // The player died: a group's units in the world go back into it.
    static func pullBack(_ g: Game, _ h: Hunt) {
        for m in h.live where m.health > 0 { h.waiting.append(m.kind.key) }
        g.mobs.mobs.removeAll { m in h.live.contains { $0 === m } }
        h.live = []
    }
}
