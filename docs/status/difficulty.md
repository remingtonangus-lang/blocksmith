# Difficulty levels (backlog G19, reworked by P302 on 2026-10-15)

Chosen on Create New World (Peaceful, Very Easy, Easy, Normal, Hard, Very Hard) and locked afterwards. Each level has a
one-line description on the Create World page and on the settings' Difficulty row (Difficulty.help). The table lives in
Sources/Difficulty.swift; `Game.diffLevel` is the level (0...5) and `Game.difficulty` the older four-step band
(0 peaceful, 1 easy, 2 normal, 3 hard) that patrol sizes, door breaking and starvation floors still key on.

Enemy health is the same on every level (Remington, Oct 15: "realistic and fixed"); the level changes the player's side
and the enemy's edge.

| | Very Easy | Easy | Normal | Hard | Very Hard |
|---|---|---|---|---|---|
| Share of an attack that lands on you | x0.25 | x0.45 | x1 | x1.5 | x2 |
| Biggest single attack (half-hearts) | 3 | 5 | any | any | any |
| Armour stopping power | x1.3 | x1.15 | x1 | x0.85 | x0.7 |
| Health regeneration | x2 | x1.5 | x1 | x0.85 | x0.7 |
| Hunger drain | x0.5 | x0.7 | x1 | x1.25 | x1.5 |
| Enemy speed | x0.75 | x0.88 | x1 | x1.12 | x1.25 |
| Enemy gun/arrow spread | x2.4 | x1.7 | x1 | x0.75 | x0.55 |
| Enemy attack and fire rate | x0.5 | x0.7 | x1 | x1.2 | x1.45 |
| Enemy notice range | x0.6 | x0.8 | x1 | x1.15 | x1.3 |
| Monsters kept around you | x0.4 | x0.65 | x1 | x1.35 | x1.7 |
| Hits on hostile fliers count for | x2.5 | x1.8 | x1 | x1 | x1 |

On Very Easy and Easy a hit knocks a hostile flier down toward you instead of up, and Searwings wind up, dive and rest
at the level's pace. Saved worlds from before P302 keep their level (Easy, Normal, Hard); the save writes both
`difficulty` (band) and `diffLevel`.
