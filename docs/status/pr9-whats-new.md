# PR #9 what's new (full history)

The player-facing list from the PR description, kept here in full; the PR shows the newest part.

## What's new since f1fb07a

### Since 2026-10-05 (being tested)
The full test suite on `5cd19c5` (run [770](https://github.com/remingtonangus-lang/blocksmith/actions/runs/38002092475)) passed the build, the 60-second play tests, the benchmarks and the snapshots; three checks were red and are fixed in `0430fec` (being tested): a jungle temple and a Capital city standing over a mineshaft or stronghold corridor dug out after them, a wrecked crawler's crew walking down its ramp, and the Blight fight in the scripted playthrough (being traced). The quick checks on the newest commit, `7629ff8`, passed.

- **The Deep and the final battle:** no bedrock floor any more. Dig through the bottom of the world into the Deep, a dimension under the surface: a molten crust, a hell band with fortresses, then the Ash Vault, an open cavern where the Ashguard (an original black-and-red army) holds a citadel with motor pools, fuel depots, gun pits and outposts. Cinder tanks, half-tracks and field guns fight you; the Ash Marshal is the final boss, and his fall ends the war (an epilogue and a lift home).
- **Factions:** the frigate is now the Meridian Navy's (its own faction and hull, drivable, with a MAC gun that craters citadels). Capital cities (white garden cities with covered walkways) appear on open ground, citadels are easier to find (a radar and intercepted orders point to them), and every faction fights the others. You can take the helm of a Capital frigate or dropship.
- **Copper replaces sparkstone:** circuits are copper (Copper Wire, Copper Signal Torch...); a 111-row check against the classic circuit rules is all green. Titanium replaces diamond on screen and steel is smelted in the blast furnace; old saves load unchanged.
- **New gear:** a craftable Jetpack (60 s of fuel), gun enchantments (Extended Magazine and others), and a bonded horse that keeps near you like a ranch horse.
- **Your Oct 9 playtest notes:** blocks break and place from 6 blocks (melee stays 3.5); closing a menu with B no longer dismounts you; caves spawn monsters again while the surface is half as crowded; Hissers flinch when hit (steady melee kills them before they blow); a calmer ground (far less grass, flowers and cacti); bone meal grows every plant it should; cows and horses drop 1-3 leather.
- **Feel and polish:** smoother step-ups for the camera, mounts and mobs; the Mac pad uses a Halo Infinite layout by default (Classic in Button Mapping); a new natural look for Fast graphics (horizon haze, stronger sun); rebuilt block, gunfire, engine, rain and wind sounds; lily pads sit flat on the water; stars fade with the sun; far fewer animals; no hitches in the first minutes of a world or near villages (time-sliced path searches).
- **Closer to the classic game, rounds 5 and 6 (enchantments, movement, mobs):** listed with rounds 2-4 under the 2026-10-05 notes below. Also **waterlogging**: stairs, slabs, fences, walls, panes, iron bars, ladders and lanterns can hold water.

### Your playtest notes (2026-10-05)
CI run [563](https://github.com/remingtonangus-lang/blocksmith/actions/runs/37255060620) (`7005780`, the full suite) was green on everything below except the split-screen play test. The full suite on `4d315cd` (run [634](https://github.com/remingtonangus-lang/blocksmith/actions/runs/37271912609)) found three more problems (memory use, a crawler's crew leaving their posts, a citadel's rebuild cost); the fixes are in `fcaeb04` and later. The quick checks on `144ba6e` and `01f1b95` passed. Run [682](https://github.com/remingtonangus-lang/blocksmith/actions/runs/37299279800) stopped at the build (one map-drawing function was too slow for the compiler in the optimized build; fixed). Run [692](https://github.com/remingtonangus-lang/blocksmith/actions/runs/37303117225) on `1b8f474` passed everything but the scripted Blight fight and the crawler crew check (followed up in the section above).

- **Sugar cane no longer floats.** Breaking any block of a plant stack (or the block under it) pops everything it held, with the drops, one block after another: sugar cane, cactus and bamboo of any height, kelp up through its water (the water stays), weeping and cave vines under a broken ceiling, vines on a broken log, both halves of tall flowers, and flowers or crops whose ground is blown up, pushed away or dug out. Carpets, snow layers, pressure plates, rails, sparkstone dust, repeaters, comparators, flower pots and lanterns (hanging or standing) fall with their block too. A new check builds every kind and fails if anything is left floating.
- **Your own music.** Put audio files (mp3, m4a, wav, aiff) in `~/Library/Application Support/Blocksmith/Music` (the folder is made the first time the game starts).
  - Options > Audio > Soundtrack: Built-in, My Music (your files only; the game's music only while the folder is empty), or Mixed (they take turns).
  - Shuffle, a My Music volume, and Next Track: Y on the pause menu, the N key (Key Bindings > Skip Music Track), or Options > Audio > Skip Track.
  - Your tracks play right through fights and dimension changes, and the next one starts a few seconds later.
  - The repository ships no music: the folder is only for your files on your Mac.
- **Invisible mobs: found and fixed** (the new mob check passes on CI run 549; confirm it in play). In real play at render distance 16-24 hundreds of mobs are loaded, and the buffer that holds mob shapes each frame (4 MB) filled with far-off mobs before the ones beside you, which were then never drawn. The new Capital soldiers made it much worse: one up close is 190 pieces, so a dozen of them filled the whole buffer. The CI renderer never loads that many mobs, so it never saw it.
  - Mobs are now drawn nearest first, nothing hidden in the fog is drawn, and the buffers grow (up to 16 MB) when they fill.
  - A new check renders every mob kind (Fancy, Fast, smaller world scale, after a survival night, after a save and load) and 600 mobs round a cow beside you; CI now fails if any of them draws nothing. On run 549 the cow drew with 246 far-off mobs left out of the full buffer.
  - If you ever see it again: F3 shows a "Mobs:" line (how many near you, drawn, dropped), and a voice bug note records the same.
- **Mobs forget you when you die.** Voidwalkers and every other mob that was after you calm down at your death and again when you respawn: anger, chase paths, a Hisser's fuse and soldiers' last sighting are cleared, in every dimension. A test angers one mob of every kind, kills you and respawns you, and checks they all go back to idle.
- **Crafting:**
  - A crafting table opens with the cursor on the first recipe tile.
  - The inventory's crafting is now the same crafting book with 2x2 recipes only (same tiles, tabs, and craft 1 / stack / max).
  - Open it with LB/RB or the Craft button beside the inventory. Its "Inventory & 2x2 grid" button goes back to your armour and the manual grid.
- **Caves without torches:**
  - A faint cool light lets you see walls, ores and mobs a few blocks away. It fades with distance, so caves stay dark and moody, and torches are still far brighter. Corners and crevices stay darker. Fast graphics gets a stronger fill, since it has no eye adaptation.
  - Options > Video > Brightness goes from Moody (as dark as before) to Bright (Default in the middle).
  - Night vision now lights mobs too (it only lit the terrain).
  - Dropped items and the item in your hand get the same faint light, so they don't stay black on a dark cave floor.
- **Also:**
  - An igloo standing on powder snow had no floor under its entrance tunnel, so its room was unreachable.
  - Seagrass no longer stands dry in one-block-deep shallows.
  - Every volume row in Options > Audio has a help line.
  - **The world doesn't stop at a fog wall** (being tested): past the loaded terrain a coarse, hazy far landscape goes on to about 1.3 km, built from the same heights and biome colours as the map, so far volcanoes and spires stand on ground and streaming gaps show land instead of sky.
  - Trees round a Capital citadel keep their crowns: clearing the site no longer leaves leaf plates hanging in mid-air.
  - Fancy graphics uses about 37 MB less memory (the glow mask now covers only the blocks that glow).
  - A crawler's crew stays at their posts while it drives (they used to wander towards where they'd spawned), and a citadel rebuilding its wall no longer costs a few milliseconds a second.
  - Citadel patrols are made up of the soldiers already on duty again (a slip made every patrol march fresh troops out of the barracks).
  - Villagers no longer wander down into caves under their village and get stuck there.
  - Loading a different world no longer shows the previous world's far landscape for a moment.
  - Less work every frame: mobs deciding what to flee, bee hives, hoppers, sparkstone circuits and the world's streaming no longer build throwaway lists 20-60 times a second (found by an audit of the game loop).
  - Split screen: player 2's scripted test walk now wanders properly, and the split-screen checks are now part of every full test run.
- **Lost and duplicated items (found by an audit of every container screen):**
  - Wooden shelves had no slots inside: using one wrote past the end of an empty list (a crash, or quiet memory damage in the release build). Shelves already placed come back with their three slots.
  - Renaming a stack in the anvil kept one item and deleted the rest; now the whole stack is renamed.
  - Hoppers, droppers and dispensers stripped enchantments, damage, names and contents from what they moved.
  - Clicking or number-keying a whole stack into a one-item slot (enchanting, the beacon) used the whole stack up.
  - Dyeing a full shell box or bundle emptied it.
  - A chest broken by player 2, blown up, or a pack animal killed while its screen was open could be emptied twice.
  - The item on your cursor and the crafting grid are kept when you quit, switch worlds, close the anvil's on-screen keyboard, or when player 2 leaves split screen.
  - The hopper minecart's screen shows all five slots, and burning barrels or bookshelves no longer strand their items.
- **Lost on quit or reload (found by an audit of everything the save keeps):**
  - Dropped items are saved with the world, so the things you drop when you die are still there after you quit and come back. They also only age while you're near them, so they no longer vanish 5 minutes after your death however far away you are.
  - A zombie villager you were curing, an iron golem you built (it forgot you built it), and a lead in your hand no longer get lost when their area unloads or you reload.
  - Your charged rebirth anchor and your last death point are saved.
  - Docking a ship keeps the contents of chests that couldn't be placed back into the world (they drop instead of vanishing).
  - Copying the world you're playing includes changes made in the last few seconds.
- **Split screen: player 2 now plays the full game (found by an audit of what only ran for player 1):**
  - Player 2's fishing line bites, their map fills in, their gun's recoil settles, and enemy gunfire, conjurer fangs, firework blasts, potion and wyrm-breath clouds and Shellsentry bolts can hit them.
  - Player 2 can step into a Hollow rift. Mob spawners, Barkwraith hearts and citadels wake up for them, and their advancements count. Mobs that were saved when their area unloaded come back when player 2 returns there.
  - The world map, vehicle throttle and helicopter controls follow player 2's own controller (player 1's stick used to pan player 2's map). Player 2's button prompts and aim assist follow their controller.
  - Each half has its own cave darkness and eye adaptation (one player in a cave used to darken the other's daylight), and the goat horn and wind charge have a cooldown per player.
  - Player 2 can drive vehicles (their controls were reset every frame), and ships near player 2 stay awake and visible.
  - Pressure plates, tripwires and pistons notice player 2; beacons, conduits, Frost Walker, campfires and falling anvils affect them; patrol vessels, Capital frigates and homing shells engage them; map discoveries happen round them.
  - Your ender pearl, trident and arrows stay yours (player 1's pearl landing near player 2 teleported player 2). A lead stays with the player who tied it. F1 / F3 and night vision on mobs are per half.
  - Subtitles are per half: each player's arrows point from where they stand, and a sound far from one player isn't captioned on their half.
  - The tutorial tips are player 1's: shown on their half and moved on only by what they do (player 2's actions used to tick them over).
  - Still the same for both: controller rumble only on player 1's pad.
- **Smoother with many mobs and while flying (being tested):** walking mobs' collision checks look each chunk up once per column instead of once per block, and no longer allocate on every move (the bench measured a walking mob at about 5x its earlier cost). The world's per-frame update no longer walks every loaded chunk when only a few blocks changed (it cost up to 0.9 ms a frame at render distance 24).
- **Pistons and signs:** a piston that breaks a sign, item frame, banner or painting now removes it properly (its text or picture stayed floating in the air, a framed item was lost, and the spot became unmovable).
- **Sturdier against rare glitches:** if a bug ever leaves you, a mob, a ship or a dropped item at an impossible position, the game now puts it back where it last was instead of crashing (and the automatic tests report it). Before, one such value could also stop all mobs or ships from being saved.
- **Caves and mineshafts:** mineshaft tunnels and ravines no longer leave walls of standing water where they cut through flooded rock; ravines through flooded caves fill with water like the caves around them.
- **Crafting book on a TV:** the hotbar row no longer touches the bottom of the panel.
- **Inventory:** the Craft button's label no longer runs under the inventory panel, and the potion effects list keeps clear of it.
- **Closer to the classic numbers (an audit against the reference game):**
  - Explosions: each block now has its own blast resistance instead of its hardness, so a Hisser or TNT no longer craters stone, brick and deepslate builds about four times too deep. Stone and bricks hold like the reference (6), planks 3, end stone 9, obsidian is blast-proof. Primed TNT drops every block it breaks.
  - Shears cut leaves and cobwebs fast, wool at 5x and vines at 2x (they had no tool speed at all); swords cut cobwebs at 15x and plants at 1.5x but no longer speed up stone or dirt; diamond and netherite hoes are capped at the reference speed.
  - Blocks of gold, lapis and copper mine faster (hardness 3). Haste counts before the "breaks instantly" test (Haste II with Efficiency V insta-mines stone again), and Mining Fatigue III and IV are as crippling as they should be.
  - A bow only crits on a full draw (it was a 25 % roll on any shot).
  - Fortune multiplies lapis and copper like other ores; zombies' iron, carrots and potatoes drop only when you kill them (Looting helps); baby zombies drop loot, so the chicken jockey's disc can actually drop; mushroom blocks drop 0-2 mushrooms.
  - Boarlings, brutes, marauders and brigands move at their reference speed (faster), tuskers too, and conjurers are quicker on their feet.
- **Closer to the classic game, round 2 (three more audits: items and blocks, combat and survival, mob spawning):**
  - Mining and items: ember quartz and gold ores drop quartz and nuggets (they dropped the ore), bookshelves drop books, sea lanterns crystals, campfires charcoal, void chests obsidian, stained glass nothing, cocoa its beans. Only tools wear out, and not on grass or torches. Leaves stay up to 6 blocks from a log, so big trees keep their canopy. Furnaces now give experience when you take the output.
  - Fuel: only wooden things burn, at their own times (slabs half, doors and signs 10 s, bamboo and scaffolding 2.5 s, dried kelp blocks 200 s); nether wood, torches, pumpkins and beds don't. Totems, beds and cake don't stack, signs stack to 16.
  - Recipes: the lodestone takes an iron ingot, the crafter has its real pattern, packed mud is mud + wheat, chiseled stone bricks are two slabs, cobwebs can't be crafted, and any wooden slab works in composters, barrels and lecterns.
  - Farming: crops grow at the classic rate (watered farmland around them helps, rows of the same crop slow each other), beetroots slower, saplings need two growth steps, and cacti, bamboo and sweet berries actually grow now.
  - Fighting: mobs have the classic half-second of invulnerability after your hit (fists and fast spam did double damage, all three Multishot arrows landed); crits need you not to be sprinting or swimming; crossbow bolts always crit; sprint and Knockback hits push harder; switching items or swinging at air restarts the attack cooldown. Armed zombies hit with their weapon. Fire Resistance blocks fireballs (not lightning), Impaling hits water animals.
  - Survival: burning and freezing go through armour, any leather piece stops freezing, soul fire hurts more, falls hurt from just over 3 blocks, hay and honey soften landings, beds halve them, and slime blocks bounce you (sneak to stop). Swimming no longer drains hunger like sprinting. Fire Protection shortens burning; suspicious stew that feeds you gives the full amount.
  - Mobs: at most 4 monsters appear at one spot (up to 12 could), thunderstorms bring monsters out by day, swamp slimes need darkness, slime chunks differ per world, mobs far below you despawn, nightwings come about ten times less often, spiders turn hostile in the dark and keep chasing in the light, a Voidwalker needs you to look right at it, Hissers stop swelling behind walls, and villagers need a free bed to have a baby.
  - Also: iron golems and deep stalkers can't be knocked back (siegebeasts and tuskers barely); blasts hurt more on Hard and less on Easy; farmland stays moist in the rain and dries slowly; full-hunger healing slows when saturation runs low; being hit makes you a little hungrier; only weapons and tools wear when you hit with them (a bow used as a club wore out); sweep attacks reach 3 blocks.
  - A new automatic check compares break times, blast resistances, hardness, fuel, stack sizes, drops and hit invulnerability with the classic numbers on every full test run.
- **Closer to the classic game, round 3 (world mechanics, sparkstone and brewing):**
  - Beds explode in the Emberdeep and the Hollow (they set a spawn that dropped you into the overworld at Emberdeep coordinates). Sleeping takes 5 seconds, monsters near the bed (not you) stop it, a new bed replaces a rebirth anchor, and a broken bed sends you to world spawn.
  - Grass and mycelium spread onto lit dirt and die under blocks (grass never changed before). Ice you break leaves water, torches melt ice and snow, and lakes freeze from the shore in. Water flows at the classic pace.
  - Fire burns by each block's own odds: logs smoulder for a long time, leaves, wool and plants go up fast, and fire no longer dies out after a fixed time.
  - Copper ages like the classic game (faster alone, held back by younger copper next to it). Lava over soul soil beside blue ice makes basalt.
  - Experience you drop when you die lies there as green sparkles for 5 minutes and floats to you when you come back (it was lost). Bottles of enchanting drop sparkles too.
  - Circuits: target blocks give a signal when an arrow hits them (stronger near the middle), torches burn out only on really fast clocks, pistons break pumpkins and melons (melon farms work), tuning a note block plays its own instrument, weighted plates count dropped stacks once, plates stay pressed for a full second, hoppers load brewing stands properly, and comparators read composters, cake, end portal frames and rebirth anchors.
  - Lingering potions heal or harm at half strength and their cloud shrinks as it's used; the grindstone keeps the right repair cost on cursed items.
- **Closer to the classic game, round 4 (loot, trading and the inventory):**
  - Chests: a buried treasure holds one Heart of the Sea (it held about five) plus its iron, gold and gems; dungeons hold 5-10 stacks again, with music discs and horse armour; desert temples, mineshafts (rails!), igloos (a golden apple) and shipwrecks fill like the classic tables.
  - Mobs: only the smallest slimes drop slime balls, witches drop a few things instead of everything, shulkers drop at most one shell, polar bears cod or salmon, sunken drop copper rarely and only to you, and gear a zombie picked up (your armour after a death) always drops back.
  - Trading and fishing: librarians level up from enchanted-book trades, the Village Hero discount works on every trade, treasure bows and rods from fishing come worn, and boarlings can barter Soul Speed books and boots and fire resistance potions.
  - Inventory: right-click swaps different items, Q drops from the slot under the cursor (Ctrl+Q the stack), double-click gathers a stack, pick block in survival fetches the block from your inventory, shift-clicking a craft result stops when your inventory is full instead of throwing items on the floor, blaze powder goes to the brewing stand's fuel slot, furnaces and smokers only take what they can use, right-clicking a furnace output takes half, and a shield shift-clicks into your off hand.
  - Also: vines grow down, concrete powder sets where it hits water, droppers can fill furnaces, dragon's breath leaves its bottle, hay bales and other straw blocks burn, and the experience you dropped is still there after you quit and come back.
  - More inventory: dragging a stack across slots with the mouse spreads it (left: evenly, right: one each), number keys swap into fuel, armour and output slots, the stonecutter pages through more than 12 cuts (LB / RB or the arrow button, hidden when there is one page), stray arrows come tipped with Slowness, and raid captains drop the banner item.
- **Closer to the classic game, round 5 (enchantments and movement):**
  - A worn carved pumpkin or head no longer vanishes on the first hit; Glider Wings don't wear from hits but Unbreaking now protects them; Thorns wears the piece that hits back; Infinity still needs one arrow; Impaling isn't counted twice on thrown tridents; Mending's leftover experience goes on to the next item.
  - Cobwebs, sweet berry bushes and powder snow hold you (and break a fall); soul sand and honey slow you, honey halves your jump, and grown berry bushes scratch you as you push through. Using an item (eating, drawing a bow, blocking) slows you to the classic 20 %.
  - Frost Walker freezes water under every step (it froze once a second, so you sank), and its ice melts in 10-20 seconds by day instead of minutes (it stays at night).
  - Boats race on ice (about 40 blocks a second, 70 on blue ice) and don't break hitting a wall there; horses jump up to 5.3 blocks like the classic game (3.5 before); a carrot or warped fungus on a stick gives the pig or strider a speed boost; Wind Burst launches you 7-15 blocks.
- **Closer to the classic game, round 6 (mobs and animals):**
  - Tamed wolves and cats can be bred (food at full health made them sit), trusting ocelots breed, llamas can be tamed by riding, baby farm animals grow faster when fed, and chickens eat every kind of seed.
  - Cave spider and bee poison follows the difficulty (none on Easy, longer on Hard); Cinderwisps rest between volleys like the classic game (they fired every 3 s); the zombie family has 2 points of natural armour and the Blight 4; armed monsters give more experience; half-point damage on Easy and Hard rounds at random instead of always down.
- **Waterlogging:** stairs, slabs, fences, walls, panes, iron bars, ladders and lanterns can hold water. Place one in water (or pour a bucket on it) and the water stays in the block; break it and the water is left; an empty bucket or a sponge drains it. The water shows its surface in the block, you swim in it, and water in a bottom slab or stair doesn't pour down through the floor.
- **Crash-class fixes from an audit of the optimized build:** holding an explorer map far from its area could hang the game and corrupt memory every frame; respawning the Hollow Wyrm read past the end of the spike list on its last moment; a few command and signal values could overflow. Loaded crossbows remember their ammo by name, so a saved world doesn't turn a tipped arrow into something else.
- **Behind the scenes:** five rare background-thread races fixed (a patch of the old dimension on the map after a portal, a new music piece taken as finished, an audio memory leak, two benchmark counters). A pre-push check now catches a call to a function on the wrong type, the mistake that broke one build today.
- **Crashes:** soldiers idling at their posts on a level deck could crash the game (a number underflow turned their facing into NaN); `/tp` and `/setblock` refuse impossible coordinates.

### Crafting book, big landmarks, photo mode and split screen (2026-10-04 evening)
In `983ea14` (ready): the crafting book, volcanoes, canyons, Ancient Spires, landmarks on the horizon and photo mode. In `29dc7cd` and later (being tested): split-screen co-op, the faster frames and the fixes at the end of this list.

- **Crafting book.** A crafting table now opens on a book of every recipe: 40 to a page under ten tabs (Craftable Now first, then Building, Decoration, Utility & Storage, Sparkstone, Tools, Combat, Food, Transport, Materials).
  - What you can make is bright with a green rim; the rest is dimmed, or hidden with the Show filter.
  - Craft straight from a tile into your inventory: A or click makes one (hold A and it keeps going, faster and faster), Y or shift-click makes a stack, X or right-click makes as many as you can.
  - The selected tile shows the result, the ingredient grid (red where something is missing) and how many of each you have.
  - LB/RB switch tabs; LT/RT, the right stick or the mouse wheel flip pages. A full inventory stops crafting cleanly (nothing is dropped), and buckets come back.
  - Manual Grid switches to the classic 3x3 grid (its book button returns).
- **Volcanoes.** About one 1280-block area in six holds one: a cone 150-210 blocks across rising 110-170 blocks, a lava lake in the crater and lava running down channels in its flanks, in basalt, tuff and blackstone with magma round the vents.
- **Canyons.** One 1536-block area in five has a winding canyon 700-1100 blocks long and 55-90 deep, its walls stepped in terraces of banded rock, with a river along the floor.
- **Ancient Spires.** Colossal ruined stone towers, 150-175 blocks tall, on rubble mounds. A stair spirals up inside through broken floors to a chest near the top, and another chest waits by the door. `/locate great_ruin` finds one.
- **Landmarks on the horizon.** Volcanoes (with their glow and smoke plume) and spires show past the render distance, up to 2.6 km away.
- **Photo mode** (F6, or Pause > Photo Mode). A free camera with the HUD hidden while the world keeps running.
  - Fly with WASD or the left stick and look with the mouse or the right stick.
  - K (X) adds a keyframe and P (Y) plays a smooth camera path through them; Backspace (D-pad left) clears it.
  - F (RB) turns on depth of field in Fancy graphics, focused on whatever is in the middle of the view; [ and ] (D-pad) set the focus by hand and - and = (LT/RT) the blur.
  - B, Esc or F6 leaves.
- **Split-screen co-op** (being tested). Plug in a second controller and press its Menu button, or use Pause > Split Screen.
  - The screen splits top and bottom (Options > Interface > Split Screen: Side by Side keeps menus bigger on a TV). Each player has their own view, HUD, inventory, health and menus.
  - Mobs go after whoever is nearer, and the world loads round both players so you can wander apart.
  - The night skips only when both sleep. Player 2 leaves from their pause menu, and their things are saved with the world.
- **Faster frames** (being tested): the minimap, far-off mobs and the HUD cost much less CPU each frame (found by profiling).
- **Fixes (being tested):** photo mode no longer starts with the camera inside your own head; the Ancient Spire's stair reaches its top-floor chest and its floors have ghost lanterns; far-off volcanoes and spires no longer float above the haze, and a volcano's plume glows orange at night; the crafting book shows ingredient names in full and a craft flashes its tile; the Capital frigate's bridge ladder now reaches the bridge deck, its drive nozzles glow while the engines run, and the citadel hall's doorways have proper lintels.

### The Capital, vehicles and controller (2026-10-04)
- **The Capital replaces Steelhold.** Military bases are now Capital citadels: white, opulent and green.
  - An octagonal plaza podium over two terraced garden steps (hedges, flowers, birches), a grand stair with gate pylons, and a reflecting pool between birch rows.
  - An octagonal hall of white piers and tall glass (foyer, barracks, armory with racked guns, mess) with a roof garden, and a vault underneath.
  - A rounded 48-block tower of white piers and smoked glass. It has a garden terrace on its setback, a landing pad cantilevered off it, and a lit crown that marks the citadel from far off.
  - Two side towers with roof gardens and their own small landing pads, joined to the main tower by an enclosed glass skyway and an open upper bridge.
  - Old worlds keep loading: the save keys, soldier keys and loot tables are unchanged. `/locate military_base` finds a citadel.
- **Twin 42 cm turrets** guard each citadel on barbettes. They are true to scale, after WWII battleship twin turrets: a 14 x 19 m gunhouse and two 20 m barrels that traverse slowly. Their shells burst like TNT, about a 3-block crater that breaks blocks and hurts everything near. You can man one (LT / right-click).
- **The Capital frigate** replaces the old airship frigate. It is an original, sleek, 142-block warship in white armour:
  - a chined hull with a raked bow and the Capital chevron
  - an enclosed deckhouse with a pyramid mast and radar faces, and an exhaust stack
  - a bow gun, launch cells and two close-in guns
  - a hangar and a marked flight deck, and drive nozzles in the stern

  One is stationed high over every citadel and only engages near it. `/vessel frigate` summons one.
- **Capital ships are machines with crews**, not monsters with one health bar:
  - The bar lists the helm, engines, wheels and manned guns.
  - The driver steers, each gunner works their turret, and the Ironback Crawler's troops are the squad it carries down its ramp.
  - Shoot out half the crawler's wheels or its engines and it rolls to a stop. A frigate whose engines are out goes down and settles where it falls.
  - Kill the driver (or shoot the helm) and the vehicle halts or drifts. The crew fight on as soldiers.
- **Controller, Halo Infinite-style defaults:** right stick click is a quick melee and B alone crouches. Options > Controller has look sensitivity 1-10 per axis (default 3), look acceleration 0-5 (default 3), the response curve, and the centre dead zone and max input threshold for each stick.
- **Wired PowerA / third-party Xbox pads** that macOS ignores now have a built-in driver. It needs a check on your Mac: start the game from Terminal and read the `usb-gip:` lines.
- **Fast flight:** in creative, sprint while flying goes about 8x faster. V toggles it (Key Bindings > Toggle Fast Flight).
- **Riding moving vehicles:** mobs on a moving hull now walk in its frame, and you can ride moving vehicles, board and leave them while they move.

### Playtest 2 (2026-10-02 evening): your notes
- **Render distance** is on the pause menu itself, and Options opens on the Video page (it was page 3, behind the input pages). Controller players still land on the Controller page.
- **Capital ships, full size, very hostile and rare.** Two new factions, plus Steelhold. All three fight each other on sight, and the two new ones hunt you too (not on Peaceful).
  - **Stormwarden Frigate**: a 480-block flying warship.
    - Hull: a hammerhead bow over a spinal rail cannon, a hangar deck open on both flanks with two parked dropships, a bridge tower and an engine block with four great drive nozzles. Rows of lit windows show its size.
    - Weapons: 16 twin naval-gun turrets (on top, slung underneath and on the flank skirts) and missile pods. It closes in, circles you broadside, then swings its bow on to fire the rail cannon.
  - **Ironback Crawler**: a 77-block six-wheeled land dreadnought.
    - Weapons: a rail cannon, two heavy twin turrets, four autocannons and missile racks.
    - It follows the ground, rolls over trees, fences and timber, and turns back from water and cliffs.
  - **Boardable.** Fly into the frigate's hangar, or take the crawler's rear ramp; ladders lead to the bridge and the command deck, and you ride along. Crews in faction colours (Stormwarden navy, Ironback rust) hold their posts and fight boarders.
  - **Damage is block by block.** Shells tear real holes in the warship plating, and pieces cut loose from the hull break away and fall as wreckage.
  - **Sinking them:** destroy the bridge helm or most of the drive engines. A frigate sinks out of the sky and crashes; a crawler grinds to a halt, burning.
  - **Rarity:** about 3 % of 2048-block regions hold a frigate, 3 % a crawler, and 1.5 % the two already fighting. `/locate warfrigate` and `/locate crawler` find them. `/locate military_base` finds a Steelhold fortress; they are rare by design, which is why you hadn't seen one.
  - **Distance:** they show out to about 900 blocks, past the terrain's fog.
  - **Engine:** the ship engine got a capital-ship mode so a 5-million-cell hull fits the frame budget.
    - The AI moves the hull directly instead of the rigid-body solver.
    - Damage and block edits update counts in place (no full-grid rebuild).
    - Only the hit region remeshes, sections are culled one by one, and the hull is built on a worker thread.
    - In the CI test the frigate builds in about 150 ms, and a 40-second frigate-against-crawler battle averages 0.6 ms of ship work per frame.
- **Blocks chip.** Mining breaks pieces off the face you're hitting, an eighth at a time, until the block gives way. A chipped block keeps its damage, and blasts chip the blocks they can't break. Options > Video > Block Chipping switches back to the classic cracks.
- **Desert temple rebuilt:**
  - a walled hall under a stepped roof that opens to 10 blocks inside, with an oculus of daylight onto the floor pattern
  - a ring corridor with windows and urns, and a pillared forecourt
  - towers with ladders up to crenellated tops
  - a decorated treasure chamber
- **Other structures:**
  - the jungle temple has carved bands, corner pillars, a paved approach, a crowned shrine and vines
  - the swamp hut has a porch rail, corner stilts and windows
  - igloo domes no longer have a hole in the top
- **More structures rebuilt:**
  - pillager outposts: a four-storey watchtower (cobble plinth, birch walls on a dark oak frame, window slits, an open lookout, an overhanging platform under a stepped roof) with a camp round it: a cage with a captive golem, tents, a log pile and archery targets
  - shipwrecks are sailing ships half sunk in the seabed: a hold under a hatched deck, a stern cabin with the map chest, forecastle, bowsprit and masts; broken ones lose the bow and the main mast
  - end cities get end-stone trim bands, a wing off every tower floor, and a lantern spire on the roof
  - village houses vary from lot to lot (oak, plaster or birch walls under spruce or dark oak roofs; dark roofs and log walls in the taiga)
- **Capital ships, more:** both now land troops (the crawler drops its rear ramp, the frigate sends drop troops down round its target). The frigate has a wedge prow, drive nacelles and a dorsal spine, with windows only where the crew lives.
- **Capital ships, more again:** the frigate launches real dropships from its hangar; they fly to you, hover, land four soldiers, then circle with an autocannon (shoot one down and it falls and explodes). Its two parked dropships are the same craft. Warship plating chips where shells don't break it, and you can mine it piece by piece.
- **Blocks chip, more:** each piece that breaks off throws chunks of that face's texture, and a block chipped from the top lets you sink into it.
- **Steelhold fortresses** are more common now, and a 30-block lit radio mast with a red pennant marks them from far off.
- **Ocean ruins and trail ruins rebuilt:** drowned buildings with worn walls and fallen roofs; buried gravel-packed rooms with a tower top poking out of the ground. Fossils have skulls.
- **Polish from a fresh blind critic round:**
  - the Fancy renderer smooths jagged edges (it had no anti-aliasing at all)
  - clouds have shading instead of flat white slabs
  - flying ships' undersides are lit by the ground instead of black
  - the shipwreck's odd bright-blue tiles are gone (water no longer draws faces against sunken fences, slabs and stairs)
  - the jungle palette is less neon, and bamboo no longer swallows jungle temples
  - the held item no longer glows at night
  - desert temples stand wholly in the desert
  - Steelhold sentries on rooftops stand watch instead of spinning on the spot
- **Rabbits** wear their biome's coat: gold in the desert, white or black-and-white in snow, mixed elsewhere.
- **Falling water** seen from afar is tumbling water, not a bright blue mirror.
- **Polish from the blind critic:**
  - snowy spruces end in leaves (no stump at the tip)
  - the held block keeps a moonlit glow at night
  - shallow water caustics no longer glow lime
  - snow has texture again in sunlight
  - item frames start upright
- **Cacti vanishing at mid range: fixed.** Your "near and far but not mid range" pinned it down. The texture mip levels used at mid distance had their transparency pushed just under the cutoff, so the whole cactus side was dropped there. The same bug hid framed and dropped items beyond about 6 blocks (the Steelhold armory's gun racks looked empty). A new test probes every cactus from 8 to 120 blocks away; all show green now, in Fancy and Fast.

### Quality pass (2026-10-02): fidelity over features
All found by the automated checks (structure walker, behaviour sim, collision test, world-gen check, image checks, two blind critics) rather than by playing:
- **Textures at 128 px per block face** (8x the original), compressed so they take about the memory 64 px did, with mipmaps and anisotropic filtering. About 60 new high-detail materials: polished and smooth stones, sandstones, Emberdeep and Hollow stones, soils, ices, prismarine, amethyst, lava, magma, copper, iron, gold, glass, bookshelves. Distant leaves no longer dissolve into black speckles.
- **Inventory:** block icons show their real shape (stairs, slabs, fences, walls, lanterns...), and the player preview box shows your character (it was empty). Icons stay sharp on a TV.
- **Villagers** pathfind their strolls instead of walking into walls, give up on spots they can't reach instead of pushing into them, stay inside their work and meeting areas (no more spinning on the spot), and actually walk to bed at night.
- **Village houses** have their floor at the door sill (no jump to get in) and a clear doorway.
- **Structures you can walk through:** strongholds (rooms were sealed from each other; the library balcony has a ladder, the portal room a doorway), trial chambers (corridors were walled through the atrium), pillager outposts (no door, and the ladder didn't reach the roof), mansions (stairs ran into the floor above).
- **Structure mobs** no longer spawn inside walls or furniture; buried structures no longer hang over caves.
- **Cave water** no longer stands as vertical walls (18,692 such spots in the test area, now 336 at lake edges).
- **Trees:** fancy oak and jungle branches are connected (no more floating logs). Grass no longer grows on village cobblestone. Seagrass grows in meadows instead of covering every seabed.
- **Collision:** the dragon egg, brewing stand, hanging lanterns, bell, stonecutter, campfire, sculk sensor, copper golem statue and ship fittings collide like the reference (you could climb some of them like stairs).
- **Lighting:** a softer, less orange torch light; caves are no longer pitch black away from torches; no colour banding in the sky; under water your hand and held item take the water's colour.
- **Spawn:** a new world never starts you inside a tree.
- **The Blight** can't heal back from a killing blow (its star could be lost).

Also in `a0cc166`:
- **Villagers and animals climb one-block steps.** Their hop peaked at 0.8 blocks, so they bounced at every step for minutes (it was most of the "stuck villager" time). Villagers now get to bed, work and the meeting point almost every time.
- **Fancy lighting:** shaded hillsides and canopy undersides get light bounced from the sunlit ground (terrace sides were black lines from the air).
- **Every block gets 128 px detail:** blocks without a hand-made material keep their design but get real material detail (no more flat 8x8 squares on furnaces, crafting tables, doors...). New hand-made materials: grass, tall grass, ferns and seagrass as drawn blades; flowers (poppy, dandelion, daisy, tulips, allium, lily of the valley...); kelp, sugar cane, vines, lily pads, dead bushes; ice; pumpkins, melons, cactus; huge mushrooms; the Emberdeep floor (nylium, wart blocks, glowstone, shroomlight, ores, ancient debris, basalt) and sculk; diamond, emerald, lapis, redstone and coal blocks; crying obsidian, violite pillars, bedrock; chests and barrels.
- **End cities you can walk:** a step up to the door, stairs from the house into the tower, no head bump between tower floors, and bridge steps that reach the ship.
- **Mobs** stop pushing against a step, bed or workstation they can't get onto, and animals stuck in a pit rest instead of pacing.
- **Composters** are solid to walk on (you could fall in and get stuck).
- **More structures you can walk:** stronghold libraries linked only north or south (a dead-end pocket before the shelves), bastion stables (the stair stopped a block short of the rampart with both chests) and bridges (the deck had no way up), ancient-city halls (one hall's walls sealed the next one's room), mineshaft branches at another height (they met their corridor at a wall or a pit), Steelhold corner towers (guard rooms with no doorway), mansion upper floors (carpet over the room below, no floor). Strongholds sit on foundations instead of hanging over caves. Torches hang on walls instead of floating (village houses, strongholds, igloos, mineshafts).
- **Lakes and rivers** above sea level hold their water: a bank or a little waterfall where the ground drops, instead of a wall of water.
- **More 128 px materials:** doors, trapdoors, ladders, torches, rails, beds, furnaces, crafting tables, smokers, blast furnaces, the village job sites (cartography and fletching tables, loom, lectern, stonecutter, smithing table, composter, grindstone), pistons, observers, dispensers, droppers, hoppers, note blocks, lamps, targets, sea lanterns, lanterns, iron bars, spawners, TNT, slime, honey, sponges, ancient debris; crops, berry bushes, tall flowers, pink petals, cobwebs and water. Mobs get fine fur and patch detail to match.
- **Farmers** walk over to a ripe crop instead of turning away from it.
- **More 128 px materials (second batch):** saplings, Emberdeep fungi, roots and vines, bamboo, azalea, mangrove roots, cave vines, chorus plants, end rods, the dragon egg, fire and soul fire, the nether portal and the Hollow gate, gilded blackstone, reinforced deepslate, budding amethyst and clusters, dripstone, sculk shriekers, repeaters, comparators, daylight detectors, sparkstone torches; spruce leaves as needles; nicer birch bark, ice, hay, farmland furrows, podzol needles, crying obsidian tears and copper patina.
- **Tests:** the play test now opens every options page and 20 workstation and container screens; a repeated key in the settings help (a merge leftover) is removed and caught automatically from now on.
- **About 150 more 128 px materials:** enchanting tables, ender chests, cakes, Murk sensors, catalysts and veins, scaffolding, chains, campfires, rebirth anchors, jukeboxes, crafters, beacons, brewing stands, decorated pots, chiseled bookshelves, eggs, bee nests, froglights, eyeblossoms; Steelhold plating, consoles and ammo crates; ship fittings (engines, balloons, wings, wheels); every colour of stained glass, candles and shulker boxes; every copper form at every oxidation stage; glazed terracotta; coral blocks; lush-cave plants, ground plants, pumpkin faces, pillars, netherite, honeycomb.
- **Structures:** end-city tower stairs have head room, mineshaft supports leave crossings at chunk borders open, the village walking bot reaches every door (a villager shutting a door on it was the last miss).
- **World:** gravel no longer hangs over caves (623 such blocks in the test area, now 100).
- **Graphics:** Fancy shade at about 40 % of sunlight; far water no longer bands from the air; glass icons, smaller stack counts on a TV, dark effect text, descenders for g j p q y; lighter oak bark; a quieter glass frame; darker sand, layered dripstone.
- **128 px:** horizontal logs and pillars match upright ones.
- **World:** lone blocks no longer float in caves (18 in the test area, now 3).
- **Mobs:** iron golems circle their stroll targets less; villagers don't shut a door on someone standing in it.
- **Graphics:** under water the surface overhead is lit and caustics are cyan; shade under trees a little brighter; round soft stars; outlined stack counts and a readable torch icon; a crafting arrow; fog hides the world's edge; a subtle variation breaks texture tiling.

Since `a0cc166` (all in `5ec779d`):
- **128 px:** stripped logs, the remaining saplings, coral plants, frosted ice, nether wart, the newer crops, sparkstone dust and cocoa pods.
- **Menus easier to read:** help lines wrap instead of being cut off; anvil and enchanting costs on dark badges; a flame and arrows that fill in the furnace and brewing stand; a darker focus colour; the book page below its title; clearer advancement rows; a bigger map marker; a scrollbar beside long lists; keycap labels with room inside the cap (Tab no longer reads as Iab); the effect list beside the recipe-book button instead of under it; the held item's name above the air bubbles.
- **Structures:** jungle-temple steps to the chest chamber and upper floor; igloo entrances you can walk into on slopes; end-ship hatches you can walk down and bridges whose steps reach the deck (they ran under the hull); mineshaft branches that climb without a two-block step, and no support post in a crossing corridor; mansions roofed over the second floor's outer ring; village houses no longer stand wall to wall with their roofs run together.
- **Mobs:** iron golems far from home walk back instead of turning on the spot; wolves (and foxes and cats) commit to a hunt instead of switching between hunting and strolling every tick (they spun on the spot); animals no longer turn round at a pond their path goes around; villagers stand beside their workstation instead of climbing onto it; fleeing animals pick a spot and run instead of zigzagging.
- **World:** lakes a level above the sea no longer stand as a wall of water at chunk borders; underground water open to a cave spills into it as a waterfall; biome borders and snowlines fray in clumps instead of salt-and-pepper speckle; rivers meet the sea at sea level instead of in a staircase of water walls; world generation back to full speed (a lake-edge check and a cave noise had made it 2.5x slower).
- **Graphics:** softer shadow edges; thinner, fainter shoreline foam (it glowed as a white rim round pools); jungle leaves a little less neon; unlit caves slightly less pitch black; the Hollow a little brighter; thinner evening mist (it veiled the view in lavender); rain darkens grass and sand without a grey puddle film; overcast days no longer turn shade black; beaches with visible ripples; less doubled seabed under water; a smooth moon in its phases (it had a hook-shaped tail); denser, softer snowfall.
- **Menus (blind UI critic):** buttons with readable labels (the book's Sign button and the advancement tabs were too faint), the pause menu shows all ten rows, small blocks such as lanterns fill their slot icon, advancement rows with done/not-done boxes and descriptions that never shrink or vanish, enchanting offers that read "Unbreaking II +?".

Since `5ec779d`:
- **Woodland mansions** look like manors: dark log posts and pale birch panels with a window in each bay, a cobblestone sill, a lean-to over the second floor and a proper hipped roof (it was a brown box under a stepped pyramid).
- **Villages:** cave pockets right beside a house are filled (two villagers spent the whole test trapped under a house, one fell 13 blocks); villagers now reach their bed and the meeting point every time in the behaviour test (47 of 47).
- **Structures:** end-city towers with a crenellated, lamp-lit roof; purple end-ship sails; shipwrecks with a planked deck and three hatches; igloos only on level ground (one sank into a mountainside); mineshaft supports kept clear of crossings and slope changes, and water against a mineshaft corridor boarded off.
- **World:** beach sand and gravel left as a cave ceiling turn to sandstone or stone (they fell at the first touch); desert hills stay sand instead of turning to grass terraces with height.
- **Graphics:** torch, lantern and glow-berry light stays warm at the edge of its reach but whitens near the source (lush-cave stone looked like bark); the Emberdeep is a little brighter away from lava.
- **Mobs:** Steelhold troopers find real cover to reload behind (they sometimes found none).
- **Tests:** the deep-dark and biome snapshots now show the right place; the structure checker draws a map round anything it can't reach.
- **Deserts and mesas:** deserts stay sand to their edge (grass and savanna trees covered nearly half of some), and badlands come in whole regions of banded terracotta instead of scattered patches.
- **Doorways:** villagers line up with the gap beside an open door instead of clipping its panel and standing stuck in the doorway; no diagonal steps through doors.
- **Villages:** houses sit on a two-step terrace cut into the hillside (villagers got stuck in trenches beside the walls); iron golems spawn where they fit; snow edges in clumps instead of single white squares.
- **Woodland mansions:** every room has a torch and furniture (shelves, barrels, crafting tables, lecterns).
- **Caves:** underground lava pools spill into caves as lavafalls, and water against a mineshaft corridor is boarded off.
- **Falls:** being moved by a portal or teleport no longer counts as a fall (fall damage after a long teleport).
- **CI:** a fast check on every push (about 2 minutes) and the full test suite split into parallel jobs (about 21 minutes instead of 22-52).

**Gemini textures:** the API key's image quota is 0, so the textures are being generated on the Gemini website instead; the list of 66 wanted textures is in `docs/texture_requests.md` and uploads to `assets/gemini/` are imported as they arrive.

### New in the previous round (2026-10-01)
- **Mob shadows (Fancy):** mobs, and you in third person, cast real sun shadows that move with them.
- **Sign dyes:** use a dye on a sign to colour its text, a glow ink sac to make the text glow (readable at night) and an ink sac to undo the glow.
- **Two new music discs:** "Wailer's Lament" drops when a wailer is killed by its own fireball sent back, and "Hot Coop" drops from a chicken jockey's rider.
- **Advancements:** ten that could never be earned now work: Sent Back, Lifted (levitate 50 blocks), Bright Letters (glowing sign), a full rebirth anchor, first arrow and trident hits, bartering, curing a zombie villager, music in a meadow, and armour trims.
- **Spears** in every tier (wood to duskium), crafted from the tier material and two sticks in a diagonal.
  - Jab: reaches 4.5 blocks, against 3.5 for a sword.
  - Charge: hold use while running or riding. The hit grows with your closing speed. After 3 s the arm tires and the spear only shoves.
  - New enchantment **Lunge** (I–III): the jab carries you forward and costs hunger.
- **The copper set:**
  - copper tools, a copper spear and copper armour, between stone and iron
  - copper nuggets (iron, gold and copper gear smelts down to nuggets)
  - the copper torch (green flame)
  - copper lanterns, bars, chains, doors and trapdoors, in every oxidation stage (wax them to stop the ageing)
- **Lightning rods** oxidize too, and lightning striking copper scrapes it clean.
- **Cows, pigs and chickens come in climate variants:**
  - warm biomes: red long-horned cows, muddy pigs, brown hens
  - cold biomes: shaggy cows, woolly pigs, grey hens
  - warm and cold hens lay **brown and blue eggs**, and a thrown egg hatches its own kind
- **Copper and duskium horse armour** (duskium by smithing diamond horse armour).
- **Powered shelves** (up to three in a row) swap their items with your hotbar.
- **Fancy eye adaptation:** your eyes adjust to the light, so caves open up after a moment and stepping into daylight is briefly bright.
- **Terrain balance:** a bit less snow, more badlands (including wooded ones), windswept hills and stony shores, and less sparse jungle.
- **HUD:** item names no longer cover the armour row, and tips no longer cover the weapon wheel.
- **Wooden shelves** for every wood type: they hold three items on the front. Using an item swaps it with the clicked slot.
- **Dried Wailer** (8 wailer tears around soul sand): keep it next to water for about 20 minutes and it hatches a Wailerling, a baby Cloudwailer. This is the survival way to get one.
- **World map waypoints:** X, Enter or right-click at the centre of the map drops one. The minimap shows the distance and direction to the nearest.
- **Copper Chests and the Copper Golem.**
  - Copper chests come in four oxidation stages and can be waxed.
  - Put a carved pumpkin on a block of copper to build a golem.
  - The golem carries up to 16 items at a time from copper chests to the chest that already holds that item, or else to an empty chest.
  - It oxidizes over time and finally freezes into a **Copper Golem Statue**. An axe scrapes a statue back to life; honeycomb keeps a golem from ageing.
- **Vessels have Steelhold crews:** marksmen and riflemen on the Skyward Frigate, a trooper and an arc-lance ironclad on the Siege Carriage. They hold their stations and fire from the deck.
- **Ships in Fancy graphics** now get the full HDR lighting: sun shadows, glow, flash lights and fog. They darken under cover.
- **Gunfire lights up the surroundings** for an instant: muzzle flashes from your guns, soldiers and deck guns.
- **Ships and aircraft hold their throttle**, like an engine telegraph. W/S, the stick or the triggers move it; when you let go it stays; it pauses at stop. Cars and land vehicles still drive only while held.
- **Cannon barrels rise and fall** with your view. Propellers spin and wheels roll. Ships far away sleep.
- **Ship advancements:** Anchors Aweigh, Prize Crew and Brought Low.
- **World map and minimap** (M, or hold View on the controller):
  - Biome colours shaded by height.
  - Marks for Steelhold bases, villages and vessel patrols.
  - Live vehicles shown in red (hostile) or blue (yours).
- **Weapon wheel** (hold RB or Tab), aim down sights with snap and gentle aim assist (controller only), and a combat HUD: damage direction, armour wear, vehicle gauges, deck-gun reload.
- **Per-vehicle controller layouts:**
  - boats and cars: RT throttle, LT reverse
  - airships: the stick climbs
  - aircraft: pull back to climb (Options > Controller > Flight Stick flips it)
  - every vehicle: RB/LB climb and descend
- **Mannable Steelhold deck guns:** LT or right-click to take one, RT or left-click to fire both barrels.
- **Audio round 2:**
  - engines that rise with throttle, propellers, wing rush, a frigate drone, siege-carriage treads
  - streams and waterfalls, mountain and tundra wind, swamp insects
  - combat music near Steelhold garrisons and vessels
- **Graphics polish:** volumetric light shafts at half resolution (cheaper), emissive glow eases off in daylight, warmer daytime light, calmer dirt.
- **Terrain:** lakes and deltas, shrubs on open land, climate maps.
- **Fixes:**
  - **Hang:** the game could freeze every frame once subtitles were read. The audio and accessibility subtitle settings called each other forever. One setting now stores the value.
  - **Mac compile:** expressions that the M1's newer Swift couldn't type-check in time are split up (Vibrant and about 30 others). CI now fails on any expression that is slow to type-check.
  - **Lava:** lava is no longer treated as water. Inside lava you now see an orange haze.
  - **Frigate:** it holds its patrol altitude instead of sinking 6 blocks.

### Controller, TV and menus (PR #5)
- Full Xbox controller play:
  - hotplug, rumble
  - look speed / acceleration / response curve, dead zone, southpaw
  - aim assist and sticky block targeting
  - auto-sprint, hold or toggle sneak
  - button remapping
- Options rebuilt as six tabbed pages (LB/RB): Keyboard & Mouse, Controller, Video, Audio, Interface, Accessibility.
  - Key rebinding, resolution scale, display picker (laptop or TV), VSync, frame cap, safe area, couch mode.
  - Crosshair styles, colourblind-safe colours, narrator, reduced flashes, tutorial hints.
- Button glyphs everywhere, contextual prompts, an on-screen keyboard for signs and text fields.
- Worlds list: newest first, with Play, Rename, Copy and Delete (deleted worlds go to the Trash). Also Save and Quit to Title, and a loading screen.
- Creative palette with nine tabs and search.
- Button prompts follow what you're holding: **Fire / Aim / Reload** with a gun, **Steer / Climb / Leave Helm** at a ship's helm. Gun and helm controls are listed in the Controls Reference page.
- **Reload Gun** has its own key in Key Bindings (default R).
- **Voice bug notes** (Options > Interface > Bug Notes): say a bug out loud while playing.
  - Two modes: always listening, or push-to-talk (F7, or click both sticks).
  - Notes are transcribed on the Mac and saved to `~/Documents/Blocksmith/BugNotes/bug-notes.md`, with a screenshot, the audio and everything needed to reproduce it (position, seed, build...).
  - The next sessions fix bugs from that file.

### Graphics (PR #6)
- **Graphics: Fancy / Fast** (Options > Video).
- Fancy adds:
  - an HDR renderer with sun and moon shadows
  - emissive glow, specular materials
  - refractive and reflective water with caustics
  - bloom, god rays, sun haze, tone mapping and colour grading
  - a gradient sky dome, 3D clouds, soft blob shadows, swaying grass and flowers
- Both modes get:
  - a textured sun, a moon with 8 phases, twinkling stars
  - translucent rain and snow, lightning glow, blue moonlight
  - new break cracks, clumpy leaves, drifting lava hot spots
  - torch, campfire and lava particles
  - per-biome Emberdeep fog with embers, spores and ash
  - better underwater fog
  - a sleeve on the first-person arm
  - redrawn item icons
  - explosions with a light flash, smoke and debris
  - brighter moonlit Fancy nights
  - an original Hisser face
  - caves no longer glow sky blue in the distance
- **World Scale (Fancy)** (Options > Video): draws the world at 100/85/70% and scales it up, while menus and the HUD stay sharp.

### Sound and music (PR #4)
- Fully synthesized 3D audio:
  - distance, panning and occlusion through blocks
  - reverb that follows the room or cave you're in
  - an underwater muffle
- Volume per category (Options > Audio): master, music, blocks, hostile, friendly, players, ambient, weather, interface. Plus subtitles with direction arrows.
- About 600 sounds:
  - every block material
  - every mob with its own voice (young mobs higher), and mob footsteps
  - bosses
  - villager work sounds
  - all 16 note-block instruments
- Ambience: birds, owls, crickets, frogs, surf, wind, caves, the Emberdeep, the Hollow, the deep dark.
- A music composer with 14 moods (day, night, rain, underground, Emberdeep, the Hollow, boss...). Jukebox discs play in 3D.

### Mobs, villagers and raids (PR #2)
- Raids with 3/5/7 waves by difficulty, captains, siegebeast riders, Village Hero gifts. Patrols move as a group.
- Smarter movement: 8-way pathfinding, ladders, vines and scaffolding; zombies break doors on Hard.
- Spawning, despawning and mob caps follow the reference rules.
  - Per-biome packs, slimes, jockeys, animal packs in new chunks.
  - Fixed: monsters could spawn at noon.
- Behaviour:
  - Conversions: drowned, strays, zombified boarlings, frogs from tadpoles.
  - Bees with hives and honey. Voidwalkers carry blocks and dodge arrows.
  - Cats bring gifts, wolves defend you, foxes sleep by day, llamas spit, pandas have personalities, axolotls play dead.
- Villagers: schedules, gossip and reputation (prices, golem anger), golem summoning.
- New:
  - spawn eggs for every mob
  - zombie horse, Mirage Caster
  - Cloudwailer (a rideable gentle ghast, with harnesses)
  - Sunscorched Skeleton, Dust Camel
  - Nautilus (tame and ride it underwater) and Sunken Nautilus

### Finishing the game: the Hollow and the Blight (PR #3)
- Bosses no longer despawn when you're far away. Before, the Hollow Wyrm could respawn at full health and the far crystals vanished.
- **Hollow Wyrm:**
  - head hits do full damage, other hits a quarter
  - it takes off after losing 25% of its health while perched
  - it always plays its death sequence, which opens the exit portal
  - a second kill gives 500 XP
- **Egg:** the Wyrm egg teleports when hit.
- **Rifts:** the far islands get a return rift so you aren't stranded 1000 blocks out.
- **Blight:** all three heads fire, it keeps its distance and hovers, and arrows bounce off its armour.
- The scripted playthrough now goes from spawn to the credits and kills the Blight (only its furnace placement step failed, fixed in `0cdfe9a`).
- Cinder rods drop like the reference game.

### Performance (PR #1)
- Start-up fills render distance 12 in 4.6 s instead of 33.8 s (CI runner), and meshing is about 4x faster.
- Streaming keeps up at render distance 16–24; chunk memory is about 3x smaller.
- One draw call per section.
- Dynamic resolution on 4K screens, capped by Options > Video > Resolution.
- Autosave writes only changed chunks, in the background.
- Fixed a race: a mesh freed while a frame was still drawing it could be overwritten mid-draw.

### Steelhold: guns, soldiers and fortresses (PR #2, Gameplay session)
- Six original firearms:
  - rifle, chatter gun, shotgun
  - farsight rifle (scoped), skybreaker launcher (rockets), arc lance (beam)
  - crafted ammunition, magazines and reloads (**R**, or **X** on the controller)
  - aiming, recoil, spread bloom, tracers
  - first-person gun models and an ammo/scope HUD
- Steelhold soldiers in four ranks (recruit, trooper, marksman, ironclad):
  - rank armour
  - they alert each other and seek cover
  - burst fire, grenades and marksman lasers
- Deck guns that solve ballistic arcs.
- Very rare 63-block steel fortresses: basement, two floors, roof and corner gun towers.
- Weapon audio (PR #4): a sound for each gun, plus reloads, distant gunfire with echo, bullet impacts and whizzes, soldier barks and boots.

### Ships, airships and vehicles (PR #8, Engine session)
- **Turn a build into a ship:** use a **Ship Helm** and everything connected to it, up to 60 000 blocks, becomes a free-moving ship. Sneak-use the helm to dock it back onto the block grid.
- **Real physics:**
  - buoyancy, keel drag and air drag
  - engines with propellers, lift balloons with altitude hold, airfoils
  - wheels with suspension
  - collisions with terrain and other ships
- **On board:** walk, jump and build on a moving ship. Chests keep their contents and mobs ride along.
- **Pilot controls:**
  - keyboard: W/S throttle, A/D turn, Space/Ctrl climb and descend, Shift leaves
  - controller: left stick, RT/A to climb, LT to descend, B leaves
- **New blocks:** Ship Helm, Propeller, Engine, Lift Balloon, Airfoil, Wheel (all craftable).

### Realistic terrain (PR #7)
- **Biomes follow climate:**
  - temperature bands, altitude lapse, rainfall with rain shadows behind ranges
  - neighbours always make sense (no snow next to badlands)
  - borders blend gradually
- **Landforms:**
  - continents thousands of blocks wide
  - long mountain ranges with eroded, branching valleys
  - hill country and mesa terraces
  - fjords, sea cliffs and rare islands
- **Water:** rivers that flow downhill into lakes and the sea, with deltas, floodplains and levees. Basins fill into lakes, and dry basins become salt flats.

### Blocks and world (integration branch)
- New blocks:
  - resin block and bricks (with stairs, slab, wall, chiseled), resin clump
  - the bamboo planks family and mosaic
  - firefly bush, bush, leaf litter, wildflowers, dry grass, cactus flowers (all generated in the world)
- Fixed a crash when breaking a creaking heart.
- Wall torches lean against the wall.
- Underwater is water-coloured instead of a black seabed.
- Ruined portals are kept out of spawn and sit on level ground.
- Sparser Ashbark groves.

### How the workstreams were combined (playtest branch)
- **Subtitles:** there is one subtitles system. The toggles in Audio and Accessibility are the same setting, and the audio branch's captions cover every sound.
- **Options > Audio:** the controller branch's Audio tab holds the audio branch's per-category volume sliders and a test sound.
- **Resolution:** the Resolution option caps the performance branch's dynamic resolution, so the two no longer fight over the screen size.
- **Fancy graphics and performance:**
  - Fancy terrain reads chunk positions the performance branch's way. Without this, Fancy would have drawn garbled terrain.
  - Fancy's new frame path keeps the performance branch's GPU timing.
- **New mobs and soldiers:** they get voices from the audio branch's voice table.
- **Ships in Fancy graphics:** ships draw through the graphics branch's ship pipelines (full HDR lighting).
- **World Scale and Resolution:** the graphics branch's world scale used the same option ID and saved-settings key as the controller branch's Resolution. They're now two separate options.
- **Graphics on the D-pad:** the Graphics setting now changes with D-pad left/right.
- **Guns and ships:** a held gun fires even when it's pointed at a ship (unless you're piloting one). Before, the ship took every click.
- **Reload key:** reloading used a hard-coded R that also swapped the off hand. **Reload Gun** is now its own key in Key Bindings (default R); with a gun held, R reloads.
- **Render distance 24 crash:** the per-frame scratch buffer could fill up with the many mobs at render distance 24, and the first-person arm or gun was then written past its end. The buffer is now 4 MB, the world passes leave room at the end, and the first-person pass only draws when it fits.
- **Duplicate code:** a function that both the terrain and performance branches carried is kept once.
- **CI:** one run does everything: build, then a **launch smoke test** (60 s of real play through the full game loop and renderer at render distances 8, 16 and 24), benchmarks, profile, scripted playthrough, then every snapshot and harness test (`--padtest`, `--bugnotetest`, `--mobtests`, `--pathtest`, `--physicstest`, `--selftest`, terrain maps, sounds and music). A failing test no longer stops the remaining snapshots; every failure is listed and the step still fails.

