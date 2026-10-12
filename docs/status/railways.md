# C1 railways (2026-10-12)

What shipped (Sources/Railways.swift, Sources/Trains.swift, check: `questcheck --rail-only`, Sources/RailwayTests.swift):

- **Lines.** Rare, procedural, generated with the world. A village row (34-chunk regions) is split into stretches of six
  regions; about one stretch in three carries a line linking the towns along it (three to six stations). Rarity is
  measured over 24 seeds by the check (target: about one line per 4,000 x 4,000 blocks, the citadels' rarity).
- **Track.** Each station sits on a straight along the south edge of its town; between towns the track runs east,
  dog-legs north or south on two flat curves and runs east again. The profile follows the land at most one block a
  step: cuttings and tunnels through rises, spruce trestles with legs over dips, rivers and lakes. Curves and platforms
  are level. Never over the open sea; a leg that would cut through any surface structure is moved (five tries) or the
  line ends there. Buffer stops at both ends.
- **Stations.** Platform with lamps on the town side, a station house across the track with the town's name and a
  TICKETS board.
- **Old saves.** Ground any save generated before railways (`structure-guard-c1.txt`) keeps no line.
- **Trains.** One steam train per line (locomotive, coach, express car) shuttles end to end on a world-time timetable,
  24 s at each station, chuffing smoke and whistling as it leaves. Cars exist only near the player and are never saved.
- **Riding and fast travel.** Use the coach to ride (sneak to get off). The TICKETS board sells a fare to every other
  station ($0.02 a block of track, at least $1); the trip passes in a fade and the clock moves on.
- **Robbery.** Hold a gun on the driver for 1.5 s (20 blocks or nearer) or block the track and the train brakes;
  crack the express car's strongbox (five uses, or one with TNT): $40-$120 plus gold and emeralds. Honour -15, a $80
  bounty in the nearest town and two posses ride out. The train runs again once you are 48 blocks away or after a
  minute; it carries no money again that day.
- **The Ash Vault.** Armoured trains (armoured locomotive and a gun car with a turret) shuttle the four Vault lines
  between the citadel halt and each garrison town; the gun car fires bursts at you; explosives wreck it.
- **Map.** Reaching a station marks every station on its line ("R" markers).

Leftovers (not built): passengers you can see in the coach, a timetable board showing the next train, the posse on
horseback chasing the train.
