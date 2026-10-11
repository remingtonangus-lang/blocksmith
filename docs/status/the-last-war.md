# The last war: the Ashguard below hell (backlog B7, 2026-10-11, Lane B thread)

Remington's intent: below hell is a WW2-German-style army. heavy period-style tanks, black everything, red flags with black,
replicas of the period's weapons. It should be clear what we are going for. You kill them and you have beaten the game.

Listed in the backlog:
- Build on the Ashguard and the Ash Vault (PR 22 and the gap pass).
- Black uniforms and vehicles, and red banners with a black fictional emblem.
- Heavy tanks in the style of the period, half-tracks, artillery, and period-style rifles, SMGs and MGs, all under
  fictional names.
- A final campaign: fortified lines, a leader in a final bunker, a big last battle and an ending.
- Store-safe: fictional names and a fictional emblem. No swastikas, SS runes, Iron Crosses or real unit insignia.

## Store-safety rules for this item
- **The emblem.** The Ashguard's ember mark is the only emblem: a diamond split by a bar, black on a white disc on a
  red field. No real symbol, rune, cross or eagle appears anywhere.
- **Names.** Every name is invented, German-flavoured at most. No real person, party, unit, vehicle or weapon name.
  The real ones go into tools/coined-terms.txt so the namecheck in every build keeps them out of player-visible text.
- **The leader.** The leader is a fictional figure, the Ash Chancellor. He is not a likeness of any real person: no
  moustache, no real uniform pattern.

## Expanded objectives (written before building)
1. **The look: the period army, unmistakably.**
   - Ashguard soldiers wear period field dress in black:
     - Flared steel helmets (the period's coal-scuttle shape) for the line ranks.
     - Officers wear high-crowned peaked caps with red piping.
     - The sharpshooter wears a soft field cap; the drivers wear side caps with headsets.
     - Everyone has a tunic with pockets, a belt with Y-straps and ammo pouches, a gas-mask canister on the back and
       tall jackboots.
     - Officers wear a long greatcoat over breeches.
     - Every soldier wears a red armband with the emblem on a white disc.
     - None of the Capital's sci-fi plate, crests or visors.
   - The Ash Marshal gets a greatcoat with red lapels and a peaked cap with silver cords.
   - **Banners.**
     - Tall red banners with the emblem on a white disc hang down the citadel's walls, the bunkers and the depots.
     - A big 3x3 standard hangs over the citadel gate.
     - Red flags with the emblem fly from the flagpoles.
   - **Vehicles, restyled in the period's shapes.**
     - The Cinder Tank becomes a heavy tank: a slab hull with a near-vertical front plate, big interleaved road
       wheels, a boxy turret with a long gun and a double-baffle muzzle brake, spare track links, and a stowage bin
       on the turret's back.
     - The half-track gets an angular armoured body with sloped plates.
     - The field gun becomes a heavy flak gun on a cross-shaped platform with outriggers, a tall mount, a long
       barrel and a shield.
     - All of them are black, marked with the emblem and red bands.
   - A new super-heavy tank, the Behemoth, is the last battle's centrepiece. It is huge and slow, with two guns
     (a main gun and a coaxial gun), 700 health, and it can only be fought from cover.
2. **Period-style weapons under fictional names.**
   - The four guns:

     | Name | Style | Ammo | Rounds | Damage | Fire |
     |---|---|---|---|---|---|
     | Kessel Bolt Rifle | bolt-action | heavy rounds | 5 | 16 | slow and accurate |
     | Hagel Machine Pistol | SMG with a stick magazine | rifle rounds | 32 | 3 | auto |
     | Sturmwind Carbine | assault carbine with a curved magazine | rifle rounds | 30 | 4.5 | auto |
     | Ashsaw Machine Gun | belt-fed, ripping rate | rifle rounds | 75 | 3.5 | very fast; hip fire is wild, aimed is tight |

   - Each gun has a first-person model in walnut wood and blued steel, an icon and a sound of its own (the Ashsaw's
     ripping buzz above all).
   - **Who carries what.**
     - Riflemen: bolt rifle or carbine.
     - Stormers: carbine or machine pistol.
     - Sharpshooters: bolt rifle.
     - Heavies: the Ashsaw, fired in long bursts from the hip with a readable spin-up.
     - Officers and drivers: machine pistol.
     - The Marshal: carbine.
   - **Getting them.** Soldiers drop their gun sometimes. The vault's armouries and the bunker hold them. They can't
     be crafted.
3. **The fortified lines.**
   - **The Ember Line** rings the citadel at 404-432 blocks out, between the ring of depots and the outposts. Its
     layers, from the outside in:
     - two rows of tank-trap teeth;
     - a belt of barbed wire (a new block that slows and scratches);
     - a sandbagged trench;
     - concrete MG bunkers every 15 degrees, with firing slits and crews.
   - **The Last Line** rings the citadel at 54-66 blocks with:
     - teeth, wire and a trench;
     - eight MG bunkers;
     - a dug-in tank behind an earth berm beside each road.
   - Both lines open at the four roads into checkpoints with barriers and guard posts.
   - The lines generate in fresh vault ground. An old world's explored vault keeps its ground (documented).
4. **The last battle.**
   - The Marshal's death no longer ends the game. It starts the last battle:
     - sirens, and the Chancellor's voice over the citadel's loudspeakers (toasts);
     - three counter-attack waves from the vault's motor pools, converging on the player.
   - **The waves.**
     - Wave 1: infantry and half-tracks.
     - Wave 2: tanks and infantry under artillery barrages, each marked by a red flare two seconds before the shell
       lands.
     - Wave 3: the Behemoth, two tanks and the Chancellor's guard of heavies.
   - **Between waves.** A wave ends when nearly all of it is down. A short breather follows, with a toast naming
     what's coming.
   - **Limits.** Every wave respects the live-unit cap, so the battle holds 72 fps on Quest. Units spawn out of sight
     on loaded ground.
   - **Leaving and dying.** Leaving the vault (or dying) pauses the battle; it picks up where it left off. It's
     saved.
5. **The Chancellor's Bunker.**
   - It's dug deep under the command bunker, reached by a stairwell behind a blast door that stays shut (nothing
     breaks it) until the last battle is won.
   - Inside: a corridor, a guard room, a radio room, a map room, a generator room and the Chancellor's study, hung
     with banners, all lit with red lamps.
   - Old worlds get the bunker stamped in under the citadel as its chunks load.
6. **The Ash Chancellor (the final boss).**
   - A fictional leader in a long black leather coat and peaked cap with the red armband. Boss bar.
   - He fights from behind his guard with a machine pistol. At two thirds and one third of his health he calls his
     last guard out of the side rooms. At half health the bunker shakes under the vault's own artillery, with dust
     and falling debris.
   - He spawns in his study when the player enters the bunker after the battle, and the fight survives a reload.
7. **The ending.**
   - Killing the Chancellor beats the game:
     - the Ashguard stands down everywhere;
     - a new epilogue ("The war below the world is over"), then THE END and the credits;
     - the advancement Ashes to Ashes (now for the Chancellor), after The Last Battle for holding out;
     - the lift home opens in the command bunker above.
   - Worlds that beat the old ending (the Marshal) count as beaten, and nothing changes for them.
8. **Checks (questcheck slice "lastwar:").**
   - Every gun registers with its model, icon, sound and ammo, Ashguard soldiers carry the right guns, and the
     Ashsaw's bursts and spin-up behave.
   - The new and restyled models build, and the banners and emblem textures paint.
   - The Ember Line and the Last Line generate with bunkers, teeth, wire and trench, and the roads stay open.
   - The bunker exists under the citadel, the blast door holds before the battle and opens after it, and an old
     chunk gets it stamped in.
   - The Marshal's death starts the battle. The waves spawn within the cap and advance, and the battle saves and
     resumes.
   - The Chancellor spawns, calls his guard and dies, the ending plays and victory is saved.
   - The namecheck covers the period's real names. A last-battle timing check keeps the unit tick within budget.

## Built (2026-10-11, Lane B thread)
- **Arms.** Sources/AshArms.swift has the four guns' models, details and icons; Guns.swift has the specs (gun_kessel,
  gun_hagel, gun_sturmwind, gun_ashsaw); WeaponAudio.swift has sound slots 16-19 and their reloads. Soldier.ashGun
  hands them out by rank (old saves swap a Capital gun on load); the Ashsaw gunner racks the bolt before each burst.
  Soldiers drop their gun now and then (the shared soldier drop), and the vault's armoury and command chests hold them.
- **Look.** Sources/AshLook.swift dresses the Ashguard (helmets, caps, tunics, Y-straps, canisters, armbands, the
  officers' greatcoats and breeches). AshUnits.swift has the restyled tank, the half-track, the flak gun and the new
  Behemoth (`ash_behemoth`, 700 health, main gun plus coax). The Chancellor (`ash_chancellor`) is soldier-rigged in
  black leather.
- **Cloth.** Banners and the 3x3 standard are blocks (ash_banner_top / _mark / ash_banner / _end, ash_standard_0..8),
  each with an "[x]" state: the picture is on the two faces across the cloth, plain edge elsewhere, and the +Z / +X
  faces carry the mirror tile, so walls and flags read right from both sides (AshWar.banner / AshWar.standard).
- **Lines.** Sources/AshLines.swift: the Ember Line (ring 404-432) and the Last Line (square 54-66), carved per column
  in DeepGen.generate; 28 MG bunkers and 8 checkpoints are structure starts. The gate booms are raised and the Last
  Line's dug-in tanks sit beside the road, so the roads stay open.
- **Bunker and battle.** Sources/AshFinal.swift: the Chancellor's Bunker (fixed start "ash_finalbunker", built after
  the citadel; stamped into saved vault chunks by SaveManager.loadChunk), the last battle (Game.ashStage / ashWave,
  saved; LastWar live state; waves 45-70 blocks out, not saved, respawned after a reload), barrages
  (Game.ashStrikesTick, shared with the Marshal), the Chancellor's AI and the quake.
- **Ending.** AshWar.epilogue ends with THE END; Ashes to Ashes is the Chancellor's; The Last Battle is new.
- **Namecheck.** tools/coined-terms.txt now lists the period's real names (parties, units, people, arms, vehicles).
- **Checks.** `questcheck --lastwar-only` (LastWarTests, part of every full questcheck); with --render it also writes
  lastwar_gate, lastwar_army, lastwar_command, lastwar_line and lastwar_study. DeepTests now expects the Marshal's fall
  to start the battle and the Chancellor's to win the war.

## Defaults picked (no questions asked)
- The Chancellor spawns once the player has been in the bunker for 3 s, with two heavies; he calls four of his guard
  at two thirds and one third, and the bunker shakes at half.
- A wave is beaten when at most two of it are left (the last wave: none). Breathers are 15 s (8 s before the first).
  Barrages come every 13 s (10 s on Hard) from wave 2 on.
- Leaving the vault pauses the battle; a reload brings the current wave again.
- Worlds won under the old ending (the Marshal) count as won.

## Verifier pass (2026-10-11) and fixes
- Wave units are never despawned (`Mob.waveUnit`, exempt in shouldDespawn) and never saved; a wave whose units unload
  alive (the player left the vault or died) regroups and comes again instead of counting as beaten.
- Waves spawn on the vault floor itself (not roofs), off the lines (not in a trench), out of the player's sight when
  any spot is.
- The checkpoint booms are raised to five blocks: tanks and the Behemoth drive under them.
- The officers' cap badge is a round red cockade with a white centre (the old white square with a black bar could
  read as two strokes at a distance).
- The breather toast names the next wave; the Chancellor speaks over the loudspeakers as the battle starts.
- The Ashsaw's cooling slots were trimmed so every upgraded gun fits the first-person arm buffer (checked).
- Tests: the battle check now closes the death screen a downed test player opened (it broke the VR checks after it),
  and the last-wave timing check measures both the units' thinking and the whole tick against a baseline.
