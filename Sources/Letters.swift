import Foundation

// Nov 13 playtest (12:35:27, reading a Greywall Dispatch: "Let's make a thousand different types of literature, so that
// way it's not all the same"): every dispatch, set of naval orders and ledger read the same two pages, names aside.
// Each is now put together from its own pools of openings, orders, news, postscripts and hands, picked by a hash of where
// it points, the world and how many such papers he has read, so no two in a row read alike (well over a thousand of
// each). The facts a paper carries (the place, its grid, what the map table and the war rooms hold) stay on its pages.
// LetterCheck reads thousands and counts them. BS_OLDLETTERS=1: the fixed texts, as before.
enum Letters {
    static let old = ProcessInfo.processInfo.environment["BS_OLDLETTERS"] == "1"
    static var read = 0                      // papers read this session (the next one reads differently)

    struct Pick {
        var h: UInt64
        init(_ a: Int, _ b: Int, _ c: Int, _ salt: UInt64) {
            var x = UInt64(bitPattern: Int64(a)) &* 0x9E3779B97F4A7C15 ^ UInt64(bitPattern: Int64(b)) &* 0xC2B2AE3D27D4EB4F
            x ^= UInt64(bitPattern: Int64(c)) &* 0x165667B19E3779F9 ^ salt
            h = x
        }
        mutating func next<T>(_ a: [T]) -> T {
            h ^= h >> 31; h = h &* 0x7FB5D329728EA185; h ^= h >> 27; h = h &* 0x81DADEF4BC2DD44D; h ^= h >> 33
            return a[Int(h % UInt64(a.count))]
        }
    }

    // MARK: Greywall Command

    static let gwHeads = ["GREYWALL COMMAND - DISPATCH", "GREYWALL COMMAND - FIELD ORDER", "GREYWALL SIGNALS - BY RUNNER",
                          "GREYWALL COMMAND - STANDING ORDER", "GREYWALL STAFF - FOR THE COMMANDANT", "GREYWALL COMMAND - URGENT"]
    static let gwOrders = [
        "Hold the walls. Report any rider from the towns. Keep the alarm panels manned.",
        "Double the gate watch after dark. Nobody in or out without the day's word.",
        "Stand to at dawn and dusk. Lamps out on the towers until the bell.",
        "Strip the yard of loose crates; the last raid hid behind them.",
        "Fill every water barrel. Ration the fuel to the tower guns only.",
        "Check the turret rings daily. Grease is in the armoury, not the mess.",
        "Send two scouts north at first light. They are back by noon or we assume the worst.",
        "Keep the motor pool locked. The last truck taken was taken by one of ours.",
        "Patrols in pairs, never alone, never past the second ridge.",
        "The towns are to be watched, not visited. Buy nothing from traders.",
        "Rotate the sentries every two hours. Sleeping on watch is a court matter.",
        "Mark every stranger on the board in the comms room, with the hour seen.",
    ]
    static let gwNews = [
        "The Capital's columns were seen on the east road. Count them if they come again.",
        "A trader swears the Ashguard are digging under the hills. Believe nothing, report everything.",
        "Our relief is late. The mountain passes are snowed in.",
        "The last convoy lost a wagon to wolves, the driver says. The driver says a lot.",
        "Someone has been cutting the wire on the south fence. Find them.",
        "The fortress to the west reports thunder with no storm. Guns, most likely.",
        "Three deserters were caught at the river. They said the war is lost. It is not.",
        "A sky-ship passed over at noon, flying no colours.",
        "The radio net was down two nights running. Use runners until it holds.",
        "The cook at the garrison mess has been stealing tins. He has been moved to the latrines.",
        "There is a stranger asking about our bases in the towns. If he comes, hold him.",
        "Pay is a month late. Tell the men it is coming. It is coming.",
    ]
    static let gwLore = [
        "Who takes this base takes its map table: the radar net shows our other bases.",
        "The map table in the comms room shows the radar net: guard it above all else.",
        "Should the base fall, burn the map table. It shows every base on the net.",
    ]
    static let gwLore2 = [
        "The Fortresses keep the fleet's orders in their war rooms.",
        "The fleet's sailing orders are kept in the Fortress war rooms, under guard.",
        "Orders for the fleet go by the Fortress war rooms only.",
    ]
    static let gwPS = ["", "Burn this once read.", "Do not trust the radio.", "Eat this if taken. It is thin paper.",
                       "The password changes at the new moon.", "Your request for boots is denied.",
                       "Tell the gunners well done for last week.", "Keep your head down."]
    static let gwHands = ["Greywall Command", "Col. Brannoch Hale, Greywall Command", "Maj. Isolde Varr, Staff",
                          "Cmdt. Oswin Thrale", "Capt. Ilse Morrow, Signals", "Col. Dacre Fenn", "Greywall Command, by runner",
                          "Lt. Col. Sabin Rook"]

    static func greywallDispatch(name: String, x: Int, z: Int, seed: UInt64) -> [String] {
        if old {
            return ["GREYWALL COMMAND - DISPATCH\n\nTo the \(name), grid \(x), \(z).\n\nHold the walls. Report any rider from the towns. Keep the alarm panels manned.",
                    "Who takes this base takes its map table: the radar net shows our other bases.\n\nThe Fortresses keep the fleet's orders in their war rooms.\n\n- Greywall Command"]
        }
        var p = Pick(x, z, read, seed ^ 0x6A11)
        read += 1
        let no = 100 + Int(p.h % 899)
        let p1 = "\(p.next(gwHeads))\nNo. \(no)\n\nTo the \(name), grid \(x), \(z).\n\n\(p.next(gwOrders))"
        let ps = p.next(gwPS)
        let p2 = p.next(gwNews) + (ps.isEmpty ? "" : "\n\n" + ps)
        let p3 = "\(p.next(gwLore))\n\n\(p.next(gwLore2))\n\n- \(p.next(gwHands))"
        return [p1, p2, p3]
    }

    // MARK: The Meridian fleet

    static let nvHeads = ["MERIDIAN FLEET - SAILING ORDERS", "MERIDIAN FLEET - SIGNAL", "FLAG OFFICER TO ALL SHIPS",
                          "MERIDIAN FLEET - SEALED ORDERS", "FLEET STAFF - MOST SECRET"]
    static let nvTask = ["and to hold the coast against the towns.", "and to stop every boat that comes out of the river mouths.",
                         "and to shell any battery that shows itself on the cliffs.", "and to meet the supply barges at dawn.",
                         "and to keep the sky-ships off the harbours.", "and to watch for the Ashguard's raiders by night.",
                         "and to fly the recall flag if the weather turns.", "and to sink anything flying no colours."]
    static let nvNews = ["The barometer is falling. Reef early.", "A gunner on the forward mount has the fever. Keep him below.",
                         "Powder is short: no salutes, no practice firing.", "A whale was taken for a submarine last week. Look twice.",
                         "The coast lights are out from the point to the bay. Navigate by stars.",
                         "Shore leave is cancelled until further orders.", "Fresh water at the second anchorage is foul. Boil it.",
                         "The town traders will offer fish for shells. Refuse."]
    static let nvLore = ["Her strongroom carries an Ember Charge for the Capital. It is not to be lost.",
                         "An Ember Charge rides in her strongroom for the Capital. Guard it with the ship.",
                         "The Capital's Ember Charge is in her strongroom. If she founders, it goes down with her."]
    static let nvHands = ["Flag Officer, Meridian Fleet", "Commodore Aurel Strand", "Rear Adm. Petra Lowe", "Capt. Hallam Drey, Fleet Staff",
                          "Signal Officer, Meridian Fleet", "Commodore Fiske Arden"]

    static func navalOrders(ship: String?, x: Int, z: Int, seed: UInt64) -> [String] {
        if old {
            guard let ship else {
                return ["MERIDIAN FLEET - SAILING ORDERS\n\nAll ships to put to sea and keep the far patrols.",
                        "Each flagship's strongroom carries an Ember Charge for the Capital. It is not to be lost.\n\n- Flag Officer, Meridian Fleet"]
            }
            return ["MERIDIAN FLEET - SAILING ORDERS\n\nThe \(ship) to keep station at grid \(x), \(z), and to hold the coast against the towns.",
                    "Her strongroom carries an Ember Charge for the Capital. It is not to be lost.\n\nBoarders are to be met at the rails.\n\n- Flag Officer, Meridian Fleet"]
        }
        var p = Pick(x, z, read, seed ^ 0x5EA5)
        read += 1
        let head = p.next(nvHeads)
        let p1 = ship.map { "\(head)\n\nThe \($0) to keep station at grid \(x), \(z), \(p.next(nvTask))" }
            ?? "\(head)\n\nAll ships to put to sea and keep the far patrols, \(p.next(nvTask))"
        let p2 = "\(p.next(nvNews))\n\nBoarders are to be met at the rails."
        let p3 = "\(p.next(nvLore))\n\n- \(p.next(nvHands))"
        return [p1, p2, p3]
    }

    // MARK: The Ash Chancellor's ledger

    static let lgGoods = ["Shells, fuel and Ember Charges", "Ember Charges, rifles and tinned meat", "Fuel, valves and two hundred shells",
                          "Cable, shells and a crate of Ember Charges", "Engines, fuel and Ember Charges", "Shells by the wagon, fuel by the tank"]
    static let lgNotes = ["Paid in full. The Capital asks only that the war below never ends.",
                          "Paid in gold from the vaults. The Capital asks no questions and wants no receipts.",
                          "Half paid. The rest when the Ember Line holds another winter.",
                          "Paid. The Capital's agent counted every coin twice and smiled once.",
                          "Paid in full, and a case of wine for the agent. Keep him sweet."]
    static let lgEnds = ["It has. The citadels are next.", "It is over. The citadels will pay instead.",
                         "The war below is lost. The citadels owe us now.", "The Chancellor keeps the ledger. The citadels keep the debt."]

    static func ledger(x: Int, z: Int, seed: UInt64) -> [String] {
        if old {
            return ["LEDGER OF THE ASH CHANCELLOR\n\nShells, fuel and Ember Charges, received from the Capital's citadel at grid \(x), \(z).",
                    "Paid in full. The Capital asks only that the war below never ends.\n\nIt has. The citadels are next."]
        }
        var p = Pick(x, z, read, seed ^ 0x1ED6)
        read += 1
        let entry = 10 + Int(p.h % 89)
        return ["LEDGER OF THE ASH CHANCELLOR\nEntry \(entry)\n\n\(p.next(lgGoods)), received from the Capital's citadel at grid \(x), \(z).",
                "\(p.next(lgNotes))\n\n\(p.next(lgEnds))"]
    }
}

// The check (questcheck suite): thousands read of each kind, every page on the book screen, and how many differ.
enum LetterCheck {
    static func run(_ check: (Bool, String) -> Void) {
        guard !Letters.old else { return }
        let r0 = Letters.read
        defer { Letters.read = r0 }
        var gw = Set<String>(), nv = Set<String>(), lg = Set<String>(), long: [String] = []
        for i in 0..<3000 {
            let x = 4000 + (i % 7) * 900, z = -3000 - (i % 5) * 700
            for (set, pages) in [(0, Letters.greywallDispatch(name: "Greywall Garrison", x: x, z: z, seed: 77)),
                                 (1, Letters.navalOrders(ship: i % 3 == 0 ? nil : "Meridian Frigate", x: x, z: z, seed: 77)),
                                 (2, Letters.ledger(x: x, z: z, seed: 77))] {
                let all = pages.joined(separator: "|")
                if set == 0 { gw.insert(all) } else if set == 1 { nv.insert(all) } else { lg.insert(all) }
                for pg in pages where Books.wrap(pg).count > Books.linesPerPage || pg.contains("_") { if long.count < 3 { long.append(pg) } }
            }
        }
        check(gw.count >= 1000 && nv.count >= 1000 && lg.count >= 1000 && long.isEmpty,
              "letters: 3000 read of each, \(gw.count) Greywall dispatches, \(nv.count) naval orders, \(lg.count) ledgers differ; every page fits the book screen"
              + (long.isEmpty ? "" : " (too long: " + long.map { $0.replacingOccurrences(of: "\n", with: " / ").prefix(80) }.joined(separator: "; ") + ")"))
    }
}
