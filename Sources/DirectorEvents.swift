import Foundation
import simd

// P266 (b): what each Director template does in the world, from systems the game already has. `start` places an
// event (false: not possible here yet, it waits in the queue), `tick` runs it once a second and ends it (Director.pay /
// Director.fail), `expire` ends it when its time is up. Everything it spawns appears out of the player's sight (k):
// sites are built when he comes within 96 blocks while still 64+ off (or 40+ and hidden by the ground), people who come
// to him start 40-60 blocks away behind him or behind terrain.
enum DirectorEvents {

    // MARK: Places

    // Dry land about `dist` blocks from `from` (the player): the generator's own heights, so unloaded ground works.
    static func landSpot(_ g: Game, dist: Float, from c: V3? = nil) -> (Int, Int)? {
        let o = c ?? g.player.pos
        for _ in 0..<16 {
            let a = Rand.float(in: 0..<(2 * .pi)), r = dist * Rand.float(in: 0.85...1.15)
            let x = Int(floor(o.x + sinf(a) * r)), z = Int(floor(o.z + cosf(a) * r))
            let col = g.world.gen.column(x, z)
            guard col.height > SEA + 1 else { continue }
            let b = col.biome.displayName.lowercased()
            if b.contains("ocean") || b.contains("river") || b.contains("beach") { continue }
            return (x, z)
        }
        return nil
    }

    // Open ground at or near (x, z) in loaded chunks: solid, dry, not a tree's crown, two blocks of air over it.
    static func ground(_ g: Game, _ x: Int, _ z: Int) -> V3? {
        let w = g.world
        for r in 0...6 {
            for k in 0..<max(1, r * 8) {
                let a = Float(k) / Float(max(1, r * 8)) * 2 * .pi
                let px = x + Int((cosf(a) * Float(r)).rounded()), pz = z + Int((sinf(a) * Float(r)).rounded())
                guard w.isLoaded(px, pz) else { continue }
                let y = w.topY(px, pz)
                let b = w.block(px, y, pz)
                guard y > 0, Blocks.collide[Int(b)], !Blocks.isLiquid(b), !Blocks.key(Blocks.groupBase[Int(b)]).hasSuffix("_leaves"),
                      !Blocks.collide[Int(w.block(px, y + 1, pz))], !Blocks.collide[Int(w.block(px, y + 2, pz))],
                      !Blocks.isLiquid(w.block(px, y + 1, pz)) else { continue }
                return V3(Float(px) + 0.5, Float(y + 1), Float(pz) + 0.5)
            }
        }
        return nil
    }

    // A site may be built now: loaded, he is within 96 blocks, and it is out of his sight (k).
    static func ready(_ g: Game, _ e: DirectorEvent) -> V3? {
        guard let a = e.at else { return nil }
        let d = simd_length(V2(a.x - g.player.pos.x, a.y - g.player.pos.z))
        guard d < 96, let p = ground(g, Int(floor(a.x)), Int(floor(a.y))) else { return nil }
        if d >= 64 { return p }
        return g.world.canSee(p + V3(0, 1.6, 0), g.player.eye) ? nil : p
    }

    // Where someone coming to him starts: 40-60 blocks off, behind him or hidden from his eyes (k). In the Emberdeep,
    // on the cavern floor near his level.
    static func nearSpot(_ g: Game, _ r: ClosedRange<Float>) -> V3? {
        let pp = g.player.pos
        let back = -V2(g.player.look.x, g.player.look.z)
        let base = atan2f(back.x, back.y)
        for k in 0..<32 {
            let a = base + Rand.float(in: -1.2...1.2) * (k < 16 ? 1 : 2.6), d = Rand.float(in: r)
            let x = Int(floor(pp.x + sinf(a) * d)), z = Int(floor(pp.z + cosf(a) * d))
            guard g.world.isLoaded(x, z) else { continue }
            let at: V3?
            if g.dim.dim == .overworld { at = ground(g, x, z) } else { at = MobManager.groundSpot(g.world, near: V3(Float(x), pp.y, Float(z))) }
            guard let p = at, abs(p.y - pp.y) < 16 else { continue }
            if k < 24 && g.world.canSee(p + V3(0, 1.6, 0), g.player.eye) { continue }
            return p
        }
        return nil
    }

    static func around(_ c: V3, _ i: Int, _ r: Float = 3) -> V3 {
        let a = Float(i) * 2.399
        return c + V3(cosf(a) * r, 0, sinf(a) * r)
    }

    // MARK: People and creatures

    // A gunman on the bounty hunters' soldier rig (no faction; trail dusters), named for the event.
    static func gunman(_ g: Game, _ name: String, rank i: Int, at p: V3, grit: Float, guardPost: Bool) -> Mob {
        let m = BountyHunters.makeHunter(g, index: i, at: g.world.freeSpawn(p))
        m.customName = name
        m.spec.name = name
        let hp = max(10, Int(Float(m.spec.health) * grit / 1.6))
        m.spec.health = hp
        m.health = hp
        if guardPost {
            m.soldierBrain.order = m.pos
            m.soldierBrain.orderRun = false
            m.home = m.pos
        }
        return m
    }

    static func soldier(_ g: Game, _ f: Faction, _ i: Int, at p: V3, name: String) -> Mob {
        let ranks: [MobKind] = [.soldierOfficer, .soldierTrooper, .soldierRecruit, .soldierMarksman, .soldierTrooper, .soldierRecruit, .soldierIronclad]
        let m = Mob(ranks[i % ranks.count], at: g.world.freeSpawn(p))
        m.faction = f.rawValue
        if m.kind == .soldierIronclad { m.variant = Guns.arc }
        if f == .greywall { m.variant = i % 3 == 0 ? Guns.repeater : Guns.slatefall }      // Greywall's own arms (P256)
        m.customName = name
        m.persistent = true
        m.home = m.pos
        return m
    }

    static func put(_ g: Game, _ e: inout DirectorEvent, _ m: Mob) {
        m.persistent = true
        g.mobs.mobs.append(m)
        Director.refs[e.id, default: []].append(m)
        if let n = m.customName, !e.names.contains(n) { e.names.append(n) }
    }

    // How many of an event's people and creatures still live, loaded or stored with the unloaded ground.
    static func alive(_ g: Game, _ e: DirectorEvent, only: String? = nil) -> Int {
        let names = only.map { [$0] } ?? e.names
        var n = 0
        for m in g.mobs.mobs where m.health > 0 { if let c = m.customName, names.contains(c) { n += 1 } }
        for (_, list) in g.mobs.stored { for r in list { if let c = r.name, names.contains(c) { n += 1 } } }
        return n
    }

    static func find(_ g: Game, _ name: String?) -> Mob? {
        guard let name else { return nil }
        return g.mobs.mobs.first { $0.customName == name && $0.health > 0 }
    }

    // MARK: Building

    static func setIfAir(_ g: Game, _ x: Int, _ y: Int, _ z: Int, _ key: String) {
        guard Blocks.has(key) else { return }
        let b = g.world.block(x, y, z)
        guard !Blocks.collide[Int(b)], !Blocks.isLiquid(b) else { return }
        g.world.setBlock(x, y, z, Blocks.id(key))
    }

    // A container of loot from a table (wreck, supply drop, outpost pay chest); returns how many items it holds.
    static func container(_ g: Game, _ x: Int, _ y: Int, _ z: Int, block: String, table: String) -> Int {
        let key = Blocks.has(block) ? block : "chest"
        g.world.setBlock(x, y, z, Blocks.id(key))
        let be = BlockEntity(.chest)
        var rng = SRng(UInt64(hash3(x, y, z, UInt32(truncatingIfNeeded: g.world.seed) ^ 0xD1EC)) | 1)
        Loot.fill(be.container, table: table, rng: &rng)
        g.world.blockEntities[IVec3(x, y, z)] = be
        return be.container.slots.reduce(0) { $0 + $1.count }
    }

    static func stock(_ g: Game, _ c: [Int]) -> Int? {
        guard c.count == 3, let be = g.world.blockEntities[IVec3(c[0], c[1], c[2])] else { return nil }
        return be.container.slots.reduce(0) { $0 + $1.count }
    }

    // Tents round a campfire (camps: hostage, outpost).
    static func camp(_ g: Game, _ c: V3, wool: String) {
        let x = Int(floor(c.x)), y = Int(floor(c.y)), z = Int(floor(c.z))
        setIfAir(g, x, y, z, "campfire")
        for (ox, oz) in [(-5, -2), (4, 2)] {
            for k in 0..<4 {
                setIfAir(g, x + ox + k, y, z + oz, wool)
                setIfAir(g, x + ox + k, y + 1, z + oz, wool)
                setIfAir(g, x + ox + k, y, z + oz + 2, wool)
            }
        }
    }

    static func lootTable(_ f: Faction) -> String {
        switch f {
        case .steelhold: return "steelhold_supply"          // Capital gear only from Capital stores (P256)
        case .greywall: return "greywall_armory"
        default: return "shipwreck_supply"
        }
    }
    static func wool(_ f: Faction) -> String {
        switch f {
        case .steelhold: return "white_wool"; case .greywall: return "gray_wool"; case .meridian: return "blue_wool"
        case .ironback: return "brown_wool"; default: return "light_blue_wool"
        }
    }

    // MARK: Start

    static func start(_ g: Game, _ e: inout DirectorEvent) -> Bool {
        let rules = DirectorRules.self
        switch e.t {
        case "town_raid", "dead_rise", "beasts", "gift", "hostage":
            guard let (town, a) = Director.nearTown(g, within: 700) else { return false }
            e.place = town
            switch e.t {
            case "town_raid":
                e.x = a.x; e.z = a.z
            case "dead_rise", "beasts":
                let ang = Rand.float(in: 0..<(2 * .pi)), r: Float = e.t == "beasts" ? 52 : 38
                e.x = a.x + Int(sinf(ang) * r); e.z = a.z + Int(cosf(ang) * r)
            case "hostage":
                guard let (x, z) = landSpot(g, dist: Float(e.num("dist")), from: V3(Float(a.x), 0, Float(a.z))) else { return false }
                e.x = x; e.z = z
                e.s["who"] = rules.person()
            default:   // gift: a messenger walks to him
                guard let p = nearSpot(g, 40...56) else { return false }
                let who = "Messenger from " + town
                let m = Mob(.villager, at: p)
                m.customName = who
                put(g, &e, m)
                e.s["who"] = who
                e.spawned = true
                e.x = Int(floor(p.x)); e.z = Int(floor(p.z))
            }
        case "bounty":
            guard let (x0, z0) = landSpot(g, dist: Float(e.num("dist"))) else { return false }
            var route = [[x0, z0]]
            for _ in 0..<2 {
                let l = route[route.count - 1]
                if let (x, z) = landSpot(g, dist: Rand.float(in: 150...250), from: V3(Float(l[0]), 0, Float(l[1]))) { route.append([x, z]) }
            }
            e.route = route; e.leg = 1
            e.x = x0; e.z = z0
        case "counteroffensive":
            let mine = g.raidPlaces().filter { $0.1 == "your home" || $0.1 == "your base" }
            guard let p = mine.first else { return false }
            e.place = p.1
            e.x = Int(floor(p.0.x)); e.z = Int(floor(p.0.z)); e.y = Int(floor(p.0.y))
            e.faction = Director.faction(e.s["faction"] ?? "capital").rawValue
            e.due = Director.state.play + e.num("lead") * 60
        case "wreck", "outpost", "supply_drop", "incursion":
            guard let (x, z) = landSpot(g, dist: Float(e.num("dist"))) else { return false }
            e.x = x; e.z = z
            e.faction = Director.faction(e.s["faction"] ?? "capital").rawValue
        case "storm":
            guard !g.weather.thundering else { return false }
            let secs = Float(e.num("minutes") * 60)
            g.weather.raining = true; g.weather.thundering = true
            g.weather.rainTime = secs; g.weather.thunderTime = secs
            e.until = Director.state.play + Double(secs) + 120
        case "eruption":
            guard g.eruption == nil, let v = Director.nearVolcano(g) else { return false }
            g.startEruption(v)
            e.x = Int(v.x); e.z = Int(v.z)
            e.place = "the volcano"
        case "trader":
            guard let p = nearSpot(g, 40...56) else { return false }
            let who = rules.person() + " the Peddler"
            let t = Mob(.wanderingTrader, at: p)
            t.villager = traderStock(e)
            t.customName = who
            put(g, &e, t)
            for k in 0..<2 {
                guard let lp = ground(g, Int(p.x) + k * 2 - 1, Int(p.z) + 2) else { continue }
                let l = Mob(.traderLlama, at: lp)
                l.target = t
                l.customName = who + "'s Llama"
                put(g, &e, l)
            }
            e.s["who"] = who
            e.spawned = true
            e.x = Int(floor(p.x)); e.z = Int(floor(p.z))
            e.until = Director.state.play + e.num("minutes") * 60
        case "rival":
            guard let p = nearSpot(g, 44...60) else { return false }
            let who = e.s["who"] ?? rules.person()
            e.s["who"] = who
            e.s["deed"] = rules.deed(g)
            let m = gunman(g, who, rank: 0, at: p, grit: Float(e.num("grit")), guardPost: false)
            m.soldierBrain.order = g.player.pos
            m.soldierBrain.orderRun = false
            put(g, &e, m)
            e.spawned = true
            e.x = Int(floor(p.x)); e.z = Int(floor(p.z))
        case "warband":
            guard let p = nearSpot(g, 30...44) else { return false }
            let n = e.int("count")
            let lead = (e.s["name"] ?? "The Brand").replacingOccurrences(of: "'s Warband", with: "")
            for i in 0..<n {
                let k: MobKind = i == 0 ? .brandChampion : (i % 2 == 1 ? .brandKnight : .brandSquire)
                guard let q = MobManager.groundSpot(g.world, near: around(p, i, 2)) else { continue }
                let m = Mob(k, at: q)
                m.customName = i == 0 ? lead : "Warband Brand"
                m.aggro = true; m.lockTime = 30
                put(g, &e, m)
            }
            guard !e.names.isEmpty else { return false }
            e.spawned = true
        case "legend":
            let i = Int(e.s["beast"] ?? "0") ?? 0
            guard i >= 0, i < Hunting.legends.count, Hunting.live(g, i) == nil,
                  let (x, z) = landSpot(g, dist: Float(e.num("dist"))) else { return false }
            e.x = x; e.z = z
            e.place = Hunting.legends[i].name.capitalizedFirst
        default:
            return false
        }
        return true
    }

    static func traderStock(_ e: DirectorEvent) -> VillagerData {
        var v = WanderingTrader.data()
        let price = max(1, e.int("price"))
        var goods: [(String, Int)] = []
        if let a = e.s["goods"] { goods.append((a, price)) }
        if let b = e.s["goods2"], b != e.s["goods"] { goods.append((b, max(1, price * 3 / 5))) }
        for (k, p) in goods where Items.has(k) && Items.has("emerald") {
            let n = k.hasSuffix("_rounds") || k.hasSuffix("_shells") ? 24 : 1
            v.offers.insert(TradeOffer(buyA: ItemStack(Items.id("emerald"), min(64, p)), buyB: .empty, sell: ItemStack(Items.id(k), n),
                                       maxUses: 3, xp: 2, priceMult: 0.05), at: 0)
        }
        return v
    }

    // MARK: Tick

    static func tick(_ g: Game, _ e: inout DirectorEvent) {
        let play = Director.state.play
        switch e.t {
        case "town_raid":
            guard let town = e.place else { return }
            if !e.fired {
                if TownLaw.inTown == town {
                    if TownRaids.night(g.dayFraction), g.raid == nil, TownRaids.start(g, town: town) { e.fired = true; e.spawned = true }
                    else if e.n["told"] == nil { e.n["told"] = 1; g.onToast?("\(town) is ready for you. The raiders will come after dark") }
                }
            } else if let won = Director.raidResults[town] {
                Director.raidResults[town] = nil
                if won { Director.pay(g, &e, dollars: e.int("reward"), honour: Float(e.num("honour"))) }
                else { e.state = 4; e.outcome = "The townsfolk beat them off without you"; Director.radio(g, caller: e.s["caller"] ?? "Radio", "They held. No thanks to the stranger who wasn't there.") }
            } else if g.raid == nil {
                Honour.change(g, -2, "raiders overran \(town)")
                Director.fail(g, &e, consequence: "Raiders overran \(town): honour lost")
            }
        case "bounty":
            if !e.spawned {
                // The gang rides its route until it camps within a few hundred blocks of him.
                if var a = e.at, let r = e.route, e.leg < r.count {
                    let d = simd_length(V2(a.x - g.player.pos.x, a.y - g.player.pos.z))
                    if d > 160 {
                        let t = V2(Float(r[e.leg][0]), Float(r[e.leg][1]))
                        let off = t - a, len = simd_length(off)
                        if len < 2 { e.leg += 1 } else { a += off / len * min(1.2, len) }
                        e.x = Int(floor(a.x)); e.z = Int(floor(a.y))
                    }
                }
                guard let p = ready(g, e) else { return }
                let lead = e.name
                let gang = (lead.split(separator: " ").last.map(String.init) ?? "Outlaw") + " Gang"
                put(g, &e, gunman(g, lead, rank: 0, at: p, grit: 2.2, guardPost: true))
                for i in 0..<e.int("posse") { put(g, &e, gunman(g, gang, rank: 1 + i, at: around(p, i + 1), grit: 1.4, guardPost: true)) }
                setIfAir(g, Int(floor(p.x)) + 2, Int(floor(p.y)), Int(floor(p.z)) + 2, "campfire")
                e.spawned = true
            } else if alive(g, e, only: e.name) == 0 {
                var poster = ItemStack(Items.id("paper"), 1)
                poster.label = "Bounty Poster: \(e.name) (paid)"
                Director.pay(g, &e, dollars: e.int("reward"), honour: Float(e.num("honour")), items: Items.has("paper") ? [poster] : [])
            }
        case "counteroffensive":
            let f = Faction(rawValue: e.faction) ?? .steelhold
            guard let a = e.at else { return }
            let c = V3(a.x, Float(e.y ?? Int(g.player.pos.y)), a.y)
            if !e.fired {
                if play >= e.due - 60 && e.n["warned"] == nil {
                    e.n["warned"] = 1
                    Director.radio(g, caller: e.s["caller"] ?? "Radio", "Dropships of \(f.name) inbound to \(e.place ?? "your place"). A minute out.")
                }
                guard play >= e.due, simd_length(V2(c.x - g.player.pos.x, c.z - g.player.pos.z)) < FactionRaids.reach,
                      FactionRaids.active == nil, g.world.ships.pilot == nil else { return }
                let y = g.world.isLoaded(Int(c.x), Int(c.z)) ? Float(g.world.topY(Int(c.x), Int(c.z)) + 1) : c.y
                e.n["beaten0"] = Double(FactionRaids.beaten)
                if g.startRaid(f, at: V3(c.x, y, c.z), place: e.place ?? "your home") > 0 { e.fired = true; e.spawned = true }
            } else if FactionRaids.active == nil {
                if Double(FactionRaids.beaten) > e.num("beaten0") { Director.pay(g, &e, dollars: e.int("reward"), honour: Float(e.num("honour"))) }
                else {
                    let lost = min(g.money / 10, 10000)
                    g.money -= lost
                    Director.fail(g, &e, consequence: "\(f.name) sacked \(e.place ?? "your place")" + (lost > 0 ? ": \(Money.format(lost)) of your stores gone" : ""))
                }
            }
        case "wreck", "supply_drop":
            if !e.spawned {
                guard let p = ready(g, e) else { return }
                let x = Int(floor(p.x)), y = Int(floor(p.y)), z = Int(floor(p.z))
                let f = Faction(rawValue: e.faction) ?? .steelhold
                if e.t == "wreck" {
                    // A broken hull: scorched planks strewn along it, a snapped mast, a smoking fire, the hold's chest.
                    for dx in -4...4 { for dz in -1...1 where hashf(dx, dz, e.id, 0xD1E1) < 0.6 {
                        setIfAir(g, x + dx, y, z + dz, "dark_oak_planks")
                        if abs(dz) == 1 && hashf(dx, dz, e.id, 0xD1E2) < 0.5 { setIfAir(g, x + dx, y + 1, z + dz, "dark_oak_planks") }
                    } }
                    for k in 0..<3 { setIfAir(g, x - 2 + k, y + 1, z, "dark_oak_log") }
                    setIfAir(g, x + 4, y + 1, z, "campfire")
                    e.chest = [x, y + 1, z + 1]
                    e.stock = container(g, x, y + 1, z + 1, block: "chest", table: e.s["loot"] ?? "shipwreck_supply")
                    for i in 0..<e.int("scavengers") { put(g, &e, gunman(g, "Scavenger", rank: 1 + i, at: around(p, i, 6), grit: 1.2, guardPost: true)) }
                } else {
                    setIfAir(g, x + 2, y, z, "campfire")                            // the smoke the crew follows
                    e.chest = [x, y, z]
                    e.stock = container(g, x, y, z, block: "barrel", table: lootTable(f))
                    for i in 0..<e.int("guards") { put(g, &e, soldier(g, f, i, at: around(p, i, 7), name: "\(f.name) Recovery Team")) }
                }
                g.particles.smoke(at: p + V3(0, 2, 0))
                e.spawned = true
            } else if let c = e.chest {
                let left = stock(g, c)
                if left == nil || left! * 2 <= e.stock { Director.pay(g, &e, dollars: 0) }
            }
        case "hostage":
            let who = e.s["who"]
            if !e.spawned {
                guard let p = ready(g, e) else { return }
                camp(g, p, wool: "brown_wool")
                let h = Mob(.villager, at: g.world.freeSpawn(p + V3(1.5, 0, 0)))
                h.customName = who
                h.home = h.pos
                put(g, &e, h)
                for i in 0..<e.int("guards") { put(g, &e, gunman(g, "Kidnapper", rank: 1 + i, at: around(p, i, 5), grit: 1.3, guardPost: true)) }
                e.spawned = true
                return
            }
            let captors = alive(g, e, only: "Kidnapper")
            guard let h = find(g, who) else {
                if alive(g, e, only: who ?? "") == 0 {
                    Honour.change(g, -2, "\(who ?? "a hostage") died")
                    Director.fail(g, &e, consequence: "\(who ?? "The hostage") did not survive")
                }
                return
            }
            if let home = h.home, simd_length(h.pos - home) > 3 && captors > 0 { h.wanderGoal = home; h.moving = true }
            let d = simd_length(h.pos - g.player.pos)
            if captors == 0 && d < 4 {
                h.persistent = false
                if let (t, a) = Director.nearTown(g, within: 2000), t == e.place {
                    h.home = V3(Float(a.x), Float(a.y), Float(a.z)); h.wanderGoal = h.home; h.moving = true
                }
                Director.pay(g, &e, dollars: e.int("reward"), honour: Float(e.num("honour")),
                             line: e.s["win"] ?? "\(who ?? "They")'s safe. The family won't forget it.")
                g.onToast?("\(who ?? "The hostage"): \"Thank you! I'll find my way home from here.\"")
            } else if captors == 0 && e.n["told"] == nil {
                e.n["told"] = 1
                g.onToast?("The kidnappers are down. Go to \(who ?? "the hostage") and cut them loose")
            }
        case "storm":
            if play - e.born >= e.num("minutes") * 60 && g.alive { Director.pay(g, &e, dollars: 0) }
        case "eruption":
            guard g.eruption == nil else { return }
            if let a = e.at, simd_length(V2(a.x - g.player.pos.x, a.y - g.player.pos.z)) < Game.eruptionShakeRange {
                let n = e.int("fallout")
                var items: [ItemStack] = []
                if Items.has("obsidian") { items.append(ItemStack(Items.id("obsidian"), n)) }
                if Items.has("magma_block") { items.append(ItemStack(Items.id("magma_block"), max(1, n / 2))) }
                Director.pay(g, &e, dollars: 0, items: items)
            } else {
                e.state = 4
                e.outcome = "Seen from afar: you were too far off to gather the fallout"
                Director.radio(g, caller: e.s["caller"] ?? "Radio", "The mountain has gone quiet again.")
            }
        case "outpost":
            let f = Faction(rawValue: e.faction) ?? .steelhold
            if !e.spawned {
                guard let p = ready(g, e) else { return }
                camp(g, p, wool: wool(f))
                let x = Int(floor(p.x)), y = Int(floor(p.y)), z = Int(floor(p.z))
                _ = container(g, x + 1, y, z + 3, block: "barrel", table: lootTable(f))
                for i in 0..<e.int("troops") { put(g, &e, soldier(g, f, i, at: around(p, i, 6), name: "\(f.name) Outpost")) }
                e.spawned = true
            } else if alive(g, e) == 0 {
                g.changeRep(f, -5)
                for o in FactionRep.tracked where o != f { g.changeRep(o, 2) }
                Director.pay(g, &e, dollars: e.int("reward"))
            }
        case "trader":
            guard let t = find(g, e.s["who"]) else {
                if alive(g, e, only: e.s["who"] ?? "") == 0 {
                    Honour.change(g, -3, "a peddler was killed")
                    Director.fail(g, &e, consequence: "The peddler is dead. Word gets round: honour lost")
                }
                return
            }
            e.x = Int(floor(t.pos.x)); e.z = Int(floor(t.pos.z))
        case "rival":
            guard let m = find(g, e.s["who"]) else {
                if alive(g, e) == 0 {
                    var items: [ItemStack] = []
                    if Items.has(Guns.revolverKey) { items.append(ItemStack(Items.id(Guns.revolverKey), 1)) }
                    if Items.has("rifle_rounds") { items.append(ItemStack(Items.id("rifle_rounds"), 18)) }
                    Director.pay(g, &e, dollars: e.int("reward"), items: items)
                }
                return
            }
            m.soldierBrain.order = g.player.pos
            e.x = Int(floor(m.pos.x)); e.z = Int(floor(m.pos.z))
        case "incursion":
            if !e.spawned {
                guard let p = ready(g, e) else { return }
                let x = Int(floor(p.x)), y = Int(floor(p.y)) - 1, z = Int(floor(p.z))
                // The rift: scorched cinderstone round a glowing core, fires in it.
                for dz in -3...3 { for dx in -3...3 where dx * dx + dz * dz <= 10 {
                    let b = g.world.block(x + dx, y, z + dz)
                    if Blocks.collide[Int(b)] && !Blocks.isLiquid(b) && Blocks.has("netherrack") {
                        g.world.setBlock(x + dx, y, z + dz, Blocks.id(dx == 0 && dz == 0 && Blocks.has("magma_block") ? "magma_block" : "netherrack"))
                        if hashf(dx, dz, e.id, 0xD1E3) < 0.25 { setIfAir(g, x + dx, y + 1, z + dz, "fire") }
                    }
                } }
                let n = e.int("count")
                for i in 0..<n {
                    let k: MobKind = i % 4 == 0 ? .brandKnight : (i % 4 == 1 ? .brandSquire : (i % 4 == 2 ? .scorchling : .brandSquire))
                    guard let q = ground(g, Int(floor(around(p, i, 4).x)), Int(floor(around(p, i, 4).z))) else { continue }
                    let m = Mob(k, at: q)
                    m.customName = "Riftborn"
                    m.aggro = true
                    put(g, &e, m)
                }
                g.particles.smoke(at: p + V3(0, 1, 0))
                g.sfx(.volcanoRumble, 0.6, at: p)
                e.spawned = true
            } else if alive(g, e) == 0 { Director.pay(g, &e, dollars: e.int("reward")) }
        case "warband":
            if alive(g, e) == 0 { Director.pay(g, &e, dollars: e.int("reward")) }
        case "dead_rise", "beasts":
            if !e.spawned {
                if e.t == "dead_rise" && !TownRaids.night(g.dayFraction) { return }
                guard let p = ready(g, e) else { return }
                let n = e.int("count")
                for i in 0..<n {
                    let k: MobKind
                    if e.t == "dead_rise" { k = [.zombie, .skeleton, .zombie, .husk][i % 4] }
                    else { k = i % 3 == 2 ? .wolf : .cougar }
                    guard let q = ground(g, Int(floor(around(p, i, 4).x)), Int(floor(around(p, i, 4).z))) else { continue }
                    let m = Mob(k, at: q)
                    m.customName = e.t == "dead_rise" ? "Restless Dead" : "Prowler"
                    m.aggro = true
                    put(g, &e, m)
                }
                e.spawned = !e.names.isEmpty
            } else if alive(g, e) == 0 {
                Director.pay(g, &e, dollars: e.int("reward"), honour: Float(e.num("honour")))
            }
        case "gift":
            guard let m = find(g, e.s["who"]) else {
                if alive(g, e) == 0 { Director.fail(g, &e, consequence: "The messenger from \(e.place ?? "town") never made it") }
                return
            }
            let d = simd_length(m.pos - g.player.pos)
            if d > 3 { m.wanderGoal = g.player.pos; m.moving = true; m.aiTimer = 2; m.panic = 0 }
            if d > 60, let p = nearSpot(g, 30...40) { m.pos = p }                 // he rides to catch up
            e.x = Int(floor(m.pos.x)); e.z = Int(floor(m.pos.z))
            if d < 3.5 {
                let c = ItemContainer(27)
                var rng = SRng(UInt64(e.id &* 7919) | 1)
                Loot.fill(c, table: e.s["loot"] ?? "village", rng: &rng)
                let town = e.place ?? "the town"
                g.logDocument("A Letter from \(town)", ["To the one who stood by us,\n\nWe have not forgotten what you did. Take this, with the thanks of every soul in \(town).\n\n" + (e.s["win"] ?? "")],
                              cat: .notes, id: "director-letter:\(e.id)")
                m.persistent = false
                m.customName = nil
                m.wanderGoal = m.pos + V3(40, 0, 40)
                Director.pay(g, &e, dollars: e.int("reward"), items: c.slots.filter { !$0.isEmpty })
            }
        case "legend":
            let i = Int(e.s["beast"] ?? "0") ?? 0
            if !e.spawned {
                guard let p = ready(g, e) else { return }
                let m = Hunting.spawnLegend(g, i, at: p)
                Director.refs[e.id] = [m]
                if let n = m.customName, !e.names.contains(n) { e.names.append(n) }
                e.spawned = true
            } else if let m = Director.refs[e.id]?.first {
                if m.health <= 0 { Director.pay(g, &e, dollars: 0) }
                else if !g.mobs.mobs.contains(where: { $0 === m }) { e.spawned = false; Director.refs[e.id] = nil }   // wandered off unloaded
                else { e.x = Int(floor(m.pos.x)); e.z = Int(floor(m.pos.z)) }
            } else { e.spawned = false }
        default:
            break
        }
    }

    // Q2c-console-28: how far along a running event is, for its journal entry.
    static func progress(_ g: Game, _ e: DirectorEvent) -> String? {
        func left(_ total: Int, _ what: String) -> String {
            let n = alive(g, e)
            return n == 0 ? "none left" : "\(n) of \(max(n, total)) \(what) left"
        }
        switch e.t {
        case "bounty":
            guard e.spawned else { return "the gang rides its route (the marker follows it)" }
            return alive(g, e, only: e.name) > 0 ? "\(e.name) is at the camp; " + left(e.int("posse") + 1, "outlaws") : "\(e.name) is down"
        case "hostage":
            guard e.spawned else { return "the kidnappers' camp waits at the marker" }
            let k = alive(g, e, only: "Kidnapper")
            return k > 0 ? "\(k) kidnapper\(k == 1 ? "" : "s") left, then free \(e.s["who"] ?? "the hostage")" : "go to \(e.s["who"] ?? "the hostage") and cut them loose"
        case "wreck", "supply_drop":
            guard e.spawned, let c = e.chest, let n = stock(g, c) else { return "not reached yet" }
            return n * 2 > e.stock ? "the chest still holds most of its load" : "the chest is nearly empty"
        case "outpost": return e.spawned ? left(e.int("troops"), "soldiers") : "not reached yet"
        case "incursion", "dead_rise", "beasts", "warband":
            if e.t == "dead_rise" && !e.spawned { return "waiting for nightfall by \(e.place ?? "the town")" }
            return e.spawned ? left(e.int("count"), e.t == "beasts" ? "prowlers" : "creatures") : "not reached yet"
        case "town_raid": return e.fired ? "the raid is on" : "waiting for nightfall at \(e.place ?? "the town")"
        case "counteroffensive":
            if e.fired { return "the raid is on" }
            let m = Int(((e.due - Director.state.play) / 60).rounded())
            return m > 0 ? "the strike comes in about \(m) min" : "they are at \(e.place ?? "your place"): get there"
        case "trader": return "the peddler waits near the marker"
        case "gift": return "the messenger is on the way to you"
        case "rival": return "he is coming for you"
        case "storm": return "the storm rages"
        case "legend": return e.spawned ? "it roams near the marker" : "not found yet"
        case "eruption": return "the mountain is erupting"
        default: return nil
        }
    }

    // MARK: Time up (l)

    static func expire(_ g: Game, _ e: inout DirectorEvent) {
        // What it left in the world goes away where he cannot see it (the people of a won fight stay where they fell).
        let names = e.names
        g.mobs.mobs.removeAll { m in
            guard let n = m.customName, names.contains(n), m.health > 0 else { return false }
            return simd_length(m.pos - g.player.pos) > 40 || e.t == "trader"
        }
        switch e.t {
        case "town_raid":
            Honour.change(g, -2, "you let \(e.place ?? "a town") down")
            Director.fail(g, &e, consequence: "Raiders hit \(e.place ?? "the town") while you were away: honour lost", expired: true)
        case "counteroffensive":
            if e.fired && FactionRaids.active != nil { e.until += 120; return }     // the fight is still on
            let lost = min(g.money / 10, 10000)
            g.money -= lost
            Director.fail(g, &e, consequence: "\(Faction(rawValue: e.faction)?.name ?? "They") sacked \(e.place ?? "your place")" + (lost > 0 ? ": \(Money.format(lost)) of your stores gone" : ""), expired: true)
        case "hostage":
            Honour.change(g, -2, "\(e.s["who"] ?? "a hostage") was not saved")
            Director.fail(g, &e, consequence: "The kidnappers moved on with \(e.s["who"] ?? "their hostage"): honour lost", expired: true)
        case "trader":
            let traded = Director.refs[e.id]?.first?.villager?.offers.contains { $0.uses > 0 } ?? false
            e.state = traded ? 2 : 4
            e.outcome = traded ? "Traded with \(e.s["who"] ?? "the peddler") before they moved on" : "The peddler moved on"
            Director.radio(g, caller: e.s["caller"] ?? "Radio", "The peddler's wagon has gone on down the road.")
        default:
            Director.fail(g, &e, consequence: "\(e.name): the chance has passed", expired: true)
        }
    }
}
