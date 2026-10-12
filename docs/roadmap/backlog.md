# Blocksmith roadmap backlog (Remington, Oct 10 21:40; fleshed out by the overseer)

How to use this file (cloud threads and the Mac worker):
- Work top to bottom inside your lane. Claim an item by adding your thread name and the date next to it in a PR that only edits this file, or in your first PR for it. Skip items another thread has claimed.
- Each item lists Remington's intent first, then the expanded objectives. Treat both as the spec. Write your own extra objectives too (OBJECTIVES FIRST), grade everything with the DONE GATE reviewer, and only then mark the item DONE here with the PR numbers.
- Never stop while an unclaimed item remains in your lane. When your lane is empty, take the next unclaimed item from the other cloud lane that does not touch files another thread is editing.
- IP: inspiration only. No coined names from Halo, GoldenEye, Red Dead, Minecraft or real military units in player-visible text (tools/namecheck.py --coined; add new banned words to tools/coined-terms.txt). The WW2 layer uses fictional names and a fictional emblem: no swastikas, SS runes, Iron Crosses or real unit insignia (store-safe; also required for sale in Germany).
- Quest is the product: every feature must hold 72 fps on Quest 3 in its busiest scene, and be judged on QuestSim or the device.

## PLAYTEST Oct 11 AM (P1-P15): TOP PRIORITY, take these before any other G item
He played build 0.129 (04d1296) on the Quest; later merges may already fix some, so check each against claude/quest-port first and only fix what is still broken. His 241 spoken notes, each with game state and a Mac repro line: docs/playtests/2026-10-11/voice-notes.md. Fix the class of each problem, not the instance; Quest first. Record each note status in docs/playtests/2026-10-11/voice-notes-status.md. Checks that need the real headset go to docs/status/device-checklist.md (the Mac overseer runs them).
P1. Water/ice: ice in water shows the water running down its sides (seam/flow faces visible).
P2. Sugarcane does not look right when stacked; make stacked cane seamless.
P3. Dripstone is still upside down.
P4. Trees are visible through the ground when 40 blocks underground (culling/LOD bug).
P5. Dropped item stacks look like a single item; make stacks read as stacks.
P6. Sign text runs off the signs.
P7. Iron ore is too hard to see (titanium reads fine); raise iron ore texture contrast.
P8. The distant volcano still looked wrong on the Quest build he played; verify the far-view fix (audit gap 6) reaches the Quest renderer.
P9. Inventory (hold Y) opens a few hundred ms too slowly; cut the hold time or open immediately.
P10. Crafting grid cells are too small for a controller pointer (misclicks); make the targets 5x5-grid sized and test with the controller pointer.
P11. Show the player height (Y) next to X and Z.
P12. Hunger drains too fast: drain mainly from sprinting, attacking and jumping, very little from walking.
P13. VR melee: hits register only for top-down or side-to-side swings, never bottom-up, and the sword sometimes passes through an enemy with no damage. Fix blade-vs-hitbox for every swing direction; raise the attack rate a bit.
P14. Footsteps still sound like walking through mud; one unidentified sound plays that should be improved or removed (find it from the note timestamps).
P15. Frame rate dropped to about 22 fps in a survival world at high render distance; find the scene from the notes state lines and fix the cause.
Praised, keep: performance at 24 chunks, removing the big water buckets, cave mob density, jungle, hell blocks, the Powderwight look, raw titanium.

## PLAYTEST Oct 11 midday (P16-P38): same priority as P1-P15
He played build 3222ab3d (12:40-13:31); notes 12:40 onward in docs/playtests/2026-10-11/voice-notes.md (with repro lines). Several repeat P items because no P fix had shipped yet; check against claude/quest-port first.
P16. VR melee (extends P13): swings at targets below the player never hit; only one hit registers per few hundred ms when swinging fast (allow several hits per second); damage should scale with swing speed; leave a visible hit mark (red streak) on what you hit.
P17. The held sword is see-through edge-on and looks like five pieces stitched together: give held tools real thickness and a clean single mesh.
P18. Lava next to him did not spill/flow toward him (12:42); water falling one block looks wrong from the side (with P1).
P19. Minecraft lookalike content: a deep-dark-style cave with a warden-like mob appeared, which he never asked for (12:45-12:48). Audit for content copied from Minecraft (warden, deep dark, end city and similar) and replace it with original designs or remove it (IP rule).
P20. Teleported through a wall of blocks once (12:48, collision/rubber-band bug).
P21. Unclear objects: something at 12:52 he could not identify (make its purpose obvious) and an eye-like item/creature at 13:03 that looks poor; find them from the repro lines.
P22. Coral underwater looks low effort; rework coral and reef looks.
P23. Capital base soldiers must not respawn once killed, so a base or city can be cleared for good.
P24. Villages need things to steal: chests in houses, and a register/strongbox chest behind the general store counter; chest placement in buildings must make sense, and buildings should have a readable purpose instead of filler.
P25. Input bug: the left grip / a stuck trigger auto-placed blocks (a crafting table) repeatedly (12:56-12:57).
P26. Horses: taming is undiscoverable (no pat prompt; hand-only patting unexplained); bonding levels rise far too fast (aim for RDR2-like riding time); verify speed tiers (his horse felt very slow); a way to call your horse (e.g. hold A to whistle); a spare horse walks into him (follow to near, not onto, the player); a horse he attacked would not die and froze in place; some hits on a horse do no damage; the running animation looks wrong. Keep: the horse rearing/falling backwards.
P27. Hostile mobs should not be out in daylight; follow the day/night cycle.
P28. Crafting shows only that you can make an item; show how many (e.g. 6 chests).
P29. General store: an empty map for 6 dollars must be a treasure map or cost much less; check prices (titanium ingot 5 dollars felt cheap); the pistol sold by the sheriff looks wrong.
P30. Titanium armour vs guns: he lost no health at all under gunfire; armour should take heavy durability damage from bullets (that part is good) but some damage must still get through; swords should do little to it. A shock weapon held by enemies looks far more powerful in the inventory than it is; match its look to its strength.
P31. Hostages tell him to put his weapon away while held hostage by the soldiers he is fighting; fix that dialogue (hands-up is good).
P32. Guns: the reload button still does not work; guns are not accurate enough; rounds land higher than the sights; the Farsight rifle cannot aim down its scope.
P33. Capital assault: entering a capital base should trigger an alarm and send reinforcements from the capital tower; it should be genuinely hard. Tower interiors: denser, narrow corridors, less open space (inspired by the N64 Siberia facility feel, all original).
P34. Capital special food: more technologically advanced rations unique to the capital.
P35. Some building pillars float above the ground (foundations must reach the terrain).
P36. The radar blocks in capital bases should do something (e.g. reveal patrols or other bases when used).
P37. A sheriff office/jail rework (with G14): the current one looks poor.
P38. Hunger still drains too fast when sprinting (same as P12).
Praised, keep: wind sounds (perfect), terrain generation improved, titanium ingot look, helicopters, armour shattering under fire, hostages raising hands, guns badly damaging titanium armour.

## PLAYTEST Oct 11 evening (P39-P67): same priority as P1-P38
Played build bfb3f146 18:30-19:16; notes with repro lines in docs/playtests/2026-10-11/voice-notes.md (after 18:30). Check each against claude/quest-port first.
P39. Lava: he reverses the earlier ask; he needs lava. Either keep cave-floor lava pools or replace them with plenty of single lava sources so lava stays easy to collect.
P40. Ammo economy: store rifle rounds are far too cheap; the capital uses its own rounds that cannot be bought (only looted from capital bases); capital weapons only from the capital or its town.
P41. Stairs in Elk Gulch sit in the way and look wrong (fix stair placement in town buildings).
P42. Potions: better visuals; the doctor must not sell every potion (some rare); design an original potion set of our own.
P43. Guns hit exactly where the sights point (perfect accuracy, except shotguns). This supersedes the accuracy part of P32.
P44. World rarity pass: iron ore and coal too common; less surface water; structures much rarer: capital towns and military bases about one per 4000x4000 blocks (woodland-mansion rarity); the world should look normal almost everywhere.
P45. Getting guns was too easy while wearing titanium armour (balance with P30).
P46. [feature] Endgame: after the player defeats the Reich below hell and returns to the surface, hordes from every faction converge; the player must defeat them all to roam the surface freely.
P47. Dropped gunpowder renders upside down.
P48. Military bases get a small town beside them, like the capital town: the player can shop there undetected, but the guards are on edge.
P49. Horses: longer stamina; gallop speed similar to RDR2; the horse cannot climb from water onto land at equal height (regression); allow a jump while swimming; riding into leaves turns the screen black (camera clipping); let horses squeeze through tight gaps (hesitating in dense trees is fine); hooves on capital brick sound cheap; mounting is blocked while holding a gun; a mob hit makes the horse rear and locks the player (a creeper killed his horse); if your horse dies it falls over and the saddle can be recovered; zombie hits stun the rider too much.
P50. What each place is known for should be knowledge earned with high honour in a village, not shown up front.
P51. [feature] Roads linking villages, with occasional riders you can rob (loot their satchel); a nearby village sends a hunting party; at low honour, bounty hunters with guns come for you; if they kill you, the bounty is paid off and you are left with no money.
P52. He wants to try the polygon test world (M1) on the Quest: make sure it is reachable from the Quest menu and tell him where.
P53. HUD: make it translucent until the grips are used; remove the button-hint overlays (or make them fade after the first hours / an option).
P54. [design] Vehicles: either craft a tank from a ludicrous amount of materials or build preset vehicles at a special vehicle table; he is undecided, so prototype one and note the trade-off.
P55. Mob variety: individual mobs vary widely in speed, damage, toughness and (skeletons) accuracy.
P56. VR reload: manual reload; grab a magazine from the hip and insert it into the gun.
P57. Bodies stay on the ground in an area until the player leaves and returns.
P58. Townsfolk lines ignore the time of day (the kitchen-closing line played far too late at night).
P59. Sleeping in (or taking) someone else bed costs honour.
P60. Teleporting mobs snap onto the player and are hard to hit; entities must not overlap each other (also check the mob for Minecraft likeness, with P19).
P61. Inventory: hold A on a stack and release to choose how many to take, instead of the current pick-up behaviour.
P62. Town buildings are packed too tightly; widen the spacing between buildings and paths.
P63. Gunfire in a town should bring people to investigate (noise response).
P64. Death and damage: do not lose experience on death; unarmoured hits should hurt more; more townsfolk should carry guns.
P65. Dropships and crawlers clip through capital buildings; they should collide and break blocks instead.
P66. Drop craft: the pilot can hardly see while driving (camera/visibility); it should need fuel.
P67. Sheriff jobs: the map marker for him works (keep).
Praised, keep: guns against enemies, the Hunter Map, the Elk Gulch welcome, the horse staying near, the potion look improving.

## MOVED FROM THE MAC (Oct 11): take after the P and G items
Q1. Finish the done audit (Mac task 25b6, unfinished): complete docs/status/done-audit.md for every task marked done since Oct 8 (MET / PARTIAL / MISSING per requirement, scale words count), fix small gaps directly, add big gaps here as G items.
Q2. Quality loop (standing, when nothing else is open): docs/STORE_QUALITY.md and docs/status/scorecard.md; pick the reddest high-impact objectives, expand each into what finished looks like, fix, re-measure, independent verifier; never declare the game store-ready.

## THE GAME'S SPINE (read first; every item serves this)
Play by the rules until you have iron, ideally diamond. Then you can take a village. Then the military bases (rare, tiered, GoldenEye-style), then the navy and its frigates, then hell, then the Reich below hell. Killing the Reich's leader beats the game. Gear tiers, tool upgrades and vehicles are the keys between stages.

FROM THE OCT 11 AM PLAYTEST (Remington on the Quest, build 0.129; check each against current claude/quest-port first):
G12. [capitals] [DONE: Lane A thread, 2026-10-11, PR #49; docs/status/tidebreaker-gaps.md] Capitals are far too common (two within 500 blocks) and one sat at the player's spawn with a crawler; make capitals rare, never near spawn, and procedurally varied in size (a pool of capital buildings where only some spawn per city).
G13. [frigate, with G1] [DONE: Lane A thread, 2026-10-11, PR #49; docs/status/tidebreaker-gaps.md] The naval/main gun does far too little damage: against a crawler it should tear off a huge chunk or destroy it outright. Ships should not carry Capital soldiers: the frigates are their own navy faction (A3).
G14. [towns] The jail is broken (find what is wrong in a town jail and fix it). Emerald-to-cash is undiscoverable: make the bank exchange obvious (signs, a tip, a notice board line) and make emeralds findable in survival (where they come from, documented in the recipe book or a tip).
G15. [towns] Stealing a gun from a townsperson must be very hard before iron armour (the six-iron rule); verify the sheriff/deputies respond and the gun is guarded.
G16. [mobs] The Powderwight is too hard to kill before it detonates, even with an iron sword; tune its health, fuse or telegraph so a prepared player can win.
G17. [hell] Entering hell from above ends at a lava-pool cut-off; make the transition from the deep rock into hell gradual and readable. Hell mobs must be hell's own types everywhere (check B6 covers all spawns).
G18. [looks] Plain grass looks barren: add more ground cover (tall grass tufts, short grass that rises slightly off the block, variety) within the Quest frame budget.
G19. [new, Lane B] Difficulty levels: easy, medium, hard chosen when creating a world and locked afterwards; they change enemy speed, damage, health, hunger and spawn density. Document the table.
G20. [IP, from P19] Replace the remaining close copies of reference features with original designs (docs/status/ip-content-audit-oct11.md: the Hollow + Hollow Spire + Void Dragon, Cinder Fortress / Boarling Keep, Sea Temple, Forest Manor, Proving Halls). The murk depths, Buried Citadel and Deep Stalker summons are already out (P19).
G21. [done, PR #50: VRScope.swift, a 4x zoomed eye view with a lens mask and the impact reticle; check vrScope] [guns, from P32] The Farsight rifle has no VR scope: raising it to the eye should show a magnified scope view (a render-to-texture lens on the scope, or a zoomed overlay on the eye nearest it), with the reticle matched to where the round lands.

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

B4. Countries that give minerals. [DONE: Lane B thread, 2026-10-11, PR #39; docs/status/countries.md] Intent: there should be countries too that give minerals.
- The world is divided into a handful of countries with borders, flags, capitals and towns, each rich in particular minerals. They trade, tax and pay tribute; you can ally with one, raid another, or take it over through its capital. Border posts, customs and wars between countries that change the map over time.

B5. Enchantments become tool upgrades. [DONE: Lane B thread, 2026-10-11, PR #40; docs/status/upgrades.md] Intent: enchanting is too similar to the original; make it tool upgrades that still need experience.
- A workbench upgrade tree per tool and weapon (sharper edge, reinforced head, balanced grip, scopes, extended mags) paid with experience plus materials; visible changes on the model; old enchanted items convert in saves.

B6. Hell's own mobs. [DONE: Lane B thread, 2026-10-11, PR #44; docs/status/hell-mobs.md] Intent: hell needs its own mobs, including a dark burgundy knight class. Hell comes after mastering the bases and getting upgrades.
- A knight order in dark burgundy armour: squire, knight, champion and a commander mini-boss, with shields, parries and charges that suit VR melee. Plus 3+ other original hell mobs with distinct roles (flying, swarm, ranged).
- Gate: hell is reachable only with base-tier gear (a key or charge looted from command fortresses), so the order is clear.

B7. The Reich below hell. [DONE: Lane B thread, 2026-10-11, PR #46; docs/status/the-last-war.md] Intent: below hell is Nazi Germany: tiger tanks, black everything, red flags with black, replicas of German weapons from the time; it should be clear what we are going for. You kill them and you have beaten the game.
- Build on the Ashguard and the Ash Vault (PR 22 and the gap pass). Black uniforms and vehicles, red banners with a black fictional emblem, heavy tanks in the style of the period, half-tracks, artillery, and period-style rifles, SMGs and MGs under fictional names.
- A final campaign: fortified lines, a leader in a final bunker, a big last battle and an ending.
- Store-safe as stated at the top.

## LANE M (the Mac worker; needs the device or the Mac)

M1. Polygon terrain test. [DONE: Mac queue, 2026-10-11; docs/status/polygon-test.md; device walk in device-checklist.md section 2] Intent: a test of the polygon idea to see how it turns out. Build on the smooth-terrain prototype (task 25b3) and make it playable as an option on Quest so Remington can walk around in it; screenshots and fps compared with blocks.
M2. (moved to lane C as L2)
M3. [Checklist written 2026-10-11: device-checklist.md section 3; needs the headset] Device feel for the lanes above: flying, crawler, frigate radar and VR melee against knights, checked on the Quest.

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

L2. Redstone. DONE (PR #38): the Sparkstone Workshop world (Worlds menu), seven standard circuits checked against the reference in questcheck --workshop-only; 4 engine fixes (docs/status/sparkstone-workshop.md).
REDSTONE: Build a redstone test world with standard circuits (clocks, T flip-flops, piston doors, item sorters, observers, comparator subtraction) and make every one behave like the genre reference; automate the check.

L3. Oct 10 AM playtest flesh-out list (skip towns items; lane B owns them). [DONE: Lane C thread, 2026-10-11, PRs #42 (ground), #43 (perf overlay, world gen, eruptions), #45 (VR combat feel); docs/status/ground-l3.md, l3-part3.md, vr-combat-feel.md. The 20-minute soak, device fps and the Quest build ship are on lane M's device checklist. Ruined portals were removed at Remington's request.]
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
T2. questcheck on CI run 38158315397 (HEAD 9b91522d) fails 20 town checks: voices (greets 0 times), honour (theft heat,
    $0.00 bounty), bounty (law never challenges, lapse day), honour HUD/meter/inventory, six-iron hit rate, countries
    ore. Towns-lane code; the Mac worker did not touch it. Reproduce: quest/tools/linux-check.sh then questcheck.
T3. Mac heavy lane reds that are red on claude/quest-port too (run 930 on bfb3f14, still red on PR #49's run 940), left
    when #49 merged (Lane A thread, 2026-10-11): each needs its root cause, not a looser threshold.
    a. play: `--playthrough` blight fight: 388 arrows for 31 damage, 0 sword hits in 601 s, so no Blight Star (the
       Blight sits 5 blocks above the player and the sword never reaches it).
    b. checks: `--structcheck` floating 1 (a capital_city wall over a dip, see the structcheck-on-linux baseline);
       agent life: 3 unmet goals of 3 on seeds 12345 and 777.
    c. tours: ridecheck 3 FAILED (crew leave their posts / the disabled deck; bay troops inside a solid on the ramp,
       24.3,10.1,71.3 ship space), rulescheck "water heads for the drop 3 east and not west" (both ways), questbugs
       "VR trigger spam: zombie not dead in 6 s" and "aliased chunk blocks load as wardstone".
    d. Quest host questcheck reds that come and go on claude/quest-port itself (Lane A, PR #50 full runs 50-52,
       2026-10-12): `ash vault perf` (citadel Total War, Game.tick avg 12-14 ms against the 10 ms debug budget),
       `maingun: the impact itself is cheap` (fx 15 ms of 17 on the frame thread), `lastwar: the last wave's units cost`
       (whole tick 22 ms against 8.6 without them, under load), `deep: sealed lava pockets above the
       lava sea`, `boreal 12345 ... birdCall`, `boreal ops: a roused soldier leaves the shut archive` (passes alone).
       Load-dependent on a 4-core runner; each needs its own fix (the fx cost first), not a looser budget.
T4. Citadel patrols give up where a path exists (PR #49 heavy shots red, `--basetest patrol`; Linux repro:
    `questcheck --basetest-only patrol`). G12 moved seed 12345's nearest citadel to -456,920. A gunshot 40 blocks south of
    its gate: PathFinder.find (8,000 nodes) walks gate -> spot, but the patrol leader stops 36 blocks short ("no way on")
    after ~4 blocks: basePatrol (CapitalBasesWork.swift) orders 18-block waypoints at `standY` ground and the soldier's
    own search gives up on them. Fix the class: a patrol follows one long path (or waypoints taken from it), and the
    test's "reaches the spot" passes at this citadel and the old one.

## ART LONG TAIL (non-blocking notes from the 25b4zzz art-gaps done gate, 2026-10-11)
AR1. 268 block layers still procedural (workblocks, sculk, copper bulbs/chests, coral, Steelhold/capital/frigate
     panels, ship parts): list in docs/status/art-style-remaining.md. Needs Gemini sheets (Mac, CHROME=1).
AR2. cave_vines, weeping_vines, twisting_vines and the torch_top/torch_bottom variants are still procedural.
AR3. Add a snap with XP set so the xp_bar fill is seen in evidence; check its stripes read as a tube at 3 px tall.
AR4. Beds read as a thin flat slab in the Mac family gallery; check them at play distance on Quest.
AR5. Close-up tiled shot of nether_quartz_ore / deepslate_diamond_ore to confirm the seam blend.
AR6. texpack.bin grew 12.9 -> 18.6 MB; weigh it for the repo and Quest download (ASTC is Remington's call).
AR7. Save each Gemini prompt verbatim in assets/CREDITS.md going forward (s23-s28/p03/i20 record pattern + cells only).

## FROM THE DONE AUDIT (task 25b6, 2026-10-11; items G1-G11, renamed from A1-A11 so they are not confused with Lane A; full tables in docs/status/done-audit.md). Whichever cloud thread is free takes these FIRST, before new lane items.
Cloud-lane areas, worst first. Each line is a gap an independent reviewer found against a task already marked done.
G1. [frigate gun, FIRST] [DONE: Lane A thread, 2026-10-11, PR #48; docs/status/tidebreaker-gaps.md] The live helm shot never fires: `--questbugs --only maingun` fails 6 checks on fa79ef5e
    ("charges for 5.56 s", 0-block crater, 0 coil thumps, 0 shake). Tests that call mainGunTick directly pass; the
    g.tick path doesn't finish the charge. Also make FactionTests.swift:77 fire a real slug instead of Explosion.crater.
G2. [the Deep] D2 vault pass never merged (garrison towns, rail, airfield + AA, mortar pits, foot patrols, saved
    vault-wide alarm, reinforcements, crew bail-out DE9, radio/story DE11). This is the "far under spec" part.
G3. [the Deep] Quest perf in the vault: proxy ashvault route 12 hitches/min (max 45.6 ms); add a live-unit cap and
    soldier AI LOD, plus a questcheck "citadel at full alarm" number (DE14).
G4. [the Deep] Playthrough.swift has no Deep stage (keep -> Sunderite -> charge -> seal -> citadel -> Marshal -> lift).
G5. [the Deep, small] battery shells get the Marshal's red flare warning (AshUnits.swift ashArtillery -> g.ashStrikes,
    DE10); marksmen get a first-shot glint (an unarmoured arrival died 92 blocks out in 4 s); blend the vault sky over
    y 120-136 instead of the switch at 128; fog end 130 -> ~220 so the 138-tall vault reads as huge (check proxy p99).
G6. [base / village] [DONE: Lane A thread, 2026-10-11, PR #49; docs/status/tidebreaker-gaps.md] First citadel findability: radar and intercepted orders are base loot, so the first base means
    wandering ~1,200 blocks. Add a cartographer explorer map to military_base or orders in wild camps.
G7. [towns] [DONE: Lane A thread, 2026-10-11, PR #49; docs/status/tidebreaker-gaps.md] Rename the Capital city "Meridian" (CapitalTown.swift:17): it clashes with the Meridian Navy. Add a
    capital_city structure shot and a street-level shot to snap.sh.
G8. [frigate] [DONE: Lane A thread, 2026-10-11, PR #49; docs/status/tidebreaker-gaps.md] Thrusters read as two small points at night: bigger glowing faces + a drive-glow sprite.
G9. [horses] Horse coats are flat untextured colours; texture the coat per variant, check the rider's view of the
    neck/mane, add a Quest horse render to questcheck.
G10. [towns] `--towntests` has 5 FAIL on fa79ef5e: wallet/honour HUD lines empty (HonourTests.swift:218,
    HonourGapTests.swift:263), "sheriff shoots an outlaw player", "3 bread for $0.90". Fix, then add --towntests to
    snap.sh's checks shard so they gate CI.
G11. [frigate] [DONE: Lane A thread, 2026-10-11, PR #49; docs/status/tidebreaker-gaps.md] No designed way to board the Meridian frigate 45 blocks up outside `/vessel frigate`: a boarding route
    (drop ladder, or hail-and-board when it flies low) plus a ride-check bot that reaches the helm from the ground.

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
