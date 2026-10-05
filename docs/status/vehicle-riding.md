# Vehicle riding and crews (session B, branch claude/bs-vehicle-riding)

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

## Open / for other sessions

- Capital frigate (integration session's file): the deckhouse ladder at (-6, 15..20, 66) ends a block short of the
  bridge deck (the deck is z 53-64, y 21): nobody can climb onto the bridge. Extending the bridge deck to z 66 (or the
  ladder) fixes it.

## State

- 2026-10-04: riding, boarding, crews and disabled vehicles done; `--ridecheck` passes all 10 scenes on CI (fast lane,
  run of 6f459b3; ~25 s of real time for ~20 min of game time). Merged into claude/blocksmith-playtest.
- Also fixed on the way: crawlers rest on the real ground where it is loaded (the generator's height misses carved
  valleys), riders of a long hull stay simulated at its far end (frigate bow crew were stashed with their chunk).
- Next (same session): destruction physics and persistent wrecks (branch claude/bs-destruction, notes to follow here).
