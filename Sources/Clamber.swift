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
    // Nov 13 (his notes Nov 1 15:44 in a crater, "double jump to grab", Nov 2 08:31 and Nov 13 "Did we ever get that
    // double jump to climb over thing?"; backlog 15, "big one, missed twice"): the grab. The clamber above took jump
    // HELD while pushing into the ledge and reached 2.3 blocks from where he stood: not what he does, and not out of a
    // crater. A second press of jump in the air (the double jump) grabs a ledge in front of him: its top up to 2.2
    // blocks over his feet as they are then (his hands over his head at the top of a jump: a wall three blocks high
    // from the ground), up to 1.2 blocks ahead, toward the stick if it is pushed and the way he faces if not. No
    // ledge there, and in creative the double tap toggles flying as before. BS_OLDCLAMBER=1: the held clamber only.
    static let grabOn = ProcessInfo.processInfo.environment["BS_OLDCLAMBER"] != "1"
    static let grabHigh: Float = 2.2, grabLow: Float = 0.4, grabTotal: Float = 3.75, grabAhead: Float = 1.2
    static var grabs = 0                                      // (checks)

    // The second press of jump in the air: true when a ledge was taken (Game: then no flight toggle).
    func tryGrab(_ w: World) -> Bool {
        guard Player.grabOn, clamber == nil, !onGround, !flying, !inWater, !inLava, !prone, !gliding, levitate <= 0, !jetThrust else { return false }
        let dir = simd_length(lastWish) > 0.3 ? lastWish : lastFacing
        guard startClamber(dir, w, grab: true) else { return false }
        Player.grabs += 1
        return true
    }

    // Starts a clamber toward `wish` (horizontal push) when a ledge is there to take; false when there is none.
    func startClamber(_ wish: V3, _ w: World, grab: Bool = false) -> Bool {
        let d2 = V2(wish.x, wish.z), l = simd_length(d2)
        guard l > 1e-3 else { return false }
        let dir = V3(d2.x / l, 0, d2.y / l)
        // (something in his way: right against him, or for a grab within reach of his arms)
        var gap: Float = 0
        if !collides(at: pos + dir * 0.3, w) {
            guard grab else { return false }
            var found = false
            var r: Float = 0.45
            while r <= Player.grabAhead + 0.001 {
                if collides(at: pos + dir * r, w) { gap = r - 0.3; found = true; break }
                r += 0.15
            }
            // (already over its top, feet in the air just short of it: the ledge under his feet ahead)
            if !found {
                guard collides(at: pos + dir * 0.6 - V3(0, 0.6, 0), w), !collides(at: pos + dir * 0.6, w) else { return false }
            }
        }
        let ahead = pos + dir * (gap + halfW + 0.55)
        // The ledge's top: the lowest height where his body stands clear just past the face, on something.
        var top: Float? = nil
        var y = pos.y + (grab ? 0.0 : 0.5)
        // (a jump first doesn't lift the held clamber's reach; a grab reaches from his feet in the air)
        let reach = grab ? min(pos.y + Player.grabHigh, clamberBase + Player.grabTotal) : min(pos.y, clamberBase) + Player.clamberHigh
        while y <= reach + 0.001 {
            let probe = V3(ahead.x, y, ahead.z)
            if !collides(at: probe, w) {
                if collides(at: probe - V3(0, 0.15, 0), w) { top = y }
                break
            }
            y += 0.125
        }
        guard let t = top, t - pos.y >= (grab ? Player.grabLow : Player.clamberLow) else { return false }
        // Room to rise straight up the face, and to move over onto the top.
        let up = V3(pos.x, t + 0.02, pos.z)
        guard !collides(at: up, w), !collides(at: V3(pos.x, (pos.y + t) * 0.5, pos.z), w),
              !collides(at: (up + V3(ahead.x, t + 0.02, ahead.z)) * 0.5, w) else { return false }
        clamber = (0, pos, V3(ahead.x, t + 0.02, ahead.z))
        // (a short pull is quick, a full reach takes the old time and a little more)
        clamberDur = max(0.3, min(0.6, 0.2 + 0.11 * (t - pos.y) + 0.12 * gap))
        vel = .zero
        Player.clambers += 1
        return true
    }

    // One step of a clamber under way (Player.update, in place of walking).
    func stepClamber(_ dt: Float, _ w: World) {
        guard var c = clamber else { return }
        c.t = min(1, c.t + dt / clamberDur)
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
        // (Nov 13, the grab: a jump, then jump pressed again in the air)
        func grab(_ wall: Int, push: Bool) -> (V3, Int) {
            lane()
            for x in 3...11 { for z in -2...2 { for dy in 0..<wall { put(cx + x, y + dy, cz + z, STONE) } } }
            p.flying = false; p.vel = .zero; p.clamber = nil; p.yaw = -Float.pi / 2; p.moveYaw = nil; p.moveLook = nil
            p.pos = V3(Float(cx) + 2.0, Float(y), Float(cz) + 0.5)                  // (half a block short of the wall)
            for _ in 0..<20 { p.update(dt: 1.0 / 72, input: MoveInput(), world: w) }
            let n0 = Player.grabs
            var inp = MoveInput(); inp.forward = push ? 1 : 0; inp.jump = true
            for _ in 0..<5 { p.update(dt: 1.0 / 72, input: inp, world: w) }
            inp.jump = false
            for _ in 0..<10 { p.update(dt: 1.0 / 72, input: inp, world: w) }
            inp.jump = true
            for _ in 0..<3 { p.update(dt: 1.0 / 72, input: inp, world: w) }
            inp.jump = false
            for _ in 0..<72 { p.update(dt: 1.0 / 72, input: inp, world: w) }
            return (p.pos, Player.grabs - n0)
        }
        let (g3, ng3) = grab(3, push: true), (g3s, ng3s) = grab(3, push: false), (g4, ng4) = grab(4, push: true)
        check(g3.y >= Float(y) + 2.95 && g3.x > Float(cx) + 3.2 && ng3 == 1 && g3s.y >= Float(y) + 2.95 && ng3s == 1 && g4.y < Float(y) + 0.5 && ng4 == 0,
              String(format: "clamber: a jump and a second press of jump in the air takes him onto a wall three high (feet %.2f, %d grabs; stick let go %.2f, %d), not one four high (%.2f, %d)",
                     g3.y - Float(y), ng3, g3s.y - Float(y), ng3s, g4.y - Float(y), ng4))
        let (three, _) = run(3, roof: false)
        let (roofed, _) = run(2, roof: true)
        check(three.y < Float(y) + 0.5 && roofed.y < Float(y) + 0.5,
              String(format: "clamber: a wall three high stays out of reach (feet %.2f) and so does one with no room on top (%.2f)",
                     three.y - Float(y), roofed.y - Float(y)))
    }
}

// P511: the crawler's interior as built (Capital.crawlerDense): a drive motor at each of the six wheels, a trunk with a
// hoist under each of the three mounts, the command deck split in three, its air a good part filled, and no run of
// more than a dozen open cells down its middle.
enum CrawlerInteriorCheck {
    static func run(_ check: (Bool, String) -> Void) {
        let hb = Capital.crawler()
        let engine = Capital.id("ship_engine"), hoist = Capital.id(ShipShells.hoistKey, AIR), armour = Capital.id("warship_hull")
        var motors = 0
        for zc in [18, 41, 64] { for sx in [-1, 1] where (10...11).allSatisfy({ y in hb.get(sx * 10, y, zc) == engine }) { motors += 1 } }
        var trunks = 0, hoists = 0
        for zc in [32, 54, 63] {
            if (22...24).allSatisfy({ hb.get(0, $0, zc) == armour }) { trunks += 1 }
            if hb.get(0, 22, zc - 2) == hoist { hoists += 1 }
        }
        var air = 0, filled = 0, run = 0, longest = 0
        for z in 22...65 {
            for y in 22...26 { for x in -7...7 { let b = hb.get(x, y, z); if b == AIR { air += 1 } else if Blocks.collide[Int(b)] { filled += 1 } } }
            if hb.get(0, 23, z) == AIR { run += 1; longest = max(longest, run) } else { run = 0 }
        }
        // (the share over the deck's whole air, rows 22-26: the two aisles, three wide of its fifteen, and the headroom
        // over the fittings stay open by design, so a fully fitted deck is about a fifth filled: 18% as built)
        let share = Float(filled) / Float(max(1, air + filled))
        let bulkheads = [37, 49].filter { z in (-7...7).filter { hb.get($0, 23, z) != AIR }.count >= 10 }.count
        check(motors == 6 && trunks == 3 && hoists == 3 && bulkheads == 2 && share > 0.15 && longest <= 12,
              String(format: "crawler inside: %d of 6 wheels with a drive motor, %d of 3 mounts with a trunk (%d hoists), %d bulkheads across the command deck, %.0f%% of its air filled, its longest open run down the middle %d cells",
                     motors, trunks, hoists, bulkheads, share * 100, longest))
    }
}
