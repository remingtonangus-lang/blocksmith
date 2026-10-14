import Foundation
import simd

// Realistic world, layers 2-3 (docs/design/realistic-world.md 2.3, 3.2) in the game: what a blow knocks off a block flies
// as real pieces. Chips are cut from the block where the tool or round touched it (Fracture.bite), a broken block or a
// blasted one splits on the spot into Voronoi pieces (Fracture.shatter), and every piece is a rigid body (DebrisWorld)
// that tumbles, lands on the drawn ground (WorldGround), settles and fades. Pieces show the block's own texture on its
// outer faces, exactly the part they came from, and darker fresh material where they broke.
final class DebrisField {
    let bodies: DebrisWorld
    private let ws = Fracture.Workspace()
    private var scratch: [Fracture.Poly] = []
    // Per slot: the piece's quads round its centroid and its block (set when the slot gets a piece).
    private var meshes: [[Fracture.MeshVertex]]
    private var blockOf: [BlockID]
    private var ground: WorldGround?
    // Dead creatures falling as ragdolls (MobRagdoll.swift), on the same ground: one slot per corpse (MobAnim.maxCorpses).
    let ragdolls = RagdollWorld(capacity: MobAnim.maxCorpses)

    init() {
        var cfg = DebrisWorld.Config()
        cfg.maxNewPerFrame = 64                  // (a blast throws 16 blocks of 4 pieces at once)
        #if os(macOS)
        cfg.capacity = 240
        #endif
        bodies = DebrisWorld(config: cfg)
        meshes = Array(repeating: [], count: bodies.slotCount)
        blockOf = Array(repeating: AIR, count: bodies.slotCount)
    }

    var count: Int { bodies.count }

    // Rough density by what the block sounds like (only ratios matter: a stone chip shoves a wood one).
    private static func density(_ b: BlockID) -> Float {
        switch soundMat(b) {
        case .wood: return 0.6
        case .plant, .wool, .slime: return 0.35
        case .metal: return 2.5
        case .glass: return 0.9
        case .sand, .gravel, .dirt: return 0.8
        default: return 1.0
        }
    }

    // Chips a blow knocks off block b at `cell`: cut from the volume the tool touched (contact on the struck face,
    // `normal` out of it), thrown back out along the face and away from the swing.
    func chips(_ b: BlockID, cell: IVec3, at hit: V3, normal: V3, blow: V3, radius: Float, seed: UInt32) {
        let o = V3(Float(cell.x), Float(cell.y), Float(cell.z))
        scratch.removeAll(keepingCapacity: true)
        Fracture.bite(min: .zero, max: SIMD3<Float>(1, 1, 1), contact: hit - o, normal: normal, radius: radius, seed: seed,
                      workspace: ws, into: &scratch)
        var r = seed
        for p in scratch {
            r = r &* 1664525 &+ 1013904223
            let jitter = V3(Float(r & 0xFF) / 255 - 0.5, Float((r >> 8) & 0xFF) / 255, Float((r >> 16) & 0xFF) / 255 - 0.5)
            let v = normal * (1.6 + 1.2 * jitter.y) + jitter * 1.4 - blow * 0.4 + V3(0, 1.2, 0)
            add(p, b, origin: o, velocity: v, spin: jitter * 9)
        }
    }

    // A block that broke (mined through, blasted): what was left of it splits into `count` pieces round the impact,
    // pushed along `direction` (a blast: away from its centre) at about `speed`.
    func shatter(_ b: BlockID, cell: IVec3, impact: V3, direction: V3, count: Int, speed: Float, seed: UInt32, crowding: Float = 0.6) {
        let o = V3(Float(cell.x), Float(cell.y), Float(cell.z))
        scratch.removeAll(keepingCapacity: true)
        // (Non-full blocks shatter their collision box: slabs, stairs' lower half; models fall back to a small cube.)
        var lo = SIMD3<Float>(0, 0, 0), hi = SIMD3<Float>(1, 1, 1)
        if !Blocks.fullCollide[Int(b)] {
            if let bx = Blocks.collBoxes[Int(b)].first ?? Blocks.boxes[Int(b)].first {
                lo = SIMD3(Float(bx.x0), Float(bx.y0), Float(bx.z0)) / 16; hi = SIMD3(Float(bx.x1), Float(bx.y1), Float(bx.z1)) / 16
            } else { lo = SIMD3(0.3, 0, 0.3); hi = SIMD3(0.7, 0.4, 0.7) }
        }
        Fracture.shatter(min: lo, max: hi, impact: impact - o, direction: direction, count: count, seed: seed, crowding: crowding,
                         workspace: ws, into: &scratch)
        var r = seed ^ 0x5EED
        let dl = simd_length(direction)
        let dir = dl > 1e-4 ? direction / dl : V3(0, 1, 0)
        for p in scratch {
            r = r &* 1664525 &+ 1013904223
            let jitter = V3(Float(r & 0xFF) / 255 - 0.5, Float((r >> 8) & 0xFF) / 255 - 0.3, Float((r >> 16) & 0xFF) / 255 - 0.5)
            // Pieces nearer the impact leave faster; all of them spread out from the block's middle.
            let c = p.center
            let out = c - SIMD3<Float>(0.5, 0.5, 0.5)
            // (A block mined through slumps apart into a pile; a blasted one flies.)
            let v = dir * speed * (0.6 + 0.6 * jitter.y + 0.3) + out * (speed * 0.8 + 3.5) + jitter * (speed * 0.5 + 1.2) + V3(0, 1.2, 0)
            add(p, b, origin: o, velocity: v, spin: jitter * (4 + speed))
        }
    }

    // P247: a small box of block b's material (a bone a blade broke off) centred at `c`, split into `count` pieces
    // that fly along `direction`.
    func bits(_ b: BlockID, at c: V3, size: SIMD3<Float>, direction: V3, count: Int, speed: Float, seed: UInt32) {
        let o = c - size * 0.5
        scratch.removeAll(keepingCapacity: true)
        Fracture.shatter(min: .zero, max: size, impact: size * 0.5, direction: direction, count: count, seed: seed,
                         workspace: ws, into: &scratch)
        var r = seed ^ 0xB0E5
        for p in scratch {
            r = r &* 1664525 &+ 1013904223
            let jitter = V3(Float(r & 0xFF) / 255 - 0.5, Float((r >> 8) & 0xFF) / 255, Float((r >> 16) & 0xFF) / 255 - 0.5)
            add(p, b, origin: o, velocity: direction * speed + jitter * 2 + V3(0, 1.5, 0), spin: jitter * 12)
        }
    }

    private func add(_ p: Fracture.Poly, _ b: BlockID, origin o: V3, velocity: V3, spin: V3) {
        guard p.mass.volume > 0, p.verts.count >= 4 else { return }
        let c = p.mass.centroid
        var hull = [SIMD3<Float>]()
        hull.reserveCapacity(p.verts.count)
        for v in p.verts { hull.append(v - c) }
        // Planes round the centroid (Poly.planes are in the piece's local frame from its origin).
        var planes = [SIMD4<Float>]()
        planes.reserveCapacity(p.planes.count)
        for pl in p.planes { planes.append(SIMD4(pl.x, pl.y, pl.z, pl.w - simd_dot(SIMD3(pl.x, pl.y, pl.z), c))) }
        let pos = o + p.center
        guard let s = bodies.add(verts: hull, volume: p.mass.volume, inertia: p.mass.inertia, position: pos,
                                 velocity: velocity, angularVelocity: spin, density: DebrisField.density(b), tag: UInt32(b),
                                 planes: planes.count <= DebrisWorld.maxPlanes ? planes : nil) else { return }
        var quads: [Fracture.MeshVertex] = []
        quads.reserveCapacity(Fracture.quadCount(p) * 4)
        Fracture.emitQuads(p, into: &quads)
        // emitQuads places textures from the piece's origin fraction; the piece came from block-local space here,
        // so its UVs are the block's own (the part of the face it was).
        meshes[s] = quads
        blockOf[s] = b
    }

    // A blast nearby: pieces already lying round fly again.
    func blast(at c: V3, radius: Float, speed: Float) { bodies.blast(centre: c, radius: radius, speed: speed) }

    // A block changed (removed or placed): sleeping pieces round it fall or get pushed out.
    func blockChanged(_ p: IVec3) {
        ground?.forget()
        let c = V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5
        if bodies.count > 0 { bodies.wake(centre: c, radius: 1.2) }
        ragdolls.wake(near: c, radius: 2.5)
    }

    func clear() { bodies.clear(); ragdolls.removeAll() }

    func tick(_ dt: Float, world: World) {
        let limp = ragdolls.awakeCount > 0
        guard bodies.count > 0 || limp else { return }
        if ground == nil || ground!.world !== world { ground = WorldGround(world) }
        let g = ground!
        g.newFrame()
        if bodies.count > 0 { bodies.step(dt: dt, ground: g) }
        if limp { ragdolls.step(dt: dt, ground: g) }
    }

    // The pieces as lit, textured quads in the entity pass (positions relative to the eye). A fading piece shrinks away.
    func write(_ wr: inout EntityWriter, eye: V3, world: World, daylight: Float) {
        guard bodies.count > 0 else { return }
        let sunShade: (SIMD3<Float>) -> Float = { n in
            let n2 = n * n
            return 0.8 * n2.x + 0.68 * n2.z + (n.y > 0 ? 1.0 : 0.55) * n2.y
        }
        bodies.forEachLive { s, pos, rot, fade, tag in
            let quads = meshes[s]
            guard !quads.isEmpty else { return }
            let c = pos - eye
            if simd_length_squared(c) > 64 * 64 { return }
            let b = blockOf[s]
            let l = world.lightAt(Int(floor(pos.x)), Int(floor(pos.y + 0.1)), Int(floor(pos.z)))
            let near: Float = 1 - 0.55 * Terrain.smooth(5, 30, simd_length(c))
            let fill: Float = max(0.08, MobLight.fill * near)
            let light = max(fill, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
            let t = Blocks.tint[Int(b)]
            let tint = t == 1 || t == 3 ? V3(0.57, 0.74, 0.35) : (t == 2 ? V3(0.47, 0.67, 0.18) : V3(1, 1, 1))
            let scale = 1 - fade * fade
            let q = rot
            var k = 0
            while k + 3 < quads.count {
                let tag = quads[k].tag
                let n = q.act(quads[k].normal)
                // The inside of a break shows the block's bottom texture (dirt under turf, a log's grain), darker.
                let face = tag < 6 ? Int(tag) : 3
                let layer = Int(Blocks.tex[Int(b) * 6 + face])
                // Turf sides draw like a dropped block's: the side texture with its grass fringe overlaid (tinted there).
                let overlay = t == 3 && tag < 6 && tag != 2 && tag != 3
                let tn = (t == 3 && tag != 2) ? V3(1, 1, 1) : tint
                let shade = sunShade(n) * light * (tag == Fracture.inner ? 0.62 : 1)
                let col = V4(tn * shade, 1)
                let p0 = c + q.act(quads[k].position * scale), p1 = c + q.act(quads[k + 1].position * scale)
                let p2 = c + q.act(quads[k + 2].position * scale), p3 = c + q.act(quads[k + 3].position * scale)
                wr.quad4(p0, p1, p2, p3, quads[k].uv, quads[k + 1].uv, quads[k + 2].uv, quads[k + 3].uv, layer, col, overlay: overlay)
                k += 4
            }
        }
    }
}

// What debris lands on (PhysicsGround): the drawn surface. In smooth worlds natural ground answers with the field's own
// crossing between the column tops round the point (the surface the mesher draws, the same height the view and mobs
// follow: World.smoothGroundOffset); everything else with its collision boxes, pushed out through an open side.
final class WorldGround: PhysicsGround, DebrisFreeSpace {
    let world: World
    private let smooth: Bool
    private let gen: WorldGen?
    private var lastKey = ChunkKey(x: Int.min, z: Int.min)
    private var lastChunk: Chunk?
    // Column tops: direct-mapped cache (x, z, from y) -> drawn top (the field's crossing costs a few generator noise
    // reads); kept until a block changes (blockChanged), since the fields never do.
    private var topKey = [Int](repeating: Int.min, count: 4096)
    private var topVal = [Float](repeating: 0, count: 4096)
    private var boxes: [(V3, V3)] = []

    init(_ w: World) {
        world = w
        smooth = SmoothTerrain.enabled && SmoothTerrain.fromField
        gen = w.gen as? WorldGen
    }

    func forget() { for i in 0..<topKey.count { topKey[i] = Int.min } }
    func newFrame() { lastKey = ChunkKey(x: Int.min, z: Int.min); lastChunk = nil }      // (chunks load and unload)

    @inline(__always) private func block(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
        if y < 0 { return BEDROCK }
        if y >= CH { return AIR }
        let k = ChunkKey(x: floorDiv(x, CS), z: floorDiv(z, CS))
        if k != lastKey { lastKey = k; lastChunk = world.chunks[k] }
        guard let c = lastChunk else { return BEDROCK }          // (unloaded: solid, pieces wait there)
        return c.blocks[Chunk.index(mod(x, CS), y, mod(z, CS))]
    }

    // The drawn top of column (x, z) at or near y: the block top, or the field's crossing over natural ground.
    private func top(_ x: Int, _ z: Int, _ y: Int) -> Float {
        let key = (x & 0xFFFFF) | ((z & 0xFFFFF) << 20) | ((y & 0x3FF) << 40)
        let slot = Int(UInt(bitPattern: key &* -0x61C8864680B583EB) >> 52)     // (top 12 bits of a Fibonacci hash: 4096 slots)
        if topKey[slot] == key { return topVal[slot] }
        var t = Float(y + 1)
        for yy in (y - 1)...(y + 1) where Blocks.opaque[Int(block(x, yy, z))] && !Blocks.opaque[Int(block(x, yy + 1, z))] {
            t = Float(yy + 1)
            if let g = gen, SmoothTerrain.natural[Int(block(x, yy, z))] {
                let a = g.terrainDensity(x, yy, z), b = g.terrainDensity(x, yy + 1, z)
                if a > 0 && b <= 0 { t = Float(yy) + 0.5 + a / (a - b) }
            }
        }
        topKey[slot] = key; topVal[slot] = t
        return t
    }

    func contact(_ p: SIMD3<Float>) -> (depth: Float, normal: SIMD3<Float>)? {
        let x = Int(floor(p.x)), y = Int(floor(p.y)), z = Int(floor(p.z))
        let b = block(x, y, z)
        let nat = SmoothTerrain.natural
        // Smooth natural ground seen from above: the drawn surface between the 4 column tops round the point.
        if smooth && gen != nil {
            let under = !Blocks.collide[Int(b)] && nat[Int(block(x, y - 1, z))]
            if nat[Int(b)] || under {
                let fy = under ? y - 1 : y
                if !Blocks.opaque[Int(block(x, fy + 1, z))] || under {
                    let bx = floor(p.x - 0.5), bz = floor(p.z - 0.5)
                    let tx = p.x - 0.5 - bx, tz = p.z - 0.5 - bz
                    let ix = Int(bx), iz = Int(bz)
                    let h00 = top(ix, iz, fy), h10 = top(ix + 1, iz, fy), h01 = top(ix, iz + 1, fy), h11 = top(ix + 1, iz + 1, fy)
                    let h = (h00 * (1 - tx) + h10 * tx) * (1 - tz) + (h01 * (1 - tx) + h11 * tx) * tz
                    if p.y >= h { return nil }
                    if h - p.y < 1.1 {
                        let dx = (h10 - h00) * (1 - tz) + (h11 - h01) * tz, dz = (h01 - h00) * (1 - tx) + (h11 - h10) * tx
                        let n = simd_normalize(SIMD3<Float>(-dx, 1, -dz))
                        return ((h - p.y) * n.y, n)
                    }
                }
            }
        }
        guard Blocks.collide[Int(b)] else { return nil }
        let o = SIMD3<Float>(Float(x), Float(y), Float(z))
        if Blocks.fullCollide[Int(b)] {
            return push(p, lo: o, hi: o + 1, x, y, z)
        }
        boxes.removeAll(keepingCapacity: true)
        world.collisionBoxes(x, y, z, &boxes)
        var best: (depth: Float, normal: SIMD3<Float>)?
        for (lo, hi) in boxes where p.x > lo.x && p.y > lo.y && p.z > lo.z && p.x < hi.x && p.y < hi.y && p.z < hi.z {
            if let c = push(p, lo: lo, hi: hi, x, y, z), c.depth < (best?.depth ?? .greatestFiniteMagnitude) { best = c }
        }
        return best
    }

    // Out of a box by the shortest way through a side that isn't buried in the next full block.
    private func push(_ p: SIMD3<Float>, lo: SIMD3<Float>, hi: SIMD3<Float>, _ x: Int, _ y: Int, _ z: Int) -> (depth: Float, normal: SIMD3<Float>)? {
        let d: [Float] = [hi.x - p.x, p.x - lo.x, hi.y - p.y, p.y - lo.y, hi.z - p.z, p.z - lo.z]
        let n: [SIMD3<Float>] = [SIMD3(1, 0, 0), SIMD3(-1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(0, 0, -1)]
        var best = -1
        for f in 0..<6 {
            // A side flush with the cell's face into a full block is no way out.
            let flush = (f == 0 && hi.x >= Float(x + 1)) || (f == 1 && lo.x <= Float(x)) || (f == 2 && hi.y >= Float(y + 1))
                || (f == 3 && lo.y <= Float(y)) || (f == 4 && hi.z >= Float(z + 1)) || (f == 5 && lo.z <= Float(z))
            if flush {
                let nb = block(x + Int(n[f].x), y + Int(n[f].y), z + Int(n[f].z))
                if Blocks.fullCollide[Int(nb)] { continue }
            }
            if best < 0 || d[f] < d[best] { best = f }
        }
        if best < 0 { return (hi.y - p.y, SIMD3(0, 1, 0)) }       // buried: up
        return (max(0, d[best]), n[best])
    }

    func isFree(_ c: SIMD3<Float>, radius r: Float) -> Bool {
        // (A margin under the ball: smooth ground can rise up to 0.6 into the air cell over it.)
        let x0 = Int(floor(c.x - r)), x1 = Int(floor(c.x + r))
        let y0 = Int(floor(c.y - r - (smooth ? 0.7 : 0))), y1 = Int(floor(c.y + r))
        let z0 = Int(floor(c.z - r)), z1 = Int(floor(c.z + r))
        if (x1 - x0 + 1) * (y1 - y0 + 1) * (z1 - z0 + 1) > 27 { return false }
        for yy in y0...y1 { for zz in z0...z1 { for xx in x0...x1 where Blocks.collide[Int(block(xx, yy, zz))] { return false } } }
        return true
    }
}
