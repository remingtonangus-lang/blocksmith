# Bone meal audit (playtest Oct 9 PM #7)

"Bone meal doesn't work on sugar cane (and probably other plants). Audit every plant and make bone meal work wherever
it does in Bedrock."

Before: bone meal worked on wheat, carrots, potatoes, beetroots, the eight `_sapling`s, grass blocks (Farming.swift)
and cocoa (GameBlocks.swift); dispensers did crops and saplings only. Everything else (sugar cane, cactus, bamboo,
berry bushes, mushrooms, fungi, nylium, vines, dripleaf, moss, flowers, ferns, kelp, seagrass, pickles, the newer
crops, mangrove propagule, azaleas...) did nothing.

Now: one function, `Game.boneMealGrow` (Sources/BoneMeal.swift), used by the player (`Farming.useItemOnBlock` ->
`useBoneMeal`, which uses one bone meal and shows hearts) and by dispensers (GameCircuit).

Check: `Blocksmith --snapshot snaps/pm9b.png --seed 12345 --find plains --time 0.3 --rd 4 --questbugs --only pm9b`.
For every row it builds the setup (right soil, water, coral, nylium, ceiling...) on a pad 70 blocks above the spawn,
gives the player 64 bone meal in survival and calls `Game.useItemOnBlock` on the block (the path a right click takes)
until the world around changes or an item drops (probabilistic rows: up to 40 uses), then asserts something grew and
that exactly one bone meal was used per use. "Uses" is from one local run.

| block (internal key) | Bedrock effect implemented | grows + used up |
|---|---|---|
| wheat, carrots, potatoes | 2-5 stages | yes (1 use) |
| beetroots | +1 stage on 3 in 4 | yes (1-2 uses) |
| torchflower_crop | next stage, then torchflower | yes (1) |
| pitcher_crop | next stage, then pitcher plant | yes (1) |
| oak, birch, spruce, acacia, jungle, cherry saplings | 45% a use to advance; two stages, then the tree | yes (2-8) |
| dark_oak_sapling, pale_oak_sapling | 2x2 grows the big tree (a single one never grows; still uses bone meal, as in Bedrock) | yes (5-11) |
| mangrove_propagule | as a sapling | yes (4-16) |
| azalea | as a sapling (tree) | yes (2-7) |
| red_mushroom, brown_mushroom | 40% huge mushroom | yes (1-9) |
| crimson_fungus, warped_fungus | on their own nylium: 40% huge fungus (else not used) | yes (1-4) |
| crimson_nylium, warped_nylium | roots and fungi sprout on the nylium around | yes (1) |
| netherrack beside nylium | turns into that nylium | yes (1) |
| grass_block | short grass and flowers around | yes (1) |
| moss_block, pale_moss_block | moss spreads over stone/dirt around, carpets (+ grass, azalea on moss) | yes (1) |
| sugar_cane | grows to full height 3 (Bedrock); a 3-tall stalk doesn't use it | yes (1) |
| cactus | grows to full height 3 (Bedrock) | yes (1) |
| bamboo | 1-2 blocks up to its 12-16 cap | yes (1) |
| sweet_berry_bush | next stage | yes (1) |
| cocoa | next stage | yes (1) |
| kelp | one block up into the water above its tip | yes (1) |
| seagrass | seagrass spreads over the water-covered floor around | yes (1) |
| sand / gravel / dirt / clay / mud under water | seagrass sprouts | yes (1) |
| sea_pickle on a coral block | +1 pickle, pickles spread onto coral blocks around | yes (1) |
| twisting_vines | 1-3 blocks up | yes (1) |
| weeping_vines | 1-3 blocks down | yes (1) |
| cave_vines | 1 block down (every cave vine block here carries glow berries, so this is "more berries") | yes (1) |
| small_dripleaf | becomes a big dripleaf 2-5 tall | yes (1) |
| big_dripleaf | one block taller | yes (1) |
| short_grass | tall grass | yes (1) |
| fern | large fern | yes (1) |
| short_dry_grass | tall dry grass | yes (1) |
| dandelion, poppy, allium, azure_bluet, 4 tulips, oxeye_daisy, cornflower, lily_of_the_valley, blue_orchid | Bedrock: more of the same flower on the soil around | yes (1 each, 12 rows) |
| sunflower, lilac, rose_bush, peony | drops a copy | yes (1) |
| pink_petals, wildflowers | drops a copy (one-state blocks here: the "full" case) | yes (1) |
| bush, firefly_bush | spreads to a free spot beside it | yes (1) |
| rooted_dirt | hanging roots below | yes (1) |
| sugar cane 1 / 2 / 3 tall | -> 3 / 3 / 3, bone meal used / used / kept | yes |

Non-targets (Bedrock): nothing happens and the bone meal stays in the hand (all pass):
dead_bush, lily_pad, vine, nether_wart, torchflower, pitcher_plant, leaf_litter, tall_dry_grass, cactus_flower,
crimson_roots.

Not in this game (no block to target): melon and pumpkin stems (the seeds exist but plant nothing), bamboo shoot /
sapling, tall seagrass, glow lichen spreading (left out: the block has no per-face states to grow), mangrove leaves
growing propagules (no hanging propagule state), cave vines without berries (every cave vine is lit and drops berries).
