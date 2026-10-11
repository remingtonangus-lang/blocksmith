import Foundation
import simd

// Honour and bounties: a frontier reputation for the whole world (docs/status/honour.md).
//
// Honour runs from -100 to +100 (saved with the town law state, TownLaw.Saved.honour). Crimes the law sees cost it:
// theft and vandalism (1.5 a point of the town's heat), assault, a town turning on you (5), killing a townsperson (15),
// a deputy (20), the sheriff (25). Good deeds earn it, capped per day and per source so a night of zombie farming
// can't max it: monsters killed in or near a town (+1, raiders +2, 8 a day), outlaws killed in the wild (Brigands and
// crossbowmen outside a raid, +3, 9 a day), a bounty paid (+3).
//   Outlaw <= -60 < Disreputable <= -20 < Neutral < 20 <= Respected < 60 <= Honourable
// It moves shop prices a little (ShopPricing, inside the bounds the no-arbitrage check uses), the townsfolk's
// greetings, how fast a town's heat cools (twice as fast for the honourable, half for an outlaw), and the law (an
// outlaw is challenged on arriving in a town).
//
// Bounties: a town that turns on you puts $5 on your head, each townsperson killed there $15 more (deputy $20, sheriff
// $25). While one is out, that town's keepers won't serve you and its law challenges you once a visit. Talking to the
// sheriff or a deputy pays it (in the middle of a fight too: you give yourself up), which ends the hostility and cools
// the town. A bounty lapses after `lapseDays` with no new crime there, so a player who can't pay, with the sheriff
// dead, is never locked out of a town for good.
enum Honour {
    static let outlaw: Float = -60, disreputable: Float = -20, respected: Float = 20, honourable: Float = 60
    static let lapseDays = 7
    static let dailyCap: [String: Float] = ["monster": 8, "outlaw": 9, "trade": 3, "job": 15, "donation": 6, "theft": 10, "defence": 10]
    static let outlawFine = 1000                    // cents: what surrendering as an outlaw costs (on top of bounties)

    // HUD (HonourHUD.lines) and the toast throttle.
    static var changedAt: Double = -100
    static var delta: Float = 0
    static var lastToast: Double = -100
    static var lastWhy = ""
    static let logCap = 60
    // The log's entries as (day, amount, why), oldest first.
    static var log: [(day: Int, amount: Float, why: String)] {
        (TownLaw.state.honourLog ?? []).compactMap { e in
            let p = e.split(separator: "|", maxSplits: 2).map(String.init)
            guard p.count == 3, let d = Int(p[0]), let a = Float(p[1]) else { return nil }
            return (d, a, p[2])
        }
    }
    static var challengedVisit: String?             // the town whose law already challenged you this visit

    static var value: Float {
        get { TownLaw.state.honour ?? 0 }
        set { TownLaw.state.honour = max(-100, min(100, newValue)) }
    }

    static func standing(_ h: Float) -> String {
        h <= outlaw ? "Outlaw" : h <= disreputable ? "Disreputable" : h < respected ? "Neutral" : h < honourable ? "Respected" : "Honourable"
    }
    static var isOutlaw: Bool { value <= outlaw }

    // Shop price nudge: down to 5% off at +100, up to 10% dearer at -100 (ShopPricing clamps to the shop bounds).
    static func buyNudge(_ h: Float) -> Float { h >= 0 ? -0.05 * h / 100 : -0.10 * h / 100 }
    static func sellNudge(_ h: Float) -> Float { h >= 0 ? 0.05 * h / 100 : 0.10 * h / 100 }
    // How fast a town's heat cools (TownLaw.tick).
    static func coolRate(_ h: Float) -> Float { h >= honourable ? 2 : h <= outlaw ? 0.5 : 1 }

    // MARK: Changing it

    static func change(_ g: Game, _ amount: Float, _ why: String) {
        guard amount != 0, g.survival else { return }
        let before = value
        value = before + amount
        let d = value - before
        guard d != 0 else { return }
        let burst = why == lastWhy && g.clock - changedAt < 1          // (the same deed again at once: one sound)
        delta = g.clock - changedAt < 6 ? delta + d : d
        changedAt = g.clock
        lastWhy = why
        // The log (tests prove each rule from it; the notice board shows the latest).
        var log = TownLaw.state.honourLog ?? []
        log.append("\(Int(g.time / DAY_LENGTH))|\(String(format: "%.1f", d))|\(why)")
        if log.count > logCap { log.removeFirst(log.count - logCap) }
        TownLaw.state.honourLog = log
        // The meter pulses (HonourHUD) with a soft chime up or a low knell down.
        if !burst { g.sfx(d > 0 ? .amethystChime : .bellResonate, d > 0 ? 0.45 : 0.3) }
        if standing(before) != standing(value) {
            g.onToast?("Honour: \(standing(value))")
            lastToast = g.clock
        } else if g.clock - lastToast > 8 {
            g.onToast?(d > 0 ? "Honour raised (\(why))" : "Honour lowered (\(why))")
            lastToast = g.clock
        }
    }

    // A good deed from a capped source: what's left of today's allowance for it.
    static func earn(_ g: Game, _ amount: Float, source: String, _ why: String) {
        let key = "\(Int(g.time / DAY_LENGTH)):\(source)"
        var gains = TownLaw.state.honourGains ?? [:]
        if gains.keys.contains(where: { !$0.hasPrefix("\(Int(g.time / DAY_LENGTH)):") }) { gains = gains.filter { $0.key.hasPrefix("\(Int(g.time / DAY_LENGTH)):") } }
        let used = gains[key] ?? 0
        let cap = dailyCap[source] ?? .infinity
        let give = min(amount, cap - used)
        guard give > 0 else { TownLaw.state.honourGains = gains; return }
        gains[key] = used + give
        TownLaw.state.honourGains = gains
        change(g, give, why)
    }

    // Unseen theft (TownLaw.offence with no witness): a loss, capped at 10 a day like the gains (so clearing a town
    // field at night costs some honour, not all of it), with the chime only once for a burst (change).
    static func unseenTheft(_ g: Game, _ amount: Float) {
        let key = "\(Int(g.time / DAY_LENGTH)):theft"
        var gains = TownLaw.state.honourGains ?? [:]
        let used = gains[key] ?? 0
        let take = min(amount, (dailyCap["theft"] ?? 10) - used)
        guard take > 0 else { return }
        gains[key] = used + take
        TownLaw.state.honourGains = gains
        change(g, -take, "theft, unseen")
    }

    // What's left of today's allowance for a capped source.
    static func capLeft(_ g: Game, _ source: String) -> Float {
        let key = "\(Int(g.time / DAY_LENGTH)):\(source)"
        return (dailyCap[source] ?? .infinity) - (TownLaw.state.honourGains?[key] ?? 0)
    }

    // MARK: Bounties (cents)

    static func bounty(_ town: String) -> Int { TownLaw.state.bounty?[town] ?? 0 }
    static func addBounty(_ g: Game, _ town: String, _ cents: Int) {
        guard g.survival, cents > 0 else { return }
        if TownLaw.state.bounty == nil { TownLaw.state.bounty = [:] }
        if TownLaw.state.bountyDay == nil { TownLaw.state.bountyDay = [:] }
        TownLaw.state.bounty?[town, default: 0] += cents
        TownLaw.state.bountyDay?[town] = Int(g.time / DAY_LENGTH)
    }
    static func clearBounty(_ town: String) {
        TownLaw.state.bounty?[town] = nil
        TownLaw.state.bountyDay?[town] = nil
    }

    // Talking to the law with a bounty out in their town: pay it (and give yourself up if the town is fighting you).
    // Returns false when there's no bounty here (the talk goes on as usual).
    static func settle(_ g: Game, _ lawman: Mob) -> Bool {
        let town = TownLaw.town(of: lawman, g)
        // An outlaw surrenders to any lawman: the fine on top of what's owed here, and honour back to Disreputable.
        let fine = isOutlaw ? outlawFine : 0
        let owed = bounty(town) + fine
        guard owed > 0, TownLaw.isLaw(lawman) else { return false }
        lawman.face(g.player.pos)
        let who = lawman.villager?.person ?? "The sheriff"
        guard g.money >= owed else {
            Townsfolk.say(g, lawman, fine > 0 ? "Your fine's \(Money.format(owed)), outlaw. Come back when you can pay it."
                                              : "There's \(Money.format(owed)) on your head. Come back when you can pay it.")
            return true
        }
        g.money -= owed
        clearBounty(town)
        if fine > 0 { for t in Array((TownLaw.state.bounty ?? [:]).keys) where bounty(t) == 0 { clearBounty(t) } }
        TownLaw.state.hostile[town] = nil
        TownLaw.state.heat[town] = nil
        TownLaw.pending.removeAll { TownLaw.town(of: $0.0, g) == town }
        // Paid in full: the town lets the old grudges go (their bad gossip would set the armed back on you, and keep
        // the counters shut below -100, the moment you stood near them).
        for o in g.mobs.mobs where TownLaw.isTownsperson(o) && TownLaw.town(of: o, g) == town {
            o.town.anger = 0; o.panic = 0
            if var v = o.villager, var gs = v.gossip {
                gs[Gossip.majorNeg.rawValue] = 0; gs[Gossip.minorNeg.rawValue] = 0
                v.gossip = gs; o.villager = v
            }
        }
        challengedVisit = town
        Townsfolk.townLastLine = -100
        Townsfolk.say(g, lawman, "That settles it. Keep your nose clean in \(town).")
        outlawSpotted = nil
        g.onToast?("\(fine > 0 ? "Fine" : "Bounty") of \(Money.format(owed)) paid to \(who)")
        if fine > 0 { change(g, outlaw + 5 - value, "you gave yourself up") } else { change(g, 3, "you paid your bounty") }
        return true
    }

    // MARK: Hooks

    // TownLaw.offence: a witnessed crime (heat points added) in a town.
    static func crime(_ g: Game, heat: Float, assault: Bool) {
        change(g, -(assault ? 3 : 1.5 * heat), assault ? "assault" : "theft")
    }
    // TownLaw.turnHostile (a fresh turn only).
    static func townTurned(_ g: Game, _ town: String) {
        change(g, -5, "\(town) turned on you")
        addBounty(g, town, 500)
    }

    // Game.mobDied.
    static func mobDied(_ g: Game, _ m: Mob) {
        TownBoard.mobDied(g, m)                                          // (any death: an outlaw drowned ends his job too)
        guard m.killedByPlayer, g.survival, g.dim.dim == .overworld else { return }
        if m.posse != 0 { return }                                       // hunters, an outlaw and his gang: no honour
        if m.kind == .villager, m.villager?.person != nil {
            // Only a killing the player did (hurt within 10 s: killedByPlayer is never cleared, so a punch long ago
            // or a rocket that missed doesn't make a later death to a zombie murder) and only in a real town (a
            // villager at your own base has a made-up town with no law to pay).
            guard g.clock - m.playerHurtAt < 10,
                  TownLaw.isTownSpot(g, IVec3(Int(floor(m.pos.x)), Int(floor(m.pos.y)), Int(floor(m.pos.z)))) else { return }
            let role = m.villager?.role ?? ""
            let town = TownLaw.town(of: m, g)
            let (loss, cents) = role == "sheriff" ? (Float(25), 2500) : role == "deputy" ? (20, 2000) : (m.baby ? 25 : 15, 1500)
            change(g, -loss, role == "sheriff" ? "you killed the sheriff" : "murder")
            addBounty(g, town, cents)
            if role == "sheriff" { sheriffDrops(g, m) }
            if role == "sheriff" || role == "deputy" { TownConquest.lawFell(g, m, town: town) }   // the town may give up
            return
        }
        guard m.kind.hostile else { return }
        let outlawKind = m.kind == .vindicator || m.kind == .pillager
        if outlawKind && !m.raider && TownLaw.inTown == nil {
            earn(g, 3, source: "outlaw", "outlaw killed")
        } else if TownLaw.inTown != nil || nearTownsfolk(g, m.pos) {
            earn(g, m.raider ? 2 : 1, source: "monster", m.raider ? "raider killed" : "you protected the town")
        }
    }
    static func nearTownsfolk(_ g: Game, _ p: V3) -> Bool {
        g.mobs.mobs.contains { TownLaw.isTownsperson($0) && simd_length($0.pos - p) < 32 }
    }

    // MARK: The six-iron

    // Every sheriff carries a six-iron (SixIron.swift; backlog B1 replaced the old 5% gun chance). One in four comes
    // out of the fight in good enough shape to take: a killed sheriff drops it loaded `revolverChance` of the time, and
    // always a few cartridges. (VillagerData.revolver, the old per-sheriff roll, is still read from saves but no
    // longer matters.)
    static var revolverChance: Float = 0.25
    static func rollRevolver(_ r: Float) -> Bool { r < revolverChance }
    static func carriesRevolver(_ m: Mob) -> Bool { m.villager?.role == "sheriff" }
    static func sheriffDrops(_ g: Game, _ m: Mob) {
        let at = m.pos + V3(0, 0.5, 0)
        if Items.has("rifle_rounds") { g.drops.spawn(ItemStack(Items.id("rifle_rounds"), Rand.int(in: 3...8)), at: at) }
        if Items.has(Guns.revolverKey), carriesRevolver(m), rollRevolver(Rand.float(in: 0..<1)) {
            var s = ItemStack(Items.id(Guns.revolverKey), 1)
            s.tag = Guns.all[Guns.revolver].mag
            g.drops.spawn(s, at: at)
        }
    }

    // MARK: Every second (TownLaw.tick): lapsed bounties, the law's challenge on arrival.

    static func tick(_ g: Game, town here: String?) {
        let day = Int(g.time / DAY_LENGTH)
        if let days = TownLaw.state.bountyDay {
            for (t, d) in days where day - d >= lapseDays {
                clearBounty(t)
                g.onToast?("The bounty in \(t) has lapsed.")
            }
        }
        guard let here else { challengedVisit = nil; outlawSpotted = nil; return }
        guard challengedVisit != here, g.survival, !TownLaw.isHostile(here), !TownConquest.owns(here), bounty(here) > 0 || isOutlaw else { return }
        // The nearest lawman who can see you calls you out and walks over.
        guard let law = g.mobs.mobs.filter({ TownLaw.isTownsperson($0) && TownLaw.isLaw($0) && !$0.lying && simd_length($0.pos - g.player.pos) < 24
                                              && g.world.canSee($0.eye, g.player.eye) })
            .min(by: { simd_length($0.pos - g.player.pos) < simd_length($1.pos - g.player.pos) }) else { return }
        challengedVisit = here
        law.face(g.player.pos)
        if simd_length(law.pos - g.player.pos) > 4 { law.wanderGoal = g.player.pos; law.moving = true; law.aiTimer = 4 }
        Townsfolk.townLastLine = -100
        TownVoice.speak(g, law, .challenge)
        let owed = bounty(here)
        g.onToast?(owed > 0 ? "Wanted in \(here): \(Money.format(owed)). Talk to the law to pay it." : "The law here knows your name, outlaw.")
    }
}

// MARK: What the standings do in town (the gap pass): outlaws fought on sight, the disreputable warned off, the
// respected told where things are, the honourable given gifts.
extension Honour {
    static var outlawSpotted: (town: String, at: Double)?
    static var tipChance: Float = 0.25
    static var giftChance: Float = 0.5

    // TownLaw.tick, once a second while an outlaw is in a town that isn't already fighting them: the first townsperson
    // to see them cries out; 3 s later everyone armed who can see them comes for them and the rest run.
    static func outlawSeen(_ g: Game, _ town: String) {
        for o in g.mobs.mobs where TownLaw.isTownsperson(o) && !o.lying && TownLaw.town(of: o, g) == town {
            guard simd_length(o.pos - g.player.pos) < 24, g.world.canSee(o.eye, g.player.eye) else { continue }
            if outlawSpotted?.town != town {
                outlawSpotted = (town, g.clock)
                o.face(g.player.pos)
                Townsfolk.townLastLine = -100
                Townsfolk.say(g, o, TownLaw.isLaw(o) ? "You've got some gall riding in here, outlaw." : "It's that outlaw! Somebody fetch the sheriff!")
                g.onToast?("You're an outlaw: \(town) will fight you on sight. Surrender to the law to pay your fine")
            }
            guard let s = outlawSpotted, g.clock - s.at > 3 else { continue }
            if o.townWeapon != .none && !o.baby { o.town.anger = max(o.town.anger, 3) } else { o.panic = max(o.panic, 4) }
        }
    }

    // TownLaw's greeting hook: what the standing adds. Returns true when it said something itself.
    static func greet(_ g: Game, _ m: Mob, _ v: VillagerData) -> Bool {
        guard g.survival else { return false }
        let h = value
        let lines: [String]
        if h <= disreputable {
            lines = ["I know what you are. Keep your hands where I can see them.", "We don't want your kind of trouble here.",
                     "Folks say you're no good. Move along."]
            if m.townWeapon == .none { m.panic = max(m.panic, 2) }
            Townsfolk.say(g, m, Townsfolk.pick(lines, UInt64(v.look ?? 0) &+ UInt64(Int(g.clock))))
            return true
        }
        guard h >= respected else { return false }
        let name = TownBoard.playerName
        // The sheriff mentions his six-iron.
        if Honour.carriesRevolver(m) && Rand.float(in: 0..<1) < 0.5 {
            Townsfolk.say(g, m, "Afternoon, \(name). This here six-iron stays holstered for folks like you.")
            return true
        }
        // The honourable: a gift, once a day per town.
        let town = TownLaw.town(of: m, g)
        let day = Int(g.time / DAY_LENGTH)
        let key = "\(day):\(town)"
        if h >= honourable && !m.baby && !(TownLaw.state.gifts ?? []).contains(key) && Rand.float(in: 0..<1) < giftChance {
            let gifts: [(String, Int)] = [("bread", 3), ("apple", 4), ("cooked_beef", 2), ("arrow", 8), ("emerald", 1), ("golden_carrot", 2),
                                          ("potion_healing", 1), ("rifle_rounds", 6), ("honey_bottle", 1)]
                .filter { Items.has($0.0) }
            if let (item, n) = gifts.isEmpty ? nil : gifts[Int(UInt64(v.look ?? 0) &+ UInt64(day)) % gifts.count] {
                g.drops.spawn(ItemStack(Items.id(item), n), at: m.eye + m.forward * 0.6, delay: 0)
                TownLaw.state.gifts = ((TownLaw.state.gifts ?? []).filter { $0.hasPrefix("\(day):") }) + [key]
                giftsGiven += 1
                Townsfolk.say(g, m, "\(name)! Here, take this. Folks like you keep \(town) safe.")
                return true
            }
        }
        // The respected: a tip about something worth finding nearby.
        if Rand.float(in: 0..<1) < tipChance, let t = tip(g, from: m.pos) {
            Townsfolk.say(g, m, "Good to see you, \(name). " + t)
            return true
        }
        if Rand.float(in: 0..<1) < 0.5 { Townsfolk.say(g, m, Townsfolk.pick(["Good to see you again, \(name).", "Howdy, \(name)!", "Evening, \(name). Stay safe out there."], UInt64(v.look ?? 0) &+ UInt64(Int(g.clock)))); return true }
        return false
    }
    static var giftsGiven = 0

    // "Word is there's ... about N blocks north-west of here."
    static let tipKinds: [(String, String)] = [("wild_camp", "an outlaw camp"), ("pillager_outpost", "a raiders' outpost"),
                                               ("shipwreck", "a wreck washed up"), ("ruined_portal", "old ruins with a strange arch"),
                                               ("temple", "an old temple"), ("trail_ruins", "buried ruins"), ("military_base", "an army base"),
                                               ("mineshaft", "an old mine")]
    // One lookup per town per day (StructureCache.nearest can lay out structures: not on every greeting).
    private static var tipCache: [String: String?] = [:]
    static func tip(_ g: Game, from p: V3) -> String? {
        let key = "\(Int(g.time / DAY_LENGTH)):\(TownLaw.inTown ?? Townsfolk.town(g, at: p))"
        if let c = tipCache[key] { if c != nil { tipsGiven += 1 }; return c }
        if tipCache.count > 64 { tipCache.removeAll() }
        let t = findTip(g, from: p)
        tipCache[key] = .some(t)
        if t != nil { tipsGiven += 1 }
        return t
    }
    static func findTip(_ g: Game, from p: V3) -> String? {
        guard let sc = g.world.gen.structures else { return nil }
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        var best: (Float, String, Float, Float)?
        for (k, what) in tipKinds {
            guard let s = sc.nearest(k, x: x, z: z, maxRegions: 2) else { continue }
            let dx = Float((s.min.x + s.max.x) / 2 - x), dz = Float((s.min.z + s.max.z) / 2 - z)
            let d = (dx * dx + dz * dz).squareRoot()
            if d > 40 && d < 1200 && (best == nil || d < best!.0) { best = (d, what, dx, dz) }
        }
        guard let b = best else { return nil }
        return "Word is there's \(b.1) about \(Int(b.0 / 10) * 10) blocks \(TownBoard.direction(b.2, b.3)) of here."
    }
    static var tipsGiven = 0
}

// The honour standing on the HUD, under the wallet: shown in towns and for 6 s after a change (with the change).
enum HonourHUD {
    static func lines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        let inv = g.menu is InventoryMenu                               // the inventory always shows it, under the wallet
        guard HudExtras.enabled, !g.hideHUD, g.menu == nil || inv, g.alive, g.survival else { return [] }
        let recent = g.clock - Honour.changedAt < 6
        guard recent || TownLaw.inTown != nil || inv else { return [] }
        let s = L.s
        let walletShown = TownLaw.inTown != nil || g.clock - Wallet.changedAt < 6 || inv
        var y = L.insetY + 6 * s + (g.effects.any && !inv ? 54 * s : 0) + (walletShown ? 14 * s : 0)     // one line under the wallet
        if Settings.shared.minimap && !inv { y += 64 * s + 30 * s }
        let h = Honour.value
        let t = "Honour: " + Honour.standing(h)
        // A change pulses the meter: it swells and brightens for 0.8 s, then settles (with the chime from change()).
        let since = Float(g.clock - Honour.changedAt)
        let pulse = recent && since < 0.8 ? 1 - since / 0.8 : 0
        let ps = s * (1 + 0.3 * pulse)
        let w = Float(Font.width(t)) * ps
        let x = L.W - L.insetX - w - 8 * s
        var c = h <= Honour.disreputable ? V4(1, 0.55, 0.45, 1) : h >= Honour.respected ? V4(0.6, 0.85, 1, 1) : V4(0.9, 0.9, 0.86, 1)
        if pulse > 0 { c = c + (V4(1, 1, 1, 1) - c) * (0.6 * pulse); c.w = 1 }
        var out = [HudLine(text: t, x: x, y: y - 4 * s * pulse, scale: ps, color: c, bg: V4(0, 0, 0, 0.55))]
        var below = y + 14 * s
        if recent && Honour.delta != 0 {
            let fade = Float(max(0, min(1, 6 - (g.clock - Honour.changedAt))))
            let d = (Honour.delta > 0 ? "+" : "") + String(Int(Honour.delta.rounded()))
            let dw = Float(Font.width(d)) * s
            let dc = Honour.delta > 0 ? V4(0.45, 1, 0.45, fade) : V4(1, 0.45, 0.4, fade)
            out.append(HudLine(text: d, x: x - dw - 6 * s, y: y, scale: s, color: dc))
            // The reason, under the meter.
            if !Honour.lastWhy.isEmpty {
                let why = ShopMenu.fit(Honour.lastWhy, 200)
                let ww = Float(Font.width(why)) * s
                out.append(HudLine(text: why, x: L.W - L.insetX - ww - 8 * s, y: below, scale: s, color: V4(dc.x, dc.y, dc.z, fade), bg: V4(0, 0, 0, 0.45 * fade)))
                below += 14 * s
            }
        }
        if let here = TownLaw.inTown, Honour.bounty(here) > 0 {
            let b = "Wanted: " + Money.format(Honour.bounty(here))
            let bw = Float(Font.width(b)) * s
            out.append(HudLine(text: b, x: L.W - L.insetX - bw - 8 * s, y: below, scale: s, color: V4(1, 0.4, 0.3, 1), bg: V4(0, 0, 0, 0.55)))
        }
        return out
    }
}
