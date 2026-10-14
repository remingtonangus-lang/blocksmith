import Foundation

// Recorded sounds that replace synthesized ones (SND2). A file named after a sound (Snd.name, the list is
// docs/audio/sound-list.md) replaces that sound everywhere, on the Mac and the Quest:
//   <name>.wav and/or <name>_1.wav ... <name>_5.wav    every file found is one take (variant), picked in turn
// Where files are looked for (a later place wins for the same file name):
//   Resources/Sounds/real/ next to the working directory (harness runs, the Quest headless check)
//   the Mac app bundle's Contents/Resources/Sounds/real/ (build.sh copies Resources/Sounds/real there)
//   the Quest APK's assets/sounds/real/ (quest/tools/build-apk.sh copies them; AndroidMain registers them)
//   side-loaded: ~/Library/Application Support/Blocksmith/Sounds/ on the Mac; on the Quest the app's external files
//   folder Sounds/ (adb push x.wav /sdcard/Android/data/com.blocksmith.quest/files/Sounds/) and its internal data folder Sounds/
// Files are decoded by SoundBank.clip (the prewarm thread, never the audio thread): WAV PCM 8/16/24/32-bit or float
// 32/64-bit, any channel count (mixed to mono), any rate (resampled to SoundBank.rate). Each sound's takes share one
// gain that brings them to the loudness of the synthesized sound they replace (the per-sound LUFS that
// docs/status/audio_levels.md lists, measured here with the same BS.1770 gated method), peaks are held under
// -1 dBFS, and repeating events (footsteps, gunshots, hits) get a random +-4% pitch and +-2 dB level per play.
// With no file for a sound the synthesized clip is used exactly as before.
enum RealSounds {
    static let maxVariants = 5
    static let peakCap: Float = 0.891        // -1 dBFS

    private enum Source { case file(String), asset(String) }
    private static let lock = NSLock()
    private static var extraFolders: [String] = []           // side-load folders, in the order added (later wins)
    private static var assetNames: [String] = []
    private static var assetReader: ((String) -> Data?)?
    private static var index: [String: Source]?             // "step_grass_2" -> where its bytes are
    private static var warned = Set<String>()

    // A folder of side-loaded files (the Quest's external files folder). Later folders win.
    static func addFolder(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        if !extraFolders.contains(path) { extraFolders.append(path) }
        index = nil
    }

    // The Quest APK's assets/sounds/real/ files (names only; bytes read on demand through `reader`).
    static func setAssets(_ names: [String], reader: @escaping (String) -> Data?) {
        lock.lock(); defer { lock.unlock() }
        assetNames = names
        assetReader = reader
        index = nil
    }

    // Forgets the folder scan (a newly side-loaded file is found by the next sound that loads).
    static func rescan() { lock.lock(); index = nil; lock.unlock() }

    // Shipped with the build (lowest priority first).
    private static var bundledFolders: [String] {
        var f = [FileManager.default.currentDirectoryPath + "/Resources/Sounds/real"]
        if let r = Bundle.main.resourcePath { f.append(r + "/Sounds/real") }
        return f
    }
    // Side-loaded by the player (win over the shipped files).
    private static var sideFolders: [String] {
        var f: [String] = []
        #if os(macOS)
        f.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Blocksmith/Sounds").path)
        #endif
        return f + extraFolders
    }

    private static func buildIndex() -> [String: Source] {
        var ix: [String: Source] = [:]
        func base(_ file: String) -> String? {
            guard file.lowercased().hasSuffix(".wav"), !file.hasPrefix(".") else { return nil }
            return String(file.dropLast(4))
        }
        func scan(_ d: String) {
            for f in (try? FileManager.default.contentsOfDirectory(atPath: d)) ?? [] { if let b = base(f) { ix[b] = .file(d + "/" + f) } }
        }
        for d in bundledFolders { scan(d) }
        for f in assetNames { if let b = base(f) { ix[b] = .asset(f) } }
        for d in sideFolders { scan(d) }
        if !ix.isEmpty { print("sounds: \(ix.count) recorded files override synthesized sounds") }
        return ix
    }

    // Legacy roster names play the mob family's own files.
    static func fileName(_ s: Snd) -> String {
        switch s {
        case .mobCow: return Snd.mob(.cow, .ambient).name
        case .mobSheep: return Snd.mob(.sheep, .ambient).name
        case .mobChicken: return Snd.mob(.chicken, .ambient).name
        case .mobPig: return Snd.mob(.pig, .ambient).name
        case .mobZombie: return Snd.mob(.zombie, .ambient).name
        case .mobSkeleton: return Snd.mob(.skeleton, .ambient).name
        case .mobSpider: return Snd.mob(.silverfish, .ambient).name
        case .mobSlime: return Snd.mob(.slime, .ambient).name
        case .mobWailer: return Snd.mob(.ghast, .ambient).name
        case .mobCinderwisp: return Snd.mob(.blaze, .ambient).name
        case .mobBoarling: return Snd.mob(.piglin, .ambient).name
        case .mobUndeadBoarling: return Snd.mob(.zombifiedPiglin, .ambient).name
        case .mobVillager: return Snd.mob(.villager, .ambient).name
        case .mobGolem: return Snd.mob(.ironGolem, .ambient).name
        case .mobBlight: return Snd.mob(.wither, .ambient).name
        case .mobVex: return Snd.mob(.vex, .ambient).name
        case .mobRavager: return Snd.mob(.ravager, .ambient).name
        case .mobWolf: return Snd.mob(.wolf, .ambient).name
        case .mobCat: return Snd.mob(.cat, .ambient).name
        case .mobHorse: return Snd.mob(.horse, .ambient).name
        case .mobLlama: return Snd.mob(.llama, .ambient).name
        case .mobBee: return Snd.mob(.bee, .ambient).name
        case .mobWarden: return Snd.mob(.warden, .ambient).name
        default: return s.name
        }
    }

    private static func sources(_ s: Snd) -> [(String, Source)] {
        if case .voice = s { return [] }               // townsfolk lines are recordings already (voices.bin)
        lock.lock()
        if index == nil { index = buildIndex() }
        let ix = index!
        lock.unlock()
        if ix.isEmpty { return [] }
        let n = fileName(s)
        var out: [(String, Source)] = []
        if let src = ix[n] { out.append((n, src)) }
        for k in 1...maxVariants { let v = "\(n)_\(k)"; if let src = ix[v] { out.append((v, src)) } }
        return out
    }

    // How many recorded takes a sound has (0: it stays synthesized).
    static func count(_ s: Snd) -> Int { sources(s).count }

    // The normalised takes for a sound, or nil when it has no recording (or none decodes).
    static func load(_ s: Snd) -> [[Float]]? {
        let src = sources(s)
        if src.isEmpty { return nil }
        lock.lock()
        let reader = assetReader
        lock.unlock()
        var takes: [[Float]] = []
        for (name, where_) in src {
            let data: Data?
            switch where_ {
            case .file(let p): data = FileManager.default.contents(atPath: p)
            case .asset(let a): data = reader?(a)
            }
            guard let d = data, let w = WAVReader.decode(d) else { warn(name, "is not a readable WAV (PCM 8/16/24/32-bit or float)"); continue }
            var x = w.rate == Int(SoundBank.rate) ? w.mono : WAVReader.resample(w.mono, from: Double(w.rate), to: SoundBank.rate)
            if x.count < 16 { warn(name, "is empty"); continue }
            prepare(&x, loop: s.isLoop)
            takes.append(x)
        }
        if takes.isEmpty { return nil }
        normalise(&takes, target: targetLUFS(s))
        return takes
    }

    private static func warn(_ name: String, _ why: String) {
        lock.lock(); let first = warned.insert(name).inserted; lock.unlock()
        if first { print("sounds: \(name).wav \(why); using the synthesized sound") }
    }

    // DC removed; one-shots get a 1 ms fade-in and a 5 ms fade-out so they never click (loops are left seamless).
    private static func prepare(_ x: inout [Float], loop: Bool) {
        var mean: Double = 0
        for v in x { mean += Double(v) }
        let m = Float(mean / Double(x.count))
        if abs(m) > 1e-6 { for i in 0..<x.count { x[i] -= m } }
        if loop { return }
        let fi = min(x.count / 4, Int(0.001 * SoundBank.rate)), fo = min(x.count / 4, Int(0.005 * SoundBank.rate))
        for i in 0..<fi { x[i] *= Float(i) / Float(fi) }
        for i in 0..<fo { x[x.count - 1 - i] *= Float(i) / Float(fo) }
    }

    // Per-category fallbacks (medians of docs/status/audio_levels.md), for a sound whose synthesized take is silent.
    static func categoryLUFS(_ c: SoundCategory) -> Float {
        switch c {
        case .players: return -18
        case .blocks: return -19
        case .ambient: return -20
        case .friendly: return -21
        case .weather: return -21.5
        case .hostile: return -22
        case .ui: return -24
        case .master, .music: return -16
        }
    }

    // The level to match: that of the synthesized sound being replaced (what audio_levels.md records per sound).
    static func targetLUFS(_ s: Snd) -> Float {
        let ref = Loudness.lufs(SoundBank.render(s, variant: 0), rate: Float(SoundBank.rate))
        return ref > -60 ? ref : categoryLUFS(s.category)
    }

    // One gain for all takes (keeps a soft take softer than a hard one), then each take's peak held under -1 dBFS.
    private static func normalise(_ takes: inout [[Float]], target: Float) {
        var power: Float = 0
        var n: Float = 0
        for t in takes { let l = Loudness.lufs(t, rate: Float(SoundBank.rate)); if l > -70 { power += powf(10, l / 10); n += 1 } }
        guard n > 0 else { return }
        let measured = 10 * log10f(power / n)
        let gain = powf(10, (target - measured) / 20)
        for k in 0..<takes.count {
            var peak: Float = 0
            for v in takes[k] { peak = max(peak, abs(v)) }
            let g = peak * gain > peakCap ? peakCap / peak : gain
            for i in 0..<takes[k].count { takes[k][i] *= g }
        }
    }

    // Per-play variation for recordings that repeat (the synthesized takes already differ by design).
    static func pitchJitter() -> Float { Rand.float(in: 0.96...1.04) }
    static func volumeJitter() -> Float { powf(10, Rand.float(in: -2...2) / 20) }
}

extension SoundBank {
    // Footsteps, gunshots and hits: the events a player hears many times a minute.
    static func variesPerPlay(_ s: Snd) -> Bool {
        switch s {
        case .step, .soldierStep, .hoof, .hit, .bulletImpact, .bulletFlesh, .gunDistant, .arrowHit, .tridentHit, .plantBrush,
             .attack, .attackWeak, .attackCrit, .attackSweep, .attackKnockback, .mob(_, .hurt), .babyMob(_, .hurt):
            return true
        case .gun(let k): return k <= 5 || k == 8 || k == 9 || k == WeaponAudio.sidearmSlot || WeaponAudio.ashSlots.contains(k)
        default: return false
        }
    }
}

// Integrated loudness (ITU-R BS.1770: K-weighting, 400 ms blocks with 75% overlap, -70 LUFS absolute and -10 LU
// relative gates; a clip shorter than one block is one block), as tools/audiolevels.py measures audio_levels.md.
enum Loudness {
    static func lufs(_ x: [Float], rate fs: Float) -> Float {
        if x.isEmpty { return -99 }
        // Stage 1: high shelf (+4 dB above ~1.7 kHz); stage 2: RLB high-pass (~38 Hz).
        var y = [Float](repeating: 0, count: x.count)
        let f0: Double = 1681.974450955533, G: Double = 3.999843853973347, Q: Double = 0.7071752369554196
        let K: Double = tan(Double.pi * f0 / Double(fs))
        let KK: Double = K * K
        let KQ: Double = K / Q
        let Vh: Double = pow(10.0, G / 20.0)
        let Vb: Double = pow(Vh, 0.4996667741545416)
        let a0: Double = 1 + KQ + KK
        let s0: Double = (Vh + Vb * KQ + KK) / a0
        let s1: Double = 2 * (KK - Vh) / a0
        let s2: Double = (Vh - Vb * KQ + KK) / a0
        let s3: Double = 2 * (KK - 1) / a0
        let s4: Double = (1 - KQ + KK) / a0
        biquad(x, &y, s0, s1, s2, s3, s4)
        let f1: Double = 38.13547087602444, Q1: Double = 0.5003270373238773
        let K1: Double = tan(Double.pi * f1 / Double(fs))
        let K1K1: Double = K1 * K1
        let b0: Double = 1 + K1 / Q1 + K1K1
        let r3: Double = 2 * (K1K1 - 1) / b0
        let r4: Double = (1 - K1 / Q1 + K1K1) / b0
        var z = [Float](repeating: 0, count: x.count)
        biquad(y, &z, 1, -2, 1, r3, r4)
        let blk = Int(0.4 * fs), hop = Int(0.1 * fs)
        var ms: [Double] = []
        if z.count < blk {
            var s: Double = 0
            for v in z { s += Double(v) * Double(v) }
            ms.append(s / Double(z.count))
        } else {
            var i = 0
            while i + blk <= z.count {
                var s: Double = 0
                for k in i..<(i + blk) { s += Double(z[k]) * Double(z[k]) }
                ms.append(s / Double(blk))
                i += hop
            }
        }
        func L(_ m: Double) -> Double { m > 0 ? -0.691 + 10 * log10(m) : -99 }
        var g = ms.filter { L($0) > -70 }
        if g.isEmpty { return -99 }
        let rel = L(g.reduce(0, +) / Double(g.count)) - 10
        g = g.filter { L($0) > rel }
        if g.isEmpty { return -99 }
        return Float(L(g.reduce(0, +) / Double(g.count)))
    }

    private static func biquad(_ x: [Float], _ y: inout [Float], _ b0: Double, _ b1: Double, _ b2: Double, _ a1: Double, _ a2: Double) {
        var x1: Double = 0, x2: Double = 0, y1: Double = 0, y2: Double = 0
        for i in 0..<x.count {
            let v = Double(x[i])
            let o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = v; y2 = y1; y1 = o
            y[i] = Float(o)
        }
    }
}

// A small RIFF/WAVE reader (no AVFoundation: the Quest shares this path).
enum WAVReader {
    struct Clip { var rate: Int; var mono: [Float] }

    static func decode(_ d: Data) -> Clip? {
        let b = [UInt8](d)
        guard b.count >= 12, b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46,      // "RIFF"
              b[8] == 0x57, b[9] == 0x41, b[10] == 0x56, b[11] == 0x45 else { return nil }  // "WAVE"
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 }
        var format = 0, channels = 0, rate = 0, bits = 0, align = 0
        var dataAt = -1, dataLen = 0
        var o = 12
        while o + 8 <= b.count {
            let id = String(bytes: b[o..<(o + 4)], encoding: .ascii) ?? ""
            var len = u32(o + 4)
            let body = o + 8
            if len > b.count - body { len = b.count - body }           // a streamed/truncated file: take what is there
            if id == "fmt " && len >= 16 {
                format = u16(body); channels = u16(body + 2); rate = u32(body + 4); align = u16(body + 12); bits = u16(body + 14)
                if format == 0xFFFE && len >= 26 { format = u16(body + 24) }   // WAVE_FORMAT_EXTENSIBLE: the sub-format GUID's tag
            } else if id == "data" {
                dataAt = body; dataLen = len
            }
            o = body + len + (len & 1)
        }
        guard dataAt >= 0, channels > 0, rate >= 8000, rate <= 384000 else { return nil }
        let bytes = bits / 8
        guard bytes > 0, align >= channels * bytes else { return nil }
        guard (format == 1 && [1, 2, 3, 4].contains(bytes)) || (format == 3 && (bytes == 4 || bytes == 8)) else { return nil }
        let frames = dataLen / align
        guard frames > 0 else { return nil }
        var out = [Float](repeating: 0, count: frames)
        let inv = 1 / Float(channels)
        for f in 0..<frames {
            var acc: Float = 0
            for c in 0..<channels {
                let p = dataAt + f * align + c * bytes
                var v: Float
                switch (format, bytes) {
                case (1, 1): v = (Float(b[p]) - 128) / 128
                case (1, 2): v = Float(Int16(bitPattern: UInt16(u16(p)))) / 32768
                case (1, 3):
                    let raw = Int32(b[p]) | Int32(b[p + 1]) << 8 | Int32(b[p + 2]) << 16
                    v = Float((raw << 8) >> 8) / 8388608
                case (1, 4): v = Float(Int32(bitPattern: UInt32(u32(p)))) / 2147483648
                case (3, 4): v = Float(bitPattern: UInt32(u32(p)))
                default:
                    var bitsLE: UInt64 = 0
                    for k in 0..<8 { bitsLE |= UInt64(b[p + k]) << (8 * UInt64(k)) }
                    v = Float(Double(bitPattern: bitsLE))
                }
                if !v.isFinite { v = 0 }
                acc += v
            }
            out[f] = acc * inv
        }
        return Clip(rate: rate, mono: out)
    }

    // Band-limited resampling (Lanczos, 8 lobes; the cutoff follows the lower rate so downsampling doesn't alias).
    static func resample(_ x: [Float], from inRate: Double, to outRate: Double) -> [Float] {
        let ratio = inRate / outRate                     // input frames per output frame
        let n = Int(Double(x.count) / ratio)
        guard n > 1 else { return x }
        let cut = min(1, 1 / ratio)                      // normalised cutoff (1 = the input Nyquist)
        let a = 8.0
        let half = Int((a / cut).rounded(.up))
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) * ratio
            let c = Int(t)
            var s: Double = 0, w: Double = 0
            for k in (c - half + 1)...(c + half) {
                guard k >= 0 && k < x.count else { continue }
                let d = (t - Double(k)) * cut
                let wk: Double
                if abs(d) < 1e-9 { wk = 1 } else if abs(d) >= a { wk = 0 } else {
                    let pd = Double.pi * d
                    wk = a * sin(pd) * sin(pd / a) / (pd * pd)
                }
                s += Double(x[k]) * wk
                w += wk
            }
            out[i] = w != 0 ? Float(s / w) : 0
        }
        return out
    }
}
