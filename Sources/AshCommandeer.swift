import Foundation
import Metal
import simd

// P324 (Oct 15 18:54-19:07: "I should be able to drive the tank... core feature", "their rocket half-tracks, their
// motorcycles with the sidecar", "none of them are driving around"). The Ashguard's vehicles, taken and driven:
//   take one    P344 (Oct 16 19:49-19:58: "getting into a half-track turned it into a different vehicle", "can't get in
//               the Tiger or use the artillery"): use a Cinder Tank, a half-track, a truck or a field gun and its crew
//               climbs out fighting (tank 3, half-track 2, gun 2, truck 1); the vehicle itself stays exactly what it
//               was (the same hull, model and guns) and he takes its controls (AshSeat): the stick drives and steers
//               the hull, the turret or the field gun lays on his view, the trigger fires the seat's gun (the tank's
//               main gun, its coaxial MG while the main gun reloads; the field gun; the half-track's rear MG from the
//               gunner's seat: jump moves between the driver's and the gunner's seats), sneak climbs out. Hands are on
//               the controls (P282 rules).
//   empty       a hull knocked under a third bails its crew out on its own; an empty vehicle (bailed, or one he has
//               left) is his and stands parked: P344 (e), no vehicle moves without a crew. Crewed half-tracks show
//               their driver and gunner, a crewed tank its commander in the cupola.
//   rockets     half-tracks carry a four-rocket rack: from 14 blocks out they loose a salvo about every 9 s, on top
//               of the pintle MG.
//   sidecars    beside one half-track or truck in two stands an Ashguard sidecar motorcycle: two wheels in line and a
//               car with its own wheel and a light machine gun, quick and light, free to take at its helm.
//   patrols     half the tanks, half-tracks and trucks no longer sit parked: calm, they drive a loop of four points
//               round where they stood, and turn to fight when they see him (trucks drive at 3.6 b/s now).
enum AshCommandeer {
    static let clearRange: Float = 20
    static let bailAt: Float = 1.0 / 3
    static let patrolRadius: Float = 26
    static let salvo = 4
    static let salvoEvery: ClosedRange<Float> = 8...10
    static let sidecarName = "Ashguard Sidecar"
    static let crewOut: Float = 4.5               // the crew jumps down this far from the hull's middle (outside its wheels)
    static var taken = 0, bailed = 0, salvos = 0, sidecars = 0, sidecarNoRoom = 0          // (counters)

    static func takeable(_ k: MobKind) -> Bool { k == .ashTank || k == .ashHalftrack || k == .ashTruck || k == .ashArtillery }
    static func crew(_ k: MobKind) -> Int { k == .ashTank ? 3 : (k == .ashHalftrack || k == .ashArtillery ? 2 : 1) }

    // Half of the army's vehicles patrol (by where they first stood).
    static func patrols(_ m: Mob, home h: V3) -> Bool {
        takeable(m.kind) && hash3(Int(floor(h.x)), 31, Int(floor(h.z)), 0xA59) % 2 == 0
    }

    // The sidecar motorcycle, front toward -Z: the bike on x 0 (two wheels in line), the car on x 1 with its own wheel
    // and a light machine gun.
    // P449 (Oct 25 09:04-09:05: "why are there five wheels clumped together?"; "doesn't look anything like that"): each
    // wheel was a plus of five wheel blocks three tall, drawn as five discs, the bike riding a block and a half up on
    // them. A wheel is one block now, the bike four blocks long over its two, the car low beside it on its own.
    static func sidecar() -> Blueprint {
        let b = Blueprint()
        b.set(0, 0, 0, "ship_wheel"); b.set(0, 0, 3, "ship_wheel"); b.set(1, 0, 2, "ship_wheel")
        b.set(0, 1, 0, "iron_bars")                                  // the forks and handlebars over the front wheel
        // P435: the controls just behind the handlebars, the rider in the saddle facing the way it goes; the engine
        // under the pillion.
        b.set(0, 1, 1, "ship_helm[south]")
        b.set(0, 1, 2, "ship_engine")
        b.set(0, 1, 3, "polished_blackstone")                        // the pillion over the rear wheel
        b.set(1, 1, 1, "red_nether_bricks")                          // the car's nose
        b.set(1, 1, 2, "polished_blackstone"); b.set(1, 1, 3, "polished_blackstone")
        b.set(1, 2, 2, "ship_cannon[south]")                         // the car's machine gun
        return b
    }
}

extension Game {
    // Mob use (Farming.mobInteract): take an Ashguard vehicle's controls (P344: whoever is still aboard climbs out
    // fighting; the vehicle stays itself). True when handled.
    func ashCommandeer(_ m: Mob) -> Bool {
        guard AshCommandeer.takeable(m.kind), m.health > 0, alive, world.ships.pilot == nil, AshSeat.shared.vehicle == nil else { return false }
        if !m.tamed { ashEmpty(m) }
        AshSeat.shared.enter(self, m)
        return true
    }

    // P464 (Oct 25 19:33, "should be able to run people over with it"): the vehicle he drives runs down whoever stands
    // in front of it (behind, backing up) at more than a walking pace: a blow growing with the speed (a truck at full
    // throttle kills a soldier outright; a tank kills anything on foot) and a shove off to the side. Other vehicles and
    // big beasts it only nudges.
    func ashRunOver(_ v: Mob, _ speed: Float) {
        guard abs(speed) > 2.5 else { return }
        let dir = v.forward * (speed > 0 ? 1 : -1), side = V3(-dir.z, 0, dir.x)
        let reach: Float = (v.kind == .ashBehemoth ? 4.4 : (v.kind == .ashTank ? 3.4 : 3.0)) + 0.6
        let heavy = v.kind == .ashTank || v.kind == .ashBehemoth
        for m in mobs.mobs where m !== v && m.health > 0 && !m.kind.ashVehicle && m.kind != .deckGun && m.spec.halfW < 1 {
            let d = m.pos - v.pos
            let along = simd_dot(d, dir), across = simd_dot(d, side)
            guard along > 0, along < reach, abs(across) < v.halfW + m.spec.halfW + 0.1, abs(d.y) < 2.5 else { continue }
            if clock - m.playerHurtAt < 0.6 { continue }                       // (once per pass)
            let dmg = Int((abs(speed) * (heavy ? 5 : 2.4)).rounded())
            m.killedByPlayer = true; m.playerHurtAt = clock
            m.hit(from: v.pos - dir, damage: dmg, knockback: 1.6)
            m.vel += side * (across < 0 ? -1 : 1) * min(8, abs(speed)) + V3(0, 3, 0)
            sfx(.shipCollide, min(1.5, abs(speed) / 8), at: m.pos)
            AshSeat.ranOver += 1
        }
    }

    func ashguardNear(_ p: V3, _ r: Float, except: Mob) -> Bool {
        mobs.mobs.contains { $0 !== except && $0.health > 0 && $0.faction == Faction.ashguard.rawValue && !$0.kind.ashVehicle
            && simd_length_squared($0.pos - p) < r * r }
    }

    // The crew climbs out (fighting) and the vehicle stands empty: his, parked until he takes its controls.
    func ashEmpty(_ m: Mob) {
        guard AshCommandeer.takeable(m.kind), !m.tamed else { return }
        ashBailOut(m)
        m.owner = true
        m.aggro = false
        m.persistent = true
        m.soldierBrain.order = nil
        m.soldierBrain.charge = 0
        AshCommandeer.taken += 1
    }

    // Its crew jumps down beside it, rifles up.
    func ashBailOut(_ m: Mob) {
        let w = world
        for i in 0..<AshCommandeer.crew(m.kind) {
            let a = m.yaw + Float(i) * 2.1
            var p = m.pos + V3(cosf(a), 0, -sinf(a)) * AshCommandeer.crewOut
            let x = Int(floor(p.x)), z = Int(floor(p.z)), y = Int(floor(m.pos.y))
            if w.solidAt(x, y, z) || w.solidAt(x, y + 1, z) { p = m.pos + V3(0, m.height + 0.2, 0) }
            let c = Mob(.soldierCrew, at: p)
            if !m.boreal { c.ashSetup() }                     // (a Boreal vehicle's crew are the Capital's)
            c.persistent = true
            c.aggro = true
            c.soldierBrain.lastSeen = player.eye
            c.soldierBrain.seenAgo = 0
            c.lockTime = 20
            mobs.mobs.append(c)
        }
        AshCommandeer.bailed += 1
        sfx(.ironDoorOpen, 0.9, at: m.pos + V3(0, m.height, 0))
    }

    // Each AI tick of a crewed Ashguard vehicle (Mob.ashVehicleAI). True when the hull was knocked out and left empty.
    func ashVehicleLife(_ m: Mob, dist: Float) -> Bool {
        guard AshCommandeer.takeable(m.kind) else { return false }
        let b = m.soldierBrain
        if m.home == nil { m.home = m.pos }              // (saved with the mob: the loop stays put across loads)
        if b.patrolHome == nil { b.patrolHome = m.home }
        if Float(m.health) <= Float(m.spec.health) * AshCommandeer.bailAt {
            ashEmpty(m)
            return true
        }
        // One half-track or truck in two keeps a sidecar motorcycle beside it (none if one already stands near).
        if m.kind != .ashTank, !m.boreal, !b.sidecarDone, dist < 64, let h = b.patrolHome {
            b.sidecarDone = true
            if hash3(Int(floor(h.x)), 7, Int(floor(h.z)), 0x51DE) % 2 == 0
                && !world.ships.list.contains(where: { $0.name == AshCommandeer.sidecarName && simd_length($0.pos - h) < 18 }) {
                ashParkSidecar(beside: m, at: h)
            }
        }
        return false
    }

    func ashParkSidecar(beside m: Mob, at h: V3) {
        let w = world
        let side = V3(cosf(m.yaw), 0, -sinf(m.yaw))
        for gap: Float in [3.5, -3.5, 5.5, -5.5] {
            let at = h + side * (3 + gap)
            let x = Int(floor(at.x)), z = Int(floor(at.z))
            guard w.isLoaded(x, z) else { return }
            // Level ground beside it (a surface within two blocks of the vehicle's: block ground found looking down
            // from just above it, so a cavern's roof never counts; else the drawn ground) with room above.
            var floorY: Float?
            for yy in stride(from: Int(floor(h.y)) + 2, through: Int(floor(h.y)) - 2, by: -1)
                where w.solidAt(x, yy - 1, z) && !w.solidAt(x, yy, z) { floorY = Float(yy); break }
            if floorY == nil, abs(w.ships.groundTop(x, z) + 1 - h.y) <= 1.5 { floorY = w.ships.groundTop(x, z) + 1 }
            guard let floorY else { continue }
            let y = Int(floorY)
            var clear = true
            for dz in -3...3 { for dy in 0...2 where w.solidAt(x, y + dy, z + dz) { clear = false } }
            guard clear else { continue }
            let s = w.ships.spawn(AshCommandeer.sidecar(), at: V3(at.x, floorY + 3, at.z), yaw: m.yaw, name: AshCommandeer.sidecarName, role: "")
            s.role = nil
            VehicleWorks.settle(s, on: V3(at.x, floorY, at.z))
            s.initialBlocks = s.blockCount
            s.gunPower = 0.5; s.reloadTime = 0.18; s.gunSpeed = 90; s.gunGravity = 4; s.gunScatter = 0.035
            AshCommandeer.sidecars += 1
            return
        }
        AshCommandeer.sidecarNoRoom += 1
    }

    // A calm patrolling vehicle's next point: four points round where it stood, in turn (nil: it stays parked).
    func ashPatrolPoint(_ m: Mob) -> V3? {
        let b = m.soldierBrain
        guard !m.aggro, let h = b.patrolHome, AshCommandeer.patrols(m, home: h) else { return nil }
        b.patrolLeg += 1
        let turn = Float(hash3(Int(floor(h.x)), 3, Int(floor(h.z)), 0xA5A) % 100) / 100 * .pi
        let a = Float(b.patrolLeg % 4) * .pi / 2 + turn
        return V3(h.x + cosf(a) * AshCommandeer.patrolRadius, h.y, h.z + sinf(a) * AshCommandeer.patrolRadius)
    }
}

// P344: the controls of an Ashguard vehicle he has taken (the way Turrets mans a deck gun): from Game.tick before
// movement. The vehicle mob drives itself from these (Mob.ashSeatDrive); he rides at the seat.
final class AshSeat {
    static var shared = AshSeat()
    weak var vehicle: Mob?
    var gunner = false                  // the half-track's rear machine gun (else the driver's seat)
    var drive: Float = 0, steer: Float = 0
    var sprint = false                  // P435: the sprint button opens the throttle right up
    var fireTap = false, fireHeld = false
    // P435 (Oct 24 15:49-15:56): his guns hit like the real thing. The tank's 75 mm round (a crew's is power 1.3 and
    // breaks nothing) and the field gun's shell burst against walls and hole a vehicle's plate (Slug.antiTank).
    static let tankPower: Float = 3.6, tankAntiTank: Float = 110
    static let gunPower: Float = 4.2, gunAntiTank: Float = 90
    // P449 (Oct 25 09:05, "the explosion from your artillery took way too long to generate"): the field gun's shell left
    // at 46 blocks a second under 12 of drop, 2-7 s in the air (and a high shot outlived its 6 s and vanished with no
    // burst). Now 100 under 40: about the same reach (250 blocks at most), a 100-block shot lands in about 1 s.
    static let gunSpeed: Float = 100, gunGravity: Float = 40
    // P435 (15:49, "when you sprint with the tank, it goes up to like 30, 40 kilometers per hour"): driven by him, a
    // vehicle cruises at the first speed and sprints at the second (blocks a second; 10 b/s is 36 km/h). The crews
    // still drive at the spec's pace.
    static func seatSpeed(_ k: MobKind) -> (cruise: Float, sprint: Float) {
        switch k {
        case .ashTank: return (4.5, 10.5)
        case .ashHalftrack: return (6, 13)
        default: return (6.5, 14)                   // the truck
        }
    }
    private var jumpWas = false
    static var entered = 0, shots = 0, ploughed = 0, tracked = 0, ranOver = 0   // (counters)
    static var lastDrive: Float = 0                 // (the throttle the stick last asked for, -1...1)

    // The seat on the vehicle, in its own frame (blocks: x to the right, y up from its feet, z toward the back).
    func seatOffset(_ m: Mob) -> V3 {
        switch m.kind {
        case .ashTank: return V3(-0.55, 1.7, 0.45)                                  // up in the commander's hatch
        case .ashHalftrack: return gunner ? V3(0, 0.75, -0.4) : V3(-0.6, 0.1, -1.4)
        case .ashArtillery: return V3(0, 0.15, 1.0)                                 // behind the breech
        default: return V3(-0.4, -0.25, -2.1)                                       // the truck's cab
        }
    }

    func enter(_ g: Game, _ m: Mob) {
        vehicle = m
        gunner = false
        jumpWas = true
        m.aggro = false
        m.persistent = true
        g.player.yaw = m.yaw
        g.player.flying = false
        g.sfx(m.kind == .ashArtillery ? .place(.stone) : .engineStart, 1, at: m.pos)
        AshSeat.entered += 1
    }

    func leave(_ g: Game) {
        guard let m = vehicle else { return }
        vehicle = nil
        drive = 0; steer = 0; sprint = false
        g.player.pos = Turrets.exitSpot(g.world, m, fwd: m.forward)
        g.player.vel = .zero
        g.player.airPeak = g.player.pos.y
    }

    // Per frame while seated: true = the vehicle has the controls this frame.
    func tick(_ g: Game, _ p: PadSnapshot, _ q: PadSnapshot, _ mi: MoveInput, dt: Float) -> Bool {
        guard let m = vehicle else { return false }
        if m.health <= 0 || !g.alive || !g.mobs.mobs.contains(where: { $0 === m }) { vehicle = nil; return false }
        if mi.sneak { leave(g); return false }
        if m.kind == .ashHalftrack && mi.jump && !jumpWas {
            gunner.toggle()
            g.sfx(.place(.stone), 0.6, at: m.pos)
        }
        jumpWas = mi.jump
        drive = gunner ? 0 : mi.forward
        steer = gunner ? 0 : mi.strafe
        sprint = mi.sprint
        fireTap = g.input.leftClicked || (p.rt > 0.5 && q.rt <= 0.5)
        fireHeld = g.input.leftDown || p.rt > 0.5
        let o = seatOffset(m)
        let right = V3(cosf(m.yaw), 0, -sinf(m.yaw)), back = V3(sinf(m.yaw), 0, cosf(m.yaw))
        g.player.pos = m.pos + right * o.x + V3(0, o.y, 0) + back * o.z
        g.player.vel = .zero
        g.player.onGround = true
        g.target = nil
        g.mining = nil
        return true
    }
}

// --ashdrive: P324 / P344's quick check. Each of the four is taken on a level yard (its crew out, the vehicle still
// itself, his at its controls): the tank, half-track and truck drive and turn, the tank's main gun, the half-track's
// rear gun (jump to its seat) and the field gun fire, and sneaking out leaves the vehicle parked. A half-track knocked
// under a third bails out and stands empty; trucks round a yard park sidecars beside some of them.
enum AshDriveCheck {
    final class Drive: AgentBot {
        let name = "ashdrive"
        var next = AgentAction()
        func act(_ s: AgentState, _ a: Agent) -> AgentAction { next }
        func goals() -> [(String, Bool, String)] { [] }
    }

    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        guard let device = MTLCreateSystemDefaultDevice() else { print("ashdrive: no Metal device"); return 2 }
        PrefsSandbox.begin()
        defer { PrefsSandbox.end() }
        let (world, game) = Agent.makeWorld(device: device, seed: 12345, botSeed: 1, rd: 6)
        World.deterministic = false
        world.ships.encounters = false
        game.difficulty = 0
        let agent = Agent(game: game, world: world)
        let (x, z) = RideCheck.land(world, near: game.player.pos, rough: false, verify: true)
        _ = world.loadSync(center: V3(Float(x), 100, Float(z)), radius: 4)
        func ground(_ x: Int, _ z: Int) -> V3 { V3(Float(x) + 0.5, world.ships.groundTop(x, z) + 1, Float(z) + 0.5) }      // (on the top block)
        // A level yard: stone, 17 wide, from 12 behind to 40 ahead (-Z), cleared above.
        let y0 = Int(world.ships.groundTop(x, z))
        for dz in -40...12 { for dx in -8...8 {
            for y in (y0 - 3)...y0 { world.setBlock(x + dx, y, z + dz, STONE) }
            for y in (y0 + 1)...(y0 + 10) where !world.isAir(x + dx, y, z + dz) { world.setBlock(x + dx, y, z + dz, AIR) }
        } }
        game.mobs.mobs.removeAll { $0.kind.hostile }
        game.player.flying = false
        var fails = 0
        func check(_ ok: Bool, _ what: String) { print("ashdrive: \(ok ? "ok  " : "FAIL") \(what)"); if !ok { fails += 1 } }
        let bot = Drive()
        func run(_ ticks: Int, _ a: AgentAction) { bot.next = a; for _ in 0..<ticks { agent.step(bot) } }
        func crew() -> Int { game.mobs.mobs.filter { $0.faction == Faction.ashguard.rawValue && !$0.kind.ashVehicle }.count }
        func act(forward: Float = 0, strafe: Float = 0, jump: Bool = false, sneak: Bool = false, attack: Bool = false) -> AgentAction {
            var a = AgentAction(); a.forward = forward; a.strafe = strafe; a.jump = jump; a.sneak = sneak; a.attack = attack; return a
        }
        // Takes one, drives it 6 s ahead and 2 s turning (unless a field gun), fires its gun, climbs out.
        for kind in [MobKind.ashTank, .ashHalftrack, .ashTruck, .ashArtillery] {
            let v = Mob(kind, at: ground(x, z + 6))
            v.ashSetup()
            v.yaw = 0
            v.persistent = true                         // (peaceful: a hostile mob that isn't would despawn)
            game.mobs.mobs.append(v)
            game.player.pos = ground(x - 5, z + 6)
            run(5, act())
            let took = game.ashCommandeer(v)
            let name = v.spec.name
            check(took && AshSeat.shared.vehicle === v && game.mobs.mobs.contains { $0 === v } && v.kind == kind && game.world.ships.pilot == nil,
                  "\(name): taken, still itself, his at its controls")
            check(crew() == AshCommandeer.crew(kind), "\(name): its crew of \(AshCommandeer.crew(kind)) climbs out (\(crew()))")
            game.mobs.mobs.removeAll { $0.faction == Faction.ashguard.rawValue && !$0.kind.ashVehicle }
            let p0 = v.pos, y0 = v.yaw
            if kind != .ashArtillery {
                run(360, act(forward: 1))
                let moved = simd_length(V2(v.pos.x - p0.x, v.pos.z - p0.z))
                check(moved > 6, String(format: "\(name): drives, %.1f blocks in 6 s (he rides %.1f from its centre)", moved, simd_length(game.player.pos - v.pos)))
                run(120, act(forward: 1, strafe: 1))
                check(abs(v.yaw - y0) > 0.5, String(format: "\(name): turns, %.0f degrees in 2 s", abs(v.yaw - y0) * 180 / .pi))
                // P461: the stick goes the way he looks. Looking a quarter round to the right and pushing ahead, the
                // hull comes round to his view and drives off that way; looking along it and pulling back, it backs up
                // instead of turning about.
                func wrap(_ a: Float) -> Float { var a = a; while a > .pi { a -= 2 * .pi }; while a < -.pi { a += 2 * .pi }; return a }
                let look = v.yaw - .pi / 2
                game.player.yaw = look
                let q0 = v.pos
                run(180, act(forward: 1))
                let along = simd_dot(V2(v.pos.x - q0.x, v.pos.z - q0.z), V2(-sinf(look), -cosf(look)))
                check(abs(wrap(v.yaw - look)) < 0.15 && along > 2, String(format: "\(name): pushed ahead looking right, it comes round to his view (%.0f degrees off) and drives that way (%.1f blocks in 3 s)",
                                                                           abs(wrap(v.yaw - look)) * 180 / .pi, along))
                run(90, act())                                  // (rolled to a stop first)
                game.player.yaw = v.yaw
                let y2 = v.yaw, q1 = v.pos
                run(120, act(forward: -1))
                let back = simd_dot(V2(v.pos.x - q1.x, v.pos.z - q1.z), V2(-sinf(y2), -cosf(y2)))
                check(back < -1 && abs(wrap(v.yaw - y2)) < 0.2, String(format: "\(name): pulled back, it reverses (%.1f blocks, turned %.0f degrees)", back, abs(wrap(v.yaw - y2)) * 180 / .pi))
                run(60, act())
            }
            if kind == .ashHalftrack {
                run(2, act(jump: true)); run(2, act())
                check(AshSeat.shared.gunner, "\(name): jump moves him to the rear gun")
            }
            if kind != .ashTruck {
                let shells = AshSeat.shots, slugs0 = game.arms.slugs.count
                run(2, act()); run(30, act(attack: true))
                let fired = kind == .ashHalftrack ? game.arms.slugs.count > slugs0 : AshSeat.shots > shells
                check(fired, "\(name): the trigger fires its gun")
            }
            run(2, act(sneak: true))
            let p1 = v.pos
            run(180, act())
            check(AshSeat.shared.vehicle == nil && v.tamed && simd_length(V2(v.pos.x - p1.x, v.pos.z - p1.z)) < 0.5, "\(name): sneak climbs out; it stands parked")
            game.mobs.mobs.removeAll { $0 === v }
        }
        // P435: the sidecar motorcycle, driven from its saddle: how fast it goes and which way it turns.
        do {
            let sc = world.ships.spawn(AshCommandeer.sidecar(), at: ground(x, z + 6) + V3(0, 3, 0), yaw: 0, name: AshCommandeer.sidecarName, role: "")
            sc.role = nil
            VehicleWorks.settle(sc, on: ground(x, z + 6))
            run(30, act())
            game.player.pos = sc.toWorld(game.helmStand(sc) ?? sc.com)
            game.takeCommand(sc)
            let p0 = sc.pos, yaw0 = sc.yaw
            run(300, act(forward: 1))
            let d = sc.pos - p0, v = simd_length(V2(sc.vel.x, sc.vel.z))
            let ahead = simd_dot(V2(d.x, d.z), V2(-sinf(yaw0), -cosf(yaw0)))
            print(String(format: "ashdrive:   sidecar: %.1f blocks in 5 s (%.1f ahead along its nose), %.1f b/s at the end, grounded %@, on the helm %@",
                         simd_length(V2(d.x, d.z)), ahead, v, sc.grounded ? "yes" : "no", game.world.ships.pilot === sc ? "yes" : "no"))
            check(ahead > 20, String(format: "sidecar: drives nose first, %.1f blocks in 5 s", ahead))
            let y1 = sc.yaw
            run(90, act(forward: 1, strafe: 1))
            var dy = sc.yaw - y1
            while dy > .pi { dy -= 2 * .pi }
            while dy < -.pi { dy += 2 * .pi }
            print(String(format: "ashdrive:   sidecar: right stick turned it %.0f degrees (a tank turning right: negative)", dy * 180 / .pi))
            check(dy < -0.1, "sidecar: steering right turns it right")
            // P461: drawn as a motorcycle and sidecar (its blocks hidden), and he gets off it onto the ground.
            let skin = AshWrecks.skinMobs.filter { $0.wreck == 6 }.min { simd_length($0.pos - sc.pos) < simd_length($1.pos - sc.pos) }
            check(sc.hidden && skin != nil && simd_length(V2(skin!.pos.x - sc.pos.x, skin!.pos.z - sc.pos.z)) < 4,
                  "sidecar: drawn as the motorcycle model over its hull (\(AshWrecks.skinMobs.count) skins, hidden \(sc.hidden))")
            run(60, act())
            run(2, act(sneak: true))
            let off = game.player.pos
            let pb = game.player
            let free = !world.collides(V3(off.x - pb.halfW + 0.02, off.y + 0.05, off.z - pb.halfW + 0.02), V3(off.x + pb.halfW - 0.02, off.y + pb.height - 0.05, off.z + pb.halfW - 0.02))
            print(String(format: "ashdrive:   sidecar: off at %.1f %.1f %.1f, %.1f from the hull's box, aboard %@", off.x, off.y, off.z,
                         world.ships.boundsDistance(sc, off), world.ships.aboard == nil ? "no" : "yes"))
            check(world.ships.pilot == nil && world.ships.aboard == nil && free && world.ships.boundsDistance(sc, off) > 0.2,
                  "sidecar: sneak gets him off onto the ground beside it, clear of the hull")
            run(60, act(forward: 1))
            check(simd_length(V2(game.player.pos.x - off.x, game.player.pos.z - off.z)) > 2,
                  String(format: "sidecar: he walks away from it (%.1f blocks in 1 s)", simd_length(V2(game.player.pos.x - off.x, game.player.pos.z - off.z))))
            world.ships.remove(sc)
        }
        // P435: the repaired fighter on a long strip: its take-off run and its speed (Oct 24 15:53: "this thing can't
        // really take off", "the planes should be extremely quick").
        if CommandLine.arguments.contains("--fighter") {
            let fx = x + 90
            let ships0 = Set(world.ships.list.map { ObjectIdentifier($0) })
            let home = game.player.pos
            _ = world.loadSync(center: V3(Float(fx), 100, Float(z - 145)), radius: 11)        // (the whole strip loaded)
            for dz in -300...10 { for dx in -12...12 {
                for y in (y0 - 2)...y0 { world.setBlock(fx + dx, y, z + dz, STONE) }
                for y in (y0 + 1)...(y0 + 14) where !world.isAir(fx + dx, y, z + dz) { world.setBlock(fx + dx, y, z + dz, AIR) }
            } }
            let fp = world.ships.spawn(AshWrecks.salvagedFighter(), at: ground(fx, z) + V3(0, 1.2, 0), yaw: 0, name: AshWrecks.fighterName, role: "capplane")
            fp.initialBlocks = fp.blockCount
            FlightModel.attach(fp)
            run(30, act())
            game.player.pos = fp.toWorld(game.helmStand(fp) ?? fp.com)
            game.takeCommand(fp)
            let g0 = fp.pos.y
            var liftAt = -1, top: Float = 0
            for t in 0..<(60 * 20) {
                let pull: Float = simd_length(fp.vel) > 20 && fp.pos.y - g0 < 12 && fp.dirToWorld(fp.fwd).y < 0.25 ? 0.6 : 0
                run(1, act(forward: 1, jump: pull > 0))
                let sp = simd_length(fp.vel)
                top = max(top, sp)
                if liftAt < 0 && fp.pos.y - g0 > 3 { liftAt = t }
                if t % 120 == 0 { print(String(format: "ashdrive:   fighter t=%4.1f s  run %5.0f  speed %5.1f b/s  height %5.1f  pitch %4.1f deg", Float(t) / 60, Float(z) - fp.pos.z, sp, fp.pos.y - g0, asinf(max(-1, min(1, fp.dirToWorld(fp.fwd).y))) * 180 / .pi)) }
            }
            print(String(format: "ashdrive:   fighter: off the ground at %@, top speed %.1f b/s (%.0f km/h), mass %.0f", liftAt < 0 ? "never" : String(format: "%.1f s", Float(liftAt) / 60), top, top * 3.6, fp.mass))
            check(liftAt > 0 && liftAt < 60 * 9, "fighter: takes off within 9 s")
            check(top > 45, String(format: "fighter: quick, %.0f b/s", top))
            let endPitch = asinf(max(-1, min(1, fp.dirToWorld(fp.fwd).y))) * 180 / .pi
            check(abs(endPitch) < 35, String(format: "fighter: stick centred, she settles toward level (%.0f degrees at the end)", endPitch))
            run(2, act(sneak: true))
            if world.ships.pilot != nil { game.leaveHelm() }
            world.ships.aboard = nil; world.frame = nil
            for sh in world.ships.list where !ships0.contains(ObjectIdentifier(sh)) { world.ships.remove(sh) }   // (and any wreckage)
            game.player.pos = home; game.player.vel = .zero; game.player.airPeak = home.y   // (back where the scenes after this one start, unhurt)
            _ = world.loadSync(center: home, radius: 4)
            run(30, act())
        }
        let ht = Mob(.ashHalftrack, at: ground(x + 30, z + 20))
        ht.ashSetup()
        ht.health = ht.spec.health / 4
        ht.persistent = true
        game.mobs.mobs.append(ht)
        let ships0 = world.ships.list.count
        run(5, act())
        check(game.mobs.mobs.contains { $0 === ht } && ht.tamed && world.ships.list.count == ships0, "a half-track knocked under a third stands empty, still a half-track")
        let side0 = AshCommandeer.sidecars
        for i in 0..<6 {
            let t = Mob(.ashTruck, at: ground(x - 30 + i * 9, z - 30))
            t.ashSetup()
            game.mobs.mobs.append(t)
        }
        run(5, act())
        for t in game.mobs.mobs where t.kind == .ashTruck {
            let h = t.soldierBrain.patrolHome
            print("ashdrive:   truck at \(Int(t.pos.x)),\(Int(t.pos.z)): looked \(t.soldierBrain.sidecarDone), picked \(h.map { hash3(Int(floor($0.x)), 7, Int(floor($0.z)), 0x51DE) % 2 == 0 } ?? false)")
        }
        check(AshCommandeer.sidecars > side0, "sidecars parked beside \(AshCommandeer.sidecars - side0) of 6 trucks (\(AshCommandeer.sidecarNoRoom) had no room)")
        print("ashdrive: \(fails == 0 ? "OK" : "\(fails) failed")")
        return fails == 0 ? 0 : 1
    }
}
