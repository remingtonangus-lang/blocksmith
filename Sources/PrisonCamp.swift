import Foundation
import simd

// P347 (Oct 16 19:53: a prison camp in the Ash Vault, "a German camp he can raid and liberate, freeing the prisoners").
// The Ashguard's prison camp (AshWar.frontSites, "prisoncamp", south-east of the citadel inside the Ember Line), built
// with weight, as the horror the Ash Vault is about:
//   the camp      a double fence of wire on iron stakes, four watchtowers with sentries and lamps, a gate with its
//                 gatehouse, the guards' block with the commandant's papers, a bare roll-call ground, and four long
//                 prisoners' huts of raw planks with tiers of bare bunks; nothing else.
//   prisoners     civilians in worn, patched, ill-fitting clothes, gaunt, some sitting on the bunks, some standing; they
//                 turn their heads toward him when he is near. They can't be hurt by anyone (no harm of them is ever
//                 possible or rewarded), and the Ashguard's soldiers never fight over them.
//   liberation    when no Ashguard soldier is left alive inside the wire and he is there, the camp is free (kept with the
//                 world: TownLaw.state.vaultObj "prisoncamp"): the prisoners rise, walk out through the gate and away
//                 up the road, and are gone once out of his sight. The guards stay down; the camp stays empty.
// Content (Meta store rules, docs/design/prison-camp.md): no real camp, people or insignia; no killing or cruelty
// shown, no bodies, no gas chambers or ovens, nothing for comedy; the prisoners are never targets.

enum Prisoners {
    static let posse = 7                            // Mob.posse marks a prisoner (saved)
    static let key = "prisoncamp"
    static var site: AshSite { AshWar.frontSites.first { $0.kind == "prisoncamp" }! }
    static var liberated: Bool { (TownLaw.state.vaultObj?[key] ?? 0) > 0 }
    static var freedAt = 0.0
    private static var clearFor: Float = 0
    private static var routes: [ObjectIdentifier: [V3]] = [:]
    static var freed = 0                            // (counter: prisoners that walked out of sight)

    static func setup(_ m: Mob, sitting: Bool) {
        m.posse = posse
        m.faction = Faction.none.rawValue
        m.persistent = true
        m.aggro = false
        m.sitting = sitting
        m.variant = Int(hash3(Int(m.pos.x * 4), 0x9A1, Int(m.pos.z * 4), 0x9A2) & 0xFFFF)
    }

    // Inside the camp's wire (blocks of margin).
    static func inside(_ p: V3, _ margin: Float = 0) -> Bool {
        let s = site
        return abs(p.x - Float(s.x) - 0.5) <= Float(s.r) + margin && abs(p.z - Float(s.z) - 0.5) <= Float(s.r) + margin
    }

    // A point of the camp's own frame (AshSites: u to the right of the facing, v toward the gate), on the ground.
    static func at(_ u: Float, _ v: Float) -> V3 {
        let s = site, f = AshWar.Frame(s)
        return V3(Float(s.x) + 0.5 + u * Float(-f.fz) + v * Float(f.fx), Float(AshWar.ground + 1), Float(s.z) + 0.5 + u * Float(f.fx) + v * Float(f.fz))
    }
    static let huts: [(Int, Int)] = [(-26, -19), (-14, -7), (7, 14), (19, 26)]     // (AshSites "prisoncamp": u0, u1; v -24...-6)
    static func exits() -> (gate: V3, beyond: V3) { (at(0, Float(site.r + 3)), at(0, Float(site.r + 44))) }

    // The way out from where he stands: out of his hut's door, across the roll-call ground, through the gate and away.
    static func route(from p: V3) -> [V3] {
        let s = site, f = AshWar.Frame(s)
        let dx = p.x - Float(s.x) - 0.5, dz = p.z - Float(s.z) - 0.5
        let u = Float(-f.fz) * dx + Float(f.fx) * dz, v = Float(f.fx) * dx + Float(f.fz) * dz
        var r: [V3] = []
        if v < -5, let h = huts.first(where: { u >= Float($0.0) && u <= Float($0.1) }) {
            let mid = Float((h.0 + h.1) / 2)
            r += [at(mid, v), at(mid, -6), at(mid, -3)]
        }
        let (gate, beyond) = exits()
        return r + [at(0, 0), at(0, Float(s.r - 4)), gate, beyond]
    }

    // Once a second (Game.ashTick): the camp's liberation.
    static func tick(_ g: Game) {
        guard g.dim.dim == .deep, DeepGen.inVault(g.player.pos.y) else { return }
        if !liberated {
            guard inside(g.player.pos, 2), g.alive else { clearFor = 0; return }
            let held = g.mobs.mobs.contains { $0.health > 0 && $0.posse != posse && ($0.faction == Faction.ashguard.rawValue || $0.kind.ash)
                && !$0.kind.ashVehicle && inside($0.pos, 3) }
            let anyPrisoner = g.mobs.mobs.contains { $0.posse == posse }
            clearFor = held || !anyPrisoner ? 0 : clearFor + 1
            guard clearFor >= 3 else { return }
            var m = TownLaw.state.vaultObj ?? [:]
            m[key] = 1
            TownLaw.state.vaultObj = m
            freedAt = g.clock
            g.sfx(.ironDoorOpen, 1, at: exits().gate)
        }
        // Free: out of sight, they are gone.
        let p = g.player.pos
        g.mobs.mobs.removeAll { m in
            guard m.posse == posse, simd_length(m.pos - p) > 56, !inside(m.pos, -2) || g.clock - freedAt > 300 else { return false }
            routes[ObjectIdentifier(m)] = nil
            freed += 1
            return true
        }
    }
}

extension Mob {
    // A prisoner's whole mind: before the camp is free, still (heads turn to him); after, out through the gate and away.
    func prisonerAI(_ dt: Float, _ g: Game) -> Float {
        aggro = false
        strafe = 0
        faceGoal = nil
        health = max(health, spec.health)              // nothing wears them down (fire, contact, effects)
        let toP = g.player.pos - pos
        let near = simd_length(toP) < 7
        if !Prisoners.liberated {
            headYaw = near ? max(-0.9, min(0.9, angleDiff(atan2f(-toP.x, -toP.z), yaw))) : headYaw * 0.9
            return 0
        }
        if sitting { sitting = false; aiTimer = Float(hash3(Int(pos.x), 3, Int(pos.z), 0x9A3) % 30) / 10 }  // they rise, one by one
        if aiTimer > 0 { return 0 }
        let id = ObjectIdentifier(self)
        var route = Prisoners.routesFor(id) ?? []
        if route.isEmpty {
            route = Prisoners.route(from: pos)
            Prisoners.setRoute(id, route)
        }
        guard let next = route.first else { return 0 }
        if simd_length(V2(next.x - pos.x, next.z - pos.z)) < 0.8 {
            route.removeFirst()
            Prisoners.setRoute(id, route)
            if route.isEmpty { return 0 }
        }
        face(route[0])
        headYaw = 0
        return spec.speed * 0.6
    }

    private func angleDiff(_ a: Float, _ b: Float) -> Float {
        var d = a - b
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }
}

extension Prisoners {
    static func routesFor(_ id: ObjectIdentifier) -> [V3]? { routes[id] }
    static func setRoute(_ id: ObjectIdentifier, _ r: [V3]) { routes[id] = r.isEmpty ? [] : r }
}

// A prisoner: gaunt, in worn and patched civilian clothes too big for him (front toward -Z, feet at y 0). Sitting: the
// thighs forward, the shins hanging, hunched.
func prisonerParts(_ m: Mob, swing: Float) -> [Part] {
    let h = UInt32(truncatingIfNeeded: m.variant) &* 2654435761
    let cloths = [V3(0.37, 0.36, 0.34), V3(0.33, 0.3, 0.26), V3(0.29, 0.29, 0.31), V3(0.4, 0.35, 0.28)]
    let coat = cloths[Int(h % 4)], trousers = cloths[Int(h >> 3 % 4)] * 0.85, patch = coat * 0.72 + V3(0.04, 0.03, 0.02)
    let skin = Livery.skins[Int(h >> 6) % Livery.skins.count] * 0.86, hair = Livery.hairs[Int(h >> 9) % Livery.hairs.count]
    let shoes = V3(0.16, 0.12, 0.09)
    var p: [Part] = []
    func b(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = 6,
           pv: V3 = .zero, rx: Float = 0, rz: Float = 0) {
        p.append(Part(mn: V3(x0, y0, z0), mx: V3(x1, y1, z1), pivot: pv, rotX: rx, rotZ: rz, color: c, pattern: pat))
    }
    let sit = m.sitting
    let hip: Float = sit ? 7 : 12
    let lean: Float = sit ? 0.32 : 0.12                    // hunched
    // Legs: thin, the trousers loose; walking swings them, sitting folds them forward over the bunk's edge.
    for s: Float in [-1, 1] {
        let x0: Float = s < 0 ? -3.2 : 0.4, x1: Float = s < 0 ? -0.4 : 3.2
        if sit {
            b(x0, hip - 1.6, -6, x1, hip + 1, 1, trousers)                           // thigh, forward
            b(x0, 0, -6.5, x1, hip - 1.6, -3.8, trousers)                            // shin, hanging
            b(x0 - 0.2, 0, -8, x1 + 0.2, 1.5, -3.6, shoes, 10)
        } else {
            let pv = V3((x0 + x1) / 2, hip, 0.5), a = swing * s
            b(x0, 1.5, -1, x1, hip, 2, trousers, 6, pv: pv, rx: a)
            b(x0 - 0.2, 0, -2.5, x1 + 0.2, 1.6, 2.2, shoes, 10, pv: pv, rx: a)
        }
    }
    // Body: a coat too big for him, a patch on it, the shoulders forward.
    let tp = V3(0, hip, 0.5)
    b(-4, hip, -1.6, 4, hip + 11, 2.6, coat, 6, pv: tp, rx: lean)
    b(-4.15, hip + 3, -1.75, -1.2, hip + 6, -1.5, patch, 6, pv: tp, rx: lean)
    b(-4.2, hip - 0.6, -1.8, 4.2, hip + 1.2, 2.8, coat * 0.8, 6, pv: tp, rx: lean)      // the hem
    // Arms: thin, hanging (resting on the knees when sitting), the sleeves past the wrists.
    for s: Float in [-1, 1] {
        let x0: Float = s < 0 ? -6.2 : 4, x1: Float = s < 0 ? -4 : 6.2
        let sp = V3((x0 + x1) / 2, hip + 10.5, 0.5)
        let a: Float = sit ? -0.75 : -swing * s * 0.8
        b(x0, hip + 1.5, -1, x1, hip + 11, 1.6, coat, 6, pv: sp, rx: a)
        b(x0 + 0.3, hip, -0.8, x1 - 0.3, hip + 1.6, 1.4, skin, 0, pv: sp, rx: a)
    }
    // Head: hollow-cheeked, the hair cropped short; some wear a worn cap.
    let hp = V3(0, hip + 11, 0)
    let hy = hip + 11
    let hlean: Float = lean * 1.3
    b(-2.8, hy, -3.2, 2.8, hy + 6, 2, skin, 0, pv: hp, rx: hlean)
    b(-2.9, hy + 4.8, -2.4, 2.9, hy + 6.3, 2.1, hair, 0, pv: hp, rx: hlean)
    b(-2, hy + 3.4, -3.3, -0.8, hy + 4, -3.15, V3(0.08, 0.07, 0.06), 0, pv: hp, rx: hlean)
    b(0.8, hy + 3.4, -3.3, 2, hy + 4, -3.15, V3(0.08, 0.07, 0.06), 0, pv: hp, rx: hlean)
    b(-2.85, hy + 1.6, -3.0, -2.6, hy + 3, -1.2, skin * 0.8, 0, pv: hp, rx: hlean)        // sunken cheeks
    b(2.6, hy + 1.6, -3.0, 2.85, hy + 3, -1.2, skin * 0.8, 0, pv: hp, rx: hlean)
    if h >> 12 % 3 == 0 {
        b(-3.1, hy + 5.6, -3.4, 3.1, hy + 7, 2.3, coat * 0.6, 6, pv: hp, rx: hlean)        // cap
        b(-2.6, hy + 5.4, -4.6, 2.6, hy + 5.9, -3.2, coat * 0.55, 6, pv: hp, rx: hlean)    // its peak
    }
    return p
}
