import Foundation
import simd

// (Remington, Oct 31 09:34, the frigate's gun: "the round goes through buildings without damaging them, just spawning a
// crater where it was aimed"; Oct 30 20:28-20:29, "the whole thing should just fall too because of physics"... "there is
// a gravity system, just doesn't work all the time"): a shot that strikes past the active distance, where chunks are
// shells (ChunkShells: no blocks, only their meshes and heights). A Tidebreaker slug and a rail slug are fired down at a
// shell chunk's ground from 40 blocks up: each must stop at that ground (it read as air and the shot flew on
// down through it), its blocks must come back on the workers (not on the frame thread) while the shot waits, the blast
// must change blocks there, and the world must run round the strike for a while (World.heat).
extension MainGunTests {
    static func farStrike(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let home = g.player.pos
        let active0 = w.activeDistance
        w.activeDistance = 4
        defer {
            w.activeDistance = active0
            w.hotZones.removeAll()
            w.ships.shells.removeAll(); w.ships.shockwaves.removeAll(); w.ships.pendingCraters.removeAll(); w.ships.pendingAlong.removeAll()
        }
        _ = w.loadSync(center: home, radius: 9)
        let pcx = floorDiv(Int(floor(home.x)), CS), pcz = floorDiv(Int(floor(home.z)), CS)
        for (n, kind) in [(0, 3), (1, 1)] {
            // A chunk 7 east (n = 0) or 7 west (n = 1) of the player, past the active distance (4 chunks) and the 2 more
            // that keep their blocks, made a shell with the chunks round it.
            let k = ChunkKey(x: pcx + (n == 0 ? 7 : -7), z: pcz)
            guard let c = w.chunks[k], !c.hollow else { check(false, "far strike: chunk \(k.x) \(k.z) loaded"); continue }
            // The column nearest the chunk's middle whose top is solid ground ten deep (not a tree's crown over air, a
            // plant or water), chosen while its blocks are still there.
            var col = (8, 8), best = Int.max
            for lz in 2..<14 { for lx in 2..<14 {
                let h = Int(c.height[lx + lz * CS])
                let d = (lx - 8) * (lx - 8) + (lz - 8) * (lz - 8)
                guard d < best, h > 12 else { continue }
                let solid = (h - 9...h).allSatisfy { y in
                    let b = w.block(k.x * CS + lx, y, k.z * CS + lz)
                    return Blocks.opaque[Int(b)] && !CapitalBase.isLeaf(b) && !CapitalBase.isLog(b)
                }
                if solid { col = (lx, lz); best = d }
            } }
            for dz in -2...2 { for dx in -2...2 {
                if let o = w.chunks[ChunkKey(x: k.x + dx, z: k.z + dz)], !o.hollow, !o.modified, !o.fieldDirty { o.holdData = 0; w.hollow(o, ChunkKey(x: o.cx, z: o.cz)) }
            } }
            let x = k.x * CS + col.0, z = k.z * CS + col.1
            let top = Int(c.height[col.0 + col.1 * CS])
            let aim = V3(Float(x) + 0.5, Float(top) + 1, Float(z) + 0.5)
            // (straight down the column: nothing stands above its top, so nothing else can stop the shot first)
            let from = aim + V3(0, 40, 0)
            let dir = simd_normalize(aim - from)
            let at0 = World.refilledAtOnce, impacts0 = MainGun.impacts
            let hollow0 = c.hollow
            let sh = Shell(pos: from, vel: dir * 700, owner: -7, power: kind == 3 ? 12 : 10)
            sh.gravity = 0; sh.kind = kind; sh.life = 3.5
            w.ships.shells = [sh]
            var probe = ShipBlockReader(w)
            let seen = probe.get(x, top, z)              // (solid ground: stone, or grass grown over it since the world began)
            var hitAt: V3? = nil, waited = 0, frames = 0, waitMs = 0.0
            // The cells within 3 of the aim, as generated (read once the shell's blocks are back).
            var box: [IVec3] = []
            // (a rail slug bores on along its line, about a block and a half across, before it bursts further in)
            if kind == 1 {
                for t in 0..<10 { let q = aim + dir * Float(t); let b = IVec3(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z))); if !box.contains(b) { box.append(b) } }
            } else {
                for dy in -3...3 { for dz in -3...3 { for dx in -3...3 { box.append(IVec3(x + dx, top + dy, z + dz)) } } }
            }
            var before: [BlockID]? = nil
            while frames < 400 {
                let t0 = CFAbsoluteTimeGetCurrent()
                w.update(center: home)
                let p0 = sh.pos
                if before == nil && !c.hollow && w.ships.shells.contains(where: { $0 === sh }) { before = box.map { w.block($0.x, $0.y, $0.z) } }
                w.ships.updateShells(1.0 / 72, game: g)
                if sh.parked >= 0 { waited += 1 }
                if !w.ships.shells.contains(where: { $0 === sh }) && hitAt == nil { hitAt = p0 }
                frames += 1
                if hitAt != nil && w.ships.shockwaves.allSatisfy({ $0.crater?.done ?? true }) { break }
                usleep(2000)
                if sh.parked >= 0 { waitMs += (CFAbsoluteTimeGetCurrent() - t0) * 1000 }
            }
            let removed = before.map { b in zip(b, box.map { w.block($0.x, $0.y, $0.z) }).filter { $0 != AIR && $1 == AIR }.count } ?? -1
            let off = kind == 3 ? simd_length(MainGun.lastImpact - aim) : 0
            let name = kind == 3 ? "a Tidebreaker slug" : "a rail slug"
            check(hollow0 && seen != AIR && Blocks.collide[Int(seen)] && hitAt != nil && off < 4 && removed >= (kind == 3 ? 20 : 5) && (kind != 3 || MainGun.impacts == impacts0 + 1),
                  String(format: "far strike: %@ fired at a shell chunk's ground stops on it and breaks it (%d of the %d cells %@ broken; impact %.1f blocks off; %d frames, %.0f ms, waiting for its blocks; a shell reads %@ under its heights)",
                         name, removed, box.count, kind == 3 ? "within 3 of the aim" : "along its line in from the aim", off, waited, waitMs, Blocks.key(seen)))
            check(!c.hollow && World.refilledAtOnce == at0,
                  "far strike: \(name)'s chunk got its blocks back on the workers (\(World.refilledAtOnce - at0) on the frame thread)")
            check(w.hot(aim) && !w.hot(home + V3(0, 0, 200)) && w.activeHere(aim) && (w.chunks[k]?.holdData ?? 0) > CFAbsoluteTimeGetCurrent() + 10,
                  "far strike: the world runs round \(name)'s strike past the active distance for a while, and its chunks keep their blocks")
            w.hotZones.removeAll()
        }
    }
}
