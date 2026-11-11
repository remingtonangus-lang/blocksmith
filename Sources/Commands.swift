import Foundation
import simd

// Command console (T or / on the keyboard, "Commands..." in the pause menu for a controller).
// The usual cheat commands with the reference game's syntax; names accept both the internal keys
// (diamond_sword, creeper) and Blocksmith display names (powderwight, sea_temple).
final class CommandMenu: Menu {
    var line = ""
    var historyPos = -1
    var logScroll = 0                      // P355: wrapped log lines scrolled back from the newest (wheel / right stick)
    // P510 (Nov 1 20:32, "combine shortcuts into commands"): the last, wide button opens the Go To list (the pause
    // menu's old Shortcuts page: teleports to the nearest place of a kind), and Back there comes back here.
    static let buttons = ["Run", "Day", "Night", "Clear Sky", "Rain", "Survival", "Creative", "Keyboard", "Go To a Place..."]
    static let suggestBase = 100           // suggestion buttons under the input line

    init(game: Game, prefill: String = "") {
        line = prefill
        super.init("Commands", game: game)
        showInventoryLabel = false
        width = 280; height = 195
        for i in CommandMenu.buttons.indices {
            let wide = i == 8
            let b = MenuSlot(8 + (i % 4) * 67, 136 + (i / 4) * 19, nil, 0, .button(i))
            b.w = wide ? 264 : 63; b.h = 16
            slots.append(b)
        }
        for k in 0..<3 {                       // three chips wide enough for names like pillager_outpost
            let b = MenuSlot(8 + k * 88, 31, nil, 0, .button(CommandMenu.suggestBase + k))
            b.w = 86; b.h = 12
            slots.append(b)
        }
    }
    override var capturesText: Bool { true }
    override func typed(_ s: String) {
        for c in s {
            if c == "\u{8}" { if !line.isEmpty { line.removeLast() } }
            else if c == "\t" { complete() }
            else if c == "\n" { run(); game.closeMenu(); return }          // Enter from the Quest's system keyboard
            else if line.count < 120 { line.append(c) }
        }
    }
    override func tick() {
        let inp = game.input
        if inp.tapped(Key.enter) { run(); game.closeMenu(); return }
        if inp.tapped(Key.tab) { complete() }
        let h = game.commandHistory
        if inp.tapped(Key.arrowUp), !h.isEmpty { historyPos = min(h.count - 1, historyPos + 1); line = h[h.count - 1 - historyPos] }
        if inp.tapped(Key.arrowDown) {
            historyPos = max(-1, historyPos - 1)
            line = historyPos >= 0 && !h.isEmpty ? h[h.count - 1 - historyPos] : ""
        }
    }
    override func buttonPressed(_ i: Int) {
        if i >= CommandMenu.suggestBase { complete(i - CommandMenu.suggestBase); game.sfx(.click, 0.4); return }
        switch i {
        case 0: run()
        case 1: game.command("/time set day")
        case 2: game.command("/time set night")
        case 3: game.command("/weather clear")
        case 4: game.command("/weather rain")
        case 5: game.command("/gamemode survival")
        case 6: game.command("/gamemode creative")
        case 7: game.openMenu(KeyboardMenu(game: game, target: self)); return
        case 8:
            let pm = PauseMenu(game: game)
            pm.page = .shortcuts; pm.fromCommands = true; pm.build()
            game.openMenu(pm)
            return
        default: break
        }
        game.sfx(.click, 0.4)
    }
    func run() {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        game.command(t)
        line = ""; historyPos = -1; logScroll = 0
    }

    // Suggestions for what is being typed (shown as buttons under the input line; Tab or a click takes one). Names
    // match with spaces or hyphens where the key has an underscore ("military base", "diamond-sword"): the Quest's
    // keyboard has no underscore. Taking a suggestion writes the key with its underscores.
    var suggestions: [String] {
        let words = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard let first = words.first else { return [] }
        if words.count == 1 {
            let pool = first.isEmpty ? Game.shortcutNames.map { "/" + $0 } : (Game.commandNames + Game.shortcutNames).map { "/" + $0 }
            let w = first.lowercased()
            return Array(pool.filter { $0.hasPrefix(w) && $0 != w }.sorted { ($0.count, $0) < ($1.count, $1) }.prefix(3))
        }
        let pool: [(key: String, name: String)]
        switch first.lowercased() {
        case "/give": pool = Items.allKeys.map { ($0, Items.name(Items.id($0))) }
        case "/summon": pool = MobKind.allCases.map { ($0.key, $0.name) }
        case "/locate": pool = Game.structureNames.map { ($0.0, $0.1) }
        case "/effect": pool = (["give", "clear"] + Effect.allCases.map { Game.snake("\($0)") }).map { ($0, $0) }
        default: return []
        }
        // The name is everything after the command up to a number or ~coordinate.
        var nameWords: [String] = []
        for w in words.dropFirst() { if Int(w) != nil || w.hasPrefix("~") || Float(w) != nil { break }; nameWords.append(w) }
        let typed = Game.norm(nameWords.joined(separator: " "))
        guard !typed.isEmpty || words.count == 2 else { return [] }
        var hits = pool.filter { $0.key.hasPrefix(typed) || Game.norm($0.name).hasPrefix(typed) }.map { $0.key }
        if hits.count < 4 { hits += pool.filter { $0.key.contains(typed) && !$0.key.hasPrefix(typed) }.map { $0.key } }
        if hits.count == 1 && hits[0] == typed { return [] }
        var seen = Set<String>()
        return Array(hits.filter { seen.insert($0).inserted }.sorted { ($0.count, $0) < ($1.count, $1) }.prefix(3))
    }

    // Tab / a suggestion button: take a suggestion (the first by default).
    func complete(_ k: Int = 0) {
        let sug = suggestions
        guard k < sug.count else { return }
        let words = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if words.count <= 1 { line = sug[k] + " "; return }
        var rest: [String] = []
        var inName = true
        for w in words.dropFirst() {
            if inName && (Int(w) != nil || w.hasPrefix("~") || Float(w) != nil) { inName = false }
            if !inName { rest.append(w) }
        }
        line = ([words[0], sug[k]] + rest).joined(separator: " ") + (rest.isEmpty ? " " : "")
    }
}

extension ItemRegistry {
    var allKeys: [String] { (0..<count).map { key(ItemID($0)) } }
}

extension Game {
    static let commandNames = ["help", "time", "weather", "gamemode", "difficulty", "tp", "give", "summon", "kill", "clear",
                               "effect", "xp", "locate", "seed", "spawnpoint", "setblock", "vessel"]
    static let structureNames: [(String, String)] = [
        ("village", "Village"), ("stronghold", "Stronghold"), ("monument", "Sunken Dreadnought"), ("mansion", "Brigand Roost"),
        ("ancient_city", "Buried Citadel"), ("trial_chambers", "Sealed Armoury"), ("temple", "Temple"),
        ("pillager_outpost", "Marauder Watchtower"), ("wild_camp", "Wild Camp"), ("frontier_site", "Frontier Site"), ("shipwreck", "Shipwreck"),
        ("buried_treasure", "Buried Treasure"), ("mineshaft", "Mineshaft"), ("ocean_ruin", "Ocean Ruin"),
        ("trail_ruins", "Trail Ruins"), ("desert_well", "Desert Well"), ("fossil", "Fossil"),
        ("fortress", "Brand Chapterhouse"), ("bastion", "Searwing Roost"), ("end_city", "Hollow Spire"),
        ("military_base", "Capital Citadel"), ("capital_city", "Capital City"), ("great_ruin", "Ancient Spire"), ("boreal_station", "Boreal Station"),
        ("brimstone_keep", "Brimstone Keep"), (HellWorks.kind, "Hell Works"),
        // Vessel encounters (ShipVessels.swift / CapitalShips.swift), found by region rather than as structures.
        ("warfrigate", "Stormwarden Frigate"), ("crawler", "Ironback Crawler"), ("frigate", "Meridian Frigate"), ("carriage", "Siege Carriage"),
        // P504: a Greywall Command base (a structure), and a train on its line (where its timetable has it now).
        ("greywall_base", "Greywall Base"), ("train", "Train")]

    // P474 (Oct 26 19:30-19:31, after /locate in creative: "What are the trail ruins? I don't even know what trail
    // ruins are"; "What the sealed armory is"; at the Sealed Armoury's spot, "Sunken dreadnought, huh?... Nothing"):
    // what each place is and how it is found, the line under a /locate result.
    static let placeAbout: [String: String] = [
        "village": "a farming town with houses, fields, a well, people to trade with and work for",
        "stronghold": "an old fortress buried deep underground, its gate room holds the way to the Hollow; follow a thrown Seeker Eye",
        "monument": "a Capital battleship sunk on the deep ocean floor, its hull guarded; dive, or take a submarine down",
        "mansion": "a brigand gang's log stockade deep in the dark forest, a long hall full of loot and armed men",
        "ancient_city": "never built in this game; there is none to find",
        "trial_chambers": "a Capital armoury sealed underground before the war (its halls 40 to 60 blocks down); dig down where it is marked, or find a cave tunnel into it",
        "temple": "a stone temple in the desert or jungle, its treasure under the floor and trapped",
        "pillager_outpost": "a marauders' timber watchtower on open ground, their captain at the top",
        "wild_camp": "a small camp in open country (hunters, prospectors, traders, or one left empty) with a chest",
        "frontier_site": "a ghost town, homestead, mission or other place people built out on the land",
        "shipwreck": "an old wooden ship, wrecked on a beach or on the sea floor, its chests still aboard",
        "buried_treasure": "a chest buried in a beach; dig where it is marked",
        "mineshaft": "abandoned mine tunnels underground, timbered, with rails, ore carts and cobwebs",
        "ocean_ruin": "sunken stone ruins on the sea floor, a chest among them",
        "trail_ruins": "an old roadside settlement buried in the ground, only its tops showing; dig the gravel round it for pottery and trinkets",
        "desert_well": "a lone stone well in the desert",
        "fossil": "the bones of a great beast buried in the rock",
        "fortress": "the Brand Order's walled house in the Emberdeep",
        "bastion": "a Searwing spire on a rock islet in the Emberdeep",
        "end_city": "violite towers on the Hollow's outer islands, guarded, with treasure at the top",
        "military_base": "a Capital citadel, the enemy's walled base, with guns, soldiers and an armoury",
        "capital_city": "a Capital city, walled, with avenues, guns and a garrison",
        "great_ruin": "a colossal ruined stone tower; a stair inside climbs to a chest at the top",
        "boreal_station": "a Meridian Navy post on the ice, manned by its marines, its vehicles parked in the yard",
        "brimstone_keep": "a walled castle over the lava sea in the Deep's hell band, holding the Sunderite Ore",
        HellWorks.kind: "the Brand Order's works in hell (a distillery, a gaol or a Brimsalt quarry), the only place to find Brimsalt and Tech Salvage",
        "warfrigate": "a Greywall warship under sail", "crawler": "a Greywall land ship on its patrol",
        "frigate": "a Meridian frigate on patrol", "carriage": "a Capital siege carriage on the move",
        "greywall_base": "a Greywall Command base: walls, gun towers, a garrison and a vault",
        "train": "a train running its line between the towns' stations"]

    static func snake(_ s: String) -> String {
        var out = ""
        for c in s { if c.isUppercase { out += "_" + c.lowercased() } else { out.append(c) } }
        return out
    }
    // Names typed with spaces or hyphens for underscores (the Quest's keyboard has no underscore).
    static func norm(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
    }
    // Shortcuts that locate the interesting places (Commands: /bases, /citadels, /frigates, /villages, /rare).
    static let shortcutNames = ["bases", "citadels", "frigates", "villages", "rare", "ending"]

    func say(_ s: String) {
        commandLog.append(s)
        if commandLog.count > 60 { commandLog.removeFirst(commandLog.count - 60) }
    }

    // Runs a command line (or posts a chat line) and reports into the console log; the first line
    // of the result also shows as a toast so it is visible after the console closes.
    func command(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        commandHistory.append(t)
        if commandHistory.count > 40 { commandHistory.removeFirst() }
        guard t.hasPrefix("/") else { say("<Player> \(t)"); return }
        say(t)
        let cmd = t.dropFirst().split(separator: " ").first.map { $0.lowercased() } ?? ""
        LocateJob.cmd = cmd
        let out = execute(t.dropFirst().split(separator: " ").map(String.init))
        report(cmd, out)
    }
    private func report(_ cmd: String, _ out: [String]) {
        // P456 (Oct 25 14:13, the commands list: "we got a duplicate here... two Boreal stations"): a place found again
        // replaces the line it had in the log (where the nearest one was when last asked) instead of listing it twice.
        if cmd == "locate" || Game.shortcutNames.contains(cmd) {
            for l in out {
                guard let colon = l.firstIndex(of: ":") else { continue }
                let head = "  " + l[..<colon] + ":"
                commandLog.removeAll { $0.hasPrefix(head) }
            }
        }
        for l in out { say("  " + l) }
        if let f = out.first { onToast?(f) }
    }

    // The nearest of each kind, one line each (the shortcut commands), nearest first.
    // P436: the other dimensions' generators for /locate (made once a seed; structure placement only, no chunks).
    private static var otherGens: [Dim: TerrainGenerator] = [:]
    private static var otherSeed: UInt64 = 0
    static func otherGen(_ d: Dim, seed: UInt64) -> TerrainGenerator {
        if otherSeed != seed { otherGens.removeAll(); otherSeed = seed }
        if let g = otherGens[d] { return g }
        let g: TerrainGenerator
        switch d {
        case .overworld: g = WorldGen(seed: seed)
        case .nether: g = EmberGen(seed: seed)
        case .end: g = HollowGen(seed: seed)
        case .deep: g = DeepGen(seed: seed)
        }
        otherGens[d] = g
        return g
    }
    static func dimName(_ d: Dim) -> String {
        switch d {
        case .overworld: return "the surface"
        case .nether: return "the Emberdeep"
        case .end: return "the Hollow"
        case .deep: return "the Deep"
        }
    }

    private func locateAll(_ keys: [String]) -> [String] {
        let entries = keys.compactMap { k in Game.structureNames.first { $0.0 == k } }
        if Game.arrivalHold && !Game.oldShortcutLand { return locateLater(entries, all: true) }      // (ledger 80)
        let snap = locateSnap(for: keys)
        return locateAllLines(entries, entries.map { locateFind($0.0, snap) })
    }
    private func locateAllLines(_ entries: [(String, String)], _ hits: [LocateHit]) -> [String] {
        var out: [(Int, String)] = []
        for (e, h) in zip(entries, hits) {
            for l in locateLines(e, h).prefix(1) {               // (P474: the place, not the line on what it is)
                let d = l.range(of: "(").flatMap { Int(l[$0.upperBound...].prefix { $0.isNumber }) } ?? Int.max
                out.append((d, l))
            }
        }
        return out.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    // Ledger 80 (Nov 11, the VR fuzz's stack sampler: a frigate shortcut held one frame 685 ms): /locate and the place
    // shortcuts (/bases, /rare...) searched on the frame, out to 40 rings of vessel encounter regions or 40 rings of a
    // structure's regions planned there, in every dimension for a kind this one lacks: /bases ran nine such searches
    // in one frame. The search is now split: what only the frame may read (the vessels and trains already out, the
    // generators) is taken on the frame (locateSnap), the search itself (locateFind) reads nothing else, and on the
    // headset it runs on a worker; its lines go to the console when it is done (locateTick, every frame), as the
    // command's would have. Host checks: all on the frame as before (same lines). BS_OLDSHORTCUT=1: on the frame.
    struct LocateSnap {
        var p: V3, seed: UInt64, dim: Dim, fleetSails: Bool, time: Double
        var gens: [(Dim, TerrainGenerator)]                  // this dimension's first
        var shipOut: [String: (IVec3, Float)] = [:]          // the nearest vessel of a kind already out
        var trainOut: (IVec3, Float, String)?                // the nearest train running
    }
    enum LocateHit {
        case none
        case structure(StructureStart, String)               // (start, " in <dimension>" or "")
        case vessel(IVec3, Float, Bool)                      // (point, distance, on the move)
        case train(IVec3, Float, String)
    }
    func locateSnap(for keys: [String]) -> LocateSnap {
        var s = LocateSnap(p: player.pos, seed: world.seed, dim: dim.dim, fleetSails: fleetSails, time: time, gens: [(dim.dim, world.gen)])
        if keys.contains(where: { k in !["warfrigate", "crawler", "frigate", "carriage", "train"].contains(k) }) {
            for d in Dim.allCases where d != dim.dim { s.gens.append((d, Game.otherGen(d, seed: world.seed))) }
        }
        for k in keys where ["warfrigate", "crawler", "frigate", "carriage"].contains(k) {
            let role = k == "frigate" ? "capfrigate" : k
            for sh in world.ships.list where sh.role == role && !sh.wrecked {
                let d = simd_length(V2(sh.pos.x - player.pos.x, sh.pos.z - player.pos.z))
                if s.shipOut[k] == nil || d < s.shipOut[k]!.1 { s.shipOut[k] = (IVec3(Int(floor(sh.pos.x)), Int(floor(sh.pos.y)), Int(floor(sh.pos.z))), d) }
            }
        }
        if keys.contains("train") && dim.dim == .overworld {
            for tr in Trains.trains.values where !tr.wrecked && tr.track.dim == .overworld {
                guard let c = tr.cars.first else { continue }
                let d = simd_length(V2(c.pos.x - player.pos.x, c.pos.z - player.pos.z))
                if s.trainOut == nil || d < s.trainOut!.1 { s.trainOut = (IVec3(Int(floor(c.pos.x)), Int(floor(c.pos.y)), Int(floor(c.pos.z))), d, tr.track.name) }
            }
        }
        return s
    }
    // The search (no game state but the snapshot: also run on a worker). onFrame: the shared train track cache.
    static func locateFind(_ key: String, _ s: LocateSnap, onFrame: Bool = true) -> LocateHit {
        if key == "train" {
            if let t = s.trainOut { return .train(t.0, t.1, t.2) }
            guard s.dim == .overworld, let wg = s.gens.first?.1 as? WorldGen,
                  let t = Game.trainLines(wg, from: s.p, time: s.time, cached: onFrame) else { return .none }
            return .train(t.0, t.1, t.2)
        }
        if ["warfrigate", "crawler", "frigate", "carriage"].contains(key) {
            if let o = s.shipOut[key] { return .vessel(o.0, o.1, true) }
            guard let g = s.gens.first?.1, let v = Game.vesselRegions(key, from: s.p, seed: s.seed, gen: g, fleetSails: s.fleetSails) else { return .none }
            return .vessel(v.0, v.1, false)
        }
        // P436 (Oct 24 15:46, "I need a command so I can find shit in another [dimension]"): what this dimension
        // doesn't hold is looked up in the others (the surface, the Deep and its hell band, the Emberdeep, the Hollow),
        // with the dimension named; x and z are the same in every dimension.
        // (P504: near first, then out to 40 regions: the nearest however far, not only one close by.)
        for reach in [6, 40] {
            for (i, (d, g)) in s.gens.enumerated() {
                guard let sc = g.structures, let st = sc.nearest(key, x: Int(s.p.x), z: Int(s.p.z), maxRegions: reach) else { continue }
                return .structure(st, i == 0 ? "" : " in " + Game.dimName(d))
            }
        }
        return .none
    }
    // The console lines for a search's answer (on the frame: marks the map).
    func locateLines(_ entry: (String, String), _ hit: LocateHit) -> [String] {
        switch hit {
        case .train(let c, let d, let line):
            return ["Train: \(c.x) ~ \(c.z) (\(Int(d)) blocks, on the \(line))"]
        case .vessel(let c, let d, let moving):
            return ["\(entry.1): \(c.x) ~ \(c.z) (\(Int(d)) blocks, \(moving ? "on the move" : "patrols"))"]
        case .none:
            if entry.0 == "train" { return ["Could not find a railway with a train running in this world"] }
            if ["warfrigate", "crawler", "frigate", "carriage"].contains(entry.0) {
                return [entry.0 == "warfrigate" && !fleetSails ? "The Stormwarden Frigates sail once a Greywall Fortress falls"
                                                               : "Could not find a \(entry.1) nearby"]
            }
            return ["There is no \(entry.1) in this world"]
        case .structure(let s, let whereIn):
            let dx = Float(s.anchor.x) - player.pos.x, dz = Float(s.anchor.z) - player.pos.z
            // P474: how deep it lies (a place under the ground or the sea shows nothing where he stands), it goes on
            // his map, and what it is.
            var depth = ""
            if whereIn.isEmpty {
                let top = world.gen.column(s.anchor.x, s.anchor.z).height
                if s.anchor.y < top - 6 {
                    depth = ", underground: its floor at y \(s.anchor.y - YOFF), \(top - s.anchor.y) blocks under the \(top < SEA - 2 ? "sea floor" : "surface")"
                } else if top < SEA - 2 { depth = ", on the sea floor \(max(0, SEA - s.anchor.y)) blocks down" }
                MapCache.shared.discover(self, kind: entry.0, x: s.anchor.x, z: s.anchor.z, name: entry.1, silent: true)
            }
            var out = ["\(entry.1)\(whereIn): \(s.anchor.x) ~ \(s.anchor.z) (\(Int(sqrtf(dx * dx + dz * dz))) blocks\(depth))\(whereIn.isEmpty ? ", marked on your map" : "")"]
            if let about = Game.placeAbout[entry.0] { out.append(about.prefix(1).uppercased() + about.dropFirst() + ".") }
            return out
        }
    }
    // The headset: the search on a worker (one at a time); the command's lines come when it is done.
    private func locateLater(_ entries: [(String, String)], all: Bool) -> [String] {
        guard LocateJob.pending == nil else { return ["Still looking..."] }
        let snap = locateSnap(for: entries.map { $0.0 })
        LocateJob.pending = (LocateJob.cmd, entries, all)
        DispatchQueue.global(qos: .userInitiated).async {
            let hits = entries.map { Game.locateFind($0.0, snap, onFrame: false) }
            LocateJob.lock.lock(); LocateJob.hits = hits; LocateJob.lock.unlock()
        }
        return []
    }
    func locateTick() {
        guard let (cmd, entries, all) = LocateJob.pending else { return }
        LocateJob.lock.lock(); let h = LocateJob.hits; LocateJob.hits = nil; LocateJob.lock.unlock()
        guard let hits = h else { return }
        LocateJob.pending = nil
        let out = all ? locateAllLines(entries, hits) : locateLines(entries[0], hits[0])
        report(cmd, out)
    }

    private func execute(_ raw: [String]) -> [String] {
        guard let cmd = raw.first?.lowercased() else { return [] }
        // Multi-word names (spaces for underscores) join into one argument: "/give diamond sword 3", "/locate military base".
        var a = raw
        if ["give", "summon", "locate", "setblock"].contains(cmd) && a.count > 2 {
            let start = cmd == "setblock" ? 4 : 1
            if a.count > start {
                var end = start + 1
                if cmd == "setblock" { end = a.count }
                else { while end < a.count && Int(a[end]) == nil && Float(a[end]) == nil && !a[end].hasPrefix("~") { end += 1 } }
                if end - start > 1 { a = Array(a[..<start]) + [a[start..<end].joined(separator: "_")] + Array(a[end...]) }
            }
        }
        func num(_ i: Int) -> Int? { i < a.count ? Int(a[i]) : nil }
        func coord(_ i: Int, _ base: Float) -> Float? {
            guard i < a.count else { return nil }
            let s = a[i]
            // Finite and inside 30 million blocks: "nan", "inf" or 1e20 parsed fine and then trapped in the first
            // Int(floor()) of a block coordinate.
            let v: Float? = s.hasPrefix("~") ? base + (Float(s.dropFirst()) ?? 0) : Float(s)
            guard let r = v, r.isFinite, abs(r) < 30_000_000 else { return nil }
            return r
        }
        switch cmd {
        case "help", "?":
            return ["Commands: " + Game.commandNames.joined(separator: " "),
                    "Tab completes names; arrow keys recall earlier commands."]
        case "seed":
            return ["Seed: \(world.seed)"]
        case "time":
            guard a.count >= 2 else { return ["Usage: /time set|add|query <value>"] }
            let day = floor(time / DAY_LENGTH) * DAY_LENGTH
            let named: [String: Double] = ["day": 1000, "noon": 6000, "sunset": 12000, "night": 13000, "midnight": 18000, "sunrise": 23000]
            // Finite and of sane size: "nan", "inf" or 1e30 made the clock NaN / huge, and the pause screen's day number
            // and the moon phase convert it to Int (undefined in the release build).
            let raw = a.count > 2 ? (named[a[2].lowercased()] ?? Double(a[2])) : nil
            let value: Double? = raw.flatMap { $0.isFinite && abs($0) < 1e12 ? $0 : nil }
            switch a[1] {
            case "set":
                guard let v = value else { return ["Usage: /time set day|noon|night|midnight|<ticks>"] }
                time = day + v.truncatingRemainder(dividingBy: 24000) / 24000 * DAY_LENGTH
                return ["Set the time to \(Int(v))"]
            case "add":
                guard let v = value else { return ["Usage: /time add <ticks>"] }
                time += v / 24000 * DAY_LENGTH
                return ["Added \(Int(v)) to the time"]
            default:
                return ["The time is \(Int(dayFraction * 24000)) (day \(Int(time / DAY_LENGTH) + 1))"]
            }
        case "weather":
            guard a.count >= 2 else { return ["Usage: /weather clear|rain|thunder"] }
            let secs = Float(num(2) ?? 6000)
            switch a[1] {
            case "clear": weather.raining = false; weather.thundering = false; weather.rainTime = secs; weather.thunderTime = secs
            case "rain": weather.raining = true; weather.thundering = false; weather.rainTime = secs
            case "thunder": weather.raining = true; weather.thundering = true; weather.rainTime = secs; weather.thunderTime = secs
            default: return ["Unknown weather \(a[1])"]
            }
            return ["Changing to \(a[1] == "clear" ? "clear" : a[1])"]
        case "gamemode", "gm":
            guard a.count >= 2 else { return ["Usage: /gamemode survival|creative"] }
            let want: Bool
            switch a[1].lowercased() { case "survival", "s", "0": want = true; case "creative", "c", "1": want = false
            default: return ["Unknown game mode \(a[1])"] }
            if survival != want { toggleMode() }
            return ["Set own game mode to \(want ? "Survival" : "Creative") Mode"]
        case "difficulty":
            // P302: six levels; a name without its space ("veryeasy", "very_easy") or a number 0-5.
            guard a.count >= 2 else { return ["The difficulty is \(Difficulty.name(diffLevel))"] }
            func squash(_ t: String) -> String { t.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "") }
            let names = Difficulty.names.map(squash)
            guard let d = names.firstIndex(of: squash(a[1])) ?? num(1).flatMap({ (0...5).contains($0) ? $0 : nil }) else {
                return ["Unknown difficulty \(a[1])"]
            }
            diffLevel = d
            return ["The difficulty has been set to \(Difficulty.name(d))"]
        case "tp", "teleport":
            let p = player.pos
            guard let x = coord(1, p.x), let y = coord(2, p.y - Float(YOFF)), let z = coord(3, p.z) else { return ["Usage: /tp <x> <y> <z> (~ for relative)"] }
            player.pos = V3(x, y + Float(YOFF), z)
            player.vel = .zero
            player.airPeak = player.pos.y
            return [String(format: "Teleported Player to %.1f, %.1f, %.1f", x, y, z)]
        case "give":
            guard a.count >= 2 else { return ["Usage: /give <item> [count]"] }
            let n = Game.norm(a[1])
            let key = Items.has(n) ? n : Items.allKeys.first { Game.norm(Items.name(Items.id($0))) == n }
            guard let k = key else { return ["Unknown item \(a[1])"] }
            let id = Items.id(k)
            var left = max(1, min(num(2) ?? 1, 64 * 36))
            let total = left
            while left > 0 {
                let c = min(left, Items.def(id).maxStack)
                let rest = inventory.add(ItemStack(id, c))
                if !rest.isEmpty { dropItem(rest, thrown: false) }
                left -= c
            }
            return ["Gave \(total) [\(Items.name(id))] to Player"]
        case "summon":
            guard a.count >= 2 else { return ["Usage: /summon <mob> [x y z]"] }
            let n = Game.norm(a[1])
            guard let k = MobKind.named(n) ?? MobKind.allCases.first(where: { Game.norm($0.name) == n }) else { return ["Unknown mob \(a[1])"] }
            let f = V3(-sinf(player.yaw), 0, -cosf(player.yaw))
            var at = player.pos + f * 3
            if let x = coord(2, player.pos.x), let y = coord(3, player.pos.y - Float(YOFF)), let z = coord(4, player.pos.z) { at = V3(x, y + Float(YOFF), z) }
            let m = Mob(k, at: at)
            m.yaw = player.yaw + .pi
            mobs.mobs.append(m)
            return ["Summoned new \(k.name)"]
        case "vessel":
            return vesselCommand(a)
        case "kill":
            if a.count >= 2 && a[1] == "@e" {
                let n = mobs.mobs.count
                for m in mobs.mobs { m.health = 0 }
                return ["Killed \(n) entities"]
            }
            if survival { die("fell out of the world") } else { return ["Player can't be killed in Creative (use /gamemode survival)"] }
            return ["Killed Player"]
        case "clear":
            var n = 0
            for c in [inventory.main, inventory.armor, inventory.offhand] {
                for i in 0..<c.count where !c[i].isEmpty { n += c[i].count; c[i] = .empty }
            }
            return ["Removed \(n) item(s) from Player"]
        case "effect":
            guard a.count >= 2 else { return ["Usage: /effect give <effect> [seconds] [level] | /effect clear"] }
            if a[1] == "clear" { effects.clear(); return ["Removed every effect from Player"] }
            guard a[1] == "give", a.count >= 3 else { return ["Usage: /effect give <effect> [seconds] [level]"] }
            let n = Game.norm(a[2]).replacingOccurrences(of: "_", with: "")
            guard let e = Effect.allCases.first(where: { "\($0)".lowercased() == n }) else { return ["Unknown effect \(a[2])"] }
            // Clamped: an Int.min level overflowed the - 1, a huge duration overflowed the HUD timer.
            applyEffect(e, amp: min(255, max(1, num(4) ?? 1)) - 1, seconds: Float(min(1_000_000, max(0, num(3) ?? 30))))
            return ["Applied effect \(Game.snake("\(e)")) to Player"]
        case "xp", "experience":
            guard a.count >= 2 else { return ["Usage: /xp <amount>[L]"] }
            if a[1].hasSuffix("L") || a[1].hasSuffix("l"), let l = Int(a[1].dropLast()) {
                xpLevel = max(0, min(1_000_000, xpLevel + max(-1_000_000, min(1_000_000, l))))
                return ["Gave \(l) experience levels to Player"]
            }
            guard let v = Int(a[1]), v > 0 else { return ["Usage: /xp <amount>[L]"] }
            addXP(min(v, 100_000_000))                   // n * 2 in the Mending split overflowed near Int.max
            return ["Gave \(v) experience points to Player"]
        // P355: every kind under one shortcut only (the Capital Citadel was listed by both /bases and /citadels).
        case "ending": return endingCommand(a)                 // P438 (AshEnding.swift)
        // P504 (Nov 1 09:33, Remington: "I want 'rare' and 'bases' to show the nearest anything regardless of if it's
        // nearby or not including capital citadels and cities, or a crawler, a train or frigate"): every kind of base
        // and war machine, the nearest of each however far.
        case "bases": return locateAll(["military_base", "capital_city", "boreal_station", "greywall_base", "crawler", "frigate", "warfrigate", "carriage", "train"])
        case "cities": return locateAll(["capital_city"])
        case "citadels": return locateAll(["military_base"])
        case "frigates": return locateAll(["frigate", "warfrigate"])
        case "villages": return locateAll(["village"])
        case "rare": return locateAll(["mansion", "great_ruin", "temple", "pillager_outpost", "trail_ruins", "monument", "trial_chambers", "ancient_city"])
        case "locate":
            guard a.count >= 2 else { return ["Usage: /locate <structure>   Shortcuts: /bases /citadels /frigates /villages /rare"] }
            let n = Game.norm(a[1])
            guard let entry = Game.structureNames.first(where: { $0.0 == n || Game.norm($0.1) == n }) else { return ["Unknown structure \(a[1])"] }
            if Game.arrivalHold && !Game.oldShortcutLand { return locateLater([entry], all: false) }      // (ledger 80)
            return locateLines(entry, locateFind(entry.0, locateSnap(for: [entry.0])))
        case "spawnpoint":
            spawnPoint = player.pos
            return [String(format: "Set spawn point to %.0f, %.0f, %.0f", player.pos.x, player.pos.y - Float(YOFF), player.pos.z)]
        case "setblock":
            guard a.count >= 5, let x = coord(1, player.pos.x), let y = coord(2, player.pos.y - Float(YOFF)), let z = coord(3, player.pos.z) else {
                return ["Usage: /setblock <x> <y> <z> <block>"]
            }
            let n = Game.norm(a[4])
            guard Blocks.has(n) else { return ["Unknown block \(a[4])"] }
            world.setBlock(Int(floor(x)), Int(floor(y)) + YOFF, Int(floor(z)), Blocks.id(n))
            return ["Changed the block"]
        default:
            return ["Unknown command: \(cmd). Type /help for a list"]
        }
    }
}

// A /locate or place shortcut searching on a worker (ledger 80): the command, its places and whether it lists them
// all (frame thread), and the answers (under the lock).
enum LocateJob {
    static let lock = NSLock()
    static var cmd = ""
    static var pending: (String, [(String, String)], Bool)?
    static var hits: [Game.LocateHit]?
}
