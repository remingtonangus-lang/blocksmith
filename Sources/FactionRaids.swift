import Foundation
import simd

// Faction raids (backlog O5). A faction you have angered (standing -45 or lower, FactionRep.swift) comes for what is
// yours: your home (the respawn point), a Greywall base you took, a camp you freed, or the town you are standing in.
//   when      every 10 minutes, while you are within 120 blocks of such a place in the overworld: a toast names the
//             faction and the place, and two of its dropships land 24-30 blocks out on dry ground (so a wall around the
//             place makes them walk to a gate), four raiders each
//   defences  walls, and wall turrets: a working or damaged wall turret you placed (mine one from a base you took) or
//             one on a base you hold fires three-round bursts at raiders and hostile soldiers within 40 blocks, in
//             front of it and in sight; your companions (O2) fight with you
//   the end   once a minute has passed and no raider is left within 64 blocks: "Raid beaten off" (+$20 salvage); if
//             you leave or die, it simply ends. Five minutes is the most a raid lasts.
// The next raid time is saved with the world extras ("factionRaids").
enum FactionRaids {
    static let angeredAt: Float = -45
    // P215 (Oct 13 18:53-19:01, "raiding parties and bounty hunters came round after round"): one dropship a raid,
    // forty minutes apart, and never within 25 minutes of any other assault (another faction's raid, a hunters'
    // dropship): `lastAssault` is shared with FactionRep's hunters.
    // P231 (Oct 13 21:46, "ultra rare: something you see after a long time and go wow"): one rarity pass over every
    // random encounter (faction raids, hunters, bounty posses, town raids, corsair sloops). Two hours between raids of
    // a faction, and 90 minutes of play with no other random encounter before any of them (`lastAssault`).
    static let every: Double = 7200
    static let quiet: Double = 5400
    static let rocketeerName = "Raid Rocketeer"
    static var lastAssault: Double = -1e9
    static let reach: Float = 120
    static let landAt: Float = 24
    static let maxTime: Double = 300
    static let salvage = 2000                       // cents
    static var next: Double = 0
    static var active: Raid?
    static var beaten = 0

    struct Raid {
        let faction: Faction
        let target: V3
        let place: String
        let started: Double
        var turrets: [IVec3] = []
        var scanAt: Double = 0
    }
    struct Gun { var cool: Float = 0, look: Float = 0, shots = 0, gap: Float = 0, foe: Mob? = nil }
    static var guns: [IVec3: Gun] = [:]

    // P236 (Oct 13 21:50): retaliation, once each. Killing corsairs at sea gives a one-in-two chance they raid your home
    // once; clearing or taking a base a one-in-eight chance its faction does. Each cause is rolled only the first time
    // (`settled`), and an owed raid comes 15-40 minutes later, the next time you are home.
    static var owed: [String: (faction: Int, due: Double)] = [:]
    static var settled: Set<String> = []
    static func owe(_ key: String, _ f: Faction, chance: Float, clock: Double) {
        guard !settled.contains(key) else { return }
        settled.insert(key)
        guard Rand.float(in: 0..<1) < chance else { return }
        owed[key] = (f.rawValue, clock + Double(Rand.float(in: 900..<2400)))
    }

    static func encode() -> String {
        let o = owed.map { "\($0.key),\($0.value.faction),\(Int($0.value.due))" }.joined(separator: ";")
        return "\(Int(max(0, next)))|\(o)|\(settled.joined(separator: ";"))"
    }
    static func decode(_ s: String) {
        let parts = s.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        next = Double(parts.first ?? "") ?? 0; active = nil; guns = [:]
        owed = [:]; settled = []
        if parts.count > 1 {
            for e in parts[1].split(separator: ";") {
                let f = e.split(separator: ",").map(String.init)
                guard f.count >= 3, let fr = Int(f[f.count - 2]), let due = Double(f[f.count - 1]) else { continue }
                owed[f[0..<(f.count - 2)].joined(separator: ","), default: (fr, due)] = (fr, due)
            }
        }
        if parts.count > 2 { settled = Set(parts[2].split(separator: ";").map(String.init)) }
    }

    static func angered() -> Faction? {
        FactionRep.tracked.filter { FactionRep.of($0) <= angeredAt }.min { FactionRep.of($0) < FactionRep.of($1) }
    }
}

extension Game {
    // The player's places a raid can fall on, nearest first: (centre, name).
    func raidPlaces() -> [(V3, String)] {
        var out: [(V3, String)] = [(spawnPoint, "your home")]
        for key in greywallAlarm.taken {
            let p = key.dropFirst("greywall:".count).split(separator: ",").compactMap { Int($0) }
            guard p.count == 2 else { continue }
            let y = world.isLoaded(p[0], p[1]) ? Float(world.topY(p[0], p[1])) : player.pos.y
            out.append((V3(Float(p[0]), y, Float(p[1])), "your base"))
        }
        for m in Liberation.freedCamps() {
            let y = world.isLoaded(m.x, m.z) ? Float(world.topY(m.x, m.z)) : player.pos.y
            out.append((V3(Float(m.x), y, Float(m.z)), "your camp"))
        }
        let px = Int(player.pos.x), pz = Int(player.pos.z)
        if let s = world.gen.structures?.nearest("village", x: px, z: pz, maxRegions: 1),
           simd_length(V2(Float(s.anchor.x - px), Float(s.anchor.z - pz))) < 100 {
            out.append((V3(Float(s.anchor.x), player.pos.y, Float(s.anchor.z)), Townsfolk.townName(s.anchor.x, s.anchor.z, seed: world.seed)))
        }
        let pp = player.pos
        return out.sorted { simd_length($0.0 - pp) < simd_length($1.0 - pp) }
    }

    // Once a second (the HUD tick).
    func factionRaidsTick() {
        guard survival, alive, dim.dim == .overworld else { FactionRaids.active = nil; return }
        if var r = FactionRaids.active {
            let near = mobs.mobs.contains { $0.health > 0 && !$0.hired && $0.factionValue == r.faction && Soldier.rank($0.kind) != nil && simd_length($0.pos - r.target) < 64 }
            let age = clock - r.started
            if simd_length(player.pos - r.target) > FactionRaids.reach * 1.5 || age > FactionRaids.maxTime {
                FactionRaids.active = nil
                return
            }
            if age > 60 && !near {
                FactionRaids.active = nil
                FactionRaids.beaten += 1
                money += FactionRaids.salvage
                onToast?("Raid beaten off! \(r.faction.name) left \(Money.format(FactionRaids.salvage)) of salvage behind.")
                return
            }
            if clock >= r.scanAt { r.turrets = raidTurrets(around: r.target); r.scanAt = clock + 20 }
            FactionRaids.active = r
            return
        }
        // P236: an owed retaliation falls on your home once you are there.
        if let (k, o) = FactionRaids.owed.first(where: { clock >= $0.value.due }), let f = Faction(rawValue: o.faction),
           simd_length(spawnPoint - player.pos) < FactionRaids.reach, world.ships.pilot == nil {
            FactionRaids.owed[k] = nil
            onToast?(f == .corsairs ? "The corsairs haven't forgotten the men you sank: they're coming for your home!"
                                    : "\(f.name) wants payback for its base: they're coming for your home!")
            startRaid(f, at: spawnPoint, place: "your home")
            return
        }
        if FactionRaids.next == 0 { FactionRaids.next = clock + FactionRaids.every; return }
        guard clock >= FactionRaids.next, clock - FactionRaids.lastAssault > FactionRaids.quiet, let f = FactionRaids.angered() else { return }
        guard let place = raidPlaces().first(where: { simd_length($0.0 - player.pos) < FactionRaids.reach }), world.ships.pilot == nil else { return }
        FactionRaids.next = clock + FactionRaids.every
        startRaid(f, at: place.0, place: place.1)
    }

    @discardableResult
    func startRaid(_ f: Faction, at c: V3, place: String, sync: Bool = false) -> Int {
        var landed = 0
        for k in 0..<8 where landed < 1 {
            let a = Float(k) * .pi / 4 + 0.4, d = FactionRaids.landAt + Float(k % 3) * 3
            let x = c.x + cosf(a) * d, z = c.z + sinf(a) * d
            let ix = Int(floor(x)), iz = Int(floor(z))
            guard world.isLoaded(ix, iz) else { continue }
            let y = world.topY(ix, iz)
            guard y > 0, !Blocks.isLiquid(world.block(ix, y, iz)) else { continue }
            let land = V3(x, Float(y + 1), z)
            let from = land + V3(cosf(a) * 240, 70, sinf(a) * 240)
            if world.ships.callDropship(faction: f, from: from, to: land, game: self, sync: sync, troops: 5, rocketeer: true) { landed += 1 }
        }
        guard landed > 0 else { return 0 }
        FactionRaids.lastAssault = clock
        FactionRaids.active = FactionRaids.Raid(faction: f, target: c, place: place, started: clock, turrets: raidTurrets(around: c), scanAt: clock + 20)
        onToast?("\(f.name) is raiding \(place)! Hold it.")
        sfx(.raidHorn, 1)
        return landed
    }

    // Wall turrets that fight for the player within 48 blocks of c: placed ones, and those of a base the player holds.
    func raidTurrets(around c: V3) -> [IVec3] {
        let gun = GreywallAlarmState.turretIds.0, hurt = GreywallAlarmState.turretIds.1
        let st = greywallAlarm
        var theirs = Set<IVec3>()
        for (key, site) in st.sites where !st.taken.contains(key) { theirs.formUnion(site.turrets) }
        var out: [IVec3] = []
        let cx = Int(floor(c.x)), cy = Int(floor(c.y)), cz = Int(floor(c.z))
        for z in (cz - 48)...(cz + 48) { for x in (cx - 48)...(cx + 48) where world.isLoaded(x, z) {
            for y in max(1, cy - 16)...min(CH - 2, cy + 24) {
                let b = world.block(x, y, z)
                guard (b >= gun && b < gun + 4) || (b >= hurt && b < hurt + 4) else { continue }
                let p = IVec3(x, y, z)
                if !theirs.contains(p) { out.append(p) }
            }
        } }
        return out
    }

    // Every frame (from basesTick): the player's wall turrets fire at raiders and hostile soldiers.
    func playerTurretsTick(_ dt: Float) {
        guard let r = FactionRaids.active, !r.turrets.isEmpty else { return }
        let gun = GreywallAlarmState.turretIds.0, hurt = GreywallAlarmState.turretIds.1
        let dirs = GreywallAlarmState.turretDirs
        for p in r.turrets {
            guard world.isLoaded(p.x, p.z) else { continue }
            let b = world.block(p.x, p.y, p.z)
            let damaged = b >= hurt && b < hurt + 4
            guard (b >= gun && b < gun + 4) || damaged else { FactionRaids.guns[p] = nil; continue }
            let f = Int(b - (damaged ? hurt : gun))
            let muzzle = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5) + dirs[f] * 0.6
            var gs = FactionRaids.guns[p] ?? FactionRaids.Gun()
            gs.cool = max(0, gs.cool - dt)
            gs.look -= dt
            if gs.look <= 0 {
                gs.look = 0.3
                gs.foe = nil
                var best = GreywallAlarmState.turretRange
                for m in mobs.mobs where m.health > 0 && !m.hired && Soldier.rank(m.kind) != nil && (m.aggro || m.factionValue == r.faction) {
                    let e = m.pos + V3(0, m.height * 0.6, 0)
                    let v = e - muzzle, dd = simd_length(v)
                    guard dd < best, simd_dot(v / max(dd, 0.01), dirs[f]) > -0.05, world.canSee(muzzle + dirs[f] * 0.5, e) else { continue }
                    best = dd; gs.foe = m
                }
            }
            if gs.shots > 0, let m = gs.foe, m.health > 0 {
                gs.gap -= dt
                if gs.gap <= 0 {
                    gs.gap = 0.12; gs.shots -= 1
                    let to = m.pos + V3(0, m.height * 0.6, 0) - muzzle
                    let dir = Guns.scatter(to / max(simd_length(to), 0.01), damaged ? 0.05 : 0.025)
                    arms.spawn(Slug(pos: muzzle + dir * 0.4, vel: dir * 140, kind: .bullet, damage: 4, fromPlayer: true,
                                    shooter: nil, by: "your wall turret", life: 0.6, gravity: 0))
                    addFlash(at: muzzle + dir * 0.5, color: V3(5, 3.5, 1.6), radius: 4, life: 0.06)
                    sfx(.gun(1), 0.9, at: muzzle)
                    if gs.shots == 0 { gs.cool = GreywallAlarmState.turretCool }
                }
            } else if gs.foe != nil && gs.cool <= 0 {
                gs.shots = GreywallAlarmState.turretBurst; gs.gap = 0.4
            } else {
                gs.shots = 0
            }
            FactionRaids.guns[p] = gs
        }
    }
}
