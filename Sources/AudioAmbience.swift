import Foundation
import simd

// Game-side audio: listener + occlusion, looping emitters found by scanning the blocks around the
// player (fire, lava, water, portals, beacons, spawners), weather and biome beds, cave stings,
// the block-sound helpers used by the rest of the game, and the music director.

final class AudioState {
    var scanTimer: Float = 0
    var emitters: [String: (pos: V3, count: Int)] = [:]
    var caveBiome = 0                       // 0 none, 1 deep dark, 2 lush, 3 dripstone
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
    var armorPrimed = false
    static var kindTable: [UInt8] = []      // block id -> emitter kind (built once)
}

final class MusicDirector {
    var wait: Float = Float.random(in: 60...150)
    var mood: MusicMood? = nil              // mood of the piece being played
    var pieces = 0
    var silence: Float = 0                  // seconds of forced silence after a fade-out
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
        snd.setListener(eye: eye, yaw: player.yaw, pitch: player.pitch, cave: a.cave, underwater: player.headInWater)

        // Scan the blocks around the player for looping emitters twice a second.
        a.scanTimer -= dt
        if a.scanTimer <= 0 {
            a.scanTimer = 0.5
            audioScan()
        }
        var asked = Set<String>()
        func ask(_ key: String, _ s: Snd, _ v: Float, at pos: V3? = nil) {
            guard v > 0.001 else { return }
            asked.insert(key)
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
        a.asked = asked
        snd.update(dt, asked: asked)
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
        let names = [1: "fire", 2: "campfire", 3: "furnace", 4: "lava", 5: "water", 6: "portal", 7: "beacon", 8: "spawner", 12: "portal", 13: "anchor", 14: "bubbles"]
        var out: [String: (pos: V3, count: Int)] = [:]
        for (k, v) in best { if let n = names[k] { if let e = out[n] { out[n] = (e.pos, e.count + v.2) } else { out[n] = (v.0, v.2) } } }
        a.emitters = out
        a.caveBiome = sculk >= 4 ? 1 : (moss >= 4 ? 2 : (drip >= 4 ? 3 : 0))
    }

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
        return f < 0.5 ? .day : .night
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
                m.wait = 0
            }
            return
        }
        if m.mood != nil && !stream.isPlaying {
            // The piece ended by itself.
            m.mood = nil
            m.wait = want == .title ? Float.random(in: 8...20) : Float.random(in: 360...900)
        }
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
        s.notes = s.notes.filter { $0.t < len - 4 }
        s.length = len
        s.title = title(name)
        return s
    }
}
