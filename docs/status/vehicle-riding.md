# Vehicle riding, crews, destruction physics and wrecks (session B)

Handoff notes for riding moving capital vehicles (Ironback Crawler, Capital frigate, Stormwarden frigate), their crews,
and disabled vehicles. Status: see "State" at the bottom.

## How riding works now

- **Frame.** A rider moves and collides in the ship's own frame (`World.frame`, exact ship blocks) and is carried by
  `ShipManager.update` (position and yaw from the ship's previous to current pose). Unchanged in principle; what changed:
- **Velocity stays in the deck's frame** (`ShipManager.riderShip/riderVel/riderOut/riderAt`, ShipPlay.shipPlayerUpdate).
  The player's deck-relative velocity is kept tick to tick; only outside pushes (knockback, blasts: `p.vel` differing
  from what was handed out last tick) change it. Before, the world velocity was converted back each tick, so every
  change in the deck's speed or turn rate leaked in as a shove (sliding when a crawler sped up or turned). A tick
  without a ship update (turret, helm) starts afresh.
- **Who is aboard** (VehicleRiding.swift). Boarding needs a hold on the ship: a ship block under the feet
  (`holdsRider`, any corner of the footprint, turrets count), a ship ladder the body overlaps (`atShipLadder`), or the
  hull's enclosed air (`insideHull`). A rider leaves when it stands on the world's ground (not a ship block, not on a
  ladder), stepping up onto that ground if the frame's per-cell sampling had it up to a block low. Standing beside or
  under a moving hull no longer drags you along. Mobs use the same rule (ShipPhysics rider list) and their velocity is
  deck-relative while aboard: the deck's own is added back when they leave and taken out when they board.
- **Capital hulls are their own space above their floor** (Ship.frameBlock): for kinematic ships, world blocks inside
  the hull's columns above its lowest block are ignored, so terrain and trees a crawler drives through or a frigate
  settles into never pop riders up or block them.
- **World-space ship boxes**: partial blocks (stairs, slabs) are each of their boxes turned with the ship (a stair was a
  full-height box: a ramp of stairs couldn't be walked up from the ground); ladders are no obstacle (climbers board at
  them).
- **Fall height** (`airPeak`) and the teleport check move with the deck when carried (a settling frigate carries its
  riders down without fall damage; falls inside the hull still count).

## Vehicles

- **Ironback Crawler**: grid 84 long (the hull ends at z 76). Ladders up both flanks at z 29 from the ground to the
  chassis-roof walkway, a stair and a hatch from there into the command deck (x ±8, z 30). Rear ramp (`Capital.crawlerRamp`):
  steel stairs from the bay floor to the ground behind (z 74-83), folded into a door plate while it drives; it lowers
  when the AI wants under 1.6 b/s, when troops are on their way out, or when disabled, and rises only once nobody stands
  on it (or after 8 s). While it is down the crawler creeps (1.5 b/s). Its ground-following is smoothed (height, pitch
  and roll eased; turn rate eased in) so riders feel no jolts. Disabled (half its wheels or its engines): it keeps
  following the ground while it grinds to a stop (1.4 b/s lost per second), sagging toward the wheels it lost, smoke at
  the wheels; no blast, no despawn.
- **Frigates** (Capital and Stormwarden): engines out → `crashLand`: a little way on, sinking up to 7 b/s, flared from
  24 blocks over the ground to about 2.6 + clearance x 0.18 b/s, pitched to the ground under bow and stern, touchdown
  with three power-3 blasts under the keel (deck riders are out of their reach); riders take damage only above 3.5 b/s
  at touchdown ((v - 3.5) x 2). It stays where it lands.
- **Crew** (`Mob.crewPost/crewRoute/crewFree`, `Mob.crewStep`): each soldier holds its post in the hull's frame while the
  vehicle runs (the soldier AI still turns and fires; strolling, flanking, cover and chasing are overridden, no path
  finding on a hull). Crawler bay troops sent out walk a route round the engine room, out of the rear door and down the
  ramp (no teleport). A disabled vehicle releases its crew (`crewFree`): they fight as soldiers, still aboard, never
  stepping off a ledge (an edge guard in the deck branch of Mob.update).

## Checks: `Blocksmith --ridecheck [--scenes ...] [--scale F] [--seed N] [--out DIR]` (RideCheck.swift)

Bots ride through the real Game.tick (Agent API). Scenes: crawler, rough, frigate, warfrigate (stand, then laps with
sprints and jumps on a deck while the vehicle drives S-turns), board (crawler ladder, roof, hatch, back down, rear ramp up
and down while it moves), frigateboard (fly down onto a cruising frigate, hangar, deckhouse, side doors and the unrailed
side decks, take off), crew (crewed crawler: posts held while driving; half its wheels shot away: grinds to a stop, crew
aboard fighting enemy soldiers), troops (ramp lowers, bay troops walk out), frigatecrew (posts held; engines out: crash
landing, crew aboard), frigatecrash (a survival bot rides a frigate down). Oracles: never off/below the deck, never in a
solid (exact, in the frame), standing drift, deck-relative velocity spikes and shoves, bouncing, world-velocity jumps
(skipping the ticks round a jump or landing), laps, crew at posts, smooth stops, no despawn. Report snaps/ridecheck.md.
In CI: snap.sh tours shard (gating). The fast lane runs any harness command given as `[fast: ARGS]` in the head commit
message (focus.log on ci-fast-<branch>).

## Destruction physics (Future ideas #7, branch claude/bs-destruction)

- **Materials** (BlockMaterial.swift, public API for other sessions): `BlockMaterial.kind(id)` (stone, brick, wood, metal,
  glass, earth, plant, cloth, ice, other, none), `.strength(id)` (longest unsupported reach in blocks: stone 5, brick 6,
  wood 6, metal 14, glass 1, earth 1), `.mass(id)` (tonnes per block, the ship physics' table), `.load(id)` (blocks of
  weight one block bears at a narrowed section: stone 30, brick 40, wood 20, metal 150), `.anchors(id)` (terrain, trees
  and growths, and generated terrain outside the helm's natural list: desert sandstone, basalt, blackstone, icebergs,
  geodes, glowstone ceilings, fungus crowns, raw ore veins: hold up what is built on them, never fall). Tuned in `BlockMaterial.byKind`.
- **Support analysis** (Destruction.swift, `Collapse.analyze`): after a blast (Explosion.explode queues its holes; one
  check per frame for all of that frame's blasts), a mined built block (Game.breakBlock) or a block a falling piece
  smashed: flood fill through built blocks from
  the cells next to the holes, capped at 6000 cells (the edge of a search that hits the cap is taken as held, so a huge
  building only fails near the damage). No ground contact: the piece falls. Reach (0-1 BFS: resting on the block below
  is free, sideways or hanging costs 1) beyond the material's strength: those blocks and whatever only hung on them
  fall. A layer the damage narrowed by at least a quarter of what carried it (a tower's base) fails, inside a search
  that saw the whole structure, when the weight above outweighs its bearing or its centre
  of mass is past the layer's edge or far off the middle of what is left: everything above tips over toward the gap.
- **Debris** (Debris.swift): falling parts become free-moving ships (`Ship.debris`) under the ordinary ship physics
  (gravity, terrain contacts; speed capped at 20 b/s so big pieces can't tunnel through the ground), smash weak blocks
  they hit hard (glass, plants, wood, cloth, ice; earth when very hard), hurt bodies they run into (by relative speed),
  and once at rest (1.2 s) are laid back into the world as ordinary blocks (`bake`: each block to the cell its centre is
  in plus the cells whose centre falls inside a block, so turned shells stay closed; never into the player or a mob; tipped
  bodies lose block facings). At most 32 live bodies (the oldest is laid down early); pieces under 3 blocks just break.
  Debris over unloaded ground waits rather than being laid down mid-air. Debris isn't saved (transient: under 40 s).
- **Capital hulls cut through** (`splitHull`): a blast on a kinematic hull asks for a full connectivity check half a second
  later; every part not joined to the part with the helm comes away as a falling body; a part left without its helm goes
  down (crash-lands) too. Small parts (< 20 blocks) just burst.

## Persistent wrecks (Future ideas #3)

- A downed crawler or frigate (8 s after it came to rest), a shot-down dropship (3 s after it hit the ground, which it
  no longer vanishes in a fireball) and a big capital section are laid into the world as blocks (`makeWreck`): saved with
  the chunks, salvage crates set in sheltered floor spots of the hull (loot table `wreck_salvage`: iron, copper, redstone,
  gold nuggets, gunpowder, rounds, rusted plating, a rare diamond), its own chests kept; its dark hull is where mobs
  settle. A record per wreck (wrecks.json beside ships.json) keeps its box and when it fell; while the player is within
  200 blocks the overgrowth catches up with its age (3 steps a day, full at 63 steps = three weeks): exposed plates turn
  to rusted plating, moss gathers on top, vines hang down the sides, grass grows tall round it. A wrecked capital's region
  stays used, so it doesn't come back.

## Checks: `Blocksmith --collapsecheck [--scenes bridge,mine,tower,stands,desert,frigate,wreck,dropship]` (CollapseCheck.swift)

Bridge on three piers with the middle pier blasted (and mined out block by block); a 60-high lopsided tower that loses
one mined block and a wall chunk and must stand; blasts in a real desert that must bring no terrain down; a 30-high tower blasted at its base on one side; a Capital frigate
cut through amidships by a ring of blasts; a crawler disabled into a wreck and aged three weeks; a dropship shot down.
Oracles: the scene stands before; the right part falls as a moving body; debris under the cap and all laid back; no
floating leftovers (the support analysis over the whole scene region); nothing inside the player; tick time p95 under
16 ms; frigate halves split, fall and become wrecks; wreck blocks, salvage, shelter, rust/moss/vine counts, record round
trip. Shots: `--collapse NAME --at SECONDS` in the snapshot harness (snap.sh tours: collapse_*.png). Benchmark scene
`collapse` (bridge and tower together: blast ms, tick p50/p95/max, bodies, analysis ms).

## Open / for other sessions

- Capital frigate (integration session's file): the deckhouse ladder at (-6, 15..20, 66) ends a block short of the
  bridge deck (the deck is z 53-64, y 21): nobody can climb onto the bridge. Extending the bridge deck to z 66 (or the
  ladder) fixes it.

## State

- 2026-10-04: riding, boarding, crews and disabled vehicles done; `--ridecheck` passes all 10 scenes on CI (fast lane,
  run of 6f459b3; ~25 s of real time for ~20 min of game time). Merged into claude/blocksmith-playtest.
- Also fixed on the way: crawlers rest on the real ground where it is loaded (the generator's height misses carved
  valleys), riders of a long hull stay simulated at its far end (frigate bow crew were stashed with their chunk).
- 2026-10-05: riding merged into claude/blocksmith-playtest at c181086 (rebased on 639eb75; ride check PASS, 10 scenes).
  Fixed on the way: troops leaving by the crawler's ramp (a mob without a deck boards by the player's holds; a hull
  shoving mobs tests the overlap exactly in its frame and lifts at most a stair step; riders carried into the ground
  beside the hull step up).
- 2026-10-05: destruction and wrecks: `--collapsecheck` PASS on e40799a (9 scenes: bridge, mine, tower, stands,
  massive, desert, frigate, wreck, dropship). Support search 1.4 ms for a 60-high tower, 3.4 ms for a capped 6000-cell
  search; laying a 10k-block frigate hull down 37 ms (was 70). Full heavy run next, then the merge.
- Open: a Capital base has 34 blocks the support analysis finds unsupported untouched (capital stone and trim, light
  panels; the main tower's landing pad reaches ~22 blocks off the terrace, capital stone spans 14, and its braces hang
  from the pad rather than running to the tower wall). `--structcheck` unstable class measures it per structure.
