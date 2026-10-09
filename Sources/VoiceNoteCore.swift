import Foundation
import simd

// Shared parts of the Quest's always-on voice bug notes (quest/src/android/QuestVoiceNotes.swift, dev builds only):
// the voice-activity segmenter, the recent-events log, the game-state context written beside each recording and the
// storage cap. Plain Swift with no audio APIs, so `--questbugs` checks it on the Mac.

// Energy voice-activity detection on 20 ms mic frames. The threshold sits above both the room's noise floor and the
// game's own sound as heard by the mic (`ref` = the mixer's output level, `leak` = learned pickup ratio), so music
// and explosions don't open notes. A note is the speech plus padding: the recorder keeps `preroll` seconds before
// the start and the segment runs `hangover` seconds past the last voiced frame.
struct VoiceSegmenter {
    enum Event: Equatable { case none, start, split, end(keep: Bool) }
    var attack = 0.12               // seconds above the threshold before a note opens
    var hangover = 1.0              // trailing padding: quiet seconds before it closes
    var minVoiced = 0.4             // shorter bursts (a cough, a click) are dropped
    var maxLength = 60.0            // longer notes are split into files of at most this length
    static let preroll = 0.5        // leading padding the recorder keeps

    private(set) var inSpeech = false
    private(set) var noiseFloor: Float = 0.003
    private(set) var leak: Float = 0.3
    private(set) var threshold: Float = 0.01
    private(set) var segmentTime = 0.0
    private(set) var voicedTime = 0.0
    private var above = 0.0, below = 0.0

    // One frame: mic RMS and game output RMS (both 0...1 of full scale). Returns what the recorder must do.
    mutating func push(rms: Float, ref: Float, dt: Double) -> Event {
        // Minimum statistics: fall fast to quieter levels, rise slowly (speech is bursty, noise and music are steady).
        noiseFloor = rms < noiseFloor ? noiseFloor * 0.95 + rms * 0.05 : noiseFloor * 0.9995 + rms * 0.0005
        if ref > 0.005 {
            let r = min(2, rms / ref)
            leak = r < leak ? leak * 0.95 + r * 0.05 : leak * 0.999 + r * 0.001
        }
        let floorT = max(0.008, noiseFloor * 3)
        let gameT = leak * ref * 2.5
        threshold = max(floorT, gameT)
        if !inSpeech {
            above = rms > threshold ? above + dt : 0
            guard above >= attack else { return .none }
            inSpeech = true
            segmentTime = above; voicedTime = above; below = 0
            return .start
        }
        segmentTime += dt
        if rms > threshold * 0.7 { voicedTime += dt; below = 0 } else { below += dt }
        if below >= hangover {
            inSpeech = false
            above = 0
            return .end(keep: voicedTime >= minVoiced)
        }
        if segmentTime >= maxLength {
            segmentTime = 0; voicedTime = 0
            return .split
        }
        return .none
    }
}

// What the player was doing lately, from per-tick state changes (no hooks in game code): damage, deaths, dimension,
// mounts, piloting, screens, held item, toasts, biome. Each note's sidecar lists the last 30 seconds.
final class VoiceEvents {
    private(set) var log: [(t: Double, text: String)] = []
    private var health = -1, alive = true, dim = "", mount = "", pilot = "", screen = "", held = "", toast = "", biome = ""
    private var biomeCheck = 0.0, damage = 0, damageAt = 0.0

    func observe(_ g: Game) {
        let t = g.clock
        func add(_ s: String) { log.append((t, s)); if log.count > 40 { log.removeFirst(log.count - 40) } }
        if health >= 0 && g.health < health { damage += health - g.health; damageAt = t }
        if damage > 0 && t - damageAt > 1 { add("took \(damage) damage (health \(g.health)/20)"); damage = 0 }
        health = g.health
        if alive && !g.alive { add("died") }
        if !alive && g.alive { add("respawned") }
        alive = g.alive
        let d = g.dim.dim.displayName
        if d != dim { if !dim.isEmpty { add("entered \(d)") }; dim = d }
        let m = g.riding?.kind.name ?? ""
        if m != mount { add(m.isEmpty ? "dismounted \(mount)" : "mounted \(m)"); mount = m }
        let p = g.world.ships.pilot?.name ?? ""
        if p != pilot { add(p.isEmpty ? "stopped piloting \(pilot)" : "piloting \(p)"); pilot = p }
        let s = g.menu.map { "\(type(of: $0))" } ?? ""
        if s != screen { add(s.isEmpty ? "closed \(screen)" : "opened \(s)"); screen = s }
        let h = g.held.count > 0 ? Items.name(g.held.item) : "empty hand"
        if h != held { if !held.isEmpty { add("holding \(h)") }; held = h }
        if g.toastText != toast { if !g.toastText.isEmpty { add("message: \(g.toastText)") }; toast = g.toastText }
        if t - biomeCheck > 2 {
            biomeCheck = t
            let b = VoiceNoteContext.biome(g)
            if b != biome { if !biome.isEmpty { add("walked into \(b)") }; biome = b }
        }
    }

    func recent(_ g: Game, seconds: Double = 30) -> [String] {
        log.filter { g.clock - $0.t <= seconds }.map { String(format: "-%.0fs %@", g.clock - $0.t, $0.text) }
    }
}

enum VoiceNoteContext {
    static func biome(_ g: Game) -> String {
        g.world.gen.column(Int(floor(g.player.pos.x)), Int(floor(g.player.pos.z))).biome.displayName
    }

    // Game state for a note's sidecar, in display order.
    static func describe(_ g: Game, build: String, fps: Double) -> [(String, String)] {
        let p = g.player
        var yawDeg = Double(-p.yaw * 180 / .pi).truncatingRemainder(dividingBy: 360)
        if yawDeg < 0 { yawDeg += 360 }
        let dirs = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
        let facing = dirs[Int((yawDeg + 22.5) / 45) % 8]
        var target = "nothing"
        if let t = g.target {
            target = "\(Blocks.name(g.world.block(t.hit.x, t.hit.y, t.hit.z))) at \(t.hit.x) \(t.hit.y - YOFF) \(t.hit.z)"
        }
        let hour = (g.dayFraction * 24 + 6).truncatingRemainder(dividingBy: 24)
        let weather = g.weather.thundering ? "thunderstorm" : (g.weather.raining ? "rain" : "clear")
        var mount = "on foot"
        if let r = g.riding { mount = "riding \(r.kind.name)" }
        if let s = g.world.ships.pilot { mount = "piloting \(s.name)" }
        if p.flying { mount += ", flying" }
        let held = g.held.count > 0 ? "\(Items.name(g.held.item)) x\(g.held.count)" : "empty hand"
        return [
            ("build", build),
            ("world", "\(g.save?.dir.lastPathComponent ?? "(test world)") (seed \(g.world.seed))"),
            ("dimension", g.dim.dim.displayName),
            ("position", String(format: "%.1f %.1f %.1f", p.pos.x, p.pos.y - Float(YOFF), p.pos.z)),
            ("facing", String(format: "%@ (yaw %.0f, pitch %.0f)", facing, yawDeg, Double(p.pitch * 180 / .pi))),
            ("biome", biome(g)),
            ("held", held),
            ("mount", mount),
            ("looking at", target),
            ("mode", "\(g.survival ? "Survival" : "Creative"), health \(g.health)/20\(g.menu.map { ", screen \(type(of: $0))" } ?? "")"),
            ("time", String(format: "day %d %02d:%02d, %@", Int(g.time / DAY_LENGTH) + 1, Int(hour), Int(hour * 60) % 60, weather)),
            ("fps", String(format: "%.0f", fps)),
        ]
    }

    // One JSON object per line; keys in the given order.
    static func json(_ fields: [(String, Any)]) -> String {
        func esc(_ s: String) -> String {
            var o = "\""
            for u in s.unicodeScalars {
                switch u {
                case "\"": o += "\\\""
                case "\\": o += "\\\\"
                case "\n": o += "\\n"
                case "\r", "\t": o += " "
                default: if u.value < 0x20 { o += " " } else { o.unicodeScalars.append(u) }
                }
            }
            return o + "\""
        }
        func val(_ v: Any) -> String {
            switch v {
            case let s as String: return esc(s)
            case let d as Double: return String(format: "%.3f", d)
            case let i as Int: return "\(i)"
            case let b as Bool: return b ? "true" : "false"
            case let a as [String]: return "[" + a.map(esc).joined(separator: ",") + "]"
            case let kv as [(String, String)]: return "{" + kv.map { esc($0.0) + ":" + esc($0.1) }.joined(separator: ",") + "}"
            default: return esc("\(v)")
            }
        }
        return "{" + fields.map { esc($0.0) + ":" + val($0.1) }.joined(separator: ",") + "}"
    }

    // Keeps the recordings folder under `maxBytes` by deleting the oldest files (names start vn-YYYYMMDD-HHMMSS, so
    // name order is age order). Returns the number of files deleted.
    @discardableResult
    static func enforceCap(dir: String, maxBytes: Int64) -> Int {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return 0 }
        var files: [(String, Int64)] = []
        var total: Int64 = 0
        for n in names.sorted() where n.hasPrefix("vn-") {
            let size = ((try? fm.attributesOfItem(atPath: dir + "/" + n))?[.size] as? NSNumber)?.int64Value ?? 0
            files.append((n, size)); total += size
        }
        var deleted = 0
        for (n, size) in files where total > maxBytes {
            try? fm.removeItem(atPath: dir + "/" + n)
            total -= size; deleted += 1
        }
        return deleted
    }
}
