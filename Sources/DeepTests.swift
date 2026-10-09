import Foundation
import simd

// Task 22 checks (world depth, the Deep, the Ashguard war): part of `--questbugs`; `--questbugs --only deep` runs just these.
enum DeepTests {
    static func run(_ game: Game, _ check: (Bool, String) -> Void) {
        depthZone(game, check)
        floorMigration(check)
        deepWorld(check)
        seam(game, check)
    }

    // The Deep's layers: molten core, vault floor, the open vault, crust, hell band, upper crust; no bedrock anywhere;
    // fortresses in the hell band.
    static func deepWorld(_ check: (Bool, String) -> Void) {
        let g = DeepGen(seed: 12345)
        var bedrock = 0, coreOK = true, vaultAir = 0, vaultCols = 0, hellRack = 0, topSolid = true, floorSolid = true
        for (cx, cz) in [(20, 3), (-15, 9), (40, -30), (2, 2)] {
            let b = g.generate(cx: cx, cz: cz)
            for v in b where v == BEDROCK { bedrock += 1 }
            for lz in 0..<CS { for lx in 0..<CS {
                for y in 0...DeepGen.coreTop where b[Chunk.index(lx, y, lz)] != LAVA { coreOK = false }
                let wx = cx * CS + lx, wz = cz * CS + lz
                let f = g.floorY(wx, wz)
                if !g.pillar(wx, wz) && !g.lavaRiver(wx, wz) {
                    vaultCols += 1
                    if (f + 2..<(DeepGen.ceilingBase - 16)).allSatisfy({ b[Chunk.index(lx, $0, lz)] == AIR }) { vaultAir += 1 }
                    if !(DeepGen.coreTop + 1...f).allSatisfy({ Blocks.opaque[Int(b[Chunk.index(lx, $0, lz)])] || b[Chunk.index(lx, $0, lz)] == LAVA }) { floorSolid = false }
                }
                for y in DeepGen.hellBase..<DeepGen.crustTop where b[Chunk.index(lx, y, lz)] == NETHERRACK { hellRack += 1 }
                for y in (CH - 4)..<CH where !Blocks.opaque[Int(b[Chunk.index(lx, y, lz)])] { topSolid = false }
            } }
        }
        check(bedrock == 0, "deep: no bedrock in the Deep (\(bedrock))")
        check(coreOK && floorSolid, "deep: molten core under a solid vault floor")
        check(vaultAir > vaultCols * 9 / 10, "deep: the Ash Vault is open floor to roof (\(vaultAir) of \(vaultCols) columns)")
        check(hellRack > 4 * CSQ * 20, "deep: the hell band holds cinderstone terrain (\(hellRack))")
        check(topSolid, "deep: the top four layers are solid rock (digging down from the surface carries on)")
        let fort = g.structures?.nearest("fortress", x: 0, z: 0)
        check(fort.map { $0.anchor.y > DeepGen.hellBase + 40 && $0.anchor.y < DeepGen.hellBase + 80 } ?? false,
              "deep: fortresses stand in the hell band (nearest at \(fort.map { "\($0.anchor.x) \($0.anchor.y) \($0.anchor.z)" } ?? "none"))")
    }

    // Digging through the surface's bottom layer lands you at the top of the Deep and climbing out of its top layer
    // brings you back; the vault's updrafts catch a long fall.
    static func seam(_ game: Game, _ check: (Bool, String) -> Void) {
        let home = game.player.pos, homeDim = game.dim.dim
        game.player.pos = V3(40.5, 0.3, -20.5)
        game.deepTick(0.05)
        let x = 40, z = -21
        let w = game.world
        check(game.dim.dim == .deep && game.player.pos.y == Float(CH - 3) && w.block(x, CH - 3, z) == AIR && w.block(x, CH - 2, z) == AIR
              && Blocks.opaque[Int(w.block(x, CH - 4, z))], "deep: falling through the surface floor lands in a pocket at the top of the Deep")
        game.player.pos.y = Float(CH - 1)
        game.deepTick(0.05)
        check(game.dim.dim == .overworld && game.player.pos.y == 1 && game.world.block(x, 1, z) == AIR && Blocks.opaque[Int(game.world.block(x, 0, z))],
              "deep: climbing out of the Deep's top comes back up at the surface's floor")
        game.changeDimension(to: .deep, at: V3(300.5, 100, 40.5))
        game.player.onGround = false
        game.player.flying = false
        game.player.vel = V3(0, -20, 0)
        game.deepTick(0.05)
        check(game.effects.has(.slowFalling), "deep: the vault's updraft slows a long fall")
        game.effects.clear()
        if homeDim != game.dim.dim { game.changeDimension(to: homeDim, at: home) }
        game.player.pos = home
    }

    // The surface's lowest 64 layers: no bedrock floor, solid hot rock at the bottom, emberslate taking over with
    // depth, sealed lava pockets that never touch air.
    static func depthZone(_ game: Game, _ check: (Bool, String) -> Void) {
        let gen = WorldGen(seed: 12345)
        var bedrock = 0, openBottom = 0, ember = 0, deepRock = 0, lava = 0, leaky = 0, emberHigh = 0
        for cx in 0..<6 { for cz in 0..<6 {
            let b = gen.generate(cx: cx * 7 - 20, cz: cz * 5 - 12)
            for i in 0..<(CSQ * 5) where b[i] == BEDROCK { bedrock += 1 }
            for i in 0..<(CSQ * 3) where !Blocks.opaque[Int(b[i])] { openBottom += 1 }
            for lz in 1..<(CS - 1) { for lx in 1..<(CS - 1) {
                for y in 3..<(YOFF - 24) {
                    let i = Chunk.index(lx, y, lz), v = b[i]
                    if v == EMBERSLATE { ember += 1 } else if v == DEEPSLATE { deepRock += 1 }
                    if v == LAVA && y > YOFF - 55 {
                        lava += 1
                        for o in [1, -1, CS, -CS, CSQ, -CSQ] where !(Blocks.opaque[Int(b[i + o])] || b[i + o] == LAVA) { leaky += 1 }
                    }
                }
                for y in (YOFF - 8)..<YOFF where b[Chunk.index(lx, y, lz)] == EMBERSLATE { emberHigh += 1 }
            } }
        } }
        check(bedrock == 0, "deep: no bedrock floor in 36 new chunks (\(bedrock) bedrock blocks in layers 0-4)")
        check(openBottom == 0, "deep: the bottom 3 layers are solid (\(openBottom) open)")
        check(ember > deepRock, "deep: emberslate outnumbers deeprock below y -24 (\(ember) vs \(deepRock))")
        check(emberHigh == 0, "deep: no emberslate above y -8 (\(emberHigh))")
        check(lava > 200 && leaky == 0, "deep: sealed lava pockets above the lava sea (\(lava) lava, \(leaky) open faces)")
        // Tougher monsters deep down.
        let p0 = MobManager.depthPower(.overworld, Float(YOFF + 10)), p1 = MobManager.depthPower(.overworld, Float(YOFF - 60))
        let z = Mob(.zombie, at: game.player.pos + V3(0, 0, -3))
        z.equip = nil
        z.power = p1
        let h0 = z.health
        z.hit(from: game.player.pos, damage: 8, knockback: 0)
        check(p0 == 1 && p1 > 1.5 && h0 - z.health == 5, String(format: "deep: depth power 1 at y 10, %.2f at y -60; an 8 hit does %d", p1, h0 - z.health))
    }

    // Saved surface chunks lose the old bedrock floor as they load (other dimensions keep theirs); Remington's real worlds
    // (copied to a temp folder, never touched) still load every saved chunk.
    static func floorMigration(_ check: (Bool, String) -> Void) {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bs-floor-\(UInt32.random(in: 0...UInt32.max))")
        defer { try? fm.removeItem(at: tmp) }
        let sm = SaveManager(dir: tmp)
        var b = [BlockID](repeating: STONE, count: CSQ * CH)
        for i in 0..<(CSQ * 5) { b[i] = BEDROCK }
        b[CSQ * 5] = BEDROCK                                    // layer 5: not the old floor, kept
        sm.saveChunk(ChunkKey(x: 3, z: -2), b)
        let back = sm.loadChunk(ChunkKey(x: 3, z: -2)) ?? []
        let sub = sm.sub("DIM-1")
        sub.saveChunk(ChunkKey(x: 0, z: 0), b)
        let netherBack = sub.loadChunk(ChunkKey(x: 0, z: 0)) ?? []
        check(back.count == CSQ * CH && !back[0..<(CSQ * 5)].contains(BEDROCK) && back[CSQ * 5] == BEDROCK
              && netherBack.count == CSQ * CH && netherBack[0] == BEDROCK,
              "deep: saved surface chunks lose the bedrock floor on load, the Emberdeep keeps its own")
        // The real worlds on this Mac (if any): every chunk file still decodes.
        let worlds = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Blocksmith/Worlds")
        guard let names = try? fm.contentsOfDirectory(atPath: worlds.path), !names.isEmpty else { return }
        for n in names.sorted() {
            let src = worlds.appendingPathComponent(n)
            let copy = tmp.appendingPathComponent("w-\(n)")
            guard (try? fm.copyItem(at: src, to: copy)) != nil else { continue }
            let w = SaveManager(dir: copy)
            let files = (try? fm.contentsOfDirectory(atPath: w.chunkDir.path)) ?? []
            var ok = 0, bad = 0, floorLeft = 0
            for f in files where f.hasPrefix("c.") && f.hasSuffix(".lz") {
                let parts = f.dropFirst(2).dropLast(3).split(separator: ".")
                guard parts.count == 2, let x = Int(parts[0]), let z = Int(parts[1]) else { continue }
                if let c = w.loadChunk(ChunkKey(x: x, z: z)) {
                    ok += 1
                    if c[0..<(CSQ * 5)].contains(BEDROCK) { floorLeft += 1 }
                } else { bad += 1 }
            }
            check(w.loadMeta() != nil && bad == 0 && floorLeft == 0, "deep: saved world '\(n)' loads: \(ok) chunks, \(bad) unreadable, \(floorLeft) with the old floor")
        }
    }
}
