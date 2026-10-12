import Foundation
import simd

// On-device AI villagers, the placeholder (backlog C4; docs/status/villager-mind.md).
//
// A VillagerMind decides what a townsperson says, what they think of you and how they spend their day. The game asks
// the current mind (`VillagerMinds.current`) at three points:
//   greeting   Game.townGreet's last word, when no conquest, anger, honour or voiced line has spoken first.
//   opinion    what a villager thinks of the player (reputation, honour, gossip, who holds the town).
//   choice     the day's activity (Mob.activity: work, the midday meal, the meeting at the bell, the saloon, play).
// ScriptedMind is today's behaviour, unchanged: the written greeting tables, the schedule and the reputation scale.
// ModelMind is the stub a small language model will drive: it builds a short prompt from a VillagerContext, hands it
// to a MindBackend (Apple Foundation Models on the Mac, the Quest's NPU later) off the frame thread, keeps the cleaned
// answer per villager and uses it the next time that villager speaks or plans. With no backend, or before an answer
// arrives, or when an answer is unusable, every call falls back to ScriptedMind. No backend ships yet: `probe()`
// returns nil on every platform, so the game runs the scripted mind.
// The law (sheriffs, deputies), shopkeepers and bankers keep the scripted schedule whatever the mind: shop hours,
// patrols and the bank's counter are game rules, not choices.

struct VillagerContext {
    var name: String                 // "Clara Whitlock"
    var role: String                 // farmer, shopkeeper, deputy, sheriff, elder, child, citizen...
    var profession: String
    var town: String?
    var dayFraction: Double          // 0 sunrise, 0.25 noon, 0.5 sunset
    var reputation: Int              // the villager's own -100...100
    var honour: Float                // the player's honour
    var playerName: String
    var yours: Bool                  // the player holds this town (TownConquest)
    var raid: Bool
    var hostile: Bool
    var child: Bool
    var look: Int                    // appearance seed (also seeds the scripted picks)

    // The prompt a model sees: who they are, where, when, and how they feel about the player. Short (small models,
    // on-device latency), no game rules, and asking for one spoken line.
    func prompt(_ task: VillagerMinds.Task) -> String {
        let when = dayFraction < 0.12 ? "early morning" : dayFraction < 0.4 ? "the middle of the day" : dayFraction < 0.5 ? "evening" : "night"
        var s = "You are \(name), a \(role) in the frontier town of \(town ?? "a small settlement"). It is \(when). "
        s += "\(playerName) is \(VillagerMinds.Opinion.of(reputation: reputation, honour: honour, yours: yours).words) to you"
        s += yours ? ", and holds this town now. " : ". "
        if raid { s += "Raiders are attacking the town. " }
        switch task {
        case .greeting: s += "Say one short line (under 12 words) greeting \(playerName). Plain words, no quotes."
        case .plan: s += "Answer with one word for what you do next: work, eat, meet, social or idle."
        }
        return s
    }
}

protocol MindBackend: AnyObject {
    var label: String { get }
    // Off the frame thread; `done` may come on any thread (ModelMind hops back to the main queue).
    func complete(_ prompt: String, maxTokens: Int, done: @escaping (String?) -> Void)
}

protocol VillagerMind: AnyObject {
    var label: String { get }
    func greeting(_ m: Mob, _ c: VillagerContext, _ g: Game) -> String
    func opinion(_ c: VillagerContext) -> VillagerMinds.Opinion
    func choice(_ m: Mob, _ f: Double) -> Mob.Activity
}

enum VillagerMinds {
    enum Task { case greeting, plan }
    enum Opinion: Int, Comparable {
        case hates = -2, wary, neutral, likes, admires
        static func < (a: Opinion, b: Opinion) -> Bool { a.rawValue < b.rawValue }
        var words: String { ["hated", "not trusted", "a stranger", "liked", "admired"][rawValue + 2] }
        static func of(reputation r: Int, honour h: Float, yours: Bool) -> Opinion {
            let score = Float(r) + h * 0.3 + (yours ? 10 : 0)
            return score <= -60 ? .hates : score <= -15 ? .wary : score < 25 ? .neutral : score < 60 ? .likes : .admires
        }
    }

    static var current: VillagerMind = ScriptedMind.shared
    // The platform's model, when there is one (none yet: see the file comment).
    static func probe() -> MindBackend? { nil }
    // At start-up (and `--mind model` in tests): a model mind over the probed backend, else the scripted mind.
    static func select(model: Bool, game: Game? = nil) {
        ModelMind.game = game
        if model { current = ModelMind(backend: probe()) } else { current = ScriptedMind.shared }
    }

    static func context(_ m: Mob, _ g: Game) -> VillagerContext {
        let v = m.villager ?? VillagerData()
        return VillagerContext(name: v.person ?? "a townsperson", role: m.baby ? "child" : (v.role ?? "townsperson"), profession: v.profession,
                               town: v.town, dayFraction: g.dayFraction, reputation: v.reputation, honour: Honour.value,
                               playerName: TownBoard.playerName, yours: TownConquest.owns(v.town), raid: g.raid != nil,
                               hostile: TownLaw.isHostile(g, m), child: m.baby, look: v.look ?? 0)
    }
    static func keepsSchedule(_ m: Mob) -> Bool {
        let v = m.villager
        return v?.shopKind != nil || v?.role == "deputy" || v?.role == "sheriff" || v?.role == "banker"
    }
}

// Today's behaviour.
final class ScriptedMind: VillagerMind {
    static let shared = ScriptedMind()
    let label = "scripted"
    func greeting(_ m: Mob, _ c: VillagerContext, _ g: Game) -> String { Townsfolk.greeting(m.villager ?? VillagerData(), g) }
    func opinion(_ c: VillagerContext) -> VillagerMinds.Opinion { .of(reputation: c.reputation, honour: c.honour, yours: c.yours) }
    func choice(_ m: Mob, _ f: Double) -> Mob.Activity { m.scriptedActivity(f) }
}

// The stub a model will drive.
final class ModelMind: VillagerMind {
    let backend: MindBackend?
    let fallback = ScriptedMind.shared
    var label: String { backend.map { "model (\($0.label))" } ?? "model (no backend: scripted)" }
    // Answers per villager (appearance seed), used once each; requests in flight.
    private(set) var lines: [Int: String] = [:]
    private(set) var plans: [Int: (Mob.Activity, Double)] = [:]
    private var asking = Set<Int>()
    var asked = 0, used = 0, refused = 0                 // (tests)

    init(backend: MindBackend?) { self.backend = backend }

    func greeting(_ m: Mob, _ c: VillagerContext, _ g: Game) -> String {
        let key = c.look * 2
        if let s = lines.removeValue(forKey: key) { used += 1; ask(key, c, .greeting); return s }
        ask(key, c, .greeting)
        return fallback.greeting(m, c, g)
    }
    func opinion(_ c: VillagerContext) -> VillagerMinds.Opinion { fallback.opinion(c) }     // a game rule for now: prices and gossip read it
    func choice(_ m: Mob, _ f: Double) -> Mob.Activity {
        let scripted = fallback.choice(m, f)
        guard backend != nil, !m.baby, !VillagerMinds.keepsSchedule(m), let look = m.villager?.look else { return scripted }
        // A plan holds for an hour of game time (1000 ticks), then is asked again.
        if let (a, at) = plans[look * 2 + 1], abs(f - at) < 1.0 / 24 { return a }
        if let g = ModelMind.game { var c = VillagerMinds.context(m, g); c.dayFraction = f; ask(look * 2 + 1, c, .plan) }
        return scripted
    }
    static weak var game: Game?

    private func ask(_ key: Int, _ c: VillagerContext, _ task: VillagerMinds.Task) {
        guard let b = backend, !asking.contains(key), asking.count < 4 else { return }
        asking.insert(key)
        asked += 1
        let f = c.dayFraction
        b.complete(c.prompt(task), maxTokens: task == .greeting ? 32 : 4) { [weak self] text in
            let apply = {
                guard let self else { return }
                self.asking.remove(key)
                switch task {
                case .greeting:
                    if let s = ModelMind.clean(text) { self.lines[key] = s } else { self.refused += 1 }
                case .plan:
                    if let a = ModelMind.activity(text) { self.plans[key] = (a, f) } else { self.refused += 1 }
                }
            }
            if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
        }
    }

    // One spoken line: first line only, quotes and markup off, 2-90 characters, letters in it, nothing the HUD font
    // can't show; else nil (the scripted line is used).
    static func clean(_ text: String?) -> String? {
        guard var s = text?.split(whereSeparator: \.isNewline).first.map(String.init) else { return nil }
        s = s.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'`*_#"))
        s = String(s.unicodeScalars.filter { $0.value >= 32 && $0.value < 127 })
        guard s.count >= 2, s.count <= 90, s.contains(where: \.isLetter) else { return nil }
        return s
    }
    static func activity(_ text: String?) -> Mob.Activity? {
        let w = (text ?? "").lowercased()
        for (k, a) in [("work", Mob.Activity.work), ("eat", .eat), ("meet", .meet), ("social", .social), ("idle", .idle)] where w.contains(k) { return a }
        return nil
    }
}
