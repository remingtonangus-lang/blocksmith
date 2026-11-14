import Foundation
import simd

// questcheck --builds (Remington, Nov 14: "pretty builds that ai agents placed block by block themselves to prove that
// it's easy, ... on varieties of natural terrain that is currently vulnerable to the procedural reshaping"): in a
// Polygons world at the Builders' Grounds seed, BuilderBot builds each blueprint on its own kind of ground with the
// player's controls only. Then the world runs on (load checks, the ground's weighing and reshaping) and every block the
// agent put down, and every cell it dug, is read back; the ground round each build is compared with how it was.
// BS_BUILDONLY=key,key limits it to some builds.
enum BuildersCheck {
    static let maxTicks = Int(ProcessInfo.processInfo.environment["BS_BUILDTICKS"] ?? "") ?? 240_000
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
        // A block placed over a drop (a lintel, a deck, an eave) grows no ground under it; one on the ground still meets it.
        do {
            let x = Int(floor(spawn.x)) + 3, z = Int(floor(spawn.z)) + 3
            let gy = BuildersGrounds.groundY(w, x, z)
            func census() -> Int {
                var n = 0
                for y in (gy - 1)...(gy + 8) { for dz in -3...3 { for dx in -3...3 where w.groundAt(x + dx, y, z + dz) { n += 1 } } }
                return n
            }
            let n0 = census()
            let brick = Blocks.id("stone_bricks")
            w.setBlock(x, gy + 6, z, brick)
            let grew = w.meetGround(x, gy + 6, z, brick)
            let n1 = census()
            w.setBlock(x, gy + 6, z, AIR)
            check(grew == 0 && n1 == n0, "builds: a stone brick 5 over the ground grows none under it (\(grew) cells filled, \(n1 - n0) ground cells more; BS_OLDMEET=1 filled them)")
        }
        let only = ProcessInfo.processInfo.environment["BS_BUILDONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        let bps = BuildersGrounds.blueprints().filter { only?.contains($0.key) ?? true }
        print("builds: finding the sites round \(Int(spawn.x)) \(Int(spawn.z))"); fflush(stdout)
        let t0 = CFAbsoluteTimeGetCurrent()
        let sites = BuildersGrounds.findSites(w, centre: spawn, kinds: bps.map { $0.ground })
        print(String(format: "builds: spawn %.0f %.0f, sites found in %.1f s:", spawn.x, spawn.z, CFAbsoluteTimeGetCurrent() - t0))
        fflush(stdout)
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
            // Ground that comes up in the build's own cells while it goes up (the reshaping), as it happens.
            var groundWas: [IVec3: Bool] = [:]
            for j in plan.jobs { groundWas[j.cell] = w.groundAt(j.cell.x, j.cell.y, j.cell.z) }
            var risen = 0
            // (the columns over the build as they were, to tell where risen ground came from)
            func column(_ x: Int, _ z: Int) -> String {
                (plan.lo.y - 2...plan.hi.y + 16).map { w.groundAt(x, $0, z) ? "#" : (w.block(x, $0, z) == AIR ? "." : "b") }.joined()
            }
            var columns0: [IVec3: String] = [:]
            for x in plan.lo.x...plan.hi.x { for z in plan.lo.z...plan.hi.z { columns0[IVec3(x, 0, z)] = column(x, z) } }
            while !bot.done && ticks < BuildersCheck.maxTicks {
                agent.step(bot); ticks += 1
                if ticks % 20 == 0 {
                    for (q, was) in groundWas {
                        let now = w.groundAt(q.x, q.y, q.z)
                        if now && !was {
                            risen += 1
                            if risen <= 6 {
                                let jb = bot.i < bot.jobs.count ? bot.jobs[bot.i] : nil
                                if risen <= 2 {
                                    print("builds:     column then \(columns0[IVec3(q.x, 0, q.z)] ?? "?") (from y \(plan.lo.y - 2 - YOFF))")
                                    print("builds:     column now  \(column(q.x, q.z))")
                                }
                                print("builds:   ground came up at \(q.x) \(q.y - YOFF) \(q.z) by tick \(ticks) (job \(bot.i): \(jb.map { ($0.want == AIR ? "dig" : Blocks.key($0.want)) + " at \($0.cell.x) \($0.cell.y - YOFF) \($0.cell.z)" } ?? "-"))")
                            }
                        }
                        groundWas[q] = now
                    }
                }
                if ticks % 6000 == 0 { print("builds:   \(bp.key) tick \(ticks): job \(bot.i)/\(bot.jobs.count), \(bot.placed) placed, \(bot.dug) dug, \(bot.missed.count) missed"); fflush(stdout) }
            }
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
            if risen > 0 { print("builds:   ground came up in \(risen) of the build's cells while it went up") }
            for m in bot.missed.prefix(BuilderBot.trace ? 2000 : 8) { print("   missed: \(m)") }
            for m in wrong.prefix(8) { print("   wrong: \(m)") }
            fflush(stdout)
            check(bot.done && bot.missed.isEmpty, "builds: the agent builds the \(bp.key) on \(bp.ground) through the controls (\(bot.placed) placed, \(bot.dug) dug, \(bot.missed.count) missed)")
            check(wrong.isEmpty && fell == 0, "builds: the \(bp.key) stands whole 20 s later (\(wrong.count) cells wrong, \(fell) fell)")
            check(lost + gained <= 12, "builds: the ground round the \(bp.key) is left as it was (\(lost) cells lost, \(gained) gained; want at most 12)")
        }
    }
}
