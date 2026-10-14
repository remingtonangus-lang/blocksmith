import Foundation
import simd

// D34: base objectives. Every Greywall base not yet yours has three side objectives, announced the first time you're
// inside its walls (and on each visit after, with what's left):
//   comms array   break every alarm panel (the comms room's, the keep's and the towers'): the base can't call for
//                 help, and the comms desk gives up its intercepted orders and a pair of diamonds.
//   the plans     stand at a command console for three seconds: you take the base's plans (a Greywall dispatch that
//                 names the next base up the chain) and its war chest ($40).
//   the prisoner  a captured scout is held in the keep. Reach him with no Greywall soldier within 12 blocks and he's
//                 free: he slips out, and pays you what he can ($60) and a little honour.
// Done objectives are saved per base (TownLaw.state.baseObj: bit 1 comms, 2 plans, 4 prisoner, 8 the scout placed).
enum BaseObjectives {
    static let names = ["destroy the comms array", "steal the plans", "free the prisoner"]
    static var told = Set<String>()                        // bases announced this session
    static var atConsole: [String: Float] = [:]
    static var done = 0                                    // (harness)

    static func bits(_ key: String) -> Int { TownLaw.state.baseObj?[key] ?? 0 }
    static func set(_ key: String, _ bit: Int) {
        var o = TownLaw.state.baseObj ?? [:]
        o[key] = (o[key] ?? 0) | bit
        TownLaw.state.baseObj = o
    }
    static func left(_ key: String) -> [String] { (0..<3).filter { bits(key) & (1 << $0) == 0 }.map { names[$0] } }
    static func scoutName(_ key: String) -> String { "Captive Scout" }
}

extension Game {
    // Once a second, after greywallAlarmTick (CapitalBases basesTick).
    func baseObjectivesTick(_ b: BaseWatch, _ dt: Float) {
        guard survival else { return }
        let st = b.greywall
        let pp = player.pos
        for (key, site) in st.sites where !st.taken.contains(key) {
            let inside = Greywall.inside(site, pp)
            if inside && !BaseObjectives.told.contains(key) {
                BaseObjectives.told.insert(key)
                let l = BaseObjectives.left(key)
                if !l.isEmpty { onToast?("\(site.tier.name) objectives: " + l.joined(separator: ", ")) }
            }
            // The scout, placed once (persistent: saved with the ground after that).
            if BaseObjectives.bits(key) & 12 == 0, simd_length(V2(pp.x - Float(site.cx), pp.z - Float(site.cz))) < 96,
               world.isLoaded(site.cx, site.cz + site.tier.keepC) {
                let at = world.freeSpawn(V3(Float(site.cx) + 0.5, Float(site.S + 1), Float(site.cz + site.tier.keepC) + 0.5))
                let m = Mob(.villager, at: at)
                Townsfolk.setup(m, game: self)
                if var v = m.villager { v.role = "captive"; v.locked = true; v.profession = "none"; m.villager = v }
                m.customName = BaseObjectives.scoutName(key)
                m.persistent = true
                m.home = at
                mobs.mobs.append(m)
                BaseObjectives.set(key, 8)
            }
            guard inside else { continue }
            let bits = BaseObjectives.bits(key)
            // The comms array.
            if bits & 1 == 0, !site.panels.isEmpty, site.panelsDown || greywallPanelsStanding(site) == 0 {
                BaseObjectives.set(key, 1); BaseObjectives.done += 1
                for (k, n) in [("intercepted_orders", 1), ("diamond", 2)] where Items.has(k) { drops.spawn(ItemStack(Items.id(k), n), at: pp + V3(0, 0.5, 0)) }
                sfx(.levelUp, 0.6)
                onToast?("Comms array down: the orders on the comms desk are yours")
            }
            // The plans.
            if bits & 2 == 0 {
                let near = site.consoles.contains { simd_length(V3(Float($0.x) + 0.5, Float($0.y), Float($0.z) + 0.5) - pp) < 2.6 }
                let t = near ? (BaseObjectives.atConsole[key] ?? 0) + dt : 0
                BaseObjectives.atConsole[key] = t
                if t >= 3 {
                    BaseObjectives.set(key, 2); BaseObjectives.done += 1
                    if Items.has("greywall_dispatch") { let r = inventory.add(ItemStack(Items.id("greywall_dispatch"), 1)); if !r.isEmpty { dropItem(r) } }
                    money += 4000
                    sfx(.pageTurn, 0.8)
                    onToast?("You've taken the base's plans and its war chest (+\(Money.format(4000))). Read the dispatch for the next base")
                }
            }
            // The prisoner.
            if bits & 4 == 0, let s = mobs.mobs.first(where: { $0.villager?.role == "captive" && $0.health > 0 && Greywall.inside(site, $0.pos, pad: 2) }),
               simd_length(s.pos - pp) < 2.2,
               !mobs.mobs.contains(where: { $0.faction == Faction.greywall.rawValue && $0.health > 0 && simd_length($0.pos - s.pos) < 12 }) {
                BaseObjectives.set(key, 4); BaseObjectives.done += 1
                mobs.mobs.removeAll { $0 === s }
                money += 6000
                Honour.earn(self, 3, source: "outlaw", "a prisoner freed")
                sfx(.villagerYes, 0.8, at: s.pos)
                onToast?("\"Bless you. Here's what they didn't take.\" The scout slips out (+\(Money.format(6000)))")
            }
        }
    }
}
