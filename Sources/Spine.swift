import Foundation
import simd

// The game's spine (backlog Y1-Y6, docs/roadmap/backlog.md "THE GAME'S SPINE"): iron, a town, the Greywall bases, the
// Meridian fleet, hell, and at last the Capital. Goals.swift walks the player along it; this file is what makes each
// stage hand over the key to the next and points the side systems at the current one.
//   iron       a full iron set (SixIron.armourScore): the sheriff's six-iron no longer kills in one round.
//   town       every town you take (TownConquest) hands over a Greywall Dispatch: read, it names the nearest Greywall
//              base (and once a base is yours, the nearest Fortress: the chain of command leads up).
//   Greywall   a taken base below Fortress tier hands over another dispatch; a taken Fortress or Command Fortress hands
//              over the Naval Orders, and from then on the Meridian and Stormwarden warships sail (Game.fleetSails, was
//              only after the end game).
//   navy       the Naval Orders name the nearest fleet patrol; a fleet frigate sunk or seized near you gives up the
//              Ember Charge from her strongroom (Capital vaults keep theirs too).
//   hell       the charge through the Wardstone, the hell band, a Brimstone Keep, the Sealrock, the Ash Vault, the Ash
//              Chancellor. His ledger names the Capital's citadels.
//   Capital    clear a citadel, then three: the Capital is broken.
// Milestones are advancements ("spine/...", saved with the rest), so old saves need no new keys; the items handed over
// are remembered as flags in the same set ("spinetown/<town>", "spinebase/<key>", "spine/orders", "spine/ledger").
// Side systems: contracts paid, treaties signed and legendaries found pass on word of the current stage's target
// (Spine.lead), the saloon sells a dispatch, the world map carries a "Next objective" marker (MapCache.setObjective)
// and the goal banner a bearing to it.
enum Spine {
    static let stages = ["Iron", "Take a town", "Greywall Command", "The Meridian fleet", "Hell", "The Capital"]
    static var paused = false                       // (GoalTests: the walk sets advancements by hand)
    static func active(_ g: Game) -> Bool { HudExtras.enabled && !paused && g.survival }

    // Live (not saved).
    static weak var game: Game?
    static var lastTick: Double = -100
    static var seenTaken = -1
    static var targetGoal: String?
    static var targetAt: Double = -100
    static var target: Game.RadarContact?
    static var bearing: String?                     // "Greywall Outpost: 1,240 m NW, ahead left" (Goals.lines)
    static var bearingAt: Double = -100

    static func reset() { lastTick = -100; seenTaken = -1; targetGoal = nil; targetAt = -100; target = nil; bearing = nil; bearingAt = -100 }

    // MARK: Twice a second (Goals.tick, every frame before the hints check)

    static func tick(_ g: Game) {
        if g !== game { game = g; reset() }
        guard active(g), g.clock - lastTick >= 0.5 else { return }
        lastTick = g.clock
        progress(g)
        track(g)
    }

    static func flag(_ s: String) -> String { s.replacingOccurrences(of: ",", with: "_") }

    // What the world says the player has done, as spine advancements, and the keys each step hands over.
    static func progress(_ g: Game) {
        let cur = Goals.next(g)?.id
        // Stage 1 and the start of stage 2 are only looked at once they are the goal (a town walked into before the
        // first pickaxe doesn't skip the iron).
        if cur == "spine/iron_set", SixIron.armourScore(g.inventory.armor.slots) >= SixIron.ironFrom { g.achieve("spine_iron_set") }
        if cur == "spine/find_town", g.dim.dim == .overworld,
           TownLaw.inTown != nil || MapCache.shared.marks.contains(where: { $0.kind == "village" }) { g.achieve("spine_find_town") }
        if let c = cur, c.hasPrefix("spine/"), c != "spine/iron_set", !g.advancements.contains("spine/intro") {
            g.advancements.insert("spine/intro")
            g.logDocument("Who Holds the Frontier", introPages, cat: .notes, id: "spine-intro")
        }
        // Stage 2: every town taken hands over a dispatch.
        if let owned = TownLaw.state.owned {
            for (town, _) in owned {
                let f = "spinetown/" + flag(town)
                guard !g.advancements.contains(f) else { continue }
                g.advancements.insert(f)
                g.achieve("spine_take_town")
                if !g.advancements.contains("spine/greywall_top") {
                    give(g, "greywall_dispatch")
                    g.onToast?("In \(town)'s jail safe: a Greywall Dispatch. Read it to find the nearest Greywall base.")
                }
            }
        }
        // Stage 3: each Greywall base taken.
        let taken = g.greywallAlarm.taken
        if taken.count != seenTaken, g.dim.dim == .overworld, let sc = g.world.gen.structures {
            seenTaken = taken.count
            for key in taken.sorted() {
                let f = "spinebase/" + flag(key)
                guard !g.advancements.contains(f) else { continue }
                let xz = key.dropFirst("greywall:".count).split(separator: ",").compactMap { Int($0) }
                guard xz.count == 2 else { continue }
                g.advancements.insert(f)
                g.achieve("spine_greywall_base")
                let tier = sc.nearest(Greywall.kind, x: xz[0], z: xz[1], maxRegions: 1).map { Greywall.Tier.of($0) } ?? .outpost
                if tier.rawValue >= Greywall.Tier.fortress.rawValue {
                    g.achieve("spine_greywall_top")
                    if !g.advancements.contains("spine/orders") {
                        g.advancements.insert("spine/orders")
                        give(g, "naval_orders")
                        g.onToast?("In the war room: Naval Orders. The Meridian fleet puts to sea; read them to find it.")
                    }
                } else if !g.advancements.contains("spine/greywall_top") {
                    give(g, "greywall_dispatch")
                    g.onToast?("The \(tier.name)'s dispatch box: orders from a Greywall Fortress. Read them to find it.")
                }
            }
        }
        // Stage 4: a fleet frigate sunk or seized near you gives up her Ember Charge.
        if g.fleetSails, !g.advancements.contains("spine/flagship"), g.dim.dim == .overworld {
            let p = g.player.pos
            for s in g.world.ships.list where s.parent == nil && (s.wrecked || s.captured) {
                guard let r = s.role, r == "capfrigate" || r == "warfrigate", simd_length(s.pos - p) < 600 else { continue }
                g.achieve("spine_flagship")
                give(g, HellGate.chargeKey)
                g.onToast?("From the \(s.name)'s strongroom: an Ember Charge. Press it on the Wardstone at the bottom of the world.")
                break
            }
        }
        // Stage 5's end: the Chancellor's ledger names the Capital's citadels.
        if g.ashVictory, !g.advancements.contains("spine/ledger") {
            g.advancements.insert("spine/ledger")
            give(g, "chancellor_ledger")
            g.onToast?("The Chancellor's Ledger: the Capital paid for his war. Read it to find its citadels.")
        }
        // Stage 6: citadels cleared.
        var cleared = 0
        for r in g.bases.records.values where r.cleared == true { cleared += 1 }
        if cleared >= 1 { g.achieve("spine_capital_citadel") }
        if cleared >= 3 || g.advancements.contains("adventure/break_citadel") { g.achieve("spine_capital_fall") }
    }

    static func give(_ g: Game, _ key: String) {
        guard Items.has(key) else { return }
        let rest = g.inventory.add(ItemStack(Items.id(key), 1))
        if !rest.isEmpty { g.dropItem(rest) }
    }

    static let introPages = [
        "WHO HOLDS THE FRONTIER\n\nGREYWALL COMMAND: walled bases in the wilds, grey concrete, blue corner lamps. Take them a tier at a time: outpost, garrison, fortress. Their war rooms keep the fleet's orders.",
        "THE CAPITAL: white citadels and garden cities. It pays for every war and keeps the Ember Charges. It is the enemy over everything.\n\nYour road: iron, a town, the Greywall bases, the Meridian fleet, the fire below the world, and the Capital itself.",
    ]

    // MARK: The current goal's target (banner bearing and the map's "Next objective")

    static func track(_ g: Game) {
        let id = Goals.next(g)?.id
        if id != targetGoal || g.clock - targetAt >= 5 {
            let changed = id != targetGoal
            targetGoal = id; targetAt = g.clock
            let t = id.flatMap { g.dim.dim == .overworld ? known(g, $0) : nil }
            let moved = t.map { n in target.map { abs($0.x - n.x) + abs($0.z - n.z) > 64 } ?? true } ?? (target != nil)
            target = t
            if changed || moved {
                if let t { MapCache.shared.setObjective(g, x: t.x, z: t.z, name: t.name) } else { MapCache.shared.setObjective(g, x: nil, z: nil, name: nil) }
            }
        }
        if g.clock - bearingAt >= 0.5 {
            bearingAt = g.clock
            bearing = target.map { "\($0.name): \(g.radarBearing($0))" }
        }
    }

    // What the player already knows of the target for a goal (the map's marks, towns and patrols): no search.
    static func known(_ g: Game, _ id: String) -> Game.RadarContact? {
        let px = Int(g.player.pos.x), pz = Int(g.player.pos.z)
        func nearestMark(_ ok: (MapCache.Mark) -> Bool) -> MapCache.Mark? {
            var best: MapCache.Mark?
            var bd = Int.max
            for m in MapCache.shared.marks where ok(m) {
                let d = (m.x - px) * (m.x - px) + (m.z - pz) * (m.z - pz)
                if d < bd { bd = d; best = m }
            }
            return best
        }
        let taken = g.greywallAlarm.taken
        switch id {
        case "spine/find_town", "spine/take_town":
            guard let sc = g.world.gen.structures, let s = sc.nearest("village", x: px, z: pz, maxRegions: 2) else { return nil }
            let name = Townsfolk.townName(s.anchor.x, s.anchor.z, seed: g.world.seed)
            if id == "spine/take_town" && TownConquest.owns(name) { return nil }
            return Game.RadarContact(name: name, kind: "village", x: s.anchor.x, z: s.anchor.z)
        case "spine/greywall_base", "spine/greywall_top":
            let top = id == "spine/greywall_top"
            return nearestMark { m in
                m.kind == Greywall.kind && !taken.contains("greywall:\(m.x),\(m.z)") && (!top || (m.name ?? "").contains("Fortress"))
            }.map { Game.RadarContact(name: $0.name ?? "Greywall base", kind: Greywall.kind, x: $0.x, z: $0.z) }
        case "spine/flagship":
            return g.fleetSails ? g.nearestWarship() : nil
        case "spine/capital_citadel", "spine/capital_fall":
            return nearestMark { m in
                m.kind == "military_base" && !g.bases.records.values.contains { $0.cleared == true && abs($0.cx - m.x) < 80 && abs($0.cz - m.z) < 80 }
            }.map { Game.RadarContact(name: "Capital Citadel", kind: "military_base", x: $0.x, z: $0.z) }
        default:
            return nil
        }
    }

    // MARK: Finding targets the player doesn't know yet (items read, word passed on)

    // The nearest Greywall base of at least `minTier` not yet taken, searched ring by ring out to `rings` regions.
    static func findGreywall(_ g: Game, minTier: Greywall.Tier, rings: Int = 9) -> Game.RadarContact? {
        guard g.dim.dim == .overworld, let sc = g.world.gen.structures, let type = sc.types.first(where: { $0.name == Greywall.kind }) else { return nil }
        let span = Greywall.spacing * CS
        let px = Int(g.player.pos.x), pz = Int(g.player.pos.z)
        let rx0 = floorDiv(px, span), rz0 = floorDiv(pz, span)
        let taken = g.greywallAlarm.taken
        var best: Game.RadarContact?
        var bd = Int.max
        for ring in 0...rings {
            if best != nil, ring >= 2 {
                let edge = (ring - 1) * span
                if bd < edge * edge { break }               // nothing further out can be nearer
            }
            for dz in -ring...ring { for dx in -ring...ring where max(abs(dx), abs(dz)) == ring {
                guard let s = sc.start(type, regionX: rx0 + dx, regionZ: rz0 + dz) else { continue }
                let t = Greywall.Tier.of(s)
                guard t.rawValue >= minTier.rawValue else { continue }
                let (x, z) = Greywall.centre(s)
                guard !taken.contains("greywall:\(x),\(z)") else { continue }
                let d = (x - px) * (x - px) + (z - pz) * (z - pz)
                if d < bd { bd = d; best = Game.RadarContact(name: t.name, kind: Greywall.kind, x: x, z: z) }
            } }
        }
        return best
    }

    // The dispatch's target: the nearest base while none is yours, then the nearest Fortress (or bigger).
    static func dispatchTarget(_ g: Game) -> Game.RadarContact? {
        if g.greywallAlarm.taken.isEmpty { return findGreywall(g, minTier: .outpost, rings: 6) }
        return findGreywall(g, minTier: .fortress) ?? findGreywall(g, minTier: .outpost, rings: 6)
    }

    static func capitalTarget(_ g: Game) -> Game.RadarContact? {
        guard g.dim.dim == .overworld, let sc = g.world.gen.structures else { return nil }
        let px = Int(g.player.pos.x), pz = Int(g.player.pos.z)
        guard let s = sc.nearest("military_base", x: px, z: pz, maxRegions: 4) else { return nil }
        return Game.RadarContact(name: "Capital Citadel", kind: "military_base", x: (s.min.x + s.max.x) / 2, z: (s.min.z + s.max.z) / 2)
    }

    // Word of the current stage's target, from someone you did a good turn (a contract's patron, an ally's envoy, a
    // legend's teller): it goes on the map as the next objective; the returned text is added to their own message
    // ("" when there is nothing to tell, or outside play).
    static func lead(_ g: Game, from: String) -> String {
        guard active(g), g.dim.dim == .overworld, let n = Goals.next(g) else { return "" }
        var t = known(g, n.id)
        if t == nil {
            switch n.id {
            case "spine/greywall_base": t = findGreywall(g, minTier: .outpost, rings: 5)
            case "spine/greywall_top": t = findGreywall(g, minTier: .fortress, rings: 7)
            case "spine/capital_citadel", "spine/capital_fall": t = capitalTarget(g)
            default: break
            }
            if let f = t { MapCache.shared.discover(g, kind: f.kind, x: f.x, z: f.z, name: f.kind == Greywall.kind ? f.name : nil) }
        }
        guard let tt = t else { return "" }
        target = tt; targetGoal = n.id; targetAt = g.clock; bearingAt = -100
        MapCache.shared.setObjective(g, x: tt.x, z: tt.z, name: tt.name)
        return " \(from) passes on word: \(tt.name), \(g.radarBearing(tt)). On your map."
    }

    // A legend found: which legend waits further along the spine (Legendaries.award adds it to its message).
    static func legendHint(_ g: Game) -> String {
        guard active(g), let n = Goals.next(g), let i = Goals.stage(n.id) else { return "" }
        let words = ["", " Tellers say the Greywall Aegis waits in a Command Fortress's strongbox.",
                     " Tellers say the Greywall Aegis waits in a Command Fortress's strongbox.",
                     " Tellers say the Ash Marshal's own six-iron waits below the world.",
                     " Tellers say the Ash Marshal's own six-iron waits below the world.",
                     " Tellers say the Capital's citadels keep what they took from the Chancellor's guard."]
        return i < words.count ? words[i] + lead(g, from: "The teller") : ""
    }
}

// MARK: Items

extension ItemRegistry {
    func registerSpineItems() {
        let defs: [(String, String, UInt32, [Character: UInt32])] = [
            ("greywall_dispatch", "Greywall Dispatch", 0xC9CFD8, ["c": 0x3A6AD0, "d": 0x2A2E36]),       // Greywall blue seal
            ("naval_orders", "Naval Orders", 0xE6EEF4, ["c": 0x1E3E8A, "d": 0x24303A]),                 // fleet navy seal
            ("chancellor_ledger", "Chancellor's Ledger", 0xB8A890, ["c": 0xC0281E, "d": 0x1A1A1A]),      // scorched, red seal
        ]
        for (k, name, base, extras) in defs where !has(k) {
            var d = ItemDef(k, name)
            d.sprite = Sprite(mask: "orders", base: base, extras: extras)
            d.maxStack = 16
            add(d)
        }
    }
}

// MARK: Reading them (FactionGear.factionGearUse)

extension Game {
    // The warships sail once a Greywall Fortress falls (Y3; before, only after the end game).
    var fleetSails: Bool { postGame || advancements.contains("spine/greywall_top") || advancements.contains("spine/fleet") }

    func spineItemUse() -> Bool {
        let held = inventory.main[inventory.selected]
        guard !held.isEmpty else { return false }
        let k = Items.key(held.item)
        guard k == "greywall_dispatch" || k == "naval_orders" || k == "chancellor_ledger" else { return false }
        guard dim.dim == .overworld else { onToast?("Its maps are of the surface: read it up there"); return true }
        switch k {
        case "greywall_dispatch":
            guard let t = Spine.dispatchTarget(self) else { onToast?("The dispatch names no Greywall base within reach"); return true }
            MapCache.shared.discover(self, kind: Greywall.kind, x: t.x, z: t.z, name: t.name)
            onToast?("Greywall Dispatch: the \(t.name), \(radarBearing(t)). Marked on your map.")
            spineDocument("Greywall Dispatch", [
                "GREYWALL COMMAND - DISPATCH\n\nTo the \(t.name), grid \(t.x), \(t.z).\n\nHold the walls. Report any rider from the towns. Keep the alarm panels manned.",
                "Who takes this base takes its map table: the radar net shows our other bases.\n\nThe Fortresses keep the fleet's orders in their war rooms.\n\n- Greywall Command"])
        case "naval_orders":
            achieve("spine_fleet")
            if let w = nearestWarship() {
                MapCache.shared.discover(self, kind: w.kind, x: w.x, z: w.z)
                onToast?("Naval Orders: the \(w.name) keeps station \(radarBearing(w)). Marked on your map.")
                spineDocument("Naval Orders", [
                    "MERIDIAN FLEET - SAILING ORDERS\n\nThe \(w.name) to keep station at grid \(w.x), \(w.z), and to hold the coast against the towns.",
                    "Her strongroom carries an Ember Charge for the Capital. It is not to be lost.\n\nBoarders are to be met at the rails.\n\n- Flag Officer, Meridian Fleet"])
            } else {
                onToast?("Naval Orders: the fleet is at sea, beyond this coast. A radar set finds its patrols.")
                spineDocument("Naval Orders", [
                    "MERIDIAN FLEET - SAILING ORDERS\n\nAll ships to put to sea and keep the far patrols.",
                    "Each flagship's strongroom carries an Ember Charge for the Capital. It is not to be lost.\n\n- Flag Officer, Meridian Fleet"])
            }
        default:
            guard let t = Spine.capitalTarget(self) else { onToast?("The ledger names no citadel within reach"); return true }
            MapCache.shared.discover(self, kind: t.kind, x: t.x, z: t.z)
            if let sc = world.gen.structures, let c = sc.nearest("capital_city", x: Int(player.pos.x), z: Int(player.pos.z), maxRegions: 4) {
                MapCache.shared.discover(self, kind: "capital_city", x: (c.min.x + c.max.x) / 2, z: (c.min.z + c.max.z) / 2)
            }
            onToast?("The ledger names a Capital citadel, \(radarBearing(t)). Marked on your map.")
            spineDocument("Chancellor's Ledger", [
                "LEDGER OF THE ASH CHANCELLOR\n\nShells, fuel and Ember Charges, received from the Capital's citadel at grid \(t.x), \(t.z).",
                "Paid in full. The Capital asks only that the war below never ends.\n\nIt has. The citadels are next."])
        }
        return true
    }

    // One of the held item read: used up, kept as a book to reread (and in the journal), opened now.
    private func spineDocument(_ title: String, _ pages: [String]) {
        inventory.main[inventory.selected].count -= 1
        if inventory.main[inventory.selected].count <= 0 { inventory.main[inventory.selected] = .empty }
        sfx(.pageTurn, 0.8, at: player.pos)
        guard Items.has("written_book") else { return }
        var doc = ItemStack(Items.id("written_book"), 1)
        doc.pages = pages
        doc.label = title
        if inventory.main[inventory.selected].isEmpty { inventory.main[inventory.selected] = doc }
        else { let rest = inventory.add(doc); if !rest.isEmpty { dropItem(rest) } }
        if menu == nil { openMenu(BookMenu(game: self, stack: doc, source: .hand(inventory.selected))) }
        else { logDocument(title, pages, cat: .orders) }
    }
}
