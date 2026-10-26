import Foundation
import simd

// D44: fuel depots; recall or garage a vehicle.
//   fuel      your land vehicles (built at a Vehicle Works or round a helm on wheels) burn fuel: a full tank lasts
//             twenty minutes at full throttle, less at part throttle, nothing standing. Low at a fifth (a toast); dry,
//             the engines cough along at a crawl (15% throttle) so you're never stranded. The helm's HUD line shows it.
//   depots    a Fuel Pump (crafted: a bucket, a cauldron and iron; one stands on every dockyard's quay) fills the tank
//             of your vehicle within 14 blocks: $0.20 for each hundredth. A Fuel Can (general stores, or crafted from a
//             bucket, iron and coal) used at the helm or beside your vehicle pours in half a tank.
//   garage    at a Vehicle Works: put a vehicle of yours within 24 blocks in its garage (it's stored, out of the world),
//             take a garaged one out beside the Works, or recall one from anywhere for $50 (it's brought by road).
// Fuel and the garage are kept with the world (TownLaw.state.vehicleFuel, garage).
enum VehicleDepot {
    static let canKey = "fuel_can", pumpKey = "fuel_pump"
    static let burnSeconds: Float = 1200
    static let fumes: Float = 0.15, low: Float = 0.2
    static let pumpReach: Float = 14, garageReach: Float = 24
    static let pricePerHundredth = 20, recallPrice = 5000
    static var warned = Set<Int>(), dry = Set<Int>()
    static var refuels = 0, garaged = 0, recalled = 0       // (harness)

    // MARK: Fuel

    static func usesFuel(_ s: Ship) -> Bool { s.parent == nil && !s.wheels.isEmpty && s.role == nil && !s.kinematic }

    static func level(_ s: Ship) -> Float { TownLaw.state.vehicleFuel?["\(s.root.id)"] ?? 1 }
    static func setLevel(_ s: Ship, _ v: Float) {
        var m = TownLaw.state.vehicleFuel ?? [:]
        m["\(s.root.id)"] = max(0, min(1, v))
        TownLaw.state.vehicleFuel = m
        if v > fumes { dry.remove(s.root.id) }
        if v > low { warned.remove(s.root.id) }
    }

    // pilotTick, after the throttle is set: burn, and hold a dry vehicle to a crawl.
    static func burn(_ g: Game, _ s: Ship, _ dt: Float) {
        guard usesFuel(s), g.survival else { return }
        var f = level(s)
        if f > 0 { f -= abs(s.throttle) * dt / burnSeconds; setLevel(s, f) }
        if f <= 0 {
            s.throttle = max(-fumes, min(fumes, s.throttle))
            if !dry.contains(s.id) { dry.insert(s.id); g.onToast?("Out of fuel: the \(s.name) crawls on fumes") }
        } else if f < low && !warned.contains(s.id) {
            warned.insert(s.id)
            g.onToast?("Fuel low on the \(s.name)")
        }
    }

    static func hud(_ s: Ship) -> String? {
        guard usesFuel(s) else { return nil }
        return String(format: "  fuel %d%%", Int((level(s) * 100).rounded()))
    }

    // His dropship: the one he flies, else a taken one within r of p.
    static func dropship(_ g: Game, _ p: V3, _ r: Float) -> Ship? {
        if let s = g.world.ships.pilot?.root { return s.role == "dropship" ? s : nil }
        return g.world.ships.list.filter { $0.parent == nil && $0.role == "dropship" && $0.captured && !$0.wrecked
            && g.world.ships.boundsDistance($0, p) < r }.min { g.world.ships.boundsDistance($0, p) < g.world.ships.boundsDistance($1, p) }
    }

    // The nearest vehicle of yours that burns fuel, within r of p.
    static func nearestVehicle(_ g: Game, _ p: V3, _ r: Float) -> Ship? {
        g.world.ships.list.filter { usesFuel($0) && g.world.ships.boundsDistance($0, p) < r }
            .min { g.world.ships.boundsDistance($0, p) < g.world.ships.boundsDistance($1, p) }
    }

    // Game.openBlock: a pump.
    static func pump(_ g: Game, _ at: IVec3) {
        let c = V3(Float(at.x) + 0.5, Float(at.y), Float(at.z) + 0.5)
        guard let s = nearestVehicle(g, c, pumpReach) else { g.onToast?("No vehicle at the pump"); return }
        let need = Int(((1 - level(s)) * 100).rounded(.up))
        guard need > 0 else { g.onToast?("The \(s.name)'s tank is full"); return }
        let afford = g.survival ? min(need, g.money / pricePerHundredth) : need
        guard afford > 0 else { g.onToast?("Fuel is \(Money.format(pricePerHundredth)) a hundredth. You're broke"); return }
        if g.survival { g.money -= afford * pricePerHundredth }
        setLevel(s, level(s) + Float(afford) / 100)
        refuels += 1
        g.sfx(.bucketFill, 0.8, at: c)
        g.onToast?("Filled the \(s.name): fuel \(Int((level(s) * 100).rounded()))%" + (g.survival ? " for \(Money.format(afford * pricePerHundredth))" : ""))
    }

    // useGadget: a Fuel Can at the helm or beside your vehicle.
    static func useCan(_ g: Game) -> Bool {
        guard !g.held.isEmpty, Items.key(g.held.item) == canKey else { return false }
        // P461: a dropship of his (at its helm or within 6 blocks of its hull) takes a can as a third of its tank.
        if let d = dropship(g, g.player.pos, 6), let st = g.world.ships.capState[d.id] {
            guard st.fuel < CapitalState.dropFuel - 1 else { g.onToast?("The \(d.name)'s tanks are full"); return true }
            st.fuel = min(CapitalState.dropFuel, st.fuel + ShipManager.canFuel)
            if g.survival { g.consumeHeld() }
            refuels += 1
            g.sfx(.bucketEmpty, 0.8, at: g.player.pos)
            g.onToast?("Poured in a can: fuel \(Int((st.fuel / CapitalState.dropFuel * 100).rounded()))%")
            return true
        }
        let s = g.world.ships.pilot.map { $0.root } ?? nearestVehicle(g, g.player.pos, 6)
        guard let v = s, usesFuel(v) else { g.onToast?("No vehicle beside you"); return true }
        guard level(v) < 0.99 else { g.onToast?("The \(v.name)'s tank is full"); return true }
        setLevel(v, level(v) + 0.5)
        if g.survival { g.consumeHeld() }
        refuels += 1
        g.sfx(.bucketEmpty, 0.8, at: g.player.pos)
        g.onToast?("Poured in a can: fuel \(Int((level(v) * 100).rounded()))%")
        return true
    }

    // MARK: Garage and recall

    struct Stored { let name: String; let data: String }
    static func garage() -> [Stored] {
        (TownLaw.state.garage ?? []).compactMap { e in
            guard let i = e.firstIndex(of: "|") else { return nil }
            return Stored(name: String(e[..<i]), data: String(e[e.index(after: i)...]))
        }
    }

    // Vehicles of yours anywhere (land vehicles you built or bought), and whether the Works has anything to offer.
    static func yours(_ g: Game) -> [Ship] { g.world.ships.list.filter { usesFuel($0) } }
    static func anything(_ g: Game) -> Bool { !garage().isEmpty || !yours(g).isEmpty }

    static func busy(_ g: Game, _ s: Ship) -> Bool {
        let ships = g.world.ships
        return ships.pilot?.root === s || ships.aboard?.root === s
    }

    static func store(_ g: Game, _ s: Ship) -> (String, Bool) {
        let ships = g.world.ships
        guard !busy(g, s) else { return ("Step off the \(s.name) first.", false) }
        let all = ships.list.filter { $0.root === s }
        guard let d = ships.encode(all) else { return ("The \(s.name) won't fit in the garage.", false) }
        var gar = TownLaw.state.garage ?? []
        gar.append(s.name.replacingOccurrences(of: "|", with: " ") + "|" + d.base64EncodedString() + "#" + String(level(s)))
        TownLaw.state.garage = gar
        TownLaw.state.vehicleFuel?["\(s.id)"] = nil
        ships.remove(s)
        garaged += 1
        g.sfx(.engineStart, 0.4, at: g.player.pos)
        return ("The \(s.name) is in the garage.", true)
    }

    static func takeOut(_ g: Game, _ i: Int, at p: IVec3) -> (String, Bool) {
        let gar = garage()
        guard i < gar.count else { return ("", false) }
        guard let (c, yaw) = VehicleWorks.spot(g, p) else { return ("Clear the yard beside the Works first.", false) }
        var payload = gar[i].data, fuel: Float = 1
        if let h = payload.lastIndex(of: "#") { fuel = Float(payload[payload.index(after: h)...]) ?? 1; payload = String(payload[..<h]) }
        guard let raw = Data(base64Encoded: payload), let roots = restore(g, raw), let s = roots.first else { return ("The garage has lost that one.", false) }
        s.rot = Quat(angle: yaw, axis: V3(0, 1, 0))
        s.pos = c + V3(0, 3, 0)
        s.vel = .zero; s.angVel = .zero
        s.prevRot = s.rot
        VehicleWorks.settle(s, on: c)
        setLevel(s, fuel)
        var left = TownLaw.state.garage ?? []
        if i < left.count { left.remove(at: i) }
        TownLaw.state.garage = left
        g.sfx(.engineStart, 1, at: c)
        return ("The \(s.name) rolls out of the garage.", true)
    }

    static func recall(_ g: Game, _ s: Ship, at p: IVec3) -> (String, Bool) {
        guard !busy(g, s) else { return ("You're aboard the \(s.name).", false) }
        if g.survival && g.money < recallPrice { return ("Bringing her by road is \(Money.format(recallPrice)).", false) }
        guard let (c, yaw) = VehicleWorks.spot(g, p) else { return ("Clear the yard beside the Works first.", false) }
        if g.survival { g.money -= recallPrice }
        s.rot = Quat(angle: yaw, axis: V3(0, 1, 0))
        s.pos = c + V3(0, 3, 0)
        s.vel = .zero; s.angVel = .zero
        s.prevRot = s.rot
        VehicleWorks.settle(s, on: c)
        recalled += 1
        g.sfx(.engineStart, 1, at: c)
        return ("The \(s.name) has been brought round to the Works.", true)
    }

    // Decodes garaged ships under fresh ids (a saved id may belong to another ship by now); returns the roots.
    static func restore(_ g: Game, _ d: Data) -> [Ship]? {
        let ships = g.world.ships
        guard var arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return nil }
        var map: [Int: Int] = [:]
        for e in arr { if let id = e["id"] as? Int { map[id] = ships.newId() } }
        for k in arr.indices {
            if let id = arr[k]["id"] as? Int { arr[k]["id"] = map[id] }
            if let p = arr[k]["parent"] as? Int { arr[k]["parent"] = map[p] }
        }
        guard let out = try? JSONSerialization.data(withJSONObject: arr) else { return nil }
        ships.decode(out)
        let ids = Set(map.values)
        return ships.list.filter { ids.contains($0.id) && $0.parent == nil }
    }
}

extension ItemRegistry {
    func registerFuelCan() {
        guard !has(VehicleDepot.canKey) else { return }
        var d = ItemDef(VehicleDepot.canKey, "Fuel Can")
        d.sprite = Sprite(mask: "jerry_can", base: 0xB0322A, extras: ["k": 0x2A2A2C])     // P365 (b)
        d.maxStack = 4
        add(d)
    }
}

extension BlockRegistry {
    func registerFuelPump() {
        guard !has(VehicleDepot.pumpKey) else { return }
        var d = BlockDef(VehicleDepot.pumpKey, "Fuel Pump")
        d.tex = ["fuel_pump_side", "fuel_pump_side", "ship_metal", "ship_metal", "fuel_pump_front", "fuel_pump_side"]
        d.hardness = 3; d.resistance = 5; d.tool = .pickaxe; d.requiresTool = true; d.sound = .stone
        add(d)
    }
}

extension TextureGen {
    // A red pump: a dial window up top, a hose coiled on the front.
    static func fuelPumpPainters(_ p: inout [String: Painter]) {
        p["fuel_pump_side"] = { x, y in
            if x == 0 || x == 15 { return hex(0x6A1812) }
            if y <= 1 { return hex(0x3A3D44) }
            return hex(0xB0322A, 0.9 + 0.1 * r(x, y, 4411))
        }
        p["fuel_pump_front"] = { x, y in
            if x == 0 || x == 15 || y <= 1 { return hex(0x6A1812) }
            if x >= 4 && x <= 11 && y >= 3 && y <= 7 { return (x == 4 || x == 11 || y == 3 || y == 7) ? hex(0x2A2A2E) : hex(0xE8E0C8) }
            let dx = Float(x) - 7.5, dy = Float(y) - 11.5
            let rr = (dx * dx + dy * dy).squareRoot()
            if rr > 2 && rr < 3.4 { return hex(0x1E1E22) }
            return hex(0xB0322A, 0.9 + 0.1 * r(x, y, 4412))
        }
    }
}

extension VehicleDepot {
    static func recipes() -> [Recipe?] {
        [Recipes.shapeless(["bucket", "cauldron", "iron_ingot", "iron_ingot"], pumpKey),
         Recipes.shapeless(["bucket", "iron_ingot", "coal", "coal"], canKey)]
    }
}
