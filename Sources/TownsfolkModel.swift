import Foundation
import simd

// Townsfolk models: people with human proportions (about 1.95 blocks), dressed for their role, with a face, hair,
// headgear and the tool or weapon they carry. Model pixels (1/16 block), feet at y 0, facing -Z, Part rotation
// convention as in Mob.swift (rotX > 0 = forward). Arms swing against the legs when walking; the right arm raises
// the weapon when they fight and strikes in an arc on each blow; both arms go up when a gun is pointed at them.
// Every colour comes from the role plus the person's look seed, so a town reads as many different people.

struct TownLook {
    var skin: V3, hair: V3, shirt: V3, legs: V3, boots: V3
    var vest: V3? = nil, apron: V3? = nil, coat: V3? = nil, overalls: V3? = nil, skirt: V3? = nil
    var hat: Hat = .none, hatColor = V3(0.3, 0.22, 0.15)
    var beard = false, longHair = false, bald = false, rolledSleeves = false, badge = false, bowTie: V3? = nil
    var glasses = false, tape = false, gunBelt = false

    enum Hat { case none, wideBrim, flatCap, bowler, bonnet, cap, straw }

    static let shirts = [V3(0.86, 0.82, 0.72), V3(0.9, 0.9, 0.87), V3(0.42, 0.5, 0.62), V3(0.6, 0.27, 0.22), V3(0.55, 0.43, 0.3),
                         V3(0.6, 0.6, 0.58), V3(0.36, 0.42, 0.3)]
    static let trousers = [V3(0.24, 0.29, 0.4), V3(0.4, 0.3, 0.21), V3(0.37, 0.36, 0.35), V3(0.16, 0.15, 0.15), V3(0.6, 0.5, 0.37)]
    static let dresses = [V3(0.45, 0.3, 0.42), V3(0.3, 0.4, 0.55), V3(0.56, 0.5, 0.4), V3(0.34, 0.44, 0.31), V3(0.6, 0.32, 0.27),
                          V3(0.28, 0.26, 0.3)]

    static func of(_ m: Mob) -> TownLook {
        let v = m.villager
        let k = v?.look ?? Int(Townsfolk.mix(Int(m.pos.x), Int(m.pos.z), 7) & 0xFFFF)
        let woman = Townsfolk.isWoman(v)
        let role = v?.role ?? (m.baby ? "child" : "worker")
        var l = TownLook(skin: Livery.skins[k % Livery.skins.count], hair: Livery.hairs[(k / 5) % Livery.hairs.count],
                         shirt: shirts[(k / 3) % shirts.count], legs: trousers[(k / 7) % trousers.count], boots: V3(0.2, 0.14, 0.1))
        if woman { l.skirt = dresses[(k / 11) % dresses.count]; l.longHair = true }
        else { l.beard = !m.baby && k % 3 == 0 }
        switch role {
        case "deputy":
            l.shirt = V3(0.72, 0.62, 0.46); l.vest = V3(0.26, 0.18, 0.12); l.badge = true; l.gunBelt = true
            l.hat = .wideBrim; l.hatColor = V3(0.32, 0.24, 0.16); l.skirt = nil; l.legs = trousers[(k / 7) % 2 == 0 ? 0 : 3]
        case "farmer":
            l.overalls = l.skirt == nil ? V3(0.25, 0.32, 0.46) : nil; l.hat = .straw; l.hatColor = V3(0.86, 0.74, 0.44)
            l.shirt = [V3(0.62, 0.24, 0.2), V3(0.36, 0.44, 0.6), V3(0.86, 0.82, 0.72)][k % 3]
        case "elder":
            l.hair = V3(0.78, 0.77, 0.74); l.bald = !woman && k % 2 == 0
            l.hat = woman ? .bonnet : .none; l.hatColor = V3(0.82, 0.8, 0.74); l.glasses = true
            if l.skirt != nil { l.skirt = V3(0.25, 0.24, 0.27) }
        case "child":
            l.beard = false; l.hat = k % 3 == 0 ? .flatCap : .none; l.hatColor = V3(0.4, 0.36, 0.3)
        case "shopkeeper":
            switch v?.shopKind {
            case .general?: l.shirt = V3(0.92, 0.91, 0.87); l.vest = V3(0.14, 0.13, 0.13); l.apron = V3(0.85, 0.82, 0.72)
            case .gunsmith?: l.shirt = V3(0.58, 0.58, 0.56); l.apron = V3(0.26, 0.19, 0.13); l.hat = .flatCap; l.hatColor = V3(0.24, 0.24, 0.25); l.gunBelt = true
            case .butcher?: l.shirt = V3(0.92, 0.92, 0.9); l.apron = V3(0.94, 0.92, 0.9); l.hat = .cap; l.hatColor = V3(0.94, 0.94, 0.92); l.rolledSleeves = true
            case .doctor?: l.shirt = V3(0.93, 0.93, 0.9); l.coat = V3(0.12, 0.12, 0.13); l.hat = .bowler; l.hatColor = V3(0.1, 0.1, 0.1); l.glasses = true
            case .stable?: l.shirt = V3(0.5, 0.38, 0.26); l.vest = V3(0.36, 0.26, 0.18); l.hat = .wideBrim; l.hatColor = V3(0.62, 0.5, 0.34)
            case .tailor?: l.shirt = V3(0.93, 0.92, 0.88); l.vest = V3(0.45, 0.12, 0.16); l.tape = true; l.glasses = true
            case .blacksmith?: l.shirt = V3(0.45, 0.44, 0.42); l.apron = V3(0.3, 0.2, 0.12); l.rolledSleeves = true; l.skirt = nil
            case .saloon?: l.shirt = V3(0.93, 0.92, 0.88); l.vest = V3(0.5, 0.12, 0.1); l.bowTie = V3(0.08, 0.08, 0.08)
            case nil: break
            }
        case "craftsman":
            l.apron = V3(0.42, 0.3, 0.18); l.hat = k % 2 == 0 ? .flatCap : .none; l.hatColor = V3(0.3, 0.28, 0.26)
        default:
            if k % 4 == 0 { l.hat = .wideBrim; l.hatColor = [V3(0.34, 0.26, 0.18), V3(0.22, 0.2, 0.19), V3(0.55, 0.45, 0.32)][(k / 4) % 3] }
            else if k % 4 == 1 { l.hat = .flatCap; l.hatColor = V3(0.36, 0.34, 0.3) }
            if l.skirt == nil && k % 3 == 1 { l.vest = V3(0.3, 0.26, 0.22) }
        }
        return l
    }
}

func townsfolkParts(_ m: Mob, swing: Float) -> [Part] {
    let l = TownLook.of(m)
    let w = m.townWeapon
    var p: [Part] = []
    p.reserveCapacity(48)
    func b(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = Pat.cloth) {
        p.append(Part(mn: V3(x0, y0, z0), mx: V3(x1, y1, z1), color: c, pattern: pat))
    }
    // Legs (with boots) swing from the hips.
    for (side, ph) in [(Float(-1), Float(1)), (1, -1)] {
        let x0: Float = side < 0 ? -3.8 : 0.2, x1: Float = side < 0 ? -0.2 : 3.8
        let pivot = V3(side * 2, 13, 0)
        p.append(Part(mn: V3(x0, 3, -1.8), mx: V3(x1, 13, 1.8), pivot: pivot, rotX: swing * ph, color: l.overalls ?? l.legs, pattern: Pat.cloth))
        p.append(Part(mn: V3(x0 - 0.15, 0, -2.3), mx: V3(x1 + 0.15, 3.4, 1.95), pivot: pivot, rotX: swing * ph, color: l.boots, pattern: Pat.leather))
    }
    // Skirt over the legs (women), a long coat (the doctor).
    if let s = l.skirt { b(-4.6, 2.6, -2.9, 4.6, 14, 2.9, s) }
    if let c = l.coat { b(-4.5, 7, -2.5, 4.5, 23.6, 2.5, c); b(-0.5, 15, -2.6, 0.5, 23.4, -2.45, l.shirt) }
    // Torso, belt, vest / overalls / apron, details.
    b(-4.2, 13, -2.2, 4.2, 23.5, 2.2, l.shirt)
    if l.coat == nil {
        b(-4.3, 13, -2.3, 4.3, 14.2, 2.3, V3(0.16, 0.11, 0.08), Pat.leather)
        b(-0.8, 13.1, -2.42, 0.8, 14.1, -2.3, V3(0.75, 0.66, 0.4), Pat.metal)                 // buckle
    }
    if l.gunBelt { b(-4.5, 12.4, -2.5, 4.5, 13.4, 2.5, V3(0.3, 0.2, 0.12), Pat.leather); b(3.6, 9.5, -1.2, 4.9, 13, 1.0, V3(0.2, 0.14, 0.1), Pat.leather) }
    if let v = l.vest {
        b(-4.35, 14.2, -2.35, -0.6, 23.3, 2.35, v); b(0.6, 14.2, -2.35, 4.35, 23.3, 2.35, v)
        b(-0.6, 14.2, 0, 0.6, 23.3, 2.35, v)
    }
    if let o = l.overalls {
        b(-3, 13, -2.4, 3, 20, -2.25, o)
        b(-2.6, 20, -2.4, -1.6, 23.5, -2.25, o); b(1.6, 20, -2.4, 2.6, 23.5, -2.25, o)
    }
    if let a = l.apron {
        b(-3.6, 6, -2.55, 3.6, 21, -2.35, a, Pat.leather)
        b(-2.4, 21, -2.55, 2.4, 23.4, -2.35, a, Pat.leather)
        if m.villager?.shopKind == .butcher { b(-1.5, 14, -2.6, 0.2, 15.5, -2.5, V3(0.62, 0.16, 0.14)); b(1, 10, -2.6, 2, 11, -2.5, V3(0.6, 0.18, 0.15)) }
    }
    if l.badge { b(-3.4, 19.5, -2.5, -1.8, 21.1, -2.36, V3(0.95, 0.8, 0.35), Pat.metal) }
    if let t = l.bowTie { b(-1.4, 22.4, -2.5, 1.4, 23.3, -2.3, t) }
    if l.tape { b(-2.4, 21, -2.45, -1.6, 23.5, -2.3, V3(0.92, 0.82, 0.3)); b(1.6, 21, -2.45, 2.4, 23.5, -2.3, V3(0.92, 0.82, 0.3)) }
    // Arms: walk swing, the weapon raised / striking, or hands up.
    let engaged = m.town.foe != nil || m.town.anger > 0
    var right = -swing * 0.8, left = swing * 0.8
    var rz: Float = 0
    if m.town.handsUp > 0 {
        right = .pi - 0.12; left = .pi - 0.12; rz = 0.22
    } else if m.town.swing > 0 {
        let k = 1 - m.town.swing / 0.45                       // 0 -> 1 through the blow
        right = 2.6 - 2.2 * k * k
    } else if engaged && w != .none {
        right = 1.0
    }
    let sleeve = l.coat ?? l.shirt
    for (side, rot) in [(Float(-1), left), (1, right)] {
        let x0: Float = side < 0 ? -7.0 : 4.2, x1: Float = side < 0 ? -4.2 : 7.0
        let pivot = V3(side * 5.6, 23, 0)
        let z = side * rz
        p.append(Part(mn: V3(x0, l.rolledSleeves ? 18 : 14.5, -1.4), mx: V3(x1, 23.6, 1.4), pivot: pivot, rotX: rot, rotZ: z, color: sleeve, pattern: Pat.cloth))
        p.append(Part(mn: V3(x0 + 0.1, 12.6, -1.3), mx: V3(x1 - 0.1, l.rolledSleeves ? 18 : 14.5, 1.3), pivot: pivot, rotX: rot, rotZ: z, color: l.skin, pattern: Pat.skin))
    }
    // The weapon or tool in the right hand.
    p += townWeaponParts(w, combat: engaged && m.town.handsUp <= 0, pivot: V3(5.6, 23, 0), rotX: right, rotZ: rz)
    // Head: face, hair, beard, glasses, headgear.
    let skin = l.skin
    b(-3.2, 23.5, -3.2, 3.2, 30.5, 3.2, skin, Pat.skin)
    b(-0.6, 25.9, -3.85, 0.6, 27.6, -3.2, skin * 0.92, Pat.skin)                              // nose
    b(-2.2, 27, -3.3, -0.9, 28, -3.2, V3(0.95, 0.95, 0.93), Pat.skin)                          // eyes
    b(0.9, 27, -3.3, 2.2, 28, -3.2, V3(0.95, 0.95, 0.93), Pat.skin)
    let iris = [V3(0.22, 0.15, 0.1), V3(0.25, 0.4, 0.55), V3(0.3, 0.42, 0.25)][(m.villager?.look ?? 0) % 3]
    b(-1.7, 27, -3.36, -1.0, 27.9, -3.28, iris, Pat.skin); b(1.0, 27, -3.36, 1.7, 27.9, -3.28, iris, Pat.skin)
    b(-2.4, 28.4, -3.32, -0.8, 28.9, -3.2, l.hair * 0.8); b(0.8, 28.4, -3.32, 2.4, 28.9, -3.2, l.hair * 0.8)  // brows
    b(-1.2, 24.8, -3.3, 1.2, 25.3, -3.2, V3(0.5, 0.25, 0.22), Pat.skin)                         // mouth
    if !l.bald { b(-3.4, 29.6, -3.4, 3.4, 31, 3.4, l.hair); b(-3.4, 25.5, 2.4, 3.4, 31, 3.45, l.hair) }
    else { b(-3.35, 26, 0, -3.15, 29, 3.3, l.hair); b(3.15, 26, 0, 3.35, 29, 3.3, l.hair) }
    if l.longHair { b(-3.5, 21.5, 2.2, 3.5, 30, 3.6, l.hair); b(-3.5, 25.5, -1.5, -3.2, 30, 3, l.hair); b(3.2, 25.5, -1.5, 3.5, 30, 3, l.hair) }
    if l.beard { b(-3.3, 23.4, -3.45, 3.3, 25.6, -1.2, l.hair); b(-1.8, 25.4, -3.5, 1.8, 26, -3.3, l.hair) }
    if l.glasses {
        let g = V3(0.25, 0.22, 0.2)
        b(-2.5, 26.8, -3.5, -0.6, 27.1, -3.35, g, Pat.metal); b(0.6, 26.8, -3.5, 2.5, 27.1, -3.35, g, Pat.metal)
        b(-0.6, 27.4, -3.5, 0.6, 27.7, -3.35, g, Pat.metal)
    }
    let h = l.hatColor
    switch l.hat {
    case .none: break
    case .wideBrim, .straw:
        b(-5.6, 30.6, -5.6, 5.6, 31.3, 5.6, h, l.hat == .straw ? Pat.cloth : Pat.leather)
        b(-3.5, 31.3, -3.5, 3.5, 33.9, 3.5, h, l.hat == .straw ? Pat.cloth : Pat.leather)
        b(-3.55, 31.3, -3.55, 3.55, 32.1, 3.55, l.hat == .straw ? V3(0.5, 0.2, 0.15) : h * 0.6)
    case .flatCap:
        b(-3.5, 30.3, -3.5, 3.5, 31.9, 3.5, h)
        b(-3, 30.3, -5.2, 3, 30.9, -3.5, h * 0.9)
    case .bowler:
        b(-4.4, 30.6, -4.4, 4.4, 31.2, 4.4, h, Pat.leather)
        b(-3.4, 31.2, -3.4, 3.4, 33.4, 3.4, h, Pat.leather)
        b(-2.6, 33.4, -2.6, 2.6, 34, 2.6, h, Pat.leather)
    case .bonnet:
        b(-3.7, 25.5, -2.4, 3.7, 31.6, 3.8, h)
    case .cap:
        b(-3.5, 30.2, -3.5, 3.5, 32.6, 3.5, h)
    }
    return p
}

// The weapon in the right hand: carried along the arm (hanging / a staff), or pointing forward from the hand while
// fighting (raised by the arm's rotation). Built in the right arm's frame (same pivot and rotation).
func townWeaponParts(_ w: TownWeapon, combat: Bool, pivot: V3, rotX: Float, rotZ: Float) -> [Part] {
    let wood = V3(0.45, 0.31, 0.17), steel = V3(0.72, 0.74, 0.78), iron = V3(0.36, 0.37, 0.4)
    var p: [Part] = []
    func a(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = 0) {
        p.append(Part(mn: V3(x0, y0, z0), mx: V3(x1, y1, z1), pivot: pivot, rotX: rotX, rotZ: rotZ, color: c, pattern: pat))
    }
    let hx0: Float = 5.25, hx1: Float = 5.95, hy: Float = 13.2      // hand
    if combat {
        switch w {
        case .none: break
        case .sword:
            a(hx0, hy - 0.3, -0.6, hx1, hy + 0.7, 2.0, V3(0.25, 0.17, 0.1), Pat.leather)
            a(4.4, hy - 0.4, -1.2, 6.8, hy + 0.8, -0.6, V3(0.75, 0.66, 0.4), Pat.metal)
            a(5.4, hy - 0.5, -12.5, 5.8, hy + 0.9, -1.2, steel, Pat.metal)
        case .pitchfork:
            a(5.3, hy - 0.3, -16, 5.9, hy + 0.3, 9, wood)
            a(4.3, hy - 0.3, -16.6, 6.9, hy + 0.3, -16, iron, Pat.metal)
            for x: Float in [4.3, 5.4, 6.5] { a(x, hy - 0.25, -20.5, x + 0.4, hy + 0.25, -16.6, steel, Pat.metal) }
        case .hammer:
            a(hx0, hy - 0.3, -8, hx1, hy + 0.4, 1, wood)
            a(4.5, hy - 1.6, -10.4, 6.7, hy + 2.2, -8, iron, Pat.metal)
        case .cleaver:
            a(hx0, hy - 0.3, -3, hx1, hy + 0.4, 1, V3(0.25, 0.17, 0.1), Pat.leather)
            a(5.4, hy - 0.4, -9.5, 5.8, hy + 3.6, -3, steel, Pat.metal)
        case .axe:
            a(hx0, hy - 0.3, -10, hx1, hy + 0.4, 1.5, wood)
            a(5.35, hy, -10.6, 5.85, hy + 3.6, -8.2, iron, Pat.metal)
            a(5.3, hy + 3.2, -10.8, 5.9, hy + 4, -7.8, steel, Pat.metal)
        case .shovel:
            a(hx0, hy - 0.3, -11, hx1, hy + 0.4, 2, wood)
            a(4.5, hy - 0.4, -14.5, 6.7, hy + 0.4, -11, iron, Pat.metal)
        case .hoe:
            a(hx0, hy - 0.3, -12, hx1, hy + 0.4, 2, wood)
            a(5.3, hy - 2.8, -12.6, 5.9, hy + 0.4, -11.8, iron, Pat.metal)
        }
        return p
    }
    switch w {
    case .none: break
    case .sword:
        a(hx0, hy, -0.4, hx1, hy + 2, 0.4, V3(0.25, 0.17, 0.1), Pat.leather)
        a(4.4, hy - 0.6, -0.6, 6.8, hy, 0.6, V3(0.75, 0.66, 0.4), Pat.metal)
        a(5.4, 3.2, -0.6, 5.8, hy - 0.6, 0.6, steel, Pat.metal)
    case .pitchfork:
        a(6.9, 1, -0.3, 7.5, 33, 0.3, wood)
        a(6, 33, -0.3, 8.4, 33.6, 0.3, iron, Pat.metal)
        for x: Float in [6, 7, 8] { a(x, 33.6, -0.2, x + 0.4, 37, 0.2, steel, Pat.metal) }
    case .hammer:
        a(hx0, 6.5, -0.35, hx1, hy + 1.2, 0.35, wood)
        a(4.5, 4.4, -1.5, 6.7, 6.8, 1.5, iron, Pat.metal)
    case .cleaver:
        a(hx0, 10.8, -0.35, hx1, hy + 1.2, 0.35, V3(0.25, 0.17, 0.1), Pat.leather)
        a(5.4, 5, -2.8, 5.8, 10.8, 0.4, steel, Pat.metal)
    case .axe:
        a(hx0, 4, -0.35, hx1, hy + 1.2, 0.35, wood)
        a(5.35, 4, -2.6, 5.85, 7.2, -0.35, iron, Pat.metal)
    case .shovel:
        a(hx0, 3.2, -0.35, hx1, hy + 1.2, 0.35, wood)
        a(4.5, 0.6, -0.5, 6.7, 3.4, 0.5, iron, Pat.metal)
    case .hoe:
        a(hx0, 3.4, -0.35, hx1, hy + 1.2, 0.35, wood)
        a(5.3, 3, -2.8, 5.9, 3.8, -0.35, iron, Pat.metal)
    }
    return p
}
