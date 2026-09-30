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
    var gliding = false            // glider wings flight
    var boost: Float = 0           // firework rocket boost left (s)
    var levitate: Float = 0        // sentry bolt levitation left (s)
    var levitateAmp = 0
    var speedMul: Float = 1        // speed / slowness effects
    var jumpBoost = 0              // jump boost level
    var slowFalling = false
    var dolphinsGrace = false
    var depthStrider = 0           // boots enchantments
    var soulSpeed = 0
    var swiftSneak = 0
    var frostWalker = 0
    var impact: Float = 0          // kinetic energy of the last wall hit while gliding (Game turns it into damage)
    private var glideAcc: Float = 0

    var swimming = false           // sprint-swimming: 0.6 tall, moves along the look direction
    var autoJump = false           // hop up one-block steps automatically while walking into them
    var crawling = false           // no headroom to stand (after swimming into a low gap): 0.6 tall

    let halfW: Float = 0.3
    var prone: Bool { swimming || crawling || gliding }
    var height: Float { prone ? 0.6 : (sneaking && !flying ? 1.5 : 1.8) }
    let eyeHeight: Float = 1.62

    var eye: V3 { pos + V3(0, prone ? 0.4 : ((sneaking && !flying) ? eyeHeight - 0.35 : eyeHeight), 0) }
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

        // Pose: sprint-swim in water; crawl when there is no room to stand or sneak.
        let wet = Blocks.isLiquid(w.block(Int(floor(pos.x)), Int(floor(pos.y + 0.3)), Int(floor(pos.z))))
        if swimming {
            if !(wet && input.sprint && input.forward > 0) || flying { swimming = false }
        } else if !flying && input.sprint && input.forward > 0 && headInWater { swimming = true }
        func fits(_ h: Float) -> Bool { !w.collides(V3(pos.x - halfW, pos.y, pos.z - halfW), V3(pos.x + halfW, pos.y + h, pos.z + halfW)) }
        crawling = !flying && !swimming && !gliding && fits(0.6) && !fits(1.5)
        let forcedCrouch = !flying && !prone && fits(1.5) && !fits(1.8)

        // Unstuck: if spawned or placed inside a block, pop upward.
        var tries = 0
        while collides(at: pos, w) && tries < 64 { pos.y += 1; tries += 1 }

        let feet = w.block(Int(floor(pos.x)), Int(floor(pos.y + 0.1)), Int(floor(pos.z)))
        let body = w.block(Int(floor(pos.x)), Int(floor(pos.y + (prone ? 0.3 : 0.9))), Int(floor(pos.z)))
        inWater = Blocks.isLiquid(feet) || Blocks.isLiquid(body)
        let e = eye
        headInWater = Blocks.isLiquid(w.block(Int(floor(e.x)), Int(floor(e.y)), Int(floor(e.z))))

        if flying || inWater { airPeak = pos.y }
        jumped = false
        if gliding && (onGround || inWater || flying) { gliding = false }
        if gliding { glide(dt, w); return }

        sneaking = (input.sneak || forcedCrouch) && !flying && !prone
        sprinting = (input.sprint && input.forward > 0 && !sneaking) || swimming

        let f = V3(-sinf(yaw), 0, -cosf(yaw))
        let r = V3(cosf(yaw), 0, -sinf(yaw))
        var wish = f * input.forward + r * input.strafe
        let len = simd_length(wish)
        if len > 1 { wish /= len }

        var speed: Float
        if flying { speed = sprinting ? 21.6 : 10.9 }
        else if inWater {
            speed = sprinting ? 3.0 : 2.2
            // Depth magmastrider closes the gap to land speed; dolphin's grace is much faster.
            if depthStrider > 0 { speed += (4.317 - speed) * Float(min(3, depthStrider)) / 3 }
            if dolphinsGrace { speed *= 2.2 }
        }
        else if sneaking || crawling { speed = 4.317 * min(1, 0.3 + 0.15 * Float(swiftSneak)) }
        else { speed = sprinting ? 5.612 : 4.317 }
        if !flying { speed *= speedMul }
        if soulSpeed > 0 && onGround {
            let under = Blocks.key(w.block(Int(floor(pos.x)), Int(floor(pos.y - 0.2)), Int(floor(pos.z))))
            if under == "soul_sand" || under == "soul_soil" { speed *= 1.3 + 0.105 * Float(soulSpeed) }
        }

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
        } else if swimming {
            // Sprint-swimming goes where you look (dive and surface with the view), about sprint speed.
            var sp: Float = 5.6 * speedMul
            if depthStrider > 0 { sp *= 1 + 0.1 * Float(min(3, depthStrider)) }
            if dolphinsGrace { sp *= 1.8 }
            let t = look * sp
            let ks = 1 - expf(-5 * dt)
            vel += (t - vel) * ks
        } else if inWater {
            vel.y -= 9 * dt
            vel.y *= expf(-2.5 * dt)
            if input.jump { vel.y = min(vel.y + 22 * dt, 3.2) }
            vel.y = max(vel.y, -4)
        } else if levitate > 0 {
            levitate -= dt
            vel.y += (0.9 * Float(levitateAmp + 1) - vel.y) * (1 - expf(-4 * dt))
            airPeak = pos.y
        } else {
            vel.y -= (slowFalling && vel.y < 0 ? 2.8 : 28) * dt
            vel.y = max(vel.y, slowFalling ? -1.2 : -60)
            if slowFalling { airPeak = pos.y }
            if input.jump && onGround { vel.y = 8.6 + 2 * Float(jumpBoost); jumped = true }
        }

        // Ladders and vines: climb when pushing forward or jumping, hold with sneak, slow slide otherwise.
        if !flying && (Player.climbable(feet) || Player.climbable(body)) {
            if input.jump || (input.forward > 0.1 && (collides(at: pos + f * 0.35, w))) { vel.y = 2.35 }
            else if input.sneak { vel.y = max(vel.y, 0) }
            else { vel.y = max(vel.y, -3) }
            airPeak = pos.y
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
        if autoJump && onGround && !flying && !sneaking && !prone && (hit.x || hit.z) && simd_length(wish) > 0.3 {
            // Auto-jump: a one-block step ahead with room above it.
            let d = simd_normalize(wish) * 0.35
            if collides(at: pos + d, w) && !collides(at: pos + d + V3(0, 1.05, 0), w) && !collides(at: pos + V3(0, 1.05, 0), w) {
                vel.y = 8.6 + 2 * Float(jumpBoost)
            }
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

    // Glider Wings flight, stepped at 20 Hz in blocks/tick like the reference game: pitch trades height for
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

    static let climbIds: Set<BlockID> = {
        var s = Set<BlockID>()
        for i in 0..<Blocks.count where Blocks.shape[i] == "ladder" { s.insert(BlockID(i)) }
        for n in ["vine", "cave_vines", "scaffolding", "twisting_vines", "weeping_vines"] where Blocks.has(n) { s.insert(Blocks.id(n)) }
        return s
    }()
    static func climbable(_ b: BlockID) -> Bool { climbIds.contains(b) }
}
