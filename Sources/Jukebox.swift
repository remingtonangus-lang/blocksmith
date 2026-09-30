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
        onToast?("Now Playing: \(MusicDiscs.title(name))")
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

// Blocksmith's own titles for the discs (the keys stay the save IDs).
extension MusicDiscs {
    static let titles: [String: String] = [
        "13": "Hollow Echo", "cat": "Paw Prints", "blocks": "Building Blocks", "chirp": "Morning Chirp", "far": "Far Hills",
        "mall": "Market Day", "mellohi": "Slow Glow", "stal": "Stalwart", "strad": "Strings", "ward": "Warding",
        "11": "Broken Record", "wait": "Patience", "pigstep": "Ember March", "otherside": "Other Shore", "5": "Deep Signal",
        "relic": "Relic", "creator": "Maker", "creator_music_box": "Maker (Music Box)", "precipice": "Cliffside",
    ]
    static func title(_ key: String) -> String { titles[key] ?? key }

    // Calm background pieces: slow harp/flute lines over soft bass, lots of space between phrases.
    static func ambient(seed: UInt64, mood: Int) -> [Note] {
        var rng = SRng(seed | 0x5EED)
        let beat: Float = 60 / Float(52 + rng.int(20))
        let sc = mood == 1 ? [0, 1, 3, 5, 7, 8, 10, 12, 13, 15] : (mood == 2 ? [0, 2, 3, 6, 7, 8, 11, 12, 14, 15] : [0, 2, 4, 7, 9, 12, 14, 16, 19, 21])
        let root = 3 + rng.int(5)
        let lead = mood == 0 ? [0, 6, 13][rng.int(3)] : (mood == 1 ? 1 : 5)
        var out: [Note] = []
        var t: Float = 1
        let len = Float(90 + rng.int(90))
        while t < len {
            // A phrase of 4-8 notes, then a rest of 2-6 beats.
            let n = 4 + rng.int(5)
            var deg = rng.int(5)
            for _ in 0..<n {
                out.append(Note(t: t, inst: lead, pitch: min(24, root + sc[max(0, min(9, deg))])))
                if rng.chance(0.35) { out.append(Note(t: t, inst: 1, pitch: (root + sc[deg % 5]) % 25)) }
                deg += rng.chance(0.5) ? 1 : -1
                deg = max(0, min(9, deg))
                t += beat * Float([1, 1, 2, 2, 3][rng.int(5)])
            }
            t += beat * Float(2 + rng.int(5))
        }
        return out
    }
}

// Background music: a piece every 10-20 minutes (first one 1-3 minutes in), mood by dimension,
// quiet while a jukebox plays nearby.
final class MusicDirector {
    var wait: Float = Float.random(in: 60...180)
    var notes: [MusicDiscs.Note] = []
    var t: Float = 0
    var next = 0
    var playing: Bool { next < notes.count }
}

extension Game {
    func musicTick(_ dt: Float) {
        // Cave ambience: an occasional low rumble when standing in darkness underground.
        caveTimer -= dt
        if caveTimer <= 0 {
            caveTimer = Float.random(in: 20...60)
            let l = world.lightAt(Int(floor(player.pos.x)), Int(floor(player.eye.y)), Int(floor(player.pos.z)))
            if dim.dim == .overworld && l.sky == 0 && l.block < 4 && Float.random(in: 0..<1) < 0.5 {
                let a = Float.random(in: 0..<(2 * .pi))
                sfx(.caveAmbience, 0.6, at: player.eye + V3(cosf(a), 0, sinf(a)) * 6)
            }
        }
        let m = music
        let jukeboxNear = jukeboxes.contains { simd_length(V3(Float($0.pos.x), Float($0.pos.y), Float($0.pos.z)) - player.pos) < 64 && $0.next < $0.notes.count }
        if m.playing {
            m.t += dt
            while m.next < m.notes.count && m.notes[m.next].t <= m.t {
                let n = m.notes[m.next]
                if !jukeboxNear && musicVolume > 0 { sfx(.note(n.inst, n.pitch), 0.32 * musicVolume) }
                m.next += 1
            }
            if !m.playing { m.wait = Float.random(in: 600...1200) }
            return
        }
        m.wait -= dt
        if m.wait <= 0 {
            let mood = dim.dim == .nether ? 1 : (dim.dim == .end ? 2 : 0)
            m.notes = MusicDiscs.ambient(seed: UInt64.random(in: 0...UInt64(Int32.max)), mood: mood)
            m.t = 0; m.next = 0
        }
    }
}
