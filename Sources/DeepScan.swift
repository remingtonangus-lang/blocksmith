import Foundation

// P323 (d): the Deep's layers over a few seeds, generator only (questcheck --deepscan [SEEDS]): per column, the seal
// whole (8 layers of Sealrock), no open air in the lower crust between the vault's roof and the seal or in the hell
// band's floor (the "void below hell" a playtest dug into), the vault open under its roof, and the Sunderite seams
// just above the seal.
enum DeepScan {
    static func run(seeds: [UInt64] = [3931512493184456980, 1, 42, 777, 20261015], chunks: Int = 24) -> Int32 {
        var bad = 0
        let ore = Blocks.id("sunderite_ore")
        for seed in seeds {
            let dg = DeepGen(seed: seed)
            var cols = 0, sealHoles = 0, crustAir = 0, floorAir = 0, vaultShut = 0, seams = 0, oreBlocks = 0
            var rng = SRng(seed &+ 0xDEE5)
            for k in 0..<chunks {
                // (the playtest's column first, then spread out over ±20000)
                let cx = k == 0 ? floorDiv(11680, CS) : Int(rng.next() % 2500) - 1250
                let cz = k == 0 ? floorDiv(-13090, CS) : Int(rng.next() % 2500) - 1250
                let b = dg.generate(cx: cx, cz: cz)
                var chunkOre = 0
                for lz in 0..<CS { for lx in 0..<CS {
                    cols += 1
                    let wx = cx * CS + lx, wz = cz * CS + lz
                    let roof = dg.ceilingY(wx, wz)
                    for y in DeepSeal.bottom..<DeepSeal.top where b[Chunk.index(lx, y, lz)] != SEALROCK { sealHoles += 1 }
                    for y in (roof + 1)..<DeepSeal.bottom where b[Chunk.index(lx, y, lz)] == AIR { crustAir += 1 }
                    if b[Chunk.index(lx, DeepGen.hellBase, lz)] == AIR { floorAir += 1 }
                    if !dg.pillar(wx, wz) && b[Chunk.index(lx, roof - 8, lz)] != AIR && b[Chunk.index(lx, roof - 8, lz)] != Blocks.id("basalt")
                        && b[Chunk.index(lx, roof - 8, lz)] != LAMP { vaultShut += 1 }
                    for y in DeepGen.hellBase...(DeepGen.hellBase + 6) where b[Chunk.index(lx, y, lz)] == ore { chunkOre += 1 }
                } }
                oreBlocks += chunkOre
                if chunkOre > 0 { seams += 1 }
            }
            let ok = sealHoles == 0 && crustAir == 0 && floorAir == 0
            if !ok { bad += 1 }
            print("deepscan seed \(seed): \(cols) columns; seal holes \(sealHoles), crust air \(crustAir), hell floor air \(floorAir), "
                  + "vault roof cells not open \(vaultShut); Sunderite seams in \(seams)/\(chunks) chunks (\(oreBlocks) ore) \(ok ? "OK" : "FAIL")")
        }
        return bad == 0 ? 0 : 1
    }
}
