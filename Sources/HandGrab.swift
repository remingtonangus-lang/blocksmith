import Foundation
import simd

// P177 (Oct 13 13:07-13:09: "hands that grab: drag a body, pick up an animal and throw it, a chicken; move things
// around"). On the headset, a grip pressed with the hand on a small creature (a chicken, rabbit, cat, fox, frog, a
// baby animal: anything under 1 block tall and under 0.9 wide) picks it up: it hangs from the hand and follows it, its
// own legs and AI stopped. Let go and it carries the hand's speed: swung, it is thrown (a few blocks for a flick, up
// to 12 b/s); held still, it is set down. A grip on a body (a hunted animal's carcass, Hunting.bodies) drags it
// instead: it slides along the ground behind the hand on a short lead, whatever its size, and stays where it is let
// go. A hand holding something doesn't step the hotbar. The right hand grabs only when it holds nothing.
// H12 ("hands can grab and move anything physical"): a dropped item is picked up in the hand the same way (and thrown
// or set down when let go, not swept into the pack while held), and anything else that moves (a cow, a horse, a
// villager, a fallen soldier, an armour stand, a boat, a minecart) is taken by the scruff or the rail and dragged
// along on the lead like a body: over the ground, or on the water for a boat. Bosses and anything bigger than a horse
// are too heavy.
enum HandGrab {
    final class Hold {
        let mob: Mob
        let body: Bool                    // dragged along the ground on the lead (a carcass, H12: anything too big to lift)
        let carcass: Bool                 // a hunted animal's body (Hunting.bodies), not a live mob
        let item: ItemEntity?             // H12: a dropped item in the hand (`mob` is then a placeholder)
        var last: V3
        var vel: V3 = .zero               // the hand's speed, smoothed over a few frames
        init(_ m: Mob, body: Bool, at p: V3, carcass: Bool = false, item: ItemEntity? = nil) {
            mob = m; self.body = body; self.carcass = carcass; self.item = item; last = p
        }
    }
    static let placeholder = Mob(.armorStand, at: V3(0, -1000, 0))
    static func holds(_ e: ItemEntity) -> Bool { held[0]?.item === e || held[1]?.item === e }

    // H12: too big to lift but light enough to drag (no bosses, nothing over a horse's size, no ships' crews' guns).
    static func draggable(_ m: Mob) -> Bool {
        m.health > 0 && !liftable(m) && m.halfW * m.scale <= 0.9 && m.height * m.scale <= 2.6 && !m.spec.flying
            && ![MobKind.enderDragon, .wither, .warden, .elderGuardian, .deckGun, .ravager].contains(m.kind)
    }
    static var held: [Hold?] = [nil, nil]        // per hand: 0 the off hand, 1 the aiming hand
    static var grabs = 0, flings = 0, drags = 0  // counters (PlaytestOct13Tests)
    static let reach: Float = 0.45                // how close the hand must be to the creature's body
    static let lead: Float = 0.7                  // a dragged body trails the hand by this much
    static let maxThrow: Float = 12

    static func holds(_ m: Mob) -> Bool { held[0]?.mob === m || held[1]?.mob === m }

    // Small enough to lift in one hand.
    static func liftable(_ m: Mob) -> Bool {
        m.health > 0 && m.height * m.scale <= 1.0 && m.halfW * m.scale <= 0.45 && !m.spec.flying && m.kind != .armorStand
            && m.kind != .boat && m.kind != .minecart && !m.carcass
    }

    // Per frame for one hand (QuestControls): true while that hand holds something, and on the press that took it and
    // the release that let it go (those grip edges are the grab's, not the hotbar's).
    static func tick(_ g: Game, hand i: Int, at p: V3, grip: Bool, gripWas: Bool, empty: Bool, dt: Float) -> Bool {
        if let h = held[i] {
            let gone: Bool
            if let it = h.item { gone = it.stack.isEmpty || !g.drops.items.contains { $0 === it } }
            else if h.carcass { gone = !Hunting.bodies.contains { $0.mob === h.mob } }
            else { gone = h.mob.health <= 0 || !g.mobs.mobs.contains { $0 === h.mob } }
            if gone { held[i] = nil; return grip }
            if grip {
                // The hand's speed while it holds (the release frame's own sample is left out: let go mid-swing, the
                // throw keeps the swing's speed).
                let v = (p - h.last) / max(dt, 0.001)
                h.vel = h.vel * 0.55 + v * 0.45
                h.last = p
                if let it = h.item {
                    it.pos = p - V3(0, 0.125, 0); it.vel = .zero; it.onGround = false
                    it.pickupDelay = max(it.pickupDelay, 0.4)              // not swept into the pack while it is in the hand
                } else if h.body { drag(g, h.mob, toward: p) } else { carry(h.mob, at: p) }
                return true
            }
            held[i] = nil
            if let it = h.item {
                var t = h.vel
                let s = simd_length(t)
                if s > maxThrow { t *= maxThrow / s }
                it.vel = t
                it.pickupDelay = s > 2.5 ? 1.0 : 0.4
                if s > 2.5 { flings += 1; g.sfx(.throwItem, 0.8, at: p) }
                return true
            }
            if !h.body {
                var t = h.vel
                let s = simd_length(t)
                if s > maxThrow { t *= maxThrow / s }
                h.mob.vel = t
                h.mob.onGround = false
                if s > 2.5 { flings += 1; g.sfx(.throwItem, 0.8, at: p); g.sfx(.mob(h.mob.kind, .hurt), 0.7, at: p) }
            }
            return true
        }
        guard grip && !gripWas && empty && g.alive else { return false }
        var best: (Mob, Bool)?, bestD = Float.infinity
        for m in g.mobs.mobs where liftable(m) && !holds(m) && g.riding !== m {
            let c = m.pos + V3(0, m.height * m.scale * 0.5, 0)
            let d = simd_length(c - p) - m.halfW * m.scale
            if d < reach && d < bestD { bestD = d; best = (m, false) }
        }
        var carcass = false
        for b in Hunting.bodies where b.dim == g.world.dim && !holds(b.mob) {
            let m = b.mob
            let d = simd_length(m.pos + V3(0, 0.3, 0) - p) - max(m.halfW, m.height * 0.5)
            if d < reach && d < bestD { bestD = d; best = (m, true); carcass = true }
        }
        // H12: a dropped item in reach of the hand.
        var item: ItemEntity?
        for e in g.drops.items where !e.stack.isEmpty && !holds(e) {
            let d = simd_length(e.pos + V3(0, 0.125, 0) - p) - 0.2
            if d < reach && d < bestD { bestD = d; item = e; best = nil }
        }
        // H12: anything else that moves, taken by its nearest side and dragged.
        if item == nil {
            for m in g.mobs.mobs where draggable(m) && !holds(m) && g.riding !== m {
                let lo = m.pos - V3(m.halfW * m.scale, 0, m.halfW * m.scale)
                let hi = m.pos + V3(m.halfW * m.scale, m.height * m.scale, m.halfW * m.scale)
                let d = simd_length(simd_clamp(p, lo, hi) - p)
                if d < reach && d < bestD { bestD = d; best = (m, true); carcass = false }
            }
        }
        if let e = item {
            held[i] = Hold(placeholder, body: false, at: p, item: e)
            grabs += 1
            g.sfx(.pickup, 0.5, at: p)
            return true
        }
        guard let (m, body) = best else { return false }
        held[i] = Hold(m, body: body, at: p, carcass: carcass)
        grabs += 1
        if body { drags += 1; g.sfx(carcass ? .plantBrush : .mob(m.kind, .hurt), 0.9, at: p) } else { g.sfx(.mob(m.kind, .hurt), 0.8, at: p); g.sfx(.pickup, 0.5, at: p) }
        return true
    }

    // A lifted creature hangs from the hand by its middle.
    static func carry(_ m: Mob, at p: V3) {
        m.pos = p - V3(0, m.height * m.scale * 0.5, 0)
        m.vel = .zero
        m.onGround = false
    }

    // A body on a short lead: pulled along the ground toward the hand, never lifted; it turns to follow the pull.
    static func drag(_ g: Game, _ m: Mob, toward p: V3) {
        let d = V2(p.x - m.pos.x, p.z - m.pos.z)
        let l = simd_length(d)
        guard l > lead else { return }
        let step = d / l * (l - lead)
        let nx = m.pos.x + step.x, nz = m.pos.z + step.y
        // A boat on the water is towed across it at its own height (H12).
        if m.kind == .boat && Blocks.isLiquid(g.world.block(Int(floor(nx)), Int(floor(m.pos.y + 0.2)), Int(floor(nz)))) {
            if !Blocks.collide[Int(g.world.block(Int(floor(nx)), Int(floor(m.pos.y + 0.5)), Int(floor(nz))))] {
                m.pos = V3(nx, m.pos.y, nz); m.yaw = atan2f(-step.x, -step.y)
            }
            return
        }
        // The ground under the new spot: from a little above the body down to 3 below.
        let x = Int(floor(nx)), z = Int(floor(nz))
        var y = Int(floor(m.pos.y + 1.2))
        while y > Int(floor(m.pos.y)) - 3 {
            let b = g.world.block(x, y - 1, z)
            if Blocks.collide[Int(b)] && !Blocks.collide[Int(g.world.block(x, y, z))] { break }
            y -= 1
        }
        guard y > Int(floor(m.pos.y)) - 3 else { return }                 // over a drop: it stays at the edge
        m.pos = V3(nx, Float(y), nz)
        m.yaw = atan2f(-step.x, -step.y)
    }
}
