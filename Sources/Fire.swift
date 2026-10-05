import Foundation
import simd

// Fire (scheduled ticks every 1.2-1.8 s): fire ages and burns out, eats flammable neighbours and spreads. Session H
// (docs/status/world-fx.md) adds:
//   wind      the weather's wind vector (World.wind): downwind neighbours catch sooner, upwind ones later, and in a
//             strong wind embers carry fire several blocks downwind;
//   wood      full wooden blocks scorch in three stages (decals) before they char through into smouldering charcoal
//             (glows, cools to a charcoal block) or burn away; charcoal burns slowly;
//   cap       at most World.fireCap burning cells (no new fire past it), and every tick is timed (World.fireStats).
struct FireStats {
    var lastMs = 0.0, worstMs = 0.0, meanMs = 0.0
    var ticks = 0
    var burning = 0, peak = 0
    var downwind = 0, upwind = 0        // spreads into air with / against the wind (checks)
    var charred = 0, burnedAway = 0, capped = 0
}

extension World {
    static let fireCap = 1500
    // Magma keeps a fire on it burning (looked up once: a name compare per burning cell per tick before).
    static let magmaID: BlockID = Blocks.has("magma_block") ? Blocks.id("magma_block") : BlockID.max

    func placeFire(_ p: IVec3) {
        guard Blocks.replaceable[Int(block(p.x, p.y, p.z))], !Blocks.isLiquid(block(p.x, p.y, p.z)) else { return }
        setBlock(p.x, p.y, p.z, FIRE)
        fires[p] = 0
    }

    private func burnOrSmoulder(_ q: IVec3, _ nb: BlockID) {
        onIgnite?(q, nb)
        blockEntities.removeValue(forKey: q)            // a burnt barrel's contents burn with it
        if fires.count < World.fireCap && Rand.int(in: 0..<2) == 0 { setBlockAsync(q.x, q.y, q.z, FIRE); fires[q] = 0 }
        else { setBlockAsync(q.x, q.y, q.z, AIR) }
        fireStats.burnedAway += 1
    }

    func fireTick() {
        if fires.isEmpty && embers.isEmpty { fireStats.burning = 0; return }
        let t0 = CFAbsoluteTimeGetCurrent()
        let fl = Blocks.flammable, kindT = Wear.kind
        let cube = RenderType.cube.rawValue
        let charcoal = Wear.charcoal, smolder = Wear.smolder
        let magma = World.magmaID
        let ws = simd_length(V2(wind.x, wind.z))
        let wd = ws > 0.01 ? V2(wind.x, wind.z) / ws : V2(0, 0)
        let windK = min(1, ws / 15)                     // 0 calm ... 1 gale
        for (p, age) in fires {
            let b = block(p.x, p.y, p.z)
            if b != FIRE { fires.removeValue(forKey: p); continue }
            if !isLoaded(p.x, p.z) { continue }
            let below = block(p.x, p.y - 1, p.z)
            let eternal = below == NETHERRACK || below == magma
            // Rain puts out fires open to the sky (lightning fires get a few ticks: 1 in 4 per tick); not under glass
            // (Chunk.rainTop).
            if rainLevel > 0.5 && !eternal, let c = chunks[ChunkKey(x: floorDiv(p.x, CS), z: floorDiv(p.z, CS))],
               p.y >= Int(c.rainTop[mod(p.x, CS) + mod(p.z, CS) * CS]), Rand.int(in: 0..<4) == 0 {
                let bi = gen.column(p.x, p.z).biome
                if !(bi == .desert || bi.isBadlands || bi == .savanna || bi == .savannaPlateau) {
                    setBlockAsync(p.x, p.y, p.z, AIR); fires.removeValue(forKey: p); continue
                }
            }
            var anyFlammable = false
            for d in World.allDirs {
                let q = p + d
                let nb = block(q.x, q.y, q.z)
                if kindT[Int(nb)] == .glass && Rand.int(in: 0..<12) == 0 { onGlassHeat?(q) }    // heat cracks glass
                guard fl[Int(nb)] else { continue }
                anyFlammable = true
                if nb == smolder { continue }               // already burning (Fire: embers below)
                // Downwind neighbours catch sooner, upwind ones later; flames climb.
                let dw = Float(d.x) * wd.x + Float(d.z) * wd.y
                var chance: Float = d.y > 0 ? 0.3 : max(0.05, 0.2 * (1 + 1.5 * windK * dw))
                if nb == charcoal { chance *= 0.06 }             // char burns slowly: a burnt-out shell is left
                guard Rand.float(in: 0..<1) < chance else { continue }
                if kindT[Int(nb)] == .wood && Blocks.render[Int(nb)] == cube && nb != charcoal {
                    let s = Int(scorch[q] ?? 0)
                    // (A full scorch map records nothing: then the wood burns on without its stages.)
                    if s < 3 && addScorch(q, to: s + 1) { continue }
                    // Charred through: it smoulders into charcoal, or the flames take it.
                    if Rand.float(in: 0..<1) < 0.55 {
                        onIgnite?(q, nb)
                        blockEntities.removeValue(forKey: q)
                        setBlockAsync(q.x, q.y, q.z, smolder)
                        embers[q] = 0
                        fireStats.charred += 1
                        continue
                    }
                }
                burnOrSmoulder(q, nb)
            }
            // Spread to air next to flammable blocks nearby; in a wind, embers carry it downwind.
            if anyFlammable && Rand.float(in: 0..<1) < 0.34 + 0.3 * windK {
                var q = IVec3(p.x + Rand.int(in: -1...1), p.y + Rand.int(in: -1...2), p.z + Rand.int(in: -1...1))
                if windK > 0.1 && Rand.float(in: 0..<1) < windK * 0.8 {
                    let reach = 1 + Rand.float(in: 0...1) * (1 + windK * 3)
                    q = IVec3(p.x + Int((wd.x * reach).rounded()) + Rand.int(in: -1...1), p.y + Rand.int(in: -1...1),
                              p.z + Int((wd.y * reach).rounded()) + Rand.int(in: -1...1))
                }
                if fires.count >= World.fireCap {
                    fireStats.capped += 1
                } else if block(q.x, q.y, q.z) == AIR && World.allDirs.contains(where: { fl[Int(block(q.x + $0.x, q.y + $0.y, q.z + $0.z))] }) {
                    setBlockAsync(q.x, q.y, q.z, FIRE); fires[q] = 0
                    let along = Float(q.x - p.x) * wd.x + Float(q.z - p.z) * wd.y
                    if along > 0.5 { fireStats.downwind += 1 } else if along < -0.5 { fireStats.upwind += 1 }
                }
            }
            let supported = Blocks.opaque[Int(below)] || anyFlammable || below == smolder
            if !eternal && (!supported || (age > 6 && Rand.int(in: 0..<4) == 0 && !anyFlammable) || age > 30) {
                setBlockAsync(p.x, p.y, p.z, AIR)
                fires.removeValue(forKey: p)
            } else {
                fires[p] = age + 1
            }
        }
        // Smouldering charcoal: glows a while, cools to charcoal; in a wind it can flare up the air above it.
        for (p, age) in embers {
            if block(p.x, p.y, p.z) != smolder { embers.removeValue(forKey: p); continue }
            if !isLoaded(p.x, p.z) { continue }
            if age > 5 && Rand.int(in: 0..<4) == 0 {
                setBlockAsync(p.x, p.y, p.z, charcoal)
                embers.removeValue(forKey: p)
                continue
            }
            embers[p] = age + 1
            if fires.count < World.fireCap && Rand.float(in: 0..<1) < 0.04 + 0.1 * windK, block(p.x, p.y + 1, p.z) == AIR {
                setBlockAsync(p.x, p.y + 1, p.z, FIRE); fires[IVec3(p.x, p.y + 1, p.z)] = 0
            }
        }
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        fireStats.ticks += 1
        fireStats.lastMs = ms
        fireStats.worstMs = max(fireStats.worstMs, ms)
        fireStats.meanMs += (ms - fireStats.meanMs) * (fireStats.ticks == 1 ? 1 : 0.1)
        fireStats.burning = fires.count
        fireStats.peak = max(fireStats.peak, fires.count)
    }
}
