import Foundation
import simd

// L3 placement rules and old saves (docs/status/l3-part3.md): a Capital city too near a stronger neighbour is dropped,
// unless its ground was saved before the rule (StructureCache.legacyL3, structure-guard-l3.txt); the same guard keeps
// camps as they were.
enum L3GuardTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        guard let gen = g.world.gen as? WorldGen, let sc = gen.structures, let t = sc.types.first(where: { $0.name == "capital_city" }) else {
            check(false, "l3 guard: the overworld has Capital cities"); return
        }
        let span = t.spacing * CS
        let c = WorldRules.spawnCentre(gen)
        let rx0 = floorDiv(Int(c.x), span), rz0 = floorDiv(Int(c.y), span)
        // A real city, and a made-up one 300 blocks from it in a weaker neighbouring region.
        var found: (StructureStart, Int, Int)?
        for rz in (rz0 - 3)...(rz0 + 3) { for rx in (rx0 - 3)...(rx0 + 3) where found == nil {
            if let s = sc.start(t, regionX: rx, regionZ: rz) { found = (s, rx, rz) }
        } }
        guard let (city, rx, rz) = found else { check(false, "l3 guard: a Capital city within 3 regions of the spawn"); return }
        let mine = WorldRules.capitalPriority(gen, rx, rz)
        var weak: (Int, Int)?
        for dz in -1...1 { for dx in -1...1 where (dx != 0 || dz != 0) && weak == nil && WorldRules.capitalPriority(gen, rx + dx, rz + dz) < mine { weak = (rx + dx, rz + dz) } }
        guard let (wx, wz) = weak else { check(false, "l3 guard: a weaker region beside the city"); return }
        let a = IVec3(city.anchor.x + 300, city.anchor.y, city.anchor.z)
        let fake = StructureStart(kind: "capital_city", pieces: [], anchor: a)
        let cx = floorDiv(a.x, CS), cz = floorDiv(a.z, CS)
        let saved = sc.legacyL3, explored = sc.explored
        defer { sc.legacyL3 = saved; sc.explored = explored }
        sc.legacyL3 = []; sc.explored = []
        let dropped = !WorldRules.capitalApart(gen, fake, wx, wz, cx, cz)
        sc.legacyL3 = [StructureCache.key(cx + 2, cz - 1)]                 // one chunk of its ground saved before the rule
        let kept = WorldRules.capitalApart(gen, fake, wx, wz, cx, cz)
        let camp = WorldRules.savedBeforeL3(gen, cx, cz, reach: 2) && !WorldRules.savedBeforeL3(gen, cx + 10, cz, reach: 2)
        check(dropped && kept && camp,
              "l3 guard: a city 300 blocks from a stronger one is dropped (\(dropped)), kept where its ground was saved before the rule (\(kept)); camps read the same guard (\(camp))")
    }

    // G12 and old saves (verifier, PR #49): ground saved before G12 (StructureCache.legacyG12) keeps a citadel that the
    // new keep share drops, even when the saved chunk is a neighbour's (a city 240 blocks off gave way to it); keeps a
    // city region's old rules (keep share 0.7, the large plan) for every spot; and keeps a camp the new thinning drops
    // when the saved ground is at the region's alternate spot.
    static func g12(_ g: Game, check: (Bool, String) -> Void) {
        guard let gen = g.world.gen as? WorldGen, let sc = gen.structures else { check(false, "g12 guard: the overworld has structures"); return }
        let saved = sc.legacyG12, explored = sc.explored
        defer { sc.legacyG12 = saved; sc.explored = explored }
        sc.explored = []
        let s32 = UInt32(truncatingIfNeeded: gen.seed)
        // A citadel region the keep share drops, well clear of the spawn.
        let sp = WorldRules.spawnCentre(gen)
        let sr = (floorDiv(Int(sp.x), 40 * CS), floorDiv(Int(sp.y), 40 * CS))
        var cit: (Int, Int)?
        for rz in (sr.1 + 3)...(sr.1 + 12) { for rx in (sr.0 + 3)...(sr.0 + 12) where cit == nil && hashf(rx, 7361, rz, s32 ^ 0xC17A) >= WorldRules.citadelKeep { cit = (rx * 40 + 5, rz * 40 + 5) } }
        guard let (ccx, ccz) = cit else { check(false, "g12 guard: a citadel region the keep share drops"); return }
        sc.legacyG12 = []
        let dropped = !WorldRules.citadelAllowed(gen, ccx, ccz)
        sc.legacyG12 = [StructureCache.key(ccx + 22, ccz)]                 // a chunk 350 blocks off: a neighbour's ground
        let kept = WorldRules.citadelAllowed(gen, ccx, ccz) && WorldRules.citadelApart(gen, ccx, ccz, anchor: IVec3(ccx * CS, 0, ccz * CS))
        // A city region the new keep share drops but the old one kept; legacy ground near its far corner.
        let cr = (floorDiv(Int(sp.x), 56 * CS), floorDiv(Int(sp.y), 56 * CS))
        var reg: (Int, Int)?
        for rz in (cr.1 + 3)...(cr.1 + 20) { for rx in (cr.0 + 3)...(cr.0 + 20) where reg == nil {
            let h = hashf(rx, 7351, rz, UInt32(truncatingIfNeeded: gen.seed) ^ 0xCA91)
            if h >= WorldRules.capitalKeep && h < WorldRules.capitalKeepBeforeG12 { reg = (rx, rz) }
        } }
        guard let (rx, rz) = reg else { check(false, "g12 guard: a city region between the keep shares"); return }
        let cx = rx * 56 + 3, cz = rz * 56 + 3
        sc.legacyG12 = []
        let cityDropped = !WorldRules.capitalAllowed(gen, cx, cz) && !WorldRules.capitalLegacy(gen, rx, rz)
        sc.legacyG12 = [StructureCache.key(rx * 56 + 35 + 20, rz * 56 + 35)]   // past the square's far corner
        let cityKept = WorldRules.capitalAllowed(gen, cx, cz) && WorldRules.capitalLegacy(gen, rx, rz)
        // A camp region the thinning drops; legacy ground only at its alternate spot.
        var camp: (UInt64, Int, Int)?
        for rz in 0...40 { for rx in 0...40 where camp == nil {
            let cx0 = rx * WildCamps.spacing, cz0 = rz * WildCamps.spacing
            let seed = sc.seed &+ 61733021 &+ UInt64(bitPattern: Int64(cx0 &* 31 &+ cz0))
            sc.legacyG12 = []
            if WildCamps.thinnedG12(gen, seed, cx0, cz0) { camp = (seed, cx0, cz0) }
        } }
        guard let (cs, cx0, cz0) = camp else { check(false, "g12 guard: a camp region the thinning drops"); return }
        let (ax, az) = WildCamps.alternateSpot(cs, cx0, cz0)
        sc.legacyG12 = [StructureCache.key(ax, az)]
        let campKept = !WildCamps.thinnedG12(gen, cs, cx0, cz0)
        check(dropped && kept && cityDropped && cityKept && campKept,
              "g12 guard: a dropped citadel stays with a neighbour's ground saved before G12 (\(dropped), \(kept)); a city region keeps the old rules for saved ground near any spot (\(cityDropped), \(cityKept)); a thinned camp stays with its alternate spot saved (\(campKept))")
    }
}
