import Foundation
import simd

// P475 (Oct 27 18:52, a Boreal Station: "let's do some machine guns that are AI-powered, mounted on the ceilings, that
// can't be turned off until you get to some computer room"): on stations first generated with them (legacyP475), a
// ceiling gun hangs at each corner of the ring corridor. It fires on him whenever it sees him below its mount (any way
// round, nothing at or above its own level), winding up first (a red flash and a whine), four rounds a burst. The
// control room's console shuts the station's guns down (the first use there; the next starts the copy), and so does
// the generator dying (the station's power). Shot up, a gun wears out as any block does.
enum CeilingGuns {
    static let key = "ceiling_gun"
    // (dx, row above the bunker floor block, dz): hung from the corridor ceiling (row 5) at the ring's corners.
    static let spots: [(Int, Int, Int)] = [(-12, 4, -12), (12, 4, -12), (-12, 4, 12), (12, 4, 11)]      // (12, 4, 12): the power cable
    static let range: Float = 26, wind: Float = 0.7, gap: Float = 0.1, cool: Float = 1.4, burst = 4, damage: Float = 3
    struct Gun { var look: Float = 0, sees = false, windup: Float = 0, shots = 0, gapT: Float = 0, cool: Float = 0 }
    static var guns: [IVec3: Gun] = [:]
    static var fired = 0                                   // (harness)

    // Below the mount: the target at least 6 degrees under the gun's level.
    static func inArc(_ u: V3) -> Bool { u.y < -0.1 }
}

extension BlockRegistry {
    func registerCeilingGun() {
        guard !has(CeilingGuns.key) else { return }
        var d = BlockDef(CeilingGuns.key, "Ceiling Gun")
        d.tex = ["wall_turret_side"]; d.render = .model; d.layer = .cutout; d.opaque = false; d.skyStop = false
        d.hardness = 3; d.resistance = 12; d.tool = .pickaxe; d.harvestLevel = 1; d.requiresTool = true; d.sound = .metal
        // A plate on the ceiling, the drum of the mount under it, the gun head and its twin barrels.
        d.boxes = [Box(3, 14, 3, 13, 16, 13), Box(5, 10, 5, 11, 14, 11), Box(4, 5, 4, 12, 10, 12),
                   Box(5, 6, 0, 7, 8, 4), Box(9, 6, 0, 11, 8, 4)]
        add(d)
    }
}

extension Game {
    // Every frame (basesTick): the ceiling guns of loaded stations near a player.
    func ceilingGunsTick(_ dt: Float) {
        guard survival, alive, Blocks.has(CeilingGuns.key), !bases.boreal.sites.isEmpty else { return }
        let id = Blocks.id(CeilingGuns.key)
        let eye = player.eye
        for (key, site) in bases.boreal.sites {
            let F = site.S - BorealStation.depth
            guard abs(eye.x - Float(site.cx)) < 48, abs(eye.z - Float(site.cz)) < 48 else { continue }
            let op = stationOps[key]
            let off = op?.gunsOff == true || op?.blown == true
            for (dx, ly, dz) in CeilingGuns.spots {
                let p = IVec3(site.cx + dx, F + ly, site.cz + dz)
                guard world.isLoaded(p.x, p.z), world.block(p.x, p.y, p.z) == id else { CeilingGuns.guns[p] = nil; continue }
                var gs = CeilingGuns.guns[p] ?? CeilingGuns.Gun()
                defer { CeilingGuns.guns[p] = gs }
                if off { gs = CeilingGuns.Gun(); continue }
                let muzzle = V3(Float(p.x) + 0.5, Float(p.y) + 0.25, Float(p.z) + 0.5)
                let to = eye - muzzle
                let d = simd_length(to)
                let u = to / max(d, 0.01)
                gs.cool = max(0, gs.cool - dt)
                gs.look -= dt
                if gs.look <= 0 {
                    gs.look = 0.25
                    gs.sees = d < CeilingGuns.range && CeilingGuns.inArc(u) && world.canSee(muzzle + u * 0.7, eye)
                }
                if gs.shots > 0 {
                    gs.gapT -= dt
                    if gs.gapT <= 0 {
                        gs.gapT = CeilingGuns.gap; gs.shots -= 1
                        let dir = Guns.scatter(u, 0.03)
                        arms.spawn(Slug(pos: muzzle + dir * 0.6, vel: dir * 140, kind: .bullet, damage: CeilingGuns.damage, fromPlayer: false,
                                        shooter: nil, by: "a ceiling gun", life: 0.5, gravity: 0))
                        addFlash(at: muzzle + dir * 0.7, color: V3(5, 3.5, 1.6), radius: 4, life: 0.06)
                        sfx(.gun(1), 0.9, at: muzzle)
                        CeilingGuns.fired += 1
                        // (the station's own gun: heard as one of its own, not a hostile shot to send the garrison to)
                        if gs.shots == 0 { gs.cool = CeilingGuns.cool; baseNoise(at: muzzle, kind: .gunshot, hostile: false) }
                    }
                } else if gs.sees && gs.cool <= 0 {
                    if gs.windup == 0 {
                        sfx(.gun(12), 0.7, at: muzzle)
                        addFlash(at: muzzle, color: V3(4, 0.4, 0.3), radius: 3, life: CeilingGuns.wind)
                    }
                    gs.windup += dt
                    if gs.windup >= CeilingGuns.wind { gs.windup = 0; gs.shots = CeilingGuns.burst; gs.gapT = 0 }
                } else {
                    gs.windup = max(0, gs.windup - dt * 2)
                }
            }
        }
    }
}
