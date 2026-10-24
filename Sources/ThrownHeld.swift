import Foundation
import simd

// P371 (Oct 18 07:54: "if I hold on to an item and swing my arm, that thing should go flying. Should be able to hit
// stuff too"). On the headset a grip held on whatever is in the hand (not a gun) is a hold: swung and let go, the thing
// leaves the hand with the hand's speed (QuestControls; a quick grip tap still steps the hotbar). It flies as a dropped
// item does, bounces off what it meets and comes to rest where anyone can pick it up again. In flight it hits the
// first creature or person in its way once: damage by what it is and how fast it goes (a sword does a sword's damage
// at a hard throw, a block knocks for 2-3, bread barely), a knock back the same way, and a hard hit staggers them
// (Mob.stagger: rocked back a moment) or, if it kills, drops them as a ragdoll like any death. A few flights at a time.
enum ThrownHeld {
    final class Flight {
        weak var e: ItemEntity?
        var t: Float = 0
        var done = false
        init(_ e: ItemEntity) { self.e = e }
    }
    static var flights: [Flight] = []
    static var thrown = 0, hits = 0, lastDamage = 0          // (checks)
    static let maxSpeed: Float = 24
    static let maxFlights = 6

    // How much it carries: a weapon or tool its whole weight, a block a fair lump, anything else (food, a feather) little.
    static func mass(_ s: ItemStack) -> Float {
        let d = s.def
        if d.durability > 0 || d.attack > 1 { return 1 }
        if d.block != nil { return 0.8 }
        return 0.2
    }

    // Damage for a hit at `speed` (blocks a second): the item's own attack (a fist's 1 for anything else) times its
    // weight, full at 12 b/s and up to half again at the top of a throw.
    static func damage(_ s: ItemStack, speed: Float) -> Int {
        let base: Float = max(1, s.def.attack) * mass(s)
        let k: Float = min(1.5, max(0, (speed - 2) / 10))
        let base3: Float = s.def.block != nil && s.def.attack <= 1 ? 3 : base
        return Int((base3 * k).rounded())
    }

    // Lets the held thing go from `from` at `vel` (world, blocks a second). One of a stack; a tool or weapon whole.
    @discardableResult
    static func throwHeld(_ g: Game, from: V3, vel: V3) -> Bool {
        let h = g.held
        guard !h.isEmpty, g.heldGun == nil, g.alive else { return false }
        var v = vel
        let sp = simd_length(v)
        if sp > maxSpeed { v *= maxSpeed / sp }
        let one = h.with(count: 1)
        if g.survival { var rest = h; rest.count -= 1; g.inventory.held = rest.count > 0 ? rest : .empty }
        g.drops.spawn(one, at: from, vel: v, delay: 0.8)
        if let e = g.drops.items.last {
            e.thrown = true
            if flights.count >= maxFlights { flights.removeFirst() }
            flights.append(Flight(e))
        }
        g.sfx(.throwItem, min(1, 0.4 + simd_length(v) / 30), at: from)
        g.swing = 1
        thrown += 1
        return true
    }

    // Once a tick (Game.update): flights look for something to hit.
    static func tick(_ g: Game, _ dt: Float) {
        guard !flights.isEmpty else { return }
        for f in flights where !f.done {
            guard let e = f.e, !e.stack.isEmpty else { f.done = true; continue }
            f.t += dt
            let sp = simd_length(e.vel)
            if f.t > 5 || (e.onGround && sp < 1) { f.done = true; e.thrown = false; continue }
            guard sp > 3 else { continue }
            for m in g.mobs.mobs where m.health > 0 && simd_length_squared(m.pos - e.pos) < 9 {
                let hw = m.halfW * m.scale + 0.2
                let dy = e.pos.y + 0.12 - m.pos.y
                guard abs(e.pos.x - m.pos.x) < hw, abs(e.pos.z - m.pos.z) < hw, dy > -0.1, dy < m.height * m.scale + 0.1 else { continue }
                let dmg = damage(e.stack, speed: sp)
                lastDamage = dmg
                let kb: Float = min(3, mass(e.stack) * sp / 7)          // P423 (b): a hard throw of something heavy launches them
                Mob.playerMelee = true
                m.hit(from: e.pos - simd_normalize(e.vel), damage: dmg, knockback: kb)
                Mob.playerMelee = false
                if dmg > 0 { m.provoke(g) }
                if dmg >= 4 || sp > 14 { m.stagger = 0.5 }
                g.sfx(e.stack.def.block != nil ? .attackWeak : .attackKnockback, 0.7, at: e.pos)
                // It glances off: back and down, most of its speed spent.
                e.vel = V3(-e.vel.x * 0.25, min(e.vel.y, 0) * 0.3, -e.vel.z * 0.25)
                hits += 1
                f.done = true
                break
            }
        }
        flights.removeAll { $0.done }
    }
}

// P371's check (questcheck --throw-only): on a stone floor high over the ground, an iron sword thrown hard at a cow and
// a loaf of bread at a townsman, through Game.tick: the sword hurts and staggers, the bread barely; both come to rest on
// the floor and are picked up again.
enum ThrownHeldCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let pos0 = g.player.pos, surv0 = g.survival, fly0 = g.player.flying, mobs0 = g.mobs.mobs, main0 = g.inventory.main.slots
        let sel0 = g.inventory.selected, time0 = g.time
        let fx = Int(floor(pos0.x)), fz = Int(floor(pos0.z)), py = min(CH - 30, w.topY(fx, fz) + 24)
        var placed: [IVec3] = []
        defer {
            for q in placed { w.setBlock(q.x, q.y, q.z, AIR) }
            g.mobs.mobs = mobs0; g.drops.items.removeAll(); ThrownHeld.flights.removeAll()
            g.player.pos = pos0; g.player.vel = .zero; g.survival = surv0; g.player.flying = fly0
            g.inventory.main.slots = main0; g.inventory.selected = sel0; g.time = time0; g.menu = nil
        }
        _ = w.loadSync(center: V3(Float(fx), Float(py), Float(fz)), radius: 3)
        for z in (fz - 12)...(fz + 12) { for x in (fx - 12)...(fx + 12) {
            w.setBlock(x, py - 1, z, STONE); placed.append(IVec3(x, py - 1, z))
            for y in py...(py + 3) where !w.isAir(x, y, z) { w.setBlock(x, y, z, AIR) }
        } }
        g.time = DAY_LENGTH * 0.25
        g.survival = true; g.alive = true; g.player.flying = false; g.menu = nil
        g.player.pos = V3(Float(fx) + 0.5, Float(py), Float(fz) + 0.5); g.player.vel = .zero
        g.mobs.mobs = []
        func throwAt(_ key: String, _ kind: MobKind) -> (Mob, Int, Bool, Bool) {
            let m = Mob(kind, at: V3(Float(fx) + 0.5, Float(py), Float(fz) - 5.5))
            m.persistent = true
            g.mobs.mobs = [m]; g.mobs.rebuildIndex()
            let hp = m.health
            g.inventory.main.slots = Array(repeating: .empty, count: 36)
            g.inventory.selected = 0
            g.inventory.held = ItemStack(Items.id(key), 1)
            let from = g.player.eye - V3(0, 0.3, 0)
            let to = m.pos + V3(0, m.height * m.scale * 0.5, 0)
            let d = simd_normalize(to - from)
            _ = ThrownHeld.throwHeld(g, from: from, vel: d * 16 + V3(0, 1.2, 0))
            let gone = g.held.isEmpty
            var staggered = false
            for _ in 0..<(30 * 4) { g.tick(1.0 / 30); if m.stagger > 0 { staggered = true } }
            // Walk over to it (the target out of the way): it is picked up again.
            let dealt = hp - m.health
            g.mobs.mobs = []; g.health = 20; g.alive = true
            if let e = g.drops.items.first(where: { Items.key($0.stack.item) == key }) {
                g.player.pos = e.pos; g.player.vel = .zero
                for _ in 0..<(30 * 4) { g.tick(1.0 / 30) }
            }
            let back = g.inventory.main.slots.contains { Items.key($0.item) == key }
            return (m, dealt, staggered, gone && back)
        }
        let h0 = ThrownHeld.hits
        let (_, sword, st, swordBack) = throwAt("iron_sword", .cow)
        let swordHits = ThrownHeld.hits - h0
        let h1 = ThrownHeld.hits
        let (_, bread, _, breadBack) = throwAt("bread", .villager)
        check(swordHits == 1 && sword >= 5 && st && swordBack,
              "P371 thrown: an iron sword thrown at a cow hits once for \(sword) and staggers it (\(st)); it lands and is picked up again (\(swordBack))")
        check(ThrownHeld.hits - h1 == 1 && bread <= 1 && breadBack,
              "P371 thrown: a loaf thrown at a townsman hits \(ThrownHeld.hits - h1) time for \(bread); picked up again (\(breadBack))")
    }
}
