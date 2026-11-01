import Foundation
import simd

// Oct 14 midday playtest items (docs/roadmap/backlog.md P250-P265); questcheck `--oct14-only [P2xx]`. `render` draws
// a frame from a point (the Quest renderer, next to `--render`'s PNG) when the harness has one.
enum PlaytestOct14Tests {
    static func run(_ g: Game, only: String?, render: ((String, V3, Float, Float) -> Void)?, check: (Bool, String) -> Void) {
        func on(_ id: String) -> Bool { only == nil || only == id }
        if on("P250") { p250(g, check: check) }
        if on("P251") { p251(g, render: render, check: check) }
        if on("P253") { p253(g, check: check) }
        if on("P254") { p254(g, check: check) }
        if on("P255") { p255(g, check: check) }
    }

    // P250: (a) the render distance the player sets holds unless frames really suffer and comes back when they stop;
    // (b) woods past the chunks stand as their canopy in leaf colours; (c) so the skyline carries on at the seam.
    static func p250(_ g: Game, check: (Bool, String) -> Void) {
        check(RenderDistanceGovernorTest.run() == 0, "P250 (a): the governor keeps 24 through a loading burst, drops on a real slump and climbs back to 24")
        guard let gen = g.world.gen as? WorldGen else { check(false, "P250: an overworld"); return }
        // A forest column and a plains column from the generator, then their middle-ring samples.
        var forest: (Int, Int)?, plains: (Int, Int)?
        search: for r in stride(from: 0, through: 4000, by: 64) { for a in 0..<16 {
            let t = Float(a) * .pi / 8
            let x = Int(cosf(t) * Float(r)), z = Int(sinf(t) * Float(r))
            let k = gen.columnData(x, z), b = gen.terrain.biome(k, k.h)
            if forest == nil && (b == .forest || b == .darkForest) && FarRing.canopy(gen, b, x, z, ground: k.h).cover > 0.4 { forest = (x, z) }
            if plains == nil && b == .plains && k.wl < k.h { plains = (x, z) }
            if forest != nil && plains != nil { break search }
        } }
        guard let f = forest, let p = plains else { check(false, "P250 (b): a forest and a plains column within 4000 blocks"); return }
        let fs = FarRing.sample(gen, f.0, f.1), ps = FarRing.sample(gen, p.0, p.1)
        let fk = gen.columnData(f.0, f.1), pk = gen.columnData(p.0, p.1)
        let fUp = fs.y - (Float(YOFF) + fk.h + 1), pUp = ps.y - (Float(YOFF) + pk.h + 1)
        let green = fs.c.y / max(0.01, (fs.c.x + fs.c.y + fs.c.z) / 3)
        check(fUp > 4 && pUp < 0.5, String(format: "P250 (b, c): a forest far off stands %.1f blocks over its ground as canopy (open plains %.1f)", fUp, pUp))
        check(fs.c.y < ps.c.y && green > 1.05, String(format: "P250 (b): in leaf colours, darker than the plains' grass (green %.2f vs %.2f)", fs.c.y, ps.c.y))
    }

    // P251: (a) on foot in survival, the Capital's helicopter on its pad can be boarded and flown off; (b) its rotor turns.
    static func p251(_ g: Game, render: ((String, V3, Float, Float) -> Void)?, check: (Bool, String) -> Void) {
        let w = g.world
        let wasPos = g.player.pos, wasSurvival = g.survival, wasFlying = g.player.flying
        let sx = Int(floor(g.player.pos.x)) + 40, sz = Int(floor(g.player.pos.z))
        _ = w.loadSync(center: V3(Float(sx), 200, Float(sz)), radius: 3)
        let Y = min(CH - 40, w.topY(sx, sz) + 40)
        let stone = Blocks.id("smooth_stone")
        w.deferRemesh = true
        for dz in -12...12 { for dx in -12...12 {
            for y in Y...(Y + 20) where !w.isAir(sx + dx, y, sz + dz) { w.setBlock(sx + dx, y, sz + dz, AIR) }
            w.setBlock(sx + dx, Y, sz + dz, stone)
        } }
        w.deferRemesh = false
        defer {
            for s in w.ships.list where s.role == "kestrel" { w.ships.remove(s) }
            w.ships.pilot = nil; w.ships.aboard = nil
            w.deferRemesh = true
            for dz in -12...12 { for dx in -12...12 { w.setBlock(sx + dx, Y, sz + dz, AIR) } }
            w.deferRemesh = false
            g.player.pos = wasPos; g.survival = wasSurvival; g.player.flying = wasFlying
        }
        let padTop = Float(Y + 1)
        let k = Aircraft.spawn("kestrel", at: V3(Float(sx) + 0.5, padTop + 3, Float(sz) + 0.5), yaw: .pi, game: g, crewed: false)
        let dt: Float = 1.0 / 60
        for _ in 0..<180 { w.ships.update(dt, game: g) }
        // (a) A step up to the door on both sides: pad -> step -> cabin floor, a block each.
        let lo = Aircraft.kestrel().cells.keys.reduce(IVec3(Int.max, Int.max, Int.max)) { IVec3(min($0.x, $1.x), min($0.y, $1.y), min($0.z, $1.z)) }
        func cell(_ x: Int, _ y: Int, _ z: Int) -> BlockID { k.grid.get(x - lo.x, y - lo.y, z - lo.z) }
        let stepL = cell(-3, 0, -1), stepR = cell(3, 0, -1), floorR = cell(2, 1, -1), doorR = cell(2, 2, -1), headR = cell(2, 3, -1)
        check(Blocks.collide[Int(stepL)] && Blocks.collide[Int(stepR)] && Blocks.collide[Int(floorR)] && doorR == AIR && headR == AIR,
              "P251 (a): a step outside each door, a block over the pad and a block under the cabin floor (\(Blocks.key(stepL)), \(Blocks.key(stepR)), door \(Blocks.key(doorR)))")
        // On foot on the pad beside it, survival: the use button takes the controls.
        g.survival = true; g.player.flying = false
        g.player.pos = k.toWorld(V3(Float(4 - lo.x) + 0.5, 0.05, Float(-1 - lo.z) + 0.5)); g.player.vel = .zero
        g.player.pos.y = padTop
        let can = g.commandeerable()
        check(can === k, "P251 (a): standing on the pad beside the Kestrel, use takes its controls (\(can?.name ?? "none"))")
        guard can === k else { return }
        g.takeCommand(k)
        check(w.ships.pilot === k, "P251 (a): the player is at the Kestrel's controls")
        // Collective up (jump) for 6 s: it lifts off the pad.
        var input = MoveInput()
        input.jump = true
        let y0 = k.pos.y, spin0 = k.flight?.spin ?? 0
        var turned: Float = 0, last = spin0
        for _ in 0..<360 {
            if !g.pilotTick(k, input, dt) { break }
            w.ships.update(dt, game: g)
            let sp = k.flight?.spin ?? last
            turned += sp >= last ? sp - last : sp + 2 * .pi - last
            last = sp
        }
        check(k.pos.y - y0 > 3, String(format: "P251 (a): in survival the collective lifts it off the pad (%.1f blocks up in 6 s)", k.pos.y - y0))
        // (b) The rotor turns while it flies (drawn on the Quest by ShipDraw like the Mac's ShipRenderer).
        check(turned > 1 && k.flight?.kind == .heli && !k.rotors.isEmpty, String(format: "P251 (b): the rotor turns (%.0f rad in 6 s)", turned))
        render?("p251_kestrel", k.pos + V3(-9, 2, 9), atan2f(-9, 9), -0.12)
    }


    // P253: (a) under a clear sky nothing fogs: no fog bank and no valley mist at dawn, dusk or night; (b) foggy weather
    // overcasts the sky first and only then fogs.
    static func p253(_ g: Game, check: (Bool, String) -> Void) {
        let t0 = g.time, rain0 = g.weather.rain, raining0 = g.weather.raining
        defer {
            g.time = t0; g.weather.rain = rain0; g.weather.raining = raining0
            WeatherWar.fogOn = false; WeatherWar.fog = 0; WeatherWar.fogTimer = 1200; g.weatherWarTick(0)
        }
        g.weather.rain = 0; g.weather.raining = false
        WeatherWar.forceStorm = nil; WeatherWar.fogOn = false; WeatherWar.fog = 0; WeatherWar.fogTimer = 1e9
        var clear: [String] = []
        for (name, f) in [("dawn", 0.02), ("noon", 0.25), ("dusk", 0.48), ("night", 0.75)] as [(String, Double)] {
            g.time = DAY_LENGTH * (40 + f)
            g.weatherWarTick(1)
            if g.weatherFogEnd != nil || g.valleyMist > 0 { clear.append(name) }
        }
        check(clear.isEmpty, "P253 (a): under a clear sky no fog bank and no valley mist at dawn, noon, dusk or night (fogged: \(clear.isEmpty ? "none" : clear.joined(separator: ", ")))")
        // Foggy weather: the sky overcasts, then the fog comes in (once a second, as the HUD tick runs it).
        g.time = DAY_LENGTH * 40.3
        let cover0 = g.cloudCover
        WeatherWar.fogOn = true
        var coverAtFog: Float = -1, secs = 0, thick: Float = 999
        for s in 1...240 {
            g.weatherWarTick(1)
            if coverAtFog < 0, g.weatherFogEnd != nil { coverAtFog = g.cloudCover; secs = s }
            thick = g.weatherFogEnd ?? 999
        }
        check(coverAtFog > 0.9 && thick < 60 && g.valleyMist > 0.4,
              String(format: "P253 (b): foggy weather clouds the sky over first (cover %.2f -> %.2f when the fog starts after %d s), then the view closes to %.0f blocks", cover0, coverAtFog, secs, thick))
    }

    // P254: base crates and barrels hold bulk building materials.
    static func p254(_ g: Game, check: (Bool, String) -> Void) {
        let building = Set(BaseMaterials.table.entries.map { $0.0 })
        func blocks(_ c: ItemContainer) -> Int { c.slots.filter { !$0.isEmpty && building.contains(Items.key($0.item)) }.reduce(0) { $0 + $1.count } }
        // The layouts: store barrels of building blocks and the crate stacks in Greywall yards and a Capital armoury.
        let crate = Blocks.id(BaseMaterials.crate)
        func count(_ span: ClosedRange<Int>, _ build: (inout StructWriter) -> Void) -> (barrels: Int, blocks: Int, crates: Int) {
            var barrels = 0, n = 0, crates = 0
            for cz in span { for cx in span {
                var buf = [BlockID](repeating: AIR, count: CS * CS * CH)
                buf.withUnsafeMutableBufferPointer { b in
                    var w = StructWriter(bx: cx * CS, bz: cz * CS, blocks: b.baseAddress!)
                    build(&w)
                    for (_, be) in w.entities where be.kind == .chest {
                        let k = blocks(be.container)
                        if k >= 150 { barrels += 1; n += k }
                    }
                }
                crates += buf.filter { $0 == crate }.count
            } }
            return (barrels, n, crates)
        }
        let garrison = count(-3...2) { Greywall.build(&$0, 0, 100, 0, .garrison, 4242) }
        let fortress = count(-3...2) { Greywall.build(&$0, 0, 100, 0, .fortress, 4242) }
        let capital = count(-4...3) { CapitalBase.build(&$0, 0, 100, 0, 4242) }
        check(garrison.barrels >= 1 && fortress.barrels >= 3 && capital.barrels >= 5 && capital.blocks / max(1, capital.barrels) >= 300,
              "P254: store barrels of building blocks: a Greywall garrison \(garrison.barrels) (\(garrison.blocks) blocks, \(garrison.crates) crates), a fortress \(fortress.barrels) (\(fortress.blocks), \(fortress.crates) crates), a Capital citadel \(capital.barrels) (\(capital.blocks), \(capital.crates) crates)")
        // A base's crate in the world opens with a few hundred blocks in it, the same every time; broken, it spills them
        // and leaves no crate to place again.
        let w = g.world
        let p = IVec3(Int(floor(g.player.pos.x)) + 3, Int(floor(g.player.pos.y)) + 2, Int(floor(g.player.pos.z)))
        let was = w.block(p.x, p.y, p.z), surv = g.survival
        defer { w.blockEntities[p] = nil; w.setBlock(p.x, p.y, p.z, was); g.closeMenu(); g.drops.items.removeAll(); g.survival = surv }
        w.setBlock(p.x, p.y, p.z, crate); w.blockEntities[p] = nil
        let opens = g.isInteractive(p)
        g.openBlock(p)
        func items(_ c: ItemContainer) -> Int { c.slots.filter { !$0.isEmpty }.reduce(0) { $0 + $1.count } }
        let title = g.menu?.title ?? "none", inside = items(g.crateEntity(p).container)
        g.closeMenu()
        g.openBlock(p)
        let again = items(g.crateEntity(p).container)
        g.closeMenu()
        g.drops.items.removeAll()
        g.survival = true
        g.breakBlock(p, crate, drop: true)
        let spilled = g.drops.items.filter { Items.key($0.stack.item) != BaseMaterials.crate }.reduce(0) { $0 + $1.stack.count }
        let crateDrop = g.drops.items.contains { Items.key($0.stack.item) == BaseMaterials.crate }
        check(opens && title == "Supply Crate" && again == inside && spilled == inside && !crateDrop
              && Blocks.def(crate).display == "Supply Crate",
              "P254: a base's Supply Crate opens with \(inside) items (\(title)), keeps them, and broken spills \(spilled) with no crate to place again")
        // P499: a crate holds a stack or two at most, about half none (each held 6-9 full stacks of building blocks).
        var empty = 0, most = 0, stacks = 0
        for k in 0..<200 {
            let q = IVec3(p.x + 1000 + k * 7, p.y, p.z - 3000)
            let c = g.crateEntity(q).container
            let n = c.slots.filter { !$0.isEmpty }.count
            if n == 0 { empty += 1 }
            most = max(most, n); stacks += n
            w.blockEntities[q] = nil
        }
        check(empty >= 60 && empty <= 150 && most <= 2,
              "P499: supply crates are sparse: \(empty) of 200 empty, at most \(most) stacks in one (\(stacks) stacks in all)")
    }

    // P255: small Greywall outposts: (a) an extra variant, never instead of a big base; (b) a little bigger; (c) no glare
    // off the lights; (d) a gun on every tower; (e) a second floor.
    static func p255(_ g: Game, check: (Bool, String) -> Void) {
        // (a) The regions round spawn: the big bases' regions roll garrison, fortress or command only; outposts come in
        // regions of their own.
        var never = true
        for i in 0..<2000 { if Greywall.tier(roll: Float(i) / 2000, dist: 600 + (i * 37) % 4000) == .outpost { never = false } }
        var byTier: [Greywall.Tier: Int] = [:]
        if let sc = g.world.gen.structures, let type = sc.types.first(where: { $0.name == Greywall.kind }) {
            let o = Game.spawnOrigin(seed: g.world.seed)
            let orx = floorDiv(floorDiv(o.0, CS), Greywall.spacing), orz = floorDiv(floorDiv(o.1, CS), Greywall.spacing)
            for rz in (orz - 5)...(orz + 5) { for rx in (orx - 5)...(orx + 5) {
                if let s = sc.start(type, regionX: rx, regionZ: rz) { byTier[Greywall.Tier.of(s), default: 0] += 1 }
            } }
        }
        let outposts = byTier[.outpost] ?? 0, big = (byTier[.garrison] ?? 0) + (byTier[.fortress] ?? 0) + (byTier[.command] ?? 0)
        check(never && outposts > 0 && Float(big) > Float(outposts) * 1.5,
              "P255 (a): outposts are an extra variant: a big base's region never rolls one; round spawn \(big) big bases (still the most) and \(outposts) outposts (\(Greywall.Tier.allCases.map { "\($0) \(byTier[$0] ?? 0)" }.joined(separator: ", ")))")
        // (b) A little bigger.
        let t = Greywall.Tier.outpost
        check(t.half == 18 && t.keepX == 7 && t.keepZ == 7 && t.wallH == 6 && t.troops == 8,
              "P255 (b): an outpost is a little bigger: walls \(t.half * 2) blocks across (was 28), keep \(t.keepX * 2 + 1) x \(t.keepZ * 2 + 1) (was 13 x 13), \(t.troops) troops (was 6)")
        // (c) No halo off the bases' flat electric lights; flames keep theirs.
        let flat = ["light_panel", "corner_lamp", "alarm_lamp", "alarm_lamp_lit", "greywall_terminal"].filter { Blocks.has($0) }
        let haloed = flat.filter { LightHalos.color[Int(Blocks.id($0))] != .zero }
        let flames = ["torch", "lantern"].filter { Blocks.has($0) && LightHalos.color[Int(Blocks.id($0))] != .zero }
        check(haloed.isEmpty && flames.count == 2, "P255 (c): no glare disc on the bases' lights (\(flat.count) checked, haloed: \(haloed.isEmpty ? "none" : haloed.joined(separator: ", "))); torches and lanterns keep theirs")
        // (d, e) Laid out: a gun on each tower roof, and an upper floor up a stair with a watch room.
        let S = 100
        var mobs: [(String, V3)] = [], chestsUp = 0, upper = 0, stairs = 0
        let stairID = Blocks.groupBase[Int(Blocks.id("bunker_concrete_stairs[west]"))]
        for cz in -2...1 { for cx in -2...1 {
            var buf = [BlockID](repeating: AIR, count: CS * CS * CH)
            buf.withUnsafeMutableBufferPointer { b in
                var w = StructWriter(bx: cx * CS, bz: cz * CS, blocks: b.baseAddress!)
                Greywall.build(&w, 0, S, 0, .outpost, 777)
                mobs += w.mobs
                chestsUp += w.entities.filter { $0.0.y == S + 6 && $0.1.kind == .chest }.count
            }
            for lz in 0..<CS { for lx in 0..<CS {
                let x = cx * CS + lx, z = cz * CS + lz
                guard abs(x) < t.keepX, z > t.keepC - t.keepZ, z < t.keepC + t.keepZ else { continue }
                if buf[Chunk.index(lx, S + 5, lz)] != AIR { upper += 1 }
                for y in (S + 1)...(S + 4) where Blocks.groupBase[Int(buf[Chunk.index(lx, y, lz)])] == stairID { stairs += 1 }
            } }
        } }
        let towerGuns = t.towers.filter { tw in
            let c = Greywall.tower(t, tw.0, tw.1)
            return mobs.contains { $0.0.hasPrefix("deck_gun") && abs($0.1.x - Float(c.x) - 0.5) < 1 && abs($0.1.z - Float(c.z) - 0.5) < 1 }
        }.count
        let garrisonGuns: Int = {
            var n = 0
            let gt = Greywall.Tier.garrison
            for cz in -3...2 { for cx in -3...2 {
                var buf = [BlockID](repeating: AIR, count: CS * CS * CH)
                buf.withUnsafeMutableBufferPointer { b in
                    var w = StructWriter(bx: cx * CS, bz: cz * CS, blocks: b.baseAddress!)
                    Greywall.build(&w, 0, S, 0, gt, 777)
                    n += w.mobs.filter { m in m.0.hasPrefix("deck_gun:light") && gt.towers.contains { tw in let c = Greywall.tower(gt, tw.0, tw.1); return abs(m.1.x - Float(c.x) - 0.5) < 1 && abs(m.1.z - Float(c.z) - 0.5) < 1 } }.count
                }
            } }
            return n
        }()
        check(towerGuns == t.towers.count && garrisonGuns == Greywall.Tier.garrison.towers.count,
              "P255 (d): a gun on every tower (outpost \(towerGuns) of \(t.towers.count), garrison \(garrisonGuns) of \(Greywall.Tier.garrison.towers.count))")
        let inner = (t.keepX * 2 - 1) * (t.keepZ * 2 - 1)
        // (P485: a one-wide stair where the mess room's door is beside its foot: 4 steps, was always 8.)
        check(t.floors == 2 && upper * 10 >= inner * 8 && stairs >= 4 && chestsUp >= 1,
              "P255 (e): the outpost's keep has a second floor (\(upper) of \(inner) cells floored, \(stairs) stair blocks up, \(chestsUp) chest upstairs)")
        // P499 (Oct 30 15:06, "where are the bases with the second floors?"): a garrison on new ground has one too; one on
        // ground saved before keeps its single floor.
        func keep(_ up: Bool) -> (stairs: Int, roofed: Int, chests: Int, men: Int) {
            let gt = Greywall.Tier.garrison
            var st = 0, roofed = 0, ch = 0, men = 0
            for cz in -3...2 { for cx in -3...2 {
                var buf = [BlockID](repeating: AIR, count: CS * CS * CH)
                buf.withUnsafeMutableBufferPointer { b in
                    var w = StructWriter(bx: cx * CS, bz: cz * CS, blocks: b.baseAddress!)
                    Greywall.build(&w, 0, S, 0, gt, 777, upper: up)
                    ch += w.entities.filter { $0.0.y == S + 6 && $0.1.kind == .chest }.count
                    men += w.mobs.filter { $0.0.hasPrefix("soldier") && Int(floor($0.1.y)) == S + 6 }.count
                }
                for lz in 0..<CS { for lx in 0..<CS {
                    let x = cx * CS + lx, z = cz * CS + lz
                    guard abs(x) < gt.keepX, z > gt.keepC - gt.keepZ, z < gt.keepC + gt.keepZ else { continue }
                    for y in (S + 1)...(S + 4) where Blocks.groupBase[Int(buf[Chunk.index(lx, y, lz)])] == stairID { st += 1 }
                    if buf[Chunk.index(lx, S + 7, lz)] == AIR && buf[Chunk.index(lx, S + 10, lz)] != AIR { roofed += 1 }
                } }
            } }
            return (st, roofed, ch, men)
        }
        let newK = keep(true), oldK = keep(false)
        let gInner = (Greywall.Tier.garrison.keepX * 2 - 1) * (Greywall.Tier.garrison.keepZ * 2 - 1)
        check(newK.stairs >= 4 && newK.roofed * 10 >= gInner * 6 && newK.chests >= 1 && newK.men >= 1 && oldK.stairs == 0 && oldK.roofed == 0,
              "P499 garrison: a new garrison's keep has an upper floor (\(newK.stairs) stair blocks, \(newK.roofed) of \(gInner) cells roofed over a second storey, \(newK.chests) chest and \(newK.men) soldier upstairs); an old one keeps one floor (\(oldK.stairs) stairs, \(oldK.roofed) cells)")
        // P499 (15:13, "instead of golden apples... some sort of medication... that only exists at bases"): a Field Stim
        // gives a golden apple's regeneration and absorption, and is spent; nothing crafts one. P501 (Oct 31 09:56, "How
        // do I use it?"): it goes in on one click of use, mending 6 at once, with its rush at the edges of the view.
        let surv0 = g.survival, held0 = g.inventory.held, hp0 = g.health
        g.survival = true; g.health = 4; g.stimFlash = 0
        g.inventory.held = ItemStack(Items.id("field_stim"), 2)
        let pitch0 = g.player.pitch
        g.player.pitch = 1.45                           // (at the sky: nothing under the laser)
        g.input.rightClicked = true; g.input.rightDown = true
        g.tick(1.0 / 60)
        g.input.rightClicked = false; g.input.rightDown = false; g.player.pitch = pitch0
        let left = g.inventory.held.item == Items.id("field_stim") ? g.inventory.held.count : 0
        let buffed = g.effects.has(.absorption) && g.effects.has(.regeneration)
        let mended = g.health, rush = g.stimFlash
        let crafted = Recipes.all.contains { Items.key($0.result.item).hasSuffix("_stim") }
        g.foodEffects("milk_bucket")                    // (clears the effects and the absorption again)
        g.survival = surv0; g.inventory.held = held0; g.health = hp0; g.stimFlash = 0
        check(buffed && left == 1 && mended >= 10 && rush > 1 && !crafted,
              "P499/P501 stims: one click injects a Field Stim (health 4 -> \(mended), absorption and regeneration \(buffed), rush \(rush)), one is spent (\(left) left), none crafted (\(!crafted))")
        // P499 (15:14, "an assault shotgun... one of the top level troops guns... rapid fire shotguns, shotgun shells").
        let asg = Guns.all[Guns.autoShotgun]
        let carried = TroopClass.pickGun(.hannibal, .soldierTrooper, roll: 0.9) == Guns.autoShotgun
        check(asg.key == "gun_autoshotgun" && asg.auto && asg.pellets > 1 && asg.ammo == "shotgun_shells" && carried && Items.has(asg.key)
              && CapitalArms.models[Guns.autoShotgun].parts.count > 12 && Guns.rotary == Guns.faust + 1 && Guns.all[Guns.rotary].key == "gun_rotary",
              "P499 assault shotgun: the \(asg.name) fires \(asg.pellets) pellets automatically from shotgun shells, a Hannibal trooper carries it (\(carried)); the Faustrohr and Mahlwerk keep their indices")
        // P499 (20:31, 64 TNT: "it took too long for the damage to show up"): a face blasted all round keeps at most 25
        // grid lines each way; a lone bullet hole keeps every ring.
        var blasted: [(Int, Int, Int, Bite)] = []
        for x in 4...6 { for y in 4...6 { for z in 4...6 { for i in 0..<8 {
            let a = Float(i) * 0.785 + Float(x * 3 + y * 5 + z * 7)
            blasted.append((x, y, z, Bite(c: SIMD3<Float>(0.5 + 0.4 * cosf(a), 0.5 + 0.4 * sinf(a), Float(i) / 8), n: simd_normalize(SIMD3<Float>(cosf(a), 0.5, sinf(a))),
                                          r: 0.25 + 0.03 * Float(i), d: 0.2, seed: UInt32(i * 977 + x * 31 + y * 17 + z))))
        } } } }
        let face: [SIMD3<Float>] = [SIMD3(5, 7, 5), SIMD3(6, 7, 5), SIMD3(6, 7, 6), SIMD3(5, 7, 6)]
        let wall = CraterSet(blasted, sy: 0, wo: .zero) { x, y, z in x + y * 48 + z * 2304 }.ticks(face, base: 6)
        let hole = CraterSet([(5, 6, 5, Bite(c: SIMD3<Float>(0.5, 1, 0.5), n: SIMD3<Float>(0, 1, 0), r: 0.08, d: 0.06, seed: 7))], sy: 0, wo: .zero) { x, y, z in x + y * 48 + z * 2304 }.ticks(face, base: 6)
        check(wall.s.count <= 25 && wall.t.count <= 25 && hole.s.count > 12,
              "P499 crater grid: a face blasted all round \(wall.s.count) x \(wall.t.count) lines (at most 25), a lone bullet hole \(hole.s.count) (every ring)")
        // P499 (15:14, "we shouldn't have void pearls. No reason for those to exist").
        let pearl = Items.id("ender_pearl")
        func uses(_ r: Recipe, _ k: String) -> Bool { r.shapeless.contains(k) || r.cells.contains(k) }
        let crafts = Recipes.all.filter { uses($0, "ender_pearl") }.map { Items.key($0.result.item) }
        let dropped = MobKind.allCases.filter { k in k.spec.drops.contains { $0.0 == "ender_pearl" } }.map { "\($0)" }
        let eye = Recipes.all.contains { Items.key($0.result.item) == "ender_eye" && uses($0, "amethyst_shard") }
        check(!CreativeMenu.every.contains(pearl) && crafts.isEmpty && dropped.isEmpty && eye && !Director.rareGoods.contains("ender_pearl"),
              "P499 void pearls: out of the palette; recipes using one \(crafts), mobs dropping one \(dropped); a Seeker Eye from amethyst (\(eye))")
    }



}
