import Foundation
import simd

// `--questbugs --only pm9a`: Remington's Quest playtest 2026-10-09 pm, items 1 and 2.
//  1. Mounted step-ups were a one-tick snap of the camera (close to motion sickness): every mount, and the player on
//     foot, climbs a staircase through Game.tick at 72 Hz; the drawn eye (Player.viewEye: the Mac camera and the Quest
//     rig's feet both follow it) may move at most 0.12 blocks per frame and must settle on the true eye.
//  2. Horse legs came apart while walking / when hit: every mob kind is posed across its walk cycle (walking,
//     galloping, knocked back, hurt) and its model must stay one connected piece (oriented boxes touching).
enum PM9ATests {
    static func run(_ game: Game, _ check: (Bool, String) -> Void) {
        steps(game, check)
        models(check)
    }

    // MARK: 1. Eased step-ups

    static func steps(_ game: Game, _ check: (Bool, String) -> Void) {
        let p = game.player, w = game.world
        let save = (p.pos, p.yaw, p.pitch, p.flying, game.paused, game.riding, game.inventory.held)
        defer {
            game.input.releaseAll()
            game.riding = nil
            (p.pos, p.yaw, p.pitch, p.flying, game.paused, game.riding, game.inventory.held) = save
            p.vel = .zero
        }
        game.paused = false
        p.flying = false
        let bx = Int(floor(p.pos.x)), by = Int(floor(p.pos.y)) + 60, bz = Int(floor(p.pos.z))
        // A hill of 1-block steps, 2 blocks deep, climbing toward -z (yaw 0), on a stone pad; a plateau on top.
        let z0 = bz - 40, z1 = bz + 4
        // Bulk edits without a synchronous remesh per block (setBlock), then one remesh of the area.
        func put(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) { _ = w.setBlockAsync(x, y, z, b) }
        func done() { w.remeshArea(x0: bx - 5, z0: z0, x1: bx + 5, z1: z1, y0: by - 1, y1: by + 14) }
        func clear() { for x in (bx - 5)...(bx + 5) { for z in z0...z1 { for y in (by - 1)...(by + 14) { put(x, y, z, AIR) } } }; done() }
        func build(rise: Int, run: Int, block: BlockID, steps n: Int) {
            for x in (bx - 5)...(bx + 5) { for z in z0...z1 { for y in (by - 1)...(by + 14) {
                let k = z <= bz - run ? min(n, (bz - z) / run) : 0      // steps climbed at this z
                let solid = y == by - 1 || (y - by) < k * rise
                put(x, y, z, solid ? block : AIR)
            } } }
            done()
        }
        defer { clear() }
        let start = V3(Float(bx) + 0.5, Float(by), Float(bz) + 2.5)
        let dt: Double = 1.0 / 72

        // One climb: hold forward for up to `secs`; returns (max per-frame drawn-eye change, max raw change, risen,
        // settled error, rider-to-mount drawn offset spread).
        // The bound: 0.12 blocks per 72 Hz frame, or a quarter over the hill's true average climb rate when that alone
        // is near it (the fastest horse, 16 blocks/s up a 1-in-2 hill, truly rises 0.11 per frame: no easing can go below).
        var climbRate: Float = 0
        func bound() -> Float { max(0.12, 1.25 * climbRate) }
        func climb(_ m: Mob?, secs: Float) -> (Float, Float, Float, Float, Float) {
            var firstRise = -1, lastRise = -1, frame = 0
            let stopZ = Float(bz - 20)                              // on the plateau: let go, coast, settle
            var lastView = p.viewEye.y, lastRaw = p.eye.y
            let y0 = p.eye.y
            var maxView: Float = 0, maxRaw: Float = 0
            var offLo: Float = 1e9, offHi: Float = -1e9
            game.input.keys.insert(KeyBinds.key(.forward))
            var t: Float = 0
            while t < secs + 1.2 {
                if t >= secs || p.pos.z < stopZ { game.input.keys.remove(KeyBinds.key(.forward)) }
                p.yaw = 0; p.pitch = 0
                if let m = m { m.yaw = 0 }
                game.tick(dt); game.input.endFrame()
                t += Float(dt)
                let v = p.viewEye.y, r = p.eye.y
                if r - lastRaw > 0.04 { if firstRise < 0 { firstRise = frame }; lastRise = frame }
                frame += 1
                maxView = max(maxView, abs(v - lastView)); maxRaw = max(maxRaw, abs(r - lastRaw))
                lastView = v; lastRaw = r
                if let m = m {
                    let o: Float = v - (m.pos.y + m.viewDY)
                    offLo = min(offLo, o); offHi = max(offHi, o)
                }
            }
            game.input.keys.remove(KeyBinds.key(.forward))
            let risen: Float = p.eye.y - y0
            climbRate = lastRise > firstRise ? max(0, risen - 1) / Float(lastRise - firstRise) : 0
            return (maxView, maxRaw, p.eye.y - y0, abs(p.viewEye.y - p.eye.y), m == nil ? 0 : offHi - offLo)
        }

        // Mounts: every rideable kind, each over a fresh hill (1-block steps, 2 deep).
        let stickFor: [MobKind: String] = [.pig: "carrot_on_a_stick", .strider: "warped_fungus_on_a_stick"]
        // The horse twice: a typical one (~10.7 blocks/s) and the fastest (16).
        let mounts: [(MobKind, Int)] = [(.horse, 8), (.horse, 15), (.donkey, -1), (.mule, -1), (.skeletonHorse, -1), (.zombieHorse, -1),
                                        (.camel, -1), (.pig, -1), (.strider, -1)]
        for (kind, nib) in mounts {
            build(rise: 1, run: 2, block: STONE, steps: 8)
            let m = Mob(kind, at: start)
            m.owner = true; m.saddled = true; m.persistent = true; m.yaw = 0
            if nib >= 0 { m.variant = (m.variant & ~0xF0) | (nib << 4) }          // horse speed 4.8 + nib/15 x 11.2
            game.mobs.mobs.append(m)
            game.inventory.held = stickFor[kind].map { ItemStack(Items.id($0), 1) } ?? .empty
            game.riding = m
            p.pos = m.pos + V3(0, m.height * 0.75, 0)
            for _ in 0..<20 { game.tick(dt); game.input.endFrame() }           // settle on the pad
            let speedEst: Float = kind == .pig ? 3.5 : (kind == .strider ? 2.5 : (kind == .camel ? 3.8 : 7))
            let (mv, mr, risen, settle, spread) = climb(m, secs: min(8, 22 / speedEst))
            check(risen >= 5 && mv <= bound() && settle < 0.02 && spread < 0.01,
                  String(format: "pm9a step: riding a %@%@ up 1-block steps: drawn eye moves %.3f/frame (bound %.3f; raw physics %.2f), rose %.1f, settles %.3f, rider-mount drift %.3f",
                         kind.key, nib >= 0 ? String(format: " (%.1f b/s)", m.horseSpeed) : "", mv, bound(), mr, risen, settle, spread))
            game.riding = nil
            game.mobs.mobs.removeAll { $0 === m }
        }
        game.inventory.held = .empty

        // On foot: half-block steps (slabs) one block deep; the player's own 0.6 step-up.
        if Blocks.has("stone_slab") {
            let slab = Blocks.id("stone_slab")
            // Alternate slab and full block: 0.5 rises one block deep.
            for x in (bx - 5)...(bx + 5) { for z in z0...z1 { for y in (by - 1)...(by + 14) {
                let k = z <= bz - 1 ? min(12, bz - z) : 0                // half-blocks climbed
                let full = k / 2, half = k % 2 == 1
                let yy = y - by
                let b: BlockID = y == by - 1 || yy < full ? STONE : ((half && yy == full) ? slab : AIR)
                put(x, y, z, b)
            } } }
            done()
            p.pos = start; p.vel = .zero
            for _ in 0..<20 { game.tick(dt); game.input.endFrame() }
            let (mv, mr, risen, settle, _) = climb(nil, secs: 4)
            check(risen >= 3 && mv <= bound() && settle < 0.02,
                  String(format: "pm9a step: on foot up slab steps: drawn eye moves %.3f/frame (bound %.3f; raw physics %.2f), rose %.1f, settles %.3f", mv, bound(), mr, risen, settle))
        }

        // Unridden mobs ease their steps the same way (the class: what is drawn never snaps a block).
        build(rise: 1, run: 2, block: STONE, steps: 3)
        let cow = Mob(.cow, at: start)
        cow.onGround = true
        game.mobs.mobs.append(cow)
        defer { game.mobs.mobs.removeAll { $0 === cow } }
        var cy = cow.pos.y + cow.viewDY, cmax: Float = 0, rmax: Float = 0, ry = cow.pos.y
        for _ in 0..<(72 * 4) {
            cow.vel.x = 0; cow.vel.z = -2.5; cow.yaw = 0
            let wasG = cow.onGround, y0 = cow.pos.y
            let hit = w.moveBody(&cow.pos, halfW: cow.halfW, height: cow.height, V3(0, -2, -2.5) * Float(dt), step: 1.05, onGround: cow.onGround)
            cow.onGround = hit.y
            cow.easeStep(fromY: y0, wasGround: wasG, Float(dt))
            let d = cow.pos.y + cow.viewDY
            cmax = max(cmax, abs(d - cy)); rmax = max(rmax, abs(cow.pos.y - ry)); cy = d; ry = cow.pos.y
        }
        check(cmax <= 0.12 && rmax > 0.9, String(format: "pm9a step: a mob's drawn model eases its step-ups (%.3f/frame drawn, %.2f physics)", cmax, rmax))
    }

    // MARK: 2. Models stay in one piece

    // Kinds whose models are meant to have separate pieces (with the reason).
    static let floating: [MobKind: String] = [
        .blaze: "its rods orbit the body on their own (reference look)",
        .endCrystal: "the crystal floats and spins above its bedrock base",
        .magmaCube: "its slices spread apart mid-jump (reference look)",
    ]

    struct OBB { var c: V3; var a: simd_float3x3; var h: V3 }
    static func obb(_ p: Part, tol: Float) -> OBB {
        let r = p.rotation
        let mid: V3 = (p.mn + p.mx) * 0.5
        return OBB(c: r * (mid - p.pivot) + p.pivot, a: r, h: (p.mx - p.mn) * 0.5 + V3(repeating: tol))
    }
    // Separating axis test for two oriented boxes.
    static func touch(_ A: OBB, _ B: OBB) -> Bool {
        let t: V3 = B.c - A.c
        func proj(_ o: OBB, _ ax: V3) -> Float {
            abs(simd_dot(o.a.columns.0, ax)) * o.h.x + abs(simd_dot(o.a.columns.1, ax)) * o.h.y + abs(simd_dot(o.a.columns.2, ax)) * o.h.z
        }
        func sep(_ ax: V3) -> Bool {
            let l2 = simd_length_squared(ax)
            if l2 < 1e-8 { return false }
            let n = ax / sqrtf(l2)
            return abs(simd_dot(t, n)) > proj(A, n) + proj(B, n)
        }
        let aa = [A.a.columns.0, A.a.columns.1, A.a.columns.2], ba = [B.a.columns.0, B.a.columns.1, B.a.columns.2]
        for x in aa where sep(x) { return false }
        for x in ba where sep(x) { return false }
        for x in aa { for y in ba where sep(simd_cross(x, y)) { return false } }
        return true
    }
    // Parts not connected (through touching parts) to the largest one.
    static func detached(_ parts: [Part], tol: Float = 0.3) -> [Int] {
        guard parts.count > 1 else { return [] }
        let boxes = parts.map { obb($0, tol: tol) }
        var root = 0, best: Float = -1
        for (i, p) in parts.enumerated() {
            let s = p.mx - p.mn
            let v: Float = s.x * s.y * s.z
            if v > best { best = v; root = i }
        }
        var seen = [Bool](repeating: false, count: parts.count)
        var stack = [root]
        seen[root] = true
        while let i = stack.popLast() {
            for j in parts.indices where !seen[j] && touch(boxes[i], boxes[j]) { seen[j] = true; stack.append(j) }
        }
        return parts.indices.filter { !seen[$0] }
    }

    static func models(_ check: (Bool, String) -> Void) {
        var bad: [String] = []
        var posed = 0
        for kind in MobKind.allCases {
            if floating[kind] != nil { continue }
            let m = Mob(kind, at: V3(0, 200, 0))
            m.yaw = 0
            var worst: (String, [Int])?
            for baby in [false, true] {
                m.baby = baby
                for speed: Float in [0, 3, 9] {
                    for hurt: Float in [0, 0.3] {
                        for i in 0..<16 {
                            m.walkPhase = Float(i) / 16 * 2 * .pi
                            m.walkAmount = speed > 0 ? 1 : 0
                            m.vel = V3(0, hurt > 0 ? 3 : 0, -speed)           // knocked back: up and away
                            m.hurt = hurt
                            if kind == .horse || kind == .donkey || kind == .mule { m.saddled = i % 2 == 0; m.armorTier = i % 3 }
                            let parts = mobModelParts(m)
                            posed += 1
                            let d = detached(parts)
                            if !d.isEmpty && worst == nil {
                                worst = (String(format: "%@%@ speed %.0f hurt %.1f phase %d/16", kind.key, baby ? " (baby)" : "", speed, hurt, i), d)
                            }
                        }
                    }
                }
            }
            if let (pose, d) = worst {
                bad.append("\(pose): \(d.count) detached part(s) \(d.prefix(6))")
            }
        }
        for b in bad.prefix(40) { print("questbugs:   detached: \(b)") }
        check(bad.isEmpty, "pm9a model: every mob model stays in one piece across walk, gallop, knockback and hurt (\(posed) poses, \(bad.count) kinds with gaps)")
    }
}
