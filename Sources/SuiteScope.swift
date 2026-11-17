import Foundation

// Job 6 (after ledger 218-220): a suite group that leaves ships, mobs, trains, pending mobs, a later time of day or a
// seeded random stream behind moves every group after it: the guard in questcheck's leaves() named nine. A group
// takes a scope when it starts and puts it back when it ends:
//     let scope = SuiteScope(g); defer { scope.putBack(g) }
// What the group added goes (by identity, never by place in a list); what it took away of what was there comes back.
final class SuiteScope {
    private let ships: [Ship]
    private let mobs: [Mob]
    private let pending: [(String, V3)]
    private let trains: [Int64: Trains.Train]
    private let carOf: [ObjectIdentifier: (Trains.Train, Int)]
    private let saved: [Int64: Trains.SavedTrain]
    private let time: Double
    private let rand: (deterministic: Bool, state: UInt64)

    init(_ g: Game) {
        ships = g.world.ships.list
        mobs = g.mobs.mobs
        pending = g.world.pendingMobs
        trains = Trains.trains; carOf = Trains.carOf; saved = Trains.saved
        time = g.time
        rand = Rand.snapshot
    }

    func putBack(_ g: Game) {
        // Trains first: taking one away takes its cars and riders out of the mobs.
        for (id, tr) in Trains.trains where trains[id] !== tr { Trains.remove(g, tr) }
        Trains.trains = trains; Trains.carOf = carOf; Trains.saved = saved
        let ms = g.world.ships
        let had = Set(ships.map { ObjectIdentifier($0) })
        while let s = ms.list.first(where: { !had.contains(ObjectIdentifier($0)) }) { ms.remove(s) }
        let has = Set(ms.list.map { ObjectIdentifier($0) })
        for s in ships where !has.contains(ObjectIdentifier(s)) { ms.add(s) }
        let hadMobs = Set(mobs.map { ObjectIdentifier($0) })
        g.mobs.mobs.removeAll { !hadMobs.contains(ObjectIdentifier($0)) }
        let hasMobs = Set(g.mobs.mobs.map { ObjectIdentifier($0) })
        let back = mobs.filter { !hasMobs.contains(ObjectIdentifier($0)) }
        g.mobs.mobs.append(contentsOf: back)
        g.world.pendingMobs = pending
        g.time = time
        Rand.snapshot = rand
    }
}
