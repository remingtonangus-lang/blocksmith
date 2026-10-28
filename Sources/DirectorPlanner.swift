import Foundation
import simd

// P266 (a, c): who plans the Director's events: the rule director, hand-tuned rules over a compact world summary.
// P479 (Remington, Oct 27 21:12: "Get rid of the language model stuff"): the on-device model (llama.cpp with a Qwen
// download) and the cloud planner are gone; the rules were always there and plan every event. Every plan still goes
// through Director.accept (clamps, lists, the text filter).
protocol DirectorBackend: AnyObject {
    var name: String { get }
    var ready: Bool { get }
    func status() -> String
    // At once; nil when it could not.
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

// MARK: The planner (keeps the Director's queue filled)

final class DirectorPlanner {
    static let shared = DirectorPlanner()
    let rules = DirectorRulesBackend()
    private var retryAt: Double = 0

    func status() -> String { rules.status() }

    // A new world: whatever was being planned is for the old one.
    func reset() { retryAt = 0 }

    // Ask for plans (once a second while the queue is short).
    func ask(_ g: Game, wanted: Int) {
        guard wanted > 0 else { return }
        if Director.state.queue.isEmpty || g.clock >= retryAt { rulesNow(g); retryAt = g.clock + 30 }
    }

    // The rule director's plan, here and now.
    func rulesNow(_ g: Game) {
        let want = max(1, 2 - Director.state.queue.count)
        Director.enqueue(g, rules.plan(DirectorSummary.of(g), wanted: want) ?? [], source: "rules")
    }
}
