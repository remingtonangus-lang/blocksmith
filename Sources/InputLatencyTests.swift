import Foundation
import simd

// Response within one frame (Q2, scorecard "Response within one frame"; `questcheck --latency-only`, and part of every
// questcheck run). Each control is pressed through the pad path the headset feeds (PadManager.touch, read by Game.tick
// in the same frame the XR layer polls the controllers, QuestApp.frame) and the frame its effect first shows in the
// game state is counted: 0 means the very tick that read the press, so the frame drawn next shows it. Every control
// must answer at frame 0: jump, walk, look, sneak, the hotbar, pause, the inventory, mining, placing and an attack.
enum InputLatencyTests {
    static func run(game g: Game, check: (Bool, String) -> Void) {
        let w = g.world, pm = PadManager.shared
        let dt = 1.0 / 72
        let surv0 = g.survival, pos0 = g.player.pos, yaw0 = g.player.yaw, pitch0 = g.player.pitch, sel0 = g.selected
        let slot0 = g.inventory.main[0], slot1 = g.inventory.main[1], time0 = g.time, mobs0 = g.mobs.mobs
        // A stone floor high over the spawn with a dirt wall two blocks north, out of the way of the world's own blocks.
        let fx = Int(floor(pos0.x)) + 40, fz = Int(floor(pos0.z)) + 40
        let py = min(CH - 12, w.topY(fx, fz) + 30)
        var placed: [(IVec3, BlockID)] = []
        func put(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) {
            placed.append((IVec3(x, y, z), w.block(x, y, z)))
            w.setBlock(x, y, z, b)
        }
        func arena() {
            for z in (fz - 4)...(fz + 4) { for x in (fx - 4)...(fx + 4) { for y in py...(py + 4) {
                let want = y == py ? STONE : (z == fz - 2 && x == fx && y <= py + 2 ? DIRT : AIR)
                if w.block(x, y, z) != want { put(x, y, z, want) }
            } } }
        }
        defer {
            pm.touch = nil
            for (p, b) in placed.reversed() { w.setBlock(p.x, p.y, p.z, b) }
            g.survival = surv0; g.player.pos = pos0; g.player.vel = .zero; g.player.yaw = yaw0; g.player.pitch = pitch0
            g.inventory.main[0] = slot0; g.inventory.main[1] = slot1; g.selected = sel0; g.time = time0; g.mobs.mobs = mobs0
            g.mining = nil; if g.menu != nil { g.closeMenu() }; g.paused = false
        }
        let spot = V3(Float(fx) + 0.5, Float(py + 1), Float(fz) + 0.5)
        var mob: Mob?
        var h0 = 0

        // Settle on the floor facing the wall with neutral input, press, and count frames to the effect (nil: none
        // within 12 frames).
        func frames(_ name: String, setup: () -> Void = {}, _ press: (inout PadSnapshot) -> Void, _ effect: () -> Bool) -> Int? {
            arena()
            g.mobs.mobs.removeAll(); w.pendingMobs.removeAll(); mob = nil
            if g.menu != nil { g.closeMenu() }; g.paused = false
            g.survival = true; g.health = 20; g.alive = true; g.time = DAY_LENGTH * 0.25
            g.player.pos = spot; g.player.vel = .zero; g.player.yaw = 0; g.player.pitch = 0; g.player.flying = false
            g.inventory.main[0] = ItemStack(Items.id("cobblestone"), 64); g.inventory.main[1] = .empty; g.selected = 0
            g.mining = nil
            setup()
            pm.touch = PadSnapshot()
            for _ in 0..<20 { g.tick(dt) }                 // on the ground, still, the press edge clear
            if let m = mob, g.mobs.mobs.contains(where: { $0 === m }) { m.pos = spot + V3(0, 0, -1.2); m.vel = .zero; g.player.pitch = -0.7 }
            g.swing = 0
            var p = PadSnapshot()
            press(&p)
            for i in 0..<12 {
                pm.touch = p
                g.tick(dt)
                if effect() { pm.touch = PadSnapshot(); g.tick(dt); return i }
            }
            pm.touch = PadSnapshot(); g.tick(dt)
            return nil
        }

        var rows: [String] = [], late: [String] = []
        func row(_ name: String, _ n: Int?) {
            rows.append("\(name) \(n.map(String.init) ?? "none")")
            if n != 0 { late.append("\(name) \(n.map { "\($0) frames" } ?? "no effect in 12 frames")") }
        }
        var ref = V3.zero
        row("jump", frames("jump", { $0.a = true }) { g.player.vel.y > 0 })
        row("walk", frames("walk", setup: { ref = spot }, { $0.ly = 1 }) { simd_length(V2(g.player.pos.x - ref.x, g.player.pos.z - ref.z)) > 1e-4 })
        var yaw = Float(0)
        row("look", frames("look", setup: { yaw = 0 }, { $0.rx = 1 }) { g.player.yaw != yaw })
        row("sneak", frames("sneak", { $0.b = true }) { g.player.sneaking })
        row("hotbar", frames("hotbar", { $0.rb = true }) { g.selected != 0 })
        row("pause", frames("pause", { $0.menu = true }) { g.paused && g.menu != nil })
        row("inventory", frames("inventory", { $0.y = true }) { g.menu != nil })
        let wall = IVec3(fx, py + 2, fz - 2)
        row("mine", frames("mine", { $0.rt = 1 }) { g.mining == wall || g.swing > 0 || w.block(wall.x, wall.y, wall.z) != DIRT })
        let front = IVec3(fx, py + 2, fz - 1)
        row("place", frames("place", { $0.lt = 1 }) { w.block(front.x, front.y, front.z) != AIR })
        row("attack", frames("attack", setup: {
            // A pig in the gap, at arm's length (the wall behind it).
            let m = Mob(.pig, at: spot + V3(0, 0, -1.2))
            g.mobs.mobs = [m]; mob = m; h0 = m.health
            g.player.pitch = -0.7
            for z in (fz - 2)...(fz - 1) { for y in (py + 1)...(py + 2) { if w.block(fx, y, z) != AIR { put(fx, y, z, AIR) } } }
        }, { $0.rt = 1 }) { mob.map { $0.health < h0 } ?? false })
        print("input latency (frames to the first effect, 0 = the same tick): " + rows.joined(separator: ", "))
        check(late.isEmpty, "latency: every control answers in the frame that reads the press (\(rows.count) controls)"
              + (late.isEmpty ? "" : "; late: " + late.joined(separator: ", ")))
    }
}
