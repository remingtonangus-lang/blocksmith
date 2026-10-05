import Foundation
import simd

// The Quest's SoundEngine: the same API as the Mac's AVAudioEngine front end (Sources/SoundEngine.swift), mixed in
// software. The game thread queues voices and re-aims them every tick (equal-power panning in head space, linear
// distance rolloff, occlusion and underwater low-pass, a little cave reverb); the audio thread (AAudio on Android,
// QuestAudioOutput) pulls stereo frames from render(). Music and jukebox discs are rendered a block at a time on a
// background queue (MusicStream) and mixed in from a ring.

// A PCM clip shared between the game thread and the mixer (immutable once made).
final class QuestClip {
    let data: [Float]
    init(_ d: [Float]) { data = d }
}

final class SoundEngine {
    let bank = SoundBank()
    var custom: CustomMusic? { nil }            // no own-music folder on the Quest (MacOnlyStubs.swift)
    static let rate = SoundBank.rate

    // One mixer voice. The game thread writes the target gains; the mixer glides toward them per block.
    struct Voice {
        var clip: QuestClip?
        var pos: Double = 0            // read position in frames
        var rate: Double = 1
        var loop = false
        var gl: Float = 0, gr: Float = 0           // current per-channel gain
        var tl: Float = 0, tr: Float = 0           // target per-channel gain
        var cutoff: Float = 1          // one-pole low-pass coefficient (1 = open)
        var lp: Float = 0              // filter state
        var active = false
        var world: V3? = nil           // world position (re-aimed on setListener)
        var range: Float = 16
        var baseGain: Float = 0
        var occlusion: Float = 0
        var bus = 0                    // 0 world (filtered underwater), 1 interface (never filtered)
        var endTime: Double = 0
        var loudness: Float = 0
    }
    private var voices = [Voice](repeating: Voice(), count: 40)
    private static let spatialCount = 24, flatCount = 10       // voices 34..39 are interface voices
    private var nextSpatial = 0, nextFlat = 0, nextUI = 0, variant = 0
    private var mixLock = NSLock()
    private var clips: [Snd: [QuestClip]] = [:]

    private(set) var music: MusicStream?
    private(set) var disc: MusicStream?
    private var discPos: V3?
    private var discOcclusion: Float = 0

    private var eye = V3.zero, fwd = V3(0, 0, -1), right = V3(1, 0, 0), up = V3(0, 1, 0)
    private(set) var cave: Float = 0
    private var underwater = false
    private var underwaterMix: Float = 0       // 0...1, glides (mixer reads it)
    private var reverb = QuestReverb()

    final class Loop {
        var snd: Snd
        var voice = -1
        var target: Float = 0, level: Float = 0
        var pos: V3?
        var occlusion: Float = 0
        init(_ s: Snd) { snd = s }
    }
    private var loops: [String: Loop] = [:]
    private var loopVoices = [Voice](repeating: Voice(), count: 24)

    var volume: Float {
        get { AudioSettings.volume(.master) }
        set { AudioSettings.set(.master, newValue) }
    }
    var enabled = true
    var musicDuck: Float = 1

    init?() {
        music = MusicStream(stereo: true)
        disc = MusicStream(stereo: false)
        bank.prewarm(SoundBank.commonSounds + [.explode, .thunder, .lightning, .caveAmbience, .caveDrip, .caveWind, .levelUp, .totem, .playerDeath])
        music?.start()
        disc?.start()
    }

    // MARK: Listener / environment

    // `yaw`/`pitch` are the game's camera angles; on the Quest the game's camera follows the head, so this is head space.
    func setListener(eye e: V3, yaw: Float, pitch: Float, cave c: Float, underwater w: Bool) {
        eye = e
        fwd = V3(-sinf(yaw) * cosf(pitch), sinf(pitch), -cosf(yaw) * cosf(pitch))
        right = V3(cosf(yaw), 0, -sinf(yaw))
        up = simd_cross(right, fwd)
        cave = c
        underwater = w
        mixLock.lock()
        for i in 0..<voices.count where voices[i].active { aim(&voices[i]) }
        for (_, l) in loops where l.voice >= 0 && loopVoices[l.voice].active {
            loopVoices[l.voice].world = l.pos
            loopVoices[l.voice].occlusion = l.occlusion
            loopVoices[l.voice].baseGain = l.level
            aim(&loopVoices[l.voice])
        }
        mixLock.unlock()
        if let d = disc {
            if let p = discPos {
                let (gl, gr, _) = pan(p, range: 64, gain: 1, occlusion: discOcclusion)
                d.setPan(gl, gr)
            }
        }
    }

    func setDisc(at p: V3?, occlusion: Float = 0) {
        discPos = p
        discOcclusion = occlusion
        guard let d = disc else { return }
        if let p = p {
            let (gl, gr, _) = pan(p, range: 64, gain: 1, occlusion: occlusion)
            d.setPan(gl, gr)
            d.volume = AudioSettings.volume(.master) * AudioSettings.volume(.blocks) * 1.2
        }
    }

    func setRoom(size: Float, enclosure: Float) {
        reverb.setRoom(size: size, enclosure: enclosure)
    }

    // Equal-power pan + linear rolloff (the Mac's environment node: reference 1.5, max 16, scaled by range).
    private func pan(_ p: V3, range: Float, gain: Float, occlusion: Float) -> (Float, Float, Float) {
        let rel = p - eye
        let k = 16 / max(1, range)
        let x = simd_dot(rel, right) * k, y = simd_dot(rel, up) * k, z = -simd_dot(rel, fwd) * k
        let d = (x * x + y * y + z * z).squareRoot()
        let att: Float = d <= 1.5 ? 1 : max(0, 1 - (d - 1.5) / (16 - 1.5))
        let az: Float = d > 0.01 ? max(-1, min(1, x / d)) : 0
        let a = (az + 1) * 0.25 * .pi
        let occ = max(0, 1 - 0.6 * occlusion)
        let g = gain * att * occ
        // Sounds behind the listener lose a little top end (a cheap front/back cue).
        let behind: Float = z > 0 && d > 0.01 ? z / d : 0
        let cutoff = max(0.05, (1 - 0.65 * occlusion) * (1 - 0.35 * behind))
        return (g * cosf(a) * 1.2, g * sinf(a) * 1.2, cutoff)
    }

    private func aim(_ v: inout Voice) {
        if let p = v.world {
            let (l, r, c) = pan(p, range: v.range, gain: v.baseGain, occlusion: v.occlusion)
            v.tl = l; v.tr = r; v.cutoff = c
        } else {
            v.tl = v.baseGain; v.tr = v.baseGain; v.cutoff = 1
        }
    }

    // MARK: One-shots

    private func clip(_ s: Snd, variant v: Int) -> QuestClip? {
        if let list = clips[s], !list.isEmpty { return list[v % list.count] }
        var list: [QuestClip] = []
        for k in 0..<SoundBank.variants(for: s) {
            let data = bank.clip(s, variant: k)
            if !data.isEmpty { list.append(QuestClip(data)) }
        }
        clips[s] = list
        bank.evict(s)
        return list.isEmpty ? nil : list[v % list.count]
    }

    func play(_ s: Snd, volume v: Float = 1, at pos: V3? = nil, occlusion: Float = 0) {
        guard enabled else { return }
        let gain = v * AudioSettings.gain(s)
        if gain <= 0.001 { return }
        let range = max(16 * max(1, v), s.range)
        if let p = pos, simd_length(p - eye) > range { return }
        variant += 1
        guard let c = clip(s, variant: variant) else { return }
        let now = CFAbsoluteTimeGetCurrent()
        var nv = Voice()
        nv.clip = c
        nv.active = true
        nv.baseGain = min(1.5, gain)
        nv.endTime = now + Double(c.data.count) / SoundEngine.rate
        let idx: Int
        if s.category == .ui {
            idx = SoundEngine.spatialCount + SoundEngine.flatCount + nextUI
            nextUI = (nextUI + 1) % (voices.count - SoundEngine.spatialCount - SoundEngine.flatCount)
            nv.bus = 1
        } else if pos == nil {
            idx = SoundEngine.spatialCount + nextFlat
            nextFlat = (nextFlat + 1) % SoundEngine.flatCount
        } else {
            let p = pos!
            let d = simd_length(p - eye)
            let loud = gain * max(0, 1 - d / range)
            var i = -1
            mixLock.lock()
            for k in 0..<SoundEngine.spatialCount {
                let c = (nextSpatial + k) % SoundEngine.spatialCount
                if !voices[c].active || voices[c].endTime <= now { i = c; break }
            }
            if i < 0 {
                var best: Float = .greatestFiniteMagnitude
                for k in 0..<SoundEngine.spatialCount {
                    let score = voices[k].loudness * min(Float(voices[k].endTime - now), 2)
                    if score < best { best = score; i = k }
                }
                if voices[i].loudness > loud * 2 { mixLock.unlock(); return }
            }
            mixLock.unlock()
            nextSpatial = (i + 1) % SoundEngine.spatialCount
            idx = i
            nv.world = p
            nv.range = range
            nv.occlusion = occlusion
            nv.loudness = loud
            switch s.category {
            case .blocks, .hostile, .friendly, .players: nv.rate = Double(Rand.float(in: 0.95...1.05))
            default: nv.rate = 1
            }
        }
        aim(&nv)
        nv.gl = nv.tl; nv.gr = nv.tr
        mixLock.lock()
        voices[idx] = nv
        mixLock.unlock()
    }

    // MARK: Loops

    func loop(_ key: String, _ s: Snd, volume v: Float, at pos: V3? = nil, occlusion: Float = 0) {
        guard enabled else { return }
        let l: Loop
        if let e = loops[key] {
            l = e
            if e.snd != s { e.snd = s; stopLoopVoice(e) }
        } else {
            l = Loop(s)
            loops[key] = l
        }
        l.target = v * AudioSettings.gain(s)
        l.pos = pos
        l.occlusion = occlusion
        if l.voice < 0 {
            if clips[s] == nil && !bank.has(s) { bank.prewarm([s], qos: .userInitiated); return }
            guard let c = clip(s, variant: 0) else { return }
            mixLock.lock()
            if let free = loopVoices.firstIndex(where: { !$0.active }) {
                var nv = Voice()
                nv.clip = c; nv.loop = true; nv.active = true
                nv.world = pos; nv.range = s.range; nv.occlusion = occlusion
                nv.baseGain = 0
                aim(&nv)
                loopVoices[free] = nv
                l.voice = free
            }
            mixLock.unlock()
        }
    }

    private func stopLoopVoice(_ l: Loop) {
        if l.voice >= 0 {
            mixLock.lock(); loopVoices[l.voice].active = false; mixLock.unlock()
            l.voice = -1
        }
    }

    func update(_ dt: Float, asked: Set<String>) {
        var dead: [String] = []
        for (k, l) in loops {
            if !asked.contains(k) { l.target = 0 }
            let rate: Float = l.target > l.level ? 2.5 : 3.5
            let step = dt * rate
            if abs(l.target - l.level) <= step { l.level = l.target } else { l.level += l.target > l.level ? step : -step }
            if l.voice >= 0 {
                mixLock.lock()
                loopVoices[l.voice].baseGain = min(1.5, l.level)
                loopVoices[l.voice].world = l.pos
                aim(&loopVoices[l.voice])
                mixLock.unlock()
            }
            if l.level <= 0.0005 && l.target <= 0 {
                stopLoopVoice(l)
                if !asked.contains(k) { dead.append(k) }
            }
        }
        for k in dead { loops[k] = nil }
        music?.volume = AudioSettings.volume(.master) * AudioSettings.volume(.music) * musicDuck
        music?.update(dt)
        disc?.update(dt)
    }

    var loopCount: Int { loops.count }

    func restartAfterDeviceChange() {}

    func stopAll() {
        mixLock.lock()
        for i in 0..<voices.count { voices[i].active = false }
        for i in 0..<loopVoices.count { loopVoices[i].active = false }
        mixLock.unlock()
        for l in loops.values { l.voice = -1; l.level = 0; l.target = 0 }
        music?.stop(fade: 0.5)
    }

    // MARK: Mixer (audio thread)

    private var scratchL = [Float](repeating: 0, count: 4096), scratchR = [Float](repeating: 0, count: 4096)
    private var uiL = [Float](repeating: 0, count: 4096), uiR = [Float](repeating: 0, count: 4096)
    private var lpL: Float = 0, lpR: Float = 0

    // Fills `out` with `frames` interleaved stereo float frames. Called on the audio thread.
    func render(_ out: UnsafeMutablePointer<Float>, frames total: Int) {
        var done = 0
        while done < total {
            let n = min(4096, total - done)
            renderBlock(out + done * 2, n)
            done += n
        }
    }

    private func renderBlock(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        for i in 0..<n { scratchL[i] = 0; scratchR[i] = 0; uiL[i] = 0; uiR[i] = 0 }
        mixLock.lock()
        for i in 0..<voices.count where voices[i].active {
            if voices[i].bus == 1 { mixVoice(&voices[i], &uiL, &uiR, n) } else { mixVoice(&voices[i], &scratchL, &scratchR, n) }
        }
        for i in 0..<loopVoices.count where loopVoices[i].active { mixVoice(&loopVoices[i], &scratchL, &scratchR, n) }
        let uw = underwater
        let caveAmt = cave
        mixLock.unlock()
        // World bus: a little reverb (more in caves), then the underwater low-pass.
        reverb.process(&scratchL, &scratchR, n, wet: 0.04 + 0.3 * caveAmt)
        let wantUW: Float = uw ? 1 : 0
        for i in 0..<n {
            underwaterMix += (wantUW - underwaterMix) * 0.0005
            let a: Float = 1 - underwaterMix * 0.93
            lpL += (scratchL[i] - lpL) * a
            lpR += (scratchR[i] - lpR) * a
            scratchL[i] = lpL
            scratchR[i] = lpR
        }
        music?.mix(into: &scratchL, &scratchR, n)
        disc?.mix(into: &scratchL, &scratchR, n)
        for i in 0..<n {
            // Soft clip.
            let l = scratchL[i] + uiL[i], r = scratchR[i] + uiR[i]
            out[i * 2] = l / (1 + abs(l) * 0.25)
            out[i * 2 + 1] = r / (1 + abs(r) * 0.25)
        }
    }

    @inline(__always) private func mixVoice(_ v: inout Voice, _ l: inout [Float], _ r: inout [Float], _ n: Int) {
        guard let c = v.clip else { v.active = false; return }
        let d = c.data
        let len = d.count
        if len < 2 { v.active = false; return }
        let dgl = (v.tl - v.gl) / Float(n), dgr = (v.tr - v.gr) / Float(n)
        var gl = v.gl, gr = v.gr, pos = v.pos, lp = v.lp
        let rate = v.rate, cut = v.cutoff
        d.withUnsafeBufferPointer { src in
            for i in 0..<n {
                var k = Int(pos)
                if k >= len - 1 {
                    if v.loop { pos -= Double(len - 1); k = Int(pos) } else { v.active = false; break }
                }
                let f = Float(pos - Double(k))
                let s = src[k] + (src[k + 1] - src[k]) * f
                lp += (s - lp) * cut
                l[i] += lp * gl
                r[i] += lp * gr
                gl += dgl; gr += dgr
                pos += rate
            }
        }
        v.gl = v.tl; v.gr = v.tr; v.pos = pos; v.lp = lp
    }
}

// Small stereo room (damped combs + allpass), sized by setRoom.
struct QuestReverb {
    private var combs: [[Float]] = [1116, 1188, 1277, 1356, 1422, 1491].map { [Float](repeating: 0, count: $0) }
    private var idx = [Int](repeating: 0, count: 6)
    private var lps = [Float](repeating: 0, count: 6)
    private var feedback: Float = 0.78
    mutating func setRoom(size: Float, enclosure: Float) {
        feedback = enclosure < 0.35 ? 0.7 : min(0.88, 0.74 + size * 0.008)
    }
    mutating func process(_ l: inout [Float], _ r: inout [Float], _ n: Int, wet: Float) {
        for i in 0..<n {
            let input = (l[i] + r[i]) * 0.5
            var ol: Float = 0, or: Float = 0
            for k in 0..<6 {
                let y = combs[k][idx[k]]
                lps[k] += 0.4 * (y - lps[k])
                combs[k][idx[k]] = input + lps[k] * feedback
                idx[k] += 1
                if idx[k] == combs[k].count { idx[k] = 0 }
                if k & 1 == 0 { ol += y } else { or += y }
            }
            l[i] += ol * wet / 3
            r[i] += or * wet / 3
        }
    }
}

// Music for the mixer: MusicRenderer blocks rendered ahead on a background queue into a ring (the Mac streams the
// same renderer into an AVAudioPlayerNode). Mono streams (jukebox discs) are panned by the engine.
final class MusicStream {
    let renderer = MusicRenderer()
    private let queue = DispatchQueue(label: "blocksmith.music", qos: .userInitiated)
    private let block = 4096
    private let lock = NSLock()
    private var ring: [Float]              // interleaved stereo
    private var readPos = 0, writePos = 0, filled = 0
    private let capacity: Int
    private var l: [Float], r: [Float]
    private var running = false
    private var rendererFinished = true
    private let stereo: Bool
    private var panL: Float = 1, panR: Float = 1
    var volume: Float = 1
    private var gain: Float = 0
    private(set) var current: MusicMood? = nil
    private(set) var title = ""

    init(stereo: Bool) {
        self.stereo = stereo
        capacity = 4096 * 4
        ring = [Float](repeating: 0, count: capacity * 2)
        l = [Float](repeating: 0, count: 4096)
        r = [Float](repeating: 0, count: 4096)
    }

    func start() {
        running = true
        queue.async { [weak self] in self?.pump() }
    }
    func restart() {}

    var isPlaying: Bool { lock.lock(); defer { lock.unlock() }; return current != nil }

    func setPan(_ a: Float, _ b: Float) { panL = a; panR = b }

    func play(_ score: MusicScore, fadeIn: Float = 2) {
        lock.lock(); current = score.mood; title = score.title; rendererFinished = false; lock.unlock()
        queue.async { [weak self] in self?.renderer.play(score, fadeIn: fadeIn) }
    }

    func stop(fade: Float) {
        lock.lock(); let had = current != nil; current = nil; lock.unlock()
        if had { queue.async { [weak self] in self?.renderer.stop(fade: fade) } }
    }

    func update(_ dt: Float) {
        lock.lock()
        if current != nil && rendererFinished { current = nil }
        lock.unlock()
    }

    // Keeps the ring full (one block per pass, re-queued while running).
    private func pump() {
        guard running else { return }
        lock.lock(); let space = capacity - filled; lock.unlock()
        if space >= block {
            renderer.render(into: &l, &r)
            let fin = renderer.finished
            lock.lock()
            rendererFinished = fin
            for i in 0..<block {
                let j = (writePos + i) % capacity
                if stereo { ring[j * 2] = l[i]; ring[j * 2 + 1] = r[i] } else { let m = (l[i] + r[i]) * 0.5; ring[j * 2] = m; ring[j * 2 + 1] = m }
            }
            writePos = (writePos + block) % capacity
            filled += block
            lock.unlock()
            queue.async { [weak self] in self?.pump() }
        } else {
            queue.asyncAfter(deadline: .now() + 0.03) { [weak self] in self?.pump() }
        }
    }

    // Audio thread: adds up to n frames (silence on underrun).
    func mix(into L: inout [Float], _ R: inout [Float], _ n: Int) {
        lock.lock()
        let take = min(n, filled)
        let target = volume
        for i in 0..<take {
            gain += (target - gain) * 0.001
            let j = (readPos + i) % capacity
            L[i] += ring[j * 2] * gain * panL
            R[i] += ring[j * 2 + 1] * gain * panR
        }
        readPos = (readPos + take) % capacity
        filled -= take
        lock.unlock()
    }
}
