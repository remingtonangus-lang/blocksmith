import Foundation
import simd

// Faction gear (task 23). Capital citadels keep components no one else makes: Firing Mechanisms, Targeting Optics and
// Radar Modules (loot only: armories, command rooms, vaults; the Meridian frigate's hold). Guns are crafted only
// with them (Guns.recipes), and so is the Radar Set:
// - Radar Set: held in either hand it lists the nearest Capital citadel and city, and after the end game (the Hollow's
//   dragon or the Ash Marshal beaten) the nearest faction warship still afloat - Meridian frigates, Stormwarden
//   frigates, Ironback crawlers - with distance and bearing. Use: marks them all on the map.
// - Intercepted Orders (citadel command rooms and vaults): use to read them; after the end game they give a faction
//   warship's patrol, before it the nearest Capital city or citadel not yet on your map; marked on the map.
// Faction warships sail once a Greywall Fortress falls (Y3, Spine.swift: Game.fleetSails; until then only after the end
// game), and rarely (ShipVessels: 3 % of 2048-block regions a Meridian
// frigate, 1.5 % a Stormwarden frigate, 1.5 % an Ironback crawler, 0.7 % the two at war).
extension Game {
    var postGame: Bool { dragonKilled || ashVictory }

    struct RadarContact { let name: String; let kind: String; let x: Int; let z: Int }

    // Nearest citadel, city and (post-game) warship.
    func radarContacts() -> [RadarContact] {
        var out: [RadarContact] = []
        guard dim.dim == .overworld, let sc = world.gen.structures else { return out }
        let px = Int(player.pos.x), pz = Int(player.pos.z)
        for (k, n) in [("military_base", "Capital Citadel (enemy)"), ("capital_city", "Capital City"), (Greywall.kind, "Greywall Base")] {
            if let s = sc.nearest(k, x: px, z: pz, maxRegions: 4) {
                let c = sc.siteCentre(s)                     // (P456: the site's own walls, not its trailing pieces)
                out.append(RadarContact(name: n, kind: k, x: c.x, z: c.z))
            }
        }
        if fleetSails, let w = nearestWarship() { out.append(w) }
        return out
    }

    // The nearest faction warship: a live one, else an encounter region within ~6,000 blocks whose ship hasn't sailed
    // yet (regions whose ship came and went are skipped).
    func nearestWarship() -> RadarContact? {
        let names = ["capfrigate": "Meridian Frigate", "warfrigate": "Stormwarden Frigate", "crawler": "Ironback Crawler"]
        let ships = world.ships
        var best: (RadarContact, Float)?
        let p = V2(player.pos.x, player.pos.z)
        for s in ships.list where s.parent == nil && !s.wrecked && !s.captured {
            guard let r = s.role, let n = names[r] else { continue }
            let d = simd_length(V2(s.pos.x, s.pos.z) - p)
            if best == nil || d < best!.1 { best = (RadarContact(name: n, kind: "vessel_" + r, x: Int(s.pos.x), z: Int(s.pos.z)), d) }
        }
        let R = Vessels.region
        let rx = floorDiv(Int(p.x), R), rz = floorDiv(Int(p.y), R)
        for dz in -3...3 { for dx in -3...3 {
            let key = "\(rx + dx),\(rz + dz)"
            if ships.spawnedRegions.contains(key) { continue }
            guard let e = Vessels.encounter(seed: world.seed, rx: rx + dx, rz: rz + dz, gen: world.gen) else { continue }
            let role = e.0 == "frigate" ? "capfrigate" : (e.0 == "battle" ? "warfrigate" : e.0)
            guard let n = names[role] else { continue }
            let d = simd_length(V2(Float(e.1.x), Float(e.1.z)) - p)
            if best == nil || d < best!.1 { best = (RadarContact(name: n, kind: "vessel_" + role, x: e.1.x, z: e.1.z), d) }
        } }
        return best?.0
    }

    // "1,240 m NW, ahead left".
    func radarBearing(_ c: RadarContact) -> String {
        let dx = Float(c.x) - player.pos.x, dz = Float(c.z) - player.pos.z
        let d = Int((dx * dx + dz * dz).squareRoot())
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        var deg = Double(atan2f(dx, -dz) * 180 / .pi)
        if deg < 0 { deg += 360 }
        let abs8 = dirs[Int((deg + 22.5) / 45) % 8]
        let rel = atan2f(dx, -dz) + player.yaw                 // 0 = ahead (yaw 0 looks toward -z)
        var r = Double(rel * 180 / .pi).truncatingRemainder(dividingBy: 360)
        if r < 0 { r += 360 }
        let words = ["ahead", "ahead right", "right", "behind right", "behind", "behind left", "left", "ahead left"]
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return "\(f.string(from: NSNumber(value: d)) ?? "\(d)") m \(abs8), \(words[Int((r + 22.5) / 45) % 8])"
    }

    var holdingRadar: Bool {
        guard Items.has("radar_set") else { return false }
        let r = Items.id("radar_set")
        let m = inventory.main[inventory.selected], o = inventory.offhand[0]
        return (!m.isEmpty && m.item == r) || (!o.isEmpty && o.item == r)
    }

    // Right-click with the radar or the orders.
    func factionGearUse() -> Bool {
        let held = inventory.main[inventory.selected]
        guard !held.isEmpty else { return false }
        if pulseChargeUse() { return true }
        if skySkiffUse() { return true }               // A4 (SkySkiff.swift)
        if grappleUse() { return true }                // C7 (SkyIsle.swift)
        if submarineUse() { return true }              // C8 (Submarines.swift)
        if depthChargeUse() { return true }            // P278 (DepthCharges.swift)
        if sundryUse() { return true }                 // P133 (BaseSundries.swift)
        if aeroSparesUse() { return true }             // P346 (AshWrecks.swift)
        if trackSparesUse() { return true }            // P435 (AshWrecks.swift)
        if blueprintUse() { return true }              // P138 (Blueprints.swift)
        if vehicleBlueprintUse() { return true }       // D43 (VehiclePresets.swift)
        if VehicleDepot.useCan(self) { return true }   // D44 (VehicleDepot.swift)
        if Tracking.useBait(self) { return true }      // D46 (Tracking.swift)
        if spineItemUse() { return true }              // Y2 (Spine.swift): dispatch, naval orders, ledger
        let k = Items.key(held.item)
        if k == "radar_set" {
            let cs = radarContacts()
            guard !cs.isEmpty else { onToast?("Radar: no contacts here"); return true }
            for c in cs { MapCache.shared.discover(self, kind: c.kind, x: c.x, z: c.z) }
            onToast?("Radar contacts marked on your map")
            sfx(.click, 0.6, at: player.pos)
            return true
        }
        if k == "intercepted_orders" {
            guard let ot = ordersTarget() else { onToast?("The orders are coded beyond reading"); return true }
            let (t, text) = ot
            inventory.main[inventory.selected].count -= 1
            if inventory.main[inventory.selected].count <= 0 { inventory.main[inventory.selected] = .empty }
            MapCache.shared.discover(self, kind: t.kind, x: t.x, z: t.z)
            onToast?("\(text): \(radarBearing(t)). Marked on your map.")
            sfx(.pageTurn, 0.8, at: player.pos)
            // P68 (playtest 09:18, "pull them out and read it"): the orders open as a document to read. P168 (Oct 13:
            // "I'd like to still be able to read those, not just one and done"): the decoded orders stay with you as a
            // book (in the hand they came from, or the pack) to reread any time; the Journal keeps them too.
            var doc = ItemStack(Items.id("written_book"), 1)
            doc.pages = ordersPages(t)
            doc.label = "Intercepted Orders"
            if inventory.main[inventory.selected].isEmpty { inventory.main[inventory.selected] = doc }
            else { let rest = inventory.add(doc); if !rest.isEmpty { dropItem(rest) } }
            if menu == nil { openMenu(BookMenu(game: self, stack: doc, source: .hand(inventory.selected))) }
            else { logDocument("Intercepted Orders", doc.pages ?? [], cat: .orders) }   // R24: filed even unread
            return true
        }
        return false
    }

    // P456 (Oct 25 14:03, "the orders were not accurate. There's nothing here... There should also be different types
    // of orders, not just ones that lead to the Capital bases"). The place a set of intercepted orders points at, and the
    // toast's opening: a warship's patrol once the fleet sails, else a Capital site not on the map yet. The kinds:
    // report to a citadel or a city; a strike on a Greywall base; a supply run to a Boreal Station; a survey of an
    // Ancient Spire; a bounty on a Marauder Watchtower. Which kind a set of orders carries comes from where it is read
    // (the same spot reads the same), the first ones always pointing at a citadel while none is on the map. A place is
    // offered only when its pieces lay blocks where its map mark goes (StructureCache.builds), so the orders never send
    // him to an empty forest.
    static let orderKinds: [(kind: String, name: String, verb: String)] = [
        ("military_base", "Capital Citadel", "report"), ("capital_city", "Capital City", "report"),
        (Greywall.kind, "Greywall Base", "strike"), (BorealStation.kind, "Boreal Station", "supply"),
        ("great_ruin", "Ancient Spire", "survey"), ("pillager_outpost", "Marauder Watchtower", "bounty")]
    static var ordersSkipped = 0                     // (checks: places passed over as not there)
    func ordersTarget() -> (RadarContact, String)? {
        if fleetSails, let w = nearestWarship() { return (w, "The orders give a \(w.name)'s patrol") }
        guard let sc = world.gen.structures else { return nil }
        let px = Int(player.pos.x), pz = Int(player.pos.z)
        var cands: [RadarContact] = []
        var starts: [StructureStart] = []
        for (kd, n, _) in Game.orderKinds {
            guard let t = sc.types.first(where: { $0.name == kd }) else { continue }
            let rx = floorDiv(floorDiv(px, CS), t.spacing), rz = floorDiv(floorDiv(pz, CS), t.spacing)
            let reach = max(1, min(3, 120 / max(1, t.spacing)))        // (about 2,000 blocks round him whatever the spacing)
            for dz in -reach...reach { for dx in -reach...reach {
                guard let s = sc.start(t, regionX: rx + dx, regionZ: rz + dz) else { continue }
                let c = sc.siteCentre(s)
                cands.append(RadarContact(name: n, kind: kd, x: c.x, z: c.z))
                starts.append(s)
            } }
        }
        func dist(_ c: RadarContact) -> Int { (c.x - px) * (c.x - px) + (c.z - pz) * (c.z - pz) }
        // The kind of orders these are (from where they are read: the same spot reads the same).
        let roll = hashf(px >> 4, pz >> 4, 4560, 0x0D)
        var target: RadarContact?
        for _ in 0..<12 where !cands.isEmpty {
            let near = cands.filter { dist($0) <= 2200 * 2200 }
            var fresh = near.filter { c in !MapCache.shared.marked(kind: c.kind, x: c.x, z: c.z) && dist(c) > 120 * 120 }
            // The first orders read point to a citadel while none is on the map (done audit 25b6, G6: the first base
            // meant wandering ~1,200 blocks; orders turn up in outlaw and abandoned camps, WildCamps.loot).
            if !MapCache.shared.marks.contains(where: { $0.kind == "military_base" }), fresh.contains(where: { $0.kind == "military_base" }) {
                fresh = fresh.filter { $0.kind == "military_base" }
            } else if !fresh.isEmpty {
                let kinds = Array(Set(fresh.map { $0.kind })).sorted()
                let pick = kinds[min(kinds.count - 1, Int(roll * Float(kinds.count)))]
                fresh = fresh.filter { $0.kind == pick }
            }
            guard let t = (fresh.isEmpty ? (near.isEmpty ? cands : near) : fresh).min(by: { dist($0) < dist($1) }),
                  let i = cands.firstIndex(where: { $0.kind == t.kind && $0.x == t.x && $0.z == t.z }) else { break }
            // Only a place that is really there: its pieces lay blocks where the map mark goes, and ground already made
            // there (loaded, or saved by an earlier build that placed it elsewhere) has them.
            if sc.builds(starts[i], at: IVec3(t.x, 0, t.z)) >= 24 && siteStands(t.x, t.z) { target = t; break }
            Game.ordersSkipped += 1
            cands.remove(at: i); starts.remove(at: i)
        }
        guard let t = target else { return nil }
        let verb = Game.orderKinds.first { $0.kind == t.kind }?.verb ?? "report"
        switch verb {
        case "strike": return (t, "The orders set a Capital strike on a \(t.name)")
        case "supply": return (t, "A Capital supply run is bound for a \(t.name)")
        case "survey": return (t, "The orders send a Capital survey party to an \(t.name)")
        case "bounty": return (t, "The Capital has a bounty on a \(t.name)")
        default: return (t, "Capital patrol routes lead to a \(t.name)")
        }
    }

    // Whether ground already made at (x, z) has something built on it (a structure's blocks, not ground, trees, plants
    // or water). Ground not made yet: true (the generator lays it down when he gets there).
    func siteStands(_ x: Int, _ z: Int) -> Bool {
        func built(_ b: BlockID) -> Bool {
            !(b == AIR || SmoothTerrain.natural[Int(b)] || CapitalBase.isLog(b) || CapitalBase.isLeaf(b) || Blocks.replaceable[Int(b)] || Blocks.isLiquid(b))
        }
        var n = 0
        if world.chunkAt(x, z) != nil {
            let bx = floorDiv(x, CS) * CS, bz = floorDiv(z, CS) * CS
            for lz in stride(from: 0, to: CS, by: 2) { for lx in stride(from: 0, to: CS, by: 2) { for y in 1..<(CH - 1) where built(world.builtBlock(bx + lx, y, bz + lz)) { n += 1 } } }
            return n >= 6
        }
        guard let save = world.save, let b = save.loadChunk(ChunkKey(x: floorDiv(x, CS), z: floorDiv(z, CS))) else { return true }
        for lz in stride(from: 0, to: CS, by: 2) { for lx in stride(from: 0, to: CS, by: 2) { for y in 1..<(CH - 1) where built(b[lx + lz * CS + y * CSQ]) { n += 1 } } }
        return n >= 6
    }

    // The text of a set of intercepted orders pointing at `t`: a dispatch header, the orders themselves (where, which
    // way, how far, what to watch for) and a signature, a page or two of the book screen. The words come from the
    // target and a hash of its position, so the same orders always read the same.
    func ordersPages(_ t: RadarContact) -> [String] {
        let h = { (k: Int) -> Int in Int(hashf(t.x, t.z, 6800 + k, 0x0D) * 997) }
        let officers = ["Col. Harrow Vane", "Maj. Edda Corran", "Capt. Tobin Lisle", "Col. Mara Quill", "Maj. Aldous Pike", "Capt. Wren Halloway"]
        let units = ["3rd Rifle Company", "Ironback Battery", "1st Mounted Patrol", "Road Watch, East", "Signal Section 9", "Column Grey"]
        let watch = ["outlaws on the old road", "Greywall scouts in the hills", "wagons travelling after dark", "riders without papers",
                     "smoke from unlicensed camps", "lights on the ridge after sundown"]
        let dx = Float(t.x) - player.pos.x, dz = Float(t.z) - player.pos.z
        var deg = Double(atan2f(dx, -dz) * 180 / .pi)
        if deg < 0 { deg += 360 }
        let compass = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][Int((deg + 22.5) / 45) % 8]
        let km = Int((dx * dx + dz * dz).squareRoot() / 100)
        let bearing = "\(km < 10 ? "\(max(1, km) * 100) m" : "\(km / 10) km") \(compass) of here, at grid \(t.x), \(t.z)"
        let warship = t.kind.hasPrefix("vessel_")
        var p1 = warship ? "FLEET SIGNAL - MOST SECRET\nIntercept no. \(1000 + h(1))\n" : "CAPITAL STAFF - DISPATCH\nIntercept no. \(1000 + h(1))\n"
        p1 += "To: \(units[h(2) % units.count])\n\n"
        switch warship ? "fleet" : (Game.orderKinds.first { $0.kind == t.kind }?.verb ?? "report") {
        case "fleet": p1 += "The \(t.name) keeps station \(bearing). Supply boats to come alongside by night only, no lamps."
        case "strike": p1 += "The \(t.name), \(bearing), is to be taken. Form up out of sight of its towers and go in at first light, guns first."
        case "supply": p1 += "Escort the supply sledges to the \(t.name), \(bearing). Fuel, rations and spare valves; sign for every crate."
        case "survey": p1 += "Survey party to the \(t.name), \(bearing). Map the halls, take nothing apart, bring back anything with writing on it."
        case "bounty": p1 += "The \(t.name), \(bearing), harbours raiders. Twenty crowns a head; clear it and burn the stores."
        default: p1 += "Report to the \(t.name), \(bearing). Be inside the walls by nightfall."
        }
        let p2b = "Watch for \(watch[h(3) % watch.count]). Stop and search; send word by runner, not by radio.\n\n"
        let p2 = p2b + "Burn these orders once read.\n\n- \(officers[h(4) % officers.count])"
        return [p1, p2]                  // (PlaytestOct12Tests.readOrders: each fits the book page)
    }

    // HUD while a radar is held: a small panel above the hotbar, refreshed twice a second.
    // A citadel's command console (the blocks with the little radar screen, Oct 11 playtest P36: "they should have a use"):
    // used, it puts the citadel's picture on the radar readout for 30 s: the nearest citadel and city, every Capital
    // patrol out in the field and how many soldiers still hold the walls. True when the block was a console.
    func consoleUse(_ p: IVec3) -> Bool {
        let k = Blocks.key(Blocks.groupBase[Int(world.materialAt(p.x, p.y, p.z))])
        guard k == "command_console" || k == "greywall_terminal" else { return false }   // (P68 terminals too)
        consoleRadarUntil = clock + 30
        BaseConsoles.camerasAt = nil                                 // (P422: the locator's picture, not the cameras')
        Game.radarCache.time = -1
        sfx(.click, 0.8, at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5))
        onToast?("Console: patrols and Capital sites on your radar for 30 s")
        return true
    }

    // Console contacts: patrols in the field (leader's position) and the garrison still inside the nearest citadel's walls.
    func consoleContacts() -> [RadarContact] {
        var out: [RadarContact] = []
        for (_, team) in bases.patrols {
            guard let lead = team.first(where: { $0.health > 0 }) else { continue }
            let n = team.filter { $0.health > 0 }.count
            out.append(RadarContact(name: "Patrol of \(n)", kind: "patrol", x: Int(lead.pos.x), z: Int(lead.pos.z)))
        }
        if let r = bases.records.values.min(by: { simd_length($0.centre - player.pos) < simd_length($1.centre - player.pos) }) {
            let n = mobs.mobs.filter { $0.kind.steelhold && $0.kind != .deckGun && $0.health > 0 && r.inside($0.pos) }.count
            out.append(RadarContact(name: r.cleared == true ? "Citadel (cleared)" : "Citadel garrison: \(n)", kind: "garrison", x: r.cx, z: r.cz))
        }
        return out
    }

    func radarLines(_ L: HudLayout) -> [HudLine] {
        let console = clock < consoleRadarUntil
        let ship = frigateRadar
        guard holdingRadar || console || ship, menu == nil else { return [] }
        if clock - Game.radarCache.time > 0.5 || Game.radarCache.world !== world {
            Game.radarCache = (clock, world, ship ? frigateContacts() : (console && BaseConsoles.camerasAt != nil ? consoleCameraContacts() : radarContacts() + (console ? consoleContacts() : [])))
            if ship { markRadarSites(Game.radarCache.list) }
        }
        let s = L.s
        let rows = Game.radarCache.list.map { "\($0.name)  \(radarBearing($0))" }
        let head = ship ? "Frigate radar (1,500 m)" : console ? (BaseConsoles.camerasAt != nil ? "Security cameras" : "Citadel console") : (fleetSails ? "Radar" : "Radar (the fleet sails once a Greywall Fortress falls)")
        let w = Float(([head] + rows).map { Font.width($0) }.max() ?? 40) * s + 8 * s
        let x = floor(L.W / 2 - w / 2), y = L.hotbarY0 - Float(rows.count + 1) * 10 * s - 30 * s
        var out = [HudLine(text: "", x: x, y: y - 3 * s, scale: s, bg: V4(0.02, 0.08, 0.04, 0.6), box: V2(w, Float(rows.count + 1) * 10 * s + 5 * s))]
        out.append(HudLine(text: head, x: x + 4 * s, y: y, scale: s, color: V4(0.45, 1, 0.55, 1)))
        // Y4: the Capital (the enemy over everything) in red, Greywall Command (the proving ground) in its blue-grey.
        let list = Game.radarCache.list
        for (i, r) in rows.enumerated() {
            let k = i < list.count ? list[i].kind : ""
            let c = k == "military_base" || k == "capital_city" ? V4(1, 0.62, 0.55, 1) : k == Greywall.kind ? V4(0.7, 0.8, 0.95, 1) : V4(0.8, 1, 0.82, 1)
            out.append(HudLine(text: r, x: x + 4 * s, y: y + Float(i + 1) * 10 * s, scale: s, color: c))
        }
        return out
    }
    static var radarCache: (time: Double, world: World?, list: [RadarContact]) = (-1, nil, [])
}
