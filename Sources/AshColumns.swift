import Foundation
import simd

// P509 (Remington, Nov 1 16:26, of the Ash Vault: "add flying planes that are hostile, tank divisions, scary troop
// divisions singing song in distance (the troop divisions will have like 100 troops or so with vehicles and if they spot
// you they follow you until you die. make somewhat rare enough not to be annoying ... its too empty now"). The overseer:
// original songs only.
//   the roll      every six minutes spent on the vault floor (not once the war is won) is a roll: one in three, a
//                 formation comes. Two in three of those are a marching column, one in three an armoured division.
//   the column    eighty men in twenty ranks of four with an officer at their head, a half-track leading, a supply
//                 truck in the middle and a Cinder tank behind. It forms 300 blocks off and marches on a line that
//                 passes 30-60 blocks to one side of him and on past, at a soldier's walk. It sings as it marches: its
//                 own march (AshColumnSong below, written for it), a choir of men's voices over their boots, heard from
//                 far off and growing as it nears.
//   the division  five Cinder tanks and two half-tracks two abreast, at a vehicle's pace; its engines and tracks are
//                 heard coming.
//   bodies        a formation is a line and a roll of slots until a slot comes within 110 blocks of him: then its man
//                 or vehicle is put there (out of his sight) and marches by the soldiers' own feet to the slot ahead of
//                 it. A slot that passes on beyond 140 blocks takes its body back. The dead stay dead.
//   spotted       if any of them sees him (their own eyes: stealth counts) or is hit, the formation stops singing and
//                 hunts him: every one of them knows where he is from then on and comes for him; those beyond the
//                 active distance are brought along by the formation (out of his sight), so they keep coming wherever
//                 he goes in the vault. It ends when he dies, leaves the vault or kills the lot.
//   unseen        a formation that marches past without seeing him goes on its way and is gone.
// Not saved: a formation on the march when he saves is simply gone after the reload.
final class AshFormation {
    enum Kind: Int { case column, armour }
    struct Slot { var key: String; var rank: Float; var side: Float; var body: Mob?; var dead = false }
    let kind: Kind
    let origin: V2, dir: V2, perp: V2
    var s: Float                                  // the head's distance along the line from `origin`
    let speed: Float
    let length: Float
    var slots: [Slot] = []
    var hunting = false
    var huntTick: Float = 0
    var formTick: Float = 0
    @WeakLink var game: Game?
    init(kind: Kind, origin: V2, dir: V2, start: Float, length: Float, game: Game) {
        self.kind = kind; self.origin = origin; self.dir = dir; self.perp = V2(-dir.y, dir.x)
        self.s = start; self.length = length; self.game = game
        speed = kind == .column ? 1.6 : 3.2
    }
    var head: V2 { origin + dir * s }
    func slotXZ(_ k: Slot) -> V2 { head - dir * k.rank + perp * k.side }
    // The middle of the formation (where its song or its engines are heard from).
    var middle: V2 { head - dir * (kind == .column ? 24 : 18) }
    var alive: Int { slots.reduce(0) { $0 + ($1.dead ? 0 : 1) } }
    var bodies: [Mob] { slots.compactMap { $0.body } }
}

enum AshColumns {
    static let every: Double = 360
    static var chance: Float = 1.0 / 3
    static let near: Float = 110, far: Float = 140
    static var formation: AshFormation?
    static var onFloor: Double = 0                // seconds on the vault floor since the last roll
    static var rolls = 0, columns = 0, divisions = 0, hunts = 0     // (harness)

    // The column's roll: rank (blocks behind the head) and side (blocks off its line) of every man and vehicle.
    static func columnSlots() -> [AshFormation.Slot] {
        var out: [AshFormation.Slot] = [AshFormation.Slot(key: "ash_halftrack", rank: 0, side: 0),
                                        AshFormation.Slot(key: "soldier_officer", rank: 7, side: 0)]
        for r in 0..<20 {
            let rank = Float(10 + r * 2) + (r >= 10 ? 9 : 0)          // (a gap mid-column for the truck)
            for f in 0..<4 {
                let key = f == 0 && r % 5 == 0 ? "soldier_trooper" : (r % 3 == 1 && f == 3 ? "soldier_trooper" : "soldier_recruit")
                out.append(AshFormation.Slot(key: key, rank: rank, side: (Float(f) - 1.5) * 1.5))
            }
        }
        out.append(AshFormation.Slot(key: "ash_truck", rank: 34.5, side: 0))
        out.append(AshFormation.Slot(key: "ash_tank", rank: 66, side: 0))
        return out
    }
    static func armourSlots() -> [AshFormation.Slot] {
        var out: [AshFormation.Slot] = []
        for i in 0..<7 {
            let key = i == 0 || i == 6 ? "ash_halftrack" : "ash_tank"
            out.append(AshFormation.Slot(key: key, rank: Float(i / 2) * 12 + (i == 6 ? 12 : 0), side: i == 6 ? 0 : (i % 2 == 0 ? -4.5 : 4.5)))
        }
        return out
    }

    static func onTheFloor(_ g: Game) -> Bool {
        g.dim.dim == .deep && DeepGen.inVault(g.player.pos.y) && g.player.pos.y > Float(DeepGen.floorBase - 24)
    }

    // The vault floor's walkable top at (x, z): the first cell with ground under it and room for a body (wide: a vehicle).
    static func ground(_ g: Game, _ x: Int, _ z: Int, wide: Bool) -> Float? {
        let w = g.world
        guard w.isLoaded(x, z) else { return nil }
        let f = (w.gen as? DeepGen)?.floorY(x, z) ?? DeepGen.floorBase
        for y in [f + 1, f + 2, f, f + 3, f - 1, f + 4, f - 2, f + 5] where w.solidAt(x, y - 1, z) && w.isAir(x, y, z) && w.isAir(x, y + 1, z) {
            if wide && !(w.isAir(x + 1, y, z) && w.isAir(x - 1, y, z) && w.isAir(x, y, z + 1) && w.isAir(x, y, z - 1)) { continue }
            return Float(y)
        }
        return nil
    }

    // Starts a formation on a line passing `side` blocks from him, its head `start` blocks short of his point on it.
    @discardableResult
    static func begin(_ g: Game, _ kind: AshFormation.Kind, start: Float = 300, side: Float? = nil) -> AshFormation {
        let p = V2(g.player.pos.x, g.player.pos.z)
        let a = Rand.float(in: 0..<(2 * .pi))
        let dir = V2(cosf(a), sinf(a))
        let off = side ?? (Rand.float(in: 30...60) * (Rand.int(in: 0...1) == 0 ? 1 : -1))
        let pass = p + V2(-dir.y, dir.x) * off
        let f = AshFormation(kind: kind, origin: pass - dir * start, dir: dir, start: 0, length: start * 2, game: g)
        f.slots = kind == .column ? columnSlots() : armourSlots()
        formation = f
        if kind == .column { columns += 1 } else { divisions += 1 }
        return f
    }

    // Takes every body off (out of his sight or not: the formation is over).
    static func end(_ g: Game) {
        guard let f = formation else { return }
        let gone = Set(f.bodies.map { ObjectIdentifier($0) })
        g.mobs.mobs.removeAll { gone.contains(ObjectIdentifier($0)) && $0.health > 0 }
        formation = nil
        g.mobs.rebuildIndex()
    }
}

extension Game {
    // Every frame in the Deep (ashArmyTick), before its alive guard: the roll, the march, the hunt.
    func ashColumnsTick(_ dt: Float) {
        if let f = AshColumns.formation, f.game !== self { AshColumns.formation = nil }
        guard let f = AshColumns.formation else {
            guard alive, !ashVictory, survival, difficulty > 0, AshColumns.onTheFloor(self) else { return }
            if Int(clock) != Int(clock - Double(dt)) { AshColumns.onFloor += 1 }
            guard AshColumns.onFloor >= AshColumns.every else { return }
            AshColumns.onFloor = 0
            AshColumns.rolls += 1
            guard Rand.float(in: 0..<1) < AshColumns.chance else { return }
            AshColumns.begin(self, Rand.int(in: 0..<3) == 0 ? .armour : .column)
            return
        }
        // Over: he died, left the floor, the war is won, or the formation is dead.
        if !alive || !AshColumns.onTheFloor(self) || ashVictory || f.alive == 0 { AshColumns.end(self); return }
        let p = player.pos
        if !f.hunting {
            f.s += f.speed * dt
            // Marched past and gone on.
            if f.s > f.length && simd_length(f.middle - V2(p.x, p.z)) > AshColumns.far { AshColumns.end(self); return }
            // Seen him, or been hit: the hunt.
            if f.bodies.contains(where: { $0.aggro || $0.hurt > 0 || $0.health < $0.spec.health }) {
                f.hunting = true
                AshColumns.hunts += 1
                if let lead = f.bodies.min(by: { simd_length_squared($0.pos - p) < simd_length_squared($1.pos - p) }) {
                    sfx(.soldier(3, .attack), 1.0, at: lead.eye)
                }
            }
        }
        f.formTick -= dt
        guard f.formTick <= 0 else { return }
        f.formTick = 0.5
        // The dead (killed by him, by the Ashguard's foes, by anything) stay dead.
        let living = Set(mobs.mobs.lazy.filter { $0.health > 0 }.map { ObjectIdentifier($0) })
        for i in f.slots.indices { if let m = f.slots[i].body, !living.contains(ObjectIdentifier(m)) { f.slots[i].body = nil; f.slots[i].dead = true } }
        var changed = false, made = 0
        for i in f.slots.indices where !f.slots[i].dead {
            let k = f.slots[i]
            let xz = f.slotXZ(k)
            let d = simd_length(xz - V2(p.x, p.z))
            if let m = k.body {
                if f.hunting {
                    m.aggro = true
                    let b = m.soldierBrain
                    b.lastSeen = player.eye; b.seenAgo = min(b.seenAgo, 2)
                    b.order = nil
                    m.lockTime = max(m.lockTime, 20)
                    m.home = nil
                    // Beyond the active distance nobody walks: the formation brings them on, unseen, at a run.
                    if !world.activeHere(m.pos) {
                        var to = V2(p.x - m.pos.x, p.z - m.pos.z)
                        let l = simd_length(to)
                        if l > 1 { to /= l }
                        let step = to * min(l - 40, (m.kind.ash ? 4 : 3) * 0.5)
                        let nx = Int(floor(m.pos.x + step.x)), nz = Int(floor(m.pos.z + step.y))
                        if l > 40, let y = AshColumns.ground(self, nx, nz, wide: m.kind.ash) {
                            let np = V3(Float(nx) + 0.5, y, Float(nz) + 0.5)
                            if spawnHidden(np, min: 48, near: 56, clear: 128) { m.pos = np; m.yaw = -atan2f(to.x, -to.y) }
                        }
                    }
                    continue
                }
                if d > AshColumns.far && spawnHidden(m.pos, min: 60, near: 60, clear: 160) {
                    mobs.mobs.removeAll { $0 === m }
                    f.slots[i].body = nil
                    changed = true
                    continue
                }
                // On the march: to the slot a few steps ahead of where it stands now, at a walk, weapons carried.
                let ahead = xz + f.dir * (m.kind.ash ? 6 : 2.5)
                let b = m.soldierBrain
                b.order = V3(ahead.x, m.pos.y, ahead.y)
                b.orderRun = simd_length(V2(m.pos.x, m.pos.z) - xz) > 6
                b.ready = false
                if !world.activeHere(m.pos), let y = AshColumns.ground(self, Int(floor(xz.x)), Int(floor(xz.y)), wide: m.kind.ash) {
                    m.pos = V3(xz.x, y, xz.y)
                    m.yaw = -atan2f(f.dir.x, -f.dir.y)
                    if m.kind.ash { b.turret = m.yaw }
                }
            } else if (f.hunting ? made < 4 : d < AshColumns.near) && f.s >= k.rank {
                // Its turn to be there: put on the floor at its slot, out of his sight (hunting: the rest of the
                // formation comes on, a few at a time, from 90 blocks off on its side of him).
                let wide = k.key.hasPrefix("ash_")
                var q = xz
                if f.hunting && d > 90 { q = V2(p.x, p.z) + (xz - V2(p.x, p.z)) / d * Rand.float(in: 80...95) }
                // (P509: a vehicle's own cell on a boulder, a stump or a shell hole: the next clear cell within three
                // of its slot. The division came on with 4 of its 7 vehicles when its line crossed rough floor.)
                var spot: (Int, Int, Float)?
                let cx = Int(floor(q.x)), cz = Int(floor(q.y))
                search: for r in 0...(wide ? 3 : 1) { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {
                    if let y = AshColumns.ground(self, cx + dx, cz + dz, wide: wide) { spot = (cx + dx, cz + dz, y); break search }
                } } }
                guard let (sx, sz, y) = spot else { continue }
                let at = V3(Float(sx) + 0.5, y, Float(sz) + 0.5)
                guard spawnHidden(at, min: 40, near: 56, clear: 128), let m = Mob.structureMob(k.key + "@ash", at: at) else { continue }
                m.persistent = false                    // (never saved)
                m.waveUnit = true                       // (never despawned while it marches)
                m.yaw = -atan2f(f.dir.x, -f.dir.y)
                let b = m.soldierBrain
                b.turret = m.yaw
                b.extra = false
                m.home = nil
                if f.hunting { m.aggro = true; b.lastSeen = player.eye; b.seenAgo = 2; m.lockTime = 20 }
                mobs.mobs.append(m)
                f.slots[i].body = m
                changed = true
                made += 1
            }
        }
        if changed { mobs.rebuildIndex() }
    }

    // The column's song (and the division's engines): where it is heard from and how loud, for AudioAmbience.
    func ashColumnSound(_ eye: V3) -> (Snd, V3, Float)? {
        guard let f = AshColumns.formation, f.game === self, AshColumns.onTheFloor(self) else { return nil }
        let m = f.middle
        let at = V3(m.x, Float(DeepGen.floorBase) + 3, m.y)
        let d = simd_length(at - eye)
        let reach: Float = f.kind == .column ? 420 : 260
        guard d < reach else { return nil }
        if f.kind == .column {
            guard !f.hunting else { return nil }
            let k = 1 - d / reach
            return (.ashMarchSong, at, 1.25 * k * k + 0.05)
        }
        let k = 1 - d / reach
        return (.tankEngineLoop, at, 1.1 * k * k)
    }
}

// The column's march: an original tune for this game (D minor, 108 to the minute, 32 beats, looped), sung by a choir of
// men on open vowels over the tramp of their boots. Not any real song.
enum AshColumnSong {
    static let bpm: Float = 108
    // (semitones over D, beats)
    static let tune: [(Float, Float)] = [
        (0, 1), (0, 0.5), (3, 0.5), (7, 1), (7, 1), (5, 1), (3, 0.5), (2, 0.5), (0, 2),
        (3, 1), (5, 0.5), (7, 0.5), (8, 1), (7, 1), (5, 1.5), (3, 0.5), (2, 2),
        (7, 1), (10, 1), (8, 1), (7, 1), (5, 1), (7, 0.5), (5, 0.5), (3, 2),
        (2, 1), (3, 0.5), (5, 0.5), (3, 1), (2, 1), (-2, 1), (2, 1), (0, 2),
    ]
    static var beats: Float { tune.reduce(0) { $0 + $1.1 } }
    static var cycle: Float { beats * 60 / bpm }

    static func render(_ s: inout Synth, p: Float) -> [Float] {
        let fade: Float = 0.6
        let beat = 60 / bpm
        let n = s.frames(cycle + fade)
        var out = [Float](repeating: 0, count: n)
        let vowels: [[(Float, Float, Float)]] = [
            [(730, 6, 1.0), (1090, 8, 0.5), (2440, 10, 0.18)],          // ah
            [(570, 6, 1.0), (840, 8, 0.55), (2410, 10, 0.12)],          // oh
            [(530, 6, 0.9), (1840, 9, 0.4), (2480, 10, 0.15)],          // eh
        ]
        let d3: Float = 146.83 * p
        // The choir: seven voices on the tune, two an octave down; each a little off in pitch and time.
        let voices: [(Float, Float, Float)] = [(1, 0.000, 0.0), (1.006, 0.018, 0.0), (0.994, -0.012, 0.0), (1.003, 0.026, 0.0),
                                               (0.997, 0.008, 0.0), (0.5, 0.010, 1), (0.503, -0.016, 1)]
        for (vi, v) in voices.enumerated() {
            var t: Float = v.1 + 0.03
            var k = 0
            while t < cycle + fade {
                let (semi, len) = tune[k % tune.count]
                let f0 = d3 * powf(2, semi / 12) * v.0
                let dur = len * beat * 0.92
                let vow = vowels[(k + vi) % 3]
                let note = s.formant(dur, f0: f0, f1: f0 * 0.997, formants: vow, breath: 0.12, vib: 0.012, vibRate: 5.0 + Float(vi) * 0.13,
                                     attack: 0.06, release: 0.12, gain: v.2 > 0 ? 0.22 : 0.16)
                out = Synth.mix(out, note, at: s.frames(t))
                t += len * beat
                k += 1
            }
        }
        // Boots: every beat a heavy tread of many feet, a little smeared.
        var t: Float = 0
        while t < cycle + fade {
            for j in 0..<5 {
                let thud = s.burst(0.16, lp: 180 * p, hp: 30, attack: 0.004, decay: 0.05, gain: 0.5)
                out = Synth.mix(out, thud, at: s.frames(t + Float(j) * 0.011))
            }
            t += beat
        }
        if out.count > n { out = Array(out[0..<n]) }
        // Far off, across the vault: the high end gone and a long hall's echo.
        out = Synth.lowpass(out, 2600)
        out = Synth.reverb(out, size: 0.8, damp: 0.5, mix: 0.35, tail: 0)
        if out.count > n { out = Array(out[0..<n]) }
        return Synth.loopify(out, fade: fade)
    }
}

// The harness (DeepTests.run): the roll, a column forming out of sight and marching on singing, the hunt once it is hit,
// its end when he falls, an armoured division, and the song itself.
extension AshColumns {
    static func check(_ g: Game, _ check: (Bool, String) -> Void) {
        let home = g.player.pos, homeDim = g.dim.dim, wasSurvival = g.survival
        g.changeDimension(to: .deep, at: V3(0.5, 100, 600.5))
        let w = g.world
        let y = Float((w.gen as? DeepGen)?.floorY(0, 600) ?? DeepGen.floorBase) + 1
        let stand = V3(0.5, y, 600.5)
        _ = w.loadSync(center: stand, radius: 7)
        g.mobs.mobs.removeAll(); w.pendingMobs.removeAll()
        g.paused = false; g.menu = nil; g.alive = true; g.player.flying = false
        g.player.pos = stand
        func sim(_ secs: Float, each: () -> Void = {}) {
            var e: Float = 0
            while e < secs {
                g.health = 20
                g.tick(0.05)
                g.player.pos = stand; g.player.vel = .zero
                w.pendingMobs.removeAll()
                g.mobs.mobs.removeAll { $0.brain?.extra == true }       // (the vault's own squads and patrols)
                each()
                e += 0.05
            }
        }
        // The roll: six minutes on the floor, one in three.
        g.survival = true
        formation = nil
        let c0 = chance
        chance = 1
        onFloor = every - 1
        sim(1.2)
        let rolled = formation != nil
        chance = c0
        end(g)
        check(rolled, "P509 columns: six minutes on the vault floor rolls a formation (\(rolls) rolls)")

        // A column marching past 60 blocks off, its head a little short of him, while he isn't seen (creative).
        g.survival = false
        let f = begin(g, .column, start: 60, side: 60)
        f.s = 70
        g.player.yaw = atan2f(f.perp.x, f.perp.y); g.player.pitch = 0      // (looking away from it: look = -perp)
        sim(2)
        let made = f.bodies.count, vehicles = f.bodies.filter { $0.kind.ash }.count
        check(made >= 60 && vehicles >= 2, "P509 columns: a column of \(f.slots.count) forms out of his sight (\(made) on the floor, \(vehicles) vehicles)")
        func along() -> Float {
            let b = f.bodies
            guard !b.isEmpty else { return 0 }
            return b.reduce(0) { $0 + simd_dot(V2($1.pos.x, $1.pos.z) - f.origin, f.dir) } / Float(b.count)
        }
        let a0 = along()
        sim(20)
        let a1 = along()
        let song = g.ashColumnSound(g.player.eye)
        check(a1 - a0 > 12 && !f.hunting && song?.0 == .ashMarchSong && (song?.2 ?? 0) > 0.1,
              String(format: "P509 columns: it marches on (%.0f blocks in 20 s) singing, heard at %.2f", a1 - a0, song?.2 ?? 0))
        // Hit: the hunt. Every one of them comes for him.
        g.survival = true
        let d0 = f.bodies.reduce(Float(0)) { $0 + simd_length($1.pos - stand) } / Float(max(1, f.bodies.count))
        // (He stands through it: 84 rifles and a tank killed him inside the 12 s, his death calmed every one of them and
        // left the death screen up for the armour check below; suite 61, "0 of 84 after him", "0 vehicles".)
        g.applyEffect(.resistance, amp: 4, seconds: 30)
        var died = false
        if let m = f.bodies.first(where: { !$0.kind.ash }) { m.hit(from: stand, damage: 2) }
        sim(12) { if !g.alive || g.menu != nil { died = true; g.alive = true; g.menu = nil } }
        g.effects.clear()
        let aggro = f.bodies.filter { $0.aggro }.count
        let d1 = f.bodies.reduce(Float(0)) { $0 + simd_length($1.pos - stand) } / Float(max(1, f.bodies.count))
        check(f.hunting && aggro >= f.bodies.count - 2 && d1 < d0 - 3 && g.ashColumnSound(g.player.eye) == nil,
              "P509 columns: hit, it stops singing and hunts him (hunting \(f.hunting), died \(died), " + String(format: "%d of %d after him, %.0f -> %.0f blocks)", aggro, f.bodies.count, d0, d1))
        // He falls: it is over.
        g.alive = false
        g.ashColumnsTick(0.05)
        g.alive = true
        check(formation == nil && !g.mobs.mobs.contains { $0.waveUnit }, "P509 columns: when he dies the column is gone")

        // An armoured division: tanks and half-tracks, heard by their engines.
        g.survival = false
        g.menu = nil; g.alive = true
        let a = begin(g, .armour, start: 60, side: 60)
        a.s = 50
        g.player.yaw = atan2f(a.perp.x, a.perp.y); g.player.pitch = 0      // (it forms out of his sight)
        sim(2)
        let tanks = a.bodies.filter { $0.kind == .ashTank }.count
        let snd = g.ashColumnSound(g.player.eye)
        check(tanks >= 4 && snd?.0 == .tankEngineLoop, "P509 columns: an armoured division (\(a.bodies.count) vehicles, \(tanks) tanks) rumbles past")
        end(g)

        // The song: its own tune, a loop of the right length, sung (not silent), not clipping.
        var syn = Synth(seed: 7)
        let pcm = AshColumnSong.render(&syn, p: 1)
        let secs = Float(pcm.count) / Synth.sr
        let peak = pcm.reduce(Float(0)) { max($0, abs($1)) }
        let rms = (pcm.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(1, pcm.count))).squareRoot()
        check(abs(secs - AshColumnSong.cycle) < 0.2 && rms > 0.02 && peak < 1.5,
              String(format: "P509 columns: the march loops (%.1f s for a %.1f s tune), rms %.3f, peak %.2f", secs, AshColumnSong.cycle, rms, peak))

        g.mobs.mobs.removeAll(); g.survival = wasSurvival
        g.changeDimension(to: homeDim, at: home)
    }
}
