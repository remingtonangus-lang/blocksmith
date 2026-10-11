import Foundation
import simd

// World-gen placement rules from Remington's Quest playtest of Oct 10 (docs/status/worldgen-oct10.md):
// - 09:22:48 "capital buildings are supposed to be more rare, why did I just find one": no Capital city within
//   `capitalMinSpawn` blocks of the spawn origin, and only `capitalKeep` of the regions keep their city.
// - Capital citadels (Steelhold) stay findable (Remington, playtest 2) but never stand on top of a new player:
//   at least `citadelMinSpawn` from the spawn origin.
// - 09:25:29/35 "these broken portals, not really any point": ruined gates no longer generate (OverworldStructures).
// A rule only applies where a save has not yet generated any chunk of the structure (StructureCache.explored, taken
// once from the chunk folder on the first load with these rules), so nothing already explored is cut in half.
enum WorldRules {
    static let capitalMinSpawn: Float = 1200
    static let capitalKeep: Float = 0.7
    static let capitalMinApart: Float = 1200   // L3: no two Capital cities closer (checked over 50 seeds, --worldgencheck)
    static let citadelMinSpawn: Float = 320
    static let margin: Float = 40              // the anchor sits off the site centre; settleSpawn moves the spawn a little

    // The world spawn (x, z): Game.findSpawn's terrain-only search, cached per seed (settleSpawn then moves it at
    // most 8 blocks). The search origin alone was up to ~150 blocks off: a city stood 1,119 from the real spawn.
    private static var spawnCache: [UInt64: V2] = [:]
    private static let lock = NSLock()
    static func spawnCentre(_ gen: WorldGen) -> V2 {
        lock.lock()
        if let c = spawnCache[gen.seed] { lock.unlock(); return c }
        lock.unlock()
        let p = Game.findSpawn(gen: gen, seed: gen.seed)
        let c = V2(p.x, p.z)
        lock.lock(); spawnCache[gen.seed] = c; lock.unlock()
        return c
    }

    static func explored(_ gen: WorldGen, _ cx: Int, _ cz: Int, reach: Int) -> Bool {
        guard let sc = gen.structures else { return false }
        return !sc.clear(cx: cx, cz: cz, reach: reach, guardSet: sc.explored)
    }

    // May a Capital city stand with its centre at chunk (cx, cz)?
    static func capitalAllowed(_ gen: WorldGen, _ cx: Int, _ cz: Int) -> Bool {
        if explored(gen, cx, cz, reach: 9) { return true }
        let c = spawnCentre(gen)
        if simd_length(V2(Float(cx * CS), Float(cz * CS)) - c) < capitalMinSpawn + margin { return false }
        let rx = floorDiv(cx, 56), rz = floorDiv(cz, 56)
        return hashf(rx, 7351, rz, UInt32(truncatingIfNeeded: gen.seed) ^ 0xCA91) < capitalKeep
    }

    // L3: no two Capital cities within `capitalMinApart`. Each region has a priority; a city gives way to a city of a
    // higher-priority neighbouring region that stands too close (regions are 56 chunks: cities two regions apart are
    // always 1,216+ blocks apart, so the 8 neighbours are enough). Asking a neighbour only ever climbs in priority, so
    // the lookups end. Cities already explored in a save stay.
    static func capitalPriority(_ gen: WorldGen, _ rx: Int, _ rz: Int) -> Float {
        hashf(rx, 7353, rz, UInt32(truncatingIfNeeded: gen.seed) ^ 0xCA92)
    }
    static func capitalApart(_ gen: WorldGen, _ s: StructureStart, _ rx: Int, _ rz: Int, _ cx: Int, _ cz: Int) -> Bool {
        guard let sc = gen.structures, let t = sc.types.first(where: { $0.name == "capital_city" }) else { return true }
        if explored(gen, cx, cz, reach: 9) { return true }
        let mine = capitalPriority(gen, rx, rz)
        for dz in -1...1 { for dx in -1...1 where dx != 0 || dz != 0 {
            guard capitalPriority(gen, rx + dx, rz + dz) > mine, let o = sc.start(t, regionX: rx + dx, regionZ: rz + dz) else { continue }
            if simd_length(V2(Float(o.anchor.x - s.anchor.x), Float(o.anchor.z - s.anchor.z))) < capitalMinApart { return false }
        } }
        return true
    }

    // May a Capital citadel stand with its centre at chunk (cx, cz)?
    static func citadelAllowed(_ gen: WorldGen, _ cx: Int, _ cz: Int) -> Bool {
        if explored(gen, cx, cz, reach: 5) { return true }
        return simd_length(V2(Float(cx * CS + 8), Float(cz * CS + 8)) - spawnCentre(gen)) >= citadelMinSpawn + 2 * margin   // the anchor sits up to ~60 off the centre chunk
    }
}
