import Foundation

// P292 (b): hell's own lands, built by EmberGen (the Emberdeep and the Deep's hell band) in place of the reference
// nether's five biomes. The biome keys stay (saves, maps, the locate list); their names, ground, plants, light and
// sound are hell's own (HellLooks.swift draws them, AmbientParticles.swift lights them, SoundSynth.swift voices them):
//   Cinder Plains     (nether_wastes)      bare cinderstone split by glowing fissures, ash shores by the lava sea
//   Ash Dunes         (soul_sand_valley)   pale ash drifted into dunes, charred snags, wild Brimroot in the hollows
//   Charwood Thicket  (crimson_forest)     gnarled leaning charwood trees, forked limbs ending in clumps of ember
//                                          fronds, ember pods and tendrils hanging under them; ember fern on the moss
//   Gloamwood         (warped_forest)      tall straight gloamwood spires ringed with spokes of violet fronds, gloam
//                                          tendrils climbing from the lichen, crystal sprouts
//   Sulfur Flats      (basalt_deltas)      yellow sulfur crust in plates over the rock, steaming vents with glowing
//                                          throats, black onyxstone outcrops
// Overhead: lumenstone hangs as amber crystal spikes (the nether's glowstone blobs are gone).
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
        let crust = Blocks.has("sulfur_crust") ? Blocks.id("sulfur_crust") : Blocks.id("basalt")
        let blackstone = Blocks.id("blackstone"), stem = Blocks.id("crimson_stem"), wart = Blocks.id("nether_wart_3")
        for z in 0..<CS { for x in 0..<CS {
            let wx = bx + x, wz = bz + z
            let bio = biome(wx, wz)
            var past = -1                                   // rows this column's own drift or outcrop already filled
            for y in (EmberGen.lavaLevel + 1)..<(H - 8) where y > past {
                let g = at(x, y, z)
                guard g != AIR, !Blocks.isLiquid(g), at(x, y + 1, z) == AIR else { continue }
                let h = hash3(wx, y, wz, s32 ^ 0x292)
                switch bio {
                case .soulSandValley:
                    // Dunes: long ridges across the wind, 0-3 blocks of drift on the floor.
                    guard g == soulSand || g == soulSoil else { continue }
                    let ridge: Float = deco.noise2(Float(wx) / 26, Float(wz) / 11) + deco.noise2(Float(wx) / 70, Float(wz) / 70) * 0.6
                    let drift = Int(max(0, ridge + 0.15) * 3.2)
                    var top = y
                    for dy in 1...max(1, drift) where drift > 0 && at(x, y + dy, z) == AIR && at(x, y + dy + 1, z) == AIR { set(x, y + dy, z, soulSand); top = y + dy }
                    past = top + 6
                    // Wild Brimroot in the hollows, now and then a charred snag on a crest.
                    if drift == 0 && h % 53 == 0 && at(x, top + 1, z) == AIR { set(x, top + 1, z, wart) }
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
                    // Vents: a ring of crust raised round a glowing throat.
                    if h % 97 == 0 && x > 0 && x < 15 && z > 0 && z < 15 {
                        set(x, y, z, magma)
                        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)] where at(x + dx, y + 1, z + dz) == AIR
                            && at(x + dx, y, z + dz) != AIR {
                            set(x + dx, y + 1, z + dz, crust)
                        }
                    } else if h % 61 == 0 && x > 0 && x < 15 && z > 0 && z < 15 {
                        // A black outcrop: a stub of onyxstone 1-3 high.
                        for dy in 1...(1 + Int(h >> 10) % 3) where at(x, y + dy, z) == AIR { set(x, y + dy, z, blackstone) }
                        past = y + 4
                    }
                case .netherWastes:
                    // Fissures: thin glowing cracks wandering across the plains.
                    let f: Float = deco.noise2(Float(wx) / 38 + 17, Float(wz) / 38 - 5)
                    if abs(f) < 0.022 && g == NETHERRACK { set(x, y, z, magma) }
                default: break
                }
            }
        } }
        // Lumenstone: amber crystal spikes hanging from the roof (a taller band hangs more, far overhead).
        let glow = LAMP
        for k in 0..<(H > 128 ? 5 : 3) {
            let h = hash3(cx, k, cz, s32 ^ 0x6C2)
            if h % 3 == 0 { continue }
            let x0 = 2 + Int(h % 12), z0 = 2 + Int((h >> 4) % 12)
            var y0 = H - 8
            while y0 > 40 && !(at(x0, y0, z0) == AIR && at(x0, y0 + 1, z0) != AIR && !Blocks.isLiquid(at(x0, y0 + 1, z0))) { y0 -= 1 }
            if y0 <= 40 { continue }
            let len = 3 + Int((h >> 8) % 7)
            for i in 0..<len where at(x0, y0 - i, z0) == AIR { set(x0, y0 - i, z0, glow) }
            // A root of shorter crystals round the main spike.
            for (j, (dx, dz)) in [(1, 0), (-1, 0), (0, 1), (0, -1)].enumerated() where (h >> UInt32(12 + j)) & 1 == 1 {
                let l2 = 1 + Int((h >> UInt32(16 + j * 2)) % 3)
                for i in 0..<l2 where at(x0 + dx, y0 - i, z0 + dz) == AIR { set(x0 + dx, y0 - i, z0 + dz, glow) }
            }
        }
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
                for (dx, dz) in [(1, 1), (-1, -1)] where at(t.0 + dx, t.1 - 2, t.2 + dz) == AIR {
                    let len = 1 + Int(hh >> 4) % 3
                    for i in 0..<len where at(t.0 + dx, t.1 - 2 - i, t.2 + dz) == AIR { set(t.0 + dx, t.1 - 2 - i, t.2 + dz, tendril) }
                }
            }
        }
    }

    // A gloamwood spire on (x, y, z): a tall straight trunk with spokes of fronds every third block (turning a quarter
    // each time) and a spire of fronds on top, a ring of four round its foot.
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
                let ex = x + dx * reach, ez = z + dz * reach
                for (fx, fy, fz) in [(0, 0, 0), (0, 1, 0), (0, -1, 0), (dz, 0, dx), (-dz, 0, -dx)] where at(ex + fx, y + level + fy, ez + fz) == AIR {
                    set(ex + fx, y + level + fy, ez + fz, frond)
                }
            }
            axis ^= 1
            level += 3
        }
        let spire = 2 + Int(h >> 16) % 3
        for dy in 1...spire { set(x, y + tall + dy, z, frond) }
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where at(x + dx, y + tall, z + dz) == AIR { set(x + dx, y + tall, z + dz, frond) }
    }
}
