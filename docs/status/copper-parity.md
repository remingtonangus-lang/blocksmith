# Copper circuits: parity checklist (Copper = our redstone)

Goal (Remington, playtest 2026-10-09 PM, item 5): a player coming from the reference game builds the same circuits
the same way. Reference = Java Edition semantics (what most players learned); Bedrock differences noted where relevant.
Times are game ticks (20/s); one "circuit tick" = 2 game ticks.

Code: Sources/Circuit.swift (engine), GameCircuit.swift (use/dispense/hopper/plates), BlocksCircuit.swift (states),
Rails.swift + MinecartVariants.swift (carts), Crafter.swift, Projectile.swift (targets, arrows on buttons),
Recipes.swift. Save keys stay `redstone_*`; player-facing names are Copper Wire, Copper Signal Torch, Copper
Repeater, Copper Comparator, Copper Lamp, Copper Battery.

Test: `build/Blocksmith.app/Contents/MacOS/Blocksmith --snapshot snaps/coppertest.png --seed 12345 --find plains
--time 0.3 --up 6 --rd 5 --coppertest` (Sources/CopperTests.swift). It builds every circuit on pads high above the
terrain and steps the real engine (`World.redstone.tick()` + `detectorCheck`, the circuit half of `Game.gameTick`;
carts through `Mob.updateMinecart`). One test per row, printed as `coppertest: PASS|FAIL|MISSING|XPASS <id> ...`.
Rows marked missing run as expected failures: MISSING does not fail the run, XPASS (a missing row that now works)
does, so the table cannot go stale. Exit status is nonzero on any FAIL or XPASS. CI: snap.sh checks shard.

Columns: **Exists** = the block/behaviour is in the game; **Correct** = matches the reference (test passes);
**Test** = the `--coppertest` id.

## Totals

(filled in from the last `--coppertest` run, see bottom)

## Wire (Copper Wire)

| ID | Behaviour (reference) | Exists | Correct | Test |
|---|---|---|---|---|
| W1 | Signal 15 at the source, -1 per wire, 0 after 15 wires | yes | yes | wire.decay |
| W2 | A lone wire is a cross: powers all four sides (Java 1.16+ and Bedrock) | yes | yes | wire.cross |
| W3 | Right-click toggles a lone wire between cross and dot (dot powers nothing beside it) | no | missing | wire.dot |
| W4 | A straight line powers the block it points into, not blocks at its sides | yes | yes | wire.points |
| W5 | Wire bends toward components (repeater, torch, lever...) and stops pointing where it no longer runs | yes | yes | wire.redirect |
| W6 | Wire climbs up the side of a block to wire on top | yes | yes | wire.climb |
| W7 | Wire runs down off a block to wire below | yes | yes | wire.descend |
| W8 | A solid block above the lower wire cuts the climb | yes | yes | wire.cut |
| W9 | Wire weakly powers the block it points into (lamp beside it lights, wire beyond stays off) | yes | yes | wire.weak |
| W10 | Wire powers the block it sits on (lamp below lights) | yes | yes | wire.below |
| W11 | Transparent blocks (glass) do not conduct | yes | yes | wire.glass |
| W12 | Breaking a powered line drops it to 0 downstream at once | yes | yes | wire.break |

## Power rules

| ID | Behaviour | Exists | Correct | Test |
|---|---|---|---|---|
| P1 | Strong power (repeater into a block) powers wire on the block's other sides | yes | yes | power.strong |
| P2 | Weak power (wire into a block) drives lamps/repeaters but not wire | yes | yes | power.weak |
| P3 | Copper Battery powers adjacent wire and components, not through a solid block | yes | yes | power.battery |
| P4 | Lever strongly powers the block it is mounted on | yes | yes | power.lever |
| P5 | Component blocks (lamp, note block, dispenser, dropper) also conduct like stone | no | missing | power.components |

## Signal Torch

| ID | Behaviour | Exists | Correct | Test |
|---|---|---|---|---|
| T1 | Turns off when the block it is on is powered (inverter) | yes | yes | torch.invert |
| T2 | 1 circuit tick (2 game ticks) delay | yes | yes | torch.delay |
| T3 | Strongly powers the block above it | yes | yes | torch.above |
| T4 | Powers wire/lamps beside it, not solid blocks beside it | yes | yes | torch.side |
| T5 | Wall torch inverts the wall block | yes | yes | torch.wall |
| T6 | Burnout: 8 turn-offs in 60 ticks leave it off, relights later | yes | yes | torch.burnout |

## Repeater

| ID | Behaviour | Exists | Correct | Test |
|---|---|---|---|---|
| R1 | Delay 1-4 circuit ticks (2/4/6/8 game ticks), cycled by right-click | yes | yes | repeater.delay |
| R2 | Refreshes any input level to 15 | yes | yes | repeater.refresh |
| R3 | One way: power at the front does not go back | yes | yes | repeater.oneway |
| R4 | A powered repeater/comparator into its side locks it | yes | yes | repeater.lock |
| R5 | Short pulses are stretched to the delay | yes | yes | repeater.extend |
| R6 | Wire at its side does not feed it | yes | yes | repeater.side |

## Comparator

| ID | Behaviour | Exists | Correct | Test |
|---|---|---|---|---|
| C1 | Compare mode: rear if rear >= side, else 0 | yes | yes | comparator.compare |
| C2 | Subtract mode: rear - side | yes | yes | comparator.subtract |
| C3 | Reads container fullness: floor(1 + fill/slots * 14) | yes | yes | comparator.container |
| C4 | Reads a container through one solid block | yes | yes | comparator.through |
| C5 | Reads composter, cake, end portal frame, respawn anchor | yes | yes | comparator.special |
| C6 | Updates when container contents change (any cause) | yes | ? | comparator.update |
| C7 | 1 circuit tick delay | yes | yes | comparator.delay |
| C8 | Reads item frame rotation (1-8) | no | missing | comparator.frame |
| C9 | Reads lectern page / jukebox disc | no | missing | comparator.lectern |

## Observer

| ID | Behaviour | Exists | Correct | Test |
|---|---|---|---|---|
| O1 | A change in front gives a 1 circuit tick (2 game tick) pulse out of the back, 2 ticks later | yes | yes | observer.pulse |
| O2 | Output strongly powers the block behind | yes | yes | observer.strong |
| O3 | Sees state changes too (a lamp lighting, wire level) | yes | yes | observer.state |
| O4 | Two observers facing each other make a clock | yes | yes | observer.clock |

## Piston / Sticky Piston

| ID | Behaviour | Exists | Correct | Test |
|---|---|---|---|---|
| PI1 | Pushes a block one step when powered, retracts when not | yes | yes | piston.push |
| PI2 | Push limit 12 blocks (13 fails) | yes | yes | piston.limit |
| PI3 | Immovable: obsidian, bedrock, block entities (chest), extended pistons | yes | yes | piston.immovable |
| PI4 | Fragile blocks in the way (torches, plants) break and drop | yes | yes | piston.fragile |
| PI5 | Sticky piston pulls the block back | yes | yes | piston.sticky |
| PI6 | Sticky piston leaves immovable blocks | yes | yes | piston.stickyimmovable |
| PI7 | Slime drags its neighbours | yes | yes | piston.slime |
| PI8 | Honey and slime do not stick to each other | yes | yes | piston.honey |
| PI9 | Not powered through its face | yes | yes | piston.face |
| PI10 | Quasi-connectivity: power at the space above counts | yes | yes | piston.qc |
| PI11 | BUD: a QC-powered piston waits for a block update | yes | yes | piston.bud |
| PI12 | Entities in moved blocks ride along | yes | yes | piston.entities |

## Hopper

| ID | Behaviour | Exists | Correct | Test |
|---|---|---|---|---|
| H1 | One item per 8 ticks (2.5 items/s) | yes | yes | hopper.rate |
| H2 | Pushes into the container it faces | yes | yes | hopper.push |
| H3 | Pulls from a container above | yes | yes | hopper.pull |
| H4 | Picks up item entities above | yes | yes | hopper.items |
| H5 | Locked while powered | yes | yes | hopper.lock |
| H6 | Furnace faces: top -> input, side -> fuel; pulls output from below | yes | yes | hopper.furnace |
| H7 | Hopper chains pass items along | yes | yes | hopper.chain |

## Dispenser / Dropper

| ID | Behaviour | Exists | Correct | Test |
|---|---|---|---|---|
| D1 | Fires once per rising edge, 2 circuit ticks (4 game ticks) later | yes | yes | dispenser.edge |
| D2 | Quasi-connectivity (power at the space above) | yes | yes | dispenser.qc |
| D3 | Dropper drops an item entity | yes | yes | dropper.drop |
| D4 | Dropper inserts into a container in front | yes | yes | dropper.insert |
| D5 | Dispenser shoots arrows | yes | yes | dispenser.arrow |
| D6 | Water/lava bucket placed, empty bucket fills | yes | yes | dispenser.bucket |
| D7 | Primes TNT | yes | yes | dispenser.tnt |
| D8 | Bone meal grows crops | yes | yes | dispenser.bonemeal |
| D9 | Fire charge shoots a fireball | yes | yes | dispenser.firecharge |
| D10 | Equips armour on a player in front | yes | yes | dispenser.armor |
| D11 | Throws snowballs/eggs/splash potions | no | missing | dispenser.throwables |
| D12 | Places shulker boxes, minecarts, boats; spawn eggs; shears sheep; fills bottles | no | missing | dispenser.place |

## Switches and plates

| ID | Behaviour | Exists | Correct | Test |
|---|---|---|---|---|
| S1 | Lever toggles 15 on/off | yes | yes | lever.toggle |
| S2 | Stone button: 10 circuit ticks (20 game ticks) | yes | yes | button.stone |
| S3 | Wooden button: 15 circuit ticks (30 game ticks) | yes | yes | button.wood |
| S4 | Arrows press wooden buttons | no | missing | button.arrow |
| S5 | Wooden plate: any entity incl. items | yes | yes | plate.wood |
| S6 | Stone plate: players and mobs only (items ignored) | yes | yes | plate.stone |
| S7 | Light weighted plate: min(15, entities) | yes | yes | plate.light |
| S8 | Heavy weighted plate: ceil(entities / 10) | yes | yes | plate.heavy |
| S9 | Plates release 20 ticks (weighted 10) after the last press | yes | yes | plate.release |
| S10 | Tripwire: two hooks + string, anything on the string powers both hooks | yes | yes | tripwire.trip |
| S11 | A single hook with string is not armed | yes | yes | tripwire.unarmed |

## Sensors and other sources

| ID | Behaviour | Exists | Correct | Test |
|---|---|---|---|---|
| X1 | Daylight Detector: signal by sky light and sun height | yes | yes | daylight.day |
| X2 | Inverted mode (right-click) | yes | yes | daylight.inverted |
| X3 | Target: 1-15 by accuracy, resets after 8 ticks (arrows) | yes | yes | target.hit |
| X4 | Trapped chest: viewers -> power, strong into the block below | yes | yes | trapped.chest |
| X5 | Murk Sensor (sculk-equivalent): vibration within 8 blocks, signal by distance, 30 ticks | yes | yes | murk.sensor |
| X6 | Lectern: pulse on page turn | no | missing | lectern.pulse |

## Outputs

| ID | Behaviour | Exists | Correct | Test |
|---|---|---|---|---|
| L1 | Copper Lamp: on at once, off 2 circuit ticks after power goes | yes | yes | lamp.timing |
| N1 | Note block: 25 pitches cycled by right-click | yes | yes | note.pitch |
| N2 | Instrument by the block below (16 instruments) | yes | yes | note.instrument |
| N3 | Silent with a block above | yes | yes | note.blocked |
| N4 | Plays once per rising edge | yes | yes | note.edge |
| G1 | Iron door opens while powered, closes after | yes | yes | door.iron |
| G2 | Trapdoors and fence gates follow power | yes | yes | door.trapgate |
| G3 | TNT is primed by power | yes | yes | tnt.power |
| G4 | Bell rings on a rising edge | yes | yes | bell.power |
| G5 | Copper bulb toggles on each rising edge | yes | yes | bulb.toggle |
| G6 | Crafter crafts one item per pulse | yes | yes | crafter.pulse |

## Rails

| ID | Behaviour | Exists | Correct | Test |
|---|---|---|---|---|
| RL1 | Powered rail: power runs 8 rails along the line (9 total) | yes | yes | rail.propagate |
| RL2 | Powered rail boosts a moving cart | yes | yes | rail.boost |
| RL3 | Unpowered powered rail brakes a cart | yes | yes | rail.brake |
| RL4 | Detector rail powers while a cart is on it | yes | yes | rail.detector |
| RL5 | Comparator reads a detector rail's cart contents | no | missing | rail.detectorcomparator |
| RL6 | Activator rail takes power like a powered rail | yes | yes | rail.activator |

## Crafting and names

| ID | Behaviour | Exists | Correct | Test |
|---|---|---|---|---|
| K1 | Every component has its reference recipe with Copper Wire in place of dust | yes | yes | recipes.all |
| K2 | No "Redstone" in player-facing names | yes | yes | names.original |

## Not planned

- 0-tick pistons, block dropping by 1-tick sticky pulses, update order quirks: skipped (task brief).
- Piston motion is instant (the reference keeps moved blocks as "moving" for 2 ticks): circuits built for the
  timing work, piston-tick-perfect contraptions may not.
