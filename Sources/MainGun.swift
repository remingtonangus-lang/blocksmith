import Foundation
import simd

// The Meridian frigate's spinal gun, the Tidebreaker (Remington, Oct 9 2026: "make the gun the centrepiece"). It was
// the "MAC", a Halo term, renamed in everything the player sees (docs/status/ip-renames.md).
//   Barrel: 63 blocks between the bow booms with glowing coil rings (CapitalFrigate.swift).
//   Charge: 2.6 s, telegraphed to everyone: a rising whine with accelerating coil thumps, a light pulse running
//     breech to muzzle faster and brighter, sparks drawn into the muzzle; on board the deck shakes and the
//     controllers pulse harder and faster.
//   Shot: a white-blue slug at 420 b/s with a glowing wake, a muzzle blast that lights the sky, steam venting from
//     every coil, a recoil lurch, a crack heard 480 blocks off.
//   Impact: a crater bounded to MainGun.craterCap blocks (nearest first, so a capped crater is still a round
//     bowl) and carved 400 blocks a frame (Explosion.swift CraterJob), a light column, a dust shockwave that runs out at 64 b/s and flattens mobs out to 48 blocks, a long
//     ground rumble (sound, shake and haptics arriving with the wave), smoke rising from the bowl.
//   Reload: 22 s from the helm, 30 s for the frigate's own crew.
// Frame time around a blast is logged by MainGunPerf (the Quest perf monitor and questcheck's main gun test).
enum MainGun {
    static let name = "Tidebreaker"
    static let chargeTime: Float = 2.6
    static let playerReload: Float = 22
    static let aiReload: Float = 30
    static let slugSpeed: Float = 420
    static let craterRadius: Float = 13
    static let craterCap = 9000             // blocks removed per shot at most (the remesh and fluid work it causes)
    static let shockRadius: Float = 48      // mobs inside are struck as the front passes
    static let shockFelt: Float = 200       // players feel the front (shake, haptics) out to here
    static let shockSpeed: Float = 64
    static let shockHeight: Float = 20
    static let pendingCap = 16                          // off-world hits remembered (this session) to dig on arrival      // the front runs along the ground: a frigate's deck 40 up is spared
    // The last impact (tests, perf notes).
    private(set) static var impacts = 0
    private(set) static var lastImpact = V3(0, 0, 0)
    private(set) static var lastCrater = 0

    // How much a player feels this ship's gun: fully at its helm or aboard, fading out to 160 blocks away.
    static func presence(_ s: Ship, _ g: Game) -> Float {
        let ships = g.world.ships
        if ships.pilot?.root === s || ships.aboard?.root === s { return 1 }
        let d = simd_length(s.pos - g.player.eye)
        return max(0, 1 - d / 160) * 0.6
    }

    static func noteImpact(at p: V3) { impacts += 1; lastImpact = p; lastCrater = 0 }
    static func noteCrater(_ n: Int) { lastCrater = n }
    static var warnings = 0                             // charges an AI frigate aimed at a player (MainGunTests)

    // Controller rumble (Touch controllers on the Quest, the pad on the Mac).
    static func feel(_ strength: Float, _ seconds: Float, sharpness: Float) {
        let pm = PadManager.shared
        guard strength > 0.02, pm.connected, Settings.shared.rumble > 0 else { return }
        pm.rumble(min(1, strength), seconds, sharpness: sharpness)
    }
}

// An expanding ring of force and dust from a Tidebreaker impact.
final class Shockwave {
    let center: V3
    let owner: Int
    var r: Float = 0
    var age: Float = 0
    var struck = Set<ObjectIdentifier>()
    var felt = 0                            // bitmask of split-screen seats the front has reached
    var crater: CraterJob?                  // the bowl, carved a slice a frame
    init(center: V3, owner: Int) { self.center = center; self.owner = owner }
}

extension ShipManager {
    // Starts the Tidebreaker's charge (the helm's attack, or the frigate's own crew with a target in its cone).
    func startMainGunCharge(_ s: Ship, _ st: CapitalState, _ g: Game, byPlayer: Bool) {
        st.gunCharge = 0
        st.gunPulse = 0
        st.gunByPlayer = byPlayer
        let md = s.dirToWorld(st.mainGunDir)
        let mid = s.toWorld(st.mainGunMuzzle) - md * (st.mainGunLength * 0.5)
        // On board, the whine follows the listener (the hull carries it); from outside it sounds from the barrel.
        g.sfx(.mainGunCharge, 1, at: MainGun.presence(s, g) >= 1 ? nil : mid)
        // Aimed at a player: a warning in words and in the hands, so the 2.6 s charge is a chance to get clear.
        if !byPlayer, let t = st.target, t.player {
            g.coop.withSeat(t.seat, g) {
                g.onToast?("The frigate is charging its main gun at you: get clear!")
                MainGun.feel(0.5, 0.25, sharpness: 0.3)
            }
            MainGun.warnings += 1
        }
    }

    // Per frame for every Meridian frigate: the charge's light, sparks, shake and haptics; the shot when it is full.
    func mainGunTick(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        guard st.gunCharge >= 0 else { return }
        if s.wrecked || (!st.gunByPlayer && !st.driverAlive) { st.gunCharge = -1; return }
        if st.gunByPlayer && pilot === s { st.gunPitch = g.player.pitch }
        st.gunCharge += dt
        let k = min(1, st.gunCharge / MainGun.chargeTime)
        let md = s.dirToWorld(st.mainGunDir)
        let mw = s.toWorld(st.mainGunMuzzle)
        let len = st.mainGunLength
        let near = MainGun.presence(s, g)
        if simd_length(mw - g.player.eye) < 320 || near > 0 {
            // A pulse of light runs down the coils from the breech to the muzzle, quicker and brighter as it fills.
            let run = st.gunCharge * (0.5 + 2.5 * k)
            let at = mw - md * (len * (1 - (run - floorf(run))))
            g.addFlash(at: at, color: V3(0.5, 1.0, 2.6) * (1 + 3 * k), radius: 7 + 9 * k, life: 0.07)
            g.addFlash(at: mw + md, color: V3(0.9, 1.6, 3.6) * (0.4 + 4 * k * k), radius: 6 + 18 * k, life: 0.07)
            let layer = Int(Tex.id("smoke"))
            // The coil rings glow through the hull, each flaring as the pulse passes it, and a corona gathers at the
            // muzzle: big soft glow puffs that read from a few hundred blocks (the lights alone don't, beyond ~40).
            let head = len * (run - floorf(run))                 // the pulse's distance back from the breech
            for c in stride(from: 9, through: Int(len), by: 6) {
                let back = Float(c)                              // coil ring c blocks behind the muzzle
                let hit = max(0, 1 - abs((len - back) - head) / 8)
                let glow = 0.15 + 0.35 * k + 0.6 * hit
                g.particles.add(Particle(pos: s.toWorld(st.mainGunMuzzle + V3(0, 0, back)), vel: s.vel, life: dt * 1.5, maxLife: dt * 1.5,
                                         layer: layer, uv0: V2(0, 0), uvSize: 1, size: 3.2 + 1.6 * hit, gravity: 0,
                                         color: V3(0.35, 0.75, 1.0) * glow, collide: false, glow: true))
            }
            g.particles.add(Particle(pos: mw + md * 1.5, vel: s.vel, life: dt * 1.5, maxLife: dt * 1.5, layer: layer, uv0: V2(0, 0),
                                     uvSize: 1, size: 1.5 + 6 * k * k, gravity: 0, color: V3(0.6, 0.9, 1.0) * (0.4 + 0.6 * k),
                                     collide: false, glow: true))
            // Sparks drawn in toward the muzzle along the barrel.
            let side = simd_normalize(simd_cross(md, V3(0, 1, 0)) + V3(0, 0, 1e-4))
            let up = simd_cross(side, md)
            var n = dt * (40 + 260 * k)
            while n > 0 {
                if n < 1 && Rand.float(in: 0..<1) > n { break }
                n -= 1
                let a = Rand.float(in: 0..<(2 * .pi)), rr = Rand.float(in: 2...5)
                let off = (side * cosf(a) + up * sinf(a)) * rr - md * Rand.float(in: 0...6)
                g.particles.add(Particle(pos: mw + off, vel: s.vel - off * 3 + md * 4, life: 0.3, maxLife: 0.3, layer: layer, uv0: V2(0, 0),
                                         uvSize: 1, size: Rand.float(in: 0.12...0.3), gravity: 0, color: V3(0.55, 0.85, 1), collide: false, glow: true))
            }
        }
        if near > 0 {
            g.addShake((0.1 + 0.3 * k * k) * near)
            st.gunPulse -= dt
            if st.gunPulse <= 0 {
                st.gunPulse = 0.34 - 0.26 * k                       // the coil thumps quicken
                MainGun.feel((0.15 + 0.55 * k) * near, 0.05, sharpness: 0.65)
            }
        }
        guard st.gunCharge >= MainGun.chargeTime else { return }
        st.gunCharge = -1
        var dir = md
        if st.gunByPlayer {
            // Raised or lowered with the helm's view, 30 degrees down to 15 up.
            let p = max(-0.52, min(0.26, st.gunPitch))
            let h = simd_normalize(V2(md.x, md.z) + V2(1e-5, 0))
            dir = simd_normalize(V3(h.x * cosf(p), sinf(p), h.y * cosf(p)))
        } else if let t = st.target {
            let dist = simd_length(t.point - mw)
            dir = simd_normalize(t.point + t.vel * (dist / MainGun.slugSpeed) - mw + V3(1e-5, 0, 0))
            if simd_dot(dir, md) < 0.85 { dir = simd_normalize(md + (dir - md) * 0.5) }
        }
        st.mainGunCD = st.gunByPlayer ? MainGun.playerReload : MainGun.aiReload
        fireMainGun(s, st, dir: dir, game: g)
    }

    // The shot: the slug (ShipCombat kind 3), the muzzle blast, venting coils, recoil.
    func fireMainGun(_ s: Ship, _ st: CapitalState, dir: V3, game g: Game) {
        let mw = s.toWorld(st.mainGunMuzzle)
        let md = s.dirToWorld(st.mainGunDir)
        let sh = Shell(pos: mw + dir * 3, vel: dir * MainGun.slugSpeed + s.vel, owner: s.id, power: 12)
        sh.gravity = 0.4
        sh.kind = 3
        sh.life = 3.5
        shells.append(sh)
        let near = MainGun.presence(s, g)
        g.sfx(.mainGunFire, 1, at: near >= 1 ? nil : mw)
        g.baseNoise(at: mw, kind: .cannon, hostile: true)
        g.addFlash(at: mw + dir * 6, color: V3(4, 6, 10), radius: 56, life: 0.55)
        let layer = Int(Tex.id("smoke"))
        // Muzzle blast: a cone of white-hot glow, then a ring of smoke round the bow.
        for _ in 0..<70 {
            let spread = V3(Rand.float(in: -1...1), Rand.float(in: -1...1), Rand.float(in: -1...1)) * 0.25
            let v = simd_normalize(dir + spread) * Rand.float(in: 20...70)
            g.particles.add(Particle(pos: mw + dir * 2, vel: v + s.vel, life: Rand.float(in: 0.15...0.4), maxLife: 0.4, layer: layer, uv0: V2(0, 0),
                                     uvSize: 1, size: Rand.float(in: 0.8...2.2), gravity: 0, color: V3(0.85, 0.95, 1), collide: false, glow: true))
        }
        let side = simd_normalize(simd_cross(dir, V3(0, 1, 0)) + V3(0, 0, 1e-4))
        let up = simd_cross(side, dir)
        for i in 0..<48 {
            let a = Float(i) / 48 * 2 * .pi
            let r = side * cosf(a) + up * sinf(a)
            let g0 = Rand.float(in: 0.55...0.75)
            g.particles.add(Particle(pos: mw + dir * 3 + r * 2, vel: r * Rand.float(in: 10...16) + dir * 6 + s.vel, life: Rand.float(in: 1.2...2.2), maxLife: 2.2,
                                     layer: layer, uv0: V2(0, 0), uvSize: 1, size: Rand.float(in: 1.0...1.8), gravity: -0.3, color: V3(g0, g0, g0), collide: false))
        }
        // Steam venting from each coil ring along the barrel.
        var z: Float = 3
        while z < st.mainGunLength {
            let c = mw - md * z
            for _ in 0..<3 {
                let o = V3(Rand.float(in: -1...1), Rand.float(in: 0...1), Rand.float(in: -1...1))
                g.particles.add(Particle(pos: c + o * 3, vel: o * 5 + V3(0, 3, 0) + s.vel, life: Rand.float(in: 0.8...1.6), maxLife: 1.6, layer: layer,
                                         uv0: V2(0, 0), uvSize: 1, size: Rand.float(in: 0.6...1.1), gravity: -0.6, color: V3(0.85, 0.88, 0.92), collide: false))
            }
            z += 6
        }
        // Recoil: the hull lurches back (its drive takes it up again over a second or two).
        s.vel -= dir * 4
        if near > 0 {
            g.addShake(0.9 * near)
            MainGun.feel(near, 0.45, sharpness: 0.15)
        }
    }

    // A slug's impact: crater, light column, shockwave, rumble.
    func mainGunImpact(at p: V3, owner: Int, game g: Game) {
        MainGunPerf.blast(clock: g.clock)
        MainGun.noteImpact(at: p)
        let wave = Shockwave(center: p, owner: owner)
        if craterGroundLoaded(p) {
            wave.crater = CraterJob(at: p, radius: MainGun.craterRadius, cap: MainGun.craterCap, game: g)
        } else if pendingCraters.count < MainGun.pendingCap {
            pendingCraters.append(p)                         // dug when the player comes near enough to load it
        }
        shockwaves.append(wave)
        g.sfx(.mainGunRumble, 1, at: p)
        for k in 1...3 { g.particles.explosion(at: p + V3(0, Float(k) * 4, 0), power: Float(8 - k)) }
        mainGunFireball(at: p, game: g)
        g.addFlash(at: p + V3(0, 6, 0), color: V3(6, 6.5, 8), radius: 90, life: 1.1)
        // The flash and the first jolt arrive at once; the ground shake comes with the wave (updateShockwaves).
        let d = simd_length(p - g.player.eye)
        if d < MainGun.shockFelt { g.addShake(0.5 * (1 - d / MainGun.shockFelt)) }
    }

    // A fireball the size of the crater and a column of dark smoke climbing out of it, in puffs big enough to read
    // from the helm a hundred blocks and more away (an ordinary explosion's puffs are under a block wide).
    func mainGunFireball(at p: V3, game g: Game) {
        let smoke = Int(Tex.id("smoke"))
        let R = MainGun.craterRadius
        // The fireball rolling out over the bowl, hottest at its heart.
        for _ in 0..<16 {
            let o = V3(Rand.float(in: -1...1), Rand.float(in: 0...1), Rand.float(in: -1...1)) * (R * 0.25)
            g.particles.add(Particle(pos: p + o + V3(0, 3, 0), vel: o * 0.8, life: Rand.float(in: 0.25...0.5), maxLife: 0.5, layer: smoke,
                                     uv0: V2(0, 0), uvSize: 1, size: Rand.float(in: 6...10), gravity: -2, color: V3(1, 0.95, 0.7),
                                     collide: false, glow: true))
        }
        for _ in 0..<120 {
            let d = simd_normalize(V3(Rand.float(in: -1...1), Rand.float(in: 0...1), Rand.float(in: -1...1)))
            let heat = Rand.float(in: 0.35...0.85)
            g.particles.add(Particle(pos: p + d * Rand.float(in: 0...(R * 0.5)), vel: d * Rand.float(in: 8...20) + V3(0, 5, 0),
                                     life: Rand.float(in: 0.6...1.8), maxLife: 1.8, layer: smoke, uv0: V2(0, 0), uvSize: 1,
                                     size: Rand.float(in: 3.5...9), gravity: -3, color: V3(1, heat, heat * 0.3),
                                     collide: false, glow: true))
        }
        for i in 0..<40 {
            let up = Float(i) / 40
            let o = V3(Rand.float(in: -1...1), 0, Rand.float(in: -1...1)) * (R * 0.3)
            let gy = Rand.float(in: 0.12...0.24)
            g.particles.add(Particle(pos: p + o + V3(0, up * 6, 0), vel: V3(o.x * 0.1, Rand.float(in: 4...12), o.z * 0.1),
                                     life: Rand.float(in: 5...8), maxLife: 8, layer: smoke, uv0: V2(0, 0), uvSize: 1,
                                     size: Rand.float(in: 3.5...7), gravity: 0.8, color: V3(gy, gy, gy), collide: false))
        }
    }

    // Moves the shockwaves out: mobs struck as the front passes, players shaken, dust along the front, smoke rising
    // from the bowl. Called once per frame (updateShells).
    // Every chunk the bowl reaches is loaded (a slug past the streamed world lands on the generator's ground).
    func craterGroundLoaded(_ p: V3) -> Bool {
        let r = Int(ceilf(MainGun.craterRadius)) + 1
        for z in stride(from: Int(floor(p.z)) - r, through: Int(floor(p.z)) + r, by: CS) {
            for x in stride(from: Int(floor(p.x)) - r, through: Int(floor(p.x)) + r, by: CS) where world.chunkAt(x, z) == nil { return false }
        }
        return world.chunkAt(Int(floor(p.x)) + r, Int(floor(p.z)) + r) != nil
    }

    // Twice a second: a pending crater whose ground has loaded is dug quietly, a slice a frame like any other.
    func updatePendingCraters(_ dt: Float, game g: Game) {
        guard !pendingCraters.isEmpty else { return }
        pendingCraterTimer -= dt
        guard pendingCraterTimer <= 0 else { return }
        pendingCraterTimer = 0.5
        if let i = pendingCraters.firstIndex(where: { craterGroundLoaded($0) }) {
            let p = pendingCraters.remove(at: i)
            let wave = Shockwave(center: p, owner: -1)
            wave.r = MainGun.shockFelt                       // no front, no mobs struck, no shake, no smoke: just the bowl
            wave.age = 5
            wave.felt = ~0
            wave.crater = CraterJob(at: p, radius: MainGun.craterRadius, cap: MainGun.craterCap, game: g, quiet: true)
            shockwaves.append(wave)
        }
    }

    func updateShockwaves(_ dt: Float, game g: Game) {
        updatePendingCraters(dt, game: g)
        if shockwaves.isEmpty { return }
        let layer = Int(Tex.id("smoke"))
        for w in shockwaves {
            if let j = w.crater, !j.done, w.age > 0 {                // from the frame after the impact
                if j.step(g, blocks: CraterJob.blocksPerFrame) { MainGun.noteCrater(j.removed) }
            }
            let r0 = w.r
            w.age += dt
            w.r += MainGun.shockSpeed * dt
            let c = w.center
            if r0 < MainGun.shockRadius {
                for m in g.mobs.mobs where m.health > 0 && m.deck?.root.id != w.owner && !w.struck.contains(ObjectIdentifier(m)) {
                    let dx = m.pos.x - c.x, dz = m.pos.z - c.z
                    let d = (dx * dx + dz * dz).squareRoot()
                    guard d <= w.r && d <= MainGun.shockRadius && abs(m.pos.y - c.y) < MainGun.shockHeight else { continue }
                    w.struck.insert(ObjectIdentifier(m))
                    let f = 1 - d / MainGun.shockRadius
                    m.hit(from: c, damage: Int((6 + 54 * f * f).rounded()), knockback: 0)
                    let out = d > 0.1 ? V3(dx / d, 0, dz / d) : V3(1, 0, 0)
                    m.vel += out * (6 + 14 * f) + V3(0, 3 + 6 * f, 0)
                }
                // Dust thrown up along the front.
                for _ in 0..<14 {
                    let a = Rand.float(in: 0..<(2 * .pi))
                    let o = V3(cosf(a), 0, sinf(a))
                    let x = Int(floor(c.x + o.x * w.r)), z = Int(floor(c.z + o.z * w.r))
                    let top = world.topY(x, z)
                    let y = top >= 0 && abs(Float(top) - c.y) < MainGun.shockHeight ? Float(top) + 1.2 : c.y
                    let tone = Rand.float(in: 0.42...0.58)
                    g.particles.add(Particle(pos: V3(c.x + o.x * w.r, y, c.z + o.z * w.r), vel: o * Rand.float(in: 8...16) + V3(0, Rand.float(in: 1...4), 0),
                                             life: Rand.float(in: 0.6...1.1), maxLife: 1.1, layer: layer, uv0: V2(0, 0), uvSize: 1,
                                             size: Rand.float(in: 1.0...2.2), gravity: -0.2, color: V3(tone, tone * 0.93, tone * 0.8), collide: false))
                }
            }
            // Players: the ground shake and a long rumble in the hands when the front reaches them; inside the
            // strike radius, a blow (survival) and a shove.
            for i in 0..<max(1, g.coop.seatCount) where w.felt & (1 << i) == 0 {
                g.coop.withSeat(i, g) {
                    let pp = g.player.pos
                    let d = simd_length(V2(pp.x - c.x, pp.z - c.z))
                    guard d <= w.r else { return }
                    w.felt |= 1 << i
                    guard d < MainGun.shockFelt else { return }
                    let f2 = 1 - d / MainGun.shockFelt
                    let onShooter = self.aboard?.root.id == w.owner || self.pilot?.root.id == w.owner
                    g.addShake((onShooter ? 0.35 : 0.85) * f2)
                    MainGun.feel(0.9 * f2, 1.4, sharpness: 0.05)
                    if d < MainGun.shockRadius && !onShooter && abs(pp.y - c.y) < MainGun.shockHeight {
                        let f = 1 - d / MainGun.shockRadius
                        if g.survival { g.hurtPlayer(Int((2 + 10 * f * f).rounded()), from: c, cause: "was flattened by a shockwave", knockback: 0, type: .explosion) }
                        let out = d > 0.1 ? V3((pp.x - c.x) / d, 0, (pp.z - c.z) / d) : V3(1, 0, 0)
                        g.player.vel += out * (3 + 7 * f) + V3(0, 2 + 3 * f, 0)
                    }
                }
            }
            // Smoke rising from the bowl for a few seconds.
            if w.age < 5 {
                let rate = dt * 60 * (1 - w.age / 5)
                var n = rate
                while n > 0 {
                    if n < 1 && Rand.float(in: 0..<1) > n { break }
                    n -= 1
                    let o = V3(Rand.float(in: -1...1), 0, Rand.float(in: -1...1)) * (MainGun.craterRadius * 0.6)
                    let tone = Rand.float(in: 0.18...0.32)
                    g.particles.add(Particle(pos: c + o, vel: V3(o.x * 0.1, Rand.float(in: 5...10), o.z * 0.1), life: Rand.float(in: 2...3.2), maxLife: 3.2,
                                             layer: layer, uv0: V2(0, 0), uvSize: 1, size: Rand.float(in: 1.6...3.0), gravity: -0.4,
                                             color: V3(tone, tone, tone), collide: false))
                }
            }
        }
        shockwaves.removeAll { $0.r >= MainGun.shockFelt && $0.age >= 5 && ($0.crater?.done ?? true) }
    }

    // The player at a commandeered Meridian frigate's helm: attack starts the Tidebreaker's charge when it is
    // loaded (it fires 2.6 s later along the bow, raised or lowered with the view). False when it can't (reloading,
    // already charging, not a Meridian frigate): attack then fires the point-defence guns.
    func playerMainGun(_ s: Ship, pitch: Float, game g: Game) -> Bool {
        guard s.role == "capfrigate", let st = capState[s.id], st.mainGunCD <= 0, st.gunCharge < 0 else { return false }
        st.gunPitch = pitch
        startMainGunCharge(s, st, g, byPlayer: true)
        return true
    }

    // The helm's readout (nil for ships without a Tidebreaker): a short state ("READY", "63%" while charging, "14 s"
    // while reloading) and the gauge's fill.
    func mainGunStatus(_ s: Ship) -> (state: String, fill: Float, ready: Bool)? {
        guard s.role == "capfrigate", let st = capState[s.id] else { return nil }
        if st.gunCharge >= 0 {
            let k = min(1, st.gunCharge / MainGun.chargeTime)
            return ("\(Int(k * 100))%", k, false)
        }
        if st.mainGunCD > 0 {
            let total = st.gunByPlayer ? MainGun.playerReload : MainGun.aiReload
            return (String(format: "%.0f s", st.mainGunCD.rounded(.up)), max(0, 1 - st.mainGunCD / total), false)
        }
        return ("READY", 1, true)
    }

    // Seconds until the Tidebreaker can fire again (nil: not a Meridian frigate).
    func mainGunCooldown(_ s: Ship) -> Float? {
        guard s.role == "capfrigate", let st = capState[s.id] else { return nil }
        return max(0, st.mainGunCD)
    }
}

// Screen shake (trauma 0...1, felt as its square): explosions near the player, the Tidebreaker's charge and blast.
// The Mac camera turns and moves with it; in VR only the eyes move, by at most 2.5 cm and not at all with Screen
// Effects off (VR comfort: no rotation is ever added to the headset's view).
extension Game {
    func addShake(_ amount: Float) { shake = min(1, max(shake, amount)) }

    // Smooth pseudo-random wobble in -1...1 (three incommensurate sines per axis).
    func shakeWobble(_ seed: Float, rate: Float) -> Float {
        let t = Float(clock.truncatingRemainder(dividingBy: 1000)) * rate
        return (sinf(t * 1.0 + seed) * 0.5 + sinf(t * 1.73 + seed * 2.1) * 0.3 + sinf(t * 2.61 + seed * 3.7) * 0.2)
    }

    // Mac / flat screen: (yaw, pitch, eye offset).
    var shakeView: (Float, Float, V3) {
        let s = shake * shake * (Settings.shared.screenEffects ? 1 : 0.3)
        guard s > 0.0005 else { return (0, 0, .zero) }
        return (shakeWobble(1, rate: 31) * 0.03 * s, shakeWobble(2, rate: 29) * 0.03 * s,
                V3(shakeWobble(3, rate: 23), shakeWobble(4, rate: 27), shakeWobble(5, rate: 25)) * 0.12 * s)
    }

    // VR: an eye offset only (metres = blocks).
    var shakeVR: V3 {
        let s = shake * shake
        guard s > 0.0005, Settings.shared.screenEffects else { return .zero }
        return V3(shakeWobble(3, rate: 17), shakeWobble(4, rate: 19), shakeWobble(5, rate: 15)) * 0.025 * s
    }
}

// Frame times around a Tidebreaker impact (store objective 1: no hitch from the blast). The Quest perf monitor and
// questcheck feed every frame; for 4 s after an impact they are kept, then one line is printed:
//   perf: main gun blast: N frames, median X ms, p99 Y ms, worst Z ms, over budget K
enum MainGunPerf {
    static let window = 4.0
    private(set) static var blastAt = -1.0
    private static var frames = [Float](repeating: 0, count: 1024)
    private static var n = 0
    private(set) static var lastReport = ""
    private(set) static var lastWorst: Float = 0
    private(set) static var lastP99: Float = 0
    // `clock`: the game clock (seconds of play) at the impact; frames are kept for `window` seconds of play after it.
    static func blast(clock: Double) { blastAt = clock; n = 0 }
    // One frame's time in ms at game clock `clock`; `budget` the frame budget in ms (13.9 at 72 Hz).
    static func record(frameMs: Double, budget: Double, clock: Double) {
        guard blastAt >= 0 else { return }
        if clock < blastAt { blastAt = -1; return }          // another world (its clock is behind): drop the window
        if clock - blastAt <= window {
            if n < frames.count { frames[n] = Float(frameMs); n += 1 }
            return
        }
        finish(budget: budget)
    }
    static func finish(budget: Double) {
        guard blastAt >= 0 else { return }
        blastAt = -1
        guard n > 0 else { return }
        let s = frames[0..<n].sorted()
        lastWorst = s[n - 1]
        lastP99 = s[min(n - 1, n * 99 / 100)]
        let over = s.filter { Double($0) > budget }.count
        lastReport = String(format: "perf: main gun blast: %d frames, median %.1f ms, p99 %.1f ms, worst %.1f ms, over %.1f ms budget %d",
                            n, s[n / 2], lastP99, lastWorst, budget, over)
        print(lastReport)
        n = 0
    }
}
