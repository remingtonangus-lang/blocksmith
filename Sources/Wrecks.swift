import Foundation
import simd

// Persistent wrecks (Future ideas #3): a downed dropship, crawler or frigate (or a big piece of one) stays where it came
// to rest, laid into the world as ordinary blocks (saved with the chunks), with salvage crates in it (loot table
// "wreck_salvage"); mobs move in like anywhere dark; and over a few in-game weeks it overgrows: its metal rusts, moss
// gathers on top, vines climb its sides and the grass round it grows tall. A record per wreck (wrecks.json in the
// dimension's save folder) keeps its bounds and when it fell; the overgrowth catches up whenever the player is near.
struct WreckRecord: Codable {
    var id: Int
    var kind: String
    var lo: [Int]
    var hi: [Int]
    var born: Double              // Game.time when it came down
    var steps: Int                // overgrowth steps applied
}

enum Wrecks {
    static let stepsPerDay: Double = 3          // overgrowth steps per in-game day
    static let maxSteps = 63                    // three weeks: fully overgrown
    static let salvageTable = "wreck_salvage"

    // Blocks rust turns into a rusted plate.
    static func rusts(_ b: BlockID) -> Bool {
        let k = Blocks.key(Blocks.groupBase[Int(b)])
        return k.hasPrefix("warship_") || k.hasPrefix("capital_plate") || k.hasPrefix("capital_panel") || k.hasPrefix("capital_trim")
            || k.hasPrefix("capital_graphite") || k == "steel_grating" || k == "iron_block"
    }
}

extension ShipManager {
    // A settled capital (or a big section of one) becomes a wreck: laid into the world, salvage crates set in its
    // sheltered floor spots, a record kept for its overgrowth.
    func makeWreck(_ s: Ship, kind: String, game: Game?) {
        let lo = IVec3(Int(floor(s.worldMin.x)), Int(floor(s.worldMin.y)), Int(floor(s.worldMin.z)))
        let hi = IVec3(Int(floor(s.worldMax.x)), Int(floor(s.worldMax.y)), Int(floor(s.worldMax.z)))
        // Salvage spots first, in ship space: floor cells inside the hull (enclosed air over a solid block).
        var spots: [V3] = []
        let g = s.grid
        var rng = SRng(UInt64(truncatingIfNeeded: s.id &* 2654435761) | 1)
        var tries = 0
        while spots.count < max(2, min(6, s.blockCount / 1500)) && tries < 4000 {
            tries += 1
            let x = rng.range(0, g.sx - 1), y = rng.range(1, g.sy - 2), z = rng.range(0, g.sz - 1)
            guard g.get(x, y, z) == AIR, g.get(x, y + 1, z) == AIR, Blocks.fullCollide[Int(g.get(x, y - 1, z))], s.dry(x, y, z) else { continue }
            spots.append(s.toWorld(V3(Float(x), Float(y), Float(z)) + 0.5))
        }
        bake(s, game: game)
        let w = world
        let chest = Blocks.id("chest")
        for p in spots {
            let c = IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
            guard w.isLoaded(c.x, c.z), Blocks.replaceable[Int(w.rawBlock(c.x, c.y, c.z))] else { continue }
            _ = w.setBlockAsync(c.x, c.y, c.z, chest)
            let be = BlockEntity(.chest)
            var r2 = SRng(UInt64(bitPattern: Int64(c.x &* 73856093 ^ c.z &* 19349663 ^ c.y &* 83492791)) | 1)
            Loot.fill(be.container, table: Wrecks.salvageTable, rng: &r2)
            w.blockEntities[c] = be
        }
        let rec = WreckRecord(id: s.id, kind: kind, lo: [lo.x, lo.y, lo.z], hi: [hi.x, hi.y, hi.z], born: game?.time ?? 0, steps: 0)
        wrecks.append(rec)
        saveWrecks()
        if let g = game, simd_length(s.pos - g.player.pos) < 300 { g.onToast?("The \(s.name) lies wrecked") }
    }

    // Overgrowth: for wrecks near the player, the steps their age calls for (a few per call, so a long absence catches
    // up over a minute of play, not in one frame).
    func wreckTick(_ dt: Float, game g: Game) {
        wreckTimer -= dt
        guard wreckTimer <= 0, !wrecks.isEmpty else { return }
        wreckTimer = 2
        var budget = 4
        for i in wrecks.indices where budget > 0 {
            let r = wrecks[i]
            let c = V3(Float(r.lo[0] + r.hi[0]) * 0.5, Float(r.lo[1] + r.hi[1]) * 0.5, Float(r.lo[2] + r.hi[2]) * 0.5)
            if simd_length(V2(c.x - g.player.pos.x, c.z - g.player.pos.z)) > 200 { continue }
            let want = min(Wrecks.maxSteps, Int((g.time - r.born) / DAY_LENGTH * Wrecks.stepsPerDay))
            while wrecks[i].steps < want && budget > 0 {
                overgrow(wrecks[i], step: wrecks[i].steps)
                wrecks[i].steps += 1
                budget -= 1
            }
        }
        if budget < 4 { saveWrecks() }
    }

    // One overgrowth step: 200 random cells of the wreck's box (and a margin round it).
    func overgrow(_ r: WreckRecord, step: Int) {
        let w = world
        var rng = SRng(UInt64(truncatingIfNeeded: r.id &* 31 &+ step &* 977) | 1)
        let rusted = Blocks.has("rusted_plating") ? Blocks.id("rusted_plating") : AIR
        let moss = Blocks.id("moss_carpet"), vine = Blocks.id("vine")
        let grass = Blocks.has("short_grass") ? Blocks.id("short_grass") : (Blocks.has("grass") ? Blocks.id("grass") : AIR)
        for _ in 0..<200 {
            let x = rng.range(r.lo[0] - 2, r.hi[0] + 2), y = rng.range(r.lo[1] - 1, r.hi[1] + 1), z = rng.range(r.lo[2] - 2, r.hi[2] + 2)
            guard w.isLoaded(x, z), y > 0, y < CH - 1 else { continue }
            let b = w.rawBlock(x, y, z)
            let above = w.rawBlock(x, y + 1, z)
            if Wrecks.rusts(b) {
                // Exposed plates rust (a quarter of the tries), moss gathers on top, vines hang down the sides.
                let exposed = above == AIR || w.rawBlock(x + 1, y, z) == AIR || w.rawBlock(x - 1, y, z) == AIR
                    || w.rawBlock(x, y, z + 1) == AIR || w.rawBlock(x, y, z - 1) == AIR
                if exposed && rusted != AIR && rng.range(0, 3) == 0 { _ = w.setBlockAsync(x, y, z, rusted); continue }
            }
            if Blocks.collide[Int(b)] && Blocks.fullCollide[Int(b)] && !BlockMaterial.anchors(b) {
                if above == AIR && rng.range(0, 2) == 0 { _ = w.setBlockAsync(x, y + 1, z, moss); continue }
                for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)] {
                    let v = IVec3(x, y, z) + d
                    if w.rawBlock(v.x, v.y, v.z) == AIR {
                        _ = w.setBlockAsync(v.x, v.y, v.z, vine)
                        var k = 1
                        while k < 4 && w.rawBlock(v.x, v.y - k, v.z) == AIR && rng.range(0, 1) == 0 { _ = w.setBlockAsync(v.x, v.y - k, v.z, vine); k += 1 }
                        break
                    }
                }
            } else if Blocks.key(b) == "grass_block" && above == AIR && grass != AIR && rng.range(0, 1) == 0 {
                _ = w.setBlockAsync(x, y + 1, z, grass)
            }
        }
    }

    private var wrecksURL: URL? { world.save?.dir.appendingPathComponent("wrecks.json") }
    func saveWrecks() {
        guard let u = wrecksURL, let d = try? JSONEncoder().encode(wrecks) else { return }
        try? d.write(to: u, options: .atomic)
    }
    func loadWrecks() {
        guard let u = wrecksURL, let d = try? Data(contentsOf: u), let a = try? JSONDecoder().decode([WreckRecord].self, from: d) else { return }
        wrecks = a
    }
}
