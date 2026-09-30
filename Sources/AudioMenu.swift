import Foundation

// The Audio page of the options menu: one slider per sound category (A / X step it up and down,
// the mouse clicks step forward / right-click back), plus a test sound.
extension PauseMenu {
    static let volumeSteps: [Float] = [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1]

    func audioRows() -> [(String, String)] {
        var r: [(String, String)] = []
        for c in SoundCategory.allCases {
            let v = Int((AudioSettings.volume(c) * 100).rounded())
            r.append(("\(c.label): \(v)%", "vol:\(c.rawValue)"))
        }
        r.append(("Subtitles: \(AudioSettings.subtitles ? "On" : "Off")", "audio_subs"))
        r.append(("Test Sound", "audio_test"))
        r.append(("Done", "audio_back"))
        return r
    }

    func audioAct(_ id: String, back: Bool) {
        let g = game
        if id == "audio_subs" { AudioSettings.subtitles.toggle(); return }
        if id == "audio_test" {
            g.sfx(.mob(.cow, .ambient), 1, at: g.player.eye + g.player.look * 4)
            return
        }
        guard id.hasPrefix("vol:"), let raw = Int(id.dropFirst(4)), let c = SoundCategory(rawValue: raw) else { return }
        let steps = PauseMenu.volumeSteps
        let cur = AudioSettings.volume(c)
        var i = 0
        for (k, s) in steps.enumerated() where abs(s - cur) < abs(steps[i] - cur) { i = k }
        i = (i + (back ? steps.count - 1 : 1)) % steps.count
        let v = steps[i]
        AudioSettings.set(c, v)
        if c == .master { g.volumeSetting = v }
        if c == .music { g.musicVolume = v }
    }
}
