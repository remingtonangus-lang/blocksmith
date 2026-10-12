# Combat balance: time-to-kill table (Q2)

Written by `questcheck --balance-only --write-balance` (Sources/BalanceTests.swift): real duels through
Game.tick on a walled stone floor at midnight, Normal difficulty. "Kills you": seconds until the mob has dealt
20 damage to a player standing still. "You kill it": seconds of full-charge swings at a mob held 2.5 blocks
off (it still fights). Tiers: early (no armour, stone sword), iron (iron set and sword), diamond (diamond set
and sword). "Kills you" averages three seeded duels, "you kill it" is one, so a cell can move a little with
hit luck.

| mob | kills you: early | iron | diamond | you kill it: early | iron | diamond |
|---|---|---|---|---|---|---|
| Zombie | 6.8 s | 20.8 s | 20.8 s | 3.3 s | 2.6 s | 2.0 s |
| Dust Zombie | 7.0 s | 20.9 s | 20.8 s | 3.3 s | 2.6 s | 2.0 s |
| Sunken | 6.9 s | 20.8 s | 20.9 s | 2.6 s | 2.6 s | 2.0 s |
| Skeleton | 15.7 s | > 60 s | > 60 s | 2.6 s | 2.6 s | 2.0 s |
| Frost Skeleton | 19.8 s | 48.3 s | > 60 s | 2.6 s | 2.6 s | 2.0 s |
| Spider | 9.3 s | 20.1 s | > 60 s | 2.6 s | 2.0 s | 2.0 s |
| Cave Spider | 9.0 s | 20.4 s | > 60 s | 2.0 s | 1.3 s | 1.3 s |
| Witch | 9.7 s | 9.8 s | 9.7 s | 3.9 s | 2.6 s | 2.6 s |
| Voidwalker | 2.9 s | 5.0 s | 10.0 s | 5.3 s | 4.6 s | 3.9 s |
| Brigand | 2.3 s | 3.2 s | 5.3 s | 3.3 s | 2.6 s | 2.6 s |
| Marauder | 10.6 s | 26.6 s | 55.0 s | 3.3 s | 2.6 s | 2.6 s |
| Capital Trooper | 5.1 s | 8.9 s | 9.5 s | 3.9 s | 3.3 s | 2.6 s |

Hisser blast at 1.5 blocks: 20 / 20 / 14 damage (early / iron / diamond).

Designed ranges (the checks): with iron gear no common night mob (zombie, husk, drowned, skeleton, spider)
kills you in under 4 s and nothing in under 2 s, and no common night mob in under 2 s unarmoured; early gear beats each common night mob one on one
and diamond gear beats every mob here; a diamond sword needs more than one swing on everything; each tier up
is at least as good against every mob; a hisser blast takes at least half an unarmoured player's health and
diamond armour survives it (at Normal a point-blank blast can kill a player in iron, as in the reference). The Deep's units: docs/status/deep-balance.md; the soldier classes:
docs/status/troop-classes.md.