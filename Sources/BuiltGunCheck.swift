import Foundation
import simd

// P507 (Nov 1 12:36:14-12:36:30, a gun he built on a hill, a Turret Ring under a row of Medium Gun Barrels: "This is kind
// of what I had in mind by a gun... I guess we need a computer attached to it also to make it operational... Then you
// need to use the computer"): questcheck --builtgun builds his gun on a platform in the sky (a deck of planks, a Turret
// Ring, six Medium Gun Barrels laid out over it from the ring, no cannon block) with a Command Console on the deck, uses
// the console (he takes the gun), turns it to his look, fires it (a medium shell leaves the far end of the barrels) and
// checks the gun stands where he built it through three seconds (a row of barrels over a one-block ring tipped over).
enum BuiltGunCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, ships = w.ships
        let base = IVec3(Int(floor(g.player.pos.x)) + 6, 200, Int(floor(g.player.pos.z)) + 6)
        _ = w.loadSync(center: V3(Float(base.x), Float(base.y), Float(base.z)), radius: 2)
        let deck = Blocks.id("oak_planks"), ring = Blocks.id("ship_turret_ring"), console = Blocks.id("command_console")
        let tube = Blocks.id("gun_barrel_medium[south]")
        for dz in -2...2 { for dx in -2...2 { w.setBlock(base.x + dx, base.y, base.z + dz, deck) } }
        w.setBlock(base.x, base.y + 1, base.z, ring)
        for k in 0..<6 { w.setBlock(base.x, base.y + 2, base.z - k, tube) }       // (over the ring and on out north)
        let at = IVec3(base.x + 2, base.y + 1, base.z + 2)
        w.setBlock(at.x, at.y, at.z, console)
        g.player.pos = V3(Float(at.x) + 0.5, Float(at.y), Float(at.z) + 1.6)
        let before = ships.list.count
        let used = g.builtGunUse(at)
        guard used, let s = ships.pilot, ships.list.count > before else {
            check(false, "builtgun: using the console beside his gun (a ring and six medium barrels) takes it (used \(used), piloting \(ships.pilot != nil))"); return
        }
        defer { if ships.pilot != nil { g.leaveHelm() }; _ = ships.disassemble(s, game: g) }
        let guns = ships.turrets(of: s)
        let barrels = guns.first?.cannonLength.first ?? 0, cal = guns.first?.cannonCalibre.first ?? 0
        check(s.helm != nil && s.emplacement && guns.count == 1 && barrels == 6 && cal == 2,
              "builtgun: the console works his gun: helm at the computer \(s.helm != nil), standing gun \(s.emplacement), \(guns.count) turret (want 1), its barrels \(barrels) of calibre \(cal) (want 6, medium 2)")
        guard let t = guns.first else { return }
        // Three seconds at the gun, looking east: the turret turns to it and the hull stays put.
        let p0 = s.pos
        g.player.yaw = -Float.pi / 2; g.player.pitch = 0
        for _ in 0..<180 { g.tick(1.0 / 60) }
        let moved = simd_length(s.pos - p0)
        let aim = t.dirToWorld(t.cannons.first?.1 ?? V3(0, 0, -1))
        let shellsBefore = ships.shells.count
        let fired = ships.fire(s, pitch: 0, game: g)
        let shell = ships.shells.count > shellsBefore ? ships.shells.last : nil
        check(moved < 0.05 && fired > 0 && shell != nil,
              String(format: "builtgun: it stands where he built it (moved %.2f in 3 s), its barrels point %.2f %.2f %.2f after he looked east, and it fires (%d shell%@, power %.1f)",
                     moved, aim.x, aim.y, aim.z, fired, fired == 1 ? "" : "s", shell?.power ?? 0))
    }
}
