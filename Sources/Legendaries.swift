import Foundation
import simd

// Legendary weapons and armour (backlog C10; docs/status/legendaries.md).
//
// Eleven named one-off items, each found once per world: one from each legendary animal's body (Hunting), one from
// each boss the player brings down (the Hollow Wyrm, the Blight, the Warden, the elder guardian, the Ash Marshal, the
// Ash Chancellor) and one in the strongbox of the first Greywall Command Fortress you take. A legendary is an ordinary
// stack of its base item (a sword, a coat, a revolver...) carrying `ItemStack.legend`: its own name in gold, a glint,
// its story in the tooltip and a perk of its own:
//   bloodthirst  +30% melee damage, each hit heals half a heart
//   bulwark      a quarter less damage from blows (anything that hits you in melee)
//   ram          +25% melee damage, double knockback
//   fireproof    fire resistance while worn
//   wyrmfire     sets what it hits alight; +50% against bosses
//   blightward   night vision while worn; the Blight's withering wears off at once
//   swift        Speed I while worn
//   tide         water breathing and dolphin's grace while held
//   marksman     +40% damage, no recoil
//   steadfast    +25% damage, half the recoil
//   aegis        35% less from bullets, shells and blasts
// The gallery: legendaries hung in item frames near each other count as your gallery; it is counted when you're within
// 24 blocks of one (a toast for each new piece, honour when all eleven hang together).
// Saved in the world's effects dictionary ("legends": the keys found, then "|" and the gallery's best count).
enum Legendaries {
    enum Perk: String { case bloodthirst, bulwark, ram, fireproof, wyrmfire, blightward, swift, tide, marksman, steadfast, aegis }
    enum Source: Equatable { case animal(Int), boss(MobKind), fortress }
    struct Def {
        let key: String, name: String, base: [String], source: Source, perk: Perk
        let perkLine: String, story: [String]
        let worn: Bool                    // armour (its perk counts from the armour slots) or held
    }
    static let all: [Def] = [
        Def(key: "greyfang", name: "Greyfang", base: ["iron_sword", "stone_sword"], source: .animal(0), perk: .bloodthirst,
            perkLine: "+30% damage; each hit heals you", story: ["Forged from the Ashen Wolf's fang.", "It still hungers."], worn: false),
        Def(key: "frostjaw_mantle", name: "Frostjaw Mantle", base: ["leather_chestplate", "iron_chestplate"], source: .animal(1), perk: .bulwark,
            perkLine: "A quarter less from blows", story: ["Old Frostjaw's hide, cured in snow.", "Claws slide off it."], worn: true),
        Def(key: "ramhorn_maul", name: "Ramhorn Maul", base: ["mace", "iron_axe"], source: .animal(2), perk: .ram,
            perkLine: "+25% damage, double knockback", story: ["The Crag Ram's horn on an ash haft.", "It hits like the ram did."], worn: false),
        Def(key: "ember_hood", name: "Ember Hood", base: ["leather_helmet", "iron_helmet"], source: .animal(3), perk: .fireproof,
            perkLine: "Fire resistance while worn", story: ["The Ember Fox's tail, sewn to a hood.", "Flame won't take it."], worn: true),
        Def(key: "wyrmbone_blade", name: "Wyrmbone Blade", base: ["netherite_sword", "diamond_sword", "iron_sword"], source: .boss(.enderDragon), perk: .wyrmfire,
            perkLine: "Sets foes alight; +50% against bosses", story: ["Ground from the Hollow Wyrm's spine.", "It remembers burning skies."], worn: false),
        Def(key: "blightward_helm", name: "Blightward Helm", base: ["netherite_helmet", "diamond_helmet", "iron_helmet"], source: .boss(.brandCommander), perk: .blightward,
            perkLine: "Night vision; shrugs off withering", story: ["Beaten from a Brand Commander's crest.", "It sees in any dark."], worn: true),
        Def(key: "hush_boots", name: "Hush", base: ["diamond_boots", "iron_boots"], source: .boss(.warden), perk: .swift,
            perkLine: "Speed while worn", story: ["The blind keeper of the deep heard every step.", "These it never heard."], worn: true),
        Def(key: "tidecaller", name: "Tidecaller", base: ["trident", "iron_sword"], source: .boss(.elderGuardian), perk: .tide,
            perkLine: "Water breathing and swift swimming while held", story: ["The old sea sentinel's eye, set in the haft.", "The sea makes way."], worn: false),
        Def(key: "marshals_word", name: "The Marshal's Word", base: ["gun_revolver", "gun_sidearm"], source: .boss(.ashMarshal), perk: .marksman,
            perkLine: "+40% damage, no recoil", story: ["The Ash Marshal's own six-iron.", "His word was always final."], worn: false),
        Def(key: "chancellors_mandate", name: "The Chancellor's Mandate", base: ["gun_rifle", "gun_repeater"], source: .boss(.ashChancellor), perk: .steadfast,
            perkLine: "+25% damage, half the recoil", story: ["Carried by the Ash Chancellor's guard.", "It signed a thousand orders."], worn: false),
        Def(key: "greywall_aegis", name: "Greywall Aegis", base: ["diamond_chestplate", "iron_chestplate"], source: .fortress, perk: .aegis,
            perkLine: "35% less from bullets, shells and blasts", story: ["The commander's plate, never pierced.", "Until you took his fortress."], worn: true),
    ]
    static func def(_ key: String?) -> Def? { key.flatMap { k in all.first { $0.key == k } } }
    static func def(_ s: ItemStack) -> Def? { s.isEmpty ? nil : def(s.legend) }

    // MARK: State

    static var found = Set<String>()
    static var galleryBest = 0
    static var galleryNow = 0, galleryChecked: Double = -100
    static var awarded = 0                                           // (tests)
    static func reset() { found = []; galleryBest = 0; galleryNow = 0; galleryChecked = -100 }
    static func save(_ d: inout [String: String]) {
        guard !found.isEmpty || galleryBest > 0 else { return }
        d["legends"] = found.sorted().joined(separator: ",") + "|\(galleryBest)"
    }
    static func load(_ d: [String: String]) {
        reset()
        guard let s = d["legends"] else { return }
        let parts = s.split(separator: "|", omittingEmptySubsequences: false)
        found = Set((parts.first ?? "").split(separator: ",").map(String.init))
        galleryBest = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
    }

    // The item itself.
    static func make(_ d: Def) -> ItemStack? {
        guard let b = d.base.first(where: { Items.has($0) }) else { return nil }
        var s = ItemStack(Items.id(b), 1)
        s.legend = d.key
        if Guns.index(s.item) != nil { s.tag = Guns.all[Guns.index(s.item)!].mag }   // loaded
        return s
    }

    // Dropped (or handed over) once per world.
    @discardableResult
    static func award(_ g: Game, _ d: Def, at p: V3?, from: String) -> Bool {
        guard !found.contains(d.key), let s = make(d) else { return false }
        found.insert(d.key)
        awarded += 1
        if let p { g.drops.spawn(s, at: p) } else if !g.inventory.main.add(s).isEmpty { g.dropItem(s) }
        g.onToast?("Legendary: \(d.name), from \(from)." + Spine.legendHint(g))       // Y6: the next legend along the spine
        g.sfx(.goatHorn, 0.5, at: p ?? g.player.pos)
        return true
    }

    // Hunting.died: a legendary animal brought down.
    static func animalDied(_ g: Game, _ legend: Int, at p: V3) {
        guard let d = all.first(where: { $0.source == .animal(legend) }) else { return }
        award(g, d, at: p + V3(0, 0.5, 0), from: Hunting.legends[legend].name)
    }
    // Game.mobDied: a boss killed by the player.
    static func bossDied(_ g: Game, _ m: Mob) {
        guard m.killedByPlayer, let d = all.first(where: { $0.source == .boss(m.kind) }) else { return }
        award(g, d, at: m.pos + V3(0, 1, 0), from: m.spec.name)
    }
    // Game.greywallTake: a command fortress's strongbox.
    static func fortressTaken(_ g: Game, _ tier: Greywall.Tier) {
        guard tier == .command, let d = all.first(where: { $0.source == .fortress }) else { return }
        award(g, d, at: nil, from: "the commander's strongbox")
    }

    // MARK: Perks

    static func worn(_ g: Game) -> [Perk] { g.inventory.armor.slots.compactMap { s in def(s).flatMap { $0.worn ? $0.perk : nil } } }
    static func held(_ g: Game) -> Perk? { def(g.held).flatMap { $0.worn ? nil : $0.perk } }
    static func perk(_ s: ItemStack) -> Perk? { def(s).flatMap { $0.worn ? nil : $0.perk } }
    static func isBoss(_ m: Mob) -> Bool { [.enderDragon, .brandCommander, .warden, .elderGuardian, .ashMarshal, .ashChancellor, .ashBehemoth].contains(m.kind) }

    static func meleeScale(_ g: Game, _ m: Mob) -> Float {
        switch held(g) {
        case .bloodthirst?: return 1.3
        case .ram?: return 1.25
        case .wyrmfire?: return isBoss(m) ? 1.5 : 1
        default: return 1
        }
    }
    static func knockbackScale(_ g: Game) -> Float { held(g) == .ram ? 2 : 1 }
    // After a melee hit lands.
    static func meleeHit(_ g: Game, _ m: Mob) {
        switch held(g) {
        case .bloodthirst?: g.heal(1)
        case .wyrmfire?: if !m.spec.fireImmune { m.fire = max(m.fire, 5) }
        default: break
        }
    }
    static func gunScale(_ s: ItemStack) -> Float { perk(s) == .marksman ? 1.4 : (perk(s) == .steadfast ? 1.25 : 1) }
    static func recoilScale(_ s: ItemStack) -> Float { perk(s) == .marksman ? 0 : (perk(s) == .steadfast ? 0.5 : 1) }

    // Game.hurtPlayer: what armour perks take off.
    static func taken(_ g: Game, _ amount: Int, _ type: DamageType, attacker: Mob?) -> Int {
        let ps = worn(g)
        guard !ps.isEmpty else { return amount }
        var f: Float = 1
        if ps.contains(.bulwark) && attacker != nil && type == .generic { f *= 0.75 }
        if ps.contains(.aegis) && (type == .projectile || type == .explosion) { f *= 0.65 }
        guard f < 1 else { return amount }
        let a = Float(amount) * f, whole = floorf(a)
        return max(1, Int(whole) + (Rand.float(in: 0..<1) < a - whole ? 1 : 0))
    }

    // MARK: Every second (TownLaw.tick)

    static func tick(_ g: Game) {
        let ps = worn(g)
        if ps.contains(.fireproof) { g.applyEffect(.fireResistance, amp: 0, seconds: 3, ambient: true) }
        if ps.contains(.blightward) {
            g.applyEffect(.nightVision, amp: 0, seconds: 12, ambient: true)
            if g.effects.has(.wither) { g.effects.remove(.wither) }
        }
        if ps.contains(.swift) { g.applyEffect(.speed, amp: 0, seconds: 3, ambient: true) }
        if held(g) == .tide {
            g.applyEffect(.waterBreathing, amp: 0, seconds: 3, ambient: true)
            g.applyEffect(.dolphinsGrace, amp: 0, seconds: 3, ambient: true)
        }
        if g.clock - galleryChecked >= 5 { galleryChecked = g.clock; gallery(g) }
    }

    // Legendaries hanging in item frames within 24 blocks of the player, counted once each.
    @discardableResult
    static func gallery(_ g: Game) -> Int {
        let p = g.player.pos
        var keys = Set<String>()
        for (q, be) in g.world.blockEntities where be.kind == .frame {
            guard abs(Float(q.x) - p.x) < 24 && abs(Float(q.z) - p.z) < 24 && abs(Float(q.y) - p.y) < 16 else { continue }
            if let k = be.container[0].legend, def(k) != nil { keys.insert(k) }
        }
        galleryNow = keys.count
        if keys.count > galleryBest {
            galleryBest = keys.count
            g.onToast?("Your gallery: \(keys.count) of \(all.count) legends on display")
            if keys.count == all.count { Honour.earn(g, 5, source: "gallery", "you gathered every legend in one hall") }
        }
        return keys.count
    }

    // MARK: Tooltip (Renderer)

    static let gold = V4(1, 0.78, 0.25, 1)
    static func tooltip(_ s: ItemStack) -> [String] {
        guard let d = def(s) else { return [] }
        return ["Legendary", d.perkLine] + d.story
    }
}
