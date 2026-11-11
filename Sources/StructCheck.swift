import Foundation
import Metal
import simd

// Structure walkability checker (--structcheck): generates real instances of every structure type in every
// dimension (several seeds, several instances each) and checks them the way a player or a villager would
// meet them, so whole classes of layout bugs show up at once instead of one house at a time:
//   door_blocked      a side of a door has no room to stand (wall, terrain, missing floor)
//   door_step         walking through a door needs a jump (the floor on one side is a block higher)
//   door_no_floor     nothing to stand on in the doorway itself
//   door_unreachable  no walking route reaches either side of the door from outside / the structure's start
//   door_needs_jump   (villages) a door is only reachable with 1-block jumps (villagers path poorly over those)
//   door_half         a door's upper half is missing (overwritten by a later write)
//   poi_unreachable   a bed, job site, chest, bell... has no reachable cell next to it
//   mob_in_block      a structure mob spawns inside a solid block
//   mob_no_floor      a walking structure mob spawns with nothing under it
//   mob_trapped       a villager spawns where no route leads out to the village
//   bed_broken        a bed half without its other half
//   floating          structure columns (walls, foundations) hanging over air
//   torch_unsupported a standing torch with nothing under it, or a wall torch with nothing behind it
//   ladder_unsupported a ladder with nothing behind it
// Walk model: a two-block-tall body; steps up to 0.6 are walking, up to 1.25 need a jump, drops up to 3;
// doors and gates count as open, ladders and vines climb. Prints a summary per kind, writes a report
// (--out FILE, markdown) with every issue's position and a snapshot command to look at it.
enum StructCheck {
    struct Issue {
        let cls: String; let kind: String; let seed: UInt64; let pos: IVec3; let detail: String
        var view = ""                 // snapshot args looking from the walk's closest cell toward the issue
    }

    // Underwater / buried kinds: no walking checks (they are reached by swimming or digging).
    static let noWalk: Set<String> = ["monument", "ocean_ruin", "shipwreck", "buried_treasure", "fossil", "trail_ruins"]
    // Kinds entered from their own start piece (underground or enclosed) rather than from the open surface.
    static let fromInside: Set<String> = ["mineshaft", "stronghold", "ancient_city", "trial_chambers", "end_city", "fortress", "bastion"]
    static let flying: Set<String> = ["ghast", "blaze", "vex", "bat", "allay", "phantom", "wither", "ender_dragon", "shulker", "end_crystal",
                                      "parrot", "bee", "happy_ghast", "breeze",
                                      "searwing"]          // (check fix 25: hell's winged mob, P336)
    static let poiKeys: Set<String> = ["chest", "trapped_chest", "barrel", "lectern", "composter", "smoker", "cartography_table",
                                       "fletching_table", "loom", "stonecutter", "cauldron", "blast_furnace", "smithing_table", "grindstone",
                                       "brewing_stand", "crafting_table", "bell", "furnace", "anvil", "enchanting_table"]

    // MARK: Walk model

    static let garageDoor: BlockID = Blocks.has(Depots.shutter) ? Blocks.groupBase[Int(Blocks.id(Depots.shutter))] : 0

    static func top(_ w: World, _ x: Int, _ y: Int, _ z: Int) -> Float {
        let b = w.block(x, y, z)
        let sh = Blocks.shape[Int(b)]
        if sh == "door" { return 0 }
        if Blocks.key(Blocks.groupBase[Int(b)]).hasSuffix("_fence_gate") { return 0 }
        // (Check fix 25: a garage door swings open from its buttons (GarageDoors.swift), like a door.)
        if Blocks.groupBase[Int(b)] == garageDoor { return 0 }
        return PathFinder.solidTop(w, x, y, z)
    }

    // Feet height of a body standing with its feet in cell (x, y, z), or nil if it can't stand there.
    static func feet(_ w: World, _ x: Int, _ y: Int, _ z: Int) -> Float? {
        guard y > 0 && y < CH - 3 else { return nil }
        let id0 = w.block(x, y, z)
        if Blocks.fluidKind[Int(id0)] == 1 {
            // Swimming: a water cell with water or open air above it (a player swims to a chest across a pool; run 354:
            // three ruined-portal chests counted unreachable behind water).
            let up = w.block(x, y + 1, z)
            if Blocks.fluidKind[Int(up)] == 1 || top(w, x, y + 1, z) <= 0.01 { return Float(y) + 0.5 }
            return nil
        }
        if PathFinder.danger(id0) || Blocks.fluidKind[Int(id0)] != 0 { return nil }
        let t0 = top(w, x, y, z)
        if t0 > 0.6 { return nil }
        if top(w, x, y + 1, z) > 0.01 { return nil }
        if t0 > 0.2 && top(w, x, y + 2, z) > 0.01 { return nil }
        if t0 > 0.01 { return Float(y) + t0 }
        if PathFinder.climbable(id0) { return Float(y) }
        let below = w.block(x, y - 1, z)
        if PathFinder.danger(below) { return nil }
        let tb = top(w, x, y - 1, z)
        if tb >= 0.4 && tb <= 1.01 { return Float(y - 1) + tb }
        if Blocks.fluidKind[Int(below)] == 1 { return nil }
        return nil
    }

    // The standing cell in column (x, z) nearest below or at y (within `down` blocks), with its feet height.
    static func standNear(_ w: World, _ x: Int, _ y: Int, _ z: Int, up: Int = 1, down: Int = 3) -> (Int, Float)? {
        var yy = y + up
        while yy >= y - down {
            if let f = feet(w, x, yy, z) { return (yy, f) }
            yy -= 1
        }
        return nil
    }

    @inline(__always) static func key(_ x: Int, _ y: Int, _ z: Int) -> Int { PathFinder.key(IVec3(x, y, z)) }
    @inline(__always) static func colKey(_ x: Int, _ z: Int) -> Int { (x & 0xFFFFF) | ((z & 0xFFFFF) << 20) }

    // Reachable cells from the seeds inside a box: (walking only, walking or jumping).
    static func reach(_ w: World, seeds: [IVec3], lo: IVec3, hi: IVec3) -> (walk: Set<Int>, any: Set<Int>) {
        func bfs(_ jump: Bool) -> Set<Int> { walkOrder(w, seeds: seeds, lo: lo, hi: hi, jump: jump).seen }
        return (bfs(false), bfs(true))
    }

    // The cells a walker reaches from the seeds inside a box, in breadth-first order (nearest by steps first), and
    // their keys. The cave bot uses the order to pick the nearest cave floor actually connected to the surface.
    static func walkOrder(_ w: World, seeds: [IVec3], lo: IVec3, hi: IVec3, jump: Bool, limit: Int = 400_000)
        -> (cells: [IVec3], seen: Set<Int>) {
            var seen = Set<Int>()
            var queue: [(Int, Int, Int, Float)] = []
            for s in seeds { if let f = feet(w, s.x, s.y, s.z), seen.insert(key(s.x, s.y, s.z)).inserted { queue.append((s.x, s.y, s.z, f)) } }
            var head = 0
            while head < queue.count && seen.count < limit {
                let (x, y, z, f) = queue[head]
                head += 1
                let here = w.block(x, y, z)
                // Diving and surfacing: straight up and down through water (the neighbour search below takes the
                // highest cell, so a swimmer never left the surface; run 356: three ruined portals 30 blocks down).
                if Blocks.fluidKind[Int(here)] == 1 {
                    for dy in [1, -1] {
                        let ny = y + dy
                        if let nf = feet(w, x, ny, z), seen.insert(key(x, ny, z)).inserted { queue.append((x, ny, z, nf)) }
                    }
                }
                // Ladders and vines: straight up and down.
                if PathFinder.climbable(here) || PathFinder.climbable(w.block(x, y + 1, z)) {
                    for dy in [1, -1] {
                        let ny = y + dy
                        if let nf = feet(w, x, ny, z) ?? (PathFinder.climbable(w.block(x, ny, z)) ? Float(ny) : nil), seen.insert(key(x, ny, z)).inserted {
                            queue.append((x, ny, z, nf))
                        }
                    }
                }
                // A trapdoor over a ladder shaft opens: down through it from the floor, up through it from the ladder.
                if Blocks.shape[Int(w.block(x, y - 1, z))] == "trapdoor" && PathFinder.climbable(w.block(x, y - 2, z)),
                   seen.insert(key(x, y - 2, z)).inserted { queue.append((x, y - 2, z, Float(y - 2))) }
                if PathFinder.climbable(here) && Blocks.shape[Int(w.block(x, y + 1, z))] == "trapdoor"
                    && top(w, x, y + 2, z) <= 0.01 && top(w, x, y + 3, z) <= 0.01,
                   seen.insert(key(x, y + 2, z)).inserted { queue.append((x, y + 2, z, feet(w, x, y + 2, z) ?? Float(y + 2))) }
                for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, nz = z + dz
                    if nx < lo.x || nx > hi.x || nz < lo.z || nz > hi.z { continue }
                    // Highest standable cell in the neighbour column from one up to three down.
                    var ny = y + 1
                    var found: (Int, Float)?
                    while ny >= y - 3 {
                        if ny < lo.y || ny > hi.y { ny -= 1; continue }
                        if let nf = feet(w, nx, ny, nz) { found = (ny, nf); break }
                        // A solid cell in between at head height blocks the move.
                        if ny < y + 1 && top(w, nx, ny + 1, nz) > 0.01 && ny + 1 <= y + 1 { break }
                        ny -= 1
                    }
                    guard let (cy, cf) = found else { continue }
                    let rise = cf - f
                    if rise > (jump ? 1.25 : 0.6) || rise < -3.2 { continue }
                    if rise > 0.6 && top(w, x, y + 2, z) > 0.01 { continue }          // no headroom to jump
                    if cy < y && top(w, nx, y + 1, nz) > 0.01 { continue }            // can't step off under a ceiling lip
                    if seen.insert(key(nx, cy, nz)).inserted { queue.append((nx, cy, nz, cf)) }
                }
            }
            return (queue.map { IVec3($0.0, $0.1, $0.2) }, seen)
    }

    // MARK: Run

    static func run(device: MTLDevice) -> Int32 {
        let seeds: [UInt64] = (arg("--seeds") ?? "12345,777,424242").split(separator: ",").compactMap { UInt64($0) }
        let per = Int(arg("--per") ?? "") ?? 3
        let only: Set<String>? = arg("--kinds").map { Set($0.split(separator: ",").map(String.init)) }
        let dims: [Dim] = (arg("--dims") ?? "overworld,nether,end").split(separator: ",").compactMap { Dim(rawValue: String($0)) }
        let t0 = CFAbsoluteTimeGetCurrent()
        PathFinder.doors = true
        var issues: [Issue] = []
        var stats: [String: (n: Int, doors: Int, pois: Int, mobs: Int)] = [:]
        for seed in seeds {
            for dim in dims {
                let world = World(seed: seed, device: device, save: nil, dim: dim)
                if meet { world.makeFieldWorld() }          // (--meet: the headset's ground, a density field)
                guard let cache = world.gen.structures else { continue }
                var kinds: [(String, [StructureStart])] = []
                for t in cache.types where only == nil || only!.contains(t.name) {
                    var found: [StructureStart] = []
                    var r = 0
                    while found.count < per && r < 6 {
                        for rz in -r...r { for rx in -r...r where max(abs(rx), abs(rz)) == r && found.count < per {
                            if let s = cache.start(t, regionX: rx, regionZ: rz) { found.append(s) }
                        } }
                        r += 1
                    }
                    kinds.append((t.name, found))
                }
                let fixedKinds = Set(cache.fixed.map { $0.kind })
                for k in fixedKinds where only == nil || only!.contains(k) {
                    var fs: [StructureStart] = cache.fixed.filter { (f: StructureStart) -> Bool in f.kind == k }
                    fs.sort { (a: StructureStart, b: StructureStart) -> Bool in
                        let da: Int = abs(a.anchor.x) + abs(a.anchor.z)
                        let db: Int = abs(b.anchor.x) + abs(b.anchor.z)
                        return da < db
                    }
                    kinds.append((k, Array(fs.prefix(per))))
                }
                for (name, starts) in kinds {
                    for s in starts {
                        let r = check(world, s, typeName: name, seed: seed)
                        issues += r.issues
                        var st = stats[name] ?? (0, 0, 0, 0)
                        st.n += 1; st.doors += r.doors; st.pois += r.pois; st.mobs += r.mobs
                        stats[name] = st
                        world.unloadAll()
                        world.blockEntities.removeAll()
                        world.pendingMobs.removeAll()
                    }
                }
            }
        }
        PathFinder.doors = false
        // Summary per kind and class.
        var byKind: [String: [String: Int]] = [:]
        for i in issues { byKind[i.kind, default: [:]][i.cls, default: 0] += 1 }
        var lines: [String] = []
        lines.append("# Structure check")
        lines.append("")
        lines.append("Seeds \(seeds.map(String.init).joined(separator: ", ")), up to \(per) per kind. Walk model: steps <= 0.6 walk, <= 1.25 jump, drops <= 3.")
        lines.append("")
        lines.append("| kind | checked | doors | POIs | mobs | issues |")
        lines.append("|---|---|---|---|---|---|")
        for k in stats.keys.sorted() {
            let st = stats[k]!
            let iss = (byKind[k] ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
            lines.append("| \(k) | \(st.n) | \(st.doors) | \(st.pois) | \(st.mobs) | \(iss.isEmpty ? "-" : iss) |")
        }
        lines.append("")
        lines.append("## Issues (first 6 per kind and class)")
        var shown: [String: Int] = [:]
        for i in issues {
            let k = i.kind + "/" + i.cls
            shown[k, default: 0] += 1
            if shown[k]! > 6 { continue }
            let snap = "--snapshot snaps/issue.png --seed \(i.seed) --x \(i.pos.x) --z \(i.pos.z) --up 3 --pitch -30"
            let shownY: Int = i.pos.y - YOFF
            let where_: String = "seed \(i.seed) at \(i.pos.x) \(shownY) \(i.pos.z)"
            lines.append("- **\(i.cls)** \(i.kind) " + where_ + ": \(i.detail)  `\(snap)`")
            if !i.view.isEmpty { lines.append("  - view: `\(i.view)`") }
        }
        if meet {
            lines.append("")
            lines.append("## Meeting the ground (--meet): outside columns over the drawn ground by more than 0.3 blocks")
            lines.append("")
            lines.append("| kind | columns | over a gap | worst |")
            lines.append("|---|---|---|---|")
            for (k, v) in meetCols.sorted(by: { $0.key < $1.key }) {
                lines.append(String(format: "| %@ | %ld | %ld | %.2f |", k, v.cols, v.gaps, v.worst))
                print(String(format: "structmeet: %@ %ld columns, %ld over a gap of 0.3-1.5, worst %.2f", k, v.cols, v.gaps, v.worst))
            }
            let h = meetHist.map(String.init).joined(separator: " / ")
            lines.append("")
            lines.append("Every outside column: gap up to 0.3 / 0.3-0.6 / 0.6-1.0 / 1.0-1.5 / no ground within 1.5: " + h)
            print("structmeet: every outside column: gap up to 0.3 / 0.3-0.6 / 0.6-1.0 / 1.0-1.5 / no ground within 1.5: " + h)
            print("structmeet: the gaps: \(meetUnder[0]) with ground in the cell under the block, \(meetUnder[1]) with none there")
        }
        let report = lines.joined(separator: "\n") + "\n"
        if let out = arg("--out") { try? report.write(toFile: out, atomically: true, encoding: .utf8) }
        for l in lines.prefix(6 + stats.count) { print("structcheck " + l) }
        var byClass: [String: Int] = [:]
        for i in issues { byClass[i.cls, default: 0] += 1 }
        let summary = byClass.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        print(String(format: "structcheck: %ld instances, %ld issues (%@) in %.1f s", stats.values.reduce(0) { $0 + $1.n }, issues.count,
                     summary.isEmpty ? "none" : summary, CFAbsoluteTimeGetCurrent() - t0))
        return CommandLine.arguments.contains("--strict") && !issues.isEmpty ? 2 : 0
    }

    // MARK: Meeting the ground (--meet)

    // Week item 60 ("built things sit on the ground", a trailer bug: houses floating off slopes). In a field world (the
    // headset's: natural ground is a density field drawn smooth, buildings stay blocks) each column's lowest built block
    // that rests on its floor, on the building's outside (open to one side), is measured against the drawn ground under
    // it (World.floorGap: its corners, edge middles and middle). A gap over 0.3 blocks shows daylight under the wall.
    static let meet = CommandLine.arguments.contains("--meet")
    static var meetCols: [String: (cols: Int, gaps: Int, worst: Float)] = [:]
    static var meetTraced = 0
    static var meetUnder = [0, 0]                              // gaps over ground in the cell under the block / over none
    static var meetHist = [Int](repeating: 0, count: 5)       // gap <= 0.3, 0.3-0.6, 0.6-1.0, 1.0-1.5, none within 1.5
    // World.floorGap, leaving out the samples on a side where a built block stands beside it, at its level or under it:
    // the ground meets that block's side there (a wall going on down, the next course of a foundation), out of sight
    // (build 305's traces: most "gaps" were the drawn ground dipping beside a deeper log or plank of the same building).
    static func sideGap(_ w: World, _ x: Int, _ y: Int, _ z: Int) -> Float {
        func walled(_ dx: Int, _ dz: Int) -> Bool {
            Blocks.collide[Int(w.builtBlock(x + dx, y - 1, z + dz))] || Blocks.collide[Int(w.builtBlock(x + dx, y, z + dz))]
        }
        let wx0 = walled(-1, 0), wx1 = walled(1, 0), wz0 = walled(0, -1), wz1 = walled(0, 1)
        var worst: Float = 0
        for k in 0..<9 {
            let i = k % 3, j = k / 3
            if i == 0 && wx0 || i == 2 && wx1 || j == 0 && wz0 || j == 2 && wz1 { continue }
            let o = V3(Float(x) + 0.02 + Float(i) * 0.48, Float(y) + 0.02, Float(z) + 0.02 + Float(j) * 0.48)
            guard w.fieldDensity(at: o) <= 0 else { continue }
            if let h = w.fieldRaySegment(o, V3(0, -1, 0), from: 0, to: 1.5) { worst = max(worst, Float(y) - h.at.y) } else { worst = max(worst, 1.5) }
        }
        return worst
    }
    static func meetCheck(_ w: World, _ s: StructureStart, typeName: String, seed: UInt64) -> [Issue] {
        let kind = s.kind
        if noWalk.contains(typeName) || fromInside.contains(typeName) || ["sky_isle", "end_centre", "ruined_portal"].contains(typeName) { return [] }
        var gaps: [(IVec3, Float)] = []
        var cols = 0
        let y0 = max(2, s.min.y), y1 = min(CH - 2, s.max.y)
        for z in s.min.z...s.max.z { for x in s.min.x...s.max.x {
            var found: Int? = nil
            var y = y0
            while y <= y1 {
                let b = Int(w.builtBlock(x, y, z))
                if Blocks.collide[b] {
                    if World.restsOnFloor[b] && !Blocks.collide[Int(w.builtBlock(x, y - 1, z))] { found = y }
                    break
                }
                y += 1
            }
            guard let yb = found else { continue }
            var open = false
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where !Blocks.collide[Int(w.builtBlock(x + dx, yb, z + dz))] {
                if w.fieldDensity(at: V3(Float(x + dx) + 0.5, Float(yb) + 0.5, Float(z + dz) + 0.5)) <= 0 { open = true; break }
            }
            guard open else { continue }
            cols += 1
            // (1.5: no ground within a block and a half under it: eaves, a balcony, a bridge deck: held by what it's
            // built on, and a base hanging that far is the block-world check's `floating`. The bug is a base standing a
            // little proud of the smoothed slope.)
            let g = sideGap(w, x, yb, z)
            meetHist[g <= 0.3 ? 0 : g < 0.6 ? 1 : g < 1.0 ? 2 : g < 1.49 ? 3 : 4] += 1
            if g > 0.3 && g < 1.49 {
                gaps.append((IVec3(x, yb, z), g))
                // (what is under it: ground in the cell below (the drawn ground curving away at its edge), or not)
                meetUnder[w.fieldDensity(at: V3(Float(x) + 0.5, Float(yb) - 0.5, Float(z) + 0.5)) > 0 ? 0 : 1] += 1
                if meetTraced < 16 {
                    meetTraced += 1
                    func dc(_ ax: Int, _ ay: Int, _ az: Int) -> String {
                        String(format: "%.2f", w.fieldDensity(at: V3(Float(ax) + 0.5, Float(ay) + 0.5, Float(az) + 0.5)))
                    }
                    var samples: [String] = []
                    for k in 0..<9 {
                        let px = Float(x) + 0.02 + Float(k % 3) * 0.48, pz = Float(z) + 0.02 + Float(k / 3) * 0.48
                        let o = V3(px, Float(yb) + 0.02, pz)
                        if w.fieldDensity(at: o) > 0 { samples.append("in"); continue }
                        if let h = w.fieldRaySegment(o, V3(0, -1, 0), from: 0, to: 1.5) { samples.append(String(format: "%.2f", Float(yb) - h.at.y)) }
                        else { samples.append("-") }
                    }
                    var nb: [String] = []
                    for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let k0 = Blocks.key(w.builtBlock(x + dx, yb - 1, z + dz)), k1 = Blocks.key(w.builtBlock(x + dx, yb, z + dz))
                        nb.append("\(dx),\(dz): below \(dc(x + dx, yb - 1, z + dz)) \(k0) / level \(dc(x + dx, yb, z + dz)) \(k1)")
                    }
                    print("structmeet trace: \(kind) \(x) \(yb - YOFF) \(z) \(Blocks.key(w.builtBlock(x, yb, z))) gap \(String(format: "%.2f", g)); samples \(samples.joined(separator: " ")); cell under \(dc(x, yb - 1, z)) \(Blocks.key(w.builtBlock(x, yb - 1, z))), own \(dc(x, yb, z)); " + nb.joined(separator: "; "))
                }
            }
        } }
        let worst = gaps.map { $0.1 }.max() ?? 0
        var m = meetCols[kind] ?? (0, 0, 0)
        m.cols += cols; m.gaps += gaps.count; m.worst = max(m.worst, worst)
        meetCols[kind] = m
        guard let first = gaps.max(by: { $0.1 < $1.1 }) else { return [] }
        let p = first.0
        let blk = Blocks.key(Blocks.groupBase[Int(w.builtBlock(p.x, p.y, p.z))])
        var out = [Issue(cls: "floor_gap", kind: kind, seed: seed, pos: p,
                         detail: String(format: "%ld of %ld outside columns stand over the drawn ground, worst %.2f blocks (%@)", gaps.count, cols, worst, blk))]
        out[0].view = "--view v.png --seed \(seed) --at \(p.x + 4),\(p.y + 1),\(p.z) --look 90,-15 --field"
        return out
    }

    // MARK: One instance

    // --slices: each unreachable door or point of interest printed as top-down maps of the cells round it (two levels
    // under its feet to two over), one character a cell, so a flag can be read without a render. '#' collides fully,
    // '+' collides in part (slabs, fences, panes, stairs), 'D' door, 'H' ladder, '~' fluid, '.' open; the flagged cell is
    // shown as '@' over its own character's place.
    static let slices = CommandLine.arguments.contains("--slices")
    static func printSlice(_ w: World, _ p: IVec3, label: String, r: Int = 8) {
        print("slice: \(label) at \(p.x) \(p.y - YOFF) \(p.z) (rows +z down, columns +x right, x from \(p.x - r), z from \(p.z - r))")
        var parts: [String: Int] = [:]                      // the '+' cells' blocks at its level and the one over it
        for dy in 0...1 { for z in (p.z - r)...(p.z + r) { for x in (p.x - r)...(p.x + r) {
            let b = w.block(x, p.y + dy, z), i = Int(b)
            if Blocks.collide[i] && !Blocks.fullCollide[i] && !PathFinder.isDoor(b) && !PathFinder.climbable(b) { parts[Blocks.key(Blocks.groupBase[i]), default: 0] += 1 }
        } } }
        print("slice:  '+' there: " + parts.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        for dy in stride(from: 2, through: -2, by: -1) {
            print("slice:  y \(p.y + dy - YOFF)\(dy == 0 ? " (its level)" : "")")
            for z in (p.z - r)...(p.z + r) {
                var row = ""
                for x in (p.x - r)...(p.x + r) {
                    if x == p.x && z == p.z && dy == 0 { row += "@"; continue }
                    let b = w.block(x, p.y + dy, z)
                    let i = Int(b)
                    if PathFinder.isDoor(b) { row += "D" }
                    else if PathFinder.climbable(b) { row += "H" }
                    else if Blocks.fluidKind[i] != 0 { row += "~" }
                    else if Blocks.fullCollide[i] { row += "#" }
                    else if Blocks.collide[i] { row += "+" }
                    else { row += "." }
                }
                print("slice:   " + row)
            }
        }
    }

    static func check(_ w: World, _ s: StructureStart, typeName: String, seed: UInt64) -> (issues: [Issue], doors: Int, pois: Int, mobs: Int) {
        var out: [Issue] = []
        let kind = s.kind
        func add(_ cls: String, _ p: IVec3, _ d: String) {
            out.append(Issue(cls: cls, kind: kind, seed: seed, pos: p, detail: d))
            if slices && cls.hasSuffix("unreachable") { printSlice(w, p, label: "\(kind) \(cls) seed \(seed)") }
        }
        let margin = 6
        let lo = IVec3(s.min.x - margin, max(1, s.min.y - 4), s.min.z - margin)
        let hi = IVec3(s.max.x + margin, min(CH - 4, s.max.y + 4), s.max.z + margin)
        let cx0 = floorDiv(lo.x, CS), cz0 = floorDiv(lo.z, CS), cx1 = floorDiv(hi.x, CS), cz1 = floorDiv(hi.z, CS)
        // Very large structures (strongholds' bounding boxes can be huge): skip anything over 24x24 chunks.
        guard (cx1 - cx0) <= 24 && (cz1 - cz0) <= 24 else { return ([], 0, 0, 0) }
        w.loadBlocks(cx0: cx0 - 1, cz0: cz0 - 1, cx1: cx1 + 1, cz1: cz1 + 1)
        if meet { return (meetCheck(w, s, typeName: typeName, seed: seed), 0, 0, 0) }
        // Blocks the structure wrote: compare with the bare terrain.
        var written = Set<Int>()
        var writtenSolid: [Int: [Int]] = [:]           // column key -> written solid y values
        var lowestOnGround: [Int: Bool] = [:]
        for cz in cz0...cz1 { for cx in cx0...cx1 {
            let raw = w.gen.generate(cx: cx, cz: cz)
            for z in 0..<CS { for x in 0..<CS {
                let wx = cx * CS + x, wz = cz * CS + z
                if wx < s.min.x || wx > s.max.x || wz < s.min.z || wz > s.max.z { continue }
                for y in thru(max(1, s.min.y), min(CH - 2, s.max.y)) {
                    let b = w.block(wx, y, wz)
                    if b == raw[Chunk.index(x, y, z)] { continue }
                    written.insert(key(wx, y, wz))
                    if Blocks.fullCollide[Int(b)] {
                        let ck = colKey(wx, wz)
                        // The column's lowest written block (y ascends) replaced solid ground: it rests on the terrain's
                        // own crust, even with a cave under it (run 364: village floors on a 1-block crust over caves).
                        if writtenSolid[ck] == nil { lowestOnGround[ck] = Blocks.fullCollide[Int(raw[Chunk.index(x, y, z)])] }
                        writtenSolid[ck, default: []].append(y)
                    }
                }
            } }
        } }
        let walk = !noWalk.contains(typeName) && !noWalk.contains(kind)
        // Seeds: the start's anchor, plus (surface kinds) a ring of ground cells around the structure.
        var seedCells: [IVec3] = []
        if let (ay, _) = standNear(w, s.anchor.x, s.anchor.y, s.anchor.z, up: 2, down: 4) { seedCells.append(IVec3(s.anchor.x, ay, s.anchor.z)) }
        else {
            // Rings outward to 10 blocks (bastion and ruined-portal anchors sit in solid blocks: no_start).
            outer: for r in 1...10 { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
                if let (ay, _) = standNear(w, s.anchor.x + dx, s.anchor.y, s.anchor.z + dz, up: 4, down: 6) {
                    seedCells.append(IVec3(s.anchor.x + dx, ay, s.anchor.z + dz)); break outer
                }
            } } }
        }
        let surface = !fromInside.contains(typeName) && !fromInside.contains(kind)
        if surface {
            let r0 = IVec3(s.min.x - 4, 0, s.min.z - 4), r1 = IVec3(s.max.x + 4, 0, s.max.z + 4)
            var ring: [(Int, Int)] = []
            for x in stride(from: r0.x, through: r1.x, by: 3) { ring.append((x, r0.z)); ring.append((x, r1.z)) }
            for z in stride(from: r0.z, through: r1.z, by: 3) { ring.append((r0.x, z)); ring.append((r1.x, z)) }
            for (x, z) in ring {
                let ty = w.topY(x, z)
                if let (y, _) = standNear(w, x, ty + 1, z, up: 0, down: 1), Blocks.fluidKind[Int(w.builtBlock(x, y - 1, z))] == 0 { seedCells.append(IVec3(x, y, z)) }
            }
        }
        let (rw, ra) = walk && !seedCells.isEmpty ? reach(w, seeds: seedCells, lo: lo, hi: hi) : (Set<Int>(), Set<Int>())
        if walk && seedCells.isEmpty { add("no_start", s.anchor, "no standable cell at the start piece or around the structure") }
        if walk && !surface, let c = seedCells.first {
            // Entered from inside: where the walk starts and how far it gets (stronghold POIs were all unreachable).
            let ay = s.anchor.y - YOFF, cy = c.y - YOFF, y0 = s.min.y - YOFF, y1 = s.max.y - YOFF
            let under = Blocks.key(w.materialAt(c.x, c.y - 1, c.z))
            // How much of the structure itself the walk got into, and how high.
            var inside = 0, topY = Int.min
            for k in ra {
                func sx(_ v: Int) -> Int { v >= 0x80000 ? v - 0x100000 : v }
                let x = sx(k & 0xFFFFF), z = sx((k >> 20) & 0xFFFFF), yy = (k >> 40) & 0x3FF
                if s.contains(x, yy, z) { inside += 1; topY = max(topY, yy - YOFF) }
            }
            print("structcheck: \(kind) at \(s.anchor.x) \(ay) \(s.anchor.z): start cell \(c.x) \(cy) \(c.z) (\(under) under), reaches \(ra.count) cells (\(rw.count) without jumps), \(inside) inside the structure up to y \(topY), box \(y0)...\(y1)")
        }
        // Doors.
        var doors = 0, pois = 0
        var explained = false
        var viewArgs = ""
        if walk {
            for y in thru(max(1, s.min.y), min(CH - 3, s.max.y)) { for z in s.min.z...s.max.z { for x in s.min.x...s.max.x {
                let b = w.block(x, y, z)
                guard Blocks.shape[Int(b)] == "door" else { continue }
                let st = Int(b - Blocks.groupBase[Int(b)])
                if st & 8 != 0 { continue }
                doors += 1
                let f = st & 3
                let (ax, az) = f < 2 ? (0, 1) : (1, 0)
                let p = IVec3(x, y, z)
                let iron = Blocks.key(Blocks.groupBase[Int(b)]).hasPrefix("iron_")
                // The upper half: another write in the same column (a wall, a roof row, a neighbour piece) can replace it,
                // leaving a one-block door under a wall.
                let up = w.block(x, y + 1, z)
                if Blocks.groupBase[Int(up)] != Blocks.groupBase[Int(b)] { add("door_half", p, "a door without its upper half (\(Blocks.key(up)) above)") }
                guard let fd = feet(w, x, y, z) else { add("door_no_floor", p, "nothing to stand on in the doorway"); continue }
                var sideOK = 0
                var sides: [IVec3] = []
                for sgn in [-1, 1] {
                    let sx = x + ax * sgn, sz = z + az * sgn
                    guard let (sy, sf) = standNear(w, sx, y, sz, up: 1, down: 1) else {
                        add("door_blocked", p, "no room to stand on the \(sgn < 0 ? "-" : "+")\(ax == 1 ? "x" : "z") side (\(Blocks.key(w.materialAt(sx, y, sz))) / \(Blocks.key(w.materialAt(sx, y + 1, sz))))")
                        continue
                    }
                    let rise = abs(sf - fd)
                    if rise > 0.6 { add("door_step", p, String(format: "a %.2f-block step through the door (%@ side)", rise, sgn < 0 ? "-" : "+")) }
                    sideOK += 1
                    sides.append(IVec3(sx, sy, sz))
                }
                if sideOK == 0 || iron { continue }
                let kd = key(x, y, z)
                var reachAny = ra.contains(kd), reachWalk = rw.contains(kd)
                for c in sides {
                    let kc = key(c.x, c.y, c.z)
                    if ra.contains(kc) { reachAny = true }
                    if rw.contains(kc) { reachWalk = true }
                }
                if !reachAny { add("door_unreachable", p, "no walking route from \(surface ? "outside" : "the start piece")") }
                else if !reachWalk && kind == "village" {
                    // The ground round the door's outer side: feet heights (relative to the doorway) in a 7x7 square, so
                    // the step that needs the jump shows in the report.
                    var grid: [String] = []
                    if let o = sides.first {
                        for dz in -3...3 {
                            var row = ""
                            for dx in -3...3 {
                                if let (_, f) = standNear(w, o.x + dx, y, o.z + dz, up: 2, down: 3) {
                                    let r = f - fd
                                    row += r == 0 ? " 0" : String(format: "%+.1f", r).replacingOccurrences(of: ".0", with: "")
                                } else { row += " #" }
                                row += " "
                            }
                            grid.append(row)
                        }
                    }
                    add("door_needs_jump", p, "reachable only with 1-block jumps; ground round the outer side (rows z-3...z+3): " + grid.joined(separator: " | "))
                }
            } } }
            // Check fix 28: another structure's pieces that reach into this one's box (a Greywall base's own depot, built
            // against its wall, P469: its magazine chests, walked from the depot's own gate by the depot's check, counted as
            // the base's from the base's side of the fence: poi_unreachable 12).
            var foreign: [Piece] = []
            if let reg = w.gen.structures {
                let ccx = floorDiv((s.min.x + s.max.x) / 2, CS), ccz = floorDiv((s.min.z + s.max.z) / 2, CS)
                for t in reg.types where t.name != typeName && t.name != kind {
                    for o in reg.startsNear(cx: ccx, cz: ccz, t) where o.kind != kind {
                        foreign += o.pieces.filter { $0.max.x >= s.min.x && $0.min.x <= s.max.x && $0.max.z >= s.min.z && $0.min.z <= s.max.z }
                    }
                }
            }
            // Points of interest and beds.
            for y in thru(max(1, s.min.y), min(CH - 3, s.max.y)) { for z in s.min.z...s.max.z { for x in s.min.x...s.max.x {
                guard written.contains(key(x, y, z)) else { continue }
                let b = w.block(x, y, z)
                let base = Blocks.key(Blocks.groupBase[Int(b)])
                let isBed = base.hasSuffix("_bed") || base.hasSuffix("_bed_head")
                guard isBed || poiKeys.contains(base) else { continue }
                if isBed {
                    // The other half must sit next to this one.
                    let want = base.hasSuffix("_head") ? String(base.dropLast(5)) : base + "_head"
                    var pair = false
                    for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where Blocks.key(Blocks.groupBase[Int(w.materialAt(x + dx, y, z + dz))]) == want { pair = true }
                    if !pair { add("bed_broken", IVec3(x, y, z), "\(base) without its other half") }
                    if base.hasSuffix("_head") { continue }
                }
                // Only the structure's own: a mineshaft or dungeon chest that happens to lie in the bounding box differs
                // from bare terrain too (run 359: a chest 21 blocks under a stronghold's floor counted as its own).
                let own = s.pieces.contains { (pc: Piece) -> Bool in
                    let inX: Bool = x >= pc.min.x && x <= pc.max.x
                    let inYZ: Bool = y >= pc.min.y && y <= pc.max.y && z >= pc.min.z && z <= pc.max.z
                    return inX && inYZ
                }
                if !own { continue }
                if foreign.contains(where: { (pc: Piece) -> Bool in
                    let inX: Bool = x >= pc.min.x && x <= pc.max.x
                    let inYZ: Bool = y >= pc.min.y && y <= pc.max.y && z >= pc.min.z && z <= pc.max.z
                    return inX && inYZ
                }) { continue }
                // A world-gen dungeon's chest inside the box (mossy cobblestone floor, a spawner beside it): not the
                // structure's own (run 373: a Steelhold foundation closed a dungeon's cave opening).
                // Another structure's chest inside this box (a desert pyramid's treasure room under a citadel, seed
                // 424242: store audit) is that structure's business.
                // Its mark: TNT two below the room's centre, four blocks from the chest.
                if base == "chest" && [(4, 0), (-4, 0), (0, 4), (0, -4)].contains(where: { (dx: Int, dz: Int) -> Bool in
                    Blocks.key(w.materialAt(x + dx, y - 2, z + dz)) == "tnt" }) { continue }
                if base == "chest" {
                    var mossy = false, spawner = false
                    for dz in -1...1 { for dx in -1...1 where Blocks.key(w.materialAt(x + dx, y - 1, z + dz)) == "mossy_cobblestone" { mossy = true } }
                    for dz in -4...4 { for dx in -4...4 where Blocks.key(w.materialAt(x + dx, y, z + dz)) == "spawner" { spawner = true } }
                    if mossy && spawner { continue }
                    // ...or a cobblestone room the structure didn't build (walls on three sides it never wrote: run 375,
                    // a dungeon whose spawner is gone, inside a Steelhold's box).
                    var foreign = 0
                    for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        for d in 1...6 {
                            let qx = x + dx * d, qz = z + dz * d
                            let b = w.block(qx, y, qz)
                            guard Blocks.collide[Int(b)] else { continue }
                            let k = Blocks.key(b)
                            if (k == "cobblestone" || k == "mossy_cobblestone") && !written.contains(key(qx, y, qz)) { foreign += 1 }
                            break
                        }
                    }
                    if foreign >= 3 { continue }
                }
                pois += 1
                // The desert pyramid's treasure room is reached by digging through the floor pattern, by design.
                if kind == "desert_pyramid" && base == "chest" { continue }
                // (Check fix 25: a chest in a barred cell, bars on all four sides, is a deliberate cell broken into: the
                // Chain Gaol's cells, HellWorks.)
                if [(1, 0), (-1, 0), (0, 1), (0, -1)].allSatisfy({ Blocks.key(w.materialAt(x + $0.0, y, z + $0.1)) == "iron_bars" }) { continue }
                var ok = false
                for dz in -1...1 { for dx in -1...1 where !ok && (dx != 0 || dz != 0) {
                    for dy in [-1, 0, 1] where !ok {
                        if ra.contains(key(x + dx, y + dy, z + dz)) { ok = true }
                    }
                } }
                if !ok && !ra.isEmpty {
                    var detail = "\(base): no reachable cell next to it"
                    if !explained {
                        // The first one per structure: the closest cell the walk did reach, and what stands at and
                        // above the cell next to it toward the POI (the wall, step or gap in the way).
                        explained = true
                        var best = IVec3(0, 0, 0), bd = Int.max
                        for k in ra {
                            func sx(_ v: Int) -> Int { v >= 0x80000 ? v - 0x100000 : v }
                            let cx = sx(k & 0xFFFFF), cz = sx((k >> 20) & 0xFFFFF), cy = (k >> 40) & 0x3FF
                            let d = abs(cx - x) + abs(cz - z) + 2 * abs(cy - y)
                            if d < bd { bd = d; best = IVec3(cx, cy, cz) }
                        }
                        let sx = best.x + (x > best.x ? 1 : (x < best.x ? -1 : 0)), sz = best.z + (z > best.z ? 1 : (z < best.z ? -1 : 0))
                        let col = (-1...2).map { Blocks.key(w.materialAt(sx, best.y + $0, sz)) }.joined(separator: "/")
                        let by: Int = best.y - YOFF
                        detail += "; closest reached \(best.x) \(by) \(best.z), next toward it \(sx) \(sz) from y-1 up: \(col)"
                        // Top-down map around the POI at its height (rows -z to +z): P the POI, R a reached cell (y-1..y+1),
                        // # solid at feet or head, f fence/wall, _ open over a floor, ~ fluid, space open over a drop.
                        var rows: [String] = []
                        for mz in (z - 5)...(z + 5) {
                            var row = ""
                            for mx in (x - 7)...(x + 7) {
                                if mx == x && mz == z { row += "P"; continue }
                                if ra.contains(key(mx, y, mz)) || ra.contains(key(mx, y - 1, mz)) || ra.contains(key(mx, y + 1, mz)) { row += "R"; continue }
                                let fb = w.block(mx, y, mz), hb = w.block(mx, y + 1, mz)
                                let fk = Blocks.key(Blocks.groupBase[Int(fb)])
                                if fk.hasSuffix("_fence") || fk.hasSuffix("_wall") { row += "f" }
                                else if Blocks.fluidKind[Int(fb)] != 0 { row += "~" }
                                else if Blocks.collide[Int(fb)] || Blocks.collide[Int(hb)] { row += "#" }
                                else { row += w.solidAt(mx, y - 1, mz) ? "_" : " " }
                            }
                            rows.append(row)
                        }
                        let py: Int = y - YOFF, x0: Int = x - 7, z0: Int = z - 5
                        print("structcheck map \(kind) \(x) \(py) \(z) (columns from x \(x0), rows from z \(z0)):")
                        for r in rows { print("  |\(r)|") }
                        // What closes the room: the first blocking cell each way from the POI (feet / head blocks).
                        var walls: [String] = []
                        for (dx, dz, nm) in [(1, 0, "+x"), (-1, 0, "-x"), (0, 1, "+z"), (0, -1, "-z")] {
                            for d in 1...12 {
                                let fb = w.block(x + dx * d, y, z + dz * d), hb = w.block(x + dx * d, y + 1, z + dz * d)
                                if Blocks.collide[Int(fb)] || Blocks.collide[Int(hb)] {
                                    walls.append("\(nm) at \(d): \(Blocks.key(fb))/\(Blocks.key(hb))"); break
                                }
                            }
                        }
                        let ax = s.anchor.x, az = s.anchor.z
                        let floorKey = Blocks.key(w.materialAt(x, y - 1, z)), ceilKey = Blocks.key(w.materialAt(x, y + 2, z))
                        var near: [String] = []
                        for dy in -2...3 { for dz in -5...5 { for dx in -5...5 {
                            let k = Blocks.key(Blocks.groupBase[Int(w.materialAt(x + dx, y + dy, z + dz))])
                            if k == "spawner" || k == "mossy_cobblestone" || k.hasSuffix("chest") { near.append("\(k)@\(dx),\(dy),\(dz)") }
                        } } }
                        print("  closed by: \(walls.joined(separator: "; ")) (structure anchor \(ax) \(az)); floor \(floorKey), ceiling \(ceilKey); near: \(near.prefix(10).joined(separator: " "))")
                        // Whose it is: the bare terrain's block here and the chest's first items (run 395: a cobblestone room
                        // with a chest under a Steelhold, no spawner and no mossy floor).
                        let rawHere = w.gen.generate(cx: floorDiv(x, CS), cz: floorDiv(z, CS))[Chunk.index(mod(x, CS), y, mod(z, CS))]
                        let items = (w.blockEntities[IVec3(x, y, z)]?.container.slots ?? []).filter { !$0.isEmpty }.prefix(4).map { Items.key($0.item) }
                        print("  terrain here: \(Blocks.key(rawHere)); box y \(s.min.y - YOFF)...\(s.max.y - YOFF), anchor y \(s.anchor.y - YOFF); holds \(items.joined(separator: ", "))")
                        let ddx = Float(x - best.x), ddz = Float(z - best.z)
                        let yawD: Float = atan2f(-ddx, -ddz) * 180 / Float.pi
                        let dimArg = w.dim == .overworld ? "" : " --dim \(w.dim.rawValue)"
                        viewArgs = String(format: "--seed %llu%@ --x %.1f --z %.1f --feet %ld --yaw %.0f --pitch -15", seed, dimArg,
                                          Float(best.x) + 0.5, Float(best.z) + 0.5, by, yawD)
                    }
                    add("poi_unreachable", IVec3(x, y, z), detail)
                    if !viewArgs.isEmpty { out[out.count - 1].view = viewArgs; viewArgs = "" }
                }
            } } }
        }
        // Torches the structure placed: a standing one needs a top to stand on, a wall one a block behind it.
        var torchIssues = 0
        for y in thru(max(1, s.min.y), min(CH - 3, s.max.y)) { for z in s.min.z...s.max.z { for x in s.min.x...s.max.x {
            guard written.contains(key(x, y, z)) else { continue }
            let b = w.block(x, y, z)
            guard Blocks.shape[Int(b)] == "torch" else { continue }
            let st = Int(b - Blocks.groupBase[Int(b)])
            let ok: Bool
            if st == 0 {
                ok = top(w, x, y - 1, z) > 0.4
            } else {
                // Facing f (0 north -Z, 1 south +Z, 2 west -X, 3 east +X): the wall is on the opposite side.
                let back: [(Int, Int)] = [(0, 1), (0, -1), (1, 0), (-1, 0)]
                let (bx, bz) = back[min(3, st - 1)]
                ok = w.solidAt(x + bx, y, z + bz)
            }
            if !ok && torchIssues < 3 {
                torchIssues += 1
                add("torch_unsupported", IVec3(x, y, z), st == 0 ? "standing torch over \(Blocks.key(w.materialAt(x, y - 1, z)))" : "wall torch with nothing behind it")
            }
        } } }
        // Ladders the structure placed: each needs a block behind it (ledger 30: a depot tank wagon's side ladder hung
        // on a corner). State f's panel is on side [1, 0, 3, 2][f] (BlocksBuilding), so its back is that side's cell.
        var ladderIssues = 0
        for y in thru(max(1, s.min.y), min(CH - 3, s.max.y)) { for z in s.min.z...s.max.z { for x in s.min.x...s.max.x {
            guard written.contains(key(x, y, z)) else { continue }
            let b = w.block(x, y, z)
            guard Blocks.shape[Int(b)] == "ladder" else { continue }
            let f = Int(b - Blocks.groupBase[Int(b)])
            let back: [(Int, Int)] = [(0, 1), (0, -1), (1, 0), (-1, 0)]
            let (bx, bz) = back[min(3, f)]
            if !Blocks.collide[Int(w.materialAt(x + bx, y, z + bz))] && ladderIssues < 3 {
                ladderIssues += 1
                let sides = [(1, 0, "+x"), (-1, 0, "-x"), (0, 1, "+z"), (0, -1, "-z")].map { "\($0.2) \(Blocks.key(w.materialAt(x + $0.0, y, z + $0.1)))" }
                add("ladder_unsupported", IVec3(x, y, z), "ladder (state \(f)) with \(Blocks.key(w.materialAt(x + bx, y, z + bz))) behind it; round it \(sides.joined(separator: ", "))")
            }
        } } }
        // Structure mobs.
        var mobs = 0
        for (name, pos) in w.pendingMobs where s.contains(Int(floor(pos.x)), Int(floor(pos.y)), Int(floor(pos.z))) {
            mobs += 1
            let c = IVec3(Int(floor(pos.x)), Int(floor(pos.y + 0.01)), Int(floor(pos.z)))
            let inside = w.block(c.x, c.y, c.z)
            if Blocks.fluidKind[Int(inside)] == 1 { continue }                 // aquatic / spawned in water
            if top(w, c.x, c.y, c.z) > 0.6 || top(w, c.x, c.y + 1, c.z) > 0.01 && !flying.contains(name) {
                add("mob_in_block", c, "\(name) spawns inside \(Blocks.key(inside)) / \(Blocks.key(w.materialAt(c.x, c.y + 1, c.z)))")
                continue
            }
            if flying.contains(name) { continue }
            if standNear(w, c.x, c.y, c.z, up: 0, down: 2) == nil { add("mob_no_floor", c, "\(name) has nothing to stand on"); continue }
            // A villager behind iron bars is a deliberate cell (igloo basement), not a trapped spawn.
            var caged = false
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where Blocks.key(w.materialAt(c.x + dx, c.y, c.z + dz)) == "iron_bars" { caged = true }
            // (Check fix 25: an outpost's captive stands in a fenced cage two blocks round, by design: OverworldStructures.outpostCamp.)
            if typeName == "pillager_outpost" || kind == "pillager_outpost" { caged = true }
            if walk && name == "villager" && !caged && !ra.isEmpty, let (sy, _) = standNear(w, c.x, c.y, c.z, up: 0, down: 2), !ra.contains(key(c.x, sy, c.z)) {
                add("mob_trapped", c, "villager spawn not connected to the village")
            }
        }
        // Floating: columns with at least three written solid blocks whose lowest one hangs over air.
        var floating: [IVec3] = []
        for z in s.min.z...s.max.z { for x in s.min.x...s.max.x {
            guard let ys = writtenSolid[colKey(x, z)], ys.count >= 3, let y0 = ys.min() else { continue }
            // A tree canopy the structure planted (capital city parks) hangs over air by nature (store audit: 13 false hits).
            if Blocks.key(Blocks.groupBase[Int(w.materialAt(x, y0, z))]).hasSuffix("_leaves") { continue }
            if lowestOnGround[colKey(x, z)] == true { continue }
            let below = w.block(x, y0 - 1, z)
            if top(w, x, y0 - 1, z) < 0.4 && Blocks.fluidKind[Int(below)] == 0 && !(y0 - 1 <= 0) {
                // Air under it: count the gap (ignore one-block overhangs over open terrain under 2 blocks).
                var gap = 0
                var yy = y0 - 1
                while yy > 0 && top(w, x, yy, z) < 0.4 && Blocks.fluidKind[Int(w.builtBlock(x, yy, z))] == 0 && gap < 8 { gap += 1; yy -= 1 }
                // (check fix: a roof over a room whose floor matched the ground it was laid on, so it was never counted as
                // written: every way out of the room under it, along the gap's top, meets a written wall within 8. The
                // pueblo's upper tiers on the lower tier's roofs, seed 99: 41 columns. An overhang on a slope is open on
                // its downhill side and still counts.)
                var walled = true
                if gap >= 2 {
                    for (ex, ez) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        var k = 1, met = false
                        while k <= 8 {
                            let qx = x + ex * k, qz = z + ez * k
                            if top(w, qx, y0 - 1, qz) >= 0.4 { met = written.contains(key(qx, y0 - 1, qz)); break }
                            k += 1
                        }
                        if !met { walled = false; break }
                    }
                }
                if gap >= 2 && !walled { floating.append(IVec3(x, y0, z)) }
            }
        } }
        if floating.count >= 3 && !["end_city", "fortress", "bastion", "ruined_portal", "end_centre", "sky_isle"].contains(typeName) && kind != "end_centre" {   // the Hollow's exit-portal island and the sky isles (C7) float by design
            // The first column top-down beside the bare terrain there (block now / generated without structures),
            // to tell a foundation that stopped early from terrain carved away under it.
            let fc = floating[0]
            let raw = w.gen.generate(cx: floorDiv(fc.x, CS), cz: floorDiv(fc.z, CS))
            let lx = fc.x - floorDiv(fc.x, CS) * CS, lz = fc.z - floorDiv(fc.z, CS) * CS
            var stack: [String] = []
            for y in stride(from: fc.y + 2, through: max(1, fc.y - 5), by: -1) {
                let now = Blocks.key(w.materialAt(fc.x, y, fc.z)), was = Blocks.key(raw[Chunk.index(lx, y, lz)])
                stack.append("\(y - YOFF) \(now)" + (now == was ? "" : " (was \(was))"))
            }
            add("floating", floating[0], "\(floating.count) wall/foundation columns over air (first shown; column: \(stack.joined(separator: ", ")))")
            // A view from six blocks east, a little below the hanging block, looking west at its underside.
            let f0 = floating[0]
            let dimArg = w.dim == .overworld ? "" : " --dim \(w.dim.rawValue)"
            let fy: Int = f0.y - YOFF - 3
            out[out.count - 1].view = String(format: "--seed %llu%@ --x %.1f --z %.1f --feet %ld --yaw 90 --pitch 15", seed, dimArg,
                                             Float(f0.x) + 6.5, Float(f0.z) + 0.5, fy)
        }
        return (out, doors, pois, mobs)
    }
}
