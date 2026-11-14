import Foundation
import simd

// The builder agent (BuildersGrounds.swift): works through a placement's jobs with the player's own controls. For each
// job it picks a face to click (a neighbour's face for a block, the cell's own face to dig), a spot to stand within
// reach where the face is in plain sight and the block would come out the right way round (stairs and doors face away
// from the player, a slab or a stair goes upside down from the top half of a face, a log lies along the clicked face's
// axis, a lantern hangs from a face underneath), flies there (straight when the way is clear, else up, over and down),
// turns to the face, and presses the place or break button once the game's own aim shows that face and that cell.
// The hotbar is filled as he would from the creative menu: the block in hand, in a free slot.
final class BuilderBot: AgentBot {
    let name = "builder"
    let plan: BuildersGrounds.Placement
    private(set) var jobs: [BuildersGrounds.Job]
    private(set) var i = 0
    private var phase = 0, ticks = 0, moveTicks = 0, aimTicks = 0, wait = 0, flyCool = 0
    private var spots: [(feet: V3, aim: V3)] = []
    private var ci = 0                                  // the spot flown to
    private var path: [V3] = [], wp = 0
    private var deferred: [IVec3: Int] = [:]
    private var slotOf: [ItemID: Int] = [:], nextSlot = 0
    let cruise: Float
    private(set) var routed = 0, cuts = 0, scaffolds = 0
    private var scaffoldFor: [IVec3: IVec3] = [:]
    private enum Draft0 { static let plank = Blocks.has("oak_planks") ? Blocks.id("oak_planks") : STONE }
    private(set) var placed = 0, dug = 0, presses = 0, redone = 0
    private(set) var missed: [String] = []
    private(set) var doneTick: Int?
    var done: Bool { i >= jobs.count }

    init(_ p: BuildersGrounds.Placement, world w: World) {
        plan = p
        jobs = p.jobs
        var top = p.hi.y
        for x in stride(from: p.lo.x - 8, through: p.hi.x + 8, by: 2) { for z in stride(from: p.lo.z - 8, through: p.hi.z + 8, by: 2) { top = max(top, w.topY(x, z)) } }
        cruise = Float(top + 3)
    }

    func goals() -> [(String, Bool, String)] {
        [("build \(plan.bp.key): every job done", missed.isEmpty && done,
          "\(placed) placed, \(dug) dug, \(missed.count) missed\(missed.isEmpty ? "" : ": " + missed.prefix(5).joined(separator: "; "))")]
    }

    // MARK: Faces and spots

    private static let dirs6 = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)]
    private static let looks: [V3] = {
        var v: [V3] = []
        for e in [-0.45, 0, 0.45, 0.85] as [Float] {
            for k in 0..<12 {
                let a = Float(k) * .pi / 6
                v.append(simd_normalize(V3(cosf(a) * cosf(e), sinf(e), sinf(a) * cosf(e))))
            }
        }
        v.append(V3(0, 1, 0)); v.append(V3(0, -1, 0))
        return v
    }()

    private func fv(_ v: IVec3) -> V3 { V3(Float(v.x), Float(v.y), Float(v.z)) }
    private func solid(_ w: World, _ c: IVec3) -> Bool { w.solidAt(c.x, c.y, c.z) }
    // The body standing with its feet at f: clear of every solid cell and of the cell being worked.
    private func bodyFree(_ w: World, _ f: V3, not c: IVec3) -> Bool {
        let x0 = Int(floor(f.x - 0.3)), x1 = Int(floor(f.x + 0.3)), z0 = Int(floor(f.z - 0.3)), z1 = Int(floor(f.z + 0.3))
        let y0 = Int(floor(f.y)), y1 = Int(floor(f.y + 1.79))
        for y in y0...y1 { for z in z0...z1 { for x in x0...x1 {
            let q = IVec3(x, y, z)
            if q == c || solid(w, q) { return false }
        } } }
        return true
    }
    private func pathFree(_ w: World, from a: V3, to b: V3, not c: IVec3) -> Bool {
        let d = b - a, n = max(1, Int(simd_length(d) / 0.3))
        for k in 0...n where !bodyFree(w, a + d * (Float(k) / Float(n)), not: c) { return false }
        return true
    }
    private func columnFree(_ w: World, _ f: V3, not c: IVec3) -> Bool {
        var y = f.y
        while y < cruise { if !bodyFree(w, V3(f.x, y, f.z), not: c) { return false }; y += 1 }
        return true
    }

    // What the placed state would be from this click: the game's own rules for the shapes the blueprints use.
    static func wouldPlace(_ want: BlockID, normal n: IVec3, fracY: Float, yaw: Float) -> Bool {
        let base = Blocks.groupBase[Int(want)], off = Int(want - base)
        let key = Blocks.key(base)
        let upper = n.y == -1 || (n.y == 0 && fracY > 0.5)
        let facing = BlockRegistry.facingToward(yaw: yaw)
        switch Blocks.shape[Int(want)] {
        case "stairs": return off == (upper ? 4 : 0) + (facing ^ 1)
        case "slab": return off == (upper ? 1 : 0)
        case "door": return off & 3 == facing
        case "lantern": return off == (n.y == -1 ? 1 : 0) && n.y != 0
        case "trapdoor": return off == facing + (upper ? 8 : 0)
        default: break
        }
        if Blocks.has(key + "[x]") && Blocks.shape[Int(base)].isEmpty { return Game.axisPlaced(base, key, normal: n) == want }
        if Blocks.has(key + "[south]") && Blocks.shape[Int(base)].isEmpty { return off == facing }
        return true
    }

    // Blocks a click would work instead of build on (a door opens, a chest opens), or a slab of the kind in hand (the
    // click would make it a double slab): never a face to place against.
    private static func clickable(_ b: BlockID, holding want: BlockID) -> Bool {
        let sh = Blocks.shape[Int(b)]
        if sh == "door" || sh == "trapdoor" || sh == "gate" { return true }
        if sh == "slab" && Blocks.groupBase[Int(b)] == Blocks.groupBase[Int(want)] { return true }
        let k = Blocks.key(Blocks.groupBase[Int(b)])
        return k.contains("chest") || k.contains("furnace") || k.contains("crafting") || k.contains("barrel")
    }

    // Spots to stand and points to aim at for a job, nearest to `from` first.
    private var why = ""
    private var blocker: IVec3?                 // the tree cell most in the way of the faces (a crown over a dig, say)
    private var noFaces = false
    private var successes = 0, deferredAt: [IVec3: Int] = [:], cleared = 0
    private lazy var planned: Set<IVec3> = Set(plan.jobs.filter { $0.want != AIR }.map { $0.cell })
    private func tree(_ w: World, _ q: IVec3) -> Bool {
        let b = w.block(q.x, q.y, q.z)
        if b == AIR || Blocks.isLiquid(b) || planned.contains(q) || (w.fieldTerrain && w.groundAt(q.x, q.y, q.z)) { return false }
        let k = Blocks.key(Blocks.groupBase[Int(b)])
        return k.hasSuffix("_leaves") || k.hasSuffix("_log") || k.hasSuffix("_wood") || Blocks.render[Int(b)] == RenderType.cross.rawValue || k.contains("vine")
    }
    private func candidates(_ w: World, _ j: BuildersGrounds.Job, from: V3) -> [(feet: V3, aim: V3)] {
        let c = j.cell
        var nBody = 0, nState = 0, nRay = 0, nWay = 0, rayAt: [String: Int] = [:], blockers: [IVec3: Int] = [:]
        blocker = nil
        var faces: [(hit: IVec3, n: IVec3, aim: V3)] = []
        let cc = V3(Float(c.x) + 0.5, Float(c.y) + 0.5, Float(c.z) + 0.5)
        if j.want == AIR {
            // (aimed at the middle of what is there: a snow layer or a plant is lower and smaller than the cell)
            var mid = cc, half = V3(0.45, 0.45, 0.45)
            let b = w.block(c.x, c.y, c.z)
            if !(w.fieldTerrain && w.groundAt(c.x, c.y, c.z)), let box = w.selectionBoxes(b).first {
                mid = fv(c) + (box.0 + box.1) * 0.5; half = (box.1 - box.0) * 0.45
            }
            for d in BuilderBot.dirs6 where !solid(w, c + d) { faces.append((c, d, mid + fv(d) * half)) }
        } else {
            let shape = Blocks.shape[Int(j.want)], off = Int(j.want - Blocks.groupBase[Int(j.want)])
            let wantsUpper: Bool? = shape == "stairs" ? off >= 4 : (shape == "slab" ? off == 1 : (shape == "trapdoor" ? off >= 8 : nil))
            for d in BuilderBot.dirs6 {
                let s = c + d
                let sb = w.block(s.x, s.y, s.z)
                guard solid(w, s) || (sb != AIR && !Blocks.replaceable[Int(sb)]) else { continue }
                if BuilderBot.clickable(sb, holding: j.want) { continue }
                let n = IVec3(-d.x, -d.y, -d.z)
                if shape == "door" && n.y != 1 { continue }
                if shape == "lantern" && n.y == 0 { continue }
                var a = cc + fv(d) * 0.5
                a = a - fv(d) * 0.02                      // (just on the support's face, on the cell's side)
                if let up = wantsUpper {
                    if n.y == 1 && up { continue }
                    if n.y == -1 && !up { continue }
                    if n.y == 0 { a.y = Float(c.y) + (up ? 0.8 : 0.2) }
                }
                faces.append((s, n, a))
            }
        }
        // Cheap tests first (the body fits, the block would come out right, the ray meets the face), the way there last.
        var spots: [(V3, V3, Float)] = []
        for f in faces {
            for look in BuilderBot.looks where simd_dot(look, fv(f.n)) >= 0.3 {
                for dist in [2.2, 3.0, 3.9] as [Float] {
                    let eye = f.aim + look * dist
                    let feet = eye - V3(0, 1.62, 0)
                    guard feet.y > 1, bodyFree(w, feet, not: c) else { nBody += 1; continue }
                    let dv = f.aim - eye
                    if j.want != AIR {
                        let yaw = atan2f(-dv.x, -dv.z)
                        let fy = f.aim.y - Float(f.hit.y)
                        if !BuilderBot.wouldPlace(j.want, normal: f.n, fracY: fy, yaw: yaw) { nState += 1; continue }
                    }
                    // (Natural ground is met where the drawn surface is, which can name the next cell over: near enough
                    // here; the game's own aim decides at the spot.)
                    let fGround = w.fieldTerrain && w.groundAt(f.hit.x, f.hit.y, f.hit.z)
                    guard let h = w.raycast(eye, simd_normalize(dv), maxDist: simd_length(dv) + 0.4),
                          h.hit == f.hit || (fGround && w.groundAt(h.hit.x, h.hit.y, h.hit.z) && h.hit != c
                                              && abs(h.hit.x - f.hit.x) <= 1 && abs(h.hit.y - f.hit.y) <= 1 && abs(h.hit.z - f.hit.z) <= 1) else {
                        nRay += 1
                        if let h = w.raycast(eye, simd_normalize(dv), maxDist: simd_length(dv) + 0.4) {
                            let k = "\(h.hit.x - c.x),\(h.hit.y - c.y),\(h.hit.z - c.z) \(Blocks.key(w.block(h.hit.x, h.hit.y, h.hit.z)))"
                            rayAt[k, default: 0] += 1
                            if tree(w, h.hit) { blockers[h.hit, default: 0] += 1 }
                        } else { rayAt["nothing", default: 0] += 1 }
                        continue
                    }
                    spots.append((feet, f.aim, simd_length(feet - from)))
                }
            }
        }
        spots.sort { $0.2 < $1.2 }
        noFaces = faces.isEmpty
        blocker = blockers.max { $0.value < $1.value }?.key
        let top = rayAt.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key) x\($0.value)" }.joined(separator: ", ")
        why = "\(faces.count) faces; spots: \(nBody) body blocked, \(nState) wrong way round, \(nRay) ray elsewhere (\(top)), \(spots.count) seen"
        return spots.prefix(80).map { (feet: $0.0, aim: $0.1) }
    }

    // MARK: The way there

    // A flight from the body's cell to the nearest of the spots, cell by cell (a cell free with the one over it, never
    // the cell being worked), in a box round the build. `through`: tree cells count as free (to find what to cut).
    private func route(_ w: World, from: V3, to spots: [(feet: V3, aim: V3)], not c: IVec3, through: Bool) -> (spot: Int, path: [IVec3])? {
        let x0 = min(plan.lo.x, Int(floor(from.x))) - 16, x1 = max(plan.hi.x, Int(floor(from.x))) + 16
        let z0 = min(plan.lo.z, Int(floor(from.z))) - 16, z1 = max(plan.hi.z, Int(floor(from.z))) + 16
        let y0 = max(1, min(plan.lo.y, Int(floor(from.y))) - 30), y1 = min(CH - 3, max(Int(cruise), Int(floor(from.y))) + 6)
        let nx = x1 - x0 + 1, nz = z1 - z0 + 1, ny = y1 - y0 + 1
        func idx(_ q: IVec3) -> Int { ((q.y - y0) * nz + (q.z - z0)) * nx + (q.x - x0) }
        func inside(_ q: IVec3) -> Bool { q.x >= x0 && q.x <= x1 && q.y >= y0 && q.y <= y1 && q.z >= z0 && q.z <= z1 }
        func open(_ q: IVec3) -> Bool { q != c && (!solid(w, q) || (through && tree(w, q))) }
        func free(_ q: IVec3) -> Bool { open(q) && open(q + IVec3(0, 1, 0)) }
        var goal: [Int: Int] = [:]
        for (k, sp) in spots.enumerated() {
            let q = IVec3(Int(floor(sp.feet.x)), Int(floor(sp.feet.y)), Int(floor(sp.feet.z)))
            if inside(q) && goal[idx(q)] == nil { goal[idx(q)] = k }
        }
        var start = IVec3(Int(floor(from.x)), Int(floor(from.y + 0.1)), Int(floor(from.z)))
        if !free(start) {
            if let s2 = [IVec3(0, 1, 0), IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1), IVec3(0, -1, 0)].map({ start + $0 }).first(where: { inside($0) && free($0) }) { start = s2 }
        }
        guard inside(start), !goal.isEmpty else { return nil }
        var parent = [Int32](repeating: -1, count: nx * ny * nz)
        var queue: [IVec3] = [start]
        parent[idx(start)] = Int32(idx(start))
        var head = 0
        while head < queue.count {
            let q = queue[head]; head += 1
            if let k = goal[idx(q)] {
                var path: [IVec3] = [q]
                var at = idx(q)
                while Int(parent[at]) != at {
                    at = Int(parent[at])
                    let x = at % nx, r = at / nx, z = r % nz, y = r / nz
                    path.append(IVec3(x + x0, y + y0, z + z0))
                }
                return (k, path.reversed())
            }
            for d in BuilderBot.dirs6 {
                let n = q + d
                guard inside(n) else { continue }
                let ni = idx(n)
                if parent[ni] != -1 || !free(n) { continue }
                parent[ni] = Int32(idx(q))
                queue.append(n)
            }
        }
        return nil
    }

    // MARK: Acting

    private func next(_ s: AgentState, ok: Bool, why: String = "") {
        if ok { successes += 1; if jobs[i].want == AIR { dug += 1 } else { placed += 1 } }
        else { missed.append("\(jobs[i].want == AIR ? "dig" : Blocks.key(jobs[i].want)) at \(jobs[i].cell.x) \(jobs[i].cell.y - YOFF) \(jobs[i].cell.z): \(why)") }
        i += 1; phase = 0; ticks = 0; spots = []; ci = 0; path = []
    }
    // A job that can't be reached yet (nothing to click on, no spot) goes to the back, three times at most.
    private func later(_ s: AgentState, _ why: String) {
        let j = jobs[i]
        let n = deferredAt[j.cell] == successes ? deferred[j.cell, default: 0] + 1 : 1
        deferred[j.cell] = n; deferredAt[j.cell] = successes
        if n > 3 { next(s, ok: false, why: why); return }
        jobs.remove(at: i); jobs.insert(j, at: min(jobs.count, i + 4))
        phase = 0; ticks = 0; spots = []; ci = 0; path = []
    }

    // A tree cell in the way: dug first (a job of its own, moved up if it is one already).
    private func cut(_ q: IVec3) -> Bool {
        guard cuts < 600 else { return false }
        cuts += 1
        if let k = jobs[i...].firstIndex(where: { $0.cell == q && $0.want == AIR }) { jobs.remove(at: k) }
        jobs.insert(BuildersGrounds.Job(cell: q, want: AIR), at: i)
        phase = 0; ticks = 0; spots = []; path = []
        return true
    }
    private var lastDrop = ""
    // The spot didn't work: the next nearest, by a new route.
    private func drop(_ s: AgentState, _ why: String) {
        lastDrop = why
        if ci < spots.count { spots.remove(at: ci) }
        if spots.isEmpty { later(s, why); return }
        phase = 4; moveTicks = 0
    }

    func act(_ s: AgentState, _ a: Agent) -> AgentAction {
        let w = a.world, g = a.game, p = g.player
        var act = AgentAction()
        if flyCool > 0 { flyCool -= 1 }
        guard i < jobs.count else { if doneTick == nil { doneTick = s.tick }; return act }
        let j = jobs[i]
        if phase != 3 && BuildersGrounds.holds(w, j) { next(s, ok: true); return act }
        ticks += 1
        if ticks > 1200 { next(s, ok: false, why: "out of time"); return act }
        // The block in hand.
        if j.want != AIR {
            guard let item = Items.item(forBlock: j.want) else { next(s, ok: false, why: "no item for it"); return act }
            var slot = slotOf[item]
            if slot == nil || g.inventory.main[slot!].isEmpty || g.inventory.main[slot!].item != item {
                slot = nextSlot; nextSlot = (nextSlot + 1) % 9
                for (k, v) in slotOf where v == slot! { slotOf[k] = nil }
                g.inventory.main[slot!] = ItemStack(item, 64)
                slotOf[item] = slot
            }
            if g.inventory.selected != slot! { act.slot = slot! }
        }
        switch phase {
        case 0:
            spots = candidates(w, j, from: p.pos)
            ci = 0
            if spots.isEmpty {
                // A crown over a dig, or leaves between the spots and the face: cleared first, as he would.
                let up = j.cell + IVec3(0, 1, 0)
                let clear: IVec3? = (j.want == AIR && noFaces && tree(w, up)) ? up : blocker
                if let q = clear, cut(q) { return act }
                // Nothing to place it against (the first block of a ceiling, a top slab over a wall): a plank put down
                // beside it first and broken after, as he would.
                if j.want != AIR && noFaces && scaffolds < 120 && scaffoldFor[j.cell] == nil {
                    for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1), IVec3(0, -1, 0)] {
                        let q = j.cell + d
                        guard w.block(q.x, q.y, q.z) == AIR, !(w.fieldTerrain && w.groundAt(q.x, q.y, q.z)) else { continue }
                        let backed = BuilderBot.dirs6.contains { e in let r = q + e; return r != j.cell && solid(w, r) }
                        guard backed else { continue }
                        scaffolds += 1; scaffoldFor[j.cell] = q
                        jobs.insert(BuildersGrounds.Job(cell: q, want: Draft0.plank), at: i)
                        jobs.insert(BuildersGrounds.Job(cell: q, want: AIR), at: i + 2)
                        phase = 0; ticks = 0
                        return act
                    }
                }
                later(s, "no spot: " + why); return act
            }
            phase = 4
            return act
        case 4:
            // The way to the nearest spot; none clear: the first tree cell on a way through the trees is cut.
            if let r = route(w, from: p.pos, to: spots, not: j.cell, through: false) {
                routed += 1
                ci = r.spot
                path = r.path.dropFirst().map { V3(Float($0.x) + 0.5, Float($0.y) + 0.05, Float($0.z) + 0.5) } + [spots[ci].feet]
                wp = 0; phase = 1; moveTicks = 0
                return act
            }
            if let r = route(w, from: p.pos, to: spots, not: j.cell, through: true),
               let q = r.path.lazy.flatMap({ [$0, $0 + IVec3(0, 1, 0)] }).first(where: { self.tree(w, $0) }), cut(q) { return act }
            later(s, "no way to any of \(spots.count) spots (\(why))\(lastDrop.isEmpty ? "" : "; last: " + lastDrop)")
            return act
        case 1, 2:
            let c = spots[ci]
            // Look at the aim point the whole way.
            let dv = c.aim - p.eye
            let wantYaw = atan2f(-dv.x, -dv.z)
            let wantPitch = atan2f(dv.y, simd_length(V2(dv.x, dv.z)))
            let ey = wrapAngle(wantYaw - p.yaw), ep = wantPitch - p.pitch
            act.yaw = max(-0.45, min(0.45, ey))
            act.pitch = max(-0.45, min(0.45, ep))
            let d = c.feet - p.pos
            let flat = simd_length(V2(d.x, d.z))
            if phase == 1 {
                // Flying: a landing stops it, the fly key starts it again.
                if !p.flying && flyCool == 0 && (flat > 0.6 || d.y > 0.4) { act.key = KeyBinds.key(.fly); flyCool = 12; return act }
                moveTicks += 1
                if moveTicks > 420 { drop(s, "the flight there stalled"); return act }
                // Waypoint by waypoint, each axis held to a speed that dies away as it closes (the keys are all or
                // nothing: pressed toward while slower than that, against while faster).
                if wp < path.count - 1 && simd_length(path[wp] - p.pos) < 0.45 { wp += 1 }
                let go = path[min(wp, path.count - 1)] - p.pos
                let f = V3(-sinf(p.yaw), 0, -cosf(p.yaw)), r = V3(cosf(p.yaw), 0, -sinf(p.yaw))
                func key(_ dist: Float, _ v: Float, _ top: Float) -> Float {
                    let want = max(-top, min(top, dist * 4))
                    if abs(dist) < 0.08 && abs(v) < 0.4 { return 0 }
                    return v < want - 0.4 ? 1 : (v > want + 0.4 ? -1 : 0)
                }
                act.forward = key(simd_dot(go, f), simd_dot(p.vel, f), 6)
                act.strafe = key(simd_dot(go, r), simd_dot(p.vel, r), 6)
                let ud = key(go.y, p.vel.y, 5)
                if ud > 0 { act.jump = true } else if ud < 0 { act.sneak = true }
                if wp >= path.count - 1 && flat < 0.3 && abs(d.y) < 0.3 && simd_length(p.vel) < 1.5 { phase = 2; aimTicks = 0 }
                return act
            }
            // Aiming: once the view is on the point and the game's aim is on the face and the cell, press.
            aimTicks += 1
            if abs(ey) < 0.02 && abs(ep) < 0.02 {
                if let t = g.target {
                    let ok: Bool
                    if j.want == AIR { ok = t.hit == j.cell }
                    else {
                        let at = g.placeCell(t, for: Blocks.groupBase[Int(j.want)])
                        let fy = g.hitPoint(t).y - Float(t.hit.y)
                        ok = at == j.cell && BuilderBot.wouldPlace(j.want, normal: t.normal, fracY: fy, yaw: p.yaw)
                    }
                    if ok {
                        if j.want == AIR { act.attack = true } else { act.use = true }
                        presses += 1; phase = 3; wait = 0
                        return act
                    }
                }
                if aimTicks > 12 { drop(s, "the aim never fell on the face") }
            }
            if aimTicks > 60 { drop(s, "never steadied on the face") }
            return act
        default:
            // Pressed: see what came of it.
            wait += 1
            if wait < 3 { return act }
            if BuildersGrounds.holds(w, j) { next(s, ok: true); return act }
            let b = w.block(j.cell.x, j.cell.y, j.cell.z)
            if j.want != AIR && b != AIR && !Blocks.replaceable[Int(b)] && !Blocks.isLiquid(b) {
                // The wrong state went in: break it and try again (twice at most).
                redone += 1
                let n = deferred[j.cell, default: 0] + 3
                deferred[j.cell] = n
                if n > 8 { next(s, ok: false, why: "came out as \(Blocks.key(b)) state \(Int(b - Blocks.groupBase[Int(b)]))"); return act }
                jobs.insert(BuildersGrounds.Job(cell: j.cell, want: AIR), at: i)
                phase = 0; ticks = 0
                return act
            }
            if wait > 20 { drop(s, "pressed, nothing came of it") }
            return act
        }
    }
}
