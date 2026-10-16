import Foundation
import simd

// D38: lost bases counter-attack, and a base's alarm survives a reload.
//   counter-attack  Greywall Command doesn't forget a base you took. Three days after it fell (and every three days
//                   after that) while you're within 120 blocks of it, two squads march on its gate to take it back.
//                   Kill them all and the base holds (+$50, honour); leave any of them standing inside the walls
//                   for two and a half minutes and Greywall has its base back (its alarm, its guns' crews, the lot).
//   alarm on reload a base whose alarm was up when you saved is still up when you come back (TownLaw.state.alarms).
enum BaseCounter {
    static let every = 3
    static let holdFor: Double = 150
    struct Attack { let start: Double; var squad: [Mob] }
    static var active: [String: Attack] = [:]
    static var held = 0, lost = 0                         // (harness)
}

extension Game {
    // Once a second, beside bodiesTick (CapitalBases basesTick).
    func baseCounterTick(_ b: BaseWatch) {
        let st = b.greywall
        // The alarm's state, kept for a reload.
        // (bases not scanned yet keep what was saved: after a load the sites fill in as their ground comes in)
        let saved = TownLaw.state.alarms ?? []
        let on = (saved.filter { st.sites[$0] == nil } + st.sites.filter { $0.value.on }.map { $0.key }).sorted()
        if on != saved { TownLaw.state.alarms = on.isEmpty ? nil : on }
        guard survival, dim.dim == .overworld else { return }
        let day = Int(time / DAY_LENGTH)
        let pp = player.pos
        for (key, site) in st.sites where st.taken.contains(key) {
            if var a = BaseCounter.active[key] {
                a.squad.removeAll { s in s.health <= 0 || !mobs.mobs.contains(where: { $0 === s }) }
                BaseCounter.active[key] = a
                if a.squad.isEmpty {
                    BaseCounter.active[key] = nil
                    BaseCounter.held += 1
                    money += 5000
                    Honour.earn(self, 2, source: "outlaw", "a base held")
                    onToast?("The counter-attack is broken: the \(site.tier.name) is still yours (+\(Money.format(5000)))")
                } else if clock - a.start > BaseCounter.holdFor, a.squad.contains(where: { Greywall.inside(site, $0.pos) }) {
                    BaseCounter.active[key] = nil
                    BaseCounter.lost += 1
                    st.taken.remove(key)
                    onToast?("Greywall has taken the \(site.tier.name) back")
                }
                continue
            }
            var last = TownLaw.state.counter ?? [:]
            guard let d0 = last[key] else { last[key] = day; TownLaw.state.counter = last; continue }     // (the day it fell)
            guard day - d0 >= BaseCounter.every, simd_length(V2(pp.x - Float(site.cx), pp.z - Float(site.cz))) < 120 else { continue }
            last[key] = day; TownLaw.state.counter = last
            let n0 = mobs.mobs.count
            let H = site.tier.half
            for row in 0..<2 {
                greywallSquadOnFoot(row == 0 ? "soldier_officer" : "soldier_marksman", leash: Greywall.leashTag(site.cx, site.cz, site.tier),
                                    src: V3(Float(site.cx) + 0.5, Float(site.S + 1), Float(site.cz) + 0.5),
                                    at: { i in self.world.freeSpawn(V3(Float(site.cx + i * 2 - 2) + 0.5, Float(site.S + 1), Float(site.cz + H + 6 + row * 2) + 0.5)) })
            }
            let squad = Array(mobs.mobs[n0...])
            BaseCounter.active[key] = BaseCounter.Attack(start: clock, squad: squad)
            onToast?("Greywall is counter-attacking the \(site.tier.name)!")
        }
    }
}
