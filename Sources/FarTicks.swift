import Foundation
import simd

// P376 step 1 (P375 step 2): nothing ticks past the active distance. Every per-thing update (mobs, dropped items,
// projectiles, lit blocks, fluids, fire, campfires, falling cells, debris, ships) asks `World.activeHere` first and
// skips a thing that is past it; what a skipped thing would have done waits (fluid and falling cells are parked and
// handed back once the player comes near; campfires catch up from the clock). `FarTicks.note` is called inside each
// update body, after that check: anything that still ran past the active distance is counted, and the stats line shows
// the last second's count ("far ticking N"), which must read 0.
enum FarTicks {
    static var counting = 0             // this second
    static var lastSecond = 0           // shown on the stats line
    static var total = 0                // (harness)
    static var shipAwakeFar = 0         // ships stepped past it (only one being steered can be)
    private static var stamp = 0.0
    @inline(__always) static func note(_ w: World, _ p: V3) {
        if !w.activeHere(p) { counting += 1; total += 1 }
    }
    static func noteShips() { counting += shipAwakeFar; total += shipAwakeFar; shipAwakeFar = 0 }
    static func roll(clock: Double) {
        noteShips()
        guard clock - stamp >= 1 else { return }
        stamp = clock; lastSecond = counting; counting = 0
    }
}

extension World {
    // Inside the active distance of the player (or of a second co-op player).
    @inline(__always) func activeHere(_ q: V3) -> Bool {
        if isActive(q, from: activeCenter) { return true }
        if let e = extraCenter, isActive(q, from: e) { return true }
        return !hotZones.isEmpty && hot(q)
    }
    // (Remington, Oct 30 20:28-20:29, the frigate's gun on a Capital city: "I should be able to blow that thing to
    // smithereens. Whole thing should just fall too because of physics"; then, flown over to it, "gravity does work...
    // just doesn't work all the time"): a big gun's shot strikes well past the active distance, where nothing ticks,
    // so what it cut loose waited for him to come near (load checks, falling blocks and a toppled tower parked, frozen).
    // Round such a strike the world runs as if he were there for a while (heat): load checks, what falls, fire and
    // fluid, the soldiers there, the toppled piece's fall (ShipManager: a body in a hot zone stays awake). Its chunks
    // keep their blocks as long (World.dataReady holds them).
    func hot(_ q: V3) -> Bool {
        for z in hotZones where abs(q.x - z.center.x) <= z.r && abs(q.z - z.center.z) <= z.r { return true }
        return false
    }
    func heat(at p: V3, radius: Float, seconds: Double) {
        let until = CFAbsoluteTimeGetCurrent() + seconds
        hotZones.append((center: p, r: radius, until: until))
    }
    func coolZones() {
        guard !hotZones.isEmpty else { return }
        let now = CFAbsoluteTimeGetCurrent()
        hotZones.removeAll { now > $0.until }
    }
    @inline(__always) func activeHere(_ c: IVec3) -> Bool { activeHere(V3(Float(c.x) + 0.5, Float(c.y), Float(c.z) + 0.5)) }

    // Fluid and falling cells reached past the active distance wait here, by chunk, until it comes near again.
    func park(fluid p: IVec3, lava: Bool) {
        parked[ChunkKey(x: floorDiv(p.x, CS), z: floorDiv(p.z, CS)), default: []].append((p, lava ? 2 : 1))
    }
    func park(falling p: IVec3) {
        parked[ChunkKey(x: floorDiv(p.x, CS), z: floorDiv(p.z, CS)), default: []].append((p, 0))
    }
    // P430 (b): a load check for a piece past the active distance (a mast shelled from a gun a long way off) waits too.
    func park(load p: IVec3) {
        parked[ChunkKey(x: floorDiv(p.x, CS), z: floorDiv(p.z, CS)), default: []].append((p, 3))
    }
    // Once a second: parked cells whose chunk is active again go back to their queues; unloaded chunks drop theirs
    // (a loaded chunk re-queues its own springs and loose cells).
    func unparkActive() {
        coolZones()
        guard !parked.isEmpty else { return }
        for (k, cells) in parked {
            if chunks[k] == nil { parked.removeValue(forKey: k); continue }
            let c = V3(Float(k.x * CS + CS / 2), 0, Float(k.z * CS + CS / 2))
            guard activeHere(c) else { continue }
            parked.removeValue(forKey: k)
            for (p, kind) in cells {
                if kind == 0 { gravityQueue.append(p) } else if kind == 2 { lavaPending.insert(p) }
                else if kind == 3 { if loadQueued.insert(IVec3(floorDiv(p.x, 4), floorDiv(p.y, 4), floorDiv(p.z, 4))).inserted { loadQueue.append(p) } }
                else { fluidPending.insert(p) }
            }
        }
    }
}
