import Foundation
import simd

// The villager mind placeholder (backlog C4), `questcheck --mind-only`:
//   scripted   the default mind is the scripted one; its greeting, opinion and schedule are today's
//   fallback   a model mind with no backend says and does exactly what the scripted mind does
//   model      a model mind over a fake backend: the prompt carries the villager's name, role, town and feelings;
//              the next greeting is the backend's line (cleaned); the plan it answers is followed for that hour, but
//              never by a deputy or a shopkeeper; unusable answers fall back to the scripted line
enum VillagerMindTests {
    final class Fake: MindBackend {
        let label = "fake"
        var prompts: [String] = []
        var answer: (String) -> String? = { _ in nil }
        func complete(_ prompt: String, maxTokens: Int, done: @escaping (String?) -> Void) { prompts.append(prompt); done(answer(prompt)) }
    }

    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let before = VillagerMinds.current
        defer { VillagerMinds.current = before; ModelMind.game = nil }
        func villager(_ role: String, look: Int, town: String = "Cedar Ford") -> Mob {
            let m = Mob(.villager, at: g.player.pos + V3(2, 0, 0))
            var v = VillagerData()
            v.person = "Clara Whitlock"; v.role = role; v.town = town; v.look = look; v.profession = role == "farmer" ? "farmer" : "none"
            m.villager = v
            return m
        }
        let farmer = villager("farmer", look: 4242)
        let deputy = villager("deputy", look: 77)

        // Scripted.
        VillagerMinds.select(model: false)
        let sc = VillagerMinds.current
        let c = VillagerMinds.context(farmer, g)
        let fracs = [0.05, 0.24, 0.3, 0.4, 0.48, 0.6]
        let same = sc.greeting(farmer, c, g) == Townsfolk.greeting(farmer.villager!, g) && fracs.allSatisfy { sc.choice(farmer, $0) == farmer.scriptedActivity($0) }
            && fracs.allSatisfy { farmer.activity($0) == farmer.scriptedActivity($0) }
        var ops: [VillagerMinds.Opinion] = []
        for r in [-90, -30, 0, 40, 90] { var k = c; k.reputation = r; k.honour = 0; ops.append(sc.opinion(k)) }
        check(sc.label == "scripted" && same && ops == ops.sorted() && ops.first == .hates && ops.last == .admires,
              "C4 scripted: the default mind is \(sc.label); greeting and schedule are today's; opinions \(ops.map { $0.words })")

        // Fallback: no backend.
        VillagerMinds.select(model: true)
        let none = VillagerMinds.current
        let fb = none.greeting(farmer, c, g) == Townsfolk.greeting(farmer.villager!, g) && fracs.allSatisfy { none.choice(farmer, $0) == farmer.scriptedActivity($0) }
        check(VillagerMinds.probe() == nil && fb && none.label.contains("scripted"),
              "C4 fallback: no backend on this platform (\(none.label)); every line and plan is the scripted one")

        // A fake backend.
        let fake = Fake()
        fake.answer = { p in p.contains("one word") ? "Social." : "\"Howdy, partner. Fields need rain.\"\nAnd more text" }
        let mind = ModelMind(backend: fake)
        VillagerMinds.current = mind
        ModelMind.game = g
        let first = mind.greeting(farmer, c, g)
        let second = mind.greeting(farmer, c, g)
        let prompt = fake.prompts.first ?? ""
        let carries = prompt.contains("Clara Whitlock") && prompt.contains("farmer") && prompt.contains("Cedar Ford") && prompt.contains(TownBoard.playerName)
        check(first == Townsfolk.greeting(farmer.villager!, g) && second == "Howdy, partner. Fields need rain." && carries && mind.used == 1,
              "C4 model: first greeting scripted while the backend answers, then \"\(second)\"; prompt carries name, role, town and player (\(prompt.count) chars)")
        let f = 0.3                                      // working hours: the scripted plan is work
        _ = farmer.activity(f)
        let planned = farmer.activity(f + 0.01)
        _ = deputy.activity(f)
        let dep = deputy.activity(f + 0.01)
        check(farmer.scriptedActivity(f) == .work && planned == .social && dep == deputy.scriptedActivity(f + 0.01),
              "C4 plans: the farmer's model plan (\(planned)) replaces the scripted \(farmer.scriptedActivity(f)) for the hour; the deputy keeps patrolling (\(dep))")
        fake.answer = { _ in "  \n" }
        let bad = ModelMind(backend: fake)
        VillagerMinds.current = bad
        _ = bad.greeting(farmer, c, g)
        let after = bad.greeting(farmer, c, g)
        check(after == Townsfolk.greeting(farmer.villager!, g) && bad.refused >= 1 && ModelMind.clean(String(repeating: "a", count: 200)) == nil
              && ModelMind.clean("Héllo there") == "Hllo there",
              "C4 guard: an empty answer is refused (\(bad.refused)) and the scripted line used; long lines and odd characters are cleaned or refused")
    }
}
