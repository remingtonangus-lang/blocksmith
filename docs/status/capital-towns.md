# People in the Capital cities (2026-10-10, branch claude/project-thread-db44wr, PR into quest-port)

## What a player sees
- Capital cities were soldiers only. Now each has a market: the four lots nearest the fountain hold two storefronts
  each, all eight town shops (general store and saloon on the lot nearest the fountain, the others in a city-dependent
  order). A storefront is Capital white with a glazed front, a 3-wide way in, the shop's sign over it, an awning, the
  shop's colour across the fascia (the doctor's red cross above the awning), and inside the same counter, keeper, bed
  and fittings as a town shop. The keepers sell and buy in dollars exactly as in towns (Shops.swift).
- About half the other buildings are flats: beds against the back wall with a night stand and lantern, a resident
  for each (up to 3 a block). The rest are offices. Every city has at least eight buildings; a flat with no office
  within two lots becomes an office.
- Citizens ("citizen" role) keep a city day: their office desk from 2000 ticks (the nearest office, or the next one
  over), lunch at the saloon, the square's bell in the afternoon (every square and the civic centre has a bell on a
  white post), the saloon in the evening, home to bed. They dress for the city (pale shirts, dark coats or
  waistcoats, bow ties, bowlers; dresses and bonnets), carry nothing and run from monsters: the Capital's soldiers
  keep the streets. They greet you with city lines and say they are from the city.
- The city has a name ("Welcome to / Meridian / Capital City" on the fountain's north rim; 16 original names in
  CapitalTown.cityNames). Townsfolk within 130 blocks of a capital's centre are from it.

## Fixes for every townsperson (found by the new day sim)
- Bed reach: the path to a bed ends beside the pillow or on the foot end (the head is against a wall), about 1.2-1.45
  from the pillow, and lying down needed 1.2: 4 of 20 slept, the rest stood on the foot of the bed all night (and a
  villager who did lie down was 1.45 from the pillow and woke the next tick). Now up to 1.6 with a clear line
  (World.clearShot, so never through a wall).
- Counters: a keeper strolling round the counter (radius 2.5) picked goals a block up, i.e. the counter top, and
  stood on it. Strolls in a tight area (radius 3 or less) keep to the anchor's floor (Mob.strollGoal).
- Range: path searches gave up on any goal more than 48 blocks away (x + z) without searching, so a citizen whose
  bed was 52 away walked straight at the office wall all night. Villagers search up to 100 (PathProfile.range), still
  capped at 1500 nodes and time-sliced as before.

## Code
CapitalTown.swift (market and storefronts, flats and residents, desks, squares' bells and the name sign, city names),
CapitalCity.swift (Plan.shops/flat/seed, planFor split out of site, building footprint shared with CapitalTown, flats
in building()), StructureStart.plan (the city plan kept for name lookups and the checks), Townsfolk.swift (citizen
tag "citizen@x,y,z", city greetings, Townsfolk.town knows capitals), TownsfolkModel.swift (city clothes),
VillageLife.swift (citizens work at their desk; bed reach), Mob.swift (tight strolls), Pathfinding.swift (range).

## Checks (repeatable)
- `questcheck` (every Quest host check) and Mac `--towntests` run CapitalTownTests via TownTests.run;
  `questcheck --capitals-only [--seed N]` runs only these (about 70 s on the 4-core cloud box, `CAPITAL_DEBUG=1` prints
  who is late or awake with their path state):
  - plans: 3 cities each hold all 8 shops on 4 market lots, flats and offices, at most a third of flats without a desk;
  - city: one keeper of each kind, a sign per shop, the name sign, a bell, 8+ citizens (2/3 with a desk), a bed for
    every keeper and citizen, everyone and every desk on a floor with head room;
  - day: through Game.tick, 90% of citizens reach their desk in 180 s of work hours and 90% of citizens and keepers
    are asleep in bed within 150 s of night.
- Results (2026-10-10): seeds 12345 / 777 / 424242 / 9001: desks 12/12, 24/24, 9/9, 30/30; asleep 20/20, 32/32,
  17/17, 38/38.
- `questcheck --render R.png --golden DIR`: capital_market.png (the general store's front from the walkway).

## Pre-mortem (5 ways a player could break or dislike it, and the test for each)
1. Shops you can't find or get into in a white city -> storefronts on the lots round the fountain, signs counted,
   keepers on a floor with head room (city check), the market golden shot judged by eye.
2. Townsfolk stuck against walls or standing on furniture all day -> day sim desk and bed goals at 90% on 4 seeds; the
   bed/counter/range fixes above.
3. A dead city (a few people, or none) -> at least 8 buildings, 8+ citizens checked; seeds give 9-30 citizens.
4. Frame rate in the capital (more mobs) -> at most 3 residents per flat (9-30 citizens + 8 keepers), path searches
   stay inside the existing per-tick budget (1.5 ms, 4 searches); bench route_capital to be re-measured on device.
5. Old worlds -> chunks already generated keep their buildings; a city half generated before this change gets the
   new lots only in chunks generated after it (lot kinds changed for the market and the extra buildings).
