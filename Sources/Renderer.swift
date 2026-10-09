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
    var eye: V4
    var invViewProj = matrix_identity_float4x4
    var shadowMat = matrix_identity_float4x4
    var sunColor = V4(0, 0, 0, 0)
    var ambColor = V4(0, 0, 0, 0)
    var lightDir = V4(0, 1, 0, 0)
    var screen = V4(1, 1, 1, 1)
    var dimTint = V4(1, 1, 1, 0)
}
struct SkyParams { var invViewProj: float4x4; var zenith: V4; var horizon: V4; var sun: V4 }

struct SimpleVert { var pos: V4; var color: V4 }
struct SectionRec { var x: Float; var y: Float; var z: Float; var tint: UInt32 }     // chunkVS buffer(2), 16 bytes
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
    let chunkPipeL: MTLRenderPipelineState
    let chunkSolidPipeL: MTLRenderPipelineState   // same as chunkPipe without the alpha test (keeps hidden-surface removal)
    let waterPipeL: MTLRenderPipelineState
    let simplePipeL: MTLRenderPipelineState
    let hudPipe: MTLRenderPipelineState
    let starPipeL: MTLRenderPipelineState
    let cloudPipeL: MTLRenderPipelineState
    let mobPipeL: MTLRenderPipelineState
    let entityPipeL: MTLRenderPipelineState
    let crackPipeL: MTLRenderPipelineState
    let skyPipeL: MTLRenderPipelineState
    let hollowSkyPipeL: MTLRenderPipelineState
    let cloudBoxPipeL: MTLRenderPipelineState
    let clouds: CloudMesh?
    let shipRenderer: ShipRenderer                // free-moving block structures (ShipRender.swift)
    let starBuf: MTLBuffer
    let starVerts: Int
    let depthWrite: MTLDepthStencilState
    let depthRead: MTLDepthStencilState
    var landmarkVerts: [SimpleVert] = []       // far landmark impostors (LandmarkRender.swift), reused every frame
    var landmarkSmoke: [SimpleVert] = []
    let depthNone: MTLDepthStencilState
    let texture: MTLTexture
    let quadIndices: MTLBuffer
    // Fancy (HDR) pipeline: while a vibrant frame's world passes are encoded, the pipe names below
    // resolve to the HDR variants (Vibrant.swift); Fast always uses the L (drawable-format) ones.
    var vib: Vibrant?
    var hdrActive = false
    // Entity pass of the last frame: ring room, vertices before and after the decor (signs, frames, paintings).
    var entityStats = (cap: -1, beforeDecor: 0, afterDecor: 0)
    var lightFrame = Vibrant.LightFrame()
    var chunkPipe: MTLRenderPipelineState { hdrActive ? vib!.chunk : chunkPipeL }
    var chunkSolidPipe: MTLRenderPipelineState { hdrActive ? vib!.chunkSolid : chunkSolidPipeL }
    var waterPipe: MTLRenderPipelineState { hdrActive ? vib!.water : waterPipeL }
    var simplePipe: MTLRenderPipelineState { hdrActive ? vib!.simple : simplePipeL }
    var starPipe: MTLRenderPipelineState { hdrActive ? vib!.star : starPipeL }
    var cloudPipe: MTLRenderPipelineState { hdrActive ? vib!.cloud : cloudPipeL }
    var mobPipe: MTLRenderPipelineState { hdrActive ? vib!.mob : mobPipeL }
    var entityPipe: MTLRenderPipelineState { hdrActive ? vib!.entity : entityPipeL }
    var crackPipe: MTLRenderPipelineState { hdrActive ? vib!.crack : crackPipeL }
    var skyPipe: MTLRenderPipelineState { hdrActive ? vib!.sky : skyPipeL }
    var hollowSkyPipe: MTLRenderPipelineState { hdrActive ? vib!.hollowSky : hollowSkyPipeL }
    var cloudBoxPipe: MTLRenderPipelineState { hdrActive ? vib!.cloudBox : cloudBoxPipeL }
    static let maxQuads = 1 << 17

    private let inflight = DispatchSemaphore(value: 3)
    private var ring: [MTLBuffer] = []   // per-frame scratch for sky/outline/HUD vertices
    private let ringSize = 1 << 22
    // The world passes (mobs, entities) stop this far short of the ring's end so the first-person arm / gun,
    // the held item and the HUD always fit; at render distance 24 the generation-time animal packs alone
    // could fill the ring, and the arm was then written past the buffer's end.
    private let ringTailReserve = 1 << 19
    private var frame = 0
    // Fancy eye adaptation: current exposure from the surroundings' brightness. Kept per split-screen seat (one view
    // in a cave and one in daylight each adapt on their own; a shared value gave player 2 player 1's exposure).
    struct IconInfo { var order: [Box]; var fit: Float; var mid: V3; var leafy: Bool; var glassy: Bool }
    private var iconCache: [BlockID: IconInfo] = [:]    // hotbar / slot block icons (drawBlockIcon)
    // Far landscape ring (HorizonRing.swift): per-snapshot cell normals / colours and the per-frame projected grid.
    var horizonKey = HorizonKey()
    var horizonNrm: [V3] = []
    var horizonBase: [V3] = []
    var horizonProj: [V4] = []
    private var eyeAdapts = [Float](repeating: 1, count: 4)
    private var eyeAdaptTs = [Double](repeating: 0, count: 4)
    private var seatIx: Int { game.coop.active ? min(3, max(0, game.coop.current)) : 0 }
    private var eyeAdapt: Float { get { eyeAdapts[seatIx] } set { eyeAdapts[seatIx] = newValue } }
    private var eyeAdaptT: Double { get { eyeAdaptTs[seatIx] } set { eyeAdaptTs[seatIx] = newValue } }
    private var lastTime = CACurrentMediaTime()
    var drawHUD = true

    // Stats
    private(set) var fps: Double = 0
    private var fpsFrames = 0
    private var fpsTime: Double = 0
    private(set) var drawnChunks = 0
    private(set) var drawCalls = 0          // chunk section draws last frame (opaque, cutout, water)
    private(set) var drawnQuads = 0
    private(set) var visibleSections = 0
    private(set) var bfsVisited = 0          // sections walked by cave culling last frame
    private(set) var cullSeconds = 0.0       // culling walk + sort, last frame
    private var visibleScratch: [(Chunk, Int, Float)] = []
    private var visitGen: [UInt32] = []
    private var gen: UInt32 = 0
    private var bfs: [(Chunk, Int, Int, Int, Int, Int)] = []
    private var chunkGrid: [Chunk?] = []
    // Base vertex / base instance draws (every Apple-silicon GPU; the old per-draw binding path otherwise).
    // Apple's paravirtual GPU (the CI runners) reports the family but draws base-vertex calls with the wrong
    // vertices (scrambled, black terrain), so it takes the per-draw binding path; --no-base-vertex forces it too.
    // Apple's paravirtual GPU (the CI runners) reports the family but draws base-vertex calls with the wrong
    // vertices (scrambled, black terrain in CI shots); it gets the per-draw path (Engine branch fix, add64f6).
    lazy var baseVertexOK: Bool = (device.supportsFamily(.apple3) || device.supportsFamily(.mac2))
        && !device.name.contains("Paravirtual") && !CommandLine.arguments.contains("--no-base-vertex") && !CommandLine.arguments.contains("--nobase")
        && !device.name.contains("Paravirtual") && !CommandLine.arguments.contains("--no-base-vertex")
    // Apple's paravirtual GPU driver (CI runners) aborts now and then on its own command-storage assertion in Fancy at
    // render distance 24 (runs 354, 362, 371, 372; never on a Mac): there the shadow passes go in a command buffer of
    // their own, so no single buffer carries the whole frame.
    lazy var paravirtual: Bool = device.name.contains("Paravirtual")
    var caveCulling = true
    // Smoothed skylight at the player's eye (0...1, -1 = not sampled yet). Fog and sky colour fade toward
    // near-black when it is low, so distant cave walls no longer fog into bright sky blue underground.
    // Per split-screen seat, like eyeAdapt (shared, the two views pulled it back and forth every frame).
    private var caveKs = [Float](repeating: -1, count: 4)
    private var caveK: Float { get { caveKs[seatIx] } set { caveKs[seatIx] = newValue } }

    @discardableResult func updateCave() -> Float {
        guard game.dim.dim.hasSky else { caveK = 1; return 1 }
        let e = game.player.eye
        let target = Float(game.world.lightAt(Int(floor(e.x)), Int(floor(e.y)), Int(floor(e.z))).sky) / 15
        caveK = caveK < 0 ? target : caveK + (target - caveK) * 0.04
        return caveK
    }
    var caveScale: Float {
        if caveK < 0 { updateCave() }
        return 0.08 + 0.92 * min(1, caveK * 1.6)
    }
    var viewSky: V3 { game.skyColor * caveScale }
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
        chunkPipeL = try pipe("chunkVS", "chunkFS", blend: false)
        chunkSolidPipeL = try pipe("chunkVS", "chunkSolidFS", blend: false)
        waterPipeL = try pipe("chunkVS", "waterFS", blend: true)
        simplePipeL = try pipe("simpleVS", "simpleFS", blend: true)
        hudPipe = try pipe("hudVS", "hudFS", blend: true)
        starPipeL = try pipe("starVS", "starFS", blend: true)
        cloudPipeL = try pipe("cloudVS", "cloudFS", blend: true)
        mobPipeL = try pipe("mobVS", "mobFS", blend: false)
        entityPipeL = try pipe("entityVS", "entityFS", blend: false)
        crackPipeL = try pipe("entityVS", "crackFS", blend: true)
        skyPipeL = try pipe("skyVS", "skyFastFS", blend: false)
        hollowSkyPipeL = try pipe("skyVS", "hollowSkyFS", blend: false)
        cloudBoxPipeL = try pipe("cloudBoxVS", "cloudBoxFS", blend: true)
        clouds = CloudMesh(device: device)
        shipRenderer = try ShipRenderer(device: device, colorFormat: colorFormat)

        // Star field: fixed random directions on a sphere of radius 90 (sky frame, rotated per frame).
        var stars: [SimpleVert] = []
        for i in 0..<1400 {
            let u1 = hashf(i, 1, 0, 4242) * 2 - 1, u2 = hashf(i, 2, 0, 4242) * 2 * .pi
            let rr = (1 - u1 * u1).squareRoot()
            let dir = V3(rr * cosf(u2), u1, rr * sinf(u2))
            let size: Float = (0.1 + 0.16 * hashf(i, 3, 0, 4242) * hashf(i, 4, 0, 4242)) * 1.6     // room for the soft edge (starFS)
            let b: Float = 0.45 + 0.55 * hashf(i, 5, 0, 4242)
            let warm = hashf(i, 6, 0, 4242)
            let col = V4(b * (0.85 + 0.15 * warm), b * 0.9, b * (1 - 0.15 * warm), 1)
            let c = dir * 90
            let ref = abs(dir.y) > 0.9 ? V3(1, 0, 0) : V3(0, 1, 0)
            let r = simd_normalize(simd_cross(dir, ref)) * size
            let up = simd_normalize(simd_cross(r, dir)) * size
            let lo: V3 = c - up, hi: V3 = c + up
            let q: [V3] = [lo - r, lo + r, hi + r, hi - r]
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

        // Texture array with a CPU-built mip chain, built, compressed and uploaded in batches of layers (128 px RGBA
        // for every layer at once would hold ~145 MB on the CPU side during start-up). Every texture name is
        // registered first: the layer count must be final before the array and the emissive mask are sized.
        TextureGen.registerAll()
        let layers = Tex.count
        // BC3-compressed where the GPU samples BC formats (TexCompress), RGBA8 otherwise.
        let bc = TexCompress.enabled && device.supportsBCTextureCompression
        let td = MTLTextureDescriptor()
        td.textureType = .type2DArray
        td.pixelFormat = bc ? .bc3_rgba : .rgba8Unorm
        td.width = TextureGen.size
        td.height = TextureGen.size
        td.arrayLength = layers
        var levelCount = 1
        while (TextureGen.size >> (levelCount - 1)) > 1 { levelCount += 1 }
        td.mipmapLevelCount = levelCount
        td.usage = .shaderRead
        let tex = device.makeTexture(descriptor: td)!
        var texBytes = 0
        var tgMs: Double = 0, tcMs: Double = 0
        let batch = 256
        var first = 0
        let glow = Vibrant.emissiveModes(layers: layers)
        let (glowSlots, glowSlices) = Vibrant.emissiveSlots(glow)
        var emissive = [UInt8](repeating: 0, count: TextureGen.size * TextureGen.size * glowSlices)
        while first < layers {
            let range = first..<min(layers, first + batch)
            let tg0 = CFAbsoluteTimeGetCurrent()
            let levels = TextureGen.mipChain(layers: range)
            Vibrant.emissiveMask(levels[0], first: range.lowerBound, count: range.count, modes: glow, slots: glowSlots, into: &emissive)
            tgMs += (CFAbsoluteTimeGetCurrent() - tg0) * 1000
            let tc0 = CFAbsoluteTimeGetCurrent()
            let n = range.count
            var size = TextureGen.size
            for (lvl, data) in levels.enumerated() where lvl < levelCount {
                let bytesPerImage = size * size * 4
                if bc {
                    let bw = max(1, (size + 3) / 4)
                    let blockBytes = bw * bw * 16
                    var packed = [UInt8](repeating: 0, count: blockBytes * n)
                    let sz = size
                    data.withUnsafeBytes { raw in
                        packed.withUnsafeMutableBufferPointer { dst in
                            let base = dst.baseAddress!
                            DispatchQueue.concurrentPerform(iterations: n) { layer in
                                TexCompress.encode(raw.baseAddress! + layer * bytesPerImage, size: sz, into: base + layer * blockBytes)
                            }
                        }
                    }
                    packed.withUnsafeBytes { raw in
                        for layer in 0..<n {
                            tex.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: lvl, slice: range.lowerBound + layer,
                                        withBytes: raw.baseAddress! + layer * blockBytes, bytesPerRow: bw * 16, bytesPerImage: blockBytes)
                        }
                    }
                    texBytes += blockBytes * n
                } else {
                    data.withUnsafeBytes { raw in
                        for layer in 0..<n {
                            tex.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: lvl, slice: range.lowerBound + layer,
                                        withBytes: raw.baseAddress! + layer * bytesPerImage,
                                        bytesPerRow: size * 4, bytesPerImage: bytesPerImage)
                        }
                    }
                    texBytes += bytesPerImage * n
                }
                size = max(1, size / 2)
            }
            tcMs += (CFAbsoluteTimeGetCurrent() - tc0) * 1000
            first = range.upperBound
        }
        print(String(format: "textures: %d layers at %d px, %@, %.1f MB with mips (build %.0f ms, upload %.0f ms)", layers, TextureGen.size,
                     bc ? "BC3" : "RGBA8", Double(texBytes) / 1_048_576, tgMs, tcMs))
        texture = tex
        do {
            let vlib = try device.makeLibrary(source: shaderSource + vibrantShaderSource, options: nil)
            vib = try Vibrant(device: device, library: vlib, finalFormat: colorFormat, emissive: emissive, slots: glowSlots)
        } catch { print("Fancy renderer unavailable (falling back to Fast): \(error)") }

        // Shared index buffer: every quad is 4 vertices -> 2 CCW triangles.
        // Written in place (building it through per-quad array literals cost a measurable slice of startup).
        let qi = device.makeBuffer(length: Renderer.maxQuads * 6 * 4, options: .storageModeShared)!
        let ip = qi.contents().bindMemory(to: UInt32.self, capacity: Renderer.maxQuads * 6)
        for q in 0..<Renderer.maxQuads {
            let b = UInt32(q * 4), o = q * 6
            ip[o] = b; ip[o + 1] = b + 1; ip[o + 2] = b + 2; ip[o + 3] = b; ip[o + 4] = b + 2; ip[o + 5] = b + 3
        }
        quadIndices = qi

        super.init()
        if let v = vib { shipRenderer.vibPipes = [v.shipSolid, v.shipCut, v.shipTrans] }   // ships lit like terrain in Fancy
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

        adjustResolution(view)
        if game.coop.active && view.framebufferOnly { view.framebufferOnly = false }    // split screen copies views in
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
        BugNotes.shared.frameTime = dt
        if let shot = BugNotes.shared.screenshotRequest {
            // Voice bug note started: save this view next to the note (half size on big screens).
            BugNotes.shared.screenshotRequest = nil
            inflight.wait(); inflight.wait()
            let sz = view.drawableSize, k: CGFloat = sz.width > 1600 ? 0.5 : 1
            _ = renderToPNG(path: shot.path, width: Int(sz.width * k), height: Int(sz.height * k))
            inflight.signal(); inflight.signal()
        }
        let cmd = queue.makeCommandBuffer()!
        let fence = MeshArena.frameSubmitted()      // freed meshes wait for this frame before reuse
        cmd.addCompletedHandler { [inflight, weak self] cb in
            MeshArena.frameCompleted(fence)
            self?.recordGPU(cb.gpuEndTime - cb.gpuStartTime)
            let g = cb.gpuEndTime - cb.gpuStartTime
            if g > 0 && g < 1, let s = self { s.frameGPULock.lock(); s.frameGPUMs = s.frameGPUMs * 0.92 + g * 1000 * 0.08; s.frameGPULock.unlock() }
            inflight.signal()
        }
        let s = view.drawableSize
        renderFrame(cmd, final: rpd, width: Int(s.width), height: Int(s.height))
        cmd.present(drawable)
        cmd.commit()
        onFrame?(dt)
    }

    // MARK: Dynamic resolution
    // Above 1440p (a 4K TV, a big external display) the drawable shrinks in 5% steps, down to 60%, while the
    // GPU needs more than ~85% of the frame budget, and grows back once it has headroom; the layer scales it
    // to the window. At 1440p and below it always renders at full resolution.
    private(set) var renderScale: Double = 1
    private var gpuAvgMs = 0.0
    private var scaleCooldown = 0
    private let gpuLock = NSLock()
    var dynamicResolution = UserDefaults.standard.object(forKey: "dynamicResolution") as? Bool ?? true

    private func recordGPU(_ seconds: Double) {
        guard seconds > 0 && seconds < 1 else { return }
        gpuLock.lock(); gpuAvgMs = gpuAvgMs * 0.9 + seconds * 1000 * 0.1; gpuLock.unlock()
    }

    private func adjustResolution(_ view: MTKView) {
        let full = view.convertToBacking(view.bounds).size
        guard full.width >= 1, full.height >= 1 else { return }
        gpuLock.lock(); let g = gpuAvgMs; gpuLock.unlock()
        let budget = 1000.0 / Double(max(30, view.preferredFramesPerSecond))
        if !dynamicResolution || Double(full.width * full.height) <= 2560 * 1440 * 1.05 {
            renderScale = 1
        } else if scaleCooldown > 0 {
            scaleCooldown -= 1
        } else if g > budget * 0.85 && renderScale > 0.6 {
            renderScale = max(0.6, renderScale - 0.05); scaleCooldown = 20
        } else if g < budget * 0.55 && renderScale < 1 {
            renderScale = min(1, renderScale + 0.05); scaleCooldown = 40
        }
        // The Resolution option (Settings.renderScale, for TVs) caps the dynamic scale.
        let k = renderScale * Double(Settings.shared.renderScale)
        let want = CGSize(width: max(64, (full.width * k).rounded()), height: max(64, (full.height * k).rounded()))
        if view.autoResizeDrawable { view.autoResizeDrawable = false }
        if abs(view.drawableSize.width - want.width) >= 1 || abs(view.drawableSize.height - want.height) >= 1 {
            view.drawableSize = want
        }
    }

    // MARK: Scene

    enum Split { case afterOpaque, beforeHUD }
    private(set) var lastUniforms: Uniforms?
    // Harness pixel probes: world points whose on-screen colour renderToPNG prints after the readback.
    var probes: [(String, V3)] = []
    var postParams = PostParams()
    private var shadowList: [(Chunk, Int)] = []
    private var splitColor: MTLTexture?           // split screen: one view's target (Coop.swift)
    private var splitDepth: MTLTexture?
    private var flashScratch: [V4] = []
    private let frameGPULock = NSLock()
    private var frameGPUMs: Double = 0
    var gpuFrameMs: Double { frameGPULock.lock(); defer { frameGPULock.unlock() }; return frameGPUMs }
    private var lastShadow = Vibrant.LightFrame()
    private var shadowAge = 0
    // Fancy: this frame's mob (and third-person player) vertices, written once before the shadow pass and
    // drawn both into the shadow map and in the world pass.
    private var mobBufs: [MTLBuffer] = []
    private var mobBufIdx = 0
    private var mobPre: (buf: MTLBuffer, count: Int)?
    private var shadowHadMobs = false
    var shadowFresh = false

    // Camera position and angles: first person, or pulled back behind / in front of the player (F5),
    // stopping short of blocks.
    func cameraEye() -> (eye: V3, yaw: Float, pitch: Float) {
        let p = game.player
        // Photo mode (Cinematic.swift): the free camera.
        if game.cine.active {
            if game.cine.followPlayer { return (p.eye, p.yaw, p.pitch) }
            return (game.cine.pos, game.cine.yaw, game.cine.pitch)
        }
        let tp = game.cameraMode != 0 && game.sleeping == 0
        var camYaw = p.yaw, camPitch = p.pitch
        var eye = p.eye
        if tp {
            let front = game.cameraMode == 2
            let dir = front ? p.look : -p.look
            if front { camYaw = p.yaw + .pi; camPitch = -p.pitch }
            let reach = game.thirdPersonDistance          // 4, or farther back while steering a big ship
            var dist: Float = reach
            var t: Float = 0.1
            while t < reach {
                let q = p.eye + dir * t
                if Blocks.opaque[Int(game.world.block(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z))))] { dist = max(0.2, t - 0.3); break }
                t += 0.1
            }
            eye = p.eye + dir * dist
        }
        return (eye, camYaw, camPitch)
    }

    // One frame into `final` (the drawable or an offscreen target). Fast: a single pass. Fancy: shadow
    // map, HDR world pass, scene copy, HDR water/translucent pass, post (bloom, god rays, haze, tone map,
    // grading) into `final`, then the HUD.
    func renderFrame(_ cmd: MTLCommandBuffer, final: MTLRenderPassDescriptor, width: Int, height: Int) {
        MobLight.fill = (0.06 + 0.3 * Settings.shared.lightBrightness) * (game.fancyGraphics && vib != nil ? 1 : 2)
        MobDrawStats.mobs = game.mobs.mobs.count
        MobDrawStats.near = 0
        let pe = game.player.pos
        for m in game.mobs.mobs where simd_length_squared(m.pos - pe) < 32 * 32 { MobDrawStats.near += 1 }
        MobDrawStats.written = 0; MobDrawStats.drawn = 0; MobDrawStats.culled = 0; MobDrawStats.dropped = 0; MobDrawStats.path = "none"
        HudLayout.splitFullH = game.coop.active ? Float(height) : 0
        HudLayout.splitFullW = game.coop.active ? Float(width) : 0
        if game.coop.active { renderSplit(cmd, final: final, width: width, height: height); return }
        renderView(cmd, final: final, width: width, height: height)
    }

    // Split screen (Coop.swift): each seat's view (world + its own HUD and menus) renders at full width and a share of
    // the height into an offscreen target, copied into its band of the frame (player 1 on top) with a thin dark gap.
    private func renderSplit(_ cmd: MTLCommandBuffer, final: MTLRenderPassDescriptor, width: Int, height: Int) {
        guard let out = final.colorAttachments[0].texture else { return }
        let n = game.coop.seatCount
        let gap = height >= 900 ? 4 : 2
        // Top / bottom (wide views), or side by side (Options > Interface > Split Screen: taller views, menus stay bigger).
        let side = Settings.shared.splitSideBySide
        let w = side ? max(16, (width - gap * (n - 1)) / n) : width
        let h = side ? height : max(16, (height - gap * (n - 1)) / n)
        // Two views a frame: twice the per-frame scratch buffers (each view takes the next one).
        while ring.count < 6 { ring.append(device.makeBuffer(length: ringSize, options: .storageModeShared)!) }
        shipRenderer.ensureRing(6)
        if splitColor?.width != w || splitColor?.height != h || splitColor?.pixelFormat != out.pixelFormat {
            let cd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: out.pixelFormat, width: w, height: h, mipmapped: false)
            cd.usage = [.renderTarget, .shaderRead]
            cd.storageMode = .private
            splitColor = device.makeTexture(descriptor: cd)
            let df = final.depthAttachment.texture?.pixelFormat ?? .depth32Float
            let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: df, width: w, height: h, mipmapped: false)
            dd.usage = .renderTarget
            dd.storageMode = .private
            splitDepth = device.makeTexture(descriptor: dd)
        }
        guard let sc = splitColor, let sd = splitDepth else { return }
        // Clear the whole frame (the gap stays dark).
        final.colorAttachments[0].loadAction = .clear
        final.colorAttachments[0].clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.025, alpha: 1)
        final.colorAttachments[0].storeAction = .store
        cmd.makeRenderCommandEncoder(descriptor: final)?.endEncoding()
        let me = game.coop.current
        for i in 0..<n {
            game.coop.switchTo(i, game)
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = sc
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].storeAction = .store
            rpd.depthAttachment.texture = sd
            rpd.depthAttachment.loadAction = .clear
            rpd.depthAttachment.storeAction = .dontCare
            rpd.depthAttachment.clearDepth = 1
            renderView(cmd, final: rpd, width: w, height: h)
            let b = cmd.makeBlitCommandEncoder()!
            let ox = side ? i * (w + gap) : 0, oy = side ? 0 : i * (h + gap)
            b.copy(from: sc, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: w, height: h, depth: 1),
                   to: out, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: ox, y: oy, z: 0))
            b.endEncoding()
        }
        game.coop.switchTo(me, game)
    }

    private func renderView(_ cmd: MTLCommandBuffer, final: MTLRenderPassDescriptor, width: Int, height: Int) {
        // Per view: mobs share this player's night-vision lift (set once per frame, both halves used player 1's).
        MobLight.nightVision = game.nightVision
        updateCave()
        let clear = game.blindFog != nil ? V3(0, 0, 0) : (game.player.headInLava ? Game.lavaFog : (game.player.headInWater ? game.underwaterFog : viewSky))
        let cc = MTLClearColor(red: Double(clear.x), green: Double(clear.y), blue: Double(clear.z), alpha: 1)
        guard game.fancyGraphics, let v = vib else {
            final.colorAttachments[0].clearColor = cc
            final.colorAttachments[0].loadAction = .clear
            let enc = cmd.makeRenderCommandEncoder(descriptor: final)!
            encode(enc, width: Float(width), height: Float(height)).endEncoding()
            return
        }
        let rs = max(0.5, min(1, game.renderScale))
        v.ensure(max(1, Int(Float(width) * rs)), max(1, Int(Float(height) * rs)))
        // The shadow map is re-rendered only when the light turned or the snapped centre moved (or every
        // 8th frame for block edits); otherwise last frame's map and matrix are reused.
        let lf = Vibrant.lightFrame(game: game, eye: game.coop.shadowFocus(game) ?? cameraEye().eye)
        shadowAge += 1
        let turned = simd_dot(lf.dir, lastShadow.dir) < 0.99995
        let moved = simd_length(lf.center - lastShadow.center) > 1.0
        var terrainShadow = false
        let shadowCmd: MTLCommandBuffer = paravirtual ? (cmd.commandQueue.makeCommandBuffer() ?? cmd) : cmd
        if turned || moved || shadowAge >= 8 || lf.shadowStrength != lastShadow.shadowStrength || shadowFresh == false {
            lightFrame = lf
            shadowPass(shadowCmd, v)
            lastShadow = lf
            shadowAge = 0
            shadowFresh = true
            terrainShadow = true
        } else {
            var keep = lf
            keep.lightVP = lastShadow.lightVP
            keep.center = lastShadow.center
            lightFrame = keep
        }
        mobShadowPass(shadowCmd, v, terrainChanged: terrainShadow, width: width, height: height)
        if shadowCmd !== cmd { shadowCmd.commit() }
        defer { mobPre = nil }
        let a = MTLRenderPassDescriptor()
        a.colorAttachments[0].texture = v.hdr
        a.colorAttachments[0].loadAction = .clear
        a.colorAttachments[0].clearColor = cc
        a.colorAttachments[0].storeAction = .store
        a.depthAttachment.texture = v.depth
        a.depthAttachment.loadAction = .clear
        a.depthAttachment.clearDepth = 1
        a.depthAttachment.storeAction = .store
        func bind(_ e: MTLRenderCommandEncoder) {
            e.setFragmentTexture(texture, index: 0)
            e.setFragmentTexture(v.shadowMap, index: 1)
            e.setFragmentTexture(v.emissive, index: 2)
            e.setFragmentBuffer(v.materials, offset: 0, index: 4)
            _ = self.game.packFlashes(eye: self.cameraEye().eye, into: &self.flashScratch)
            self.flashScratch.withUnsafeBytes { e.setFragmentBytes($0.baseAddress!, length: $0.count, index: 5) }
        }
        hdrActive = true
        let encA = cmd.makeRenderCommandEncoder(descriptor: a)!
        bind(encA)
        let last = encode(encA, width: Float(width), height: Float(height)) { stage, cur in
            cur.endEncoding()
            switch stage {
            case .afterOpaque:
                let b = cmd.makeBlitCommandEncoder()!
                b.copy(from: v.hdr!, to: v.sceneCopy!)
                b.copy(from: v.depth!, to: v.depthCopy!)
                b.endEncoding()
                let d = MTLRenderPassDescriptor()
                d.colorAttachments[0].texture = v.hdr
                d.colorAttachments[0].loadAction = .load
                d.colorAttachments[0].storeAction = .store
                d.depthAttachment.texture = v.depth
                d.depthAttachment.loadAction = .load
                d.depthAttachment.storeAction = .store
                let e = cmd.makeRenderCommandEncoder(descriptor: d)!
                bind(e)
                e.setFragmentTexture(v.sceneCopy, index: 3)
                e.setFragmentTexture(v.depthCopy, index: 4)
                return e
            case .beforeHUD:
                self.hdrActive = false
                final.colorAttachments[0].loadAction = .dontCare
                let e = v.post(cmd, final: final, u: self.lastUniforms ?? Uniforms(viewProj: matrix_identity_float4x4, fogColor: .zero, params: .zero, sunDir: .zero, eye: .zero), params: self.postParams)
                e.setFragmentTexture(self.texture, index: 0)
                return e
            }
        }
        last.endEncoding()
        hdrActive = false
    }

    // Mobs cast moving shadows: copy the terrain map and draw this frame's mob vertices on top. Skipped while
    // no mob has been in the map since the terrain map last changed (then shadowMap already holds the terrain).
    // The camera's view frustum for culling mobs before encode builds its own (same projection, a far far plane).
    // Mobs past the loaded terrain's fog can't be seen (frigates far off are ships, not mobs).
    var mobMaxDist: Float { Float(game.world.renderDistance * CS + 24) }

    func mobCullFrustum(_ width: Int, _ height: Int) -> Frustum {
        let (eye, camYaw, camPitch) = cameraEye()
        let fov: Float = (game.cine.active ? game.cine.fov : game.fovSetting * game.fovScale) * .pi / 180
        let proj = perspectiveRH(fovy: fov, aspect: Float(width) / Float(max(height, 1)), near: 0.05, far: 4000)
        let viewRot = rotationX(-camPitch) * rotationY(-camYaw)
        return Frustum(proj * viewRot * translationMatrix(-eye))
    }

    // This view's mob vertices (and the player model, and split screen's other player) in a buffer of their own: Fancy
    // writes them before the shadow pass, Fast before its draw. Nearest mobs go first, and the buffers double (up to
    // 16 MB) after a frame that had to drop some: a Capital soldier close up is 190 parts (330 KB of vertices), so a
    // dozen filled the old 4 MB and the rest, the mobs beside the player among them, went undrawn (playtest 2026-10-05).
    private var mobBufBytes = 1 << 22
    func writeMobBuffer(eye: V3, daylight: Float, cull: Frustum) -> (buf: MTLBuffer, count: Int)? {
        let want = game.coop.active ? 6 : 3           // split screen draws two views a frame
        while mobBufs.count < want {
            guard let b = device.makeBuffer(length: mobBufBytes, options: .storageModeShared) else { break }
            mobBufs.append(b)
        }
        guard !mobBufs.isEmpty else { return nil }
        mobBufIdx = (mobBufIdx + 1) % mobBufs.count
        let buf = mobBufs[mobBufIdx]
        let cap = buf.length / MemoryLayout<MobVert>.stride
        let ptr = buf.contents().bindMemory(to: MobVert.self, capacity: cap)
        let droppedBefore = MobDrawStats.dropped
        var n = writeMobVertices(game.mobs.mobs, eye: eye, daylight: daylight, world: game.world, into: ptr, capacity: cap,
                                 cull: cull, maxDist: mobMaxDist)
        if game.showsPlayerModel { n += writePlayerModel(game, eye: eye, daylight: daylight, into: ptr + n, capacity: cap - n) }
        n += game.coop.writeOthers(game, eye: eye, daylight: daylight, into: ptr + n, capacity: cap - n)
        MobDrawStats.written += n
        if MobDrawStats.dropped > droppedBefore && mobBufBytes < 1 << 24 {
            mobBufBytes <<= 1
            mobBufs.removeAll()                       // larger ones next frame (frames in flight keep theirs alive)
        }
        return (buf, n)
    }

    func mobShadowPass(_ cmd: MTLCommandBuffer, _ v: Vibrant, terrainChanged: Bool, width: Int, height: Int) {
        let lf = lightFrame
        let eye = cameraEye().eye
        var n = 0
        if !game.mobs.mobs.isEmpty || game.showsPlayerModel || game.coop.active,
           let pre = writeMobBuffer(eye: eye, daylight: game.renderDaylight, cull: mobCullFrustum(width, height)) {
            mobPre = pre
            n = pre.count
        }
        let cast = n > 0 && lf.shadowStrength > 0
        guard cast || shadowHadMobs || terrainChanged else { return }
        shadowHadMobs = cast
        let b = cmd.makeBlitCommandEncoder()!
        b.copy(from: v.shadowStatic, to: v.shadowMap)
        b.endEncoding()
        guard cast, let pre = mobPre else { return }
        let d = MTLRenderPassDescriptor()
        d.depthAttachment.texture = v.shadowMap
        d.depthAttachment.loadAction = .load
        d.depthAttachment.storeAction = .store
        let e = cmd.makeRenderCommandEncoder(descriptor: d)!
        var lvp = lf.lightVP
        let o3: V3 = eye - lf.center
        var o = V4(o3.x, o3.y, o3.z, 0)
        e.setRenderPipelineState(v.mobShadow)
        e.setDepthStencilState(v.shadowDepth)
        e.setCullMode(.none)
        e.setDepthClipMode(.clamp)
        e.setVertexBuffer(pre.buf, offset: 0, index: 0)
        e.setVertexBytes(&lvp, length: MemoryLayout<float4x4>.stride, index: 1)
        e.setVertexBytes(&o, length: 16, index: 2)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: pre.count)
        e.endEncoding()
    }

    // Depth-only render of the terrain around the camera as seen from the sun / moon (into the static map).
    func shadowPass(_ cmd: MTLCommandBuffer, _ v: Vibrant) {
        let d = MTLRenderPassDescriptor()
        d.depthAttachment.texture = v.shadowStatic
        d.depthAttachment.loadAction = .clear
        d.depthAttachment.clearDepth = 1
        d.depthAttachment.storeAction = .store
        let e = cmd.makeRenderCommandEncoder(descriptor: d)!
        defer { e.endEncoding() }
        let lf = lightFrame
        if lf.shadowStrength <= 0 { return }
        let fr = Frustum(lf.lightVP * translationMatrix(-lf.center))
        let R = Int((Vibrant.shadowHalf * 1.5 / 16).rounded(.up)) + 1
        let ccx = floorDiv(Int(floor(lf.center.x)), CS), ccz = floorDiv(Int(floor(lf.center.z)), CS)
        shadowList.removeAll(keepingCapacity: true)
        for dz in -R...R { for dx in -R...R {
            guard let c = game.world.chunks[ChunkKey(x: ccx + dx, z: ccz + dz)], c.meshedOnce else { continue }
            for sy in 0..<NSEC {
                let sec = c.sections[sy]
                if sec.empty || sec.opaqueQuads == 0 || sec.opaqueBuf == nil { continue }
                let mn = V3(Float(c.cx * CS), Float(sy * 16), Float(c.cz * CS))
                if !fr.visible(min: mn, max: mn + V3(16, 16, 16)) { continue }
                shadowList.append((c, sy))
            }
        } }
        var lvp = lf.lightVP
        e.setDepthStencilState(v.shadowDepth)
        e.setCullMode(.none)
        e.setDepthClipMode(.clamp)
        e.setVertexBytes(&lvp, length: MemoryLayout<float4x4>.stride, index: 1)
        e.setFragmentTexture(texture, index: 0)
        for pass in 0..<2 {
            e.setRenderPipelineState(pass == 0 ? v.shadowSolid : v.shadowCut)
            for (c, sy) in shadowList {
                let sec = c.sections[sy]
                guard let buf = sec.opaqueBuf else { continue }
                let total = min(sec.opaqueQuads, Renderer.maxQuads), solid = min(sec.solidQuads, total)
                let first = pass == 0 ? 0 : solid, count = pass == 0 ? solid : total - solid
                if count <= 0 { continue }
                var o = V4(Float(c.cx * CS) - lf.center.x, Float(sy * 16) - lf.center.y, Float(c.cz * CS) - lf.center.z, 0)
                e.setVertexBuffer(buf.buffer, offset: buf.offset, index: 0)
                e.setVertexBytes(&o, length: 16, index: 2)
                e.drawIndexedPrimitives(type: .triangle, indexCount: count * 6, indexType: .uint32,
                                        indexBuffer: quadIndices, indexBufferOffset: first * 6 * 4)
            }
        }
    }

    @discardableResult
    func encode(_ enc0: MTLRenderCommandEncoder, width W: Float, height H: Float,
                split: ((Split, MTLRenderCommandEncoder) -> MTLRenderCommandEncoder)? = nil) -> MTLRenderCommandEncoder {
        var enc = enc0
        // World passes may render below the output size (Fancy render scale); the HUD always uses W x H.
        let VW = hdrActive ? Float(vib?.hdr?.width ?? Int(W)) : W
        let VH = hdrActive ? Float(vib?.hdr?.height ?? Int(H)) : H
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
        let tp = game.showsPlayerModel
        let (eye, camYaw, camPitch) = cameraEye()
        let camLook = V3(-sinf(camYaw) * cosf(camPitch), sinf(camPitch), -cosf(camYaw) * cosf(camPitch))
        let rd = Float(game.world.renderDistance)
        let underwater = p.headInWater
        // Capital ships show far past the terrain (a 480-block frigate on the horizon): a longer far plane while one is out.
        let far = max(rd * 16 + 96, game.world.ships.list.contains { $0.kinematic } ? 1000 : 0)
        let proj = perspectiveRH(fovy: (game.cine.active ? game.cine.fov : game.fovSetting * game.fovScale) * .pi / 180, aspect: W / max(H, 1), near: 0.05, far: far)
        let viewRot = rotationX(-camPitch) * rotationY(-camYaw)
        let viewProj = proj * viewRot
        let frustum = Frustum(viewProj * translationMatrix(-eye))

        let sky = viewSky
        let hasSky = game.dim.dim.hasSky
        // Under water: clear daytime water sees ~56 blocks, night and murky depths much less.
        let uwSee: Float = 18 + 38 * game.daylight * caveScale
        // 12 short of the render distance: at 6 the loaded world's edge (and half-fogged trees on it) showed as an arc
        // in aerial views (blind critic, tour_777_aerial; tour_mesa).
        var fogEnd: Float = underwater ? uwSee : (game.dim.dim == .nether ? min(rd * 16 - 12, 96) : rd * 16 - 12)
        var fogStart: Float = underwater ? 1 : fogEnd * 0.62
        var fogColor = underwater ? game.underwaterFog : sky
        if p.headInLava {
            // Inside lava: a few blocks of glowing orange (a little more with fire resistance).
            fogEnd = game.effects.has(.fireResistance) ? 6 : 2.5; fogStart = 0.2; fogColor = Game.lavaFog
        }
        if let bf = game.blindFog { fogEnd = min(fogEnd, bf); fogStart = bf * 0.2; fogColor = V3(0, 0, 0) }
        let daylight = game.renderDaylight
        // Night vision lifts every light level toward full brightness.
        let nv = game.nightVision
        let ambient = 1 - (1 - game.dim.dim.ambient) * (1 - 0.85 * nv)
        // Warm dawn/dusk glow strength shared by the Fancy sky dome and the fog toward the sun.
        let skyGlow: Float = {
            let sd = game.sunDir
            let dusk = max(0, 1 - abs(sd.y - 0.02) / 0.22)
            return (dusk * 0.9 + 0.12 * daylight) * (1 - min(1, game.weather.rain))
        }()
        let fogGlow: Float = (!underwater && hasSky && game.blindFog == nil) ? min(0.99, skyGlow) : 0
        var u = Uniforms(viewProj: viewProj,
                         fogColor: V4(fogColor, fogStart),
                         params: V4(fogEnd, daylight, Float(game.time.truncatingRemainder(dividingBy: 1000)), underwater ? 1 : 0),
                         sunDir: V4(game.sunDir, ambient),
                         eye: V4(eye, game.fancyGraphics ? 1 + fogGlow : 0))
        u.dimTint.w = Settings.shared.lightBrightness                            // cave fill strength (Shaders.caveFill)
        if hdrActive {
            let lf = lightFrame
            u.invViewProj = viewProj.inverse
            u.shadowMat = lf.lightVP * translationMatrix(eye - lf.center)
            u.sunColor = V4(lf.color, lf.shadowStrength)
            u.ambColor = V4(lf.ambient, game.dim.dim.hasSky ? min(1, game.weather.rain) : 0)
            u.lightDir = V4(lf.dir, Float(game.dayFraction))
            u.screen = V4(VW, VH, 1 / max(VW, 1), 1 / max(VH, 1))
            // Dimension ambient colour: ember-warm in the Emberdeep, cool violet in the Hollow (night vision stays white).
            let dimC: V3 = game.dim.dim == .nether ? V3(1.0, 0.78, 0.68) : (game.dim.dim == .end ? V3(0.86, 0.8, 1.0) : V3(1, 1, 1))
            u.dimTint = V4(simd_mix(dimC, V3(1, 1, 1), V3(repeating: game.nightVision)), Settings.shared.lightBrightness)
            // Post: sun position for god rays, bloom, haze and grading.
            var pp = PostParams()
            // Eyes adapt at night: exposure rises as daylight falls (only with open sky above).
            let night: Float = hasSky ? simd_clamp((0.55 - daylight) / 0.45, 0, 1) * caveScale : 0
            pp.grade = V4(1.0 + 0.55 * night, 1.14 - 0.12 * night, 1.06, 0.16)
            if game.cine.active && game.cine.dof { pp.dof = V4(game.cine.focus, game.cine.aperture, max(4, H / 90), 1) }
            // Eye adaptation: exposure follows how bright the eye's surroundings are (sky and block light around it),
            // opening up slowly in the dark and closing quickly in daylight, so leaving a cave is bright for a moment.
            let ex = Int(floor(eye.x)), ey = Int(floor(eye.y)), ez = Int(floor(eye.z))
            var lum: Float = 0
            for (dx, dz) in [(0, 0), (2, 0), (-2, 0), (0, 2), (0, -2)] {
                let l = game.world.lightAt(ex + dx, ey, ez + dz)
                lum += max(Float(l.sky) / 15 * daylight, Float(l.block) / 15 * 0.85) / 5
            }
            let adaptRange: Float = hasSky ? 0.6 : 0.25                      // the Emberdeep and Hollow have their own ambient
            let adaptTarget: Float = 1 + adaptRange * (1 - simd_clamp(lum, 0, 1))
            let nowT = CFAbsoluteTimeGetCurrent()
            if eyeAdaptT == 0 { eyeAdapt = adaptTarget }                      // first frame (and snapshots): already adapted
            let adt = Float(min(0.1, max(0, nowT - eyeAdaptT)))
            eyeAdaptT = nowT
            let rate: Float = adaptTarget > eyeAdapt ? 0.7 : 2.0
            eyeAdapt += (adaptTarget - eyeAdapt) * (1 - expf(-adt * rate))
            pp.grade.x = max(pp.grade.x, eyeAdapt)
            pp.sun.w = 0.075
            let sunDay = game.sunDir.y > -0.02
            if hasSky && !underwater && game.blindFog == nil && sunDay {
                let cp = viewProj * V4(game.sunDir * 100, 1)
                if cp.w > 0 {
                    let nd = V2(cp.x / cp.w, cp.y / cp.w)
                    pp.sun.x = nd.x * 0.5 + 0.5; pp.sun.y = 0.5 - nd.y * 0.5
                    let off = max(abs(nd.x), abs(nd.y))
                    let onScreen: Float = max(0, 1 - max(0, off - 1) / 0.8)
                    let clearSky: Float = 1 - min(1, game.weather.rain)
                    pp.sun.z = 0.45 * onScreen * clearSky * caveScale
                }
                pp.sunCol = V4(lf.color * 1.6, lf.hazeStrength * caveScale)
            }
            if hasSky && !underwater && game.blindFog == nil {
                // Morning and evening mist settles in the lowlands (sea level and a few blocks up); rain thickens it.
                let tod = Float(game.dayFraction)
                let morning = max(0, 1 - abs(tod - 0.03) / 0.09), evening = max(0, 1 - abs(tod - 0.5) / 0.08)
                let rain = min(1, game.weather.rain)
                // Thinner than before: at sea level the evening mist veiled everything in lavender and burnt to white
                // toward the sun (blind critic, run 364 lake_glint: 7 % of the frame clipped).
                let dens: Float = (0.003 + 0.016 * max(morning, evening * 0.35) + 0.012 * rain) * caveScale
                pp.mist = V4(fogColor * 0.95 + lf.color * 0.25, dens)
                pp.mistH = V4(Float(SEA) - eye.y + 2, 9, 0, 0)
            }
            postParams = pp
        }
        lastUniforms = u
        ParticleManager.glowBoost = hdrActive ? 3.2 : 1
        ParticleManager.flashes = game.flashes

        enc.setFragmentTexture(texture, index: 0)

        // Fancy sky: gradient dome + sun glow drawn over the clear colour before anything else.
        if game.fancyGraphics && !underwater && hasSky && game.blindFog == nil {
            var sp = SkyParams(invViewProj: viewProj.inverse, zenith: V4(game.skyZenith * caveScale, Float(game.dayFraction * 2 * .pi)),
                               horizon: V4(sky, skyGlow), sun: V4(game.sunDir, daylight))
            enc.setRenderPipelineState(skyPipe)
            enc.setDepthStencilState(depthNone)
            enc.setCullMode(.none)
            enc.setFragmentBytes(&sp, length: MemoryLayout<SkyParams>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        } else if game.fancyGraphics && game.dim.dim == .end && !underwater && game.blindFog == nil {
            var sp = SkyParams(invViewProj: viewProj.inverse, zenith: V4(sky, 0), horizon: V4(sky, 0),
                               sun: V4(0, 1, 0, Float(game.clock.truncatingRemainder(dividingBy: 10000))))
            enc.setRenderPipelineState(hollowSkyPipe)
            enc.setDepthStencilState(depthNone)
            enc.setCullMode(.none)
            enc.setFragmentBytes(&sp, length: MemoryLayout<SkyParams>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }

        // Sky bodies (camera-relative, no depth): stars, then the textured sun and moon.
        do {
            var verts: [SimpleVert] = []
            let sd = game.sunDir
            let dusk = max(0, 1 - abs(sd.y - 0.02) / 0.22)
            if !underwater && hasSky && !game.fancyGraphics {
                // Fast: a square halo behind the sun (the Fancy sky shades its own glow).
                let c = sd * 90
                let r = simd_normalize(simd_cross(sd, V3(0, 0, 1))) * 11
                let up = simd_normalize(simd_cross(r, sd)) * 11
                let lo: V3 = c - up, hi: V3 = c + up
                let q: [V3] = [lo - r, lo + r, hi + r, hi - r]
                for i in [0, 1, 2, 0, 2, 3] { verts.append(SimpleVert(pos: V4(q[i], 1), color: V4(1.0, 0.85, 0.5, 0.18))) }
            }
            let starAlpha = game.starAlpha
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
            if !underwater && hasSky {
                // Sun (reddening at dawn/dusk) and the moon in its current phase: textured, blended, no fog.
                let bodyOff = (scratchOff + 255) & ~255
                let ptr = (scratch.contents() + bodyOff).bindMemory(to: EntityVert.self, capacity: 12)
                var bw = EntityWriter(out: ptr, capacity: 12)
                func body(_ dir: V3, _ size: Float, _ layer: Int, _ color: V4) {
                    let c = dir * 90
                    let r = simd_normalize(simd_cross(dir, V3(0, 0, 1))) * size
                    let up = simd_normalize(simd_cross(r, dir)) * size
                    bw.quad([c - r - up, c + r - up, c + r + up, c - r + up], [V2(0, 1), V2(1, 1), V2(1, 0), V2(0, 0)], layer, color)
                }
                let sunK: Float = hdrActive ? 4.5 : 1
                body(sd, 7, Int(Tex.id("sun")), V4(sunK, sunK * (1 - 0.3 * dusk), sunK * (1 - 0.55 * dusk), 1))
                body(-sd, 5, Int(Tex.id("moon_\(game.moonPhase)")), V4(1, 1, 1, 1))
                scratchOff = bodyOff + bw.n * MemoryLayout<EntityVert>.stride
                enc.setRenderPipelineState(crackPipe)
                enc.setDepthStencilState(depthNone)
                enc.setCullMode(.none)
                enc.setVertexBuffer(scratch, offset: bodyOff, index: 0)
                enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: bw.n)
            }
        }

        // Visible sections, near to far
        let pcx = floorDiv(Int(floor(eye.x)), CS), pcz = floorDiv(Int(floor(eye.z)), CS)
        let cullStart = CFAbsoluteTimeGetCurrent()
        bfsVisited = 0
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
            // Chunks around the camera in a flat grid: one dictionary lookup per column instead of one per step.
            if chunkGrid.count != span * span { chunkGrid = [Chunk?](repeating: nil, count: span * span) }
            var topSec = 0
            for dz in -R...R { for dx in -R...R {
                let c = game.world.inMeshRadius(dx, dz) ? game.world.chunks[ChunkKey(x: pcx + dx, z: pcz + dz)] : nil
                chunkGrid[(dx + R) + (dz + R) * span] = c
                if let c, c.topSec > topSec { topSec = c.topSec }
            } }
            // Above the tallest geometry in range everything is open air: walking one layer of it is enough to get
            // around anything, so the walk never climbs higher (it used to cross every empty sky section).
            let yLimit = max(pSec, topSec + 1)
            bfs.removeAll(keepingCapacity: true)
            bfs.append((startC, 0, 0, pSec, -1, 0))
            visitGen[vidx(0, 0, pSec)] = gen
            var head = 0
            let dirs = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
            while head < bfs.count {
                let (c, dx, dz, sy, entry, dirMask) = bfs[head]; head += 1
                bfsVisited += 1
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
                    if nsy < 0 || nsy >= NSEC || nsy > yLimit || !game.world.inMeshRadius(ndx, ndz) || abs(ndx) > R || abs(ndz) > R { continue }
                    let vi = vidx(ndx, ndz, nsy)
                    if visitGen[vi] == gen { continue }
                    let nmn = V3(Float((pcx + ndx) * CS), Float(nsy * 16), Float((pcz + ndz) * CS))
                    if !frustum.visible(min: nmn, max: nmn + V3(16, 16, 16)) { continue }
                    guard let nc = ox == 0 && oz == 0 ? c : chunkGrid[(ndx + R) + (ndz + R) * span], nc.meshedOnce else { continue }
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
        cullSeconds = CFAbsoluteTimeGetCurrent() - cullStart
        drawnChunks = drawnSet
        visibleSections = visibleScratch.count
        let visible = visibleScratch

        // Per-section draw records in the frame's scratch ring (origin relative to the camera + tint table
        // offset), read by instance id: a section draw is then one draw call, with buffers rebound only when
        // its mesh slab changes (base vertex = the slice's offset), instead of four calls with a constant upload.
        let recOff = (scratchOff + 255) & ~255
        let nRec = max(0, min(visible.count, (ringSize - recOff) / 16))
        if nRec > 0 {
            let recs = (scratch.contents() + recOff).bindMemory(to: SectionRec.self, capacity: nRec)
            for i in 0..<nRec {
                let (c, sy, _) = visible[i]
                recs[i] = SectionRec(x: Float(c.cx * CS) - eye.x, y: Float(sy * 16) - eye.y, z: Float(c.cz * CS) - eye.z,
                                     tint: UInt32((c.tintBuf?.offset ?? 0) / 4))
            }
            scratchOff = recOff + nRec * 16
        }
        let baseOK = baseVertexOK
        var boundVerts: MTLBuffer?, boundTints: MTLBuffer?
        drawCalls = 0; drawnQuads = 0
        func drawSection(_ i: Int, _ slice: MeshSlice, _ tb: MeshSlice, first: Int, count: Int) {
            drawCalls += 1; drawnQuads += count
            if tb.buffer !== boundTints { enc.setVertexBuffer(tb.buffer, offset: 0, index: 3); boundTints = tb.buffer }
            if baseOK {
                if slice.buffer !== boundVerts { enc.setVertexBuffer(slice.buffer, offset: 0, index: 0); boundVerts = slice.buffer }
                enc.drawIndexedPrimitives(type: .triangle, indexCount: count * 6, indexType: .uint32, indexBuffer: quadIndices,
                                          indexBufferOffset: first * 6 * 4, instanceCount: 1, baseVertex: slice.offset / 8, baseInstance: i)
            } else {
                enc.setVertexBuffer(slice.buffer, offset: slice.offset, index: 0)
                enc.setVertexBufferOffset(recOff + i * 16, index: 2)
                enc.drawIndexedPrimitives(type: .triangle, indexCount: count * 6, indexType: .uint32, indexBuffer: quadIndices,
                                          indexBufferOffset: first * 6 * 4)
            }
        }

        enc.setDepthStencilState(depthWrite)
        enc.setCullMode(.back)
        enc.setFrontFacing(.counterClockwise)
        enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.setVertexBuffer(scratch, offset: recOff, index: 2)
        // Two passes, near to far: solid cube faces without alpha test first (the GPU can then reject
        // hidden fragments before shading), then the alpha-tested cutout faces (leaves, plants, models).
        for pass in 0..<2 {
            enc.setRenderPipelineState(pass == 0 ? chunkSolidPipe : chunkPipe)
            for i in 0..<nRec {
                let (c, sy, _) = visible[i]
                let sec = c.sections[sy]
                guard sec.opaqueQuads > 0, let buf = sec.opaqueBuf, let tb = c.tintBuf else { continue }
                let total = min(sec.opaqueQuads, Renderer.maxQuads), solid = min(sec.solidQuads, total)
                let first = pass == 0 ? 0 : solid, count = pass == 0 ? solid : total - solid
                if count <= 0 { continue }
                drawSection(i, buf, tb, first: first, count: count)
            }
        }

        shipRenderer.beginFrame()
        shipRenderer.hdr = hdrActive                 // Fancy draws into the HDR target
        shipRenderer.drawOpaque(enc, ships: game.world.ships, eye: eye, u: &u, frustum: frustum, quads: quadIndices)

        // Big landmarks past the render distance (volcano impostors): opaque cone, then blended smoke.
        if hasSky && !underwater {
            var smokeStart = 0
            buildLandmarks(&landmarkVerts, smokeStart: &smokeStart, game: game, eye: eye, far: far, fog: fogColor, rd: rd)
            if !landmarkVerts.isEmpty, let off = push(landmarkVerts) {
                enc.setRenderPipelineState(simplePipe)
                enc.setCullMode(.none)
                enc.setVertexBuffer(scratch, offset: off, index: 0)
                enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                enc.setDepthStencilState(depthWrite)
                if smokeStart > 0 { enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: smokeStart) }
                enc.setDepthStencilState(depthRead)
                if landmarkVerts.count > smokeStart { enc.drawPrimitives(type: .triangle, vertexStart: smokeStart, vertexCount: landmarkVerts.count - smokeStart) }
            }
            landmarkVerts.removeAll(keepingCapacity: true)
        }

        // Mobs (written straight into the scratch ring: no per-frame arrays); Fancy wrote them before the shadow pass.
        if let pre = mobPre, hdrActive {
            MobDrawStats.path = "Fancy buffer"
            if pre.count > 0 {
                MobDrawStats.drawn += pre.count
                enc.setRenderPipelineState(mobPipe)
                enc.setDepthStencilState(depthWrite)
                enc.setCullMode(.none)
                enc.setVertexBuffer(pre.buf, offset: 0, index: 0)
                enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: pre.count)
            }
        } else if !game.mobs.mobs.isEmpty || tp || game.coop.active {
            // Fast: the same buffers (the frame's scratch ring shares its 4 MB with everything else).
            if let pre = writeMobBuffer(eye: eye, daylight: daylight, cull: frustum) {
                MobDrawStats.path = hdrActive ? "Fancy (no shadow pass)" : "Fast buffer"
                if pre.count > 0 {
                    MobDrawStats.drawn += pre.count
                    enc.setRenderPipelineState(mobPipe)
                    enc.setDepthStencilState(depthWrite)
                    enc.setCullMode(.none)
                    enc.setVertexBuffer(pre.buf, offset: 0, index: 0)
                    enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                    enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: pre.count)
                }
            } else { MobDrawStats.path = "no mob buffer" }
        }

        // Dropped items and the crack overlay (written straight into the scratch ring)
        do {
            let entOff = (scratchOff + 255) & ~255
            let stride = MemoryLayout<EntityVert>.stride
            let entCap = max(0, ringSize - ringTailReserve - entOff) / stride
            entityStats = (entCap, 0, 0)
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
                game.writeFalling(&wr, eye: eye)
                game.world.ships.writeShells(&wr, eye: eye)
                let preDecor = wr.n
                game.writeDecor(&wr, eye: eye)
                entityStats = (entCap, preDecor, wr.n)
                game.writeBobber(&wr, eye: eye, right: right, up: -up)
                game.writeLeads(&wr, eye: eye)
                game.writeBanners(&wr, eye: eye)
                game.writeRockets(&wr, eye: eye)
                game.writeArms(&wr, eye: eye)
                game.writeLecternBooks(&wr, eye: eye)
                game.writeShelves(&wr, eye: eye)
                game.particles.write(&wr, eye: eye, right: right, up: -up, world: game.world, daylight: daylight)
                let nItems = wr.n
                // Blended pass: entity shadows, rain / snow / lightning glow, then the crack overlay.
                game.writeShadows(&wr, eye: eye)
                game.writeWeather(&wr, eye: eye)
                // (A chipped block shows its missing pieces instead of the crack overlay.)
                if let m = game.mining, game.mineProgress > 0, game.world.damageLevel(m) == 0 {
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

        shipRenderer.drawBeforeWater(enc, ships: game.world.ships, world: game.world, eye: eye, u: &u, frustum: frustum)

        if let sp = split { enc = sp(.afterOpaque, enc) }
        // Water, far to near
        enc.setRenderPipelineState(waterPipe)
        enc.setDepthStencilState(depthRead)
        enc.setCullMode(.none)
        enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        // Other passes (mobs, entities, outline) rebound buffers 0 and 2.
        enc.setVertexBuffer(scratch, offset: recOff, index: 2)
        boundVerts = nil; boundTints = nil
        for i in stride(from: nRec - 1, through: 0, by: -1) {
            let (c, sy, _) = visible[i]
            let sec = c.sections[sy]
            guard sec.transQuads > 0, let buf = sec.transBuf, let tb = c.tintBuf else { continue }
            drawSection(i, buf, tb, first: 0, count: min(sec.transQuads, Renderer.maxQuads))
        }

        shipRenderer.drawTranslucent(enc, ships: game.world.ships, eye: eye, u: &u, frustum: frustum, quads: quadIndices)

        // Cloud layer (after water so both blend over terrain; depth-tested against terrain).
        if !underwater && hasSky, game.fancyGraphics, let cm = clouds {
            // Fancy: shaded boxes. Depth-written so blobs occlude each other instead of double-blending.
            let ext = far
            let wind = Float((game.time * 1.3).truncatingRemainder(dividingBy: 12 * 8192))
            let cs = CloudMesh.cell
            let ccx = Int(floor((eye.x + wind) / cs)), ccz = Int(floor(eye.z / cs))
            let n = cm.update(centerX: ccx, centerZ: ccz, radius: min(32, Int(ext / cs) + 1))
            if n > 0 {
                var off = V4(-wind - eye.x, CLOUD_Y - eye.y, -eye.z, 0)
                var cp = V4(0, 0, ext * 0.95, 0)
                enc.setRenderPipelineState(cloudBoxPipe)
                enc.setDepthStencilState(depthWrite)
                enc.setCullMode(.back)
                enc.setVertexBuffer(cm.buffer, offset: 0, index: 0)
                enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                enc.setVertexBytes(&off, length: 16, index: 2)
                enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                enc.setFragmentBytes(&cp, length: 16, index: 2)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: n)
            }
        } else if !underwater && hasSky {
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
        // Both are written without per-vertex bounds checks, so the pass only runs when its worst case
        // (1024 arm / gun vertices + 64 held-item vertices) fits in what is left of the ring.
        let firstPersonEnd = ((scratchOff + 255) & ~255) + 1024 * MemoryLayout<MobVert>.stride + 256 + 64 * MemoryLayout<EntityVert>.stride
        if drawHUD && !game.hideHUD && !tp && game.menu == nil && game.sleeping == 0 && firstPersonEnd <= ringSize {
            var uh = u
            uh.viewProj = perspectiveRH(fovy: 70 * .pi / 180, aspect: W / max(H, 1), near: 0.01, far: 8)
            uh.fogColor.w = 100; uh.params.x = 200
            if game.player.headInWater {
                // Under water the arm and held item take on the water's colour like everything else (they stayed in
                // full daylight colours: critic, underwater.png).
                // About a fifth of the way to the water colour at arm's length (at a third and more the held block
                // read as a textureless navy box in deep water: blind critic, run 373 seabed_deep).
                let f = game.underwaterFog
                uh.fogColor = V4(f.x, f.y, f.z, -1); uh.params.x = 6
            }
            let ey = Int(floor(eye.y)) + (Blocks.opaque[Int(game.world.block(Int(floor(eye.x)), Int(floor(eye.y)), Int(floor(eye.z))))] ? 1 : 0)
            let l = game.world.lightAt(Int(floor(eye.x)), ey, Int(floor(eye.z)))
            // Skylight keeps a moonlit floor like the terrain's night ambient (the held block was a black cube on a
            // moonlit meadow: blind critic, run 395 torches).
            let skyK: Float = 0.12 + 0.88 * daylight          // ~0.22 at night: 0.38 read 3x the terrain (critic, run 417)
            let fill: Float = max(0.12, MobLight.fill)                                    // the cave fill at arm's length
            let light = max(fill, max(Float(l.sky) / 15 * skyK, Float(l.block) / 15), game.nightVision * 0.9)
            let sw = game.swing
            let a = sinf(sqrtf(sw) * .pi)
            let bob = sinf(game.walkBob * 2) * 0.02 * game.walkAmount
            let base = V3(0.5 - 0.25 * a, -0.4 + 0.12 * sinf(sqrtf(sw) * 2 * .pi) + bob - 0.45 * game.equipAnim, -0.8 - 0.15 * sinf(sw * .pi))
            let held = game.held
            // Arm (skin-coloured box angled up into the screen).
            let armOff = (scratchOff + 255) & ~255
            let armPtr = (scratch.contents() + armOff).bindMemory(to: MobVert.self, capacity: 1024)
            var an = 0
            let skin = V3(0.84, 0.64, 0.5)
            let axL = simd_normalize(V3(-0.12, 0.62, -0.78)) * (held.isEmpty ? 0.36 : 0.3)
            let axW = V3(0.075, 0, 0.03), axD = simd_normalize(simd_cross(axL, axW)) * 0.075
            let ac = base + V3(0.12, -0.34, 0.3) + (held.isEmpty ? V3(-0.05, 0.12, -0.1) : .zero)
            let CT = Mesher.cornerTable
            let faceShade: [Float] = [0.8, 0.8, 1.0, 0.55, 0.68, 0.68]
            // Sleeve over the upper (shoulder) half: tunic colour, or the chestplate's when armour is worn.
            let chest = game.inventory.armor[1]
            let sleeve = chest.isEmpty ? V3(0.62, 0.26, 0.16) : (ArmorLook.color(chest.item) ?? V3(0.62, 0.26, 0.16))
            let boxes: [(V3, Float, Float, V3, Float)] = [(ac, 1, 1, skin, 4), (ac - axL * 0.45, 0.56, 1.1, sleeve, 2)]
            for (c0, lenK, thick, col, pat) in boxes {
                for f in 0..<6 {
                    for k in [0, 1, 2, 0, 2, 3] {
                        let ci = (f * 4 + k) * 3
                        let pp = c0 + axW * (Float(CT[ci] * 2 - 1) * thick) + axL * (Float(CT[ci + 1] * 2 - 1) * lenK) + axD * (Float(CT[ci + 2] * 2 - 1) * thick)
                        armPtr[an] = MobVert(pos: V4(pp, pat), color: V4(col, faceShade[f] * light), local: V4(pp * 32, 0))
                        an += 1
                    }
                }
            }
            // Guns are drawn as solid models (aiming moves them to the centre of the view).
            let gunIndex = game.heldGun
            if let gi = gunIndex, !game.sniperScoped {
                let reloadDip: Float = game.arms.reload > 0 ? min(1, game.arms.reload * 3, (Guns.reloadTime(game.held, gi) - game.arms.reload) * 3) : 0
                an += Guns.writeFirstPerson(gi, aim: game.arms.aim, kick: game.arms.kick, lower: reloadDip * 0.35 + game.equipAnim,
                                            bob: V3(0, bob, 0), light: light, rounds: game.arms.reload > 0 ? 0 : game.held.tag, into: armPtr + an)
            }
            scratchOff = armOff + an * MemoryLayout<MobVert>.stride
            enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(VW), height: Double(VH), znear: 0, zfar: 0.001))
            enc.setDepthStencilState(depthWrite)
            enc.setCullMode(.none)
            enc.setRenderPipelineState(mobPipe)
            enc.setVertexBuffer(scratch, offset: armOff, index: 0)
            enc.setVertexBytes(&uh, length: MemoryLayout<Uniforms>.stride, index: 1)
            enc.setFragmentBytes(&uh, length: MemoryLayout<Uniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: an)
            if !held.isEmpty && gunIndex == nil {
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
            enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(VW), height: Double(VH), znear: 0, zfar: 1))
        }

        if let sp = split { enc = sp(.beforeHUD, enc) }
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
        return enc
    }

    func bowPull() -> Float { Items.key(game.held.item) == "bow" ? min(1, game.bowCharge) * 0.12 : 0 }

    // MARK: HUD (pixel coordinates, origin top-left)

    var hudScale: Float = 2
    private var hudScratch: [HudVert] = []

    func buildHUD(_ W: Float, _ H: Float) -> [HudVert] {
        // The vertex array keeps its storage from frame to frame (it grew from empty every frame: profile).
        var v = hudScratch
        hudScratch = []
        v.removeAll(keepingCapacity: true)
        defer { hudScratch = v }
        let L = HudLayout(W, H)
        let s = L.s
        hudScale = s
        self.game.screen = V2(W, H)
        func quad(_ p: [V2], _ uv: [V2], _ c: V4, _ layer: Float) {
            let ex = V4(layer, 0, 0, 0)
            v.append(HudVert(pos: p[0], uv: uv[0], color: c, extra: ex)); v.append(HudVert(pos: p[1], uv: uv[1], color: c, extra: ex))
            v.append(HudVert(pos: p[2], uv: uv[2], color: c, extra: ex)); v.append(HudVert(pos: p[0], uv: uv[0], color: c, extra: ex))
            v.append(HudVert(pos: p[2], uv: uv[2], color: c, extra: ex)); v.append(HudVert(pos: p[3], uv: uv[3], color: c, extra: ex))
        }
        // An axis-aligned textured quad (text glyphs) without building corner arrays.
        func glyphQuad(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ u1: Float, _ v1: Float, _ c: V4, _ layer: Float) {
            let ex = V4(layer, 0, 0, 0)
            let a = HudVert(pos: V2(x, y), uv: V2(0, 0), color: c, extra: ex), b = HudVert(pos: V2(x + w, y), uv: V2(u1, 0), color: c, extra: ex)
            let d = HudVert(pos: V2(x + w, y + h), uv: V2(u1, v1), color: c, extra: ex), e = HudVert(pos: V2(x, y + h), uv: V2(0, v1), color: c, extra: ex)
            v.append(a); v.append(b); v.append(d); v.append(a); v.append(d); v.append(e)
        }
        // Plain rectangles (most of the HUD: panels, bars, the minimap) without building corner arrays.
        func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ c: V4) {
            let z = V2(0, 0), ex = V4(-1, 0, 0, 0)
            let a = V2(x, y), b = V2(x + w, y), d = V2(x + w, y + h), e = V2(x, y + h)
            v.append(HudVert(pos: a, uv: z, color: c, extra: ex)); v.append(HudVert(pos: b, uv: z, color: c, extra: ex))
            v.append(HudVert(pos: d, uv: z, color: c, extra: ex)); v.append(HudVert(pos: a, uv: z, color: c, extra: ex))
            v.append(HudVert(pos: d, uv: z, color: c, extra: ex)); v.append(HudVert(pos: e, uv: z, color: c, extra: ex))
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
                        Glyphs.cap(cx, y, Float(w + 5) * scale, scale, baseColor.w, rect: rect)      // 3 in, label, 2 out (Glyphs.advance)
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
                    let rows = Float(Font.rows(code))                 // 8 for g j p q y (a row below the baseline)
                    let layer = Float(Font.layerBase + code - 32)
                    func g(_ ox: Float, _ oy: Float, _ c: V4) { glyphQuad(cx + ox, y + oy, w * scale, rows * scale, w / 16, rows / 16, c, layer) }
                    if shadow { g(scale, scale, V4(color.x * 0.25, color.y * 0.25, color.z * 0.25, color.w)) }
                    g(0, 0, color)
                }
                cx += adv * scale
            }
        }
        func textWidth(_ str: String, _ scale: Float) -> Float { Float(Font.width(str)) * scale }

        if let t = HudExtras.loading {
            // Loading screen: dirt-dark backdrop, big title, the world name.
            rect(0, 0, W, H, V4(0.09, 0.07, 0.06, 1))
            let big = s * 2
            text("BLOCKSMITH", floor((W - textWidth("BLOCKSMITH", big * 2)) / 2), H * 0.3, big * 2, V4(0.86, 0.78, 0.55, 1))
            text(t, floor((W - textWidth(t, big)) / 2), H * 0.55, big)
            return v
        }
        if game.player.headInWater { rect(0, 0, W, H, V4(0.05, 0.15, 0.45, 0.18)) }
        if game.player.headInLava { rect(0, 0, W, H, V4(0.9, 0.3, 0.02, 0.45)) }
        if game.sleeping > 0 { rect(0, 0, W, H, V4(0.02, 0.02, 0.06, min(1, game.sleeping / 1.5))) }
        let fx: Float = Settings.shared.screenEffects ? 1 : 0.3       // Accessibility > Screen Flashes
        if game.hurtFlash > 0 { rect(0, 0, W, H, V4(0.75, 0.02, 0.02, min(0.45, game.hurtFlash * 1.3) * fx)) }
        if game.portalTime > 0 { rect(0, 0, W, H, V4(0.45, 0.1, 0.8, min(0.7, game.portalTime / 4 * 0.7) * fx)) }
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
            for (i, line) in (game.creditsAsh ? AshWar.epilogue : Game.creditsLines).enumerated() {
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
            if let a = game.ashBossBar() { bars.append((a.0, a.1, V4(0.8, 0.1, 0.08, 1))) }
            for b in game.shipBars() { bars.append((b.0, b.1, V4(0.75, 0.6, 0.3, 1))) }
            for (i, b) in bars.enumerated() {
                let bw = 182 * s, bx = (W - bw) / 2, by = L.insetY + 12 * s + Float(i) * 19 * s
                text(b.0, (W - textWidth(b.0, s)) / 2, by - 9 * s, s)
                rect(bx, by, bw, 5 * s, V4(b.2.x * 0.3, b.2.y * 0.3, b.2.z * 0.3, 1))
                rect(bx, by, bw * max(0, min(1, b.1)), 5 * s, b.2)
            }
            // Piloting gauges (speed, altitude, throttle, hull, guns) are drawn by CombatHUD.swift; shipHUDLine stays for the harness.
        }

        func frame(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ b: Float, _ c: V4) {
            rect(x, y, w, b, c)
            rect(x, y + h - b, w, b, c)
            rect(x, y, b, h, c)
            rect(x + w - b, y, b, h, c)
        }
        // A pixel-art arrow pointing right (crafting result): a shaft and a stepped head, `len` long, centred on cy.
        // `upTo` (0...1) draws only that much of it from the left (progress fills).
        func arrowRight(_ x: Float, _ cy: Float, _ len: Float, _ s: Float, _ c: V4, upTo: Float = 1) {
            let head: Float = 5 * s
            let end: Float = x + len * max(0, min(1, upTo))
            let shaftEnd: Float = min(end, x + len - head)
            if shaftEnd > x { rect(x, cy - 1.5 * s, shaftEnd - x, 3 * s, c) }
            for i in 0..<5 {
                let fi = Float(i)
                let cx0: Float = x + len - head + fi * s
                guard cx0 < end else { break }
                let hh: Float = (9 - 2 * fi) * s
                rect(cx0, cy - hh / 2, s, hh, c)
            }
        }
        // The same arrow pointing down (brewing), centred on cx, filling from the top.
        func arrowDown(_ cx: Float, _ y: Float, _ len: Float, _ s: Float, _ c: V4, upTo: Float = 1) {
            let head: Float = 5 * s
            let end: Float = y + len * max(0, min(1, upTo))
            let shaftEnd: Float = min(end, y + len - head)
            if shaftEnd > y { rect(cx - 1.5 * s, y, 3 * s, shaftEnd - y, c) }
            for i in 0..<5 {
                let fi = Float(i)
                let ry: Float = y + len - head + fi * s
                guard ry < end else { break }
                let ww: Float = (9 - 2 * fi) * s
                rect(cx - ww / 2, ry, ww, s, c)
            }
        }
        // A pixel-art flame 13 x 13 (furnace fuel): `level` 0...1 burns down from the top.
        func flame(_ x: Float, _ y: Float, _ s: Float, level: Float) {
            let rows: [(Int, Int)] = [(6, 7), (5, 8), (5, 8), (4, 9), (3, 9), (3, 10), (2, 10), (2, 11), (2, 11), (2, 11), (3, 10), (3, 10), (4, 9)]
            let cut: Int = Int((1 - max(0, min(1, level))) * 13)
            for (r, span) in rows.enumerated() {
                let fy: Float = y + Float(r) * s
                rect(x + Float(span.0) * s, fy, Float(span.1 - span.0) * s, s, V4(0.42, 0.42, 0.42, 1))
                guard r >= cut else { continue }
                let hot: Float = Float(r) / 12
                let col = V4(1, 0.35 + 0.45 * hot, 0.08 + 0.2 * hot, 1)
                rect(x + Float(span.0) * s, fy, Float(span.1 - span.0) * s, s, col)
            }
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
                        if game.dim.dim != .overworld && game.dim.dim != .deep && ik == "compass" { ang = Float(game.clock * 7).truncatingRemainder(dividingBy: 2 * .pi) }
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
                // At TV scales a slightly smaller count covers less of the icon and stays above 14 px at 1080p (the
                // counts hid half of each hotbar icon: blind critic, tv_hud).
                var cs: Float = s
                if s >= 3 { cs = s * 0.8 } else if s >= 2 { cs = s * 0.85 }
                let t = "\(st.count)"
                let tx: Float = x + size - textWidth(t, cs) - cs * 0.5 + s
                let ty: Float = y + size - 7 * cs
                // A dark outline round the digits (white on the grey slot was 3.4:1, under the 4.5:1 the spec asks:
                // blind critic, inventory); the bottom row no longer runs past the slot.
                let o: Float = max(1, cs * 0.5)
                for (ox, oy) in [(-o, 0), (o, 0), (0, -o), (0, o)] as [(Float, Float)] {
                    text(t, tx + ox, ty + oy, cs, V4(0.1, 0.1, 0.1, 0.85), shadow: false)
                }
                text(t, tx, ty, cs)
            }
        }

        // Positioned text / boxes / item icons from HudExtras, CombatHUD, the map (HudLine).
        func drawHudLine(_ l: HudLine) {
            if let b = l.bg {
                if let box = l.box { rect(l.x, l.y, box.x, box.y, b) }
                else { rect(l.x - 3 * l.scale, l.y - 3 * l.scale, textWidth(l.text, l.scale) + 6 * l.scale, 13 * l.scale, b) }
            }
            if let it = l.item { itemIcon(it, l.x, l.y, l.box?.x ?? 16 * l.scale) }
            if !l.text.isEmpty { text(l.text, l.x, l.y, l.scale, l.color) }
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
                // A flame that burns down and an arrow that fills (a bar and an orange square didn't read as
                // progress: blind UI critic, furnace).
                let fx = o.x + 57 * s, fy = o.y + 37 * s
                var k: Float = 0
                if f.be.burn > 0 && f.be.burnMax > 0 { k = Float(f.be.burn) / Float(f.be.burnMax) }
                flame(fx, fy, s, level: k)
                let ax = o.x + 79 * s, ay = o.y + 34 * s
                arrowRight(ax, ay + 8 * s, 24 * s, s, V4(0.5, 0.5, 0.5, 1))
                arrowRight(ax, ay + 8 * s, 24 * s, s, V4(1, 1, 1, 1), upTo: Float(f.be.cook) / 200)
            }
            if let im = m as? InventoryMenu, game.effects.any {
                var y = o.y
                // Left of the recipe-book toggle (the list ran under it: run 362 inventory shot), and of the open book.
                // Clear of the "Craft" label too, which is wider than its button (inventory shot: the list touched it).
                let craftLabel: Float = 4 * s + textWidth("Craft", s) + 3 * s
                let right: Float = im.book.open ? o.x - 126 * s : o.x - max(26 * s, craftLabel)
                for (e, a) in game.effects.active {
                    let bw = 120 * s
                    let bx = right - bw
                    guard bx > 0 else { break }
                    rect(bx, y, bw, 32 * s, V4(0.776, 0.776, 0.776, 1))
                    frame(bx, y, bw, 32 * s, s, V4(0.2, 0.2, 0.2, 1))
                    quad([V2(bx + 6 * s, y + 7 * s), V2(bx + 24 * s, y + 7 * s), V2(bx + 24 * s, y + 25 * s), V2(bx + 6 * s, y + 25 * s)],
                         [V2(0, 0), V2(1, 0), V2(1, 1), V2(0, 1)], V4(1, 1, 1, 1), Float(Tex.id("effect_" + e.key)))
                    // Dark text on the light panel like the menu titles (white and mid-grey read poorly: blind critic,
                    // inventory).
                    let label: String = e.name + (a.amp > 0 ? " " + Effect.roman(a.amp + 1) : "")
                    text(label, bx + 28 * s, y + 7 * s, s, V4(0.18, 0.18, 0.2, 1), shadow: false)
                    let secs = Int(min(1e6, max(0, a.time)))          // converted only in range (an infinite effect overflowed Int)
                    let left: String = a.time > 1e6 ? "Infinite" : String(format: "%d:%02d", secs / 60, secs % 60)
                    text(left, bx + 28 * s, y + 18 * s, s, V4(0.3, 0.3, 0.33, 1), shadow: false)
                    y += 33 * s
                }
            }
            if m is InventoryMenu {
                rect(o.x + 26 * s, o.y + 8 * s, 50 * s, 70 * s, V4(0, 0, 0, 1))
                rect(o.x + 27 * s, o.y + 9 * s, 48 * s, 68 * s, V4(0.35, 0.35, 0.38, 1))
                playerPreview(x: o.x + 27 * s, y: o.y + 9 * s, w: 48 * s, h: 68 * s, quad)
                text("Crafting", o.x + 97 * s, o.y + 7 * s, s, titleC, shadow: false)
                text("Open the book", o.x + 97 * s, o.y + 20 * s, s, V4(0.3, 0.3, 0.33, 1), shadow: false)
                text("to craft", o.x + 97 * s, o.y + 30 * s, s, V4(0.3, 0.3, 0.33, 1), shadow: false)
                if let im = m as? InventoryMenu, let sb = im.slots.first(where: { if case .button(let i) = $0.kind { return i == InventoryMenu.searchBtn } else { return false } }) {
                    let x = o.x + Float(sb.x) * s, y = o.y + Float(sb.y) * s
                    rect(x, y, Float(sb.w) * s, Float(sb.h) * s, game.menuHover === sb ? V4(0.2, 0.32, 0.68, 1) : (im.searching ? V4(0.12, 0.12, 0.14, 1) : V4(0.36, 0.36, 0.4, 1)))
                    let caret = im.searching && Int(game.clock * 2) % 2 == 0 ? "_" : ""
                    var t = im.query.isEmpty && !im.searching ? "Search..." : im.query + caret
                    while textWidth(t, s) > Float(sb.w - 4) * s && t.count > 1 { t.removeFirst() }
                    text(t, x + 2 * s, y + 3 * s, s, im.query.isEmpty && !im.searching ? V4(0.85, 0.85, 0.85, 1) : V4(1, 1, 0.7, 1))
                    if !im.query.isEmpty {
                        let n = im.slots.filter { $0.isPlayerInv && im.matches($0.stack) }.count
                        text(n == 0 ? "Not carried" : "\(n) found", o.x + 97 * s, o.y + 46 * s, s, n == 0 ? V4(0.6, 0.12, 0.1, 1) : V4(0.1, 0.42, 0.12, 1), shadow: false)
                    }
                }
            }
            if m is CraftingTableMenu { arrowRight(o.x + 89 * s, o.y + 36 * s, 24 * s, s, V4(0.5, 0.5, 0.5, 1)) }
            if let b = m as? BrewingMenu {
                // Cinderwisp fuel bar, brew progress (downward arrow) and bubbles.
                rect(o.x + 60 * s, o.y + 44 * s, 18 * s, 4 * s, V4(0.3, 0.3, 0.3, 1))
                rect(o.x + 60 * s, o.y + 44 * s, 18 * s * Float(b.be.fuel) / 20, 4 * s, V4(1, 0.6, 0.1, 1))
                // A down arrow that fills as it brews (a white bar flush against the slot read as a glitch: blind UI
                // critic, brewing).
                arrowDown(o.x + 101.5 * s, o.y + 16 * s, 26 * s, s, V4(0.5, 0.5, 0.5, 1))
                if b.be.brewTime > 0 {
                    let k = 1 - Float(b.be.brewTime) / 400
                    arrowDown(o.x + 101.5 * s, o.y + 16 * s, 26 * s, s, V4(1, 1, 1, 1), upTo: k)
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
                // Faint lines of writing on both pages and a spine shadow (blank pages read as an empty box: blind UI critic).
                rect(o.x + 29 * s, o.y + 16 * s, 2 * s, 22 * s, V4(0.62, 0.55, 0.45, 1))
                for ln in 0..<6 {
                    let ly: Float = o.y + Float(19 + ln * 3) * s
                    let lw1: Float = Float(9 + (ln * 5) % 4) * s, lw2: Float = Float(8 + (ln * 7) % 5) * s
                    rect(o.x + 16 * s, ly, lw1, s, V4(0.55, 0.5, 0.62, 1))
                    rect(o.x + 33 * s, ly, lw2, s, V4(0.55, 0.5, 0.62, 1))
                }
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
                    // Cost on a dark badge, padded from the row border (lime on lavender was 2.6:1 and touched the
                    // border: blind UI critic, enchant).
                    let ct = "\(e.costs[i])"
                    let cw: Float = textWidth(ct, s)
                    rect(bx + 102 * s - cw, by + 8 * s, cw + 3 * s, 9 * s, V4(0.12, 0.1, 0.16, 0.9))
                    text(ct, bx + 103.5 * s - cw, by + 9 * s, s, ok ? Settings.shared.goodColor : Settings.shared.badColor * V4(0.6, 0.6, 0.6, 1))
                    if let c = e.clues[i] {
                        // The clue is one enchantment the offer holds, maybe with more: "Unbreaking II +?" (a bare "?" read
                        // as a placeholder), cut to stay clear of the cost badge.
                        let line = Enchant.displayLine(c.0, c.1)
                        var clue = line + " +?"
                        if textWidth(clue, s) > 80 * s {
                            var cut = line
                            while textWidth(cut + "..+?", s) > 80 * s && cut.count > 3 { cut.removeLast() }
                            clue = cut + "..+?"
                        }
                        text(clue, bx + 18 * s, by + 3 * s, s, ok ? V4(0.12, 0.08, 0.2, 1) : V4(0.22, 0.22, 0.22, 1), shadow: false)
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
                arrowRight(o.x + 100 * s, o.y + 55 * s, 24 * s, s, V4(0.5, 0.5, 0.5, 1))
                if a.cost > 0 {
                    // On a dark plate under the output, clear of the "Inventory" label (lime on the grey panel was 1.3:1
                    // and ran into the label: blind UI critic, anvil).
                    let t = a.tooExpensive ? "Too Expensive!" : "Cost: \(a.cost) levels"
                    let ok = !a.tooExpensive && (!game.survival || game.xpLevel >= a.cost)
                    let tw: Float = textWidth(t, s)
                    let tx: Float = o.x + 168 * s - tw
                    rect(tx - 3 * s, o.y + 67 * s, tw + 6 * s, 11 * s, V4(0.12, 0.12, 0.14, 0.9))
                    text(t, tx, o.y + 69 * s, s, ok ? Settings.shared.goodColor : Settings.shared.badColor)
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
                rect(o.x + Float(b.x) * s, o.y + Float(b.y) * s, 50 * s, 16 * s, game.menuHover === b ? V4(0.2, 0.32, 0.68, 1) : V4(0.36, 0.36, 0.4, 1))
                text("Done", o.x + Float(b.x + 13) * s, o.y + Float(b.y + 4) * s, s)
            }
            if let bm = m as? BookMenu {
                // Parchment page with wrapped text, page counter and buttons.
                // The page starts under the panel title (it covered all but "Boo": blind UI critic, book).
                rect(o.x + 24 * s, o.y + 16 * s, 144 * s, 160 * s, V4(0.93, 0.89, 0.78, 1))
                rect(o.x + 24 * s, o.y + 16 * s, 144 * s, 3 * s, V4(0.55, 0.38, 0.22, 1))
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
                    text(pg, o.x + 160 * s - textWidth(pg, s), o.y + 22 * s, s, V4(0.35, 0.3, 0.25, 1), shadow: false)
                    var lines = Books.wrap(bm.pages[bm.page])
                    if bm.editable && Int(game.clock * 2) % 2 == 0 { if lines.isEmpty { lines = ["_"] } else { lines[lines.count - 1] += "_" } }
                    for (i, l) in lines.prefix(Books.linesPerPage).enumerated() {
                        text(l, o.x + 36 * s, o.y + Float(33 + i * 9) * s, s, ink, shadow: false)
                    }
                }
                for sl in bm.slots where sl.isButton {
                    guard case .button(let i) = sl.kind else { continue }
                    let x = o.x + Float(sl.x) * s, y = o.y + Float(sl.y) * s
                    let label = [0: "<", 1: ">", 2: bm.signing ? "Sign" : "Done", 3: "Sign", 6: "Take"][i] ?? ""
                    if i == 3 && bm.signing { continue }
                    // Darker grey and the focus blue under white text (the hover grey measured 2.1:1: blind UI critic, book).
                    rect(x, y, Float(sl.w) * s, Float(sl.h) * s, game.menuHover === sl ? V4(0.2, 0.32, 0.68, 1) : V4(0.36, 0.36, 0.4, 1))
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
                        // The inventory's way into its crafting book (LB/RB too): labelled, an icon alone was easy to miss.
                        if m is InventoryMenu {
                            // Right-aligned to the button: centred, the label (wider than the button) ran under the panel.
                            let lw = textWidth("Craft", s)
                            text("Craft", x + Float(sl.w) * s - lw, y + Float(sl.h + 2) * s, s, hot ? V4(1, 1, 0.7, 1) : V4(1, 1, 1, 1))
                        }
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
                        rect(x, y, Float(sl.w) * s, Float(sl.h) * s, hot ? V4(0.2, 0.32, 0.68, 1) : V4(0.36, 0.36, 0.4, 1))
                        let label = id == 491 ? "<" : (id == 492 ? ">" : (book.craftableOnly ? "Can" : "All"))
                        text(label, x + (Float(sl.w) * s - textWidth(label, s)) / 2, y + 3 * s, s)
                    }
                }
            }
            if let km = m as? KeyboardMenu {
                // Live preview of the text being edited.
                let pv = km.preview
                text(pv.label, o.x + 8 * s, o.y + 6 * s, s, V4(0.25, 0.25, 0.25, 1), shadow: false)
                rect(o.x + 8 * s, o.y + 16 * s, 160 * s, 13 * s, V4(0, 0, 0, 1))
                rect(o.x + 9 * s, o.y + 17 * s, 158 * s, 11 * s, V4(0.08, 0.08, 0.08, 1))
                var pt = pv.text
                while textWidth(pt, s) > 150 * s && !pt.isEmpty { pt.removeFirst() }
                text(pt + (Int(game.clock * 2) % 2 == 0 ? "_" : ""), o.x + 12 * s, o.y + 19 * s, s, V4(0.95, 0.95, 0.95, 1))
                for (i, sl) in km.slots.enumerated() where i < km.keys.count {
                    let x = o.x + Float(sl.x) * s, y = o.y + Float(sl.y) * s
                    let hot = game.menuHover === sl
                    rect(x, y, Float(sl.w) * s, Float(sl.h) * s, hot ? V4(0.2, 0.32, 0.68, 1) : V4(0.45, 0.45, 0.5, 1))
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
                // Suggestions (Tab or click): the completed name with its underscores, underlined like a link.
                let sug = cm.suggestions
                for sl in cm.slots where sl.isButton {
                    guard case .button(let i) = sl.kind, i >= CommandMenu.suggestBase else { continue }
                    let k = i - CommandMenu.suggestBase
                    guard k < sug.count else { continue }
                    let x = o.x + Float(sl.x) * s, y = o.y + Float(sl.y) * s
                    rect(x, y, Float(sl.w) * s, Float(sl.h) * s, game.menuHover === sl ? V4(0.2, 0.32, 0.68, 1) : V4(0.18, 0.18, 0.22, 1))
                    var t = sug[k]
                    while textWidth(t, s) > Float(sl.w - 4) * s && t.count > 2 { t = String(t.dropLast(2)) + "." }
                    text(t, x + 2 * s, y + 2 * s, s, k == 0 ? V4(1, 1, 0.6, 1) : V4(0.85, 0.85, 0.85, 1))
                    rect(x + 2 * s, y + 10 * s, textWidth(t, s), s, k == 0 ? V4(1, 1, 0.6, 0.8) : V4(0.6, 0.6, 0.6, 0.6))
                }
                // The log, newest at the bottom; long lines (coordinates) wrap instead of being cut off.
                let logY: Float = sug.isEmpty ? 32 : 45, logH: Float = sug.isEmpty ? 100 : 87
                rect(o.x + 8 * s, o.y + logY * s, 264 * s, logH * s, V4(0.12, 0.12, 0.14, 0.85))
                var wrapped: [(String, V4)] = []
                for l in game.commandLog.suffix(12) {
                    let c = l.hasPrefix("  ") ? V4(0.75, 0.75, 0.75, 1) : (l.hasPrefix("/") ? V4(1, 1, 0.55, 1) : V4(1, 1, 1, 1))
                    var rest = Substring(l)
                    while !rest.isEmpty {
                        var n = rest.count
                        while n > 1 && textWidth(String(rest.prefix(n)), s) > 258 * s { n -= 1 }
                        if n < rest.count, let sp = rest.prefix(n).lastIndex(of: " "), rest.distance(from: rest.startIndex, to: sp) > 8 {
                            n = rest.distance(from: rest.startIndex, to: sp) + 1
                        }
                        wrapped.append((String(rest.prefix(n)), c))
                        rest = rest.dropFirst(n)
                        if !rest.isEmpty { rest = Substring("    " + rest) }
                    }
                }
                let fit = Int((logH - 4) / 11)
                for (i, (t, c)) in wrapped.suffix(fit).enumerated() {
                    text(t, o.x + 11 * s, o.y + Float(Int(logY) + 3 + i * 11) * s, s, c)
                }
                if game.commandLog.isEmpty { text("Type /help, Tab completes names", o.x + 11 * s, o.y + (logY + 3) * s, s, V4(0.6, 0.6, 0.6, 1)) }
                for sl in cm.slots where sl.isButton {
                    guard case .button(let i) = sl.kind, i < CommandMenu.buttons.count else { continue }
                    let x = o.x + Float(sl.x) * s, y = o.y + Float(sl.y) * s
                    let hot = game.menuHover === sl
                    rect(x, y, Float(sl.w) * s, Float(sl.h) * s, hot ? V4(0.2, 0.32, 0.68, 1) : V4(0.42, 0.42, 0.46, 1))
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
                    rect(x, y, Float(sl.w) * s, Float(sl.h) * s, hot ? V4(0.2, 0.32, 0.68, 1) : V4(0.42, 0.42, 0.46, 1))
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
                // Controller status along the bottom edge (inside the safe area).
                let pads = PadManager.shared
                let status = pads.connected ? Glyph.a.s + " " + pads.name + " ready" + (pads.battery.map { "  (battery \(Int($0 * 100))%)" } ?? "")
                    : "Connect a controller any time, or play with keyboard and mouse"
                text(status, floor((W - textWidth(status, s)) / 2), H - ML.insetY - 12 * s, s, V4(0.9, 0.9, 0.9, 0.9))
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
                    rect(x, y, Float(sl.w) * s, Float(sl.h) * s, info ? V4(0.3, 0.3, 0.33, 1) : (hot ? V4(0.2, 0.32, 0.68, 1) : V4(0.42, 0.42, 0.46, 1)))
                    frame(x, y, Float(sl.w) * s, Float(sl.h) * s, s, hot ? V4(1, 1, 1, 1) : V4(0.2, 0.2, 0.22, 1))
                    let label = r.0
                    // Long labels (remapped buttons, long values) shrink to fit between the value arrows.
                    let ls = min(s, (Float(sl.w) - 20) * s / max(1, textWidth(label, s)) * s)
                    let lx = info ? x + 5 * s : x + (Float(sl.w) * s - textWidth(label, ls)) / 2
                    text(label, lx, y + (Float(sl.h) * s - 7 * ls) / 2, ls)
                    if hot && PauseMenu.isValue(r.1) {
                        // Arrows: D-pad left / right steps the setting.
                        text("<", x + 4 * s, y + (Float(sl.h) - 7) / 2 * s, s, V4(1, 1, 0.6, 1))
                        text(">", x + Float(sl.w) * s - 8 * s, y + (Float(sl.h) - 7) / 2 * s, s, V4(1, 1, 0.6, 1))
                    }
                }
                if pm.rows.count > pm.slots.count, let first = pm.slots.first, let last = pm.slots.last {
                    // Scroll position: a thin scrollbar beside the list (dots under it read as pages next to "Page 2 of 6":
                    // blind UI critic, options).
                    let n = pm.rows.count - pm.slots.count + 1
                    let top: Float = o.y + Float(first.y) * s, bottom: Float = o.y + Float(last.y + last.h) * s
                    let bx: Float = o.x + Float(first.x + first.w + 3) * s
                    let trackH: Float = bottom - top
                    let thumbH: Float = max(6 * s, trackH * Float(pm.slots.count) / Float(pm.rows.count))
                    let thumbY: Float = top + (trackH - thumbH) * Float(pm.scroll) / Float(max(1, n - 1))
                    rect(bx, top, 3 * s, trackH, V4(0.5, 0.5, 0.52, 1))
                    rect(bx, thumbY, 3 * s, thumbH, V4(0.2, 0.32, 0.68, 1))
                }
                // Help line: full size if it fits, else a little smaller, else two lines at word breaks (it was cut
                // letter by letter at the panel edge: "...return to the title scree", blind UI critic).
                let help = pm.helpText
                let room: Float = pw - 12 * s
                let helpC = V4(0.22, 0.22, 0.25, 1)
                if !help.isEmpty {
                    if textWidth(help, s) <= room {
                        text(help, o.x + (pw - textWidth(help, s)) / 2, o.y + ph - 12 * s, s, helpC, shadow: false)
                    } else {
                        let hs: Float = s * 0.85
                        if textWidth(help, hs) <= room {
                            text(help, o.x + (pw - textWidth(help, hs)) / 2, o.y + ph - 11 * s, hs, helpC, shadow: false)
                        } else {
                            var l1 = "", rest = ""
                            for sub in help.split(separator: " ") {
                                let wd = String(sub)
                                let tryL: String = l1.isEmpty ? wd : l1 + " " + wd
                                if rest.isEmpty && textWidth(tryL, hs) <= room { l1 = tryL; continue }
                                if !rest.isEmpty { rest += " " }
                                rest += wd
                            }
                            let full = rest.count
                            while !rest.isEmpty && textWidth(rest, hs) > room { rest.removeLast() }
                            if rest.count < full {
                                while !rest.isEmpty && textWidth(rest + "...", hs) > room { rest.removeLast() }
                                rest += "..."
                            }
                            text(l1, o.x + (pw - textWidth(l1, hs)) / 2, o.y + ph - 20 * s, hs, helpC, shadow: false)
                            text(rest, o.x + (pw - textWidth(rest, hs)) / 2, o.y + ph - 11 * s, hs, helpC, shadow: false)
                        }
                    }
                }
            }
            if let am = m as? AdvancementMenu {
                // Tabs, then the checklist: done ones in gold (challenges purple), open ones grey.
                for sl in am.slots where sl.isButton {
                    guard case .button(let i) = sl.kind else { continue }
                    let x = o.x + Float(sl.x) * s, y = o.y + Float(sl.y) * s
                    let label = i < 100 ? Advancements.tabs[i] : (i == 100 ? "^" : "v")
                    let sel = i == am.tab
                    rect(x, y, Float(sl.w) * s, Float(sl.h) * s, sel ? V4(0.35, 0.55, 0.35, 1) : (game.menuHover === sl ? V4(0.2, 0.32, 0.68, 1) : V4(0.36, 0.36, 0.4, 1)))
                    let ts = min(s, (Float(sl.w) - 4) * s / max(1, textWidth(label, 1)))
                    text(label, x + (Float(sl.w) * s - textWidth(label, ts)) / 2, y + (Float(sl.h) * s - 7 * ts) / 2, ts)
                }
                let list = am.list
                let done = list.filter { game.advancements.contains($0.id) }.count
                text("\(done)/\(list.count) done  (\(game.advancements.count)/\(Advancements.all.count) total)", o.x + 8 * s, o.y + 34 * s, s, titleC, shadow: false)
                for (row, a) in list.dropFirst(am.scroll).prefix(AdvancementMenu.rows).enumerated() {
                    let y = o.y + Float(48 + row * 15) * s
                    let got = game.advancements.contains(a.id)
                    // Darker done-row fills (cream on mustard was 3.2:1), descriptions at 0.85x where they fit (0.75x
                    // was under the 14 px floor at 1080p) and 5 px in from the row's right edge (blind UI critic).
                    let doneC: V4 = a.challenge ? V4(0.32, 0.16, 0.4, 1) : V4(0.36, 0.28, 0.06, 1)
                    rect(o.x + 6 * s, y - 2 * s, 226 * s, 14 * s, got ? doneC : V4(0.26, 0.26, 0.29, 1))
                    // A filled box for done, an empty one for not yet ("+ / -" read as expand and collapse), the title,
                    // then the description at 0.85x, cut with "..." where it doesn't fit (it was shrunk under the 14 px
                    // floor or dropped: blind UI critic, run 366).
                    let mark: V4 = got ? V4(1, 0.85, 0.3, 1) : V4(0.7, 0.7, 0.72, 1)
                    rect(o.x + 9 * s, y + s, 6 * s, 6 * s, mark)
                    if !got { rect(o.x + 10 * s, y + 2 * s, 4 * s, 4 * s, V4(0.26, 0.26, 0.29, 1)) }
                    text(a.title, o.x + 18 * s, y + s, s, got ? V4(1, 1, 0.8, 1) : V4(0.8, 0.8, 0.8, 1))
                    let ds: Float = s * 0.85
                    let maxW: Float = 226 * s - textWidth(a.title, s) - 24 * s
                    var d = a.desc
                    if textWidth(d, ds) > maxW {
                        while !d.isEmpty && textWidth(d + "...", ds) > maxW { d.removeLast() }
                        d = d.trimmingCharacters(in: .whitespaces) + "..."
                    }
                    if d.count > 3 { text(d, o.x + 227 * s - textWidth(d, ds), y + 2 * s, ds, V4(0.9, 0.9, 0.88, 1)) }
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
                if sc.pages > 1, sc.slots.count > 13 {
                    let sl = sc.slots[13]
                    let x = o.x + Float(sl.x) * s, y = o.y + Float(sl.y) * s
                    rect(x, y, 10 * s, 16 * s, game.menuHover === sl ? V4(0.7, 0.7, 0.7, 1) : V4(0.55, 0.55, 0.55, 1))
                    text(">", x + 2 * s, y + 4 * s, s, V4(0.15, 0.15, 0.15, 1), shadow: false)
                    text("\(sc.page + 1)/\(sc.pages)", x - 2 * s, y + 18 * s, s, V4(0.25, 0.25, 0.25, 1), shadow: false)
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
            if let cm = m as? CustomDrawnMenu { for l in cm.drawLines(ML, o) { drawHudLine(l) } }
            for sl in m.slots where !sl.isButton {
                let x = o.x + Float(sl.x - 1) * s, y = o.y + Float(sl.y - 1) * s
                let bigSlot = (m is CraftingTableMenu || m is FurnaceMenu || m is AnvilMenu || m is SmithingMenu || m is StonecutterMenu || m is GrindstoneMenu) && { if case .result = sl.kind { return true } else if case .output = sl.kind { return true } else { return false } }()
                let big: Float = bigSlot ? 4 : 0
                let bx = x - big * s, by = y - big * s, bs = (18 + 2 * big) * s
                rect(bx, by, bs, bs, V4(0.216, 0.216, 0.216, 1))
                rect(bx + s, by + s, bs - s, bs - s, V4(1, 1, 1, 1))
                rect(bx + s, by + s, bs - 2 * s, bs - 2 * s, V4(0.545, 0.545, 0.545, 1))
                itemIcon(sl.stack, x + s, y + s, 16 * s)
                if let im = m as? InventoryMenu, !im.query.isEmpty, sl.isPlayerInv {
                    // Inventory search: matches framed in gold, everything else dimmed.
                    if im.matches(sl.stack) { frame(bx, by, bs, bs, s, V4(1, 0.85, 0.2, 1)) }
                    else { rect(bx + s, by + s, bs - 2 * s, bs - 2 * s, V4(0.15, 0.15, 0.17, 0.7)) }
                }
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
                for l in Guns.tooltip(st) { lines.append((l, V4(0.67, 0.67, 0.67, 1))) }
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
        let style = Settings.shared.crosshair
        let arm = (style == 2 ? 1.5 : 5) * s, th = style == 1 ? max(2, 2 * s) : max(1, s)
        let edge: Float = style == 1 ? max(2, s) : 1
        let shadow = V4(0, 0, 0, style == 1 ? 0.9 : 0.45), white = V4(1, 1, 1, style == 1 ? 1 : 0.9)
        if let spread = game.gunSpread, game.menu == nil {
            // Guns: four ticks that open up with the current spread (hidden in the farsight scope).
            if !game.sniperScoped {
                let gap = 2 * s + spread / tanf(35 * .pi / 180 * game.fovScale) * H / 2
                let len = 4 * s
                for (dx, dy) in [(Float(-1), Float(0)), (1, 0), (0, -1), (0, 1)] {
                    let x = cx + dx * (gap + len / 2), y = cy + dy * (gap + len / 2)
                    let w = dx != 0 ? len : th, h = dx != 0 ? th : len
                    rect(x - w / 2 - 1, y - h / 2 - 1, w + 2, h + 2, shadow)
                    rect(x - w / 2, y - h / 2, w, h, white)
                }
                rect(cx - th / 2, cy - th / 2, th, th, white)
            }
        } else {
            rect(cx - arm - edge, cy - th / 2 - edge, arm * 2 + 2 * edge, th + 2 * edge, shadow)
            rect(cx - th / 2 - edge, cy - arm - edge, th + 2 * edge, arm * 2 + 2 * edge, shadow)
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
            if let mount = game.riding, mount.health > 0, mount.kind.spec.behavior != .vehicle, mount.kind != .boat {
                // Riding an animal: its hearts replace the hunger row (rows of 10 upward), as in the reference.
                let slots = (max(mount.kind.spec.health, mount.health) + 1) / 2
                for i in 0..<slots {
                    let h = mount.health - i * 2
                    heartSprite(h >= 2 ? fullH : (h == 1 ? halfH : HudTex.heartEmpty), x0 + total - isz - Float(i % 10) * step, yh - Float(i / 10) * rowStep, V4(1, 1, 1, 1))
                }
            } else {
                for i in 0..<10 {
                    let f = game.hunger - i * 2
                    heartSprite(f >= 2 ? HudTex.food : (f == 1 ? HudTex.foodHalf : HudTex.foodEmpty), x0 + total - isz - Float(i) * step, yh, hungerTint)
                }
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
            let per = Float(1 << md.scale)
            // Explorer maps: the destination (a coloured mark with a dark rim).
            if let mk = md.marker, mk.count == 3 {
                let tx = (Float(mk[0]) - Float(md.cx)) / per + 64, tz = (Float(mk[1]) - Float(md.cz)) / per + 64
                if tx >= 0 && tx < 128 && tz >= 0 && tz < 128 {
                    let c = UInt32(truncatingIfNeeded: mk[2])
                    rect(mx + tx * px - 4 * px, my + tz * px - 4 * px, 8 * px, 8 * px, V4(0.15, 0.1, 0.05, 1))
                    rect(mx + tx * px - 3 * px, my + tz * px - 3 * px, 6 * px, 6 * px,
                         V4(Float((c >> 16) & 255) / 255, Float((c >> 8) & 255) / 255, Float(c & 255) / 255, 1))
                }
            }
            // The player marker.
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
        // Sprinting: a small tag left of the hotbar (VR has no FOV kick, so the speed change alone was easy to miss).
        if game.player.sprinting && !game.player.flying && game.menu == nil {
            let tw = textWidth(">> SPRINT", s), tx = L.hotbarX0 - tw - 36 * s, ty = L.hotbarY0 + 6 * s
            rect(tx - 3 * s, ty - 3 * s, tw + 6 * s, 13 * s, V4(0, 0, 0, 0.45))
            text(">> SPRINT", tx, ty, s, V4(0.55, 0.95, 1, 1))
        }
        // Toast (item names, messages) above the hotbar, fading out.
        let since = game.clock - game.toastTime
        if since < 2.2 && !game.toastText.isEmpty {
            let a = Float(min(1, (2.2 - since) / 0.5))
            // Above the survival rows: hearts and hunger, and the armour (left) or air-bubble (right) row above them
            // (the name sat in the bubble row beside the bubbles: run 362 survival shot).
            let armourRow: Float = game.survival && (game.inventory.armorPoints > 0 || game.air < 15) ? 10 : 0
            let ty = L.hotbarY0 - ((game.survival ? 26 : 14) + armourRow) * s
            let tb = Settings.shared.textBackground
            if tb > 0 { let tw = textWidth(game.toastText, s); rect(floor((W - tw) / 2) - 3 * s, ty - 3 * s, tw + 6 * s, 13 * s, V4(0, 0, 0, tb * a)) }
            text(game.toastText, floor((W - textWidth(game.toastText, s)) / 2), ty, s, V4(1, 1, 1, a))
        }
        // Gun: ammo readout, hit marker and the farsight scope.
        if game.menu == nil, let g = game.gunHUD {
            if game.sniperScoped {
                let r = floor(min(W, H) * 0.42), cx = W / 2, cy = H / 2
                let dark = V4(0, 0, 0, 0.94)
                rect(0, 0, W, cy - r, dark); rect(0, cy + r, W, H - cy - r, dark)
                rect(0, cy - r, cx - r, 2 * r, dark); rect(cx + r, cy - r, W - cx - r, 2 * r, dark)
                // Round lens: darken the corners of the square row by row.
                let rows = 32
                let rowH = 2 * r / Float(rows)
                for i in 0..<rows {
                    let y = cy - r + Float(i) * rowH
                    let dy = (y + rowH / 2 - cy) / r
                    let half = r * sqrtf(max(0, 1 - dy * dy))
                    rect(cx - r, y, r - half, rowH, dark)
                    rect(cx + half, y, r - half, rowH, dark)
                }
                rect(cx - r, cy - s * 0.5, 2 * r, s, V4(0, 0, 0, 0.85)); rect(cx - s * 0.5, cy - r, s, 2 * r, V4(0, 0, 0, 0.85))
                rect(cx - 2 * s, cy - 2 * s, 4 * s, 4 * s, V4(0.9, 0.15, 0.1, 0.9))
            }
            if game.arms.hitMarker > 0 {
                let c = V4(1, 1, 1, min(1, game.arms.hitMarker * 6)), cx = W / 2, cy = H / 2
                for (dx, dy) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] as [(Float, Float)] {
                    for k in 2...4 { rect(cx + dx * Float(k) * s - s / 2, cy + dy * Float(k) * s - s / 2, s, s, c) }
                }
            }
            let tw = textWidth(g.text, s * 1.5)
            text(g.text, W - tw - 10 * s, L.hotbarY0 - 14 * s, s * 1.5, g.color)
        }

        // Tutorial tips, contextual button prompts and subtitles (HudExtras.swift).
        for l in HudExtras.lines(game, L) { drawHudLine(l) }

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
        if let t = game.target { tgt = "\(Blocks.name(w.block(t.hit.x, t.hit.y, t.hit.z))) @ \(t.hit.x) \(t.hit.y - YOFF - game.dim.dim.yShift) \(t.hit.z)" }
        let hour = Int(game.dayFraction * 24 + 6) % 24
        let l = w.lightAt(bx, by, bz)
        return [
            "Blocksmith  \(Int(fps.rounded())) fps  seed \(w.seed)",
            String(format: "XYZ %.2f / %.2f / %.2f", p.pos.x, p.pos.y - Float(YOFF + game.dim.dim.yShift), p.pos.z),
            "Block \(bx) \(by - YOFF - game.dim.dim.yShift) \(bz)  Chunk \(floorDiv(bx, CS)) \(floorDiv(bz, CS))  Facing \(facing)",
            "Biome \(biome.displayName)  Light sky \(l.sky) block \(l.block)",
            "Chunks \(w.chunks.count) loaded, \(w.meshedCount) meshed, \(drawnChunks) drawn, \(w.pendingJobs) jobs, RD \(w.renderDistance)",
            "Target \(tgt)",
            "\(p.flying ? "flying" : (p.onGround ? "on ground" : "in air"))\(p.inWater ? ", in water" : "")  Time \(String(format: "%02d:00", hour))  Controller \(game.padConnected ? "yes" : "no")",
            "Mobs: " + MobDrawStats.line + "  Fluid queue \(w.fluidPending.count)",
            String(format: "GPU %.1f ms  Graphics %@  Render scale %d%%", gpuFrameMs, game.fancyGraphics ? "Fancy" : "Fast", Int((game.renderScale * 100).rounded())),
            game.audioDebugLine(),
        ]
    }

    // Isometric block icon (grass/leaves tinted with default biome colours). Model and connecting blocks (stairs,
    // slabs, fences, walls, lanterns, anvils...) draw their real boxes: each box's three visible faces (+Y, +Z on
    // the left, +X on the right) projected with that face's texture sub-rect, back to front.
    func icon(_ id: BlockID, center c: V2, size sz: Float, _ quad: ([V2], [V2], V4, Float) -> Void) {
        let tex = Blocks.tex
        let uv = [V2(0, 0), V2(1, 0), V2(1, 1), V2(0, 1)]
        let tintMode = Blocks.tint[Int(id)]
        let grassC = V4(0.57, 0.74, 0.35, 1), leafC = V4(0.47, 0.67, 0.18, 1)
        let full: V4 = tintMode == 1 ? grassC : (tintMode == 2 ? leafC : V4(1, 1, 1, 1))
        let ck = Blocks.connectKind[Int(id)]
        if Blocks.flatIcon(id) || ck == 2 {
            // Torches fill only a 2-texel strip of their texture: drawn larger, or the hotbar showed just the flame's dot
            // (blind critic, tv_hud).
            var h: Float = sz * 0.55
            if Blocks.shape[Int(id)] == "torch" {
                // Only the middle strip of the texture (5 of 16 texels), drawn at full height: the stick was 2 px wide
                // and the flame a dot even at 0.8 (run 358 spawn hotbar).
                h = sz * 0.8
                let u0: Float = 5.5 / 16, u1: Float = 10.5 / 16
                let hw: Float = h * (u1 - u0)
                let tuv: [V2] = [V2(u0, 0), V2(u1, 0), V2(u1, 1), V2(u0, 1)]
                quad([V2(c.x - hw, c.y - h), V2(c.x + hw, c.y - h), V2(c.x + hw, c.y + h), V2(c.x - hw, c.y + h)], tuv, full, Float(tex[Int(id) * 6]))
                return
            }
            quad([V2(c.x - h, c.y - h), V2(c.x + h, c.y - h), V2(c.x + h, c.y + h), V2(c.x - h, c.y + h)], uv, full, Float(tex[Int(id) * 6]))
            return
        }
        let hx = sz * 0.5, hy = sz * 0.25, vh = sz * 0.55
        let topC = tintMode == 3 ? grassC : full
        let r = Blocks.render[Int(id)]
        // The box order, fit and material flags depend only on the block: cached per id (every slot sorted its boxes and
        // tested its key string every frame: integration Next list).
        let info: IconInfo
        if let ci = iconCache[id] { info = ci } else {
        var boxes: [Box] = []
        if r == RenderType.model.rawValue { boxes = Blocks.boxes[Int(id)] }
        else if r == RenderType.connect.rawValue { boxes = BlockRegistry.connectBoxes(ck, n: false, s: false, w: true, e: true, collision: false) }
        if boxes.isEmpty { boxes = [Box(0, 0, 0, 16, 16, 16)] }
        // Small models (lanterns, candles, pots, buttons...) are scaled up round their own centre to fill the slot: drawn
        // at true size the lantern was a 10 px speck in a 28 px trade slot (blind UI critic, trade).
        var bmin = V3(1, 1, 1), bmax = V3(0, 0, 0)
        for b in boxes { bmin = simd_min(bmin, b.minV); bmax = simd_max(bmax, b.maxV) }
        let ext: V3 = bmax - bmin
        let big: Float = max(ext.x, max(ext.y, ext.z))
        let fit0: Float = big > 0.01 && big < 0.7 ? min(2.2, 0.8 / big) : 1
        let mid0: V3 = fit0 == 1 ? V3(0.5, 0.5, 0.5) : (bmin + bmax) * 0.5
        func depth(_ b: Box) -> Int { Int(b.x0) + Int(b.x1) + Int(b.y0) + Int(b.y1) + Int(b.z0) + Int(b.z1) }
        let order0 = boxes.sorted { depth($0) < depth($1) }
        let leafy0 = Blocks.key(Blocks.groupBase[Int(id)]).hasSuffix("leaves")
        // Glass is nearly all clear: a faint pale-blue body behind its frame, or the icon read as an empty outline
        // (blind critic, tv_hud).
        let glassy0 = Blocks.key(Blocks.groupBase[Int(id)]).contains("glass") && !Blocks.opaque[Int(id)]
        info = IconInfo(order: order0, fit: fit0, mid: mid0, leafy: leafy0, glassy: glassy0)
        iconCache[id] = info
        }
        let order = info.order, fit = info.fit, mid = info.mid, leafy = info.leafy, glassy = info.glassy
        // Block-local point (0...1 per axis) to the screen: +X goes right-down, +Z left-down, +Y up.
        let oy: Float = c.y + (vh - 2 * hy) / 2
        func P(_ x0: Float, _ y0: Float, _ z0: Float) -> V2 {
            let x: Float = 0.5 + (x0 - mid.x) * fit, y: Float = 0.5 + (y0 - mid.y) * fit, z: Float = 0.5 + (z0 - mid.z) * fit
            let sx: Float = c.x + (x - z) * hx
            let sy: Float = oy + (x + z) * hy - y * vh
            return V2(sx, sy)
        }
        let leftC: V4 = full * V4(0.78, 0.78, 0.78, 1), rightC: V4 = full * V4(0.6, 0.6, 0.6, 1)
        let backC: V4 = full * V4(0.38, 0.38, 0.38, 1)
        for b in order {
            let lo: V3 = b.minV, hi: V3 = b.maxV
            let tl: Float = 1 - hi.y, bl: Float = 1 - lo.y          // v at the top and bottom of a side face
            let un: Float = 1 - hi.z, uf: Float = 1 - lo.z          // u at the front and back of the +X face
            // + 4096: the HUD shader samples these with mipmaps (see hudFS).
            func layer(_ f: Int) -> Float { (b.tex.count == 6 ? Float(b.tex[f]) : Float(tex[Int(id) * 6 + f])) + 4096 }
            // +Z face (left): u = x, v = 1 - y.
            let lp: [V2] = [P(lo.x, hi.y, hi.z), P(hi.x, hi.y, hi.z), P(hi.x, lo.y, hi.z), P(lo.x, lo.y, hi.z)]
            let lu: [V2] = [V2(lo.x, tl), V2(hi.x, tl), V2(hi.x, bl), V2(lo.x, bl)]
            let rp0: [V2] = [P(hi.x, hi.y, hi.z), P(hi.x, hi.y, lo.z), P(hi.x, lo.y, lo.z), P(hi.x, lo.y, hi.z)]
            let tp0: [V2] = [P(lo.x, hi.y, lo.z), P(hi.x, hi.y, lo.z), P(hi.x, hi.y, hi.z), P(lo.x, hi.y, hi.z)]
            if glassy {
                let zero = [V2](repeating: .zero, count: 4)
                let gc = V4(0.78, 0.88, 0.95, 0.28)
                quad(lp, zero, gc * V4(0.85, 0.85, 0.85, 1), -1); quad(rp0, zero, gc * V4(0.7, 0.7, 0.7, 1), -1); quad(tp0, zero, gc, -1)
            }
            if leafy {
                // Leaves are cutout: a dark foliage backing so the icon reads as a solid bush, not a sieve.
                let zero = [V2](repeating: .zero, count: 4)
                quad(lp, zero, backC * V4(0.78, 0.78, 0.78, 1), -1); quad(rp0, zero, backC * V4(0.6, 0.6, 0.6, 1), -1); quad(tp0, zero, backC, -1)
            }
            quad(lp, lu, leftC, layer(4))
            // +X face (right): u = 1 - z, v = 1 - y.
            let rp: [V2] = [P(hi.x, hi.y, hi.z), P(hi.x, hi.y, lo.z), P(hi.x, lo.y, lo.z), P(hi.x, lo.y, hi.z)]
            let ru: [V2] = [V2(un, tl), V2(uf, tl), V2(uf, bl), V2(un, bl)]
            quad(rp, ru, rightC, layer(0))
            // +Y face (top): u = x, v = z.
            let tp: [V2] = [P(lo.x, hi.y, lo.z), P(hi.x, hi.y, lo.z), P(hi.x, hi.y, hi.z), P(lo.x, hi.y, hi.z)]
            let tu: [V2] = [V2(lo.x, lo.z), V2(hi.x, lo.z), V2(hi.x, hi.z), V2(lo.x, hi.z)]
            quad(tp, tu, topC, layer(2))
        }
    }

    // The player in the inventory's preview box (it was left empty): the third-person model's boxes projected
    // flat into the HUD (no depth pass needed, so it works in the Fast and Fancy final passes alike), turned toward
    // the cursor, back faces dropped, faces drawn far to near.
    func playerPreview(x: Float, y: Float, w: Float, h: Float, _ quad: ([V2], [V2], V4, Float) -> Void) {
        let cx = x + w / 2
        let mx = game.input.mouseX, my = game.input.mouseY
        var yaw: Float = 0.45, pitch: Float = 0
        if mx > 0 || my > 0 {
            let dx: Float = (mx - cx) / (w * 0.8)
            let eyeY: Float = y + h * 0.25
            let dy: Float = (my - eyeY) / (h * 0.8)
            yaw = max(-1.1, min(1.1, atanf(dx)))
            pitch = max(-0.6, min(0.6, -atanf(dy)))
        }
        let parts = playerParts(game, pitch: pitch, walk: 0, hit: 0)
        let k: Float = h * 0.86 / 32.5
        let feetY: Float = y + h * 0.95
        let cyw = cosf(yaw), syw = sinf(yaw)
        let CT = Mesher.cornerTable
        let shade: [Float] = [0.8, 0.8, 1.0, 0.55, 0.68, 0.68]
        var faces: [(depth: Float, pts: [V2], color: V4)] = []
        for part in parts {
            let rot = part.rotation
            let size = part.mx - part.mn
            func place(_ lp: V3) -> V3 {
                let q = part.place(lp, rot)
                return V3(cyw * q.x + syw * q.z, q.y, -syw * q.x + cyw * q.z)
            }
            let mid = place(part.mn + size * 0.5)
            for f in 0..<6 {
                var pts: [V2] = []
                var fc = V3(0, 0, 0)
                for c in 0..<4 {
                    let ci = (f * 4 + c) * 3
                    let lp: V3 = part.mn + size * V3(Float(CT[ci]), Float(CT[ci + 1]), Float(CT[ci + 2]))
                    let r = place(lp)
                    fc += r * 0.25
                    let px: Float = cx - r.x * k, py: Float = feetY - r.y * k
                    pts.append(V2(px, py))
                }
                // The camera looks along +Z from the front (the model faces -Z): keep faces turned toward it.
                if fc.z - mid.z > -0.001 { continue }
                let c: V3 = part.color * shade[f]
                faces.append((depth: fc.z, pts: pts, color: V4(c.x, c.y, c.z, 1)))
            }
        }
        faces.sort { $0.depth > $1.depth }
        let uv = [V2](repeating: .zero, count: 4)
        for f in faces { quad(f.pts, uv, f.color, -1) }
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
            renderFrame(cmd, final: rpd, width: width, height: height)
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
        MobLight.nightVision = game.nightVision         // (per view: see renderView)
        updateCave()
        let sky = game.blindFog != nil ? V3(0, 0, 0) : (game.player.headInLava ? Game.lavaFog : (game.player.headInWater ? game.underwaterFog : viewSky))
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: Double(sky.x), green: Double(sky.y), blue: Double(sky.z), alpha: 1)
        rpd.depthAttachment.texture = depth
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .dontCare
        rpd.depthAttachment.clearDepth = 1

        let t0 = CFAbsoluteTimeGetCurrent()
        let cmd = queue.makeCommandBuffer()!
        renderFrame(cmd, final: rpd, width: width, height: height)
        let blit = cmd.makeBlitCommandEncoder()!
        blit.synchronize(resource: color)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        let t1 = CFAbsoluteTimeGetCurrent()
        if let err = cmd.error { print("GPU error: \(err)") }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        color.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        if !probes.isEmpty, let u = lastUniforms {
            let e = cameraEye().eye
            for (name, p) in probes {
                let r = p - e
                let clip = u.viewProj * V4(r.x, r.y, r.z, 1)
                guard clip.w > 0.01 else { print("probe \(name): behind the camera"); continue }
                let px = Int((clip.x / clip.w * 0.5 + 0.5) * Float(width)), py = Int((0.5 - clip.y / clip.w * 0.5) * Float(height))
                guard px >= 0 && px < width && py >= 0 && py < height else { print("probe \(name): off screen"); continue }
                let i = (py * width + px) * 4
                print(String(format: "probe %@: pixel %ld,%ld rgb %d %d %d (depth %.3f)", name, px, py, Int(bytes[i + 2]), Int(bytes[i + 1]), Int(bytes[i]), clip.z / clip.w))
            }
        }
        if ImageCheck.enabled {
            var fl: Double?
            if ImageCheck.flicker {
                // The same view nudged by a thousandth of a block: only z-fighting changes much.
                let keep = game.player.pos
                game.player.pos += V3(0.001, 0.0007, 0.0013)
                let cmd2 = queue.makeCommandBuffer()!
                renderFrame(cmd2, final: rpd, width: width, height: height)
                let blit2 = cmd2.makeBlitCommandEncoder()!
                blit2.synchronize(resource: color)
                blit2.endEncoding()
                cmd2.commit()
                cmd2.waitUntilCompleted()
                var b2 = [UInt8](repeating: 0, count: width * height * 4)
                color.getBytes(&b2, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
                fl = ImageCheck.flickerShare(bytes, b2)
                game.player.pos = keep
            }
            ImageCheck.log(path: path, ImageCheck.stats(bytes, width, height), flicker: fl)
        }
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
