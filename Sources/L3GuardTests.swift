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
}
