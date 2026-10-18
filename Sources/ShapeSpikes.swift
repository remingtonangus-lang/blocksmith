import Foundation
import simd

// P338 step 6 (Oct 16 playtest: dripstone "not joined to the ground" and drawn as "paper fold" cards up close): in a
// field world pointed driprock is a real tapered spike, not a crossed card. A run of stacked driprock is one spike from
// the rock it grows out of to its point: its base sinks into that rock (the drawn ground under a floor spike), so it
// meets the ground with no gap, and it narrows to a point at the open end. The blocks stay for gameplay (breaking,
// collision, saves); only the drawing changes.
enum ShapeSpikes {
    static let drip = Mesher.pointedDrip

    static func emit(_ ctx: DetailContext) {
        guard drip != 0 else { return }
        var any = false
        scan: for y in 0..<16 { for z in 0..<16 { for x in 0..<16 where ctx.R[ctx.ri(x, y, z)] == drip { any = true; break scan } } }
        guard any else { return }
        let sides = ctx.lod == 0 ? 7 : 5
        let layer = Int(Blocks.tex[Int(drip) * 6])
        let opq = Blocks.opaque
        for y in 0..<16 { for z in 0..<16 { for x in 0..<16 where ctx.R[ctx.ri(x, y, z)] == drip {
            // The run this block belongs to (the region reaches 16 past the section, deeper than any spike).
            var lo = y, hi = y
            while lo > -15 && ctx.block(x, lo - 1, z) == drip { lo -= 1 }
            while hi < 30 && ctx.block(x, hi + 1, z) == drip { hi += 1 }
            let hangs = opq[Int(ctx.block(x, hi + 1, z))] || !opq[Int(ctx.block(x, lo - 1, z))] && ctx.block(x, hi + 1, z) != AIR
            let len = Float(hi - lo + 1)
            // Base and point along the run (section-local y); the base sinks into the rock it grows from.
            var base: Float, tip: Float
            if hangs {
                base = Float(hi + 1) + 0.35; tip = Float(lo) + 0.08
            } else {
                base = (ctx.groundTop(x, lo - 1, z, reach: 2, lowest: true) ?? Float(lo)) - 0.35; tip = Float(hi) + 0.92
            }
            let span = base - tip
            guard abs(span) > 0.05 else { continue }
            let rb: Float = min(0.36, 0.2 + 0.05 * len)
            // A slight world-stable lean so a cave of spikes isn't a grid of plumb lines.
            let lean = SIMD2<Float>(ctx.noise(SIMD3(Float(x), Float(lo), Float(z)), 0.5, 0x51D3), ctx.noise(SIMD3(Float(x), Float(lo), Float(z)), 0.5, 0x2B17)) * 0.08
            func at(_ py: Float) -> (SIMD3<Float>, Float) {
                let t = max(0, min(1, (base - py) / span))            // 0 at the base, 1 at the point
                let r = rb * powf(1 - t, 0.85)
                return (SIMD3(Float(x) + 0.5 + lean.x * t, py, Float(z) + 0.5 + lean.y * t), max(0.004, r))
            }
            // This block's piece of the spike (the end blocks reach out to the base and the point).
            var y0 = Float(y), y1 = Float(y + 1)
            if hangs { if y == hi { y1 = base }; if y == lo { y0 = tip } } else { if y == lo { y0 = base }; if y == hi { y1 = tip } }
            let segs = ctx.lod == 0 ? 2 : 1
            for s in 0..<segs {
                let a = y0 + (y1 - y0) * Float(s) / Float(segs), b = y0 + (y1 - y0) * Float(s + 1) / Float(segs)
                let (pa, ra) = at(a), (pb, rbb) = at(b)
                ShapeTrunks.tube(ctx, pa, pb, ra, rbb, bark: layer, sides: sides, salt: UInt32(truncatingIfNeeded: x &* 5 &+ y &* 17 &+ z &* 3))
            }
        } } }
    }
}
