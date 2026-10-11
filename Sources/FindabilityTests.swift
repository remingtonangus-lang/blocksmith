import Foundation
import simd

// The first citadel can be found (done audit 25b6, G6: radar and intercepted orders were base loot only, so the first
// base meant wandering ~1,200 blocks). Outlaw camps always hold intercepted orders and abandoned camps sometimes do;
// the first orders read point to a citadel. Run by questcheck and the Mac `--questbugs`.
enum FindabilityTests {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        // Every outlaw camp's chest holds orders (50 chests).
        var withOrders = 0
        for i in 0..<50 {
            let c = ItemContainer(27)
            var rng = SRng(UInt64(7919 &* (i + 1)))
            Loot.fill(c, table: "camp_outlaws", rng: &rng)
            if c.slots.contains(where: { !$0.isEmpty && Items.key($0.item) == "intercepted_orders" }) { withOrders += 1 }
        }
        check(withOrders == 50, "findability: every outlaw camp chest holds intercepted orders (\(withOrders) of 50)")
        // From spawn on six seeds: the nearest outlaw camp versus the nearest citadel.
        var camp: [Int] = [], base: [Int] = []
        for i in 0..<6 {
            let seed = UInt64(1000 + i * 7919)
            guard let sc = WorldGen(seed: seed).structures else { continue }
            let o = Game.spawnOrigin(seed: seed)
            let x = o.0 * 16, z = o.1 * 16
            func d(_ s: StructureStart?) -> Int { s.map { Int(simd_length(V2(Float($0.anchor.x - x), Float($0.anchor.z - z)))) } ?? 99999 }
            camp.append(d(sc.nearest("wild_camp", x: x, z: z, maxRegions: 4) { $0.kind == "camp_outlaws" }))
            base.append(d(sc.nearest("military_base", x: x, z: z, maxRegions: 4)))
        }
        let avg = { (a: [Int]) in a.isEmpty ? 0 : a.reduce(0, +) / a.count }
        check(!camp.isEmpty && avg(camp) < avg(base), "findability: an outlaw camp (orders) is nearer spawn than a citadel: camps \(camp) (avg \(avg(camp))), citadels \(base) (avg \(avg(base)))")
        // Reading the first orders marks a citadel (while none is on the map yet).
        guard g.dim.dim == .overworld else { return }
        if MapCache.shared.marks.contains(where: { $0.kind == "military_base" }) {
            print("findability: a citadel is already on this map; the first-orders check is skipped")
            return
        }
        let slot = g.inventory.selected
        let held = g.inventory.main[slot]
        defer { g.inventory.main[slot] = held }
        g.inventory.main[slot] = ItemStack(Items.id("intercepted_orders"), 1)
        let used = g.factionGearUse()
        let mark = MapCache.shared.marks.last
        check(used && mark?.kind == "military_base", "findability: the first orders read mark a citadel (\(mark?.kind ?? "nothing"))")
    }
}
