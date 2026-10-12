import Foundation
import simd

// The living war map checks (backlog C2; part of `questcheck --towns-only` through CountriesTests):
//   stable    over 90 days of an even war the front moves (battles are fought) but a town by the line changes hands
//             only a few times, never back and forth on consecutive days
//   bounded   the front never passes 3/4 of the way to either seat (capitals don't fall to the AI)
//   tipping   the same war from the same day with the player's part on one side ends with that side ahead
//   replay    the same seed, state and days give the same front (a save replays the same war); fronts and might
//             survive a save
//   shown     the world map draws the front; a taken base's war table reports the war
enum WarFrontTests {
    static func run(_ g: Game, _ a: Country, _ n: Country, town: String, check: (Bool, String) -> Void) {
        let k = Countries.warKey(a.key, n.key)
        let L = WarFront.line(a, n)
        let saved = Countries.state
        defer { Countries.state = saved }
        func reset(might: [String: Float]) {
            Countries.state.wars = [k: 1]
            Countries.state.fronts = [:]
            Countries.state.might = might
            Countries.state.townOwner = [:]
        }
        func war(days: Int, salt: UInt64, keepMight: Bool = false) -> (fronts: [Float], flips: Int, flipBack: Int) {
            var fronts: [Float] = [], flips = 0, flipBack = 0
            var owner = Countries.ofKnown(g, town: town)
            var lastFlip = -10
            for d in 0..<days {
                let h = Townsfolk.mix(d, Int(salt & 0xFFFF), g.world.seed ^ salt)
                if !keepMight { WarFront.fade() }
                WarFront.day(g, a, n, h)
                fronts.append(WarFront.front(k))
                let o = Countries.ofKnown(g, town: town)
                if o != owner { flips += 1; if d - lastFlip <= 1 { flipBack += 1 }; lastFlip = d; owner = o }
            }
            return (fronts, flips, flipBack)
        }

        // An even war (no part played), the frontier town 60 blocks inside a.
        var tx = Countries.state.towns[town] ?? [0, 0]
        let tp = L.point(0, 0) + L.n * (L.lo == a ? -60 : 60)
        tx = [Int(tp.x), Int(tp.y)]
        Countries.state.towns[town] = tx
        reset(might: [:])
        let even = war(days: 90, salt: 0xE7E4)
        let span = (even.fronts.max() ?? 0) - (even.fronts.min() ?? 0)
        let lim = L.half * WarFront.reach
        let bounded = even.fronts.allSatisfy { abs($0) <= lim + 0.01 }
        check(span > 150 && even.flips <= 12 && even.flipBack == 0 && bounded,
              String(format: "warfront: over 90 days the front ranges %.0f blocks (within %.0f of the border: %@), the town by it changes hands %d times, %d of them straight back",
                     span, lim, bounded ? "yes" : "no", even.flips, even.flipBack))

        // Tipping: the player's part on each side in turn; the helped side ends ahead.
        reset(might: [a.key: 40, n.key: -40])
        let forA = war(days: 20, salt: 0x71B, keepMight: true).fronts.last ?? 0
        reset(might: [n.key: 40, a.key: -40])
        let forN = war(days: 20, salt: 0x71B, keepMight: true).fronts.last ?? 0
        let aSign: Float = L.lo == a ? 1 : -1                  // positive fronts are lo's gains
        check(forA * aSign > 100 && forN * aSign < -100,
              String(format: "warfront: the same 20 days end %.0f blocks into %@'s favour with the player on its side, %.0f into %@'s with the player on the other",
                     abs(forA), a.name, abs(forN), n.name))

        // Replay: the same days from the same state give the same front; fronts and might survive a save.
        reset(might: [a.key: 12])
        let r1 = war(days: 15, salt: 0x5EED, keepMight: true).fronts
        reset(might: [a.key: 12])
        let r2 = war(days: 15, salt: 0x5EED, keepMight: true).fronts
        var d: [String: String] = [:]
        Countries.save(&d)
        let f0 = WarFront.front(k), m0 = Countries.state.might
        Countries.state.fronts = nil; Countries.state.might = nil
        Countries.load(d)
        check(r1 == r2 && WarFront.front(k) == f0 && Countries.state.might == m0,
              String(format: "warfront: the same days replay the same front (%.0f), and the front and the player's part survive a save", f0))

        // Shown: the map's orange line and the war table's report.
        var lines: [HudLine] = []
        let mid = L.point(f0, 0)
        WarFront.mapFronts(&lines, g, x0: 0, y0: 0, cols: 152, rows: 82, px: 2, wx: mid.x, wz: mid.y, bpc: 16)
        let report = WarFront.report(g)
        let names = report.first.map { $0.contains(a.name) && $0.contains(n.name) && $0.contains("Strength") } ?? false
        check(lines.count > 20 && names, "warfront: the world map draws the front (\(lines.count) marks); the war table reports it ('\(report.first?.prefix(60) ?? "")')")
    }
}
