import Foundation
import Dispatch

// P385: a piece of a frame's recording handed to a worker thread (the mobs' vertices, the occluder raster) while the
// frame thread goes on. When the frame thread needs the result and the worker hasn't begun it (on a busy CPU a queued
// worker can start milliseconds late), the frame thread takes the work back and does it itself, so handing work out
// never costs more than doing it in place; when the worker is part way through, the frame thread waits for it.
final class FrameWork: @unchecked Sendable {
    private let lock = NSLock()
    private let done = DispatchSemaphore(value: 0)
    private let queue: DispatchQueue
    private var gen = 0
    private var state = 3                  // 0 waiting for a thread, 1 the worker has it, 2 done or taken back, 3 none
    private var job: (() -> Void)?
    private(set) var tookBack = 0           // times the frame thread did the work itself (since the last take)

    init(label: String) { queue = DispatchQueue(label: label, qos: .userInteractive) }

    func start(_ work: @escaping () -> Void) {
        finish()                                         // (a previous frame's, if never finished)
        lock.lock()
        gen &+= 1
        let g = gen
        state = 0; job = work
        lock.unlock()
        queue.async { [self] in
            lock.lock()
            guard gen == g, state == 0, let w = job else { lock.unlock(); return }
            state = 1; job = nil
            lock.unlock()
            w()
            done.signal()
        }
    }

    // The work is done when this returns (by the worker, or here). Calling it again, or with nothing started, does nothing.
    func finish() {
        lock.lock()
        switch state {
        case 0:
            state = 2
            let w = job
            job = nil
            tookBack += 1
            lock.unlock()
            w?()
        case 1:
            state = 2
            lock.unlock()
            done.wait()
        default:
            lock.unlock()
        }
    }

    func takeTookBack() -> Int { let n = tookBack; tookBack = 0; return n }
}
