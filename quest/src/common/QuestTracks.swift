import Foundation

// P359 (a): the Sunderfall soundtrack on the Quest. Two decks crossfade in the software mixer; each deck's track is
// decoded a block at a time on a background queue (Android: AMediaExtractor + AMediaCodec over the APK's
// assets/music, AndroidMain's MediaTrackDecoder) and resampled to the mixer's rate into a ring, so a song is never
// held whole in memory. Soundtrack.swift picks the tracks. Off Android (the Linux host checks) there is no decoder and
// the composer plays.

// Decodes one compressed track to interleaved stereo float frames at its own rate.
protocol TrackDecoder: AnyObject {
    var sampleRate: Int { get }
    // Up to `frames` stereo frames into `out` (interleaved); 0 at the end of the track.
    func read(_ out: inout [Float], frames: Int) -> Int
}

final class QuestTrackDeck: TrackDeck {
    // Set by the Android entry point: opens assets/music/<name>.m4a; `names` lists the tracks there.
    static var open: ((String) -> TrackDecoder?)?
    static var names: Set<String> = []

    final class Deck {
        var name: String?
        var decoder: TrackDecoder?
        var ring: [Float]
        var readPos = 0, writePos = 0, filled = 0
        var eof = false                 // the decoder is done (the ring may still hold the tail)
        var gain: Float = 0, target: Float = 0, step: Float = 0      // fade envelope, per output frame
        var trackGain: Float = 1
        var generation = 0
        var srcPos: Double = 0          // resampler: fractional read position in decoded frames
        var prevL: Float = 0, prevR: Float = 0
        init(_ cap: Int) { ring = [Float](repeating: 0, count: cap * 2) }
    }

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "blocksmith.tracks", qos: .userInitiated)
    private let capacity = 32768                    // frames per ring (~0.75 s)
    private let decks: [Deck]
    private var decoded = [Float](repeating: 0, count: 4096 * 2)
    private var running = false
    private let outRate = Double(SoundEngine.rate)
    var volume: Float = 1
    private var mixVolume: Float = 0

    init() {
        decks = [Deck(32768), Deck(32768)]
    }

    var available: Bool { QuestTrackDeck.open != nil && !QuestTrackDeck.names.isEmpty }

    var current: String? {
        lock.lock(); defer { lock.unlock() }
        for d in decks where d.target > 0 && !(d.eof && d.filled == 0) { return d.name }
        return nil
    }

    func play(_ name: String, gain: Float, fade: Float) {
        guard QuestTrackDeck.names.contains(name) else { return }
        let outFrames = Float(outRate) * max(0.1, fade)
        lock.lock()
        let d = decks[0].gain <= decks[1].gain ? decks[0] : decks[1]
        let other = d === decks[0] ? decks[1] : decks[0]
        other.target = 0
        other.step = 1 / outFrames
        d.generation += 1
        let gen = d.generation
        d.name = name
        let old = d.decoder
        d.decoder = nil
        d.eof = false
        d.readPos = 0; d.writePos = 0; d.filled = 0
        d.gain = 0; d.target = 1; d.step = 1 / outFrames
        d.trackGain = gain
        d.srcPos = 0
        lock.unlock()
        // Opening the asset and the codec can take a moment: off the game thread (the old decoder goes there too).
        queue.async { [weak self] in
            _ = old
            let dec = QuestTrackDeck.open?(name)
            guard let self else { return }
            self.lock.lock()
            if d.generation == gen { d.decoder = dec; if dec == nil { d.eof = true } }
            self.lock.unlock()
        }
        if !running {
            running = true
            queue.async { [weak self] in self?.pump() }
        }
    }

    func stop(fade: Float) {
        lock.lock()
        for d in decks where d.target > 0 { d.target = 0; d.step = 1 / (Float(outRate) * max(0.1, fade)) }
        lock.unlock()
    }

    func update(_ dt: Float) {}

    // Keeps each live deck's ring full: decode a block, resample it (linear) to the mixer's rate.
    private func pump() {
        var worked = false
        for d in decks {
            lock.lock()
            var drop: TrackDecoder? = nil           // a freed deck's decoder is released here, never on the audio thread
            if d.name == nil { drop = d.decoder; d.decoder = nil }
            let gen = d.generation
            let dec = d.decoder
            let space = capacity - d.filled
            let live = d.name != nil && !d.eof
            lock.unlock()
            drop = nil
            guard live, let dec, space >= 4096 else { continue }
            let got = dec.read(&decoded, frames: 2048)
            lock.lock()
            if d.generation != gen { lock.unlock(); continue }
            if got == 0 { d.eof = true; lock.unlock(); continue }
            worked = true
            let ratio = Double(dec.sampleRate) / outRate
            // Resample: output frames while the read position stays inside this block (prev = the frame before it).
            var pos = d.srcPos
            while pos < Double(got) {
                let i = Int(pos), f = Float(pos - Double(i))
                let l0 = i == 0 ? d.prevL : decoded[(i - 1) * 2], r0 = i == 0 ? d.prevR : decoded[(i - 1) * 2 + 1]
                let l1 = decoded[i * 2], r1 = decoded[i * 2 + 1]
                let j = d.writePos
                d.ring[j * 2] = l0 + (l1 - l0) * f
                d.ring[j * 2 + 1] = r0 + (r1 - r0) * f
                d.writePos = (j + 1) % capacity
                d.filled += 1
                pos += ratio
            }
            d.srcPos = pos - Double(got)
            d.prevL = decoded[(got - 1) * 2]; d.prevR = decoded[(got - 1) * 2 + 1]
            lock.unlock()
        }
        queue.asyncAfter(deadline: .now() + (worked ? 0.002 : 0.03)) { [weak self] in self?.pump() }
    }

    // Audio thread: adds both decks into the music bus (silence on underrun).
    func mix(into L: inout [Float], _ R: inout [Float], _ n: Int) {
        lock.lock()
        let vt = volume
        for d in decks where d.name != nil {
            let take = min(n, d.filled)
            for i in 0..<take {
                if d.gain < d.target { d.gain = min(d.target, d.gain + d.step) } else if d.gain > d.target { d.gain = max(d.target, d.gain - d.step) }
                mixVolume += (vt - mixVolume) * 0.0005
                let g = sinf(d.gain * .pi / 2) * d.trackGain * mixVolume
                let j = (d.readPos + i) % capacity
                L[i] += d.ring[j * 2] * g
                R[i] += d.ring[j * 2 + 1] * g
            }
            d.readPos = (d.readPos + take) % capacity
            d.filled -= take
            // Faded out, or played to the end: the deck is free (the pump drops its decoder).
            if (d.gain <= 0 && d.target <= 0) || (d.eof && d.filled == 0) {
                d.generation += 1
                d.name = nil
                d.target = 0
                d.gain = 0
            }
        }
        lock.unlock()
    }
}
