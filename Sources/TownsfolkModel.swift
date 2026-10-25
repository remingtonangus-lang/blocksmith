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
    var glasses = false, tape = false, gunBelt = false, star = false
    var woman = false              // P343: the figure and face
    var mask: V3? = nil, bandolier = false, gloves: V3? = nil     // P444: the raiders' bandana, bolts and gloves

    enum Hat { case none, wideBrim, flatCap, bowler, bonnet, cap, straw }

    static let shirts = [V3(0.86, 0.82, 0.72), V3(0.9, 0.9, 0.87), V3(0.42, 0.5, 0.62), V3(0.6, 0.27, 0.22), V3(0.55, 0.43, 0.3),
                         V3(0.6, 0.6, 0.58), V3(0.36, 0.42, 0.3)]
    static let trousers = [V3(0.24, 0.29, 0.4), V3(0.4, 0.3, 0.21), V3(0.37, 0.36, 0.35), V3(0.16, 0.15, 0.15), V3(0.6, 0.5, 0.37)]
    static let dresses = [V3(0.45, 0.3, 0.42), V3(0.3, 0.4, 0.55), V3(0.56, 0.5, 0.4), V3(0.34, 0.44, 0.31), V3(0.6, 0.32, 0.27),
                          V3(0.28, 0.26, 0.3)]

    static func of(_ m: Mob) -> TownLook {
        if m.kind == .pillager || m.kind == .vindicator { return raider(m) }
        let v = m.villager
        let k = v?.look ?? Int(Townsfolk.mix(Int(m.pos.x), Int(m.pos.z), 7) & 0xFFFF)
        let woman = Townsfolk.isWoman(v)
        let role = v?.role ?? (m.baby ? "child" : "worker")
        var l = TownLook(skin: Livery.skins[k % Livery.skins.count], hair: Livery.hairs[(k / 5) % Livery.hairs.count],
                         shirt: shirts[(k / 3) % shirts.count], legs: trousers[(k / 7) % trousers.count], boots: V3(0.2, 0.14, 0.1))
        l.woman = woman
        if woman { l.skirt = dresses[(k / 11) % dresses.count]; l.longHair = true }
        else { l.beard = !m.baby && k % 3 == 0 }
        switch role {
        case "deputy":
            l.shirt = V3(0.72, 0.62, 0.46); l.vest = V3(0.26, 0.18, 0.12); l.badge = true; l.gunBelt = true
            l.hat = .wideBrim; l.hatColor = V3(0.32, 0.24, 0.16); l.skirt = nil; l.legs = trousers[(k / 7) % 2 == 0 ? 0 : 3]
        case "sheriff":
            // The sheriff: black hat and waistcoat, a red neckerchief, a big gold star, a gun belt and a moustache.
            l.shirt = V3(0.84, 0.8, 0.72); l.vest = V3(0.11, 0.1, 0.1); l.star = true; l.gunBelt = true; l.bowTie = V3(0.62, 0.13, 0.1)
            l.hat = .wideBrim; l.hatColor = V3(0.09, 0.08, 0.08); l.skirt = nil; l.longHair = false; l.beard = true; l.legs = trousers[3]
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
        case "citizen":
            // City clothes: a pale shirt, a dark coat or waistcoat, a bowler or a bonnet; dresses in quiet colours.
            l.shirt = [V3(0.93, 0.93, 0.9), V3(0.82, 0.86, 0.9), V3(0.9, 0.86, 0.78)][k % 3]
            if l.skirt == nil {
                if k % 2 == 0 { l.coat = [V3(0.16, 0.17, 0.2), V3(0.3, 0.28, 0.26), V3(0.22, 0.26, 0.34)][(k / 2) % 3] }
                else { l.vest = [V3(0.2, 0.2, 0.22), V3(0.38, 0.3, 0.24)][(k / 2) % 2]; l.bowTie = V3(0.12, 0.12, 0.14) }
                l.legs = trousers[(k / 7) % 2 == 0 ? 2 : 3]
                l.hat = k % 3 == 0 ? .bowler : .none; l.hatColor = V3(0.1, 0.1, 0.11)
            } else {
                l.skirt = [V3(0.3, 0.4, 0.55), V3(0.28, 0.26, 0.3), V3(0.45, 0.3, 0.42), V3(0.62, 0.6, 0.56)][(k / 11) % 4]
                l.hat = k % 3 == 0 ? .bonnet : .none; l.hatColor = V3(0.9, 0.88, 0.82)
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

    // P444 (Oct 24 20:58: "These pillager assholes need to get fixed... Looks really, really primitive"): the raiders on
    // the townsfolk body as an outlaw band, every face behind a bandana. Marauders (crossbows): a long duster, a
    // wide-brimmed hat, a bandolier of bolts and a quiver on the back. Brigands (axes): a waistcoat over rolled sleeves,
    // a flat cap or a bare head. Their own look from the mob's coat seed (steady as it walks).
    static func raider(_ m: Mob) -> TownLook {
        let k = Int(m.coatSeed) & 0xFFFF
        var l = TownLook(skin: Livery.skins[k % Livery.skins.count] * 0.94, hair: Livery.hairs[(k / 5) % Livery.hairs.count],
                         shirt: shirts[0], legs: trousers[(k / 7) % 2 == 0 ? 3 : 1], boots: V3(0.14, 0.1, 0.08))
        // Cloth colours no hair or skin comes in (a black or a tan one read as a beard).
        l.mask = [V3(0.58, 0.1, 0.09), V3(0.14, 0.2, 0.38), V3(0.16, 0.3, 0.19), V3(0.36, 0.38, 0.44)][(k / 3) % 4]
        l.gloves = V3(0.26, 0.19, 0.13)
        if m.kind == .pillager {
            l.shirt = [V3(0.62, 0.55, 0.44), V3(0.44, 0.42, 0.38), V3(0.55, 0.4, 0.3)][(k / 11) % 3]
            l.coat = [V3(0.33, 0.26, 0.19), V3(0.21, 0.2, 0.19), V3(0.42, 0.34, 0.25)][(k / 13) % 3]
            l.hat = .wideBrim; l.hatColor = [V3(0.16, 0.13, 0.11), V3(0.3, 0.23, 0.16), V3(0.11, 0.1, 0.1)][(k / 17) % 3]
            l.bandolier = true
        } else {
            l.shirt = [V3(0.48, 0.2, 0.16), V3(0.38, 0.36, 0.32), V3(0.3, 0.33, 0.38)][(k / 11) % 3]
            l.vest = [V3(0.2, 0.15, 0.11), V3(0.12, 0.12, 0.12)][(k / 13) % 2]
            l.rolledSleeves = true
            if k % 2 == 0 { l.hat = .flatCap; l.hatColor = [V3(0.24, 0.22, 0.2), V3(0.3, 0.25, 0.19)][(k / 17) % 2] }
            else { l.bald = k % 3 == 0 }
        }
        return l
    }
}

func townsfolkParts(_ m: Mob, swing: Float) -> [Part] {
    let l = TownLook.of(m)
    let raider = m.kind == .pillager || m.kind == .vindicator          // P444: Marauders and Brigands
    let w: TownWeapon = raider ? (m.kind == .vindicator ? .axe : .none) : m.townWeapon
    let aiming = m.kind == .pillager && m.aimHold > 0                     // the crossbow up at the shoulder
    var p: [Part] = []
    p.reserveCapacity(48)
    func b(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = Pat.cloth) {
        p.append(Part(mn: V3(x0, y0, z0), mx: V3(x1, y1, z1), color: c, pattern: pat))
    }
    let lv = MobDetail.level
    // Legs swing from the hips, thigh and shin jointed at the knee (it folds as the foot comes through, P295); boots
    // with a toe.
    for (side, sgn) in [(Float(-1), Float(1)), (1, -1)] {
        let x0: Float = -1.8, x1: Float = 1.8
        let thigh = ModelJoint(o: V3(side * 2, 13, 0), a: swing * sgn)
        let flex: Float = max(0, cosf(m.walkPhase) * sgn) * 0.9 * m.walkAmount
        let shin = thigh.at(V3(0, -6, 0), -flex)
        let cloth = l.overalls ?? l.legs
        p.append(thigh.box(x0, -6.4, -1.8, x1, 0, 1.8, cloth, Pat.cloth))
        p.append(shin.box(x0 + 0.1, -3.6, -1.7, x1 - 0.1, 0.3, 1.7, cloth, Pat.cloth))
        p.append(shin.box(x0 - 0.15, -7, -2.3, x1 + 0.15, -3.6, 1.95, l.boots, Pat.leather))
        if lv < 2 { p.append(shin.box(x0 - 0.05, -7, -3.1, x1 + 0.05, -5.7, -2.3, l.boots * 0.92, Pat.leather)) }
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
    if l.woman && !m.baby, let s = l.skirt, l.coat == nil, l.apron == nil, l.overalls == nil {
        // P343: a fitted bodice in the dress's colour with a cinched sash at the waist (a modest, tailored line).
        b(-3.85, 13.6, -2.32, 3.85, 15.0, 2.32, s * 0.82)
        if lv < 2 { b(-3.3, 15.0, -2.36, 3.3, 21.2, -2.22, s); b(-2.6, 21.2, -2.36, 2.6, 22.3, -2.22, s * 0.95) }
    }
    if l.badge { b(-3.4, 19.5, -2.5, -1.8, 21.1, -2.36, V3(0.95, 0.8, 0.35), Pat.metal) }
    if l.star {                                                                                    // a six-point star, read as a cross with a hub
        let gold = V3(1, 0.82, 0.3)
        b(-3.9, 19.9, -2.62, -1.3, 20.9, -2.4, gold, Pat.metal); b(-3.1, 19.0, -2.62, -2.1, 21.8, -2.4, gold, Pat.metal)
        b(-3.5, 19.4, -2.66, -1.7, 21.4, -2.44, gold * 0.9, Pat.metal)
    }
    if let t = l.bowTie { b(-1.4, 22.4, -2.5, 1.4, 23.3, -2.3, t) }
    if l.tape { b(-2.4, 21, -2.45, -1.6, 23.5, -2.3, V3(0.92, 0.82, 0.3)); b(1.6, 21, -2.45, 2.4, 23.5, -2.3, V3(0.92, 0.82, 0.3)) }
    if l.bandolier {
        // From the left shoulder to the right hip, front and back, bolt heads in its loops; a quiver on the back.
        let strap = V3(0.24, 0.17, 0.11), tip = V3(0.55, 0.56, 0.58)
        func d(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float, _ pv: V3, _ rz: Float) {
            p.append(Part(mn: V3(x0, y0, z0), mx: V3(x1, y1, z1), pivot: pv, rotZ: rz, color: c, pattern: pat))
        }
        let f = V3(0, 18.3, -2.75), bk = V3(0, 18.3, 2.75)
        d(-0.85, 11.8, -2.95, 0.85, 24.8, -2.55, strap, Pat.leather, f, 0.65)
        d(-0.85, 11.8, 2.55, 0.85, 24.8, 2.95, strap, Pat.leather, bk, 0.65)
        if lv < 2 { for o: Float in [-4.4, -2.2, 0, 2.2, 4.4] { d(-0.5, 18.3 + o - 0.45, -3.25, 0.5, 18.3 + o + 0.45, -2.9, tip, Pat.metal, f, 0.65) } }
        let q = V3(1.8, 18, 3.6)
        d(0.4, 12.5, 2.6, 3.2, 21.5, 4.6, V3(0.36, 0.25, 0.15), Pat.leather, q, -0.3)                // the quiver
        if lv < 2 { d(0.7, 21.5, 3.0, 2.9, 23.6, 4.2, V3(0.82, 0.8, 0.74), Pat.cloth, q, -0.3) }        // fletchings
    }
    // Arms: walk swing, the weapon raised / striking, or hands up.
    let engaged = raider ? m.aggro || aiming : m.town.foe != nil || m.town.anger > 0 || m.town.drawn > 0
    var right = -swing * 0.8, left = swing * 0.8
    var rz: Float = 0
    var aimY: (left: Float, right: Float) = (0, 0)
    if aiming {
        // Both arms up and in: the right hand under the crossbow's fore-end, the left across at its grip.
        right = 1.8; left = 1.8; aimY = (-0.9, 0.37)
    } else if raider {
        if m.kind == .vindicator && m.strikeT > 0 {
            let k = 1 - min(1, m.strikeT / 0.3)                  // the axe comes down through the lunge
            right = 2.6 - 2.2 * k * k
        } else if m.kind == .vindicator && engaged { right = 1.0 }
    } else if m.town.handsUp > 0 {
        right = .pi - 0.12; left = .pi - 0.12; rz = 0.22
    } else if w == .revolver && m.town.swing > 0 {
        right = .pi / 2 + 0.6 * m.town.swing / 0.3            // the six-iron's recoil kick
    } else if w == .revolver && m.town.aim > 0 {
        right = .pi / 2                                        // the aim telegraph: arm level, gun on you (SixIron)
    } else if m.town.swing > 0 {
        let k = 1 - m.town.swing / 0.45                       // 0 -> 1 through the blow
        right = 2.6 - 2.2 * k * k
    } else if engaged && w != .none {
        right = 1.0
    }
    // At rest the arms hang loose and sway a little with the breath (P295).
    let still: Float = max(0, 1 - m.walkAmount * 3) * (engaged || m.town.handsUp > 0 ? 0 : 1)
    let sway: Float = sinf(m.animT * 1.25 + Float((m.villager?.look ?? 0) % 7)) * 0.04 * still
    right += sway; left -= sway * 0.8
    let sleeve = l.coat ?? l.shirt
    let hand = l.gloves ?? l.skin
    for (side, rot) in [(Float(-1), left), (1, right)] {
        let x0: Float = side < 0 ? -7.0 : 4.2, x1: Float = side < 0 ? -4.2 : 7.0
        let pivot = V3(side * 5.6, 23, 0)
        let z = side * rz + side * 0.03 * still
        let y = side < 0 ? aimY.left : aimY.right
        func arm(_ mn: V3, _ mx: V3, _ c: V3, _ pat: Float) {
            p.append(Part(mn: mn, mx: mx, pivot: pivot, rotX: rot, rotZ: z, color: c, pattern: pat, rotY: y))
        }
        let cuff: Float = l.rolledSleeves ? 18 : 14.4
        arm(V3(x0, cuff, -1.4), V3(x1, 23.6, 1.4), sleeve, Pat.cloth)
        if l.rolledSleeves { arm(V3(x0 + 0.15, 14.2, -1.25), V3(x1 - 0.15, 18, 1.25), l.skin, Pat.skin) }
        else if lv < 2 { arm(V3(x0 - 0.05, 14.4, -1.45), V3(x1 + 0.05, 15.0, 1.45), sleeve * 0.9, Pat.cloth) }       // cuff
        // The hand: narrower and flatter than the arm, the thumb forward on the inner side.
        arm(V3(x0 + 0.35, 11.7, -1.05), V3(x1 - 0.35, 14.4, 1.15), hand, l.gloves == nil ? Pat.skin : Pat.leather)
        if lv == 0 {
            let tx0: Float = side < 0 ? x1 - 1.0 : x0 + 0.2, tx1: Float = side < 0 ? x1 - 0.2 : x0 + 1.0
            arm(V3(tx0, 12.8, -1.5), V3(tx1, 14.1, -0.95), hand * 0.96, l.gloves == nil ? Pat.skin : Pat.leather)
        }
    }
    // The weapon or tool in the right hand.
    p += townWeaponParts(w, combat: engaged && m.town.handsUp <= 0, pivot: V3(5.6, 23, 0), rotX: right, rotZ: rz)
    if m.kind == .pillager { p += crossbowParts(aiming: aiming, pivot: V3(5.6, 23, 0), rotX: right, lod: lv) }
    // Head: face, hair, beard, glasses, headgear. P295: built in the old head's frame (23.5 to 30.5), then drawn at a
    // person's proportions (a fifth smaller, about one in five and a half of their height) on a neck: ears, chin, lips,
    // pupils and lids, blinking now and then.
    let headStart = p.count
    let skin = l.skin
    let shut = m.blinking && lv == 0
    b(-3.2, 23.5, -3.2, 3.2, 30.5, 3.2, skin, Pat.skin)
    b(-0.6, 25.9, -3.85, 0.6, 27.6, -3.2, skin * 0.92, Pat.skin)                              // nose
    b(-3.55, 25.8, -0.6, -3.2, 28.2, 0.9, skin * 0.94, Pat.skin); b(3.2, 25.8, -0.6, 3.55, 28.2, 0.9, skin * 0.94, Pat.skin)   // ears
    if lv < 2 {
        b(-1.5, 23.5, -3.45, 1.5, 24.4, -3.2, skin * 0.97, Pat.skin)                         // chin
        b(-0.85, 25.7, -4.0, 0.85, 26.4, -3.5, skin * 0.9, Pat.skin)                         // the nose's tip
    }
    if shut {
        b(-2.25, 26.95, -3.36, -0.85, 28.05, -3.2, skin * 0.9, Pat.skin); b(0.85, 26.95, -3.36, 2.25, 28.05, -3.2, skin * 0.9, Pat.skin)
    } else {
        b(-2.2, 27, -3.3, -0.9, 28, -3.2, V3(0.95, 0.95, 0.93), Pat.skin)                      // eyes
        b(0.9, 27, -3.3, 2.2, 28, -3.2, V3(0.95, 0.95, 0.93), Pat.skin)
        let iris = [V3(0.22, 0.15, 0.1), V3(0.25, 0.4, 0.55), V3(0.3, 0.42, 0.25)][(m.villager?.look ?? 0) % 3]
        b(-1.7, 27, -3.36, -1.0, 27.9, -3.28, iris, Pat.enamel); b(1.0, 27, -3.36, 1.7, 27.9, -3.28, iris, Pat.enamel)
        if lv == 0 {
            b(-1.5, 27.2, -3.4, -1.2, 27.7, -3.36, V3(0.04, 0.03, 0.03), Pat.enamel); b(1.2, 27.2, -3.4, 1.5, 27.7, -3.36, V3(0.04, 0.03, 0.03), Pat.enamel)
            b(-2.25, 27.85, -3.34, -0.85, 28.1, -3.2, skin * 0.78, Pat.skin); b(0.85, 27.85, -3.34, 2.25, 28.1, -3.2, skin * 0.78, Pat.skin)   // lids
        }
    }
    b(-2.4, 28.4, -3.32, -0.8, 28.9, -3.2, l.hair * 0.8); b(0.8, 28.4, -3.32, 2.4, 28.9, -3.2, l.hair * 0.8)  // brows
    let lip = skin * V3(0.82, 0.58, 0.55)
    b(-1.2, 25.0, -3.3, 1.2, 25.3, -3.2, lip * 0.85, Pat.skin)                                 // lips
    if lv < 2 { b(-0.95, 24.7, -3.32, 0.95, 25.0, -3.2, lip, Pat.skin) }
    if lv == 0 {
        let cheek = skin * V3(1.03, 0.93, 0.92)
        b(-2.8, 25.3, -3.25, -1.6, 26.4, -3.2, cheek, Pat.skin); b(1.6, 25.3, -3.25, 2.8, 26.4, -3.2, cheek, Pat.skin)
    }
    // P343 (Oct 16, 19:46): adult faces with more character. Women: lashes over the eyes, fuller rosy lips, a softer
    // jaw, styled hair (a fringe, a bun or a side sweep by look). Men: a squarer jaw, sideburns, stubble on some.
    let look = m.villager?.look ?? 0
    if l.woman && !m.baby {
        let lash = V3(0.06, 0.05, 0.05)
        if !shut { b(-2.35, 27.95, -3.4, -0.8, 28.2, -3.3, lash); b(0.8, 27.95, -3.4, 2.35, 28.2, -3.3, lash) }
        if lv < 2 { b(-2.45, 27.5, -3.38, -2.2, 28.1, -3.3, lash); b(2.2, 27.5, -3.38, 2.45, 28.1, -3.3, lash) }   // outer flick
        let rose = mixV(skin * V3(0.82, 0.58, 0.55), V3(0.7, 0.32, 0.34), 0.6)
        b(-0.9, 24.7, -3.34, 0.9, 25.0, -3.22, rose, Pat.enamel); b(-1.05, 25.0, -3.32, 1.05, 25.25, -3.22, rose * 0.88, Pat.enamel)
        if !l.bald {
            switch look % 3 {
            case 0: b(-3.45, 28.9, -3.5, 3.45, 30.4, -3.15, l.hair)                                     // fringe
            case 1: b(-1.7, 27.6, 3.3, 1.7, 30.6, 5.1, l.hair * 0.94); b(-1.1, 28.2, 5.1, 1.1, 30.0, 5.6, l.hair * 0.9)   // bun
            default: b(-3.45, 29.0, -3.5, 0.4, 30.5, -3.15, l.hair); b(-3.6, 26.2, -3.2, -3.3, 30.2, 1.2, l.hair)   // side sweep
            }
        }
    } else if !m.baby {
        b(-3.25, 23.5, -3.3, 3.25, 24.5, -2.4, skin * 0.95, Pat.skin)                                    // the jaw's line
        if !l.bald { b(-3.42, 25.2, -1.3, -3.2, 28.4, 0.6, l.hair * 0.9); b(3.2, 25.2, -1.3, 3.42, 28.4, 0.6, l.hair * 0.9) }   // sideburns
        if !l.beard && look % 3 == 1 { b(-3.0, 23.45, -3.36, 3.0, 25.1, -3.26, mixV(skin, l.hair, 0.3), Pat.skin) }   // stubble
    }
    if !l.bald { b(-3.4, 29.6, -3.4, 3.4, 31, 3.4, l.hair); b(-3.4, 25.5, 2.4, 3.4, 31, 3.45, l.hair) }
    else { b(-3.35, 26, 0, -3.15, 29, 3.3, l.hair); b(3.15, 26, 0, 3.35, 29, 3.3, l.hair) }
    if l.longHair { b(-3.5, 21.5, 2.2, 3.5, 30, 3.6, l.hair); b(-3.5, 25.5, -1.5, -3.2, 30, 3, l.hair); b(3.2, 25.5, -1.5, 3.5, 30, 3, l.hair) }
    if l.beard { b(-3.3, 23.4, -3.45, 3.3, 25.6, -1.2, l.hair); b(-1.8, 25.4, -3.5, 1.8, 26, -3.3, l.hair) }
    if let mk = l.mask {
        // The bandana: round the jaw and pulled up over the nose to just under the eyes, its point under the chin, the
        // knot behind.
        // Up to the eyes so no skin shows between (under a strip of skin it read as a beard), a low ridge over the nose
        // (a tall one read as a clown's nose), a folded hem, the cloth hanging from the nose in a tent (shaded sides,
        // no marks across it: a row of dots read as teeth) to a wide point under the chin, the knot behind.
        b(-3.38, 23.2, -3.52, 3.38, 26.75, 3.52, mk)
        b(-3.42, 26.35, -3.6, 3.42, 26.8, -3.48, mk * 0.78)                                        // hem
        b(-0.75, 22.4, -3.82, 0.75, 26.7, -3.5, mk * 1.08)                                         // from the nose down
        if lv < 2 { b(-1.35, 22.4, -3.66, -0.75, 25.6, -3.5, mk * 0.84); b(0.75, 22.4, -3.66, 1.35, 25.6, -3.5, mk * 0.84) }
        b(-2.6, 22.2, -3.7, 2.6, 23.25, -3.3, mk * 0.92)                                           // the point
        b(-1.3, 21.35, -3.66, 1.3, 22.2, -3.34, mk * 0.86)
        if lv < 2 { b(-0.8, 24.6, 3.5, 0.8, 26.3, 4.1, mk * 0.82); b(-0.45, 23.2, 3.6, 0.45, 24.6, 3.95, mk * 0.82) }   // knot
    }
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
    // The head to a person's proportions, on a neck.
    let hs = V3(0.8, 0.8, 0.82), h0 = V3(0, 23.5, 0), lift = V3(0, 1.1, 0)
    for i in headStart..<p.count {
        p[i].mn = h0 + (p[i].mn - h0) * hs + lift
        p[i].mx = h0 + (p[i].mx - h0) * hs + lift
    }
    b(-1.45, 23.3, -1.5, 1.45, 24.9, 1.4, skin, Pat.skin)                                     // neck
    if lv < 2 { b(-2.1, 22.9, -1.9, 2.1, 23.85, 1.8, l.coat ?? l.vest ?? l.shirt) }            // collar
    // Build (TownStats): the body below the neck broader for the strong and tough, slighter for the frail.
    let k = m.townStats.build
    if abs(k - 1) > 0.01 {
        for i in 0..<headStart where p[i].mn.y < 23.4 {
            p[i].mn.x *= k; p[i].mx.x *= k; p[i].mn.z *= k; p[i].mx.z *= k; p[i].pivot.x *= k; p[i].pivot.z *= k
        }
    }
    // P343: the figure. A woman's shoulders and chest narrower than her hips (the skirt keeps its width); a man's
    // shoulders broader. The unjointed parts from the waist up (torso, belt, vest) narrow or widen; the arms (and what
    // they hold) move in or out with the shoulders without changing their own width.
    if !m.baby {
        let f: Float = l.woman ? 0.88 : 1.07
        for i in 0..<headStart {
            if p[i].pivot == .zero {
                guard p[i].mn.y >= 12.9 && p[i].mn.y < 23.4 else { continue }
                p[i].mn.x *= f; p[i].mx.x *= f
            } else if p[i].pivot.y == 23 && p[i].pivot.x != 0 {
                let dx = p[i].pivot.x * (f - 1)
                if l.woman && p[i].mx.x - p[i].mn.x > 1.5 {                               // slimmer arms (not what she holds)
                    let c = (p[i].mn.x + p[i].mx.x) / 2, hw = (p[i].mx.x - p[i].mn.x) * 0.43
                    p[i].mn.x = c - hw; p[i].mx.x = c + hw
                }
                p[i].mn.x += dx; p[i].mx.x += dx; p[i].pivot.x += dx
            }
        }
    }
    return p
}

@inline(__always) private func mixV(_ a: V3, _ b: V3, _ t: Float) -> V3 { a + (b - a) * t }

// P444: the Marauder's crossbow. Aimed: level at the right eye's height along the body's front, the butt by the
// shoulder, bolt loaded and the string drawn back to the nut (the arms posed up and in to hold it: townsfolkParts).
// Carried: in the right hand, canted on its side so the prod stands upright beside the leg, swinging with the arm.
// (Parts carry a pivot, so the head's turn leaves them alone: MobAnim's fixedOnly.)
func crossbowParts(aiming: Bool, pivot: V3, rotX: Float, lod: Int) -> [Part] {
    let wood = V3(0.42, 0.28, 0.15), dark = V3(0.25, 0.17, 0.1), iron = V3(0.34, 0.35, 0.38), str = V3(0.82, 0.8, 0.72)
    var p: [Part] = []
    if aiming {
        let pv = V3(2.5, 26.4, -8)
        func a(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = 0, ry: Float = 0, at: V3? = nil) {
            p.append(Part(mn: V3(x0, y0, z0), mx: V3(x1, y1, z1), pivot: at ?? pv, color: c, pattern: pat, rotY: ry))
        }
        a(1.9, 25.9, -14.6, 3.1, 26.9, -2.9, wood, Pat.leather)                     // stock
        a(1.75, 25.0, -4.4, 3.25, 27.0, -2.9, dark, Pat.leather)                     // butt
        a(2.3, 25.0, -7.0, 2.7, 25.9, -6.2, iron, Pat.metal)                         // trigger
        a(-3.5, 26.2, -14.2, 8.5, 26.9, -13.4, dark, Pat.leather)                    // prod
        a(-4.0, 26.2, -13.6, -3.0, 26.9, -12.0, iron, Pat.metal); a(8.0, 26.2, -13.6, 9.0, 26.9, -12.0, iron, Pat.metal)
        a(1.7, 25.6, -15.6, 3.3, 26.9, -14.6, iron, Pat.metal)                       // stirrup
        let nut = V3(2.5, 27.0, -8.0)
        a(2.5 - 7.33, 26.95, -8.06, 2.5, 27.1, -7.94, str, ry: -0.61, at: nut)        // string, drawn back
        a(2.5, 26.95, -8.06, 2.5 + 7.33, 27.1, -7.94, str, ry: 0.61, at: nut)
        a(2.35, 26.9, -16.0, 2.65, 27.25, -8.0, wood)                                // bolt
        a(2.3, 26.85, -17.0, 2.7, 27.3, -16.0, iron, Pat.metal)
        if lod < 2 { a(2.1, 26.95, -9.2, 2.9, 27.2, -8.0, str * 0.95) }               // fletching
    } else {
        func a(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = 0) {
            p.append(Part(mn: V3(x0, y0, z0), mx: V3(x1, y1, z1), pivot: pivot, rotX: rotX, color: c, pattern: pat))
        }
        a(5.0, 12.5, -10.2, 6.2, 13.7, 3.2, wood, Pat.leather)                       // stock through the fist
        a(4.9, 11.6, 1.8, 6.3, 13.8, 3.4, dark, Pat.leather)                         // butt
        a(5.2, 7.6, -9.6, 6.0, 18.6, -8.8, dark, Pat.leather)                        // prod, upright
        a(5.25, 7.1, -8.8, 5.95, 8.1, -7.6, iron, Pat.metal); a(5.25, 18.1, -8.8, 5.95, 19.1, -7.6, iron, Pat.metal)
        a(5.5, 7.9, -7.7, 5.7, 18.8, -7.5, str)                                      // string, slack
        a(4.95, 12.3, -11.2, 6.25, 13.9, -10.2, iron, Pat.metal)                     // stirrup
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
        case .revolver:
            a(hx0, hy - 1.8, -0.4, hx1, hy + 0.3, 0.8, V3(0.36, 0.22, 0.12), Pat.leather)        // grip
            a(5.1, hy + 0.1, -1.6, 6.1, hy + 1.3, 0.6, iron, Pat.metal)                         // cylinder
            a(5.35, hy + 0.5, -5.6, 5.85, hy + 1.1, -1.6, iron, Pat.metal)                      // barrel
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
    case .revolver: break                                                     // holstered on the gun belt
    }
    return p
}
