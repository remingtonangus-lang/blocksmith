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
            let t = Thread { [unowned self] in self.run(i) }
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
        let h = held
        cond.unlock()
        if h > 0 { cond.broadcast() } else { cond.signal() }      // (a held worker woken alone would sleep on the job)
    }

    // P414: ahead of every waiting job (the ground under and ahead of the player).
    func addFront(_ job: @escaping () -> Void) {
        cond.lock()
        if head > 0 { head -= 1; jobs[head] = job } else { jobs.insert(job, at: 0) }
        let h = held
        cond.unlock()
        if h > 0 { cond.broadcast() } else { cond.signal() }
    }

    // Blocks until every job added so far has finished (World.deterministic harness runs; never from a worker).
    func waitIdle() {
        idle.lock()
        while pending > 0 { idle.wait() }
        idle.unlock()
    }

    // Store review (the citadel soak): the frame's own helpers (the mobs' vertices, FrameWork) are woken each frame and
    // wanted within a millisecond or two, but with every core busy with these workers' chunk jobs the scheduler could
    // leave one waiting for its turn, and the frame thread then did that work itself (44 of 2,376 frames, 4-6 ms each).
    // Linux and Android give each thread its own nice value: the world workers run a few steps nicer, so a woken frame
    // helper (or the frame thread) goes first. The Mac keeps its quality-of-service classes. BS_WORKERNICE=0: as before.
    static let nice: Int32 = Int32(ProcessInfo.processInfo.environment["BS_WORKERNICE"] ?? "") ?? 5

    // Ledger 126 (FrameGovernor): after late frames the first `held` workers take no new job (one already under way
    // finishes), so the frame's own threads get the cores; never all of them. Jobs sent ahead of the queue (the ground
    // under the player) still go at once on the workers left.
    private var held = 0
    func setHeld(_ n: Int) {
        let h = max(0, min(workers - 1, n))
        cond.lock()
        let changed = h != held
        held = h
        cond.unlock()
        // (lowered: the held wake. Raised: a worker signalled for a job and now held would sleep on it, so all look.)
        if changed { cond.broadcast() }
    }
    var heldNow: Int { cond.lock(); defer { cond.unlock() }; return held }

    private func run(_ index: Int) {
        #if os(Linux) || os(Android)
        if JobPool.nice > 0 { _ = jobPoolSetPriority(0, 0, JobPool.nice) }      // (PRIO_PROCESS, this thread)
        #endif
        while true {
            cond.lock()
            while head == jobs.count || index < held { cond.wait() }
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

#if os(Linux) || os(Android)
// setpriority(2) by its C signature (Glibc and Bionic import its first argument as different types). With PRIO_PROCESS
// and who 0, Linux sets the calling thread's nice value alone.
@_silgen_name("setpriority") private func jobPoolSetPriority(_ which: Int32, _ who: UInt32, _ prio: Int32) -> Int32
#endif
