import Foundation
import simd

// D30: late-game money sinks tied to the spine. Every gunsmith keeps a quartermaster's book (ShopService.quartermaster)
// of big-ticket orders that open up as you walk the spine (Goals.next's stage: 0 iron, 1 a town, 2 Greywall, 3 the
// fleet, 4 hell, 5 the Capital):
//   a town taken      Hired gun          a seasoned gunhand joins you as a companion (Companions.swift)
//                     Fortify homestead  a stone wall with a gate round your homestead (Property.swift)
//   Greywall          Field Tank kit     the whole Vehicle Works bill (and the Works) in a crate
//   the fleet         Gun crew           companions up to the full three
//   hell              Hell-proof kit     four fire-resistance tonics and a stack of golden carrots
//   the Capital       Siege kit          a second Field Tank kit and a crew
enum Quartermaster {
    struct Offer { let name: String; let detail: String; let stage: Int; let price: Int }
    static let offers: [Offer] = [
        Offer(name: "Hired Gun", detail: "A seasoned gunhand rides with you", stage: 1, price: 9000),
        Offer(name: "Fortify Homestead", detail: "A stone wall and gate round it", stage: 1, price: 30000),
        Offer(name: "Field Tank Kit", detail: "The whole Vehicle Works bill, crated", stage: 2, price: 45000),
        Offer(name: "Gun Crew", detail: "Gunhands up to a full crew of three", stage: 3, price: 24000),
        Offer(name: "Hell-Proof Kit", detail: "Fire tonics and golden carrots", stage: 4, price: 20000),
        Offer(name: "Siege Kit", detail: "A tank kit and a full crew", stage: 5, price: 60000),
    ]
    static var bought = 0                                // (harness)

    static func stage(_ g: Game) -> Int { Goals.next(g)?.stage ?? 6 }

    static func buy(_ g: Game, _ i: Int) -> (String, Bool) {
        let o = offers[i]
        guard stage(g) >= o.stage else { return ("That order opens at \"\(Spine.stages[o.stage])\".", false) }
        guard g.money >= o.price else { return ("That's \(Money.format(o.price)). You have \(Money.format(g.money)).", false) }
        let r: (String, Bool)
        switch i {
        case 0: r = hire(g, 1)
        case 1: r = fortify(g)
        case 2: r = give(g, tankKit)
        case 3: r = hire(g, Companions.max)
        case 4: r = give(g, [("potion_fire_resistance", 4), ("golden_carrot", 16)])
        default:
            let k = give(g, tankKit)
            r = k.1 ? (hire(g, Companions.max).1 ? ("Tank kit crated and the crew's mounted up.", true) : k) : k
        }
        if r.1 { g.money -= o.price; bought += 1; g.sfx(.villagerTrade, 0.7) }
        return r
    }

    static var tankKit: [(String, Int)] { VehicleWorks.bill + [(VehicleWorks.key, 1)] }

    static func give(_ g: Game, _ list: [(String, Int)]) -> (String, Bool) {
        for (k, n0) in list where Items.has(k) {
            var n = n0
            while n > 0 {
                let part = min(n, ItemStack(Items.id(k), 1).maxStack)
                let rest = g.inventory.add(ItemStack(Items.id(k), part)); if !rest.isEmpty { g.dropItem(rest) }
                n -= part
            }
        }
        return ("Delivered. What doesn't fit in your pack is at your feet.", true)
    }

    // Gunhands until there are `upTo` companions (at least one, or none and a refusal).
    static func hire(_ g: Game, _ upTo: Int) -> (String, Bool) {
        let room = min(Companions.max, upTo) - g.companions.count
        guard room > 0 || (upTo == 1 && g.companions.count < Companions.max) else { return ("You already lead a full crew.", false) }
        let names = ["Wade Ellery", "June Bascom", "Tom Raskin", "Nell Corrigan", "Abe Thorne", "Lottie Shaw"]
        for i in 0..<max(1, room) {
            let p = g.world.freeSpawn(g.player.pos + V3(Float(i) * 1.5 - 1.5, 0, 2))
            let c = Mob(.soldierRecruit, at: p)
            c.variant = Guns.rifle
            c.faction = Faction.none.rawValue
            c.hired = true; c.persistent = true; c.aggro = false
            c.customName = names[(g.companions.count + Int(g.clock)) % names.count]
            if c.troop < 0 { c.troop = 0 }
            g.mobs.mobs.append(c)
            c.soldierBrain.mag = Guns.all[c.soldierBrain.gun].mag
        }
        return (room > 1 ? "\(room) gunhands ride with you now." : "A gunhand rides with you now.", true)
    }

    // A wall of stone bricks three high round the homestead you stand in, a gate on its north side.
    static func fortify(_ g: Game) -> (String, Bool) {
        let p = IVec3(Int(floor(g.player.pos.x)), Int(floor(g.player.pos.y)), Int(floor(g.player.pos.z)))
        guard let b = (TownLaw.state.property ?? []).first(where: { $0.count == 6 && $0[3] - $0[0] == 24
                && p.x >= $0[0] && p.x <= $0[3] && p.z >= $0[2] && p.z <= $0[5] }) else {
            return ("Stand on your homestead to order its walls.", false)
        }
        let cx = (b[0] + b[3]) / 2, cz = (b[2] + b[5]) / 2, r = 10
        let wall = Blocks.has("stone_bricks") ? Blocks.id("stone_bricks") : Blocks.id("cobblestone")
        let gate = Blocks.has("oak_fence_gate") ? Blocks.id("oak_fence_gate") : AIR
        for i in -r...r { for (x, z) in [(cx + i, cz - r), (cx + i, cz + r), (cx - r, cz + i), (cx + r, cz + i)] {
            guard g.world.isLoaded(x, z) else { continue }
            let y = g.world.topY(x, z) + 1
            let isGate = z == cz - r && abs(x - cx) <= 1
            for dy in 0..<3 { g.world.setBlock(x, y + dy, z, isGate ? (dy == 0 ? gate : AIR) : wall) }
        } }
        return ("The masons are done: your homestead has its walls.", true)
    }
}

final class QuartermasterMenu: ListMenu {
    init(game g: Game) {
        super.init("Quartermaster", game: g)
        subtitle = "Big orders for the long road"
    }
    override var rows: [Row] {
        corner = "Wallet " + Money.format(game.money)
        let st = Quartermaster.stage(game)
        return Quartermaster.offers.map { o in
            let open = st >= o.stage
            return Row(name: o.name, detail: open ? o.detail : "Opens at: \(Spine.stages[o.stage])", value: Money.format(o.price),
                       enabled: open && game.money >= o.price, good: open)
        }
    }
    override func pressed(_ i: Int) {
        guard i < Quartermaster.offers.count else { return }
        let r = Quartermaster.buy(game, i)
        say(r.0, good: r.1)
    }
}
