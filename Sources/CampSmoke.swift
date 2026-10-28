import Foundation
import simd

// P331 (Oct 16 11:51, "I want smoke to be coming from the campsite, that way I can see it off in a distance"): every
// wild camp with a lit fire (hunters, traders, outlaws) sends up a tall column of soft puffs that reads from far off,
// drifting with the sky's wind, the foot of it lit orange by the fire at night. Drawn with the landmark smoke (blended,
// no depth write): inside the loaded terrain at its true place (hills in front hide it), past it on the far shell like
// the volcano plumes. Near the camp the campfire's own particle smoke (AmbientParticles) takes over, so the column
// fades in from 14 to 30 blocks away.
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
            guard dist > 14, dist < Renderer.campSmokeRange else { continue }
            let fadeIn = Terrain.smooth(14, 30, dist)        // P365 (a): the near fire smoke hands over closer
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

    // P365 (i, idea: "a faint glow over villages at night so he can spot them from far"): after dusk every village and
    // Capital city within reach lights the air over it: a wide, faint warm haze hanging over the rooftops, fading in as
    // the light goes and out again as he walks into the town. Drawn with the landmark smoke (true place inside the
    // loaded terrain, the far shell past it). Regions not yet planned are planned on a worker thread.
    static var townList: [V4] = []                  // (x, ground y, z, radius), refreshed every 3 s
    static var townAt: Double = -10
    static var townPlanning = false
    static var townBoxes: [(min: IVec3, max: IVec3, tone: FarTone)] = []   // P483: their far boxes (StructureStart.far)
    func townCache(_ game: Game) -> [V4] {
        if game.clock - Renderer.townAt < 3 { return Renderer.townList }
        Renderer.townAt = game.clock
        Renderer.townList.removeAll()
        Renderer.townBoxes.removeAll(keepingCapacity: true)
        guard let sc = (game.world.gen as? WorldGen)?.structures else { return [] }
        let p = game.player.pos
        var todo: [(StructureType, Int, Int)] = []
        // (Greywall bases: their far boxes only, no glow over them: radius 0.)
        for (name, radius) in [("village", Float(36)), ("capital_city", Float(80)), (Greywall.kind, Float(0))] {
            guard let t = sc.types.first(where: { $0.name == name }) else { continue }
            let span = t.spacing * CS
            let rx0 = floorDiv(Int(p.x), span), rz0 = floorDiv(Int(p.z), span)
            let n = Int(Renderer.campSmokeRange) / span + 1
            for rz in (rz0 - n)...(rz0 + n) { for rx in (rx0 - n)...(rx0 + n) {
                guard sc.isCached(t, regionX: rx, regionZ: rz) else { todo.append((t, rx, rz)); continue }
                guard let s = sc.start(t, regionX: rx, regionZ: rz) else { continue }
                let cx = Float(s.min.x + s.max.x) / 2, cz = Float(s.min.z + s.max.z) / 2
                if radius > 0 { Renderer.townList.append(V4(cx, Float(s.anchor.y), cz, radius)) }
                Renderer.townBoxes += s.far
            } }
        }
        if !todo.isEmpty && !Renderer.townPlanning {
            Renderer.townPlanning = true
            DispatchQueue.global(qos: .utility).async {
                for (t, rx, rz) in todo { _ = sc.start(t, regionX: rx, regionZ: rz) }
                Renderer.townPlanning = false
            }
        }
        return Renderer.townList
    }

    func townGlow(_ smoke: inout [SimpleVert], game: Game, eye: V3, loaded: Float, fog: V3, day: Float, hdrK: Float,
                  shell: (V3) -> V4) {
        let night = Terrain.smooth(0.55, 0.9, 1 - day)
        guard night > 0.01 else { return }
        let towns = townCache(game)
        guard !towns.isEmpty else { return }
        Renderer.campEye = eye
        let t = Float(game.time.truncatingRemainder(dividingBy: 600))
        for c in towns {
            let at3 = V3(c.x, c.y, c.z)
            let dist = simd_length(V2(c.x - eye.x, c.z - eye.z))
            guard dist > c.w, dist < Renderer.campSmokeRange else { continue }
            let fadeIn = Terrain.smooth(c.w, c.w * 2.5, dist)
            let fadeOut = 1 - Terrain.smooth(Renderer.campSmokeRange * 0.75, Renderer.campSmokeRange, dist)
            let inside = dist < loaded - 8
            func at(_ q: V3) -> V4 { inside ? V4(q - eye, 1) : shell(q) }
            let grow = max(1, dist / 400)
            let breathe: Float = 0.92 + 0.08 * sinf(t * 0.4 + c.x * 0.01)
            let a: Float = 0.16 * night * fadeIn * fadeOut * breathe
            guard a > 0.005 else { continue }
            let warm = V3(1.0, 0.62, 0.3) * 1.2 * hdrK
            // Two layers: a broad dim haze, and a smaller brighter heart low over the roofs.
            puff(&smoke, at3 + V3(0, 14, 0), c.w * 1.3 * grow, V4(warm, a), at)
            puff(&smoke, at3 + V3(0, 9, 0), c.w * 0.7 * grow, V4(warm * 1.15, a * 1.3), at)
        }
    }

    // P365 (a, "campfire smoke is yellow circles coming out of the ground"): a lit fire near the player sends up soft
    // grey smoke: round puffs clear at the rim, swelling and thinning as they rise from the top of the fire, swaying
    // and leaning with the wind, drawn with the blended landmark smoke. AmbientParticles notes the fires it finds.
    static var fires: [IVec3: Double] = [:]
    func fireSmoke(_ smoke: inout [SimpleVert], game: Game, eye: V3, day: Float, hdrK: Float) {
        guard !Renderer.fires.isEmpty else { return }
        Renderer.campEye = eye
        let now = game.clock
        let t = Float(game.time.truncatingRemainder(dividingBy: 600))
        let w = game.sky.wind
        let wind = V3(w.x, 0, w.y) * 0.6 + V3(0.25, 0, 0.1)
        let em = Game.emitters
        for (k, seen) in Renderer.fires {
            // Gone out, broken or far behind: forget it (a fire is found again within a few seconds when it is near).
            if now - seen > 8 || em[Int(game.world.block(k.x, k.y, k.z))] != Emitter.campfire.rawValue {
                Renderer.fires[k] = nil; continue
            }
            let base = V3(Float(k.x) + 0.5, Float(k.y) + 0.45, Float(k.z) + 0.5)
            let dist = simd_length(base - eye)
            guard dist < 40 else { continue }
            let near = 1 - Terrain.smooth(24, 40, dist)
            let phase = Float((k.x &* 7 &+ k.z &* 13) & 63)
            for j in 0..<16 {
                // Each puff rises 9 blocks over 6 s and starts again at the fire.
                let life = ((t + phase) / 6 + Float(j) / 16).truncatingRemainder(dividingBy: 1)
                let rise = life * 9
                let sway = V3(sinf(t * 0.7 + Float(j) * 1.9 + phase), 0, cosf(t * 0.6 + Float(j) * 2.3)) * (0.08 + rise * 0.06)
                let ctr = base + V3(0, 0.2 + rise, 0) + wind * rise * 0.3 + sway
                let size: Float = 0.22 + rise * 0.16
                let alpha = 0.42 * Terrain.smooth(0, 0.08, life) * (1 - life) * near
                guard alpha > 0.01 else { continue }
                let g: Float = 0.5 + 0.12 * life
                let rgb = V3(g, g, g * 1.02) * (0.2 + 0.8 * day) * hdrK
                puff(&smoke, ctr, size, V4(rgb, alpha)) { V4($0 - eye, 1) }
            }
            Renderer.plumeRising = true                 // (rebuilt every 2nd frame on the Quest while it rises)
        }
    }
}
