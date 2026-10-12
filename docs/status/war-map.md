# C2: the living war map (Lane A, 2026-10-12)

What a player sees: neighbouring countries that go to war (Countries.swift, B4) now fight along a front line that
moves day by day. News of big pushes near you comes as a toast ("Battle on the Ostvaal-Kesmark front: Ostvaal advances
180 blocks"). Towns behind the line change hands, and go back when the line comes back. Near an active front you hear
distant guns and see smoke over the line. The world map draws each front in orange. A Greywall base you have taken
has a war table: its map table opens a War Report with each war near you, who holds how much ground, both sides'
strength, the towns taken and your part in it.

How it works (`Sources/WarFront.swift`; fully procedural, no hand-placed events):
- A war's front is one number: how far the line sits from the old border along the line between the two seats.
- Each day of war: each side's strength (a seeded base, towns held against towns lost, the player's part) sets the
  push, and a seeded roll adds the fortunes of battle. The front never goes past 3/4 of the way to a seat, so the AI
  never takes a capital (only the player does, through TownConquest).
- Known towns follow the line with 40 blocks of slack, so a stalled front doesn't flip a town every day.
- Your part: killing a country's law (-6), taking one of its towns (-10) and trading with it (+0.3) while it is at war
  shift its strength. It fades by a tenth a day.
- Everything is a function of the world seed, the day and the saved state (`fronts`, `might` in the countries save),
  so a save replays the same war.
- Checks (`questcheck --towns-only`, `Sources/WarFrontTests.swift` through CountriesTests): a war moves a frontier
  town; over 90 days an even war's front ranges widely while the town by it changes hands only a few times and never
  straight back; the front stays bounded; the same 20 days end in the favour of whichever side the player helps; the
  same days replay the same front; fronts and might survive a save; the map draws the front; the report names it.

Defaults picked (no questions asked, per the standing rules):
- The war map is the countries' wars (the land factions). The Capital, Greywall and the navy keep their own bases; they
  don't hold territory on the map. Folding them in needs each to own ground first, which none does today.
- Battles are simulated, not spawned: no armies walk the line (a battle you can join with soldiers on both sides is a
  later item, T12).
- Only wars between the player's country and its neighbours are simulated (as before), so a far-off war pauses while
  you're away and picks up when you return.
