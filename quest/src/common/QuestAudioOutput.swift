import Foundation
#if os(Android)
import CAndroidGlue
#endif

// Plays the software mixer (QuestSound.swift) through AAudio on the headset: a low-latency float stereo stream whose
// callback pulls frames from SoundEngine.render. No-op elsewhere.
final class QuestAudioOutput {
    static let shared = QuestAudioOutput()
    // RMS of the last mixed buffer (0...1), smoothed: the voice notes' detector hears the game through the mic.
    static var level: Float = 0
    fileprivate var engine: SoundEngine?
    #if os(Android)
    private var stream: OpaquePointer?
    #endif

    func start(_ e: SoundEngine?) {
        engine = e
        #if os(Android)
        guard stream == nil, e != nil else { return }
        var builder: OpaquePointer?
        guard AAudio_createStreamBuilder(&builder) == aaudio_result_t(AAUDIO_OK), let b = builder else { print("audio: no stream builder"); return }
        AAudioStreamBuilder_setFormat(b, aaudio_format_t(AAUDIO_FORMAT_PCM_FLOAT))
        AAudioStreamBuilder_setChannelCount(b, 2)
        AAudioStreamBuilder_setSampleRate(b, Int32(SoundBank.rate))
        AAudioStreamBuilder_setPerformanceMode(b, aaudio_performance_mode_t(AAUDIO_PERFORMANCE_MODE_LOW_LATENCY))
        AAudioStreamBuilder_setSharingMode(b, aaudio_sharing_mode_t(AAUDIO_SHARING_MODE_SHARED))
        AAudioStreamBuilder_setDataCallback(b, { _, user, data, frames in
            guard let user else { return aaudio_data_callback_result_t(AAUDIO_CALLBACK_RESULT_CONTINUE) }
            let out = Unmanaged<QuestAudioOutput>.fromOpaque(user).takeUnretainedValue()
            let p = data.assumingMemoryBound(to: Float.self)
            if let e = out.engine { e.render(p, frames: Int(frames)) } else { p.initialize(repeating: 0, count: Int(frames) * 2) }
            var sum: Float = 0
            for i in 0..<Int(frames) * 2 { sum += p[i] * p[i] }
            let rms = frames > 0 ? (sum / Float(frames * 2)).squareRoot() : 0
            QuestAudioOutput.level = max(rms, QuestAudioOutput.level * 0.9)
            return aaudio_data_callback_result_t(AAUDIO_CALLBACK_RESULT_CONTINUE)
        }, Unmanaged.passUnretained(self).toOpaque())
        var s: OpaquePointer?
        let r = AAudioStreamBuilder_openStream(b, &s)
        _ = AAudioStreamBuilder_delete(b)
        guard r == aaudio_result_t(AAUDIO_OK), let st = s else { print("audio: openStream failed \(r)"); return }
        stream = st
        let sr = AAudioStream_getSampleRate(st)
        _ = AAudioStream_requestStart(st)
        print("audio: AAudio stream started, \(sr) Hz, burst \(AAudioStream_getFramesPerBurst(st)) frames")
        #endif
    }

    func pause(_ on: Bool) {
        #if os(Android)
        guard let st = stream else { return }
        if on { _ = AAudioStream_requestPause(st) } else { _ = AAudioStream_requestStart(st) }
        #endif
    }

    func stop() {
        #if os(Android)
        if let st = stream { _ = AAudioStream_requestStop(st); _ = AAudioStream_close(st); stream = nil }
        #endif
        engine = nil
    }
}
