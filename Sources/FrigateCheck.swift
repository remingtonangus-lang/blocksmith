import Foundation
import simd

// P325's quick check (questcheck --frigatecheck, Mac --frigatecheck): the Meridian frigate rebuilt, through the helm.
//   (b) a full interior: three decks of floor, bulkhead walls and doors, rooms with their furniture, and no straight line
//       through the hull from side to side; a door opens and closes from the corridor;
//   (e) taking command opens no repairs book; the drive follows the engines left;
//   (c), (f) its first flight in survival and in creative: the throttle drives it along the bow, the pitch control tilts
//       the bow and it climbs only by flying up the slope (nothing moves it straight up or sideways), way carries on
//       after the throttle comes off, a turn carves round with little sideways drift;
//   (a) the main gun's slug leaves along the barrel, wherever the hull points, flat (no drop);
//   (d) flown into the ground the frigate is wrecked, the pilot thrown from the helm and, in survival, killed.
enum FrigateCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        guard g.dim.dim == .overworld else { check(false, "frigate: needs the overworld"); return }
        let w = g.world
        let home = g.player.pos
        let was = (g.survival, g.player.flying, g.paused, g.health)
        defer {
            w.ships.pilot = nil; w.ships.aboard = nil
            (g.survival, g.player.flying, g.paused, g.health) = was
            g.alive = true
            g.player.pos = home; g.player.vel = .zero
            _ = w.loadSync(center: home, radius: 8)
        }
        g.paused = false
        g.player.flying = true
        let n0 = w.ships.list.count
        w.ships.spawnCapital("capfrigate", home: IVec3(Int(floor(home.x)), 0, Int(floor(home.z)) + 260), yaw: 0, region: nil, sync: true)
        guard let s = w.ships.list.dropFirst(n0).first(where: { $0.role == "capfrigate" }), let st = w.ships.capState[s.id] else {
            check(false, "frigate: the Meridian frigate spawns"); return
        }
        defer { w.ships.remove(s); w.ships.capState.removeValue(forKey: s.id); w.ships.shells.removeAll { $0.owner == s.id } }
        let ox = 13                                             // grid x of the centre line (HullBuilder ox)
        let gr = s.grid

        // (b) The interior.
        func key(_ b: BlockID) -> String { Blocks.key(Blocks.groupBase[Int(b)]) }
        var doors = 0, walls = 0
        var floors = [8: 0, 14: 0, 20: 0]
        var rooms = Set<String>()
        let furniture: Set<String> = ["furnace", "smoker", "lectern", "anvil", "cartography_table", "brewing_stand", "crafting_table",
                                      "smithing_table", "chest", "barrel", "data_cabinet", "iron_bars", "smooth_stone_slab"]
        for y in 0..<gr.sy { for z in 0..<gr.sz { for x in 0..<gr.sx {
            let b = gr.get(x, y, z)
            guard b != AIR else { continue }
            let k = key(b)
            if k == "bulkhead_door" && (Int(b - Blocks.groupBase[Int(b)]) & 8) == 0 { doors += 1 }
            if k == "frigate_wall" { walls += 1 }
            if k == "frigate_deck", floors[y] != nil { floors[y]! += 1 }
            if furniture.contains(k) || k.hasSuffix("_wool") { rooms.insert(k.hasSuffix("_wool") ? "bunks" : k) }
        } } }
        // Not a shell: every straight line across the hull below the bridge, inside it (hull above and below the centre
        // line there), meets something solid (the old frigate's open hangar ran clear through from side to side).
        var through = 0, lines = 0
        for y in 3...24 { for z in 0..<gr.sz {
            guard (0..<y).contains(where: { gr.get(ox, $0, z) != AIR }), ((y + 1)..<gr.sy).contains(where: { gr.get(ox, $0, z) != AIR }) else { continue }
            lines += 1
            if !(0..<gr.sx).contains(where: { Blocks.opaque[Int(gr.get($0, y, z))] }) { through += 1 }
        } }
        check(doors >= 40 && walls >= 1500 && floors.values.allSatisfy { $0 >= 400 } && rooms.count >= 10,
              "frigate (b): \(doors) bulkhead doors, \(walls) bulkhead panels, deck floors \(floors[8]!)/\(floors[14]!)/\(floors[20]!) blocks (gun, main, upper), \(rooms.count) kinds of fittings (\(rooms.sorted().joined(separator: ", ")))")
        check(lines >= 1000 && through == 0, "frigate (b): not a shell: of \(lines) lines straight across the hull, \(through) see through from side to side")

        // Hold it still while the checks stand in it.
        s.captured = true
        s.vel = .zero; s.angVel = .zero
        w.ships.pointHull(s, pitch: 0)
        _ = w.loadSync(center: s.pos, radius: 6)
        for _ in 0..<4 { w.ships.update(1.0 / 60, game: g) }

        // (b) A corridor door on the main deck opens and closes (the port side of the corridor at z 66).
        let door = IVec3(ox - 3, 15, 66)
        let d0 = gr.get(door.x, door.y, door.z), u0 = gr.get(door.x, door.y + 1, door.z)
        g.player.pos = s.toWorld(V3(Float(ox) + 0.5, 15.02, 66.5))
        g.player.vel = .zero
        // Use, aimed at a point of the door's cell (ship space) from the corridor.
        func use(at l: V3) {
            let look = simd_normalize(s.toWorld(l) - g.player.eye)
            g.player.yaw = atan2f(-look.x, -look.z); g.player.pitch = asinf(look.y)
            g.target = nil
            _ = g.shipInteract(breakHeld: false, breakNow: false, useNow: true, sneak: false, dt: 1.0 / 60)
        }
        use(at: V3(Float(door.x) + 0.9, 16.3, 66.5))                     // the closed panel on the corridor side
        let d1 = gr.get(door.x, door.y, door.z), u1 = gr.get(door.x, door.y + 1, door.z)
        for dz in [Float(0.1), 0.9] where gr.get(door.x, door.y, door.z) == d1 { use(at: V3(Float(door.x) + 0.5, 16.3, 66 + dz)) }   // the open leaf
        let d2 = gr.get(door.x, door.y, door.z)
        let db = Blocks.groupBase[Int(d0)]
        func ds(_ b: BlockID) -> Int { Blocks.groupBase[Int(b)] == db ? Int(b - db) : -1 }
        check(key(d0) == "bulkhead_door" && ds(d1) == ds(d0) ^ 4 && ds(u0) >= 8 && ds(u1) == ds(u0) ^ 4 && d2 == d0,
              "frigate (b): the corridor door opens from the corridor (both halves) and closes again (\(Blocks.key(d0)) -> \(Blocks.key(d1)) -> \(Blocks.key(d2)), upper \(Blocks.key(u0)) -> \(Blocks.key(u1)))")

        // (e) The helm: command taken, no repairs book; the drive.
        guard let stand = g.helmStand(s) else { check(false, "frigate: has a helm"); return }
        let drive0 = Capital.drive(s, st)
        let e0 = s.engines
        s.engines = st.engines0 * 3 / 10
        let dry = Capital.drive(s, st)
        s.engines = e0
        check(Wrecks.guide(s) == nil && drive0 > 0.99 && dry == 0 && VehicleControls.kind(s) == .warship,
              "frigate (e): no repairs book for its helm; drive \(Int(drive0 * 100))% with every engine, 0 with 30% of them (the panel reads Engines out)")

        let dt: Float = 1.0 / 60
        var frames = 0
        let start = s.pos
        // One frame at the helm: the pilot's controls, the hull's tick, the pilot carried at the helm (the ride itself
        // is RideCheck's), the ground loaded round the bow every half second.
        func fly(_ input: MoveInput, _ secs: Float) {
            for _ in 0..<Int(secs * 60) {
                guard w.ships.pilot === s else { return }
                g.player.pos = s.toWorld(stand); g.player.vel = s.vel
                if !g.pilotTick(s, input, dt) { return }
                w.ships.update(dt, game: g)
                if w.ships.pilot === s { g.player.pos = s.toWorld(stand) }
                frames += 1
                if frames % 30 == 0 { _ = w.loadSync(center: s.toWorld(V3(Float(ox) + 0.5, 4, 0)), radius: 5) }
                if s.wrecked { return }
            }
        }
        func bow() -> V3 { s.dirToWorld(V3(0, 0, -1)) }

        for survival in [true, false] {
            let mode = survival ? "survival" : "creative"
            g.survival = survival
            g.player.flying = !survival
            g.health = 20; g.alive = true
            s.vel = .zero; s.angVel = .zero; s.throttle = 0
            s.pos = start; s.prevPos = start                    // (from where it spawned each time: the last run climbed)
            w.ships.pointHull(s, pitch: 0)
            g.player.pos = s.toWorld(stand); g.player.vel = .zero
            Wrecks.guided.remove(s.id)
            g.takeCommand(s)
            Wrecks.hintTick(g)
            check(w.ships.pilot === s && g.menu == nil, "frigate (f) \(mode): use at the helm takes command and no menu opens (\(g.menu.map { String(describing: type(of: $0)) } ?? "none"))")
            guard w.ships.pilot === s else { continue }
            // Throttle up, level: along the bow, nothing up, down or sideways.
            let p0 = s.pos, f0 = bow()
            var fwd = MoveInput(); fwd.forward = 1
            fly(fwd, 8)
            let moved = s.pos - p0
            let along = simd_dot(moved, f0), off = simd_length(moved - f0 * along)
            check(along > 60 && off < 3, String(format: "frigate (c) %@: full throttle level for 8 s drives it %.0f blocks along the bow, %.1f off it (%.0f km/h)",
                                                 mode, along, off, simd_length(s.vel) * 3.6))
            // Pitch up for 2 s (the jump / RB control), then hold: the bow rises and it climbs along it.
            var up = fwd; up.jump = true
            let y0 = s.pos.y
            fly(up, 2)
            fly(fwd, 3)
            let b = bow()
            let pitchDeg = asinf(b.y) * 180 / .pi
            let velAlong = simd_dot(simd_normalize(s.vel + V3(0, 1e-6, 0)), b)
            check(pitchDeg > 18 && s.pos.y - y0 > 10 && velAlong > 0.97,
                  String(format: "frigate (c) %@: the pitch control raises the bow %.0f degrees and it climbs %.0f blocks flying along it (velocity on the bow %.3f)",
                         mode, pitchDeg, s.pos.y - y0, velAlong))
            // Level again, then the throttle off: way carries on.
            var down = fwd; down.jump = false
            g.input.control = true
            fly(down, Float(st.helmPitch / 0.32))
            g.input.control = false
            let v0 = simd_length(s.vel)
            s.throttle = 0
            fly(MoveInput(), 1)
            let v1 = simd_length(s.vel)
            check(abs(st.helmPitch) < 0.05 && v1 > v0 * 0.6 && v1 < v0, String(format: "frigate (c) %@: levelled off (pitch %.1f degrees), throttle off: way carries on (%.0f -> %.0f km/h in 1 s)",
                                                                     mode, st.helmPitch * 180 / .pi, v0 * 3.6, v1 * 3.6))
            if !survival { continue }
            // A hard turn at full speed: it carves round, banked, with little sideways drift.
            var turn = fwd; turn.strafe = 1
            fly(fwd, 3)
            let yaw0 = s.yaw
            fly(turn, 4)
            let right = simd_normalize(simd_cross(bow(), V3(0, 1, 0)))
            let slip = abs(simd_dot(s.vel, right)) / max(1, simd_length(s.vel))
            var turned = s.yaw - yaw0
            while turned > .pi { turned -= 2 * .pi }
            while turned < -.pi { turned += 2 * .pi }
            let bank = asinf(s.dirToWorld(V3(1, 0, 0)).y) * 180 / .pi
            check(turned < -0.4 && slip < 0.3 && bank < -8, String(format: "frigate (c): steering right turns it %.0f degrees in 4 s, banked %.0f degrees, slipping sideways at %.0f%% of its speed",
                                                                -turned * 180 / .pi, -bank, slip * 100))
        }

        // (a) The main gun: the hull pointed 12 degrees down and to the side, the slug leaves along the barrel, flat.
        s.vel = .zero; s.angVel = .zero; s.throttle = 0
        w.ships.pointHull(s, pitch: -0.21)
        st.mainGunCD = 0
        let shells0 = w.ships.shells.count
        let started = w.ships.playerMainGun(s, game: g)
        var n = 0
        while w.ships.shells.count == shells0 && n < 400 { fly(MoveInput(), 1.0 / 60); n += 1 }
        let md = s.dirToWorld(st.mainGunDir)
        if started, let sh = w.ships.shells.dropFirst(shells0).first(where: { $0.kind == 3 }) {
            let dir = simd_normalize(sh.vel - s.vel)
            check(simd_dot(dir, md) > 0.9995 && sh.gravity == 0 && abs(simd_length(sh.vel - s.vel) - MainGun.slugSpeed) < 15,   // (the hull recoils)
                  String(format: "frigate (a): the slug leaves along the barrel (%.2f degrees off, the hull %.0f degrees down) at %.0f blocks/s with no drop",
                         acosf(min(1, simd_dot(dir, md))) * 180 / .pi, -asinf(md.y) * 180 / .pi, simd_length(sh.vel - s.vel)))
        } else { check(false, "frigate (a): the helm fires the main gun (started \(started))") }
        w.ships.shells.removeAll { $0.owner == s.id }

        // (d) Bow down at full throttle into the ground, in survival.
        g.survival = true; g.player.flying = false; g.health = 20; g.alive = true
        if w.ships.pilot !== s { g.player.pos = s.toWorld(stand); g.takeCommand(s) }
        let crashes0 = Capital.crashes
        var dive = MoveInput(); dive.forward = 1
        g.input.control = true
        fly(dive, 2)
        g.input.control = false
        fly(dive, 40)
        let hurt = 20 - g.health
        check(s.wrecked && st.disabledWhy == "crashed" && Capital.crashes == crashes0 + 1 && w.ships.pilot == nil && (!g.alive || hurt >= 10),
              "frigate (d): flown bow-first into the ground it is wrecked (\(s.wrecked ? st.disabledWhy : "flying"), \(frames) frames), the pilot thrown from the helm and \(g.alive ? "hurt \(hurt) half-hearts" : "killed")")
    }
}
