import Foundation
import simd

// Mob persistence: mobs that walk out of the loaded area (or are in the world when it is saved)
// are kept per chunk and come back when their chunk loads again — like the reference game's
// entity storage. Natural hostile mobs are not kept (they would despawn anyway).
struct MobRecord: Codable {
    var k: String
    var p: [Float]
    var yaw: Float
    var hp: Int
    var baby: Bool? = nil
    var age: Float? = nil
    var sheared: Bool? = nil
    var wool: String? = nil
    var size: Int? = nil
    var persistent: Bool? = nil
    var home: [Float]? = nil
    var name: String? = nil
    var villager: VillagerData? = nil
    var extra: [String: Float]? = nil
    var inv: [ItemStack]? = nil
    var eq: [ItemStack]? = nil
    var knot: [Int]? = nil
}

extension Mob {
    var keepOnUnload: Bool {
        if health <= 0 { return false }
        if persistent || customName != nil || villager != nil || leashed { return true }
        // Despawning categories (monsters, bats, fish, squid...) are simply dropped when their chunk unloads.
        return !kind.category.despawns
    }

    var record: MobRecord {
        var r = MobRecord(k: kind.key, p: [pos.x, pos.y, pos.z], yaw: yaw, hp: health)
        if baby { r.baby = true; r.age = age }
        if sheared { r.sheared = true }
        if kind == .sheep { r.wool = woolColor }
        if sized { r.size = slimeSize }
        if persistent { r.persistent = true }
        if let h = home { r.home = [h.x, h.y, h.z] }
        r.name = customName
        r.villager = villager
        if let c = cargo { r.inv = c.slots }
        r.eq = equip
        if let k = knot { r.knot = [k.x, k.y, k.z] } else if leashed { r.knot = [] }      // [] = held by the player
        var ex: [String: Float] = [:]
        saveExtra(&ex)
        if !ex.isEmpty { r.extra = ex }
        return r
    }

    static func from(_ r: MobRecord) -> Mob? {
        guard let kind = MobKind.named(r.k), r.p.count == 3 else { return nil }
        let m = Mob(kind, at: V3(r.p[0], r.p[1], r.p[2]))
        m.yaw = r.yaw
        if let s = r.size { m.makeSlime(size: s) }
        m.health = r.hp
        if r.baby == true { m.baby = true; m.scale = 0.5; m.age = r.age ?? 0 }
        m.sheared = r.sheared ?? false
        if let w = r.wool { m.woolColor = w }
        m.persistent = r.persistent ?? false
        if let h = r.home, h.count == 3 { m.home = V3(h[0], h[1], h[2]) }
        m.customName = r.name
        m.villager = r.villager
        if let i = r.inv { let c = ItemContainer(i.count); c.slots = i; m.cargo = c }
        m.equip = r.eq
        if let k = r.knot, k.count == 3 { m.knot = IVec3(k[0], k[1], k[2]); m.leashed = true }
        else if let k = r.knot, k.isEmpty { m.leashed = true }        // a lead the player held (it reloaded loose, the lead gone)
        if let ex = r.extra { m.loadExtra(ex) }
        return m
    }

    // Per-kind extra state (tamed, variants, ...); filled in by later systems.
    func saveExtra(_ d: inout [String: Float]) {
        if let o = owner { d["owned"] = o ? 1 : 0 }
        if variant != 0 { d["variant"] = Float(variant) }
        if sitting { d["sit"] = 1 }
        if collar != 0 { d["collar"] = Float(collar) }
        if saddled { d["saddle"] = 1 }
        if armorTier != 0 { d["armor"] = Float(armorTier) }
        if armorHP != 0 { d["armorHP"] = Float(armorHP) }
        if chested { d["chest"] = 1 }
        if raider { d["raider"] = 1 }
        if captain { d["captain"] = 1 }
        if trap { d["trap"] = 1 }
        if hasEgg { d["egg"] = 1 }
        if canPickUp { d["pickup"] = 1 }
        if let h = hive { d["hx"] = Float(h.x); d["hy"] = Float(h.y); d["hz"] = Float(h.z) }
        // A cure in progress and a player-built golem (both were lost when the mob unloaded or the world reloaded: the
        // golden apple was wasted, the golem turned on its builder near unhappy villagers).
        if cureTimer > 0 { d["cure"] = cureTimer }
        if playerBuilt { d["built"] = 1 }
        if bond != 0 { d["bond"] = bond }
        if let h = horse, h.bondXP > 0 { d["bxp"] = h.bondXP }
        if power != 1 { d["power"] = power }
        if faction == Faction.ashguard.rawValue { d["fac"] = Float(faction) }
    }
    func loadExtra(_ d: [String: Float]) {
        if let o = d["owned"] { owner = o > 0 }
        variant = Int(d["variant"] ?? 0)
        sitting = (d["sit"] ?? 0) > 0
        collar = Int(d["collar"] ?? 0)
        saddled = (d["saddle"] ?? 0) > 0
        armorTier = Int(d["armor"] ?? 0)
        armorHP = Int(d["armorHP"] ?? 0)
        chested = (d["chest"] ?? 0) > 0
        raider = (d["raider"] ?? 0) > 0
        captain = (d["captain"] ?? 0) > 0
        trap = (d["trap"] ?? 0) > 0
        hasEgg = (d["egg"] ?? 0) > 0
        canPickUp = (d["pickup"] ?? 0) > 0
        power = d["power"] ?? 1
        if let x = d["hx"], let y = d["hy"], let z = d["hz"] { hive = IVec3(Int(x), Int(y), Int(z)) }
        cureTimer = d["cure"] ?? 0
        playerBuilt = (d["built"] ?? 0) > 0
        bond = d["bond"] ?? 0
        if let x = d["bxp"] { hs.bondXP = x }
        if let f = d["fac"], Int(f) == Faction.ashguard.rawValue { faction = Int(f); ashSetup() }
    }
}

extension MobManager {
    // Stores a mob leaving the loaded area.
    func stash(_ m: Mob) {
        let k = ChunkKey(x: floorDiv(Int(floor(m.pos.x)), CS), z: floorDiv(Int(floor(m.pos.z)), CS))
        stored[k, default: []].append(m.record)
    }

    // Brings back stored mobs whose chunk is loaded and inside the active area.
    func restore(_ w: World, center p: V3, limit: Float) {
        guard !stored.isEmpty else { return }
        var back: [ChunkKey] = []
        for (k, _) in stored {
            let cx = Float(k.x * CS + 8), cz = Float(k.z * CS + 8)
            if abs(cx - p.x) < limit - 16 && abs(cz - p.z) < limit - 16 && w.isLoaded(k.x * CS + 8, k.z * CS + 8) { back.append(k) }
        }
        for k in back {
            for r in stored.removeValue(forKey: k) ?? [] { if let m = Mob.from(r) { mobs.append(m) } }
        }
    }

    // Everything (live + stored) for the save file.
    func save(to s: SaveManager?, background: Bool = false) {
        guard let s = s else { return }
        var all: [String: [MobRecord]] = [:]
        for (k, v) in stored { all["\(k.x),\(k.z)"] = v }
        for m in mobs where m.keepOnUnload {
            let k = "\(floorDiv(Int(floor(m.pos.x)), CS)),\(floorDiv(Int(floor(m.pos.z)), CS))"
            all[k, default: []].append(m.record)
        }
        let url = s.dir.appendingPathComponent("mobs.json")
        if background { SaveIO.writeJSON(all, to: url) }       // (MobRecord: value snapshots)
        else if let d = try? JSONEncoder().encode(all) { try? d.write(to: url, options: .atomic) }
        savePopulated(to: s)
        saveHives(to: s)
    }

    func load(from s: SaveManager?) {
        loadPopulated(from: s)
        loadHives(from: s)
        guard let s = s, let d = try? Data(contentsOf: s.dir.appendingPathComponent("mobs.json")),
              let all = try? JSONDecoder().decode([String: [MobRecord]].self, from: d) else { return }
        for (key, v) in all {
            let p = key.split(separator: ",").compactMap { Int($0) }
            guard p.count == 2 else { continue }
            stored[ChunkKey(x: p[0], z: p[1]), default: []] += v
        }
    }
}
