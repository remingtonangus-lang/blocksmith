import Foundation
import simd
import Metal
import CVulkan

// Monkey test of the VR play path (the Mac's --agent monkey, for the Quest layer): seeded random head motion and
// Touch input (sticks, triggers, grips, every button, aim swings, holds and taps) drive QuestRig, QuestControls and
// Game.tick for a few simulated minutes, survival and creative, with the world rendered every half second. Oracles each
// frame: the player, rig and panels stay finite, the player stays in the world; at the end the B / menu buttons must
// get back to play from whatever menu is open (no dead ends). A crash fails the run by itself.
enum QuestFuzz {
    static func run(game: Game, ctx: VkContext, seconds: Int, seed: UInt64, check: (Bool, String) -> Void) throws {
        let scene = try SceneRenderer(ctx: ctx, device: sharedSystemDevice as! QuestDevice, views: 2, colorFormat: VK_FORMAT_R8G8B8A8_UNORM)
        try scene.uploadTextures()
        let host = SimHost(scene: scene)
        let sim = host.sim, rig = host.rig
        let controls = QuestControls(app: host, game: game, panel: try HudPanel(scene: scene, width: QuestControls.panelW, height: QuestControls.panelH))
        host.controls = controls
        let wr = WorldRenderer(scene: scene, game: game)
        wr.extraOpaque = { s, eye in controls.drawOpaque(s, eye: eye) }
        wr.extraOverlay = { s, eye in controls.drawOverlay(s, eye: eye) }
        wr.prePass = { s in controls.recordPanel(s) }
        let size = 160
        let img = try VkImg(ctx, width: size, height: size, layers: 2, format: VK_FORMAT_R8G8B8A8_UNORM,
                            usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue)
        let target = try scene.makeTarget(image: img.image, width: size, height: size)
        let keepSurvival = game.survival, keepPos = game.player.pos
        let teleport0 = QuestSettings.teleport, smooth0 = QuestSettings.smoothTurn, seated0 = QuestSettings.seated
        // (Nov 11, check fix 35: structure starts planned on workers, as the game does (QuestApp). The host checks plan
        // them on the frame so a base is found at once, and the stall oracle charged those plans to the frame.
        // Trips wait for their ground as on the headset too (Game.arrivalHold), not loaded on the frame.)
        let plans0 = StructureCache.plansOffThread, hold0 = Game.arrivalHold
        StructureCache.plansOffThread = true; Game.arrivalHold = true
        defer {
            StructureCache.plansOffThread = plans0; Game.arrivalHold = hold0
            QuestSettings.teleport = teleport0; QuestSettings.smoothTurn = smooth0; QuestSettings.seated = seated0
            if game.menu != nil { game.closeMenu() }
            game.paused = false
            game.survival = keepSurvival
            game.arrivalSince = nil; game.arrivalThen = nil                          // (a trip still waiting for its ground)
            game.player.pos = keepPos; game.player.vel = .zero
            PadManager.shared.touch = nil
            scene.waitIdle()
            withExtendedLifetime((img, target)) {}
        }
        game.paused = false
        rig.needsRecenter = true
        let dt: Float = 1.0 / 72
        var rng = SRng(seed)
        func rnd(_ a: Float, _ b: Float) -> Float { a + (b - a) * rng.float() }
        func randomRot() -> simd_quatf {
            simd_quatf(angle: rnd(-.pi, .pi), axis: V3(0, 1, 0)) * simd_quatf(angle: rnd(-1.2, 1.2), axis: V3(1, 0, 0))
        }
        // The current "intent", held for a random number of frames (a human holds a stick or a trigger for a while).
        var hold = [XRHand(), XRHand()]
        var holdLeft = 0
        var headYaw: Float = 0, headPitch: Float = 0
        var frames = 0, renders = 0, menusSeen = Set<String>(), bad: [String] = []
        var maxMenuFrames = 0, menuFrames = 0
        // (Nov 11: the frame's own CPU time for the input and the game tick, the thread's clock so the host's scheduler
        // doesn't count; a frame over the budget is a stall a player would see, with what was going on then)
        @inline(__always) func threadMs() -> Double {
            var ts = timespec()
            clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
            return Double(ts.tv_sec) * 1000 + Double(ts.tv_nsec) / 1e6
        }
        // The thread's voluntary context switches (it blocked: a lock, a wait, a sleep), on the host: a frame past the
        // budget by the wall clock that blocked is a stall the CPU clock above doesn't see (ledger 78: a 1.8 s wait in
        // a 68 ms frame). Host preemption is an involuntary switch and doesn't count.
        @inline(__always) func blocks() -> Int {
            #if os(Linux)
            var ru = rusage()
            getrusage(__rusage_who_t(1), &ru)                                         // RUSAGE_THREAD
            return ru.ru_nvcsw
            #else
            return 0
            #endif
        }
        @inline(__always) func wallMs() -> Double {
            var ts = timespec()
            clock_gettime(CLOCK_MONOTONIC, &ts)
            return Double(ts.tv_sec) * 1000 + Double(ts.tv_nsec) / 1e6
        }
        var slowFrames = 0, worstMs = 0.0, worstWhat = "", tickSum = 0.0
        var slowList: [(Double, String)] = []
        var waitFrames = 0, worstWait = 0.0
        var waitList: [String] = []
        func finite(_ v: V3) -> Bool { v.x.isFinite && v.y.isFinite && v.z.isFinite }
        let total = seconds * 72
        StallTrace.install()                                                         // (BS_STALLTRACE=FILE)
        for i in 0..<total {
            if i == total / 2 { game.survival = !game.survival }                   // both modes
            if i % 1500 == 0 {                                                       // comfort options vary too
                QuestSettings.teleport = rng.chance(0.3); QuestSettings.smoothTurn = rng.chance(0.4); QuestSettings.seated = rng.chance(0.2)
            }
            if holdLeft <= 0 {
                holdLeft = rng.range(4, 60)
                for h in 0..<2 {
                    var hd = XRHand()
                    hd.aimValid = !rng.chance(0.02); hd.gripValid = hd.aimValid      // tracking loss now and then
                    hd.aimRot = rng.chance(0.5) ? randomRot() : simd_quatf(angle: rnd(-0.4, 0.4), axis: V3(1, 0, 0))
                    hd.gripRot = hd.aimRot
                    hd.stick = rng.chance(0.55) ? V2(rnd(-1, 1), rnd(-1, 1)) : .zero
                    hd.trigger = rng.chance(0.25) ? rnd(0.5, 1) : 0
                    hd.squeeze = rng.chance(0.15) ? rnd(0.5, 1) : 0
                    hd.stickClick = rng.chance(0.04)
                    hd.button1 = rng.chance(0.12)
                    hd.button2 = rng.chance(0.08)
                    hd.menu = h == 0 && rng.chance(0.03)
                    hold[h] = hd
                }
                headYaw += rnd(-0.8, 0.8); headPitch = rnd(-0.9, 0.7)
            }
            holdLeft -= 1
            // Head: a slow random walk inside a 2 m play space; hands follow the head.
            sim.headPos += V3(rnd(-0.01, 0.01), 0, rnd(-0.01, 0.01))
            sim.headPos.x = max(-1, min(1, sim.headPos.x)); sim.headPos.z = max(-1, min(1, sim.headPos.z))
            sim.headPos.y = QuestSettings.seated ? 1.2 : 1.7
            sim.headRot = simd_quatf(angle: headYaw, axis: V3(0, 1, 0)) * simd_quatf(angle: headPitch, axis: V3(1, 0, 0))
            for h in 0..<2 {
                var hd = hold[h]
                hd.aimPos = sim.headPos + sim.headRot.act(V3(h == 0 ? -0.2 : 0.2, -0.4, -0.3))
                hd.gripPos = hd.aimPos
                hd.aimRot = sim.headRot * hd.aimRot
                hd.gripRot = hd.aimRot
                sim.hands[h] = hd
            }
            StallTrace.begin(i)
            let w0 = wallMs(), b0 = blocks()
            let c0 = threadMs()
            rig.update(xr: sim, game: game)
            controls.update(dt: dt)
            let c1 = threadMs()
            game.tick(Double(dt))
            let c2 = threadMs()
            controls.afterTick(dt: dt)
            let ms = threadMs() - c0
            let wall = wallMs() - w0, blocked = blocks() - b0
            tickSum += ms
            let waited = wall > 13.9 && blocked > 0 && wall - ms > 5 && i > 72
            StallTrace.end(slow: (ms > 13.9 || waited) && i > 72, ms: max(ms, wall), what: game.menu.map { String(describing: type(of: $0)) } ?? "none")
            if waited {
                waitFrames += 1; worstWait = max(worstWait, wall)
                if waitList.count < 8 {
                    waitList.append(String(format: "frame %d, %.1f ms by the clock, %.1f on the CPU, blocked %d times: menu %@, %@ (stage ", i, wall, ms, blocked,
                                           game.menu.map { String(describing: type(of: $0)) } ?? "none", game.survival ? "survival" : "creative")
                                    + TickProf.summary() + ")")
                }
            }
            // (Nov 11: a trip's arrival hold (Game.arrivalHold) waits up to 4 s of game clock for the workers to load the
            // ground; the fuzz runs far faster than the headset's 72 Hz, so it timed out in a fraction of a second and
            // loaded on the frame. While a hold is on, frames keep the headset's pace.)
            if game.arrivalSince != nil, wallMs() - w0 < 13.9 { usleep(UInt32((13.9 - (wallMs() - w0)) * 1000)) }
            if ms > 13.9 && i > 72 {
                slowFrames += 1
                let what = String(format: "frame %d, %.1f ms: menu %@, %@, riding %@, holding %@, at %.0f %.0f %.0f", i, ms,
                                  game.menu.map { String(describing: type(of: $0)) } ?? "none", game.survival ? "survival" : "creative",
                                  game.riding?.kind.key ?? "nothing", game.held.count > 0 ? Items.key(game.held.item) : "nothing",
                                  game.player.pos.x, game.player.pos.y - 64, game.player.pos.z)
                    + String(format: "; input %.1f, tick %.1f (top stage ", c1 - c0, c2 - c1) + TickProf.summary() + ")"
                if slowList.count < 8 { slowList.append((ms, what)) }
                if ms > worstMs { worstMs = ms; worstWhat = what }
            }
            frames += 1
            if let m = game.menu { menusSeen.insert(String(describing: type(of: m))); menuFrames += 1 } else { menuFrames = 0 }
            maxMenuFrames = max(maxMenuFrames, menuFrames)
            if i % 36 == 0 {
                let s = scene.beginFrame()
                wr.record(s, target, rig.camera(xr: sim, far: Float(game.world.renderDistance * 16 + 96)))
                vkCmdEndRenderPass(s.cmd)
                try scene.submit(s)
                scene.waitIdle()
                renders += 1
            }
            // Oracles.
            let p = game.player
            if bad.count < 6 {
                if !finite(p.pos) || !finite(p.vel) { bad.append("frame \(i): player position / velocity not finite") }
                if !rig.bodyYaw.isFinite || !finite(rig.headWorld) { bad.append("frame \(i): rig not finite") }
                if !finite(controls.panelWorldCenter) { bad.append("frame \(i): panel position not finite") }
                if p.pos.y < -70 && game.alive { bad.append(String(format: "frame %d: fell out of the world (y %.1f)", i, p.pos.y)) }
            }
            if !bad.isEmpty && bad.count >= 6 { break }
        }
        // Back to play from whatever is open: B (back) and the menu button, as a person would.
        var back = 0
        for k in 0..<240 where game.menu != nil || game.paused || !game.alive {
            for h in 0..<2 { sim.hands[h] = XRHand(); sim.hands[h].aimValid = true; sim.hands[h].gripValid = true }
            let phase = k % 12
            if let dm = game.menu as? DeathMenu { if phase == 0 { dm.buttonPressed(0) } }   // its Respawn button (laser + trigger)
            else if phase < 2 { sim.hands[1].button2 = true }                         // B
            else if phase >= 6 && phase < 8 && game.menu == nil && game.paused { sim.hands[0].menu = true }
            rig.update(xr: sim, game: game)
            controls.update(dt: dt)
            game.tick(Double(dt))
            controls.afterTick(dt: dt)
            back += 1
        }
        let stuck = game.menu.map { String(describing: type(of: $0)) } ?? (game.paused ? "pause" : nil)
        print("questfuzz: \(frames) frames, \(renders) renders, menus seen: \(menusSeen.sorted().joined(separator: " ")); "
              + "longest menu stay \(maxMenuFrames) frames; back to play in \(back) frames")
        print(String(format: "questfuzz: input + tick own CPU %.3f ms a frame mean, %d frames over 13.9 ms", tickSum / Double(max(1, frames)), slowFrames)
              + (slowFrames > 0 ? "; worst " + worstWhat : ""))
        for (_, w) in slowList { print("  slow: " + w) }
        print(String(format: "questfuzz: %d frames past 13.9 ms by the clock that blocked (waited)", waitFrames) + (waitFrames > 0 ? String(format: ", worst %.1f ms", worstWait) : ""))
        for w in waitList { print("  waited: " + w) }
        StallTrace.write()
        check(bad.isEmpty, "VR fuzz (seed \(seed), \(seconds) s): no oracle failures" + (bad.isEmpty ? "" : ": " + bad.joined(separator: "; ")))
        check(stuck == nil, "VR fuzz: B / menu buttons get back to play" + (stuck.map { " (stuck in \($0))" } ?? ""))
    }
}
