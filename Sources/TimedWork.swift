import Foundation

// P127 (Oct 12 PM): "If you sleep overnight, make it so anything in your furnaces gets finished. Same thing if you
// leave and come back, just like game time, how long it's been in there." Furnaces, smokers, blast furnaces, brewing
// stands and campfires remember the game time they last ran (BlockEntity.last, saved). When one runs again after a gap
// (a night slept through, a trip to another dimension, its chunk out of reach) it first runs the game ticks it missed,
// stopping early once nothing is left to do.
extension BlockEntity {
    static let maxCatchUp = 20 * 60 * 60 * 2          // two hours of game ticks at most in one go

    // The 20 Hz ticks missed since the last run at game time `now` (and the clock moved on to `now`).
    func missedTicks(_ now: Double) -> Int {
        defer { last = now }
        guard last > 0, now - last > 0.15 else { return 0 }
        return min(Int((now - last) / 0.05) - 1, BlockEntity.maxCatchUp)
    }

    // Runs up to `n` furnace ticks; returns the ticks actually run.
    @discardableResult func catchUpFurnace(_ n: Int) -> Int {
        var k = 0
        while k < n {
            _ = tickFurnace(); k += 1
            if burn <= 0 && cook == 0 { break }       // out of fuel or out of work
        }
        return k
    }

    @discardableResult func catchUpBrewing(_ n: Int) -> Int {
        var k = 0
        while k < n {
            let done = tickBrewing(); k += 1
            if brewTime == 0 && !done { break }
        }
        return k
    }

    func catchUpCampfire(_ n: Int) {
        for i in 0..<4 where !container[i].isEmpty { cooks[i] -= n }
    }
}

extension World {
    // P128: the hinge bit (16) to toggle as door state `st` at `p` opens: 16 when its panel would swing toward a
    // neighbouring door of the same facing (the middle of a double door), else 0. Closing keeps the hinge.
    func doorHingeFlip(_ p: IVec3, _ st: Int) -> Int {
        guard st & 4 == 0, st < 32 else { return 0 }
        let n = p + BlockRegistry.sideDir[BlockRegistry.doorSide(st | 4)]
        let nb = block(n.x, n.y, n.z)
        guard Blocks.shape[Int(nb)] == "door" else { return 0 }
        return Int(nb - Blocks.groupBase[Int(nb)]) & 3 == st & 3 ? 16 : 0
    }
}

// P130: steady digging. The pause after each break (the reference's 5 game ticks), the shortest break time that still
// chips, and the progress of the block the aim last slipped off (kept half a second).
enum MineSteady {
    static let pause = 0.25
    static let chipMin: Float = 0.33
    private static var kept: (p: IVec3, progress: Float, at: Double)?

    static func remember(_ p: IVec3, _ progress: Float, now: Double) { kept = (p, progress, now) }
    static func recall(_ p: IVec3, now: Double) -> Float {
        guard let k = kept, k.p == p, now - k.at < 0.5 else { return 0 }
        kept = nil
        return k.progress
    }
}
