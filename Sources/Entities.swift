import Foundation
import simd

// Textured entity geometry (dropped items, block crack overlay, held items...).
// pos.xyz camera-relative, pos.w = texture layer; uv; color.rgb multiplier, color.a alpha.
struct EntityVert { var pos: V4; var uv: V4; var color: V4 }

// Appends triangles into a raw vertex buffer with a capacity check.
struct EntityWriter {
    let out: UnsafeMutablePointer<EntityVert>
    let capacity: Int
    var n = 0

    mutating func quad(_ p: [V3], _ uv: [V2], _ layer: Int, _ color: V4, overlay: Bool = false) {
        guard n + 6 <= capacity else { return }
        for i in [0, 1, 2, 0, 2, 3] {
            out[n] = EntityVert(pos: V4(p[i], Float(layer)), uv: V4(uv[i].x, uv[i].y, overlay ? 1 : 0, 0), color: color)
            n += 1
        }
    }

    // Axis-aligned textured cube (block icon in the world), faces shaded like terrain.
    mutating func cube(center c: V3, half h: Float, yaw: Float, block b: BlockID, light: Float, tint: V3 = V3(1, 1, 1)) {
        let cy = cosf(yaw), sy = sinf(yaw)
        let CT = Mesher.cornerTable
        let shade: [Float] = [0.8, 0.8, 1.0, 0.55, 0.68, 0.68]
        let uvs = [V2(0, 1), V2(1, 1), V2(1, 0), V2(0, 0)]
        for f in 0..<6 {
            var ps: [V3] = []
            for k in 0..<4 {
                let ci = (f * 4 + k) * 3
                let l = V3(Float(CT[ci]) * 2 - 1, Float(CT[ci + 1]) * 2 - 1, Float(CT[ci + 2]) * 2 - 1) * h
                ps.append(c + V3(cy * l.x + sy * l.z, l.y, -sy * l.x + cy * l.z))
            }
            let s = shade[f] * light
            let overlaySide = Blocks.tint[Int(b)] == 3 && f != 2
            quad(ps, uvs, Int(Blocks.tex[Int(b) * 6 + f]), V4((overlaySide ? V3(1, 1, 1) : tint) * s, 1), overlay: overlaySide && f != 3)
        }
    }

    // Flat sprite facing the camera (both sides visible: drawn without culling).
    mutating func sprite(center c: V3, half h: Float, right r: V3, up u: V3, layer: Int, light: Float, tint: V3 = V3(1, 1, 1)) {
        let rr = r * h, uu = u * h
        quad([c - rr - uu, c + rr - uu, c + rr + uu, c - rr + uu], [V2(0, 1), V2(1, 1), V2(1, 0), V2(0, 0)], layer, V4(tint * light, 1))
    }
}

final class ItemEntity {
    var stack: ItemStack
    var pos: V3
    var vel: V3
    var age: Float = 0
    var pickupDelay: Float
    var onGround = false
    let spin = Rand.float(in: 0..<(2 * .pi))

    init(_ s: ItemStack, at p: V3, vel v: V3, delay: Float = 0.5) {
        stack = s
        pos = p
        vel = v
        pickupDelay = delay
    }

    func update(_ dt: Float, _ w: World) {
        age += dt
        pickupDelay -= dt
        let inWater = Blocks.isLiquid(w.block(Int(floor(pos.x)), Int(floor(pos.y + 0.1)), Int(floor(pos.z))))
        if inWater {
            vel.y += (1.2 - vel.y) * min(1, dt * 4)
            vel.x *= expf(-2 * dt); vel.z *= expf(-2 * dt)
        } else {
            vel.y -= 16 * dt
            vel.y = max(vel.y, -40)
        }
        if onGround { let f = expf(-10 * dt); vel.x *= f; vel.z *= f }
        if !w.isLoaded(Int(floor(pos.x)), Int(floor(pos.z))) { return }
        if w.collides(V3(pos.x - 0.125, pos.y, pos.z - 0.125), V3(pos.x + 0.125, pos.y + 0.25, pos.z + 0.125)) { pos.y += 0.3; vel.y = 0 }
        let hit = w.moveBody(&pos, halfW: 0.125, height: 0.25, vel * dt, step: 0, onGround: onGround)
        if hit.y { onGround = vel.y < 0; vel.y = 0 } else { onGround = false }
        if hit.x { vel.x = 0 }
        if hit.z { vel.z = 0 }
    }
}

final class ItemEntityManager {
    var items: [ItemEntity] = []
    private var mergeTimer: Float = 0

    func spawn(_ s: ItemStack, at p: V3, vel: V3? = nil, delay: Float = 0.5) {
        if s.isEmpty { return }
        let v = vel ?? V3(Rand.float(in: -1...1), Rand.float(in: 2...3.5), Rand.float(in: -1...1))
        items.append(ItemEntity(s, at: p, vel: v, delay: delay))
    }

    // Returns the stacks picked up this frame (for sound/feedback).
    @discardableResult
    func update(_ dt: Float, game: Game) -> Int {
        let w = game.world
        var picked = 0
        let pp = game.player.pos
        let pickOnly = game.coop.current > 0          // split screen: a second seat only picks up
        for e in items {
            if !pickOnly { e.update(dt, w) }
            if e.pickupDelay <= 0 && game.alive {
                let d = e.pos - pp
                if abs(d.x) < 1.3 && abs(d.z) < 1.3 && d.y > -0.8 && d.y < 2.3 {
                    let before = e.stack.count
                    e.stack = game.inventory.add(e.stack)
                    if e.stack.count != before || e.stack.isEmpty { picked += 1 }
                }
            }
        }
        if pickOnly { if picked > 0 { game.sfx(.pickup, 0.5) }; return picked }
        items.removeAll { $0.stack.isEmpty || $0.age > 300 || $0.pos.y < -64 }
        // Merge nearby identical stacks now and then.
        mergeTimer -= dt
        if mergeTimer <= 0 && items.count > 1 {
            mergeTimer = 0.5
            for i in 0..<items.count {
                let a = items[i]
                if a.stack.isEmpty { continue }
                for j in (i + 1)..<items.count {
                    let b = items[j]
                    if b.stack.isEmpty || !a.stack.stacks(with: b.stack) { continue }
                    if simd_length_squared(a.pos - b.pos) > 0.5 * 0.5 { continue }
                    let n = min(b.stack.count, a.stack.maxStack - a.stack.count)
                    a.stack.count += n
                    b.stack.count -= n
                }
            }
            items.removeAll { $0.stack.isEmpty }
        }
        if picked > 0 { game.sfx(.pickup, 0.5) }
        return picked
    }

    func write(_ wr: inout EntityWriter, eye: V3, right: V3, up: V3, world: World, daylight: Float, time: Float) {
        for e in items {
            let bob = sinf(e.age * 2.5 + e.spin) * 0.06 + 0.12
            let c = e.pos + V3(0, bob, 0) - eye
            let l = world.lightAt(Int(floor(e.pos.x)), Int(floor(e.pos.y + 0.2)), Int(floor(e.pos.z)))
            // The cave fill (Shaders.caveFill): an item on a dark cave floor shows like the floor around it.
            let near: Float = 1 - 0.55 * Terrain.smooth(5, 30, simd_length(c))
            let fill: Float = max(0.08, (0.05 + 0.2 * Settings.shared.lightBrightness) * near)
            let light = max(fill, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
            let copies = e.stack.count > 32 ? 3 : (e.stack.count > 1 ? 2 : 1)
            for k in 0..<copies {
                let off = V3(Float(k) * 0.06, Float(k) * 0.05, Float(k) * -0.05)
                if let b = e.stack.def.block, !Blocks.flatIcon(b) {
                    let t = Blocks.tint[Int(b)]
                    let tint = t == 1 || t == 3 ? V3(0.57, 0.74, 0.35) : (t == 2 ? V3(0.47, 0.67, 0.18) : V3(1, 1, 1))
                    wr.cube(center: c + off, half: 0.125, yaw: e.age * 1.5 + e.spin, block: b, light: light, tint: tint)
                } else {
                    let layer = Items.texLayer(e.stack.item) ?? Int(Blocks.tex[Int(e.stack.def.block ?? 0) * 6])
                    wr.sprite(center: c + off + V3(0, 0.05, 0), half: 0.2, right: right, up: up, layer: layer, light: light)
                }
            }
        }
    }
}
