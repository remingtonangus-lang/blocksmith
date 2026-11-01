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
// P357: many small rooms off narrow corridors that turn (no long straight hall), stairs and ladders between the decks;
// the helm taken only at the helm; a careful landing does no harm, a crash tears the hull open and puts every light out;
// a shell's crater leans along the shot.
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
        // P357 (a): the longest straight open run along the main and upper decks (no big central hallway), and the ways up.
        var longest = 0
        for y in [16, 22] { for x in (ox - 7)...(ox + 7) {
            var run = 0
            for z in 58...119 {
                let open = gr.get(x, y, z) == AIR && gr.get(x, y - 1, z) == AIR
                run = open ? run + 1 : 0
                longest = max(longest, run)
            }
        } }
        var stairs = 0, ladders = 0
        for y in 15...20 { for z in 58...119 { for x in 0..<gr.sx {
            let k = key(gr.get(x, y, z))
            if k.hasSuffix("_stairs") { stairs += 1 } else if k == "ladder" { ladders += 1 }
        } } }
        check(doors >= 70 && rooms.count >= 12 && longest <= 26 && stairs >= 5 && ladders >= 10,
              "frigate P357 (a): \(doors) doors, \(rooms.count) kinds of fittings, longest straight run of corridor \(longest) blocks, a stair of \(stairs) steps and \(ladders) ladder rungs between the decks")

        // Hold it still while the checks stand in it.
        s.captured = true
        s.vel = .zero; s.angVel = .zero
        w.ships.pointHull(s, pitch: 0)
        _ = w.loadSync(center: s.pos, radius: 6)
        for _ in 0..<4 { w.ships.update(1.0 / 60, game: g) }

        // (b) A door on the main deck opens and closes from its corridor side (P357: the first one aft of z 64).
        var door = IVec3(ox - 3, 15, 66), side = IVec3(1, 0, 0)
        find: for z in 64...119 { for x in 0..<gr.sx {
            let b = gr.get(x, 15, z)
            guard key(b) == "bulkhead_door" else { continue }
            let f = Int(b - Blocks.groupBase[Int(b)]) & 3
            let o = [IVec3(0, 0, -1), IVec3(0, 0, 1), IVec3(-1, 0, 0), IVec3(1, 0, 0)][f]
            if gr.get(x + o.x, 15, z + o.z) == AIR && gr.get(x + o.x, 16, z + o.z) == AIR { door = IVec3(x, 15, z); side = o; break find }
        } }
        let d0 = gr.get(door.x, door.y, door.z), u0 = gr.get(door.x, door.y + 1, door.z)
        let mid = V3(Float(door.x) + 0.5, 16.3, Float(door.z) + 0.5), sd = V3(Float(side.x), 0, Float(side.z))
        g.player.pos = s.toWorld(V3(Float(door.x + side.x) + 0.5, 15.02, Float(door.z + side.z) + 0.5) + sd * 0.3)
        g.player.vel = .zero
        // P357 (b): standing aboard away from the helm, use takes no command.
        w.ships.aboard = s
        check(g.commandeerable() !== s, "frigate P357 (b): aboard, away from the helm, use doesn't take command (only at the helm)")
        // Use, aimed at a point of the door's cell (ship space) from the corridor.
        func use(at l: V3) {
            let look = simd_normalize(s.toWorld(l) - g.player.eye)
            g.player.yaw = atan2f(-look.x, -look.z); g.player.pitch = asinf(look.y)
            g.target = nil
            _ = g.shipInteract(breakHeld: false, breakNow: false, useNow: true, sneak: false, dt: 1.0 / 60)
        }
        use(at: mid + sd * 0.4)                                            // the closed panel on the corridor side
        let d1 = gr.get(door.x, door.y, door.z), u1 = gr.get(door.x, door.y + 1, door.z)
        let across = V3(abs(sd.z), 0, abs(sd.x))
        for k in [Float(-0.4), 0.4] where gr.get(door.x, door.y, door.z) == d1 { use(at: mid + across * k) }   // the open leaf
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
            check(g.helmFarView, "frigate P472 (\(mode)): at the helm the far ground (FarRing) shows past the loaded chunks, Auto View or not")
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
            fly(fwd, 1)                                      // (P504: at 400 km/h three seconds more reached the sky's ceiling)
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
            // P499 (Oct 30 20:27, "the frigate goes like... a thousand kilometers per hour"): high up with the sprint held
            // she runs up to about 1,000 km/h (the hull speed cap let no ship past 216 km/h before).
            s.pos.y += 110; s.prevPos = s.pos
            w.ships.pointHull(s, pitch: 0)
            var dash = fwd; dash.sprint = true
            fly(dash, 13)
            let top = simd_length(s.vel)
            fly(fwd, 4)
            let after = simd_length(s.vel)
            check(top > 250 && after < top * 0.7, String(format: "frigate P499: with the sprint held high up she dashes at %.0f km/h; let go, she sheds it (%.0f km/h 4 s later)",
                                                       top * 3.6, after * 3.6))
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

        // P357 (c): set down gently (3-4 blocks/s onto the ground under it): no harm to hull or crew.
        g.survival = true; g.player.flying = false; g.health = 20; g.alive = true
        if w.ships.pilot !== s { g.player.pos = s.toWorld(stand); g.takeCommand(s) }
        s.vel = .zero; s.angVel = .zero; s.throttle = 0
        w.ships.pointHull(s, pitch: 0)
        _ = w.loadSync(center: s.pos, radius: 6)
        var ground = -Float.greatestFiniteMagnitude
        for i in 0...4 { for j in 0...4 {
            let x = Int(floor(s.worldMin.x + (s.worldMax.x - s.worldMin.x) * Float(i) / 4)), z = Int(floor(s.worldMin.z + (s.worldMax.z - s.worldMin.z) * Float(j) / 4))
            ground = max(ground, Float(w.topY(x, z)) + 1)
        } }
        s.pos.y += ground + 0.4 - s.worldMin.y; s.prevPos = s.pos; s.updateBounds()
        let blocks0 = s.blockCount, wreck0 = s.wrecked
        s.vel = V3(0, -4, 0)
        fly(MoveInput(), 3)
        check(!s.wrecked && !wreck0 && blocks0 - s.blockCount < 10 && g.health == 20,
              "frigate P357 (c): a careful landing does no harm (\(s.wrecked ? "wrecked" : "whole"), \(blocks0 - s.blockCount) hull blocks lost, \(20 - g.health) half-hearts)")
        // P476 (Oct 27 19:11, "Maybe there has to be a VTOL mode"): 40 blocks up with no way on and the bow pitched
        // down 10 degrees, the pitch control held down: she levels, sinks straight down and settles onto the ground
        // unharmed.
        do {
            if w.ships.pilot !== s { g.player.pos = s.toWorld(stand); g.takeCommand(s) }
            s.vel = .zero; s.angVel = .zero; s.throttle = 0
            w.ships.pointHull(s, pitch: -0.17)
            if let cst = w.ships.capState[s.id] { cst.helmPitch = -0.17 }
            s.pos.y += ground + 40 - s.worldMin.y; s.prevPos = s.pos; s.updateBounds()
            let x0 = s.pos.x, z0 = s.pos.z, had = s.blockCount, crashes = Capital.crashes
            g.input.control = true
            fly(MoveInput(), 30)
            g.input.control = false
            let fwd = s.dirToWorld(V3(0, 0, -1))
            let slid = simd_length(V2(s.pos.x - x0, s.pos.z - z0)), left = s.worldMin.y - ground
            check(!s.wrecked && Capital.hovering && Capital.crashes == crashes && had - s.blockCount < 10 && left < 2 && slid < 6 && abs(fwd.y) < 0.03 && g.health == 20,
                  String(format: "frigate P476: with no way on she hovers and comes straight down onto the ground (%.1f blocks over it, slid %.1f, bow %.1f degrees, %d hull blocks lost, %d crashes, %d half-hearts)",
                         left, slid, asinf(fwd.y) * 180 / .pi, had - s.blockCount, Capital.crashes - crashes, 20 - g.health))
        }
        // P476 ("if it doesn't have enough thrust, it doesn't get off the ground"): her stern's thruster cores shot
        // away, 30 up with nothing at the helm's controls: no drive, and she settles to the ground.
        do {
            if w.ships.pilot !== s { g.player.pos = s.toWorld(stand); g.takeCommand(s) }
            let thr = Blocks.id("frigate_thruster"), cells = st.thrustCells
            for c in cells { w.ships.setBlock(s, c, AIR) }
            s.vel = .zero; s.angVel = .zero; s.throttle = 0
            w.ships.pointHull(s, pitch: 0)
            s.pos.y += ground + 30 - s.worldMin.y; s.prevPos = s.pos; s.updateBounds()
            fly(MoveInput(), 12)
            var under: Float = 0                    // (the ground right under her, not at the start spot)
            for (i, j) in [(1, 1), (0, 0), (2, 0), (0, 2), (2, 2)] {
                let x = Int(floor(s.worldMin.x + (s.worldMax.x - s.worldMin.x) * Float(i) * 0.5))
                let z = Int(floor(s.worldMin.z + (s.worldMax.z - s.worldMin.z) * Float(j) * 0.5))
                under = max(under, Float(w.topY(x, z)) + 1)
            }
            let left = s.worldMin.y - under, power = Capital.power(s, st), drive = Capital.drive(s, st)
            check(!cells.isEmpty && power < 0.05 && drive == 0 && left < 3,
                  String(format: "frigate P476: with her %d thruster cores gone she has no thrust (power %.2f, drive %.2f) and settles from 30 up to %.1f over the ground", cells.count, power, drive, left))
            for c in cells { w.ships.setBlock(s, c, thr) }
            st.thrustT = 0
        }
        s.pos = start; s.prevPos = start; s.vel = .zero
        w.ships.pointHull(s, pitch: 0)
        if w.ships.pilot !== s { g.player.pos = s.toWorld(stand); g.takeCommand(s) }

        // P472 (Oct 26 20:14, "the frigate should also break through trees and break through blocks too, to a degree"):
        // a stand of trunks and leaves from the ground up past her keel, dead ahead of the bow: under way she breaks
        // through it, no crash.
        do {
            g.survival = true; g.player.flying = false; g.health = 20; g.alive = true
            if w.ships.pilot !== s { g.player.pos = s.toWorld(stand); g.takeCommand(s) }
            let lo = s.localMin, hi = s.localMax
            let keel = lo.y + 2, cx = (lo.x + hi.x) * 0.5
            let foot = s.toWorld(V3(cx, keel, lo.z - 16))
            _ = w.loadSync(center: foot, radius: 3)
            let ground = w.topY(Int(floor(foot.x)), Int(floor(foot.z)))
            let topY = Int(floor(s.toWorld(V3(cx, keel + 6, lo.z)).y))
            var stood = 0
            for dz in 0..<3 { for dx in -3...3 {
                let c = s.toWorld(V3(cx + Float(dx), keel, lo.z - 16 - Float(dz)))
                let x = Int(floor(c.x)), z = Int(floor(c.z))
                guard ground < topY else { continue }
                for y in (ground + 1)...topY { w.setBlock(x, y, z, Blocks.id(dz == 1 && abs(dx) < 2 ? "oak_log" : "oak_leaves")); stood += 1 }
            } }
            let crushed0 = ShipManager.crushed, crashes1 = Capital.crashes
            var ahead = MoveInput(); ahead.forward = 1
            fly(ahead, 7)
            check(stood > 0 && ShipManager.crushed - crushed0 >= 20 && Capital.crashes == crashes1 && !s.wrecked && g.health == 20,
                  "frigate P472: under way she breaks through a stand of trunks and leaves dead ahead (\(ShipManager.crushed - crushed0) of \(stood) blocks broken, \(Capital.crashes - crashes1) crashes, \(20 - g.health) half-hearts)")
            s.pos = start; s.prevPos = start; s.vel = .zero; s.angVel = .zero; s.throttle = 0
            w.ships.pointHull(s, pitch: 0)
        }

        // (d) Bow down at full throttle into the ground, in survival.
        g.survival = true; g.player.flying = false; g.health = 20; g.alive = true
        if w.ships.pilot !== s { g.player.pos = s.toWorld(stand); g.takeCommand(s) }
        let crashes0 = Capital.crashes, blocks1 = s.blockCount
        var dive = MoveInput(); dive.forward = 1
        g.input.control = true
        fly(dive, 2)
        g.input.control = false
        fly(dive, 40)
        let hurt = 20 - g.health
        // P472 (Oct 26 19:48, "crashing shouldn't kill you like that"): the pilot rides it out, unhurt.
        check(s.wrecked && st.disabledWhy == "crashed" && Capital.crashes == crashes0 + 1 && w.ships.pilot == nil && g.alive && hurt == 0,
              "frigate (d): flown bow-first into the ground it is wrecked (\(s.wrecked ? st.disabledWhy : "flying"), \(frames) frames), the pilot thrown from the helm \(g.alive ? "hurt \(hurt) half-hearts" : "killed") (P472: unhurt)")
        // P357 (c), (d): the crash tore the hull open and every light aboard is out.
        var lit = 0
        let emitters = Set(["light_panel", "frigate_porthole", "frigate_thruster"].filter { Blocks.has($0) }.map { Blocks.id($0) })
        for y in 0..<gr.sy { for z in 0..<gr.sz { for x in 0..<gr.sx where emitters.contains(gr.get(x, y, z)) { lit += 1 } } }
        check(blocks1 - s.blockCount >= 300 && lit == 0 && Capital.darkened.contains(s.id),
              "frigate P357 (c, d): the crash broke \(blocks1 - s.blockCount) hull blocks away and \(lit) lights are left burning")

        // P357 (e): a crater from a shot coming down at 30 degrees heading +x leans along it.
        let gx = Int(floor(home.x)) + 40, gz = Int(floor(home.z))
        _ = w.loadSync(center: V3(Float(gx), 100, Float(gz)), radius: 3)
        let gy = w.topY(gx, gz)
        var before: [Int: BlockID] = [:]
        for y in (gy - 12)...gy { for z in (gz - 16)...(gz + 16) { for x in (gx - 16)...(gx + 16) { before[(x - gx + 16) + (z - gz + 16) * 33 + (y - gy + 12) * 1089] = w.block(x, y, z) } } }
        Explosion.crater(at: V3(Float(gx) + 0.5, Float(gy) + 1, Float(gz) + 0.5), radius: 6, game: g, depth: 6, along: V3(0.87, -0.5, 0))
        var sumX: Float = 0, cnt: Float = 0
        for y in (gy - 12)..<(gy - 2) { for z in (gz - 16)...(gz + 16) { for x in (gx - 16)...(gx + 16) {
            if let b = before[(x - gx + 16) + (z - gz + 16) * 33 + (y - gy + 12) * 1089], b != AIR, w.isAir(x, y, z) { sumX += Float(x - gx); cnt += 1 }
        } } }
        let lean = cnt > 0 ? sumX / cnt : 0
        check(cnt > 20 && lean > 1.5, String(format: "frigate P357 (e): the crater's lower part sits %.1f blocks on along the shot (%.0f blocks dug below 3 deep)", lean, cnt))

        // P499 (Oct 30 20:28, "I literally shot through a building and made a crater in the ground as if I was shooting
        // vertically downwards"): a level shot into a wall drives its bowl on into the wall, not down under the impact.
        do {
            let wx = gx - 40, wz = gz
            _ = w.loadSync(center: V3(Float(wx), 100, Float(wz)), radius: 3)
            let wy = w.topY(wx, wz) + 1
            for y in wy..<(wy + 24) { for z in (wz - 12)...(wz + 12) { for x in wx..<(wx + 14) { _ = w.setBlockAsync(x, y, z, STONE) } } }
            let iy = wy + 12
            Explosion.crater(at: V3(Float(wx) + 0.5, Float(iy) + 0.5, Float(wz) + 0.5), radius: 6, game: g, depth: 12, along: V3(1, 0, 0))
            var ahead: Float = 0, dug: Float = 0, low = 0
            for y in wy..<(wy + 24) { for z in (wz - 12)...(wz + 12) { for x in wx..<(wx + 14) where w.isAir(x, y, z) {
                ahead += Float(x - wx); dug += 1
                if y < iy - 7 { low += 1 }
            } } }
            let into = dug > 0 ? ahead / dug : 0
            // (A half bowl twelve deep along the shot and six round: its dug cells average about 4 in, ragged edge and all.)
            check(dug > 300 && into > 3.3 && low == 0,
                  String(format: "frigate P499: a level shot into a wall digs on into it (%.0f blocks, %.1f deep on average, %d below the impact's reach)", dug, into, low))
        }

        // P476 (Oct 27 19:14, "crashing it shouldn't really do that much damage. It'll damage the front. Maybe if it
        // crashed too hard, it would destroy enough blocks to disrupt the main gun"): a second frigate (the first is a
        // wreck by now), its bow pitched down and driven into the ground at 19 blocks/s: a crash that tears her where she
        // struck, and she flies on, gun and pilot still in place.
        do {
            let n1 = w.ships.list.count
            w.ships.spawnCapital("capfrigate", home: IVec3(Int(floor(home.x)) + 400, 0, Int(floor(home.z)) + 260), yaw: 0, region: nil, sync: true)
            guard let f = w.ships.list.dropFirst(n1).first(where: { $0.role == "capfrigate" }), let fs = w.ships.capState[f.id],
                  let fstand = g.helmStand(f) else { check(false, "frigate P476: a second frigate spawns"); return }
            defer { w.ships.remove(f); w.ships.capState.removeValue(forKey: f.id); w.ships.shells.removeAll { $0.owner == f.id } }
            g.survival = true; g.player.flying = false; g.health = 20; g.alive = true
            w.ships.pilot = nil; w.ships.aboard = nil
            g.player.pos = f.toWorld(fstand); g.takeCommand(f)
            f.vel = .zero; f.angVel = .zero; f.throttle = 0
            w.ships.pointHull(f, pitch: -Capital.maxPitch)
            f.updateBounds()
            // (the hull's lowest block, not its box's corner: the bow's foot, half a block over the firm ground under it)
            let bowLocal = Capital.hullProbes(f.grid).min { f.toWorld($0).y < f.toWorld($1).y } ?? V3(0, 0, 0)
            let bowPt = f.toWorld(bowLocal)
            _ = w.loadSync(center: bowPt, radius: 4)
            let gy = Float(Capital.firmTop(w, Int(floor(bowPt.x)), Int(floor(bowPt.z))) + 1)
            // (Firm stone where she strikes, open air over it: the ground generated there can be a tree's crown or a
            // trunk she crushes on the way down, and a crash into that is no test of one into the ground.)
            let bx = Int(floor(bowPt.x)), bz = Int(floor(bowPt.z)), iy = Int(gy)
            for z in (bz - 14)...(bz + 14) { for x in (bx - 14)...(bx + 14) {
                for y in (iy - 6)..<iy { w.setBlock(x, y, z, STONE) }
                for y in iy...(iy + 30) where !w.isAir(x, y, z) { w.setBlock(x, y, z, AIR) }
            } }
            f.pos.y += gy + 0.5 - bowPt.y; f.prevPos = f.pos; f.updateBounds()
            let blocks2 = f.blockCount, crashes2 = Capital.crashes
            Capital.crashLog = []
            check(!Capital.barrelTorn(f, fs), "frigate P476: a whole frigate's main gun reads as whole")
            f.vel = f.dirToWorld(V3(0, 0, -1)) * 19
            var trace: [String] = []
            for i in 0..<180 {
                guard w.ships.pilot === f else { trace.append("no pilot at \(i)"); break }
                g.player.pos = f.toWorld(fstand); g.player.vel = f.vel
                if !g.pilotTick(f, MoveInput(), dt) { trace.append("helm left at \(i)"); break }
                w.ships.update(dt, game: g)
                if i % 10 == 0 && Capital.crashes == crashes2 {
                    let b = f.toWorld(bowLocal)
                    trace.append(String(format: "%d: keel %.1f bow %.1f over %d, v %.1f %.1f %.1f", i, f.worldMin.y, b.y,
                                        Capital.firmTop(w, Int(floor(b.x)), Int(floor(b.z))) + 1, f.vel.x, f.vel.y, f.vel.z))
                }
                if f.wrecked { break }
            }
            if Capital.crashes == crashes2 { print("P476 trace: " + trace.joined(separator: "; ")) }
            print("P476 crash: " + Capital.crashLog.suffix(12).joined(separator: "; "))
            check(Capital.crashes == crashes2 + 1 && !f.wrecked && blocks2 - f.blockCount > 0 && blocks2 - f.blockCount < 300
                  && w.ships.pilot === f && fs.mainGunCD < 1e30 && g.health == 20,
                  "frigate P476: a bow-first crash at 19 b/s tears \(blocks2 - f.blockCount) hull blocks where she struck and she flies on (\(Capital.crashes - crashes2) crashes, \(f.wrecked ? "wrecked" : "whole"), pilot \(w.ships.pilot === f ? "at the helm" : "thrown"), gun \(fs.mainGunCD < 1e30 ? "intact" : "out"))")
            // P499 (Oct 30 20:36, "the capital's naval guns should be doing a number on the ship, which I don't think they
            // are"): a citadel's main battery shell fired at her in the air, striking her flank aft of the bridge, breaks
            // through her armour skin (it took nothing: not a block, not a chip).
            do {
                let aft = f.toWorld(V3(Float(f.grid.sx) * 0.5, Float(f.grid.sy) * 0.45, Float(f.grid.sz) * 0.8))
                let side = f.dirToWorld(V3(1, 0, 0))
                var sh = Slug(pos: aft + side * 60, vel: -side * AirDefence.flakSpeed, kind: .shell, damage: 0, fromPlayer: false,
                              shooter: nil, by: "Capital naval gun", life: 4, gravity: 0)
                sh.breaks = false; sh.tracer = true
                AirDefence.mainBattery(&sh)
                let had = f.blockCount, chips = f.damage.count
                let shots = g.arms.slugs.count
                g.arms.spawn(sh)
                for _ in 0..<90 where g.arms.slugs.count > shots {
                    g.player.pos = f.toWorld(fstand); g.player.vel = .zero
                    g.arms.update(dt, g)
                }
                check(had - f.blockCount >= 4 && g.alive,
                      "frigate P499: a main battery shell striking her flank in flight breaks \(had - f.blockCount) hull blocks (\(f.damage.count - chips) more chipped)")
            }
        }
    }
}

// P483 (Oct 28 17:34, on foot in survival with a Meridian frigate overhead: "the frigate's guns aren't hurting me at all
// on survival normal"; questcheck --frigatefire): a hostile frigate spawned 90 blocks off, the player standing in
// survival on Normal; for 40 s of play, what it fires, how near its rounds come and what reaches him.
extension FrigateCheck {
    static func fireOnPlayer(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, home = g.player.pos
        g.paused = false; g.survival = true; g.player.flying = false; g.health = 20; g.alive = true; g.difficulty = 2
        let n0 = w.ships.list.count
        w.ships.spawnCapital("capfrigate", home: IVec3(Int(floor(home.x)), 0, Int(floor(home.z)) + 90), yaw: 0, region: nil, sync: true)
        guard let s = w.ships.list.dropFirst(n0).first(where: { $0.role == "capfrigate" }), let st = w.ships.capState[s.id] else {
            check(false, "frigatefire: the Meridian frigate spawns"); return
        }
        var seen = Set<ObjectIdentifier>(), fired = 0, kinds: [Int: Int] = [:], nearest: Float = 1e9, low = g.health, targeted = 0
        var firstHurt: Double = -1
        var last: [ObjectIdentifier: (V3, Int)] = [:], bursts: [String] = [], track: [String] = [], tick = 0
        let t0 = g.clock
        for _ in 0..<(72 * 40) {
            g.tick(1.0 / 72)
            if st.target?.player == true { targeted += 1 }
            var live = Set<ObjectIdentifier>()
            for sh in w.ships.shells where w.ships.list.first(where: { $0.id == sh.owner })?.root === s {
                live.insert(ObjectIdentifier(sh))
                if seen.insert(ObjectIdentifier(sh)).inserted { fired += 1; kinds[sh.kind, default: 0] += 1 }
                nearest = min(nearest, simd_length(sh.pos - g.player.eye))
                last[ObjectIdentifier(sh)] = (sh.pos, sh.kind)
            }
            // A round gone since the last tick burst (or ran out) where it was last seen.
            for (k, v) in last where !live.contains(k) {
                bursts.append(String(format: "%d:%.0f", v.1, simd_length(v.0 - g.player.pos)))
                last[k] = nil
            }
            tick += 1
            if tick % 360 == 0 {
                let d = w.ships.boundsDistance(s, g.player.pos)
                let sight = w.clearShot(s.pos, g.player.eye) || w.clearShot(V3(s.pos.x, s.worldMax.y + 1, s.pos.z), g.player.eye)
                let gunSight = w.ships.turrets(of: s).contains { w.clearShot($0.toWorld($0.pivot) + V3(0, 1, 0), g.player.eye) }
                let on = st.target.map { t in t.player ? " T" : (t.mob.map { " mob \($0.kind)" } ?? (t.ship != nil ? " ship" : " fixed")) } ?? ""
                track.append(String(format: "%.0fs %.0f%@%@%@", Double(tick) / 72, d, sight ? "" : " blind", gunSight ? "" : " gunsblind", on))
            }
            if g.health < low { low = g.health; if firstHurt < 0 { firstHurt = g.clock - t0 } }
            if !g.alive { break }
        }
        print(String(format: "frigatefire: frigate %.0f blocks off (%.0f up), targeting him %d of %d ticks, %d rounds fired %@, nearest %.1f blocks, health 20 -> %d%@, first hurt at %.1f s",
                     simd_length(s.pos - home), s.pos.y - home.y, targeted, 72 * 40, fired, "\(kinds)", nearest, low, g.alive ? "" : " (killed)", firstHurt))
        print("frigatefire: every 5 s (bounds distance, T targeting him): \(track.joined(separator: ", "))")
        print("frigatefire: rounds burst (kind:blocks from him): \(bursts.joined(separator: " "))")
        check(fired > 0 && low < 20, "frigatefire: a hostile frigate's guns hurt a survival player on Normal (\(fired) rounds, health 20 -> \(low))")
        w.ships.remove(s); w.ships.capState.removeValue(forKey: s.id)
        g.health = 20; g.alive = true; g.player.pos = home
    }
}

// P476 (Oct 27, "I wanted to figure out how to repair it. I should be able to go to the helm and figure out how";
// questcheck --frigaterepair): a Meridian frigate he has taken, her barrel blown away and a hole in her side; ingots
// used at her helm put the barrel back first (the gun works again), then the side.
extension FrigateCheck {
    static func repair(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, home = g.player.pos
        let n0 = w.ships.list.count
        w.ships.spawnCapital("capfrigate", home: IVec3(Int(floor(home.x)), 0, Int(floor(home.z)) + 120), yaw: 0, region: nil, sync: true)
        guard let s = w.ships.list.dropFirst(n0).first(where: { $0.role == "capfrigate" }), let st = w.ships.capState[s.id], let helm = s.helm else {
            check(false, "frigaterepair: the Meridian frigate spawns"); return
        }
        s.captured = true
        w.ships.requestBlueprint(s, st)
        let t0 = CFAbsoluteTimeGetCurrent()
        while w.ships.hullShare(s, st) == nil && CFAbsoluteTimeGetCurrent() - t0 < 20 { usleep(20_000) }
        let drawn = CFAbsoluteTimeGetCurrent() - t0
        let whole = w.ships.hullShare(s, st) ?? 0
        // The barrel blown away just behind the muzzle, and a hole in the port side amidships.
        let md = simd_normalize(st.mainGunDir)
        let had = s.blockCount
        w.ships.blast(at: s.toWorld(st.mainGunMuzzle - md * 6), power: 12, game: nil)
        w.ships.blast(at: s.toWorld(V3(1, 14, 80)), power: 8, game: nil)
        if Capital.barrelTorn(s, st) { st.mainGunCD = .greatestFiniteMagnitude }
        let out = st.mainGunCD >= 1e30, lost = had - s.blockCount, hurt = w.ships.hullShare(s, st) ?? 0
        var ingots = 0, gunAt = -1
        var last = ""
        while ingots < 200 {
            guard let msg = w.ships.repairVehicle(s, near: helm) else { break }
            ingots += 1; last = msg
            if gunAt < 0 && st.mainGunCD < 1e30 { gunAt = ingots }
        }
        print(String(format: "frigaterepair: plans drawn in %.2f s (hull %.0f%%), blasts took %d blocks (hull %.0f%%, gun %@), %d ingots: gun back after %d, hull %.0f%%, last: %@",
                     drawn, whole * 100, lost, hurt * 100, out ? "out" : "whole", ingots, gunAt, (w.ships.hullShare(s, st) ?? 0) * 100, last))
        check(whole > 0.99 && out && gunAt > 0 && s.blockCount >= had && !Capital.barrelTorn(s, st),
              "frigaterepair: ingots at the helm put the torn barrel back first (gun working after \(gunAt) of \(ingots)) and the hull back whole (\(s.blockCount) of \(had) blocks)")
        w.ships.remove(s); w.ships.capState.removeValue(forKey: s.id)
    }
}
