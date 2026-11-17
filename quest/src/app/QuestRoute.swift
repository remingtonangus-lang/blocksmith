import Foundation
import simd

// Ledger 285 (store review, Meta Nov 17 on 0.131: VRC.Quest.Performance.1, "Your app fluctuates under and over 60
// frames per second... throughout the duration of the app experience"): nothing ever measured the headset before a store
// build went in. The route player plays a fixed route on the headset with no one in it, so tools/headset_gate.sh can
// read the runtime's frame rate (VrApi) leg by leg. It is off unless the debug property debug.sunderfall.route is set
// (`adb shell setprop debug.sunderfall.route all`; a player's headset can't set debug.* properties without adb):
//   all, or legs by name: menu newworld plains forest jungle village fight frigate train reload
//   combat legs (not in `all`; `combat` = all three): battle (the Ash Vault gate in the Deep at Total War, every
//   garrison awake), siege (the crawler parked 40 blocks off the nearest military base's wall, main gun into it every
//   5 s, its garrison fighting back), naval (two hostile frigates shelling him on a stone float at sea). Each prints
//   "route: leg NAME-load" while it is set up and "route: leg NAME" for its 90 s of fighting, and every 5 s
//   "route: combat ..." with the mobs, ships and particles (the perf line's quads count only the land).
// Each leg prints "route: leg NAME" (the gate tags every second after it with that leg); "route: done" at the end. The
// legs play through the game's own input (the pad the Touch controllers fill: stick forward, looking about, the
// trigger), with moves the player makes by travelling (to a biome, a village, a frigate's helm, a train's cab) done as
// a jump there with the land streaming in round him as it does on any arrival; those seconds are "NAME-arrive".
final class QuestRoute {
    static let all = ["menu", "newworld", "plains", "forest", "jungle", "village", "fight", "frigate", "train", "reload"]
    static let combat = ["battle", "siege", "naval"]
    static let combatSeed: UInt64 = 7653607216494784574        // (the host framesoak's crawler/citadel world)
    static let fightSeconds = 90.0
    static let seconds: [String: Double] = ["menu": 20, "newworld": 30, "plains": 90, "forest": 90, "jungle": 120,
                                            "village": 120, "fight": 120, "frigate": 120, "train": 120, "reload": 45]

    // The A/B route ("spots"): the same pictures every time, in a new creative world of a fixed seed (nothing of his
    // touched), noon, clear weather. Each spot: placed there (flying when in the air), no input, held until the chunk
    // jobs are 0 ("spot-NAME-load"), then held `hold` seconds ("spot-NAME"). x/z nil: found (biome or village).
    struct Spot { let name: String; let x: Float?; let y: Float?; let z: Float?; let yaw: Float; let find: String? }
    static let spotSeed: UInt64 = 3084501862406496736
    static let spotHold = 20.0
    static let spots: [Spot] = [
        Spot(name: "jungle", x: 718, y: 143, z: 30, yaw: 299, find: nil),           // his 49.8 fps at view 14
        Spot(name: "taiga", x: 148, y: 302, z: -3684, yaw: 0, find: nil),           // 56 fps at view 8
        Spot(name: "savanna", x: 2139.7, y: 122.1, z: 827.3, yaw: 229, find: nil),  // the frigate spot
        Spot(name: "beach", x: nil, y: nil, z: nil, yaw: 0, find: "beach"),         // water in view
        Spot(name: "village", x: nil, y: nil, z: nil, yaw: 90, find: "village"),
        Spot(name: "forest", x: nil, y: nil, z: nil, yaw: 0, find: "forest")]       // on the ground, eye height

    static let shared: QuestRoute? = {
        #if os(Android)
        let v = Env.androidProperty("debug.sunderfall.route")
        #else
        let v = Env.all["BS_ROUTE"] ?? ""
        #endif
        let s = v.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        guard !s.isEmpty else { return nil }
        let legs = s == "all" ? all : s == "spots" ? ["spotworld"] + spots.map { "spot-" + $0.name } : s == "combat" ? combat
            : s.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
                .flatMap { $0 == "combat" ? combat : [$0] }
                .filter { all.contains($0) || combat.contains($0) || $0 == "spotworld" || $0.hasPrefix("spot-") }
        guard !legs.isEmpty else { print("route: failed: no known leg in '\(s)'"); return nil }
        // (Nov 17: the combat legs ran in the world the app opened, his own. They now get a world of their own first.)
        var legs2 = legs
        if let i = legs2.firstIndex(where: { combat.contains($0) }), !legs2[..<i].contains("combatworld") { legs2.insert("combatworld", at: i) }
        print("route: legs \(legs2.joined(separator: " "))")
        return QuestRoute(legs2)
    }()

    let legs: [String]
    private var index = -1
    private var legTime = 0.0
    private var phase = 0                       // per leg: 0 set up, 1 arriving, 2 playing
    private var target: V3?                     // where an arrival goes (found off the frame thread)
    private var seeking = false
    private var found: V3?
    private let lock = NSLock()
    private var ship: Ship?
    private var drive: (() -> Void)?
    private var worldName = ""
    private var frame = 0

    init(_ legs: [String]) { self.legs = legs }

    var leg: String { index >= 0 && index < legs.count ? legs[index] : "" }
    // What the gate tags seconds with now ("spot-jungle-load", "plains-arrive" ...); the host soak reads it too.
    private(set) var label = ""
    var done: Bool { index >= legs.count }
    private func mark(_ s: String) { label = String(s.split(separator: " ").first ?? ""); print("route: leg " + s) }

    private func next(_ app: QuestApp?) {
        index += 1; legTime = 0; phase = 0; target = nil; seeking = false; ship = nil; drive = nil
        if index >= legs.count { print("route: done"); return }
        mark("\(leg)")
    }

    // Once a frame (QuestApp.frame), before the tick, after the controls filled the pad. `game` nil while loading.
    func step(_ app: QuestApp, _ game: Game?, dt: Double) {
        frame += 1
        if index < 0 { if game != nil { next(app) }; return }
        guard index < legs.count else { return }
        legTime += dt
        guard let g = game else { return }                         // (a world loading: its time counts in its leg)
        g.health = max(g.health, 10); g.alive = true             // (the route never ends in death)
        let want = QuestRoute.seconds[leg] ?? 60
        if leg == "combatworld" {
            if phase == 0 {
                phase = 1
                worldName = "GateCombat\(Int(Date().timeIntervalSince1970) % 100000)"
                g.paused = false; g.closeMenu()
                app.routeAction("create:0:3:1:\(worldName):\(QuestRoute.combatSeed)")
                return
            }
            if g.world.seed == QuestRoute.combatSeed && legTime > 5 { claim(g); next(app) }
            return
        }
        // Never in a world the route did not make: the spots and combat legs change the world (mode, mobs, blocks).
        if (leg.hasPrefix("spot-") || QuestRoute.combat.contains(leg)) && !ownWorld(g) {
            print("route: failed: leg \(leg) refused: world '\(g.save?.dir.lastPathComponent ?? "?")' is not the route's own ('\(worldName)')")
            index = legs.count
            return
        }
        if leg == "spotworld" {
            if phase == 0 {
                phase = 1
                g.paused = false; g.closeMenu()          // (a fresh install's first-launch setup panel)
                worldName = "GateSpots\(Int(Date().timeIntervalSince1970) % 100000)"
                app.routeAction("create:0:3:1:\(worldName):\(QuestRoute.spotSeed)")
                return
            }
            if g.world.seed == QuestRoute.spotSeed && legTime > 5 { claim(g); next(app) }
            return
        }
        if leg.hasPrefix("spot-"), let sp = QuestRoute.spots.first(where: { "spot-" + $0.name == leg }) {
            spot(g, sp)
            return
        }
        if QuestRoute.combat.contains(leg) {
            combatLeg(app, g)
            return
        }
        switch leg {
        case "menu":
            if phase == 0 { phase = 2; g.paused = true; (g.menu as? PauseMenu)?.build() }
            if legTime > want { g.paused = false; g.closeMenu(); next(app) }
        case "newworld":
            if phase == 0 {
                phase = 1
                worldName = "Gate\(Int(Date().timeIntervalSince1970) % 100000)"
                app.routeAction("create:1:3:1:\(worldName):\(Int(Date().timeIntervalSince1970))")
                return
            }
            if legTime > want { next(app) }
        case "plains", "forest", "jungle":
            arrive(g, biome: leg == "forest" ? "forest" : leg)
            if phase == 2 { walk(g) }
            if legTime > want { next(app) }
        case "village":
            if phase == 0 {
                phase = 1
                if let st = g.world.gen.structures?.nearestIfReady("village", x: Int(g.player.pos.x), z: Int(g.player.pos.z), maxRegions: 6) {
                    let r = Float(max(st.max.x - st.min.x, st.max.z - st.min.z)) / 2
                    target = V3(Float(st.min.x + st.max.x) / 2 + r * 0.6, g.player.pos.y, Float(st.min.z + st.max.z) / 2 + 0.5)
                }
            }
            if phase == 1 { land(g, then: { g.player.yaw = .pi / 2 }) }
            if phase == 2 { walk(g) }
            if legTime > want { next(app) }
        case "fight":
            if phase == 0 {
                phase = 2
                g.survival = true; g.difficulty = 2
                for k in 0..<10 {
                    let a = Float(k) * 0.628, p = g.player.pos + V3(cosf(a) * 12, 1, sinf(a) * 12)
                    g.mobs.mobs.append(Mob(k % 3 == 2 ? .skeleton : .zombie, at: p))
                }
            }
            // (turned to the nearest, the trigger every half second)
            if let m = g.mobs.mobs.filter({ $0.health > 0 && ($0.kind == .zombie || $0.kind == .skeleton) })
                .min(by: { simd_length($0.pos - g.player.pos) < simd_length($1.pos - g.player.pos) }) {
                let d = m.pos - g.player.pos
                g.player.yaw = atan2f(-d.x, -d.z)
            }
            var pad = PadManager.shared.touch ?? PadSnapshot()
            pad.rt = frame % 36 < 4 ? 1 : 0
            PadManager.shared.touch = pad
            if legTime > want { next(app) }
        case "frigate":
            if phase == 0 {
                phase = 2
                let w = g.world
                let n = w.ships.capitals.count
                w.ships.spawnCapital("warfrigate", home: IVec3(Int(floor(g.player.pos.x)), 0, Int(floor(g.player.pos.z)) + 24), yaw: 0, region: nil)
                print("route: frigate asked for (\(n) capitals before)")
            }
            if ship == nil, let s = g.world.ships.capitals.first(where: { $0.role == "warfrigate" }), let st = g.world.ships.capState[s.id],
               let stand = g.helmStand(s) {
                st.crewDone = Set(0..<st.crew.count); st.crewless = true
                st.testTurn = 0; st.testSpeed = 10
                ship = s
                g.player.flying = false
                g.player.pos = s.toWorld(stand); g.player.vel = s.velocity(at: g.player.pos)
                print(String(format: "route: aboard %@", s.name))
            }
            if let s = ship, let stand = g.helmStand(s), simd_length(g.player.pos - s.toWorld(stand)) > 3 {
                g.player.pos = s.toWorld(stand); g.player.vel = s.velocity(at: g.player.pos)
            }
            if legTime > want { next(app) }
        case "train":
            if phase == 0 {
                phase = 2
                if let gen = g.world.gen as? WorldGen {
                    let ax = Int(g.player.pos.x), az = Int(g.player.pos.z)
                    if let l = Railways.near(gen, x0: ax - 2000, z0: az - 2000, x1: ax + 2000, z1: az + 2000, pad: 0, wait: false)
                        .filter({ $0.stations.count >= 1 })
                        .min(by: { abs($0.minX - ax) + abs($0.minZ - az) < abs($1.minX - ax) + abs($1.minZ - az) }) {
                        let c0 = l.cells[l.stations[0].index]
                        g.player.pos = V3(Float(c0.x) + 0.5, Float(c0.y) + 1, Float(c0.z - 2) + 0.5)
                        print("route: to the line \(l.name)")
                    } else { print("route: no line planned within 2,000 blocks yet") }
                }
            }
            if g.riding == nil, frame % 72 == 0 {
                // (into the nearest train's lead car once one comes by, then the regulator open)
                if let tr = Trains.trains.values.min(by: { a, b in
                    guard let ca = a.cars.first, let cb = b.cars.first else { return false }
                    return simd_length(ca.pos - g.player.pos) < simd_length(cb.pos - g.player.pos) }),
                   let lead = tr.cars.first, simd_length(lead.pos - g.player.pos) < 40 {
                    _ = Trains.use(g, lead); tr.throttle = 2
                    drive = { tr.throttle = 2 }
                    print("route: aboard a train")
                }
            }
            drive?()
            if legTime > want { next(app) }
        case "reload":
            if phase == 0 {
                phase = 1
                g.saveNow()
                let name = g.save?.dir.lastPathComponent ?? worldName
                app.routeAction("play:\(name)")
                return
            }
            if legTime > want { next(app) }
        default:
            next(app)
        }
    }

    private var holdFrom = -1.0
    private func spot(_ g: Game, _ sp: Spot) {
        g.time = 0.25 * DAY_LENGTH
        g.weather.raining = false; g.weather.thundering = false; g.weather.rain = 0
        g.survival = false
        if phase == 0 {
            holdFrom = -1
            if let x = sp.x, let y = sp.y, let z = sp.z {
                target = V3(x, y + Float(YOFF), z); phase = 1
                g.player.pos = target!; g.player.flying = true; g.player.vel = .zero
                g.player.yaw = -sp.yaw * .pi / 180; g.player.pitch = -10 * .pi / 180
                mark("\(leg)-load")
            } else if sp.find == "village" {
                if let st = g.world.gen.structures?.nearestIfReady("village", x: 0, z: 0, maxRegions: 8) {
                    target = V3(Float(st.min.x + st.max.x) / 2 + 0.5, 0, Float(st.min.z + st.max.z) / 2 + 0.5); phase = 1
                }
                if legTime > 30 && phase == 0 { print("route: no village planned near spawn"); next(nil); return }
            } else if let b = sp.find {
                arrive(g, biome: b)                     // (phase 1: the search runs; placed below once found)
            }
            if phase == 1, sp.x == nil { mark("\(leg)-load") }
            return
        }
        if target == nil {
            lock.lock(); let busy = seeking; if !busy { target = found }; lock.unlock()
            if busy { return }
        }
        guard let t = target else { next(nil); return }
        if sp.x != nil {
            g.player.pos = t; g.player.vel = .zero; g.player.flying = true
        } else {
            // (on the ground at eye height, once his chunk is in)
            g.player.flying = true; g.player.vel = .zero
            let px = Int(floor(t.x)), pz = Int(floor(t.z))
            if let c = g.world.chunkAt(px, pz) {
                g.player.pos = V3(t.x, Float(c.height[mod(px, CS) + mod(pz, CS) * CS]) + 1.01, t.z)
                g.player.flying = false
            } else { g.player.pos = V3(t.x, Float(CH - 40), t.z) }
            g.player.yaw = -sp.yaw * .pi / 180; g.player.pitch = -5 * .pi / 180
        }
        PadManager.shared.touch = PadSnapshot()
        if holdFrom < 0 {
            if g.world.pendingJobs == 0 && legTime > 3 { holdFrom = legTime; mark("\(leg)") }
            else if legTime > 90 { holdFrom = legTime; mark("\(leg) (jobs never reached 0: \(g.world.pendingJobs))") }
        } else if legTime - holdFrom > QuestRoute.spotHold { next(nil) }
    }

    // A jump to the middle of `biome`: the search runs on a utility thread; then landing.
    private func arrive(_ g: Game, biome: String) {
        if phase == 0 {
            phase = 1
            seeking = true
            let gen = g.world.gen
            let from = g.player.pos
            found = nil
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let p = QuestRoute.findBiome(gen, biome, from: from)
                if p == nil { print("route: no \(biome) found: walking on here") }
                self?.lock.lock(); self?.found = p; self?.seeking = false; self?.lock.unlock()
            }
        }
        lock.lock(); let busy = seeking; if !busy && target == nil { target = found }; lock.unlock()
        if phase == 1 && !busy {
            if target == nil { phase = 2; return }
            land(g)
        }
    }

    // Arriving at `target`: held in the air (flying) until his chunk is in, then set on the ground.
    private func land(_ g: Game, then: () -> Void = {}) {
        guard let t = target else { phase = 2; return }
        if simd_length(V2(g.player.pos.x - t.x, g.player.pos.z - t.z)) > 1 {
            mark("\(leg)-arrive")
            g.player.pos = V3(t.x, Float(CH - 40), t.z)
        }
        g.player.flying = true; g.player.vel = .zero
        let px = Int(floor(t.x)), pz = Int(floor(t.z))
        guard let c = g.world.chunkAt(px, pz) else { return }
        let y = Int(c.height[mod(px, CS) + mod(pz, CS) * CS])
        g.player.pos = V3(t.x, Float(y + 1) + 0.01, t.z)
        g.player.flying = false
        phase = 2
        then()
        mark("\(leg)")
    }

    // On foot, stick forward, looking about.
    private func walk(_ g: Game) {
        var pad = PadManager.shared.touch ?? PadSnapshot()
        pad.ly = 1
        pad.rx = frame % 720 < 360 ? 0.25 : -0.25
        PadManager.shared.touch = pad
    }

    // MARK: Combat legs (Fable, Nov 17: the route's fight and frigate legs were thin: 10 vanilla mobs, a crewless
    // frigate, nothing firing). The heaviest fights the game has, staged where they happen.
    private var fightFrom = -1.0
    private var lastCount = -1.0
    private var stand = V3.zero, aim = V3.zero, before: V3?
    private var crawler: Ship?
    private func combatLeg(_ app: QuestApp, _ g: Game) {
        g.health = 20; g.alive = true
        if phase == 0 {
            phase = 1; fightFrom = -1; lastCount = -1; crawler = nil; found = nil; target = nil
            if g.paused || g.menu != nil { g.paused = false; g.closeMenu() }     // (a fresh install's setup panel)
            if g.dim.dim == .overworld { before = g.player.pos }
            mark("\(leg)-load")
            if leg != "battle" {
                // (the base or the sea found off the frame thread)
                seeking = true
                let gen = g.world.gen, from = g.player.pos, which = leg
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    var p: V3?
                    if which == "siege" {
                        if let st = gen.structures?.nearest("military_base", x: Int(from.x), z: Int(from.z), maxRegions: 24) {
                            let cz = Float(st.min.z + st.max.z) / 2, cx = Float(st.min.x + st.max.x) / 2
                            p = V3(Float(st.min.x) - 40, Float(st.pieces.first?.min.y ?? 140) + 12, cz)
                            self?.lock.lock(); self?.aim = V3(cx, p!.y, cz); self?.lock.unlock()
                        }
                    } else {
                        p = QuestRoute.findBiome(gen, "*ocean", from: from)
                    }
                    if p == nil { print("route: \(which): nothing found to fight at") }
                    self?.lock.lock(); self?.found = p; self?.seeking = false; self?.lock.unlock()
                }
            }
            return
        }
        if phase == 1 {
            switch leg {
            case "battle":
                // (one long frame: the Deep loaded round the gate and its garrisons ticked in; counted in battle-load)
                stand = AshVaultGapTests.battleScene(g)
                g.player.yaw = .pi; g.player.pitch = 0.05
                fight()
            case "siege", "naval":
                if target == nil {
                    lock.lock(); let busy = seeking; if !busy { target = found }; lock.unlock()
                    if busy { return }
                    guard let t = target else { next(app); return }
                    if g.dim.dim != .overworld, let b = before { g.changeDimension(to: .overworld, at: b) }
                    g.player.pos = V3(t.x, Float(CH - 40), t.z); g.player.flying = true; g.player.vel = .zero
                    g.world.ships.encounters = false
                    return
                }
                let t = target!
                g.player.flying = true; g.player.vel = .zero
                let px = Int(floor(t.x)), pz = Int(floor(t.z))
                guard let c = g.world.chunkAt(px, pz), g.world.pendingJobs < 8 || legTime > 45 else { return }
                let w = g.world
                if leg == "siege" {
                    let gy = Int(c.height[mod(px, CS) + mod(pz, CS) * CS])
                    stand = V3(t.x, Float(gy + 1), t.z)
                    w.ships.spawnCapital("crawler", home: IVec3(px, 0, pz), yaw: -.pi / 2, region: nil, sync: true)
                    guard let cr = w.ships.capitals.first(where: { $0.role == "crawler" }), let st = w.ships.capState[cr.id], let hc = cr.helm else {
                        print("route: siege: no crawler could be spawned"); next(app); return
                    }
                    st.crewDone = Set(0..<st.crew.count); st.crewless = true; st.testTurn = 0; st.testSpeed = 0
                    crawler = cr
                    g.player.flying = false
                    g.player.pos = cr.toWorld(V3(Float(hc.x) + 0.5, Float(hc.y) + 1.02, Float(hc.z) + 1.5))
                    g.player.vel = cr.velocity(at: g.player.pos)
                    g.player.yaw = -.pi / 2; g.player.pitch = -0.15
                } else {
                    let top = SEA
                    for dz in -3...3 { for dx in -3...3 { w.setBlock(px + dx, top, pz + dz, STONE) } }
                    stand = V3(Float(px) + 0.5, Float(top + 1), Float(pz) + 0.5)
                    g.player.pos = stand; g.player.flying = false
                    w.ships.spawnCapital("capfrigate", home: IVec3(px, 0, pz + 90), yaw: 0, region: nil, sync: true)
                    w.ships.spawnCapital("capfrigate", home: IVec3(px - 85, 0, pz - 30), yaw: .pi / 2, region: nil, sync: true)
                    g.player.yaw = .pi; g.player.pitch = -0.1
                }
                fight()
            default: next(app)
            }
            return
        }
        // Fighting.
        g.survival = true; g.difficulty = 2
        let t = legTime - fightFrom
        switch leg {
        case "battle":
            g.ashSpot = stand; g.ashSpotSeen = g.clock
            g.player.yaw = .pi + 0.5 * sinf(Float(t) * 0.4)        // (looking along the wall and back)
        case "siege":
            if let cr = crawler, let st = g.world.ships.capState[cr.id] {
                if let hc = cr.helm {
                    let h = cr.toWorld(V3(Float(hc.x) + 0.5, Float(hc.y) + 1.02, Float(hc.z) + 1.5))
                    if simd_length(g.player.pos - h) > 3 { g.player.pos = h; g.player.vel = cr.velocity(at: h) }
                }
                if frame % 360 == 180 {
                    lock.lock(); let a = aim; lock.unlock()
                    let mw = cr.toWorld(st.mainGunMuzzle)
                    g.world.ships.fireMainGun(cr, st, dir: simd_normalize(a - mw + V3(1e-5, 0, 0)), game: g)
                }
            }
        case "naval":
            if simd_length(g.player.pos - stand) > 4 { g.player.pos = stand; g.player.vel = .zero }
            g.player.yaw = .pi + 0.8 * sinf(Float(t) * 0.3)
        default: break
        }
        if t - lastCount >= 5 {
            lastCount = t
            let mobs = g.mobs.mobs.filter { $0.health > 0 }
            let hostile = mobs.filter { $0.aggro }.count
            print("route: combat \(leg) \(Int(t)) s: \(mobs.count) mobs (\(hostile) aggro), \(g.world.ships.list.count) ships (\(g.world.ships.capitals.count) capital), \(g.particles.list.count) particles")
        }
        if t > QuestRoute.fightSeconds {
            // (back to the overworld for the legs after)
            if leg == "battle", let b = before { g.changeDimension(to: .overworld, at: b) }
            next(app)
        }
    }
    // The world the route made itself (spotworld, combatworld), by its save folder's name.
    private var ownDir: String?
    private func ownWorld(_ g: Game) -> Bool { ownDir != nil && g.save?.dir.lastPathComponent == ownDir }
    // (the world just made: its folder, if it is one of the route's "Gate" worlds)
    private func claim(_ g: Game) {
        let d = g.save?.dir.lastPathComponent ?? ""
        ownDir = d.hasPrefix("Gate") ? d : nil
        print("route: world \(d)\(ownDir == nil ? " is NOT the route's own" : "")")
    }
    private func fight() { phase = 2; fightFrom = legTime; lastCount = -5; mark(leg) }

    // The nearest middle of `biome` from `from` (QuestFrameSoak.findBiome's spiral, 48-block steps).
    static func findBiome(_ gen: TerrainGenerator, _ want: String, from: V3) -> V3? {
        let r = 32
        var x = 0, z = 0, dx = 0, dz = -1
        let ox = Int(from.x), oz = Int(from.z)
        let probes: [(Int, Int)] = [(0, 0), (r, 0), (-r, 0), (0, r), (0, -r)]
        for _ in 0..<40000 {
            let wx = ox + x * 48 + 8, wz = oz + z * 48 + 8
            if probes.allSatisfy({ want == "*ocean" ? gen.column(wx + $0.0, wz + $0.1).biome.isOcean : gen.column(wx + $0.0, wz + $0.1).biome.name == want }) {
                return V3(Float(wx) + 0.5, 0, Float(wz) + 0.5)
            }
            if x == z || (x < 0 && x == -z) || (x > 0 && x == 1 - z) { (dx, dz) = (-dz, dx) }
            x += dx; z += dz
        }
        return nil
    }
}

extension QuestApp {
    // The route player's world moves (QuestRoute): the pause menu's own actions.
    func routeAction(_ id: String) { appAction(id) }
}
