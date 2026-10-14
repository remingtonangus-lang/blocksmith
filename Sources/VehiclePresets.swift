import Foundation
import simd

// D43: vehicle presets unlocked by blueprints, a stage at a time. The Vehicle Works always knows the Field Tank; four
// more drawings turn up as Vehicle Blueprints in chests along the spine, each where its stage takes you, about one
// chest in fourteen of those places:
//   Scout Buggy  (a town)      camps' and towns' chests      four wheels, an engine, quick and unarmed
//   Gun Truck    (Greywall)    Greywall bases' chests        six wheels and a light gun on a turret
//   Heavy Tank   (the fleet)   wrecks, dockyards, vessels    ten wheels, two engines, a twin-gun turret
//   Siege Gun    (hell)        the Ashguard's and hell's     eight wheels, a three-barrel turret with long tubes
// Read one (use it) and the Works learns it for good (Blueprints.known, "vehicle:<key>"); with more than one known,
// using the Works asks which to build (VehicleWorksMenu), showing the parts each still needs.
enum VehiclePresets {
    struct Preset {
        let key: String, name: String, stage: Int
        let bill: [(String, Int)]
        let blueprint: () -> Blueprint
    }
    static let itemKey = "vehicle_blueprint"
    static let chestChance = 70                         // per thousand chests of a stage's places

    static let all: [Preset] = [
        Preset(key: "field_tank", name: "Field Tank", stage: 0, bill: VehicleWorks.bill, blueprint: VehicleWorks.fieldTank),
        Preset(key: "scout_buggy", name: "Scout Buggy", stage: 1,
               bill: [("iron_ingot", 32), ("ship_engine", 1), ("ship_wheel", 4), ("ship_helm", 1)],
               blueprint: { vehicle(halfWidth: 2, length: 8, wheels: 2, engines: 1, guns: 0, tube: 0) }),
        Preset(key: "gun_truck", name: "Gun Truck", stage: 2,
               bill: [("iron_ingot", 64), ("ship_engine", 1), ("ship_wheel", 6), ("ship_turret_ring", 1), ("ship_cannon", 1), ("ship_helm", 1)],
               blueprint: { vehicle(halfWidth: 3, length: 11, wheels: 3, engines: 1, guns: 1, tube: 3) }),
        Preset(key: "heavy_tank", name: "Heavy Tank", stage: 3,
               bill: [("iron_ingot", 160), ("ship_engine", 2), ("ship_wheel", 10), ("ship_turret_ring", 1), ("ship_cannon", 2), ("ship_helm", 1)],
               blueprint: { vehicle(halfWidth: 4, length: 15, wheels: 5, engines: 2, guns: 2, tube: 5) }),
        Preset(key: "siege_gun", name: "Siege Gun", stage: 4,
               bill: [("iron_ingot", 192), ("ship_engine", 2), ("ship_wheel", 8), ("ship_turret_ring", 1), ("ship_cannon", 3), ("ship_helm", 1)],
               blueprint: { vehicle(halfWidth: 4, length: 14, wheels: 4, engines: 2, guns: 3, tube: 7) }),
    ]

    static func knownKey(_ p: Preset) -> String { "vehicle:" + p.key }
    static func knows(_ p: Preset) -> Bool { p.stage == 0 || Blueprints.known.contains(knownKey(p)) }
    static func known(_ g: Game) -> [Preset] { g.survival ? all.filter { knows($0) } : all }

    // A wheeled hull, front toward -Z, wheels at y 0, centreline x 0 (the Field Tank's build, sized).
    static func vehicle(halfWidth hw: Int, length L: Int, wheels n: Int, engines: Int, guns: Int, tube: Int) -> Blueprint {
        let b = Blueprint()
        for i in 0..<n {
            let zc = n == 1 ? L / 2 : 2 + (L - 4) * i / (n - 1)
            for x in [-hw - 1, hw + 1] {
                for y in 0...2 { for z in (zc - 1)...(zc + 1) where (y - 1) * (y - 1) + (z - zc) * (z - zc) <= 1 { b.set(x, y, z, "ship_wheel") } }
            }
        }
        b.box(-hw, hw, 1, 3, 0, L, "iron_block", hollow: true)
        b.set(0, 2, L - 2, "ship_engine")
        if engines > 1 { b.set(0, 2, 2, "ship_engine") }
        for z in 0...L { b.set(-hw, 4, z, "iron_bars"); b.set(hw, 4, z, "iron_bars") }
        for x in (-hw + 1)...(hw - 1) { b.set(x, 4, 0, "iron_bars") }
        b.set(0, 4, L - 1, "ship_helm[south]")
        guard guns > 0 else { return b }
        let ring = IVec3(0, 4, L / 2 - 1)
        b.set(ring.x, ring.y, ring.z, "ship_turret_ring")
        let t = Blueprint()
        let r = guns > 2 ? 2 : (hw > 3 ? 2 : 1)
        t.box(-r, r, 0, 2, -r, r, "iron_block", hollow: true)
        let xs: [Int] = guns == 1 ? [0] : (guns == 2 ? [-1, 1] : [-1, 0, 1])
        for x in xs {
            if tube > 0 { for z in (-r - tube)...(-r - 1) { t.set(x, 1, z, "iron_block") } }
            t.set(x, 1, -r - tube - 1, "ship_cannon[south]")
        }
        b.turrets.append((ring, t))
        return b
    }

    // MARK: The drawings

    static func stack(_ i: Int) -> ItemStack {
        var s = ItemStack(Items.id(itemKey), 1)
        s.tag = i + 1
        s.label = "Vehicle Blueprint: " + all[i].name
        return s
    }
    static func preset(_ s: ItemStack) -> Int? {
        guard !s.isEmpty, Items.key(s.item) == itemKey, s.tag > 0, s.tag <= all.count else { return nil }
        return s.tag - 1
    }

    // Which preset a chest's table may hold (the stage its place belongs to).
    static func forTable(_ t: String) -> Int? {
        if t.hasPrefix("camp_") || t.hasPrefix("village") || t.hasPrefix("town") || t.hasPrefix("shop_") { return 1 }
        if t.hasPrefix("greywall") { return 2 }
        if t.hasPrefix("port_") || t.hasPrefix("shipwreck") || t.hasPrefix("steelhold") || t.hasPrefix("military") { return 3 }
        if t.hasPrefix("ash") || t.hasPrefix("nether") || t.hasPrefix("bastion") || t.hasPrefix("fortress") || t.hasPrefix("ruined_portal") { return 4 }
        return nil
    }

    // Loot.fill (beside Blueprints.addToChest).
    static func addToChest(_ c: ItemContainer, table: String, rng: inout SRng) {
        guard Items.has(itemKey), c.count > 1, let i = forTable(table), !table.hasPrefix("shop_register") else { return }
        guard rng.int(1000) < chestChance else { return }
        let free = c.slots.indices.filter { c[$0].isEmpty }
        guard !free.isEmpty else { return }
        c[free[rng.int(free.count)]] = stack(i)
    }
}

extension Game {
    // Reading a vehicle blueprint teaches the Works its preset.
    func vehicleBlueprintUse() -> Bool {
        guard let i = VehiclePresets.preset(held) else { return false }
        let p = VehiclePresets.all[i]
        let k = VehiclePresets.knownKey(p)
        if Blueprints.known.contains(k) && survival {
            onToast?("The Vehicle Works already knows the \(p.name)")
            return true
        }
        Blueprints.known.insert(k)
        if survival { consumeHeld() }
        sfx(.pageTurn, 0.8, at: player.pos)
        onToast?("Vehicle blueprint learned: \(p.name). Build it at a Vehicle Works")
        return true
    }
}

final class VehicleWorksMenu: ListMenu {
    enum Act { case build(VehiclePresets.Preset), takeOut(Int), store(Ship), recall(Ship) }
    let at: IVec3
    var acts: [Act] = []
    init(game g: Game, at p: IVec3) {
        at = p
        super.init("Vehicle Works", game: g)
        subtitle = "Build from a drawing, or see to your vehicles"
    }
    override var rows: [Row] {
        acts = []
        var out: [Row] = []
        let c = V3(Float(at.x) + 0.5, Float(at.y), Float(at.z) + 0.5)
        for v in VehiclePresets.known(game) {
            let short = VehicleWorks.missing(game, v.bill)
            let detail = short.isEmpty ? "All parts in your pack"
                : "Needs " + short.prefix(2).map { "\($0.1) \(Items.def(Items.id($0.0)).display)" }.joined(separator: ", ") + (short.count > 2 ? "..." : "")
            acts.append(.build(v))
            out.append(Row(name: "Build a \(v.name)", detail: detail, value: "", enabled: short.isEmpty, good: short.isEmpty))
        }
        for (i, st) in VehicleDepot.garage().enumerated() {                         // D44: the garage
            acts.append(.takeOut(i))
            out.append(Row(name: "Take out the \(st.name)", detail: "In the garage", value: "", enabled: true, good: true))
        }
        for s in VehicleDepot.yours(game) {
            let near = game.world.ships.boundsDistance(s, c) < VehicleDepot.garageReach
            let busy = VehicleDepot.busy(game, s)
            if near {
                acts.append(.store(s))
                out.append(Row(name: "Garage the \(s.name)", detail: busy ? "Step off her first" : "Store her out of the weather", value: "",
                               enabled: !busy, good: true))
            } else {
                let price = game.survival ? Money.format(VehicleDepot.recallPrice) : ""
                acts.append(.recall(s))
                out.append(Row(name: "Recall the \(s.name)", detail: String(format: "%.0f blocks off: brought by road", simd_length(s.pos - c)),
                               value: price, enabled: !busy && (!game.survival || game.money >= VehicleDepot.recallPrice), good: true))
            }
        }
        corner = "Wallet " + Money.format(game.money)
        return out
    }
    override func pressed(_ i: Int) {
        _ = rows
        guard i < acts.count else { return }
        switch acts[i] {
        case .build(let v):
            if VehicleWorks.build(game, at, v) { game.closeMenu() } else { say("Not yet: see what it needs", good: false) }
        case .takeOut(let k):
            let r = VehicleDepot.takeOut(game, k, at: at)
            if r.1 { game.closeMenu() } else if !r.0.isEmpty { say(r.0, good: false) }
        case .store(let s):
            let r = VehicleDepot.store(game, s); say(r.0, good: r.1)
        case .recall(let s):
            let r = VehicleDepot.recall(game, s, at: at)
            if r.1 { game.closeMenu(); game.onToast?(r.0) } else { say(r.0, good: false) }
        }
    }
}
