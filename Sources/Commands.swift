import Foundation
import simd

// Command console (T or / on the keyboard, "Commands..." in the pause menu for a controller).
// The usual cheat commands with the reference game's syntax; names accept both the internal keys
// (diamond_sword, creeper) and Blocksmith display names (hisser, sea_temple).
final class CommandMenu: Menu {
    var line = ""
    var historyPos = -1
    static let buttons = ["Run", "Day", "Night", "Clear Sky", "Rain", "Survival", "Creative", "Keyboard"]

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

    // Tab: complete the word being typed from command names, then items, mobs, structures.
    func complete() {
        var words = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard let last = words.last else { return }
        let pool: [String]
        if words.count == 1 { pool = Game.commandNames.map { "/" + $0 } }
        else {
            switch words[0] {
            case "/give": pool = Items.allKeys
            case "/summon": pool = MobKind.allCases.map { $0.key }
            case "/locate": pool = Game.structureNames.map { $0.0 }
            case "/effect": pool = ["give", "clear"] + Effect.allCases.map { Game.snake("\($0)") }
            default: pool = []
            }
        }
        let hits = pool.filter { $0.hasPrefix(last) && $0 != last }.sorted()
        guard let first = hits.first else { return }
        words[words.count - 1] = first
        line = words.joined(separator: " ")
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
        ("military_base", "Capital Citadel"),
        // Vessel encounters (ShipVessels.swift / CapitalShips.swift), found by region rather than as structures.
        ("warfrigate", "Stormwarden Frigate"), ("crawler", "Ironback Crawler"), ("frigate", "Capital Frigate"), ("carriage", "Siege Carriage")]

    static func snake(_ s: String) -> String {
        var out = ""
        for c in s { if c.isUppercase { out += "_" + c.lowercased() } else { out.append(c) } }
        return out
    }
    static func norm(_ s: String) -> String { s.lowercased().replacingOccurrences(of: " ", with: "_") }

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

    private func execute(_ a: [String]) -> [String] {
        guard let cmd = a.first?.lowercased() else { return [] }
        func num(_ i: Int) -> Int? { i < a.count ? Int(a[i]) : nil }
        func coord(_ i: Int, _ base: Float) -> Float? {
            guard i < a.count else { return nil }
            let s = a[i]
            if s.hasPrefix("~") { return base + (Float(s.dropFirst()) ?? 0) }
            return Float(s)
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
            let value = a.count > 2 ? (named[a[2].lowercased()] ?? Double(a[2])) : nil
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
            applyEffect(e, amp: max(0, (num(4) ?? 1) - 1), seconds: Float(num(3) ?? 30))
            return ["Applied effect \(Game.snake("\(e)")) to Player"]
        case "xp", "experience":
            guard a.count >= 2 else { return ["Usage: /xp <amount>[L]"] }
            if a[1].hasSuffix("L") || a[1].hasSuffix("l"), let l = Int(a[1].dropLast()) {
                xpLevel = max(0, xpLevel + l)
                return ["Gave \(l) experience levels to Player"]
            }
            guard let v = Int(a[1]), v > 0 else { return ["Usage: /xp <amount>[L]"] }
            addXP(v)
            return ["Gave \(v) experience points to Player"]
        case "locate":
            guard a.count >= 2 else { return ["Usage: /locate <structure>"] }
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
                return ["The nearest \(entry.1) patrols around [\(b.0.x), ~, \(b.0.z)] (\(Int(b.1)) blocks away)"]
            }
            guard let sc = world.gen.structures,
                  let s = sc.nearest(entry.0, x: Int(player.pos.x), z: Int(player.pos.z)) else {
                return ["Could not find a \(entry.1) nearby"]
            }
            let dx = Float(s.anchor.x) - player.pos.x, dz = Float(s.anchor.z) - player.pos.z
            return ["The nearest \(entry.1) is at [\(s.anchor.x), ~, \(s.anchor.z)] (\(Int(sqrtf(dx * dx + dz * dz))) blocks away)"]
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
