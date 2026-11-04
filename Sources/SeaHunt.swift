import Foundation
import simd

// P508 (Nov 1 16:08:54-16:09:46, out on the water: "if you're in the water... There's a chance every five minutes that
// a pirate ship spawns, with cans [cannons] on it, and make it an eighth of a chance that [a] cruiser spawns, like a
// modern one... If the cruiser spawns, you're fucked... make it so that the cruiser is so vicious that you have to go
// underwater to escape"). Out at sea (open water under him for 20 blocks round, in a boat, a vessel or swimming) every
// five minutes is a roll: one in eight a Corsair Cruiser (the destroyer's hull, the corsairs' colours, a volley every
// two seconds out to 160 blocks), three in eight a corsair sloop; either comes in from 150 blocks off and hunts him
// (it steers for him, not the shore, and lands nobody). The guns lose him only under the water: head two blocks down,
// or sunk in a submarine. Out of reach (400 blocks) or ashore for a minute, the hunter sails off. One at a time; not
// in creative, on peaceful or at peace.
enum SeaHunt {
    static let every: Double = 300
    static let cruiserName = "Corsair Cruiser"
    static let reach: Float = 160, leave: Float = 400
    static var hunters: Set<Int> = []
    static var atSea: Double = 0                       // seconds out at sea since the last roll
    static var ashore: Double = 0
    static var rolls = 0, sloops = 0, cruisers = 0      // (harness)
    static func isHunter(_ s: Ship) -> Bool { hunters.contains(s.id) }
    static func cruiser(_ s: Ship) -> Bool { hunters.contains(s.id) && s.role == NavalPatrol.role }

    // Open water under him (20 blocks round).
    static func atSea(_ g: Game) -> Bool {
        let p = g.player.pos
        for (dx, dz) in [(0, 0), (20, 0), (-20, 0), (0, 20), (0, -20)] {
            if Submarine.surface(g.world, Int(floor(p.x)) + dx, Int(floor(p.z)) + dz) == nil { return false }
        }
        return true
    }

    // Hidden from the guns: his head two blocks under the surface.
    static func under(_ g: Game) -> Bool {
        guard g.player.headInWater else { return false }
        let e = g.player.eye
        let x = Int(floor(e.x)), z = Int(floor(e.z))
        var y = Int(floor(e.y))
        var depth = 0
        while depth < 3 && Blocks.fluidKind[Int(g.world.builtBlock(x, y + 1, z))] == 1 { depth += 1; y += 1 }
        return depth >= 2
    }
}

extension Game {
    // Every tick, from corsairsTick.
    func seaHuntTick(_ dt: Float) {
        let ships = world.ships
        // The hunters: steer for him, sail off when he's gone.
        for s in ships.list where SeaHunt.isHunter(s) && s.parent == nil {
            if s.captured || s.wrecked { SeaHunt.hunters.remove(s.id); continue }
            let d = simd_length(V2(s.pos.x - player.pos.x, s.pos.z - player.pos.z))
            if d > SeaHunt.leave || SeaHunt.ashore > 60 || !alive {
                SeaHunt.hunters.remove(s.id)
                ships.remove(s)
                continue
            }
            s.home = player.pos
            Corsairs.landed.insert(s.id)                     // (a hunting sloop puts no party ashore)
        }
        SeaHunt.hunters = SeaHunt.hunters.filter { id in ships.list.contains { $0.id == id } }
        guard dim.dim == .overworld, survival, difficulty > 0, alive, !Reckoning.won else { return }
        // Once a second: out at sea or ashore?
        if Int(clock) != Int(clock - Double(dt)) {
            if SeaHunt.atSea(self) { SeaHunt.atSea += 1; SeaHunt.ashore = 0 } else { SeaHunt.ashore += 1 }
        }
        guard SeaHunt.hunters.isEmpty, SeaHunt.atSea >= SeaHunt.every else { return }
        SeaHunt.atSea = 0
        SeaHunt.rolls += 1
        let r = Rand.float(in: 0..<1)
        guard r < 0.5 else { return }
        let cruiser = r < 0.125
        // In from 150 blocks off, over open water.
        let p = player.pos
        let a0 = Rand.float(in: 0..<(2 * .pi))
        for k in 0..<12 {
            let a = a0 + Float(k) * .pi / 6
            let x = Int(floor(p.x + cosf(a) * 150)), z = Int(floor(p.z + sinf(a) * 150))
            // (open water all round where it comes in: a sloop made against a reef or a shore lost its gun and lay there)
            guard world.isLoaded(x, z), let y = Submarine.surface(world, x, z),
                  [(14, 0), (-14, 0), (0, 14), (0, -14)].allSatisfy({ world.isLoaded(x + $0.0, z + $0.1) && Submarine.surface(world, x + $0.0, z + $0.1) != nil })
            else { continue }
            let yaw = atan2f(cosf(a), sinf(a))                       // bow (-Z) toward him
            let s = ships.spawnVessel(cruiser ? NavalPatrol.role : "sloop", home: IVec3(x, y + 1, z), game: self, yaw: yaw)
            s.home = p
            SeaHunt.hunters.insert(s.id)
            Corsairs.landed.insert(s.id)
            if cruiser {
                s.name = SeaHunt.cruiserName
                for m in mobs.mobs where m.deck === s { Corsairs.dress(m) }
                SeaHunt.cruisers += 1
                onToast?("A Corsair Cruiser is bearing down on you")
            } else {
                SeaHunt.sloops += 1
                onToast?("Corsair sails on the horizon: they've seen you")
            }
            sfx(.bell, 0.8, at: p)
            return
        }
    }
}
