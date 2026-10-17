import Foundation
import simd

// P331 (Oct 16 11:51, "I want smoke to be coming from the campsite, that way I can see it off in a distance"): every
// wild camp with a lit fire (hunters, traders, outlaws) sends up a tall column of soft puffs that reads from far off,
// drifting with the sky's wind, the foot of it lit orange by the fire at night. Drawn with the landmark smoke (blended,
// no depth write): inside the loaded terrain at its true place (hills in front hide it), past it on the far shell like
// the volcano plumes. Near the camp the campfire's own particle smoke (AmbientParticles) takes over, so the column
// fades in from 40 to 80 blocks away.
extension Renderer {
    static let campSmokeRange: Float = 1100
    static let campSmokeKinds: Set<String> = ["camp_hunters", "camp_traders", "camp_outlaws"]
    static var campList: [V3] = []                  // fire spots (x, ground y, z), refreshed every 2 s
    static var campAt: Double = -10
    static var campPlanning = false

    // Lit camps within range. Regions not yet planned are planned on a worker thread (never on the frame).
    func campCache(_ game: Game) -> [V3] {
        if game.clock - Renderer.campAt < 2 { return Renderer.campList }
        Renderer.campAt = game.clock
        Renderer.campList.removeAll()
        guard let sc = (game.world.gen as? WorldGen)?.structures, let t = sc.types.first(where: { $0.name == "wild_camp" }) else { return [] }
        let span = t.spacing * CS
        let p = game.player.pos
        let rx0 = floorDiv(Int(p.x), span), rz0 = floorDiv(Int(p.z), span)
        let n = Int(Renderer.campSmokeRange) / span + 1
        var todo: [(Int, Int)] = []
        for rz in (rz0 - n)...(rz0 + n) { for rx in (rx0 - n)...(rx0 + n) {
            guard sc.isCached(t, regionX: rx, regionZ: rz) else { todo.append((rx, rz)); continue }
            guard let s = sc.start(t, regionX: rx, regionZ: rz), Renderer.campSmokeKinds.contains(s.kind) else { continue }
            Renderer.campList.append(V3(Float(s.anchor.x) + 0.5, Float(s.anchor.y), Float(s.anchor.z) + 0.5))
        } }
        if !todo.isEmpty && !Renderer.campPlanning {
            Renderer.campPlanning = true
            DispatchQueue.global(qos: .utility).async {
                for (rx, rz) in todo { _ = sc.start(t, regionX: rx, regionZ: rz) }
                Renderer.campPlanning = false
            }
        }
        return Renderer.campList
    }

    // A soft round puff facing the eye: an eight-sided fan, opaque-ish in the middle and clear at the rim (flat
    // squares read as glass panes in the sky).
    private func puff(_ smoke: inout [SimpleVert], _ c: V3, _ r: Float, _ col: V4, _ at: (V3) -> V4) {
        let eye = Renderer.campEye
        let toEye = simd_normalize(eye - c + V3(0, 1e-3, 0))
        let right = simd_normalize(simd_cross(V3(0, 1, 0), toEye) + V3(1e-4, 0, 0)), up = simd_cross(toEye, right)
        let mid = at(c), rim = V4(col.x, col.y, col.z, 0)
        var prev = at(c + right * r)
        for k in 1...8 {
            let a = Float(k) / 8 * 2 * .pi
            let q = at(c + (right * cosf(a) + up * sinf(a) * 0.85) * r)
            smoke.append(SimpleVert(pos: mid, color: col)); smoke.append(SimpleVert(pos: prev, color: rim)); smoke.append(SimpleVert(pos: q, color: rim))
            prev = q
        }
    }
    static var campEye = V3.zero

    // Appends the camp smoke columns to the blended landmark smoke. `shell` puts a far point on the far-plane shell.
    func campSmoke(_ smoke: inout [SimpleVert], game: Game, eye: V3, loaded: Float, fog: V3, day: Float, hdrK: Float,
                   shell: (V3) -> V4) {
        let camps = campCache(game)
        guard !camps.isEmpty else { return }
        Renderer.campEye = eye
        let t = Float(game.time.truncatingRemainder(dividingBy: 600))
        let w = game.sky.wind
        let wind = V3(w.x, 0, w.y)
        let night = 1 - day
        for c in camps {
            let dist = simd_length(V2(c.x - eye.x, c.z - eye.z))
            guard dist > 40, dist < Renderer.campSmokeRange else { continue }
            let fadeIn = Terrain.smooth(40, 80, dist)
            let fadeOut = 1 - Terrain.smooth(Renderer.campSmokeRange * 0.75, Renderer.campSmokeRange, dist)
            let haze: Float = 0.15 + 0.6 * Terrain.smooth(80, Renderer.campSmokeRange, dist)
            let inside = dist < loaded - 8
            func at(_ q: V3) -> V4 { inside ? V4(q - eye, 1) : shell(q) }
            // Far off a puff never shrinks below a few pixels' worth, so the column still reads as a thin line.
            let grow = max(1, dist / 150)
            for j in 0..<10 {
                let fj = Float(j)
                let rise = fj * 12 + (t * 1.5).truncatingRemainder(dividingBy: 12)
                let size = (1.6 + rise * 0.12) * grow
                let ctr = c + V3(0, 3 + rise, 0) + wind * rise * 0.35
                let alpha: Float = 0.85 * (1 - rise / 130) * fadeIn * fadeOut
                guard alpha > 0.01 else { continue }
                // Pale grey by day, dark by night with the lowest puffs lit orange by the fire under them.
                let fireLit: Float = night * 0.8 * max(0, 1 - rise / 14)
                let grey = (V3(0.58, 0.58, 0.6) * (0.15 + 0.85 * day) + V3(1.0, 0.45, 0.15) * fireLit) * hdrK
                let rgb = grey * (1 - haze) + fog * haze
                puff(&smoke, ctr, size, V4(rgb, alpha), at)
            }
            // Night: the fire itself as a small glow at the foot of the column (a point of light across the dark land).
            guard night > 0.3 else { continue }
            let gs: Float = 0.8 * grow
            let flicker: Float = 0.85 + 0.15 * sinf(t * 9 + c.x)
            let glowA: Float = min(1, (night - 0.3) * 2) * fadeIn * fadeOut * flicker
            let glow = V4(V3(1.0, 0.55, 0.2) * 1.4 * hdrK * (1 - haze * 0.6) + fog * haze * 0.6, glowA)
            let g0 = c + V3(0, 0.8, 0)
            let top = at(g0 + V3(0, gs, 0)), bot = at(g0 - V3(0, gs * 0.6, 0))
            for (sx, sz) in [(gs, Float(0)), (Float(0), gs)] {
                let l = at(g0 - V3(sx, 0, sz)), r = at(g0 + V3(sx, 0, sz))
                smoke.append(SimpleVert(pos: l, color: glow)); smoke.append(SimpleVert(pos: r, color: glow)); smoke.append(SimpleVert(pos: top, color: glow))
                smoke.append(SimpleVert(pos: r, color: glow)); smoke.append(SimpleVert(pos: l, color: glow)); smoke.append(SimpleVert(pos: bot, color: glow))
            }
        }
    }
}
