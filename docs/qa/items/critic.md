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
| 2 (Claude / Gemini) | turned 40 degrees, food at 0.25, lit walls, no outline on model faces, tools lying level, drop shadows in Fast, distance growth | 2 -> 5 (old cave shot vs the tier grid) | 6 -> 5 / 3 -> 4 | 4 -> 6; shield 6 |

Round 1 notes: held items read as flat outlined cards (face exactly toward the eye, side walls near-black), the held
apple far too big, dropped tools stood on the handle's tip. Changed for round 2: held items turned ~40 degrees off the
eye line, food/potions at 0.25 (was 0.36), walls sample 5 px inside the contour and are lit no darker than 0.66,
dropped items lean back 18 degrees and tools lie level.

Round 2 notes: the apple is now the right size and no longer a sticker; the shield reads well. The held pickaxe split
the critics (Gemini preferred the new one, Claude the round-1 version, which was enchanted and purple-glinted: not a
like-for-like pair); both asked for a crisper diamond head. Dropped items: real 3D with shadows, but they hovered
well above their shadows (fixed: they now rest 0.05-0.25 over the ground), the apple leaf was too dark (lighter leaf
green). The translucent tan quads Claude flagged in the tier grid are the sunlit sides of a one-block sand step (in
the older shots too). Claude also asked for a hand gripping the held item (the genre shows none while holding one).
