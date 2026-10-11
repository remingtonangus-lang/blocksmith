import Foundation
import simd

// Taking a town (backlog B1; docs/status/six-iron.md).
//
// The iron rule (SixIron.swift) means a town's law can only be beaten in iron or better. Beat it and the town is yours:
//   surrender: when the sheriff has fallen to you and no deputy of that town is left standing (within 10 minutes of
//              the sheriff), the town gives up: everyone raises their hands, the fighting and the bounty there end.
//   yours:     its keepers always serve you at their best price (ShopPricing, inside the shop bounds), its beds and
//              chests are yours (no theft or trespass counts there), its folk call you boss, a new sheriff sent three
//              days later works for you, and it pays tribute: `tributePerDay` for each day since you last collected
//              (up to `tributeCap` days), handed over when you walk in.
//   honour:    taking a town by force costs `honourCost` on top of the killings.
//   neighbours: for `waryDays` after a taking, other towns within `waryRadius` blocks have heard: their law calls you
//              out on arrival, they start on edge (heat 3: one more crime turns them) and charge 10% more.
// Saved in TownLaw.Saved.owned (town -> [anchor x, anchor z, day taken, day tribute was last paid]).
enum TownConquest {
    enum Standing { case none, owned, wary }
    static let honourCost: Float = 10
    static let tributePerDay = 600              // cents
    static let tributeCap = 7
    static let waryDays = 10
    static let waryRadius: Float = 2000
    static let sheriffWindow: Double = 600

    // Live (not saved).
    static var sheriffFell: [String: Double] = [:]   // town -> when its sheriff fell to the player
    static var warnedVisit: String?                  // the wary town whose law already called you out this visit
    static var greetedVisit: String?                 // the owned town that already paid you this visit
    static var surrenders = 0                        // (tests)

    static func reset() { sheriffFell = [:]; warnedVisit = nil; greetedVisit = nil; surrenders = 0 }

    static func owns(_ town: String?) -> Bool { town.map { TownLaw.state.owned?[$0] != nil } ?? false }
    static func standing(_ town: String?) -> Standing {
        guard let t = town else { return .none }
        if owns(t) { return .owned }
        return wary.contains(t) ? .wary : .none
    }
    static var wary = Set<String>()                  // towns on edge after a taking nearby (worked out on arrival)

    // MARK: The surrender (Honour.mobDied: the sheriff or a deputy killed by the player in a real town)

    static func lawFell(_ g: Game, _ m: Mob, town: String) {
        guard !owns(town) else { return }
        if m.villager?.role == "sheriff" { sheriffFell[town] = g.clock }
        guard let t = sheriffFell[town], g.clock - t < sheriffWindow else { return }
        let standing = g.mobs.mobs.contains {
            $0 !== m && TownLaw.isTownsperson($0) && TownLaw.isLaw($0) && TownLaw.town(of: $0, g) == town && simd_length($0.pos - m.pos) < 160
        }
        if !standing { surrender(g, town, at: m.pos) }
    }

    static func surrender(_ g: Game, _ town: String, at p: V3) {
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        let a = g.world.gen.structures?.nearest("village", x: x, z: z, maxRegions: 1)?.anchor
        let day = Int(g.time / DAY_LENGTH)
        if TownLaw.state.owned == nil { TownLaw.state.owned = [:] }
        TownLaw.state.owned?[town] = [a?.x ?? x, a?.z ?? z, day, day]
        sheriffFell[town] = nil
        greetedVisit = town                              // (the surrender says it; no "is yours" toast on top)
        surrenders += 1
        // The fight's over: no hostility, no heat, no bounty here; the old grudges go with it.
        TownLaw.state.hostile[town] = nil
        TownLaw.state.heat[town] = nil
        Honour.clearBounty(town)
        TownLaw.pending.removeAll { TownLaw.town(of: $0.0, g) == town }
        var spokesman: Mob?
        for o in g.mobs.mobs where TownLaw.isTownsperson(o) && TownLaw.town(of: o, g) == town {
            o.town.anger = 0; o.panic = 0; o.town.handsUp = 6; o.town.foe = nil
            o.face(g.player.pos)
            if var v = o.villager, var gs = v.gossip {
                gs[Gossip.majorNeg.rawValue] = 0; gs[Gossip.minorNeg.rawValue] = 0
                v.gossip = gs; o.villager = v
            }
            if !o.baby, spokesman == nil || simd_length(o.pos - g.player.pos) < simd_length(spokesman!.pos - g.player.pos) { spokesman = o }
        }
        Honour.change(g, -honourCost, "you took \(town) by force")
        if let s = spokesman {
            Townsfolk.townLastLine = -100
            Townsfolk.say(g, s, "Don't shoot! We give up. \(town) is yours.")
        }
        g.sfx(.bell, 0.8, at: p)
        g.onToast?("\(town) surrenders. It's yours: its beds and chests, its best prices, and tribute every day.")
    }

    // MARK: Every second (TownLaw.tick): tribute in your towns, the neighbours' news.

    static func tick(_ g: Game, town here: String?) {
        guard let here, g.survival else { greetedVisit = nil; warnedVisit = nil; return }
        let day = Int(g.time / DAY_LENGTH)
        if var o = TownLaw.state.owned?[here], o.count >= 4 {
            guard greetedVisit != here else { return }
            greetedVisit = here
            let days = min(tributeCap, day - o[3])
            if days > 0 {
                o[3] = day
                TownLaw.state.owned?[here] = o
                g.money += days * tributePerDay
                g.sfx(.xp, 0.5)
                g.onToast?("Tribute from \(here): \(Money.format(days * tributePerDay)) (\(days) day\(days == 1 ? "" : "s"))")
                tributes += 1
            } else {
                g.onToast?("\(here) is yours.")
            }
            return
        }
        greetedVisit = nil
        // A town near one you took lately: on edge.
        let pos = g.player.pos
        let anchor = g.world.gen.structures?.nearest("village", x: Int(floor(pos.x)), z: Int(floor(pos.z)), maxRegions: 1)?.anchor
        let ax = Float(anchor?.x ?? Int(floor(pos.x))), az = Float(anchor?.z ?? Int(floor(pos.z)))
        let news = (TownLaw.state.owned ?? [:]).first { (t, o) in
            t != here && o.count >= 4 && day - o[2] < waryDays && simd_length(V2(Float(o[0]) - ax, Float(o[1]) - az)) < waryRadius
        }
        guard let (taken, _) = news else { wary.remove(here); return }
        wary.insert(here)
        guard warnedVisit != here else { return }
        warnedVisit = here
        TownLaw.state.heat[here] = max(TownLaw.heat(here), TownLaw.hostileHeat - 1)
        if let law = g.mobs.mobs.filter({ TownLaw.isTownsperson($0) && TownLaw.isLaw($0) && !$0.lying && simd_length($0.pos - pos) < 32 })
            .min(by: { simd_length($0.pos - pos) < simd_length($1.pos - pos) }) {
            law.face(pos)
            if simd_length(law.pos - pos) > 4 { law.wanderGoal = pos; law.moving = true; law.aiTimer = 4 }
            Townsfolk.townLastLine = -100
            Townsfolk.say(g, law, "Word's come from \(taken). You won't do here what you did there.")
        }
        g.onToast?("\(here) has heard what happened in \(taken). They're on edge.")
    }
    static var tributes = 0

    // MARK: Townsfolk in your towns (Game.townGreet)

    static func greet(_ g: Game, _ m: Mob, _ v: VillagerData) -> Bool {
        guard g.survival, owns(v.town) else { return false }
        let lines = TownLaw.isLaw(m) ? ["Town's quiet, boss.", "Nobody's giving trouble. I see to that.", "Your town, your rules, boss."]
                                     : ["Morning, boss.", "Anything you need, it's yours.", "We've kept your chests stocked.",
                                        "Tribute's ready when you are.", "Folks are settling down to you."]
        Townsfolk.say(g, m, Townsfolk.pick(lines, UInt64(v.look ?? 0) &+ UInt64(Int(g.clock))))
        return true
    }
}
