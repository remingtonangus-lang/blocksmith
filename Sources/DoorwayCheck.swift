import Foundation
import simd

// P471 (Oct 26 19:53: "Still having trouble getting through doors sometimes"; P458: "Make it so my hitbox is smaller than
// the door opening") checks, `questcheck --doorway`: walking straight at a one-block doorway (an open bulkhead door, a
// bare gap) a little off its middle, the body slides into line with it and goes through; without the assist it stuck on
// the frame. A walk into a plain wall stays put.
enum DoorwayCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let a = PlaytestOct12Tests.arena(g, dx: 70, dz: 70, r: 7)
        let w = g.world
        var placed: [(IVec3, BlockID)] = []
        func set(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) { placed.append((IVec3(x, y, z), w.block(x, y, z))); w.setBlock(x, y, z, b) }
        defer { Player.doorwayAssistOn = true; for (p, b) in placed.reversed() { w.setBlock(p.x, p.y, p.z, b) }; a.restore() }
        let wz = a.fz - 2, y1 = a.py + 1
        let door = Blocks.has("bulkhead_door") ? Blocks.id("bulkhead_door") : Blocks.id("iron_door")
        func wall(_ opening: String) {
            for x in (a.fx - 4)...(a.fx + 4) { for y in y1...(y1 + 2) { set(x, y, wz, STONE) } }
            switch opening {
            case "door": set(a.fx, y1, wz, door + 4); set(a.fx, y1 + 1, wz, door + 12)
            case "gap": set(a.fx, y1, wz, AIR); set(a.fx, y1 + 1, wz, AIR)
            default: break
            }
        }
        // Walk at it for 2 s from 0.38 off the opening's middle (the body overlaps the frame by 0.18).
        func walk(_ off: Float) -> Float {
            let p = g.player
            p.flying = false; p.vel = .zero; p.yaw = 0; p.pitch = 0
            p.pos = V3(Float(a.fx) + 0.5 + off, Float(y1), Float(a.fz) + 0.5)
            var mi = MoveInput(); mi.forward = 1
            for _ in 0..<120 { p.update(dt: 1.0 / 60, input: mi, world: w) }
            return p.pos.z
        }
        var results: [String: (Bool, Bool)] = [:]
        for opening in ["door", "gap"] {
            wall(opening)
            Player.doorwayAssistOn = false
            let before = walk(0.38) < Float(wz)
            Player.doorwayAssistOn = true
            let after = walk(0.38) < Float(wz) && walk(-0.38) < Float(wz)
            results[opening] = (before, after)
        }
        wall("none")
        let z0 = Float(a.fz) + 0.5
        let solid = walk(0.38)
        let x = g.player.pos.x - (Float(a.fx) + 0.5 + 0.38)
        check(results["door"]!.1 && results["gap"]!.1 && solid > Float(wz) + 1 && abs(x) < 0.01,
              "doorway: 0.38 off the middle, through an open bulkhead door \(results["door"]!.1) (without the assist \(results["door"]!.0)), a bare gap \(results["gap"]!.1) (\(results["gap"]!.0)); into a plain wall it stays put (\(String(format: "%.2f", z0 - solid)) on, \(String(format: "%.2f", x)) aside)")
    }
}
