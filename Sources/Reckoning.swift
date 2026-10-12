import Foundation
import simd

// P46 (Oct 11 evening playtest): the endgame. Once the Ashguard has fallen below hell and the player is back on the
// surface, word spreads and every power in the land comes for them: five waves (the Marauder clans, the Capital, the
// Stormwarden Fleet, the restless dead, then every banner at once) close in from out of sight, the soldiers partly by
// dropship. Beat the last wave and the surface is yours: Marauder patrols stop for good. Not in creative or on
// Peaceful; a death sends the wave home and it comes again after a breather. Saved as "reckoning".
enum Reckoning {
    struct Group { let kind: MobKind; let n: Int; let faction: Faction }
    struct Wave { let intro: String; let groups: [Group]; let dropships: [Faction] }
    static let waves: [Wave] = [
        Wave(intro: "The Marauder clans ride for you", groups: [Group(kind: .pillager, n: 5, faction: .none), Group(kind: .vindicator, n: 3, faction: .none),
                                                              Group(kind: .ravager, n: 1, faction: .none)], dropships: []),
        Wave(intro: "The Capital sends its garrison after you", groups: [Group(kind: .soldierRecruit, n: 3, faction: .steelhold), Group(kind: .soldierTrooper, n: 2, faction: .steelhold),
                                                                        Group(kind: .soldierMarksman, n: 1, faction: .steelhold)], dropships: [.steelhold]),
        Wave(intro: "The Stormwarden Fleet is landing", groups: [Group(kind: .soldierTrooper, n: 2, faction: .stormwarden), Group(kind: .soldierIronclad, n: 1, faction: .stormwarden)],
             dropships: [.stormwarden, .stormwarden]),
        Wave(intro: "The dead walk out to meet you", groups: [Group(kind: .husk, n: 5, faction: .none), Group(kind: .witherSkeleton, n: 2, faction: .none),
                                                             Group(kind: .spider, n: 3, faction: .none), Group(kind: .creeper, n: 2, faction: .none)], dropships: []),
        Wave(intro: "Every banner in the land, at once", groups: [Group(kind: .pillager, n: 3, faction: .none), Group(kind: .vindicator, n: 2, faction: .none),
                                                                 Group(kind: .ravager, n: 1, faction: .none), Group(kind: .soldierTrooper, n: 2, faction: .steelhold),
                                                                 Group(kind: .soldierTrooper, n: 2, faction: .stormwarden), Group(kind: .witherSkeleton, n: 1, faction: .none)],
             dropships: [.steelhold, .stormwarden]),
    ]
    static let posse = 4                 // Mob.posse of a horde member (saved with the mob)
    static let warning: Float = 60       // back on the surface to the first wave
    static let breather: Float = 25      // between waves
    static let minWave: Float = 40       // a wave with dropships stays up at least this long (its troops are still flying in)
    static let reward = 25000            // $250
    static let rejoin: Float = 20        // seconds a reloaded wave has for its troops to load back in
    static let retry: Float = 5          // seconds before a wave that found no ground tries again

    static var stage = 0                 // 0 not begun, 1 under way, 2 won
    static var wave = 0                  // the wave to send next (stage 1), or the one in the field
    static var timer: Float = 0          // > 0: seconds to the next wave
    static var inField = false           // a wave is out
    static var age: Float = 0            // seconds the wave in the field has been out
    static var won: Bool { stage == 2 }
    static var dropshipsOn = true        // the host check turns the dropships off (they are checked in --ridecheck)
    private static var gameID: ObjectIdentifier?    // the game (save) this state belongs to (a new world starts clean;
                                                    // not the World, which changes with every dimension)

    static func reset() { stage = 0; wave = 0; timer = 0; inField = false; age = 0 }
    // Clears the state when another game (a new world in the same run) ticks without a load.
    static func own(_ g: Game) {
        let id = ObjectIdentifier(g)
        if gameID != id { reset(); gameID = id }
    }

    static func save(_ d: inout [String: String]) {
        if stage > 0 { d["reckoning"] = "\(stage),\(wave),\(timer),\(inField ? 1 : 0)" }
    }
    static func load(_ d: [String: String], game: Game) {
        gameID = ObjectIdentifier(game)
        let p = (d["reckoning"] ?? "").split(separator: ",").map(String.init)
        stage = p.count > 0 ? max(0, min(2, Int(p[0]) ?? 0)) : 0
        wave = p.count > 1 ? max(0, min(waves.count - 1, Int(p[1]) ?? 0)) : 0
        timer = p.count > 2 ? Float(p[2]) ?? breather : 0
        inField = false; age = 0
        // A wave out when the world was saved is still out: its ground troops are saved mobs (sending it again would
        // double it). Its dropships are not saved, so it gets a grace while its chunks (and troops) load back in.
        if p.count > 3 && p[3] == "1" { inField = true; age = -rejoin }
    }

    static func members(_ g: Game) -> [Mob] { g.mobs.mobs.filter { $0.posse == posse && $0.health > 0 } }

    // Once a second (Game.ashTick's slot).
    static func tick(_ g: Game, _ dt: Float, sync: Bool = false) {
        own(g)
        guard g.ashVictory, stage < 2, g.survival, g.difficulty > 0 else { return }
        guard g.dim.dim == .overworld else { return }
        if !g.alive {
            if inField { sendHome(g); inField = false; timer = breather }
            return
        }
        if stage == 0 {
            stage = 1; wave = 0; timer = warning
            g.onToast?("Word of the Ashguard's fall has spread. Every army in the land is marching on you")
            g.sfx(.goatHorn, 0.7)
            return
        }
        if inField {
            age += dt
            let cur = waves[wave]
            for m in members(g) {
                m.aggro = true; m.lockTime = max(m.lockTime, 10)
                if simd_length(m.pos - g.player.pos) > 160 { m.health = 0 }     // ran off: counts as beaten
            }
            g.mobs.mobs.removeAll { $0.posse == posse && $0.health <= 0 && simd_length($0.pos - g.player.pos) > 160 }
            let troops = cur.dropships.contains { f in
                g.mobs.mobs.contains { $0.factionValue == f && $0.posse == 0 && $0.health > 0 && $0.aggro && simd_length($0.pos - g.player.pos) < 64 }
            }
            guard age >= 0, members(g).isEmpty, !troops, cur.dropships.isEmpty || age >= minWave else { return }
            inField = false
            if wave == waves.count - 1 {
                stage = 2
                g.money += reward
                g.onToast?("The last of them break and run. The surface is yours (+\(Money.format(reward)))")
                g.sfx(.goatHorn, 1)
                return
            }
            wave += 1; timer = breather
            g.onToast?("Wave \(wave) of \(waves.count) beaten. More are coming")
            return
        }
        timer -= dt
        if timer <= 0 { send(g, sync: sync) }
    }

    // Puts wave `wave` in the field: its ground troops out of sight 26-36 blocks off, its dropships from 180 out.
    @discardableResult
    static func send(_ g: Game, sync: Bool = false) -> Int {
        let w = g.world, cur = waves[wave]
        let scale: Float = [0, 0.75, 1, 1.35][max(0, min(3, g.difficulty))]
        var placed = 0
        for grp in cur.groups {
            let n = max(1, Int((Float(grp.n) * scale).rounded()))
            var got = 0
            for k in 0..<(n * 10) where got < n {
                let a = Rand.float(in: 0..<(2 * .pi)), r = Rand.float(in: 26...36)
                let x = Int(floor(g.player.pos.x + sinf(a) * r)), z = Int(floor(g.player.pos.z + cosf(a) * r))
                guard w.isLoaded(x, z) else { continue }
                let y = w.topY(x, z) + 1
                guard !Blocks.isLiquid(w.block(x, y - 1, z)), !Blocks.isLiquid(w.block(x, y, z)) else { continue }
                let at = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
                if k < n * 6 && w.canSee(at + V3(0, 1.6, 0), g.player.eye) { continue }
                let m = Mob(grp.kind, at: w.freeSpawn(at))
                if m.collides(m.pos, w) { continue }
                m.posse = posse
                m.persistent = true
                m.aggro = true; m.lockTime = 30
                if grp.faction != .none { m.faction = grp.faction.rawValue }
                if m.kind == .soldierIronclad { m.variant = Guns.arc }
                g.mobs.mobs.append(m)
                got += 1
            }
            placed += got
        }
        for (i, f) in cur.dropships.enumerated() where dropshipsOn {
            let a = Rand.float(in: 0..<(2 * .pi)) + Float(i) * 2
            let fx = g.player.pos.x + sinf(a) * 180, fz = g.player.pos.z + cosf(a) * 180
            let h = Float(max(w.gen.column(Int(fx), Int(fz)).height, SEA)) + 40
            g.world.ships.callDropship(faction: f, from: V3(fx, h, fz), to: g.player.pos, game: g, sync: sync)
        }
        // Nowhere to stand and nothing flying in (in water, or the ground not loaded): try again shortly.
        if placed == 0 && (cur.dropships.isEmpty || !dropshipsOn) { timer = retry; return 0 }
        inField = true; age = 0
        g.onToast?("\(cur.intro) (wave \(wave + 1) of \(waves.count))")
        g.sfx(.goatHorn, 0.8)
        return placed
    }

    // The player died: the wave's ground troops go home (they come again with the wave).
    static func sendHome(_ g: Game) {
        g.mobs.mobs.removeAll { $0.posse == posse }
    }
}
