import Foundation
import simd

// P460 (Remington, Oct 25 17:08, overrun by the Capital's band in the jungle: "there should be a giant crawler"):
// questcheck --huntcrawler starts the Reckoning with one Capital band 200 blocks east of him and runs the whole game for
// 60 s with him standing in the open: the band should bring a Capital Crawler in behind it, driving on him.
enum HuntCrawlerCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let mobs0 = g.mobs.mobs, victory0 = g.ashVictory, survival0 = g.survival, diff0 = g.difficulty
        let pos0 = g.player.pos, fly0 = g.player.flying, rd0 = g.world.renderDistance
        g.world.renderDistance = 8                          // (the game's own active distance: the crawler comes in at its edge)
        defer {
            g.world.renderDistance = rd0
            g.mobs.mobs = mobs0; g.ashVictory = victory0; g.survival = survival0; g.difficulty = diff0
            g.alive = true; Reckoning.reset(); g.player.pos = pos0; g.player.flying = fly0
        }
        let w = g.world
        _ = w.loadSync(center: pos0, radius: 5)
        let px = Int(floor(pos0.x)), pz = Int(floor(pos0.z))
        let stand = V3(pos0.x, Float(w.topY(px, pz) + 1), pos0.z)
        g.player.pos = stand; g.player.flying = false
        g.mobs.mobs = []; g.ashVictory = true; g.survival = true; g.difficulty = 2; g.alive = true
        Reckoning.own(g)                    // (the hunt is this game's: a first tick for another would reset it)
        Reckoning.reset()
        Reckoning.stage = 2
        let p = V2(stand.x, stand.z)
        Reckoning.hunts = [Reckoning.Hunt(side: .capital, pos: p + V2(200, 0), waiting: Reckoning.Side.capital.roster)]
        var t: Float = 0, first: Float = -1, d0: Float = -1, nearest = Float.infinity
        var log: [String] = []
        while t < 60 {
            g.health = 20; g.alive = true
            g.tick(0.05)
            t += 0.05
            g.player.pos = stand; g.player.vel = .zero
            if first < 0 && Int((t * 20).rounded()) % 200 == 0 {
                let h = Reckoning.hunts.first
                log.append(String(format: "%.0f s: stage %d, band %.0f off, spot %@, capitals %@", t, Reckoning.stage,
                                  h.map { simd_length($0.pos - p) } ?? -1, Reckoning.crawlerAt.map { "\(Int($0.x)),\(Int($0.y))" } ?? "none",
                                  w.ships.capitals.compactMap { $0.role }.joined(separator: "/")))
            }
            guard let c = Reckoning.crawlerAt, let s = Reckoning.huntCrawler(g, c) else { continue }
            let d = simd_length(V2(s.pos.x, s.pos.z) - p)
            if first < 0 { first = t; d0 = d }
            nearest = min(nearest, d)
            if Int((t * 20).rounded()) % 200 == 0 {
                log.append(String(format: "%.0f s: %@ %.0f off%@", t, s.name, d, w.ships.capState[s.id]?.target != nil ? ", has him in sight" : ""))
            }
        }
        let cr = Reckoning.crawlerAt.flatMap { Reckoning.huntCrawler(g, $0) }
        let name = cr?.name ?? "none"
        if let s = cr { for x in w.ships.list where x === s || x.root === s { w.ships.remove(x) }; w.ships.capState.removeValue(forKey: s.id) }
        check(cr?.factionValue == .steelhold && first >= 0 && nearest < d0 - 40,
              String(format: "huntcrawler: the Capital band brings %@ (in at %.0f s, %.0f blocks off), it drives on him to %.0f; ", name, first, d0, nearest)
                + log.joined(separator: "; "))
    }
}
