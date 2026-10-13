import Foundation
import simd

// Faction reputation (backlog O3). Towns already remember you (Honour.swift) and so do countries (Countries.swift
// standing); this adds the armed factions: the Capital, Greywall Command, the Meridian Navy, the Stormwarden Fleet and
// the Ironback Legion. Each holds a standing from -100 to 100 (saved with the world extras, "factionRep"), starting
// at -30: wary, their soldiers fire on sight, as they always have.
//   costs     killing one of its soldiers -6 (an officer -10), wrecking a deck gun -10, taking a Greywall base -30
//   gains     killing a soldier of a faction at war with it +3 (every other armed faction is): fight their enemies
//   ally      at 30 or more its soldiers hold fire unless you hurt one of them in the last minute, and its posts
//             let you pass
//   hunted    at -60 or less it puts a price on you: every 8 minutes in the open overworld a dropship of its hunters
//             lands near you (never inside a base, never at sea)
// Crossing a line says so in a toast.
enum FactionRep {
    static let tracked: [Faction] = [.steelhold, .greywall, .meridian, .stormwarden, .ironback]
    static let start: Float = -30
    static let allyAt: Float = 30, huntedAt: Float = -60
    static let hunterEvery: Double = 480
    static var rep: [Int: Float] = [:]
    static var nextHunters: Double = 0

    static func of(_ f: Faction) -> Float { rep[f.rawValue] ?? start }
    static func label(_ v: Float) -> String { v >= allyAt ? "an ally" : (v <= huntedAt ? "hunted" : (v > 0 ? "tolerated" : "wary of you")) }

    static func encode() -> String {
        tracked.map { "\($0.rawValue):\(Int(of($0).rounded()))" }.joined(separator: ";")
    }
    static func decode(_ s: String) {
        rep = [:]
        for p in s.split(separator: ";") {
            let kv = p.split(separator: ":")
            if kv.count == 2, let k = Int(kv[0]), let v = Float(kv[1]) { rep[k] = max(-100, min(100, v)) }
        }
        nextHunters = 0
    }
}

extension Game {
    // A change of standing, with a toast when it crosses a line.
    func changeRep(_ f: Faction, _ d: Float) {
        guard FactionRep.tracked.contains(f), d != 0 else { return }
        let old = FactionRep.of(f), now = max(-100, min(100, old + d))
        FactionRep.rep[f.rawValue] = now
        let lines: [Float] = [FactionRep.allyAt, FactionRep.huntedAt]
        for l in lines where (old < l) != (now < l) {
            onToast?("\(f.name) now counts you \(FactionRep.label(now)).")
        }
    }

    // A soldier the player killed (Game.soldierDied).
    func repSoldierKilled(_ m: Mob) {
        guard m.killedByPlayer, !m.hired else { return }
        let f = m.factionValue
        guard FactionRep.tracked.contains(f) else { return }
        changeRep(f, m.kind == .deckGun ? -10 : (m.kind == .soldierOfficer ? -10 : -6))
        for o in FactionRep.tracked where o != f { changeRep(o, 3) }
    }

    // An ally's soldier holds fire unless the player hurt one of them in the last minute.
    func repAllied(_ m: Mob) -> Bool {
        let f = m.factionValue
        guard FactionRep.tracked.contains(f), FactionRep.of(f) >= FactionRep.allyAt else { return false }
        return clock - m.playerHurtAt > 60
    }

    // Hunters (once a second is plenty: called from the HUD tick).
    func repHuntersTick() {
        guard survival, alive, dim.dim == .overworld, !Reckoning.won else { return }
        if FactionRep.nextHunters == 0 { FactionRep.nextHunters = clock + FactionRep.hunterEvery; return }
        guard clock >= FactionRep.nextHunters else { return }
        FactionRep.nextHunters = clock + FactionRep.hunterEvery
        guard let f = FactionRep.tracked.filter({ FactionRep.of($0) <= FactionRep.huntedAt }).min(by: { FactionRep.of($0) < FactionRep.of($1) }) else { return }
        let pp = player.pos
        guard !bases.inAnyBase(pp), world.ships.pilot == nil else { return }
        // Dry ground a little way off.
        var spot: V3?
        for k in 0..<8 {
            let a = Float(k) * .pi / 4, x = pp.x + cosf(a) * 14, z = pp.z + sinf(a) * 14
            let ix = Int(floor(x)), iz = Int(floor(z))
            guard world.isLoaded(ix, iz) else { continue }
            let y = world.topY(ix, iz)
            guard y > 0, !Blocks.isLiquid(world.block(ix, y, iz)) else { continue }
            spot = V3(x, Float(y + 1), z); break
        }
        guard let land = spot else { return }
        let from = pp + V3(260, 70, 120)
        world.ships.callDropship(faction: f, from: from, to: land, game: self, troops: 4)
        onToast?("\(f.name) has put a price on you: a dropship of hunters is coming!")
    }
}
