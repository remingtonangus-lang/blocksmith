import Foundation
import simd

// --flighttest [heli|player|plane|planeplayer|all|helishot|planeshot]: the real flight model (FlightModel.swift) on the Capital's
// aircraft (Aircraft.swift), flown by their autopilots through the ship physics at 60 Hz.
//  helicopter: spins up and lifts off its pad, settles into a hover (height within 0.6, drift under 1.5 blocks), flies
//              80 blocks forward nose-down, turns 90 degrees on the pedals, flies back and lands softly on the pad
//              (touchdown under 2.5 b/s, within 2.5 blocks of the centre), upright
//  plane:      level flight under power (height within 6, flying speed), climbs when asked, banks into a turn,
//              stalls when slowed nose-high and recovers by itself (nose drops, speed comes back)
enum FlightTests {
    static var failures: [String] = []
    static weak var game: Game?
    static func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        let d = detail()
        print("flighttest \(ok ? "ok  " : "FAIL") \(name)\(d.isEmpty ? "" : ": " + d)")
        if !ok { failures.append(name) }
    }
    // Telemetry every second of a phase (height, speed, attitude, controls), to tune from the CI log.
    static func trace(_ tag: String, _ s: Ship, _ t: Float) {
        guard let f = s.flight, Int(t * 60) % 60 == 0 else { return }
        let up = s.dirToWorld(V3(0, 1, 0)), fw = s.dirToWorld(s.fwd)
        let rw = s.dirToWorld(simd_normalize(simd_cross(s.fwd, V3(0, 1, 0))))
        let bank: Float = asinf(max(-1, min(1, -rw.y)))              // > 0: right wing down
        print(String(format: "flighttrace %@ t=%.0f y=%.1f v=%.1f vy=%.1f nose=%.2f up=%.2f bank=%+.2f yaw=%.2f rpm=%.2f col=%.2f cyc=%.2f,%.2f ped=%.2f T=%.0f L=%.0f a=%.2f%@",
                     tag, t, s.pos.y, simd_length(s.vel), s.vel.y, fw.y, up.y, bank, s.yaw, f.rpm, f.collective, f.cyclic.x, f.cyclic.y, f.pedal,
                     f.thrust, f.lift, f.alpha, f.stalled ? " STALL" : ""))
    }

    static func run(game g: Game, phase: String) -> Bool {
        failures = []
        game = g
        let t0 = CFAbsoluteTimeGetCurrent()
        let w = g.world
        w.ships.encounters = false
        g.paused = false; g.menu = nil
        let base = g.player.pos
        // Ground (terrain and trees) under a point; the generator's height where it isn't loaded yet.
        func groundY(_ x: Float, _ z: Float) -> Float {
            let ix = Int(floor(x)), iz = Int(floor(z))
            return Float((w.isLoaded(ix, iz) ? w.topY(ix, iz) : w.gen.column(ix, iz).height + 6) + 1)
        }
        var traced: Ship?
        var tag = ""
        var input = MoveInput()                                   // the player's keys while at a helm
        // The camera rides along above the traced aircraft and the world streams round it (a ship over unloaded
        // ground sleeps), waiting for the chunk under it when generation falls behind.
        var frames = 0
        func stream(_ s: Ship) {
            if w.ships.pilot !== s { g.player.flying = true; g.player.pos = s.pos + V3(0, 12, 0) }
            frames += 1
            if frames % 20 == 0 { w.update(center: s.pos) }
            var n = 0
            while !w.isLoaded(Int(floor(s.pos.x)), Int(floor(s.pos.z))) && n < 3000 { w.update(center: s.pos); usleep(2000); n += 1 }
        }
        func step(_ secs: Float, _ every: ((Float) -> Bool)? = nil) -> Float? {
            let dt: Float = 1.0 / 60
            var t: Float = 0
            while t < secs {
                if let s = traced { stream(s) }
                if let s = w.ships.pilot, !g.pilotTick(s, input, dt) { print("flighttest: the player left the helm") }
                w.ships.update(dt, game: g)
                FlightCrew.tick(g)
                t += dt
                if let s = traced { trace(tag, s, t) }
                if let e = every, e(t) { return t }
            }
            return nil
        }
        func upright(_ s: Ship) -> Float { s.dirToWorld(V3(0, 1, 0)).y }
        func look(_ s: Ship, from off: V3) {
            g.player.flying = true
            g.player.pos = s.pos + off
            let d = s.pos - (g.player.pos + V3(0, 1.62, 0))
            g.player.yaw = atan2f(-d.x, -d.z)
            g.player.pitch = atan2f(d.y, simd_length(V2(d.x, d.z)))
        }
        // A landing pad: a flat smooth-stone square on posts at the highest ground under it, cleared above.
        // The air above it is cleared out to `clear` (a tail boom hangs well past the skids).
        func pad(_ x: Float, _ z: Float, radius r: Int, clear: Int = 14) -> Float {
            let cx = Int(floor(x)), cz = Int(floor(z))
            var top = 0
            for dz in -r...r { for dx in -r...r { top = max(top, w.topY(cx + dx, cz + dz)) } }
            let stone = Blocks.id("smooth_stone")
            let c = max(r, clear)
            for dz in -c...c {
                for dx in -c...c {
                    let ground = w.topY(cx + dx, cz + dz)
                    guard ground >= 0 else { continue }
                    if abs(dx) <= r && abs(dz) <= r { for y in max(1, min(ground, top - 6))...top { w.setBlockAsync(cx + dx, y, cz + dz, stone) } }
                    for y in (top + 1)...(top + 16) where w.block(cx + dx, y, cz + dz) != AIR { w.setBlockAsync(cx + dx, y, cz + dz, AIR) }
                }
            }
            return Float(top + 1)
        }
        let shotOnly = phase.hasSuffix("shot")
        let name = shotOnly ? String(phase.dropLast(4)) : phase

        if name == "heli" || name == "all" {
            let gx = base.x + 10, gz = base.z - 10
            let padY = pad(gx, gz, radius: 6)
            let s = Aircraft.spawn("kestrel", at: V3(gx, padY + 3, gz), yaw: 0, game: g, troops: 2)
            traced = s; tag = "kestrel-settle"
            _ = step(2)                                           // settle on the skids
            let rest = s.pos
            check(upright(s) > 0.97, "the Kestrel stands on its skids", String(format: "upright %.2f", upright(s)))
            guard let fm = s.flight, fm.kind == .heli else { check(false, "the Kestrel has a helicopter flight model"); return finish(t0) }
            check(fm.tailRotor, "the tail rotor is recognised")
            // Hover 25 up, clear of the trees and hills round it.
            var high: Float = rest.y
            for k in 0...8 { high = max(high, groundY(rest.x + Float(k) * 0 , rest.z - Float(k) * 10) + 1) }
            let hoverAt = V3(rest.x, max(rest.y + 25, high + 18), rest.z)
            fm.hold = hoverAt; fm.holdYaw = s.yaw
            tag = "kestrel-liftoff"
            print(String(format: "flighttest: Kestrel mass %.1f t, rotor radius %.1f", s.mass, fm.rotorRadius(s)))
            let lift = step(14) { _ in s.pos.y > rest.y + 10 }
            check(lift != nil, "it spins up and lifts off", String(format: "after %.1f s, rpm %.2f", lift ?? -1, fm.rpm))
            let settled = step(30) { _ in abs(hoverAt.y - s.pos.y) < 0.4 && simd_length(s.vel) < 0.3 }
            check(settled != nil, "it settles into the hover", String(format: "after %.1f s, %.1f off", settled ?? -1, abs(hoverAt.y - s.pos.y)))
            var lo: Float = 1e9, hi: Float = -1e9, drift: Float = 0, up: Float = 1
            let p0 = s.pos
            _ = step(5) { _ in
                lo = min(lo, s.pos.y); hi = max(hi, s.pos.y)
                drift = max(drift, simd_length(V2(s.pos.x - p0.x, s.pos.z - p0.z))); up = min(up, upright(s)); return false
            }
            check(hi - lo < 0.6 && drift < 1.5 && up > 0.95, "it hovers steadily", String(format: "height span %.2f, drift %.2f, upright %.2f", hi - lo, drift, up))
            if shotOnly { look(s, from: V3(-14, 3, 10)); return finish(t0) }
            // Forward flight.
            let fwd = s.dirToWorld(s.fwd)
            var dest = s.pos + V3(fwd.x, 0, fwd.z) * 80
            var clear: Float = 0
            for k in 0...16 { let p = s.pos + V3(fwd.x, 0, fwd.z) * Float(k * 5); clear = max(clear, groundY(p.x, p.z) + 15) }
            dest.y = max(s.pos.y, clear)
            fm.hold = dest; fm.holdYaw = nil; fm.holdSpeed = 14
            tag = "kestrel-forward"
            var minPitch: Float = 0
            let arrived = step(30) { _ in
                minPitch = min(minPitch, s.dirToWorld(s.fwd).y)
                return simd_length(V2(s.pos.x - dest.x, s.pos.z - dest.z)) < 8
            }
            check(arrived != nil, "it flies 80 blocks forward", String(format: "in %.1f s", arrived ?? -1))
            check(minPitch < -0.05, "nose down to accelerate", String(format: "lowest nose %.2f", minPitch))
            // Turn on the pedals.
            let yaw0 = s.yaw
            fm.hold = s.pos; fm.holdYaw = yaw0 + .pi / 2
            tag = "kestrel-turn"
            let turned = step(10) { _ in
                var e = s.yaw - (yaw0 + .pi / 2)
                while e > Float.pi { e -= 2 * Float.pi }
                while e < -Float.pi { e += 2 * Float.pi }
                return abs(e) < 0.17
            }
            check(turned != nil, "it turns 90 degrees in a hover", String(format: "in %.1f s", turned ?? -1))
            // Back to the pad, then land on it.
            let skids = s.pos.y - s.worldMin.y
            fm.hold = V3(gx, s.pos.y, gz); fm.holdYaw = nil; fm.holdSpeed = 12
            tag = "kestrel-return"
            let over = step(40) { _ in simd_length(V2(s.pos.x - gx, s.pos.z - gz)) < 1.5 && simd_length(s.vel) < 1 }
            check(over != nil, "it flies back over its pad", String(format: "in %.1f s, %.1f blocks off", over ?? -1, simd_length(V2(s.pos.x - gx, s.pos.z - gz))))
            let pad = V3(gx, padY, gz)
            fm.hold = pad + V3(0, skids - 1, 0)          // a little under the pad: it settles onto its skids
            tag = "kestrel-land"
            var touch: Float = 99
            let down = step(30) { _ in
                if s.worldMin.y < pad.y + 0.25 && touch == 99 { touch = abs(s.vel.y) }
                return touch != 99 && abs(s.vel.y) < 0.2
            }
            check(down != nil && touch < 2.5, "it lands softly", String(format: "touchdown %.2f b/s", touch))
            let off = simd_length(V2(s.pos.x - gx, s.pos.z - gz))
            check(off < 2.5, "it lands on the pad", String(format: "%.1f blocks from the centre", off))
            fm.hold = nil
            _ = step(4)
            check(upright(s) > 0.97, "upright on the ground after landing", String(format: "%.2f", upright(s)))
            let crewOK = g.mobs.mobs.filter { $0.deck === s && $0.station == .seated }.allSatisfy { simd_length($0.pos - s.toWorld(s.crewStations[0])) < 1 }
            check(crewOK, "the pilot stays in the seat")
            look(s, from: V3(-12, 4, 12))
        }

        // The player flies a Kestrel from the helm through the real controls (pilotTick, keyboard layout): Space
        // lifts it, let go it holds the height, W tilts it forward, the view turns it, Ctrl sets it down.
        if name == "player" || name == "all" {
            let gx = base.x - 20, gz = base.z + 25
            let padY = pad(gx, gz, radius: 6)
            let s = Aircraft.spawn("kestrel", at: V3(gx, padY + 3, gz), yaw: 0, game: g, crewed: false)
            traced = s; tag = "player-settle"
            _ = step(2)
            g.startPiloting(s)
            g.player.yaw = s.yaw
            let rest = s.pos
            check(VehicleControls.kind(s) == .helicopter, "the helm flies it as a helicopter")
            input = MoveInput(); input.jump = true
            tag = "player-climb"
            let up = step(20) { _ in s.pos.y > rest.y + 25 }                 // clear of the hills round it
            check(up != nil, "Space spins it up and lifts it", String(format: "after %.1f s, %+.1f", up ?? -1, s.pos.y - rest.y))
            input = MoveInput()
            tag = "player-hold"
            _ = step(3)
            let yh = s.pos.y
            _ = step(4)
            check(abs(s.pos.y - yh) < 1.5 && abs(s.vel.y) < 0.6, "let go, it holds its height", String(format: "%+.1f in 4 s, %.1f b/s", s.pos.y - yh, s.vel.y))
            let fwd = s.dirToWorld(s.fwd), p0 = s.pos
            input.forward = 1
            tag = "player-forward"
            var nose: Float = 0
            _ = step(3) { _ in nose = min(nose, s.dirToWorld(s.fwd).y); return false }
            let along = simd_dot(s.pos - p0, fwd)
            check(along > 12 && nose < -0.05, "W tilts it forward and it flies", String(format: "%.0f blocks, nose %.2f", along, nose))
            input = MoveInput()
            _ = step(4)
            check(upright(s) > 0.95, "stick centred, it levels out", String(format: "upright %.2f", upright(s)))
            let yaw0 = s.yaw
            g.player.yaw = yaw0 + .pi / 2
            tag = "player-turn"
            let turned = step(10) { _ in
                var e = s.yaw - (yaw0 + .pi / 2)
                while e > Float.pi { e -= 2 * Float.pi }
                while e < -Float.pi { e += 2 * Float.pi }
                return abs(e) < 0.17
            }
            check(turned != nil, "it turns to the view", String(format: "in %.1f s", turned ?? -1))
            // Stick against the drift until it stops (a player brakes so), then a pad under it to set down on (the
            // hills round it are no place to land).
            tag = "player-brake"
            let stopped = step(12) { _ in
                let f = s.dirToWorld(s.fwd), r = simd_normalize(simd_cross(f, V3(0, 1, 0)))
                input.forward = max(-1, min(1, -simd_dot(s.vel, f) * 0.25))
                input.strafe = max(-1, min(1, -simd_dot(s.vel, r) * 0.25))
                return simd_length(V2(s.vel.x, s.vel.z)) < 0.6
            }
            input = MoveInput()
            check(stopped != nil, "the stick brakes it to a hover", String(format: "after %.1f s, %.1f b/s", stopped ?? -1, simd_length(s.vel)))
            _ = pad(s.pos.x, s.pos.z, radius: 7)
            tag = "player-land"
            var touch: Float = 99
            g.input.control = true
            let down = step(40) { _ in
                if s.flight!.agl < 6.2 && touch == 99 { touch = abs(s.vel.y) }
                return touch != 99 && abs(s.vel.y) < 0.2
            }
            g.input.control = false
            check(down != nil && touch < 6, "Ctrl sets it down", String(format: "touchdown %.1f b/s", touch))
            _ = step(3)
            check(upright(s) > 0.9, "upright after the player's landing", String(format: "%.2f", upright(s)))
            g.leaveHelm()
            look(s, from: V3(-12, 4, 12))
        }

        if name == "plane" || name == "all" {
            let px = base.x - 60, pz = base.z - 30
            // The whole route (1200 blocks north, the turn and the stall either side of it).
            var top: Float = 0
            for k in 0..<45 { for j in -6...6 { top = max(top, groundY(px + Float(j) * 40, pz - Float(k) * 30)) } }
            let s = Aircraft.spawn("heron", at: V3(px, min(Float(CH - 60), top + 60), pz), yaw: 0, game: g)
            guard let fm = s.flight, fm.kind == .plane else { check(false, "the Heron has a fixed-wing flight model", "wings \(s.wings.count)"); return finish(t0) }
            print(String(format: "flighttest: Heron mass %.1f t, %d airfoil cells, weight %.0f", s.mass, s.wings.count, s.mass * ShipTuning.g))
            let fwd = s.dirToWorld(s.fwd)
            s.vel = fwd * 24
            let y0 = s.pos.y
            traced = s; tag = "heron-level"
            fm.hold = s.pos + V3(fwd.x, 0, fwd.z) * 2000; fm.holdSpeed = 1
            var lo: Float = 1e9, hi: Float = -1e9, up: Float = 1
            _ = step(12) { t in
                if t > 4 { lo = min(lo, s.pos.y); hi = max(hi, s.pos.y); up = min(up, upright(s)) }
                return false
            }
            let speed = simd_length(s.vel)
            check(hi - y0 < 8 && y0 - lo < 8 && speed > 14 && speed < 45 && up > 0.8, "level flight under power",
                  String(format: "height %+.1f..%+.1f, %.1f b/s, upright %.2f, lift %.0f", lo - y0, hi - y0, speed, up, fm.lift))
            if shotOnly { look(s, from: V3(-16, 4, 14)); return finish(t0) }
            let yc = s.pos.y
            fm.hold = s.pos + V3(fwd.x, 0, fwd.z) * 2000 + V3(0, 30, 0)
            tag = "heron-climb"
            _ = step(12)
            check(s.pos.y - yc > 12, "it climbs when asked", String(format: "%+.1f in 12 s", s.pos.y - yc))
            // Turn: bank into it.
            let yawT = s.yaw
            fm.holdYaw = yawT + .pi / 2; fm.hold = s.pos + V3(0, 0, 0)
            tag = "heron-turn"
            var bank: Float = 0, low: Float = 1
            let turned = step(16) { _ in
                bank = max(bank, abs(s.dirToWorld(simd_normalize(simd_cross(s.fwd, V3(0, 1, 0)))).y))
                low = min(low, upright(s))
                var e = s.yaw - (yawT + .pi / 2)
                while e > Float.pi { e -= 2 * Float.pi }
                while e < -Float.pi { e += 2 * Float.pi }
                return abs(e) < 0.3
            }
            check(turned != nil && bank > 0.15 && bank < 0.8 && low > 0.5, "it banks into a 90 degree turn",
                  String(format: "in %.1f s, bank %.2f, upright at least %.2f", turned ?? -1, bank, low))
            // Wings level on the new heading first, then the stall: throttle off, nose held up.
            fm.holdYaw = s.yaw; fm.hold = s.pos
            tag = "heron-level-off"
            _ = step(5)
            fm.hold = nil; fm.holdYaw = nil
            s.autopilot = V3(0, 0, 1)
            tag = "heron-stall"
            var stalled = false
            _ = step(8) { _ in if fm.stalled { stalled = true }; return false }
            check(stalled, "slowed nose-high it stalls", String(format: "alpha %.2f, %.1f b/s", fm.alpha, simd_length(s.vel)))
            s.autopilot = V3(1, 0, 0)
            let rec = step(10) { _ in !fm.stalled && simd_length(s.vel) > 16 }
            check(rec != nil, "it recovers from the stall by itself", String(format: "%.1f b/s", simd_length(s.vel)))
            s.autopilot = nil
            look(s, from: V3(-16, 4, 14))
        }
        // The player flies the Heron from the helm (keyboard layout, VehicleControls .aircraft): W opens the throttle
        // (it holds), Space pulls the nose up, A banks it left into a turn; let go, the wings level out.
        if name == "planeplayer" || name == "all" {
            let px = base.x + 70, pz = base.z + 40
            var top: Float = 0
            for k in 0..<30 { for j in -6...6 { top = max(top, groundY(px + Float(j) * 40, pz - Float(k) * 30)) } }
            let s = Aircraft.spawn("heron", at: V3(px, min(Float(CH - 60), top + 60), pz), yaw: 0, game: g, crewed: false)
            s.vel = s.dirToWorld(s.fwd) * 24
            traced = s; tag = "planeplayer"
            g.startPiloting(s)
            g.player.yaw = s.yaw
            check(VehicleControls.kind(s) == .aircraft, "the helm flies it as an aircraft")
            input = MoveInput(); input.forward = 1
            _ = step(2)
            check(s.throttle > 0.9, "W opens the throttle", String(format: "throttle %.2f", s.throttle))
            input = MoveInput()
            let y0 = s.pos.y
            var low: Float = 1
            _ = step(6) { _ in low = min(low, upright(s)); return false }
            check(simd_length(s.vel) > 14 && abs(s.pos.y - y0) < 12 && low > 0.8, "hands off, it flies on level",
                  String(format: "%.1f b/s, %+.1f, upright at least %.2f, throttle %.2f", simd_length(s.vel), s.pos.y - y0, low, s.throttle))
            let yc = s.pos.y
            input.jump = true
            _ = step(4)
            input = MoveInput()
            check(s.pos.y - yc > 4, "Space pulls it up into a climb", String(format: "%+.1f in 4 s", s.pos.y - yc))
            let yaw0 = s.yaw
            var bank: Float = 0
            input.strafe = -1
            tag = "planeplayer-left"
            func turnedSince(_ y: Float) -> Float {
                var d = s.yaw - y
                while d > Float.pi { d -= 2 * Float.pi }
                while d < -Float.pi { d += 2 * Float.pi }
                return d
            }
            var at3: Float = 0
            _ = step(5) { t in
                bank = max(bank, abs(s.dirToWorld(simd_normalize(simd_cross(s.fwd, V3(0, 1, 0)))).y))
                if t < 3 { at3 = turnedSince(yaw0) }
                return false
            }
            input = MoveInput()
            let turned = turnedSince(yaw0)
            check(bank > 0.15 && turned > 0.5 && at3 > 0.2, "A banks it into a left turn",
                  String(format: "bank %.2f, turned %.2f rad (%.2f in the first 3 s)", bank, turned, at3))
            _ = step(6)
            check(upright(s) > 0.9, "let go, the wings level out", String(format: "upright %.2f", upright(s)))
            g.leaveHelm()
            look(s, from: V3(-16, 4, 14))
        }
        return finish(t0)
    }

    static func finish(_ t0: Double) -> Bool {
        if let g = game { _ = g.world.loadSync(center: g.player.pos, radius: 4) }     // the camera's ground for the shot
        game = nil
        print(String(format: "flighttest: %ld failed (%.1f s)%@", failures.count, CFAbsoluteTimeGetCurrent() - t0,
                     failures.isEmpty ? "" : " -> " + failures.joined(separator: ", ")))
        return failures.isEmpty
    }
}
