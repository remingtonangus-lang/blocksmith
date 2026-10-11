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

## Verifier pass (independent Opus subagent, 2026-10-11) and what changed
- Fixed: the stats cache only keyed on role, so a craftsman who lost his workstation and took another kept the old
  trade's stats (and they changed on reload); it now keys on role, trade and shop (plain compares, no per-frame
  string building).
- Fixed: farmers could never read "weak" and a third of them showed nothing; the glance words now compare against an
  ordinary adult (weak <= 0.88, slow <= 0.9, ...), biggest difference first, and swing rate shows ("fast hands").
- Fixed (Quest): the line followed the aiming hand and flickered across busy streets; it now needs 0.3 s of steady aim
  and lingers 0.5 s, sits lower (clear of the damage ring and the deck-gun reload bar) and hides with the weapon wheel
  or a manned gun. Keepers read by their trade ("storekeeper"), a craftsman without a trade as "craftsman".
- Known (by design): elders and farmers flee zombies more slowly now (about 1.4 and 1.8 blocks/s against a zombie's
  2.3), so more of them are caught at night and in raids; deputies top out near 3.2 blocks/s, under a sprinting
  player and a horse. Speed and swing rate have no body cue beyond the line.

## Checks
`questcheck --towns-only` (TownStatsTests via TownTests.run): role means over 300 people each, spread person to
person, determinism, a child growing up re-rolls, a 12-point blow on an elder vs a blacksmith, hammer vs pitchfork
damage and deputy vs smith swing rate through Mob.townDefend, a deputy outwalking an elder in real Mob.update frames,
model width, the crosshair line's text and that it follows your look.
- Split-screen co-op: the glance line shows for the first seat only (shared aim state; the verifier's re-check).
