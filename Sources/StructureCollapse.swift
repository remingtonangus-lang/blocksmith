import Foundation
import simd

// Physics revamp, part 1, in play (StructureFlow has the why and the method): a structure too big for the load check
// near a change (Structure.analyse stops at 1,536 blocks and takes the rest as held) is weighed whole here, and what
// cannot carry its weight comes down.
//   - asked for by Structure.tick, when its check of a change stopped at its bound and found nothing cut loose;
//   - waits until the structure has been left alone for `settleFrames` frames (a salvo is weighed once, after it);
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
    static var settleFrames = 25                      // frames without a structural change before a piece is read (a third of a second)
    static var limit = 250_000                        // blocks read (past it: held, as before)
    static let bodyBin = Int(ProcessInfo.processInfo.environment["BS_COLLAPSEBIN"] ?? "") ?? 12   // a falling body is at most a cube of this side
    static var wantSeconds = 0.0012, maxWait = 3      // (as Structure.tick: a body waits for a frame with room)
    static let patientPieces = ProcessInfo.processInfo.environment["BS_COLLAPSEPUSH"] != "1"
    static var crumbsAFrame = 32
    static var patienceFrames = 216                   // (3 s: the longest a piece waits for quiet)
    private static var pendingSince = 0
    private static var lastLoud = 0
    // (harness: what it is doing)
    static var state: String {
        lock.lock(); defer { lock.unlock() }
        var j = "no piece in hand"
        if let jb = job {
            if let o = jb.outcome { j = "taking out \(jb.next)/\(o.parts.count) bodies, \(jb.crumb)/\(o.crumbs.count) loose" }
            else if jb.solving { j = "with the worker" }
            else { j = "reading, \(jb.capture.count) so far" }
        }
        return "\(j); \(pending.count) waiting (\(frameNo - pendingSince) frames, quiet for \(quietFrames)); \(held.count) checks held"
    }
    static var sliceFloor = 0.0004                    // (a frame with no room left still reads this much)

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
        var stale = false
        var again = false                             // (changed while the worker had it: weighed once more after)
        var capture: StructureFlow.Capture
        var captureT = 0.0
        var solving = false
        var outcome: Outcome?                         // (set by the worker under `lock`)
        var next = 0, crumb = 0
        init(_ p: IVec3, _ c: StructureFlow.Capture? = nil) { seed = p; capture = c ?? StructureFlow.Capture(at: p, limit: StructureCollapse.limit) }
    }
    // The piece last read, kept a while: a battle changes a structure many times, and each change after the first is
    // read into what is kept (the blocks it touched, StructureFlow.Capture.refresh) instead of the whole piece again.
    private static var kept: StructureFlow.Capture?
    private static var keptAt = 0.0, keptUsed = 0.0
    static var keepSeconds = 20.0, keepAtMost = 90.0
    static var reused = 0
    // Frames left of a collapse and its aftermath: what the check near a change topples meanwhile (the stubs a
    // collapse leaves hanging) waits for the workers' redraw too (Game.topple).
    static var comingDown = 0
    static var tracking: Bool { job != nil || !pending.isEmpty || kept != nil || !held.isEmpty }
    private static var pending: [IVec3] = []
    private static var job: Job?
    private static let lock = NSLock()
    private static var quietFrames = 0, waited = 0
    static var withWorker: Bool { lock.lock(); defer { lock.unlock() }; return job.map { $0.solving && $0.outcome == nil } ?? false }
    static var busy: Bool { job != nil || !pending.isEmpty }

    static func reset() { pending.removeAll(); job = nil; kept = nil; waited = 0; againSeeds.removeAll(); held.removeAll(); passed.removeAll(); clearedUntil = 0; dropped.removeAll() }

    // The whole weigh goes first. The check near a change (Structure.tick) that stopped at its bound and found blocks
    // past their reach used to drop them at once, and each drop asked for the next check: a brick tower left on a
    // pier too small for it rained its corners down storey by storey, filled the shot-out storey with them and then
    // stood on its own rubble, where the whole top should have come down in one piece (the tower test). Such a check
    // is held here until the piece has been weighed (or `holdFrames` at most, so a long barrage still sheds its
    // loose blocks), then run again: what the weigh left standing loses its loose blocks as before.
    // BS_COLLAPSEHOLD=0: dropped at once, as before.
    static let holding = ProcessInfo.processInfo.environment["BS_COLLAPSEHOLD"] != "0"
    static var holdFrames = 216, clearFrames = 360
    private static var held: [(p: IVec3, at: Int)] = []
    private static var passed: [IVec3: Int] = [:]     // (4-cubes whose check goes ahead, until a frame)
    private static var clearedUntil = 0               // (the piece kept was weighed: its checks go ahead until then)
    private static var frameNo = 0
    static var heldChecks = 0
    @inline(__always) private static func cube(_ p: IVec3) -> IVec3 { IVec3(floorDiv(p.x, 4), floorDiv(p.y, 4), floorDiv(p.z, 4)) }
    static func hold(_ w: World, at s: IVec3) -> Bool {
        guard enabled, holding, w.frame == nil, held.count < 64 else { return false }
        if let t = passed[cube(s)], t > frameNo { return false }
        if frameNo < clearedUntil, let k = kept, k.contains(s) || Structure.nbrs.contains(where: { k.contains(s + $0) }) { return false }
        let before = asked
        request(w, at: s)
        // (nothing asked and nothing in hand: nobody would let the check go)
        guard asked > before || busy else { return false }
        held.append((s, frameNo)); heldChecks += 1
        return true
    }
    private static func release(_ w: World, olderThan age: Int = 0) {
        guard !held.isEmpty else { return }
        var rest: [(p: IVec3, at: Int)] = []
        for h in held {
            if frameNo - h.at < age { rest.append(h); continue }
            passed[cube(h.p)] = frameNo + clearFrames
            w.requeueLoadCheck(h.p)
        }
        held = rest
        if passed.count > 256 { passed = passed.filter { $0.value > frameNo } }
    }
    // How many times its own weight a structure must carry to stand (BS_COLLAPSESAFETY).
    static var safety: Float = Float(ProcessInfo.processInfo.environment["BS_COLLAPSESAFETY"] ?? "") ?? 1

    // A change whose check stopped at its bound: the piece at p is weighed whole once things are quiet.
    // (another world, a dimension entered or a save loaded: nothing read from the last one is carried over)
    private static weak var owner: World?
    @inline(__always) private static func own(_ w: World) { if owner !== w { reset(); owner = w } }
    static func request(_ w: World, at p: IVec3) {
        guard enabled, w.frame == nil else { return }
        own(w)
        // (the changed cell itself is often air now: the built block beside it)
        var p = p
        if Structure.part(w, p.x, p.y, p.z) == nil {
            guard let d = Structure.nbrs.first(where: { Structure.part(w, p.x + $0.x, p.y + $0.y, p.z + $0.z) != nil }) else { return }
            p = p + d
        }
        if let j = job, !j.counted, j.capture.contains(p) { return }             // (the piece being read: the change is read into it)
        if pending.contains(where: { abs($0.x - p.x) + abs($0.y - p.y) + abs($0.z - p.z) < 24 }) { return }
        if pending.count >= 8 { pending.removeFirst() }
        if pending.isEmpty { pendingSince = frameNo }
        pending.append(p)
        asked += 1
    }

    // The worker's part: the flow, then what falls split into bodies (cubes of `bodyBin`, each joined group one body).
    static func work(_ piece: StructureFlow.Piece) -> Outcome {
        let o = Outcome()
        o.result = StructureFlow.solve(piece, scale: safety)
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
        if comingDown > 0 { comingDown -= 1 }
        frameNo += 1
        own(w)
        guard enabled, tracking else { return }
        if !held.isEmpty { if busy { release(w, olderThan: holdFrames) } else { release(w) } }
        let now = CFAbsoluteTimeGetCurrent()
        let paced = CraterJob.inTick && !(World.deterministic || Rand.deterministic)
        // The structural changes since the last frame (World.queueLoadCheck notes them): one in or against the piece
        // being read or weighed makes what was read stale; one near a piece that waits keeps it waiting.
        // (the two arrays trade places: no buffer made each frame a piece is kept)
        scratch.removeAll(keepingCapacity: true)
        swap(&scratch, &w.structChanged)
        let changes = scratch, flood = w.structFlood
        w.structFlood = false
        if let j = job {
            if flood {
                if j.counted { j.stale = true }       // (coming down already: finished, but not kept)
                else {
                    // (more changes than were noted: read again from the start)
                    restarts += 1
                    job = nil
                    if pending.count < 8 { if pending.isEmpty { pendingSince = frameNo }; pending.insert(j.seed, at: 0) }
                    quietFrames = 0
                }
            } else if !changes.isEmpty {
                let mine = changes.filter { c in j.capture.contains(c) || World.allDirs.contains(where: { j.capture.contains(c + $0) }) }
                if !mine.isEmpty {
                    // (read already: read again here. With the worker: what it finds falling is checked block by
                    // block as it is taken out, and the piece is weighed once more after)
                    if !j.counted { patched += mine.count; if j.solving { j.again = true } }
                    j.capture.refresh(w, mine)
                }
            }
        }
        if kept != nil {
            if flood || now - keptUsed > keepSeconds || now - keptAt > keepAtMost { kept = nil }
            else if !changes.isEmpty {
                let mine = changes.filter { c in kept!.contains(c) || World.allDirs.contains(where: { kept!.contains(c + $0) }) }
                if !mine.isEmpty { kept!.refresh(w, mine); keptUsed = now }
            }
        }
        quietFrames += 1
        // (quiet = no change a load check was queued for. Every structural block's change is noted for the piece in
        // hand, grass dying back, snow settling and leaves falling among them: counted here too, a piece under trees
        // or in the snow waited for a quiet that never came, 30 s and more in the citadel run)
        if !pending.isEmpty, flood || w.structLoud != lastLoud { quietFrames = 0 }
        lastLoud = w.structLoud
        if job == nil {
            // (seeded runs do not wait on the clock: the queue of checks empty is their quiet)
            // (a fight that never lets up for a third of a second, pieces still landing: weighed all the same after
            // `patienceFrames`; what changes meanwhile is read in, and the piece weighed once more)
            guard paced ? (quietFrames >= settleFrames || frameNo - pendingSince >= patienceFrames) : w.loadQueue.isEmpty else { return }
            while job == nil, let p = pending.first {
                pending.removeFirst()
                guard w.activeHere(p), Structure.part(w, p.x, p.y, p.z) != nil else { continue }
                if let k = kept, k.contains(p) { job = Job(p, k); kept = nil; reused += 1 }
                else { kept = nil; keptAt = now; job = Job(p) }
            }
            pendingSince = frameNo
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
            let piece = j.capture.piece                               // (the worker's own copy: a change read in meanwhile copies on write)
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
                // (thin ground weighed with the piece, StructureFlow.thin: it leaves the field as ground does)
                if w.fieldTerrain {
                    let soil = o.parts[j.next].filter { w.isGround($0) }
                    if !soil.isEmpty { GroundCollapse.drop(g, soil); groundFell += soil.count }
                }
                j.next += 1
                if cells.count >= 2 {
                    g.topple(cells, away: simd_length(o.away) > 0.5 ? o.away : nil)
                    // (a tree felled waits a tenth of a second for the world to be redrawn without it, then has its
                    // sections meshed on the frame: for the dozens of pieces of a collapse, each leaving a citadel's
                    // sections to redraw, that is the frame gone. They wait for the workers instead, up to 4 s.)
                    if patientPieces { Felling.falls.last?.patient = true }
                    comingDown = 5 * 72
                    bodies += 1
                }
            } while !paced && j.next < o.parts.count
            let dt = CFAbsoluteTimeGetCurrent() - t0
            if paced { CraterJob.spend(dt) }
            worstBodyMs = max(worstBodyMs, dt * 1000)
            if j.next < o.parts.count { return }
        }
        // The loose blocks, `crumbsAFrame` a frame (a citadel's collapse leaves hundreds along the pieces' borders).
        while j.crumb < o.crumbs.count {
            if paced {
                if CraterJob.allowance() < wantSeconds && waited < maxWait { waited += 1; return }
                waited = 0
            }
            let t0 = CFAbsoluteTimeGetCurrent()
            let end = paced ? min(o.crumbs.count, j.crumb + crumbsAFrame) : o.crumbs.count
            // (a loose block that fell and came to rest in the same cell, on something that is no part of a
            // structure: left there. Dropped again it was weighed, 120 ms on the worker, and dropped again, without end:
            // eight times in a row at one cell of the citadel run.)
            var cells: [IVec3] = []
            if w.fieldTerrain {
                let soil = o.crumbs[j.crumb..<end].filter { w.isGround($0) }
                if !soil.isEmpty { GroundCollapse.drop(g, Array(soil)); groundFell += soil.count }
            }
            for c in o.crumbs[j.crumb..<end] where Structure.part(w, c.x, c.y, c.z) != nil {
                if let t = dropped[c], frameNo - t < dropMemory { leftLying += 1; continue }
                dropped[c] = frameNo
                cells.append(c)
            }
            if dropped.count > 4096 { dropped = dropped.filter { frameNo - $0.value < dropMemory } }
            j.crumb = end
            let was = w.restoring
            w.restoring = true                                        // (what they leave was weighed already)
            if !cells.isEmpty { Structure.drop(g, cells) }
            w.restoring = was
            let dt = CFAbsoluteTimeGetCurrent() - t0
            if paced { CraterJob.spend(dt) }
            worstBodyMs = max(worstBodyMs, dt * 1000)
            if j.crumb < o.crumbs.count { return }
        }
        finish(j, w)
    }
    private static var scratch: [IVec3] = []
    private static var dropped: [IVec3: Int] = [:]
    static var dropMemory = 72 * 30, leftLying = 0
    static var groundFell = 0
    private static var againSeeds: [IVec3: Int] = [:]
    private static func finish(_ j: Job, _ w: World) {
        job = nil
        if !j.stale { kept = j.capture; keptUsed = CFAbsoluteTimeGetCurrent() }
        clearedUntil = frameNo + clearFrames
        release(w)
        // (changed under the worker: once more, at most twice for one place)
        if j.again, againSeeds[j.seed, default: 0] < 2, Structure.part(w, j.seed.x, j.seed.y, j.seed.z) != nil {
            againSeeds[j.seed, default: 0] += 1
            if againSeeds.count > 64 { againSeeds.removeAll() }
            if pending.count < 8 { if pending.isEmpty { pendingSince = frameNo }; pending.append(j.seed) }
        }
    }
}
