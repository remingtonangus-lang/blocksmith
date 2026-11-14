import Foundation
import simd

// questcheck --builds (Remington, Nov 14: "pretty builds that ai agents placed block by block themselves to prove that
// it's easy, ... on varieties of natural terrain that is currently vulnerable to the procedural reshaping"): in a
// Polygons world at the Builders' Grounds seed, BuilderBot builds each blueprint on its own kind of ground with the
// player's controls only. Then the world runs on (load checks, the ground's weighing and reshaping) and every block the
// agent put down, and every cell it dug, is read back; the ground round each build is compared with how it was.
// BS_BUILDONLY=key,key limits it to some builds.
enum BuildersCheck {
    static func run(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let w = World(seed: BuildersGrounds.seed, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 4; w.activeDistance = 4
        let g = Game(world: w, save: nil, persistent: false)
        g.paused = false; g.survival = false
        let spawn = g.spawnPoint
        g.player.pos = spawn
        _ = w.loadSync(center: spawn, radius: 2)
        let only = ProcessInfo.processInfo.environment["BS_BUILDONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        let bps = BuildersGrounds.blueprints().filter { only?.contains($0.key) ?? true }
        let t0 = CFAbsoluteTimeGetCurrent()
        let sites = BuildersGrounds.findSites(w, centre: spawn, kinds: bps.map { $0.ground })
        print(String(format: "builds: spawn %.0f %.0f, sites found in %.1f s:", spawn.x, spawn.z, CFAbsoluteTimeGetCurrent() - t0))
        for bp in bps { print("  \(bp.key) on \(bp.ground): \(sites[bp.ground].map { "\($0.x) \($0.z)" } ?? "NONE")") }
        check(bps.allSatisfy { sites[$0.ground] != nil }, "builds: a site for every kind of ground (\(sites.count)/\(Set(bps.map { $0.ground }).count))")
        for bp in bps {
            guard let site = sites[bp.ground] else { continue }
            _ = w.loadSync(center: V3(Float(site.x), 120, Float(site.z)), radius: 2)
            let plan = BuildersGrounds.place(bp, on: w, at: site)
            // The ground round the build (6 out, the build's own cells and 1 round them left out) as it was.
            let r0 = IVec3(plan.lo.x - 7, plan.lo.y - 14, plan.lo.z - 7), r1 = IVec3(plan.hi.x + 7, plan.hi.y + 2, plan.hi.z + 7)
            func inRing(_ x: Int, _ z: Int) -> Bool { x < plan.lo.x - 1 || x > plan.hi.x + 1 || z < plan.lo.z - 1 || z > plan.hi.z + 1 }
            var before: [IVec3: Bool] = [:]
            for y in r0.y...r1.y { for z in r0.z...r1.z { for x in r0.x...r1.x where inRing(x, z) { before[IVec3(x, y, z)] = w.groundAt(x, y, z) } } }
            let digs = plan.jobs.filter { $0.want == AIR }.count
            print("builds: \(bp.key) floor y \(plan.origin.y - YOFF), \(digs) to dig, \(plan.jobs.count - digs) to place")
            // The agent starts off to the south, a little over the ground.
            let start = V3(Float(site.x) + 4.5, Float(max(plan.hi.y, w.topY(site.x + 4, site.z + 16)) + 2), Float(site.z) + 16.5)
            g.player.pos = start; g.player.vel = .zero; g.player.flying = true
            g.player.yaw = 0; g.player.pitch = 0
            let agent = Agent(game: g, world: w)
            let bot = BuilderBot(plan, world: w)
            let fell0 = Structure.fellTotal
            let tb = CFAbsoluteTimeGetCurrent()
            var ticks = 0
            while !bot.done && ticks < 240_000 { agent.step(bot); ticks += 1 }
            let buildS = CFAbsoluteTimeGetCurrent() - tb
            // The world runs on for 20 s with the agent standing by.
            for _ in 0..<1200 { agent.step(bot) }
            var wrong: [String] = []
            for j in plan.jobs where !BuildersGrounds.holds(w, j) {
                let b = w.block(j.cell.x, j.cell.y, j.cell.z)
                wrong.append("\(j.want == AIR ? "dug" : Blocks.key(j.want)) at \(j.cell.x) \(j.cell.y - YOFF) \(j.cell.z) is \(Blocks.key(b))")
            }
            var lost = 0, gained = 0
            for (q, was) in before {
                let now = w.groundAt(q.x, q.y, q.z)
                if was && !now { lost += 1 } else if !was && now { gained += 1 }
            }
            let fell = Structure.fellTotal - fell0
            print(String(format: "builds: %@ built in %d ticks (%.1f s), %d placed, %d dug, %d presses, %d redone, %d missed; after 20 s %d cells wrong, %d fell; ground round it %d lost, %d gained",
                         bp.key, ticks, buildS, bot.placed, bot.dug, bot.presses, bot.redone, bot.missed.count, wrong.count, fell, lost, gained))
            for m in bot.missed.prefix(8) { print("   missed: \(m)") }
            for m in wrong.prefix(8) { print("   wrong: \(m)") }
            check(bot.done && bot.missed.isEmpty, "builds: the agent builds the \(bp.key) on \(bp.ground) through the controls (\(bot.placed) placed, \(bot.dug) dug, \(bot.missed.count) missed)")
            check(wrong.isEmpty && fell == 0, "builds: the \(bp.key) stands whole 20 s later (\(wrong.count) cells wrong, \(fell) fell)")
            check(lost + gained <= 12, "builds: the ground round the \(bp.key) is left as it was (\(lost) cells lost, \(gained) gained; want at most 12)")
        }
    }
}
