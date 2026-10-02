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
        // Pressing on but not moving (a low wall, the rim of an empty composter or cauldron it dropped into): hop, as a
        // player would (run 348: the village bot sat in a composter for 45 s).
        let hv: Float = (s.vel.x * s.vel.x + s.vel.z * s.vel.z).squareRoot()
        if act.forward > 0.5 && s.onGround && hv < 0.3 && flat > 1 && s.tick % 30 < 2 { act.jump = true }
        // A closed wooden door straight ahead: look at it and use it.
        // Its own cell first: standing in a doorway when the door shut (a villager closes doors behind it), the panel is
        // at this cell's edge and the cell ahead holds no door (run 357: 45 s pressing against it).
        let f = V3(-sinf(s.yaw), 0, -cosf(s.yaw))
        let by = Int(floor(s.pos.y + 0.1))
        for reach in [Float(0), 0.9] {
            let ahead: V3 = s.pos + f * reach
            let bx = Int(floor(ahead.x)), bz = Int(floor(ahead.z))
            let b = a.world.block(bx, by, bz)
            guard Blocks.shape[Int(b)] == "door" && PathFinder.isWoodDoor(b) else { continue }
            if reach == 0 && hv >= 0.3 { break }               // walking out of the doorway: the panel isn't in the way
            let st = Int(b - Blocks.groupBase[Int(b)])
            if st & 4 == 0 {                                   // closed
                act.forward = 0
                act.pitch = max(-0.2, min(0.2, -0.25 - s.pitch))
                if let t = s.target, t.x == bx && t.z == bz { act.use = (s.tick % 6) < 3 }
            }
            break
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
    var reportedNoPath = false
    var waterTarget = false          // heading for water: arrived only once in it (stopping on the shore never swam)
    init(seed: UInt64) { rng = SRng(seed) }

    func pick(_ s: AgentState, _ a: Agent) {
        var best: V3?
        for k in 0..<10 {
            let ang: Float = rng.float() * 2 * .pi
            // Within the pathfinder's range (48 blocks Manhattan).
            let d: Float = 16 + rng.float() * 14
            let x = Int(floor(s.pos.x + sinf(ang) * d)), z = Int(floor(s.pos.z + cosf(ang) * d))
            let y = a.world.topY(x, z) + 1
            // Ground, not tree tops: a target on a canopy had the bot climbing trees and stranding itself up there.
            let tk = Blocks.key(Blocks.groupBase[Int(a.world.block(x, y - 1, z))])
            if tk.hasSuffix("leaves") || tk.hasSuffix("_log") || tk.hasSuffix("_wood") { continue }
            let c = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
            let ck = floorDiv(x, CS) &* 1_000_003 &+ floorDiv(z, CS)
            best = c
            if !a.visitedChunks.contains(ck) || k == 9 { break }
        }
        // Until it has swum: head for visible water within 30 blocks now and then.
        waterTarget = false
        if !swam && chosen % 2 == 1 {
            search: for r in stride(from: 4, through: 44, by: 2) { for k in 0..<16 {
                let ang: Float = Float(k) / 16 * 2 * .pi
                let x = Int(floor(s.pos.x + sinf(ang) * Float(r))), z = Int(floor(s.pos.z + cosf(ang) * Float(r)))
                let ty = a.world.topY(x, z)
                if Blocks.fluidKind[Int(a.world.block(x, ty, z))] == 1 { best = V3(Float(x) + 0.5, Float(ty), Float(z) + 0.5); waterTarget = true; break search }
            } }
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
        if path.isEmpty && !reportedNoPath {
            // Why the pathfinder can't leave this spot: the blocks around the feet and each neighbour's stand cost.
            reportedNoPath = true
            let f = PathFinder.anchor(s.pos, span: 1)
            func k(_ x: Int, _ y: Int, _ z: Int) -> String { Blocks.key(a.world.block(x, y, z)) }
            var ns: [String] = []
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let c = [-1, 0, 1].map { dy -> String in PathFinder.standCost(a.world, f.x + dx, f.y + dy, f.z + dz, pr).map { String(format: "%.0f", $0) } ?? "-" }
                ns.append("\(dx),\(dz): \(k(f.x + dx, f.y, f.z + dz))/\(k(f.x + dx, f.y + 1, f.z + dz)) cost \(c.joined(separator: " "))")
            }
            let head: String = String(format: "agent explorer: no path from %.2f %.2f %.2f to %.0f %.0f %.0f", s.pos.x, s.pos.y - Float(YOFF), s.pos.z, t.x, t.y - Float(YOFF), t.z)
            let fk = k(f.x, f.y, f.z), hk = k(f.x, f.y + 1, f.z), uk = k(f.x, f.y - 1, f.z)
            let around = ns.joined(separator: "; ")
            print("\(head); feet \(fk), head \(hk), under \(uk); \(around)")
        }
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
        if flatToT < 1.5 && (!waterTarget || s.inWater) { reached += 1; pick(s, a); return act }
        if waterTarget && flatToT < 1.5 { act = Steer.toward(s, a, t); act.jump = true; return act }   // wade in
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
    var trace: [IVec3] = []          // where the bot was each second on the current door (printed when it fails)
    var plans: [Int] = []            // node counts of the paths planned for the current door (0: no path)

    init(world w: World, village s: StructureStart) {
        PathFinder.doors = true
        for y in max(1, s.min.y)...min(CH - 3, s.max.y) { for z in s.min.z...s.max.z { for x in s.min.x...s.max.x {
            let b = w.block(x, y, z)
            guard Blocks.shape[Int(b)] == "door" else { continue }
            let st = Int(b - Blocks.groupBase[Int(b)])
            if st & 8 != 0 { continue }
            let (ax, az) = (st & 3) < 2 ? (0, 1) : (1, 0)
            // Inside: the side roofed over further in (any block 2-10 above each of the 3 cells in from the door; roofs
            // are stairs and slabs). One cell scored the eave over a street between two facing houses as much as the
            // room (run 353, seed 777: the bot was sent into the street and climbed onto the eave).
            var best = 0, bestSide = 0
            for sgn in [-1, 1] {
                var cover = 0
                for depth in 1...3 {
                    let cx = x + ax * sgn * depth, cz = z + az * sgn * depth
                    var roofed = false
                    for dy in 2...10 where w.block(cx, y + dy, cz) != AIR { roofed = true; break }
                    if roofed { cover += 1 }
                }
                if cover > best { best = cover; bestSide = sgn }
            }
            if best > 0 { doors.append(Door(door: IVec3(x, y, z), inside: IVec3(x + ax * bestSide, y, z + az * bestSide))) }
        } } }
        PathFinder.doors = false
    }

    // Two vertical slices through a door (front-to-back through the doorway, and along the wall), 9 wide,
    // from 3 below to 8 above the sill: # full block, D door, s stairs, _ slab, o other partial, ~ liquid,
    // . air, B the bot's feet. Rows top-down; the door column is the middle one.
    static func section(_ w: World, _ d: Door, bot: IVec3) -> [String] {
        let fx = d.inside.x - d.door.x, fz = d.inside.z - d.door.z          // inward
        var out: [String] = []
        for (name, ax, az) in [("through the door (left: outside, right: inside)", fx, fz), ("along the wall", fz, fx)] {
            out.append(name)
            for dy in stride(from: 8, through: -3, by: -1) {
                var row = String(format: "%+3d ", dy)
                for k in -4...4 {
                    let x = d.door.x + ax * k, y = d.door.y + dy, z = d.door.z + az * k
                    let b = w.block(x, y, z)
                    var c: Character = "o"
                    if x == bot.x && y == bot.y && z == bot.z { c = "B" }
                    else if b == AIR { c = "." }
                    else if Blocks.isLiquid(b) { c = "~" }
                    else if !Blocks.collide[Int(b)] { c = "," }
                    else if Blocks.shape[Int(b)] == "door" { c = "D" }
                    else if Blocks.shape[Int(b)] == "stairs" { c = "s" }
                    else if Blocks.shape[Int(b)] == "slab" { c = "_" }
                    else if Blocks.fullCollide[Int(b)] { c = "#" }
                    row.append(c)
                }
                out.append(row)
            }
        }
        return out
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
        if ticks % 60 == 1 { trace.append(IVec3(Int(floor(s.pos.x)), Int(floor(s.pos.y)) - YOFF, Int(floor(s.pos.z)))) }
        if flat < 0.6 && abs(goal.y - s.pos.y) < 1.1 {
            results.append(("enter the building with the door at \(d.door.x) \(d.door.y - YOFF) \(d.door.z)", true, "in after \(ticks / 60) s"))
            next(s); return act
        }
        if ticks > 60 * 45 {
            let feet = IVec3(Int(floor(s.pos.x)), Int(floor(s.pos.y)), Int(floor(s.pos.z)))
            results.append(("enter the building with the door at \(d.door.x) \(d.door.y - YOFF) \(d.door.z)", false,
                            String(format: "came within %.1f blocks in 45 s; stopped at %d %d %d", best, feet.x, feet.y - YOFF, feet.z)))
            a.flag("goal_failed", "couldn't walk into the building at door \(d.door.x) \(d.door.y - YOFF) \(d.door.z)")
            print("agent village: unmet door \(d.door.x) \(d.door.y - YOFF) \(d.door.z), inside \(d.inside.x) \(d.inside.z), bot \(feet.x) \(feet.y - YOFF) \(feet.z)")
            for line in VillageBot.section(a.world, d, bot: feet) { print("  " + line) }
            print("  paths planned (nodes, 0 = none): \(plans.prefix(24).map(String.init).joined(separator: " "))")
            print("  trace (1/s): \(trace.map { "\($0.x),\($0.y),\($0.z)" }.joined(separator: " "))")
            next(s); return act
        }
        if idx >= path.count || since > 150 {
            var pr = PathProfile()
            pr.doors = true
            // A player drops off a roof (a 6-block fall costs 3 hearts); with 3 the bot stayed stranded on an eave it
            // had walked onto from a hillside (run 355 seed 777: every replan from the roof found no path).
            pr.maxDrop = 6
            path = PathFinder.find(a.world, from: s.pos, to: goal, profile: pr, maxNodes: 4000) ?? []
            plans.append(path.count)
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

    func next(_ s: AgentState) { cur += 1; ticks = 0; path = []; idx = 0; since = 0; best = 999; trace = []; plans = [] }

    func goals() -> [(String, Bool, String)] {
        if doors.isEmpty { return [("find doors in the village", false, "no doors found")] }
        return results
    }
}

// Village life: open a villager's trade screen, then at nightfall sleep in a village bed and wake in the morning
// (Remington's explorer goals "trade", "sleep", "survive a night"). Starts at the village plaza shortly before
// sunset (a disclosed fixture: header time). The game's toasts ("You can only sleep at night", "monsters nearby")
// are kept as the reason when a goal fails.
final class LifeBot: AgentBot {
    let name = "life"
    static let startTime: Double = 0.47          // day fraction: a little before sunset
    let village: StructureStart
    var phase = 0                       // 0 trade, 1 bed, 2 asleep / waiting for morning, 3 done
    var traded = false, slept = false, morning = false
    var tradeDetail = "no villager with a trade nearby", sleepDetail = "no bed reached", morningDetail = "never slept"
    var lastToast = ""
    var hooked = false
    var path: [IVec3] = []
    var idx = 0, since = 0, phaseTicks = 0, uses = 0
    weak var trader: Mob?
    var tried: [ObjectIdentifier] = []
    var bed: IVec3?
    init(village v: StructureStart) { village = v }

    func aim(_ s: AgentState, _ p: V3, into act: inout AgentAction) -> Bool {
        let eye = s.pos + V3(0, 1.62, 0)
        let d = p - eye
        let flat: Float = (d.x * d.x + d.z * d.z).squareRoot()
        let turn: Float = wrapAngle(atan2f(-d.x, -d.z) - s.yaw)
        let wantPitch: Float = atan2f(d.y, max(0.01, flat))
        act.yaw = max(-0.3, min(0.3, turn))
        act.pitch = max(-0.2, min(0.2, wantPitch - s.pitch))
        return abs(turn) < 0.06 && abs(wantPitch - s.pitch) < 0.06
    }

    func walk(_ s: AgentState, _ a: Agent, to goal: V3) -> AgentAction {
        if idx >= path.count || since > 90 {
            var pr = PathProfile()
            pr.doors = true
            // A player drops off a roof (a 6-block fall costs 3 hearts); with 3 the bot stayed stranded on an eave it
            // had walked onto from a hillside (run 355 seed 777: every replan from the roof found no path).
            pr.maxDrop = 6
            path = PathFinder.find(a.world, from: s.pos, to: goal, profile: pr, maxNodes: 4000) ?? []
            idx = 0; since = 0
        }
        since += 1
        if idx < path.count {
            let wp = path[idx]
            let c = V3(Float(wp.x) + 0.5, Float(wp.y), Float(wp.z) + 0.5)
            if simd_length(V2(c.x - s.pos.x, c.z - s.pos.z)) < 0.4 && abs(c.y - s.pos.y) < 1.3 { idx += 1; since = 0 }
            return Steer.toward(s, a, c)
        }
        return Steer.toward(s, a, goal)
    }

    func act(_ s: AgentState, _ a: Agent) -> AgentAction {
        if !hooked {
            hooked = true
            let prev = a.game.onToast
            a.game.onToast = { [weak self] t in self?.lastToast = t; prev?(t) }
        }
        phaseTicks += 1
        var act = AgentAction()
        switch phase {
        case 0:
            if let m = s.menu {
                if m.contains("Merchant") { traded = true; tradeDetail = "trade screen opened after \(phaseTicks / 60) s" }
                act.key = Key.esc
                if traded { phase = 1; phaseTicks = 0; path = [] }
                return act
            }
            if phaseTicks > 60 * 50 { tradeDetail += "; gave up after 50 s"; phase = 1; phaseTicks = 0; path = []; return act }
            if trader == nil || trader!.health <= 0 || uses > 40 {
                if let t = trader { tried.append(ObjectIdentifier(t)) }
                trader = nil; uses = 0; path = []
                var best: Float = 64
                for m in a.game.mobs.of(.villager) where m.health > 0 && !m.baby && !tried.contains(ObjectIdentifier(m)) {
                    let prof = m.villager?.profession ?? "none"
                    if prof == "none" || prof == "nitwit" { continue }
                    let d = simd_length(m.pos - s.pos)
                    if d < best { best = d; trader = m }
                }
                guard trader != nil else { return act }
                tradeDetail = "walked to a villager but no trade screen opened"
            }
            guard let t = trader else { return act }
            let d: Float = simd_length(V2(t.pos.x - s.pos.x, t.pos.z - s.pos.z))
            if d > 2.2 {
                if phaseTicks % 60 == 0 { path = [] }                        // it moves: re-plan each second
                return walk(s, a, to: t.pos)
            }
            if aim(s, t.pos + V3(0, t.height * 0.75, 0), into: &act) {
                uses += 1
                act.use = uses % 4 < 2
            }
            return act
        case 1:
            if s.menu != nil { act.key = Key.esc; return act }
            if bed == nil {
                // The nearest bed in the village (foot half), searched once.
                var best = Int.max
                for y in max(1, village.min.y)...min(CH - 3, village.max.y) { for z in village.min.z...village.max.z { for x in village.min.x...village.max.x {
                    let k = Blocks.key(Blocks.groupBase[Int(a.world.block(x, y, z))])
                    guard k.hasSuffix("_bed") else { continue }
                    let d = abs(x - Int(s.pos.x)) + abs(z - Int(s.pos.z)) + abs(y - Int(s.pos.y))
                    if d < best { best = d; bed = IVec3(x, y, z) }
                } } }
                guard bed != nil else { sleepDetail = "no bed in the village"; phase = 3; return act }
            }
            guard let b = bed else { return act }
            if s.sleeping { slept = true; sleepDetail = String(format: "asleep at day time %.2f", s.timeOfDay); phase = 2; phaseTicks = 0; return act }
            if phaseTicks > 60 * 70 {
                sleepDetail = "couldn't sleep in the bed at \(b.x) \(b.y - YOFF) \(b.z)" + (lastToast.isEmpty ? "" : " (\"\(lastToast)\")")
                phase = 3; return act
            }
            let c = V3(Float(b.x) + 0.5, Float(b.y), Float(b.z) + 0.5)
            let d: Float = simd_length(V2(c.x - s.pos.x, c.z - s.pos.z))
            if d > 2.0 { sleepDetail = "walking to the bed"; return walk(s, a, to: c) }
            // At the bed: wait for night, then use it.
            if aim(s, c + V3(0, 0.3, 0), into: &act) && s.timeOfDay > 0.53 && s.timeOfDay < 0.95 {
                uses += 1
                act.use = uses % 20 < 2
            }
            return act
        case 2:
            if !s.sleeping && (s.timeOfDay < 0.1 || s.timeOfDay > 0.97) {
                morning = true; morningDetail = String(format: "woke at day time %.2f after %d s", s.timeOfDay, phaseTicks / 60); phase = 3
            } else if phaseTicks > 60 * 40 {
                morningDetail = String(format: "still %@ at day time %.2f after 40 s", s.sleeping ? "asleep" : "awake", s.timeOfDay); phase = 3
            }
            return act
        default:
            return act
        }
    }

    func goals() -> [(String, Bool, String)] {
        [("open a villager's trade screen", traded, tradeDetail),
         ("sleep in a village bed at night", slept, sleepDetail),
         ("the night passes while asleep", morning, morningDetail)]
    }
}

// Down into a cave and back up (Remington's explorer goal "cave down and back"): the nearest cave floor at least 10
// blocks under the surface that a path reaches (dark: no sky light), walked to on foot, then back to the start.
final class CaveBot: AgentBot {
    let name = "cave"
    var phase = 0                        // 0 pick, 1 down, 2 back, 3 done, 4 roam further to search again
    var roams = 0
    var roamTo = V3(0, 0, 0)
    var origin = V3(0, 0, 0)
    var down = false, back = false
    var downDetail = "no cave floor within 64 blocks with a walkable way down and back", backDetail = "never got down"
    var start = V3(0, 0, 0)
    var goal = V3(0, 0, 0)
    var path: [IVec3] = []
    var idx = 0, since = 0, phaseTicks = 0, stalls = 0
    var deepest: Float = 999

    func plan(_ s: AgentState, _ a: Agent, to t: V3) {
        var pr = PathProfile()
        pr.doors = true
        pr.waterCost = 3
        path = PathFinder.find(a.world, from: s.pos, to: t, profile: pr, maxNodes: 8000) ?? []
        idx = 0; since = 0
    }

    func act(_ s: AgentState, _ a: Agent) -> AgentAction {
        if s.menu != nil { var k = AgentAction(); k.key = Key.esc; return k }
        phaseTicks += 1
        deepest = min(deepest, s.pos.y)
        switch phase {
        case 4:
            // Walking on to search from further away (a human looking for a cave keeps walking).
            let flat: Float = simd_length(V2(roamTo.x - s.pos.x, roamTo.z - s.pos.z))
            if flat < 2 || phaseTicks > 60 * 40 { phase = 0; phaseTicks = 0; path = []; return AgentAction() }
            if idx >= path.count || since > 180 { plan(s, a, to: roamTo) }
            since += 1
            guard idx < path.count else { return Steer.toward(s, a, roamTo) }
            let wp = path[idx]
            let c = V3(Float(wp.x) + 0.5, Float(wp.y), Float(wp.z) + 0.5)
            if simd_length(V2(c.x - s.pos.x, c.z - s.pos.z)) < 0.4 && abs(c.y - s.pos.y) < 1.3 { idx += 1; since = 0 }
            var act = Steer.toward(s, a, c)
            if since > 60 && s.onGround { act.jump = true }
            return act
        case 0:
            start = s.pos
            // Cave floors 10+ blocks under the start that a walk from the start actually reaches (breadth-first over the
            // walk model, nearest by steps first). Picking the nearest dark floors by distance tried enclosed pockets
            // with no way in: seeds 12345 and 777 found no cave in 48 blocks (runs 356, 357).
            let sc = IVec3(Int(floor(s.pos.x)), Int(floor(s.pos.y)), Int(floor(s.pos.z)))
            let lo = IVec3(sc.x - 64, max(2, sc.y - 60), sc.z - 64), hi = IVec3(sc.x + 64, sc.y + 16, sc.z + 64)
            let order = StructCheck.walkOrder(a.world, seeds: [sc], lo: lo, hi: hi, jump: true, limit: 250_000).cells
            var cands: [(Float, IVec3)] = []
            for c in order where c.y <= sc.y - 10 && a.world.lightAt(c.x, c.y, c.z).sky == 0 {
                let near = cands.contains { (e: (Float, IVec3)) -> Bool in abs(e.1.x - c.x) + abs(e.1.z - c.z) < 6 }
                if near { continue }
                cands.append((Float(cands.count), c))
                if cands.count >= 25 { break }
            }
            for (_, c) in cands {
                let t = V3(Float(c.x) + 0.5, Float(c.y), Float(c.z) + 0.5)
                plan(s, a, to: t)
                guard let last = path.last, abs(last.x - c.x) <= 1 && abs(last.z - c.z) <= 1 && abs(last.y - c.y) <= 1 else { continue }
                // Only a floor a path also leads back up from: the way down may drop further than a jump climbs (a
                // one-way drop into a cave is ordinary terrain, not a bug; run 353 seed 12345 got down and found no way back).
                var pr2 = PathProfile()
                pr2.doors = true
                pr2.waterCost = 3
                let up = PathFinder.find(a.world, from: t, to: s.pos, profile: pr2, maxNodes: 8000) ?? []
                let sx = Int(floor(s.pos.x)), sy = Int(floor(s.pos.y)), sz = Int(floor(s.pos.z))
                if let top = up.last, abs(top.x - sx) <= 1 && abs(top.z - sz) <= 1 && abs(top.y - sy) <= 1 {
                    goal = t; phase = 1; phaseTicks = 0
                    downDetail = "walking to the cave floor at \(c.x) \(c.y - YOFF) \(c.z)"
                    return AgentAction()
                }
            }
            // None here: walk on to the farthest surface cell the walk reached (about level with the start) and look
            // again (seed 777 had no walkable cave within 64 blocks of spawn: run 359).
            // The farthest from where the bot first stood (BFS order's last cell is farthest by steps, which led the
            // second roam back toward spawn: seed 777, run 362), up to four times.
            if roams == 0 { origin = s.pos }
            let fromOrigin: (IVec3) -> Float = { c in simd_length(V2(Float(c.x) - self.origin.x, Float(c.z) - self.origin.z)) }
            if roams < 4, let far = order.filter({ abs($0.y - sc.y) <= 6 }).max(by: { fromOrigin($0) < fromOrigin($1) }),
               abs(far.x - sc.x) + abs(far.z - sc.z) > 24 {
                roams += 1
                roamTo = V3(Float(far.x) + 0.5, Float(far.y), Float(far.z) + 0.5)
                downDetail = "no cave floor within 64 blocks; walking on to \(far.x) \(far.z) to look again (\(roams))"
                phase = 4; phaseTicks = 0; plan(s, a, to: roamTo)
                return AgentAction()
            }
            path = []
            phase = 3
            return AgentAction()
        case 1, 2:
            let t = phase == 1 ? goal : start
            let flat: Float = simd_length(V2(t.x - s.pos.x, t.z - s.pos.z))
            if flat < 1.5 && abs(t.y - s.pos.y) < 1.5 {
                if phase == 1 {
                    down = true; downDetail = "reached the cave floor \(Int(start.y - s.pos.y)) blocks down in \(phaseTicks / 60) s"
                    phase = 2; phaseTicks = 0; backDetail = "walking back up"; plan(s, a, to: start)
                } else {
                    back = true; backDetail = "back at the start in \(phaseTicks / 60) s"; phase = 3
                }
                return AgentAction()
            }
            if phaseTicks > 60 * 60 {
                let at = String(format: "%.0f %.0f %.0f", s.pos.x, s.pos.y - Float(YOFF), s.pos.z)
                if phase == 1 { downDetail = "didn't reach the cave floor in 60 s (stopped at \(at))" } else { backDetail = "didn't get back up in 60 s (stopped at \(at))" }
                a.flag("goal_failed", phase == 1 ? "couldn't walk down to the cave floor" : "couldn't walk back up out of the cave")
                phase = 3
                return AgentAction()
            }
            if idx >= path.count || since > 180 {
                if since > 180 { stalls += 1 }
                plan(s, a, to: t)
            }
            since += 1
            guard idx < path.count else { return Steer.toward(s, a, t) }
            let wp = path[idx]
            let c = V3(Float(wp.x) + 0.5, Float(wp.y), Float(wp.z) + 0.5)
            if simd_length(V2(c.x - s.pos.x, c.z - s.pos.z)) < 0.4 && abs(c.y - s.pos.y) < 1.3 { idx += 1; since = 0 }
            var act = Steer.toward(s, a, c)
            if since > 60 && s.onGround { act.jump = true }
            return act
        default:
            return AgentAction()
        }
    }

    func goals() -> [(String, Bool, String)] {
        [("walk down into a cave (10+ blocks under the surface)", down, downDetail),
         ("walk back up out of it", back, backDetail)]
    }
}
