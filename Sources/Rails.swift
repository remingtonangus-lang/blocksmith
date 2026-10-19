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

    // Does the rail at n have an exit pointing at q's column?
    static func pointsTo(_ w: World, _ n: IVec3, _ q: IVec3) -> Bool {
        let nb = w.block(n.x, n.y, n.z)
        guard isRail(nb) else { return false }
        for e in exits[shape(nb)] where n.x + e.0 == q.x && n.z + e.2 == q.z { return true }
        return false
    }

    // Both ends of the rail at n already run into rails that run back into it (reference canConnectTo: such a rail
    // keeps its shape when a rail is laid beside it).
    static func full(_ w: World, _ n: IVec3) -> Bool {
        let nb = w.block(n.x, n.y, n.z)
        guard isRail(nb) else { return false }
        var c = 0
        for e in exits[shape(nb)] {
            if let m = neighbour(w, n, e.0, e.2), pointsTo(w, m, n) { c += 1 }
        }
        return c >= 2
    }

    // Picks the shape for the rail at p from the rails around it, then lets the neighbours turn to it (W6, reference
    // RailState): only rails already pointing at it or with a free end connect (connected rails keep their shape); a
    // plain rail at a T or a cross takes the south-east curve first, or north-west first while powered; slopes rise
    // to a rail one block up.
    static func autoShape(_ w: World, _ p: IVec3, recurse: Bool = true, powered: Bool? = nil) {
        let b = w.block(p.x, p.y, p.z)
        guard isRail(b) else { return }
        let dirs = [(0, -1), (0, 1), (-1, 0), (1, 0)]       // N S W E
        var link = [false, false, false, false]
        for (k, d) in dirs.enumerated() {
            if let q = neighbour(w, p, d.0, d.1), pointsTo(w, q, p) || !full(w, q) { link[k] = true }
        }
        let n = link[0], s = link[1], wv = link[2], e = link[3]
        let isPlain = plain(b)
        let on = powered ?? (w.redstone.received(p) > 0)
        func up(_ k: Int) -> Bool { let d = dirs[k]; return isRail(w.block(p.x + d.0, p.y + 1, p.z + d.1)) }
        let ns = n || s, ew = wv || e
        var shape: Int?
        if ns && !ew { shape = 0 }
        if ew && !ns { shape = 1 }
        if isPlain {
            if s && e && !n && !wv { shape = 6 }
            if s && wv && !n && !e { shape = 7 }
            if n && wv && !s && !e { shape = 8 }
            if n && e && !s && !wv { shape = 9 }
            if shape == nil {
                // Junction priority: each later match wins.
                if on {
                    if s && e { shape = 6 }; if s && wv { shape = 7 }; if n && e { shape = 9 }; if n && wv { shape = 8 }
                } else {
                    if n && wv { shape = 8 }; if n && e { shape = 9 }; if s && wv { shape = 7 }; if s && e { shape = 6 }
                }
            }
        } else if shape == nil && ns && ew {
            // A straight-only rail at a junction keeps its axis (north-south if it had none).
            shape = Rails.shape(b) == 1 || Rails.shape(b) == 2 || Rails.shape(b) == 3 ? 1 : 0
        }
        if shape == 0 { shape = up(0) ? 4 : (up(1) ? 5 : 0) }
        if shape == 1 { shape = up(3) ? 2 : (up(2) ? 3 : 1) }
        let nb = with(b, shape: shape ?? Rails.shape(b))
        if nb != b { w.setBlock(p.x, p.y, p.z, nb) }
        guard recurse else { return }
        // The rails it now runs into turn toward it if they have a free end.
        for ex in exits[Rails.shape(nb)] {
            if let q = neighbour(w, p, ex.0, ex.2), !pointsTo(w, q, p), !full(w, q) { autoShape(w, q, recurse: false) }
        }
    }

    // W6: power reaching or leaving a plain rail with three rails around it swaps the junction's curve (reference
    // RailBlock.updateState).
    static func junctionSwitch(_ w: World, _ p: IVec3, powered: Bool) {
        let b = w.block(p.x, p.y, p.z)
        guard plain(b) else { return }
        var around = 0
        for d in [(0, -1), (0, 1), (-1, 0), (1, 0)] where neighbour(w, p, d.0, d.1) != nil { around += 1 }
        guard around == 3 else { return }
        autoShape(w, p, recurse: false, powered: powered)
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
                        s = w.opaqueAt(back.x, back.y, back.z) ? -2 : 2
                    } else { s += (s > 0 ? 1 : -1) * 24 * dt }
                } else {
                    s *= expf(-12 * dt)
                    if abs(s) < 0.3 { s = 0 }
                }
            } else if k == .activatorRail && on && riding {
                g.dismount()
            }
            var cap: Float = 8
            if riding {
                // The rider can nudge the cart along its look direction.
                let look = V3(-sinf(g.player.yaw), 0, -cosf(g.player.yaw))
                if variant == Carts.engine {
                    // The engine cart drives (P132): throttle on the stick, burning fuel while it pulls.
                    let along: Float = simd_dot(look, axis) >= 0 ? 1 : -1
                    let throttle = g.riderPush
                    if jobTimer > 0 && abs(throttle) > 0.1 {
                        s += along * throttle * Carts.engineAccel * dt
                        let wasFuelled = jobTimer > 0
                        jobTimer = max(0, jobTimer - dt * abs(throttle))
                        if wasFuelled && jobTimer <= 0 { g.onToast?("The engine is out of fuel") }
                        if Rand.float(in: 0..<1) < dt * 10 { g.particles.smoke(at: pos + V3(0, 1.2, 0) - axis * 0.3, dark: true) }
                    } else if abs(throttle) > 0.1 { s += along * throttle * 2 * dt }
                    cap = shape >= 6 ? Carts.engineCurve : Carts.engineTop
                } else {
                    s += simd_dot(look, axis) * g.riderPush * 2 * dt
                }
            }
            s *= powf(riding ? 0.997 : 0.96, dt * 20)
            s = max(-cap, min(cap, s))
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
            g.cartLayTrack(self)
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
        // P49: a ridden horse is narrower than a loose one; left in a gap only the rider's width fits through, it
        // would be stuck in the trunks, so it steps out to the nearest spot it fits.
        if cart.gaited, cart.collides(cart.pos, world) {
            let p = world.freeSpawn(cart.pos, wide: true)
            if !cart.collides(p, world) { cart.pos = p }
        }
        player.pos = cart.pos + V3(0, 1, 0)
        player.vel = .zero
        player.airPeak = player.pos.y
    }
}
