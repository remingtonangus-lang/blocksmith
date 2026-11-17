import Foundation
import simd

// Nov 16 evening playtest (20:50:16-20:50:35 at a Greywall garrison: took 9, then 18 in one hit; "what gun did that guy
// use? Whatever gun he used was overpowered... a few shots, I'm dead"): questcheck --soldierguns (also in every run)
// puts one soldier of the same rank (a Trooper, Normal, night) with each gun soldiers carry against him in iron armour,
// 12 blocks off on a walled floor, for 20 s, his health topped up every tick, and measures the damage it deals a second
// and its hardest single tick. No gun deals more than three times the middle gun's damage a second, or over 10 (half his 20, Normal's cap on one blow) in one tick.
enum SoldierGunCheck {
    struct Row { let gun: Int; let name: String; let dps: Float; let worst: Int }

    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let scope = SuiteScope(g); defer { scope.putBack(g) }
        let w = g.world
        let pos0 = g.player.pos, surv0 = g.survival, fly0 = g.player.flying, time0 = g.time, diff0 = g.difficulty
        let health0 = g.health, mobs0 = g.mobs.mobs, armour0 = g.inventory.armor.slots, main0 = g.inventory.main.slots, enc0 = w.ships.encounters
        var placed: [IVec3] = []
        let fx = Int(floor(pos0.x)) + 400, fz = Int(floor(pos0.z))
        _ = w.loadSync(center: V3(Float(fx), pos0.y, Float(fz)), radius: 3)
        let py = min(CH - 30, w.topY(fx, fz) + 24)
        defer {
            for q in placed { w.setBlock(q.x, q.y, q.z, AIR) }
            g.mobs.mobs = mobs0; w.pendingMobs.removeAll(); g.arms.slugs.removeAll()
            g.player.pos = pos0; g.player.vel = .zero; g.survival = surv0; g.player.flying = fly0; g.time = time0
            g.difficulty = diff0; g.health = health0; g.alive = true; g.menu = nil
            g.inventory.armor.slots = armour0; g.inventory.main.slots = main0; w.ships.encounters = enc0
        }
        w.ships.encounters = false
        g.paused = false; g.riding = nil; w.ships.pilot = nil; w.ships.aboard = nil
        g.survival = true; g.player.flying = false; g.difficulty = 2
        let iron = ["iron_helmet", "iron_chestplate", "iron_leggings", "iron_boots"]
        for i in 0..<4 { g.inventory.armor[i] = ItemStack(Items.id(iron[i]), 1) }
        for z in (fz - 40)...(fz + 20) { for x in (fx - 8)...(fx + 8) { for y in (py - 1)...(py + 5) {
            let edge = abs(x - fx) == 8 || z == fz - 40 || z == fz + 20
            let want = y <= py || (edge && y <= py + 3) ? STONE : AIR
            if w.block(x, y, z) != want { w.setBlock(x, y, z, want); placed.append(IVec3(x, y, z)) }
        } } }
        let spot = V3(Float(fx) + 0.5, Float(py + 1), Float(fz) + 0.5 + 6)
        let guns = (0..<Guns.all.count).filter { gi in
            !Guns.isRetired(gi) && !Guns.isLauncher(gi) && Guns.all[gi].shot == .bullet
        }
        var rows: [Row] = []
        var lootLeft: [String] = []
        for gi in guns {
            g.mobs.mobs.removeAll(); w.pendingMobs.removeAll(); g.arms.slugs.removeAll(); g.drops.items.removeAll()
            let m = Mob(.soldierTrooper, at: spot + V3(0, 0, -12))
            m.troop = Int8(TroopClass.regular.rawValue)
            let b = m.soldierBrain
            b.gun = gi; b.mag = Guns.all[gi].mag
            m.variant = gi
            m.aggro = true; b.lastSeen = g.player.eye; b.seenAgo = 0
            g.mobs.mobs = [m]
            var dealt = 0, worst = 0, s: Float = 0
            while s < 20 {
                g.health = 20; g.hunger = 20; g.saturation = 5; g.alive = true; g.menu = nil
                for i in 0..<4 { g.inventory.armor[i] = ItemStack(Items.id(iron[i]), 1) }      // (fresh: hits wear it away)
                g.player.pos = spot; g.player.vel = .zero
                g.time = DAY_LENGTH * 0.75
                if b.gun != gi { b.gun = gi }
                if m.health <= 0 { break }
                m.health = max(m.health, 1)
                g.tick(0.05); s += 0.05
                let lost = max(0, 20 - g.health)
                dealt += lost; worst = max(worst, lost)
            }
            rows.append(Row(gun: gi, name: Guns.all[gi].name, dps: Float(dealt) / max(1, s), worst: worst))
            // Nov 15 20:52:53 ("why am I picking up those weapons but not that ammo?"): killed, what he drops (his rounds,
            // a quarter of the time his gun) is all picked up when he walks over where he fell.
            g.drops.items.removeAll()
            for i in 0..<36 { g.inventory.main[i] = .empty }
            m.killedByPlayer = true
            g.soldierDied(m)
            let fell = m.pos
            g.mobs.mobs.removeAll()
            let dropped = g.drops.items.map { Items.key($0.stack.item) }
            for k in 0..<120 {
                g.health = 20; g.alive = true
                g.player.pos = k < 30 ? spot : V3(fell.x, Float(py + 1), fell.z)
                g.player.vel = .zero
                g.tick(0.05)
            }
            let left = g.drops.items.filter { !$0.stack.isEmpty }.map { Items.key($0.stack.item) + "@" + String(format: "%.1f,%.1f,%.1f", $0.pos.x - fell.x, $0.pos.y - Float(py + 1), $0.pos.z - fell.z) }
            if !left.isEmpty || dropped.isEmpty { lootLeft.append(Guns.all[gi].name + ": dropped " + dropped.joined(separator: ",") + ", left " + left.joined(separator: " ")) }
        }
        // Nov 16 20:49:57 (on foot in a Greywall garrison's yard with a Slatefall Carbine: "I don't think I can land a
        // hit"): a trooper standing 8, 20 and 35 blocks off, ten rounds aimed at his chest one at a time (on the
        // headset braced with both hands, and one-handed, which throws a shouldered gun's rounds wide by design, P499):
        // how many register.
        if let gi = Guns.all.firstIndex(where: { $0.key == "gun_slatefall" }) {
            let held0 = g.inventory.held, two0 = g.vrTwoHanded
            defer { g.inventory.held = held0; g.vrAim = nil; g.vrTwoHanded = two0 }
            var lines: [String] = [], braced = 0, bracedShots = 0
            for (range, two) in [(Float(8), true), (20, true), (35, true), (20, false)] {
                g.mobs.mobs.removeAll(); g.arms.slugs.removeAll()
                let m = Mob(.soldierTrooper, at: spot + V3(0, 0, -range))
                m.faction = Faction.greywall.rawValue
                m.troop = Int8(TroopClass.regular.rawValue)
                g.mobs.mobs = [m]
                let stand = m.pos
                var hits = 0
                for _ in 0..<10 {
                    m.health = m.spec.health; m.pos = stand; m.vel = .zero; m.invulnerable = 0
                    g.player.pos = spot; g.player.vel = .zero
                    var gun = ItemStack(Items.id(Guns.all[gi].key), 1); gun.tag = 30
                    g.inventory.held = gun
                    let chest = stand + V3(0, m.height * 0.6, 0)
                    let hand = g.player.eye + V3(0.2, -0.3, -0.1)
                    g.vrAim = (hand, simd_normalize(chest - hand)); g.vrTwoHanded = two
                    let h0 = m.health
                    g.fireHeldGun(gi)
                    for _ in 0..<20 { m.pos = stand; m.vel = .zero; g.armsTick(0.05) }
                    if m.health < h0 { hits += 1 }
                }
                if two { braced += hits; bracedShots += 10 }
                lines.append(String(format: "%.0f blocks %@: %d of 10", range, two ? "braced" : "one-handed", hits))
            }
            g.mobs.mobs.removeAll(); g.arms.slugs.removeAll()
            print("soldierguns: carbine hits on a trooper: " + lines.joined(separator: ", "))
            check(braced == bracedShots, "soldierguns: braced, every Slatefall round aimed at a trooper's chest (8 to 35 blocks) registers (" + lines.joined(separator: ", ") + ")")
        }
        let sorted = rows.map { $0.dps }.sorted()
        let mid = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        for r in rows.sorted(by: { $0.dps > $1.dps }) {
            print(String(format: "soldierguns: %-30@ %5.2f a second, hardest tick %2d", r.name as NSString, r.dps, r.worst))
        }
        check(lootLeft.isEmpty, "soldierguns: walking over a soldier he killed, he picks up all he dropped, rounds and gun" + (lootLeft.isEmpty ? "" : " (" + lootLeft.joined(separator: "; ") + ")"))
        // (the bar: three times the middle gun's damage a second and no single tick over Normal's cap on one blow, half
        // his health (P413). Measured in iron before ledgers 245-246 the Sturmbrecher dealt 5 times the middle gun and 16
        // in one tick (his note: 18); after, 2.2 times and 6: still the hardest soldier gun, as P501 asked of it.)
        let over = rows.filter { $0.dps > mid * 3 || $0.worst > 10 }
        check(!rows.isEmpty && over.isEmpty, String(format: "soldierguns: no soldier's gun deals over three times the middle gun's %.2f a second to him in iron, or over 10 (half his health) in one tick", mid)
              + (over.isEmpty ? "" : " (over: " + over.map { String(format: "%@ %.2f, hardest tick %d", $0.name, $0.dps, $0.worst) }.joined(separator: "; ") + ")"))
    }
}
