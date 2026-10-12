import Foundation
import simd

// Radio spoofing checks (backlog C6; `questcheck --radio-only`, and part of every questcheck run), on a stand-in Capital
// citadel round the player: its console opens the radio net; a supply drop lands a filled crate in the yard; a fire
// mission needs a waypoint and drops three marked shells on it; requests raise suspicion (a repeat more), which cools;
// shells on their own base give the game away: the console's net goes dead, the citadels go on alert and a hunter
// squad led by a Spec Ops trooper comes; suspicion and the dead net are saved.
enum RadioTests {
    static func run(game g: Game, check: (Bool, String) -> Void) {
        let w = g.world
        let p0 = g.player.pos, surv0 = g.survival, mobs0 = g.mobs.mobs, recs0 = g.bases.records, marks0 = MapCache.shared.marks
        let strikes0 = g.ashStrikes, toast0 = g.onToast
        var placed: [IVec3] = []
        defer {
            for q in placed { w.setBlock(q.x, q.y, q.z, AIR) }
            g.player.pos = p0; g.survival = surv0; g.mobs.mobs = mobs0; g.bases.records = recs0
            MapCache.shared.replaceMarks(marks0); g.ashStrikes = strikes0; g.onToast = toast0
            g.radio.suspicion = [:]; g.radio.burned = []; g.radio.alertUntil = [:]; g.radio.last = [:]; g.radio.drops = []
            if g.menu is RadioMenu { g.closeMenu() }
        }
        g.onToast = { _ in }
        g.survival = true
        let cx = Int(floor(p0.x)), cz = Int(floor(p0.z))
        let y0 = Int(floor(p0.y)) - 5
        g.bases.records["radiotest"] = BaseRecord(key: "radiotest", cx: cx, cz: cz, y0: y0)
        let c = IVec3(cx + 1, Int(floor(p0.y)), cz)
        w.setBlock(c.x, c.y, c.z, Blocks.id("command_console")); placed.append(c)
        let opened = g.radioUse(c) && g.menu is RadioMenu
        let plain = IVec3(cx - 1, Int(floor(p0.y)), cz)
        w.setBlock(plain.x, plain.y, plain.z, STONE); placed.append(plain)
        let notStone = !g.radioUse(plain)
        if g.menu is RadioMenu { g.closeMenu() }
        guard let net = RadioNet.net(g, at: c) else { check(false, "radio: the console in the citadel has a net"); return }
        check(opened && notStone && net.faction == .steelhold, "radio: a citadel's command console opens its radio net (\(opened)); other blocks don't (\(notStone))")

        // A supply drop.
        let r1 = g.radioRequest(net, strike: false)
        let s1 = g.radio.suspicion[Faction.steelhold.rawValue] ?? 0
        for _ in 0..<180 { g.radioTick(0.05) }
        let yard = IVec3(Int(floor(net.yard.x)), 0, Int(floor(net.yard.z)))
        var crate: IVec3?
        for y in (y0 - 20)...(y0 + 60) where w.block(yard.x, y, yard.z) == Blocks.id("chest") { crate = IVec3(yard.x, y, yard.z) }
        let filled = crate.flatMap { w.blockEntities[$0] }.map { $0.container.slots.contains { !$0.isEmpty } } ?? false
        if let q = crate { placed.append(q) }
        check(r1.ok && s1 == RadioNet.perRequest && filled, "radio: a supply drop is answered (\(r1.text)), suspicion \(Int(s1)), and a filled crate lands in the yard (\(crate.map { "\($0.y)" } ?? "none"))")

        // A fire mission: needs a waypoint; then three shells marked on it; a repeat within a minute costs more.
        MapCache.shared.replaceMarks([])
        let none = g.radioRequest(net, strike: true)
        MapCache.shared.togglePin(g, x: cx + 60, z: cz, near: 0)
        let n0 = g.ashStrikes.count
        let r2 = g.radioRequest(net, strike: true)
        let shells = g.ashStrikes.dropFirst(n0)
        let onPin = shells.allSatisfy { abs($0.at.x - Float(cx + 60)) < 5 && abs($0.at.z - Float(cz)) < 5 }
        let s2 = g.radio.suspicion[Faction.steelhold.rawValue] ?? 0
        check(!none.ok && r2.ok && shells.count == 3 && onPin && abs(s2 - (2 * RadioNet.perRequest + RadioNet.repeatExtra)) < 0.5,
              "radio: no waypoint, no fire mission (\(none.text)); with one, three shells marked on it (\(shells.count), on the pin \(onPin)); suspicion \(Int(s2)) after a quick repeat")
        g.ashStrikes = strikes0
        // Cooling: 100 s takes 5 off.
        for _ in 0..<100 { g.radioTick(1) }
        g.ashStrikes = strikes0
        let s3 = g.radio.suspicion[Faction.steelhold.rawValue] ?? 0
        check(abs(s2 - s3 - 5) < 0.5, String(format: "radio: suspicion cools, %.0f to %.0f in 100 s", s2, s3))

        // Shells on their own base: they know.
        MapCache.shared.replaceMarks([])
        MapCache.shared.togglePin(g, x: cx + 3, z: cz + 3, near: 0)
        g.mobs.mobs = []
        let r3 = g.radioRequest(net, strike: true)
        let hunters = g.mobs.mobs.filter { $0.aggro && $0.faction == Faction.steelhold.rawValue }
        let lead = hunters.contains { $0.troopClass == .specOps }
        let dead = g.radioRequest(net, strike: false)
        let alert = g.bases.records["radiotest"]?.alert ?? .calm
        check(!r3.ok && g.radio.burned.contains(net.key) && hunters.count == 4 && lead && alert.rawValue >= BaseAlert.alert.rawValue
              && g.radio.alerted(.steelhold, g.clock) && !dead.ok && dead.text.contains("Unknown station"),
              "radio: a fire mission on their own citadel gives it away (\(r3.text)): \(hunters.count) hunters, a Spec Ops lead (\(lead)), the citadel on \(alert.name), the net dead (\(dead.text))")

        // Saved.
        let saved = g.radio.saved
        let back = RadioState(); back.load(saved.0, saved.1)
        check(back.burned == g.radio.burned && back.suspicion[Faction.steelhold.rawValue] == g.radio.suspicion[Faction.steelhold.rawValue],
              "radio: suspicion and the dead net are kept through a save (\(saved.0); \(saved.1))")
    }
}
