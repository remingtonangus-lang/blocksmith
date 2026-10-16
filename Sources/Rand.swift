import Foundation

// Game randomness. Every gameplay random draw goes through here so bot runs can be replayed exactly:
// in deterministic mode (agent runs, replays) main-thread draws come from one seeded SplitMix64 stream;
// otherwise (normal play) and on any other thread (audio, workers) it is the system generator.
enum Rand {
    static var deterministic = false
    private static var state: UInt64 = 0x9E3779B97F4A7C15

    static func seed(_ s: UInt64) { state = s &+ 0x9E3779B97F4A7C15; deterministic = true }

    // Normal play on the main thread: its own SplitMix64 stream, seeded once from the system. The system generator is
    // a getrandom() syscall per draw on Linux and Android: a main gun impact's ~3,000 particle draws cost 10 ms of the
    // frame (T3: "the impact itself is cheap", puffs 9.8 ms of 13.2).
    private static var fast: UInt64 = { var g = SystemRandomNumberGenerator(); return g.next() }()

    // P283: Thread.isMainThread is two system calls on Linux and Android (the thread's id against the process's): 8% of
    // the frame thread's samples on the Quest replay of his homestead went there, from the grass ticks' and the
    // particles' draws. The first Game (always made on the main thread) notes the thread; it is compared directly.
    static var mainThread: pthread_t? = nil
    @inline(__always) static var onMain: Bool {
        if let m = mainThread { return pthread_equal(pthread_self(), m) != 0 }
        return Thread.isMainThread
    }

    @inline(__always) static func next() -> UInt64 {
        if onMain {
            var z: UInt64
            if deterministic { state &+= 0x9E3779B97F4A7C15; z = state } else { fast &+= 0x9E3779B97F4A7C15; z = fast }
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
