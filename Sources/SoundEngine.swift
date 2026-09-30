import Foundation
import AVFoundation
import simd

// Volume sliders (persisted in UserDefaults). Master and music keep the original keys so old settings carry over.
enum AudioSettings {
    private static var cache: [SoundCategory: Float] = [:]
    static func volume(_ c: SoundCategory) -> Float {
        if let v = cache[c] { return v }
        let d = UserDefaults.standard
        let key = c == .master ? "volume" : (c == .music ? "musicVolume" : c.key)
        let v: Float = d.object(forKey: key) == nil ? (c == .master ? 0.8 : 1) : d.float(forKey: key)
        cache[c] = v
        return v
    }
    static func set(_ c: SoundCategory, _ v: Float) {
        cache[c] = v
        UserDefaults.standard.set(v, forKey: c == .master ? "volume" : (c == .music ? "musicVolume" : c.key))
    }
    // Gain for one sound: its category times master.
    static func gain(_ s: Snd) -> Float { volume(.master) * volume(s.category) }
}

// AVAudioEngine front end: 3D sources through an environment node (distance rolloff, panning, obstruction,
// cave reverb), flat sources for the player's own sounds, an interface bus that is never muffled, looping
// emitters, an underwater low-pass, and the streaming music player.
final class SoundEngine {
    let engine = AVAudioEngine()
    let env = AVAudioEnvironmentNode()
    let pre = AVAudioMixerNode()                        // world mix (3D + flat) before the underwater filter
    let eq = AVAudioUnitEQ(numberOfBands: 1)
    let bank = SoundBank()
    let mono: AVAudioFormat
    let stereo: AVAudioFormat
    private var spatial: [AVAudioPlayerNode] = []      // one-shots with a world position
    private var spatialPos: [V3?] = []                 // world position per spatial node (re-aimed as the listener turns)
    private var spatialRange: [Float] = []
    private var spatialEnd: [Double] = []              // when each spatial voice's current sound ends
    private var spatialGain: [Float] = []              // how loud it started (quiet voices are stolen first)
    private var flat: [AVAudioPlayerNode] = []         // one-shots at the listener (own steps, hurt...)
    private var ui: [AVAudioPlayerNode] = []           // interface clicks: never filtered
    private var buffers: [Snd: [AVAudioPCMBuffer]] = [:]
    private var nextSpatial = 0, nextFlat = 0, nextUI = 0, variant = 0
    private(set) var music: MusicStream?
    private(set) var disc: MusicStream?          // jukebox discs: mono, positional, through the environment node
    private var discPos: V3? = nil

    // Listener state (world space) and environment.
    private var eye = V3.zero, fwd = V3(0, 0, -1), right = V3(1, 0, 0), up = V3(0, 1, 0)
    private(set) var cave: Float = 0          // 0 open air ... 1 deep cave (drives reverb)
    private var underwater = false
    private var eqCutoff: Float = 20000
    private var roomPreset = -1

    // Looping emitters keyed by name ("fire", "lava", "rain", ...).
    final class Loop {
        let node = AVAudioPlayerNode()
        var snd: Snd
        var target: Float = 0, level: Float = 0
        var pos: V3? = nil
        var started = false
        var positional: Bool
        init(_ s: Snd, positional: Bool) { snd = s; self.positional = positional }
    }
    private var loops: [String: Loop] = [:]

    var volume: Float {
        get { AudioSettings.volume(.master) }
        set { AudioSettings.set(.master, newValue) }
    }
    var enabled = true
    var musicDuck: Float = 1                  // 0 while a jukebox plays nearby

    init?() {
        guard let m = AVAudioFormat(standardFormatWithSampleRate: SoundBank.rate, channels: 1),
              let s = AVAudioFormat(standardFormatWithSampleRate: SoundBank.rate, channels: 2) else { return nil }
        mono = m; stereo = s
        engine.attach(env)
        engine.attach(pre)
        engine.attach(eq)
        env.distanceAttenuationParameters.distanceAttenuationModel = .linear
        env.distanceAttenuationParameters.referenceDistance = 1.5
        env.distanceAttenuationParameters.maximumDistance = 16
        env.distanceAttenuationParameters.rolloffFactor = 1
        env.reverbParameters.enable = true
        env.reverbParameters.loadFactoryReverbPreset(.mediumHall)
        env.reverbParameters.level = -40
        env.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        env.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
        eq.bands[0].filterType = .lowPass
        eq.bands[0].frequency = 20000
        eq.bands[0].bandwidth = 0.5
        eq.bands[0].bypass = false
        engine.connect(env, to: pre, format: stereo)
        engine.connect(pre, to: eq, format: stereo)
        engine.connect(eq, to: engine.mainMixerNode, format: stereo)
        for _ in 0..<16 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: env, format: mono)
            p.renderingAlgorithm = .equalPowerPanning
            spatial.append(p); spatialPos.append(nil); spatialRange.append(16); spatialEnd.append(0); spatialGain.append(0)
        }
        for _ in 0..<6 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: pre, format: mono)
            flat.append(p)
        }
        for _ in 0..<4 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: mono)
            ui.append(p)
        }
        let ms = MusicStream(format: stereo)
        engine.attach(ms.node)
        engine.connect(ms.node, to: engine.mainMixerNode, format: stereo)
        music = ms
        let ds = MusicStream(format: mono)
        engine.attach(ds.node)
        engine.connect(ds.node, to: env, format: mono)
        ds.node.renderingAlgorithm = .equalPowerPanning
        disc = ds
        engine.mainMixerNode.outputVolume = 1
        do { try engine.start() } catch { print("audio disabled: \(error)"); return nil }
        for p in spatial + flat + ui { p.play() }
        ms.node.play()
        ms.start()
        ds.node.play()
        ds.start()
        // Output device changes (headphones, a TV over HDMI/AirPlay) stop the engine: restart and re-prime everything.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.restartAfterDeviceChange()
        }
        bank.prewarm(SoundBank.commonSounds + [.explode, .thunder, .lightning, .caveAmbience, .caveDrip, .caveWind, .levelUp, .totem, .playerDeath])
    }

    // MARK: Listener / environment

    // Called once per tick with the camera; `cave` 0...1 drives the reverb, `underwater` the low-pass.
    func setListener(eye e: V3, yaw: Float, pitch: Float, cave c: Float, underwater w: Bool) {
        eye = e
        fwd = V3(-sinf(yaw) * cosf(pitch), sinf(pitch), -cosf(yaw) * cosf(pitch))
        right = V3(cosf(yaw), 0, -sinf(yaw))
        up = simd_cross(right, fwd)
        if abs(c - cave) > 0.01 {
            cave = c
            env.reverbParameters.level = -40 + 36 * c
        }
        if w != underwater {
            underwater = w
        }
        let want: Float = underwater ? 450 : 20000
        if abs(want - eqCutoff) > 1 {
            eqCutoff += (want - eqCutoff) * 0.35
            if abs(want - eqCutoff) < 20 { eqCutoff = want }
            eq.bands[0].frequency = eqCutoff
        }
        // Re-aim the spatial one-shots that are still playing and the loops.
        let now = CFAbsoluteTimeGetCurrent()
        for i in 0..<spatial.count where spatialEnd[i] > now { if let p = spatialPos[i] { spatial[i].position = point(p, range: spatialRange[i]) } }
        for l in loops.values where l.positional { if let p = l.pos { l.node.position = point(p, range: 16) } }
        if let p = discPos, let d = disc { d.node.position = point(p, range: 64); d.node.reverbBlend = 0.05 + 0.4 * cave }
    }

    // Where the playing jukebox is (nil stops it); volume is the Blocks category.
    func setDisc(at p: V3?, occlusion: Float = 0) {
        discPos = p
        guard let d = disc else { return }
        if let p = p {
            d.node.position = point(p, range: 64)
            d.node.obstruction = -32 * occlusion
            d.node.occlusion = -18 * occlusion
            d.volume = AudioSettings.volume(.master) * AudioSettings.volume(.blocks) * 1.2
        }
    }

    // Picks a reverb character for the space: small room, chamber, hall, cathedral-like cavern.
    func setRoom(size: Float, enclosure: Float) {
        let bucket: Int = enclosure < 0.35 ? 0 : (size < 5 ? 1 : (size < 10 ? 2 : (size < 16 ? 3 : 4)))
        guard bucket != roomPreset else { return }
        roomPreset = bucket
        let presets: [AVAudioUnitReverbPreset] = [.mediumHall, .smallRoom, .mediumChamber, .largeHall, .cathedral]
        env.reverbParameters.loadFactoryReverbPreset(presets[bucket])
    }

    // World position -> listener space (listener at the origin looking down -Z). `range` scales the distance
    // so louder sounds carry further with the fixed attenuation curve.
    private func point(_ p: V3, range: Float) -> AVAudio3DPoint {
        let rel = p - eye
        let k = 16 / max(1, range)
        return AVAudio3DPoint(x: simd_dot(rel, right) * k, y: simd_dot(rel, up) * k, z: -simd_dot(rel, fwd) * k)
    }

    // MARK: One-shots

    private func buffer(_ s: Snd, variant v: Int) -> AVAudioPCMBuffer? {
        if let list = buffers[s], !list.isEmpty { return list[v % list.count] }
        var list: [AVAudioPCMBuffer] = []
        for k in 0..<SoundBank.variants(for: s) {
            let data = bank.clip(s, variant: k)
            guard !data.isEmpty, let b = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(data.count)), let ch = b.floatChannelData else { continue }
            b.frameLength = AVAudioFrameCount(data.count)
            data.withUnsafeBufferPointer { src in ch[0].update(from: src.baseAddress!, count: data.count) }
            list.append(b)
        }
        buffers[s] = list
        bank.evict(s)
        return list.isEmpty ? nil : list[v % list.count]
    }

    // Plays a sound. With a world position it is spatialized; `occlusion` 0...1 (solid blocks in the way) muffles it.
    func play(_ s: Snd, volume v: Float = 1, at pos: V3? = nil, occlusion: Float = 0) {
        guard enabled else { return }
        let gain = v * AudioSettings.gain(s)
        if gain <= 0.001 { return }
        if let p = pos {
            let d = simd_length(p - eye)
            let range = max(16 * max(1, v), s.range)
            if d > range { return }
        }
        variant += 1
        guard let buf = buffer(s, variant: variant) else { return }
        if s.category == .ui {
            let node = ui[nextUI]; nextUI = (nextUI + 1) % ui.count
            node.volume = gain
            node.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
            if !node.isPlaying { node.play() }
            return
        }
        guard let p = pos else {
            let node = flat[nextFlat]; nextFlat = (nextFlat + 1) % flat.count
            node.volume = min(1.5, gain)
            node.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
            if !node.isPlaying { node.play() }
            return
        }
        // Voice allocation: a free voice, else the quietest one that ends soonest.
        let now = CFAbsoluteTimeGetCurrent()
        let d = simd_length(p - eye)
        let loud = gain * max(0, 1 - d / max(16 * max(1, v), s.range))
        var i = -1
        for k in 0..<spatial.count {
            let c = (nextSpatial + k) % spatial.count
            if spatialEnd[c] <= now { i = c; break }
        }
        if i < 0 {
            var best: Float = .greatestFiniteMagnitude
            for k in 0..<spatial.count {
                let left = Float(spatialEnd[k] - now)
                let score = spatialGain[k] * min(left, 2)
                if score < best { best = score; i = k }
            }
            if spatialGain[i] > loud * 2 { return }         // everything playing matters more than this
        }
        nextSpatial = (i + 1) % spatial.count
        spatialEnd[i] = now + Double(buf.frameLength) / SoundBank.rate
        spatialGain[i] = loud
        let node = spatial[i]
        let range = max(16 * max(1, v), s.range)
        spatialPos[i] = p; spatialRange[i] = range
        node.position = point(p, range: range)
        node.volume = min(1.5, gain)
        node.reverbBlend = 0.06 + 0.5 * cave
        node.obstruction = -32 * occlusion
        node.occlusion = -18 * occlusion
        node.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
        if !node.isPlaying { node.play() }
    }

    // MARK: Loops

    // Keeps a looping emitter alive with the given target volume; call every tick, volume 0 fades it out.
    func loop(_ key: String, _ s: Snd, volume v: Float, at pos: V3? = nil, occlusion: Float = 0) {
        guard enabled else { return }
        let l: Loop
        if let e = loops[key] {
            l = e
            if e.snd != s { e.snd = s; e.started = false; e.node.stop() }
        } else {
            l = Loop(s, positional: pos != nil)
            engine.attach(l.node)
            let dest: AVAudioNode = pos != nil ? env : pre
            engine.connect(l.node, to: dest, format: mono)
            if pos != nil { l.node.renderingAlgorithm = .equalPowerPanning }
            loops[key] = l
        }
        l.target = v * AudioSettings.gain(s)
        l.pos = pos
        if !l.started {
            guard let buf = buffer(s, variant: 0) else { return }
            l.node.scheduleBuffer(buf, at: nil, options: [.loops, .interrupts], completionHandler: nil)
            l.node.volume = 0
            l.node.play()
            l.started = true
        }
        if l.positional, let p = pos {
            l.node.position = point(p, range: 16)
            l.node.reverbBlend = 0.05 + 0.4 * cave
            l.node.obstruction = -32 * occlusion
            l.node.occlusion = -18 * occlusion
        }
    }

    // Fades loop levels toward their targets; loops nobody asked for this tick fade out and stop.
    func update(_ dt: Float, asked: Set<String>) {
        var dead: [String] = []
        for (k, l) in loops {
            if !asked.contains(k) { l.target = 0 }
            let rate: Float = l.target > l.level ? 2.5 : 3.5
            let step = dt * rate
            if abs(l.target - l.level) <= step { l.level = l.target } else { l.level += l.target > l.level ? step : -step }
            l.node.volume = min(1.5, l.level)
            if l.level <= 0.0005 && l.target <= 0 {
                l.node.stop()
                l.started = false
                if !asked.contains(k) { dead.append(k) }
            }
        }
        for k in dead {
            if let l = loops[k] { engine.detach(l.node); loops[k] = nil }
        }
        music?.volume = AudioSettings.volume(.master) * AudioSettings.volume(.music) * musicDuck
        music?.update(dt)
    }

    var loopCount: Int { loops.count }

    func restartAfterDeviceChange() {
        do { try engine.start() } catch { print("audio restart failed: \(error)"); return }
        for p in spatial + flat + ui { p.play() }
        for i in 0..<spatialEnd.count { spatialEnd[i] = 0 }
        for l in loops.values { l.node.stop(); l.started = false; l.level = 0 }     // re-scheduled on the next tick
        music?.restart()
        disc?.restart()
    }

    func stopAll() {
        for p in spatial + flat + ui { p.stop(); p.play() }
        for l in loops.values { l.node.stop(); l.started = false; l.level = 0; l.target = 0 }
        music?.stop(fade: 0.5)
    }
}
