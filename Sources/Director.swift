import Foundation
import simd

// P266 (Remington, Oct 14 19:00): THE DIRECTOR. After the story is beaten (the Ash Chancellor down and the Reckoning
// over: Director.storyBeaten), something keeps shaping the land: one meaningful event every 15-30 minutes of play
// (Options > Director > Event Frequency), arriving in the world as a radio call, a messenger, a map marker or a sound,
// never as a menu. Each is one of the templates below, built only from systems the game already has (town raids,
// outlaw gangs, faction dropships, wrecks, storms, eruptions, legendary beasts, traders...).
//   who plans  a DirectorBackend (DirectorLLM.swift): the rule director (always there, the fallback), a small language
//              model on the device (llama.cpp, loaded after the story, run only while the game is paused, asleep,
//              loading or idle somewhere safe), or a cloud endpoint (off by default; a built-in mock server). A backend
//              gets a compact world summary (DirectorSummary) and the catalogue, and answers with event requests as
//              strict JSON: a template id, numbers, picks from fixed lists and short in-world text.
//   trust      nothing a backend says runs as code. `accept` drops unknown templates, clamps every number to its range
//              (and the player's tier), keeps only listed picks, and cleans every name and line (DirectorText: length
//              caps, printable text, the coined-name filter); what fails is replaced by the rule director's choice.
//   pacing     play time (survival, alive, not paused) counts toward the next event; it escalates with his strength
//              (tiers 1-4), never repeats a template of the last three events or a name used before, waits for
//              night or day, a fitting dimension, a town or volcano nearby, and a safe moment (not dead, flying,
//              piloting or in creative), and at most two events run at once. Each has a time limit and always ends
//              (won, failed or expired) with a closing radio line.
//   the player a radio crackle and a subtitled call open each event (kept in the journal's Events shelf, which lists
//              active and finished events with their outcomes), a map marker the HUD can track, rewards in dollars,
//              honour, standing and loot with a sting, consequences named when it goes badly.
// Saved with the world extras ("director"): the queue, the active events and the history.
struct DirectorParam {
    let key: String
    let lo: Double
    let hi: Double
    let note: String
}

struct DirectorTemplate {
    let id: String
    let title: String          // the rule director's name for it
    let blurb: String          // what it is (the model reads this; so does the journal)
    let dims: [Dim]
    let when: Int              // 0 any time, 1 begins at night, 2 by day
    let minTier: Int
    let limit: Double          // minutes of play before it ends unwon
    let nums: [DirectorParam]
    let picks: [String: [String]]
    let needs: String          // "", "town", "volcano", "place" (his home or a base he took)

    func param(_ k: String) -> DirectorParam? { nums.first { $0.key == k } }
}

// What a backend asks for (before `accept`).
struct DirectorRequest {
    var t: String
    var n: [String: Double] = [:]
    var s: [String: String] = [:]
    var source = "rules"
}

struct DirectorEvent: Codable {
    var id: Int
    var t: String
    var n: [String: Double]
    var s: [String: String]
    var source: String
    var state = 0                       // 0 planned, 1 under way, 2 won, 3 failed, 4 expired
    var x: Int? = nil, z: Int? = nil    // where it is (the map marker), once it has a place
    var y: Int? = nil
    var route: [[Int]]? = nil           // bounty: the gang's waypoints
    var leg = 0
    var place: String? = nil            // the town or place it concerns
    var spawned = false
    var born: Double = 0                // Director.state.play when it began
    var until: Double = 0
    var due: Double = 0                 // counteroffensive: when the strike comes
    var names: [String] = []            // the people and creatures it put in the world
    var chest: [Int]? = nil             // wreck, supply drop: the container (x, y, z)
    var stock = 0                       // what that container held at first
    var fired = false                   // a one-off step has happened (the raid started, the fallout fell...)
    var faction = 0
    var outcome: String? = nil
    var day = 0

    var name: String { s["name"] ?? Director.template(t)?.title ?? "Event" }
    var open: Bool { state == 1 }
    func num(_ k: String) -> Double { n[k] ?? 0 }
    func int(_ k: String) -> Int { Int(num(k).rounded()) }
    var at: V2? { (x != nil && z != nil) ? V2(Float(x!) + 0.5, Float(z!) + 0.5) : nil }
}

struct DirectorState: Codable {
    var play: Double = 0                // seconds of play since the Director woke
    var nextDue: Double = 0
    var queue: [DirectorEvent] = []
    var active: [DirectorEvent] = []
    var history: [String] = []          // "template|name|outcome|day", newest last
    var usedNames: [String] = []
    var nextId = 1
    var woke = false
    var plans = 0                       // plans received, by backend (status)
    var planned: [String: Int] = [:]
}

enum Director {
    static var state = DirectorState()
    static var lastSecond: Double = -1
    static var lastActive: Double = 0             // the last frame of active play (the model's quiet test off the Quest)
    static var idleSince: Double = 0
    static var lastPos = V3(0, 0, 0), lastYaw: Float = 0
    static var refs: [Int: [Mob]] = [:]           // the mobs each event put in the world (this session)
    static var waitNote = ""                      // why the next event is waiting (Options > Director)
    static var fallbackNote = ""                  // why the backend asked fell back to rules
    static let posse = 3                          // gunmen ride on the bounty hunters' soldier rig (no faction)
    static let maxActive = 2

    // MARK: The catalogue (b)

    static let factions = ["capital", "greywall", "meridian", "ironback", "stormwarden"]
    static func faction(_ k: String) -> Faction {
        switch k { case "greywall": return .greywall; case "meridian": return .meridian; case "ironback": return .ironback
                   case "stormwarden": return .stormwarden; default: return .steelhold }
    }
    static func key(_ f: Faction) -> String {
        switch f { case .greywall: return "greywall"; case .meridian: return "meridian"; case .ironback: return "ironback"
                   case .stormwarden: return "stormwarden"; default: return "capital" }
    }
    static var raidResults: [String: Bool] = [:]  // a town's night raid ended: did he stand with it (TownRaids.won)
    static let rareGoods = ["diamond", "emerald", "golden_apple", "ender_pearl", "name_tag", "saddle", "experience_bottle", "blaze_rod",
                            "nautilus_shell", "heart_of_the_sea", "totem_of_undying", "trident", "enchanted_golden_apple", "spyglass", "rifle_rounds",
                            "heavy_rounds", "shotgun_shells"]

    static let catalogue: [DirectorTemplate] = [
        DirectorTemplate(id: "town_raid", title: "Raiders on the Town", blurb: "raiders ride on a town by night; stand with the townsfolk",
                         dims: [.overworld], when: 0, minTier: 1, limit: 60,
                         nums: [DirectorParam(key: "reward", lo: 20, hi: 250, note: "dollars from the town purse"),
                                DirectorParam(key: "honour", lo: 1, hi: 8, note: "honour won")],
                         picks: [:], needs: "town"),
        DirectorTemplate(id: "bounty", title: "A Price on an Outlaw", blurb: "a named outlaw and his gang ride a route; bring him down",
                         dims: [.overworld], when: 0, minTier: 1, limit: 50,
                         nums: [DirectorParam(key: "reward", lo: 40, hi: 500, note: "the bounty in dollars"),
                                DirectorParam(key: "posse", lo: 1, hi: 5, note: "riders with him"),
                                DirectorParam(key: "dist", lo: 200, hi: 700, note: "blocks away the trail starts"),
                                DirectorParam(key: "honour", lo: 1, hi: 6, note: "honour won")],
                         picks: [:], needs: ""),
        DirectorTemplate(id: "counteroffensive", title: "Counter-Offensive", blurb: "a faction strikes back at your home or a base you took",
                         dims: [.overworld], when: 0, minTier: 2, limit: 35,
                         nums: [DirectorParam(key: "lead", lo: 3, hi: 15, note: "minutes of warning"),
                                DirectorParam(key: "reward", lo: 40, hi: 300, note: "salvage in dollars"),
                                DirectorParam(key: "honour", lo: 1, hi: 6, note: "honour won")],
                         picks: ["faction": factions], needs: "place"),
        DirectorTemplate(id: "wreck", title: "A Wreck to Salvage", blurb: "a crashed craft lies out in the wild; salvage it before scavengers do",
                         dims: [.overworld], when: 0, minTier: 1, limit: 45,
                         nums: [DirectorParam(key: "dist", lo: 150, hi: 600, note: "blocks away"),
                                DirectorParam(key: "scavengers", lo: 0, hi: 4, note: "scavengers at the wreck")],
                         picks: ["loot": ["shipwreck_treasure", "shipwreck_supply", "buried_treasure", "camp_traders"]], needs: ""),
        DirectorTemplate(id: "hostage", title: "Hostage Rescue", blurb: "outlaws hold a townsperson at a camp; free them alive",
                         dims: [.overworld], when: 0, minTier: 1, limit: 45,
                         nums: [DirectorParam(key: "dist", lo: 150, hi: 500, note: "blocks from the town"),
                                DirectorParam(key: "guards", lo: 2, hi: 5, note: "outlaws guarding"),
                                DirectorParam(key: "reward", lo: 40, hi: 400, note: "the family's reward in dollars"),
                                DirectorParam(key: "honour", lo: 2, hi: 10, note: "honour won")],
                         picks: [:], needs: "town"),
        DirectorTemplate(id: "storm", title: "The Great Storm", blurb: "a great thunderstorm rolls in; get under a roof",
                         dims: [.overworld], when: 0, minTier: 1, limit: 14,
                         nums: [DirectorParam(key: "minutes", lo: 3, hi: 10, note: "how long it rages")],
                         picks: [:], needs: ""),
        DirectorTemplate(id: "eruption", title: "The Mountain Wakes", blurb: "a nearby volcano erupts; watch from a safe distance for the fallout",
                         dims: [.overworld], when: 0, minTier: 1, limit: 10,
                         nums: [DirectorParam(key: "fallout", lo: 2, hi: 8, note: "volcanic glass and ember stone falling near you")],
                         picks: [:], needs: "volcano"),
        DirectorTemplate(id: "outpost", title: "A New Outpost", blurb: "a faction raises an outpost in the wild; clear it",
                         dims: [.overworld], when: 0, minTier: 2, limit: 60,
                         nums: [DirectorParam(key: "dist", lo: 200, hi: 700, note: "blocks away"),
                                DirectorParam(key: "troops", lo: 3, hi: 7, note: "soldiers"),
                                DirectorParam(key: "reward", lo: 40, hi: 400, note: "dollars from their pay chest")],
                         picks: ["faction": factions], needs: ""),
        DirectorTemplate(id: "trader", title: "A Travelling Trader", blurb: "a peddler with rare goods comes by for a while",
                         dims: [.overworld], when: 2, minTier: 1, limit: 20,
                         nums: [DirectorParam(key: "price", lo: 2, hi: 40, note: "emeralds for the dearest good"),
                                DirectorParam(key: "minutes", lo: 6, hi: 18, note: "how long the trader stays")],
                         picks: ["goods": rareGoods, "goods2": rareGoods], needs: ""),
        DirectorTemplate(id: "rival", title: "A Rival Calls You Out", blurb: "a gunslinger who remembers your deeds comes for a duel",
                         dims: [.overworld], when: 0, minTier: 2, limit: 20,
                         nums: [DirectorParam(key: "grit", lo: 1.5, hi: 4, note: "his toughness, times a soldier's"),
                                DirectorParam(key: "reward", lo: 40, hi: 400, note: "his purse in dollars")],
                         picks: [:], needs: ""),
        DirectorTemplate(id: "incursion", title: "A Rift from Below", blurb: "the Emberdeep breaks through: a rift spills its creatures",
                         dims: [.overworld], when: 0, minTier: 3, limit: 45,
                         nums: [DirectorParam(key: "dist", lo: 80, hi: 300, note: "blocks away"),
                                DirectorParam(key: "count", lo: 3, hi: 10, note: "creatures"),
                                DirectorParam(key: "reward", lo: 40, hi: 300, note: "a bounty from the towns in dollars")],
                         picks: [:], needs: ""),
        DirectorTemplate(id: "warband", title: "A Warband on Your Trail", blurb: "a brand warband hunts you through the Emberdeep",
                         dims: [.nether], when: 0, minTier: 1, limit: 20,
                         nums: [DirectorParam(key: "count", lo: 2, hi: 6, note: "warriors"),
                                DirectorParam(key: "reward", lo: 40, hi: 300, note: "dollars in their packs")],
                         picks: [:], needs: ""),
        DirectorTemplate(id: "dead_rise", title: "The Dead Rise", blurb: "the restless dead climb out by a town after dark",
                         dims: [.overworld], when: 1, minTier: 1, limit: 30,
                         nums: [DirectorParam(key: "count", lo: 4, hi: 12, note: "dead"),
                                DirectorParam(key: "reward", lo: 20, hi: 200, note: "the town's thanks in dollars"),
                                DirectorParam(key: "honour", lo: 1, hi: 6, note: "honour won")],
                         picks: [:], needs: "town"),
        DirectorTemplate(id: "beasts", title: "Prowlers at the Herds", blurb: "predators harry a town's herds; hunt them down",
                         dims: [.overworld], when: 0, minTier: 1, limit: 35,
                         nums: [DirectorParam(key: "count", lo: 2, hi: 6, note: "predators"),
                                DirectorParam(key: "reward", lo: 20, hi: 200, note: "the ranchers' bounty in dollars")],
                         picks: [:], needs: "town"),
        DirectorTemplate(id: "gift", title: "A Messenger with a Gift", blurb: "a town you helped sends a messenger with a gift and a letter",
                         dims: [.overworld], when: 2, minTier: 1, limit: 15,
                         nums: [DirectorParam(key: "reward", lo: 20, hi: 300, note: "dollars in the purse")],
                         picks: ["loot": ["village", "buried_treasure", "camp_traders", "shipwreck_supply"]], needs: "town"),
        DirectorTemplate(id: "supply_drop", title: "A Supply Drop", blurb: "a faction's cargo drop lands off course; take it before its guards do",
                         dims: [.overworld], when: 0, minTier: 1, limit: 40,
                         nums: [DirectorParam(key: "dist", lo: 150, hi: 500, note: "blocks away"),
                                DirectorParam(key: "guards", lo: 0, hi: 5, note: "soldiers sent to recover it")],
                         picks: ["faction": factions], needs: ""),
        DirectorTemplate(id: "legend", title: "A Legend Sighted", blurb: "a legendary beast is seen far from its den",
                         dims: [.overworld], when: 0, minTier: 1, limit: 45,
                         nums: [DirectorParam(key: "dist", lo: 150, hi: 500, note: "blocks away")],
                         picks: ["beast": Hunting.legends.indices.map { "\($0)" }], needs: ""),
    ]
    static func template(_ id: String) -> DirectorTemplate? { catalogue.first { $0.id == id } }
    static let textCaps: [String: Int] = ["name": 28, "caller": 28, "open": 170, "win": 130, "lose": 130]

    // MARK: Switches and status (f, h, n)

    static func storyBeaten(_ g: Game) -> Bool { g.ashVictory && Reckoning.stage != 1 && Reckoning.stage != 2 }
    static func on(_ g: Game) -> Bool {
        let st = Settings.shared
        return st.directorOn && (storyBeaten(g) || st.directorEarly)
    }
    // Minutes of play between events, by frequency (Rare, Normal, Often).
    static func gap() -> ClosedRange<Double> {
        switch Settings.shared.directorFreq { case 0: return 30...45; case 2: return 8...15; default: return 15...30 }
    }
    static let freqNames = ["Rare (30-45 min)", "Normal (15-30 min)", "Often (8-15 min)"]
    static let backendNames = ["Rules", "On-Device Model", "Cloud"]

    // The Director page's status line (n): what it is doing now.
    static func statusLines(_ g: Game) -> [String] {
        let st = Settings.shared
        var out: [String] = []
        if !st.directorOn { out.append("Status: off. No events after the story") }
        else if !storyBeaten(g) && !st.directorEarly { out.append(g.ashVictory ? "Status: waiting for the Reckoning to end" : "Status: waiting for the story's end") }
        else if !g.survival { out.append("Status: paused in creative mode") }
        else {
            let left = max(0, state.nextDue - state.play) / 60
            let act = state.active.filter { $0.open }.count
            var s = act > 0 ? "Status: \(act) event\(act == 1 ? "" : "s") under way" : "Status: watching"
            s += left > 0.5 ? ", next in about \(Int(left.rounded())) min" : (waitNote.isEmpty ? ", next one soon" : ", next waits: " + waitNote)
            out.append(s)
        }
        if g.difficulty == 0 { out[0] += " (Peaceful: only peaceful events)" }         // Q2c-console-23
        out.append("Planner: " + DirectorPlanner.shared.status(st.directorBackend))
        if !fallbackNote.isEmpty && st.directorBackend != 0 { out.append("Last plan: " + fallbackNote) }
        return out
    }

    // The Director page's short rows (the hover help reads statusLines in full).
    static func shortStatus(_ g: Game) -> String {
        let st = Settings.shared
        if !st.directorOn { return "Now: Off" }
        if !storyBeaten(g) && !st.directorEarly { return "Now: Waiting for the story's end" }
        if !g.survival { return "Now: Paused (creative mode)" }
        let act = state.active.filter { $0.open }.count
        if act > 0 { return "Now: \(act) event\(act == 1 ? "" : "s") under way" }
        let left = Int((max(0, state.nextDue - state.play) / 60).rounded())
        return left > 0 ? "Now: Next event in ~\(left) min" : "Now: Next event soon"
    }
    static func shortPlanner() -> String {
        switch Settings.shared.directorBackend {
        case 1:
            if DirectorLLM.slow { return "Model: Too slow here (Rules)" }
            if DirectorLLM.modelPath == nil { return "Model: Not installed (Rules)" }
            if !DirectorLLM.open() { return "Model: Not in this build (Rules)" }
            if DirectorLLM.busy { return "Model: Thinking" }
            return DirectorLLM.loaded ? "Model: Loaded" : "Model: Ready"
        case 2:
            if DirectorPlanner.shared.cloud.endpoint == "mock" { return "Cloud: Mock server" }
            return DirectorCloudBackend.https ? "Cloud: On" : "Cloud: No HTTPS here (Rules)"
        default: return "Planner state: Rules, ready"
        }
    }
    // Event Frequency changed: the wait already running follows the new pace.
    static func rescheduled(from old: Int) {
        let left = state.nextDue - state.play
        guard left > 0 else { return }
        state.nextDue = state.play + min(left, 60 * gap().upperBound)
    }

    // MARK: Ticking (f, k, l)

    // Every frame (HudExtras.tick): the model's heartbeat while he plays, the once-a-second step.
    static func frame(_ g: Game) {
        let playing = !g.paused && g.menu == nil && g.sleeping <= 0 && HudExtras.loading == nil && !idleSafe(g)
        if playing { lastActive = g.clock; DirectorLLM.heartbeat() }
        guard g.clock - lastSecond >= 1 || lastSecond < 0 || g.clock < lastSecond else { return }
        let dt = lastSecond < 0 || g.clock < lastSecond ? 1 : min(5, g.clock - lastSecond)
        lastSecond = g.clock
        second(g, dt)
    }

    // Idle somewhere safe (the model may think then): still for 20 s, no hostile within 32 blocks, at home, in a
    // town or a base he holds.
    static func idleSafe(_ g: Game) -> Bool {
        let p = g.player.pos
        if simd_length(p - lastPos) > 0.05 || abs(g.player.yaw - lastYaw) > 0.02 { lastPos = p; lastYaw = g.player.yaw; idleSince = g.clock; return false }
        guard g.clock - idleSince > 20, g.alive else { return false }
        let home = simd_length(g.spawnPoint - p) < 48 || TownLaw.inTown != nil || g.bases.inAnyBase(p)
        guard home else { return false }
        return !g.mobs.mobs.contains { $0.health > 0 && $0.kind.hostile && simd_length($0.pos - p) < 32 }
    }

    static func second(_ g: Game, _ dt: Double) {
        DirectorPlanner.shared.collect(g)
        guard on(g) else {
            DirectorLLM.idle(g, wanted: false)
            return
        }
        DirectorLLM.idle(g, wanted: Settings.shared.directorBackend == 1)
        // Q2c-console-24: when this world started being played here, and his last death.
        if arrivedAt < 0 || g.clock < arrivedAt { arrivedAt = g.clock }
        if !g.alive { diedAt = g.clock }
        if !state.woke && g.credits == nil && g.menu == nil && !g.paused && g.alive {
            state.woke = true
            state.nextDue = state.play + 60 * Rand.double(in: 4...8)
            radio(g, caller: "A crackle on the radio", "Word of what you did below is spreading. The land is stirring: listen for calls, and watch your map.")
        }
        let playing = g.survival && g.alive && !g.paused && g.menu == nil
        if playing { state.play += dt }
        // Q2c-console-28: the Events shelf refreshed once a minute of play.
        let refresh = state.play - lastFiled >= 60
        if refresh { lastFiled = state.play; for e in state.active where e.open { file(g, e) } }
        // The active events.
        for i in state.active.indices where state.active[i].open {
            var e = state.active[i]
            DirectorEvents.tick(g, &e)
            if e.open && state.play > e.until { DirectorEvents.expire(g, &e) }
            state.active[i] = e
            if !e.open { finished(g, e) }
        }
        state.active.removeAll { !$0.open }
        // Keep two plans ahead (a backend fills the queue; rules at once when it is empty and one is due).
        if state.queue.count < 2 { DirectorPlanner.shared.ask(g, wanted: 2 - state.queue.count) }
        guard g.survival else { waitNote = "creative mode"; return }
        guard state.play >= state.nextDue else { return }
        guard state.active.count < maxActive else { waitNote = "two events already under way"; return }
        if let why = unsafe(g) { waitNote = why; return }
        if state.queue.isEmpty { DirectorPlanner.shared.rulesNow(g) }
        // The first planned event that fits here and now.
        for (qi, q) in state.queue.enumerated() {
            guard let t = template(q.t) else { continue }
            if let why = unfit(g, t) { waitNote = why; continue }
            var e = q
            e.born = state.play
            e.until = state.play + t.limit * 60
            e.day = Int(g.time / DAY_LENGTH) + 1
            if DirectorEvents.start(g, &e) {
                state.queue.remove(at: qi)
                e.state = 1
                state.active.append(e)
                state.nextDue = state.play + 60 * Rand.double(in: gap())
                waitNote = ""
                announce(g, e)
                return
            }
            waitNote = "no place for it here yet"
        }
        // Nothing fits for long: drop the oldest plan so the queue does not stall (a fresh one comes).
        if state.play - state.nextDue > 600, !state.queue.isEmpty { state.queue.removeFirst(); state.nextDue = state.play }
    }

    // A safe moment for a new event (l). Q2c-console-24: not asleep, not under the credits, not just arrived or revived.
    static var arrivedAt: Double = -1, diedAt: Double = -1000
    static var lastFiled: Double = 0
    static func unsafe(_ g: Game) -> String? {
        if !g.alive { return "you are down" }
        if g.sleeping > 0 { return "you are asleep" }
        if g.credits != nil { return "the credits are rolling" }
        if g.clock - arrivedAt < 60 { return "you have just arrived" }
        if g.clock - diedAt < 60 { return "you have just come back" }
        if g.world.ships.pilot != nil { return "you are at the controls of a craft" }
        if g.player.flying { return "you are flying" }
        if g.dim.dim == .overworld {
            let x = Int(floor(g.player.pos.x)), z = Int(floor(g.player.pos.z))
            if g.world.isLoaded(x, z), g.player.pos.y - Float(g.world.topY(x, z)) > 24 { return "you are high in the air" }
        }
        if g.raid != nil || FactionRaids.active != nil { return "a fight is on" }
        return nil
    }

    // Q2c-console-23: what a Peaceful world can get (no monsters, raiders or gunfights).
    static let peaceful: Set<String> = ["trader", "gift", "storm", "eruption", "wreck", "supply_drop", "legend"]
    static let foeKeys = ["posse", "guards", "troops", "count", "scavengers"]

    // Whether a template fits where he is and the hour (l, f).
    static func unfit(_ g: Game, _ t: DirectorTemplate) -> String? {
        if !t.dims.contains(g.dim.dim) { return "not in this land" }
        if g.difficulty == 0 && !peaceful.contains(t.id) { return "not on Peaceful" }      // Q2c-console-23
        let night = TownRaids.night(g.dayFraction)
        if t.when == 1 && !night { return "it comes after dark" }
        if t.when == 2 && night { return "it comes by day" }
        if tier(g) < t.minTier { return "not yet" }
        switch t.needs {
        case "town": if nearTown(g, within: 700) == nil { return "it needs a town nearby" }
        case "volcano": if nearVolcano(g) == nil { return "it needs a volcano nearby" }
        case "place": if !g.raidPlaces().contains(where: { $0.1 == "your home" || $0.1 == "your base" }) { return "it needs a place of yours" }
        default: break
        }
        return nil
    }

    static func nearTown(_ g: Game, within r: Float) -> (String, IVec3)? {
        guard g.dim.dim == .overworld, let sc = g.world.gen.structures else { return nil }
        let px = Int(floor(g.player.pos.x)), pz = Int(floor(g.player.pos.z))
        guard let s = sc.nearest("village", x: px, z: pz, maxRegions: 2), simd_length(V2(Float(s.anchor.x - px), Float(s.anchor.z - pz))) < r else { return nil }
        return (Townsfolk.townName(s.anchor.x, s.anchor.z, seed: g.world.seed), s.anchor)
    }

    static func nearVolcano(_ g: Game) -> Volcano? {
        guard g.dim.dim == .overworld, let wg = g.world.gen as? WorldGen else { return nil }
        let e = g.player.pos
        return wg.terrain.volcanoes(near: e.x, e.z, reach: Game.eruptionReach).min {
            simd_length(V2($0.x - e.x, $0.z - e.z)) < simd_length(V2($1.x - e.x, $1.z - e.z))
        }
    }

    // MARK: Strength (f: escalation)

    static func strength(_ g: Game) -> Int {
        var s = min(40, g.inventory.armorPoints * 2)
        if g.inventory.main.slots.contains(where: { !$0.isEmpty && Guns.index($0.item) != nil }) { s += 20 }
        s += min(15, g.greywallAlarm.taken.count * 5)
        s += min(15, Legendaries.found.count * 3)
        s += min(10, max(0, g.money) / 20000)
        return min(100, s)
    }
    static func tier(_ g: Game) -> Int { 1 + min(3, strength(g) / 26) }

    // MARK: Accepting a plan (a, o)

    // A backend's request as an event, or nil when its template is unknown. Numbers are clamped to the template's
    // ranges (and the tier's share of them), picks kept only from their lists, text cleaned; what fails is the rule
    // director's.
    static func accept(_ g: Game, _ r: DirectorRequest) -> DirectorEvent? {
        guard let t = template(r.t) else { return nil }
        let rules = DirectorRules.fill(g, t)
        let tr = Double(tier(g))
        var n: [String: Double] = [:]
        for p in t.nums {
            // Escalation: the top of each range opens up with his tier (tier 4: all of it).
            let hi = p.lo + (p.hi - p.lo) * min(1, 0.4 + 0.2 * tr)
            let v = r.n[p.key].flatMap { $0.isFinite ? $0 : nil } ?? rules.n[p.key] ?? p.lo
            n[p.key] = max(p.lo, min(hi, v))
        }
        // Q2c-console-23: Peaceful sends nobody to fight; Easy keeps the foes to the bottom of each range.
        if g.difficulty == 0 { for k in ["scavengers", "guards"] where n[k] != nil { n[k] = 0 } }
        if g.difficulty == 1 {
            for p in t.nums where foeKeys.contains(p.key) { n[p.key] = min(n[p.key] ?? p.lo, (p.lo + (p.hi - p.lo) * 0.25).rounded()) }
            if let p = t.param("grit") { n["grit"] = min(n["grit"] ?? p.lo, p.lo + 0.5) }
        }
        var s: [String: String] = [:]
        for (k, list) in t.picks {
            if let v = r.s[k], list.contains(v) { s[k] = v } else { s[k] = rules.s[k] ?? list.first }
        }
        for (k, cap) in textCaps {
            if let v = r.s[k], let c = DirectorText.clean(v, max: cap), k != "name" || !state.usedNames.contains(c) { s[k] = c }
            else { s[k] = rules.s[k] }
        }
        let e = DirectorEvent(id: state.nextId, t: t.id, n: n, s: s, source: r.source)
        state.nextId += 1
        return e
    }

    // Plans from a backend into the queue (no template of the last three events, none planned twice).
    static func enqueue(_ g: Game, _ list: [DirectorRequest], source: String) {
        var added = 0
        for r in list {
            guard state.queue.count < 3, var e = accept(g, r) else { continue }
            if g.difficulty == 0 && !peaceful.contains(e.t) { continue }            // Q2c-console-23: whoever planned it
            let recent = Set(state.history.suffix(3).map { String($0.split(separator: "|").first ?? "") } + state.active.map { $0.t })
            if recent.contains(e.t) || state.queue.contains(where: { $0.t == e.t }) { continue }
            e.source = source
            state.usedNames.append(e.name)
            if state.usedNames.count > 120 { state.usedNames.removeFirst(state.usedNames.count - 120) }
            state.queue.append(e)
            added += 1
        }
        if added > 0 { state.plans += 1; state.planned[source, default: 0] += added }
    }

    // MARK: Feedback (g, j, m)

    // The radio crackle and the subtitled call (the toast; the journal keeps it).
    static func radio(_ g: Game, caller: String, _ text: String) {
        g.sfx(.gun(11), 0.9, at: g.player.eye)
        g.onToast?("\(caller): \"\(text)\"")
    }

    static func fill(_ g: Game, _ e: DirectorEvent, _ text: String) -> String {
        var t = text
        let dir: String
        let dist: String
        if let a = e.at {
            let dx = a.x - g.player.pos.x, dz = a.y - g.player.pos.z
            dir = TownBoard.direction(dx, dz)
            dist = "\(Int((dx * dx + dz * dz).squareRoot() / 10) * 10)"
        } else { dir = "nearby"; dist = "a few" }
        let reward = Money.format(e.int("reward") * 100)
        let f = faction(e.s["faction"] ?? "capital").name
        for (k, v) in [("{town}", e.place ?? "the town"), ("{place}", e.place ?? "your place"), ("{dir}", dir), ("{dist}", dist),
                       ("{reward}", reward), ("{faction}", f), ("{name}", e.name),
                       ("{deed}", e.s["deed"] ?? "made a name out here")] {
            t = t.replacingOccurrences(of: k, with: v)
        }
        return t
    }

    static func announce(_ g: Game, _ e: DirectorEvent) {
        radio(g, caller: e.s["caller"] ?? "Radio", fill(g, e, e.s["open"] ?? e.name))
        if e.at != nil {
            // The marker (j): followed at once when he is not following anything else.
            if Waymarks.trackedKey == nil && Spine.target == nil { Waymarks.trackedKey = "director|\(e.id)"; Waymarks.cache = (-1e9, nil) }
            Waymarks.marksAt = -1e9
        }
        // A bounty's poster (g): filed with the pamphlets, the reward and the outlaw's last known whereabouts.
        if e.t == "bounty" {
            g.logDocument("Wanted: \(e.name)", ["WANTED\n\n\(e.name)\n\nDead or alive. \(Money.format(e.int("reward") * 100)) reward.\n\n"
                + "Last seen with his gang, riding \(fill(g, e, "{dir}, about {dist} blocks from here")). Armed and dangerous."],
                          cat: .pamphlets, id: "director-poster:\(e.id)")
        }
        file(g, e)
    }

    static func finished(_ g: Game, _ e: DirectorEvent) {
        let word = ["", "", "won", "failed", "expired"][max(0, min(4, e.state))]
        state.history.append("\(e.t)|\(e.name)|\(word)|\(e.day)")
        if state.history.count > 60 { state.history.removeFirst(state.history.count - 60) }
        refs[e.id] = nil
        if Waymarks.trackedKey == "director|\(e.id)" { Waymarks.trackedKey = nil; Waymarks.cache = (-1e9, nil) }
        Waymarks.marksAt = -1e9
        file(g, e)
    }

    // The payoff (m): money, honour and items with a sting and a toast naming each.
    static func pay(_ g: Game, _ e: inout DirectorEvent, dollars: Int, honour: Float = 0, items: [ItemStack] = [], line: String? = nil) {
        e.state = 2
        var paid: [String] = []
        if dollars > 0 { g.money += dollars * 100; paid.append(Money.format(dollars * 100)) }
        if honour > 0 { Honour.earn(g, honour, source: "director", e.name); paid.append("honour") }
        for s in items where !s.isEmpty {
            g.drops.spawn(s, at: g.player.pos + V3(0, 1, 0), deliberate: true)
            paid.append("\(s.count) \(s.def.display)")
        }
        e.outcome = "Won" + (paid.isEmpty ? "" : ": " + paid.joined(separator: ", "))
        g.sfx(.levelUp, 0.8)
        radio(g, caller: e.s["caller"] ?? "Radio", fill(g, e, line ?? e.s["win"] ?? "Well done."))
        if !paid.isEmpty { g.onToast?("\(e.name) done: " + paid.joined(separator: ", ")) }
    }

    static func fail(_ g: Game, _ e: inout DirectorEvent, consequence: String, expired: Bool = false) {
        e.state = expired ? 4 : 3
        e.outcome = (expired ? "Expired: " : "Failed: ") + consequence
        g.sfx(.bellResonate, 0.5)
        radio(g, caller: e.s["caller"] ?? "Radio", fill(g, e, e.s["lose"] ?? "Too late."))
        g.onToast?(consequence)
    }

    // MARK: The journal's Events shelf (g)

    static func file(_ g: Game, _ e: DirectorEvent) {
        let word = ["Planned", "Under way", "Won", "Failed", "Expired"][max(0, min(4, e.state))]
        let title = "\(word): \(e.name)"
        // Q2c-console-28: a finished entry leads with its outcome; a running one says how far along it is.
        var body = e.outcome.map { $0 + "\n\n" } ?? ""
        body += "\(template(e.t)?.title ?? "Event") (\(template(e.t)?.blurb ?? "")).\n\n"
        body += "\(e.s["caller"] ?? "Radio"): \"\(fill(g, e, e.s["open"] ?? ""))\"\n\n"
        if let p = e.place { body += "Where: \(p)" + (e.at.map { " (\(Int($0.x)), \(Int($0.y)))" } ?? "") + "\n" }
        else if let a = e.at { body += "Where: \(Int(a.x)), \(Int(a.y)) (on your map)\n" }
        if e.open {
            if let pr = DirectorEvents.progress(g, e) { body += "Now: \(pr)\n" }
            body += "Time left: about \(max(1, Int(((e.until - state.play) / 60).rounded()))) minutes of play\n"
        }
        let (d, h, m) = g.journalStamp
        let id = "director:\(e.id)"
        if let i = g.journal.lastIndex(where: { $0.id == id }) {
            g.journal[i].title = title
            g.journal[i].text = "Event: \(e.name)"
            g.journal[i].pages = [body]                    // (Q2c-console-28: it keeps the day and hour it began)
        } else {
            var j = JournalEntry(day: d, hour: h, minute: m, text: "Event: \(e.name)", title: title, pages: [body])
            j.cat = Journal.Cat.events.key
            j.place = e.place ?? g.journalPlace()
            j.id = id
            g.journal.append(j)
            g.trimJournal()
        }
        Journal.rev += 1
    }

    // MARK: Map markers (j)

    static func targets(_ g: Game) -> [Waymarks.Target] {
        guard g.dim.dim == .overworld else { return [] }
        return state.active.compactMap { e in
            guard e.open, let a = e.at else { return nil }
            return Waymarks.Target(kind: "director", key: "\(e.id)", name: "Event: " + e.name, pos: V3(a.x, g.player.pos.y, a.y))
        }
    }

    // A person or creature an open event put in the world (bounty hunters' clean-up leaves them be).
    static func owns(_ m: Mob) -> Bool {
        guard let n = m.customName else { return false }
        return state.active.contains { $0.open && $0.names.contains(n) }
    }

    // MARK: Saves (i)

    static func encode() -> String {
        guard let d = try? JSONEncoder().encode(state), let s = String(data: d, encoding: .utf8) else { return "" }
        return s
    }
    static func decode(_ s: String?) {
        refs = [:]; lastSecond = -1; waitNote = ""; fallbackNote = ""; arrivedAt = -1; diedAt = -1000
        state = s.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode(DirectorState.self, from: $0) } ?? DirectorState()
        // Creatures that were not saved with the world come back when he is near again.
        for i in state.active.indices where state.active[i].t == "legend" || state.active[i].t == "warband" { state.active[i].spawned = false }
        DirectorPlanner.shared.reset()
    }
}

// MARK: Text a backend wrote (b, o)

enum DirectorText {
    static let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,'!?:;()&$-{}")
    static let placeholders = ["{town}", "{place}", "{dir}", "{dist}", "{reward}", "{faction}", "{name}", "{deed}"]
    static let blocked = ["http", "www.", ".com", "@", "fuck", "shit", "cunt", "nigg", "fag", "rape", "nazi", "hitler", "swastika"]

    // Printable, capped at a word, free of coined names and links; nil when nothing usable is left.
    static func clean(_ raw: String, max cap: Int) -> String? {
        var t = String(raw.map { $0 == "\n" || $0 == "\t" || $0 == "\"" ? " " : $0 }.filter { allowed.contains($0) })
        // Braces only round the known placeholders.
        var kept = ""
        var i = t.startIndex
        while i < t.endIndex {
            if t[i] == "{" {
                if let p = placeholders.first(where: { t[i...].hasPrefix($0) }) { kept += p; i = t.index(i, offsetBy: p.count); continue }
            } else if t[i] != "}" { kept.append(t[i]) }
            i = t.index(after: i)
        }
        t = kept.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        if t.count > cap {
            let cut = String(t.prefix(cap))
            t = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? cut
        }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))
        guard t.filter({ $0.isLetter }).count >= 2 else { return nil }
        let low = t.lowercased()
        if blocked.contains(where: { low.contains($0) }) { return nil }
        if coined(t) { return nil }
        return t
    }

    // tools/coined-terms.txt rules: "*term" anywhere, any case; "Term" case-sensitively at a word start.
    static func coined(_ t: String) -> Bool {
        let low = t.lowercased()
        for term in DirectorTerms.coined {
            if term.hasPrefix("*") {
                if low.contains(term.dropFirst().lowercased()) { return true }
                continue
            }
            var from = t.startIndex
            while let r = t.range(of: term, range: from..<t.endIndex) {
                if r.lowerBound == t.startIndex || !t[t.index(before: r.lowerBound)].isLetter { return true }
                from = r.upperBound
            }
        }
        return false
    }
}
