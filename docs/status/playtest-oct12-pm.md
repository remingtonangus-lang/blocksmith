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
