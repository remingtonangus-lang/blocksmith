import Foundation

// Ledger 39 (Nov 6): a structure start planned on a worker (StructureCache.regionsReady, as the game always plans them)
// could outlive its world. The structure types held their generator unowned, so a plan still running when the world was
// let go (leaving to the title, loading another world) read a freed generator and the game stopped: "Attempted to read an
// unowned reference but object ... was already destroyed" (the perf scenes on build 203, between two scenes).
//   questcheck --planrelease
// Each round makes a world generator, asks for every structure kind's regions round a far spot (each missing one goes to
// a worker), and lets the generator go at once; the workers are then given time to finish. Passing = still running.
enum PlanReleaseCheck {
    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        let off0 = StructureCache.plansOffThread
        StructureCache.plansOffThread = true                     // (as in the game)
        defer { StructureCache.plansOffThread = off0 }
        let plans0 = StructureCache.offThreadPlans
        var asked = 0
        for round in 0..<24 {
            do {
                let gen = WorldGen(seed: 0x51A7_0000 &+ UInt64(round) &* 7919)
                if let sc = gen.structures {
                    let x = 40_000 + round * 3_000, z = -25_000 - round * 2_000
                    for t in sc.types where !sc.regionsReady(t.name, x: x, z: z, maxRegions: 2) { asked += 1 }
                }
            }
            usleep(2_000)                                        // (a little of the planning under way as the next goes)
        }
        // Every plan finishes (or finds its world gone) well inside this.
        var waited = 0, still = 0, last = -1
        while waited < 400 && still < 40 {                      // (until no plan has finished for 2 s, at most 20 s)
            usleep(50_000); waited += 1
            let n = StructureCache.offThreadPlans
            still = n == last ? still + 1 : 0; last = n
        }
        let done = StructureCache.offThreadPlans - plans0
        print("planrelease: 24 worlds let go with \(asked) kinds' regions still planning; \(done) plans finished on the workers in \(String(format: "%.1f", Double(waited) * 0.05)) s")
        let ok = asked > 0
        print((ok ? "ok   " : "FAIL ") + "planrelease: the game still runs after every world was let go mid-plan (\(asked) kinds asked)")
        return ok ? 0 : 1
    }
}
