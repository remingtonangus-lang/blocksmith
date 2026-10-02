import Foundation
import simd

// Bots for the agent runner (Agent.swift). They walk (never fly), see only what AgentState and the world blocks
// around them show, and act only through AgentAction.

@inline(__always) func wrapAngle(_ a: Float) -> Float {
    var x = a.truncatingRemainder(dividingBy: 2 * .pi)
    if x > .pi { x -= 2 * .pi }
    if x < -.pi { x += 2 * .pi }
    return x
}

// Steering shared by the walking bots: turn toward a point (capped rate), level the view, walk, jump up steps,
// swim up in water, open a closed wooden door in the way with the use button.
struct Steer {
    static func toward(_ s: AgentState, _ a: Agent, _ goal: V3, run: Bool = false) -> AgentAction {
        var act = AgentAction()
        let dx: Float = goal.x - s.pos.x, dz: Float = goal.z - s.pos.z
        let want: Float = atan2f(-dx, -dz)
        let turn: Float = wrapAngle(want - s.yaw)
        act.yaw = max(-0.3, min(0.3, turn))
        act.pitch = max(-0.2, min(0.2, -s.pitch * 0.3))
        let flat: Float = (dx * dx + dz * dz).squareRoot()
        act.forward = abs(turn) < 0.9 ? 1 : 0.2
        if flat < 0.3 { act.forward = 0 }
        act.sprint = run && flat > 6
        // Step or jump up when the goal is higher, swim up in water.
        if (goal.y > s.pos.y + 0.55 && s.onGround && flat < 1.8) || s.inWater { act.jump = true }
        // A closed wooden door straight ahead: look at it and use it.
        let f = V3(-sinf(s.yaw), 0, -cosf(s.yaw))
        let ahead: V3 = s.pos + f * 0.9
        let bx = Int(floor(ahead.x)), by = Int(floor(s.pos.y + 0.1)), bz = Int(floor(ahead.z))
        let b = a.world.block(bx, by, bz)
        if Blocks.shape[Int(b)] == "door" && PathFinder.isWoodDoor(b) {
            let st = Int(b - Blocks.groupBase[Int(b)])
            if st & 4 == 0 {                                   // closed
                act.forward = 0
                act.pitch = max(-0.2, min(0.2, -0.25 - s.pitch))
                if let t = s.target, t.x == bx && t.z == bz { act.use = (s.tick % 6) < 3 }
            }
        }
        return act
    }
}

// Random input with persistence: holds an intent for a while, then rolls a new one. Taps menus now and then
// (inventory, escape, hotbar) and uses / attacks whatever is in front.
final class MonkeyBot: AgentBot {
    let name = "monkey"
    var rng: SRng
    var intent = AgentAction()
    var left = 0
    init(seed: UInt64) { rng = SRng(seed) }
    func act(_ s: AgentState, _ a: Agent) -> AgentAction {
        if left <= 0 {
            left = rng.range(10, 90)
            var i = AgentAction()
            i.forward = [1, 1, 1, 0, -1][rng.int(5)]
            i.strafe = [-1, 0, 0, 0, 1][rng.int(5)]
            i.yaw = (rng.float() - 0.5) * 0.12
            i.pitch = (rng.float() - 0.5) * 0.04
            i.jump = rng.chance(0.25)
            i.sneak = rng.chance(0.08)
            i.sprint = rng.chance(0.3)
            i.attack = rng.chance(0.2)
            i.use = rng.chance(0.12)
            intent = i
        }
        left -= 1
        var act = intent
        act.slot = -1
        act.key = 0xFFFF
        let roll = rng.int(1000)
        if roll < 4 { act.key = KeyBinds.key(.inventory) }
        else if roll < 8 || (s.menu != nil && roll < 40) { act.key = Key.esc }
        else if roll < 20 { act.slot = rng.int(9) }
        if s.pitch > 1.2 && act.pitch > 0 { act.pitch = -0.02 }
        if s.pitch < -1.2 && act.pitch < 0 { act.pitch = 0.02 }
        return act
    }
    func goals() -> [(String, Bool, String)] { [] }
}

// Curiosity: keeps choosing targets 20-40 blocks away in chunks it hasn't visited, walks there along the
// pathfinder's route, and reports routes the pathfinder believes in but the body can't follow (path_stuck).
final class ExplorerBot: AgentBot {
    let name = "explorer"
    var rng: SRng
    var target: V3?
    var path: [IVec3] = []
    var idx = 0
    var since = 0                      // ticks without reaching the next waypoint
    var targetTicks = 0
    var repaths = 0
    var reached = 0, failed = 0, chosen = 0
    var swam = false, wentDown = false, cameBack = false
    var startY: Float = 0
    var lowest: Float = 999
    init(seed: UInt64) { rng = SRng(seed) }

    func pick(_ s: AgentState, _ a: Agent) {
        var best: V3?
        for k in 0..<10 {
            let ang: Float = rng.float() * 2 * .pi
            let d: Float = 20 + rng.float() * 20
            let x = Int(floor(s.pos.x + sinf(ang) * d)), z = Int(floor(s.pos.z + cosf(ang) * d))
            let y = a.world.topY(x, z) + 1
            let c = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
            let ck = floorDiv(x, CS) &* 1_000_003 &+ floorDiv(z, CS)
            best = c
            if !a.visitedChunks.contains(ck) || k == 9 { break }
        }
        target = best
        chosen += 1
        targetTicks = 0
        repaths = 0
        replan(s, a)
    }

    func replan(_ s: AgentState, _ a: Agent) {
        guard let t = target else { return }
        var pr = PathProfile()
        pr.doors = true
        pr.waterCost = 2
        path = PathFinder.find(a.world, from: s.pos, to: t, profile: pr, maxNodes: 3000) ?? []
        idx = 0
        since = 0
    }

    func act(_ s: AgentState, _ a: Agent) -> AgentAction {
        if s.tick == 0 { startY = s.pos.y }
        if s.inWater { swam = true }
        lowest = min(lowest, s.pos.y)
        if s.pos.y < startY - 12 { wentDown = true }
        if wentDown && s.pos.y > startY - 3 { cameBack = true }
        var act = AgentAction()
        if s.menu != nil { act.key = Key.esc; return act }
        if target == nil { pick(s, a) }
        targetTicks += 1
        since += 1
        guard let t = target else { return act }
        let flatToT: Float = simd_length(V2(t.x - s.pos.x, t.z - s.pos.z))
        if flatToT < 1.5 { reached += 1; pick(s, a); return act }
        if targetTicks > 60 * 45 { failed += 1; pick(s, a); return act }
        if idx >= path.count {
            if path.isEmpty || targetTicks % 120 == 0 { replan(s, a) }
            if path.isEmpty { failed += 1; pick(s, a); return act }
        }
        if idx < path.count {
            let wp = path[idx]
            let c = V3(Float(wp.x) + 0.5, Float(wp.y), Float(wp.z) + 0.5)
            let flat: Float = simd_length(V2(c.x - s.pos.x, c.z - s.pos.z))
            if flat < 0.4 && abs(c.y - s.pos.y) < 1.3 { idx += 1; since = 0 }
            if since > 180 {
                // The route says this step is walkable; the body has not managed it in 3 s.
                let here = IVec3(Int(floor(s.pos.x)), Int(floor(s.pos.y)), Int(floor(s.pos.z)))
                let below = Blocks.key(a.world.block(wp.x, wp.y - 1, wp.z)), at = Blocks.key(a.world.block(wp.x, wp.y, wp.z))
                a.flag("path_stuck", "from \(here.x) \(here.y - YOFF) \(here.z) to waypoint \(wp.x) \(wp.y - YOFF) \(wp.z) (\(at) on \(below))")
                repaths += 1
                if repaths > 3 { failed += 1; pick(s, a); return act }
                replan(s, a)
                return act
            }
            act = Steer.toward(s, a, c)
            if since > 60 && s.onGround { act.jump = true }            // nudge over a lip
        }
        return act
    }

    func goals() -> [(String, Bool, String)] {
        let rate: Float = chosen > 0 ? Float(reached) / Float(chosen) : 0
        return [("reach most chosen targets on foot", rate >= 0.6, "\(reached) of \(chosen) reached, \(failed) given up"),
                ("swim at least once", swam, swam ? "swam" : "never entered water")]
    }
}

// Walks into every building of a village through its door (opening it with the use button), one door after
// another, nearest first. Each door is a goal: a door a player would expect to walk through and can't is a bug.
final class VillageBot: AgentBot {
    let name = "village"
    struct Door { let door: IVec3; let inside: IVec3 }
    var doors: [Door] = []
    var results: [(String, Bool, String)] = []
    var cur = 0
    var ticks = 0
    var path: [IVec3] = []
    var idx = 0
    var since = 0
    var best: Float = 999
    var started = false

    init(world w: World, village s: StructureStart) {
        PathFinder.doors = true
        for y in max(1, s.min.y)...min(CH - 3, s.max.y) { for z in s.min.z...s.max.z { for x in s.min.x...s.max.x {
            let b = w.block(x, y, z)
            guard Blocks.shape[Int(b)] == "door" else { continue }
            let st = Int(b - Blocks.groupBase[Int(b)])
            if st & 8 != 0 { continue }
            let (ax, az) = (st & 3) < 2 ? (0, 1) : (1, 0)
            // Inside: the side with a roof above it.
            for sgn in [-1, 1] {
                let cx = x + ax * sgn, cz = z + az * sgn
                var roofed = false
                for dy in 2...7 where w.block(cx, y + dy, cz) != AIR && Blocks.fullCollide[Int(w.block(cx, y + dy, cz))] { roofed = true; break }
                if roofed { doors.append(Door(door: IVec3(x, y, z), inside: IVec3(cx, y, cz))); break }
            }
        } } }
        PathFinder.doors = false
    }

    func act(_ s: AgentState, _ a: Agent) -> AgentAction {
        var act = AgentAction()
        if s.menu != nil { act.key = Key.esc; return act }
        if !started { started = true; order(s) }
        guard cur < min(doors.count, 12) else { return act }
        let d = doors[cur]
        let goal = V3(Float(d.inside.x) + 0.5, Float(d.inside.y), Float(d.inside.z) + 0.5)
        let flat: Float = simd_length(V2(goal.x - s.pos.x, goal.z - s.pos.z))
        best = min(best, flat)
        ticks += 1
        if flat < 0.6 && abs(goal.y - s.pos.y) < 1.1 {
            results.append(("enter the building with the door at \(d.door.x) \(d.door.y - YOFF) \(d.door.z)", true, "in after \(ticks / 60) s"))
            next(s); return act
        }
        if ticks > 60 * 45 {
            let feet = IVec3(Int(floor(s.pos.x)), Int(floor(s.pos.y)), Int(floor(s.pos.z)))
            results.append(("enter the building with the door at \(d.door.x) \(d.door.y - YOFF) \(d.door.z)", false,
                            String(format: "came within %.1f blocks in 45 s; stopped at %d %d %d", best, feet.x, feet.y - YOFF, feet.z)))
            a.flag("goal_failed", "couldn't walk into the building at door \(d.door.x) \(d.door.y - YOFF) \(d.door.z)")
            next(s); return act
        }
        if idx >= path.count || since > 150 {
            var pr = PathProfile()
            pr.doors = true
            path = PathFinder.find(a.world, from: s.pos, to: goal, profile: pr, maxNodes: 4000) ?? []
            idx = 0; since = 0
        }
        since += 1
        if idx < path.count {
            let wp = path[idx]
            let c = V3(Float(wp.x) + 0.5, Float(wp.y), Float(wp.z) + 0.5)
            if simd_length(V2(c.x - s.pos.x, c.z - s.pos.z)) < 0.4 && abs(c.y - s.pos.y) < 1.3 { idx += 1; since = 0 }
            act = Steer.toward(s, a, c, run: true)
        } else {
            act = Steer.toward(s, a, goal)
        }
        return act
    }

    func order(_ s: AgentState) {
        // Nearest-neighbour tour from the start.
        var left = doors, out: [Door] = []
        var p = s.pos
        while !left.isEmpty {
            var bi = 0
            var bd: Float = .greatestFiniteMagnitude
            for (i, d) in left.enumerated() {
                let dd: Float = simd_length(V3(Float(d.inside.x), Float(d.inside.y), Float(d.inside.z)) - p)
                if dd < bd { bd = dd; bi = i }
            }
            let d = left.remove(at: bi)
            out.append(d)
            p = V3(Float(d.inside.x), Float(d.inside.y), Float(d.inside.z))
        }
        doors = out
    }

    func next(_ s: AgentState) { cur += 1; ticks = 0; path = []; idx = 0; since = 0; best = 999 }

    func goals() -> [(String, Bool, String)] {
        if doors.isEmpty { return [("find doors in the village", false, "no doors found")] }
        return results
    }
}
