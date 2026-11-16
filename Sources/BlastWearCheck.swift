import Foundation
import simd

// Ledger 172 (Nov 15 evening, at the crawler's helm: "Explosion's still taking too long to register... Two seconds"):
// a blast inside a vehicle's wear zone goes ahead of the mesh queue like any blast; a rut there still waits.
enum BlastWearCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let p = g.player.pos + V3(40, 0, 0)
        _ = w.loadSync(center: p, radius: 2)
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        let y = w.topY(x, z)
        let key = ChunkKey(x: floorDiv(x, CS), z: floorDiv(z, CS))
        guard let c = w.chunks[key] else { check(false, "blast wear: no chunk at the site"); return }
        let frame0 = World.frameNow
        defer { World.frameNow = frame0 }
        World.frameNow = max(frame0, 1000)
        World.wearZone(-7, cx0: key.x, cz0: key.z, cx1: key.x, cz1: key.z)
        // A rut: an ordinary change in the zone is wear, not an edit.
        c.urgent = false; c.vehicleWorn = false
        let b0 = w.block(x, y, z)
        _ = w.setBlockAsync(x, y, z, AIR)
        let rutWorn = c.vehicleWorn && !c.urgent
        _ = w.setBlockAsync(x, y, z, b0)
        // A blast at the same spot.
        c.urgent = false; c.vehicleWorn = true
        let n0 = World.blastUrgent
        Explosion.explode(at: V3(Float(x) + 0.5, Float(y) + 1, Float(z) + 0.5), power: 4, game: g, breakBlocks: true)
        let sent = World.blastUrgent - n0
        let want = !World.oldBlastWear
        check(rutWorn && c.urgent == want && (sent > 0) == want,
              "blast wear: in a vehicle's wear zone a rut waits (\(rutWorn)) and a blast's crater goes ahead of the queue (urgent \(c.urgent), \(sent) sections sent ahead)")
    }
}
