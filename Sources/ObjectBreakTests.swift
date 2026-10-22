import Foundation
import simd

// P389 check (questcheck --view OUT --field --scene objects): the nearest one of each of the ten object kinds
// (WorldObjects.kinds) at the census's three sites, struck as the player strikes it (Game.strikeObject with the right
// tool, the aim at the object): a shot untouched, one converted to its pieces before any blow (it must look the same),
// one after 3 blows and one after it breaks; with what each blow cost the frame thread (the blow, and the finished
// cut swapped in with its debris and drops), what the cut cost the object worker, the collision left after 3 blows, the
// drops, and a save of the 3-blow object read back and rebuilt from its cuts.
enum ObjectBreakTests {
    struct Found { let site: String; let kind: WorldObjects.Kind; let group: WorldObjects.Group }

    // One of each kind: the first site's nearest to its middle (then the next site's).
    static func find(_ w: World) -> [Found] {
        var out: [WorldObjects.Kind: Found] = [:]
        for site in World.objectSites(w) {
            let mid = V3(Float(site.lo.x + site.hi.x) / 2, 0, Float(site.lo.z + site.hi.z) / 2)
            var best: [WorldObjects.Kind: (Float, WorldObjects.Group)] = [:]
            World.scanObjects(w, lo: site.lo, hi: site.hi) { g, k in
                guard WorldObjects.kinds.contains(k), out[k] == nil else { return }
                let d = simd_length(V3(Float(g.lo.x), 0, Float(g.lo.z)) - mid)
                if d < best[k]?.0 ?? .greatestFiniteMagnitude && viewpoint(w, g) != nil { best[k] = (d, g) }
            }
            for (k, v) in best { out[k] = Found(site: site.name, kind: k, group: v.1) }
        }
        return WorldObjects.Kind.allCases.compactMap { out[$0] }
    }

    @inline(__always) static func middle(_ g: WorldObjects.Group) -> V3 {
        (V3(Float(g.lo.x), Float(g.lo.y), Float(g.lo.z)) + V3(Float(g.hi.x), Float(g.hi.y), Float(g.hi.z)) + 1) * 0.5
    }

    // An eye with a clear line to the object's middle, about 2.5 blocks off it (farther for a tall one; nearer, higher
    // or lower when that is blocked: a chest indoors, a log in the grass), and its yaw and pitch looking at the middle.
    static func viewpoint(_ w: World, _ g: WorldObjects.Group) -> (V3, Float, Float)? {
        let c = middle(g)
        let s = g.size
        let base = 2.0 + Float(max(s.x, s.z)) * 0.5 + Float(s.y) * 0.45
        let set = Set(g.cells)
        // (of the places with a clear line to the middle, the one that sees the most of its cells)
        var best: (V3, Float, Float)?, bestSeen = -1
        for (dist, up) in [(base, 0.4), (base, 1.2), (base - 0.8, 0.6), (base + 1, 0.9), (base - 0.8, 1.4), (base, -0.3)] as [(Float, Float)] {
            for k in 0..<16 {
                let a = Float(k) * .pi / 8 + .pi / 16
                let eye = c + V3(cosf(a) * dist, up, sinf(a) * dist)
                let ex = Int(floor(eye.x)), ey = Int(floor(eye.y)), ez = Int(floor(eye.z))
                guard w.isAir(ex, ey, ez), w.isAir(ex, ey - 1, ez) else { continue }
                let d = simd_normalize(c - eye)
                guard let h = w.raycast(eye, d, maxDist: dist + 2), set.contains(h.hit) else { continue }
                var seen = 0
                for q in g.cells.prefix(16) {
                    let t = V3(Float(q.x), Float(q.y), Float(q.z)) + 0.5
                    if let hq = w.raycast(eye, simd_normalize(t - eye), maxDist: simd_length(t - eye) + 1), hq.hit == q { seen += 1 }
                }
                if seen > bestSeen { bestSeen = seen; best = (eye, atan2f(-d.x, -d.z), asinf(d.y)) }
                if seen == min(g.cells.count, 16) { return best }
            }
        }
        return best
    }

    // Aims the player from `eye` at `at` and strikes once (true: the blow was taken by an object).
    static func strike(_ g: Game, eye: V3, at: V3) -> Bool {
        let d = simd_normalize(at - eye)
        g.player.flying = true
        g.player.pos = eye - V3(0, g.player.eyeHeight, 0)
        g.player.yaw = atan2f(-d.x, -d.z); g.player.pitch = asinf(d.y)
        g.target = g.world.raycast(g.player.eye, g.player.look, maxDist: 6)
        return g.strikeObject(breakNow: true, breakHeld: true, dt: 0)
    }

    // The worker's cuts in, swapped in on the frame thread, the sections remeshed now (the harness can't wait for the
    // mesh workers), and the debris flown for `fly` seconds.
    static func settle(_ g: Game, _ grp: WorldObjects.Group, fly: Float) {
        g.world.objectReg.waitIdle()
        g.objectsTick()
        while !g.world.objectReg.later.isEmpty { g.objectsTick() }     // (P394: the frames after the swap-in)
        g.world.remeshArea(x0: grp.lo.x - 1, z0: grp.lo.z - 1, x1: grp.hi.x + 1, z1: grp.hi.z + 1, y0: grp.lo.y - 1, y1: grp.hi.y + 1)
        var t: Float = 0
        while t < fly { g.debris.tick(1.0 / 72, world: g.world); t += 1.0 / 72 }
    }

    static func tool(for b: BlockID) -> String {
        switch ToolType(rawValue: Blocks.tool[Int(b)]) ?? .none {
        case .pickaxe: return "iron_pickaxe"
        case .shovel: return "iron_shovel"
        case .hoe: return "iron_hoe"
        default: return "iron_axe"
        }
    }

    static func items(_ g: Game) -> Int {
        var n = 0
        for (i, s) in g.inventory.main.slots.enumerated() where i != g.inventory.selected && !s.isEmpty { n += s.count }
        return n
    }

    static func stat(_ a: [Double]) -> String {
        guard !a.isEmpty else { return "-" }
        return String(format: "mean %.3f, worst %.3f ms (%d)", a.reduce(0, +) / Double(a.count), a.max()!, a.count)
    }

    static func run(_ g: Game, base: String, shoot: (String, V3, Float, Float) -> Void) -> String {
        let w = g.world
        g.survival = true
        var lines = ["objects (P389): the ten kinds struck where they stand (\(w.objectsOn ? "objects on" : "OBJECTS OFF: this world draws no detail stream"))"]
        // BS_OBJCENSUS=1: the ten kinds taken from this run's census (the most groups at the three sites) instead of
        // WorldObjects.kinds (to check the list it holds).
        if ProcessInfo.processInfo.environment["BS_OBJCENSUS"] == "1" {
            var n: [WorldObjects.Kind: Int] = [:]
            for site in World.objectSites(w) {
                World.scanObjects(w, lo: site.lo, hi: site.hi) { _, k in
                    if k != .other && k != .building && k != .tree && k != .none { n[k, default: 0] += 1 }
                }
            }
            let top = n.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }.prefix(10)
            lines.append("  census top 10: " + top.map { "\($0.key.name) \($0.value)" }.joined(separator: ", ")
                         + (Set(top.map { $0.key }) == WorldObjects.kinds ? " (= WorldObjects.kinds)" : " (WorldObjects.kinds differs: using the census's)"))
            WorldObjects.kinds = Set(top.map { $0.key })
        }
        let found = find(w)
        lines.append("  found \(found.count) of \(WorldObjects.kinds.count) kinds: " + found.map { $0.kind.name }.joined(separator: ", "))
        // The session's first block break builds caches every break reads (towns, vaults, mines round it): timed apart on a
        // plank set in the air over the first object, so the objects' numbers are their own.
        if let f0 = found.first {
            let m = middle(f0.group)
            let p = IVec3(Int(floor(m.x)), f0.group.hi.y + 4, Int(floor(m.z)))
            if w.isAir(p.x, p.y, p.z), Blocks.has("oak_planks") {
                let pl = Blocks.id("oak_planks")
                w.setBlockAsync(p.x, p.y, p.z, pl)
                let t0 = DispatchTime.now().uptimeNanoseconds
                g.breakBlock(p, pl, drop: false, quiet: true)
                lines.append(String(format: "  the session's first block break (a plank, no object; caches every break reads): %.3f ms", Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6))
            }
        }
        var allStrike: [Double] = [], allInstall: [Double] = [], allWork: [Double] = [], allLater: [Double] = []
        var savedOnce = false
        for f in found {
            let grp = f.group
            _ = w.loadSync(center: middle(grp), radius: 3)
            guard let (eye, yaw, pitch) = viewpoint(w, grp) else { lines.append("  \(f.kind.name): no clear view"); continue }
            let name = f.kind.name.replacingOccurrences(of: " ", with: "_")
            g.inventory.main.slots = Array(repeating: .empty, count: 36)
            g.inventory.selected = 0
            g.inventory.held = ItemStack(Items.id(tool(for: grp.blocks[0])), 1)
            g.objectStats = WorldObjects.Stats()
            let mid = middle(grp)
            shoot("\(base)-\(name)-1-untouched.png", eye, yaw, pitch)
            // Converted to its pieces with no blow yet, every cell drawn by the object (in play an untouched cell stays
            // the block mesher's): the pieces must look as the cells did.
            let reg = w.objectReg
            let o = reg.register(w, grp, kind: f.kind)
            o.buildWhole(WorldObjects.Registry.mainWS)
            WorldObjects.Registry.drawAll = true
            reg.install(w, o, WorldObjects.Result(id: o.id, frags: o.wholeFrags,
                                                  removed: [], fallen: [], applied: 0, replay: false, workMs: 0))
            w.remeshArea(x0: grp.lo.x - 1, z0: grp.lo.z - 1, x1: grp.hi.x + 1, z1: grp.hi.z + 1, y0: grp.lo.y - 1, y1: grp.hi.y + 1)
            shoot("\(base)-\(name)-2-converted.png", eye, yaw, pitch)
            WorldObjects.Registry.drawAll = false
            reg.refresh(w, o)
            // Three blows round the middle (the aim nudged a little each time), then the shot.
            let before = items(g)
            var hits = 0
            var first: [String] = []
            for k in 0..<3 {
                let aim = mid + V3(0, Float(k - 1) * 0.18, 0)
                if strike(g, eye: eye, at: aim) { hits += 1 }
                settle(g, grp, fly: 0)
                first.append(o.broken ? "broken" : String(format: "%.0f%%/%d", 100 * o.volumes(o.frags).reduce(0, +) / max(o.totalVolume, 1e-6), o.frags.count))
            }
            settle(g, grp, fly: 0.2)
            shoot("\(base)-\(name)-3-three-hits.png", eye, yaw, pitch)
            let left3 = o.broken ? 0 : o.volumes(o.frags).reduce(0, +)
            var boxes: [(V3, V3)] = []
            for c in grp.cells { w.collisionBoxes(c.x, c.y, c.z, &boxes) }
            let collLine = o.broken ? "broken already" : "\(boxes.count) boxes over its \(grp.cells.count) cells"
            // Save after 3 blows: written, read back, rebuilt from its cuts on a worker; the same pieces?
            var saveLine = ""
            if !o.broken && !savedOnce {
                savedOnce = true
                let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("objects-\(ProcessInfo.processInfo.processIdentifier).json")
                SaveIO.storeJSON(reg.saved(), to: url)
                SaveIO.flush()
                if let d = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([WorldObjects.Saved].self, from: d) {
                    let r2 = WorldObjects.Registry()
                    r2.load(w, list)
                    r2.startLoaded(w)
                    r2.waitIdle()
                    let res = r2.poll().first { $0.id == o.id }
                    let v1 = o.volumes(o.frags).reduce(0, +), v2 = res.map { o.volumes($0.frags).reduce(0, +) } ?? -1
                    let same = res != nil && res!.frags.count == o.frags.count && abs(v1 - v2) < 1e-4
                    saveLine = String(format: "; save: %@ (%d objects in the file, %d cuts; %d pieces, volume %.4f -> read back %d pieces, %.4f)",
                                      same ? "OK" : "FAIL", list.count, o.cuts.count, o.frags.count, v1, res?.frags.count ?? -1, v2)
                } else { saveLine = "; save: FAIL (not read back)" }
                try? FileManager.default.removeItem(at: url)
            }
            // On until it breaks (the aim at its largest piece left), then the shot.
            var more = 0, missed = 0
            var standAt = eye
            var trail: [String] = []
            while !o.broken && more < 60 {
                // (the largest piece the eye can reach: one behind a counter or in a crater is passed over)
                var target = mid
                let set = Set(grp.cells)
                for f in o.frags.sorted(by: { $0.poly.mass.volume > $1.poly.mass.volume }).prefix(12) {
                    let t = o.originV + f.poly.center + V3(0, w.objectSeat(o.blocks[o.parts[f.part].cell], o.cells[o.parts[f.part].cell]), 0)
                    if let h = w.raycast(standAt, simd_normalize(t - standAt), maxDist: 6), set.contains(h.hit) { target = t; break }
                }
                more += 1
                if !strike(g, eye: standAt, at: target) {
                    missed += 1
                    if reg.objects[o.id] == nil { break }
                    // (nothing left in sight from here: a new place to stand, looking at what is left)
                    if let f = o.frags.max(by: { $0.poly.mass.volume < $1.poly.mass.volume }) {
                        var sub = grp
                        let c = o.cells[o.parts[f.part].cell]
                        sub.cells = [c]; sub.lo = c; sub.hi = c
                        if let v = viewpoint(w, sub) { standAt = v.0 }
                    }
                }
                settle(g, grp, fly: 0)
                if more % 5 == 0 && !o.broken {
                    trail.append(String(format: "%d:%.0f%%/%d", more, 100 * o.volumes(o.frags).reduce(0, +) / max(o.totalVolume, 1e-6), o.frags.count))
                }
            }
            let trailLine = "    blows 1-3 (left/pieces): " + first.joined(separator: " ") + "; after 3 (blow: left/pieces): " + trail.joined(separator: " ") + (missed > 0 ? "; \(missed) missed" : "")
            settle(g, grp, fly: 0.5)
            shoot("\(base)-\(name)-4-broken.png", eye, yaw, pitch)
            let cellsLeft = grp.cells.filter { w.builtBlock($0.x, $0.y, $0.z) != AIR }.count
            let st = g.objectStats
            allStrike += st.strikeMs; allInstall += st.installMs; allWork += st.workMs; allLater += st.laterMs
            lines.append(String(format: "  %@ at %d %d %d (%@): %d cells, %d parts; 3 blows took %d (%.0f%% left), broke after %d more (%@): %d cells left; drops %d items; debris %d chunks, %d falls; collision after 3: %@%@",
                                f.kind.name, grp.lo.x, grp.lo.y, grp.lo.z, f.site, grp.cells.count, o.parts.count, hits,
                                100 * left3 / max(o.totalVolume, 1e-6), more, o.broken ? "broken" : "NOT BROKEN", cellsLeft,
                                items(g) - before, st.debris, st.falls, collLine, saveLine))
            lines.append("    frame thread per blow: " + stat(st.strikeMs) + "; cut swapped in: " + stat(st.installMs) + "; worker: " + stat(st.workMs))
            lines.append(trailLine)
            if !st.phase.isEmpty {
                lines.append("    swap-in worst by part: " + st.phase.keys.sorted().map { String(format: "%@ %.3f", $0, st.phase[$0]!) }.joined(separator: ", ") + " ms")
            }
        }
        lines.append("  all: frame thread per blow " + stat(allStrike) + "; cut swapped in " + stat(allInstall) + "; worker " + stat(allWork))
        lines.append("  later frames (one cell or drop each, P394): " + stat(allLater))
        let worst = (allStrike.max() ?? 0) + (allInstall.max() ?? 0)
        lines.append(String(format: "  per hit on the frame thread (worst blow + worst swap-in): %.3f ms: %@", worst, worst < 1 ? "OK (under 1 ms)" : "OVER 1 ms"))
        return lines.joined(separator: "\n")
    }
}
