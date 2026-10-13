import Foundation

// P189 (Oct 13 13:25: "a journal that collects everything I read: Capital logs, pamphlets, orders, notes"): things to
// read in the world, found in chests. Each is a book item (DeepJournals' registry: use it to open it, BookMenu then
// files it in the Journal, which keeps every document whole to reread). Capital duty logs (fortress and station
// supply and command chests), Greywall field notes (their bases), town pamphlets (village houses and Capital
// cities).
enum Readables {
    static let all: [String: DeepJournals.Journal] = [
        "capital_duty_log": DeepJournals.Journal(title: "Capital Duty Log", pages: [
            "DUTY LOG - WATCH 4\n\n0600 Relieved the night watch. Nothing on the road but a mule cart, papers in order.\n\n0900 Rations short again: two crates of biscuit for forty men.",
            "1300 Greywall smoke on the ridge, east. Reported by runner. The lieutenant says it is charcoal burners. It is not charcoal burners.\n\n1800 Gate shut. Lamps lit on the wall.",
            "2300 Shots in the hills, three, far off. The deck gun crew stood to and stood down.\n\nIf the relief does not come by the end of the week we hold the gate with cooks.",
        ], tint: 0x5A4A3A),
        "capital_signal_log": DeepJournals.Journal(title: "Signal Room Log", pages: [
            "SIGNAL ROOM - RECEIVED\n\nFrom Column Grey: patrol returned, one horse lame, no contact.\n\nFrom the coast battery: shells received, fuses wrong pattern, returning half.",
            "From Staff: all posts to keep the radio silent after dark. Messages by runner only. Greywall listens.\n\nFrom Staff: a reward of 200 for word of the outlaw riders on the old road.",
            "Not sent:\n\nWe have heard the frigate's engines twice this month and seen nothing. Whoever is out there knows our hours better than we do.",
        ], tint: 0x3A4A5A),
        "greywall_field_notes": DeepJournals.Journal(title: "Greywall Field Notes", pages: [
            "Greywall holds the high ground because the Capital never wanted it. Stone, snow and goats. We made it a wall.\n\nThe towers watch the passes. A lookout in every one, day and night.",
            "The Capital's men march in step and shoot in step. Let them. A rifle behind a rock beats ten on a parade ground.\n\nNever fire first from a tower: it gives the tower away.",
            "Supply comes up the mule road on the third day. If it does not, the armoury feeds us until it does.\n\nWhoever finds this: the passes are ours. Walk them quietly.",
        ], tint: 0x6A6A70),
        "town_pamphlet": DeepJournals.Journal(title: "Town Pamphlet", pages: [
            "WELCOME, TRAVELLER\n\nThis town keeps the peace. The sheriff keeps the town. Bounties are posted at the board by his office, paid in emeralds, no questions asked.",
            "Trade with the shops by day. The gunsmith sells rounds for every make of gun, the general store sells food and lamps, the stable sells horses and tack.\n\nNo shooting in the street.",
            "Mind the roads after dark: outlaws ride them, and the Capital's patrols are not always kinder.\n\nA bed at the inn is cheaper than a grave.",
        ], tint: 0xC8B890),
        "capital_recruiting_pamphlet": DeepJournals.Journal(title: "Capital Recruiting Pamphlet", pages: [
            "SERVE THE CAPITAL\n\nA rifle, a uniform and three meals a day. Pay on the first of the month. See the world from the walls of a fortress.",
            "The Capital brings the roads, the rail and the law. Greywall brings only snow and trouble.\n\nAsk at any Capital post for the recruiting officer.",
        ], tint: 0xA04030),
    ]
}
