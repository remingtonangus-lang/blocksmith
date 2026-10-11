# Townsfolk variety (backlog B2, 2026-10-11, Lane B thread)

Remington's intent: villager attack rates, health and speed vary. Listed: per-person stats rolled from role and age
(farmers weak and slow, blacksmiths strong, deputies fast and armed), with visible cues (build, tools) so players can
read them.

## Expanded objectives (written before building)
1. Four stats per person: toughness (damage taken is divided by it), speed (walk and run), strength (melee damage
   and knockback) and rate (swings per second). Base values per role and age; each person's own roll on top (+-12%,
   +-8% for children and elders), seeded by name and look so nothing new is saved and the same person never changes.
2. Roles: farmers weak and slow; elders the slowest and frailest adults; children frail and quick but harmless;
   blacksmiths (and hammer craftsmen: armorers, toolsmiths, weaponsmiths, masons) strong and tough but slow to swing;
   butchers strong; doctors and tailors slight; deputies fast and quick to swing; the sheriff the toughest.
   No difference between men and women.
3. Readable at a glance: a broader or slighter build in the model (width and depth below the neck, 0.86x-1.16x), the
   trade's tool in hand (already per role), and in town a line under the crosshair for the person you look at:
   "Silas Ridley, blacksmith: strong, tough".
4. Re-rolled when the role changes (a child grows up, a second sheriff becomes a deputy).
5. Cheap: stats cached per mob (not saved), the crosshair scan only in town.

## Defaults picked
- Toughness scales damage taken rather than max health, so health bars, healing and saves stay as they are.
- The sheriff's six-iron ignores strength (a gun is a gun; SixIron owns its damage).

## Checks
`questcheck --towns-only` (TownStatsTests via TownTests.run): role means over 300 people each, spread person to
person, determinism, a child growing up re-rolls, a 12-point blow on an elder vs a blacksmith, hammer vs pitchfork
damage and deputy vs smith swing rate through Mob.townDefend, a deputy outwalking an elder in real Mob.update frames,
model width, the crosshair line's text and that it follows your look.
