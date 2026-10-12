import Foundation
import simd

// G9 horse coats through the Quest renderer: `questcheck --render X --horsecoats-only [--horse-shots DIR]`.
//   lineup   the five coats (and a paint and a marked horse) side by side on a stone pad at noon, three-quarter on;
//   rider    the rider's eye on a saddled horse, looking ahead and down at the neck and mane.
// Checks: every coat's body carries a coat pattern (12-14), manes and tails the hair pattern (15); the markings show up
// over 2,000 horses at sensible rates; in the lineup render no two coats come out the same mean colour; from the
// saddle the neck and mane fill the bottom middle of the view (no sky or ground there) and the hair is not one flat tone.
enum HorseCoatShots {
    static func modelChecks(_ check: (Bool, String) -> Void) {
        var coatPats = Set<Float>(), bad: [String] = []
        for coat in 0..<5 {
            let m = Mob(.horse, at: .zero)
            m.variant = (8 << 4) | (8 << 8)
            m.variant += (coat - m.variant % 5 + 5) % 5
            let ps = horseParts(m)
            let body = ps[0]
            coatPats.insert(body.pattern)
            if !(12...14).contains(body.pattern) { bad.append("coat \(coat) body pattern \(body.pattern)") }
            if !ps.contains(where: { $0.pattern == 15 }) { bad.append("coat \(coat): no hair-patterned mane or tail") }
        }
        var socks = 0, blaze = 0, star = 0, dapple = 0, greys = 0, paint = 0
        for v in 0..<2000 {
            let m = Mob(.horse, at: .zero)
            m.variant = v * 7
            let k = HorseCoat.markings(m)
            socks += k.socks.contains(true) ? 1 : 0
            blaze += k.blaze ? 1 : 0; star += k.star ? 1 : 0; paint += k.paint ? 1 : 0
            if m.variant % 5 == 1 { greys += 1; dapple += k.dapple ? 1 : 0 }
        }
        let ok = bad.isEmpty && socks > 600 && socks < 1600 && blaze > 250 && blaze < 700 && star > 250 && star < 700
            && dapple > greys / 2 && paint > 150 && paint < 600
        check(ok, "G9 horse coats: body patterns \(coatPats.sorted()), hair on manes and tails; of 2000 horses \(socks) with socks, "
              + "\(blaze) blazes, \(star) stars, \(paint) paints, \(dapple) of \(greys) greys dappled" + (bad.isEmpty ? "" : "; " + bad.joined(separator: "; ")))
    }

    static func run(game: Game, ctx: VkContext, dir: String?, check: (Bool, String) -> Void) throws {
        modelChecks(check)
        let out = dir ?? FileManager.default.temporaryDirectory.appendingPathComponent("horsecoats-\(getpid())").path
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let p = game.player
        let saved = (p.pos, p.flying, game.time, game.mobs.mobs, game.riding)
        defer { (p.pos, p.flying, game.time, game.mobs.mobs, game.riding) = saved; game.mobs.rebuildIndex() }
        p.flying = true
        let w = game.world
        let base = game.findSpawn() + V3(0, 30, 0)
        let pad = IVec3(Int(floor(base.x)), Int(floor(base.y)) - 1, Int(floor(base.z)))
        var restore: [(IVec3, BlockID)] = []
        let grass = Blocks.has("grass_block") ? Blocks.id("grass_block") : STONE
        for dx in -14...14 { for dz in -6...6 {
            let q = IVec3(pad.x + dx, pad.y, pad.z + dz)
            restore.append((q, w.block(q.x, q.y, q.z)))
            w.setBlock(q.x, q.y, q.z, grass)
            for dy in 1...6 { let r = IVec3(q.x, q.y + dy, q.z); restore.append((r, w.block(r.x, r.y, r.z))); w.setBlock(r.x, r.y, r.z, AIR) }
        } }
        defer { for (q, b) in restore.reversed() { w.setBlock(q.x, q.y, q.z, b) } }
        _ = w.loadSync(center: base, radius: 3)
        game.time = 0.24 * DAY_LENGTH

        // The lineup: coats 0-4, then a paint, then a horse with a blaze and four socks.
        func horse(coat: Int, want: (HorseCoat.Markings) -> Bool) -> Mob {
            for k in 0..<4000 {
                let m = Mob(.horse, at: .zero)
                m.variant = ((k & 15) << 4) | (((k >> 4) & 15) << 8) | ((k >> 8) << 12)
                m.variant += (coat - m.variant % 5 + 5) % 5
                if want(HorseCoat.markings(m)) { return m }
            }
            let m = Mob(.horse, at: .zero); m.variant = coat; return m
        }
        let plain: (HorseCoat.Markings) -> Bool = { !$0.paint && !$0.blaze && !$0.star && !$0.socks.contains(true) }
        var line: [Mob] = (0..<5).map { c in horse(coat: c, want: { c == 1 ? ($0.dapple && !$0.socks.contains(true) && !$0.blaze && !$0.star) : plain($0) }) }
        line.append(horse(coat: 0, want: { $0.paint }))
        line.append(horse(coat: 2, want: { $0.blaze && $0.socks.allSatisfy { $0 } }))
        for (i, m) in line.enumerated() {
            m.pos = V3(Float(pad.x) + 0.5 + Float(i - 3) * 3.4, Float(pad.y + 1), Float(pad.z) + 0.5)
            m.yaw = -.pi / 2 + 0.35                                  // side on, a little toward the camera
            m.callTimer = 0.5                                        // standing, head up (no graze)
        }
        game.mobs.mobs = line; game.mobs.rebuildIndex()
        let target = V3(Float(pad.x) + 0.5, Float(pad.y) + 2.0, Float(pad.z) + 0.5)
        let eye = target + V3(0, 1.0, 11.5)
        p.pos = eye - V3(0, p.eyeHeight, 0)
        let f = simd_normalize(target - eye)
        try RenderTest.render(game: game, ctx: ctx, path: "\(out)/horse_coats_lineup.png", width: 640, height: 640,
                              yaw: atan2f(-f.x, -f.z), pitch: asinf(f.y), fovDeg: 92)
        print("horsecoats: \(out)/horse_coats_lineup.png")
        // Mean colour of each coat's barrel in the left eye (projected with the same camera).
        let rgba = RenderTest.lastRGBA, W = 640, H = 640
        let t = tanf(92 * .pi / 360)
        let yaw = atan2f(-f.x, -f.z), pitch = asinf(f.y)
        let head = simd_quatf(angle: yaw, axis: V3(0, 1, 0)) * simd_quatf(angle: pitch, axis: V3(1, 0, 0))
        func project(_ q: V3) -> (Int, Int)? {
            let v = head.inverse.act(q - (p.eye + head.act(V3(-0.032, 0, 0))))
            guard v.z < -0.1 else { return nil }
            let x = (v.x / -v.z) / t, y = (v.y / -v.z) / t
            let px = Int((x * 0.5 + 0.5) * Float(W)), py = Int((0.5 - y * 0.5) * Float(H))
            return px >= 4 && px < W - 4 && py >= 4 && py < H - 4 ? (px, py) : nil
        }
        func mean(_ cx: Int, _ cy: Int, _ r: Int) -> V3 {
            var s = V3.zero, n: Float = 0
            for y in max(0, cy - r)...min(H - 1, cy + r) { for x in max(0, cx - r)...min(W - 1, cx + r) {
                let i = (y * W * 2 + x) * 4
                guard i + 2 < rgba.count else { continue }
                s += V3(Float(rgba[i]), Float(rgba[i + 1]), Float(rgba[i + 2])); n += 1
            } }
            return n > 0 ? s / n : .zero
        }
        var means: [V3] = []
        for m in line.prefix(5) {
            if let (x, y) = project(m.pos + V3(0, 1.1, 0)) { means.append(mean(x, y, 3)) }
        }
        var minDiff: Float = .greatestFiniteMagnitude
        for i in 0..<means.count { for j in (i + 1)..<max(i + 1, means.count) { minDiff = min(minDiff, simd_length(means[i] - means[j])) } }
        check(means.count == 5 && minDiff > 12, "G9 lineup: five coats render distinct (closest pair \(Int(minDiff)) apart in RGB; means \(means.map { "\(Int($0.x)),\(Int($0.y)),\(Int($0.z))" }))")

        // The rider's view: in the saddle of the chestnut, looking ahead and down.
        let ridden = line[0]
        ridden.saddled = true
        game.mobs.mobs = [ridden]; game.mobs.rebuildIndex()
        game.riding = ridden
        p.pos = ridden.pos + V3(0, ridden.height * 0.75, 0)
        try RenderTest.render(game: game, ctx: ctx, path: "\(out)/horse_coats_rider.png", width: 480, height: 480,
                              yaw: ridden.yaw, pitch: -0.45, fovDeg: 90)
        print("horsecoats: \(out)/horse_coats_rider.png")
        let rr = RenderTest.lastRGBA
        // Bottom middle of the left eye: the neck and mane (not sky blue, not the grass pad).
        var hairish = 0, total = 0, lum: [Float] = []
        for y in 300..<440 { for x in 200..<280 {
            let i = (y * 480 * 2 + x) * 4
            guard i + 2 < rr.count else { continue }
            let c = V3(Float(rr[i]), Float(rr[i + 1]), Float(rr[i + 2]))
            total += 1
            let sky = c.z > c.x + 20 && c.z > 120
            let grassy = c.y > c.x + 15 && c.y > c.z + 15
            if !sky && !grassy { hairish += 1; lum.append(c.x + c.y + c.z) }
        } }
        let avg = lum.reduce(0, +) / Float(max(1, lum.count))
        let spread = sqrtf(lum.map { ($0 - avg) * ($0 - avg) }.reduce(0, +) / Float(max(1, lum.count)))
        check(total > 0 && Float(hairish) > Float(total) * 0.5 && spread > 6,
              "G9 rider's view: neck and mane fill \(hairish) of \(total) pixels at the bottom middle, tone spread \(Int(spread)) (not flat)")
        game.riding = nil
    }
}
