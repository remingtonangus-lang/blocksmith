# Troop classes (backlog A2)

Lane A thread, 2026-10-12. Code: Sources/TroopClasses.swift (classes, segmented armour, loot, guns), Soldiers.swift
(behaviour hooks), Ballistics.swift and Mob.hit (where hits land), SoldierRig.swift (looks), TroopTests.swift
(`questcheck --troopclasses-only`; part of every full questcheck run). Time-to-kill tables: troop-classes-ttk.md
(regenerated with `--troopclasses-only --write-ttk`).

## Classes
| class | armour (helmet / vest / greaves) | soaks | guns | behaviour | where |
|---|---|---|---|---|---|
| Regular | 20 / 30 / 20 | 30 % | rifle, SMG (troopers a shotgun or rifle, officers and crew a pistol) | hold and patrol | everywhere |
| Spec Ops | 30 / 45 / 30 | 45 % | scoped rifle (marksmen) or a suppressed SMG / rifle, grenades | flank wide, quietly; suppressed shots raise no alarm | marksmen and officers from the Greywall garrison tier up, a third of command-fortress troopers, Capital marksmen and officers |
| Hannibal | 60 / 90 / 60 | 65 % | Ashsaw-class machine gun, launcher, arc gun | push in while firing, long suppressing bursts | heavies of Greywall fortresses and command fortresses, Capital heavies (citadels) |

The name Hannibal is historical, not coined by a reference game (checked against tools/coined-terms.txt), so it stays
as Remington wrote it.

A Greywall outpost's garrison is all Regulars; Spec Ops start at the garrison tier.

The time-to-kill tables count continuous hits; a real fight adds misses, bursts and cover.

## Segmented armour
- A round lands on the helmet (top fifth), greaves (below the hips) or vest (between) by where it hits; a melee blow
  lands on the vest.
- A segment that holds soaks its class's share of the hit and wears by the whole hit. Under half it is cracked: the
  plate goes dull on the model and soaks 40 % less. At zero it falls off: a cracked piece drops (a tenth of its life
  left), a broken helmet leaves the head bare, and that part takes hits in full.
- A soldier the player kills drops each surviving piece 35 % of the time, with the life it had left.
- The pieces (Regular / Spec Ops / Hannibal Helmet, Vest, Greaves) are wearable armour and repair at an anvil with
  steel ingots.

## Defaults picked (no questions asked)
- Capital soldiers get a class by rank but keep their rank's gun (their loadouts and the pose check stay as they
  were); Greywall soldiers are armed by class. The Ashguard keep their own plate (no class).
- Gun rarity tiers (common, fine, rare, elite with stat ranges) were not done here: the classes' armour pieces carry
  the rarity through their durability. Logged as a T item.
