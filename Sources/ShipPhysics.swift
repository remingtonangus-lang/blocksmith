import Foundation
import simd

// Rigid-body physics for ships (see Ships.swift). Units: blocks (metres), seconds, tonnes; water
// weighs 1 t per block. Fixed 60 Hz substeps; forces first (gravity, buoyancy, drag, propulsion,
// lift, airfoils, wheel suspension), then sequential-impulse contacts against terrain and other ships.
enum ShipTuning {
    static let g: Float = 12
    static let balloonLift: Float = 2.0         // tonnes held up by one lift balloon
    static let propThrust: Float = 120          // per powered propeller at full throttle
    static let paddleThrust: Float = 18         // the helm alone moves a small boat slowly
    static let wheelAccel: Float = 4            // drive per wheel: its share of the weight times this (b/s^2)
    static let perEngine = 4                    // propellers / wheels one engine drives
    static let hullRadius: Float = 0.45
}

// Block reads with the last chunk cached (physics touches many cells in the same chunks).
struct ShipBlockReader {
    let w: World
    private var key = ChunkKey(x: Int.min, z: Int.min)
    private var chunk: Chunk?
    init(_ w: World) { self.w = w }

    @inline(__always) mutating func get(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
        if y < 0 { return BEDROCK }
        if y >= CH { return AIR }
        let cx = x >> 4, cz = z >> 4
        if cx != key.x || cz != key.z { key = ChunkKey(x: cx, z: cz); chunk = w.chunks[key] }
        guard let c = chunk else { return AIR }
        return c.blocks[(x & 15) + (z & 15) * 16 + y * 256]
    }
    @inline(__always) mutating func loaded(_ x: Int, _ z: Int) -> Bool {
        let cx = x >> 4, cz = z >> 4
        if cx != key.x || cz != key.z { key = ChunkKey(x: cx, z: cz); chunk = w.chunks[key] }
        return chunk != nil
    }

    // Highest sky-stopping block of a column (terrain, water, leaves), -1 if unloaded.
    @inline(__always) mutating func columnTop(_ x: Int, _ z: Int) -> Int {
        let cx = x >> 4, cz = z >> 4
        if cx != key.x || cz != key.z { key = ChunkKey(x: cx, z: cz); chunk = w.chunks[key] }
        guard let c = chunk else { return -1 }
        return Int(c.height[(x & 15) + (z & 15) * 16])
    }

    // Height of the water surface in the column at p (near p.y), nil if there is no water there.
    mutating func waterTop(_ p: V3) -> Float? {
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        var y = Int(floor(p.y))
        let fk = Blocks.fluidKind
        if fk[Int(get(x, y, z))] == 1 {
            var k = 0
            while k < 6 && fk[Int(get(x, y + 1, z))] == 1 { y += 1; k += 1 }
            return Float(y) + 0.875 + (k == 6 ? 4 : 0)
        }
        for d in 1...2 where fk[Int(get(x, y - d, z))] == 1 { return Float(y - d) + 0.875 }
        return nil
    }
}

private struct Contact {
    var p: V3
    var n: V3
    var pen: Float
    var acc: Float = 0
    weak var other: Ship?
}

extension ShipManager {
    // Advances every ship (call once per frame) and carries what stands on them.
    func update(_ dt: Float, game: Game?) {
        if !ghosts.isEmpty { ghosts = ghosts.map { ($0.0, $0.1 - dt) }.filter { $0.1 > 0 } }
        if let game {
            // Wind turns slowly over the days; rain and thunder strengthen it.
            let a = Float((game.time / 900).truncatingRemainder(dividingBy: 2 * .pi)) + Float(world.seed % 628) / 100
            let strength: Float = 5 + 4 * game.weather.rain + 5 * game.weather.thunder
            wind = V3(cosf(a), 0, sinf(a)) * strength
        }
        if encounters, let game { encounterTick(dt, game: game) }
        if list.isEmpty { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        // Riders: mobs and items resting on a ship before it moves.
        var mobRiders: [(Mob, Ship)] = []
        var itemRiders: [(ItemEntity, Ship)] = []
        if let game {
            for m in game.mobs.mobs where m.onGround && game.riding !== m {
                if let s = standing(on: m.pos) { mobRiders.append((m, s)) }
            }
            for it in game.drops.items where it.onGround {
                if let s = standing(on: it.pos) { itemRiders.append((it, s)) }
            }
        }
        for s in list {
            s.prevPos = s.pos; s.prevRot = s.rot
            if s === pilot { continue }
            if let a = s.autopilot { s.piloted = true; s.throttle = a.x; s.steer = a.y; s.climb = a.z }
            else { s.piloted = false; s.throttle = 0; s.steer = 0; s.climb = 0 }
        }
        accum += dt
        let h: Float = 1.0 / 60
        var steps = 0
        while accum >= h && steps < 4 {
            accum -= h
            step(h)
            steps += 1
        }
        if steps == 4 { accum = 0 }
        updateShells(dt, game: game)
        // Carry riders with their ship.
        for (m, s) in mobRiders where s.pos != s.prevPos || s.rot != s.prevRot {
            m.pos = s.toWorld(s.prevToLocal(m.pos))
            m.yaw += angleDelta(s.yaw, s.prevYaw)
        }
        for (it, s) in itemRiders where s.pos != s.prevPos || s.rot != s.prevRot {
            it.pos = s.toWorld(s.prevToLocal(it.pos))
        }
        // Mobs a moving hull ran into are shoved aside (or lifted onto it when they are near its top).
        if let game {
            let riding = Set(mobRiders.map { ObjectIdentifier($0.0) })      // (crews on deck are carried, not shoved)
            for m in game.mobs.mobs where m.health > 0 && game.riding !== m && !riding.contains(ObjectIdentifier(m)) {
                let mn = V3(m.pos.x - m.halfW, m.pos.y, m.pos.z - m.halfW), mx = V3(m.pos.x + m.halfW, m.pos.y + m.height, m.pos.z + m.halfW)
                guard let s = list.first(where: { mx.x > $0.worldMin.x && mn.x < $0.worldMax.x && mx.y > $0.worldMin.y && mn.y < $0.worldMax.y
                    && mx.z > $0.worldMin.z && mn.z < $0.worldMax.z }), overlaps(mn, mx) else { continue }
                var lifted = false
                for up in [Float(0.35), 0.7, 1.05] where !overlaps(mn + V3(0, up, 0), mx + V3(0, up, 0)) {
                    m.pos.y += up; lifted = true; break
                }
                if !lifted {
                    var away = V3(m.pos.x - s.pos.x, 0, m.pos.z - s.pos.z)
                    away = simd_length(away) > 0.01 ? simd_normalize(away) : V3(1, 0, 0)
                    m.pos += away * 0.4
                    m.vel += away * 2 + s.velocity(at: m.pos) * 0.5
                }
            }
        }
        if let game {
            for s in list where (s === aboard || s === pilot) && (s.pos != s.prevPos || s.rot != s.prevRot) {
                let p = game.player
                p.pos = s.toWorld(s.prevToLocal(p.pos))
                p.yaw += angleDelta(s.yaw, s.prevYaw)
                p.airPeak = p.pos.y
            }
        }
        for s in list { s.mesh.apply(device: world.device) }
        stepMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
    }

    private func angleDelta(_ a: Float, _ b: Float) -> Float {
        var d = a - b
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }

    // Whether a world point is inside a ship's hull, above its floor (the sea there is kept out).
    func dry(at p: V3) -> Bool {
        if list.isEmpty { return false }
        for s in list where p.x > s.worldMin.x && p.x < s.worldMax.x && p.y > s.worldMin.y && p.y < s.worldMax.y
            && p.z > s.worldMin.z && p.z < s.worldMax.z {
            let l = s.toLocal(p)
            let x = Int(floor(l.x)), y = Int(floor(l.y)), z = Int(floor(l.z))
            if s.grid.inside(x, y, z) && Int(s.colMin[x + z * s.grid.sx]) < y { return true }
        }
        return false
    }

    // The ship a body's feet rest on, if any.
    func standing(on feet: V3) -> Ship? {
        for s in list where feet.x > s.worldMin.x - 0.5 && feet.x < s.worldMax.x + 0.5 && feet.z > s.worldMin.z - 0.5 && feet.z < s.worldMax.z + 0.5
            && feet.y > s.worldMin.y && feet.y < s.worldMax.y + 0.6 {
            let l = s.toLocal(feet - V3(0, 0.15, 0))
            let c = IVec3(Int(floor(l.x)), Int(floor(l.y)), Int(floor(l.z)))
            if Blocks.collide[Int(s.grid.get(c.x, c.y, c.z))] { return s }
        }
        return nil
    }

    // One fixed physics substep for every ship.
    func step(_ h: Float) {
        var reader = ShipBlockReader(world)
        for s in list where s.parent == nil {
            // Frozen while the ground under it isn't loaded.
            if !reader.loaded(Int(floor(s.pos.x)), Int(floor(s.pos.z))) { s.vel = .zero; s.angVel = .zero; continue }
            integrateForces(s, h, &reader)
        }
        // Contacts: terrain and ship-ship.
        for s in list where s.parent == nil {
            var cs: [Contact] = []
            terrainContacts(s, &reader, &cs)
            for o in list where o !== s && o.id < s.id && o.parent == nil {
                if o.worldMax.x < s.worldMin.x - 1 || o.worldMin.x > s.worldMax.x + 1 || o.worldMax.y < s.worldMin.y - 1
                    || o.worldMin.y > s.worldMax.y + 1 || o.worldMax.z < s.worldMin.z - 1 || o.worldMin.z > s.worldMax.z + 1 { continue }
                shipContacts(s, o, &cs)
                shipContacts(o, s, &cs, flip: true)
            }
            s.contacts = cs.count
            if !cs.isEmpty { solve(s, &cs, h) }
        }
        for s in list where s.parent == nil {
            if !reader.loaded(Int(floor(s.pos.x)), Int(floor(s.pos.z))) { continue }
            let sp = simd_length(s.vel)
            if sp > 60 { s.vel *= 60 / sp }
            let w = simd_length(s.angVel)
            if w > 4 { s.angVel *= 4 / w }
            s.pos += s.vel * h
            if w > 1e-6 {
                s.rot = simd_normalize(Quat(angle: w * h, axis: s.angVel / w) * s.rot)
            }
            s.updateBounds()
        }
        // Turrets ride on their (now moved) parents; turrets of turrets after their parent turret.
        for _ in 0..<2 { for s in list where s.parent != nil { s.followParent(h) } }
    }

    // MARK: Forces

    private func integrateForces(_ s: Ship, _ h: Float, _ rd: inout ShipBlockReader) {
        let g = ShipTuning.g
        var F = V3(0, -s.mass * g, 0)
        var T = V3(0, 0, 0)
        @inline(__always) func apply(_ f: V3, at w: V3) { F += f; T += simd_cross(w - s.pos, f) }

        // Buoyancy and water drag per bucket.
        let fwdAxis = abs(s.fwd.x) > 0.5 ? 0 : 2
        var cw = V3(2.2, 3.0, 2.2)
        cw[fwdAxis] = 0.15
        var sub: Float = 0
        for b in s.buckets {
            let wp = s.toWorld(b.centre)
            guard let top = rd.waterTop(wp) else { continue }
            let f = min(1, max(0, (top - (wp.y - b.height * 0.5)) / b.height))
            if f <= 0 { continue }
            let v = b.volume * f
            sub += v
            var force = V3(0, v * g, 0)
            let vl = s.dirToLocal(s.velocity(at: wp))
            let quad: V3 = vl * simd_abs(vl)
            let rel: V3 = vl + quad * 0.3
            let drag: V3 = -(cw * rel) * v
            force += s.dirToWorld(drag)
            apply(force, at: wp)
        }
        s.submerged = sub

        // Air drag on the projected area across each ship axis, and damping.
        let sp = simd_length(s.vel)
        let vlAir = s.dirToLocal(s.vel)
        let airK: Float = 0.1 + 0.03 * sp
        let airLocal: V3 = vlAir * s.area * airK
        F -= s.dirToWorld(airLocal)
        s.angVel *= expf(-(sub > 0 ? 0.4 : 0.8) * h)

        let up = s.dirToWorld(V3(0, 1, 0))
        let fwdW = s.dirToWorld(s.fwd)
        let props = s.props.count, wheels = s.wheels.count
        // Drive units: each propeller, and wheels by the square root of their cells (big wheels are made of many).
        let drives = props + (wheels > 0 ? Int(ceil(sqrtf(Float(wheels)))) : 0)
        let power: Float = s.engines > 0 && drives > 0 ? min(1, Float(s.engines * ShipTuning.perEngine) / Float(drives)) : 0
        let aircraft = s.wings.count >= 4 && s.balloons == 0
        let piloted = s.piloted

        // Propellers (applied at the propeller, level with the centre of mass so they don't pitch the hull).
        if piloted && s.throttle != 0 && power > 0 {
            for (p, d) in s.props {
                var at = p
                at.y = s.com.y
                apply(s.dirToWorld(d) * (s.throttle * ShipTuning.propThrust * power), at: s.toWorld(at))
            }
        }
        // Sails (wool): pushed by the wind relative to the ship while someone steers (furled otherwise).
        if piloted && s.sails > 0 {
            let rel = wind - s.vel
            let rh = V3(rel.x, 0, rel.z)
            // Trimmed sails turn the wind into drive along the heading (the keel takes the rest): best running
            // before the wind, weaker across it, a little even close to it (tacking), plus some leeway.
            var fh = V3(fwdW.x, 0, fwdW.z)
            fh = simd_length_squared(fh) > 1e-4 ? simd_normalize(fh) : V3(0, 0, -1)
            let speed2 = simd_length_squared(rh)
            if speed2 > 0.01 {
                let cosA = simd_dot(rh / speed2.squareRoot(), fh)
                let push = speed2 * 0.35 * Float(s.sails)
                F += fh * (push * max(0.15, (1 + cosA) * 0.5)) + rh / speed2.squareRoot() * (push * 0.15)
            }
        }
        // Helm paddling in water.
        if piloted && s.throttle != 0 && sub > 0 && s.helm != nil {
            F += fwdW * (s.throttle * ShipTuning.paddleThrust * (s.throttle < 0 ? 0.5 : 1))
        }

        // Lift balloons: hold an altitude, climb or sink on command.
        if s.balloons > 0 {
            let cap = Float(s.balloons) * ShipTuning.balloonLift * g
            var vyTarget: Float
            if piloted && abs(s.climb) > 0.1 { vyTarget = s.climb * 5; s.hoverY = s.pos.y }
            else {
                if s.hoverY == nil { s.hoverY = s.pos.y }
                vyTarget = max(-2, min(2, (s.hoverY! - s.pos.y) * 1.2))
            }
            let want = s.mass * g - sub * g + s.mass * 2.5 * (vyTarget - s.vel.y)
            let lvl = max(0, min(1, want / cap))
            s.liftLevel += max(-h * 1.5, min(h * 1.5, lvl - s.liftLevel))
            F.y += s.liftLevel * cap
        }

        // Airfoils: a flat plate pushes back against motion through it (lift when the nose is up).
        for p in s.wings {
            let wp = s.toWorld(p)
            let v = s.velocity(at: wp)
            let vn = simd_dot(v, up)
            let mag = simd_length(v)
            apply(-up * (0.15 * mag * vn + 0.3 * vn), at: wp)
        }

        // Wheels: spring-damper suspension, rolling along the heading, gripping sideways.
        s.grounded = false
        if wheels > 0 {
            // The load is carried by the lowest row of wheel cells.
            let share = s.mass / Float(max(1, s.wheelBase))
            let k = share * g / 0.15
            let c = 2 * sqrtf(k * share) * 0.6
            var fh = V3(fwdW.x, 0, fwdW.z)
            fh = simd_length(fh) > 1e-3 ? simd_normalize(fh) : V3(0, 0, -1)
            let side = V3(-fh.z, 0, fh.x)
            for p in s.wheels {
                let wp = s.toWorld(p)
                let x = Int(floor(wp.x)), z = Int(floor(wp.z))
                var top: Float?
                var y = Int(floor(wp.y))
                while y >= Int(floor(wp.y - 1.3)) {
                    let b = rd.get(x, y, z)
                    if Blocks.collide[Int(b)] {
                        var t: Float = 1
                        if !Blocks.fullCollide[Int(b)] { t = 0; for bx in Blocks.boxes[Int(b)] { t = max(t, Float(bx.y1) / 16) } }
                        top = Float(y) + t
                        break
                    }
                    y -= 1
                }
                // Up to half a block above the axle: the wheel rides up onto a step.
                guard let ground = top, ground <= wp.y + 0.55 else { continue }
                let comp = 0.75 - (wp.y - ground)
                if comp <= 0 { continue }
                let cp = V3(wp.x, ground, wp.z)
                let v = s.velocity(at: cp)
                let fn = max(0, k * min(comp, 0.6) - c * v.y)
                if fn <= 0 { continue }
                s.grounded = true
                let grip = 0.9 * fn
                let vs = simd_dot(v, side), vf = simd_dot(v, fh)
                let lat = max(-grip, min(grip, -vs * share * 12))
                var long: Float
                if piloted && s.throttle != 0 && power > 0 {
                    let fade = s.throttle * vf > 0 ? max(0, 1 - abs(vf) / 16) : 1
                    long = s.throttle * share * ShipTuning.wheelAccel * power * fade - vf * share * 0.3
                } else {
                    long = -vf * share * (piloted ? 0.6 : 8)       // rolling resistance / parking brake
                }
                long = max(-grip, min(grip, long))
                apply(V3(0, fn, 0), at: wp)
                apply(side * lat + fh * long, at: V3(wp.x, (wp.y + ground) * 0.5, wp.z))
            }
        }

        // Steering: a yaw-rate controller (rudder / differential / tail surfaces).
        let I = s.inertiaDiag
        let iAvg = (I.x + I.y + I.z) / 3
        if piloted {
            let speed = simd_length(s.vel)
            var rate: Float = 0.6
            if s.grounded { rate = 0.9 }
            else if sub > 0 && s.balloons == 0 { rate = 0.55 * max(0.3, min(1, speed / 4)) }
            let target = -s.steer * rate
            let wy = simd_dot(s.angVel, up)
            T += up * (I.y * 4 * (target - wy))
        }

        // Keep upright (aircraft: roll toward the bank the pilot asks for, pitch free; pitch by climb input).
        var desiredUp = V3(0, 1, 0)
        if aircraft {
            let right = simd_normalize(simd_cross(fwdW, V3(0, 1, 0)) + V3(0, 1e-5, 0))
            desiredUp = simd_normalize(V3(0, 1, 0) + right * (piloted ? s.steer * 0.5 : 0))
        }
        var err = simd_cross(up, desiredUp)
        if aircraft { err = fwdW * simd_dot(err, fwdW) }
        let kr: Float = s.balloons > 0 ? 8 : (aircraft ? 5 : (s.grounded ? 1.5 : (sub > 0 ? 1.2 : 2)))
        let wHoriz = s.angVel - up * simd_dot(s.angVel, up)
        let damped: V3 = aircraft ? fwdW * simd_dot(wHoriz, fwdW) : wHoriz
        let kd: Float = iAvg * (s.balloons > 0 ? 3 : 1.2)
        T += err * (kr * iAvg) - damped * kd
        if aircraft && piloted {
            let right = simd_normalize(simd_cross(fwdW, up))
            // No input: hold a slight nose-up trim so level flight needs no constant correction.
            let pitch = asinf(max(-1, min(1, fwdW.y)))
            let target = abs(s.climb) > 0.05 ? s.climb * 0.9 : max(-0.5, min(0.5, (0.08 - pitch) * 2))
            let wr = simd_dot(s.angVel, right)
            T += right * (I.x * 4 * (target - wr))
        }

        s.vel += F / s.mass * h
        s.angVel += s.invInertiaWorld * T * h
    }

    // MARK: Contacts

    private func terrainContacts(_ s: Ship, _ rd: inout ShipBlockReader, _ out: inout [Contact]) {
        let r = ShipTuning.hullRadius
        // Broadphase: nothing under the ship reaches its lowest point (heightmaps of its footprint).
        if s.terrainCheck <= 0 {
            var top = -1
            for z in Int(floor(s.worldMin.z))...Int(floor(s.worldMax.z)) {
                for x in Int(floor(s.worldMin.x))...Int(floor(s.worldMax.x)) { top = max(top, rd.columnTop(x, z)) }
            }
            s.terrainClear = s.worldMin.y - Float(top + 1)
            // Re-check sooner when close or fast.
            let fall = max(1, simd_length(s.vel))
            s.terrainCheck = s.terrainClear > 2 ? min(30, Int((s.terrainClear - 1) / fall * 60)) : 0
        } else {
            s.terrainCheck -= 1
        }
        if s.terrainClear > 1.5 && s.terrainCheck > 0 { return }
        let collide = Blocks.collide
        // Big hulls test half their cells each substep (alternating).
        let stride = s.hull.count > 6000 ? 2 : 1
        let phase = stride > 1 ? Int(s.pos.x * 7 + s.pos.z * 3) & 1 : 0
        var i = phase
        let hull = s.hull
        let stepUp = !s.wheels.isEmpty && s.grounded
        while i < hull.count {
            let w = s.toWorld(hull[i])
            i += stride
            let x0 = Int(floor(w.x - r)), x1 = Int(floor(w.x + r))
            let y0 = Int(floor(w.y - r)), y1 = Int(floor(w.y + r))
            let z0 = Int(floor(w.z - r)), z1 = Int(floor(w.z + r))
            var best: (V3, Float)?
            for y in y0...y1 { for z in z0...z1 { for x in x0...x1 {
                let b = rd.get(x, y, z)
                if !collide[Int(b)] { continue }
                let mn = V3(Float(x), Float(y), Float(z))
                var mx = mn + 1
                if !Blocks.fullCollide[Int(b)] {
                    var top: Float = 0
                    for bx in Blocks.boxes[Int(b)] { top = max(top, Float(bx.y1) / 16) }
                    mx.y = mn.y + max(0.125, min(1, top))
                }
                let q = simd_clamp(w, mn, mx)
                let d = w - q
                let d2 = simd_dot(d, d)
                if d2 >= r * r { continue }
                var n: V3, pen: Float
                if d2 > 1e-8 {
                    let dist = sqrtf(d2)
                    n = d / dist; pen = r - dist
                } else {
                    // Centre inside the block: push out through the nearest face (up preferred).
                    let faces: [(Float, V3)] = [(mx.y - w.y - 0.05, V3(0, 1, 0)), (w.y - mn.y, V3(0, -1, 0)), (mx.x - w.x, V3(1, 0, 0)),
                                                (w.x - mn.x, V3(-1, 0, 0)), (mx.z - w.z, V3(0, 0, 1)), (w.z - mn.z, V3(0, 0, -1))]
                    var f = faces[0]
                    for c in faces.dropFirst() where c.0 < f.0 { f = c }
                    n = f.1; pen = r + max(0, f.0)
                }
                // Wheeled vehicles on the ground climb low steps: a side hit low on the hull against a block with room
                // above it pushes the hull up onto the step instead of stopping it.
                if stepUp && abs(n.y) < 0.7 && mx.y - (w.y - r) < 1.05 && !collide[Int(rd.get(x, y + 1, z))] {
                    n = V3(0, 1, 0)
                    pen = min(0.35, mx.y - (w.y - r))
                }
                if best == nil || pen > best!.1 { best = (n, pen) }
            } } }
            if let bc = best { out.append(Contact(p: w - bc.0 * r, n: bc.0, pen: bc.1, other: nil)) }
        }
    }

    // Contacts of a's hull cells against b's blocks (normals point from b toward a).
    private func shipContacts(_ a: Ship, _ b: Ship, _ out: inout [Contact], flip: Bool = false) {
        let r = ShipTuning.hullRadius
        let g = b.grid
        let collide = Blocks.collide
        for c in a.hull {
            let w = a.toWorld(c)
            if w.x < b.worldMin.x - 1 || w.x > b.worldMax.x + 1 || w.y < b.worldMin.y - 1 || w.y > b.worldMax.y + 1
                || w.z < b.worldMin.z - 1 || w.z > b.worldMax.z + 1 { continue }
            let l = b.toLocal(w)
            var best: (V3, Float)?
            for y in Int(floor(l.y - r))...Int(floor(l.y + r)) { for z in Int(floor(l.z - r))...Int(floor(l.z + r)) { for x in Int(floor(l.x - r))...Int(floor(l.x + r)) {
                if !collide[Int(g.get(x, y, z))] { continue }
                let mn = V3(Float(x), Float(y), Float(z)), mx = mn + 1
                let q = simd_clamp(l, mn, mx)
                let d = l - q
                let d2 = simd_dot(d, d)
                if d2 >= r * r { continue }
                var n: V3, pen: Float
                if d2 > 1e-8 { let dist = sqrtf(d2); n = d / dist; pen = r - dist }
                else {
                    let faces: [(Float, V3)] = [(mx.y - l.y, V3(0, 1, 0)), (l.y - mn.y, V3(0, -1, 0)), (mx.x - l.x, V3(1, 0, 0)),
                                                (l.x - mn.x, V3(-1, 0, 0)), (mx.z - l.z, V3(0, 0, 1)), (l.z - mn.z, V3(0, 0, -1))]
                    var f = faces[0]
                    for c in faces.dropFirst() where c.0 < f.0 { f = c }
                    n = f.1; pen = r + f.0
                }
                if best == nil || pen > best!.1 { best = (n, pen) }
            } } }
            if let bc = best {
                let n = b.dirToWorld(bc.0), pen = bc.1
                // Stored from the point of view of the ship being solved (flip: the contact belongs to b's list owner).
                out.append(Contact(p: w - n * r, n: flip ? -n : n, pen: pen, other: b === a ? nil : (flip ? a : b)))
            }
        }
    }

    // Sequential impulses: non-penetration with Baumgarte bias, Coulomb friction.
    private func solve(_ s: Ship, _ cs: inout [Contact], _ h: Float) {
        let invM = 1 / s.mass
        let iw = s.invInertiaWorld
        let mu: Float = 0.6
        for _ in 0..<6 {
            for k in cs.indices {
                let c = cs[k]
                let r = c.p - s.pos
                var v = s.vel + simd_cross(s.angVel, r)
                var oInvM: Float = 0
                var oIw = simd_float3x3(0)
                var ro = V3(0, 0, 0)
                if let o = c.other {
                    ro = c.p - o.pos
                    v -= o.vel + simd_cross(o.angVel, ro)
                    oInvM = 1 / o.mass
                    oIw = o.invInertiaWorld
                }
                let vn = simd_dot(v, c.n)
                let rn = simd_cross(r, c.n)
                var kn = invM + simd_dot(rn, iw * rn)
                if c.other != nil { let ron = simd_cross(ro, c.n); kn += oInvM + simd_dot(ron, oIw * ron) }
                let bias = min(4, 0.2 / h * max(0, c.pen - 0.02))
                var dj = (-vn + bias) / kn
                let acc = max(0, c.acc + dj)
                dj = acc - c.acc
                cs[k].acc = acc
                applyImpulse(s, c.n * dj, r, invM, iw)
                if let o = c.other { applyImpulse(o, -c.n * dj, ro, oInvM, oIw) }
                // Friction.
                v = s.vel + simd_cross(s.angVel, r)
                if let o = c.other { v -= o.vel + simd_cross(o.angVel, ro) }
                let vt = v - c.n * simd_dot(v, c.n)
                let vtl = simd_length(vt)
                if vtl > 1e-4 {
                    let t = vt / vtl
                    let rt = simd_cross(r, t)
                    var kt = invM + simd_dot(rt, iw * rt)
                    if c.other != nil { let rot = simd_cross(ro, t); kt += oInvM + simd_dot(rot, oIw * rot) }
                    let jt = max(-vtl / kt, -mu * acc)
                    applyImpulse(s, t * jt, r, invM, iw)
                    if let o = c.other { applyImpulse(o, -t * jt, ro, oInvM, oIw) }
                }
            }
        }
    }

    @inline(__always) private func applyImpulse(_ s: Ship, _ j: V3, _ r: V3, _ invM: Float, _ iw: simd_float3x3) {
        s.vel += j * invM
        s.angVel += iw * simd_cross(r, j)
    }
}
