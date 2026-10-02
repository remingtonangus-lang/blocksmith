import Foundation
import Metal
import simd

// Fancy ("vibrant") renderer resources: HDR pipelines for the world, the shadow map, the emissive
// texture array and per-layer material table, render targets and the post chain (bloom, god rays,
// composite). The Fast path never touches any of this.
final class Vibrant {
    let device: MTLDevice
    // World pipelines rendering into the HDR target.
    let chunk, chunkSolid, water, simple, star, cloud, cloudBox, mob, entity, crack, sky, hollowSky: MTLRenderPipelineState
    let shadowSolid, shadowCut, mobShadow: MTLRenderPipelineState
    // Moving block structures (ships/vehicles) in the Fancy world pass: shipVibVS (buffer 2 = model matrix +
    // section origin, the ship renderer's per-draw record) with the terrain fragment shaders.
    let shipSolid, shipCut, shipTrans: MTLRenderPipelineState
    let bloomDown, bloomUp, rays, composite: MTLRenderPipelineState
    let shadowDepth: MTLDepthStencilState
    let shadowMap: MTLTexture
    // Terrain-only shadow depth, re-rendered when the light turns or the centre moves; each frame with mobs
    // around it is copied into `shadowMap` and the mobs are drawn on top (moving shadows without redrawing terrain).
    let shadowStatic: MTLTexture
    let emissive: MTLTexture
    let materials: MTLBuffer
    static let shadowSize = 2048
    static let shadowHalf: Float = 64        // blocks covered either side of the camera
    static let shadowDepthRange: Float = 192 // blocks along the light direction, either side

    private(set) var hdr: MTLTexture?
    private(set) var depth: MTLTexture?
    private(set) var sceneCopy: MTLTexture?
    private(set) var depthCopy: MTLTexture?
    private(set) var bloom: [MTLTexture] = []
    private(set) var raysTex: MTLTexture?
    private var size = (0, 0)

    init(device: MTLDevice, library lib: MTLLibrary, finalFormat: MTLPixelFormat, emissive mask: [UInt8]) throws {
        self.device = device
        let hdrF = MTLPixelFormat.rgba16Float
        func pipe(_ vs: String, _ fs: String?, color: MTLPixelFormat?, depth: MTLPixelFormat = .depth32Float,
                  blend: Int = 0) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: vs)
            if let fs { d.fragmentFunction = lib.makeFunction(name: fs) }
            if let color {
                d.colorAttachments[0].pixelFormat = color
                if blend != 0 {
                    let a = d.colorAttachments[0]!
                    a.isBlendingEnabled = true
                    if blend == 1 {
                        a.sourceRGBBlendFactor = .sourceAlpha
                        a.destinationRGBBlendFactor = .oneMinusSourceAlpha
                        a.sourceAlphaBlendFactor = .one
                        a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                    } else {
                        a.sourceRGBBlendFactor = .one
                        a.destinationRGBBlendFactor = .one
                        a.sourceAlphaBlendFactor = .one
                        a.destinationAlphaBlendFactor = .one
                    }
                }
            }
            d.depthAttachmentPixelFormat = depth
            return try device.makeRenderPipelineState(descriptor: d)
        }
        chunk = try pipe("chunkVibVS", "chunkVibFS", color: hdrF)
        chunkSolid = try pipe("chunkVibVS", "chunkVibSolidFS", color: hdrF)
        water = try pipe("chunkVibVS", "waterVibFS", color: hdrF, blend: 1)
        simple = try pipe("simpleVS", "simpleFS", color: hdrF, blend: 1)
        star = try pipe("starVS", "simpleFS", color: hdrF, blend: 1)
        cloud = try pipe("cloudVS", "cloudFS", color: hdrF, blend: 1)
        cloudBox = try pipe("cloudBoxVS", "cloudBoxFS", color: hdrF, blend: 1)
        mob = try pipe("mobVS", "mobVibFS", color: hdrF)
        entity = try pipe("entityVS", "entityFS", color: hdrF)
        crack = try pipe("entityVS", "crackFS", color: hdrF, blend: 1)
        sky = try pipe("skyVS", "skyFS", color: hdrF)
        hollowSky = try pipe("skyVS", "hollowSkyFS", color: hdrF)
        shipSolid = try pipe("shipVibVS", "chunkVibSolidFS", color: hdrF)
        shipCut = try pipe("shipVibVS", "chunkVibFS", color: hdrF)
        shipTrans = try pipe("shipVibVS", "waterVibFS", color: hdrF, blend: 1)
        shadowSolid = try pipe("shadowVS", nil, color: nil)
        shadowCut = try pipe("shadowVS", "shadowCutFS", color: nil)
        mobShadow = try pipe("mobShadowVS", nil, color: nil)
        bloomDown = try pipe("fsVS", "bloomDownFS", color: hdrF, depth: .invalid)
        bloomUp = try pipe("fsVS", "bloomUpFS", color: hdrF, depth: .invalid, blend: 2)
        rays = try pipe("fsVS", "raysFS", color: hdrF, depth: .invalid)
        composite = try pipe("fsVS", "compositeFS", color: finalFormat)

        let dsd = MTLDepthStencilDescriptor()
        dsd.depthCompareFunction = .lessEqual
        dsd.isDepthWriteEnabled = true
        shadowDepth = device.makeDepthStencilState(descriptor: dsd)!

        let sd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: Vibrant.shadowSize,
                                                          height: Vibrant.shadowSize, mipmapped: false)
        sd.usage = [.renderTarget, .shaderRead]
        sd.storageMode = .private
        shadowMap = device.makeTexture(descriptor: sd)!
        shadowStatic = device.makeTexture(descriptor: sd)!

        // Emissive mask (R8) per texture layer, with box-filtered mips like the colour atlas.
        let S = TextureGen.size, layers = Tex.count
        let ed = MTLTextureDescriptor()
        ed.textureType = .type2DArray
        ed.pixelFormat = .r8Unorm
        ed.width = S; ed.height = S; ed.arrayLength = layers
        var lv = 0, sz = S
        while sz >= 1 { lv += 1; sz /= 2 }
        ed.mipmapLevelCount = lv
        ed.usage = .shaderRead
        let em = device.makeTexture(descriptor: ed)!
        var cur = mask, cs = S
        for level in 0..<lv {
            cur.withUnsafeBytes { raw in
                for l in 0..<layers {
                    em.replace(region: MTLRegionMake2D(0, 0, cs, cs), mipmapLevel: level, slice: l,
                                     withBytes: raw.baseAddress! + l * cs * cs, bytesPerRow: cs, bytesPerImage: cs * cs)
                }
            }
            if cs == 1 { break }
            let ns = cs / 2
            var next = [UInt8](repeating: 0, count: ns * ns * layers)
            for l in 0..<layers { for y in 0..<ns { for x in 0..<ns {
                let b = l * cs * cs
                // Typed steps: the one-line 4-term sum timed out the type checker on the Mac (Swift 6.3).
                let r0: Int = b + (2 * y) * cs + 2 * x
                let r1: Int = r0 + cs
                let s0: Int = Int(cur[r0]) + Int(cur[r0 + 1])
                let s1: Int = Int(cur[r1]) + Int(cur[r1 + 1])
                let s: Int = s0 + s1
                next[l * ns * ns + y * ns + x] = UInt8(s / 4)
            } } }
            cur = next; cs = ns
        }
        emissive = em
        let mats = Vibrant.materialTable(layers: layers)
        materials = device.makeBuffer(bytes: mats, length: max(16, mats.count), options: .storageModeShared)!
    }

    // Glowing texels: layers of light-emitting blocks glow where they are bright (lava, flames, lamps,
    // lumenstone); ore layers glow faintly in their coloured specks.
    // Glow per layer: > 0 emitter strength, < 0 ore glint, 0 none.
    static func emissiveModes(layers: Int) -> [Float] {
        var mode = [Float](repeating: 0, count: layers)       // >0: emitter strength, <0: ore
        // Layers shared with non-glowing blocks (carved pumpkin sides, furnace stone) never glow.
        var dark = [Bool](repeating: false, count: layers)
        for id in 0..<Blocks.count where Blocks.emit[id] == 0 {
            for f in 0..<6 { let l = Int(Blocks.tex[id * 6 + f]); if l < layers { dark[l] = true } }
            for b in Blocks.boxes[id] { for t in b.tex where Int(t) < layers { dark[Int(t)] = true } }
        }
        for id in 0..<Blocks.count where Blocks.emit[id] > 0 {
            let k = Float(Blocks.emit[id]) / 15
            for f in 0..<6 { let l = Int(Blocks.tex[id * 6 + f]); if l < layers { mode[l] = max(mode[l], k) } }
            for b in Blocks.boxes[id] { for t in b.tex where Int(t) < layers { mode[Int(t)] = max(mode[Int(t)], k) } }
        }
        for l in 0..<layers where dark[l] && mode[l] > 0 { mode[l] = 0 }
        for (l, n) in Tex.names.enumerated() where l < layers && mode[l] == 0 && n.hasSuffix("_ore") && !n.contains("coal") {
            mode[l] = -1
        }
        return mode
    }

    // Emissive mask (R8, S x S per layer) for layers first..<first+count, from their full-size RGBA (`base` holds just
    // those layers), written into `out` (all layers). The renderer calls it once per batch of built layers.
    static func emissiveMask(_ base: [UInt8], first: Int, count: Int, modes mode: [Float], into out: inout [UInt8]) {
        let S = TextureGen.size
        for lb in 0..<count where mode[first + lb] != 0 {
            let l = first + lb
            for i in 0..<(S * S) {
                let p = (lb * S * S + i) * 4
                let r = Float(base[p]) / 255, g = Float(base[p + 1]) / 255, b = Float(base[p + 2]) / 255, a = Float(base[p + 3]) / 255
                if a < 0.5 { continue }
                let mx = max(r, max(g, b)), mn = min(r, min(g, b))
                var e: Float
                if mode[l] > 0 {
                    let t = simd_clamp((mx - 0.55) / 0.4, 0, 1)
                    e = t * t * (3 - 2 * t) * mode[l]
                } else {
                    // Ores: only a faint glint (a strong glow would light up and give away ore veins in the dark).
                    let t = simd_clamp((mx - mn - 0.2) / 0.3, 0, 1)
                    e = t * 0.05
                }
                out[l * S * S + i] = UInt8(min(255, e * 255))
            }
        }
    }

    // Per-layer material: x = specular strength, y = shininess, z = metal (tints the highlight), w = gets wet in rain.
    static func materialTable(layers: Int) -> [UInt8] {
        var m = [UInt8](repeating: 0, count: layers * 4)
        let metals = ["iron_block", "gold_block", "diamond_block", "emerald_block", "netherite_block", "copper_block",
                      "cut_copper", "exposed_copper", "weathered_copper", "raw_iron_block", "raw_gold_block", "lapis_block",
                      "iron_door", "iron_trapdoor", "chain", "lantern", "anvil", "cauldron", "hopper", "bell"]
        for (l, n) in Tex.names.enumerated() where l < layers {
            var spec: Float = 0.05, shin: Float = 14, metal: Float = 0, wet: Float = 1
            if n.contains("glass") || n == "ice" || n == "packed_ice" || n == "blue_ice" || n.hasPrefix("frosted_ice") {
                spec = 0.55; shin = 96; wet = 0
            } else if metals.contains(where: { n.hasPrefix($0) }) {
                spec = 0.6; shin = 44; metal = 1
            } else if n.hasPrefix("polished_") || n.hasPrefix("smooth_") || n.contains("quartz") || n.hasSuffix("glazed_terracotta")
                        || n == "obsidian" || n == "crying_obsidian" || n.hasPrefix("prismarine") || n == "sea_lantern" || n.hasSuffix("_concrete") {
                spec = 0.22; shin = 40
            } else if n.hasPrefix("purpur") || n.hasPrefix("end_stone_brick") || n.hasPrefix("end_rod") {
                spec = 0.18; shin = 32                    // Hollow building stone: a soft sheen
            } else if n == "snow" || n == "snow_block" || n == "powder_snow" || n == "grass_block_snow" {
                spec = 0.2; shin = 60; metal = 0.5; wet = 0
            } else if n.contains("leaves") {
                spec = 0.0; wet = 0.6; metal = 0.25       // 0.25 = translucent foliage (backlit glow)
            } else if n.contains("wool") || n.hasSuffix("_carpet") {
                spec = 0.0; wet = 0.6
            }
            m[l * 4] = UInt8(spec * 255); m[l * 4 + 1] = UInt8(shin); m[l * 4 + 2] = UInt8(metal * 255); m[l * 4 + 3] = UInt8(wet * 255)
        }
        return m
    }

    // (Re)creates the size-dependent targets.
    func ensure(_ w: Int, _ h: Int) {
        if size == (w, h), hdr != nil { return }
        size = (w, h)
        func tex(_ f: MTLPixelFormat, _ w: Int, _ h: Int, _ usage: MTLTextureUsage) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: f, width: max(1, w), height: max(1, h), mipmapped: false)
            d.usage = usage
            d.storageMode = .private
            return device.makeTexture(descriptor: d)!
        }
        hdr = tex(.rgba16Float, w, h, [.renderTarget, .shaderRead])
        depth = tex(.depth32Float, w, h, [.renderTarget, .shaderRead])
        sceneCopy = tex(.rgba16Float, w, h, [.shaderRead])
        depthCopy = tex(.depth32Float, w, h, [.shaderRead])
        bloom = (1...5).map { i in tex(.rgba16Float, w >> i, h >> i, [.renderTarget, .shaderRead]) }
        raysTex = tex(.rgba16Float, w / 2, h / 2, [.renderTarget, .shaderRead])
    }

    // Light frame for this view: direction toward the sun (day) or moon (night), colours, shadow matrices.
    struct LightFrame {
        var dir = V3(0, 1, 0)
        var color = V3(0, 0, 0)
        var shadowStrength: Float = 0
        var ambient = V3(0, 0, 0)
        var lightVP = matrix_identity_float4x4     // world - center -> shadow clip
        var center = V3(0, 0, 0)                    // snapped shadow-map centre (world)
        var hazeStrength: Float = 0
    }

    static func lightFrame(game: Game, eye: V3) -> LightFrame {
        var f = LightFrame()
        guard game.dim.dim.hasSky else { return f }
        let sd = game.sunDir
        let rain = min(1, game.weather.rain)
        let day = sd.y > -0.08
        let L = day ? sd : -sd
        f.dir = L
        let up = simd_clamp((L.y + 0.02) / 0.3, 0, 1)
        if day {
            let dusk = simd_clamp(1 - sd.y / 0.4, 0, 1)
            let warm = simd_mix(V3(1.0, 0.95, 0.86), V3(1.0, 0.56, 0.3), V3(repeating: dusk * dusk))
            let rise: Float = up * up * (3 - 2 * up)
            let dim: Float = 1 - 0.75 * rain
            // Sun 0.9 against a day ambient of ~0.5: shade at ~40 % of sunlit (spec 25-45 %; 0.68 against 0.58 left
            // canopy shade at 64 %: blind critic, forest_in).
            f.color = warm * (0.9 * rise * dim)
            let hz: Float = 0.25 + 0.75 * dusk
            f.hazeStrength = hz * (1 - rain) * up
        } else {
            let moonDim: Float = 1 - 0.75 * rain
            f.color = V3(0.5, 0.6, 0.95) * (0.2 * up * moonDim)
        }
        f.shadowStrength = simd_clamp((L.y - 0.03) / 0.15, 0, 1) * (1 - 0.85 * rain)
        let dl = simd_clamp((game.daylight - 0.1) / 0.9, 0, 1)
        let dayAmb = V3(0.48, 0.51, 0.57), nightAmb = V3(0.17, 0.2, 0.33)
        f.ambient = simd_mix(nightAmb, dayAmb, V3(repeating: dl))
        // Thunderstorms: heavy cloud cover, a steely ambient and almost no direct sun.
        let storm = min(1, game.weather.thunder)
        f.ambient *= V3(1 - 0.35 * storm, 1 - 0.33 * storm, 1 - 0.25 * storm)
        f.color *= 1 - 0.6 * storm
        f.hazeStrength *= 1 - storm
        // Shadow map basis: light travels along -L.
        let fwd = -L
        let ref = abs(fwd.y) > 0.95 ? V3(0, 0, 1) : V3(0, 1, 0)
        let right = simd_normalize(simd_cross(fwd, ref))
        let upv = simd_cross(right, fwd)
        let texel = 2 * shadowHalf / Float(shadowSize)
        let lx = simd_dot(right, eye), ly = simd_dot(upv, eye)
        let sx = (lx / texel).rounded() * texel, sy = (ly / texel).rounded() * texel
        f.center = eye + right * (sx - lx) + upv * (sy - ly)
        let S = shadowHalf, D = shadowDepthRange
        f.lightVP = float4x4(rows: [
            SIMD4<Float>(right.x / S, right.y / S, right.z / S, 0),
            SIMD4<Float>(upv.x / S, upv.y / S, upv.z / S, 0),
            SIMD4<Float>(fwd.x / (2 * D), fwd.y / (2 * D), fwd.z / (2 * D), 0.5),
            SIMD4<Float>(0, 0, 0, 1),
        ])
        return f
    }

    // Bloom chain + god rays + composite into the final pass (returned encoder continues with the HUD).
    func post(_ cmd: MTLCommandBuffer, final: MTLRenderPassDescriptor, u: Uniforms, params: PostParams) -> MTLRenderCommandEncoder {
        var p = params
        var uu = u
        func pass(_ target: MTLTexture, load: Bool) -> MTLRenderCommandEncoder {
            let d = MTLRenderPassDescriptor()
            d.colorAttachments[0].texture = target
            d.colorAttachments[0].loadAction = load ? .load : .dontCare
            d.colorAttachments[0].storeAction = .store
            return cmd.makeRenderCommandEncoder(descriptor: d)!
        }
        guard let hdr, let depth, let raysTex else { return cmd.makeRenderCommandEncoder(descriptor: final)! }
        // Bloom: threshold + downsample, then tent-upsample back up additively.
        var src: MTLTexture = hdr
        for (i, dst) in bloom.enumerated() {
            let e = pass(dst, load: false)
            e.setRenderPipelineState(bloomDown)
            e.setFragmentTexture(src, index: 0)
            var prm = V4(1 / Float(src.width), 1 / Float(src.height), i == 0 ? 1.0 : 0, 0)
            e.setFragmentBytes(&prm, length: 16, index: 0)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            e.endEncoding()
            src = dst
        }
        for i in stride(from: bloom.count - 1, to: 0, by: -1) {
            let e = pass(bloom[i - 1], load: true)
            e.setRenderPipelineState(bloomUp)
            e.setFragmentTexture(bloom[i], index: 0)
            var prm = V4(1 / Float(bloom[i].width), 1 / Float(bloom[i].height), 0.85, 0)
            e.setFragmentBytes(&prm, length: 16, index: 0)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            e.endEncoding()
        }
        // Half resolution: red = screen-space god rays (sun on screen), green = volumetric shafts.
        do {
            let e = pass(raysTex, load: false)
            e.setRenderPipelineState(rays)
            e.setFragmentTexture(depth, index: 0)
            e.setFragmentTexture(shadowMap, index: 1)
            e.setFragmentBytes(&p, length: MemoryLayout<PostParams>.stride, index: 0)
            e.setFragmentBytes(&uu, length: MemoryLayout<Uniforms>.stride, index: 1)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            e.endEncoding()
        }
        let e = cmd.makeRenderCommandEncoder(descriptor: final)!
        e.setRenderPipelineState(composite)
        e.setFragmentTexture(hdr, index: 0)
        e.setFragmentTexture(bloom[0], index: 1)
        e.setFragmentTexture(raysTex, index: 2)
        e.setFragmentTexture(depth, index: 3)
        e.setFragmentBytes(&p, length: MemoryLayout<PostParams>.stride, index: 0)
        e.setFragmentBytes(&uu, length: MemoryLayout<Uniforms>.stride, index: 1)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        return e
    }
}

struct PostParams {
    var sun = V4(0, 0, 0, 0)      // xy = sun uv, z = god ray strength, w = bloom strength
    var sunCol = V4(0, 0, 0, 0)   // rgb = sun colour, w = haze strength
    var grade = V4(1, 1, 1, 0)    // exposure, saturation, contrast, vignette
    var mist = V4(0, 0, 0, 0)     // rgb = mist colour, w = density (0 = off)
    var mistH = V4(0, 0, 0, 0)    // x = mist base height relative to the eye, y = falloff height
}
