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
    // P142: drawn this far up or down onto the smooth ground it rests on (World.smoothGroundOffset), eased.
    var viewDY: Float = 0, groundKey = Int.min, groundH = SIMD4<Float>(repeating: 0)
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
        if HandGrab.holds(self) { return }                    // H12: in a hand (HandGrab.swift moves it)
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
        if w.collides(V3(pos.x - 0.125, pos.y, pos.z - 0.125), V3(pos.x + 0.125, pos.y + 0.25, pos.z + 0.125)) {
            // PG2 rewrite: inside a field world's ground (dropped from a dug cell into its rounded wall) it is pushed out
            // along the ground's normal to the surface; popped up 0.3 a tick, a buried item rose through a hillside to
            // its top (45 blocks in 5 s, --fieldbodies) and ore mined from a wall was never seen again.
            if !(w.fieldTerrain && pushOutOfField(w)) { pos.y += 0.3; vel.y = 0 }
        }
        let before = pos
        let hit = w.moveBody(&pos, halfW: 0.125, height: 0.25, vel * dt, step: 0, onGround: onGround)
        if hit.y { onGround = vel.y < 0; vel.y = 0 } else { onGround = false }
        // On a ship's deck (P70, playtest 09:20: "the pieces are falling through the ship"): the world's collision has
        // no ship blocks, so a drop into a ship's cell stops where it was.
        if !hit.y && w.ships.solid(at: pos) { pos = V3(pos.x, before.y, pos.z); if w.ships.solid(at: pos) { pos = before }; onGround = vel.y < 0; vel = .zero }
        if hit.x { vel.x = 0 }
        if hit.z { vel.z = 0 }
        // Resting on smooth ground it lies on the drawn surface, not the block top under it (up to 0.6 off); in the air
        // it drifts back to its box.
        let target = onGround ? w.smoothGroundOffset(pos, key: &groundKey, heights: &groundH) : 0
        viewDY += (target - viewDY) * min(1, dt * (onGround ? 10 : 3))
    }

    // Out of the field's ground the shortest way: along its outward normal, a little past the surface. false: not the
    // field that holds it (a built block), or nothing free within a block that way.
    func pushOutOfField(_ w: World) -> Bool {
        let c = pos + V3(0, 0.125, 0)
        let d = w.fieldDensity(at: c)
        guard d > -0.3 else { return false }
        let g = w.fieldGradient(c)
        let l = simd_length(g)
        guard l > 1e-4 else { return false }
        let out = -g / l
        for extra: Float in [0.2, 0.45, 0.8] {
            let q = pos + out * (max(0, d) + extra)
            if !w.collides(V3(q.x - 0.125, q.y, q.z - 0.125), V3(q.x + 0.125, q.y + 0.25, q.z + 0.125)) { pos = q; vel = .zero; return true }
        }
        return false
    }
}

final class ItemEntityManager {
    // How many copies a dropped stack draws (the reference's piles: 1, 2-16, 17-32, 33-48, 49+). It was 1/2/3 with the
    // copies 0.06 apart, so a stack read as a single item (Oct 11 Quest playtest P5).
    static func copies(_ count: Int) -> Int { count <= 1 ? 1 : (count <= 16 ? 2 : (count <= 32 ? 3 : (count <= 48 ? 4 : 5))) }
    var items: [ItemEntity] = []
    private var mergeTimer: Float = 0

    // Dropped items are saved with their dimension (drops.json): they lived only in memory, so quitting before going
    // back for the things dropped at a death lost them all.
    struct Saved: Codable { var s: ItemStack; var p: [Float]; var age: Float }
    func save(to sm: SaveManager?, background: Bool = false) {
        guard let sm else { return }
        let list: [Saved] = items.filter { !$0.stack.isEmpty && $0.pos.y.isFinite }.map { Saved(s: $0.stack, p: [$0.pos.x, $0.pos.y, $0.pos.z], age: $0.age) }
        let url = sm.dir.appendingPathComponent("drops.json")
        if background { SaveIO.writeJSON(list, to: url) }
        else if let d = try? JSONEncoder().encode(list) { try? d.write(to: url, options: .atomic) }
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
        if let h = NetCoop.redirect { h.drop(s, at: p); return }      // C14: loot of a mob the co-op guest killed
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

    private(set) var burned = 0                    // items burnt up in lava or fire (tests)
    static func burns(_ s: ItemStack) -> Bool {
        let k = s.def.name
        return !(k.hasPrefix("netherite") || k == "ancient_debris" || k == "nether_star")
    }

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
        // P114 (Oct 12 PM: "items should burn when they're thrown into lava"): a dropped item in lava or fire burns up
        // with a hiss and a puff of smoke (Duskium gear and the Emberdeep's star survive, as in the reference).
        for e in items where !e.stack.isEmpty && ItemEntityManager.burns(e.stack) {
            // R17: any touch burns it. Items bob in a liquid, so on a lava surface the one cell at its middle was
            // often the air above (it floated on the lava for a while, then got picked up again).
            let ix = Int(floor(e.pos.x)), iz = Int(floor(e.pos.z))
            let b = w.block(ix, Int(floor(e.pos.y + 0.1)), iz), b0 = w.block(ix, Int(floor(e.pos.y - 0.05)), iz)
            guard Blocks.fluidKind[Int(b)] == 2 || b == FIRE || Blocks.fluidKind[Int(b0)] == 2 || b0 == FIRE else { continue }
            e.stack = ItemStack()
            burned += 1
            for _ in 0..<4 { game.particles.smoke(at: e.pos + V3(0, 0.2, 0)) }
            game.sfx(.fizz, 0.5, at: e.pos)
        }
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
            let c = e.pos + V3(0, bob + e.viewDY, 0) - eye
            let l = world.lightAt(Int(floor(e.pos.x)), Int(floor(e.pos.y + 0.2)), Int(floor(e.pos.z)))
            // The cave fill (Shaders.caveFill): an item on a dark cave floor shows like the floor around it.
            let near: Float = 1 - 0.55 * Terrain.smooth(5, 30, simd_length(c))
            let fill: Float = max(0.08, MobLight.fill * near)
            let light = max(fill, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
            let copies = ItemEntityManager.copies(e.stack.count)
            for k in 0..<copies {
                if let b = e.stack.def.block, !Blocks.flatIcon(b) {
                    // A small pile turning with the stack: the copies sit round its centre, the later ones higher.
                    let a = e.age * 1.5 + e.spin + Float(k) * 2.4
                    let off = k == 0 ? V3(0, 0, 0) : V3(cosf(a) * 0.13, Float(k) * 0.07, sinf(a) * 0.13)
                    let t = Blocks.tint[Int(b)]
                    let tint = t == 1 || t == 3 ? V3(0.57, 0.74, 0.35) : (t == 2 ? V3(0.47, 0.67, 0.18) : V3(1, 1, 1))
                    wr.cube(center: c + off, half: 0.125, yaw: e.age * 1.5 + e.spin, block: b, light: light, tint: tint)
                } else {
                    // Flat icons fan out across the view (offsets along the camera's own axes stay visible) and
                    // step back a little so they overlap like a held hand of cards.
                    let off = right * (Float(k) * 0.08) - up * (Float(k) * 0.06) + simd_normalize(c) * (Float(k) * 0.02)
                    let layer = Items.texLayer(e.stack.item) ?? Int(Blocks.tex[Int(e.stack.def.block ?? 0) * 6])
                    // (`up` arrives pointing down, the particles' convention: the icon's top row goes up. P47: it drew
                    // upside down on both renderers, plain on a pile of gunpowder.)
                    wr.sprite(center: c + off + V3(0, 0.05, 0), half: 0.2, right: right, up: -up, layer: layer, light: light)
                }
            }
        }
    }
}
