import Foundation
import simd

// P436 (Remington, Oct 24 15:44-15:45 in hell: "What I'm not seeing is enough mobs... I need a greater variety of them,
// maybe say two mobs specific to each biome... the purple biome won't be that hostile"). Each of hell's five lands now
// has two creatures of its own, original in look and habit; they are kinds of hell's own (Scorchling, Searwing,
// Slagthrower: Mob.variant picks the creature), so they share those kinds' caps, saves and spawn rules.
//   Cinder Plains     Cinder Hound (scorchling 2): a lean coal-black hound with a glowing split down its back, in
//                     pairs or threes; long low lunges, a burning bite. With the Slagthrower (the plains' brute).
//   Ash Dunes         Dune Crawler (scorchling 3): a long, low, bone-plated crawler the colour of the drifts; slow, no
//                     leaps, a heavy bite. Ash Wraith (searwing 2): a ragged pale shroud that glides low over the dunes
//                     and dives without a sound until it screams.
//   Charwood Thicket  Charwood Lurker (slagthrower 1): a burnt stump that stands still among the trees until you are
//                     close, then rears up and lobs burning pods. Emberkite (searwing 3): a small fast ember-bird with
//                     long streamer tails, quick shallow dives.
//   Gloamwood         the Gloamling (scorchling 1) and the Gloamwing (searwing 1) of P336; the violet wood is the
//                     quiet land: both go about their own business and only fight back once hurt.
//   Ghostglass Spires Shard Skitter (scorchling 4): a crab of black glass with crystal spines, quick and sidelong.
//                     Glass Wight (slagthrower 2): a tall figure of black glass crowned with violet crystal that
//                     throws shards of cold ghost fire.
enum HellBiomeMobs {
    // The creature's name, for death messages.
    static func name(_ m: Mob) -> String {
        switch (m.kind, m.variant) {
        case (.scorchling, 1): return "Gloamling"
        case (.scorchling, 2): return "Cinder Hound"
        case (.scorchling, 3): return "Dune Crawler"
        case (.scorchling, 4): return "Shard Skitter"
        case (.searwing, 1): return "Gloamwing"
        case (.searwing, 2): return "Ash Wraith"
        case (.searwing, 3): return "Emberkite"
        case (.slagthrower, 1): return "Charwood Lurker"
        case (.slagthrower, 2): return "Glass Wight"
        default: return m.spec.name
        }
    }

    static func aName(_ m: Mob) -> String {
        let n = name(m)
        return ("AEIOU".contains(n.first ?? "x") ? "an " : "a ") + n
    }

    // The variant of a kind for the land it spawns in (hellOwnSpawn).
    static func variant(_ k: MobKind, _ b: Biome) -> Int {
        switch (k, b) {
        case (.scorchling, .warpedForest): return 1
        case (.scorchling, .soulSandValley): return 3
        case (.scorchling, .basaltDeltas): return 4
        case (.scorchling, .crimsonForest): return 0
        case (.scorchling, _): return 2
        case (.searwing, .warpedForest): return 1
        case (.searwing, .soulSandValley): return 2
        case (.searwing, .crimsonForest): return 3
        case (.slagthrower, .crimsonForest): return 1
        case (.slagthrower, .basaltDeltas): return 2
        default: return 0
        }
    }

    // Pack sizes and health by creature (the kinds' specs are the Scorchling's, Searwing's and Slagthrower's).
    static func pack(_ v: Int) -> ClosedRange<Int> { [5...8, 4...6, 2...3, 1...2, 3...5][min(4, max(0, v))] }
    static func setup(_ m: Mob) {
        switch (m.kind, m.variant) {
        case (.scorchling, 2): m.health = 14
        case (.scorchling, 3): m.health = 22
        case (.scorchling, 4): m.health = 9
        case (.searwing, 2): m.health = 14
        case (.searwing, 3): m.health = 8
        case (.slagthrower, 1): m.health = 40
        case (.slagthrower, 2): m.health = 30
        default: break
        }
    }

    // The quiet land's creatures fight only once hurt.
    static func peaceable(_ m: Mob) -> Bool { m.variant == 1 && (m.kind == .scorchling || m.kind == .searwing) }

    static func parts(_ m: Mob, swing: Float) -> [Part]? {
        switch (m.kind, m.variant) {
        case (.scorchling, 2): return houndParts(m, swing: swing)
        case (.scorchling, 3): return crawlerParts(m, swing: swing)
        case (.scorchling, 4): return skitterParts(m, swing: swing)
        case (.searwing, 2): return wraithParts(m)
        case (.searwing, 3): return kiteParts(m)
        case (.slagthrower, 1): return lurkerParts(m, swing: swing)
        case (.slagthrower, 2): return wightParts(m, swing: swing)
        default: return nil
        }
    }

    // MARK: Models (1/16 block units, facing -Z)

    private static func houndParts(_ m: Mob, swing: Float) -> [Part] {
        let coal = V3(0.09, 0.07, 0.07), ash = V3(0.22, 0.18, 0.17), hot = V3(2.5, 0.85, 0.15)
        let s = swing * 1.5
        var p: [Part] = [
            box(-2.5, 4, -6, 5, 4, 12, coal, 4),                                                       // body
            box(-0.6, 8, -5.5, 1.2, 0.5, 11, hot).withPattern(9),                                      // the glowing split
            Part(mn: V3(-2, 5, -10), mx: V3(2, 9, -6), pivot: V3(0, 7, -6), rotX: -0.1, color: coal, pattern: 4),    // head
            Part(mn: V3(-1.3, 4.6, -13), mx: V3(1.3, 6.8, -10), pivot: V3(0, 7, -6), rotX: -0.1, color: ash, pattern: 4),   // muzzle
            Part(mn: V3(-1.6, 7.4, -10.3), mx: V3(-0.6, 8.2, -9.9), pivot: V3(0, 7, -6), color: hot, pattern: 9),
            Part(mn: V3(0.6, 7.4, -10.3), mx: V3(1.6, 8.2, -9.9), pivot: V3(0, 7, -6), color: hot, pattern: 9),
            Part(mn: V3(-1.9, 9, -8), mx: V3(-0.9, 11, -7), pivot: V3(-1.4, 9, -7.5), rotX: 0.4, color: coal),     // ears
            Part(mn: V3(0.9, 9, -8), mx: V3(1.9, 11, -7), pivot: V3(1.4, 9, -7.5), rotX: 0.4, color: coal),
            Part(mn: V3(-0.5, 6.5, 6), mx: V3(0.5, 7.5, 12), pivot: V3(0, 7, 6), rotX: -0.5 + swing * 0.4, color: hot * 0.8, pattern: 9),   // tail
        ]
        for (x, z, ph) in [(-2.4, -5.0, s), (1.0, -5.0, -s), (-2.4, 4.0, -s), (1.0, 4.0, s)] as [(Float, Float, Float)] {
            p.append(Part(mn: V3(x, 0, z), mx: V3(x + 1.4, 5, z + 1.4), pivot: V3(x + 0.7, 5, z + 0.7), rotX: ph, color: coal))
        }
        return p
    }

    private static func crawlerParts(_ m: Mob, swing: Float) -> [Part] {
        let hide = V3(0.62, 0.58, 0.52), bone = V3(0.82, 0.78, 0.68), dark = V3(0.2, 0.17, 0.15), eye = V3(1.6, 0.4, 0.2)
        var p: [Part] = [box(-3, 1.5, -9, 6, 3, 18, hide, 4)]
        for i in 0..<5 {                                                                              // bone plates down its back
            let z = -8 + Float(i) * 3.4
            p.append(box(-3.4, 4.2, z, 6.8, 1.2, 2.8, bone, 5))
        }
        p += [
            box(-2.6, 1.2, -13, 5.2, 3, 4, hide, 4),                                                  // flat head
            box(-2.8, 0.6, -14, 1.2, 1.6, 2.4, bone, 5), box(1.6, 0.6, -14, 1.2, 1.6, 2.4, bone, 5),   // mandibles
            box(-2, 3.4, -13.3, 1, 0.8, 0.4, eye).withPattern(9), box(1, 3.4, -13.3, 1, 0.8, 0.4, eye).withPattern(9),
            box(-1.5, 1.6, 9, 3, 2, 5, hide * 0.9, 4),                                               // tail
        ]
        for i in 0..<4 {                                                                              // four pairs of short legs
            let z = -7 + Float(i) * 4.5, ph = (i % 2 == 0 ? swing : -swing) * 1.2
            p.append(Part(mn: V3(-5, 0, z), mx: V3(-3, 2, z + 1.2), pivot: V3(-3, 2, z), rotZ: 0.3, color: dark, rotY: ph * 0.6))
            p.append(Part(mn: V3(3, 0, z), mx: V3(5, 2, z + 1.2), pivot: V3(3, 2, z), rotZ: -0.3, color: dark, rotY: -ph * 0.6))
        }
        return p
    }

    private static func skitterParts(_ m: Mob, swing: Float) -> [Part] {
        let glass = V3(0.07, 0.06, 0.1), crystal = V3(1.1, 0.7, 2.2), ghost = V3(0.7, 1.9, 2.0)
        var p: [Part] = [
            box(-4, 2, -3, 8, 3, 6, glass, 11),                                                        // shell
            box(-3, 5, -2, 6, 1, 4, glass * 1.4, 11),
            box(-1.2, 3, -3.4, 0.9, 0.9, 0.4, ghost).withPattern(9), box(0.3, 3, -3.4, 0.9, 0.9, 0.4, ghost).withPattern(9),
            Part(mn: V3(-6.5, 2, -6), mx: V3(-4, 3.5, -2), pivot: V3(-4, 3, -2), color: glass, pattern: 11, rotY: 0.4 + swing * 0.5),   // claws
            Part(mn: V3(4, 2, -6), mx: V3(6.5, 3.5, -2), pivot: V3(4, 3, -2), color: glass, pattern: 11, rotY: -0.4 - swing * 0.5),
        ]
        for (x, z, r) in [(-2.5, -1.0, 0.3), (1.0, 0.5, -0.25), (-0.5, -1.5, 0.05), (2.0, -0.8, -0.4)] as [(Float, Float, Float)] {
            p.append(Part(mn: V3(x, 6, z), mx: V3(x + 0.9, 9.5, z + 0.9), pivot: V3(x + 0.45, 6, z + 0.45), rotX: r, rotZ: -r, color: crystal, pattern: 9))
        }
        for i in 0..<3 {
            let z = Float(-2 + i * 2), ph = (i % 2 == 0 ? swing : -swing) * 1.6
            p.append(Part(mn: V3(-7, 0, z), mx: V3(-4, 1, z + 0.8), pivot: V3(-4, 2, z), rotZ: 0.5 + ph * 0.3, color: glass))
            p.append(Part(mn: V3(4, 0, z), mx: V3(7, 1, z + 0.8), pivot: V3(4, 2, z), rotZ: -0.5 - ph * 0.3, color: glass))
        }
        return p
    }

    private static func wraithParts(_ m: Mob) -> [Part] {
        let s = m.hell?.s ?? .idle
        let shroud = V3(0.66, 0.63, 0.6), rag = V3(0.5, 0.48, 0.46), void = V3(0.04, 0.03, 0.03)
        let eye = s == .windup || s == .dive ? V3(2.6, 0.5, 0.3) : V3(1.2, 0.6, 0.4)
        let flow = sinf(m.walkPhase * 0.6)
        let sweep: Float = s == .dive ? 0.9 : 0.2
        var p: [Part] = [
            box(-3, 4, -3, 6, 6, 5, shroud, 4),                                                        // hood and shoulders
            box(-2.2, 5.2, -3.4, 4.4, 4, 0.6, void),                                                   // the face in the hood
            box(-1.5, 7, -3.6, 1, 0.8, 0.3, eye).withPattern(9), box(0.5, 7, -3.6, 1, 0.8, 0.3, eye).withPattern(9),
        ]
        for i in 0..<4 {                                                                              // trailing rags
            let x = Float(i * 2 - 3)
            let w = flow * 0.3 * (i % 2 == 0 ? 1 : -1)
            p.append(Part(mn: V3(x - 1, 0, 0), mx: V3(x + 1, 5, 9 + Float(i % 2) * 2), pivot: V3(x, 5, 1), rotX: sweep + w, color: rag, pattern: 4))
        }
        for side: Float in [-1, 1] {                                                                  // ragged wing-sleeves
            let rz = (side < 0 ? 1 : -1) * (0.2 + flow * 0.35)
            let (a, b): (Float, Float) = side < 0 ? (-13, -3) : (3, 13)
            p.append(Part(mn: V3(a, 6.5, -2), mx: V3(b, 7.1, 4), pivot: V3(side * 3, 7, 0), rotZ: rz, color: shroud, pattern: 4))
            p.append(Part(mn: V3(a + (side < 0 ? 2 : 0), 3.5, 1), mx: V3(b - (side < 0 ? 0 : 2), 6.6, 3.5), pivot: V3(side * 3, 7, 0), rotZ: rz, color: rag, pattern: 4))
        }
        return p
    }

    private static func kiteParts(_ m: Mob) -> [Part] {
        let s = m.hell?.s ?? .idle
        let plume = V3(0.42, 0.08, 0.04), ember = V3(2.6, 0.9, 0.2), beak = V3(0.3, 0.25, 0.2)
        let beat = sinf(m.walkPhase * (s == .dive ? 3 : 1.8)) * (s == .dive ? 0.3 : 0.9) + (s == .dive ? 0.7 : 0)
        var p: [Part] = [
            box(-1.5, 5, -4, 3, 2.5, 7, plume, 3),
            box(-1, 7.4, -3.5, 2, 0.4, 6, ember).withPattern(9),
            box(-1.3, 5.5, -7, 2.6, 2.4, 3, plume, 3),
            box(-0.4, 5.6, -9, 0.8, 0.8, 2, beak),
            box(-1.2, 6.8, -7.3, 0.6, 0.6, 0.3, ember).withPattern(9), box(0.6, 6.8, -7.3, 0.6, 0.6, 0.3, ember).withPattern(9),
        ]
        for side: Float in [-1, 1] {
            let rz = side < 0 ? beat : -beat
            let (a, b): (Float, Float) = side < 0 ? (-11, -1.5) : (1.5, 11)
            p.append(Part(mn: V3(a, 6.3, -3), mx: V3(b, 6.8, 2), pivot: V3(side * 1.5, 6.5, 0), rotZ: rz, color: plume, pattern: 3))
            p.append(Part(mn: V3(side < 0 ? a + 3 : a, 6.2, -1), mx: V3(side < 0 ? b : b - 3, 6.4, 0), pivot: V3(side * 1.5, 6.5, 0), rotZ: rz, color: ember, pattern: 9))
        }
        let trail = sinf(m.walkPhase * 1.1) * 0.25
        for x: Float in [-0.9, 0.3] {                                                                 // two long streamer tails
            p.append(Part(mn: V3(x, 5.4, 3), mx: V3(x + 0.6, 5.8, 14), pivot: V3(x, 5.6, 3), rotX: trail, color: ember * 0.8, pattern: 9))
        }
        return p
    }

    private static func lurkerParts(_ m: Mob, swing: Float) -> [Part] {
        let s = m.hell?.s ?? .idle
        let bark = V3(0.12, 0.09, 0.07), char = V3(0.2, 0.14, 0.1), ember = V3(2.4, 0.7, 0.15), pod = V3(2.8, 1.2, 0.3)
        // At rest it stands as a stump: arms down along the trunk, head sunk; awake it rears and the arms come up.
        let awake = s != .idle || m.aggro
        let arm: Float = s == .windup ? -2.4 : (s == .recover ? 1.6 : (awake ? swing * 0.5 - 0.3 : 0))
        var p: [Part] = [
            Part(mn: V3(-5, 0, -4), mx: V3(-1, 8, 4), pivot: V3(-3, 8, 0), rotX: awake ? swing * 0.6 : 0, color: bark, pattern: 4),   // root legs
            Part(mn: V3(1, 0, -4), mx: V3(5, 8, 4), pivot: V3(3, 8, 0), rotX: awake ? -swing * 0.6 : 0, color: bark, pattern: 4),
            Part(mn: V3(-6, 8, -5), mx: V3(6, 28, 5), pivot: V3(0, 8, 0), color: char, pattern: 4),                                    // the trunk
            Part(mn: V3(-5.5, 13, -5.4), mx: V3(-4, 24, -5), pivot: V3(0, 8, 0), color: ember, pattern: 9),                            // glowing cracks
            Part(mn: V3(2, 10, -5.4), mx: V3(3.2, 20, -5), pivot: V3(0, 8, 0), color: ember, pattern: 9),
            Part(mn: V3(-4, 28, -4), mx: V3(4, awake ? 33 : 30, 4), pivot: V3(0, 28, 0), color: bark, pattern: 4),                      // the broken top
            Part(mn: V3(-2.5, 25, -5.6), mx: V3(-1, 26.5, -5), pivot: V3(0, 8, 0), color: awake ? pod : char, pattern: awake ? 9 : 4), // eyes in the bark
            Part(mn: V3(1, 25, -5.6), mx: V3(2.5, 26.5, -5), pivot: V3(0, 8, 0), color: awake ? pod : char, pattern: awake ? 9 : 4),
            Part(mn: V3(-10, 10, -2), mx: V3(-6, 27, 2), pivot: V3(-8, 27, 0), rotX: awake ? -swing * 0.4 : 0, rotZ: awake ? -0.2 : 0, color: bark, pattern: 4),
            Part(mn: V3(6, 8, -2), mx: V3(10, 27, 2), pivot: V3(8, 27, 0), rotX: arm, color: bark, pattern: 4),
            Part(mn: V3(-8, 30, -1), mx: V3(-4, 31, 1), pivot: V3(-4, 30, 0), rotZ: 0.5, color: bark),                                 // snapped branches
            Part(mn: V3(4, 29, -1), mx: V3(9, 30, 1), pivot: V3(4, 29, 0), rotZ: -0.4, color: bark),
        ]
        if s == .windup { p.append(Part(mn: V3(6.5, 4, -2.5), mx: V3(9.5, 7, 0.5), pivot: V3(8, 27, 0), rotX: arm, color: pod, pattern: 9)) }
        return p
    }

    private static func wightParts(_ m: Mob, swing: Float) -> [Part] {
        let s = m.hell?.s ?? .idle
        let glass = V3(0.06, 0.05, 0.09), crystal = V3(1.2, 0.75, 2.4), ghost = V3(0.6, 2.0, 2.1)
        let arm: Float = s == .windup ? -2.5 : (s == .recover ? 1.7 : swing * 0.4)
        var p: [Part] = [
            Part(mn: V3(-3.5, 0, -2), mx: V3(-0.5, 14, 2), pivot: V3(-2, 14, 0), rotX: swing * 0.7, color: glass, pattern: 11),
            Part(mn: V3(0.5, 0, -2), mx: V3(3.5, 14, 2), pivot: V3(2, 14, 0), rotX: -swing * 0.7, color: glass, pattern: 11),
            box(-4.5, 14, -2.5, 9, 13, 5, glass, 11),                                                  // a narrow faceted body
            box(-1, 17, -2.9, 2, 7, 0.4, ghost).withPattern(9),                                       // the cold seam
            box(-3, 27, -3, 6, 6, 6, glass, 11),                                                       // head
            box(-2, 29.5, -3.4, 1.4, 1, 0.4, ghost).withPattern(9), box(0.6, 29.5, -3.4, 1.4, 1, 0.4, ghost).withPattern(9),
            Part(mn: V3(-8, 12, -1.5), mx: V3(-4.5, 27, 1.5), pivot: V3(-6, 27, 0), rotX: -swing * 0.4, color: glass, pattern: 11),
            Part(mn: V3(4.5, 12, -1.5), mx: V3(8, 27, 1.5), pivot: V3(6, 27, 0), rotX: arm, color: glass, pattern: 11),
        ]
        for (x, h, r) in [(-2.5, 6.0, 0.3), (-0.5, 9.0, 0.0), (1.5, 7.0, -0.3), (-1.5, 5.0, 0.15)] as [(Float, Float, Float)] {   // the crown
            p.append(Part(mn: V3(x, 33, -0.5), mx: V3(x + 1.2, 33 + h, 0.7), pivot: V3(x + 0.6, 33, 0), rotZ: r, color: crystal, pattern: 9))
        }
        if s == .windup { p.append(Part(mn: V3(4.5, 8, -2.5), mx: V3(8, 12, 1), pivot: V3(6, 27, 0), rotX: arm, color: ghost, pattern: 9)) }
        return p
    }
}
