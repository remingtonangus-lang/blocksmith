import Foundation
import simd

// P114 (Oct 12 PM playtest, lava): blocks go into lava. The aim passes through lava (it can't be targeted), so over a
// deep pool nothing solid was in reach and a block could not be placed ("works only sometimes": only where the pool's
// floor or side was within 6 blocks). With nothing to target, a use press puts a plain full block into the first lava
// cell along the aim, as building out over a pool needs.
extension Game {
    @discardableResult
    func placeIntoLava(reach: Float = 6) -> Bool {
        guard let b = held.def.block, Blocks.render[Int(b)] == RenderType.cube.rawValue, Blocks.shape[Int(b)].isEmpty,
              !Blocks.isLiquid(b) else { return false }
        let eye = player.eye, dir = player.look
        var t: Float = 0.3
        while t <= reach {
            let q = eye + dir * t
            let c = IVec3(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z)))
            let id = world.block(c.x, c.y, c.z)
            if Blocks.fluidKind[Int(id)] == 2 {
                guard !player.intersectsBlock(c) else { return false }
                world.setBlock(c.x, c.y, c.z, b)
                sfx(.place(soundMat(b)), at: V3(Float(c.x), Float(c.y), Float(c.z)) + 0.5)
                consumeHeld(); swing = 1
                return true
            }
            if Blocks.collide[Int(id)] { return false }
            t += 0.1
        }
        return false
    }

    // P122: lifts the player standing in cell `c` (in the air) to its top, if there is head room; true when lifted.
    func liftOnto(_ c: IVec3) -> Bool {
        var p = player.pos
        p.y = Float(c.y) + 1.001
        let top = Int(floor(p.y + player.height))
        for y in (c.y + 1)...top {
            for (dx, dz) in [(-1, -1), (-1, 1), (1, -1), (1, 1)] {
                let x = Int(floor(p.x + Float(dx) * (player.halfW - 0.01))), z = Int(floor(p.z + Float(dz) * (player.halfW - 0.01)))
                if Blocks.collide[Int(world.block(x, y, z))] { return false }
            }
        }
        player.pos = p
        player.vel.y = max(0, player.vel.y)
        return true
    }
}
