# Hell's own mobs and the gate into hell (backlog B6, 2026-10-11, Lane B thread)

Remington's intent: hell needs its own mobs, including a dark burgundy knight class. Hell comes after mastering the
bases and getting upgrades.

Listed in the backlog:
- A knight order in dark burgundy armour (squire, knight, champion and a commander mini-boss), with shields, parries
  and charges that suit VR melee.
- 3+ other original hell mobs with distinct roles (flying, swarm, ranged).
- A gate: hell is reachable only with base-tier gear (a key or charge looted from command fortresses).

"Hell" here means both places: the Emberdeep (through a portal) and the Deep's hell band (dig through the bottom of the
world).

## Expanded objectives (written before building)
1. **The Brand Order, a knight order in burgundy plate.** Four ranks, from common to rare:
   - Brand Squire: light plate, small shield, short sword.
   - Brand Knight: full plate, kite shield, longsword.
   - Brand Champion: heavier plate, gold trim, a two-hand greatsword, a quicker guard.
   - The Brand Commander, the mini-boss: huge, crowned helm, a banner on his back, a boss bar.
   Every rank wears the order's dark burgundy with a glowing visor slit, drawn on Mac and Quest from the same parts.
2. **Fights built for VR melee.** Every rule below is readable from the model and its sound, so a player in the
   headset can see it and answer with their own blade.
   - **Shield.** A knight with its shield up takes no damage from the front: a blade, an arrow or a thrown thing
     clangs off with sparks, and bullets lose most of their damage. A hit from the side or behind lands.
   - **Guard break.** Each blocked hit wears the knight's guard. When it breaks, the shield drops and the knight
     reels for a moment, open to hits.
   - **Parry window.** Before each swing the knight raises its blade high for a clear moment (a wind-up glint and a
     rising whine). A hit that lands in that moment parries: the knight staggers, its shield drops and it takes extra
     damage for a short while.
   - **Recovery.** After a swing the shield stays down for a short window, so trading hits works too.
   - **Charge.** Knights, Champions and the Commander charge from mid range: a lowered blade, a war cry and pawing
     for most of a second, then a straight rush. Sidestep it and the knight skids past and stands dazed, open to
     hits. Take it and you're hit hard and thrown back. A charge into a wall stuns it longer.
   - **The Commander.** At half health he sounds a horn that calls a knight and two squires and goes berserk:
     double charges, a faster wind-up and a guard that breaks less often.
3. **Three more hell mobs, each in a role of its own.**
   - **Searwing (flying).** A burning bat-winged flier. It circles high, screeches and glows before each dive, then
     stoops at your head. It burns on contact and climbs away slowly afterwards, which is the moment to hit it.
   - **Scorchlings (swarm).** Knee-high fire imps in packs of 5 to 8. Each one is weak and fast, they leap and nip,
     and they burst into sparks when they die.
   - **Slagthrower (ranged).** A hunched brute that keeps its distance. It lobs glowing slag in an arc: you see the
     arm drawn back glowing first, then a hissing lump you can watch and step out of. The slag splashes and sets the
     ground alight.
4. **Spawning.**
   - These mobs spawn naturally in the Emberdeep and in the Deep's hell band, alongside the old roster: order patrols
     of a knight with squires (a Champion leading now and then), Searwings in the open halls, Scorchling packs and
     lone Slagthrowers. Caps keep the numbers sane for 72 fps.
   - After a few minutes in hell, a Commander's muster can ride out once in a while: the Commander and a retinue,
     announced by a horn.
   - Every new Brimstone Keep holds an order detachment at its gate.
   - `/summon` works for all seven, and the mobs save and load.
5. **The gate: hell needs base loot.**
   - **Wardstone floor.** The bottom of the surface world becomes three layers of Wardstone. Nothing breaks it: no
     pickaxe, explosion, frigate shell, piston or mob.
   - **The Ember Charge.** Only an Ember Charge, pressed against Wardstone, blasts a 3x3 shaft through to the Deep.
   - **Portals.** A portal frame no longer lights with flint and steel or a fire charge on the surface. Using an
     Ember Charge on the frame wakes it.
   - **Loot only.** Ember Charges can't be crafted. They come only from the command and vault loot of the military
     bases (Capital Citadels and Boreal Stations; A1's command fortresses use the same tables when they land). Every
     command chest is guaranteed one.
   - **Old worlds.** Saved surface chunks get the floor stamped in as they load, like the Sealrock. Portals that were
     already lit stay lit, and the way back up from the Deep still works.
   - **Hints.** Mining Wardstone or striking a cold frame says what it needs and where to find it.
6. **Checks (questcheck slice "hell:").**
   - Every new mob registers, saves and loads, and has a model and a voice.
   - The shield blocks a frontal blade and arrow but not one from behind, and bullets are cut down.
   - The guard breaks after the right number of blocks.
   - A hit in the wind-up parries, a dodged charge leaves the knight dazed, and a charge that connects knocks the
     player back.
   - The Commander calls his retinue at half health and has a boss bar.
   - The Searwing dives and climbs, Scorchlings come in packs, and the Slagthrower's slag lands near a standing target
     and misses a moving one.
   - Hell spawns include the new mobs.
   - The surface floor is Wardstone and no pickaxe or TNT breaks it. A charge opens a shaft and the seam carries the
     player through it.
   - Flint and steel fails on a frame and an Ember Charge lights it.
   - Every base command chest holds a charge, and saved chunks get the floor.
   - The namecheck stays clean, and a busy-hell timing check keeps the mob tick within budget.
