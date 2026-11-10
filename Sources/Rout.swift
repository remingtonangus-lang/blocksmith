import Foundation
import simd

// P511 (Nov 2 08:46:52-08:46:56, at a Capital base: "Let's make it so that if you murder... let's say 80% of any given
// facility, the rest of them flee"): a garrison that has lost four in five of its soldiers to him breaks. The soldiers
// left of it (the same side, posted within `reach` of where the fallen were posted) stop fighting, turn and run from
// him, and are gone once they are well clear of him and out of his sight. The count is per facility: the soldiers'
// posts (Mob.home) grouped by `cell`, and forgotten after `memory` seconds without a kill there.
enum Rout {
    static let share: Float = 0.8
    static let reach: Float = 96                 // blocks between posts of one facility's soldiers
    static let cell = 128
    static let least = 5                         // a garrison this size or more (a patrol of two doesn't break)
    static let memory: Double = 900
    static var kills: [Int64: (n: Int, at: Double)] = [:]
    static var broke = 0, fled = 0               // (checks)

    static func key(_ p: V3) -> Int64 {
        Int64(floorDiv(Int(floor(p.x)), cell)) << 32 | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: floorDiv(Int(floor(p.z)), cell))))
    }
    static func soldier(_ m: Mob) -> Bool { m.kind.steelhold && m.kind != .deckGun && Soldier.rank(m.kind) != nil && !m.hired }

    // Game.mobDied.
    static func died(_ g: Game, _ m: Mob) {
        guard m.killedByPlayer, soldier(m), m.factionValue != .none, m.posse == 0 else { return }
        let post = m.home ?? m.pos
        let k = key(post)
        var e = kills[k] ?? (n: 0, at: g.clock)
        if g.clock - e.at > memory { e.n = 0 }
        e.n += 1; e.at = g.clock
        kills[k] = e
        // (the kills of the facility: this cell and the cells round it within reach)
        var n = 0
        let c = (floorDiv(Int(floor(post.x)), cell), floorDiv(Int(floor(post.z)), cell))
        for dz in -1...1 { for dx in -1...1 {
            let kk = Int64(c.0 + dx) << 32 | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: c.1 + dz)))
            if let v = kills[kk], g.clock - v.at <= memory {
                let mid = V2(Float((c.0 + dx) * cell + cell / 2), Float((c.1 + dz) * cell + cell / 2))
                if simd_length(mid - V2(post.x, post.z)) < reach + Float(cell) * 0.72 { n += v.n }
            }
        } }
        let side = m.factionValue
        let rest = g.mobs.mobs.filter { o in
            o !== m && o.health > 0 && soldier(o) && o.factionValue == side && !o.routed && o.posse == 0 && o.deck == nil && o.mount == nil
                && simd_length(V2((o.home ?? o.pos).x - post.x, (o.home ?? o.pos).z - post.z)) < reach
        }
        guard !rest.isEmpty, n + rest.count >= least, Float(n) >= share * Float(n + rest.count) else { return }
        broke += 1
        for o in rest {
            o.routed = true
            o.persistent = false
            o.aggro = false
            _ = TroopVoice.say(g, o, .flee, gap: 1, chance: 0.5)
        }
    }

    // Mob.soldierAI for a routed soldier: away from him at a run, gone once clear (the speed to walk; nil: not routed).
    static let oldVanish = ProcessInfo.processInfo.environment["BS_OLDROUT"] == "1"
    static func step(_ m: Mob, _ dt: Float, _ g: Game) -> Float? {
        guard m.routed else { return nil }
        let d = V2(m.pos.x - g.player.pos.x, m.pos.z - g.player.pos.z)
        let far = simd_length(d)
        // Item 27 (Nov 10, "troops don't vanish"): past 72 blocks a routed soldier went at once, in plain sight across open
        // ground too. Now he is gone only out of sight: past 40 blocks with the ground between them, or behind him (outside
        // a 60 degree cone round his look). BS_OLDROUT=1: gone past 72 as before.
        let hidden: Bool = {
            if Rout.oldVanish { return far > 72 }
            let to = m.eye - g.player.eye
            let l = simd_length(to)
            return l > 0.01 && simd_dot(to / l, g.player.look) < 0.5
        }()
        if (far > 72 && (Rout.oldVanish || hidden)) || (far > 40 && (hidden || !g.world.canSee(m.eye, g.player.eye))) {
            if !m.fledClear { fled += 1 }
            m.fledClear = true                          // (gone at the next despawn pass, MobManager.shouldDespawn)
            return 0
        }
        m.aggro = false
        m.wanderGoal = nil
        let away = d / max(far, 0.01)
        m.face(m.pos + V3(away.x, 0, away.y) * 8)
        return m.spec.speed * 1.2
    }
}

// The rout's check (in the full suite; questcheck --rout): ten soldiers of a base posted round a spot, eight shot down by
// him: the two left break and run from him (further off a few seconds on), and fight no more; a patrol of three that
// loses two doesn't; another faction's men beside them hold.
enum RoutCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let mobs0 = g.mobs.mobs, pos0 = g.player.pos, kills0 = Rout.kills, surv0 = g.survival, alive0 = g.alive
        defer { g.mobs.mobs = mobs0; g.player.pos = pos0; Rout.kills = kills0; g.survival = surv0; g.alive = alive0 }
        g.mobs.mobs = []; Rout.kills = [:]; g.survival = true; g.alive = true
        let c = V3(Float(Int(floor(pos0.x)) / 512 * 512 + 3000), 0, Float(Int(floor(pos0.z)) / 512 * 512 + 3000))
        _ = g.world.loadSync(center: c, radius: 2)
        let y = Float(g.world.topY(Int(c.x), Int(c.z)) + 1)
        func soldier(_ k: Int, _ f: Faction, _ at: V3) -> Mob {
            let m = Mob([MobKind.soldierRecruit, .soldierTrooper, .soldierMarksman][k % 3], at: at)
            m.faction = f.rawValue; m.home = at; m.persistent = true
            g.mobs.mobs.append(m)
            return m
        }
        var base: [Mob] = []
        for k in 0..<10 { base.append(soldier(k, .greywall, c + V3(Float(k % 5) * 6, y - c.y, Float(k / 5) * 6))) }
        let other = soldier(0, .steelhold, c + V3(12, y - c.y, 30))
        g.player.pos = c + V3(-20, y - c.y, 0)
        for m in base.prefix(8) { m.killedByPlayer = true; m.health = 0; g.mobDied(m) }
        let left = Array(base.suffix(2))
        let broke = left.allSatisfy { $0.routed }
        let d0 = left.map { simd_length($0.pos - g.player.pos) }
        for _ in 0..<(3 * 20) { for m in left { m.update(0.05, game: g) } }
        let d1 = left.map { simd_length($0.pos - g.player.pos) }
        let ran = zip(d0, d1).allSatisfy { $1 > $0 + 2 }
        let calm = left.allSatisfy { !$0.aggro }
        check(broke && ran && calm && !other.routed,
              String(format: "rout: a base that lost 8 of 10 breaks: the two left run (%@ -> %@ blocks off) and fight no more (%@); another side's man beside them holds (%@)",
                     d0.map { String(format: "%.0f", $0) }.joined(separator: ","), d1.map { String(format: "%.0f", $0) }.joined(separator: ","),
                     calm ? "yes" : "no", other.routed ? "no" : "yes"))
        // Item 27: a routed soldier 80 blocks off in plain sight stays in the world (he was taken out past 72); with the
        // player turned away he goes.
        let r = left[0]
        r.fledClear = false
        _ = g.world.loadSync(center: r.pos, radius: 6)
        let yaw0 = g.player.yaw, pitch0 = g.player.pitch
        g.player.pos = r.pos + V3(-80, 30, 0)
        g.player.yaw = -Float.pi / 2
        let dv = r.eye - g.player.eye
        g.player.pitch = atan2f(dv.y, sqrtf(dv.x * dv.x + dv.z * dv.z))
        let inSight = g.world.canSee(r.eye, g.player.eye)
        _ = Rout.step(r, 0.05, g)
        let stayed = !r.fledClear
        g.player.yaw += Float.pi
        _ = Rout.step(r, 0.05, g)
        let wentBehind = r.fledClear
        g.player.yaw = yaw0; g.player.pitch = pitch0
        check(inSight && (Rout.oldVanish ? !stayed : stayed) && wentBehind,
              "rout: a routed soldier 80 blocks off in plain sight \(stayed ? "stays" : "is taken out") (in sight: \(inSight)); with him turned away \(wentBehind ? "he goes" : "he stays")")
        // Item 27: a wandering soldier (not a garrison's) 140 blocks off in plain sight is past the reference's 128-block
        // despawn, which took him while drawn (out to the view, 184 blocks at view 10); he stays while seen and goes when
        // the player looks away. A creeper 30 blocks ahead at dawn is seen (dawn read "seen" as within 24 blocks).
        do {
            let rd0 = g.world.renderDistance
            g.world.renderDistance = max(rd0, 10)
            defer { g.world.renderDistance = rd0 }
            let w = soldier(1, .greywall, r.pos + V3(140, 0, 0))
            w.persistent = false; w.home = nil
            _ = g.world.loadSync(center: r.pos + V3(70, 0, 0), radius: 7)
            w.pos.y = Float(g.world.topY(Int(floor(w.pos.x)), Int(floor(w.pos.z))) + 1)
            g.player.pos = w.pos + V3(-140, 30, 0)
            g.player.yaw = -Float.pi / 2
            let dw = w.eye - g.player.eye
            g.player.pitch = atan2f(dw.y, sqrtf(dw.x * dw.x + dw.z * dw.z))
            let d = simd_length(w.pos - g.player.pos)
            let seen = MobManager.inPlainSight(w, g)
            let spawnOK = g.spawnHidden(w.pos, min: 32)             // (item 71: a spawn on that spot would pop in)
            w.despawnLook = 0
            let tookSeen = g.mobs.shouldDespawn(w, d, 0.05, g)
            g.player.yaw += Float.pi
            w.despawnLook = 0
            let tookAway = g.mobs.shouldDespawn(w, d, 0.05, g)
            let cr = Mob(.creeper, at: g.player.pos + V3(-30, -30, 0))
            cr.pos.y = Float(g.world.topY(Int(floor(cr.pos.x)), Int(floor(cr.pos.z))) + 1)
            let dc = cr.eye - g.player.eye
            g.player.pitch = atan2f(dc.y, sqrtf(dc.x * dc.x + dc.z * dc.z))
            let creeperSeen = MobManager.inPlainSight(cr, g)
            g.player.yaw = yaw0; g.player.pitch = pitch0
            check(Game.oldSpawnSight ? spawnOK : !spawnOK,
                  "spawn: a spot \(Int(d)) blocks ahead in plain sight \(spawnOK ? "takes a spawn (it pops in)" : "takes no spawn")")
            check(seen && (MobManager.oldDespawn ? tookSeen : !tookSeen) && tookAway && creeperSeen,
                  String(format: "despawn: a wandering soldier %.0f blocks off in plain sight (%@) %@; turned away, %@; a monster 30 blocks ahead counts as seen (%@)",
                         d, seen ? "seen" : "not seen", tookSeen ? "is taken out" : "stays", tookAway ? "he goes" : "he stays", creeperSeen ? "yes" : "no"))
        }
        // A patrol of three losing two: no rout (under five).
        g.mobs.mobs = []; Rout.kills = [:]
        let p = c + V3(200, y - c.y, 200)
        let patrol = (0..<3).map { soldier($0, .greywall, p + V3(Float($0) * 3, 0, 0)) }
        for m in patrol.prefix(2) { m.killedByPlayer = true; m.health = 0; g.mobDied(m) }
        check(!patrol[2].routed, "rout: a patrol of three that loses two holds")
    }
}
