import Foundation
import simd

// Nov 12 trailer cut (the frigate's main gun striking beside a village, frames 31.8 s and 32.6 s): the slug's white wake
// read as a dashed line that moved from frame to frame, a field of hard grey-brown puffs flickered under the fireball,
// and small grey pieces hung still in the sky. `questcheck --strikelook`: one Tidebreaker slug into the ground beside the
// player, measured: the widest gap along its wake, the big puffs drawn solid that pop in and out (no fade), the
// fireball's size at once against its largest (Nov 12 08:46 cut: "an explosion renders too slowly"), and a
// debris piece thrown over ground that is not loaded (it read as rock all the way up: the piece touched it, slept, hung).
enum StrikeLook {
    static let wake = V3(0.6, 0.85, 1)

    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let home = g.player.pos
        _ = w.loadSync(center: home, radius: 6)
        defer { w.ships.shells.removeAll(); w.ships.shockwaves.removeAll(); w.ships.pendingCraters.removeAll(); w.ships.pendingAlong.removeAll(); g.particles.list.removeAll(); g.debris.clear() }
        let x = Int(floor(home.x)) + 40, z = Int(floor(home.z))
        let aim = V3(Float(x) + 0.5, Float(w.topY(x, z)) + 1, Float(z) + 0.5)
        g.particles.list.removeAll()
        let from = aim + V3(-260, 70, 0)
        let dir = simd_normalize(aim - from)
        let sh = Shell(pos: from, vel: dir * MainGun.slugSpeed, owner: -7, power: 12)
        sh.gravity = 0; sh.kind = 3; sh.life = 3.5
        w.ships.shells = [sh]
        let dt: Float = 1.0 / 72
        var gap: Float = -1, motes = 0
        var popped = 0, hardBorn = 0, frames = 0
        let impacts0 = MainGun.impacts
        var after = 0
        var ball0: Float = 0, ballPeak: Float = 0
        while frames < 72 * 8 {
            frames += 1
            let n0 = g.particles.list.count
            let flying = !w.ships.shells.isEmpty
            if flying && frames > 1 {
                // The wake as it stands this frame, along the slug's line.
                let ts = g.particles.list.filter { $0.glow && $0.color == wake }.map { simd_dot($0.pos - from, dir) }.sorted()
                motes = ts.count
                if ts.count > 1 { for i in 1..<ts.count { gap = max(gap, ts[i] - ts[i - 1]) } }
            }
            w.ships.updateShells(dt, game: g)
            if MainGun.impacts > impacts0 { after += 1 }
            // The fireball's size (the 90th-percentile reach of its glowing puffs from the impact) each frame for 2 s.
            if after > 0 && after <= 72 * 2 {
                var ds = g.particles.list.filter { $0.glow && $0.size >= 2 }.map { simd_length($0.pos - MainGun.lastImpact) }
                if ds.count > 10 {
                    ds.sort()
                    let r90 = ds[ds.count * 9 / 10]
                    if after == 7 { ball0 = r90 }
                    ballPeak = max(ballPeak, r90)
                }
            }
            if after > 0 && after < 72 * 5 {
                for p in g.particles.list.dropFirst(n0) where hard(p) { hardBorn += 1 }
                for p in g.particles.list where hard(p) && p.life <= dt { popped += 1 }
            }
            g.particles.update(dt, w)
            g.debris.tick(dt, world: w)
        }
        let secs = Float(min(after, 72 * 5)) / 72
        print("strikelook: slug landed \(MainGun.impacts > impacts0) at \(Int(aim.x)) \(Int(aim.y)) \(Int(aim.z)); wake \(motes) motes, widest gap \(String(format: "%.1f", gap)) blocks; big solid puffs born \(hardBorn), popped out \(popped) over \(String(format: "%.1f", secs)) s")
        check(MainGun.impacts > impacts0, "strikelook: the slug lands")
        check(gap >= 0 && gap <= 2, "strikelook: the slug's wake is one line, no gap over 2 blocks (widest \(String(format: "%.1f", gap)), \(motes) motes)")
        print(String(format: "strikelook: the fireball reaches %.1f blocks 0.1 s after the impact, %.1f at its largest", ball0, ballPeak))
        check(ballPeak > 0 && ball0 >= 0.7 * ballPeak,
              String(format: "strikelook: the fireball is near its full size at once (%.1f of %.1f blocks 0.1 s in)", ball0, ballPeak))
        check(popped <= 20, "strikelook: under the fireball no big solid puffs pop out without fading (\(popped) popped, \(hardBorn) born)")

        // A piece thrown over ground not loaded yet: it falls (it hung where it first touched the unloaded column).
        g.debris.clear()
        let far = home + V3(2400, 0, 2400)
        let fx = Int(floor(far.x)), fz = Int(floor(far.z))
        let loaded = w.chunks[ChunkKey(x: floorDiv(fx, CS), z: floorDiv(fz, CS))] != nil
        let h = Float(w.gen.column(fx, fz).height)
        let start = V3(far.x, h + 30, far.z)
        g.debris.bits(STONE, at: start, size: SIMD3<Float>(0.6, 0.6, 0.6), direction: V3(0, 1, 0), count: 3, speed: 0.5, seed: 77)
        var y0: Float = 0, y1: Float = 0, n = 0
        g.debris.bodies.forEachLive { _, p, _, _, _ in y0 += p.y; n += 1 }
        for _ in 0..<(72 * 2) { g.debris.tick(dt, world: w) }
        g.debris.bodies.forEachLive { _, p, _, _, _ in y1 += p.y }
        let fell = n > 0 ? (y0 - y1) / Float(n) : 0
        print("strikelook: \(n) pieces thrown 30 over ground not loaded (loaded: \(loaded)) fell \(String(format: "%.1f", fell)) blocks in 2 s")
        check(!loaded && n > 0 && fell > 12, "strikelook: debris over ground not loaded yet falls, not hangs (\(String(format: "%.1f", fell)) blocks in 2 s)")
    }

    // A puff a block or more across drawn in the solid pass: it shows and goes in a single frame.
    static func hard(_ p: Particle) -> Bool {
        p.size >= 0.5 && p.uvSize >= 1 && !ParticleManager.isSmoke(p) && !ParticleManager.isGlowPuff(p)
            && (p.layer == ParticleManager.smokeLayer || p.layer == ParticleManager.puffLayer)
    }
}
