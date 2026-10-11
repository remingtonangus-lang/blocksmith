# Tidebreaker gaps (Lane A) (Lane A, 2026-10-11)

## G1: the live helm shot never fired (done audit 25b6)
Objectives (backlog + Lane A's own):
1. Find why the g.tick path never finished the charge on the Mac harness, and fix the class, not the instance.
2. The helm shot through Game.tick charges for 2.6 s, fires one slug, lands where the marker shows and digs a crater of
   thousands of blocks, every run (no landing in water, no drift).
3. FactionTests fires a real slug at a citadel through the game loop (was Explosion.crater called directly), and the
   check gates questcheck.
4. The impact frame holds the Quest budget: the gun's biggest moment must not hitch.

Results:
- Cause: a fresh Game starts paused (Game.swift `paused = true`) and a paused Game.tick returns before advance(), so on
  the Mac harness (`--questbugs`) the shot charged for 400 empty frames (5.56 s). questcheck unpaused, so it passed.
  QuestBugTests.run and MainGunTests now unpause; every other g.tick test already did.
- FactionTests.frigate: a commandeered Meridian frigate 180 blocks off a citadel fires from its helm through Game.tick;
  the slug lands about 9 blocks from the citadel's centre and empties the inner bowl. Runs in questcheck after the main
  gun checks.
- Impact frame (host, -Onone): first frame 82-125 ms, worst 159 ms before; first frame 9 ms, worst 23 ms (water filling
  the bowl 2.5 s later) after. Causes: the structure lookup of what the slug hit planned a structure region (76 ms; now
  planned on a worker during the charge, MainGunStrikes.prewarm); a power-8 blast that breaks no blocks still cast its
  1,352 rays (17 ms; skipped); every crater cell marked ~40 circuit neighbours (7 ms a slice; skipped when no circuit
  part is within reach, World.circuitQuiet, scan spread over the first frames). New check: the impact's own work < 12 ms.

- Verifier pass (independent): the root cause, the FactionTests rewrite, thread safety and the circuit skip held up.
  It found a crash for a slug bursting above y 215 (the crater's circuit scan had an empty y range; fixed) and the
  test firing into a swamp in the full questcheck (the site is now chosen from the world spawn, in open country, and
  the test fails loudly when no dry landing exists). Full questcheck: every maingun and factions check passes; the
  12 failures left are the base's (town law/honour/bounty/six-iron/countries, the Marshal's barrage).

## G13: the gun did far too little to vessels; frigates carried Capital soldiers (Oct 11 AM playtest)
Objectives (backlog + Lane A's own):
1. A direct hit on a crawler wrecks it and tears out hundreds of blocks; a near miss beside it still hurts it.
2. The same rule for every Capital vessel (frigates, crawlers, dropships), one code path (mainGunHullDamage).
3. Frigate crews belong to their own navy: their own rank names (and the livery they already had), kept through a save.

Results:
- ShipManager.mainGunHullDamage: a direct hit tears a 12-block-radius hole (was 7) and knocks out the drive (a crawler
  is wrecked on its next tick, a flier goes down); a ground hit within 9 blocks of a vessel's bounds tears its nearest
  side (radius 12 - 0.6 x distance) and within 5 blocks wrecks it.
- Crews: Mob.faction's didSet gives a navy's soldiers that navy's ranks (Meridian Rating / Marine / Gunner / Heavy
  Marine / Lieutenant / Helmsman; Stormwarden and Ironback sets too). The faction is now saved for every faction, not
  only the Ashguard, so a crew no longer reloads as Capital soldiers.
- Checks: MainGunTests 7 (direct hit and near miss on an Ironback Crawler) and 8 (crew names).

## G11: no designed way to board the Meridian frigate from the ground (done audit 25b6)
Objectives (backlog + Lane A's own):
1. A visible, discoverable boarding route from the ground to the frigate 30-45 blocks up, without commands or a flyer.
2. It works while the frigate cruises (it heaves to for a boarder) and does no fall damage.
3. From where it sets you down, a walkable route reaches the helm, and an automated bot proves it through Game.tick.

Results:
- FrigateBoarding.swift: a cargo winch line from the port hangar door to the ground (a dark cable with a lit hook at the
  foot, drawn within 140 blocks; a toast the first time you come within 60). Stand at the foot (2.2 blocks) and it
  hauls you up at 9 b/s and sets you on the hangar deck. While a player is within 34 blocks of the foot the frigate
  heaves to (0.6 b/s, holding its heading) so the line can be caught.
- BoardingTests (questcheck, and the Mac `--questbugs`): a bot under a cruising frigate is hauled aboard, walks to the
  ladder at z 89, climbs to the bridge deck and walks to the helm with the left stick only.

## G8: the frigate's thrusters read as two small points at night (done audit 25b6)
Objectives: the stern reads as engines from a few hundred blocks at night; cheap (a handful of particles, one light).
Results: ShipManager.driveGlow: a blue-white glow sprite over each nozzle (7.5 blocks across, 3.5 for the centre one),
growing with distance up to 3x past 180 blocks so it never shrinks to a dot, brighter at night, flickering slightly;
one shared light on the stern within 160 blocks (the flash list is shared with gunfire). Works on AI and commandeered
frigates. Check: MainGunTests 1b (four or more nozzle sprites over 2.5 degrees across from 300 blocks astern at night);
render maingun_stern_night with --render.

## G6: the first citadel was hard to find (done audit 25b6)
Objectives: a walking player gets a lead to a citadel well before stumbling on one; the lead is loot the player meets
early (wild camps), and the first one read points to a citadel, not a city.
Results: outlaw camps always hold 1-2 Intercepted Orders (Loot extra pool), abandoned camps sometimes (weight 7); the
first orders read while no citadel is on the map mark the nearest citadel. FindabilityTests (questcheck): 50 of 50
outlaw chests hold orders, nearest outlaw camp versus nearest citadel from spawn on six seeds, first orders mark a
citadel.

## G12: capitals too common and one at the spawn (Oct 11 AM playtest)
Objectives (backlog + Lane A's own):
1. Capital citadels (the "capital with a crawler") never stand near the spawn and never two close together.
2. Citadels and Capital cities are rarer, but each still exists within a findable distance (the G6 orders point there).
3. Cities vary: a size per city (16, 24 or 32 lots) and its own mix of offices, squares and gardens.
4. Nothing already generated in a save is cut in half (a new guard file, structure-guard-g12.txt).

Results:
- Citadels: at least 640 blocks from the spawn (was 320), 60 % of 40-chunk regions keep theirs (was all), and none
  within 800 blocks of another (WorldRules.citadelApart, by region priority as L3 keeps cities apart).
- Capital cities: half the regions keep theirs (was 70 %); still 1,200+ from the spawn and from each other.
- City size and mix: CapitalCity.planFor draws small, medium or large (40/35/25 %), the building share (40-70 %),
  squares against gardens and the canopy share per city. Small cities keep at least six buildings.
- Ground saved before G12 (StructureCache.legacyG12) keeps the old rules and the old plan.
- Check: `--worldgencheck` (questcheck binary or Mac) fails on two citadels within 800, a citadel within 640 of the
  spawn or none within 1,600, and prints the citadel count and the city sizes.

## G7: a Capital city could be named "Meridian", the navy's name (done audit 25b6)
Results: the first city name is Brightmoor now (CapitalTown.cityNames); MainGunTests 8 checks no city carries the
navy's name. snap.sh renders capital_city (from above) and capital_street (street level). A saved city's fountain
sign keeps the text it was built with.
