# Failures

Remington's standing list (Nov 1 2026, 20:41 voice notes, 20:51 clarification): "when I ask for something, I see the
thing that was implemented, and I think it wasn't done well enough. Or maybe I asked to fix a bug, and the bug was
fixed, specifically that bug, but you should have fixed all the bugs just like it." "No half-assing things."

This is the record of how NOT to work. Entries stay here for good. When one is rebuilt properly, the entry gets a
"Rebuilt" line saying what was done and how it was checked; it is never deleted. Before calling any feature done, read
this list and ask whether the work repeats one of these.

## The lessons so far

- Build the thing he named, as it works in the world: a garage door is a door a vehicle drives through; an elevator is a
  car in a shaft that carries you between floors with call buttons. A stand-in with a different mechanism is a failure
  even when it "technically" covers the request.
- Try it the way he will: walk, drive or ride through it at his scale, in the headset's numbers, from both sides. If he
  can't get through it, it isn't done.
- Fix the family, not the instance: when a bug shows up once, find every place the same cause can bite (other blocks,
  other structures, other vehicles, other dimensions) and fix those too, with a check that covers them.
- Finish the surroundings: a feature that lives in a place (floors an elevator serves, a garage a door opens) needs that
  place furnished and worth going to.
- No copy and paste: floors, rooms and buildings that repeat one layout read as filler (the Capital city buildings'
  identical floors, Nov 1 20:20). Each should be its own.

## Entries

### 1. The garage door (P507, Nov 1)

- **Asked:** at an ammo depot's magazines, Nov 1 12:33:06: "There should be like garage doors here, 'cause that's what
  it's like in [that] depot."
- **Made:** a "Roller Shutter" block (Depots.swift): each shutter cell rolls up to a 3/16 strip at the top of its own
  cell when used.
- **Why it failed:** Nov 1 evening, -2512.8 72.0 26.2: "the garage door was not made... lazy replacement that doesn't
  even let you through was made instead", "that's not how a door's supposed to work. I can't even get through... this
  has gotta be fixed... an actual garage door." A garage door is one door across a vehicle-wide opening that opens as
  a whole and leaves the full opening clear to drive through; the shutter was cells, each its own thing, and the
  opening was not clear.
- **Rebuilt (Nov 2, PR #648):** a magazine's opening is one garage door five wide and four high. Used from outside
  or by the button inside, the whole door swings up as one body on its hinge and lies under the crown, leaving all 20
  cells of the opening clear; used again it swings back down across it. Old shutters in saved depots widen to the
  same door the first time they are used. Checked by `questcheck --garagedoor` (in the full suite): he walks in
  through it and back out, a vehicle 4.4 wide drives through it open (and can't while it's shut), the button inside shuts it.

### 2. The elevator (P503 Lift Pads, Oct 31 - Nov 1)

- **Asked:** Oct 31 16:20:47 in a citadel side tower: "there should be an elevator".
- **Made:** Lift Pads (Lift.swift): a pad in each floor; a jump on one teleports-rides to the next pad up the column,
  a crouch goes down.
- **Why it failed:** Nov 1 evening (20:17-20:2x, -310 74 -1818 and 650 105 2072): "is this supposed to be an
  elevator?... I want it to be an actual elevator", "Should also be stuff on these levels too", "Should be replacing
  the wires if there's actually gonna be functional elevators". An elevator is a car that moves up and down a shaft
  with doors and call buttons, carrying him (and whoever stands in it) smoothly between floors; and the floors it
  serves should have something on them: "Not just copy and paste for every level either like you did in the capital
  city buildings... Something creative different each floor" (20:20:11).
- **Rebuilt (Nov 2, PR #648):** a lift is a car in a shaft with doors at each landing, a floor panel in the
  car and a call button at each landing. The car moves as one body and carries whoever stands in it; the doors open
  only where it stands. His World's Lift Pad columns turn into lifts in place (no pads left), and a citadel
  side tower gets one beside its ladder. The tower's empty storeys are furnished as rooms that differ floor to floor
  (a guard post, a signals room, bunks, an armoury with ammo racks, a mess); a storey he furnished himself is left
  alone. Checked by `questcheck --elevator` (in the full suite): he walks in, picks the top floor, rides up without
  falling or leaving the car, walks out at the top, a landing button calls the car down; pad columns and his citadel
  towers convert; the rooms are there and differ.

### 3. The train (C1, P470, P508, P510; Oct 26 - Nov 1)

- **Asked:** Oct 26 18:35 and 20:14: "make big train tracks and make it so there is a train that can be boarded", "a
  large variant that would be real-life sized"; Nov 1 20:38: "The train doesn't stop. It goes on forever."
- **Made:** real-size cars drawn as models (TrainCars.swift) on one moving body per car. Only a few surfaces were
  made solid by special cases (a roof while it runs, a coach's floor): the walls, ends, seats and couplings were not
  there to touch, nobody rode it, and the engine was driven only by mounting it as a seat.
- **Why it failed:** Nov 2 08:40-08:42, -9600 85 5317 (seed 7653607216494784574): "can get in the passenger carts
  here, but... there's no passengers, and I am glitching through this section", "[the train] wasn't entirely well
  done here... I'm gonna call that a failure", "I should be able to jump on top of this section", "I can't seem to
  drive the train now", and 08:40:06 at -8365 128 5109: "Oh, look, a train. And it stops... That shouldn't be there".
  A train is cars you walk through, stand on and ride, with people aboard, an engine you drive from its cab, that
  runs on along the line. (His Nov 2 12:13: "The railway was good but there was still a 'start' to it": the 08:40:06
  note meant the line still has a starting end.)

### 4. The see-through void triangles (P404, P499, P511; Oct 22 - Nov 2)

- **Asked:** four times: Oct 22 22:17-22:23 ("lines and cracks in the ground"), Oct 30-31 (the void triangle fanning
  past the held carbine at the Slatefall), Nov 2 morning ("horrible triangles", jungle -5572 77 2812), and Nov 2 12:13:
  "Void triangles still. Add that to the failure list with context of this thing asked to be fixed 4 times now. The
  correct fix would have been a giant sweep of tests and screenshots looking and solving the underlying patterns until
  none exist."
- **Made:** one instance at a time: the fine-ground ring's border pinned onto the whole-cell vertices (#446) and called
  closed when one repro showed no sky pixel (#478); an opt-in VR sim shot of the Slatefall that did not show it on the
  host, so nothing was changed (#643); the tree feet's buttress spikes rounded (P511, 3f2bf31d).
- **Why it failed:** each fix answered the one spot he named and was checked at that spot only. Nobody looked for the
  pattern: where else the drawn ground, trunks, roots, water and shells leave a gap the sky shows through, at what
  distances, LODs, mesh borders and viewing angles. A bug he names is a family; the check is a sweep that finds every
  member (many seeds, biomes, structures, distances, the headset's view), not one screenshot.
- **Swept (Nov 3, PR #650):** `tools/voidsweep.sh` renders 564 headset-style views (the field world, the Quest's LOD
  rings, the frame cleared to magenta with no sky: `questcheck --view ... --voidcount`): his six spots each looking four
  ways, and 15 biomes on three seeds at four pitches looking three ways. It found two patterns. From high up, a ray
  going down past the loaded land and over the far ring's outer edge met nothing (a sky wedge under the horizon in 29
  views): a fog floor now lies under the far ring, drawn in fog colour, so the wedge is far haze. The other was the
  sweep's own placement (badlands views stood inside the mesa: `--up` now goes over the loaded world's top). On build
  101 all 564 views are clean. Still to check on the headset: his own spots in the Quest's stereo view, since the host
  renders one eye's frustum per side, not the device's.
- **Asked a fifth time (Nov 12):** "sky-blue triangle voids" in the grass at 3903.9 65.9 1025.2 and 3919.0 64.5 1041.4,
  "a really big one". The Nov 3 sweep could not see them: they open only where half-block ground (a dug, blasted or
  built-on chunk) meets ground drawn from whole cells, a layout a fresh `--view` never has, and under such a hole lies
  the fog floor, which the sweep counted as ground.
- **Swept again (Nov 12, PR #711):** the sweep now makes those layouts itself (`--corner --finechunks`: seven layouts
  of half-block and cells-drawn chunks round a chunk corner, each turned four ways) and counts any fog floor seen
  looking down as a hole. The old code fails 54 of 56 views. Two causes found and fixed (ledger 91, 92): a
  cells-drawn diagonal neighbour, and a border vertex just under a 16-block section line. His two spots: 5,846 and
  15,003 sky pixels before, 0 after. Plains: 26 of 28 views with a hole before, 2 after (one pixel each). NOT DONE:
  on a steep forest slope 20 of 28 views still show a hole from low side angles (28 before, a third of the pixels);
  that third cause is open and is the next work. This entry is not closed until that sweep is clean on every biome
  and both seeds.
- **Third cause (Nov 12, the PR after #711, ledger 98):** steep ground across the border left the neighbour's
  in-between vertices out; the half-block ground is now stitched along them. Forest: 20 views with a hole
  (11,341 px) to 13 (698 px); plains clean. STILL NOT DONE: 13 forest views keep a small hole. A new check reads the
  mesh itself (`--watertight`), so what is left is counted without a camera. Not closed.
- **Nov 13 (ledger 99):** three more causes (the fan took the wrong in-between cell; sections sharing a cell on a
  section line fixed it differently; a vertex on two borders lost one). Forest and plains: 0 of 56 views looking
  down with a hole. Seven more biomes on two seeds: 193 of 196 clean. STILL NOT DONE: a one-block hole on a steep
  desert bank at a section line (3 views, one seed). Not closed until those are clean too.
