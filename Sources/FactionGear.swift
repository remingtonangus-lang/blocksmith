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
// Faction warships sail only after the end game, and rarely (ShipVessels: 3 % of 2048-block regions a Meridian
// frigate, 1.5 % a Stormwarden frigate, 1.5 % an Ironback crawler, 0.7 % the two at war).
extension Game {
    var postGame: Bool { dragonKilled || ashVictory }

    struct RadarContact { let name: String; let kind: String; let x: Int; let z: Int }

    // Nearest citadel, city and (post-game) warship.
    func radarContacts() -> [RadarContact] {
        var out: [RadarContact] = []
        guard dim.dim == .overworld, let sc = world.gen.structures else { return out }
        let px = Int(player.pos.x), pz = Int(player.pos.z)
        for (k, n) in [("military_base", "Capital Citadel"), ("capital_city", "Capital City")] {
            if let s = sc.nearest(k, x: px, z: pz, maxRegions: 4) {
                out.append(RadarContact(name: n, kind: k, x: (s.min.x + s.max.x) / 2, z: (s.min.z + s.max.z) / 2))
            }
        }
        if postGame, let w = nearestWarship() { out.append(w) }
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
            var target: RadarContact?
            var text = ""
            if postGame, let w = nearestWarship() {
                target = w; text = "The orders give a \(w.name)'s patrol"
            } else if let sc = world.gen.structures {
                // The nearest Capital city or citadel not on the map yet (or the nearest one if all are).
                let px = Int(player.pos.x), pz = Int(player.pos.z)
                var cands: [RadarContact] = []
                for (kd, n) in [("capital_city", "Capital City"), ("military_base", "Capital Citadel")] {
                    guard let t = sc.types.first(where: { $0.name == kd }) else { continue }
                    let rx = floorDiv(floorDiv(px, CS), t.spacing), rz = floorDiv(floorDiv(pz, CS), t.spacing)
                    for dz in -3...3 { for dx in -3...3 {
                        if let s = sc.start(t, regionX: rx + dx, regionZ: rz + dz) {
                            cands.append(RadarContact(name: n, kind: kd, x: (s.min.x + s.max.x) / 2, z: (s.min.z + s.max.z) / 2))
                        }
                    } }
                }
                func dist(_ c: RadarContact) -> Int { (c.x - px) * (c.x - px) + (c.z - pz) * (c.z - pz) }
                let fresh = cands.filter { c in !MapCache.shared.marked(kind: c.kind, x: c.x, z: c.z) && dist(c) > 120 * 120 }
                target = (fresh.isEmpty ? cands : fresh).min { dist($0) < dist($1) }
                if let t = target { text = "Capital patrol routes lead to a \(t.name)" }
            }
            guard let t = target else { onToast?("The orders are coded beyond reading"); return true }
            inventory.main[inventory.selected].count -= 1
            if inventory.main[inventory.selected].count <= 0 { inventory.main[inventory.selected] = .empty }
            MapCache.shared.discover(self, kind: t.kind, x: t.x, z: t.z)
            onToast?("\(text): \(radarBearing(t)). Marked on your map.")
            sfx(.pageTurn, 0.8, at: player.pos)
            return true
        }
        return false
    }

    // HUD while a radar is held: a small panel above the hotbar, refreshed twice a second.
    func radarLines(_ L: HudLayout) -> [HudLine] {
        guard holdingRadar, menu == nil else { return [] }
        if clock - Game.radarCache.time > 0.5 || Game.radarCache.world !== world {
            Game.radarCache = (clock, world, radarContacts())
        }
        let s = L.s
        let rows = Game.radarCache.list.map { "\($0.name)  \(radarBearing($0))" }
        let head = postGame ? "Radar" : "Radar (fleets sail after the end game)"
        let w = Float(([head] + rows).map { Font.width($0) }.max() ?? 40) * s + 8 * s
        let x = floor(L.W / 2 - w / 2), y = L.hotbarY0 - Float(rows.count + 1) * 10 * s - 30 * s
        var out = [HudLine(text: "", x: x, y: y - 3 * s, scale: s, bg: V4(0.02, 0.08, 0.04, 0.6), box: V2(w, Float(rows.count + 1) * 10 * s + 5 * s))]
        out.append(HudLine(text: head, x: x + 4 * s, y: y, scale: s, color: V4(0.45, 1, 0.55, 1)))
        for (i, r) in rows.enumerated() {
            out.append(HudLine(text: r, x: x + 4 * s, y: y + Float(i + 1) * 10 * s, scale: s, color: V4(0.8, 1, 0.82, 1)))
        }
        return out
    }
    static var radarCache: (time: Double, world: World?, list: [RadarContact]) = (-1, nil, [])
}
