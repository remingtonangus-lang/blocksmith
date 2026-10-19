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

    // The sidecar motorcycle, front toward -Z: the bike on x 0 (two wheels in line), the car on x 1-2 with its own
    // wheel on x 3 and a light machine gun.
    static func sidecar() -> Blueprint {
        let b = Blueprint()
        func wheel(_ x: Int, _ zc: Int) {
            for y in 0...2 { for z in (zc - 1)...(zc + 1) where (y - 1) * (y - 1) + (z - zc) * (z - zc) <= 1 { b.set(x, y, z, "ship_wheel") } }
        }
        wheel(0, 0); wheel(0, 5); wheel(3, 3)
        for z in 1...4 { b.set(0, 2, z, "polished_blackstone") }
        b.set(0, 3, 2, "ship_engine")
        b.set(0, 3, 4, "ship_helm[south]")
        b.set(0, 3, 0, "iron_bars")                                  // the handlebars
        b.box(1, 2, 1, 2, 1, 4, "polished_blackstone")
        b.set(1, 3, 1, "red_nether_bricks")
        b.set(2, 3, 1, "ship_cannon[south]")                         // the car's machine gun
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
            c.ashSetup()
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
        if m.kind != .ashTank, !b.sidecarDone, dist < 64, let h = b.patrolHome {
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
    var fireTap = false, fireHeld = false
    private var jumpWas = false
    static var entered = 0, shots = 0   // (counters)

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
        drive = 0; steer = 0
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
