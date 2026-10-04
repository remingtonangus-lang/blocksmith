import Foundation
import simd

// --flighttest [heli|plane|all|helishot|planeshot]: the real flight model (FlightModel.swift) on the Capital's
// aircraft (Aircraft.swift), flown by their autopilots through the ship physics at 60 Hz.
//  helicopter: spins up and lifts off the ground, hovers (height within 0.6, drift under 1.5 blocks), flies 80 blocks
//              forward nose-down, turns 90 degrees on the pedals, lands softly (touchdown under 2.5 b/s), upright
//  plane:      level flight under power (height within 6, flying speed), climbs when asked, banks into a turn,
//              stalls when slowed nose-high and recovers by itself (nose drops, speed comes back)
enum FlightTests {
    static var failures: [String] = []
    static func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        let d = detail()
        print("flighttest \(ok ? "ok  " : "FAIL") \(name)\(d.isEmpty ? "" : ": " + d)")
        if !ok { failures.append(name) }
    }

    static func run(game g: Game, phase: String) -> Bool {
        failures = []
        let t0 = CFAbsoluteTimeGetCurrent()
        let w = g.world
        w.ships.encounters = false
        g.paused = false; g.menu = nil
        let base = g.player.pos
        func groundY(_ x: Float, _ z: Float) -> Float { Float(w.topY(Int(floor(x)), Int(floor(z))) + 1) }
        func step(_ secs: Float, _ every: ((Float) -> Bool)? = nil) -> Float? {
            let dt: Float = 1.0 / 60
            var t: Float = 0
            while t < secs {
                w.ships.update(dt, game: g)
                FlightCrew.tick(g)
                t += dt
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
        let shotOnly = phase.hasSuffix("shot")
        let name = shotOnly ? String(phase.dropLast(4)) : phase

        if name == "heli" || name == "all" {
            let gx = base.x + 10, gz = base.z - 10
            let gy = groundY(gx, gz)
            let s = Aircraft.spawn("kestrel", at: V3(gx, gy + 3, gz), yaw: 0, game: g, troops: 2)
            _ = step(2)                                           // settle on the skids
            let rest = s.pos
            check(upright(s) > 0.97, "the Kestrel stands on its skids", String(format: "upright %.2f", upright(s)))
            guard let fm = s.flight, fm.kind == .heli else { check(false, "the Kestrel has a helicopter flight model"); return finish(t0) }
            check(fm.tailRotor, "the tail rotor is recognised")
            let hoverAt = rest + V3(0, 12, 0)
            fm.hold = hoverAt; fm.holdYaw = s.yaw
            let lift = step(14) { _ in s.pos.y > rest.y + 10 }
            check(lift != nil, "it spins up and lifts off", String(format: "after %.1f s, rpm %.2f", lift ?? -1, fm.rpm))
            _ = step(6)
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
            let dest = s.pos + V3(fwd.x, 0, fwd.z) * 80
            fm.hold = dest; fm.holdYaw = nil; fm.holdSpeed = 14
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
            let turned = step(10) { _ in
                var e = s.yaw - (yaw0 + .pi / 2)
                while e > Float.pi { e -= 2 * Float.pi }
                while e < -Float.pi { e += 2 * Float.pi }
                return abs(e) < 0.17
            }
            check(turned != nil, "it turns 90 degrees in a hover", String(format: "in %.1f s", turned ?? -1))
            // Land.
            let pad = V3(s.pos.x, groundY(s.pos.x, s.pos.z), s.pos.z)
            fm.hold = pad + V3(0, s.pos.y - s.worldMin.y - 0.2, 0); fm.holdYaw = nil
            var touch: Float = 99
            let down = step(30) { _ in
                if s.worldMin.y < pad.y + 0.25 && touch == 99 { touch = abs(s.vel.y) }
                return touch != 99 && abs(s.vel.y) < 0.2
            }
            check(down != nil && touch < 2.5, "it lands softly", String(format: "touchdown %.2f b/s", touch))
            fm.hold = nil
            _ = step(4)
            check(upright(s) > 0.97, "upright on the ground after landing", String(format: "%.2f", upright(s)))
            let crewOK = g.mobs.mobs.filter { $0.deck === s && $0.station == .seated }.allSatisfy { simd_length($0.pos - s.toWorld(s.crewStations[0])) < 1 }
            check(crewOK, "the pilot stays in the seat")
            look(s, from: V3(-12, 4, 12))
        }

        if name == "plane" || name == "all" {
            let px = base.x - 60, pz = base.z - 30
            var top: Float = 0
            for k in 0..<12 { top = max(top, groundY(px, pz - Float(k) * 30)) }
            let s = Aircraft.spawn("heron", at: V3(px, top + 40, pz), yaw: 0, game: g)
            guard let fm = s.flight, fm.kind == .plane else { check(false, "the Heron has a fixed-wing flight model", "wings \(s.wings.count)"); return finish(t0) }
            let fwd = s.dirToWorld(s.fwd)
            s.vel = fwd * 24
            let y0 = s.pos.y
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
            _ = step(12)
            check(s.pos.y - yc > 12, "it climbs when asked", String(format: "%+.1f in 12 s", s.pos.y - yc))
            // Turn: bank into it.
            let yawT = s.yaw
            fm.holdYaw = yawT + .pi / 2; fm.hold = s.pos + V3(0, 0, 0)
            var bank: Float = 0
            let turned = step(16) { _ in
                bank = max(bank, abs(s.dirToWorld(simd_normalize(simd_cross(s.fwd, V3(0, 1, 0)))).y))
                var e = s.yaw - (yawT + .pi / 2)
                while e > Float.pi { e -= 2 * Float.pi }
                while e < -Float.pi { e += 2 * Float.pi }
                return abs(e) < 0.3
            }
            check(turned != nil && bank > 0.15, "it banks into a 90 degree turn", String(format: "in %.1f s, bank %.2f", turned ?? -1, bank))
            // Stall: throttle off, nose held up.
            fm.hold = nil; fm.holdYaw = nil
            s.autopilot = V3(0, 0, 1)
            var stalled = false
            _ = step(8) { _ in if fm.stalled { stalled = true }; return false }
            check(stalled, "slowed nose-high it stalls", String(format: "alpha %.2f, %.1f b/s", fm.alpha, simd_length(s.vel)))
            s.autopilot = V3(1, 0, 0)
            let rec = step(10) { _ in !fm.stalled && simd_length(s.vel) > 16 }
            check(rec != nil, "it recovers from the stall by itself", String(format: "%.1f b/s", simd_length(s.vel)))
            s.autopilot = nil
            look(s, from: V3(-16, 4, 14))
        }
        return finish(t0)
    }

    static func finish(_ t0: Double) -> Bool {
        print(String(format: "flighttest: %ld failed (%.1f s)%@", failures.count, CFAbsoluteTimeGetCurrent() - t0,
                     failures.isEmpty ? "" : " -> " + failures.joined(separator: ", ")))
        return failures.isEmpty
    }
}
