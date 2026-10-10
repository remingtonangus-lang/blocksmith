import Foundation
import simd

// Task 22 checks (world depth, the Deep, the Ashguard war): part of `--questbugs`; `--questbugs --only deep` runs just these.
enum DeepTests {
    static func run(_ game: Game, _ check: (Bool, String) -> Void) {
        depthZone(game, check)
        floorMigration(check)
        deepWorld(check)
        seam(game, check)
        sites(check)
        war(game, check)
    }

    // The Ashguard fights: on the citadel road (open, levelled) a tank closes in and shells the player, a half-track
    // and a field gun open fire, vehicles brew up when destroyed, the Marshal marks barrages and calls his guard,
    // his death is the victory (the army stands down, the epilogue, the lift home), and Ashguard soldiers keep their
    // colours through a save.
    static func war(_ g: Game, _ check: (Bool, String) -> Void) {
        let home = g.player.pos, homeDim = g.dim.dim, wasSurvival = g.survival
        let wasMobs = g.mobs.mobs
        g.changeDimension(to: .deep, at: V3(0.5, 100, 600.5))
        let w = g.world
        let y = Float((w.gen as? DeepGen)?.floorY(0, 600) ?? DeepGen.floorBase) + 1
        _ = w.loadSync(center: V3(0.5, y, 610.5), radius: 4)
        g.mobs.mobs.removeAll(); w.pendingMobs.removeAll()
        g.survival = true; g.paused = false; g.menu = nil; g.alive = true
        g.player.flying = false
        let stand = V3(0.5, y, 600.5)
        var hurt = 0, maxHit = 0
        func sim(_ secs: Float, until: () -> Bool = { false }) {
            var e: Float = 0
            while e < secs {
                g.health = 20
                g.tick(0.05)
                if g.health < 20 { hurt += 1; maxHit = max(maxHit, 20 - g.health) }
                g.health = 20; g.alive = true
                g.player.pos = stand; g.player.vel = .zero
                w.pendingMobs.removeAll()
                e += 0.05
                if until() { return }
            }
        }
        func unit(_ name: String, dz: Float, dx: Float = 0) -> Mob {
            let m = Mob.structureMob(name, at: V3(0.5 + dx, y, 600.5 + dz))!
            g.mobs.mobs.append(m)
            return m
        }
        let sight = w.canSee(stand + V3(0, 1.6, 0), V3(0.5, y + 2, 634))
        check(sight, "deep war: the citadel road is open (tank to player line of sight)")
        // A tank 34 blocks off: it closes in and fires its main gun and MG.
        let tank = unit("ash_tank^180", dz: 34)
        let z0 = tank.pos.z
        var shells = 0
        sim(25) {
            if g.arms.slugs.contains(where: { $0.kind == .shell && $0.shooter == ObjectIdentifier(tank) }) { shells += 1 }
            return false
        }
        check(tank.aggro && z0 - tank.pos.z > 4 && shells > 0 && hurt > 0 && maxHit < 16,
              "deep war: a Cinder tank engages (moved \(Int(z0 - tank.pos.z)) blocks, \(shells) shell ticks, player hurt \(hurt) ticks, worst hit \(maxHit))")
        // Destroyed by the player: it brews up, drops salvage, the advancement.
        let drops0 = g.drops.items.count
        tank.killedByPlayer = true
        tank.hit(from: stand, damage: tank.health + 400)
        sim(1.5)
        check(!g.mobs.mobs.contains { $0 === tank } && g.drops.items.count > drops0 && g.advancements.contains("adventure/ash_tank"),
              "deep war: a destroyed tank brews up and leaves salvage (Tank Buster)")
        // Half-track and field gun.
        hurt = 0
        let ht = unit("ash_halftrack^180", dz: 30, dx: 3)
        sim(12)
        let htHurt = hurt
        g.mobs.mobs.removeAll { $0 === ht }
        hurt = 0
        let gun = unit("ash_artillery^180", dz: 40)
        var gunShells = 0
        sim(20) {
            if g.arms.slugs.contains(where: { $0.kind == .shell && $0.shooter == ObjectIdentifier(gun) }) { gunShells += 1 }
            return false
        }
        check(htHurt > 0 && gunShells > 0, "deep war: a half-track's MG hits (\(htHurt) ticks) and a field gun lobs shells (\(gunShells))")
        g.mobs.mobs.removeAll()
        // The Marshal: barrages, his guard, and his fall.
        let marshal = unit("ash_marshal^180", dz: 14)
        marshal.soldierBrain.ashTimer = 0                       // his first barrage before he closes within 5 blocks
        var marked = false
        sim(15) { if !g.ashStrikes.isEmpty { marked = true }; return marked }
        marshal.health = marshal.spec.health / 2
        func guardNow() -> [Mob] { g.mobs.mobs.filter { $0.faction == Faction.ashguard.rawValue && Soldier.rank($0.kind) != nil && $0.kind != .ashMarshal } }
        sim(3) { guardNow().count >= 4 }
        let guard_ = guardNow()
        check(marked && guard_.count >= 4 && guard_.allSatisfy { $0.spec.name.hasPrefix("Ashguard") },
              "deep war: the Marshal marks a barrage and calls his guard (\(guard_.count) Ashguard soldiers)")
        marshal.killedByPlayer = true
        marshal.hit(from: stand, damage: marshal.health + 400)
        sim(1)
        check(g.ashVictory && g.advancements.contains("adventure/ash_victory") && g.creditsAsh && g.credits != nil,
              "deep war: the Marshal's fall is the victory (advancement, epilogue)")
        g.credits = nil; g.creditsAsh = false
        g.mobs.mobs.removeAll()
        hurt = 0
        _ = unit("ash_tank^180", dz: 24)
        sim(10)
        check(hurt == 0, "deep war: after the victory the Ashguard stands down (\(hurt) hurt ticks)")
        // Saves: an Ashguard soldier keeps its faction and name.
        let s0 = Mob.structureMob("soldier_recruit@ash^0", at: stand)!
        var d: [String: Float] = [:]
        s0.saveExtra(&d)
        let s1 = Mob(.soldierRecruit, at: stand)
        s1.loadExtra(d)
        check(s1.faction == Faction.ashguard.rawValue && s1.spec.name == "Ashguard Rifleman" && s1.power > 1,
              "deep war: an Ashguard soldier keeps its colours through a save")
        // The lift home in the command bunker.
        g.mobs.mobs.removeAll()
        let l = AshWar.liftAt
        _ = w.loadSync(center: V3(Float(l.x), Float(l.y), Float(l.z)), radius: 2)
        g.player.pos = V3(Float(l.x) + 0.5, Float(l.y + 1), Float(l.z) + 0.5)
        g.ashTick()
        check(g.dim.dim == .overworld, "deep war: the lift in the bunker carries the player home after the victory")
        g.ashVictory = false
        g.mobs.mobs = wasMobs
        g.survival = wasSurvival
        if homeDim != g.dim.dim { g.changeDimension(to: homeDim, at: home) }
        g.player.pos = home
        g.player.vel = .zero
        _ = g.world.loadSync(center: home, radius: 4)        // the lift landed at the world spawn: reload around home
    }

    // The Ashguard's sites: the citadel at 0, 0 with its marks, lamps, loot and garrison; roads along both axes that
    // lead to it from anywhere; patrol camps out in the far vault; loot tables that only name real items.
    static func sites(_ check: (Bool, String) -> Void) {
        let g = DeepGen(seed: 12345)
        guard let sc = g.structures else { check(false, "deep: the Deep has structures"); return }
        let hq = sc.nearest("ash_hq", x: 500, z: -300)
        check(hq.map { $0.anchor.x == 0 && $0.anchor.z == 0 } ?? false, "deep: the Ashguard citadel stands at x 0, z 0")
        var count: [BlockID: Int] = [:], chests = 0
        var mobs: [String] = []
        for cz in -3...2 { for cx in -3...2 {
            var b = g.generate(cx: cx, cz: cz)
            let (ents, ms) = sc.place(into: &b, cx: cx, cz: cz)
            chests += ents.count
            mobs += ms.map { $0.0 }
            for v in b { count[v, default: 0] += 1 }
        } }
        let marks = count[Blocks.id("ash_mark")] ?? 0, lamps = count[Blocks.id("ash_lamp")] ?? 0, walls = count[Blocks.id("ash_concrete")] ?? 0
        check(marks >= 8 && lamps >= 60 && walls > 3000 && chests >= 6,
              "deep: the citadel is built (\(walls) ashcrete, \(marks) ember marks, \(lamps) lamps, \(chests) chests)")
        let tanks = mobs.filter { $0.hasPrefix("ash_tank") }.count, troops = mobs.filter { $0.contains("@ash") }.count
        check(mobs.contains { $0.hasPrefix("ash_marshal") } && tanks >= 4 && troops >= 15,
              "deep: the citadel's garrison: the Marshal, \(tanks) tanks, \(troops) soldiers (\(mobs.count) units)")
        let road = Blocks.id("polished_blackstone")
        let far = [(0, 1500), (-2200, 0), (1, -900)].map { (x, z) -> Bool in
            let b = g.generate(cx: floorDiv(x, CS), cz: floorDiv(z, CS))
            return b[Chunk.index(mod(x, CS), g.floorY(x, z), mod(z, CS))] == road
        }
        check(!far.contains(false), "deep: the axis roads run on through the far vault (\(far))")
        var camps = 0
        for rz in -6...6 { for rx in -6...6 where AshWar.camp(regionX: rx, regionZ: rz) != nil { camps += 1 } }
        check(camps > 60, "deep: patrol camps across the far vault (\(camps) in 13 x 13 regions)")
        var missing: [String] = []
        for t in ["ash_armory", "ash_supply", "ash_fuel", "ash_command"] {
            guard let e = Loot.tables[t] else { missing.append(t); continue }
            for (n, _, _, _) in e.entries where !Items.has(String(n.split(separator: "@")[0])) { missing.append(n) }
        }
        check(missing.isEmpty, "deep: Ashguard loot tables name real items (missing: \(missing))")
    }

    // The Deep's layers: molten core, vault floor, the open vault, crust, hell band, upper crust; no bedrock anywhere;
    // fortresses in the hell band.
    static func deepWorld(_ check: (Bool, String) -> Void) {
        let g = DeepGen(seed: 12345)
        var bedrock = 0, coreOK = true, vaultAir = 0, vaultCols = 0, hellRack = 0, topSolid = true, floorSolid = true
        for (cx, cz) in [(20, 3), (-15, 9), (40, -30), (2, 2)] {
            let b = g.generate(cx: cx, cz: cz)
            for v in b where v == BEDROCK { bedrock += 1 }
            for lz in 0..<CS { for lx in 0..<CS {
                for y in 0...DeepGen.coreTop where b[Chunk.index(lx, y, lz)] != LAVA { coreOK = false }
                let wx = cx * CS + lx, wz = cz * CS + lz
                let f = g.floorY(wx, wz)
                if !g.pillar(wx, wz) && !g.lavaRiver(wx, wz) {
                    vaultCols += 1
                    if (f + 2..<(DeepGen.ceilingBase - 16)).allSatisfy({ b[Chunk.index(lx, $0, lz)] == AIR }) { vaultAir += 1 }
                    if !(DeepGen.coreTop + 1...f).allSatisfy({ Blocks.opaque[Int(b[Chunk.index(lx, $0, lz)])] || b[Chunk.index(lx, $0, lz)] == LAVA }) { floorSolid = false }
                }
                for y in DeepGen.hellBase..<DeepGen.crustTop where b[Chunk.index(lx, y, lz)] == NETHERRACK { hellRack += 1 }
                for y in (CH - 4)..<CH where !Blocks.opaque[Int(b[Chunk.index(lx, y, lz)])] { topSolid = false }
            } }
        }
        check(bedrock == 0, "deep: no bedrock in the Deep (\(bedrock))")
        check(coreOK && floorSolid, "deep: molten core under a solid vault floor")
        check(vaultAir > vaultCols * 9 / 10, "deep: the Ash Vault is open floor to roof (\(vaultAir) of \(vaultCols) columns)")
        check(hellRack > 4 * CSQ * 20, "deep: the hell band holds cinderstone terrain (\(hellRack))")
        check(topSolid, "deep: the top four layers are solid rock (digging down from the surface carries on)")
        let fort = g.structures?.nearest("fortress", x: 0, z: 0)
        check(fort.map { $0.anchor.y > DeepGen.hellBase + 40 && $0.anchor.y < DeepGen.hellBase + 80 } ?? false,
              "deep: fortresses stand in the hell band (nearest at \(fort.map { "\($0.anchor.x) \($0.anchor.y) \($0.anchor.z)" } ?? "none"))")
    }

    // Digging through the surface's bottom layer lands you at the top of the Deep and climbing out of its top layer
    // brings you back; the vault's updrafts catch a long fall.
    static func seam(_ game: Game, _ check: (Bool, String) -> Void) {
        let home = game.player.pos, homeDim = game.dim.dim
        game.player.pos = V3(40.5, 0.3, -20.5)
        game.deepTick(0.05)
        let x = 40, z = -21
        let w = game.world
        check(game.dim.dim == .deep && game.player.pos.y == Float(CH - 3) && w.block(x, CH - 3, z) == AIR && w.block(x, CH - 2, z) == AIR
              && Blocks.opaque[Int(w.block(x, CH - 4, z))], "deep: falling through the surface floor lands in a pocket at the top of the Deep")
        game.player.pos.y = Float(CH - 1)
        game.deepTick(0.05)
        check(game.dim.dim == .overworld && game.player.pos.y == 1 && game.world.block(x, 1, z) == AIR && Blocks.opaque[Int(game.world.block(x, 0, z))],
              "deep: climbing out of the Deep's top comes back up at the surface's floor")
        game.changeDimension(to: .deep, at: V3(300.5, 100, 40.5))
        game.player.onGround = false
        game.player.flying = false
        game.player.vel = V3(0, -20, 0)
        game.deepTick(0.05)
        check(game.effects.has(.slowFalling), "deep: the vault's updraft slows a long fall")
        game.effects.clear()
        if homeDim != game.dim.dim { game.changeDimension(to: homeDim, at: home) }
        game.player.pos = home
    }

    // The surface's lowest 64 layers: no bedrock floor, solid hot rock at the bottom, emberslate taking over with
    // depth, sealed lava pockets that never touch air.
    static func depthZone(_ game: Game, _ check: (Bool, String) -> Void) {
        let gen = WorldGen(seed: 12345)
        var bedrock = 0, openBottom = 0, ember = 0, deepRock = 0, lava = 0, leaky = 0, emberHigh = 0
        for cx in 0..<6 { for cz in 0..<6 {
            let b = gen.generate(cx: cx * 7 - 20, cz: cz * 5 - 12)
            for i in 0..<(CSQ * 5) where b[i] == BEDROCK { bedrock += 1 }
            for i in 0..<(CSQ * 3) where !Blocks.opaque[Int(b[i])] { openBottom += 1 }
            for lz in 1..<(CS - 1) { for lx in 1..<(CS - 1) {
                for y in 3..<(YOFF - 24) {
                    let i = Chunk.index(lx, y, lz), v = b[i]
                    if v == EMBERSLATE { ember += 1 } else if v == DEEPSLATE { deepRock += 1 }
                    if v == LAVA && y > YOFF - 55 {
                        lava += 1
                        for o in [1, -1, CS, -CS, CSQ, -CSQ] where !(Blocks.opaque[Int(b[i + o])] || b[i + o] == LAVA) { leaky += 1 }
                    }
                }
                for y in (YOFF - 8)..<YOFF where b[Chunk.index(lx, y, lz)] == EMBERSLATE { emberHigh += 1 }
            } }
        } }
        check(bedrock == 0, "deep: no bedrock floor in 36 new chunks (\(bedrock) bedrock blocks in layers 0-4)")
        check(openBottom == 0, "deep: the bottom 3 layers are solid (\(openBottom) open)")
        check(ember > deepRock, "deep: emberslate outnumbers deeprock below y -24 (\(ember) vs \(deepRock))")
        check(emberHigh == 0, "deep: no emberslate above y -8 (\(emberHigh))")
        check(lava > 200 && leaky == 0, "deep: sealed lava pockets above the lava sea (\(lava) lava, \(leaky) open faces)")
        // Tougher monsters deep down.
        let p0 = MobManager.depthPower(.overworld, Float(YOFF + 10)), p1 = MobManager.depthPower(.overworld, Float(YOFF - 60))
        let z = Mob(.zombie, at: game.player.pos + V3(0, 0, -3))
        z.equip = nil
        z.power = p1
        let h0 = z.health
        z.hit(from: game.player.pos, damage: 8, knockback: 0)
        check(p0 == 1 && p1 > 1.5 && h0 - z.health == 5, String(format: "deep: depth power 1 at y 10, %.2f at y -60; an 8 hit does %d", p1, h0 - z.health))
    }

    // Saved surface chunks lose the old bedrock floor as they load (other dimensions keep theirs); Remington's real worlds
    // (copied to a temp folder, never touched) still load every saved chunk.
    static func floorMigration(_ check: (Bool, String) -> Void) {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bs-floor-\(UInt32.random(in: 0...UInt32.max))")
        defer { try? fm.removeItem(at: tmp) }
        let sm = SaveManager(dir: tmp)
        var b = [BlockID](repeating: STONE, count: CSQ * CH)
        for i in 0..<(CSQ * 5) { b[i] = BEDROCK }
        b[CSQ * 5] = BEDROCK                                    // layer 5: not the old floor, kept
        sm.saveChunk(ChunkKey(x: 3, z: -2), b)
        let back = sm.loadChunk(ChunkKey(x: 3, z: -2)) ?? []
        let sub = sm.sub("DIM-1")
        sub.saveChunk(ChunkKey(x: 0, z: 0), b)
        let netherBack = sub.loadChunk(ChunkKey(x: 0, z: 0)) ?? []
        check(back.count == CSQ * CH && !back[0..<(CSQ * 5)].contains(BEDROCK) && back[CSQ * 5] == BEDROCK
              && netherBack.count == CSQ * CH && netherBack[0] == BEDROCK,
              "deep: saved surface chunks lose the bedrock floor on load, the Emberdeep keeps its own")
        // The real worlds on this Mac (if any): every chunk file still decodes.
        let worlds = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Blocksmith/Worlds")
        guard let names = try? fm.contentsOfDirectory(atPath: worlds.path), !names.isEmpty else { return }
        for n in names.sorted() {
            let src = worlds.appendingPathComponent(n)
            let copy = tmp.appendingPathComponent("w-\(n)")
            guard (try? fm.copyItem(at: src, to: copy)) != nil else { continue }
            let w = SaveManager(dir: copy)
            let files = (try? fm.contentsOfDirectory(atPath: w.chunkDir.path)) ?? []
            var ok = 0, bad = 0, floorLeft = 0
            for f in files where f.hasPrefix("c.") && f.hasSuffix(".lz") {
                let parts = f.dropFirst(2).dropLast(3).split(separator: ".")
                guard parts.count == 2, let x = Int(parts[0]), let z = Int(parts[1]) else { continue }
                if let c = w.loadChunk(ChunkKey(x: x, z: z)) {
                    ok += 1
                    if c[0..<(CSQ * 5)].contains(BEDROCK) { floorLeft += 1 }
                } else { bad += 1 }
            }
            check(w.loadMeta() != nil && bad == 0 && floorLeft == 0, "deep: saved world '\(n)' loads: \(ok) chunks, \(bad) unreadable, \(floorLeft) with the old floor")
        }
    }
}
