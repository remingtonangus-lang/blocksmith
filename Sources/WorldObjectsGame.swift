import Foundation
import simd

// P389 in play: holding break on an object strikes it, a blow at a time; each blow cuts a chunk out where it landed
// (its size from the blow: the tool on that material, as the time a cell of it takes to mine), the chunk flies off as
// debris and the object is rebuilt without it on the object worker. What loses its hold falls; when enough of it is
// gone the rest comes down. A cell that has lost half its volume gives its drop; a cell with nothing left is air.
extension WorldObjects {
    // The objects that are struck as one piece: P389 step 1's census (questcheck --objectcensus, seed 13480747113613945685:
    // Stone Gulch, the nearest capital city and base), the ten the player meets most there. Groups counted: chest 40,
    // lantern or torch 34, cafe table 32, sign 23, parasol 23, lamp post 21, pumpkin or melon 13, fence post 8, barrel 8,
    // workblock 6 (next: crate 5, bell 3, cauldron 3; unnamed groups, 38, are not a kind).
    static var kinds: Set<Kind> = [.chest, .lantern, .table, .sign, .parasol, .lampPost, .gourd, .fencePost, .barrel, .workblock]
    // Below this share of its volume the rest of an object comes down.
    static let breakShare: Float = 0.4
    // More pieces than this (a long run of blows on one spot) and it comes down too.
    static let maxPieces = 400

    // Frame-thread cost of the blows (questcheck --scene objects).
    struct Stats {
        var strikeMs: [Double] = []        // the blow itself: finding the object, registering it, queueing the cut
        var installMs: [Double] = []       // a finished cut swapped in: pieces, collision, debris, drops
        var workMs: [Double] = []          // the cut on the object worker
        var laterMs: [Double] = []         // P394: a cell that went or a drop, on a frame after its swap-in
        var debris = 0, falls = 0, breaks = 0
        var phase: [String: Double] = [:]  // the worst ms per part of a swap-in (install, debris, cells, break)
        mutating func note(_ k: String, _ t0: UInt64) -> UInt64 {
            let t = DispatchTime.now().uptimeNanoseconds
            phase[k] = max(phase[k] ?? 0, Double(t - t0) / 1e6)
            return t
        }
    }
    // A blow's removed pieces thrown as debris bodies (the largest); the crumbs round the bite are dust.
    static let debrisPerBlow = 4
}

extension Game {
    // The blow's radius from how long a cell of this material takes to mine with what is in hand.
    func objectBlowRadius(_ secs: Float) -> Float {
        min(0.42, max(0.12, 0.34 * powf(0.6 / max(secs, 0.05), 0.25)))
    }

    // Break held at an object: true when the aim is at one (handled here, nothing mined).
    func strikeObject(breakNow: Bool, breakHeld: Bool, dt: Float) -> Bool {
        // (P477, Oct 27 19:25: "I'm in creative mode. I shouldn't have to wait for this barrel to break": creative breaks
        // an object's blocks at once, as any block)
        guard world.objectsOn, breakHeld, survival, let t = target else { objectStrikeWait = 0; return false }
        let t0 = DispatchTime.now().uptimeNanoseconds
        let reg = world.objectReg
        let p = t.hit
        var obj = reg.object(at: p) ?? reg.pendingObject(at: p)
        var group: WorldObjects.Group?
        if obj == nil {
            guard let g = WorldObjects.objectGroup(world, at: p, limit: 48),
                  WorldObjects.kinds.contains(WorldObjects.classify(world, g)) else { return false }
            group = g
        }
        let b = obj.map { o in o.cellIndex(p).map { o.blocks[$0] } ?? AIR } ?? world.builtBlock(p.x, p.y, p.z)
        let aqua = Enchant.level(.aquaAffinity, inventory.armor[0]) > 0
        let secs = Mining.breakSeconds(b, held, onGround: player.onGround || player.flying, inWater: player.headInWater && !aqua,
                                       mul: miningSpeedMul)
        mining = nil
        mineProgress = 0
        if secs.isInfinite { return true }
        swing = max(swing, 0.5)
        objectStrikeWait -= dt
        guard breakNow || objectStrikeWait <= 0 else { return true }
        objectStrikeWait = min(0.9, max(0.25, secs / 4))
        // Where the blow lands: the exact point on the object's pieces the ray met (World.raycast), else the cell's boxes.
        var at = hitPoint(t), nrm = V3(Float(t.normal.x), Float(t.normal.y), Float(t.normal.z))
        if let h = reg.lastHit, h.cell == p, simd_length(h.at - (player.eye + player.look * simd_dot(h.at - player.eye, player.look))) < 0.01 {
            at = h.at; nrm = h.normal
        }
        if simd_length_squared(nrm) < 0.5 { nrm = -player.look }
        let o = obj ?? reg.register(world, group!, kind: WorldObjects.classify(world, group!))
        obj = o
        let k = o.cellIndex(p) ?? 0
        let seat = world.objectSeat(o.blocks[k], p)
        let local = at - o.originV - V3(0, seat, 0)
        let seed = hash3(p.x, p.y &+ o.cuts.count &* 977, p.z, UInt32(truncatingIfNeeded: Int(clock * 60)))
        // (a small thing takes a smaller bite: a sign or a lantern isn't gone at the first blow)
        let size = cbrtf(max(o.parts.reduce(0) { $0 + $1.volume }, 1e-3))
        let r = max(0.07, objectBlowRadius(secs) * min(1, max(0.35, size * 1.2)))
        let cut = WorldObjects.Cut(c: [local.x, local.y, local.z], n: [nrm.x, nrm.y, nrm.z], r: r, s: seed)
        reg.strike(o, cut)
        swing = 1
        particles.dust(b, at: at + nrm * 0.05, count: 4, spread: 0.2)
        sfx(.hit(soundMat(b)), 0.8, at: at)
        objectStats.strikeMs.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        return true
    }

    // Each tick: finished cuts swapped in; what they took out and what lost its hold flies as debris; drops; breaks.
    func objectsTick() {
        let reg = world.objectReg
        // P394: one item a swap-in left for later (before this frame's swap-ins: a frame does one or the other's share).
        if !reg.later.isEmpty {
            let t0 = DispatchTime.now().uptimeNanoseconds
            reg.later.removeFirst()()
            objectStats.laterMs.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        }
        guard !reg.isEmpty else { return }
        reg.startLoaded(world)
        for r in reg.poll() {
            let t0 = DispatchTime.now().uptimeNanoseconds
            objectStats.workMs.append(r.workMs)
            guard let o = reg.objects[r.id], !o.broken else { continue }
            // (a cell changed under it while the cut was on the worker: the object is forgotten, its cells draw as blocks)
            if o.cells.indices.contains(where: { !o.gone[$0] && world.builtBlock(o.cells[$0].x, o.cells[$0].y, o.cells[$0].z) != o.blocks[$0] }) {
                reg.forget(world, o); continue
            }
            reg.install(world, o, r)
            if r.replay { continue }
            var tp = objectStats.note("install", t0)
            let ov = o.originV
            let blow = player.look
            var rng = UInt32(truncatingIfNeeded: r.id &* 7919 &+ r.applied &* 104729)
            func jitter() -> V3 {
                rng = rng &* 1664525 &+ 1013904223
                return V3(Float(rng & 0xFF) / 255 - 0.5, Float((rng >> 8) & 0xFF) / 255 - 0.5, Float((rng >> 16) & 0xFF) / 255 - 0.5)
            }
            func pieceOrigin(_ f: WorldObjects.Frag) -> V3 {
                let c = o.cells[o.parts[f.part].cell]
                return ov + V3(0, world.objectSeat(o.blocks[o.parts[f.part].cell], c), 0)
            }
            func layers(_ f: WorldObjects.Frag) -> [UInt16]? {
                let pt = o.parts[f.part], bi = Int(o.blocks[pt.cell])
                guard pt.boxIndex >= 0 && pt.boxIndex < Blocks.boxes[bi].count, Blocks.boxes[bi][pt.boxIndex].tex.count == 6 else { return nil }
                return Blocks.boxes[bi][pt.boxIndex].tex
            }
            // What the blow took out leaves along the face it struck, away from the swing.
            let cn = o.cuts.last.map { V3($0.n[0], $0.n[1], $0.n[2]) } ?? V3(0, 1, 0)
            let order = r.removed.indices.sorted { r.removed[$0].poly.mass.volume > r.removed[$1].poly.mass.volume }
            for (n, i) in order.enumerated() {
                let f = r.removed[i]
                if n >= WorldObjects.debrisPerBlow {
                    if n < WorldObjects.debrisPerBlow + 4 { particles.dust(o.blocks[o.parts[f.part].cell], at: pieceOrigin(f) + f.poly.center, count: 1, spread: 0.1) }
                    continue
                }
                let j = jitter()
                if debris.piece(f.poly, o.blocks[o.parts[f.part].cell], origin: pieceOrigin(f),
                                velocity: cn * (1.8 + j.y) + blow * 1.2 + j * 1.4 + V3(0, 1.4, 0), spin: j * 10, layers: layers(f)) {
                    objectStats.debris += 1
                }
            }
            // What lost its hold falls (a lamp's head over a post cut through).
            for f in r.fallen {
                let j = jitter()
                debris.piece(f.poly, o.blocks[o.parts[f.part].cell], origin: pieceOrigin(f), velocity: blow * 0.6 + j * 0.6, spin: j * 3, layers: layers(f))
            }
            if !r.fallen.isEmpty { objectStats.falls += 1 }
            tp = objectStats.note("debris", tp)
            // Drops by what is gone: a cell's drop once it has lost half its volume; a cell with nothing left is air.
            let left = o.volumes(o.frags)
            let at = o.cuts.last.map { ov + V3($0.c[0], $0.c[1], $0.c[2]) } ?? ov
            // P394: the drop and the cell's going are left to the next frames, one a frame (the object already draws and
            // meets nothing there: its pieces are gone); the hit's own frames keep under 1 ms.
            for k in o.cells.indices where !o.gone[k] {
                let b = o.blocks[k]
                if !o.dropped[k] && left[k] <= o.cellVolume[k] * 0.5 {
                    o.dropped[k] = true
                    reg.dirty = true
                    let tl = held.isEmpty ? ToolType.none : held.def.tool
                    if tl != .none && Blocks.hardness[Int(b)] > 0 { damageHeld(tl == .sword ? 2 : 1) }
                    if survival { reg.later.append { [weak self] in self?.objectDrop(b, at: at) } }
                }
                if left[k] <= 1e-5 && !o.leaving[k] {
                    o.leaving[k] = true
                    reg.later.append { [weak self, weak o] in
                        guard let self, let o, !o.broken, !o.gone[k], self.world.objectReg.objects[o.id] === o else { return }
                        let reg = self.world.objectReg
                        reg.editing = true
                        self.breakBlock(o.cells[k], o.blocks[k], drop: false, quiet: true)
                        reg.editing = false
                        reg.dropCell(o, k)
                        reg.refresh(self.world, o)
                    }
                }
            }
            tp = objectStats.note("cells", tp)
            // Enough gone: the rest comes down, and every cell left gives what it hasn't yet.
            let total = left.reduce(0, +)
            if total < o.totalVolume * WorldObjects.breakShare || o.frags.count > WorldObjects.maxPieces || o.gone.indices.allSatisfy({ o.gone[$0] || o.leaving[$0] }) {
                breakObject(o, at: at)
                _ = objectStats.note("break", tp)
            }
            objectStats.installMs.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        }
    }

    // The rest of an object comes down: its pieces fall as debris (the largest 24; the crumbs as dust), its cells go.
    func breakObject(_ o: WorldObjects.Obj, at: V3) {
        let reg = world.objectReg
        var tb = DispatchTime.now().uptimeNanoseconds
        let ov = o.originV
        let mid = (V3(Float(o.cells.map { $0.x }.min()!), Float(o.cells.map { $0.y }.min()!), Float(o.cells.map { $0.z }.min()!))
                   + V3(Float(o.cells.map { $0.x }.max()!), Float(o.cells.map { $0.y }.max()!), Float(o.cells.map { $0.z }.max()!)) + 1) * 0.5
        let order = o.frags.indices.sorted { o.frags[$0].poly.mass.volume > o.frags[$1].poly.mass.volume }
        var rng = UInt32(truncatingIfNeeded: o.id &* 31337)
        for (n, i) in order.enumerated() {
            let f = o.frags[i]
            let k = o.parts[f.part].cell
            let b = o.blocks[k]
            if n >= 24 { if n < 36 { particles.dust(b, at: ov + f.poly.center, count: 1, spread: 0.1) }; continue }
            rng = rng &* 1664525 &+ 1013904223
            let j = V3(Float(rng & 0xFF) / 255 - 0.5, Float((rng >> 8) & 0xFF) / 255 - 0.5, Float((rng >> 16) & 0xFF) / 255 - 0.5)
            let c = ov + f.poly.center
            let out = c - mid
            let pt = o.parts[f.part], bi = Int(b)
            let lay: [UInt16]? = pt.boxIndex >= 0 && pt.boxIndex < Blocks.boxes[bi].count && Blocks.boxes[bi][pt.boxIndex].tex.count == 6
                ? Blocks.boxes[bi][pt.boxIndex].tex : nil
            debris.piece(f.poly, b, origin: ov + V3(0, world.objectSeat(b, o.cells[k]), 0),
                         velocity: out * 1.2 + player.look * 0.8 + j * 1.2 + V3(0, 0.8, 0), spin: j * 5, layers: lay)
        }
        tb = objectStats.note("break: pieces", tb)
        if let k = o.cells.indices.first(where: { !o.gone[$0] }) { blockSound(audioBreakSound(o.blocks[k]), at: o.cells[k]) }
        for k in o.cells.indices where !o.gone[k] {
            reg.editing = true
            // (a crate's loot spills even when its drop was given already)
            if survival && o.dropped[k] && Blocks.key(Blocks.groupBase[Int(o.blocks[k])]) == BaseMaterials.crate { _ = crateEntity(o.cells[k]) }
            breakBlock(o.cells[k], o.blocks[k], drop: survival && !o.dropped[k], toPack: true, quiet: true)
            reg.editing = false
        }
        tb = objectStats.note("break: cells", tb)
        reg.forget(world, o)
        _ = objectStats.note("break: forget", tb)
        objectStats.breaks += 1
        _ = at
    }

    // A cell's drop (into the pack; what doesn't fit falls where the blow landed).
    func objectDrop(_ b: BlockID, at: V3) {
        for s in Mining.enchantedDrops(b, held) {
            let rest = inventory.add(s)
            if rest.count != s.count || rest.isEmpty { notePickup(s, s.count - (rest.isEmpty ? 0 : rest.count)); sfx(.pickup, 0.3) }
            if !rest.isEmpty { drops.spawn(rest, at: at, vel: V3(Rand.float(in: -1...1), 2, Rand.float(in: -1...1)), delay: 0.5, deliberate: true) }
        }
    }
}
