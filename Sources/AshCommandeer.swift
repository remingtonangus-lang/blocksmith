import Foundation
import Metal
import simd

// P324 (Oct 15 18:54-19:07: "I should be able to drive the tank... core feature", "their rocket half-tracks, their
// motorcycles with the sidecar", "none of them are driving around"). The Ashguard's vehicles, taken and driven:
//   take one    use a Cinder Tank, a half-track or a truck once it is cleared (no Ashguard on foot within 20 blocks of
//               it) or knocked under a third of its health: the crew climbs out fighting (tank 3, half-track 2, truck
//               1) and the hull is his, rebuilt as a drivable vehicle on the ship system in the army's black and red
//               (wheels, engines, the helm, a turret with its gun), with him at the controls. A held hatch (Ashguard
//               still near) gives a dull knock and stays shut. The Behemoth and the field guns stay the army's.
//   knocked out a hull knocked under a third bails its crew out on its own and stands empty, to be taken.
//   rockets     half-tracks carry a four-rocket rack: from 14 blocks out they loose a salvo about every 9 s, on top
//               of the pintle MG; a taken half-track's gun fires light, quick rounds.
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

    static func takeable(_ k: MobKind) -> Bool { k == .ashTank || k == .ashHalftrack || k == .ashTruck }
    static func crew(_ k: MobKind) -> Int { k == .ashTank ? 3 : (k == .ashHalftrack ? 2 : 1) }

    // Half of the army's vehicles patrol (by where they first stood).
    static func patrols(_ m: Mob, home h: V3) -> Bool {
        takeable(m.kind) && hash3(Int(floor(h.x)), 31, Int(floor(h.z)), 0xA59) % 2 == 0
    }

    // The army's black and red: a preset vehicle's iron turned to dark plate, with a red band along the hull's top.
    static func paint(_ b: Blueprint, band: Int = 3) {
        let iron = Blocks.id("iron_block")
        let dark = Blocks.has("polished_blackstone") ? Blocks.id("polished_blackstone") : iron
        let red = Blocks.has("red_nether_bricks") ? Blocks.id("red_nether_bricks") : dark
        for (c, v) in b.cells where v == iron { b.cells[c] = c.y == band ? red : dark }
        for t in b.turrets { for (c, v) in t.bp.cells where v == iron { t.bp.cells[c] = dark } }
    }

    static func blueprint(_ k: MobKind) -> Blueprint {
        let b: Blueprint
        switch k {
        case .ashTank: b = VehiclePresets.vehicle(halfWidth: 2, length: 9, wheels: 4, engines: 2, guns: 1, tube: 4)
        case .ashHalftrack: b = VehiclePresets.vehicle(halfWidth: 2, length: 8, wheels: 3, engines: 1, guns: 2, tube: 1)
        default:
            // A truck: the hull with a load of plank crates under black tarps either side of the driver's line, no gun.
            b = VehiclePresets.vehicle(halfWidth: 2, length: 8, wheels: 3, engines: 1, guns: 0, tube: 0)
            for z in 2...5 { for x in [-1, 1] { b.set(x, 4, z, "spruce_planks"); b.set(x, 5, z, "black_wool") } }
        }
        paint(b)
        return b
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
    // Mob use (Farming.mobInteract): take an Ashguard vehicle that is cleared. True when handled.
    func ashCommandeer(_ m: Mob) -> Bool {
        guard AshCommandeer.takeable(m.kind), m.health > 0, alive, world.ships.pilot == nil else { return false }
        let beaten = Float(m.health) <= Float(m.spec.health) * AshCommandeer.bailAt
        guard beaten || !ashguardNear(m.pos, AshCommandeer.clearRange, except: m) else {
            sfx(.vaultReject, 0.6, at: m.pos + V3(0, m.height * 0.6, 0))           // the hatch is held shut
            return true
        }
        guard let s = ashTakeOver(m) else { return false }
        startPiloting(s)
        return true
    }

    func ashguardNear(_ p: V3, _ r: Float, except: Mob) -> Bool {
        mobs.mobs.contains { $0 !== except && $0.health > 0 && $0.faction == Faction.ashguard.rawValue && !$0.kind.ashVehicle
            && simd_length_squared($0.pos - p) < r * r }
    }

    // The crew climbs out (fighting) and the hull becomes a vehicle of the ship system at the mob's place and heading.
    @discardableResult
    func ashTakeOver(_ m: Mob) -> Ship? {
        guard AshCommandeer.takeable(m.kind), mobs.mobs.contains(where: { $0 === m }) else { return nil }
        let s = world.ships.spawn(AshCommandeer.blueprint(m.kind), at: m.pos + V3(0, 3, 0), yaw: m.yaw, name: m.spec.name, role: "")
        s.role = nil
        VehicleWorks.settle(s, on: m.pos)
        s.initialBlocks = s.blockCount
        if m.kind == .ashHalftrack {
            for t in world.ships.list where t.parent === s {
                t.gunPower = 1.4; t.reloadTime = 0.9; t.gunSpeed = 60; t.gunGravity = 8; t.gunScatter = 0.02
            }
        }
        ashBailOut(m)
        mobs.mobs.removeAll { $0 === m }                 // (the mob update walks a copy: safe mid-update)
        AshCommandeer.taken += 1
        sfx(.engineStart, 1, at: s.pos)
        return s
    }

    // Its crew jumps down beside it, rifles up.
    func ashBailOut(_ m: Mob) {
        let w = world
        for i in 0..<AshCommandeer.crew(m.kind) {
            let a = m.yaw + Float(i) * 2.1
            var p = m.pos + V3(cosf(a), 0, -sinf(a)) * AshCommandeer.crewOut
            let x = Int(floor(p.x)), z = Int(floor(p.z)), y = Int(floor(m.pos.y))
            if Blocks.collide[Int(w.block(x, y, z))] || Blocks.collide[Int(w.block(x, y + 1, z))] { p = m.pos + V3(0, m.height + 0.2, 0) }
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

    // Each AI tick of a living Ashguard vehicle (Mob.ashVehicleAI). True when the hull was knocked out and left empty
    // (the mob is gone).
    func ashVehicleLife(_ m: Mob, dist: Float) -> Bool {
        guard AshCommandeer.takeable(m.kind) else { return false }
        let b = m.soldierBrain
        if m.home == nil { m.home = m.pos }              // (saved with the mob: the loop stays put across loads)
        if b.patrolHome == nil { b.patrolHome = m.home }
        if Float(m.health) <= Float(m.spec.health) * AshCommandeer.bailAt {
            return ashTakeOver(m) != nil
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
                where Blocks.collide[Int(w.block(x, yy - 1, z))] && !Blocks.collide[Int(w.block(x, yy, z))] { floorY = Float(yy); break }
            if floorY == nil, abs(w.ships.groundTop(x, z) + 1 - h.y) <= 1.5 { floorY = w.ships.groundTop(x, z) + 1 }
            guard let floorY else { continue }
            let y = Int(floorY)
            var clear = true
            for dz in -3...3 { for dy in 0...2 where Blocks.collide[Int(w.block(x, y + dy, z + dz))] { clear = false } }
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

// --ashdrive: P324's quick check. A Cinder Tank on open ground with no Ashguard near is taken (its crew of 3 out, the
// player at the helm) and driven forward 8 s; a half-track knocked under a third bails out and stands empty; trucks
// round a yard park sidecars beside some of them.
enum AshDriveCheck {
    final class Drive: AgentBot {
        let name = "ashdrive"
        func act(_ s: AgentState, _ a: Agent) -> AgentAction { var x = AgentAction(); x.forward = 1; return x }
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
        // A level yard for the drive (a hull with a block of clearance hangs up on a slope's step mid-body, the Vehicle
        // Works' own Field Tank as much as any): stone, 17 wide, from 12 behind to 40 ahead (-Z), cleared above.
        let y0 = Int(world.ships.groundTop(x, z))
        for dz in -40...12 { for dx in -8...8 {
            for y in (y0 - 3)...y0 { world.setBlock(x + dx, y, z + dz, STONE) }
            for y in (y0 + 1)...(y0 + 10) where world.block(x + dx, y, z + dz) != AIR { world.setBlock(x + dx, y, z + dz, AIR) }
        } }
        game.mobs.mobs.removeAll { $0.kind.hostile }
        game.player.pos = ground(x - 12, z)
        game.player.flying = false
        var fails = 0
        func check(_ ok: Bool, _ what: String) { print("ashdrive: \(ok ? "ok  " : "FAIL") \(what)"); if !ok { fails += 1 } }

        // Reference: the Vehicle Works' own Field Tank on the same ground, driven 4 s.
        do {
            let ref = world.ships.spawn(VehicleWorks.fieldTank(), at: ground(x, z) + V3(0, 3, 0), yaw: 0, name: "Field Tank", role: "")
            ref.role = nil
            VehicleWorks.settle(ref, on: ground(x, z))
            game.startPiloting(ref)
            let p0 = ref.pos
            for _ in 0..<240 { agent.step(Drive()) }
            print(String(format: "ashdrive:   (reference Field Tank: %.1f blocks in 4 s, contacts %d, mass %.0f)", simd_length(V2(ref.pos.x - p0.x, ref.pos.z - p0.z)), ref.contacts, ref.mass))
            game.leaveHelm()
            world.ships.remove(ref)
            game.player.pos = ground(x - 12, z)
        }
        let tank = Mob(.ashTank, at: ground(x, z))
        tank.ashSetup()
        tank.yaw = 0
        game.mobs.mobs.append(tank)
        for _ in 0..<5 { agent.step(Drive()) }
        let took = game.ashCommandeer(tank)
        let crew = game.mobs.mobs.filter { $0.faction == Faction.ashguard.rawValue && !$0.kind.ashVehicle }.count
        check(took && game.world.ships.pilot != nil, "the cleared tank is taken and he is at its helm")
        check(!game.mobs.mobs.contains { $0 === tank }, "the tank mob is gone, a vehicle in its place")
        check(crew == 3, "its crew of 3 climbs out (\(crew))")
        if let s = game.world.ships.pilot {
            let p0 = s.pos
            print("ashdrive: taken: \(s.wheels.count) wheels, \(s.engines) engines, mass \(Int(s.mass))")
            for i in 0..<480 {
                agent.step(Drive())
                if i % 120 == 119 {
                    print(String(format: "ashdrive:   t %.0f s: moved %.1f, throttle %.2f, piloting %@, grounded %@, contacts %d", Float(i + 1) / 60,
                                 simd_length(V2(s.pos.x - p0.x, s.pos.z - p0.z)), s.throttle, game.world.ships.pilot === s ? "yes" : "no",
                                 s.grounded ? "yes" : "no", s.contacts))
                }
            }
            let moved = simd_length(V2(s.pos.x - p0.x, s.pos.z - p0.z))
            check(moved > 6, String(format: "it drives: %.1f blocks in 8 s", moved))
            game.leaveHelm()
        }
        let ht = Mob(.ashHalftrack, at: ground(x + 30, z + 20))
        ht.ashSetup()
        ht.health = ht.spec.health / 4
        game.mobs.mobs.append(ht)
        let before = world.ships.list.count
        for _ in 0..<5 { agent.step(Drive()) }
        check(!game.mobs.mobs.contains { $0 === ht } && world.ships.list.count > before, "a half-track knocked under a third stands empty")
        let side0 = AshCommandeer.sidecars
        for i in 0..<6 {
            let t = Mob(.ashTruck, at: ground(x - 30 + i * 9, z - 30))
            t.ashSetup()
            game.mobs.mobs.append(t)
        }
        for _ in 0..<5 { agent.step(Drive()) }
        for t in game.mobs.mobs where t.kind == .ashTruck {
            let h = t.soldierBrain.patrolHome
            print("ashdrive:   truck at \(Int(t.pos.x)),\(Int(t.pos.z)): looked \(t.soldierBrain.sidecarDone), picked \(h.map { hash3(Int(floor($0.x)), 7, Int(floor($0.z)), 0x51DE) % 2 == 0 } ?? false)")
        }
        check(AshCommandeer.sidecars > side0, "sidecars parked beside \(AshCommandeer.sidecars - side0) of 6 trucks (\(AshCommandeer.sidecarNoRoom) had no room)")
        print("ashdrive: \(fails == 0 ? "OK" : "\(fails) failed")")
        return fails == 0 ? 0 : 1
    }
}
