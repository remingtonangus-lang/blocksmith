import Foundation
import simd

// Ledger 55 (week item 62, "placement sanity: no torches in lava"): every torch gives way to water and lava, and none
// goes into either (questcheck --torchwater; in the full suite).
//   - Water poured beside each kind (a standing torch and one on a wall, soul, copper and signal torches) runs into its
//     cell and takes it; the torch drops as an item. Lava takes them too, and burns them (no item).
//   - Held torches clicked at the floor under water or lava are refused, the pool left as it was.
enum TorchWaterCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, p = g.player
        let home = p.pos, survival0 = g.survival, fly0 = p.flying, yaw0 = p.yaw, pitch0 = p.pitch
        let held0 = g.inventory.held
        defer { p.pos = home; g.survival = survival0; p.flying = fly0; p.vel = .zero; p.yaw = yaw0; p.pitch = pitch0; g.inventory.held = held0 }
        _ = w.loadSync(center: home, radius: 3)
        let bx = Int(floor(home.x)) - 6, bz = Int(floor(home.z)) - 6, by = min(CH - 30, w.topY(bx + 6, bz + 6) + 40)
        let active0 = w.activeCenter
        w.activeCenter = V3(Float(bx) + 6.5, Float(by) + 2, Float(bz) + 6.5)      // (the fluids round the tray run)
        defer { w.activeCenter = active0 }
        // A walled stone tray 13 x 13 in the air, a stone post in its middle row for the wall torches.
        func tray() {
            for z in -1...13 { for x in -1...13 { for y in 0...4 {
                let rim = x < 0 || x > 12 || z < 0 || z > 12
                w.setBlock(bx + x, by + y, bz + z, y == 0 || (rim && y <= 2) ? STONE : AIR)
            } } }
            for _ in 0..<4 { w.fluidTick(); w.fluidTick(lava: true) }
            g.drops.items.removeAll()
        }
        func id(_ k: String) -> BlockID? { Blocks.has(k) ? Blocks.id(k) : nil }
        // (name, the block state: standing, or on the wall to its south)
        var kinds: [(String, BlockID)] = []
        for k in ["torch", "soul_torch", "copper_torch", "redstone_torch"] { if let b = id(k) { kinds.append((k, b)) } }
        for k in ["torch", "soul_torch", "copper_torch"] { if let b = id(k) { kinds.append((k + " on a wall", b + 1)) } }   // (state 1: on the wall to its south)
        if let b = id("redstone_torch[2]") { kinds.append(("redstone_torch on a wall", b)) }
        let giving = kinds.filter { World.washedAway[Int($0.1)] }.count
        check(kinds.count >= 6 && giving == kinds.count, "torchwater: every torch kind gives way to fluids (\(giving) of \(kinds.count) kinds)")
        // (and the other small things the reference's water washes off: ripe wheat, carrots, copper wire, a repeater, a
        // comparator, tripwire, a cobweb)
        for (k, st) in [("wheat", 7), ("carrots", 7), ("redstone_wire", 0), ("repeater", 0), ("comparator", 0), ("tripwire", 0), ("cobweb", 0)] {
            if let b = id(k) { kinds.append((k, b + BlockID(st))) }
        }

        for (fluid, lava) in [(WATER, false), (LAVA, true)] {
            var taken = 0, dropped = 0, droppers = 0
            var stood: [String] = [], dry: [String] = []
            for (name, b) in kinds {
                tray()
                // The torch on the floor at (6, 7); a wall torch there hangs on a stone post south of it, at (6, 8).
                let tx = bx + 6, tz = bz + 7
                if name.hasSuffix("on a wall") { w.setBlock(tx, by + 1, tz + 1, STONE); w.setBlock(tx, by + 2, tz + 1, STONE) }
                w.setBlock(tx, by + 1, tz, b)
                // The source two cells north: its flow reaches the torch's cell in the next steps.
                w.setBlock(tx, by + 1, tz - 2, fluid)
                for _ in 0..<(lava ? 30 : 20) { w.fluidTick(lava: lava) }
                let now = w.block(tx, by + 1, tz)
                if !World.washedAway[Int(now)] && Blocks.isLiquid(now) { taken += 1 } else { stood.append("\(name): \(Blocks.key(now))") }
                // (what breaking it by hand drops: a cobweb by hand drops nothing)
                if !Mining.drops(b, .empty).isEmpty {
                    droppers += 1
                    if !g.drops.items.isEmpty { dropped += 1 } else { dry.append(name) }
                } else if !g.drops.items.isEmpty { dropped += 1 }
            }
            check(taken == kinds.count, "torchwater: \(lava ? "lava" : "water") runs into every torch's (and crop's, wire's...) cell and takes it (\(taken) of \(kinds.count))"
                  + (stood.isEmpty ? "" : "; still standing: " + stood.joined(separator: ", ")))
            if lava { check(dropped == 0, "torchwater: what the lava takes burns (\(dropped) of \(kinds.count) left an item)") }
            else { check(dropped == droppers, "torchwater: what the water takes drops as items (\(dropped) of \(droppers))" + (dry.isEmpty ? "" : "; none from " + dry.joined(separator: ", "))) }
        }

        // Held torches clicked at the floor under a pool: refused, the pool left whole.
        g.survival = true
        p.flying = false
        for (fluid, word) in [(WATER, "water"), (LAVA, "lava")] {
            tray()
            // A pool of sources (no fluid step runs while he clicks, so it stays where it was poured).
            for z in 3...9 { for x in 3...9 { w.setBlock(bx + x, by + 1, bz + z, fluid) } }
            var refused = 0, tried = 0
            for (k, b) in [("torch", id("torch")), ("soul torch", id("soul_torch")), ("signal torch", id("redstone_torch"))] {
                guard let b, let item = Items.item(forBlock: b) else { continue }
                tried += 1
                g.inventory.held = ItemStack(item, 16)
                p.pos = V3(Float(bx) + 6.5, Float(by) + 1, Float(bz) + 11.5)     // (on the tray's floor south of the pool)
                p.vel = .zero
                p.yaw = 0; p.pitch = -45 * .pi / 180                        // (north, down at the floor under the pool's edge)
                g.input.rightClicked = false; g.input.rightDown = false
                g.lastRefusal = ""
                g.tick(1.0 / 60)
                p.pos = V3(Float(bx) + 6.5, Float(by) + 1, Float(bz) + 11.5); p.vel = .zero
                p.yaw = 0; p.pitch = -45 * .pi / 180
                g.input.rightClicked = true; g.input.rightDown = true
                g.tick(1.0 / 60)
                g.input.rightClicked = false; g.input.rightDown = false
                var torches = 0
                for z in 3...9 { for x in 3...9 { for y in 1...2 where World.washedAway[Int(w.block(bx + x, by + y, bz + z))] { torches += 1 } } }
                if torches == 0 && g.inventory.held.count == 16 && g.lastRefusal.contains(word) { refused += 1 }
                else { print("torchwater: \(k) at the \(word): \(torches) torches in the pool, \(g.inventory.held.count) held, refused \"\(g.lastRefusal)\"") }
            }
            check(tried >= 2 && refused == tried, "torchwater: a torch clicked into \(word) is refused (\(refused) of \(tried))")
        }
        tray()
        for z in -1...13 { for x in -1...13 { for y in 0...4 { w.setBlock(bx + x, by + y, bz + z, AIR) } } }
        g.drops.items.removeAll()
    }
}
