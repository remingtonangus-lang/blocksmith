import Foundation
import simd

// C1 trains (Railways.swift lays the lines):
//   Timetable  one steam train per line shuttles end to end, stopping `dwell` seconds at every station, on a
//              timetable of world time (Game.time), so it is wherever the clock says even while nobody watches.
//              Near the player (and loaded) it is three cars, a locomotive, a coach and an express car, moved along
//              the track every frame (minecart mobs, variant 10+, never saved: a reload rebuilds them).
//   Riding     use the coach to take a seat (sneak to get off); it carries you down the line.
//   Tickets    the TICKETS sign at a station sells a fare to every other station on the line: the journey passes
//              in a fade (the clock moves on by the trip) and you step off on that platform. Fast travel.
//   Robbery    hold up the driver (a gun on the locomotive, 20 blocks or nearer, for 1.5 s) or block the track ahead
//              and the train brakes to a stop; crack the express car's strongbox (use it five times, or once with
//              TNT in hand) for the line's takings. A crime: honour down, a bounty in the nearest town and a posse of
//              five rides out (outrun them, or pay up as for any bounty). The train runs again once you are 48 blocks
//              off or a minute has passed; that train carries no money for the rest of the day.
//   The Vault  armoured trains (an armoured locomotive and a gun car) shuttle the Ash Vault's four lines between the
//              citadel halt and each garrison town; the gun car's turret fires on you; explosives wreck it.
enum Trains {
    static let ticketWord = "TICKETS"
    static var speed: Float = 7                 // average blocks a second between stops
    static let dwell: Double = 24
    static let gap: Float = 3.6                 // between car centres
    static let carScale: Float = 2
    static let loco = 10, coach = 11, express = 12, armouredLoco = 13, gunCar = 14
    static let crackUses = 5
    static let robBounty = 8000, robHonour: Float = -15
    static let holdUpTime: Float = 1.5
    static let fareCentsPerBlock = 2           // a fare: 2 cents a block of track, at least $1

    static func isCar(_ m: Mob) -> Bool { m.kind == .minecart && m.variant >= loco }

    // A track a train runs: rail cells in order, the y of each cell's rail top, the stops (cell indices) and names.
    final class Track {
        let id: Int64
        let name: String
        let cells: [IVec3]
        let ys: [Float]
        let stops: [Int]
        let stopNames: [String]
        let armoured: Bool
        let dim: Dim
        // The timetable: (start, duration, from, to) over one period; from == to is a dwell.
        let legs: [(Double, Double, Float, Float)]
        let period: Double
        let phase: Double
        init(id: Int64, name: String, cells: [IVec3], slopes: [Bool], stops: [Int], stopNames: [String], armoured: Bool, dim: Dim) {
            self.id = id; self.name = name; self.cells = cells; self.stops = stops; self.stopNames = stopNames
            self.armoured = armoured; self.dim = dim
            ys = cells.indices.map { Float(cells[$0].y) + (slopes[$0] ? 0.5 : 0) + 0.0625 }
            var legs: [(Double, Double, Float, Float)] = [], t: Double = 0
            let order = stops + stops.reversed().dropFirst().dropLast()
            for k in 0..<order.count {
                let a = order[k], b = order[(k + 1) % order.count]
                legs.append((t, Trains.dwell, Float(a), Float(a))); t += Trains.dwell
                let d = Double(abs(b - a)) / Double(Trains.speed * (armoured ? 1.3 : 1))
                legs.append((t, d, Float(a), Float(b))); t += d
            }
            self.legs = legs
            period = max(1, t)
            phase = Double(hashf(Int(truncatingIfNeeded: id), Int(truncatingIfNeeded: id >> 32), 0x7A1, 0x5EED)) * max(1, t)
        }
        // Where the train's head is at timetable time t: its cell position, its heading (+1 up the cells, -1 down)
        // and the stop it stands at, if any.
        func at(_ t: Double) -> (s: Float, dir: Float, stop: Int?) {
            var u = (t + phase).truncatingRemainder(dividingBy: period)
            if u < 0 { u += period }
            var i = legs.firstIndex { u < $0.0 + $0.1 } ?? (legs.count - 1)
            let (t0, d, a, b) = legs[i]
            if a == b {
                // A dwell: heading for the next leg (the locomotive runs round at the terminus in the first second).
                i = (i + 1) % legs.count
                let n = legs[i]
                return (a, n.3 > n.2 ? 1 : -1, stops.firstIndex(of: Int(a)))
            }
            // Ease in and out of each stop (no speed at either end).
            let f = Float(max(0, min(1, (u - t0) / d)))
            let e = f - sinf(2 * .pi * f) / (2 * .pi)
            return (a + (b - a) * e, b > a ? 1 : -1, nil)
        }
        func point(_ s: Float) -> V3 {
            let n = cells.count
            let s = max(0, min(Float(n - 1), s))
            let i = min(n - 2, Int(s)), f = s - Float(i)
            let a = cells[i], b = cells[i + 1]
            let pa = V3(Float(a.x) + 0.5, ys[i], Float(a.z) + 0.5), pb = V3(Float(b.x) + 0.5, ys[i + 1], Float(b.z) + 0.5)
            return pa + (pb - pa) * f
        }
    }

    final class Train {
        let track: Track
        var delay: Double = 0                   // seconds the train has stood still off its timetable
        var brake: Float = 0                    // 0 running ... 1 stopped (a hold-up or a blocked track)
        var stoppedFor: Float = 0
        var holdUp: Float = 0
        var heldBy = false                      // the player stopped it (a hold-up or a block on the line)
        var cars: [Mob] = []
        var cracks = 0
        var robbedDay = -1
        var wrecked = false
        var gunCool: Float = 2
        var chuff: Float = 0
        var lastS: Float = 0
        init(_ t: Track) { track = t }
        var time: Double = 0                    // timetable time (Game.time less the delay), set each frame
    }
    static var trains: [Int64: Train] = [:]
    private static var carOf: [ObjectIdentifier: (Train, Int)] = [:]

    // MARK: Tracks

    static func track(_ l: Railways.Line) -> Track {
        let slopes = l.cells.indices.map { (2...5).contains(l.shape($0)) }
        return Track(id: l.id, name: l.name, cells: l.cells, slopes: slopes, stops: l.stations.map { $0.index },
                     stopNames: l.stations.map { $0.name + " Station" }, armoured: false, dim: .overworld)
    }
    private static var tracks: [Int64: Track] = [:]
    static func cachedTrack(_ l: Railways.Line) -> Track {
        if let t = tracks[l.id], t.cells.count == l.cells.count { return t }
        let t = track(l); tracks[l.id] = t
        if tracks.count > 64 { tracks.removeAll(); tracks[l.id] = t }
        return t
    }
    // The Ash Vault's four lines, citadel halt to town (AshVault.swift runs 0-3, flat at the vault floor).
    static let vaultTracks: [Track] = (0..<4).map { ri in
        let r = AshWar.railRuns[ri]
        let cells = (r.a...r.b).map { t -> IVec3 in let c = AshWar.cell(r, t); return IVec3(c.x, AshWar.ground + 1, c.z) }
        let hs = AshWar.halts.filter { $0.run == ri }
        let stops = hs.map { h in h.from + h.dir * (AshWar.haltLength / 2) - r.a }.map { max(4, min(cells.count - 5, $0)) }.sorted()
        let names = stops.map { s in hs.min { abs($0.from + $0.dir * (AshWar.haltLength / 2) - r.a - s) < abs($1.from + $1.dir * (AshWar.haltLength / 2) - r.a - s) }!.name }
        return Track(id: Int64(-1 - ri), name: "Ashguard Rail", cells: cells, slopes: cells.map { _ in false }, stops: stops,
                     stopNames: names, armoured: true, dim: .deep)
    }

    // Tracks within `r` blocks of p in this dimension.
    static func tracksNear(_ g: Game, _ p: V3, _ r: Int) -> [Track] {
        switch g.dim.dim {
        case .overworld:
            guard let gen = g.world.gen as? WorldGen else { return [] }
            let x = Int(floor(p.x)), z = Int(floor(p.z))
            return Railways.near(gen, x0: x - r, z0: z - r, x1: x + r, z1: z + r, pad: r).map { cachedTrack($0) }
        case .deep:
            guard DeepGen.inVault(p.y) else { return [] }
            return vaultTracks.filter { t in
                let a = t.cells.first!, b = t.cells.last!
                return p.x > Float(min(a.x, b.x) - r) && p.x < Float(max(a.x, b.x) + r) && p.z > Float(min(a.z, b.z) - r) && p.z < Float(max(a.z, b.z) + r)
            }
        default: return []
        }
    }

    // MARK: Ticking

    // Once a second: trains near the player are built as cars, far ones taken away; strays (a reload) go too.
    static func tick(_ g: Game) {
        let p = g.player.pos
        var want: Set<Int64> = []
        for t in tracksNear(g, p, 140) {
            let tr = trains[t.id] ?? Train(t)
            trains[t.id] = tr
            if tr.wrecked { continue }
            tr.time = g.time - tr.delay
            let head = t.point(t.at(tr.time).s)
            guard simd_length(head - p) < 128 else { continue }
            // Only where the track was laid (ground a save had generated before keeps no rails).
            let c0 = t.cells[max(0, min(t.cells.count - 1, Int(t.at(tr.time).s)))]
            guard g.world.isLoaded(c0.x, c0.z), Rails.isRail(g.world.block(c0.x, c0.y, c0.z)) else { continue }
            want.insert(t.id)
            if tr.cars.isEmpty || tr.cars.contains(where: { $0.health <= 0 && !t.armoured }) || !tr.cars.allSatisfy({ m in g.mobs.mobs.contains { $0 === m } }) {
                build(g, tr)
            }
        }
        for (id, tr) in trains where !want.contains(id) && !tr.cars.isEmpty { remove(g, tr) }
        // Cars not in a train (a save's leftovers) go.
        g.mobs.mobs.removeAll { isCar($0) && carOf[ObjectIdentifier($0)] == nil }
        // A held train with the player gone, or a minute on, runs again.
        for tr in trains.values where tr.heldBy {
            tr.stoppedFor += 1
            let far = tr.cars.first.map { simd_length($0.pos - p) > 48 } ?? true
            if far || tr.stoppedFor > 60 { tr.heldBy = false; tr.brake = 0; tr.stoppedFor = 0; tr.holdUp = 0 }
        }
        if trains.count > 48 { for (id, tr) in trains where tr.cars.isEmpty && !want.contains(id) { trains[id] = nil } }
    }

    static func build(_ g: Game, _ tr: Train) {
        remove(g, tr)
        let kinds = tr.track.armoured ? [armouredLoco, gunCar] : [loco, coach, express]
        for (k, v) in kinds.enumerated() {
            let m = Mob(.minecart, at: tr.track.point(0))
            m.variant = v
            m.scale = carScale
            m.persistent = false
            m.customName = tr.track.armoured ? (v == gunCar ? "Ashguard Gun Car" : "Ashguard Armoured Train")
                                             : ["\(tr.track.name) Locomotive", "\(tr.track.name) Coach", "\(tr.track.name) Express Car"][k]
            if tr.track.armoured { m.health = v == gunCar ? 160 : 240 }
            carOf[ObjectIdentifier(m)] = (tr, k)
            tr.cars.append(m)
            g.mobs.mobs.append(m)
        }
        place(g, tr, dt: 0)
    }

    static func remove(_ g: Game, _ tr: Train) {
        if let r = g.riding, tr.cars.contains(where: { $0 === r }) { g.dismount() }
        for m in tr.cars { carOf[ObjectIdentifier(m)] = nil }
        let gone = Set(tr.cars.map { ObjectIdentifier($0) })
        g.mobs.mobs.removeAll { gone.contains(ObjectIdentifier($0)) }
        tr.cars = []
    }

    // Mob.update for a car: the train's head car moves the whole train; every car keeps its pose.
    static func drive(_ m: Mob, _ dt: Float, _ g: Game) {
        guard let (tr, k) = carOf[ObjectIdentifier(m)] else { m.health = -1; return }
        if !tr.track.armoured { m.health = m.spec.health; m.hurt = 0 }
        if k == 0 { place(g, tr, dt: dt) }
        if g.riding === m {
            g.player.pos = m.pos + V3(0, 1.0, 0)
            g.player.vel = .zero
            g.player.airPeak = g.player.pos.y
        }
    }

    static func place(_ g: Game, _ tr: Train, dt: Float) {
        let t = tr.track
        // Blocked line: a solid block on the rail just ahead of the locomotive stops the train (the player's doing).
        if dt > 0, let lead = tr.cars.first {
            let ahead = lead.pos + lead.forward * (gap * 0.75 + 1.2)
            let c = IVec3(Int(floor(ahead.x)), Int(floor(ahead.y + 0.3)), Int(floor(ahead.z)))
            let b = g.world.block(c.x, c.y, c.z)
            if Blocks.collide[Int(b)] && !Rails.isRail(b) && t.at(tr.time).stop == nil && !t.armoured {
                if !tr.heldBy { tr.heldBy = true; tr.stoppedFor = 0; whistle(g, tr) }
            }
            holdUpTick(g, tr, dt)
        }
        tr.brake += ((tr.heldBy ? 1 : 0) - tr.brake) * min(1, dt * 1.2)
        tr.delay += Double(dt * tr.brake)
        tr.time = g.time - tr.delay
        let (s, dir, stop) = t.at(tr.time)
        let moving = abs(s - tr.lastS)
        tr.lastS = s
        for (k, m) in tr.cars.enumerated() {
            let sk = s - dir * gap * Float(k)
            let p = t.point(sk)
            let d = t.point(sk + dir * 0.7) - t.point(sk - dir * 0.7)
            m.pos = p
            m.vel = dt > 0 ? d * (moving / max(dt, 1e-4) / 1.4) : .zero
            if simd_length(V2(d.x, d.z)) > 0.01 { m.yaw = atan2f(-d.x, -d.z) }
            m.walkPhase += moving * 1.6
            m.onGround = true
        }
        // Steam: chuffs with speed, a whistle leaving each stop.
        guard dt > 0, let lead = tr.cars.first, simd_length(lead.pos - g.player.pos) < 96 else { return }
        let sp = moving / max(dt, 1e-4)
        tr.chuff -= dt * (0.6 + sp * 0.5)
        if tr.chuff <= 0 {
            tr.chuff = 1
            let top = lead.pos + V3(0, 3.6, 0) + lead.forward * 1.4
            if !tr.track.armoured { g.particles.smoke(at: top, dark: true); g.particles.smoke(at: top + V3(0, 0.4, 0), dark: false) }
            if sp > 0.3 || stop != nil { g.sfx(.steamChuff, tr.track.armoured ? 0.5 : 0.7, at: top) }
        }
        if let st = stop, t.at(tr.time + 2).stop == nil, t.at(tr.time - Double(dt)).stop == st, tr.brake < 0.1 { whistle(g, tr) }
        if t.armoured { gunCar(g, tr, dt) }
    }

    static func whistle(_ g: Game, _ tr: Train) {
        guard let lead = tr.cars.first else { return }
        g.sfx(.trainWhistle, tr.track.armoured ? 0.7 : 1, at: lead.pos + V3(0, 3, 0))
    }

    // MARK: Hold-ups and robbery

    static func holdUpTick(_ g: Game, _ tr: Train, _ dt: Float) {
        guard !tr.track.armoured, !tr.heldBy, let lead = tr.cars.first, g.alive, g.survival, Guns.index(g.held.item) != nil else { tr.holdUp = 0; return }
        let from = g.vrAim?.origin ?? g.player.eye, dir = simd_normalize(g.vrAim?.dir ?? g.player.look)
        let cab = lead.pos + V3(0, 2.2, 0) - lead.forward * 0.9
        let to = cab - from, d = simd_length(to)
        guard d > 1, d < 20, simd_dot(to / d, dir) > 0.985, g.world.canSee(from, cab) else { tr.holdUp = max(0, tr.holdUp - dt); return }
        tr.holdUp += dt
        if tr.holdUp >= holdUpTime {
            tr.heldBy = true; tr.stoppedFor = 0
            whistle(g, tr)
            g.onToast?("The driver throws on the brakes")
        }
    }

    // Use a car: the coach seats you; the express car's strongbox cracks (a held-up train only).
    static func use(_ g: Game, _ m: Mob) -> Bool {
        guard isCar(m), let (tr, k) = carOf[ObjectIdentifier(m)] else { return false }
        _ = k
        switch m.variant {
        case coach, loco:
            if g.riding === m { return false }
            if g.riding != nil { g.dismount() }
            g.riding = m
            g.player.pos = m.pos + V3(0, 1.0, 0)
            g.sfx(.armorEquip(0), 0.5, at: m.pos)
            g.onToast?("Riding the \(tr.track.name). Sneak to get off")
            return true
        case express:
            return crack(g, tr, m)
        default:
            return false
        }
    }

    static func crack(_ g: Game, _ tr: Train, _ m: Mob) -> Bool {
        let day = Int(g.time / DAY_LENGTH)
        guard tr.brake > 0.8 else { g.onToast?("The express car's strongbox: stop the train first"); return true }
        guard tr.robbedDay != day else { g.onToast?("The strongbox is empty"); return true }
        let tnt = Items.key(g.held.item) == "tnt"
        if tnt {
            tr.cracks = crackUses
            if g.survival { g.consumeHeld() }
            Explosion.explode(at: m.pos + V3(0, 1, 0) + m.forward * 0.6, power: 1.2, game: g, except: m)
        } else {
            tr.cracks += 1
            g.sfx(.anvil, 0.6, at: m.pos)
            g.swing = 1
        }
        if tr.cracks < crackUses { g.onToast?("Cracking the strongbox (\(tr.cracks) of \(crackUses))"); return true }
        // Open: the line's takings.
        tr.cracks = 0
        tr.robbedDay = day
        let cash = Rand.int(in: 40...120) * 100
        g.money += cash
        for (k, lo, hi) in [("gold_ingot", 2, 5), ("gold_nugget", 4, 12), ("emerald", 1, 3), ("paper", 1, 4)] where Items.has(k) {
            let n = Rand.int(in: lo...hi)
            if n > 0 { g.drops.spawn(ItemStack(Items.id(k), n), at: m.pos + V3(0, 1, 0)) }
        }
        g.onToast?("The strongbox gives up \(Money.format(cash))")
        Trains.robbed += 1
        if g.survival {
            let town = Townsfolk.town(g, at: m.pos)
            Honour.change(g, robHonour, "robbed the \(tr.track.name)")
            Honour.addBounty(g, town, robBounty)
            _ = Riders.sendPosse(g, from: town)
            _ = Riders.sendPosse(g, from: town)
        }
        return true
    }
    static var robbed = 0

    // MARK: The armoured gun car

    static func gunCar(_ g: Game, _ tr: Train, _ dt: Float) {
        guard tr.cars.count > 1 else { return }
        // Wrecked: both cars down (explosives and heavy rounds).
        if tr.cars.allSatisfy({ $0.health <= 0 }) || tr.cars[0].health <= 0 {
            for c in tr.cars { Explosion.explode(at: c.pos + V3(0, 1, 0), power: 2.5, game: g, except: c) }
            tr.wrecked = true
            g.onToast?("The armoured train is wrecked")
            remove(g, tr)
            return
        }
        let gun = tr.cars[1]
        guard gun.health > 0, g.alive, g.survival, !g.ashVictory else { return }
        let muzzle = gun.pos + V3(0, 2.6, 0)
        let to = g.player.eye - muzzle, d = simd_length(to)
        tr.gunCool -= dt
        // The turret turns to the player (yaw kept in the gun car's jobTimer for the model).
        let want = atan2f(-to.x, -to.z) - gun.yaw
        gun.jobTimer += (atan2f(sinf(want - gun.jobTimer), cosf(want - gun.jobTimer))) * min(1, dt * 2)
        guard d < 48, tr.gunCool <= 0, g.world.canSee(muzzle, g.player.eye) else { return }
        tr.gunCool = Float([1.6, 1.2, 0.9, 0.7][max(0, min(3, g.difficulty))])
        for k in 0..<3 {
            let dir = Guns.scatter(simd_normalize(to), 0.03)
            let dmg: Float = 1.5 * Soldier.difficultyScale(g.difficulty) + 0.5
            g.arms.spawn(Slug(pos: muzzle + dir * 1.2, vel: dir * 140, kind: .bullet, damage: dmg, fromPlayer: false, shooter: ObjectIdentifier(gun),
                              by: "an Ashguard Gun Car", life: 0.6 + Float(k) * 0.02, gravity: 1.5))
        }
        g.addFlash(at: muzzle + simd_normalize(to) * 1.2, color: V3(6, 3.5, 1.6), radius: 5, life: 0.06)
        g.sfx(.gun(1), 1, at: muzzle)
    }

    // MARK: Tickets

    static func isTicketSign(_ be: BlockEntity) -> Bool { be.kind == .sign && be.lines.first == ticketWord }

    static func openTickets(_ g: Game, at p: IVec3) -> Bool {
        guard let gen = g.world.gen as? WorldGen,
              let (l, st) = Railways.station(gen, near: V3(Float(p.x), Float(p.y), Float(p.z)), within: 20) else { return false }
        g.openMenu(TicketMenu(game: g, line: l, from: st))
        return true
    }

    static func fare(_ a: Railways.Station, _ b: Railways.Station) -> Int { max(100, abs(a.index - b.index) * fareCentsPerBlock) }

    // Travel: the trip's time passes, you step off on the platform at `to` (the town side of the track).
    static func travel(_ g: Game, line l: Railways.Line, from a: Railways.Station, to b: Railways.Station) -> (String, Bool) {
        let cost = fare(a, b)
        guard g.money >= cost || !g.survival else { return ("You need \(Money.format(cost)) for that fare.", false) }
        if g.survival { g.money -= cost }
        if g.riding != nil { g.dismount() }
        let c = l.cells[b.index]
        let trip = Double(abs(b.index - a.index)) / Double(speed * 1.6)
        g.time += trip
        g.player.pos = V3(Float(c.x) + 0.5, Float(c.y), Float(c.z - 2) + 0.5)
        g.player.vel = .zero
        g.player.airPeak = g.player.pos.y
        g.sfx(.trainWhistle, 0.8)
        g.closeMenu()
        Trains.journeys += 1
        g.onToast?("You arrive at \(b.name) Station")
        return ("", true)
    }
    static var journeys = 0

    // The network (P132): found stations on other lines, nearest first (twelve at most).
    static func networkStops(_ g: Game, line l: Railways.Line, from a: Railways.Station) -> [MapCache.Mark] {
        let own = Set(l.stations.map { "\($0.x),\($0.z)" })
        let marks = MapCache.shared.marks.filter { m in m.kind == "station" && !own.contains("\(m.x),\(m.z)")
            && !l.stations.contains(where: { s in abs(s.x - m.x) < 24 && abs(s.z - m.z) < 24 }) }
        return Array(marks.sorted { crowFlies(a, $0) < crowFlies(a, $1) }.prefix(12))
    }
    static func crowFlies(_ a: Railways.Station, _ m: MapCache.Mark) -> Int {
        let dx = Float(m.x - a.x), dz = Float(m.z - a.z)
        return Int((dx * dx + dz * dz).squareRoot())
    }
    static let changeFare = 300
    static func networkFare(_ blocks: Int) -> Int { max(100, blocks * fareCentsPerBlock * 5 / 4) + changeFare }

    static func travelNetwork(_ g: Game, from a: Railways.Station, to m: MapCache.Mark) -> (String, Bool) {
        guard let gen = g.world.gen as? WorldGen,
              let (l, b) = Railways.station(gen, near: V3(Float(m.x), 64, Float(m.z)), within: 24) else {
            return ("That line isn't running.", false)
        }
        let d = crowFlies(a, m), cost = networkFare(d)
        guard g.money >= cost || !g.survival else { return ("You need \(Money.format(cost)) for that fare.", false) }
        if g.survival { g.money -= cost }
        if g.riding != nil { g.dismount() }
        let c = l.cells[b.index]
        g.time += Double(d) * 1.3 / Double(speed * 1.6)            // the trip, with the wait for the connection
        g.player.pos = V3(Float(c.x) + 0.5, Float(c.y), Float(c.z - 2) + 0.5)
        g.player.vel = .zero
        g.player.airPeak = g.player.pos.y
        g.sfx(.trainWhistle, 0.8)
        g.closeMenu()
        Trains.journeys += 1
        g.onToast?("You change trains and arrive at \(b.name) Station")
        return ("", true)
    }

    // Finding a station puts the whole line on the map (once a second).
    static func discover(_ g: Game) {
        guard g.dim.dim == .overworld, let gen = g.world.gen as? WorldGen, let (l, _) = Railways.station(gen, near: g.player.pos, within: 40) else { return }
        guard !MapCache.shared.marked(kind: "station", x: l.stations[0].x, z: l.stations[0].z) else { return }
        for s in l.stations { MapCache.shared.discover(g, kind: "station", x: s.x, z: s.z, name: "\(s.name) Station") }
        g.onToast?("You found the \(l.name): \(l.stations.count) stations, marked on your map")
    }

    // MARK: Models (units 1/16 at scale 2: one unit is an eighth of a block; the car faces -Z)

    static func parts(_ m: Mob) -> [Part] {
        let iron = V3(0.16, 0.16, 0.17), brass = V3(0.85, 0.66, 0.3), red = V3(0.55, 0.12, 0.1)
        var p: [Part] = []
        func wheels(_ zs: [Float], _ c: V3) {
            let spin = m.walkPhase
            for z in zs { for x: Float in [-6.6, 5.6] {
                p.append(Part(mn: V3(x, 0, z - 2), mx: V3(x + 1, 4, z + 2), pivot: V3(x, 2, z), rotX: spin, color: c, pattern: 8))
            } }
        }
        switch m.variant {
        case loco:
            let body = V3(0.12, 0.13, 0.14), cab = V3(0.42, 0.1, 0.09)
            p.append(box(-6, 2, -13, 12, 2, 26, iron, 8))                         // the frame
            p.append(box(-6.1, 2.5, -13, 12.2, 1, 26, red, 7))                    // its red stripe
            wheels([-8, -2.5, 3, 9], red)
            p.append(box(-4.5, 4, -13, 9, 8, 15, body, 7))                        // the boiler
            p.append(box(-4, 4.5, -14, 8, 7, 1, V3(0.22, 0.22, 0.23), 8))        // the smokebox door
            p.append(box(-1, 9, -14.6, 2, 2, 0.8, V3(1, 0.95, 0.7), 9))           // the headlamp
            p.append(box(-1.5, 12, -11, 3, 5, 3, body, 7))                        // the chimney
            p.append(box(-2.1, 16.5, -11.6, 4.2, 1.2, 4.2, body, 7))
            p.append(box(-2, 12, -5, 4, 2.5, 4, brass, 8))                         // the steam dome
            p.append(box(-1.2, 12, -1.5, 2.4, 1.6, 2, brass, 8))                   // the whistle
            for z: Float in [-12, -7, -2] { p.append(box(-4.7, 4, z, 9.4, 8.2, 0.6, brass, 8)) }    // boiler bands
            p.append(box(-6, 4, 2, 12, 12, 9, cab, 7))                             // the cab
            p.append(box(-6.1, 10, 3.5, 0.3, 4, 6, V3(0.05, 0.05, 0.06), 11))      // cab windows
            p.append(box(5.8, 10, 3.5, 0.3, 4, 6, V3(0.05, 0.05, 0.06), 11))
            p.append(box(-6.6, 16, 1.4, 13.2, 1, 10.2, body, 7))                  // its roof
            p.append(box(-5, 0.6, -15.6, 10, 2.6, 2, red, 7))                     // the cowcatcher
            p.append(box(-5.4, 4, 11, 10.8, 1, 2, iron, 8))                         // the drawbar
            // Connecting rods on the drivers (they run with the wheels).
            let r = sinf(m.walkPhase) * 1.2, q = cosf(m.walkPhase) * 1.2
            p.append(box(-7.2, 1.6 + q, -8 + r, 0.5, 0.8, 11.5, V3(0.75, 0.75, 0.78), 8))
            p.append(box(6.7, 1.6 + q, -8 + r, 0.5, 0.8, 11.5, V3(0.75, 0.75, 0.78), 8))
        case coach, express:
            let side = m.variant == coach ? V3(0.2, 0.33, 0.22) : V3(0.16, 0.2, 0.36)
            let trim = m.variant == coach ? V3(0.85, 0.72, 0.42) : V3(0.9, 0.78, 0.35)
            p.append(box(-6, 2, -13, 12, 2, 26, iron, 8))
            wheels([-9, -5, 5, 9], iron)
            p.append(box(-6, 4, -13, 12, 11, 26, side, 7))                        // the body
            p.append(box(-6.1, 6, -13, 12.2, 0.6, 26, trim, 8))                   // a lined stripe
            p.append(box(-6.6, 15, -13.5, 13.2, 1.4, 27, V3(0.2, 0.18, 0.17), 7))  // the roof
            p.append(box(-1.5, 16.4, -13, 3, 0.8, 26, V3(0.24, 0.22, 0.2), 7))
            if m.variant == coach {
                for z: Float in stride(from: -11, through: 9, by: 4) {           // windows, lit warm
                    p.append(box(-6.15, 9, z, 0.3, 4, 2.6, V3(0.95, 0.82, 0.5), 9))
                    p.append(box(5.85, 9, z, 0.3, 4, 2.6, V3(0.95, 0.82, 0.5), 9))
                }
            } else {
                // The express car: barred little windows and a heavy sliding door on each side, the strongbox inside.
                for z: Float in [-10, 8] {
                    p.append(box(-6.15, 11, z, 0.3, 2, 2, V3(0.05, 0.05, 0.06), 11))
                    p.append(box(5.85, 11, z, 0.3, 2, 2, V3(0.05, 0.05, 0.06), 11))
                }
                p.append(box(-6.3, 4.5, -4, 0.5, 10, 8, V3(0.12, 0.14, 0.24), 7))
                p.append(box(5.8, 4.5, -4, 0.5, 10, 8, V3(0.12, 0.14, 0.24), 7))
                p.append(box(-6.4, 12, -1.5, 0.3, 1.2, 3, trim, 8))                 // a brass plate
                p.append(box(6.1, 12, -1.5, 0.3, 1.2, 3, trim, 8))
            }
            for e: Float in [-13.5, 12.5] { p.append(box(-4, 4, e, 8, 9, 1, V3(0.1, 0.09, 0.08), 7)) }   // end platforms
        case armouredLoco:
            let plate = V3(0.24, 0.25, 0.22), dark = V3(0.13, 0.13, 0.12)
            p.append(box(-6.4, 1, -14, 12.8, 3, 28, dark, 8))
            wheels([-9, -3, 3, 9], dark)
            p.append(box(-6, 4, -13, 12, 9, 26, plate, 8))                         // the armoured box
            p.append(box(-5, 13, -11, 10, 3, 18, plate, 8))                        // its upper casemate
            p.append(box(-6.6, 1, -15.4, 13.2, 6, 1.6, dark, 8))                   // the ram plate
            p.append(box(-4.5, 13.2, -11.2, 9, 0.6, 0.4, V3(0.05, 0.05, 0.05), 11))  // the vision slit
            p.append(box(-1.4, 16, 3, 2.8, 3, 2.8, dark, 8))                        // the exhaust
            p.append(box(-6.2, 8, -13, 12.4, 0.6, 26, V3(0.5, 0.12, 0.08), 7))   // the Ashguard red band
        case gunCar:
            let plate = V3(0.24, 0.25, 0.22), dark = V3(0.13, 0.13, 0.12)
            p.append(box(-6.4, 1, -14, 12.8, 3, 28, dark, 8))
            wheels([-9, -3, 3, 9], dark)
            p.append(box(-6, 4, -13, 12, 7, 26, plate, 8))
            p.append(box(-6.2, 8, -13, 12.4, 0.6, 26, V3(0.5, 0.12, 0.08), 7))
            // The turret turns to its target (Mob.jobTimer holds its yaw relative to the car).
            let ty = m.jobTimer
            p.append(Part(mn: V3(-4.5, 11, -4.5), mx: V3(4.5, 16, 4.5), pivot: V3(0, 11, 0), color: plate, pattern: 8, rotY: ty))
            p.append(Part(mn: V3(-0.8, 13, -14), mx: V3(0.8, 14.6, -4), pivot: V3(0, 11, 0), color: dark, pattern: 8, rotY: ty))
            p.append(Part(mn: V3(-2.2, 12.6, -5.2), mx: V3(2.2, 15, -4.2), pivot: V3(0, 11, 0), color: dark, pattern: 8, rotY: ty))
        default: break
        }
        return p
    }
}

// The station's ticket board: a fare to every other station on the line.
final class TicketMenu: ListMenu {
    let line: Railways.Line
    let from: Railways.Station
    // P132: the network. Stations you have found on other lines (the map's station marks) are sold too, priced by the
    // distance as the crow flies plus a change of trains; the trip runs to the far line's station.
    let network: [MapCache.Mark]
    init(game g: Game, line l: Railways.Line, from st: Railways.Station) {
        line = l; from = st
        network = Trains.networkStops(g, line: l, from: st)
        super.init(l.name, game: g)
        subtitle = "\(st.name) Station: tickets"
        say(network.isEmpty ? "Pick a station. The trip passes on the train."
                            : "Pick a station. Stations on other lines you have found are sold too, with a change.", good: true)
    }
    var others: [Railways.Station] { line.stations.filter { $0.index != from.index } }
    override var rows: [Row] {
        corner = "Wallet " + Money.format(game.money)
        let icon = Items.has("rail") ? ItemStack(Items.id("rail"), 1) : .empty
        let own = others.map { s -> Row in
            let f = Trains.fare(from, s)
            let km = abs(s.index - from.index)
            return Row(icon: icon, name: "\(s.name) Station",
                       detail: "\(km) blocks of track", value: Money.format(f), enabled: !game.survival || game.money >= f)
        }
        let far = network.map { m -> Row in
            let d = Trains.crowFlies(from, m), f = Trains.networkFare(d)
            return Row(icon: icon, name: m.name ?? "Station", detail: "\(d) blocks away, change trains", value: Money.format(f),
                       enabled: !game.survival || game.money >= f)
        }
        return own + far
    }
    override func pressed(_ i: Int) {
        let o = others
        if i < o.count {
            let r = Trains.travel(game, line: line, from: from, to: o[i])
            if !r.1 { say(r.0, good: false) }
            return
        }
        let j = i - o.count
        guard j < network.count else { return }
        let r = Trains.travelNetwork(game, from: from, to: network[j])
        if !r.1 { say(r.0, good: false) }
    }
}
