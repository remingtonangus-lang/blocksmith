import Foundation
import simd

// Field of view effects (sprint, flying, speed/slowness, bow draw, spyglass), the spyglass, goat
// horns, and leads (leash animals to the player or tie them to fences).
extension Game {
    func updateFov(_ dt: Float) {
        var target: Float = 1
        if scoping {
            target = 0.1
        } else {
            // Reference: fov scales with (movement speed / walk speed + 1) / 2.
            var speed: Float = 1
            if player.sprinting { speed *= 1.3 }
            speed *= 1 + 0.2 * Float(effects.level(.speed))
            speed *= max(0, 1 - 0.15 * Float(effects.level(.slowness)))
            target = (speed + 1) / 2
            if player.flying { target *= 1.1 }
            if bowCharge > 0 { let c = min(1, bowCharge); target *= 1 - 0.15 * c * c }
            target *= gunFovScale
        }
        fovScale += (target - fovScale) * min(1, dt * (scoping ? 30 : 10))
        scoping = false
    }

    // Held-use gadgets. Returns true when the use was consumed.
    func useGadget(useHeld: Bool, useNow: Bool) -> Bool {
        let k = Items.key(held.item)
        if k == "spyglass" && useHeld { scoping = true; return true }
        if k == "goat_horn" && useNow {
            guard clock - lastHorn > 7 else { return true }
            lastHorn = clock
            sfx(.goatHorn, 2, at: player.eye)
            return true
        }
        return false
    }

    // Right-click a mob with a lead (or a leashed mob with anything to let it go).
    func useLead(_ m: Mob) -> Bool {
        if m.leashed {
            m.leashed = false
            m.knot = nil
            if survival { let r = inventory.add(ItemStack(Items.id("lead"), 1)); if !r.isEmpty { dropItem(r) } }
            return true
        }
        guard Items.key(held.item) == "lead", m.leashable else { return false }
        m.leashed = true
        m.knot = nil
        if survival { consumeHeld() }
        sfx(.armorEquip(0), 0.5, at: m.pos)
        return true
    }

    // Right-click a fence: tie every mob on the player's leads to it (or take tied ones back).
    func useFenceLeash(_ p: IVec3) -> Bool {
        let near = mobs.mobs.filter { $0.leashed && $0.knot == nil && simd_length($0.pos - player.pos) < 12 }
        if !near.isEmpty {
            for m in near { m.knot = p }
            sfx(.place(.wood), 0.6, at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5))
            return true
        }
        let tied = mobs.mobs.filter { $0.leashed && $0.knot == p }
        if !tied.isEmpty && held.isEmpty {
            for m in tied { m.knot = nil }
            return true
        }
        return false
    }

    // Leashes draw as sagging ropes from the mob to the player's hand or the fence knot.
    func writeLeads(_ wr: inout EntityWriter, eye: V3) {
        let white = Int(Tex.id("smoke"))
        for m in mobs.mobs where m.leashed {
            let from = m.pos + V3(0, m.height * 0.8, 0) + m.forward * m.halfW
            let to: V3
            if let k = m.knot { to = V3(Float(k.x) + 0.5, Float(k.y) + 0.6, Float(k.z) + 0.5) }
            else { to = player.pos + V3(0, 1.1, 0) + V3(cosf(player.yaw), 0, -sinf(player.yaw)) * 0.3 }
            if let k = m.knot {
                let c = V3(Float(k.x) + 0.5, Float(k.y) + 0.6, Float(k.z) + 0.5) - eye
                for f in 0..<4 {
                    let a = Float(f) * .pi / 2
                    let d = V3(cosf(a), 0, sinf(a)) * 0.2
                    let s = V3(-d.z, 0, d.x)
                    wr.quad([c + d - s + V3(0, -0.15, 0), c + d + s + V3(0, -0.15, 0), c + d + s + V3(0, 0.15, 0), c + d - s + V3(0, 0.15, 0)],
                            [V2(0.4, 0.4), V2(0.6, 0.4), V2(0.6, 0.6), V2(0.4, 0.6)], white, V4(0.55, 0.4, 0.25, 1))
                }
            }
            let span: V3 = to - from
            let len = simd_length(span)
            let sag: Float = max(0, 1.2 - len * 0.1)
            var prev: V3 = from
            let n = 16
            for i in 1...n {
                let t = Float(i) / Float(n)
                var q: V3 = from + span * t
                q.y -= sinf(t * .pi) * sag
                let a: V3 = prev - eye
                let c: V3 = q - eye
                let seg: V3 = c - a
                let view: V3 = (a + c) * 0.5
                let cr: V3 = simd_cross(seg, view) + V3(1e-5, 0, 0)
                let side: V3 = simd_normalize(cr) * 0.025
                let col = i % 2 == 0 ? V4(0.45, 0.32, 0.2, 1) : V4(0.6, 0.45, 0.3, 1)
                wr.quad([a - side, a + side, c + side, c - side], [V2(0.4, 0.4), V2(0.6, 0.4), V2(0.6, 0.6), V2(0.4, 0.6)], white, col)
                prev = q
            }
        }
    }
}

extension Mob {
    var leashable: Bool {
        !kind.hostile && kind != .villager && kind != .wanderingTrader && spec.behavior != .vehicle && kind != .armorStand
            || kind == .zoglin || kind == .hoglin
    }

    // Pulled toward the anchor beyond 6 blocks; the lead snaps beyond 10 (reference distances).
    func leashTick(_ dt: Float, _ g: Game) {
        let anchor: V3
        if let k = knot {
            let b = g.world.block(k.x, k.y, k.z)
            if !Blocks.key(Blocks.groupBase[Int(b)]).hasSuffix("_fence") { breakLeash(g); return }
            anchor = V3(Float(k.x) + 0.5, Float(k.y), Float(k.z) + 0.5)
        } else {
            anchor = g.player.pos
        }
        let d = anchor - pos
        let len = simd_length(d)
        if len > 10 { breakLeash(g); return }
        if len > 6 {
            let k: Float = (len - 6) * 6 / len
            let pull = d * k
            vel.x += pull.x * dt * 4
            vel.z += pull.z * dt * 4
            if spec.flying || spec.aquatic { vel.y += pull.y * dt * 4 }
            home = anchor
        }
    }

    func breakLeash(_ g: Game) {
        leashed = false
        knot = nil
        g.drops.spawn(ItemStack(Items.id("lead"), 1), at: pos + V3(0, height * 0.7, 0))
    }
}

// Spyglass overlay: black outside a centred circle.
extension Renderer {
    static func scopeRects(W: Float, H: Float) -> [(Float, Float, Float, Float)] {
        let r = min(W, H) * 0.46
        let cx = W / 2, cy = H / 2
        var out: [(Float, Float, Float, Float)] = []
        out.append((0, 0, W, max(0, cy - r)))
        out.append((0, cy + r, W, max(0, H - cy - r)))
        let rows = 96
        let h = 2 * r / Float(rows)
        for i in 0..<rows {
            let y0 = cy - r + Float(i) * h
            let ym = y0 + h / 2 - cy
            let half = sqrtf(max(0, r * r - ym * ym))
            out.append((0, y0, cx - half, h + 0.5))
            out.append((cx + half, y0, W - cx - half, h + 0.5))
        }
        return out
    }
}
