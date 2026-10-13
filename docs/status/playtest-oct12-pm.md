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
