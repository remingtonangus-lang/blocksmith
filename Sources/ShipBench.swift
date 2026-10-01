import Foundation
import Metal
import simd

// Bench scene "ships": costs of moving block structures.
//   ships.spawn_frigate_ms      building a 48-block frigate (+ turrets) from its blueprint (main thread)
//   ships.mesh_frigate_ms       meshing the whole frigate grid on one thread (normally a background job)
//   ships.edit_ms               one block placed on a ship (grid + mass properties; the remesh is background)
//   ships.tick_ms               game tick with a frigate and a siege carriage under way (mean / p95)
//   ships.physics_ms            the ship physics share of that (all substeps of a frame)
//   ships.collide_us            one mob-sized World.collides query next to a ship (ship boxes included)
//   ships.collide_far_us        the same query away from ships (should cost what it did before ships)
extension Bench {
    static func turrets(_ m: ShipManager, _ s: Ship) -> Int { m.turrets(of: s).reduce(0) { $0 + $1.blockCount } }

    static func ships(_ device: MTLDevice, _ seed: UInt64) {
        let (world, game, pos) = setup(device, seed, rd: 6)
        _ = world.loadSync(center: pos, radius: 6)
        let ships = world.ships
        ships.encounters = false
        let gx = Int(floor(pos.x)), gz = Int(floor(pos.z))
        let ground = world.topY(gx, gz)

        var t = now
        let fg = ships.spawnVessel("frigate", home: IVec3(gx, max(ground, SEA) + 40, gz - 20), game: game)
        put("ships.spawn_frigate_ms", (now - t) * 1000)
        t = now
        _ = ShipMesh.build(sx: fg.grid.sx, sy: fg.grid.sy, sz: fg.grid.sz, blocks: fg.grid.blocks, only: nil)
        put("ships.mesh_frigate_ms", (now - t) * 1000)
        let cg = ships.spawnVessel("carriage", home: IVec3(gx + 30, ground + 1, gz + 10), game: game)

        // Edits: place and remove one block on the frigate's deck, ten times.
        var edits: [Double] = []
        let deck = IVec3(fg.grid.sx / 2, 5, fg.grid.sz / 2)
        for i in 0..<10 {
            let a = now
            ships.setBlock(fg, deck + IVec3(0, 1, 0), i % 2 == 0 ? PLANKS : AIR)
            edits.append((now - a) * 1000)
        }
        put("ships.edit_ms", dist(edits), "mean,max")

        // Ticks with both vessels under way (crews steering).
        let dt = 1.0 / 60
        var ticks: [Double] = [], phys: [Double] = []
        for i in 0..<360 {
            game.player.pos = pos + V3(0, 30, 0)
            let a = now
            game.tick(dt)
            if i >= 60 { ticks.append((now - a) * 1000); phys.append(ships.stepMs) }
        }
        put("ships.tick_ms", dist(ticks), "mean,p95,max")
        put("ships.physics_ms", dist(phys), "mean,p95")

        // Collision queries: mob-sized boxes on the carriage's deck and far from any ship.
        func queries(_ c: V3) -> Double {
            let n = 2000
            var hits = 0
            let a = now
            for i in 0..<n {
                let p = c + V3(Float(i % 7) * 0.3, 0, Float(i % 5) * 0.3)
                if world.collides(p - V3(0.3, 0, 0.3), p + V3(0.3, 1.8, 0.3)) { hits += 1 }
            }
            _ = hits
            return (now - a) / Double(n) * 1_000_000
        }
        // Docking the frigate into the world and assembling it again from its helm: main-thread time, then how long
        // the background remesh of the touched sections takes.
        func remeshWait(_ around: V3) -> Double {
            let a = now
            while now - a < 20 {
                world.update(center: around)
                if !unmeshed(world, around) { break }
                usleep(2_000)
            }
            return now - a
        }
        fg.vel = .zero; fg.angVel = .zero
        let helmWorld = fg.helm.map { fg.toWorld(V3(Float($0.x), Float($0.y), Float($0.z)) + 0.5) }
        let blocks = fg.blockCount + turrets(ships, fg)
        t = now
        _ = ships.disassemble(fg, game: game)
        put("ships.dock_ms", (now - t) * 1000)
        put("ships.dock_remesh_s", remeshWait(pos))
        // (docking snaps to a quarter turn, so look for the helm around where it was)
        var helmCell: IVec3?
        if let hw = helmWorld {
            search: for r in 0...12 { for dy in -2...2 { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
                let c = IVec3(Int(floor(hw.x)) + dx, Int(floor(hw.y)) + dy, Int(floor(hw.z)) + dz)
                if ShipParts.kinds[Int(world.rawBlock(c.x, c.y, c.z))] == .helm { helmCell = c; break search }
            } } } }
        }
        if let hc = helmCell {
            t = now
            let (again, _) = ships.assemble(at: hc, game: game)
            put("ships.assemble_ms", (now - t) * 1000)
            put("ships.assemble_remesh_s", remeshWait(pos))
            print("bench ships: docked \(blocks) blocks in \(f(metrics["ships.dock_ms"] ?? 0)) ms (world remesh \(f(metrics["ships.dock_remesh_s"] ?? 0)) s), assembled \(again?.blockCount ?? 0) in \(f(metrics["ships.assemble_ms"] ?? 0)) ms")
        }
        put("ships.collide_us", queries(cg.toWorld(V3(Float(cg.grid.sx) / 2, Float(cg.grid.sy) - 0.5, Float(cg.grid.sz) / 2))))
        put("ships.collide_far_us", queries(pos + V3(200, 0, 200)))
        print("bench ships: frigate \(fg.blockCount) blocks spawn \(f(metrics["ships.spawn_frigate_ms"] ?? 0)) ms, mesh \(f(metrics["ships.mesh_frigate_ms"] ?? 0)) ms; "
              + "tick \(f(dist(ticks).mean)) ms (p95 \(f(dist(ticks).p95))), physics \(f(dist(phys).mean)) ms; "
              + "collide \(f(metrics["ships.collide_us"] ?? 0)) us near ships, \(f(metrics["ships.collide_far_us"] ?? 0)) us far; \(ships.list.count) ships")
    }
}
