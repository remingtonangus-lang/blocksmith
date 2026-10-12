# Greywall Command: military bases as their own faction (backlog A1)

Lane A thread, 2026-10-12. Code: Sources/Greywall.swift (faction, tiers, placement, layouts, blocks, loot),
Sources/GreywallAlarm.swift (alarm, reinforcements, leash, wall turrets, taking a base, radar net),
Sources/GreywallTests.swift (`questcheck --greywall-only`, part of every full questcheck run; `--no-greywall` skips it).

## What the player finds
- **The faction.** Greywall Command is separate from the Capital: its soldiers are the soldier mob kinds in grey
  livery (Sentry, Rifleman, Marksman, Heavy, Officer, Crewman), with their own loot tables. They shoot the player and
  fight Capital units on sight. The faction is saved with each soldier.
- **Four tiers**, placed by distance from spawn, each bigger, rarer, better defended and better looted:

  | tier | half-size | wall | troops | towers | from spawn | share of bases |
  |---|---|---|---|---|---|---|
  | outpost | 14 | 5 | 6 | 1 | 600+ | 60 % |
  | garrison | 22 | 7 | 14 | 2, gatehouse | 900+ | 25 % |
  | fortress | 30 | 9 | 24 | 4, inner wall, motor pool, vault, deck guns | 1,500+ | 11 % |
  | command fortress | 38 | 10 | 36 | 4, plus an underground war room and vault | 3,000+ | 4 % |

  Regions are 64 x 64 chunks (1,024 blocks); about 45 % of regions hold one (rarity check, 3 seeds). A walking player
  finds an outpost in a long session; the Radar Set lists the nearest Greywall base.
- **Alarms.** Red caged alarm lamps on the walls, towers and keep. A hostile noise inside the walls (a shot, a blast,
  a wall turret firing), or a soldier who sees a player inside, lights every lamp; a klaxon sounds from the keep or the
  gate; the garrison stands to. It stands down 45 s after the last noise or fight.
- **Alarm panels** in the keep, the towers and the comms room. Break them (pickaxe) or shoot them (three rounds): a base
  with every panel down can't call for help.
- **Reinforcements** (fortress and up): while the alarm is up and a panel stands, a squad of three marches in at the
  gate every 45 s, at most four squads an alarm.
- **Wall turrets** (garrison and up: 2, 4, 6) sit in merlon gaps facing out. A turret that sees the player in front of
  it within 40 blocks winds up 0.9 s (a red flash and a whine: the telegraph), fires a three-round burst, cools 1.6 s.
  Six hits leave it damaged (sparking, 1.4 s wind-up, wider spread), six more wreck it. Tower deck guns (fortress and
  up) are the base's naval guns: they shell the player and enemy ships, worked by the tower's lookout.
- **The leash.** A base's soldiers chase a player anywhere inside the walls plus four blocks, hold at the leash and
  keep firing, and walk back in if carried out. Reinforcement squads are leashed too.
- **Taking a base.** Kill every soldier inside the walls (a player inside, so the whole garrison is loaded), then
  stand at a command console for 10 s ("hold the command console to take the base"; walking off restarts it). Then:
  the flag on the keep becomes yours, the alarm is silent for good, the turrets stand down, the deck guns are gone,
  and the base's yard by the gate is your respawn point.
- **Respawn rules.** Taking a base sets your respawn to its yard. Sleeping in a bed afterwards moves it to the bed, as
  any bed does; taking another base moves it there. A charged Rebirth Anchor still wins over both while charged.
- **The radar network.** A base you hold: use its map table to mark every other Greywall base within 3,000 blocks on
  your map. Before you take it the charts are locked.
- **Saving.** Taken bases are saved (Effects.swift meta key `greywallTaken`). Alarms are in memory only, like Boreal
  Station's: a reload finds a base quiet (lamps saved mid-alarm are darkened when it is next scanned).

## Defaults picked (no questions asked)
- The name Greywall Command (checked against docs/status/ip-renames.md: original).
- Bases only on new ground: worlds saved before this change keep their ground (structure guard file
  `structure-guard-greywall.txt`, like G20Guard).
- Coastal placement for command fortresses was not done: the deck guns on the towers are the naval guns, and they
  already engage ships in range. Logged as a T item.
- The outpost gets a map table too (the objectives said a field radio).

## Checks (`--greywall-only`)
faction (parse, names, save, foes both ways), alarm (lamps lit, garrison stands to, squads, panels down stop squads,
stand-down), leash (held at the wall, walks back), capture (blocked by a live soldier, taken after 10 s at the
console, guns gone, respawn in the yard, kept through a save, walking off resets), radar net (other bases marked),
turret (wind-up telegraph, line of sight, damaged then wreck, stands down when taken), rarity (3 seeds, R = 6 regions
around spawn), and per tier: structcheck walkability with no issues, troop count, keep floor, walk-in from outside the
gate to every room, the tower roof, the wall walk (and the command hall, war room and bunker vault on the bigger
tiers), loot tiers in chests, lamps, panels, map tables, wall turrets and the flag.
