import Foundation
#if canImport(AVFoundation)
import AVFoundation

// P359 (a): the Sunderfall soundtrack on the Mac. Two player nodes crossfade; each track streams from disk
// (scheduleFile reads the AAC file as it plays, never the whole song at once). Soundtrack.swift picks the tracks.
final class MacTrackDeck: TrackDeck {
    final class Deck {
        let node = AVAudioPlayerNode()
        var name: String?
        var gain: Float = 0, target: Float = 0, rate: Float = 1   // fade envelope (rate: per second)
        var trackGain: Float = 1
        var generation = 0
        var ended = false
    }
    private unowned let engine: AVAudioEngine
    private let decks = [Deck(), Deck()]
    private var files: [String: URL] = [:]
    var volume: Float = 1

    init(engine: AVAudioEngine, format: AVAudioFormat) {
        self.engine = engine
        for d in decks {
            engine.attach(d.node)
            engine.connect(d.node, to: engine.mainMixerNode, format: format)
            d.node.volume = 0
        }
        let fm = FileManager.default
        for dir in Soundtrack.folders() {
            for n in Soundtrack.tracks where files[n] == nil {
                let u = URL(fileURLWithPath: dir + "/" + n + ".m4a")
                if fm.fileExists(atPath: u.path) { files[n] = u }
            }
        }
    }

    var available: Bool { !files.isEmpty }

    var current: String? {
        for d in decks where d.target > 0 && !d.ended { return d.name }
        return nil
    }

    func play(_ name: String, gain: Float, fade: Float) {
        guard let url = files[name], let f = try? AVAudioFile(forReading: url) else { return }
        // The quieter deck takes the new track; the other fades out.
        let d = decks[0].gain <= decks[1].gain ? decks[0] : decks[1]
        let other = d === decks[0] ? decks[1] : decks[0]
        other.target = 0
        other.rate = 1 / max(0.1, fade)
        d.generation += 1
        let gen = d.generation
        if d.node.isPlaying { d.node.stop() }
        engine.disconnectNodeOutput(d.node)
        engine.connect(d.node, to: engine.mainMixerNode, format: f.processingFormat)
        d.name = name
        d.gain = 0
        d.target = 1
        d.rate = 1 / max(0.1, fade)
        d.trackGain = gain
        d.ended = false
        d.node.volume = 0
        d.node.scheduleFile(f, at: nil, completionCallbackType: .dataPlayedBack) { [weak d] _ in
            DispatchQueue.main.async { if let d, d.generation == gen { d.ended = true; d.target = 0 } }
        }
        if engine.isRunning { d.node.play() }
    }

    func stop(fade: Float) {
        for d in decks where d.target > 0 { d.target = 0; d.rate = 1 / max(0.1, fade) }
    }

    func update(_ dt: Float) {
        for d in decks {
            if d.gain < d.target { d.gain = min(d.target, d.gain + d.rate * dt) }
            else if d.gain > d.target { d.gain = max(d.target, d.gain - d.rate * dt) }
            // Equal-power crossfade curve on the linear envelope.
            let g = sinf(d.gain * .pi / 2)
            d.node.volume = g * d.trackGain * volume
            if d.gain <= 0 && d.target <= 0 && d.name != nil {
                d.generation += 1
                if d.node.isPlaying { d.node.stop() }
                d.name = nil
            }
        }
    }

    // The output device changed (the engine restarted): the scheduled files are gone; the director starts again.
    func restart() {
        for d in decks { d.generation += 1; d.node.stop(); d.name = nil; d.gain = 0; d.target = 0 }
    }
}
#endif
