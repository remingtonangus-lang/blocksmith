import Foundation
import simd

// The living war map (backlog C2; docs/status/war-map.md). Countries at war (Countries.wars) fight along a front line
// that moves day by day from a simulation, not from scripted events:
//   the front     for each war a line across the two countries' shared border, stored as an offset along the line
//                 between their seats (0 = the old border). Ground on a side of it belongs to that side.
//   a day of war  each side's strength (a seeded base, the towns it holds against the towns it lost, the player's
//                 part) sets the push; a seeded roll adds the fortunes of battle. The front moves by the push,
//                 never past 3/4 of the way to a seat, so capitals never fall to the AI.
//   towns         every known town of the two (not a capital, not the player's) follows the line: one more than 40
//                 blocks behind the front is held by the side that holds the ground there, and goes back when the
//                 front does (the 40 blocks stop a town flipping back and forth on a stalled front).
//   your part     killing a country's law, taking its towns and trading with it shift its strength (`might`), which
//                 fades a tenth a day; so do the towns you hand its enemy by taking them.
//   battles       the news reaches you as a toast when a front moves a long way near you; near an active front you
//                 hear distant guns and see smoke over the line.
//   the war table a taken Greywall base's map table opens the war report (WarFront.report) and the world map draws
//                 every active front in orange.
// Everything is a pure function of the world seed, the day and the saved state (Countries.Saved.fronts/might), so a
// save replays the same war.
enum WarFront {
    static let hysteresis: Float = 40
    static let pushScale: Float = 220            // blocks a day at a 100% strength advantage
    static let fortune: Float = 110              // the roll's range, blocks a day each way
    static let reach: Float = 0.75               // the front stops this share of the way to a seat
    static let newsAt: Float = 60                // a push this big near you is news
    static let mightFade: Float = 0.9

    // A war's geometry: `lo` is the country whose key sorts first; positive offsets are lo's gains.
    struct Line {
        let lo: Country, hi: Country
        let mid: V2, n: V2, along: V2
        let half: Float                          // half the distance between the seats
        func s(_ x: Float, _ z: Float) -> Float { simd_dot(V2(x, z) - mid, n) }
        func point(_ f: Float, _ t: Float) -> V2 { mid + n * f + along * t }
    }
    static func line(_ a: Country, _ b: Country) -> Line {
        let (lo, hi) = a.key < b.key ? (a, b) : (b, a)
        let d = V2(Float(hi.seatX - lo.seatX), Float(hi.seatZ - lo.seatZ))
        let len = max(1, simd_length(d))
        let n = d / len
        return Line(lo: lo, hi: hi, mid: V2(Float(lo.seatX + hi.seatX) / 2, Float(lo.seatZ + hi.seatZ) / 2), n: n,
                    along: V2(-n.y, n.x), half: len / 2)
    }

    static func front(_ k: String) -> Float { Countries.state.fronts?[k] ?? 0 }
    static func might(_ c: Country) -> Float { Countries.state.might?[c.key] ?? 0 }
    static func addMight(_ c: Country, _ by: Float) {
        var m = Countries.state.might ?? [:]
        m[c.key] = max(-60, min(60, (m[c.key] ?? 0) + by))
        Countries.state.might = m
    }

    // Towns a country holds now, less the ones it lost (known towns only: the ones you learnt).
    static func townBalance(_ c: Country, seed: UInt64) -> Int {
        var n = 0
        for (t, holder) in Countries.state.townOwner {
            if holder == c.key { n += 1 }
            else if let xz = Countries.state.towns[t], xz.count == 2, Countries.cellAt(xz[0], xz[1], seed: seed) == (c.cx, c.cz) { n -= 1 }
        }
        return n
    }
    static func strength(_ c: Country, seed: UInt64) -> Float {
        let base = 40 + Float(Countries.hash(c.cx, c.cz, seed, 0x3A9F) % 30)
        return max(10, base + 4 * Float(townBalance(c, seed: seed)) + might(c))
    }

    // One day of the war between a and b (Countries.simulateDay): the front moves, the towns follow it.
    static func day(_ g: Game, _ a: Country, _ b: Country, _ h: UInt64) {
        let L = line(a, b)
        let k = Countries.warKey(a.key, b.key)
        let seed = g.world.seed
        let sl = strength(L.lo, seed: seed), sh = strength(L.hi, seed: seed)
        let roll = (Float(h % 2001) / 1000 - 1) * fortune
        let push = pushScale * (sl - sh) / (sl + sh) + roll
        let was = front(k)
        let lim = L.half * reach
        let f = max(-lim, min(lim, was + push))
        var fr = Countries.state.fronts ?? [:]
        fr[k] = f
        Countries.state.fronts = fr
        Countries.state.battles = (Countries.state.battles ?? 0) + 1
        let moved = f - was
        if abs(moved) >= newsAt {
            let pp = V2(g.player.pos.x, g.player.pos.z)
            if simd_length(pp - L.mid) < 2 * L.half {
                let (win, lose) = moved > 0 ? (L.lo, L.hi) : (L.hi, L.lo)
                Countries.warNews += 1
                g.onToast?("Battle on the \(win.name)-\(lose.name) front: \(win.name) advances \(Int(abs(moved).rounded())) blocks")
            }
        }
        follow(g, L, f)
    }

    // Every known town of the two follows the line.
    static func follow(_ g: Game, _ L: Line, _ f: Float) {
        let seed = g.world.seed
        for (t, xz) in Countries.state.towns.sorted(by: { $0.key < $1.key }) where xz.count == 2 {
            let cell = Countries.cellAt(xz[0], xz[1], seed: seed)
            let home: Country
            if cell == (L.lo.cx, L.lo.cz) { home = L.lo } else if cell == (L.hi.cx, L.hi.cz) { home = L.hi } else { continue }
            guard !TownConquest.owns(t), !Countries.isCapital(g, town: t, of: home) else { continue }
            let s = L.s(Float(xz[0]), Float(xz[1]))
            let holderNow = Countries.state.townOwner[t].flatMap { Countries.byKey(g, $0) } ?? home
            guard holderNow == L.lo || holderNow == L.hi else { continue }   // held by a third country: not this war's
            var holder = holderNow
            if s < f - hysteresis { holder = L.lo } else if s > f + hysteresis { holder = L.hi }
            guard holder != holderNow else { continue }
            Countries.state.townOwner[t] = holder == home ? nil : holder.key
            Countries.warNews += 1
            g.onToast?(holder == home ? "\(home.name) took back \(t)" : "\(holder.name) took \(t) from \(holderNow.name)")
        }
    }

    // Once a day, before the wars: the player's part fades.
    static func fade() {
        guard var m = Countries.state.might else { return }
        for (k, v) in m { m[k] = abs(v * mightFade) < 0.5 ? nil : v * mightFade }
        Countries.state.might = m
    }

    // The player's part (Countries hooks): a country weakened or supplied, while it is at war.
    static func atWar(_ c: Country) -> Bool { Countries.state.wars.keys.contains { $0.split(separator: "|").contains(Substring(c.key)) } }
    static func lawKilled(_ c: Country) { if atWar(c) { addMight(c, -6) } }
    static func townTaken(_ c: Country) { if atWar(c) { addMight(c, -10) } }
    static func traded(_ c: Country) { if atWar(c) { addMight(c, 0.3) } }

    // MARK: Battles you can hear (every second, Countries.tick)

    static var nextGun: Double = 0
    static func ambience(_ g: Game) {
        guard g.clock >= nextGun, !Countries.state.wars.isEmpty else { return }
        let seed = g.world.seed
        let p = g.player.pos
        let here = Countries.at(g, p)
        for n in Countries.neighbours(g, here) {
            let k = Countries.warKey(here.key, n.key)
            guard Countries.state.wars[k] != nil else { continue }
            let L = line(here, n)
            let f = front(k)
            let d = abs(L.s(p.x, p.z) - f)
            guard d < 260 else { continue }
            let h = Townsfolk.mix(Int(g.clock * 10), Int(d), seed ^ 0xBA77)
            nextGun = g.clock + 3 + Double(h % 6)
            // A point on the line ahead of you along it, 60-200 blocks off.
            let t = simd_dot(V2(p.x, p.z) - L.mid, L.along) + (Float(h >> 8 % 280) - 140)
            let q = L.point(f, t)
            let gy = Float(g.world.gen.column(Int(floor(q.x)), Int(floor(q.y))).height + 2)
            let at = V3(q.x, gy, q.y)
            let far = simd_length(at - p)
            guard far > 40 else { continue }
            g.sfx((h >> 20) % 3 == 0 ? .explodeLarge : .shipCannon, max(0.15, min(0.9, 60 / far)), at: at)
            if g.world.isLoaded(Int(floor(q.x)), Int(floor(q.y))) { g.particles.smoke(at: at) }
            return
        }
        nextGun = g.clock + 5
    }

    // MARK: The world map (WorldMap, after the borders): each active front as an orange line.

    static func mapFronts(_ out: inout [HudLine], _ g: Game, x0: Float, y0: Float, cols: Int, rows: Int, px: Float, wx: Float, wz: Float, bpc: Int) {
        guard g.dim.dim == .overworld else { return }
        let seed = g.world.seed
        for k in Countries.state.wars.keys.sorted() {
            let ks = k.split(separator: "|").map(String.init)
            guard ks.count == 2, let a = Countries.byKey(g, ks[0]), let b = Countries.byKey(g, ks[1]) else { continue }
            let L = line(a, b)
            let f = front(k)
            let step = Float(max(8, bpc * 2))
            var t = -Float(Countries.cell)
            while t <= Float(Countries.cell) {
                let q = L.point(f, t)
                t += step
                let c = Countries.cellAt(Int(floor(q.x)), Int(floor(q.y)), seed: seed)
                guard c == (L.lo.cx, L.lo.cz) || c == (L.hi.cx, L.hi.cz) else { continue }
                guard let p = MapDraw.project(q.x, q.y, x0: x0, y0: y0, cols: cols, rows: rows, px: px, wx: wx, wz: wz, bpc: bpc) else { continue }
                out.append(HudLine(text: "", x: p.x - px, y: p.y - px, scale: 1, bg: V4(1, 0.55, 0.1, 0.95), box: V2(px * 2, px * 2)))
            }
        }
    }

    // MARK: The war table (a taken Greywall base's map table)

    static func report(_ g: Game) -> [String] {
        var pages: [String] = []
        let seed = g.world.seed
        let day = Int(g.time / DAY_LENGTH)
        for (k, started) in Countries.state.wars.sorted(by: { $0.key < $1.key }) {
            let ks = k.split(separator: "|").map(String.init)
            guard ks.count == 2, let a = Countries.byKey(g, ks[0]), let b = Countries.byKey(g, ks[1]) else { continue }
            let L = line(a, b)
            let f = front(k)
            let gain = Int(abs(f).rounded())
            let ahead = f > 0 ? L.lo : L.hi
            var text = "\(L.lo.name) against \(L.hi.name)\nDay \(max(1, day - started + 1)) of the war.\n\n"
            text += gain < 20 ? "The front holds the old border.\n" : "\(ahead.name) holds \(gain) blocks past the old border.\n"
            text += "Strength: \(L.lo.name) \(Int(strength(L.lo, seed: seed))), \(L.hi.name) \(Int(strength(L.hi, seed: seed))).\n"
            let lost = Countries.state.townOwner.filter { $0.value == L.lo.key || $0.value == L.hi.key }.keys.sorted()
            if !lost.isEmpty { text += "Taken: " + lost.prefix(4).map { "\($0) (\(Countries.byKey(g, Countries.state.townOwner[$0]!)!.name))" }.joined(separator: ", ") + ".\n" }
            let mine = [L.lo, L.hi].filter { abs(might($0)) >= 1 }
            if !mine.isEmpty { text += "Your part: " + mine.map { "\($0.name) \(might($0) > 0 ? "+" : "")\(Int(might($0).rounded()))" }.joined(separator: ", ") + "." }
            pages.append(text)
        }
        if pages.isEmpty { pages = ["No wars are being fought near this base.\n\nWhen neighbouring countries go to war, their front lines and the towns they take show here and on your map."] }
        return pages
    }

    static func openReport(_ g: Game) {
        guard Items.has("written_book") else { return }
        var st = ItemStack(Items.id("written_book"), 1)
        st.pages = report(g)
        st.label = "War Report"
        g.openMenu(BookMenu(game: g, stack: st, source: .hand(g.inventory.selected)))
    }
}
