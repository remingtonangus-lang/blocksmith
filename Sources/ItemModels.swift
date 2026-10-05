import Foundation
import simd

// 3D item models (Remington's TV playtest: held items were flat cards, dropped items camera-facing sprites). Every
// sprite item is extruded from its icon: the icon's alpha, captured while the texture layer is generated
// (TextureGen.base), at 64 x 64 samples; front and back faces carry the icon itself (cut out by its own alpha), the side
// walls follow the alpha's 0.5 contour (marching squares: smooth diagonals, no staircase) sampling the colour just
// inside the outline, 1/13 of the item's size thick. One model per texture layer,
// built on first use and kept. Drawn in the entity pass: first-person held items, the player's (and the other co-op
// seats') hand in third person, and dropped items.
enum ItemModels {
    static let G = 64
    static let thickness: Float = 1.0 / 13

    struct Quad { var p: (V3, V3, V3, V3); var uv: (V2, V2, V2, V2); var n: V3 }

    private static let lock = NSLock()
    private static var masks: [Int: [Float]] = [:]
    private static var meshes: [Int: [Quad]] = [:]

    // Texture names of every sprite item (item_<name>, or a shared sprite such as a potion bottle).
    static let itemLayerNames: Set<String> = {
        var s = Set<String>()
        for i in 1..<Items.count {
            let d = Items.def(ItemID(i))
            if let k = d.texKey { s.insert(k) } else if d.sprite != nil { s.insert("item_" + d.name) }
            if let o = d.overlay { s.insert(o) }
        }
        return s
    }()

    // An item's tinted overlay layer (potion liquid, spawn egg shell, tipped arrow head) and its colour.
    static func overlay(_ item: ItemID) -> (Int, V3)? {
        guard case let (l, c)? = Items.overlayLayer(item) else { return nil }
        let h = TextureGen.hex(c)
        return (l, V3(h.x, h.y, h.z))
    }

    // Called from TextureGen.base (concurrently, one layer per call) with the layer's final pixels.
    static func capture(layer: Int, name: String, px: [V4], n: Int) {
        guard !Bench.abNoItemArt, itemLayerNames.contains(name), n > 0, px.count >= n * n else { return }
        // Alpha at the centres of a G x G grid (bilinear between texel centres).
        var m = [Float](repeating: 0, count: G * G)
        for j in 0..<G { for i in 0..<G {
            let fx = (Float(i) + 0.5) / Float(G) * Float(n) - 0.5, fy = (Float(j) + 0.5) / Float(G) * Float(n) - 0.5
            let x0 = max(0, min(n - 1, Int(floorf(fx)))), y0 = max(0, min(n - 1, Int(floorf(fy))))
            let x1 = min(n - 1, x0 + 1), y1 = min(n - 1, y0 + 1)
            let tx = simd_clamp(fx - Float(x0), 0, 1), ty = simd_clamp(fy - Float(y0), 0, 1)
            let top = px[y0 * n + x0].w * (1 - tx) + px[y0 * n + x1].w * tx
            let bot = px[y1 * n + x0].w * (1 - tx) + px[y1 * n + x1].w * tx
            m[j * G + i] = top * (1 - ty) + bot * ty
        } }
        lock.lock(); masks[layer] = m; lock.unlock()
    }

    static var disabled = false                 // harness: --dropstress N --nomodels (sprites, for a cost comparison)

    static func has(_ layer: Int) -> Bool {
        if disabled { return false }
        lock.lock(); defer { lock.unlock() }
        return masks[layer] != nil
    }

    // The model, or nil while it is still being built: the first sight of an item starts its build on a background
    // queue (about a millisecond each; a chest's worth of new drops built on the render thread was a visible hitch) and
    // callers draw the flat sprite until it is ready.
    private static var building = Set<Int>()
    private static let queue = DispatchQueue(label: "item-models", qos: .userInitiated)
    static var synchronous = false              // harness shots: build on the spot so the first frame has the models

    static func quads(_ layer: Int) -> [Quad]? {
        lock.lock()
        if let q = meshes[layer] { lock.unlock(); return q }
        guard let mask = masks[layer] else { lock.unlock(); return nil }
        if synchronous {
            lock.unlock()
            let q = build(mask)
            lock.lock(); meshes[layer] = q; lock.unlock()
            return q
        }
        if !building.contains(layer) {
            building.insert(layer)
            queue.async {
                let q = build(mask)
                lock.lock(); meshes[layer] = q; building.remove(layer); lock.unlock()
            }
        }
        lock.unlock()
        return nil
    }

    // Harness (--itemcheck): builds every captured model once, timed: (models, mean ms, worst ms, mean quads, most
    // quads, bytes if all were kept).
    static func measure() -> (Int, Double, Double, Double, Int, Int) {
        lock.lock(); let all = masks; lock.unlock()
        var total = 0.0, worst = 0.0, quads = 0, most = 0
        for (_, m) in all {
            let t0 = Date()
            let q = build(m)
            let ms = Date().timeIntervalSince(t0) * 1000
            total += ms; worst = max(worst, ms); quads += q.count; most = max(most, q.count)
        }
        let n = max(1, all.count)
        return (all.count, total / Double(n), worst, Double(quads) / Double(n), most, quads * MemoryLayout<Quad>.stride)
    }

    // Local space: the icon in the XY plane, x right and y up, centred, 1 x 1; z toward the icon's front.
    static func build(_ m: [Float]) -> [Quad] {
        let h: Float = thickness / 2
        var q: [Quad] = []
        q.append(Quad(p: (V3(-0.5, -0.5, h), V3(0.5, -0.5, h), V3(0.5, 0.5, h), V3(-0.5, 0.5, h)),
                      uv: (V2(0, 1), V2(1, 1), V2(1, 0), V2(0, 0)), n: V3(0, 0, 1)))
        q.append(Quad(p: (V3(0.5, -0.5, -h), V3(-0.5, -0.5, -h), V3(-0.5, 0.5, -h), V3(0.5, 0.5, -h)),
                      uv: (V2(1, 1), V2(0, 1), V2(0, 0), V2(1, 0)), n: V3(0, 0, -1)))
        // Alpha at grid point (i, j) (sample centres; 0 outside, so every contour closes).
        func a(_ i: Int, _ j: Int) -> Float { i >= 0 && j >= 0 && i < G && j < G ? m[j * G + i] : 0 }
        let g = Float(G)
        func uvAt(_ i: Float, _ j: Float) -> V2 { V2((i + 0.5) / g, (j + 0.5) / g) }
        // Gradient of the bilinear field at grid coordinates (fi, fj), by central differences.
        func alphaAt(_ fi: Float, _ fj: Float) -> Float {
            let i0 = Int(floorf(fi)), j0 = Int(floorf(fj))
            let tx = fi - Float(i0), ty = fj - Float(j0)
            let top = a(i0, j0) * (1 - tx) + a(i0 + 1, j0) * tx
            let bot = a(i0, j0 + 1) * (1 - tx) + a(i0 + 1, j0 + 1) * tx
            return top * (1 - ty) + bot * ty
        }
        func wall(_ p0: V2, _ p1: V2) {
            // p0, p1 in grid coordinates. Outward = down the alpha gradient.
            let mid: V2 = (p0 + p1) * 0.5
            let e: Float = 0.35
            var gu = alphaAt(mid.x + e, mid.y) - alphaAt(mid.x - e, mid.y)
            var gv = alphaAt(mid.x, mid.y + e) - alphaAt(mid.x, mid.y - e)
            let gl = sqrtf(gu * gu + gv * gv)
            if gl < 1e-5 { let d = p1 - p0; gu = d.y; gv = -d.x } else { gu /= gl; gv /= gl }
            // Outward in grid space is (-gu, -gv); the wall samples the colour 2.6 cells (5 px of a 128 px icon) inside
            // the contour, past the dark outline and bevel rim (at 1.2 cells the walls read near-black: blind critic).
            let inset = V2(gu, gv) * 2.6
            let u0 = uvAt(p0.x + inset.x, p0.y + inset.y), u1 = uvAt(p1.x + inset.x, p1.y + inset.y)
            let l0 = V2((p0.x + 0.5) / g - 0.5, 0.5 - (p0.y + 0.5) / g), l1 = V2((p1.x + 0.5) / g - 0.5, 0.5 - (p1.y + 0.5) / g)
            let nrm = simd_normalize(V3(-gu, gv, 0))
            q.append(Quad(p: (V3(l0.x, l0.y, h), V3(l1.x, l1.y, h), V3(l1.x, l1.y, -h), V3(l0.x, l0.y, -h)),
                          uv: (u0, u1, u1, u0), n: nrm))
        }
        // Marching squares over the cells between grid points (-1...G), crossings interpolated at alpha 0.5; the
        // segments are then chained into contours and simplified (Douglas-Peucker, 0.3 cells) into fewer walls.
        var segs: [(V2, V2)] = []
        // (Fixed-size tuples per cell, no arrays: 4,225 cells per model.)
        for j in -1..<G { for i in -1..<G {
            let c = SIMD4<Float>(a(i, j), a(i + 1, j), a(i + 1, j + 1), a(i, j + 1))
            let ins = c .>= SIMD4<Float>(repeating: 0.5)
            if all(ins) || !any(ins) { continue }
            let fi = Float(i), fj = Float(j)
            let cx = SIMD4<Float>(fi, fi + 1, fi + 1, fi), cy = SIMD4<Float>(fj, fj, fj + 1, fj + 1)
            var pts = (V2(0, 0), V2(0, 0), V2(0, 0), V2(0, 0))
            var np = 0
            for e in 0..<4 {
                let k = (e + 1) & 3
                if ins[e] != ins[k] {
                    let t = simd_clamp((0.5 - c[e]) / (c[k] - c[e]), 0, 1)
                    let p = V2(cx[e] + (cx[k] - cx[e]) * t, cy[e] + (cy[k] - cy[e]) * t)
                    switch np { case 0: pts.0 = p; case 1: pts.1 = p; case 2: pts.2 = p; default: pts.3 = p }
                    np += 1
                }
            }
            if np >= 2 { segs.append((pts.0, pts.1)) }
            if np == 4 { segs.append((pts.2, pts.3)) }
        } }
        func key(_ p: V2) -> Int64 { Int64((p.x * 1000).rounded()) * 1_000_003 + Int64((p.y * 1000).rounded()) }
        var ends: [Int64: [Int]] = [:]
        for (k, sg) in segs.enumerated() { ends[key(sg.0), default: []].append(k); ends[key(sg.1), default: []].append(k) }
        var used = [Bool](repeating: false, count: segs.count)
        func next(from p: V2) -> V2? {
            let kp = key(p)
            for k in ends[kp] ?? [] where !used[k] {
                used[k] = true
                return key(segs[k].0) == kp ? segs[k].1 : segs[k].0
            }
            return nil
        }
        func simplify(_ c: [V2], _ lo: Int, _ hi: Int, _ out: inout [V2]) {
            let a = c[lo], b = c[hi]
            var far: Float = 0, at = -1
            if hi > lo + 1 {
                for k in (lo + 1)..<hi {
                    let d: Float
                    let ab = b - a
                    let l2 = simd_dot(ab, ab)
                    if l2 < 1e-8 { d = simd_length(c[k] - a) } else {
                        let t = simd_clamp(simd_dot(c[k] - a, ab) / l2, 0, 1)
                        d = simd_length(c[k] - (a + ab * t))
                    }
                    if d > far { far = d; at = k }
                }
            }
            if at >= 0 && far > 0.3 {
                simplify(c, lo, at, &out)
                simplify(c, at, hi, &out)
            } else {
                out.append(b)
            }
        }
        for start in 0..<segs.count where !used[start] {
            used[start] = true
            var chain = [segs[start].0, segs[start].1]
            while let p = next(from: chain[chain.count - 1]) { chain.append(p) }
            var head: [V2] = []
            while let p = next(from: head.last ?? chain[0]) { head.append(p) }
            if !head.isEmpty { chain = [V2](head.reversed()) + chain }
            var simp: [V2] = [chain[0]]
            simplify(chain, 0, chain.count - 1, &simp)
            for k in 0..<(simp.count - 1) { wall(simp[k], simp[k + 1]) }
        }
        return q
    }

    static let lightDir: V3 = simd_normalize(V3(-0.3, 0.9, 0.4))

    // Writes a model: local point v goes to o + ax * v.x + ay * v.y + az * v.z (the axes carry the scale). `full`
    // false writes only the two faces (far away). Returns false when the layer has no model.
    @discardableResult
    static func write(_ wr: inout EntityWriter, layer: Int, o: V3, ax: V3, ay: V3, az: V3, light: Float,
                      tint: V3 = V3(1, 1, 1), glint: Bool = false, full: Bool = true, overlay: (Int, V3)? = nil) -> Bool {
        guard let qs = quads(layer) else { return false }
        if let (ol, oc) = overlay {
            // The tinted overlay: its own model, a hair thicker so its faces sit just over the base's.
            let k: Float = 1.004
            write(&wr, layer: ol, o: o, ax: ax * k, ay: ay * k, az: az * k, light: light, tint: tint * oc, glint: glint, full: full)
        }
        let g: Float = glint ? 1 : 0
        let count = full ? qs.count : min(2, qs.count)
        for k in 0..<count {
            let q = qs[k]
            let nw = simd_normalize(ax * q.n.x + ay * q.n.y + az * q.n.z)
            // Side walls (k >= 2) no darker than 0.66 of full light: their edge reads as thickness, not a black rim.
            let shade = max(k < 2 ? 0.45 : 0.66, 0.68 + 0.32 * simd_dot(nw, lightDir))
            let c = V4(tint * (shade * light), 1)
            let a = o + ax * q.p.0.x + ay * q.p.0.y + az * q.p.0.z
            let b = o + ax * q.p.1.x + ay * q.p.1.y + az * q.p.1.z
            let cc = o + ax * q.p.2.x + ay * q.p.2.y + az * q.p.2.z
            let d = o + ax * q.p.3.x + ay * q.p.3.y + az * q.p.3.z
            wr.quad(a, b, cc, d, q.uv.0, q.uv.1, q.uv.2, q.uv.3, layer, c, glint: g, kind: k < 2 ? -1 : 0)
        }
        return true
    }

    // An orthonormal hold: the icon's diagonal (handle at the lower left, head at the upper right, as every tool is
    // drawn) along `along`, its face toward `facing`; scaled by `size`.
    // upright: the icon's up (not its diagonal) along `along`, for items held like a card (a potion stood on end, not
    // tipped over at 45 degrees).
    static func basis(along: V3, facing: V3, size: Float, upright: Bool = false) -> (V3, V3, V3) {
        let n = simd_normalize(facing)
        var d = along - n * simd_dot(along, n)
        d = simd_length(d) > 1e-5 ? simd_normalize(d) : simd_normalize(simd_cross(n, V3(1, 0, 0)))
        let e = simd_normalize(simd_cross(n, d))
        if upright { return (-e * size, d * size, n * size) }
        let k: Float = 0.70710678
        let ax = (d - e) * k, ay = (d + e) * k
        return (ax * size, ay * size, n * size)
    }

    // Held size for things held up like a card: hand-sized things (food, potions, materials, seeds) small; shields,
    // armour, boats, carts, banners, books, maps, wings and saddles as large as before (at the small size a shield was
    // a coaster).
    static func heldScale(_ d: ItemDef) -> Float {
        if d.armorSlot != nil { return 1.4 }
        let n = d.name
        if ["shield", "elytra", "saddle", "totem_of_undying"].contains(n) { return 1.4 }
        if n.hasSuffix("_banner") || n.hasSuffix("boat") || n.hasSuffix("_raft") || n.hasSuffix("_horse_armor") { return 1.4 }
        if n.contains("minecart") || n.contains("map") || n.contains("book") { return 1.4 }
        return 1
    }

    // Tools and weapons are held by the handle, diagonal; everything else is held up like a card.
    static func isTool(_ d: ItemDef) -> Bool {
        if d.tool != .none || d.attack > 1 { return true }
        let n = d.name
        return n.hasSuffix("_spear") || ["bow", "crossbow", "trident", "fishing_rod", "carrot_on_a_stick", "warped_fungus_on_a_stick",
                                         "stick", "blaze_rod", "breeze_rod", "flint_and_steel", "shears", "brush", "mace", "spyglass"].contains(n)
    }
}

extension Game {
    // The held item in the third-person hand (own player in F5 views and the other co-op seats): the right arm's
    // transform from the player model, the tool pointing forward along the forearm.
    func writeHeldThirdPerson(_ wr: inout EntityWriter, eye: V3, daylight: Float) {
        let held = inventory.held
        guard !held.isEmpty, heldGun == nil else { return }
        let p = player
        let walk = sinf(walkBob) * 0.8 * walkAmount
        let rotX = walk + playerHitAngle(swing)
        let arm = Part(mn: V3(4, 12, -2), mx: V3(8, 24, 2), pivot: V3(6, 22, 0), rotX: rotX, color: V3(1, 1, 1))
        let r = arm.rotation
        let cy = cosf(p.yaw), sy = sinf(p.yaw)
        let sneak: Float = p.sneaking && !p.flying ? -0.15 : 0
        let base = p.pos + V3(0, sneak, 0) - eye
        func place(_ m: V3) -> V3 {
            let q = arm.place(m, r) * (0.9375 / 16)
            return V3(cy * q.x + sy * q.z, q.y, -sy * q.x + cy * q.z) + base
        }
        func turn(_ m: V3) -> V3 {
            let q = r * m
            return V3(cy * q.x + sy * q.z, q.y, -sy * q.x + cy * q.z)
        }
        let l = world.lightAt(Int(floor(p.pos.x)), Int(floor(p.pos.y + 1)), Int(floor(p.pos.z)))
        let light = max(0.08, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
        let hand = place(V3(6, 12.5, -1))
        if let b = held.def.block, !Blocks.flatIcon(b) {
            wr.cube(center: hand + turn(V3(0, -1, -3)) * (0.9375 / 16), half: 0.12, yaw: p.yaw + 0.4, block: b, light: light)
            return
        }
        guard let layer = Items.texLayer(held.item) else { return }
        let tool = ItemModels.isTool(held.def)
        // Model space: forward is -z, up +y; the arm hangs down, so "forward along the forearm" is -z at rest.
        let along = tool ? turn(V3(0, 0.45, -1)) : turn(V3(0, 1, -0.2))
        let facing = turn(V3(1, 0, 0))
        let size: Float = tool ? 0.62 : 0.3 * ItemModels.heldScale(held.def)   // hand-sized things smaller (as in first person)
        let (ax, ay, az) = ItemModels.basis(along: along, facing: facing, size: size, upright: !tool)
        // The grip point of a tool's icon (lower left, on the handle) sits in the hand.
        let grip: V2 = tool ? V2(-0.3, -0.3) : V2(0, -0.2)
        let o = hand - ax * grip.x - ay * grip.y
        if !ItemModels.write(&wr, layer: layer, o: o, ax: ax, ay: ay, az: az, light: light, glint: held.ench != 0, overlay: ItemModels.overlay(held.item)) {
            // The model still being built (ItemModels.quads): the flat icon in its place for a frame or two.
            wr.sprite(center: o, half: size * 0.5, right: simd_normalize(ax), up: simd_normalize(ay), layer: layer, light: light)
        }
    }
}

extension Renderer {
    static let heldVertCap = 12288

    // The first-person held item as a 3D model (camera space: x right, y up, -z ahead), gripped by the handle: tools
    // angled up and away to the right with the blade turned toward the view, other items held up like a card; a slow
    // idle sway, a chopping arc on a swing, the bow drawn back, food lifted to the mouth while eating.
    func writeHeldModel(_ wr: inout EntityWriter, held: ItemStack, layer: Int, base: V3, light: Float, swing sw: Float) -> Bool {
        guard ItemModels.has(layer) else { return false }
        let t = Float(game.clock)
        let tool = ItemModels.isTool(held.def)
        let sway = V3(sinf(t * 1.1) * 0.006, sinf(t * 1.7) * 0.005, 0)
        // Swing: the head comes down and across (a chop), back up after.
        let a = sinf(sqrtf(max(0, sw)) * .pi)
        let chop = a * (tool ? 1.15 : 0.5)
        // The face turned about 40 degrees off the line to the eye, so the item's thickness shows along one edge (face-on
        // it read as a flat card: blind critic, held round 1).
        var along = tool ? V3(-0.28, 0.9, -0.42) : V3(-0.15, 1, -0.1)
        var facing = tool ? V3(0.25, 0.25, 0.9) : V3(0.2, 0.05, 1)
        // Rotate the hold about the camera's right axis by the chop (head forward and down).
        let c = cosf(chop), s = sinf(chop)
        func rotX(_ v: V3) -> V3 { V3(v.x, v.y * c + v.z * s, -v.y * s + v.z * c) }
        along = rotX(along); facing = rotX(facing)
        var hand = base + (tool ? V3(0.02, 0.0, -0.06) : V3(-0.03, 0.04, -0.06)) + sway
        let name = held.def.name
        if name == "bow" || name == "crossbow" {
            // Held upright, drawn back toward the eye.
            along = V3(-0.5, 0.86, -0.1); facing = V3(-0.3, 0.1, 1)
            hand += V3(-0.12, 0.08, bowPull() * 0.8)
        }
        if held.def.food != nil || held.def.drink, game.eatProgress > 0 {
            let k = min(1, game.eatProgress * 3)
            hand = hand * (1 - k) + V3(0.0, -0.2 + 0.02 * sinf(t * 22), -0.42) * k
        }
        // Hand-sized things (food, potions, materials) about two thirds of a tool (at 0.36 an apple filled the corner).
        let size: Float = tool ? 0.5 : 0.25 * ItemModels.heldScale(held.def)
        let (ax, ay, az) = ItemModels.basis(along: along, facing: facing, size: size, upright: !tool)
        let grip: V2 = tool ? V2(-0.3, -0.3) : V2(0, -0.3)
        let o = hand - ax * grip.x - ay * grip.y
        return ItemModels.write(&wr, layer: layer, o: o, ax: ax, ay: ay, az: az, light: light, glint: held.ench != 0,
                                overlay: ItemModels.overlay(held.item))
    }
}

extension Game {
    // The other co-op seats' held items (their bodies come from Coop.writeOthers).
    func writeHeldOtherSeats(_ wr: inout EntityWriter, eye: V3, daylight: Float) {
        guard coop.active else { return }
        let me = coop.current
        for i in 0..<coop.slots.count where i != me {
            coop.withSeat(i, self) { writeHeldThirdPerson(&wr, eye: eye, daylight: daylight) }
        }
    }
}
