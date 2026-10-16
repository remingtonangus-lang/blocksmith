import Foundation
import simd

// Hell's own mobs (backlog B6, docs/status/hell-mobs.md). Every rule here is meant to be read from the model and the
// sound in a headset and answered with the player's own blade.
//   The Brand Order  knights in dark burgundy plate: Squire, Knight, Champion and the Brand Commander (mini-boss).
//                    The shield takes any frontal hit (blades and arrows clang off, bullets lose most of theirs) and
//                    wears down the guard until it breaks; each swing is wound up high first, and a hit in that moment
//                    parries (stagger, shield down, extra damage); after a swing the shield stays down a moment; from
//                    mid range they charge in a straight line: sidestep and they skid past, dazed.
//   Searwing         a burning flier that circles high, glows and screeches, dives at your head, then climbs slowly.
//   Scorchling       knee-high fire imps in packs: fast, weak, leaping nips, a spark burst when they die.
//   Slagthrower      a hunched brute that keeps its distance and lobs glowing slag in a visible arc.
// They spawn in the Emberdeep and the Deep's hell band (MobManager.hellOwnSpawn), a Commander's muster now and then
// (Game.hellTick), and an order detachment holds every new Brimstone Keep's gate.

final class HellState {
    enum S { case idle, windup, recover, stagger, aim, charge, dazed, dive, climb }
    enum FX { case none, clang, guardBreak, parry }
    var s: S = .idle
    var t: Float = 0
    var cool: Float = Rand.float(in: 1...3)       // until the next charge, dive or throw
    var guardLeft = 0
    var chargeYaw: Float = 0
    var chargeHit = false
    var swings = 0
    var side: Float = 1
    var sideT: Float = 0
    var hover: Float = 8                          // a Searwing's circling height over the player (headroom probed)
    var called = false                            // the Commander's horn
    var raged = false
    var fx: FX = .none
    var feint = false                             // P185: this wind-up is a feint (it breaks off and comes again)
}

// What's live in the world for these mobs and the gate (Game.hell).
struct HellWorld {
    struct Slag { var pos: V3; var vel: V3; var age: Float = 0 }
    var slag: [Slag] = []
    var charges: [(at: IVec3, t: Float)] = []     // Ember Charges burning on Wardstone (HellGate.swift)
    var time: Float = 0                            // seconds spent in hell (the muster waits for a few minutes of it)
    var musterCool: Float = 0
    var hintAt: Double = -1000
}

// Harness counters (HellMobsTests).
enum HellStats {
    static var blocked = 0, guardBreaks = 0, parries = 0, dodged = 0, wallStuns = 0, chargeHits = 0, ripostes = 0, feints = 0
    static var dives = 0, diveHits = 0, lobs = 0, slagHits = 0, musters = 0, calls = 0
}

extension MobKind {
    var hellOwn: Bool {
        switch self {
        case .brandSquire, .brandKnight, .brandChampion, .brandCommander, .searwing, .scorchling, .slagthrower: return true
        default: return false
        }
    }
    var brandOrder: Bool { orderRank >= 0 }
    var orderRank: Int {
        switch self {
        case .brandSquire, .caveSpider: return 0          // P246: the Gravesworn fight as the order's squire and knight
        case .vindicator: return 0                        // P272: the Brigand duels as a squire (guard, wind-up, stagger)
        case .brandKnight, .spider: return 1
        case .brandChampion: return 2
        case .brandCommander: return 3
        default: return -1
        }
    }
    // Index 0...6 among hell's own (caps and counts as plain arrays).
    var hellIndex: Int {
        switch self {
        case .brandSquire: return 0
        case .brandKnight: return 1
        case .brandChampion: return 2
        case .brandCommander: return 3
        case .searwing: return 4
        case .scorchling: return 5
        default: return 6
        }
    }

    var hellSpec: Spec {
        switch self {
        case .brandSquire:
            return Spec(name: "Brand Squire", halfW: 0.3, height: 1.95, health: 40, speed: 3.0, behavior: .monster, attack: 5,
                        drops: [("gold_nugget", 1, 4), ("iron_nugget", 1, 3)], xp: 8, call: .mob(self, .ambient), fireImmune: true)
        case .brandKnight:
            return Spec(name: "Brand Knight", halfW: 0.32, height: 1.98, health: 64, speed: 2.8, behavior: .monster, attack: 9,
                        drops: [("gold_ingot", 0, 2), ("iron_ingot", 1, 2)], xp: 16, call: .mob(self, .ambient), fireImmune: true)
        case .brandChampion:
            return Spec(name: "Brand Champion", halfW: 0.34, height: 2.05, health: 90, speed: 2.9, behavior: .monster, attack: 11,
                        drops: [("gold_ingot", 1, 3), ("diamond", 0, 1)], xp: 30, call: .mob(self, .ambient), fireImmune: true)
        case .brandCommander:
            return Spec(name: "Brand Commander", halfW: 0.38, height: 2.05, health: 420, speed: 3.0, behavior: .monster, attack: 14,
                        drops: [("brand_greatsword", 1, 1), ("diamond", 2, 4), ("gold_ingot", 4, 8), ("netherite_scrap", 1, 2)], xp: 200,
                        call: .mob(self, .ambient), fireImmune: true)
        case .searwing:
            return Spec(name: "Searwing", halfW: 0.45, height: 0.8, health: 16, speed: 7, behavior: .monster, attack: 5,
                        drops: [("blaze_powder", 0, 1), ("leather", 0, 2)], xp: 10, call: .mob(self, .ambient), fireImmune: true, flying: true)
        case .scorchling:
            return Spec(name: "Scorchling", halfW: 0.25, height: 0.6, health: 6, speed: 5, behavior: .monster, attack: 2,
                        drops: [("magma_cream", 0, 1)], xp: 3, call: .mob(self, .ambient), fireImmune: true)
        default:
            return Spec(name: "Slagthrower", halfW: 0.55, height: 2.2, health: 34, speed: 1.8, behavior: .monster, attack: 6,
                        drops: [("magma_block", 0, 2), ("gold_nugget", 1, 4)], xp: 15, call: .mob(self, .ambient), fireImmune: true)
        }
    }
}

extension Mob {
    static var playerMelee = false            // set by Game.interact around a melee hit (a parry needs a blade)
    static var playerMeleePower: Float = 1    // that hit's charge (x the swing's power): a tap neither parries nor wears a guard
    static weak var meleeGame: Game?          // the game round that melee hit (a vest it breaks drops and cracks visibly)

    var hellState: HellState {
        if let h = hell { return h }
        let h = HellState()
        h.guardLeft = orderGuardMax
        // A Commander saved past half health already called his retinue.
        if kind == .brandCommander && health * 2 < spec.health { h.called = true; h.raged = true }
        hell = h
        return h
    }

    var orderGuardMax: Int {
        if kind == .brandCommander { return hell?.raged == true ? 16 : 12 }
        return HellMobs.guardMax[max(0, min(3, kind.orderRank))]
    }

    func hellSetup() {
        if kind == .brandCommander { scale = 1.3; persistent = true }
    }

    // A hit on a knight (from Mob.hit, before armour): true when the shield took it all. A wind-up hit by a blade
    // parries; staggered or dazed, it takes half again; from the side or behind, the hit lands as usual.
    func orderGuard(from src: V3, damage: inout Int, knockback: inout Float) -> Bool {
        let h = hellState
        let melee = Mob.playerMelee
        let firm = melee && Mob.playerMeleePower >= 0.6         // a charged blow, not a tap
        switch h.s {
        case .windup where firm && h.feint:
            // P185: swinging into a feint meets the knight's blade, and he answers at once.
            h.feint = false; h.s = .windup; h.t = 0.3; h.fx = .clang
            HellStats.blocked += 1
            return true
        case .windup where firm:
            h.s = .stagger; h.t = 1.7; h.fx = .parry
            damage = damage * 3 / 2
            HellStats.parries += 1
            return false
        case .stagger, .dazed:
            damage = damage * 3 / 2
            return false
        case .recover, .windup:
            return false
        default: break
        }
        let d = V2(src.x - pos.x, src.z - pos.z)
        let l = simd_length(d)
        let front: Float = l > 0.01 ? simd_dot(d / l, V2(forward.x, forward.z)) : -1    // a blast at its feet: no side to block
        guard front > 0.3 else { return false }
        if melee && !firm { h.fx = .clang; HellStats.blocked += 1; return true }           // a tap clangs off, no wear
        if melee {
            h.guardLeft -= 1
            HellStats.blocked += 1
            if h.guardLeft <= 0 { h.s = .stagger; h.t = 1.4; h.fx = .guardBreak; HellStats.guardBreaks += 1 } else {
                h.fx = .clang
                // P185: a blow taken on the guard can be answered with a quick riposte (more often the higher the rank).
                if h.s == .idle && Rand.float(in: 0..<1) < HellMobs.riposte[max(0, min(3, kind.orderRank))] {
                    h.s = .windup; h.t = 0.32; h.feint = false; HellStats.ripostes += 1
                }
            }
            return true
        }
        // Arrows and thrown things clang off; bullets and blasts lose most of theirs.
        let cut = Int(Float(damage) * 0.3)
        h.fx = .clang
        if cut <= 1 { HellStats.blocked += 1; return true }
        damage = cut
        knockback *= 0.3
        return false
    }

    func hellAI(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float {
        switch kind {
        case .searwing: return searwingAI(dt, g, dist: dist, canTarget: canTarget)
        case .scorchling: return scorchlingAI(dt, g, dist: dist, canTarget: canTarget)
        case .slagthrower: return slagthrowerAI(dt, g, dist: dist, canTarget: canTarget)
        default: return orderAI(dt, g, dist: dist, canTarget: canTarget)
        }
    }

    // The order's feedback for what orderGuard decided (it has no game): the clang, the guard breaking, the parry.
    private func orderFX(_ g: Game) {
        let h = hellState
        guard h.fx != .none else { return }
        let at = pos + forward * 0.5 + V3(0, height * 0.6, 0)
        switch h.fx {
        case .clang: g.sfx(.shieldBlock, 1, at: at); g.particles.crit(at: at)
        case .guardBreak: g.sfx(.shieldBreak, 1.1, at: at); g.particles.crit(at: at); g.particles.crit(at: at)
        case .parry:
            g.sfx(.attackCrit, 1.3, at: at); g.sfx(.shieldBreak, 0.6, at: at)
            g.particles.crit(at: at + V3(0, 0.4, 0)); g.particles.crit(at: at)
            g.achieve("brand_parry")
        case .none: break
        }
        h.fx = .none
    }

    private func orderAI(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float {
        let h = hellState
        let rank = kind.orderRank
        h.t -= dt; h.cool -= dt
        orderFX(g)
        if kind == .brandCommander { commanderTick(g) }
        if h.s == .stagger || h.s == .dazed {
            if Rand.float(in: 0..<1) < dt * 5 { g.particles.smoke(at: pos + V3(0, height + 0.1, 0), dark: false) }
            if h.t <= 0 { h.s = .idle; h.guardLeft = orderGuardMax }
            return 0
        }
        guard canTarget else {
            if h.s != .idle { h.s = .idle }
            wander()
            return moving ? spec.speed * 0.5 : 0
        }
        let player = g.player.pos
        let gap = g.meleeGap(self)
        let reach: Float = halfW + 1.2 + (rank >= 2 ? 0.3 : 0)
        let windup: Float = h.raged ? 0.42 : HellMobs.windups[min(3, rank)]
        switch h.s {
        case .windup:
            guardTurn(player, dt)
            // P185: a feint breaks off halfway and the real cut comes from the other side.
            if h.feint && h.t < windup * 0.45 {
                h.feint = false; h.side = -h.side; h.t = windup * 0.6; HellStats.feints += 1
                g.sfx(.attackSweep, 0.5, at: pos)
                return 0
            }
            if h.t <= 0 {
                g.sfx(.attackSweep, 1, at: pos)
                if gap < reach + 0.4 {
                    g.hurtPlayer(spec.attack, from: pos, cause: "was cut down by a \(spec.name)", knockback: 1.2, attacker: self)
                }
                h.swings += 1
                // P185 (Oct 13: "sword-duel knights, and much harder"): a combo of up to rank + 1 cuts, each wound up for
                // a different time, so the rhythm can't be learnt; the recovery after it is the opening.
                if h.swings <= rank && gap < reach + 1 { h.s = .windup; h.t = windup * Rand.float(in: 0.5...0.9); h.feint = false }
                else { h.s = .recover; h.t = rank >= 2 ? 0.6 : 0.85; h.swings = 0 }
            }
            return 0
        case .recover:
            guardTurn(player, dt)
            if h.t <= 0 { h.s = .idle }
            return gap < reach ? -spec.speed * 0.4 : 0
        case .aim:
            face(player)
            if Rand.float(in: 0..<1) < dt * 12 { g.particles.smoke(at: pos + V3(Rand.float(in: -0.3...0.3), 0.1, Rand.float(in: -0.3...0.3))) }
            if h.t <= 0 {
                h.s = .charge; h.t = 1.3; h.chargeYaw = yaw; h.chargeHit = false
                g.sfx(.mob(kind, .ambient), 1.6, at: pos)                 // the war cry
                g.sfx(.attackKnockback, 0.8, at: pos)
            }
            return 0
        case .charge:
            yaw = h.chargeYaw
            let toP = V2(player.x - pos.x, player.z - pos.z)
            let ahead = simd_dot(toP, V2(forward.x, forward.z))
            if gap < 0.6 && !h.chargeHit {
                h.chargeHit = true
                HellStats.chargeHits += 1
                let dmg = HellMobs.chargeDamage[min(3, rank)]
                g.hurtPlayer(dmg, from: pos - forward, cause: "was run through by a \(spec.name)", knockback: 2.4, attacker: self)
                h.s = .recover; h.t = 1.0
                return 0
            }
            let flat = simd_length(V2(vel.x, vel.z))
            if h.t < 1.05 && flat < 2 {
                // Into a wall: it reels the longest.
                h.s = .dazed; h.t = 2.6; HellStats.wallStuns += 1
                g.sfx(.anvilLand, 0.7, at: pos)
                return 0
            }
            if h.t <= 0 || (ahead < -1 && dist > 1.5) {
                h.s = .dazed; h.t = 1.5; HellStats.dodged += 1
                return 0
            }
            if Rand.float(in: 0..<1) < dt * 20 { g.particles.smoke(at: pos + V3(0, 0.1, 0)) }
            return HellMobs.chargeSpeed[min(3, rank)]
        default:
            // Close in, the knight turns at a walking pace (circle it to get round the shield); further off it
            // paths straight at you.
            if gap < reach + 1 { guardTurn(player, dt) } else { face(player) }
            h.sideT -= dt
            if h.sideT <= 0 { h.sideT = Rand.float(in: 1.5...3); h.side = Rand.float(in: 0..<1) < 0.5 ? -1 : 1 }
            if rank >= 1 && h.cool <= 0 && dist > 5.5 && dist < 16 && onGround && abs(player.y - pos.y) < 2.5
                && g.world.canSee(eye, g.player.eye) {
                h.s = .aim
                h.t = rank == 3 ? 0.7 : (rank == 2 ? 0.75 : 0.85)
                h.cool = h.raged ? 4.5 : Rand.float(in: 6...9)
                g.sfx(.mob(kind, .ambient), 1.3, at: pos)
                return 0
            }
            if gap < reach && attackCooldown <= 0 {
                h.s = .windup; h.t = windup * Rand.float(in: 0.85...1.2)
                h.feint = Rand.float(in: 0..<1) < HellMobs.feint[min(3, rank)]
                attackCooldown = 1.4
                g.sfx(.spyglass, 0.7, at: pos + V3(0, height, 0))      // the rising whine of the wind-up
                return 0
            }
            if gap < reach { strafe = h.side * spec.speed * 0.35; return 0 }
            return spec.speed
        }
    }

    // Turns toward `p` no faster than the rank's guard turn (HellMobs.turnRate): rad/s.
    private func guardTurn(_ p: V3, _ dt: Float) {
        let want = atan2f(-(p.x - pos.x), -(p.z - pos.z))
        var d = want - yaw
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        let r = HellMobs.turnRate[max(0, min(3, kind.orderRank))] * dt
        yaw += max(-r, min(r, d))
    }

    // Half health: the horn, a knight and two squires, and he goes berserk.
    private func commanderTick(_ g: Game) {
        let h = hellState
        guard !h.called, health * 2 < spec.health else { return }
        h.called = true; h.raged = true
        h.guardLeft = orderGuardMax
        g.sfx(.goatHorn, 1.6, at: pos)
        for (i, k) in [MobKind.brandKnight, .brandSquire, .brandSquire].enumerated() {
            let a = Float(i) * 2.1 + yaw
            let p = MobManager.groundSpot(g.world, near: pos + V3(cosf(a) * 3.5, 0, sinf(a) * 3.5)) ?? pos
            let m = Mob(k, at: p)
            m.aggro = true; m.lockTime = 20; m.power = power
            g.mobs.mobs.append(m)
        }
        HellStats.calls += 1
        g.onToast?("The Brand Commander sounds his horn: the order rallies to him")
    }

    private func searwingAI(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float {
        let h = hellState
        // P302 (b): on the easy levels a Searwing winds up longer, dives slower and climbs away slowly for longer
        // (the moment to hit it), and rests longer between dives; on the hard ones it is quicker at all of it.
        let pace: Float = Difficulty.row.pace, lvlSpeed: Float = Difficulty.row.speed
        h.t -= dt; h.cool -= dt
        circleAngle += dt * 0.9
        if Rand.float(in: 0..<1) < dt * 6 { g.particles.flame(at: pos + V3(Rand.float(in: -0.4...0.4), 0.3, Rand.float(in: -0.4...0.4))) }
        guard canTarget && dist < 48 else {
            h.s = .idle
            let drift = V3(cosf(circleAngle), sinf(circleAngle * 0.7) * 0.3, sinf(circleAngle)) * 3
            vel += (drift - vel) * min(1, dt)
            face(pos + vel)
            return 0
        }
        let head = g.vrHead ?? g.player.eye
        switch h.s {
        case .windup:
            vel *= expf(-4 * dt)
            face(head)
            if h.t <= 0 { h.s = .dive; h.t = 2; HellStats.dives += 1; g.sfx(.mob(kind, .hurt), 1.4, at: pos) }
        case .dive:
            let d = head - pos
            let l = max(0.01, simd_length(d))
            vel += (d * (15 * lvlSpeed / l) - vel) * min(1, dt * 4)
            face(pos + vel)
            if l < 1.1 {
                HellStats.diveHits += 1
                g.hurtPlayer(spec.attack, from: pos, cause: "was struck down by a Searwing", attacker: self)
                if !g.effects.has(.fireResistance) { g.onFire = max(g.onFire, 3) }
                h.s = .climb; h.t = 2.4 / pace
            } else if h.t <= 0 || g.world.collides(pos + vel * 0.15 - V3(halfW, 0, halfW), pos + vel * 0.15 + V3(halfW, height, halfW)) {
                h.s = .climb; h.t = 2.4 / pace
            }
        case .climb:
            // Climbing away slowly: the moment to hit it.
            let up = V3(forward.x * 2, 2.5, forward.z * 2) * lvlSpeed
            vel += (up - vel) * min(1, dt * 3)
            if h.t <= 0 { h.s = .idle; h.cool = Rand.float(in: 3.5...6) / pace }
        default:
            // About once a second: how much open air is over the player (low halls: circle under the roof).
            h.sideT -= dt
            if h.sideT <= 0 {
                h.sideT = 1
                let x = Int(floor(g.player.pos.x)), z = Int(floor(g.player.pos.z)), y0 = Int(floor(g.player.pos.y))
                var open = 2
                while open < 11 && !Blocks.collide[Int(g.world.block(x, y0 + open, z))] { open += 1 }
                h.hover = max(2.5, Float(open) - 2.5)
            }
            let r: Float = 9
            let c = g.player.pos + V3(cosf(circleAngle) * r, h.hover + sinf(circleAngle * 2) * 1.2, sinf(circleAngle) * r)
            let d = c - pos
            let l = max(0.01, simd_length(d))
            vel += (d * (spec.speed * lvlSpeed / l) - vel) * min(1, dt * 2)
            face(pos + vel)
            if h.cool <= 0 && dist < 28 && g.world.canSee(eye, head) {
                h.s = .windup; h.t = 0.7 / pace
                g.sfx(.mob(kind, .ambient), 1.3, at: pos)
            }
        }
        return 0
    }

    private func scorchlingAI(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float {
        if Rand.float(in: 0..<1) < dt * 3 { g.particles.flame(at: pos + V3(0, height, 0)) }
        guard canTarget else { wander(); return moving ? spec.speed * 0.4 : 0 }
        face(g.player.pos)
        if onGround && dist > 1.4 && dist < 3.5 && Rand.float(in: 0..<1) < dt * 3 {
            vel += forward * 5 + V3(0, 5.5, 0)
        }
        if g.meleeGap(self) < halfW + 0.7 && attackCooldown <= 0 {
            attackCooldown = 0.9
            g.hurtPlayer(spec.attack, from: pos, cause: "was nibbled to cinders by Scorchlings", knockback: 0.3, attacker: self)
        }
        return spec.speed
    }

    private func slagthrowerAI(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float {
        let h = hellState
        h.t -= dt; h.cool -= dt
        guard canTarget else { h.s = .idle; wander(); return moving ? spec.speed * 0.5 : 0 }
        let player = g.player.pos
        face(player)
        switch h.s {
        case .windup:
            if Rand.float(in: 0..<1) < dt * 20 { g.particles.flame(at: slagHand) }
            if h.t <= 0 {
                throwSlag(g, at: player)
                h.s = .recover; h.t = 0.6
                h.cool = Rand.float(in: 3.2...4.5)
            }
            return 0
        case .recover:
            if h.t <= 0 { h.s = .idle }
            return 0
        default:
            if g.meleeGap(self) < halfW + 1.1 && attackCooldown <= 0 {
                attackCooldown = 1.5
                g.hurtPlayer(spec.attack, from: pos, cause: "was flattened by a Slagthrower", knockback: 1.6, attacker: self)
            }
            if h.cool <= 0 && dist > 5 && dist < 26 && g.world.canSee(eye, g.player.eye) {
                h.s = .windup; h.t = 0.9
                g.sfx(.mob(kind, .ambient), 1.2, at: pos)
                return 0
            }
            h.sideT -= dt
            if h.sideT <= 0 { h.sideT = Rand.float(in: 2...4); h.side = Rand.float(in: 0..<1) < 0.5 ? -1 : 1 }
            strafe = dist < 18 ? h.side * spec.speed * 0.5 : 0
            return dist > 18 ? spec.speed : (dist < 8 ? -spec.speed : 0)
        }
    }

    // Where the glowing slag sits in the drawn-back hand.
    var slagHand: V3 {
        let side = V3(cosf(yaw), 0, -sinf(yaw))
        return pos + V3(0, height * 0.95, 0) + side * 0.5 - forward * 0.5
    }

    // A lump of slag lobbed to land where the target stands now (no lead: keep moving and it misses).
    func throwSlag(_ g: Game, at target: V3) {
        let from = pos + V3(0, height * 0.9, 0) + forward * 0.6
        let to = target + V3(0, 0.2, 0)
        let dist = simd_length(V2(to.x - from.x, to.z - from.z))
        let T: Float = 0.8 + dist * 0.035
        var v = (to - from) / T
        v.y += 0.5 * HellMobs.slagGravity * T
        g.hell.slag.append(HellWorld.Slag(pos: from, vel: v))
        HellStats.lobs += 1
        g.sfx(.fireball, 0.8, at: from)
    }
}

enum HellMobs {
    static let slagGravity: Float = 20
    static let caps: [Int] = [6, 4, 2, 1, 4, 14, 3]             // by MobKind.hellIndex (the Commander comes with musters)
    static let guardMax: [Int] = [4, 6, 8, 12]                   // by order rank (P185: harder)
    static let riposte: [Float] = [0, 0.35, 0.5, 0.6]           // P185: a blocked blow answered at once (not squires)
    static let feint: [Float] = [0, 0.2, 0.3, 0.4]              // P185: wind-ups that break off and come again
    static let windups: [Float] = [0.75, 0.62, 0.5, 0.55]
    static let chargeDamage: [Int] = [0, 8, 10, 13]
    static let chargeSpeed: [Float] = [0, 10, 11, 12]
    static let turnRate: [Float] = [2.6, 2.3, 2.6, 2.0]          // a player circling at 2 blocks at a walk is ~2 rad/s
}

extension MobManager {
    // A standing spot (floor below, two blocks of air) within a few blocks of `p`.
    static func groundSpot(_ w: World, near p: V3) -> V3? {
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        for dy in [0, 1, -1, 2, -2, 3, -3, 4, -4] {
            let y = Int(floor(p.y)) + dy
            if Blocks.collide[Int(w.block(x, y - 1, z))] && !Blocks.collide[Int(w.block(x, y, z))] && !Blocks.collide[Int(w.block(x, y + 1, z))]
                && !Blocks.isLiquid(w.block(x, y, z)) {
                return V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
            }
        }
        return nil
    }

    // Hell's own natural spawns (from trySpawnEmberdeep, outside fortresses): order patrols, Searwings in the open,
    // Scorchling packs and lone Slagthrowers, about a third of the attempts, with caps for 72 fps.
    func hellOwnSpawn(_ g: Game, at p: V3) -> Bool {
        guard Rand.float(in: 0..<1) < 0.3 else { return false }
        let w = g.world
        var count = (0, 0, 0, 0, 0, 0, 0)                           // by hellIndex (a tuple: no allocation)
        func get(_ i: Int) -> Int {
            switch i { case 0: return count.0; case 1: return count.1; case 2: return count.2; case 3: return count.3
                       case 4: return count.4; case 5: return count.5; default: return count.6 }
        }
        func bump(_ k: MobKind) {
            switch k.hellIndex { case 0: count.0 += 1; case 1: count.1 += 1; case 2: count.2 += 1; case 3: count.3 += 1
                                 case 4: count.4 += 1; case 5: count.5 += 1; default: count.6 += 1 }
        }
        for m in mobs where m.kind.hellOwn { bump(m.kind) }
        func room(_ k: MobKind) -> Bool { get(k.hellIndex) < HellMobs.caps[k.hellIndex] }
        func put(_ k: MobKind, _ q: V3) {
            guard let s = MobManager.groundSpot(w, near: q) else { return }
            mobs.append(Mob(k, at: s))
            bump(k)
        }
        func around(_ i: Int) -> V3 { p + V3(Float(i % 3) - 1, 0, Float(i / 3) - 1) * 1.6 }
        let r = Rand.int(in: 0..<100)
        if r < 35 {
            guard room(.brandKnight) || room(.brandSquire) else { return false }
            let lead: MobKind = Rand.int(in: 0..<5) == 0 && room(.brandChampion) ? .brandChampion : .brandKnight
            if room(lead) { put(lead, p) }
            for i in 0..<Rand.int(in: 1...2) where room(.brandSquire) { put(.brandSquire, around(i + 1)) }
        } else if r < 65 {
            guard room(.scorchling) else { return false }
            for i in 0..<Rand.int(in: 5...8) where room(.scorchling) { put(.scorchling, around(i)) }
        } else if r < 80 {
            guard room(.slagthrower) else { return false }
            put(.slagthrower, p)
        } else {
            guard room(.searwing) else { return false }
            let x = Int(floor(p.x)), z = Int(floor(p.z)), y = Int(floor(p.y))
            for dy in 1...6 where Blocks.collide[Int(w.block(x, y + dy, z))] { return false }      // needs open air
            for _ in 0..<Rand.int(in: 1...2) where room(.searwing) {
                mobs.append(Mob(.searwing, at: p + V3(Rand.float(in: -1...1), 4, Rand.float(in: -1...1))))
                bump(.searwing)
            }
        }
        return true
    }
}

extension Game {
    var inHell: Bool { dim.dim == .nether || (dim.dim == .deep && DeepGen.inHell(player.pos.y)) }

    func hellTick(_ dt: Float) {
        emberChargesTick(dt)
        slagTick(dt)
        guard survival, alive else { return }
        if inHell { hell.time += dt } else { hell.time = max(0, hell.time - dt * 0.25) }
        hell.musterCool -= dt
        if inHell && hell.time > 180 && hell.musterCool <= 0 && Rand.float(in: 0..<1) < dt / 120
            && !mobs.mobs.contains(where: { $0.kind == .brandCommander && $0.health > 0 && simd_length($0.pos - player.pos) < 160 }) {
            if muster() { hell.musterCool = 900 }
        }
    }

    // The Commander's muster: the Commander, a Champion, two Knights and two Squires out of the dark 28-40 blocks off.
    @discardableResult
    func muster(at fixed: V3? = nil) -> Bool {
        var at: V3?
        if let f = fixed { at = MobManager.groundSpot(world, near: f) } else {
            // P307 (a): 44-64 blocks out and out of sight (it was 28-40, often in plain view); the horn calls them in.
            for _ in 0..<16 where at == nil {
                let a = Rand.float(in: 0..<(2 * .pi)), r = Rand.float(in: 44...64)
                let q = player.pos + V3(cosf(a) * r, 0, sinf(a) * r)
                guard world.isLoaded(Int(floor(q.x)), Int(floor(q.z))) else { continue }
                if let s = MobManager.groundSpot(world, near: q), spawnHidden(s, min: 40) { at = s }
            }
        }
        guard let c = at else { return false }
        let ranks: [MobKind] = [.brandCommander, .brandChampion, .brandKnight, .brandKnight, .brandSquire, .brandSquire]
        let pw = dim.dim == .deep ? MobManager.depthPower(.deep, c.y) : 1
        for (i, k) in ranks.enumerated() {
            let a = Float(i) * 1.05
            let q = i == 0 ? c : (MobManager.groundSpot(world, near: c + V3(cosf(a) * 2.5, 0, sinf(a) * 2.5)) ?? c)
            let m = Mob(k, at: q)
            m.aggro = true; m.lockTime = 30; m.power = pw
            mobs.mobs.append(m)                                   // only the Commander is persistent (hellSetup)
        }
        HellStats.musters += 1
        sfx(.goatHorn, 1.4, at: c)
        onToast?("A horn in the dark: the Brand Commander's muster rides out")
        return true
    }

    func hellBossBar() -> (String, Float)? {
        guard let m = mobs.mobs.first(where: { $0.kind == .brandCommander && $0.health > 0 && simd_length($0.pos - player.pos) < 48 }) else { return nil }
        return (m.customName ?? "Brand Commander", Float(m.health) / Float(m.spec.health))
    }

    func hellDied(_ m: Mob) {
        switch m.kind {
        case .scorchling:
            let c = m.pos + V3(0, 0.3, 0)
            for _ in 0..<6 { particles.flame(at: c + V3(Rand.float(in: -0.3...0.3), Rand.float(in: 0...0.4), Rand.float(in: -0.3...0.3))) }
            sfx(.fireball, 0.4, at: c)
            if simd_length(player.pos - m.pos) < 1.5 { hurtPlayer(1, from: c, cause: "was singed by a Scorchling", knockback: 0.2, type: .fire) }
        case .brandChampion where m.killedByPlayer && Rand.int(in: 0..<12) == 0:
            drops.spawn(ItemStack(Items.id("brand_greatsword"), 1), at: m.pos + V3(0, 0.5, 0))
        case .brandCommander:
            if m.killedByPlayer { achieve("brand_commander") }
            onToast?("The Brand Commander falls. His order breaks and scatters")
        default: break
        }
    }

    // Slag in flight: gravity, a glowing trail, a splash that burns where it lands.
    func slagTick(_ dt: Float) {
        guard !hell.slag.isEmpty else { return }
        let centre = player.pos + V3(0, 0.9, 0)
        for i in hell.slag.indices.reversed() {
            var s = hell.slag[i]
            s.age += dt
            s.vel.y -= HellMobs.slagGravity * dt
            let np = s.pos + s.vel * dt
            // The lump itself: a big glowing blob drawn every frame, sparks behind it, a hiss as it flies.
            particles.add(Particle(pos: s.pos, vel: .zero, life: 0.05, maxLife: 0.05, layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1,
                                   size: 0.32, gravity: 0, color: V3(2.8, 1.1, 0.25), collide: false, glow: true))
            if Rand.float(in: 0..<1) < 0.6 { particles.flame(at: s.pos) }
            if Int(s.age / 0.3) != Int((s.age - dt) / 0.3) { sfx(.fizz, 0.7, at: s.pos) }
            let b = world.block(Int(floor(np.x)), Int(floor(np.y)), Int(floor(np.z)))
            if s.age > 6 || simd_length(np - centre) < 0.9 || Blocks.collide[Int(b)] || Blocks.isLiquid(b) {
                hell.slag.remove(at: i)
                slagSplash(at: s.pos)
                continue
            }
            s.pos = np
            hell.slag[i] = s
        }
    }

    func slagSplash(at c: V3) {
        sfx(.fireball, 1, at: c)
        for _ in 0..<14 {
            particles.add(Particle(pos: c, vel: V3(Rand.float(in: -3...3), Rand.float(in: 1...5), Rand.float(in: -3...3)), life: 0.7, maxLife: 0.7,
                                   layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1, size: 0.12, gravity: 14,
                                   color: V3(2.4, 0.9, 0.2), collide: true, glow: true))
        }
        let d = simd_length(player.pos + V3(0, 0.9, 0) - c)
        if d < 2.2 {
            HellStats.slagHits += 1
            let dmg = max(2, Int(7 * (1 - d / 2.6)))
            hurtPlayer(dmg, from: c, cause: "was buried in slag", knockback: 0.6, type: .fire)
            if !effects.has(.fireResistance) { onFire = max(onFire, 3) }
        }
        for m in mobs.mobs where m.health > 0 && m.kind != .slagthrower && simd_length(m.pos - c) < 1.6 { m.hit(from: c, damage: 4, knockback: 0.5) }
        // The ground where it lands catches.
        let x = Int(floor(c.x)), z = Int(floor(c.z))
        for y in stride(from: Int(floor(c.y)) + 1, through: Int(floor(c.y)) - 2, by: -1)
            where world.block(x, y, z) == AIR && Blocks.opaque[Int(world.block(x, y - 1, z))] {
            world.placeFire(IVec3(x, y, z)); break
        }
    }
}

// MARK: Models (1/16 block units, facing -Z)

func hellParts(_ m: Mob, swing: Float) -> [Part] {
    switch m.kind {
    case .searwing: return searwingParts(m)
    case .scorchling: return scorchlingParts(m, swing: swing)
    case .slagthrower: return slagthrowerParts(m, swing: swing)
    default: return orderParts(m, swing: swing)
    }
}

// The order's plate: dark burgundy over black mail, a glowing visor slit; rank shows in trim, plume, size of the shield
// and the blade. Pose: guard (shield up, blade raised), wind-up (blade high behind, shield swung aside, a glint),
// recover (shield down), charge (blade levelled, leaning in), stagger (shield dropped, rocked back).
private func orderParts(_ m: Mob, swing: Float) -> [Part] {
    let rank = m.kind.orderRank
    let s = m.hell?.s ?? .idle
    // P246: the Gravesworn (surface night duellists) wear the same cut of plate, tarnished grey-green with old brass,
    // a moss-dark tabard, a torn grave cloak and a cold blue light in the visor.
    let grave = m.kind == .spider || m.kind == .caveSpider
    let plate = grave ? V3(0.33, 0.36, 0.33) : V3(0.36, 0.05, 0.09)
    let dark = grave ? V3(0.1, 0.14, 0.11) : V3(0.2, 0.03, 0.06)
    let mail = grave ? V3(0.16, 0.16, 0.15) : V3(0.12, 0.1, 0.11)
    let trim = grave ? V3(0.5, 0.44, 0.3) : (rank >= 2 ? V3(0.85, 0.66, 0.22) : V3(0.45, 0.42, 0.44))
    let visor = grave ? V3(0.5, 1.3, 2.3) : V3(2.2, 0.7, 0.2)
    let steel = V3(0.72, 0.72, 0.76)
    let legSwing = s == .charge ? swing * 1.6 : swing
    var p: [Part] = [
        Part(mn: V3(-4, 0, -2), mx: V3(0, 12, 2), pivot: V3(-2, 12, 0), rotX: legSwing, color: plate, pattern: 8),
        Part(mn: V3(0, 0, -2), mx: V3(4, 12, 2), pivot: V3(2, 12, 0), rotX: -legSwing, color: plate, pattern: 8),
        Part(mn: V3(-4.3, 5, -2.3), mx: V3(-0.2, 7, 2.3), pivot: V3(-2, 12, 0), rotX: legSwing, color: trim, pattern: 8),
        Part(mn: V3(0.2, 5, -2.3), mx: V3(4.3, 7, 2.3), pivot: V3(2, 12, 0), rotX: -legSwing, color: trim, pattern: 8),
    ]
    // Body: leaning in on a charge, rocked back when staggered.
    let lean: Float = s == .charge || s == .aim ? 0.35 : (s == .stagger || s == .dazed ? -0.25 : 0)
    let body = V3(0, 12, 0)
    p.append(Part(mn: V3(-4, 12, -2), mx: V3(4, 24, 2), pivot: body, rotX: lean, color: plate, pattern: 8))
    p.append(Part(mn: V3(-3, 12.5, -2.4), mx: V3(3, 22, -2), pivot: body, rotX: lean, color: dark, pattern: 6))      // tabard
    p.append(Part(mn: V3(-0.6, 13, -2.6), mx: V3(0.6, 21.5, -2.3), pivot: body, rotX: lean, color: trim))            // its stripe
    p.append(Part(mn: V3(-4.2, 12, -2.2), mx: V3(4.2, 13.2, 2.2), pivot: body, rotX: lean, color: mail))              // belt
    p.append(Part(mn: V3(-5, 21.5, -2.5), mx: V3(-3, 24.5, 2.5), pivot: body, rotX: lean, color: plate * 1.15, pattern: 8))   // pauldrons
    p.append(Part(mn: V3(3, 21.5, -2.5), mx: V3(5, 24.5, 2.5), pivot: body, rotX: lean, color: plate * 1.15, pattern: 8))
    // Helm with the glowing slit, a plume for knights and up, a crown of spikes for the Commander.
    p.append(Part(mn: V3(-4, 24, -4), mx: V3(4, 32, 4), pivot: body, rotX: lean, color: dark, pattern: 8))
    p.append(Part(mn: V3(-3, 27.6, -4.3), mx: V3(3, 28.6, -3.9), pivot: body, rotX: lean, color: visor, pattern: 9))
    p.append(Part(mn: V3(-0.5, 24.5, -4.4), mx: V3(0.5, 27.4, -3.9), pivot: body, rotX: lean, color: trim))
    if grave {
        // The torn cloak down the back (ragged hem at three lengths) and a rust bloom on the helm.
        let cloak = V3(0.07, 0.08, 0.07)
        p.append(Part(mn: V3(-4.4, 6, 2.1), mx: V3(4.4, 24.5, 2.8), pivot: body, rotX: lean, color: cloak, pattern: 6))
        p.append(Part(mn: V3(-4.4, 3, 2.15), mx: V3(-1.6, 6, 2.75), pivot: body, rotX: lean, color: cloak, pattern: 6))
        p.append(Part(mn: V3(1.2, 4.5, 2.15), mx: V3(3.6, 6, 2.75), pivot: body, rotX: lean, color: cloak, pattern: 6))
        p.append(Part(mn: V3(-4.6, 23.5, -2.6), mx: V3(4.6, 25, 3), pivot: body, rotX: lean, color: cloak, pattern: 6))      // the hood fold
        p.append(Part(mn: V3(1.5, 29, -4.15), mx: V3(3.6, 31.2, -3.95), pivot: body, rotX: lean, color: V3(0.42, 0.22, 0.1), pattern: 4))
        if rank >= 1 { p.append(Part(mn: V3(-0.6, 32, -3), mx: V3(0.6, 33.5, 3.5), pivot: body, rotX: lean, color: trim * 0.8, pattern: 8)) }   // crest ridge
    } else if rank >= 1 && rank < 3 { p.append(Part(mn: V3(-0.8, 32, -2), mx: V3(0.8, 35, 4), pivot: body, rotX: lean, color: V3(0.6, 0.06, 0.08), pattern: 2)) }
    if rank == 3 {
        for x: Float in [-3.5, -1, 1.5] { p.append(Part(mn: V3(x, 32, -3.5), mx: V3(x + 2, 35, -1.5), pivot: body, rotX: lean, color: trim, pattern: 8)) }
        p.append(Part(mn: V3(-3, 14, 2), mx: V3(3, 30, 2.6), pivot: body, rotX: lean, color: V3(0.45, 0.04, 0.08), pattern: 6))   // banner on the back
        p.append(Part(mn: V3(-0.4, 14, 2.6), mx: V3(0.4, 36, 3.4), pivot: body, rotX: lean, color: V3(0.15, 0.12, 0.1)))
    }
    // Sword arm (right, +x) and blade along arm-local -z from the fist.
    var armR: Float
    switch s {
    case .windup: armR = 2.6
    case .recover: armR = 0.3
    case .aim, .charge: armR = 0.25                // the blade levelled like a lance
    case .stagger, .dazed: armR = 0.2
    default: armR = 1.0 + swing * 0.2
    }
    let sp = V3(6, 22, 0)
    p.append(Part(mn: V3(4, 11, -2), mx: V3(8, 23, 2), pivot: sp, rotX: armR, color: plate, pattern: 8))
    p.append(Part(mn: V3(4.2, 11, -2.2), mx: V3(7.8, 13.5, 2.2), pivot: sp, rotX: armR, color: mail))               // gauntlet
    let bladeLen: Float = [11, 16, 20, 22][min(3, rank)], bladeW: Float = rank >= 2 ? 1.4 : 1
    let glint = s == .windup ? V3(2.4, 2.1, 1.6) : steel
    p.append(Part(mn: V3(5.4, 11.5, -2.5), mx: V3(6.6, 12.5, 2.5), pivot: sp, rotX: armR, color: trim))            // cross guard
    p.append(Part(mn: V3(6 - bladeW / 2, 11.6, -2.5 - bladeLen), mx: V3(6 + bladeW / 2, 12.4, -2.5), pivot: sp, rotX: armR,
                  color: glint, pattern: s == .windup ? 9 : 8))
    // Shield arm (left): raised in front in guard, aim and charge; swung aside in the wind-up; hanging otherwise.
    let up = s == .idle || s == .aim || s == .charge
    // The shield darkens and loses its trim's shine as the guard wears down (each blocked blow shows).
    let wear: Float = m.hell.map { Float(max(0, $0.guardLeft)) / Float(max(1, m.orderGuardMax)) } ?? 1
    let face = plate * (0.45 + 0.45 * wear)
    let shieldW: Float = [4.5, 5, 5.5, 6.5][min(3, rank)]
    let lp = V3(-6, 22, 0)
    if up {
        let armL: Float = 1.3
        p.append(Part(mn: V3(-8, 11, -2), mx: V3(-4, 23, 2), pivot: lp, rotX: armL, color: plate, pattern: 8))
        p.append(Part(mn: V3(-6 - shieldW, 9.6, -shieldW * 1.2), mx: V3(-6 + shieldW, 10.8, shieldW * 1.2), pivot: lp, rotX: armL, color: face, pattern: 7))
        p.append(Part(mn: V3(-6.8, 9.3, -shieldW * 1.1), mx: V3(-5.2, 9.7, shieldW * 1.1), pivot: lp, rotX: armL, color: trim))      // boss stripe
        p.append(Part(mn: V3(-6 - shieldW * 0.9, 9.3, -0.8), mx: V3(-6 + shieldW * 0.9, 9.7, 0.8), pivot: lp, rotX: armL, color: trim))
    } else {
        let armL: Float = s == .windup ? 0.6 : 0.1
        p.append(Part(mn: V3(-8, 11, -2), mx: V3(-4, 23, 2), pivot: lp, rotX: armL, rotZ: s == .windup ? -0.5 : 0, color: plate, pattern: 8))
        p.append(Part(mn: V3(-9.6, 22 - shieldW * 2.2, -shieldW), mx: V3(-8.4, 22, shieldW), pivot: lp, rotX: armL, rotZ: s == .windup ? -0.5 : 0,
                      color: face, pattern: 7))
    }
    return p
}

// A burning bat-winged flier: dark leathery body glowing at the seams, wings flapping (faster in a dive, spread wide in
// the wind-up glow).
private func searwingParts(_ m: Mob) -> [Part] {
    let s = m.hell?.s ?? .idle
    let hide = V3(0.22, 0.08, 0.06), glow = s == .windup || s == .dive ? V3(2.6, 1.0, 0.25) : V3(1.6, 0.55, 0.15)
    let rate: Float = s == .dive ? 3 : 1.4
    let flap = sinf(m.walkPhase * rate) * (s == .dive ? 0.35 : 0.7)
    let spread: Float = s == .windup ? -0.2 : 0
    return [
        box(-2.5, 4, -6, 5, 4, 10, hide, 4),
        box(-1.8, 7.6, -5, 3.6, 0.6, 7, glow).withPattern(9),
        Part(mn: V3(-2, 4.5, -10), mx: V3(2, 8, -6), pivot: V3(0, 6, -6), rotX: s == .dive ? 0.4 : 0, color: hide, pattern: 4),
        Part(mn: V3(-1.5, 5, -10.4), mx: V3(-0.5, 6, -10), pivot: V3(0, 6, -6), color: glow, pattern: 9),
        Part(mn: V3(0.5, 5, -10.4), mx: V3(1.5, 6, -10), pivot: V3(0, 6, -6), color: glow, pattern: 9),
        Part(mn: V3(-0.5, 3, -12), mx: V3(0.5, 5, -10), pivot: V3(0, 6, -6), color: V3(0.8, 0.7, 0.5)),       // beak
        Part(mn: V3(-16, 6.5, -5), mx: V3(-2.5, 7.3, 3), pivot: V3(-2.5, 7, 0), rotZ: flap + spread, color: hide, pattern: 4),
        Part(mn: V3(2.5, 6.5, -5), mx: V3(16, 7.3, 3), pivot: V3(2.5, 7, 0), rotZ: -flap - spread, color: hide, pattern: 4),
        Part(mn: V3(-15, 6.4, -1), mx: V3(-3, 6.6, 1), pivot: V3(-2.5, 7, 0), rotZ: flap + spread, color: glow, pattern: 9),
        Part(mn: V3(3, 6.4, -1), mx: V3(15, 6.6, 1), pivot: V3(2.5, 7, 0), rotZ: -flap - spread, color: glow, pattern: 9),
        box(-1, 4.5, 4, 2, 1.5, 6, hide, 4),                                                                    // tail
    ]
}

// A knee-high fire imp: soot-black, a glowing belly and eyes, little horns.
private func scorchlingParts(_ m: Mob, swing: Float) -> [Part] {
    let soot = V3(0.14, 0.08, 0.07), ember = V3(2.2, 0.8, 0.2)
    return [
        Part(mn: V3(-2, 0, -1), mx: V3(-0.2, 3, 1), pivot: V3(-1, 3, 0), rotX: swing * 1.4, color: soot),
        Part(mn: V3(0.2, 0, -1), mx: V3(2, 3, 1), pivot: V3(1, 3, 0), rotX: -swing * 1.4, color: soot),
        box(-2.5, 3, -1.5, 5, 4, 3, soot, 4),
        box(-1.8, 3.6, -1.8, 3.6, 2.4, 0.4, ember).withPattern(9),
        box(-2.5, 7, -2.5, 5, 4, 4, soot, 4),
        box(-1.8, 9, -2.8, 1.2, 0.8, 0.4, ember).withPattern(9), box(0.6, 9, -2.8, 1.2, 0.8, 0.4, ember).withPattern(9),
        box(-2.4, 11, -1, 1, 2, 1, V3(0.3, 0.12, 0.08)), box(1.4, 11, -1, 1, 2, 1, V3(0.3, 0.12, 0.08)),
        Part(mn: V3(-4, 4, -0.8), mx: V3(-2.5, 7, 0.8), pivot: V3(-3, 7, 0), rotX: -swing, color: soot),
        Part(mn: V3(2.5, 4, -0.8), mx: V3(4, 7, 0.8), pivot: V3(3, 7, 0), rotX: swing, color: soot),
    ]
}

// A hunched brute of cooled slag: thick legs, a back of crusted plates, a small low head, a long throwing arm that
// draws back glowing before each lob.
private func slagthrowerParts(_ m: Mob, swing: Float) -> [Part] {
    let s = m.hell?.s ?? .idle
    let crust = V3(0.2, 0.17, 0.16), seam = V3(1.9, 0.6, 0.15), hot = V3(2.8, 1.3, 0.3)
    let arm: Float = s == .windup ? -2.3 : (s == .recover ? 1.9 : swing * 0.5)
    var p: [Part] = [
        Part(mn: V3(-6, 0, -3), mx: V3(-1, 11, 3), pivot: V3(-3.5, 11, 0), rotX: swing * 0.8, color: crust, pattern: 4),
        Part(mn: V3(1, 0, -3), mx: V3(6, 11, 3), pivot: V3(3.5, 11, 0), rotX: -swing * 0.8, color: crust, pattern: 4),
        Part(mn: V3(-7, 11, -5), mx: V3(7, 27, 5), pivot: V3(0, 11, 0), rotX: 0.35, color: crust, pattern: 4),
        Part(mn: V3(-6, 16, -5.4), mx: V3(6, 17, -5), pivot: V3(0, 11, 0), rotX: 0.35, color: seam, pattern: 9),
        Part(mn: V3(-5, 21, -5.4), mx: V3(5, 22, -5), pivot: V3(0, 11, 0), rotX: 0.35, color: seam, pattern: 9),
        Part(mn: V3(-6, 22, 4), mx: V3(6, 30, 7), pivot: V3(0, 11, 0), rotX: 0.35, color: crust * 0.8, pattern: 4),   // crusted back plates
        Part(mn: V3(-3, 22, -10), mx: V3(3, 28, -4), pivot: V3(0, 11, 0), rotX: 0.35, color: crust * 1.1, pattern: 4),  // low head
        Part(mn: V3(-2, 25, -10.4), mx: V3(-0.6, 26, -10), pivot: V3(0, 11, 0), rotX: 0.35, color: hot, pattern: 9),
        Part(mn: V3(0.6, 25, -10.4), mx: V3(2, 26, -10), pivot: V3(0, 11, 0), rotX: 0.35, color: hot, pattern: 9),
        Part(mn: V3(-11, 9, -2.5), mx: V3(-7, 25, 2.5), pivot: V3(-9, 25, 0), rotX: -swing * 0.5, color: crust, pattern: 4),
        Part(mn: V3(7, 7, -2.5), mx: V3(11, 25, 2.5), pivot: V3(9, 25, 0), rotX: arm, color: crust, pattern: 4),
    ]
    if s == .windup { p.append(Part(mn: V3(7, 4, -3), mx: V3(11, 8, 1), pivot: V3(9, 25, 0), rotX: arm, color: hot, pattern: 9)) }
    return p
}

extension Part {
    func withPattern(_ pat: Float) -> Part { var q = self; q.pattern = pat; return q }
}
