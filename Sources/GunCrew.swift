import Foundation
import simd

// D40: hire a crew to man your ship's guns. Your companions (hired at a harbourmaster, a quartermaster or anywhere:
// Companions.swift) who stand aboard your vessel are its gun crew. While nobody is at the helm (you're on deck with a
// rifle, ashore, or swimming) each hand aboard mans one turret: it swings onto the nearest enemy vessel, crawler or
// soldier within 110 blocks, the barrels come up to the range and it fires when it bears. Hull cannons with no turret
// fire when the target lies off their muzzles. Enemies: the Corsairs, and every army or navy that isn't your ally
// (FactionRep). At the helm you aim the guns yourself, as before.
extension ShipManager {
    static let crewRange: Float = 110
    static var crewVolleys = 0                         // (harness)

    // Yours: taken, built or bought, with no faction's colours (NavalPort.yourVessel's rule).
    func isYours(_ s: Ship) -> Bool {
        s.parent == nil && (s.captured || (s.factionValue == .none && (s.role == nil || s.role == NavalPort.hullRole)))
    }

    static func hostile(_ f: Faction) -> Bool {
        if f == .none { return false }
        if f == .corsairs { return true }
        return FactionRep.of(f) < FactionRep.allyAt
    }

    // The nearest enemy of the player's crews: a hull, or a soldier.
    func crewFoe(near p: V3, game g: Game) -> V3? {
        var best: V3?, bd = ShipManager.crewRange
        for o in list where o.parent == nil && !o.wrecked && ShipManager.hostile(o.factionValue) && !isYours(o) {
            let d = boundsDistance(o, p)
            if d < bd {
                bd = d
                let c = simd_clamp(p, o.worldMin, o.worldMax)
                best = c + (o.pos - c) * 0.35
            }
        }
        for m in g.mobs.mobs where m.health > 0 && !m.hired && Soldier.rank(m.kind) != nil && ShipManager.hostile(m.factionValue) {
            let d = simd_length(m.pos - p)
            if d < bd { bd = d; best = m.pos + V3(0, m.height * 0.5, 0) }
        }
        // P478: and anything else out for him (monsters, brigands, raiders) within a gunner's sight, never one so near
        // him that the shell would burst on him.
        for m in g.mobs.mobs where m.health > 0 && !m.hired && m.kind.hostile && Soldier.rank(m.kind) == nil && m.aggro
            && simd_length(m.pos - g.player.pos) > 7 {
            let d = simd_length(m.pos - p)
            if d < min(bd, VehicleGunners.sight) { bd = d; best = m.pos + V3(0, m.height * 0.5, 0) }
        }
        return best
    }

    func aboard(_ m: Mob, _ s: Ship) -> Bool {
        let p = m.pos
        return p.x > s.worldMin.x - 1 && p.x < s.worldMax.x + 1 && p.z > s.worldMin.z - 1 && p.z < s.worldMax.z + 1
            && p.y > s.worldMin.y - 1 && p.y < s.worldMax.y + 2
    }

    // Every tick (vesselTick): your crews at the guns.
    // P478: also while he drives, at the turrets a companion has climbed onto (VehicleGunners): theirs to lay and fire, his
    // sight keeps the rest. Each gun is laid for its own shell (a calibre gun's flat, fast one, as the tank sight does).
    func gunCrewTick(_ dt: Float, game g: Game) {
        let hands = g.companions
        guard !hands.isEmpty else { return }
        for s in list where isYours(s) && !s.wrecked {
            let tur = turrets(of: s).filter { !$0.cannons.isEmpty }
            let gunners = tur.filter { VehicleGunners.manned($0) }
            let driven = s === pilot
            if driven && gunners.isEmpty { continue }
            let crew = driven ? gunners.count : max(gunners.count, hands.filter { aboard($0, s) }.count)
            guard crew > 0 else { continue }
            guard !tur.isEmpty || !s.cannons.isEmpty else { continue }
            guard let aim = crewFoe(near: s.pos, game: g) else {
                for t in (driven ? gunners : tur) { t.aimAt = nil }
                continue
            }
            let manned = driven ? gunners : Array((gunners + tur.filter { t in !gunners.contains { $0 === t } }).prefix(crew))
            for t in manned {
                t.aimAt = aim
                let muzzle = t.toWorld(t.pivot)
                let d = aim - muzzle
                let horiz = simd_length(V2(d.x, d.z))
                guard horiz >= 10 else { continue }
                let (sv, sg) = t.shellFlight
                let elev = ShipManager.elevation(horiz, d.y, speed: sv, gravity: sg)
                t.gunPitch += (max(-0.2, min(0.6, elev)) - t.gunPitch) * min(1, dt * 3)
                let tf = t.dirToWorld(V3(0, 0, -1))
                let a = simd_normalize(V2(tf.x, tf.z) + V2(1e-5, 0)), b = simd_normalize(V2(d.x, d.z) + V2(1e-5, 0))
                if t.reload <= 0 && acosf(max(-1, min(1, simd_dot(a, b)))) < 0.15 && fire(t, pitch: elev, game: g) > 0 { ShipManager.crewVolleys += 1 }
            }
            // The hull's own cannons, when the target lies off a muzzle.
            if !driven, s.reload <= 0, !s.cannons.isEmpty, crew > manned.count {
                for (c, dir) in s.cannons {
                    let muzzle = s.toWorld(c)
                    let d = aim - muzzle
                    let horiz = simd_length(V2(d.x, d.z))
                    guard horiz >= 10 else { continue }
                    let md = s.dirToWorld(dir)
                    let a = simd_normalize(V2(md.x, md.z) + V2(1e-5, 0)), b = simd_normalize(V2(d.x, d.z) + V2(1e-5, 0))
                    if acosf(max(-1, min(1, simd_dot(a, b)))) < 0.2 {
                        let (sv, sg) = s.shellFlight
                        if fireHull(s, pitch: ShipManager.elevation(horiz, d.y, speed: sv, gravity: sg), game: g) > 0 { ShipManager.crewVolleys += 1 }
                        break
                    }
                }
            }
        }
    }

    // Elevation to land a 45 b/s shell `horiz` away and `dy` up under gravity 20 (the low arc).
    static func elevation(_ horiz: Float, _ dy: Float, speed v: Float = 45, gravity gr: Float = 20) -> Float {
        let v2 = v * v
        let disc: Float = v2 * v2 - gr * (gr * horiz * horiz + 2 * dy * v2)
        return disc > 0 ? atanf((v2 - sqrtf(disc)) / (gr * horiz)) : 0.6
    }

    // The hull's cannons only (its turrets are manned on their own).
    func fireHull(_ s: Ship, pitch: Float, game g: Game) -> Int {
        let tur = turrets(of: s)
        let saved = tur.map { $0.reload }
        for t in tur { t.reload = max(t.reload, 0.01) }
        let n = fire(s, pitch: pitch, game: g)
        for (t, r) in zip(tur, saved) { t.reload = r }
        return n
    }
}
