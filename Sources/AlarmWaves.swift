import Foundation
import simd

// P287 (Oct 14 19:51, a Greywall base: "literally everybody in the base came at once, which isn't right"). An alarm
// no longer turns a whole garrison loose on the noise in one go:
//   holders    marksmen, officers and every fourth of the rest keep their posts and their guns (they fight what they
//              see from where they stand; turret crews and a gun's own gunner were already held);
//   waves      the others answer in three waves, nearest the alarm first: the second 20 s later, the third 20 s after
//              that, so the men in the keep, the towers and the far barracks come out over time;
//   later men  soldiers who arrive after the alarm (dropship troops, truck squads) are reinforcements and go at once.
// A soldier who sees an enemy fights whatever his wave (his own sight, Soldiers.swift). Used by the Capital citadels'
// lockdown (CapitalBases.baseLockdown) and the Greywall Command alarm (GreywallAlarm.greywallAlarmTick).
enum AlarmWaves {
    static let every: Double = 20
    static let waves = 3
    static let holdShare = 4                     // one in four of the rest holds

    final class Plan {
        var start: Double
        var last: Double
        var role: [ObjectIdentifier: Int] = [:]  // 0 holds, 1...waves answers in that wave
        var sent = Set<ObjectIdentifier>()       // already sent toward the alarm (a wave's first call aims him)
        init(_ t: Double) { start = t; last = t }
    }
    static var plans: [String: Plan] = [:]

    // The plan of an alarm at `key`, made when the alarm is new (or after 15 s without a call: it stood down).
    static func plan(_ key: String, _ garrison: [Mob], src: V3, now: Double) -> Plan {
        if let p = plans[key], now - p.last < 15 { p.last = now; return p }
        let p = Plan(now)
        var rest: [Mob] = []
        for m in garrison {
            if m.kind == .soldierMarksman || m.kind == .soldierOfficer || m.brain?.gunPost != nil { p.role[ObjectIdentifier(m)] = 0 } else { rest.append(m) }
        }
        rest.sort { simd_length_squared($0.pos - src) < simd_length_squared($1.pos - src) }
        var answer: [Mob] = []
        for (i, m) in rest.enumerated() {
            // (the nearest man always answers: an alarm of one soldier still sends him)
            if i > 0 && i % holdShare == holdShare - 1 { p.role[ObjectIdentifier(m)] = 0 } else { answer.append(m) }
        }
        let per = max(1, Int((Float(answer.count) / Float(waves)).rounded(.up)))
        for (i, m) in answer.enumerated() { p.role[ObjectIdentifier(m)] = min(waves, 1 + i / per) }
        plans[key] = p
        if plans.count > 32 { plans = plans.filter { now - $0.value.last < 60 } }
        return p
    }

    enum Order { case hold, wait, go }
    // .go, and whether this is the call that first sends him (his own spot round the source is set then).
    static func send(_ m: Mob, _ p: Plan, now: Double) -> (Order, Bool) {
        let o = order(m, p, now: now)
        guard o == .go else { return (o, false) }
        return (o, p.sent.insert(ObjectIdentifier(m)).inserted)
    }
    static func order(_ m: Mob, _ p: Plan, now: Double) -> Order {
        guard let r = p.role[ObjectIdentifier(m)] else { return .go }      // came after the alarm: a reinforcement
        if r == 0 { return .hold }
        return now - p.start >= Double(r - 1) * every ? .go : .wait
    }
}
