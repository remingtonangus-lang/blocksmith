import Foundation
import simd

// P338 step 8 ("player building moves off the block grid too: building pieces placed freely and snapped to each other
// and to the ground, not to a world grid; existing block worlds and builds keep loading"): in a field world the building
// blocks in hand set down free pieces instead of cubes. Sneak keeps placing the classic block.
//
//   held                               piece
//   a built full block (planks, bricks) wall, 2 x 2 blocks, 0.2 thick
//   a slab                             floor, 2 x 2, 0.2 thick
//   stairs                             a flight (1 wide, 2 up over 2), or a roof panel when aimed at a wall's top
//   a fence or a wall block            post, 2 tall
//   a door                             door, 1 x 2, opened and shut with use
//   a pane                             window: a wall with a 1 x 1 opening glazed with the pane
//
// Pieces sit anywhere at any heading. On the ground a piece rests on the drawn surface (a floor on the highest of its
// corners, so it stands level) facing the way you look. Aimed at a piece it snaps to it: a wall on a wall's top or end
// continues it, on its face starts a wall at right angles, on a floor's edge stands along that edge; a floor at a
// floor's edge joins it, on a wall's top it hangs out from it; stairs on a wall's top are a roof panel rising away from
// you. Pieces collide (World.collisionBoxes), draw in the section mesh's detail stream (FreeBuild.emit) and are saved
// per world in pieces.json. Breaking one gives its block back.
struct FreePiece: Codable, Equatable {
    var k: UInt8                    // FreeBuild.Kind
    var m: String                   // material block key
    var p: [Float]                  // origin (bottom centre; a roof: the middle of its low edge)
    var yaw: Float
    var open: Bool? = nil           // a door

    var kind: FreeBuild.Kind { FreeBuild.Kind(rawValue: k) ?? .wall }
    var origin: V3 { V3(p[0], p[1], p[2]) }
    var mat: BlockID { Blocks.has(m) ? Blocks.id(m) : PLANKS }
    var ax: V3 { V3(cosf(yaw), 0, -sinf(yaw)) }
    var az: V3 { V3(sinf(yaw), 0, cosf(yaw)) }
    func world(_ q: V3) -> V3 { origin + ax * q.x + V3(0, q.y, 0) + az * q.z }
    func local(_ w: V3) -> V3 { let d = w - origin; return V3(simd_dot(d, ax), d.y, simd_dot(d, az)) }
}

enum FreeBuild {
    enum Kind: UInt8 { case wall, floor, stairs, roof, post, door, window }
    static let roofPitch: Float = atanf(0.5)
    static let roofLen: Float = (4 + 1 as Float).squareRoot()

    // The piece's parts in its own frame (before a roof's pitch), and whether each is the glazing.
    static func parts(_ k: Kind, open: Bool) -> [(mn: V3, mx: V3, glass: Bool)] {
        switch k {
        case .wall: return [(V3(-1, 0, -0.1), V3(1, 2, 0.1), false)]
        case .floor: return [(V3(-1, 0, -1), V3(1, 0.2, 1), false)]
        case .roof: return [(V3(-1, 0, 0), V3(1, 0.15, roofLen), false)]
        case .post: return [(V3(-0.13, 0, -0.13), V3(0.13, 2, 0.13), false)]
        case .stairs: return (0..<4).map { s in (V3(-0.5, 0, -1 + 0.5 * Float(s)), V3(0.5, 0.5 * Float(s + 1), -0.5 + 0.5 * Float(s)), false) }
        case .door: return open ? [(V3(-0.56, 0, 0.06), V3(-0.44, 2, 1.06), false)] : [(V3(-0.5, 0, -0.06), V3(0.5, 2, 0.06), false)]
        case .window:
            return [(V3(-1, 0, -0.1), V3(1, 0.5, 0.1), false), (V3(-1, 1.5, -0.1), V3(1, 2, 0.1), false),
                    (V3(-1, 0.5, -0.1), V3(-0.5, 1.5, 0.1), false), (V3(0.5, 0.5, -0.1), V3(1, 1.5, 0.1), false),
                    (V3(-0.5, 0.5, -0.02), V3(0.5, 1.5, 0.02), true)]
        }
    }
    // A roof's pitch: its +z rises 1 in 2.
    @inline(__always) static func pitched(_ k: Kind, _ q: V3) -> V3 {
        guard k == .roof else { return q }
        let c = cosf(roofPitch), s = sinf(roofPitch)
        return V3(q.x, q.y * c + q.z * s, -q.y * s + q.z * c)
    }
    static func height(_ k: Kind) -> Float { k == .floor ? 0.2 : (k == .roof ? 1 : 2) }
    static func halfWidth(_ k: Kind) -> Float { k == .door || k == .stairs ? 0.5 : (k == .post ? 0.13 : 1) }

    // World collision boxes: each part cut into slices no wider than about a third of a block, each slice's box taken
    // in world space, so a piece at an angle is met close to its real shape.
    static func collision(_ pc: FreePiece) -> [(V3, V3)] {
        var out: [(V3, V3)] = []
        let k = pc.kind
        let square = abs(sinf(2 * pc.yaw)) < 0.02 && k != .roof
        for part in parts(k, open: pc.open ?? false) {
            let ext = part.mx - part.mn
            let nx = square ? 1 : max(1, Int((ext.x / 0.35).rounded(.up))), nz = square ? 1 : max(1, Int((ext.z / 0.35).rounded(.up)))
            for ix in 0..<nx { for iz in 0..<nz {
                let a = part.mn + V3(ext.x * Float(ix) / Float(nx), 0, ext.z * Float(iz) / Float(nz))
                let b = V3(part.mn.x + ext.x * Float(ix + 1) / Float(nx), part.mx.y, part.mn.z + ext.z * Float(iz + 1) / Float(nz))
                var lo = V3(repeating: .infinity), hi = V3(repeating: -.infinity)
                for c in 0..<8 {
                    let q = V3(c & 1 == 0 ? a.x : b.x, c & 2 == 0 ? a.y : b.y, c & 4 == 0 ? a.z : b.z)
                    let w = pc.world(pitched(k, q))
                    lo = simd_min(lo, w); hi = simd_max(hi, w)
                }
                out.append((lo, hi))
            } }
        }
        return out
    }

    // The nearest piece part along a ray: (piece index, distance, normal in the piece's frame).
    static func ray(_ pieces: [FreePiece], _ o: V3, _ d: V3, maxDist: Float) -> (Int, Float, V3)? {
        var best: (Int, Float, V3)?
        for (i, pc) in pieces.enumerated() {
            let c = pc.origin
            if simd_length(c - o) > maxDist + 3 { continue }
            let k = pc.kind
            var lo = pc.local(o), ld = V3(simd_dot(d, pc.ax), d.y, simd_dot(d, pc.az))
            if k == .roof {
                // Into the unpitched frame: the inverse of `pitched`.
                let cs = cosf(roofPitch), s = sinf(roofPitch)
                func un(_ q: V3) -> V3 { V3(q.x, q.y * cs - q.z * s, q.y * s + q.z * cs) }
                lo = un(lo); ld = un(ld)
            }
            for part in parts(k, open: pc.open ?? false) {
                var t0: Float = 0, t1 = maxDist, n = V3(0, 0, 0)
                var hit = true
                for a in 0..<3 {
                    if abs(ld[a]) < 1e-6 { if lo[a] < part.mn[a] || lo[a] > part.mx[a] { hit = false; break }; continue }
                    var ta = (part.mn[a] - lo[a]) / ld[a], tb = (part.mx[a] - lo[a]) / ld[a]
                    var na = V3(0, 0, 0); na[a] = -1
                    if ta > tb { swap(&ta, &tb); na[a] = 1 }
                    if ta > t0 { t0 = ta; n = na }
                    t1 = min(t1, tb)
                    if t0 > t1 { hit = false; break }
                }
                if hit && t0 > 0 && (best == nil || t0 < best!.1) { best = (i, t0, n) }
            }
        }
        return best
    }

    // MARK: Drawing (Mesher.buildSection's detail stream)

    // The pieces whose origin lies in this section, as boxes, each face textured with the material's face texture at
    // one repeat per block.
    static func emit(_ ctx: DetailContext, _ pieces: [FreePiece]) {
        let base = V3(Float(ctx.wx0), Float(ctx.wy0), Float(ctx.wz0))
        for pc in pieces {
            let o = pc.origin
            guard o.y >= base.y && o.y < base.y + 16 && o.x >= base.x && o.x < base.x + 16 && o.z >= base.z && o.z < base.z + 16 else { continue }
            let k = pc.kind
            var mat = pc.mat
            var glass = AIR
            if k == .window && Blocks.key(mat).hasSuffix("pane") { glass = mat; mat = PLANKS }
            for part in parts(k, open: pc.open ?? false) {
                let b = part.glass ? glass : mat
                if part.glass && glass == AIR { continue }
                let cut = Blocks.layer[Int(b)] != Blocks.layer[Int(STONE)]
                box(ctx, pc, k, part.mn, part.mx, b, base: base, cut: cut)
            }
        }
    }

    // Faces: outward normal and the two axes across it (u x v = n), corners -u-v, +u-v, +u+v, -u+v: counter-clockwise
    // seen from outside, as the detail stream's other shapes are.
    private static let faces: [(n: V3, u: V3, v: V3, f: Int)] = [
        (V3(1, 0, 0), V3(0, 0, -1), V3(0, 1, 0), 0), (V3(-1, 0, 0), V3(0, 0, 1), V3(0, 1, 0), 1),
        (V3(0, 1, 0), V3(1, 0, 0), V3(0, 0, -1), 2), (V3(0, -1, 0), V3(1, 0, 0), V3(0, 0, 1), 3),
        (V3(0, 0, 1), V3(1, 0, 0), V3(0, 1, 0), 4), (V3(0, 0, -1), V3(-1, 0, 0), V3(0, 1, 0), 5),
    ]
    private static func box(_ ctx: DetailContext, _ pc: FreePiece, _ k: Kind, _ mn: V3, _ mx: V3, _ b: BlockID, base: V3, cut: Bool) {
        let c = (mn + mx) * 0.5, h = (mx - mn) * 0.5
        let tint = Int(Blocks.tint[Int(b)]) == 3 ? 0 : Int(Blocks.tint[Int(b)])
        for fc in faces {
            let layer = Int(Blocks.tex[Int(b) * 6 + fc.f])
            let fcn = c + fc.n * simd_dot(abs(fc.n), h)
            let hu = simd_dot(abs(fc.u), h), hv = simd_dot(abs(fc.v), h)
            let wn = pc.world(pitched(k, fc.n)) - pc.world(V3(0, 0, 0))
            for (su, sv) in [(-1, -1), (1, -1), (1, 1), (-1, 1)] as [(Float, Float)] {
                let q = fcn + fc.u * (su * hu) + fc.v * (sv * hv)
                let w = pc.world(pitched(k, q)) - base
                // One texture repeat per block, measured across the face from its own corner.
                let uv = SIMD2<Float>((su + 1) * hu, (1 - sv) * hv)
                ctx.vertex(w, wn, uv, layer: layer, tint: tint, cut: cut)
            }
        }
    }
}

extension World {
    // Rebuilds the cell index of the pieces' collision boxes.
    func reindexPieces() {
        pieceCells.removeAll(keepingCapacity: true)
        for pc in pieces {
            for (a, b) in FreeBuild.collision(pc) {
                for y in Int(floor(a.y))...Int(floor(b.y - 1e-4)) { for z in Int(floor(a.z))...Int(floor(b.z - 1e-4)) {
                    for x in Int(floor(a.x))...Int(floor(b.x - 1e-4)) { pieceCells[IVec3(x, y, z), default: []].append((a, b)) }
                } }
            }
        }
    }

    // The pieces a chunk's sections draw (those standing in it).
    func pieceList(_ c: Chunk) -> [FreePiece] {
        if pieces.isEmpty { return [] }
        return pieces.filter { floorDiv(Int(floor($0.p[0])), CS) == c.cx && floorDiv(Int(floor($0.p[2])), CS) == c.cz }
    }

    // A piece added, changed or taken away: collision again, and its section redrawn now.
    func piecesChanged(at p: V3) {
        reindexPieces()
        piecesDirty = true
        let x = Int(floor(p.x)), y = Int(floor(p.y)), z = Int(floor(p.z))
        guard let c = chunkAt(x, z), y >= 0 && y < CH else { return }
        let sy = y >> 4
        c.sections[sy].version += 1
        editBatch { remeshSync(c, sy) }                // (P446: on the edit lane on the headset)
    }

    func loadPieces() {
        guard let s = save, let d = try? Data(contentsOf: s.dir.appendingPathComponent("pieces.json")),
              let list = try? JSONDecoder().decode([FreePiece].self, from: d) else { return }
        pieces = list.filter { $0.p.count == 3 }
        reindexPieces()
    }

    func savePieces() {
        guard piecesDirty, let s = save else { return }
        piecesDirty = false
        SaveIO.storeJSON(pieces, to: s.dir.appendingPathComponent("pieces.json"))
    }
}

extension Game {
    // What the held block sets down as a piece in this world (nil: it places as a block).
    func freePieceKind(_ b: BlockID) -> FreeBuild.Kind? {
        guard world.fieldTerrain else { return nil }
        let key = Blocks.key(Blocks.groupBase[Int(b)]), shape = Blocks.shape[Int(b)]
        if shape == "door" { return .door }
        if shape == "slab" { return .floor }
        if shape == "stairs" { return .stairs }
        if key.hasSuffix("_fence") || key.hasSuffix("_wall") && !key.hasSuffix("_sign") { return .post }
        if key.hasSuffix("pane") { return .window }
        if ShapeClass.kind[Int(b)] == .built && Blocks.render[Int(b)] == RenderType.cube.rawValue { return .wall }
        return nil
    }

    private func pieceHit() -> (Int, Float, V3)? {
        guard !world.pieces.isEmpty, let h = FreeBuild.ray(world.pieces, player.eye, player.look, maxDist: 6) else { return nil }
        if let t = target {
            let c = V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) + 0.5
            if simd_length(c - player.eye) - 0.5 < h.1 { return nil }
        }
        return h
    }

    // Break: the piece aimed at (nearer than the block aimed at) comes down and gives its block back.
    func breakFreePiece() -> Bool {
        guard let (i, _, _) = pieceHit() else { return false }
        let pc = world.pieces.remove(at: i)
        let at = pc.world(V3(0, FreeBuild.height(pc.kind) * 0.5, 0))
        if survival, let it = Items.item(forBlock: pc.mat) { drops.spawn(ItemStack(it, 1), at: at) }
        sfx(.place(soundMat(pc.mat)), 0.8, at: at)
        world.piecesChanged(at: pc.origin)
        Structure.pieces(self, near: pc.origin)                 // P388: what that piece held up
        return true
    }

    // Use: a door piece aimed at opens or shuts; a building block in hand sets a piece down.
    func useFreePiece(sneak: Bool) -> Bool {
        let hit = pieceHit()
        if let (i, _, _) = hit, world.pieces[i].kind == .door {
            world.pieces[i].open = !(world.pieces[i].open ?? false)
            sfx(.place(.wood), 0.6, at: world.pieces[i].origin + V3(0, 1, 0))
            world.piecesChanged(at: world.pieces[i].origin)
            return true
        }
        guard !sneak, let b = held.def.block, var k = freePieceKind(b) else { return false }
        let look = player.look
        var yaw = atan2f(look.x, look.z)
        let step: Float = .pi / 24                                   // headings to 7.5 degrees
        yaw = (yaw / step).rounded() * step
        var o: V3?
        var rest = false                                              // set down on what is under it
        if let (i, t, n) = hit {
            let P = world.pieces[i], pk = P.kind
            let lp = P.local(player.eye + look * t)
            let toward: Float = simd_dot(player.eye - P.origin, P.az) >= 0 ? 1 : -1
            let wallLike = pk == .wall || pk == .window || pk == .door
            if k == .stairs && wallLike && n.y > 0.5 {
                k = .roof
                yaw = toward > 0 ? P.yaw + .pi : P.yaw
                o = P.origin + V3(0, FreeBuild.height(pk), 0) - V3(sinf(yaw), 0, cosf(yaw)) * 0.1
            } else if k == .floor && wallLike && n.y > 0.5 {
                yaw = P.yaw
                o = P.origin + V3(0, FreeBuild.height(pk), 0) + P.az * toward
            } else if k == .floor && pk == .floor && abs(n.y) < 0.5 {
                yaw = P.yaw
                o = P.origin + (abs(n.x) > 0.5 ? P.ax * (2 * n.x) : P.az * (2 * n.z))
            } else if k == .wall || k == .window || k == .door {
                let w = FreeBuild.halfWidth(k)
                if wallLike && n.y > 0.5 {
                    yaw = P.yaw; o = P.origin + V3(0, FreeBuild.height(pk), 0)
                } else if wallLike && abs(n.x) > 0.5 {
                    yaw = P.yaw; o = P.origin + P.ax * (n.x * (FreeBuild.halfWidth(pk) + w))
                } else if wallLike && abs(n.z) > 0.5 {
                    yaw = P.yaw + .pi / 2
                    let along = (lp.x * 2).rounded() / 2
                    o = P.origin + P.ax * along + P.az * (n.z * (0.1 + w))
                } else if pk == .floor && n.y > 0.5 {
                    let top = P.origin + V3(0, 0.2, 0)
                    if abs(lp.x) > abs(lp.z) { yaw = P.yaw + .pi / 2; o = top + P.ax * ((lp.x > 0 ? 1 : -1) * 0.9) }
                    else { yaw = P.yaw; o = top + P.az * ((lp.z > 0 ? 1 : -1) * 0.9) }
                }
            } else if k == .post && wallLike {
                yaw = P.yaw; o = P.origin + P.ax * ((lp.x > 0 ? 1 : -1) * FreeBuild.halfWidth(pk))
            }
            if o == nil { o = player.eye + look * (t - 0.05); rest = true }
        } else if let tg = target {
            // The point the ray meets the aimed cell, then the surface under it.
            let cell = V3(Float(tg.hit.x), Float(tg.hit.y), Float(tg.hit.z))
            var tEnter: Float = 0
            for a in 0..<3 where abs(look[a]) > 1e-6 {
                let ta = (cell[a] - player.eye[a]) / look[a], tb = (cell[a] + 1 - player.eye[a]) / look[a]
                tEnter = max(tEnter, min(ta, tb))
            }
            var p = player.eye + look * tEnter
            if tg.normal.y == 0 { p += V3(Float(tg.normal.x), 0, Float(tg.normal.z)) * (k == .floor ? 1 : 0.15) }
            o = p; rest = true
        }
        guard var at = o else { return false }
        let probe = FreePiece(k: k.rawValue, m: Blocks.key(b), p: [at.x, at.y, at.z], yaw: yaw)
        // Rest on the drawn ground: a floor on the highest of its corners and centre (level, like a foundation).
        if rest {
            var top = -Float.infinity
            let hw = FreeBuild.halfWidth(k)
            let pts: [V3] = k == .floor ? [V3(0, 0, 0), V3(-hw, 0, -hw), V3(hw, 0, -hw), V3(-hw, 0, hw), V3(hw, 0, hw)] : [V3(0, 0, 0)]
            for q in pts {
                let w = probe.world(q)
                if let y = world.restHeight(V3(w.x, at.y, w.z), halfW: 0.1, up: 1.5, depth: 3) { top = max(top, y) }
            }
            if top > -.infinity { at.y = top }
        }
        let pc = FreePiece(k: k.rawValue, m: Blocks.key(b), p: [at.x, at.y, at.z], yaw: yaw)
        // Not into the player.
        let pmn = player.pos - V3(player.halfW, 0, player.halfW), pmx = player.pos + V3(player.halfW, player.height, player.halfW)
        for (a, c) in FreeBuild.collision(pc) where a.x < pmx.x && c.x > pmn.x && a.y < pmx.y && c.y > pmn.y && a.z < pmx.z && c.z > pmn.z {
            placeRefused("You're standing there")
            return true
        }
        world.pieces.append(pc)
        world.piecesChanged(at: at)
        Structure.pieces(self, near: at)                        // P388: the new piece's weight
        sfx(.place(soundMat(b)), at: at)
        consumeHeld()
        return true
    }
}
