import Foundation
import simd

// Countries that give minerals (backlog B4; docs/status/countries.md).
//
// The overworld is cut into countries: a jittered grid of seats `cell` blocks apart, and every place belongs to its
// nearest seat (straight-edged cells that read clearly on the map). Everything about a country comes from its seat
// cell and the world seed, so a lookup is a few hashes, the same on every thread:
//   name and flag   an original name from syllables, two flag colours (wool dyes);
//   minerals        two it's rich in: generation adds veins of them under its land (WorldGen.placeOres, its own random
//                   stream), its towns pay less for them (x0.7) and more for the ones it isn't rich in (x1.3);
//   tax             0-15% on what you buy in its towns;
//   capital         the capital city, else the town, nearest its seat inside it.
// What you do there changes things (saved under the world extra "countries"):
//   standing        -100...100 per country: crimes, killing its law and taking its towns lower it, trade raises it.
//                   At `enemyAt` or below its towns are on edge (TownConquest's wary prices and heat) when you arrive.
//   alliance        a treaty bought at its capital's general store (standing `allyAt`+): 10% off, no customs.
//   annexed         take its capital (the B1 surrender) and the country is yours: all its towns are your towns
//                   (TownConquest.owns), its flag on the map is yours, and its treasury pays tribute at the capital.
//   border posts    a flagged guard post where neighbouring countries meet, built when you first come near it. Crossing
//                   there with minerals owes customs (`dutyPct` of their value): stop at the post to pay, or ride on
//                   and it counts against you.
//   wars            once a day neighbouring countries may declare war or make peace; each day of war its front line
//                   moves and the known towns behind it change hands (WarFront.swift, C2; news as a toast; prices and
//                   annexing follow the new owner).

enum Mineral: Int, CaseIterable, Codable {
    case coal, iron, copper, gold, lapis, titanium, emerald
    var name: String { ["coal", "iron", "copper", "gold", "lapis", "titanium", "emerald"][rawValue] }
    var items: [String] {
        switch self {
        case .coal: return ["coal", "coal_block"]
        case .iron: return ["raw_iron", "iron_ingot", "iron_nugget", "iron_block", "raw_iron_block"]
        case .copper: return ["raw_copper", "copper_ingot", "copper_block", "raw_copper_block"]
        case .gold: return ["raw_gold", "gold_ingot", "gold_nugget", "gold_block", "raw_gold_block"]
        case .lapis: return ["lapis_lazuli", "lapis_block"]
        case .titanium: return ["raw_titanium", "diamond", "diamond_block"]
        case .emerald: return ["emerald"]
        }
    }
}

struct Country: Equatable {
    let cx: Int, cz: Int                    // seat cell
    let seatX: Int, seatZ: Int
    let name: String
    let flag: (Int, Int)                    // indices into Countries.dyes
    let rich: [Mineral]
    let tax: Int                            // percent
    var key: String { "\(cx),\(cz)" }
    static func == (a: Country, b: Country) -> Bool { a.cx == b.cx && a.cz == b.cz }
    func isRich(_ m: Mineral) -> Bool { rich.contains(m) }
    var richText: String { rich.map { $0.name }.joined(separator: " and ") }
}

// A shop's country terms (ShopPricing.country): the mineral factors, tax and an ally's discount.
struct CountryTerms {
    var rich: [Mineral] = []
    var tax: Float = 0
    var ally = false
    var active = false
    static let none = CountryTerms()

    func buy(_ item: ItemID, _ value: Int, _ p: ShopPricing) -> Int {
        var f: Float = 1 + tax
        if let m = Countries.mineral(item), !rich.contains(m) { f *= Countries.lackFactor }
        var price = max(1, Int((Float(value) * p.buyMult * f).rounded()))
        // An ally's 10% never takes a price under the best a shop ever asks (the barter loop guards rely on it).
        if ally { price = max(max(1, Int((Float(value) * Economy.minBuyMult).rounded())), Int((Float(price) * 0.9).rounded())) }
        return price
    }
    func sell(_ item: ItemID, _ value: Int, _ p: ShopPricing) -> Int {
        guard let m = Countries.mineral(item) else { return p.sell(value) }
        let base = Float(value) * p.sellMult
        var s = Int((base * (rich.contains(m) ? Countries.richFactor : Countries.lackFactor)).rounded(.down))
        // Never more than the least money that gets you one anywhere (no buy-and-sell loop, whatever the country).
        if let c = Economy.cashIn[item] { s = min(s, max(0, Int(c.rounded(.down)) - 1)) }
        return max(0, s)
    }
}

enum Countries {
    static let cell = 2048
    static let richFactor: Float = 0.7, lackFactor: Float = 1.3
    static let enemyAt: Float = -50, allyAt: Float = 25
    static let treatyFee = 5000                 // cents
    static let dutyPct = 8
    static let payRadius: Float = 8
    static let tributePerDay = 1500
    static let tributeCap = 7

    // Flag colours: the wool block's dye and a HUD colour.
    static let dyes: [(String, V4)] = [
        ("red", V4(0.75, 0.15, 0.13, 1)), ("blue", V4(0.2, 0.3, 0.75, 1)), ("green", V4(0.3, 0.55, 0.15, 1)),
        ("yellow", V4(0.95, 0.8, 0.2, 1)), ("black", V4(0.1, 0.1, 0.12, 1)), ("white", V4(0.93, 0.93, 0.93, 1)),
        ("orange", V4(0.95, 0.5, 0.1, 1)), ("purple", V4(0.5, 0.2, 0.65, 1)), ("cyan", V4(0.1, 0.55, 0.6, 1)),
        ("brown", V4(0.45, 0.3, 0.17, 1)),
    ]
    static let first = ["Ost", "Kes", "Val", "Mar", "Dra", "Bel", "Tor", "Har", "Sel", "Ard", "Cal", "Ves", "Lor", "Bran",
                        "Eld", "Rho", "Sav", "Tam", "Wen", "Quel", "Ith", "Zor", "Fen", "Gor"]
    static let middle = ["", "", "e", "a", "i", "o", "ar", "en", "is"]
    static let last = ["vaal", "mark", "land", "ria", "dor", "heim", "stad", "mere", "gard", "wick", "onia", "esh", "hold",
                       "reach", "vania", "moor"]

    // Real places, real historical names and near-misses of other works' places the syllables can spell: re-rolled.
    static let blockedNames: Set<String> = ["ostmark", "ostland", "harstad", "fenland", "savonia", "valonia", "gordor", "marland",
                                            "holland", "valland", "selland", "ardland", "calland", "belland", "torland", "tamland",
                                            "eldland", "vesland", "rholand", "gorland", "itheland", "kesland", "dravania", "harland",
                                            "marmark", "belgard", "tormark", "ardmark", "eldorado", "eldoria", "calonia", "savoria",
                                            "marmoor", "fenmoor", "vesmere", "dramark", "ostria", "valdor", "valheim", "eldheim",
                                            "lorria", "cal", "mordor", "gondor", "rohan", "eriador", "tamria", "tamriel", "valenwood",
                                            "harrenhal", "belgium", "wenland", "wendor"]
    static func blocked(_ n: String) -> Bool {
        let l = n.lowercased()
        return blockedNames.contains(l) || l.hasPrefix("nazi") || l.hasPrefix("reich")
    }

    // MARK: The layer (pure, any thread)

    @inline(__always) static func hash(_ cx: Int, _ cz: Int, _ seed: UInt64, _ salt: UInt64) -> UInt64 {
        Townsfolk.mix(cx, cz, seed ^ salt)
    }
    static func seat(_ cx: Int, _ cz: Int, seed: UInt64) -> (Int, Int) {
        let h = hash(cx, cz, seed, 0xC0_5EA7)
        let m = cell / 8, span = UInt64(cell - 2 * m)
        return (cx * cell + m + Int(h % span), cz * cell + m + Int((h >> 24) % span))
    }
    // The seat cell a place belongs to (nearest seat of the 3x3 cells around it).
    static func cellAt(_ x: Int, _ z: Int, seed: UInt64) -> (Int, Int) {
        let gx = floorDiv(x, cell), gz = floorDiv(z, cell)
        var best = (gx, gz), bd = Int.max
        for dz in -1...1 { for dx in -1...1 {
            let s = seat(gx + dx, gz + dz, seed: seed)
            let ex = s.0 - x, ez = s.1 - z
            let d = ex * ex + ez * ez
            if d < bd { bd = d; best = (gx + dx, gz + dz) }
        } }
        return best
    }
    static func richMinerals(_ cx: Int, _ cz: Int, seed: UInt64) -> [Mineral] {
        let h = hash(cx, cz, seed, 0x0BE5)
        // Emerald is the rare pick (weight 1 against 3 for the others).
        func pick(_ r: UInt64, not: Mineral?) -> Mineral {
            let w: [Int] = Mineral.allCases.map { $0 == not ? 0 : ($0 == .emerald ? 1 : 3) }
            var k = Int(r % UInt64(w.reduce(0, +)))
            for (i, x) in w.enumerated() { k -= x; if k < 0 { return Mineral(rawValue: i)! } }
            return .iron
        }
        let a = pick(h, not: nil)
        return [a, pick(h >> 20, not: a)]
    }
    // Generation: the rich minerals at a place (WorldGen.placeOres).
    static func rich(atX x: Int, z: Int, seed: UInt64) -> [Mineral] {
        let c = cellAt(x, z, seed: seed)
        return richMinerals(c.0, c.1, seed: seed)
    }

    static func make(_ cx: Int, _ cz: Int, seed: UInt64) -> Country {
        let h = hash(cx, cz, seed, 0xF1A6)
        var name = ""
        for k in 0..<8 {
            let r = k == 0 ? h : Townsfolk.mix(cx, cz, seed ^ 0xF1A6 &+ UInt64(k))
            name = Townsfolk.pick(first, r) + Townsfolk.pick(middle, r >> 11) + Townsfolk.pick(last, r >> 22)
            if name.count > 11 { name = Townsfolk.pick(first, r) + Townsfolk.pick(last, r >> 22) }
            if !blocked(name) { break }
        }
        let a = Int((h >> 33) % UInt64(dyes.count))
        let b = (a + 1 + Int((h >> 41) % UInt64(dyes.count - 1))) % dyes.count
        let s = seat(cx, cz, seed: seed)
        return Country(cx: cx, cz: cz, seatX: s.0, seatZ: s.1, name: name, flag: (a, b),
                       rich: richMinerals(cx, cz, seed: seed), tax: Int((h >> 50) % 16))
    }

    // Main-thread cache of made countries.
    private static var made: [Int64: Country] = [:]
    private static var madeSeed: UInt64 = 0
    static func country(_ cx: Int, _ cz: Int, seed: UInt64) -> Country {
        if madeSeed != seed { made = [:]; madeSeed = seed }
        let k = Int64(cx) << 32 ^ Int64(cz & 0xFFFF_FFFF)
        if let c = made[k] { return c }
        let c = make(cx, cz, seed: seed)
        if made.count > 256 { made = [:] }
        made[k] = c
        return c
    }
    static func at(_ g: Game, x: Int, z: Int) -> Country {
        let c = cellAt(x, z, seed: g.world.seed)
        return country(c.0, c.1, seed: g.world.seed)
    }
    static func at(_ g: Game, _ p: V3) -> Country { at(g, x: Int(floor(p.x)), z: Int(floor(p.z))) }
    static func byKey(_ g: Game, _ key: String) -> Country? { byKey(key, seed: g.world.seed) }
    static func byKey(_ key: String, seed: UInt64) -> Country? {
        let p = key.split(separator: ",").compactMap { Int($0) }
        return p.count == 2 ? country(p[0], p[1], seed: seed) : nil
    }

    static let mineralOf: [ItemID: Mineral] = {
        var d: [ItemID: Mineral] = [:]
        for m in Mineral.allCases { for k in m.items where Items.has(k) { d[Items.id(k)] = m } }
        return d
    }()
    static func mineral(_ item: ItemID) -> Mineral? { mineralOf[item] }

    // MARK: Saved state

    struct Saved: Codable {
        var standing: [String: Float] = [:]
        var allies: [String] = []
        var annexed: [String] = []
        var wars: [String: Int] = [:]            // "a|b" (keys in order) -> the day it started
        var townOwner: [String: String] = [:]    // town -> the country holding it, where a war moved it
        var towns: [String: [Int]] = [:]         // known towns -> [x, z] of their anchor
        var posts: [String] = []                 // border posts built ("a|b")
        var tributeDay: [String: Int] = [:]
        var warDay: Int? = nil
        var seed: UInt64? = nil
        var learned: [String]? = nil             // countries whose riches a townsperson told you (P50)
        var fronts: [String: Float]? = nil       // war key -> the front line's offset (C2, WarFront.swift)
        var might: [String: Float]? = nil        // country -> the player's part in its strength (C2)
        var battles: Int? = nil                  // days of war fought (C2)
    }
    static var state = Saved()

    // Live.
    static var lastTick: Double = -10
    static var lastKey: String?                  // the country the player was in at the last tick
    static var lastTown: String?
    static var owed = 0                          // customs owed at the post you're near (cents), 0 = none
    static var owedTo: String?                   // the country it's owed to
    static var owedPost: String?
    static var paidPost: String?                 // paid at this post (until you leave it)
    static var postPause: Double = 0
    static var lastPostDistance: Float = .infinity  // the nearest you came to the owed post's booth (since it asked)
    static var crossings = 0, smuggled = 0, warNews = 0, annexes = 0    // (tests)
    static var capitals: [String: (String, Int, Int)?] = [:]
    static var postSpots: [String: (Int, Int)?] = [:]

    static func reset() {
        state = Saved(); lastTick = -10; lastKey = nil; lastTown = nil; owed = 0; owedTo = nil; owedPost = nil; paidPost = nil
        crossings = 0; smuggled = 0; warNews = 0; annexes = 0; capitals = [:]; postSpots = [:]; lastPos = nil
        lastPostDistance = .infinity; hud = nil; WarFront.nextGun = 0
    }
    static func save(_ d: inout [String: String]) {
        if let e = try? JSONEncoder().encode(state), let s = String(data: e, encoding: .utf8) { d["countries"] = s }
    }
    static func load(_ d: [String: String]) {
        reset()
        if let s = d["countries"], let data = s.data(using: .utf8), let st = try? JSONDecoder().decode(Saved.self, from: data) { state = st }
    }

    static func standing(_ c: Country) -> Float { state.standing[c.key] ?? 0 }
    static func change(_ g: Game, _ c: Country, _ by: Float, _ why: String? = nil) {
        guard !isAnnexed(c) else { return }
        let was = standing(c)
        let now = max(-100, min(100, was + by))
        state.standing[c.key] = now
        if was > enemyAt && now <= enemyAt {
            if let i = state.allies.firstIndex(of: c.key) { state.allies.remove(at: i) }
            g.onToast?("\(c.name) counts you its enemy\(why.map { ": " + $0 } ?? "")")
        }
    }
    // P50 (Oct 11 evening): what a country is rich in is earned knowledge: a townsperson tells a respected player
    // (honour 20+) on a greeting, once per country; your annexed countries you know. Until then the map and the
    // border toast give only the name.
    static func knows(_ c: Country) -> Bool { isAnnexed(c) || (state.learned ?? []).contains(c.key) }
    static func tellRiches(_ g: Game, _ m: Mob, town: String) -> Bool {
        guard g.survival, Honour.value >= Honour.respected, !m.baby else { return false }
        let c = of(g, town: town, near: m.pos)
        guard !knows(c), !c.rich.isEmpty else { return false }
        state.learned = (state.learned ?? []) + [c.key]
        Townsfolk.say(g, m, "You've done right by folks, so here's something: \(c.name)'s hills are rich in \(c.richText).")
        g.onToast?("Learned: \(c.name) is rich in \(c.richText) (on your map)")
        return true
    }
    static func isAlly(_ c: Country) -> Bool { state.allies.contains(c.key) }
    static func isAnnexed(_ c: Country) -> Bool { state.annexed.contains(c.key) }
    static func isEnemy(_ c: Country) -> Bool { !isAnnexed(c) && standing(c) <= enemyAt }

    // MARK: Towns

    // Where a town is (its anchor), learnt the first time it comes up.
    @discardableResult
    static func note(_ g: Game, town: String, near p: V3) -> (Int, Int) {
        if let t = state.towns[town], t.count == 2 { return (t[0], t[1]) }
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        var a = (x, z)
        if let s = g.world.gen.structures?.nearest("village", x: x, z: z, maxRegions: 1), abs(s.anchor.x - x) < 200 && abs(s.anchor.z - z) < 200 {
            a = (s.anchor.x, s.anchor.z)
        }
        state.towns[town] = [a.0, a.1]
        return a
    }
    // The country a town belongs to now (a war may have moved it).
    static func of(_ g: Game, town: String, near p: V3) -> Country {
        if let k = state.townOwner[town], let c = byKey(g, k) { return c }
        let a = note(g, town: town, near: p)
        return at(g, x: a.0, z: a.1)
    }
    static func ofKnown(_ g: Game, town: String) -> Country? { ofKnown(town, seed: g.world.seed) }
    static func ofKnown(_ town: String, seed: UInt64) -> Country? {
        if let k = state.townOwner[town], let c = byKey(k, seed: seed) { return c }
        guard let t = state.towns[town], t.count == 2 else { return nil }
        let c = cellAt(t[0], t[1], seed: seed)
        return country(c.0, c.1, seed: seed)
    }
    // TownConquest.owns: every town of a country you annexed is yours (towns are learnt on the way in: the tick, a
    // shop, a crime there).
    static func annexes(_ town: String) -> Bool {
        guard !state.annexed.isEmpty, let seed = state.seed, let c = ofKnown(town, seed: seed) else { return false }
        return isAnnexed(c)
    }
    static func isEnemyTown(_ town: String) -> Bool {
        guard !state.standing.isEmpty, let seed = state.seed, let c = ofKnown(town, seed: seed) else { return false }
        return isEnemy(c)
    }

    // The capital: the capital city nearest the seat inside the country, else the town nearest it.
    static func capital(_ g: Game, _ c: Country) -> (name: String, x: Int, z: Int)? {
        if let v = capitals[c.key] { return v.map { (name: $0.0, x: $0.1, z: $0.2) } }
        var out: (String, Int, Int)?
        if let sc = g.world.gen.structures {
            func inside(_ s: StructureStart) -> Bool {
                let cx = (s.min.x + s.max.x) / 2, cz = (s.min.z + s.max.z) / 2
                return cellAt(cx, cz, seed: g.world.seed) == (c.cx, c.cz)
            }
            if let s = sc.nearest("capital_city", x: c.seatX, z: c.seatZ, maxRegions: 2, accept: inside) {
                let cx = (s.min.x + s.max.x) / 2, cz = (s.min.z + s.max.z) / 2
                out = (Townsfolk.town(g, at: V3(Float(cx), 64, Float(cz))), cx, cz)
            } else if let s = sc.nearest("village", x: c.seatX, z: c.seatZ, maxRegions: 4, accept: inside) {
                out = (Townsfolk.town(g, at: V3(Float(s.anchor.x), 64, Float(s.anchor.z))), s.anchor.x, s.anchor.z)
            }
        }
        if let o = out, state.towns[o.0] == nil { state.towns[o.0] = [o.1, o.2] }
        capitals[c.key] = .some(out)
        return out.map { (name: $0.0, x: $0.1, z: $0.2) }
    }
    static func isCapital(_ g: Game, town: String, of c: Country) -> Bool { capital(g, c)?.name == town }

    // MARK: Prices (ShopPricing.country)

    static func terms(_ g: Game, town: String?, at p: V3) -> CountryTerms {
        guard g.dim.dim == .overworld else { return .none }
        let c = town.map { of(g, town: $0, near: p) } ?? at(g, p)
        let yours = isAnnexed(c) || TownConquest.owns(town)
        return CountryTerms(rich: c.rich, tax: yours ? 0 : Float(c.tax) / 100, ally: isAlly(c), active: true)
    }

    // MARK: Hooks

    // TownLaw.offence: a crime witnessed in one of its towns.
    static func crime(_ g: Game, town: String, at p: V3, heat: Float) {
        let c = of(g, town: town, near: p)
        change(g, c, -3 * heat, "your crimes in \(town)")
    }
    // TownLaw.turnHostile: a town turned on you.
    static func townTurned(_ g: Game, town: String, at p: V3) {
        change(g, of(g, town: town, near: p), -10, "\(town) turned on you")
    }
    // TownConquest.lawFell: you killed its law. Killing the law of a country at war with your ally helps your ally.
    static func lawKilled(_ g: Game, town: String, at p: V3) {
        let c = of(g, town: town, near: p)
        change(g, c, -25, "you killed its law")
        WarFront.lawKilled(c)
        for a in state.allies where a != c.key && state.wars[warKey(a, c.key)] != nil {
            if let ally = byKey(g, a) {
                state.standing[a] = min(100, (state.standing[a] ?? 0) + 8)
                g.onToast?("\(ally.name) thanks you: \(c.name) is its enemy")
            }
        }
    }
    // Shop.buy / Shop.sell: fair trade, a little goodwill.
    static func traded(_ g: Game, town: String?, at p: V3) {
        guard g.dim.dim == .overworld else { return }
        let c = town.map { of(g, town: $0, near: p) } ?? at(g, p)
        if !isAnnexed(c) { state.standing[c.key] = min(100, standing(c) + 0.2) }
        WarFront.traded(c)
    }
    // TownConquest.surrender: taking the capital annexes the country; any other town costs standing.
    static func townTaken(_ g: Game, _ town: String, at p: V3) {
        let c = of(g, town: town, near: p)
        guard !isAnnexed(c) else { return }
        if isCapital(g, town: town, of: c) {
            state.annexed.append(c.key)
            state.allies.removeAll { $0 == c.key }
            state.standing[c.key] = 100
            for (k, _) in state.wars where k.split(separator: "|").contains(Substring(c.key)) { state.wars[k] = nil }
            state.tributeDay[c.key] = Int(g.time / DAY_LENGTH)
            annexes += 1
            g.sfx(.bell, 0.9, at: p)
            g.onToast?("\(town) was \(c.name)'s capital: all of \(c.name) is yours now, its towns and its tribute")
        } else {
            change(g, c, -30, "you took \(town)")
            WarFront.townTaken(c)
        }
    }

    // The treaty (a service at the capital's general store).
    static func offersTreaty(_ g: Game, _ m: Mob) -> Bool {
        guard g.dim.dim == .overworld, let t = m.villager?.town else { return false }
        let c = of(g, town: t, near: m.pos)
        return !isAnnexed(c) && isCapital(g, town: t, of: c)
    }
    static func treatyDetail(_ g: Game, _ m: Mob) -> (String, Bool) {
        let c = of(g, town: m.villager?.town ?? "", near: m.pos)
        if isAlly(c) { return ("You are allies already", false) }
        let s = standing(c)
        if s < allyAt { return ("Needs standing \(Int(allyAt)) with \(c.name) (now \(Int(s.rounded())))", false) }
        return ("Ally with \(c.name): 10% off, no customs", true)
    }
    static func signTreaty(_ g: Game, _ m: Mob) -> (String, Bool) {
        let c = of(g, town: m.villager?.town ?? "", near: m.pos)
        let (why, ok) = treatyDetail(g, m)
        guard ok else { return (why + ".", false) }
        guard g.money >= treatyFee else { return ("The treaty costs \(Money.format(treatyFee)). You have \(Money.format(g.money)).", false) }
        g.money -= treatyFee
        state.allies.append(c.key)
        g.sfx(.bell, 0.7, at: m.pos)
        g.achieve("trade")
        return ("Signed. \(c.name) is your ally.", true)
    }

    // MARK: Every second (HudExtras.tick)

    static func tick(_ g: Game) {
        guard g.clock - lastTick >= 1 || g.clock < lastTick else { return }
        lastTick = g.clock
        if state.seed == nil { state.seed = g.world.seed } else if state.seed != g.world.seed { reset(); state.seed = g.world.seed }
        guard g.dim.dim == .overworld, g.world.frame == nil else { lastKey = nil; lastPos = nil; return }
        let p = g.player.pos
        let c = at(g, p)
        if let was = lastKey, was != c.key {
            crossings += 1
            crossed(g, from: was, into: c)
        }
        lastKey = c.key
        if let t = TownLaw.inTown {
            note(g, town: t, near: p)
            if t != lastTown { arrived(g, town: t) }
        }
        lastTown = TownLaw.inTown
        posts(g)
        wars(g)
        WarFront.ambience(g)
        lastPos = p
        hud = makeHud(g)
    }
    static var lastPos: V3?
    // How close the path since the last tick came to a booth (the segment from the last position to here).
    static func passed(_ g: Game, _ spot: (Int, Int)) -> Float {
        let q = V2(Float(spot.0) + 0.5, Float(spot.1) + 0.5)
        let a = V2(g.player.pos.x, g.player.pos.z)
        let b = lastPos.map { V2($0.x, $0.z) } ?? a
        let ab = b - a
        let t = max(0, min(1, simd_dot(q - a, ab) / max(1e-4, simd_dot(ab, ab))))
        return min(simd_length(a + ab * t - q), lastPostDistance)
    }

    static func crossed(_ g: Game, from: String, into c: Country) {
        // Ran a post without paying: smuggling.
        if owed > 0, owedTo == c.key, let pk = owedPost, let spot = postSpots[pk] ?? nil,
           simd_length(V2(Float(spot.0) - g.player.pos.x, Float(spot.1) - g.player.pos.z)) < 48, g.survival {
            // Through the booth (the tick is once a second: at a run or on a horse you can be past it before one
            // sees you there): that's paying, when you can.
            if passed(g, spot) < payRadius, g.money >= owed {
                g.money -= owed
                g.sfx(.villagerTrade, 0.6)
                g.onToast?("Paid \(Money.format(owed)) duty to \(c.name)")
                paidPost = pk; owed = 0; owedTo = nil
                return
            }
            smuggled += 1
            change(g, c, -10)
            g.onToast?("You ran \(c.name)'s customs post. They won't forget it.")
            owed = 0; owedTo = nil
            return
        }
        var t = knows(c) ? "Entering \(c.name): rich in \(c.richText)" : "Entering \(c.name)"
        if isAnnexed(c) { t = "Entering \(c.name), your country" }
        else if isEnemy(c) { t += ". You are its enemy." }
        else if isAlly(c) { t += ". Your ally." }
        g.onToast?(t)
    }

    // An enemy country's towns are on edge when you walk in; your annexed capital pays its tribute.
    static func arrived(_ g: Game, town: String) {
        guard g.survival else { return }
        let c = of(g, town: town, near: g.player.pos)
        if isEnemy(c), !TownConquest.owns(town) {
            TownLaw.state.heat[town] = max(TownLaw.heat(town), TownLaw.hostileHeat - 1)
            g.onToast?("\(town) knows you: you're \(c.name)'s enemy. They're on edge.")
        }
        if isAnnexed(c), isCapital(g, town: town, of: c) {
            let day = Int(g.time / DAY_LENGTH)
            let days = min(tributeCap, day - (state.tributeDay[c.key] ?? day))
            if days > 0 {
                state.tributeDay[c.key] = day
                g.money += days * tributePerDay
                g.sfx(.xp, 0.5)
                g.onToast?("\(c.name)'s treasury pays you \(Money.format(days * tributePerDay))")
            }
        }
    }

    // MARK: Border posts and customs

    static func warKey(_ a: String, _ b: String) -> String { a < b ? a + "|" + b : b + "|" + a }

    // Where the post between two neighbouring countries stands: on the border half way between their seats, moved
    // along it off water and away from towns; nil when the two don't meet there.
    static func postSpot(_ g: Game, _ a: Country, _ b: Country) -> (Int, Int)? {
        let k = warKey(a.key, b.key)
        if let v = postSpots[k] { return v }
        var out: (Int, Int)?
        let mx = Float(a.seatX + b.seatX) / 2, mz = Float(a.seatZ + b.seatZ) / 2
        var along = V2(-Float(b.seatZ - a.seatZ), Float(b.seatX - a.seatX))
        along = along / max(1, simd_length(along))
        for i in 0..<9 {
            let off = Float((i + 1) / 2) * 40 * (i % 2 == 0 ? 1 : -1)
            let x = Int(floor(mx + along.x * off)), z = Int(floor(mz + along.y * off))
            let here = cellAt(x, z, seed: g.world.seed)
            guard here == (a.cx, a.cz) || here == (b.cx, b.cz) else { continue }
            let col = g.world.gen.column(x, z)
            guard !col.biome.isOcean, !col.biome.isRiver, col.height > SEA else { continue }
            if let sc = g.world.gen.structures, sc.types.contains(where: { t in
                sc.startsNear(cx: floorDiv(x, CS), cz: floorDiv(z, CS), t).contains { $0.max.x >= x - 24 && $0.min.x <= x + 24 && $0.max.z >= z - 24 && $0.min.z <= z + 24 }
            }) { continue }
            if let s = g.world.gen.structures?.nearest("village", x: x, z: z, maxRegions: 1),
               abs(s.anchor.x - x) < 120 && abs(s.anchor.z - z) < 120 { continue }
            out = (x, z)
            break
        }
        postSpots[k] = .some(out)
        return out
    }

    static func neighbours(_ g: Game, _ c: Country) -> [Country] {
        var out: [Country] = []
        for dz in -1...1 { for dx in -1...1 where dx != 0 || dz != 0 {
            out.append(country(c.cx + dx, c.cz + dz, seed: g.world.seed))
        } }
        return out
    }

    // Duty on the minerals you carry (allies and your own countries charge none).
    static func duty(_ g: Game, into c: Country) -> Int {
        guard !isAlly(c), !isAnnexed(c) else { return 0 }
        var v = 0
        for j in 0..<36 {
            let s = g.inventory.main[j]
            guard !s.isEmpty, mineral(s.item) != nil, let val = Economy.value(of: s.item) else { continue }
            v += val * s.count
        }
        return v * dutyPct / 100
    }

    static func posts(_ g: Game) {
        let p = g.player.pos
        let here = at(g, p)
        var near: (String, (Int, Int), Country, Country)?
        for n in neighbours(g, here) {
            // Only borders within 200 blocks (the spot search reads structure starts: once, and only near).
            var nn = V2(Float(n.seatX - here.seatX), Float(n.seatZ - here.seatZ)); nn = nn / max(1, simd_length(nn))
            let mid = V2(Float(n.seatX + here.seatX) / 2, Float(n.seatZ + here.seatZ) / 2)
            guard abs(simd_dot(V2(p.x, p.z) - mid, nn)) < 200, let s = postSpot(g, here, n) else { continue }
            let d = simd_length(V2(Float(s.0) - p.x, Float(s.1) - p.z))
            let k = warKey(here.key, n.key)
            if d < 96, d > 8, !state.posts.contains(k), g.world.isLoaded(s.0 - 2, s.1 - 2), g.world.isLoaded(s.0 + 4, s.1 + 2),
               g.world.isLoaded(s.0 - 2, s.1 + 2), g.world.isLoaded(s.0 + 4, s.1 - 2) {
                if clear(g, at: s) { build(g, at: s, here, n) }
                state.posts.append(k)
                MapCache.shared.discover(g, kind: "border_post", x: s.0, z: s.1, name: "\(here.name) - \(n.name) border post")
            }
            if d < 40 { near = (k, s, here, n) }
        }
        guard let (k, s, _, target) = near, g.survival else {
            if near == nil { paidPost = nil; owed = 0; owedTo = nil; owedPost = nil }
            return
        }
        // The duty is owed to the country across the post from you; paid, you're clear until you leave the post.
        if paidPost == k { return }
        let due = duty(g, into: target)
        if due == 0 { owed = 0; owedTo = nil; return }
        if owedPost != k || owedTo != target.key {
            owedPost = k; owedTo = target.key; owed = due; lastPostDistance = .infinity
            g.onToast?("\(target.name) customs: \(Money.format(due)) duty on your minerals. Stop at the post to pay.")
        }
        owed = due
        let d = simd_length(V2(Float(s.0) + 0.5 - p.x, Float(s.1) + 0.5 - p.z))
        lastPostDistance = min(lastPostDistance, d)
        if d < payRadius {
            if g.money >= due {
                g.money -= due
                paidPost = k; owed = 0; owedTo = nil
                g.sfx(.villagerTrade, 0.6)
                g.onToast?("Paid \(Money.format(due)) duty to \(target.name)")
            } else if g.clock - postPause > 10 {
                postPause = g.clock
                g.onToast?("You can't pay the \(Money.format(due)) duty. Turn back or run it.")
            }
        }
    }

    // The footprint holds nothing anyone built (an old save's base, a cabin): a post goes only on open ground.
    static func clear(_ g: Game, at s: (Int, Int)) -> Bool {
        let gy = g.world.gen.column(s.0, s.1).height
        let made = ["plank", "brick", "glass", "wool", "fence", "door", "slab", "stairs", "torch", "chest", "bed", "concrete",
                    "lantern", "furnace", "table", "carpet", "rail", "wall", "steel", "copper_block", "iron_block"]
        for dz in -2...2 { for dx in -2...4 { for y in (gy - 2)...(gy + 6) {
            let id = g.world.block(s.0 + dx, y, s.1 + dz)
            guard id != AIR else { continue }
            let n = Blocks.def(id).name
            if made.contains(where: { n.contains($0) }) { return false }
        } } }
        return true
    }

    // A small guard post: a stone-brick floor, a roofed booth on log posts and a flag on a fence pole.
    static func build(_ g: Game, at s: (Int, Int), _ a: Country, _ b: Country) {
        let w = g.world
        // Hundreds of edits: the mesh workers redraw the sections (synchronous remeshes stalled the Quest's frame).
        w.deferRemesh = true
        defer { w.deferRemesh = false }
        func id(_ n: String, _ fb: BlockID) -> BlockID { Blocks.has(n) ? Blocks.id(n) : fb }
        let floorB = id("stone_bricks", STONE), log = id("spruce_log", STONE), roof = id("spruce_slab", id("spruce_planks", STONE))
        let fence = id("spruce_fence", log), fill = id("cobblestone", STONE)
        let x0 = s.0 - 2, z0 = s.1 - 2
        let gy = w.gen.column(s.0, s.1).height
        for dz in 0..<5 { for dx in 0..<7 {
            let x = x0 + dx, z = z0 + dz
            for y in (gy + 1)...(gy + 6) where w.block(x, y, z) != AIR { w.setBlock(x, y, z, AIR) }
            w.setBlock(x, gy, z, floorB)
            var y = gy - 1
            while y > gy - 5 && !Blocks.opaque[Int(w.block(x, y, z))] { w.setBlock(x, y, z, fill); y -= 1 }
        } }
        // Booth: four posts and a slab roof over the 3x3 middle.
        for (dx, dz) in [(0, 0), (2, 0), (0, 2), (2, 2)] {
            for y in 1...3 { w.setBlock(x0 + 1 + dx, gy + y, z0 + 1 + dz, log) }
        }
        for dz in 0..<5 { for dx in 0..<5 { w.setBlock(x0 + dx, gy + 4, z0 + dz, roof) } }
        // The pole and the two flags, one each side.
        let px = x0 + 6, pz = z0 + 2
        for y in 1...6 { w.setBlock(px, gy + y, pz, fence) }
        let ca = dyes[a.flag.0].0, cb = dyes[a.flag.1].0, da = dyes[b.flag.0].0, db = dyes[b.flag.1].0
        w.setBlock(px, gy + 6, pz - 1, id(ca + "_wool", fill)); w.setBlock(px, gy + 5, pz - 1, id(cb + "_wool", fill))
        w.setBlock(px, gy + 6, pz + 1, id(da + "_wool", fill)); w.setBlock(px, gy + 5, pz + 1, id(db + "_wool", fill))
        // Signs at both ends of the booth saying what it is (Oct 11 playtest P21: a bare booth and two flags read as
        // "what the hell is this thing?"): one per direction, each naming the country you are entering.
        if Blocks.has("spruce_sign") {
            let sign = Blocks.id("spruce_sign")
            for (z, facing, into, from) in [(z0, BlockID(0), b, a), (z0 + 4, BlockID(1), a, b)] {
                w.setBlock(x0 + 2, gy + 1, z, sign + facing)
                let be = BlockEntity(.sign)
                be.lines = ["BORDER POST", "Entering \(into.name)", "from \(from.name)", "Customs: pay here"]
                w.blockEntities[IVec3(x0 + 2, gy + 1, z)] = be
            }
        }
    }

    // MARK: Wars (once a day, around you)

    static func wars(_ g: Game) {
        let day = Int(g.time / DAY_LENGTH)
        guard let last = state.warDay else { state.warDay = day; return }
        guard day > last else { return }
        state.warDay = day
        simulateDay(g, day: day)
    }

    static func simulateDay(_ g: Game, day: Int) {
        let me = at(g, g.player.pos)
        var pairs: [(Country, Country)] = []
        let block = [me] + neighbours(g, me)
        for a in block { for b in block where a.key < b.key && abs(a.cx - b.cx) + abs(a.cz - b.cz) == 1 { pairs.append((a, b)) } }
        let seed = g.world.seed
        WarFront.fade()
        for (a, b) in pairs {
            let k = warKey(a.key, b.key)
            let h = Townsfolk.mix(a.cx * 7 + b.cx, a.cz * 7 + b.cz, seed ^ UInt64(bitPattern: Int64(day)) &* 0x2545F4914F6CDD1D)
            let roll = Int(h % 100)
            if isAnnexed(a) || isAnnexed(b) { state.wars[k] = nil; continue }
            if let started = state.wars[k] {
                if day - started >= 2 && roll < 30 {
                    state.wars[k] = nil
                    warNews += 1
                    g.onToast?("\(a.name) and \(b.name) have made peace")
                    continue
                }
                WarFront.day(g, a, b, h >> 8)
            } else {
                let rivals = Townsfolk.mix(a.cx + b.cx, a.cz + b.cz, seed ^ 0x2A11) % 3 == 0
                if roll < (rivals ? 12 : 3) && state.wars.count < 3 {
                    state.wars[k] = day
                    warNews += 1
                    g.onToast?("\(a.name) has gone to war with \(b.name)")
                }
            }
        }
    }

    // MARK: HUD

    // Under the minimap: the country you're in, in its flag colour.
    static var hud: (String, V4)?
    static func hudLine(_ g: Game) -> (String, V4)? { g.dim.dim == .overworld && lastKey != nil ? hud : nil }
    static func makeHud(_ g: Game) -> (String, V4)? {
        guard g.dim.dim == .overworld, let k = lastKey, let c = byKey(g, k) else { return nil }
        var t = c.name
        if isAnnexed(c) { t += " (yours)" } else if isAlly(c) { t += " (ally)" } else if isEnemy(c) { t += " (enemy)" }
        if owed > 0 { t += " - duty " + Money.format(owed) }
        let col = dyes[c.flag.0].1
        return (t, c.flag.0 == 4 ? dyes[c.flag.1].1 : col)
    }

    // The big map: border lines and each country's name at its seat.
    private static var borderKey: [Int] = []
    private static var borderCells: [(Int, Int)] = []
    static func mapBorders(_ out: inout [HudLine], _ g: Game, x0: Float, y0: Float, cols: Int, rows: Int, px: Float, wx: Float, wz: Float, bpc: Int, s: Float) {
        guard g.dim.dim == .overworld else { return }
        let key = [Int(floor(wx)), Int(floor(wz)), bpc, cols, rows, Int(g.world.seed & 0xFFFFFFF)]
        if key != borderKey {
            borderKey = key
            borderCells.removeAll(keepingCapacity: true)
            var prevRow = [Int](repeating: 0, count: cols)
            let seed = g.world.seed
            let hc: Float = Float(cols) / 2, hr: Float = Float(rows) / 2, st: Float = Float(bpc)
            for r in 0..<rows {
                let z = Int(floor(wz + (Float(r) - hr) * st))
                var left = 0
                for c in 0..<cols {
                    let x = Int(floor(wx + (Float(c) - hc) * st))
                    let cc = cellAt(x, z, seed: seed)
                    let id = cc.0 &* 92821 &+ cc.1
                    if (c > 0 && id != left) || (r > 0 && id != prevRow[c]) { borderCells.append((c, r)) }
                    left = id
                    prevRow[c] = id
                }
            }
        }
        for (c, r) in borderCells {
            out.append(HudLine(text: "", x: x0 + Float(c) * px, y: y0 + Float(r) * px, scale: s, bg: V4(0.55, 0.08, 0.1, 0.85), box: V2(px, px)))
        }
        // Names at the seats in view.
        let half = V2(Float(cols) * Float(bpc) / 2, Float(rows) * Float(bpc) / 2)
        let gx0 = floorDiv(Int(wx - half.x), cell) - 1, gx1 = floorDiv(Int(wx + half.x), cell) + 1
        let gz0 = floorDiv(Int(wz - half.y), cell) - 1, gz1 = floorDiv(Int(wz + half.y), cell) + 1
        guard gx1 - gx0 < 12 && gz1 - gz0 < 12 else { return }
        for gz in gz0...gz1 { for gx in gx0...gx1 {
            let c = country(gx, gz, seed: g.world.seed)
            guard let p = MapDraw.project(Float(c.seatX), Float(c.seatZ), x0: x0, y0: y0, cols: cols, rows: rows, px: px, wx: wx, wz: wz, bpc: bpc) else { continue }
            var name = knows(c) ? c.name + ": " + c.rich.map { $0.name }.joined(separator: ", ") : c.name
            if isAnnexed(c) { name = c.name + " (yours)" }
            let w = Float(Font.width(name)) * s
            let yours = isAnnexed(c)            // your flag: gold over black
            out.append(HudLine(text: "", x: p.x - w / 2 - 6 * s, y: p.y - 2 * s, scale: s, bg: yours ? V4(1, 0.8, 0.25, 1) : dyes[c.flag.0].1, box: V2(4 * s, 3 * s)))
            out.append(HudLine(text: "", x: p.x - w / 2 - 6 * s, y: p.y + s, scale: s, bg: yours ? V4(0.1, 0.1, 0.12, 1) : dyes[c.flag.1].1, box: V2(4 * s, 3 * s)))
            out.append(HudLine(text: name, x: p.x - w / 2, y: p.y - 3 * s, scale: s,
                               color: isAnnexed(c) ? V4(1, 0.85, 0.3, 1) : V4(1, 1, 1, 0.95), bg: V4(0, 0, 0, 0.55)))
        }}
    }
}
