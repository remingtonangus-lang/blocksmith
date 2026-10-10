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
    var rainNear: Float = 0                 // share of nearby columns where it rains (not snows)
    var rainTimer: Float = 0
    var asked: Set<String> = []
    var lastHurtSound: Float = -10
    var stepTimer: Float = 0
    var discPlaying: JukeboxPlayer? = nil
    var armorSeen: [ItemID] = [0, 0, 0, 0]
    var biomeTimer: Float = 0
    var paddleTimer: Float = 0
    var ships: [Int: ShipAudioState] = [:]
    var rockTimer: Float = 60
    var combatHold: Float = 0               // combat music lingers this long after the last sign of a fight
    var combatCheck: Float = 0
    var warmed = Set<String>()              // sound groups already sent to the background renderer
    var combat = 0                          // 0 calm, 1 near a garrison, 2 fighting (soldiers aggro / raid wave)
    var record: [String: Int]? = nil        // harness: counts of every sound played while set
    var leafCover: Float = 0                // leaves overhead (rain on leaves)
    var biomeHere: Biome = .plains
    var nearOcean = false
    var armorPrimed = false
    static var kindTable: [UInt8] = []      // block id -> emitter kind (built once)
}

final class MusicDirector {
    // Moods that cut in at once (built once: musicTick runs every frame).
    static let hardMoods: Set<MusicMood> = [.title, .ember, .hollow, .boss, .combat, .tension]
    var wait: Float = Rand.float(in: 60...150)
    var mood: MusicMood? = nil              // mood of the piece being played
    var pieces = 0
    var silence: Float = 0                  // seconds of forced silence after a fade-out
    var lastWant: MusicMood? = nil
    var customOn = false                    // one of the player's own tracks is playing (CustomMusic.swift)
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
                else if k == "beehive" || k == "bee_nest" { kind = 18 }
                else if k.hasSuffix("leaves") { kind = 21 }
                else if k == "corner_lamp" || k == "data_cabinet" { kind = 22 }      // Boreal Station machinery
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
        // Headless harnesses set `audio.record` to run the director without an audio device: loops asked
        // for are then counted under their key (as "loop:<key>").
        let snd = sound
        guard snd != nil || audio.record != nil else { return }
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
        case .nether, .deep: caveTarget = 0.7
        case .end: caveTarget = 0.2
        }
        a.cave += (caveTarget - a.cave) * min(1, dt * 1.5)
        // Reverb follows the space around the listener: how enclosed it is and how big.
        let wet: Float = max(a.enclosure * a.enclosure, a.cave * 0.6)
        snd?.setListener(eye: eye, yaw: player.yaw, pitch: player.pitch, cave: wet, underwater: player.headInWater)
        snd?.setRoom(size: a.roomSize, enclosure: a.enclosure)

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
            if a.record != nil { a.record!["loop:" + key, default: 0] += 1 }
            snd?.loop(key, s, volume: v * max(0.15, 1 - occ * 0.7), at: pos, occlusion: occ)
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
        emitter("hive", .hiveLoop, base: 0.35, per: 0.1, cap: 0.6)
        emitter("stationhum", .stationHumLoop, base: 0.2, per: 0.01, cap: 0.45)
        if let e = a.emitters["drygrass"], !isNight, Rand.float(in: 0..<1) < dt * min(0.3, 0.05 + 0.01 * Float(e.count)) {
            sfx(.dryGrassRustle, 0.5, at: e.pos + V3(Rand.float(in: -2...2), 0.3, Rand.float(in: -2...2)))
        }
        if let e = a.emitters["heart"], Rand.float(in: 0..<1) < dt / 6 { sfx(.heartCreak, 0.8, at: e.pos) }
        // Lava pops now and then; drips near driprock.
        if let e = a.emitters["lava"], simd_length(e.pos - eye) < 12, Rand.float(in: 0..<1) < dt * min(1.5, 0.3 + 0.05 * Float(e.count)) {
            let j = V3(Rand.float(in: -2...2), 0.4, Rand.float(in: -2...2))
            sfx(.lavaPop, 0.7, at: e.pos + j)
        }
        if a.caveBiome == 3 && Rand.float(in: 0..<1) < dt * 0.25 {
            let j = V3(Rand.float(in: -6...6), Rand.float(in: 0...3), Rand.float(in: -6...6))
            sfx(.caveDrip, 0.4, at: eye + j)
        }

        // Weather.
        if dim.dim == .overworld && weather.rain > 0.05 {
            a.rainTimer -= dt
            if a.rainTimer <= 0 {
                a.rainTimer = 0.6
                var exposed = 0, raining = 0, total = 0
                for dz in stride(from: -8, through: 8, by: 4) { for dx in stride(from: -8, through: 8, by: 4) {
                    let x = Int(floor(p.x)) + dx, z = Int(floor(p.z)) + dz
                    total += 1
                    guard precipitation(x, Int(p.y), z) == 1 else { continue }
                    raining += 1
                    if skyExposed(x, Int(p.y), z) { exposed += 1 }
                } }
                a.rainExposure = Float(exposed) / Float(max(1, total))
                a.rainNear = Float(raining) / Float(max(1, total))
            }
            let r = weather.rain
            ask("rain", .rain, r * min(1, a.rainExposure * 1.6) * 0.9)
            // Under a roof near the surface: rain on the roof instead (only where it rains, not snows).
            let roofed = max(0, a.rainNear - a.rainExposure)
            if a.rainExposure < 0.5 && a.cave < 0.9 && roofed > 0.3 { ask("rainroof", .rainRoof, r * roofed * (1 - a.cave) * 0.6) }
        }
        weatherAudioTick(dt, ask: ask)
        movingWaterTick(ask: ask)
        // Rockets and shells in flight: the nearest of each within 32 blocks.
        var rocket: (V3, Float)? = nil, shell: (V3, Float)? = nil
        for s in arms.slugs where s.kind == .rocket || s.kind == .shell {
            let d = simd_length(s.pos - eye)
            if d > 32 { continue }
            if s.kind == .rocket { if rocket == nil || d < rocket!.1 { rocket = (s.pos, d) } }
            else if shell == nil || d < shell!.1 { shell = (s.pos, d) }
        }
        if let r = rocket { ask("rocketflight", .rocketFlightLoop, 0.9 * (1 - r.1 / 32), at: r.0) }
        for sh in world.ships.shells {
            let d = simd_length(sh.pos - eye)
            if d < 32 && (shell == nil || d < shell!.1) { shell = (sh.pos, d) }
        }
        if let s = shell { ask("shellflight", .shellFlightLoop, 1.0 * (1 - s.1 / 32), at: s.0) }
        vehicleAudioTick(dt, ask: ask)
        // Player state loops.
        if player.headInWater { ask("underwater", .underwaterLoop, 0.9) }
        if player.jetThrust { ask("jetpack", .rocketFlightLoop, 0.85) }
        if player.gliding { ask("glide", .elytraLoop, min(1, simd_length(player.vel) / 28)) }
        if let r = riding, r.kind == .minecart { ask("cart", .minecartLoop, min(1, simd_length(r.vel) / 8 + 0.1)) }
        if let r = riding, r.kind == .boat {
            let spd = simd_length(V2(r.vel.x, r.vel.z))
            a.paddleTimer -= dt * min(1.5, spd / 3)
            if spd > 0.8 && a.paddleTimer <= 0 { a.paddleTimer = 0.9; sfx(.boatPaddle, 0.6, at: r.pos) }
        }

        // Biome beds.
        switch dim.dim {
        case .deep where !DeepGen.inHell(p.y): ask("bed", .basaltLoop, 0.4)
        case .nether, .deep:
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
            if a.cave < 0.6 && !player.headInWater {
                overworldAmbience(dt, open: 1 - a.cave, ask: ask)
                terrainAudioTick(dt, open: 1 - a.cave, ask: ask)
            }
        }

        // Stings: cave noises in the dark, nether moods, underwater moans.
        a.caveTimer -= dt
        if a.caveTimer <= 0 {
            a.caveTimer = Rand.float(in: 18...55)
            let ang = Rand.float(in: 0..<(2 * .pi))
            let off = V3(cosf(ang), Rand.float(in: -0.3...0.3), sinf(ang)) * Rand.float(in: 5...9)
            if player.headInWater {
                if Rand.float(in: 0..<1) < 0.5 { sfx(.underwaterMood, 0.5, at: eye + off) }
            } else if dim.dim == .nether {
                if Rand.float(in: 0..<1) < 0.4 { sfx(.netherMood, 0.5, at: eye + off) }
            } else if dim.dim == .overworld && a.cave > 0.75 {
                let l = world.lightAt(Int(floor(eye.x)), Int(floor(eye.y)), Int(floor(eye.z)))
                if l.block < 6 && Rand.float(in: 0..<1) < 0.6 {
                    let s: Snd = [.caveAmbience, .caveAmbience, .caveDrip, .caveWind].pick()!
                    sfx(s, s == .caveDrip ? 0.5 : 0.7, at: eye + off)
                }
            } else if dim.dim == .overworld && eye.y > Float(SEA + 60) && Rand.float(in: 0..<1) < 0.5 {
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
        guard let snd else { return }
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
        let snowy = AmbientBiomes.snowy
        let dry = AmbientBiomes.dry
        let wooded = AmbientBiomes.wooded
        let jungle = AmbientBiomes.jungle
        let swamp = AmbientBiomes.swamp
        if a.nearOcean { ask("surf", .oceanLoop, 0.55 * open, nil) }
        // Plain wind where no landform bed takes over (TerrainAudio: mountain howl on peaks, tundra whistle).
        let ownWind = AmbientBiomes.peaks.contains(b) || p.y - Float(SEA) > 60 || AmbientBiomes.tundra.contains(b)
        if (high || snowy.contains(b) || dry.contains(b)) && !ownWind { ask("wind", .windLoop, (high ? 0.6 : 0.35) * open, nil) }
        if jungle.contains(b) { ask("jungle", .jungleLoop, (0.5 * day + 0.35 * night) * wet * open, nil) }
        if swamp.contains(b) { ask("swamp", .swampLoop, (0.2 + 0.4 * night) * wet * open, nil) }
        if night > 0 && !snowy.contains(b) && !dry.contains(b) && !jungle.contains(b) && !high {
            ask("crickets", .cricketsLoop, 0.3 * wet * open, nil)
        }
        // Stings: birdsong by day in wooded land, an owl at night in forests.
        if wooded.contains(b) || jungle.contains(b) {
            let rate: Float = (jungle.contains(b) ? 0.5 : 0.25) * day * wet * open
            if Rand.float(in: 0..<1) < dt * rate {
                let ang = Rand.float(in: 0..<(2 * .pi))
                let at = player.eye + V3(cosf(ang) * Rand.float(in: 5...14), Rand.float(in: 2...7), sinf(ang) * Rand.float(in: 5...14))
                sfx(.birdCall, 0.6, at: at)
            }
            if night > 0 && Rand.float(in: 0..<1) < dt * 0.02 * wet * open {
                let ang = Rand.float(in: 0..<(2 * .pi))
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
        var sculk = 0, moss = 0, drip = 0, leaves = 0
        for y in (cy - 5)...(cy + 5) { for z in (cz - 8)...(cz + 8) { for x in (cx - 8)...(cx + 8) {
            let b = world.block(x, y, z)
            if b == AIR { continue }
            let k = Int(Game.audioKind(b))
            if k == 0 { continue }
            if k == 9 { sculk += 1; continue }
            if k == 10 { moss += 1; continue }
            if k == 11 { drip += 1; continue }
            if k == 21 { if y > cy { leaves += 1 }; continue }
            var kind = k
            if k == 5 {
                // Still water only counts at its surface; flowing water everywhere.
                let above = world.block(x, y + 1, z)
                let flowing = Blocks.groupBase[Int(b)] != b
                if !flowing && above != AIR { continue }
                // Falling water is a waterfall, other flowing water a stream, still water a lake or sea surface.
                kind = Blocks.key(b) == "water_falling" ? 20 : (flowing ? 19 : 5)
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
                     15: "fireflies", 16: "drygrass", 17: "heart", 18: "hive", 19: "river", 20: "waterfall", 22: "stationhum"]
        var out: [String: (pos: V3, count: Int)] = [:]
        for (k, v) in best { if let n = names[k] { if let e = out[n] { out[n] = (e.pos, e.count + v.2) } else { out[n] = (v.0, v.2) } } }
        a.emitters = out
        a.caveBiome = sculk >= 4 ? 1 : (moss >= 4 ? 2 : (drip >= 4 ? 3 : 0))
        a.leafCover = Float(leaves) / 30
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

    // F3 line: what the audio is doing (music mood, combat level, loops, reverb room).
    func audioDebugLine() -> String {
        let mood = music.mood?.label ?? "silent"
        let combat = ["calm", "garrison near", "combat"][max(0, min(2, audio.combat))]
        let loops = audio.asked.sorted().prefix(6).joined(separator: " ")
        return "Audio: \(mood)  \(combat)  " + String(format: "cave %.2f room %.0f", audio.cave, audio.roomSize) + "  loops \(loops.isEmpty ? "-" : loops)"
    }

    // MARK: Music director

    // The mood the music should be in right now.
    func musicMood() -> MusicMood {
        if let pm = menu as? PauseMenu, pm.page == .title { return .title }
        switch dim.dim {
        case .nether: return .ember
        case .deep where DeepGen.inHell(player.pos.y): return .ember
        case .end: return .hollow
        case .overworld, .deep: break
        }
        if mobs.of(.wither).contains(where: { $0.health > 0 && simd_length($0.pos - player.pos) < 80 }) { return .boss }
        // Firefights and raids score as combat; a Steelhold garrison nearby keeps a tense underscore.
        switch combatLevel() {
        case 2: return .combat
        case 1: return .tension
        default: break
        }
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
        case .stonyPeaks, .windsweptHills, .windsweptGravellyHills, .windsweptForest: return .mountain
        case .swamp, .mangroveSwamp: return .swamp
        case .jungle, .sparseJungle, .bambooJungle: return .jungle
        default: return .day
        }
    }

    // 2 = a fight is on (garrison soldiers or deck guns hunting the player within 48 blocks, or a raid wave
    // near the player), held 15 s after it ends; 1 = a Steelhold garrison within 64 blocks; 0 = calm.
    func combatLevel() -> Int { audio.combat }

    // Renders a group of sounds in the background once, ahead of first use.
    func audioWarm(_ group: String, _ list: @autoclosure () -> [Snd]) {
        guard let snd = sound, !audio.warmed.contains(group) else { return }
        audio.warmed.insert(group)
        snd.bank.prewarm(list())
    }

    func combatTick(_ dt: Float) {
        let a = audio
        a.combatHold = max(0, a.combatHold - dt)
        a.combatCheck -= dt
        guard a.combatCheck <= 0 else { return }
        a.combatCheck = 0.5
        let p = player.pos
        var fighting = false, garrison = false
        for m in mobs.mobs where m.health > 0 {
            guard Soldier.rank(m.kind) != nil || m.kind == .deckGun else { continue }
            let d = simd_length(m.pos - p)
            if d < 64 { garrison = true }
            if d < 48 && m.aggro { fighting = true; break }
        }
        if let r = raid, r.state == 1, simd_length(r.center - p) < 96 { fighting = true }
        // A crewed vessel within its gun range has the player in its sights.
        if !fighting && survival && difficulty > 0 {
            for s in world.ships.list where s.isVessel && !s.captured && s.parent == nil {
                let d = simd_length(s.pos - p)
                if d < (s.role == "frigate" ? 64 : 80) { fighting = true; break }
                if d < 140 { garrison = true }
            }
        }
        if fighting || garrison || Guns.index(held.item) != nil { audioWarm("combat", SoundBank.combatSounds) }
        if fighting { a.combatHold = 15 }
        a.combat = a.combatHold > 0 ? 2 : (garrison ? 1 : 0)
    }

    func musicTick(_ dt: Float) {
        combatTick(dt)
        guard let snd = sound, let stream = snd.music else { return }
        let m = music
        let want = musicMood()
        // The player's own track (Options > Audio > Soundtrack) plays through, mood changes and fights included; when it
        // ends the next follows in a few seconds (My Music) or after the usual quiet (Mixed).
        let src = Settings.shared.musicSource
        if m.customOn, let c = snd.custom {
            if c.playing && src != 0 && AudioSettings.volume(.music) > 0 { return }
            c.stop()
            m.customOn = false
            m.wait = src == 1 ? Rand.float(in: 2...6) : Rand.float(in: 240...600)
        }
        // Some moods take over at once (dimension change, boss, the title screen); the rest wait their turn.
        let hard = MusicDirector.hardMoods
        if let cur = m.mood, stream.isPlaying {
            let curHard = hard.contains(cur), wantHard = hard.contains(want)
            if cur != want && (curHard || wantHard) && !(cur == .title && want == .creative) {
                stream.stop(fade: want == .combat ? 0.8 : 2.5)
                m.mood = nil
                m.silence = want == .title ? 1 : (want == .combat ? 0.3 : Rand.float(in: 4...10))
                // Entering a dimension or a boss fight scores at once; leaving the title screen gives the world a quiet minute.
                m.wait = hard.contains(want) ? 0 : Rand.float(in: 30...90)
            }
            return
        }
        if m.mood != nil && !stream.isPlaying {
            // The piece ended by itself.
            m.mood = nil
            m.wait = want == .title ? Rand.float(in: 8...20) : (want == .combat || want == .tension ? Rand.float(in: 1...4) : Rand.float(in: 360...900))
        }
        if want == .title && m.wait > 2 { m.wait = 2 }
        // Arriving in the Emberdeep or the Hollow (or a boss appearing) with nothing playing: score it soon.
        if want != m.lastWant && hard.contains(want) && m.wait > 6 { m.wait = Rand.float(in: 3...6) }
        m.lastWant = want
        if m.silence > 0 { m.silence -= dt; return }
        m.wait -= dt
        if m.wait <= 0 && AudioSettings.volume(.music) > 0 {
            // My Music: always the folder (the composer only while it is empty). Mixed: every other calm piece.
            let useCustom = src == 1 || (src == 2 && !hard.contains(want) && m.pieces % 2 == 1)
            if useCustom, let c = snd.custom, c.playNext(shuffle: Settings.shared.musicShuffle) {
                m.customOn = true
                m.mood = nil
                m.pieces += 1
                onToast?("♪ \(c.title ?? "")")
                return
            }
            let seed = Rand.u64(in: 0...UInt64(Int32.max))
            let score = Composer.compose(want, seed: seed)
            stream.play(score, fadeIn: want == .boss || want == .combat ? 0.5 : 3)
            m.mood = want
            m.pieces += 1
            if want != .title && want != .combat && want != .tension { onToast?("♪ \(score.title)") }
        }
    }
}

extension Game {
    // Skip Track (Y on the pause menu, the Skip Music Track key, Options > Audio): the next piece, now.
    func skipMusicTrack() {
        guard let snd = sound else { return }
        snd.custom?.stop()
        music.customOn = false
        snd.music?.stop(fade: 0.4)
        music.mood = nil
        music.silence = 0.6
        music.wait = 0
        onToast?("Next track")
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
