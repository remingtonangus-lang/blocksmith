import Foundation

// One-time thinning of old animal crowds (audit 25b6 #3). Task 21 cut animal spawns for new chunks only, and animals
// never despawn, so worlds started before it kept their crowds. The first load of such a save (world format < 4:
// SaveMigration backs the whole folder up first) thins every stored chunk to `cap` wild animals. Never touched: tamed
// or owned animals, named, leashed, saddled, chested or armoured ones, babies, animals the player bred (`bred`, saved
// from now on) and anything standing within 4 blocks of a fence, gate or wall (a pen: grown-up farm animals bred
// before the `bred` flag existed). A marker file keeps it to once per world.
extension MobManager {
    static let thinCap = 4
    static let thinMarker = "animals-thinned"

    // Counts (removed, kept) for the log and the test.
    @discardableResult
    func thinOldCrowds(_ s: SaveManager) -> (removed: Int, kept: Int) {
        let marker = s.dir.appendingPathComponent(MobManager.thinMarker)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: marker.path) else { return (0, 0) }
        var removed = 0, kept = 0
        lazy var penT: [Bool] = (0..<Blocks.count).map {
            let k = Blocks.key(BlockID($0))
            return k.contains("fence") || k.hasSuffix("_wall") || k.contains("_wall[")
        }
        for (key, recs) in stored {
            let wild = recs.indices.filter { MobManager.thinnable(recs[$0]) }
            guard wild.count > MobManager.thinCap else { kept += recs.count; continue }
            // Pens: the chunk's saved blocks, read only for crowded chunks (a few per world).
            var penned = Set<Int>()
            if let b = s.loadChunk(key) {
                let pt = penT
                for i in wild {
                    let r = recs[i]
                    let lx = Int(floor(r.p[0])) - key.x * CS, ly = Int(floor(r.p[1])), lz = Int(floor(r.p[2])) - key.z * CS
                    search: for y in max(0, ly - 2)...min(CH - 1, ly + 2) {
                        for z in max(0, lz - 4)...min(CS - 1, lz + 4) {
                            for x in max(0, lx - 4)...min(CS - 1, lx + 4) where pt[Int(b[Chunk.index(x, y, z)])] {
                                penned.insert(i); break search
                            }
                        }
                    }
                }
            }
            let free = wild.filter { !penned.contains($0) }
            let drop = Set(free.dropFirst(max(0, MobManager.thinCap - penned.count)))
            removed += drop.count
            let left = recs.indices.filter { !drop.contains($0) }.map { recs[$0] }
            kept += left.count
            stored[key] = left
        }
        try? Data("removed \(removed) kept \(kept)\n".utf8).write(to: marker)
        if removed > 0 { print("save migration: thinned old animal crowds, \(removed) removed, \(kept) kept") }
        return (removed, kept)
    }

    // A wild animal of a creature kind the player has not marked as theirs in any way.
    static func thinnable(_ r: MobRecord) -> Bool {
        guard let kind = MobKind.named(r.k), kind.category == .creature else { return false }
        if r.baby == true || r.name != nil || r.knot != nil || r.persistent == true || r.villager != nil { return false }
        if r.inv != nil || (r.eq.map { $0.contains { $0.count > 0 } } ?? false) { return false }
        let ex = r.extra ?? [:]
        for k in ["owned", "saddle", "chest", "armor", "bond", "bxp", "bred", "collar", "sit", "hx"] where ex[k] != nil { return false }
        return true
    }
}
