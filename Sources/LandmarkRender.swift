import Foundation
import simd

// Landmark impostors (Future ideas #9): big landmarks stay on the horizon past the render distance. Each is a coarse
// mesh (a low-poly cone, its crater glow and a smoke plume) built on the CPU every frame from the same parameters the
// terrain uses, shaded by the sun and hazed toward the fog colour by distance. The mesh is scaled in toward the eye so
// it sits just inside the far plane (the same angular size): loaded terrain is always nearer, so it hides the impostor
// wherever the real landmark has been generated, and the impostor fills in where it hasn't.
extension Renderer {
    static let landmarkRange: Float = 2600
    static let spireRange: Float = 1800               // a 170-block shaft is a sliver beyond this
    static var spireList: [V4] = []                // x, base y, z, height (refreshed every 2 s)
    static var spireAt: Double = -10

    // Ancient Spire starts within the landmark range (structure regions are 1024 blocks).
    func spireCache(_ game: Game) -> [V4] {
        if game.clock - Renderer.spireAt < 2 { return Renderer.spireList }
        Renderer.spireAt = game.clock
        Renderer.spireList.removeAll()
        guard let sc = (game.world.gen as? WorldGen)?.structures, let t = sc.types.first(where: { $0.name == "great_ruin" }) else { return [] }
        let span = t.spacing * CS
        let p = game.player.pos
        let rx0 = floorDiv(Int(p.x), span), rz0 = floorDiv(Int(p.z), span)
        let n = Int(Renderer.spireRange) / span + 1
        for rz in (rz0 - n)...(rz0 + n) { for rx in (rx0 - n)...(rx0 + n) {
            guard let s = sc.start(t, regionX: rx, regionZ: rz) else { continue }
            let y0 = Float(s.min.y + 8), h = Float(s.max.y - 4 - (s.min.y + 8))
            Renderer.spireList.append(V4(Float(s.min.x + s.max.x) / 2, y0, Float(s.min.z + s.max.z) / 2, h))
        } }
        return Renderer.spireList
    }

    // Appends the impostor triangles: opaque ones first, then `smokeStart` marks the blended smoke.
    func buildLandmarks(_ out: inout [SimpleVert], smokeStart: inout Int, game: Game, eye: V3, far: Float, fog: V3, rd: Float) {
        smokeStart = 0
        guard game.dim.dim == .overworld, let wg = game.world.gen as? WorldGen else { return }
        let vols = wg.terrain.volcanoes(near: eye.x, eye.z, reach: Renderer.landmarkRange)
        let loaded = rd * 16
        let sun = game.sunDir
        let day = game.daylight
        let hdrK: Float = hdrActive ? 1.6 : 1
        let place: Float = far * 0.93
        var smoke = landmarkSmoke
        smoke.removeAll(keepingCapacity: true)
        // Every impostor vertex goes onto a shell just inside the far plane, along its own direction (same size on
        // screen), the radius growing a little with the true distance so nearer faces still cover farther ones. The shell
        // lies beyond all loaded terrain, so an impostor can never cut through the real landmark: scaled as a whole, a
        // volcano nearer than the far plane stayed at its true depth and its low-poly cone poked through the real one
        // (the sky-coloured streak and smooth patches on volcano_far, runs 470-509).
        func p(_ w: V3) -> V4 {
            let d = w - eye
            let len = max(0.001, simd_length(d))
            let r: Float = place * (0.95 + 0.05 * min(1, len / Renderer.landmarkRange))
            return V4(d * (r / len), 1)
        }
        func tri(_ a: V4, _ b: V4, _ c: V4, _ col: V4, _ into: inout [SimpleVert]) {
            into.append(SimpleVert(pos: a, color: col)); into.append(SimpleVert(pos: b, color: col)); into.append(SimpleVert(pos: c, color: col))
        }
        for v in vols {
            let c = V3(v.x, Float(YOFF) + v.base, v.z)
            let dist = simd_length(V2(c.x - eye.x, c.z - eye.z))
            // Near: the real terrain shows it (until its centre is past the loaded area). Far: past the landmark range.
            guard dist > loaded + v.r * 0.2, dist < Renderer.landmarkRange else { continue }
            let haze: Float = 0.3 + 0.5 * Terrain.smooth(loaded, Renderer.landmarkRange, dist)
            func shade(_ base: V3, _ n: V3) -> V3 {
                let lit: Float = 0.32 + 0.68 * max(0, simd_dot(n, sun)) * day + 0.08
                return base * lit * hdrK * (1 - haze) + fog * haze
            }
            func height(_ t: Float) -> Float {
                let tc = v.crater / v.r
                if t <= tc { return v.rim }
                return v.base + v.peak * powf((1 - t) / (1 - tc), 1.55)
            }
            let seg = 28
            let rings: [Float] = [1.05, 0.85, 0.66, 0.5, 0.38, 0.28, v.crater / v.r]
            let rock = V3(0.2, 0.19, 0.19), foot = V3(0.3, 0.34, 0.26)
            func ringPoint(_ t: Float, _ i: Int) -> V3 {
                let a = Float(i) / Float(seg) * 2 * .pi
                let rr = t * v.r
                let hgt = t > 1 ? v.base - 6 : height(t)
                return V3(v.x + cosf(a) * rr, Float(YOFF) + hgt, v.z + sinf(a) * rr)
            }
            for ri in 0..<(rings.count - 1) {
                let t0 = rings[ri], t1 = rings[ri + 1]
                let col = t0 > 0.9 ? foot : rock * (t1 < 0.3 ? 0.85 : 1)
                for i in 0..<seg {
                    let a0 = ringPoint(t0, i), b0 = ringPoint(t0, i + 1)
                    let a1 = ringPoint(t1, i), b1 = ringPoint(t1, i + 1)
                    let n = simd_normalize(simd_cross(b0 - a0, a1 - a0) + V3(0, 1e-4, 0))
                    let up = n.y < 0 ? -n : n
                    // The foot fades into the fog, with a skirt hanging out of sight: alone past the loaded terrain the
                    // outer ring floated as a pale disc (volcano_horizon, run 482).
                    let cc = ri == 0 ? V4(fog, 1) : V4(shade(col, up), 1)
                    tri(p(a0), p(b0), p(a1), cc, &out); tri(p(b0), p(b1), p(a1), cc, &out)
                    if ri == 0 {
                        let a2 = a0 - V3(0, 60, 0), b2 = b0 - V3(0, 60, 0)
                        tri(p(a0), p(b0), p(b2), cc, &out); tri(p(a0), p(b2), p(a2), cc, &out)
                    }
                }
            }
            // Crater: the inner wall down to the glowing lava lake (brighter at night).
            let glowK: Float = (0.9 + 1.4 * (1 - day)) * hdrK
            let lava = V4(V3(1.0, 0.36, 0.08) * glowK * (1 - haze * 0.6) + fog * haze * 0.6, 1)
            let ctr = V3(v.x, Float(YOFF) + v.lavaLevel, v.z)
            let tc = v.crater / v.r
            for i in 0..<seg {
                let a = ringPoint(tc, i), b = ringPoint(tc, i + 1)
                let ia = V3(v.x + (a.x - v.x) * 0.8, ctr.y, v.z + (a.z - v.z) * 0.8)
                let ib = V3(v.x + (b.x - v.x) * 0.8, ctr.y, v.z + (b.z - v.z) * 0.8)
                let wall = V4(shade(rock * 0.6, V3(0, 1, 0)), 1)
                tri(p(a), p(b), p(ia), wall, &out); tri(p(b), p(ib), p(ia), wall, &out)
                tri(p(ctr), p(ia), p(ib), lava, &out)
            }
            // Smoke plume: crossed quads rising from the crater, widening, drifting downwind, fading.
            let t = Float(game.time.truncatingRemainder(dividingBy: 600))
            let windA: Float = 0.6
            for j in 0..<7 {
                let fj = Float(j)
                let rise = fj * 26 + (t * 1.5).truncatingRemainder(dividingBy: 26)
                let size = v.crater * (0.5 + fj * 0.28)
                let drift = V3(cosf(windA), 0, sinf(windA)) * rise * 0.45
                let ctrS = V3(v.x, Float(YOFF) + v.rim + 6 + rise, v.z) + drift
                let alpha: Float = 0.42 * (1 - fj / 7)
                // By night the plume is dark, its lower puffs lit orange by the lava under them.
                let lavaLit: Float = (1 - day) * max(0, 1 - fj / 3) * 0.55
                let grey = (V3(0.42, 0.41, 0.42) * (0.18 + 0.82 * day) + V3(1.0, 0.38, 0.1) * lavaLit) * hdrK
                let sc = V4(grey * (1 - haze) + fog * haze, alpha)
                for (ux, uz) in [(Float(1), Float(0)), (Float(0), Float(1))] {
                    let side = V3(ux, 0, uz) * size
                    let q0 = ctrS - side - V3(0, size * 0.6, 0), q1 = ctrS + side - V3(0, size * 0.6, 0)
                    let q2 = ctrS + side + V3(0, size * 0.6, 0), q3 = ctrS - side + V3(0, size * 0.6, 0)
                    tri(p(q0), p(q1), p(q2), sc, &smoke); tri(p(q0), p(q2), p(q3), sc, &smoke)
                }
            }
        }
        // Ancient Spires: an eight-sided shaft with a broken crown.
        let grey = V3(0.43, 0.43, 0.44)
        for sp in spireCache(game) {
            let dist = simd_length(V2(sp.x - eye.x, sp.z - eye.z))
            guard dist > loaded + 16, dist < Renderer.spireRange else { continue }
            let haze: Float = 0.35 + 0.55 * Terrain.smooth(loaded, Renderer.spireRange, dist)
            let r: Float = 13
            for i in 0..<8 {
                let a0 = Float(i) / 8 * 2 * .pi + .pi / 8, a1 = Float(i + 1) / 8 * 2 * .pi + .pi / 8
                let top0 = sp.y + sp.w - 22 * (0.5 + 0.5 * sinf(a0 * 3)), top1 = sp.y + sp.w - 22 * (0.5 + 0.5 * sinf(a1 * 3))
                let b0 = V3(sp.x + cosf(a0) * r, sp.y - 2, sp.z + sinf(a0) * r), b1 = V3(sp.x + cosf(a1) * r, sp.y - 2, sp.z + sinf(a1) * r)
                let t0 = V3(b0.x, top0, b0.z), t1 = V3(b1.x, top1, b1.z)
                let n = simd_normalize(V3(cosf((a0 + a1) / 2), 0, sinf((a0 + a1) / 2)))
                let lit: Float = 0.32 + 0.68 * max(0, simd_dot(n, sun)) * day + 0.08
                let c = V4(grey * lit * hdrK * (1 - haze) + fog * haze, 1)
                tri(p(b0), p(b1), p(t1), c, &out); tri(p(b0), p(t1), p(t0), c, &out)
                // A fog-coloured skirt under the foot: past the loaded terrain the shaft hung over the horizon haze
                // (spire_horizon, run 482).
                let f4 = V4(fog, 1)
                let d0 = b0 - V3(0, 70, 0), d1 = b1 - V3(0, 70, 0)
                tri(p(d0), p(d1), p(b1), f4, &out); tri(p(d0), p(b1), p(b0), f4, &out)
            }
        }
        smokeStart = out.count
        out.append(contentsOf: smoke)
        landmarkSmoke = smoke
    }
}
