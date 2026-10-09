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
        let keepScale = g.renderScale
        // Fancy, Fast, and Fancy at a TV's reduced World Scale (the HDR target smaller than the screen).
        for (fancy, scale) in [(true, Float(1)), (false, Float(1)), (true, Float(0.7))] {
            g.fancyGraphics = fancy
            g.renderScale = scale
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
                if mobModelParts(m).isEmpty { noParts.append("\(k)"); continue }
                g.mobs.mobs = [m]
                let img = pixels(r, w, h)
                let c = changed(base, img)
                if c < 30 { invisible.append("\(k) (\(c) px)") } else { drawn += 1 }
            }
            g.mobs.mobs.removeAll()
            let mode = (fancy ? "Fancy" : "Fast") + (scale < 1 ? " at world scale \(Int(scale * 100))%" : "")
            print("mobcheck \(mode): \(drawn) kinds drawn, \(invisible.count) invisible\(invisible.isEmpty ? "" : ": " + invisible.joined(separator: ", "))")
            if !noParts.isEmpty { print("mobcheck \(mode): no model parts (not checked): \(noParts.joined(separator: ", "))") }
            if !invisible.isEmpty { fails += 1 }
        }
        g.renderScale = keepScale
        for fancy in [true, false] {
            g.fancyGraphics = fancy
            fails += crowd(g, r, w, h)
            fails += live(g, r, w, h)
        }
        g.fancyGraphics = keepFancy
        g.mobs.mobs = saved
        print("mobcheck: \(fails == 0 ? "PASS" : "\(fails) FAILED")")
        return fails
    }

    // Live: mobs that spawned and updated through Game.tick (a survival night) must draw too. Each is rendered alone
    // from a clear viewpoint a few blocks away (night vision on, so a dark mob in a dark cave still differs from the
    // empty frame), again after a save and load, and checked for a broken state (NaN position or yaw, zero scale).
    static func live(_ g: Game, _ r: Renderer, _ w: Int, _ h: Int) -> Int {
        let p = g.player
        let keepTime = g.time, keepSurvival = g.survival, keepPos = p.pos, keepYaw = p.yaw, keepPitch = p.pitch
        g.time = 0.62 * DAY_LENGTH
        g.survival = true
        g.paused = false
        p.flying = true
        g.mobs.mobs.removeAll()
        for _ in 0..<(60 * 45) {
            g.tick(1.0 / 60)
            g.health = 20
            if g.menu != nil { g.closeMenu(); g.paused = false }
        }
        let all = g.mobs.mobs
        var broken: [String] = [], invisible: [String] = []
        var drawn = 0, skipped = 0, kinds = Set<MobKind>()
        g.applyEffect(.nightVision, amp: 0, seconds: 60)
        func clear(_ a: V3, _ b: V3) -> Bool {
            for i in 0...16 {
                let q = a + (b - a) * (Float(i) / 16)
                if g.world.collides(q - V3(0.1, 0.1, 0.1), q + V3(0.1, 0.1, 0.1)) { return false }
            }
            return true
        }
        for m in all where kinds.count < 40 {
            let ok = m.pos.x.isFinite && m.pos.y.isFinite && m.pos.z.isFinite && m.yaw.isFinite && m.scale > 0.01
            if !ok { broken.append("\(m.kind) pos \(m.pos) yaw \(m.yaw) scale \(m.scale)"); continue }
            if kinds.contains(m.kind) { continue }
            let c = m.pos + V3(0, m.height * 0.5, 0)
            let d: Float = 2.5 + max(m.height, m.halfW * 2) * 1.5
            let views = [V3(d, 1.5, 0), V3(-d, 1.5, 0), V3(0, 1.5, d), V3(0, 1.5, -d), V3(0.7 * d, d, 0.7 * d)]
            // Every clear view until one shows the mob (a dark enderman against the night sky, a bat side-on: one
            // view could change under 30 px though the model draws; the CI run after the PM9 spawning change hit both).
            let clearViews = views.filter { clear(c + $0, c) }
            if clearViews.isEmpty { skipped += 1; continue }
            kinds.insert(m.kind)
            func shown(_ mob: Mob) -> Int {
                var best = 0
                for off in clearViews where best < 30 {
                    let eye = c + off
                    p.pos = eye - V3(0, p.eyeHeight, 0)
                    let to = c - eye
                    p.yaw = atan2f(-to.x, -to.z)
                    p.pitch = atan2f(to.y, simd_length(V2(to.x, to.z)))
                    g.mobs.mobs = []
                    _ = pixels(r, w, h)
                    let base = pixels(r, w, h)
                    g.mobs.mobs = [mob]
                    best = max(best, changed(base, pixels(r, w, h)))
                }
                return best
            }
            let n = shown(m)
            if n < 30 { invisible.append("\(m.kind) (\(n) px)") } else { drawn += 1 }
            // The same mob through a save and a load (Remington plays saved worlds; a fresh harness world has none).
            if let data = try? JSONEncoder().encode(m.record), let rec = try? JSONDecoder().decode(MobRecord.self, from: data),
               let back = Mob.from(rec) {
                let nb = shown(back)
                if nb < 30 { invisible.append("\(m.kind) after save and load (\(nb) px)") }
            } else { broken.append("\(m.kind) does not survive a save and load") }
        }
        g.effects.remove(.nightVision)
        g.mobs.mobs = all
        g.time = keepTime; g.survival = keepSurvival
        p.pos = keepPos; p.yaw = keepYaw; p.pitch = keepPitch
        var line: String = "mobcheck live \(g.fancyGraphics ? "Fancy" : "Fast"): \(all.count) mobs after a 45 s survival night, \(kinds.count) kinds viewed, \(drawn) drawn"
        line += ", \(skipped) without a clear view"
        if !invisible.isEmpty { line += "; invisible: " + invisible.joined(separator: ", ") }
        if !broken.isEmpty { line += "; broken state: " + broken.prefix(6).joined(separator: ", ") }
        print(line)
        return (invisible.isEmpty && broken.isEmpty && !all.isEmpty) ? 0 : 1
    }

    // Crowd: hundreds of mobs loaded (render distance 16-24, a citadel's jointed soldiers) must not crowd the mob beside
    // the player out of the vertex buffer. It is appended last, as a fresh spawn is (playtest 2026-10-05: mobs invisible
    // in game; the buffer filled with far mobs first).
    static func crowd(_ g: Game, _ r: Renderer, _ w: Int, _ h: Int) -> Int {
        let p = g.player
        p.pitch = 0
        let fwd = V3(-sinf(p.yaw), 0, -cosf(p.yaw))
        var many: [Mob] = []
        var total = 0
        for i in 0..<600 {
            let a: Float = Float(i) * 2.399
            let d: Float = 30 + Float(i % 56)
            let k: MobKind = i % 3 == 0 ? .soldierOfficer : (i % 3 == 1 ? .soldierTrooper : .cow)
            let m = Mob(k, at: p.pos + V3(cosf(a) * d, 0, sinf(a) * d))
            total += mobModelParts(m).count
            many.append(m)
        }
        let cow = Mob(.cow, at: p.eye + fwd * 5 - V3(0, 0.7, 0))
        cow.yaw = p.yaw + 2.3
        g.mobs.mobs = many
        _ = pixels(r, w, h)
        let base = pixels(r, w, h)
        g.mobs.mobs = many + [cow]
        let n = changed(base, pixels(r, w, h))
        let dropped = MobDrawStats.dropped
        g.mobs.mobs = []
        let mode = g.fancyGraphics ? "Fancy" : "Fast"
        print("mobcheck crowd \(mode): 600 mobs 30-85 blocks round (\(total) model parts), \(dropped) dropped; the cow beside the player \(n) px\(n < 30 ? " INVISIBLE" : "")")
        return n < 30 ? 1 : 0
    }
}
