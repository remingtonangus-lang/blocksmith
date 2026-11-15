# ElevenLabs takes, Nov 15 (78 sounds)

Remington's Nov 15 sound list (the doc at https://claude.ai/artifact/Wc69UinP5RUjM8SpD1FQ3b), generated as ElevenLabs
takes (Drive: Sunderfall/sounds-elevenlabs-2026-11-15, 312 MP3s after the regeneration round). One take per sound is
committed, as a trimmed mono 16-bit WAV in Resources/Sounds/real named by Snd.name (tools/elevenlabs_nov15.py; the
packing for the APK is tools/sfxpack.py, loading is RealSounds.swift). The other takes and the MP3s are not committed.

How a take was chosen (tools/elevenlabs_nov15.py --measure gives the numbers below):
- dropped: clipped samples, more than 150 ms of silence before the sound starts (40 dB under its peak), or a length
  far off the one asked;
- of the rest, a loop takes the smallest join step (the jump in level and spectrum, dB, where its end meets its start);
  a one-shot the cleanest onset and the length nearest the ask;
- "waived": every take started late (the model adds a lead-in; the coordinator's regeneration round gave no better
  one), so the best was taken and trimmed on import to 10 ms before its onset.

How it was cut: one-shots trimmed 10 ms before the onset and 60 ms after the end (2 ms fade in, 25 ms out); loops kept
whole; levelled to a neighbour (the old take of the same slot where there was one, else a sound of the same kind) and
peaks held at -1 dBFS. The game levels every recording again on load (RealSounds.normalise, to the synth stand-in's
loudness). Slots follow elevenlabs_wire.py: a loop replaces the old loop; a one-shot takes the base slot and the old take
moves to the next free `_k` slot, so nothing that played a recording before lost it.

Host check: `questcheck --nov15sounds` (Sources/RecordedNov15Check.swift, also in the full suite): every entry with a
usable take resolves to a recording the game plays, and the two new uses (a well's bucket, a desk's drawer) play theirs.
Switches: BS_OLDNOV15SOUNDS=1 plays the sounds from before (the watcher in Sources/RecordedAudio.swift stays quiet);
BS_OLDWELLREACH=1 keeps the bucket at 5 blocks; BS_OLDDESKDRAWER=1 makes a desk only a block again.

Columns: take = the ElevenLabs take number; length = seconds / asked; peak and LUFS of the take as delivered; head = ms
before the sound starts; join = a loop's join step (dB); slots = the Snd names it plays as; event = where the game plays it.

| # | Sound | Take | Length (s) | Peak dBFS | LUFS | Head ms | Join | Slots | Event |
|---|---|---|---|---|---|---|---|---|---|
| 01 | Train running | 3 | 8.00 / 8 | -22.6 | -34.5 | 0 | 0.6 | trainCoachLoop | aboard a moving train (RecordedAudio trainSounds) |
| 02 | Train running, outside | 1 | 8.00 / 8 | -21.9 | -40.4 | 0 | 0.9 | trainPassLoop | the nearest moving train within 96 blocks, not aboard |
| 03 | Train idling at a station | 4 | 6.00 / 6 | -22.5 | -38.6 | 0 | 0.9 | trainIdleLoop | a stopped train within 40 blocks |
| 04 | Train brakes | 4 | 4.00 / 4 | -0.3 | -12.2 | 0 | - | trainBrakes | 3 s before a timetable stop, or the cab brake at speed |
| 05 | Train pulling away | 3 | 5.00 / 5 | -12.7 | -30.9 | 0 | - | trainDepart | leaving a stop after 3 s or more |
| 06 | Coupler clunk | 2 | 1.48 / 1.5 | -3.8 | -20.1 | 25 | - | trainCoupler | arriving at a stop |
| 07 | Train whistle, long | 1 | 3.00 / 3 | -5.0 | -14.0 | 0 | - | trainWhistle | Trains.whistle (long) |
| 08 | Train whistle, two short | 3 | 2.00 / 2 | -6.8 | -14.4 | 0 | - | trainWhistleShort | Trains.whistle short: leaving a stop |
| 09 | Station bell | 1 | 3.00 / 3 | -9.1 | -22.1 | 0 | - | stationBell | arriving at a station stop |
| 10 | Coach door | 6 | 2.00 / 2 | -2.1 | -21.8 | 175 | - | coachDoor | boarding a coach (Trains); waived: starts late, trimmed on import |
| 11 | Tree cracking | 1 | 2.48 / 2.5 | -3.5 | -24.0 | 264 | - | treeCrack | a felled tree of 24+ blocks starts to fall (Felling.falls); waived: starts late, trimmed on import |
| 12 | Tree hitting the ground | 3 | 3.00 / 3 | -2.6 | -31.7 | 0 | - | treeLand | a felled tree lands |
| 13 | Small tree falling | 4 | 2.00 / 2 | -16.1 | -33.8 | 419 | - | treeFallSmall | a felled tree under 24 blocks starts to fall; waived: starts late, trimmed on import |
| 14 | Tree landing in snow | 4 | 2.48 / 2.5 | -5.6 | -22.3 | 474 | - | treeLandSnow | a felled tree lands on snow; waived: starts late, trimmed on import |
| 15 | Log rolling to rest | 2 | 2.00 / 2 | -2.8 | -27.2 | 0 | - | logRoll | 0.6 s after a felled tree lands |
| 16 | Elevator running | 4 | 6.00 / 6 | -28.6 | -43.8 | 0 | 1.2 | elevatorLoop | a lift car moving (Elevators phase 3) |
| 17 | Elevator arriving | 3 | 2.00 / 2 | -23.3 | -37.9 | 30 | - | elevatorArrive | a lift car arrives (Elevators) |
| 18 | Elevator doors | 4 | 2.48 / 2.5 | -5.2 | -20.0 | 0 | - | elevatorDoors | lift doors open and close (Elevators) |
| 19 | Garage door | 2 | 4.00 / 4 | -15.6 | -33.4 | 0 | - | garageDoor | a garage door starts (GarageDoors.start) |
| 20 | Radar sweep | 2 | 4.00 / 4 | -39.9 | -49.1 | 0 | 0.2 | radarLoop | while the radar shows |
| 21 | Radar contact | 4 | 1.00 / 1 | -8.5 | -17.7 | 0 | - | radarContact | a new contact on the radar |
| 22 | Radar warning | 3 | 2.00 / 2 | -0.4 | -7.5 | 5 | - | radarWarning | a new vessel contact on the radar (1.5 s apart) |
| 23 | Crawler engine | 1 | 8.00 / 8 | -14.6 | -27.4 | 0 | 0.1 | crawlerLoop | the crawler's engine (VehicleAudio) |
| 24 | Crawler stopping | 3 | 4.00 / 4 | -13.2 | -25.8 | 0 | - | crawlerStop | the crawler stops |
| 25 | Siege carriage pushing through trees | 7 | 4.00 / 4 | -1.8 | -22.4 | 25 | - | carriageTrees | a capital vehicle crushes a tree (crawlerCrush, 1 per 1.2 s) |
| 26 | Vehicle hatch | 1 | 1.48 / 1.5 | -14.0 | -31.5 | 70 | - | vehicleHatch | taking a tank's helm (ShipPlay.takeHelm) |
| 27 | Tank machine gun | 1 | 6.00 / 6 | -0.1 | -10.9 | 0 | 1.6 | tankMGLoop | the Ash tank's coax gun firing (rounds within 0.2 s) |
| 28 | Tank machine gun, last rounds | 1 | 1.48 / 1.5 | -1.3 | -11.8 | 0 | - | tankMGTail | the coax burst ends |
| 29 | Shell casings on steel | 1 | 2.00 / 2 | -4.8 | -20.4 | 5 | - | casingsSteel | the coax burst ends (casings) |
| 30 | Parachute opening | 1 | 2.48 / 2.5 | -8.0 | -23.5 | 459 | - | chuteOpen | a parachute opens (Parachute.deploy); waived: starts late, trimmed on import |
| 31 | Parachute descending | 2 | 6.00 / 6 | -19.8 | -42.2 | 10 | 0.2 | chuteLoop | while under a parachute |
| 32 | Parachute landing | 4 | 2.00 / 2 | -0.5 | -23.6 | 0 | - | chuteLand | landing under a parachute |
| 33 | Wall collapsing | 6 | 4.00 / 4 | -0.5 | -15.6 | 95 | - | wallCollapse | a falling structure of 8+ blocks that is not a tree (Felling.falls) |
| 34 | Concrete breaking | 4 | 2.00 / 2 | -1.3 | -19.1 | 0 | - | concreteBreak | breaking concrete (audioBreakSound) |
| 35 | Bullet into ice | 3 | 1.48 / 1.5 | -1.0 | -22.0 | 115 | - | bulletIce | a bullet hitting ice (Ballistics) |
| 36 | Bullet into a steel hull | 1 | 1.48 / 1.5 | -1.0 | -19.3 | 0 | - | bullet_impact_metal | a bullet hitting metal (Ballistics, old take to _1) |
| 37 | Bolt rifle reload | 2 | 2.48 / 2.5 | -9.6 | -29.2 | 479 | - | gun_reload_16 | the bolt rifle's reload; waived: starts late, trimmed on import |
| 38 | Pistol reload | none | - | - | - | - | - | - | not wired: every take a lone 70-90 ms click after 0.8-1.3 s of silence; regenerate |
| 39 | Shotgun reload | 1 | 3.00 / 3 | -4.7 | -23.0 | 484 | - | gun_reload_2 | the shotgun's reload; waived: starts late, trimmed on import |
| 40 | Submachine gun reload | 4 | 2.00 / 2 | -8.0 | -25.8 | 294 | - | gun_reload_17 | the submachine gun's reload; waived: starts late, trimmed on import |
| 41 | Sniper rifle reload | 1 | 2.48 / 2.5 | -4.2 | -28.4 | 10 | - | gun_reload_3 | the sniper rifle's reload |
| 42 | Rocket launcher reload | 1 | 3.00 / 3 | -0.6 | -20.1 | 0 | - | gun_reload_4 | the rocket launcher's reload |
| 43 | Machine gun reload | 4 | 4.00 / 4 | -7.4 | -29.8 | 329 | - | gun_reload_20, gun_reload_19 | the machine guns' reload (slots 20 and 19); waived: starts late, trimmed on import |
| 44 | Revolver reload | 4 | 3.00 / 3 | -9.7 | -31.5 | 419 | - | gun_reload_23 | the Sechser Revolver's reload (new slot 23, Guns.reloadSound); waived: starts late, trimmed on import |
| 45 | Distant rifle fire | 1 | 3.00 / 3 | -0.4 | -22.4 | 0 | - | gun_distant_0 | distant rifle fire |
| 46 | Distant machine gun | 1 | 3.00 / 3 | -1.5 | -13.7 | 0 | - | gun_distant_19 | distant machine gun fire |
| 47 | Distant artillery | 4 | 4.00 / 4 | -2.5 | -25.7 | 0 | - | gun_distant_9 | distant artillery |
| 48 | Distant battle | 3 | 8.00 / 8 | -5.1 | -32.7 | 0 | 1.0 | battleLoop | the battle bed (replaces the old loop) |
| 49 | Item picked up | 4 | 0.49 / 0.5 | -6.8 | -26.8 | 0 | - | pickup | picking up an item |
| 50 | Leather armour on | 3 | 1.48 / 1.5 | -23.6 | -40.0 | 20 | - | armor_equip_0 | leather armour on |
| 51 | Mail armour on | 3 | 1.48 / 1.5 | -34.6 | -53.1 | 165 | - | armor_equip_1 | mail armour on; waived: starts late, trimmed on import |
| 52 | Plate armour on | 2 | 2.00 / 2 | -10.4 | -25.2 | 668 | - | armor_equip_2, armor_equip_3, armor_equip_4, armor_equip_5 | plate armour on (iron, gold, diamond, netherite slots); waived: starts late, trimmed on import |
| 53 | Coins traded | 2 | 1.48 / 1.5 | -8.3 | -27.5 | 0 | - | villagerTrade | a trade |
| 54 | Blacksmith at work | 3 | 3.00 / 3 | -1.2 | -21.4 | 90 | - | villager_work_0, villager_work_11, villager_work_12 | smith workstations at work |
| 55 | Carpenter at work | 4 | 3.00 / 3 | -0.8 | -13.2 | 0 | - | villager_work_6 | carpenter at work |
| 56 | Farmer at work | 1 | 2.48 / 2.5 | -5.9 | -24.9 | 5 | - | villager_work_4 | farmer at work |
| 57 | Tripwire | 3 | 0.69 / 0.7 | -0.9 | -19.5 | 5 | - | tripwire | a tripwire |
| 58 | Sulphur vents | 2 | 6.00 / 6 | -20.8 | -39.6 | 0 | 0.1 | sulfurLoop | sulphur vents (Emberdeep) |
| 59 | Deep boom | 4 | 4.00 / 4 | -9.4 | -27.6 | 105 | - | sealBoom | the Deep Seal's boom (DeepSeal) |
| 60 | Falling fast | 4 | 5.00 / 5 | -17.8 | -28.5 | 0 | 0.4 | fallRushLoop | falling fast |
| 61 | City square crowd | 1 | 10.00 / 10 | -21.8 | -37.2 | 0 | 0.7 | cityCrowdLoop | a town square with 12+ people |
| 62 | Market street | 4 | 8.00 / 8 | -19.1 | -35.4 | 0 | 1.4 | marketLoop | 2+ shopkeepers within 24 blocks |
| 63 | Crowd in panic | 3 | 6.00 / 6 | -15.9 | -27.3 | 0 | 0.0 | crowdPanicLoop | 3+ townsfolk panicking |
| 64 | Fighting in a city | 4 | 8.00 / 8 | -9.4 | -28.8 | 0 | 1.3 | cityFightLoop | a hostile Steelhold fighter within 40 blocks in town |
| 65 | Quest accepted | 4 | 2.00 / 2 | -1.4 | -11.2 | 0 | - | questAccept | taking a contract |
| 66 | Quest completed | 3 | 3.00 / 3 | -5.2 | -16.4 | 0 | - | questDone | a contract paid |
| 67 | Quest failed | 4 | 2.48 / 2.5 | -3.8 | -13.3 | 0 | - | questFail | a contract failed |
| 68 | Convoy horse and cart | 2 | 6.00 / 6 | -13.3 | -39.1 | 5 | 0.2 | convoyCartLoop | the nearest moving coach horse within 40 blocks |
| 69 | Customs gate | 1 | 3.00 / 3 | -15.0 | -35.0 | 324 | - | customsGate | paying at a customs post (Countries.paidPost); waived: starts late, trimmed on import |
| 70 | Well bucket | 1 | 4.00 / 4 | -11.6 | -30.5 | 45 | - | wellBucket | an empty bucket drawn up a well shaft (bucket reach 12 looking down a shaft) |
| 71 | House bought | 3 | 2.00 / 2 | -2.3 | -25.1 | 0 | - | houseBought | buying a house (Property.bought) |
| 72 | Far volcano | 2 | 8.00 / 8 | -5.4 | -22.9 | 0 | 2.9 | volcanoLoop | a volcano within reach (louder in eruption) |
| 73 | Sheet ice underfoot | 5 | 3.00 / 3 | -2.0 | -28.2 | 115 | - | sheetIceStep (5 slices) | footsteps on sheet ice (5 sliced steps) |
| 74 | Ice cracking under weight | 6 | 2.48 / 2.5 | -1.0 | -23.2 | 145 | - | iceCrack | a ship or Ash vehicle on sea ice (every 6 s; old take to _1) |
| 75 | Snowy bush | 4 | 1.48 / 1.5 | -17.2 | -29.0 | 0 | - | snowyBush | brushing foliage in snowy biomes |
| 76 | Chair | 2 | 1.00 / 1 | -7.2 | -24.6 | 0 | - | chairSit | sitting on a seat (Seats) |
| 77 | Chest of drawers | 4 | 1.48 / 1.5 | -17.0 | -37.1 | 50 | - | drawerOpen | opening and closing a desk's drawer (new desk drawer container) |
| 78 | Rocket tube in hand | 3 | 2.00 / 2 | -17.3 | -42.6 | 50 | - | faustShoulder | taking the Faust rocket tube in hand |


## Not wired

- 38 Pistol reload: no usable take. All four start 0.8-1.3 s late and hold a single click of 70-90 ms (sound from
  0.84 to 0.91 s in take 1, 1.29 to 1.38 s in take 2), not a 2 s magazine change. The sidearm keeps its synthesized
  reload. Regenerate it.

## Known limits

- Felled trees still play the synthesized creak and thump under the new tree recordings: they are played inside
  Felling.swift, a file kept out of this change (tree work in another lane). The recordings are heard over them.
