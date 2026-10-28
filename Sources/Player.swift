import Foundation
import simd

struct MoveInput {
    var forward: Float = 0   // -1..1
    var strafe: Float = 0    // -1..1 (right positive)
    var jump = false
    var sneak = false
    var sprint = false
    var spur = false         // a fresh sprint press (riding: spurs a horse up a gait, HorseFeel.swift)
}

final class Player {
    var pos = V3(0, 100, 0)       // feet centre
    var vel = V3(0, 0, 0)
    var yaw: Float = 0
    var pitch: Float = 0
    var flying = false
    var fastFlight = true           // sprint while flying goes ~8x normal flight speed (V toggles it)
    var hyperFlight = false         // P478: creative flight with the right stick held in, ten times fast flight (Quest)
    var onGround = false
    var viewDY: Float = 0, viewDV: Float = 0        // eased step offset of the drawn eye (ViewStep.swift)
    var steadyY: Float?                             // Steady Saddle: the eased height of the saddle (ViewStep.swift)
    var steadyV: Float = 0, steadyLast: Float = 0   // its eased climb rate and the saddle height last tick
    var viewLastY: Float?, viewLastGround = false
    var viewGround: Float = 0                       // P142: eased height of the smooth ground over the block top under the feet
    var inWater = false             // water only (lava is inLava; QA: lava used to count as water)
    var inLava = false
    var headInLava = false
    var headInWater = false
    var headAt: V3?                // the headset's eye in the world (VR), for headInWater (P188)
    var sneaking = false
    var ducking = false            // VR: the user physically crouched (QuestControls.roomScale): counts as sneaking
    var sprinting = false
    var walkWant = V2(0, 0)        // P311 (a): the walk asked for this tick (blocks/s), even when a mob stops it: shoves
    var airPeak: Float = 0         // highest feet y since last touching ground/water (fall damage)
    var lastUpdatePos = V3(0, 0, 0)  // where the last update left the body (a jump of 6+ blocks is a teleport)
    var pendingFall: Float = 0     // fall distance of the last landing; Game consumes and clears it
    var jumped = false             // a ground jump started this frame
    var gliding = false            // glider wings flight
    var jetThrust = false          // jetpack thrusting this frame (set by Game.jetpackTick before update)
    var jetHold: Float = 0         // seconds jump has been held (jetpack takes over after 0.15 s)
    var jetBurn: Float = 0         // fractional fuel ticks burnt
    var jetEmptyWarned = false
    var jetBoost: Float = 0        // P322: 0...1, the thrust leaning forward (flies along jetDir instead of straight up)
    var jetDir = V3(0, 1, 0)       // ... where it thrusts (the look, or the headset's)
    var suitFuel: Float = 0        // ... the Hannibal plate's fuel buffer, in jetpack ticks (filled from the pack's coal)
    var boost: Float = 0           // firework rocket boost left (s)
    var levitate: Float = 0        // sentry bolt levitation left (s)
    var levitateAmp = 0
    var speedMul: Float = 1        // speed / slowness effects
    var gunSlow: Float = 1         // P391: a heavy gun in hand (the rotary gun)
    var jumpBoost = 0              // jump boost level
    // P417 (b) (Oct 23 21:06-21:12: up "about a block and a half", "the jump animation's too slow"): the jump rises
    // about 1.55 blocks under a stronger pull while it lasts, so the whole hop takes about 0.47 s (it was 1.3 blocks
    // in 0.61 s at 8.6 b/s under 28). Falls that aren't a jump keep the old pull.
    static let jumpG: Float = 56
    static let jumpV: Float = (2 * jumpG * 1.55).squareRoot()      // 13.2 b/s
    var jumpArc = false
    var jumpSpeed: Float { Player.jumpV + 2 * Float(jumpBoost) * Player.jumpV / 8.6 }
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
    /// Direction sprint-swimming and ladder pushing follow when it isn't the look (VR: the head, not the aiming hand).
    var moveLook: V3? = nil
    /// Yaw the walking/flying stick input is relative to when it isn't the aim yaw (VR: the head, never the hand).
    /// Set each tick by the VR controls, so nothing that turns `yaw` later in the tick (aim assist, pad look) can steer.
    var moveYaw: Float? = nil
    var wetGrace: Float = 0         // s since leaving water that the bank climb / step-up still apply (getting out over the edge)

    // Block-centred spots within 2 blocks sideways, 1 down and 2 up, nearest first (ties: level, then up).
    static let unstuckOffsets: [V3] = {
        var o: [V3] = []
        for dy in -1...2 { for dz in -2...2 { for dx in -2...2 where !(dx == 0 && dy == 0 && dz == 0) { o.append(V3(Float(dx), Float(dy), Float(dz))) } } }
        return o.sorted { a, b in
            let la = simd_length_squared(a) + (a.y < 0 ? 0.6 : 0), lb = simd_length_squared(b) + (b.y < 0 ? 0.6 : 0)
            return la < lb
        }
    }()
    static let fieldNudgeRadii: [Float] = [0.06, 0.12, 0.2, 0.3, 0.45, 0.6, 0.75]
    // (Up first: feet a hair into the floor; down: a head into a rounded ceiling's corners; then sideways and slanting.)
    static let fieldNudgeDirs: [V3] = [V3(0, 1, 0), V3(0, -1, 0)] + (0..<8).map { k in V3(cosf(Float(k) * .pi / 4), 0, sinf(Float(k) * .pi / 4)) }
        + (0..<4).map { k in simd_normalize(V3(cosf(Float(k) * .pi / 2 + .pi / 4), 1, sinf(Float(k) * .pi / 2 + .pi / 4))) }
        + (0..<4).map { k in simd_normalize(V3(cosf(Float(k) * .pi / 2 + .pi / 4), -1, sinf(Float(k) * .pi / 2 + .pi / 4))) }
    static func nearestFree(_ p: V3, _ free: (V3) -> Bool) -> V3? {
        let base = V3(floorf(p.x) + 0.5, floorf(p.y), floorf(p.z) + 0.5)
        if free(base) { return base }
        return unstuckOffsets.lazy.map { base + $0 }.first(where: free)
    }

    func collides(at p: V3, _ w: World) -> Bool {
        let was = w.foliageSoft
        w.foliageSoft = !flying                // P417 (a): standing in leaves or a limb is not being stuck in a block
        defer { w.foliageSoft = was }
        return w.collides(V3(p.x - halfW, p.y, p.z - halfW), V3(p.x + halfW, p.y + height, p.z + halfW))
    }

    // A one-block opening (a door, a gap in a wall) just ahead and to one side of where the body pushes against its
    // edge: the body slides sideways toward the opening's middle, up to 3 blocks a second and never more than 0.45, as
    // if the frame's corners were rounded. Only for a push mostly along one axis (not a glancing walk along a wall).
    static var doorwayAssistOn = true                  // (off only for the check's before-and-after)
    private func doorwayAssist(_ wish: V3, _ w: World, _ dt: Float) {
        let d = simd_normalize(V2(wish.x, wish.z))
        let alongX = abs(d.x) > abs(d.y)
        // (P475, Oct 27: "Still a little too hard to get through doors": it now takes a door met at up to 45 degrees,
        // looks further ahead, and centres the body faster)
        guard max(abs(d.x), abs(d.y)) > 0.7 else { return }
        let ahead: Float = 0.6
        let perp = alongX ? pos.z : pos.x
        let base = Int(floor(perp))
        var best: Float?
        for c in [base, base - 1, base + 1] {
            let mid = Float(c) + 0.5
            guard abs(mid - perp) < 0.55 else { continue }
            var probe = pos, there = pos
            if alongX { probe.z = mid; probe.x += d.x > 0 ? ahead : -ahead; there.z = mid }
            else { probe.x = mid; probe.z += d.y > 0 ? ahead : -ahead; there.x = mid }
            // Room in the opening ahead, and nothing in the way of the slide itself.
            guard !collides(at: probe, w), !collides(at: there, w) else { continue }
            if best == nil || abs(mid - perp) < abs(best! - perp) { best = mid }
        }
        guard let mid = best else { return }
        let step = max(-5 * dt, min(5 * dt, mid - perp))
        _ = w.moveBody(&pos, halfW: halfW, height: height, alongX ? V3(0, 0, step) : V3(step, 0, 0), step: 0, onGround: onGround)
    }

    func intersectsBlock(_ b: IVec3) -> Bool {
        let bx = Float(b.x), by = Float(b.y), bz = Float(b.z)
        return pos.x + halfW > bx && pos.x - halfW < bx + 1 &&
            pos.y + height > by && pos.y < by + 1 &&
            pos.z + halfW > bz && pos.z - halfW < bz + 1
    }

    private func groundBelow(_ p: V3, _ w: World) -> Bool {
        guard collides(at: p - V3(0, 0.06, 0), w) else { return false }
        // P386: on field ground a bank touching the body's side over the knee is not ground under it: standing needs the
        // drawn ground, or something built, within 0.06 under the feet.
        guard w.fieldTerrain && w.frame == nil, let g = w.drawnGround(p.x, p.z, lo: p.y - 2, hi: p.y + 0.5), p.y - g > 0.06 else { return true }
        return w.sweep(V3(p.x - halfW, p.y, p.z - halfW), V3(p.x + halfW, p.y + height, p.z + halfW), axis: 1, -0.06) > -0.06 + 1e-4
    }

    // P126 (Oct 12 PM, "it's possible to fall even when you're crouching"): a sneaking move is backed off 0.05 at a time
    // until the body still stands on something, each axis alone and then both together (the old per-axis test let a
    // diagonal step past a corner: each axis alone kept a toe on the block, both together left nothing under the body).
    // Also used for roomscale steps (QuestControls), which moved the body without the guard.
    func edgeClamp(_ d: V3, _ w: World) -> V3 {
        guard groundBelow(pos, w) else { return d }
        let step: Float = 0.05
        func shrink(_ v: Float) -> Float { abs(v) <= step ? 0 : v - (v > 0 ? step : -step) }
        var dx = d.x, dz = d.z
        while dx != 0 && !groundBelow(pos + V3(dx, 0, 0), w) { dx = shrink(dx) }
        while dz != 0 && !groundBelow(pos + V3(0, 0, dz), w) { dz = shrink(dz) }
        while dx != 0 && dz != 0 && !groundBelow(pos + V3(dx, 0, dz), w) { dx = shrink(dx); dz = shrink(dz) }
        return V3(dx, d.y, dz)
    }

    static var quarantined = 0
    // P274 (Oct 14 19:32, "sprint isn't fast enough"): 2x a walk in VR (was 1.6x), 7.0 flat (was the reference 5.612);
    // the walk keeps 4.317.
    static let vrSprintSpeed: Float = 4.317 * 2.0
    static let sprintSpeed: Float = 7.0
    static let slimeID: BlockID = Blocks.has("slime_block") ? Blocks.id("slime_block") : AIR
    static let cobwebID: BlockID = Blocks.has("cobweb") ? Blocks.id("cobweb") : AIR
    static let soulSandID: BlockID = Blocks.has("soul_sand") ? Blocks.id("soul_sand") : AIR
    static let honeyID: BlockID = Blocks.has("honey_block") ? Blocks.id("honey_block") : AIR
    static let powderSnowID: BlockID = Blocks.has("powder_snow") ? Blocks.id("powder_snow") : AIR
    static let wireID: BlockID = Blocks.has("ash_wire") ? Blocks.id("ash_wire") : AIR      // barbed wire (AshLines.swift)
    static let berryBase: BlockID = Blocks.has("sweet_berry_bush") ? Blocks.groupBase[Int(Blocks.id("sweet_berry_bush"))] : AIR
    // Held in a block (reference makeStuckInBlock, each tick's motion scaled and then cleared): the share of walking
    // speed left, the fall and the climb speeds in b/s (cobweb 0.25 / 0.05, berry bush 0.8 / 0.75, powder snow 0.9 with
    // its sinking left to Physics). Nil when free.
    static func stuck(_ b: BlockID) -> (h: Float, down: Float, up: Float)? {
        if b == AIR { return nil }
        if b == cobwebID { return (0.116, 0.08, 0.42) }
        if berryBase != AIR && Blocks.groupBase[Int(b)] == berryBase { return (0.37, 1.2, 6.3) }
        if b == powderSnowID { return (0.415, 60, 60) }
        if b == wireID { return (0.3, 1.2, 3.0) }
        // P417 (a): crushing through leaves and limbs (passed through: World.foliageSoft) slows him a little and lets
        // him sink through a canopy rather than drop.
        // P447 (Oct 25 09:10, "walking straight through branches is too slow"): 0.92 of the pace, momentum kept
        // (brush), where it was 0.75 with every step started from a standstill.
        // P462 (Oct 25 17:04, the jungle: "These branches are slowing me down way too much"): his full pace through
        // leaves and limbs; only the sinking through a canopy is kept.
        if brush(b) { return (1, 6, 20) }
        return nil
    }
    @inline(__always) static func brush(_ b: BlockID) -> Bool { ShapeClass.kind[Int(b)] == .foliage || ShapeClass.kind[Int(b)] == .trunk }
    private var lastGoodPos: V3?
    static let moveOverUnmade = ProcessInfo.processInfo.environment["BS_P414"] != "0"
    private(set) var overUnloaded = false          // P414: over ground not made yet (moving on through it)
    // P414: the lowest height at or above p where a body is clear (ground that came in round it), up to 64 blocks up,
    // else the column's top; nil if already clear.
    static func clearY(_ p: V3, _ w: World, collides: (V3) -> Bool) -> Float? {
        guard collides(p) else { return nil }
        var q = p
        for _ in 0..<128 {
            q.y = floor(q.y * 2 + 1) / 2
            if !collides(q) { return q.y }
        }
        let top = w.topY(Int(floor(p.x)), Int(floor(p.z)))
        return top >= 0 ? Float(top + 1) : nil
    }
    func update(dt: Float, input: MoveInput, world w: World) {
        walkWant = V2(0, 0)
        // NaN quarantine: a body left non-finite (a degenerate push or knockback, here or before this step) goes back to
        // its last finite position instead of reaching Int(floor()) in every block lookup (undefined in the release
        // build). Every repair is counted: the agents' non_finite oracle and the smoke line report it.
        func finite(_ v: V3) -> Bool { v.x.isFinite && v.y.isFinite && v.z.isFinite }
        if !finite(pos) || !finite(vel) {
            if !finite(pos) { pos = lastGoodPos ?? V3(0, Float(YOFF + 100), 0) }
            vel = .zero
            Player.quarantined += 1
        }
        let pos0 = pos
        defer {
            if !finite(pos) || !finite(vel) {
                pos = pos0; vel = .zero
                Player.quarantined += 1
            } else {
                lastGoodPos = pos
            }
        }
        // P414 (Remington, Oct 23: "just don't slow me down"): ground not made yet never holds the player back (he was
        // frozen until the chunk under him existed). He moves on through it and may fall; no fall counts there, and when
        // it comes in he is set on it if it came in around him.
        if !w.isLoaded(Int(floor(pos.x)), Int(floor(pos.z))) {
            if !Player.moveOverUnmade { return }          // (BS_P414=0: frozen there, as before, for the numbers)
            overUnloaded = true
        } else if overUnloaded {
            overUnloaded = false
            if let y = Player.clearY(pos, w, collides: { self.collides(at: $0, w) }) { pos.y = y; vel.y = max(0, vel.y) }
            airPeak = pos.y
        }
        if overUnloaded { airPeak = pos.y }

        // Pose: sprint-swim in water; crawl when there is no room to stand or sneak.
        let wet = Blocks.fluidKind[Int(w.builtBlock(Int(floor(pos.x)), Int(floor(pos.y + 0.3)), Int(floor(pos.z))))] == 1
        if swimming {
            if !(wet && input.sprint && input.forward > 0) || flying { swimming = false }
        } else if !flying && input.sprint && input.forward > 0 && headInWater { swimming = true }
        func fits(_ h: Float) -> Bool { !w.collides(V3(pos.x - halfW, pos.y, pos.z - halfW), V3(pos.x + halfW, pos.y + h, pos.z + halfW)) }
        crawling = !flying && !swimming && !gliding && fits(0.6) && !fits(1.5)
        // P179 (Oct 13: "crouching down should make it so I can get through caves easier"): sneaking into a gap too low
        // to sneak through (under 1.5 but at least 0.6 high) drops to a crawl at its mouth, so it can be entered.
        // P226: the probe follows the stick's direction (VR: relative to the head, strafing too), and a real duck counts.
        let stick = input.forward * input.forward + input.strafe * input.strafe
        if !crawling && (sneaking || ducking || input.sneak) && !flying && !swimming && !gliding && onGround && stick > 0.04 {
            let my0 = moveYaw ?? yaw
            let dir = V3(-sinf(my0), 0, -cosf(my0)) * input.forward + V3(cosf(my0), 0, -sinf(my0)) * input.strafe
            let q = pos + simd_normalize(dir) * 0.45
            func fitsAhead(_ h: Float) -> Bool { !w.collides(V3(q.x - halfW, q.y, q.z - halfW), V3(q.x + halfW, q.y + h, q.z + halfW)) }
            if fitsAhead(0.6) && !fitsAhead(1.5) { crawling = true }
        }
        let forcedCrouch = !flying && !prone && fits(1.5) && !fits(1.8)

        // Unstuck: if spawned or placed inside a block, pop upward. A hair's overlap with a wall first slides out
        // sideways: on a moving vehicle the ship-frame round trip leaves the body ~1e-4 inside the wall it walks
        // along, and popping up a block at a time carried it through an engine stack onto the crawler's roof
        // (ridecheck board/troops, z 71 face of the troop-bay engines). Feet a hair into the floor (placed at a dropped
        // item's resting height) rise by that hair, not by whole blocks up through the rock (playthrough "mine" run).
        var tries = 0
        if collides(at: pos, w) {
            let nudges: [V3] = [V3(0, 0.002, 0), V3(0.002, 0, 0), V3(-0.002, 0, 0), V3(0, 0, 0.002), V3(0, 0, -0.002),
                                V3(0, 0.02, 0), V3(0.01, 0, 0), V3(-0.01, 0, 0), V3(0, 0, 0.01), V3(0, 0, -0.01), V3(0, 0.1, 0)]
            if let n = nudges.first(where: { !collides(at: pos + $0, w) }) { pos += n }
        }
        // PG2 rewrite: in a field world the ground's rounded walls can press a body that fitted a moment ago (a hole dug a
        // cell at a time, ground a blast reshaped): the nearest free spot within three quarters of a block first. The
        // block-centred spots below missed the middle of a one-cell shaft and popped the body up through 40 blocks of
        // rock to the surface (field playthrough, mining at the foot of a shaft).
        if w.fieldTerrain && collides(at: pos, w) {
            search: for r in Player.fieldNudgeRadii {
                for o in Player.fieldNudgeDirs where !collides(at: pos + o * r, w) { pos += o * r; break search }
            }
        }
        // Still inside: the nearest free spot round the body (a cave beside it, the room it leaned out of) before popping
        // up. Popping straight up carried a player embedded underground up through the rock to the next cave or the
        // surface (Oct 11 playtest P20: "teleported through a bunch of blocks").
        if collides(at: pos, w), let free = Player.nearestFree(pos, { !self.collides(at: $0, w) }) { pos = free }
        while collides(at: pos, w) && tries < 64 { pos.y += 1; tries += 1 }

        let feet = w.builtBlock(Int(floor(pos.x)), Int(floor(pos.y + 0.1)), Int(floor(pos.z)))
        let body = w.builtBlock(Int(floor(pos.x)), Int(floor(pos.y + (prone ? 0.3 : 0.9))), Int(floor(pos.z)))
        inWater = Blocks.fluidKind[Int(feet)] == 1 || Blocks.fluidKind[Int(body)] == 1
        inLava = Blocks.fluidKind[Int(feet)] == 2 || Blocks.fluidKind[Int(body)] == 2
        // P188 (Oct 13: "the underwater look only goes away once I'm completely out of the water"): on the headset the
        // real head (headAt, Game.vrHead) is tested, against the water's surface rather than its whole block: the top
        // cell of a pool counts only below its surface (0.85 up the cell).
        let e = headAt.map { simd_length($0 - eye) < 2.5 ? $0 : eye } ?? eye
        let hb = w.builtBlock(Int(floor(e.x)), Int(floor(e.y)), Int(floor(e.z)))
        var headKind = Blocks.fluidKind[Int(hb)]
        if headKind == 1 && Blocks.fluidKind[Int(w.builtBlock(Int(floor(e.x)), Int(floor(e.y)) + 1, Int(floor(e.z))))] != 1
            && e.y - floor(e.y) > 0.85 { headKind = 0 }
        headInWater = headKind == 1
        headInLava = headKind == 2
        // Movement treats both fluids alike (lava is slower and heavier below); views, air and swimming are water only.
        let inFluid = inWater || inLava

        if flying || inFluid { airPeak = pos.y }
        // Moved 6+ blocks since the last update: a teleport (portal, command, harness), not a fall. Terminal speed is
        // under 4 blocks a tick. (The playthrough died of "fall" damage after being placed at the Emberdeep portal
        // below where it had last stood: run 375.)
        if simd_length(pos - lastUpdatePos) > 6 { airPeak = pos.y }
        jumped = false
        if gliding && (onGround || inFluid || flying) { gliding = false }
        if gliding { glide(dt, w); return }

        sneaking = (input.sneak || forcedCrouch || ducking) && !flying && !prone
        // VR (moveYaw set): sprint in any stick direction, at full sprint speed however far the stick is pushed (the
        // Touch stick's round gate rarely gives full deflection, so sprinting at a partial push was barely faster than a
        // full walk, Quest round 4).
        let vrSprint = moveYaw != nil && input.sprint && !sneaking && !swimming && input.forward * input.forward + input.strafe * input.strafe > 0.09
        sprinting = (input.sprint && input.forward > 0 && !sneaking) || swimming || vrSprint

        let my = moveYaw ?? yaw
        let f = V3(-sinf(my), 0, -cosf(my))
        let r = V3(cosf(my), 0, -sinf(my))
        var wish = f * input.forward + r * input.strafe
        let swimLook = moveLook ?? look
        var fh = f
        if let m = moveLook, m.x * m.x + m.z * m.z > 1e-6 { fh = simd_normalize(V3(m.x, 0, m.z)) }
        let len = simd_length(wish)
        if len > 1 || (vrSprint && len > 1e-3) { wish /= len }

        var speed: Float
        if flying { speed = hyperFlight ? 870 : (sprinting ? (fastFlight ? 87.0 : 21.6) : 10.9) }
        else if inFluid {
            speed = inLava && !inWater ? 1.0 : (sprinting ? 3.0 : 2.2)
            // Depth magmastrider closes the gap to land speed; dolphin's grace is much faster.
            if depthStrider > 0 { speed += (4.317 - speed) * Float(min(3, depthStrider)) / 3 }
            if dolphinsGrace { speed *= 2.2 }
        }
        else if sneaking || crawling { speed = 4.317 * min(1, 0.3 + 0.15 * Float(swiftSneak)) }
        // VR sprints at 2x a walk (P274; 1.6x before; the reference's 1.3x is near invisible in a headset: playtest v78, fourth report).
        else { speed = sprinting ? (moveYaw != nil ? Player.vrSprintSpeed : Player.sprintSpeed) : 4.317 }
        if !flying { speed *= speedMul * HandGrab.slow * gunSlow }          // P258: a body dragged or carried; P391: a heavy gun
        if soulSpeed > 0 && onGround {
            let under = Blocks.key(w.materialAt(Int(floor(pos.x)), Int(floor(pos.y - 0.2)), Int(floor(pos.z))))
            if under == "soul_sand" || under == "soul_soil" { speed *= 1.3 + 0.105 * Float(soulSpeed) }
        }
        // Soul sand and honey slow walking to ~58 % (reference speed factor 0.4 against ground friction; Soul Speed
        // cancels the sand's), honey halves the jump (below).
        let underID = w.materialAt(Int(floor(pos.x)), Int(floor(pos.y - 0.2)), Int(floor(pos.z)))
        if !flying && onGround && ((underID == Player.soulSandID && soulSpeed == 0) || underID == Player.honeyID) { speed *= 0.58 }
        let held = flying ? nil : (Player.stuck(feet) ?? Player.stuck(body))
        if let s = held { speed *= s.h }

        if jetThrust { speed *= 1.3 }
        let target = wish * speed
        walkWant = V2(target.x, target.z)
        let accel: Float = flying ? 10 : (onGround ? 20 : (inFluid ? 8 : (jetThrust ? 8 : 5)))
        let k = 1 - expf(-accel * dt)
        if !(jetThrust && jetBoost > 0) {                // (P322: a forward thrust steers the whole velocity below)
            vel.x += (target.x - vel.x) * k
            vel.z += (target.z - vel.z) * k
        }
        if held != nil && !Player.brush(feet) && !Player.brush(body) { vel.x = target.x; vel.z = target.z }        // no momentum carried into a web or a bush

        if flying {
            var vy: Float = 0
            if input.jump { vy += 1 }
            if input.sneak { vy -= 1 }
            let ty = vy * (hyperFlight ? 144 : (sprinting ? (fastFlight ? 48 : 12) : 8))
            vel.y += (ty - vel.y) * (1 - expf(-10 * dt))
        } else if swimming {
            // Sprint-swimming goes where you look (dive and surface with the view), about sprint speed.
            var sp: Float = 5.6 * speedMul
            if depthStrider > 0 { sp *= 1 + 0.1 * Float(min(3, depthStrider)) }
            if dolphinsGrace { sp *= 1.8 }
            let t = swimLook * sp
            let ks = 1 - expf(-5 * dt)
            vel += (t - vel) * ks
        } else if inFluid {
            let lava = inLava && !inWater
            vel.y -= 9 * dt
            vel.y *= expf((lava ? -5 : -2.5) * dt)
            if input.jump { vel.y = min(vel.y + (lava ? 16 : 22) * dt, lava ? 2.0 : 3.2) }
            vel.y = max(vel.y, lava ? -2 : -4)
        } else if levitate > 0 {
            levitate -= dt
            vel.y += (0.9 * Float(levitateAmp + 1) - vel.y) * (1 - expf(-4 * dt))
            airPeak = pos.y
        } else if jetThrust && jetBoost > 0 {
            // P322 (a): leaning into it, the thrust flies him where he looks: up to 16 b/s (22 sprinting) along jetDir,
            // the lift holding him up; the strafe input slides him sideways.
            let top: Float = (sprinting ? 22 : 16) * jetBoost
            var want = jetDir * top + r * (input.strafe * 4)
            want.y = max(want.y, -6) + 1.2 * (1 - jetBoost)
            let kk: Float = 1 - expf(-2.6 * dt)
            vel += (want - vel) * kk
            airPeak = pos.y
        } else if jetThrust {
            // Jetpack: ease the climb toward ~6 blocks/s; the fall restarts from wherever the thrust stops.
            vel.y += (6 - vel.y) * (1 - expf(-4 * dt))
            airPeak = pos.y
        } else {
            if onGround || vel.y < -Player.jumpV { jumpArc = false }
            vel.y -= (slowFalling && vel.y < 0 ? 2.8 : (jumpArc ? Player.jumpG : 28)) * dt
            vel.y = max(vel.y, slowFalling ? -1.2 : -60)
            if slowFalling { airPeak = pos.y }
            if input.jump && onGround {
                vel.y = jumpSpeed * (underID == Player.honeyID ? 0.5 : 1)
                jumped = true
                jumpArc = true
            }
        }
        if let s = held {
            vel.y = max(-s.down, min(s.up, vel.y))
            airPeak = pos.y                       // being held resets the fall (reference)
        }

        // Ladders and vines: climb when pushing forward or jumping, hold with sneak, slow slide otherwise.
        if !flying && (Player.climbable(feet) || Player.climbable(body)) {
            if input.jump || (input.forward > 0.1 && (collides(at: pos + fh * 0.35, w))) { vel.y = 2.35 }
            else if input.sneak { vel.y = max(vel.y, 0) }
            else { vel.y = max(vel.y, -3) }
            airPeak = pos.y
        }

        // Sneak edge guard: don't let horizontal motion carry us off a ledge.
        if onGround && sneaking && dt > 0 {
            let c = edgeClamp(V3(vel.x * dt, 0, vel.z * dt), w)
            vel.x = c.x / dt; vel.z = c.z / dt
        }
        // Step-up also works while swimming and just after (feet within 0.6 of a bank top walk straight out, as in the
        // reference, whose water check is the whole body box: it keeps pushing until the feet clear the surface).
        wetGrace = inWater ? 0.15 : max(0, wetGrace - dt)
        let wetish = inFluid || wetGrace > 0
        w.bodiesSolid = !flying                // P306: step onto the bodies lying about, not through them
        w.mobsSolid = true                     // P311 (a): and never walk through a living mob
        w.foliageSoft = !flying                // P417 (a): through leaves and limbs, not trunks
        let hit = w.moveBody(&pos, halfW: halfW, height: height, vel * dt, step: flying ? 0 : 0.6, onGround: onGround || wetish)
        w.bodiesSolid = false
        w.mobsSolid = false
        w.foliageSoft = false
        var landed = false
        var bounce: Float = 0
        if hit.y {
            if vel.y < 0 {
                landed = true
                // Slime blocks bounce you back up unless you sneak (reference; the fall does no damage: Game).
                let under = w.builtBlock(Int(floor(pos.x)), Int(floor(pos.y - 0.05)), Int(floor(pos.z)))
                if under == Player.slimeID && !sneaking && vel.y < -2 { bounce = -vel.y * 0.85 }
            }
            vel.y = 0
        }
        if bounce > 0 { vel.y = bounce }
        if autoJump && onGround && !flying && !sneaking && !prone && (hit.x || hit.z) && simd_length(wish) > 0.3 {
            // Auto-jump: a one-block step ahead with room above it.
            let d = simd_normalize(wish) * 0.35
            // P417 (b): and a block and a half (the jump clears it now).
            let rise: Float? = [1.05, 1.55].first { !collides(at: pos + d + V3(0, $0, 0), w) }
            if collides(at: pos + d, w), let r = rise, !collides(at: pos + V3(0, r, 0), w) {
                vel.y = jumpSpeed
                jumpArc = true
            }
        }
        // P471 (Oct 26 19:53: "Still having trouble getting through doors sometimes"; P458, Oct 25: "Make it so my hitbox
        // is smaller than the door opening"): pushing into a doorway's frame, the body slides into line with the opening.
        if !flying && Player.doorwayAssistOn && (hit.x || hit.z) && simd_length(wish) > 0.3 { doorwayAssist(wish, w, dt) }
        // Climbing out of water: pushing into a wall while in water lifts you along it (reference: 0.3 blocks/tick
        // while there's room 0.6 higher), so a one-block bank is easy to get onto.
        if wetish && !flying && (hit.x || hit.z) && simd_length(wish) > 0.3 && !collides(at: pos + V3(0, 0.6, 0), w) {
            vel.y = max(vel.y, 5.0)
        }
        if hit.x { vel.x = 0 }
        if hit.z { vel.z = 0 }
        // P386: drawn ground steeper than 50 degrees doesn't hold the feet: the body slides down it and can't walk up it
        // (walkable slopes hold it still).
        if landed && !flying && !wetish, let down = w.steepDrawnGround(pos) {
            let up = -(vel.x * down.x + vel.z * down.y)
            if up > 0 { vel.x += down.x * up; vel.z += down.y * up }
            vel.x += down.x * 14 * dt; vel.z += down.y * 14 * dt
        }
        onGround = landed || (vel.y <= 0 && groundBelow(pos, w))
        if flying && landed { flying = false }
        if onGround {
            if airPeak - pos.y > 0 { pendingFall = max(pendingFall, airPeak - pos.y) }
            airPeak = pos.y
        } else {
            airPeak = max(airPeak, pos.y)
        }
        if pos.y < -64 { pos.y = Float(CH); vel = .zero }
        lastUpdatePos = pos
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
                let push: V3 = l * 0.1
                v += push + (l * 1.5 - v) * 0.5
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
