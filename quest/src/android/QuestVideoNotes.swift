#if VOICE_NOTES
import Foundation
import CVulkan
import CAndroidGlue

// P368 (Oct 17 20:59: "voice notes get video"), playtest builds only (STORE=1 leaves it out with the rest of the
// voice-note code). While Bug Notes listens, about 30 times a second the frame thread blits the left eye (after the
// eye pass, the HUD panel included) on the GPU (QuestScreenshot.record into a staging buffer, no CPU copy on the frame
// thread; the whole eye since Nov 13, a quarter of it each way before) and a utility queue, once that frame's fence
// has signalled, turns it into NV12 in the hardware H.264 encoder's input (quest/c/voice/voicevideo.c: a keyframe
// every second), which keeps the last 10 s of packets in memory. Nothing is written while he is silent. When a note starts,
// vn-<stamp>.mp4 gets the buffered 10 s and then everything until 2 s after the note ends (BugNotes lists it in the
// sidecar). Options > Interface > Bug Note Video turns it off for performance runs. The cost is logged every 10 s
// ("voicevideo: frame thread ... ms"): the frame-thread recording time and the GPU blit share the frame; conversion
// and encoding run on the utility queue and the encoder block.
enum QuestVideo {
    static let fps = 30.0
    // Nov 13 (Remington, 14:48: "Why doesn't the recorder capture at higher resolution", "I want it at max resolution";
    // ledger 120): the clip was a quarter of the left eye each way (384x416 on the headset, ~2 Mb/s). It is the whole
    // eye now, every pixel the game drew: the GPU copy is the same one blit (full size), the conversion to the
    // encoder's picture is NEON in C straight into its input buffer (voicevideo.c; the Swift loop and a copy are
    // gone), still on the utility queue, and the bit rate goes by the picture's size (0.2 bits a pixel a picture,
    // 4 to 24 Mb/s). Three pictures in flight, not four (each is 12 MB at this size). An encoder that will not open
    // at a size halves it (full, half, quarter). BS_VIDEOSCALE=4: the quarter picture, as before.
    static var scale: Int = max(1, min(4, ProcessInfo.processInfo.environment["BS_VIDEOSCALE"].flatMap { Int($0) } ?? 1))
    static func bitrate(_ w: Int, _ h: Int) -> Int32 { Int32(max(4_000_000, min(24_000_000, Double(w * h) * fps * 0.2))) }
    static let window: Int32 = 10              // seconds buffered before a note
    static let tail = 2.0                      // seconds after a note

    private final class Entry {
        let st: QuestScreenshot.Staging
        var slot: SceneRenderer.Slot?
        var ctx: VkContext?
        var pts: Int64 = 0
        var busy = false                       // its buffer is being converted (under lock)
        init(_ st: QuestScreenshot.Staging) { self.st = st }
    }

    private static let lock = NSLock()
    private static var entries: [Entry] = []
    private static var lastAt = 0.0
    private static var unsupported = false
    private static var wanted = false          // BugNotes listening and the toggle on (set by tick)
    private static let queue = DispatchQueue(label: "blocksmith.voicevideo", qos: .utility)

    // Queue-owned.
    private static var enc: UnsafeMutableRawPointer?
    private static var encW = 0, encH = 0
    private static var clipGen = 0

    // Cost (frame thread, then the utility queue), logged every 10 s.
    private static var recSum = 0.0, recN = 0, convSum = 0.0, convN = 0, dropped = 0, lastLog = 0.0

    // From BugNotes.tick, once a frame: video wanted or not. Turning it off frees the encoder and its buffer.
    static func tick(listening: Bool) {
        let want = listening && Settings.shared.bugNoteVideo && !unsupported
        lock.lock(); let was = wanted; wanted = want; lock.unlock()
        if was && !want { queue.async { if let e = enc { bs_venc_close(e); enc = nil } } }
        let now = CFAbsoluteTimeGetCurrent()
        if want && now - lastLog > 10 {
            lastLog = now
            lock.lock()
            let r = recN > 0 ? recSum / Double(recN) * 1000 : 0, c = convN > 0 ? convSum / Double(convN) * 1000 : 0
            let n = convN, d = dropped
            recSum = 0; recN = 0; convSum = 0; convN = 0; dropped = 0
            lock.unlock()
            print(String(format: "voicevideo: frame thread %.3f ms a capture; convert + encode %.2f ms on the queue; %d pictures, %d dropped in 10 s",
                         r, c, n, d))
        }
    }

    // MARK: Frame thread

    // After the eye pass (and QuestScreenshot.service), before submit: records a capture when one is due.
    // Nov 12 playtest (the coordinator's relay: "only the top-left ~60% of each recorded frame is clean"): with dynamic
    // resolution on (P498) the eye pass draws only the top-left `drawn` part of the eye image; the video blitted the
    // whole image, the stale rest of it included. It now blits the drawn part to the whole picture (the staging keeps
    // the full image's size, so a changing resolution reallocates nothing). BS_OLDVIDEOAREA=1: the whole image.
    static let oldArea = ProcessInfo.processInfo.environment["BS_OLDVIDEOAREA"] == "1"
    static func service(_ s: SceneRenderer.Slot, ctx: VkContext, image: VkImage, format: VkFormat, width: Int, height: Int,
                        drawn: (Int, Int)? = nil) {
        lock.lock(); let want = wanted; lock.unlock()
        guard want, width >= 512, height >= 256 else { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        guard t0 - lastAt >= 1 / fps - 0.004 else { return }
        let fourByte: [VkFormat] = [VK_FORMAT_R8G8B8A8_SRGB, VK_FORMAT_B8G8R8A8_SRGB, VK_FORMAT_R8G8B8A8_UNORM, VK_FORMAT_B8G8R8A8_UNORM]
        guard fourByte.contains(format) else { unsupported = true; print("voicevideo: eye format \(format.rawValue) not supported"); return }
        // The eye over `scale` (1: all of it), rows a multiple of 128 bytes wide and the height of 32 (no encoder padding).
        lock.lock(); let k = scale; lock.unlock()
        let w = max(256, width / k / 128 * 128), h = max(128, height / k / 32 * 32)
        if entries.first.map({ $0.st.srcW != width || $0.st.srcH != height || $0.st.format != format || $0.st.w != w || $0.st.h != h }) ?? true {
            lock.lock(); let idle = !entries.contains { $0.busy || $0.slot != nil }; lock.unlock()
            guard idle else { return }
            do {
                entries = try (0..<(k == 1 ? 3 : 4)).map { _ in Entry(try QuestScreenshot.Staging(ctx: ctx, srcW: width, srcH: height, format: format, w: w, h: h, forceCopy: false)) }
            } catch { unsupported = true; print("voicevideo: staging: \(error)"); return }
            if !entries[0].st.blit { unsupported = true; entries = []; print("voicevideo: no GPU blit from the eye image: video off"); return }
        }
        lock.lock()
        let free = entries.first { !$0.busy && $0.slot == nil }
        if free == nil { dropped += 1 }
        lock.unlock()
        guard let e = free else { return }
        QuestScreenshot.record(s.cmd, e.st, image: image, region: oldArea ? nil : drawn)
        e.slot = s; e.ctx = ctx; e.pts = Int64(t0 * 1_000_000)
        lastAt = t0
        let dt = CFAbsoluteTimeGetCurrent() - t0
        lock.lock(); recSum += dt; recN += 1; lock.unlock()
    }

    // Right after scene.beginFrame() (like QuestScreenshot.collect): captures whose frame has completed go to the queue.
    static func collect(began: SceneRenderer.Slot?) {
        for e in entries {
            guard let slot = e.slot, let ctx = e.ctx else { continue }
            if began !== slot { guard vkGetFenceStatus(ctx.device, slot.fence) == VK_SUCCESS else { continue } }
            e.slot = nil
            lock.lock(); e.busy = true; lock.unlock()
            let pts = e.pts, st = e.st
            queue.async {
                let t0 = CFAbsoluteTimeGetCurrent()
                QuestVideo.encode(st, pts: pts)
                let dt = CFAbsoluteTimeGetCurrent() - t0
                lock.lock(); e.busy = false; convSum += dt; convN += 1; lock.unlock()
            }
        }
    }

    // MARK: Queue

    private static func encode(_ st: QuestScreenshot.Staging, pts: Int64) {
        guard let mapped = st.buffer.mapped else { return }
        let w = st.w, h = st.h
        if enc == nil || encW != w || encH != h {
            if let e = enc { bs_venc_close(e) }
            enc = bs_venc_open(Int32(w), Int32(h), Int32(fps), bitrate(w, h), 1, window)
            encW = w; encH = h
            if enc == nil {
                // (no encoder at this size: the next captures are half of it, down to the quarter picture)
                lock.lock()
                if scale < 4 { scale *= 2; print("voicevideo: no encoder at \(w)x\(h): 1/\(scale) of the eye from here") } else { unsupported = true }
                lock.unlock()
                encW = 0; encH = 0
                return
            }
        }
        let src = UnsafePointer(mapped.bindMemory(to: UInt8.self, capacity: w * h * 4))
        _ = bs_venc_frame_rgba(enc, src, Int32(w * 4), pts)
    }

    // RGBA8 display values -> NV12 (BT.601, limited range), chroma from each 2x2 block's mean.
    static func toNV12(_ p: UnsafePointer<UInt8>, _ w: Int, _ h: Int, _ out: UnsafeMutablePointer<UInt8>) {
        for y in 0..<h {
            var i = y * w * 4
            let row = out + y * w
            for x in 0..<w {
                let r = Int(p[i]), g = Int(p[i + 1]), b = Int(p[i + 2])
                row[x] = UInt8(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16)
                i += 4
            }
        }
        let uv = out + w * h
        for y in 0..<(h / 2) {
            let a = y * 2 * w * 4, c = a + w * 4
            let row = uv + y * w
            for x in 0..<(w / 2) {
                let k = x * 8
                let r = Int(p[a + k]) + Int(p[a + k + 4]) + Int(p[c + k]) + Int(p[c + k + 4])
                let g = Int(p[a + k + 1]) + Int(p[a + k + 5]) + Int(p[c + k + 1]) + Int(p[c + k + 5])
                let b = Int(p[a + k + 2]) + Int(p[a + k + 6]) + Int(p[c + k + 2]) + Int(p[c + k + 6])
                row[x * 2] = UInt8(max(16, min(240, ((-38 * r - 74 * g + 112 * b + 512) >> 10) + 128)))
                row[x * 2 + 1] = UInt8(max(16, min(240, ((112 * r - 94 * g - 18 * b + 512) >> 10) + 128)))
            }
        }
    }

    // MARK: Clips (BugNotes, main thread)

    // A note started: its clip opens with the buffered seconds. Returns whether a clip is being made.
    static func begin(path: String) -> Bool {
        lock.lock(); let want = wanted; lock.unlock()
        guard want else { return false }
        queue.async {
            clipGen += 1
            guard let e = enc, bs_venc_begin(e, path) == 0 else { try? FileManager.default.removeItem(atPath: path); return }
        }
        return true
    }

    // A note ended: the clip runs on for `tail` seconds and closes (a new note in that time closes it at once).
    // A dropped note's clip is deleted straight away.
    static func end(path: String, keep: Bool) {
        queue.async {
            let gen = clipGen
            func close() {
                guard gen == clipGen, let e = enc else { return }
                let bytes = bs_venc_end(e)
                if bytes <= 0 || !keep { try? FileManager.default.removeItem(atPath: path) }
            }
            if keep { queue.asyncAfter(deadline: .now() + tail) { close() } } else { close() }
        }
    }
}
#endif
