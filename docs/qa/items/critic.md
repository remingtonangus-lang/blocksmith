# Item art: blind critic rounds

Sheets: `--itemsheet tools|items[:4[:page]]` at 1920 x 1080 (icons 64 px, TV scale), old art (docs/qa/items/before)
against the new, labels shuffled per pair; critics see only the images and a brief (TV readability, upper-left light,
palette with voxel blocks, distinct tiers, material cues, no noise, consistency, polish). Gemini: `tools/item_critic.py`;
Claude: a fresh subagent per round. Scores are old -> new.

| Round | Change before it | Tools | Items p1 | Items p2 |
|---|---|---|---|---|
| 1 (Gemini, lab preview) | vector tools / armour v2 | 4 -> 7 | 3 -> 8 (families preview) | |
| 2 (Claude) | in-game v2, families | 3.5 -> 7 | 4.5 -> 7 | |
| 3 (Gemini) | | | | 6.5 -> 7.5 |
| 4 (Claude / Gemini) | guns, ingots, tier silhouettes, emblems | 5 -> 8 / 4 -> 7.5 | 5 -> 8 / +1.5 | 4 -> 7.5 / 4.5 -> 6.5 |
| 6 (Claude / Gemini) | round 5: eggs, potion forms, wood, chainmail, boats | 4.5 -> 7.5 | 5 -> 7.5 / 6 -> 7.5 | 5 -> 7 / 4 -> 6 |
| 7 (Claude / Gemini) | round 6: two-tone eggs per mob, duskium, coal, chops, lead, crossbow, wings | 5 -> 8 / 6 -> 7.5 | 5 -> 8 | 4 -> 8 / 5 -> 7 |

Round 7 (Claude) verdict: the new set wins every pair by 3-4 points and reads "clearly good" (8/10) on all three
sheets. Its remaining notes (hoe vs axe heads, gold saturation, boats' plank weave, wheat, fire charge, chorus fruit,
pale-blue potion fills, the two muted egg rows) are the next polish pass.

## Held and dropped models

Shots: first-person `--hold <item>` on a plains meadow, `--camera 2` (third person), `--drops` in a lit cave and
`--dropgrid` (every tool tier) in a desert; old (flat sprite / camera-facing card) against the 3D models.

| Round | Change before it | Dropped | Held (tool) | Held (food) |
|---|---|---|---|---|
| 1 (Claude) | extruded models, contour walls, overlay models | 2 -> 7-7.5 | 6 | 4 |

Round 1 notes: held items read as flat outlined cards (face exactly toward the eye, side walls near-black), the held
apple far too big, dropped tools stood on the handle's tip. Changed for round 2: held items turned ~40 degrees off the
eye line, food/potions at 0.25 (was 0.36), walls sample 5 px inside the contour and are lit no darker than 0.66,
dropped items lean back 18 degrees and tools lie level.
