import Foundation
import simd

// A real flight model for aircraft and helicopters on the ship physics (Future ideas #8), for ships with rotor
// blocks (helicopters) or the "capplane" role (the Capital's fixed-wing aircraft). Older wing-and-propeller builds
// keep their arcade model (ShipPhysics: wing plates, held attitude).
//
// Fixed wing: every airfoil cell is a lifting surface. Lift = Ka * q * CL(alpha), drag = Ka * q * (CD0 + k CL^2),
// q = |v|^2 in the fwd/up plane of the cell (its own velocity, so rotation damps itself), CL linear to the stall
// (alpha 0.3) then falling away. Pilot controls deflect the effective alpha: elevator = tail cells (climb input),
// ailerons = outer wing cells, differential (steer input). A virtual fin over the tail turns the nose into the
// airflow (weathervane) and carries the rudder; a little dihedral levels the wings when the stick is centred.
// Thrust from the propellers as before (ShipPhysics).
//
// Helicopter: the rotor's thrust = collective * Tmax * rpm^2, increased in ground effect and with translational lift,
// along the disk normal that the cyclic tilts, applied at the rotor hub (above the centre of mass, so the tilt
// pitches and rolls the hull as it does a real helicopter) plus a hub moment; the rotor's reaction torque yaws the
// hull unless a tail rotor (a sideways propeller) cancels it, and the pedals trim it. A stability augmentation
// (rate damping, attitude hold with the stick centred) makes it flyable with a controller.
final class FlightModel {
    enum Kind { case plane, heli }
    let kind: Kind
    // Pilot / autopilot controls.
    var collective: Float = 0          // heli: 0...1
    var cyclic = V2(0, 0)              // heli: x roll right, y pitch forward (-1...1)
    var pedal: Float = 0               // heli: > 0 yaws left (toward a growing yaw), < 0 right
    // Rotor state.
    var rpm: Float = 0                 // 0...1 of flight speed
    var spin: Float = 0                // rotor angle (rendering)
    var tailRotor = false
    var groundEffect: Float = 1
    // Autopilot: hold a position (helicopter hover / fly to) or a heading and altitude (plane); nil = pilot inputs.
    var hold: V3?
    var holdYaw: Float?
    var holdSpeed: Float = 10
    // Telemetry (HUD and tests).
    var thrust: Float = 0, lift: Float = 0, alpha: Float = 0, stalled = false

    init(_ k: Kind) { kind = k }

    static let rho: Float = 0.055       // Ka per airfoil cell: 0.5 * air density * area (blocks, tonnes, seconds)
    static let heliTmax: Float = 2.1    // rotor thrust at full collective, in hull weights

    // Which model a ship gets (nil: the arcade one).
    static func attach(_ s: Ship) {
        if !s.rotors.isEmpty {
            if s.flight?.kind != .heli { s.flight = FlightModel(.heli) }
        } else if s.role == "capplane" && s.wings.count >= 4 {
            if s.flight?.kind != .plane { s.flight = FlightModel(.plane) }
        } else if s.flight != nil {
            s.flight = nil
        }
        if let f = s.flight, f.kind == .heli { f.tailRotor = s.props.contains { abs($0.1.x) > 0.5 && abs($0.1.z) < 0.5 || abs(simd_dot($0.1, simd_cross(s.fwd, V3(0, 1, 0)))) > 0.7 } }
    }

    // MARK: Forces (one physics substep)

    // Adds this model's forces and torques. `power`: engine drive 0...1.
    func forces(_ s: Ship, _ h: Float, _ F: inout V3, _ T: inout V3, power: Float, ground: Float, g: Float) {
        if hold != nil { autopilot(s, g: g, ground: ground) }
        else if !s.piloted { collective = 0; cyclic = V2(0, 0); pedal = 0 }        // nobody at the controls
        switch kind {
        case .plane: planeForces(s, &F, &T)
        case .heli: heliForces(s, h, &F, &T, power: power, ground: ground, g: g)
        }
    }

    private func planeForces(_ s: Ship, _ F: inout V3, _ T: inout V3) {
        let fwdL = s.fwd, upL = V3(0, 1, 0)
        let rightL = simd_normalize(simd_cross(fwdL, upL))
        let com = s.com
        // Span and tail extents from the airfoil cells (ship space).
        var span: Float = 0, aft: Float = -1e9
        for p in s.wings { span = max(span, abs(simd_dot(p - com, rightL))); aft = max(aft, -simd_dot(p - com, fwdL)) }
        let climb = s.piloted ? s.climb : 0, steer = s.piloted ? s.steer : 0
        var totalLift: Float = 0, aSum: Float = 0, stallN = 0
        func apply(_ f: V3, at w: V3) { F += f; T += simd_cross(w - s.pos, f) }
        for p in s.wings {
            let rel = p - com
            let along = simd_dot(rel, fwdL), side = simd_dot(rel, rightL)
            let wp = s.toWorld(p)
            let vl = s.dirToLocal(s.velocity(at: wp))
            let u = simd_dot(vl, fwdL), w = simd_dot(vl, upL)
            let q = u * u + w * w
            guard q > 0.04 else { continue }
            var a = atan2f(-w, max(0.1, u))
            // Controls: tail cells are the elevator, outer wing cells the ailerons (right roll: right aileron up).
            // The tailplane is set at a negative incidence (it holds the tail down: pitch stability) and its elevator
            // pushes the tail down to raise the nose.
            if along < -aft * 0.6 && aft > 2 { a += -0.03 - climb * 0.24 }
            else {
                a += 0.05                                        // wing incidence
                if abs(side) > span * 0.55 { a += (side > 0 ? -1 : 1) * steer * 0.16 }
            }
            let aa = abs(a)
            var cl: Float = 4.6 * a
            if aa > 0.3 { cl = (a > 0 ? 1 : -1) * max(0.35, 1.38 - (aa - 0.3) * 2.6); stallN += 1 }
            let cd: Float = 0.035 + 0.06 * cl * cl
            let sq = sqrtf(q)
            let vdir: V3 = (fwdL * u + upL * w) / sq
            let ldir: V3 = (upL * u - fwdL * w) / sq
            let liftF: Float = FlightModel.rho * q * cl, dragF: Float = FlightModel.rho * q * cd
            let fl = s.dirToWorld(ldir * liftF - vdir * dragF)
            apply(fl, at: wp)
            totalLift += FlightModel.rho * q * cl
            aSum += a
        }
        lift = totalLift
        alpha = s.wings.isEmpty ? 0 : aSum / Float(s.wings.count)
        stalled = stallN * 3 > s.wings.count
        // Virtual fin over the tail: weathervane and rudder (steer adds a little rudder for coordinated turns).
        let tail = s.toWorld(com - fwdL * max(2, aft) + upL * 1.5)
        let vt = s.velocity(at: tail)
        let rightW = s.dirToWorld(rightL)
        let sv = simd_dot(vt, rightW), sp = simd_length(vt)
        let fin = Float(s.wings.count) * 0.06
        let vane: Float = -FlightModel.rho * fin * sp * sv * 2
        let rudder: Float = FlightModel.rho * fin * sp * sp * steer * 0.08
        apply(rightW * (vane + rudder), at: tail)
        // Dihedral: wings level out by themselves with the stick centred.
        if abs(steer) < 0.1 {
            let up = s.dirToWorld(upL), fw = s.dirToWorld(fwdL)
            let err = simd_cross(up, V3(0, 1, 0))
            T += fw * (simd_dot(err, fw) * s.inertiaDiag.z * 0.8 * min(1, sp / 15))
        }
    }

    private func heliForces(_ s: Ship, _ h: Float, _ F: inout V3, _ T: inout V3, power: Float, ground: Float, g: Float) {
        // The rotor spins up over a few seconds while an engine drives it.
        let want: Float = power > 0 && (s.piloted || hold != nil) ? 1 : 0
        rpm += (want - rpm) * min(1, h * (want > rpm ? 0.45 : 0.15))
        spin = fmodf(spin + rpm * 28 * h, 2 * .pi)
        guard let hubL = s.rotors.first else { return }
        // The mast stands over the centre of mass (as a helicopter is built): thrust there doesn't pitch the hull.
        let hub = s.toWorld(V3(s.com.x, hubL.y + 0.5, s.com.z))
        let up = s.dirToWorld(V3(0, 1, 0)), fw = s.dirToWorld(s.fwd)
        let right = simd_normalize(simd_cross(fw, up))
        let I = s.inertiaDiag
        // Ground effect within a rotor diameter of the ground, translational lift with forward speed.
        let radius = rotorRadius(s)
        let hAbove = max(0, hub.y - ground)
        groundEffect = 1 + 0.22 * max(0, 1 - hAbove / (radius * 2))
        let vh = simd_length(V2(s.vel.x, s.vel.z))
        let etl = 1 + 0.12 * min(1, vh / 12)
        let c: Float = max(0, min(1, collective))
        let weight: Float = s.mass * g
        let spool: Float = rpm * rpm * groundEffect * etl
        thrust = c * FlightModel.heliTmax * weight * spool
        let cx: Float = max(-1, min(1, cyclic.x)), cy: Float = max(-1, min(1, cyclic.y))
        let cyc = V2(cx, cy)
        let tiltF: V3 = fw * (cy * 0.14)
        let tiltR: V3 = right * (cx * 0.14)
        let n = simd_normalize(up + tiltF + tiltR)
        F += n * thrust
        T += simd_cross(hub - s.pos, n * thrust)
        // Hub moment from the cyclic (stiff rotor), stability augmentation: rate damping and, stick centred, level.
        let auth = rpm * max(0.3, c)
        let hubPitch: Float = -cy * I.x * 2.2 * auth, hubRoll: Float = cx * I.z * 2.2 * auth
        T += right * hubPitch
        T += fw * hubRoll
        let w = s.angVel
        let wPitch: Float = simd_dot(w, right), wRoll: Float = simd_dot(w, fw), wYaw: Float = simd_dot(w, up)
        let dampP: Float = wPitch * I.x * 2.6 * rpm, dampR: Float = wRoll * I.z * 2.6 * rpm
        T -= right * dampP
        T -= fw * dampR
        let level = simd_cross(up, V3(0, 1, 0))
        let centred: Float = 1 - min(1, simd_length(cyc) * 2)
        let holdK: Float = 3.2 * centred * rpm
        let levP: Float = simd_dot(level, right) * I.x * holdK, levR: Float = simd_dot(level, fw) * I.z * holdK
        T += right * levP
        T += fw * levR
        // Rotor reaction torque, the tail rotor's answer and the pedals, yaw damping.
        let reaction: Float = c * 0.5 * rpm
        let tail: Float = tailRotor ? reaction + pedal * 1.6 * rpm : pedal * 0.3 * rpm
        let yawT: Float = (tail - reaction) * I.y - wYaw * I.y * 1.8 * rpm
        T += up * yawT
    }

    func rotorRadius(_ s: Ship) -> Float { max(3, min(9, (s.localMax.z - s.localMin.z) * 0.42)) }

    // MARK: Autopilot

    // Flies to `hold` (helicopter: hovers there; plane: flies over it at its height), turning to `holdYaw` / the track.
    private func autopilot(_ s: Ship, g: Float, ground: Float) {
        guard let target = hold else { return }
        let fw = s.dirToWorld(s.fwd)
        let fh = simd_normalize(V2(fw.x, fw.z) + V2(1e-5, 0))
        let rh = V2(-fh.y, fh.x)
        let to = target - s.pos
        switch kind {
        case .heli:
            // Desired velocity toward the target, then the acceleration that gets there; collective carries the
            // weight plus the vertical part, the cyclic tilts for the horizontal part (in the hull's frame).
            let dh = V2(to.x, to.z)
            let dist = simd_length(dh)
            let vw = dist > 0.1 ? dh / dist * min(holdSpeed, dist * 0.3) : V2(0, 0)
            let ah = (vw - V2(s.vel.x, s.vel.z)) * 0.5
            let vyWant = max(-3, min(4, to.y * 0.8))
            let ay = (vyWant - s.vel.y) * 1.6
            let tmax = FlightModel.heliTmax * s.mass * g * max(0.2, rpm * rpm) * groundEffect
            collective = max(0, min(1, (s.mass * (g + ay)) / tmax))
            cyclic = V2(max(-0.8, min(0.8, simd_dot(ah, rh) * 0.07)), max(-0.8, min(0.8, simd_dot(ah, fh) * 0.07)))
            var yawWant = holdYaw ?? (dist > 10 ? atan2f(-dh.x, -dh.y) : s.yaw)
            if dist <= 6, let y = holdYaw { yawWant = y }
            var e = yawWant - s.yaw
            while e > Float.pi { e -= 2 * Float.pi }
            while e < -Float.pi { e += 2 * Float.pi }
            pedal = max(-1, min(1, e * 1.4))                      // pedal > 0 turns left (yaw grows)
        case .plane:
            let dh = V2(to.x, to.z)
            let yawWant = holdYaw ?? atan2f(-dh.x, -dh.y)
            var e = yawWant - s.yaw
            while e > Float.pi { e -= 2 * Float.pi }
            while e < -Float.pi { e += 2 * Float.pi }
            let steer = max(-1, min(1, -e * 1.2))
            let climb = max(-1, min(1, to.y * 0.06 - s.vel.y * 0.08))
            s.autopilot = V3(holdSpeed > 0 ? 1 : 0, steer, climb)    // the ship manager feeds these to the propellers too
            s.throttle = s.autopilot!.x; s.steer = steer; s.climb = climb
            s.piloted = true
        }
    }

    // MARK: Player controls

    // Helicopter: collective with Space / Ctrl, RT / LT (it stays where it was left); cyclic with WASD or the left
    // stick; yaw follows the view (heading hold toward the camera's yaw, so the right stick or the mouse turns it),
    // LB / RB nudge the pedals. Plane: the usual aircraft controls (VehicleControls) feed the surfaces directly.
    func playerInput(_ g: Game, _ s: Ship, _ mi: MoveInput, _ dt: Float) {
        guard kind == .heli else { return }
        hold = nil
        let p = PadManager.shared.lastMapped
        var up: Float = mi.jump ? 1 : 0
        if g.input.control { up -= 1 }
        if let p { up += p.rt - p.lt }
        collective = max(0, min(1, collective + up * 0.45 * dt))
        cyclic = V2(max(-1, min(1, mi.strafe)), max(-1, min(1, mi.forward)))
        var e = g.player.yaw - s.yaw
        while e > Float.pi { e -= 2 * Float.pi }
        while e < -Float.pi { e += 2 * Float.pi }
        var ped = max(-1, min(1, e * 1.5))
        if let p { ped += (p.lb ? 1 : 0) - (p.rb ? 1 : 0) }
        pedal = max(-1, min(1, ped))
    }
}
