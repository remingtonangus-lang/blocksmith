import Foundation

// Music loudness (Q2, scorecard "Mix": music about -16 LUFS, peaks under -1 dBFS, nothing clipped;
// `questcheck --musiclevels-only`, and part of every questcheck run). Every mood's piece (seed 12345) is rendered for
// 45 s through the game's own MusicRenderer, leveller included, and measured as tools/audiolevels.py does: BS.1770
// integrated loudness (K-weighting, -70 LUFS and -10 LU gates, 400 ms blocks every 100 ms) and sample peak.
enum MusicLevelTests {
    static func lufs(_ x: [Float], _ fs: Float) -> Float {
        func biquad(_ x: [Float], _ b0: Float, _ b1: Float, _ b2: Float, _ a1: Float, _ a2: Float) -> [Float] {
            var y = [Float](repeating: 0, count: x.count)
            var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
            for i in 0..<x.count {
                let o = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                x2 = x1; x1 = x[i]; y2 = y1; y1 = o; y[i] = o
            }
            return y
        }
        var f0: Float = 1681.9745, q: Float = 0.70717524
        var k = tanf(.pi * f0 / fs)
        let vh = powf(10, 3.9998438 / 20), vb = powf(vh, 0.49966677)
        var a0 = 1 + k / q + k * k
        var y = biquad(x, (vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0)
        f0 = 38.135471; q = 0.50032704
        k = tanf(.pi * f0 / fs); a0 = 1 + k / q + k * k
        y = biquad(y, 1, -2, 1, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0)
        let blk = Int(0.4 * fs), hop = Int(0.1 * fs)
        guard y.count >= blk else { return -99 }
        var ms: [Float] = []
        var i = 0
        while i + blk <= y.count {
            var s: Float = 0
            for j in i..<(i + blk) { s += y[j] * y[j] }
            ms.append(s / Float(blk)); i += hop
        }
        func L(_ m: Float) -> Float { m > 0 ? -0.691 + 10 * log10f(m) : -99 }
        var g = ms.filter { L($0) > -70 }
        guard !g.isEmpty else { return -99 }
        let rel = L(g.reduce(0, +) / Float(g.count)) - 10
        g = g.filter { L($0) > rel }
        return L(g.reduce(0, +) / Float(g.count))
    }

    static func run(check: (Bool, String) -> Void) {
        let fs = Float(SoundBank.rate)
        var off: [String] = [], loud: [String] = [], rows: [String] = []
        var lo: Float = 0, hi: Float = -99
        for mood in MusicMood.allCases {
            let x = MusicRenderer.renderMono(Composer.compose(mood, seed: 12345), seconds: 45)
            let L = lufs(x, fs)
            let peak = x.reduce(0) { max($0, abs($1)) }
            let pdb = peak > 0 ? 20 * log10f(peak) : -99
            let clipped = x.filter { abs($0) >= 0.999 }.count
            lo = min(lo, L); hi = max(hi, L)
            rows.append("\(mood.rawValue) " + String(format: "%.1f LUFS %.1f dBFS", L, pdb))
            if !(L >= -18 && L <= -14) { off.append("\(mood.rawValue) " + String(format: "%.1f", L)) }
            if pdb > -1 || clipped > 0 { loud.append("\(mood.rawValue) " + String(format: "%.1f dBFS (%d clipped)", pdb, clipped)) }
        }
        print("music levels: " + rows.joined(separator: ", "))
        check(off.isEmpty, String(format: "music levels: every piece within -16 +-2 LUFS (%d pieces, %.1f to %.1f)", MusicMood.allCases.count, lo, hi)
              + (off.isEmpty ? "" : "; off: " + off.joined(separator: ", ")))
        check(loud.isEmpty, "music levels: no piece peaks over -1 dBFS or clips\(loud.isEmpty ? "" : ": " + loud.joined(separator: ", "))")

        // Voice coverage (scorecard "Audio coverage"): every creature and war machine has a voice (only the crystal,
        // minecart, boat and armour stand are silent), and each war machine's idle, hit and death render audibly.
        let silent = MobKind.allCases.filter { MobVoice.profile($0).family == .silent && ![.endCrystal, .minecart, .boat, .armorStand].contains($0) }
        check(silent.isEmpty, "sound coverage: every creature and vehicle kind has a voice or engine (\(silent.isEmpty ? "none silent" : "silent: " + silent.map { "\($0)" }.joined(separator: ", ")))")
        var weak: [String] = []
        for k in MobKind.allCases where MobVoice.profile(k).family == .engine {
            for s in MobSound.allCases {
                let x = SoundBank.render(.mob(k, s), variant: 0)
                let peak = x.reduce(0) { max($0, abs($1)) }
                if x.count < 2000 || peak < 0.05 || !peak.isFinite { weak.append("\(k) \(s.name) " + String(format: "(%.2f s, peak %.2f)", Float(x.count) / fs, peak)) }
            }
        }
        check(weak.isEmpty, "sound coverage: war machines idle, take hits and die audibly\(weak.isEmpty ? "" : ": " + weak.joined(separator: ", "))")
    }
}
