# Oct 12 afternoon playtest fixes (P107-P139)

Check: `questcheck --p12pm-only [P1xx]` (`Sources/PlaytestOct12PMTests.swift`), one check per item.

- **P107 smooth worlds reopen smooth.** `world.json` is written as soon as a world is created (it waited for the first
  autosave), and saves encode non-finite floats as strings (`SaveIO.encoder`/`decoder`): one such float made every
  later save throw, so the world reopened with default options (blocky).
- **P108 HUD over the hotbar.** The right-hand context prompts move up above the hotbar whenever they would reach it.
- **P109 left grip with a gun.** `VRReload.atHip` also needs the hand not out in front of the body, so a grip at the
  waist in front steps the hotbar.
- **P110 icons.** Inventory icons draw the state facing the viewer (`Blocks.iconState`); beds draw both halves; the
  observer has a new face (a lens in a copper ring) and a copper side strip (its imported art was removed).
- **P111 textures.** Cobweb and amethyst block use their painters again (`TextureGen.painted`). Granite, diorite and
  andesite were sharpened; stone is the deepslate rock re-toned light grey, and the stone ores were rebased on it
  (Resources/Textures, `texpack.bin` rebuilt with tools/texpack.py). `questcheck --texdump OUT.png a,b,c` shows layers.
- **P112 cave water.** Small pools sunk into cave floors (`WorldGen.floorWater`), held on every side.
- **P113 sky in caves.** Underground (rock 6+ blocks over the eye, little skylight) the Quest sky pass draws only dark
  fog and the cave fog closes before the far sections are culled.
- **P114 lava.** Fluid cells within 24 blocks of the player tick first (`FluidQueue.urgent`), so nearby lava flows
  steadily; a block can be placed into lava with nothing solid in reach (`LavaPlay.placeIntoLava`); dropped items burn
  in lava and fire (Duskium gear and the like don't); the Quest view shows flames while burning.
- **P115 bounty hunters.** No posse while the player is underground (rock 4+ over the head or little skylight) and
  hunters lose the trail there; the chance is 1 in 900 a second with at least 3 days between posses; 5 to 6 riders,
  7 to 8 for an outlaw.
- **P116 journal.** Every message and every document read is kept (`Sources/Journal.swift`, saved); the pause menu's
  Journal opens it as a book, newest first.
- **P117 horse underground.** Calling from underground: "<name> can't hear you down here"; a call in progress stops
  when the player goes below.
- **P118 gravel.** A body knock plus five pebble clicks instead of a wash.
- **P119 magazines.** Rounds craft into magazines (`Sources/Magazines.swift`, 10 to 30 rounds, stack 16); they count as
  ammo. In the headset the reload button and the empty-trigger reload are gone: reach to the hip for a magazine.
- **P120 Capital rounds.** Steel ingot, copper ingot and two gunpowder make 12.
- **P121 floating pieces.** Generation drops rails over air and amethyst buds with nothing to hold
  (`PlantSupport.dropFloating`).
- **P122 placing while jumping.** Placing a block under yourself in a jump lifts you onto it.
- **P123 armour bars.** Each bar has its piece's icon, under an "Armour" heading.
- **P124 hitch.** A walk probe (`Sources/HitchProbe.swift`, profiler marks through the bases tick) caught 500-620 ms
  ticks in the Greywall alarm: the per-second base ticks asked for the nearest Greywall base, Boreal Station and citadel
  on the frame thread, and a fresh region planned its start there (a Greywall start tries up to seven sites, each
  checking ten other kinds' starts). `StructureCache.nearestIfReady` now answers only from planned starts and plans the
  missing ones on a worker. Also: the structure cache evicts its least recently used quarter instead of emptying, and
  the Greywall alarm's block scan walks loaded sections through a kind table.
- **P125 Lanternvine.** Cave vines are Lanternvine; podded ones glow and drop Lumen Pods (teal), regrowing pods over time.
- **P126 sneak edges.** Sneaking backs a move off an edge on each axis, in room-scale too.
- **P127 sleep and timed work.** Beds work from dusk (0.497); furnaces, brewing stands and campfires catch up on up to
  2 hours missed while unloaded or asleep.
- **P128 double doors.** A door next to another takes the opposite hinge, so the pair opens outward to the sides.
- **P129 crafting book.** The click that opens the book does nothing for 0.35 s; grip or right-click only selects.
- **P130 steady shovel.** No progress during the swing cooldown, no chips on fast blocks, progress remembered per block.
- **P131 home finder.** An orange H marks the bed on the map and the minimap edge; "Home 342 NW" shows past 200 blocks
  or with a compass.
- **P132 rail network.** The Engine Cart (minecart, furnace, piston, copper ingot) runs on coal, coal blocks, blaze rods
  or a Copper Battery and drives at up to 14 blocks a second (7 in curves). Riding with rails in hand and use held lays
  track ahead. Ticket offices sell trips to found stations on other lines (fare by distance plus a change). Mine drifts
  join round the shaft on rails.
- **P133 base sundries.** Ten useless-to-you base items (Requisition Form, Duty Roster, Tin of Boot Polish, Spare Radio
  Valve, Typewriter Ribbon, Rubber Stamp, Empty Sandbag, Tent Pegs, Mess Tin, Spent Casings; `Sources/BaseSundries.swift`).
  About half of Steelhold, Greywall and Ashguard supply chests hold one or two; base barrels (mess, yard, generator room,
  stores) are filled with them plus rations and baked potatoes. Using one reads its note; stores buy them for pennies.
- **P134 mob variety.** A monster rolls a build: one in five a runner (x1.35-1.7 speed, x0.5-0.8 hits), one in five a
  brute (x0.6-0.8 speed, x1.4-2 hits, tougher), the rest middling. Voidwalker and slime hits now vary too. A Powderwight
  within 20 blocks runs (x1.7, about 4.2 blocks a second).
- **P135 small missiles.** `Sources/SmallMissiles.swift`. Pod salvos are small missiles (blast 1.0, was 2.5) from a load
  of three salvos. Crawlers (6), pod-less frigates (10) and citadels on alert (8, restocking one per five calm minutes)
  launch single homing missiles at a survival player 24 to 120 blocks off, 6 to 9 seconds apart.
- **P136 sword damage.** Swing power is tip speed / 4.5 m/s (0.45 to 2), times up to 1.4 for the tip's travel this
  swing. Hits on the head (top fifth of an upright body, the front of a beast's upper half) do x1.5, swung or aimed.
- **P137 repair cost.** A full anvil repair takes 4 material units plus one per upgrade level.
- **P138 blueprints.** `Sources/Blueprints.swift`. In survival an upgrade line needs its blueprint, read once and kept with
  the world. About one chest in four holds a random one (advanced lines a third as often). Older saves know the lines on
  carried items. The host checks fit freely (`Blueprints.on = false`).
- **P139 next step.** A goal step "Raid a Capital citadel's command room for an Ember Charge" sits before the Ember Gate,
  and the gate and Deep goals name the charge. Hitting Wardstone says no ore or tool breaks it and marks the nearest
  citadel on the map with its bearing.
