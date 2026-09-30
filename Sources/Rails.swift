import Foundation
import simd

// Rail shapes, auto-shaping and minecart movement.
// Shapes: 0 N-S, 1 E-W, 2 ascending east, 3 ascending west, 4 ascending north, 5 ascending south,
//         6 curve S-E, 7 curve S-W, 8 curve N-W, 9 curve N-E (curves only for plain rails).
enum Rails {
    // Two exits per shape: (dx, dy, dz); dy = 1 on the raised end of a slope.
    static let exits: [[(Int, Int, Int)]] = [
        [(0, 0, -1), (0, 0, 1)], [(1, 0, 0), (-1, 0, 0)], [(1, 1, 0), (-1, 0, 0)], [(-1, 1, 0), (1, 0, 0)],
        [(0, 1, -1), (0, 0, 1)], [(0, 1, 1), (0, 0, -1)],
        [(0, 0, 1), (1, 0, 0)], [(0, 0, 1), (-1, 0, 0)], [(0, 0, -1), (-1, 0, 0)], [(0, 0, -1), (1, 0, 0)],
    ]

    static func isRail(_ b: BlockID) -> Bool { Blocks.shape[Int(b)] == "rail" }
    static func plain(_ b: BlockID) -> Bool { Circuit.kind(b) == .rail }
    static func shape(_ b: BlockID) -> Int {
        let s = Int(b - Blocks.groupBase[Int(b)])
        return plain(b) ? s : s % 6
    }
    static func with(_ b: BlockID, shape: Int) -> BlockID {
        let base = Blocks.groupBase[Int(b)]
        if plain(b) { return base + BlockID(shape) }
        let on = Int(b - base) >= 6
        return base + BlockID(min(shape, 5) + (on ? 6 : 0))
    }

    // Rail next to p in horizontal direction (dx, dz): same level, one up or one down.
    static func neighbour(_ w: World, _ p: IVec3, _ dx: Int, _ dz: Int) -> IVec3? {
        for dy in [0, 1, -1] {
            let q = IVec3(p.x + dx, p.y + dy, p.z + dz)
            if isRail(w.block(q.x, q.y, q.z)) { return q }
        }
        return nil
    }

    // Picks the shape for the rail at p from the rails around it, then lets the neighbours turn to it.
    static func autoShape(_ w: World, _ p: IVec3, recurse: Bool = true) {
        let b = w.block(p.x, p.y, p.z)
        guard isRail(b) else { return }
        let dirs = [(0, -1), (0, 1), (-1, 0), (1, 0)]       // N S W E
        var conn: [Int] = []
        for (k, d) in dirs.enumerated() where neighbour(w, p, d.0, d.1) != nil { conn.append(k) }
        var shape = shape(b)
        func up(_ k: Int) -> Bool { let d = dirs[k]; return isRail(w.block(p.x + d.0, p.y + 1, p.z + d.1)) }
        let ns = conn.contains(0) || conn.contains(1), ew = conn.contains(2) || conn.contains(3)
        if conn.count >= 2 && plain(b) && ns && ew {
            let n = conn.contains(0), s = conn.contains(1), wv = conn.contains(2), e = conn.contains(3)
            if s && e { shape = 6 } else if s && wv { shape = 7 } else if n && wv { shape = 8 } else if n && e { shape = 9 }
        } else if ns && !ew || (ns && !plain(b)) {
            shape = up(0) ? 4 : (up(1) ? 5 : 0)
        } else if ew {
            shape = up(3) ? 2 : (up(2) ? 3 : 1)
        }
        let nb = with(b, shape: shape)
        if nb != b { w.setBlock(p.x, p.y, p.z, nb) }
        if recurse { for d in dirs { if let q = neighbour(w, p, d.0, d.1) { autoShape(w, q, recurse: false) } } }
    }
}

extension Mob {
    // Minecart: follows rails, rolls down slopes, is pushed by powered rails and braked by unpowered
    // ones, carries the player; off the rails it is just a box that falls and slides.
    func updateMinecart(_ dt: Float, _ g: Game) {
        let w = g.world
        let riding = g.riding === self
        var cell = IVec3(Int(floor(pos.x)), Int(floor(pos.y + 0.1)), Int(floor(pos.z)))
        var b = w.block(cell.x, cell.y, cell.z)
        if !Rails.isRail(b) {
            let below = IVec3(cell.x, cell.y - 1, cell.z)
            let bb = w.block(below.x, below.y, below.z)
            if Rails.isRail(bb) { cell = below; b = bb }
        }
        if Rails.isRail(b) {
            let shape = Rails.shape(b)
            let e = Rails.exits[shape]
            let base = V3(Float(cell.x) + 0.5, Float(cell.y) + 0.0625, Float(cell.z) + 0.5)
            let A = base + V3(Float(e[0].0) * 0.5, Float(e[0].1), Float(e[0].2) * 0.5)
            let B = base + V3(Float(e[1].0) * 0.5, Float(e[1].1), Float(e[1].2) * 0.5)
            let axis = simd_normalize(B - A)
            var s = simd_dot(vel, axis)
            // Gravity along slopes.
            s -= axis.y * 5 * dt
            let k = Circuit.kind(b)
            let on = Int(b - Blocks.groupBase[Int(b)]) >= 6
            if k == .poweredRail {
                if on {
                    if abs(s) < 0.2 {
                        // Start moving away from a solid block at one end.
                        let back = cell - IVec3(e[0].0, 0, e[0].2)
                        s = Blocks.opaque[Int(w.block(back.x, back.y, back.z))] ? -2 : 2
                    } else { s += (s > 0 ? 1 : -1) * 24 * dt }
                } else {
                    s *= expf(-12 * dt)
                    if abs(s) < 0.3 { s = 0 }
                }
            } else if k == .activatorRail && on && riding {
                g.dismount()
            }
            if riding {
                // The rider can nudge the cart along its look direction.
                let look = V3(-sinf(g.player.yaw), 0, -cosf(g.player.yaw))
                s += simd_dot(look, axis) * g.riderPush * 2 * dt
            }
            s *= powf(riding ? 0.997 : 0.96, dt * 20)
            s = max(-8, min(8, s))
            var np = pos + axis * s * dt
            let t = simd_dot(np - A, axis)
            np = A + axis * t
            // Stop at a wall past the hollow of the track.
            if collides(np + V3(0, 0.1, 0), w) { s = 0 } else { pos = np }
            vel = axis * s
            if abs(s) > 0.05 { yaw = atan2f(-axis.x * (s > 0 ? 1 : -1), -axis.z * (s > 0 ? 1 : -1)) }
            onGround = true
        } else {
            vel.y -= 28 * dt
            if onGround { vel.x *= expf(-6 * dt); vel.z *= expf(-6 * dt) }
            let hit = w.moveBody(&pos, halfW: halfW, height: height, vel * dt, step: 0, onGround: onGround)
            if hit.y { onGround = vel.y < 0; vel.y = 0 } else { onGround = false }
            if hit.x { vel.x = 0 }
            if hit.z { vel.z = 0 }
        }
        walkPhase += simd_length(vel) * dt
        if riding {
            g.player.pos = pos + V3(0, 0.35, 0)
            g.player.vel = .zero
            g.player.airPeak = g.player.pos.y
        }
    }
}

extension Game {
    func dismount() {
        guard let cart = riding else { return }
        riding = nil
        player.pos = cart.pos + V3(0, 1, 0)
        player.vel = .zero
        player.airPeak = player.pos.y
    }
}
