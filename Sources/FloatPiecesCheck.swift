import Foundation
import simd

// questcheck --floatpieces (and the full suite): his note Nov 14 20:58:21, Savanna by a Capital citadel just after his
// Ironback Crawler's battle with it ("All right, looks like we got some floating pieces here"). What a battle leaves
// lying (a soldier's body where he fell, a broken block's pieces) sleeps once still, and only a block broken by hand
// woke it: when a shell's blast, a bowl's carving or a collapse then took what it lay on, it slept on in the air.
// On made ground: a stone pillar 9 high and 7 across, a soldier killed on its top and a broken block's pieces beside him; once both
// sleep the pillar's top 4 courses go as a bowl's carving takes cells (setBlockAsync), and both must come down onto
// what is left. BS_OLDDEBRISWAKE=1 for before (World.supportGone).
enum FloatPiecesCheck {
    static func run(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let w = World(seed: 4242, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 3; w.activeDistance = 3
        let g = Game(world: w, save: nil, persistent: false)
        g.paused = false; g.survival = false
        let at = V3(40, 200, 40)
        g.player.pos = at; g.player.flying = true
        w.activeCenter = at
        _ = w.loadSync(center: at, radius: 3)
        func top(_ x: Int, _ z: Int) -> Int { var y = CH - 2; while y > 1 && !Blocks.collide[Int(w.block(x, y, z))] { y -= 1 }; return y }
        let x0 = 52, z0 = 40
        var base = 0
        for dz in -3...3 { for dx in -3...3 { base = max(base, top(x0 + dx, z0 + dz) + 1) } }
        let roof = base + 9                                   // (the pillar's top cells at roof - 1)
        let stone = Blocks.has("capital_stone") ? Blocks.id("capital_stone") : STONE
        for dz in -3...3 { for dx in -3...3 {
            for y in (top(x0 + dx, z0 + dz) + 1)..<roof { w.setBlock(x0 + dx, y, z0 + dz, stone) }
            for y in roof..<(roof + 4) { w.setBlock(x0 + dx, y, z0 + dz, AIR) }
        } }
        g.player.pos = V3(Float(x0) + 0.5, Float(roof) + 2, Float(z0) - 10.5)
        for _ in 0..<12 { g.tick(1.0 / 72) }
        // A soldier killed on the pillar's top, and a broken block's pieces beside him.
        let m = Mob(.soldierTrooper, at: V3(Float(x0) + 0.5, Float(roof), Float(z0) + 0.5))
        g.mobs.mobs.append(m)
        g.tick(1.0 / 72)
        m.health = 0
        g.tick(1.0 / 72)
        g.debris.bits(stone, at: V3(Float(x0) + 1.3, Float(roof) + 0.6, Float(z0) + 1.3), size: SIMD3(0.8, 0.8, 0.8), direction: V3(0, 1, 0),
                      count: 3, speed: 0.2, seed: 77)
        let rag = g.mobs.corpses.first { $0 === m }?.ragdoll
        func bodyY() -> Float { rag.map { g.debris.ragdolls.pose($0.id, 0).position.y } ?? m.pos.y }
        func piecesY() -> [Float] { var ys: [Float] = []; g.debris.bodies.forEachLive { _, p, _, _, _ in ys.append(p.y) }; return ys }
        func piecesAwake() -> Int { var n = 0; g.debris.bodies.forEachLive { s, _, _, _, _ in if g.debris.bodies.isAwake(s) { n += 1 } }; return n }
        // Still: the body asleep and the pieces too (at most 4 s).
        var t = 0
        while t < 288 && ((rag.map { g.debris.ragdolls.isAwake($0.id) } ?? false) || piecesAwake() > 0) { g.tick(1.0 / 72); t += 1 }
        let body0 = bodyY(), pieces0 = piecesY()
        let slept = t < 288
        // The top 4 courses go, cell by cell, as a crater's carving takes them.
        let cut = roof - 4
        for y in stride(from: roof - 1, through: cut, by: -1) { for dz in -3...3 { for dx in -3...3 { _ = w.setBlockAsync(x0 + dx, y, z0 + dz, AIR) } } }
        let woke0 = DebrisField.woke
        for _ in 0..<(72 * 3) { g.tick(1.0 / 72) }
        let body1 = bodyY(), pieces1 = piecesY()
        let pieceHigh = pieces1.filter { $0 > Float(cut) + 1.5 }.count
        let bodyDown = body1 < Float(cut) + 1.5
        let onTop = body0 > Float(cut) + 3 && pieces0.allSatisfy { $0 > Float(cut) + 3 }       // (both lay on the top before)
        check(rag != nil && slept && onTop && !pieces0.isEmpty && bodyDown && pieceHigh == 0,
              String(format: "floatpieces: a soldier killed on a pillar's top and a broken block's pieces by him, asleep (%@, %.1f s), come down when the 4 courses under them are carved away (the body %.1f -> %.1f over the pillar's new top at %d; %d of %d pieces left over it; %d sleepers woken; BS_OLDDEBRISWAKE=%d)",
                     rag == nil ? "no ragdoll" : (slept ? "yes" : "no"), Float(t) / 72, body0 - Float(cut), body1 - Float(cut), cut - YOFF,
                     pieceHigh, pieces1.count, DebrisField.woke - woke0, World.oldDebrisWake ? 1 : 0))
    }
}
