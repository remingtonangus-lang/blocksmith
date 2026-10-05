import Foundation
import Metal
import simd

// --mobcheck: every mob kind must put pixels on screen, in Fancy and in Fast graphics (playtest 2026-10-05: mobs were
// invisible in game). Each kind floats a few blocks in front of a level camera, alone; its frame is compared with the
// empty frame, and a kind that changes almost nothing is a failure (one with no model parts at all is listed apart).
enum MobRenderCheck {
    static func pixels(_ r: Renderer, _ w: Int, _ h: Int) -> [UInt8] {
        let cd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        cd.usage = [.renderTarget, .shaderRead]
        cd.storageMode = .managed
        let color = r.device.makeTexture(descriptor: cd)!
        let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: w, height: h, mipmapped: false)
        dd.usage = .renderTarget
        dd.storageMode = .private
        let depth = r.device.makeTexture(descriptor: dd)!
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = color
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.depthAttachment.texture = depth
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .dontCare
        rpd.depthAttachment.clearDepth = 1
        let cmd = r.queue.makeCommandBuffer()!
        r.renderFrame(cmd, final: rpd, width: w, height: h)
        let blit = cmd.makeBlitCommandEncoder()!
        blit.synchronize(resource: color)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        color.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return bytes
    }

    // Pixels that differ clearly between two frames.
    static func changed(_ a: [UInt8], _ b: [UInt8]) -> Int {
        var n = 0
        var i = 0
        while i + 3 < a.count {
            let d = max(abs(Int(a[i]) - Int(b[i])), abs(Int(a[i + 1]) - Int(b[i + 1])), abs(Int(a[i + 2]) - Int(b[i + 2])))
            if d > 24 { n += 1 }
            i += 4
        }
        return n
    }

    static func run(_ g: Game, _ r: Renderer) -> Int {
        let w = 320, h = 200
        var fails = 0
        let p = g.player
        p.flying = true
        p.vel = .zero
        p.pitch = 0
        let fwd = V3(-sinf(p.yaw), 0, -cosf(p.yaw))
        let keepFancy = g.fancyGraphics
        let saved = g.mobs.mobs
        for fancy in [true, false] {
            g.fancyGraphics = fancy
            g.mobs.mobs.removeAll()
            _ = pixels(r, w, h)                                 // warm-up (pipelines, residency)
            let base = pixels(r, w, h)
            var invisible: [String] = [], noParts: [String] = []
            var drawn = 0
            for k in MobKind.allCases {
                let m = Mob(k, at: p.pos)
                let size: Float = max(m.height, 1)
                let dist: Float = 3 + size * 1.6
                m.pos = p.eye + fwd * dist - V3(0, m.height * 0.5, 0)
                m.yaw = p.yaw + .pi * 0.75                       // three-quarter view
                if parts(m).isEmpty && equipmentParts(m).isEmpty { noParts.append("\(k)"); continue }
                g.mobs.mobs = [m]
                let img = pixels(r, w, h)
                let c = changed(base, img)
                if c < 30 { invisible.append("\(k) (\(c) px)") } else { drawn += 1 }
            }
            g.mobs.mobs.removeAll()
            let mode = fancy ? "Fancy" : "Fast"
            print("mobcheck \(mode): \(drawn) kinds drawn, \(invisible.count) invisible\(invisible.isEmpty ? "" : ": " + invisible.joined(separator: ", "))")
            if !noParts.isEmpty { print("mobcheck \(mode): no model parts (not checked): \(noParts.joined(separator: ", "))") }
            if !invisible.isEmpty { fails += 1 }
        }
        g.fancyGraphics = keepFancy
        g.mobs.mobs = saved
        print("mobcheck: \(fails == 0 ? "PASS" : "\(fails) FAILED")")
        return fails
    }
}
