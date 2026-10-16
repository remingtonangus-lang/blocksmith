import Foundation

// P283: the worlds' worker threads (World's chunk generation and meshing jobs). OperationQueue in the open-source
// Foundation the headset runs takes one lock to add, start and finish every operation: on the Quest replay of his
// homestead (questcheck --perfscenes) a quarter of the frame thread's samples sat in addOperation, half of them
// waiting on that lock while the workers finished meshes. Here a job is a closure appended under a lock the workers
// hold only to take the next one. One pool for every world (the dimensions take turns streaming).
final class JobPool {
    static let shared = JobPool(workers: max(2, ProcessInfo.processInfo.activeProcessorCount - 2))

    let workers: Int
    private let cond = NSCondition()           // guards everything below; workers wait on it for work
    private let idle = NSCondition()           // waitIdle waits on this one
    private var jobs: [() -> Void] = []
    private var head = 0
    private var active = 0

    init(workers: Int) {
        self.workers = workers
        for i in 0..<workers {
            let t = Thread { [unowned self] in self.run() }
            t.name = "blocksmith.world.\(i)"
            t.qualityOfService = .userInitiated
            t.stackSize = 8 << 20
            t.start()
        }
    }

    // Jobs waiting or running.
    var pending: Int {
        cond.lock(); defer { cond.unlock() }
        return jobs.count - head + active
    }

    func add(_ job: @escaping () -> Void) {
        cond.lock()
        jobs.append(job)
        cond.unlock()
        cond.signal()
    }

    // Blocks until every job added so far has finished (World.deterministic harness runs; never from a worker).
    func waitIdle() {
        idle.lock()
        while pending > 0 { idle.wait() }
        idle.unlock()
    }

    private func run() {
        while true {
            cond.lock()
            while head == jobs.count { cond.wait() }
            let job = jobs[head]
            jobs[head] = {}
            head += 1
            if head == jobs.count { jobs.removeAll(keepingCapacity: true); head = 0 }
            else if head >= 512 { jobs.removeFirst(head); head = 0 }
            active += 1
            cond.unlock()
            #if canImport(ObjectiveC)
            autoreleasepool { job() }              // (a finished job's leftovers must not keep a World alive)
            #else
            job()
            #endif
            cond.lock()
            active -= 1
            let done = active == 0 && head == jobs.count
            cond.unlock()
            if done { idle.lock(); idle.broadcast(); idle.unlock() }
        }
    }
}
