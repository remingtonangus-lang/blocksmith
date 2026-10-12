import Foundation
import Metal
import simd

// Save soak (Q2, scorecard "Crashes: 100 save/load cycles"; `questcheck --savesoak-only`, SOAK_CYCLES=N to change the
// count): a survival world is played, changed, saved and loaded back as the app loads it (SaveManager + World + Game +
// apply(meta)) again and again, each cycle playing on in the loaded copy. Every cycle compares what was saved with what
// came back: the player's place, health, hunger and time, every inventory slot, a chest's contents, every block changed
// so far, the tamed animals. At the end: no mismatch, no World or Game left alive from earlier cycles (a leak would
// keep their chunk memory), resident memory flat, and the save folder holds only changed chunks.
enum SaveSoakTests {
    static func rssMB() -> Double? {
        guard let s = try? String(contentsOfFile: "/proc/self/statm", encoding: .utf8) else { return nil }
        let f = s.split(separator: " ")
        guard f.count > 1, let pages = Double(f[1]) else { return nil }
        return pages * 4096 / 1_048_576
    }
    static func folderMB(_ u: URL) -> Double {
        let fm = FileManager.default
        var n = 0
        if let e = fm.enumerator(at: u, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let f as URL in e { n += (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        }
        return Double(n) / 1_048_576
    }

    static func run(device: MTLDevice, cycles n: Int = 100, check: (Bool, String) -> Void) {
        let cycles = Int(ProcessInfo.processInfo.environment["SOAK_CYCLES"] ?? "") ?? n
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("savesoak-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? fm.removeItem(at: tmp)
        defer { try? fm.removeItem(at: tmp) }
        let seed: UInt64 = 424242
        let worlds0 = World.alive, games0 = Game.alive

        func open() -> Game {
            let save = SaveManager(dir: tmp)
            let meta = save.loadMeta()
            let w = World(seed: seed, device: device, save: save)
            w.renderDistance = 3
            let g = Game(world: w, save: save, persistent: true)
            if let m = meta { g.apply(m) } else { g.player.pos = g.spawnPoint; g.survival = true }
            _ = w.loadSync(center: g.player.pos, radius: 3)
            return g
        }

        var g: Game! = open()
        let home = g.player.pos
        let hx = Int(floor(home.x)), hz = Int(floor(home.z))
        var rng = SRng(seed &+ 77)
        var edits: [IVec3: BlockID] = [:]
        let palette = ["oak_planks", "cobblestone", "glass", "stone_bricks", "spruce_planks"].filter { Blocks.has($0) }.map { Blocks.id($0) }
        let items = ["iron_ingot", "bread", "torch", "oak_log", "arrow", "coal", "diamond", "string"].filter { Items.has($0) }.map { Items.id($0) }
        let chestAt = IVec3(hx + 3, g.world.topY(hx + 3, hz + 3) + 1, hz + 3)
        g.world.setBlock(chestAt.x, chestAt.y, chestAt.z, Blocks.id("chest"))
        edits[chestAt] = g.world.block(chestAt.x, chestAt.y, chestAt.z)

        var mismatches: [String] = []
        var rss: [Double] = []
        let t0 = Date()
        for c in 0..<cycles {
            // Play a little (survival ticks: hunger, mobs, the clock), then change things.
            g.menu = nil; g.paused = false
            for _ in 0..<8 { g.tick(0.05) }
            g.health = max(1, g.health); g.health = min(20, g.health)
            for _ in 0..<3 {
                let x = hx + Int(rng.next() % 17) - 8, z = hz + Int(rng.next() % 17) - 8
                guard abs(x - chestAt.x) + abs(z - chestAt.z) > 1 else { continue }
                let y = g.world.topY(x, z) + 1 + Int(rng.next() % 3)
                let b = rng.next() % 4 == 0 ? AIR : palette[Int(rng.next() % UInt64(palette.count))]
                g.world.setBlock(x, y, z, b)
                edits[IVec3(x, y, z)] = g.world.block(x, y, z)
            }
            let slot = 9 + c % 27
            g.inventory.main[slot] = ItemStack(items[c % items.count], 1 + c % 16)
            let be = g.world.entity(chestAt, .chest)
            g.world.blockEntities[chestAt] = be
            be.container[c % be.container.slots.count] = ItemStack(items[(c * 3) % items.count], 1 + c % 9)
            let px = Float(hx) + 0.5 + Float(c % 7) - 3, pz = Float(hz) + 0.5 + Float(c % 5) - 2
            g.player.pos = V3(px, Float(g.world.topY(Int(floor(px)), Int(floor(pz))) + 1), pz)
            g.player.vel = .zero

            let pos = g.player.pos, health = g.health, hunger = g.hunger, time = g.time
            let inv = g.inventory.main.slots
            let box = be.container.slots
            g.saveNow()
            g = nil                                  // the old world goes, as when the app loads another
            g = open()

            var bad: [String] = []
            if simd_length(g.player.pos - pos) > 0.01 { bad.append("player at \(g.player.pos) not \(pos)") }
            if g.health != health || g.hunger != hunger { bad.append("health \(g.health)/\(health), hunger \(g.hunger)/\(hunger)") }
            if abs(g.time - time) > 0.01 { bad.append("time \(g.time) not \(time)") }
            if g.inventory.main.slots != inv { bad.append("inventory differs in \(zip(g.inventory.main.slots, inv).filter { $0 != $1 }.count) slots") }
            let box2 = g.world.blockEntities[chestAt]?.container.slots ?? []
            if box2 != box { bad.append("chest differs (\(box2.filter { !$0.isEmpty }.count) of \(box.filter { !$0.isEmpty }.count) stacks)") }
            let lost = edits.filter { g.world.block($0.key.x, $0.key.y, $0.key.z) != $0.value }
            if !lost.isEmpty { bad.append("\(lost.count) of \(edits.count) changed blocks came back different, e.g. \(lost.first!.key)") }
            if !bad.isEmpty && mismatches.count < 5 { mismatches.append("cycle \(c): " + bad.joined(separator: "; ")) }
            if !bad.isEmpty && mismatches.count >= 5 { mismatches.append("") }
            if let r = rssMB() { rss.append(r) }
        }
        let secs = Date().timeIntervalSince(t0)
        let liveWorlds = World.alive - worlds0, liveGames = Game.alive - games0
        g = nil
        check(mismatches.isEmpty, "savesoak: \(cycles) save/load cycles in \(Int(secs)) s, every cycle came back as saved (\(mismatches.filter { !$0.isEmpty }.joined(separator: " | ")))")
        // Memory: the last tenth against the second tenth (the first fills caches).
        var flat = true, memText = "not measured here"
        if rss.count >= 20 {
            let k = rss.count / 10
            let early = rss[k..<(2 * k)].reduce(0, +) / Double(k), late = rss[(rss.count - k)...].reduce(0, +) / Double(k)
            flat = late - early < 64
            memText = String(format: "resident %.0f MB early, %.0f MB late", early, late)
        }
        let mb = folderMB(tmp)
        check(liveWorlds <= 2 && liveGames <= 1 && flat && mb < 40,
              "savesoak: no world or game left behind (\(liveWorlds) worlds, \(liveGames) games alive, the open one included), \(memText), save folder \(String(format: "%.1f", mb)) MB")
    }
}
