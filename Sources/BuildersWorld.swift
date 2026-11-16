import Foundation
import simd

// The Builders' Grounds world (Worlds menu): a creative Polygons world where the six builds go up the first time it
// loads, each on its own kind of natural ground, a few blocks a tick in the builder agent's own job order (the cells dug
// first with the same hole a creative break leaves, then the blocks bottom up). questcheck --builds is where BuilderBot
// does the same jobs through the player's controls, every block checked. Each build gets a sign and a mark on the map.
// The sites are kept in the save (builders-sites.txt) so a world left half built finishes on the same ground.
extension BuildersGrounds {
    final class Run {
        var plans: [Placement]
        var p = 0, j = 0
        var announced = -1
        init(_ plans: [Placement]) { self.plans = plans }
        var done: Bool { p >= plans.count }
    }

    static let builtMarker = "builders-built.txt", sitesFile = "builders-sites.txt"

    // A job as the world does it: a dig breaks the cell and leaves a creative break's hole in natural ground; a block is
    // set (a door with its upper half).
    static func apply(_ g: Game, _ job: Job) {
        let w = g.world, c = job.cell
        if holds(w, job) { return }
        if job.want == AIR {
            let b = w.block(c.x, c.y, c.z)
            g.breakBlock(c, b, drop: false, quiet: true)
            if SmoothTerrain.natural[Int(b)] {
                _ = w.carve(at: V3(Float(c.x) + 0.5, Float(c.y) + 0.5, Float(c.z) + 0.5), radius: Game.digRadius(b), mode: .shape, remesh: true)
            }
            return
        }
        w.setBlock(c.x, c.y, c.z, job.want)
        if Blocks.shape[Int(job.want)] == "door" { w.setBlock(c.x, c.y + 1, c.z, job.want + 8) }
        else { w.meetGround(c.x, c.y, c.z, job.want) }                 // (as a placed block does: Game.useItem)
    }

    // Ledger 202: the trees round the six and where he starts, so he sees them from there (his Nov 15 pictures: a wood;
    // the first place the search finds with all six is often in one). Trunks and leaves only, from the ground up, each
    // column within `radius` of the middle. Returns the cells cleared.
    static func clearTrees(_ w: World, middle m: V3, radius: Float) -> Int {
        var n = 0
        let r = Int(radius.rounded(.up))
        for dz in -r...r { for dx in -r...r where Float(dx * dx + dz * dz) <= radius * radius {
            let x = Int(floorf(m.x)) + dx, z = Int(floorf(m.z)) + dz
            guard w.isLoaded(x, z) else { continue }
            let g = groundY(w, x, z)
            for y in (g + 1)...(g + 40) {
                let b = w.block(x, y, z)
                guard b != AIR else { continue }
                let k = ShapeClass.kind[Int(b)]
                if k == .trunk || k == .foliage { _ = w.setBlockAsync(x, y, z, AIR); n += 1 }
            }
        } }
        return n
    }

    // A sign by a build, on the ground two out from its south side.
    static func sign(_ g: Game, _ pl: Placement) {
        let w = g.world
        let x = (pl.lo.x + pl.hi.x) / 2, z = pl.hi.z + 3
        let y = groundY(w, x, z) + 1
        guard !Blocks.isLiquid(w.block(x, y, z)) else { return }
        ProvingGrounds.sign(w, IVec3(x, y, z), facingSouth: true, [pl.bp.title[0], pl.bp.title.count > 1 ? pl.bp.title[1] : "", "built block by", "block by an agent"])
    }
}

extension Game {
    func buildersTick() {
        if let r = buildersRun {
            if !r.done {
                let pl = r.plans[r.p]
                if r.announced != r.p {
                    r.announced = r.p
                    _ = world.loadSync(center: V3(Float(pl.origin.x), Float(pl.origin.y), Float(pl.origin.z)), radius: 1)
                    onToast?("Builders' Grounds: the \(pl.bp.title[0]) going up (\(r.p + 1) of \(r.plans.count))")
                }
                // (6 jobs a tick: he watches them go up)
                var n = 0
                while r.j < pl.jobs.count && n < 6 { BuildersGrounds.apply(self, pl.jobs[r.j]); r.j += 1; n += 1 }
                if r.j >= pl.jobs.count {
                    BuildersGrounds.sign(self, pl)
                    MapCache.shared.discover(self, kind: "agent_build", x: pl.origin.x, z: pl.origin.z, name: pl.bp.title[0], silent: true)
                    r.p += 1; r.j = 0
                }
            }
            if r.done {
                buildersRun = nil
                if let dir = save?.dir { try? "the six agent builds are up\n".write(to: dir.appendingPathComponent(BuildersGrounds.builtMarker), atomically: true, encoding: .utf8) }
                onToast?("Builders' Grounds: all six built")
            }
            return
        }
        guard !buildersChecked else { return }
        guard let dir = save?.dir, dir.lastPathComponent == BuildersGrounds.worldName else { buildersChecked = true; return }
        guard dim.dim == .overworld else { return }
        buildersChecked = true
        let bps = BuildersGrounds.blueprints()
        // The sites: kept from the first load, else found round the spawn. (Ledger 202: the six together, kept with
        // where he starts, a "cluster" line; a save from before, its six spread out, has them built again together.)
        var sites: [String: IVec3] = [:]
        var start: (V3, Float)?
        let sf = dir.appendingPathComponent(BuildersGrounds.sitesFile)
        if let s = try? String(contentsOf: sf, encoding: .utf8) {
            for line in s.split(separator: "\n") {
                let f = line.split(separator: " ")
                if f.count == 3, let x = Int(f[1]), let z = Int(f[2]) { sites[String(f[0])] = IVec3(x, 0, z) }
                if f.count == 5, f[0] == "cluster", let x = Float(f[1]), let y = Float(f[2]), let z = Float(f[3]), let a = Float(f[4]) { start = (V3(x, y, z), a) }
            }
            if !BuildersGrounds.oldSites && start == nil { sites = [:] }
        }
        if save?.hasMarker(BuildersGrounds.builtMarker) == true && !sites.isEmpty { return }
        if sites.isEmpty {
            onToast?("Builders' Grounds: finding the ground")
            if !BuildersGrounds.oldSites, let c = BuildersGrounds.findCluster(world, centre: findSpawn(), kinds: bps.map { $0.ground }) {
                sites = c.sites
                start = (c.spawn, c.yaw)
            } else {
                sites = BuildersGrounds.findSites(world, centre: findSpawn(), kinds: bps.map { $0.ground })
            }
            var text = sites.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.x) \($0.value.z)" }.joined(separator: "\n") + "\n"
            if case let (p, a)? = start { text += "cluster \(p.x) \(p.y) \(p.z) \(a)\n" }
            try? text.write(to: sf, atomically: true, encoding: .utf8)
        }
        var plans: [BuildersGrounds.Placement] = []
        for bp in bps {
            guard let s = sites[bp.ground] else { continue }
            _ = world.loadSync(center: V3(Float(s.x), 120, Float(s.z)), radius: 1)
            plans.append(BuildersGrounds.place(bp, on: world, at: s))
        }
        guard let first = plans.first else { return }
        if case let (p, _)? = start {
            // (ledger 202: no wood between him and the six)
            let mids = plans.map { V3(Float($0.lo.x + $0.hi.x) / 2, 0, Float($0.lo.z + $0.hi.z) / 2) }
            let m = mids.reduce(V3.zero, +) / Float(mids.count)
            let reach = (mids.map { simd_length(V2($0.x - m.x, $0.z - m.z)) } + [simd_length(V2(p.x - m.x, p.z - m.z))]).max() ?? 30
            _ = world.loadSync(center: V3(m.x, 100, m.z), radius: Int(reach / Float(CS)) + 2)
            _ = BuildersGrounds.clearTrees(world, middle: m, radius: reach + 10)
        }
        buildersRun = BuildersGrounds.Run(plans)
        // He starts by the first build, flying, looking north at it. (Ledger 202: where all six are in front of him, 12
        // from their middle, a little over the ground, looking down at them; the world's spawn there too.)
        if case let (p, a)? = start {
            let floors = plans.map { Float($0.origin.y) }.sorted()
            let mid = floors[floors.count / 2]
            let y = max(p.y + 2, mid + 10)
            player.pos = V3(p.x, y, p.z)
            player.vel = .zero
            player.flying = true
            player.yaw = a
            let cm = plans.map { V2(Float($0.lo.x + $0.hi.x) / 2, Float($0.lo.z + $0.hi.z) / 2) }.reduce(V2.zero, +) / Float(plans.count)
            player.pitch = -atan2f(y - mid - 3, max(6, simd_length(cm - V2(p.x, p.z))))
            spawnPoint = V3(p.x, p.y, p.z)
            return
        }
        player.pos = V3(Float(first.origin.x) + 4.5, Float(max(first.hi.y, world.topY(first.origin.x + 4, first.hi.z + 12)) + 3), Float(first.hi.z) + 12.5)
        player.vel = .zero
        player.flying = true
        player.yaw = 0; player.pitch = -0.25
    }
}
