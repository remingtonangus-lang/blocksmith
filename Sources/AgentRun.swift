import Foundation
import Metal
import simd

// `Blocksmith --agent <bot> [--seeds a,b] [--runs N] [--ticks N] [--botseed K] [--out DIR] [--minimize] [--strict]`
//   bots: monkey (random input), explorer (curiosity walking), village (walk into every building)
// `Blocksmith --agent replay FILE [--verify]` plays a recorded run back with the oracles (--verify: twice, and
//   checks both runs end in the same state).
// Every run with an oracle violation or an unmet goal writes DIR/replay_<bot>_<seed>_<botseed>.jsonl; with
// --minimize the first violation's replay is shrunk (ddmin over the action list, idling chunks out) to the
// fewest non-idle ticks that still trigger the same oracle. A markdown summary goes to DIR/agent_<bot>.md.
enum AgentRun {
    static func run() -> Int32 {
        Agent.ensureDeterministicHashing()
        guard let device = MTLCreateSystemDefaultDevice() else { print("agent: no Metal device"); return 2 }
        PrefsSandbox.begin()
        defer { PrefsSandbox.end() }
        let botName = arg("--agent") ?? "explorer"
        let out = arg("--out") ?? "snaps"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        if botName == "replay" {
            guard let file = CommandLine.arguments.dropFirst().first(where: { $0.hasSuffix(".jsonl") }) else { print("agent replay: no .jsonl file"); return 2 }
            return replay(device: device, file: file, verify: CommandLine.arguments.contains("--verify"))
        }
        let seeds: [UInt64] = (arg("--seeds") ?? "12345").split(separator: ",").compactMap { UInt64($0) }
        let runs = Int(arg("--runs") ?? "") ?? 1
        let ticks = Int(arg("--ticks") ?? "") ?? 3600
        let base = UInt64(arg("--botseed") ?? "") ?? 1
        var md: [String] = ["# Agent runs: \(botName)", "", "Ticks per run \(ticks) (\(ticks / 60) s of game time), walking only.", ""]
        var total = 0, unmet = 0
        var minimized = false
        let t0 = CFAbsoluteTimeGetCurrent()
        for seed in seeds {
            for r in 0..<runs {
                let bs = base &+ UInt64(r)
                guard let (agent, bot, start) = make(device: device, bot: botName, seed: seed, botSeed: bs) else {
                    md.append("- seed \(seed): \(botName) has no start here (e.g. no village nearby)"); continue
                }
                let header = "{\"bot\":\"\(botName)\",\"seed\":\(seed),\"botSeed\":\(bs),\"start\":[\(start.x),\(start.y),\(start.z)],\"ticks\":\(ticks)}"
                let res = agent.run(bot, ticks: ticks, header: header)
                let missed = res.goals.filter { !$0.1 }
                total += res.violations.count
                unmet += missed.count
                let cs = res.counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
                md.append("## seed \(seed), bot seed \(bs)")
                md.append("- oracle counts: \(cs.isEmpty ? "none" : cs); worst tick \(String(format: "%.1f", agent.tickMsWorst)) ms; chunks visited \(agent.visitedChunks.count)")
                for v in res.violations {
                    let p = String(format: "%.1f %.1f %.1f", v.pos.x, v.pos.y - Float(YOFF), v.pos.z)
                    md.append("- **\(v.oracle)** at tick \(v.tick) (\(p)): \(v.detail)")
                }
                for g in res.goals { md.append("- goal \(g.1 ? "met" : "**NOT MET**"): \(g.0) - \(g.2)") }
                print("agent \(botName) seed \(seed)/\(bs): \(res.violations.count) violations, \(missed.count) unmet goals of \(res.goals.count); \(cs)")
                if !res.violations.isEmpty || !missed.isEmpty {
                    let file = "\(out)/replay_\(botName)_\(seed)_\(bs).jsonl"
                    try? (agent.log.joined(separator: "\n") + "\n").write(toFile: file, atomically: true, encoding: .utf8)
                    md.append("- replay: `\(file)`")
                    if CommandLine.arguments.contains("--minimize") && !minimized, let v = res.violations.first {
                        minimized = true
                        let m = minimize(device: device, log: agent.log, oracle: v.oracle, until: v.tick + 60)
                        md.append("- minimised \(v.oracle): \(m.before) -> \(m.after) non-idle ticks; `\(m.file)`")
                    }
                }
                md.append("")
            }
        }
        let summary = String(format: "agent %@: %ld oracle violations, %ld unmet goals over %ld seeds x %ld runs in %.0f s",
                             botName, total, unmet, seeds.count, runs, CFAbsoluteTimeGetCurrent() - t0)
        md.insert(summary, at: 2)
        try? (md.joined(separator: "\n") + "\n").write(toFile: "\(out)/agent_\(botName).md", atomically: true, encoding: .utf8)
        print(summary)
        return CommandLine.arguments.contains("--strict") && (total > 0 || unmet > 0) ? 3 : 0
    }

    // World + bot for a run (the village bot starts at the nearest village's plaza: a disclosed fixture).
    static func make(device: MTLDevice, bot: String, seed: UInt64, botSeed: UInt64, at fixed: V3? = nil) -> (Agent, AgentBot, V3)? {
        var at = fixed
        var village: StructureStart?
        if bot == "village" && at == nil {
            let probe = World(seed: seed, device: device, save: nil)
            guard let s = probe.gen.structures?.nearest("village", x: 0, z: 0, maxRegions: 8) else { return nil }
            village = s
            at = V3(Float(s.anchor.x) + 0.5, Float(s.anchor.y), Float(s.anchor.z) + 0.5)
        }
        let (world, game) = Agent.makeWorld(device: device, seed: seed, botSeed: botSeed, at: at)
        let agent = Agent(game: game, world: world)
        let b: AgentBot
        switch bot {
        case "monkey": b = MonkeyBot(seed: botSeed)
        case "village":
            if village == nil { village = world.gen.structures?.nearest("village", x: Int(game.player.pos.x), z: Int(game.player.pos.z), maxRegions: 8) }
            guard let v = village else { return nil }
            let c = V3(Float(v.min.x + v.max.x) / 2, game.player.pos.y, Float(v.min.z + v.max.z) / 2)
            _ = world.loadSync(center: c, radius: 6)
            b = VillageBot(world: world, village: v)
        default: b = ExplorerBot(seed: botSeed)
        }
        return (agent, b, game.player.pos)
    }

    // MARK: Replay

    static func parse(_ text: String) -> (header: [String: Any], actions: [AgentAction])? {
        let lines = text.split(separator: "\n")
        guard let first = lines.first, let data = String(first).data(using: .utf8),
              let h = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var acts: [AgentAction] = []
        for l in lines.dropFirst() { if let a = AgentAction.decode(l) { acts.append(a) } }
        return (h, acts)
    }

    static func play(device: MTLDevice, header h: [String: Any], actions: [AgentAction]) -> Agent.RunResult? {
        guard let seedN = h["seed"] as? NSNumber, let bsN = h["botSeed"] as? NSNumber, let st = h["start"] as? [NSNumber], st.count == 3 else { return nil }
        let start = V3(st[0].floatValue, st[1].floatValue, st[2].floatValue)
        let (world, game) = Agent.makeWorld(device: device, seed: seedN.uint64Value, botSeed: bsN.uint64Value, at: start)
        game.player.pos = start
        let agent = Agent(game: game, world: world)
        return agent.run(ReplayBot(actions), ticks: actions.count, header: "")
    }

    static func replay(device: MTLDevice, file: String, verify: Bool) -> Int32 {
        guard let text = try? String(contentsOfFile: file, encoding: .utf8), let (h, acts) = parse(text),
              let r1 = play(device: device, header: h, actions: acts) else { print("agent replay: can't read \(file)"); return 2 }
        for v in r1.violations { print("replay \(v.oracle) at tick \(v.tick): \(v.detail)") }
        if verify, let r2 = play(device: device, header: h, actions: acts) {
            let same = r1.hash == r2.hash && r1.violations.map { $0.tick } == r2.violations.map { $0.tick }
            print("replay determinism: \(same ? "same end state" : "DIFFERENT end state (\(r1.hash) vs \(r2.hash))")")
            if !same { return 4 }
        }
        print("replay: \(acts.count) ticks, \(r1.violations.count) violations")
        return 0
    }

    // MARK: Minimise (ddmin over idle-masked chunks of the action list)

    static func minimize(device: MTLDevice, log: [String], oracle: String, until: Int) -> (before: Int, after: Int, file: String) {
        guard let (h, all) = parse(log.joined(separator: "\n")) else { return (0, 0, "") }
        var acts = Array(all.prefix(max(1, until)))
        func fails(_ a: [AgentAction]) -> Bool {
            guard let r = play(device: device, header: h, actions: a) else { return false }
            return r.violations.contains { $0.oracle == oracle }
        }
        let before = acts.filter { $0 != .idle }.count
        guard fails(acts) else { return (before, before, "(did not reproduce: nondeterminism?)") }
        var n = 2
        var tests = 0
        while n <= acts.count && tests < 40 {
            let chunk = max(1, acts.count / n)
            var reduced = false
            var start = 0
            while start < acts.count && tests < 40 {
                var trial = acts
                var changed = false
                for i in start..<min(acts.count, start + chunk) where trial[i] != .idle { trial[i] = .idle; changed = true }
                if changed {
                    tests += 1
                    if fails(trial) { acts = trial; reduced = true }
                }
                start += chunk
            }
            if !reduced { n *= 2 }
        }
        let after = acts.filter { $0 != .idle }.count
        let file = "snaps/replay_min_\(oracle).jsonl"
        var lines = [log.first ?? ""]
        for a in acts { lines.append(a.encode()) }
        try? (lines.joined(separator: "\n") + "\n").write(toFile: file, atomically: true, encoding: .utf8)
        return (before, after, file)
    }
}
