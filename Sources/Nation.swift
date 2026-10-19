import Foundation
import simd

// Your own nation (backlog C3; docs/status/nation.md).
//
// Every town you take (TownConquest) and every Greywall base you take (GreywallAlarm.taken) is a province of your
// nation. Ring the bell in one of your towns to sit with its council (NationMenu):
//   name, flag  pick the nation's name and its flag colour; your provinces show on the world map in that colour, the
//               capital as a larger square with a star.
//   taxes       low, fair or high: scales each town's tribute (x0.5, x1, x1.6) and its folk's loyalty (+3, 0, -4 a day).
//   laws        curfew (raids on your provinces half as likely, -1.5 loyalty a day), conscription (settlers drill into a
//               garrison, -1 loyalty a day), open market (+15% tribute, +1 loyalty a day).
//   capital     one of your towns, with a hall in the style you choose (timber, stone or brick) that its settlers raise
//               once six have come; the capital's folk are prouder (+2 loyalty a day).
// Each day (simulated from the save, so days away count, up to 30 at once):
//   loyalty     drifts toward 55, plus the tax and law terms above; the hall and a defended raid lift it.
//   settlers    a loyal province (35+) draws one or two settlers a day, up to 16 in a town and 8 at a base. Every three
//               settlers build: a fenced wheat farm or a cabin, on open ground 30-60 blocks round the town (bases:
//               cabins round the walls), placed when you're near and the ground is loaded. Up to six of them walk
//               about the town as its folk; each settler adds $0.50 to the day's tribute.
//   raids       about one day in twelve a province is attacked while you're away (curfew halves it): its garrison,
//               buildings and loyalty against the raiders' strength. Held: loyalty +3. Lost: loyalty -12 and a quarter
//               of the settlers leave. While you're there, the night raids (TownRaids) come twice as often to your
//               towns, and beating one off is worth +10 loyalty.
//   revolt      a town whose loyalty stays under 15 for three days throws you out: it is no longer yours (bases hold:
//               their garrison is your own).
// Saved in TownLaw.Saved.nation.
enum Nation {
    struct Province: Codable {
        var settlers = 0
        var loyalty: Float = 50
        var garrison = 1
        var lowDays = 0
        var spawned = 0                              // settlers walking about as townsfolk
        var sites: [[Int]] = []                      // what the settlers built: [x, y, z, kind] (0 farm, 1 cabin, 2 hall)
        var tries = 0                                // build sites tried and refused (open ground is hard to find)
    }
    struct Saved: Codable {
        var name: String? = nil
        var flag = 0
        var capital: String? = nil
        var hallStyle = 0
        var tax = 1
        var laws: [String] = []
        var provinces: [String: Province] = [:]
        var day = -1
        var log: [String] = []                       // "day|text", newest last, capped
    }
    static var s: Saved {
        get { TownLaw.state.nation ?? Saved() }
        set { TownLaw.state.nation = newValue }
    }

    static let taxNames = ["Low", "Fair", "High"]
    static let taxScale: [Float] = [0.5, 1, 1.6]
    static let taxLoyalty: [Float] = [3, 0, -4]
    static let laws: [(key: String, name: String, detail: String)] = [
        ("curfew", "Curfew", "Raids half as likely; loyalty -1.5 a day"),
        ("conscription", "Conscription", "Settlers drill as a garrison; loyalty -1 a day"),
        ("market", "Open market", "+15% tribute; loyalty +1 a day"),
    ]
    static let flagColors: [(name: String, wool: String, c: V4)] = [
        ("Scarlet", "red_wool", V4(0.78, 0.16, 0.14, 1)), ("Royal blue", "blue_wool", V4(0.2, 0.32, 0.85, 1)),
        ("Forest green", "green_wool", V4(0.22, 0.55, 0.2, 1)), ("Gold", "yellow_wool", V4(0.95, 0.78, 0.15, 1)),
        ("Black", "black_wool", V4(0.1, 0.1, 0.12, 1)), ("White", "white_wool", V4(0.95, 0.95, 0.92, 1)),
        ("Purple", "purple_wool", V4(0.52, 0.22, 0.7, 1)), ("Orange", "orange_wool", V4(0.95, 0.5, 0.12, 1)),
    ]
    static let hallStyles: [(name: String, wall: String, frame: String)] = [
        ("Timber", "spruce_planks", "oak_log"), ("Stone", "stone_bricks", "cobblestone"), ("Brick", "bricks", "stone_bricks"),
    ]
    static let townCap = 16, baseCap = 8, walkers = 6
    static let maxDaysAtOnce = 30
    static var events: [String] = []                 // (tests) every daily event, newest last
    static var raids = true                          // (tests) off: the policy checks see no random raids

    static func has(_ law: String) -> Bool { s.laws.contains(law) }
    static func isBase(_ key: String) -> Bool { key.hasPrefix("greywall:") }

    // MARK: The provinces

    // Province key -> anchor (x, z). Towns from TownConquest's saved anchors, bases from their keys.
    static func provinces(_ g: Game) -> [(key: String, x: Int, z: Int)] {
        var out: [(String, Int, Int)] = []
        for (t, o) in (TownLaw.state.owned ?? [:]) where o.count >= 2 { out.append((t, o[0], o[1])) }
        for k in g.greywallAlarm.taken {
            let xz = k.dropFirst("greywall:".count).split(separator: ",").compactMap { Int($0) }
            if xz.count == 2 { out.append((k, xz[0], xz[1])) }
        }
        return out.sorted { $0.0 < $1.0 }
    }
    static func displayName(_ key: String) -> String {
        guard isBase(key) else { return key }
        let xz = key.dropFirst("greywall:".count).split(separator: ",")
        return "Fort " + (xz.first.map(String.init) ?? "") + (xz.count > 1 ? " " + xz[1] : "")
    }
    static func nationName(_ g: Game) -> String { s.name ?? "The Free Holdings" }
    static func nameChoices(_ g: Game) -> [String] {
        var out = ["The Free Holdings", "The Frontier Union", "The Westmark League", "The Ironwood Commonwealth"]
        if let c = s.capital, !isBase(c) { out += ["Republic of \(c)", "\(c) Confederacy"] }
        return out
    }

    // MARK: Tribute (TownConquest.tick)

    static func tributePerDay(_ town: String) -> Int {
        let p = s.provinces[town]
        let base = Float(TownConquest.tributePerDay) + Float(p?.settlers ?? 0) * 50
        return Int((base * taxScale[max(0, min(2, s.tax))] * (has("market") ? 1.15 : 1)).rounded())
    }

    // MARK: Every second (TownLaw.tick)

    static func tick(_ g: Game) {
        let ps = provinces(g)
        guard !ps.isEmpty else { return }
        let day = Int(g.time / DAY_LENGTH)
        var st = s
        if st.day < 0 { st.day = day }
        // New provinces start with their town's folk content enough (50).
        for p in ps where st.provinces[p.key] == nil { st.provinces[p.key] = Province() }
        s = st
        if day > st.day { advance(g, to: day) }
        let pos = g.player.pos
        for p in ps where simd_length(V2(Float(p.x) - pos.x, Float(p.z) - pos.z)) < 160 {
            build(g, p.key, x: p.x, z: p.z)
            if !isBase(p.key) { settle(g, p.key) }
        }
    }

    // The days since the last one, simulated in order (also the tests' clock).
    static func advance(_ g: Game, to day: Int) {
        var st = s
        let from = max(st.day + 1, day - maxDaysAtOnce + 1)
        var news: [String] = []
        let ps = provinces(g)
        let here = TownLaw.inTown
        guard from <= day else { st.day = day; s = st; return }
        for d in from...day {
            for p in ps {
                guard var pr = st.provinces[p.key] else { continue }
                let base = isBase(p.key)
                var h = Townsfolk.mix(d, p.x &* 31 &+ p.z, g.world.seed ^ 0xC3A7)
                func roll() -> Float { h = h &* 6364136223846793005 &+ 1442695040888963407; return Float(h >> 40) / Float(1 << 24) }
                // Loyalty.
                var dl = (55 - pr.loyalty) * 0.1 + taxLoyalty[max(0, min(2, st.tax))]
                if st.laws.contains("curfew") { dl -= 1.5 }
                if st.laws.contains("conscription") { dl -= 1 }
                if st.laws.contains("market") { dl += 1 }
                if st.capital == p.key { dl += 2 }
                if pr.sites.contains(where: { $0.count > 3 && $0[3] == 2 }) { dl += 1 }
                pr.loyalty = max(0, min(100, pr.loyalty + dl))
                // Settlers.
                let cap = base ? baseCap : townCap
                if pr.loyalty >= 35 && pr.settlers < cap {
                    pr.settlers = min(cap, pr.settlers + 1 + (roll() < pr.loyalty / 100 ? 1 : 0))
                }
                // The garrison.
                let drill = base ? 3 : 1
                if st.laws.contains("conscription") { pr.garrison = min(pr.settlers / 2 + drill + 1, pr.garrison + 1) }
                else if pr.garrison > drill { pr.garrison -= 1 }
                else { pr.garrison = drill }
                // Raids while you're away.
                let chance: Float = (base ? 0.06 : 0.085) * (st.laws.contains("curfew") ? 0.5 : 1)
                if raids, p.key != here, roll() < chance {
                    let atk = 3 + roll() * 9
                    let def = 4 + Float(pr.garrison) * 2 + Float(pr.sites.count) * 0.5 + pr.loyalty / 20
                    if def >= atk {
                        pr.loyalty = min(100, pr.loyalty + 3)
                        news.append("\(displayName(p.key)) beat off raiders")
                    } else {
                        pr.loyalty = max(0, pr.loyalty - 12)
                        pr.settlers -= pr.settlers / 4
                        news.append("Raiders struck \(displayName(p.key)); settlers fled")
                    }
                }
                // Revolt.
                if !base {
                    pr.lowDays = pr.loyalty < 15 ? pr.lowDays + 1 : 0
                    if pr.lowDays >= 3 {
                        TownLaw.state.owned?[p.key] = nil
                        st.provinces[p.key] = nil
                        if st.capital == p.key { st.capital = nil }
                        news.append("\(p.key) rose up and threw you out")
                        continue
                    }
                }
                st.provinces[p.key] = pr
            }
            st.day = d
        }
        for n in news { st.log.append("\(day)|\(n)"); events.append(n) }
        if st.log.count > 20 { st.log.removeFirst(st.log.count - 20) }
        s = st
        if !news.isEmpty {
            g.onToast?(news.prefix(2).joined(separator: ". ") + (news.count > 2 ? " (and \(news.count - 2) more)" : ""))
        }
    }

    // MARK: Raids you stand through (TownRaids)

    static func raidWon(_ town: String) {
        guard var pr = s.provinces[town] else { return }
        pr.loyalty = min(100, pr.loyalty + 10)
        s.provinces[town] = pr
        s.log.append("-1|\(town) stood with you against the raiders")
    }
    static func raidScale(_ town: String) -> Float { s.provinces[town] != nil ? (has("curfew") ? 1 : 2) : 1 }

    // MARK: Building

    // How many buildings the settlers have earned: one a three settlers, plus the hall at the capital.
    static func earned(_ key: String) -> Int {
        guard let pr = s.provinces[key] else { return 0 }
        return pr.settlers / 3 + (s.capital == key && pr.settlers >= 6 ? 1 : 0)
    }

    static func build(_ g: Game, _ key: String, x ax: Int, z az: Int) {
        guard var pr = s.provinces[key], pr.sites.count < earned(key), pr.tries < 400 else { return }
        let wantHall = s.capital == key && pr.settlers >= 6 && !pr.sites.contains { $0.count > 3 && $0[3] == 2 }
        let kind = wantHall ? 2 : (isBase(key) ? 1 : pr.sites.count % 2)
        let half = kind == 2 ? 6 : 3
        let w = g.world
        let n = pr.sites.count
        let r0: Float = isBase(key) ? 42 : 32
        // Four tries a second round a spiral of sites.
        for _ in 0..<4 {
            let t = pr.tries
            pr.tries += 1
            let a = Float(t) * 2.39996 + Float(n) * 0.7
            let r = r0 + Float(t % 9) * 3.5
            let cx = ax + Int(cosf(a) * r), cz = az + Int(sinf(a) * r)
            guard let y = siteFloor(w, cx, cz, half: half, others: pr.sites) else { continue }
            place(w, kind: kind, cx, y, cz)
            pr.sites.append([cx, y, cz, kind])
            s.provinces[key] = pr
            let what = ["a farm", "a cabin", "the capital's hall"][kind]
            g.onToast?("Settlers in \(displayName(key)) have built \(what)")
            return
        }
        s.provinces[key] = pr
    }

    static let natural: Set<String> = ["grass_block", "dirt", "coarse_dirt", "sand", "red_sand", "stone", "gravel", "snow_block",
                                       "podzol", "mud", "clay", "terracotta", "sandstone", "packed_mud", "rooted_dirt", "moss_block"]
    // A floor height where a (2 half + 1)-wide square is loaded, open, natural ground within one block of level, dry,
    // and clear of the other sites; nil when not.
    static func siteFloor(_ w: World, _ cx: Int, _ cz: Int, half: Int, others: [[Int]]) -> Int? {
        for o in others where abs(o[0] - cx) < half + 8 && abs(o[2] - cz) < half + 8 { return nil }
        var lo = Int.max, hi = Int.min
        for dx in -half...half { for dz in -half...half where (dx + dz) & 1 == 0 || abs(dx) == half || abs(dz) == half {
            let x = cx + dx, z = cz + dz
            guard w.isLoaded(x, z) else { return nil }
            var y = w.topY(x, z)
            guard y > SEA - 2 else { return nil }
            // Down through plants, snow layers and leaves to the ground.
            while y > 1, !w.solidAt(x, y, z) || Blocks.key(w.materialAt(x, y, z)).hasSuffix("leaves") { y -= 1 }
            let b = w.block(x, y, z)
            guard natural.contains(Blocks.key(b)) else { return nil }
            if Blocks.isLiquid(w.builtBlock(x, y + 1, z)) { return nil }
            for up in 1...5 where w.solidAt(x, y + up, z) && !Blocks.key(w.materialAt(x, y + up, z)).hasSuffix("leaves") { return nil }
            lo = min(lo, y); hi = max(hi, y)
            if hi - lo > 1 { return nil }
        } }
        return lo == Int.max ? nil : hi
    }

    static func bid(_ n: String, _ fallback: String = "oak_planks") -> BlockID { Blocks.has(n) ? Blocks.id(n) : Blocks.id(fallback) }

    // 0 farm: 7 x 7, a fence round a 5 x 5 of wheat on farmland with water at the centre.
    // 1 cabin: 7 x 7, log corners, plank walls 3 high with a doorway and windows, a plank roof, a lantern inside.
    // 2 hall: 13 x 13 in the capital's style, 5 high, a wide doorway, windows each side, a flag on a pole on top.
    static func place(_ w: World, kind: Int, _ cx: Int, _ y: Int, _ cz: Int) {
        let half = kind == 2 ? 6 : 3
        let dirt = bid("dirt", "stone")
        // Level the ground: fill under, clear over.
        for dx in -half...half { for dz in -half...half {
            let x = cx + dx, z = cz + dz
            var yy = y
            while yy > y - 4 && !w.solidAt(x, yy, z) { w.setBlock(x, yy, z, dirt); yy -= 1 }
            for up in 1...(kind == 2 ? 9 : 6) { w.setBlock(x, y + up, z, AIR) }
        } }
        switch kind {
        case 0:
            let soil = bid("farmland", "dirt"), crop = bid("wheat", "grass"), fence = bid("oak_fence", "oak_planks"), water = bid("water")
            for dx in -3...3 { for dz in -3...3 {
                let x = cx + dx, z = cz + dz
                if abs(dx) == 3 || abs(dz) == 3 {
                    w.setBlock(x, y, z, bid("grass_block", "dirt"))
                    if !(dz == 3 && dx == 0) { w.setBlock(x, y + 1, z, fence) }      // a gap to walk in on the south side
                } else if dx == 0 && dz == 0 {
                    w.setBlock(x, y, z, water)
                } else {
                    w.setBlock(x, y, z, soil); w.setBlock(x, y + 1, z, crop)
                }
            } }
        case 1:
            let wall = bid("spruce_planks"), log = bid("oak_log"), floor = bid("oak_planks"), glass = bid("glass_pane", "glass")
            for dx in -3...3 { for dz in -3...3 {
                let x = cx + dx, z = cz + dz
                w.setBlock(x, y, z, floor)
                let edge = abs(dx) == 3 || abs(dz) == 3
                for up in 1...3 where edge {
                    let corner = abs(dx) == 3 && abs(dz) == 3
                    let door = dz == 3 && dx == 0 && up <= 2
                    let window = up == 2 && !corner && ((abs(dx) == 3 && dz == 0) || (dz == -3 && dx == 0))
                    w.setBlock(x, y + up, z, door ? AIR : (corner ? log : (window ? glass : wall)))
                }
                w.setBlock(x, y + 4, z, floor)
            } }
            if Blocks.has("lantern") { w.setBlock(cx, y + 1, cz - 2, Blocks.id("lantern")) }
        default:
            let st = hallStyles[max(0, min(hallStyles.count - 1, s.hallStyle))]
            let wall = bid(st.wall), frame = bid(st.frame), floor = bid("oak_planks"), glass = bid("glass_pane", "glass")
            for dx in -6...6 { for dz in -6...6 {
                let x = cx + dx, z = cz + dz
                w.setBlock(x, y, z, frame)
                let edge = abs(dx) == 6 || abs(dz) == 6
                if !edge && abs(dx) < 6 && abs(dz) < 6 { w.setBlock(x, y, z, floor) }
                for up in 1...5 where edge {
                    let corner = abs(dx) == 6 && abs(dz) == 6
                    let door = dz == 6 && abs(dx) <= 1 && up <= 3
                    let window = (up == 2 || up == 3) && !corner && abs(dx) != 6 ? (dz == -6 && abs(dx) % 3 == 1) : ((up == 2 || up == 3) && !corner && abs(dz) % 3 == 1)
                    w.setBlock(x, y + up, z, door ? AIR : (corner || up == 5 ? frame : (window ? glass : wall)))
                }
                w.setBlock(x, y + 6, z, abs(dx) == 6 || abs(dz) == 6 ? frame : wall)
            } }
            // The flag: a log pole on the roof and four blocks of the nation's colour.
            for up in 7...11 { w.setBlock(cx, y + up, cz, frame) }
            let c = flagColors[max(0, min(flagColors.count - 1, s.flag))]
            let cloth = Blocks.has("taken_flag") && !Blocks.has(c.wool) ? Blocks.id("taken_flag") : bid(c.wool, "white_wool")
            for (fx, fy) in [(1, 10), (2, 10), (1, 11), (2, 11), (3, 10), (3, 11)] { w.setBlock(cx + fx, y + fy, cz, cloth) }
            if Blocks.has("lantern") { for (lx, lz) in [(-4, -4), (4, -4), (-4, 4), (4, 4)] { w.setBlock(cx + lx, y + 1, cz + lz, Blocks.id("lantern")) } }
        }
    }

    // MARK: Settlers as townsfolk

    static func settle(_ g: Game, _ town: String) {
        guard var pr = s.provinces[town], pr.spawned < min(walkers, pr.settlers),
              let home = pr.sites.first(where: { $0.count > 3 && $0[3] == 1 }) ?? pr.sites.first else { return }
        let w = g.world
        let p = V3(Float(home[0]) + 0.5, Float(home[1] + 1), Float(home[2]) + 0.5)
        guard w.isLoaded(home[0], home[2]), simd_length(p - g.player.pos) > 12 else { return }   // not popping in under your eyes
        let m = Mob(.villager, at: p)
        guard !m.collides(m.pos, w) else { return }
        m.home = p
        m.persistent = true
        Townsfolk.setup(m, tag: "", game: g)
        if var v = m.villager { v.town = town; m.villager = v }
        g.mobs.mobs.append(m)
        pr.spawned += 1
        s.provinces[town] = pr
    }

    // MARK: The map (WorldMap.drawLines)

    static func mapProvinces(_ out: inout [HudLine], _ g: Game, x0: Float, y0: Float, cols: Int, rows: Int, px: Float, wx: Float, wz: Float, bpc: Int, s sc: Float) {
        guard g.dim.dim == .overworld else { return }
        let col = flagColors[max(0, min(flagColors.count - 1, s.flag))].c
        for p in provinces(g) {
            guard let q = MapDraw.project(Float(p.x), Float(p.z), x0: x0, y0: y0, cols: cols, rows: rows, px: px, wx: wx, wz: wz, bpc: bpc) else { continue }
            let cap = s.capital == p.key
            let r: Float = cap ? 8 : 6
            out.append(HudLine(text: "", x: q.x - (r + 1) * sc, y: q.y - (r + 1) * sc, scale: sc, bg: V4(0, 0, 0, 0.85), box: V2((r + 1) * 2 * sc, (r + 1) * 2 * sc)))
            out.append(HudLine(text: "", x: q.x - r * sc, y: q.y - r * sc, scale: sc, bg: col, box: V2(r * 2 * sc, r * 2 * sc)))
            if cap { out.append(HudLine(text: "*", x: q.x - 2 * sc, y: q.y - 3 * sc, scale: sc, color: V4(1, 1, 1, 1))) }
            mapDrawn += 1
        }
    }
    static var mapDrawn = 0

    // MARK: The council (a bell in one of your towns)

    static func open(_ g: Game, town: String) {
        tick(g)
        g.openMenu(NationMenu(game: g, town: town))
    }
}

final class NationMenu: ListMenu {
    let town: String
    enum Item { case name, flag, tax, law(Int), capital, hall, province(String), log(String) }
    var items: [Item] = []

    init(game: Game, town: String) {
        self.town = town
        super.init("The Council of \(town)", game: game)
        refresh()
        game.sfx(.pageTurn, 0.6)
    }

    func refresh() {
        subtitle = "\(Nation.nationName(game)): \(Nation.provinces(game).count) province\(Nation.provinces(game).count == 1 ? "" : "s")"
        items = [.name, .flag, .tax]
        items += Nation.laws.indices.map { .law($0) }
        items += [.capital, .hall]
        items += Nation.provinces(game).map { .province($0.key) }
        items += Nation.s.log.suffix(5).reversed().map { .log($0) }
    }

    override var rows: [Row] {
        let st = Nation.s
        func icon(_ n: String) -> ItemStack { Items.has(n) ? ItemStack(Items.id(n), 1) : .empty }
        return items.map { it in
            switch it {
            case .name:
                return Row(icon: icon("written_book"), name: Nation.nationName(game), detail: "Press to rename your nation")
            case .flag:
                let c = Nation.flagColors[max(0, min(Nation.flagColors.count - 1, st.flag))]
                return Row(icon: icon(c.wool), name: "Flag: \(c.name)", detail: "Your provinces on the map, your hall's flag")
            case .tax:
                let t = max(0, min(2, st.tax))
                return Row(icon: icon("emerald"), name: "Taxes: \(Nation.taxNames[t])",
                           detail: ["Half the tribute; loyalty +3 a day", "Tribute as it is", "Tribute x1.6; loyalty -4 a day"][t],
                           value: Money.format(Nation.tributePerDay(town)) + "/day", good: t < 2)
            case .law(let i):
                let l = Nation.laws[i]
                let on = st.laws.contains(l.key)
                return Row(name: "Law: \(l.name)", detail: l.detail, value: on ? "in force" : "off", good: on)
            case .capital:
                let here = st.capital == town
                return Row(icon: icon("bell"), name: "Capital: " + (st.capital.map(Nation.displayName) ?? "none"),
                           detail: here ? "This is your capital" : "Press to make \(town) your capital", enabled: !here)
            case .hall:
                let built = st.capital.flatMap { st.provinces[$0] }?.sites.contains { $0.count > 3 && $0[3] == 2 } ?? false
                let sty = Nation.hallStyles[max(0, min(Nation.hallStyles.count - 1, st.hallStyle))]
                return Row(icon: icon(sty.wall), name: "Capital hall: \(sty.name)",
                           detail: built ? "Built" : (st.capital == nil ? "Name a capital first" : "Raised once six settlers come; press for another style"),
                           enabled: !built)
            case .province(let k):
                let p = st.provinces[k] ?? Nation.Province()
                return Row(name: Nation.displayName(k) + (st.capital == k ? " (capital)" : ""),
                           detail: "\(p.settlers) settlers, garrison \(p.garrison), \(p.sites.count) built",
                           value: "loyal \(Int(p.loyalty.rounded()))", enabled: false, good: p.loyalty >= 35)
            case .log(let e):
                let parts = e.split(separator: "|", maxSplits: 1).map(String.init)
                let d = Int(parts.first ?? "") ?? -1
                return Row(name: parts.last ?? e, detail: d >= 0 ? "Day \(d + 1)" : "", enabled: false)
            }
        }
    }

    override func pressed(_ index: Int) {
        guard index < items.count else { return }
        var st = Nation.s
        switch items[index] {
        case .name:
            let names = Nation.nameChoices(game)
            let i = names.firstIndex(of: Nation.nationName(game)) ?? -1
            st.name = names[(i + 1) % names.count]
            say("Your nation is \(st.name!)", good: true)
        case .flag:
            st.flag = (st.flag + 1) % Nation.flagColors.count
            say("Your flag is \(Nation.flagColors[st.flag].name)", good: true)
        case .tax:
            st.tax = (st.tax + 1) % 3
            say("Taxes are \(Nation.taxNames[st.tax].lowercased()) from today", good: st.tax < 2)
        case .law(let i):
            let k = Nation.laws[i].key
            if let j = st.laws.firstIndex(of: k) { st.laws.remove(at: j); say("\(Nation.laws[i].name) repealed", good: true) }
            else { st.laws.append(k); say("\(Nation.laws[i].name) is law", good: true) }
        case .capital:
            st.capital = town
            say("\(town) is your capital", good: true)
            game.sfx(.bell, 0.6)
        case .hall:
            st.hallStyle = (st.hallStyle + 1) % Nation.hallStyles.count
            say("The hall will be built in \(Nation.hallStyles[st.hallStyle].name.lowercased())", good: true)
        default: return
        }
        Nation.s = st
        game.sfx(.click, 0.4)
        refresh()
    }
}
