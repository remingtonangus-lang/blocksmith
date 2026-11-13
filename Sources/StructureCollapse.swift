import Foundation
import simd

// Physics revamp, part 1, in play (StructureFlow has the why and the method): a structure too big for the load check
// near a change (Structure.analyse stops at 1,536 blocks and takes the rest as held) is weighed whole here, and what
// cannot carry its weight comes down.
//   - asked for by Structure.tick, when its check of a change stopped at its bound and found nothing cut loose;
//   - waits until the structure has been left alone for `settle` seconds (a salvo is weighed once, after it);
//   - read from the world a slice a frame under the tick's carving allowance (StructureFlow.Capture), started over
//     when a structural block changes meanwhile;
//   - weighed on a worker thread (StructureFlow.solve: arrays only), which also splits what falls into bodies;
//   - what falls is taken out one body a frame, lowest first, each a rigid body with its own mesh (Game.topple), tipping
//     away from what still stands.
// What still stands after it needs no second look: none of the weight that found its way down went through a block
// that fell (such a block would have had a way down itself).
// BS_COLLAPSE=0: off (before/after). Seeded runs and harnesses do every step on the frame it is asked.
enum StructureCollapse {
    static let enabled = ProcessInfo.processInfo.environment["BS_COLLAPSE"] != "0"
    static var settle = 0.35                          // seconds without a structural change before a piece is read
    static var limit = 250_000                        // blocks read (past it: held, as before)
    static let bodyBin = Int(ProcessInfo.processInfo.environment["BS_COLLAPSEBIN"] ?? "") ?? 12   // a falling body is at most a cube of this side
    static var wantSeconds = 0.0012, maxWait = 3      // (as Structure.tick: a body waits for a frame with room)
    static var sliceFloor = 0.0002                    // (a frame with no room left still reads this much)

    // (harness and soak)
    static var asked = 0, weighed = 0, collapses = 0, fellBlocks = 0, bodies = 0, restarts = 0, patched = 0
    static var worstSliceMs = 0.0, lastCaptureMs = 0.0, lastSolveMs = 0.0, lastBlocks = 0, worstBodyMs = 0.0
    static var log = ProcessInfo.processInfo.environment["BS_COLLAPSELOG"] == "1"

    // What the worker hands back.
    final class Outcome {
        var result = StructureFlow.Result()
        var parts: [[IVec3]] = []                     // the bodies, lowest first
        var crumbs: [IVec3] = []                      // (pieces too small for a body: they fall block by block)
        var away = V3(0, 0, 0)                        // from what stands to what falls
    }
    private final class Job {
        var seed: IVec3
        var counted = false
        var again = false                             // (changed while the worker had it: weighed once more after)
        var capture: StructureFlow.Capture
        var captureT = 0.0
        var solving = false
        var outcome: Outcome?                         // (set by the worker under `lock`)
        var next = 0
        init(_ p: IVec3) { seed = p; capture = StructureFlow.Capture(at: p, limit: StructureCollapse.limit) }
    }
    private static var pending: [IVec3] = []
    private static var job: Job?
    private static let lock = NSLock()
    private static var quietSince = 0.0, waited = 0
    static var busy: Bool { job != nil || !pending.isEmpty }

    static func reset() { pending.removeAll(); job = nil; waited = 0; againSeeds.removeAll() }

    // A change whose check stopped at its bound: the piece at p is weighed whole once things are quiet.
    static func request(_ w: World, at p: IVec3) {
        guard enabled, w.frame == nil else { return }
        if let j = job, j.outcome == nil, j.capture.contains(p) { return }       // (the piece being read: it starts over on the change anyway)
        if pending.contains(where: { abs($0.x - p.x) + abs($0.y - p.y) + abs($0.z - p.z) < 24 }) { return }
        if pending.count >= 8 { pending.removeFirst() }
        pending.append(p)
        asked += 1
    }

    // The worker's part: the flow, then what falls split into bodies (cubes of `bodyBin`, each joined group one body).
    static func work(_ piece: StructureFlow.Piece) -> Outcome {
        let o = Outcome()
        o.result = StructureFlow.solve(piece)
        guard !o.result.falls.isEmpty else { return o }
        var bins: [IVec3: [IVec3]] = [:]
        var fsum = SIMD3<Double>(0, 0, 0)
        let fell = Set(o.result.falls)
        var ssum = SIMD3<Double>(0, 0, 0), sn = 0.0
        for i in 0..<piece.cells.count {
            let c = piece.cells[i]
            if fell.contains(i) {
                bins[IVec3(floorDiv(c.x, bodyBin), floorDiv(c.y, bodyBin), floorDiv(c.z, bodyBin)), default: []].append(c)
                fsum += SIMD3<Double>(Double(c.x), Double(c.y), Double(c.z))
            } else { ssum += SIMD3<Double>(Double(c.x), Double(c.y), Double(c.z)); sn += 1 }
        }
        for (_, cells) in bins {
            for comp in Structure.components(cells) {
                if comp.count >= Structure.wholeMin { o.parts.append(comp) } else { o.crumbs += comp }
            }
        }
        func low(_ p: [IVec3]) -> (Int, Int, Int) { var m = (Int.max, Int.max, Int.max); for c in p where (c.y, c.x, c.z) < m { m = (c.y, c.x, c.z) }; return m }
        let keyed = o.parts.map { (low($0), $0) }.sorted { $0.0 < $1.0 }
        o.parts = keyed.map { $0.1 }
        if sn > 0 {
            let f = fsum / Double(fell.count), s = ssum / sn
            o.away = V3(Float(f.x - s.x), 0, Float(f.z - s.z))
        }
        return o
    }

    static func tick(_ g: Game) {
        let w = g.world
        guard enabled, job != nil || !pending.isEmpty else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let paced = CraterJob.inTick && !(World.deterministic || Rand.deterministic)
        // The structural changes since the last frame (World.queueLoadCheck notes them): one in or against the piece
        // being read or weighed makes what was read stale; one near a piece that waits keeps it waiting.
        let changes = w.structChanged, flood = w.structFlood
        w.structChanged.removeAll(keepingCapacity: true); w.structFlood = false
        if let j = job, !j.counted {
            if flood {
                // (more changes than were noted: read again from the start)
                restarts += 1
                job = nil
                if pending.count < 8 { pending.insert(j.seed, at: 0) }
                quietSince = now
            } else if !changes.isEmpty {
                let mine = changes.filter { c in j.capture.contains(c) || World.allDirs.contains(where: { j.capture.contains(c + $0) }) }
                if !mine.isEmpty {
                    patched += mine.count
                    // (read already: read again here; with the worker: what it finds falling is checked block by
                    // block as it is taken out, and the piece is weighed once more after)
                    if j.solving { j.again = true } else { j.capture.refresh(w, mine) }
                }
            }
        }
        if let p = pending.first, flood || changes.contains(where: { abs($0.x - p.x) + abs($0.z - p.z) < 128 }) { quietSince = now }
        if job == nil {
            // (seeded runs do not wait on the clock: the queue of checks empty is their quiet)
            guard paced ? now - quietSince >= settle : w.loadQueue.isEmpty else { return }
            while job == nil, let p = pending.first {
                pending.removeFirst()
                guard w.activeHere(p), Structure.part(w, p.x, p.y, p.z) != nil else { continue }
                job = Job(p)
            }
        }
        guard let j = job else { return }
        lock.lock(); let outcome = j.outcome; lock.unlock()
        if outcome == nil {
            if j.solving { return }                                   // (the worker has it)
            let room = paced ? max(sliceFloor, CraterJob.allowance()) : Double.infinity
            let t0 = CFAbsoluteTimeGetCurrent()
            let done = j.capture.step(w, until: t0 + room)
            let dt = CFAbsoluteTimeGetCurrent() - t0
            if paced { CraterJob.spend(dt) }
            j.captureT += dt
            worstSliceMs = max(worstSliceMs, dt * 1000)
            guard done else { return }
            pending.removeAll { j.capture.contains($0) }
            lastCaptureMs = j.captureT * 1000; lastBlocks = j.capture.count
            // (a docked vessel is the ships' business; a piece small enough for the check near the change was its)
            if j.capture.vessel { job = nil; return }
            let piece = j.capture.piece
            j.capture.piece = StructureFlow.Piece()                   // (the arrays go with the worker; the index stays, for the changes)
            j.solving = true
            if paced {
                DispatchQueue.global(qos: .utility).async {
                    let o = work(piece)
                    lock.lock(); j.outcome = o; lock.unlock()
                }
            } else {
                j.outcome = work(piece)
            }
            return
        }
        let o = outcome!
        if !j.counted {
            j.counted = true
            weighed += 1
            lastSolveMs = o.result.ms
            if log {
                print(String(format: "collapse: weighed %d blocks at %d %d %d (read %.1f ms, worst slice %.2f ms; weighed %.1f ms off the frame): %@",
                             o.result.blocks, j.seed.x, j.seed.y, j.seed.z, lastCaptureMs, worstSliceMs, o.result.ms,
                             o.result.falls.isEmpty ? "stands" : "\(o.result.falls.count) blocks come down in \(o.parts.count) bodies, \(o.crumbs.count) loose blocks"))
            }
            if o.result.falls.isEmpty { finish(j, w); return }
            collapses += 1
            fellBlocks += o.result.falls.count
        }
        // One body a frame, lowest first.
        if j.next < o.parts.count {
            if paced {
                if CraterJob.allowance() < wantSeconds && waited < maxWait { waited += 1; return }
                waited = 0
            }
            let t0 = CFAbsoluteTimeGetCurrent()
            repeat {
                let cells = o.parts[j.next].filter { Structure.part(w, $0.x, $0.y, $0.z) != nil }
                j.next += 1
                if cells.count >= 2 {
                    g.topple(cells, away: simd_length(o.away) > 0.5 ? o.away : nil)
                    bodies += 1
                }
            } while !paced && j.next < o.parts.count
            let dt = CFAbsoluteTimeGetCurrent() - t0
            if paced { CraterJob.spend(dt) }
            worstBodyMs = max(worstBodyMs, dt * 1000)
            if j.next < o.parts.count { return }
        }
        if !o.crumbs.isEmpty {
            let cells = o.crumbs.filter { Structure.part(w, $0.x, $0.y, $0.z) != nil }
            let was = w.restoring
            w.restoring = true                                        // (what they leave was weighed already)
            Structure.drop(g, cells)
            w.restoring = was
        }
        finish(j, w)
    }
    private static var againSeeds: [IVec3: Int] = [:]
    private static func finish(_ j: Job, _ w: World) {
        job = nil
        // (changed under the worker: once more, at most twice for one place)
        if j.again, againSeeds[j.seed, default: 0] < 2, Structure.part(w, j.seed.x, j.seed.y, j.seed.z) != nil {
            againSeeds[j.seed, default: 0] += 1
            if againSeeds.count > 64 { againSeeds.removeAll() }
            if pending.count < 8 { pending.append(j.seed) }
        }
    }
}
