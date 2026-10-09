import Foundation
import simd

// Towns of people. Every villager is a townsperson with a name, a town, a role and a look (VillagerData.person /
// town / role / look), set the first time it thinks. Roles: shopkeepers (one per shop, Shops.swift), deputies who
// patrol the square and keep watch at night, farmers, craftsfolk (the old job-site professions, still bartering),
// workers, elders and children. Adults carry what their trade gives them (swords, pitchforks, hammers, cleavers,
// axes, shovels, hoes) and use it: hostile mobs that come into town are met by everyone armed, while elders and
// children run. Hurt a townsperson and the armed folk nearby turn on you for a while; draw a gun on one and they put
// their hands up. They greet you by name, and what they say follows the hour and what the town thinks of you.
//
// Day (adults, ticks of 24000 from sunrise, VillageLife.activity): idle, work from 2000, a midday meal at the saloon
// 5600-6600, work, meet at the bell 9000-11000, an evening at the saloon until 12000, then bed. Shopkeepers keep
// their counter through their shop's hours; deputies never take a bed.

enum TownWeapon: Int, CaseIterable {
    case none, sword, pitchfork, hammer, cleaver, axe, shovel, hoe

    var damage: Int { [0, 6, 5, 5, 5, 6, 3, 3][rawValue] }
    var reach: Float { self == .pitchfork ? 2.9 : 2.2 }
    var cooldown: Float { self == .pitchfork ? 1.3 : 1.1 }
    var name: String { ["bare hands", "sword", "pitchfork", "hammer", "cleaver", "axe", "shovel", "hoe"][rawValue] }
}

// Per-mob townsperson state that isn't saved (anger, reactions, animation timers).
struct TownState {
    var anger: Float = 0            // > 0: fighting the player (seconds left)
    var handsUp: Float = 0          // > 0: hands raised (a gun pointed at them)
    var greetCooldown: Float = 0
    var swing: Float = 0            // > 0: a weapon swing in progress (seconds left)
    var think: Float = 0
    weak var foe: Mob?
    var mealSpot: V3?
    var mealSearch: Float = 0
    var eating = false
    var aimMemory: Float = 0        // > 0: already offended by a pointed gun (no further reputation loss)
}

enum Townsfolk {
    // Original first names and surnames with a frontier feel. Real given names only; TownTests keeps out the
    // leading characters of the game this borrows its feel from.
    static let firstNames = ["Amos", "Ada", "Asa", "Beulah", "Calvin", "Clara", "Cyrus", "Delia", "Eben", "Edna", "Elias", "Etta",
                             "Ezra", "Flora", "Gideon", "Hattie", "Henry", "Ida", "Isaiah", "Jonah", "Josephine", "Lena", "Levi",
                             "Lottie", "Luther", "Mabel", "Matthias", "Minnie", "Nell", "Obadiah", "Opal", "Otis", "Pearl",
                             "Rufus", "Ruth", "Silas", "Sophronia", "Thaddeus", "Tobias", "Viola", "Walter", "Willa", "Zeke",
                             "Cora", "Harlan", "Iris", "Jasper", "Marian", "Nathaniel", "Rosalie", "Virgil", "Wendell"]
    // Which first names are women's (for the look: long hair, skirts).
    static let women: Set<String> = ["Ada", "Beulah", "Clara", "Delia", "Edna", "Etta", "Flora", "Hattie", "Ida", "Josephine",
                                     "Lena", "Lottie", "Mabel", "Minnie", "Nell", "Opal", "Pearl", "Ruth", "Sophronia", "Viola",
                                     "Willa", "Cora", "Iris", "Marian", "Rosalie"]
    static let surnames = ["Ashby", "Bramwell", "Calloway", "Dunmore", "Ellery", "Fairweather", "Gartside", "Hale", "Ingram",
                           "Jessup", "Kettering", "Lowell", "Merriweather", "Nash", "Oakes", "Pruitt", "Quill", "Ridley",
                           "Stroud", "Thorne", "Underhill", "Vance", "Whitlock", "Yardley", "Burke", "Coffey", "Dawes",
                           "Fenwick", "Holloway", "Merriman", "Pickett", "Rowe", "Tillman", "Wainwright"]
    static let townFirst = ["Cedar", "Copper", "Dry", "Elk", "Flint", "Gold", "Hollow", "Iron", "Juniper", "Lone", "Mill",
                            "Mesa", "Pine", "Red", "Salt", "Silver", "Stone", "Thistle", "Willow", "Wolf", "Ash", "Bitter",
                            "Clear", "Rook", "Sage"]
    static let townLast = ["Ford", "Creek", "Springs", "Bend", "Gulch", "Ridge", "Hollow", "Crossing", "Falls", "Wells",
                           "Flats", "Point", "Rock", "Junction", "Mill", "Valley", "Bluff", "Station"]

    static func pick<T>(_ a: [T], _ h: UInt64) -> T { a[Int(h % UInt64(a.count))] }
    static func mix(_ x: Int, _ z: Int, _ salt: UInt64) -> UInt64 {
        var h = UInt64(bitPattern: Int64(x)) &* 0x9E3779B97F4A7C15 ^ UInt64(bitPattern: Int64(z)) &* 0xC2B2AE3D27D4EB4F ^ salt
        h ^= h >> 31; h = h &* 0xBF58476D1CE4E5B9; h ^= h >> 29
        return h
    }

    static func townName(_ x: Int, _ z: Int, seed: UInt64) -> String {
        let h = mix(x, z, seed ^ 0x70A1)
        let a = pick(townFirst, h), b = pick(townLast, h >> 17)
        return a == b ? a + " Town" : (b == "Hollow" && a == "Hollow" ? "Hollow Rock" : "\(a) \(b)")
    }

    // The town a place belongs to: the nearest village start (its anchor names it), else the region cell.
    static func town(_ g: Game, at p: V3) -> String {
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        if let sc = g.world.gen.structures, let s = sc.nearest("village", x: x, z: z, maxRegions: 1),
           abs(s.anchor.x - x) < 200 && abs(s.anchor.z - z) < 200 {
            return townName(s.anchor.x, s.anchor.z, seed: g.world.seed)
        }
        return townName(floorDiv(x, 34 * CS), floorDiv(z, 34 * CS), seed: g.world.seed)
    }

    // Gives a villager its townsperson identity (once; the tag comes from the structure spawn, "villager:shop_saloon").
    static func setup(_ m: Mob, tag: String = "", game g: Game?) {
        var v = m.villager ?? VillagerData()
        if v.person == nil {
            let p = m.home ?? m.pos
            let h = mix(Int(floor(p.x * 4)), Int(floor(p.z * 4)), UInt64(Int(floor(p.y))) &+ 0x5EED)
            v.look = Int(h & 0xFFFF)
            v.person = "\(pick(firstNames, h >> 16)) \(pick(surnames, h >> 32))"
        }
        if tag.hasPrefix("shop_"), let k = ShopKind(rawValue: String(tag.dropFirst(5))) {
            v.shop = k.rawValue; v.role = "shopkeeper"; v.locked = true; v.profession = "none"
            let p = m.pos
            v.jobSite = [Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))]      // behind the counter
        } else if tag == "deputy" {
            v.role = "deputy"; v.locked = true; v.profession = "none"
        }
        if v.role == nil {
            if m.baby { v.role = "child" }
            else if v.profession == "farmer" { v.role = "farmer" }
            else if v.profession != "none" && v.profession != "nitwit" { v.role = "craftsman" }
            else { v.role = (v.look ?? 0) % 6 == 0 ? "elder" : "worker" }
        }
        if v.town == nil, let g { v.town = town(g, at: m.home ?? m.pos) }
        m.villager = v
    }

    static func weapon(_ v: VillagerData?, baby: Bool) -> TownWeapon {
        guard let v, !baby else { return .none }
        let look = v.look ?? 0
        switch v.role ?? "worker" {
        case "deputy": return .sword
        case "farmer": return .pitchfork
        case "elder", "child": return .none
        case "shopkeeper":
            switch v.shopKind {
            case .blacksmith?: return .hammer
            case .butcher?: return .cleaver
            case .gunsmith?: return .sword
            case .stable?: return .pitchfork
            case .doctor?, .tailor?: return .none
            default: return .axe
            }
        case "craftsman":
            return ["armorer", "toolsmith", "weaponsmith", "mason"].contains(v.profession) ? .hammer : (look % 2 == 0 ? .axe : .hoe)
        default:
            return [TownWeapon.axe, .shovel, .hoe, .pitchfork][look % 4]
        }
    }

    static func isWoman(_ v: VillagerData?) -> Bool {
        guard let n = v?.person?.split(separator: " ").first else { return false }
        return women.contains(String(n))
    }
    static func first(_ v: VillagerData) -> String { v.person.map { String($0.split(separator: " ")[0]) } ?? "Someone" }

    // MARK: Speech

    static func say(_ g: Game, _ m: Mob, _ line: String) {
        guard let v = m.villager else { return }
        g.onToast?("\(v.person ?? "Townsperson"): \(line)")
        townLastLine = g.clock
    }
    static var townLastLine: Double = -100

    static func greeting(_ v: VillagerData, _ g: Game) -> String {
        let rep = v.reputation
        let f = g.dayFraction
        let h = UInt64(v.look ?? 0) &+ UInt64(Int(g.clock / 7))
        if rep <= -60 { return pick(["You've got some nerve showing your face here.", "Keep walking.", "We don't want trouble."], h) }
        if g.raid != nil { return pick(["Get inside! They're coming!", "Grab whatever you can swing!"], h) }
        if f > 0.5 { return pick(["Late to be out.", "Mind the dark out there.", "Evening."], h) }
        var lines = f < 0.12 ? ["Morning.", "Early start, stranger?", "Fine morning."] : ["Afternoon.", "Hot one today.", "Howdy."]
        if rep >= 40 { lines += ["Good to see you again, friend.", "Always welcome here."] }
        switch v.role ?? "" {
        case "deputy": lines += ["Keep the peace and we'll get along.", "Quiet day. I like it quiet."]
        case "farmer": lines += ["Crops are coming in nice.", "Rain'd do the fields good."]
        case "shopkeeper": lines += ["Come on in, the \(v.shopKind?.name.lowercased() ?? "shop") is open.", "Take a look, I've got good stock."]
        case "elder": lines += ["When I was young this was all prairie.", "Don't let them sell you nothing you don't need."]
        case "child": lines = ["Hi!", "Are you a cowpoke?", "Watch this!"]
        default: lines += ["Work never ends.", "You new around here?"]
        }
        return pick(lines, h)
    }

    static func shopGreeting(_ v: VillagerData, _ g: Game) -> String {
        if v.reputation < -100 { return "\(first(v)): I won't serve you." }
        if v.reputation >= 40 { return "\(first(v)): Good to see you. Friends get a fair price." }
        let lines = ["What'll it be?", "Have a look around.", "Prices are fair, I promise."]
        return "\(first(v)): " + pick(lines, UInt64(v.look ?? 0) &+ UInt64(Int(g.clock)))
    }
}

extension VillagerData {
    var townRole: String { role ?? "worker" }
}

// MARK: Behaviour (called from the villager AI in Mob.swift)

extension Mob {
    var townWeapon: TownWeapon { Townsfolk.weapon(villager, baby: baby) }

    // Monsters a townsperson stands up to (creepers are run from, not fought).
    func isTownThreat(_ o: Mob) -> Bool {
        guard o.health > 0, o !== self else { return false }
        if Mob.villageThreats.contains(o.kind) { return o.kind != .witch || o.raider }
        return o.kind.hostile && !o.kind.steelhold && ![.creeper, .enderman, .ghast, .enderDragon, .wither, .warden].contains(o.kind)
            && o.spec.behavior != .crystal && o.spec.behavior != .vehicle
    }

    // Fighting: monsters near home, or the player while angry. Returns the walk speed while engaged.
    func townDefend(_ dt: Float, _ g: Game) -> Float? {
        town.swing = max(0, town.swing - dt)
        town.anger = max(0, town.anger - dt)
        guard health > 0 else { return nil }
        let w = townWeapon
        if w == .none { return nil }
        let home = self.home ?? pos
        town.think -= dt
        if town.think <= 0 {
            town.think = 0.5
            var best: Mob?
            var bd: Float = 14
            for o in g.mobs.mobs where isTownThreat(o) {
                let d = simd_length(o.pos - pos)
                if d < bd && simd_length(o.pos - home) < 40 && g.world.canSee(eye, o.eye) { bd = d; best = o }
            }
            if best != nil && town.foe == nil { g.sfx(.soldier(1, .alert), 0.8, at: eye) }
            town.foe = best
            if villager.map({ $0.reputation < -100 }) ?? false, g.alive, simd_length(g.player.pos - pos) < 10, g.survival {
                town.anger = max(town.anger, 2)
            }
        }
        if let f = town.foe, f.health <= 0 || simd_length(f.pos - home) > 44 { town.foe = nil }
        let playerFoe = town.anger > 0 && g.alive && g.survival && simd_length(g.player.pos - pos) < 24
        guard town.foe != nil || playerFoe else { return nil }
        let at = town.foe?.pos ?? g.player.pos
        let dist = simd_length(V2(at.x - pos.x, at.z - pos.z))
        face(at)
        moving = dist > w.reach * 0.8
        if attackCooldown <= 0 && dist < w.reach + (town.foe?.halfW ?? 0.3) && abs(at.y - pos.y) < 2.5 {
            attackCooldown = w.cooldown
            town.swing = 0.45
            g.sfx(.attack, 0.7, at: at)
            if let f = town.foe {
                f.hit(from: pos, damage: w.damage, knockback: 0.7)
            } else {
                g.hurtPlayer(w.damage, from: pos, cause: "was struck down by \(villager?.person ?? "a townsperson")", knockback: 0.8, attacker: self)
            }
        }
        return moving ? spec.speed * 1.35 : 0
    }

    // Reactions to the player: hands up at a pointed gun, a greeting by name, turning to look.
    func townReact(_ dt: Float, _ g: Game) -> Bool {
        town.handsUp = max(0, town.handsUp - dt)
        town.greetCooldown = max(0, town.greetCooldown - dt)
        town.aimMemory = max(0, town.aimMemory - dt)
        guard g.alive, g.menu == nil, var v = villager else { return false }
        let to = g.player.eye - eye
        let d = simd_length(to)
        guard d < 14 else { return town.handsUp > 0 }
        // A gun pointed at them (within ~4 degrees): hands up, a word, and the town remembers.
        if Guns.index(g.held.item) != nil && d > 0.5 {
            let aim = simd_dot(simd_normalize(-to), g.player.look)
            if aim > 0.9975 && g.world.canSee(g.player.eye, eye) {
                if town.handsUp <= 0 {
                    if g.clock - Townsfolk.townLastLine > 2 { Townsfolk.say(g, self, ["Easy! Easy now!", "Don't shoot!", "Put that away, mister."][Int(Rand.int(in: 0...2))]) }
                    if town.aimMemory <= 0 { v.addGossip(.minorNeg, 2); villager = v }   // once a minute per person
                    town.aimMemory = 60
                }
                town.handsUp = 2.5
            }
        }
        if town.handsUp > 0 { face(g.player.pos); return true }
        // A greeting when you come close (each person every 45 s, one voice at a time).
        if d < 4 && town.greetCooldown <= 0 && !lying && g.clock - Townsfolk.townLastLine > 6 {
            town.greetCooldown = 45
            face(g.player.pos)
            Townsfolk.say(g, self, Townsfolk.greeting(v, g))
            return false
        }
        return false
    }

    // The midday meal: the nearest saloon's counter within 64 blocks (searched every 60 s), else home.
    func townMealSpot(_ g: Game, _ dt: Float) -> V3? {
        town.mealSearch -= dt
        if town.mealSearch > 0 { return town.mealSpot }
        town.mealSearch = 60
        var best: V3?
        var bd: Float = 64
        for o in g.mobs.mobs where o.kind == .villager && o.villager?.shop == ShopKind.saloon.rawValue {
            let d = simd_length(o.pos - pos)
            if d < bd, let js = o.villager?.jobSite { bd = d; best = V3(Float(js[0]) + 0.5, Float(js[1]), Float(js[2]) + 0.5) }
        }
        town.mealSpot = best
        return best
    }
}

extension Game {
    // A townsperson attacked by the player: the victim cries out; armed folk within 24 that see it come for the
    // player for 30 s, the rest run.
    func townAlarm(_ victim: Mob) {
        guard victim.kind == .villager else { return }
        if Townsfolk.townLastLine < clock - 1.5 {
            Townsfolk.say(self, victim, ["Help! Somebody help!", "What's wrong with you?!", "Deputy!"][Rand.int(in: 0...2)])
        }
        for o in mobs.mobs where o.kind == .villager && o.health > 0 && simd_length(o.pos - victim.pos) < 24 {
            guard o === victim || simd_length(o.pos - victim.pos) < 8 || world.canSee(o.eye, victim.eye) else { continue }
            if o.townWeapon != .none { o.town.anger = max(o.town.anger, 30) } else { o.panic = max(o.panic, 8) }
        }
    }

    // Right-click on a townsperson: a shopkeeper opens the shop, a craftsperson barters as before, anyone else talks.
    func talkToTownsperson(_ m: Mob) -> Bool {
        guard m.kind == .villager else { return false }
        if m.villager?.person == nil { Townsfolk.setup(m, game: self) }
        guard let v = m.villager else { return false }
        if m.town.anger > 0 { Townsfolk.say(self, m, "Stay back!"); return true }
        if m.lying {
            onToast?("\(v.person ?? "They") is asleep.")
            return true
        }
        if !m.baby, let k = v.shopKind {
            let f = Float(dayFraction)
            let (a, b) = k.hours
            if f < a || f > b {
                Townsfolk.say(self, m, "We're closed. Come back \(f > 0.5 ? "in the morning" : "a little later").")
                return true
            }
            openMenu(ShopMenu(game: self, keeper: m, kind: k))
            return true
        }
        if !m.baby && v.profession != "none" && v.profession != "nitwit" { return openTrading(m) }
        m.face(player.pos)
        Townsfolk.say(self, m, Townsfolk.greeting(v, self))
        return true
    }
}
