import Foundation

// Bastion remnants: big blackstone ruins at y 33 sharing the fortress region grid (3 in 5 starts).
// Four layouts like the reference game's: housing units, hoglin stables, treasure room and bridge.
// Blocks mix bricks / cracked bricks / blackstone / gilded blackstone by a position hash so every
// chunk agrees on the same ruin; piglins, brutes and hoglins are placed when the chunk generates.
enum Bastion {
    static let type = StructureType(name: "bastion", spacing: 27, separation: 4, salt: 30084232, reach: 4) { seed, cx, cz in
        var rng = SRng(seed)
        if rng.int(5) < 2 { return nil }             // the other 2 in 5 are fortresses
        let variant = rng.int(4)
        let ox = cx * CS + 8, oz = cz * CS + 8, y = YOFF + 33
        let s = rng.next()
        let half = variant == 3 ? 30 : 22
        let piece = Piece(min: IVec3(ox - half, y - 40, oz - half), max: IVec3(ox + half, y + 34, oz + half)) { w in
            build(&w, variant: variant, ox: ox, oz: oz, y: y, seed: s)
        }
        return StructureStart(kind: "bastion", pieces: [piece], anchor: IVec3(ox, y + (variant == 1 ? 12 : 1), oz + (variant == 3 ? 0 : -6)))
    }

    static func mat(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
        let h = hashf(x, y, z, 0xBA57)
        if h < 0.62 { return Blocks.id("polished_blackstone_bricks") }
        if h < 0.8 { return Blocks.id("cracked_polished_blackstone_bricks") }
        if h < 0.95 { return Blocks.id("blackstone") }
        return Blocks.id("gilded_blackstone")
    }

    // Hollow box: walls of `mat`, a polished floor, interior carved to air; windows every few blocks.
    static func room(_ w: inout StructWriter, _ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int, windows: Bool = true, roof: Bool = true) {
        let floor = Blocks.id("polished_blackstone")
        for y in y0...y1 { for z in z0...z1 { for x in x0...x1 {
            guard w.inside(x, y, z) else { continue }
            let edge = x == x0 || x == x1 || z == z0 || z == z1
            if y == y0 { w.set(x, y, z, floor) }
            else if y == y1 && roof { w.set(x, y, z, mat(x, y, z)) }
            else if edge {
                let win = windows && (y - y0) % 6 >= 2 && (y - y0) % 6 <= 3 && (x + z) % 4 == 0 && (x == x0 || x == x1) != (z == z0 || z == z1)
                // Crumbled top edges: ruins lose blocks near the top.
                let ruined = y > y1 - 3 && hashf(x, y, z, 0xDEC4) < 0.35
                w.set(x, y, z, win || ruined ? AIR : mat(x, y, z))
            } else { w.set(x, y, z, AIR) }
        } } }
    }

    static func supports(_ w: inout StructWriter, _ x0: Int, _ z0: Int, _ x1: Int, _ z1: Int, _ y: Int, step: Int = 6) {
        let basalt = Blocks.id("basalt")
        for x in stride(from: x0, through: x1, by: step) { for z in stride(from: z0, through: z1, by: step) {
            w.pillarDown(x, y - 1, z, hashf(x, 0, z, 7) < 0.5 ? basalt : Blocks.id("blackstone"), minY: YOFF + 1)
        } }
    }

    static func stairsUp(_ w: inout StructWriter, x: Int, z: Int, from y0: Int, to y1: Int, dirZ: Int) {
        let st = Blocks.id("polished_blackstone_brick_stairs")
        guard y1 > y0 else { return }
        for i in 0..<(y1 - y0) {
            let zz = z + i * dirZ
            for dx in 0...1 {
                w.set(x + dx, y0 + 1 + i, zz, st + (dirZ > 0 ? 1 : 0))
                w.fill(x + dx, y0 + 2 + i, zz, x + dx, y0 + 4 + i, zz, AIR)
            }
        }
    }

    static func build(_ w: inout StructWriter, variant: Int, ox: Int, oz: Int, y: Int, seed: UInt64) {
        var rng = SRng(seed)
        let gold = Blocks.id("gold_block")
        switch variant {
        case 0:
            // Housing units: rampart ring with gates, four two-storey houses around a courtyard.
            supports(&w, ox - 20, oz - 20, ox + 20, oz + 20, y)
            room(&w, ox - 20, y, oz - 20, ox + 20, y + 9, oz + 20, windows: false, roof: false)
            w.fill(ox - 19, y + 8, oz - 19, ox + 19, y + 8, oz - 18, Blocks.id("polished_blackstone"))     // rampart walk
            w.fill(ox - 19, y + 8, oz + 18, ox + 19, y + 8, oz + 19, Blocks.id("polished_blackstone"))
            for g in [(ox, oz - 20), (ox, oz + 20), (ox - 20, oz), (ox + 20, oz)] { w.fill(g.0 - 1, y + 1, g.1 - 1, g.0 + 1, y + 4, g.1 + 1, AIR) }
            for (i, c) in [(-10, -10), (10, -10), (-10, 10), (10, 10)].enumerated() {
                let hx = ox + c.0, hz = oz + c.1
                room(&w, hx - 5, y, hz - 5, hx + 5, y + 13, hz + 5)
                w.fill(hx - 4, y + 6, hz - 4, hx + 4, y + 6, hz + 4, Blocks.id("polished_blackstone"))     // upper floor
                w.fill(hx - 4, y + 6, hz + 1, hx - 3, y + 6, hz + 4, AIR)                                   // stairwell
                stairsUp(&w, x: hx - 4, z: hz + 4, from: y, to: y + 5, dirZ: -1)
                w.fill(hx - 1, y + 1, c.1 < 0 ? hz + 5 : hz - 5, hx + 1, y + 3, c.1 < 0 ? hz + 5 : hz - 5, AIR)  // door to the courtyard
                w.chest(hx + 3, y + 7, hz - 3, loot: "bastion", seed: rng.next(), facing: i % 4)
                w.mob("piglin", V3(Float(hx) + 0.5, Float(y + 1), Float(hz) + 0.5))
                if i % 2 == 0 { w.mob("piglin", V3(Float(hx) + 0.5, Float(y + 7), Float(hz) + 1.5)) }
            }
            w.mob("piglin_brute", V3(Float(ox) + 0.5, Float(y + 1), Float(oz) + 0.5))
            w.chest(ox, y + 1, oz + 2, loot: "bastion", seed: rng.next(), facing: 1)
        case 1:
            // Treasure room: thick-walled keep over a lava pit; central platform with a gold core,
            // the treasure chest and magma cube spawners; bridges out to the walls.
            supports(&w, ox - 16, oz - 16, ox + 16, oz + 16, y, step: 8)
            room(&w, ox - 16, y, oz - 16, ox + 16, y + 30, oz + 16, windows: false, roof: false)
            room(&w, ox - 15, y, oz - 15, ox + 15, y + 29, oz + 15, windows: false, roof: false)
            w.fill(ox - 14, y, oz - 14, ox + 14, y, oz + 14, LAVA)
            w.fill(ox - 14, y - 1, oz - 14, ox + 14, y - 1, oz + 14, Blocks.id("blackstone"))
            // Platform on four basalt legs.
            for (dx, dz) in [(-4, -4), (4, -4), (-4, 4), (4, 4)] {
                w.fill(ox + dx, y, oz + dz, ox + dx, y + 11, oz + dz, Blocks.id("basalt"))
            }
            w.fill(ox - 5, y + 12, oz - 5, ox + 5, y + 12, oz + 5, Blocks.id("polished_blackstone_bricks"))
            w.fill(ox - 1, y + 13, oz - 1, ox + 1, y + 14, oz + 1, gold)
            for (dx, dz) in [(-2, 0), (2, 0), (0, -2), (0, 2)] { w.set(ox + dx, y + 13, oz + dz, Blocks.id("gilded_blackstone")) }
            w.chest(ox, y + 15, oz, loot: "bastion", seed: rng.next(), facing: 0)
            w.spawner(ox - 4, y + 13, oz - 4, mob: "magma_cube")
            w.spawner(ox + 4, y + 13, oz + 4, mob: "magma_cube")
            // Bridges from the platform to each wall.
            w.fill(ox - 1, y + 12, oz - 15, ox + 1, y + 12, oz - 6, Blocks.id("polished_blackstone_bricks"))
            w.fill(ox - 1, y + 12, oz + 6, ox + 1, y + 12, oz + 15, Blocks.id("polished_blackstone_bricks"))
            w.fill(ox - 15, y + 12, oz - 1, ox - 6, y + 12, oz + 1, Blocks.id("polished_blackstone_bricks"))
            w.fill(ox + 6, y + 12, oz - 1, ox + 15, y + 12, oz + 1, Blocks.id("polished_blackstone_bricks"))
            for g in [(ox, oz - 16), (ox, oz + 16), (ox - 16, oz), (ox + 16, oz)] {
                w.fill(g.0 - 1, y + 13, g.1 - 1, g.0 + 1, y + 16, g.1 + 1, AIR)
            }
            // Walkways around the inside at the bridge level.
            for s in [-14, 14] {
                w.fill(ox - 14, y + 12, oz + s, ox + 14, y + 12, oz + s, Blocks.id("polished_blackstone"))
                w.fill(ox + s, y + 12, oz - 14, ox + s, y + 12, oz + 14, Blocks.id("polished_blackstone"))
            }
            for k in 0..<3 { w.mob("piglin_brute", V3(Float(ox - 12 + k * 12) + 0.5, Float(y + 13), Float(oz - 14) + 0.5)) }
            w.mob("piglin", V3(Float(ox) + 0.5, Float(y + 13), Float(oz + 13) + 0.5))
        case 2:
            // Hoglin stables: a big U of ramparts around a sunken yard with basalt pillars.
            supports(&w, ox - 20, oz - 20, ox + 20, oz + 20, y)
            room(&w, ox - 20, y, oz - 20, ox + 20, y + 12, oz + 20, windows: false, roof: false)
            w.fill(ox - 19, y + 1, oz + 19, ox + 19, y + 11, oz + 20, AIR)          // open side
            for s in [-1, 1] {
                w.fill(ox - 19, y + 1, oz - 19, ox + 19, y + 6, oz - 15, mat(ox, y, oz))  // rampart mass
                w.fill(ox + s * 19 - (s > 0 ? 4 : 0), y + 1, oz - 19, ox + s * 19 + (s < 0 ? 4 : 0), y + 6, oz + 12, mat(ox + s, y, oz))
            }
            w.fill(ox - 14, y + 1, oz - 14, ox + 14, y + 6, oz + 18, AIR)
            for x in stride(from: ox - 12, through: ox + 12, by: 8) { for z in stride(from: oz - 10, through: oz + 14, by: 8) {
                w.fill(x, y + 1, z, x, y + 5, z, Blocks.id("basalt"))
            } }
            w.fill(ox - 19, y + 7, oz - 19, ox + 19, y + 7, oz - 15, Blocks.id("polished_blackstone"))
            stairsUp(&w, x: ox - 13, z: oz + 2, from: y, to: y + 6, dirZ: -1)
            w.chest(ox - 16, y + 8, oz - 17, loot: "bastion", seed: rng.next(), facing: 1)
            w.chest(ox + 16, y + 8, oz - 17, loot: "bastion", seed: rng.next(), facing: 1)
            for k in 0..<4 { w.mob("hoglin", V3(Float(ox - 6 + k * 4) + 0.5, Float(y + 1), Float(oz + 4) + 0.5)) }
            w.mob("piglin", V3(Float(ox) + 0.5, Float(y + 8), Float(oz - 17) + 0.5))
        default:
            // Bridge: a long arched span to a gatehouse with a chest.
            let len = 26
            supports(&w, ox - len, oz - 2, ox + len, oz + 2, y + 10, step: 9)
            for x in (ox - len)...(ox + len) {
                let arch = abs((x - ox + len) % 9 - 4)
                w.fill(x, y + 10 - (4 - arch) / 2, oz - 2, x, y + 10, oz + 2, mat(x, y + 10, oz))
                if hashf(x, 0, oz, 11) > 0.15 { w.set(x, y + 11, oz - 2, mat(x, y + 11, oz - 2)); w.set(x, y + 11, oz + 2, mat(x, y + 11, oz + 2)) }
                w.fill(x, y + 11, oz - 1, x, y + 14, oz + 1, AIR)
            }
            room(&w, ox + len - 4, y + 10, oz - 6, ox + len + 4, y + 20, oz + 6)
            w.fill(ox + len - 4, y + 11, oz - 1, ox + len - 4, y + 13, oz + 1, AIR)
            w.chest(ox + len, y + 11, oz + 4, loot: "bastion", seed: rng.next(), facing: 0)
            w.mob("piglin", V3(Float(ox) + 0.5, Float(y + 11), Float(oz) + 0.5))
            w.mob("piglin", V3(Float(ox + len) + 0.5, Float(y + 11), Float(oz) + 0.5))
        }
    }
}
