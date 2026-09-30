import Foundation
import simd

// Game-side audio: listener + occlusion, looping emitters found by scanning the blocks around the
// player (fire, lava, water, portals, beacons, spawners), weather and biome beds, cave stings,
// the block-sound helpers used by the rest of the game, and the music director.

final class AudioState {
    var scanTimer: Float = 0
    var emitters: [String: (pos: V3, count: Int)] = [:]
    var caveBiome = 0                       // 0 none, 1 deep dark, 2 lush, 3 dripstone
    var enclosure: Float = 0                // fraction of probe rays that hit a solid block (0 open air ... 1 sealed room)
    var roomSize: Float = 24                // mean free distance of the probe rays (blocks)
    var cave: Float = 0                     // smoothed 0 open sky ... 1 underground
    var caveTimer: Float = 25
    var moodTimer: Float = 40
    var rainExposure: Float = 0
    var rainTimer: Float = 0
    var asked: Set<String> = []
    var lastHurtSound: Float = -10
    var stepTimer: Float = 0
    var discPlaying: JukeboxPlayer? = nil
    var armorSeen: [ItemID] = [0, 0, 0, 0]
    var biomeTimer: Float = 0
    var biomeHere: Biome = .plains
    var nearOcean = false
    var armorPrimed = false
    static var kindTable: [UInt8] = []      // block id -> emitter kind (built once)
}

final class MusicDirector {
    var wait: Float = Float.random(in: 60...150)
    var mood: MusicMood? = nil              // mood of the piece being played
    var pieces = 0
    var silence: Float = 0                  // seconds of forced silence after a fade-out
    var lastWant: MusicMood? = nil
}

extension Game {
    // MARK: Emitter table

    static func audioKind(_ id: BlockID) -> UInt8 {
        var t = AudioState.kindTable
        if t.isEmpty {
            t = [UInt8](repeating: 0, count: Blocks.count)
            for i in 0..<Blocks.count {
                let id = BlockID(i)
                let k = Blocks.key(Blocks.groupBase[i])
                let raw = Blocks.key(id)
                var kind: UInt8 = 0
                if k == "fire" || k == "soul_fire" { kind = 1 }
                else if k.hasSuffix("campfire") { kind = 2 }
                else if raw.hasPrefix("lit_") { kind = 3 }
                else if k == "lava" || raw.hasPrefix("lava") { kind = 4 }
                else if k == "water" || raw.hasPrefix("water") { kind = 5 }
                else if k == "nether_portal" { kind = 6 }
                else if k == "beacon" { kind = 7 }
                else if k == "spawner" || k == "trial_spawner" { kind = 8 }
                else if k.hasPrefix("sculk") { kind = 9 }
                else if k == "moss_block" || k == "moss_carpet" || k.hasPrefix("cave_vines") || k == "big_dripleaf" || k == "spore_blossom" { kind = 10 }
                else if k == "dripstone_block" || k == "pointed_dripstone" { kind = 11 }
                else if k == "end_portal" || k == "end_gateway" { kind = 12 }
                else if k == "respawn_anchor" { kind = 13 }
                else if k == "bubble_column" || k == "magma_block" { kind = 14 }
                else if k == "firefly_bush" { kind = 15 }
                else if k == "short_dry_grass" || k == "tall_dry_grass" { kind = 16 }
                else if k == "creaking_heart" { kind = 17 }
                t[i] = kind
            }
            AudioState.kindTable = t
        }
        return Int(id) < t.count ? t[Int(id)] : 0
    }

    // Solid blocks between two points, 0...1 (five or more blocks fully muffle).
    func audioOcclusion(_ from: V3, _ to: V3) -> Float {
        let d = to - from
        let len = simd_length(d)
        if len < 1.5 { return 0 }
        let steps = min(24, Int(len / 0.6) + 1)
        var solid = 0
        for i in 1..<steps {
            let p = from + d * (Float(i) / Float(steps))
            if Blocks.opaque[Int(world.block(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))))] { solid += 1 }
        }
        return min(1, Float(solid) / 5)
    }

    // The block sound helpers the rest of the game calls.
    func blockSound(_ s: Snd, at p: IVec3, _ v: Float = 1) { sfx(s, v, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5) }
    func soundCenter(_ p: IVec3) -> V3 { V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5 }

    // MARK: Per-tick

    func audioAmbientTick(_ dt: Float) {
        guard let snd = sound else { return }
        let a = audio
        let p = player.pos
        let eye = player.eye
        // Cave factor from sky light at the eye (smoothed); fixed per dimension elsewhere.
        var caveTarget: Float
        switch dim.dim {
        case .overworld:
            let l = world.lightAt(Int(floor(eye.x)), Int(floor(eye.y)), Int(floor(eye.z)))
            caveTarget = 1 - Float(l.sky) / 15
            if eye.y > Float(SEA + 40) { caveTarget *= 0.5 }
        case .nether: caveTarget = 0.7
        case .end: caveTarget = 0.2
        }
        a.cave += (caveTarget - a.cave) * min(1, dt * 1.5)
        // Reverb follows the space around the listener: how enclosed it is and how big.
        let wet: Float = max(a.enclosure * a.enclosure, a.cave * 0.6)
        snd.setListener(eye: eye, yaw: player.yaw, pitch: player.pitch, cave: wet, underwater: player.headInWater)
        snd.setRoom(size: a.roomSize, enclosure: a.enclosure)

        // Scan the blocks around the player for looping emitters twice a second.
        a.scanTimer -= dt
        if a.scanTimer <= 0 {
            a.scanTimer = 0.5
            audioScan()
        }
        a.asked.removeAll(keepingCapacity: true)
        func ask(_ key: String, _ s: Snd, _ v: Float, at pos: V3? = nil) {
            guard v > 0.001 else { return }
            a.asked.insert(key)
            if v > 0.15 && AudioSettings.subtitles { subtitle(s, at: pos) }
            let occ = pos.map { audioOcclusion(eye, $0) } ?? 0
            snd.loop(key, s, volume: v * max(0.15, 1 - occ * 0.7), at: pos, occlusion: occ)
        }
        func emitter(_ kind: String, _ s: Snd, base: Float, per: Float, cap: Float = 1.2) {
            if let e = a.emitters[kind] {
                let d = simd_length(e.pos - eye)
                let v = min(cap, base + per * Float(e.count)) * max(0, 1 - d / 14)
                ask(kind, s, v, at: e.pos)
            }
        }
        emitter("fire", .fireLoop, base: 0.45, per: 0.08)
        emitter("campfire", .campfireLoop, base: 0.5, per: 0.1)
        emitter("furnace", .furnaceLoop, base: 0.4, per: 0.08)
        emitter("lava", .lavaLoop, base: 0.35, per: 0.02, cap: 1.0)
        emitter("water", .waterLoop, base: 0.15, per: 0.01, cap: 0.6)
        emitter("portal", .portalLoop, base: 0.5, per: 0.02, cap: 0.8)
        emitter("beacon", .beaconLoop, base: 0.35, per: 0.1, cap: 0.6)
        emitter("spawner", .spawnerLoop, base: 0.4, per: 0.1, cap: 0.7)
        emitter("anchor", .respawnAnchorLoop, base: 0.3, per: 0.1, cap: 0.5)
        emitter("bubbles", .underwaterLoop, base: 0.2, per: 0.02, cap: 0.5)
        // Fireflies glitter at night; dry grass rustles by day; a Barkwraith heart creaks now and then.
        let isNight = dayFraction > 0.52 && dayFraction < 0.98
        if isNight { emitter("fireflies", .fireflyLoop, base: 0.3, per: 0.05, cap: 0.6) }
        if let e = a.emitters["drygrass"], !isNight, Float.random(in: 0..<1) < dt * min(0.3, 0.05 + 0.01 * Float(e.count)) {
            sfx(.dryGrassRustle, 0.5, at: e.pos + V3(Float.random(in: -2...2), 0.3, Float.random(in: -2...2)))
        }
        if let e = a.emitters["heart"], Float.random(in: 0..<1) < dt / 6 { sfx(.heartCreak, 0.8, at: e.pos) }
        // Lava pops now and then; drips near driprock.
        if let e = a.emitters["lava"], simd_length(e.pos - eye) < 12, Float.random(in: 0..<1) < dt * min(1.5, 0.3 + 0.05 * Float(e.count)) {
            let j = V3(Float.random(in: -2...2), 0.4, Float.random(in: -2...2))
            sfx(.lavaPop, 0.7, at: e.pos + j)
        }
        if a.caveBiome == 3 && Float.random(in: 0..<1) < dt * 0.25 {
            let j = V3(Float.random(in: -6...6), Float.random(in: 0...3), Float.random(in: -6...6))
            sfx(.caveDrip, 0.4, at: eye + j)
        }

        // Weather.
        if dim.dim == .overworld && weather.rain > 0.05 {
            a.rainTimer -= dt
            if a.rainTimer <= 0 {
                a.rainTimer = 0.6
                var exposed = 0, total = 0
                for dz in stride(from: -8, through: 8, by: 4) { for dx in stride(from: -8, through: 8, by: 4) {
                    let x = Int(floor(p.x)) + dx, z = Int(floor(p.z)) + dz
                    total += 1
                    if precipitation(x, Int(p.y), z) == 1 && skyExposed(x, Int(p.y), z) { exposed += 1 }
                } }
                a.rainExposure = Float(exposed) / Float(max(1, total))
            }
            let r = weather.rain
            ask("rain", .rain, r * min(1, a.rainExposure * 1.6) * 0.9)
            // Under a roof near the surface: rain on the roof instead.
            if a.rainExposure < 0.5 && a.cave < 0.9 { ask("rainroof", .rainRoof, r * (1 - a.rainExposure) * (1 - a.cave) * 0.6) }
        }
        // Player state loops.
        if player.headInWater { ask("underwater", .underwaterLoop, 0.9) }
        if player.gliding { ask("glide", .elytraLoop, min(1, simd_length(player.vel) / 28)) }
        if let r = riding, r.kind == .minecart { ask("cart", .minecartLoop, min(1, simd_length(r.vel) / 8 + 0.1)) }

        // Biome beds.
        switch dim.dim {
        case .nether:
            let b = world.gen.column(Int(floor(p.x)), Int(floor(p.z))).biome
            let s: Snd
            switch b {
            case .soulSandValley: s = .soulValleyLoop
            case .crimsonForest: s = .crimsonLoop
            case .warpedForest: s = .warpedLoop
            case .basaltDeltas: s = .basaltLoop
            default: s = .netherWastesLoop
            }
            ask("bed", s, 0.5)
        case .end: ask("bed", .endLoop, 0.45)
        case .overworld:
            if a.cave > 0.6 && a.caveBiome > 0 {
                ask("bed", a.caveBiome == 1 ? .deepDarkLoop : (a.caveBiome == 2 ? .lushLoop : .dripstoneLoop), 0.45 * a.cave)
            }
            if a.cave < 0.6 && !player.headInWater { overworldAmbience(dt, open: 1 - a.cave, ask: ask) }
        }

        // Stings: cave noises in the dark, nether moods, underwater moans.
        a.caveTimer -= dt
        if a.caveTimer <= 0 {
            a.caveTimer = Float.random(in: 18...55)
            let ang = Float.random(in: 0..<(2 * .pi))
            let off = V3(cosf(ang), Float.random(in: -0.3...0.3), sinf(ang)) * Float.random(in: 5...9)
            if player.headInWater {
                if Float.random(in: 0..<1) < 0.5 { sfx(.underwaterMood, 0.5, at: eye + off) }
            } else if dim.dim == .nether {
                if Float.random(in: 0..<1) < 0.4 { sfx(.netherMood, 0.5, at: eye + off) }
            } else if dim.dim == .overworld && a.cave > 0.75 {
                let l = world.lightAt(Int(floor(eye.x)), Int(floor(eye.y)), Int(floor(eye.z)))
                if l.block < 6 && Float.random(in: 0..<1) < 0.6 {
                    let s: Snd = [.caveAmbience, .caveAmbience, .caveDrip, .caveWind].randomElement()!
                    sfx(s, s == .caveDrip ? 0.5 : 0.7, at: eye + off)
                }
            } else if dim.dim == .overworld && eye.y > Float(SEA + 60) && Float.random(in: 0..<1) < 0.5 {
                sfx(.windGust, 0.5, at: eye + off)      // high peaks
            }
        }
        // Armor put on (any path: menus, shift-click, dispensers): the material's equip sound.
        for i in 0..<min(4, inventory.armor.count) {
            let it = inventory.armor[i].isEmpty ? 0 : inventory.armor[i].item
            if it != a.armorSeen[i] {
                if a.armorPrimed && it != 0 { sfx(.armorEquip(Game.armorSoundTier(Items.key(it))), 0.8) }
                a.armorSeen[i] = it
            }
        }
        a.armorPrimed = true
        // Jukebox nearby: duck the background music.
        let jukeboxNear = a.discPlaying != nil
        snd.musicDuck += ((jukeboxNear ? 0 : 1) - snd.musicDuck) * min(1, dt * 2)
        snd.update(dt, asked: a.asked)
    }

    // Surface ambience by biome and time of day: birds and owls, crickets, frogs, surf, wind, jungle insects.
    private func overworldAmbience(_ dt: Float, open: Float, ask: (String, Snd, Float, V3?) -> Void) {
        let a = audio
        let p = player.pos
        a.biomeTimer -= dt
        if a.biomeTimer <= 0 {
            a.biomeTimer = 2
            a.biomeHere = world.gen.column(Int(floor(p.x)), Int(floor(p.z))).biome
            // Surf: any ocean column within 24 blocks.
            var ocean = false
            for (dx, dz) in [(24, 0), (-24, 0), (0, 24), (0, -24), (16, 16), (-16, -16), (16, -16), (-16, 16), (0, 0)] {
                let b = world.gen.column(Int(floor(p.x)) + dx, Int(floor(p.z)) + dz).biome
                if [.ocean, .deepOcean, .warmOcean, .lukewarmOcean, .deepLukewarmOcean, .coldOcean, .deepColdOcean].contains(b) { ocean = true; break }
            }
            a.nearOcean = ocean
        }
        let b = a.biomeHere
        let f = Float(dayFraction)
        let day: Float = f < 0.02 || f > 0.48 ? 0 : 1                 // birds from sunrise to sunset
        let night: Float = f > 0.52 && f < 0.98 ? 1 : 0
        let wet: Float = 1 - min(1, weather.rain * 1.5)                // rain hushes the wildlife
        let high = p.y > Float(SEA + 50)
        let snowy: Set<Biome> = [.snowyPlains, .iceSpikes, .snowyTaiga, .snowySlopes, .frozenPeaks, .jaggedPeaks, .grove, .snowyBeach, .frozenRiver, .frozenOcean, .deepFrozenOcean]
        let dry: Set<Biome> = [.desert, .badlands, .erodedBadlands, .woodedBadlands]
        let wooded: Set<Biome> = [.forest, .flowerForest, .birchForest, .oldGrowthBirchForest, .darkForest, .taiga, .oldGrowthPineTaiga, .oldGrowthSpruceTaiga,
                                  .windsweptForest, .cherryGrove, .meadow, .plains, .sunflowerPlains, .savanna, .savannaPlateau, .river, .paleGarden]
        let jungle: Set<Biome> = [.jungle, .sparseJungle, .bambooJungle]
        let swamp: Set<Biome> = [.swamp, .mangroveSwamp]
        if a.nearOcean { ask("surf", .oceanLoop, 0.55 * open, nil) }
        if high || snowy.contains(b) || dry.contains(b) { ask("wind", .windLoop, (high ? 0.6 : 0.35) * open, nil) }
        if jungle.contains(b) { ask("jungle", .jungleLoop, (0.5 * day + 0.35 * night) * wet * open, nil) }
        if swamp.contains(b) { ask("swamp", .swampLoop, (0.2 + 0.4 * night) * wet * open, nil) }
        if night > 0 && !snowy.contains(b) && !dry.contains(b) && !jungle.contains(b) && !high {
            ask("crickets", .cricketsLoop, 0.3 * wet * open, nil)
        }
        // Stings: birdsong by day in wooded land, an owl at night in forests.
        if wooded.contains(b) || jungle.contains(b) {
            let rate: Float = (jungle.contains(b) ? 0.5 : 0.25) * day * wet * open
            if Float.random(in: 0..<1) < dt * rate {
                let ang = Float.random(in: 0..<(2 * .pi))
                let at = player.eye + V3(cosf(ang) * Float.random(in: 5...14), Float.random(in: 2...7), sinf(ang) * Float.random(in: 5...14))
                sfx(.birdCall, 0.6, at: at)
            }
            if night > 0 && Float.random(in: 0..<1) < dt * 0.02 * wet * open {
                let ang = Float.random(in: 0..<(2 * .pi))
                sfx(.owlHoot, 0.7, at: player.eye + V3(cosf(ang) * 12, 4, sinf(ang) * 12))
            }
        }
    }

    // Finds the nearest block of each emitter kind (and how many there are) within 8 blocks.
    private func audioScan() {
        let a = audio
        let eye = player.eye
        let cx = Int(floor(eye.x)), cy = Int(floor(eye.y)), cz = Int(floor(eye.z))
        var best: [Int: (V3, Float, Int)] = [:]      // kind -> (pos, dist², count)
        var sculk = 0, moss = 0, drip = 0
        for y in (cy - 5)...(cy + 5) { for z in (cz - 8)...(cz + 8) { for x in (cx - 8)...(cx + 8) {
            let b = world.block(x, y, z)
            if b == AIR { continue }
            let k = Int(Game.audioKind(b))
            if k == 0 { continue }
            if k == 9 { sculk += 1; continue }
            if k == 10 { moss += 1; continue }
            if k == 11 { drip += 1; continue }
            var kind = k
            if k == 5 {
                // Still water only counts at its surface; flowing water everywhere.
                let above = world.block(x, y + 1, z)
                let flowing = Blocks.groupBase[Int(b)] != b
                if !flowing && above != AIR { continue }
                kind = 5
            }
            let c = V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
            let d2 = simd_length_squared(c - eye)
            if let cur = best[kind] {
                best[kind] = (d2 < cur.1 ? c : cur.0, min(d2, cur.1), cur.2 + 1)
            } else {
                best[kind] = (c, d2, 1)
            }
        } } }
        let names = [1: "fire", 2: "campfire", 3: "furnace", 4: "lava", 5: "water", 6: "portal", 7: "beacon", 8: "spawner", 12: "portal", 13: "anchor", 14: "bubbles",
                     15: "fireflies", 16: "drygrass", 17: "heart"]
        var out: [String: (pos: V3, count: Int)] = [:]
        for (k, v) in best { if let n = names[k] { if let e = out[n] { out[n] = (e.pos, e.count + v.2) } else { out[n] = (v.0, v.2) } } }
        a.emitters = out
        a.caveBiome = sculk >= 4 ? 1 : (moss >= 4 ? 2 : (drip >= 4 ? 3 : 0))
        // Room probe: 14 rays (6 axes + 8 diagonals) up to 24 blocks.
        var hits = 0
        var total: Float = 0
        for d in Game.probeDirs {
            var t: Float = 1
            var hit = false
            while t < 24 {
                let q = eye + d * t
                if Blocks.opaque[Int(world.block(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z))))] { hit = true; break }
                t += 1
            }
            if hit { hits += 1 }
            total += t
        }
        let enc = Float(hits) / Float(Game.probeDirs.count)
        a.enclosure += (enc - a.enclosure) * 0.5
        a.roomSize += (total / Float(Game.probeDirs.count) - a.roomSize) * 0.5
    }

    static let probeDirs: [V3] = {
        var d: [V3] = [V3(1, 0, 0), V3(-1, 0, 0), V3(0, 1, 0), V3(0, -1, 0), V3(0, 0, 1), V3(0, 0, -1)]
        for x in [-1, 1] { for y in [-1, 1] { for z in [-1, 1] { d.append(simd_normalize(V3(Float(x), Float(y), Float(z)))) } } }
        return d
    }()

    // MARK: Music director

    // The mood the music should be in right now.
    func musicMood() -> MusicMood {
        if let pm = menu as? PauseMenu, pm.page == .title { return .title }
        switch dim.dim {
        case .nether: return .ember
        case .end: return .hollow
        case .overworld: break
        }
        if mobs.mobs.contains(where: { $0.kind == .wither && $0.health > 0 && simd_length($0.pos - player.pos) < 80 }) { return .boss }
        if player.headInWater { return .underwater }
        if audio.cave > 0.85 && player.pos.y < Float(SEA - 6) { return .underground }
        if !survival { return .creative }
        if weather.rain > 0.6 { return .rain }
        let f = dayFraction
        if f >= 0.5 { return .night }
        // Daytime flavour by biome.
        switch audio.biomeHere {
        case .snowyPlains, .iceSpikes, .snowyTaiga, .snowySlopes, .frozenPeaks, .jaggedPeaks, .grove, .snowyBeach, .frozenRiver: return .snow
        case .desert, .badlands, .erodedBadlands, .woodedBadlands: return .desert
        case .ocean, .deepOcean, .warmOcean, .lukewarmOcean, .deepLukewarmOcean, .coldOcean, .deepColdOcean, .frozenOcean, .deepFrozenOcean, .beach: return .ocean
        case .cherryGrove, .meadow, .flowerForest, .sunflowerPlains: return .grove
        default: return .day
        }
    }

    func musicTick(_ dt: Float) {
        guard let snd = sound, let stream = snd.music else { return }
        let m = music
        let want = musicMood()
        // Some moods take over at once (dimension change, boss, the title screen); the rest wait their turn.
        let hard: Set<MusicMood> = [.title, .ember, .hollow, .boss]
        if let cur = m.mood, stream.isPlaying {
            let curHard = hard.contains(cur), wantHard = hard.contains(want)
            if cur != want && (curHard || wantHard) && !(cur == .title && want == .creative) {
                stream.stop(fade: 2.5)
                m.mood = nil
                m.silence = want == .title ? 1 : Float.random(in: 4...10)
                // Entering a dimension or a boss fight scores at once; leaving the title screen gives the world a quiet minute.
                m.wait = hard.contains(want) ? 0 : Float.random(in: 30...90)
            }
            return
        }
        if m.mood != nil && !stream.isPlaying {
            // The piece ended by itself.
            m.mood = nil
            m.wait = want == .title ? Float.random(in: 8...20) : Float.random(in: 360...900)
        }
        if want == .title && m.wait > 2 { m.wait = 2 }
        // Arriving in the Emberdeep or the Hollow (or a boss appearing) with nothing playing: score it soon.
        if want != m.lastWant && hard.contains(want) && m.wait > 6 { m.wait = Float.random(in: 3...6) }
        m.lastWant = want
        if m.silence > 0 { m.silence -= dt; return }
        m.wait -= dt
        if m.wait <= 0 && AudioSettings.volume(.music) > 0 {
            let seed = UInt64.random(in: 0...UInt64(Int32.max))
            let score = Composer.compose(want, seed: seed)
            stream.play(score, fadeIn: want == .boss ? 0.5 : 3)
            m.mood = want
            m.pieces += 1
            if want != .title { onToast?("♪ \(score.title)") }
        }
    }
}

// Music disc rendering: discs become scores on the same engine (original pieces, seeded by the disc's name).
extension MusicDiscs {
    static func score(_ name: String) -> MusicScore {
        var h: UInt64 = 0xcbf29ce484222325
        for b in name.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        let moods: [MusicMood] = [.day, .night, .creative, .rain, .title, .hollow, .ember]
        var s = Composer.compose(moods[Int(h % UInt64(moods.count))], seed: h)
        let len = Float(all.first { $0.0 == name }?.2 ?? 120)
        // Long discs repeat the piece (a second pass one step up) until the disc's length.
        let piece = s.notes, span = max(30, s.length - 4)
        var k = 1
        while Float(k) * span < len - 4 {
            let off = Float(k) * span, lift = Float(k % 2 == 1 ? 2 : 0)
            s.notes += piece.map { n in var m = n; m.t += off; m.midi += lift; return m }
            k += 1
        }
        s.notes = s.notes.filter { $0.t < len - 4 }
        if name.hasSuffix("music_box") {
            // A music box: only the tuned parts, up an octave, on a tiny plucked comb.
            s.notes = s.notes.filter { ![.bass, .kick, .tom, .shaker, .thud, .drone, .pad].contains($0.inst) }.map { n in
                var m = n; m.inst = .bell; m.midi += 12; m.dur = min(m.dur, 0.6); m.vel *= 0.8; return m
            }
        }
        s.length = len
        s.title = title(name)
        return s
    }
}
