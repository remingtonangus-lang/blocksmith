# Blocksmith roadmap backlog (Remington, Oct 10 21:40; fleshed out by the overseer)

How to use this file (cloud threads and the Mac worker):
- Work top to bottom inside your lane. Claim an item by adding your thread name and the date next to it in a PR that only edits this file, or in your first PR for it. Skip items another thread has claimed.
- Each item lists Remington's intent first, then the expanded objectives. Treat both as the spec. Write your own extra objectives too (OBJECTIVES FIRST), grade everything with the DONE GATE reviewer, and only then mark the item DONE here with the PR numbers.
- Never stop while an unclaimed item remains in your lane. When your lane is empty, take the next unclaimed item from the other cloud lane that does not touch files another thread is editing.
- IP: inspiration only. No coined names from Halo, GoldenEye, Red Dead, Minecraft or real military units in player-visible text (tools/namecheck.py --coined; add new banned words to tools/coined-terms.txt). The WW2 layer uses fictional names and a fictional emblem: no swastikas, SS runes, Iron Crosses or real unit insignia (store-safe; also required for sale in Germany).
- Quest is the product: every feature must hold 72 fps on Quest 3 in its busiest scene, and be judged on QuestSim or the device.

## THE GAME'S SPINE (read first; every item serves this)
Play by the rules until you have iron, ideally diamond. Then you can take a village. Then the military bases (rare, tiered, GoldenEye-style), then the navy and its frigates, then hell, then the Reich below hell. Killing the Reich's leader beats the game. Gear tiers, tool upgrades and vehicles are the keys between stages.

## LANE A (cloud thread A): factions, bases, navy, vehicles

A1. Military bases as their own faction (separate from the Capital). Intent: castle-like fortified bases, confined to the base, tiers of bases like GoldenEye N64, very rare, naval guns and small turrets, ranked troops.
- 4+ base tiers: outpost, garrison, fortress, command fortress; each larger, rarer, better defended and better looted. Original layouts; the grey-concrete, blue-corner-light, metal-door feel of the Siberian levels is the art direction.
- Walls, gatehouses, towers, bunkers, barracks, armoury, comms room, motor pool, vault. Alarms with red lights; reinforcements arrive while the alarm is up; alarm panels can be destroyed.
- Turrets: small auto-turrets on walls and corridors, and coastal or naval guns (several calibres) at shore bases, all with readable telegraphs, line of sight and destructible states.
- Troops never leave the base footprint (leash), but chase within it and call for help.
- Each base has a map table that, once taken, reveals other bases on the map (the radar network).
- Taking a base: kill or drive out the garrison, take the command room, the flag changes; it stays yours and can be used as a home, with respawn rules documented.
- Rarity tuned so a walking player finds one in a long session; a frigate makes them reachable.

A2. Troop classes. Intent: three classes, Regular, Spec Ops and Hannibal troops (unless that name is a problem; Hannibal is historical, check the coined list anyway), each with its own armour level that gets damaged over time, its own class of guns, and rarity rising with the level.
- Armour as segmented durability (helmet, chest, legs) that visibly cracks and falls off; damaged armour lets more damage through; players can loot damaged sets and repair them.
- Weapon classes per troop: regulars with rifles and SMGs, spec ops with suppressed and scoped weapons plus grenades, Hannibal troops with heavy weapons and the best armour. Loot rarity tiers (common, fine, rare, elite) with stat ranges.
- Behaviour per class: regulars patrol and hold, spec ops flank and use stealth, Hannibal troops push and suppress. Mixed squads with an officer.
- Balance against player gear tiers; write the time-to-kill table.

A3. The navy (the frigates' faction). Intent: frigates are the UNSC-like faction with super soldiers with shields, done without infringing.
- Rename everything player-visible to our own navy (keep the Meridian name if it is already ours). Super soldiers get an original name (not Spartan) and regenerating energy shields that flare, pop and recharge after a delay; shield breakers (EMP-like weapons) as counters.
- Frigates patrol the seas, have radar, launch boarding parties and small craft, and bombard shore positions; frigates can be boarded and captured.
- A captured frigate becomes the player's fast vehicle with radar that shows bases and ships in range.

A4. Vehicles that fly, and the crawler. Intent: ways to make vehicles that fly; the crawler needs to be perfected.
- Finish the free-moving block structures engine (old PR 8) so players can build aircraft from blocks: engines, lift surfaces, control seat; weight and thrust matter. Plus at least one craftable ready-made flyer for players who don't want to build.
- VR comfort for flight: cockpit frame, vignette, horizon lock option, snap or smooth turning.
- The crawler: smooth movement on all terrain, no clipping or jitter, sensible speed and weapons, boarding and exiting in VR, damage states, repair.
- Vehicles persist in saves and are found where you left them.

A5. Radar and discovery. Bases reveal other bases; frigates have radar; a map and compass that show discovered sites, with fog of war.

## LANE B (cloud thread B): progression, law, hunting, hell, the Reich

B1. Sheriff's six-iron and the iron rule. [DONE: Lane B thread, 2026-10-11, PR #28; docs/status/six-iron.md] Intent: the sheriff carries a six-shooter that one-shots you in anything below iron armour, is a middle ground in iron, and hardly hurts diamond and above. You play by the rules until you have diamond or at least iron, then you can take a village.
- Every sheriff carries the six-iron (replaces the 5 percent gun chance). Readable draw, warning shot, fair reaction time; deadly at range in VR, dodgeable.
- Damage tuned per armour tier and documented: leather or none = death in one shot, iron = several shots, diamond and up = chip damage.
- Taking a village: defeat the sheriff and deputies; the town surrenders, becomes yours (trade discounts, tribute, a bed and storage), honour consequences, and nearby towns react.

B2. Townsfolk variety. [DONE: Lane B thread, 2026-10-11, PR #32; docs/status/townsfolk-variety.md] Intent: villager attack rates, health and speed vary.
- Per-person stats rolled from role and age: farmers weak and slow, blacksmiths strong, deputies fast and armed. Visible cues (build, tools) so players can read them.

B3. Hunting like RDR2. [DONE: Lane B thread, 2026-10-11, PR #35; docs/status/hunting.md] Intent: hunting with pelts and the rest.
- Animal quality (poor, good, perfect) shown when studying an animal; clean kills with the right weapon keep perfect pelts; skinning animation; pelts, meat, hides and trophies.
- A trapper or butcher in towns buys pelts by quality; crafted outfits, saddles and satchels from pelts (bigger inventory).
- Legendary animals with map clues and unique pelts. Fishing with species, sizes and a fishing minigame that works in VR.

B4. Countries that give minerals. [CLAIMED: Lane B thread, 2026-10-11] Intent: there should be countries too that give minerals.
- The world is divided into a handful of countries with borders, flags, capitals and towns, each rich in particular minerals. They trade, tax and pay tribute; you can ally with one, raid another, or take it over through its capital. Border posts, customs and wars between countries that change the map over time.

B5. Enchantments become tool upgrades. Intent: enchanting is too similar to the original; make it tool upgrades that still need experience.
- A workbench upgrade tree per tool and weapon (sharper edge, reinforced head, balanced grip, scopes, extended mags) paid with experience plus materials; visible changes on the model; old enchanted items convert in saves.

B6. Hell's own mobs. Intent: hell needs its own mobs, including a dark burgundy knight class. Hell comes after mastering the bases and getting upgrades.
- A knight order in dark burgundy armour: squire, knight, champion and a commander mini-boss, with shields, parries and charges that suit VR melee. Plus 3+ other original hell mobs with distinct roles (flying, swarm, ranged).
- Gate: hell is reachable only with base-tier gear (a key or charge looted from command fortresses), so the order is clear.

B7. The Reich below hell. Intent: below hell is Nazi Germany: tiger tanks, black everything, red flags with black, replicas of German weapons from the time; it should be clear what we are going for. You kill them and you have beaten the game.
- Build on the Ashguard and the Ash Vault (PR 22 and the gap pass). Black uniforms and vehicles, red banners with a black fictional emblem, heavy tanks in the style of the period, half-tracks, artillery, and period-style rifles, SMGs and MGs under fictional names.
- A final campaign: fortified lines, a leader in a final bunker, a big last battle and an ending.
- Store-safe as stated at the top.

## LANE M (the Mac worker; needs the device or the Mac)

M1. Polygon terrain test. Intent: a test of the polygon idea to see how it turns out. Build on the smooth-terrain prototype (task 25b3) and make it playable as an option on Quest so Remington can walk around in it; screenshots and fps compared with blocks.
M2. (moved to lane C as L2)
M3. Device feel for the lanes above: flying, crawler, frigate radar and VR melee against knights, checked on the Quest.

## LANE C (optional third cloud thread): looks, redstone, polish
Moved from the Mac queue on Oct 10 21:52 (Quest is the product; judge on QuestSim, Mac renderer only where shared code forces it).

L1. Look upgrade. [DONE: Lane C thread, 2026-10-11, PRs #26 (sky), #29 (Powderwight), #34 (trees), #36 (mob animation), and the golden before/after PR; docs/status/look-upgrade.md. Headset fps proof stays on lane M's device checklist.]
LOOK UPGRADE (not texture style - that waits for Remington's pick): 1) a realistic sky with real-looking clouds (cheap: a few layers/billboards or a 2D cloud texture scrolled, no expensive volumetrics on Quest). 2) Redesign mob and animal models so they stop looking fake/cheap: better proportions, silhouettes, animation; 3) replace the creeper with an original mob that fills its role (keep save compatibility). 4) Tree shapes: more natural, varied silhouettes. Keep compute flat or lower. Blocksmith rules: branch claude/quest-port (shared gameplay also to claude/blocksmith-playtest); read docs/status/quest-port.md first; his saved world must keep loading (backup + migration test). Commit after each item. Verify with ./build.sh fast and --questbugs/QuestSim checks (judge downscaled screenshots yourself). Ship: push, ONE blocking wait per Quest CI run, confirm the APK on quest-dist, install if adb shows the Quest, add notes to quest-port.md. Bar: store quality. Remington gives you wide leeway: if you see anything else that would make the game better without costing more compute, do it.

EXPANDED OBJECTIVES (overseer, 10-10 14:45; meet these as well as the items above):
SKY: day gradient that shifts with sun height; real sunrise/sunset colours; moon with phases and stars at night; 2-3 cloud layers at different speeds following one wind direction; overcast and rain skies darken the world and the clouds; storms with distant lightning flashes; the sky matches each biome (hazier in desert, cold blue in snow); cheap on Quest (measure).
MOBS AND ANIMALS: every mob gets walk, run, idle, attack, hurt and death animations (no sideways flip deaths); heads track the player; hurt flash and knockback that read clearly; sounds matched to the new looks; size/colour variants and babies for animals; hostile silhouettes readable at night at 20 blocks; a before/after screenshot sheet for every mob.
CREEPER REPLACEMENT: a design note (name, look, behaviour, counterplay, drops, advancement); a clear telegraph (sound and visual) before it detonates or attacks; it fills the same gameplay role (punishes inattention, damages builds) but is original; old saves convert existing creepers.
TREES: at least 4 shapes per species with branches and root flare; leaf colour varies with biome; occasional fallen logs, stumps and dead trees; big rare old trees; far-LOD silhouettes match the new shapes; no floating leaves after generation changes.
GENERAL: golden screenshot set before and after (day, night, rain, 3 biomes); fps measured on the Quest build before and after with no regression; list anything else you improved under the 'wide leeway' rule.

NOTE (10-10 21:26): Quest renderer first. Do the sky, mobs, creeper replacement and trees in shared code + the Quest renderer; touch the Mac Metal renderer only where shared code forces it.

L2. Redstone. CLAIMED: Lane C thread, 2026-10-11 (the Sparkstone Workshop world).
REDSTONE: Build a redstone test world with standard circuits (clocks, T flip-flops, piston doors, item sorters, observers, comparator subtraction) and make every one behave like the genre reference; automate the check.

L3. Oct 10 AM playtest flesh-out list (skip towns items; lane B owns them).
FLESH-OUT of the Oct 10 AM playtest task (Remington, 10-10 14:45). That task got his literal list; these are the extra objectives (written by the overseer) it must also meet. Read what 25b4z already shipped (git log, docs/playtests/2026-10-10/voice-notes-status.md), skip what is truly MET, build the rest. Grade everything at the end with the DONE GATE reviewer.
TEXTURES/GROUND
- Before/after captures from the Quest build at 1, 4 and 16 blocks for stone, chest, grass, ores, planks; put them in the status doc.
- No shimmering or moire at distance (tune mip bias per material), no blur up close; consistent texel density across all blocks.
- Ores readable at 10+ blocks; every ore distinct by colour and shape, not just tint.
- Grass: 3-4 top variants with random rotation so tiling never shows, biome tint, a proper side overhang; grass side reads at a glance.
- Flower bushes: 2-3 variants, cheap wind sway, rustle sound when walked through.
RENDER DISTANCE / PERF
- Hysteresis: auto-drop only after sustained low fps, auto-recover after sustained headroom; never ratchet down forever.
- An optional perf overlay (fps, frame ms, render distance, chunk jobs) in settings.
- A 20-minute soak in the busiest town and the taiga on the Quest build with logged min/avg fps; list the top 3 frame-time costs and what was done about each.
WORLD GEN
- Capitals: a minimum distance from spawn and from each other, checked over 50 seeds with the numbers in the doc; spawn always gets a natural start area.
- Volcanoes: foothills that blend (gradient of tuff/ash/basalt into the biome), a cheap smoke plume visible far away, lava glow at night, a correct far-LOD silhouette, rare small eruptions with particles and rumble.
- Ruined portals: rare, each one with loot worth the detour and a reason to exist.
TOWNS
- Townsfolk have names shown when looked at, greet by time of day, have work and sleep hours; shops close at night with a sign.
- Wallet: animated gain/loss with a coin sound; prices and the emerald exchange rate shown in every shop UI.
- Theft uses line of sight: unseen theft found later costs less; witnesses run to the sheriff; a bounty that fades over time or can be paid.
- Sheriff: patrol routes, warns first, can fine or arrest instead of always fighting; despawns/respawns sensibly; never kills the player over a tiny theft.
- Voice lines: at least 8 per role per situation (greet, trade, warn, angry, flee, goodbye), never the same line twice in a row, spatial audio with falloff, optional subtitles.
- Old-save migration test: a pre-towns save loads with every villager converted.
CAMPS
- At least 5 camp types (hunter, trader, bandit, deserter, surveyor), each with a campfire (light, smoke, cooking), a tent or lean-to, loot that fits, and an owner; some friendly (trade, rest), some hostile.
- Rarity tuned so you find one every 10-15 minutes of travel; respawn rules documented.
SWING MODE / RECLINED MODE
- First-use tutorial prompt for each mode; mode switch reachable in VR without taking the headset off.
- Blade trail, a tiny hit-stop on contact, damage scaled by swing speed, distinct haptics for flesh, armour and stone.
- Friendly-fire guard: swinging near villagers, pets or your horse never hurts them unless you deliberately attack.
- Enemy wind-ups are telegraphed (pose plus sound) so physical dodging and blocking are fair; sword-on-weapon contact can parry.
- Reclined mode: a soft aim-assist cone, seated height calibration, comfort defaults (snap turn, vignette).
BOW
- Nock animation, draw creak, string vibration and sound on release, draw strength sets speed and damage, arrows can be picked up; works left- and right-handed; crossbow uses the same hand logic.
Finish: update voice-notes-status.md with evidence per note, ship one Quest build (tools/quest-local.sh, install if adb sees the Quest), DONE GATE.

NOTE (10-10 21:20): TOWNS items in this list now belong to the cloud lane (it shipped towns/honour/sheriff in PRs #19-#20); skip them here.

## OVERSEER'S FEATURES (Claude's list, trimmed by Remington Oct 10 21:52; lane in brackets)
C1. [B] Railways (procedural, rare): rail lines generated with the world, linking several villages and towns, so finding one is a big find: it is fast travel to many places. Generation must be robust: lines follow terrain with cuttings, bridges and tunnels, stations only at real villages, never through structures, never floating; a worldgen check over 50 seeds proves it. Steam trains run the lines on a timetable; you can ride, and RDR-style train robberies (stop the train, crack the strongbox, outrun the posse) carry honour and bounty fallout. Armoured trains in the Ash Vault.
C2. [A] The living war map, procedural only: factions hold generated territory and front lines shift over in-game weeks from simulation, not hand-placed events; battles happen without you; your actions tip them; a war table in captured bases shows it. If it can't be made fully procedural and stable, drop it and say so.
C3. [B] Your own nation: villages and bases you take become provinces; settlers arrive, build and farm; you set taxes and laws; they need defending; your flag on the map; a capital you design.
C4. [B] On-device AI villagers (placeholder): define a clean interface (VillagerMind) that a small language model can drive for dialogue, opinions and daily choices, running on the device's neural engine or NPU when available (Apple Foundation Models on Mac, the Quest's NPU later), with today's scripted behaviour as the fallback. Ship only the interface, the scripted implementation and a stub; no model yet.
C5. [M] Physical VR crafting and guns: hammering blades on the anvil, sharpening, fitting gun parts, physical reloads (drop the mag, seat a new one, rack the slide), holstering on the body; always with a seated or Reclined shortcut.
C6. [A] Radio spoofing: at a military base's radio room (or a Capital comms post), pose as the garrison and request help. Other bases of the same faction actually send it: supply drops or a truck convoy (military), a frigate strike on a map grid (Capital or navy). It only works for a while: a suspicion meter rises with each request and with odd requests; when they find out, the faction goes on alert, sends a hunter squad and stops answering that radio.
C7. [A] Airships and a sky layer: the Capital's armoured airships patrol high above; board one with a flyer or a grapple; a small cloud-island layer mirroring the Deep below, with its own loot.
C8. [A] Submarines, wrecks and mines: build or capture a submarine; sunken warships and treasure wrecks to dive; naval mines and torpedoes; the navy hunts you with sonar.
C9. [B] Seasons: spring to winter over in-game weeks; lakes freeze, snow on trees, crops by season, animals migrate, hunting seasons, town festivals.
C10. [B] Legendary weapons and armour: named one-off items from bosses, legendary animals and command fortresses, each with a story, a look and a unique perk; a gallery in your base.
C11. [B] Jobs and contracts: notice boards in towns, bases and countries with procedural jobs (escort, delivery, bounty, clear a camp, defend a town) paying money and reputation.
C12. [B] Mining expeditions replace genre-style abandoned mineshafts: real working mines attached to big villages (mining towns), with dynamite, mine carts and rail, supports and cave-ins, gas pockets and lamps, miners, and deep veins worth an expedition.
C13. [B] Village size variety: village sizes span hamlet, village, town, large town and city, with rarity scaling exponentially (each size roughly 3 to 4 times rarer than the one below). Bigger places get more shops, a mine, a rail station if a line passes, more law. Check the size histogram over 50 seeds.
C14. [A+B, last] Two-player co-op on Quest: a friend joins your world (host-authoritative), shares horses, vehicles and robberies. The biggest sales driver on Quest and the biggest job, so it goes last, after the single-player game is store-ready.

## FOR THE TOWNS LANE (from the Mac worker, task 25b4zxxxx, 2026-10-11)
T1. Hostile townsfolk melee reaches the player's real body: Townsfolk.swift ~line 238 tests the centre distance
    (`dist < w.reach + 0.3`, feet height window 2.5) so an angry townsperson can't hit a player on a 2-block step and
    can hit one standing on a pillar. Monsters now use `Game.meleeGap(_:)` (VRMelee.swift: feet to headset, only the part
    level with the mob); use the same helper for townsfolk swings. Check: `--swingtest` covers the monster side.

## SMALLER IDEAS (take when a lane is empty)
O1. Outposts and liberation (Far Cry style): small enemy camps on the map that you clear to unlock fast travel and shops.
O2. Hired companions: pay or recruit townsfolk and troops to follow and fight; gear them with your looted armour.
O3. Faction reputation: towns, the Capital, the military, the navy and the countries each remember you; bounties and allies follow.
O4. Armour and weapon repair benches and a gunsmith tier, so damaged loot matters.
O5. Raids on your bases and towns by factions you have angered, with defences you can build (walls, turrets you captured).
O6. Trophy room and museum: legendary pelts, boss trophies, captured flags, displayed in your base.
O7. Weather that matters: storms ground flyers, fog helps stealth, snow slows troops.
O8. Wanted posters and bounty hunters that track you across the map.

## Inspiration (feel and mechanics only)
GoldenEye 007 (base tiers, alarms, stealth), Red Dead Redemption 2 (law, honour, hunting, towns, horses), Halo (shields, vehicles, frigates), Far Cry (outposts), Mount and Blade (taking villages, factions), Valheim and Terraria (boss-gated progression), Metal Gear Solid (alerts and stealth), Wolfenstein (the final layer), Sea of Thieves (naval play).
