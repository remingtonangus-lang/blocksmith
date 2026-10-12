# Difficulty levels (backlog G19, Lane A thread, 2026-10-11)

Chosen on Create New World (Peaceful, Easy, Normal, Hard) and locked afterwards: the pause menu shows the level with
"(locked)" and pressing it only says so. Normal is the ask's "medium". The table lives in Sources/Difficulty.swift.

| | Easy | Normal | Hard |
|---|---|---|---|
| Monster damage to you | half + 1 (the reference formula) | as listed | x1.5 |
| Monster toughness (blows they take) | x0.75 | x1 | x1.4 |
| Monster speed | x0.9 | x1 | x1.12 |
| Monsters kept around you (spawn cap) | x0.65 | x1 | x1.35 |
| Hunger drain (moving, sprinting, jumping) | x0.75 | x1 | x1.3 |
| Starvation stops at | 5 hearts | half a heart | death |

Peaceful keeps its old rules (no monsters, hunger never harms). Toughness applies to monsters only (not animals,
townsfolk or soldiers, whose own tables set them). Check: `questcheck --p11-only` "G19 difficulty".
