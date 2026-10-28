import Foundation
import simd

// `--jetplate` (P478, Oct 27 19:30: "Make it so I can have an armour chest plate on and a jet pack"): a jetpack strapped
// onto a chest piece by crafting. Fitting, taking it off again (the piece stays in the grid), refuelling through the
// piece, and flying on it in the real Game.tick with the piece's armour counted.
enum JetplateCheck {
    static func run(_ game: Game, _ check: (Bool, String) -> Void) {
        let jet = Items.id("jetpack"), plate = Items.id("iron_chestplate")
        func grid(_ a: [ItemStack]) -> [ItemStack] { a + Array(repeating: ItemStack.empty, count: 9 - a.count) }
        var pack = ItemStack(jet, 1); pack.damage = 500
        let fit = Fireworks.craft(grid([ItemStack(plate, 1), .empty, pack]))
        check(fit?.0.item == plate && fit.flatMap { Jetpack.fitted($0.0) }?.damage == 500,
              "jetplate: an iron chestplate and a jetpack craft the chestplate carrying the pack, its fuel kept (\(fit.map { Items.key($0.0.item) } ?? "none"))")
        guard let worn = fit?.0 else { return }
        check(Fireworks.craft(grid([ItemStack(Items.id("elytra"), 1), pack])) == nil && Fireworks.craft(grid([worn, pack])) == nil,
              "jetplate: wings, or a piece already carrying one, take no pack")
        // Taking it off: the pack comes out, the chestplate stays in the grid.
        let cg = CraftingGrid(3)
        cg.grid[4] = worn
        cg.update()
        let got = cg.take()
        check(got.map { Jetpack.isJetpack($0) && $0.damage == 500 } == true && cg.grid[4].item == plate && cg.grid[4].contents == nil,
              "jetplate: crafted alone it gives the pack back and the plain chestplate stays (\(cg.grid[4].isEmpty ? "gone" : Items.key(cg.grid[4].item)))")
        let coal = ItemStack(Items.id("coal"), 1)
        let rf = Fireworks.craft(grid([worn, coal]))
        check(rf?.0.item == plate && rf.flatMap { Jetpack.fitted($0.0) }?.damage == 200, "jetplate: coal with it refuels the strapped pack (+300)")
        check(!Jetpack.tooltip(worn).isEmpty, "jetplate: its tooltip names the pack and its fuel")

        // Flying on it: jump held climbs, the strapped pack burns, the chestplate's armour counts.
        let p = game.player, w = game.world
        let x = Int(floor(p.pos.x)), z = Int(floor(p.pos.z))
        let gy = min(CH - 60, w.topY(x, z) + 30)
        for dx in -1...1 { for dz in -1...1 { w.setBlock(x + dx, gy, z + dz, STONE); for k in 1...40 where gy + k < CH { w.setBlock(x + dx, gy + k, z + dz, AIR) } } }
        game.survival = true; p.flying = false; p.moveYaw = nil
        game.paused = false; if game.menu != nil { game.closeMenu() }
        var full = worn; full.contents = [ItemStack(jet, 1)]
        game.inventory.armor[1] = full
        p.pos = V3(Float(x) + 0.5, Float(gy + 1), Float(z) + 0.5); p.vel = .zero; p.airPeak = p.pos.y; p.pendingFall = 0
        for _ in 0..<10 { game.tick(1.0 / 60) }
        let y0 = p.pos.y, jump = KeyBinds.key(.jump)
        var top = y0
        for i in 0..<180 {
            game.input.keys.insert(jump); if i == 0 { game.input.pressed.insert(jump) }
            game.tick(1.0 / 60)
            top = max(top, p.pos.y)
        }
        game.input.keys.remove(jump)
        let used = Jetpack.fitted(game.inventory.armor[1])?.damage ?? -1
        check(top - y0 > 10 && used >= 50 && used <= 62 && game.inventory.armor[1].item == plate,
              String(format: "jetplate: 3 s of jump held climbs %.1f blocks on the strapped pack, burning %d fuel (want > 10, ~57-60)", top - y0, used))
        check(game.inventory.armorPoints == ItemStack(plate, 1).def.armor && ItemStack(plate, 1).def.armor > 0,
              "jetplate: the chestplate's armour counts while it carries the pack (\(game.inventory.armorPoints))")
        check(!Jetpack.gauge(game, HudLayout(1280, 720)).isEmpty, "jetplate: the fuel gauge shows for the strapped pack")
        game.inventory.armor[1] = .empty
    }
}
