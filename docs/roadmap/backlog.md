# Blocksmith roadmap backlog (Remington, Oct 10 21:40; fleshed out by the overseer)

How to use this file (cloud threads and the Mac worker):
- Work top to bottom inside your lane. Claim an item by adding your thread name and the date next to it in a PR that only edits this file, or in your first PR for it. Skip items another thread has claimed.
- Each item lists Remington's intent first, then the expanded objectives. Treat both as the spec. Write your own extra objectives too (OBJECTIVES FIRST), build to them, then mark the item DONE here with the PR numbers.
- ONE AND DONE (Remington, Oct 12 19:11; overrides any review, verify or DONE GATE wording anywhere in this repo): build each item thoroughly and well the first time, make sure it compiles, run the one quick test that shows the item works, fix any conflict you know of, commit, push, merge, mark DONE, move on. No reviewer, no verifier rounds, no rechecks, no full questcheck per item or per round. If the Quest build or a later playtest shows something broke, fix it then (80/20).
- NO HELPER AGENTS (Remington, Oct 13 21:15): work one item at a time yourself. Never dispatch subagents (no implementer, reviewer or parallel helper agents, and do not use the subagent-driven-development skill); they burn the weekly usage. Push and self-merge each item as its own PR.
- NO TEST WORK (Remington, Oct 13 08:15): never take an item, or part of an item, whose goal is making tests, bots, CI runs, checks, scorecards, benchmarks, evidence snaps or verifier notes pass or exist. If an item mixes gameplay and test work, do only the gameplay. Anything that needs the headset or the Mac (device checks, Quest fps) is skipped by cloud threads. If you notice yourself spending more than 30 minutes on a test or tool instead of the game, stop and move to the next gameplay item.
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

## PLAYTEST Oct 12 AM (P68-P97): top priority with any open P items
Played build 07d9fc85 (#50-#54 merged) 09:17-09:49 in his existing world; notes with repro lines in docs/playtests/2026-10-12/voice-notes.md. P82 and P84 say items claimed done in #50 did not work on the headset: verify on the real build, not only in headless checks.
P68. [DONE: PR #56, 2026-10-12: Greywall terminals and server racks on new ground, the console keyboard no longer a checkerboard, orders open as a document.] Greywall outpost interior: he loves the space (keep the layout), but the computer room uses old-looking props (a chess-like computer); Greywall needs its own modern equipment. Intercepted orders should be readable documents you can pull out and read (RDR2-style text).
P69. [DONE: PR #56, 2026-10-12: Greywall bases and stations kept 480+ from Capital sites, station garrisons are Greywall troops; the citadel crawler is still Capital.] Greywall bases sit right beside Capital structures; they are a different force and must be placed apart from anything Capital. Crawlers are not Capital either; check faction labels and ownership.
P70. [DONE: PR #56, 2026-10-12: four deck gun looks, a manned shell breaks ~30 Capital stone blocks and tears hulls at power 11, drops and debris rest on ship decks.] Naval guns: do not reuse one copy-pasted naval gun model everywhere; damage against crawlers and the Capital tower is still far too low (much more); wreck debris falls through the ship deck. Keep: the explosion effects.
P71. [DONE: PR #56, 2026-10-12: wide-town streets 5 across.] Village paths are still too narrow for the spacing between houses; widen them (P62 follow-up).
P72. [DONE: PR #56, 2026-10-12: open tab gold.] Menu tabs: the selected grey tab does not change colour; only haptics show it. Make the selected tab clearly highlighted.
P73. [DONE: PR #56, 2026-10-12: tap the map to pin a waypoint.] Map: let him place a waypoint on explored map areas.
P74. [DONE: PR #56, 2026-10-12: gun in hand opens doors, left grip steps the hotbar.] Holding a gun breaks other inputs: doors will not open and the left grip (inventory wheel) does not work while a gun is held.
P75. [DONE: PR #56, 2026-10-12: short grass drawn by the painted blade tufts (36 blades, taller, spread) instead of the stubby imported sprite, compared on the Quest renderer; flowers unchanged. TextureGen.painted lists layers kept painted.] Ground cover: the scattered bits of grass look wrong (flowers look great, keep them). He hands this to us: experiment and pick whatever looks best.
P76. [DONE: PR #56, 2026-10-12: saddlebags chest on a tamed gaited horse.] Saddle bags: a small chest on the saddle to carry items on the horse.
P77. [DONE: PR #56, 2026-10-12: blade trail smoothed and dimmed, no strobe.] Sword: a white strobing flicker appears when moving the sword (likely the blade trail). Keep: swing mode, the sword look, the crafting fix.
P78. [DONE: PR #56, 2026-10-12: corpses not red.] The red hit mark did not stay on the target; dead mobs stay tinted red on the ground; corpses should not be red.
P79. Some NPC/mob models look underdeveloped (he could not tell who they were, maybe pillagers); the skeleton on the spire looks wrong; design our own enemy instead (with P19/G20).
P80. [DONE: PR #56, 2026-10-12: bloom sits on the cactus.] The flower on top of cactus floats above it.
P81. [DONE: PR #56, 2026-10-12: slowest horse canters at 6 b/s.] Player movement felt very slow at 09:28 (check his state at that note: speed modifiers, armour weight, status).
P82. Regression or not reaching the headset: the Farsight rifle still cannot aim and the reload button still does not work (P32, P56, G21 were claimed done). Verify on the device build.
P83. [DONE: PR #56, 2026-10-12: longer gallop, bonding toughens.] Horses: running animation still bad; stamina far too short; bonding levels should raise stamina and health like RDR2; RDR2-style health and stamina cores in the UI.
P84. [DONE: PR #56, 2026-10-12: Polygon Terrain row on the Video page and the world screen.] He cannot find the polygon (smooth terrain) option after several asks: make it obvious (it is at Create New World > Terrain and Options > Video), e.g. a clearly labelled toggle on the world screen; confirm it shows on the Quest build.
P85. [DONE: PR #56, 2026-10-12: no hotbar hints on the headset.] HUD: remove the L-grip / right-stick hint labels beside the hotbar and the sprint indicator (keep the translucency, he likes it).
P86. [DONE: PR #56, 2026-10-12: a wall torch is one slanted stick (Box.leanX/leanZ shears its top 5 px out) with its foot on the wall, and its sides now sample the torch art (they were blank at the wall's edge).] Wall torches look bad: they look fused to the wall and not fully textured.
P87. [DONE: PR #56, 2026-10-12: riders on roads about 2.4x as often.] Roads with riders near villages: he still wants them; make sure they appear (they are new-chunk only in old worlds, so check generation).
P88. [DONE: PR #56, 2026-10-12: 3-5 hunters, twice as tough, red crosses on the map, combat music.] Bounty hunters must be a big deal (RDR2): a map marker at a distance, a music change when they come, and tougher fights.
P89. [DONE: PR #56, 2026-10-12: leaves rustle.] The leaf-breaking sound sounds wrong.
P90. [DONE: PR #56, 2026-10-12: no turtles by cold ground.] Turtles appear near a snow biome; fix biome rules for turtle spawns.
P91. [DONE: PR #56, 2026-10-12: stations, Greywall bases and citadels bank down into the land on new ground.] Bases sit on raised block platforms; blend their foundations into the terrain.
P92. [DONE: PR #56, 2026-10-12: a citadel on new ground lays a rail spur of up to 150 blocks (cuttings, trestles, ballast, buffer stops, a platform with lamps) with a parked train: a Capital Locomotive (furnace cart) and two freight cars of supplies; the spur is its own structure kind (capital_rail) on the citadel grid, so the citadel's box and older ground decisions are unchanged. Folded into C1 later.] [feature] Capital trains: a procedurally generated rail line leading out of a base with a train on it (fold into C1 railways).
P93. [DONE: PR #56, 2026-10-12: wrecks on new ground are rotten (Rotten Planks) and a helm raises one once they're replaced; ship guns use Cannonballs in survival (iron + gunpowder makes 4); a cannon next to a base computer (console, Greywall terminal or server) is an auto-turret. Pirates as a faction and computers on ships are T15.] [feature] Pirates and wrecks: repair broken ships and float them, craft cannons and cannonballs to mount, combine a computer taken from a base with a cannon for an auto-firing turret. Player-built vs preset vehicles and damage physics are left to us.
P94. [DONE: PR #56, 2026-10-12: clearer ice.] Ice: a nicer, semi-transparent texture you can see through to the bottom.
P95. [DONE: PR #56, 2026-10-12: stations 6% and Greywall bases 15% of their old share on new ground.] Bunker bases and military towers are far too common (three within minutes); the rarity rule (about one per 4000x4000) is not holding, at least where he played.
P96. [DONE: PR #56, 2026-10-12: outlaw only within 800 of where it happened.] Outlaw status should be local: far from the village where he became an outlaw, people should not try to kill him.
P97. [DONE: PR #56, 2026-10-12: campfires respond (they never did), rest by a lit fire mends, flames are crossed sheets, a camper at each camp.] Camps: the campfire cannot be used and its fire looks wrong; a camp should have a person at or near it.
Praised, keep: the outpost interior space, explosions, sugarcane fix, crafting fix, the sword and swing mode, flowers, the translucent HUD, camps.

## REMINGTON, Oct 12 12:08: the Reckoning as he means it (P98, top priority with the P items)
P98. [DONE: PR #56, 2026-10-12: eight war bands (Marauders x2, the Capital x2, Greywall, Stormwarden Aegis Marines, the dead x2; ~100 units) set out 450-700 blocks off at once and track the player; units stream in out of sight (24 live max); underground loses the trail; a death pushes them 250 out; all dead = peace (no Marauder patrols, bounty hunters, town raids, Capital patrols, warships) + $250; orange map squares and a HUD counter; saved; P46 saves migrate. Device check is the Mac worker's.] Rework the P46 Reckoning (Sources/Reckoning.swift, merged in #50) to his full vision. Today it is five small sequential waves (5 Marauders + 3, a handful of soldiers...) spawned 26-36 blocks away, and winning only stops Marauder patrols. He wants: (1) when the player returns to the surface after defeating the Reich below hell, EVERY faction (Marauders, the Capital, Greywall Command, the Stormwarden navy and its Aegis Marines, the restless dead) sends BIG groups at the same time, not one small wave after another; (2) they actively track and hunt the player across the whole surface, converging on his position wherever he goes; (3) the only escape is going underground: below the surface they lose the trail and wait/patrol at the surface, resuming the hunt when he comes back up; (4) the hunt only ends when every one of those hunting groups is dead; (5) then the surface is at peace for good: all factions stop hostile patrols and raids against him (not only the Marauders). Keep it Quest-safe (72 fps: cap live units, stream groups in from out of sight, reuse the dropship arrival), saved across reloads, and tell the player clearly what is happening (warning, map markers for hunting groups, a counter of groups left, a peace moment when it ends). Verify on the device build.
P99. [DONE: PR #56, 2026-10-12: a hostile frigate charging its main gun marks a spot near the player (a red ring, walking in 14 -> 3 blocks over shots), the slug digs a 26-deep crater spread over frames (capped per frame), 90 debris bits.] [Remington, Oct 12 12:11] Hostile frigates bombard the player: an enemy frigate that spots him fires its main-gun slugs at the ground around him to kill him (a telegraphed warning, then the impact). Each slug must be devastating: a crater at least 20 blocks deep (today the main-gun crater is a radius-9 bowl, Explosion.crater), with debris and a big shockwave. Keep it Quest-safe (cap blocks removed per frame, spread the crater job over frames as CraterJob does) and keep the IP rule: an original name and look, no Halo terms. Ties to P70 (naval gun damage far too low against crawlers and the Capital tower: raise it to match).
P100. [DONE: PR #56, 2026-10-12: Quest chase view behind a piloted ship or boat (eased follow, comfort vignette by speed, pulled in short of walls), Options > Vehicle View to stay in first person.] [Remington, Oct 12 12:11] Vehicles switch to a third-person chase view automatically when you take the controls (like GTA), and back to first person when you get out: the drop craft (P66, he can hardly see while driving), crawlers, the Sky Skiff, boats and frigates. The Mac already has thirdPersonDistance for ships (ShipPlay.swift); bring an equivalent to the Quest renderer with VR comfort in mind (smooth follow, comfort vignette, an option to stay in first person).
P101. [DONE: PR #57, 2026-10-12: a manned twin gun fires left then right (two shots a load, 0.45 s apart), a flash at each muzzle, per-barrel kick; --p12-only twinBarrels] [Remington, Oct 12 12:15] Twin-barrel naval guns fire both barrels: the base and Capital naval guns have two barrels, so the player gets two shots per load (alternate left and right, or a paired salvo), with two muzzle flashes.
P102. [DONE: PR #57, 2026-10-12: NavalGuns.swift: heavy shells do plate damage to deck guns on bases, ships and the Capital (2 manned hits kill one), hurt guns darken, smoke and droop a barrel, a destroyed gun leaves a wreck heap; --p12-only gunDamage] [Remington, Oct 12 12:16] Naval guns can be destroyed: he hit another naval gun with a naval gun and nothing happened. Guns on bases, ships and the Capital take damage, show damage states and break (wreck model, no longer usable).
P103. [DONE: PR #57, 2026-10-12: a manned shell carves a ~7-wide breach through a 3-thick base wall, 150 blocks a frame (cap 650); --p12-only wallBreach] [Remington, Oct 12 12:16] Military base walls take far too little damage from a naval gun shell: a hit should blow a large breach (with P70, which covers crawlers and the Capital tower). Keep it Quest-safe (cap blocks removed per frame).
P104. [DONE: PR #57, 2026-10-12: GreywallArms.swift: five Greywall guns and Slate Rounds for troops, drops and chests; saves re-arm on load; --p12-only greywallArms] [Remington, Oct 12 12:17] Greywall base troops drop and carry Capital rounds and Capital weapons: they should not. Give the base faction its own weapons and ammo (with P70: no copy-pasted Capital naval gun on the bases either).
P105. [DONE: PR #57, 2026-10-12: guns differ by range, damage and recoil (four pistols, five rifles); recoil also widens AI aim, Hannibal troops have none; rocket launcher unchanged; --p12-only handling] [Remington, Oct 12 12:18] Weapon variety by recoil: at least three pistol types (and the same idea across rifles) that differ in range, recoil and damage; the better guns are harder to handle because of their recoil. Hannibal troops (power suits) fire them with no recoil penalty. Keep: the rocket launcher, which he praised.
P106. [DONE: PR #57, 2026-10-12: (4) every natural cave wall meshes smooth (13 more natural blocks); (1) surface relaxation over a 4-cell ring shared between sections (no seams), a stepped hill strays 0.029 blocks from an even slope against 0.050; (2) chipped blocks stay smooth and dent inward; (3) trees are the Mac worker's (tree looks), (5) water left as blocks; device fps for the Mac worker (T17); --smooth2-only] [TOP PRIORITY (Remington, Oct 12 12:34): work it alongside the small P fixes, not after; Remington, Oct 12 12:12-12:21] Polygon terrain, round 2. He found the smooth/polygon test (P84 is resolved on the device) and loves the caves (this is like not Minecraft at all). He wants it developed much further even though it is disruptive. What is wrong today: (1) hills and everything else look wavy and you can still tell it used to be blocks; (2) breaking a block turns that spot back into a cube: instead each block should be made of polygon pieces that break off as you dig; (3) trees are still blocky; (4) some cave areas did not smooth; (5) water still behaves as blocks (fine for now). Goal: smooth and realistic like Red Dead Redemption 2 or Halo while keeping Minecraft block physics underneath (destruction depends on it). Render distance may cost some, but keep compute sensible on Quest; measure fps against blocks. Start with caves, which already look terrific.

Oct 12 afternoon playtest (Remington, 14:59-17:56, on the 12:32 build e13bd0db; check each against claude/quest-port first, several may already be fixed by #57-#60). Notes: docs/playtests/2026-10-12/voice-notes.md. Small fixes first (P107-P130), then features (P131-P139). Keep: field rations and baked potato in base barrels, the shooting range, crafting a standard magazine, obsidian look, granite colour.
P107. [DONE: world.json is written when a world is created and saves no longer fail on a non-finite number; a smooth world reopens smooth (--p12pm-only P107)] [14:59] A smooth (polygon) world reloaded as blocks: smooth must persist per world across save/load.
P108. [DONE: the context prompts move above the hotbar whenever they would reach it (45 screens and scales checked)] [15:01] The right-hand UI still overlaps the hotbar.
P109. [DONE: a grip with the hand in front of the waist steps the hotbar; only a hand down at the side takes a magazine] [15:02] Left grip still does nothing while holding a gun (P74 was in the build he played: regression or wrong hand).
P110. [DONE: icons show the front of furnaces, dispensers, droppers, observers and chests; the bed icon has both halves; the observer has a new copper-ringed lens face] [15:04, 17:50] Inventory icons: furnace and bed look wrong; dropper and dispenser have no texture; the observer needs a new look.
P111. [DONE: cobweb and amethyst block painted again; granite (and diorite, andesite) sharpened; stone given the deepslate rock look, ores rebased on it] [15:10, 17:13, 17:17, 17:21] Textures: granite looks good but soft (sharpen); amethyst looks bad; spider webs looked better before (regression); he likes the deepslate look much more than plain stone.
P112. [DONE: small held pools sunk into cave floors from -40 to below sea level] [15:12, 15:32] Caves need a little water here and there (some exists, too little).
P113. [DONE: underground the sky dome is replaced by dark cave fog and the fog closes before the far sections are cut] [15:14] Looking down a long cave, the sky shows at the far end (it should not in the cave layers).
P114. [DONE: lava flows steadily near the player, blocks place into lava, items burn in it] [15:22, 17:13, 17:15, 17:28] Lava: flows only sometimes; blocks can usually not be placed into lava (Minecraft allows it; works only sometimes); thrown items should burn in lava; a burning overlay when the player is on fire; making obsidian takes far too long.
P115. [DONE: hunters never find him underground, a posse every 3+ days at 1 in 900 a second, 5 to 8 riders] [15:24, 17:19, 17:51] Bounty hunters: they must not find him underground; much rarer, but when they come they are many and a real problem (with P88).
P116. [DONE: Journal in the pause menu keeps every message and document] [15:25] A journal/log to reread notes and messages he has received.
P117. [DONE: the horse won't come when called from underground] [15:30] The horse (Ginger) must not come when called from underground.
P118. [DONE: gravel hits are a knock and pebble clicks] [15:32] Hitting gravel still sounds like hitting water.
P119. [DONE: magazines crafted from rounds; in VR, reload only by a magazine from the hip] [15:34] Ammo: craft loose rounds into magazines (less inventory space); reloading is done by taking a magazine from the hip only; remove the reload button.
P120. [DONE: Capital rounds craft from steel, copper and gunpowder] [17:11, 17:47] He wants to craft capital rounds (his favourite ammo); today he cannot. Allow it at a fitting cost.
P121. [DONE: rails over air and unattached amethyst are dropped at generation] [17:22, 17:32] Floating pieces: a rail floating in the air; floating amethyst.
P122. [DONE: blocks place while jumping, lifting the player onto them] [17:22] Allow placing blocks while jumping.
P123. [DONE: the armour bars show piece icons and an Armour heading] [17:23] He does not know what the four bars on his left are: label them or remove them.
P124. [DONE: base ticks planned Greywall/station/citadel starts on the frame thread (520 ms); now planned on a worker] [17:24] Occasional frame drop with a freeze of about a second: find the hitch.
P125. [DONE: Lanternvine with teal Lumen Pods, picked and regrowing] [17:25] Glow lights on cave vines (like glow berries), but not a near copy of Minecraft (IP: make it our own).
P126. [DONE: sneaking stops at edges on foot and in room-scale] [17:30] He fell off an edge while crouching: sneaking must stop at edges.
P127. [DONE: sleep from dusk; furnaces, brewing stands and campfires catch up on missed time] [17:49] Sleep was refused when it should be allowed. Sleeping through the night (and time away from a loaded area) should advance furnaces and other timed work by the time passed.
P128. [DONE: doors pair their hinges, so double doors open to the sides] [17:51] Running through double doors snags in the middle.
P129. [DONE: the crafting book ignores the opening click and grip only selects] [17:53] He made stairs without meaning to (crafted or placed): find the input that did it.
P130. [DONE: shovel digging is steady, with progress kept when you look back] [17:54] Shovel digging breaks blocks in uneven bursts: make it smooth and steady.
P131. [DONE: a home marker on the map and minimap with distance and direction] [15:06] Home finder: a way to find home (bed or respawn point) when lost, such as a compass needle or map marker.
P132. [DONE: engine carts on fuel, laying track from a cart, tickets to found stations on other lines, linked mine drifts] [15:13] Railways (with C1): connect the lines into a real network for fast travel; let him lay rails himself; minecarts with an engine that need fuel or power.
P133. [DONE: ten base sundries in supply chests and now-filled base barrels] [15:19] Base barrels also hold flavour items useful to a base but useless to the player.
P134. [DONE: monsters roll runner, middling or brute builds; Powderwights run at you] [17:18, 17:33] Mobs vary a lot in speed and damage; the creeper replacement runs at you, faster.
P135. [DONE: small missiles with limited loads from crawlers, frigates and citadels] [17:26] Small missiles: crawlers, bases and frigates can fire small missiles (not big ones), with a limited supply.
P136. [DONE: swing damage linear in tip speed, a wind-up bonus, head hits x1.5] [17:29, 17:35] Sword damage scales with swing speed and/or how far the blade travelled before the hit; head hits do more.
P137. [DONE: a full repair takes 4 units plus one per upgrade level] [17:51] Repairing a weapon costs more material the more upgrades it has.
P138. [DONE: upgrade lines need a found blueprint; one chest in four holds one] [17:55] Upgrades need a found recipe or blueprint first, found in chests at camps, boats and similar places.
P139. [DONE: a goal step for the citadel raid; the Wardstone hint marks the nearest citadel] [15:27-15:29] Progression was unclear underground (which ore breaks the barrier, what to do next) until he worked out the base raid: make the next step clearer.

Oct 12 evening playtest (Remington, 20:49-21:16, on the 20:45 build 664e3d10; check each against claude/quest-port first). Notes: docs/playtests/2026-10-12/voice-notes.md. Keep: roads, the home finder, wind high up, treasure maps, robbable buildings, Saddle Salve, horse jumping and momentum ("so fun to ride").
P140. [DONE Oct 13: the hovered button turns bright blue with a gold frame and arrows] [20:49] Create New World menu: he cannot tell which button the pointer is on; make the hovered/selected button obvious.
P141. [DONE Oct 13: covered by the polygon thread, PR #81] [20:51] The smooth (polygon) world still shows the checkered look on hillsides.
P142. [CLAIMED by the polygon thread (branch claude/polygon-ground-up), Oct 13 09:25: other threads skip it] [FIRST VERSION: PR #81, Oct 13: overworld Smooth worlds mesh the generator's own terrain and cave fields (no checkered hills, P141), materials blend, snow on slopes, dug pits dent; docs/status/polygon-ground-up.md. PR #83: the view follows the smooth ground. Tree canopies: rounded leaf blobs (T17). River steps ramp (T17 water). Mobs stand on the drawn ground (PR #89). Cloud parts DONE: P141 (checkered hills, PR #81) and T17 smooth trees and water (PRs #85, #87); left: Quest fps on the device (Mac lane), then Smooth as the Quest default once Remington likes it on the headset] [BIG, go-ahead given 20:51-20:53] Polygon terrain from the ground up: instead of smoothing block terrain, build a separate experimental version designed smooth from the start (its own branch and world type, not replacing blocks), so it can be judged on its own. Everything nice and smooth; keep block-style digging and destruction underneath.
P143. [DONE Oct 13: in the headset the right-hand hints are gone; a one-time toast teaches the gun controls] [20:55] The right-hand control hints (R trigger, L trigger, reload, R stick) must go from the HUD; teach them in the tutorial instead (with P85/P108).
P144. [DONE Oct 13: first-time hints near a wreck and on a hull with no drive, both explaining masts and sails] [20:56] Boats: first-time hints on repairing a wreck, and a clear way to make a mast.
P145. [DONE Oct 13: hull floor above the waterline, rocking chop, quicker steering, pointed bow and raised stern] [21:00] Boats: water shows inside the hull; he cannot see himself in the boat (with P100 third person); the boat model does not match its inventory icon; turning is too sensitive (soften); the boat does not ride the waves; he has seen no storms (with any storm item in this backlog).
P146. [DONE Oct 13: terrain draws batched with indirect draws, one per vertex slab (121 -> 39 draws in the test view; at distance 23 about 3300 section draws become a few dozen); device numbers still to measure] [21:02] Performance work to raise render distance beyond 16 on the Quest.
P147. [DONE Oct 13: a galloping horse follows the ground down one-block steps instead of falling and thumping, eased like steps up] [21:04] Horse gallop still feels like a one-cylinder engine (jerky bounce); smooth the riding motion and animation (with P83).
P148. [DONE Oct 13: many more lines for every townsperson type (folk, shopkeeper, cook, farmer, elder, child, deputy, sheriff), plus weather and reputation greetings] [21:07] Townsfolk all repeat the same few lines; write many more lines per type and situation.
P149. [DONE Oct 13: saloons are 15x11 with five tables and four patrons inside] [21:08] Saloons: bigger, with people inside; maybe a simple game (cards) later.
P150. [DONE Oct 13: rounds the player did not fire himself pass through livestock] [21:10] Something shot the cattle with rifle rounds; soldiers and townsfolk must not shoot livestock.
P151. [DONE Oct 13: the drowned are now drowned sailors: navy coat, tarnished buttons, rope belt, slack jaw, barnacles and kelp] [21:11] The drowned look bad: new model and texture.
P152. [DONE Oct 13: they are the labelled bars from P123; he recognised them on Oct 12 21:12] [21:11] The four white bars on the left are still unexplained (P123; check it on the newest build).
P153. [DONE Oct 13: horses take drops of up to 4 blocks] [21:15] Horses refuse drops they took earlier; raise the drop height a horse will take.
P154. [DONE Oct 13: horse barding with trim, cloth skirt, rivets, neck plates, face plate and plume; iron and golden horse armour can be crafted] [20:54] Horse armour.

Oct 13 morning playtest (Remington, 09:40-10:13, on the 09:22 build 40ac7d81; check each against claude/quest-port first). Notes: docs/playtests/2026-10-13/voice-notes.md. Keep: potions, rain and weather, the marshal cap, treasure maps, the Wren pistol.
P155. [DONE Oct 13: village iron golems no longer spawn or stay (only ones the player builds)] [09:41] No iron golems (or anything like them) in villages: Minecraft lookalike.
P156. [DONE Oct 13: glider wings worn now fly as a jetpack; End ship loot gives a jetpack] [09:41] Remove the glider wings: the jetpack replaces them.
P157. [DONE Oct 13: every gun has a German-sounding fictional name (Donnerkeil, Hummel, Brecher, Fernblick, Himmelsturm, Blitzlanze, Falke, Sechser, Kettensturm); the pistol is now a classic blued steel and walnut sidearm] [09:41, 09:44, 09:48] Guns: upgrade how the gun models look; the pistol looks too futuristic; give every gun a German-sounding (fictional) name, like the Sturmwind.
P158. [DONE Oct 13: tooltips say which rounds a gun takes and where to get them; the load prompt and out-of-ammo messages name the round] [09:42] Make it clear what rounds each gun takes and where to get them (he could not tell what the machine gun fires).
P159. [DONE Oct 13: left hand on the barrel plus left trigger aims the gun two-handed, with half the recoil] [09:43] Two-handed aiming: put the left hand on the gun's front grip and hold the left trigger to aim it like a real gun.
P160. [DONE Oct 13: fire, aim and hold hints removed; only "Load" shows with an empty gun] [09:43] The right-hand control hints are still there: remove fire, aim and hold-weapon hints (a load hint may stay). Same as P143; do both together.
P161. [DONE Oct 13: the magazine well catches the magazine anywhere along the barrel and the magazine stays in hand without squeezing] [09:46] Loading a magazine into a gun is too hard; make the reload gesture easy and forgiving.
P162. [DONE Oct 13: the left grip only grabs or inserts a magazine, so it steps the hotbar again] [09:48] While reloading, the left grip cannot step the hotbar left.
P163. [DONE Oct 13: rival factions spot each other from much farther and advance to fight] [09:48] Two hostile bases side by side were not fighting each other: rival factions must attack each other.
P164. [DONE Oct 13: 4-block drops, 1-block gaps, the rider ducks under 2-high overhangs, low bushes trampled at a canter] [09:50-09:58, 10:11] Horses (with P153): willingly jump down 2-3 blocks (only refuse real pits); squeeze through 1-block-wide gaps; duck under 2-block-high overhangs while ridden; run through small prickly bushes without stopping.
P165. [DONE Oct 13: leaves take 0.75 s to break by hand or with an axe; shears, hoe and sword stay fast] [09:52] Axes cut through leaves visibly too fast.
P166. [DONE Oct 13: with P147] [09:55] The gallop still jerks like a whipper snipper (P147, still broken).
P167. [DONE Oct 13: the flame sheets no longer show a solid top piece] [09:57] Fire looks better but still has an odd flame piece on top.
P168. [DONE Oct 13: decoded orders are kept as an Intercepted Orders book] [09:58] Orders and messages must stay readable afterwards (with the journal, P116).
P169. [DONE Oct 13: trampling and dug blocks no longer remesh on the spot; a 60 s gallop over new ground at distance 10 had one tick over 40 ms (80 ms)] [09:59, 10:03, 10:11, 10:12] Repeated short freezes while playing (P124 still present on the 09:22 build); one was big at 10:11.
P170. [DONE Oct 13: the blade trail is no longer drawn] [09:59] The sword still strobes when swung (P77 regression).
P171. [DONE Oct 13: dead bodies fall and slide down slopes] [10:02] Ragdolls: dead bodies must fall (one hung in the air after dying on a hill); ragdoll physics for all bodies.
P172. [DONE Oct 13: digging relights the sections between the old and new ground heights] [10:08] Dark patches appear where he digs (lighting not updated).
P173. [DONE Oct 13: it was the Ancient Spire (great_ruin, 183 blocks tall, about 1000 blocks south-east); it no longer generates] [10:10] Remove the odd tower seen in the distance from World376 (seed 3931512493184456980) near 9110 67 -13846, looking south; find what structure it is and drop it.
P174. [DONE Oct 13: a softer, less inky zenith, a milky haze band above the horizon and crisper, whiter cumulus that fade before the horizon] [10:10] The sky needs work (the rain is good).

Oct 13 midday playtest (Remington, 13:02-13:57, on the 12:54 build 448c3de6 with polygon round 3; check each against claude/quest-port first). Notes: docs/playtests/2026-10-13/voice-notes.md. Keep: the caves in polygon worlds ("terrific", the winner), cave water, barrels with stock, the base raid ("that was a lot of fun").
P175. [CLAIMED by the realistic-world thread (design docs/design/realistic-world.md), Oct 13: (1) real shapes DONE in slice 1 (round trunks, roots, limbs, rounded gourds/hay/caps/blobs, bevelled built blocks, every block state classed automatically); (2)(3)(6) fracture, mining only what is touched and ragdolls/walking on the drawn surface in slices 2-3; (7) far-ring cost in slice 4] [CLAIMED by the polygon thread; PARTLY DONE Oct 13: plants sit on the smooth ground and water meets shores naturally (objectives docs/objectives/polygon-round5.md, status docs/status/polygon-ground-up.md); the rest goes to the new polygon thread] [13:02-13:21] Polygon round 5. His verdict: it does not yet feel built from the ground up. (1) Everything takes its real shape: round trunks with real branches, round pumpkins, and so on. (2) Procedural fracture: when a tool or a bullet hits something, polygon pieces are generated on the spot where it hit and break off (chiselling), unpredictable but realistic, not pre-made block pieces. (3) In polygon worlds the pickaxe mines only what it actually touches. (4) Water still follows block shapes. (5) Floating grass. (6) Animals hover: everything must walk on the polygons (with ragdolls, P171). (7) Lag: it barely holds render distance 16. (8) Some blocks still do not blend into the smooth style.
P176. [DONE Oct 13: the headset laser no longer drags the menu cursor back each frame, so the left stick moves it and the gold hover shows] [13:02, 13:08] On the headset the gold menu-tab highlight still does not show, and the left grip/left stick still does not work (P72, P109).
P177. [DONE Oct 13: on the headset a grip with the hand on a small creature (chicken, rabbit, cat, fox, a baby animal) lifts it; let go mid-swing and it is thrown with the hand\'s speed; a grip on a carcass drags it along the ground on a short lead; those grips do not step the hotbar] [13:07-13:09] Hands that grab: drag a body, pick up an animal and throw it (a chicken), move things around.
P178. [DONE Oct 13: big four-legged animals tip over onto their side when they die] [13:08] Killed cows do not fall over (ragdolls, P171).
P179. [DONE Oct 13: sneaking forward into a gap lower than you are tall drops you into a crawl] [13:10] Crouching should let him fit through low cave gaps.
P180. [DONE Oct 13: new six-iron model: octagon fluted cylinder, top strap, ejector rod, hammer spur, brass guard, raked walnut grip] [13:12] The six iron does not look like a six iron (he mentioned it before).
P181. [DONE Oct 13: nights a little lighter (sky floor 0.30)] [13:15] Nights slightly brighter.
P182. [DONE Oct 13: snow repainted: soft drifts, wind ripples, blue-grey hollows and glints] [13:18] Snow should look more realistic.
P183. [DONE Oct 13: rain streaks fade out near the ground and at the edge of the rain column, so no streaks show through roofs and walls] [13:19] In a boat, a horizontal line of rain sits across the middle of the view at the horizon.
P184. [DONE Oct 13: far (LOD 1) still water is merged into big quads like flat ground (16k cells merged in one ocean view, same look), and the water shader skips its noise ripples past 128 blocks, its foam noise away from shores and its glint with the sun down; the device fps check is the Mac lane\'s] [13:20] Render distance struggles over water, where it should be cheapest.
P185. [DONE Oct 13: zombies and husks are now gaunt hunched dead men (long reaching arms with hooked fingers, ribs through a rotted shirt, a hanging jaw, ember eyes in deep sockets); the Brand Order fights as sword duellists and is much harder: combos of up to rank+1 cuts with uneven timing, feints that come again from the other side, ripostes off a blocked blow, about 1.7x health, more damage, tougher guards] [13:21] Zombies and the other enemies: less Minecraft, scarier. The burgundy knights in hell should be sword-duel knights like the spider replacement, and much harder.
P186. [DONE Oct 13: cookable food used on a lit campfire goes on the fire instead of being eaten] [13:23] Cook food on a campfire.
P187. [DONE Oct 13: tree roots are lying logs (fewer of them), stumps 1 high with roots] [13:23] Tree generation: mutant merged trees and stumps ringed by stray blocks.
P188. [DONE Oct 13: in the headset the water check uses your real head, and the top of the water cell counts as air] [13:24] The underwater tint must clear as soon as his head is above water, not only once fully out.
P189. [DONE Oct 13: Capital duty and signal-room logs, Greywall field notes and town and recruiting pamphlets turn up in chests; the Journal opens on a contents page and keeps every document read whole, page for page] [13:25] A journal that collects everything he reads: Capital logs, pamphlets, orders, notes (with P116, P168).
P190. [DONE Oct 13: shipwrecks are an eighth as common] [13:26] Ships far too common: about 8 times rarer.
P191. [DONE Oct 13: lines under the minimap are spaced 13 apart and no longer overlap] [13:27] The home/distance indicator overlaps the location indicator.
P192. [DONE Oct 13: Hannibal troopers fly on jump jets in a fight; wearing the full Hannibal suit, punching with an empty hand fires an arc blast] [13:27] Power armour fires blasts from the hands; Hannibal troops can fly.
P193. [DONE Oct 13: Capital hall lights doubled, station lamps brighter] [13:33] Lights inside bases so he can see.
P194. [DONE Oct 13: getting out of a gun sets you on the nearest floor; each Capital deck gun calls a rifleman from its garrison to its breech and he works it; while he lives you cannot take the gun ("take him out to take it"), Greywall tower guns likewise while their lookout lives; the block-built gun stays with P102] [13:35, 13:40] Base guns: getting out of a gun drops him outside the base in mid-air. Give each gun a seat under it with a gunner in it (kill him to take the gun); build the gun from blocks so it is destroyed block by block, not as an entity (with P102).
P195. [DONE Oct 13: a tap on the map places a pin even when the laser shakes] [13:36] Pointing and pulling the trigger on the map does not set a waypoint (P73).
P196. [DONE Oct 13: Greywall soldiers drop Greywall rounds] [13:43] A base soldier still carried Capital rounds (P104).
P197. [DONE Oct 13: soldiers who lose you search around where you were instead of standing still; a fresh alarm spreads them out] [13:48, 13:54] Base troops spin in circles and bunch up at the front: spread them through the base and have them hunt the raider the whole time.
P198. [DONE Oct 13: town gunsmiths sell Greywall rounds] [13:48, 13:56] Nearly every gun takes slate rounds and he ran dry: balance ammo types and supply.
P199. [DONE Oct 13: Greywall tower lookouts stand inside the tower] [13:49] A soldier spawned inside a gun.
P200. [DONE Oct 13: wall turrets you place shoot hostiles that come in front of them] [13:50] A wall turret he places must be on his side and shoot his enemies.

## PLAYTEST Oct 13 evening (P201-P220): top priority with the R items
He played the OLD 14:34 build (e25ee2bf) 18:32-19:15, so check each against claude/quest-port first; notes with repro lines in docs/playtests/2026-10-13/voice-notes.md (after 18:32). Several repeat R items (noted). His main complaint: the cool new base and raid content has no limits, so it never ends.
P201. [DONE] [18:33] Create New World: on the third page nothing shows which button is selected (no blue, no yellow); elsewhere a doubled blue-and-yellow highlight shows. One clear highlight on every menu page (with R3).
P202. [DONE] [18:34] The moon is visible through the ground.
P203. [DONE] [18:38, 18:42, 18:46-18:47] Base guards respawn constantly, faster than he can kill them, and reinforcement trucks never stop. A base must be clearable: a fixed garrison, a capped number of reinforcement waves (trucks are fine), then no more. Killed guards stay dead.
P204. [DONE] [18:39] Armour dropped by troops is one set item that fills all four armour slots when worn, instead of four pieces clogging the inventory.
P205. [DONE] [18:40] After dying at the base his stuff was missing (no boots, only some tools). Every item must land in the death drop and be easy to find.
P206. [DONE] [18:42] The Greywall computer on the second floor needs a key he never found: make the key's location findable (a note, a guard who carries it, a marked desk).
P207. [DONE] [18:43] Journal: he could not find how to open it. Give it an obvious entry (pause menu tab and a wrist or hip control) and tell the player once.
P208. [DONE] [18:43] The weapon wheel does not work. Make it work on the headset, or remove it if the toolbar does the job.
P209. [DONE] [18:44] Text in the base (logs, codes, panels) is cut off and cannot be read in full.
P210. [DONE] [18:46] Base tower guns sit displaced off their towers and are far too big for the base. Use smaller guns sized and mounted to fit the towers.
P211. [DONE] [18:47-18:50] Fog banks keep rolling in and blinding him, especially when high up. No fog unless it is foggy weather; otherwise he wants to see a very long way (with F4).
P212. [DONE] [18:49] Jumping over gaps: the jump button overrides the horse's refusal, like RDR2.
P213. [DONE] [18:51] On a crafting tile the craftable count overlaps the item's own number.
P214. [DONE] [18:52, repeat of 13:15] Nights slightly brighter, enough to see a gap before falling in.
P215. [DONE] [18:53-19:01] Raiding parties and bounty hunters came in round after round. One wave per event, much rarer; another base must not send raids right after. Raiders may carry a rocket launcher that blows holes in houses (he liked that).
P216. [DONE] [18:50, 19:01-19:02, repeat of R8] Ammo mismatch: he has piles of arc cells and heavy rounds but nothing he owns fires them; shotguns are rare; nearly everything takes slate rounds. Spread ammo types across the guns and make loot match.
P217. [DONE] [18:35, 19:02-19:03, with R9] Guns: the held model does not match the inventory icon, and several guns look identical. Frontier guns look like their real-world counterparts. Capital guns are white with no blue accents. Cut the roster to fewer, clearly different guns (keep the Slate Repeater and the Service Rifle).
P218. [DONE] [19:04] Sleep is allowed once the sun starts touching the horizon.
P219. [DONE] [19:08] A direct rocket hit should kill a soldier outright.
P220. [DONE] [19:08-19:14] Ship repair: the engine block and light panel requirements are unclear. The repair UI shows each missing part, its recipe and where it goes.
Repeats in this session: R1 (left grip with a gun, 19:06; he also wants grip-left to scroll the toolbar past weapons, 19:14) and F1 (freezes at 18:48, 19:11). Praise, keep: Capital raids are exciting, the alarm panel, the Breach shotgun, the Capital Service Rifle, the stone look.

## THE POLYGON DIRECTION (Remington, Oct 13 22:05): the biggest item now, take right after P221-P251
He played the polygon world on the 21:25 build and decided: "this will be the way forward, no more Minecrafty stuff." He loves the forests, fallen logs, caves and new village buildings. What is wrong comes from blocks still being the base under the smooth surface. A frozen block-world fallback build is kept on the Mac (git tag blocks-fallback-oct13); do NOT maintain a parallel block version, put the effort into the polygon game. Build these thoroughly; each is big, so split into several PRs (one per working piece), each pushed and merged.
PG1. [DONE] No blocks underneath: the polygon world's terrain is a true smooth volumetric field (density/SDF data meshed with dual contouring or marching cubes, materials blended), not smoothed block cells. Digging, explosions and bullets carve the field and break pieces off procedurally (the realistic-world fracture work), including the ground itself. Saves store the field.
PG2. [DONE] Physics on the surface: the player, creatures, items and vehicles collide with the mesh, not with block cells. Sheep and animals never sink into or hover over the ground; moving through caves is easy (capsule vs mesh, crouch to pass low gaps); ragdolls rest on the real surface.
PG3. [DONE] Distance: far terrain is drawn as cheap smooth meshes that keep the real silhouette, never square blocks (with F4).
PG4. [DONE] Objects as real shapes: tree trunks show their bark outside, never their inside; birch trees get real birch shapes (not random procedural sticks); fallen logs sit on the ground (none floating); pumpkins are round, and can be picked up instead of breaking apart; everything that looks boxy gets its real shape.
PG5. [DONE] Roads on smooth ground blend into each other and into the terrain.
PG6. [DONE] Port all content onto the polygon world: towns, bases, Capital sites, structures, caves, hell and the Reich layers, so a polygon world plays the whole game. Then make Polygon the default for new worlds.
PG7. [DONE] Creative mode: no damage to the player.

## PLAYTEST Oct 13 night (P221-P251): top priority with the polygon items
He played the 21:25 build (3148f425, before PR #112 merged the R/F/S batch) 21:27-22:02; notes in docs/playtests/2026-10-13/voice-notes.md after 21:27. Ragdolls (21:40), freezes (21:41, 21:57) and render-distance lag (21:52) may be covered by #112; check on the current build first.
P221. [DONE] [21:29] Explosions kill everyone inside the blast radius; nobody walks out of a rocket or shell hit.
P222. [DONE] [21:29-21:30] Capital tower base guns: too big for the base. Use a large variety of smaller naval/AA guns (he loved the small one at 21:30; do not just scale down the big gun). Some guns spawn without their top, half generated: fix the generation. Put a helicopter on a tower landing pad that he can steal.
P223. [DONE] [21:37] Opening his world has a very long wait before the loading screen: show the loading screen at once and cut the wait.
P224. [DONE] [21:38, 21:41] Blocks of the dropship are hard to break off; make breaking craft blocks as reliable as terrain.
P225. [DONE] [21:39-21:42] Wreck repair: "needs 299 lift balloons" is absurd. Size lift parts sensibly (a few balloons lift a craft), say where each part goes (propeller on the stern), and make cannon ammo obvious: where cannonballs load and how to get them.
P226. [DONE] [21:40] Crouch lets him pass under low gaps (repeat of 13:10).
P227. [DONE] [21:43] The gun inspect view (the one that shows a gun's details) is far too big.
P228. [DONE] [21:44] Strike-team ships make a loud, ominous engine sound heard from far away, as the warning that a strike is coming.
P229. [DONE] [21:44, with F4] In the block world the far chunks are too simple: they must still look like blocks from a distance (no mobs or detail needed).
P230. [DONE] [21:45] Pirates are their own faction, never the Capital.
P231. [DONE] [21:46] All random encounters (raids, strike teams, pirates, bounty hunters, convoys) are ultra rare: something a player sees after a long time and goes "wow, I've never seen that", never something to get used to. One global rarity pass.
P232. [DONE] [21:47] A Capital gun's inventory icon renders black.
P233. [DONE] [21:48] He could not scroll the craftables list.
P234. [DONE] [21:49] The titanium shovel digs faster (efficiency like a top-tier shovel).
P235. [DONE] [21:49] Dirt next to grass grows grass over time.
P236. [DONE] [21:50] Retaliation: after killing pirates at sea, a 50% chance they raid his home once; after robbing a base, a 1-in-8 chance it retaliates once. Only once each.
P237. [DONE] [21:51, H15] Shovelling snow must not fill the inventory with snowballs.
P238. [DONE] [21:52] Villagers walk on water.
P239. [DONE] [21:52, with SH1] Ice looks beautiful: mirror-like reflections.
P240. [DONE] [21:52] Input lag and general lag at render distance 17: performance must improve (with F1-F5).
P241. [DONE] [21:53] Rockets: he could not find how to make them; the crafting book shows rockets and their ammo clearly.
P242. [DONE] [21:54] Specialty bases, like GoldenEye missions: e.g. an ammo depot that supplies ammo for good once found, and other one-of-a-kind bases with their own speciality.
P243. [DONE] [21:55] A normal (non-futuristic) navy warship sailing the seas; also make sure the UNSC-like frigates can actually be found (he has never seen one).
P244. [DONE] [21:56-21:57] Some ground material, granite and gravel look cheap and blurry. Add to docs/art/image-requests.md a ranked list "blocks that don't look pretty enough" at the top, so he knows what to make first.
P245. [DONE] [21:58] Gold is an easy currency in villages, with more uses; no platinum (titanium covers it).
P246. [DONE] [21:59-22:00, with P79] Remove the spire for good (replaced by the duelling knight). Zombies look terrific; skeletons, golems and the creeper replacement need upgrades.
P247. [DONE] [22:00] Skeletons fall apart where the sword hits them.
P248. [DONE] [22:01] Safes in ground military bases, like GoldenEye: a key in a chest within about 100 blocks, or an ultra-rare reusable safe breaker (about 1 in 100 bases). Safes hold really good loot.
P249. [DONE] [22:02] He will try to beat the game next (hell, the Ash Vault, the final battle). Walk the whole completion path in code from his existing world and fix anything that would block finishing it. Gameplay fixes only, no test bots. Traced (Oct 14): his World376 sits about 19,300 blocks from the world centre, and the Ash Vault citadel (the Marshal, the last battle, the bunker) is under the centre, so breaking through where he plays means a 19 km march underground. The Ember Charge was loot only (Capital command rooms, fleet frigates he has never seen). Fixed: a forged Ember Charge (3 Titanium Ingots, 3 TNT, a gold block); the Wardstone hint, the charge toast and the goal say to go down near the world's centre and how far it is; the last few units of a battle wave glow and the toast gives their bearing after 25 s, so a straggler stuck in a trench can't stall the battle. Keeps, Sunderite, flux, the blast furnace, the seal, the vault fall and the bunker door had no blocker.
Praise, keep: smaller guns like the one at 21:30, the new village buildings, caves, fallen logs, the cannon, German gun names, grip-left now works, walking through double doors, snow and changing weather.

## NEXT BATCH (Remington, Oct 13 18:25): take after any open P item, in this order: R, F, S, Y, U, SND, SH, IMG, W, H, D
Remington accepted this list (S10 German and D53 online co-op left out). The realistic-world (ultracode) thread is stopped; its leftovers are U1 here and the main thread owns them. OBJECTIVES FIRST still applies: write your own fuller objectives for each item before building, and build the full version, not the literal minimum. ONE AND DONE and NO TEST WORK still apply.
R items are complaints he made two or more times after an item was marked DONE. Treat each as NOT fixed: find the real cause on the Quest path (QuestInput/OpenXR, the Quest renderer), not only the Mac or headless path, and rebuild it properly instead of tweaking a number. Note in the DONE line what was actually wrong.

R1. [DONE] Left grip / left stick dead while holding a gun (claimed by P74, P109, P162, P176).
R2. [DONE] Right-side control-hint UI still shows (P53, P85, P108, P143, P160): remove it entirely in play; the hints live in the tutorial (S6).
R3. [DONE] On the headset he cannot tell which menu tab or button is selected (P72, P140, P176).
R4. [DONE] Point the controller at the map and pull the trigger to set a waypoint (P73, P195).
R5. [DONE] Accidental crafts and misclicks (P10, P129); the thumbsticks must move the selection through inventory, crafting and menus.
R6. [DONE] Two-handed aiming (left hand on the gun, hold left trigger, aim like real life) and the Farsight scope on the device (P32, G21, P159, P82).
R7. [DONE] Loading a magazine from the hip is too hard: a forgiving snap zone at the magazine well, clear haptic/audio click.
R8. [DONE] Ammo: Greywall troops must not carry Capital rounds (P104, P196); loot and shop ammo match the guns each faction and town actually uses; he keeps running dry while "everything takes slate rounds".
R9. [DONE] Gun models: the six-iron looks nothing like one, and every gun model needs an upgrade (procedural geometry, period-correct, not futuristic).
R10. [DONE] Naval guns: a distinct gun per mount instead of one copy-pasted model, and real damage against crawlers and the Capital tower.
R11. [DONE] Melee: hits from every angle including bottom-up and targets below; several hits per second when swinging fast; damage from swing speed; the red hit mark stays on the target.
R12. [DONE] The sword strobes when swung (P77, P170).
R13. [DONE] Horse gallop feels like "a one-cylinder whipper snipper" (five playtests): rebuild the gallop gait, body/camera motion and hoof timing to RDR2 smoothness.
R14. [DONE] Horses: drop down two or more blocks, squeeze through 1-wide gaps and under 2-high gaps while mounted, push through small bushes, climb out of water onto equal-height land.
R15. [DONE] Ragdolls for every creature and person in the block world too (the realistic-world slice 3 covers the drawn ground); no body or animal ever hovers.
R16. [DONE] Mob variety much wider in speed, damage and toughness ("a lot more").
R17. [DONE] Water: one-block falls, water that conforms to block shapes, water spreading both ways instead of toward the drop. Lava: flows reliably, blocks can be placed into lava, items burn in lava, an on-fire overlay on the Quest, obsidian forms quickly.
R18. [DONE] Sky and far trees visible from underground (P4, P113).
R19. [DONE] Footsteps sound like mud; gravel sounds like punching water (P14, P118) (with SND).
R20. [DONE] Towns: wider paths for the house spacing, far more townsfolk lines that fit time of day and situation, an obvious emerald-to-cash exchange, a jail that looks and works like one.
R21. [DONE] Bounty hunters: much rarer, never underground, and a real fight when they come.
R22. [DONE] Structure rarity everywhere (ships 8x rarer was P190; check all) and a sweep for floating generation: pillars, rails, amethyst, grass, Capital trim over a void, citadels built over pyramids.
R23. [DONE] Factions kept apart and fighting each other; base troops spread through the base and actively hunting him instead of spinning in place.
R24. [DONE] Journal: every order, Capital log, note and pamphlet is kept and readable later.
R25. [DONE] The Blight boss hovers out of sword reach (old T3a, wrongly dropped as test work): it is a gameplay bug.
R26. [DONE] His existing world loaded without smooth terrain after being smooth; the polygon setting must stick per world.

F1. [DONE] The ~1 s freezes: the 60 s autosave encodes the whole world's block entities, maps (16,384 UInt32 as JSON), ships, populated and hives on the frame thread. Snapshot values and encode on SaveIO.queue, store map pixels in binary, unload block entities with their chunks. Log any frame over 250 ms with its stage to a file on the device so it can be matched to his notes.
F2. [DONE] MapFog writes mapfog.json every 10 s on the frame thread and grows forever: background, deltas or binary.
F3. [DONE] Pause/quit shows "Saving..." instead of a frozen frame while SaveIO flushes.
F4. [DONE] Far rendering (his idea): full chunks out to 20, then cheap rings out to 40 or more: merged low-poly heightmap meshes with baked colour, no entities or block detail, blended into the fog so the horizon looks great. Must hold 72 fps on Quest 3.
F5. [DONE] Over open ocean the view must be the cheapest case (he saw the render distance struggle on the water).

S1. [DONE] A chunk or world file that will not decode is renamed .corrupt and kept, never replaced by a regenerated chunk or an empty chest/mob list on the next save; tell the player.
S2. [DONE] Save errors (full disk, encode failure) are shown to the player, not swallowed by try?.
S3. [DONE] Rolling autosave snapshots (keep the last 3), fsync before rename, so a dead battery cannot corrupt a world.
S4. [DONE] Crash handling: a log file, and on launch "last session crashed, restore the last backup?".
S5. [DONE] Paid-app entitlement check (Meta Platform SDK); code in place, switched on once the store app ID exists.
S6. [DONE] VR first launch: standing / seated / reclined, comfort preset, dominant hand, height; then short in-world lessons for guns, horses, honour and law, money and shops, contracts. Replaces the flat-screen tips.
S7. [DONE] Touch controller presets and a left-handed swap in the headset.
S8. [DONE] Boundary appearing, recenter and tracking loss handled; the game saves on pause, headset off and Quit.
S9. [DONE] Draft docs: privacy policy, IARC age-rating answers, store listing text, comfort rating, credits and licences (docs/store/).

Y1. [DONE] The Goals path follows THE GAME'S SPINE: iron, take a village, Greywall bases, the navy, hell, the Reich. Remove the leftover reference chain (Ember Gate, Foundry, blaze rods, eyes, Stronghold) from the main path. (built in the Oct 14 batch: Spine.swift, Goals.swift.)
Y2. [DONE] Each stage hands over the key to the next: taking a town gives base intel; Greywall's top tier gives what opens the navy; the navy gives the hell key (the Ember Charge is only in Capital vaults today). (built in the Oct 14 batch: Spine.swift.)
Y3. [DONE] The navy comes before hell (FactionGear.swift: warships sail only after the end game today). (built in the Oct 14 batch: FactionGear.swift, Game.fleetSails.)
Y4. [DONE] Make it obvious which military force is the progression stage (Greywall) and which is the enemy over everything (the Capital). (built in the Oct 14 batch: Spine intro document.)
Y5. [DONE] Saved worlds get new content in unexplored ground: roads, base towns, railways, Greywall and wide streets currently skip old worlds, so his world never shows them. (built in the Oct 14 batch: FreshGround.swift.)
Y6. [DONE] Hook the side systems to the spine: money, contracts, the war map, legendaries and countries lead toward the next stage. (built in the Oct 14 batch: Spine.lead in Contracts, Countries, Legendaries.)

U1. [DONE] Realistic world leftovers from the stopped ultracode thread (read its design/status doc): animals walk on the drawn surface instead of hovering, blocks that refuse to smooth, polygon trees with real round branches, the pickaxe in the polygon world only mines what it touches. T17 is folded into this.

SND1. [DONE] Sound list: write docs/audio/sound-list.md, every sound event in the game (footsteps per surface, each gun, reloads, horses, every mob, weather, water, UI, vehicles, ships, ambience per biome), one line each on what it should sound like, and mark the 40 worst current synthesized sounds. All ~1,000 sounds today are synthesized in code; real recordings will replace them, so keep file names stable.
SND2. [DONE] Drop-in pipeline: any file placed under Resources/Sounds/real/<name> overrides the synthesized one by name, loudness-normalised to the levels in audio_levels.md, with random pitch/volume variation and 3-5 variants per event where it repeats (footsteps, gunshots, hits).

SH1. [DONE] A prettier shader pass inside the 72 fps budget, each piece switchable: grass, leaves and crops waving in the vertex shader; water with Fresnel sky reflection, sun glint and shoreline foam; warm sun and cool sky ambient with sunrise/sunset tint; fog with sun glow (in-scattering) and low valley fog; blob contact shadows under mobs, players and items; emissive glow halos for torches, lava, lamps and ores; colour grading per biome and time of day; specular sheen on metal, ice and wet surfaces. Look at what good Quest 3 titles and Minecraft shader packs (BSL, Complementary) do first. No real-time shadow maps unless a near-field one fits the budget.

IMG1. [DONE] Image request list: write docs/art/image-requests.md listing every image the game still wants (the 268 AR1 block layers, AR2 items, icons, paintings, posters, signs, UI art, the Upgrade Bench), one line each: file name and path, size, what it shows, a ready-to-paste prompt and the style reference. Remington's Gemini account will generate them; the Mac drops results in. Do not try to generate images in the cloud thread.

W1. [DONE] Circuit state is never saved: pending ticks, edges, burn, hopper cooldown and comparator output reset on reload, so buttons stay pressed, powered observers stay on, and bulbs/dispensers/droppers/crafters fire falsely. Save it per chunk or keep POWERED/TRIGGERED in the block state. (built in the Oct 14 batch: Circuit.swift save.)
W2. [DONE] Copper doors and trapdoors respond to power; both door halves age, wax and scrape together; an axe opens them unless sneaking. (built in the Oct 14 batch: Circuit.swift.)
W3. [DONE] Lightning rods: rebuilt on load and pruned on break, nearest rod within 128, signal 15 for 8 ticks when struck, no fire on top, can face 6 ways. (built in the Oct 14 batch: Circuit.swift, Weather.swift.)
W4. [DONE] Comparator readings: crafter (filled or disabled slots), double chests as one 54-slot inventory (hoppers too), cauldron, beehive/nest, chiseled bookshelf, decorated pot. (built in the Oct 14 batch: Circuit.swift.)
W5. [DONE] Pistons with a 2-tick moving block so flying machines, piston doors and block spitting work; pistons push item entities; slime bounces, honey slows; glazed terracotta does not stick; copper doors break when pushed; world height limits respected. (built in the Oct 14 batch: Circuit.swift.)
W6. [DONE] Rails: powered T-junction switching, connected rails keep their shape, junction priority; hopper minecart pulls from containers above and empties into hoppers below; activator rails disable hopper carts and eject riders. (built in the Oct 14 batch: Rails.swift, MinecartVariants.swift.)
W7. [DONE] Crafter: disabled-slot toggling, hoppers fill slots evenly, output into any container, bottle and bucket leftovers. (built in the Oct 14 batch: Crafter.swift.)
W8. [DONE] Dispenser behaviours: fireworks, tipped/spectral arrows, waxing copper, golem building, armour stands, saddles and horse armour, respawn-anchor charging, fish and powder-snow buckets, every minecart type.
W9. [DONE] Sensor (sculk equivalent): vibration frequencies, the calibrated sensor, wool blocking, comparator frequency output. (built in the Oct 14 batch: Circuit.swift.)

H1. [DONE] Cave mobs spawn about 10 blocks farther away.
H2. [DONE] Ravines and more cave styles.
H3. [DONE] Titanium needs a blast furnace.
H4. [DONE] Salvage the frigate's gun.
H5. [DONE] A Capital weapon printer built from parts taken at several bases.
H6. [DONE] City buildings with a readable purpose; copper and power in cities.
H7. [DONE] The shock weapon is as strong as it looks.
H8. [DONE] Less surface water.
H9. [DONE] Boats: see yourself in the boat, the boat model matches its icon, storms at sea.
H10. [DONE] Horse bonding raises stamina and health, with RDR2-style cores in the UI.
H11. [DONE] Vehicle damage physics.
H12. [DONE] Hands can grab and move anything physical, not only small animals and carcasses.
H13. [DONE] Base guns built of blocks, with a gunner already seated under the gun (kill him to take the seat), destroyed block by block; leaving the seat never drops you outside the base.
H14. [DONE] Townsfolk have homes and beds.
H15. [DONE] Snowballs clogging the inventory.

D1. [DONE] Lasso: catch wild horses, rope outlaws.
D2. [DONE] Wild horse herds, rare coats, a legendary horse.
D3. [DONE] Hitching posts in towns. (built in the Oct 14 batch: Hitching.swift.)
D4. [DONE] Wagons and stagecoaches: escort contracts and robberies.
D5. [DONE] Melee from the saddle.
D6. [DONE] Holsters on the body; draw from hip or chest.
D7. [DONE] Working levers, bolts and revolver hammers; shotguns loaded shell by shell (unblocks C5 in the cloud).
D8. [DONE] Dual-wield revolvers.
D9. [DONE] Suppressor attachment and gun cleaning at camp.
D10. [DONE] Bandits and soldiers who block and parry; an off-hand kick or shove to break guards.
D11. [DONE] Throwing knife and tomahawk.
D12. [DONE] Silent knife takedowns from behind.
D13. [DONE] Fist brawls in the saloon (non-lethal knockouts).
D14. [DONE] Frontier predators: cougars, rattlesnakes, alligators.
D15. [DONE] Monsters hear gunshots and investigate; night hordes that stalk and surround.
D16. [DONE] Bandit gangs that use cover and flank.
D17. [DONE] Saloon bartender with drinks (mild, comfort-safe) and a piano player.
D18. [DONE] The knife-between-the-fingers game and poker.
D19. [DONE] Hotel rooms: paid save, heal, bath.
D20. [DONE] Stranger side stories with recurring characters.
D21. [DONE] Townsfolk react to his deeds and how he looks (bloody, armoured).
D22. [DONE] Bandana mask: masked crimes cannot be pinned on him.
D23. [DONE] Catch a fleeing witness before they reach the sheriff.
D24. [DONE] Bring bounties in alive (lasso, hogtie) for double pay.
D25. [DONE] Arrest, jail time and an escape option.
D26. [DONE] Named gang leaders with hideouts.
D27. [DONE] A fence for stolen goods; shops refuse flagged items.
D28. [DONE] Buy a homestead or a town house.
D29. [DONE] Mail-order catalog for rare items.
D30. [DONE] Late-game money sinks tied to the spine: vehicle presets, base upgrades, hired crews.
D31. [DONE] Gunsmith bench that assembles guns from parts (receiver, barrel, stock tiers).
D32. [DONE] Upgrades that change behaviour (ricochet rounds, serrated bleed), not just stats.
D33. [DONE] Wearable faction armour sets (Greywall, Capital, Ashguard).
D34. [DONE] Base objectives: destroy the comms array, steal the plans, free a prisoner, for bonus loot or intel.
D35. [DONE] Keycards, locked doors and security cameras.
D36. [DONE] Bodies found raise the alarm; stealth plays differently from going loud.
D37. [DONE] Disguise in a looted uniform to pass through base towns.
D38. [DONE] Lost bases counter-attack; alarm state survives a reload.
D39. [DONE] Naval ports and dockyards to raid; buy and repair hulls there.
D40. [DONE] Hire a crew to man ship guns.
D41. [DONE] Broadside battles and boarding by grapple.
D42. [DONE] Aim the Field Tank turret from the helm.
D43. [DONE] Vehicle presets unlocked by blueprints per stage.
D44. Fuel depots; recall or garage a vehicle.
D45. Deer, elk, bison herds and boar.
D46. Bait and wind, tracks and blood trails, snares.
D47. Vault side objectives, the armoured train robbery, a boss bar on the Quest HUD.
D48. Landmarks: canyons, ghost towns, homesteads; biome-specific settlements.
D49. [DONE] Blizzards and sandstorms that cut visibility, body temperature, lightning risk to riders.
D50. Ride train roofs and climb between cars; defend against holdups.
D51. Track one objective with a HUD marker and an in-world beacon; contract and bounty markers; horse, ship and vehicle markers; notes stamped on the map.
D52. Co-op: share a horse or vehicle with gun seats, shared contracts and bounties, revive a downed partner.


## MOVED FROM THE MAC (Oct 11): take after the P and G items
Q1. [DONE: Lane A thread, 2026-10-12, PRs #50 and #51; docs/status/done-audit.md covers every done task since Oct 8 with MET/PARTIAL/MISSING, small gaps fixed, the rest as G items.] Finish the done audit (Mac task 25b6, unfinished): complete docs/status/done-audit.md for every task marked done since Oct 8 (MET / PARTIAL / MISSING per requirement, scale words count), fix small gaps directly, add big gaps here as G items.
Q2. [REWRITTEN by Remington, Oct 13: no measuring, no scorecard, no verifier] QUALITY AND POLISH LOOP, never ends: when every item above is DONE, loop forever through: (a) bugs and rough edges from all his voice notes in docs/playtests/, (b) the thing a player would notice most (looks, feel, sound, clarity, prettiness), (c) making it ready to sell. Never stop; never declare the backlog finished. Each pass: pick the thing a player would notice most (looks, feel, sound, clarity), improve it in one pass, push, merge, next.

## THE GAME'S SPINE (read first; every item serves this)
Play by the rules until you have iron, ideally diamond. Then you can take a village. Then the military bases (rare, tiered, GoldenEye-style), then the navy and its frigates, then hell, then the Reich below hell. Killing the Reich's leader beats the game. Gear tiers, tool upgrades and vehicles are the keys between stages.

FROM THE OCT 11 AM PLAYTEST (Remington on the Quest, build 0.129; check each against current claude/quest-port first):
G12. [capitals] [DONE: Lane A thread, 2026-10-11, PR #49; docs/status/tidebreaker-gaps.md] Capitals are far too common (two within 500 blocks) and one sat at the player's spawn with a crawler; make capitals rare, never near spawn, and procedurally varied in size (a pool of capital buildings where only some spawn per city).
G13. [frigate, with G1] [DONE: Lane A thread, 2026-10-11, PR #49; docs/status/tidebreaker-gaps.md] The naval/main gun does far too little damage: against a crawler it should tear off a huge chunk or destroy it outright. Ships should not carry Capital soldiers: the frigates are their own navy faction (A3).
G14. [done, Lane A, 639959b + G20 PR: two stone cells with iron doors, bunks and chains (check frontier: jail cell behind bars and an iron door); emerald tip, BANK signs and a town board line (check G14 emeralds)] [towns] The jail is broken (find what is wrong in a town jail and fix it). Emerald-to-cash is undiscoverable: make the bank exchange obvious (signs, a tip, a notice board line) and make emeralds findable in survival (where they come from, documented in the recipe book or a tip).
G15. [done, Lane A, 639959b: check G15 sheriff] [towns] Stealing a gun from a townsperson must be very hard before iron armour (the six-iron rule); verify the sheriff/deputies respond and the gun is guarded.
G16. [done, Lane A, 639959b + G20 PR: 16 health, 2.0 s fuse, 0.8 s setback a hit (check G16 Powderwight)] [mobs] The Powderwight is too hard to kill before it detonates, even with an iron sword; tune its health, fuse or telegraph so a prepared player can win.
G17. [done, Lane A, 639959b: hell's rock rises through the deep layers, hell-only spawns (check deep G17)] [hell] Entering hell from above ends at a lava-pool cut-off; make the transition from the deep rock into hell gradual and readable. Hell mobs must be hell's own types everywhere (check B6 covers all spawns).
G18. [done, Lane A, 639959b: grass in patches with tall tufts (check G18 grass patches, plants)] [looks] Plain grass looks barren: add more ground cover (tall grass tufts, short grass that rises slightly off the block, variety) within the Quest frame budget.
G19. [done, Lane A, 639959b: docs/status/difficulty.md (check G19 difficulty)] [new, Lane B] Difficulty levels: easy, medium, hard chosen when creating a world and locked afterwards; they change enemy speed, damage, health, hunger and spawn density. Document the table.
G20. [done, G20 PR: OriginalSites.swift; docs/status/ip-content-audit-oct11.md] [IP, from P19] Replace the remaining close copies of reference features with original designs (docs/status/ip-content-audit-oct11.md: the Hollow + Hollow Spire + Void Dragon, Cinder Fortress / Boarling Keep, Sea Temple, Forest Manor, Proving Halls). The murk depths, Buried Citadel and Deep Stalker summons are already out (P19).
G21. [done, PR #50: VRScope.swift, a 4x zoomed eye view with a lens mask and the impact reticle; check vrScope] [guns, from P32] The Farsight rifle has no VR scope: raising it to the eye should show a magnified scope view (a render-to-texture lens on the scope, or a zoomed overlay on the eye nearest it), with the reticle matched to where the round lands.

## LANE A (cloud thread A): factions, bases, navy, vehicles

A1. [done, Lane A PR #52, docs/status/greywall.md; leftovers T6] Military bases as their own faction (separate from the Capital). Intent: castle-like fortified bases, confined to the base, tiers of bases like GoldenEye N64, very rare, naval guns and small turrets, ranked troops.
- 4+ base tiers: outpost, garrison, fortress, command fortress; each larger, rarer, better defended and better looted. Original layouts; the grey-concrete, blue-corner-light, metal-door feel of the Siberian levels is the art direction.
- Walls, gatehouses, towers, bunkers, barracks, armoury, comms room, motor pool, vault. Alarms with red lights; reinforcements arrive while the alarm is up; alarm panels can be destroyed.
- Turrets: small auto-turrets on walls and corridors, and coastal or naval guns (several calibres) at shore bases, all with readable telegraphs, line of sight and destructible states.
- Troops never leave the base footprint (leash), but chase within it and call for help.
- Each base has a map table that, once taken, reveals other bases on the map (the radar network).
- Taking a base: kill or drive out the garrison, take the command room, the flag changes; it stays yours and can be used as a home, with respawn rules documented.
- Rarity tuned so a walking player finds one in a long session; a frigate makes them reachable.

A2. [done, Lane A PR #52, docs/status/troop-classes.md; leftovers T7] Troop classes. Intent: three classes, Regular, Spec Ops and Hannibal troops (unless that name is a problem; Hannibal is historical, check the coined list anyway), each with its own armour level that gets damaged over time, its own class of guns, and rarity rising with the level.
- Armour as segmented durability (helmet, chest, legs) that visibly cracks and falls off; damaged armour lets more damage through; players can loot damaged sets and repair them.
- Weapon classes per troop: regulars with rifles and SMGs, spec ops with suppressed and scoped weapons plus grenades, Hannibal troops with heavy weapons and the best armour. Loot rarity tiers (common, fine, rare, elite) with stat ranges.
- Behaviour per class: regulars patrol and hold, spec ops flank and use stealth, Hannibal troops push and suppress. Mixed squads with an officer.
- Balance against player gear tiers; write the time-to-kill table.

A3. [done, Lane A PR #52, docs/status/navy.md; leftovers T8] The navy (the frigates' faction). Intent: frigates are the UNSC-like faction with super soldiers with shields, done without infringing.
- Rename everything player-visible to our own navy (keep the Meridian name if it is already ours). Super soldiers get an original name (not Spartan) and regenerating energy shields that flare, pop and recharge after a delay; shield breakers (EMP-like weapons) as counters.
- Frigates patrol the seas, have radar, launch boarding parties and small craft, and bombard shore positions; frigates can be boarded and captured.
- A captured frigate becomes the player's fast vehicle with radar that shows bases and ships in range.

A4. [flyers done, Lane A PR #52, docs/status/flyers-a4.md; the crawler still open: T9] Vehicles that fly, and the crawler. Intent: ways to make vehicles that fly; the crawler needs to be perfected.
- Finish the free-moving block structures engine (old PR 8) so players can build aircraft from blocks: engines, lift surfaces, control seat; weight and thrust matter. Plus at least one craftable ready-made flyer for players who don't want to build.
- VR comfort for flight: cockpit frame, vignette, horizon lock option, snap or smooth turning.
- The crawler: smooth movement on all terrain, no clipping or jitter, sensible speed and weapons, boarding and exiting in VR, damage states, repair.
- Vehicles persist in saves and are found where you left them.

A5. [done, Lane A PR #52, docs/status/map-fog-a5.md] Radar and discovery. Bases reveal other bases; frigates have radar; a map and compass that show discovered sites, with fog of war.

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
M3. [Mac/headset only: cloud threads skip] [Checklist written 2026-10-11: device-checklist.md section 3; needs the headset] Device feel for the lanes above: flying, crawler, frigate radar and VR melee against knights, checked on the Quest.

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
C1. [B] [DONE: Lane A thread, 2026-10-12, docs/status/railways.md; questcheck --rail-only] Railways (procedural, rare): rail lines generated with the world, linking several villages and towns, so finding one is a big find: it is fast travel to many places. Generation must be robust: lines follow terrain with cuttings, bridges and tunnels, stations only at real villages, never through structures, never floating; a worldgen check over 50 seeds proves it. Steam trains run the lines on a timetable; you can ride, and RDR-style train robberies (stop the train, crack the strongbox, outrun the posse) carry honour and bounty fallout. Armoured trains in the Ash Vault.
C2. [A] [done, Lane A PR #52, docs/status/war-map.md; leftover T12] The living war map, procedural only: factions hold generated territory and front lines shift over in-game weeks from simulation, not hand-placed events; battles happen without you; your actions tip them; a war table in captured bases shows it. If it can't be made fully procedural and stable, drop it and say so.
C3. [B] [DONE: Lane A thread, 2026-10-12, docs/status/nation.md; questcheck --nation-only] Your own nation: villages and bases you take become provinces; settlers arrive, build and farm; you set taxes and laws; they need defending; your flag on the map; a capital you design.
C4. [B] [DONE: Lane A thread, 2026-10-12, docs/status/villager-mind.md; questcheck --mind-only] On-device AI villagers (placeholder): define a clean interface (VillagerMind) that a small language model can drive for dialogue, opinions and daily choices, running on the device's neural engine or NPU when available (Apple Foundation Models on Mac, the Quest's NPU later), with today's scripted behaviour as the fallback. Ship only the interface, the scripted implementation and a stub; no model yet.
C5. [M] Physical VR crafting and guns: hammering blades on the anvil, sharpening, fitting gun parts, physical reloads (drop the mag, seat a new one, rack the slide), holstering on the body; always with a seated or Reclined shortcut.
C6. [A] [done, Lane A PR #52, docs/status/radio-spoofing.md] Radio spoofing: at a military base's radio room (or a Capital comms post), pose as the garrison and request help. Other bases of the same faction actually send it: supply drops or a truck convoy (military), a frigate strike on a map grid (Capital or navy). It only works for a while: a suspicion meter rises with each request and with odd requests; when they find out, the faction goes on alert, sends a hunter squad and stops answering that radio.
C7. [A] [done, Lane A PR #52, docs/status/sky-isles.md] Airships and a sky layer: the Capital's armoured airships patrol high above; board one with a flyer or a grapple; a small cloud-island layer mirroring the Deep below, with its own loot.
C8. [A] [done, Lane A PR #52, docs/status/submarines.md; leftovers T13] Submarines, wrecks and mines: build or capture a submarine; sunken warships and treasure wrecks to dive; naval mines and torpedoes; the navy hunts you with sonar.
C9. [B] [DONE: Lane A thread, 2026-10-12, docs/status/seasons.md; questcheck --seasons-only] Seasons: spring to winter over in-game weeks; lakes freeze, snow on trees, crops by season, animals migrate, hunting seasons, town festivals.
C10. [DONE: Lane A thread, 2026-10-13, docs/status/legendaries.md; questcheck --legends-only] [B] Legendary weapons and armour: named one-off items from bosses, legendary animals and command fortresses, each with a story, a look and a unique perk; a gallery in your base.
C11. [DONE: Lane A thread, 2026-10-13, docs/status/contracts.md; questcheck --contracts-only] [B] Jobs and contracts: notice boards in towns, bases and countries with procedural jobs (escort, delivery, bounty, clear a camp, defend a town) paying money and reputation.
C12. [DONE: mining towns (Sources/MiningTowns.swift; --mines-only 10 ok; docs/status/mining-towns.md)] [B] Mining expeditions replace genre-style abandoned mineshafts: real working mines attached to big villages (mining towns), with dynamite, mine carts and rail, supports and cave-ins, gas pockets and lamps, miners, and deep veins worth an expedition.
C13. [DONE: town sizes (Sources/TownSizes.swift; --sizes-only 4 ok: 278/70/34/12/4 over 50 seeds; docs/status/town-sizes.md)] [B] Village size variety: village sizes span hamlet, village, town, large town and city, with rarity scaling exponentially (each size roughly 3 to 4 times rarer than the one below). Bigger places get more shops, a mine, a rail station if a line passes, more law. Check the size histogram over 50 seeds.
C14. [DONE Oct 13: Play Together over Wi-Fi (pause menu): host this world or find/join a friend's (LAN beacon or typed address). The host owns the world (blocks, chests, mobs, time); the guest owns its body, inventory and health, sees the host and the host's mobs, and its edits, hits, pickups and kills sync both ways (Sources/NetLink.swift, NetCoop.swift; questcheck --net-only). Part 2 (NetShare.swift): the host's vessels mirror for the guest (ride along on deck; the host steers), the guest rides the host's horses (moved over the link, the host's AI resting), and the guest's thefts, assaults, gunfire and mob uses (rider satchels, strongboxes) run on the host's towns, so robberies are shared. Capital ships are not sent; trade screens open on the host only.] [A+B, last] Two-player co-op on Quest: a friend joins your world (host-authoritative), shares horses, vehicles and robberies. The biggest sales driver on Quest and the biggest job, so it goes last, after the single-player game is store-ready.

## FOR THE TOWNS LANE (from the Mac worker, task 25b4zxxxx, 2026-10-11)
T1. [done, Lane A, G20 PR: townsfolk swings at the player use Game.meleeGap (check T1 townsfolk melee)] Hostile townsfolk melee reaches the player's real body: Townsfolk.swift ~line 238 tests the centre distance
    (`dist < w.reach + 0.3`, feet height window 2.5) so an angry townsperson can't hit a player on a 2-block step and
    can hit one standing on a pillar. Monsters now use `Game.meleeGap(_:)` (VRMelee.swift: feet to headset, only the part
    level with the mob); use the same helper for townsfolk swings. Check: `--swingtest` covers the monster side.
T2. [DONE: questcheck --towns-only 309 of 309 ok on quest-port after C13; the 20 town reds no longer reproduce; the one new red (the law check took pieces.last as a lot, the C12 mine's head frame came last) fixed by putting the mine's pieces before the lots] questcheck on CI run 38158315397 (HEAD 9b91522d) fails 20 town checks: voices (greets 0 times), honour (theft heat,
    $0.00 bounty), bounty (law never challenges, lapse day), honour HUD/meter/inventory, six-iron hit rate, countries
    ore. Towns-lane code; the Mac worker did not touch it. Reproduce: quest/tools/linux-check.sh then questcheck.
T3. [DROPPED by Remington, Oct 13 08:10: no time on making test bots or automated checks pass; one and done. Skip this item.] Mac heavy lane reds that are red on claude/quest-port too (run 930 on bfb3f14, still red on PR #49's run 940), left
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
T4. [DONE: the patrol marches on one searched path (77 cells) and reaches the spot 40 blocks out at -456,920 in 58 s, then returns (`questcheck --basetest-only patrol`, Oct 13). Fix the gameplay: patrols follow paths that exist. Do not chase the test.] Citadel patrols give up where a path exists (PR #49 heavy shots red, `--basetest patrol`; Linux repro:
    `questcheck --basetest-only patrol`). G12 moved seed 12345's nearest citadel to -456,920. A gunshot 40 blocks south of
    its gate: PathFinder.find (8,000 nodes) walks gate -> spot, but the patrol leader stops 36 blocks short ("no way on")
    after ~4 blocks: basePatrol (CapitalBasesWork.swift) orders 18-block waypoints at `standY` ground and the soldier's
    own search gives up on them. Fix the class: a patrol follows one long path (or waypoints taken from it), and the
    test's "reaches the spot" passes at this citadel and the old one.
T5. [Left for lane M: needs a headset look, nothing for the cloud lane to build.] P18 water falling one block (Oct 11 playtest, "looks weird from the side"): time-boxed in the cloud (Lane A,
    2026-10-12). `questcheck --view OUT.png --scene waterstep --at 0,230,0 --look 0,-15` now settles real water over a
    one-block step (fluid steps run directly; the old scene never flowed). Seen from three angles the drop renders as
    the reference does (the cell under the edge is full height, the spread slopes from it); the one oddity is the
    shallow rim's side faces reading as separate dashes along a diagonal edge. No defect pinned; needs a headset look
    (lane M) with the scene above to say what "weird" is.

T6. [DONE Oct 13: alerts wake only their own faction, turrets aim at every split-screen seat, squads arrive by truck on the road, two corridor turrets in fortress and up, shore bases mount light quick-firers on each sea wall (and heavy tower guns below fortress); the distance statistic and capture harness skipped as test parts] [A1 leftovers, Greywall Command] Coastal guns of two calibres at shore bases (the tower deck guns stand in);
turrets at corridor corners; reinforcements by truck (they come on foot); the nearest-outpost distance over 20 seeds
(sampled on 3); an end-to-end capture of a generated base in the harness (the scan of every generated tier is checked,
the hold is checked on a stand-in); soldier alerts wake every faction near a base (Soldiers.alertGarrison, older than
A1); wall turrets track the first split-screen player only.
T7. [DONE Oct 13: gun grades Common/Fine/Rare/Elite with damage, recoil and reload ranges (ItemStack.grade, saved as "q") from soldier drops by class and base chests; Capital classes by post (Hannibal only on the citadel's heavy posts, about 15 % Spec Ops); officer-led mixed dropship squads; Spec Ops crouch to shoot; plate takes arc beams and blasts; worn colours for the class pieces; the TTK table skipped as a test part] [A2 leftover, troop classes] Gun rarity tiers (common, fine, rare, elite with stat ranges): ItemStack has no free
per-stack field for it (tag is the loaded rounds), so it needs a save-format addition; the armour pieces carry rarity
through their durability meanwhile. Also from the A2 review: Capital troop classes by post (Hannibal only at
fortresses, command fortresses and citadel vaults, about 15 % Spec Ops on Capital posts; today every Capital ironclad is
Hannibal and every marksman and officer Spec Ops), officer-led mixed reinforcement squads, a crouch pose for Spec Ops,
the time-to-kill table measured through Mob.hit with the real items (class x gear) in docs/status/troop-classes-ttk.md,
plate on arc beams and explosions, worn colours for the class armour pieces, helmets shot off leaving a face.
T8. [DONE Oct 13: Meridian and Stormwarden warships over the sea with nothing in sight shell the nearest Greywall base or Capital citadel; boarding parties come by launch (the troop-drop path) at 60 blocks, only onto dry ground, their count saved per region; Aegis Marines a fifth taller and a third faster; a rising tone on the shield recharge; the radar check skipped as a test part] [A3 leftovers, the navy] Frigates bombarding shore positions and launching small craft (boarding parties are in).
From the A3 review: boarding parties through the troop-drop path, never over open water, at 60 blocks, their count
saved; Aegis Marines bigger and faster than troopers; a rising recharge tone; a radar check that pilots a captured
frigate end to end.
T9. [DONE Oct 13 (gameplay part): a crawler whose driver is dead can be taken at its helm and driven (throttle and steer, following the ground); steel or iron ingots used on it rebuild a damaged wheel or restart and rebuild its engines, and it drives again; terrain jitter and VR boarding left for the Mac worker's device testing] [A4 leftover, the crawler] Crawler polish: terrain jitter and clipping, VR boarding and exit, repair after
capture. Needs the Mac ride check (`--ridecheck`, Metal only) and device testing, so it was not changed blind.

T10. [DROPPED by Remington, Oct 13 08:10: no time on making test bots or automated checks pass; one and done. Skip this item.] PR #51 Mac heavy-lane leftovers after its 30-minute time-box (Lane A, 2026-10-12). Fixed in #51: the G20 stronghold
    check (it read terrain without structures), the hollow gate stage (the open gate took the player through before
    the frames were read; the trip back left a portal cooldown), the Deep death loop (armour worn out by the Blight
    fight), the gun and ammo count. Left, each needing its own look on the Mac lane (Metal-only checks):
    a. tours: `padtest` 6 fails on #51's run (not reproduced on Linux; compare with the base's tours run first).
    b. shots: `towntests` line 69 newly gated on #51's run; the Linux towns slice is green on the same code.
    The Blight fight (T3a) stays red as on claude/quest-port.

T11. [DONE Oct 13: a frigate with a sky isle within 700 blocks of its home circles the isle instead of home, and every frigate counts an isle under or ahead of it as ground for its cruise clearance; the structcheck pass skipped as a test part] [C7 leftover, sky isles] The Capital's airships keep their own routes: a frigate patrol that circles a sky isle at
cruise clearance, and a structcheck pass that walks an isle's top (the shrine floor and the turf rim).

T12. [DONE Oct 13: near an active front two squads of the warring countries meet and fight (FrontBattles.swift); both hold fire at you until you hurt a side, the winner gains strength on the war map (more when you fought for it); wars away from you are fought every day too. The military factions on the war map stay as they are] [C2 leftover, the war map] Battles you can join: soldiers of both countries meeting on the front line near you
(today the battles are simulated, heard and seen as guns and smoke); the military factions (Capital, Greywall, navy)
holding ground on the war map; wars far from the player keep going while away.

T13. [DONE Oct 13: a blown radio cover sends the hunters by a two-truck convoy (on foot where no road reaches you); a fire mission goes to a frigate of the faction in range when there is one (three missiles, red smoke); the alert and crates still in the air are saved over a quit; navy submarines hunt over deep water with torpedoes and surface to be claimed when holed; a pinging frigate runs to the last ping; the kit has its own icon; moored mines sit in water (waterlogged); the map fog is saved with every quit or pause save. C7 rode with T11. Test parts skipped] [Gameplay parts only; skip every test/check/verifier part] [C6/C8/A5 verifier leftovers, Lane A PR #52] C6: a truck convoy as the military answer (crates come by air), the
fire mission from a real frigate (today the faction's artillery), the 10-minute alert and crates in flight saved over a
quit. C8: enemy submarines you can capture, the pinging frigate steering to the last ping, the kit's own icon, generated
mines sitting in a dry cell inside the water. A5: the map fog saved on quit (every 10 s today). C7: frigates over high
ground keep clear of sky isles (with T11).
T14. [DONE Oct 13: heavy far noise at a Capital citadel now sends a dropship, no crawler rolls out; the rest cooldown is per world (Game.restedAt). Test-only parts skipped] [Gameplay parts only (e.g. crawlers no longer fight for the Capital); skip every 'no test of' part] [PR #56 verifier leftovers, Lane A, 2026-10-12] P69: crawlers still fight for the Capital ("crawlers aren't Capital either"); P87: only the rider chance went up, nothing checks roads near villages in World376; P91: no test of berm seams across chunks; Game.restedAt is static (the rest cooldown carries across worlds in one session).
T15. [DONE Oct 13: the Corsairs, a sea faction (Pirates.swift): beached wrecks are often corsair camps, a Corsair Sloop (cannon forward, three corsairs, a treasure chest) raids the coast near you and puts a party ashore; a ship cannon beside a computer of the same hull is an auto-turret; a broken wreck will not raise until her open bow is built back up to the deck] [P93 leftovers, Lane A, 2026-10-12] Pirates as a sea faction (crewed wrecks, raids from the water); an auto-turret on a ship (cannon + computer aboard); patching a wreck's open bow so it floats (today only rotten planks gate raising).
T16. [DONE Oct 13: Reckoning soldier bands near the player come down by dropship (up to six), the Stormwarden band brings a warfrigate. Test parts skipped] [Gameplay parts only (e.g. dropships and navy in the Reckoning); skip the Tests part] [PR #56 verifier round 2 leftovers, Lane A, 2026-10-12] P98: no dropship arrivals or navy ships in the Reckoning; Greywall alarms still sound after peace (by design: you broke in). Tests: the trains test uses p44 off as "old ground" (not a real legacyP95 guard) and accepts any solid bed; the wrecks test raises a raft, not a generated wreck, and calls useCannonballs directly; the reckoning test buries the player in rock for "underground" and checks peace as a flag, not that hunters, raids and patrols stop.
T17. [FOLDED into U1, Oct 13] [Cloud: smooth trees and smooth water only; Quest fps measurement is the Mac's] [P106 leftovers, Lane A, 2026-10-12] Polygon terrain: measure fps against block terrain on the Quest (Mac worker, device); smooth trees (Mac worker, tree looks); water as a smooth surface; relaxation costs about 40% more mesh time a section in the debug build, worth a look if streaming stalls on the device.

## ART LONG TAIL (non-blocking notes from the 25b4zzz art-gaps done gate, 2026-10-11)
AR1. [BLOCKED in cloud threads, Oct 13: the cloud Gemini key is on the free tier, which allows no image generation (HTTP 429, quota 0); needs the Mac with CHROME=1 as noted, or billing on the key] 268 block layers still procedural (workblocks, sculk, copper bulbs/chests, coral, Steelhold/capital/frigate
     panels, ship parts): list in docs/status/art-style-remaining.md. Needs Gemini sheets (Mac, CHROME=1).
AR2. [BLOCKED in cloud threads, Oct 13: same Gemini free-tier block as AR1. Checked: the torch_top/torch_bottom variants are all in Resources/Textures now; cave_vines, cave_vines_lit, weeping_vines and twisting_vines are the four still procedural] cave_vines, weeping_vines, twisting_vines and the torch_top/torch_bottom variants are still procedural.
AR3. [DROPPED, Oct 13: evidence snaps are test work; skip] Add a snap with XP set so the xp_bar fill is seen in evidence; check its stripes read as a tube at 3 px tall.
AR4. [Mac/headset only: cloud threads skip] Beds read as a thin flat slab in the Mac family gallery; check them at play distance on Quest.
AR5. [SKIPPED Oct 13: an evidence shot (test work) and Metal-only] Close-up tiled shot of nether_quartz_ore / deepslate_diamond_ore to confirm the seam blend.
AR6. [DONE Oct 13: weighed in docs/status/texpack-size.md: 17 copies cost 88 MB of git history; build it at Quest build time instead, and ASTC 6x6 would cut GPU memory 80 -> 9 MB; both Remington's call] texpack.bin grew 12.9 -> 18.6 MB; weigh it for the repo and Quest download (ASTC is Remington's call).
AR7. [DONE Oct 13: the rule heads assets/CREDITS.md] Save each Gemini prompt verbatim in assets/CREDITS.md going forward (s23-s28/p03/i20 record pattern + cells only).

## FROM THE DONE AUDIT (task 25b6, 2026-10-11; items G1-G11, renamed from A1-A11 so they are not confused with Lane A; full tables in docs/status/done-audit.md). Whichever cloud thread is free takes these FIRST, before new lane items.
Cloud-lane areas, worst first. Each line is a gap an independent reviewer found against a task already marked done.
G1. [frigate gun, FIRST] [DONE: Lane A thread, 2026-10-11, PR #48; docs/status/tidebreaker-gaps.md] The live helm shot never fires: `--questbugs --only maingun` fails 6 checks on fa79ef5e
    ("charges for 5.56 s", 0-block crater, 0 coil thumps, 0 shake). Tests that call mainGunTick directly pass; the
    g.tick path doesn't finish the charge. Also make FactionTests.swift:77 fire a real slug instead of Explosion.crater.
G2. [DONE: merged as PR #47 (86427fd), 2026-10-11; rows D3b, D3c, D5, DE8-DE11 MET in docs/status/the-deep-expansion.md; checked by Lane A 2026-10-12] [the Deep] D2 vault pass never merged (garrison towns, rail, airfield + AA, mortar pits, foot patrols, saved
    vault-wide alarm, reinforcements, crew bail-out DE9, radio/story DE11). This is the "far under spec" part.
G3. [DONE: PR #47: AshArmy.unitCap 64 near the player, extrasCap 24, far-AI LOD past 64 blocks, the `ash vault perf` biggest-battle number (DE14) and the draw side at render distance 10; the on-device proxy route is the Mac worker's; the debug-build perf line is load-sensitive, T3d] [the Deep] Quest perf in the vault: proxy ashvault route 12 hitches/min (max 45.6 ms); add a live-unit cap and
    soldier AI LOD, plus a questcheck "citadel at full alarm" number (DE14).
G4. [done, G20 PR: PlaythroughDeep.swift, `--playthrough --only deep` (questcheck or the Mac app): Ember Charge through the Wardstone, the hell band, the keep's Castellan, Sunderite to ingots in a blast furnace, pickaxe and charge, the seal, the vault, the Marshal, three waves, the Chancellor, the lift home] [the Deep] Playthrough.swift has no Deep stage (keep -> Sunderite -> charge -> seal -> citadel -> Marshal -> lift).
G5. [DONE Oct 13: checked, nothing left for cloud threads: battery and field-gun shells mark their landing with red smoke and a whistle (AshArmy.ashShellTick), sharpshooters glint; the sky blend and fog end are looks for the Mac worker] [part, G20 PR: battery shells already mark their landing (DE10); Ashguard sharpshooters now glint 1.1 s before the first shot at a target (check G5 sharpshooter glint); the sky blend and fog end are looks, left to the Mac worker] [the Deep, small] battery shells get the Marshal's red flare warning (AshUnits.swift ashArtillery -> g.ashStrikes,
    DE10); marksmen get a first-shot glint (an unarmoured arrival died 92 blocks out in 4 s); blend the vault sky over
    y 120-136 instead of the switch at 128; fog end 130 -> ~220 so the 138-tall vault reads as huge (check proxy p99).
G6. [base / village] [DONE: Lane A thread, 2026-10-11, PR #49; docs/status/tidebreaker-gaps.md] First citadel findability: radar and intercepted orders are base loot, so the first base means
    wandering ~1,200 blocks. Add a cartographer explorer map to military_base or orders in wild camps.
G7. [towns] [DONE: Lane A thread, 2026-10-11, PR #49; docs/status/tidebreaker-gaps.md] Rename the Capital city "Meridian" (CapitalTown.swift:17): it clashes with the Meridian Navy. Add a
    capital_city structure shot and a street-level shot to snap.sh.
G8. [frigate] [DONE: Lane A thread, 2026-10-11, PR #49; docs/status/tidebreaker-gaps.md] Thrusters read as two small points at night: bigger glowing faces + a drive-glow sprite.
G9. [horses] [DONE: Lane A thread, 2026-10-12: five coat patterns (sleek, dapple grey, paint) with hair grain and sheen, mane/tail hair pattern, socks, blazes, stars, flaxen manes; questcheck --horsecoats-only (model checks, lineup and rider's-view renders)] Horse coats are flat untextured colours; texture the coat per variant, check the rider's view of the
    neck/mane, add a Quest horse render to questcheck.
G10. [done, G20 PR: the five pass in questcheck --towns-only (same TownTests), and --towntests now gates snap.sh's checks shard] [towns] `--towntests` has 5 FAIL on fa79ef5e: wallet/honour HUD lines empty (HonourTests.swift:218,
    HonourGapTests.swift:263), "sheriff shoots an outlaw player", "3 bread for $0.90". Fix, then add --towntests to
    snap.sh's checks shard so they gate CI.
G11. [frigate] [DONE: Lane A thread, 2026-10-11, PR #49; docs/status/tidebreaker-gaps.md] No designed way to board the Meridian frigate 45 blocks up outside `/vessel frigate`: a boarding route
    (drop ladder, or hail-and-board when it flies low) plus a ride-check bot that reaches the helm from the ground.

## SMALLER IDEAS (take when a lane is empty)
O1. [DONE Oct 13: outlaw camps are freed once their outlaws are gone and you stand in them (a $25 reward, a general store keeper sets up, an O mark on the map); a freed camp's fire is a fast-travel post to the other freed camps (use to see the offer, use again within 6 s to ride there); Liberation.swift, questcheck --liberation-only] Outposts and liberation (Far Cry style): small enemy camps on the map that you clear to unlock fast travel and shops.
O2. [DONE Oct 13: sneak-use a townsperson ($30) or a calm Capital soldier ($60) to hire them, up to three; they follow, catch up, and fire on monsters and soldiers hunting you (their rounds count as yours, never hit you); hand them troop class plate or a gun to gear them; sneak-use to let them go; Companions.swift, questcheck --companions-only] Hired companions: pay or recruit townsfolk and troops to follow and fight; gear them with your looted armour.
O3. [DONE Oct 13: towns (Honour) and countries (standing) already remembered you; added the armed factions (Capital, Greywall, Meridian, Stormwarden, Ironback): -100..100 from -30, killing their soldiers costs it and killing their enemies earns it; at 30 their soldiers hold fire unless you hurt one, at -60 they send a hunter dropship every 8 minutes; FactionRep.swift, questcheck --factionrep-only] Faction reputation: towns, the Capital, the military, the navy and the countries each remember you; bounties and allies follow.
O4. [DONE Oct 13: a gun past 60% wear can jam and kicks harder; the blacksmith's Repair counter mends armour, tools and weapons for money; the gunsmith mends guns and reworks them a grade (Fine $40, Rare $120, Elite $300); the anvil still mends with materials; Repairs.swift, questcheck --repair-only] Armour and weapon repair benches and a gunsmith tier, so damaged loot matters.
O5. [DONE Oct 13: a faction at -45 or below raids your home, a base you took, a camp you freed or the town you are in every 10 minutes when you are near (two dropships landing 24-30 blocks out); wall turrets you placed or hold fire on raiders; beat them off for $20 salvage; FactionRaids.swift, questcheck --raids-only] Raids on your bases and towns by factions you have angered, with defences you can build (walls, turrets you captured).
O6. [DONE Oct 13: legendary pelts and trophy parts, boss trophies (Wyrm Head, Wyrm Egg, Blight Star), legendary arms and captured Greywall flags (taking a base hands you its flag) count when framed, on an armour stand or placed within 16 blocks of your home, a taken base or a freed camp; first showing gives a toast and honour; three or more make a museum paying $2 a trophy a day; sneak-use an item frame for the ledger; Trophies.swift, questcheck --trophies-only] Trophy room and museum: legendary pelts, boss trophies, captured flags, displayed in your base.
O7. [DONE Oct 13: thunderstorms ground flyers (frigates break off over home, no dropship launches: hunters and raids wait), fog banks roll in (mostly at dawn) closing the view to ~30 blocks and cutting soldiers' spotting to 40% (rain 85%, storm 70%), falling or lying snow slows soldiers to 70%; WeatherWar.swift, questcheck --weather-only] Weather that matters: storms ground flyers, fog helps stealth, snow slows troops.
O8. [DONE Oct 13: wanted posters were already on the town boards; now a hunting party sets out 450-600 blocks off, rides toward you at a canter (a gallop outruns them), shows on the map and minimap as a red ring, waits while you're underground or in a town, gives up after 20 minutes, and its posse rides in from their side at 48 blocks] Wanted posters and bounty hunters that track you across the map.

## Inspiration (feel and mechanics only)
GoldenEye 007 (base tiers, alarms, stealth), Red Dead Redemption 2 (law, honour, hunting, towns, horses), Halo (shields, vehicles, frigates), Far Cry (outposts), Mount and Blade (taking villages, factions), Valheim and Terraria (boss-gated progression), Metal Gear Solid (alerts and stealth), Wolfenstein (the final layer), Sea of Thieves (naval play).
