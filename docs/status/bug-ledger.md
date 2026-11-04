# Bug ledger (week plan item 1: 1,000 real bugs)

Each entry is a bug a player could hit. It was reproduced before the fix (a host check or a measurement), proven gone after, and
fixed at its root. Item 5 (bloom) applies to every entry: after each fix, look for the same mistake elsewhere and log what turned
up. Newest at the bottom.

Count: 9

| # | Found | Bug | Root cause and fix | Proof | Bloom |
|---|-------|-----|--------------------|-------|-------|
| 1 | Nov 3 | Revenge-raid dropships never reached his home | Ships beyond the active distance (136 blocks at view 8) sleep, and the dropship is called from 260 blocks off, so it hung in the sky. A dropship on its run stays awake (ShipPhysics). | --encounters: before, 0 troops landed; after, 6-7 landed and fought him | Same mistake: entry 2 |
| 2 | Nov 3 | Corsair sloops and the Corsair Cruiser never came for him at sea | The same sleep: sea hunters roll in 150 blocks off. Hunters stay awake. | --encounters: the sloop went from 150 to 24 blocks off and fired 14 rounds | Other far spawns aimed at him: still to sweep |
| 3 | Nov 3 | Gun-station chairs blocked the frigate's stairwell, so crew and boarders could not reach the bridge | Stations were placed without checking walkways. Now a station is never placed if it cuts the hull's largest walkable stretch (GunStations Walkways). | --render boarding: before, stuck at the rails | Every placed-furniture generator should do the same check: to sweep |
| 4 | Nov 3 | A crewman in a station chair floated 0.4 above the seat | Deck collision lifted it out of the chair's box. A mob at a station is now held to its seat (Mob.swift). | --gunstations: off its chair 0.40 before, 0.00 after | |
| 5 | Nov 3 | Triple Mount on the range couldn't be used | A Gun Barrel only lengthens a cannon, and that mount had no cannon. Each row now starts at a cannon. | --proving: Triple Mount now taken and fires | |
| 6 | Nov 3 | FactionRaidsTests expected two dropships, but a raid lands one | The test was out of date. | the raids check | |
| 7 | Nov 4 | The Stormwarden's mast-top gun had no station: no one could work it while he drove | Its mount has no room within 18 blocks. A last, wide look (40 across, 48 up and down) finds the hull's nearest room for its computer, and the assignment gives a gun with nothing near the nearest free station further off. | --gunstations: 15 of 16 before; the check now asks for every gun | Any other gun without a station: the check now fails on one |
| 8 | Nov 4 | The Meridian Frigate's stern thrusters floated: 209 glowing cores joined to nothing | Each core sat a block in from the stern over the hollow behind the engine room's bulkhead, with its nozzle ring only at the stern face. The ring now runs a block deep round the core. | --frigatelayout: 263 loose before | The other loose groups (17 hull at z 121, 15 trim on the bridge top, lights, plates) are listed cell by cell for the next pass |
| 9 | Nov 4 | "balance gear pays" failed at random (Capital Trooper one run, a Gravesworn another) | A trooper's vest takes a blow by where it lands, so one duel's kill time was luck: 4.6 s early and 5.3 s iron on one run, 3.3 s iron on the next. The duel against troopers now takes the middle of seven seeds. | the --render suite | Other single-seed duels: the witch's potion pick already averages three |
