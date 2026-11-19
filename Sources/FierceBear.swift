import Foundation
import simd

// Ledger 342 (Remington, Nov 18 20:45, on the new polar bear of ledger 332: "those polar bears ought to be scary ...
// it should be a fierce beast unlike other mobs players fear until they have steel or better armour"):
//   - it sees him from far off (28 blocks, in sight) and gives a warning roar, stands its ground a moment, then charges
//     with a roar faster than he can sprint (9.5 b/s against his 7.0 flat, 8.6 in the headset);
//   - a heavy swipe that throws him back (12 at Normal); 80 health (was 30), so iron gear loses the fight;
//   - its claws skate on hard plate: the blow is cut by the toughness of what he wears (a full steel set, toughness 6,
//     takes 40 %; titanium and duskium the same), so from steel up he wins;
//   - it gives up when he is 48 off or out of the fight (creative, dead), and comes for him again only when it sees him;
//   - no polar bear comes within 200 blocks of a world's spawn point, so the snowy start stays a start.
// Cubs and the legendary Old Frostjaw keep their own ways (Hunting.swift). BS_OLDBEAR=1: the bear as before (neutral,
// 30 health, 6 a blow, the old growl).
enum FierceBear {
    static let old = Env.all["BS_OLDBEAR"] == "1"
    static let health = 80
    static let swipe = 12
    static let notice: Float = 28, giveUp: Float = 48
    static let charge: Float = 9.5
    // Ledger 344 (Remington, Nov 19 01:08 on the bear's clip: "it ought to be bigger, the animal, so it's real scary and a
    // little faster, around sprinting speed in 5s bursts"): a grown wild bear stands half as big again (2 blocks tall, its
    // model 2 wide; its body box 1.45 wide, the old bear's, so it still gets between trees: 2 wide stuck it on a trunk in
    // the chase clip; its reach 0.3 longer), and it charges in bursts: 5 s flat out at 10 b/s (a little over his sprint, 8.6 in
    // the headset), then 2 s winded at a lope, then the next burst. A sprinting player gains a step while it blows, then
    // loses it again. BS_OLDBEARRUN=1: as ledger 342 (its old size, one steady 9.5 charge).
    static let oldRun = old || Env.all["BS_OLDBEARRUN"] == "1"
    static let size: Float = 1.45
    static let burst: Float = 10, burstFor: Float = 5, windedFor: Float = 2, lope: Float = 4.5
    static var lastSpeed: Float = 0                // (checks: what it ran at last tick)
    static func runSpeed(_ m: Mob, _ g: Game, dist: Float) -> Float {
        let fight = m.spec.speed * 1.4                                   // (on him and him standing: a fighting pace)
        guard !oldRun else { return dist > 4 ? charge : fight }
        let run = m.phaseTime.truncatingRemainder(dividingBy: burstFor + windedFor) < burstFor ? burst : lope
        guard dist <= 4 else { return run }
        // (on him while he runs: it runs him down rather than dropping to its fighting pace beside him and letting him go,
        // the chase clip's fault: it closed to 3 blocks and he sprinted clear)
        let his = simd_length(V2(g.player.vel.x, g.player.vel.z))
        return his > 1 ? run : fight
    }
    static let stand: Float = 1.2                 // the warning: it stands and roars this long before it comes
    static let spawnClear: Float = 200
    static var warnings = 0, charges = 0, swipes = 0, kept = 0       // (checks)

    // The share of a swipe that gets through what he wears: claws skate on hard plate.
    static func clawShare(_ g: Game) -> Float { max(0.4, 1 - 0.1 * g.inventory.toughness) }

    // Natural spawns: none near the world's spawn point (where a new world starts him, not his bed).
    static var origin: (seed: UInt64, at: V2)?
    static func nearSpawn(_ g: Game, _ x: Int, _ z: Int) -> Bool {
        guard !old else { return false }
        let w = g.world
        if origin?.seed != w.seed {
            let sp = Game.findSpawn(gen: w.gen, seed: w.seed)
            origin = (w.seed, V2(sp.x, sp.z))
        }
        guard let o = origin?.at else { return false }
        let near = simd_length(V2(Float(x), Float(z)) - o) < spawnClear
        if near { kept += 1 }
        return near
    }
}

extension Mob {
    // animalAI: the fierce polar bear (nil: not one, or the old bear).
    func fierceBearAI(_ dt: Float, _ g: Game, dist: Float) -> Float? {
        guard kind == .polarBear, !FierceBear.old, !baby, legend < 0, !tamed else { return nil }
        let p = g.player.pos
        if !FierceBear.oldRun && scale != FierceBear.size { scale = FierceBear.size }     // (ledger 344: half as big again)
        let inFight = g.survival && g.alive
        switch phase {
        case 1:                                           // the warning: up on its hind legs, facing him, roaring
            phaseTime += dt
            face(p); moving = false
            if !inFight || dist > FierceBear.giveUp { phase = 0; aggro = false; return 0 }
            if phaseTime >= FierceBear.stand || wasHit {
                phase = 2; phaseTime = 0; wasHit = false
                FierceBear.charges += 1
                g.sfx(.bearCharge, 1, at: eye)
            }
            return 0
        case 2:                                           // the charge and the fight
            phaseTime += dt
            if !inFight || dist > FierceBear.giveUp { phase = 0; aggro = false; return 0 }
            aggro = true
            face(p); moving = true
            if g.meleeStrike(self, reach: halfW + 1.6 + (FierceBear.oldRun ? 0 : 0.3)) {
                attackCooldown = 1.1
                FierceBear.swipes += 1
                let blow = Float(FierceBear.swipe) * FierceBear.clawShare(g)
                let n = Int(blow) + (Rand.float(in: 0..<1) < blow - floorf(blow) ? 1 : 0)
                g.hurtPlayer(max(1, n), from: pos, cause: "was mauled by a \(spec.name)", knockback: 1.6, attacker: self)
            }
            // (a charge runs flat out; once on him, it keeps at him at a fighting pace)
            FierceBear.lastSpeed = FierceBear.runSpeed(self, g, dist: dist)
            return FierceBear.lastSpeed
        default:
            // Hit or seen: the warning, then the charge.
            let sees = inFight && dist < FierceBear.notice && g.world.canSee(eye, g.player.eye)
            if (aggro || wasHit || sees) && inFight {
                phase = wasHit ? 2 : 1; phaseTime = 0
                if phase == 1 { FierceBear.warnings += 1; g.sfx(.bearWarn, 1, at: eye) }
                else { FierceBear.charges += 1; g.sfx(.bearCharge, 1, at: eye) }
                wasHit = false
                face(p)
                return 0
            }
            return nil                                    // (nothing to fight: an animal like the rest)
        }
    }
}
