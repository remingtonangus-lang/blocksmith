import Foundation
import simd

// Harness scenes for ships (main.swift):
//   --ship boat|airship|car|deck   build a demo vessel, assemble it, run it a few seconds, chase camera
//   --physicstest                  scripted checks (floating, propulsion, steering, hover, climb, driving,
//                                  riding the deck, save/load, docking); prints PASS/FAIL lines and the
//                                  snapshot shows the boat at the end. Exit status 1 when a check fails.
enum ShipTest {
    static func id(_ n: String) -> BlockID { Blocks.has(n) ? Blocks.id(n) : PLANKS }

    // Top of the water column at x, z (the highest water block), nil on land.
    static func waterTop(_ w: World, _ x: Int, _ z: Int) -> Int? {
        var y = CH - 1
        while y > 0 && w.rawBlock(x, y, z) == AIR { y -= 1 }
        return Blocks.fluidKind[Int(w.rawBlock(x, y, z))] == 1 ? y : nil
    }
    static func groundTop(_ w: World, _ x: Int, _ z: Int) -> Int {
        var y = CH - 1
        while y > 0 && !Blocks.collide[Int(w.rawBlock(x, y, z))] { y -= 1 }
        return y
    }

    // Builds a demo vessel with its lowest layer at o; returns the helm cell. Bow toward -Z.
    @discardableResult
    static func build(_ w: World, _ kind: String, at o: IVec3) -> IVec3 {
        func put(_ x: Int, _ y: Int, _ z: Int, _ n: String) { w.setBlockAsync(o.x + x, o.y + y, o.z + z, id(n)) }
        let planks = "oak_planks"
        switch kind {
        case "airship":
            for z in 0..<9 { for x in 0..<5 { put(x, 0, z, planks) } }
            for z in 0..<9 { for x in 0..<5 where x == 0 || x == 4 || z == 0 || z == 8 { put(x, 1, z, "oak_fence") } }
            for (x, z) in [(0, 0), (4, 0), (0, 8), (4, 8)] { for y in 1...3 { put(x, y, z, "oak_log") } }
            for y in 4...5 { for z in -1..<10 { for x in -1..<6 { put(x, y, z, "ship_balloon") } } }
            put(2, 1, 6, "ship_helm[south]")
            put(2, 1, 7, "ship_engine")
            put(2, 0, 9, "ship_propeller[south]")
            put(0, 0, 9, "ship_propeller[south]")
            put(4, 0, 9, "ship_propeller[south]")
            for x in [0, 4] { put(x, 0, 9 - 1, planks) }
            return IVec3(o.x + 2, o.y + 1, o.z + 6)
        case "plane":
            for z in 0..<11 { for x in 0..<3 { put(x, 0, z, planks) } }
            for x in -5...7 where x < 0 || x > 2 { for z in 4...6 { put(x, 0, z, "ship_wing") } }
            for x in -2...4 where x < 0 || x > 2 { for z in 9...10 { put(x, 0, z, "ship_wing") } }
            put(1, 1, 10, planks); put(1, 2, 10, planks)
            put(0, 0, -1, "ship_propeller[south]"); put(2, 0, -1, "ship_propeller[south]")
            put(1, 1, 1, "ship_engine")
            put(1, 1, 6, "ship_helm[south]")
            put(1, 1, 7, "glass")
            return IVec3(o.x + 1, o.y + 1, o.z + 6)
        case "car":
            for z in 0..<7 { for x in 0..<5 { put(x, 0, z, planks) } }
            for (x, z) in [(-1, 1), (5, 1), (-1, 5), (5, 5)] { put(x, 0, z, "ship_wheel") }
            put(2, 1, 4, "ship_helm[south]")
            put(2, 1, 5, "ship_engine")
            for x in [0, 4] { put(x, 1, 0, "oak_slab"); put(x, 1, 6, "oak_slab") }
            put(1, 1, 0, "glass"); put(2, 1, 0, "glass"); put(3, 1, 0, "glass")
            return IVec3(o.x + 2, o.y + 1, o.z + 4)
        case "gunboat":
            build(w, "boat", at: o)
            // A pedestal at the bow carries the ring; the turret above it touches nothing but the ring.
            put(1, 1, 1, "oak_planks")                       // (no chest)
            put(2, 1, 1, "oak_planks"); put(2, 2, 1, "oak_planks")
            put(2, 3, 1, "ship_turret_ring")
            for x in 1...3 { put(x, 4, 1, "iron_block") }
            put(2, 5, 1, "ship_cannon[south]")
            put(1, 5, 1, "ship_cannon[south]"); put(3, 5, 1, "ship_cannon[south]")
            return IVec3(o.x + 2, o.y + 1, o.z + 7)
        default:                                  // boat
            for z in 0..<11 { for x in 0..<5 { put(x, 0, z, planks) } }
            for y in 1...2 { for z in 0..<11 { for x in 0..<5 where x == 0 || x == 4 || z == 0 || z == 10 { put(x, y, z, y == 2 ? "spruce_planks" : planks) } } }
            for y in 1...5 { put(2, y, 3, "oak_log") }
            for y in 3...5 { for x in 1...3 where x != 2 { put(x, y, 3, "white_wool") } }
            put(2, 1, 7, "ship_helm[south]")
            put(2, 1, 9, "ship_engine")
            put(2, 0, 11, "ship_propeller[south]")
            put(1, 1, 1, "chest")
            return IVec3(o.x + 2, o.y + 1, o.z + 7)
        }
    }

    // Finds a place for a demo vessel near p and builds it there; returns the helm cell.
    static func place(_ w: World, _ kind: String, near p: V3) -> IVec3 {
        let x = Int(floor(p.x)) - 2, z = Int(floor(p.z)) - 5
        switch kind {
        case "airship":
            return build(w, kind, at: IVec3(x, groundTop(w, x, z) + 18, z))
        case "plane":
            return build(w, kind, at: IVec3(x, groundTop(w, x, z) + 40, z))
        case "car":
            // Level the ground under it first.
            let y = groundTop(w, x + 2, z + 3) + 1
            for dz in -48..<10 { for dx in -3..<8 {
                for yy in y..<(y + 6) { w.setBlockAsync(x + dx, yy, z + dz, AIR) }
                w.setBlockAsync(x + dx, y - 1, z + dz, GRASS)
                if !Blocks.collide[Int(w.rawBlock(x + dx, y - 2, z + dz))] { w.setBlockAsync(x + dx, y - 2, z + dz, DIRT) }
            } }
            return build(w, kind, at: IVec3(x, y, z))
        default:
            let top = waterTop(w, x + 2, z + 5) ?? (groundTop(w, x + 2, z + 5))
            return build(w, kind, at: IVec3(x, top - 1, z))
        }
    }

    // Steps the game's ships (and the player, aboard or at the helm) for `seconds` at 60 Hz.
    static func run(_ g: Game, seconds: Float, input: MoveInput = MoveInput()) {
        let dt: Float = 1.0 / 60
        for _ in 0..<Int(seconds * 60) {
            g.shipPlayerUpdate(dt, input)
            g.world.ships.update(dt, game: g)
        }
    }

    static func horiz(_ v: V3) -> Float { simd_length(V2(v.x, v.z)) }

    // Chase camera behind and above a ship.
    static func chase(_ g: Game, _ s: Ship, dist: Float, height: Float, side: Float = 0.35) {
        let f = s.dirToWorld(s.fwd)
        var fh = V3(f.x, 0, f.z)
        fh = simd_length(fh) > 0.01 ? simd_normalize(fh) : V3(0, 0, -1)
        let right = V3(-fh.z, 0, fh.x)
        let cam = s.pos - fh * dist + right * dist * side + V3(0, height, 0)
        let to = s.pos - cam
        g.player.flying = true
        g.player.pos = cam - V3(0, g.player.eyeHeight, 0)
        g.player.yaw = atan2f(-to.x, -to.z)
        g.player.pitch = atan2f(to.y, horiz(to))
        g.world.ships.aboard = nil
        g.world.ships.pilot = nil
    }

    // Remeshes the world around the camera and waits for ship meshes.
    static func settle(_ g: Game, rd: Int) {
        _ = g.world.loadSync(center: g.player.pos, radius: rd)
        for s in g.world.ships.list {
            var n = 0
            while s.mesh.busy && n < 4000 { usleep(1000); s.mesh.apply(device: g.world.device); n += 1 }
            s.mesh.apply(device: g.world.device)
        }
    }

    // --ship <kind>: a demo vessel under way. Returns the camera position.
    static func scene(_ kind: String, game g: Game, at p: V3, rd: Int) -> V3 {
        let w = g.world
        w.ships.encounters = false
        if kind == "frigate" || kind == "carriage" {
            let x = Int(floor(p.x)), z = Int(floor(p.z)) - 30
            let ground = groundTop(w, x, z)
            let s = w.ships.spawnVessel(kind, home: IVec3(x, kind == "frigate" ? max(ground, SEA) + 40 : ground + 1, z), game: g)
            run(g, seconds: kind == "frigate" ? 4 : 5)
            print(String(format: "ship %@: %ld blocks %.0f t  pos %.1f %.1f %.1f  speed %.2f b/s  turrets %ld  crew %ld  physics %.2f ms/frame",
                         kind, s.blockCount, s.mass, s.pos.x, s.pos.y, s.pos.z, simd_length(s.vel), w.ships.turrets(of: s).count,
                         s.crewStations.count, w.ships.stepMs))
            if kind == "frigate" { chase(g, s, dist: 60, height: 14, side: 0.6) } else { chase(g, s, dist: 34, height: 12, side: 0.7) }
            settle(g, rd: rd)
            return g.player.pos
        }
        let helm = place(w, kind == "deck" ? "boat" : kind, near: p)
        let (ship, msg) = w.ships.assemble(at: helm, game: g)
        print("ship \(kind): \(msg)")
        guard let s = ship else { return p }
        g.startPiloting(s)
        var mi = MoveInput()
        switch kind {
        case "airship":
            run(g, seconds: 1)
            mi.jump = true; run(g, seconds: 2, input: mi)
            mi.jump = false; mi.forward = 1; mi.strafe = 0.4; run(g, seconds: 5, input: mi)
            chase(g, s, dist: 22, height: 6)
        case "plane":
            s.vel = s.dirToWorld(s.fwd) * 18
            mi.forward = 1; run(g, seconds: 3, input: mi)
            mi.strafe = 0.6; run(g, seconds: 1.5, input: mi)
            chase(g, s, dist: 18, height: 5)
        case "car":
            run(g, seconds: 2)
            mi.forward = 1; run(g, seconds: 4, input: mi)
            mi.strafe = 1; run(g, seconds: 1.5, input: mi)
            chase(g, s, dist: 14, height: 5)
        case "deck":
            run(g, seconds: 2)
            mi.forward = 1; run(g, seconds: 3, input: mi)
            // First person at the helm, looking over the bow.
            g.player.pitch = -0.25
            g.player.yaw = s.yaw
        default:
            run(g, seconds: 2)
            mi.forward = 1; run(g, seconds: 4, input: mi)
            mi.strafe = 1; run(g, seconds: 2, input: mi)
            if kind == "gunboat" {
                // Swing the turret to port and fire a salvo; the shot shows the shells in flight.
                for t in w.ships.turrets(of: s) { t.aimYaw = .pi / 2 }
                mi.strafe = 0; run(g, seconds: 2.5, input: mi)
                w.ships.fire(s, pitch: 0.15, game: g)
                run(g, seconds: 0.25, input: mi)
            }
            chase(g, s, dist: 16, height: 6)
        }
        let v = s.vel
        print(String(format: "ship %@: %ld blocks %.1f t  pos %.1f %.1f %.1f  speed %.2f b/s  submerged %.1f  contacts %ld  physics %.2f ms/frame",
                     kind, s.blockCount, s.mass, s.pos.x, s.pos.y, s.pos.z, simd_length(v), s.submerged, s.contacts, w.ships.stepMs))
        if kind != "deck" { w.ships.pilot = nil }
        settle(g, rd: rd)
        return g.player.pos
    }

    // --physicstest: returns the number of failed checks.
    static func physicsTest(game g: Game, rd: Int) -> Int {
        let w = g.world
        var fails = 0
        func check(_ ok: Bool, _ what: String) {
            print("physicstest \(ok ? "PASS" : "FAIL"): \(what)")
            if !ok { fails += 1 }
        }
        func upright(_ s: Ship) -> Float { s.dirToWorld(V3(0, 1, 0)).y }
        let t0 = CFAbsoluteTimeGetCurrent()
        g.player.flying = false
        w.ships.encounters = false

        // 1. Boat: floats, sails, turns, carries a rider, saves and loads.
        guard let sea = Snapshot.findBiome(w.gen, "ocean") else { print("physicstest: no ocean"); return 1 }
        _ = w.loadSync(center: sea, radius: max(rd, 6))
        let helm = place(w, "boat", near: sea)
        let (boatOpt, msg) = w.ships.assemble(at: helm, game: g)
        print("physicstest boat: \(msg)")
        guard let boat = boatOpt else { check(false, "boat assembles"); return fails }
        check(boat.helm != nil && boat.props.count == 1 && boat.engines == 1, "boat has helm, propeller and engine")
        let surface = Float(waterTop(w, Int(floor(boat.pos.x)), Int(floor(boat.pos.z))) ?? SEA) + 0.875
        run(g, seconds: 5)
        let draft = surface - (boat.toWorld(V3(boat.localMin.x, boat.localMin.y, boat.localMin.z)).y)
        print(String(format: "physicstest boat: mass %.1f t, submerged %.1f, draft %.2f, vy %.3f, up %.3f", boat.mass, boat.submerged, draft, boat.vel.y, upright(boat)))
        check(abs(boat.vel.y) < 0.4 && draft > 0.1 && draft < 2.5 && upright(boat) > 0.95, "boat floats upright at rest")
        // Rider on deck while it sails.
        let deck = V3(2.5, 1, 5.5)
        g.player.pos = boat.toWorld(deck)
        g.player.vel = .zero
        boat.autopilot = V3(1, 0, 0)
        let start = boat.pos
        run(g, seconds: 10)
        let dist = horiz(boat.pos - start)
        let rider = boat.toLocal(g.player.pos)
        print(String(format: "physicstest boat: 10 s at full throttle: %.1f blocks, speed %.2f b/s, rider at %.2f %.2f %.2f (deck %.1f %.1f %.1f)",
                     dist, horiz(boat.vel), rider.x, rider.y, rider.z, deck.x, deck.y, deck.z))
        check(dist > 15, "boat sails under propeller power")
        check(w.ships.aboard === boat && simd_length(V2(rider.x - deck.x, rider.z - deck.z)) < 1.5 && abs(rider.y - deck.y) < 0.6,
              "player stays on the moving deck")
        let yaw0 = boat.yaw
        boat.autopilot = V3(1, 1, 0)
        run(g, seconds: 5)
        var dyaw = boat.yaw - yaw0
        while dyaw > .pi { dyaw -= 2 * .pi }
        while dyaw < -.pi { dyaw += 2 * .pi }
        print(String(format: "physicstest boat: turned %.0f degrees in 5 s", dyaw * 180 / .pi))
        check(dyaw < -0.5, "boat turns right under helm")
        boat.autopilot = nil
        // Save / load round trip.
        if let data = w.ships.encode() {
            let probe = ShipManager(world: w)
            let before = probe.list.count
            probe.decode(data)
            let copy = probe.list.last
            check(probe.list.count == before + 1 && copy?.blockCount == boat.blockCount && simd_length((copy?.pos ?? .zero) - boat.pos) < 0.01,
                  "ship saves and loads (\(data.count) bytes)")
        } else { check(false, "ship saves and loads") }

        // 1b. Gunboat: the turret turns on its ring and rides the hull, cannons hit a target, blasts break hulls.
        let gunAt = sea + V3(40, 0, 0)
        _ = w.loadSync(center: gunAt, radius: max(rd, 6))
        let gh = place(w, "gunboat", near: gunAt)
        let (gbOpt, gmsg) = w.ships.assemble(at: gh, game: g)
        print("physicstest gunboat: \(gmsg)")
        if let gb = gbOpt, let turret = w.ships.turrets(of: gb).first {
            check(turret.cannons.count == 3, "turret carries its cannons")
            run(g, seconds: 2)
            turret.aimYaw = .pi / 2
            run(g, seconds: 3)
            let drift = simd_length(turret.toWorld(turret.pivot) - gb.toWorld(turret.mountLocal))
            print(String(format: "physicstest gunboat: turret yaw %.2f (wanted 1.57), bearing gap %.3f", turret.turretYaw, drift))
            check(abs(turret.turretYaw - .pi / 2) < 0.05 && drift < 0.05, "turret turns on its ring and stays mounted")
            turret.aimYaw = 0
            run(g, seconds: 2.5)
            // Target wall 22 blocks ahead of the bow.
            let f = gb.dirToWorld(gb.fwd)
            let bow = turret.toWorld(turret.pivot)
            let wc = bow + f * 22
            var wall: [IVec3] = []
            for dy in 0...3 { for dx in -2...2 {
                let p = IVec3(Int(floor(wc.x + f.z * Float(dx))), Int(floor(bow.y)) - 1 + dy, Int(floor(wc.z - f.x * Float(dx))))
                w.setBlockAsync(p.x, p.y, p.z, STONE); wall.append(p)
            } }
            let fired = w.ships.fire(gb, pitch: 0.05, game: g)
            run(g, seconds: 3)
            let broken = wall.filter { w.rawBlock($0.x, $0.y, $0.z) != STONE }.count
            print("physicstest gunboat: fired \(fired) shells, \(broken) of \(wall.count) wall blocks destroyed, \(w.ships.shells.count) in flight")
            check(fired == 3 && broken > 0 && w.ships.shells.isEmpty, "cannon shells fly and explode on impact")
            let n0 = gb.blockCount
            Explosion.explode(at: gb.toWorld(V3(0.5, 1.5, 6)), power: 3, game: g)
            print("physicstest gunboat: blast removed \(n0 - gb.blockCount) hull blocks")
            check(gb.blockCount < n0, "explosions break ship blocks")
            for t in w.ships.turrets(of: gb) { w.ships.remove(t) }
            w.ships.remove(gb)
        } else { check(false, "gunboat assembles with a turret") }

        // 2. Airship: hovers, climbs, flies forward.
        let land = Snapshot.findBiome(w.gen, "plains") ?? V3(sea.x + 400, 80, sea.z)
        _ = w.loadSync(center: land, radius: max(rd, 6))
        let ah = place(w, "airship", near: land)
        let (airOpt, amsg) = w.ships.assemble(at: ah, game: g)
        print("physicstest airship: \(amsg)")
        if let air = airOpt {
            g.player.flying = true
            g.player.pos = land + V3(30, 30, 30)
            run(g, seconds: 4)
            let y0 = air.pos.y
            run(g, seconds: 4)
            print(String(format: "physicstest airship: mass %.1f t, %ld balloons, lift %.2f, drift %.2f in 4 s", air.mass, air.balloons, air.liftLevel, air.pos.y - y0))
            check(abs(air.pos.y - y0) < 1 && upright(air) > 0.97, "airship hovers")
            air.autopilot = V3(0, 0, 1)
            let y1 = air.pos.y
            run(g, seconds: 3)
            print(String(format: "physicstest airship: climbed %.1f in 3 s", air.pos.y - y1))
            check(air.pos.y - y1 > 4, "airship climbs")
            air.autopilot = V3(1, 0, 0)
            let a0 = air.pos
            run(g, seconds: 6)
            print(String(format: "physicstest airship: flew %.1f blocks in 6 s, altitude change %.2f", horiz(air.pos - a0), air.pos.y - a0.y))
            check(horiz(air.pos - a0) > 10 && abs(air.pos.y - a0.y) < 2, "airship flies level under propellers")
            air.autopilot = nil
        } else { check(false, "airship assembles") }

        // 3. Aircraft: launched level at speed, holds its altitude under power and climbs on command.
        // The plane flies north from the south edge of a wide loaded area (ships freeze over unloaded ground).
        _ = w.loadSync(center: land + V3(0, 0, -60), radius: 14)
        let ph = place(w, "plane", near: land + V3(0, 0, 60))
        let (planeOpt, pmsg) = w.ships.assemble(at: ph, game: g)
        print("physicstest plane: \(pmsg)")
        if let plane = planeOpt {
            plane.vel = plane.dirToWorld(plane.fwd) * 18
            plane.autopilot = V3(1, 0, 0)
            let p0 = plane.pos
            run(g, seconds: 6)
            print(String(format: "physicstest plane: mass %.1f t, %ld airfoils, 6 s: %.1f blocks, altitude change %.1f, speed %.1f, up %.2f",
                         plane.mass, plane.wings.count, horiz(plane.pos - p0), plane.pos.y - p0.y, simd_length(plane.vel), upright(plane)))
            check(horiz(plane.pos - p0) > 60 && plane.pos.y - p0.y > -12 && upright(plane) > 0.8, "aircraft flies under power")
            plane.autopilot = V3(1, 0, 1)
            let y1 = plane.pos.y
            run(g, seconds: 2)
            print(String(format: "physicstest plane: climb input 2 s: altitude change %.1f", plane.pos.y - y1))
            check(plane.pos.y - y1 > 2, "aircraft climbs when pulled up")
            plane.autopilot = nil
            w.ships.remove(plane)
        } else { check(false, "aircraft assembles") }

        // 4. Land vehicle: settles on its wheels, drives, docks.
        let carSpot = land + V3(-40, 0, 20)
        _ = w.loadSync(center: carSpot, radius: max(rd, 6))
        let ch = place(w, "car", near: carSpot)
        let (carOpt, cmsg) = w.ships.assemble(at: ch, game: g)
        print("physicstest car: \(cmsg)")
        if let car = carOpt {
            run(g, seconds: 3)
            print(String(format: "physicstest car: mass %.1f t, grounded %@, up %.3f, vy %.3f", car.mass, car.grounded ? "yes" : "no", upright(car), car.vel.y))
            check(car.grounded && upright(car) > 0.97 && abs(car.vel.y) < 0.3, "car rests on its wheels")
            car.autopilot = V3(1, 0, 0)
            let c0 = car.pos
            run(g, seconds: 6)
            print(String(format: "physicstest car: drove %.1f blocks in 6 s, speed %.2f, up %.3f", horiz(car.pos - c0), horiz(car.vel), upright(car)))
            check(horiz(car.pos - c0) > 10 && upright(car) > 0.95, "car drives")
            car.autopilot = nil
            run(g, seconds: 3)
            let n = car.blockCount
            _ = w.ships.disassemble(car, game: g)
            var found = 0
            let c = car.pos
            for y in Int(c.y) - 6...Int(c.y) + 6 { for z in Int(c.z) - 12...Int(c.z) + 12 { for x in Int(c.x) - 12...Int(c.x) + 12 {
                let b = w.rawBlock(x, y, z)
                if ShipParts.kinds[Int(b)] != .none || b == Blocks.id("oak_planks") || Blocks.key(Blocks.groupBase[Int(b)]) == "oak_slab" || b == GLASS { found += 1 }
            } } }
            print("physicstest car: docked \(found) of \(n) blocks back into the world")
            check(w.ships.list.allSatisfy { $0 !== car } && found >= n, "car docks back into the world")
        } else { check(false, "car assembles") }

        // 5. Vessels: the frigate holds its altitude on patrol, turrets track; the carriage drives; encounters are rare.
        let vf = land + V3(150, 0, 150)
        _ = w.loadSync(center: vf, radius: max(rd, 6))
        let fg = w.ships.spawnVessel("frigate", home: IVec3(Int(vf.x), max(groundTop(w, Int(vf.x), Int(vf.z)), SEA) + 40, Int(vf.z)), game: g)
        let fy = fg.pos.y, fp = fg.pos
        g.player.pos = vf + V3(0, 80, 0)
        for _ in 0..<6 { w.ships.crewTick(1, game: g); run(g, seconds: 1) }
        print(String(format: "physicstest frigate: %ld blocks %.0f t, %ld balloons, lift %.2f, 6 s patrol: %.1f blocks, altitude change %.2f, up %.3f",
                     fg.blockCount, fg.mass, fg.balloons, fg.liftLevel, horiz(fg.pos - fp), fg.pos.y - fy, upright(fg)))
        check(abs(fg.pos.y - fy) < 3 && upright(fg) > 0.95 && horiz(fg.pos - fp) > 5, "frigate patrols at its altitude")
        if let tur = w.ships.turrets(of: fg).first {
            let aim = fg.pos + fg.dirToWorld(V3(1, 0, 0)) * 40
            tur.aimAt = aim
            run(g, seconds: 4)
            let tf = tur.dirToWorld(V3(0, 0, -1)), d = aim - tur.toWorld(tur.pivot)
            let err = acosf(max(-1, min(1, simd_dot(simd_normalize(V2(tf.x, tf.z)), simd_normalize(V2(d.x, d.z))))))
            print(String(format: "physicstest frigate: turret aim error %.3f rad", err))
            check(err < 0.12, "frigate turret tracks a target")
        } else { check(false, "frigate has turrets") }
        let vc = land + V3(15, 0, -40)
        _ = w.loadSync(center: vc, radius: max(rd, 6))
        let cx = Int(vc.x), cz = Int(vc.z)
        let cg = w.ships.spawnVessel("carriage", home: IVec3(cx, groundTop(w, cx, cz) + 1, cz), game: g)
        run(g, seconds: 3)
        let c0 = cg.pos
        for _ in 0..<6 { w.ships.crewTick(1, game: g); run(g, seconds: 1) }
        print(String(format: "physicstest carriage: %ld blocks %.0f t, grounded %@, up %.3f, 6 s: %.1f blocks",
                     cg.blockCount, cg.mass, cg.grounded ? "yes" : "no", upright(cg), horiz(cg.pos - c0)))
        check(cg.grounded && upright(cg) > 0.95 && horiz(cg.pos - c0) > 5, "siege carriage rolls on six wheels")
        if let gt = w.ships.turrets(of: cg).first {
            check(gt.cannons.count == 3 && w.ships.fire(cg, pitch: 0.1, game: g) == 3, "siege carriage's giant gun fires")
        } else { check(false, "siege carriage has a turret") }
        var frigates = 0, carriages = 0
        for rz in -10...10 { for rx in -10...10 {
            if let e = Vessels.encounter(seed: w.seed, rx: rx, rz: rz, gen: w.gen) { if e.0 == "frigate" { frigates += 1 } else { carriages += 1 } }
        } }
        print("physicstest encounters: \(frigates) frigates, \(carriages) siege carriages in 441 regions of 2048 blocks")
        check(frigates + carriages > 0 && frigates + carriages < 110, "vessel encounters are rare")

        print(String(format: "physicstest: %ld checks failed, %.1f s, ships %ld", fails, CFAbsoluteTimeGetCurrent() - t0, w.ships.list.count))
        // Final view: the boat.
        chase(g, boat, dist: 16, height: 6)
        settle(g, rd: rd)
        return fails
    }
}
