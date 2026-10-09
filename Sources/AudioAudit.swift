import Foundation
import simd

// --audioaudit OUT.md (snapshot sub-mode): docs/STORE_QUALITY.md objective 5. Writes the sound coverage table
// (every block material, mob kind and sound in the bank) and runs the context rules: dry blocks never step like mud
// or slime, and the ambience director (Game.audioAmbientTick in record mode) plays no birds, owls or insects
// underground, at night, in the Deep or in the Ash Vault, while a forest at noon does get birdsong.
// Levels (loudness, peaks, clipping) and the wet-sounding check of the rendered steps: tools/audiolevels.py.
//   Blocksmith --snapshot /tmp/a.png --seed 12345 --rd 4 --audioaudit snaps/audio_audit.md
enum AudioAudit {
    static func run(game g: Game, out: String) -> Int {
        var md = "# Audio audit (Blocksmith --audioaudit)\n\n"
        var fails = 0
        func check(_ ok: Bool, _ what: String, _ info: String = "") {
            let line = "\(ok ? "PASS" : "FAIL"): \(what)\(info.isEmpty ? "" : " (\(info))")"
            print("audioaudit " + line); md += "- " + line + "\n"
            if !ok { fails += 1 }
        }

        // 1. Coverage: blocks per sound material, dry blocks that sound wet, silent mob kinds, the bank's size.
        md += "## Coverage\n\n"
        var perMat: [SoundMat: [String]] = [:]
        var seen = Set<BlockID>()
        for i in 1..<Blocks.count {
            let base = Blocks.groupBase[i]
            guard seen.insert(base).inserted else { continue }
            perMat[soundMat(BlockID(i)), default: []].append(Blocks.key(base))
        }
        md += "| material | blocks | examples |\n|---|---|---|\n"
        for m in SoundMat.allCases {
            let ks = perMat[m] ?? []
            md += "| \(m.name) | \(ks.count) | \(ks.prefix(8).joined(separator: ", ")) |\n"
        }
        let bank = Set(SoundBank.allSounds.map { $0.name })
        for m in SoundMat.allCases {
            let miss = [Snd.breakBlock(m), .place(m), .step(m), .hit(m), .fall(m)].filter { !bank.contains($0.name) }
            check(miss.isEmpty, "material \(m.name) has break/place/step/hit/fall sounds", miss.map { $0.name }.joined(separator: " "))
        }
        // A name says dry (stone, wood, sand, grass...) while the material is mud or slime: steps would squelch.
        let dryWords = ["stone", "planks", "log", "wood", "sand", "dirt", "grass", "gravel", "brick", "cobble", "deepslate", "concrete", "tile"]
        let wetMats: Set<SoundMat> = [.mud, .slime]
        let wetDry = (perMat[.mud] ?? []) + (perMat[.slime] ?? [])
        let suspects = wetDry.filter { k in dryWords.contains { k.contains($0) } && !k.contains("mud") }
        check(suspects.isEmpty, "no dry-named block uses the mud or slime material", suspects.joined(separator: ", "))
        // Common ground blocks the player walks on most: their material must be the dry one.
        let ground: [(String, SoundMat)] = [("grass_block", .grass), ("dirt", .dirt), ("stone", .stone), ("sand", .sand), ("gravel", .gravel),
                                            ("oak_planks", .wood), ("cobblestone", .stone), ("deepslate", .deepslate), ("snow_block", .snow)]
        for (k, want) in ground where Blocks.has(k) {
            let got = soundMat(Blocks.id(k))
            check(got == want && !wetMats.contains(got), "\(k) steps sound \(want.name)", "got \(got.name)")
        }
        let silent = MobKind.allCases.filter { MobVoice.profile($0).family == .silent }
        md += "\nSilent mob kinds (no voice profile): \(silent.isEmpty ? "none" : silent.map { "\($0)" }.joined(separator: ", "))\n\n"
        md += "Sound bank: \(SoundBank.allSounds.count) sounds (+ mob voices, guns and vehicles rendered on demand).\n\n"
        let gaps = silent.filter { ![.endCrystal, .minecart, .boat, .armorStand].contains($0) }
        check(gaps.isEmpty, "every creature and vehicle kind has a voice or engine profile", gaps.map { "\($0)" }.joined(separator: ", "))

        // 2. Ambience rules: run the director for 60 s per place and count wildlife.
        md += "\n## Ambience context rules\n\n"
        let wildlife = ["birdCall", "owlHoot", "loop:crickets", "loop:jungle", "loop:swamp"]
        func listen(_ game: Game, _ seconds: Float = 60) -> [String: Int] {
            game.audio.record = [:]
            var t: Float = 0
            while t < seconds { game.audioAmbientTick(0.05); t += 0.05 }
            defer { game.audio.record = nil }
            return game.audio.record ?? [:]
        }
        func wild(_ r: [String: Int]) -> [String] { wildlife.filter { k in r.keys.contains { $0.hasPrefix(k) } } }
        g.weather.raining = false; g.weather.rain = 0
        let w = g.world
        let forest = Snapshot.findBiome(w.gen, "forest", interior: true) ?? g.player.pos
        _ = w.loadSync(center: forest, radius: 3)
        let top = Float(w.gen.column(Int(forest.x), Int(forest.z)).height + 1)
        func at(_ p: V3, _ time: Double) -> [String: Int] {
            g.player.pos = p; g.player.vel = .zero
            g.time = time * DAY_LENGTH
            g.audio.biomeTimer = 0
            return listen(g)
        }
        let noon = at(V3(forest.x, top, forest.z), 0.25)
        check(noon["birdCall"] ?? 0 > 0, "forest at noon: birdsong", "\(noon["birdCall"] ?? 0) calls")
        let night = at(V3(forest.x, top, forest.z), 0.75)
        check((night["birdCall"] ?? 0) == 0, "forest at midnight: no birdsong", wild(night).joined(separator: " "))
        // Underground: the first open cave space 30+ blocks under the forest floor.
        var cave: V3?
        let x0 = Int(forest.x), z0 = Int(forest.z)
        search: for y in stride(from: Int(top) - 30, to: YOFF - 40, by: -1) { for dx in stride(from: -24, through: 24, by: 3) { for dz in stride(from: -24, through: 24, by: 3) {
            if w.block(x0 + dx, y, z0 + dz) == AIR && w.block(x0 + dx, y + 1, z0 + dz) == AIR && Blocks.opaque[Int(w.block(x0 + dx, y - 1, z0 + dz))] {
                cave = V3(Float(x0 + dx) + 0.5, Float(y), Float(z0 + dz) + 0.5); break search
            }
        } } }
        if let c = cave {
            for (t, label) in [(0.25, "noon"), (0.75, "midnight")] {
                let r = at(c, t)
                check(wild(r).isEmpty, "cave under the forest at \(label): no birds, owls or insects", "y \(Int(c.y) - YOFF): \(wild(r).joined(separator: " "))")
            }
        } else { check(false, "found a cave under the forest") }
        // The Deep (hell band) and the Ash Vault: a game of their own in that dimension.
        let dw = World(seed: w.seed, device: w.device, save: nil, dim: .deep)
        dw.renderDistance = 3
        let dg = Game(world: dw, save: nil, persistent: false)
        dg.paused = false
        for (label, p) in [("Ash Vault", V3(-60, Float(((dw.gen as? DeepGen)?.floorY(-60, 0) ?? 30) + 2), 0)),
                           ("the Deep's hell band", V3(60, Float(DeepGen.hellBase + 60), 60))] {
            _ = dw.loadSync(center: p, radius: 2)
            dg.player.pos = p
            dg.time = 0.25 * DAY_LENGTH
            let r = listen(dg)
            check(wild(r).isEmpty, "\(label) at noon: no birds, owls or insects", wild(r).joined(separator: " "))
        }
        md += "\n\(fails) failing checks.\n"
        try? md.write(toFile: out, atomically: true, encoding: .utf8)
        print("audioaudit: \(fails) failing checks -> \(out)")
        return fails
    }
}
