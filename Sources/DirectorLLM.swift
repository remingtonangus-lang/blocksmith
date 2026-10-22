import Foundation
import simd
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Darwin)
import Darwin
#endif

// P266 (a, c, d, e): who plans the Director's events. One protocol, three backends:
//   Rules      (c) hand-tuned rules over the same world summary; always there, and the fallback for the others.
//   On-Device  (d) a small quantized model (Qwen2.5 0.5B Instruct Q4_K_M, Apache 2.0; quest/tools/push-director-model.sh)
//              run by llama.cpp in libdirectorllm.so (quest/c/llm), loaded with dlopen only after the story is beaten,
//              on a background thread at low priority; it only thinks while no frame of active play has come for
//              0.3 s (paused, a menu, asleep, loading, idle somewhere safe, the app in the background) and stops within
//              a token when play resumes. Its reply is held to the event JSON by a GBNF grammar. Unloaded under memory
//              pressure or when the Director is off; missing, failing or too slow: the rules plan instead.
//   Cloud      (e) the same request over HTTPS to a configurable endpoint (UserDefaults "directorCloud"; on the Quest
//              directorCloud=... in quest-settings.txt), off unless chosen; only the world summary is sent, no account
//              or device data. "mock" (the default endpoint) answers with a built-in mock server's reply, through the
//              same parser and checks.
// Every reply, whoever wrote it, goes through Director.accept (clamps, lists, the text filter).
protocol DirectorBackend: AnyObject {
    var name: String { get }
    var ready: Bool { get }                                    // can plan now (model present, transport there)
    func status() -> String
    // Blocking: on the planner's thread for the model and the cloud, at once for the rules. nil when it could not.
    func plan(_ summary: DirectorSummary, wanted: Int) -> [DirectorRequest]?
}

// The compact world summary every backend plans from (a).
struct DirectorSummary: Codable {
    var day = 1
    var night = false
    var dim = "overworld"
    var biome = ""
    var town: String? = nil
    var townDist: Int? = nil
    var volcano = false
    var places: [String] = []
    var health = 20
    var armour = 0
    var guns = 0
    var money = 0
    var honour = 0
    var standing = ""
    var outlaw = false
    var bounty = 0
    var factions: [String: Int] = [:]
    var tier = 1
    var strength = 0
    var deeds: [String] = []
    var recent: [String] = []
    var seen: [String] = []
    var active: [String] = []
    var allowed: [String] = []

    static func of(_ g: Game) -> DirectorSummary {
        var s = DirectorSummary()
        s.day = Int(g.time / DAY_LENGTH) + 1
        s.night = TownRaids.night(g.dayFraction)
        s.dim = g.dim.dim.rawValue
        let x = Int(floor(g.player.pos.x)), z = Int(floor(g.player.pos.z))
        s.biome = g.world.gen.column(x, z).biome.displayName
        if let (t, a) = Director.nearTown(g, within: 700) {
            s.town = t
            s.townDist = Int(simd_length(V2(Float(a.x - x), Float(a.z - z))))
        }
        s.volcano = Director.nearVolcano(g) != nil
        s.places = g.dim.dim == .overworld ? Array(Set(g.raidPlaces().map { $0.1 })).sorted() : []
        s.health = g.health
        s.armour = g.inventory.armorPoints
        s.guns = g.inventory.main.slots.filter { !$0.isEmpty && Guns.index($0.item) != nil }.count
        s.money = g.money / 100
        s.honour = Int(Honour.value)
        s.standing = Honour.standing(Honour.value)
        s.outlaw = Honour.isOutlaw
        s.bounty = BountyHunters.totalBounty / 100
        for f in FactionRep.tracked { s.factions[Director.key(f)] = Int(FactionRep.of(f)) }
        s.strength = Director.strength(g)
        s.tier = Director.tier(g)
        s.deeds = DirectorRules.deeds(g)
        s.recent = g.journal.suffix(40).filter { $0.pages == nil }.suffix(5).map { String($0.text.prefix(70)) }
        s.seen = Director.state.history.suffix(8).map { $0.split(separator: "|").prefix(3).joined(separator: ":") }
        s.active = Director.state.active.map { $0.t } + Director.state.queue.map { $0.t }
        s.allowed = Director.catalogue.filter { Director.unfit(g, $0) == nil }.map { $0.id }
        return s
    }

    var json: String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let d = try? enc.encode(self), let t = String(data: d, encoding: .utf8) else { return "{}" }
        return t
    }
}

// MARK: Rules (c)

enum DirectorRules {
    static let first = ["Eli", "Silas", "Abner", "Jeb", "Virgil", "Hank", "Cyrus", "Ezra", "Wade", "Cole", "Rufus", "Amos", "Josiah", "Tate",
                        "Mae", "Ada", "Hattie", "Clara", "Etta", "Nell", "Opal", "Ruth", "Lottie", "Wren"]
    static let last = ["Hollis", "Crane", "Barlow", "Pike", "Mercer", "Daggett", "Slade", "Thorne", "Kimble", "Varney", "Holt", "Rourke",
                       "Ashby", "Lusk", "Pruitt", "Garner", "Quill", "Tolliver", "Becket", "Sumner"]
    static let nick = ["Red", "Blind", "Gentleman", "Six-Finger", "Black", "Lucky", "Long", "Deacon", "Whistling", "Iron"]
    static func one(_ a: [String]) -> String { a.pick() ?? "" }
    static func person() -> String { "\(one(first)) \(one(last))" }
    static func outlaw() -> String { Rand.int(in: 0..<3) == 0 ? "\(one(nick)) \(one(last))" : person() }

    // What people say he has done (the rival's taunt; the model's summary).
    static func deeds(_ g: Game) -> [String] {
        var d: [String] = []
        if g.ashVictory { d.append("brought down the Ash Chancellor") }
        let bases = g.greywallAlarm.taken.count
        if bases > 0 { d.append("took \(bases) Greywall base\(bases == 1 ? "" : "s")") }
        let gangs = TownLaw.state.gangsBeaten?.count ?? 0
        if gangs > 0 { d.append("broke \(gangs) outlaw gang\(gangs == 1 ? "" : "s")") }
        if Legendaries.found.count > 0 { d.append("found \(Legendaries.found.count) legendary piece\(Legendaries.found.count == 1 ? "" : "s")") }
        if FactionRaids.beaten > 0 { d.append("beat off \(FactionRaids.beaten) faction raid\(FactionRaids.beaten == 1 ? "" : "s")") }
        if Honour.isOutlaw { d.append("rides as an outlaw") } else if Honour.value >= Honour.honourable { d.append("is known as an honest hand") }
        for e in Director.state.history.suffix(4) {
            let p = e.split(separator: "|").map(String.init)
            if p.count >= 3 && p[2] == "won" { d.append("finished \(p[1])") }
        }
        return Array(d.prefix(6))
    }
    static func deed(_ g: Game) -> String { deeds(g).pick() ?? "made a name out here" }

    // Weights for picking (context makes a fitting template likelier).
    static func weight(_ t: DirectorTemplate, _ s: DirectorSummary) -> Double {
        let worst = s.factions.values.min() ?? -30
        switch t.id {
        case "bounty": return 3
        case "town_raid": return 2
        case "counteroffensive": return worst <= -45 ? 4 : 1.5
        case "outpost": return worst <= -30 ? 2.5 : 1.5
        case "wreck", "supply_drop": return 2
        case "hostage": return 2
        case "storm": return 1
        case "eruption": return 2.5
        case "trader": return s.money > 50 ? 2 : 1
        case "rival": return Double(s.tier)
        case "incursion": return Double(s.tier) * 0.8
        case "warband": return 4
        case "dead_rise": return 3
        case "beasts": return 1.5
        case "gift": return s.honour > 10 ? 2.5 : 0.6
        case "legend": return 1.5
        default: return 1
        }
    }

    // A full request for a template (numbers, picks and text), from the summary.
    static func fill(_ t: DirectorTemplate, _ s: DirectorSummary) -> DirectorRequest {
        var r = DirectorRequest(t: t.id)
        let tr = Double(s.tier)
        for p in t.nums {
            let k = max(0, min(1, 0.22 * tr + Rand.double(in: -0.12...0.12)))
            r.n[p.key] = (p.lo + (p.hi - p.lo) * k).rounded()
        }
        if t.picks["faction"] != nil {
            let worst = s.factions.min { $0.value < $1.value }?.key ?? "capital"
            r.s["faction"] = t.id == "supply_drop" ? one(Director.factions) : worst
        }
        if let l = t.picks["loot"] { r.s["loot"] = l.pick() }
        if t.picks["goods"] != nil {
            let g = Director.rareGoods.filter { Items.has($0) }.shuffledRand()
            r.s["goods"] = g.first; r.s["goods2"] = g.dropFirst().first
        }
        if t.picks["beast"] != nil { r.s["beast"] = "\(Rand.int(in: 0..<max(1, Hunting.legends.count)))" }
        let (name, caller, open, win, lose) = words(t, r)
        r.s["name"] = name; r.s["caller"] = caller; r.s["open"] = open; r.s["win"] = win; r.s["lose"] = lose
        return r
    }
    static func fill(_ g: Game, _ t: DirectorTemplate) -> DirectorRequest { fill(t, DirectorSummary.of(g)) }

    // In-world text with placeholders ({town}, {dir}, {dist}, {reward}, {faction}, {place}, {name}).
    static func words(_ t: DirectorTemplate, _ r: DirectorRequest) -> (String, String, String, String, String) {
        let sheriff = "Sheriff \(one(last))"
        switch t.id {
        case "town_raid":
            return ("Raiders on {town}", "\(sheriff) of {town}",
                    one(["Riders were seen gathering in the hills. They mean to hit {town} after dark. We could use a gun like yours.",
                     "Word is a raiding party's coming for {town} tonight. Stand with us and the purse is yours."]),
                    "They're running! {town} owes you, friend.", "They burned half the stores. Where were you?")
        case "bounty":
            let n = outlaw()
            return (n, "\(sheriff), on the wire",
                    one(["\(n) robbed the stage and shot the driver. His gang rides {dir}, about {dist} blocks out. {reward} on his head, dead or alive.",
                     "Wanted: \(n). Last seen {dist} blocks {dir} of you, riding with his gang. The reward is {reward}."]),
                    "\(n) won't ride again. The reward's yours.", "\(n) slipped the net. He'll be laughing in some saloon tonight.")
        case "counteroffensive":
            return ("Strike on {place}", "A friendly operator",
                    "{faction} is mustering a strike on {place}. Get there and hold it, or they'll take what's yours.",
                    "They're pulling back. {place} holds.", "They hit {place} hard and left with what they could carry.")
        case "wreck":
            return (one(["The Downed Courier", "The Broken Keel", "The Last Run of the Margery"]), "A distress beacon",
                    "Mayday... craft down {dist} blocks {dir} of you... cargo intact... scavengers closing...",
                    "Whatever was in that hold is yours now.", "The scavengers stripped the wreck bare.")
        case "hostage":
            return ("Taken from {town}", "A frightened voice from {town}",
                    "They took one of ours from {town}! Outlaws, camped {dist} blocks {dir} of you. Please, bring them home alive.",
                    "You brought them home. {town} won't forget it.", "We waited all night. Nobody came back.")
        case "storm":
            return ("The Great Storm", "The weather station",
                    "A great storm is coming in fast. Get under a roof and keep your animals close.",
                    "The storm has passed. The sky's clearing.", "")
        case "eruption":
            return ("The Mountain Wakes", "A survey crew",
                    "The mountain's waking up! Keep your distance, but if you're close when it settles, there'll be glass and ember stone for the taking.",
                    "It's settled. Look around you: the fallout's worth gathering.", "")
        case "outpost":
            return ("A New {faction} Outpost", "A trapper on the trail",
                    "{faction} has thrown up an outpost {dist} blocks {dir} of you. Tents, soldiers, a pay chest. Thought you'd want to know.",
                    "The outpost's down. Their pay chest is yours.", "They've dug in and moved on. The chance is gone.")
        case "trader":
            return ("A Travelling Peddler", "A peddler's cheerful whistle",
                    "Rare goods, friend, rare goods! I'm on the road near you for a short while only. Bring emeralds!",
                    "Pleasure doing business! The road calls.", "")
        case "rival":
            return ("A Rival Calls You Out", "A voice on the wind",
                    "They say you {deed}. I say you got lucky. I'm coming to see for myself.",
                    "He talked big. He's quiet now. His purse is yours.", "He lost his nerve and rode off.")
        case "incursion":
            return ("A Rift from Below", "A miner, out of breath",
                    "The ground split open {dist} blocks {dir} of you! Things are crawling out of it, burning things!",
                    "The rift's gone cold. The towns are paying out {reward} for that.", "The rift spat out its creatures and closed. They're loose now.")
        case "warband":
            return (one(["The Ember Brand's Warband", "The Cinder Oath's Warband", "The Scorched Host's Warband"]), "A brand horn, close by",
                    "A warband has your scent. They are coming through the caverns behind you.",
                    "The warband is broken.", "The warband lost your trail.")
        case "dead_rise":
            return ("The Dead Rise at {town}", "The undertaker of {town}",
                    "The graves outside {town} are opening. The dead are walking toward the houses. Hurry!",
                    "They're back in the ground. {town} thanks you.", "Dawn came and burned them. Folks are asking where you were.")
        case "beasts":
            return ("Prowlers at {town}", "A rancher near {town}",
                    "Something's killing our herds outside {town}. Big cats. Hunt them down and the ranchers pay {reward}.",
                    "The herds are safe. Here's the bounty.", "They took three more calves and vanished into the hills.")
        case "gift":
            return ("A Gift from {town}", "A rider from {town}",
                    "A rider's on the way to you from {town}, carrying something with our thanks.",
                    "We'll always have a place for you in {town}.", "")
        case "supply_drop":
            return ("A Lost Supply Drop", "Static on a military band",
                    "Cargo drop off course... {dist} blocks {dir} of your position... recovery team en route... ({faction})",
                    "The crate is yours. Somebody's quartermaster is going to have a bad day.", "The recovery team got to it first.")
        case "legend":
            return ("A Legend Sighted", "An old hunter",
                    "I've seen it with my own eyes: {place}, {dist} blocks {dir} of you, far from its den. A hunt like this comes once.",
                    "You took {place}. They'll tell this one for years.", "It's gone back to the wild places.")
        default:
            return (t.title, "Radio", t.blurb, "Done.", "Too late.")
        }
    }
}

final class DirectorRulesBackend: DirectorBackend {
    let name = "Rules"
    var ready: Bool { true }
    func status() -> String { "rules (always available)" }
    func plan(_ s: DirectorSummary, wanted: Int) -> [DirectorRequest]? {
        let recent = Set(s.seen.suffix(3).map { String($0.split(separator: ":").first ?? "") } + s.active)
        var pool = Director.catalogue.filter { s.allowed.contains($0.id) && !recent.contains($0.id) }
        if pool.isEmpty { pool = Director.catalogue.filter { !recent.contains($0.id) && $0.dims.contains(Dim(rawValue: s.dim) ?? .overworld) } }
        var out: [DirectorRequest] = []
        while out.count < wanted && !pool.isEmpty {
            let total = pool.reduce(0) { $0 + DirectorRules.weight($1, s) }
            var roll = Rand.double(in: 0..<max(total, 0.0001))
            var pick = pool.count - 1
            for (i, t) in pool.enumerated() { roll -= DirectorRules.weight(t, s); if roll < 0 { pick = i; break } }
            out.append(DirectorRules.fill(pool[pick], s))
            pool.remove(at: pick)
        }
        return out
    }
}

// MARK: The prompt, the grammar and the reply (a)

enum DirectorPrompt {
    static let system = """
    You are the Director of Blocksmith, a frontier survival game. The player has beaten the main story. You plan events \
    that keep his world alive: pick templates from the catalogue, set their numbers within the ranges, and write short \
    in-world text (radio calls, names). Only use templates listed in "allowed". Do not repeat templates in "seen" or \
    "active". Match his strength (tier 1-4) and what he has done ("deeds"). Text may use {town} {dir} {dist} {reward} \
    {faction} {place} {name}. Plain words only: no links, no real people, no other games' names. Reply with JSON only.
    """

    static func catalogue() -> String {
        Director.catalogue.map { t in
            var line = "\(t.id): \(t.blurb)"
            if !t.nums.isEmpty { line += " | n: " + t.nums.map { "\($0.key) \(Int($0.lo))-\(Int($0.hi.rounded(.up))) (\($0.note))" }.joined(separator: ", ") }
            for (k, v) in t.picks.sorted(by: { $0.key < $1.key }) { line += " | s.\(k): " + (v.count > 8 ? v.prefix(8).joined(separator: "/") + "/..." : v.joined(separator: "/")) }
            return line
        }.joined(separator: "\n")
    }

    static func user(_ s: DirectorSummary, wanted: Int) -> String {
        """
        CATALOGUE
        \(catalogue())
        TEXT in s: name (max 28 chars), caller (who speaks, max 28), open (the call that starts it, max 170), win (max 130), lose (max 130).
        WORLD
        \(s.json)
        Plan \(wanted) event\(wanted == 1 ? "" : "s"). Answer as {"events":[{"t":"<template>","n":{...},"s":{...}}]}
        """
    }

    // GBNF: the reply is exactly the event JSON (templates from the catalogue, number and string maps, printable text).
    static func grammar(max events: Int) -> String {
        let ids = Director.catalogue.map { "\"\\\"\($0.id)\\\"\"" }.joined(separator: " | ")
        return """
        root ::= "{" ws "\\"events\\"" ws ":" ws "[" ws event (ws "," ws event){0,\(max(0, events - 1))} ws "]" ws "}"
        event ::= "{" ws "\\"t\\"" ws ":" ws tmpl ws "," ws "\\"n\\"" ws ":" ws nums ws "," ws "\\"s\\"" ws ":" ws strs ws "}"
        tmpl ::= \(ids)
        nums ::= "{" ws ( numkv ( ws "," ws numkv ){0,5} )? ws "}"
        numkv ::= key ws ":" ws number
        strs ::= "{" ws ( strkv ( ws "," ws strkv ){0,8} )? ws "}"
        strkv ::= key ws ":" ws string
        key ::= "\\"" [a-z0-9_]{1,12} "\\""
        number ::= "-"? [0-9]{1,5} ("." [0-9]{1,2})?
        string ::= "\\"" [A-Za-z0-9 .,'!?:;()&${}_-]{0,170} "\\""
        ws ::= [ \\n]{0,2}
        """
    }

    // The reply's events (anything else in it ignored; at most three).
    static func parse(_ text: String, source: String) -> [DirectorRequest]? {
        guard let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b,
              let d = String(text[a...b]).data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let list = root["events"] as? [Any] else { return nil }
        var out: [DirectorRequest] = []
        for item in list.prefix(3) {
            guard let o = item as? [String: Any], let t = o["t"] as? String else { continue }
            var r = DirectorRequest(t: t, source: source)
            for (k, v) in (o["n"] as? [String: Any]) ?? [:] {
                if let x = v as? NSNumber { r.n[k] = x.doubleValue } else if let x = v as? Double { r.n[k] = x } else if let x = v as? Int { r.n[k] = Double(x) }
            }
            for (k, v) in (o["s"] as? [String: Any]) ?? [:] { if let x = v as? String { r.s[k] = String(x.prefix(400)) } }
            out.append(r)
        }
        return out
    }
}

// MARK: On-device model (d)

enum DirectorLLM {
    typealias LoadFn = @convention(c) (UnsafePointer<CChar>?, Int32, Int32) -> Int32
    typealias GenFn = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int32, UInt32, UnsafeMutablePointer<CChar>?, Int32) -> Int32
    typealias VoidFn = @convention(c) () -> Void
    typealias IntFn = @convention(c) () -> Int32

    static var searchDirs: [String] = [WorldStore.base.deletingLastPathComponent().path]   // the Quest sets its files folders
    static let lock = NSLock()
    static var tried = false
    static var lib: UnsafeMutableRawPointer?
    static var load: LoadFn?, gen: GenFn?, unload: VoidFn?, beat: VoidFn?, quietFn: IntFn?, lower: VoidFn?, loadedFn: IntFn?
    static var busy = false                       // a plan is running (main thread reads it)
    static var slow = false                       // a plan took too long on this device: rules from now on (this session)
    static var failed = ""                        // why the model could not be used
    static var lastSeconds: Double = 0
    static var dropAsked = false                  // unload when the running plan ends

    static var modelPath: String? {
        searchDirs.map { $0 + "/director/model.gguf" }.first { FileManager.default.fileExists(atPath: $0) }
    }

    // The runner library, once (dlopen; nil on builds without it).
    static func open() -> Bool {
        if lib != nil { return true }
        if tried { return false }
        tried = true
        var names = ["libdirectorllm.so"]
        #if os(macOS)
        names = ["libdirectorllm.dylib", Bundle.main.bundlePath + "/Contents/Frameworks/libdirectorllm.dylib"]
        #endif
        for n in names { if let h = dlopen(n, RTLD_NOW) { lib = h; break } }
        guard let h = lib else { failed = "the model runner is not in this build"; return false }
        guard let l = dlsym(h, "dllm_load"), let g = dlsym(h, "dllm_generate"), let u = dlsym(h, "dllm_unload"),
              let b = dlsym(h, "dllm_heartbeat"), let q = dlsym(h, "dllm_quiet"), let p = dlsym(h, "dllm_lower_priority"),
              let d = dlsym(h, "dllm_loaded") else { failed = "the model runner is the wrong version"; lib = nil; return false }
        load = unsafeBitCast(l, to: LoadFn.self); gen = unsafeBitCast(g, to: GenFn.self); unload = unsafeBitCast(u, to: VoidFn.self)
        beat = unsafeBitCast(b, to: VoidFn.self); quietFn = unsafeBitCast(q, to: IntFn.self); lower = unsafeBitCast(p, to: VoidFn.self)
        loadedFn = unsafeBitCast(d, to: IntFn.self)
        return true
    }

    // Every frame of active play (Director.frame): generation pauses for it.
    static func heartbeat() { beat?() }
    static var quiet: Bool {
        if let q = quietFn { return q() != 0 }
        return false
    }
    static var loaded: Bool { (loadedFn?() ?? 0) != 0 }

    // Once a second: the model stays in memory only while the Director is on and set to it.
    static func idle(_ g: Game, wanted: Bool) {
        if !wanted && loaded { release() }
    }
    // Memory pressure (Android: APP_CMD_LOW_MEMORY), the Director switched off.
    static func release() {
        if busy { dropAsked = true; return }
        lock.lock(); unload?(); lock.unlock()
    }

    // On the planner's thread: wait for quiet, load if needed, generate; nil when it could not (the rules plan).
    static func plan(_ s: DirectorSummary, wanted: Int, cancelled: () -> Bool) -> [DirectorRequest]? {
        guard !slow, open(), let path = modelPath, let load, let gen else {
            if modelPath == nil && failed.isEmpty { failed = "model not installed" }
            return nil
        }
        lower?()
        let system = DirectorPrompt.system, user = DirectorPrompt.user(s, wanted: wanted), grammar = DirectorPrompt.grammar(max: wanted)
        var spent: Double = 0
        for _ in 0..<8 {
            // A quiet moment (never a frame of play).
            while !quiet { if cancelled() { return nil }; Thread.sleep(forTimeInterval: 0.25) }
            lock.lock()
            if !loaded {
                let rc = path.withCString { load($0, 2048, 2) }
                if rc != 0 { lock.unlock(); failed = "the model failed to load"; return nil }
            }
            let cap = 4096
            var out = [CChar](repeating: 0, count: cap)
            let t0 = Date()
            let rc = system.withCString { sp in user.withCString { up in grammar.withCString { gp in
                gen(sp, up, gp, 360, UInt32(truncatingIfNeeded: Rand.int(in: 1..<Int(Int32.max))), &out, Int32(cap))
            } } }
            spent += Date().timeIntervalSince(t0)
            lock.unlock()
            if dropAsked { dropAsked = false; release() }
            if rc >= 0 {
                lastSeconds = spent
                if spent > 120 { slow = true }                 // too slow on this device: rules from now on
                let text = String(cString: out)
                return DirectorPrompt.parse(text, source: "on-device model")
            }
            if rc != -2 { failed = rc == -3 ? "the reply ran too long" : "the model failed to answer"; return nil }
            if spent > 240 { slow = true; return nil }
        }
        return nil
    }
}

final class DirectorDeviceBackend: DirectorBackend {
    let name = "On-Device Model"
    var ready: Bool { !DirectorLLM.slow && DirectorLLM.modelPath != nil && DirectorLLM.open() }
    func status() -> String {
        if DirectorLLM.slow { return "on-device model too slow here: Rules plan" }
        if DirectorLLM.modelPath == nil { return "on-device model not installed: Rules plan" }
        if !DirectorLLM.open() { return DirectorLLM.failed + ": Rules plan" }
        if DirectorLLM.busy { return "on-device model thinking (paused or idle only)" }
        if !DirectorLLM.failed.isEmpty { return "on-device model: \(DirectorLLM.failed); Rules plan" }
        return DirectorLLM.loaded ? "on-device model loaded" + (DirectorLLM.lastSeconds > 0 ? " (last plan \(Int(DirectorLLM.lastSeconds)) s)" : "") : "on-device model ready (loads when needed)"
    }
    func plan(_ s: DirectorSummary, wanted: Int) -> [DirectorRequest]? {
        DirectorLLM.plan(s, wanted: wanted, cancelled: { DirectorPlanner.shared.cancelled })
    }
}

// MARK: Cloud (e)

final class DirectorCloudBackend: DirectorBackend {
    let name = "Cloud"
    var endpoint: String { UserDefaults.standard.string(forKey: "directorCloud").flatMap { $0.isEmpty ? nil : $0 } ?? "mock" }
    var ready: Bool { endpoint == "mock" || DirectorCloudBackend.https }
    #if os(macOS) || (canImport(FoundationNetworking) && !os(Android))
    static let https = true
    #else
    static let https = false
    #endif
    var lastError = ""
    func status() -> String {
        if endpoint == "mock" { return "cloud: the built-in mock server answers (no network used)" }
        if !DirectorCloudBackend.https { return "cloud: HTTPS is not in this build: Rules plan" }
        return lastError.isEmpty ? "cloud: \(endpoint)" : "cloud: \(lastError); Rules plan"
    }
    // The request: the summary and the catalogue only, never account or device data.
    func body(_ s: DirectorSummary, wanted: Int) -> Data? {
        #if QUEST && !PLAYTEST
        return nil                      // P396: nothing to send in the store build
        #else
        let o: [String: Any] = ["format": "blocksmith-director-1", "wanted": wanted, "system": DirectorPrompt.system,
                                "prompt": DirectorPrompt.user(s, wanted: wanted)]
        return try? JSONSerialization.data(withJSONObject: o)
        #endif
    }
    func plan(_ s: DirectorSummary, wanted: Int) -> [DirectorRequest]? {
        #if QUEST && !PLAYTEST
        return nil                      // P396: the store build sends nothing off the headset (no cloud planner)
        #else
        if endpoint == "mock" { return DirectorPrompt.parse(DirectorCloudBackend.mockReply(s, wanted: wanted), source: "cloud (mock)") }
        guard let url = URL(string: endpoint), url.scheme == "https", let data = body(s, wanted: wanted) else { lastError = "the endpoint must be https"; return nil }
        #if os(macOS) || (canImport(FoundationNetworking) && !os(Android))
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        final class Box { var reply: String?; var error = "" }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { d, resp, err in
            if let d, (resp as? HTTPURLResponse)?.statusCode == 200 { box.reply = String(data: d, encoding: .utf8) }
            else { box.error = err == nil ? "the server refused" : "no answer" }
            done.signal()
        }.resume()
        if done.wait(timeout: .now() + 25) == .timedOut { lastError = "no answer"; return nil }
        guard let r = box.reply else { lastError = box.error.isEmpty ? "no answer" : box.error; return nil }
        lastError = ""
        return DirectorPrompt.parse(r, source: "cloud")
        #else
        lastError = "HTTPS is not in this build"
        return nil
        #endif
        #endif
    }
    // What a server answers (the mock): the rule director's plan written out as the reply JSON.
    static func mockReply(_ s: DirectorSummary, wanted: Int) -> String {
        let plan = DirectorRulesBackend().plan(s, wanted: wanted) ?? []
        let events: [[String: Any]] = plan.map { ["t": $0.t, "n": $0.n, "s": $0.s] }
        guard let d = try? JSONSerialization.data(withJSONObject: ["events": events]), let t = String(data: d, encoding: .utf8) else { return "{}" }
        return t
    }
}

// MARK: The planner (keeps the Director's queue filled)

final class DirectorPlanner {
    static let shared = DirectorPlanner()
    let rules = DirectorRulesBackend()
    let device = DirectorDeviceBackend()
    let cloud = DirectorCloudBackend()
    private let lock = NSLock()
    private var running = false
    private var result: ([DirectorRequest]?, String, Int)?      // (plans, source, generation)
    private var generation = 0
    private var retryAt: Double = 0
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return generation != runningGeneration }
    private var runningGeneration = -1

    func backend(_ i: Int) -> DirectorBackend { i == 1 ? device as DirectorBackend : (i == 2 ? cloud as DirectorBackend : rules as DirectorBackend) }
    func status(_ i: Int) -> String { backend(i).status() }

    // A new world: whatever was being planned is for the old one.
    func reset() { lock.lock(); generation += 1; result = nil; lock.unlock(); retryAt = 0 }

    // Ask for plans (once a second while the queue is short): rules at once, the others on a background thread.
    func ask(_ g: Game, wanted: Int) {
        guard wanted > 0 else { return }
        let which = Director.effectiveBackend                 // Q2c-console-45: a choice that can't work here plans with the rules
        let b = backend(which)
        if which == 0 || !b.ready {
            if which != 0 { Director.fallbackNote = b.status() }
            if Director.state.queue.isEmpty || g.clock >= retryAt { rulesNow(g); retryAt = g.clock + 30 }
            return
        }
        lock.lock()
        if running || result != nil { lock.unlock(); return }
        guard g.clock >= retryAt else { lock.unlock(); return }
        running = true
        runningGeneration = generation
        let gen = generation
        lock.unlock()
        let summary = DirectorSummary.of(g)
        let source = which == 1 ? "on-device model" : "cloud"
        if which == 1 { DirectorLLM.busy = true }
        let t = Thread { [weak self] in
            let plans = b.plan(summary, wanted: wanted)
            guard let self else { return }
            self.lock.lock()
            self.result = (plans, source, gen)
            self.running = false
            self.lock.unlock()
            DirectorLLM.busy = false
        }
        t.qualityOfService = .background
        t.stackSize = 1 << 20
        t.start()
    }

    // The rule director's plan, here and now (the fallback when one is due and nothing else has answered).
    func rulesNow(_ g: Game) {
        let want = max(1, 2 - Director.state.queue.count)
        Director.enqueue(g, rules.plan(DirectorSummary.of(g), wanted: want) ?? [], source: "rules")
    }

    // Once a second on the main thread: a finished plan goes into the queue (checked by Director.accept).
    func collect(_ g: Game) {
        lock.lock()
        guard let r = result else { lock.unlock(); return }
        result = nil
        let current = r.2 == generation
        lock.unlock()
        guard current else { return }
        if let plans = r.0, !plans.isEmpty {
            let before = Director.state.queue.count
            Director.enqueue(g, plans, source: r.1)
            Director.fallbackNote = Director.state.queue.count > before ? "planned by the \(r.1)" : "the \(r.1)'s plan did not fit: Rules plan"
            if Director.state.queue.count == before { retryAt = g.clock + 60 }
        } else {
            Director.fallbackNote = "the \(r.1) could not plan: Rules plan"
            retryAt = g.clock + 120
        }
    }
}
