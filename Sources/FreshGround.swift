import Foundation

// Y5 (backlog, Remington: "saved worlds get new content in unexplored ground: roads, base towns, railways, Greywall and
// wide streets currently skip old worlds, so his world never shows them"). Most of those guards already work chunk by
// chunk (Greywall bases: legacyGreywall within 4 chunks of the site; the garrison row by a citadel: legacyP44 by its
// lots; wide streets: legacyFrontier/TownsGap/C13/R20 within 7-8 chunks of the town), so a town or base out in
// unexplored ground of an old save gets them. Two were all-or-nothing over long distances:
//   roads     a road between two towns (up to 720 blocks) was dropped whole if any of it came near ground saved before
//             P44. Now it is drawn wherever its chunks are generated fresh (Roads.segment); roads are drawn only into a
//             chunk being generated, so saved ground is never cut through: the road stops at its edge.
//   railways  a line across up to six towns (3,000+ blocks) was dropped whole if any of it came near ground saved before
//             C1. A line the old rule drops is now planned again from its runs that keep 3 chunks clear of every
//             chunk saved before Y5 (this file's guard; Railways.plan). The guard has to be the chunks saved before this
//             rule, not before C1: ground explored between C1 and now was generated with no line there.
// The guard (structure-guard-y5.txt) is taken once per save like the others (SaveManager.structureGuard), when its
// overworld is opened (World.init calls FreshGround.load). Without it (harness worlds with no save) the old rules hold.
enum FreshGround {
    static let file = "structure-guard-y5.txt"
    static var on = true                         // (the host checks can turn the new rules off to compare)

    private struct Entry { weak var sc: StructureCache?; let set: Set<Int64> }
    private static let lock = NSLock()
    private static var guards: [Entry] = []      // (NSMapTable isn't in Linux Foundation; a world or two at a time)

    // The chunks the save had generated before Y5, for that world's structures (World.init, before any chunk is made).
    static func load(_ sc: StructureCache, _ save: SaveManager?) {
        guard let save else { return }
        set(sc, save.structureGuard(file: file))
    }
    static func set(_ sc: StructureCache, _ s: Set<Int64>?) {
        lock.lock(); defer { lock.unlock() }
        guards.removeAll { $0.sc == nil || $0.sc === sc }
        if let s { guards.append(Entry(sc: sc, set: s)) }
    }
    // nil: no guard was taken for these structures (the old rules apply).
    static func guardSet(_ sc: StructureCache) -> Set<Int64>? {
        guard on else { return nil }
        lock.lock(); defer { lock.unlock() }
        return guards.first { $0.sc === sc }?.set
    }
}
