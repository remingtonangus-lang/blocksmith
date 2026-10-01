import Foundation
import simd

// Bees (reference behaviour): each bee remembers a nest or hive within 16 blocks, flies to flowers by day,
// hovers ~10 s to collect nectar, grows crops it passes over while carrying it, and goes home at night,
// in rain or once it has nectar. Inside (max 3 per hive) a bee with nectar adds one honey level (0-5);
// bees come back out by day after 2 minutes (30 s without nectar). Taking honey or combs angers the bees
// unless a campfire smokes the hive from up to 5 blocks below.
struct HiveRecord: Codable { var p: [Int]; var bees: [Bool]; var t: [Float] }

extension MobManager {
    // Bees currently inside hives: nectar flag and seconds spent inside.
    func hiveTick(_ dt: Float, _ g: Game) {
        guard !hives.isEmpty else { return }
        let w = g.world
        var gone: [IVec3] = []
        for (h, var bees) in hives {
            guard w.isLoaded(h.x, h.z) else { continue }
            for i in bees.indices { bees[i].time += dt }
            let key = Blocks.key(Blocks.groupBase[Int(w.block(h.x, h.y, h.z))])
            let broken = key != "bee_nest" && key != "beehive"
            let day = g.daylight > 0.5 && !g.isRainingAt(V3(Float(h.x), Float(h.y + 1), Float(h.z)))
            var keep: [(nectar: Bool, time: Float)] = []
            for b in bees {
                if broken || (day && b.time > (b.nectar ? 120 : 30)) { releaseBee(w, from: h, angry: broken) } else { keep.append(b) }
            }
            if keep.isEmpty { gone.append(h) } else { hives[h] = keep }
        }
        for h in gone { hives[h] = nil }
    }

    func releaseBee(_ w: World, from h: IVec3, angry: Bool) {
        var at = V3(Float(h.x) + 0.5, Float(h.y) + 1.1, Float(h.z) + 0.5)
        for (dx, dz) in [(0, -1), (0, 1), (-1, 0), (1, 0)] where w.block(h.x + dx, h.y, h.z + dz) == AIR {
            at = V3(Float(h.x + dx) + 0.5, Float(h.y) + 0.2, Float(h.z + dz) + 0.5)
            break
        }
        let b = Mob(.bee, at: at)
        b.hive = h
        b.aggro = angry
        mobs.append(b)
    }

    func saveHives(to s: SaveManager?) {
        guard let s = s else { return }
        let recs = hives.map { HiveRecord(p: [$0.key.x, $0.key.y, $0.key.z], bees: $0.value.map { $0.nectar }, t: $0.value.map { $0.time }) }
        if let d = try? JSONEncoder().encode(recs) { try? d.write(to: s.dir.appendingPathComponent("hives.json"), options: .atomic) }
    }

    func loadHives(from s: SaveManager?) {
        guard let s = s, let d = try? Data(contentsOf: s.dir.appendingPathComponent("hives.json")),
              let recs = try? JSONDecoder().decode([HiveRecord].self, from: d) else { return }
        for r in recs where r.p.count == 3 {
            hives[IVec3(r.p[0], r.p[1], r.p[2])] = zip(r.bees, r.t).map { (nectar: $0.0, time: $0.1) }
        }
    }
}

extension Mob {
    static let beeFlowers: Set<String> = ["dandelion", "poppy", "blue_orchid", "allium", "azure_bluet", "red_tulip", "orange_tulip",
                                          "white_tulip", "pink_tulip", "oxeye_daisy", "cornflower", "lily_of_the_valley", "sunflower",
                                          "lilac", "rose_bush", "peony", "torchflower", "pitcher_plant", "flowering_azalea",
                                          "flowering_azalea_leaves", "cherry_leaves", "pink_petals", "wither_rose", "spore_blossom"]

    func isHive(_ w: World, _ p: IVec3) -> Bool {
        let k = Blocks.key(Blocks.groupBase[Int(w.block(p.x, p.y, p.z))])
        return k == "bee_nest" || k == "beehive"
    }

    // Scans a few random spots for a block in `keys` (cheap: 40 samples).
    func findNearby(_ w: World, radius: Int, where ok: (IVec3) -> Bool) -> IVec3? {
        let c = IVec3(Int(floor(pos.x)), Int(floor(pos.y)), Int(floor(pos.z)))
        var best: IVec3?
        var bd = Int.max
        for _ in 0..<40 {
            let q = IVec3(c.x + Int.random(in: -radius...radius), c.y + Int.random(in: -4...4), c.z + Int.random(in: -radius...radius))
            guard ok(q) else { continue }
            let d = (q.x - c.x) * (q.x - c.x) + (q.y - c.y) * (q.y - c.y) + (q.z - c.z) * (q.z - c.z)
            if d < bd { bd = d; best = q }
        }
        return best
    }

    // Returns 0 (bees move by velocity); called from animalAI when not angry.
    func beeAI(_ dt: Float, _ g: Game) -> Float {
        let w = g.world
        jobTimer -= dt
        if jobTimer <= 0 {
            jobTimer = 10
            if let h = hive, !isHive(w, h) { hive = nil }
            if hive == nil { hive = findNearby(w, radius: 16) { self.isHive(w, $0) } }
        }
        let homeTime = g.daylight < 0.45 || g.isRainingAt(pos) || nectar
        var goal: V3?
        if let h = hive, homeTime {
            let c = V3(Float(h.x) + 0.5, Float(h.y) + 0.5, Float(h.z) + 0.5)
            goal = c
            if simd_length(c - pos) < 1.4 {
                var inside = g.mobs.hives[h] ?? []
                if inside.count < 3 {
                    inside.append((nectar: nectar, time: 0))
                    g.mobs.hives[h] = inside
                    if nectar {
                        let b = w.block(h.x, h.y, h.z)
                        if Int(b - Blocks.groupBase[Int(b)]) < 5 { w.setBlock(h.x, h.y, h.z, b + 1) }
                    }
                    health = -2000                       // gone inside (no drops)
                    return 0
                }
            }
        } else if !nectar {
            if let f = flower, !Mob.beeFlowers.contains(Blocks.key(Blocks.groupBase[Int(w.block(f.x, f.y, f.z))])) { flower = nil }
            if flower == nil && aiTimer <= 0 {
                aiTimer = 3
                flower = findNearby(w, radius: 10) { Mob.beeFlowers.contains(Blocks.key(Blocks.groupBase[Int(w.block($0.x, $0.y, $0.z))])) }
            }
            if let f = flower {
                let c = V3(Float(f.x) + 0.5, Float(f.y) + 0.6, Float(f.z) + 0.5)
                goal = c
                if simd_length(c - pos) < 0.8 {
                    scuteTimer = min(scuteTimer, 10) - dt
                    if scuteTimer <= 0 { nectar = true; flower = nil; scuteTimer = 10 }
                }
            }
        }
        // Carrying nectar: grow a crop below now and then (reference: up to 10 per trip).
        if nectar && Float.random(in: 0..<1) < dt * 0.5 {
            let q = IVec3(Int(floor(pos.x)), Int(floor(pos.y)) - 1, Int(floor(pos.z)))
            let b = w.block(q.x, q.y, q.z)
            let base = Blocks.groupBase[Int(b)]
            if let (ripe, _) = VillageLife.crops[Blocks.key(base)], Int(b - base) < ripe { w.setBlock(q.x, q.y, q.z, b + 1) }
        }
        if goal == nil {
            if aiTimer <= 0 || flyTarget == nil {
                aiTimer = Float.random(in: 3...8)
                flyTarget = pos + V3(Float.random(in: -6...6), Float.random(in: -1...2), Float.random(in: -6...6))
            }
            goal = flyTarget
        }
        if let t = goal {
            let d = t - pos
            let l = simd_length(d)
            let want: V3 = l > 0.2 ? d * (min(3, l * 2) / l) : V3.zero
            let k: Float = min(1, dt * 2.5)
            vel += (want - vel) * k
            if l > 0.2 { face(t) }
        }
        return 0
    }
}

extension Game {
    // Honey or combs taken: every bee around (and in the hive) is angered, unless a campfire smokes it.
    func beeHiveDisturbed(_ c: V3) {
        let x = Int(floor(c.x)), y = Int(floor(c.y)), z = Int(floor(c.z))
        for dy in 1...5 where Blocks.key(Blocks.groupBase[Int(world.block(x, y - dy, z))]).hasSuffix("campfire") { return }
        for m in mobs.of(.bee) where simd_length(m.pos - c) < 16 { m.aggro = true; m.lockTime = 20 }
        let h = IVec3(x, y, z)
        if let inside = mobs.hives[h] {
            for _ in inside { mobs.releaseBee(world, from: h, angry: true) }
            mobs.hives[h] = nil
        }
    }
}
