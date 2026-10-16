import Foundation
import simd

// P294 (Oct 15 11:49, "the helicopter is too hard to fly, and tipping it over did nothing"). Crashes for every craft
// that flies on its own (rotors, wings or a flight model; not the Capital's scripted fliers, which crash-land their
// own way: CapitalShips.crashLand):
//   impact     a sudden loss of speed against the ground, a hull or the water over 9 blocks a second is a crash:
//              the hull is torn where it struck (a blast scaled by the impact), the crew aboard is hurt with it, and
//              over 15 b/s the rotor heads break off; over 20 b/s the fuel goes up: a fireball and the craft is a wreck
//              (its engines gone).
//   rolled     a helicopter on its side (past 70 degrees) with its rotor turning near the ground strikes the blades:
//              the rotor heads shear off with a crash and a burst of splinters, and a hard roll (rotor at speed) tears
//              the hull round the mast too.
// A broken rotor can be set back with a new Rotor Head; a wreck's engines must be rebuilt.
enum AircraftCrash {
    static let crashAt: Float = 9
    static let rotorAt: Float = 15
    static let burnAt: Float = 20
    static let tipUp: Float = 0.34               // the hull's up axis this far from vertical (about 70 degrees)
    static var lastVel: [Int: V3] = [:]
    static var cooldown: [Int: Double] = [:]
    static var crashes = 0, rotorsLost = 0       // (counters)

    static func flier(_ s: Ship) -> Bool {
        s.parent == nil && !s.kinematic && (s.flight != nil || !s.rotors.isEmpty || !s.wings.isEmpty)
    }
}

extension Game {
    func aircraftCrashTick(_ dt: Float) {
        guard dt > 0 else { return }
        var seen = Set<Int>()
        for s in world.ships.list where AircraftCrash.flier(s) {
            seen.insert(s.id)
            let before = AircraftCrash.lastVel[s.id] ?? s.vel
            AircraftCrash.lastVel[s.id] = s.vel
            if clock < AircraftCrash.cooldown[s.id] ?? 0 { continue }
            let dv = simd_length(s.vel - before)
            let touching = s.contacts > 0 || s.grounded || s.submerged > 0
            if touching && dv > AircraftCrash.crashAt {
                AircraftCrash.cooldown[s.id] = clock + 1.5
                aircraftCrash(s, dv: dv, toward: dv > 0.01 ? (before - s.vel) / dv : V3(0, -1, 0))
                continue
            }
            // Rolled over with the blades turning near the ground.
            if let f = s.flight, f.kind == .heli, !s.rotors.isEmpty, f.rpm > 0.3, f.agl < f.rotorRadius(s) + 2 {
                let up = s.dirToWorld(V3(0, 1, 0))
                if up.y < AircraftCrash.tipUp {
                    AircraftCrash.cooldown[s.id] = clock + 1.5
                    rotorStrike(s, hard: f.rpm > 0.7)
                }
            }
        }
        if AircraftCrash.lastVel.count > seen.count + 8 {
            AircraftCrash.lastVel = AircraftCrash.lastVel.filter { seen.contains($0.key) }
            AircraftCrash.cooldown = AircraftCrash.cooldown.filter { seen.contains($0.key) }
        }
    }

    private func aircraftCrash(_ s: Ship, dv: Float, toward: V3) {
        AircraftCrash.crashes += 1
        let k: Float = min(1, (dv - AircraftCrash.crashAt) / 12)
        // Where it struck: the hull's edge on the side it was moving.
        let half = (s.worldMax - s.worldMin) * 0.5
        let mid = (s.worldMax + s.worldMin) * 0.5
        let at = mid + simd_clamp(toward * simd_length(half), -half, half) * 0.8
        sfx(.shipCollideHard, 1.5 + k, at: at)
        addShakeNear(at, 0.4 + 0.5 * k)
        world.ships.blast(at: at, power: 1.5 + 3 * k, game: self)
        for _ in 0..<Int(6 + 14 * k) { particles.smoke(at: at + V3(Rand.float(in: -1...1), Rand.float(in: 0...1.5), Rand.float(in: -1...1))) }
        // The crew aboard takes the blow too.
        if world.ships.aboardOrPilot?.root === s && survival {
            hurtPlayer(Int((dv - AircraftCrash.crashAt) * 1.2) + 2, from: at, cause: "crashed", knockback: 0, type: .generic)
        }
        if dv > AircraftCrash.rotorAt && !s.rotors.isEmpty { breakRotors(s) }
        if dv > AircraftCrash.burnAt {
            s.engines = 0
            s.wrecked = true
            Explosion.explode(at: mid, power: 3.5, game: self, fire: true)
        }
    }

    // The blades strike the ground: they shear off.
    private func rotorStrike(_ s: Ship, hard: Bool) {
        AircraftCrash.crashes += 1
        let hubs = s.rotors.map { s.toWorld($0 + V3(0.5, 0.5, 0.5)) }
        breakRotors(s)
        for h in hubs {
            sfx(.shipCollideHard, hard ? 2 : 1.4, at: h)
            sfx(.breakBlock(.wood), 1.2, at: h)
            sfx(.bulletImpact(.metal), 1, at: h)
            for _ in 0..<14 { particles.smoke(at: h + V3(Rand.float(in: -2...2), Rand.float(in: -0.5...1), Rand.float(in: -2...2)), dark: false) }
            if hard { world.ships.blast(at: h, power: 2.2, game: self) }
            addShakeNear(h, hard ? 0.7 : 0.4)
        }
        if hard && world.ships.aboardOrPilot?.root === s && survival {
            hurtPlayer(4, from: hubs.first ?? s.pos, cause: "crashed", knockback: 0, type: .generic)
        }
    }

    private func breakRotors(_ s: Ship) {
        let g = s.grid
        var cells: [IVec3] = []
        for i in 0..<g.blocks.count where g.blocks[i] != AIR && ShipParts.kinds[Int(g.blocks[i])] == .rotor {
            cells.append(IVec3(i % g.sx, i / (g.sx * g.sz), (i / g.sx) % g.sz))
        }
        for c in cells {
            let at = s.toWorld(V3(Float(c.x), Float(c.y), Float(c.z)) + 0.5)
            world.ships.setBlock(s, c, AIR)
            particles.blockBreak(Blocks.id("ship_rotor"), at: IVec3(Int(floor(at.x)), Int(floor(at.y)), Int(floor(at.z))))
        }
        if !cells.isEmpty { AircraftCrash.rotorsLost += 1; s.flight?.rpm = 0 }
    }

    private func addShakeNear(_ p: V3, _ amount: Float) {
        let d = simd_length(player.pos - p)
        if d < 40 { addShake(amount * (1 - d / 40)) }
    }
}
