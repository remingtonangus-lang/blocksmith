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
            for y in Y...(Y + 20) where w.block(sx + dx, y, sz + dz) != AIR { w.setBlock(sx + dx, y, sz + dz, AIR) }
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
        let title = g.menu?.title ?? "none", inside = blocks(g.crateEntity(p).container)
        g.closeMenu()
        g.openBlock(p)
        let again = blocks(g.crateEntity(p).container)
        g.closeMenu()
        g.drops.items.removeAll()
        g.survival = true
        g.breakBlock(p, crate, drop: true)
        let spilled = g.drops.items.filter { building.contains(Items.key($0.stack.item)) }.reduce(0) { $0 + $1.stack.count }
        let crateDrop = g.drops.items.contains { Items.key($0.stack.item) == BaseMaterials.crate }
        check(opens && title == "Supply Crate" && inside >= 250 && again == inside && spilled == inside && !crateDrop
              && Blocks.def(crate).display == "Supply Crate",
              "P254: a base's Supply Crate opens with \(inside) building blocks (\(title)), keeps them, and broken spills \(spilled) with no crate to place again")
    }




}
