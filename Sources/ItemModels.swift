import Foundation
import simd

// 3D item models (Remington's TV playtest: held items were flat cards, dropped items camera-facing sprites). Every
// sprite item is extruded from its icon: the icon's alpha mask, captured while the texture layer is generated
// (TextureGen.base), at 32 x 32 cells; front and back faces carry the icon itself, the side walls run round the mask's
// edges (merged into strips) sampling the edge texels, 1/16 of the item's size thick. One model per texture layer,
// built on first use and kept. Drawn in the entity pass: first-person held items, the player's (and the other co-op
// seats') hand in third person, and dropped items.
enum ItemModels {
    static let G = 32
    static let thickness: Float = 1.0 / 16

    struct Quad { var p: (V3, V3, V3, V3); var uv: (V2, V2, V2, V2); var n: V3 }

    private static let lock = NSLock()
    private static var masks: [Int: [Bool]] = [:]
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
        guard itemLayerNames.contains(name), n > 0, px.count >= n * n else { return }
        var m = [Bool](repeating: false, count: G * G)
        for j in 0..<G { for i in 0..<G {
            let x = min(n - 1, (i * n + n / 2) / G), y = min(n - 1, (j * n + n / 2) / G)
            m[j * G + i] = px[y * n + x].w >= 0.5
        } }
        lock.lock(); masks[layer] = m; lock.unlock()
    }

    static var disabled = false                 // harness: --dropstress N --nomodels (sprites, for a cost comparison)

    static func has(_ layer: Int) -> Bool {
        if disabled { return false }
        lock.lock(); defer { lock.unlock() }
        return masks[layer] != nil
    }

    static func quads(_ layer: Int) -> [Quad]? {
        lock.lock()
        if let q = meshes[layer] { lock.unlock(); return q }
        let m = masks[layer]
        lock.unlock()
        guard let mask = m else { return nil }
        let q = build(mask)
        lock.lock(); meshes[layer] = q; lock.unlock()
        return q
    }

    // Local space: the icon in the XY plane, x right and y up, centred, 1 x 1; z toward the icon's front.
    static func build(_ m: [Bool]) -> [Quad] {
        let s: Float = 1 / Float(G), h: Float = thickness / 2
        func filled(_ i: Int, _ j: Int) -> Bool { i >= 0 && j >= 0 && i < G && j < G && m[j * G + i] }
        var q: [Quad] = []
        q.append(Quad(p: (V3(-0.5, -0.5, h), V3(0.5, -0.5, h), V3(0.5, 0.5, h), V3(-0.5, 0.5, h)),
                      uv: (V2(0, 1), V2(1, 1), V2(1, 0), V2(0, 0)), n: V3(0, 0, 1)))
        q.append(Quad(p: (V3(0.5, -0.5, -h), V3(-0.5, -0.5, -h), V3(-0.5, 0.5, -h), V3(0.5, 0.5, -h)),
                      uv: (V2(1, 1), V2(0, 1), V2(0, 0), V2(1, 0)), n: V3(0, 0, -1)))
        // Top and bottom walls: runs along each row.
        for j in 0..<G {
            for (dj, ny) in [(-1, Float(1)), (1, Float(-1))] {
                var i = 0
                while i < G {
                    guard filled(i, j) && !filled(i, j + dj) else { i += 1; continue }
                    var e = i
                    while e + 1 < G && filled(e + 1, j) && !filled(e + 1, j + dj) { e += 1 }
                    let x0 = Float(i) * s - 0.5, x1 = Float(e + 1) * s - 0.5
                    let y: Float = 0.5 - Float(dj < 0 ? j : j + 1) * s
                    let u0 = (Float(i) + 0.5) * s, u1 = (Float(e) + 0.5) * s, v = (Float(j) + 0.5) * s
                    q.append(Quad(p: (V3(x0, y, h), V3(x1, y, h), V3(x1, y, -h), V3(x0, y, -h)),
                                  uv: (V2(u0, v), V2(u1, v), V2(u1, v), V2(u0, v)), n: V3(0, ny, 0)))
                    i = e + 1
                }
            }
        }
        // Left and right walls: runs down each column.
        for i in 0..<G {
            for (di, nx) in [(-1, Float(-1)), (1, Float(1))] {
                var j = 0
                while j < G {
                    guard filled(i, j) && !filled(i + di, j) else { j += 1; continue }
                    var e = j
                    while e + 1 < G && filled(i, e + 1) && !filled(i + di, e + 1) { e += 1 }
                    let x: Float = Float(di < 0 ? i : i + 1) * s - 0.5
                    let y0 = 0.5 - Float(j) * s, y1 = 0.5 - Float(e + 1) * s
                    let u = (Float(i) + 0.5) * s, v0 = (Float(j) + 0.5) * s, v1 = (Float(e) + 0.5) * s
                    q.append(Quad(p: (V3(x, y0, h), V3(x, y1, h), V3(x, y1, -h), V3(x, y0, -h)),
                                  uv: (V2(u, v0), V2(u, v1), V2(u, v1), V2(u, v0)), n: V3(nx, 0, 0)))
                    j = e + 1
                }
            }
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
            let shade = max(0.45, 0.68 + 0.32 * simd_dot(nw, lightDir))
            let c = V4(tint * (shade * light), 1)
            let a = o + ax * q.p.0.x + ay * q.p.0.y + az * q.p.0.z
            let b = o + ax * q.p.1.x + ay * q.p.1.y + az * q.p.1.z
            let cc = o + ax * q.p.2.x + ay * q.p.2.y + az * q.p.2.z
            let d = o + ax * q.p.3.x + ay * q.p.3.y + az * q.p.3.z
            wr.quad(a, b, cc, d, q.uv.0, q.uv.1, q.uv.2, q.uv.3, layer, c, glint: g)
        }
        return true
    }

    // An orthonormal hold: the icon's diagonal (handle at the lower left, head at the upper right, as every tool is
    // drawn) along `along`, its face toward `facing`; scaled by `size`.
    static func basis(along: V3, facing: V3, size: Float) -> (V3, V3, V3) {
        let n = simd_normalize(facing)
        var d = along - n * simd_dot(along, n)
        d = simd_length(d) > 1e-5 ? simd_normalize(d) : simd_normalize(simd_cross(n, V3(1, 0, 0)))
        let e = simd_normalize(simd_cross(n, d))
        let k: Float = 0.70710678
        let ax = (d - e) * k, ay = (d + e) * k
        return (ax * size, ay * size, n * size)
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
        let size: Float = tool ? 0.62 : 0.4
        let (ax, ay, az) = ItemModels.basis(along: along, facing: facing, size: size)
        // The grip point of a tool's icon (lower left, on the handle) sits in the hand.
        let grip: V2 = tool ? V2(-0.3, -0.3) : V2(0, -0.2)
        let o = hand - ax * grip.x - ay * grip.y
        ItemModels.write(&wr, layer: layer, o: o, ax: ax, ay: ay, az: az, light: light, glint: held.ench != 0, overlay: ItemModels.overlay(held.item))
    }
}

extension Renderer {
    static let heldVertCap = 6144

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
        var along = tool ? V3(-0.28, 0.9, -0.42) : V3(-0.15, 1, -0.1)
        var facing = tool ? V3(-0.62, 0.18, 0.76) : V3(-0.2, 0.05, 1)
        // Rotate the hold about the camera's right axis by the chop (head forward and down).
        let c = cosf(chop), s = sinf(chop)
        func rotX(_ v: V3) -> V3 { V3(v.x, v.y * c + v.z * s, -v.y * s + v.z * c) }
        along = rotX(along); facing = rotX(facing)
        var hand = base + V3(0.02, 0.0, -0.06) + sway
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
        let size: Float = tool ? 0.5 : 0.36
        let (ax, ay, az) = ItemModels.basis(along: along, facing: facing, size: size)
        let grip: V2 = tool ? V2(-0.3, -0.3) : V2(0, -0.18)
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
