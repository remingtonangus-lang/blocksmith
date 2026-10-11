import Foundation
import simd

// L1 part 4 (docs/status/look-upgrade.md): the animation layers over the mob models (Sources/MobAnim.swift). Logic
// checks on the shared game: the head turns toward the player, babies' heads are bigger, an attack lunges, a hit rocks,
// rest breathes, a death tips the body over and ends in a puff, and the posed vertices stay finite.
enum MobAnimTest {
    // A model point after the mob's pose (head transform when `head`), in model pixels.
    static func posed(_ m: Mob, _ q: V3, head: Bool) -> V3 {
        let p = MobAnim.pose(m)
        var r = q
        if head, p.joint != nil { r = p.ha * r + p.hb }
        return p.a * r + p.b
    }

    static func run(game: Game, check: (Bool, String) -> Void) {
        let pl = game.player
        let saved = (pl.pos, pl.flying, game.mobs.mobs, game.mobs.corpses, game.alive, game.survival)
        defer {
            (pl.pos, pl.flying, game.mobs.mobs, game.mobs.corpses, game.alive, game.survival) = saved
            game.mobs.rebuildIndex()
        }
        game.alive = true
        pl.flying = true
        let at = game.findSpawn() + V3(0, 40, 0)
        _ = game.world.loadSync(center: at, radius: 2)
        // Head tracking: a cow facing -z with the player front-right, 2.5 blocks off: the head turns right (+x) and up.
        let cow = Mob(.cow, at: at)
        cow.yaw = 0
        pl.pos = at + V3(1.8, 0.6, -1.8)
        for _ in 0..<40 { cow.lookTimer = 0; cow.animTick(0.05, game) }           // looks every tick here (it glances at random)
        let nose = posed(cow, V3(0, 17, -15.5), head: true)
        check(cow.headYaw < -0.5 && nose.x > 3 && cow.headPitch > 0,
              String(format: "mob anim: a cow turns its head toward the player beside it (yaw %.2f, nose x %+.1f px, pitch %.2f)", cow.headYaw, nose.x, cow.headPitch))
        // Behind it: no neck can turn that far, the head stays straight.
        pl.pos = at + V3(0, 0.6, 3)
        for _ in 0..<40 { cow.lookTimer = 0; cow.animTick(0.05, game) }
        check(abs(cow.headYaw) < 0.05, String(format: "mob anim: the player behind it doesn't twist its neck round (yaw %.2f)", cow.headYaw))
        // A zombie watches its prey from 10 blocks, its helmet turning with the head.
        let z = Mob(.zombie, at: at)
        z.yaw = 0
        pl.pos = at + V3(-6, 0, -8)
        for _ in 0..<40 { z.animTick(0.05, game) }
        let parts = mobModelParts(z)
        let heads = parts.filter { MobAnim.headJoint(z)!.holds($0) }.count
        check(z.headYaw > 0.4 && heads >= 3 && heads < parts.count / 2,
              String(format: "mob anim: a zombie turns its head toward the player (yaw %.2f, %d of %d boxes are its head)", z.headYaw, heads, parts.count))
        // Babies: a bigger head on the small body.
        let calf = Mob(.cow, at: at); calf.baby = true; calf.scale = 0.5
        let calfNose = posed(calf, V3(0, 17, -15.5), head: true), adultNose = posed(Mob(.cow, at: at), V3(0, 17, -15.5), head: true)
        check(calfNose.z < adultNose.z - 1.5, String(format: "mob anim: a calf's head is drawn bigger (nose z %.1f vs %.1f px)", calfNose.z, adultNose.z))
        // An attack: the cooldown resets and the body lunges, its head forward and down.
        let top0 = posed(z, V3(0, 30, -4), head: false)
        z.attackCooldown = 1; z.animTick(0.12, game)
        let lunge = posed(z, V3(0, 30, -4), head: false)
        check(z.strikeT > 0 && lunge.z < top0.z - 1 && lunge.y < top0.y,
              String(format: "mob anim: an attack lunges the body forward (head z %.1f -> %.1f px)", top0.z, lunge.z))
        z.strikeT = 0
        // A hit rocks it back.
        z.hurt = 0.3
        let rocked = posed(z, V3(0, 30, -4), head: false)
        check(rocked.z > top0.z + 1, String(format: "mob anim: a hit rocks it back (head z %.1f -> %.1f px)", top0.z, rocked.z))
        z.hurt = 0
        // At rest it breathes: the top of the body rises and falls a little over a breath.
        var lo: Float = 99, hi: Float = -99
        for i in 0..<30 { z.animT = Float(i) * 0.1; let y = posed(z, V3(0, 32, 0), head: false).y; lo = min(lo, y); hi = max(hi, y) }
        check(hi - lo > 0.6 && hi - lo < 2, String(format: "mob anim: at rest it breathes (%.2f px)", hi - lo))
        // Death: killed, it leaves the live list for the corpses, tips onto its side, then goes in a puff.
        game.mobs.mobs = [z]; game.mobs.corpses = []
        game.survival = false
        z.health = 0
        game.mobs.update(0.05, game: game)
        let inCorpses = game.mobs.corpses.contains { $0 === z }, gone = !game.mobs.mobs.contains { $0 === z }
        for _ in 0..<9 { game.mobs.corpses.forEach { $0.deathT += 0.05 } }
        let tipped = posed(z, V3(0, 30, 0), head: false)
        check(inCorpses && gone && tipped.y < 14 && abs(tipped.x) > 18,
              String(format: "mob anim: a dead zombie tips over instead of vanishing (head at y %.1f, x %+.1f px after %.2f s)", tipped.y, tipped.x, z.deathT))
        // The corpse draws (and its vertices are finite).
        let cap = 4096
        let buf = UnsafeMutablePointer<MobVert>.allocate(capacity: cap)
        defer { buf.deallocate() }
        let n = writeMobVertices([], eye: z.pos + V3(0, 1.6, 3), daylight: 1, world: game.world, into: buf, capacity: cap, corpses: game.mobs.corpses)
        var finite = true
        for i in 0..<n where !(buf[i].pos.x.isFinite && buf[i].pos.y.isFinite && buf[i].pos.z.isFinite) { finite = false }
        check(n > 36 && finite, "mob anim: the falling body is drawn (\(n) vertices, all finite)")
        let puffs0 = game.particles.list.count
        for _ in 0..<12 { game.mobs.update(0.05, game: game) }
        check(game.mobs.corpses.isEmpty && game.particles.list.count > puffs0,
              "mob anim: after its fall it goes in a puff (\(game.particles.list.count - puffs0) puff particles, \(game.mobs.corpses.count) corpses left)")
        // Machines and armour stands never fall or breathe.
        let stand = Mob(.armorStand, at: at)
        check(MobAnim.pose(stand).still && !MobAnim.falls(Mob(.boat, at: at)), "mob anim: armour stands and boats keep still")
    }
}
