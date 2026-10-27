import Foundation
import simd

// Checks for the Oct 12 AM Quest playtest items (docs/roadmap/backlog.md P68-P97). Part of every questcheck run;
// `questcheck --p12-only` stops after them.
enum PlaytestOct12Tests {
    static func run(_ game: Game, _ check: (Bool, String) -> Void) {
        gunOpensDoors(game, check)
        horseBond(game, check)
        tabHighlight(game, check)
        hotbarHints(game, check)
        corpseTint(game, check)
        cactusFlower(check)
        turtleBeaches(game, check)
        baseRarity(check)
        localOutlaw(game, check)
        streetWidth(game, check)
        mapClickPin(game, check)
        greywallApart(check)
        polygonOption(game, check)
        leafSound(check)
        campLife(game, check)
        clearIce(check)
        bigHunters(game, check)
        baseBanks(check)
        greywallKit(check)
        readOrders(game, check)
        navalGuns(game, check)
        bombard(game, check)
        chaseView(game, check)
        trains(check)
        wrecks(game, check)
        PlaytestOct12NoonTests.run(game, check)
    }

    // P88 (09:37): bounty hunters are a big deal: an outlaw draws four or more, two with six-irons, twice as tough; they
    // show on the map; the music turns tense while they ride in.
    // P91: a base's levelled site banks down into the land round it (StructWriter.berm): one chunk of grass ground at
    // y 60 with a site of floor 70 ending just west of it; column by column the bank falls one a block to the ground,
    // a built block at the bank's top is left alone, a shallow pool becomes sand, and nothing past the reach changes.
    // P68: Greywall's own equipment on new ground (terminals and server racks, no Capital consoles or tape cabinets),
    // the old fittings on ground saved before; the Capital console's keyboard no longer alternates like a chess board.
    static func greywallKit(_ check: (Bool, String) -> Void) {
        func count(_ bank: Bool) -> [String: Int] {
            var out: [String: Int] = [:]
            let S = 100, t = Greywall.Tier.command, e = t.half + Greywall.margin
            for cz in floorDiv(-e, CS)...floorDiv(e, CS) { for cx in floorDiv(-e, CS)...floorDiv(e, CS) {
                var buf = [BlockID](repeating: AIR, count: CS * CS * CH)
                for z in 0..<CS { for x in 0..<CS { for y in 0...S { buf[Chunk.index(x, y, z)] = STONE } } }
                buf.withUnsafeMutableBufferPointer { b in
                    var w = StructWriter(bx: cx * CS, bz: cz * CS, blocks: b.baseAddress!)
                    Greywall.build(&w, 0, S, 0, t, 4242, bank: bank)
                }
                for b in buf where b != AIR && b != STONE {
                    let base = Blocks.groupBase[Int(b)], k = Blocks.def(base).group ?? Blocks.key(base)
                    if ["greywall_terminal", "greywall_server", "command_console", "data_cabinet"].contains(k) { out[k, default: 0] += 1 }
                }
            } }
            return out
        }
        let fresh = count(true), old = count(false)
        let top = TextureGen.painters()["command_console_top"]
        var alternations = 0
        if let paint = top { for y in 9...12 { for x in 2...12 where paint(x, y) != paint(x + 1, y) && paint(x, y) == paint(x + 2, y) { alternations += 1 } } }
        check((fresh["greywall_terminal"] ?? 0) >= 3 && (fresh["greywall_server"] ?? 0) >= 3 && fresh["command_console"] == nil && fresh["data_cabinet"] == nil
              && (old["command_console"] ?? 0) >= 3 && old["greywall_terminal"] == nil && top != nil && alternations < 12,
              "P68 Greywall kit: a command fortress on new ground has its own terminals and server racks (\(fresh)), one on old ground keeps its fittings (\(old)); console keyboard alternations \(alternations)")
    }

    // P68: intercepted orders open as a document to read (two pages that fit the book screen, naming where they lead)
    // after marking the map; a far-off target and a warship's orders fit too.
    static func readOrders(_ g: Game, _ check: (Bool, String) -> Void) {
        let slot = g.inventory.selected, held = g.inventory.main[slot], marks0 = MapCache.shared.marks, menu0 = g.menu
        defer {
            if g.menu is BookMenu { g.closeMenu() }
            g.menu = menu0; g.inventory.main[slot] = held; MapCache.shared.replaceMarks(marks0)
        }
        if g.menu is DeathMenu { g.menu = nil } else if g.menu != nil { g.closeMenu() }
        g.menu = nil
        g.inventory.main[slot] = ItemStack(Items.id("intercepted_orders"), 1)
        let used = g.factionGearUse()
        let book = g.menu as? BookMenu
        let pages = book?.pages ?? []
        let far = g.ordersPages(Game.RadarContact(name: "Capital Citadel", kind: "military_base", x: -123456, z: 987654))
        let ship = g.ordersPages(Game.RadarContact(name: "Meridian Dreadnought Sovereign", kind: "vessel_dreadnought", x: 40000, z: -40000))
        let all = pages + far + ship
        let long = all.filter { Books.wrap($0).count > Books.linesPerPage }
        check(used && book != nil && pages.count == 2 && pages[0].contains("Capital") && long.isEmpty && !all.contains(where: { $0.contains("_") }),
              "P68 orders: reading intercepted orders opens them as a document (\(book == nil ? "no book" : "\(pages.count) pages"), every page fits the book screen\(long.isEmpty ? "" : "; too long: " + long.map { "\(Books.wrap($0).count) lines" }.joined(separator: ", "))): \(pages.first?.replacingOccurrences(of: "\n", with: " / ").prefix(140) ?? "")")
    }

    // P70: deck guns don't all look the same (the Capital's three looks spread over a base's guns, Greywall's own), and
    // a manned gun's shell bites through Capital stone (a citadel tower) where the crew's own salvo only chips it.
    static func navalGuns(_ g: Game, _ check: (Bool, String) -> Void) {
        var looks: [DeckGunLook: Int] = [:]
        for i in 0..<12 {
            let m = Mob(.deckGun, at: V3(Float(i * 37 - 200), 70, Float(i * 53 + 11)))
            m.faction = Faction.steelhold.rawValue
            looks[deckGunLook(m), default: 0] += 1
        }
        let gm = Mob(.deckGun, at: V3(5, 70, 5)); gm.faction = Faction.greywall.rawValue
        let greyLook = deckGunLook(gm), greyParts = deckGunParts(gm).count
        let a = PlaytestOct12Tests.arena(g, dx: 60, dz: 60, r: 9)
        let w = g.world, stone = Blocks.has("capital_stone") ? Blocks.id("capital_stone") : STONE
        var placed: [IVec3] = []
        defer { for q in placed { w.setBlock(q.x, q.y, q.z, AIR) }; a.restore(); g.drops.items.removeAll() }
        // Two 5 x 5 x 5 blocks of Capital stone, each shelled once on its west face.
        func broken(_ manned: Bool, _ ox: Int) -> Int {
            var n = 0
            for z in (a.fz - 2)...(a.fz + 2) { for y in (a.py + 1)...(a.py + 5) { for x in ox...(ox + 4) { w.setBlock(x, y, z, stone); placed.append(IVec3(x, y, z)) } } }
            var sl = Slug(pos: V3(Float(ox) - 2, Float(a.py) + 3.5, Float(a.fz) + 0.5), vel: V3(260, 0, 0), kind: .shell, damage: 0, fromPlayer: manned,
                          shooter: nil, by: manned ? "Player" : "Deck gun", life: 12, gravity: 0)
            HeavyTurret.arm(&sl)
            if manned { sl.power = HeavyTurret.mannedPower; sl.breach = HeavyTurret.mannedBreach }
            g.arms.detonate(sl, at: V3(Float(ox) - 0.3, Float(a.py) + 3.5, Float(a.fz) + 0.5), g)
            g.arms.breaches.removeAll()              // (the blast alone here; P103's breach has its own check)
            for z in (a.fz - 2)...(a.fz + 2) { for y in (a.py + 1)...(a.py + 5) { for x in ox...(ox + 4) where w.block(x, y, z) != stone { n += 1 } } }
            return n
        }
        let crew = broken(false, a.fx - 8), player = broken(true, a.fx + 2)
        check(looks.count >= 3 && looks.values.allSatisfy { $0 <= 8 } && greyLook == .greywall && greyParts > 0 && player >= 20 && player > crew * 4,
              "P70 deck guns: looks over 12 Capital guns \(looks.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")), Greywall's own (\(greyLook)); one manned shell breaks \(player) blocks of Capital stone, the crew's \(crew)")
    }

    // P99: a frigate's Tidebreaker crater goes at least 20 blocks down under the impact (it was a bowl two thirds of its
    // radius deep), its shots at a player walk in from a 14-block warning, and the struck ground is marked while it charges.
    static func bombard(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let pos0 = g.player.pos
        let fx = Int(floor(pos0.x)) - 150, fz = Int(floor(pos0.z)) + 150      // (well clear of the other checks' ground)
        _ = w.loadSync(center: V3(Float(fx), pos0.y, Float(fz)), radius: 3)
        let top = w.topY(fx, fz)
        // A stone column under the impact, 30 deep, put back afterwards.
        var saved: [(Int, BlockID)] = []
        for y in (top - 30)...top { saved.append((y, w.block(fx, y, fz))); w.setBlock(fx, y, fz, STONE) }
        defer { for (y, b) in saved { w.setBlock(fx, y, fz, b) } }
        let removed = Explosion.crater(at: V3(Float(fx) + 0.5, Float(top + 1), Float(fz) + 0.5), radius: MainGun.craterRadius, cap: MainGun.craterCap,
                                       game: g, depth: MainGun.craterDepth)
        var deep = 0
        for y in stride(from: top, through: top - 30, by: -1) { if w.block(fx, y, fz) == STONE { break }; deep += 1 }
        let walk = (0..<5).map { MainGun.bombardOffset($0) }
        let n0 = g.particles.list.count, m0 = MainGun.bombardMarks
        w.ships.bombardMark(V3(Float(fx), Float(top + 1), Float(fz)), charge: 0.5, dt: 1.0 / 72, game: g)
        let marked = g.particles.list.count - n0
        g.drops.items.removeAll()
        check(deep >= 20 && removed > 1000 && walk == [14, 10, 6, 3, 3] && marked >= 24 && MainGun.bombardMarks == m0 + 1,
              "P99 bombardment: a Tidebreaker crater is \(deep) blocks deep under the impact (\(removed) blocks), shots walk in \(walk.map { Int($0) }), the struck ground is marked (\(marked) lights)")
    }

    // P100: the headset's chase view: none on foot; in a boat it sits behind the boat and above, pulled in short of a
    // wall behind it.
    static func chaseView(_ g: Game, _ check: (Bool, String) -> Void) {
        let a = PlaytestOct12Tests.arena(g, dx: -60, dz: -60, r: 9)
        let riding0 = g.riding, pos0 = g.player.pos, mobs0 = g.mobs.mobs
        var wall: [IVec3] = []
        defer { for q in wall { g.world.setBlock(q.x, q.y, q.z, AIR) }; g.riding = riding0; g.mobs.mobs = mobs0; g.player.pos = pos0; a.restore() }
        g.riding = nil
        g.player.pos = V3(Float(a.fx) + 0.5, Float(a.py + 1), Float(a.fz) + 0.5)
        let foot = g.chaseOffset
        let boat = Mob(.boat, at: g.player.pos); boat.yaw = 0            // facing -z
        g.mobs.mobs.append(boat); g.riding = boat
        let open = g.chaseOffset ?? .zero
        for y in (a.py + 1)...(a.py + 5) { for x in (a.fx - 2)...(a.fx + 2) { g.world.setBlock(x, y, a.fz + 4, STONE); wall.append(IVec3(x, y, a.fz + 4)) } }
        let walled = g.chaseOffset ?? .zero
        check(foot == nil && open.z > 4 && open.y > 1 && simd_length(walled) < simd_length(open) - 1,
              String(format: "P100 chase view: none on foot (%@); a boat's sits %.1f back and %.1f up, %.1f with a wall 4 behind", foot == nil ? "none" : "set", open.z, open.y, simd_length(walled)))
    }

    static func baseBanks(_ check: (Bool, String) -> Void) {
        var buf = [BlockID](repeating: AIR, count: CS * CS * CH)
        for z in 0..<CS { for x in 0..<CS { for y in 0...60 { buf[Chunk.index(x, y, z)] = y == 60 ? GRASS : (y > 56 ? DIRT : STONE) } } }
        // A pool two deep at x 3 z 12...15; a cobble post (built) at x 2 z 0 up to y 68; tall grass everywhere else.
        for z in 12..<CS { buf[Chunk.index(3, 60, z)] = WATER; buf[Chunk.index(3, 59, z)] = WATER }
        for y in 61...68 { buf[Chunk.index(2, y, 0)] = COBBLE }
        let tall = Blocks.has("short_grass") ? Blocks.id("short_grass") : (Blocks.has("grass") ? Blocks.id("grass") : AIR)
        for z in 0..<CS { for x in 4..<CS { buf[Chunk.index(x, 61, z)] = tall } }
        var bad: [String] = []
        buf.withUnsafeMutableBufferPointer { b in
            let w = StructWriter(bx: 0, bz: 0, blocks: b.baseAddress!)
            w.berm(-21, 8, half: 20, floor: 70, reach: 8)            // the site's east edge at x -1: x 0 is d 1
            func top(_ x: Int, _ z: Int) -> (Int, BlockID) {
                var y = CH - 1
                while y > 0 && (b[Chunk.index(x, y, z)] == AIR || !Blocks.collide[Int(b[Chunk.index(x, y, z)])]) { y -= 1 }
                return (y, b[Chunk.index(x, y, z)])
            }
            for x in 0..<CS {
                let d = x + 1, want = d <= 8 ? max(60, 70 - d) : 60
                let (y, t) = top(x, 6)
                if y != want || t != GRASS { bad.append("x \(x): top \(y) \(Blocks.key(t)), want \(want) grass") }
            }
            if top(2, 0).0 != 68 || b[Chunk.index(2, 67, 0)] != COBBLE { bad.append("the cobble post was banked over") }
            let pool = top(3, 13)
            if pool.0 != 66 || pool.1 != SAND { bad.append("the pool: top \(pool.0) \(Blocks.key(pool.1)), want 66 sand") }
            if b[Chunk.index(2, 61, 6)] != DIRT { bad.append("under the bank is \(Blocks.key(b[Chunk.index(2, 61, 6)])), not dirt") }
        }
        check(bad.isEmpty, "P91 base banks: a levelled site's edge falls one block a step into the land (grass on dirt, sand over a shallow pool, built blocks left alone, nothing past the reach)"
              + (bad.isEmpty ? "" : "; " + bad.prefix(5).joined(separator: "; ")))
    }

    static func bigHunters(_ g: Game, _ check: (Bool, String) -> Void) {
        let mobs0 = g.mobs.mobs, st0 = TownLaw.state, inTown0 = TownLaw.inTown, surv0 = g.survival
        defer { g.mobs.mobs = mobs0; TownLaw.state = st0; TownLaw.inTown = inTown0; g.survival = surv0 }
        g.mobs.mobs = []; g.survival = true; TownLaw.inTown = nil
        Honour.value = -90; TownLaw.state.huntersDay = nil
        Rand.seed(4242)
        BountyHunters.send(g)
        let h = g.mobs.mobs.filter { BountyHunters.isHunter($0) }
        // R21: a posse of two to four on the soldier AI (an outlaw draws three), the leader with a six-iron, 60 % tougher.
        let guns = h.filter { ($0.brain?.gun ?? -1) == Guns.revolver }.count
        let tough = h.allSatisfy { $0.health >= $0.kind.spec.health * 3 / 2 }
        // On the map: a red cross for each.
        var lines: [HudLine] = []
        MapDraw.markers(&lines, g, x0: 0, y0: 0, cols: 152, rows: 82, px: 2, wx: g.player.pos.x, wz: g.player.pos.z, bpc: 2, s: 1)
        let crosses = lines.filter { $0.bg == V4(1, 0.2, 0.15, 1) }.count / 2
        g.audio.combatCheck = 0; g.audio.combatHold = 0
        g.combatTick(0.6)
        let music = g.audio.combat
        check(h.count >= 3 && h.count <= 4 && guns >= 1 && tough && crosses == h.count && music >= 1,
              "P88/R21 bounty hunters: \(h.count) come for an outlaw, \(guns) with six-irons, 60 % tougher (\(tough)); \(crosses) on the map; music level \(music)")
    }

    // P94 (09:45): ice you can see through: both the 16 px and the HD tile are mostly clear (mean alpha under 0.45).
    static func clearIce(_ check: (Bool, String) -> Void) {
        let p = TextureGen.painters()
        var a16: Float = 0
        if let f = p["ice"] { for y in 0..<16 { for x in 0..<16 { a16 += f(x, y).w } }; a16 /= 256 }
        var aHD: Float = 0
        if let img = HDTex.table["ice"]?(64, 3) { aHD = img.px.reduce(0) { $0 + $1.w } / Float(img.px.count) }
        check(a16 > 0.2 && a16 < 0.45 && aHD > 0.2 && aHD < 0.45,
              String(format: "P94 ice: mostly clear, mean alpha %.2f (16 px) and %.2f (HD), was about 0.66", a16, aHD))
    }

    // P97 (09:48): hunters' and prospectors' camps have someone by the fire, and a lit campfire can be used with
    // anything but a block or food in hand (a gun too): you rest by it and mend, once a minute.
    static func campLife(_ g: Game, _ check: (Bool, String) -> Void) {
        var people: [String: Int] = [:]
        for kind in ["camp_hunters", "camp_prospectors"] {
            var blocks = [BlockID](repeating: AIR, count: CS * CS * CH)
            blocks.withUnsafeMutableBufferPointer { buf in
                var w = StructWriter(bx: 0, bz: 0, blocks: buf.baseAddress!)
                WildCamps.build(&w, kind, 8, 120, 8, 0, 7)
                people[kind] = w.mobs.filter { $0.0 == "villager:camper" }.count
            }
        }
        let a = PlaytestOct12Tests.arena(g, dx: -50, dz: 50)
        let held0 = g.inventory.held, surv0 = g.survival, rested0 = g.restedAt
        defer { g.world.blockEntities[IVec3(a.fx, a.py + 1, a.fz)] = nil; a.restore(); g.inventory.held = held0; g.survival = surv0; g.restedAt = rested0; g.effects.remove(.regeneration) }
        g.survival = true; g.effects.remove(.regeneration); g.restedAt = -100
        let fire = IVec3(a.fx, a.py + 1, a.fz)
        g.world.setBlock(fire.x, fire.y, fire.z, Blocks.id("campfire"))
        var gun = ItemStack(Items.id("gun_rifle"), 1); gun.tag = Guns.magSize(gun)
        g.inventory.held = gun
        let used = g.useNewBlock((hit: fire, normal: IVec3(0, 1, 0)))
        let mended = g.effects.has(.regeneration)
        g.effects.remove(.regeneration)
        _ = g.useNewBlock((hit: fire, normal: IVec3(0, 1, 0)))
        let again = g.effects.has(.regeneration)
        // And raw food goes on to cook.
        g.inventory.held = ItemStack(Items.id("beef"), 2)
        let cooking = g.useNewBlock((hit: fire, normal: IVec3(0, 1, 0))) && g.inventory.held.count == 1
        check(people["camp_hunters"] == 1 && people["camp_prospectors"] == 1 && used && mended && !again && cooking,
              "P97 camps: someone at the hunters' (\(people["camp_hunters"] ?? 0)) and prospectors' (\(people["camp_prospectors"] ?? 0)) fires; resting by a lit campfire with a gun in hand mends (\(used), \(mended)), not again within a minute (\(!again)); raw beef goes on to cook (\(cooking))")
    }

    // P89 (09:39): breaking leaves is a soft rustle, not a hiss: its sound sits well below the plant break's (which
    // it matched before) by zero crossings, lasts at least 0.2 s, and passes the sound check.
    static func leafSound(_ check: (Bool, String) -> Void) {
        func hz(_ x: [Float]) -> Float {
            var z = 0
            for i in 1..<x.count where (x[i] >= 0) != (x[i - 1] >= 0) { z += 1 }
            return Float(z) / 2 / (Float(x.count) / Synth.sr)
        }
        func audible(_ x: [Float]) -> Float {
            let peak = x.map { abs($0) }.max() ?? 0
            return Float((x.lastIndex { abs($0) > peak * 0.05 } ?? 0)) / Synth.sr
        }
        let leaf = SoundBank.render(.breakBlock(.leaves), variant: 0), plant = SoundBank.render(.breakBlock(.plant), variant: 0)
        let c = SoundBank.check(.breakBlock(.leaves), leaf)
        check(hz(leaf) < hz(plant) * 0.7 && audible(leaf) >= 0.2 && c.ok,
              "P89 leaves: the break rustles at about \(Int(hz(leaf))) Hz (a plant: \(Int(hz(plant)))), heard for \(String(format: "%.2f", audible(leaf))) s; sound check \(c.ok ? "ok" : c.problems.joined(separator: ", "))")
    }

    // P84 (09:34): the polygon terrain option is easy to find: second on the Video page (also with the headset's
    // hidden rows), named "Polygon", and the Create New World page offers "Polygons".
    static func polygonOption(_ g: Game, _ check: (Bool, String) -> Void) {
        let hidden0 = PauseMenu.hostHidden, menu0 = g.menu
        defer { PauseMenu.hostHidden = hidden0; g.menu = menu0 }
        var at: [Int] = [], named: [Bool] = []
        for hidden in [Set<String>(), ["photo", "coop", "fullscreen", "display", "launchfs", "vsync", "fps", "rscale", "wscale", "graphics", "fov", "controls", "keys", "padmap"]] {
            PauseMenu.hostHidden = hidden
            let m = PauseMenu(game: g)
            m.page = .options; m.cat = .video; m.build()
            let i = m.rows.firstIndex { $0.1 == "smooth" } ?? -1
            at.append(i); named.append(i >= 0 && m.rows[i].0.contains("Polygon"))
        }
        let m = PauseMenu(game: g)
        m.page = .create; m.newSmooth = true; m.build()
        let create = m.rows.first { $0.1 == "new_terrain" }?.0 ?? ""
        check(at.allSatisfy { $0 >= 0 && $0 <= 1 } && named.allSatisfy { $0 } && create.contains("Polygons"),
              "P84 polygon terrain: row \(at) on the Video page (desktop, headset), named Polygon (\(named)); Create New World: '\(create)'")
    }

    // P92: a citadel on new ground lays a rail spur with a parked train: every step a connected rail with head room and
    // a bed under it, buffer stops, the locomotive and two freight cars, clear of every other structure; old ground none.
    static func trains(_ check: (Bool, String) -> Void) {
        let p440 = WorldRules.p44
        defer { WorldRules.p44 = p440; CapitalRail.keepSpur = false }
        var bad0: [String] = []
        func spurs(_ on: Bool, keep: Bool = true) -> (WorldGen, [StructureStart], Int) {
            WorldRules.p44 = on
            CapitalRail.keepSpur = keep          // (P470: ground no save had before P470 has none; the spur as drawn before)
            let gen = WorldGen(seed: 12345)
            guard let sc = gen.structures, let t = sc.types.first(where: { $0.name == CapitalRail.kind }),
                  let mt = sc.types.first(where: { $0.name == "military_base" }) else { return (gen, [], 0) }
            var out: [StructureStart] = [], bases = 0
            let span = t.spacing * CS
            for rz in floorDiv(-8000, span)...floorDiv(8000, span) { for rx in floorDiv(-8000, span)...floorDiv(8000, span) {
                // The citadel's own start stays one piece plus its garrison row (its box is the citadel's).
                if let b = sc.start(mt, regionX: rx, regionZ: rz) {
                    bases += 1
                    if b.pieces.contains(where: { $0.max.z - $0.min.z == 7 && $0.max.x - $0.min.x > 40 }) { bad0.append("a citadel start carries a spur") }
                }
                if let st = sc.start(t, regionX: rx, regionZ: rz) { out.append(st) }
            } }
            return (gen, out, bases)
        }
        let (_, old, _) = spurs(false)
        let oldSpurs = old.count
        let (_, p470, _) = spurs(true, keep: false)
        let (gen, withRail, bases) = spurs(true)
        let fresh = Array(repeating: 0, count: bases)     // (the citadels counted)
        var bad: [String] = bad0, cars: [String] = [], steps = 0, overlaps = 0, inWay: [String] = []
        if let st = withRail.first, let sc = gen.structures, let p = st.pieces.first {
            if let l = (st.plan as? CapitalRail.Plan)?.line {
                var chunks: [IVec2Key: [BlockID]] = [:]
                for cxk in floorDiv(min(l.x(0), l.x(l.level.count - 1)) - 2, CS)...floorDiv(max(l.x(0), l.x(l.level.count - 1)) + 2, CS) {
                    let czk = floorDiv(l.z, CS)
                    for dz in -1...1 {
                        var blocks = gen.generate(cx: cxk, cz: czk + dz)
                        cars += sc.place(into: &blocks, cx: cxk, cz: czk + dz).mobs.map { $0.0 }.filter { $0.hasPrefix("minecart") }
                        chunks[IVec2Key(cxk, czk + dz)] = blocks
                    }
                }
                func at(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
                    guard let c = chunks[IVec2Key(floorDiv(x, CS), floorDiv(z, CS))], y >= 0, y < CH else { return AIR }
                    return c[Chunk.index(mod(x, CS), y, mod(z, CS))]
                }
                for i in 0..<l.level.count {
                    let xx = l.x(i), y = l.level[i], b = at(xx, y, l.z)
                    steps += 1
                    if !Rails.isRail(b) { bad.append("step \(i): \(Blocks.key(b)) not rail"); continue }
                    if Rails.shape(b) != CapitalRail.shape(l, i) { bad.append("step \(i): shape \(Rails.shape(b))") }
                    if at(xx, y + 1, l.z) != AIR || at(xx, y + 2, l.z) != AIR { bad.append("step \(i): no head room") }
                    if !Blocks.collide[Int(at(xx, y - 1, l.z))] { bad.append("step \(i): nothing under the rail") }
                    if i > 0 && abs(l.level[i] - l.level[i - 1]) > 1 { bad.append("step \(i): a jump") }
                }
                // Clear of every other structure.
                // (Its own citadel included. Underground and sky kinds aside: the box reaches 40 down for trestle legs.)
                for t in sc.types where ![CapitalRail.kind, "mineshaft", "ancient_city", "trial_chambers", "fossil", "buried_treasure", SkyIsle.kind].contains(t.name) {
                    let span = t.spacing * CS
                    for rz in (floorDiv(p.min.z, span) - 1)...(floorDiv(p.max.z, span) + 1) { for rx in (floorDiv(p.min.x, span) - 1)...(floorDiv(p.max.x, span) + 1) {
                        guard let o = sc.start(t, regionX: rx, regionZ: rz) else { continue }
                        if o.max.x >= p.min.x && o.min.x <= p.max.x && o.max.z >= p.min.z && o.min.z <= p.max.z { overlaps += 1; inWay.append(o.kind) }
                    } }
                }
            } else { bad.append("no plan") }
        }
        let loco = Mob.structureMob("minecart:loco_e", at: V3(0, 100, 0)), freight = Mob.structureMob("minecart:freight", at: V3(4, 100, 0))
        let carsOK = loco?.variant == 4 && loco?.customName == "Capital Locomotive" && freight?.variant == 1 && (freight?.cargo.map { c in (0..<c.count).contains { !c[$0].isEmpty } } ?? false)
        check(oldSpurs == 0 && p470.isEmpty && !withRail.isEmpty && bad.isEmpty && steps >= 40 && cars.count == 3 && carsOK && overlaps == 0,
              "P92 trains: \(withRail.count) of \(fresh.count) citadels on new ground lay a rail spur (old ground \(oldSpurs); ground new since P470 \(p470.count): a citadel is a main-line station); the first: \(steps) steps of connected track with head room and a bed, "
              + "\(cars.count) cars parked (\(cars.joined(separator: " "))), cars set up \(carsOK), \(overlaps) other structures in its way \(inWay)" + (bad.isEmpty ? "" : "; " + bad.prefix(4).joined(separator: "; ")))
    }

    // P93: wrecks on new ground are rotten, not holed, and a helm won't raise one until the rotten planks are replaced;
    // a ship's guns use cannonballs; a cannon by a base computer is an auto-turret that hurts hostiles, not blocks.
    static func wrecks(_ g: Game, _ check: (Bool, String) -> Void) {
        let p440 = WorldRules.p44
        defer { WorldRules.p44 = p440 }
        // Generated wrecks: rotten planks on new ground only.
        func rot(_ on: Bool) -> (Int, Int) {
            WorldRules.p44 = on
            let gen = WorldGen(seed: 12345)
            guard let sc = gen.structures, let t = sc.types.first(where: { $0.name == "shipwreck" }) else { return (0, 0) }
            var n = 0, wrecks = 0
            for rz in -3...3 { for rx in -3...3 where wrecks < 4 {
                guard let st = sc.start(t, regionX: rx, regionZ: rz) else { continue }
                wrecks += 1
                for cz in floorDiv(st.min.z, CS)...floorDiv(st.max.z, CS) { for cx in floorDiv(st.min.x, CS)...floorDiv(st.max.x, CS) {
                    var blocks = gen.generate(cx: cx, cz: cz)
                    _ = sc.place(into: &blocks, cx: cx, cz: cz)
                    n += blocks.reduce(0) { $0 + ($1 == Wrecks.rottenID ? 1 : 0) }
                } }
            } }
            return (n, wrecks)
        }
        let (oldRot, _) = rot(false), (newRot, wrecks) = rot(true)
        // The helm refuses a rotten hull, then raises it once the plank is replaced.
        let w = g.world, pos0 = g.player.pos
        // A 3 x 3 raft of planks in the air with a helm on it (and, first, a rotten plank at its edge).
        let rx = Int(floor(pos0.x)) - 30, rz = Int(floor(pos0.z)) + 30
        _ = w.loadSync(center: V3(Float(rx), pos0.y, Float(rz)), radius: 2)
        let ry = min(CH - 10, w.topY(rx, rz) + 20)
        var raftCells: [(IVec3, BlockID)] = []
        for z in (rz - 1)...(rz + 1) { for x in (rx - 1)...(rx + 1) { raftCells.append((IVec3(x, ry, z), w.block(x, ry, z))); w.setBlock(x, ry, z, PLANKS) } }
        raftCells.append((IVec3(rx, ry + 1, rz), w.block(rx, ry + 1, rz))); raftCells.append((IVec3(rx + 2, ry, rz), w.block(rx + 2, ry, rz)))
        w.setBlock(rx, ry + 1, rz, Blocks.id("ship_helm"))
        let helm = IVec3(rx, ry + 1, rz)
        let plank: IVec3? = IVec3(rx + 2, ry, rz)
        var refused = "", raised = false
        if let pl = plank {
            let was = w.block(pl.x, pl.y, pl.z)
            w.setBlock(pl.x, pl.y, pl.z, Wrecks.rottenID)
            let (no, msg) = w.ships.assemble(at: helm, game: g)
            refused = no == nil ? msg : ""
            w.setBlock(pl.x, pl.y, pl.z, was)
            if let s = w.ships.assemble(at: helm, game: g).0 { raised = true; w.ships.remove(s) }
        }
        for (p, b) in raftCells.reversed() { w.setBlock(p.x, p.y, p.z, b) }
        // Cannonballs: the pack pays one a gun.
        let inv = g.inventory.main, slot0 = inv[0]
        inv[0] = ItemStack(Items.id(Wrecks.cannonball), 3)
        Wrecks.useCannonballs(g, 2)
        let balls = Wrecks.cannonballs(g)
        inv[0] = slot0
        // The auto-turret: a cannon and a console on a stone deck in the air, a zombie 16 blocks off.
        let mobs0 = g.mobs.mobs, time0 = g.time
        let fx = Int(floor(pos0.x)) + 40, fz = Int(floor(pos0.z)) - 40
        _ = w.loadSync(center: V3(Float(fx), pos0.y, Float(fz)), radius: 3)
        let py = min(CH - 14, w.topY(fx, fz) + 30)
        var placed: [(IVec3, BlockID)] = []
        func put(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) { placed.append((IVec3(x, y, z), w.block(x, y, z))); w.setBlock(x, y, z, b) }
        for z in (fz - 4)...(fz + 4) { for x in (fx - 2)...(fx + 20) {
            put(x, py, z, STONE)
            for y in (py + 1)...(py + 5) where !w.isAir(x, y, z) { put(x, y, z, AIR) }
        } }
        put(fx, py + 1, fz, Blocks.id("ship_cannon"))
        put(fx - 1, py + 1, fz, Blocks.id("command_console"))
        let sites0 = AutoTurrets.sites
        AutoTurrets.sites = []
        AutoTurrets.placed(g, IVec3(fx - 1, py + 1, fz))
        let online = AutoTurrets.sites.contains(IVec3(fx, py + 1, fz))
        g.mobs.mobs = []
        let z0 = Mob(.zombie, at: V3(Float(fx + 16) + 0.5, Float(py + 1), Float(fz) + 0.5))
        z0.health = 200
        g.mobs.mobs.append(z0)
        var deck = 0
        for z in (fz - 4)...(fz + 4) { for x in (fx - 2)...(fx + 20) where w.block(x, py, z) == STONE { deck += 1 } }
        for _ in 0..<(72 * 6) {
            z0.pos = V3(Float(fx + 16) + 0.5, Float(py + 1), Float(fz) + 0.5); z0.vel = .zero
            AutoTurrets.tick(g, 1.0 / 72)
            w.ships.updateShells(1.0 / 72, game: g)
        }
        var deckAfter = 0
        for z in (fz - 4)...(fz + 4) { for x in (fx - 2)...(fx + 20) where w.block(x, py, z) == STONE { deckAfter += 1 } }
        let hurt = 200 - z0.health
        w.ships.shells.removeAll()
        AutoTurrets.sites = sites0
        g.mobs.mobs = mobs0; g.time = time0
        for (p, b) in placed.reversed() { w.setBlock(p.x, p.y, p.z, b) }
        check(oldRot == 0 && newRot > 0 && refused.contains("rotten") && raised && balls == 1 && online && hurt > 0 && deckAfter == deck,
              "P93 wrecks: \(wrecks) wrecks on new ground have \(newRot) rotten planks (old ground \(oldRot)); a rotten hull is refused ('\(refused)'), raised once replaced (\(raised)); "
              + "3 cannonballs less 2 leaves \(balls); a cannon by a console comes online (\(online)) and hits a zombie 16 off for \(hurt) without breaking blocks (\(deck) -> \(deckAfter))")
    }

    // P69 (09:18-09:19): on new ground a Boreal station is Greywall Command's (its troops and stores), and stations and
    // Greywall bases stand at least WorldRules.capitalApartP69 blocks from any Capital citadel or city.
    static func greywallApart(_ check: (Bool, String) -> Void) {
        let p440 = WorldRules.p44
        WorldRules.p44 = true
        defer { WorldRules.p44 = p440 }
        let gen = WorldGen(seed: 12345)
        guard let sc = gen.structures else { check(false, "P69: no structures"); return }
        var starts: [String: [StructureStart]] = [:]
        for t in sc.types where ["military_base", "capital_city", BorealStation.kind, Greywall.kind].contains(t.name) {
            let span = t.spacing * CS
            for rz in floorDiv(-9000, span)...floorDiv(9000, span) { for rx in floorDiv(-9000, span)...floorDiv(9000, span) {
                if let st = sc.start(t, regionX: rx, regionZ: rz) { starts[t.name, default: []].append(st) }
            } }
        }
        func gap(_ a: StructureStart, _ b: StructureStart) -> Int {
            let dx = max(0, max(a.min.x - b.max.x, b.min.x - a.max.x)), dz = max(0, max(a.min.z - b.max.z, b.min.z - a.max.z))
            return Int(hypotf(Float(dx), Float(dz)))
        }
        let capital = (starts["military_base"] ?? []) + (starts["capital_city"] ?? [])
        let grey = (starts[BorealStation.kind] ?? []) + (starts[Greywall.kind] ?? [])
        let closest = grey.map { g in capital.map { gap(g, $0) }.min() ?? Int.max }.min() ?? Int.max
        // A station's garrison and stores.
        var keys: [String] = []
        if let st = starts[BorealStation.kind]?.first {
            let cx = floorDiv((st.min.x + st.max.x) / 2, CS), cz = floorDiv((st.min.z + st.max.z) / 2, CS)
            for dz in -2...2 { for dx in -2...2 {
                var blocks = gen.generate(cx: cx + dx, cz: cz + dz)
                keys += sc.place(into: &blocks, cx: cx + dx, cz: cz + dz).mobs.map { $0.0 }
            } }
        }
        let soldiers = keys.filter { $0.hasPrefix("soldier_") }
        check(closest >= WorldRules.capitalApartP69 && !soldiers.isEmpty && soldiers.allSatisfy { $0.hasSuffix("@grey") } && grey.count >= 3,
              "P69 Greywall apart: \(grey.count) stations and Greywall bases over 18 km square, the nearest \(closest) blocks from a Capital citadel or city (\(capital.count)); a station's \(soldiers.count) soldiers are Greywall's (\(Set(soldiers.map { $0.hasSuffix("@grey") })))")
    }

    // P73 (09:21): a tap on the map (the headset's laser and trigger, or a mouse click) drops a waypoint where it
    // points; a drag pans and drops none.
    static func mapClickPin(_ g: Game, _ check: (Bool, String) -> Void) {
        let menu0 = g.menu
        defer { g.input.leftDown = false; g.menu = menu0 }
        let m = MapMenu(game: g)
        g.menu = m
        let L = HudLayout(g.screen.x, g.screen.y).fitted(m)
        let o = m.origin(L), s = L.s
        // 30 cells right and 10 down of the centre cross.
        let at = V2(o.x + 8 * s + (Float(MapMenu.cols) / 2 + 30.5) * 2 * s, o.y + 18 * s + (Float(MapMenu.rows) / 2 + 10.5) * 2 * s)
        let want = (Int(floor(m.cx + 30.5 * Float(m.bpc))), Int(floor(m.cz + 10.5 * Float(m.bpc))))
        func pins() -> [(Int, Int)] { MapCache.shared.marks.filter { $0.kind == "pin" }.map { ($0.x, $0.z) } }
        let before = pins()
        func added() -> [(Int, Int)] { pins().filter { p in !before.contains { $0 == p } } }
        func undo() { for p in added() { MapCache.shared.togglePin(g, x: p.0, z: p.1, near: 0) } }
        g.input.mouseX = at.x; g.input.mouseY = at.y
        g.input.leftDown = true; m.tick(); m.tick()
        g.input.leftDown = false; m.tick()
        let tapped = added()
        let hit = tapped.contains { abs($0.0 - want.0) <= m.bpc && abs($0.1 - want.1) <= m.bpc }
        undo()
        // A drag of 40 px: no pin.
        g.input.leftDown = true; m.tick()
        for k in 1...8 { g.input.mouseX = at.x + Float(k) * 5; m.tick() }
        g.input.leftDown = false; m.tick()
        let dragged = added().count
        undo()
        check(hit && tapped.count == 1 && dragged == 0,
              "P73 map: a tap drops a waypoint where it points (\(tapped) for \(want)); a drag pans and drops none (\(dragged))")
    }

    // P71 (09:20): wide towns' streets are five blocks across (a narrow, saved-ground town keeps three). The town's
    // pieces are built over plain ground in the 5 x 5 chunks round the square and, for each street column, the narrower of its
    // straight runs of street across x and z is its width; the most common width counts.
    static func streetWidth(_ g: Game, _ check: (Bool, String) -> Void) {
        guard let gen = g.world.gen as? WorldGen else { return }
        func width(_ st: StructureStart, _ ox: Int, _ oz: Int, _ path: BlockID) -> Int {
            var street = Set<IVec2Key>()
            for cz in (floorDiv(oz, CS) - 2)...(floorDiv(oz, CS) + 2) { for cx in (floorDiv(ox, CS) - 2)...(floorDiv(ox, CS) + 2) {
                var blocks = [BlockID](repeating: AIR, count: CS * CS * CH)
                for lz in 0..<CS { for lx in 0..<CS {                   // (ground, so a road column is path, not planks)
                    for y in 0...min(CH - 1, gen.groundY(cx * CS + lx, cz * CS + lz)) { blocks[Chunk.index(lx, y, lz)] = DIRT }
                } }
                blocks.withUnsafeMutableBufferPointer { buf in
                    var w = StructWriter(bx: cx * CS, bz: cz * CS, blocks: buf.baseAddress!)
                    for pc in st.pieces.dropFirst() where pc.overlaps(cx * CS, cz * CS) { pc.build(&w) }   // (not the square)
                    for lz in 0..<CS { for lx in 0..<CS {
                        let x = cx * CS + lx, z = cz * CS + lz
                        if (40..<(CH - 1)).contains(where: { w.get(x, $0, z) == path }) { street.insert(IVec2Key(x, z)) }
                    } }
                }
            } }
            var hist: [Int: Int] = [:]
            for c in street {
                func run(_ dx: Int, _ dz: Int) -> Int {
                    var n = 1, k = 1
                    while street.contains(IVec2Key(c.x + dx * k, c.z + dz * k)) { n += 1; k += 1 }
                    k = 1
                    while street.contains(IVec2Key(c.x - dx * k, c.z - dz * k)) { n += 1; k += 1 }
                    return n
                }
                hist[min(run(1, 0), run(0, 1)), default: 0] += 1
            }
            return hist.max { $0.value < $1.value }?.key ?? 0
        }
        var got: [(Int, Int)] = []
        for i in 0..<40 where got.count < 3 {
            let ox = (i % 10) * 544 + 8 - 3000, oz = (i / 10) * 544 + 8 - 3000
            let cy = gen.groundY(ox, oz)
            guard cy >= SEA else { continue }
            let seed = UInt64(i) &* 0x9E3779B97F4A7C15
            guard let wideT = Village.layout(gen, seed: seed, ox: ox, oz: oz, cy: cy, style: .plains, frontier: true, townsGap: true, wide: true, streets: true),
                  let narrowT = Village.layout(gen, seed: seed, ox: ox, oz: oz, cy: cy, style: .plains, frontier: true, townsGap: true, wide: false) else { continue }
            let m = Village.mats(.plains)
            got.append((width(wideT, ox, oz, m.path), width(narrowT, ox, oz, m.path)))
        }
        check(got.count == 3 && got.allSatisfy { $0.0 == 5 && $0.1 == 3 },
              "P71 streets: wide towns' streets are 5 blocks across, saved-ground towns keep 3 (wide, narrow per town: \(got.map { "\($0.0)/\($0.1)" }.joined(separator: ", ")))")
    }

    // P96 (09:47): an outlaw is known (fought on sight, refused service) only near where the deed was done.
    static func localOutlaw(_ g: Game, _ check: (Bool, String) -> Void) {
        let st0 = TownLaw.state, pos0 = g.player.pos, surv0 = g.survival
        defer { TownLaw.state = st0; g.player.pos = pos0; g.survival = surv0 }
        g.survival = true
        TownLaw.state.honour = -55; TownLaw.state.outlawAt = nil
        g.player.pos = V3(5000, 140, 5000)
        Honour.change(g, -10, "test: a killing")                       // past the outlaw line here
        let at = TownLaw.state.outlawAt ?? []
        let here = Honour.outlawKnown(g)
        g.player.pos = V3(5300, 140, 5200)
        let nextTown = Honour.outlawKnown(g)
        g.player.pos = V3(6500, 140, 5000)
        let far = Honour.outlawKnown(g)
        let still = Honour.isOutlaw
        // An old save (no spot): known where the player stands.
        TownLaw.state.outlawAt = nil
        let old = Honour.outlawKnown(g) && TownLaw.state.outlawAt?.first == 6500
        check(at == [5000, 5000] && here && nextTown && !far && still && old,
              "P96 outlaw: known where it happened (\(here)) and 360 blocks off (\(nextTown)), not 1,500 off (\(!far)), still an outlaw by standing (\(still)); an old save starts where you stand (\(old))")
    }

    // P95 (09:47-09:48, World376): "bunker bases ... way too common", "another military base thing".
    static func baseRarity(_ check: (Bool, String) -> Void) {
        let p440 = WorldRules.p44
        WorldRules.p44 = true
        defer { WorldRules.p44 = p440 }
        let gen = WorldGen(seed: 3931512493184456980)
        let c = census(gen, x: 10000, z: -12000, half: 2000, near: [(8925, -12007), (9316, -12184), (10906, -12222), (11190, -12091)])
        print("P95 census World376 4000x4000 at 10000,-12000: \(c.counts.sorted { $0.key < $1.key })")
        for n in c.nearest { print("P95 nearest: " + n) }
        for n in census(gen, x: -400, z: -1770, half: 900, near: [(-406, -1770)]).nearest { print("P69 nearest to the 09:18 outpost: " + n) }
        for n in census(gen, x: 4716, z: -9554, half: 900, near: [(4716, -9554)]).nearest { print("P91 nearest to the 09:40 base: " + n) }
        // P87: the roads near his 09:37 spot (no save guard here: every road the rules allow).
        if let n = Roads.nearest(gen, to: V3(4668, 88, -8625), range: 600) { print("P87 nearest road to 4668,-8625: \(Int(Roads.distance(n.0, V2(4668, -8625)).0)) blocks, \(n.0.a) to \(n.0.b)") }
        else { print("P87 no road within 600 of 4668,-8625") }
        // And four squares of the test seed's world.
        let gen2 = WorldGen(seed: 12345)
        var other: [String: Int] = [:]
        for (x, z) in [(6000, 6000), (-6000, 6000), (6000, -6000), (-6000, -6000)] {
            for (k, n) in census(gen2, x: x, z: z, half: 2000).counts { other[k, default: 0] += n }
        }
        print("P95 census seed 12345, four 4000x4000 squares: \(other.sorted { $0.key < $1.key })")
        let st = c.counts[BorealStation.kind] ?? 0, gw = c.counts[Greywall.kind] ?? 0, mb = c.counts["military_base"] ?? 0
        let st2 = Float(other[BorealStation.kind] ?? 0) / 4, gw2 = Float(other[Greywall.kind] ?? 0) / 4
        check(st <= 3 && gw <= 2 && st + gw + mb <= 5 && st2 <= 2 && gw2 <= 2,
              "P95 bases: in Remington's World376 square (4,000 x 4,000) \(st) Boreal stations, \(gw) Greywall bases, \(mb) citadels (were 19, 4, 2); seed 12345 averages \(st2) and \(gw2) per square")
    }

    // Structure starts of the military kinds in a square (half `half` blocks) round (x, z), with the nearest kind to
    // each named point (the playtest's sightings).
    static let militaryKinds = ["military_base", Greywall.kind, BorealStation.kind, "pillager_outpost", "wild_camp", "capital_city"]
    static func census(_ gen: WorldGen, x: Int, z: Int, half: Int, near pts: [(Int, Int)] = []) -> (counts: [String: Int], nearest: [String]) {
        guard let sc = gen.structures else { return ([:], []) }
        var counts: [String: Int] = [:], all: [(String, Int, Int)] = []
        for t in sc.types where militaryKinds.contains(t.name) {
            let span = t.spacing * CS
            for rz in floorDiv(z - half, span)...floorDiv(z + half, span) { for rx in floorDiv(x - half, span)...floorDiv(x + half, span) {
                guard let st = sc.start(t, regionX: rx, regionZ: rz) else { continue }
                if abs(st.anchor.x - x) <= half && abs(st.anchor.z - z) <= half { counts[t.name, default: 0] += 1; all.append((t.name, st.anchor.x, st.anchor.z)) }
            } }
        }
        let nearest = pts.map { p in all.min { hypotf(Float($0.1 - p.0), Float($0.2 - p.1)) < hypotf(Float($1.1 - p.0), Float($1.2 - p.1)) }
            .map { "\($0.0) at \($0.1),\($0.2) (\(Int(hypotf(Float($0.1 - p.0), Float($0.2 - p.1)))) off)" } ?? "none" }
        return (counts, nearest)
    }

    // P90 (09:33): "turtles appear near a snow biome". Over a 6 km square of the test world, beaches beside anything
    // cold get no turtles and a warm beach does; a pack never spills off the beach.
    static func turtleBeaches(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, mm = g.mobs
        var warm: (Int, Int)?, coldBeach: (Int, Int)?, beaches = 0
        for i in stride(from: -3000, through: 3000, by: 48) { for j in stride(from: -3000, through: 3000, by: 48) {
            guard w.gen.column(i, j).biome == .beach else { continue }
            beaches += 1
            if MobManager.turtleShore(w, i, j) { if warm == nil { warm = (i, j) } } else if coldBeach == nil {
                let near = (0..<8).contains { k in let a = Float(k) * .pi / 4; return w.gen.column(i + Int(cosf(a) * 20), j + Int(sinf(a) * 20)).biome.info.temp < 0.3 }
                if near { coldBeach = (i, j) }
            }
        } }
        let mobs0 = mm.mobs
        defer { mm.mobs = mobs0 }
        func pack(_ x: Int, _ z: Int) -> (n: Int, off: Int) {
            _ = w.loadSync(center: V3(Float(x), 140, Float(z)), radius: 2)
            mm.mobs.removeAll()
            for _ in 0..<6 { mm.spawnAnimalPack(w, .turtle, x, z, 5) }
            let t = mm.mobs.filter { $0.kind == .turtle }
            return (t.count, t.filter { w.gen.column(Int(floor($0.pos.x)), Int(floor($0.pos.z))).biome != .beach }.count)
        }
        let wp = warm.map { pack($0.0, $0.1) }, cp = coldBeach.map { pack($0.0, $0.1) }
        check((wp?.n ?? 0) > 0 && wp?.off == 0 && (cp?.n ?? 0) == 0,
              "P90 turtles: \(beaches) beach samples; a warm beach gets \(wp?.n ?? -1) turtles (\(wp?.off ?? -1) off the sand), a beach beside cold ground \(cp.map { "gets \($0.n)" } ?? "(none found)")")
    }

    // P80 (09:27): "the flower on top of cactus floats above it": both the 16 px and the HD tile must reach the bottom
    // row (the cactus top is flush with the block below the flower).
    static func cactusFlower(_ check: (Bool, String) -> Void) {
        var p: [String: TextureGen.Painter] = [:]
        TextureGen.springPainters(&p)
        func lowest16() -> Int { guard let f = p["cactus_flower"] else { return -1 }; var m = -1; for y in 0..<16 { for x in 0..<16 where f(x, y).w > 0.1 { m = max(m, y) } }; return m }
        let n = 64
        let img = HDTex.table["cactus_flower"].map { $0(n, 7) }
        var low = -1
        if let img = img { for y in 0..<n { for x in 0..<n where img[x, y].w > 0.1 { low = max(low, y) } } }
        check(lowest16() == 15 && low == n - 1, "P80 cactus flower: the bloom reaches the tile's bottom row, on the cactus (16 px: row \(lowest16()) of 15; HD: row \(low) of \(n - 1))")
    }

    // P78 (09:26): "don't keep them red": a mob killed mid-hurt lay red on the ground (corpses are never updated).
    static func corpseTint(_ g: Game, _ check: (Bool, String) -> Void) {
        let at = g.player.pos + V3(40, 40, 40)
        let live = Mob(.pig, at: at); live.hurt = 0.3
        let dead = Mob(.pig, at: at); dead.hurt = 0.3; dead.fire = 2; dead.health = 0; dead.deathT = 0.5
        let body = Mob(.cow, at: at); body.hurt = 0.3; body.carcass = true
        let red = Mob.tint(live), d = Mob.tint(dead), b = Mob.tint(body)
        check(red.y < 0.6 && d == V3(1, 1, 1) && b == V3(1, 1, 1),
              "P78 corpses: a hurt mob flashes red (\(red)), a corpse (\(d)) and a hunted carcass (\(b)) don't stay red")
    }

    // P85 (09:31): on the headset the grip / stick labels beside the hotbar go (a screen with a pad keeps them).
    static func hotbarHints(_ g: Game, _ check: (Bool, String) -> Void) {
        let st = Settings.shared
        let style0 = st.glyphStyle, hints0 = st.buttonHints, secs0 = st.hintSeconds, en0 = HudExtras.enabled, head0 = g.vrHead, menu0 = g.menu
        defer { st.glyphStyle = style0; st.buttonHints = hints0; st.hintSeconds = secs0; HudExtras.enabled = en0; g.vrHead = head0; g.menu = menu0 }
        st.glyphStyle = 1; st.buttonHints = true; st.hintSeconds = 0; HudExtras.enabled = true; g.menu = nil
        let L = HudLayout(1280, 720)
        let lb = PadMap.glyph(.lb).s
        func labelled() -> Bool { HudExtras.lines(g, L).contains { $0.text == lb && $0.x < L.hotbarX0 && abs($0.y - (L.hotbarY0 + L.slot / 2 - 4 * L.s)) < 1 } }
        g.vrHead = nil
        let tv = labelled()
        g.vrHead = g.player.eye
        let vr = labelled()
        // P328 (NO TEXT): no control labels over play on a screen either (they never showed on the headset).
        check(!tv && !vr, "P85 / P328 hotbar: no bumper labels beside the hotbar on a screen (\(tv)) or on the headset (\(vr))")
    }

    // P72 (09:21): the open menu tab stayed grey ("I can only tell by haptic feedback"). The crafting book's open tab
    // must stand apart from the others in brightness and colour, and the hover colour must differ from plain grey.
    static func tabHighlight(_ g: Game, _ check: (Bool, String) -> Void) {
        func luma(_ c: V4) -> Float { 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }
        func chroma(_ c: V4) -> Float { max(c.x, c.y, c.z) - min(c.x, c.y, c.z) }
        let cb = CraftingBookMenu(game: g, size: 3)
        cb.tab = .tools
        let L = HudLayout(1280, 720)
        let lines = cb.drawLines(L, V2(0, 0))
        let tabs = cb.slots.filter { if case .button(let id) = $0.kind { return id >= CraftingBookMenu.tabBase && id < CraftingBookMenu.tabBase + CraftCategory.allCases.count } else { return false } }
        func fill(_ sl: MenuSlot) -> V4? {
            lines.first { $0.bg != nil && abs($0.x - Float(sl.x) * L.s) < 0.5 && abs($0.y - Float(sl.y) * L.s) < 0.5 }?.bg
        }
        let open = tabs.first { if case .button(let id) = $0.kind { return id == CraftingBookMenu.tabBase + CraftCategory.tools.rawValue } else { return false } }.flatMap(fill)
        let other = tabs.first { if case .button(let id) = $0.kind { return id == CraftingBookMenu.tabBase } else { return false } }.flatMap(fill)
        let grey = V4(0.42, 0.42, 0.46, 1)
        let ok = open.map { o in other.map { abs(luma(o) - luma($0)) > 0.15 && chroma(o) > 0.5 } ?? false } ?? false
        check(ok && chroma(MenuColors.hover) > 0.5 && abs(luma(MenuColors.hover) - luma(grey)) > 0.05,
              "P72 menu tabs: the open tab is a clear colour against the others (open \(open.map { "\($0)" } ?? "none"), other \(other.map { "\($0)" } ?? "none")), hover is a strong blue")
    }

    // P81/P83 (09:28, a fresh horse "slow as anything"; stamina far too short; bond should raise health too): a full
    // push canters faster than the player sprints, and a bonded horse takes less of a hit (HorseTests has the gaits).
    static func horseBond(_ g: Game, _ check: (Bool, String) -> Void) {
        let at = g.player.pos + V3(60, 40, 60)
        var took: [Int] = []
        for lvl in [1, 4] {
            let h = Mob(.horse, at: at); h.owner = true; h.saddled = true
            h.hs.bondXP = HorseFeel.levelXP[lvl - 1]
            let h0 = h.health
            h.invulnerable = 0
            h.hit(from: at + V3(2, 0, 0), damage: 10, knockback: 0)
            took.append(h0 - h.health)
        }
        let slowest = Mob(.horse, at: at); slowest.variant = 0                // the slowest breed roll (top 8 b/s)
        let canter = slowest.gaitSpeed(.canter)
        check(took[0] == 10 && took[1] == 6 && canter > 5.6,
              "P83 horse: a 10 hit takes \(took[0]) at bond 1 and \(took[1]) at bond 4; P81 the slowest horse canters at \(canter) b/s on a full push (the player sprints 5.6)")
    }

    // A stone floor high over the spawn, cleared above, for checks that press buttons through Game.tick. Returns the
    // floor's y and a function that puts everything back.
    static func arena(_ g: Game, dx: Int = 50, dz: Int = -50, r: Int = 5) -> (fx: Int, fz: Int, py: Int, restore: () -> Void) {
        let w = g.world
        let pos0 = g.player.pos
        let fx = Int(floor(pos0.x)) + dx, fz = Int(floor(pos0.z)) + dz
        _ = w.loadSync(center: V3(Float(fx), pos0.y, Float(fz)), radius: 2)
        let py = min(CH - 12, w.topY(fx, fz) + 30)
        var placed: [(IVec3, BlockID)] = []
        for z in (fz - r)...(fz + r) { for x in (fx - r)...(fx + r) { for y in py...(py + 5) {
            let want = y == py ? STONE : AIR
            let b = w.block(x, y, z)
            if b != want { placed.append((IVec3(x, y, z), b)); w.setBlock(x, y, z, want) }
        } } }
        return (fx, fz, py, { for (p, b) in placed.reversed() { w.setBlock(p.x, p.y, p.z, b) } })
    }

    // Press a pad snapshot for one tick (as the headset feeds it), then let go.
    static func press(_ g: Game, _ f: (inout PadSnapshot) -> Void) {
        let pm = PadManager.shared
        pm.touch = PadSnapshot(); g.tick(1.0 / 72)
        var p = PadSnapshot(); f(&p)
        pm.touch = p; g.tick(1.0 / 72)
        pm.touch = PadSnapshot(); g.tick(1.0 / 72)
    }

    // P74 (09:22): with a gun in hand the use press opened no door (the gun's aim took it), and a left grip by the side
    // never stepped the hotbar (every grip read as a reach for a magazine, refused with the gun full).
    static func gunOpensDoors(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, pm = PadManager.shared
        let pos0 = g.player.pos, yaw0 = g.player.yaw, pitch0 = g.player.pitch, surv0 = g.survival, fly0 = g.player.flying
        let sel0 = g.selected, slot0 = g.inventory.main[g.selected], menu0 = g.menu, riding0 = g.riding, credits0 = g.credits
        let a = arena(g)
        defer {
            pm.touch = nil; a.restore()
            if g.menu is DeathMenu { g.menu = nil } else if g.menu != nil { g.closeMenu() }
            g.menu = menu0; g.riding = riding0; g.credits = credits0
            g.player.pos = pos0; g.player.vel = .zero; g.player.yaw = yaw0; g.player.pitch = pitch0
            g.survival = surv0; g.player.flying = fly0; g.selected = sel0; g.inventory.main[sel0] = slot0
            g.arms.magInHand = false; g.arms.aim = 0
        }
        if g.menu is DeathMenu { g.menu = nil } else if g.menu != nil { g.closeMenu() }
        g.riding = nil; g.credits = nil; g.survival = true; g.player.flying = false; g.health = 20; g.alive = true
        var gun = ItemStack(Items.id("gun_rifle"), 1); gun.tag = Guns.magSize(gun)
        g.inventory.main[g.selected] = gun
        // A door two blocks north, a wall beside it.
        let door = IVec3(a.fx, a.py + 1, a.fz - 2)
        w.setBlock(door.x, door.y, door.z, Blocks.id("oak_door")); w.setBlock(door.x, door.y + 1, door.z, Blocks.id("oak_door") + 8)
        for y in (a.py + 1)...(a.py + 2) { w.setBlock(a.fx + 2, y, a.fz - 2, STONE) }
        g.player.pos = V3(Float(a.fx) + 0.5, Float(a.py + 1), Float(a.fz) + 0.5); g.player.vel = .zero
        g.player.yaw = 0; g.player.pitch = -0.25
        for _ in 0..<20 { g.tick(1.0 / 72) }
        let closed = w.block(door.x, door.y, door.z)
        let gunOut = g.heldGun != nil
        press(g) { $0.lt = 1 }
        let opened = w.block(door.x, door.y, door.z) != closed
        // Aimed at the wall instead, the same press still aims the gun.
        g.player.yaw = -atan2f(2, 2.5)
        var aimed: Float = 0
        pm.touch = PadSnapshot(); g.tick(1.0 / 72)
        for _ in 0..<20 { var p = PadSnapshot(); p.lt = 1; pm.touch = p; g.tick(1.0 / 72); aimed = max(aimed, g.arms.aim) }
        pm.touch = PadSnapshot(); g.tick(1.0 / 72)
        check(gunOut && opened && aimed > 0.3,
              "P74 gun in hand: the use press opens a door in reach (\(opened)) and still aims the gun elsewhere (aim \(String(format: "%.2f", aimed)))")
        // The left grip by the side with a full gun: no magazine taken; P465: and it doesn't step the hotbar either (the
        // grip in front of the waist does, P109).
        let head = g.player.eye
        let ev = VRReload.tick(g, offHand: head + V3(-0.25, -0.8, 0.05), gunHand: head + V3(0.2, -0.35, -0.35), head: head, grip: true, gripWas: false)
        check(ev == .full && !g.arms.magInHand, "P74/P465 gun in hand: a left grip at the side with a full magazine takes nothing (\(ev)) and keeps the gun")
    }
}
