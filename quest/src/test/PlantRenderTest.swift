import Foundation
import simd

// L3 ground on the Quest renderer (docs/status/ground-l3.md): plants bend in the wind (chunk.vert plantSway) and grass
// tops are turned per block (texSharpTurned). A pad of grass high in the sky, so nothing else is in view:
//  - sway: the same frame twice is identical over the meadow; 0.7 s later the plants have moved (and the bare pad hasn't);
//  - turned tops: seen straight down, the pad's blocks come in several orientations (one texture would give one).
// `--ground-shots DIR` also writes a before/after-style sheet of the meadow (sway frames) and the lawn from above.
enum PlantRenderTest {
    static func run(game: Game, ctx: VkContext, dir: String?, check: (Bool, String) -> Void) throws {
        let w = game.world
        let saved = (game.player.pos, game.player.flying, game.time, game.player.yaw, game.player.pitch)
        defer { (game.player.pos, game.player.flying, game.time, game.player.yaw, game.player.pitch) = saved }
        let p0 = saved.0
        let x0 = Int(floorf(p0.x)) - 260, z0 = Int(floorf(p0.z)) + 30
        _ = w.loadSync(center: V3(Float(x0), p0.y, Float(z0)), radius: 3)
        var top = SEA
        for dx in stride(from: -8, through: 24, by: 4) { for dz in stride(from: -8, through: 24, by: 4) { top = max(top, w.topY(x0 + dx, z0 + dz)) } }
        let y0 = min(CH - 30, top + 24)
        let grass = Blocks.id("grass_block"), tuft = Blocks.id("short_grass"), fern = Blocks.id("fern"), poppy = Blocks.id("poppy")
        var placed: [IVec3] = []
        func put(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) { w.setBlock(x, y, z, b); placed.append(IVec3(x, y, z)) }
        defer { for q in placed.reversed() { w.setBlock(q.x, q.y, q.z, AIR) } }
        // A 16 x 16 lawn; the north half (z 0-7) planted, the south half bare.
        for dx in 0..<16 { for dz in 0..<16 { put(x0 + dx, y0, z0 + dz, grass) } }
        for dx in 0..<16 { for dz in 0..<8 where (dx + dz) % 2 == 0 {
            put(x0 + dx, y0 + 1, z0 + dz, (dx * 7 + dz) % 5 == 0 ? poppy : ((dx + dz * 3) % 4 == 0 ? fern : tuft))
        } }
        game.player.flying = true
        game.time = 0.22 * DAY_LENGTH
        let out = dir ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

        // Sway: from the bare half, low, looking north over the planted half.
        game.player.pos = V3(Float(x0) + 8, Float(y0) + 1.1, Float(z0) + 12)
        func frame(_ t: Double, _ name: String) throws -> [UInt8] {
            game.time = 0.22 * DAY_LENGTH + t
            try RenderTest.render(game: game, ctx: ctx, path: out + "/\(name).png", yaw: 0, pitch: -0.32)
            return RenderTest.lastRGBA
        }
        let a = try frame(0, "ground_sway_a"), a2 = try frame(0, "ground_sway_a2"), b = try frame(0.7, "ground_sway_b")
        // Left eye: the rows the planted half covers (pitch -0.32 from 1.6 m up: about rows 240-340) and the bare lawn
        // under the camera. (The horizon band above can differ between two frames while far chunks stream in.)
        func diff(_ p: [UInt8], _ q: [UInt8], rows: Range<Int>) -> Int {
            var n = 0
            for y in rows { for x in 0..<640 {
                let i = (y * 1280 + x) * 4
                if abs(Int(p[i]) - Int(q[i])) + abs(Int(p[i + 1]) - Int(q[i + 1])) + abs(Int(p[i + 2]) - Int(q[i + 2])) > 24 { n += 1 }
            } }
            return n
        }
        let same = diff(a, a2, rows: 240..<340), moved = diff(a, b, rows: 240..<340), bare = diff(a, b, rows: 400..<640)
        check(same < moved / 20 && moved > 600 && bare < moved / 20,
              "ground: plants bend in the wind (\(moved) pixels of the meadow move in 0.7 s, \(bare) of the bare lawn, a repeated frame \(same))")

        // Turned grass tops: straight down from 4 blocks over a block corner in the middle of the bare half.
        game.player.pos = V3(Float(x0) + 8, Float(y0) + 1, Float(z0) + 12)
        let eye = game.player.eye
        game.player.pos.y += Float(y0 + 1) + 4 - eye.y
        let h = game.player.eye.y - Float(y0 + 1)
        game.time = 0.22 * DAY_LENGTH
        try RenderTest.render(game: game, ctx: ctx, path: out + "/ground_lawn_top.png", yaw: 0, pitch: -.pi / 2 + 0.0001)
        let img = RenderTest.lastRGBA
        let ppb = 320 / h                                   // pixels per block (90 degree view)
        // The 4 x 4 blocks round the centre, each sampled over its middle half, luma with the block's mean taken out.
        var tiles: [[Float]] = []
        let n = Int(ppb / 2)
        for by in -2..<2 { for bx in -2..<2 {
            let cx = 320 + Int((Float(bx) + 0.5) * ppb), cy = 320 + Int((Float(by) + 0.5) * ppb)
            var t: [Float] = []
            for y in (cy - n / 2)..<(cy + n / 2) { for x in (cx - n / 2)..<(cx + n / 2) {
                let i = (y * 1280 + x) * 4
                t.append(0.3 * Float(img[i]) + 0.59 * Float(img[i + 1]) + 0.11 * Float(img[i + 2]))
            } }
            let m = t.reduce(0, +) / Float(t.count)
            tiles.append(t.map { $0 - m })
        } }
        func d(_ p: [Float], _ q: [Float]) -> Float { zip(p, q).reduce(0) { $0 + abs($1.0 - $1.1) } / Float(p.count) }
        // Greedy clusters: a tile joins the first group whose first tile is within 1/3 of the typical difference.
        var ds: [Float] = []
        for i in 0..<tiles.count { for j in (i + 1)..<tiles.count { ds.append(d(tiles[i], tiles[j])) } }
        ds.sort()
        let typical = ds[ds.count / 2], tight = ds.first ?? 0
        var groups: [Int] = []
        for i in 0..<tiles.count where !groups.contains(where: { d(tiles[$0], tiles[i]) < typical / 3 }) { groups.append(i) }
        check(groups.count >= 5 && typical > 3,
              "ground: grass tops are turned per block (\(groups.count) orientations among 16 blocks seen from above; " + String(format: "difference typical %.1f, closest pair %.1f)", typical, tight))

        // --ground-shots: the materials wall (stone, chest, grass, planks, the seven ores) at 1, 4, 10 and 16 blocks
        // at noon, for the status doc (docs/status/ground-l3.md).
        guard let shots = dir else { return }
        let wall = ["stone", "chest", "grass_block", "oak_planks", "coal_ore", "iron_ore", "copper_ore", "gold_ore", "lapis_ore",
                    "emerald_ore", "diamond_ore"]
        for (k, key) in wall.enumerated() where Blocks.has(key) { put(x0 + 2 + k, y0 + 1, z0 - 1, Blocks.id(key)) }
        let mid = Float(x0 + 2) + Float(wall.count) / 2
        for d in [1, 4, 10, 16] {
            game.player.pos = V3(mid, Float(y0 + 1), Float(z0) + Float(d))
            game.time = 0.22 * DAY_LENGTH
            try RenderTest.render(game: game, ctx: ctx, path: shots + "/ground_wall_\(d).png", yaw: 0, pitch: -0.12)
        }
    }
}
