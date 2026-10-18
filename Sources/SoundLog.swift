import Foundation

// P362 (g): the last sounds played, by name, so an odd sound in a voice note or bug note can be found: every note's
// context carries the sounds of the 12 seconds before it ("sounds"). A fixed ring of enum values (no strings until a
// note asks).
enum SoundLog {
    private static var ring = [(Double, Snd, Float)](repeating: (-1e9, .click, 0), count: 64)
    private static var next = 0

    static func note(_ s: Snd, clock: Double, dist: Float) {
        ring[next] = (clock, s, dist)
        next = (next + 1) % ring.count
    }

    // "name (2.4 s ago, 6 blocks), ..." newest first, over the last `window` seconds.
    static func recent(clock: Double, window: Double = 12) -> String {
        var out: [String] = []
        for k in 1...ring.count {
            let (t, s, d) = ring[(next - k + ring.count) % ring.count]
            if clock - t > window || t < 0 { break }
            out.append(String(format: "%@ (%.1f s ago%@)", s.name, clock - t, d > 0.5 ? String(format: ", %.0f blocks", d) : ""))
        }
        return out.isEmpty ? "none" : out.joined(separator: ", ")
    }
}
