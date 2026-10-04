import Foundation
import simd

// Reactive Capital citadels (Future ideas #2). A citadel hears gunfire, cannon and explosions within a sensible
// range (a noise bus fed by guns, explosions and turrets: Game.baseNoise), raises its alert state and acts:
//   suspicious / alert  a patrol (an officer and three soldiers, mustered at the gate) marches to the noise at low
//                       ready, searches the area, then returns to its posts; a loud blast far off brings out a
//                       second, larger patrol
//   lockdown            the citadel itself was attacked (shots or blasts inside its walls): the alarm sounds, the
//                       garrison turns on the source, crews run to the turrets (gunner stance at the barbettes),
//                       and Capital dropships fly in and land reinforcements in the plaza
//   air patrol          on alert or lockdown a crewed Kestrel helicopter lifts off the tower's landing pad, flies
//                       out and circles the noise (or the citadel), then lands back on the pad (CapitalAir.swift)
//   rebuild             once things are calm, blast damage inside the walls is rebuilt block by block by pilots
//                       working at the site: the original blocks come from regenerating the citadel's chunks (a
//                       worker thread), and only cells that are now air, liquid or fire are restored, so wrecks,
//                       debris and anything else left in the craters stay where they are
// Alert states, patrol targets and pending damage are saved in world.json ("bases"); the work itself only runs
// for citadels in loaded chunks, once a second (BaseWatch.tickMs is measured: --basetest prints it).

enum NoiseKind: Int { case gunshot = 0, explosion, cannon }

enum BaseAlert: Int, Codable {
    case calm = 0, suspicious, alert, lockdown
    var name: String { ["calm", "suspicious", "alert", "lockdown"][rawValue] }
}

struct BaseNoise {
    var pos: V3
    var kind: NoiseKind
    var power: Float
    var hostile: Bool
}

struct PatrolRecord: Codable {
    var target: [Float]
    var phase: Int            // 0 muster at the gate, 1 out, 2 search, 3 back
    var t: Float
    var size: Int = 4
}

// Saved per citadel.
struct BaseRecord: Codable {
    var key: String
    var cx: Int, cz: Int, y0: Int          // site centre and the plaza level's base (plaza floor = y0 + 4)
    var alert: BaseAlert = .calm
    var calm: Float = 0                    // seconds since the last hostile noise
    var lastNoise: [Float]? = nil
    var patrol: PatrolRecord? = nil
    var damage: [[Float]] = []             // blast spheres to rebuild: x, y, z, radius
    var rebuilt: Int = 0
    var dropshipCD: Float = 0
    var dropships: Int = 0
    var lastTick: Double = 0
    var crawlerGoal: [Float]? = nil         // a crawler patrol out to a distant blast or cannon fire
    var crawlerPhase: Int = 0               // 0 to call, 1 out, 2 holding there, 3 back
    var crawlerT: Float = 0
    var air: [Float]? = nil                 // the Kestrel's goal while it is up (CapitalAir.swift)
    var airPhase: Int? = nil
    var airT: Float? = nil
    var airShip: Int? = nil
    var airCD: Float? = nil

    var centre: V3 { V3(Float(cx) + 0.5, Float(y0 + 4), Float(cz) + 0.5) }
    var gate: V3 { V3(Float(cx) + 0.5, Float(y0 + 1), Float(cz + 52) + 0.5) }
    var plaza: V3 { V3(Float(cx) + 0.5, Float(y0 + 5), Float(cz + 30) + 0.5) }
    var motorPool: V3 { V3(Float(cx) + 0.5, Float(y0), Float(cz + 92) + 0.5) }      // where the crawler comes and goes
    func inside(_ p: V3) -> Bool {
        abs(p.x - Float(cx)) < Float(CapitalBase.A) && abs(p.z - Float(cz)) < Float(CapitalBase.A) && p.y > Float(y0 - 20) && p.y < Float(y0 + 80)
    }
}

final class BaseWatch {
    var records: [String: BaseRecord] = [:]
    var noises: [BaseNoise] = []
    var patrols: [String: [Mob]] = [:]              // leader first
    var posts: [ObjectIdentifier: V3] = [:]          // where each patrol member / crewman goes back to
    var crews: [String: [Mob]] = [:]
    var workers: [String: [Mob]] = [:]
    var aircraft: [String: Ship] = [:]
    var queue: [String: [(IVec3, BlockID)]] = [:]
    var pending = Set<String>()
    private let lock = NSLock()
    private var ready: [String: [(IVec3, BlockID)]] = [:]
    var timer: Float = 0
    var tickMs: Double = 0, tickWorstMs: Double = 0, ticks = 0
    var log: [String] = []                            // harness: what happened, in order
    var quiet = false                                 // set round the Capital's own explosions (Ballistics.detonate)
    static var calmScale: Float = 1                   // harness: stand down faster (--basetest rebuild)

    // One watch per Game (the harness and the app each make one game).
    private static var current: (ObjectIdentifier, BaseWatch)?
    static func of(_ g: Game) -> BaseWatch {
        let id = ObjectIdentifier(g)
        if let c = current, c.0 == id { return c.1 }
        let w = BaseWatch()
        current = (id, w)
        return w
    }

    func note(_ s: String) {
        log.append(s)
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    // Hearing radius of a noise (blocks).
    static func hearing(_ n: BaseNoise) -> Float {
        switch n.kind {
        case .gunshot: return 96
        case .cannon: return 200
        case .explosion: return min(200, 64 + 24 * n.power)
        }
    }

    func setReady(_ key: String, _ cells: [(IVec3, BlockID)]) { lock.lock(); ready[key] = cells; lock.unlock() }
    func takeReady(_ key: String) -> [(IVec3, BlockID)]? {
        lock.lock(); defer { lock.unlock() }
        return ready.removeValue(forKey: key)
    }
}

extension Game {
    var bases: BaseWatch { BaseWatch.of(self) }

    // The noise bus: guns, cannon, turrets and explosions report here; citadels within hearing react.
    func baseNoise(at p: V3, kind: NoiseKind, power: Float = 1, hostile: Bool = true) {
        let b = bases
        if b.noises.count < 48 { b.noises.append(BaseNoise(pos: p, kind: kind, power: power, hostile: hostile && !b.quiet)) }
    }

    // MARK: Tick

    func basesTick(_ dt: Float) {
        let b = bases
        b.timer += dt
        guard b.timer >= 1 else { return }
        let step = b.timer
        b.timer = 0
        let t0 = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            b.tickMs += ms; b.ticks += 1; b.tickWorstMs = max(b.tickWorstMs, ms)
            b.noises.removeAll(keepingCapacity: true)
        }
        guard world.dim == .overworld, let sc = world.gen.structures else { return }
        // Citadels near the player (their centre chunk loaded) plus any with work in hand.
        if let s = sc.nearest("military_base", x: Int(player.pos.x), z: Int(player.pos.z), maxRegions: 1) {
            let cx = (s.min.x + s.max.x) / 2, cz = (s.min.z + s.max.z) / 2
            let key = "citadel:\(cx),\(cz)"
            if b.records[key] == nil && world.isLoaded(cx, cz) {
                b.records[key] = BaseRecord(key: key, cx: cx, cz: cz, y0: s.min.y + 20, lastTick: clock)
            }
        }
        for key in Array(b.records.keys) {
            guard var r = b.records[key] else { continue }
            guard world.isLoaded(r.cx, r.cz), world.isLoaded(r.cx, r.cz + 52) else { continue }
            let away = clock - r.lastTick
            r.lastTick = clock
            baseHear(&r, b)
            baseAlertStep(&r, b, step)
            if r.alert == .lockdown { baseLockdown(&r, b, step) } else { baseStandDown(&r, b) }
            basePatrol(&r, b, step)
            baseCrawler(&r, b, step)
            baseAir(&r, b, step)
            baseRebuild(&r, b, step, away: Float(away))
            b.records[key] = r
        }
    }

    // MARK: Hearing and alert

    private func baseHear(_ r: inout BaseRecord, _ b: BaseWatch) {
        let c = r.centre
        for n in b.noises where n.hostile {
            let d = simd_length(n.pos - c)
            guard d < BaseWatch.hearing(n) else { continue }
            r.calm = 0
            r.lastNoise = [n.pos.x, n.pos.y, n.pos.z]
            if r.inside(n.pos) {
                if n.kind == .explosion {
                    r.damage.append([n.pos.x, n.pos.y, n.pos.z, 1.5 + n.power * 1.25])
                    if r.damage.count > 64 { r.damage.removeFirst() }
                }
                if r.alert != .lockdown { b.note("\(r.key) lockdown (\(n.kind) inside, power \(n.power) at \(Int(n.pos.x)),\(Int(n.pos.y)),\(Int(n.pos.z)))") }
                raise(&r, .lockdown, b)
            } else {
                let level: BaseAlert = d < 70 || n.kind != .gunshot ? .alert : .suspicious
                raise(&r, level, b)
                if level == .alert && r.alert != .lockdown { baseCallAir(&r, b, to: n.pos) }      // the Kestrel goes up
                // Heavy noise far out: the crawler goes too.
                if n.kind != .gunshot && d > 70 && r.crawlerGoal == nil {
                    r.crawlerGoal = [n.pos.x, n.pos.y, n.pos.z]; r.crawlerPhase = 0; r.crawlerT = 0
                    b.note("\(r.key) crawler out to \(Int(n.pos.x)),\(Int(n.pos.z))")
                }
                if r.patrol == nil {
                    r.patrol = PatrolRecord(target: [n.pos.x, n.pos.y, n.pos.z], phase: 0, t: 0, size: n.kind == .gunshot ? 4 : 6)
                    b.note("\(r.key) patrol out to \(Int(n.pos.x)),\(Int(n.pos.z)) (\(n.kind), \(Int(d)) blocks)")
                    if simd_length(player.pos - c) < 140 { onToast?("A Capital patrol sets out to investigate") }
                } else if var pt = r.patrol, pt.phase < 3 {
                    pt.target = [n.pos.x, n.pos.y, n.pos.z]         // a newer noise redirects it
                    r.patrol = pt
                }
            }
        }
        // A garrison soldier who can see the player inside the walls is an attack too.
        if survival, r.inside(player.pos), r.alert != .lockdown {
            for m in mobs.mobs where m.kind.steelhold && m.kind != .deckGun && m.health > 0 && m.aggro && (m.brain?.sees ?? false) && r.inside(m.pos) {
                r.calm = 0
                b.note("\(r.key) lockdown (intruder)")
                raise(&r, .lockdown, b)
                break
            }
        }
    }

    private func raise(_ r: inout BaseRecord, _ a: BaseAlert, _ b: BaseWatch) {
        guard a.rawValue > r.alert.rawValue else { return }
        r.alert = a
        if a == .lockdown {
            r.dropships = 0
            r.dropshipCD = 4
            sfx(.gun(10), 1.4, at: r.centre)
            if simd_length(player.pos - r.centre) < 160 { onToast?("The citadel is on lockdown!") }
            baseCallAir(&r, b, to: r.centre)                         // air cover over the citadel
        }
    }

    // Stand down slowly: lockdown -> alert after 60 s of quiet, -> suspicious after 90, -> calm after 120.
    private func baseAlertStep(_ r: inout BaseRecord, _ b: BaseWatch, _ dt: Float) {
        r.calm += dt
        r.dropshipCD -= dt
        let limits: [Float] = [0, 120, 90, 60]
        if r.alert != .calm && r.calm > limits[r.alert.rawValue] * BaseWatch.calmScale {
            // Not while a soldier of this citadel is still fighting someone in sight.
            let fighting = mobs.mobs.contains { $0.kind.steelhold && $0.health > 0 && $0.aggro && ($0.brain?.sees ?? false) && simd_length($0.pos - r.centre) < 90 }
            if !fighting {
                let lower = BaseAlert(rawValue: r.alert.rawValue - 1) ?? .calm
                b.note("\(r.key) \(r.alert.name) -> \(lower.name)")
                r.alert = lower
                r.calm = 0
            }
        }
    }

    // The garrison soldiers of a citadel (inside its walls, not crewing, not on patrol).
    func garrison(_ r: BaseRecord, _ b: BaseWatch) -> [Mob] {
        let busy = Set((b.patrols[r.key] ?? []).map { ObjectIdentifier($0) } + (b.crews[r.key] ?? []).map { ObjectIdentifier($0) }
                       + (b.workers[r.key] ?? []).map { ObjectIdentifier($0) })
        return mobs.mobs.filter { m in
            m.kind.steelhold && m.kind != .deckGun && m.health > 0 && r.inside(m.pos) && !busy.contains(ObjectIdentifier(m))
                && (m.faction == 0 || m.faction == Faction.steelhold.rawValue) && m.deck == nil
        }
    }

    // MARK: Lockdown

    private func baseLockdown(_ r: inout BaseRecord, _ b: BaseWatch, _ dt: Float) {
        let src = r.lastNoise.map { V3($0[0], $0[1], $0[2]) } ?? r.centre
        let gar = garrison(r, b)
        // Everyone turns on the source.
        for m in gar {
            let br = m.soldierBrain
            br.ready = true
            if !m.aggro { m.aggro = true; br.react = max(br.react, 0.5) }
            if !br.sees { br.lastSeen = src; br.seenAgo = min(br.seenAgo, 2) }
            m.lockTime = max(m.lockTime, 30)
        }
        // Crews run to the turrets: two soldiers at the back of each barbette, in the gunner stance.
        var crew = (b.crews[r.key] ?? []).filter { $0.health > 0 }
        let turrets = mobs.of(.deckGun).filter { r.inside($0.pos) }
        if crew.count < turrets.count * 2 {
            var free = gar.filter { $0.kind != .soldierMarksman && $0.kind != .soldierOfficer }
            free.sort { simd_length($0.pos - r.centre) < simd_length($1.pos - r.centre) }
            for t in turrets {
                let assigned = crew.filter { $0.brain?.order.map { simd_length($0 - t.pos) < 14 } ?? false }.count
                for k in 0..<max(0, 2 - assigned) where !free.isEmpty {
                    let m = free.removeFirst()
                    let back = V3(sinf(t.yaw), 0, cosf(t.yaw))
                    let side = V3(cosf(t.yaw), 0, -sinf(t.yaw)) * (k == 0 ? -2.5 : 2.5)
                    let at = t.pos + back * 9 + side
                    let br = m.soldierBrain
                    if b.posts[ObjectIdentifier(m)] == nil { b.posts[ObjectIdentifier(m)] = m.home ?? m.pos }
                    br.order = V3(at.x, Float(r.y0 + 5), at.z)
                    br.orderStation = .gunner
                    br.orderRun = true
                    br.orderFace = t.pos
                    crew.append(m)
                }
            }
            if !crew.isEmpty && b.crews[r.key]?.isEmpty ?? true { b.note("\(r.key) turret crews: \(crew.count)") }
        }
        b.crews[r.key] = crew
        // Reinforcements: up to two Capital dropships, the first a few seconds after the alarm.
        if r.dropshipCD <= 0 && r.dropships < 2 {
            r.dropshipCD = 75
            let dir = simd_normalize(V3(r.centre.x - src.x, 0, r.centre.z - src.z) + V3(0.3, 0, 0.7))
            let from = r.centre + dir * 170 + V3(0, 60, 0)
            if world.ships.callDropship(faction: .steelhold, from: from, to: r.plaza, game: self) {
                r.dropships += 1
                b.note("\(r.key) dropship \(r.dropships) called")
            }
        }
        if Int(r.calm) % 8 == 0 && r.calm < 40 { sfx(.gun(10), 1.2, at: r.centre) }
    }

    // After a lockdown: crews leave the turrets and everyone goes back to their posts.
    private func baseStandDown(_ r: inout BaseRecord, _ b: BaseWatch) {
        if let crew = b.crews[r.key], !crew.isEmpty, r.alert.rawValue < BaseAlert.alert.rawValue {
            for m in crew where m.health > 0 {
                let br = m.soldierBrain
                br.station = .none
                br.orderStation = .none
                br.order = b.posts[ObjectIdentifier(m)]
                br.orderRun = false
                br.ready = false
            }
            b.crews[r.key] = []
            b.note("\(r.key) turret crews stand down")
        }
        if r.alert == .calm {
            for m in garrison(r, b) where m.brain?.ready ?? false { m.brain?.ready = false }
        }
        // Soldiers back at their posts drop their orders.
        for m in garrison(r, b) {
            guard let br = m.brain, let o = br.order, br.orderStation == .none else { continue }
            if simd_length(V2(m.pos.x - o.x, m.pos.z - o.z)) < 2.5 { br.order = nil; m.home = o; b.posts.removeValue(forKey: ObjectIdentifier(m)) }
        }
    }
}

// MARK: Soldier orders (used by the citadel; SoldierBrain fields in Soldiers.swift)

extension Mob {
    // A calm soldier with an order walks to it (at low ready when brain.ready) and takes its station on arrival.
    // Returns the walk speed, or nil when there is no order.
    func followOrder(_ g: Game) -> Float? {
        guard let b = brain, let o = b.order else { return nil }
        let d = simd_length(V2(o.x - pos.x, o.z - pos.z))
        if d > (b.orderStation == .none ? 1.6 : 0.9) {
            if b.station != .none { b.station = .none }
            face(o)
            moving = true
            return spec.speed * (b.orderRun ? 0.95 : 0.6)
        }
        moving = false
        if b.orderStation != .none {
            b.station = b.orderStation
            if let t = b.orderFace { face(t) }
        }
        return 0
    }
}
