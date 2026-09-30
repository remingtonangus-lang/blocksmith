import Foundation
import Metal
import MetalKit
import QuartzCore
import ImageIO
import UniformTypeIdentifiers
import simd

struct Uniforms {
    var viewProj: float4x4
    var fogColor: V4
    var params: V4
    var sunDir: V4
}

struct SimpleVert { var pos: V4; var color: V4 }
struct HudVert { var pos: V2; var uv: V2; var color: V4; var extra: V4 }
struct StarParams { var rot: float4x4; var tint: V4 }

let CLOUD_Y: Float = 192 + Float(YOFF)

enum HudTex {
    static let heart = Int(Tex.id("heart")), heartHalf = Int(Tex.id("heart_half")), heartEmpty = Int(Tex.id("heart_empty"))
    static let food = Int(Tex.id("food")), foodHalf = Int(Tex.id("food_half")), foodEmpty = Int(Tex.id("food_empty"))
    static let bubble = Int(Tex.id("bubble"))
    static let armor = Int(Tex.id("armor")), armorHalf = Int(Tex.id("armor_half")), armorEmpty = Int(Tex.id("armor_empty"))
    static func destroy(_ i: Int) -> Int { Int(Tex.id("destroy_\(max(0, min(9, i)))")) }
}

final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let game: Game
    let chunkPipe: MTLRenderPipelineState
    let chunkSolidPipe: MTLRenderPipelineState   // same as chunkPipe without the alpha test (keeps hidden-surface removal)
    let waterPipe: MTLRenderPipelineState
    let simplePipe: MTLRenderPipelineState
    let hudPipe: MTLRenderPipelineState
    let starPipe: MTLRenderPipelineState
    let cloudPipe: MTLRenderPipelineState
    let mobPipe: MTLRenderPipelineState
    let entityPipe: MTLRenderPipelineState
    let crackPipe: MTLRenderPipelineState
    let starBuf: MTLBuffer
    let starVerts: Int
    let depthWrite: MTLDepthStencilState
    let depthRead: MTLDepthStencilState
    let depthNone: MTLDepthStencilState
    let texture: MTLTexture
    let quadIndices: MTLBuffer
    static let maxQuads = 1 << 17

    private let inflight = DispatchSemaphore(value: 3)
    private var ring: [MTLBuffer] = []   // per-frame scratch for sky/outline/HUD vertices
    private let ringSize = 1 << 21
    private var frame = 0
    private var lastTime = CACurrentMediaTime()
    var drawHUD = true

    // Stats
    private(set) var fps: Double = 0
    private var fpsFrames = 0
    private var fpsTime: Double = 0
    private(set) var drawnChunks = 0
    private var visibleScratch: [(Chunk, Int, Float)] = []
    private var visitGen: [UInt32] = []
    private var gen: UInt32 = 0
    private var bfs: [(Chunk, Int, Int, Int, Int, Int)] = []
    var caveCulling = true
    var onFrame: ((Double) -> Void)?

    init(device: MTLDevice, game: Game, colorFormat: MTLPixelFormat) throws {
        self.device = device
        self.game = game
        queue = device.makeCommandQueue()!
        let lib = try device.makeLibrary(source: shaderSource, options: nil)

        func pipe(_ vs: String, _ fs: String, blend: Bool, depth: Bool = true) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: vs)
            d.fragmentFunction = lib.makeFunction(name: fs)
            d.colorAttachments[0].pixelFormat = colorFormat
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
        chunkPipe = try pipe("chunkVS", "chunkFS", blend: false)
        chunkSolidPipe = try pipe("chunkVS", "chunkSolidFS", blend: false)
        waterPipe = try pipe("chunkVS", "waterFS", blend: true)
        simplePipe = try pipe("simpleVS", "simpleFS", blend: true)
        hudPipe = try pipe("hudVS", "hudFS", blend: true)
        starPipe = try pipe("starVS", "simpleFS", blend: true)
        cloudPipe = try pipe("cloudVS", "cloudFS", blend: true)
        mobPipe = try pipe("mobVS", "mobFS", blend: false)
        entityPipe = try pipe("entityVS", "entityFS", blend: false)
        crackPipe = try pipe("entityVS", "crackFS", blend: true)

        // Star field: fixed random directions on a sphere of radius 90 (sky frame, rotated per frame).
        var stars: [SimpleVert] = []
        for i in 0..<1400 {
            let u1 = hashf(i, 1, 0, 4242) * 2 - 1, u2 = hashf(i, 2, 0, 4242) * 2 * .pi
            let rr = (1 - u1 * u1).squareRoot()
            let dir = V3(rr * cosf(u2), u1, rr * sinf(u2))
            let size: Float = 0.1 + 0.16 * hashf(i, 3, 0, 4242) * hashf(i, 4, 0, 4242)
            let b: Float = 0.45 + 0.55 * hashf(i, 5, 0, 4242)
            let warm = hashf(i, 6, 0, 4242)
            let col = V4(b * (0.85 + 0.15 * warm), b * 0.9, b * (1 - 0.15 * warm), 1)
            let c = dir * 90
            let ref = abs(dir.y) > 0.9 ? V3(1, 0, 0) : V3(0, 1, 0)
            let r = simd_normalize(simd_cross(dir, ref)) * size
            let up = simd_normalize(simd_cross(r, dir)) * size
            let q = [c - r - up, c + r - up, c + r + up, c - r + up]
            for k in [0, 1, 2, 0, 2, 3] { stars.append(SimpleVert(pos: V4(q[k], 1), color: col)) }
        }
        starVerts = stars.count
        starBuf = device.makeBuffer(bytes: stars, length: stars.count * MemoryLayout<SimpleVert>.stride, options: .storageModeShared)!

        func ds(_ cmp: MTLCompareFunction, _ write: Bool) -> MTLDepthStencilState {
            let d = MTLDepthStencilDescriptor()
            d.depthCompareFunction = cmp
            d.isDepthWriteEnabled = write
            return device.makeDepthStencilState(descriptor: d)!
        }
        depthWrite = ds(.less, true)
        depthRead = ds(.lessEqual, false)
        depthNone = ds(.always, false)

        // Texture array with CPU-built mip chain
        let levels = TextureGen.mipChain()
        let layers = Tex.count
        let td = MTLTextureDescriptor()
        td.textureType = .type2DArray
        td.pixelFormat = .rgba8Unorm
        td.width = TextureGen.S
        td.height = TextureGen.S
        td.arrayLength = layers
        td.mipmapLevelCount = levels.count
        td.usage = .shaderRead
        let tex = device.makeTexture(descriptor: td)!
        var size = TextureGen.S
        for (lvl, data) in levels.enumerated() {
            let bytesPerImage = size * size * 4
            data.withUnsafeBytes { raw in
                for layer in 0..<layers {
                    tex.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: lvl, slice: layer,
                                    withBytes: raw.baseAddress! + layer * bytesPerImage,
                                    bytesPerRow: size * 4, bytesPerImage: bytesPerImage)
                }
            }
            size = max(1, size / 2)
        }
        texture = tex

        // Shared index buffer: every quad is 4 vertices -> 2 CCW triangles.
        var idx = [UInt32]()
        idx.reserveCapacity(Renderer.maxQuads * 6)
        for q in 0..<UInt32(Renderer.maxQuads) {
            let b = q * 4
            idx.append(contentsOf: [b, b + 1, b + 2, b, b + 2, b + 3])
        }
        quadIndices = device.makeBuffer(bytes: idx, length: idx.count * 4, options: .storageModeShared)!

        super.init()
        for _ in 0..<3 { ring.append(device.makeBuffer(length: ringSize, options: .storageModeShared)!) }
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = now - lastTime
        lastTime = now
        game.tick(dt)

        fpsFrames += 1
        fpsTime += dt
        if fpsTime >= 0.5 { fps = Double(fpsFrames) / fpsTime; fpsFrames = 0; fpsTime = 0 }

        guard let rpd = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else { return }
        inflight.wait()
        if game.screenshotRequested {
            // F2: hold every in-flight ring buffer, render the same view offscreen, save it to ~/Pictures/Blocksmith.
            game.screenshotRequested = false
            inflight.wait(); inflight.wait()
            let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Blocksmith")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH.mm.ss"
            let name = "Blocksmith-\(f.string(from: Date())).png"
            let sz = view.drawableSize
            _ = renderToPNG(path: dir.appendingPathComponent(name).path, width: Int(sz.width), height: Int(sz.height))
            inflight.signal(); inflight.signal()
            game.onToast?("Saved screenshot as \(name)")
        }
        let cmd = queue.makeCommandBuffer()!
        cmd.addCompletedHandler { [inflight] _ in inflight.signal() }
        let sky = game.skyColor
        let clear = game.blindFog != nil ? V3(0, 0, 0) : (game.player.headInWater ? V3(0.05, 0.12, 0.3) : sky)
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: Double(clear.x), green: Double(clear.y), blue: Double(clear.z), alpha: 1)
        let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)!
        let s = view.drawableSize
        encode(enc, width: Float(s.width), height: Float(s.height))
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
        onFrame?(dt)
    }

    // MARK: Scene

    func encode(_ enc: MTLRenderCommandEncoder, width W: Float, height H: Float) {
        frame = (frame + 1) % ring.count
        let scratch = ring[frame]
        var scratchOff = 0
        func pushBytes(_ raw: UnsafeRawBufferPointer) -> Int? {
            if raw.count == 0 { return nil }
            let aligned = (scratchOff + 255) & ~255
            guard aligned + raw.count <= ringSize else { return nil }
            memcpy(scratch.contents() + aligned, raw.baseAddress!, raw.count)
            scratchOff = aligned + raw.count
            return aligned
        }
        func push(_ items: [SimpleVert]) -> Int? { items.withUnsafeBytes { pushBytes($0) } }
        func push(_ items: [HudVert]) -> Int? { items.withUnsafeBytes { pushBytes($0) } }

        let p = game.player
        // Camera: first person, or pulled back behind / in front of the player (F5), stopping short of blocks.
        let tp = game.cameraMode != 0 && game.sleeping == 0
        var camYaw = p.yaw, camPitch = p.pitch
        var eye = p.eye
        if tp {
            let front = game.cameraMode == 2
            let dir = front ? p.look : -p.look
            if front { camYaw = p.yaw + .pi; camPitch = -p.pitch }
            var dist: Float = 4
            var t: Float = 0.1
            while t < 4 {
                let q = p.eye + dir * t
                if Blocks.opaque[Int(game.world.block(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z))))] { dist = max(0.2, t - 0.3); break }
                t += 0.1
            }
            eye = p.eye + dir * dist
        }
        let camLook = V3(-sinf(camYaw) * cosf(camPitch), sinf(camPitch), -cosf(camYaw) * cosf(camPitch))
        let rd = Float(game.world.renderDistance)
        let underwater = p.headInWater
        let far = rd * 16 + 96
        let proj = perspectiveRH(fovy: game.fovSetting * game.fovScale * .pi / 180, aspect: W / max(H, 1), near: 0.05, far: far)
        let viewRot = rotationX(-camPitch) * rotationY(-camYaw)
        let viewProj = proj * viewRot
        let frustum = Frustum(viewProj * translationMatrix(-eye))

        let sky = game.skyColor
        let hasSky = game.dim.dim.hasSky
        var fogEnd: Float = underwater ? 20 : (game.dim.dim == .nether ? min(rd * 16 - 6, 96) : rd * 16 - 6)
        var fogStart: Float = underwater ? 1 : fogEnd * 0.62
        var fogColor = underwater ? V3(0.05, 0.12, 0.3) : sky
        if let bf = game.blindFog { fogEnd = min(fogEnd, bf); fogStart = bf * 0.2; fogColor = V3(0, 0, 0) }
        let daylight = game.daylight
        // Night vision lifts every light level toward full brightness.
        let nv = game.nightVision
        let ambient = 1 - (1 - game.dim.dim.ambient) * (1 - 0.85 * nv)
        var u = Uniforms(viewProj: viewProj,
                         fogColor: V4(fogColor, fogStart),
                         params: V4(fogEnd, daylight, Float(game.time.truncatingRemainder(dividingBy: 1000)), underwater ? 1 : 0),
                         sunDir: V4(game.sunDir, ambient))

        enc.setFragmentTexture(texture, index: 0)

        // Sky bodies (camera-relative, no depth)
        do {
            var verts: [SimpleVert] = []
            func body(_ dir: V3, _ size: Float, _ color: V4) {
                let c = dir * 90
                let r = simd_normalize(simd_cross(dir, V3(0, 0, 1))) * size
                let up = simd_normalize(simd_cross(r, dir)) * size
                let q = [c - r - up, c + r - up, c + r + up, c - r + up]
                for i in [0, 1, 2, 0, 2, 3] { verts.append(SimpleVert(pos: V4(q[i], 1), color: color)) }
            }
            let sd = game.sunDir
            if !underwater && hasSky {
                body(sd, 7, V4(1.0, 0.95, 0.75, 1))
                body(sd, 11, V4(1.0, 0.85, 0.5, 0.18))
                body(-sd, 5, V4(0.85, 0.88, 0.95, 1))
            }
            let starAlpha = simd_clamp((0.6 - daylight) / 0.35, 0, 1)
            if !underwater && starAlpha > 0 && hasSky {
                var sp = StarParams(rot: rotationZ(Float(game.dayFraction * 2 * .pi)), tint: V4(1, 1, 1, starAlpha))
                enc.setRenderPipelineState(starPipe)
                enc.setDepthStencilState(depthNone)
                enc.setCullMode(.none)
                enc.setVertexBuffer(starBuf, offset: 0, index: 0)
                enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                enc.setVertexBytes(&sp, length: MemoryLayout<StarParams>.stride, index: 2)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: starVerts)
            }
            if let off = push(verts) {
                enc.setRenderPipelineState(simplePipe)
                enc.setDepthStencilState(depthNone)
                enc.setCullMode(.none)
                enc.setVertexBuffer(scratch, offset: off, index: 0)
                enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verts.count)
            }
        }

        // Visible sections, near to far
        let pcx = floorDiv(Int(floor(eye.x)), CS), pcz = floorDiv(Int(floor(eye.z)), CS)
        visibleScratch.removeAll(keepingCapacity: true)
        var drawnSet = 0
        let pSec = Int(floor(eye.y / 16))
        if caveCulling, let startC = game.world.chunks[ChunkKey(x: pcx, z: pcz)], pSec >= 0 && pSec < NSEC {
            // Cave culling: walk sections outward from the camera, only through faces that connect via
            // open cells and never back toward the camera; frustum-test every step.
            let R = game.world.renderDistance + 1, span = 2 * R + 1
            let need = span * span * NSEC
            if visitGen.count < need { visitGen = [UInt32](repeating: 0, count: need) }
            gen &+= 1
            if gen == 0 { gen = 1; for i in visitGen.indices { visitGen[i] = 0 } }
            func vidx(_ dx: Int, _ dz: Int, _ sy: Int) -> Int { ((dx + R) + (dz + R) * span) * NSEC + sy }
            bfs.removeAll(keepingCapacity: true)
            bfs.append((startC, 0, 0, pSec, -1, 0))
            visitGen[vidx(0, 0, pSec)] = gen
            var head = 0
            let dirs = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
            while head < bfs.count {
                let (c, dx, dz, sy, entry, dirMask) = bfs[head]; head += 1
                let sec = c.sections[sy]
                let mn = V3(Float(c.cx * CS), Float(sy * 16), Float(c.cz * CS))
                if !sec.empty {
                    visibleScratch.append((c, sy, simd_length_squared(mn + V3(8, 8, 8) - eye)))
                    if c.drawnMark != gen { c.drawnMark = gen; drawnSet += 1 }
                }
                let vis = sec.meshedVersion == -1 ? ~UInt64(0) : sec.vis
                for f in 0..<6 {
                    if dirMask & (1 << (f ^ 1)) != 0 { continue }
                    if entry >= 0 && vis & (1 << UInt64(entry * 6 + f)) == 0 { continue }
                    let (ox, oy, oz) = dirs[f]
                    let ndx = dx + ox, ndz = dz + oz, nsy = sy + oy
                    if nsy < 0 || nsy >= NSEC || !game.world.inMeshRadius(ndx, ndz) || abs(ndx) > R || abs(ndz) > R { continue }
                    let vi = vidx(ndx, ndz, nsy)
                    if visitGen[vi] == gen { continue }
                    let nmn = V3(Float((pcx + ndx) * CS), Float(nsy * 16), Float((pcz + ndz) * CS))
                    if !frustum.visible(min: nmn, max: nmn + V3(16, 16, 16)) { continue }
                    guard let nc = ox == 0 && oz == 0 ? c : game.world.chunks[ChunkKey(x: pcx + ndx, z: pcz + ndz)], nc.meshedOnce else { continue }
                    visitGen[vi] = gen
                    bfs.append((nc, ndx, ndz, nsy, f ^ 1, dirMask | (1 << f)))
                }
            }
        } else {
        for (_, c) in game.world.chunks where c.meshedOnce {
            let dx = c.cx - pcx, dz = c.cz - pcz
            if !game.world.inMeshRadius(dx, dz) { continue }
            let cmn = V3(Float(c.cx * CS), 0, Float(c.cz * CS))
            if !frustum.visible(min: cmn, max: cmn + V3(16, Float(CH), 16)) { continue }
            var any = false
            for (sy, sec) in c.sections.enumerated() where !sec.empty {
                let mn = V3(cmn.x, Float(sy * 16), cmn.z)
                let mx = mn + V3(16, 16, 16)
                if !frustum.visible(min: mn, max: mx) { continue }
                let center = (mn + mx) * 0.5 - eye
                visibleScratch.append((c, sy, simd_length_squared(center)))
                any = true
            }
            if any { drawnSet += 1 }
        }
        }
        visibleScratch.sort { $0.2 < $1.2 }
        drawnChunks = drawnSet
        let visible = visibleScratch

        func offset(_ c: Chunk, _ sy: Int) -> V4 { V4(Float(c.cx * CS) - eye.x, Float(sy * 16) - eye.y, Float(c.cz * CS) - eye.z, 0) }

        enc.setDepthStencilState(depthWrite)
        enc.setCullMode(.back)
        enc.setFrontFacing(.counterClockwise)
        enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        // Two passes, near to far: solid cube faces without alpha test first (the GPU can then reject
        // hidden fragments before shading), then the alpha-tested cutout faces (leaves, plants, models).
        for pass in 0..<2 {
            enc.setRenderPipelineState(pass == 0 ? chunkSolidPipe : chunkPipe)
            for (c, sy, _) in visible {
                let sec = c.sections[sy]
                guard sec.opaqueQuads > 0, let buf = sec.opaqueBuf, let tb = c.tintBuf else { continue }
                let total = min(sec.opaqueQuads, Renderer.maxQuads), solid = min(sec.solidQuads, total)
                let first = pass == 0 ? 0 : solid, count = pass == 0 ? solid : total - solid
                if count <= 0 { continue }
                var o = offset(c, sy)
                enc.setVertexBuffer(buf.buffer, offset: buf.offset, index: 0)
                enc.setVertexBytes(&o, length: 16, index: 2)
                enc.setVertexBuffer(tb, offset: 0, index: 3)
                enc.drawIndexedPrimitives(type: .triangle, indexCount: count * 6,
                                          indexType: .uint32, indexBuffer: quadIndices, indexBufferOffset: first * 6 * 4)
            }
        }

        // Mobs (written straight into the scratch ring: no per-frame arrays)
        if !game.mobs.mobs.isEmpty || tp {
            let off = (scratchOff + 255) & ~255
            let cap = (ringSize - off) / MemoryLayout<MobVert>.stride
            if cap > 36 {
                let ptr = (scratch.contents() + off).bindMemory(to: MobVert.self, capacity: cap)
                var n = writeMobVertices(game.mobs.mobs, eye: eye, daylight: daylight, world: game.world, into: ptr, capacity: cap)
                if tp { n += writePlayerModel(game, eye: eye, daylight: daylight, into: ptr + n, capacity: cap - n) }
                if n > 0 {
                    scratchOff = off + n * MemoryLayout<MobVert>.stride
                    enc.setRenderPipelineState(mobPipe)
                    enc.setDepthStencilState(depthWrite)
                    enc.setCullMode(.none)
                    enc.setVertexBuffer(scratch, offset: off, index: 0)
                    enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                    enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: n)
                }
            }
        }

        // Dropped items and the crack overlay (written straight into the scratch ring)
        do {
            let entOff = (scratchOff + 255) & ~255
            let stride = MemoryLayout<EntityVert>.stride
            let entCap = (ringSize - entOff) / stride
            if entCap > 64 {
                let ptr = (scratch.contents() + entOff).bindMemory(to: EntityVert.self, capacity: entCap)
                var wr = EntityWriter(out: ptr, capacity: entCap)
                let right = V3(cosf(camYaw), 0, -sinf(camYaw))
                let up = simd_normalize(simd_cross(right, camLook))
                game.drops.write(&wr, eye: eye, right: right, up: -up, world: game.world, daylight: daylight, time: Float(game.clock))
                game.projectiles.write(&wr, eye: eye, world: game.world, daylight: daylight)
                game.tnts.write(&wr, eye: eye, world: game.world, daylight: daylight)
                game.writeEndEntities(&wr, eye: eye, right: right, up: -up)
                game.writeFangs(&wr, eye: eye)
                game.writeBeams(&wr, eye: eye)
                game.writeWeather(&wr, eye: eye)
                game.writeFalling(&wr, eye: eye)
                game.writeDecor(&wr, eye: eye)
                game.writeBobber(&wr, eye: eye, right: right, up: -up)
                game.writeLeads(&wr, eye: eye)
                game.writeBanners(&wr, eye: eye)
                game.writeRockets(&wr, eye: eye)
                game.writeLecternBooks(&wr, eye: eye)
                game.writeShelves(&wr, eye: eye)
                game.particles.write(&wr, eye: eye, right: right, up: -up, world: game.world, daylight: daylight)
                let nItems = wr.n
                if let m = game.mining, game.mineProgress > 0 {
                    let layer = HudTex.destroy(Int(game.mineProgress * 10))
                    let o = V3(Float(m.x), Float(m.y), Float(m.z)) - eye
                    let CT = Mesher.cornerTable
                    let uvs = [V2(0, 1), V2(1, 1), V2(1, 0), V2(0, 0)]
                    for (bmn, bmx) in game.world.selectionBoxes(game.world.block(m.x, m.y, m.z)) {
                        let a = o + bmn - V3(repeating: 0.002), b = o + bmx + V3(repeating: 0.002)
                        for f in 0..<6 {
                            var ps: [V3] = []
                            for k in 0..<4 {
                                let ci = (f * 4 + k) * 3
                                ps.append(V3(CT[ci] == 1 ? b.x : a.x, CT[ci + 1] == 1 ? b.y : a.y, CT[ci + 2] == 1 ? b.z : a.z))
                            }
                            wr.quad(ps, uvs, layer, V4(1, 1, 1, 0.9))
                        }
                    }
                }
                if wr.n > 0 {
                    scratchOff = entOff + wr.n * stride
                    enc.setDepthStencilState(depthWrite)
                    enc.setCullMode(.none)
                    enc.setVertexBuffer(scratch, offset: entOff, index: 0)
                    enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                    enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                    if nItems > 0 {
                        enc.setRenderPipelineState(entityPipe)
                        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: nItems)
                    }
                    if wr.n > nItems {
                        enc.setRenderPipelineState(crackPipe)
                        enc.setDepthStencilState(depthRead)
                        enc.drawPrimitives(type: .triangle, vertexStart: nItems, vertexCount: wr.n - nItems)
                    }
                }
            }
        }

        // Target block outline (the block's selection boxes)
        let pe = game.player.eye
        let eyeCell = IVec3(Int(floor(pe.x)), Int(floor(pe.y)), Int(floor(pe.z)))
        if let t = game.target, t.hit != eyeCell {   // never outline the block the camera is in
            let e: Float = 0.003
            let o = V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) - eye
            var verts: [SimpleVert] = []
            let col = V4(0, 0, 0, 0.7)
            let edges = [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
            for (bmn, bmx) in game.world.selectionBoxes(game.world.block(t.hit.x, t.hit.y, t.hit.z)) {
                let a = o + bmn - V3(repeating: e), b = o + bmx + V3(repeating: e)
                let cs = [V3(a.x, a.y, a.z), V3(b.x, a.y, a.z), V3(b.x, a.y, b.z), V3(a.x, a.y, b.z),
                          V3(a.x, b.y, a.z), V3(b.x, b.y, a.z), V3(b.x, b.y, b.z), V3(a.x, b.y, b.z)]
                for i in edges { verts.append(SimpleVert(pos: V4(cs[i], 1), color: col)) }
            }
            if let off = push(verts) {
                enc.setRenderPipelineState(simplePipe)
                enc.setDepthStencilState(depthRead)
                enc.setCullMode(.none)
                enc.setVertexBuffer(scratch, offset: off, index: 0)
                enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                enc.drawPrimitives(type: .line, vertexStart: 0, vertexCount: verts.count)
            }
        }

        // Water, far to near
        enc.setRenderPipelineState(waterPipe)
        enc.setDepthStencilState(depthRead)
        enc.setCullMode(.none)
        enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        for (c, sy, _) in visible.reversed() {
            let sec = c.sections[sy]
            guard sec.transQuads > 0, let buf = sec.transBuf, let tb = c.tintBuf else { continue }
            var o = offset(c, sy)
            enc.setVertexBuffer(buf.buffer, offset: buf.offset, index: 0)
            enc.setVertexBytes(&o, length: 16, index: 2)
            enc.setVertexBuffer(tb, offset: 0, index: 3)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: min(sec.transQuads, Renderer.maxQuads) * 6,
                                      indexType: .uint32, indexBuffer: quadIndices, indexBufferOffset: 0)
        }

        // Cloud layer (after water so both blend over terrain; depth-tested against terrain).
        if !underwater && hasSky {
            let ext = far
            let cy = CLOUD_Y - eye.y
            let q = [V3(-ext, cy, -ext), V3(ext, cy, -ext), V3(ext, cy, ext), V3(-ext, cy, ext)]
            let cv = [0, 1, 2, 0, 2, 3].map { SimpleVert(pos: V4(q[$0], 1), color: V4(1, 1, 1, 1)) }
            if let off = push(cv) {
                let wind = Float((game.time * 1.3).truncatingRemainder(dividingBy: 12 * 8192))
                var cp = V4(eye.x + wind, eye.z, ext * 0.95, 0)
                enc.setRenderPipelineState(cloudPipe)
                enc.setDepthStencilState(depthRead)
                enc.setCullMode(.none)
                enc.setVertexBuffer(scratch, offset: off, index: 0)
                enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                enc.setFragmentBytes(&cp, length: 16, index: 2)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: cv.count)
            }
        }

        // First-person arm + held item, squeezed into the front of the depth range so it never clips.
        if drawHUD && !game.hideHUD && !tp && game.menu == nil && game.sleeping == 0 {
            var uh = u
            uh.viewProj = perspectiveRH(fovy: 70 * .pi / 180, aspect: W / max(H, 1), near: 0.01, far: 8)
            uh.fogColor.w = 100; uh.params.x = 200
            let ey = Int(floor(eye.y)) + (Blocks.opaque[Int(game.world.block(Int(floor(eye.x)), Int(floor(eye.y)), Int(floor(eye.z))))] ? 1 : 0)
            let l = game.world.lightAt(Int(floor(eye.x)), ey, Int(floor(eye.z)))
            let light = max(0.12, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15), game.nightVision * 0.9)
            let sw = game.swing
            let a = sinf(sqrtf(sw) * .pi)
            let bob = sinf(game.walkBob * 2) * 0.02 * game.walkAmount
            let base = V3(0.5 - 0.25 * a, -0.4 + 0.12 * sinf(sqrtf(sw) * 2 * .pi) + bob - 0.45 * game.equipAnim, -0.8 - 0.15 * sinf(sw * .pi))
            let held = game.held
            // Arm (skin-coloured box angled up into the screen).
            let armOff = (scratchOff + 255) & ~255
            let armPtr = (scratch.contents() + armOff).bindMemory(to: MobVert.self, capacity: 64)
            var an = 0
            let skin = V3(0.84, 0.64, 0.5)
            let axL = simd_normalize(V3(-0.12, 0.62, -0.78)) * (held.isEmpty ? 0.36 : 0.3)
            let axW = V3(0.075, 0, 0.03), axD = simd_normalize(simd_cross(axL, axW)) * 0.075
            let ac = base + V3(0.12, -0.34, 0.3) + (held.isEmpty ? V3(-0.05, 0.12, -0.1) : .zero)
            let CT = Mesher.cornerTable
            let faceShade: [Float] = [0.8, 0.8, 1.0, 0.55, 0.68, 0.68]
            for f in 0..<6 {
                for k in [0, 1, 2, 0, 2, 3] {
                    let ci = (f * 4 + k) * 3
                    let pp = ac + axW * Float(CT[ci] * 2 - 1) + axL * Float(CT[ci + 1] * 2 - 1) + axD * Float(CT[ci + 2] * 2 - 1)
                    armPtr[an] = MobVert(pos: V4(pp, 4), color: V4(skin, faceShade[f] * light), local: V4(pp * 32, 0))
                    an += 1
                }
            }
            scratchOff = armOff + an * MemoryLayout<MobVert>.stride
            enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(W), height: Double(H), znear: 0, zfar: 0.001))
            enc.setDepthStencilState(depthWrite)
            enc.setCullMode(.none)
            enc.setRenderPipelineState(mobPipe)
            enc.setVertexBuffer(scratch, offset: armOff, index: 0)
            enc.setVertexBytes(&uh, length: MemoryLayout<Uniforms>.stride, index: 1)
            enc.setFragmentBytes(&uh, length: MemoryLayout<Uniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: an)
            if !held.isEmpty {
                let itOff = (scratchOff + 255) & ~255
                let itPtr = (scratch.contents() + itOff).bindMemory(to: EntityVert.self, capacity: 64)
                var wr = EntityWriter(out: itPtr, capacity: 64)
                if let b = held.def.block, !Blocks.flatIcon(b) {
                    let t = Blocks.tint[Int(b)]
                    let tint = t == 1 || t == 3 ? V3(0.57, 0.74, 0.35) : (t == 2 ? V3(0.47, 0.67, 0.18) : V3(1, 1, 1))
                    wr.cube(center: base + V3(-0.02, 0.0, -0.05), half: 0.115, yaw: 0.8, block: b, light: light, tint: tint)
                } else {
                    let layer = Items.texLayer(held.item) ?? Int(Blocks.tex[Int(held.def.block ?? 0) * 6])
                    // Tools lean forward like they're gripped; two layers make the sprite look solid.
                    let r = simd_normalize(V3(-0.25, 0.1, -1)), up = simd_normalize(V3(0.1, 1, -0.05))
                    let c = base + V3(-0.02, 0.1, -0.1) + V3(0, 0, bowPull())
                    for (i, off) in [Float(0), 0.02].enumerated() {
                        let n = simd_normalize(simd_cross(r, up)) * off
                        let k: Float = i == 0 ? 1 : 0.7
                        wr.sprite(center: c + n, half: 0.2, right: r, up: up, layer: layer, light: light * k)
                    }
                }
                if wr.n > 0 {
                    scratchOff = itOff + wr.n * MemoryLayout<EntityVert>.stride
                    enc.setRenderPipelineState(entityPipe)
                    enc.setVertexBuffer(scratch, offset: itOff, index: 0)
                    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: wr.n)
                }
            }
            enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(W), height: Double(H), znear: 0, zfar: 1))
        }

        if drawHUD && (!game.hideHUD || game.menu != nil), let off = push(buildHUD(W, H)) {
            let count = (scratchOff - off) / MemoryLayout<HudVert>.stride
            var screen = V2(W, H)
            enc.setRenderPipelineState(hudPipe)
            enc.setDepthStencilState(depthNone)
            enc.setCullMode(.none)
            enc.setVertexBuffer(scratch, offset: off, index: 0)
            enc.setVertexBytes(&screen, length: 8, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
        }
    }

    func bowPull() -> Float { Items.key(game.held.item) == "bow" ? min(1, game.bowCharge) * 0.12 : 0 }

    // MARK: HUD (pixel coordinates, origin top-left)

    var hudScale: Float = 2

    func buildHUD(_ W: Float, _ H: Float) -> [HudVert] {
        var v: [HudVert] = []
        let L = HudLayout(W, H)
        let s = L.s
        hudScale = s
        self.game.screen = V2(W, H)
        func quad(_ p: [V2], _ uv: [V2], _ c: V4, _ layer: Float) {
            for i in [0, 1, 2, 0, 2, 3] { v.append(HudVert(pos: p[i], uv: uv[i], color: c, extra: V4(layer, 0, 0, 0))) }
        }
        func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ c: V4) {
            quad([V2(x, y), V2(x + w, y), V2(x + w, y + h), V2(x, y + h)], [V2](repeating: .zero, count: 4), c, -1)
        }
        let game = self.game
        // Pixel-font text; scale = size of one font pixel in screen pixels.
        func text(_ str: String, _ x: Float, _ y: Float, _ scale: Float, _ color: V4 = V4(1, 1, 1, 1), shadow: Bool = true) {
            var cx = x
            var color = color, shadow = shadow
            let baseColor = color, baseShadow = shadow
            let us = str.unicodeScalars
            var idx = us.startIndex
            while idx < us.endIndex {
                let u = us[idx]
                idx = us.index(after: idx)
                let code = Int(u.value)
                let adv = Float(Font.advance(code))
                if Glyphs.isGlyph(code) {
                    // Controller glyphs and key caps (Glyphs.swift).
                    if code == Glyphs.capOpen {
                        var w = 0, j = idx
                        while j < us.endIndex && Int(us[j].value) != Glyphs.capClose { w += Font.advance(Int(us[j].value)); j = us.index(after: j) }
                        Glyphs.cap(cx, y, Float(w + 3) * scale, scale, baseColor.w, rect: rect)
                        color = V4(Glyphs.capInk.x, Glyphs.capInk.y, Glyphs.capInk.z, baseColor.w); shadow = false
                    } else if code == Glyphs.capClose {
                        color = baseColor; shadow = baseShadow
                    } else {
                        Glyphs.draw(code, cx, y, scale, baseColor.w, rect: rect) { t, tx, ty, ts, tc, sh in text(t, tx, ty, ts, tc, shadow: sh) }
                    }
                    cx += adv * scale
                    continue
                }
                if code > 32 && code < 127 {
                    let w = Float(Font.glyphs[code - 32][0])
                    let layer = Float(Font.layerBase + code - 32)
                    let uv = [V2(0, 0), V2(w / 16, 0), V2(w / 16, 7 / 16), V2(0, 7 / 16)]
                    func g(_ ox: Float, _ oy: Float, _ c: V4) {
                        let a = V2(cx + ox, y + oy)
                        quad([a, a + V2(w * scale, 0), a + V2(w * scale, 7 * scale), a + V2(0, 7 * scale)], uv, c, layer)
                    }
                    if shadow { g(scale, scale, V4(color.x * 0.25, color.y * 0.25, color.z * 0.25, color.w)) }
                    g(0, 0, color)
                }
                cx += adv * scale
            }
        }
        func textWidth(_ str: String, _ scale: Float) -> Float { Float(Font.width(str)) * scale }

        if game.player.headInWater { rect(0, 0, W, H, V4(0.05, 0.15, 0.45, 0.35)) }
        if game.sleeping > 0 { rect(0, 0, W, H, V4(0.02, 0.02, 0.06, min(1, game.sleeping / 1.5))) }
        if game.hurtFlash > 0 { rect(0, 0, W, H, V4(0.75, 0.02, 0.02, min(0.45, game.hurtFlash * 1.3))) }
        if game.portalTime > 0 { rect(0, 0, W, H, V4(0.45, 0.1, 0.8, min(0.7, game.portalTime / 4 * 0.7))) }
        if game.onFire > 0 && game.menu == nil {
            // Flickering flames along the bottom of the view.
            let fireLayer = Float(Tex.id("fire"))
            let n = 8
            for i in 0..<n {
                let w = W / Float(n)
                let hh = H * (0.28 + 0.06 * sinf(Float(game.clock) * 9 + Float(i) * 1.7))
                quad([V2(Float(i) * w, H - hh), V2(Float(i + 1) * w, H - hh), V2(Float(i + 1) * w, H), V2(Float(i) * w, H)],
                     [V2(0, 0), V2(1, 0), V2(1, 1), V2(0, 1)], V4(1, 1, 1, 0.85), fireLayer)
            }
        }

        if let c = game.credits {
            // Credits: black screen, lines scrolling up from the bottom.
            rect(0, 0, W, H, V4(0, 0, 0, 1))
            let lineH = 14 * s
            let y0 = H + 20 - c * lineH / 1.4
            for (i, line) in Game.creditsLines.enumerated() {
                let y = y0 + Float(i) * lineH
                if y < -lineH || y > H { continue }
                let big = i == 0
                let sc = big ? s * 2 : s
                let col = big ? V4(0.95, 0.85, 0.4, 1) : V4(0.9, 0.9, 0.9, 1)
                text(line, (W - textWidth(line, sc)) / 2, y, sc, col)
            }
            return v
        }
        if game.menu == nil {
            // Boss bars: hollow wyrm (pink), blight (purple), raid (red).
            var bars: [(String, Float, V4)] = []
            if let d = game.mobs.mobs.first(where: { $0.kind == .enderDragon }) { bars.append(("Hollow Wyrm", Float(d.health) / 200, V4(0.9, 0.3, 0.95, 1))) }
            for wi in game.mobs.mobs where wi.kind == .wither && simd_length(wi.pos - game.player.pos) < 64 {
                bars.append((wi.customName ?? "Blight", Float(wi.health) / 300, V4(0.6, 0.2, 0.85, 1)))
            }
            if let r = game.raidBar { bars.append((r.0, r.1, V4(0.85, 0.15, 0.15, 1))) }
            for (i, b) in bars.enumerated() {
                let bw = 182 * s, bx = (W - bw) / 2, by = L.insetY + 12 * s + Float(i) * 19 * s
                text(b.0, (W - textWidth(b.0, s)) / 2, by - 9 * s, s)
                rect(bx, by, bw, 5 * s, V4(b.2.x * 0.3, b.2.y * 0.3, b.2.z * 0.3, 1))
                rect(bx, by, bw * max(0, min(1, b.1)), 5 * s, b.2)
            }
        }

        func frame(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ b: Float, _ c: V4) {
            rect(x, y, w, b, c)
            rect(x, y + h - b, w, b, c)
            rect(x, y, b, h, c)
            rect(x + w - b, y, b, h, c)
        }
        let slot = L.slot

        // Banner cloth: base colour (-1 = none) and pattern layers in a w x h rect.
        func bannerArt(_ base: Int, _ layers: [Int], _ x: Float, _ y: Float, _ w: Float, _ h: Float) {
            for half in 0..<2 {
                let y0 = y + h / 2 * Float(half)
                let pts = [V2(x, y0), V2(x + w, y0), V2(x + w, y0 + h / 2), V2(x, y0 + h / 2)]
                let uvs = [V2(0, 0), V2(1, 0), V2(1, 1), V2(0, 1)]
                let sfx = half == 0 ? "_t" : "_b"
                if base >= 0 { let t = Banners.tint(base); quad(pts, uvs, V4(t, 1), Float(Tex.id("banner_cloth" + sfx))) }
                for l in layers {
                    let (pi, ci) = Banners.decode(l)
                    guard pi < Banners.patterns.count else { continue }
                    let t = Banners.tint(ci)
                    quad(pts, uvs, V4(t, 1), Float(Tex.id("banner_pat_\(Banners.patterns[pi].0)" + sfx)))
                }
            }
        }

        // Item icon (block cube or sprite) with count and durability bar; size = slot pixel size.
        func itemIcon(_ st: ItemStack, _ x: Float, _ y: Float, _ size: Float, counts: Bool = true) {
            if st.isEmpty { return }
            let c = V2(x + size / 2, y + size / 2)
            if let layer = Items.texLayer(st.item) {
                let h = size * 0.5
                let pts = [V2(c.x - h, c.y - h), V2(c.x + h, c.y - h), V2(c.x + h, c.y + h), V2(c.x - h, c.y + h)]
                let uvs = [V2(0, 0), V2(1, 0), V2(1, 1), V2(0, 1)]
                // Dyed leather: tint the sprite from its leather brown to the dye colour.
                var tint = V4(1, 1, 1, 1)
                if st.def.name.hasPrefix("leather_"), let c = st.pat?.first {
                    let base = V3(0xA0 / 255.0, 0x59 / 255.0, 0x2B / 255.0)
                    tint = V4(Float((c >> 16) & 255) / 255 / base.x, Float((c >> 8) & 255) / 255 / base.y, Float(c & 255) / 255 / base.z, 1)
                }
                quad(pts, uvs, tint, Float(layer))
                // Live compass / clock: a needle toward spawn (or the lodestone / last death) or the time of day.
                let ik = st.def.name
                if ik == "compass" || ik == "clock" || ik == "recovery_compass" {
                    var ang: Float
                    if ik == "clock" {
                        ang = Float(game.dayFraction) * 2 * .pi - .pi / 2
                    } else {
                        let target = game.compassTarget(st)
                        let d = target - game.player.pos
                        let world = atan2f(d.x, -d.z)                 // bearing from north
                        ang = world + game.player.yaw - .pi / 2
                        if game.dim.dim != .overworld && ik == "compass" { ang = Float(game.clock * 7).truncatingRemainder(dividingBy: 2 * .pi) }
                    }
                    let r = size * 0.28, w = size * 0.05
                    let dir = V2(cosf(ang), sinf(ang)), nrm = V2(-dir.y, dir.x) * w
                    let tip = c + dir * r, tail = c - dir * r * 0.4
                    quad([tail - nrm, tip - nrm * 0.2, tip + nrm * 0.2, tail + nrm], [V2(0, 0), V2(1, 0), V2(1, 1), V2(0, 1)],
                         ik == "clock" ? V4(0.2, 0.2, 0.25, 1) : V4(0.85, 0.12, 0.12, 1), -1)
                }
                if let pat = st.pat, !st.def.name.hasPrefix("leather_") {
                    bannerArt(-1, pat, x + size * 3 / 16, y + size * 2 / 16, size * 10 / 16, size * 12 / 16)
                }
                if case let (ol, col)? = Items.overlayLayer(st.item) {
                    let t = TextureGen.hex(col)
                    quad(pts, uvs, V4(t.x, t.y, t.z, 1), Float(ol))
                }
                let k = st.def.name
                if st.ench != 0 || k == "enchanted_golden_apple" || k == "experience_bottle" || k == "nether_star" || k == "enchanted_book" {
                    // Enchantment glint: a pulsing violet sheen over the sprite.
                    let a = 0.25 + 0.15 * sinf(Float(game.clock) * 3 + Float(x) * 0.01)
                    quad(pts, uvs, V4(0.75, 0.35, 1, a), Float(layer))
                }
            } else if let b = st.def.block {
                icon(b, center: c, size: size * 0.78, quad)
            }
            let def = st.def
            if def.durability > 0 && st.damage > 0 {
                let f = 1 - Float(st.damage) / Float(def.durability)
                let bw = size * 13 / 16, bx = x + size * 1.5 / 16, by = y + size * 13 / 16
                rect(bx, by, bw, size / 8, V4(0, 0, 0, 1))
                rect(bx, by, bw * f, size / 16, Settings.shared.colorblind ? V4(1 - f * 0.8, 0.5 + 0.2 * f, 0.1 + 0.9 * f, 1) : V4(1 - f, f, 0, 1))
            }
            if counts && st.count > 1 {
                let t = "\(st.count)"
                text(t, x + size - textWidth(t, s) - s * 0.5 + s, y + size - 7 * s + s, s)
            }
        }

        if let m = game.menu {
            // Container screen: dimmed world, bevelled panel, slots, items, cursor stack, tooltip.
            // Big panels drop to a smaller GUI scale so they always fit (TV GUI scales, safe area).
            let ML = L.fitted(m)
            let s = ML.s
            rect(0, 0, W, H, m is DeathMenu ? V4(0.45, 0, 0, 0.55) : V4(0, 0, 0, 0.45))
            let o = m.origin(ML)
            let pw = Float(m.width) * s, ph = Float(m.height) * s
            let bg = V4(0.776, 0.776, 0.776, 1)
            rect(o.x + s, o.y, pw - 2 * s, ph, V4(0, 0, 0, 1))
            rect(o.x, o.y + s, pw, ph - 2 * s, V4(0, 0, 0, 1))
            rect(o.x + s, o.y + s, pw - 2 * s, ph - 2 * s, bg)
            rect(o.x + s, o.y + s, pw - 3 * s, 2 * s, V4(1, 1, 1, 1))
            rect(o.x + s, o.y + s, 2 * s, ph - 3 * s, V4(1, 1, 1, 1))
            rect(o.x + 2 * s, o.y + ph - 3 * s, pw - 3 * s, 2 * s, V4(0.333, 0.333, 0.333, 1))
            rect(o.x + pw - 3 * s, o.y + 2 * s, 2 * s, ph - 3 * s, V4(0.333, 0.333, 0.333, 1))
            let titleC = V4(0.25, 0.25, 0.25, 1)
            text(m.title, o.x + 8 * s, o.y + 6 * s, s, titleC, shadow: false)
            if m.showInventoryLabel { text("Inventory", o.x + 8 * s, o.y + Float(m.inventoryLabelY) * s, s, titleC, shadow: false) }
            if Settings.shared.buttonHints {
                // Control legend under the panel (controller glyphs or keys, following the last device used).
                let legend = Prompt.menuLegend(m, game)
                let lw = textWidth(legend, s), ly = min(H - 10 * s - ML.insetY, o.y + ph + 4 * s)
                rect(floor((W - lw) / 2) - 3 * s, ly - 3 * s, lw + 6 * s, 13 * s, V4(0, 0, 0, 0.35 + Settings.shared.textBackground * 0.5))
                text(legend, floor((W - lw) / 2), ly, s)
            }
            if let f = m as? FurnaceMenu {
                // Flame (fuel left) and arrow (cook progress).
                let fx = o.x + 57 * s, fy = o.y + 37 * s
                rect(fx, fy, 13 * s, 13 * s, V4(0.55, 0.55, 0.55, 1))
                if f.be.burn > 0 && f.be.burnMax > 0 {
                    let k = Float(f.be.burn) / Float(f.be.burnMax)
                    rect(fx, fy + 13 * s * (1 - k), 13 * s, 13 * s * k, V4(1, 0.55, 0.1, 1))
                }
                let ax = o.x + 79 * s, ay = o.y + 34 * s
                rect(ax, ay + 5 * s, 22 * s, 6 * s, V4(0.55, 0.55, 0.55, 1))
                rect(ax, ay + 5 * s, 22 * s * Float(f.be.cook) / 200, 6 * s, V4(1, 1, 1, 1))
            }
            if m is InventoryMenu && game.effects.any {
                var y = o.y
                for (e, a) in game.effects.active {
                    let bw = 120 * s
                    let bx = o.x - bw - 4 * s
                    guard bx > 0 else { break }
                    rect(bx, y, bw, 32 * s, V4(0.776, 0.776, 0.776, 1))
                    frame(bx, y, bw, 32 * s, s, V4(0.2, 0.2, 0.2, 1))
                    quad([V2(bx + 6 * s, y + 7 * s), V2(bx + 24 * s, y + 7 * s), V2(bx + 24 * s, y + 25 * s), V2(bx + 6 * s, y + 25 * s)],
                         [V2(0, 0), V2(1, 0), V2(1, 1), V2(0, 1)], V4(1, 1, 1, 1), Float(Tex.id("effect_" + e.key)))
                    text(e.name + (a.amp > 0 ? " " + Effect.roman(a.amp + 1) : ""), bx + 28 * s, y + 7 * s, s)
                    let secs = Int(a.time)
                    text(a.time > 1e6 ? "Infinite" : String(format: "%d:%02d", secs / 60, secs % 60), bx + 28 * s, y + 18 * s, s, V4(0.5, 0.5, 0.5, 1))
                    y += 33 * s
                }
            }
            if m is InventoryMenu {
                rect(o.x + 26 * s, o.y + 8 * s, 50 * s, 70 * s, V4(0, 0, 0, 1))
                rect(o.x + 27 * s, o.y + 9 * s, 48 * s, 68 * s, V4(0.35, 0.35, 0.38, 1))
                text("Crafting", o.x + 97 * s, o.y + 7 * s, s, titleC, shadow: false)
                rect(o.x + 136 * s, o.y + 33 * s, 12 * s, 3 * s, V4(0.55, 0.55, 0.55, 1))
            }
            if m is CraftingTableMenu { rect(o.x + 90 * s, o.y + 33 * s, 22 * s, 6 * s, V4(0.55, 0.55, 0.55, 1)) }
            if let b = m as? BrewingMenu {
                // Cinderwisp fuel bar, brew progress (downward arrow) and bubbles.
                rect(o.x + 60 * s, o.y + 44 * s, 18 * s, 4 * s, V4(0.3, 0.3, 0.3, 1))
                rect(o.x + 60 * s, o.y + 44 * s, 18 * s * Float(b.be.fuel) / 20, 4 * s, V4(1, 0.6, 0.1, 1))
                rect(o.x + 97 * s, o.y + 16 * s, 9 * s, 28 * s, V4(0.55, 0.55, 0.55, 1))
                if b.be.brewTime > 0 {
                    let k = 1 - Float(b.be.brewTime) / 400
                    rect(o.x + 97 * s, o.y + 16 * s, 9 * s, 28 * s * k, V4(1, 1, 1, 1))
                    let bub = Float(Int(game.clock * 6) % 7) * 4 * s
                    rect(o.x + 65 * s, o.y + 42 * s - bub, 3 * s, 3 * s, V4(0.9, 0.9, 1, 0.8))
                }
                // Tubes from the ingredient to the bottles.
                rect(o.x + 63 * s, o.y + 36 * s, 50 * s, 2 * s, V4(0.45, 0.45, 0.45, 1))
            }
            if let e = m as? EnchantMenu {
                // Open book on the left, then the three offers: cost, clue and lapis needed.
                rect(o.x + 12 * s, o.y + 14 * s, 36 * s, 26 * s, V4(0.45, 0.22, 0.1, 1))
                rect(o.x + 14 * s, o.y + 16 * s, 15 * s, 22 * s, V4(0.93, 0.9, 0.8, 1))
                rect(o.x + 31 * s, o.y + 16 * s, 15 * s, 22 * s, V4(0.93, 0.9, 0.8, 1))
                for i in 0..<3 {
                    let bx = o.x + 60 * s, by = o.y + Float(14 + 19 * i) * s
                    let ok = e.available(i)
                    let hover = game.menuHover === e.slots[2 + i]
                    let bg = e.costs[i] == 0 ? V4(0.55, 0.55, 0.55, 1) : (ok ? (hover ? V4(0.75, 0.55, 0.85, 1) : V4(0.62, 0.5, 0.7, 1)) : V4(0.45, 0.4, 0.45, 1))
                    rect(bx, by, 108 * s, 19 * s, V4(0.2, 0.2, 0.2, 1))
                    rect(bx + s, by + s, 106 * s, 17 * s, bg)
                    guard e.costs[i] > 0 else { continue }
                    // Lapis pips.
                    for k in 0...i { rect(bx + Float(2 + k * 5) * s, by + 3 * s, 4 * s, 4 * s, V4(0.16, 0.36, 0.78, 1)) }
                    let ct = "\(e.costs[i])"
                    text(ct, bx + 106 * s - textWidth(ct, s), by + 10 * s, s, ok ? Settings.shared.goodColor : Settings.shared.badColor * V4(0.6, 0.6, 0.6, 1))
                    if let c = e.clues[i] {
                        var clue = Enchant.displayLine(c.0, c.1) + " . . . ?"
                        while textWidth(clue, s) > 84 * s && clue.count > 4 { clue.removeLast() }
                        text(clue, bx + 18 * s, by + 3 * s, s, ok ? V4(0.2, 0.15, 0.3, 1) : V4(0.3, 0.3, 0.3, 1), shadow: false)
                    }
                }
            }
            if let a = m as? AnvilMenu {
                // Hammer icon, name field, "+" and arrow, level cost.
                rect(o.x + 60 * s, o.y + 20 * s, 104 * s, 13 * s, a.editing ? V4(0, 0, 0, 1) : V4(0.25, 0.25, 0.25, 1))
                rect(o.x + 61 * s, o.y + 21 * s, 102 * s, 11 * s, a.editing ? V4(0.08, 0.08, 0.08, 1) : V4(0.35, 0.35, 0.35, 1))
                var nm = a.name
                while textWidth(nm, s) > 98 * s && !nm.isEmpty { nm.removeFirst() }
                let caret = a.editing && Int(game.clock * 2) % 2 == 0 ? "_" : ""
                text(nm + caret, o.x + 63 * s, o.y + 23 * s, s, V4(0.95, 0.95, 0.95, 1))
                text("+", o.x + 56 * s, o.y + 51 * s, s, titleC, shadow: false)
                rect(o.x + 101 * s, o.y + 52 * s, 22 * s, 6 * s, V4(0.55, 0.55, 0.55, 1))
                if a.cost > 0 {
                    let t = a.tooExpensive ? "Too Expensive!" : "Enchantment Cost: \(a.cost)"
                    let ok = !a.tooExpensive && (!game.survival || game.xpLevel >= a.cost)
                    text(t, o.x + 168 * s - textWidth(t, s), o.y + 69 * s, s, ok ? Settings.shared.goodColor : Settings.shared.badColor)
                }
            }
            if let sm = m as? SignMenu {
                // The sign board with its four lines; the edited line shows a cursor.
                rect(o.x + 28 * s, o.y + 20 * s, 120 * s, 60 * s, V4(0.62, 0.48, 0.28, 1))
                for (i, line) in sm.be.lines.enumerated() {
                    let caret = i == sm.line && Int(game.clock * 2) % 2 == 0 ? "_" : ""
                    let t = line + caret
                    text(t, o.x + 88 * s - textWidth(line, s) / 2, o.y + Float(26 + i * 12) * s, s, V4(0.08, 0.06, 0.04, 1), shadow: false)
                }
                let b = sm.slots[0]
                rect(o.x + Float(b.x) * s, o.y + Float(b.y) * s, 50 * s, 16 * s, game.menuHover === b ? V4(0.7, 0.7, 0.8, 1) : V4(0.5, 0.5, 0.55, 1))
                text("Done", o.x + Float(b.x + 13) * s, o.y + Float(b.y + 4) * s, s)
            }
            if let bm = m as? BookMenu {
                // Parchment page with wrapped text, page counter and buttons.
                rect(o.x + 24 * s, o.y + 4 * s, 144 * s, 172 * s, V4(0.93, 0.89, 0.78, 1))
                rect(o.x + 24 * s, o.y + 4 * s, 144 * s, 3 * s, V4(0.55, 0.38, 0.22, 1))
                let ink = V4(0.1, 0.08, 0.06, 1)
                if bm.signing {
                    text("Enter Book Title:", o.x + 44 * s, o.y + 30 * s, s, ink, shadow: false)
                    let caret = Int(game.clock * 2) % 2 == 0 ? "_" : ""
                    text(bm.bookTitle + caret, o.x + 96 * s - textWidth(bm.bookTitle, s) / 2, o.y + 48 * s, s, ink, shadow: false)
                    text("by Player", o.x + 70 * s, o.y + 60 * s, s, V4(0.4, 0.4, 0.4, 1), shadow: false)
                    text("Signing makes the book", o.x + 36 * s, o.y + 90 * s, s, ink, shadow: false)
                    text("read-only.", o.x + 36 * s, o.y + 100 * s, s, ink, shadow: false)
                } else {
                    let pg = "Page \(bm.page + 1) of \(bm.pages.count)"
                    text(pg, o.x + 160 * s - textWidth(pg, s), o.y + 12 * s, s, V4(0.35, 0.3, 0.25, 1), shadow: false)
                    var lines = Books.wrap(bm.pages[bm.page])
                    if bm.editable && Int(game.clock * 2) % 2 == 0 { if lines.isEmpty { lines = ["_"] } else { lines[lines.count - 1] += "_" } }
                    for (i, l) in lines.prefix(Books.linesPerPage).enumerated() {
                        text(l, o.x + 36 * s, o.y + Float(26 + i * 9) * s, s, ink, shadow: false)
                    }
                }
                for sl in bm.slots where sl.isButton {
                    guard case .button(let i) = sl.kind else { continue }
                    let x = o.x + Float(sl.x) * s, y = o.y + Float(sl.y) * s
                    let label = [0: "<", 1: ">", 2: bm.signing ? "Sign" : "Done", 3: "Sign", 6: "Take"][i] ?? ""
                    if i == 3 && bm.signing { continue }
                    rect(x, y, Float(sl.w) * s, Float(sl.h) * s, game.menuHover === sl ? V4(0.7, 0.7, 0.8, 1) : V4(0.5, 0.5, 0.55, 1))
                    text(label, x + (Float(sl.w) * s - textWidth(label, s)) / 2, y + (Float(sl.h) - 7) / 2 * s, s)
                }
            }
            if let hb = m as? HasRecipeBook {
                let book = hb.book
                if book.open {
                    let bx = o.x - 122 * s
                    rect(bx, o.y, 120 * s, 162 * s, V4(0.776, 0.776, 0.776, 1))
                    frame(bx, o.y, 120 * s, 162 * s, s, V4(0.33, 0.33, 0.33, 1))
                    text("Recipes \(book.page + 1)/\(book.pages)", bx + 4 * s, o.y + 16 * s, s, titleC, shadow: false)
                }
                let pool = hb.poolFor(hb.craftGrid)
                for sl in hb.slots where sl.isButton {
                    guard case .button(let id) = sl.kind, id >= 490 && id < 600 else { continue }
                    let x = o.x + Float(sl.x) * s, y = o.y + Float(sl.y) * s
                    let hot = game.menuHover === sl
                    if id == 490 {
                        rect(x, y, Float(sl.w) * s, Float(sl.h) * s, hot ? V4(0.6, 0.75, 0.6, 1) : V4(0.55, 0.45, 0.3, 1))
                        itemIcon(ItemStack(Items.id("book"), 1), x + s, y + s, 16 * s, counts: false)
                    } else if id >= RecipeBook.base {
                        let k = book.page * RecipeBook.perPage + id - RecipeBook.base
                        guard k < book.list.count else { continue }
                        let r = Recipes.all[book.list[k]]
                        let ok = RecipeBook.craftable(r, pool)
                        let cb = Settings.shared.colorblind
                        rect(x, y, Float(sl.w) * s, Float(sl.h) * s, hot ? V4(0.7, 0.7, 0.8, 1) : (ok ? (cb ? V4(0.35, 0.5, 0.75, 1) : V4(0.45, 0.6, 0.45, 1)) : (cb ? V4(0.7, 0.5, 0.25, 1) : V4(0.6, 0.4, 0.4, 1))))
                        itemIcon(r.result, x + 2 * s, y + 2 * s, 16 * s)
                        if hot {
                            let name = r.result.displayName
                            rect(x - 2 * s, y - 12 * s, textWidth(name, s) + 4 * s, 11 * s, V4(0.1, 0.05, 0.15, 0.92))
                            text(name, x, y - 10 * s, s)
                        }
                    } else {
                        rect(x, y, Float(sl.w) * s, Float(sl.h) * s, hot ? V4(0.7, 0.7, 0.8, 1) : V4(0.5, 0.5, 0.55, 1))
                        let label = id == 491 ? "<" : (id == 492 ? ">" : (book.craftableOnly ? "Can" : "All"))
                        text(label, x + (Float(sl.w) * s - textWidth(label, s)) / 2, y + 3 * s, s)
                    }
                }
            }
            if let km = m as? KeyboardMenu {
                for (i, sl) in km.slots.enumerated() where i < km.keys.count {
                    let x = o.x + Float(sl.x) * s, y = o.y + Float(sl.y) * s
                    let hot = game.menuHover === sl
                    rect(x, y, Float(sl.w) * s, Float(sl.h) * s, hot ? V4(0.42, 0.55, 0.85, 1) : V4(0.45, 0.45, 0.5, 1))
                    let label = km.keys[i]
                    text(label, x + (Float(sl.w) * s - textWidth(label, s)) / 2, y + (Float(sl.h) - 7) / 2 * s, s)
                }
            }
            if let cm = m as? CommandMenu {
                // Input line with caret, the console log (newest at the bottom), then quick buttons.
                rect(o.x + 8 * s, o.y + 16 * s, 264 * s, 13 * s, V4(0, 0, 0, 1))
                rect(o.x + 9 * s, o.y + 17 * s, 262 * s, 11 * s, V4(0.08, 0.08, 0.08, 1))
                var ln = cm.line
                while textWidth(ln, s) > 254 * s && !ln.isEmpty { ln.removeFirst() }
                let caret = Int(game.clock * 2) % 2 == 0 ? "_" : ""
                text(ln + caret, o.x + 12 * s, o.y + 19 * s, s, V4(0.95, 0.95, 0.95, 1))
                rect(o.x + 8 * s, o.y + 32 * s, 264 * s, 100 * s, V4(0.12, 0.12, 0.14, 0.85))
                let log = game.commandLog.suffix(9)
                for (i, l) in log.enumerated() {
                    var t = l
                    while textWidth(t, s) > 258 * s && !t.isEmpty { t.removeLast() }
                    let c = l.hasPrefix("  ") ? V4(0.75, 0.75, 0.75, 1) : (l.hasPrefix("/") ? V4(1, 1, 0.55, 1) : V4(1, 1, 1, 1))
                    text(t, o.x + 11 * s, o.y + Float(35 + i * 11) * s, s, c)
                }
                if game.commandLog.isEmpty { text("Type /help, Tab completes names", o.x + 11 * s, o.y + 35 * s, s, V4(0.6, 0.6, 0.6, 1)) }
                for sl in cm.slots where sl.isButton {
                    guard case .button(let i) = sl.kind, i < CommandMenu.buttons.count else { continue }
                    let x = o.x + Float(sl.x) * s, y = o.y + Float(sl.y) * s
                    let hot = game.menuHover === sl
                    rect(x, y, Float(sl.w) * s, Float(sl.h) * s, hot ? V4(0.42, 0.55, 0.85, 1) : V4(0.42, 0.42, 0.46, 1))
                    let label = CommandMenu.buttons[i]
                    text(label, x + (Float(sl.w) * s - textWidth(label, s)) / 2, y + (Float(sl.h) - 7) / 2 * s, s)
                }
            }
            if let dm = m as? DeathMenu {
                text("You Died!", o.x + (Float(dm.width) * s - textWidth("You Died!", s * 2)) / 2, o.y + 8 * s, s * 2, V4(0.9, 0.2, 0.2, 1))
                text(dm.message, o.x + (Float(dm.width) * s - textWidth(dm.message, s)) / 2, o.y + 30 * s, s, V4(0.2, 0.2, 0.2, 1), shadow: false)
                let score = "Score: \(game.deathScore)"
                text(score, o.x + (Float(dm.width) * s - textWidth(score, s)) / 2, o.y + 42 * s, s, V4(0.35, 0.3, 0.1, 1), shadow: false)
                for (i, sl) in dm.slots.enumerated() {
                    let x = o.x + Float(sl.x) * s, y = o.y + Float(sl.y) * s
                    let hot = game.menuHover === sl
                    rect(x, y, Float(sl.w) * s, Float(sl.h) * s, hot ? V4(0.42, 0.55, 0.85, 1) : V4(0.42, 0.42, 0.46, 1))
                    let label = i == 0 ? "Respawn" : "Title Screen"
                    text(label, x + (Float(sl.w) * s - textWidth(label, s)) / 2, y + (Float(sl.h) - 7) / 2 * s, s)
                }
            }
            if let pm = m as? PauseMenu, pm.page == .title {
                // Title screen logo: big blocky letters with a drop shadow, plus a tagline.
                let logo = "BLOCKSMITH", ls = s * 4
                let lx = floor((W - textWidth(logo, ls)) / 2), ly = max(4 * s, o.y - 44 * s)
                text(logo, lx + ls * 0.5, ly + ls * 0.5, ls, V4(0.1, 0.1, 0.12, 1), shadow: false)
                text(logo, lx, ly, ls, V4(0.86, 0.78, 0.55, 1), shadow: false)
                let tag = "Build. Explore. Survive."
                text(tag, floor((W - textWidth(tag, s)) / 2), ly + 9 * ls, s, V4(1, 1, 0.4, 1))
            }
            if let pm = m as? PauseMenu {
                // Big labelled buttons; the controller cursor shows as the highlighted one.
                if !pm.subtitle.isEmpty {
                    text(pm.subtitle, o.x + (pw - textWidth(pm.subtitle, s)) / 2, o.y + 17 * s, s, V4(0.3, 0.3, 0.32, 1), shadow: false)
                }
                for sl in pm.slots where sl.isButton {
                    guard case .button(let i) = sl.kind, let r = pm.row(forSlot: i) else { continue }
                    let x = o.x + Float(sl.x) * s, y = o.y + Float(sl.y) * s
                    let hot = game.menuHover === sl
                    let info = r.1 == "noop"
                    rect(x, y, Float(sl.w) * s, Float(sl.h) * s, info ? V4(0.3, 0.3, 0.33, 1) : (hot ? V4(0.42, 0.55, 0.85, 1) : V4(0.42, 0.42, 0.46, 1)))
                    frame(x, y, Float(sl.w) * s, Float(sl.h) * s, s, hot ? V4(1, 1, 1, 1) : V4(0.2, 0.2, 0.22, 1))
                    let label = r.0
                    let lx = info ? x + 5 * s : x + (Float(sl.w) * s - textWidth(label, s)) / 2
                    text(label, lx, y + (Float(sl.h) - 7) / 2 * s, s)
                    if hot && PauseMenu.valueIDs.contains(r.1) {
                        // Arrows: D-pad left / right steps the setting.
                        text("<", x + 4 * s, y + (Float(sl.h) - 7) / 2 * s, s, V4(1, 1, 0.6, 1))
                        text(">", x + Float(sl.w) * s - 8 * s, y + (Float(sl.h) - 7) / 2 * s, s, V4(1, 1, 0.6, 1))
                    }
                }
                if pm.rows.count > pm.slots.count {
                    // Scroll position: dots under the list.
                    let n = pm.rows.count - pm.slots.count + 1
                    let dotY = o.y + Float(pm.slots.last.map { $0.y + $0.h + 2 } ?? 0) * s
                    let dw = min(10 * s, 200 * s / Float(n))
                    let x0 = o.x + (pw - dw * Float(n)) / 2
                    for k in 0..<n { rect(x0 + Float(k) * dw + s, dotY, dw - 2 * s, 2 * s, k == pm.scroll ? V4(0.2, 0.3, 0.6, 1) : V4(0.5, 0.5, 0.52, 1)) }
                }
                var help = pm.helpText
                while !help.isEmpty && textWidth(help, s) > pw - 12 * s { help.removeLast() }
                if !help.isEmpty { text(help, o.x + (pw - textWidth(help, s)) / 2, o.y + ph - 12 * s, s, V4(0.22, 0.22, 0.25, 1), shadow: false) }
            }
            if let am = m as? AdvancementMenu {
                // Tabs, then the checklist: done ones in gold (challenges purple), open ones grey.
                for sl in am.slots where sl.isButton {
                    guard case .button(let i) = sl.kind else { continue }
                    let x = o.x + Float(sl.x) * s, y = o.y + Float(sl.y) * s
                    let label = i < 100 ? Advancements.tabs[i] : (i == 100 ? "^" : "v")
                    let sel = i == am.tab
                    rect(x, y, Float(sl.w) * s, Float(sl.h) * s, sel ? V4(0.35, 0.55, 0.35, 1) : (game.menuHover === sl ? V4(0.7, 0.7, 0.8, 1) : V4(0.5, 0.5, 0.55, 1)))
                    let ts = min(s, (Float(sl.w) - 4) * s / max(1, textWidth(label, 1)))
                    text(label, x + (Float(sl.w) * s - textWidth(label, ts)) / 2, y + (Float(sl.h) * s - 7 * ts) / 2, ts)
                }
                let list = am.list
                let done = list.filter { game.advancements.contains($0.id) }.count
                text("\(done)/\(list.count) done  (\(game.advancements.count)/\(Advancements.all.count) total)", o.x + 8 * s, o.y + 34 * s, s, titleC, shadow: false)
                for (row, a) in list.dropFirst(am.scroll).prefix(AdvancementMenu.rows).enumerated() {
                    let y = o.y + Float(48 + row * 15) * s
                    let got = game.advancements.contains(a.id)
                    rect(o.x + 6 * s, y - 2 * s, 226 * s, 14 * s, got ? (a.challenge ? V4(0.45, 0.25, 0.55, 1) : V4(0.55, 0.45, 0.15, 1)) : V4(0.3, 0.3, 0.33, 1))
                    text((got ? "+ " : "- ") + a.title, o.x + 9 * s, y + s, s, got ? V4(1, 1, 0.8, 1) : V4(0.75, 0.75, 0.75, 1))
                    let d = a.desc
                    let maxW = 226 * s - textWidth("+ " + a.title, s) - 16 * s
                    if textWidth(d, s * 0.75) <= maxW { text(d, o.x + 232 * s - textWidth(d, s * 0.75), y + 2 * s, s * 0.75, V4(0.85, 0.85, 0.85, 1)) }
                }
            }
            if let lm = m as? LoomMenu {
                // Pattern choices previewed on the banner's colour with the dye's colour.
                rect(o.x + 59 * s, o.y + 12 * s, 58 * s, 58 * s, V4(0.35, 0.35, 0.35, 1))
                let base = lm.box[0].def.block.map { Blocks.shape[Int($0)] == "banner" ? Banners.baseColor($0) : 0 } ?? 0
                let dye = Banners.colorIndex(ofDye: Items.key(lm.box[1].item)) ?? 15
                let opts = lm.options
                for sl in lm.slots where sl.isButton {
                    guard case .button(let i) = sl.kind else { continue }
                    let x = o.x + Float(sl.x) * s, y = o.y + Float(sl.y) * s
                    if i >= 100 {
                        rect(x, y, 12 * s, 12 * s, game.menuHover === sl ? V4(0.7, 0.7, 0.75, 1) : V4(0.5, 0.5, 0.55, 1))
                        text(i == 100 ? "^" : "v", x + 3 * s, y + 2 * s, s)
                        continue
                    }
                    let idx = lm.scroll + i
                    guard idx < opts.count else { continue }
                    rect(x, y, 14 * s, 14 * s, opts[idx] == lm.selected ? V4(0.55, 0.75, 0.55, 1) : (game.menuHover === sl ? V4(0.7, 0.7, 0.7, 1) : V4(0.55, 0.55, 0.55, 1)))
                    bannerArt(base, [Banners.encode(opts[idx], dye)], x + 3.5 * s, y + 1 * s, 7 * s, 12 * s)
                }
                if !lm.out[0].isEmpty {
                    bannerArt(base, lm.out[0].pat ?? [], o.x + 140 * s, o.y + 8 * s, 14 * s, 28 * s)
                }
            }
            if let sc = m as? StonecutterMenu {
                rect(o.x + 50 * s, o.y + 13 * s, 68 * s, 56 * s, V4(0.35, 0.35, 0.35, 1))
                for (i, opt) in sc.options.enumerated() {
                    let sl = sc.slots[1 + i]
                    let x = o.x + Float(sl.x) * s, y = o.y + Float(sl.y) * s
                    rect(x, y, 16 * s, 18 * s, i == sc.selected ? V4(0.55, 0.75, 0.55, 1) : (game.menuHover === sl ? V4(0.7, 0.7, 0.7, 1) : V4(0.55, 0.55, 0.55, 1)))
                    itemIcon(ItemStack(opt.0, opt.1), x, y + s, 16 * s)
                }
            }
            if m is SmithingMenu || m is GrindstoneMenu {
                rect(o.x + (m is SmithingMenu ? 68 : 94) * s, o.y + (m is SmithingMenu ? 50 : 36) * s, 22 * s, 6 * s, V4(0.55, 0.55, 0.55, 1))
            }
            if let bm = m as? BeaconMenu {
                // Power buttons with effect icons; locked ones dimmed; the chosen ones outlined.
                text("Primary Power", o.x + 40 * s, o.y + 8 * s, s, titleC, shadow: false)
                text("Secondary Power", o.x + 150 * s, o.y + 8 * s, s, titleC, shadow: false)
                for sl in bm.slots where sl.isButton {
                    guard case .button(let i) = sl.kind else { continue }
                    let x = o.x + Float(sl.x) * s, y = o.y + Float(sl.y) * s
                    let ok = i == 7 ? !bm.pay[0].isEmpty && bm.primary != nil : bm.available(i)
                    let chosen = (i < 5 && bm.primary == BeaconMenu.primaryButtons[i].0) || (i == 5 && bm.secondary == .regeneration)
                        || (i == 6 && bm.secondary != nil && bm.secondary == bm.primary)
                    rect(x, y, 22 * s, 22 * s, chosen ? V4(0.3, 0.8, 0.3, 1) : V4(0.2, 0.2, 0.2, 1))
                    rect(x + s, y + s, 20 * s, 20 * s, ok ? (game.menuHover === sl ? V4(0.6, 0.6, 0.75, 1) : V4(0.45, 0.45, 0.55, 1)) : V4(0.3, 0.3, 0.3, 1))
                    let e: Effect? = i < 5 ? BeaconMenu.primaryButtons[i].0 : (i == 5 ? .regeneration : (i == 6 ? bm.primary : nil))
                    if let e = e {
                        quad([V2(x + 3 * s, y + 3 * s), V2(x + 19 * s, y + 3 * s), V2(x + 19 * s, y + 19 * s), V2(x + 3 * s, y + 19 * s)],
                             [V2(0, 0), V2(1, 0), V2(1, 1), V2(0, 1)], ok ? V4(1, 1, 1, 1) : V4(0.4, 0.4, 0.4, 1), Float(Tex.id("effect_" + e.key)))
                        if i == 6 { text("II", x + 13 * s, y + 13 * s, s) }
                    } else {
                        text("OK", x + 5 * s, y + 7 * s, s, ok ? V4(0.5, 1, 0.13, 1) : V4(0.5, 0.5, 0.5, 1))
                    }
                }
                text("Layers: \(bm.be.level)", o.x + 12 * s, o.y + 112 * s, s, titleC, shadow: false)
            }
            if let mm = m as? MerchantMenu {
                // Offer list: cost (and second cost) -> result; used-up offers are crossed out.
                let offers = mm.offers
                for i in 0..<MerchantMenu.visible {
                    let idx = mm.scroll + i
                    guard idx < offers.count else { break }
                    let of = offers[idx]
                    let x: Float = 4, y = o.y + Float(17 + 20 * i) * s
                    let sel = idx == mm.selected, hov = game.menuHover === mm.slots[i]
                    rect(o.x + x * s, y, 88 * s, 20 * s, V4(0.2, 0.2, 0.2, 1))
                    rect(o.x + (x + 1) * s, y + s, 86 * s, 18 * s, sel ? V4(0.62, 0.62, 0.7, 1) : (hov ? V4(0.7, 0.7, 0.7, 1) : V4(0.55, 0.55, 0.55, 1)))
                    let price = mm.price(of)
                    itemIcon(price, o.x + (x + 3) * s, y + 2 * s, 16 * s)
                    if price.count != of.buyA.count && !of.disabled {
                        text("\(of.buyA.count)", o.x + (x + 3) * s, y + 1 * s, s * 0.8, V4(1, 0.4, 0.4, 1))
                    }
                    if !of.buyB.isEmpty { itemIcon(of.buyB, o.x + (x + 30) * s, y + 2 * s, 16 * s) }
                    text(">", o.x + (x + 52) * s, y + 6 * s, s, of.disabled ? V4(0.8, 0.2, 0.2, 1) : V4(1, 1, 1, 1))
                    itemIcon(of.sell, o.x + (x + 64) * s, y + 2 * s, 16 * s)
                    if of.disabled { rect(o.x + (x + 1) * s, y + 9 * s, 86 * s, 2 * s, V4(0.8, 0.15, 0.15, 0.9)) }
                }
                // Level name and XP bar.
                if let v = mm.mob?.villager {
                    let lvl = max(1, min(5, v.level))
                    let t = Villagers.levelNames[lvl - 1]
                    text(t, o.x + 150 * s, o.y + 6 * s, s, titleC, shadow: false)
                    let lo = Villagers.levelXP[lvl - 1], hi = lvl < 5 ? Villagers.levelXP[lvl] : lo + 1
                    let f = lvl < 5 ? Float(v.xp - lo) / Float(max(1, hi - lo)) : 1
                    rect(o.x + 136 * s, o.y + 16 * s, 102 * s, 5 * s, V4(0.2, 0.2, 0.2, 1))
                    rect(o.x + 137 * s, o.y + 17 * s, 100 * s * max(0, min(1, f)), 3 * s, V4(0.5, 1, 0.13, 1))
                }
                rect(o.x + 186 * s, o.y + 40 * s, 22 * s, 6 * s, V4(0.55, 0.55, 0.55, 1))
            }
            for sl in m.slots where !sl.isButton {
                let x = o.x + Float(sl.x - 1) * s, y = o.y + Float(sl.y - 1) * s
                let bigSlot = (m is CraftingTableMenu || m is FurnaceMenu || m is AnvilMenu || m is SmithingMenu || m is StonecutterMenu || m is GrindstoneMenu) && { if case .result = sl.kind { return true } else if case .output = sl.kind { return true } else { return false } }()
                let big: Float = bigSlot ? 4 : 0
                let bx = x - big * s, by = y - big * s, bs = (18 + 2 * big) * s
                rect(bx, by, bs, bs, V4(0.216, 0.216, 0.216, 1))
                rect(bx + s, by + s, bs - s, bs - s, V4(1, 1, 1, 1))
                rect(bx + s, by + s, bs - 2 * s, bs - 2 * s, V4(0.545, 0.545, 0.545, 1))
                itemIcon(sl.stack, x + s, y + s, 16 * s)
                if sl === game.menuHover {
                    rect(x + s, y + s, 16 * s, 16 * s, V4(1, 1, 1, 0.45))
                    // Controller cursor: a bright frame that reads from the sofa.
                    if Prompt.pad { frame(bx - s, by - s, bs + 2 * s, bs + 2 * s, s, V4(1, 0.85, 0.2, 1)) }
                }
            }
            if let c = m as? CreativeMenu {
                // Tab strip: an item icon per category; the open tab is raised and lighter.
                for sl in c.slots where sl.isButton {
                    guard case .button(let i) = sl.kind, let t = CreativeMenu.Tab(rawValue: i - CreativeMenu.tabButton) else { continue }
                    let x = o.x + Float(sl.x) * s, y = o.y + Float(sl.y) * s
                    let sel = t == c.tab, hot = game.menuHover === sl
                    rect(x, y - (sel ? s : 0), Float(sl.w) * s, Float(sl.h) * s + (sel ? s : 0), V4(0.2, 0.2, 0.2, 1))
                    rect(x + s, y + s - (sel ? s : 0), Float(sl.w - 2) * s, Float(sl.h - 2) * s + (sel ? s : 0),
                         sel ? V4(0.93, 0.93, 0.93, 1) : (hot ? V4(0.7, 0.72, 0.85, 1) : V4(0.6, 0.6, 0.62, 1)))
                    if Items.has(t.icon) { itemIcon(ItemStack(Items.id(t.icon), 1), x + 3 * s, y + s, 14 * s, counts: false) }
                    else { text(String(t.short.prefix(2)), x + 4 * s, y + 5 * s, s, V4(0.2, 0.2, 0.2, 1), shadow: false) }
                }
                if let h = game.menuHover, case .button(let i) = h.kind, let t = CreativeMenu.Tab(rawValue: i - CreativeMenu.tabButton) {
                    let name = t.name, x = o.x + Float(h.x) * s, y = o.y + Float(h.y) * s
                    rect(x - 2 * s, y - 12 * s, textWidth(name, s) + 4 * s, 11 * s, V4(0.1, 0.05, 0.15, 0.92))
                    text(name, x, y - 10 * s, s)
                }
            }
            if let c = m as? CreativeMenu, c.maxScroll > 0 {
                let tx = o.x + 175 * s, ty = o.y + 32 * s, th = 90 * s
                rect(tx, ty, 12 * s, th, V4(0.216, 0.216, 0.216, 1))
                let k = Float(c.scroll) / Float(c.maxScroll)
                rect(tx + s, ty + (th - 15 * s) * k, 10 * s, 15 * s, V4(0.8, 0.8, 0.8, 1))
            }
            // Cursor stack follows the mouse, or the controller's hovered slot.
            var cursorPos = V2(game.input.mouseX, game.input.mouseY)
            if cursorPos.x < 0, let h = game.menuHover { cursorPos = o + V2(Float(h.x + 8), Float(h.y + 8)) * s }
            if !game.carried.isEmpty { itemIcon(game.carried, cursorPos.x - 8 * s, cursorPos.y - 8 * s, 16 * s) }
            else if let h = game.menuHover, !h.stack.isEmpty {
                let st = h.stack
                var lines: [(String, V4)] = [(st.displayName, st.ench != 0 ? V4(0.33, 1, 1, 1) : (st.label != nil ? V4(1, 1, 1, 1) : V4(1, 1, 1, 1)))]
                for (e, l) in Enchant.list(st) {
                    lines.append((Enchant.displayLine(e, l), Enchant.def(e).curse ? V4(1, 0.33, 0.33, 1) : V4(0.67, 0.67, 0.67, 1)))
                }
                if case let (form, t)? = Potions.potion(of: st.item) {
                    for l in Potions.lines(form, t) {
                        let bad = t.effects.first.map { !$0.0.beneficial } ?? false
                        lines.append((l, t.effects.isEmpty ? V4(0.67, 0.67, 0.67, 1) : (bad ? V4(1, 0.33, 0.33, 1) : V4(0.33, 0.33, 1, 1))))
                    }
                }
                if let t = Smithing.trimName(st) { lines.append((t, V4(0.67, 0.67, 0.9, 1))) }
                for l in Fireworks.tooltip(st) { lines.append((l, V4(0.67, 0.67, 0.67, 1))) }
                if st.def.name == "ominous_bottle" { lines.append(("Ill Omen " + Effect.roman(st.damage + 1) + " (100:00)", V4(0.33, 0.33, 1, 1))) }
                if st.def.durability > 0 && st.damage > 0 {
                    lines.append(("Durability: \(st.def.durability - st.damage) / \(st.def.durability)", V4(0.8, 0.8, 0.8, 1)))
                }
                let tw = lines.map { textWidth($0.0, s) }.max() ?? 0
                let lh = 10 * s
                let th = Float(lines.count) * lh + 3 * s
                let tx = min(cursorPos.x + 12 * s, W - tw - 6 * s), ty = cursorPos.y - 12 * s
                rect(tx - 3 * s, ty - 3 * s, tw + 6 * s, th, V4(0.063, 0, 0.063, 0.94))
                frame(tx - 2 * s, ty - 2 * s, tw + 4 * s, th - 2 * s, s, V4(0.31, 0, 1, 0.5))
                for (i, l) in lines.enumerated() { text(l.0, tx, ty + Float(i) * lh, s, l.1) }
            }
            return v
        }

        // Crosshair
        let cx = floor(W / 2), cy = floor(H / 2)
        let arm = 5 * s, th = max(1, s)
        let shadow = V4(0, 0, 0, 0.45), white = V4(1, 1, 1, 0.9)
        rect(cx - arm - 1, cy - th / 2 - 1, arm * 2 + 2, th + 2, shadow)
        rect(cx - th / 2 - 1, cy - arm - 1, th + 2, arm * 2 + 2, shadow)
        rect(cx - arm, cy - th / 2, arm * 2, th, white)
        rect(cx - th / 2, cy - arm, th, arm * 2, white)

        // Hotbar
        let total = slot * 9
        let x0 = L.hotbarX0
        let y0 = L.hotbarY0
        rect(x0 - 2 * s, y0 - 2 * s, total + 4 * s, slot + 4 * s, V4(0, 0, 0, 0.45))
        for i in 0..<9 {
            let x = x0 + Float(i) * slot
            rect(x + s, y0 + s, slot - 2 * s, slot - 2 * s, V4(0.35, 0.35, 0.38, 0.55))
            if i == game.selected { frame(x - s, y0 - s, slot + 2 * s, slot + 2 * s, 2 * s, V4(1, 1, 1, 0.95)) }
            itemIcon(game.inventory.main[i], x + 2 * s, y0 + 2 * s, slot - 4 * s)
        }

        // Survival status: XP bar + level, hearts (left), hunger (right), armor, air bubbles.
        if game.survival {
            let isz = 9 * s, step = 8 * s
            let xpY = y0 - 7 * s
            rect(x0, xpY, total, 5 * s, V4(0, 0, 0, 0.8))
            let xpFrac = Float(game.xpPoints) / Float(Game.xpToNext(game.xpLevel))
            rect(x0 + s, xpY + s, (total - 2 * s) * xpFrac, 3 * s, V4(0.5, 1, 0.13, 1))
            if game.xpLevel > 0 {
                let t = "\(game.xpLevel)"
                text(t, floor((W - textWidth(t, s)) / 2), xpY - 7 * s, s, V4(0.5, 1, 0.13, 1))
            }
            let yh = xpY - 2 * s - isz
            let uv4 = [V2(0, 0), V2(1, 0), V2(1, 1), V2(0, 1)]
            func sprite(_ layer: Int, _ x: Float, _ y: Float) {
                quad([V2(x, y), V2(x + isz, y), V2(x + isz, y + isz), V2(x, y + isz)], uv4, V4(1, 1, 1, 1), Float(layer))
            }
            // Hearts: rows of ten (health boost adds rows), then golden absorption hearts; poison/blight tint them.
            let heartKind = game.effects.has(.wither) ? "wither" : (game.effects.has(.poison) ? "poison" : "")
            let fullH = heartKind.isEmpty ? HudTex.heart : Int(Tex.id("heart_" + heartKind))
            let halfH = heartKind.isEmpty ? HudTex.heartHalf : Int(Tex.id("heart_\(heartKind)_half"))
            let slotsH = (game.maxHealth + 1) / 2
            let absorb = Int(game.absorption.rounded(.up))
            let totalHearts = slotsH + (absorb + 1) / 2
            let rows = (totalHearts + 9) / 10
            let rowStep = max(3 * s, 10 * s - Float(rows - 2) * s)
            func heartSprite(_ layer: Int, _ x: Float, _ y: Float, _ c: V4) {
                quad([V2(x, y), V2(x + isz, y), V2(x + isz, y + isz), V2(x, y + isz)], uv4, c, Float(layer))
            }
            for i in 0..<totalHearts {
                let x = x0 + Float(i % 10) * step, y = yh - Float(i / 10) * rowStep
                if i < slotsH {
                    let h = game.health - i * 2
                    heartSprite(h >= 2 ? fullH : (h == 1 ? halfH : HudTex.heartEmpty), x, y, V4(1, 1, 1, 1))
                } else {
                    let a = absorb - (i - slotsH) * 2
                    heartSprite(Int(Tex.id(a >= 2 ? "heart_gold" : "heart_gold_half")), x, y, V4(1, 1, 1, 1))
                }
            }
            let hungerTint: V4 = game.effects.has(.hunger) ? V4(0.6, 0.8, 0.4, 1) : V4(1, 1, 1, 1)
            for i in 0..<10 {
                let f = game.hunger - i * 2
                heartSprite(f >= 2 ? HudTex.food : (f == 1 ? HudTex.foodHalf : HudTex.foodEmpty), x0 + total - isz - Float(i) * step, yh, hungerTint)
            }
            let armorY = yh - Float(rows - 1) * rowStep - step - s
            let ap = game.inventory.armorPoints
            if ap > 0 {
                for i in 0..<10 {
                    let a = ap - i * 2
                    sprite(a >= 2 ? HudTex.armor : (a == 1 ? HudTex.armorHalf : HudTex.armorEmpty), x0 + Float(i) * step, armorY)
                }
            }
            if game.air < 15 {
                let b = Int(ceilf(game.air / 1.5))
                for i in 0..<b { sprite(HudTex.bubble, x0 + total - isz - Float(i) * step, yh - step - s) }
            }
        }

        // Active effects: icons in the top-right corner (beneficial row, then harmful), blinking near the hollow.
        if game.effects.any {
            var good = 0, bad = 0
            for (e, a) in game.effects.active {
                let row = e.beneficial ? 0 : 1
                let idx = e.beneficial ? good : bad
                if e.beneficial { good += 1 } else { bad += 1 }
                let bx = W - L.insetX - Float(idx + 1) * 25 * s - 2 * s, by = L.insetY + 2 * s + Float(row) * 26 * s
                let blink = a.time < 10 && Int(a.time * 4) % 2 == 0
                rect(bx, by, 24 * s, 24 * s, V4(0.1, 0.1, 0.15, a.ambient ? 0.55 : 0.75))
                frame(bx, by, 24 * s, 24 * s, s, a.ambient ? V4(0.3, 0.8, 0.9, 0.9) : V4(0.55, 0.55, 0.6, 0.9))
                if !blink {
                    quad([V2(bx + 3 * s, by + 3 * s), V2(bx + 21 * s, by + 3 * s), V2(bx + 21 * s, by + 21 * s), V2(bx + 3 * s, by + 21 * s)],
                         [V2(0, 0), V2(1, 0), V2(1, 1), V2(0, 1)], V4(1, 1, 1, 1), Float(Tex.id("effect_" + e.key)))
                }
                if a.amp > 0 { text(Effect.roman(a.amp + 1), bx + 14 * s, by + 15 * s, s) }
            }
        }

        // Freezing in powder snow: frosted screen edges.
        if game.freeze > 0 {
            let a = min(1, game.freeze / 7) * 0.55
            let e = min(W, H) * 0.12
            rect(0, 0, W, e, V4(0.85, 0.93, 1, a)); rect(0, H - e, W, e, V4(0.85, 0.93, 1, a))
            rect(0, e, e, H - 2 * e, V4(0.85, 0.93, 1, a)); rect(W - e, e, e, H - 2 * e, V4(0.85, 0.93, 1, a))
        }
        // Spyglass: black outside the lens circle.
        if game.fovScale < 0.5 && Items.key(game.held.item) == "spyglass" {
            for r in Renderer.scopeRects(W: W, H: H) where r.2 > 0 && r.3 > 0 { rect(r.0, r.1, r.2, r.3, V4(0, 0, 0, 1)) }
        }
        // A held filled map is drawn above the hotbar.
        if Items.key(game.held.item) == "filled_map", let md = game.maps[game.held.tag] {
            let px = max(1, floor(s)), size = 128 * px
            let mx = floor((W - size) / 2), my = L.hotbarY0 - size - 34 * s
            rect(mx - 6 * s, my - 6 * s, size + 12 * s, size + 12 * s, V4(0.86, 0.8, 0.62, 1))
            rect(mx, my, size, size, V4(0.78, 0.72, 0.55, 1))
            for z in 0..<128 {
                var x = 0
                while x < 128 {
                    let c = md.colors[x + z * 128]
                    var e = x + 1
                    while e < 128 && md.colors[e + z * 128] == c { e += 1 }
                    if c != 0 {
                        rect(mx + Float(x) * px, my + Float(z) * px, Float(e - x) * px, px,
                             V4(Float((c >> 16) & 255) / 255, Float((c >> 8) & 255) / 255, Float(c & 255) / 255, 1))
                    }
                    x = e
                }
            }
            // The player marker.
            let per = Float(1 << md.scale)
            let ppx = (game.player.pos.x - Float(md.cx)) / per + 64, ppz = (game.player.pos.z - Float(md.cz)) / per + 64
            if ppx >= 0 && ppx < 128 && ppz >= 0 && ppz < 128 {
                rect(mx + ppx * px - 2 * px, my + ppz * px - 2 * px, 4 * px, 4 * px, V4(1, 1, 1, 1))
                rect(mx + ppx * px - px, my + ppz * px - px, 2 * px, 2 * px, V4(0.1, 0.1, 0.1, 1))
            }
        }

        // Advancement toasts (top right, 5 s each, one at a time).
        if let first = game.advToasts.first {
            let age = game.clock - first.2
            if age > 5 { game.advToasts.removeFirst(); if let n = game.advToasts.first { game.advToasts[0].2 = game.clock; _ = n } }
            else {
                let tw = 160 * s, th = 32 * s
                let slide = Float(min(1, min(age, 5 - age) * 4))
                let x = W - L.insetX - tw * slide - 4 * s, y = L.insetY + 4 * s
                rect(x, y, tw, th, V4(0.13, 0.13, 0.15, 0.95))
                frame(x, y, tw, th, s, first.1 ? V4(0.75, 0.45, 0.95, 1) : V4(0.95, 0.8, 0.3, 1))
                text(first.1 ? "Challenge Complete!" : "Advancement Made!", x + 8 * s, y + 6 * s, s, first.1 ? V4(0.9, 0.5, 1, 1) : V4(1, 1, 0.33, 1))
                text(first.0, x + 8 * s, y + 18 * s, s)
            }
        }
        // Toast (item names, messages) above the hotbar, fading out.
        let since = game.clock - game.toastTime
        if since < 2.2 && !game.toastText.isEmpty {
            let a = Float(min(1, (2.2 - since) / 0.5))
            let ty = L.hotbarY0 - (game.survival ? 26 : 14) * s
            let tb = Settings.shared.textBackground
            if tb > 0 { let tw = textWidth(game.toastText, s); rect(floor((W - tw) / 2) - 3 * s, ty - 3 * s, tw + 6 * s, 13 * s, V4(0, 0, 0, tb * a)) }
            text(game.toastText, floor((W - textWidth(game.toastText, s)) / 2), ty, s, V4(1, 1, 1, a))
        }

        // Tutorial tips, contextual button prompts and subtitles (HudExtras.swift).
        for l in HudExtras.lines(game, L) {
            if let b = l.bg {
                if let box = l.box { rect(l.x, l.y, box.x, box.y, b) }
                else { rect(l.x - 3 * l.scale, l.y - 3 * l.scale, textWidth(l.text, l.scale) + 6 * l.scale, 13 * l.scale, b) }
            }
            if !l.text.isEmpty { text(l.text, l.x, l.y, l.scale, l.color) }
        }

        // F3 debug overlay
        if game.showDebug {
            var y = L.insetY + 4 * s
            for line in debugLines() {
                rect(L.insetX + 2 * s, y - s, textWidth(line, s) + 4 * s, 9 * s, V4(0, 0, 0, 0.35))
                text(line, L.insetX + 4 * s, y, s, V4(0.9, 0.9, 0.9, 1), shadow: false)
                y += 10 * s
            }
        }
        return v
    }

    func debugLines() -> [String] {
        let p = game.player
        let w = game.world
        let bx = Int(floor(p.pos.x)), by = Int(floor(p.pos.y)), bz = Int(floor(p.pos.z))
        let biome = w.gen.column(bx, bz).biome
        let facing = ["north (-Z)", "west (-X)", "south (+Z)", "east (+X)"][Int((p.yaw / (.pi / 2)).rounded()).mod4]
        var tgt = "none"
        if let t = game.target { tgt = "\(Blocks.name(w.block(t.hit.x, t.hit.y, t.hit.z))) @ \(t.hit.x) \(t.hit.y - YOFF) \(t.hit.z)" }
        let hour = Int(game.dayFraction * 24 + 6) % 24
        let l = w.lightAt(bx, by, bz)
        return [
            "Blocksmith  \(Int(fps.rounded())) fps  seed \(w.seed)",
            String(format: "XYZ %.2f / %.2f / %.2f", p.pos.x, p.pos.y - Float(YOFF), p.pos.z),
            "Block \(bx) \(by - YOFF) \(bz)  Chunk \(floorDiv(bx, CS)) \(floorDiv(bz, CS))  Facing \(facing)",
            "Biome \(biome.displayName)  Light sky \(l.sky) block \(l.block)",
            "Chunks \(w.chunks.count) loaded, \(w.meshedCount) meshed, \(drawnChunks) drawn, \(w.pendingJobs) jobs, RD \(w.renderDistance)",
            "Target \(tgt)",
            "\(p.flying ? "flying" : (p.onGround ? "on ground" : "in air"))\(p.inWater ? ", in water" : "")  Time \(String(format: "%02d:00", hour))  Controller \(game.padConnected ? "yes" : "no")",
            "Mobs \(game.mobs.mobs.count)  Fluid queue \(w.fluidPending.count)",
        ]
    }

    // Isometric block icon from three textured faces (grass/leaves tinted with default biome colours).
    func icon(_ id: BlockID, center c: V2, size sz: Float, _ quad: ([V2], [V2], V4, Float) -> Void) {
        let tex = Blocks.tex
        let uv = [V2(0, 0), V2(1, 0), V2(1, 1), V2(0, 1)]
        let tintMode = Blocks.tint[Int(id)]
        let grassC = V4(0.57, 0.74, 0.35, 1), leafC = V4(0.47, 0.67, 0.18, 1)
        let full: V4 = tintMode == 1 ? grassC : (tintMode == 2 ? leafC : V4(1, 1, 1, 1))
        if Blocks.flatIcon(id) {
            let h = sz * 0.55
            quad([V2(c.x - h, c.y - h), V2(c.x + h, c.y - h), V2(c.x + h, c.y + h), V2(c.x - h, c.y + h)], uv, full, Float(tex[Int(id) * 6]))
            return
        }
        let top = Float(tex[Int(id) * 6 + 2]), left = Float(tex[Int(id) * 6 + 4]), right = Float(tex[Int(id) * 6 + 0])
        let hx = sz * 0.5, hy = sz * 0.25, vh = sz * 0.55
        let t = V2(c.x, c.y - hy - vh / 2 + hy)
        let n = V2(c.x, t.y - hy), e = V2(c.x + hx, t.y), s = V2(c.x, t.y + hy), w = V2(c.x - hx, t.y)
        let topC = tintMode == 3 ? grassC : full
        quad([n, e, s, w], uv, topC, top)
        quad([w, s, s + V2(0, vh), w + V2(0, vh)], uv, full * V4(0.78, 0.78, 0.78, 1), left)
        quad([s, e, e + V2(0, vh), s + V2(0, vh)], uv, full * V4(0.6, 0.6, 0.6, 1), right)
    }

    // MARK: Headless snapshot

    // Harness timing: median of n offscreen frames (encode + GPU), no readback.
    func medianFrame(_ n: Int, width: Int, height: Int) -> Double {
        let cd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        cd.usage = [.renderTarget]; cd.storageMode = .private
        let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
        dd.usage = .renderTarget; dd.storageMode = .private
        guard let color = device.makeTexture(descriptor: cd), let depth = device.makeTexture(descriptor: dd) else { return 0 }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = color
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .dontCare
        rpd.depthAttachment.texture = depth
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .dontCare
        rpd.depthAttachment.clearDepth = 1
        var times: [Double] = []
        for _ in 0..<n {
            let t0 = CFAbsoluteTimeGetCurrent()
            let cmd = queue.makeCommandBuffer()!
            let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)!
            encode(enc, width: Float(width), height: Float(height))
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            times.append(CFAbsoluteTimeGetCurrent() - t0)
        }
        times.sort()
        return times.isEmpty ? 0 : times[times.count / 2]
    }

    func renderToPNG(path: String, width: Int, height: Int) -> Double {
        let cd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        cd.usage = [.renderTarget, .shaderRead]
        cd.storageMode = .managed
        let color = device.makeTexture(descriptor: cd)!
        let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
        dd.usage = .renderTarget
        dd.storageMode = .private
        let depth = device.makeTexture(descriptor: dd)!

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = color
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        let sky = game.blindFog != nil ? V3(0, 0, 0) : (game.player.headInWater ? V3(0.05, 0.12, 0.3) : game.skyColor)
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: Double(sky.x), green: Double(sky.y), blue: Double(sky.z), alpha: 1)
        rpd.depthAttachment.texture = depth
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .dontCare
        rpd.depthAttachment.clearDepth = 1

        let t0 = CFAbsoluteTimeGetCurrent()
        let cmd = queue.makeCommandBuffer()!
        let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)!
        encode(enc, width: Float(width), height: Float(height))
        enc.endEncoding()
        let blit = cmd.makeBlitCommandEncoder()!
        blit.synchronize(resource: color)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        let t1 = CFAbsoluteTimeGetCurrent()
        if let err = cmd.error { print("GPU error: \(err)") }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        color.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let img = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                space: cs, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { print("PNG encode failed"); return t1 - t0 }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        return t1 - t0
    }
}
