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
        // P258: a fallen body (MobManager.corpses): the ragdoll bone and the point on it the hand holds (rag -1: a body
        // with no ragdoll, dragged by its position).
        var corpse = false
        var rag = -1, bone = 0
        var local = SIMD3<Float>(0, 0, 0)
        init(_ m: Mob, body: Bool, at p: V3, carcass: Bool = false, item: ItemEntity? = nil) {
            mob = m; self.body = body; self.carcass = carcass; self.item = item; last = p
        }
    }
    // P258 (Oct 14 12:43, "pick up a body by holding grip on it and drag or carry it"): one hand drags (the part held
    // no higher than his waist), both hands on the same body carry it; his walk slows with the load.
    static func both(_ m: Mob) -> Bool { held[0]?.mob === m && held[1]?.mob === m }
    static var slow: Float {
        var k: Float = 1
        for h in held { if let h, h.body || h.corpse { k = min(k, 0.75) } }
        if let a = held[0], a.mob !== placeholder, both(a.mob) { k = 0.6 }
        return k
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
            else if h.corpse { gone = !g.mobs.corpses.contains { $0 === h.mob } }
            else if h.carcass { gone = !Hunting.bodies.contains { $0.mob === h.mob } }
            else { gone = h.mob.health <= 0 || !g.mobs.mobs.contains { $0 === h.mob } }
            if gone { if h.corpse { g.debris.ragdolls.release(hand: i) }; held[i] = nil; return grip }
            if grip {
                // The hand's speed while it holds (the release frame's own sample is left out: let go mid-swing, the
                // throw keeps the swing's speed).
                let v = (p - h.last) / max(dt, 0.001)
                h.vel = h.vel * 0.55 + v * 0.45
                h.last = p
                if let it = h.item {
                    it.pos = p - V3(0, 0.125, 0); it.vel = .zero; it.onGround = false
                    it.pickupDelay = max(it.pickupDelay, 0.4)              // not swept into the pack while it is in the hand
                } else if h.corpse { holdBody(g, h, hand: i, at: p) }
                else if h.body && both(h.mob) {
                    // P258 (c): two hands under a carcass (or anything dragged) lift it between them.
                    if i == 1, let o = held[0] { carry(h.mob, at: (p + o.last) * 0.5 + V3(0, -0.1, 0)) }
                } else if h.body { drag(g, h.mob, toward: p) } else { carry(h.mob, at: p) }
                return true
            }
            held[i] = nil
            if h.corpse {
                // P258 (d, e): let go: it drops (the ragdoll keeps the hand's swing); a carried body lands with a thud.
                g.debris.ragdolls.release(hand: i)
                if held[1 - i]?.mob !== h.mob { g.sfx(.land, 0.9, at: p); g.sfx(.plantBrush, 0.6, at: p) }
                return true
            }
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
        for b in Hunting.bodies where b.dim == g.world.dim && (!holds(b.mob) || held[1 - i]?.mob === b.mob) && held[i]?.mob !== b.mob {
            let m = b.mob
            let d = simd_length(m.pos + V3(0, 0.3, 0) - p) - max(m.halfW, m.height * 0.5)
            if d < reach && d < bestD { bestD = d; best = (m, true); carcass = true }
        }
        // P258 (b): a fallen body: the ragdoll bone under the hand (or the body itself when it has no ragdoll). The other
        // hand may hold it already: that is the carry.
        var corpseHold: (Mob, Int, Int, SIMD3<Float>)?
        let rw = g.debris.ragdolls
        for c in g.mobs.corpses where held[i]?.mob !== c && (!holds(c) || held[1 - i]?.mob === c) {
            if let r = c.ragdoll, rw.isLive(r.id) {
                guard let nb = rw.nearestBone(r.id, to: p, reach: reach + 0.1), nb.dist < bestD else { continue }
                bestD = nb.dist; corpseHold = (c, r.id, nb.bone, nb.local); best = nil
            } else {
                let lo = c.pos - V3(c.halfW, 0, c.halfW), hi = c.pos + V3(c.halfW, 0.6, c.halfW)
                let d = simd_length(simd_clamp(p, lo, hi) - p)
                if d < reach && d < bestD { bestD = d; corpseHold = (c, -1, 0, .zero); best = nil }
            }
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
                if d < reach && d < bestD { bestD = d; best = (m, true); carcass = false; corpseHold = nil }
            }
        }
        if item == nil, let (c, rag, bone, local) = corpseHold {
            let h = Hold(c, body: true, at: p)
            h.corpse = true; h.rag = rag; h.bone = bone; h.local = local
            held[i] = h
            grabs += 1; drags += 1
            g.sfx(.plantBrush, 0.9, at: p)
            if both(c) { g.onToast?("Carrying \(c.customName ?? c.spec.name)") }
            return true
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

    // P258: a held body's ragdoll point follows the hand (one hand: no higher than his waist, so it drags); a body
    // with no ragdoll is dragged, or carried between two hands. A Greywall body is then found where it lies (D36).
    static func holdBody(_ g: Game, _ h: Hold, hand i: Int, at p: V3) {
        let two = both(h.mob)
        let rw = g.debris.ragdolls
        var t = p
        if !two { t.y = min(t.y, g.player.pos.y + 0.85) }
        let was = h.mob.pos
        if h.rag >= 0 && rw.isLive(h.rag) {
            rw.hold(hand: i, h.rag, bone: h.bone, local: h.local, at: t)
            h.mob.pos = rw.pose(h.rag, 0).position
        } else if two {
            if i == 1, let o = held[0] { carry(h.mob, at: (p + o.last) * 0.5 + V3(0, -0.1, 0)) }
        } else {
            drag(g, h.mob, toward: t)
        }
        if simd_length(h.mob.pos - was) > 0.01 { Bodies.moved(from: was, to: h.mob.pos) }
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
        // PG2 rewrite: a field world's ground is met at its surface (a body set on a cell top hovered or sank).
        if g.world.fieldTerrain {
            guard let y = g.world.restHeight(V3(nx, m.pos.y, nz), halfW: min(0.3, m.halfW), up: 1.2, depth: 3) else { return }
            m.pos = V3(nx, y, nz); m.yaw = atan2f(-step.x, -step.y)
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
