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
    static let capitalKeep: Float = 0.5        // G12 (Oct 11 playtest "capitals are far too common"); 0.7 before
    static let capitalKeepBeforeG12: Float = 0.7
    // P44 (Oct 11 evening): Capital cities and citadels about one per 4,000 x 4,000 blocks (a mansion's rarity), "the
    // world should look normal almost everywhere". Regions are 896 (cities) and 640 (citadels) blocks square, 20 and 39
    // of them to 4,000 x 4,000; about half of the kept regions find fit ground, so 1 in 10 and 1 in 20 keep. Ground saved
    // before P44 keeps the G12 shares (savedBeforeP44), so nothing explored loses half a structure.
    static let capitalKeepP44: Float = 0.1
    // The host checks (questcheck, --questbugs) keep the G12 shares so their fixture seeds still hold the cities and
    // citadels they test; the P44 check measures the real shares.
    static var p44 = true
    static let citadelKeepP44: Float = 0.05
    static let capitalMinApart: Float = 1200   // L3: no two Capital cities closer (checked over 50 seeds, --worldgencheck)
    static let citadelMinSpawn: Float = 640    // G12: "one sat at the player's spawn with a crawler" (320 before)
    static let citadelMinSpawnBeforeG12: Float = 320
    static let citadelKeep: Float = 0.6        // G12: the share of 40-chunk regions that keep their citadel
    static let citadelMinApart: Float = 800    // G12: "two within 500 blocks" (regions two apart are 880+ apart)
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

    // Ground near (cx, cz) saved before the L3 placement rules (capitals apart, camps' alternate spot and clear spawn).
    static func savedBeforeL3(_ gen: WorldGen, _ cx: Int, _ cz: Int, reach: Int) -> Bool {
        guard let sc = gen.structures else { return false }
        return !sc.clear(cx: cx, cz: cz, reach: reach, guardSet: sc.legacyL3) || explored(gen, cx, cz, reach: reach)
    }

    // Ground near (cx, cz) saved before G12 (rarer citadels and cities, citadels apart, cities of varied size).
    static func savedBeforeG12(_ gen: WorldGen, _ cx: Int, _ cz: Int, reach: Int) -> Bool {
        guard let sc = gen.structures else { return false }
        return !sc.clear(cx: cx, cz: cz, reach: reach, guardSet: sc.legacyG12)
    }
    // How far a citadel's or a city's G12 removal reaches into other placements: cities keep 240 blocks from a
    // citadel, camps 170 from a citadel and 240 from a city, Boreal stations 80. A citadel or city keeps the pre-G12
    // rules whenever ground this near was saved before G12, so a neighbour that gave way to it (or moved to its
    // alternate spot for it) on saved ground still does (verifier, PR #49).
    static let citadelLegacyReach = 28           // chunks from the citadel's chunk: 240 + a city's half width + margin
    static let capitalLegacyReach = 46           // chunks from the centre of a city region's 36-chunk placement square
    // Every city spot of region (rx, rz) uses the pre-G12 rules (keep share, size and mix) when ground anywhere they
    // reach was saved before G12: a spot 0 that now draws a smaller city and fails must not hand the region to a later
    // spot on saved ground.
    static func capitalLegacy(_ gen: WorldGen, _ rx: Int, _ rz: Int) -> Bool {
        savedBeforeG12(gen, rx * 56 + 18, rz * 56 + 18, reach: capitalLegacyReach)
    }
    static func capitalLegacyP44(_ gen: WorldGen, _ rx: Int, _ rz: Int) -> Bool {
        savedBeforeP44(gen, rx * 56 + 18, rz * 56 + 18, reach: capitalLegacyReach)
    }
    // Ground near (cx, cz) saved before P44 (the rarer cities and citadels).
    static func savedBeforeP44(_ gen: WorldGen, _ cx: Int, _ cz: Int, reach: Int) -> Bool {
        guard let sc = gen.structures else { return false }
        return !sc.clear(cx: cx, cz: cz, reach: reach, guardSet: sc.legacyP44)
    }

    // May a Capital city stand with its centre at chunk (cx, cz)?
    static func capitalAllowed(_ gen: WorldGen, _ cx: Int, _ cz: Int) -> Bool {
        if explored(gen, cx, cz, reach: 9) { return true }
        let c = spawnCentre(gen)
        if simd_length(V2(Float(cx * CS), Float(cz * CS)) - c) < capitalMinSpawn + margin { return false }
        let rx = floorDiv(cx, 56), rz = floorDiv(cz, 56)
        let keep = capitalLegacy(gen, rx, rz) ? capitalKeepBeforeG12 : (!p44 || capitalLegacyP44(gen, rx, rz) ? capitalKeep : capitalKeepP44)
        return hashf(rx, 7351, rz, UInt32(truncatingIfNeeded: gen.seed) ^ 0xCA91) < keep
    }

    // L3: no two Capital cities within `capitalMinApart`. Each region has a priority; a city gives way to a city of a
    // higher-priority neighbouring region that stands too close (regions are 56 chunks: cities two regions apart are
    // always 1,216+ blocks apart, so the 8 neighbours are enough). Asking a neighbour only ever climbs in priority, so
    // the lookups end. A city with ground saved before this rule stays (savedBeforeL3).
    static func capitalPriority(_ gen: WorldGen, _ rx: Int, _ rz: Int) -> Float {
        hashf(rx, 7353, rz, UInt32(truncatingIfNeeded: gen.seed) ^ 0xCA92)
    }
    static func capitalApart(_ gen: WorldGen, _ s: StructureStart, _ rx: Int, _ rz: Int, _ cx: Int, _ cz: Int) -> Bool {
        guard let sc = gen.structures, let t = sc.types.first(where: { $0.name == "capital_city" }) else { return true }
        if savedBeforeL3(gen, cx, cz, reach: 9) { return true }
        let mine = capitalPriority(gen, rx, rz)
        for dz in -1...1 { for dx in -1...1 where dx != 0 || dz != 0 {
            guard capitalPriority(gen, rx + dx, rz + dz) > mine, let o = sc.start(t, regionX: rx + dx, regionZ: rz + dz) else { continue }
            if simd_length(V2(Float(o.anchor.x - s.anchor.x), Float(o.anchor.z - s.anchor.z))) < capitalMinApart { return false }
        } }
        return true
    }

    // May a Capital citadel stand with its centre at chunk (cx, cz)? G12: farther from spawn and only some regions
    // keep theirs; ground saved before G12 keeps the old rule.
    static func citadelAllowed(_ gen: WorldGen, _ cx: Int, _ cz: Int) -> Bool {
        if explored(gen, cx, cz, reach: 5) { return true }
        let d = simd_length(V2(Float(cx * CS + 8), Float(cz * CS + 8)) - spawnCentre(gen))   // the anchor sits up to ~60 off the centre chunk
        if savedBeforeG12(gen, cx, cz, reach: citadelLegacyReach) { return d >= citadelMinSpawnBeforeG12 + 2 * margin }
        let rx = floorDiv(cx, 40), rz = floorDiv(cz, 40)
        let keep = !p44 || savedBeforeP44(gen, cx, cz, reach: citadelLegacyReach) ? citadelKeep : citadelKeepP44
        return d >= citadelMinSpawn + 2 * margin && hashf(rx, 7361, rz, UInt32(truncatingIfNeeded: gen.seed) ^ 0xC17A) < keep
    }

    // G12: no two citadels within `citadelMinApart`, by region priority as capitalApart does (a citadel gives way to a
    // higher-priority neighbour's that stands too close). Ground saved before G12 keeps its citadel.
    static func citadelApart(_ gen: WorldGen, _ cx: Int, _ cz: Int, anchor: IVec3) -> Bool {
        guard let sc = gen.structures, let t = sc.types.first(where: { $0.name == "military_base" }) else { return true }
        if explored(gen, cx, cz, reach: 5) || savedBeforeG12(gen, cx, cz, reach: citadelLegacyReach) { return true }
        let rx = floorDiv(cx, 40), rz = floorDiv(cz, 40)
        let mine = citadelPriority(gen, rx, rz)
        for dz in -1...1 { for dx in -1...1 where dx != 0 || dz != 0 {
            guard citadelPriority(gen, rx + dx, rz + dz) > mine, let o = sc.start(t, regionX: rx + dx, regionZ: rz + dz) else { continue }
            if simd_length(V2(Float(o.anchor.x - anchor.x), Float(o.anchor.z - anchor.z))) < citadelMinApart { return false }
        } }
        return true
    }
    static func citadelPriority(_ gen: WorldGen, _ rx: Int, _ rz: Int) -> Float {
        hashf(rx, 7363, rz, UInt32(truncatingIfNeeded: gen.seed) ^ 0xC17B)
    }
}
