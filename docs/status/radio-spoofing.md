# Radio spoofing (backlog C6)

Lane A thread, 2026-10-12. Code: Sources/RadioSpoof.swift (RadioNet, RadioState, RadioMenu, the Game hooks),
RadioTests.swift (`questcheck --radio-only`; every full run).

- Where: the command console of a Greywall base or a Capital citadel. Using it opens that base's radio net (a list
  screen); a console anywhere else still gives the 30 s radar picture (P36), which is also the net's first row.
- Requests, as the garrison:
  - Supply drop: green smoke in the yard (Greywall: in front of the keep; citadel: the plaza), 8 s later a crate lands,
    filled from the faction's supply table.
  - Fire mission on your nearest waypoint: three shells with red smoke markers, 6 s out, up to 600 blocks from the
    base. No waypoint, no mission; the grid must be loaded.
- Suspicion per faction net, shown in the screen's corner (calm, wary, suspicious, they know): +25 a request, +15 more
  for a repeat within a minute, +60 more for shells on their own base. It cools 1 point every 20 s.
- At 100 they know: that console's net answers "Unknown station" for good, the faction's citadels within 1,500
  blocks go on alert and its Greywall bases sound the alarm as soon as you step inside (10 minutes), and a hunter
  squad (a Spec Ops lead, two troopers, a marksman) comes for you from 50 blocks off.
- Saved per world: suspicion and the dead nets.

Defaults picked (no questions): a truck convoy was left out (supplies come by drop, the same request); the strike
grid
is your nearest waypoint (the map's waypoint is the one grid a VR player can already set).
