import Foundation
import simd

// The Deep expansion's checks (docs/status/the-deep-expansion.md): part of DeepTests (`--questbugs --only deep` on the
// Mac, `questcheck --deep-only` and every full questcheck run on Linux).
//   hell     the hell band is the whole Emberdeep: 128 tall, five biomes, fortresses, bastions, keeps
//   seal     Sealrock under every column, untouched by every structure, unbreakable but to Sunderite
//   blast    TNT and the main gun's crater leave it; a Sunder Charge cuts a 3x3 shaft through it
//   saves    old Deep chunks get the seal stamped in; a shaft cut with Sunderite stays open
//   ore      Sunderite only in Brimstone Keeps; the processing chain resolves; flux refuses a plain furnace
//   keeps    keeps on three seeds: walls, ore, garrison, reachable from a causeway into the strongroom
//   sky      the vault's sky (haze, ambient, roof left out) and its height
//   army     the Ashguard citadel's garrison against the strongest surface sites
enum DeepExpansionTests {
    static func run(_ game: Game, _ check: (Bool, String) -> Void) {
        let t0 = CFAbsoluteTimeGetCurrent()
        hell(check)
        seal(check)
        processing(check)
        saves(check)
        play(game, check)
        keeps(game, check)
        sky(game, check)
        army(game, check)
        print(String(format: "deep expansion: checks took %.1f s", CFAbsoluteTimeGetCurrent() - t0))
    }

    // The hell band: 176 tall (the gap pass, D1; the Emberdeep is 128), all five ember biomes within reach, fortresses, bastions and keeps on their grids.
    static func hell(_ check: (Bool, String) -> Void) {
        let g = DeepGen(seed: 12345)
        var biomes = Set<String>()
        for z in stride(from: -2000, through: 2000, by: 160) { for x in stride(from: -2000, through: 2000, by: 160) {
            biomes.insert("\(g.ember.biome(x, z))")
        } }
        check(DeepGen.crustTop - DeepGen.hellBase == DeepGen.hellHeight && DeepGen.hellHeight >= 170 && biomes.count == 5,
              "deep hell: the band is \(DeepGen.hellHeight) tall (the Emberdeep's 128) with all five ember biomes within 2,000 blocks (\(biomes.sorted().joined(separator: ", ")))")
        // Much taller open space: the tallest open (air) run in each column, over 16 chunks, against the Emberdeep's; the
        // lower 64 blocks (the lava sea and its shores, where the fortresses and keeps stand) unchanged.
        do {
            let emb = EmberGen(seed: 12345, base: DeepGen.hellBase, cap: EMBERSLATE, structures: false)
            var deepRuns: [Int] = [], embRuns: [Int] = []
            var same = 0, total = 0
            for cz in 0..<4 { for cx in 0..<4 {
                var a = [BlockID](repeating: AIR, count: CSQ * CH), b = a
                g.ember.fill(&a, cx: cx * 7, cz: cz * 7); emb.fill(&b, cx: cx * 7, cz: cz * 7)
                for lz in stride(from: 0, to: CS, by: 3) { for lx in stride(from: 0, to: CS, by: 3) {
                    func run(_ arr: [BlockID], _ h: Int) -> Int {
                        var best = 0, cur = 0
                        for y in 0..<h { if arr[Chunk.index(lx, DeepGen.hellBase + y, lz)] == AIR { cur += 1; best = max(best, cur) } else { cur = 0 } }
                        return best
                    }
                    deepRuns.append(run(a, DeepGen.hellHeight)); embRuns.append(run(b, 128))
                    for y in 0..<60 { total += 1; if a[Chunk.index(lx, DeepGen.hellBase + y, lz)] == b[Chunk.index(lx, DeepGen.hellBase + y, lz)] { same += 1 } }
                } }
            } }
            deepRuns.sort(); embRuns.sort()
            let dMed = deepRuns[deepRuns.count / 2], eMed = embRuns[embRuns.count / 2]
            let dTop = deepRuns[deepRuns.count * 9 / 10], eTop = embRuns[embRuns.count * 9 / 10]
            let kept = Float(same) / Float(max(1, total))
            check(Float(dMed) >= Float(eMed) * 1.5 && dTop >= 100 && dTop > eTop + 40 && kept > 0.97,
                  String(format: "deep hell: open space floor to roof, median %d blocks (the Emberdeep %d), tallest tenth %d+ (%d); the lower 60 blocks %.1f%% the Emberdeep's",
                         dMed, eMed, dTop, eTop, kept * 100))
        }
        guard let sc = g.structures else { check(false, "deep hell: no structures"); return }
        var found: [String: Int] = [:]
        for k in ["fortress", "bastion", "brimstone_keep"] {
            var n = 0
            for z in stride(from: -2400, through: 2400, by: 800) { for x in stride(from: -2400, through: 2400, by: 800) {
                if let s = sc.nearest(k, x: x, z: z, maxRegions: 2), abs(s.anchor.x - x) < 800, abs(s.anchor.z - z) < 800 { n += 1 }
            } }
            found[k] = n
        }
        check(found["fortress", default: 0] >= 20 && found["bastion", default: 0] >= 15 && found["brimstone_keep", default: 0] >= 12,
              "deep hell: fortresses, bastions and keeps across 7 x 7 samples (\(found.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")))")
        // Keeps and bastions keep clear of each other and of fortresses (piece boxes never meet).
        var starts: [StructureStart] = []
        for rz in -3...3 { for rx in -3...3 {
            for t in sc.types where ["fortress", "bastion", "brimstone_keep"].contains(t.name) {
                if let s = sc.start(t, regionX: rx, regionZ: rz) { starts.append(s) }
            }
        } }
        var overlaps: [String] = []
        for i in starts.indices { for j in starts.indices where j > i && starts[i].kind != starts[j].kind {
            let a = starts[i], b = starts[j]
            if a.min.x <= b.max.x && b.min.x <= a.max.x && a.min.z <= b.max.z && b.min.z <= a.max.z {
                overlaps.append("\(a.kind)@\(a.anchor.x),\(a.anchor.z)+\(b.kind)@\(b.anchor.x),\(b.anchor.z)")
            }
        } }
        check(overlaps.isEmpty, "deep hell: no fortress, bastion or keep overlaps among \(starts.count) starts (\(overlaps.prefix(4)))")
    }

    // Sealrock: every column of sampled chunks (structures placed) is sealed in all eight layers.
    static func seal(_ check: (Bool, String) -> Void) {
        let g = DeepGen(seed: 12345)
        guard let sc = g.structures else { return }
        var chunks: [(Int, Int)] = [(0, 0), (20, 3), (-15, 9), (40, -30), (-60, 61)]
        for k in ["fortress", "bastion", "brimstone_keep"] {
            if let s = sc.nearest(k, x: 300, z: -200) { chunks.append((floorDiv(s.anchor.x, CS), floorDiv(s.anchor.z, CS))) }
        }
        var holes = 0, cols = 0
        for (cx, cz) in chunks {
            var b = g.generate(cx: cx, cz: cz)
            _ = sc.place(into: &b, cx: cx, cz: cz)
            for lz in 0..<CS { for lx in 0..<CS {
                cols += 1
                for y in DeepSeal.bottom..<DeepSeal.top where b[Chunk.index(lx, y, lz)] != SEALROCK { holes += 1 }
            } }
        }
        check(holes == 0, "deep seal: \(cols) columns in \(chunks.count) chunks (with a fortress, bastion and keep) sealed in all 8 layers (\(holes) gaps)")
        let pick = ItemStack(Items.id("netherite_pickaxe"), 1), sunder = ItemStack(Items.id(DeepSeal.pickaxe), 1)
        let tDusk = Mining.breakSeconds(SEALROCK, pick, onGround: true, inWater: false)
        let tHand = Mining.breakSeconds(SEALROCK, .empty, onGround: true, inWater: false)
        let tSun = Mining.breakSeconds(SEALROCK, sunder, onGround: true, inWater: false)
        let tOther = Mining.breakSeconds(BEDROCK, sunder, onGround: true, inWater: false)
        check(tDusk.isInfinite && tHand.isInfinite && tOther.isInfinite && tSun > 1 && tSun < 5 && Mining.drops(SEALROCK, sunder).isEmpty,
              String(format: "deep seal: Duskium pickaxe and hand never break it, a Sunderite Pickaxe takes %.2f s (bedrock still unbreakable, no drop)", tSun))
        check(DeepSeal.crosses(210, 185) && DeepSeal.crosses(150, 201) && !DeepSeal.crosses(205, 230) && !DeepSeal.crosses(60, 150),
              "deep seal: a teleport across it is recognised (spiral fruit never crosses)")
    }

    // Sunderite processing: ore drops, flux recipe, blast furnace only, pickaxe and charge recipes.
    static func processing(_ check: (Bool, String) -> Void) {
        let ore = Blocks.id("sunderite_ore")
        let titanium = ItemStack(Items.id("diamond_pickaxe"), 1), iron = ItemStack(Items.id("iron_pickaxe"), 1)
        let drop = Mining.drops(ore, titanium)
        check(drop.count == 1 && Items.key(drop[0].item) == "raw_sunderite" && drop[0].count == 1 && Mining.drops(ore, iron).isEmpty,
              "deep ore: Sunderite Ore drops raw sunderite to a Titanium pickaxe (\(drop.first.map { $0.count } ?? 0)), nothing to iron")
        func craft(_ items: [String]) -> String? {
            var grid = [ItemID](repeating: 0, count: 9)
            for (i, n) in items.enumerated() { grid[i] = Items.id(n) }
            return Recipes.match(grid, 3, 3).map { Items.key($0.result.item) }
        }
        let flux = craft(["raw_sunderite", "raw_sunderite", "blaze_powder"])
        let pickR = craft(["netherite_pickaxe", "sunderite_ingot", "sunderite_ingot", "sunderite_ingot"])
        let chargeR = craft(["sunderite_ingot", "tnt"])
        let fluxID = Items.id("sunderite_flux"), ingot = Items.id("sunderite_ingot")
        let smelted = Recipes.smelt(fluxID).map { Items.key($0) }
        check(flux == "sunderite_flux" && smelted == "sunderite_ingot" && pickR == DeepSeal.pickaxe && chargeR == "sunder_charge"
              && BlockEntity.allowed(ingot, fluxID, in: "blast_furnace") && !BlockEntity.allowed(ingot, fluxID, in: "furnace")
              && Recipes.smelt(Items.id("raw_sunderite")) == nil,
              "deep ore: raw x2 + Cinder Powder -> \(flux ?? "nil"); blast furnace -> \(smelted ?? "nil") (not a plain furnace); pickaxe \(pickR ?? "nil"); charge \(chargeR ?? "nil")")
        let p = ItemStack(Items.id(DeepSeal.pickaxe), 1).def
        check(p.tool == .pickaxe && p.tier == 5 && p.durability > 2031 && Items.def(Items.id("sunder_charge")).maxStack == 16,
              "deep ore: the Sunderite Pickaxe outranks Duskium (tier \(p.tier), \(p.durability) uses)")
        // Never in open rock: 40 chunks far from any keep hold none.
        let g = DeepGen(seed: 777)
        var natural = 0
        for i in 0..<40 {
            let b = g.generate(cx: i * 37 - 700, cz: (i % 7) * 53 - 180)
            for v in b where v == ore { natural += 1 }
        }
        check(natural == 0, "deep ore: no Sunderite in ordinary Deep rock (\(natural) in 40 chunks)")
        var missing: [String] = []
        for t in ["brimstone_keep", "brimstone_strongroom"] {
            guard let e = Loot.tables[t] else { missing.append(t); continue }
            for (n, _, _, _) in e.entries where !Items.has(n) { missing.append(n) }
        }
        check(missing.isEmpty, "deep ore: keep loot tables name real items (missing: \(missing))")
    }

    // Old saves: a Deep chunk saved before the seal gets it; one with a cut shaft keeps the shaft.
    static func saves(_ check: (Bool, String) -> Void) {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bs-seal-\(UInt32.random(in: 0...UInt32.max))")
        defer { try? fm.removeItem(at: tmp) }
        let deep = SaveManager(dir: tmp).sub(Dim.deep.folder!)
        let nether = SaveManager(dir: tmp).sub(Dim.nether.folder!)
        var old = [BlockID](repeating: EMBERSLATE, count: CSQ * CH)
        old[Chunk.index(3, 195, 4)] = AIR
        deep.saveChunk(ChunkKey(x: 1, z: 1), old)
        nether.saveChunk(ChunkKey(x: 1, z: 1), old)
        var cut = [BlockID](repeating: EMBERSLATE, count: CSQ * CH)
        for y in DeepSeal.bottom..<DeepSeal.top { for i in 0..<CSQ { cut[y * CSQ + i] = SEALROCK } }
        for y in DeepSeal.bottom..<DeepSeal.top { cut[Chunk.index(5, y, 5)] = AIR }
        deep.saveChunk(ChunkKey(x: 2, z: 1), cut)
        SaveIO.flush()
        let a = deep.loadChunk(ChunkKey(x: 1, z: 1)) ?? [], b = deep.loadChunk(ChunkKey(x: 2, z: 1)) ?? []
        let n = nether.loadChunk(ChunkKey(x: 1, z: 1)) ?? []
        let sealedA = a.count == CSQ * CH && (DeepSeal.bottom..<DeepSeal.top).allSatisfy { y in (0..<CSQ).allSatisfy { a[y * CSQ + $0] == SEALROCK } }
        let shaftB = b.count == CSQ * CH && (DeepSeal.bottom..<DeepSeal.top).allSatisfy { b[Chunk.index(5, $0, 5)] == AIR }
            && b[Chunk.index(6, 195, 5)] == SEALROCK
        check(sealedA && shaftB && n.count == CSQ * CH && !n.contains(SEALROCK),
              "deep saves: an old Deep chunk is sealed as it loads, a shaft cut with Sunderite stays open, the Emberdeep is untouched")
    }

    // In play: explosions leave the seal, a charge cuts a shaft, the pickaxe mines it through Game.tick's path, the hint.
    static func play(_ g: Game, _ check: (Bool, String) -> Void) {
        let home = g.player.pos, homeDim = g.dim.dim, wasSurvival = g.survival
        let x = 520, z = -340
        g.changeDimension(to: .deep, at: V3(Float(x) + 0.5, Float(DeepSeal.top + 2), Float(z) + 0.5))
        let w = g.world
        _ = w.loadSync(center: V3(Float(x), Float(DeepSeal.top), Float(z)), radius: 2)
        func sealCount(_ r: Int) -> Int {
            var n = 0
            for zz in (z - r)...(z + r) { for xx in (x - r)...(x + r) { for y in DeepSeal.bottom..<DeepSeal.top where w.block(xx, y, zz) == SEALROCK { n += 1 } } }
            return n
        }
        let full = sealCount(4)
        // Clear a pocket above the seal and set off TNT-sized and main-gun-sized blasts on it.
        for y in DeepSeal.top...(DeepSeal.top + 4) { for zz in (z - 3)...(z + 3) { for xx in (x - 3)...(x + 3) { w.setBlock(xx, y, zz, AIR) } } }
        g.survival = false
        Explosion.explode(at: V3(Float(x) + 0.5, Float(DeepSeal.top) + 0.5, Float(z) + 0.5), power: 4, game: g)
        _ = Explosion.crater(at: V3(Float(x) + 0.5, Float(DeepSeal.top) + 0.5, Float(z) + 0.5), radius: 9, game: g)
        let afterBlast = sealCount(4)
        check(full == 81 * 8 && afterBlast == full, "deep seal: TNT and a radius-9 main-gun crater on it leave all \(afterBlast) of \(full) Sealrock blocks")
        // A Sunder Charge pressed onto it, through the use path, then burned down by deepTick.
        g.survival = true; g.alive = true; g.paused = false; g.menu = nil
        g.inventory.held = ItemStack(Items.id("sunder_charge"), 2)
        let used = g.useSunderCharge(on: (hit: IVec3(x, DeepSeal.top - 1, z), normal: IVec3(0, 1, 0)))
        var e: Float = 0
        while e < DeepSeal.chargeFuse + 0.5 { g.health = 20; g.sunderTick(0.05); e += 0.05 }
        let shaft = (DeepSeal.bottom..<DeepSeal.top).allSatisfy { y in (-1...1).allSatisfy { dz in (-1...1).allSatisfy { dx in w.block(x + dx, y, z + dz) == AIR } } }
        let ringLeft = (DeepSeal.bottom..<DeepSeal.top).allSatisfy { w.block(x + 2, $0, z) == SEALROCK && w.block(x, $0, z - 2) == SEALROCK }
        check(used && shaft && ringLeft && g.inventory.held.count == 1 && sealCount(4) == full - 72,
              "deep seal: a Sunder Charge blows a 3x3 shaft through all 8 layers and nothing past it (\(full - sealCount(4)) blocks)")
        // The pickaxe: Game.tick's mining path breaks a block of it; a Duskium pickaxe does nothing and gives the hint.
        let target = IVec3(x + 2, DeepSeal.top - 1, z)
        func mine(_ tool: String, secs: Float) -> Bool {
            g.inventory.held = ItemStack(Items.id(tool), 1)
            g.player.flying = false
            g.player.pos = V3(Float(target.x) + 0.5, Float(target.y + 1), Float(target.z) - 0.8)
            g.player.vel = .zero
            g.player.yaw = .pi; g.player.pitch = -0.9
            var t: Float = 0
            let pm = PadManager.shared
            while t < secs && w.block(target.x, target.y, target.z) == SEALROCK {
                var p = PadSnapshot(); p.rt = 1
                pm.simulated = p
                g.health = 20
                g.tick(0.05)
                g.player.pos = V3(Float(target.x) + 0.5, Float(target.y + 1), Float(target.z) - 0.8); g.player.vel = .zero
                g.player.yaw = .pi; g.player.pitch = -0.9
                t += 0.05
            }
            pm.simulated = nil
            return w.block(target.x, target.y, target.z) != SEALROCK
        }
        let toasts0 = g.sealHintAt
        let duskBroke = mine("netherite_pickaxe", secs: 6)
        let hinted = g.sealHintAt != toasts0
        let sunBroke = mine(DeepSeal.pickaxe, secs: 8)
        check(!duskBroke && hinted && sunBroke, "deep seal: in play a Duskium pickaxe can't break it (hint shown: \(hinted)), a Sunderite Pickaxe does (\(sunBroke))")
        g.survival = wasSurvival
        if homeDim != g.dim.dim { g.changeDimension(to: homeDim, at: home) }
        g.player.pos = home
        g.player.vel = .zero
        _ = g.world.loadSync(center: home, radius: 4)
    }

    // Brimstone Keeps on three seeds: the nearest to the origin is found, built (walls, ore, chests, garrison) and
    // walkable from the end of a causeway down into the strongroom.
    static func keeps(_ g: Game, _ check: (Bool, String) -> Void) {
        let brick = Blocks.id("nether_bricks"), ore = Blocks.id("sunderite_ore")
        for seed in [UInt64(12345), 777, 424242] {
            let w = World(seed: seed, device: g.world.device, save: nil, dim: .deep)
            guard let sc = w.gen.structures, let s = sc.nearest("brimstone_keep", x: 0, z: 0, maxRegions: 3) else {
                check(false, "deep keeps \(seed): no Brimstone Keep within 3 regions"); continue
            }
            let ox = (s.min.x + s.max.x) / 2, oz = (s.min.z + s.max.z) / 2
            let f = DeepGen.hellBase + BrimstoneKeep.floorUp
            let dist = Int(simd_length(V2(Float(ox), Float(oz))))
            var b: [BlockID: Int] = [:], chests = 0
            var mobs: [String] = []
            var strongOre = 0
            for cz in floorDiv(s.min.z, CS)...floorDiv(s.max.z, CS) { for cx in floorDiv(s.min.x, CS)...floorDiv(s.max.x, CS) {
                var blocks = w.gen.generate(cx: cx, cz: cz)
                let (ents, ms) = sc.place(into: &blocks, cx: cx, cz: cz)
                // Only the keep's own (its causeways reach far enough to touch other sites' chunks).
                let near = { (x: Float, z: Float) in abs(x - Float(ox)) < Float(BrimstoneKeep.half + 4) && abs(z - Float(oz)) < Float(BrimstoneKeep.half + 4) }
                chests += ents.filter { $0.1.kind == .chest && near(Float($0.0.x), Float($0.0.z)) }.count
                mobs += ms.filter { near($0.1.x, $0.1.z) }.map { $0.0 }
                for lz in 0..<CS { for lx in 0..<CS { for y in (f - 12)...(f + 24) {
                    let v = blocks[Chunk.index(lx, y, lz)]
                    b[v, default: 0] += 1
                    if v == ore && abs(cx * CS + lx - ox) <= 6 && abs(cz * CS + lz - oz) <= 6 && y < f { strongOre += 1 }
                } } }
            } }
            let monsters = mobs.filter { $0.hasSuffix("@deep") }.count, ash = mobs.filter { $0.contains("@ash") }.count
            check(b[brick, default: 0] > 2500 && strongOre >= BrimstoneKeep.oreMin && chests >= 3 && monsters >= 12 && ash >= 6,
                  "deep keeps \(seed): keep \(dist) blocks from the origin: \(b[brick, default: 0]) ember brick, \(strongOre) Sunderite Ore in the strongroom, \(chests) chests, garrison \(monsters) monsters + \(ash) Ashguard")
            // Walk in from the hell band around it: from open ground 70-90 blocks out (a ring of 48 columns, the first
            // standing cell going down from over the keep's floor), on foot with jumps and ladders, into the strongroom.
            _ = w.loadSync(center: V3(Float(ox), Float(f), Float(oz)), radius: 6)
            var starts: [IVec3] = []
            for i in 0..<48 {
                let a = Float(i) / 48 * 2 * .pi, rr: Float = i % 2 == 0 ? 72 : 88
                let x = ox + Int(cosf(a) * rr), z = oz + Int(sinf(a) * rr)
                for y in stride(from: f + 20, through: DeepGen.hellBase + 30, by: -1) where StructCheck.feet(w, x, y, z) != nil {
                    starts.append(IVec3(x, y, z)); break
                }
            }
            let walk = StructCheck.walkOrder(w, seeds: starts, lo: IVec3(ox - 95, f - 14, oz - 95),
                                             hi: IVec3(ox + 95, f + 60, oz + 95), jump: true, limit: 1_500_000).seen
            var inStrong = 0, upstairs = 0
            for dz in -4...4 { for dx in -4...4 {
                if walk.contains(StructCheck.key(ox + dx, f - 9, oz + dz)) { inStrong += 1 }
                if walk.contains(StructCheck.key(ox + dx, f + 10, oz + dz)) { upstairs += 1 }
            } }
            check(inStrong > 20 && upstairs > 20,
                  "deep keeps \(seed): walking in from the ground around it (\(starts.count) starts 72-88 blocks out) reaches \(inStrong) strongroom cells and \(upstairs) on the keep's upper floor")
        }
    }

    // The vault's own sky: the haze replaces the Deep's fog only down in the vault, brighter ambient, roof left to the
    // sky, and the vault is ~135 blocks floor to roof.
    static func sky(_ g: Game, _ check: (Bool, String) -> Void) {
        let home = g.player.pos, homeDim = g.dim.dim
        g.changeDimension(to: .deep, at: V3(300.5, Float(DeepGen.floorBase + 4), 40.5))
        let vault = (g.skyColor, g.dimAmbient, g.inVaultSky, g.skyZenith)
        g.player.pos.y = Float(DeepGen.hellBase + 60)
        let hell = (g.skyColor, g.dimAmbient, g.inVaultSky)
        g.player.pos.y = Float(DeepGen.ceilingBase + 20)
        let crust = g.inVaultSky
        check(vault.2 && !hell.2 && !crust && vault.0 == AshSky.haze && hell.0 != AshSky.haze && vault.1 > hell.1 + 0.1
              && simd_length(vault.3) < simd_length(vault.0),
              "deep sky: under the vault's sky the haze (\(vault.0)) and ambient \(vault.1) (hell band \(hell.1)), a darker zenith; not in the hell band or crust")
        let dg = DeepGen(seed: 12345)
        var heights: [Int] = []
        for i in 0..<40 { let x = i * 97 - 1900, z = i * 61 - 1200; heights.append(dg.ceilingY(x, z) - dg.floorY(x, z)) }
        heights.sort()
        check(heights[0] > 110 && heights[20] > 125 && heights.last! < DeepSeal.bottom - DeepGen.floorBase - 4
              && AshSky.cutSection * 16 < dg.ceilingY(0, 0) - 6 && Float(AshSky.cutSection * 16) > AshSky.eyeBelow,
              "deep sky: the vault is \(heights[0])-\(heights.last!) blocks floor to roof (median \(heights[20])); sky from y \(AshSky.cutSection * 16), under the roof")
        if homeDim != g.dim.dim { g.changeDimension(to: homeDim, at: home) }
        g.player.pos = home
    }

    // Garrison strength: health x power x armour over every unit a site places, for the Ashguard citadel, the nearest
    // Capital citadel and Boreal Station to spawn, and a Brimstone Keep.
    static func strength(_ names: [String]) -> (eff: Float, units: Int, soldier: Float) {
        var eff: Float = 0, units = 0, best: Float = 0
        for n in names {
            guard let m = Mob.structureMob(n, at: V3(0, 100, 0)) else { continue }
            let (armor, tough) = m.steelholdArmor
            let a = Float(armor), dmg: Float = 8
            let red = min(20, max(a / 5, a - dmg / (2 + tough / 4))) / 25
            let e = Float(m.spec.health) * max(1, m.power) / max(0.2, 1 - red)
            eff += e; units += 1
            if Soldier.rank(m.kind) == 0 { best = max(best, e) }      // a basic rifleman
        }
        return (eff, units, best)
    }

    static func garrison(_ gen: TerrainGenerator, _ s: StructureStart) -> [String] {
        guard let sc = gen.structures else { return [] }
        var out: [String] = []
        for cz in floorDiv(s.min.z, CS)...floorDiv(s.max.z, CS) { for cx in floorDiv(s.min.x, CS)...floorDiv(s.max.x, CS) {
            var b = gen.generate(cx: cx, cz: cz)
            let (_, ms) = sc.place(into: &b, cx: cx, cz: cz)
            out += ms.filter { s.contains(Int(floor($0.1.x)), Int(floor($0.1.y)), Int(floor($0.1.z))) }.map { $0.0 }
        } }
        return out
    }

    static func army(_ g: Game, _ check: (Bool, String) -> Void) {
        let seed: UInt64 = 12345
        let dg = DeepGen(seed: seed), wg = WorldGen(seed: seed)
        guard let hq = dg.structures?.nearest("ash_hq", x: 0, z: 0) else { check(false, "deep army: no citadel"); return }
        let ash = strength(garrison(dg, hq))
        var surface: [(String, (eff: Float, units: Int, soldier: Float))] = []
        let o = Game.spawnOrigin(seed: seed)
        if let c = wg.structures?.nearest("military_base", x: o.0, z: o.2, maxRegions: 6) { surface.append(("Capital citadel", strength(garrison(wg, c)))) }
        if let b = wg.structures?.nearest(BorealStation.kind, x: o.0, z: o.2, maxRegions: 6) { surface.append(("Boreal Station", strength(garrison(wg, b)))) }
        let strongest = surface.map { $0.1.eff }.max() ?? 0
        let bestSoldier = surface.map { $0.1.soldier }.max() ?? 0
        let lines = surface.map { "\($0.0) \(Int($0.1.eff)) (\($0.1.units) units)" }.joined(separator: ", ")
        check(surface.count == 2 && ash.eff >= 2 * strongest && ash.soldier > bestSoldier * 1.3,
              "deep army: Ashguard citadel garrison \(Int(ash.eff)) (\(ash.units) units) vs \(lines); a rifleman \(Int(ash.soldier)) vs \(Int(bestSoldier))")
        if let k = dg.structures?.nearest("brimstone_keep", x: 0, z: 0) {
            let ks = strength(garrison(dg, k))
            print("deep army: a Brimstone Keep's garrison \(Int(ks.eff)) (\(ks.units) units)")
        }
    }
}
