import Foundation
import simd
import Metal

// P292's quick check (questcheck --hellcheck): hell is its own. The new fortress and roost are built from hell's own
// blocks and creatures and can be walked from their entrance to their treasure; the slots build them on fresh ground and
// the old designs on ground an older save generated; natural spawns in both hells are hell's own; the retire pass turns
// an old save's copied creatures (and an Ashguard post in hell) into their heirs; the five lands show their own ground;
// the route down (rods, flux, the Brand Star, the Ember Charge) still crafts; the keep's garrison carries no gun.
enum HellCheck {
    final class Blocks3 {
        var chunks: [Int64: [BlockID]] = [:]
        var mobs: [String] = [], spawners: [String] = []
        var count: [String: Int] = [:]
        func get(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
            guard y >= 0 && y < CH, let c = chunks[StructureCache.key(floorDiv(x, CS), floorDiv(z, CS))] else { return STONE }
            return c[Chunk.index(x - floorDiv(x, CS) * CS, y, z - floorDiv(z, CS) * CS)]
        }
    }

    // Every piece of a start built chunk by chunk into stone (to y 120, air above), as the generator does.
    static func build(_ s: StructureStart) -> Blocks3 {
        let out = Blocks3()
        var x0 = Int.max, z0 = Int.max, x1 = Int.min, z1 = Int.min
        for p in s.pieces { x0 = min(x0, p.min.x); z0 = min(z0, p.min.z); x1 = max(x1, p.max.x); z1 = max(z1, p.max.z) }
        for cz in floorDiv(z0, CS)...floorDiv(z1, CS) { for cx in floorDiv(x0, CS)...floorDiv(x1, CS) {
            var b = [BlockID](repeating: STONE, count: CS * CS * CH)
            for i in (CS * CS * 120)..<(CS * CS * CH) { b[i] = AIR }
            b.withUnsafeMutableBufferPointer { buf in
                var w = StructWriter(bx: cx * CS, bz: cz * CS, blocks: buf.baseAddress!)
                for p in s.pieces where p.overlaps(cx * CS, cz * CS) { p.build(&w) }
                for (_, be) in w.entities where be.kind == .spawner && !be.mob.isEmpty { out.spawners.append(be.mob) }
                out.mobs += w.mobs.map { $0.0 }
            }
            var n = [Int](repeating: 0, count: Blocks.count)
            for v in b { n[Int(v)] += 1 }
            for (i, k) in n.enumerated() where k > 0 { out.count[Blocks.key(Blocks.groupBase[i]), default: 0] += k }
            out.chunks[StructureCache.key(cx, cz)] = b
        } }
        return out
    }

    // Cells a walker reaches from `from` (feet cells): steps of one up, drops of three, ladders up and down.
    static func walk(_ b: Blocks3, from: IVec3, box: (IVec3, IVec3)) -> Set<IVec3> {
        let ladder = Blocks.id("ladder")
        func isLadder(_ v: BlockID) -> Bool { Blocks.groupBase[Int(v)] == ladder }
        func open(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            let v = b.get(x, y, z)
            return isLadder(v) || (!Blocks.collide[Int(v)] && !Blocks.isLiquid(v))
        }
        func ground(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            let v = b.get(x, y - 1, z)
            return isLadder(b.get(x, y, z)) || (Blocks.collide[Int(v)] && !isLadder(v))
        }
        func stand(_ x: Int, _ y: Int, _ z: Int) -> Bool { open(x, y, z) && open(x, y + 1, z) && ground(x, y, z) }
        var seen: Set<IVec3> = [from], todo = [from]
        while let c = todo.popLast() {
            var next: [IVec3] = []
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                for dy in [1, 0, -1, -2, -3] {
                    let n = IVec3(c.x + dx, c.y + dy, c.z + dz)
                    guard stand(n.x, n.y, n.z) else { continue }
                    if dy == 1 && !open(c.x, c.y + 2, c.z) { continue }
                    if dy < 0 && !(0...(-dy)).allSatisfy({ open(n.x, c.y - $0 + 1, n.z) && open(n.x, c.y - $0, n.z) }) { continue }
                    next.append(n); break
                }
            }
            if isLadder(b.get(c.x, c.y, c.z)) && open(c.x, c.y + 1, c.z) { next.append(IVec3(c.x, c.y + 1, c.z)) }
            if isLadder(b.get(c.x, c.y - 1, c.z)) { next.append(IVec3(c.x, c.y - 1, c.z)) }
            for n in next where !seen.contains(n) && n.x >= box.0.x && n.x <= box.1.x && n.z >= box.0.z && n.z <= box.1.z
                && n.y >= box.0.y && n.y <= box.1.y {
                seen.insert(n); todo.append(n)
            }
        }
        return seen
    }

    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        guard let device = MTLCreateSystemDefaultDevice() else { print("hellcheck: no device"); return 2 }
        let t0 = CFAbsoluteTimeGetCurrent()
        var fails = 0
        func check(_ ok: Bool, _ what: String) { print("hellcheck: \(ok ? "ok  " : "FAIL") \(what)"); if !ok { fails += 1 } }
        func kindKey(_ s: String) -> String { String(s.split(separator: "@")[0].split(separator: ":")[0].split(separator: "^")[0]) }
        let own = Set(MobKind.allCases.filter { $0.hellOwn }.map { $0.key })

        // (c) The Brand Chapterhouse: hell's blocks and creatures, walkable from the causeway to every part.
        var rng = SRng(77)
        let ch = BrandChapterhouse.start(&rng, ox: 8, oz: 8, base: 0)
        let c = build(ch)
        let f = ch.anchor.y - 1
        let foreign = c.mobs.filter { !own.contains(kindKey($0)) } + c.spawners.filter { !own.contains(kindKey($0)) }
        check(c.count["nether_bricks", default: 0] == 0 && c.count["nether_brick_fence", default: 0] == 0 && c.count["steel_plating", default: 0] == 0
              && foreign.isEmpty && Set(c.spawners) == ["searwing", "slagthrower", "scorchling"] && c.count["chest", default: 0] >= 4,
              "\(BrandChapterhouse.name): \(c.count["red_nether_bricks", default: 0]) red brick, no old fortress brick or steel; spawners \(c.spawners.sorted()); garrison \(c.mobs.map(kindKey).sorted()); \(c.count["chest", default: 0]) chests; foreign \(foreign)")
        let lo = IVec3(8 - 30, f - 4, 8 - 26), hi = IVec3(8 + 30, f + 30, 8 + 33)
        let reach = walk(c, from: IVec3(ch.anchor.x, ch.anchor.y, ch.anchor.z), box: (lo, hi))
        func near(_ dx: Int, _ y: Int, _ dz: Int, _ r: Int = 1) -> Bool {
            for z in (dz - r)...(dz + r) { for x in (dx - r)...(dx + r) where reach.contains(IVec3(8 + x, y, 8 + z)) { return true } }
            return false
        }
        let places: [(String, Bool)] = [("courtyard", near(0, f + 1, 10)), ("chapter hall dais", near(0, f + 1, -11)),
            ("hall chests", near(-4, f + 2, -14) && near(4, f + 2, -14)), ("forge", near(15, f + 1, 4)), ("barracks", near(-17, f + 1, 2)),
            ("south walk", near(12, f + 9, 17)), ("north walk", near(-12, f + 9, -17)),
            ("tower roofs", near(22, f + 14, 18) && near(22, f + 14, -18) && near(-22, f + 14, 18)), ("belfry", near(-20, f + 20, -16))]
        check(places.allSatisfy { $0.1 }, "\(BrandChapterhouse.name): walked from the causeway to \(places.filter { $0.1 }.map { $0.0 }.joined(separator: ", "))"
              + (places.contains { !$0.1 } ? "; NOT to \(places.filter { !$0.1 }.map { $0.0 }.joined(separator: ", "))" : "") + " (\(reach.count) cells)")

        // (c) The Searwing Roost: up the stair from the islet to the treasure nest.
        let ro = SearwingRoost.start(ox: 8, oz: 8, y: 33, base: 0, seed: 5)
        let r = build(ro)
        let rforeign = r.mobs.filter { !own.contains(kindKey($0)) } + r.spawners.filter { !own.contains(kindKey($0)) }
        check(rforeign.isEmpty && Set(r.spawners) == ["searwing", "scorchling"] && r.count["chest", default: 0] == 2 && r.count["gold_block", default: 0] >= 1,
              "\(SearwingRoost.name): spawners \(r.spawners.sorted()), \(r.mobs.count) on the nests, \(r.count["chest", default: 0]) chests, \(r.count["gold_block", default: 0]) gold; foreign \(rforeign)")
        let top = 33 + SearwingRoost.tall
        let up = walk(r, from: IVec3(ro.anchor.x, ro.anchor.y, ro.anchor.z), box: (IVec3(8 - 16, 20, 8 - 16), IVec3(8 + 16, top + 6, 8 + 16)))
        let summit = [(0, 1), (1, 0), (-1, 0), (0, -1), (0, 2), (2, 0), (-2, 0), (0, -2)].contains { up.contains(IVec3(8 + $0.0, top + 1, 8 + $0.1)) }
        check(summit, "\(SearwingRoost.name): the stair climbs \(SearwingRoost.tall) from the islet to the treasure nest (\(up.count) cells, highest \((up.map { $0.y }.max() ?? 0) - 33))")

        // (c, e) The slots: the new designs on fresh ground, the old ones where a save generated ground before them.
        func firstStart(_ t: StructureType) -> (StructureStart, Int, Int)? {
            for cz in 0..<40 { for cx in 0..<40 { if let s = t.make(UInt64(cx * 977 + cz * 31 + 5), cx, cz) { return (s, cx, cz) } } }
            return nil
        }
        if let fs = firstStart(Fortress.type), let bs = firstStart(Bastion.type) {
            let (s, cx, cz) = fs, (b, bx, bz) = bs
            let freshF = s.pieces.count == 1 && s.kind == "fortress", freshB = b.anchor == IVec3(bx * CS + 8 + 9, YOFF + 34, bz * CS + 8 - 2)
            P292Guard.nether = [StructureCache.key(cx, cz), StructureCache.key(bx, bz)]
            let oldF = Fortress.type.make(UInt64(cx * 977 + cz * 31 + 5), cx, cz), oldB = Bastion.type.make(UInt64(bx * 977 + bz * 31 + 5), bx, bz)
            P292Guard.nether = []
            check(freshF && freshB && (oldF?.pieces.count ?? 0) > 1 && oldB?.anchor.z == bz * CS + 8 + BoarlingMound.half - 1,
                  "slots: fresh ground builds a chapterhouse (\(s.pieces.count) piece) and a roost; ground a save made before keeps the Ash Foundry (\(oldF?.pieces.count ?? 0) cells) and the mound")
        } else { check(false, "slots: no fortress or bastion start found") }

        // (a, d) The keep's garrison: the Brand Order, Slagthrowers and Searwings; no gun, no Ashguard.
        let keep = build(BrimstoneKeep.layout(ox: 8, oz: 8, seed: 7))
        let kforeign = keep.mobs.filter { !own.contains(kindKey($0)) } + keep.spawners.filter { !own.contains(kindKey($0)) }
        check(kforeign.isEmpty && keep.mobs.contains("brand_champion:warden@deep") && keep.count["sunderite_ore", default: 0] >= BrimstoneKeep.oreMin,
              "Brimstone Keep: garrison of \(keep.mobs.count) all hell's own (\(Set(keep.mobs.map(kindKey)).sorted())), the Castellan a Brand Champion, \(keep.count["sunderite_ore", default: 0]) Sunderite Ore; foreign \(kforeign)")

        // (b) The five lands: their own ground and growth.
        let gen = EmberGen(seed: 4242)
        func land(_ want: Biome) -> [String: Int] {
            var n = [Int](repeating: 0, count: Blocks.count)
            func out() -> [String: Int] {
                var o: [String: Int] = [:]
                for (i, k) in n.enumerated() where k > 0 { o[Blocks.key(Blocks.groupBase[i]), default: 0] += k }
                return o
            }
            for r in 0..<80 { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
                guard gen.biome(dx * CS + 8, dz * CS + 8) == want, gen.biome(dx * CS + 24, dz * CS + 8) == want, gen.biome(dx * CS - 8, dz * CS + 8) == want else { continue }
                for k in 0..<9 { for v in gen.generate(cx: dx + k % 3 - 1, cz: dz + k / 3 - 1) { n[Int(v)] += 1 } }
                return out()
            } } }
            return out()
        }
        let lands: [(Biome, String, [String])] = [(.netherWastes, "Cinder Plains", ["netherrack", "magma_block"]),
            (.soulSandValley, "Ash Dunes", ["soul_sand", "soul_soil", "nether_wart"]), (.crimsonForest, "Charwood Thicket", ["crimson_stem", "nether_wart_block", "crimson_nylium"]),
            (.warpedForest, "Gloamwood", ["warped_stem", "warped_wart_block", "warped_nylium"]), (.basaltDeltas, "Sulfur Flats", ["sulfur_crust", "blackstone", "magma_block"])]
        for (b, name, keys) in lands {
            let n = land(b)
            check(keys.allSatisfy { n[$0, default: 0] > 0 }, "\(name): " + keys.map { "\($0) \(n[$0, default: 0])" }.joined(separator: ", "))
        }

        // The route down: cinder rods to powder, Sunderite flux, the Brand Star's beacon, the Ember Charge.
        let crafted = Set(Recipes.all.map { Items.key($0.result.item) })
        let route = ["blaze_powder", "sunderite_flux", "beacon", "ender_eye", HellGate.chargeKey, DeepSeal.pickaxe]
        check(route.allSatisfy { crafted.contains($0) } && MobKind.slagthrower.living(inHell: true) == .slagthrower
              && MobKind.brandCommander.spec.drops.contains { $0.0 == "nether_star" } && MobKind.searwing.spec.drops.contains { $0.0 == "ghast_tear" },
              "route: \(route.filter { crafted.contains($0) }.count)/\(route.count) crafts; rods from Slagthrowers, the Brand Star from the Commander, tears from Searwings")

        // (a, e) An old save in the Emberdeep: its copied creatures and an Ashguard post become their heirs where they stand.
        let world = World(seed: 4242, device: device, save: nil, dim: .nether)
        world.renderDistance = 5
        let game = Game(world: world, save: nil, persistent: false)
        game.paused = false
        let at = V3(0.5, Float(YOFF + 70), 0.5)
        game.player.pos = at
        _ = world.loadSync(center: at, radius: 5)
        game.mobs.mobs.removeAll()
        let old: [MobKind] = MobKind.retiredHellKinds
        for (i, k) in old.enumerated() { game.mobs.mobs.append(Mob(k, at: at + V3(Float(i) * 2 - 10, 0, 6))) }
        let castellan = Mob(.piglinBrute, at: at + V3(0, 0, -6))
        castellan.makeKeepWarden(); castellan.health = 120
        game.mobs.mobs.append(castellan)
        game.mobs.retireHell(game)
        let after = game.mobs.mobs
        let heir = after.first { $0.warden }
        let soldier = Mob(.soldierMarksman, at: at + V3(4, 0, 0))
        soldier.faction = Faction.ashguard.rawValue
        game.mobs.admit(soldier, world)
        let posted = game.mobs.mobs.last
        check(!after.contains { $0.kind.retiredHell } && after.count == 10 && heir?.kind == .brandChampion && heir?.health == 120
              && posted?.kind.hellOwn == true && Soldier.rank(posted?.kind ?? .zombie) == nil,
              "old save: \(old.count) copied creatures -> \(after.map { $0.kind.key }.sorted()) (the blight and the magmastrider gone); the Castellan a Brand Champion at \(heir?.health ?? 0); an Ashguard marksman -> \(posted?.kind.key ?? "-")")
        check(MobKind.piglin.living(inHell: false) == .zombie && MobKind.hoglin.living(inHell: false) == nil && MobKind.zombie.living(inHell: true) == .zombie,
              "outside hell: a boarling becomes a zombie, a tusker is gone, others stay")

        // (a) Natural spawns in both hells: hell's own only.
        func sample(_ g: Game, base: Int, height: Int) -> [String: Int] {
            var seen: [String: Int] = [:]
            for i in 0..<1500 {
                g.mobs.trySpawnEmberdeep(g, base: base, height: height)
                if i % 50 == 49 { for m in g.mobs.mobs { seen[m.kind.key, default: 0] += 1 }; g.mobs.mobs.removeAll() }
            }
            return seen
        }
        let ember = sample(game, base: YOFF, height: 128)
        check(!ember.isEmpty && ember.keys.allSatisfy { own.contains($0) }, "Emberdeep spawns: \(ember.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
        let deep = World(seed: 4242, device: device, save: nil, dim: .deep)
        deep.renderDistance = 5
        let dg = Game(world: deep, save: nil, persistent: false)
        dg.paused = false
        let dat = V3(0.5, Float(DeepGen.hellBase + 50), 0.5)
        dg.player.pos = dat
        _ = deep.loadSync(center: dat, radius: 5)
        dg.mobs.mobs.removeAll()
        let hell = sample(dg, base: DeepGen.hellBase, height: DeepGen.hellHeight)
        check(!hell.isEmpty && hell.keys.allSatisfy { own.contains($0) }, "Deep hell band spawns: \(hell.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")

        print(String(format: "hellcheck: %d failed (%.1f s)", fails, CFAbsoluteTimeGetCurrent() - t0))
        return fails == 0 ? 0 : 1
    }
}
