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

B1. Sheriff's six-iron and the iron rule. Intent: the sheriff carries a six-shooter that one-shots you in anything below iron armour, is a middle ground in iron, and hardly hurts diamond and above. You play by the rules until you have diamond or at least iron, then you can take a village.
- Every sheriff carries the six-iron (replaces the 5 percent gun chance). Readable draw, warning shot, fair reaction time; deadly at range in VR, dodgeable.
- Damage tuned per armour tier and documented: leather or none = death in one shot, iron = several shots, diamond and up = chip damage.
- Taking a village: defeat the sheriff and deputies; the town surrenders, becomes yours (trade discounts, tribute, a bed and storage), honour consequences, and nearby towns react.

B2. Townsfolk variety. Intent: villager attack rates, health and speed vary.
- Per-person stats rolled from role and age: farmers weak and slow, blacksmiths strong, deputies fast and armed. Visible cues (build, tools) so players can read them.

B3. Hunting like RDR2. Intent: hunting with pelts and the rest.
- Animal quality (poor, good, perfect) shown when studying an animal; clean kills with the right weapon keep perfect pelts; skinning animation; pelts, meat, hides and trophies.
- A trapper or butcher in towns buys pelts by quality; crafted outfits, saddles and satchels from pelts (bigger inventory).
- Legendary animals with map clues and unique pelts. Fishing with species, sizes and a fishing minigame that works in VR.

B4. Countries that give minerals. Intent: there should be countries too that give minerals.
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
M2. Redstone works well. Full logic parity with the genre reference: dust, repeaters, comparators, pistons, observers, hoppers; a test world with standard circuits that all pass.
M3. Device feel for the lanes above: flying, crawler, frigate radar and VR melee against knights, checked on the Quest.

## OVERSEER'S FEATURES (Claude's own list, equal weight to Remington's; lane in brackets)
C1. [B] Railways and train robberies: craftable track, steam locomotives and carriages; scheduled passenger and cargo trains between towns and countries; RDR-style hold-ups (stop the train, crack the strongbox, escape the posse) with honour and bounty fallout; armoured trains in the Ash Vault.
C2. [B] Heists: bank and payroll heists in towns with scouting, a plan (loud or quiet), a VR safe-crack and lock-pick minigame, getaway on horseback, wanted level by witnesses.
C3. [A] Stealth and disguises (GoldenEye and Metal Gear feel): light and noise meters, guard sight cones and suspicion states, silent VR takedowns, wearing a troop's uniform to walk through lower base tiers until a higher rank looks closely, cameras and alarm panels.
C4. [A] Siege warfare: siege engines (ram, trebuchet, the existing siege carriage, mortars) to crack castle bases and walled towns; walls with damage states; defenders on ramparts; you can also be besieged.
C5. [A] The living war map: the Capital, the military, the navy, the countries and the Reich hold territory and push front lines over in-game weeks; battles happen without you; your actions tip them; a war table in captured bases shows it.
C6. [B] Your own nation: villages and bases you take become provinces; settlers arrive, build and farm; you set taxes and laws; they need defending; your flag flies on the map; a capital you design.
C7. [B] Your gang camp (RDR2 camp): recruitable members with names and skills, a camp ledger, upgrades (bigger tents, a cook, an armoury), members who go on jobs and bring loot or trouble, camp morale.
C8. [M] Physical VR crafting: hammering blades on the anvil, sharpening, fitting gun parts, physical reloads (drop the mag, seat a new one, rack the slide), holstering on the body; always with a seated or Reclined shortcut.
C9. [A] Field radio and support: once you hold a base, call in artillery, supply drops or a frigate bombardment on a map grid, with cooldowns and cost; enemies can jam it.
C10. [A] Airships and a sky layer: the Capital's armoured airships as mobile fortresses patrolling high above; board one with a flyer or a grapple; a small cloud-island layer mirroring the Deep below, with its own loot.
C11. [A] Submarines, wrecks and mines: build or capture a submarine; sunken warships and treasure wrecks to dive; naval mines and torpedoes; the navy hunts you with sonar.
C12. [B] Seasons: spring, summer, autumn, winter over in-game weeks; lakes freeze, snow on trees, crops by season, animals migrate, hunting seasons, festivals in towns.
C13. [B] Legendary weapons and armour: named one-off items from bosses, legendary animals and command fortresses, each with a story, a look and a unique perk; a gallery in your base.
C14. [B] Jobs and contracts: notice boards in towns, bases and countries offering procedural jobs (escort, delivery, bounty, clear a camp, defend a town) that pay money and reputation and pull you around the world.
C15. [A] Mining expeditions: dynamite, mine carts and rail inside mines, supports and cave-ins, gas pockets and lamps; deep ore veins worth an expedition.
C16. [A+B, last] Co-op for two players on Quest: a friend joins your world (host-authoritative), shares horses, vehicles and heists. The biggest sales driver on Quest, and the biggest job, so it goes last, after the single-player game is store-ready.

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
