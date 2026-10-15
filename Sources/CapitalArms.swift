import Foundation
import simd

// The Capital's weapons as models: white enamel furniture, graphite metal, silver fittings, smoked optics and warm
// white energy cells (original designs). Gun pixels, barrel toward -Z, y up; the hand anchors drive the soldier rig
// (SoldierRig.swift) and the first-person view draws the same boxes (Guns.models). No part carries its own
// rotation: a model is placed as one rigid body.
struct GunModel {
    var parts: [Part]
    var mag: [Int] = []          // parts that leave with the magazine / cell / shells while reloading
    var grip: V3                 // right hand
    var fore: V3                 // left hand
    var butt: V3                 // the stock's shoulder point (pistols: the grip)
    var muzzle: V3
    var magAt: V3                // where the left hand seats a magazine
    var bolt: V3                 // charging handle / pump / bolt the left hand works after the magazine
    var scale: Float             // gun pixel -> model pixel on a soldier
    var shouldered = true        // fired from the shoulder (pistols are held out in both hands)
    var slide: [Int] = []        // P301: parts that ride the pistol's slide (drawn back when it is racked or locked open)
    var slideTravel: Float = 0   // pixels the slide runs back
}

enum CapitalArms {
    // Finish colours and their shading patterns (Part.pattern).
    // Pale grey enamel and a dark band so a weapon still reads against the white uniforms.
    // P217 (Oct 13 19:03, "Capital guns white, no blue"): whiter enamel, neutral greys and steel, smoked glass, and
    // the energy parts glow warm white instead of cyan.
    static let enamel = V3(0.9, 0.9, 0.89), grey = V3(0.46, 0.46, 0.46), graphite = V3(0.15, 0.15, 0.15)
    static let silver = V3(0.82, 0.82, 0.8), glass = V3(0.12, 0.12, 0.12), glow = V3(1.7, 1.6, 1.35)
    static let pEnamel: Float = 7, pMetal: Float = 8, pGlow: Float = 9, pGlass: Float = 11

    static func b(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: V3, _ pat: Float) -> Part {
        Part(mn: V3(x, y, z), mx: V3(x + w, y + h, z + d), color: c, pattern: pat)
    }

    // (A retired gun's index draws its replacement: P217.)
    static let models: [GunModel] = (0..<Guns.all.count).map { i0 in
        let i = Guns.current(i0)
        var g = model(i)
        g.parts += details(i)                    // appended after the magazine parts: their indices stay put
        return g
    }

    // Small fittings that read up close (Quest: the gun is held at real size): triggers, rail notches, scope turrets,
    // barrel vents, slide serrations, muzzle devices.
    static func details(_ i: Int) -> [Part] {
        var p: [Part] = []
        if i != Guns.launcher && i != Guns.revolver && i != Guns.slatefall { p.append(b(-0.12, -1.15, -1.9, 0.24, 0.95, 0.3, silver, pMetal)) }       // trigger blade (the six-iron has its own)
        switch i {
        case Guns.rifle:
            for z: Float in [-6.1, -5.1, 0.1, 1.1, 2.1] { p.append(b(-0.72, 3.25, z, 1.44, 0.22, 0.45, grey, pMetal)) }
            p.append(b(-0.2, -0.55, -13.2, 0.4, 0.5, 0.5, silver, pMetal))                               // sling loop
        case Guns.shotgun:
            for k in 0..<4 { p.append(b(-0.4, 2.4, -16.5 + Float(k) * 2.6, 0.8, 0.18, 1.1, grey, pMetal)) } // rib vents
        case Guns.sniper:
            p.append(b(-0.35, 4.8, -4.4, 0.7, 0.55, 0.9, silver, pMetal))                                 // elevation turret
            p.append(b(0.8, 3.65, -4.4, 0.55, 0.7, 0.9, silver, pMetal))                                  // windage turret
        case Guns.launcher:
            p.append(b(-0.9, 3.8, -12, 1.8, 1.2, 0.3, graphite, pMetal))                                  // front sight
            p.append(b(-0.7, 3.8, 4, 1.4, 0.9, 0.3, graphite, pMetal))                                    // rear sight
        case Guns.arc:
            p.append(b(-1.4, 1.6, -4, 0.1, 0.5, 6, glow * 0.6, pGlow))                                    // charge strip
        case Guns.kessel, Guns.sturmwind:
            p += AshArms.details(i)
        case Guns.slatefall, Guns.repeater:
            p += GreywallArms.details(i)
        case Guns.revolver:
            break                                                                                         // (P180: all in the model)
        default:
            break                                                                                         // (the Falke's are in its model)
        }
        return p
    }

    // Pistol grip raked back: two stacked boxes (parts carry no rotation of their own).
    static func grip(_ x: Float, _ w: Float, top: Float, _ c: V3) -> [Part] {
        [b(x, top - 2, -0.6, w, 2, 1.8, c, pEnamel), b(x, top - 3.9, -0.1, w, 1.9, 1.8, c, pEnamel)]
    }

    static let blued = V3(0.17, 0.19, 0.25), walnut = V3(0.38, 0.21, 0.1), brass = V3(0.74, 0.57, 0.26)

    static func model(_ i: Int) -> GunModel {
        switch i {
        case Guns.kessel, Guns.sturmwind:
            return AshArms.model(i)
        case Guns.slatefall, Guns.repeater:
            return GreywallArms.model(i)
        case Guns.revolver:
            // The six-iron (P180, Oct 13: "doesn't look at all like a six iron"): a frontier single-action revolver.
            // A long round barrel with a blade front sight and the ejector rod under it, a fat fluted cylinder, a
            // case-hardened frame with a top strap, a spurred hammer, a brass trigger-guard loop and the plow-handle
            // walnut grip raked well back with a brass backstrap (original design).
            let cased = V3(0.36, 0.31, 0.28), black = V3(0.02, 0.02, 0.02)
            let p: [Part] = [
                b(-0.42, 0.35, -8.6, 0.84, 0.84, 6.1, blued, pMetal),             // barrel
                b(-0.32, 0.25, -8.6, 0.64, 1.04, 6.1, blued, pMetal),             // (its rounded flanks)
                b(-0.45, 0.32, -8.72, 0.9, 0.9, 0.14, blued * 0.7, pMetal),       // muzzle crown
                b(-0.2, 0.57, -8.76, 0.4, 0.4, 0.1, black, 0),                    // bore
                b(-0.08, 1.19, -8.3, 0.16, 0.4, 0.6, blued, pMetal),              // front sight blade
                b(-0.28, -0.3, -7.2, 0.56, 0.56, 4.6, blued, pMetal),             // ejector rod housing
                b(-0.3, -0.32, -7.45, 0.6, 0.6, 0.25, silver, pMetal),            // ejector head
                b(-0.95, -0.55, -2.6, 1.9, 1.5, 2.3, cased, pMetal),              // cylinder (an octagon of two boxes)
                b(-0.75, -0.75, -2.6, 1.5, 1.9, 2.3, cased, pMetal),
                b(-0.99, -0.2, -2.4, 0.06, 0.5, 1.9, cased * 0.55, pMetal),      // flutes
                b(0.93, -0.2, -2.4, 0.06, 0.5, 1.9, cased * 0.55, pMetal),
                b(-0.2, -0.79, -2.4, 0.4, 0.06, 1.9, cased * 0.55, pMetal),
                b(-0.4, 0.95, -2.7, 0.8, 0.3, 2.6, blued, pMetal),                // top strap
                b(-0.08, 1.2, -0.35, 0.16, 0.06, 0.3, black, 0),                  // rear sight groove
                b(-0.55, -0.85, -0.4, 1.1, 2.0, 1.3, cased, pMetal),              // frame
                b(0.55, -0.45, -0.35, 0.08, 0.7, 0.5, cased * 0.8, pMetal),       // loading gate
                b(-0.18, 0.9, -0.15, 0.36, 0.7, 0.45, blued, pMetal),             // hammer
                b(-0.18, 1.45, 0.15, 0.36, 0.25, 0.75, blued, pMetal),            // hammer spur
                b(-0.15, -1.75, -1.95, 0.3, 0.22, 1.75, brass, pMetal),           // trigger-guard loop
                b(-0.15, -1.6, -2.05, 0.3, 0.8, 0.22, brass, pMetal),
                b(-0.1, -1.45, -1.05, 0.2, 0.65, 0.22, silver, pMetal),           // trigger
                b(-0.55, -1.9, -0.2, 1.1, 1.2, 1.4, walnut, 10),                  // grip, raked back
                b(-0.55, -2.9, 0.25, 1.1, 1.1, 1.4, walnut, 10),
                b(-0.55, -3.8, 0.75, 1.1, 1.0, 1.35, walnut, 10),
                b(-0.5, -4.3, 1.15, 1.0, 0.55, 1.1, walnut, 10),                  // rounded butt
                b(-0.25, -1.6, 1.15, 0.5, 0.9, 0.25, brass, pMetal),              // brass backstrap
                b(-0.25, -2.6, 1.6, 0.5, 1.0, 0.25, brass, pMetal),
                b(-0.25, -3.6, 2.05, 0.5, 0.9, 0.25, brass, pMetal),
                b(-0.6, -2.6, 0.8, 1.2, 0.18, 0.18, silver, pMetal),              // grip screw
                // R9: the chambers show on the cylinder's front face (six dark mouths round the pin), the base pin
                // under the barrel's root, and the barrel's top flat catches the light.
                b(-0.12, -0.27, -2.66, 0.24, 0.24, 0.08, silver, pMetal),         // cylinder pin
                b(-0.62, 0.15, -2.66, 0.38, 0.38, 0.08, black, 0),                // chambers
                b(0.24, 0.15, -2.66, 0.38, 0.38, 0.08, black, 0),
                b(-0.62, -0.75, -2.66, 0.38, 0.38, 0.08, black, 0),
                b(0.24, -0.75, -2.66, 0.38, 0.38, 0.08, black, 0),
                b(-0.19, 0.42, -2.66, 0.38, 0.32, 0.08, black, 0),
                b(-0.19, -1.0, -2.66, 0.38, 0.3, 0.08, black, 0),
                b(-0.22, 1.17, -8.4, 0.44, 0.04, 5.8, blued * 1.6, pMetal),      // top flat highlight
                b(-0.3, -0.62, -2.9, 0.6, 0.3, 0.3, blued, pMetal),               // base pin head
            ]
            return GunModel(parts: p, mag: [], grip: V3(0, -2.2, 0.9), fore: V3(-0.4, -3.0, 1.3), butt: V3(0, -2.2, 0.9),
                            muzzle: V3(0, 0.77, -8.8), magAt: V3(0, -0.4, -1.4), bolt: V3(0, 1.5, 1.2), scale: 0.68, shouldered: false)
        case Guns.rifle:
            // Capital Service Rifle: long enamel receiver with a grey band, top rail and a short optic.
            var p: [Part] = [
                b(-1.1, -0.2, -7, 2.2, 3.0, 11, enamel, pEnamel),                 // receiver
                b(-1.15, 1.0, -6.5, 2.3, 0.5, 10, grey, pEnamel),                  // grey band
                b(-0.7, 2.8, -6.5, 1.4, 0.45, 9, graphite, pMetal),                // rail
                b(-0.8, 3.25, -4, 1.6, 1.5, 3.6, graphite, pMetal),                // optic
                b(-0.55, 3.45, -4.15, 1.1, 1.1, 0.15, glow * 0.7, pGlow),          // optic lens
                b(-1.0, 0.1, -14, 2.0, 2.3, 7, enamel, pEnamel),                   // handguard
                b(-1.05, 1.5, -13.4, 2.1, 0.35, 5.8, grey, pEnamel),               // vents
                b(-1.05, 0.6, -13.4, 2.1, 0.35, 5.8, grey, pEnamel),
                b(-0.45, 0.85, -19, 0.9, 0.9, 5.2, graphite, pMetal),              // barrel
                b(-0.65, 0.65, -19.8, 1.3, 1.3, 1.5, silver, pMetal),              // muzzle brake
                b(-0.3, -1.45, -2.8, 0.6, 0.3, 2.2, graphite, pMetal),             // trigger guard
                b(1.12, 1.6, -3.4, 0.12, 0.8, 2.2, silver, pMetal),                // ejection port
                b(-0.9, -1.2, 4, 1.8, 3.4, 6.2, enamel, pEnamel),                  // stock
                b(-0.95, 2.1, 4.6, 1.9, 0.6, 4.4, grey, pEnamel),                  // cheek rest
                b(-1.0, -1.5, 10, 2.0, 3.9, 0.6, graphite, pMetal),                // butt pad
            ]
            p += grip(-0.7, 1.4, top: -0.2, graphite)
            let m = p.count
            p += [b(-0.7, -4.6, -5.3, 1.4, 4.4, 2.2, graphite, pMetal), b(-0.75, -4.9, -5.4, 1.5, 0.5, 2.4, silver, pMetal)]
            return GunModel(parts: p, mag: [m, m + 1], grip: V3(0, -1.6, 0.3), fore: V3(0, -0.2, -11), butt: V3(0, 0.6, 10.4),
                            muzzle: V3(0, 1.3, -19.9), magAt: V3(0, -2.4, -4.2), bolt: V3(-1.4, 2, -2), scale: 0.64)
        case Guns.shotgun:
            // Breach Shotgun: barrel over the magazine tube, enamel pump with grey grooves, bead sight.
            var p: [Part] = [
                b(-1.2, -0.4, -6, 2.4, 3.0, 9, enamel, pEnamel),
                b(-1.25, 1.5, -5.5, 2.5, 0.4, 8, grey, pEnamel),
                b(-0.6, 1.2, -19, 1.2, 1.2, 13, graphite, pMetal),                 // barrel
                b(-0.55, -0.3, -16, 1.1, 1.1, 10, graphite, pMetal),               // magazine tube
                b(-1.1, -0.8, -14, 2.2, 2.0, 5, enamel, pEnamel),                  // pump
                b(-1.15, -0.3, -13.6, 2.3, 0.3, 4.2, grey, pEnamel),
                b(-1.15, 0.4, -13.6, 2.3, 0.3, 4.2, grey, pEnamel),
                b(-0.2, 2.4, -18.6, 0.4, 0.4, 0.4, silver, pMetal),                // bead
                b(-0.75, 1.0, -19.4, 1.5, 1.6, 0.6, silver, pMetal),               // muzzle ring
                b(-0.3, -1.6, -2.8, 0.6, 0.3, 2.2, graphite, pMetal),
                b(-1.0, -1.6, 3, 2.0, 3.6, 6.5, enamel, pEnamel),                  // stock
                b(-1.05, -1.9, 9.5, 2.1, 4, 0.6, graphite, pMetal),
            ]
            p += grip(-0.7, 1.4, top: -0.4, graphite)
            let m = p.count
            p += [b(1.2, 0, -4, 0.4, 1.4, 1, grey, pMetal), b(1.2, 0, -2.6, 0.4, 1.4, 1, grey, pMetal)]   // shell carrier
            return GunModel(parts: p, mag: [m, m + 1], grip: V3(0, -1.8, 0.3), fore: V3(0, -0.9, -11.5), butt: V3(0, 0.2, 10.1),
                            muzzle: V3(0, 1.8, -19.5), magAt: V3(0, -0.8, -3.5), bolt: V3(0, -0.9, -11.5), scale: 0.62)
        case Guns.sniper:
            // Farsight Rifle: long fluted barrel, big scope with a glowing objective, thumbhole stock, folded bipod.
            var p: [Part] = [
                b(-1.0, -0.3, -6, 2.0, 2.8, 10, enamel, pEnamel),
                b(-1.05, 1.0, -5.5, 2.1, 0.4, 9, grey, pEnamel),
                b(-0.9, 0.0, -16, 1.8, 2.2, 10, enamel, pEnamel),                  // handguard
                b(-0.95, 1.3, -15.4, 1.9, 0.3, 8.6, grey, pEnamel),
                b(-0.45, 0.8, -26, 0.9, 0.9, 10, graphite, pMetal),                // barrel
                b(-0.7, 0.55, -27.6, 1.4, 1.4, 1.8, silver, pMetal),               // brake
                b(-0.8, 3.2, -8, 1.6, 1.6, 10, graphite, pMetal),                  // scope tube
                b(-1.1, 2.9, -9.6, 2.2, 2.2, 1.6, graphite, pMetal),               // objective bell
                b(-0.85, 3.15, -9.7, 1.7, 1.7, 0.15, glow * 0.8, pGlow),           // lens
                b(-1.0, 3.0, 1.6, 2.0, 2.0, 1.4, graphite, pMetal),                // eyepiece
                b(-0.5, 2.6, -6, 1, 0.6, 1, silver, pMetal), b(-0.5, 2.6, -1, 1, 0.6, 1, silver, pMetal),
                b(-0.3, -1.4, -2.6, 0.6, 0.3, 2.0, graphite, pMetal),
                b(-0.9, -2.0, 4, 1.8, 1.6, 7.4, enamel, pEnamel),                  // thumbhole stock (lower)
                b(-0.9, 0.9, 4, 1.8, 1.6, 7.4, enamel, pEnamel),                   // (upper)
                b(-0.9, -2.0, 9, 1.8, 4.5, 2.4, enamel, pEnamel),                  // (rear)
                b(-0.95, 2.4, 4.5, 1.9, 0.8, 5, grey, pEnamel),                    // cheek riser
                b(-0.95, -2.3, 11.4, 1.9, 5.0, 0.6, graphite, pMetal),
                b(-0.85, -0.6, -15, 0.3, 0.4, 6, graphite, pMetal), b(0.55, -0.6, -15, 0.3, 0.4, 6, graphite, pMetal),   // bipod
                b(1.0, 1.4, -2.2, 1.0, 0.5, 0.5, silver, pMetal),                  // bolt knob
            ]
            p += grip(-0.7, 1.4, top: -0.3, graphite)
            let m = p.count
            p += [b(-0.7, -3.4, -4.6, 1.4, 3.2, 2.2, graphite, pMetal)]
            return GunModel(parts: p, mag: [m], grip: V3(0, -1.6, 0.3), fore: V3(0, -0.2, -12), butt: V3(0, 0.4, 11.8),
                            muzzle: V3(0, 1.25, -27.7), magAt: V3(0, -1.8, -3.5), bolt: V3(1.5, 1.6, -2), scale: 0.57)
        case Guns.launcher:
            // Skybreaker Launcher: enamel tube with graphite end rings and a grey band, side optic, two grips.
            var p: [Part] = [
                b(-2.2, -0.6, -15, 4.4, 4.4, 26, enamel, pEnamel),
                b(-2.5, -0.9, -16.2, 5, 5, 1.4, graphite, pMetal),
                b(-2.5, -0.9, 10.6, 5, 5, 1.4, graphite, pMetal),
                b(-2.3, -0.7, -3, 4.6, 4.6, 1.0, grey, pEnamel),
                b(-2.3, -0.7, 6, 4.6, 4.6, 0.6, grey, pEnamel),
                b(-4.2, 1.8, -6, 1.8, 2.2, 4, graphite, pMetal),                   // optic
                b(-4.25, 2.15, -6.1, 1.5, 1.5, 0.15, glow * 0.7, pGlow),
                b(-0.7, -4.4, -0.6, 1.4, 3.8, 1.8, graphite, pMetal),              // grip
                b(-0.7, -4.2, -8.5, 1.4, 3.6, 1.6, graphite, pMetal),              // fore grip
                b(-1.6, 3.8, 1, 3.2, 0.6, 5, graphite, pMetal),                    // shoulder pad
            ]
            let m = p.count
            p += [b(-1.6, 0.0, -16.4, 3.2, 3.2, 0.2, V3(0.25, 0.08, 0.06), pMetal)]   // the rocket's nose in the bore
            return GunModel(parts: p, mag: [m], grip: V3(0, -2.6, 0.3), fore: V3(0, -2.6, -7.7), butt: V3(0, 1.6, 11.8),
                            muzzle: V3(0, 1.6, -16.4), magAt: V3(0, 1.6, 12), bolt: V3(0, -2.6, -7.7), scale: 0.66, shouldered: true)
        case Guns.arc:
            // Arc Lance: enamel body, graphite coil housing ringed with three glowing coils, a glowing cell.
            var p: [Part] = [
                b(-1.3, -1.0, -8, 2.6, 3.4, 13.5, enamel, pEnamel),
                b(-1.35, 1.0, -7.5, 2.7, 0.4, 12.5, grey, pEnamel),
                b(-1.0, -0.6, -20, 2.0, 2.4, 12, graphite, pMetal),
                b(-0.5, 0.0, -22, 1, 1, 2, silver, pMetal),
                b(-0.3, 0.2, -22.2, 0.6, 0.6, 0.2, glow, pGlow),
                b(-0.4, 2.4, -6, 0.8, 1.2, 8, grey, pEnamel),                      // top fin
                b(-1.0, -1.2, 5.5, 2.0, 3.2, 1.5, graphite, pMetal),               // butt
            ]
            for k in 0..<3 { p.append(b(-1.5, -1.0, -18 + Float(k) * 3.4, 3.0, 3.2, 0.8, glow, pGlow)) }
            p += grip(-0.7, 1.4, top: -1.0, graphite)
            let m = p.count
            p += [b(-0.9, -4.3, -3, 1.8, 3.3, 2.4, graphite, pMetal), b(-0.95, -3.7, -2.6, 1.9, 1.6, 1.6, glow * 0.8, pGlow)]
            return GunModel(parts: p, mag: [m, m + 1], grip: V3(0, -2.4, 0.3), fore: V3(0, -1.4, -12), butt: V3(0, 0.4, 7),
                            muzzle: V3(0, 0.5, -22.2), magAt: V3(0, -2.6, -1.8), bolt: V3(-1.6, 0.5, -4), scale: 0.66)
        default:
            // Falke Pistol (P157, Oct 13: "the pistol looks too futuristic"; P217 redo, Oct 14: "Capital guns are white
            // with no blue"): the classic service automatic's lines (the real-world 1911 pattern): a long flat slide
            // with rear cocking serrations and a stepped muzzle bushing, a dust cover over the frame, a beavertail and a
            // spur hammer, a slide stop on the left, a squared trigger guard and a grip raked back over a flush
            // magazine. In the Capital's finish: a white enamel slide and frame, graphite controls and grip panels.
            var p: [Part] = [
                b(-0.65, 0.0, -6.0, 1.3, 1.25, 7.6, enamel, pEnamel),             // slide
                b(-0.45, 0.12, -6.55, 0.9, 0.95, 0.55, graphite, pMetal),          // muzzle bushing
                b(-0.22, 0.38, -6.62, 0.44, 0.44, 0.1, V3(0.02, 0.02, 0.02), 0),   // bore
                b(-0.6, -0.65, -5.6, 1.2, 0.65, 6.6, enamel * 0.94, pEnamel),      // frame and dust cover
                b(0.66, 0.35, -3.2, 0.06, 0.7, 2.2, graphite, pMetal),             // ejection port (right)
                b(-0.75, -0.35, -3.0, 0.12, 0.4, 1.6, graphite, pMetal),           // slide stop (left)
                b(-0.12, 1.25, -5.6, 0.24, 0.3, 0.3, graphite, pMetal),            // front sight
                b(-0.35, 1.25, 1.0, 0.7, 0.3, 0.4, graphite, pMetal),              // rear sight
                b(-0.2, 0.55, 1.6, 0.4, 0.7, 0.45, graphite, pMetal),              // spur hammer
                b(-0.5, -0.3, 1.35, 1.0, 0.45, 0.9, enamel * 0.94, pEnamel),       // beavertail
                b(-0.25, -1.5, -2.6, 0.5, 0.25, 2.2, enamel * 0.94, pEnamel),      // trigger guard (squared)
                b(-0.25, -1.45, -2.65, 0.5, 0.95, 0.25, enamel * 0.94, pEnamel),
                b(-0.6, -1.9, -0.6, 1.2, 1.3, 1.9, enamel * 0.94, pEnamel),        // grip, raked back
                b(-0.6, -3.1, -0.2, 1.2, 1.3, 1.9, enamel * 0.94, pEnamel),
                b(0.6, -3.0, -0.3, 0.1, 2.3, 1.6, graphite, pEnamel),              // grip panels
                b(-0.7, -3.0, -0.3, 0.1, 2.3, 1.6, graphite, pEnamel),
                b(-0.75, -1.15, -0.85, 0.15, 0.3, 0.4, graphite, pMetal),          // magazine release
            ]
            for k in 0..<4 {                                                       // rear cocking serrations
                p.append(b(0.65, 0.2, -0.6 + Float(k) * 0.4, 0.06, 0.85, 0.18, graphite, pMetal))
                p.append(b(-0.71, 0.2, -0.6 + Float(k) * 0.4, 0.06, 0.85, 0.18, graphite, pMetal))
            }
            let m = p.count
            p += [b(-0.5, -3.55, 0.2, 1.0, 0.45, 1.6, graphite, pMetal)]          // magazine base
            // P301: the slide, bushing, bore, ejection port, both sights and the serrations run back together.
            return GunModel(parts: p, mag: [m], grip: V3(0, -1.9, 0.5), fore: V3(-0.4, -2.6, 0.8), butt: V3(0, -1.9, 0.5),
                            muzzle: V3(0, 0.6, -6.6), magAt: V3(0, -3.3, 0.9), bolt: V3(0, 0.7, -0.6), scale: 0.68, shouldered: false,
                            slide: [0, 1, 2, 4, 6, 7] + Array(17..<25), slideTravel: 2.2)
        }
    }
}
