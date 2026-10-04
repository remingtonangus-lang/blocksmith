import Foundation
import simd
import Metal
import CVulkan

// Headless test of the VR play path: scripted head and controller poses (SimXR) drive the real QuestRig,
// QuestControls, Game.tick and renderer. Checks locomotion, snap turning, roomscale, hand-ray aiming, breaking and
// placing, opening the inventory and pointing at it with the laser; renders the inventory panel and the world to PNG.
final class SimXR: XRInput {
    var hands = [XRHand(), XRHand()]
    var headPos = V3(0, 1.7, 0)
    var headRot = simd_quatf()
    var floorSpace: Bool { true }
    var hapticCount = 0
    func eyePose(_ i: Int) -> (V3, simd_quatf) { (headPos + headRot.act(V3(i == 0 ? -0.032 : 0.032, 0, 0)), headRot) }
    func fovTangents(_ i: Int) -> (Float, Float, Float, Float) { (-1, 1, 1, -1) }
    func haptic(_ hand: Int, amplitude: Float, seconds: Float, frequency: Float) { hapticCount += 1 }
}

final class SimHost: QuestHost {
    let sim = SimXR()
    let rig = QuestRig()
    let scene: SceneRenderer
    var input: XRInput { sim }
    var fps: Double { 72 }
    init(scene: SceneRenderer) { self.scene = scene }
}

enum QuestSim {
    static func run(game: Game, ctx: VkContext, out: String, check: (Bool, String) -> Void) throws {
        let scene = try SceneRenderer(ctx: ctx, device: sharedSystemDevice as! QuestDevice, views: 2, colorFormat: VK_FORMAT_R8G8B8A8_UNORM)
        try scene.uploadTextures()
        let host = SimHost(scene: scene)
        let sim = host.sim, rig = host.rig
        let controls = QuestControls(app: host, game: game)
        let wr = WorldRenderer(scene: scene, game: game)
        wr.extraOpaque = { s, eye in controls.drawOpaque(s, eye: eye) }
        wr.extraOverlay = { s, eye in controls.drawOverlay(s, eye: eye) }
        wr.prePass = { s in controls.recordPanel(s) }
        game.paused = false
        game.survival = false
        game.player.flying = false
        rig.needsRecenter = true
        rig.bodyYaw = 0
        game.player.yaw = 0
        let dt: Float = 1.0 / 72
        func idleHands() {
            for h in 0..<2 {
                var hd = XRHand()
                hd.aimValid = true; hd.gripValid = true
                hd.aimPos = sim.headPos + V3(h == 0 ? -0.2 : 0.2, -0.45, -0.3)
                hd.gripPos = hd.aimPos
                hd.aimRot = simd_quatf(); hd.gripRot = simd_quatf()
                sim.hands[h] = hd
            }
        }
        func frames(_ n: Int, _ body: (Int) -> Void = { _ in }) {
            for i in 0..<n {
                body(i)
                rig.update(xr: sim, game: game)
                controls.update(dt: dt)
                game.tick(Double(dt))
                game.world.update(center: game.player.pos)
                controls.afterTick(dt: dt)
            }
        }
        // A 41 x 41 stone platform 30 blocks above the spawn, so locomotion doesn't depend on the terrain (jungle trees).
        let base = game.player.pos
        let py = Int(base.y) + 30
        for dz in -20...20 { for dx in -20...20 {
            game.world.setBlock(Int(base.x) + dx, py, Int(base.z) + dz, STONE)
            for k in 1...4 { game.world.setBlock(Int(base.x) + dx, py + k, Int(base.z) + dz, AIR) }
        } }
        game.player.pos = V3(Float(Int(base.x)) + 0.5, Float(py + 1), Float(Int(base.z)) + 0.5)
        game.player.vel = .zero
        // Settle on the platform.
        idleHands()
        frames(72)
        PadManager.shared.touch = nil

        // 1. Walk: left stick forward for 2 s with the left controller pointing -Z: the player goes -Z.
        let p0 = game.player.pos
        frames(144) { _ in idleHands(); sim.hands[0].stick = V2(0, 1) }
        frames(10) { _ in idleHands() }
        let d = game.player.pos - p0
        check(-d.z > 3 && abs(d.x) < 1.5, String(format: "VR walk: left stick forward moved (%.2f, %.2f) (want -Z)", d.x, d.z))

        // 2. Snap turn: right stick right turns the body 45 degrees clockwise (yaw decreases).
        let y0 = rig.bodyYaw
        frames(3) { _ in idleHands(); sim.hands[1].stick = V2(1, 0) }
        frames(3) { _ in idleHands() }
        let turned = (y0 - rig.bodyYaw) * 180 / .pi
        check(abs(turned - 45) < 1, String(format: "VR snap turn: %.1f degrees", turned))
        // Walking now goes along the turned direction (-Z turned 45 degrees right = toward +X, -Z).
        let p1 = game.player.pos
        frames(100) { _ in idleHands(); sim.hands[0].stick = V2(0, 1) }
        frames(10) { _ in idleHands() }
        let d1 = game.player.pos - p1
        check(d1.x > 1 && -d1.z > 1, String(format: "VR walk after the turn moved (%.2f, %.2f) (want +X -Z)", d1.x, d1.z))

        // 3. Roomscale: stepping 0.5 m to the right (tracking +X) moves the player 0.5 along the body's right.
        let p2 = game.player.pos
        sim.headPos.x += 0.5
        frames(2) { _ in idleHands() }
        let right = rig.yawRot.act(V3(1, 0, 0))
        let moved = simd_dot(game.player.pos - p2, right)
        check(abs(moved - 0.5) < 0.12, String(format: "VR roomscale: stepped %.2f m along the body's right (want 0.5)", moved))

        // 4. Aim: the right ray pointing down-forward picks the block it hits (not what the head looks at).
        sim.headRot = simd_quatf()                           // head looks straight ahead (horizontal)
        let down = simd_quatf(angle: -0.9, axis: V3(1, 0, 0))
        frames(3) { _ in idleHands(); sim.hands[1].aimRot = down }
        let o = rig.toWorld(sim.hands[1].aimPos)
        let dir = simd_normalize(rig.toWorldDir(down.act(V3(0, 0, -1))))
        let want = game.world.raycast(o, dir, maxDist: 8)
        check(want != nil && game.target?.hit == want?.hit,
              "VR aim: game target \(game.target.map { "\($0.hit)" } ?? "nil") = hand ray hit \(want.map { "\($0.hit)" } ?? "nil")")

        // 5. Break: the right trigger breaks the targeted block (creative).
        if let t = game.target?.hit {
            let before = game.world.block(t.x, t.y, t.z)
            frames(6) { _ in idleHands(); sim.hands[1].aimRot = down; sim.hands[1].trigger = 1 }
            frames(10) { _ in idleHands(); sim.hands[1].aimRot = down }
            let after = game.world.block(t.x, t.y, t.z)
            check(before != AIR && after != before, "VR break: right trigger broke \(Blocks.name(before)) at \(t) (now \(Blocks.name(after)))")
        }

        // 6. Place: right grip with a block in hand places it against the targeted face.
        game.inventory.held = ItemStack(Items.id("gold_block"), 64)
        frames(3) { _ in idleHands(); sim.hands[1].aimRot = down }
        if let t = game.target {
            let at = IVec3(t.hit.x + t.normal.x, t.hit.y + t.normal.y, t.hit.z + t.normal.z)
            frames(4) { _ in idleHands(); sim.hands[1].aimRot = down; sim.hands[1].squeeze = 1 }
            frames(6) { _ in idleHands(); sim.hands[1].aimRot = down }
            check(game.world.block(at.x, at.y, at.z) == Blocks.id("gold_block"), "VR place: right grip placed a gold block at \(at)")
        } else { check(false, "VR place: no target") }

        // 7. Inventory: Y (left upper button) opens it; the panel sits in front; the laser drives the mouse.
        frames(3) { _ in idleHands(); sim.hands[0].button2 = true }
        frames(3) { _ in idleHands() }
        check(game.menu != nil, "VR inventory: Y opened \(game.menu.map { String(describing: type(of: $0)) } ?? "nothing")")
        // Point the right ray at the panel centre (1.15 m ahead, 0.1 m down of the head when it opened).
        let haptics0 = sim.hapticCount
        var hitTarget = V3.zero
        frames(4) { _ in
            idleHands()
            let hand = sim.headPos + V3(0.2, -0.45, -0.3)
            let target = sim.headPos + V3(0, -0.1, -1.15)
            hitTarget = target
            sim.hands[1].aimPos = hand
            sim.hands[1].aimRot = simd_quatf(from: V3(0, 0, -1), to: simd_normalize(target - hand))
        }
        _ = hitTarget
        let mx = game.input.mouseX, my = game.input.mouseY
        let cx = Float(QuestControls.panelW) / 2, cy = Float(QuestControls.panelH) / 2
        check(abs(mx - cx) < 30 && abs(my - cy) < 30, String(format: "VR laser on the menu panel: mouse at (%.0f, %.0f) (want ~%.0f, %.0f)", mx, my, cx, cy))
        frames(2) { i in
            idleHands()
            let hand = sim.headPos + V3(0.2, -0.45, -0.3)
            sim.hands[1].aimPos = hand
            sim.hands[1].aimRot = simd_quatf(from: V3(0, 0, -1), to: simd_normalize(sim.headPos + V3(0, -0.1, -1.15) - hand))
            sim.hands[1].trigger = i == 0 ? 1 : 0
        }
        check(sim.hapticCount > haptics0, "VR laser click buzzes the controller (\(sim.hapticCount - haptics0) pulses)")

        // Render the inventory panel over the world, then close it and render play.
        try render(scene: scene, wr: wr, rig: rig, sim: sim, game: game, path: out.replacingOccurrences(of: ".png", with: "_menu.png"))
        frames(3) { _ in idleHands(); sim.hands[1].button2 = true }      // B closes
        frames(3) { _ in idleHands() }
        check(game.menu == nil, "VR inventory: B closed it")
        frames(3) { _ in idleHands(); sim.hands[1].aimRot = down }
        try render(scene: scene, wr: wr, rig: rig, sim: sim, game: game, path: out)
        PadManager.shared.touch = nil
    }

    static func render(scene: SceneRenderer, wr: WorldRenderer, rig: QuestRig, sim: SimXR, game: Game, path: String, size: Int = 640) throws {
        let ctx = scene.ctx
        let img = try VkImg(ctx, width: size, height: size, layers: 2, format: VK_FORMAT_R8G8B8A8_UNORM,
                            usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue)
        let target = try scene.makeTarget(image: img.image, width: size, height: size)
        let readback = try VkBuf(ctx, size: size * size * 8, usage: VK_BUFFER_USAGE_TRANSFER_DST_BIT.rawValue, host: true)
        let s = scene.beginFrame()
        wr.record(s, target, rig.camera(xr: sim, far: Float(game.world.renderDistance * 16 + 96)))
        vkCmdEndRenderPass(s.cmd)
        vkBarrier(s.cmd, img.image, from: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, to: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, layers: 2,
                  srcAccess: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue, dstAccess: VK_ACCESS_TRANSFER_READ_BIT.rawValue,
                  srcStage: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT.rawValue, dstStage: VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue)
        var r = VkBufferImageCopy()
        r.imageSubresource = VkImageSubresourceLayers(aspectMask: VK_IMAGE_ASPECT_COLOR_BIT.rawValue, mipLevel: 0, baseArrayLayer: 0, layerCount: 2)
        r.imageExtent = VkExtent3D(width: UInt32(size), height: UInt32(size), depth: 1)
        vkCmdCopyImageToBuffer(s.cmd, img.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.buffer, 1, &r)
        try scene.submit(s)
        scene.waitIdle()
        withExtendedLifetime((img, target)) {}          // the GPU used them until waitIdle
        let src = readback.mapped!.bindMemory(to: UInt8.self, capacity: size * size * 8)
        var outPx = [UInt8](repeating: 0, count: size * 2 * size * 4)
        for y in 0..<size { for e in 0..<2 { for x in 0..<size {
            let si = (e * size * size + y * size + x) * 4, di = (y * size * 2 + e * size + x) * 4
            outPx[di] = src[si]; outPx[di + 1] = src[si + 1]; outPx[di + 2] = src[si + 2]; outPx[di + 3] = 255
        } } }
        try PNG.encode(rgba: outPx, width: size * 2, height: size).write(to: URL(fileURLWithPath: path))
        print("questsim: wrote \(path)")
    }
}
