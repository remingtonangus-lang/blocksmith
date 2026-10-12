import Foundation
import simd

// Brimstone Keeps (the Deep expansion, docs/status/the-deep-expansion.md): the guarded strongholds of the Deep's hell
// band. A walled castle on a plinth over the lava sea, one per ~512-block region: four gatehouses with causeways out
// through the rock, solid corner towers with Cinderwisps on top, a two-floor central keep, and a strongroom under the
// keep whose walls hold the Sunderite Ore, the only ore that breaks the Sealrock below the band (DeepSeal.swift).
// Garrison: Blight Skeletons, Boarling Brutes and Cinderwisps at Deep strength ("@deep"), and an Ashguard detachment
// guarding the strongroom ("@ash"): the army below keeps the key to its own vault.
enum BrimstoneKeep {
    static let spacing = 32                        // chunks
    static let floorUp = 36                        // courtyard floor over the hell band's base (lava sea at +31)
    static let half = 21                           // outer wall's outer face
    static let causeway = 36                       // the built causeway (trim deck, basalt piers) out from the centre
    static let reachOut = 72                       // the tunnel / bridge runs on to here, with ladders down and up
    static let oreMin = 8
    // Three layouts (the gap pass, DE7), picked by the keep's seed: 0 the square castle with corner towers, 1 a ring fort
    // (a round curtain wall with six round towers), 2 a bastioned citadel (diamond bastions at the corners and an inner
    // wall round the keep). All share the gatehouses, the keep, the strongroom, the Ember Gate and the garrison roles.
    static let layoutNames = ["castle", "ring fort", "bastioned citadel"]
    static func variant(_ seed: UInt64) -> Int {
        // Region seeds share their high bits, so mix them first (splitmix64 finaliser).
        var z = seed &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Int((z ^ (z >> 31)) % 3)
    }

    // Fortresses of the Deep (Fortress.deepType, a fortress in every slot): the chunk of each start's origin.
    static func fortressChunk(_ worldSeed: UInt64, _ rx: Int, _ rz: Int) -> (Int, Int) {
        StructureCache(seed: worldSeed, types: []).candidate(Fortress.deepType, rx, rz)
    }
    // Keeps must stand clear of every fortress (Chebyshev chunk distance).
    static func clearOfFortresses(_ worldSeed: UInt64, _ cx: Int, _ cz: Int, _ d: Int) -> Bool {
        let s = Fortress.deepType.spacing
        let rx0 = floorDiv(cx - d - 6, s), rx1 = floorDiv(cx + d + 6, s)
        let rz0 = floorDiv(cz - d - 6, s), rz1 = floorDiv(cz + d + 6, s)
        for rz in rz0...rz1 { for rx in rx0...rx1 {
            let (fx, fz) = fortressChunk(worldSeed, rx, rz)
            if abs(fx - cx) < d && abs(fz - cz) < d { return false }
        } }
        return true
    }

    // The keep's chunk in region (rx, rz): a few deterministic tries for a spot clear of the fortresses.
    static func spot(_ worldSeed: UInt64, _ rx: Int, _ rz: Int) -> (Int, Int)? {
        var rng = SRng(worldSeed ^ 0xB815_7013 &+ UInt64(bitPattern: Int64(rx)) &* 0x9E37_79B9 &+ UInt64(bitPattern: Int64(rz)) &* 0x85EB_CA6B)
        for _ in 0..<12 {
            let cx = rx * spacing + 4 + rng.int(spacing - 8), cz = rz * spacing + 4 + rng.int(spacing - 8)
            if clearOfFortresses(worldSeed, cx, cz, 9) { return (cx, cz) }
        }
        return nil
    }

    static func type(worldSeed: UInt64, guardSet: DeepGuard) -> StructureType {
        StructureType(name: "brimstone_keep", spacing: spacing, separation: 8, salt: 0xB81_5703, reach: 5) { seed, cx, cz in
            let rx = floorDiv(cx, spacing), rz = floorDiv(cz, spacing)
            guard let (kx, kz) = spot(worldSeed, rx, rz), guardSet.clear(kx, kz, 5) else { return nil }
            return layout(ox: kx * CS + 8, oz: kz * CS + 8, seed: seed)
        }
    }

    static func layout(ox: Int, oz: Int, seed: UInt64) -> StructureStart {
        let f = DeepGen.hellBase + floorUp
        let r = reachOut
        let piece = Piece(min: IVec3(ox - r, f - 40, oz - r), max: IVec3(ox + r, f + 26, oz + r)) { w in
            build(&w, ox: ox, oz: oz, f: f, seed: seed)
        }
        let s = StructureStart(kind: "brimstone_keep", pieces: [piece], anchor: IVec3(ox, f + 1, oz + 15))
        s.plan = NSNumber(value: variant(seed))            // the layout, for DeepGapTests
        return s
    }

    // Where the strongroom's ore sits: inner wall faces and the floor, picked by position hash (same in every chunk).
    static func oreAt(_ x: Int, _ y: Int, _ z: Int, ox: Int, oz: Int, f: Int) -> Bool {
        let dx = x - ox, dz = z - oz
        // Six fixed seams (so every keep holds enough for a pickaxe), then a scatter by hash.
        for (fx, fy, fz) in [(6, -7, -2), (6, -4, 2), (-2, -7, -6), (2, -4, -6), (2, -6, 6), (-6, -8, -3)]
            where dx == fx && y - f == fy && dz == fz { return true }
        let wall = (abs(dx) == 6 && abs(dz) <= 5) || (abs(dz) == 6 && abs(dx) <= 5)
        let floor = y == f - 10 && abs(dx) <= 5 && abs(dz) <= 5 && dx > -3
        guard (wall && y >= f - 9 && y <= f - 3) || floor else { return false }
        if dx <= -3 && dz >= -6 && dz <= 5 && abs(dx) != 6 { return false }      // keep the stairwell clear
        return hashf(x, y, z, 0x5D3E) < 0.012
    }

    static func build(_ w: inout StructWriter, ox: Int, oz: Int, f: Int, seed: UInt64) {
        let brick = Blocks.id("nether_bricks"), dark = Blocks.id("polished_blackstone_bricks")
        let trim = Blocks.id("polished_blackstone"), basalt = Blocks.id("basalt"), magma = Blocks.id("magma_block")
        let lamp = Blocks.id("ash_lamp"), ore = Blocks.id("sunderite_ore")
        let h = half
        // Plinth: solid from 12 under the courtyard floor up to it, on basalt piers down to the band's floor.
        w.fill(ox - h, f - 12, oz - h, ox + h, f, oz + h, dark)
        for x in stride(from: ox - h, through: ox + h, by: 6) { for z in stride(from: oz - h, through: oz + h, by: 6) {
            w.pillarDown(x, f - 13, z, basalt, minY: DeepGen.hellBase + 1)
        } }
        w.fill(ox - h + 2, f, oz - h + 2, ox + h - 2, f, oz + h - 2, trim)
        // The open courtyard (cleared of rock up to well over the walls).
        w.fill(ox - h + 2, f + 1, oz - h + 2, ox + h - 2, f + 26, oz + h - 2, AIR)
        let layout = variant(seed)
        // Tower tops (the Cinderwisps' perches): where each layout puts them.
        var towers: [(Int, Int)] = []
        if layout == 1 {
            // Ring fort: a round curtain wall (two thick) on the square plinth, crenellated, six round towers on it.
            for z in (oz - h)...(oz + h) { for x in (ox - h)...(ox + h) {
                let d = sqrtf(Float((x - ox) * (x - ox) + (z - oz) * (z - oz)))
                guard d >= Float(h) - 1.6 && d <= Float(h) + 0.4 else { continue }
                w.fill(x, f + 1, z, x, f + 2, z, dark)
                w.fill(x, f + 3, z, x, f + 12, z, brick)
                if (x + z) % 2 == 0 { w.set(x, f + 13, z, brick) }
            } }
            for k in 0..<6 {
                let a = (Float(k) * 60 + 30) * .pi / 180
                let tx = ox + Int((sinf(a) * Float(h)).rounded()), tz = oz + Int((-cosf(a) * Float(h)).rounded())
                for z in (tz - 3)...(tz + 3) { for x in (tx - 3)...(tx + 3) where (x - tx) * (x - tx) + (z - tz) * (z - tz) <= 10 {
                    w.fill(x, f + 1, z, x, f + 20, z, dark)
                    if (x - tx) * (x - tx) + (z - tz) * (z - tz) >= 7 && (x + z) % 2 == 0 { w.set(x, f + 21, z, brick) }
                } }
                w.set(tx, f + 21, tz, lamp)
                towers.append((tx, tz))
            }
            for k in 0..<12 {
                let a = Float(k) * .pi / 6 + 0.26
                w.set(ox + Int((sinf(a) * Float(h - 2)).rounded()), f + 6, oz + Int((cosf(a) * Float(h - 2)).rounded()), lamp)
            }
        } else {
            // Curtain walls: two thick, ember brick on a dark footing, crenellated.
            for (x0, z0, x1, z1) in [(ox - h, oz - h, ox - h + 1, oz + h), (ox + h - 1, oz - h, ox + h, oz + h),
                                     (ox - h, oz - h, ox + h, oz - h + 1), (ox - h, oz + h - 1, ox + h, oz + h)] {
                w.fill(x0, f + 1, z0, x1, f + 2, z1, dark)
                w.fill(x0, f + 3, z0, x1, f + 12, z1, brick)
                w.fill(x0, f + 13, z0, x1, f + 15, z1, AIR)
            }
            for i in stride(from: -h, through: h, by: 2) {
                for (x, z) in [(ox - h, oz + i), (ox + h, oz + i), (ox + i, oz - h), (ox + i, oz + h)] { w.set(x, f + 13, z, brick) }
            }
            // Red lamps along the inner faces.
            for i in stride(from: -h + 4, through: h - 4, by: 6) {
                for (x, z) in [(ox - h + 1, oz + i), (ox + h - 1, oz + i), (ox + i, oz - h + 1), (ox + i, oz + h - 1)] { w.set(x, f + 6, z, lamp) }
            }
            for (sx, sz) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] {
                let tx = ox + sx * h, tz = oz + sz * h
                if layout == 2 {
                    // Bastioned citadel: a diamond bastion on each corner, solid to 16, its point out.
                    for dz in -6...6 { for dx in -6...6 where abs(dx) + abs(dz) <= 6 {
                        w.fill(tx + dx, f + 1, tz + dz, tx + dx, f + 16, tz + dz, dark)
                        if abs(dx) + abs(dz) >= 5 && (dx + dz) % 2 == 0 { w.set(tx + dx, f + 17, tz + dz, brick) }
                    } }
                    w.set(tx, f + 17, tz, lamp)
                } else {
                    // Castle: corner towers, solid, 7 x 7, to 20 over the floor, crenellated tops.
                    w.fill(tx - 3, f + 1, tz - 3, tx + 3, f + 20, tz + 3, dark)
                    w.fill(tx - 3, f + 21, tz - 3, tx + 3, f + 23, tz + 3, AIR)
                    for i in -3...3 where (i + 3) % 2 == 0 {
                        for (x, z) in [(tx - 3, tz + i), (tx + 3, tz + i), (tx + i, tz - 3), (tx + i, tz + 3)] { w.set(x, f + 21, z, brick) }
                    }
                    w.set(tx, f + 21, tz, lamp)
                }
                towers.append((tx, tz))
            }
            if layout == 2 {
                // The inner wall: 7 high round the keep, half-size 11, a 3-wide gate on each axis.
                let a = 11
                for i in -a...a where abs(i) > 1 {
                    for (x, z) in [(ox + i, oz - a), (ox + i, oz + a), (ox - a, oz + i), (ox + a, oz + i)] {
                        w.fill(x, f + 1, z, x, f + 7, z, brick)
                        if i % 2 == 0 { w.set(x, f + 8, z, brick) }
                    }
                }
                for (x, z) in [(ox - 2, oz + a), (ox + 2, oz + a), (ox - 2, oz - a), (ox + 2, oz - a)] { w.set(x, f + 8, z, lamp) }
            }
        }
        for (dx, dz) in [(-12, -12), (12, -12), (-12, 12), (12, 12), (-12, 0), (12, 0)] where layout != 2 || max(abs(dx), abs(dz)) != 11 {
            w.set(ox + dx, f, oz + dz, magma)                                               // magma vents in the courtyard
        }
        // Gatehouses: a 3-wide gate through each wall, flanking piers, and a causeway out through the rock (a bridge where
        // there is only air or lava). It runs on to reachOut; every 8 blocks a ladder goes down from the deck to the
        // ground below (where there is ground, not lava) and a shaft climbs from the tunnel to the open air above (where
        // the tunnel is under rock), so the keep can be walked into from the hell band around it.
        let ladder = Blocks.id("ladder")
        func solid(_ b: BlockID) -> Bool { Blocks.opaque[Int(b)] && Blocks.collide[Int(b)] }
        for (dx, dz) in [(0, 1), (0, -1), (1, 0), (-1, 0)] {
            let px = dz != 0 ? 1 : 0, pz = dx != 0 ? 1 : 0           // across the gate
            for s in [-3, 3] {
                let x = ox + dx * (h + 1) + px * s, z = oz + dz * (h + 1) + pz * s
                w.fill(x - pz, f + 1, z - px, x + pz, f + 16, z + px, dark)
            }
            for d in (h - 2)...reachOut {
                let cx = ox + dx * d, cz = oz + dz * d
                for s in -2...2 {
                    let x = cx + px * s, z = cz + pz * s
                    if d >= h - 1 && abs(s) <= 2 { w.set(x, f, z, trim) }
                    let gate = d <= h && abs(s) <= 1
                    let tunnel = d > h
                    if gate { w.fill(x, f + 1, z, x, f + 4, z, AIR) }
                    if tunnel { w.fill(x, f + 1, z, x, f + 5, z, AIR) }
                }
                if d > h + 1 && d % 4 == 0 {
                    w.pillarDown(cx, f - 1, cz, basalt, minY: DeepGen.hellBase + 1)
                }
                guard d > h + 2 && d % 8 == 4 else { continue }
                // Down: a ladder on the outside of the deck, against a basalt pier.
                let lx = cx + px * 3, lz = cz + pz * 3
                w.pillarDown(cx + px * 2, f - 1, cz + pz * 2, basalt, minY: DeepGen.hellBase + 1)
                if w.inside(lx, f, lz) {
                    var y = f - 1
                    while y > DeepGen.hellBase + 1 && !solid(w.get(lx, y, lz)) && !Blocks.isLiquid(w.get(lx, y, lz)) { y -= 1 }
                    if y < f - 1 && solid(w.get(lx, y, lz)) {
                        for yy in (y + 1)...f { w.set(lx, yy, lz, ladder + BlockID(px == 1 ? 3 : 1)) }
                    }
                }
                // Up: a shaft from the tunnel's edge to the first open air above the rock.
                let ux = cx + px * 2, uz = cz + pz * 2
                if w.inside(ux, f + 6, uz) && solid(w.get(ux, f + 6, uz)) {
                    var y = f + 6
                    while y < f + 46 && w.get(ux, y, uz) != AIR && !Blocks.isLiquid(w.get(ux, y, uz)) { y += 1 }
                    if y < f + 46 && w.get(ux, y, uz) == AIR {
                        for yy in (f + 1)..<y { w.set(ux, yy, uz, ladder + BlockID(px == 1 ? 2 : 0)) }
                    }
                }
            }
        }
        // The central keep: 13 x 13, two floors, a door on the south side, stairs up inside.
        let k = 6
        w.fill(ox - k, f + 1, oz - k, ox + k, f + 18, oz + k, dark)
        w.fill(ox - k + 1, f + 1, oz - k + 1, ox + k - 1, f + 17, oz + k - 1, AIR)
        w.fill(ox - k + 1, f + 9, oz - k + 1, ox + k - 1, f + 9, oz + k - 1, trim)
        for i in -k...k where (i + k) % 2 == 0 {
            for (x, z) in [(ox - k, oz + i), (ox + k, oz + i), (ox + i, oz - k), (ox + i, oz + k)] { w.set(x, f + 19, z, brick) }
        }
        w.fill(ox - 1, f + 1, oz + k, ox + 1, f + 3, oz + k, AIR)                      // door
        for (x, z) in [(ox - k, oz), (ox + k, oz), (ox, oz - k)] {                      // arrow slits
            w.fill(x, f + 3, z, x, f + 5, z, AIR); w.fill(x, f + 12, z, x, f + 14, z, AIR)
        }
        for (x, z) in [(ox - k + 1, oz - 3), (ox + k - 1, oz - 3), (ox - k + 1, oz + 3), (ox + k - 1, oz + 3)] {
            w.set(x, f + 5, z, lamp); w.set(x, f + 14, z, lamp)
        }
        Bastion.stairsUp(&w, x: ox + 3, z: oz + 4, from: f, to: f + 9, dirZ: -1)
        // The strongroom under the keep: 11 x 11 x 8 of air in the plinth, Sunderite in its walls and floor, stairs down
        // from the keep's ground floor.
        w.fill(ox - 5, f - 9, oz - 5, ox + 5, f - 2, oz + 5, AIR)
        var ores = 0
        for y in (f - 10)...(f - 2) { for z in (oz - 6)...(oz + 6) { for x in (ox - 6)...(ox + 6) where oreAt(x, y, z, ox: ox, oz: oz, f: f) {
            w.set(x, y, z, ore); ores += 1
        } } }
        _ = ores
        for (x, z) in [(ox - 6, oz), (ox + 6, oz), (ox, oz + 6), (ox, oz - 6)] { w.set(x, f - 5, z, lamp) }
        Bastion.stairsUp(&w, x: ox - 4, z: oz + 4, from: f - 10, to: f, dirZ: -1)
        // Chests: the strongroom's hoard and the keep's upper floor.
        w.chest(ox + 3, f - 9, oz + 4, loot: "brimstone_strongroom", seed: seed ^ 0x51, facing: 1)
        w.chest(ox, f + 10, oz - 4, loot: "brimstone_keep", seed: seed ^ 0x52)
        w.chest(ox - 4, f + 10, oz + 4, loot: "brimstone_keep", seed: seed ^ 0x53)
        // The Ember Gate (DeepGates.swift): in the courtyard north of the keep, asleep until the Warden falls.
        DeepGates.build(&w, ox: ox, oz: oz, f: f)
        // Spawners: Cinderwisps on two towers.
        let top = layout == 2 ? f + 18 : f + 22
        w.spawner(towers[1].0, top, towers[1].1, mob: "blaze")
        w.spawner(towers[towers.count - 2].0, top, towers[towers.count - 2].1, mob: "blaze")
        // The garrison.
        let y1 = Float(f + 1)
        for (dx, dz) in [(-10, -10), (10, -10), (-10, 10), (10, 10)] { w.mob("wither_skeleton@deep", V3(Float(ox + dx) + 0.5, y1, Float(oz + dz) + 0.5)) }
        // Gate guards (brutes at the north and south gates), wall guards (Blight Skeletons on the walls), tower guards
        // (Cinderwisps), the strongroom's Ashguard detail, and the Keep Warden in the strongroom with the hoard.
        for (dx, dz) in [(5, 16), (-5, -16)] { w.mob("piglin_brute@deep", V3(Float(ox + dx) + 0.5, y1, Float(oz + dz) + 0.5)) }
        w.mob("piglin_brute:warden@deep", V3(Float(ox) + 0.5, Float(f - 9), Float(oz + 2) + 0.5))
        // The Brand Order's detachment at the gate (HellMobs.swift): a knight and two squires.
        w.mob("brand_knight@deep", V3(Float(ox) + 0.5, y1, Float(oz + 13) + 0.5))
        for dx in [-2, 2] { w.mob("brand_squire@deep", V3(Float(ox + dx) + 0.5, y1, Float(oz + 12) + 0.5)) }
        if layout != 1 {
            for (dx, dz) in [(-h, 0), (h, 0), (0, -h), (0, h)] { w.mob("wither_skeleton@deep", V3(Float(ox + dx) + 0.5, Float(f + 13), Float(oz + dz) + 0.5)) }
        } else {
            for (dx, dz) in [(-h + 1, 4), (h - 1, -4), (4, -h + 1), (-4, h - 1)] { w.mob("wither_skeleton@deep", V3(Float(ox + dx) + 0.5, y1, Float(oz + dz) + 0.5)) }
        }
        for (tx, tz) in towers.prefix(4) { w.mob("blaze@deep", V3(Float(tx) + 1.5, Float(top - 1), Float(tz) + 1.5)) }
        w.mob("soldier_trooper@ash^180", V3(Float(ox - 2) + 0.5, y1, Float(oz + 3) + 0.5))
        w.mob("soldier_trooper@ash^180", V3(Float(ox + 1) + 0.5, y1, Float(oz + 2) + 0.5))
        w.mob("soldier_officer@ash^180", V3(Float(ox) + 0.5, Float(f + 10), Float(oz) + 0.5))
        w.mob("soldier_marksman@ash^180", V3(Float(ox - 3) + 0.5, Float(f + 10), Float(oz - 3) + 0.5))
        w.mob("soldier_ironclad@ash^180", V3(Float(ox + 1) + 0.5, Float(f - 9), Float(oz - 2) + 0.5))
        w.mob("soldier_recruit@ash^180", V3(Float(ox + 3) + 0.5, Float(f - 9), Float(oz) + 0.5))
        w.mob("soldier_recruit@ash^0", V3(Float(ox - 1) + 0.5, Float(f - 9), Float(oz - 3) + 0.5))
    }
}

// Deep chunks a save had generated before the keeps and the Deep's bastions arrived (structure-guard-deep-keeps.txt,
// set by World.init before any chunk is generated): new keeps and bastions stay clear of them, or they would stand cut
// off at the edge of explored ground.
final class DeepGuard {
    var chunks: Set<Int64> = []
    func clear(_ cx: Int, _ cz: Int, _ r: Int) -> Bool {
        if chunks.isEmpty { return true }
        for z in (cz - r)...(cz + r) { for x in (cx - r)...(cx + r) where chunks.contains(StructureCache.key(x, z)) { return false } }
        return true
    }
}

extension Bastion {
    // The Deep's hell band gets the Emberdeep's bastions too (their own grid, kept clear of fortresses and keeps).
    static func deepType(worldSeed: UInt64, guardSet: DeepGuard) -> StructureType {
        let spacing = 30
        return StructureType(name: "bastion", spacing: spacing, separation: 8, salt: 0xBA5_7DEE, reach: 4) { seed, cx, cz in
            let rx = floorDiv(cx, spacing), rz = floorDiv(cz, spacing)
            var rng = SRng(worldSeed ^ 0xBA57_DEE9 &+ UInt64(bitPattern: Int64(rx)) &* 0x2545_F491 &+ UInt64(bitPattern: Int64(rz)) &* 0x9E37_79B9)
            for _ in 0..<12 {
                let bx = rx * spacing + 4 + rng.int(spacing - 8), bz = rz * spacing + 4 + rng.int(spacing - 8)
                guard BrimstoneKeep.clearOfFortresses(worldSeed, bx, bz, 9), guardSet.clear(bx, bz, 4) else { continue }
                var nearKeep = false
                let ks = BrimstoneKeep.spacing
                for kz in floorDiv(bz - 12, ks)...floorDiv(bz + 12, ks) { for kx in floorDiv(bx - 12, ks)...floorDiv(bx + 12, ks) {
                    if let (px, pz) = BrimstoneKeep.spot(worldSeed, kx, kz), abs(px - bx) < 9 && abs(pz - bz) < 9 { nearKeep = true }
                } }
                if nearKeep { continue }
                var brng = SRng(seed)
                return start(&brng, ox: bx * CS + 8, oz: bz * CS + 8, y: DeepGen.hellBase + 33, mound: !G20Guard.legacy(G20Guard.deep, bx, bz, reach: 4))
            }
            return nil
        }
    }
}

extension Game {
    // The compass in the Deep's hell band points to the nearest Brimstone Keep (cached per chunk).
    func nearestKeep() -> StructureStart? {
        guard dim.dim == .deep, let sc = world.gen.structures else { return nil }
        let key = StructureCache.key(floorDiv(Int(player.pos.x), CS), floorDiv(Int(player.pos.z), CS))
        if let c = keepCompass, c.key == key { return c.keep }
        let k = sc.nearest("brimstone_keep", x: Int(player.pos.x), z: Int(player.pos.z), maxRegions: 3)
        keepCompass = (key, k)
        return k
    }

    // First time in the hell band this session: what the Sealrock is and where the nearest keep stands.
    func hellHints() {
        guard !hellHinted, DeepGen.inHell(player.pos.y) else { return }
        hellHinted = true
        achieve("deep_hell")
        guard let k = nearestKeep() else { return }
        let d = Int(simd_length(V2(Float(k.anchor.x) - player.pos.x, Float(k.anchor.z) - player.pos.z)))
        onToast?("Sealrock under this fire blocks the way down. A Brimstone Keep about \(d) blocks off holds the Sunderite that breaks it (compasses point there)")
    }
}
