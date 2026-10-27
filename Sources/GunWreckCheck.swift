import Foundation
import simd

// P459's check (questcheck --gunwreck), P473's since Oct 27: a gun mount or a vehicle destroyed stays as its burnt hulk
// (Hulks) with a few fittings flying off, and a shot-up Salvaged Fighter stays its model, burnt, its broken-off pieces
// debris rather than hulls of blocks.
enum GunWreckCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        Hulks.tick(g, 0)
        let w = g.world
        let at = g.player.pos + V3(6, 0, 0)
        for (name, key) in [("the Capital's heavy gun", "deck_gun"), ("a light gun", "deck_gun:light"), ("a Greywall gun", "deck_gun@grey")] {
            guard let m = Mob.structureMob(key, at: at) else { check(false, "gunwreck: \(key) makes a gun"); continue }
            g.debris.tick(1 / 60, world: w)            // (a new frame: the field takes 64 new pieces a frame)
            let ox = Int(floor(m.pos.x)), oy = Int(floor(m.pos.y)), oz = Int(floor(m.pos.z))
            var before: [(IVec3, BlockID)] = []
            for z in (oz - 12)...(oz + 24) { for y in oy...(oy + 5) { for x in (ox - 24)...(ox + 24) { before.append((IVec3(x, y, z), w.block(x, y, z))) } } }
            let d0 = g.debris.bodies.count, w0 = AshArmy.gunsWrecked
            m.health = 0
            g.mobDied(m)
            var put = 0
            for (p, b) in before where w.block(p.x, p.y, p.z) != b { put += 1; w.setBlockAsync(p.x, p.y, p.z, b) }
            let pieces = g.debris.bodies.count - d0
            let hulk = Hulks.mobs.contains { $0 === m }
            check(AshArmy.gunsWrecked == w0 + 1 && hulk && pieces >= 2 && pieces <= 10 && put == 0,
                  "gunwreck: \(name) destroyed stays as its hulk (\(hulk)), \(pieces) fittings fly off, \(put) blocks put down (\(m.factionValue.name))")
            Hulks.mobs.removeAll { $0 === m }
        }
        // A Cinder Tank brewed up: its hulk, burnt, solid to bump into, smoking; gone once he is far off.
        let tk = Mob(.ashTank, at: g.player.pos + V3(-10, 0, 0))
        tk.ashSetup()
        g.debris.tick(1 / 60, world: w)
        let d0 = g.debris.bodies.count
        g.ashUnitDied(tk)
        let pieces = g.debris.bodies.count - d0
        g.mobs.corpseTick(1 / 60, g)
        Hulks.tick(g, 1 / 60)
        let boxed = w.bodyBoxes.contains { $0.0.x <= tk.pos.x && $0.1.x >= tk.pos.x && $0.0.z <= tk.pos.z && $0.1.z >= tk.pos.z && $0.1.y > tk.pos.y + 0.8 }
        let parts = mobModelParts(tk)
        let burnt = parts.indices.prefix(40).filter { simd_length(Hulks.burn(parts[$0].color, tk, $0)) < simd_length(parts[$0].color) * 0.95 }.count
        check(Hulks.mobs.contains { $0 === tk } && tk.hulk && boxed && pieces >= 2 && pieces <= 12 && burnt >= 20,
              "gunwreck: a Cinder Tank destroyed stays as its hulk, solid (\(boxed)), \(burnt) of its first 40 parts burnt, \(pieces) fittings fly off")
        let keep = tk.pos
        tk.pos.x += Hulks.leave + 30
        Hulks.tick(g, 1 / 60)
        check(!Hulks.mobs.contains { $0 === tk }, "gunwreck: the hulk is gone once he is \(Int(Hulks.leave)) blocks off")
        tk.pos = keep
        // A Salvaged Fighter shot up past a sixth of its blocks: still its model (burnt), no hulls of blocks broken off.
        let fp = w.ships.spawn(AshWrecks.salvagedFighter(), at: g.player.pos + V3(0, 6, 18), yaw: 0, name: AshWrecks.fighterName, role: "capplane")
        fp.initialBlocks = fp.blockCount
        AshWrecks.syncSkins(w)
        let ships0 = w.ships.list.count
        // The wing tips and the tail shot away (the cells farthest out from the hull's middle), a third of its blocks.
        var cells: [(IVec3, Float)] = []
        let mid = V3(Float(fp.grid.sx), Float(fp.grid.sy), Float(fp.grid.sz)) * 0.5
        for y in 0..<fp.grid.sy { for z in 0..<fp.grid.sz { for x in 0..<fp.grid.sx where fp.grid.get(x, y, z) != AIR {
            let dx = abs(Float(x) + 0.5 - mid.x), dz = abs(Float(z) + 0.5 - mid.z)
            cells.append((IVec3(x, y, z), dx + 0.3 * dz))
        } } }
        let gone = Set(cells.sorted { $0.1 > $1.1 }.prefix(cells.count / 3).map { $0.0 })
        g.debris.tick(1 / 60, world: w)
        let f0 = g.debris.bodies.count
        w.ships.removeCells(fp, gone, chipped: [], center: fp.pos, power: 2, game: g)
        AshWrecks.syncSkins(w)
        let skin = AshWrecks.skinMobs.first { $0.wreck == 5 }
        let hulls = w.ships.list.count - ships0
        check(skin != nil && skin?.hulk == true && fp.hidden && hulls <= 0 && g.debris.bodies.count > f0,
              "gunwreck: a Salvaged Fighter shot up (\(fp.blockCount) of \(fp.initialBlocks) blocks left) stays its model, burnt (\(skin?.hulk == true)), "
              + "\(max(0, hulls)) hulls of blocks broken off, \(g.debris.bodies.count - f0) pieces of debris")
        w.ships.remove(fp, turrets: false)
        Hulks.mobs.removeAll()
    }
}
