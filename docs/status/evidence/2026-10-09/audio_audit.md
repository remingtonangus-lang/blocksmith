# Audio audit (Blocksmith --audioaudit)

## Coverage

| material | blocks | examples |
|---|---|---|
| stone | 342 | stone, cobblestone, bedrock, coal_ore, iron_ore, gold_ore, diamond_ore, bricks |
| dirt | 7 | dirt, farmland, clay, coarse_dirt, rooted_dirt, packed_mud, dirt_path |
| sand | 20 | sand, red_sand, white_concrete_powder, orange_concrete_powder, magenta_concrete_powder, light_blue_concrete_powder, yellow_concrete_powder, lime_concrete_powder |
| wood | 290 | oak_planks, oak_log, birch_log, spruce_log, torch, soul_torch, crimson_stem, warped_stem |
| plant | 111 | cactus, short_grass, poppy, dandelion, cornflower, oak_sapling, birch_sapling, spruce_sapling |
| glass | 62 | glass, glowstone, ice, packed_ice, blue_ice, redstone_lamp, beacon, white_stained_glass |
| snow | 5 | water, snowy_grass_block, snow_block, snow, powder_snow |
| gravel | 2 | gravel, suspicious_gravel |
| metal | 183 | copper_torch, iron_block, gold_block, copper_block, sea_lantern, iron_door, iron_trapdoor, lantern |
| wool | 51 | white_wool, orange_wool, magenta_wool, light_blue_wool, yellow_wool, lime_wool, pink_wool, gray_wool |
| slime | 2 | slime_block, honey_block |
| mud | 1 | mud |
| bone | 1 | bone_block |
| amethyst | 3 | amethyst_block, budding_amethyst, amethyst_cluster |
| soul | 3 | soul_sand, soul_soil, dried_ghast |
| sculk | 5 | sculk, sculk_shrieker, sculk_vein, sculk_sensor, sculk_catalyst |
| netherrack | 5 | netherrack, nether_quartz_ore, nether_gold_ore, crimson_nylium, warped_nylium |
| deepslate | 87 | deepslate, basalt, blackstone, polished_blackstone, polished_blackstone_bricks, cracked_polished_blackstone_bricks, chiseled_polished_blackstone, gilded_blackstone |
| grass | 5 | grass_block, podzol, mycelium, moss_block, pale_moss_block |
| leaves | 9 | oak_leaves, birch_leaves, spruce_leaves, acacia_leaves, dark_oak_leaves, jungle_leaves, mangrove_leaves, cherry_leaves |
- PASS: material stone has break/place/step/hit/fall sounds
- PASS: material dirt has break/place/step/hit/fall sounds
- PASS: material sand has break/place/step/hit/fall sounds
- PASS: material wood has break/place/step/hit/fall sounds
- PASS: material plant has break/place/step/hit/fall sounds
- PASS: material glass has break/place/step/hit/fall sounds
- PASS: material snow has break/place/step/hit/fall sounds
- PASS: material gravel has break/place/step/hit/fall sounds
- PASS: material metal has break/place/step/hit/fall sounds
- PASS: material wool has break/place/step/hit/fall sounds
- PASS: material slime has break/place/step/hit/fall sounds
- PASS: material mud has break/place/step/hit/fall sounds
- PASS: material bone has break/place/step/hit/fall sounds
- PASS: material amethyst has break/place/step/hit/fall sounds
- PASS: material soul has break/place/step/hit/fall sounds
- PASS: material sculk has break/place/step/hit/fall sounds
- PASS: material netherrack has break/place/step/hit/fall sounds
- PASS: material deepslate has break/place/step/hit/fall sounds
- PASS: material grass has break/place/step/hit/fall sounds
- PASS: material leaves has break/place/step/hit/fall sounds
- PASS: no dry-named block uses the mud or slime material
- PASS: grass_block steps sound grass (got grass)
- PASS: dirt steps sound dirt (got dirt)
- PASS: stone steps sound stone (got stone)
- PASS: sand steps sound sand (got sand)
- PASS: gravel steps sound gravel (got gravel)
- PASS: oak_planks steps sound wood (got wood)
- PASS: cobblestone steps sound stone (got stone)
- PASS: deepslate steps sound deepslate (got deepslate)
- PASS: snow_block steps sound snow (got snow)

Silent mob kinds (no voice profile): endCrystal, minecart, boat, armorStand, deckGun, ashTank, ashHalftrack, ashArtillery, ashTruck

Sound bank: 769 sounds (+ mob voices, guns and vehicles rendered on demand).

- FAIL: every creature and vehicle kind has a voice or engine profile (deckGun, ashTank, ashHalftrack, ashArtillery, ashTruck)

## Ambience context rules

- PASS: forest at noon: birdsong (9 calls)
- PASS: forest at midnight: no birdsong (owlHoot loop:crickets)
- PASS: cave under the forest at noon: no birds, owls or insects (y 51: )
- PASS: cave under the forest at midnight: no birds, owls or insects (y 51: )
- PASS: shallow dark cave near the forest surface at noon: no birds, owls or insects (y 68, sky light 0: )
- PASS: Ash Vault at noon: no birds, owls or insects
- PASS: the Deep's hell band at noon: no birds, owls or insects

1 failing checks.
