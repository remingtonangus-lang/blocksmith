import Foundation
import CAndroidGlue

// P359 (a): decodes one soundtrack file from the APK (assets/music/<name>.m4a, stored uncompressed so the extractor
// reads it straight from the APK by file descriptor) with the NDK's AMediaExtractor + AMediaCodec, a block at a time,
// on QuestTrackDeck's background queue.
final class MediaTrackDecoder: TrackDecoder {
    private let extractor: OpaquePointer
    private let codec: OpaquePointer
    private let fd: Int32
    private(set) var sampleRate = 48000
    private var channels = 2
    private var floatPCM = false
    private var inputDone = false
    private var outputDone = false
    private var pending: [Float] = []              // decoded interleaved stereo not yet handed out
    private var pendingPos = 0

    init?(_ mgr: OpaquePointer, _ path: String) {
        guard let a = AAssetManager_open(mgr, path, Int32(AASSET_MODE_UNKNOWN)) else { return nil }
        var start: off64_t = 0, len: off64_t = 0
        let fd = AAsset_openFileDescriptor64(a, &start, &len)
        AAsset_close(a)
        guard fd >= 0 else { return nil }
        guard let ex = AMediaExtractor_new() else { close(fd); return nil }
        guard AMediaExtractor_setDataSourceFd(ex, fd, start, len) == AMEDIA_OK, let fmt = AMediaExtractor_getTrackFormat(ex, 0) else {
            AMediaExtractor_delete(ex); close(fd); return nil
        }
        defer { AMediaFormat_delete(fmt) }
        var mime: UnsafePointer<CChar>? = nil
        var rate: Int32 = 48000, ch: Int32 = 2
        _ = AMediaFormat_getInt32(fmt, AMEDIAFORMAT_KEY_SAMPLE_RATE, &rate)
        _ = AMediaFormat_getInt32(fmt, AMEDIAFORMAT_KEY_CHANNEL_COUNT, &ch)
        guard AMediaFormat_getString(fmt, AMEDIAFORMAT_KEY_MIME, &mime), let mime,
              let c = AMediaCodec_createDecoderByType(mime) else {
            AMediaExtractor_delete(ex); close(fd); return nil
        }
        guard AMediaExtractor_selectTrack(ex, 0) == AMEDIA_OK, AMediaCodec_configure(c, fmt, nil, nil, 0) == AMEDIA_OK,
              AMediaCodec_start(c) == AMEDIA_OK else {
            AMediaCodec_delete(c); AMediaExtractor_delete(ex); close(fd); return nil
        }
        extractor = ex
        codec = c
        self.fd = fd
        sampleRate = Int(rate)
        channels = max(1, Int(ch))
    }

    deinit {
        AMediaCodec_stop(codec)
        AMediaCodec_delete(codec)
        AMediaExtractor_delete(extractor)
        close(fd)
    }

    func read(_ out: inout [Float], frames: Int) -> Int {
        var n = 0
        var spins = 0
        while n < frames {
            if pendingPos < pending.count {
                let take = min(frames - n, (pending.count - pendingPos) / 2)
                for i in 0..<take {
                    out[(n + i) * 2] = pending[pendingPos + i * 2]
                    out[(n + i) * 2 + 1] = pending[pendingPos + i * 2 + 1]
                }
                pendingPos += take * 2
                n += take
                continue
            }
            if outputDone { break }
            feed()
            if !drain() {
                spins += 1
                if spins > 200 { break }               // the codec is stuck: hand back what there is
            }
        }
        return n
    }

    // Queues compressed samples while the codec has free input buffers.
    private func feed() {
        while !inputDone {
            let idx = AMediaCodec_dequeueInputBuffer(codec, 0)
            if idx < 0 { return }
            var cap = 0
            guard let buf = AMediaCodec_getInputBuffer(codec, idx, &cap) else { return }
            let size = AMediaExtractor_readSampleData(extractor, buf, cap)
            if size < 0 {
                AMediaCodec_queueInputBuffer(codec, idx, 0, 0, 0, UInt32(4))          // end of stream
                inputDone = true
                return
            }
            let t = AMediaExtractor_getSampleTime(extractor)
            AMediaCodec_queueInputBuffer(codec, idx, 0, size, UInt64(max(0, t)), 0)
            _ = AMediaExtractor_advance(extractor)
        }
    }

    // Takes one decoded buffer into `pending` (as stereo float). False when none was ready.
    private func drain() -> Bool {
        var info = AMediaCodecBufferInfo()
        let idx = AMediaCodec_dequeueOutputBuffer(codec, &info, 2000)
        if idx == -2 {                                          // the output format changed
            if let f = AMediaCodec_getOutputFormat(codec) {
                var v: Int32 = 0
                if AMediaFormat_getInt32(f, AMEDIAFORMAT_KEY_SAMPLE_RATE, &v), v > 0 { sampleRate = Int(v) }
                if AMediaFormat_getInt32(f, AMEDIAFORMAT_KEY_CHANNEL_COUNT, &v), v > 0 { channels = Int(v) }
                if AMediaFormat_getInt32(f, AMEDIAFORMAT_KEY_PCM_ENCODING, &v) { floatPCM = v == 4 }
                AMediaFormat_delete(f)
            }
            return true
        }
        if idx < 0 { return idx == -3 }
        if info.flags & 4 != 0 { outputDone = true }
        var size = 0
        if info.size > 0, let buf = AMediaCodec_getOutputBuffer(codec, idx, &size) {
            let base = buf + Int(info.offset)
            let ch = channels
            pending.removeAll(keepingCapacity: true)
            pendingPos = 0
            if floatPCM {
                let frames = Int(info.size) / (4 * ch)
                base.withMemoryRebound(to: Float.self, capacity: frames * ch) { p in
                    for i in 0..<frames {
                        let l = p[i * ch], r = ch > 1 ? p[i * ch + 1] : l
                        pending.append(l); pending.append(r)
                    }
                }
            } else {
                let frames = Int(info.size) / (2 * ch)
                base.withMemoryRebound(to: Int16.self, capacity: frames * ch) { p in
                    for i in 0..<frames {
                        let l = Float(p[i * ch]) / 32768, r = ch > 1 ? Float(p[i * ch + 1]) / 32768 : l
                        pending.append(l); pending.append(r)
                    }
                }
            }
        }
        AMediaCodec_releaseOutputBuffer(codec, idx, false)
        return true
    }
}

extension MediaTrackDecoder {
    // P390: a whole packed sound effect (assets/sounds/real/<name>.ogg, stored uncompressed in the APK), decoded at once
    // and mixed to mono, at the codec's rate (RealSounds trims and resamples it).
    static func decodeAll(_ mgr: OpaquePointer, _ path: String) -> WAVReader.Clip? {
        guard let d = MediaTrackDecoder(mgr, path) else { return nil }
        var out: [Float] = []
        var buf = [Float](repeating: 0, count: 8192)
        while true {
            let n = d.read(&buf, frames: 4096)
            if n == 0 { break }
            for i in 0..<n { out.append((buf[i * 2] + buf[i * 2 + 1]) * 0.5) }
        }
        return out.isEmpty ? nil : WAVReader.Clip(rate: d.sampleRate, mono: out)
    }
}

// Lists assets/music and hands QuestTrackDeck its decoder factory.
func registerSoundtrack(_ mgr: OpaquePointer?) {
    guard let mgr, let dir = AAssetManager_openDir(mgr, "music") else { return }
    var names: Set<String> = []
    while let n = AAssetDir_getNextFileName(dir) {
        let s = String(cString: n)
        if s.hasSuffix(".m4a") { names.insert(String(s.dropLast(4))) }
    }
    AAssetDir_close(dir)
    if names.isEmpty { return }
    QuestTrackDeck.names = names
    QuestTrackDeck.open = { name in MediaTrackDecoder(mgr, "music/" + name + ".m4a") }
}
