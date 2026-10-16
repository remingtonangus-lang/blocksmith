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
        quad4(p[0], p[1], p[2], p[3], uv[0], uv[1], uv[2], uv[3], layer, color, overlay: overlay)
    }

    // The same from four corners, without arrays (rain, snow and particles write thousands of quads a frame).
    mutating func quad4(_ p0: V3, _ p1: V3, _ p2: V3, _ p3: V3, _ u0: V2, _ u1: V2, _ u2: V2, _ u3: V2,
                        _ layer: Int, _ color: V4, overlay: Bool = false) {
        guard n + 6 <= capacity else { return }
        let l = Float(layer), o: Float = overlay ? 1 : 0
        let a = EntityVert(pos: V4(p0, l), uv: V4(u0.x, u0.y, o, 0), color: color)
        let c = EntityVert(pos: V4(p2, l), uv: V4(u2.x, u2.y, o, 0), color: color)
        out[n] = a
        out[n + 1] = EntityVert(pos: V4(p1, l), uv: V4(u1.x, u1.y, o, 0), color: color)
        out[n + 2] = c
        out[n + 3] = a
        out[n + 4] = c
        out[n + 5] = EntityVert(pos: V4(p3, l), uv: V4(u3.x, u3.y, o, 0), color: color)
        n += 6
    }

    static let fullUV = (V2(0, 1), V2(1, 1), V2(1, 0), V2(0, 0))
    static let cubeShade: [Float] = [0.8, 0.8, 1.0, 0.55, 0.68, 0.68]

    // Axis-aligned textured cube (block icon in the world), faces shaded like terrain.
    mutating func cube(center c: V3, half h: Float, yaw: Float, block b: BlockID, light: Float, tint: V3 = V3(1, 1, 1)) {
        let cy = cosf(yaw), sy = sinf(yaw)
        let CT = Mesher.cornerTable
        let uv = EntityWriter.fullUV
        func corner(_ f: Int, _ k: Int) -> V3 {
            let ci = (f * 4 + k) * 3
            let l = V3(Float(CT[ci]) * 2 - 1, Float(CT[ci + 1]) * 2 - 1, Float(CT[ci + 2]) * 2 - 1) * h
            return c + V3(cy * l.x + sy * l.z, l.y, -sy * l.x + cy * l.z)
        }
        for f in 0..<6 {
            let s = EntityWriter.cubeShade[f] * light
            let overlaySide = Blocks.tint[Int(b)] == 3 && f != 2
            quad4(corner(f, 0), corner(f, 1), corner(f, 2), corner(f, 3), uv.0, uv.1, uv.2, uv.3,
                  Int(Blocks.tex[Int(b) * 6 + f]), V4((overlaySide ? V3(1, 1, 1) : tint) * s, 1), overlay: overlaySide && f != 3)
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
    var deliberate = false          // dropped by a block the player broke: picked up even if junk
    var hover: Float = 0            // seconds the player has stood over it (junk pickup)
    let spin = Rand.float(in: 0..<(2 * .pi))

    init(_ s: ItemStack, at p: V3, vel v: V3, delay: Float = 0.5) {
        stack = s
        pos = p
        vel = v
        pickupDelay = delay
    }

    func update(_ dt: Float, _ w: World) {
        // Out in an unloaded chunk it waits, its despawn clock too (it aged anyway: death drops vanished 5 minutes after
        // the death however far away the player was; the reference ages items only in loaded chunks).
        // A non-finite position (a NaN launch velocity) can't be converted to a block: the item goes (removed below).
        guard pos.x.isFinite && pos.y.isFinite && pos.z.isFinite else { stack = .empty; return }
        if !w.isLoaded(Int(floor(pos.x)), Int(floor(pos.z))) { return }
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

    // Dropped items are saved with their dimension (drops.json): they lived only in memory, so quitting before going
    // back for the things dropped at a death lost them all.
    struct Saved: Codable { var s: ItemStack; var p: [Float]; var age: Float }
    func save(to sm: SaveManager?) {
        guard let sm else { return }
        let list: [Saved] = items.filter { !$0.stack.isEmpty && $0.pos.y.isFinite }.map { Saved(s: $0.stack, p: [$0.pos.x, $0.pos.y, $0.pos.z], age: $0.age) }
        if let d = try? JSONEncoder().encode(list) { try? d.write(to: sm.dir.appendingPathComponent("drops.json"), options: .atomic) }
    }
    func load(from sm: SaveManager?) {
        guard let sm, let d = try? Data(contentsOf: sm.dir.appendingPathComponent("drops.json")),
              let list = try? JSONDecoder().decode([Saved].self, from: d) else { return }
        for e in list where e.p.count == 3 && !e.s.isEmpty {
            let it = ItemEntity(e.s, at: V3(e.p[0], e.p[1], e.p[2]), vel: .zero, delay: 0.5)
            it.age = e.age
            items.append(it)
        }
    }

    func spawn(_ s: ItemStack, at p: V3, vel: V3? = nil, delay: Float = 0.5, deliberate: Bool = false) {
        if s.isEmpty { return }
        let v = vel ?? V3(Rand.float(in: -1...1), Rand.float(in: 2...3.5), Rand.float(in: -1...1))
        let e = ItemEntity(s, at: p, vel: v, delay: delay)
        e.deliberate = deliberate
        items.append(e)
    }

    // Junk that isn't vacuumed up (Quest round 4): dirt-like blocks and plants (flowers, grass, ferns, saplings, leaves,
    // vines, seeds). The player gets them by standing over them for a second or crouching on them, or by breaking the
    // block themselves.
    private static var junkCache: [ItemID: Bool] = [:]
    static func isJunk(_ s: ItemStack) -> Bool {
        if let j = junkCache[s.item] { return j }
        let k = Items.key(s.item)
        var j = ["dirt", "coarse_dirt", "rooted_dirt", "grass_block", "podzol", "mycelium", "mud", "dirt_path", "vine", "lily_pad",
                 "seagrass", "kelp", "moss_carpet", "hanging_roots", "glow_lichen", "wheat_seeds", "sugar_cane", "cactus"].contains(k)
            || k.hasSuffix("_leaves")
        if !j, let b = s.def.block { j = Blocks.render[Int(b)] == RenderType.cross.rawValue }
        junkCache[s.item] = j
        return j
    }
    private var junkHinted = false

    // Returns the stacks picked up this frame (for sound/feedback).
    @discardableResult
    func update(_ dt: Float, game: Game) -> Int {
        let w = game.world
        var picked = 0
        let pp = game.player.pos
        let pickOnly = game.coop.current > 0          // split screen: a second seat only picks up
        // Riding, the player sits ~1.6 blocks up on a horse: reach down to the mount's feet and a bit wider (playtest
        // v78: items under a horse couldn't be picked up).
        let ridden = game.riding
        let reachXZ: Float = ridden != nil ? 1.9 : 1.3
        let reachDown: Float = ridden.map { max(0.8, pp.y - $0.pos.y + 0.8) } ?? 0.8
        for e in items {
            if !pickOnly { e.update(dt, w) }
            if e.pickupDelay <= 0 && game.alive {
                let d = e.pos - pp
                if abs(d.x) < reachXZ && abs(d.z) < reachXZ && d.y > -reachDown && d.y < 2.3 {
                    if !e.deliberate && ItemEntityManager.isJunk(e.stack) {
                        e.hover += dt
                        if e.hover < 1 && !game.player.sneaking {
                            if !junkHinted && e.hover > 0.3 {
                                junkHinted = true
                                game.onToast?("Plants and dirt aren't picked up on the move: stand over them a moment or crouch")
                            }
                            continue
                        }
                    }
                    let before = e.stack.count
                    e.stack = game.inventory.add(e.stack)
                    if e.stack.count != before || e.stack.isEmpty { picked += 1 }
                } else { e.hover = 0 }
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
            let fill: Float = max(0.08, MobLight.fill * near)
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
