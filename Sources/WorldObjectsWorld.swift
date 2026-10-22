import Foundation
import simd

// P389: the objects that have been struck (WorldObjects): each one piece made of its cells' parts, with the list of
// blows taken out of it. Its cells stay in the block grid (light, game rules, what the cell is) but the mesher draws
// the object instead of them (in the section's detail stream, WorldObjects.emit), collision meets what is left of it
// (a box per part round its remaining pieces) and the ray finds its pieces. A blow's cut is made on the object worker
// (a serial queue): the new pieces, what came away and what lost its hold come back to the frame thread, which swaps
// them in, throws the debris and has the touched sections remeshed by the mesh workers. Saved per world in
// objects.json (cells, parts, cuts); a save without it loads every object whole, as cells.
extension WorldObjects {
    // The mesher's copy of one object (immutable: read on the mesh workers).
    final class Draw {
        let origin: IVec3
        let cells: [IVec3]
        let blocks: [BlockID]
        let parts: [Part]
        let frags: [Frag]
        let mine: [Bool]               // per cell: drawn by this object (false once the cell is gone)
        init(origin: IVec3, cells: [IVec3], blocks: [BlockID], parts: [Part], frags: [Frag], mine: [Bool]) {
            self.origin = origin; self.cells = cells; self.blocks = blocks; self.parts = parts; self.frags = frags; self.mine = mine
        }
    }

    final class Obj {
        let id: Int
        let kind: Kind
        let origin: IVec3
        let cells: [IVec3]
        let blocks: [BlockID]
        let parts: [Part]
        let support: [Support]
        // Untouched (built on the object worker before its first cut, so registering costs the blow nothing):
        private(set) var partVolume: [Float] = []    // per part: its volume
        private(set) var cellVolume: [Float] = []    // per cell: the volume of its parts
        private(set) var totalVolume: Float = 0
        private(set) var wholeFrags: [Frag] = []
        var cuts: [Cut] = []
        var dropped: [Bool]               // per cell: its drop given (it lost half its volume)
        var gone: [Bool]                  // per cell: set to air (nothing of it left)
        var leaving: [Bool]               // per cell: nothing left, set to air a frame or two later (P394: Registry.later)
        var frags: [Frag] = []            // frame thread: what is drawn and met
        var applied = 0                   // cuts in `frags`
        var installed = false             // the mesher draws it (its cells are skipped)
        var broken = false
        var draw: Draw?
        var touched: [Bool] = []          // per cell: a blow has reached it (drawn and met as pieces)
        // object worker only
        var wFrags: [Frag] = []
        var wApplied = 0
        var wReady = false
        var wAnchored = true              // something was found holding it up (else nothing of it ever falls)

        init(id: Int, kind: Kind, origin: IVec3, cells: [IVec3], blocks: [BlockID], parts: [Part], support: [Support]) {
            self.id = id; self.kind = kind; self.origin = origin; self.cells = cells; self.blocks = blocks; self.parts = parts
            self.support = support
            dropped = [Bool](repeating: false, count: cells.count)
            gone = [Bool](repeating: false, count: cells.count)
            leaving = gone
        }
        // The untouched pieces and volumes (the object worker before its first cut; the harness on the frame thread).
        func buildWhole(_ ws: Fracture.Workspace) {
            guard !wReady else { return }
            let whole = WorldObjects.wholeFrags(parts, cells: cells, origin: origin, ws: ws)
            var pv = [Float](repeating: 0, count: parts.count), cv = [Float](repeating: 0, count: cells.count)
            for f in whole { pv[f.part] += f.poly.mass.volume; cv[parts[f.part].cell] += f.poly.mass.volume }
            partVolume = pv
            cellVolume = cv
            totalVolume = cv.reduce(0, +)
            wholeFrags = whole
            wFrags = whole
            wAnchored = WorldObjects.held(whole, support: support).contains(true)
            wReady = true
        }
        var originV: V3 { V3(Float(origin.x), Float(origin.y), Float(origin.z)) }
        func cellIndex(_ p: IVec3) -> Int? { cells.firstIndex(of: p) }
        func volumes(_ fr: [Frag]) -> [Float] {
            var v = [Float](repeating: 0, count: cells.count)
            for f in fr { v[parts[f.part].cell] += f.poly.mass.volume }
            return v
        }
    }

    // What a cut job hands back.
    struct Result {
        let id: Int
        let frags: [Frag]
        let removed: [Frag]                // taken out by the blows (debris)
        let fallen: [Frag]                 // no longer held by anything (falls as debris)
        let applied: Int
        let replay: Bool                   // rebuilt from a save: nothing flies
        let workMs: Double
    }

    struct Saved: Codable {
        var id: Int
        var k: UInt8
        var o: [Int]
        var cells: [Int]
        var b: [String]
        var parts: [Part]
        var cuts: [Cut]
        var dropped: [Bool]
        var gone: [Bool]
    }

    final class Registry {
        private(set) var objects: [Int: Obj] = [:]
        private(set) var owner: [IVec3: Int] = [:]          // installed objects' cells
        private(set) var cellObj: [IVec3: Int] = [:]        // ... those a blow has reached (drawn and met as pieces)
        // Harness: every cell of an object drawn and met as its pieces, touched or not (the check that the pieces look
        // as the block mesher drew the cells).
        static var drawAll = false
        static let mainWS = Fracture.Workspace()             // (frame thread: an object's untouched pieces)
        private var byChunk: [ChunkKey: [Int]] = [:]
        private(set) var cellBoxes: [IVec3: [(V3, V3)]] = [:]
        private var nextId = 1
        var dirty = false
        var editing = false                                  // the registry itself is setting cells (setBlock hook)
        // P394: the work a swap-in leaves to the frames after it, one item a frame (a cell that went, a drop): the lamp
        // post's cut-through gave two cells and their drops in one swap-in, about 0.3 ms each.
        var later: [() -> Void] = []
        private let queue = DispatchQueue(label: "object-cuts", qos: .userInitiated)
        private let ws = Fracture.Workspace()                // (object worker only)
        private var planes: [SIMD4<Float>] = []              // (object worker only)
        private let lock = NSLock()
        private var results: [Result] = []
        private(set) var pending = 0
        // The last ray that met an object's piece (World.raycast): the exact point and normal, world frame.
        var lastHit: (cell: IVec3, at: V3, normal: V3)?

        var isEmpty: Bool { objects.isEmpty }
        func object(at p: IVec3) -> Obj? { owner[p].flatMap { objects[$0] } }
        func pendingObject(at p: IVec3) -> Obj? {
            objects.values.first { !$0.installed && !$0.broken && $0.cells.contains(p) }
        }

        // MARK: Registering

        // A struck group becomes an object (its cells drawn as they are until its first cut comes back).
        func register(_ w: World, _ g: Group, kind: Kind) -> Obj {
            let origin = g.lo
            let parts = WorldObjects.makeParts(w, cells: g.cells, blocks: g.blocks, kind: kind)
            let o = Obj(id: nextId, kind: kind, origin: origin, cells: g.cells, blocks: g.blocks, parts: parts,
                        support: Registry.supports(w, g.cells, origin: origin))
            nextId += 1
            objects[o.id] = o
            dirty = true
            return o
        }

        // The faces of solid things outside the object its cells rest against (ground under it, a wall behind it).
        static func supports(_ w: World, _ cells: [IVec3], origin: IVec3) -> [Support] {
            let set = Set(cells)
            var out: [Support] = []
            for c in cells {
                let o = V3(Float(c.x - origin.x), Float(c.y - origin.y), Float(c.z - origin.z))
                for (a, s) in [(0, 1), (0, -1), (1, 1), (1, -1), (2, 1), (2, -1)] as [(Int, Int)] {
                    var q = c
                    if a == 0 { q.x += s } else if a == 1 { q.y += s } else { q.z += s }
                    if set.contains(q) { continue }
                    let nb = w.builtBlock(q.x, q.y, q.z)
                    var solid = Blocks.collide[Int(nb)] || w.groundAt(q.x, q.y, q.z) || (!w.fieldTerrain && Blocks.opaque[Int(w.block(q.x, q.y, q.z))])
                    // (a field world's drawn ground just under the cell's foot holds it too: its cell's sample can be air)
                    if !solid && a == 1 && s < 0 && w.fieldTerrain {
                        solid = w.fieldRaySegment(V3(Float(c.x) + 0.5, Float(c.y) + 0.05, Float(c.z) + 0.5), V3(0, -1, 0), from: 0, to: 1.3) != nil
                    }
                    guard solid else { continue }
                    let at = o[a] + (s > 0 ? 1 : 0)
                    out.append(Support(at: at, axis: a, side: Float(-s), lo: o, hi: o + 1))
                }
            }
            return out
        }

        // MARK: Cutting

        // A blow: queued on the object worker, which cuts it out of what is left.
        func strike(_ o: Obj, _ cut: Cut) {
            o.cuts.append(cut)
            dirty = true
            schedule(o, replay: false)
        }

        private func schedule(_ o: Obj, replay: Bool) {
            let cuts = o.cuts
            pending += 1
            queue.async { [self] in
                let t0 = DispatchTime.now().uptimeNanoseconds
                o.buildWhole(ws)
                var removed: [Frag] = []
                while o.wApplied < cuts.count {
                    let out = WorldObjects.applyCut(o.wFrags, cuts[o.wApplied], ws: ws, planes: &planes)
                    o.wFrags = out.frags.filter { $0.poly.mass.volume > 2e-5 }
                    if !replay { removed += out.removed }
                    o.wApplied += 1
                }
                // (an object nothing was found holding, a torch on a wall drawn clear of it, stands as it stood)
                let on = o.wAnchored ? WorldObjects.held(o.wFrags, support: o.support) : [Bool](repeating: true, count: o.wFrags.count)
                var kept: [Frag] = [], fallen: [Frag] = []
                for (i, f) in o.wFrags.enumerated() { if on[i] { kept.append(f) } else { fallen.append(f) } }
                o.wFrags = kept
                let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
                let r = Result(id: o.id, frags: kept, removed: removed, fallen: fallen, applied: cuts.count, replay: replay, workMs: ms)
                lock.lock(); results.append(r); lock.unlock()
            }
        }

        // Finished cuts (frame thread).
        func poll() -> [Result] {
            guard pending > 0 else { return [] }
            lock.lock()
            let r = results
            results.removeAll(keepingCapacity: true)
            lock.unlock()
            pending -= r.count
            return r
        }

        // Waits for every queued cut (harness).
        func waitIdle() { queue.sync {} }

        // Swaps a finished cut's pieces in: the mesher draws them (sections touched remesh on the mesh workers),
        // collision meets them.
        func install(_ w: World, _ o: Obj, _ r: Result) {
            guard !o.broken, r.applied >= o.applied else { return }
            o.frags = r.frags
            o.applied = r.applied
            if !o.installed {
                o.installed = true
                for (k, c) in o.cells.enumerated() where !o.gone[k] { owner[c] = o.id }
                var keys = Set<ChunkKey>()
                for c in o.cells { keys.insert(ChunkKey(x: floorDiv(c.x, CS), z: floorDiv(c.z, CS))) }
                for k in keys { byChunk[k, default: []].append(o.id) }
            }
            refresh(w, o)
        }

        // A cell of the object is gone (nothing of it left, or set to air by the object): no longer the object's.
        func dropCell(_ o: Obj, _ k: Int) {
            o.gone[k] = true
            if cellObj[o.cells[k]] == o.id { cellObj[o.cells[k]] = nil }
            if owner[o.cells[k]] == o.id { owner[o.cells[k]] = nil }
            cellBoxes[o.cells[k]] = nil
        }

        // The mesher's copy, the collision boxes, and the touched sections remeshed (in the background).
        func refresh(_ w: World, _ o: Obj) {
            // A cell no blow has reached (each of its parts still one whole piece) stays a block: drawn by the block
            // mesher (round shapes, smooth light, exactly as before), met by its own boxes. The rest are the object's.
            var whole = [Int](repeating: 0, count: o.parts.count), cut = [Bool](repeating: false, count: o.parts.count)
            for f in o.frags {
                if abs(f.poly.mass.volume - o.partVolume[f.part]) < 1e-5 { whole[f.part] += 1 } else { cut[f.part] = true }
            }
            var touched = [Bool](repeating: Registry.drawAll, count: o.cells.count)
            for (i, p) in o.parts.enumerated() where cut[i] || whole[i] != 1 { touched[p.cell] = true }
            o.touched = touched
            o.draw = Draw(origin: o.origin, cells: o.cells, blocks: o.blocks, parts: o.parts, frags: o.frags,
                          mine: o.gone.indices.map { !o.gone[$0] && touched[$0] })
            for (k, c) in o.cells.enumerated() {
                if !o.gone[k] && touched[k] { cellObj[c] = o.id } else if cellObj[c] == o.id { cellObj[c] = nil }
            }
            // A box per part round what is left of it; a fence or wall post keeps its taller collision while its top is whole.
            var per = [(V3, V3)?](repeating: nil, count: o.parts.count)
            for f in o.frags {
                let (lo, hi) = WorldObjects.bounds(f.poly)
                if let b = per[f.part] { per[f.part] = (simd_min(b.0, lo), simd_max(b.1, hi)) } else { per[f.part] = (lo, hi) }
            }
            for c in o.cells { cellBoxes[c] = nil }
            for (i, p) in o.parts.enumerated() {
                guard var b = per[i], !o.gone[p.cell], touched[p.cell] else { continue }
                let c = o.cells[p.cell], blk = o.blocks[p.cell]
                let corner = V3(Float(c.x - o.origin.x), Float(c.y - o.origin.y), Float(c.z - o.origin.z))
                if Blocks.collide[Int(blk)] {
                    if b.1.y >= corner.y + p.hi.y - 0.01, Blocks.render[Int(blk)] == RenderType.connect.rawValue {
                        let tall = BlockRegistry.connectBoxes(Blocks.connectKind[Int(blk)], n: false, s: false, w: false, e: false, collision: true)
                        if let t = tall.first { b.1.y = max(b.1.y, corner.y + Float(t.y1) / 16) }
                    }
                    let seat = w.objectSeat(o.blocks[p.cell], c)
                    cellBoxes[c, default: []].append((b.0 + o.originV + V3(0, seat, 0), b.1 + o.originV + V3(0, seat, 0)))
                }
            }
            for (k, c) in o.cells.enumerated() where !o.gone[k] && touched[k] && cellBoxes[c] == nil && o.installed {
                cellBoxes[c] = []                       // (nothing of it left to meet)
            }
            for c in o.cells {
                guard let ch = w.chunkAt(c.x, c.z) else { continue }
                let sy = c.y >> 4
                guard sy >= 0 && sy < NSEC else { continue }
                ch.sections[sy].version += 1
                // (fences beside it read its cells' blocks: unchanged; a piece seated on ground stays in its own section)
            }
        }

        // The object comes apart for good: no longer drawn or met (its cells are set to air by the caller).
        func forget(_ w: World, _ o: Obj) {
            o.broken = true
            for c in o.cells {
                if cellObj[c] == o.id { cellObj[c] = nil }
                if owner[c] == o.id { owner[c] = nil }
                cellBoxes[c] = nil
            }
            var keys = Set<ChunkKey>()
            for c in o.cells { keys.insert(ChunkKey(x: floorDiv(c.x, CS), z: floorDiv(c.z, CS))) }
            for k in keys { byChunk[k]?.removeAll { $0 == o.id }; if byChunk[k]?.isEmpty == true { byChunk[k] = nil } }
            objects[o.id] = nil
            dirty = true
            for c in o.cells {
                guard let ch = w.chunkAt(c.x, c.z), c.y >= 0 && c.y < CH else { continue }
                ch.sections[c.y >> 4].version += 1
            }
        }

        // The objects a chunk's sections draw.
        func draws(_ c: Chunk) -> [Draw] {
            guard let ids = byChunk[ChunkKey(x: c.cx, z: c.cz)] else { return [] }
            return ids.compactMap { objects[$0]?.draw }
        }

        // MARK: Ray

        // For an installed object's cell: nil when the cell isn't one; .some(nil) when the ray passes its pieces there;
        // else the face normal met (a block normal, for the target) with `lastHit` set to the exact point.
        func rayCell(_ w: World, _ p: IVec3, _ origin: V3, _ dir: V3, maxDist: Float) -> IVec3?? {
            guard let id = cellObj[p], let o = objects[id], let k = o.cellIndex(p) else { return nil }
            let seat = w.objectSeat(o.blocks[k], p)
            let local = origin - o.originV - V3(0, seat, 0)
            guard let h = WorldObjects.ray(o.frags, take: { o.parts[$0.part].cell == k }, local, dir, maxDist: maxDist) else { return .some(nil) }
            let n = h.2
            lastHit = (p, origin + dir * h.1, n)
            let a = simd_abs(n)
            let bn = a.x >= a.y && a.x >= a.z ? IVec3(n.x > 0 ? 1 : -1, 0, 0) : (a.y >= a.z ? IVec3(0, n.y > 0 ? 1 : -1, 0) : IVec3(0, 0, n.z > 0 ? 1 : -1))
            return .some(bn)
        }

        // MARK: Save

        func saved() -> [Saved] {
            objects.values.filter { !$0.broken }.sorted { $0.id < $1.id }.map { o in
                Saved(id: o.id, k: o.kind.rawValue, o: [o.origin.x, o.origin.y, o.origin.z], cells: o.cells.flatMap { [$0.x, $0.y, $0.z] },
                      b: o.blocks.map { Blocks.key($0) }, parts: o.parts, cuts: o.cuts, dropped: o.dropped, gone: o.gone)
            }
        }

        // A world's saved objects, rebuilt from their cuts on the object worker (nothing flies).
        func load(_ w: World, _ list: [Saved]) {
            for s in list {
                guard s.o.count == 3, s.cells.count == s.b.count * 3, s.b.allSatisfy({ Blocks.has($0) }), !s.parts.isEmpty,
                      s.parts.allSatisfy({ $0.box.count == 6 && $0.cell >= 0 && $0.cell < s.b.count }) else { continue }
                let cells = (0..<s.b.count).map { IVec3(s.cells[$0 * 3], s.cells[$0 * 3 + 1], s.cells[$0 * 3 + 2]) }
                let origin = IVec3(s.o[0], s.o[1], s.o[2])
                let o = Obj(id: s.id, kind: Kind(rawValue: s.k) ?? .other, origin: origin, cells: cells, blocks: s.b.map { Blocks.id($0) },
                            parts: s.parts, support: [])
                o.cuts = s.cuts
                if s.dropped.count == cells.count { o.dropped = s.dropped }
                if s.gone.count == cells.count { o.gone = s.gone }
                objects[o.id] = o
                nextId = max(nextId, o.id + 1)
                loadSupport[o.id] = true
            }
        }
        // Saved objects whose supports (the ground round them) are read once their chunks are loaded.
        private var loadSupport: [Int: Bool] = [:]

        // Frame thread, each tick: saved objects whose chunks are all loaded now are rebuilt.
        func startLoaded(_ w: World) {
            guard !loadSupport.isEmpty else { return }
            for id in Array(loadSupport.keys) {
                guard let o = objects[id] else { loadSupport[id] = nil; continue }
                guard o.cells.allSatisfy({ w.chunkAt($0.x, $0.z) != nil }) else { continue }
                loadSupport[id] = nil
                let fresh = Obj(id: o.id, kind: o.kind, origin: o.origin, cells: o.cells, blocks: o.blocks, parts: o.parts,
                                support: Registry.supports(w, o.cells, origin: o.origin))
                fresh.cuts = o.cuts; fresh.dropped = o.dropped; fresh.gone = o.gone; fresh.leaving = o.leaving
                objects[id] = fresh
                schedule(fresh, replay: true)
            }
        }
    }
}

extension World {
    // P389: objects are cut out of in worlds that draw the detail stream (polygon worlds on the headset); elsewhere the
    // cells mine as before.
    var objectsOn: Bool { Mesher.detailMeshes && (SmoothTerrain.enabled || fieldTerrain) && frame == nil }

    // A model standing on a field world's natural ground is drawn seated on the drawn ground (GroundDrape); its object's
    // pieces are met there too.
    func objectSeat(_ b: BlockID, _ c: IVec3) -> Float {
        guard Blocks.render[Int(b)] == RenderType.model.rawValue, GroundDrape.seat[Int(b)] == 1 else { return 0 }
        return groundSeat(c.x, c.y, c.z)
    }

    func loadObjects() {
        guard let s = save, let d = try? Data(contentsOf: s.dir.appendingPathComponent("objects.json")),
              let list = try? JSONDecoder().decode([WorldObjects.Saved].self, from: d) else { return }
        objectReg.load(self, list)
    }

    func saveObjects() {
        // (P394: cells and drops a swap-in left for the next frames go first, so the save holds them)
        while !objectReg.later.isEmpty { objectReg.later.removeFirst()() }
        guard objectReg.dirty, let s = save else { return }
        objectReg.dirty = false
        SaveIO.storeJSON(objectReg.saved(), to: s.dir.appendingPathComponent("objects.json"))
    }
}
