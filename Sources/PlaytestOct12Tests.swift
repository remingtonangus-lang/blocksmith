import Foundation
import simd

// Checks for the Oct 12 AM Quest playtest items (docs/roadmap/backlog.md P68-P97). Part of every questcheck run;
// `questcheck --p12-only` stops after them.
enum PlaytestOct12Tests {
    static func run(_ game: Game, _ check: (Bool, String) -> Void) {
        gunOpensDoors(game, check)
    }

    // A stone floor high over the spawn, cleared above, for checks that press buttons through Game.tick. Returns the
    // floor's y and a function that puts everything back.
    static func arena(_ g: Game, dx: Int = 50, dz: Int = -50, r: Int = 5) -> (fx: Int, fz: Int, py: Int, restore: () -> Void) {
        let w = g.world
        let pos0 = g.player.pos
        let fx = Int(floor(pos0.x)) + dx, fz = Int(floor(pos0.z)) + dz
        _ = w.loadSync(center: V3(Float(fx), pos0.y, Float(fz)), radius: 2)
        let py = min(CH - 12, w.topY(fx, fz) + 30)
        var placed: [(IVec3, BlockID)] = []
        for z in (fz - r)...(fz + r) { for x in (fx - r)...(fx + r) { for y in py...(py + 5) {
            let want = y == py ? STONE : AIR
            let b = w.block(x, y, z)
            if b != want { placed.append((IVec3(x, y, z), b)); w.setBlock(x, y, z, want) }
        } } }
        return (fx, fz, py, { for (p, b) in placed.reversed() { w.setBlock(p.x, p.y, p.z, b) } })
    }

    // Press a pad snapshot for one tick (as the headset feeds it), then let go.
    static func press(_ g: Game, _ f: (inout PadSnapshot) -> Void) {
        let pm = PadManager.shared
        pm.touch = PadSnapshot(); g.tick(1.0 / 72)
        var p = PadSnapshot(); f(&p)
        pm.touch = p; g.tick(1.0 / 72)
        pm.touch = PadSnapshot(); g.tick(1.0 / 72)
    }

    // P74 (09:22): with a gun in hand the use press opened no door (the gun's aim took it), and a left grip by the side
    // never stepped the hotbar (every grip read as a reach for a magazine, refused with the gun full).
    static func gunOpensDoors(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, pm = PadManager.shared
        let pos0 = g.player.pos, yaw0 = g.player.yaw, pitch0 = g.player.pitch, surv0 = g.survival, fly0 = g.player.flying
        let sel0 = g.selected, slot0 = g.inventory.main[g.selected], menu0 = g.menu, riding0 = g.riding, credits0 = g.credits
        let a = arena(g)
        defer {
            pm.touch = nil; a.restore()
            if g.menu is DeathMenu { g.menu = nil } else if g.menu != nil { g.closeMenu() }
            g.menu = menu0; g.riding = riding0; g.credits = credits0
            g.player.pos = pos0; g.player.vel = .zero; g.player.yaw = yaw0; g.player.pitch = pitch0
            g.survival = surv0; g.player.flying = fly0; g.selected = sel0; g.inventory.main[sel0] = slot0
            g.arms.magInHand = false; g.arms.aim = 0
        }
        if g.menu is DeathMenu { g.menu = nil } else if g.menu != nil { g.closeMenu() }
        g.riding = nil; g.credits = nil; g.survival = true; g.player.flying = false; g.health = 20; g.alive = true
        var gun = ItemStack(Items.id("gun_rifle"), 1); gun.tag = Guns.magSize(gun)
        g.inventory.main[g.selected] = gun
        // A door two blocks north, a wall beside it.
        let door = IVec3(a.fx, a.py + 1, a.fz - 2)
        w.setBlock(door.x, door.y, door.z, Blocks.id("oak_door")); w.setBlock(door.x, door.y + 1, door.z, Blocks.id("oak_door") + 8)
        for y in (a.py + 1)...(a.py + 2) { w.setBlock(a.fx + 2, y, a.fz - 2, STONE) }
        g.player.pos = V3(Float(a.fx) + 0.5, Float(a.py + 1), Float(a.fz) + 0.5); g.player.vel = .zero
        g.player.yaw = 0; g.player.pitch = -0.25
        for _ in 0..<20 { g.tick(1.0 / 72) }
        let closed = w.block(door.x, door.y, door.z)
        let gunOut = g.heldGun != nil
        press(g) { $0.lt = 1 }
        let opened = w.block(door.x, door.y, door.z) != closed
        // Aimed at the wall instead, the same press still aims the gun.
        g.player.yaw = -atan2f(2, 2.5)
        var aimed: Float = 0
        pm.touch = PadSnapshot(); g.tick(1.0 / 72)
        for _ in 0..<20 { var p = PadSnapshot(); p.lt = 1; pm.touch = p; g.tick(1.0 / 72); aimed = max(aimed, g.arms.aim) }
        pm.touch = PadSnapshot(); g.tick(1.0 / 72)
        check(gunOut && opened && aimed > 0.3,
              "P74 gun in hand: the use press opens a door in reach (\(opened)) and still aims the gun elsewhere (aim \(String(format: "%.2f", aimed)))")
        // The left grip by the side with a full gun: no magazine taken, so the grip steps the hotbar (QuestControls).
        let head = g.player.eye
        let ev = VRReload.tick(g, offHand: head + V3(-0.25, -0.8, 0.05), gunHand: head + V3(0.2, -0.35, -0.35), head: head, grip: true, gripWas: false)
        check(ev == .none && !g.arms.magInHand, "P74 gun in hand: a left grip at the side with a full magazine takes nothing (\(ev)), so it steps the hotbar")
    }
}
