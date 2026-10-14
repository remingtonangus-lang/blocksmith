import Foundation
import simd

// P242 (Oct 13 21:54, "specialty bases, like GoldenEye missions: an ammo depot that supplies ammo for good once
// found, and other one-of-a-kind bases"). About half of the military bases (Greywall bases and Capital citadels) have a
// speciality, fixed by the base's key. Walking up to one tells you what it is; once it is yours (a Greywall base
// taken, a citadel cleared) it serves you whenever you come back:
//   ammo depot      once a day: every gun you carry gets three magazines of its ammunition
//   field hospital  once a day: health and food topped up, every effect on you washed out
//   armoury         once: an elite-grade gun from the racks, with ammunition
//   radar station   once: the bearing and distance of every other base within 3 km, as map waypoints
// Used days and one-off gifts are saved with the world extras ("baseSpecials").
enum BaseSpecialty: Int, CaseIterable {
    case none, ammoDepot, fieldHospital, armoury, radarStation

    var name: String { ["", "Ammo Depot", "Field Hospital", "Armoury", "Radar Station"][rawValue] }
    var promise: String {
        switch self {
        case .none: return ""
        case .ammoDepot: return "take it and its magazine restocks your guns every day"
        case .fieldHospital: return "take it and its doctors patch you up every day"
        case .armoury: return "take it and its racks hold an elite gun for you"
        case .radarStation: return "take it and its radar marks every base around"
        }
    }
}

enum BaseSpecialties {
    static let reach: Float = 28                    // from the base centre
    static var usedDay: [String: Int] = [:]          // daily specialities: the last game day used
    static var given: Set<String> = []               // one-off specialities already handed over
    static var told: Set<String> = []                // (session) bases already announced

    // The speciality of a base, from its key (deterministic: the same base is the same everywhere).
    static func of(_ key: String) -> BaseSpecialty {
        var h: UInt64 = 1469598103934665603
        for b in key.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        let k = Int(h % 16)
        switch k {
        case 0...2: return .ammoDepot
        case 3, 4: return .fieldHospital
        case 5: return .armoury
        case 6, 7: return .radarStation
        default: return .none
        }
    }

    static func encode() -> String {
        let u = usedDay.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ";")
        return u + "|" + given.sorted().joined(separator: ";")
    }
    static func decode(_ s: String) {
        usedDay = [:]; given = []; told = []
        let parts = s.split(separator: "|", omittingEmptySubsequences: false)
        for e in (parts.first ?? "").split(separator: ";") {
            guard let i = e.lastIndex(of: "="), let d = Int(e[e.index(after: i)...]) else { continue }
            usedDay[String(e[..<i])] = d
        }
        if parts.count > 1 { given = Set(parts[1].split(separator: ";").map(String.init)) }
    }
}

extension Game {
    // Military bases near the player: key, centre, and whether it is the player's.
    func specialtyBases() -> [(String, V3, Bool)] {
        var out: [(String, V3, Bool)] = []
        for (key, site) in greywallAlarm.sites {
            let y = world.isLoaded(site.cx, site.cz) ? Float(world.topY(site.cx, site.cz)) : player.pos.y
            out.append((key, V3(Float(site.cx) + 0.5, y, Float(site.cz) + 0.5), greywallAlarm.taken.contains(key)))
        }
        for r in bases.records.values { out.append((r.key, r.centre, r.cleared == true)) }
        return out
    }

    // Once a second (the HUD tick).
    func baseSpecialtyTick() {
        guard alive, dim.dim == .overworld else { return }
        let pp = player.pos
        for (key, c, mine) in specialtyBases() {
            let sp = BaseSpecialties.of(key)
            guard sp != .none else { continue }
            let d = simd_length(V2(c.x - pp.x, c.z - pp.z))
            if !mine {
                if d < 90 && !BaseSpecialties.told.contains(key) {
                    BaseSpecialties.told.insert(key)
                    onToast?("Intel: this base is an \(sp.name): \(sp.promise)")
                }
                continue
            }
            guard d < BaseSpecialties.reach, abs(c.y - pp.y) < 24 else { continue }
            serveSpecialty(sp, key: key)
        }
    }

    private func serveSpecialty(_ sp: BaseSpecialty, key: String) {
        let day = Int(time / DAY_LENGTH)
        switch sp {
        case .none: return
        case .ammoDepot:
            guard BaseSpecialties.usedDay[key] != day else { return }
            var kinds: [String: Int] = [:]
            for s in inventory.main.slots where !s.isEmpty {
                guard let gi = Guns.index(s.item) else { continue }
                let a = Guns.all[gi].ammo
                kinds[a] = max(kinds[a] ?? 0, Guns.magSize(s) * 3)
            }
            guard !kinds.isEmpty else { return }
            BaseSpecialties.usedDay[key] = day
            for (a, n) in kinds where Items.has(a) {
                var left = n
                let id = Items.id(a), stack = Items.def(id).maxStack
                while left > 0 {
                    let k = min(left, stack)
                    let rest = inventory.add(ItemStack(id, k))
                    if !rest.isEmpty { dropItem(rest) }
                    left -= k
                }
            }
            sfx(.gunReload(0), 0.9, at: player.pos)
            onToast?("Ammo Depot: your guns are restocked (again tomorrow)")
        case .fieldHospital:
            guard BaseSpecialties.usedDay[key] != day else { return }
            guard health < maxHealth || hunger < 20 || effects.any else { return }
            BaseSpecialties.usedDay[key] = day
            effects.clear()
            health = maxHealth; hunger = 20; saturation = 20
            sfx(.levelUp, 0.6, at: player.pos)
            onToast?("Field Hospital: patched up, fed and cleaned out (again tomorrow)")
        case .armoury:
            guard !BaseSpecialties.given.contains(key) else { return }
            BaseSpecialties.given.insert(key)
            let pool = Guns.all.indices.filter { !Guns.isRetired($0) }
            guard let gi = pool.randomElement() else { return }
            let g = Guns.all[gi]
            guard Items.has(g.key) else { return }
            var gun = ItemStack(Items.id(g.key), 1)
            gun.grade = GunGrade.roll([0, 0, 0, 1], Rand.float(in: 0..<1), Rand.float(in: 0..<1))
            gun.tag = Guns.magSize(gun)
            let rest = inventory.add(gun)
            if !rest.isEmpty { dropItem(rest) }
            if Items.has(g.ammo) {
                let a = inventory.add(ItemStack(Items.id(g.ammo), min(Items.def(Items.id(g.ammo)).maxStack, Guns.magSize(gun) * 4)))
                if !a.isEmpty { dropItem(a) }
            }
            sfx(.levelUp, 0.8, at: player.pos)
            onToast?("Armoury: you take the \(gun.displayName) from its rack")
        case .radarStation:
            guard !BaseSpecialties.given.contains(key) else { return }
            BaseSpecialties.given.insert(key)
            let pp = player.pos
            var found: [(String, V3)] = []
            if let sc = world.gen.structures {
                // The nearest of each kind seen from the player and from eight points 1.5 km out: the bases round here.
                var probes = [(Int(pp.x), Int(pp.z))]
                for k in 0..<8 { let a = Float(k) * .pi / 4; probes.append((Int(pp.x + cosf(a) * 1500), Int(pp.z + sinf(a) * 1500))) }
                for kind in [Greywall.kind, "military_base"] {
                    for (x, z) in probes {
                        guard let st = sc.nearest(kind, x: x, z: z, maxRegions: 6) else { continue }
                        let p = V3(Float(st.anchor.x), pp.y, Float(st.anchor.z))
                        let d = simd_length(V2(p.x - pp.x, p.z - pp.z))
                        guard d > 60, d < 3000, !found.contains(where: { simd_length($0.1 - p) < 32 }) else { continue }
                        found.append((kind == Greywall.kind ? "Greywall base" : "Capital citadel", p))
                    }
                }
            }
            found.sort { simd_length($0.1 - pp) < simd_length($1.1 - pp) }
            for f in found.prefix(12) { MapCache.shared.pinNamed(self, x: Int(f.1.x), z: Int(f.1.z), name: f.0) }
            onToast?(found.isEmpty ? "Radar Station: no other base shows within 3 km"
                                   : "Radar Station: \(min(12, found.count)) bases marked on your map")
        }
    }
}
