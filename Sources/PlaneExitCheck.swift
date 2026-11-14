import Foundation
import simd

// Nov 13 playtest (12:32:39, Ash Vault 3231 -33 -3041, "Can't get out of the plane once I eject from it or exit from
// it"): a Salvaged Fighter's seat is a one-block cockpit sealed under its canopy, so leaving the helm left him shut in it,
// and the use press that fired his gun next (8 blocks from a plane's helm takes it) put him back at the stick. Landed,
// leaving the helm sets him on the ground beside it; in the air he bails out over the canopy, slowed; and for a moment
// after, no use press takes that helm again (ShipPlay.leaveHelm, commandeerable; BS_OLDPLANEEXIT=1: as before).
enum PlaneExitCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, ships = w.ships
        let pos0 = g.player.pos, flying0 = g.player.flying
        // An open ground column near him with room for the plane (15 wide, 16 long).
        var spot: V3?
        search: for r in stride(from: 12, through: 40, by: 4) { for (dx, dz) in [(0, r), (r, 0), (0, -r), (-r, 0)] {
            let x = Int(floor(pos0.x)) + dx, z = Int(floor(pos0.z)) + dz
            guard let c = w.chunkAt(x, z) else { continue }
            let y = Int(c.height[mod(x, CS) + mod(z, CS) * CS])
            guard y > 4, y < CH - 40, Blocks.collide[Int(w.block(x, y, z))], !Blocks.isLiquid(w.block(x, y, z)) else { continue }
            var clear = true
            for ex in -8...8 { for ez in -9...10 where w.solidAt(x + ex, y + 2, z + ez) || w.solidAt(x + ex, y + 4, z + ez) { clear = false } }
            if clear { spot = V3(Float(x) + 0.5, Float(y + 1), Float(z) + 0.5); break search }
        } }
        guard let at = spot else { check(false, "plane exit: open ground for a Salvaged Fighter near \(Int(pos0.x)) \(Int(pos0.z))"); return }
        defer { g.player.pos = pos0; g.player.vel = .zero; g.player.flying = flying0; ships.aboard = nil; ships.riderShip = nil
            g.helmLeft = nil; g.helmLeftT = 0; g.effects.remove(.slowFalling); g.player.parachute = false }

        // Landed: off the helm he stands on the ground beside it, out of its frame, and the next use doesn't take it back.
        let fp = ships.spawn(AshWrecks.salvagedFighter(), at: at + V3(0, 1.2, 0), yaw: 0.6, name: AshWrecks.fighterName, role: "capplane")
        g.startPiloting(fp)
        let atHelm = ships.pilot === fp
        g.leaveHelm()
        let p = g.player.pos
        let out = ships.boundsDistance(fp, p) > 0.2 || p.y >= fp.worldMax.y - 0.1
        // (on the ground: a solid cell under the feet, or one a block down where a field world's drawn ground stands up to a
        // block over its cell's foot: dismountSpot's own rule; not bailed out)
        let gx = Int(floor(p.x)), gz = Int(floor(p.z))
        let bailed = g.effects.has(.slowFalling) || g.player.parachute
        let ground = (w.solidAt(gx, Int(floor(p.y - 0.05)), gz) || w.solidAt(gx, Int(floor(p.y - 1.05)), gz)) && !bailed
        let retake = g.commandeerable() === fp
        check(atHelm && ships.aboard == nil && out && ground && !retake,
              String(format: "plane exit: off a landed Salvaged Fighter's helm he stands on the ground beside it (%.1f %.1f %.1f, aboard %@, clear of the hull %@, on ground %@, bailed out %@), the next use doesn't retake it (%@)",
                     p.x, p.y, p.z, ships.aboard == nil ? "no" : "yes", out ? "yes" : "no", ground ? "yes" : "no",
                     bailed ? "yes" : "no", retake ? "it does" : "no"))
        // A moment later its helm can be taken again from beside it.
        g.helmLeftT = 0.01
        g.shipPlayerUpdate(1 / 30, MoveInput())
        check(g.commandeerable() === fp, "plane exit: 1.5 s later the landed plane's helm is his to take again from beside it")
        ships.remove(fp, turrets: false)

        // In the air: he bails out over the canopy, away from the hull and its frame, falling slowly.
        let ap = ships.spawn(AshWrecks.salvagedFighter(), at: at + V3(0, 30, 0), yaw: -0.4, name: AshWrecks.fighterName, role: "capplane")
        ap.vel = V3(0, 0, -20)
        g.startPiloting(ap)
        g.leaveHelm()
        let q = g.player.pos
        let clear = !w.ships.list.contains { s in s === ap && ships.boundsDistance(s, q) < 0.2 && q.y < s.worldMax.y }
        let chute = Parachute.old ? g.effects.has(.slowFalling) : g.player.parachute
        check(ships.aboard == nil && ships.riderShip == nil && clear && q.y > ap.worldMax.y - 0.5 && chute && g.player.vel.z < -10,
              String(format: "plane exit: off a flying Salvaged Fighter's helm he bails out over it (%.1f over its top, carried on at %.0f b/s, parachute open %@, aboard %@)",
                     q.y - ap.worldMax.y, -g.player.vel.z, chute ? "yes" : "no", ships.aboard == nil ? "no" : "yes"))
        ships.remove(ap, turrets: false)
    }
}
