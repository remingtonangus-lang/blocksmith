import Foundation
import simd

// D26: named gang leaders with hideouts. Every outlaw camp (WildCamps camp_outlaws) is the hideout of one of eight
// named gangs, picked by the camp's place. Ride within 56 blocks of a hideout whose boss is still at large and he is
// there with two more of his gang (once; they're saved with the ground after that). He's tougher than a camp guard
// (twice the health, a gunman or a brawler by gang) and has a price on his head:
//   killed by you      the bounty is paid on the spot and his gang breaks and runs
//   hogtied alive      (lasso, then use him: Jail.hogtie) double the bounty
// Notice boards post the nearest leader still at large ("WANTED: ..., hides out N blocks north-east").
// A beaten leader is remembered (TownLaw.state.gangsBeaten); his camp can then be freed as before (Liberation).
enum GangLeaders {
    struct Gang { let leader: String; let gang: String; let bounty: Int; let gunman: Bool }
    static let all: [Gang] = [
        Gang(leader: "Coyote Varga", gang: "the Varga Boys", bounty: 4500, gunman: true),
        Gang(leader: "Widow Tolliver", gang: "the Tolliver Ring", bounty: 5000, gunman: true),
        Gang(leader: "Deacon Crane", gang: "the Crane Brethren", bounty: 4000, gunman: false),
        Gang(leader: "Two-Bit Morrow", gang: "the Morrow Gang", bounty: 3500, gunman: false),
        Gang(leader: "Iron Kate Pike", gang: "the Pike Riders", bounty: 5500, gunman: true),
        Gang(leader: "Smiling Jim Kincaid", gang: "the Kincaid Outfit", bounty: 6000, gunman: true),
        Gang(leader: "Hollis Stokes", gang: "the Dry Creek Bunch", bounty: 4000, gunman: false),
        Gang(leader: "Ma Haskell", gang: "the Haskell Clan", bounty: 6500, gunman: true),
    ]
    static let showUp: Float = 56
    static var spawnedHere = Set<IVec3>()           // camps whose gang turned up this session (also saved: gangsMet)
    static var beatenCount = 0                      // (harness)

    static func gang(at a: IVec3) -> Gang {
        var h: UInt64 = 0x9E3779B97F4A7C15
        for v in [a.x, a.z] { h = (h ^ UInt64(bitPattern: Int64(v))) &* 0x100000001B3 }
        return all[Int((h >> 29) % UInt64(all.count))]
    }

    static func beaten(_ leader: String) -> Bool { TownLaw.state.gangsBeaten?.contains(leader) ?? false }
    static func isLeader(_ m: Mob) -> Gang? {
        guard m.posse == 2, let n = m.customName else { return nil }
        return all.first { $0.leader == n }
    }
    static func key(_ a: IVec3) -> String { "\(a.x),\(a.z)" }

    // Once a second (TownLaw.tick): the gang turns up at its hideout.
    static func tick(_ g: Game) {
        guard g.dim.dim == .overworld, g.survival, g.difficulty > 0 else { return }
        let p = g.player.pos
        for s in Liberation.outlawCamps(g, near: p) {
            let a = s.anchor
            let gg = gang(at: a)
            let c = V3(Float(a.x) + 0.5, Float(a.y), Float(a.z) + 0.5)
            guard simd_length(V2(p.x - c.x, p.z - c.z)) < showUp, !beaten(gg.leader), !spawnedHere.contains(a),
                  !(TownLaw.state.gangsMet?.contains(key(a)) ?? false), !Liberation.freed(a.x, a.z),
                  g.world.isLoaded(a.x, a.z) else { continue }
            spawnedHere.insert(a)
            var met = TownLaw.state.gangsMet ?? []; met.append(key(a)); TownLaw.state.gangsMet = met
            let y = Float(g.world.topY(a.x, a.z) + 1)
            let boss = Mob(gg.gunman ? .pillager : .vindicator, at: g.world.freeSpawn(V3(c.x + 1, y, c.z - 1)))
            boss.customName = gg.leader; boss.persistent = true; boss.posse = 2
            boss.health = boss.spec.health * 2
            g.mobs.mobs.append(boss)
            for (i, off) in [V3(-3, 0, 2), V3(3, 0, 3)].enumerated() {
                let m = Mob(i == 0 ? .pillager : .vindicator, at: g.world.freeSpawn(V3(c.x + off.x, y, c.z + off.z)))
                m.customName = gg.gang.prefix(4) == "the " ? String(gg.gang.dropFirst(4)).capitalizedFirst : gg.gang
                m.persistent = true; m.posse = 2
                g.mobs.mobs.append(m)
            }
            g.onToast?("This is the hideout of \(gg.leader) and \(gg.gang). Bounty \(Money.format(gg.bounty)).")
        }
    }

    // TownBoard.mobDied: the boss killed by the player.
    static func mobDied(_ g: Game, _ m: Mob) {
        guard let gg = isLeader(m), m.killedByPlayer, g.survival, !beaten(gg.leader) else { return }
        settle(g, gg, at: m.pos, alive: false)
    }

    // Jail.hogtie: the boss roped and tied.
    static func captured(_ g: Game, _ m: Mob) -> Bool {
        guard let gg = isLeader(m), !beaten(gg.leader) else { return false }
        g.mobs.mobs.removeAll { $0 === m }
        settle(g, gg, at: m.pos, alive: true)
        return true
    }

    static func settle(_ g: Game, _ gg: Gang, at p: V3, alive: Bool) {
        var b = TownLaw.state.gangsBeaten ?? []; b.append(gg.leader); TownLaw.state.gangsBeaten = b
        beatenCount += 1
        let pay = alive ? gg.bounty * 2 : gg.bounty
        g.money += pay
        for o in g.mobs.mobs where o.posse == 2 && simd_length(o.pos - p) < 40 && isLeader(o) == nil {
            o.aggro = false; o.panic = max(o.panic, 12)
        }
        for (k, n) in [("gold_ingot", 2), ("emerald", 3)] where Items.has(k) { g.drops.spawn(ItemStack(Items.id(k), n), at: p + V3(0, 0.5, 0)) }
        g.sfx(.levelUp, 0.8)
        Honour.earn(g, alive ? 4 : 3, source: "outlaw", alive ? "\(gg.leader) taken alive" : "\(gg.leader) brought down")
        g.onToast?(alive ? "\(gg.leader) hogtied and handed to the law: +\(Money.format(pay)). \(gg.gang.capitalizedFirst) is finished."
                         : "\(gg.leader) is dead: +\(Money.format(pay)). \(gg.gang.capitalizedFirst) scatters.")
    }

    // The notice board line: the nearest leader still at large from this board (nil: none known nearby).
    static func wanted(_ g: Game, from a: IVec3) -> (Gang, Int, String)? {
        guard g.dim.dim == .overworld, let sc = g.world.gen.structures else { return nil }
        guard let s = sc.nearest("wild_camp", x: a.x, z: a.z, maxRegions: 3, accept: {
            $0.kind == "camp_outlaws" && !beaten(gang(at: $0.anchor).leader) && !Liberation.freed($0.anchor.x, $0.anchor.z)
        }) else { return nil }
        let dx = Float(s.anchor.x - a.x), dz = Float(s.anchor.z - a.z)
        return (gang(at: s.anchor), Int(hypotf(dx, dz)), TownBoard.direction(dx, dz))
    }
}
