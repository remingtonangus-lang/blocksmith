import Foundation
import simd

// The Capital's weapons as models: white enamel furniture, graphite metal, silver fittings, pale-cyan optics and
// energy cells (original designs). Gun pixels, barrel toward -Z, y up; the hand anchors drive the soldier rig
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
}

enum CapitalArms {
    // Finish colours and their shading patterns (Part.pattern).
    // Pale grey enamel and a dark band so a weapon still reads against the white uniforms.
    static let enamel = V3(0.8, 0.81, 0.82), grey = V3(0.42, 0.45, 0.49), graphite = V3(0.14, 0.15, 0.17)
    static let silver = V3(0.78, 0.8, 0.84), glass = V3(0.1, 0.13, 0.17), glow = V3(0.55, 1.55, 1.95)
    static let pEnamel: Float = 7, pMetal: Float = 8, pGlow: Float = 9, pGlass: Float = 11

    static func b(_ x: Float, _ y: Float, _ z: Float, _ w: Float, _ h: Float, _ d: Float, _ c: V3, _ pat: Float) -> Part {
        Part(mn: V3(x, y, z), mx: V3(x + w, y + h, z + d), color: c, pattern: pat)
    }

    static let models: [GunModel] = (0..<Guns.all.count).map { i in
        var g = model(i)
        g.parts += details(i)                    // appended after the magazine parts: their indices stay put
        return g
    }

    // Small fittings that read up close (Quest: the gun is held at real size): triggers, rail notches, scope turrets,
    // barrel vents, slide serrations, muzzle devices.
    static func details(_ i: Int) -> [Part] {
        var p: [Part] = []
        if i != Guns.launcher { p.append(b(-0.12, -1.15, -1.9, 0.24, 0.95, 0.3, silver, pMetal)) }       // trigger blade
        switch i {
        case Guns.rifle:
            for z: Float in [-6.1, -5.1, 0.1, 1.1, 2.1] { p.append(b(-0.72, 3.25, z, 1.44, 0.22, 0.45, grey, pMetal)) }
            p.append(b(-0.2, -0.55, -13.2, 0.4, 0.5, 0.5, silver, pMetal))                               // sling loop
        case Guns.smg:
            p.append(b(-0.55, 0.75, -13.1, 1.1, 0.9, 1.2, graphite, pMetal))                              // flash hider
            p.append(b(-0.65, 0.5, -10.4, 1.3, 0.25, 3.0, grey, pMetal))                                   // shroud slots
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
        case Guns.revolver:
            for k in 0..<3 { p.append(b(-0.9, -0.2 + Float(k) * 0.5, -2.2, 0.06, 0.25, 1.6, blued * 0.6, pMetal)) }   // cylinder flutes
            p.append(b(-0.06, -0.2, -8.2, 0.12, 0.2, 5.4, silver, pMetal))                                // barrel seam
        default:
            for k in 0..<3 {                                                                              // slide serrations
                p.append(b(0.7, 0.35, 0.9 - Float(k) * 0.45, 0.06, 0.8, 0.2, grey, pMetal))
                p.append(b(-0.76, 0.35, 0.9 - Float(k) * 0.45, 0.06, 0.8, 0.2, grey, pMetal))
            }
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
        case Guns.revolver:
            // The Sheriff's Revolver: a long blued barrel over its ejector rod, a fluted cylinder, a brass trigger guard
            // and a walnut grip with a rounded butt (original design).
            let p: [Part] = [
                b(-0.45, 0.3, -8.5, 0.9, 0.9, 6, blued, pMetal),                  // barrel
                b(-0.3, -0.25, -7, 0.6, 0.5, 4.5, blued, pMetal),                 // ejector rod housing
                b(-0.85, -0.5, -2.5, 1.7, 1.7, 2.2, V3(0.3, 0.32, 0.36), pMetal),  // cylinder
                b(-0.6, -0.7, -0.3, 1.2, 1.9, 1.6, blued, pMetal),               // frame
                b(-0.2, 1.0, 0.9, 0.4, 0.6, 0.7, blued, pMetal),                  // hammer
                b(-0.1, 1.2, -8.3, 0.2, 0.3, 0.4, silver, pMetal),                // front sight
                b(-0.2, 0.55, -8.62, 0.4, 0.4, 0.12, V3(0.02, 0.02, 0.02), 0),    // bore
                b(-0.25, -1.4, -1.6, 0.5, 0.3, 1.6, brass, pMetal),               // trigger guard
                b(-0.55, -2.4, 0.4, 1.1, 1.8, 1.4, walnut, 10),                   // grip
                b(-0.55, -3.7, 0.9, 1.1, 1.4, 1.4, walnut, 10),                   // butt
                b(-0.6, -3.9, 1.0, 1.2, 0.25, 1.3, brass, pMetal),                // butt cap
            ]
            return GunModel(parts: p, mag: [], grip: V3(0, -1.6, 0.9), fore: V3(-0.4, -2.6, 1.2), butt: V3(0, -1.6, 0.9),
                            muzzle: V3(0, 0.75, -8.7), magAt: V3(0, -0.4, -1.4), bolt: V3(0, 1.3, 1.2), scale: 0.68, shouldered: false)
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
        case Guns.smg:
            // Chatter Gun: compact carbine, long straight magazine, vertical fore grip, folding stock.
            var p: [Part] = [
                b(-1.1, -0.3, -6, 2.2, 3.2, 9, enamel, pEnamel),
                b(-1.15, 1.2, -5.5, 2.3, 0.4, 8, grey, pEnamel),
                b(-0.6, 2.9, -5, 1.2, 0.45, 6.5, graphite, pMetal),
                b(-0.7, 3.35, -2.6, 1.4, 1.3, 1.8, graphite, pMetal),
                b(-0.45, 3.55, -2.7, 0.9, 0.9, 0.12, glow * 0.7, pGlow),
                b(-0.8, 0.3, -10, 1.6, 1.8, 4, graphite, pMetal),                  // shroud
                b(-0.4, 0.8, -12, 0.8, 0.8, 2, silver, pMetal),                    // barrel
                b(-0.5, -3, -8.6, 1.0, 3.0, 1.2, graphite, pMetal),                // fore grip
                b(-0.4, 0.2, 3, 0.8, 0.8, 3.8, silver, pMetal),                    // stock rod
                b(-0.8, -1.0, 6.6, 1.6, 2.6, 0.6, graphite, pMetal),               // butt plate
            ]
            p += grip(-0.7, 1.4, top: -0.3, graphite)
            let m = p.count
            p += [b(-0.6, -5.6, -4.3, 1.2, 5.4, 1.6, graphite, pMetal)]
            return GunModel(parts: p, mag: [m], grip: V3(0, -1.6, 0.3), fore: V3(0, -1.8, -8), butt: V3(0, 0.3, 7.2),
                            muzzle: V3(0, 1.2, -12.1), magAt: V3(0, -2.6, -3.5), bolt: V3(-1.4, 1.8, -1), scale: 0.66)
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
            // Capital Sidearm: graphite slide over an enamel frame, grey grip panel, silver sights.
            var p: [Part] = [
                b(-0.7, 0.0, -6.5, 1.4, 1.4, 8, graphite, pMetal),                 // slide
                b(-0.65, -0.65, -6, 1.3, 0.7, 7.2, enamel, pEnamel),               // frame
                b(-0.3, 0.4, -6.62, 0.6, 0.6, 0.12, V3(0.02, 0.02, 0.02), 0),      // bore
                b(-0.15, 1.4, -6, 0.3, 0.3, 0.3, silver, pMetal), b(-0.4, 1.4, 0.8, 0.8, 0.3, 0.4, silver, pMetal),
                b(-0.25, -1.4, -2.2, 0.5, 0.3, 1.8, graphite, pMetal),             // trigger guard
                b(0.66, -2.5, 0.2, 0.08, 1.6, 1.2, grey, pEnamel),                 // grip panel
            ]
            p += [b(-0.65, -2.4, -0.1, 1.3, 1.8, 1.6, enamel, pEnamel)]
            let m = p.count
            p += [b(-0.6, -3.6, 0.3, 1.2, 1.3, 1.5, enamel, pEnamel)]
            return GunModel(parts: p, mag: [m], grip: V3(0, -1.5, 0.6), fore: V3(-0.4, -2.4, 0.9), butt: V3(0, -1.5, 0.6),
                            muzzle: V3(0, 0.7, -6.7), magAt: V3(0, -3.4, 0.9), bolt: V3(0, 0.7, -1), scale: 0.68, shouldered: false)
        }
    }
}
