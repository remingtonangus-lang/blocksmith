# L3 flesh-out (Lane C): objectives and progress

Backlog item L3 (docs/roadmap/backlog.md), the overseer's flesh-out of the Oct 10 AM playtest list. The TOWNS items
belong to lane B and are skipped here. The soak test and device fps belong to lane M (the Mac worker).

## Audit: what was already met (2026-10-11)
- Auto render distance hysteresis: `RenderDistanceGovernor` drops only after sustained low fps and recovers after
  sustained headroom. MET.
- Camps: five types in WildCamps.swift (hunter, trader, bandit, deserter, surveyor), each with a campfire, a shelter,
  loot and an owner, friendly and hostile. Mostly MET; rarity tuning is in part 3 below.
- Volcano foothills, plume, glow and far silhouette, and capital siting: shipped (docs/status/worldgen-oct10.md).
- Ruined portals: removed from the game at Remington's request, so they are not rebuilt.
- New grass top and side art and a painted firefly bush: shipped (80cd6bb4).

## Part 1: ground (this PR)
Listed objectives: grass with 3-4 top variants, random rotation and biome tint; flower bushes with variants, a cheap
wind sway and a rustle sound; ores readable at 10+ blocks and distinct by colour and shape; before/after captures.

Expanded objectives (mine):
1. Plants bend in the wind on the Quest at no CPU cost and near-zero GPU cost: a vertex-shader offset on the top
   corners only. No mesh change in size and no extra draw.
2. Nothing tears. The lower half of a tall plant, stacked plants (cane, kelp, bamboo) and hanging plants (vines,
   roots) stay still; only a plant's free top moves.
3. Per-plant phase plus a gust wave that rolls downwind across a meadow, stronger in storms.
4. Grass tops come in 8 orientations (4 turns times a mirror) picked per block from its world position. Merged faces
   too (the projected uv), with no seam lines at block edges (the mip level and sharpening see unturned
   derivatives).
5. A leafy rustle every ~1.2 blocks walked inside plants (quieter when sneaking), as a proper bank sound with a
   subtitle.
6. Ores: each overworld ore gets its own shape as well as its colour: coal and copper in round lumps, iron in
   slanting streaks, gold in a scatter of nuggets, lapis in flat lenses, emerald in upright prisms (also nether gold
   nuggets and quartz prisms). The warm metals (iron, copper, gold) never rely on colour alone.
7. Every look change is measured by an automated check, and the Mac build stays unchanged: its shaders don't read the
   new bits, so the mesher leaves them off there.

How each is checked (questcheck):
- `plants:` (Sources/PlantTests.swift): the sway table, the mesher's corner marks (poppy, tall grass upper and
  lower), rustles walking 16 blocks through grass vs bare ground, the sound in the bank.
- `ores:` (Sources/OreTests.swift): each HD ore texture is measured against its bare stone (piece count, size,
  stretch, direction, colour). Each shape is asserted, and all 21 pairs must differ.
- `ground:` (quest/src/test/PlantRenderTest.swift, Quest renderer): a meadow's pixels move between two frames 0.7 s
  apart while a bare lawn and a repeated frame don't; a lawn seen from above shows 5+ orientations among 16 blocks.
- `--ground-only` stops after these; `--ground-shots DIR` writes the frames and the materials wall at 1, 4, 10 and 16
  blocks (`BS_ORE_LUMPS=1` renders the ores as they were before, for comparisons).

Verifier round 1 (fixed): dripleaf stems swayed (stacked: they parted at every joint), and swaying plants took their
phase as AO in the cave-fill term (random darker plants in caves). Also from its notes: sway fades out without
skylight (no wind in caves), underwater plants don't sway, and the rustle plays only on foot (not swimming or riding).

Evidence: docs/status/evidence/ground-l3/materials_before_after.png (the materials wall at 1, 4, 10 and 16 blocks,
ores before and after), sway_and_lawn.png (two meadow frames 0.7 s apart and the lawn seen from above).

## Later parts
- Part 2: VR melee and bow polish. Swing-mode first-use tutorial, blade trail, hit-stop, haptics by material,
  friendly-fire guard, enemy wind-up telegraphs, parry, reclined aim-assist and seated height calibration. Bow:
  nock, creak, string vibration, left-handed support, crossbow on the same hand logic.
- Part 3: perf overlay (fps, frame ms, render distance, chunk jobs) in settings, plus worldgen checks (capitals'
  distance from spawn and from each other over 50 seeds, rare small volcano eruptions, camp rarity).
