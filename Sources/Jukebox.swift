import Foundation
import simd

// Music discs and the jukebox. Each disc is an original procedurally composed piece (seeded by the
// disc's name, played on the note-block instruments), with the reference disc lengths.
enum MusicDiscs {
    // name, label colour, length in seconds (reference lengths)
    static let all: [(String, UInt32, Int)] = [
        ("13", 0xE8E0B0, 178), ("cat", 0x6AD85A, 185), ("blocks", 0xE8762A, 345), ("chirp", 0xD02A2A, 185), ("far", 0x9AE85A, 174),
        ("mall", 0x8A5AE8, 197), ("mellohi", 0xC87AC8, 96), ("stal", 0x2A2A2A, 150), ("strad", 0xF0F0F0, 188), ("ward", 0x3A8A3A, 251),
        ("11", 0x3A3A3A, 71), ("wait", 0x3A8AE8, 238), ("pigstep", 0xB03A3A, 149), ("otherside", 0x3AB8D8, 195), ("5", 0x3A5A6A, 178),
        ("relic", 0x3A8A8A, 218), ("creator", 0xE8C040, 176), ("creator_music_box", 0xE8C040, 73), ("precipice", 0x8A6A4A, 299),
    ]
    // Discs a hisser drops when a skeleton kills it.
    static let creeperDrops = ["13", "cat", "blocks", "chirp", "far", "mall", "mellohi", "stal", "strad", "ward", "11", "wait"]

    struct Note { var t: Float; var inst: Int; var pitch: Int }

    // A seeded composition: a chord progression with a bass line, arpeggios and a melody.
    static func song(_ name: String) -> [Note] {
        var rng = SRng(UInt64(bitPattern: Int64(name.hashValue & 0x7FFFFFFF)) | 0x51)
        let len = Float(all.first { $0.0 == name }?.2 ?? 120)
        let bpm = Float(80 + rng.int(60))
        let beat = 60 / bpm
        let scale = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16]
        let minor = rng.chance(0.5)
        let sc = minor ? [0, 2, 3, 5, 7, 8, 10, 12, 14, 15] : scale
        let root = rng.int(7)
        let prog = (0..<4).map { _ in [0, 3, 4, 5, 2][rng.int(5)] }
        let lead = [0, 5, 6, 7, 8, 13, 14, 15][rng.int(8)]           // harp, bell, flute, chime...
        var out: [Note] = []
        var t: Float = 0
        var bar = 0
        while t < len {
            let chord = prog[bar % 4]
            for b in 0..<4 {
                let tb = t + Float(b) * beat
                if b == 0 || b == 2 { out.append(Note(t: tb, inst: 1, pitch: (root + sc[chord % 7]) % 25)) }                 // bass
                if bar % 8 < 6 {
                    for k in 0..<2 { out.append(Note(t: tb + Float(k) * beat / 2, inst: 0, pitch: min(24, root + sc[(chord + [0, 2, 4][(b + k) % 3]) % 10]))) }
                }
                if b % 2 == 0 && rng.chance(0.4) { out.append(Note(t: tb, inst: 2, pitch: 0)) }                                    // snare
                if rng.chance(0.7) { out.append(Note(t: tb, inst: lead, pitch: min(24, root + 5 + sc[rng.int(8)]))) }               // melody
            }
            t += 4 * beat
            bar += 1
        }
        return out
    }
}

final class JukeboxPlayer {
    let pos: IVec3
    let disc: String
    let notes: [MusicDiscs.Note]
    var t: Float = 0
    var next = 0
    init(_ p: IVec3, _ d: String) { pos = p; disc = d; notes = MusicDiscs.song(d) }
}

extension Game {
    // Right-click a jukebox: insert the held disc, or eject the playing one.
    func useJukebox(_ p: IVec3) -> Bool {
        if let i = jukeboxes.firstIndex(where: { $0.pos == p }) {
            let j = jukeboxes.remove(at: i)
            drops.spawn(ItemStack(Items.id("music_disc_\(j.disc)"), 1), at: V3(Float(p.x) + 0.5, Float(p.y) + 1.1, Float(p.z) + 0.5))
            return true
        }
        let k = Items.key(held.item)
        guard k.hasPrefix("music_disc_") else { return false }
        let name = String(k.dropFirst("music_disc_".count))
        jukeboxes.append(JukeboxPlayer(p, name))
        consumeHeld()
        onToast?("Now Playing: Blocksmith - \(name)")
        return true
    }

    func jukeboxTick(_ dt: Float) {
        guard !jukeboxes.isEmpty else { return }
        for j in jukeboxes {
            j.t += dt
            let c = V3(Float(j.pos.x) + 0.5, Float(j.pos.y) + 0.5, Float(j.pos.z) + 0.5)
            while j.next < j.notes.count && j.notes[j.next].t <= j.t {
                let n = j.notes[j.next]
                if simd_length(c - player.pos) < 64 { sfx(.note(n.inst, n.pitch), 0.7, at: c) }
                j.next += 1
            }
            if Float.random(in: 0..<1) < dt * 2 { particles.hearts(at: c + V3(0, 0.8, 0)) }
        }
        // Finished discs stay in the jukebox, silent (like the reference game).
        for j in jukeboxes where j.next >= j.notes.count { j.t = min(j.t, 1e6) }
    }
}
