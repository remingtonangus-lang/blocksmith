import Foundation
import simd

// questcheck --nov15sounds: the 78 sounds Remington asked for on Nov 15 (ElevenLabs takes, docs/status/elevenlabs-takes.md).
// Every entry with a usable take resolves to a recording in Resources/Sounds/real under a sound the game plays (a name in
// SoundBank.allSounds), each loads and decodes, a loop's take is at least two seconds; the two new uses play theirs: an
// empty bucket drawn up a well shaft (wellBucket) and a desk's drawer (drawerOpen). Run from the repo (the recordings
// are read from Resources/Sounds/real under the working directory).
enum RecordedNov15Check {
    // The doc's entries, by number: the sounds each one's take was wired to. Entry 38 (pistol reload) had no usable take.
    static let entries: [(String, [String])] = [
        ("01", ["trainCoachLoop"]), ("02", ["trainPassLoop"]), ("03", ["trainIdleLoop"]), ("04", ["trainBrakes"]),
        ("05", ["trainDepart"]), ("06", ["trainCoupler"]), ("07", ["trainWhistle"]), ("08", ["trainWhistleShort"]),
        ("09", ["stationBell"]), ("10", ["coachDoor"]), ("11", ["treeCrack"]), ("12", ["treeLand"]), ("13", ["treeFallSmall"]),
        ("14", ["treeLandSnow"]), ("15", ["logRoll"]), ("16", ["elevatorLoop"]), ("17", ["elevatorArrive"]),
        ("18", ["elevatorDoors"]), ("19", ["garageDoor"]), ("20", ["radarLoop"]), ("21", ["radarContact"]),
        ("22", ["radarWarning"]), ("23", ["crawlerLoop"]), ("24", ["crawlerStop"]), ("25", ["carriageTrees"]),
        ("26", ["vehicleHatch"]), ("27", ["tankMGLoop"]), ("28", ["tankMGTail"]), ("29", ["casingsSteel"]),
        ("30", ["chuteOpen"]), ("31", ["chuteLoop"]), ("32", ["chuteLand"]), ("33", ["wallCollapse"]),
        ("34", ["concreteBreak"]), ("35", ["bulletIce"]), ("36", ["bullet_impact_metal"]), ("37", ["gun_reload_16"]),
        ("38", []), ("39", ["gun_reload_2"]), ("40", ["gun_reload_17"]), ("41", ["gun_reload_3"]), ("42", ["gun_reload_4"]),
        ("43", ["gun_reload_20", "gun_reload_19"]), ("44", ["gun_reload_23"]), ("45", ["gun_distant_0"]),
        ("46", ["gun_distant_19"]), ("47", ["gun_distant_9"]), ("48", ["battleLoop"]), ("49", ["pickup"]),
        ("50", ["armor_equip_0"]), ("51", ["armor_equip_1"]), ("52", ["armor_equip_2", "armor_equip_3", "armor_equip_4", "armor_equip_5"]),
        ("53", ["villagerTrade"]), ("54", ["villager_work_0", "villager_work_11", "villager_work_12"]), ("55", ["villager_work_6"]),
        ("56", ["villager_work_4"]), ("57", ["tripwire"]), ("58", ["sulfurLoop"]), ("59", ["sealBoom"]), ("60", ["fallRushLoop"]),
        ("61", ["cityCrowdLoop"]), ("62", ["marketLoop"]), ("63", ["crowdPanicLoop"]), ("64", ["cityFightLoop"]),
        ("65", ["questAccept"]), ("66", ["questDone"]), ("67", ["questFail"]), ("68", ["convoyCartLoop"]),
        ("69", ["customsGate"]), ("70", ["wellBucket"]), ("71", ["houseBought"]), ("72", ["volcanoLoop"]),
        ("73", ["sheetIceStep"]), ("74", ["iceCrack"]), ("75", ["snowyBush"]), ("76", ["chairSit"]), ("77", ["drawerOpen"]),
        ("78", ["faustShoulder"]),
    ]

    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        RealSounds.rescan()
        var byName: [String: Snd] = [:]
        for s in SoundBank.allSounds { byName[s.name] = s }
        var resolved = 0, withTake = 0, recordedAll = 0
        var missing: [String] = [], unplayed: [String] = [], bad: [String] = []
        for (num, names) in entries where !names.isEmpty {
            withTake += 1
            var ok = true
            for n in names {
                guard let s = byName[n] else { unplayed.append("\(num) \(n)"); ok = false; continue }
                guard RealSounds.count(s) > 0, let takes = RealSounds.load(s) else { missing.append("\(num) \(n)"); ok = false; continue }
                let secs = Double(takes[0].count) / SoundBank.rate
                if takes.contains(where: { $0.count < 16 }) || (s.isLoop && secs < 2) { bad.append("\(num) \(n) \(String(format: "%.2f s", secs))"); ok = false }
            }
            if ok { resolved += 1 }
        }
        for s in SoundBank.allSounds where RealSounds.count(s) > 0 { recordedAll += 1 }
        print("nov15sounds: \(resolved) of \(entries.count) entries resolve to a recording (\(withTake) had a usable take; 38 pistol reload had none); \(recordedAll) sounds in the bank play a recording")
        for m in missing + unplayed + bad { print("nov15sounds:   \(m)") }
        check(resolved == withTake && missing.isEmpty && unplayed.isEmpty && bad.isEmpty,
              "Nov 15 sounds: every entry with a usable take resolves to a recording the game plays (\(resolved) of \(withTake); missing \(missing.count), not in the bank \(unplayed.count), unreadable or short loops \(bad.count))")

        // Ledger 330 (Nov 17 20:07:15: "Someone's shouting. It would work if it was way less frequent."): the market
        // street's take holds a trader's call; it is heard one pass at a time, 90-180 s apart, not every 8 s.
        do {
            var call = "no take"
            if let t = RealSounds.load(.marketLoop)?.first, t.count > 4410 {
                let win = Int(SoundBank.rate / 10)
                var db: [Float] = []
                for i in stride(from: 0, to: t.count - win, by: win) {
                    var e: Float = 0
                    for j in i..<(i + win) { e += Float(t[j]) * Float(t[j]) }
                    db.append(10 * log10f(max(e / Float(win), 1e-12)))
                }
                let med = db.sorted()[db.count / 2]
                if let k = db.indices.max(by: { db[$0] < db[$1] }) { call = String(format: "a call %.1f dB over the street at %.1f s", db[k] - med, Double(k) / 10) }
            }
            let saved = (MarketCalls.until, MarketCalls.next, MarketCalls.passes)
            defer { (MarketCalls.until, MarketCalls.next, MarketCalls.passes) = saved }
            MarketCalls.until = -1; MarketCalls.next = 0; MarketCalls.passes = 0
            var heard: Double = 0
            var clock: Double = 1000
            for _ in 0..<(600 * 20) { if MarketCalls.heard(clock) { heard += 0.05 }; clock += 0.05 }
            let calls = MarketCalls.passes
            check(MarketCalls.old ? false : (calls >= 3 && calls <= 7 && heard <= 8.5 * Double(calls) + 0.1),
                  String(format: "ledger 330: the market street (%@) heard %d times in 10 minutes among the shops, %.0f s in all (was every 8 s: 75 calls)", call, calls, heard))
        }
        // The two new uses: a well's bucket and a desk's drawer.
        let w = g.world, p = g.player
        let home = p.pos, survival0 = g.survival, fly0 = p.flying, yaw0 = p.yaw, pitch0 = p.pitch
        let sel = g.inventory.selected, held0 = g.inventory.main[sel]
        defer { p.pos = home; g.survival = survival0; p.flying = fly0; p.vel = .zero; p.yaw = yaw0; p.pitch = pitch0; g.inventory.main[sel] = held0 }
        _ = w.loadSync(center: home, radius: 3)
        let bx = Int(floor(home.x)) + 4, bz = Int(floor(home.z)) + 4, by = min(CH - 40, w.topY(bx, bz) + 30)
        // A village well's shaft: 2x2 inside a stone lining, nine deep, water in its bottom two.
        func well() {
            for dz in -1...2 { for dx in -1...2 {
                let edge = dx == -1 || dx == 2 || dz == -1 || dz == 2
                for d in 0...8 { w.setBlock(bx + dx, by - d, bz + dz, edge ? STONE : (d >= 7 ? WATER : AIR)) }
                w.setBlock(bx + dx, by - 9, bz + dz, STONE)
            } }
        }
        well()
        g.survival = true; p.flying = true; p.vel = .zero
        p.pos = V3(Float(bx) + 0.5, Float(by) + 1, Float(bz) + 0.5); p.yaw = 0; p.pitch = -Float.pi / 2 + 0.01
        g.target = nil
        g.inventory.main[sel] = ItemStack(Items.id("bucket"), 1)
        let played0 = RecordedNov15.played["wellBucket", default: 0]
        let drew = g.useBucket()
        let full = (0..<36).contains { Items.key(g.inventory.main[$0].item) == "water_bucket" }
        let rang = RecordedNov15.played["wellBucket", default: 0] > played0
        check(drew && full && (rang || RecordedNov15.off || RecordedNov15.oldWellReach),
              "Nov 15 sounds: an empty bucket draws water up a well's shaft nine blocks down (drawn \(drew), full \(full)) with the well bucket's sound (\(rang))")
        // Off the shaft (open water as far below), the bucket reaches arm's length only.
        for dz in -1...2 { for dx in -1...2 { for d in 0...6 { w.setBlock(bx + dx, by - d, bz + dz, AIR) } } }
        g.inventory.main[sel] = ItemStack(Items.id("bucket"), 1)
        let open = g.useBucket()
        check(!open, "Nov 15 sounds: over open water nine blocks down (no shaft) an empty bucket reaches no farther than before (drew \(open))")
        for dz in -1...2 { for dx in -1...2 { for d in 0...9 { w.setBlock(bx + dx, by - d, bz + dz, AIR) } } }

        // A desk's drawer opens as a container with the drawer sound; what is in it spills when the desk is broken.
        if Blocks.has("oak_desk") && !RecordedNov15.oldDeskDrawer {
            let d = IVec3(bx, by, bz)
            w.setBlock(d.x, d.y - 1, d.z, STONE); w.setBlock(d.x, d.y, d.z, Blocks.id("oak_desk"))
            let opens = g.isInteractive(d)
            let drawer0 = RecordedNov15.played["drawerOpen", default: 0]
            g.openBlock(d)
            let title = g.menu?.title ?? "none"
            let rang2 = RecordedNov15.played["drawerOpen", default: 0] > drawer0
            let kept = w.blockEntities[d] != nil
            g.closeMenu()
            check(opens && title == "Desk Drawer" && kept && (rang2 || RecordedNov15.off),
                  "Nov 15 sounds: a desk's drawer opens (\(opens), menu \(title)), keeps its things (\(kept)) and plays the drawer sound (\(rang2))")
            w.blockEntities[d] = nil
            w.setBlock(d.x, d.y, d.z, AIR); w.setBlock(d.x, d.y - 1, d.z, AIR)
        }
    }
}
