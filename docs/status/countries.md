# Countries that give minerals (backlog B4, 2026-10-11, Lane B thread)

Remington's intent: there should be countries too that give minerals. Listed:
- the world is divided into a handful of countries with borders, flags, capitals and towns, each rich in particular
  minerals;
- they trade, tax and pay tribute;
- you can ally with one, raid another, or take one over through its capital;
- border posts, customs, and wars between countries that change the map over time.

## Expanded objectives (written before building)
1. **A country layer, seeded per world and deterministic.**
   - The overworld is cut into countries of roughly 2000 x 2000 blocks: a jittered grid of seats, and each place
     belongs to its nearest seat, so borders are straight-edged cells that read clearly on the map.
   - Each country has an original name from a syllable list, checked with namecheck.
   - Each has a two-colour flag (a banner pattern and two dyes), drawn on the map and in its town signs' toasts.
   - Its capital is the town nearest its seat. Its towns are the villages inside its border.
2. **Minerals.**
   - Each country is rich in two of: coal, iron, copper, gold, lapis, titanium and emerald.
   - Generation places extra veins of those under its land, on a separate random stream so nothing else in a chunk
     moves.
   - The richness is shown when you enter, and on the map legend.
3. **Borders.**
   - Crossing a border shows "Entering <name>: rich in iron and gold" with its flag colours, and the HUD minimap shows
     the country's name.
   - A border post stands on the border half way between two neighbouring seats (moved along the border off water and
     away from towns): a small flagged guard post that is the customs point. It is built the first time you come within
     96 blocks of it (so it never cuts through generated structures) and goes on the map.
4. **Trade, tax and customs.**
   - A country's towns sell its own minerals cheaper (x0.7) and buy them for less, and pay more for minerals they
     lack (x1.3), so carrying ore between countries pays.
   - Each country taxes purchases at its own rate (0-15%), shown in the shop.
   - Near a border post, customs asks a duty (8% of the value of the minerals you carry) for the country across it.
     Stop at the booth and it's paid; cross there without paying and it costs standing with that country. Crossing
     the wild away from a post is free.
5. **Standing with each country (-100 to 100).**
   - Crimes in its towns lower it (the honour and law system's offences, per country). Trade raises it a little.
   - At -50 or below you're its enemy: its towns start on edge and its lawmen draw on sight, as in a raided town.
   - You can ally with a country by paying a treaty fee at its capital's general store, with standing of 25 or more. An ally's
     shops give 10% off (never under the shops' best price) and its customs charge nothing.
   - Raiding (crimes, killing its law) is how standing drops.
6. **Taking a country.** Taking its capital town (the B1 surrender) annexes it:
   - all its towns treat you as their owner (best prices, no theft, tribute);
   - its flag on the map becomes yours;
   - its tribute is paid at the capital.
   Taking a lesser town still only takes that town.
7. **Wars that change the map.**
   - Countries keep relations with each other. Once per in-game day, neighbouring rivals may declare war or make
     peace.
   - A war shifts border towns: each day of war, one frontier town may change hands (seeded, so no flip-flopping in
     one day). The map, town ownership and prices follow.
   - News reaches you as a toast ("Ostvaal took Elk Crossing from Kesslemark") and on the map.
   - Your ally's wars are your business: helping (killing its enemy's law) raises your standing with it.
8. **Saves and performance.**
   - Saved in the world extra "countries": standing, alliances, annexed countries, wars and towns that changed hands.
     Old saves start clean.
   - Lookups are O(1) (a seat-cell lookup). The border check runs once a second; generation adds a few veins per
     chunk.

## Built (2026-10-11, Lane B thread)
- Sources/Countries.swift: the layer (2048-block jittered seat cells, nearest of 3x3), names (syllables, with a re-roll
  list of real places and historical names), flags, rich minerals, tax, capitals (the capital city, else the village,
  nearest the seat inside the country; a country with no town within four village regions of its seat has none and
  can't be annexed), standing, treaties, annexing, border posts and customs, wars, the minimap line and the big map's
  borders and names (with each country's minerals).
- Hooks: WorldGen.placeOres (extra veins on their own random stream), TownLaw.offence / turnHostile, TownConquest
  (owns, standing, lawFell, surrender), ShopPricing.country + Economy.buyPrice/sellPrice, the treaty service row,
  the shop's "Ostvaal, tax 8%" line, Effects save/load ("countries"), HudExtras.tick.
- Prices: a country pays x0.7 for minerals it's rich in and x1.3 for the others (never more than the least money that
  buys one), sells the ones it lacks at x1.3; taxes add on; an ally's 10% never goes under the shops' best price.
- Customs: crossing at a post owes 8% of the minerals' value to the country across; stopping at the booth (8 blocks)
  or passing through it between two ticks pays; crossing within 48 blocks of the post without passing the booth is
  running it (-10 standing).
- Border posts are built (deferred remesh) only on open ground: no structure within 24 blocks, no built blocks in the
  footprint, the whole footprint loaded and the player not on it.

## Differences from the objectives
- Enemy towns start on edge (heat one short of hostile, the wary prices); their law doesn't draw on sight until you
  give them a reason.
- The treaty is signed at the capital's general store, not its sheriff.
- War news is a toast; towns that changed hands follow the new owner in prices, annexing and standing, but aren't
  recoloured on the map.
- Towns are keyed by name (as TownLaw and TownConquest already are): two towns with the same name share a country.
- Flag colours show on the map, the minimap line and the posts, not in toasts (toasts are plain text).

## Checks
TownTests "countries:" (CountriesTests.swift): the layer, a chunk with and without its country's veins (only rich ores
added, into stone), prices and no money loop, crossing, standing and enemies, trade goodwill, capital, treaty, ally
prices, duty, annexing, the border post (owe, pay at the booth, pay riding through, run it), building a post, wars over
60 days and a frontier town changing hands, save/load, the map borders.
