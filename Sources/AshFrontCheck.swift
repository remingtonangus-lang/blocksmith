import Foundation
import simd

// P326's quick check (questcheck --ashfront, Mac --ashfront): the Ash Vault as a battlefield of the last war.
// Ground: no lava on the floor, no hell rock on it, living ground, woods, shell holes, no man's land; the grey sky; the
// set pieces and the fallen; the flak batteries and the heavy-water plant; the period's weapon names; old saves' ground
// migrating, and the new things keeping off it.
enum AshFrontCheck {
    static func run(_ game: Game, _ check: (Bool, String) -> Void) {
        let g = DeepGen(seed: 12345), vg = g.ground
        let lava = LAVA, hell: Set<BlockID> = [Blocks.id("blackstone"), Blocks.id("basalt"), Blocks.id("soul_soil"), Blocks.id("magma_block")]
        let living: Set<BlockID> = [vg.grass, vg.podzol, vg.mud, vg.coarse, vg.rooted, vg.moss]
        let logs: Set<BlockID> = [Blocks.id("dark_oak_log"), Blocks.id("spruce_log"), Blocks.id("oak_log")]
        // (a) The floor over a spread of the vault: no lava above the core, no hell rock on top, living ground, woods.
        var floorLava = 0, hellTops = 0, livingTops = 0, cols = 0, logCells = 0, plants = 0, holes = 0, creekCols = 0
        var chunks: [(Int, Int)] = []
        for i in 0..<36 { chunks.append((floorDiv(i * 211 - 3700, CS), floorDiv(i * 157 - 2900, CS))) }
        for (cx, cz) in chunks {
            let b = g.generate(cx: cx, cz: cz)
            for lz in 0..<CS { for lx in 0..<CS {
                let wx = cx * CS + lx, wz = cz * CS + lz
                if g.pillar(wx, wz) { continue }
                let c = g.ceilingY(wx, wz)
                for y in (DeepGen.coreTop + 1)..<c where b[Chunk.index(lx, y, lz)] == lava { floorLava += 1 }
                let f = vg.top(wx, wz)
                if AshWar.clearance(wx, wz) <= 6 { continue }        // (roads, rails, the lines' trenches, sites)
                cols += 1
                let t = b[Chunk.index(lx, f, lz)]
                if hell.contains(t) { hellTops += 1 }
                if living.contains(t) { livingTops += 1 }
                if vg.crater(wx, wz) > 1 { holes += 1 }
                if vg.creek(wx, wz) { creekCols += 1 }
                let above = b[Chunk.index(lx, f + 1, lz)]
                if above != AIR && Blocks.isPlant(above) { plants += 1 }
                for y in (f + 1)...(f + 14) where logs.contains(b[Chunk.index(lx, y, lz)]) { logCells += 1 }
            } }
        }
        check(floorLava == 0 && hellTops == 0 && livingTops * 100 > cols * 95,
              "ashfront: no lava on the vault floor (\(floorLava) cells), no hell rock on top (\(hellTops)); \(livingTops) of \(cols) columns grass, podzol, moss, mud or dirt")
        check(logCells > 400 && plants * 100 > cols * 8 && creekCols > 0,
              "ashfront: woods and growth: \(logCells) log cells, plants on \(plants) columns, \(creekCols) mud-creek columns")
        // No man's land: shell holes thick outside the Ember Line, a few elsewhere.
        var nml = 0, nmlHoles = 0, nmlMud = 0
        for a in stride(from: 0, to: 360, by: 9) {
            let r: Float = 470, ang = Float(a) * .pi / 180
            let x = Int(sinf(ang) * r), z = Int(-cosf(ang) * r)
            for dz in stride(from: -12, through: 12, by: 3) { for dx in stride(from: -12, through: 12, by: 3) {
                guard AshWar.clearance(x + dx, z + dz) > 12 else { continue }
                nml += 1
                if vg.crater(x + dx, z + dz) > 0.3 { nmlHoles += 1 }
                let s = vg.surface(x + dx, z + dz, crater: vg.crater(x + dx, z + dz), creek: false, wood: 0, nml: vg.noMansLand(x + dx, z + dz))
                if s == vg.mud || s == vg.coarse || s == vg.rooted { nmlMud += 1 }
            } }
        }
        check(nml > 200 && nmlHoles * 100 > nml * 15 && nmlMud * 100 > nml * 70 && holes > 0,
              "ashfront: no man's land: \(nmlHoles) of \(nml) spots in shell holes, \(nmlMud) mud or churned dirt; \(holes) shell-hole columns elsewhere")
        // The sky: grey, not red; the fog close.
        let hz = AshSky.haze
        check(max(hz.x, hz.y, hz.z) - min(hz.x, hz.y, hz.z) < 0.04 && hz.y > 0.35 && AshSky.fogEnd <= 110 && AshSky.sunTint.x - AshSky.sunTint.z < 0.1,
              "ashfront: a grey overcast sky (haze \(hz), fog \(AshSky.fogStart)-\(AshSky.fogEnd), sun tint \(AshSky.sunTint))")
        // (b) Set pieces: every kind within reach of the citadel, built with their wrecks; the fallen at them.
        let scenes = AshFront.scenes(-1600, -1600, 1600, 1600, pad: 0, ground: vg)
        var kinds = [Int](repeating: 0, count: 5)
        for s in scenes { kinds[s.kind] += 1 }
        check(!kinds.contains(0) && scenes.count > 80, "ashfront: \(scenes.count) set pieces round the citadel: " + (0..<5).map { "\(kinds[$0]) \(AshScene.names[$0])" }.joined(separator: ", "))
        var built: [String] = []
        let wreck: Set<BlockID> = [AshFront.hull, AshFront.olive, AshFront.alu]
        for k in 0..<5 {
            guard let s = scenes.first(where: { $0.kind == k }), let sc = g.structures else { continue }
            var n = 0, wall = 0
            for cz in floorDiv(s.z - s.r - 2, CS)...floorDiv(s.z + s.r + 2, CS) { for cx in floorDiv(s.x - s.r - 2, CS)...floorDiv(s.x + s.r + 2, CS) {
                var b = g.generate(cx: cx, cz: cz)
                _ = sc.place(into: &b, cx: cx, cz: cz)
                for v in b { if wreck.contains(v) { n += 1 } else if v == Blocks.id("cobblestone") || v == Blocks.id("mossy_cobblestone") { wall += 1 } }
            } }
            // P346: the bomber, fighter and tanks are models over a hidden solid core (AshWrecks).
            let models = AshWrecks.spots(s, vg)
            let parts = models.map { sp -> Int in let m = Mob(.ashBehemoth, at: sp.pos); m.wreck = Int8(sp.kind); m.variant = sp.seed; return ashWreckParts(m).count }
            built.append("\(AshScene.names[k]) at \(s.x) \(s.z): \(n) wreck blocks, \(models.count) wreck models (\(parts.map(String.init).joined(separator: "/")) parts)\(k == 4 ? ", \(wall) wall" : ""), \(AshFront.fallen(s).count) fallen")
            let ok: Bool
            switch k {
            case 0: ok = n >= 13 && models.count == 1 && parts[0] > 60
            case 1: ok = models.count == 1 && parts[0] > 20
            case 2: ok = n >= 6 && models.count == 3 && parts.allSatisfy { $0 > 50 }
            case 3: ok = n > 60
            default: ok = wall > 20 && AshFront.fallen(s).count >= 8
            }
            check(ok, "ashfront: " + built.last!)
        }
        // The fallen as the player sees them: at the nearest broken wall, lying in olive drab.
        if let s = scenes.filter({ $0.kind == 4 }).min(by: { abs($0.x) + abs($0.z) < abs($1.x) + abs($1.z) }) {
            let home = game.player.pos, homeDim = game.dim.dim
            game.changeDimension(to: .deep, at: V3(Float(s.x) + 0.5, Float(vg.top(s.x, s.z) + 2), Float(s.z) + 0.5))
            _ = game.world.loadSync(center: game.player.pos, radius: 2)
            AshFallen.refresh(game)
            let ms = AshFallen.mobs
            let l = ms.first.map { Livery.of($0, rank: 1, seed: 3) }
            let olive = l.map { $0.cloth.y > $0.cloth.z + 0.06 && $0.cloth.x < 0.45 } ?? false
            let lyingOK = ms.allSatisfy { $0.fallen && $0.lying && fallenAlliedParts($0).count > 25 && $0.deathT >= MobAnim.deathTime && abs($0.pos.y - Float(vg.top(Int(floor($0.pos.x)), Int(floor($0.pos.z))) + 1)) < 2.5 }
            check(ms.count >= 8 && olive && lyingOK, "ashfront: \(ms.count) fallen Allied soldiers at the wall by \(s.x) \(s.z), olive drab \(olive), lying on the ground \(lyingOK)")
            game.changeDimension(to: homeDim, at: home)
            game.player.pos = home
            AshFallen.refresh(game)
            check(AshFallen.mobs.isEmpty, "ashfront: the fallen are gone when the player leaves the vault")
        }
        // (c) The new bases: built with their guns, cells and crews.
        for s in AshWar.frontSites {
            guard let sc = g.structures else { break }
            var units: [String] = [], cnt: [BlockID: Int] = [:], chests = 0
            for cz in floorDiv(s.z - s.r, CS)...floorDiv(s.z + s.r, CS) { for cx in floorDiv(s.x - s.r, CS)...floorDiv(s.x + s.r, CS) {
                var b = g.generate(cx: cx, cz: cz)
                let (e, m) = sc.place(into: &b, cx: cx, cz: cz)
                units += m.map { $0.0 }; chests += e.count
                for v in b { cnt[v, default: 0] += 1 }
            } }
            let guns = units.filter { $0.hasPrefix("ash_artillery") }.count, men = units.filter { $0.hasPrefix("soldier_") }.count
            if s.kind == "prisoncamp" {
                let held = units.filter { $0.contains(":prisoner") }.count, sitting = units.filter { $0.contains(":prisoner_sit") }.count
                let guards = units.filter { $0.hasPrefix("soldier_") && $0.hasSuffix("@ash") || $0.contains("@ash^") }.count
                let wire = cnt[Blocks.has("ash_wire") ? Blocks.id("ash_wire") : Blocks.id("iron_bars")] ?? 0
                check(held >= 20 && sitting >= 8 && guards >= 10 && wire > 300 && chests >= 2,
                      "ashfront: the prison camp at \(s.x) \(s.z): \(held) prisoners (\(sitting) sitting), \(guards) guards, \(wire) wire, \(chests) chests")
                continue
            }
            if s.kind == "flak" {
                check(guns == 6 && men >= 8 && chests >= 3, "ashfront: the flak battery at \(s.x) \(s.z): \(guns) guns, \(men) men, \(chests) chests")
            } else {
                let iron = cnt[Blocks.id("iron_block")] ?? 0, copper = cnt[Blocks.id("copper_block")] ?? 0, glass = cnt[Blocks.id("glass")] ?? 0
                check(iron > 100 && copper > 40 && glass > 40 && men >= 8 && chests >= 2,
                      "ashfront: the heavy-water plant at \(s.x) \(s.z): \(iron) iron (penstocks, cells), \(copper) copper, \(glass) glass, \(men) men, \(chests) chests")
            }
        }
        prisonCamp(game, check)
        // The period's weapon names; the MP40 back with its own model; who carries it.
        let names = [Guns.kessel, Guns.hagel, Guns.sturmwind, Guns.faust].map { Guns.all[$0].name }
        let mp = AshArms.model(Guns.hagel), stg = AshArms.model(Guns.sturmwind)
        var officers = 0
        for _ in 0..<4 { if let m = Mob.structureMob("soldier_officer@ash", at: V3(0, 100, 0)), m.variant == Guns.hagel { officers += 1 } }
        check(names == ["Kessel Bolt Rifle", "Hagel Machine Pistol", "Sturmwind Carbine", "Faustrohr"] && Items.has("gun_hagel") && !Guns.isRetired(Guns.hagel)
              && mp.parts.count >= 14 && mp.parts.count != stg.parts.count && officers == 4 && MobKind.ashTank.spec.name == "Cinder Tank",
              "ashfront: the arms by name \(names), the Hagel an item with its own \(mp.parts.count)-part model, carried by \(officers)/4 officers; the \(MobKind.ashTank.spec.name)")
        // (e) An old save's vault chunk: the old ground (ash plain, lava river, black pad) takes the new materials.
        migration(g, check)
        // ...and the new things keep off ground a save had: the flak site, scenes and shell holes near guarded chunks.
        let gg = DeepGen(seed: 12345)
        let fs = AshWar.frontSites[0]
        var guardSet = Set<Int64>()
        for dz in -2...2 { for dx in -2...2 { guardSet.insert(StructureCache.key(floorDiv(fs.x, CS) + dx, floorDiv(fs.z, CS) + dz)) } }
        let s0 = scenes[0]
        for dz in -1...1 { for dx in -1...1 { guardSet.insert(StructureCache.key(floorDiv(s0.x, CS) + dx, floorDiv(s0.z, CS) + dz)) } }
        gg.ground.guardSet.chunks = guardSet
        AshWar.setFront(gg.ground.guardSet)
        let off = AshWar.frontOff
        let sceneGone = AshFront.scenes(s0.x - 1, s0.z - 1, s0.x + 1, s0.z + 1, pad: 0, ground: gg.ground).isEmpty
        var holesNear = 0
        for dz in -8...8 { for dx in -8...8 where gg.ground.crater(s0.x + dx * 2, s0.z + dz * 2) > 0 { holesNear += 1 } }
        AshWar.setFront(DeepGuard())
        check(off == [true, false, false, false] && sceneGone && holesNear == 0,
              "ashfront: ground a save already had keeps clear of the new: front sites off \(off), scene gone \(sceneGone), \(holesNear) shell holes there")
    }

    // P347: the prison camp's prisoners (unharmed, in no faction, their own figure) and its liberation: with no guard
    // left inside the wire and the player there, the camp is free; they rise and walk out through the gate.
    static func prisonCamp(_ game: Game, _ check: (Bool, String) -> Void) {
        let s = Prisoners.site
        guard let pr = Mob.structureMob("soldier_crew:prisoner_sit^90", at: V3(Float(s.x) - 22.2, Float(AshWar.ground + 1), Float(s.z) - 12.5)),
              let guardM = Mob.structureMob("soldier_trooper@ash", at: V3(Float(s.x) + 10.5, Float(AshWar.ground + 1), Float(s.z) + 2.5)) else {
            check(false, "ashfront: the prison camp's mobs"); return
        }
        let hp = pr.health
        pr.hit(from: pr.pos + V3(1, 0, 0), damage: 40)
        let model = prisonerParts(pr, swing: 0).count
        check(pr.posse == Prisoners.posse && pr.sitting && pr.factionValue == .none && pr.health == hp && pr.health > 0 && model >= 18,
              "ashfront: a prisoner: unharmed by a blow (\(pr.health)/\(hp)), no side (\(pr.factionValue)), sitting \(pr.sitting), his own \(model)-part figure")
        let home = game.player.pos, homeDim = game.dim.dim, saved = TownLaw.state.vaultObj
        game.changeDimension(to: .deep, at: V3(Float(s.x) + 0.5, Float(AshWar.ground + 1), Float(s.z) + 0.5))
        _ = game.world.loadSync(center: game.player.pos, radius: 3)
        game.mobs.mobs.removeAll { $0.posse == Prisoners.posse || $0.faction == Faction.ashguard.rawValue }
        game.mobs.mobs += [pr, guardM]
        for _ in 0..<5 { Prisoners.tick(game) }
        let heldWhileGuarded = !Prisoners.liberated
        guardM.health = 0
        game.mobs.mobs.removeAll { $0 === guardM }
        for _ in 0..<4 { Prisoners.tick(game) }
        let freed = Prisoners.liberated
        let start = pr.pos
        for _ in 0..<(20 * 20) { pr.update(0.05, game: game) }
        let walked = simd_length(V2(pr.pos.x - start.x, pr.pos.z - start.z))
        let (gate, _) = Prisoners.exits()
        check(heldWhileGuarded && freed && !pr.sitting && walked > 8,
              "ashfront: the camp stays held while a guard lives (\(heldWhileGuarded)); with none it is free (\(freed)); the prisoner rose and walked \(walked) blocks toward the gate (\(Int(simd_length(V2(pr.pos.x - gate.x, pr.pos.z - gate.z)))) left)")
        game.mobs.mobs.removeAll { $0 === pr }
        TownLaw.state.vaultObj = saved
        game.changeDimension(to: homeDim, at: home)
        game.player.pos = home
    }

    static func migration(_ g: DeepGen, _ check: (Bool, String) -> Void) {
        let vg = g.ground
        let blackstone = Blocks.id("blackstone"), basalt = Blocks.id("basalt"), soulSoil = Blocks.id("soul_soil"), magma = Blocks.id("magma_block")
        // A chunk with an old river through it (searching out from the far vault), and a camp's pad.
        func oldChunk(_ cx: Int, _ cz: Int) -> [BlockID] {
            var b = [BlockID](repeating: AIR, count: CSQ * CH)
            for lz in 0..<CS { for lx in 0..<CS {
                let wx = cx * CS + lx, wz = cz * CS + lz
                let pad = AshWar.padSite(wx, wz) != nil, road = AshWar.isRoad(wx, wz)
                let river = !pad && !road && vg.creek(wx, wz, front: false)
                let f = pad ? AshWar.ground : DeepGen.floorBase + Int(vg.base(wx, wz, front: false).rounded()) - (river ? 2 : 0)
                for y in 0...f { b[Chunk.index(lx, y, lz)] = y <= DeepGen.coreTop ? LAVA : EMBERSLATE }
                let m = vg.matN.noise2(Float(wx) / 19, Float(wz) / 19)
                b[Chunk.index(lx, f, lz)] = road ? vg.road : river ? magma : (m > 0.35 ? basalt : (m < -0.45 ? soulSoil : blackstone))
                if pad { b[Chunk.index(lx, f, lz)] = blackstone }
                if river { b[Chunk.index(lx, f + 1, lz)] = LAVA }
                if vg.pillar(wx, wz, front: false) { for y in f...(DeepGen.floorBase + 40) { b[Chunk.index(lx, y, lz)] = y % 7 == 0 ? magma : basalt } }
            } }
            return b
        }
        var riverChunk: (Int, Int)? = nil
        search: for r in 0..<60 { for k in 0..<8 {
            let cx = 70 + r * 3 + k, cz = -40 + r * 2
            for lz in stride(from: 0, to: CS, by: 4) { for lx in stride(from: 0, to: CS, by: 4) where vg.creek(cx * CS + lx, cz * CS + lz, front: false) && !vg.pillar(cx * CS + lx, cz * CS + lz, front: false) {
                riverChunk = (cx, cz); break search
            } }
        } }
        var camp: AshSite? = nil
        for rz in 2...8 { for rx in 2...8 where camp == nil { camp = AshWar.camp(regionX: rx, regionZ: rz) } }
        var results: [String] = []
        for (label, key) in [("river", riverChunk), ("camp", camp.map { (floorDiv($0.x, CS), floorDiv($0.z, CS)) })] {
            guard let (cx, cz) = key else { check(false, "ashfront: found an old \(label) chunk to migrate"); continue }
            for fieldWorld in [false, true] {
                var b = oldChunk(cx, cz)
                var f: FieldData? = nil
                if fieldWorld {
                    // The old chunk as a field world saved it: the ground in the field, the lava in the built layer.
                    var fd = [Int8](repeating: FieldTerrain.outside, count: CSQ * CH), fm = [UInt8](repeating: 0, count: CSQ * CH)
                    for i in 0..<b.count where FieldMat.index[Int(b[i])] != 0 { fd[i] = FieldTerrain.inside; fm[i] = FieldMat.index[Int(b[i])]; b[i] = AIR }
                    f = FieldData(fd: fd, fm: fm)
                }
                vg.migrate(&b, &f, cx: cx, cz: cz)
                var lavaLeft = 0, oldTops = 0, newTops = 0, tops = 0, grassTufts = 0, hotPillar = 0
                for lz in 0..<CS { for lx in 0..<CS {
                    let wx = cx * CS + lx, wz = cz * CS + lz
                    for y in (DeepGen.coreTop + 1)..<(DeepGen.floorBase + 18) where b[Chunk.index(lx, y, lz)] == LAVA { lavaLeft += 1 }
                    func cell(_ y: Int) -> BlockID {
                        let i = Chunk.index(lx, y, lz)
                        if b[i] != AIR || f == nil { return b[i] }
                        return f!.fd[i] > 0 ? FieldMat.blocks[Int(f!.fm[i])] : AIR
                    }
                    if vg.pillar(wx, wz, front: false) {
                        for y in (DeepGen.coreTop + 1)...(DeepGen.floorBase + 40) where [basalt, magma].contains(cell(y)) { hotPillar += 1 }
                        continue
                    }
                    if AshWar.isRoad(wx, wz) { continue }
                    var y = DeepGen.floorBase + 18
                    while y > DeepGen.coreTop && !Blocks.opaque[Int(cell(y))] { if Blocks.isPlant(cell(y)) { grassTufts += 1 }; y -= 1 }
                    tops += 1
                    let t = cell(y)
                    if [blackstone, basalt, soulSoil, magma].contains(t) { oldTops += 1 }
                    if [vg.grass, vg.podzol, vg.mud, vg.coarse, vg.rooted, vg.moss, AshWar.padDirt, AshWar.padMud].contains(t) { newTops += 1 }
                } }
                results.append("\(label) \(fieldWorld ? "field" : "block"): \(newTops)/\(tops) new tops, \(oldTops) old, \(lavaLeft) lava, \(grassTufts) tufts, \(hotPillar) old pillar cells")
                check(lavaLeft == 0 && oldTops == 0 && hotPillar == 0 && newTops * 10 >= tops * 9,
                      "ashfront: an old save's \(label) chunk \(cx) \(cz) migrates (\(fieldWorld ? "field" : "block") world): \(results.last!)")
            }
        }
    }
}
