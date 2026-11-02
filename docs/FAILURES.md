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
