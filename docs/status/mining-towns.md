# Mining towns (C12)

Code: `Sources/MiningTowns.swift`. Check: `questcheck --mines-only` (`Sources/MiningTownsTests.swift`).

The abandoned mineshafts are retired on new ground. Ground a save had generated before C12 keeps its old shafts
(`StructureCache.legacyC12`, `structure-guard-c12.txt`). In their place, a town with 15 or more lots (C13 will tie this
to town size) works a mine. The mine sits past the end of a street, on ground that a save had not generated before C12.

- **Head frame.** A railed plank deck over a 3x3 shaft, with four log posts, a beam frame and a chain over the opening.
  A sign gives the mine's name ("<Town> Mine"). A ladder runs from the deck to the bottom of the shaft.
- **No. 1 level** (24 blocks down). It has two drifts, both on rails with a mine cart. Timber supports (posts and a cap
  beam) stand every 4 blocks, with a lantern on every other one. At the foot of the shaft are the expedition stores: a
  chest (`mine_stores`: TNT, torches, lanterns, rails, picks, food, ladders) and two TNT in a powder niche across the
  drift. Miners work at the faces.
- **No. 2 level** (y -34). The main drift runs to the deep vein, a 7x7 chamber walled with gold, titanium, redstone,
  emerald and iron ore. The side drift is blocked by an old fall of gravel, with a warning sign. Past it, a gas pocket
  sits at the end of the drift beside a gold seam.
- **Loose ground.** Stretches of roof are lagging boards with gravel packed above. Break or blast a board and the
  gravel falls. Knock out a support post and its cap beam goes, and the roof above it caves in.
- **Gas** (firedamp, checked once a second from TownLaw.tick):
  - Inside a pocket you choke (nausea and poison).
  - A naked flame sets the pocket off with a power 4 blast. That means a torch, flint and steel, a fire charge or a
    campfire in hand, a torch or fire placed in the pocket, or a gun fired inside it (TownLaw.gunfire).
  - A lantern is a safety lamp: it warns you as you come near and never ignites the gas.
  - Spent pockets are saved in `TownLaw.state.minesSpent`.
- **Miners.** Townsfolk tagged `villager:miner` (role "miner"). They work their face day and night and carry a shovel.
- **Law.** The underground workings, including the stores, are company ground, not town property. The head frame is
  the town's.
