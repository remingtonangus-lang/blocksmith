import Foundation
import simd

// Big landmarks, part 4: the Ancient Spire (structure key "great_ruin"; an original design). A colossal ruined
// stone tower, 150-175 blocks tall, rising from a rubble mound: a square shaft with chamfered corners in weathered,
// mossy and cracked stone bricks with deepslate bands, window slits up every face, walls eaten through higher up,
// a jagged broken crown. Inside, a stair spirals up the walls through broken floors every 24 blocks to a chest on the
// highest floor it still reaches; another waits by the doorway. One candidate per 64x64-chunk region on open land,
// and it shows past the render distance as an impostor (LandmarkRender).
enum AncientSpire {
    static let a = 13                  // outer half-size at the base (12 at the crown)
    static let ring = 7                // stair ring (cells at |x| or |z| = 7)
    static let floorStep = 24

    static func type(_ gen: WorldGen) -> StructureType {
        StructureType(name: "great_ruin", spacing: 96, separation: 36, salt: 51870337, reach: 2) { [unowned gen] seed, cx, cz in
            // One region in four (at 0.6 about twenty stood within sight range: tour shots full of pillars, run 482).
            guard hashf(cx, 77, cz, UInt32(truncatingIfNeeded: seed)) < 0.25 else { return nil }
            let x = cx * CS + 8, z = cz * CS + 8
            let col = gen.column(x, z)
            guard !col.biome.isOcean && !col.biome.isRiver && col.height > SEA + 2 else { return nil }
            let y = gen.groundY(x, z)
            for (dx, dz) in [(-20, -20), (20, -20), (-20, 20), (20, 20)] {
                let h = gen.column(x + dx, z + dz).height
                if abs(h - y) > 9 || h <= SEA { return nil }
            }
            let H = 150 + Int(hashf(cx, 78, cz, UInt32(truncatingIfNeeded: seed)) * 25)
            let y0 = y + 1
            guard y0 + H + 4 < CH else { return nil }
            let e = 30
            let piece = Piece(min: IVec3(x - e, y0 - 8, z - e), max: IVec3(x + e, y0 + H + 4, z + e), build: { w in AncientSpire.build(&w, x, y0, z, H, seed) })
            return StructureStart(kind: "great_ruin", pieces: [piece], anchor: IVec3(x, y0 + 1, z + a + 4))
        }
    }

    // Stair ring cell i (0..<4 * 2r), clockwise from the north-west corner, with its facing (ascending direction).
    static func ringCell(_ i: Int) -> (Int, Int, Int) {
        let r = ring, side = 2 * r
        let k = i % (4 * side)
        switch k / side {
        case 0: return (-r + k, -r, 3)                    // along +x (stairs ascend east)
        case 1: return (r, -r + (k - side), 1)            // along +z (ascend south)
        case 2: return (r - (k - 2 * side), r, 2)         // along -x (ascend west)
        default: return (-r, r - (k - 3 * side), 0)       // along -z (ascend north)
        }
    }

    static func build(_ w: inout StructWriter, _ cx: Int, _ y0: Int, _ cz: Int, _ H: Int, _ seed: UInt64) {
        func g(_ n: String, _ f: BlockID = STONE) -> BlockID { Blocks.has(n) ? Blocks.id(n) : f }
        let brick = g("stone_bricks"), mossy = g("mossy_stone_bricks", brick), cracked = g("cracked_stone_bricks", brick)
        let deep = g("deepslate_bricks", brick), chis = g("chiseled_stone_bricks", brick), rubble = g("mossy_cobblestone", COBBLE)
        let stair = g("stone_brick_stairs", brick)
        var rng = SRng(seed ^ 0x5B12E)
        let seedK = UInt32(truncatingIfNeeded: seed)
        func put(_ dx: Int, _ y: Int, _ dz: Int, _ b: BlockID) { w.set(cx + dx, y, cz + dz, b) }
        func columns(_ r: Int, _ body: (Int, Int) -> Void) {
            let xa = max(cx - r, w.bx), xb = min(cx + r, w.bx + CS - 1)
            let za = max(cz - r, w.bz), zb = min(cz + r, w.bz + CS - 1)
            guard xa <= xb, za <= zb else { return }
            for z in za...zb { for x in xa...xb { body(x - cx, z - cz) } }
        }
        // Half-size at a height (a slight taper), and whether (dx, dz) is inside it (chamfered corners).
        func half(_ y: Int) -> Int { a - (y - y0) * 1 / max(1, H) }
        func inside(_ dx: Int, _ dz: Int, _ hs: Int) -> Bool { abs(dx) <= hs && abs(dz) <= hs && abs(dx) + abs(dz) <= 2 * hs - 4 }
        // Broken crown: the top height varies round the tower.
        func topAt(_ dx: Int, _ dz: Int) -> Int {
            let ang = atan2f(Float(dz), Float(dx))
            let jag: Float = 18 * (0.5 + 0.5 * sinf(ang * 3 + Float(seed % 7))) + 8 * hashf(Int(ang * 6), 3, 0, seedK)
            return y0 + H - Int(jag)
        }
        // Stair height at a ring cell for each loop (cells of the ring carry one stair per loop).
        let topFloor = y0 + ((H - 30) / floorStep) * floorStep          // highest floor the stair still reaches
        let stairCount = topFloor - y0
        func stairY(_ i: Int) -> Int { y0 + 1 + i }

        // Rubble mound round the foot, with fallen blocks.
        columns(28) { dx, dz in
            let r = Float(dx * dx + dz * dz).squareRoot()
            guard r < 28 else { return }
            let x = cx + dx, z = cz + dz
            w.pillarDown(x, y0 - 1, z, STONE, minY: y0 - 20)
            // Under the tower itself: fill every cave pocket within 24 below (structcheck: the floor hung over a cave).
            if inside(dx, dz, a + 1) {
                for y in stride(from: y0 - 2, through: y0 - 24, by: -1) where !Blocks.opaque[Int(w.get(x, y, z))] { w.set(x, y, z, STONE) }
            }
            let hh = Int((1 - r / 28) * 4 + hashf(x, 5, z, seedK) * 2)
            if !inside(dx, dz, a + 1) { for y in y0..<(y0 + hh) { w.set(x, y, z, (x + z + y) % 3 == 0 ? GRAVEL : rubble) } }
            if hashf(x, 6, z, seedK) < 0.025 && r > 16 {
                for y in (y0 + hh)..<(y0 + hh + 1 + Int(hashf(x, 7, z, seedK) * 3)) { w.set(x, y, z, cracked) }
            }
        }
        // The shaft: walls two thick, floors every 24, windows, decay rising with height.
        columns(a + 1) { dx, dz in
            let x = cx + dx, z = cz + dz
            let top = topAt(dx, dz)
            for y in (y0 - 1)...top {
                let hs = half(y)
                guard inside(dx, dz, hs) else { continue }
                let wall = !inside(dx, dz, hs - 2)
                let rel = y - y0
                if wall {
                    // Window slits: two blocks tall every 12, in the middle of each face.
                    let face = (abs(dx) <= 1 && abs(dz) >= hs - 1) || (abs(dz) <= 1 && abs(dx) >= hs - 1)
                    if face && rel % 12 >= 5 && rel % 12 <= 6 && rel > 8 { w.set(x, y, z, AIR); continue }
                    // Decay: holes eaten through, more of them higher up.
                    let decay = Float(rel) / Float(H)
                    let n = hashf(x / 2, y / 3, z / 2, seedK ^ 0x9E1)
                    if rel > 20 && n < decay * 0.35 { w.set(x, y, z, AIR); continue }
                    var b = brick
                    let hv = hashf(x, y, z, seedK ^ 0x77)
                    if hv < 0.25 { b = mossy } else if hv < 0.45 { b = cracked }
                    if rel % 24 == 0 || rel % 24 == 1 { b = deep }               // deepslate band at each floor
                    if rel == 2 && (abs(dx) == hs || abs(dz) == hs) { b = chis }
                    w.set(x, y, z, b)
                } else if rel > 0 && rel % floorStep == 0 && y <= topFloor {
                    // Floor, broken through in places (never on the stair ring).
                    let onRing = max(abs(dx), abs(dz)) == ring && abs(dx) <= ring && abs(dz) <= ring
                    // The top floor stays whole (its chest must be reachable from the stair head).
                    if !onRing && y != topFloor && hashf(x / 2, y, z / 2, seedK ^ 0x31) < 0.3 { w.set(x, y, z, AIR) } else { w.set(x, y, z, brick) }
                } else if rel <= 0 {
                    w.set(x, y, z, brick)                                    // ground floor and its foundation (was air below)
                } else {
                    w.set(x, y, z, AIR)
                }
            }
        }
        // The spiral stair (stone brick stairs, ascending), with headroom cut through the floors above it.
        for i in 0..<stairCount {
            let (dx, dz, f) = ringCell(i)
            let y = stairY(i)
            put(dx, y, dz, stair + BlockID(f))
            put(dx, y - 1, dz, brick)                                         // solid under each step
            for k in 1...3 where y + k <= topFloor { put(dx, y + k, dz, AIR) }
        }
        // Landing at the top: the floor round the last step is whole.
        let (lx, lz, _) = ringCell(stairCount - 1)
        for ddx in -2...2 { for ddz in -2...2 where inside(lx + ddx, lz + ddz, half(topFloor) - 2) { put(lx + ddx, topFloor, lz + ddz, brick) } }
        // ...except over the last steps, which climb through it (the landing re-filled their headroom: structcheck,
        // the top chest was unreachable in 9 of 9 spires).
        for i in max(0, stairCount - 5)..<stairCount {
            let (sx, sz, _) = ringCell(i)
            for k in 1...3 where stairY(i) + k <= topFloor { put(sx, stairY(i) + k, sz, AIR) }
        }
        // Doorway on the south face, chiseled lintel.
        for y in (y0 + 1)...(y0 + 5) { for dx in -1...1 { for dz in (a - 2)...a { put(dx, y, dz, AIR) } } }
        for dx in -2...2 { put(dx, y0 + 6, a, chis) }
        // Ghost lanterns on every floor the stair reaches, two each on solid brick (the interior shot was near black).
        let lantern = g("soul_lantern", AIR)
        if lantern != AIR {
            var fy = y0
            while fy <= topFloor {
                for (dx, dz) in [(-4, 4), (4, -4)] { put(dx, fy, dz, brick); put(dx, fy + 1, dz, lantern) }
                fy += floorStep
            }
        }
        // Chests: by the door, and on the highest floor the stair reaches (away from the landing).
        w.chest(cx - 4, y0 + 1, cz + a - 4, loot: "dungeon", seed: rng.next(), facing: 1)
        let (tx, tz, _) = ringCell(stairCount / 2)
        w.chest(cx - tx / 2, topFloor + 1, cz - tz / 2, loot: "desert_pyramid", seed: rng.next(), facing: 0)
        put(-tx / 2, topFloor, -tz / 2, brick)
    }
}
