import Foundation
import simd

// P507 (Nov 1 12:14:11-12:14:44, in a bowl his rockets blew by a Greywall Garrison: "Some reason I can't place blocks
// down in this crater from my rocket launcher... That's a bug", "a lot of my clicks are just getting ignored"):
// questcheck --craterplace fires rockets into his ground (his world and spot) the way he did, then counts the ground
// cells left whole inside the bowl under a dot of drawn rock (each one a block the eye sees past), and clicks stone
// round the bowl from its rim the way he did: every click at the bowl's face puts a block down.
enum CraterPlaceCheck {
    static func run(_ g0: Game, _ check: (Bool, String) -> Void) {
        let field0 = FieldTerrain.newWorlds
        FieldTerrain.newWorlds = true
        defer { FieldTerrain.newWorlds = field0 }
        let w = World(seed: 1091709452045888406, device: g0.world.device, save: nil)
        w.makeFieldWorld()
        w.renderDistance = 3; w.activeDistance = 3
        let g = Game(world: w, save: nil, persistent: false)
        g.paused = false; g.survival = true
        let spot = V3(-4440.5, 160, 4655.5)
        g.player.pos = spot
        _ = w.loadSync(center: spot, radius: 3)
        // The ground's top at a column: the highest ground cell.
        func top(_ x: Int, _ z: Int) -> Int {
            var t = CH - 2
            while t > 1 && !w.groundAt(x, t, z) { t -= 1 }
            return t
        }
        let cx = -4441, cz = 4650
        let gy = top(cx, cz)
        // Three rockets, as he fired them: from 9 blocks off and a little above, down into the ground a few blocks apart.
        let from = V3(Float(cx) + 0.5, Float(gy) + 3.5, Float(cz) + 9.5)
        var hidden = 0, bowlCells = 0
        for (k, off) in [V3(0, 0, 0), V3(1.5, 0, 0.5), V3(-1, 0, 1)].enumerated() {
            let at = V3(Float(cx) + 0.5, Float(top(cx + Int(off.x), cz + Int(off.z))) + 0.9, Float(cz) + 0.5) + off
            let along = simd_normalize(at - from) * 60
            Explosion.explode(at: at, power: Guns.rocketPower, game: g, breakBlocks: true, resistCap: Guns.rocketBreach, along: along)
            if k == 2 {
                // Ground cells left whole inside the bowl, drawn as a dot: the field at their middle barely over nothing.
                for y in (gy - 6)...(gy + 2) { for z in (cz - 6)...(cz + 6) { for x in (cx - 6)...(cx + 6) {
                    let mid = V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
                    guard simd_length(mid - at) < 4 else { continue }
                    if !w.groundAt(x, y, z) { bowlCells += 1; continue }
                    if w.fieldDensity(at: mid) < 0.12 { hidden += 1 }
                } } }
            }
        }
        let floorY = top(cx, cz)
        check(gy - floorY >= 2 && hidden <= 4,
              "craterplace: three rockets blow a bowl \(gy - floorY) deep in his ground at \(cx) \(gy - 64) \(cz) (\(bowlCells) cells open); \(hidden) ground cells left whole inside it under a dot of drawn rock (want at most 4, round its rim)")
        // From the rim: stone in hand, clicks round the bowl's face. Each one aimed at the ground puts a block down.
        let stone = Items.id("stone")
        g.inventory.held = ItemStack(stone, 64)
        var aimed = 0, placed = 0, missed: [String] = []
        let p = g.player
        for (yawOff, pitch) in [(-0.5, -0.45), (-0.25, -0.6), (0, -0.5), (0.25, -0.75), (0.5, -0.4), (0, -0.85), (-0.4, -0.9), (0.4, -0.65),
                                (0.15, -0.35), (-0.15, -1.0)] as [(Float, Float)] {
            // Stood on the bowl's rim to the south, looking north into it.
            let rz = cz + 5
            p.pos = V3(Float(cx) + 0.5, Float(top(cx, rz) + 1) + 0.01, Float(rz) + 0.5)
            p.vel = .zero; p.flying = false
            p.yaw = yawOff; p.pitch = pitch
            g.input.rightClicked = false; g.input.rightDown = false
            g.tick(1.0 / 60)
            p.yaw = yawOff; p.pitch = pitch
            guard let t = g.target, w.groundAt(t.hit.x, t.hit.y, t.hit.z), abs(t.hit.x - cx) <= 6, abs(t.hit.z - cz) <= 6 else { continue }
            // (a block can't go where he stands: an aim at the ground under his own feet isn't one of these)
            let c0 = t.hit + t.normal
            let feet = p.pos, half: Float = 0.3
            if Float(c0.x) < feet.x + half && Float(c0.x + 1) > feet.x - half && Float(c0.z) < feet.z + half && Float(c0.z + 1) > feet.z - half
                && Float(c0.y) < feet.y + 1.8 && Float(c0.y + 1) > feet.y { continue }
            aimed += 1
            let n0 = g.inventory.held.count
            g.input.rightClicked = true; g.input.rightDown = true
            g.tick(1.0 / 60)
            g.input.rightClicked = false; g.input.rightDown = false
            if g.inventory.held.count < n0 { placed += 1 } else {
                let c = t.hit + t.normal
                missed.append("at \(t.hit.x - cx),\(t.hit.y - gy),\(t.hit.z - cz) face \(t.normal.x),\(t.normal.y),\(t.normal.z): \(Blocks.key(w.block(c.x, c.y, c.z)))")
            }
            g.tick(1.0 / 60)
        }
        g.inventory.held = .empty
        check(aimed >= 3 && placed == aimed,
              "craterplace: stone clicked at the bowl's face from its rim goes down every time (\(placed) of \(aimed) clicks)" + (missed.isEmpty ? "" : "; ignored: " + missed.prefix(4).joined(separator: "; ")))
    }
}
