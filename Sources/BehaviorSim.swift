import Foundation
import Metal
import simd

// Mob behaviour sim (--behaviorsim [--seeds a,b] [--minutes N] [--out FILE]): a real village runs headless
// through Game.tick for N minutes of game time (default a full day: work, meeting, night), with the player
// hovering out of the way. Every mob is sampled once a second and flagged when it:
//   in_wall        overlaps a solid block for 2+ s
//   stuck          wants to move (moving) but covers < 0.5 blocks in 10 s while away from its goal
//   spinning       turns > 2 full circles in 10 s while covering < 1.5 blocks
//   jitter         reverses direction > 12 times in 10 s
//   fell           lands more than 4.5 blocks below where it last stood (not swimming or flying)
//   strayed        a villager ends up > 48 blocks from home
// and every villager is scored on its schedule goals: its job site during work hours, the bell at meeting time
// and its bed at night (never within 2 blocks during that phase = goal_missed, with the closest distance).
enum BehaviorSim {
    final class Track {
        let mob: Mob
        var last: V3
        var window: [V3] = []
        var yawSum: Float = 0
        var lastYaw: Float
        var lastVel = V3(0, 0, 0)
        var reversals = 0
        var wallSeconds = 0
        var startY: Float
        var groundY: Float?                   // feet height when last standing (falls are ground-to-ground drops)
        var flags: [String: Int] = [:]
        var best: [String: Float] = [:]       // phase -> closest distance to its goal
        var seen: Set<String> = []            // phases it was alive for (with a goal)
        var gaveUp = 0                        // walk targets the pathfinder couldn't reach (Mob.giveUp)
        var gaveUpAt: [String] = []           // the first few of them: target cell and block there
        var stuckWhy: [String: Int] = [:]     // what a stuck window looked like (phase, stroll goal, path state)
        init(_ m: Mob) { mob = m; last = m.pos; lastYaw = m.yaw; startY = m.pos.y }
    }

    static func run() -> Int32 {
        Agent.ensureDeterministicHashing()
        guard let device = MTLCreateSystemDefaultDevice() else { print("behaviorsim: no Metal device"); return 2 }
        PrefsSandbox.begin()
        defer { PrefsSandbox.end() }
        let seeds: [UInt64] = (arg("--seeds") ?? "12345").split(separator: ",").compactMap { UInt64($0) }
        let minutes = Double(arg("--minutes") ?? "") ?? 20
        var md: [String] = ["# Behaviour sim", ""]
        var totals: [String: Int] = [:]
        var goalStats: [String: (Int, Int)] = [:]        // phase -> (met, total)
        let t0 = CFAbsoluteTimeGetCurrent()
        for seed in seeds {
            let probe = World(seed: seed, device: device, save: nil)
            guard let v = probe.gen.structures?.nearest("village", x: 0, z: 0, maxRegions: 8) else { md.append("- seed \(seed): no village"); continue }
            let plaza = V3(Float(v.anchor.x) + 0.5, Float(v.anchor.y), Float(v.anchor.z) + 0.5)
            let (world, game) = Agent.makeWorld(device: device, seed: seed, botSeed: seed, rd: 6, at: plaza)
            let mid = V3(Float(v.min.x + v.max.x) / 2, plaza.y, Float(v.min.z + v.max.z) / 2)
            _ = world.loadSync(center: mid, radius: 6)
            game.survival = false
            game.player.flying = true
            game.player.pos = mid + V3(0, 40, 0)          // out of the way, still within every mob's range
            game.time = 0
            var tracks: [ObjectIdentifier: Track] = [:]
            let dt = 0.05
            let steps = Int(minutes * 60 / dt)
            var sec = 0.0
            for i in 0..<steps {
                game.player.vel = .zero
                game.player.pos = mid + V3(0, 40, 0)
                game.tick(dt)
                sec += dt
                if sec < 1 { continue }
                sec = 0
                let phase = schedulePhase(game.dayFraction)
                for m in game.mobs.mobs where m.health > 0 {
                    let id = ObjectIdentifier(m)
                    let t: Track
                    if let e = tracks[id] { t = e } else { t = Track(m); tracks[id] = t }
                    sample(t, game, world, phase: phase, second: i)
                }
            }
            // Per-seed report.
            var rows: [String] = []
            var counts: [String: Int] = [:]
            for t in tracks.values {
                for (k, n) in t.flags where n > 0 { counts[k, default: 0] += 1 }
                if t.mob.kind == .villager {
                    for ph in t.seen {
                        let b = t.best[ph] ?? 999
                        var s = goalStats[ph] ?? (0, 0)
                        s.1 += 1
                        // Reached: asleep at the bed (2), working at the site (3), at the meeting (villagers mill within 6).
                        let need: Float = ph == "meet" ? 6 : (ph == "work" ? 3 : 2)
                        if b <= need { s.0 += 1 } else { counts["goal_missed_\(ph)", default: 0] += 1 }
                        goalStats[ph] = s
                    }
                }
                let fl = t.flags.filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
                let goals = t.seen.sorted().map { ph -> String in String(format: "%@ %.1f", ph, t.best[ph] ?? 999) }.joined(separator: ", ")
                if !fl.isEmpty || goals.contains("999") || rows.count < 4 {
                    let p = String(format: "%.1f %.1f %.1f", t.mob.pos.x, t.mob.pos.y - Float(YOFF), t.mob.pos.z)
                    let gu0 = t.gaveUp > 0 ? "; gave up \(t.gaveUp)x (\(t.gaveUpAt.joined(separator: "; ")))" : ""
                    let top = t.stuckWhy.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key) \($0.value)" }.joined(separator: ", ")
                    let gu = gu0 + (top.isEmpty ? "" : "; stuck as \(top)")
                    rows.append("- \(t.mob.kind.key) at \(p): \(fl.isEmpty ? "ok" : fl)\(goals.isEmpty ? "" : "; closest to goals: " + goals)\(gu)")
                }
            }
            for (k, n) in counts { totals[k, default: 0] += n }
            let cs = counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
            md.append("## seed \(seed): village at \(v.anchor.x) \(v.anchor.z), \(tracks.count) mobs tracked")
            md.append("- mobs flagged per class: \(cs.isEmpty ? "none" : cs)")
            md += rows.prefix(40)
            md.append("")
            print("behaviorsim seed \(seed): \(tracks.count) mobs; \(cs.isEmpty ? "no flags" : cs)")
        }
        let gs = goalStats.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.0)/\($0.value.1)" }.joined(separator: ", ")
        let ts = totals.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        let summary = String(format: "behaviorsim: %@; villager goals reached: %@ (%.0f s)", ts.isEmpty ? "no flags" : ts, gs.isEmpty ? "-" : gs, CFAbsoluteTimeGetCurrent() - t0)
        md.insert(summary, at: 2)
        try? (md.joined(separator: "\n") + "\n").write(toFile: arg("--out") ?? "snaps/behaviorsim.md", atomically: true, encoding: .utf8)
        print(summary)
        return CommandLine.arguments.contains("--strict") && !totals.isEmpty ? 3 : 0
    }

    // Reference villager schedule (VillageLife.activity): work 2000-9000, meet 9000-11000, rest from 12000.
    static func schedulePhase(_ f: Double) -> String {
        let t = f * 24000
        if t >= 2500 && t < 9000 { return "work" }
        if t >= 9300 && t < 11000 { return "meet" }
        if t >= 12800 && t < 23000 { return "bed" }
        return "free"
    }

    static func sample(_ t: Track, _ g: Game, _ w: World, phase: String, second: Int) {
        let m = t.mob
        let p = m.pos
        // In a wall.
        let lo = V3(p.x - m.halfW + 0.05, p.y + 0.05, p.z - m.halfW + 0.05)
        let hi = V3(p.x + m.halfW - 0.05, p.y + m.height - 0.1, p.z + m.halfW - 0.05)
        if w.collides(lo, hi) { t.wallSeconds += 1; if t.wallSeconds == 2 { t.flags["in_wall", default: 0] += 1 } } else { t.wallSeconds = 0 }
        // Turning and reversals.
        t.yawSum += abs(wrapAngle(m.yaw - t.lastYaw))
        t.lastYaw = m.yaw
        let hv = V3(m.vel.x, 0, m.vel.z)
        if simd_length(hv) > 0.3 && simd_length(t.lastVel) > 0.3 && simd_dot(hv, t.lastVel) < 0 { t.reversals += 1 }
        t.lastVel = hv
        t.window.append(p)
        if t.window.count > 10 { t.window.removeFirst() }
        if t.window.count == 10 {
            let d: Float = simd_length(V2(p.x - t.window[0].x, p.z - t.window[0].z))
            if t.yawSum > 4 * .pi && d < 1.5 {
                t.flags["spinning", default: 0] += 1
                let goal = m.wanderGoal != nil ? "stroll" : (m.faceGoal != nil ? "target" : "heading")
                let mv = m.moving ? "moving" : "standing"
                t.stuckWhy["spin:\(phase)/\(goal)/\(mv)\(m.path.nodes.isEmpty ? "/nopath" : "")", default: 0] += 1
            }
            if t.reversals > 12 { t.flags["jitter", default: 0] += 1 }
            if m.moving && d < 0.5 && !m.sitting {
                var far = true
                if let goal = goalPoint(m, phase), simd_length(goal - p) < 3 { far = false }
                if far {
                    t.flags["stuck", default: 0] += 1
                    // Why: the schedule phase, whether it strolls to a goal or faces a target, the path it follows.
                    let goal = m.wanderGoal != nil ? "stroll" : (m.faceGoal != nil ? "target" : "heading")
                    let path = m.path.nodes.isEmpty ? "nopath" : (m.path.index >= m.path.nodes.count ? "pathend" : "onpath")
                    let why = "\(phase)/\(goal)/\(path)\(m.path.partial ? "/partial" : "")\(m.unreachableTimer > 0 ? "/gaveup" : "")"
                    t.stuckWhy[why, default: 0] += 1
                }
            }
            t.yawSum = 0; t.reversals = 0
            t.window.removeAll(keepingCapacity: true)
        }
        // A fall: landing more than 4.5 blocks below where it last stood (swimmers and fliers don't fall).
        let wet = Blocks.isLiquid(w.block(Int(floor(p.x)), Int(floor(p.y + 0.2)), Int(floor(p.z))))
        if wet || m.spec.flying { t.groundY = nil } else if m.onGround {
            if let g = t.groundY, g - p.y > 4.5 { t.flags["fell", default: 0] += 1 }
            t.groundY = p.y
        }
        if m.kind == .villager, let h = m.home, simd_length(V2(h.x - p.x, h.z - p.z)) > 48 { t.flags["strayed", default: 0] = 1 }
        // Schedule goals (villagers).
        if m.kind == .villager, phase != "free", let goal = goalPoint(m, phase) {
            t.seen.insert(phase)
            let d: Float = simd_length(goal - p)
            t.best[phase] = min(t.best[phase] ?? 999, d)
        }
        // Unreachable walk targets (giveUp sets a 15 s timer; sampled once a second).
        if m.unreachableTimer > 14, let u = m.unreachable {
            t.gaveUp += 1
            if t.gaveUpAt.count < 3 {
                let c = IVec3(Int(floor(u.x)), Int(floor(u.y)), Int(floor(u.z)))
                t.gaveUpAt.append("\(c.x) \(c.y - YOFF) \(c.z) \(Blocks.key(Blocks.groupBase[Int(w.block(c.x, c.y, c.z))]))")
            }
        }
        t.last = p
    }

    static func goalPoint(_ m: Mob, _ phase: String) -> V3? {
        guard let v = m.villager, !m.baby else { return nil }
        switch phase {
        case "work": if let j = v.jobSite { return V3(Float(j[0]) + 0.5, Float(j[1]), Float(j[2]) + 0.5) }
        case "meet": if let b = m.meetPoint { return V3(Float(b.x) + 0.5, Float(b.y), Float(b.z) + 0.5) }
        case "bed": if let b = v.bed { return V3(Float(b[0]) + 0.5, Float(b[1]), Float(b[2]) + 0.5) }
        default: break
        }
        return nil
    }
}
