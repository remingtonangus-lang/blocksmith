import Foundation
import simd

// --rulescheck: world rules from the 2026-10-05 fidelity audits, built and run in a real world beside the player
// (the numbers-only ones are in --fidelitycheck): water heads for the nearest drop, broken ice leaves water, a struck
// target block powers and resets, grass spreads onto lit dirt, dropped experience drifts to the player.
enum RulesCheck {
    static func run(_ g: Game) -> Int {
        let w = g.world
        let p = g.player.pos
        var fails = 0
        func check(_ ok: Bool, _ what: String) {
            print("rulescheck: \(ok ? "PASS" : "FAIL") \(what)")
            if !ok { fails += 1 }
        }
        let floorY = Int(floor(p.y)) + 2
        var cx = Int(floor(p.x)) + 5
        let cz = Int(floor(p.z)) + 5
        // A clear 9x9 pad of stone with air above, a fresh one per case.
        func site() -> Int {
            let x = cx
            cx += 10
            for dx in -4...4 { for dz in -4...4 {
                w.setBlock(x + dx, floorY - 2, cz + dz, STONE)
                w.setBlock(x + dx, floorY - 1, cz + dz, STONE)
                for y in floorY...(floorY + 4) { w.setBlock(x + dx, y, cz + dz, AIR) }
            } }
            return x
        }
        let keepSurvival = g.survival
        g.survival = true

        // Water spreads only toward a drop in reach: a hole 2 east of the spring, nothing west.
        do {
            let x = site()
            w.setBlock(x + 3, floorY - 1, cz, AIR)
            w.setBlock(x + 3, floorY - 2, cz, AIR)
            w.setBlock(x, floorY, cz, WATER)
            w.scheduleFluid(around: IVec3(x, floorY, cz))
            for _ in 0..<30 { w.fluidTick() }
            let east = Blocks.isLiquid(w.block(x + 1, floorY, cz)), west = Blocks.isLiquid(w.block(x - 1, floorY, cz))
            check(east && !west, "water heads for the drop 3 east and not west (east \(east), west \(west))")
        }

        // Ice broken without Silk Touch over stone leaves water.
        do {
            let x = site()
            if Blocks.has("ice") {
                let ice = Blocks.id("ice")
                w.setBlock(x, floorY, cz, ice)
                g.breakBlock(IVec3(x, floorY, cz), ice, drop: true)
                check(Blocks.isLiquid(w.block(x, floorY, cz)), "broken ice leaves water")
            }
        }

        // A target block struck dead centre gives 15, and falls back to 0 after 8 ticks.
        do {
            let x = site()
            if Blocks.has("target") {
                let t = Blocks.id("target")
                let tp = IVec3(x, floorY, cz)
                w.setBlock(tp.x, tp.y, tp.z, t)
                w.redstone.hitTarget(tp, at: V3(Float(x) + 1, Float(floorY) + 0.5, Float(cz) + 0.5), arrow: true)
                let lit = Int(w.block(tp.x, tp.y, tp.z)) - Int(t)
                for _ in 0..<12 { w.redstone.tick() }
                let after = Int(w.block(tp.x, tp.y, tp.z)) - Int(t)
                check(lit == 15 && after == 0, "target block: centre hit 15 (\(lit)), back to 0 after 8 ticks (\(after))")
            }
        }

        // Grass spreads from lit grass onto open dirt beside it.
        do {
            let x = site()
            for dx in -1...1 { for dz in -1...1 { w.setBlock(x + dx, floorY - 1, cz + dz, DIRT) } }
            w.setBlock(x, floorY - 1, cz, GRASS)
            for _ in 0..<200 { g.grassTick(IVec3(x, floorY - 1, cz), GRASS) }
            var spread = 0
            for dx in -1...1 { for dz in -1...1 where (dx != 0 || dz != 0) && w.block(x + dx, floorY - 1, cz + dz) == GRASS { spread += 1 } }
            check(spread > 0, "grass spreads onto lit dirt (\(spread) of 8)")
        }

        // Experience dropped 3 blocks away drifts to the player and is collected.
        do {
            let lvl0 = g.xpLevel, pts0 = g.xpPoints
            g.addXPOrbs(30, at: g.player.pos + V3(3, 0.5, 0))
            for _ in 0..<200 { g.xpOrbTick(0.05) }
            check((g.xpLevel > lvl0 || g.xpPoints > pts0) && g.xpOrbs.isEmpty, "dropped experience drifts to the player and is collected")
        }

        g.survival = keepSurvival
        print("rulescheck: \(fails == 0 ? "PASS" : "\(fails) FAILED")")
        return fails
    }
}
