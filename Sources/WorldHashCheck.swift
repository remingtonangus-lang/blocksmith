import Foundation

// Ledger 280's proof (`questcheck --worldhash`): prints one hash per seed of every rail plan of rows -3...3 and stretches
// -1...1 (7 x 3 lines of 6 village regions each: 126 regions a seed), every default-accept `nearest` answer of each
// structure kind on a grid round the origin, and the blocks of 208 chunks. Run it with the old switches
// (BS_OLDNEAREST=1 BS_OLDSTARTCAP=1) and without: the worlds are the same when every line matches.
enum WorldHashCheck {
    static func mix(_ h: inout UInt64, _ v: Int) { h = (h ^ UInt64(bitPattern: Int64(v))) &* 0x100000001b3 }

    static func run(_ makeWorld: (UInt64) -> World) {
        for seed: UInt64 in [3084501862406496736, 12345, 9_876_543_210] {
            let w = makeWorld(seed)
            guard let wg = w.gen as? WorldGen else { print("worldhash: seed \(seed) not a WorldGen"); continue }
            var rails: UInt64 = 0xcbf29ce484222325, near: UInt64 = 0xcbf29ce484222325, blocks: UInt64 = 0xcbf29ce484222325
            var lines = 0, cells = 0, answers = 0
            for row in -3...3 { for s in -1...1 {
                guard let l = Railways.line(wg, row: row, stretch: s) else { mix(&rails, -1); continue }
                lines += 1; cells += l.cells.count
                mix(&rails, l.cells.count); for c in l.cells { mix(&rails, c.x); mix(&rails, c.y); mix(&rails, c.z) }
                for st in l.stations { mix(&rails, st.x); mix(&rails, st.z) }
            } }
            if let sc = w.gen.structures {
                for t in sc.types { for gz in stride(from: -4096, through: 4096, by: 512) { for gx in stride(from: -4096, through: 4096, by: 512) {
                    let s = sc.nearest(t.name, x: gx, z: gz, maxRegions: 3)
                    answers += 1
                    if let s { mix(&near, s.anchor.x); mix(&near, s.anchor.z); mix(&near, s.min.y) } else { mix(&near, -1) }
                } } }
            }
            var wet = 0
            let fl0 = FieldTerrain.floatersDropped, pk0 = FieldTerrain.pocketsFilled
            // 64 spread chunks (seas, shores, hills) and 144 side by side round the 39 b/s flight's start (caves, ravines)
            var keys: [ChunkKey] = []
            for cz in -4..<4 { for cx in -4..<4 { keys.append(ChunkKey(x: cx * 37, z: cz * 29)) } }
            for cz in 45..<57 { for cx in 127..<139 { keys.append(ChunkKey(x: cx, z: cz)) } }
            for k in keys {
                let p = w.produceNow(k)
                if let st = p.store, st.data.contains(WATER) { wet += 1 } else if p.blocks.contains(WATER) { wet += 1 }
                for b in p.blocks { mix(&blocks, Int(b)) }
                if let st = p.store {
                    for b in st.data { mix(&blocks, Int(b)) }
                    for d in st.fd { mix(&blocks, Int(d)) }
                    for m in st.fm { mix(&blocks, Int(m)) }
                    for k in st.fine.keys.sorted() { mix(&blocks, k); for d in st.fine[k]! { mix(&blocks, Int(d)) } }
                }
                for (q, _) in p.entities { mix(&blocks, q.x); mix(&blocks, q.y); mix(&blocks, q.z) }
            }
            print(String(format: "worldhash: seed %llu rails %016llx (%d lines, %d cells) nearest %016llx (%d answers) chunks %016llx",
                         seed, rails, lines, cells, near, answers, blocks))
            print("worldhash: chunks holding water \(wet) of \(keys.count), floater cells dropped \(FieldTerrain.floatersDropped - fl0), pocket cells filled \(FieldTerrain.pocketsFilled &- pk0)")
            print("worldhash: starts made \(StructureCache.startsMade), evictions \(StructureCache.evictions), memo hits \(StructureCache.nearHits) misses \(StructureCache.nearMisses)")
        }
    }
}
