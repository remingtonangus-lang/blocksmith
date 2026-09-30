import Foundation
import AVFoundation

// Procedural background music. A Composer writes a MusicScore (notes with instrument, pitch, length,
// velocity, pan) for a mood; MusicRenderer turns it into stereo audio block by block; MusicStream feeds
// those blocks to an AVAudioPlayerNode from a background queue. Everything here is original and seeded.

enum Inst: Int { case pad, pluck, harp, bell, bass, flute, organ, shimmer, drone, kick, tom, shaker, thud, metal }

struct MusicNote {
    var t: Float          // seconds
    var dur: Float        // seconds until release
    var inst: Inst
    var midi: Float
    var vel: Float        // 0...1
    var pan: Float        // -1...1
}

enum MusicMood: String, CaseIterable {
    case title, day, night, underground, underwater, ember, hollow, creative, boss, rain, snow, desert, ocean, grove
    var label: String {
        switch self {
        case .title: return "Title"
        case .day: return "Overworld Day"
        case .night: return "Overworld Night"
        case .underground: return "Underground"
        case .underwater: return "Underwater"
        case .ember: return "Emberdeep"
        case .hollow: return "The Hollow"
        case .creative: return "Creative"
        case .boss: return "Boss"
        case .rain: return "Rain"
        case .snow: return "Snowfields"
        case .desert: return "Dunes"
        case .ocean: return "Open Water"
        case .grove: return "Blossom"
        }
    }
}

struct MusicScore {
    var mood: MusicMood
    var notes: [MusicNote]      // sorted by t
    var length: Float           // seconds (last release + tail)
    var title: String
}

// MARK: - Voices

final class MusicVoice {
    let inst: Inst
    let f: Float
    let vel: Float
    let panL: Float, panR: Float
    let start: Int          // absolute frame
    let end: Int            // release starts here
    var age = 0
    var env: Float = 0
    var released = false
    var done = false
    var phase: Float = 0, phase2: Float = 0, phase3: Float = 0
    var lp: Float = 0, lp2: Float = 0, hp: Float = 0
    var ks: [Float] = []
    var ksIdx = 0
    var rng: UInt64
    var decayMul: Float = 1

    init(_ n: MusicNote, sr: Float, rng r: UInt64) {
        inst = n.inst
        f = 440 * powf(2, (n.midi - 69) / 12)
        vel = n.vel
        let a = (n.pan + 1) * Float.pi / 4
        panL = cosf(a); panR = sinf(a)
        start = Int(n.t * sr)
        end = start + Int(n.dur * sr)
        rng = r | 1
        switch inst {
        case .pluck, .harp:
            let len = max(2, Int(sr / max(30, f)))
            ks = [Float](repeating: 0, count: len)
            var s = rng
            var lpv: Float = 0
            let bright: Float = inst == .harp ? 0.45 : 0.3
            for i in 0..<len {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                let v = Float(Int32(truncatingIfNeeded: s >> 32)) / Float(Int32.max)
                lpv += bright * (v - lpv)
                ks[i] = lpv
            }
            let mean = ks.reduce(0, +) / Float(len)
            for i in 0..<len { ks[i] -= mean }
        case .bell: decayMul = expf(-1 / ((inst == .bell ? 1.6 : 1) * sr))
        case .metal: decayMul = expf(-1 / (1.2 * sr))
        case .kick: decayMul = expf(-1 / (0.28 * sr))
        case .tom: decayMul = expf(-1 / (0.35 * sr))
        case .shaker: decayMul = expf(-1 / (0.06 * sr))
        case .thud: decayMul = expf(-1 / (0.5 * sr))
        default: break
        }
    }

    @inline(__always) private func noise() -> Float {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        return Float(Int32(truncatingIfNeeded: rng >> 32)) / Float(Int32.max)
    }

    // Attack / release times per instrument (seconds).
    private var attack: Float {
        switch inst {
        case .pad: return 0.5
        case .organ: return 0.12
        case .flute: return 0.09
        case .shimmer: return 0.3
        case .drone: return 3.0
        case .bass: return 0.01
        default: return 0.003
        }
    }
    private var release: Float {
        switch inst {
        case .pad: return 1.2
        case .organ: return 0.4
        case .flute: return 0.25
        case .shimmer: return 2.5
        case .drone: return 4.0
        case .bass: return 0.15
        case .pluck: return 0.3
        case .harp: return 0.6
        default: return 0.5
        }
    }

    // Renders `n` frames starting at absolute frame `from` into l/r (additive).
    func render(into l: inout [Float], _ r: inout [Float], from: Int, count n: Int, sr: Float) {
        var i0 = 0
        if start > from { i0 = start - from; if i0 >= n { return } }
        let aRate = 1 / (attack * sr), rRate = expf(-1 / (release * sr))
        let w = 2 * Float.pi * f / sr
        let isPercussive = inst == .bell || inst == .metal || inst == .kick || inst == .tom || inst == .shaker || inst == .thud
        var env = self.env
        for i in i0..<n {
            let frame = from + i
            if !released && frame >= end { released = true }
            // Envelope
            if isPercussive {
                env = i == i0 && age == 0 ? 1 : env * decayMul
                if env < 0.0005 { done = true; break }
            } else if released {
                env *= rRate
                if env < 0.0005 { done = true; break }
            } else if env < 1 {
                env = min(1, env + aRate)
            }
            let t = Float(age) / sr
            var s: Float = 0
            switch inst {
            case .pad:
                phase += f / sr; if phase >= 1 { phase -= 1 }
                phase2 += f * 1.004 / sr; if phase2 >= 1 { phase2 -= 1 }
                phase3 += f * 0.996 / sr; if phase3 >= 1 { phase3 -= 1 }
                let raw = (phase + phase2 + phase3) * 2 - 3
                let cutHz: Float = 500 + 1600 * env * vel
                let cut: Float = 1 - expf(-2 * Float.pi * cutHz / sr)
                lp += cut * (raw - lp); lp2 += cut * (lp - lp2)
                s = lp2 * 0.35
            case .drone:
                phase += f / sr; if phase >= 1 { phase -= 1 }
                let ph: Float = 2 * Float.pi * phase
                let h1: Float = sinf(ph), h2: Float = 0.4 * sinf(2 * ph + 0.3), h3: Float = 0.2 * sinf(3 * ph)
                let swell: Float = 1 + 0.15 * sinf(2 * Float.pi * 0.17 * t)
                s = (h1 + h2 + h3) * 0.45 * swell
            case .organ:
                phase += f / sr; if phase >= 1 { phase -= 1 }
                let p2 = 2 * Float.pi * phase
                let o1: Float = sinf(p2) + 0.5 * sinf(2 * p2)
                let o2: Float = 0.25 * sinf(3 * p2) + 0.12 * sinf(4 * p2)
                let trem: Float = 1 + 0.08 * sinf(2 * Float.pi * 4.5 * t)
                s = (o1 + o2) * 0.4 * trem
            case .flute:
                let vibDepth: Float = min(1, t / 0.4)
                let vib: Float = 1 + 0.006 * sinf(2 * Float.pi * 5.2 * t) * vibDepth
                phase += f * vib / sr; if phase >= 1 { phase -= 1 }
                let p2 = 2 * Float.pi * phase
                let fl: Float = sinf(p2) + 0.25 * sinf(2 * p2) + 0.08 * sinf(3 * p2)
                s = fl * 0.5 + noise() * 0.02
            case .shimmer:
                phase += f / sr; if phase >= 1 { phase -= 1 }
                let shim: Float = 0.7 + 0.3 * sinf(2 * Float.pi * 6.7 * t + Float(start % 97))
                s = sinf(2 * Float.pi * phase) * 0.4 * shim
            case .bass:
                phase += f / sr; if phase >= 1 { phase -= 1 }
                let raw: Float = sinf(2 * Float.pi * phase) + 0.35 * (phase * 2 - 1)
                let cut: Float = 1 - expf(-2 * Float.pi * 380 / sr)
                lp += cut * (raw - lp)
                let pluckEnv: Float = released ? 1 : (0.6 + 0.4 * expf(-t / 0.35))
                s = lp * 0.9 * pluckEnv
            case .pluck, .harp:
                let len = ks.count
                let nxt = (ksIdx + 1) % len
                let v = ks[ksIdx]
                ks[ksIdx] = (v + ks[nxt]) * 0.5 * (released ? 0.985 : (inst == .harp ? 0.9975 : 0.996))
                ksIdx = nxt
                s = v * 0.8
            case .bell:
                let idx: Float = 2.2 * env
                let ang: Float = w * Float(age)
                s = sinf(ang + idx * sinf(3.01 * ang)) * 0.5
            case .metal:
                let ang: Float = w * Float(age)
                let modIdx: Float = 3 * env
                s = sinf(ang + modIdx * sinf(1.41 * ang)) * 0.5
            case .kick:
                let fk: Float = 40 + 110 * expf(-t / 0.045)
                phase += fk / sr; if phase >= 1 { phase -= 1 }
                s = sinf(2 * .pi * phase) * 0.9
            case .tom:
                let ft: Float = f * 0.5 + 40 * expf(-t / 0.03)
                phase += ft / sr; if phase >= 1 { phase -= 1 }
                let click: Float = t < 0.01 ? noise() * 0.3 : 0
                s = sinf(2 * Float.pi * phase) * 0.7 + click
            case .shaker:
                let nz = noise()
                hp += 0.5 * (nz - hp)
                s = (nz - hp) * 0.6
            case .thud:
                let nz = noise()
                let cut: Float = 1 - expf(-2 * Float.pi * 140 / sr)
                lp += cut * (nz - lp); lp2 += cut * (lp - lp2)
                s = lp2 * 3.0
            }
            let out = s * env * vel
            l[i] += out * panL
            r[i] += out * panR
            age += 1
        }
        self.env = env
    }
}

// MARK: - Renderer (pure; the harness uses it offline)

final class MusicRenderer {
    let sr: Float
    private(set) var score: MusicScore?
    private var voices: [MusicVoice] = []
    private var noteIdx = 0
    private(set) var frame = 0
    private var gain: Float = 0, gainTarget: Float = 0, gainRate: Float = 0
    private var seed: UInt64 = 1
    var finished: Bool { score == nil || (noteIdx >= (score?.notes.count ?? 0) && voices.isEmpty && Float(frame) / sr > (score?.length ?? 0)) }
    var isPlaying: Bool { score != nil && !finished }

    init(sampleRate: Float = Float(SoundBank.rate)) { sr = sampleRate }

    func play(_ s: MusicScore, fadeIn: Float = 2) {
        score = s
        voices = []
        noteIdx = 0
        frame = 0
        gain = 0
        gainTarget = 1
        gainRate = 1 / max(0.01, fadeIn * sr)
        seed = UInt64(bitPattern: Int64(s.title.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0x7FFFFFFF })) | 1
    }

    func stop(fade: Float) {
        gainTarget = 0
        gainRate = 1 / max(0.01, fade * sr)
        if fade <= 0 { score = nil; voices = [] }
    }

    // Renders one block; returns false when there is nothing to play (silence).
    @discardableResult
    func render(into l: inout [Float], _ r: inout [Float]) -> Bool {
        let n = l.count
        for i in 0..<n { l[i] = 0; r[i] = 0 }
        guard let s = score else { return false }
        // Start the notes that begin inside this block.
        let blockEnd = frame + n
        while noteIdx < s.notes.count && Int(s.notes[noteIdx].t * sr) < blockEnd {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            voices.append(MusicVoice(s.notes[noteIdx], sr: sr, rng: seed))
            noteIdx += 1
        }
        for v in voices { v.render(into: &l, &r, from: frame, count: n, sr: sr) }
        voices.removeAll { $0.done }
        // Master fade, the piece's own tail fade and a soft limiter.
        let tailStart = max(0, s.length - 8)
        for i in 0..<n {
            if gain != gainTarget {
                if abs(gainTarget - gain) <= gainRate { gain = gainTarget } else { gain += gainTarget > gain ? gainRate : -gainRate }
            }
            let t = Float(frame + i) / sr
            let tail: Float = t > tailStart ? max(0, 1 - (t - tailStart) / 8) : 1
            let g = gain * tail * 0.6
            let a = l[i] * g, b = r[i] * g
            l[i] = a / (1 + abs(a))
            r[i] = b / (1 + abs(b))
        }
        frame += n
        if gainTarget == 0 && gain == 0 { score = nil; voices = [] }
        if noteIdx >= s.notes.count && voices.isEmpty && Float(frame) / sr > s.length { score = nil }
        return true
    }

    // Offline: the whole piece (or the first `seconds`) as mono for the harness.
    static func renderMono(_ s: MusicScore, seconds: Float, sampleRate: Float = Float(SoundBank.rate)) -> [Float] {
        let r = MusicRenderer(sampleRate: sampleRate)
        r.play(s, fadeIn: 1)
        let block = 4096
        var l = [Float](repeating: 0, count: block), rr = [Float](repeating: 0, count: block)
        var out: [Float] = []
        out.reserveCapacity(Int(seconds * sampleRate))
        while Float(out.count) / sampleRate < seconds && r.score != nil {
            r.render(into: &l, &rr)
            for i in 0..<block { out.append((l[i] + rr[i]) * 0.5) }
        }
        return out
    }
}

// MARK: - Stream (AVAudioPlayerNode fed from a background queue)

final class MusicStream {
    let node = AVAudioPlayerNode()
    let format: AVAudioFormat
    let renderer = MusicRenderer()
    private let queue = DispatchQueue(label: "blocksmith.music", qos: .userInitiated)
    private let block = 4096
    private var queued = 0
    private var l: [Float], r: [Float]
    private var running = true
    var volume: Float = 1 { didSet { if abs(volume - oldValue) > 0.001 { node.volume = volume } } }
    private(set) var current: MusicMood? = nil
    private(set) var title = ""
    private var lock = NSLock()
    private var rendererFinished = true

    let mono: Bool

    init(format f: AVAudioFormat) {
        format = f
        mono = f.channelCount == 1
        l = [Float](repeating: 0, count: 4096)
        r = [Float](repeating: 0, count: 4096)
        node.volume = volume
    }

    // Call once the node is attached, connected and playing: primes the queue and keeps it fed.
    func start() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.generation += 1
            self.queued = 0
            for _ in 0..<4 { self.pump(self.generation) }
        }
    }

    // After the output device changed (the engine restarted): drop the old chain and prime a new one.
    func restart() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.generation += 1
            self.node.stop()
            self.node.play()
            self.queued = 0
            for _ in 0..<4 { self.pump(self.generation) }
        }
    }

    var isPlaying: Bool { lock.lock(); defer { lock.unlock() }; return current != nil }

    func play(_ score: MusicScore, fadeIn: Float = 2) {
        lock.lock(); current = score.mood; title = score.title; rendererFinished = false; lock.unlock()
        queue.async { [weak self] in self?.renderer.play(score, fadeIn: fadeIn) }
    }

    func stop(fade: Float) {
        lock.lock(); let had = current != nil; current = nil; lock.unlock()
        if had { queue.async { [weak self] in self?.renderer.stop(fade: fade) } }
    }

    func update(_ dt: Float) {
        // The render queue reports the end of a piece; mirror it into `current` on the main thread.
        lock.lock()
        if current != nil && rendererFinished { current = nil }
        lock.unlock()
    }

    // Renders one block and schedules it; the completion schedules the next, keeping ~4 blocks ahead.
    // Buffers come from a small ring (no per-block allocation); `gen` retires chains from before a restart.
    private var ring: [AVAudioPCMBuffer] = []
    private var ringIdx = 0
    private var generation = 0

    private func pump(_ gen: Int) {
        guard running, gen == generation else { return }
        if ring.isEmpty {
            for _ in 0..<6 { if let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(block)) { ring.append(b) } }
            if ring.isEmpty { return }
        }
        let buf = ring[ringIdx]
        ringIdx = (ringIdx + 1) % ring.count
        guard let ch = buf.floatChannelData else { return }
        renderer.render(into: &l, &r)
        let fin = renderer.finished
        lock.lock(); rendererFinished = fin; lock.unlock()
        buf.frameLength = AVAudioFrameCount(block)
        if mono {
            for i in 0..<block { ch[0][i] = (l[i] + r[i]) * 0.5 }
        } else {
            l.withUnsafeBufferPointer { ch[0].update(from: $0.baseAddress!, count: block) }
            r.withUnsafeBufferPointer { ch[1].update(from: $0.baseAddress!, count: block) }
        }
        queued += 1
        node.scheduleBuffer(buf, at: nil, options: [], completionCallbackType: .dataConsumed) { [weak self] _ in
            guard let self = self else { return }
            self.queue.async { self.queued -= 1; self.pump(gen) }
        }
    }
}

// MARK: - Composer

enum Composer {
    static let scales: [String: [Int]] = [
        "major": [0, 2, 4, 5, 7, 9, 11], "lydian": [0, 2, 4, 6, 7, 9, 11], "mixolydian": [0, 2, 4, 5, 7, 9, 10],
        "dorian": [0, 2, 3, 5, 7, 9, 10], "aeolian": [0, 2, 3, 5, 7, 8, 10], "phrygian": [0, 1, 3, 5, 7, 8, 10],
        "harmonicMinor": [0, 2, 3, 5, 7, 8, 11], "wholeTone": [0, 2, 4, 6, 8, 10], "pentMajor": [0, 2, 4, 7, 9], "pentMinor": [0, 3, 5, 7, 10],
        "lydianAug": [0, 2, 4, 6, 8, 9, 11],
    ]

    struct Spec {
        var scales: [String]
        var bpm: ClosedRange<Int>
        var lead: [Inst]
        var pad: Inst
        var bass: Bool
        var arp: Bool
        var bells: Bool
        var drums: Int          // 0 none, 1 slow thuds, 2 driving
        var density: Float      // melody note density 0...1
        var restiness: Float    // chance a phrase slot is a rest
        var root: ClosedRange<Int>
        var bars: ClosedRange<Int>
        var padVel: Float
    }

    static func spec(_ m: MusicMood) -> Spec {
        switch m {
        case .title: return Spec(scales: ["major", "lydian"], bpm: 66...80, lead: [.pluck, .flute], pad: .pad, bass: true, arp: true, bells: true, drums: 0, density: 0.75, restiness: 0.2, root: 50...57, bars: 40...48, padVel: 0.5)
        case .day: return Spec(scales: ["major", "lydian", "mixolydian", "pentMajor"], bpm: 62...84, lead: [.pluck, .harp, .flute], pad: .pad, bass: true, arp: true, bells: false, drums: 0, density: 0.65, restiness: 0.3, root: 48...58, bars: 40...56, padVel: 0.45)
        case .night: return Spec(scales: ["dorian", "aeolian", "pentMinor"], bpm: 50...64, lead: [.bell, .harp, .flute], pad: .pad, bass: true, arp: false, bells: true, drums: 0, density: 0.45, restiness: 0.45, root: 45...55, bars: 36...48, padVel: 0.4)
        case .underground: return Spec(scales: ["aeolian", "phrygian", "dorian"], bpm: 44...56, lead: [.bell, .shimmer], pad: .drone, bass: false, arp: false, bells: true, drums: 0, density: 0.3, restiness: 0.6, root: 40...50, bars: 32...44, padVel: 0.5)
        case .underwater: return Spec(scales: ["lydian", "major", "wholeTone"], bpm: 48...60, lead: [.shimmer, .organ], pad: .pad, bass: false, arp: false, bells: true, drums: 0, density: 0.4, restiness: 0.5, root: 48...56, bars: 32...44, padVel: 0.5)
        case .ember: return Spec(scales: ["phrygian", "harmonicMinor", "aeolian"], bpm: 56...72, lead: [.organ, .metal, .flute], pad: .drone, bass: true, arp: false, bells: false, drums: 1, density: 0.4, restiness: 0.5, root: 38...46, bars: 36...48, padVel: 0.55)
        case .hollow: return Spec(scales: ["wholeTone", "lydianAug", "lydian"], bpm: 46...58, lead: [.bell, .shimmer, .harp], pad: .pad, bass: false, arp: true, bells: true, drums: 0, density: 0.4, restiness: 0.5, root: 52...62, bars: 36...48, padVel: 0.4)
        case .creative: return Spec(scales: ["pentMajor", "major", "lydian"], bpm: 72...92, lead: [.pluck, .harp, .organ], pad: .pad, bass: true, arp: true, bells: true, drums: 0, density: 0.7, restiness: 0.25, root: 52...60, bars: 40...56, padVel: 0.4)
        case .boss: return Spec(scales: ["harmonicMinor", "phrygian"], bpm: 96...118, lead: [.organ, .metal], pad: .pad, bass: true, arp: true, bells: false, drums: 2, density: 0.7, restiness: 0.2, root: 40...48, bars: 48...64, padVel: 0.6)
        case .rain: return Spec(scales: ["dorian", "major", "mixolydian"], bpm: 54...68, lead: [.harp, .flute, .pluck], pad: .pad, bass: true, arp: false, bells: false, drums: 0, density: 0.5, restiness: 0.4, root: 48...56, bars: 36...48, padVel: 0.45)
        case .snow: return Spec(scales: ["lydian", "pentMajor", "major"], bpm: 48...60, lead: [.bell, .shimmer, .harp], pad: .pad, bass: false, arp: true, bells: true, drums: 0, density: 0.35, restiness: 0.55, root: 55...64, bars: 32...44, padVel: 0.35)
        case .desert: return Spec(scales: ["phrygian", "harmonicMinor", "pentMinor"], bpm: 58...72, lead: [.flute, .pluck], pad: .drone, bass: true, arp: false, bells: false, drums: 1, density: 0.5, restiness: 0.35, root: 45...52, bars: 36...48, padVel: 0.4)
        case .ocean: return Spec(scales: ["mixolydian", "lydian", "major"], bpm: 52...66, lead: [.harp, .organ, .flute], pad: .pad, bass: true, arp: true, bells: false, drums: 0, density: 0.45, restiness: 0.4, root: 47...55, bars: 36...48, padVel: 0.5)
        case .grove: return Spec(scales: ["pentMajor", "major", "lydian"], bpm: 60...76, lead: [.pluck, .bell, .harp], pad: .pad, bass: true, arp: true, bells: true, drums: 0, density: 0.6, restiness: 0.3, root: 52...60, bars: 36...48, padVel: 0.4)
        }
    }

    // Rhythm cells for one bar of 4 beats (note lengths in beats; negative = rest).
    static let cells: [[Float]] = [
        [1, 1, 2], [2, 2], [4], [1, 1, 1, 1], [0.5, 0.5, 1, 2], [1.5, 0.5, 2], [3, 1], [2, 1, 1], [1, 2, 1], [0.5, 0.5, 0.5, 0.5, 2],
        [-1, 1, 2], [-2, 1, 1], [1, -1, 2], [2, -1, 1], [-1, 3], [1.5, 1.5, 1], [-0.5, 0.5, 1, 2],
    ]

    static func compose(_ mood: MusicMood, seed: UInt64) -> MusicScore {
        var rng = SRng(seed ^ 0xA5A5_5A5A_1234_ABCD)
        let sp = spec(mood)
        let scaleName = sp.scales[rng.int(sp.scales.count)]
        let scale = scales[scaleName]!
        let ns = scale.count
        let root = sp.root.lowerBound + rng.int(sp.root.upperBound - sp.root.lowerBound + 1)
        let bpm = Float(sp.bpm.lowerBound + rng.int(sp.bpm.upperBound - sp.bpm.lowerBound + 1))
        let beat = 60 / bpm
        let bars = sp.bars.lowerBound + rng.int(sp.bars.upperBound - sp.bars.lowerBound + 1)
        let lead = sp.lead[rng.int(sp.lead.count)]
        var notes: [MusicNote] = []

        func pitch(_ degree: Int, octave: Int = 0) -> Float {
            let d = ((degree % ns) + ns) % ns
            let o = Int(floor(Float(degree) / Float(ns))) + octave
            return Float(root + scale[d] + 12 * o)
        }

        // Chord progression: 8-bar sections, each bar one chord (scale degrees); sections repeat with variation.
        let pools: [[Int]] = ns >= 7
            ? [[0, 5, 3, 4, 0, 5, 1, 4], [0, 3, 4, 3, 0, 3, 5, 4], [5, 3, 0, 4, 5, 3, 1, 4], [0, 4, 5, 3, 0, 4, 1, 0], [0, 0, 3, 3, 5, 5, 4, 4], [0, 2, 3, 4, 0, 2, 5, 4]]
            : [[0, 2, 1, 3, 0, 2, 4, 3], [0, 3, 2, 1, 0, 3, 4, 1], [0, 1, 2, 1, 0, 1, 3, 2]]
        let progA = pools[rng.int(pools.count)], progB = pools[rng.int(pools.count)]
        var chords: [Int] = []
        var sectionOf: [Int] = []        // 0 intro, 1 A, 2 B, 3 outro
        let sections = max(2, (bars - 8) / 8)
        chords += Array(progA.prefix(4)); sectionOf += [0, 0, 0, 0]                                 // intro (pad only)
        for s in 0..<sections { let p = s % 3 == 1 ? progB : progA; chords += p; sectionOf += [Int](repeating: s % 3 == 1 ? 2 : 1, count: 8) }
        chords += [progA[0], progA[0], progA[0], progA[0]]; sectionOf += [3, 3, 3, 3]                // outro
        let totalBars = chords.count
        let barLen = 4 * beat

        // Pad / drone: chord tones in a mid register with smooth voice leading.
        var prevTop = 7
        for b in 0..<totalBars {
            let c = chords[b]
            let t0 = Float(b) * barLen
            let isDrone = sp.pad == .drone
            var tones = [c, c + 2, c + 4]
            if ns >= 7 && rng.chance(0.35) { tones.append(c + 6) }
            // Keep the top voice near the previous one (inversion choice).
            var best = tones, bestDist = 99
            for inv in 0..<tones.count {
                var cand = tones
                for k in 0..<inv { cand[k] += ns }
                let top = cand.max()!
                let dist = abs(top - prevTop)
                if dist < bestDist { bestDist = dist; best = cand }
            }
            prevTop = best.max()!
            let sustain = b + 1 < totalBars && chords[b + 1] == c && !isDrone ? barLen * 2 : barLen
            if b > 0 && b < totalBars && chords[b - 1] == c && !isDrone && (b % 2 == 1) { continue }
            for (k, d) in best.enumerated() {
                let vel = sp.padVel * (0.8 + 0.2 * rng.float()) * (isDrone ? (k == 0 ? 1 : 0.5) : 1)
                notes.append(MusicNote(t: t0, dur: sustain - 0.05, inst: sp.pad, midi: pitch(d, octave: isDrone ? -1 : 0), vel: vel, pan: Float(k) * 0.5 - 0.5))
            }
        }

        // Bass: root on the downbeat, sometimes the fifth on beat 3.
        if sp.bass {
            for b in 4..<(totalBars - 2) {
                let c = chords[b]
                let t0 = Float(b) * barLen
                if sectionOf[b] == 3 { continue }
                if mood == .boss || mood == .creative || rng.chance(0.85) {
                    notes.append(MusicNote(t: t0, dur: 2 * beat, inst: .bass, midi: pitch(c, octave: -2), vel: 0.55, pan: 0))
                }
                if rng.chance(mood == .boss ? 0.9 : 0.4) {
                    notes.append(MusicNote(t: t0 + 2 * beat, dur: 1.5 * beat, inst: .bass, midi: pitch(c + (rng.chance(0.6) ? 4 : 0), octave: -2), vel: 0.45, pan: 0))
                }
                if mood == .boss && rng.chance(0.5) {
                    notes.append(MusicNote(t: t0 + 3.5 * beat, dur: 0.5 * beat, inst: .bass, midi: pitch(c, octave: -2), vel: 0.5, pan: 0))
                }
            }
        }

        // Arpeggios: chord tones in eighths (or triplet-ish sixteenths in the Hollow), left of centre.
        if sp.arp {
            let arpInst: Inst = mood == .hollow ? .bell : (mood == .boss ? .organ : (lead == .pluck ? .harp : .pluck))
            for b in 4..<(totalBars - 4) where sectionOf[b] != 0 && (mood == .boss || mood == .creative || (b / 8) % 2 == 1) {
                let c = chords[b]
                let t0 = Float(b) * barLen
                let pattern = [c, c + 2, c + 4, c + 7, c + 4, c + 2, c + 4, c + 7]
                let steps = mood == .hollow ? 6 : 8
                for k in 0..<steps where rng.chance(mood == .hollow ? 0.55 : 0.9) {
                    let d = pattern[k % pattern.count]
                    notes.append(MusicNote(t: t0 + Float(k) * barLen / Float(steps), dur: beat * 0.6, inst: arpInst, midi: pitch(d, octave: 1), vel: 0.28 + 0.1 * rng.float(), pan: -0.35 + 0.1 * Float(k % 3)))
                }
            }
        }

        // Melody: motif-based phrases. A motif is two bars of rhythm cells with degree offsets; each 8-bar
        // section states it, answers it a third up, varies it and cadences to the tonic.
        func makeMotif() -> [(Float, Float, Int)] {       // (beat offset, length, degree offset)
            var m: [(Float, Float, Int)] = []
            var deg = 0
            var t: Float = 0
            for _ in 0..<2 {
                let cell = cells[rng.int(cells.count)]
                for len in cell {
                    if len < 0 { t += -len; continue }
                    if rng.chance(sp.restiness) { t += len; continue }
                    m.append((t, len, deg))
                    let step = rng.chance(0.7) ? (rng.chance(0.5) ? 1 : -1) : (rng.chance(0.5) ? 2 : -2)
                    deg += step
                    if deg > 5 { deg = 4 }; if deg < -3 { deg = -2 }
                    t += len
                }
            }
            return m
        }
        let motifA = makeMotif(), motifB = makeMotif()
        var startDeg = 4 + rng.int(3)
        for b in stride(from: 4, to: totalBars - 4, by: 2) where sectionOf[b] != 0 && sectionOf[b] != 3 {
            let phrasePos = ((b - 4) / 2) % 4                // 0 state, 1 answer, 2 vary, 3 cadence
            if phrasePos == 0 && rng.chance(0.5) { startDeg = 4 + rng.int(3) }
            let motif = (sectionOf[b] == 2 ? motifB : motifA)
            let shift = phrasePos == 1 ? 2 : (phrasePos == 2 ? (rng.chance(0.5) ? -1 : 1) : 0)
            let t0 = Float(b) * barLen
            let chord = chords[b]
            for (k, n) in motif.enumerated() {
                if !rng.chance(sp.density + 0.3) { continue }
                var d = startDeg + n.2 + shift
                if phrasePos == 3 && k == motif.count - 1 { d = chord + (rng.chance(0.5) ? 0 : 4) + 7 }   // land on a chord tone
                // Pull off-chord notes on strong beats toward chord tones.
                let strong = n.0.truncatingRemainder(dividingBy: 2) == 0
                if strong {
                    let rel = ((d - chord) % ns + ns) % ns
                    if rel == 1 || rel == 3 || rel == 5 { d -= 1 }
                }
                let len = (phrasePos == 3 && k == motif.count - 1 ? n.1 * 2 : n.1) * beat
                let vel = (0.45 + 0.25 * rng.float()) * (strong ? 1 : 0.85)
                notes.append(MusicNote(t: t0 + n.0 * beat, dur: len * 0.95, inst: lead, midi: pitch(d, octave: 1), vel: vel, pan: 0.15))
                // Occasional harmony a third or sixth below on long notes.
                if n.1 >= 2 && rng.chance(0.3) {
                    notes.append(MusicNote(t: t0 + n.0 * beat, dur: len * 0.95, inst: lead, midi: pitch(d - (rng.chance(0.5) ? 2 : 5), octave: 1), vel: vel * 0.6, pan: -0.1))
                }
            }
        }

        // Bells / shimmer: sparse high chord tones, right of centre.
        if sp.bells {
            for b in 4..<(totalBars - 2) where rng.chance(0.5) {
                let c = chords[b]
                let t0 = Float(b) * barLen + Float(rng.int(4)) * beat
                let d = c + [0, 2, 4, 7][rng.int(4)]
                notes.append(MusicNote(t: t0, dur: beat * 2, inst: mood == .underwater ? .shimmer : .bell, midi: pitch(d, octave: 2), vel: 0.2 + 0.12 * rng.float(), pan: 0.4))
            }
        }

        // Drums.
        if sp.drums == 1 {
            for b in 4..<(totalBars - 4) where sectionOf[b] != 0 {
                let t0 = Float(b) * barLen
                if b % 2 == 0 { notes.append(MusicNote(t: t0, dur: 0.5, inst: .thud, midi: 40, vel: 0.8, pan: 0)) }
                if rng.chance(0.5) { notes.append(MusicNote(t: t0 + 2 * beat, dur: 0.5, inst: .thud, midi: 40, vel: 0.5, pan: 0.2)) }
                if rng.chance(0.25) { notes.append(MusicNote(t: t0 + Float(rng.int(8)) * beat / 2, dur: 1, inst: .metal, midi: Float(60 + rng.int(12)), vel: 0.3, pan: -0.4 + 0.8 * rng.float())) }
            }
        } else if sp.drums == 2 {
            for b in 4..<(totalBars - 4) where sectionOf[b] != 0 {
                let t0 = Float(b) * barLen
                for k in 0..<4 {
                    let t = t0 + Float(k) * beat
                    if k % 2 == 0 { notes.append(MusicNote(t: t, dur: 0.3, inst: .kick, midi: 36, vel: 0.9, pan: 0)) }
                    else { notes.append(MusicNote(t: t, dur: 0.4, inst: .tom, midi: 45, vel: 0.7, pan: 0.15)) }
                    if k == 3 && rng.chance(0.3) { notes.append(MusicNote(t: t + beat / 2, dur: 0.3, inst: .kick, midi: 36, vel: 0.7, pan: 0)) }
                }
                for k in 0..<8 { notes.append(MusicNote(t: t0 + Float(k) * beat / 2, dur: 0.1, inst: .shaker, midi: 80, vel: k % 2 == 0 ? 0.35 : 0.2, pan: -0.3)) }
            }
        }

        notes.sort { $0.t < $1.t }
        let length = Float(totalBars) * barLen + 6
        let titles = ["Long Meadow", "Slate and Sky", "Lantern Hours", "Hollow Bells", "Under Stone", "Ember March", "Tidewater", "First Light", "Far Hills", "Quiet Forge", "Glass Sea", "Night Watch"]
        return MusicScore(mood: mood, notes: notes, length: length, title: "\(titles[Int(seed % UInt64(titles.count))]) (\(mood.label))")
    }
}

// MARK: - Note blocks (sound effects) live here too

enum MusicSynth {
    // Note block instruments 0...12: harp, bass, snare, hat, bass drum, bell, flute, chime, guitar, xylophone, iron xylophone, banjo, pling.
    // Pitch 0 = F#3 for the harp family; bass instruments two octaves down, chimes two up.
    static func noteBlock(_ g: inout Synth, inst: Int, pitch n: Int) -> [Float] {
        let f: Float = 185 * powf(2, Float(n) / 12)
        switch inst {
        case 1: return g.modes(0.5, [(f / 4, 0.9, 0.25), (f / 2, 0.3, 0.12)])                                   // bass
        case 2: return g.burst(0.18, lp: 5000, hp: 800, attack: 0.002, decay: 0.05, gain: 1.4)                  // snare
        case 3: return g.burst(0.08, lp: 12000, hp: 6000, attack: 0.001, decay: 0.02, gain: 1.2)                // hat
        case 4: return Synth.mix(g.modes(0.3, [(60 + f / 20, 1.2, 0.08)]), g.burst(0.05, lp: 800, hp: 40, decay: 0.02, gain: 1)) // bass drum
        case 5: return g.modes(1.2, [(f * 2, 0.6, 0.6), (f * 2 * 2.76, 0.25, 0.3), (f * 2 * 5.4, 0.1, 0.15)])  // bell
        case 6: return g.voice(0.6, f0: f * 2, f1: f * 2, vib: 0.02, lp: 3000, gain: 0.9)                       // flute
        case 7: return g.modes(1.0, [(f * 4, 0.5, 0.5), (f * 4 * 2.4, 0.2, 0.3)])                              // chime
        case 8: return g.pluck(0.7, f: f / 2, damp: 0.995, bright: 0.4, gain: 0.8)                              // guitar
        case 9: return g.modes(0.35, [(f * 4, 0.7, 0.08), (f * 4 * 3.9, 0.2, 0.04)])                           // xylophone
        case 10: return g.modes(0.5, [(f, 0.7, 0.25), (f * 3.9, 0.25, 0.12)])                                  // iron xylophone
        case 11: return g.pluck(0.4, f: f, damp: 0.99, bright: 0.8, gain: 0.8)                                  // banjo
        case 12: return Synth.mix(g.modes(0.8, [(f, 0.6, 0.35)]), g.modes(0.8, [(f * 2.01, 0.3, 0.3)]))         // pling
        default: return g.modes(0.7, [(f, 0.7, 0.3), (f * 2, 0.25, 0.15), (f * 3, 0.1, 0.08)])                 // harp
        }
    }
}
