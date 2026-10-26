import Foundation
import simd

// P464 (Remington, Oct 25 20:16, manning a Greywall deck gun against a crash-landed Meridian frigate: "The rounds go
// through the frigate after a certain layer for some reason"): questcheck --shellthrough fires his manned deck-gun
// shells one after another at the same spot on a frigate's side, across the beam, and says where each one stopped
// (grid x along the beam: the hull spans 0 to sx) and how far into the hull the hole reaches. Passes while the first
// three stop inside the hull.
enum ShellThroughCheck {
    // P459: his dropship's autocannon shell (power 5.1) bursts inside a plank wall a villager stands 3 blocks in front
    // of, in the open; he dies (the burst saw nobody from inside the block). The wall is put back afterwards.
    static func burstInWall(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let mobs0 = g.mobs.mobs
        defer { g.mobs.mobs = mobs0; g.mobs.rebuildIndex() }
        let x = Int(floor(g.player.pos.x)) + 12, z = Int(floor(g.player.pos.z))
        let y = w.topY(x, z) + 1
        var old: [(Int, Int, Int, BlockID)] = []
        for dy in 0..<4 { for dz in -2...2 { old.append((x, y + dy, z + dz, w.block(x, y + dy, z + dz))); w.setBlock(x, y + dy, z + dz, Blocks.id("oak_planks")) } }
        for dy in 0..<3 { for dx in -4...(-1) { for dz in -1...1 where w.block(x + dx, y + dy, z + dz) != AIR {
            old.append((x + dx, y + dy, z + dz, w.block(x + dx, y + dy, z + dz))); w.setBlock(x + dx, y + dy, z + dz, AIR) } } }
        defer { for (bx, by, bz, id) in old.reversed() { w.setBlock(bx, by, bz, id) } }
        let v = Mob(.villager, at: V3(Float(x) - 2.5, Float(y), Float(z) + 0.5))
        g.mobs.mobs = [v]; g.mobs.rebuildIndex()
        let at = V3(Float(x) + 0.3, Float(y) + 1.2, Float(z) + 0.5)          // 0.3 into the wall, flying east
        Explosion.explode(at: at, power: 5.1, game: g, breakBlocks: false, along: V3(1, -0.1, 0))
        check(v.health <= 0, "shellthrough: a dropship burst 0.3 into a plank wall kills a villager 3 blocks in front (health \(v.health))")
    }

    // P459: a cannon with three Gun Barrels on from its muzzle fires a shell 2.2 times as hard and 1.36 times as fast as
    // a bare cannon's, from the far end of the tubes; a tube laid across the line doesn't count.
    static func gunBarrels(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        func gun(_ tubes: Int, across: Bool = false) -> (Ship, Shell?) {
            let gr = ShipGrid(sx: 11, sy: 3, sz: 11)
            for z in 0..<11 { for x in 0..<11 { gr.set(x, 0, z, Blocks.id("iron_block")) } }
            gr.set(5, 1, 5, Blocks.id("ship_cannon"))
            let s = Ship(id: 900_000 + tubes * 2 + (across ? 1 : 0), grid: gr)
            s.pos = g.player.pos + V3(0, 60, 0)
            s.rebuild()
            if let (c, d) = s.cannons.first {
                let tube = Blocks.id("ship_gun_barrel")
                let alongZ = abs(d.z) > 0.5                            // north/south tubes lie along z, west/east along x
                let t: BlockID = alongZ != across ? tube : tube + 2
                for k in 0..<tubes { let q = c + d * Float(k + 1); gr.set(Int(floor(q.x)), 1, Int(floor(q.z)), t) }
                s.rebuild()
            }
            let n0 = w.ships.shells.count
            _ = w.ships.fire(s, pitch: 0, game: nil)
            let sh = w.ships.shells.count > n0 ? w.ships.shells.last : nil
            w.ships.shells.removeLast(w.ships.shells.count - n0)
            return (s, sh)
        }
        let (bare, b0) = gun(0), (long, b3) = gun(3), (cross, _) = gun(3, across: true)
        let p = (b3?.power ?? 0) / max(0.01, b0?.power ?? 1)
        let v = simd_length(b3?.vel ?? .zero) / max(0.01, simd_length(b0?.vel ?? V3(1, 0, 0)))
        let out = simd_length((b3?.pos ?? .zero) - long.toWorld(long.cannons.first?.0 ?? .zero))
        check(bare.cannonLength == [0] && long.cannonLength == [3] && cross.cannonLength == [0] && abs(p - 2.2) < 0.01 && abs(v - 1.36) < 0.01 && out > 3.5,
              String(format: "P459 gun barrels: tubes counted bare %@, three in line %@, three across %@; shell x%.2f burst, x%.2f speed, leaves %.1f blocks out",
                     "\(bare.cannonLength)", "\(long.cannonLength)", "\(cross.cannonLength)", p, v, out))
    }

    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        guard g.dim.dim == .overworld else { check(false, "shellthrough: needs the overworld"); return }
        let w = g.world
        let home = g.player.pos
        let n0 = w.ships.list.count
        w.ships.spawnCapital("capfrigate", home: IVec3(Int(floor(home.x)), 0, Int(floor(home.z)) + 260), yaw: 0, region: nil, sync: true)
        guard let s = w.ships.list.dropFirst(n0).first(where: { $0.role == "capfrigate" }) else {
            check(false, "shellthrough: the Meridian frigate spawns"); return
        }
        defer { w.ships.remove(s); w.ships.capState.removeValue(forKey: s.id) }
        s.vel = .zero; s.angVel = .zero
        w.ships.pointHull(s, pitch: 0)
        let gr = s.grid
        let row = V3(-6, 16.5, 80.5)                        // main deck height, mid-ships, outside the port side
        let dir = s.dirToWorld(V3(1, 0, 0))
        var stops: [String] = []
        var through = 0, firstThrough = -1
        for k in 0..<10 {
            g.arms.slugs.removeAll()
            var sl = Slug(pos: s.toWorld(row), vel: dir * HeavyTurret.speed, kind: .shell, damage: 0, fromPlayer: true,
                          shooter: nil, by: "Player", life: 12, gravity: 0)
            HeavyTurret.arm(&sl)
            sl.power = HeavyTurret.mannedPower; sl.breach = HeavyTurret.mannedBreach
            g.arms.spawn(sl)
            var last = sl.pos
            for _ in 0..<120 {
                guard let cur = g.arms.slugs.first(where: { !$0.dead }) else { break }
                last = cur.pos
                g.arms.update(1.0 / 60, g)
                for _ in 0..<2 { w.ships.update(1.0 / 120, game: g) }
                s.vel = .zero; s.angVel = .zero
            }
            let lx = s.toLocal(last).x
            stops.append(String(format: "%.0f", lx))
            if lx > Float(gr.sx) { through += 1; if firstThrough < 0 { firstThrough = k } }
        }
        // The hole: solid cells left along the line.
        var solid = 0
        for x in 0..<gr.sx where Blocks.collide[Int(gr.get(x, 16, 80))] { solid += 1 }
        // Found: each shell stops on the hull and tears about four blocks in; the fourth blows out the far side, and
        // later shells fly through the tunnel the first ones tore (a real hole, not shells passing through plate).
        burstInWall(g, check)
        gunBarrels(g, check)
        check(firstThrough < 0 || firstThrough >= 3,
              "shellthrough: 10 manned shells at one spot on a frigate's side (beam 0-\(gr.sx)) stopped at x \(stops.joined(separator: ", ")); \(through) flew out the far side (first: shot \(firstThrough + 1)); \(solid) solid cells left on the line")
    }
}
