import Foundation
import simd

// P200 (Oct 13: "the wall turret should kill shit for me if I place it"): a wall turret the player places is on the
// player's side. It is remembered (saved in the world's extras as "playerTurrets"), the Greywall bases' turret tick
// skips it, and here it watches the way it faces: the nearest hostile (AutoTurrets.hostile: monsters always, soldiers
// and the neutral kinds only while they're after the player) within 32 blocks in front of it and in sight gets a
// three-round burst (0.6 s wind-up, 1.6 s between bursts). Its rounds are the player's side but spare livestock.
enum PlayerTurrets {
    static var sites: Set<IVec3> = []
    static var cool: [IVec3: Float] = [:]
    static var clock: Float = 0
    static let range: Float = 32

    static func isTurret(_ b: BlockID) -> Bool {
        let (gun, hurt) = GreywallAlarmState.turretIds
        return (b >= gun && b < gun + 4) || (b >= hurt && b < hurt + 4)
    }

    static func placed(_ g: Game, _ p: IVec3) {
        guard isTurret(g.world.block(p.x, p.y, p.z)) else { return }
        sites.insert(p)
        g.onToast?("Wall turret ready")
    }

    static func save(_ d: inout [String: String]) {
        if !sites.isEmpty { d["playerTurrets"] = sites.map { "\($0.x),\($0.y),\($0.z)" }.joined(separator: ";") }
    }
    static func load(_ d: [String: String]) {
        sites = []; cool = [:]
        for s in (d["playerTurrets"] ?? "").split(separator: ";") {
            let v = s.split(separator: ",").compactMap { Int($0) }
            if v.count == 3 { sites.insert(IVec3(v[0], v[1], v[2])) }
        }
    }

    // Every frame (from greywallTurretsTick's caller); each turret looks four times a second.
    static func tick(_ g: Game, _ dt: Float) {
        guard !sites.isEmpty, g.dim.dim == .overworld else { return }
        clock += dt
        guard clock >= 0.1 else { return }
        let step = clock
        clock = 0
        let w = g.world
        let (gun, hurt) = GreywallAlarmState.turretIds
        let dirs = GreywallAlarmState.turretDirs
        var gone: [IVec3] = []
        for p in sites {
            guard w.isLoaded(p.x, p.z) else { continue }
            let b = w.block(p.x, p.y, p.z)
            guard isTurret(b) else { gone.append(p); continue }
            if let r = FactionRaids.active, r.turrets.contains(p) { continue }      // a raid's defence has it (O5)
            let damaged = b >= hurt
            let f = Int(b - (damaged ? hurt : gun))
            let left = (cool[p] ?? 0) - step
            cool[p] = left
            guard left <= 0 else { continue }
            let muzzle = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5) + dirs[f] * 0.6
            var best: (Mob, Float)?
            for m in g.mobs.mobs where AutoTurrets.hostile(m, g) {
                let aim = m.pos + V3(0, m.height * 0.5, 0)
                let v = aim - muzzle, d = simd_length(v)
                guard d < range, d > 1, best == nil || d < best!.1, simd_dot(v / d, dirs[f]) > 0.2 else { continue }
                guard w.canSee(muzzle + dirs[f] * 0.5, aim) else { continue }
                best = (m, d)
            }
            guard let (m, d) = best else { cool[p] = 0.25; continue }
            let aim = m.pos + V3(0, m.height * 0.5, 0) + m.vel * (d / 140)
            let to = simd_normalize(aim - muzzle)
            for k in 0..<3 {
                let dir = Guns.scatter(to, damaged ? 0.04 : 0.02)
                g.arms.spawn(Slug(pos: muzzle + dir * (0.4 + Float(k) * 1.2), vel: dir * 140, kind: .bullet, damage: 4, fromPlayer: true,
                                  shooter: nil, by: "your wall turret", life: 0.4, gravity: 0))
            }
            g.addFlash(at: muzzle + to * 0.5, color: V3(5, 3.5, 1.6), radius: 4, life: 0.08)
            g.sfx(.gun(1), 0.9, at: muzzle)
            cool[p] = 1.6
        }
        for p in gone { sites.remove(p); cool[p] = nil }
    }
}
