import Foundation
import simd

// `--questbugs --only factions` (task 23): Capital cities and citadels generate and can be found, saved worlds keep
// their explored ground (the structure guard), the Meridian frigate, its MAC gun, the radar, intercepted orders and
// the base components.
enum FactionTests {
    static func run(_ game: Game, _ check: (Bool, String) -> Void) {
        structures(check)
        gear(game, check)
        frigate(game, check)
    }

    // Components, recipes, the radar and intercepted orders.
    static func gear(_ g: Game, _ check: (Bool, String) -> Void) {
        for t in ["steelhold_armory", "steelhold_command", "steelhold_vault", "meridian_hold"] {
            let names = Set((Loot.tables[t]?.entries ?? []).map { $0.0 })
            check(names.contains("firing_mechanism") || names.contains("targeting_optic") || names.contains("radar_module"),
                  "factions: base components drop from \(t)")
        }
        func crafts(_ ings: [String]) -> String? {
            var grid = [ItemID](repeating: 0, count: 9)
            for (i, n) in ings.enumerated() { grid[i] = Items.id(n) }
            return Recipes.match(grid, 3, 3).map { Items.key($0.result.item) }
        }
        check(crafts(["steel_ingot", "steel_ingot", "firing_mechanism"]) == "gun_sidearm"
              && crafts(["steel_ingot", "steel_ingot", "steel_ingot", "steel_ingot", "firing_mechanism", "targeting_optic"]) == "gun_sniper"
              && crafts(["radar_module", "compass", "steel_ingot", "steel_ingot", "redstone"]) == "radar_set"
              && crafts(["steel_ingot", "steel_ingot", "steel_ingot", "steel_ingot"]) != "gun_rifle",
              "factions: guns and the radar craft from base components only")
        guard g.dim.dim == .overworld else { check(false, "factions: gear checks need the overworld"); return }
        let wasDragon = g.dragonKilled, wasAsh = g.ashVictory, slot = g.inventory.selected
        let held = g.inventory.main[slot]
        defer { g.dragonKilled = wasDragon; g.ashVictory = wasAsh; g.inventory.main[slot] = held }
        g.dragonKilled = false; g.ashVictory = false
        let pre = g.radarContacts()
        check(pre.contains { $0.kind == "military_base" } && pre.contains { $0.kind == "capital_city" } && !pre.contains { $0.kind.hasPrefix("vessel_") },
              "factions: before the end the radar shows Capital sites only (\(pre.map { $0.kind }))")
        g.dragonKilled = true
        let war = g.nearestWarship()
        check(war == nil || war!.kind.hasPrefix("vessel_"), "factions: after the end the radar finds warships (\(war?.name ?? "none in range"))")
        g.dragonKilled = false
        g.inventory.main[slot] = ItemStack(Items.id("intercepted_orders"), 2)
        let used = g.factionGearUse()
        let mark = MapCache.shared.marks.last
        check(used && g.inventory.main[slot].count == 1 && mark.map { $0.kind == "capital_city" || $0.kind == "military_base" } == true,
              "factions: intercepted orders are read (1 used) and mark a Capital site (\(mark?.kind ?? "none"))")
        g.inventory.main[slot] = ItemStack(Items.id("radar_set"), 1)
        check(g.factionGearUse() && g.inventory.main[slot].count == 1, "factions: the radar marks its contacts and is kept")
    }

    // The Meridian frigate: its own faction, foes of the Capital, a fast commandeered helm and a MAC that craters a citadel.
    static func frigate(_ g: Game, _ check: (Bool, String) -> Void) {
        guard g.dim.dim == .overworld, let sc = g.world.gen.structures else { return }
        let w = g.world
        let px = Int(g.player.pos.x), pz = Int(g.player.pos.z)
        guard let base = sc.nearest("military_base", x: px, z: pz, maxRegions: 6) else { check(false, "factions: no citadel for the MAC check"); return }
        let home = g.player.pos
        defer { g.player.pos = home; g.player.vel = .zero }
        let cx = (base.min.x + base.max.x) / 2, cz = (base.min.z + base.max.z) / 2
        g.player.pos = V3(Float(cx) + 0.5, 200, Float(cz) + 0.5)
        _ = w.loadSync(center: g.player.pos, radius: 4)
        // The crater: a dense bowl wherever it lands, walls and all.
        var tops: [Int] = []                                    // the median surface (not a flagpole or tower top)
        for dz in stride(from: -8, through: 8, by: 4) { for dx in stride(from: -8, through: 8, by: 4) {
            var y = CH - 1
            while y > 0 && (w.block(cx + dx, y, cz + dz) == 0 || Blocks.isLiquid(w.block(cx + dx, y, cz + dz))) { y -= 1 }
            tops.append(y)
        } }
        let top = tops.sorted()[tops.count / 2]
        func solid() -> Int {
            var n = 0
            for y in (top - 10)...(top + 10) { for z in (cz - 10)...(cz + 10) { for x in (cx - 10)...(cx + 10) where w.block(x, y, z) != 0 { n += 1 } } }
            return n
        }
        let before = solid()
        Explosion.crater(at: V3(Float(cx) + 0.5, Float(top) + 0.5, Float(cz) + 0.5), radius: 9, game: g)
        let removed = before - solid()
        var left = 0                                            // anything breakable still inside the inner bowl
        for y in (top - 4)...(top + 6) { for z in (cz - 6)...(cz + 6) { for x in (cx - 6)...(cx + 6) {
            let d = V3(Float(x - cx), Float(y - top) * (y < top ? 1.5 : 1), Float(z - cz))
            let id = w.block(x, y, z)
            if simd_length(d) < 6, id != 0, !Blocks.isLiquid(id), Blocks.hardness[Int(id)] >= 0 { left += 1 }
        } } }
        check(removed > 300 && left == 0, "factions: a MAC hit craters the citadel (\(removed) of \(before) blocks gone, \(left) left in the bowl, at \(cx),\(top),\(cz))")
        // The frigate itself.
        let n0 = w.ships.list.count
        w.ships.spawnCapital("capfrigate", home: IVec3(cx + 120, 0, cz), yaw: 0.4, region: nil, sync: true)
        guard let s = w.ships.list.dropFirst(n0).first(where: { $0.role == "capfrigate" }) else { check(false, "factions: the Meridian frigate spawns"); return }
        defer { w.ships.remove(s) }
        check(s.factionValue == .meridian && Faction.meridian != .steelhold, "factions: the frigate flies for the Meridian Navy")
        let foe = w.ships.nearestFoe(of: .steelhold, near: s.pos, range: 300, game: g)
        check(foe?.ship.map { $0.root === s } == true, "factions: Capital forces count the frigate as a foe")
        w.ships.capState[s.id]?.mainGunCD = 0
        let shells0 = w.ships.shells.filter { $0.kind == 3 }.count
        let fired = w.ships.playerMAC(s, pitch: -0.3, game: g)
        let again = w.ships.playerMAC(s, pitch: -0.3, game: g)
        check(fired && !again && w.ships.shells.filter { $0.kind == 3 }.count == shells0 + 1 && (w.ships.macCharge(s) ?? 0) > 5,
              "factions: the MAC fires from the helm, then recharges")
        w.ships.shells.removeAll { $0.kind == 3 }
    }

    static func structures(_ check: (Bool, String) -> Void) {
        let fm = FileManager.default
        // Cities and citadels near spawn on a spread of seeds.
        var worst = 0, worstBase = 0
        for i in 0..<6 {
            let seed = UInt64(1000 + i * 7919)
            let gen = WorldGen(seed: seed)
            guard let sc = gen.structures else { check(false, "factions: structures"); return }
            let o = Game.spawnOrigin(seed: seed)
            let x = o.0 * 16, z = o.1 * 16
            let c = sc.nearest("capital_city", x: x, z: z, maxRegions: 3)
            let b = sc.nearest("military_base", x: x, z: z, maxRegions: 4)
            let dc = c.map { Int(simd_length(V2(Float($0.anchor.x - x), Float($0.anchor.z - z)))) } ?? 99999
            let db = b.map { Int(simd_length(V2(Float($0.anchor.x - x), Float($0.anchor.z - z)))) } ?? 99999
            worst = max(worst, dc); worstBase = max(worstBase, db)
        }
        check(worst < 2200, "factions: a Capital city within 2,200 blocks of spawn on 6 seeds (worst \(worst))")
        check(worstBase < 1200, "factions: a Capital citadel within 1,200 blocks of spawn on 6 seeds (worst \(worstBase))")

        // The structure guard: taken once from the chunk folder, never grows afterwards.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("factions-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? fm.removeItem(at: tmp)
        let sm = SaveManager(dir: tmp.appendingPathComponent("w"))
        let b = [BlockID](repeating: STONE, count: CSQ * CH)
        sm.saveChunk(ChunkKey(x: 1, z: -2), b)
        let g1 = sm.structureGuard()
        sm.saveChunk(ChunkKey(x: 5, z: 5), b)
        let g2 = sm.structureGuard()
        check(g1 == [StructureCache.key(1, -2)] && g2 == g1, "factions: the structure guard lists the chunks saved before the update only (\(g1.count), \(g2.count))")

        // Saved worlds on this Mac: no new or moved structure lands on ground they had already generated.
        let worlds = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Blocksmith/Worlds")
        for n in ((try? fm.contentsOfDirectory(atPath: worlds.path)) ?? []).sorted() {
            let src = worlds.appendingPathComponent(n)
            let copy = tmp.appendingPathComponent("w-\(n)")
            guard (try? fm.copyItem(at: src, to: copy)) != nil else { continue }
            let w = SaveManager(dir: copy)
            guard let meta = w.loadMeta() else { continue }
            try? fm.removeItem(at: copy.appendingPathComponent("structure-guard.txt"))   // as on its first load after the update
            let gen = WorldGen(seed: meta.seed)
            guard let sc = gen.structures else { continue }
            sc.legacy = w.structureGuard()
            var cities = 0, moved = 0, bad: [String] = []
            for t in sc.types where t.name == "capital_city" || t.name == "military_base" {
                let rx0 = floorDiv(floorDiv(Int(meta.x), CS), t.spacing), rz0 = floorDiv(floorDiv(Int(meta.z), CS), t.spacing)
                for rz in (rz0 - 3)...(rz0 + 3) { for rx in (rx0 - 3)...(rx0 + 3) {
                    guard let s = sc.start(t, regionX: rx, regionZ: rz) else { continue }
                    let ccx = floorDiv((s.min.x + s.max.x) / 2, CS), ccz = floorDiv((s.min.z + s.max.z) / 2, CS)
                    let original = t.name == "military_base" && sc.candidate(t, rx, rz) == (ccx, ccz)
                    if t.name == "capital_city" { cities += 1 } else if !original { moved += 1 }
                    if original { continue }
                    var hit = false
                    for z in floorDiv(s.min.z, CS)...floorDiv(s.max.z, CS) { for x in floorDiv(s.min.x, CS)...floorDiv(s.max.x, CS) where sc.legacy.contains(StructureCache.key(x, z)) { hit = true } }
                    if hit { bad.append("\(t.name) \(s.anchor.x),\(s.anchor.z)") }
                } }
            }
            let px = Int(meta.x), pz = Int(meta.z)
            let near = ["military_base", "capital_city"].map { k -> Int in
                guard let s = sc.nearest(k, x: px, z: pz, maxRegions: 3) else { return -1 }
                return Int(simd_length(V2(Float(s.anchor.x - px), Float(s.anchor.z - pz))))
            }
            check(bad.isEmpty, "factions: saved world '\(n)' (\(sc.legacy.count) explored chunks): \(cities) cities and \(moved) new citadel sites nearby, none on explored ground \(bad); nearest citadel \(near[0]), city \(near[1]) blocks")
        }
        try? fm.removeItem(at: tmp)
    }
}
