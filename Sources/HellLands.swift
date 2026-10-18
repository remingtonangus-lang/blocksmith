import Foundation

// P292 (b): hell's own lands, built by EmberGen (the Emberdeep and the Deep's hell band) in place of the reference
// nether's five biomes. The biome keys stay (saves, maps, the locate list); their names, ground, plants, light and
// sound are hell's own (HellLooks.swift draws them, AmbientParticles.swift lights them, SoundSynth.swift voices them):
//   Cinder Plains     (nether_wastes)      bare cinderstone split by glowing fissures, ash shores by the lava sea
//   Ash Dunes         (soul_sand_valley)   pale ash drifted into dunes, charred snags, ash hoodoos capped with onyxstone,
//                                          the half-buried bones of great dead beasts (P336: no more weed sprites)
//   Charwood Thicket  (crimson_forest)     gnarled leaning charwood trees, forked limbs ending in clumps of ember
//                                          fronds, ember pods and tendrils hanging under them; ember fern on the moss
//   Gloamwood         (warped_forest)      tall straight gloamwood spires ringed with spokes of violet fronds, broad
//                                          gloamcaps, gloam tendrils climbing from the lichen, violet crystals; its own
//                                          Gloamlings and moth-winged Searwings (HellMobs.swift, variant 1)
//   Ghostglass Spires (basalt_deltas)      P336 (the Sulfur Flats are gone): a floor of onyxstone with seams of violet
//                                          crystal, tall spires of black glass crowned with crystal, vents burning with
//                                          cold ghost fire, crystal shards
// (Sulfur Crust stays registered for old saves; nothing generates it now.)
// Overhead: hell's own sky (P342, HellSky.swift); no lumenstone hangs from the roof.
extension BlockRegistry {
    func registerHellLandBlocks() {
        if !has("sulfur_crust") {
            var d = BlockDef("sulfur_crust", "Sulfur Crust")
            d.tex = ["sulfur_crust"]
            d.hardness = 0.6; d.tool = .pickaxe; d.requiresTool = true; d.sound = .stone
            add(d)
        }
    }
}

extension EmberGen {
    // Biome-shaped land over the surface pass (decorate): dunes, fissures, vents, snags, wild brimroot.
    // `at`/`set` work in band y inside this chunk.
    func hellLand(_ cx: Int, _ cz: Int, at: (Int, Int, Int) -> BlockID, set: (Int, Int, Int, BlockID) -> Void) {
        let bx = cx * CS, bz = cz * CS
        let H = height
        let soulSand = Blocks.id("soul_sand"), soulSoil = Blocks.id("soul_soil"), magma = Blocks.id("magma_block")
        let ghostFire = Blocks.id("soul_fire"), crystal = Blocks.id("amethyst_cluster")
        let blackstone = Blocks.id("blackstone"), stem = Blocks.id("crimson_stem")
        // P327 (a): the dunes' cells come from the band's density (EmberGen.duneCells), the same the field world's ground
        // is raised by (bandField), so a polygon world draws the dunes as smooth ridges.
        var lat: [Float] = []
        var col = [Float](repeating: 0, count: H)
        for z in 0..<CS { for x in 0..<CS {
            let wx = bx + x, wz = bz + z
            let bio = biome(wx, wz)
            if bio == .soulSandValley {
                if lat.isEmpty { lat = bandLattice(cx: cx, cz: cz) }
                for y in 0..<H { col[y] = latticeD(lat, x, y, z) }
            }
            var past = -1                                   // rows this column's own drift or outcrop already filled
            for y in (EmberGen.lavaLevel + 1)..<(H - 8) where y > past {
                let g = at(x, y, z)
                guard g != AIR, !Blocks.isLiquid(g), at(x, y + 1, z) == AIR else { continue }
                let h = hash3(wx, y, wz, s32 ^ 0x292)
                switch bio {
                case .soulSandValley:
                    // Dunes: long ridges across the wind, 0-3 blocks of drift on the floor.
                    guard g == soulSand || g == soulSoil else { continue }
                    let drift = col[y] > 0 && col[y + 1] <= 0 ? duneCells(col, y, duneDepth(wx, wz)).n : 0
                    var top = y
                    for dy in 1...max(1, drift) where drift > 0 && at(x, y + dy, z) == AIR && at(x, y + dy + 1, z) == AIR { set(x, y + dy, z, soulSand); top = y + dy }
                    past = top + 6
                    // P336: an ash hoodoo in the hollows now and then (a pillar of packed ash under an onyxstone cap; the
                    // wild Brimroot sprites are gone), a charred snag on a crest.
                    if drift == 0 && h % 241 == 0 && x > 1 && x < 14 && z > 1 && z < 14 {
                        let tall = 3 + Int(h >> 9) % 5
                        var free = true
                        for dy in 1...(tall + 2) where at(x, top + dy, z) != AIR { free = false; break }
                        if free {
                            for dy in 1...tall { set(x, top + dy, z, dy == tall / 2 && (h >> 14) & 1 == 1 ? blackstone : soulSoil) }
                            set(x, top + tall + 1, z, blackstone)
                            for (j, (dx, dz)) in [(1, 0), (-1, 0), (0, 1), (0, -1)].enumerated() where (h >> UInt32(16 + j * 2)) & 3 != 0 {
                                if at(x + dx, top + tall + 1, z + dz) == AIR { set(x + dx, top + tall + 1, z + dz, blackstone) }
                            }
                            if at(x + 1, top + 1, z) == AIR { set(x + 1, top + 1, z, soulSoil) }      // a skirt of ash at its foot
                            past = top + tall + 3
                        }
                    }
                    else if drift >= 2 && h % 211 == 0 && x > 1 && x < 14 && z > 1 && z < 14 {
                        let tall = 3 + Int(h >> 9) % 3
                        var free = true
                        for dy in 1...(tall + 1) where at(x, top + dy, z) != AIR { free = false; break }
                        if free {
                            for dy in 1...tall { set(x, top + dy, z, stem) }
                            let d = [(1, 0), (-1, 0), (0, 1), (0, -1)][Int(h >> 13) % 4]
                            if at(x + d.0, top + tall - 1, z + d.1) == AIR { set(x + d.0, top + tall - 1, z + d.1, stem) }
                        }
                    }
                case .basaltDeltas:
                    // P336: the Ghostglass Spires. A spire of black glass, a ghost-fire vent, a shard of violet crystal.
                    if h % 113 == 0 && x > 1 && x < 14 && z > 1 && z < 14 {
                        let tall = 5 + Int(h >> 9) % 9
                        var free = true
                        for dy in 1...(tall + 1) where at(x, y + dy, z) != AIR { free = false; break }
                        if free { glassSpire(x, y, z, tall, h, at: at, set: set); past = y + tall + 3 }
                    } else if h % 89 == 0 && x > 0 && x < 15 && z > 0 && z < 15 && at(x, y + 2, z) == AIR {
                        // A vent: a throat of ash silt burning with cold fire, rimmed with onyxstone.
                        set(x, y, z, soulSoil)
                        set(x, y + 1, z, ghostFire)
                        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where at(x + dx, y + 1, z + dz) == AIR && at(x + dx, y, z + dz) != AIR {
                            set(x + dx, y + 1, z + dz, blackstone)
                        }
                        past = y + 3
                    } else if h % 29 == 0 {
                        set(x, y + 1, z, crystal)
                    }
                case .netherWastes:
                    // Fissures: thin glowing cracks wandering across the plains.
                    let f: Float = deco.noise2(Float(wx) / 38 + 17, Float(wz) / 38 - 5)
                    if abs(f) < 0.022 && g == NETHERRACK { set(x, y, z, magma) }
                default: break
                }
            }
        } }
        // P336: the Ash Dunes' dead: now and then the half-buried skeleton of something huge across the chunk.
        let ch = hash3(cx, 0x336, cz, s32 ^ 0xB0E)
        if ch % 6 == 0 && biome(bx + 8, bz + 8) == .soulSandValley && biome(bx + 3, bz + 3) == .soulSandValley
            && biome(bx + 12, bz + 12) == .soulSandValley {
            beastBones(ch, at: at, set: set)
        }
        // P342 (b): no lumenstone spikes hang from the roof any more (the glowstone look); hell has a sky (HellSky.swift).
    }

    // P336: a glass spire on (x, y, z) (the floor under it): a skirt of black glass round its foot, a shaft narrowing to
    // one block that kinks once on the way up, banded with weeping glass, a crown of violet crystal.
    func glassSpire(_ x: Int, _ y: Int, _ z: Int, _ tall: Int, _ h: UInt32, at: (Int, Int, Int) -> BlockID, set: (Int, Int, Int, BlockID) -> Void) {
        let glass = OBSIDIAN, weep = Blocks.id("crying_obsidian"), crystal = Blocks.id("amethyst_cluster")
        let kinkAt = tall / 2 + Int(h >> 12) % 3, kink = [(1, 0), (-1, 0), (0, 1), (0, -1)][Int(h >> 15) % 4]
        let thick = max(2, tall / 3)
        var sx = x, sz = z
        for dy in 1...tall {
            if dy == kinkAt { set(sx, y + dy, sz, glass); sx += kink.0; sz += kink.1 }
            set(sx, y + dy, sz, (dy + Int(h >> 3) % 4) % 5 == 0 ? weep : glass)
            if dy <= thick {
                // The skirt: all four sides at the foot, fewer as it rises.
                for (j, (dx, dz)) in [(1, 0), (-1, 0), (0, 1), (0, -1)].enumerated() where dy == 1 || (h >> UInt32(18 + j * 2)) % UInt32(dy + 1) == 0 {
                    if at(sx + dx, y + dy, sz + dz) == AIR { set(sx + dx, y + dy, sz + dz, dy == 1 && j == Int(h >> 5) % 4 ? weep : glass) }
                }
            }
        }
        if at(sx, y + tall + 1, sz) == AIR { set(sx, y + tall + 1, sz, crystal) }
    }

    // P336: a great beast's skeleton half sunk in the ash, across the chunk along x or z: a spine of bone over the
    // dunes, ribs arching down into the ash on both sides (shorter toward the ends), a skull at one end.
    func beastBones(_ ch: UInt32, at: (Int, Int, Int) -> BlockID, set: (Int, Int, Int, BlockID) -> Void) {
        let bone = Blocks.id("bone_block")
        let soulSand = Blocks.id("soul_sand"), soulSoil = Blocks.id("soul_soil")
        let alongX = ch & 64 != 0
        func put(_ a: Int, _ b: Int, _ y: Int) {          // a along the spine, b across it
            let x = alongX ? a : b, z = alongX ? b : a
            if x >= 0 && x < CS && z >= 0 && z < CS && at(x, y, z) == AIR { set(x, y, z, bone) }
        }
        // The ash floor under the spine's middle (the first drift top above the lava sea).
        var floorY = -1
        for y in (EmberGen.lavaLevel + 1)..<(height - 12) {
            let g = at(8, y, 8)
            if (g == soulSand || g == soulSoil) && at(8, y + 1, 8) == AIR { floorY = y; break }
        }
        guard floorY > 0 else { return }
        let R = 4 + Int(ch >> 8) % 2
        let spineY = floorY + R - 1
        for a in 2...13 { put(a, 8, spineY + (a == 2 || a == 13 ? -1 : 0)) }
        // Ribs every other block, a little shorter toward each end.
        for a in stride(from: 4, through: 12, by: 2) {
            let r = Float(a == 4 || a == 12 ? R - 1 : R)
            var t: Float = 0
            while t <= Float.pi {
                let b = 8 + Int((cosf(t) * r).rounded()), dy = Int((sinf(t) * r).rounded()) - Int(r)
                put(a, b, spineY + dy)
                t += 0.18
            }
        }
        // The skull: a lump of bone at the head end, two tusks curling forward.
        let head = ch & 128 != 0 ? 1 : 14
        for dy in -1...0 { for b in 7...9 { put(head, b, spineY + dy) } }
        put(head + (head == 1 ? -1 : 1), 7, spineY - 1); put(head + (head == 1 ? -1 : 1), 9, spineY - 1)
    }

    // A charwood tree on (x, y, z) (the moss under it), kept inside the chunk: a trunk leaning over at mid height,
    // two or three limbs forking out of its upper third, each ending in a loose clump of ember fronds with pods and
    // tendrils hanging under it.
    func charwoodTree(_ x: Int, _ y: Int, _ z: Int, _ h: UInt32, at: (Int, Int, Int) -> BlockID, set: (Int, Int, Int, BlockID) -> Void) {
        let stem = Blocks.id("crimson_stem"), frond = Blocks.id("nether_wart_block"), pod = Blocks.id("shroomlight")
        let tendril = Blocks.id("weeping_vines")
        let tall = 5 + Int(h >> 8) % 5
        let lean = [(1, 0), (-1, 0), (0, 1), (0, -1)][Int(h >> 3) % 4]
        let bend = tall / 2 + Int(h >> 14) % 2
        var tx = x, tz = z
        for dy in 1...tall {
            if dy == bend && (h >> 5) & 1 == 1 {
                set(tx, y + dy, tz, stem)                    // the elbow: the trunk steps over and goes on up
                tx += lean.0; tz += lean.1
            }
            set(tx, y + dy, tz, stem)
        }
        let top = y + tall
        var tips: [(Int, Int, Int)] = [(tx, top + 1, tz)]
        let limbs = 2 + Int(h >> 11) % 2                     // (lean 1 + limb 2 + clump 2: within 5 of the root)
        let dirs = [(1, 0), (0, 1), (-1, 0), (0, -1)]
        for l in 0..<limbs {
            let d = dirs[(Int(h >> 17) + l * (limbs == 2 ? 2 : 1)) % 4]
            let from = top - 1 - (l % 2)
            let len = 1 + Int(h >> UInt32(19 + l)) % 2
            var lx = tx, lz = tz, ly = from
            for i in 1...len {
                lx += d.0; lz += d.1
                if i == len { ly += 1; set(lx, ly - 1, lz, stem) }
                set(lx, ly, lz, stem)
            }
            tips.append((lx, ly + 1, lz))
        }
        for (k, t) in tips.enumerated() {
            let hh = hash3(t.0, t.1, t.2, s32 ^ 0xC4A)
            for dy in -1...1 { for dz in -2...2 { for dx in -2...2 {
                let r2 = dx * dx + dz * dz + dy * dy * 3
                guard r2 <= 5, hash3(t.0 + dx, t.1 + dy, t.2 + dz, s32 ^ 0xC4B) % 4 != 0 || r2 <= 1 else { continue }
                if at(t.0 + dx, t.1 + dy, t.2 + dz) == AIR { set(t.0 + dx, t.1 + dy, t.2 + dz, frond) }
            } } }
            // Under the clump: a pod on one tip in three, tendrils on the others.
            if (hh + UInt32(k)) % 3 == 0 {
                if at(t.0, t.1 - 2, t.2) == AIR { set(t.0, t.1 - 2, t.2, pod) }
            } else {
                // (P336: only under a frond that is there, so no tendril hangs from the air)
                for (dx, dz) in [(1, 1), (-1, -1)] where at(t.0 + dx, t.1 - 2, t.2 + dz) == AIR && at(t.0 + dx, t.1 - 1, t.2 + dz) != AIR {
                    let len = 1 + Int(hh >> 4) % 3
                    for i in 0..<len where at(t.0 + dx, t.1 - 2 - i, t.2 + dz) == AIR { set(t.0 + dx, t.1 - 2 - i, t.2 + dz, tendril) }
                }
            }
        }
    }

    // A gloamwood spire on (x, y, z): a tall straight trunk with spokes of fronds every third block (turning a quarter
    // each time) and a spire of fronds on top, a ring of four round its foot.
    // P336 ("the cactus-like plant has blocks hanging off it with an air gap"): each spoke's fronds wrap its last limb
    // block and the tip (above, both sides) instead of hanging a frond under the tip, so the rounded fronds close over
    // the limb's end and none hangs free of it.
    func gloamwoodTree(_ x: Int, _ y: Int, _ z: Int, _ h: UInt32, at: (Int, Int, Int) -> BlockID, set: (Int, Int, Int, BlockID) -> Void) {
        let stem = Blocks.id("warped_stem"), frond = Blocks.id("warped_wart_block")
        let tall = 8 + Int(h >> 8) % 7
        for dy in 1...tall { set(x, y + dy, z, stem) }
        var axis = Int(h >> 4) % 2
        var level = 3 + Int(h >> 12) % 2
        while level < tall - 1 {
            let reach = level < tall / 2 ? 3 : 2
            for s in [-1, 1] {
                let (dx, dz) = axis == 0 ? (s, 0) : (0, s)
                for i in 1..<reach { set(x + dx * i, y + level, z + dz * i, stem) }
                let ex = x + dx * reach, ez = z + dz * reach, lx = ex - dx, lz = ez - dz
                for (px, pz) in [(ex, ez), (lx, lz)] {
                    for (fx, fy, fz) in [(0, 0, 0), (0, 1, 0), (dz, 0, dx), (-dz, 0, -dx)] where at(px + fx, y + level + fy, pz + fz) == AIR {
                        set(px + fx, y + level + fy, pz + fz, frond)
                    }
                }
            }
            axis ^= 1
            level += 3
        }
        let spire = 2 + Int(h >> 16) % 3
        for dy in 1...spire { set(x, y + tall + dy, z, frond) }
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where at(x + dx, y + tall, z + dz) == AIR { set(x + dx, y + tall, z + dz, frond) }
    }

    // P336: a gloamcap on (x, y, z): a trunk bending once, under a broad domed cap of violet fronds (radius 3) whose rim
    // droops, gloam tendrils climbing the trunk's foot.
    func gloamcapTree(_ x: Int, _ y: Int, _ z: Int, _ h: UInt32, at: (Int, Int, Int) -> BlockID, set: (Int, Int, Int, BlockID) -> Void) {
        let stem = Blocks.id("warped_stem"), frond = Blocks.id("warped_wart_block"), vine = Blocks.id("twisting_vines")
        let tall = 6 + Int(h >> 8) % 5
        let bendAt = tall / 2, bend = (h >> 3) & 1 == 0 ? (x < 8 ? 1 : -1, 0) : (0, z < 8 ? 1 : -1)     // (toward the chunk's middle)
        var tx = x, tz = z
        for dy in 1...tall {
            if dy == bendAt && (h >> 6) & 1 == 1 { set(tx, y + dy, tz, stem); tx += bend.0; tz += bend.1 }
            set(tx, y + dy, tz, stem)
        }
        let top = y + tall
        for dz in -3...3 { for dx in -3...3 {
            let r2 = dx * dx + dz * dz
            guard r2 <= 10 else { continue }
            let px = tx + dx, pz = tz + dz
            if r2 <= 5, at(px, top + 1, pz) == AIR { set(px, top + 1, pz, frond) }        // the dome
            if r2 <= 1, at(px, top + 2, pz) == AIR { set(px, top + 2, pz, frond) }
            if r2 >= 1, at(px, top, pz) == AIR { set(px, top, pz, frond) }               // the cap's underside round the trunk
            // The rim droops a block on most of its cells.
            if r2 >= 7 && hash3(px, top, pz, s32 ^ 0x336) % 3 != 0 && at(px, top - 1, pz) == AIR { set(px, top - 1, pz, frond) }
        } }
        for (dx, dz) in [(1, 0), (-1, 0)] where at(x + dx, y + 1, z + dz) == AIR && (h >> 22) & 1 == 1 {
            for i in 1...(1 + Int(h >> 24) % 3) where at(x + dx, y + i, z + dz) == AIR { set(x + dx, y + i, z + dz, vine) }
        }
    }
}
