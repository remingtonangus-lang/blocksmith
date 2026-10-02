import Foundation

// Game randomness. Every gameplay random draw goes through here so bot runs can be replayed exactly:
// in deterministic mode (agent runs, replays) main-thread draws come from one seeded SplitMix64 stream;
// otherwise (normal play) and on any other thread (audio, workers) it is the system generator.
enum Rand {
    static var deterministic = false
    private static var state: UInt64 = 0x9E3779B97F4A7C15

    static func seed(_ s: UInt64) { state = s &+ 0x9E3779B97F4A7C15; deterministic = true }

    @inline(__always) static func next() -> UInt64 {
        if deterministic && Thread.isMainThread {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        var g = SystemRandomNumberGenerator()
        return g.next()
    }

    struct Gen: RandomNumberGenerator { mutating func next() -> UInt64 { Rand.next() } }

    static func float(in r: Range<Float>) -> Float { var g = Gen(); return Float.random(in: r, using: &g) }
    static func float(in r: ClosedRange<Float>) -> Float { var g = Gen(); return Float.random(in: r, using: &g) }
    static func double(in r: Range<Double>) -> Double { var g = Gen(); return Double.random(in: r, using: &g) }
    static func double(in r: ClosedRange<Double>) -> Double { var g = Gen(); return Double.random(in: r, using: &g) }
    static func int(in r: Range<Int>) -> Int { var g = Gen(); return Int.random(in: r, using: &g) }
    static func int(in r: ClosedRange<Int>) -> Int { var g = Gen(); return Int.random(in: r, using: &g) }
    static func u64(in r: Range<UInt64>) -> UInt64 { var g = Gen(); return UInt64.random(in: r, using: &g) }
    static func u64(in r: ClosedRange<UInt64>) -> UInt64 { var g = Gen(); return UInt64.random(in: r, using: &g) }
    static func bool() -> Bool { var g = Gen(); return Bool.random(using: &g) }
}

extension Collection {
    // randomElement() through Rand (replayable).
    func pick() -> Element? { var g = Rand.Gen(); return randomElement(using: &g) }
}

extension Sequence {
    func shuffledRand() -> [Element] { var g = Rand.Gen(); return shuffled(using: &g) }
}
