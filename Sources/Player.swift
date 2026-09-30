import Foundation
import simd

struct MoveInput {
    var forward: Float = 0   // -1..1
    var strafe: Float = 0    // -1..1 (right positive)
    var jump = false
    var sneak = false
    var sprint = false
}

final class Player {
    var pos = V3(0, 100, 0)       // feet centre
    var vel = V3(0, 0, 0)
    var yaw: Float = 0
    var pitch: Float = 0
    var flying = false
    var onGround = false
    var inWater = false
    var headInWater = false
    var sneaking = false
    var sprinting = false
    var airPeak: Float = 0         // highest feet y since last touching ground/water (fall damage)
    var pendingFall: Float = 0     // fall distance of the last landing; Game consumes and clears it
    var jumped = false             // a ground jump started this frame
    var gliding = false            // elytra flight
    var boost: Float = 0           // firework rocket boost left (s)
    var levitate: Float = 0        // shulker bullet levitation left (s)
    var impact: Float = 0          // kinetic energy of the last wall hit while gliding (Game turns it into damage)
    private var glideAcc: Float = 0

    let halfW: Float = 0.3
    let height: Float = 1.8
    let eyeHeight: Float = 1.62

    var eye: V3 { pos + V3(0, (sneaking && !flying) ? eyeHeight - 0.15 : eyeHeight, 0) }
    var look: V3 { V3(-sinf(yaw) * cosf(pitch), sinf(pitch), -cosf(yaw) * cosf(pitch)) }

    func collides(at p: V3, _ w: World) -> Bool {
        w.collides(V3(p.x - halfW, p.y, p.z - halfW), V3(p.x + halfW, p.y + height, p.z + halfW))
    }

    func intersectsBlock(_ b: IVec3) -> Bool {
        let bx = Float(b.x), by = Float(b.y), bz = Float(b.z)
        return pos.x + halfW > bx && pos.x - halfW < bx + 1 &&
            pos.y + height > by && pos.y < by + 1 &&
            pos.z + halfW > bz && pos.z - halfW < bz + 1
    }

    private func groundBelow(_ p: V3, _ w: World) -> Bool {
        collides(at: p - V3(0, 0.06, 0), w)
    }

    func update(dt: Float, input: MoveInput, world w: World) {
        // Freeze until the chunk under us exists, so we never fall through ungenerated terrain.
        guard w.isLoaded(Int(floor(pos.x)), Int(floor(pos.z))) else { return }

        // Unstuck: if spawned or placed inside a block, pop upward.
        var tries = 0
        while collides(at: pos, w) && tries < 64 { pos.y += 1; tries += 1 }

        let feet = w.block(Int(floor(pos.x)), Int(floor(pos.y + 0.1)), Int(floor(pos.z)))
        let body = w.block(Int(floor(pos.x)), Int(floor(pos.y + 0.9)), Int(floor(pos.z)))
        inWater = Blocks.isLiquid(feet) || Blocks.isLiquid(body)
        let e = eye
        headInWater = Blocks.isLiquid(w.block(Int(floor(e.x)), Int(floor(e.y)), Int(floor(e.z))))

        if flying || inWater { airPeak = pos.y }
        jumped = false
        if gliding && (onGround || inWater || flying) { gliding = false }
        if gliding { glide(dt, w); return }

        sneaking = input.sneak && !flying
        sprinting = input.sprint && input.forward > 0 && !sneaking

        let f = V3(-sinf(yaw), 0, -cosf(yaw))
        let r = V3(cosf(yaw), 0, -sinf(yaw))
        var wish = f * input.forward + r * input.strafe
        let len = simd_length(wish)
        if len > 1 { wish /= len }

        let speed: Float
        if flying { speed = sprinting ? 21.6 : 10.9 }
        else if inWater { speed = sprinting ? 3.0 : 2.2 }
        else if sneaking { speed = 1.31 }
        else { speed = sprinting ? 5.612 : 4.317 }

        let target = wish * speed
        let accel: Float = flying ? 10 : (onGround ? 20 : (inWater ? 8 : 5))
        let k = 1 - expf(-accel * dt)
        vel.x += (target.x - vel.x) * k
        vel.z += (target.z - vel.z) * k

        if flying {
            var vy: Float = 0
            if input.jump { vy += 1 }
            if input.sneak { vy -= 1 }
            let ty = vy * (sprinting ? 12 : 8)
            vel.y += (ty - vel.y) * (1 - expf(-10 * dt))
        } else if inWater {
            vel.y -= 9 * dt
            vel.y *= expf(-2.5 * dt)
            if input.jump { vel.y = min(vel.y + 22 * dt, 3.2) }
            vel.y = max(vel.y, -4)
        } else if levitate > 0 {
            levitate -= dt
            vel.y += (0.9 - vel.y) * (1 - expf(-4 * dt))
            airPeak = pos.y
        } else {
            vel.y -= 28 * dt
            vel.y = max(vel.y, -60)
            if input.jump && onGround { vel.y = 8.6; jumped = true }
        }

        // Sneak edge guard: don't let horizontal motion carry us off a ledge.
        if onGround && sneaking {
            for a in [0, 2] {
                var p = pos
                p[a] += vel[a] * dt
                if !groundBelow(p, w) { vel[a] = 0 }
            }
        }
        let hit = w.moveBody(&pos, halfW: halfW, height: height, vel * dt, step: flying ? 0 : 0.6, onGround: onGround)
        var landed = false
        if hit.y {
            if vel.y < 0 { landed = true }
            vel.y = 0
        }
        if hit.x { vel.x = 0 }
        if hit.z { vel.z = 0 }
        onGround = landed || (vel.y <= 0 && groundBelow(pos, w))
        if flying && landed { flying = false }
        if onGround {
            if airPeak - pos.y > 0 { pendingFall = max(pendingFall, airPeak - pos.y) }
            airPeak = pos.y
        } else {
            airPeak = max(airPeak, pos.y)
        }
        if pos.y < -64 { pos.y = Float(CH); vel = .zero }
    }

    // Elytra flight, stepped at 20 Hz in blocks/tick like the reference game: pitch trades height for
    // speed, looking up converts speed back into lift, drag 1%/2% per tick; rockets push along the look.
    private func glide(_ dt: Float, _ w: World) {
        glideAcc += dt
        var v = vel / 20
        while glideAcc >= 0.05 {
            glideAcc -= 0.05
            let l = look
            let pitchDown = -pitch
            let lookH = (l.x * l.x + l.z * l.z).squareRoot()
            let velH = (v.x * v.x + v.z * v.z).squareRoot()
            var cosP = cosf(pitchDown)
            cosP = cosP * cosP * min(1, simd_length(l) / 0.4)
            v.y += -0.08 + cosP * 0.06
            if v.y < 0 && lookH > 0 {
                let lift = v.y * -0.1 * cosP
                v.y += lift
                v.x += l.x * lift / lookH
                v.z += l.z * lift / lookH
            }
            if pitchDown < 0 && lookH > 0 {
                let climb = velH * -sinf(pitchDown) * 0.04
                v.y += climb * 3.2
                v.x -= l.x * climb / lookH
                v.z -= l.z * climb / lookH
            }
            if lookH > 0 {
                v.x += (l.x / lookH * velH - v.x) * 0.1
                v.z += (l.z / lookH * velH - v.z) * 0.1
            }
            if boost > 0 {
                boost -= 0.05
                v += l * 0.1 + (l * 1.5 - v) * 0.5
            }
            v *= V3(0.99, 0.98, 0.99)
        }
        vel = v * 20
        let before = (vel.x * vel.x + vel.z * vel.z).squareRoot()
        let hit = w.moveBody(&pos, halfW: halfW, height: 0.6, vel * dt, step: 0, onGround: false)
        if hit.x { vel.x = 0 }
        if hit.z { vel.z = 0 }
        if hit.x || hit.z {
            let after = (vel.x * vel.x + vel.z * vel.z).squareRoot()
            impact = max(impact, (before - after) / 20 * 10 - 3)
        }
        if hit.y {
            if vel.y < 0 { onGround = true; gliding = false }
            vel.y = 0
        }
        airPeak = pos.y
        if pos.y < -64 { pos.y = Float(CH); vel = .zero }
    }
}
