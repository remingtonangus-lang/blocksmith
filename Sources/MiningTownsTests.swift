import Foundation
import simd

// Mining towns (backlog C12), `questcheck --mines-only`:
//   share      over the villages of 7x7 regions round spawn, the bigger towns work a mine (and only they); no abandoned
//              mineshaft starts on new ground
//   built      the mine nearest spawn: head frame and named sign, a ladder all the way down, both levels' drifts on rails
//              with supports and lamps, the stores (chest and TNT), the deep vein's ore, the old cave-in; miners and carts
//   loose      breaking a lagging board brings the gravel above down; knocking out a support post caves the roof in
//   gas        a lantern warns of the pocket; inside it you choke; a torch in hand sets it off (once; it stays spent
//              through a save)
//   law        the workings are company ground (no theft), the head frame is the town's
//   miners     a miner works their face at midnight too
enum MiningTownsTests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let saved = TownLaw.state, pos = g.player.pos, health = g.health, held = g.inventory.main[g.inventory.selected], surv = g.survival
        defer {
            TownLaw.state = saved; g.player.pos = pos; g.health = health; g.inventory.main[g.inventory.selected] = held; g.survival = surv
        }
        g.survival = true
        guard let sc = g.world.gen.structures, let vt = sc.types.first(where: { $0.name == "village" }) else {
            check(false, "C12: no structures"); return
        }
        // Share.
        let p0 = g.player.pos
        let rx0 = floorDiv(floorDiv(Int(p0.x), CS), vt.spacing), rz0 = floorDiv(floorDiv(Int(p0.z), CS), vt.spacing)
        var towns = 0, mines: [StructureStart] = [], smallWith = 0
        for rz in (rz0 - 3)...(rz0 + 3) { for rx in (rx0 - 3)...(rx0 + 3) {
            guard let s = sc.start(vt, regionX: rx, regionZ: rz) else { continue }
            towns += 1
            if let m = s.plan as? Mine { mines.append(s); if m.lots < MiningTowns.minLots { smallWith += 1 } }
        } }
        var shafts = 0
        if let mt = sc.types.first(where: { $0.name == "mineshaft" }) {
            let r0 = floorDiv(floorDiv(Int(p0.x), CS), mt.spacing), q0 = floorDiv(floorDiv(Int(p0.z), CS), mt.spacing)
            for rz in (q0 - 3)...(q0 + 3) { for rx in (r0 - 3)...(r0 + 3) where sc.start(mt, regionX: rx, regionZ: rz) != nil { shafts += 1 } }
        }
        let share = towns > 0 ? Float(mines.count) / Float(towns) : 0
        check(towns >= 4 && share >= 0.12 && share <= 0.75 && smallWith == 0 && shafts == 0,
              "C12 share: \(mines.count) of \(towns) towns work a mine (\(Int(share * 100))%), small towns with one \(smallWith); abandoned mineshafts on new ground \(shafts)")
        guard let start = mines.min(by: { simd_length(V2(Float($0.anchor.x) - p0.x, Float($0.anchor.z) - p0.z)) < simd_length(V2(Float($1.anchor.x) - p0.x, Float($1.anchor.z) - p0.z)) }),
              let m = start.plan as? Mine else { check(false, "C12: no mining town near spawn"); return }

        // Built.
        let w = g.world
        let sh = m.shaft
        g.player.pos = V3(Float(sh.x) + 0.5, Float(sh.y + 1), Float(sh.z) + 0.5)
        _ = w.loadSync(center: g.player.pos, radius: 4)
        func key(_ p: IVec3) -> String { Blocks.key(Blocks.groupBase[Int(w.block(p.x, p.y, p.z))]) }
        let lx = sh.x + m.out.0, lz = sh.z + m.out.1
        let ladders = (m.levels[1]...sh.y).filter { key(IVec3(lx, $0, lz)) == "ladder" }.count
        let posts = [(-2, -2), (2, -2), (-2, 2), (2, 2)].filter { c in (1...7).allSatisfy { key(IVec3(sh.x + c.0, sh.y + $0, sh.z + c.1)) == "oak_log" } }.count
        var sign = ""
        for (p, be) in w.blockEntities where abs(p.x - sh.x) <= 4 && abs(p.z - sh.z) <= 4 && p.y > sh.y && be.lines[1] == "Shaft No. 1" { sign = be.lines[0] }
        check(ladders == sh.y - m.levels[1] + 1 && posts == 4 && sign == ShopMenu.fit(m.name, 88),
              "C12 head frame: \(posts) corner posts, the sign \"\(sign)\", a ladder \(ladders) of \(sh.y - m.levels[1] + 1) rungs from the deck to No. 2 level (y \(m.levels[1] - YOFF))")
        var rails = 0, cells = 0, lamps = 0
        for d in m.drifts {
            for s in 0..<d.len { cells += 1; if key(Mine.at(d, s, 0, 0)) == "rail" { rails += 1 } }
            for s in stride(from: 2, to: d.len - 1, by: 4) where key(Mine.at(d, s, 1, 2)) == "lantern" { lamps += 1 }
        }
        let supports = m.supports.filter { key($0) == "oak_log" || key($0) == "oak_fence" }.count
        let chest = w.blockEntities[m.stores]
        let stores = chest?.container.slots.filter { !$0.isEmpty }.count ?? 0
        let tnt = key(m.powder) == "tnt" && key(m.powder + IVec3(0, 1, 0)) == "tnt"
        let caveIn = m.caveIn.filter { key($0) == "gravel" }.count
        check(Float(rails) >= Float(cells - m.caveIn.count / 4) * 0.9 && lamps >= 6 && supports >= m.supports.count * 8 / 10 && stores >= 4 && tnt && caveIn >= 30,
              "C12 drifts: \(rails) of \(cells) drift blocks railed, \(lamps) lamps, \(supports) of \(m.supports.count) support posts, the stores chest holds \(stores) stacks, TNT in the powder niche \(tnt), the old fall \(caveIn) gravel")
        var ore: [String: Int] = [:]
        let deep = m.drifts[2]
        for s in (deep.len - 1)...(deep.len + 7) { for ww in -4...4 { for h in -1...5 {
            let k = key(Mine.at(deep, s, ww, h))
            if k.hasSuffix("_ore") { ore[k, default: 0] += 1 }
        } } }
        let ores = ore.values.reduce(0, +)
        let titanium = (ore["deepslate_diamond_ore"] ?? 0) + (ore["diamond_ore"] ?? 0)
        check(ores >= 60 && titanium >= 4,
              "C12 deep vein: \(ores) ore blocks round the chamber at y \(m.vein.y - YOFF) (\(titanium) titanium, \(ore.filter { $0.key.contains("gold") }.values.reduce(0, +)) gold)")
        let pend = w.pendingMobs.map { $0.0 } + g.mobs.mobs.compactMap { $0.villager?.role == "miner" ? "villager:miner" : nil }
        let miners = pend.filter { $0 == "villager:miner" }.count, carts = pend.filter { $0 == "minecart" }.count
        check(miners >= 3 && carts >= 2, "C12 crew: \(miners) miners and \(carts) mine carts placed")

        // Loose ground and supports.
        let board = m.loose[1]
        let before = g.falling.count
        let wasBoard = key(board) == "oak_planks" && key(board + IVec3(0, 1, 0)) == "gravel"
        w.setBlock(board.x, board.y, board.z, AIR)
        for _ in 0..<3 { g.gravityTick() }
        let fell = g.falling.count > before
        let post = m.supports.first { p in key(p) == "oak_log" && m.drift(at: p)?.0.level == m.levels[0] && !m.loose.contains { abs($0.x - p.x) + abs($0.z - p.z) <= 3 } }
        let n0 = g.falling.count, c0 = MiningTowns.caveIns
        if let p = post { g.breakBlock(p, w.block(p.x, p.y, p.z), drop: false); w.setBlock(p.x, p.y, p.z, AIR) }
        for _ in 0..<3 { g.gravityTick() }
        check(wasBoard && fell && post != nil && MiningTowns.caveIns == c0 + 1 && g.falling.count > n0,
              "C12 loose ground: lagging under gravel \(wasBoard); the board out, the gravel falls \(fell); a support post knocked out caves the roof in (\(g.falling.count - n0) blocks falling)")

        // Gas.
        let gc = m.gas[0]
        let side = m.drifts[3]
        let gasAt = V3(Float(gc.x) + 0.5, Float(gc.y - 1), Float(gc.z) + 0.5)
        g.inventory.main[g.inventory.selected] = ItemStack(Items.id("lantern"), 1)
        g.player.pos = gasAt - V3(Float(side.dx), 0, Float(side.dz)) * 7
        MiningTowns.warned = []
        MiningTowns.tick(g)
        let warned = MiningTowns.warned.contains(MiningTowns.key(gc))
        g.inventory.main[g.inventory.selected] = ItemStack(Items.id("bread"), 1)
        g.player.pos = gasAt
        MiningTowns.tick(g)
        let choke = g.effects.level(.nausea) > 0 && g.effects.level(.poison) > 0 && !MiningTowns.spent(gc)
        let i0 = MiningTowns.ignitions
        g.health = 20
        g.inventory.main[g.inventory.selected] = ItemStack(Items.id("torch"), 4)
        MiningTowns.tick(g)
        let blew = MiningTowns.ignitions == i0 + 1 && MiningTowns.spent(gc)
        g.health = 20
        MiningTowns.tick(g)
        let once = MiningTowns.ignitions == i0 + 1
        var kept = false
        if let data = try? JSONEncoder().encode(TownLaw.state), let back = try? JSONDecoder().decode(TownLaw.Saved.self, from: data) {
            kept = back.minesSpent?.contains(MiningTowns.key(gc)) == true
        }
        check(warned && choke && blew && once && kept,
              "C12 gas: the lantern warns \(warned); inside you choke \(choke); a torch sets it off \(blew), once \(once), still spent after a save \(kept)")

        // Law.
        let workings = Mine.at(m.drifts[0], 4, 0, 1)
        let deck = IVec3(sh.x + 3, sh.y, sh.z + 3)
        check(!TownLaw.isTownOwned(g, workings) && !TownLaw.isTownOwned(g, m.stores) && TownLaw.isTownOwned(g, deck),
              "C12 law: the workings and the stores are company ground, the head frame deck is the town's")

        // Miners.
        let miner = Mob(.villager, at: V3(Float(m.stores.x), Float(m.stores.y), Float(m.stores.z)))
        Townsfolk.setup(miner, tag: "miner", game: g)
        check(miner.villager?.role == "miner" && miner.activity(0.8) == .work && miner.activity(0.3) == .work && miner.villager?.jobSite != nil,
              "C12 miners: a miner works the face at midnight and at noon")
    }
}
