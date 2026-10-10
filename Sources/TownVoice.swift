import Foundation
import simd

// Spoken townsfolk lines. Every townsperson has one voice (role + whether they are a woman); each voice has a few
// short lines per context (greeting, chatter, night, goodbye, trade done, can't afford, theft warning, angry, hurt,
// the sheriff's challenge). The text is the source of truth here; tools/townvoice_gen.py reads this table, has each
// line spoken by the voice's speech model (ElevenLabs through OpenRouter, logged in assets/CREDITS.md) and packs the
// takes as 16 kHz IMA-ADPCM in Resources/voices.bin (keyed by an FNV-1a hash of "voice|text", so the order here can
// change freely). Every line the game speaks comes from this table (TownTests checks each voice has a take for every
// context its role uses); a line without a take would show as text with a short murmur.
//
// Playback: Snd.voice(id) is decoded on demand (never cached: a few hundred takes would hold ~80 MB as floats) and
// played at the speaker's mouth through the normal 3D path on both engines; the caption is "Name: line". One voice
// at a time town-wide (Townsfolk.townLastLine); unprompted lines (chatter, hellos) at most every 20 s (TownLaw.ambientGap).

enum TownVoice {
    enum Ctx: String, CaseIterable { case greet, chatter, night, bye, trade, broke, theft, angry, hurt, challenge, handsup, closed, raid }

    // Voice key -> (speech model voice, playback-rate change applied when packing: the child is a pitched-up take).
    static let voices: [String: (String, Double)] = [
        "sheriff": ("Brian", 1), "deputy_m": ("Adam", 1), "deputy_f": ("River", 1),
        "keeper_m": ("Eric", 1), "keeper_f": ("Matilda", 1), "chef_m": ("Roger", 1), "chef_f": ("Jessica", 1),
        "farmer_m": ("Chris", 1), "farmer_f": ("Laura", 1), "elder_m": ("Bill", 1), "elder_f": ("Alice", 1),
        "folk_m": ("Will", 1), "folk_f": ("Sarah", 1), "child": ("Jessica", 1.22),
    ]
    // Line group -> the voices that speak it.
    static let groups: [String: [String]] = [
        "sheriff": ["sheriff"], "deputy": ["deputy_m", "deputy_f"], "keeper": ["keeper_m", "keeper_f"], "chef": ["chef_m", "chef_f"],
        "farmer": ["farmer_m", "farmer_f"], "elder": ["elder_m", "elder_f"], "folk": ["folk_m", "folk_f"], "child": ["child"],
    ]

    // (group, context, lines). Plain string literals only (the generator parses this table).
    static let script: [(String, String, [String])] = [
        ("folk", "greet", ["Howdy, stranger.", "Good day to you.", "Well, look who it is.", "Fine weather for it, isn't it?"]),
        ("folk", "chatter", ["Work never ends.", "Heard the creek's running high this year.", "Somebody keeps leaving the gate open.",
                             "The stew at the saloon isn't half bad.", "Wind's picking up out west."]),
        ("folk", "night", ["Getting late. I'm turning in.", "Mind the dark out there."]),
        ("folk", "bye", ["Take care now.", "See you around."]),
        ("folk", "trade", ["Much obliged.", "Fair enough. Done."]),
        ("folk", "broke", ["You're a bit short, friend.", "Come back when you've got the money."]),
        ("folk", "theft", ["Hey! That's not yours.", "Put that back, friend.", "I saw that."]),
        ("folk", "angry", ["Thief! Somebody fetch the sheriff!", "Get out of our town!", "You'll pay for that!"]),
        ("folk", "hurt", ["Ow! What was that for?", "Stop it! Help!"]),
        ("folk", "handsup", ["Easy! Easy now!", "Don't shoot!", "Put that away, mister."]),
        ("folk", "raid", ["Get inside! They're coming!", "Grab whatever you can swing!"]),

        ("keeper", "greet", ["Welcome in! Have a look around.", "Fresh stock today.", "Step right up."]),
        ("keeper", "chatter", ["Business is steady, thank goodness.", "Prices are fair. Ask anyone.", "Folks always need rope and lamp oil."]),
        ("keeper", "night", ["We're closed for the night.", "Come back at sunup."]),
        ("keeper", "bye", ["Come again!", "Don't be a stranger."]),
        ("keeper", "trade", ["Pleasure doing business.", "There you go. Good choice.", "Much obliged, friend."]),
        ("keeper", "broke", ["You're a little short there.", "That costs more than you're carrying."]),
        ("keeper", "theft", ["Hands off the merchandise!", "That needs paying for.", "I'm watching you."]),
        ("keeper", "angry", ["Thief! Get out of my shop!", "You're not welcome here anymore."]),
        ("keeper", "hurt", ["Ow! Have you lost your mind?", "Help! Sheriff!"]),
        ("keeper", "handsup", ["Whoa! Take whatever you want!", "Don't shoot! Please!"]),
        ("keeper", "closed", ["Sorry, we're closed. Come back in the morning.", "Shop's shut for now. Come back a little later.",
                              "That's closing time. Come back tomorrow."]),
        ("keeper", "raid", ["Lock the doors! Raiders!", "Everybody inside, quick!"]),

        ("chef", "greet", ["Smells good, doesn't it?", "Pull up a stool.", "Hungry? You came to the right place."]),
        ("chef", "chatter", ["The secret's in the pepper. Don't tell.", "Stew's been simmering since dawn.", "Best cuts in town, right here."]),
        ("chef", "night", ["Kitchen's closing up.", "Last call, folks."]),
        ("chef", "bye", ["Come back hungry!", "Mind the step on your way out."]),
        ("chef", "trade", ["Enjoy it while it's hot.", "Eat up, there's plenty.", "Good choice. That one's my favorite."]),
        ("chef", "broke", ["That's a little more than you've got.", "No money, no supper. Sorry."]),
        ("chef", "theft", ["Hey, that's somebody's supper!", "Put that down. It isn't yours."]),
        ("chef", "angry", ["Out of my kitchen, you thief!", "You'll get nothing from me now."]),
        ("chef", "hurt", ["Watch the knives! Ow!", "Have you gone mad?"]),
        ("chef", "handsup", ["Easy with that thing!", "Whoa, whoa! Put it down!"]),
        ("chef", "closed", ["Kitchen's closed, friend.", "We're shut. Come back when we open.", "Ovens are cold. Come back tomorrow."]),
        ("chef", "raid", ["Raiders! Get behind the counter!", "Bar the doors!"]),

        ("farmer", "greet", ["Howdy. Mind the furrows.", "Fine day for growing."]),
        ("farmer", "chatter", ["Crops are coming in nice this year.", "A good rain would do the fields some good.",
                               "Those crows get bolder every season.", "Wheat's near ready for the scythe."]),
        ("farmer", "night", ["Early start tomorrow. Off to bed.", "Animals are in. Day's done."]),
        ("farmer", "bye", ["Go on, then. Safe travels.", "Watch your step by the fence."]),
        ("farmer", "trade", ["Grown it myself.", "Fair trade."]),
        ("farmer", "broke", ["Can't do it for less, sorry."]),
        ("farmer", "theft", ["Hey! Those are my crops!", "Leave my field alone!", "That harvest feeds the whole town."]),
        ("farmer", "angry", ["Get off my land!", "Crop thief! Sheriff!"]),
        ("farmer", "hurt", ["Ow! Are you crazy?", "Help! Somebody!"]),
        ("farmer", "handsup", ["Don't shoot! I'm just a farmer!", "Easy, friend. Easy."]),
        ("farmer", "raid", ["They're coming over the fields!", "Get the animals in!"]),

        ("elder", "greet", ["Ah, a new face.", "Sit a spell, if you like."]),
        ("elder", "chatter", ["When I was young this was all prairie.", "Don't let them sell you what you don't need.",
                              "My knees say rain is coming.", "This town was three tents and a well, once."]),
        ("elder", "night", ["These old bones need their rest.", "Off you go. It's late."]),
        ("elder", "bye", ["Mind how you go, young one."]),
        ("elder", "theft", ["Shame on you. Put that back.", "I may be old, but I'm not blind."]),
        ("elder", "angry", ["In all my years! Get out!", "Shameful! Sheriff!"]),
        ("elder", "hurt", ["Oh! My poor back!", "Leave an old soul be!"]),
        ("elder", "trade", ["There you are. Use it well."]),
        ("elder", "broke", ["Not enough, I'm afraid."]),
        ("elder", "handsup", ["Point that somewhere else, youngster.", "I'm too old for this."]),
        ("elder", "raid", ["Raiders! Hide, everyone!", "Just like the bad old days."]),

        ("child", "greet", ["Hi!", "Are you a real adventurer?", "Watch this!"]),
        ("child", "chatter", ["I can run faster than anybody!", "I'm not supposed to go past the fence.", "I found a shiny rock today!"]),
        ("child", "night", ["I'm not even sleepy.", "Do I have to go to bed?"]),
        ("child", "bye", ["Bye bye!"]),
        ("child", "theft", ["I'm telling!", "That's stealing!"]),
        ("child", "angry", ["You're mean! Go away!"]),
        ("child", "hurt", ["Ow! Help!", "Stop it!"]),
        ("child", "handsup", ["Don't hurt me!", "I'm scared!"]),
        ("child", "raid", ["Hide! Hide!", "Monsters!"]),

        ("deputy", "greet", ["Keep the peace and we'll get along.", "Everything all right?"]),
        ("deputy", "chatter", ["Quiet day. I like it quiet.", "The sheriff's got eyes everywhere."]),
        ("deputy", "night", ["I'm on watch tonight. Go on home."]),
        ("deputy", "bye", ["Stay out of trouble."]),
        ("deputy", "theft", ["That's theft. Put it back, now.", "Last warning. Drop it."]),
        ("deputy", "angry", ["Stop right there, thief!", "You're under arrest!"]),
        ("deputy", "hurt", ["Assaulting a deputy? Big mistake."]),
        ("deputy", "challenge", ["Hold it right there!", "Don't make me draw."]),
        ("deputy", "handsup", ["Lower that weapon. Now.", "Point that somewhere else."]),
        ("deputy", "raid", ["Raiders! Hold the line!", "Everyone get indoors!"]),

        ("sheriff", "greet", ["I'm the sheriff here. Keep your nose clean.", "Peaceful town. Let's keep it that way.", "Howdy. Mind the rules and we're friends."]),
        ("sheriff", "chatter", ["Every drifter thinks this town is easy pickings.", "Coffee's terrible, but it's hot.", "Quiet streets make for a happy sheriff."]),
        ("sheriff", "night", ["Quiet night. Keep it that way."]),
        ("sheriff", "bye", ["Ride safe."]),
        ("sheriff", "theft", ["I saw that. Put it back, slow.", "You're on thin ice, stranger."]),
        ("sheriff", "angry", ["That's it. You're coming with me!", "Thief! Stand and face me!"]),
        ("sheriff", "hurt", ["You just made a real big mistake.", "That's assaulting the law!"]),
        ("sheriff", "challenge", ["Hold it right there, stranger!", "Drop what you took and raise your hands.",
                                  "This is your one warning.", "Draw, if you think you're fast enough."]),
        ("sheriff", "handsup", ["You point that at me, you'd better use it.", "Lower it. Slowly."]),
        ("sheriff", "raid", ["Raiders! Everybody take cover!", "Nobody rides into my town like that."]),
    ]

    // Every (voice, context, text) take, in a fixed order: Snd.voice(id) indexes this.
    struct Take { let voice: String; let ctx: Ctx; let text: String; let key: UInt64 }
    static let takes: [Take] = {
        var out: [Take] = []
        for (g, c, lines) in script {
            guard let ctx = Ctx(rawValue: c), let vs = groups[g] else { continue }
            for v in vs { for t in lines { out.append(Take(voice: v, ctx: ctx, text: t, key: hashKey(v, t))) } }
        }
        return out
    }()
    // voice -> context -> take ids.
    static let index: [String: [Ctx: [Int]]] = {
        var d: [String: [Ctx: [Int]]] = [:]
        for (i, t) in takes.enumerated() { d[t.voice, default: [:]][t.ctx, default: []].append(i) }
        return d
    }()

    static func hashKey(_ voice: String, _ text: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in "\(voice)|\(text)".utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    // MARK: Who speaks with which voice

    static func voice(_ m: Mob) -> String {
        let v = m.villager
        let woman = Townsfolk.isWoman(v)
        let s = woman ? "_f" : "_m"
        if m.baby { return "child" }
        switch v?.role ?? "worker" {
        case "sheriff": return "sheriff"
        case "deputy": return "deputy" + s
        case "child": return "child"
        case "elder": return "elder" + s
        case "farmer": return "farmer" + s
        case "shopkeeper": return (v?.shopKind == .saloon || v?.shopKind == .butcher ? "chef" : "keeper") + s
        default: return "folk" + s
        }
    }

    // A line for this person in this context (never the same twice running for one voice). Nil: the voice has none
    // (always in the speaker's own voice: no borrowed lines that would have no take).
    private static var lastTake: [String: Int] = [:]
    static func line(_ ctx: Ctx, _ m: Mob) -> (String, Int)? {
        let vk = voice(m)
        guard let ids = index[vk]?[ctx], !ids.isEmpty else { return nil }
        var pick = ids[Rand.int(in: 0...(ids.count - 1))]
        if ids.count > 1 && pick == lastTake[vk] { pick = ids[(ids.firstIndex(of: pick)! + 1) % ids.count] }
        lastTake[vk] = pick
        return (takes[pick].text, pick)
    }

    // Says a line for the context: a toast (or subtitle) and the recorded take at the speaker.
    @discardableResult
    static func speak(_ g: Game, _ m: Mob, _ ctx: Ctx) -> String? {
        guard let (text, _) = line(ctx, m) else { return nil }
        Townsfolk.say(g, m, text)
        return text
    }

    // The same, unless someone in town spoke within `gap` seconds (shop chatter, goodbyes).
    static func speakSoon(_ g: Game, _ m: Mob, _ ctx: Ctx, gap: Double = 3) {
        guard g.clock - Townsfolk.townLastLine > gap else { return }
        speak(g, m, ctx)
    }

    // MARK: Playback (Townsfolk.say calls this for every line)

    static var captions: [Int: String] = [:]
    static var played = 0                     // takes played (TownTests)
    static var murmured = 0                   // text-only lines voiced with a murmur

    // Returns true when a recorded take played.
    @discardableResult
    static func play(_ g: Game, _ m: Mob, _ text: String) -> Bool {
        let vk = voice(m)
        let key = hashKey(vk, text)
        if let id = takeID[key], clip(key) != nil {
            captions[id] = "\(m.villager.map { Townsfolk.first($0) } ?? "Townsperson"): \(text)"
            played += 1
            g.sfx(.voice(id), 1, at: m.eye)
            return true
        }
        murmured += 1
        g.sfx(m.baby ? .babyMob(.villager, .ambient) : .mob(.villager, .ambient), 0.5, at: m.eye)
        return false
    }
    static let takeID: [UInt64: Int] = {
        var d: [UInt64: Int] = [:]
        for (i, t) in takes.enumerated() { d[t.key] = i }
        return d
    }()

    static func caption(_ id: Int) -> String? {
        captions[id] ?? (id >= 0 && id < takes.count ? "\u{201C}\(takes[id].text)\u{201D}" : nil)
    }

    // MARK: The take bank (Resources/voices.bin)

    // File: "BSV1", u32 count, then per take u64 key, u32 rate, u32 samples, u32 offset, u32 bytes (offsets from the
    // start of the file); each take's data: i16 first predictor, u8 step index, u8 0, then 4-bit IMA-ADPCM codes,
    // low nibble first.
    struct Entry { let rate: Int; let samples: Int; let offset: Int; let bytes: Int }
    private static var data = Data()
    private static var entries: [UInt64: Entry] = [:]
    private static var tried = false
    private static let lock = NSLock()

    static var loaded: Int { ensure(); return entries.count }
    static var bankBytes: Int { ensure(); return data.count }

    // The Quest hands the APK asset over at launch; the Mac reads the app bundle (or Resources/ in a checkout).
    static func load(_ d: Data?) {
        lock.lock(); defer { lock.unlock() }
        tried = true
        guard let d, d.count >= 8, d.prefix(4) == Data("BSV1".utf8) else { return }
        func u32(_ o: Int) -> Int { Int(d[d.startIndex + o]) | Int(d[d.startIndex + o + 1]) << 8 | Int(d[d.startIndex + o + 2]) << 16 | Int(d[d.startIndex + o + 3]) << 24 }
        let n = u32(4)
        var e: [UInt64: Entry] = [:]
        for i in 0..<n {
            let o = 8 + i * 24
            guard o + 24 <= d.count else { break }
            let key = UInt64(u32(o)) | UInt64(u32(o + 4)) << 32
            let en = Entry(rate: u32(o + 8), samples: u32(o + 12), offset: u32(o + 16), bytes: u32(o + 20))
            if en.offset + en.bytes <= d.count && en.bytes >= 4 { e[key] = en }
        }
        data = Data(d)
        entries = e
    }

    static func ensure() {
        lock.lock()
        let done = tried
        lock.unlock()
        if done { return }
        var paths: [String] = []
        if let r = Bundle.main.resourcePath { paths.append(r + "/voices.bin") }
        paths.append(FileManager.default.currentDirectoryPath + "/Resources/voices.bin")
        for p in paths { if let d = FileManager.default.contents(atPath: p) { load(d); return } }
        lock.lock(); tried = true; lock.unlock()
    }

    static func clip(_ key: UInt64) -> Entry? {
        ensure()
        lock.lock(); defer { lock.unlock() }
        return entries[key]
    }

    static let stepTable: [Int32] = [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80,
        88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963,
        1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132,
        7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767]
    static let indexTable: [Int32] = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]

    // Decoded samples (-1...1) at the take's own rate.
    static func decode(_ key: UInt64) -> (rate: Int, pcm: [Float])? {
        guard let e = clip(key) else { return nil }
        lock.lock(); let d = data; lock.unlock()
        let b0 = d.startIndex + e.offset
        var pred = Int32(Int16(bitPattern: UInt16(d[b0]) | UInt16(d[b0 + 1]) << 8))
        var idx = Int32(min(88, Int(d[b0 + 2])))
        var out = [Float](repeating: 0, count: e.samples)
        out[0] = Float(pred) / 32768
        var n = 1
        var byte = b0 + 4
        let end = b0 + e.bytes
        while n < e.samples && byte < end {
            let b = d[byte]
            for code in [Int32(b & 15), Int32(b >> 4)] where n < e.samples {
                let step = stepTable[Int(idx)]
                var diff = step >> 3
                if code & 4 != 0 { diff += step }
                if code & 2 != 0 { diff += step >> 1 }
                if code & 1 != 0 { diff += step >> 2 }
                pred += code & 8 != 0 ? -diff : diff
                pred = max(-32768, min(32767, pred))
                idx = max(0, min(88, idx + indexTable[Int(code)]))
                out[n] = Float(pred) / 32768
                n += 1
            }
            byte += 1
        }
        return (e.rate, out)
    }

    // The take at the sound bank's rate (linear resampling), with 4 ms fades so it starts and ends at zero.
    static func render(_ id: Int) -> [Float] {
        guard id >= 0 && id < takes.count, let (rate, x) = decode(takes[id].key), x.count > 1 else { return [] }
        let r = Double(rate) / SoundBank.rate
        let m = Int(Double(x.count) / r)
        var out = [Float](repeating: 0, count: m)
        for i in 0..<m {
            let t = Double(i) * r
            let k = Int(t)
            let f = Float(t - Double(k))
            let a = x[min(k, x.count - 1)], b = x[min(k + 1, x.count - 1)]
            out[i] = a + (b - a) * f
        }
        let fade = min(m / 4, Int(SoundBank.rate * 0.004))
        for i in 0..<fade {
            let g = Float(i) / Float(fade)
            out[i] *= g; out[m - 1 - i] *= g
        }
        return out
    }
}
