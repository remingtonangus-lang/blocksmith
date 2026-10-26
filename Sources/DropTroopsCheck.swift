import Foundation
import simd

// P460 (Remington, Oct 25 16:37-16:38 by Capital City, a Capital Dropship landing troops round him: "They're just doing
// stupid shit"; "These guys didn't do anything. Capital troops in particular are not working... at all, really"):
// questcheck --droptroops calls a Capital Dropship down 24 blocks off with him standing in the open in survival, runs
// the whole game for 60 s and reports what each trooper it lands does: how near it comes, whether it sees him, the
// rounds it fires and the damage that reaches him.
enum DropTroopsCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let home = g.player.pos
        _ = w.loadSync(center: home, radius: 5)
        let surv0 = g.survival
        defer { g.survival = surv0 }
        g.survival = true; g.alive = true; g.health = 20
        let stand = V3(home.x, Float(w.topY(Int(floor(home.x)), Int(floor(home.z))) + 1), home.z)
        g.player.pos = stand; g.player.flying = false
        let n0 = w.ships.list.count
        guard w.ships.callDropship(faction: .steelhold, from: stand + V3(-90, 40, 0), to: stand + V3(24, 0, 0), game: g, sync: true),
              let d = w.ships.list.dropFirst(n0).first(where: { $0.role == "dropship" && $0.parent == nil }),
              let st = w.ships.capState[d.id] else { check(false, "droptroops: a Capital Dropship comes"); return }
        var t: Float = 0, taken: Float = 0, firstHit: Float = -1, landedAt: Float = -1
        var fired: [ObjectIdentifier: Int] = [:], mags: [ObjectIdentifier: Int] = [:], seen: [ObjectIdentifier: Int] = [:]
        var nearest: [ObjectIdentifier: Float] = [:]
        var log: [String] = []
        while t < 60 {
            g.health = 20; g.alive = true
            g.tick(0.05)
            t += 0.05
            if g.health < 20 { taken += Float(20 - g.health); if firstHit < 0 { firstHit = t } }
            g.player.pos = stand; g.player.vel = .zero
            if landedAt < 0 && !st.troops.isEmpty { landedAt = t }
            for m in st.troops where m.health > 0 {
                let k = ObjectIdentifier(m), b = m.soldierBrain
                if let old = mags[k], b.mag < old { fired[k, default: 0] += old - b.mag }
                mags[k] = b.mag
                if b.sees { seen[k, default: 0] += 1 }
                nearest[k] = min(nearest[k] ?? .infinity, simd_length(m.pos - stand))
            }
            if Int((t * 20).rounded()) % 100 == 0 {
                let row = st.troops.map { m -> String in
                    let b = m.soldierBrain
                    return String(format: "%@ %.0f off%@%@%@ mag %d%@", m.kind.key, simd_length(m.pos - stand), m.aggro ? " aggro" : "",
                                  b.sees ? " sees" : "", b.foe != nil ? " foe" : "", b.mag, m.health <= 0 ? " dead" : "")
                }
                log.append(String(format: "%.0f s: ship phase %d at %.0f off, %.0f up; ", t, st.phase, simd_length(V2(d.pos.x - stand.x, d.pos.z - stand.z)), d.pos.y - stand.y)
                           + row.joined(separator: ", "))
            }
        }
        for x in w.ships.list where x === d || x.parent === d { w.ships.remove(x) }
        w.ships.capState.removeValue(forKey: d.id)
        let rounds = fired.values.reduce(0, +)
        let per = st.troops.map { m -> String in
            let k = ObjectIdentifier(m)
            return String(format: "%@: %d rounds, saw him %d ticks, came to %.0f", m.kind.key, fired[k] ?? 0, seen[k] ?? 0, nearest[k] ?? -1)
        }
        for m in st.troops { m.health = -1 }
        check(st.troops.count >= 3 && rounds >= 20 && taken > 0,
              String(format: "droptroops: %d troops landed (first at %.0f s); %d rounds at him in 60 s, %.0f damage reached him (first at %.0f s). ",
                     st.troops.count, landedAt, rounds, taken, firstHit) + per.joined(separator: "; ") + "\n  " + log.joined(separator: "\n  "))
    }
}
