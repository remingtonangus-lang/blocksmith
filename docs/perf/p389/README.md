# P389: objects are one piece, broken where hit

Polygons worlds on the headset (the detail stream on, `World.objectsOn`). The Mac keeps block mining as before.
All numbers are host numbers from `questcheck` built with the headset's compiler setting (`QUEST_OPT=-Ounchecked`),
seed 13480747113613945685, Polygons world. There is no GPU here: lavapipe draws the shots on the CPU, and the
headset-only checks are skipped.

Commands:
- census: `questcheck --field --objectcensus`
- shots and costs: `questcheck --view OUT/obj.png --seed 13480747113613945685 --at 6094,190,688 --rd 4 --field --questlod --w 480 --h 400 --fov 90 --scene objects`
  (`BS_OBJCENSUS=1` takes the ten kinds from that run's census and says whether they match `WorldObjects.kinds`)

Shots: `/mnt/project-files/p389-shots/` (one strip per object: untouched, converted to pieces before any blow,
after 3 blows, after it breaks; the single frames are in `png/`).

## Step 1: the census

Every connected group of object cells inside Stone Gulch (its box +-64), the nearest capital city and the nearest
base (`World.objectSites`), named by `WorldObjects.classify`. Trees, building parts and unnamed groups are not
counted as kinds.

| | kind | groups | cells | where |
|---|---|---|---|---|
| 1 | chest | 40 | 40 | all three |
| 2 | lantern or torch | 34 | 34 | capital lanterns and bulbs, gulch torches |
| 3 | cafe table | 32 | 64 | capital (birch fence post + white carpet) |
| 4 | sign | 23 | 24 | gulch, capital |
| 5 | parasol | 23 | 276 | capital (fence pole x3 + wool and carpet canopy) |
| 6 | lamp post | 21 | 68 | capital stone column + bulb or lantern, gulch fence + lantern |
| 7 | pumpkin or melon | 13 | 15 | all three |
| 8 | barrel | 8 | 22 | capital |
| 9 | fence post | 8 | 15 | gulch |
| 10 | workblock | 6 | 6 | furnace, jukebox, target |

Next: crate 5 (the base's ammo crates with barrels), bell 3, cauldron 3, anvil 2, stump 2, hay bale 2, dead
tree 1, fallen log 1. There were 38 groups the rules don't name (market stalls of fence and log, spawners,
lecterns, lightning rods).

These ten are `WorldObjects.kinds`. Of the backlog's examples:
- Carts, statues and wells were not found at these sites as object cells.
- Boulders in a Polygons world are field ground, not cells.
- Stumps, logs and driprock are rare here (2, 1 and 0).

Census rules that changed what counts:
- Window bars are not fence posts. They were 9 of the gulch's 17 "fence posts".
- A log column that a wall or roof meets beside or above is the building's frame. That was 20 of the gulch's 21
  "dead trees".
- A light set into a wall or ceiling (two built sides or more) is the building's. This removed the capital's
  ceiling panels and most gulch torches.
- A free-standing stone column of 1-4 blocks under a light is a lamp post. These are the capital's street lamps.
  The word "light" in the exclusion list had hidden every light panel.
- A fence with a carpet on it is a cafe table, and a fence pole under a wool canopy is a parasol. Both follow
  `CapitalCity.seating`.

## Step 2: one mesh and one hull, the same parts

An object is registered at its first blow (`WorldObjects.Registry.register`). Its parts are what the mesher
draws now:
- a cube's whole box;
- a model's boxes, with their own face textures;
- a fence's post and the rails it has towards its neighbours.

Round shapes become convex forms:
- a log is an octagon round its axis at the trunk radius;
- a pumpkin, melon or hay block is the convex hull of ShapeOrganic's soft box, from the same neighbours, cut
  along 74 directions. `ShapeOrganic.formAt` is shared, so both read the same form.

The pieces are built on the object worker, not on the frame.

What happens to cells:
- An untouched cell stays a block: the block mesher draws it, and its own boxes are its collision.
- A cell a blow has reached is drawn by the object in its section's detail stream (`WorldObjects.emit`). There:
  - the faces keep the block's texture mapping;
  - a cube keeps the mesher's corner light and occlusion;
  - faces on the cell's side are culled against solid neighbours as the mesher culls them;
  - cut faces show the inner texture, darker.
- Collision for a touched cell is one box per part, round what is left of that part. A fence keeps its tall
  collision while its top is whole.

Converted with no blow yet (shot 2 against shot 1, pixels differing by more than 8 of 255):

| | |
|---|---|
| chest, sign, lantern | 0% |
| fence post | 0.05% |
| cafe table | 0.07% |
| parasol | 0.19% |
| workblock | 0.24% |
| barrel | 1.7% |
| lamp post | 6.2% |
| pumpkin | 21.7% |

Some of these differ for known reasons:
- The lamp post's difference is mostly the grass blowing round its foot; the post itself matches.
- The pumpkin's pieces are a faceted hull. The drawn pumpkin is ribbed and smooth-shaded.
- Neither difference shows in play. Only a struck cell is drawn as pieces, and by then a chunk is gone from it.

## Step 3: a hit cuts a chunk

A blow (`Game.strikeObject`, on break held, one blow per a quarter of the cell's mining time, 0.25-0.9 s) cuts at
the exact point the ray met the pieces. Its normal is the face's.

The bite's radius depends on three things:
- the tool on that material: 0.12-0.42 blocks, from `Mining.breakSeconds`;
- the object's size: x0.35-1, so a sign or a lantern takes several blows;
- a minimum of 0.07.

The bite is `Fracture.bitePlanes`, a rough flattened ellipsoid with its seed from the cell and the cut count. On
the object worker:
- every piece in reach is clipped by the bite's planes;
- what is outside stays as convex pieces;
- what is inside is the chunk;
- crumbs under 3e-4 of a block go with the chunk;
- the support is checked again.

On the frame thread:
- the chunk flies off as debris (`DebrisField.piece`, with the box's own face textures; the largest 4 per blow,
  the rest as dust);
- the object's mesh and hull are swapped in;
- the touched sections remesh on the mesh workers.

Frame-thread cost, from two runs of the `--scene objects` scene on a quiet machine (55 blows each, over the ten
kinds). The game is the same in both runs; only the timings differ.

| | mean | worst |
|---|---|---|
| the blow (find or register the object, queue the cut) | 0.093 / 0.087 ms | 0.994 / 0.200 ms |
| the finished cut swapped in (pieces, collision, debris, drops, cells that went, a break) | 0.204 / 0.226 ms | 0.804 / 0.993 ms |
| the cut on the object worker (not the frame) | 1.04 / 1.08 ms | 5.6 / 4.3 ms |

The blow and its swap-in come on different frames. No single frame took 1 ms or more for an object in either run.

The step's budget is per hit, the blow and its swap-in together, and that is NOT met for the lamp post:

- **Lamp post, per hit:** 0.994 + 0.777 ms in the first run and 0.200 + 0.993 ms in the second, so 1.2-1.8 ms.
  Its worst blow (0.994 ms) is the first blow of the session; the second run's was 0.200 ms. Its worst swap-in is
  the hit that cut the post through: two cells went and gave their drops in that one swap-in, at about 0.3 ms a
  cell (`breakBlock` and the drop into the pack).
- **Every other kind, per hit:** blow plus swap-in under 0.85 ms in both runs.
- **Next step:** let the cells that go leave one per frame. That evens out the frames; the hit's total stays the
  same.

One cost is not the objects'. The session's first block break of any kind costs 74-112 ms: it builds caches every
break reads (towns, vaults, mines round it). The scene times it apart on a plank before the objects.

Cells that go no longer remesh on the frame. Before, a cell an object lost went through `breakBlock`, whose
synchronous remesh was 6-230 ms. Now `breakBlock(quiet:)` leaves it to the mesh workers, which redraw it a frame
or two later.

## Step 4: enough gone, it falls or breaks

What is held:
- Pieces are held through touching pieces from a support: a solid face the object rests on or hangs from, or the
  drawn ground just under its foot.
- What loses its hold falls as debris. A lamp's head falls when its post is cut through.
- An object nothing was found holding (a torch drawn clear of its wall) never falls.

Drops scale with the volume removed, a cell at a time:
- a cell that has lost half its volume gives its drop;
- a cell with nothing left becomes air.

The object breaks when one of these happens:
- under 40% of its volume is left;
- it has more than 400 pieces;
- every cell is gone.

When it breaks:
- the rest comes down as debris (the largest 24 pieces; the rest as dust);
- every cell gives what it hasn't given yet;
- a crate's loot spills.

Blows to break, from the run, with an iron tool of the material's kind:

| kind | blows to break |
|---|---|
| fence post | 3 |
| lamp post | 4 |
| sign | 5 |
| barrel (3 cells) | 6 |
| chest | 10 |
| lantern | 6 |
| pumpkin | 6 |
| workblock | 7 |
| cafe table | 6 |
| parasol | 2 (pole cut through) |

## Step 5: save

`objects.json` in the world folder holds every object struck and not broken: its cells, blocks, parts and the list
of its cuts. On load, objects are rebuilt from their cuts on the worker once their chunks are in; nothing flies.

The scene checks the round trip on the first object still standing after 3 blows: it is written, read back and
rebuilt. Result: OK (the lamp post: 3 cuts, 13 pieces and 0.0785 of a block, read back as 13 pieces and 0.0785).

A save without `objects.json` (every old save) loads with no objects, so every cell is whole.

## Step 6: shots

`/mnt/project-files/p389-shots/`: one strip for each of the ten kinds.

## What is not done

- Field worlds don't seat a gourd's pieces: the mesher's settle reads the smooth vertex grid, which field worlds
  don't have.
- A parasol's carpet ring mines as blocks when struck directly; its pole and wool middle strike as the parasol.
- Not checked on the headset; host numbers only.
