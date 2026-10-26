import Foundation
import simd

// P462 (Remington, Oct 25 16:33 in Capital City, his world seed 5381095465666589309 at 6581 1035: "The pillars are still
// floating"): questcheck --cityfloat builds that city on a field world (as his headset does) and looks for columns and
// posts standing half a block up, on a bottom slab (the covered walks' columns and lamp posts on the walkway's half steps).
enum CityFloatCheck {
    static func run(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let w = World(seed: 5381095465666589309, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 5; w.activeDistance = 5
        let at = V3(6581.5, 140, 1035.5)
        _ = w.loadSync(center: at, radius: 5)
        // A full block (a column, a post) standing on a bottom slab: its foot half a block over the slab's top.
        let slabs: [Bool] = (0..<Blocks.count).map { i in
            let k = Blocks.key(BlockID(i))
            return k.hasSuffix("_slab") || k.contains("_slab[") && !k.contains("top") && !k.contains("double")
        }
        var found: [IVec3] = []
        var kinds: [String: Int] = [:]
        let r = 5 * CS
        for z in (Int(at.z) - r)...(Int(at.z) + r) { for x in (Int(at.x) - r)...(Int(at.x) + r) {
            guard w.isLoaded(x, z) else { continue }
            for y in 100..<200 {
                let b = w.builtBlock(x, y, z)
                guard b != AIR, Blocks.opaque[Int(b)], slabs[Int(w.builtBlock(x, y - 1, z))] else { continue }
                found.append(IVec3(x, y, z))
                kinds[Blocks.key(Blocks.groupBase[Int(b)]) + " on " + Blocks.key(Blocks.groupBase[Int(w.builtBlock(x, y - 1, z))]), default: 0] += 1
            }
        } }
        let list = found.prefix(12).map { "\($0.x) \($0.y - 64) \($0.z)" }
        check(found.isEmpty, "cityfloat: \(found.count) blocks round Capital City at 6581 1035 stand half a block up on a slab (\(kinds.map { "\($0.key) \($0.value)" }.sorted().joined(separator: ", "))) "
              + list.joined(separator: "; "))
    }
}
