import Foundation
import simd

// Outposts and liberation (backlog O1). The outlaw camps (WildCamps camp_outlaws) are the small enemy camps on the map:
//   clearing   once no hostile is left within 24 blocks of a camp's centre while a player stands in it (12 blocks),
//              the camp is freed: a toast, a reward of $25, and the camp goes on the map as a freed camp ("O",
//              saved with the map marks, which is also what remembers it).
//   shop       a general store keeper sets up at the freed camp (a persistent villager with the general store's
//              stock, Shops.swift).
//   travel     a freed camp's campfire is a fast-travel post: using its fire offers the next other freed camp
//              ("use the fire again to travel"); using it again within 6 s goes there. The trip's time passes at a
//              rider's pace. Offers rotate through every freed camp, nearest first.
enum Liberation {
    static let kind = "camp_freed"
    static let campRadius: Float = 12
    static let clearRadius: Float = 24
    static let reward = 2500                // cents
    static let travelSpeed: Double = 8      // blocks a second (a rider), for the time the trip takes
    static var freedCount = 0               // (harness)

    struct Offer { var x: Int; var z: Int; var at: Double; var from: IVec3; var index: Int }
    static var offer: Offer?
    static var lastScan: Double = -10

    // The outlaw camp starts near a point (centre = anchor).
    static func outlawCamps(_ g: Game, near p: V3) -> [StructureStart] {
        guard let sc = g.world.gen.structures, let t = sc.types.first(where: { $0.name == "wild_camp" }) else { return [] }
        return sc.startsNear(cx: floorDiv(Int(floor(p.x)), CS), cz: floorDiv(Int(floor(p.z)), CS), t).filter { $0.kind == "camp_outlaws" }
    }

    static func freed(_ x: Int, _ z: Int) -> Bool {
        MapCache.shared.marks.contains { $0.kind == kind && abs($0.x - x) < 4 && abs($0.z - z) < 4 }
    }

    static func freedCamps() -> [MapCache.Mark] { MapCache.shared.marks.filter { $0.kind == kind } }
}

extension Game {
    // Once a second (MapCache.tick's pace, from the HUD tick): free the camp a player stands in once it is clear.
    func liberationTick() {
        guard dim.dim == .overworld, survival, clock - Liberation.lastScan >= 1 else { return }
        Liberation.lastScan = clock
        for i in 0..<max(1, coop.seatCount) {
            let pp = coop.seatPlayer(i, self).pos
            for s in Liberation.outlawCamps(self, near: pp) {
                let c = V3(Float(s.anchor.x) + 0.5, Float(s.anchor.y), Float(s.anchor.z) + 0.5)
                guard simd_length(V2(pp.x - c.x, pp.z - c.z)) < Liberation.campRadius, abs(pp.y - c.y) < 12,
                      !Liberation.freed(s.anchor.x, s.anchor.z) else { continue }
                let left = mobs.mobs.contains { $0.health > 0 && $0.kind.hostile && simd_length($0.pos - c) < Liberation.clearRadius }
                if left { continue }
                freeCamp(s.anchor, centre: c)
            }
        }
    }

    func freeCamp(_ a: IVec3, centre c: V3) {
        Liberation.freedCount += 1
        MapCache.shared.discover(self, kind: Liberation.kind, x: a.x, z: a.z, name: "Freed camp")
        money += Liberation.reward
        sfx(.levelUp, 0.8)
        // The general store keeper sets up by the fire.
        if let m = Mob.structureMob("villager:shop_\(ShopKind.general.rawValue)", at: c + V3(3, 0, -3)) {
            m.persistent = true
            mobs.mobs.append(m)
        }
        onToast?("Camp freed! +\(Money.format(Liberation.reward)). A trader sets up here, and its fire is now a fast-travel post.")
    }

    // A lit campfire used with an empty hand (or anything that is not a block): at a freed camp it offers, then makes,
    // the trip to the next freed camp. Returns true when it handled the use.
    func campTravelUse(_ fire: IVec3) -> Bool {
        let here = Liberation.freedCamps().filter { abs($0.x - fire.x) <= Int(Liberation.campRadius) && abs($0.z - fire.z) <= Int(Liberation.campRadius) }
        guard let home = here.first else { return false }
        let others = Liberation.freedCamps().filter { $0 != home }
            .sorted { hypotf(Float($0.x - home.x), Float($0.z - home.z)) < hypotf(Float($1.x - home.x), Float($1.z - home.z)) }
        guard !others.isEmpty else {
            onToast?("A freed camp. Free another outlaw camp to travel between them from its fire.")
            return false                                       // (then it rests you by the fire as before)
        }
        if let o = Liberation.offer, o.from == fire, clock - o.at < 6, others.contains(where: { $0.x == o.x && $0.z == o.z }) {
            Liberation.offer = nil
            let d = hypotf(Float(o.x - home.x), Float(o.z - home.z))
            if riding != nil { dismount() }
            time += Double(d) / Liberation.travelSpeed                         // the ride's time passes (as a train trip's)
            // The camp's ground: its column top when loaded, else the height the generator gives it.
            let top = world.topY(o.x + 2, o.z + 2)
            let y = Float(top > 0 ? top + 1 : world.gen.column(o.x + 2, o.z + 2).height + 1)
            player.pos = V3(Float(o.x + 2) + 0.5, y, Float(o.z + 2) + 0.5)
            player.vel = .zero
            player.airPeak = player.pos.y
            sfx(.mob(.horse, .ambient), 0.6)
            onToast?("You ride to the freed camp \(Int(d)) blocks \(TownBoard.direction(Float(o.x - home.x), Float(o.z - home.z))).")
            return true
        }
        let k = Liberation.offer.map { $0.from == fire ? ($0.index + 1) % others.count : 0 } ?? 0
        let o = others[k]
        Liberation.offer = Liberation.Offer(x: o.x, z: o.z, at: clock, from: fire, index: k)
        let d = Int(hypotf(Float(o.x - home.x), Float(o.z - home.z)))
        onToast?("Fast travel (\(k + 1) of \(others.count)): the freed camp \(d) blocks \(TownBoard.direction(Float(o.x - home.x), Float(o.z - home.z))). Use the fire again to go.")
        return true
    }
}
