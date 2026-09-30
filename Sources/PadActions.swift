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
        let held = p.b || p.r3
        guard Settings.shared.sneakToggle else { sneakLatched = false; return held }
        if (p.b && !q.b) || (p.r3 && !q.r3) { sneakLatched.toggle() }
        if g.player.flying || g.player.inWater { sneakLatched = false; return held }   // hold to descend
        return sneakLatched
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
        if (p.right && !q.right) || g.input.tapped(KeyBinds.key(.offhand)) { swapOffhand(g) }
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
        guard Settings.shared.aimAssist, PadManager.shared.usingPad else { return 1 }
        var f: Float = 1
        if g.mining != nil { f = 0.7 }
        let eye = g.player.eye, look = g.player.look
        for m in g.mobs.mobs where m.kind.hostile && m.health > 0 {
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
    static let shared = PadLook()
}

// Block-targeting assist (controller only): the highlighted block holds on while the crosshair drifts up to
// ~0.12 blocks past its edge, so it doesn't flicker to a neighbour when you aim at a corner or mine with a
// slightly moving stick. A block that comes clearly closer (a mob-placed block, a new wall) still wins.
extension AimAssist {
    static var last: (hit: IVec3, normal: IVec3)?

    static func sticky(_ g: Game, _ t: (hit: IVec3, normal: IVec3)?, reach: Float) -> (hit: IVec3, normal: IVec3)? {
        guard Settings.shared.aimAssist, PadManager.shared.usingPad, let prev = last else { last = t; return t }
        if let t = t, t.hit == prev.hit { last = t; return t }
        let b = g.world.block(prev.hit.x, prev.hit.y, prev.hit.z)
        guard Blocks.targetable(b) else { last = t; return t }
        let m: Float = 0.12
        let lo = V3(Float(prev.hit.x) - m, Float(prev.hit.y) - m, Float(prev.hit.z) - m)
        let hi = lo + V3(repeating: 1 + 2 * m)
        let eye = g.player.eye
        guard let h = World.rayBox(eye, g.player.look, lo, hi), h.0 <= reach + 0.2 else { last = t; return t }
        if let nt = t {
            let c = V3(Float(nt.hit.x) + 0.5, Float(nt.hit.y) + 0.5, Float(nt.hit.z) + 0.5)
            if simd_length(c - eye) + 0.6 < h.0 { last = t; return t }
        }
        return prev
    }
}
