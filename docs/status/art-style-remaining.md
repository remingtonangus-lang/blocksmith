# Art style: what is still procedural (2026-10-10)

> **Art-gaps pass (25b4zzz, 2026-10-11):** 1809 layers; 320 stay procedural on purpose (list below), so 1489 should be
> in the style and **1221 are (82%)**. Every item icon (0 missing) and all 39 effect icons + the XP bar are styled;
> doors/trapdoors (all woods + copper/iron), glass + stained glass, beds, candles, shulker boxes, glazed terracotta,
> torches, lanterns, rails, tall grass, ferns, vines, lily pads, ancient debris, gilded blackstone are done; gold ore
> nuggets are bigger and brighter; quartz/diamond-deepslate seams blended. What is left (268) is the long tail below
> (workblocks, sculk, copper bulbs/chests, coral, Steelhold/capital/frigate panels, ship parts).

> **Recount by the done audit (25b6, 2026-10-11):** the game now has 1781 layers. 352 stay procedural on purpose
> (list below), so 1429 should be in the style and 865 are (61%): blocks 433 of 933, items 432 of 496. **64 item
> icons are missing, not 12**: content added since the pass (pelts, fur armour tiers, Sunderite items, the revolver,
> fish, potion/spawn-egg layer splits, journals) came in procedural. Biggest visible block families still
> procedural: doors and trapdoors, glass and stained glass, beds, candles, shulker boxes, glazed terracotta, torches,
> lanterns, rails, tall grass, ferns, vines, lily pads. Also: gold ore specks are too faint at 7 m, and
> nether_quartz_ore / deepslate_diamond_ore have marginal wrap seams. Follow-up: 25b4zzz-blocksmith-art-gaps (CHROME=1).

Style 3 "stylised realism" (docs/art/style-options/3-stylised-realism.png) is applied to 866 of 1712 texture layers:
every common terrain/ore/stone/wood/plant block, the workshop blocks, the original Blocksmith blocks (capital,
frigate, warship, Ash, Steelhold) and all item icons except the 12 below. Sources: 20 Gemini block sheets, 19 icon
sheets, 3 plant sheets (assets/CREDITS.md); families derived by tools/texderive.py and tools/iconderive.py.
Recount: `Blocksmith --hdatlas /tmp/a.png --names '*'` lists every layer; compare with Resources/Textures.

## Kept procedural on purpose
- UI/runtime layers: glyph_* (95, pixel font), destroy_0-9, moon_0-7, sun,
  missing, shadow, smoke, water, lava, nether_portal (animated or palette-driven).
- banner_pat_* (84) and banner_cloth: masks dyed at runtime. paintings (41): original painted art, own style.
- redstone_dust_0-15 (signal levels), crops (*_stage*, *_crop*: 37 growth stages), head_*/skull_* (15+9 mob heads:
  mob looks are redesigned separately).

## Still to do (next art pass: one Gemini sheet each or a derivation)
- Items: none.
- Blocks (268):
  amethyst_cluster ammo_crate_side ammo_crate_top anvil armored_glass ash_banner ash_banner_edge ash_banner_end
  ash_banner_mark ash_banner_top ash_blastdoor ash_bunkercrete ash_crate ash_crate_top ash_drum_side ash_drum_top
  ash_lamp ash_lift ash_mark ash_mortar ash_mortar_top ash_sandbags ash_standard_0 ash_standard_1 ash_standard_2
  ash_standard_3 ash_standard_4 ash_standard_5 ash_standard_6 ash_standard_7 ash_standard_8 ash_wire azalea_side
  azalea_top bamboo_block_top bamboo_stalk beacon_core beacon_glass bee_nest_front bee_nest_front_honey bee_nest_top
  beehive_front_honey beehive_top bell big_dripleaf_stem big_dripleaf_top blast_furnace_front brain_coral
  brewing_bottle brewing_stand_base brewing_stand_rod bubble_coral budding_amethyst bulkhead_door_bottom
  bulkhead_door_top bunker_concrete bunker_concrete_dark bunker_floor bush cactus_flower cake_bottom cake_inner
  cake_side cake_top campfire_fire campfire_log capital_airframe capital_glass capital_window capital_wing
  carved_pumpkin_face cauldron cauldron_water cave_vines chain chipped_anvil chiseled_bookshelf_empty
  chiseled_bookshelf_side chiseled_bookshelf_top chorus_flower chorus_plant closed_eyeblossom command_console_side
  command_console_top comparator comparator_on composter_compost composter_ready composter_side composter_top conduit
  copper_bulb copper_bulb_lit copper_chain copper_chest_front copper_chest_side copper_chest_top corner_lamp
  corner_lamp_side crafter_bottom crafter_front crafter_side crafter_top creaking_heart creaking_heart_active
  creaking_heart_top crimson_fungus crimson_nylium_side crimson_roots damaged_anvil data_cabinet_front
  data_cabinet_side data_cabinet_top daylight_detector_inverted_top daylight_detector_side daylight_detector_top
  decorated_pot deep_lift deep_lift_side dirt_path_side dragon_egg dried_ghast_0 dried_ghast_1 dried_ghast_2
  dried_ghast_3 dried_ghast_top_0 dried_ghast_top_1 dried_ghast_top_2 dried_ghast_top_3 dried_kelp_side ember_gate
  enchanting_table_bottom enchanting_table_side enchanting_table_top end_portal end_portal_frame_eye
  end_portal_frame_side end_portal_frame_top end_rod ender_chest_front ender_chest_side ender_chest_top
  exposed_copper_bars exposed_copper_bulb exposed_copper_bulb_lit exposed_copper_chain exposed_copper_chest_front
  exposed_copper_chest_side exposed_copper_chest_top fire fire_coral fire_coral_block flower_pot frigate_mark
  frigate_porthole frigate_thruster frogspawn frosted_ice_0 frosted_ice_1 frosted_ice_2 frosted_ice_3 gate_stone
  glow_item_frame grass_block_snow grindstone hanging_roots heavy_core hopper_outside hopper_top horn_coral
  jack_o_lantern_face leaf_litter lectern_side lectern_top lever light_panel lodestone_side lodestone_top loom_top
  mangrove_propagule mangrove_roots mycelium_side observer_back observer_back_on observer_top open_eyeblossom
  oxidized_copper_bars oxidized_copper_bulb oxidized_copper_bulb_lit oxidized_copper_chain oxidized_copper_chest_front
  oxidized_copper_chest_side oxidized_copper_chest_top pale_hanging_moss pale_oak_sapling pink_petals piston_bottom
  piston_inner podzol_side pointed_dripstone puff repeater repeater_on respawn_anchor_bottom respawn_anchor_side
  respawn_anchor_top respawn_anchor_top_off scaffolding_side sculk_catalyst_side sculk_catalyst_top sculk_sensor_side
  sculk_sensor_top sculk_shrieker_side sculk_shrieker_top sculk_tendril sculk_vein sea_pickle sealbound_bricks
  sealrock ship_balloon ship_barrel ship_blade ship_brass ship_engine_front ship_engine_side ship_engine_top
  ship_ring_side ship_ring_top ship_tyre ship_wing short_dry_grass small_dripleaf sniffer_egg soul_campfire_fire
  soul_fire spawner spore_blossom station_railing stonecutter_side stonecutter_top stripped_bamboo_block_top
  sunderite_ore tnt_bottom torchflower trapped_chest_front trial_spawner_side trial_spawner_top tripwire tripwire_hook
  tube_coral turtle_egg twisting_vines vault_side vault_top wardstone warped_fungus warped_nylium_side warped_roots
  warship_stripe weathered_copper_bars weathered_copper_bulb weathered_copper_bulb_lit weathered_copper_chain
  weathered_copper_chest_front weathered_copper_chest_side weathered_copper_chest_top weeping_vines wildflowers
