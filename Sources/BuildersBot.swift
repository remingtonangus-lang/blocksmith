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
    private var cands: [(feet: V3, aim: V3, overhead: Bool)] = []
    private var ci = 0
    private var deferred: [IVec3: Int] = [:]
    private var slotOf: [ItemID: Int] = [:], nextSlot = 0
    let cruise: Float
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
    private func candidates(_ w: World, _ j: BuildersGrounds.Job, from: V3) -> [(feet: V3, aim: V3, overhead: Bool)] {
        let c = j.cell
        var faces: [(hit: IVec3, n: IVec3, aim: V3)] = []
        let cc = V3(Float(c.x) + 0.5, Float(c.y) + 0.5, Float(c.z) + 0.5)
        if j.want == AIR {
            for d in BuilderBot.dirs6 where !solid(w, c + d) { faces.append((c, d, cc + V3(d) * 0.45)) }
        } else {
            let shape = Blocks.shape[Int(j.want)], off = Int(j.want - Blocks.groupBase[Int(j.want)])
            let wantsUpper: Bool? = shape == "stairs" ? off >= 4 : (shape == "slab" ? off == 1 : (shape == "trapdoor" ? off >= 8 : nil))
            for d in BuilderBot.dirs6 {
                let s = c + d
                let sb = w.block(s.x, s.y, s.z)
                guard solid(w, s) || (sb != AIR && !Blocks.replaceable[Int(sb)]) else { continue }
                if BuilderBot.clickable(sb, holding: j.want) { continue }
                let n = IVec3(0, 0, 0) &- d
                if shape == "door" && n.y != 1 { continue }
                if shape == "lantern" && n.y == 0 { continue }
                var a = cc + V3(d) * 0.5
                a = a - V3(d) * 0.02                      // (just on the support's face, on the cell's side)
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
            for look in BuilderBot.looks where simd_dot(look, V3(f.n)) >= 0.3 {
                for dist in [2.2, 3.0, 3.9] as [Float] {
                    let eye = f.aim + look * dist
                    let feet = eye - V3(0, 1.62, 0)
                    guard feet.y > 1, bodyFree(w, feet, not: c) else { continue }
                    let dv = f.aim - eye
                    if j.want != AIR {
                        let yaw = atan2f(-dv.x, -dv.z)
                        let fy = f.aim.y - Float(f.hit.y)
                        if !BuilderBot.wouldPlace(j.want, normal: f.n, fracY: fy, yaw: yaw) { continue }
                    }
                    guard let h = w.raycast(eye, simd_normalize(dv), maxDist: simd_length(dv) + 0.4), h.hit == f.hit else { continue }
                    spots.append((feet, f.aim, simd_length(feet - from)))
                }
            }
        }
        spots.sort { $0.2 < $1.2 }
        var out: [(feet: V3, aim: V3, overhead: Bool)] = []
        let startFree = columnFree(w, from, not: c)
        for sp in spots {
            if pathFree(w, from: from, to: sp.0, not: c) { out.append((sp.0, sp.1, false)) }
            else if startFree && columnFree(w, sp.0, not: c) { out.append((sp.0, sp.1, true)) }
            if out.count >= 6 { break }
        }
        return out
    }

    // MARK: Acting

    private func next(_ s: AgentState, ok: Bool, why: String = "") {
        if ok { if jobs[i].want == AIR { dug += 1 } else { placed += 1 } }
        else { missed.append("\(jobs[i].want == AIR ? "dig" : Blocks.key(jobs[i].want)) at \(jobs[i].cell.x) \(jobs[i].cell.y) \(jobs[i].cell.z): \(why)") }
        i += 1; phase = 0; ticks = 0; cands = []; ci = 0
    }
    // A job that can't be reached yet (nothing to click on, no spot) goes to the back, three times at most.
    private func later(_ s: AgentState, _ why: String) {
        let j = jobs[i]
        let n = deferred[j.cell, default: 0] + 1
        deferred[j.cell] = n
        if n > 8 { next(s, ok: false, why: why); return }
        jobs.remove(at: i); jobs.append(j)
        phase = 0; ticks = 0; cands = []; ci = 0
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
            cands = candidates(w, j, from: p.pos)
            ci = 0
            if cands.isEmpty { later(s, "no face to click from a free spot"); return act }
            phase = 1; moveTicks = 0
            return act
        case 1, 2:
            let c = cands[ci]
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
                if moveTicks > 420 { ci += 1; moveTicks = 0; if ci >= cands.count { later(s, "no way to a spot") }; return act }
                var go = d
                if c.overhead && flat > 0.6 && p.pos.y < cruise - 0.4 { go = V3(0, cruise - p.pos.y, 0) }      // up
                else if c.overhead && flat > 0.6 { go = V3(d.x, cruise - p.pos.y, d.z) }                       // over
                let f = V3(-sinf(p.yaw), 0, -cosf(p.yaw)), r = V3(cosf(p.yaw), 0, -sinf(p.yaw))
                let fw = simd_dot(go, f), rt = simd_dot(go, r)
                let gate = flat < 1.2 ? (s.tick % 2 == 0) : true                       // (eased in: the keys are all or nothing)
                if abs(fw) > 0.18 && gate { act.forward = fw > 0 ? 1 : -1 }
                if abs(rt) > 0.18 && gate { act.strafe = rt > 0 ? 1 : -1 }
                if go.y > 0.25 { act.jump = true } else if go.y < -0.25 { act.sneak = true }
                if flat < 0.5 && abs(d.y) < 0.5 && simd_length(p.vel) < 3 { phase = 2; aimTicks = 0 }
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
                if aimTicks > 12 { ci += 1; phase = 1; moveTicks = 0; if ci >= cands.count { later(s, "the aim never fell on the face") } }
            }
            if aimTicks > 60 { ci += 1; phase = 1; moveTicks = 0; if ci >= cands.count { later(s, "never steadied on the face") } }
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
            if wait > 20 { ci += 1; phase = 1; moveTicks = 0; if ci >= cands.count { later(s, "pressed, nothing came of it") } }
            return act
        }
    }
}
