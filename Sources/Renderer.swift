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

let CLOUD_Y: Float = 158

final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let game: Game
    let chunkPipe: MTLRenderPipelineState
    let waterPipe: MTLRenderPipelineState
    let simplePipe: MTLRenderPipelineState
    let hudPipe: MTLRenderPipelineState
    let starPipe: MTLRenderPipelineState
    let cloudPipe: MTLRenderPipelineState
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
    private let ringSize = 1 << 20
    private var frame = 0
    private var lastTime = CACurrentMediaTime()
    var drawHUD = true

    // Stats
    private(set) var fps: Double = 0
    private var fpsFrames = 0
    private var fpsTime: Double = 0
    private(set) var drawnChunks = 0
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
        waterPipe = try pipe("chunkVS", "waterFS", blend: true)
        simplePipe = try pipe("simpleVS", "simpleFS", blend: true)
        hudPipe = try pipe("hudVS", "hudFS", blend: true)
        starPipe = try pipe("starVS", "simpleFS", blend: true)
        cloudPipe = try pipe("cloudVS", "cloudFS", blend: true)

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
        let td = MTLTextureDescriptor()
        td.textureType = .type2DArray
        td.pixelFormat = .rgba8Unorm
        td.width = TextureGen.S
        td.height = TextureGen.S
        td.arrayLength = T.count
        td.mipmapLevelCount = levels.count
        td.usage = .shaderRead
        let tex = device.makeTexture(descriptor: td)!
        var size = TextureGen.S
        for (lvl, data) in levels.enumerated() {
            let bytesPerImage = size * size * 4
            data.withUnsafeBytes { raw in
                for layer in 0..<T.count {
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
        let cmd = queue.makeCommandBuffer()!
        cmd.addCompletedHandler { [inflight] _ in inflight.signal() }
        let sky = game.skyColor
        let clear = game.player.headInWater ? V3(0.05, 0.12, 0.3) : sky
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
        let eye = p.eye
        let rd = Float(game.world.renderDistance)
        let underwater = p.headInWater
        let far = rd * 16 + 96
        let proj = perspectiveRH(fovy: 70 * .pi / 180, aspect: W / max(H, 1), near: 0.05, far: far)
        let viewRot = rotationX(-p.pitch) * rotationY(-p.yaw)
        let viewProj = proj * viewRot
        let frustum = Frustum(viewProj * translationMatrix(-eye))

        let sky = game.skyColor
        let fogEnd: Float = underwater ? 20 : rd * 16 - 6
        let fogStart: Float = underwater ? 1 : fogEnd * 0.62
        let fogColor = underwater ? V3(0.05, 0.12, 0.3) : sky
        let daylight = game.daylight
        var u = Uniforms(viewProj: viewProj,
                         fogColor: V4(fogColor, fogStart),
                         params: V4(fogEnd, daylight, Float(game.time.truncatingRemainder(dividingBy: 1000)), underwater ? 1 : 0),
                         sunDir: V4(game.sunDir, 0))

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
            if !underwater {
                body(sd, 7, V4(1.0, 0.95, 0.75, 1))
                body(sd, 11, V4(1.0, 0.85, 0.5, 0.18))
                body(-sd, 5, V4(0.85, 0.88, 0.95, 1))
            }
            let starAlpha = simd_clamp((0.6 - daylight) / 0.35, 0, 1)
            if !underwater && starAlpha > 0 {
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

        // Visible chunks, near to far
        let pcx = floorDiv(Int(floor(eye.x)), CS), pcz = floorDiv(Int(floor(eye.z)), CS)
        var visible: [(Chunk, Float)] = []
        visible.reserveCapacity(game.world.chunks.count)
        for (_, c) in game.world.chunks where c.meshedVersion >= 0 && (c.opaqueQuads > 0 || c.waterQuads > 0) {
            let dx = c.cx - pcx, dz = c.cz - pcz
            if !game.world.inMeshRadius(dx, dz) { continue }
            let mn = V3(Float(c.cx * CS), c.minY, Float(c.cz * CS))
            let mx = V3(Float(c.cx * CS + CS), c.maxY, Float(c.cz * CS + CS))
            if !frustum.visible(min: mn, max: mx) { continue }
            let center = (mn + mx) * 0.5 - eye
            visible.append((c, simd_length_squared(V2(center.x, center.z))))
        }
        visible.sort { $0.1 < $1.1 }
        drawnChunks = visible.count

        func offset(_ c: Chunk) -> V4 { V4(Float(c.cx * CS) - eye.x, -eye.y, Float(c.cz * CS) - eye.z, 0) }

        enc.setRenderPipelineState(chunkPipe)
        enc.setDepthStencilState(depthWrite)
        enc.setCullMode(.back)
        enc.setFrontFacing(.counterClockwise)
        enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        for (c, _) in visible where c.opaqueQuads > 0 {
            guard let buf = c.opaqueBuf else { continue }
            var o = offset(c)
            enc.setVertexBuffer(buf, offset: 0, index: 0)
            enc.setVertexBytes(&o, length: 16, index: 2)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: min(c.opaqueQuads, Renderer.maxQuads) * 6,
                                      indexType: .uint32, indexBuffer: quadIndices, indexBufferOffset: 0)
        }

        // Target block outline
        if let t = game.target {
            let e: Float = 0.003
            let o = V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) - eye
            let a = o - V3(repeating: e), b = o + V3(repeating: 1 + e)
            let cs = [V3(a.x, a.y, a.z), V3(b.x, a.y, a.z), V3(b.x, a.y, b.z), V3(a.x, a.y, b.z),
                      V3(a.x, b.y, a.z), V3(b.x, b.y, a.z), V3(b.x, b.y, b.z), V3(a.x, b.y, b.z)]
            let edges = [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
            let col = V4(0, 0, 0, 0.7)
            let verts = edges.map { SimpleVert(pos: V4(cs[$0], 1), color: col) }
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
        for (c, _) in visible.reversed() where c.waterQuads > 0 {
            guard let buf = c.waterBuf else { continue }
            var o = offset(c)
            enc.setVertexBuffer(buf, offset: 0, index: 0)
            enc.setVertexBytes(&o, length: 16, index: 2)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: min(c.waterQuads, Renderer.maxQuads) * 6,
                                      indexType: .uint32, indexBuffer: quadIndices, indexBufferOffset: 0)
        }

        // Cloud layer (after water so both blend over terrain; depth-tested against terrain).
        if !underwater {
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

        if drawHUD, let off = push(buildHUD(W, H)) {
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

        if game.player.headInWater { rect(0, 0, W, H, V4(0.05, 0.15, 0.45, 0.35)) }
        if game.hurtFlash > 0 { rect(0, 0, W, H, V4(0.75, 0.02, 0.02, min(0.45, game.hurtFlash * 1.3))) }

        func frame(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ b: Float, _ c: V4) {
            rect(x, y, w, b, c)
            rect(x, y + h - b, w, b, c)
            rect(x, y, b, h, c)
            rect(x + w - b, y, b, h, c)
        }
        let slot = L.slot

        if game.inventoryOpen {
            // Creative inventory: dimmed world, panel with every placeable block, highlighted cursor.
            let items = game.inventoryItems
            let n = items.count
            let o = L.gridOrigin(n)
            let gw = slot * Float(HudLayout.cols), gh = slot * Float(L.gridRows(n))
            rect(0, 0, W, H, V4(0, 0, 0, 0.4))
            rect(o.x - 6 * s, o.y - 6 * s, gw + 12 * s, gh + 12 * s, V4(0.1, 0.1, 0.12, 0.88))
            frame(o.x - 6 * s, o.y - 6 * s, gw + 12 * s, gh + 12 * s, s, V4(0.55, 0.55, 0.6, 0.9))
            for i in 0..<n {
                let p = L.gridSlot(i, n)
                let hi = i == game.invCursor
                rect(p.x + s, p.y + s, slot - 2 * s, slot - 2 * s, hi ? V4(0.75, 0.75, 0.8, 0.6) : V4(0.3, 0.3, 0.34, 0.6))
                icon(items[i], center: V2(p.x + slot / 2, p.y + slot / 2), size: slot * 0.62, quad)
            }
            let c = L.gridSlot(game.invCursor, n)
            frame(c.x - s, c.y - s, slot + 2 * s, slot + 2 * s, 2 * s, V4(1, 1, 1, 0.95))
        } else {
            // Crosshair
            let cx = floor(W / 2), cy = floor(H / 2)
            let arm = 5 * s, th = max(1, s)
            let shadow = V4(0, 0, 0, 0.45), white = V4(1, 1, 1, 0.9)
            rect(cx - arm - 1, cy - th / 2 - 1, arm * 2 + 2, th + 2, shadow)
            rect(cx - th / 2 - 1, cy - arm - 1, th + 2, arm * 2 + 2, shadow)
            rect(cx - arm, cy - th / 2, arm * 2, th, white)
            rect(cx - th / 2, cy - arm, th, arm * 2, white)
        }

        // Hotbar
        let total = slot * 9
        let x0 = L.hotbarX0
        let y0 = L.hotbarY0
        rect(x0 - 2 * s, y0 - 2 * s, total + 4 * s, slot + 4 * s, V4(0, 0, 0, 0.45))
        for i in 0..<9 {
            let x = x0 + Float(i) * slot
            rect(x + s, y0 + s, slot - 2 * s, slot - 2 * s, V4(0.35, 0.35, 0.38, 0.55))
            if i == game.selected {
                let b = 2 * s
                let c = V4(1, 1, 1, 0.95)
                rect(x - s, y0 - s, slot + 2 * s, b, c)
                rect(x - s, y0 + slot - b + s, slot + 2 * s, b, c)
                rect(x - s, y0 - s, b, slot + 2 * s, c)
                rect(x + slot - b + s, y0 - s, b, slot + 2 * s, c)
            }
            icon(game.hotbar[i], center: V2(x + slot / 2, y0 + slot / 2), size: slot * 0.62, quad)
        }

        // Survival status: hearts (left), hunger (right, filling right-to-left), air bubbles when submerged.
        if game.survival {
            let isz = 9 * s, step = 8 * s
            let yh = y0 - 3 * s - isz
            let uv4 = [V2(0, 0), V2(1, 0), V2(1, 1), V2(0, 1)]
            func sprite(_ layer: Int, _ x: Float, _ y: Float) {
                quad([V2(x, y), V2(x + isz, y), V2(x + isz, y + isz), V2(x, y + isz)], uv4, V4(1, 1, 1, 1), Float(layer))
            }
            for i in 0..<10 {
                let h = game.health - i * 2
                sprite(h >= 2 ? T.heart : (h == 1 ? T.heartHalf : T.heartEmpty), x0 + Float(i) * step, yh)
                let f = game.hunger - i * 2
                sprite(f >= 2 ? T.food : (f == 1 ? T.foodHalf : T.foodEmpty), x0 + total - isz - Float(i) * step, yh)
            }
            if game.air < 15 {
                let b = Int(ceilf(game.air / 1.5))
                for i in 0..<b { sprite(T.bubble, x0 + total - isz - Float(i) * step, yh - step - s) }
            }
        }
        return v
    }

    // Isometric block icon from three textured faces.
    func icon(_ id: UInt8, center c: V2, size sz: Float, _ quad: ([V2], [V2], V4, Float) -> Void) {
        let tex = Blocks.tex
        let uv = [V2(0, 0), V2(1, 0), V2(1, 1), V2(0, 1)]
        if Blocks.flatIcon(id) {
            let h = sz * 0.55
            quad([V2(c.x - h, c.y - h), V2(c.x + h, c.y - h), V2(c.x + h, c.y + h), V2(c.x - h, c.y + h)], uv, V4(1, 1, 1, 1), Float(tex[Int(id) * 6]))
            return
        }
        let top = Float(tex[Int(id) * 6 + 2]), left = Float(tex[Int(id) * 6 + 4]), right = Float(tex[Int(id) * 6 + 0])
        let hx = sz * 0.5, hy = sz * 0.25, vh = sz * 0.55
        let t = V2(c.x, c.y - hy - vh / 2 + hy)
        let n = V2(c.x, t.y - hy), e = V2(c.x + hx, t.y), s = V2(c.x, t.y + hy), w = V2(c.x - hx, t.y)
        quad([n, e, s, w], uv, V4(1, 1, 1, 1), top)
        quad([w, s, s + V2(0, vh), w + V2(0, vh)], uv, V4(0.78, 0.78, 0.78, 1), left)
        quad([s, e, e + V2(0, vh), s + V2(0, vh)], uv, V4(0.6, 0.6, 0.6, 1), right)
    }

    // MARK: Headless snapshot

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
        let sky = game.player.headInWater ? V3(0.05, 0.12, 0.3) : game.skyColor
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
