# The Meridian Navy (backlog A3)

Lane A thread, 2026-10-12. Code: Sources/Navy.swift (Aegis Marines, shields, Pulse Charge, boarding parties, frigate
radar), with hooks in Mob.hit, Soldiers.soldierAI, Ballistics (pulse rounds, arc beams), FactionGear (use, radar
readout), CapitalShips (party timers). Checks: NavyTests.swift (`questcheck --navy-only`; part of every full run).

- **Names.** The navy keeps its own name, the Meridian Navy. Its super soldiers are **Aegis Marines** (the reference
  series' word stays out: tools/coined-terms.txt).
- **Aegis Marines** are the Meridian heavies (every Meridian ironclad post, and one leading each boarding party):
  Hannibal plate (A2) under a regenerating energy shield of 40. The shield soaks every hit whole: it flares (a blue
  sheen and a chime); a hit bigger than what is left pops it (a blue burst, a flash, a shatter) and the rest goes
  through to the plate. Four seconds after the last hit it starts back (a click) and refills at 10 a second.
- **Shield breakers.** The Pulse Charge (shapeless: a radar module, two copper ingots, two redstone: two charges) is
  thrown with use; it bursts on landing or its fuse, popping every shield within 5 blocks and holding it down 8 s. Arc
  gun beams take triple their damage off a shield.
- **Boarding parties.** An AI Meridian frigate hunting the player within 70 blocks of its boarding winch lowers a
  party down the line: an Aegis Marine and two marines, 30 s apart, at most two a frigate.
- **Frigate radar.** The pilot of a captured warship (frigate or crawler) reads a radar over the hotbar: Greywall
  bases (by tier), Capital citadels and cities, and enemy warships within 1,500 blocks, nearest first, with bearings.
  The Radar Set also lists the nearest Greywall base.

## Defaults picked
- Shore bombardment of Greywall bases by frigates was not added: the main gun's AI targets ships, mobs and the player,
  not sites. Logged as a T item.
- Frigates still sail only after the end game, as before (FactionGear's rule).
