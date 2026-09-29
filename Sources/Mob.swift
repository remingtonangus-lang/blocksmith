import Foundation
import simd

// Simple passive animals: cuboid models built on the CPU each frame (a few hundred vertices each),
// wander/idle AI with cliff and water avoidance, panic when hit, AABB physics like the player's.

struct MobVert { var pos: V4; var color: V4; var local: V4 } // pos.w = pattern id, color.a = shade

enum MobKind: Int, CaseIterable {
    case cow, sheep, chicken

    var halfW: Float { self == .chicken ? 0.2 : 0.45 }
    var height: Float { self == .chicken ? 0.7 : 1.3 }
    var maxHealth: Int { [10, 8, 4][rawValue] }
    var call: Snd { [Snd.mobCow, .mobSheep, .mobChicken][rawValue] }
    var name: String { ["Cow", "Sheep", "Chicken"][rawValue] }
}

final class Mob {
    let kind: MobKind
    var pos: V3
    var vel = V3(0, 0, 0)
    var yaw: Float
    var onGround = false
    var health: Int
    var walkPhase: Float = 0
    var walkAmount: Float = 0
    var moving = false
    var aiTimer: Float
    var panic: Float = 0
    var hurt: Float = 0
    var callTimer: Float

    init(_ kind: MobKind, at p: V3) {
        self.kind = kind
        pos = p
        yaw = Float.random(in: 0..<(2 * .pi))
        health = kind.maxHealth
        aiTimer = Float.random(in: 0.5...3)
        callTimer = Float.random(in: 6...20)
    }

    var forward: V3 { V3(-sinf(yaw), 0, -cosf(yaw)) }

    // MARK: Physics

    func collides(_ p: V3, _ w: World) -> Bool {
        let hw = kind.halfW, eps: Float = 1e-4
        let x0 = Int(floor(p.x - hw)), x1 = Int(floor(p.x + hw - eps))
        let y0 = Int(floor(p.y)), y1 = Int(floor(p.y + kind.height - eps))
        let z0 = Int(floor(p.z - hw)), z1 = Int(floor(p.z + hw - eps))
        let col = Blocks.collide
        for y in y0...y1 { for z in z0...z1 { for x in x0...x1 where col[Int(w.block(x, y, z))] { return true } } }
        return false
    }

    private func moveAxis(_ a: Int, _ d: Float, _ w: World) -> Bool {
        if d == 0 { return false }
        var p = pos
        p[a] += d
        if !collides(p, w) { pos = p; return false }
        let lo: Float = a == 1 ? 0 : kind.halfW
        let hi: Float = a == 1 ? kind.height : kind.halfW
        var s = pos
        if d > 0 { s[a] = floor(p[a] + hi - 1e-4) - hi - 1e-3 } else { s[a] = floor(p[a] - lo) + 1 + lo + 1e-3 }
        if (d > 0 ? s[a] >= pos[a] : s[a] <= pos[a]) && !collides(s, w) { pos = s }
        return true
    }

    private func solid(_ x: Float, _ y: Float, _ z: Float, _ w: World) -> Bool {
        Blocks.collide[Int(w.block(Int(floor(x)), Int(floor(y)), Int(floor(z))))]
    }

    func update(_ dt: Float, world w: World, player: V3) {
        guard w.isLoaded(Int(floor(pos.x)), Int(floor(pos.z))) else { return }
        hurt = max(0, hurt - dt)
        panic = max(0, panic - dt)
        callTimer -= dt
        aiTimer -= dt

        // AI: idle <-> wander; panic runs away from the player, re-steering often.
        if panic > 0 {
            moving = true
            if aiTimer <= 0 {
                let away = V2(pos.x - player.x, pos.z - player.z)
                yaw = atan2f(-away.x, -away.y) + Float.random(in: -0.7...0.7)
                aiTimer = 0.6
            }
        } else if aiTimer <= 0 {
            moving.toggle()
            if moving { yaw += Float.random(in: -2...2); aiTimer = Float.random(in: 1.5...4) }
            else { aiTimer = Float.random(in: 2...7) }
        }
        var speed: Float = moving ? (panic > 0 ? (kind == .chicken ? 2.4 : 2.8) : 1.0) : 0

        let feetBlock = w.block(Int(floor(pos.x)), Int(floor(pos.y + 0.2)), Int(floor(pos.z)))
        let inWater = Blocks.isLiquid(feetBlock)
        if speed > 0 && onGround {
            // Don't walk off drops higher than 2 blocks or into water.
            let a = pos + forward * (kind.halfW + 0.45)
            let wet = Blocks.isLiquid(w.block(Int(floor(a.x)), Int(floor(pos.y - 0.5)), Int(floor(a.z))))
                || Blocks.isLiquid(w.block(Int(floor(a.x)), Int(floor(pos.y + 0.2)), Int(floor(a.z))))
            let drop = !solid(a.x, pos.y - 0.5, a.z, w) && !solid(a.x, pos.y - 1.5, a.z, w) && !solid(a.x, pos.y - 2.5, a.z, w)
            if wet || drop {
                yaw += .pi * Float.random(in: 0.6...1.4)
                if panic <= 0 { speed = 0; moving = false; aiTimer = Float.random(in: 1...3) }
            }
        }

        let target = forward * speed
        let k = 1 - expf(-(onGround ? 12 : 3) * dt)
        vel.x += (target.x - vel.x) * k
        vel.z += (target.z - vel.z) * k
        if inWater {
            vel.y += 18 * dt
            vel.y = min(vel.y, 1.6)
            vel.y *= expf(-2 * dt)
        } else {
            vel.y -= 28 * dt
            if kind == .chicken { vel.y = max(vel.y, -3.5) } // flaps its wings
            vel.y = max(vel.y, -40)
        }

        let dist = max(abs(vel.x), abs(vel.y), abs(vel.z)) * dt
        let steps = max(1, Int(ceil(dist / 0.4)))
        let sdt = dt / Float(steps)
        var landed = false, bumped = false
        for _ in 0..<steps {
            if moveAxis(1, vel.y * sdt, w) { if vel.y < 0 { landed = true }; vel.y = 0 }
            if moveAxis(0, vel.x * sdt, w) { vel.x = 0; bumped = true }
            if moveAxis(2, vel.z * sdt, w) { vel.z = 0; bumped = true }
        }
        onGround = landed || (vel.y <= 0 && collides(pos - V3(0, 0.06, 0), w))
        if bumped && onGround && speed > 0 { vel.y = 7.4 } // hop up one block
        if pos.y < -10 { health = 0 }

        let hs = simd_length(V2(vel.x, vel.z))
        walkPhase += hs * dt * 5.5
        walkAmount += (min(1, hs / 1.2) - walkAmount) * min(1, dt * 8)
    }

    func hit(from src: V3, damage: Int) {
        health -= damage
        hurt = 0.4
        panic = 5
        aiTimer = 0
        var away = pos - src
        away.y = 0
        let l = simd_length(away)
        away = l > 0.01 ? away / l : forward
        vel += away * 5.5 + V3(0, 5, 0)
    }

    // Ray vs AABB (slab test); returns the entry distance.
    func rayHit(_ o: V3, _ d: V3, maxDist: Float) -> Float? {
        let mn = V3(pos.x - kind.halfW, pos.y, pos.z - kind.halfW)
        let mx = V3(pos.x + kind.halfW, pos.y + kind.height, pos.z + kind.halfW)
        var t0: Float = 0, t1 = maxDist
        for a in 0..<3 {
            if abs(d[a]) < 1e-6 {
                if o[a] < mn[a] || o[a] > mx[a] { return nil }
                continue
            }
            var ta = (mn[a] - o[a]) / d[a], tb = (mx[a] - o[a]) / d[a]
            if ta > tb { swap(&ta, &tb) }
            t0 = max(t0, ta)
            t1 = min(t1, tb)
            if t0 > t1 { return nil }
        }
        return t0
    }
}

// MARK: Models

private struct Part {
    var mn: V3, mx: V3       // model-space box in pixels (1/16 block); model faces -Z
    var pivot: V3 = .zero
    var rotX: Float = 0
    var color: V3
    var pattern: Float = 0   // 0 plain, 1 cow patches, 2 wool, 3 feathers
}

private func parts(_ m: Mob) -> [Part] {
    let swing = sinf(m.walkPhase) * 0.7 * m.walkAmount
    func leg(_ x: Float, _ z: Float, _ w: Float, _ h: Float, _ ph: Float, _ c: V3, _ pat: Float = 0) -> Part {
        Part(mn: V3(x - w / 2, 0, z - w / 2), mx: V3(x + w / 2, h, z + w / 2), pivot: V3(x, h, z), rotX: swing * ph, color: c, pattern: pat)
    }
    let black = V3(0.06, 0.06, 0.06)
    switch m.kind {
    case .cow:
        let hide = V3(0.36, 0.24, 0.16)
        return [
            Part(mn: V3(-6, 12, -9), mx: V3(6, 22, 9), color: hide, pattern: 1),
            Part(mn: V3(-4, 15, -15), mx: V3(4, 23, -9), pivot: V3(0, 19, -9), color: hide, pattern: 1),
            Part(mn: V3(-2.5, 15.5, -15.6), mx: V3(2.5, 18.5, -15), color: V3(0.82, 0.6, 0.55)),
            Part(mn: V3(-5, 21, -13), mx: V3(-4, 24, -12), color: V3(0.85, 0.82, 0.72)),
            Part(mn: V3(4, 21, -13), mx: V3(5, 24, -12), color: V3(0.85, 0.82, 0.72)),
            Part(mn: V3(-3.2, 20, -15.2), mx: V3(-1.8, 21.2, -15), color: black),
            Part(mn: V3(1.8, 20, -15.2), mx: V3(3.2, 21.2, -15), color: black),
            leg(-3.5, -6, 4, 12, 1, hide, 1), leg(3.5, -6, 4, 12, -1, hide, 1),
            leg(-3.5, 6, 4, 12, -1, hide, 1), leg(3.5, 6, 4, 12, 1, hide, 1),
        ]
    case .sheep:
        let wool = V3(0.9, 0.89, 0.86), skin = V3(0.72, 0.62, 0.52)
        return [
            Part(mn: V3(-6, 11, -8), mx: V3(6, 22, 8), color: wool, pattern: 2),
            Part(mn: V3(-3, 15, -14), mx: V3(3, 21, -7), pivot: V3(0, 18, -7), color: skin),
            Part(mn: V3(-3.5, 19.5, -12.5), mx: V3(3.5, 22, -7), color: wool, pattern: 2),
            Part(mn: V3(-2.5, 18, -14.2), mx: V3(-1.2, 19.2, -14), color: black),
            Part(mn: V3(1.2, 18, -14.2), mx: V3(2.5, 19.2, -14), color: black),
            leg(-3, -5, 3.5, 12, 1, skin), leg(3, -5, 3.5, 12, -1, skin),
            leg(-3, 5, 3.5, 12, -1, skin), leg(3, 5, 3.5, 12, 1, skin),
        ]
    case .chicken:
        let white = V3(0.95, 0.94, 0.9), orange = V3(0.95, 0.6, 0.15)
        let flap = m.onGround ? 0 : sinf(m.walkPhase * 6 + Float(m.hurt) * 30) * 0.9
        return [
            Part(mn: V3(-3, 5, -4), mx: V3(3, 11, 4), color: white, pattern: 3),
            Part(mn: V3(-2, 9, -7), mx: V3(2, 15, -4), pivot: V3(0, 11, -4), color: white, pattern: 3),
            Part(mn: V3(-2, 11.5, -9), mx: V3(2, 13, -7), color: orange),
            Part(mn: V3(-1, 9.5, -8), mx: V3(1, 11.5, -7), color: V3(0.85, 0.12, 0.1)),
            Part(mn: V3(-2.2, 13, -7.2), mx: V3(-1.2, 14, -7), color: black),
            Part(mn: V3(1.2, 13, -7.2), mx: V3(2.2, 14, -7), color: black),
            Part(mn: V3(-4, 6, -3), mx: V3(-3, 10, 3), pivot: V3(-3, 10, 0), rotX: flap, color: white, pattern: 3),
            Part(mn: V3(3, 6, -3), mx: V3(4, 10, 3), pivot: V3(3, 10, 0), rotX: -flap, color: white, pattern: 3),
            leg(-1.5, 0.5, 1, 5, 1, orange), leg(1.5, 0.5, 1, 5, -1, orange),
        ]
    }
}

// Writes the mob triangles (camera-relative) into `out`; returns the vertex count written.
func writeMobVertices(_ mobs: [Mob], eye: V3, daylight: Float, world: World,
                      into out: UnsafeMutablePointer<MobVert>, capacity: Int) -> Int {
    let CT = Mesher.cornerTable
    let faceShade: [Float] = [0.8, 0.8, 1.0, 0.55, 0.68, 0.68]
    let order = [0, 1, 2, 0, 2, 3]
    var n = 0
    for m in mobs {
        // Brightness: open sky gets full daylight, covered spots half (no stored light to sample).
        var covered = false
        let bx = Int(floor(m.pos.x)), bz = Int(floor(m.pos.z))
        var y = Int(floor(m.pos.y + m.kind.height)) + 1
        while y < CH { if Blocks.sky[Int(world.block(bx, y, bz))] { covered = true; break }; y += 1 }
        let bright = max(0.06, daylight * (covered ? 0.55 : 1))
        let cy = cosf(m.yaw), sy = sinf(m.yaw)
        let base = m.pos - eye
        let tint = m.hurt > 0 ? V3(1, 0.45, 0.45) : V3(1, 1, 1)
        for p in parts(m) {
            if n + 36 > capacity { return n }
            let ca = cosf(p.rotX), sa = sinf(p.rotX)
            let size = p.mx - p.mn
            for f in 0..<6 {
                for k in order {
                    let ci = (f * 4 + k) * 3
                    let lp = p.mn + size * V3(Float(CT[ci]), Float(CT[ci + 1]), Float(CT[ci + 2]))
                    var q = lp - p.pivot
                    q = V3(q.x, q.y * ca - q.z * sa, q.y * sa + q.z * ca) + p.pivot
                    q /= 16
                    let r = V3(cy * q.x + sy * q.z, q.y, -sy * q.x + cy * q.z) + base
                    out[n] = MobVert(pos: V4(r, p.pattern), color: V4(p.color * tint, faceShade[f] * bright), local: V4(lp, 0))
                    n += 1
                }
            }
        }
    }
    return n
}

// MARK: Manager

final class MobManager {
    var mobs: [Mob] = []
    static let cap = 20
    private var spawnTimer: Float = 2

    func update(_ dt: Float, game: Game) {
        let w = game.world
        let p = game.player.pos
        for m in mobs {
            m.update(dt, world: w, player: p)
            if m.callTimer <= 0 {
                m.callTimer = Float.random(in: 10...28)
                game.sfx(m.kind.call, 0.7, at: m.pos + V3(0, m.kind.height * 0.8, 0))
            }
        }
        // Despawn dead mobs and ones that drifted out of the loaded area.
        let limit = Float((w.renderDistance + 1) * CS)
        mobs.removeAll { m in
            m.health <= 0 || abs(m.pos.x - p.x) > limit || abs(m.pos.z - p.z) > limit
                || !w.isLoaded(Int(floor(m.pos.x)), Int(floor(m.pos.z)))
        }
        spawnTimer -= dt
        if spawnTimer <= 0 {
            spawnTimer = 1.5
            if mobs.count < MobManager.cap { trySpawnGroup(game) }
        }
    }

    // Surface y (feet) at a column if it's grass with two free blocks above, else nil.
    func grassSurface(_ w: World, _ x: Int, _ z: Int) -> Int? {
        var y = CH - 2
        while y > 1 && !Blocks.collide[Int(w.block(x, y, z))] && !Blocks.isLiquid(w.block(x, y, z)) { y -= 1 }
        guard w.block(x, y, z) == GRASS else { return nil }
        let a = w.block(x, y + 1, z), b = w.block(x, y + 2, z)
        guard !Blocks.collide[Int(a)] && !Blocks.collide[Int(b)] && !Blocks.isLiquid(a) else { return nil }
        return y + 1
    }

    func trySpawnGroup(_ game: Game) {
        let w = game.world
        let rd = min(w.renderDistance, 6)
        guard rd >= 3 else { return }
        let pcx = floorDiv(Int(floor(game.player.pos.x)), CS), pcz = floorDiv(Int(floor(game.player.pos.z)), CS)
        let dx = Int.random(in: -rd...rd), dz = Int.random(in: -rd...rd)
        if max(abs(dx), abs(dz)) < 2 { return } // never pop in right next to the player
        guard let c = w.chunks[ChunkKey(x: pcx + dx, z: pcz + dz)], c.meshedVersion >= 0 else { return }
        let x = c.cx * CS + Int.random(in: 2..<(CS - 2)), z = c.cz * CS + Int.random(in: 2..<(CS - 2))
        guard grassSurface(w, x, z) != nil else { return }
        let kind: MobKind
        let r = Float.random(in: 0..<1)
        switch w.gen.column(x, z).biome {
        case .plains: kind = r < 0.45 ? .cow : (r < 0.8 ? .sheep : .chicken)
        case .forest: kind = r < 0.4 ? .chicken : (r < 0.7 ? .cow : .sheep)
        case .snowy, .mountains: kind = .sheep
        default: return
        }
        for _ in 0..<Int.random(in: 2...4) {
            let sx = x + Int.random(in: -2...2), sz = z + Int.random(in: -2...2)
            guard let y = grassSurface(w, sx, sz) else { continue }
            mobs.append(Mob(kind, at: V3(Float(sx) + 0.5, Float(y), Float(sz) + 0.5)))
            if mobs.count >= MobManager.cap { break }
        }
    }

    // Nearest mob along a ray.
    func raycast(_ o: V3, _ d: V3, maxDist: Float) -> (Mob, Float)? {
        var best: (Mob, Float)?
        for m in mobs {
            if let t = m.rayHit(o, d, maxDist: maxDist), t < (best?.1 ?? .greatestFiniteMagnitude) { best = (m, t) }
        }
        return best
    }
}
