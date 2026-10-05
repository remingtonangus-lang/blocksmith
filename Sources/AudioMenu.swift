import Foundation

// The Audio tab of the options menu: one slider per sound category (A / X step it up and down,
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
        // Your own music folder (CustomMusic.swift).
        let st = Settings.shared
        r.append(("Soundtrack: \(["Built-in", "My Music", "Mixed"][max(0, min(2, st.musicSource))])", "audio_music_src"))
        r.append(("My Music: \(game.sound?.custom?.summary ?? "no audio")", "audio_music_folder"))
        r.append(("Shuffle: \(st.musicShuffle ? "On" : "Off")", "audio_music_shuffle"))
        r.append(("My Music Volume: \(Int((st.customMusicVolume * 100).rounded()))%", "audio_music_vol"))
        r.append(("Skip Track", "audio_music_skip"))
        r.append(("Test Sound", "audio_test"))
        return r
    }

    func audioAct(_ id: String, back: Bool) {
        let g = game
        if id == "audio_subs" { AudioSettings.subtitles.toggle(); return }
        let st = Settings.shared
        switch id {
        case "audio_music_src":
            st.musicSource = (st.musicSource + (back ? 2 : 1)) % 3
            if st.musicSource != 0, g.sound?.custom?.available == false {
                g.onToast?("Put mp3, m4a, wav or aiff files in Application Support/Blocksmith/Music")
            }
            return
        case "audio_music_folder": g.sound?.custom?.scan(force: true); return
        case "audio_music_shuffle": st.musicShuffle.toggle(); return
        case "audio_music_vol":
            let steps: [Float] = [0.25, 0.5, 0.75, 1]
            let k = steps.firstIndex(where: { abs($0 - st.customMusicVolume) < 0.01 }) ?? 3
            st.customMusicVolume = steps[(k + (back ? steps.count - 1 : 1)) % steps.count]
            return
        case "audio_music_skip": g.skipMusicTrack(); return
        default: break
        }
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
