import Foundation
import simd

// Command console (T or / on the keyboard, "Commands..." in the pause menu for a controller).
// The usual cheat commands with the reference game's syntax; names accept both the internal keys
// (diamond_sword, creeper) and Blocksmith display names (hisser, sea_temple).
final class CommandMenu: Menu {
    var line = ""
    var historyPos = -1
    static let buttons = ["Run", "Day", "Night", "Clear Sky", "Rain", "Survival", "Creative", "Keyboard"]
    static let suggestBase = 100           // suggestion buttons under the input line

    init(game: Game, prefill: String = "") {
        line = prefill
        super.init("Commands", game: game)
        showInventoryLabel = false
        width = 280; height = 176
        for i in CommandMenu.buttons.indices {
            let b = MenuSlot(8 + (i % 4) * 67, 136 + (i / 4) * 19, nil, 0, .button(i))
            b.w = 63; b.h = 16
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
        default: break
        }
        game.sfx(.click, 0.4)
    }
    func run() {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        game.command(t)
        line = ""; historyPos = -1
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
        ("village", "Village"), ("stronghold", "Stronghold"), ("monument", "Sea Temple"), ("mansion", "Forest Manor"),
        ("ancient_city", "Buried Citadel"), ("trial_chambers", "Proving Halls"), ("temple", "Temple"),
        ("pillager_outpost", "Marauder Watchtower"), ("ruined_portal", "Ruined Gate"), ("shipwreck", "Shipwreck"),
        ("buried_treasure", "Buried Treasure"), ("mineshaft", "Mineshaft"), ("ocean_ruin", "Ocean Ruin"),
        ("trail_ruins", "Trail Ruins"), ("desert_well", "Desert Well"), ("fossil", "Fossil"),
        ("fortress", "Cinder Fortress"), ("bastion", "Boarling Keep"), ("end_city", "Hollow Spire"),
        ("military_base", "Capital Citadel"), ("capital_city", "Capital City"), ("great_ruin", "Ancient Spire"),
        // Vessel encounters (ShipVessels.swift / CapitalShips.swift), found by region rather than as structures.
        ("warfrigate", "Stormwarden Frigate"), ("crawler", "Ironback Crawler"), ("frigate", "Capital Frigate"), ("carriage", "Siege Carriage")]

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
    static let shortcutNames = ["bases", "citadels", "frigates", "villages", "rare"]

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
        let out = execute(t.dropFirst().split(separator: " ").map(String.init))
        for l in out { say("  " + l) }
        if let f = out.first { onToast?(f) }
    }

    // The nearest of each kind, one line each (the shortcut commands), nearest first.
    private func locateAll(_ keys: [String]) -> [String] {
        var out: [(Int, String)] = []
        for k in keys {
            for l in execute(["locate", k]) {
                let d = l.range(of: "(").flatMap { Int(l[$0.upperBound...].prefix { $0.isNumber }) } ?? Int.max
                out.append((d, l))
            }
        }
        return out.sorted { $0.0 < $1.0 }.map { $0.1 }
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
            guard a.count >= 2 else { return ["The difficulty is \(Game.difficultyNames[difficulty])"] }
            let names = Game.difficultyNames.map { $0.lowercased() }
            guard let d = names.firstIndex(of: a[1].lowercased()) ?? num(1).flatMap({ (0...3).contains($0) ? $0 : nil }) else {
                return ["Unknown difficulty \(a[1])"]
            }
            difficulty = d
            return ["The difficulty has been set to \(Game.difficultyNames[d])"]
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
        case "bases": return locateAll(["military_base"])
        case "cities": return locateAll(["capital_city"])
        case "citadels": return locateAll(["military_base", "ancient_city"])
        case "frigates": return locateAll(["frigate", "warfrigate"])
        case "villages": return locateAll(["village"])
        case "rare": return locateAll(["mansion", "great_ruin", "temple", "pillager_outpost", "trail_ruins", "monument", "trial_chambers"])
        case "locate":
            guard a.count >= 2 else { return ["Usage: /locate <structure>   Shortcuts: /bases /citadels /frigates /villages /rare"] }
            let n = Game.norm(a[1])
            guard let entry = Game.structureNames.first(where: { $0.0 == n || Game.norm($0.1) == n }) else { return ["Unknown structure \(a[1])"] }
            if ["warfrigate", "crawler", "frigate", "carriage"].contains(entry.0) {
                // Nearest encounter region of that vessel (a battle region has both capital ships).
                let R = Vessels.region
                let rx = floorDiv(Int(player.pos.x), R), rz = floorDiv(Int(player.pos.z), R)
                var best: (IVec3, Float)?
                for r in 0...12 { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
                    guard let e = Vessels.encounter(seed: world.seed, rx: rx + dx, rz: rz + dz, gen: world.gen) else { continue }
                    let match = e.0 == entry.0 || (e.0 == "battle" && (entry.0 == "warfrigate" || entry.0 == "crawler"))
                    if !match { continue }
                    let d = simd_length(V2(Float(e.1.x) - player.pos.x, Float(e.1.z) - player.pos.z))
                    if best == nil || d < best!.1 { best = (e.1, d) }
                } }
                if best != nil && r >= 2 { break } }
                guard let b = best else { return ["Could not find a \(entry.1) nearby"] }
                return ["\(entry.1): \(b.0.x) ~ \(b.0.z) (\(Int(b.1)) blocks, patrols)"]
            }
            guard let sc = world.gen.structures,
                  let s = sc.nearest(entry.0, x: Int(player.pos.x), z: Int(player.pos.z)) else {
                return ["Could not find a \(entry.1) nearby"]
            }
            let dx = Float(s.anchor.x) - player.pos.x, dz = Float(s.anchor.z) - player.pos.z
            return ["\(entry.1): \(s.anchor.x) ~ \(s.anchor.z) (\(Int(sqrtf(dx * dx + dz * dz))) blocks)"]
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
