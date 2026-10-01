import Foundation
import Metal
import simd

// Ship meshes and drawing. A ship's grid is meshed with the chunk mesher (every block shape, smooth
// light, AO and greedy faces for free): the grid is cut into virtual 16-wide chunks lifted 16 cells
// so the section below the hull is open air, and each 16^3 section becomes a mesh drawn with the
// ship's transform. Meshing runs on a background queue; results are applied on the main thread.

final class ShipMesh {
    struct Sec {
        var origin: V3              // ship-space position of the section's corner
        var opaque: MeshSlice?
        var opaqueQuads = 0
        var solidQuads = 0
        var trans: MeshSlice?
        var transQuads = 0
    }
    private(set) var sections: [Int: Sec] = [:]
    var wheelSecs: [[Sec]] = []      // per Ship.wheelParts entry (ShipRenderer builds them)
    var wheelGen = -1
    private var layoutGen = 0
    private let lock = NSLock()
    private var results: [(gen: Int, full: Bool, secs: [(Int, SectionMesh, V3)])] = []
    var building = 0                 // jobs in flight (harness waits for 0)

    @inline(__always) static func key(_ cx: Int, _ sy: Int, _ cz: Int) -> Int { (cx & 0xFFF) | ((sy & 0xFF) << 12) | ((cz & 0xFFF) << 20) }

    private(set) var released = false

    // Remeshes everything (after assembly, loading, or a grid resize).
    func rebuildAll(_ s: Ship, device: MTLDevice, queue: DispatchQueue) {
        layoutGen += 1
        released = false
        submit(s, only: nil, full: true, queue: queue)
    }

    // Gives the GPU meshes back (ship far away); rebuildAll brings them back.
    func release() {
        layoutGen += 1                   // results still in flight are dropped
        sections.removeAll()
        wheelSecs = []
        wheelGen = -1
        released = true
    }

    // Remeshes the sections within one section of a changed cell.
    func rebuildAround(_ s: Ship, _ c: IVec3, device: MTLDevice, queue: DispatchQueue) {
        rebuildAround(s, [c], device: device, queue: queue)
    }

    // The same for many changed cells (a blast) in one job; the whole grid when they touch most of it anyway.
    func rebuildAround(_ s: Ship, _ cells: [IVec3], device: MTLDevice, queue: DispatchQueue) {
        if released { return }
        var only = Set<Int>()
        var seen = Set<Int>()
        for c in cells {
            let cx = c.x >> 4, sy = (c.y + 16) >> 4, cz = c.z >> 4
            if !seen.insert(ShipMesh.key(cx, sy, cz)).inserted { continue }
            for dz in -1...1 { for dy in -1...1 { for dx in -1...1 where cx + dx >= 0 && cz + dz >= 0 && sy + dy >= 1 {
                only.insert(ShipMesh.key(cx + dx, sy + dy, cz + dz))
            } } }
        }
        if only.isEmpty { return }
        let total = ((s.grid.sx + 15) / 16) * ((s.grid.sz + 15) / 16) * max(1, (s.grid.sy + 31) / 16)
        submit(s, only: only.count * 3 >= total * 2 ? nil : only, full: false, queue: queue)
    }

    private func submit(_ s: Ship, only: Set<Int>?, full: Bool, queue: DispatchQueue) {
        let gen = layoutGen
        let sx = s.grid.sx, sy = s.grid.sy, sz = s.grid.sz
        let blocks = s.grid.blocks
        lock.lock(); building += 1; lock.unlock()
        queue.async { [weak self] in
            let secs = ShipMesh.build(sx: sx, sy: sy, sz: sz, blocks: blocks, only: only)
            guard let self else { return }
            self.lock.lock()
            self.results.append((gen, full, secs))
            self.building -= 1
            self.lock.unlock()
        }
    }

    var busy: Bool { lock.lock(); defer { lock.unlock() }; return building > 0 || !results.isEmpty }

    // Uploads finished meshes (main thread).
    func apply(device: MTLDevice) {
        lock.lock()
        let rs = results
        results.removeAll()
        lock.unlock()
        for r in rs where r.gen == layoutGen {
            if r.full { sections.removeAll() }
            for (k, m, origin) in r.secs {
                if m.opaque.isEmpty && m.trans.isEmpty { sections.removeValue(forKey: k); continue }
                var s = Sec(origin: origin)
                s.opaque = m.opaque.withUnsafeBytes { MeshArena.shared.alloc(device, $0) }
                s.opaqueQuads = m.opaque.count / 8
                s.solidQuads = m.solidQuads
                s.trans = m.trans.withUnsafeBytes { MeshArena.shared.alloc(device, $0) }
                s.transQuads = m.trans.count / 8
                sections[k] = s
            }
        }
    }

    // Builds section meshes for a grid snapshot (any thread).
    static func build(sx: Int, sy: Int, sz: Int, blocks: [BlockID], only: Set<Int>?, spinning: Bool = true) -> [(Int, SectionMesh, V3)] {
        let ncx = (sx + 15) / 16, ncz = (sz + 15) / 16
        let vh = sy + 16
        let nsec = min(NSEC - 1, (vh + 15) / 16)
        let skyT = Blocks.sky
        // Propellers and wheels are drawn on their own, turning (ShipRenderer), so the hull mesh leaves them out.
        let kinds = ShipParts.kinds
        var stores: [Int: (BlockStore, [Int16])] = [:]
        let empty = (BlockStore([]), [Int16](repeating: -1, count: CSQ))
        func store(_ cx: Int, _ cz: Int) -> (BlockStore, [Int16]) {
            if cx < 0 || cz < 0 || cx >= ncx || cz >= ncz { return empty }
            let k = cx + cz * ncx
            if let s = stores[k] { return s }
            var a = [BlockID](repeating: AIR, count: CSQ * min(CH, nsec * 16 + 16))
            var h = [Int16](repeating: -1, count: CSQ)
            for y in 0..<sy {
                let vy = y + 16
                if vy * CSQ >= a.count { break }
                for z in 0..<16 {
                    let gz = cz * 16 + z
                    if gz >= sz { break }
                    for x in 0..<16 {
                        let gx = cx * 16 + x
                        if gx >= sx { break }
                        let b = blocks[gx + gz * sx + y * sx * sz]
                        if b == AIR || (spinning && (kinds[Int(b)] == .propeller || kinds[Int(b)] == .wheel)) { continue }
                        a[x + z * 16 + vy * CSQ] = b
                        if skyT[Int(b)] { h[x + z * 16] = Int16(vy) }
                    }
                }
            }
            let s = (BlockStore(a), h)
            stores[k] = s
            return s
        }
        var out: [(Int, SectionMesh, V3)] = []
        for cz in 0..<ncz {
            for cx in 0..<ncx {
                // Partial rebuilds: only the columns holding a wanted section (and their neighbours) are built.
                if let only, !(1..<max(2, nsec)).contains(where: { only.contains(key(cx, $0, cz)) }) { continue }
                var n9: [BlockStore] = [], h9: [[Int16]] = []
                for dz in -1...1 { for dx in -1...1 { let s = store(cx + dx, cz + dz); n9.append(s.0); h9.append(s.1) } }
                for s in 1..<max(2, nsec) {
                    let k = key(cx, s, cz)
                    if let only, !only.contains(k) { continue }
                    let m = Mesher.buildSection(n9, h9, sy: s, lod: 0)
                    out.append((k, m, V3(Float(cx * 16), Float(s * 16 - 16), Float(cz * 16))))
                }
            }
        }
        return out
    }
}

// Per-draw record for shipVS (buffer 2).
struct ShipDrawRec {
    var model: float4x4            // ship space -> camera-relative world
    var origin: V4                 // section origin in ship space
}

let shipShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Uniforms { float4x4 viewProj; float4 fogColor; float4 params; float4 sunDir; };
struct ShipDraw { float4x4 model; float4 origin; };
struct ShipOut {
    float4 pos [[position]];
    float2 uv;
    float layer [[flat]];
    float3 shade;
    float3 tint;
    float overlay [[flat]];
    float dist;
};
constexpr sampler texSampler(filter::nearest, mip_filter::linear, address::repeat);
constant float faceShade[8] = { 0.80, 0.80, 1.00, 0.55, 0.68, 0.68, 0.88, 1.00 };
constant float aoCurve[4] = { 0.42, 0.62, 0.81, 1.0 };

// Same vertex format and light curve as chunkVS (Shaders.swift), placed with the ship's transform.
vertex ShipOut shipVS(uint vid [[vertex_id]],
                      const device uint2* verts [[buffer(0)]],
                      constant Uniforms& u [[buffer(1)]],
                      constant ShipDraw& d [[buffer(2)]],
                      const device uint* tints [[buffer(3)]]) {
    uint2 v = verts[vid];
    uint w0 = v.x, w1 = v.y;
    uint xi = w0 & 511u, zi = (w0 >> 18) & 511u;
    float3 p = float3(float(xi), float((w0 >> 9) & 511u), float(zi)) / 16.0;
    uint face = (w0 >> 27) & 7u;
    uint tintMode = w0 >> 30;
    uint uu = w1 & 31u, vv = (w1 >> 5) & 31u;
    float2 uv = float2(float(uu), float(vv)) / 16.0;
    if (uu == 31u && vv == 31u) {
        switch (face) {
            case 0u: uv = float2(-p.z, -p.y); break;
            case 1u: uv = float2(p.z, -p.y); break;
            case 2u: uv = float2(p.x, p.z); break;
            case 3u: uv = float2(p.x, -p.z); break;
            case 4u: uv = float2(p.x, -p.y); break;
            default: uv = float2(-p.x, -p.y); break;
        }
    }
    uint layer = ((w1 >> 10) & 1023u) | ((w1 >> 31) << 10);
    uint ao = (w1 >> 20) & 3u;
    float skyL = float((w1 >> 22) & 15u) / 15.0;
    float blkL = float((w1 >> 26) & 15u) / 15.0;
    float3 rel = (d.model * float4(p + d.origin.xyz, 1.0)).xyz;
    ShipOut o;
    o.pos = u.viewProj * float4(rel, 1.0);
    o.uv = uv;
    o.layer = float(layer);
    o.tint = float3(1.0);
    if (tintMode != 0u) { o.tint = unpack_unorm4x8_to_float(tints[(tintMode - 1u) * 256u]).rgb; }
    o.overlay = float((w1 >> 30) & 1u);
    float sky = skyL * (0.35 + 0.65 * skyL) * u.params.y;
    float blk0 = blkL / (4.0 - 3.0 * blkL);
    float inv = 1.0 - blk0;
    float blk = min(1.0, mix(blk0, 1.0 - inv * inv * inv * inv, 0.6) * 1.05);
    float3 lit = max(float3(sky), blk * float3(1.0, 0.76, 0.46));
    lit = mix(max(lit, float3(0.035)), float3(1.0), u.sunDir.w);
    o.shade = lit * (faceShade[face] * aoCurve[ao]);
    o.dist = length(rel);
    return o;
}

static float3 shipFog(float3 c, float dist, constant Uniforms& u) {
    return mix(c, u.fogColor.rgb, smoothstep(u.fogColor.w, u.params.x, dist));
}

fragment float4 shipSolidFS(ShipOut in [[stage_in]], texture2d_array<float> tex [[texture(0)]], constant Uniforms& u [[buffer(1)]]) {
    float4 c = tex.sample(texSampler, in.uv, uint(in.layer));
    float3 t = (in.overlay > 0.5 && c.a > 0.95) ? float3(1.0) : in.tint;
    return float4(shipFog(c.rgb * t * in.shade, in.dist, u), 1.0);
}

fragment float4 shipCutFS(ShipOut in [[stage_in]], texture2d_array<float> tex [[texture(0)]], constant Uniforms& u [[buffer(1)]]) {
    float4 c = tex.sample(texSampler, in.uv, uint(in.layer));
    if (c.a < 0.5) { discard_fragment(); }
    float3 t = (in.overlay > 0.5 && c.a > 0.95) ? float3(1.0) : in.tint;
    return float4(shipFog(c.rgb * t * in.shade, in.dist, u), 1.0);
}

fragment float4 shipTransFS(ShipOut in [[stage_in]], texture2d_array<float> tex [[texture(0)]], constant Uniforms& u [[buffer(1)]]) {
    float4 c = tex.sample(texSampler, in.uv, uint(in.layer));
    float3 rgb = c.rgb * in.tint * max(in.shade, float3(0.05));
    float f = smoothstep(u.fogColor.w, u.params.x, in.dist);
    return float4(mix(rgb, u.fogColor.rgb, f), mix(c.a, 1.0, f * 0.8));
}

struct LineVert { float4 pos; float4 color; };
struct LineOut { float4 pos [[position]]; float4 color; };
vertex LineOut shipLineVS(uint vid [[vertex_id]], const device LineVert* v [[buffer(0)]], constant Uniforms& u [[buffer(1)]]) {
    LineOut o;
    o.pos = u.viewProj * float4(v[vid].pos.xyz, 1.0);
    o.color = v[vid].color;
    return o;
}
fragment float4 shipLineFS(LineOut in [[stage_in]]) { return in.color; }
"""

final class ShipRenderer {
    let solidPipe: MTLRenderPipelineState
    let cutPipe: MTLRenderPipelineState
    let transPipe: MTLRenderPipelineState
    let linePipe: MTLRenderPipelineState
    let maskPipe: MTLRenderPipelineState      // depth only: keeps the sea out of hulls
    let depthWrite: MTLDepthStencilState
    let depthRead: MTLDepthStencilState
    let tintBuf: MTLBuffer
    private var ring: [MTLBuffer] = []
    private var ringIndex = 0
    private var ringOff = 0
    private static let ringSize = 1 << 20
    private(set) var drawCalls = 0
    var enabled = true               // bench: frames without ships for comparison
    private let device: MTLDevice
    private var propMeshes: [BlockID: ShipMesh.Sec] = [:]

    private func secs(_ built: [(Int, SectionMesh, V3)]) -> [ShipMesh.Sec] {
        var out: [ShipMesh.Sec] = []
        for (_, m, origin) in built where !m.opaque.isEmpty {
            var sec = ShipMesh.Sec(origin: origin)
            sec.opaque = m.opaque.withUnsafeBytes { MeshArena.shared.alloc(device, $0) }
            sec.opaqueQuads = m.opaque.count / 8
            sec.solidQuads = m.solidQuads
            out.append(sec)
        }
        return out
    }

    // Wheel parts meshed on their own (small grids; redone only when the parts change).
    private func wheelMeshes(_ s: Ship) -> [[ShipMesh.Sec]] {
        if s.mesh.wheelGen != s.wheelGen {
            s.mesh.wheelSecs = s.wheelParts.map { p in
                secs(ShipMesh.build(sx: p.size.x, sy: p.size.y, sz: p.size.z, blocks: p.blocks, only: nil, spinning: false))
            }
            s.mesh.wheelGen = s.wheelGen
        }
        return s.mesh.wheelSecs
    }

    // One propeller block meshed on its own (cached per facing state), drawn turned about its shaft.
    private func propMesh(_ b: BlockID) -> ShipMesh.Sec? {
        if let m = propMeshes[b] { return m }
        guard let sec = secs(ShipMesh.build(sx: 1, sy: 1, sz: 1, blocks: [b], only: nil, spinning: false)).first else { return nil }
        propMeshes[b] = sec
        return sec
    }
    private var maskScratch: [SimpleVert] = []

    init(device: MTLDevice, colorFormat: MTLPixelFormat) throws {
        self.device = device
        let lib = try device.makeLibrary(source: shipShaderSource, options: nil)
        func pipe(_ vs: String, _ fs: String, blend: Bool, colour: Bool = true) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: vs)
            d.fragmentFunction = lib.makeFunction(name: fs)
            d.colorAttachments[0].pixelFormat = colorFormat
            if !colour { d.colorAttachments[0].writeMask = [] }
            if blend {
                let a = d.colorAttachments[0]!
                a.isBlendingEnabled = true
                a.sourceRGBBlendFactor = .sourceAlpha
                a.destinationRGBBlendFactor = .oneMinusSourceAlpha
                a.sourceAlphaBlendFactor = .one
                a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            d.depthAttachmentPixelFormat = .depth32Float
            return try device.makeRenderPipelineState(descriptor: d)
        }
        solidPipe = try pipe("shipVS", "shipSolidFS", blend: false)
        cutPipe = try pipe("shipVS", "shipCutFS", blend: false)
        transPipe = try pipe("shipVS", "shipTransFS", blend: true)
        linePipe = try pipe("shipLineVS", "shipLineFS", blend: true)
        maskPipe = try pipe("shipLineVS", "shipLineFS", blend: false, colour: false)
        func ds(_ cmp: MTLCompareFunction, _ write: Bool) -> MTLDepthStencilState {
            let d = MTLDepthStencilDescriptor()
            d.depthCompareFunction = cmp
            d.isDepthWriteEnabled = write
            return device.makeDepthStencilState(descriptor: d)!
        }
        depthWrite = ds(.less, true)
        depthRead = ds(.lessEqual, false)
        // Plains grass, foliage and water colours (RGBA8, red in the low byte).
        func rgba(_ h: UInt32) -> UInt32 { ((h >> 16) & 255) | (((h >> 8) & 255) << 8) | ((h & 255) << 16) | (255 << 24) }
        var t = [UInt32](repeating: 0, count: 768)
        for i in 0..<256 { t[i] = rgba(0x91BD59); t[256 + i] = rgba(0x77AB2F); t[512 + i] = rgba(0x3F76E4) }
        tintBuf = device.makeBuffer(bytes: t, length: t.count * 4, options: .storageModeShared)!
        for _ in 0..<3 { ring.append(device.makeBuffer(length: ShipRenderer.ringSize, options: .storageModeShared)!) }
    }

    private func model(_ s: Ship, eye: V3) -> float4x4 {
        translationMatrix(s.pos - eye) * float4x4(s.rot) * translationMatrix(-s.com)
    }

    // Call once per frame before the other draws.
    func beginFrame() {
        ringIndex = (ringIndex + 1) % ring.count
        ringOff = 0
        drawCalls = 0
    }

    private func push(_ verts: [SimpleVert]) -> (MTLBuffer, Int)? {
        let n = verts.count * MemoryLayout<SimpleVert>.stride
        if n == 0 { return nil }
        let off = (ringOff + 255) & ~255
        guard off + n <= ShipRenderer.ringSize else { return nil }
        let b = ring[ringIndex]
        verts.withUnsafeBytes { memcpy(b.contents() + off, $0.baseAddress!, n) }
        ringOff = off + n
        return (b, off)
    }

    // Solid then cutout faces of every visible ship.
    func drawOpaque(_ enc: MTLRenderCommandEncoder, ships: ShipManager, eye: V3, u: inout Uniforms, frustum: Frustum, quads: MTLBuffer) {
        if !enabled || (ships.isEmpty && ships.ghosts.isEmpty) { return }
        enc.setDepthStencilState(depthWrite)
        enc.setCullMode(.back)
        enc.setFrontFacing(.counterClockwise)
        enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.setVertexBuffer(tintBuf, offset: 0, index: 3)
        func draw(_ s: Ship, _ pass: Int) {
            if s.mesh.released || !frustum.visible(min: s.worldMin, max: s.worldMax) { return }
            let m = model(s, eye: eye)
            for sec in s.mesh.sections.values {
                guard let buf = sec.opaque, sec.opaqueQuads > 0 else { continue }
                let total = min(sec.opaqueQuads, Renderer.maxQuads), solid = min(sec.solidQuads, total)
                let first = pass == 0 ? 0 : solid, count = pass == 0 ? solid : total - solid
                if count <= 0 { continue }
                var rec = ShipDrawRec(model: m, origin: V4(sec.origin, 0))
                enc.setVertexBuffer(buf.buffer, offset: buf.offset, index: 0)
                enc.setVertexBytes(&rec, length: MemoryLayout<ShipDrawRec>.stride, index: 2)
                enc.drawIndexedPrimitives(type: .triangle, indexCount: count * 6, indexType: .uint32, indexBuffer: quads,
                                          indexBufferOffset: first * 6 * 4)
                drawCalls += 1
            }
            // Wheels, rolled about their axles (across the heading).
            if !s.wheelParts.isEmpty {
                let meshes = wheelMeshes(s)
                let axle = simd_normalize(simd_cross(s.fwd, V3(0, 1, 0)) + V3(1e-6, 0, 0))
                for (i, p) in s.wheelParts.enumerated() where i < meshes.count {
                    let roll = float4x4(simd_quatf(angle: -s.rollDist / max(0.5, p.radius), axis: axle))
                    let lo = V3(Float(p.lo.x), Float(p.lo.y), Float(p.lo.z))
                    let wmodel: float4x4 = m * translationMatrix(p.center) * roll * translationMatrix(lo - p.center)
                    for sec in meshes[i] {
                        guard let buf = sec.opaque else { continue }
                        let total = min(sec.opaqueQuads, Renderer.maxQuads), solid = min(sec.solidQuads, total)
                        let first = pass == 0 ? 0 : solid, count = pass == 0 ? solid : total - solid
                        if count <= 0 { continue }
                        var rec = ShipDrawRec(model: wmodel, origin: V4(sec.origin, 0))
                        enc.setVertexBuffer(buf.buffer, offset: buf.offset, index: 0)
                        enc.setVertexBytes(&rec, length: MemoryLayout<ShipDrawRec>.stride, index: 2)
                        enc.drawIndexedPrimitives(type: .triangle, indexCount: count * 6, indexType: .uint32, indexBuffer: quads,
                                                  indexBufferOffset: first * 6 * 4)
                        drawCalls += 1
                    }
                }
            }
            // Propellers, turned about their shafts.
            for (c, d) in s.props {
                let b = s.grid.get(Int(floor(c.x)), Int(floor(c.y)), Int(floor(c.z)))
                guard let pm = propMesh(b), let buf = pm.opaque else { continue }
                let total = min(pm.opaqueQuads, Renderer.maxQuads), solid = min(pm.solidQuads, total)
                let first = pass == 0 ? 0 : solid, count = pass == 0 ? solid : total - solid
                if count <= 0 { continue }
                let spin = float4x4(simd_quatf(angle: s.propSpin, axis: d))
                let pmodel: float4x4 = m * translationMatrix(c) * spin * translationMatrix(V3(-0.5, -0.5, -0.5))
                var rec = ShipDrawRec(model: pmodel, origin: V4(pm.origin, 0))
                enc.setVertexBuffer(buf.buffer, offset: buf.offset, index: 0)
                enc.setVertexBytes(&rec, length: MemoryLayout<ShipDrawRec>.stride, index: 2)
                enc.drawIndexedPrimitives(type: .triangle, indexCount: count * 6, indexType: .uint32, indexBuffer: quads,
                                          indexBufferOffset: first * 6 * 4)
                drawCalls += 1
            }
        }
        for pass in 0..<2 {
            enc.setRenderPipelineState(pass == 0 ? solidPipe : cutPipe)
            for s in ships.list { draw(s, pass) }
            for g in ships.ghosts { draw(g.0, pass) }
        }
    }

    // Target outline, then the depth-only water mask over each hull's enclosed air (keeps the sea
    // surface out of boats), drawn before the world's water.
    func drawBeforeWater(_ enc: MTLRenderCommandEncoder, ships: ShipManager, world: World, eye: V3, u: inout Uniforms, frustum: Frustum) {
        if !enabled || ships.isEmpty { return }
        enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.setCullMode(.none)
        if let t = ships.target {
            let s = t.ship
            let b = s.grid.get(t.cell.x, t.cell.y, t.cell.z)
            var verts: [SimpleVert] = []
            let o = V3(Float(t.cell.x), Float(t.cell.y), Float(t.cell.z))
            let edges = [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
            let col = V4(0, 0, 0, 0.7)
            for (bmn, bmx) in world.selectionBoxes(b) {
                let a = o + bmn - V3(repeating: 0.003), c = o + bmx + V3(repeating: 0.003)
                let cs = [V3(a.x, a.y, a.z), V3(c.x, a.y, a.z), V3(c.x, a.y, c.z), V3(a.x, a.y, c.z),
                          V3(a.x, c.y, a.z), V3(c.x, c.y, a.z), V3(c.x, c.y, c.z), V3(a.x, c.y, c.z)]
                for i in edges { verts.append(SimpleVert(pos: V4(s.toWorld(cs[i]) - eye, 1), color: col)) }
            }
            if let pb = push(verts) {
                enc.setRenderPipelineState(linePipe)
                enc.setDepthStencilState(depthRead)
                enc.setVertexBuffer(pb.0, offset: pb.1, index: 0)
                enc.drawPrimitives(type: .line, vertexStart: 0, vertexCount: verts.count)
            }
        }
        maskScratch.removeAll(keepingCapacity: true)
        var rd = ShipBlockReader(world)
        for s in ships.list where !s.mesh.released && frustum.visible(min: s.worldMin, max: s.worldMax) {
            guard let top = rd.waterTop(s.pos) ?? rd.waterTop(s.pos - V3(0, 2, 0)) else { continue }
            let plane = top + (eye.y > top ? 0.01 : -0.01)
            let r = simd_float3x3(s.rot)
            let ry = V3(r[0][1], r[1][1], r[2][1])          // world y = pos.y + ry . (local - com)
            if abs(ry.y) < 0.3 { continue }
            let g = s.grid
            // Local y of the plane above ship-space column point (x, z).
            func ly(_ x: Float, _ z: Float) -> Float {
                s.com.y + (plane - s.pos.y - ry.x * (x - s.com.x) - ry.z * (z - s.com.z)) / ry.y
            }
            for z in 0..<g.sz {
                for x in 0..<g.sx {
                    let yc = ly(Float(x) + 0.5, Float(z) + 0.5)
                    let cy = Int(floor(yc))
                    if !s.dry(x, cy, z) { continue }
                    let fx = Float(x), fz = Float(z)
                    let w0 = V4(s.toWorld(V3(fx, ly(fx, fz), fz)) - eye, 1)
                    let w1 = V4(s.toWorld(V3(fx + 1, ly(fx + 1, fz), fz)) - eye, 1)
                    let w2 = V4(s.toWorld(V3(fx + 1, ly(fx + 1, fz + 1), fz + 1)) - eye, 1)
                    let w3 = V4(s.toWorld(V3(fx, ly(fx, fz + 1), fz + 1)) - eye, 1)
                    let none = V4(0, 0, 0, 0)
                    maskScratch.append(SimpleVert(pos: w0, color: none)); maskScratch.append(SimpleVert(pos: w1, color: none))
                    maskScratch.append(SimpleVert(pos: w2, color: none)); maskScratch.append(SimpleVert(pos: w0, color: none))
                    maskScratch.append(SimpleVert(pos: w2, color: none)); maskScratch.append(SimpleVert(pos: w3, color: none))
                }
            }
        }
        if let pb = push(maskScratch) {
            enc.setRenderPipelineState(maskPipe)
            enc.setDepthStencilState(depthWrite)
            enc.setVertexBuffer(pb.0, offset: pb.1, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: maskScratch.count)
            drawCalls += 1
        }
    }

    // Translucent faces (stained glass, water on deck), after the world's water.
    func drawTranslucent(_ enc: MTLRenderCommandEncoder, ships: ShipManager, eye: V3, u: inout Uniforms, frustum: Frustum, quads: MTLBuffer) {
        if !enabled || ships.isEmpty { return }
        var any = false
        for s in ships.list where frustum.visible(min: s.worldMin, max: s.worldMax) {
            let m = model(s, eye: eye)
            for sec in s.mesh.sections.values {
                guard let buf = sec.trans, sec.transQuads > 0 else { continue }
                if !any {
                    any = true
                    enc.setRenderPipelineState(transPipe)
                    enc.setDepthStencilState(depthRead)
                    enc.setCullMode(.none)
                    enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                    enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                    enc.setVertexBuffer(tintBuf, offset: 0, index: 3)
                }
                var rec = ShipDrawRec(model: m, origin: V4(sec.origin, 0))
                enc.setVertexBuffer(buf.buffer, offset: buf.offset, index: 0)
                enc.setVertexBytes(&rec, length: MemoryLayout<ShipDrawRec>.stride, index: 2)
                enc.drawIndexedPrimitives(type: .triangle, indexCount: min(sec.transQuads, Renderer.maxQuads) * 6, indexType: .uint32,
                                          indexBuffer: quads, indexBufferOffset: 0)
                drawCalls += 1
            }
        }
    }
}
