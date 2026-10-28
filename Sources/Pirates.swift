import Foundation
import simd

// Corsairs, a sea faction (backlog T15, the P93 leftovers). Pirates who live on the water:
// - Crewed wrecks: a shipwreck run aground with its deck above the sea is often a corsair camp, three of them aboard
//   (OverworldStructures.shipwreckBuild, "@corsair" structure mobs).
// - Raids from the water: while a player is near the coast, now and then a Corsair Sloop (a small gunboat with a
//   cannon on her foredeck and three corsairs on deck) sails in from the open sea, closes on the shore near the player
//   and puts a party of three ashore; the sloop stands off and shells anyone in reach. Sink her (or take her helm once
//   her crew is dead) and the chest on her stern deck is yours.
// - The navy and every other armed faction count corsairs as foes (Faction.corsairs; CapitalShips.nearestFoe).
// At most one sloop at a time, none at peace (the Reckoning won), on peaceful or in creative.
enum Corsairs {
    static let sloopName = "Corsair Sloop"
    static let checkEvery: Double = 30
    static let cooldown: Double = 7200          // P231: two hours (was seven minutes)
    static let landReach: Float = 30            // the sloop puts her party ashore within this of her raid point
    static var nextCheck: Double = 0
    static var nextRaid: Double = 2400          // (not in a session's first 40 minutes)
    static var landed: Set<Int> = []
    static var raids = 0, parties = 0           // counters (harness)

    // A corsair: a soldier of the sea faction with a pirate's name.
    static func make(_ k: MobKind, at p: V3) -> Mob {
        let m = Mob(k, at: p)
        dress(m)
        return m
    }
    static func dress(_ m: Mob) {
        m.faction = Faction.corsairs.rawValue
        m.customName = "Corsair"
        // P256: corsairs carry frontier arms, never the Capital's (the Service Rifle and its rounds stay at Capital sites).
        if Soldier.rank(m.kind) != nil && m.kind != .deckGun {
            m.variant = m.kind == .soldierOfficer || m.kind == .soldierCrew ? Guns.revolver : (m.kind == .soldierMarksman ? Guns.kessel : Guns.sturmwind)
            if let b = m.brain { b.gun = m.variant; b.mag = Guns.all[m.variant].mag }
        }
    }

    // Bow -Z: 13 long, 5 wide; a closed hold under the deck, rails, a mast with a sail, the helm and screw aft, a
    // cannon on a turret ring forward and a chest on the stern deck.
    static func sloop() -> Blueprint {
        let b = Blueprint()
        let hull = "dark_oak_planks", rail = "dark_oak_fence"
        for z in -6...6 {
            let hw = z == -6 ? 0 : (z <= -4 ? 1 : 2)
            for x in -hw...hw {
                b.set(x, 0, z, hull)
                let wall = abs(x) == hw || abs(z) == 6
                if wall { b.set(x, 1, z, hull) }
                b.set(x, 2, z, hull)                                     // the deck
                if wall { b.set(x, 3, z, rail) }
            }
        }
        for y in 3...9 { b.set(0, y, -1, "spruce_log") }
        for y in 5...8 { for x in -2...2 where x != 0 { b.set(x, y, -1, "white_wool") } }
        b.set(0, 1, 4, "ship_engine")
        b.set(0, 3, 4, "ship_helm[south]")
        b.clear(0, 3, 6)
        b.set(0, 0, 7, "ship_propeller[south]")
        // D41: two guns a side for broadsides.
        for z in [0, 2] { b.set(2, 3, z, "ship_cannon[west]"); b.set(-2, 3, z, "ship_cannon[east]") }
        b.set(1, 3, 5, "chest")
        b.chests.append((IVec3(1, 3, 5), "shipwreck_treasure"))
        b.clear(0, 3, -5)
        b.set(0, 3, -3, "ship_turret_ring")
        let t = Blueprint()
        t.set(0, 0, 0, "ship_cannon[south]")
        for z in -2 ... -1 { t.set(0, 0, z, "gun_barrel_medium[south]") }        // (P477: a barrelled gun)
        b.turrets.append((IVec3(0, 3, -3), t))
        b.crew = [V3(-1.5, 3, 1.5), V3(1.5, 3, -0.5), V3(-0.5, 3, 3.5)]
        return b
    }

    // The sea in front of a raid: from the player out along a bearing, the last water column before the open sea
    // (the raid point, near the shore) and a spot far out where the sloop appears. Nil when the bearing doesn't
    // reach open water within 110 blocks or the shore is too far.
    static func approach(_ w: World, from p: V3, bearing a: Float) -> (shore: V3, sea: V3)? {
        let dir = V2(cosf(a), sinf(a))
        var shore: V3?
        var r: Float = 6
        while r <= 110 {
            let x = Int(floor(p.x + dir.x * r)), z = Int(floor(p.z + dir.y * r))
            guard w.isLoaded(x, z) else { return nil }
            if let s = Submarine.surface(w, x, z) {
                if shore == nil { shore = V3(Float(x) + 0.5, Float(s + 1), Float(z) + 0.5) }
                if r >= 90 {
                    guard let sh = shore, simd_length(V2(sh.x - p.x, sh.z - p.z)) < 60 else { return nil }
                    // The raid point stands a little off the shore, in water at least four deep.
                    var q = sh
                    for k in 1...30 {
                        let qx = Int(floor(sh.x + dir.x * Float(k))), qz = Int(floor(sh.z + dir.y * Float(k)))
                        if let qs = Submarine.surface(w, qx, qz) { q = V3(Float(qx) + 0.5, Float(qs + 1), Float(qz) + 0.5); if k >= 8 { break } }
                    }
                    return (q, V3(Float(x) + 0.5, Float(s + 1), Float(z) + 0.5))
                }
            } else if shore != nil && r > 20 {
                shore = nil                                              // an inland pond: keep looking past it
            }
            r += 2
        }
        return nil
    }
}

extension Game {
    // Every tick (CapitalBases.basesTick, beside the submarines).
    func corsairsTick(_ dt: Float) {
        guard dim.dim == .overworld else { return }
        var live = 0
        for s in world.ships.list where s.role == "sloop" && s.parent == nil {
            if s.captured || s.wrecked { continue }
            live += 1
            let d = simd_length(s.pos - player.pos)
            if d > 600 { world.ships.remove(s); continue }              // left behind: she sails off
            if !Corsairs.landed.contains(s.id), let home = s.home, simd_length(V2(home.x - s.pos.x, home.z - s.pos.z)) < Corsairs.landReach {
                Corsairs.landed.insert(s.id)
                corsairsLand(from: s)
            }
        }
        guard live == 0, clock >= Corsairs.nextCheck else { return }
        Corsairs.nextCheck = clock + Corsairs.checkEvery
        guard clock >= Corsairs.nextRaid, survival, difficulty > 0, alive, !Reckoning.won else { return }
        guard Rand.float(in: 0..<1) < 0.08, clock - FactionRaids.lastAssault > FactionRaids.quiet else { return }   // P231
        let p = player.pos
        let a0 = Rand.float(in: 0..<(2 * .pi))
        for k in 0..<12 {
            guard let (shore, sea) = Corsairs.approach(world, from: p, bearing: a0 + Float(k) * .pi / 6) else { continue }
            let toShore = V2(shore.x - sea.x, shore.z - sea.z)
            let yaw = atan2f(-toShore.x, -toShore.y)                     // bow (-Z) toward the shore
            let s = world.ships.spawnVessel("sloop", home: IVec3(Int(floor(sea.x)), Int(sea.y), Int(floor(sea.z))), game: self, yaw: yaw)
            s.home = shore
            Corsairs.raids += 1
            Corsairs.nextRaid = clock + Corsairs.cooldown
            FactionRaids.lastAssault = clock
            onToast?("A corsair sloop is closing on the shore: pirates are coming")
            sfx(.bell, 0.8, at: p)
            return
        }
    }

    // The landing party: three corsairs on the first dry ground between the sloop and the player.
    func corsairsLand(from s: Ship) {
        let p = player.pos
        let to = V2(p.x - s.pos.x, p.z - s.pos.z)
        let d = simd_length(to)
        guard d > 1 else { return }
        let dir = to / d
        var r: Float = 4
        while r < min(d, 60) {
            let x = Int(floor(s.pos.x + dir.x * r)), z = Int(floor(s.pos.z + dir.y * r))
            guard world.isLoaded(x, z) else { return }
            let top = world.topY(x, z)
            if !Blocks.isLiquid(world.rawBlock(x, top, z)) {
                for (i, k) in [MobKind.soldierTrooper, .soldierTrooper, .soldierMarksman].enumerated() {
                    let q = V3(Float(x) + 0.5 + Float(i - 1) * 1.2, Float(top + 1), Float(z) + 0.5 + dir.y * Float(i))
                    let m = Corsairs.make(k, at: q)
                    m.persistent = false
                    m.aggro = true
                    m.soldierBrain.ready = true
                    m.soldierBrain.lastSeen = p; m.soldierBrain.seenAgo = 0
                    m.lockTime = 30
                    mobs.mobs.append(m)
                }
                Corsairs.parties += 1
                if simd_length(V2(Float(x) - p.x, Float(z) - p.z)) < 120 { onToast?("Corsairs are coming ashore!") }
                sfx(.splash, 1, at: V3(Float(x), Float(top + 1), Float(z)))
                return
            }
            r += 2
        }
    }
}
