# Art style: what is still procedural (2026-10-10)

Style 3 "stylised realism" (docs/art/style-options/3-stylised-realism.png) is applied to 866 of 1712 texture layers:
every common terrain/ore/stone/wood/plant block, the workshop blocks, the original Blocksmith blocks (capital,
frigate, warship, Ash, Steelhold) and all item icons except the 12 below. Sources: 20 Gemini block sheets, 19 icon
sheets, 3 plant sheets (assets/CREDITS.md); families derived by tools/texderive.py and tools/iconderive.py.
Recount: `Blocksmith --hdatlas /tmp/a.png --names '*'` lists every layer; compare with Resources/Textures.

## Kept procedural on purpose
- UI/runtime layers: glyph_* (95, pixel font), destroy_0-9, effect_* (39 status icons), moon_0-7, sun, xp_bar,
  missing, shadow, smoke, water, lava, nether_portal (animated or palette-driven).
- banner_pat_* (84) and banner_cloth: masks dyed at runtime. paintings (41): original painted art, own style.
- redstone_dust_0-15 (signal levels), crops (*_stage*, *_crop*: 37 growth stages), head_*/skull_* (15+9 mob heads:
  mob looks are redesigned separately).

## Still to do (next art pass: one Gemini sheet each or a derivation)
- Items (tinted multi-layer icons, need the bottle/liquid and shell/spots split kept): item_potion_bottle,
  item_potion_liquid, item_splash_bottle, item_lingering_bottle, item_tipped_arrow(+_head), item_spawn_egg(+_shell),
  item_frame, item_harness(+_band), item_explorer_mark.
- Blocks:
  acacia_door_bottom acacia_door_top acacia_trapdoor activator_rail activator_rail_on amethyst_cluster ammo_crate_side 
  ammo_crate_top ancient_debris_top anvil armored_glass ash_crate ash_crate_top ash_drum_side ash_drum_top ash_lamp 
  ash_lift ash_mark ash_sandbags at azalea_side azalea_top bamboo_block_top bamboo_stalk banner_cloth_b banner_cloth_t 
  barrel_bottom barrel_top beacon_core beacon_glass bee_nest_front bee_nest_front_honey bee_nest_top 
  beehive_front_honey beehive_top bell big_dripleaf_stem big_dripleaf_top birch_door_bottom birch_door_top 
  birch_trapdoor black_bed_side black_bed_top_foot black_bed_top_head black_candle black_glazed_terracotta 
  black_shulker_box_side black_shulker_box_top black_stained_glass blast_furnace_front blue_bed_side blue_bed_top_foot 
  blue_bed_top_head blue_candle blue_glazed_terracotta blue_shulker_box_side blue_shulker_box_top blue_stained_glass 
  bone_block_top brain_coral brewing_bottle brewing_stand_base brewing_stand_rod brown_bed_side brown_bed_top_foot 
  brown_bed_top_head brown_candle brown_glazed_terracotta brown_shulker_box_side brown_shulker_box_top 
  brown_stained_glass bubble_coral budding_amethyst bush cactus_flower cake_bottom cake_inner cake_side cake_top 
  campfire_fire campfire_log candle capital_airframe capital_glass capital_window capital_wing carved_pumpkin_face 
  cauldron cauldron_water cave_vines chain cherry_door_bottom cherry_door_top cherry_trapdoor chipped_anvil 
  chiseled_bookshelf_empty chiseled_bookshelf_side chiseled_bookshelf_top chiseled_copper chorus_flower chorus_plant 
  closed_eyeblossom cobweb command_console_side command_console_top comparator comparator_on composter_compost 
  composter_ready composter_side composter_top conduit copper_bars copper_bulb copper_bulb_lit copper_chain 
  copper_chest_front copper_chest_side copper_chest_top copper_door_bottom copper_door_top copper_grate copper_lantern 
  copper_torch copper_torch_top copper_torch_top_full copper_torch_wall copper_trapdoor crafter_bottom crafter_front 
  crafter_side crafter_top creaking_heart creaking_heart_active creaking_heart_top crimson_door_bottom crimson_door_top 
  crimson_fungus crimson_nylium_side crimson_roots crimson_trapdoor cyan_bed_side cyan_bed_top_foot cyan_bed_top_head 
  cyan_candle cyan_glazed_terracotta cyan_shulker_box_side cyan_shulker_box_top cyan_stained_glass damaged_anvil 
  dark_oak_door_bottom dark_oak_door_top dark_oak_trapdoor daylight_detector_inverted_top daylight_detector_side 
  daylight_detector_top decorated_pot detector_rail detector_rail_on dirt_path_side dragon_egg dried_ghast_0 
  dried_ghast_1 dried_ghast_2 dried_ghast_3 dried_ghast_top_0 dried_ghast_top_1 dried_ghast_top_2 dried_ghast_top_3 
  dried_kelp_side dried_kelp_top enchanting_table_bottom enchanting_table_side enchanting_table_top end_portal 
  end_portal_frame_eye end_portal_frame_side end_portal_frame_top end_rod ender_chest_front ender_chest_side 
  ender_chest_top exposed_chiseled_copper exposed_copper exposed_copper_bars exposed_copper_bulb 
  exposed_copper_bulb_lit exposed_copper_chain exposed_copper_chest_front exposed_copper_chest_side 
  exposed_copper_chest_top exposed_copper_door_bottom exposed_copper_door_top exposed_copper_grate 
  exposed_copper_lantern exposed_copper_trapdoor fire fire_coral fire_coral_block flower_pot frigate_mark 
  frigate_porthole frigate_thruster frogspawn frosted_ice_0 frosted_ice_1 frosted_ice_2 frosted_ice_3 gilded_blackstone 
  glass glow_item_frame glow_lichen grass_block_snow gray_bed_side gray_bed_top_foot gray_bed_top_head gray_candle 
  gray_glazed_terracotta gray_shulker_box_side gray_shulker_box_top gray_stained_glass green_bed_side 
  green_bed_top_foot green_bed_top_head green_candle green_glazed_terracotta green_shulker_box_side 
  green_shulker_box_top green_stained_glass grindstone hanging_roots heavy_core hopper_outside hopper_top horn_coral 
  iron_bars iron_door_bottom iron_door_top iron_trapdoor jack_o_lantern_face jungle_door_bottom jungle_door_top 
  jungle_trapdoor lantern large_fern_bottom large_fern_top lava leaf_litter lectern_side lectern_top lever 
  light_blue_bed_side light_blue_bed_top_foot light_blue_bed_top_head light_blue_candle light_blue_glazed_terracotta 
  light_blue_shulker_box_side light_blue_shulker_box_top light_blue_stained_glass light_gray_bed_side 
  light_gray_bed_top_foot light_gray_bed_top_head light_gray_candle light_gray_glazed_terracotta 
  light_gray_shulker_box_side light_gray_shulker_box_top light_gray_stained_glass light_panel lilac_bottom lilac_top 
  lily_pad lime_bed_side lime_bed_top_foot lime_bed_top_head lime_candle lime_glazed_terracotta lime_shulker_box_side 
  lime_shulker_box_top lime_stained_glass lodestone_side lodestone_top loom_top magenta_bed_side magenta_bed_top_foot 
  magenta_bed_top_head magenta_candle magenta_glazed_terracotta magenta_shulker_box_side magenta_shulker_box_top 
  magenta_stained_glass mangrove_door_bottom mangrove_door_top mangrove_propagule mangrove_roots mangrove_trapdoor 
  missing mycelium_side nether_portal oak_door_bottom oak_door_top oak_trapdoor observer_back observer_back_on 
  observer_top open_eyeblossom orange_bed_side orange_bed_top_foot orange_bed_top_head orange_candle 
  orange_shulker_box_side orange_shulker_box_top orange_stained_glass oxidized_chiseled_copper oxidized_copper_bars 
  oxidized_copper_bulb oxidized_copper_bulb_lit oxidized_copper_chain oxidized_copper_chest_front 
  oxidized_copper_chest_side oxidized_copper_chest_top oxidized_copper_door_bottom oxidized_copper_door_top 
  oxidized_copper_grate oxidized_copper_lantern oxidized_copper_trapdoor pale_hanging_moss pale_oak_door_bottom 
  pale_oak_door_top pale_oak_sapling pale_oak_trapdoor peony_bottom peony_top pink_bed_side pink_bed_top_foot 
  pink_bed_top_head pink_candle pink_glazed_terracotta pink_petals pink_shulker_box_side pink_shulker_box_top 
  pink_stained_glass piston_bottom piston_inner pitcher_plant podzol_side pointed_dripstone powered_rail 
  powered_rail_on purple_bed_side purple_bed_top_foot purple_bed_top_head purple_candle purple_glazed_terracotta 
  purple_shulker_box_side purple_shulker_box_top purple_stained_glass purpur_pillar_top quartz_pillar_top rail 
  rail_corner red_bed_side red_bed_top_foot red_bed_top_head red_candle red_glazed_terracotta red_shulker_box_side 
  red_shulker_box_top red_stained_glass redstone_torch redstone_torch_off repeater repeater_on respawn_anchor_bottom 
  respawn_anchor_side respawn_anchor_top respawn_anchor_top_off rose_bush_bottom rose_bush_top scaffolding_side 
  scaffolding_top sculk_catalyst_side sculk_catalyst_top sculk_sensor_side sculk_sensor_top sculk_shrieker_side 
  sculk_shrieker_top sculk_tendril sculk_vein sea_pickle shadow ship_balloon ship_barrel ship_blade ship_brass 
  ship_engine_front ship_engine_side ship_engine_top ship_ring_side ship_ring_top ship_tyre ship_wing short_dry_grass 
  shulker_box_side shulker_box_top small_dripleaf smoke sniffer_egg soul_campfire_fire soul_fire soul_lantern 
  soul_torch soul_torch_top_full soul_torch_wall spawner spore_blossom spruce_door_bottom spruce_door_top 
  spruce_trapdoor stonecutter_side stonecutter_top stripped_bamboo_block_top sun sunflower_bottom sunflower_top 
  tall_dry_grass tall_grass_bottom tall_grass_top tnt_bottom torch torch_bottom torch_top torch_top_full torch_wall 
  torchflower trapped_chest_front trial_spawner_side trial_spawner_top tripwire tripwire_hook tube_coral turtle_egg 
  twisting_vines vault_side vault_top vine warped_door_bottom warped_door_top warped_fungus warped_nylium_side 
  warped_roots warped_trapdoor warship_stripe water weathered_chiseled_copper weathered_copper_bars 
  weathered_copper_bulb weathered_copper_bulb_lit weathered_copper_chain weathered_copper_chest_front 
  weathered_copper_chest_side weathered_copper_chest_top weathered_copper_door_bottom weathered_copper_door_top 
  weathered_copper_grate weathered_copper_lantern weathered_copper_trapdoor weeping_vines white_bed_side 
  white_bed_top_foot white_bed_top_head white_candle white_shulker_box_side white_shulker_box_top white_stained_glass 
  wildflowers without xp_bar yellow_bed_side yellow_bed_top_foot yellow_bed_top_head yellow_candle 
  yellow_glazed_terracotta yellow_shulker_box_side yellow_shulker_box_top yellow_stained_glass 