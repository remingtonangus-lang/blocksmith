import Foundation
import simd

// P359: the Sunderfall soundtrack. 40 recorded tracks (Resources/Music/sunderfall, made by Remington in Google Flow
// Music) replace the procedural composer as the default soundtrack (Options > Audio > Soundtrack: Sunderfall; the
// composer stays as Classic, own music as My Music / Mixed). Each track is one game state; the director below picks
// the state, crossfades 3-4 s between tracks and never restarts a track while its state goes on. Calm tracks leave
// 30-90 s of quiet before they play again; combat, danger and bosses take over at once and hand back with a crossfade.
// The files stream from disk (the Mac: AVAudioFile through a player node, SoundtrackMac.swift; the Quest: APK
// assets/music decoded by AMediaExtractor + AMediaCodec, QuestTracks.swift). Gains: SoundtrackGains.swift.

// A player for the soundtrack's files: two decks crossfading.
protocol TrackDeck: AnyObject {
    var available: Bool { get }             // the tracks are there and can be decoded
    var current: String? { get }            // the track playing (not fading out); nil once it ended or stopped
    var volume: Float { get set }           // master x music x duck
    var names: Set<String> { get }          // every track file it can play (a state's own and its takes, P457)
    func play(_ name: String, gain: Float, fade: Float)
    func stop(fade: Float)
    func update(_ dt: Float)
}

enum Soundtrack {
    static let tracks = ["main_title", "loading_screen", "overworld_daytime", "overworld_night", "rain", "snow", "desert",
                         "jungle", "swamp", "mountains", "old_growth_forest", "ocean_sailing", "underwater", "caves",
                         "the_hollow", "emberdeep", "sky_islands", "village", "capital_city", "military_base_infiltration",
                         "danger_nearby", "combat", "boss_battle", "raid_incoming", "creative_mode", "ash_vault_front",
                         "ash_vault_battle", "no_mans_land", "hell_exploration", "hell_purple_wastes", "hell_red_forest",
                         "brimstone_keep", "knight_duel", "frigate_command", "drop_ship_flight", "submarine", "helicopter",
                         "trains_and_railways", "death", "victory"]
    // States that cut in at once (a short crossfade, no waiting for the state to settle).
    static let urgent: Set<String> = ["combat", "danger_nearby", "boss_battle", "knight_duel", "raid_incoming",
                                      "ash_vault_battle", "death", "victory"]
    // States that play again with no quiet when their track ends (fights, screens).
    static let looping: Set<String> = urgent.union(["main_title", "loading_screen", "military_base_infiltration"])
    static func gain(_ name: String) -> Float { SoundtrackGains.table[name] ?? SoundtrackGains.table[state(of: name)] ?? 1 }
    // P457 (Oct 25 14:40, "we need 3x the songs... Maybe 7 songs for the most normal areas you are in. That way it's not
    // just the same song playing over and over"): a state has several takes, its own file and "<state>_2", "_3b"...
    // (the overworld, caves, village and combat about seven each, the rest three). The state a file plays for: its name
    // without a trailing take number.
    static func state(of file: String) -> String {
        guard let u = file.lastIndex(of: "_") else { return file }
        let tail = file[file.index(after: u)...]
        guard let f = tail.first, f.isNumber, tail.dropFirst().allSatisfy({ $0.isNumber || ($0.isLetter && $0.isLowercase) }),
              tail.filter({ $0.isLetter }).count <= 1 else { return file }
        return String(file[..<u])
    }
    static func takes(_ state: String, in names: Set<String>) -> [String] {
        names.filter { Soundtrack.state(of: $0) == state }.sorted()
    }
    // Where the files are: next to the working directory (harness runs) or in the Mac app bundle (build.sh copies them).
    static func folders() -> [String] {
        var f = [FileManager.default.currentDirectoryPath + "/Resources/Music/sunderfall"]
        if let r = Bundle.main.resourcePath { f.append(r + "/Music/sunderfall") }
        return f
    }
}

final class SoundtrackDirector {
    var want = ""                    // the state now (evaluated twice a second)
    var settled = ""                 // the state once it has held 2 s (urgent states settle at once)
    var heldFor: Float = 0
    var evalTimer: Float = 0
    var placeTimer: Float = 0
    var place = ""                   // a structure the player is in (village, capital_city, military_base, brimstone_keep)
    var quiet: Float = 0             // seconds left of quiet before a calm track plays again
    var ended = ""                   // the state whose track last ended by itself (its quiet is running)
    var lastCur: String? = nil       // the track playing last frame
    var log: [String]? = nil         // harness: every track started
    var playedFor: Float = 0         // seconds the track playing now has played (P437: calm tracks keep the floor 45 s)
    var takes: [String: [String]] = [:]     // P457: each state's takes the deck has (looked up once)
    var recent: [String: [String]] = [:]    // P457: each state's takes played lately, newest last

    // P457: the take to play for a state: one not heard lately (the last half of its takes, at most four back), at
    // random among the rest; the state's own name when the deck has no takes for it.
    func nextTake(_ state: String, _ deck: TrackDeck) -> String {
        if takes[state] == nil { takes[state] = Soundtrack.takes(state, in: deck.names) }
        let all = takes[state] ?? []
        guard all.count > 1 else { return all.first ?? state }
        var heard = recent[state] ?? []
        let keep = min(4, all.count / 2)
        if heard.count > keep { heard.removeFirst(heard.count - keep) }
        let fresh = all.filter { !heard.contains($0) }
        let pick = fresh.isEmpty ? all[Int.random(in: 0..<all.count)] : fresh[Int.random(in: 0..<fresh.count)]
        heard.append(pick)
        recent[state] = heard
        return pick
    }
}

extension Game {
    // The state's track. Cheap checks every call; structure lookups every 2 s (director.place).
    func soundtrackState() -> String {
        if let pm = menu as? PauseMenu, pm.page == .title { return "main_title" }
        if HudExtras.loading != nil { return "loading_screen" }
        if credits != nil { return "victory" }
        if menu is DeathMenu || health <= 0 { return "death" }
        let p = player.pos
        // Bosses, then a knight at sword's length.
        var danger = false, knight = false
        for m in mobs.mobs where m.health > 0 {
            let d = simd_length(m.pos - p)
            if d > 80 { continue }
            if (Legendaries.isBoss(m) || m.kind == .wither) && (d < 48 || m.aggro) { return "boss_battle" }
            guard m.kind.hostile && d < 18 && (m.aggro || m.spec.behavior == .melee) else { continue }
            danger = true
            if d < 7 && [.brandSquire, .brandKnight, .brandChampion].contains(m.kind) { knight = true }
        }
        if knight { return "knight_duel" }
        let deep = dim.dim == .deep
        if deep && DeepGen.inVault(p.y) {
            if audio.combat >= 2 { return "ash_vault_battle" }
            let nml = (world.gen as? DeepGen)?.ground.noMansLand(Int(floor(p.x)), Int(floor(p.z))) ?? 0
            return nml > 0.3 ? "no_mans_land" : "ash_vault_front"
        }
        if raid != nil || FactionRaids.active != nil { return "raid_incoming" }
        if audio.combat >= 2 || (danger && clock - lastHurtAt < 6) { return "combat" }
        // Vehicles: the craft at the player's helm, or the train under them.
        if let s = world.ships.pilot?.root {
            let role = s.role ?? ""
            if role == "capfrigate" || role == "warfrigate" || role == "frigate" { return "frigate_command" }
            if role == "dropship" { return "drop_ship_flight" }
            if s.ballast > 0 { return "submarine" }
            if VehicleControls.kind(s) == .helicopter { return "helicopter" }
        }
        if let r = riding, Trains.trains.values.contains(where: { $0.cars.contains { $0 === r } }) { return "trains_and_railways" }
        if music.soundtrack.place == "military_base" && audio.combat == 1 { return "military_base_infiltration" }
        if danger || audio.combat == 1 { return "danger_nearby" }
        switch dim.dim {
        case .nether: return "emberdeep"
        case .end:
            return simd_length(V2(p.x, p.z)) > 700 ? "sky_islands" : "the_hollow"     // the outer islands
        case .deep where DeepGen.inHell(p.y):
            if music.soundtrack.place == "brimstone_keep" { return "brimstone_keep" }
            switch world.gen.column(Int(floor(p.x)), Int(floor(p.z))).biome {
            case .warpedForest: return "hell_purple_wastes"         // the Gloamwood
            case .crimsonForest: return "hell_red_forest"           // the Charwood Thicket
            default: return "hell_exploration"
            }
        case .deep: return "caves"
        case .overworld: break
        }
        if player.headInWater { return "underwater" }
        if audio.cave > 0.85 && p.y < Float(SEA - 6) { return "caves" }
        // P474 (Oct 26 19:32, "Does Creative not have any other songs it can play?"): Creative's own three takes had the
        // whole overworld to themselves; now they hold ten minutes in thirty and the place, biome and hour play the rest.
        if !survival && Int(clock / 600) % 3 == 0 { return "creative_mode" }
        if music.soundtrack.place == "capital_city" { return "capital_city" }
        if music.soundtrack.place == "village" { return "village" }
        let b = audio.biomeHere
        if let r = riding, r.kind == .boat { return "ocean_sailing" }
        switch b {
        case .ocean, .deepOcean, .warmOcean, .lukewarmOcean, .deepLukewarmOcean, .coldOcean, .deepColdOcean, .frozenOcean,
             .deepFrozenOcean:
            return "ocean_sailing"
        default: break
        }
        let snowy: Bool
        switch b {
        case .snowyPlains, .iceSpikes, .snowyTaiga, .snowySlopes, .frozenPeaks, .jaggedPeaks, .grove, .snowyBeach, .frozenRiver: snowy = true
        default: snowy = false
        }
        if snowy { return "snow" }
        if weather.rain > 0.6 { return "rain" }
        if dayFraction >= 0.5 { return "overworld_night" }
        switch b {
        case .desert, .badlands, .erodedBadlands, .woodedBadlands: return "desert"
        case .jungle, .sparseJungle, .bambooJungle: return "jungle"
        case .swamp, .mangroveSwamp: return "swamp"
        case .stonyPeaks, .windsweptHills, .windsweptGravellyHills, .windsweptForest, .windsweptSavanna: return "mountains"
        case .taiga, .oldGrowthPineTaiga, .oldGrowthSpruceTaiga, .forest, .birchForest, .oldGrowthBirchForest, .darkForest, .paleGarden:
            return "old_growth_forest"
        default: return "overworld_daytime"
        }
    }

    // One frame of the Sunderfall soundtrack (musicTick calls it while the soundtrack is Sunderfall).
    func soundtrackTick(_ dt: Float, _ deck: TrackDeck) {
        let d = music.soundtrack
        // A track that ended by itself: its state rests 30-90 s before it plays again.
        let now = deck.current
        if let lc = d.lastCur, now == nil { d.ended = Soundtrack.state(of: lc); d.quiet = Rand.float(in: 30...90) }
        d.lastCur = now
        func start(_ state: String, fade: Float) {
            let name = d.nextTake(state, deck)                          // P457: one of the state's takes
            deck.play(name, gain: Soundtrack.gain(name), fade: fade)
            d.ended = ""
            d.lastCur = name
            d.playedFor = 0
            d.log?.append(name)
        }
        d.placeTimer -= dt
        if d.placeTimer <= 0 {
            d.placeTimer = 2
            let p = player.pos
            let x = Int(floor(p.x)), y = Int(floor(p.y)), z = Int(floor(p.z))
            d.place = ""
            if let sc = world.gen.structures {
                let kinds = dim.dim == .overworld ? ["capital_city", "village", "military_base"] : (dim.dim == .deep ? ["brimstone_keep"] : [])
                for k in kinds where sc.structure(at: x, y, z, kind: k) != nil { d.place = k; break }
            }
        }
        d.evalTimer -= dt
        if d.evalTimer <= 0 {
            d.evalTimer = 0.5
            let w = soundtrackState()
            if w != d.want { d.want = w; d.heldFor = 0 }
        }
        d.heldFor += dt
        d.playedFor += dt
        // P437 (Oct 24 15:21, "the way the music changes from one thing to the other is a little too..."): walking along
        // a forest's edge swapped the forest and plains tracks every few seconds with a 3.5 s fade. A calm state now has
        // to hold 12 s, a calm track keeps playing at least 45 s before another calm one takes over, and calm changes
        // crossfade over 8 s (6 s back from a fight). Fights, bosses and death still cut in at once.
        let calmHold: Float = Soundtrack.urgent.contains(d.settled) ? 4 : 12
        if d.want != d.settled && (Soundtrack.urgent.contains(d.want) || d.heldFor >= calmHold) { d.settled = d.want }
        let want = d.settled
        guard !want.isEmpty, AudioSettings.volume(.music) > 0 else {
            if deck.current != nil { deck.stop(fade: 2) }
            return
        }
        if let file = deck.current {
            let cur = Soundtrack.state(of: file)
            if cur == want { return }                                   // never restart a track while its state goes on
            // A new state: crossfade (fights cut in quicker, and hand back over 4 s).
            if !Soundtrack.urgent.contains(want) && !Soundtrack.urgent.contains(cur) && !Soundtrack.looping.contains(cur) && d.playedFor < 45 { return }
            let fade: Float = Soundtrack.urgent.contains(want) ? 1.5 : (Soundtrack.urgent.contains(cur) ? 6 : 8)
            start(want, fade: fade)
            return
        }
        // Nothing playing: a calm state's track that just ended rests 30-90 s; a new state plays now.
        if d.ended == want && !Soundtrack.looping.contains(want) {
            if d.quiet > 0 { d.quiet -= dt; return }
        }
        start(want, fade: Soundtrack.urgent.contains(want) ? 1 : 5)

    }
}
