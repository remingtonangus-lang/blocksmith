import Foundation
import simd

// D20 strangers: side stories with recurring characters. Three travellers turn up in towns, one at a time and at most
// once a day, each with a story told over three chapters. Talk to one to hear the chapter and take it on (it goes in
// the Journal under Orders); come back to any town when it's done and they'll find you there.
//   Ezra Quill, travelling photographer    plates for his camera; a picture of a far ridge; the cougar that stalks him
//   Abigail Hale, widow                    flowers for a grave; the gang that shot her husband; his pocket clock back
//   Doc Silas Pettibone, tonic peddler     snake skins; honey for the tonic; the rattlers under his wagon
// Saved in TownLaw.Saved (strangers: story -> chapter * 10 + 1 while taken; strangerCount; strangerAt; strangerDay).
enum Strangers {
    enum Goal { case bring(String, Int), visit, kill(String, Int) }
    struct Chapter { let ask: String; let done: String; let goal: Goal; let pay: Int; let reward: (String, Int)? }
    struct Story { let key: String; let name: String; let chapters: [Chapter] }

    static let stories: [Story] = [
        Story(key: "quill", name: "Ezra Quill", chapters: [
            Chapter(ask: "Name's Quill. I make pictures. My plates cracked on the trail: four panes of glass and two sheets of paper would see me right.",
                    done: "Bless you. Hold still... there. Your likeness, for the wall.", goal: .bring("glass", 4), pay: 4000, reward: ("paper", 2)),
            Chapter(ask: "There's a ridge out yonder catches the sunset like nothing else. Ride out and see it for me; mark the way and I'll follow.",
                    done: "You found it! I'll have my best picture yet.", goal: .visit, pay: 6000, reward: nil),
            Chapter(ask: "A cougar's been following my wagon three nights running. Two of them, maybe. I'd sleep easier if they were gone.",
                    done: "No more yellow eyes in the dark. Take my spyglass: you've a better eye than me.", goal: .kill("cougar", 2), pay: 12000, reward: ("spyglass", 1)),
        ]),
        Story(key: "hale", name: "Abigail Hale", chapters: [
            Chapter(ask: "My husband lies out past the creek with no flowers on him. Three poppies, if you'd be so kind.",
                    done: "He'd have liked that. Thank you, truly.", goal: .bring("poppy", 3), pay: 2000, reward: nil),
            Chapter(ask: "The men who shot him ride with a bandit gang. Five of them. I won't ask how. I'll only ask that it's done.",
                    done: "Then it's over. I can sleep.", goal: .kill("bandit", 5), pay: 15000, reward: nil),
            Chapter(ask: "They took his pocket clock. Any clock would do now, if you came by one: something to keep his time.",
                    done: "It ticks just like his did. You've been a friend to me.", goal: .bring("clock", 1), pay: 20000, reward: ("golden_apple", 1)),
        ]),
        Story(key: "pettibone", name: "Doc Silas Pettibone", chapters: [
            Chapter(ask: "Pettibone's Restorative Tonic! Cures what ails you. Needs snake skin, mind: four strips of it. String'll do in a pinch.",
                    done: "Splendid! The secret ingredient, secured.", goal: .bring("string", 4), pay: 3000, reward: nil),
            Chapter(ask: "The tonic wants sweetening. Two bottles of honey and folk will swear by it.",
                    done: "Sweet as a summer morning. Have a bottle on the house.", goal: .bring("honey_bottle", 2), pay: 5000, reward: ("potion_healing", 1)),
            Chapter(ask: "Rattlers nesting under my wagon. Three of them, and they bite. You look like a person who doesn't.",
                    done: "Ha! The wagon's yours to sleep under any time. Here: the real tonic.", goal: .kill("rattlesnake", 3), pay: 10000, reward: ("potion_regeneration", 1)),
        ]),
    ]
    static let role = "stranger"
    static var appearances = 0, chaptersDone = 0      // (tests)

    static func isStranger(_ m: Mob) -> Bool { m.kind == .villager && m.villager?.role == role }
    static func code(_ key: String) -> Int { TownLaw.state.strangers?[key] ?? 0 }
    static func setCode(_ key: String, _ v: Int) { var s = TownLaw.state.strangers ?? [:]; s[key] = v; TownLaw.state.strangers = s }
    static func chapter(_ key: String) -> Int { code(key) / 10 }
    static func taken(_ key: String) -> Bool { code(key) % 10 == 1 }
    static func count(_ key: String) -> Int { TownLaw.state.strangerCount?[key] ?? 0 }
    static func setCount(_ key: String, _ v: Int) { var s = TownLaw.state.strangerCount ?? [:]; s[key] = v; TownLaw.state.strangerCount = s }

    // Once a second (TownLaw.tick): a stranger walks up in town, once a day; one far behind is gone.
    static func tick(_ g: Game) {
        g.mobs.mobs.removeAll { isStranger($0) && simd_length($0.pos - g.player.pos) > 72 }
        // Visits: a far ridge reached.
        for s in stories where taken(s.key) && chapter(s.key) < 3 {
            if case .visit = s.chapters[chapter(s.key)].goal, let t = TownLaw.state.strangerAt?[s.key], t.count == 2,
               count(s.key) == 0, simd_length(V2(Float(t[0]) - g.player.pos.x, Float(t[1]) - g.player.pos.z)) < 14 {
                setCount(s.key, 1)
                g.onToast?("The ridge Quill wanted. Find him in a town")
            }
        }
        guard g.dim.dim == .overworld, TownLaw.inTown != nil, g.alive,
              !g.mobs.mobs.contains(where: isStranger) else { return }
        let day = Int(g.time / DAY_LENGTH)
        guard day > (TownLaw.state.strangerDay ?? -1) else { return }
        // Who: someone with a chapter done to hand in, else the next story in order with chapters left.
        let ready = stories.first { taken($0.key) && chapter($0.key) < 3 && complete(g, $0) }
        let next = stories.first { !taken($0.key) && chapter($0.key) < 3 }
        guard let s = ready ?? next else { return }
        let a = Rand.float(in: 0..<(2 * .pi))
        let at = g.world.freeSpawn(g.player.pos + V3(cosf(a) * 7, 0, sinf(a) * 7))
        let m = Mob(.villager, at: at)
        Townsfolk.setup(m, game: g)
        if var v = m.villager { v.role = role; v.profession = "none"; v.locked = true; v.person = s.name; m.villager = v }
        m.customName = s.name
        m.persistent = false
        m.home = at
        g.mobs.mobs.append(m)
        TownLaw.state.strangerDay = day
        appearances += 1
        g.onToast?("A stranger in town: \(s.name)")
    }

    static func story(_ m: Mob) -> Story? { stories.first { $0.name == m.customName } }

    static func complete(_ g: Game, _ s: Story) -> Bool {
        let ch = s.chapters[chapter(s.key)]
        switch ch.goal {
        case .bring(let k, let n): return Items.has(k) && g.inventory.main.countOf(Items.id(k)) >= n
        case .visit: return count(s.key) >= 1
        case .kill(_, let n): return count(s.key) >= n
        }
    }

    // talkToTownsperson: a stranger.
    static func talk(_ g: Game, _ m: Mob) -> Bool {
        guard isStranger(m), let s = story(m) else { return false }
        let c = chapter(s.key)
        guard c < 3 else { Townsfolk.say(g, m, "Good to see you again, friend."); return true }
        let ch = s.chapters[c]
        m.face(g.player.pos)
        if !taken(s.key) {
            setCode(s.key, c * 10 + 1)
            setCount(s.key, 0)
            if case .visit = ch.goal {
                let a = Rand.float(in: 0..<(2 * .pi)), r = Rand.float(in: 220...380)
                var at = TownLaw.state.strangerAt ?? [:]
                at[s.key] = [Int(g.player.pos.x + cosf(a) * r), Int(g.player.pos.z + sinf(a) * r)]
                TownLaw.state.strangerAt = at
                if let t = at[s.key] { MapCache.shared.discover(g, kind: "legend", x: t[0], z: t[1], name: "Quill's ridge") }
            }
            Townsfolk.say(g, m, ch.ask)
            g.logDocument("\(s.name): chapter \(c + 1)", [ch.ask + "\n\nPays \(Money.format(ch.pay))."], cat: .orders, id: "stranger:\(s.key):\(c)")
            return true
        }
        guard complete(g, s) else { Townsfolk.say(g, m, "Still waiting on you, friend. " + ch.ask); return true }
        if case .bring(let k, let n) = ch.goal { _ = g.inventory.main.remove(Items.id(k), n) }
        g.money += ch.pay
        if let (k, n) = ch.reward, Items.has(k) {
            let rest = g.inventory.add(ItemStack(Items.id(k), n))
            if !rest.isEmpty { g.dropItem(rest) }
        }
        Honour.earn(g, 3, source: "job", "helping \(s.name)")
        setCode(s.key, (c + 1) * 10)
        setCount(s.key, 0)
        chaptersDone += 1
        Townsfolk.say(g, m, ch.done)
        g.onToast?("\(s.name): chapter \(c + 1) of 3 done. \(Money.format(ch.pay))")
        g.sfx(.villagerYes, 0.6)
        return true
    }

    // TownBoard.mobDied: kills for a stranger.
    static func mobDied(_ g: Game, _ m: Mob) {
        for s in stories where taken(s.key) && chapter(s.key) < 3 {
            guard case .kill(let what, _) = s.chapters[chapter(s.key)].goal else { continue }
            let hit = what == "bandit" ? (m.posse == 1 || m.posse == 2 || m.posse == Contracts.banditPosse) : m.kind.key == what
            if hit { setCount(s.key, count(s.key) + 1) }
        }
    }
}
