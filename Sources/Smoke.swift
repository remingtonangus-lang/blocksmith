import Foundation
import Metal
import simd

// Launch-and-play smoke test (CI): `Blocksmith --smoke <seconds> --rd N [--seed S]`.
// Builds the whole game the way the app does (world streaming, Game, Renderer), then plays in real time
// through Game.tick with a simulated controller while every frame goes through the full renderFrame path
// (Fancy HDR world, shadows, water, post, HUD) into an offscreen target:
//   walk + sprint + jump with a slow turn, open/close the inventory and the pause menu, then fly fast to
//   push chunk streaming. Exits non-zero on a non-finite player position or a stalled world; a crash fails
//   the step by itself. Prints frame-time percentiles, streaming coverage, mob count and peak memory, and
//   writes snaps/smoke_rd<N>.png at the end.
enum Smoke {
    static func run() -> Int32 {
        let args = CommandLine.arguments
        func arg(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let seconds = Double(arg("--smoke") ?? "") ?? 60
        let rd = Int(arg("--rd") ?? "") ?? 8
        let seed = UInt64(arg("--seed") ?? "") ?? 12345
        guard let device = MTLCreateSystemDefaultDevice() else { print("smoke: no Metal device"); return 2 }
        PrefsSandbox.begin()                                   // never touch the saved options
        defer { PrefsSandbox.end() }
        let (world, game, p0) = Bench.setup(device, seed, rd: rd)
        game.survival = false
        game.player.flying = false
        game.fancyGraphics = !args.contains("--fast")              // Fancy (the default) unless --fast
        _ = world.loadSync(center: p0, radius: min(rd, 6))
        let W = 1280, H = 720
        guard let r = try? Renderer(device: device, game: game, colorFormat: .bgra8Unorm),
              let target = OffscreenTarget(device, W, H) else { print("smoke: renderer init failed"); return 2 }
        game.screen = V2(Float(W), Float(H))
        // --coop: split screen, a second player on a simulated pad who wanders off on their own (they walk while
        // player 1 flies from the halfway mark, so chunks stream round two far-apart centres).
        let coop = args.contains("--coop")
        if coop { game.coop.simulated[1] = PadSnapshot(); game.coop.join(game, controller: nil) }
        let p2Start = game.coop.seatPlayer(1, game).pos
        let dt = 1.0 / 60
        let frames = Int(seconds / dt)
        var frameMs: [Double] = []
        var worst: (ms: Double, frame: Int, tickMs: Double) = (0, 0, 0)
        frameMs.reserveCapacity(frames)
        var minCov = 1.0, peak = residentMB(), maxMobs = 0, maxDropped = 0
        let start = CFAbsoluteTimeGetCurrent()
        let flyAt = frames / 2
        // Watchdog: a hang (deadlock, a GPU wait that never returns) becomes a reported failure instead of a CI timeout.
        let progress = SmokeProgress()
        Thread.detachNewThread {
            var last = -1, still = 0
            while true {
                sleep(5)
                let (f, phase) = progress.read()
                if f == last { still += 5 } else { still = 0; last = f }
                if still >= 20 {
                    print("smoke rd \(rd): FAIL stalled for \(still) s at frame \(f) in \(phase)")
                    fflush(stdout)
                    exit(4)
                }
            }
        }
        for i in 0..<frames {
            // Scripted controller: forward (sprinting), slow turn, a jump every 2 s; the inventory at 10 s and
            // the pause menu at 20 s (each closed half a second later); flight from the halfway mark.
            var p = PadSnapshot()
            let t = Double(i) * dt
            p.ly = 1
            p.rx = 0.25
            // Jumps (A), but not around the pause press: in the pause menu A chose "Resume" at once (run 353).
            if i % 120 < 6 && i < flyAt && !(1190...1240).contains(i) { p.a = true }
            if i == 600 { p.y = true }                         // inventory open
            if i == 630 { p.b = true }                         // ... and closed
            if i == 1200 || i == 1230 { p.menu = true }        // pause / resume
            if i == 1215 {
                // Menu tour: every pause-menu page and options category, each row hovered (help line, legend) and
                // each page drawn (Settings crashed on first read of its help table: a repeated key).
                // Self-contained: whatever the scripted pause press left open, the tour opens the pause menu itself and
                // restores the state afterwards (run 353: the pad press at 1200 had not opened it).
                let wasPaused = game.paused && game.menu is PauseMenu
                print("smoke rd \(rd): menu tour starts with \(game.menu.map { String(describing: type(of: $0)) } ?? "no menu"), paused \(game.paused)")
                if !(game.menu is PauseMenu) { game.closeMenu(); game.paused = false; game.paused = true }
                guard let pm = game.menu as? PauseMenu else { print("smoke rd \(rd): FAIL the pause menu did not open"); return 1 }
                progress.set(i, "menu tour")
                var rowsSeen = 0, pagesSeen = 0
                let pages: [PauseMenu.Page] = [.main, .options, .controls, .keys, .padmap, .worlds, .create]
                for pg in pages {
                    let cats: [PauseMenu.Cat] = pg == .options ? PauseMenu.Cat.allCases : [pm.cat]
                    for c in cats {
                        progress.set(i, "menu tour: \(pg) / \(c.name)")
                        pm.page = pg; pm.cat = c
                        var top = 0
                        repeat {
                            pm.scroll = top
                            pm.build()
                            for slot in pm.slots {
                                game.menuHover = slot
                                if pm.helpText.isEmpty && pm.hoveredID.map({ PauseMenu.isValue($0) }) == true {
                                    print("smoke rd \(rd): menu tour: no help line for \(pm.hoveredID ?? "?")")
                                }
                                _ = pm.legend
                                rowsSeen += 1
                            }
                            guard let mc = r.queue.makeCommandBuffer() else { print("smoke: no command buffer"); return 2 }
                            let mf = MeshArena.frameSubmitted()
                            mc.addCompletedHandler { _ in MeshArena.frameCompleted(mf) }
                            r.renderFrame(mc, final: target.rpd, width: W, height: H)
                            mc.commit()
                            mc.waitUntilCompleted()
                            pagesSeen += 1
                            top += PauseMenu.visible
                        } while top < pm.rows.count
                    }
                }
                pm.page = .main; pm.stack = []; pm.scroll = 0; pm.build()
                game.menuHover = nil
                // Every workstation / container screen through the real right-click dispatch (Game.openBlock), drawn
                // with each slot hovered, then closed; back to the pause menu afterwards.
                let stations = ["crafting_table", "furnace", "smoker", "blast_furnace", "barrel", "chest", "brewing_stand",
                                "enchanting_table", "smithing_table", "stonecutter", "grindstone", "ender_chest", "cartography_table",
                                "loom", "anvil", "beacon", "crafter", "white_shulker_box", "oak_sign", "lectern"]
                game.closeMenu()
                let bp = IVec3(Int(floor(game.player.pos.x)) + 2, Int(floor(game.player.pos.y)) + 2, Int(floor(game.player.pos.z)))
                let before = world.block(bp.x, bp.y, bp.z)
                var opened: [String] = [], unopened: [String] = []
                for k in stations where Blocks.has(k) {
                    progress.set(i, "menu tour: \(k) screen")
                    world.blockEntities[bp] = nil                                  // as breaking the last one would
                    world.setBlock(bp.x, bp.y, bp.z, Blocks.id(k))
                    if k == "lectern", Items.has("written_book") {
                        // An empty lectern only takes a book (no screen): lay one on it so the book screen is drawn.
                        world.entity(bp, .lectern).container[0] = ItemStack(Items.id("written_book"), 1)
                    }
                    game.openBlock(bp)
                    guard let m = game.menu else { unopened.append(k); continue }
                    for slot in m.slots { game.menuHover = slot }
                    guard let mc = r.queue.makeCommandBuffer() else { print("smoke: no command buffer"); return 2 }
                    let mf = MeshArena.frameSubmitted()
                    mc.addCompletedHandler { _ in MeshArena.frameCompleted(mf) }
                    r.renderFrame(mc, final: target.rpd, width: W, height: H)
                    mc.commit()
                    mc.waitUntilCompleted()
                    game.menuHover = nil
                    game.closeMenu()
                    opened.append(k)
                }
                world.blockEntities[bp] = nil
                world.setBlock(bp.x, bp.y, bp.z, before)
                // Back to the paused state the script expects (closing the pause menu unpaused the game; the resume
                // press at 1230 would otherwise pause it again and leave the menu open).
                game.closeMenu()
                if wasPaused { game.paused = true } else { game.paused = false; game.closeMenu() }
                print("smoke rd \(rd): menu tour: \(pagesSeen) screens, \(rowsSeen) rows hovered; \(opened.count) block screens opened\(unopened.isEmpty ? "" : ", none for " + unopened.joined(separator: " "))")
            }
            if i == flyAt { game.player.flying = true; game.player.vel.y = 0 }
            if i > flyAt && i < flyAt + 60 { p.a = true }      // climb above the terrain
            if i > flyAt { p.rx = 0.05 }
            PadManager.shared.simulated = p
            if coop {
                // Player 2: the same walk and jumps, veering right; their own inventory at 15 s (not the pause).
                var q = p
                // A zigzag: half a second's turn right, then left five seconds later, so a tree or wall in the way is
                // left behind (-0.1 sat inside the look dead zone: player 2 walked into one tree for 50 s, run 563) and
                // the walk still gets somewhere (a steady -0.25 walked an 8-block circle: 7 blocks from the start, run 634).
                let turn = i % 600
                q.lx = 0.45; q.rx = turn < 30 ? -0.6 : (turn >= 300 && turn < 330 ? 0.6 : 0)
                q.menu = false; q.y = i % 900 == 300; q.b = i % 900 == 330
                game.coop.simulated[1] = q
                if i % 600 == 0 {
                    // Where player 2 is and what holds them (run 509: they moved 12 blocks in 60 s).
                    var info = ""
                    game.coop.withSeat(1, game) {
                        let p2 = game.player
                        info = String(format: "%.1f %.1f %.1f ground %@ water %@", p2.pos.x, p2.pos.y, p2.pos.z, p2.onGround ? "yes" : "no", p2.inWater ? "yes" : "no")
                            + " menu " + (game.menu.map { String(describing: type(of: $0)) } ?? "none") + (game.paused ? " paused" : "")
                    }
                    print("smoke rd \(rd) split: t \(i / 60) s player 2 at \(info)")
                }
            }
            let b = CFAbsoluteTimeGetCurrent()
            progress.set(i, "Game.tick")
            game.tick(dt)
            let tickEnd = CFAbsoluteTimeGetCurrent()
            progress.set(i, "renderFrame")
            if i > flyAt {
                // Fly at 20 blocks/s (like the benchmark flights) so streaming is stressed at every distance.
                let f = V3(-sinf(game.player.yaw), 0, -cosf(game.player.yaw))
                game.player.pos += f * Float(20 * dt)
                let gy = Float(world.topY(Int(floor(game.player.pos.x)), Int(floor(game.player.pos.z))) + 12)
                if game.player.pos.y < gy { game.player.pos.y = gy }
            }
            guard let cmd = r.queue.makeCommandBuffer() else { print("smoke: no command buffer"); return 2 }
            let fence = MeshArena.frameSubmitted()
            cmd.addCompletedHandler { _ in MeshArena.frameCompleted(fence) }
            r.renderFrame(cmd, final: target.rpd, width: W, height: H)
            cmd.commit()
            progress.set(i, "GPU wait")
            cmd.waitUntilCompleted()
            progress.set(i + 1, "frame done")
            frameMs.append((CFAbsoluteTimeGetCurrent() - b) * 1000)
            if frameMs[frameMs.count - 1] > worst.ms {
                // Which frame was the worst and where its time went (runs 605-634: 300-840 ms, nothing said which).
                worst = (frameMs[frameMs.count - 1], i, (tickEnd - b) * 1000)
            }
            let pp = game.player.pos
            guard pp.x.isFinite && pp.y.isFinite && pp.z.isFinite else {
                print("smoke rd \(rd): FAIL player position became \(pp) at \(String(format: "%.1f", t)) s"); return 1
            }
            if i % 600 == 599 {
                // Progress (stdout is a pipe on CI: flush so a crash still shows how far it got).
                print(String(format: "smoke rd %ld %@: %.0f s, frame %.1f ms, resident %.0f MB, Metal %.0f MB, mobs %ld, coverage %.0f%%",
                             rd, game.fancyGraphics ? "Fancy" : "Fast", t, frameMs.last ?? 0, residentMB(),
                             Double(device.currentAllocatedSize) / 1_048_576, game.mobs.mobs.count, Bench.coverage(world, pp) * 100))
                print("smoke rd \(rd) mob drawing: " + MobDrawStats.line)      // mobs were invisible in real play (2026-10-05)
                fflush(stdout)
            }
            if i % 30 == 0 {
                minCov = min(minCov, i > 120 ? Bench.coverage(world, pp) : 1)
                peak = max(peak, residentMB())
                maxMobs = max(maxMobs, game.mobs.mobs.count)
                maxDropped = max(maxDropped, MobDrawStats.dropped)
            }
            let slack = start + Double(i + 1) * dt - CFAbsoluteTimeGetCurrent()
            if slack > 0 { usleep(useconds_t(slack * 1e6)) }
        }
        PadManager.shared.simulated = nil
        let wall = CFAbsoluteTimeGetCurrent() - start
        let sorted = frameMs.sorted()
        func pct(_ q: Double) -> Double { sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * q))] }
        let dist = simd_length(V2(game.player.pos.x - p0.x, game.player.pos.z - p0.z))
        print(String(format: "smoke rd %ld: worst frame %.0f ms at %.1f s (frame %ld): Game.tick %.0f ms, render + GPU %.0f ms; frames over 100 ms: %ld",
                     rd, worst.ms, Double(worst.frame) * dt, worst.frame, worst.tickMs, worst.ms - worst.tickMs, frameMs.filter { $0 > 100 }.count))
        print(String(format: "smoke rd %ld: %ld frames in %.1f s wall, frame p50 %.2f p95 %.2f p99 %.2f max %.2f ms, coverage min %.0f%%, mobs max %ld, travelled %.0f blocks, resident peak %.0f MB, menu %@",
                     rd, frames, wall, pct(0.5), pct(0.95), pct(0.99), sorted.last ?? 0, minCov * 100, maxMobs, dist, peak,
                     game.menu == nil && !game.paused ? "closed" : "STILL OPEN"))
        print("smoke rd \(rd): mobs dropped for a full mob buffer: at most \(maxDropped) in a frame (the farthest first)")
        _ = r.renderToPNG(path: "snaps/smoke_rd\(rd).png", width: 960, height: 540)
        if dist < 100 { print("smoke rd \(rd): FAIL the player only moved \(Int(dist)) blocks (input or tick stalled)"); return 1 }
        if game.menu != nil || game.paused { print("smoke rd \(rd): FAIL a menu or the pause screen is still open"); return 1 }
        if coop {
            let d2 = simd_length(game.coop.seatPlayer(1, game).pos - p2Start)
            var open2 = false
            game.coop.withSeat(1, game) { open2 = game.menu != nil }
            print("smoke rd \(rd) split screen: player 2 moved \(Int(d2)) blocks")
            if d2 < 30 || open2 { print("smoke rd \(rd): FAIL player 2 \(open2 ? "left a menu open" : "barely moved")"); return 1 }
        }
        print("smoke rd \(rd)\(game.fancyGraphics ? "" : " Fast")\(coop ? " split screen" : ""): PASS")
        return 0
    }
}

// Frame counter + phase shared with the smoke watchdog thread.
final class SmokeProgress {
    private let lock = NSLock()
    private var frame = 0, phase = "start"
    func set(_ f: Int, _ p: String) { lock.lock(); frame = f; phase = p; lock.unlock() }
    func read() -> (Int, String) { lock.lock(); defer { lock.unlock() }; return (frame, phase) }
}
