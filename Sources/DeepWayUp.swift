import Foundation
import simd

// The way back up and the Deep's written hints (the gap pass, docs/status/the-deep-expansion.md "Gap pass": DE3, DE5).
//   Way up   a HUD line in the Deep naming the nearest way to the surface, how far and which way (ahead, to your
//            left...): in the hell band and the crusts the hole you broke in by or a woken Ember Gate; in the vault a
//            shaft you blew through the seal, the command-bunker lift after victory, or a Deep Lift you set down.
//   Journals Keeper's Journal (Deep fortresses, Brimstone Keeps): a soldier's account of the Sealrock, the keeps and
//            their forge (P328: story, no recipe); the Ashguard field journals (the vault's chests) tell who they are.
extension Game {
    // The nearest way up from here: its place and what it is, or nil outside the Deep.
    func deepWayUp() -> (at: V3, what: String)? {
        guard dim.dim == .deep else { return nil }
        let p = player.pos
        var best: (V3, String)?
        func consider(_ q: V3, _ what: String) {
            if best == nil || simd_length(V2(q.x - p.x, q.z - p.z)) < simd_length(V2(best!.0.x - p.x, best!.0.z - p.z)) { best = (q, what) }
        }
        if DeepGen.inVault(p.y) {
            for s in sealShafts { consider(V3(Float(s.x) + 0.5, Float(s.y), Float(s.z) + 0.5), "your shaft through the seal") }
            if ashVictory { consider(V3(Float(AshWar.liftAt.x) + 0.5, Float(AshWar.liftAt.y), Float(AshWar.liftAt.z) + 0.5), "the bunker lift") }
            for l in deepLifts { consider(V3(Float(l.x) + 0.5, Float(l.y), Float(l.z) + 0.5), "your Hell Lift") }
            if best == nil { return nil }
        } else {
            if let e = deepEntry { consider(e, "the hole you came down") }
            for l in deepLifts where !DeepGen.inVault(Float(l.y)) { consider(V3(Float(l.x) + 0.5, Float(l.y), Float(l.z) + 0.5), "your Hell Lift") }
            if let sc = world.gen.structures {
                for key in wokenGates {
                    let xz = key.split(separator: ",").compactMap { Int(String($0)) }
                    guard xz.count == 2, let k = sc.nearest("brimstone_keep", x: xz[0], z: xz[1] - 15, maxRegions: 1),
                          DeepGates.keyFor(k) == key else { continue }
                    consider(DeepGates.front(k), "the Ember Gate")
                }
            }
        }
        return best.map { (at: $0.0, what: $0.1) }
    }

    // "Way up: the Ember Gate, 132 blocks ahead-left".
    // The HUD's copy, rebuilt four times a second (structure lookups and a string; the HUD asks every frame).
    func deepWayUpHUD() -> String? {
        if clock - wayUpCache.clock < 0.25 && clock >= wayUpCache.clock { return wayUpCache.line }
        let line = deepWayUpLine()
        wayUpCache = (clock, line)
        return line
    }

    func deepWayUpLine() -> String? {
        guard let w = deepWayUp() else { return nil }
        let d = V2(w.at.x - player.pos.x, w.at.z - player.pos.z)
        let dist = Int(simd_length(d))
        if dist < 3 { return "Way up: \(w.what), here" }
        // Bearing relative to the view: 0 ahead, positive to the right.
        let want = atan2f(-d.x, -d.y)
        var rel = player.yaw - want
        while rel > .pi { rel -= 2 * .pi }
        while rel < -.pi { rel += 2 * .pi }
        let sector = Int(((rel + .pi) / (2 * .pi) * 8).rounded()) % 8
        let words = ["behind you", "behind you, left", "to your left", "ahead-left", "ahead", "ahead-right", "to your right", "behind you, right"]
        return "Way up: \(w.what), \(dist) blocks \(words[sector])"
    }

    // A Deep Lift set down (Game.placeBlock): remembered for the way-up marker.
    func noteDeepLift(_ p: IVec3, placed: Bool) {
        guard dim.dim == .deep else { return }
        if placed { if !deepLifts.contains(p) { deepLifts.append(p) } } else { deepLifts.removeAll { $0 == p } }
        if deepLifts.count > 16 { deepLifts.removeFirst() }
    }

    // Reading a journal: a read-only book.
    func useJournal() -> Bool {
        let k = Items.key(held.item)
        guard let j = DeepJournals.all[k] else { return false }
        var b = ItemStack(Items.id("written_book"), 1)
        b.pages = j.pages
        b.label = j.title
        openMenu(BookMenu(game: self, stack: b, source: .hand(inventory.selected)))
        DeepJournals.read += 1
        return true
    }
}

enum DeepJournals {
    struct Journal { let title: String; let pages: [String]; var tint: Int = 0 }
    static var read = 0
    // Every readable book item: the Deep's journals and the overworld's logs, notes and pamphlets (Readables.swift).
    static let all: [String: Journal] = deep.merging(Readables.all) { a, _ in a }
    static let deep: [String: Journal] = [
        // P328 (f): a soldier's journal, not a manual: the forge and the flux are in it, the recipe is not.
        "keepers_journal": Journal(title: "Keeper's Journal", pages: [
            "Third week under the fire.\n\nThe floor of this place is not rock. Picks skate off it, powder only blackens it. The old hands call it Sealrock and say nothing made by smiths will bite it.",
            "Sunderite does, they say. Red crystal, warm to the touch, grown only in the walls of the Brimstone Keeps: black castles standing over the lava sea.",
            "The keeps are held. Blight Skeletons on the walls, brutes at the gates, Cinderwisps on the towers, and the Ashguard's own men in the strongroom under the keep, with a Castellan to keep the hoard.",
            "The Ashguard smiths kept a forge in that strongroom. I watched them through the grate the night before they went down: the red crystal ground up with the cinder dust at the bench into a flux the colour of a bad bruise, and the flux fed to the blast furnace on its bed of magma. What came out rang like a bell when they dropped it on the stones.",
            "They went down through the seal that same week. Sergeant Kell swears they never touched it with a pick, only knelt at it with something in their hands, and then the floor was not there.\n\nKell says a lot of things.",
            "The gate in the keep's yard burned once last winter, the night the Castellan fell to his own men. Two of them walked into the light and we never saw them again.\n\nBelow the seal is the vault, and the vault is theirs.",
        ]),
        "ashguard_journal": Journal(title: "Field Journal of an Ashguard Rifleman", pages: [
            "They told us the vault would be a refuge. A whole army under the world, out of reach of the Capital, with our own sun.\n\nThe sun is a lamp of molten rock. It never sets.",
            "The Marshal says the surface is lost, that we hold the last fire. He drills us at the red lamps every shift. Nobody has seen the surface in eleven years.",
            "The towns are for the families the first column brought down. Rail runs from the citadel to every one of them; the trains carry shells out and nothing back.",
            "The airfield is the Marshal's pride. Bombers with nowhere to fly, under a roof a hundred and forty blocks up. We polish them.",
            "If you are reading this, the seal is broken and you came down through it. Then the Marshal was wrong, and there is a way up. Take it, and take me with you.",
        ]),
    ]
}

extension ItemRegistry {
    func registerDeepJournalItems() {
        // (sorted: a dictionary's order changes from run to run, and the item and texture layer order with it: P400)
        for (k, j) in DeepJournals.all.sorted(by: { $0.key < $1.key }) where !has(k) {
            var d = ItemDef(k, j.title)
            d.sprite = Sprite(mask: "book", base: j.tint != 0 ? UInt32(j.tint) : (k == "keepers_journal" ? 0x6A2A1A : 0x26262A), extras: [:])
            d.maxStack = 1
            add(d)
        }
    }
}
