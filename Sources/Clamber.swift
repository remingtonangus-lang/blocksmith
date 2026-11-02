import Foundation
import simd

// P511 (Nov 2 08:31:17-08:31:22, at a Greywall fortress: "get over something, climb over something. We gotta add that"):
// the clamber. Jumping while pushing into a ledge too high to jump onto (a wall, a crate stack, a fence, a parapet: its
// top 1.05 to 2.3 blocks over his feet) with room on top, he pulls himself up and over it: straight up the face, then
// forward onto the top, in under half a second. Nothing in the way of the rise or the top, or something moving into
// it, and he lets go. A clamber counts as no fall.
extension Player {
    static let clamberLow: Float = 1.05, clamberHigh: Float = 2.3, clamberTime: Float = 0.45
    static var clambers = 0                                   // (checks)

    // Starts a clamber toward `wish` (horizontal push) when a ledge is there to take; false when there is none.
    func startClamber(_ wish: V3, _ w: World) -> Bool {
        let d2 = V2(wish.x, wish.z), l = simd_length(d2)
        guard l > 1e-3 else { return false }
        let dir = V3(d2.x / l, 0, d2.y / l)
        guard collides(at: pos + dir * 0.3, w) else { return false }          // (something in his way)
        let ahead = pos + dir * (halfW + 0.55)
        // The ledge's top: the lowest height where his body stands clear just past the face, on something.
        var top: Float? = nil
        var y = pos.y + 0.5
        while y <= pos.y + Player.clamberHigh + 0.001 {
            let probe = V3(ahead.x, y, ahead.z)
            if !collides(at: probe, w) {
                if collides(at: probe - V3(0, 0.15, 0), w) { top = y }
                break
            }
            y += 0.125
        }
        guard let t = top, t - pos.y >= Player.clamberLow else { return false }
        // Room to rise straight up the face, and to move over onto the top.
        let up = V3(pos.x, t + 0.02, pos.z)
        guard !collides(at: up, w), !collides(at: V3(pos.x, (pos.y + t) * 0.5, pos.z), w),
              !collides(at: (up + V3(ahead.x, t + 0.02, ahead.z)) * 0.5, w) else { return false }
        clamber = (0, pos, V3(ahead.x, t + 0.02, ahead.z))
        vel = .zero
        Player.clambers += 1
        return true
    }

    // One step of a clamber under way (Player.update, in place of walking).
    func stepClamber(_ dt: Float, _ w: World) {
        guard var c = clamber else { return }
        c.t = min(1, c.t + dt / Player.clamberTime)
        let rise = min(1, c.t / 0.6), across = max(0, (c.t - 0.6) / 0.4)
        let ey = 1 - (1 - rise) * (1 - rise)
        let p = V3(c.from.x + (c.to.x - c.from.x) * across, c.from.y + (c.to.y - c.from.y) * ey,
                   c.from.z + (c.to.z - c.from.z) * across)
        vel = .zero
        airPeak = max(p.y, pos.y)
        if collides(at: p, w) { clamber = nil; return }              // (something moved into the way: he lets go)
        pos = p
        onGround = false
        if c.t >= 1 { clamber = nil; onGround = true } else { clamber = c }
    }
}

// The clamber's check (in the full suite): on a flat stone lane, walking into a platform two blocks high with jump held he
// ends up on top of it and past its face; a wall three high he can't get over; a wall two high with a slab over the top
// (no room) he can't either.
enum ClamberCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, p = g.player
        let pos0 = p.pos, fly0 = p.flying, yaw0 = p.yaw, my0 = p.moveYaw, ml0 = p.moveLook
        defer { p.pos = pos0; p.flying = fly0; p.yaw = yaw0; p.moveYaw = my0; p.moveLook = ml0; p.vel = .zero; p.clamber = nil }
        let cx = Int(floor(pos0.x)) / 512 * 512 - 2600, cz = Int(floor(pos0.z)) / 512 * 512 - 2600
        _ = w.loadSync(center: V3(Float(cx), 0, Float(cz)), radius: 2)
        let y = w.topY(cx, cz) + 1
        var saved: [(Int, Int, Int, BlockID)] = []
        func put(_ x: Int, _ yy: Int, _ z: Int, _ b: BlockID) { saved.append((x, yy, z, w.block(x, yy, z))); w.setBlock(x, yy, z, b) }
        func lane() {
            for x in -4...13 { for z in -2...2 {
                put(cx + x, y - 1, cz + z, STONE)
                for dy in 0..<7 { put(cx + x, y + dy, cz + z, AIR) }
            } }
        }
        defer { for (x, yy, z, b) in saved.reversed() { w.setBlock(x, yy, z, b) } }
        func run(_ wall: Int, roof: Bool) -> (V3, Int) {
            lane()
            for x in 3...11 { for z in -2...2 { for dy in 0..<wall { put(cx + x, y + dy, cz + z, STONE) } } }     // (a platform: he walks on along its top)
            if roof { for x in 3...5 { for z in -2...2 { put(cx + x, y + wall + 1, cz + z, STONE) } } }
            p.flying = false; p.vel = .zero; p.clamber = nil; p.yaw = -Float.pi / 2; p.moveYaw = nil; p.moveLook = nil
            p.pos = V3(Float(cx) + 0.5, Float(y), Float(cz) + 0.5)
            for _ in 0..<20 { p.update(dt: 1.0 / 72, input: MoveInput(), world: w) }
            let n0 = Player.clambers
            var inp = MoveInput(); inp.forward = 1; inp.jump = true
            for _ in 0..<(72 * 2) { p.update(dt: 1.0 / 72, input: inp, world: w) }
            inp.jump = false
            for _ in 0..<36 { p.update(dt: 1.0 / 72, input: inp, world: w) }
            return (p.pos, Player.clambers - n0)
        }
        let (two, n2) = run(2, roof: false)
        check(two.y >= Float(y) + 1.95 && two.x > Float(cx) + 3.2 && n2 >= 1,
              String(format: "clamber: into a wall two high with jump held he pulls himself up onto it (feet %.2f over the lane, %.1f past its face, %d clambers)",
                     two.y - Float(y), two.x - Float(cx) - 3, n2))
        let (three, _) = run(3, roof: false)
        let (roofed, _) = run(2, roof: true)
        check(three.y < Float(y) + 0.5 && roofed.y < Float(y) + 0.5,
              String(format: "clamber: a wall three high stays out of reach (feet %.2f) and so does one with no room on top (%.2f)",
                     three.y - Float(y), roofed.y - Float(y)))
    }
}
