import Foundation
import simd

// Controller-only gameplay actions that have no single key equivalent: toggle sneak, auto-sprint,
// tap / hold drop, D-pad shortcuts (chat, off-hand swap).
enum PadActions {
    static var sneakLatched = false
    static var forwardTime: Float = 0
    static var dropPressedAt: Double = -1
    static var dropStackDone = false

    static func sneak(_ p: PadSnapshot, _ q: PadSnapshot, _ g: Game) -> Bool {
        // B crouches (Halo Infinite default layout: B crouch, right stick click melee).
        let held = p.b
        guard Settings.shared.sneakToggle else { sneakLatched = false; return held }
        if p.b && !q.b { sneakLatched.toggle() }
        if g.player.flying || g.player.inWater { sneakLatched = false; return held }   // hold to descend
        return sneakLatched
    }

    // Y: Classic opens the inventory on press. Halo: a tap switches back to the previously selected hotbar slot
    // (Halo's two-weapon swap), holding Y for 0.35 s opens the inventory.
    static var curSlot = 0, prevSlot = 0
    static var yDownAt: Double = -1
    static func inventoryButton(_ p: PadSnapshot, _ q: PadSnapshot, _ g: Game) -> Bool {
        if g.selected != curSlot { prevSlot = curSlot; curSlot = g.selected }
        guard PadMap.halo else { yDownAt = -1; return p.y && !q.y }
        if p.y && !q.y { yDownAt = g.clock }
        if p.y, yDownAt >= 0, g.clock - yDownAt >= 0.35 { yDownAt = -1; return true }
        if !p.y && q.y && yDownAt >= 0 {
            yDownAt = -1
            if prevSlot != g.selected { g.selected = prevSlot; g.equipAnim = 1; g.sfx(.click, 0.3) }
        }
        if !p.y { yDownAt = -1 }
        return false
    }

    // Left stick pushed fully forward for a moment starts a sprint (it ends when the stick comes back).
    static func autoSprint(_ ls: V2, _ dt: Float) -> Bool {
        guard Settings.shared.autoSprint else { forwardTime = 0; return false }
        if ls.y > 0.95 && abs(ls.x) < 0.4 { forwardTime += dt } else { forwardTime = 0 }
        return forwardTime > 0.35
    }

    // Returns true when a screen opened (the caller stops this frame's gameplay tick).
    static func extras(_ p: PadSnapshot, _ q: PadSnapshot, _ g: Game) -> Bool {
        // D-pad down: tap drops one item, holding it drops the rest of the stack.
        if p.down && !q.down { g.dropHeld(all: false); dropPressedAt = g.clock; dropStackDone = false }
        if p.down && !dropStackDone && dropPressedAt >= 0 && g.clock - dropPressedAt > 0.6 {
            g.dropHeld(all: true)
            dropStackDone = true
        }
        if !p.down { dropPressedAt = -1 }
        // D-pad right / R: swap main hand and off hand.
        // With a gun held, a key shared with Reload Gun (both default to R) reloads instead of swapping hands.
        let offKey = KeyBinds.key(.offhand)
        let keySwap = g.input.tapped(offKey) && !(g.heldGun != nil && offKey == KeyBinds.key(.reload))
        if (p.right && !q.right) || keySwap { swapOffhand(g) }
        // D-pad left: command console (it has pad quick buttons and the on-screen keyboard).
        if p.left && !q.left { g.openMenu(CommandMenu(game: g)); return true }
        return false
    }

    static func swapOffhand(_ g: Game) {
        let main = g.inventory.held, off = g.inventory.offhand[0]
        if main.isEmpty && off.isEmpty { return }
        g.inventory.held = off
        g.inventory.offhand[0] = main
        g.equipAnim = 1
        g.sfx(.click, 0.3)
    }
}

// Controller aim assist: the view turns slower while the crosshair is on or near a hostile mob, and
// while mining a block, so small stick corrections don't overshoot. Mouse aiming is never touched.
enum AimAssist {
    static func friction(_ g: Game) -> Float {
        guard Settings.shared.aimAssist, PadManager.shared.usingPad || Coop.secondSeat else { return 1 }
        var f: Float = 1
        if g.mining != nil { f = 0.7 }
        let eye = g.player.eye, look = g.player.look
        for m in g.mobs.mobs where (m.kind.hostile || m.kind.steelhold) && m.health > 0 {
            let c = m.pos + V3(0, m.height * 0.5, 0)
            let d = c - eye
            let dist = simd_length(d)
            guard dist > 0.5 && dist < 24 else { continue }
            let cosA = simd_dot(d / dist, look)
            let radius = max(m.halfW * 2, m.height) * 0.75 + 0.3
            let cone = cosf(atanf(radius / dist) * 1.6)
            if cosA > cone {
                let core = cosf(atanf(radius / dist) * 0.8)
                f = min(f, cosA > core ? 0.45 : 0.62)
            }
        }
        return f
    }
}

extension PadLook {
    static var shared = PadLook()      // var: split-screen seats swap it (Coop.swift)
}

// Block-targeting assist (controller only): the highlighted block holds on while the crosshair drifts up to
// ~0.12 blocks past its edge, so it doesn't flicker to a neighbour when you aim at a corner or mine with a
// slightly moving stick. A block that comes clearly closer (a mob-placed block, a new wall) still wins.
extension AimAssist {
    static var last: (hit: IVec3, normal: IVec3)?

    static func sticky(_ g: Game, _ t: (hit: IVec3, normal: IVec3)?, reach: Float) -> (hit: IVec3, normal: IVec3)? {
        guard Settings.shared.aimAssist, PadManager.shared.usingPad || Coop.secondSeat, let prev = last else { last = t; return t }
        if let t = t, t.hit == prev.hit { last = t; return t }
        let b = g.world.block(prev.hit.x, prev.hit.y, prev.hit.z)
        guard Blocks.targetable(b) else { last = t; return t }
        let m: Float = 0.12
        let lo = V3(Float(prev.hit.x) - m, Float(prev.hit.y) - m, Float(prev.hit.z) - m)
        let hi = lo + V3(repeating: 1 + 2 * m)
        let eye = g.player.eye
        guard let h = World.rayBox(eye, g.player.look, lo, hi), h.0 <= reach + 0.2 else { last = t; return t }
        if let nt = t {
            // Compare entry distances along the ray, not centres: a block just placed in front of the old target is only
            // ~1 closer, and holding on to the old target made every held placement after the first a no-op.
            let lo2 = V3(Float(nt.hit.x), Float(nt.hit.y), Float(nt.hit.z))
            let enter = World.rayBox(eye, g.player.look, lo2, lo2 + V3(repeating: 1))?.0 ?? h.0
            if enter + 0.3 < h.0 { last = t; return t }
        }
        return prev
    }
}

// Gun aim assist (controller only, Options > Controller > Aim Assist): pulling LT to aim down the sights snaps
// most of the way onto the nearest enemy within ~10 degrees (in sight and in range), then follows it gently
// while it stays near the crosshair. Looking away drops the target. The view also slows while aiming.
extension AimAssist {
    static weak var snapTarget: Mob?
    static var snapTime: Float = 0

    static func lookScale(_ g: Game) -> Float {
        guard g.heldGun != nil else { return 1 }
        #if os(macOS)
        return max(0.15, g.gunFovScale)   // Halo zoom sensitivity 1.0: on-screen speed while zoomed matches the hip
        #else
        return powf(max(0.15, g.gunFovScale), 0.8)
        #endif
    }

    static func angles(_ g: Game, _ m: Mob) -> (yaw: Float, pitch: Float, dist: Float) {
        let c = m.pos + V3(0, m.height * 0.6, 0)
        let d = c - g.player.eye
        let l = max(0.001, simd_length(d))
        return (atan2f(-d.x, -d.z), asinf(max(-1, min(1, d.y / l))), l)
    }

    static func wrap(_ a: Float) -> Float {
        var v = a
        while v > .pi { v -= 2 * .pi }
        while v < -.pi { v += 2 * .pi }
        return v
    }

    static func bestTarget(_ g: Game, cone: Float, range: Float) -> Mob? {
        var best: (Mob, Float)?
        for m in g.mobs.mobs where (m.kind.hostile || m.kind.steelhold) && m.health > 0 {
            let a = angles(g, m)
            guard a.dist < range else { continue }
            let off = abs(wrap(a.yaw - g.player.yaw)) + abs(a.pitch - g.player.pitch)
            guard off < cone, off < (best?.1 ?? .greatestFiniteMagnitude) else { continue }
            guard g.world.canSee(g.player.eye, m.pos + V3(0, m.height * 0.6, 0)) else { continue }
            best = (m, off)
        }
        return best?.0
    }

    static func gunTick(_ g: Game, _ p: PadSnapshot, _ q: PadSnapshot, _ dt: Float) {
        guard Settings.shared.aimAssist, PadManager.shared.usingPad || Coop.secondSeat, let gi = g.heldGun else { snapTarget = nil; return }
        let aiming = p.lt > 0.5
        if aiming && q.lt <= 0.5 {
            snapTarget = bestTarget(g, cone: 0.18, range: Guns.all[gi].range)
            snapTime = 0.18
        }
        guard aiming, let m = snapTarget, m.health > 0 else { snapTarget = nil; return }
        let a = angles(g, m)
        let dy = wrap(a.yaw - g.player.yaw), dp = a.pitch - g.player.pitch
        if snapTime > 0 {
            let k = min(1, dt / snapTime) * 0.6           // pull 60% of the way over the first 0.18 s
            g.player.yaw += dy * k
            g.player.pitch += dp * k
            snapTime -= dt
        } else if abs(dy) < 0.12 && abs(dp) < 0.12 {
            let k = min(1, dt * 3) * 0.5                  // gentle tracking of a moving target
            g.player.yaw += dy * k
            g.player.pitch += dp * k
        } else {
            snapTarget = nil
        }
    }
}
