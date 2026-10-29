# Blocksmith sound list

Every sound event in the game, by its stable file name. Today all of them are synthesized in code (Sources/SoundSynth.swift,
SoundFoley.swift, SoundMobs.swift, WeaponAudio.swift, VehicleAudio.swift, TerrainAudio.swift, HorseLife.swift). A recording
dropped in `Resources/Sounds/real/<name>.wav` (variants `<name>_1.wav` ... `<name>_5.wav`) replaces the synthesized sound with
that name on the Mac and the Quest; see `Resources/Sounds/real/README.md`. The names are `Snd.name` (Sources/Sound.swift) and
never change: they are the contract between the code and the recordings.

Each line: `file name` (volume category) [level of today's synthesized take, LUFS, from docs/status/audio_levels.md; a
recording is normalised to this level] event, then what a good recording sounds like. **WORST** marks the 40 weakest
synthesized sounds (judged from the synthesis code and Remington's playtest complaints in docs/roadmap/backlog.md): replace
those first. All recordings must be original or properly licensed (no other game's sounds).

846 named sounds (+ note blocks on demand, + 153 recorded townsfolk voice takes `voice_<n>`, already real recordings from Resources/voices.bin).
Generated from the code on 2026-10-14 (mirrors SoundBank.allSounds); regenerate with tools/soundlist.py when Snd gains a case.

## The 40 worst synthesized sounds (record these first)

1. `step_grass`: owner: footsteps sound like walking through mud (P14, R19); the synth thud + resonated grit still reads wet on the Quest
2. `step_dirt`: same mud complaint (P14, R19): no real crumb texture
3. `step_stone`: resonated contact pulse rings like a tuned block, not a boot on rock
4. `step_gravel`: gravel like water (P118): resonated grains are tiny water drops
5. `hit_gravel`: owner: hitting gravel sounds like punching water (P118)
6. `step_leaves`: band-limited noise swish: reads as static, not crisp leaves
7. `break_leaves`: owner: the leaf-breaking sound sounds wrong (P89); still a noise swish
8. `hit_leaves`: noise rustle repeats 4x/s while cutting: static
9. `step_sand`: filtered noise grains: a hiss, not a sand crunch
10. `step_snow`: missing the squeaky compressed-snow crunch
11. `step_wood`: boxy resonator knock with no board give
12. `hoof_stone`: owner: hooves on capital brick sound cheap (P49)
13. `hoof_earth`: the most-heard horse sound; a noise thud, part of the 'one-cylinder' gallop (R13)
14. `hoof_wood`: a resonator knock; cheap next to the stone and earth fixes
15. `mob_horse_ambient`: formant-synth whinny; the horse is the core companion and it sounds electronic
16. `mob_horse_hurt`: formant squeal; needs a real pained horse
17. `gun_0`: Donnerkeil rifle crack is noise bursts; guns are the main combat feel ('fix the weapons')
18. `gun_13`: one synth crack shared by four sidearms (Falke, Sechser, Wren, Breaker)
19. `gun_2`: Brecher shotgun: noise blast without real low-end weight
20. `gun_3`: Fernblick/Longwatch sniper: synthetic tail, no real supersonic snap
21. `gun_18`: Sturmwind/Slatefall carbine: noise crack
22. `gun_reload_0`: noise-click reload; R7 asks for a clear audible magazine click
23. `gun_14`: magazine-seated cue is the key reload feedback (R7) and is synthesized
24. `bullet_impact_stone`: the most-heard impact; a filtered burst, no chips or dust
25. `bulletFlesh`: noise thwack, not a meaty hit
26. `soldier_1_alert`: formant gibberish where a shouted line should be (all soldier_* barks share this problem)
27. `soldier_1_hurt`: formant grunt, robotic
28. `villagerYes`: formant 'hum' reads as a synth buzz
29. `mob_zombie_ambient`: formant groan; the most common hostile voice
30. `hurt`: player pain grunt is formant synthesis; heard constantly
31. `playerDeath`: synth grunt + noise thud
32. `doorOpen`: creak is a saw-wave pitch sweep: sounds like a synth chirp, not a hinge
33. `chestOpen`: saw-wave 'creak' sweep again
34. `rain`: white-noise rain; the commonest weather loop
35. `waterLoop`: bubble synthesis, sounds like a fish tank
36. `splash`: low-passed noise burst, no real water body
37. `fireLoop`: crackle noise with no flame body
38. `explode`: noise-burst explosion without a real low-end punch or debris
39. `engineIdleLoop`: oscillator engine, buzzy and static
40. `birdCall`: synthesized chirps; obviously fake in every forest

## Footsteps

Your own steps play dry at your feet; other players' and mobs' steps play in the world. Every surface below repeats constantly: record 3-5 takes each (heel + toe roll in one take, 0.15-0.35 s).

- `step_stone` (players) [-20 LUFS]: stone, cobble, bricks, ores. Hard boot heel on stone: a dry short tap with a little grit scuff, no ring, no thud. Record 3-5 takes. **WORST** (resonated contact pulse rings like a tuned block, not a boot on rock)
- `step_dirt` (players) [-17 LUFS]: dirt, coarse dirt, farmland, paths. Boot on packed dry earth: a soft dry pat with a little crumb grit; NOT wet. Record 3-5 takes. **WORST** (same mud complaint (P14, R19): no real crumb texture)
- `step_sand` (players) [-16 LUFS]: sand, red sand. Boot on dry sand: a soft muffled shush-crunch, fine grains. Record 3-5 takes. **WORST** (filtered noise grains: a hiss, not a sand crunch)
- `step_wood` (players) [-20 LUFS]: planks, logs, doors, wooden objects. Boot on wooden boards: a hollow knock with a slight board give, short. Record 3-5 takes. **WORST** (boxy resonator knock with no board give)
- `step_plant` (players) [-18 LUFS]: flowers, crops, saplings, grass tufts. Pushing through stems: a short leafy swish. Record 3-5 takes.
- `step_glass` (players) [-17 LUFS]: glass, panes, ice-like glassy blocks. Boot on glass: a hard, slightly bright tap, faint ring. Record 3-5 takes.
- `step_snow` (players) [-18 LUFS]: snow, snow blocks, powder snow. Boot in dry snow: the squeaky compressed crunch of cold snow. Record 3-5 takes. **WORST** (missing the squeaky compressed-snow crunch)
- `step_gravel` (players) [-17 LUFS]: gravel. Boot on loose gravel: a clear dry crunch of many small stones grinding, no water character. Record 3-5 takes. **WORST** (gravel like water (P118): resonated grains are tiny water drops)
- `step_metal` (players) [-20 LUFS]: iron blocks, steel plating, anvils, rails. Boot on steel plate: a dull clank with a brief metallic ring (damped, not a bell). Record 3-5 takes.
- `step_wool` (players) [-18 LUFS]: wool, carpet, beds. Boot on carpet: a muffled soft pad, almost silent. Record 3-5 takes.
- `step_slime` (players) [-16 LUFS]: slime blocks. Stepping on slime: a springy wet squelch. Record 3-5 takes.
- `step_mud` (players) [-16 LUFS]: mud. Boot sinking into mud: a thick wet squelch with suction on lift-off (this one SHOULD be wet). Record 3-5 takes.
- `step_bone` (players) [-19 LUFS]: bone blocks. Boot on bone: a dry hollow clack. Record 3-5 takes.
- `step_amethyst` (players) [-16 LUFS]: amethyst / crystal blocks. Stepping on crystal: a hard tap with a soft glassy chime. Record 3-5 takes.
- `step_soul` (players) [-16 LUFS]: soul sand / soul soil (Ghost Valley). Stepping on soul sand: a dry sandy shush with an eerie faint hollow moan. Record 3-5 takes.
- `step_sculk` (players) [-17 LUFS]: sculk (deep dark growth). Stepping on sculk: a soft rubbery, slightly wet squish. Record 3-5 takes.
- `step_netherrack` (players) [-19 LUFS]: Emberdeep rock. Crumbly porous rock underfoot: a soft dry crunch, slightly hollow. Record 3-5 takes.
- `step_deepslate` (players) [-19 LUFS]: deepslate and dark deep rock. A denser, lower version of stone: dull tap, no ring. Record 3-5 takes.
- `step_grass` (players) [-18 LUFS]: grass blocks. Boot on turf: soft dry pat plus a short blade swish/crunch of grass; NOT squelchy. Record 3-5 takes. **WORST** (owner: footsteps sound like walking through mud (P14, R19); the synth thud + resonated grit still reads wet on the Quest)
- `step_leaves` (players) [-19 LUFS]: leaves of every tree. Walking on/through leaves: a crisp dry leaf crunch and rustle, no hiss/static. Record 3-5 takes. **WORST** (band-limited noise swish: reads as static, not crisp leaves)
- `soldier_step_0` (hostile) [-23 LUFS]: Steelhold soldier footstep, Recruit. Light boots on hard ground. Record 3-5 takes.
- `soldier_step_1` (hostile) [-22 LUFS]: Steelhold soldier footstep, Trooper. Combat boots with webbing rattle. Record 3-5 takes.
- `soldier_step_2` (hostile) [-23 LUFS]: Steelhold soldier footstep, Marksman. Soft careful boots. Record 3-5 takes.
- `soldier_step_3` (hostile) [-20 LUFS]: Steelhold soldier footstep, Ironclad. Heavy armoured boots with plate clank. Record 3-5 takes.

## Horses

Hoof falls by ground type (HorseLife), then the horse family voices. The gallop plays four hoof falls per stride: record 4-5 takes per surface, each a single hoof.

- `hoof_stone` (friendly) [-16 LUFS]: A hoof fall on stone. A horseshoe on stone or brick: a sharp hard clop with a metallic edge, clear (P49: on capital brick it sounds cheap today). Record 3-5 takes. **WORST** (owner: hooves on capital brick sound cheap (P49))
- `hoof_wood` (friendly) [-17 LUFS]: A hoof fall on wood. A hoof on wooden boards: a hollow knock. Record 3-5 takes. **WORST** (a resonator knock; cheap next to the stone and earth fixes)
- `hoof_earth` (friendly) [-21 LUFS]: A hoof fall on earth. A hoof on dirt or turf: a dull soft thud with a little crumb. Record 3-5 takes. **WORST** (the most-heard horse sound; a noise thud, part of the 'one-cylinder' gallop (R13))
- `hoof_sand` (friendly) [-21 LUFS]: A hoof fall on sand. A hoof in sand: a muffled soft thud with grain spray. Record 3-5 takes.
- `hoof_snow` (friendly) [-16 LUFS]: A hoof fall on snow. A hoof in snow: a muffled compressed crunch. Record 3-5 takes.
- `hoof_water` (friendly) [-15 LUFS]: A hoof fall on water. A hoof in shallow water: a splash. Record 3-5 takes.
- `mob_horse_ambient` (friendly) [-22 LUFS]: Horse idle call. Horse idle call, every few seconds nearby: a real horse's whinny, snort and blow (key animal: the player rides it constantly). **WORST** (formant-synth whinny; the horse is the core companion and it sounds electronic)
- `mob_horse_hurt` (friendly) [-21 LUFS]: Horse hurt. Horse is hit: a short sharp pained version of its voice (a real horse's whinny, snort and blow (key animal: the player rides it constantly)), 0.2-0.6 s. **WORST** (formant squeal; needs a real pained horse)
- `mob_horse_death` (friendly) [-22 LUFS]: Horse death. Horse dies: a longer falling cry of its voice (a real horse's whinny, snort and blow (key animal: the player rides it constantly)), then silence; 0.5-2 s.
- `mob_donkey_ambient` (friendly) [-23 LUFS]: Donkey idle call. Donkey idle call, every few seconds nearby: a donkey's hee-haw bray.
- `mob_donkey_hurt` (friendly) [-22 LUFS]: Donkey hurt. Donkey is hit: a short sharp pained version of its voice (a donkey's hee-haw bray), 0.2-0.6 s.
- `mob_donkey_death` (friendly) [-24 LUFS]: Donkey death. Donkey dies: a longer falling cry of its voice (a donkey's hee-haw bray), then silence; 0.5-2 s.
- `mob_mule_ambient` (friendly) [-23 LUFS]: Mule idle call. Mule idle call, every few seconds nearby: a mule's bray-whinny mix.
- `mob_mule_hurt` (friendly) [-22 LUFS]: Mule hurt. Mule is hit: a short sharp pained version of its voice (a mule's bray-whinny mix), 0.2-0.6 s.
- `mob_mule_death` (friendly) [-24 LUFS]: Mule death. Mule dies: a longer falling cry of its voice (a mule's bray-whinny mix), then silence; 0.5-2 s.
- `mob_skeleton_horse_ambient` (friendly) [-31 LUFS]: Skeleton Horse idle call. Skeleton Horse idle call, every few seconds nearby: a hollow, rattly ghostly whinny.
- `mob_skeleton_horse_hurt` (friendly) [-23 LUFS]: Skeleton Horse hurt. Skeleton Horse is hit: a short sharp pained version of its voice (a hollow, rattly ghostly whinny), 0.2-0.6 s.
- `mob_skeleton_horse_death` (friendly) [-28 LUFS]: Skeleton Horse death. Skeleton Horse dies: a longer falling cry of its voice (a hollow, rattly ghostly whinny), then silence; 0.5-2 s.
- `mob_zombie_horse_ambient` (friendly) [-23 LUFS]: Zombie Horse idle call. Zombie Horse idle call, every few seconds nearby: a rotten, gurgling whinny.
- `mob_zombie_horse_hurt` (friendly) [-23 LUFS]: Zombie Horse hurt. Zombie Horse is hit: a short sharp pained version of its voice (a rotten, gurgling whinny), 0.2-0.6 s.
- `mob_zombie_horse_death` (friendly) [-24 LUFS]: Zombie Horse death. Zombie Horse dies: a longer falling cry of its voice (a rotten, gurgling whinny), then silence; 0.5-2 s.
- `baby_horse_ambient` (friendly) [-21 LUFS]: Foal idle call. A foal's higher, lighter whinny.

## Blocks by material

Break, place, mining tick and landing per material (SoundMat). The block's in-game name is what the material covers.

- `break_stone` (blocks) [-22 LUFS]: A stone block breaks. Rock cracking apart and chunks clattering down.
- `place_stone` (blocks) [-19 LUFS]: A stone block is placed. A heavy stone block set down firmly: dull knock, tiny grit settle.
- `hit_stone` (blocks) [-21 LUFS]: Mining tick on stone (repeats ~4/s while digging). Pick tapping rock: a short bright chink, dry; must not tire the ear. Record 3-5 takes.
- `fall_stone` (players) [-22 LUFS]: Landing on stone after a fall. Landing on rock: heavy body thud with a hard scuff.
- `break_dirt` (blocks) [-18 LUFS]: A dirt block breaks. A clod of earth breaking: soft crumble and pattering crumbs.
- `place_dirt` (blocks) [-19 LUFS]: A dirt block is placed. A clod set down: soft pat.
- `hit_dirt` (blocks) [-18 LUFS]: Mining tick on dirt (repeats ~4/s while digging). Shovel/hand into dry earth: short soft scuff; must not tire the ear. Record 3-5 takes.
- `fall_dirt` (players) [-16 LUFS]: Landing on dirt after a fall. Landing on earth: dull body thump and dirt scuff.
- `break_sand` (blocks) [-17 LUFS]: A sand block breaks. Sand slumping: a soft pour/hiss of grains.
- `place_sand` (blocks) [-18 LUFS]: A sand block is placed. Sand set down: soft shush.
- `hit_sand` (blocks) [-17 LUFS]: Mining tick on sand (repeats ~4/s while digging). Shovel into sand: soft gritty scuff; must not tire the ear. Record 3-5 takes.
- `fall_sand` (players) [-16 LUFS]: Landing on sand after a fall. Landing on sand: soft thump and grain spray.
- `break_wood` (blocks) [-21 LUFS]: A wood block breaks. Wood splintering: crack, fibres tearing, planks clattering.
- `place_wood` (blocks) [-18 LUFS]: A wood block is placed. A wooden block set: hollow knock.
- `hit_wood` (blocks) [-16 LUFS]: Mining tick on wood (repeats ~4/s while digging). Axe/hand on wood: a short hollow tock; must not tire the ear. Record 3-5 takes.
- `fall_wood` (players) [-20 LUFS]: Landing on wood after a fall. Landing on boards: thud with a hollow board boom.
- `break_plant` (blocks) [-19 LUFS]: A plant block breaks. A stem snapping with a soft leafy rustle.
- `place_plant` (blocks) [-17 LUFS]: A plant block is placed. A plant pressed into soil: soft rustle.
- `hit_plant` (blocks) [-18 LUFS]: Mining tick on plant (repeats ~4/s while digging). Brushing a plant: tiny leafy tick; must not tire the ear. Record 3-5 takes.
- `fall_plant` (players) [-19 LUFS]: Landing on plant after a fall. Landing in plants: thump with a leafy crush.
- `break_glass` (blocks) [-16 LUFS]: A glass block breaks. Glass shattering: crash and tinkling shards.
- `place_glass` (blocks) [-18 LUFS]: A glass block is placed. Glass set down: light clink.
- `hit_glass` (blocks) [-24 LUFS]: Mining tick on glass (repeats ~4/s while digging). Tapping glass: thin clink; must not tire the ear. Record 3-5 takes.
- `fall_glass` (players) [-20 LUFS]: Landing on glass after a fall. Landing on glass: hard thud with a clink.
- `break_snow` (blocks) [-19 LUFS]: A snow block breaks. Snow block crumbling: soft crunch and powder fall.
- `place_snow` (blocks) [-20 LUFS]: A snow block is placed. Snow packed down: muffled crunch.
- `hit_snow` (blocks) [-20 LUFS]: Mining tick on snow (repeats ~4/s while digging). Hitting snow: soft crunchy tick; must not tire the ear. Record 3-5 takes.
- `fall_snow` (players) [-17 LUFS]: Landing on snow after a fall. Landing in snow: muffled thump with compressed crunch.
- `break_gravel` (blocks) [-20 LUFS]: A gravel block breaks. A gravel heap collapsing: pebbles pouring and clattering.
- `place_gravel` (blocks) [-19 LUFS]: A gravel block is placed. Gravel dumped: pebble pour.
- `hit_gravel` (blocks) [-18 LUFS]: Mining tick on gravel (repeats ~4/s while digging). Shovel into gravel: dry knock with pebble clicks (P118: must not sound like water); must not tire the ear. Record 3-5 takes. **WORST** (owner: hitting gravel sounds like punching water (P118))
- `fall_gravel` (players) [-15 LUFS]: Landing on gravel after a fall. Landing on gravel: thump with a big crunch.
- `break_metal` (blocks) [-19 LUFS]: A metal block breaks. Metal plates wrenched apart: clang and scraping.
- `place_metal` (blocks) [-22 LUFS]: A metal block is placed. A metal block set: solid clank.
- `hit_metal` (blocks) [-15 LUFS]: Mining tick on metal (repeats ~4/s while digging). Pick on metal: a bright tink, short; must not tire the ear. Record 3-5 takes.
- `fall_metal` (players) [-22 LUFS]: Landing on metal after a fall. Landing on steel deck: heavy clang-thud.
- `break_wool` (blocks) [-19 LUFS]: A wool block breaks. Fabric tearing softly.
- `place_wool` (blocks) [-19 LUFS]: A wool block is placed. Wool dropped: soft pad.
- `hit_wool` (blocks) [-18 LUFS]: Mining tick on wool (repeats ~4/s while digging). Hitting wool: soft muffled thup; must not tire the ear. Record 3-5 takes.
- `fall_wool` (players) [-16 LUFS]: Landing on wool after a fall. Landing on wool: soft muffled thump.
- `break_slime` (blocks) [-20 LUFS]: A slime block breaks. A slime block popping apart: wet splat.
- `place_slime` (blocks) [-20 LUFS]: A slime block is placed. Slime set: wet plop.
- `hit_slime` (blocks) [-17 LUFS]: Mining tick on slime (repeats ~4/s while digging). Poking slime: small wet squish; must not tire the ear. Record 3-5 takes.
- `fall_slime` (players) [-19 LUFS]: Landing on slime after a fall. Landing on slime: big bouncy squelch.
- `break_mud` (blocks) [-18 LUFS]: A mud block breaks. Mud clod tearing: wet slop.
- `place_mud` (blocks) [-19 LUFS]: A mud block is placed. Mud slapped down: wet slap.
- `hit_mud` (blocks) [-17 LUFS]: Mining tick on mud (repeats ~4/s while digging). Shovel into mud: wet squelch; must not tire the ear. Record 3-5 takes.
- `fall_mud` (players) [-17 LUFS]: Landing on mud after a fall. Landing in mud: heavy wet splat.
- `break_bone` (blocks) [-21 LUFS]: A bone block breaks. Bone cracking: brittle snap and clatter.
- `place_bone` (blocks) [-18 LUFS]: A bone block is placed. Bone block set: dry clack.
- `hit_bone` (blocks) [-22 LUFS]: Mining tick on bone (repeats ~4/s while digging). Tapping bone: hollow clack; must not tire the ear. Record 3-5 takes.
- `fall_bone` (players) [-21 LUFS]: Landing on bone after a fall. Landing on bone: thud and dry clack.
- `break_amethyst` (blocks) [-12 LUFS]: A amethyst block breaks. Crystal breaking: crack and ringing chime shards.
- `place_amethyst` (blocks) [-15 LUFS]: A amethyst block is placed. Crystal set: chime.
- `hit_amethyst` (blocks) [-12 LUFS]: Mining tick on amethyst (repeats ~4/s while digging). Tapping crystal: a short pure chime; must not tire the ear. Record 3-5 takes.
- `fall_amethyst` (players) [-18 LUFS]: Landing on amethyst after a fall. Landing on crystal: thud and chime.
- `break_soul` (blocks) [-18 LUFS]: A soul block breaks. Soul sand slumping: dry pour with a breathy whisper.
- `place_soul` (blocks) [-19 LUFS]: A soul block is placed. Soul sand set: soft shush.
- `hit_soul` (blocks) [-19 LUFS]: Mining tick on soul (repeats ~4/s while digging). Hitting soul sand: dry gritty scuff; must not tire the ear. Record 3-5 takes.
- `fall_soul` (players) [-16 LUFS]: Landing on soul after a fall. Landing on soul sand: soft thump, grain spray.
- `break_sculk` (blocks) [-19 LUFS]: A sculk block breaks. Sculk tearing: fleshy rip.
- `place_sculk` (blocks) [-21 LUFS]: A sculk block is placed. Sculk set: soft squish.
- `hit_sculk` (blocks) [-17 LUFS]: Mining tick on sculk (repeats ~4/s while digging). Poking sculk: small rubbery tick; must not tire the ear. Record 3-5 takes.
- `fall_sculk` (players) [-16 LUFS]: Landing on sculk after a fall. Landing on sculk: soft squishy thump.
- `break_netherrack` (blocks) [-20 LUFS]: A netherrack block breaks. Brittle rock crumbling to gravelly bits.
- `place_netherrack` (blocks) [-18 LUFS]: A netherrack block is placed. Crumbly block set down: soft crunch.
- `hit_netherrack` (blocks) [-17 LUFS]: Mining tick on netherrack (repeats ~4/s while digging). Pick on brittle rock: crumbly tick; must not tire the ear. Record 3-5 takes.
- `fall_netherrack` (players) [-17 LUFS]: Landing on netherrack after a fall. Landing on crumbly rock: thud and crunch.
- `break_deepslate` (blocks) [-20 LUFS]: A deepslate block breaks. Dense rock splitting: deeper crack, heavy chunks.
- `place_deepslate` (blocks) [-19 LUFS]: A deepslate block is placed. Dense block set down: low knock.
- `hit_deepslate` (blocks) [-18 LUFS]: Mining tick on deepslate (repeats ~4/s while digging). Pick on dense rock: low dull chink; must not tire the ear. Record 3-5 takes.
- `fall_deepslate` (players) [-19 LUFS]: Landing on deepslate after a fall. Landing on deep rock: thud, low scuff.
- `break_grass` (blocks) [-19 LUFS]: A grass block breaks. Turf tearing: roots ripping, soil crumbling.
- `place_grass` (blocks) [-20 LUFS]: A grass block is placed. A sod set down: soft pat with a tiny rustle.
- `hit_grass` (blocks) [-19 LUFS]: Mining tick on grass (repeats ~4/s while digging). Hand/shovel on turf: short soft scuff with blade crackle; must not tire the ear. Record 3-5 takes.
- `fall_grass` (players) [-19 LUFS]: Landing on grass after a fall. Landing on turf: dull thump, grass crush.
- `break_leaves` (blocks) [-20 LUFS]: A leaves block breaks. A leaf clump tearing: crisp rustle with twigs snapping (P89). **WORST** (owner: the leaf-breaking sound sounds wrong (P89); still a noise swish)
- `place_leaves` (blocks) [-18 LUFS]: A leaves block is placed. A leaf block set: soft rustle.
- `hit_leaves` (blocks) [-18 LUFS]: Mining tick on leaves (repeats ~4/s while digging). Hitting leaves: short crisp rustle with a twig tick; must not tire the ear. Record 3-5 takes. **WORST** (noise rustle repeats 4x/s while cutting: static)
- `fall_leaves` (players) [-16 LUFS]: Landing on leaves after a fall. Landing in leaves: soft thump with a big crisp rustle.

## Guns: shots and gun mechanics

gun_<n> is the Snd.gun slot (Guns.swift GunSpec.sound). Shots repeat in auto fire: 3-5 takes each, close-mic'd dry; the engine adds distance and reverb. gun_14 and gun_15 are rendered on demand (not in the prewarm list) but are real events.

- `gun_0` (players) [-23 LUFS]: Donnerkeil Service Rifle (gun_rifle). A punchy, mid-heavy assault-rifle crack with a short outdoor slap and a casing tinkle; must work in rapid auto fire. Record 3-5 takes. **WORST** (Donnerkeil rifle crack is noise bursts; guns are the main combat feel ('fix the weapons'))
- `gun_1` (players) [-20 LUFS]: Hummel Machine Gun (gun_smg, retired). A short, bright, light SMG report; fast auto. Record 3-5 takes.
- `gun_2` (players) [-21 LUFS]: Brecher Shotgun. A big wide 12-gauge boom with a low thump, then a pump-action rack. Record 3-5 takes. **WORST** (Brecher shotgun: noise blast without real low-end weight)
- `gun_3` (players) [-25 LUFS]: Fernblick Rifle and Longwatch Rifle (sniper). A supersonic snap with a heavy deep boom and a long rolling tail, then the bolt worked. Record 3-5 takes. **WORST** (Fernblick/Longwatch sniper: synthetic tail, no real supersonic snap)
- `gun_4` (players) [-18 LUFS]: Himmelsturm Launcher (rockets). An ignition thump then a hissing whoosh of the rocket leaving the tube. Record 3-5 takes.
- `gun_5` (players) [-13 LUFS]: Blitzlanze Arc Gun (energy beam). A capacitor whine rising, a crackling electric discharge, a zappy tail; sci-fi but physical. Record 3-5 takes.
- `gun_6` (players) [-25 LUFS]: generic soldier reload. Magazine out, magazine in, charging handle: brisk mechanical clicks.
- `gun_7` (players) [-23 LUFS]: dry fire (empty trigger). A hollow trigger/hammer click, dry and close.
- `gun_8` (players) [-12 LUFS]: ricochet. A spark tick then a whining bullet glide away. Record 3-5 takes.
- `gun_9` (players) [-24 LUFS]: deck gun / naval gun / tank main gun. A huge cannon boom, a chest-pressure thump and a long rolling echo tail. Record 3-5 takes.
- `gun_10` (players) [-15 LUFS]: Steelhold base alarm. A two-tone klaxon sweep, twice, over loudspeakers.
- `gun_11` (players) [-26 LUFS]: soldier radio call. A radio squelch, a short burst of band-limited speech, squelch out.
- `gun_12` (players) [-10 LUFS]: turret traverse whine. A servo motor whine as a gun mount turns.
- `gun_13` (players) [-25 LUFS]: Falke Pistol, Sechser Revolver, Wren Pistol, Breaker Revolver (sidearms). A sharp, light pistol crack with a quick slide/hammer cycle. Record 3-5 takes. **WORST** (one synth crack shared by four sidearms (Falke, Sechser, Wren, Breaker))
- `gun_16` (players): Kessel Bolt Rifle. A heavy full-power rifle crack, long rolling tail, then the bolt worked. Record 3-5 takes.
- `gun_17` (players): Hagel Machine Pistol (retired). A low, round, slow-cycling pistol-calibre pop. Record 3-5 takes.
- `gun_18` (players): Sturmwind Carbine and Slatefall Carbine. A hard mid crack between a rifle and a machine pistol. Record 3-5 takes. **WORST** (Sturmwind/Slatefall carbine: noise crack)
- `gun_19` (players): Kettensturm Machine Gun (Ashsaw) and Slate Repeater. A very short, dry, ripping crack; at its rate the shots run together into a tearing buzz. Record 3-5 takes.
- `gun_14` (players): magazine seated. A magazine seating with a firm thunk and the bolt slamming home (bright double clack); must read clearly (R7). **WORST** (magazine-seated cue is the key reload feedback (R7) and is synthesized)
- `gun_15` (players): last round fired. A hollow metallic ping as the bolt locks open.

## Reloads

Full reload sequences, timed to the reload animation (0.4-2.5 s).

- `gun_reload_0` (players) [-25 LUFS]: Reload, Donnerkeil Service Rifle (gun_rifle). Rifle: mag release, mag out, new mag in, charging handle. **WORST** (noise-click reload; R7 asks for a clear audible magazine click)
- `gun_reload_1` (players) [-24 LUFS]: Reload, Hummel Machine Gun (gun_smg, retired). Machine gun: mag out/in, bolt slap.
- `gun_reload_2` (players) [-24 LUFS]: Reload, Brecher Shotgun. Shotgun: three shells thumbed in, then the pump.
- `gun_reload_3` (players) [-24 LUFS]: Reload, Fernblick Rifle and Longwatch Rifle (sniper). Sniper: bolt up/back, round in, bolt forward/down.
- `gun_reload_4` (players) [-22 LUFS]: Reload, Himmelsturm Launcher (rockets). Launcher: heavy tube latch, rocket slides in, power-up chirp.
- `gun_reload_5` (players) [-15 LUFS]: Reload, Blitzlanze Arc Gun (energy beam). Arc gun: cell ejected, new cell in, capacitor charge whine.
- `gun_reload_13` (players) [-25 LUFS]: Reload, Falke Pistol, Sechser Revolver, Wren Pistol, Breaker Revolver (sidearms). Pistol/revolver: mag out/in and slide release (revolver: gate, rounds, gate).
- `gun_reload_16` (players): Reload, Kessel Bolt Rifle. Kessel: bolt open, five rounds from a stripper clip, clip flicked away, bolt closed.
- `gun_reload_17` (players): Reload, Hagel Machine Pistol (retired). Machine pistol: mag swap and bolt.
- `gun_reload_18` (players): Reload, Sturmwind Carbine and Slatefall Carbine. Carbine: mag swap and charging handle.
- `gun_reload_19` (players): Reload, Kettensturm Machine Gun (Ashsaw) and Slate Repeater. Ashsaw: feed cover up, belt laid in, cover slammed, bolt charged.

## Distant gunfire

Played instead of the close shot beyond ~48 blocks.

- `gun_distant_0` (players) [-25 LUFS]: Distant shot, Donnerkeil Service Rifle (gun_rifle) (heard 50-220 blocks away). The same weapon far off: a low thump/boom with a long outdoor echo, no crack.
- `gun_distant_1` (players) [-25 LUFS]: Distant shot, Hummel Machine Gun (gun_smg, retired) (heard 50-220 blocks away). The same weapon far off: a low thump/boom with a long outdoor echo, no crack.
- `gun_distant_2` (players) [-26 LUFS]: Distant shot, Brecher Shotgun (heard 50-220 blocks away). The same weapon far off: a low thump/boom with a long outdoor echo, no crack.
- `gun_distant_3` (players) [-22 LUFS]: Distant shot, Fernblick Rifle and Longwatch Rifle (sniper) (heard 50-220 blocks away). The same weapon far off: a low thump/boom with a long outdoor echo, no crack.
- `gun_distant_4` (players) [-24 LUFS]: Distant shot, Himmelsturm Launcher (rockets) (heard 50-220 blocks away). The same weapon far off: a low thump/boom with a long outdoor echo, no crack.
- `gun_distant_5` (players) [-22 LUFS]: Distant shot, Blitzlanze Arc Gun (energy beam) (heard 50-220 blocks away). The same weapon far off: a low thump/boom with a long outdoor echo, no crack.
- `gun_distant_13` (players) [-24 LUFS]: Distant shot, Falke Pistol, Sechser Revolver, Wren Pistol, Breaker Revolver (sidearms) (heard 50-220 blocks away). The same weapon far off: a low thump/boom with a long outdoor echo, no crack.
- `gun_distant_16` (players): Distant shot, Kessel Bolt Rifle (heard 50-220 blocks away). The same weapon far off: a low thump/boom with a long outdoor echo, no crack.
- `gun_distant_17` (players): Distant shot, Hagel Machine Pistol (retired) (heard 50-220 blocks away). The same weapon far off: a low thump/boom with a long outdoor echo, no crack.
- `gun_distant_18` (players): Distant shot, Sturmwind Carbine and Slatefall Carbine (heard 50-220 blocks away). The same weapon far off: a low thump/boom with a long outdoor echo, no crack.
- `gun_distant_19` (players): Distant shot, Kettensturm Machine Gun (Ashsaw) and Slate Repeater (heard 50-220 blocks away). The same weapon far off: a low thump/boom with a long outdoor echo, no crack.
- `gun_distant_9` (players) [-26 LUFS]: Distant shot, deck gun / naval gun / tank main gun (heard 50-220 blocks away). The same weapon far off: a low thump/boom with a long outdoor echo, no crack.

## Bullets, explosions and war

- `bulletWhizz` (players) [-20 LUFS]: A bullet passes close to you. A supersonic crack/whizz by the ear.
- `bulletFlesh` (players) [-15 LUFS]: A bullet hits a body. A meaty thwack. Record 3-5 takes. **WORST** (noise thwack, not a meaty hit)
- `grenadeBounce` (players) [-18 LUFS]: Grenade bounces. A metal can clunk on the ground.
- `rocketFlightLoop` (players) [-15 LUFS]: Rocket in flight (loop). A rocket motor's hissing roar.
- `shellFlightLoop` (players) [-14 LUFS]: Heavy shell overhead (loop). A tearing whistling whoosh.
- `shellIncoming` (players): Incoming artillery shell. A falling whistle before impact.
- `ashSiren` (hostile): Ash Vault alarm siren. A hand-cranked air-raid siren wail, rising and falling.
- `explodeSmall` (blocks) [-20 LUFS]: Grenade / small explosion. A sharp grenade bang with debris.
- `explodeLarge` (blocks) [-22 LUFS]: Big explosion (shells, vehicles). A massive blast with a long rolling tail.
- `debrisRain` (blocks) [-21 LUFS]: Debris pattering down after a blast. Dirt and stones raining down.
- `bullet_impact_stone` (players) [-17 LUFS]: Bullet impact on stone. A bullet smacking rock: sharp crack, chips and dust spray. Record 3-5 takes. **WORST** (the most-heard impact; a filtered burst, no chips or dust)
- `bullet_impact_dirt` (players) [-17 LUFS]: Bullet impact on dirt. Bullet into earth: dull thup and a puff of dirt. Record 3-5 takes.
- `bullet_impact_sand` (players) [-17 LUFS]: Bullet impact on sand. Bullet into sand: soft thup and grain hiss. Record 3-5 takes.
- `bullet_impact_wood` (players) [-21 LUFS]: Bullet impact on wood. Bullet into wood: thock and splinters. Record 3-5 takes.
- `bullet_impact_plant` (players) [-19 LUFS]: Bullet impact on plant. Bullet through leaves: quick leafy rip. Record 3-5 takes.
- `bullet_impact_glass` (players) [-19 LUFS]: Bullet impact on glass. Bullet through glass: crack and shard tinkle. Record 3-5 takes.
- `bullet_impact_snow` (players) [-21 LUFS]: Bullet impact on snow. Bullet into snow: soft puff. Record 3-5 takes.
- `bullet_impact_gravel` (players) [-18 LUFS]: Bullet impact on gravel. Bullet into gravel: crack and a spray of pebbles. Record 3-5 takes.
- `bullet_impact_metal` (players) [-20 LUFS]: Bullet impact on metal. Bullet on steel: a sharp ping/spang with a short whine. Record 3-5 takes.
- `bullet_impact_wool` (players) [-17 LUFS]: Bullet impact on wool. Bullet into cloth: soft thup. Record 3-5 takes.
- `bullet_impact_slime` (players) [-17 LUFS]: Bullet impact on slime. Bullet into slime: wet splat. Record 3-5 takes.
- `bullet_impact_mud` (players) [-16 LUFS]: Bullet impact on mud. Bullet into mud: wet thup. Record 3-5 takes.
- `bullet_impact_bone` (players) [-20 LUFS]: Bullet impact on bone. Bullet into bone: crack and splinter. Record 3-5 takes.
- `bullet_impact_amethyst` (players) [-15 LUFS]: Bullet impact on amethyst. Bullet into crystal: crack and chime. Record 3-5 takes.
- `bullet_impact_soul` (players) [-18 LUFS]: Bullet impact on soul. Bullet into soul sand: soft thup. Record 3-5 takes.
- `bullet_impact_sculk` (players) [-19 LUFS]: Bullet impact on sculk. Bullet into sculk: wet thup. Record 3-5 takes.
- `bullet_impact_netherrack` (players) [-18 LUFS]: Bullet impact on netherrack. Bullet into brittle rock: puff of crumbs. Record 3-5 takes.
- `bullet_impact_deepslate` (players) [-19 LUFS]: Bullet impact on deepslate. Bullet into dense rock: low crack and chips. Record 3-5 takes.
- `bullet_impact_grass` (players) [-18 LUFS]: Bullet impact on grass. Bullet into turf: dull thup, soil spray. Record 3-5 takes.
- `bullet_impact_leaves` (players) [-16 LUFS]: Bullet impact on leaves. Bullet through foliage: a quick crisp rip and twig snap. Record 3-5 takes.

## Soldier voices (Steelhold barks)

Spoken barks per rank. 3-4 different lines per bark (idle 4).

- `soldier_0_alert` (hostile) [-17 LUFS]: Steelhold Recruit: alert. Spotted you: a sharp shouted warning; voice: young, nervous voice; original lines, no real-army slogans.
- `soldier_0_attack` (hostile) [-25 LUFS]: Steelhold Recruit: attack. A battle cry / order to fire; voice: young, nervous voice; original lines, no real-army slogans.
- `soldier_0_reload` (hostile) [-25 LUFS]: Steelhold Recruit: reload. Calling a reload; voice: young, nervous voice; original lines, no real-army slogans.
- `soldier_0_grenade` (hostile) [-18 LUFS]: Steelhold Recruit: grenade. Shouting a grenade warning; voice: young, nervous voice; original lines, no real-army slogans.
- `soldier_0_hurt` (hostile) [-21 LUFS]: Steelhold Recruit: hurt. A pained grunt or shout; voice: young, nervous voice; original lines, no real-army slogans.
- `soldier_0_death` (hostile) [-20 LUFS]: Steelhold Recruit: death. A dying cry, cut short; voice: young, nervous voice; original lines, no real-army slogans.
- `soldier_0_idle` (hostile) [-21 LUFS]: Steelhold Recruit: idle. Idle patrol chatter or a mutter; voice: young, nervous voice; original lines, no real-army slogans.
- `soldier_0_retreat` (hostile) [-18 LUFS]: Steelhold Recruit: retreat. Calling a fallback; voice: young, nervous voice; original lines, no real-army slogans.
- `soldier_1_alert` (hostile) [-22 LUFS]: Steelhold Trooper: alert. Spotted you: a sharp shouted warning; voice: seasoned, firm voice; original lines, no real-army slogans. **WORST** (formant gibberish where a shouted line should be (all soldier_* barks share this problem))
- `soldier_1_attack` (hostile) [-22 LUFS]: Steelhold Trooper: attack. A battle cry / order to fire; voice: seasoned, firm voice; original lines, no real-army slogans.
- `soldier_1_reload` (hostile) [-23 LUFS]: Steelhold Trooper: reload. Calling a reload; voice: seasoned, firm voice; original lines, no real-army slogans.
- `soldier_1_grenade` (hostile) [-16 LUFS]: Steelhold Trooper: grenade. Shouting a grenade warning; voice: seasoned, firm voice; original lines, no real-army slogans.
- `soldier_1_hurt` (hostile) [-22 LUFS]: Steelhold Trooper: hurt. A pained grunt or shout; voice: seasoned, firm voice; original lines, no real-army slogans. **WORST** (formant grunt, robotic)
- `soldier_1_death` (hostile) [-23 LUFS]: Steelhold Trooper: death. A dying cry, cut short; voice: seasoned, firm voice; original lines, no real-army slogans.
- `soldier_1_idle` (hostile) [-20 LUFS]: Steelhold Trooper: idle. Idle patrol chatter or a mutter; voice: seasoned, firm voice; original lines, no real-army slogans.
- `soldier_1_retreat` (hostile) [-25 LUFS]: Steelhold Trooper: retreat. Calling a fallback; voice: seasoned, firm voice; original lines, no real-army slogans.
- `soldier_2_alert` (hostile) [-22 LUFS]: Steelhold Marksman: alert. Spotted you: a sharp shouted warning; voice: calm, clipped voice; original lines, no real-army slogans.
- `soldier_2_attack` (hostile) [-24 LUFS]: Steelhold Marksman: attack. A battle cry / order to fire; voice: calm, clipped voice; original lines, no real-army slogans.
- `soldier_2_reload` (hostile) [-22 LUFS]: Steelhold Marksman: reload. Calling a reload; voice: calm, clipped voice; original lines, no real-army slogans.
- `soldier_2_grenade` (hostile) [-16 LUFS]: Steelhold Marksman: grenade. Shouting a grenade warning; voice: calm, clipped voice; original lines, no real-army slogans.
- `soldier_2_hurt` (hostile) [-17 LUFS]: Steelhold Marksman: hurt. A pained grunt or shout; voice: calm, clipped voice; original lines, no real-army slogans.
- `soldier_2_death` (hostile) [-24 LUFS]: Steelhold Marksman: death. A dying cry, cut short; voice: calm, clipped voice; original lines, no real-army slogans.
- `soldier_2_idle` (hostile) [-23 LUFS]: Steelhold Marksman: idle. Idle patrol chatter or a mutter; voice: calm, clipped voice; original lines, no real-army slogans.
- `soldier_2_retreat` (hostile) [-22 LUFS]: Steelhold Marksman: retreat. Calling a fallback; voice: calm, clipped voice; original lines, no real-army slogans.
- `soldier_3_alert` (hostile) [-26 LUFS]: Steelhold Ironclad: alert. Spotted you: a sharp shouted warning; voice: big armoured heavy, deep muffled voice through a helmet; original lines, no real-army slogans.
- `soldier_3_attack` (hostile) [-20 LUFS]: Steelhold Ironclad: attack. A battle cry / order to fire; voice: big armoured heavy, deep muffled voice through a helmet; original lines, no real-army slogans.
- `soldier_3_reload` (hostile) [-27 LUFS]: Steelhold Ironclad: reload. Calling a reload; voice: big armoured heavy, deep muffled voice through a helmet; original lines, no real-army slogans.
- `soldier_3_grenade` (hostile) [-20 LUFS]: Steelhold Ironclad: grenade. Shouting a grenade warning; voice: big armoured heavy, deep muffled voice through a helmet; original lines, no real-army slogans.
- `soldier_3_hurt` (hostile) [-17 LUFS]: Steelhold Ironclad: hurt. A pained grunt or shout; voice: big armoured heavy, deep muffled voice through a helmet; original lines, no real-army slogans.
- `soldier_3_death` (hostile) [-20 LUFS]: Steelhold Ironclad: death. A dying cry, cut short; voice: big armoured heavy, deep muffled voice through a helmet; original lines, no real-army slogans.
- `soldier_3_idle` (hostile) [-30 LUFS]: Steelhold Ironclad: idle. Idle patrol chatter or a mutter; voice: big armoured heavy, deep muffled voice through a helmet; original lines, no real-army slogans.
- `soldier_3_retreat` (hostile) [-27 LUFS]: Steelhold Ironclad: retreat. Calling a fallback; voice: big armoured heavy, deep muffled voice through a helmet; original lines, no real-army slogans.

## Player actions and combat

- `splash` (players) [-21 LUFS]: Player or mob falls into water. A body plunging into water: a full splash with spray and bubbles. **WORST** (low-passed noise burst, no real water body)
- `swim` (players) [-21 LUFS]: Swimming stroke. An arm stroke through water: a soft slosh.
- `land` (players) [-23 LUFS]: Generic landing (no material). A body landing: dull heavy thump.
- `hurt` (players) [-24 LUFS]: Player takes damage. A short male/neutral pained grunt over a body impact (needs real voice; 3+ takes). Record 3-5 takes. **WORST** (player pain grunt is formant synthesis; heard constantly)
- `hurtFall` (players) [-25 LUFS]: Player takes fall damage. A hard landing crunch plus a pained grunt.
- `hurtDrown` (players) [-20 LUFS]: Player drowning damage. A choked gurgle with bubbles.
- `hurtFire` (players) [-31 LUFS]: Player burning damage. A sharp pained hiss of breath with fire crackle.
- `playerDeath` (players) [-26 LUFS]: Player dies. A final pained cry and a body collapsing to the ground. **WORST** (synth grunt + noise thud)
- `eat` (players) [-20 LUFS]: Eating food. Three chewy bites/crunches.
- `burp` (players) [-16 LUFS]: After finishing a meal. A short burp.
- `drink` (players) [-17 LUFS]: Drinking a potion/milk. Gulping swallows.
- `pickup` (players) [-16 LUFS]: Item picked up. A soft short 'pop' (game-y, keep subtle and pleasant).
- `dig` (players) [-24 LUFS]: Generic dig scuff. A short soft dig scuff.
- `attack` (players) [-19 LUFS]: Melee hit lands. A weapon swing whoosh into a meaty body hit. Record 3-5 takes.
- `attackSweep` (players) [-17 LUFS]: Sweeping sword attack. A wide sword whoosh.
- `attackCrit` (players) [-20 LUFS]: Critical melee hit. A harder, sharper body hit with a slight metallic ring. Record 3-5 takes.
- `attackKnockback` (players) [-20 LUFS]: Knockback hit. A heavy shove-hit thud.
- `attackWeak` (players) [-18 LUFS]: Weak/uncharged hit. A light swish and soft tap. Record 3-5 takes.
- `shieldBlock` (players) [-20 LUFS]: Shield blocks a hit. A wooden shield struck: solid knock with a metal rim ring.
- `shieldBreak` (players) [-18 LUFS]: Shield breaks. A wooden shield splintering.
- `itemBreak` (players) [-18 LUFS]: A tool wears out and breaks. A small snap and a metal tink.
- `bucketFill` (players) [-12 LUFS]: Bucket filled with water. Water glugging into a metal bucket.
- `bucketEmpty` (players) [-18 LUFS]: Bucket emptied of water. Water pouring out and splashing.
- `bucketFillLava` (players) [-14 LUFS]: Bucket filled with lava. Thick molten lava glooping into a bucket.
- `bucketEmptyLava` (players) [-26 LUFS]: Bucket emptied of lava. Heavy molten pour with a hiss.
- `fishCast` (players) [-22 LUFS]: Fishing rod cast. A rod whip and line whizz.
- `fishSplash` (players) [-16 LUFS]: Fish bites the bobber. A small splash of the bobber pulled under.
- `fishReel` (players) [-21 LUFS]: Reeling in. Line ratchet and a small splash out of the water.
- `xp` (players) [-15 LUFS]: Experience orb collected. A small bright pleasant chime (game-y).
- `levelUp` (players) [-19 LUFS]: Level up. A short rising rewarding chime arpeggio.
- `totem` (players) [-14 LUFS]: Totem of undying saves you. A magical rising shimmer and swell.
- `gasp` (players) [-16 LUFS]: Surfacing for air after being underwater. A sharp in-breath gasp.
- `throwItem` (players) [-18 LUFS]: Throwing an item. A short throw whoosh.
- `pearlThrow` (players) [-13 LUFS]: Throwing a void pearl. A whoosh with a faint rising magic tone.
- `potionThrow` (players) [-17 LUFS]: Throwing a splash potion. A whoosh with a glass bottle clink.
- `potionSplash` (players) [-16 LUFS]: Splash potion shatters. A glass bottle smashing with a liquid splash.
- `snowballHit` (players) [-22 LUFS]: Snowball hits. A soft snowy puff/thup.
- `eggCrack` (players) [-19 LUFS]: Thrown egg breaks. An eggshell crack and splat.
- `bowDraw` (players) [-16 LUFS]: Drawing a bow. String stretch and bow-limb creak.
- `bow` (players) [-19 LUFS]: Bow released. A string twang and arrow whoosh.
- `arrowHit` (players) [-19 LUFS]: Arrow hits something. An arrow thunk into a target.
- `crossbowLoad` (players) [-24 LUFS]: Loading a crossbow. A crank/ratchet and the string clicking into the latch.
- `crossbowShoot` (players) [-18 LUFS]: Crossbow fired. A hard mechanical twang and bolt whoosh.
- `tridentThrow` (players) [-16 LUFS]: Trident thrown. A heavy spear whoosh.
- `tridentHit` (players) [-17 LUFS]: Trident hits. A heavy metal spear impact with ring.
- `tridentReturn` (players) [-13 LUFS]: Loyal trident returns. A whooshing magical return.
- `riptide` (players) [-15 LUFS]: Riptide launch. A big rushing water surge.
- `windCharge` (players) [-15 LUFS]: Wind charge bursts. A sudden air blast whump.
- `shearsSnip` (players) [-18 LUFS]: Shears used. A metal scissor snip.
- `ignite` (players) [-24 LUFS]: Flint and steel lights a fire. A flint strike scrape and a small fire catching (whoomph).
- `spyglass` (players) [-22 LUFS]: Spyglass raised. A brass telescope sliding/extending click.
- `goatHorn` (players) [-12 LUFS]: Goat horn blown. A long, low, haunting horn call.
- `plantBrush` (players) [-16 LUFS]: Walking through tall plants and bushes. A leafy swish of stems against legs.
- `meleeWindUp` (hostile): Enemy winds up a melee attack (telegraph). A drawn breath and the scrape of a weapon going back.
- `parryClang` (players): Parry: weapon blocks weapon. Steel on steel: a bright clang.
- `bowCreak` (players): Bow held drawn. A slow wooden limb groan.
- `bowNock` (players): Arrow nocked. A small click of the arrow on the string.
- `boatPaddle` (players) [-20 LUFS]: Paddling a boat. An oar dipping into water.
- `armor_equip_0` (players) [-22 LUFS]: Armour put on. Leather: soft leather creak and strap buckle.
- `armor_equip_1` (players) [-20 LUFS]: Armour put on. Chainmail: a jingle of rings.
- `armor_equip_2` (players) [-17 LUFS]: Armour put on. Iron: clanky plate clicks.
- `armor_equip_3` (players) [-16 LUFS]: Armour put on. Gold: soft bright metal clinks.
- `armor_equip_4` (players) [-14 LUFS]: Armour put on. Diamond: hard glassy clinks.
- `armor_equip_5` (players) [-17 LUFS]: Armour put on. Duskium (top-tier armour): heavy dark plate clunk.

## Interface

Never spatialized; keep them short, soft and dry.

- `click` (ui) [-28 LUFS]: Menu button press. A short soft UI click, neutral and pleasant.
- `open` (ui) [-24 LUFS]: Menu/inventory opens. A soft UI whoosh-click.
- `uiHover` (ui) [-23 LUFS]: Pointer moves over a button. A very short faint tick.
- `uiBack` (ui) [-29 LUFS]: Menu back/close. A soft lower click.
- `toast` (ui) [-20 LUFS]: Notification/advancement toast. A short friendly two-note chime.

## Doors, containers, mechanisms and workblocks

- `doorOpen` (blocks) [-20 LUFS]: Wooden door opens. A wooden door: latch click and a short hinge creak. **WORST** (creak is a saw-wave pitch sweep: sounds like a synth chirp, not a hinge)
- `doorClose` (blocks) [-20 LUFS]: Wooden door closes. A wooden door shutting: knock into the frame and latch.
- `ironDoorOpen` (blocks) [-19 LUFS]: Iron door opens. A heavy iron door grinding open.
- `ironDoorClose` (blocks) [-22 LUFS]: Iron door closes. A heavy iron door clanging shut.
- `trapdoorOpen` (blocks) [-19 LUFS]: Wooden trapdoor opens. A light wooden hatch flipping open.
- `trapdoorClose` (blocks) [-19 LUFS]: Wooden trapdoor closes. A wooden hatch slapping shut.
- `ironTrapdoorOpen` (blocks) [-21 LUFS]: Iron trapdoor opens. A metal hatch opening with a clank.
- `ironTrapdoorClose` (blocks) [-21 LUFS]: Iron trapdoor closes. A metal hatch clanging shut.
- `gateOpen` (blocks) [-20 LUFS]: Fence gate opens. A wooden gate creak and latch.
- `gateClose` (blocks) [-20 LUFS]: Fence gate closes. A wooden gate knocking shut.
- `chestOpen` (blocks) [-21 LUFS]: Chest opens. A wooden chest lid creaking open. **WORST** (saw-wave 'creak' sweep again)
- `chestClose` (blocks) [-20 LUFS]: Chest closes. A wooden chest lid thumping shut.
- `enderChestOpen` (blocks) [-13 LUFS]: Void chest opens. A heavy stone lid with a magical shimmer.
- `enderChestClose` (blocks) [-16 LUFS]: Void chest closes. A heavy stone lid closing with a shimmer.
- `barrelOpen` (blocks) [-18 LUFS]: Barrel opens. A wooden barrel lid knock.
- `barrelClose` (blocks) [-20 LUFS]: Barrel closes. A wooden barrel lid set down.
- `shulkerOpen` (blocks) [-19 LUFS]: Shell box opens. A shell lid sliding open.
- `shulkerClose` (blocks) [-19 LUFS]: Shell box closes. A shell lid sliding shut.
- `pistonExtend` (blocks) [-18 LUFS]: Piston pushes. A mechanical push: whoosh of air and a stone shove.
- `pistonContract` (blocks) [-19 LUFS]: Piston retracts. A mechanical pull back with a clack.
- `lever` (blocks) [-18 LUFS]: Lever switched. A stiff mechanical click.
- `buttonWood` (blocks) [-19 LUFS]: Wooden button pressed. A soft wooden click.
- `buttonStone` (blocks) [-20 LUFS]: Stone button pressed. A hard stone click.
- `plateOn` (blocks) [-19 LUFS]: Pressure plate pressed. A soft plate click down.
- `plateOff` (blocks) [-21 LUFS]: Pressure plate released. A soft plate click up.
- `dispense` (blocks) [-18 LUFS]: Dispenser/dropper fires. A mechanical clack and launch.
- `dispenseFail` (blocks) [-22 LUFS]: Dispenser empty. Two dry empty clicks.
- `tripwire` (blocks) [-21 LUFS]: Tripwire triggered. A taut string twang/click.
- `fizz` (blocks) [-17 LUFS]: Water meets lava / fire put out. A steam hiss.
- `anvil` (blocks) [-20 LUFS]: Anvil used. A hammer strike on an anvil: bright ringing clang.
- `anvilLand` (blocks) [-18 LUFS]: Falling anvil lands. A heavy iron mass hitting ground: clang-thud.
- `anvilBreak` (blocks) [-18 LUFS]: Anvil breaks. Cracking iron and falling pieces.
- `enchant` (blocks) [-20 LUFS]: Item enchanted. A magical sparkly shimmer.
- `brew` (blocks) [-17 LUFS]: Brewing stand finishes. Bubbling glass and a fizz.
- `grindstone` (blocks) [-11 LUFS]: Grindstone used. A stone wheel grinding metal: scrape and sparks.
- `smithing` (blocks) [-20 LUFS]: Smithing table upgrade. Metal hammer taps on a workbench.
- `pageTurn` (blocks) [-16 LUFS]: Book page turned. A paper page flip.
- `composterFill` (blocks) [-22 LUFS]: Composter filled. Organic matter dropped into a wooden bin.
- `composterReady` (blocks) [-23 LUFS]: Composter ready. A soft rustle and a small pop.
- `itemFrameAdd` (blocks) [-16 LUFS]: Item put in frame. A light wooden frame tap.
- `itemFrameRemove` (blocks) [-16 LUFS]: Item taken from frame. A light wooden frame knock.
- `itemFrameRotate` (blocks) [-24 LUFS]: Item in frame rotated. A tiny click.
- `paintingPlace` (blocks) [-21 LUFS]: Painting hung. A canvas bump on the wall.
- `paintingBreak` (blocks) [-24 LUFS]: Painting knocked off. Canvas and frame clatter.
- `honeySlide` (blocks) [-18 LUFS]: Sliding down honey. A sticky slow slide.
- `amethystChime` (blocks) [-14 LUFS]: Crystal chimes when touched. Soft random crystal chimes.
- `waxOn` (blocks) [-18 LUFS]: Waxing copper. A waxy rub.
- `waxOff` (blocks) [-19 LUFS]: Scraping wax off. A scraping rub.
- `scrape` (blocks) [-12 LUFS]: Scraping oxidation off copper. An axe scraping metal.
- `bulbOn` (blocks) [-18 LUFS]: Copper bulb turns on. An electric click and hum-on.
- `bulbOff` (blocks) [-19 LUFS]: Copper bulb turns off. An electric click-off.
- `crafterCraft` (blocks) [-22 LUFS]: Auto-crafter crafts. Mechanical clatter and a pop.
- `crafterFail` (blocks) [-22 LUFS]: Auto-crafter fails. Two dull clicks.
- `vaultOpen` (blocks) [-16 LUFS]: Vault opens. A heavy metal mechanism unlocking.
- `vaultEject` (blocks) [-19 LUFS]: Vault ejects loot. A metallic pop and item spit.
- `vaultReject` (blocks) [-19 LUFS]: Vault rejects a key. A dull refusal clunk.
- `spawnerSpawn` (blocks) [-20 LUFS]: Spawner spawns a mob. A fiery whoosh/puff.
- `potBreak` (blocks) [-16 LUFS]: Decorated pot shatters. Ceramic pot smashing.
- `potInsert` (blocks) [-20 LUFS]: Item put in pot. An item clinking into a ceramic pot.
- `bundleInsert` (blocks) [-24 LUFS]: Item put in bundle. A leather pouch rustle.
- `bundleRemove` (blocks) [-19 LUFS]: Item taken from bundle. A leather pouch rustle out.
- `bedEnter` (blocks) [-20 LUFS]: Getting into bed. A body settling on a mattress and blanket rustle.
- `candleOut` (blocks) [-21 LUFS]: Candle blown out. A short soft blow.
- `lanternHang` (blocks) [-20 LUFS]: Lantern placed. A metal lantern clink on a chain.
- `respawnAnchorCharge` (blocks) [-12 LUFS]: Respawn anchor charged. A deep magical power-up hum.
- `respawnAnchorSet` (blocks) [-17 LUFS]: Respawn point set at an anchor. A magical resonant chime.
- `sculkClick` (blocks) [-19 LUFS]: Sculk sensor triggers. A fleshy organic click.
- `sculkShriek` (blocks) [-16 LUFS]: Sculk shrieker shrieks. An eerie piercing organic shriek.
- `sculkBloom` (blocks) [-12 LUFS]: Sculk catalyst blooms. A soft organic bloom pulse.
- `sculkSpread` (blocks) [-14 LUFS]: Sculk spreads. A soft fleshy squelch spreading.
- `bell` (blocks) [-14 LUFS]: Village bell rung. A bronze bell strike, clear and long.
- `bellResonate` (blocks) [-16 LUFS]: Bell resonates (raid nearby). A long humming bell resonance.
- `tntFuse` (blocks) [-14 LUFS]: TNT fuse lit. A sizzling burning fuse.
- `explode` (blocks) [-22 LUFS]: TNT / Powderwight explosion. A big close explosion: sharp crack, heavy boom, debris. **WORST** (noise-burst explosion without a real low-end punch or debris)
- `glassBreak` (blocks) [-13 LUFS]: Glass shatters. A pane shattering.
- `iceCrack` (blocks) [-19 LUFS]: Ice cracks. Ice splitting with sharp crackles.
- `portalTravel` (blocks) [-12 LUFS]: Travelling through an Emberdeep portal. A rising, swirling warp whoosh.
- `portalTrigger` (blocks) [-17 LUFS]: Standing in a portal (about to travel). A swelling warp hum.
- `endPortalOpen` (blocks) [-14 LUFS]: Hollow gate opens. A huge deep rumble and rising magical chord.
- `endPortalFrame` (blocks) [-18 LUFS]: Eye placed in a Hollow gate frame. A stone thunk with a magical ring.
- `beaconActivate` (blocks) [-14 LUFS]: Beacon powers on. A rising magical power-up chord.
- `beaconPower` (blocks) [-17 LUFS]: Beacon power chosen. A short bright magical chime.
- `beaconDeactivate` (blocks) [-14 LUFS]: Beacon powers off. A falling power-down tone.
- `fireExtinguish` (blocks) [-16 LUFS]: Fire put out. A hiss of steam.
- `railClick` (blocks) [-21 LUFS]: Rail switches. A metal rail click.
- `fireworkLaunch` (blocks) [-15 LUFS]: Firework launched. A whistling rocket climbing.
- `fireworkBlast` (blocks) [-21 LUFS]: Firework bursts. A crisp airburst pop.
- `fireworkBlastLarge` (blocks) [-20 LUFS]: Large firework bursts. A big booming airburst.
- `fireworkTwinkle` (blocks) [-15 LUFS]: Firework crackle stars. Crackling sparkles.

## Water and lava

Water events live in several groups; collected here. (splash, swim, bucket*, fish*, boatPaddle, riptide are listed above under player actions.)

- `waterLoop` (ambient) [-17 LUFS]: Flowing water nearby (loop). A small stream trickling over stones. **WORST** (bubble synthesis, sounds like a fish tank)
- `riverLoop` (ambient) [-19 LUFS]: River (loop). A wide river flowing.
- `waterfallLoop` (ambient) [-15 LUFS]: Waterfall (loop). A falling water roar.
- `oceanLoop` (ambient) [-22 LUFS]: Ocean/beach (loop). Waves breaking on a shore.
- `underwaterLoop` (players) [-16 LUFS]: Head under water (loop). A muffled underwater pressure hum with distant bubbles.
- `lavaLoop` (ambient) [-19 LUFS]: Lava nearby (loop). A thick bubbling, rumbling molten pool.
- `lavaPop` (ambient) [-10 LUFS]: Lava pops near you. A thick molten bubble bursting.
- `underwaterMood` (ambient) [-22 LUFS]: Underwater mood sting. A muffled deep whale-like moan.

## Weather

- `rain` (weather) [-21 LUFS]: Rain outdoors (loop). Steady rain on the ground and foliage. **WORST** (white-noise rain; the commonest weather loop)
- `rainRoof` (weather) [-21 LUFS]: Rain heard under a roof (loop). Rain drumming on a roof above.
- `rainLeavesLoop` (weather) [-23 LUFS]: Rain on forest leaves (loop). Rain pattering on leaves.
- `snowWindLoop` (weather) [-16 LUFS]: Snowstorm (loop). Blizzard wind with blowing snow.
- `thunder` (weather) [-23 LUFS]: Thunder (near). A close thunderclap: sharp crack then long rumble.
- `thunderFar` (weather) [-26 LUFS]: Distant thunder. A far rolling thunder rumble.
- `lightning` (weather) [-22 LUFS]: Lightning strike. A very close electrical crack and boom.
- `windGust` (weather) [-20 LUFS]: Wind gust. A passing gust of wind (wind is praised: keep the character).

## Vehicles, ships and airships

Loops must be seamless (the engine loops the whole file). Idle and full engine layers are cross-faded by throttle, so record them from the same engine.

- `engineIdleLoop` (blocks) [-16 LUFS]: Ship/vehicle engine idle (loop; cross-faded with full by throttle). A steady low marine/diesel engine idle. **WORST** (oscillator engine, buzzy and static)
- `engineFullLoop` (blocks) [-15 LUFS]: Ship/vehicle engine at full throttle (loop). The same engine working hard: louder, higher, rougher.
- `propSlowLoop` (blocks) [-25 LUFS]: Propeller at low speed (loop). A slow propeller thrum.
- `propFastLoop` (blocks) [-19 LUFS]: Propeller at high speed (loop). A fast propeller buzz-roar.
- `airshipWindLoop` (blocks) [-16 LUFS]: Wind over an airship deck (loop). Rushing wind with rigging hum.
- `wheelRollLoop` (blocks) [-20 LUFS]: Land vehicle wheels rolling (loop). Tyres/wheels rolling over ground with rattle.
- `hullWaterLoop` (blocks) [-20 LUFS]: Water along a moving hull (loop). Water rushing and slapping along a hull.
- `wingRushLoop` (blocks) [-15 LUFS]: Aircraft wing rush (loop). Fast air tearing over wings.
- `frigateDroneLoop` (blocks) [-23 LUFS]: Capital frigate overhead (loop). A vast deep engine drone, heard from far.
- `carriageTreadLoop` (blocks) [-19 LUFS]: Ironstride Siege Carriage treads (loop). Heavy tank treads squealing and clanking.
- `hullCreak` (blocks) [-16 LUFS]: Ship hull creaks. Wooden hull timbers creaking.
- `shipCollide` (blocks) [-21 LUFS]: Ship bumps something. A hull knock.
- `shipCollideHard` (blocks) [-25 LUFS]: Ship crashes. A heavy hull crash with splintering.
- `shipSplash` (blocks) [-17 LUFS]: Ship hits water. A big hull splash.
- `helmTake` (blocks) [-19 LUFS]: Taking the helm. A wooden wheel grab and creak.
- `engineStart` (blocks) [-17 LUFS]: Engine starts. An engine cranking and catching.
- `trainWhistle` (blocks): Steam train whistle. A classic steam whistle.
- `steamChuff` (blocks): Steam train chuff. A steam locomotive chuff.
- `shipCannon` (blocks) [-24 LUFS]: Ship cannon fires. A black-powder cannon boom with a hull shudder.
- `turretTraverseLoop` (blocks) [-18 LUFS]: Turret turning (loop). A geared turret ring rumble with servo whine.
- `mainGunCharge` (blocks) [-17 LUFS]: Tidebreaker main gun charging. A huge capacitor/charging rise, 3 s.
- `mainGunFire` (blocks) [-18 LUFS]: Tidebreaker main gun fires. An enormous blast heard across the map.
- `mainGunRumble` (blocks) [-31 LUFS]: Tidebreaker aftermath rumble. A long rolling echo across terrain.
- `minecartLoop` (players) [-19 LUFS]: Riding a minecart (loop). Iron wheels rolling over rail joints.
- `elytraLoop` (players) [-25 LUFS]: Gliding (loop). Wind rushing past at speed.

## Ambience beds and stings

Beds are seamless loops (2-9 s today; real beds can be 20-60 s); stings are one-shots dropped at random over the beds. See the biome table below for which plays where.

- `fireLoop` (ambient) [-24 LUFS]: Fire burning (loop). A wood fire crackling and roaring softly. **WORST** (crackle noise with no flame body)
- `furnaceLoop` (ambient) [-24 LUFS]: Lit furnace (loop). A contained fire with a low roar.
- `campfireLoop` (ambient) [-21 LUFS]: Campfire (loop). A cosy campfire crackle and pop.
- `portalLoop` (ambient) [-17 LUFS]: Emberdeep portal (loop). A swirling magical whoosh hum.
- `beaconLoop` (ambient) [-15 LUFS]: Active beacon (loop). A soft magical power hum.
- `respawnAnchorLoop` (ambient) [-15 LUFS]: Charged respawn anchor (loop). A low magical thrum.
- `spawnerLoop` (ambient) [-24 LUFS]: Monster spawner (loop). A small fiery whirl.
- `netherWastesLoop` (ambient) [-19 LUFS]: Emberdeep Wastes biome (loop). A hot hollow wind and deep drone.
- `soulValleyLoop` (ambient) [-20 LUFS]: Ghost Valley biome (loop). A ghostly moaning wind.
- `crimsonLoop` (ambient) [-18 LUFS]: Rustcap Forest biome (loop). A thick low drone with organic bubbles.
- `warpedLoop` (ambient) [-19 LUFS]: Tealcap Forest biome (loop). An alien hum with glassy bubbles.
- `basaltLoop` (ambient) [-21 LUFS]: Basalt Deltas biome (loop). A harsh wind with crackling rock.
- `ashVaultLoop` (ambient) [-21 LUFS]: The Ash Vault (loop). A hot wind under a huge roof, a low engine drone.
- `endLoop` (ambient) [-18 LUFS]: The Hollow (loop). A vast empty void drone.
- `deepDarkLoop` (ambient) [-19 LUFS]: Deep Dark (loop). A near-silent deep oppressive rumble.
- `lushLoop` (ambient) [-27 LUFS]: Lush caves (loop). A soft damp cave air with drips.
- `dripstoneLoop` (ambient) [-27 LUFS]: Dripstone caves (loop). Cave air with echoing drips.
- `cricketsLoop` (ambient) [-21 LUFS]: Night in grassland/forest (loop). Real crickets at night.
- `swampLoop` (ambient) [-27 LUFS]: Swamp at night (loop). Frogs croaking with insects.
- `windLoop` (ambient) [-21 LUFS]: Open-air wind (loop). Steady wind (praised: keep the character).
- `jungleLoop` (ambient) [-23 LUFS]: Jungle (loop). Dense jungle insects and distant birds.
- `fireflyLoop` (ambient) [-24 LUFS]: Meadow at night with fireflies (loop). A soft magical night shimmer.
- `hiveLoop` (ambient) [-24 LUFS]: Beehive/nest (loop). Many bees buzzing inside wood.
- `stationHumLoop` (ambient) [-19 LUFS]: Boreal Station bunker (loop). Mains hum and fluorescent buzz.
- `mountainWindLoop` (ambient) [-15 LUFS]: Mountain peak wind (loop). High cold wind whistling over rock.
- `tundraWindLoop` (ambient) [-17 LUFS]: Tundra wind (loop). A cold flat wind.
- `swampInsectsLoop` (ambient) [-20 LUFS]: Swamp by day (loop). Buzzing insects and water.
- `birdCall` (ambient) [-15 LUFS]: Bird call in forests/plains (day). A real songbird phrase (varied species per biome; 6 takes). **WORST** (synthesized chirps; obviously fake in every forest)
- `owlHoot` (ambient) [-14 LUFS]: Owl at night in forests. A distant owl hoot, two or three notes.
- `dryGrassRustle` (ambient) [-16 LUFS]: Wind through dry grass (badlands, savanna). A dry grass rustle gust.
- `heartCreak` (ambient) [-15 LUFS]: Creaking heart in the pale woods. An old wood creak with a deep pulse.
- `caveAmbience` (ambient) [-12 LUFS]: Cave mood sting. An eerie low cave rumble/moan, distant and reverberant.
- `caveDrip` (ambient) [-24 LUFS]: Water drip in caves. A single echoing water drip.
- `caveWind` (ambient) [-20 LUFS]: Cave draught. A low breathy wind through a tunnel.
- `netherMood` (ambient) [-25 LUFS]: Emberdeep mood sting. A distant hellish moan and rumble.
- `iceCreak` (ambient) [-14 LUFS]: Frozen lakes/tundra. Ice creaking and groaning under pressure.
- `rockfall` (ambient) [-20 LUFS]: Mountain rockfall. Stones tumbling down a slope.
- `volcanoRumble` (ambient) [-20 LUFS]: Volcano eruption. A huge deep eruption boom, heard from very far.

## Mob specials, bosses and townsfolk

- `creeperHiss` (hostile) [-10 LUFS]: Powderwight about to explode (key warning). A building, threatening fuse hiss.
- `fireball` (hostile) [-18 LUFS]: Fireball launched. A roaring fiery whoosh.
- `evokerCast` (hostile) [-21 LUFS]: Conjurer casting a spell. A magical incantation shimmer.
- `fangs` (hostile) [-16 LUFS]: Conjurer fangs snap out of the ground. Jaw-like bone snaps.
- `raidHorn` (hostile) [-11 LUFS]: Raid begins. A deep ominous war horn.
- `mobVoidwalker` (hostile) [-28 LUFS]: Voidwalker stare/scream (legacy name; renders the Voidwalker idle). A deep warped vocal warble.
- `teleport` (hostile) [-16 LUFS]: Voidwalker/void pearl teleport. A warpy whoosh-pop.
- `dragonGrowl` (hostile) [-16 LUFS]: Hollow Wyrm growl. A vast dragon growl, carries far.
- `dragonFlap` (hostile) [-16 LUFS]: Hollow Wyrm wing beat. Huge leathery wing whoomph.
- `dragonShoot` (hostile) [-16 LUFS]: Hollow Wyrm spits acid. A hissing launch.
- `dragonDeath` (hostile) [-16 LUFS]: Hollow Wyrm dies. A long dying roar rising into light.
- `crystalBreak` (hostile) [-20 LUFS]: Hollow Crystal destroyed. A crystal explosion.
- `witherSpawn` (hostile) [-16 LUFS]: Blight summoned. A huge charging boom and howl.
- `witherShoot` (hostile) [-14 LUFS]: Blight fires a skull. A hollow skull launch.
- `witherDeath` (hostile) [-16 LUFS]: Blight dies. A long ghostly death howl and boom.
- `wardenHeartbeat` (hostile) [-17 LUFS]: Deep Stalker heartbeat. A deep slow heartbeat thump.
- `wardenRoar` (hostile) [-16 LUFS]: Deep Stalker roars. A monstrous roar.
- `wardenSonicCharge` (hostile) [-13 LUFS]: Deep Stalker charges its sonic attack. A rising deep inhale/charge hum.
- `wardenSonicBoom` (hostile) [-15 LUFS]: Deep Stalker sonic boom. A concussive sonic blast.
- `wardenEmerge` (hostile) [-21 LUFS]: Deep Stalker emerges. Earth and sculk heaving, a deep groan.
- `wardenDig` (hostile) [-24 LUFS]: Deep Stalker digs back down. Earth churning.
- `wardenSniff` (hostile) [-19 LUFS]: Deep Stalker sniffs. A big wet sniff.
- `elderCurse` (hostile) [-21 LUFS]: Elder Spikefish curse. A ghostly underwater wail.
- `guardianLaser` (hostile) [-11 LUFS]: Spikefish laser charge. A rising electric beam whine.
- `zombieBreakDoor` (hostile) [-18 LUFS]: Zombie bashing a door. A heavy thump on a wooden door with splintering.
- `zombieInfect` (hostile) [-18 LUFS]: Zombie infects a townsperson. A groan and a sick gurgle.
- `phantomSwoop` (hostile) [-12 LUFS]: Nightwing swoops. A screeching dive whoosh.
- `beeSting` (hostile) [-13 LUFS]: Bee stings. A tiny sharp buzz-sting.
- `breezeShoot` (hostile) [-16 LUFS]: Gustling fires a wind charge. A whirling air shot.
- `villagerYes` (friendly) [-18 LUFS]: Townsperson agrees / trade ok. A pleased short murmur (wordless 'mm-hm'). **WORST** (formant 'hum' reads as a synth buzz)
- `villagerNo` (friendly) [-13 LUFS]: Townsperson refuses. A displeased short murmur ('mm-mm').
- `villagerTrade` (friendly) [-19 LUFS]: Trade done. A satisfied murmur.
- `villagerCelebrate` (friendly) [-16 LUFS]: Townsfolk celebrate after a raid. Happy cheering murmurs.
- `zombieCure` (friendly) [-14 LUFS]: Zombie townsperson cured. A magical sizzle and a relieved sigh.
- `beePollinate` (friendly) [-11 LUFS]: Bee pollinating. A contented buzzing loop-let.
- `allayItem` (friendly) [-13 LUFS]: Fetchling picks/gives an item. A sweet little chime.
- `foxSniff` (friendly) [-18 LUFS]: Fox sniffs. A small sniff.
- `catPurr` (friendly) [-13 LUFS]: Cat purrs. A soft purr.
- `wolfPant` (friendly) [-21 LUFS]: Wolf pants. Dog panting.
- `parrotMimic` (friendly) [-9 LUFS]: Parrot imitates a mob. A squawky imitation.
- `dolphinJump` (friendly) [-12 LUFS]: Dolphin leaps. A splash and a click.
- `turtleEggCrack` (friendly) [-20 LUFS]: Turtle egg cracks. A small shell crack.
- `frogTongue` (friendly) [-17 LUFS]: Frog eats. A sticky tongue flick.
- `goatRam` (friendly) [-17 LUFS]: Goat rams. A hard head-butt thud.
- `villager_work_0` (friendly) [-18 LUFS]: Townsperson working at a armorer workstation. Blast furnace roar and hammer tap.
- `villager_work_1` (friendly) [-19 LUFS]: Townsperson working at a butcher workstation. Cleaver chop on a smoker board.
- `villager_work_2` (friendly) [-23 LUFS]: Townsperson working at a cartographer workstation. Pen scratch and paper rustle.
- `villager_work_3` (friendly) [-15 LUFS]: Townsperson working at a cleric workstation. Brewing bubbles and a glass clink.
- `villager_work_4` (friendly) [-23 LUFS]: Townsperson working at a farmer workstation. Compost scoop and shuffle.
- `villager_work_5` (friendly) [-17 LUFS]: Townsperson working at a fisherman workstation. Barrel lid knock and splash.
- `villager_work_6` (friendly) [-18 LUFS]: Townsperson working at a fletcher workstation. Feather fletching and wood whittle.
- `villager_work_7` (friendly) [-19 LUFS]: Townsperson working at a leatherworker workstation. Cauldron stir and leather slap.
- `villager_work_8` (friendly) [-17 LUFS]: Townsperson working at a librarian workstation. Lectern page flip.
- `villager_work_9` (friendly) [-21 LUFS]: Townsperson working at a mason workstation. Chisel tapping stone.
- `villager_work_10` (friendly) [-20 LUFS]: Townsperson working at a shepherd workstation. Loom shuttle clack.
- `villager_work_11` (friendly) [-17 LUFS]: Townsperson working at a toolsmith workstation. Smithing table hammer clink.
- `villager_work_12` (friendly) [-17 LUFS]: Townsperson working at a weaponsmith workstation. Grindstone sharpening scrape.

## Every mob: idle, hurt, death

One file set per mob kind (MobKind key = the stable save key, not the display name). Silent kinds (minecart, boat, armor stand, hollow crystal) have none. Two takes for idle and hurt.

- `mob_cow_ambient` (friendly) [-23 LUFS]: Cow idle call. Cow idle call, every few seconds nearby: a low, relaxed bovine moo.
- `mob_cow_hurt` (friendly) [-20 LUFS]: Cow hurt. Cow is hit: a short sharp pained version of its voice (a low, relaxed bovine moo), 0.2-0.6 s.
- `mob_cow_death` (friendly) [-23 LUFS]: Cow death. Cow dies: a longer falling cry of its voice (a low, relaxed bovine moo), then silence; 0.5-2 s.
- `mob_sheep_ambient` (friendly) [-18 LUFS]: Sheep idle call. Sheep idle call, every few seconds nearby: a nasal sheep bleat.
- `mob_sheep_hurt` (friendly) [-24 LUFS]: Sheep hurt. Sheep is hit: a short sharp pained version of its voice (a nasal sheep bleat), 0.2-0.6 s.
- `mob_sheep_death` (friendly) [-24 LUFS]: Sheep death. Sheep dies: a longer falling cry of its voice (a nasal sheep bleat), then silence; 0.5-2 s.
- `mob_chicken_ambient` (friendly) [-18 LUFS]: Chicken idle call. Chicken idle call, every few seconds nearby: chicken clucks and a short cackle.
- `mob_chicken_hurt` (friendly) [-19 LUFS]: Chicken hurt. Chicken is hit: a short sharp pained version of its voice (chicken clucks and a short cackle), 0.2-0.6 s.
- `mob_chicken_death` (friendly) [-18 LUFS]: Chicken death. Chicken dies: a longer falling cry of its voice (chicken clucks and a short cackle), then silence; 0.5-2 s.
- `mob_pig_ambient` (friendly) [-25 LUFS]: Pig idle call. Pig idle call, every few seconds nearby: pig grunts and snorts.
- `mob_pig_hurt` (friendly) [-22 LUFS]: Pig hurt. Pig is hit: a short sharp pained version of its voice (pig grunts and snorts), 0.2-0.6 s.
- `mob_pig_death` (friendly) [-23 LUFS]: Pig death. Pig dies: a longer falling cry of its voice (pig grunts and snorts), then silence; 0.5-2 s.
- `mob_zombie_ambient` (hostile) [-24 LUFS]: Zombie idle call. Zombie idle call, every few seconds nearby: a slow guttural undead groan. **WORST** (formant groan; the most common hostile voice)
- `mob_zombie_hurt` (hostile) [-22 LUFS]: Zombie hurt. Zombie is hit: a short sharp pained version of its voice (a slow guttural undead groan), 0.2-0.6 s.
- `mob_zombie_death` (hostile) [-25 LUFS]: Zombie death. Zombie dies: a longer falling cry of its voice (a slow guttural undead groan), then silence; 0.5-2 s.
- `mob_skeleton_ambient` (hostile) [-28 LUFS]: Skeleton idle call. Skeleton idle call, every few seconds nearby: dry bone rattles and clacks, no voice.
- `mob_skeleton_hurt` (hostile) [-22 LUFS]: Skeleton hurt. Skeleton is hit: a short sharp pained version of its voice (dry bone rattles and clacks, no voice), 0.2-0.6 s.
- `mob_skeleton_death` (hostile) [-28 LUFS]: Skeleton death. Skeleton dies: a longer falling cry of its voice (dry bone rattles and clacks, no voice), then silence; 0.5-2 s.
- `mob_creeper_ambient` (hostile) [-24 LUFS]: Powderwight idle call. Powderwight idle call, every few seconds nearby: a quiet dry rustle/hiss (it is mostly silent until it fuses).
- `mob_creeper_hurt` (hostile) [-21 LUFS]: Powderwight hurt. Powderwight is hit: a short sharp pained version of its voice (a quiet dry rustle/hiss (it is mostly silent until it fuses)), 0.2-0.6 s.
- `mob_creeper_death` (hostile) [-20 LUFS]: Powderwight death. Powderwight dies: a longer falling cry of its voice (a quiet dry rustle/hiss (it is mostly silent until it fuses)), then silence; 0.5-2 s.
- `mob_spider_ambient` (hostile) [-23 LUFS]: Spider idle call. Spider idle call, every few seconds nearby: a dry chittering hiss and clicking mandibles.
- `mob_spider_hurt` (hostile) [-21 LUFS]: Spider hurt. Spider is hit: a short sharp pained version of its voice (a dry chittering hiss and clicking mandibles), 0.2-0.6 s.
- `mob_spider_death` (hostile) [-20 LUFS]: Spider death. Spider dies: a longer falling cry of its voice (a dry chittering hiss and clicking mandibles), then silence; 0.5-2 s.
- `mob_enderman_ambient` (hostile) [-28 LUFS]: Voidwalker idle call. Voidwalker idle call, every few seconds nearby: a deep, warped, reversed-sounding vocal warble.
- `mob_enderman_hurt` (hostile) [-25 LUFS]: Voidwalker hurt. Voidwalker is hit: a short sharp pained version of its voice (a deep, warped, reversed-sounding vocal warble), 0.2-0.6 s.
- `mob_enderman_death` (hostile) [-26 LUFS]: Voidwalker death. Voidwalker dies: a longer falling cry of its voice (a deep, warped, reversed-sounding vocal warble), then silence; 0.5-2 s.
- `mob_slime_ambient` (hostile) [-21 LUFS]: Slime idle call. Slime idle call, every few seconds nearby: wet bouncy squishes.
- `mob_slime_hurt` (hostile) [-21 LUFS]: Slime hurt. Slime is hit: a short sharp pained version of its voice (wet bouncy squishes), 0.2-0.6 s.
- `mob_slime_death` (hostile) [-25 LUFS]: Slime death. Slime dies: a longer falling cry of its voice (wet bouncy squishes), then silence; 0.5-2 s.
- `mob_zombified_piglin_ambient` (hostile) [-21 LUFS]: Undead Boarling idle call. Undead Boarling idle call, every few seconds nearby: a rotten wet pig-like groan.
- `mob_zombified_piglin_hurt` (hostile) [-21 LUFS]: Undead Boarling hurt. Undead Boarling is hit: a short sharp pained version of its voice (a rotten wet pig-like groan), 0.2-0.6 s.
- `mob_zombified_piglin_death` (hostile) [-21 LUFS]: Undead Boarling death. Undead Boarling dies: a longer falling cry of its voice (a rotten wet pig-like groan), then silence; 0.5-2 s.
- `mob_piglin_ambient` (hostile) [-23 LUFS]: Boarling idle call. Boarling idle call, every few seconds nearby: snuffly pig-man grunts and mutters.
- `mob_piglin_hurt` (hostile) [-22 LUFS]: Boarling hurt. Boarling is hit: a short sharp pained version of its voice (snuffly pig-man grunts and mutters), 0.2-0.6 s.
- `mob_piglin_death` (hostile) [-22 LUFS]: Boarling death. Boarling dies: a longer falling cry of its voice (snuffly pig-man grunts and mutters), then silence; 0.5-2 s.
- `mob_ghast_ambient` (hostile) [-24 LUFS]: Wailer idle call. Wailer idle call, every few seconds nearby: a huge floating creature's mournful high wail, echoing.
- `mob_ghast_hurt` (hostile) [-23 LUFS]: Wailer hurt. Wailer is hit: a short sharp pained version of its voice (a huge floating creature's mournful high wail, echoing), 0.2-0.6 s.
- `mob_ghast_death` (hostile) [-24 LUFS]: Wailer death. Wailer dies: a longer falling cry of its voice (a huge floating creature's mournful high wail, echoing), then silence; 0.5-2 s.
- `mob_blaze_ambient` (hostile) [-23 LUFS]: Cinderwisp idle call. Cinderwisp idle call, every few seconds nearby: a crackling fiery breath and metallic rattle.
- `mob_blaze_hurt` (hostile) [-22 LUFS]: Cinderwisp hurt. Cinderwisp is hit: a short sharp pained version of its voice (a crackling fiery breath and metallic rattle), 0.2-0.6 s.
- `mob_blaze_death` (hostile) [-21 LUFS]: Cinderwisp death. Cinderwisp dies: a longer falling cry of its voice (a crackling fiery breath and metallic rattle), then silence; 0.5-2 s.
- `mob_magma_cube_ambient` (hostile) [-22 LUFS]: Lava Blob idle call. Lava Blob idle call, every few seconds nearby: hot heavy squelches.
- `mob_magma_cube_hurt` (hostile) [-20 LUFS]: Lava Blob hurt. Lava Blob is hit: a short sharp pained version of its voice (hot heavy squelches), 0.2-0.6 s.
- `mob_magma_cube_death` (hostile) [-24 LUFS]: Lava Blob death. Lava Blob dies: a longer falling cry of its voice (hot heavy squelches), then silence; 0.5-2 s.
- `mob_wither_skeleton_ambient` (hostile) [-30 LUFS]: Blight Skeleton idle call. Blight Skeleton idle call, every few seconds nearby: heavier, lower bone rattles.
- `mob_wither_skeleton_hurt` (hostile) [-23 LUFS]: Blight Skeleton hurt. Blight Skeleton is hit: a short sharp pained version of its voice (heavier, lower bone rattles), 0.2-0.6 s.
- `mob_wither_skeleton_death` (hostile) [-29 LUFS]: Blight Skeleton death. Blight Skeleton dies: a longer falling cry of its voice (heavier, lower bone rattles), then silence; 0.5-2 s.
- `mob_hoglin_ambient` (hostile) [-24 LUFS]: Tusker idle call. Tusker idle call, every few seconds nearby: a big boar's deep grunts and snorts.
- `mob_hoglin_hurt` (hostile) [-25 LUFS]: Tusker hurt. Tusker is hit: a short sharp pained version of its voice (a big boar's deep grunts and snorts), 0.2-0.6 s.
- `mob_hoglin_death` (hostile) [-26 LUFS]: Tusker death. Tusker dies: a longer falling cry of its voice (a big boar's deep grunts and snorts), then silence; 0.5-2 s.
- `mob_piglin_brute_ambient` (hostile) [-28 LUFS]: Boarling Brute idle call. Boarling Brute idle call, every few seconds nearby: a big angry pig-man growl.
- `mob_piglin_brute_hurt` (hostile) [-23 LUFS]: Boarling Brute hurt. Boarling Brute is hit: a short sharp pained version of its voice (a big angry pig-man growl), 0.2-0.6 s.
- `mob_piglin_brute_death` (hostile) [-25 LUFS]: Boarling Brute death. Boarling Brute dies: a longer falling cry of its voice (a big angry pig-man growl), then silence; 0.5-2 s.
- `mob_strider_ambient` (friendly) [-17 LUFS]: Magmastrider idle call. Magmastrider idle call, every few seconds nearby: a squeaky, chirping trill.
- `mob_strider_hurt` (friendly) [-16 LUFS]: Magmastrider hurt. Magmastrider is hit: a short sharp pained version of its voice (a squeaky, chirping trill), 0.2-0.6 s.
- `mob_strider_death` (friendly) [-18 LUFS]: Magmastrider death. Magmastrider dies: a longer falling cry of its voice (a squeaky, chirping trill), then silence; 0.5-2 s.
- `mob_ender_dragon_ambient` (hostile) [-23 LUFS]: Hollow Wyrm idle call. Hollow Wyrm idle call, every few seconds nearby: a vast dragon roar.
- `mob_ender_dragon_hurt` (hostile) [-21 LUFS]: Hollow Wyrm hurt. Hollow Wyrm is hit: a short sharp pained version of its voice (a vast dragon roar), 0.2-0.6 s.
- `mob_ender_dragon_death` (hostile) [-26 LUFS]: Hollow Wyrm death. Hollow Wyrm dies: a longer falling cry of its voice (a vast dragon roar), then silence; 0.5-2 s.
- `mob_silverfish_ambient` (hostile) [-25 LUFS]: Silverfish idle call. Silverfish idle call, every few seconds nearby: tiny dry insect clicks.
- `mob_silverfish_hurt` (hostile) [-23 LUFS]: Silverfish hurt. Silverfish is hit: a short sharp pained version of its voice (tiny dry insect clicks), 0.2-0.6 s.
- `mob_silverfish_death` (hostile) [-23 LUFS]: Silverfish death. Silverfish dies: a longer falling cry of its voice (tiny dry insect clicks), then silence; 0.5-2 s.
- `mob_shulker_ambient` (hostile) [-29 LUFS]: Shellsentry idle call. Shellsentry idle call, every few seconds nearby: a shell lid clack with a soft creature peep.
- `mob_shulker_hurt` (hostile) [-27 LUFS]: Shellsentry hurt. Shellsentry is hit: a short sharp pained version of its voice (a shell lid clack with a soft creature peep), 0.2-0.6 s.
- `mob_shulker_death` (hostile) [-27 LUFS]: Shellsentry death. Shellsentry dies: a longer falling cry of its voice (a shell lid clack with a soft creature peep), then silence; 0.5-2 s.
- `mob_villager_ambient` (friendly) [-18 LUFS]: Townsperson idle call. Townsperson idle call, every few seconds nearby: a short wordless murmur 'hmm' (no real words).
- `mob_villager_hurt` (friendly) [-21 LUFS]: Townsperson hurt. Townsperson is hit: a short sharp pained version of its voice (a short wordless murmur 'hmm' (no real words)), 0.2-0.6 s.
- `mob_villager_death` (friendly) [-24 LUFS]: Townsperson death. Townsperson dies: a longer falling cry of its voice (a short wordless murmur 'hmm' (no real words)), then silence; 0.5-2 s.
- `mob_iron_golem_ambient` (friendly) [-24 LUFS]: Iron Golem idle call. Iron Golem idle call, every few seconds nearby: a heavy metallic creak and rumble.
- `mob_iron_golem_hurt` (friendly) [-25 LUFS]: Iron Golem hurt. Iron Golem is hit: a short sharp pained version of its voice (a heavy metallic creak and rumble), 0.2-0.6 s.
- `mob_iron_golem_death` (friendly) [-24 LUFS]: Iron Golem death. Iron Golem dies: a longer falling cry of its voice (a heavy metallic creak and rumble), then silence; 0.5-2 s.
- `mob_husk_ambient` (hostile) [-24 LUFS]: Dust Zombie idle call. Dust Zombie idle call, every few seconds nearby: a dry, raspier zombie groan.
- `mob_husk_hurt` (hostile) [-22 LUFS]: Dust Zombie hurt. Dust Zombie is hit: a short sharp pained version of its voice (a dry, raspier zombie groan), 0.2-0.6 s.
- `mob_husk_death` (hostile) [-25 LUFS]: Dust Zombie death. Dust Zombie dies: a longer falling cry of its voice (a dry, raspier zombie groan), then silence; 0.5-2 s.
- `mob_stray_ambient` (hostile) [-28 LUFS]: Frost Skeleton idle call. Frost Skeleton idle call, every few seconds nearby: brittle icy bone rattles.
- `mob_stray_hurt` (hostile) [-22 LUFS]: Frost Skeleton hurt. Frost Skeleton is hit: a short sharp pained version of its voice (brittle icy bone rattles), 0.2-0.6 s.
- `mob_stray_death` (hostile) [-27 LUFS]: Frost Skeleton death. Frost Skeleton dies: a longer falling cry of its voice (brittle icy bone rattles), then silence; 0.5-2 s.
- `mob_drowned_ambient` (hostile) [-24 LUFS]: Sunken idle call. Sunken idle call, every few seconds nearby: a gurgling, waterlogged groan.
- `mob_drowned_hurt` (hostile) [-22 LUFS]: Sunken hurt. Sunken is hit: a short sharp pained version of its voice (a gurgling, waterlogged groan), 0.2-0.6 s.
- `mob_drowned_death` (hostile) [-24 LUFS]: Sunken death. Sunken dies: a longer falling cry of its voice (a gurgling, waterlogged groan), then silence; 0.5-2 s.
- `mob_cave_spider_ambient` (hostile) [-22 LUFS]: Cave Spider idle call. Cave Spider idle call, every few seconds nearby: a smaller, higher chittering hiss.
- `mob_cave_spider_hurt` (hostile) [-21 LUFS]: Cave Spider hurt. Cave Spider is hit: a short sharp pained version of its voice (a smaller, higher chittering hiss), 0.2-0.6 s.
- `mob_cave_spider_death` (hostile) [-20 LUFS]: Cave Spider death. Cave Spider dies: a longer falling cry of its voice (a smaller, higher chittering hiss), then silence; 0.5-2 s.
- `mob_witch_ambient` (hostile) [-20 LUFS]: Witch idle call. Witch idle call, every few seconds nearby: a nasal cackle/murmur.
- `mob_witch_hurt` (hostile) [-23 LUFS]: Witch hurt. Witch is hit: a short sharp pained version of its voice (a nasal cackle/murmur), 0.2-0.6 s.
- `mob_witch_death` (hostile) [-22 LUFS]: Witch death. Witch dies: a longer falling cry of its voice (a nasal cackle/murmur), then silence; 0.5-2 s.
- `mob_pillager_ambient` (hostile) [-21 LUFS]: Marauder idle call. Marauder idle call, every few seconds nearby: a gruff wordless grunt/murmur.
- `mob_pillager_hurt` (hostile) [-19 LUFS]: Marauder hurt. Marauder is hit: a short sharp pained version of its voice (a gruff wordless grunt/murmur), 0.2-0.6 s.
- `mob_pillager_death` (hostile) [-20 LUFS]: Marauder death. Marauder dies: a longer falling cry of its voice (a gruff wordless grunt/murmur), then silence; 0.5-2 s.
- `mob_vindicator_ambient` (hostile) [-21 LUFS]: Brigand idle call. Brigand idle call, every few seconds nearby: an aggressive gruff mutter.
- `mob_vindicator_hurt` (hostile) [-18 LUFS]: Brigand hurt. Brigand is hit: a short sharp pained version of its voice (an aggressive gruff mutter), 0.2-0.6 s.
- `mob_vindicator_death` (hostile) [-20 LUFS]: Brigand death. Brigand dies: a longer falling cry of its voice (an aggressive gruff mutter), then silence; 0.5-2 s.
- `mob_wither_ambient` (hostile) [-23 LUFS]: Blight idle call. Blight idle call, every few seconds nearby: a multi-headed hollow, howling groan.
- `mob_wither_hurt` (hostile) [-20 LUFS]: Blight hurt. Blight is hit: a short sharp pained version of its voice (a multi-headed hollow, howling groan), 0.2-0.6 s.
- `mob_wither_death` (hostile) [-24 LUFS]: Blight death. Blight dies: a longer falling cry of its voice (a multi-headed hollow, howling groan), then silence; 0.5-2 s.
- `mob_snow_golem_ambient` (friendly) [-23 LUFS]: Snow Golem idle call. Snow Golem idle call, every few seconds nearby: a soft snowy crunch and a hollow pumpkin knock.
- `mob_snow_golem_hurt` (friendly) [-24 LUFS]: Snow Golem hurt. Snow Golem is hit: a short sharp pained version of its voice (a soft snowy crunch and a hollow pumpkin knock), 0.2-0.6 s.
- `mob_snow_golem_death` (friendly) [-28 LUFS]: Snow Golem death. Snow Golem dies: a longer falling cry of its voice (a soft snowy crunch and a hollow pumpkin knock), then silence; 0.5-2 s.
- `mob_evoker_ambient` (hostile) [-25 LUFS]: Conjurer idle call. Conjurer idle call, every few seconds nearby: a scheming low murmur.
- `mob_evoker_hurt` (hostile) [-25 LUFS]: Conjurer hurt. Conjurer is hit: a short sharp pained version of its voice (a scheming low murmur), 0.2-0.6 s.
- `mob_evoker_death` (hostile) [-21 LUFS]: Conjurer death. Conjurer dies: a longer falling cry of its voice (a scheming low murmur), then silence; 0.5-2 s.
- `mob_vex_ambient` (hostile) [-23 LUFS]: Hexling idle call. Hexling idle call, every few seconds nearby: a tiny high spectral chitter.
- `mob_vex_hurt` (hostile) [-26 LUFS]: Hexling hurt. Hexling is hit: a short sharp pained version of its voice (a tiny high spectral chitter), 0.2-0.6 s.
- `mob_vex_death` (hostile) [-22 LUFS]: Hexling death. Hexling dies: a longer falling cry of its voice (a tiny high spectral chitter), then silence; 0.5-2 s.
- `mob_ravager_ambient` (hostile) [-23 LUFS]: Siegebeast idle call. Siegebeast idle call, every few seconds nearby: a huge beast's growl and snort.
- `mob_ravager_hurt` (hostile) [-20 LUFS]: Siegebeast hurt. Siegebeast is hit: a short sharp pained version of its voice (a huge beast's growl and snort), 0.2-0.6 s.
- `mob_ravager_death` (hostile) [-22 LUFS]: Siegebeast death. Siegebeast dies: a longer falling cry of its voice (a huge beast's growl and snort), then silence; 0.5-2 s.
- `mob_zombie_villager_ambient` (hostile) [-25 LUFS]: Zombie Townsperson idle call. Zombie Townsperson idle call, every few seconds nearby: a groan with a murmuring villager tone.
- `mob_zombie_villager_hurt` (hostile) [-22 LUFS]: Zombie Townsperson hurt. Zombie Townsperson is hit: a short sharp pained version of its voice (a groan with a murmuring villager tone), 0.2-0.6 s.
- `mob_zombie_villager_death` (hostile) [-25 LUFS]: Zombie Townsperson death. Zombie Townsperson dies: a longer falling cry of its voice (a groan with a murmuring villager tone), then silence; 0.5-2 s.
- `mob_rabbit_ambient` (friendly) [-18 LUFS]: Rabbit idle call. Rabbit idle call, every few seconds nearby: tiny sniffs and squeaks.
- `mob_rabbit_hurt` (friendly) [-13 LUFS]: Rabbit hurt. Rabbit is hit: a short sharp pained version of its voice (tiny sniffs and squeaks), 0.2-0.6 s.
- `mob_rabbit_death` (friendly) [-16 LUFS]: Rabbit death. Rabbit dies: a longer falling cry of its voice (tiny sniffs and squeaks), then silence; 0.5-2 s.
- `mob_fox_ambient` (friendly) [-17 LUFS]: Fox idle call. Fox idle call, every few seconds nearby: a fox's yips and screech.
- `mob_fox_hurt` (friendly) [-15 LUFS]: Fox hurt. Fox is hit: a short sharp pained version of its voice (a fox's yips and screech), 0.2-0.6 s.
- `mob_fox_death` (friendly) [-18 LUFS]: Fox death. Fox dies: a longer falling cry of its voice (a fox's yips and screech), then silence; 0.5-2 s.
- `mob_wolf_ambient` (friendly) [-20 LUFS]: Wolf idle call. Wolf idle call, every few seconds nearby: a dog-like pant and bark.
- `mob_wolf_hurt` (friendly) [-21 LUFS]: Wolf hurt. Wolf is hit: a short sharp pained version of its voice (a dog-like pant and bark), 0.2-0.6 s.
- `mob_wolf_death` (friendly) [-20 LUFS]: Wolf death. Wolf dies: a longer falling cry of its voice (a dog-like pant and bark), then silence; 0.5-2 s.
- `mob_cat_ambient` (friendly) [-18 LUFS]: Cat idle call. Cat idle call, every few seconds nearby: a domestic cat's meow.
- `mob_cat_hurt` (friendly) [-21 LUFS]: Cat hurt. Cat is hit: a short sharp pained version of its voice (a domestic cat's meow), 0.2-0.6 s.
- `mob_cat_death` (friendly) [-28 LUFS]: Cat death. Cat dies: a longer falling cry of its voice (a domestic cat's meow), then silence; 0.5-2 s.
- `mob_ocelot_ambient` (friendly) [-17 LUFS]: Ocelot idle call. Ocelot idle call, every few seconds nearby: a wild cat's short meow.
- `mob_ocelot_hurt` (friendly) [-21 LUFS]: Ocelot hurt. Ocelot is hit: a short sharp pained version of its voice (a wild cat's short meow), 0.2-0.6 s.
- `mob_ocelot_death` (friendly) [-28 LUFS]: Ocelot death. Ocelot dies: a longer falling cry of its voice (a wild cat's short meow), then silence; 0.5-2 s.
- `mob_llama_ambient` (friendly) [-23 LUFS]: Llama idle call. Llama idle call, every few seconds nearby: a llama's soft hum and snort.
- `mob_llama_hurt` (friendly) [-22 LUFS]: Llama hurt. Llama is hit: a short sharp pained version of its voice (a llama's soft hum and snort), 0.2-0.6 s.
- `mob_llama_death` (friendly) [-22 LUFS]: Llama death. Llama dies: a longer falling cry of its voice (a llama's soft hum and snort), then silence; 0.5-2 s.
- `mob_trader_llama_ambient` (friendly) [-23 LUFS]: Trader Llama idle call. Trader Llama idle call, every few seconds nearby: a llama's soft hum and snort.
- `mob_trader_llama_hurt` (friendly) [-22 LUFS]: Trader Llama hurt. Trader Llama is hit: a short sharp pained version of its voice (a llama's soft hum and snort), 0.2-0.6 s.
- `mob_trader_llama_death` (friendly) [-22 LUFS]: Trader Llama death. Trader Llama dies: a longer falling cry of its voice (a llama's soft hum and snort), then silence; 0.5-2 s.
- `mob_camel_ambient` (friendly) [-24 LUFS]: Camel idle call. Camel idle call, every few seconds nearby: a camel's grumbling groan.
- `mob_camel_hurt` (friendly) [-23 LUFS]: Camel hurt. Camel is hit: a short sharp pained version of its voice (a camel's grumbling groan), 0.2-0.6 s.
- `mob_camel_death` (friendly) [-24 LUFS]: Camel death. Camel dies: a longer falling cry of its voice (a camel's grumbling groan), then silence; 0.5-2 s.
- `mob_goat_ambient` (friendly) [-21 LUFS]: Goat idle call. Goat idle call, every few seconds nearby: a goat's bleat (higher, harsher than sheep).
- `mob_goat_hurt` (friendly) [-19 LUFS]: Goat hurt. Goat is hit: a short sharp pained version of its voice (a goat's bleat (higher, harsher than sheep)), 0.2-0.6 s.
- `mob_goat_death` (friendly) [-22 LUFS]: Goat death. Goat dies: a longer falling cry of its voice (a goat's bleat (higher, harsher than sheep)), then silence; 0.5-2 s.
- `mob_panda_ambient` (friendly) [-29 LUFS]: Panda idle call. Panda idle call, every few seconds nearby: a panda's bleaty grunt.
- `mob_panda_hurt` (friendly) [-24 LUFS]: Panda hurt. Panda is hit: a short sharp pained version of its voice (a panda's bleaty grunt), 0.2-0.6 s.
- `mob_panda_death` (friendly) [-25 LUFS]: Panda death. Panda dies: a longer falling cry of its voice (a panda's bleaty grunt), then silence; 0.5-2 s.
- `mob_polar_bear_ambient` (friendly) [-21 LUFS]: Polar Bear idle call. Polar Bear idle call, every few seconds nearby: a bear's grunt and growl.
- `mob_polar_bear_hurt` (friendly) [-20 LUFS]: Polar Bear hurt. Polar Bear is hit: a short sharp pained version of its voice (a bear's grunt and growl), 0.2-0.6 s.
- `mob_polar_bear_death` (friendly) [-21 LUFS]: Polar Bear death. Polar Bear dies: a longer falling cry of its voice (a bear's grunt and growl), then silence; 0.5-2 s.
- `mob_turtle_ambient` (friendly) [-21 LUFS]: Turtle idle call. Turtle idle call, every few seconds nearby: a quiet shuffle and soft creak.
- `mob_turtle_hurt` (friendly) [-21 LUFS]: Turtle hurt. Turtle is hit: a short sharp pained version of its voice (a quiet shuffle and soft creak), 0.2-0.6 s.
- `mob_turtle_death` (friendly) [-24 LUFS]: Turtle death. Turtle dies: a longer falling cry of its voice (a quiet shuffle and soft creak), then silence; 0.5-2 s.
- `mob_frog_ambient` (friendly) [-20 LUFS]: Frog idle call. Frog idle call, every few seconds nearby: a frog's croak.
- `mob_frog_hurt` (friendly) [-18 LUFS]: Frog hurt. Frog is hit: a short sharp pained version of its voice (a frog's croak), 0.2-0.6 s.
- `mob_frog_death` (friendly) [-22 LUFS]: Frog death. Frog dies: a longer falling cry of its voice (a frog's croak), then silence; 0.5-2 s.
- `mob_tadpole_ambient` (friendly) [-28 LUFS]: Tadpole idle call. Tadpole idle call, every few seconds nearby: tiny bubbly wiggle.
- `mob_tadpole_hurt` (friendly) [-23 LUFS]: Tadpole hurt. Tadpole is hit: a short sharp pained version of its voice (tiny bubbly wiggle), 0.2-0.6 s.
- `mob_tadpole_death` (friendly) [-20 LUFS]: Tadpole death. Tadpole dies: a longer falling cry of its voice (tiny bubbly wiggle), then silence; 0.5-2 s.
- `mob_armadillo_ambient` (friendly) [-25 LUFS]: Armadillo idle call. Armadillo idle call, every few seconds nearby: a small sniffing grunt.
- `mob_armadillo_hurt` (friendly) [-21 LUFS]: Armadillo hurt. Armadillo is hit: a short sharp pained version of its voice (a small sniffing grunt), 0.2-0.6 s.
- `mob_armadillo_death` (friendly) [-22 LUFS]: Armadillo death. Armadillo dies: a longer falling cry of its voice (a small sniffing grunt), then silence; 0.5-2 s.
- `mob_sniffer_ambient` (friendly) [-25 LUFS]: Snuffler idle call. Snuffler idle call, every few seconds nearby: a big ancient beast's deep sniff and snort.
- `mob_sniffer_hurt` (friendly) [-24 LUFS]: Snuffler hurt. Snuffler is hit: a short sharp pained version of its voice (a big ancient beast's deep sniff and snort), 0.2-0.6 s.
- `mob_sniffer_death` (friendly) [-24 LUFS]: Snuffler death. Snuffler dies: a longer falling cry of its voice (a big ancient beast's deep sniff and snort), then silence; 0.5-2 s.
- `mob_mooshroom_ambient` (friendly) [-23 LUFS]: Mushroom Cow idle call. Mushroom Cow idle call, every few seconds nearby: a moo like the cow, slightly earthier.
- `mob_mooshroom_hurt` (friendly) [-21 LUFS]: Mushroom Cow hurt. Mushroom Cow is hit: a short sharp pained version of its voice (a moo like the cow, slightly earthier), 0.2-0.6 s.
- `mob_mooshroom_death` (friendly) [-24 LUFS]: Mushroom Cow death. Mushroom Cow dies: a longer falling cry of its voice (a moo like the cow, slightly earthier), then silence; 0.5-2 s.
- `mob_bee_ambient` (friendly) [-20 LUFS]: Bee idle call. Bee idle call, every few seconds nearby: a bee's buzz.
- `mob_bee_hurt` (friendly) [-19 LUFS]: Bee hurt. Bee is hit: a short sharp pained version of its voice (a bee's buzz), 0.2-0.6 s.
- `mob_bee_death` (friendly) [-20 LUFS]: Bee death. Bee dies: a longer falling cry of its voice (a bee's buzz), then silence; 0.5-2 s.
- `mob_parrot_ambient` (friendly) [-15 LUFS]: Parrot idle call. Parrot idle call, every few seconds nearby: a parrot squawk and chirp.
- `mob_parrot_hurt` (friendly) [-13 LUFS]: Parrot hurt. Parrot is hit: a short sharp pained version of its voice (a parrot squawk and chirp), 0.2-0.6 s.
- `mob_parrot_death` (friendly) [-15 LUFS]: Parrot death. Parrot dies: a longer falling cry of its voice (a parrot squawk and chirp), then silence; 0.5-2 s.
- `mob_bat_ambient` (friendly) [-18 LUFS]: Bat idle call. Bat idle call, every few seconds nearby: high bat squeaks and wing flutter.
- `mob_bat_hurt` (friendly) [-12 LUFS]: Bat hurt. Bat is hit: a short sharp pained version of its voice (high bat squeaks and wing flutter), 0.2-0.6 s.
- `mob_bat_death` (friendly) [-14 LUFS]: Bat death. Bat dies: a longer falling cry of its voice (high bat squeaks and wing flutter), then silence; 0.5-2 s.
- `mob_allay_ambient` (friendly) [-16 LUFS]: Fetchling idle call. Fetchling idle call, every few seconds nearby: a little spirit's sweet humming trill.
- `mob_allay_hurt` (friendly) [-15 LUFS]: Fetchling hurt. Fetchling is hit: a short sharp pained version of its voice (a little spirit's sweet humming trill), 0.2-0.6 s.
- `mob_allay_death` (friendly) [-15 LUFS]: Fetchling death. Fetchling dies: a longer falling cry of its voice (a little spirit's sweet humming trill), then silence; 0.5-2 s.
- `mob_axolotl_ambient` (friendly) [-24 LUFS]: Axolotl idle call. Axolotl idle call, every few seconds nearby: a soft squeaky chirp under water.
- `mob_axolotl_hurt` (friendly) [-19 LUFS]: Axolotl hurt. Axolotl is hit: a short sharp pained version of its voice (a soft squeaky chirp under water), 0.2-0.6 s.
- `mob_axolotl_death` (friendly) [-21 LUFS]: Axolotl death. Axolotl dies: a longer falling cry of its voice (a soft squeaky chirp under water), then silence; 0.5-2 s.
- `mob_squid_ambient` (friendly) [-20 LUFS]: Squid idle call. Squid idle call, every few seconds nearby: soft watery squelch and bubbles.
- `mob_squid_hurt` (friendly) [-20 LUFS]: Squid hurt. Squid is hit: a short sharp pained version of its voice (soft watery squelch and bubbles), 0.2-0.6 s.
- `mob_squid_death` (friendly) [-19 LUFS]: Squid death. Squid dies: a longer falling cry of its voice (soft watery squelch and bubbles), then silence; 0.5-2 s.
- `mob_glow_squid_ambient` (friendly) [-24 LUFS]: Glow Squid idle call. Glow Squid idle call, every few seconds nearby: soft watery squelch, a bit brighter.
- `mob_glow_squid_hurt` (friendly) [-19 LUFS]: Glow Squid hurt. Glow Squid is hit: a short sharp pained version of its voice (soft watery squelch, a bit brighter), 0.2-0.6 s.
- `mob_glow_squid_death` (friendly) [-20 LUFS]: Glow Squid death. Glow Squid dies: a longer falling cry of its voice (soft watery squelch, a bit brighter), then silence; 0.5-2 s.
- `mob_dolphin_ambient` (friendly) [-15 LUFS]: Dolphin idle call. Dolphin idle call, every few seconds nearby: dolphin clicks and whistles.
- `mob_dolphin_hurt` (friendly) [-12 LUFS]: Dolphin hurt. Dolphin is hit: a short sharp pained version of its voice (dolphin clicks and whistles), 0.2-0.6 s.
- `mob_dolphin_death` (friendly) [-13 LUFS]: Dolphin death. Dolphin dies: a longer falling cry of its voice (dolphin clicks and whistles), then silence; 0.5-2 s.
- `mob_cod_ambient` (friendly) [-20 LUFS]: Cod idle call. Cod idle call, every few seconds nearby: a fish flop and bubbles.
- `mob_cod_hurt` (friendly) [-18 LUFS]: Cod hurt. Cod is hit: a short sharp pained version of its voice (a fish flop and bubbles), 0.2-0.6 s.
- `mob_cod_death` (friendly) [-19 LUFS]: Cod death. Cod dies: a longer falling cry of its voice (a fish flop and bubbles), then silence; 0.5-2 s.
- `mob_salmon_ambient` (friendly) [-22 LUFS]: Salmon idle call. Salmon idle call, every few seconds nearby: a fish flop and bubbles.
- `mob_salmon_hurt` (friendly) [-17 LUFS]: Salmon hurt. Salmon is hit: a short sharp pained version of its voice (a fish flop and bubbles), 0.2-0.6 s.
- `mob_salmon_death` (friendly) [-20 LUFS]: Salmon death. Salmon dies: a longer falling cry of its voice (a fish flop and bubbles), then silence; 0.5-2 s.
- `mob_tropical_fish_ambient` (friendly) [-23 LUFS]: Tropical Fish idle call. Tropical Fish idle call, every few seconds nearby: a small flop and bubbles.
- `mob_tropical_fish_hurt` (friendly) [-18 LUFS]: Tropical Fish hurt. Tropical Fish is hit: a short sharp pained version of its voice (a small flop and bubbles), 0.2-0.6 s.
- `mob_tropical_fish_death` (friendly) [-21 LUFS]: Tropical Fish death. Tropical Fish dies: a longer falling cry of its voice (a small flop and bubbles), then silence; 0.5-2 s.
- `mob_pufferfish_ambient` (friendly) [-22 LUFS]: Pufferfish idle call. Pufferfish idle call, every few seconds nearby: a puff-up inflate and bubbles.
- `mob_pufferfish_hurt` (friendly) [-21 LUFS]: Pufferfish hurt. Pufferfish is hit: a short sharp pained version of its voice (a puff-up inflate and bubbles), 0.2-0.6 s.
- `mob_pufferfish_death` (friendly) [-23 LUFS]: Pufferfish death. Pufferfish dies: a longer falling cry of its voice (a puff-up inflate and bubbles), then silence; 0.5-2 s.
- `mob_wandering_trader_ambient` (friendly) [-18 LUFS]: Wandering Trader idle call. Wandering Trader idle call, every few seconds nearby: a traveller's wordless murmur.
- `mob_wandering_trader_hurt` (friendly) [-21 LUFS]: Wandering Trader hurt. Wandering Trader is hit: a short sharp pained version of its voice (a traveller's wordless murmur), 0.2-0.6 s.
- `mob_wandering_trader_death` (friendly) [-24 LUFS]: Wandering Trader death. Wandering Trader dies: a longer falling cry of its voice (a traveller's wordless murmur), then silence; 0.5-2 s.
- `mob_phantom_ambient` (hostile) [-23 LUFS]: Nightwing idle call. Nightwing idle call, every few seconds nearby: a screeching swooping cry.
- `mob_phantom_hurt` (hostile) [-24 LUFS]: Nightwing hurt. Nightwing is hit: a short sharp pained version of its voice (a screeching swooping cry), 0.2-0.6 s.
- `mob_phantom_death` (hostile) [-22 LUFS]: Nightwing death. Nightwing dies: a longer falling cry of its voice (a screeching swooping cry), then silence; 0.5-2 s.
- `mob_guardian_ambient` (hostile) [-23 LUFS]: Spikefish idle call. Spikefish idle call, every few seconds nearby: a watery grunt and laser-eye hum.
- `mob_guardian_hurt` (hostile) [-17 LUFS]: Spikefish hurt. Spikefish is hit: a short sharp pained version of its voice (a watery grunt and laser-eye hum), 0.2-0.6 s.
- `mob_guardian_death` (hostile) [-20 LUFS]: Spikefish death. Spikefish dies: a longer falling cry of its voice (a watery grunt and laser-eye hum), then silence; 0.5-2 s.
- `mob_elder_guardian_ambient` (hostile) [-21 LUFS]: Elder Spikefish idle call. Elder Spikefish idle call, every few seconds nearby: a deeper, bigger watery groan.
- `mob_elder_guardian_hurt` (hostile) [-18 LUFS]: Elder Spikefish hurt. Elder Spikefish is hit: a short sharp pained version of its voice (a deeper, bigger watery groan), 0.2-0.6 s.
- `mob_elder_guardian_death` (hostile) [-22 LUFS]: Elder Spikefish death. Elder Spikefish dies: a longer falling cry of its voice (a deeper, bigger watery groan), then silence; 0.5-2 s.
- `mob_endermite_ambient` (hostile) [-22 LUFS]: Voidmite idle call. Voidmite idle call, every few seconds nearby: tiny clicky insect scratches.
- `mob_endermite_hurt` (hostile) [-23 LUFS]: Voidmite hurt. Voidmite is hit: a short sharp pained version of its voice (tiny clicky insect scratches), 0.2-0.6 s.
- `mob_endermite_death` (hostile) [-22 LUFS]: Voidmite death. Voidmite dies: a longer falling cry of its voice (tiny clicky insect scratches), then silence; 0.5-2 s.
- `mob_warden_ambient` (hostile) [-24 LUFS]: Deep Stalker idle call. Deep Stalker idle call, every few seconds nearby: a monstrous deep growl and chest rumble.
- `mob_warden_hurt` (hostile) [-22 LUFS]: Deep Stalker hurt. Deep Stalker is hit: a short sharp pained version of its voice (a monstrous deep growl and chest rumble), 0.2-0.6 s.
- `mob_warden_death` (hostile) [-23 LUFS]: Deep Stalker death. Deep Stalker dies: a longer falling cry of its voice (a monstrous deep growl and chest rumble), then silence; 0.5-2 s.
- `mob_breeze_ambient` (hostile) [-24 LUFS]: Gustling idle call. Gustling idle call, every few seconds nearby: a whirling wind creature's whoosh.
- `mob_breeze_hurt` (hostile) [-21 LUFS]: Gustling hurt. Gustling is hit: a short sharp pained version of its voice (a whirling wind creature's whoosh), 0.2-0.6 s.
- `mob_breeze_death` (hostile) [-20 LUFS]: Gustling death. Gustling dies: a longer falling cry of its voice (a whirling wind creature's whoosh), then silence; 0.5-2 s.
- `mob_bogged_ambient` (hostile) [-28 LUFS]: Mire Skeleton idle call. Mire Skeleton idle call, every few seconds nearby: damp, mossy bone rattles.
- `mob_bogged_hurt` (hostile) [-22 LUFS]: Mire Skeleton hurt. Mire Skeleton is hit: a short sharp pained version of its voice (damp, mossy bone rattles), 0.2-0.6 s.
- `mob_bogged_death` (hostile) [-28 LUFS]: Mire Skeleton death. Mire Skeleton dies: a longer falling cry of its voice (damp, mossy bone rattles), then silence; 0.5-2 s.
- `mob_zoglin_ambient` (hostile) [-23 LUFS]: Rot Tusker idle call. Rot Tusker idle call, every few seconds nearby: a rotten boar's snarl.
- `mob_zoglin_hurt` (hostile) [-20 LUFS]: Rot Tusker hurt. Rot Tusker is hit: a short sharp pained version of its voice (a rotten boar's snarl), 0.2-0.6 s.
- `mob_zoglin_death` (hostile) [-22 LUFS]: Rot Tusker death. Rot Tusker dies: a longer falling cry of its voice (a rotten boar's snarl), then silence; 0.5-2 s.
- `mob_creaking_ambient` (hostile) [-22 LUFS]: Barkwraith idle call. Barkwraith idle call, every few seconds nearby: a living tree's creaking wood groan.
- `mob_creaking_hurt` (hostile) [-21 LUFS]: Barkwraith hurt. Barkwraith is hit: a short sharp pained version of its voice (a living tree's creaking wood groan), 0.2-0.6 s.
- `mob_creaking_death` (hostile) [-22 LUFS]: Barkwraith death. Barkwraith dies: a longer falling cry of its voice (a living tree's creaking wood groan), then silence; 0.5-2 s.
- `mob_illusioner_ambient` (hostile) [-24 LUFS]: Mirage Caster idle call. Mirage Caster idle call, every few seconds nearby: a sly magical murmur.
- `mob_illusioner_hurt` (hostile) [-19 LUFS]: Mirage Caster hurt. Mirage Caster is hit: a short sharp pained version of its voice (a sly magical murmur), 0.2-0.6 s.
- `mob_illusioner_death` (hostile) [-20 LUFS]: Mirage Caster death. Mirage Caster dies: a longer falling cry of its voice (a sly magical murmur), then silence; 0.5-2 s.
- `mob_happy_ghast_ambient` (friendly) [-22 LUFS]: Cloudwailer idle call. Cloudwailer idle call, every few seconds nearby: a gentle, cooing big-creature trill.
- `mob_happy_ghast_hurt` (friendly) [-19 LUFS]: Cloudwailer hurt. Cloudwailer is hit: a short sharp pained version of its voice (a gentle, cooing big-creature trill), 0.2-0.6 s.
- `mob_happy_ghast_death` (friendly) [-18 LUFS]: Cloudwailer death. Cloudwailer dies: a longer falling cry of its voice (a gentle, cooing big-creature trill), then silence; 0.5-2 s.
- `mob_parched_ambient` (hostile) [-28 LUFS]: Sunscorched Skeleton idle call. Sunscorched Skeleton idle call, every few seconds nearby: dry sun-baked bone rattles.
- `mob_parched_hurt` (hostile) [-22 LUFS]: Sunscorched Skeleton hurt. Sunscorched Skeleton is hit: a short sharp pained version of its voice (dry sun-baked bone rattles), 0.2-0.6 s.
- `mob_parched_death` (hostile) [-28 LUFS]: Sunscorched Skeleton death. Sunscorched Skeleton dies: a longer falling cry of its voice (dry sun-baked bone rattles), then silence; 0.5-2 s.
- `mob_camel_husk_ambient` (friendly) [-24 LUFS]: Dust Camel idle call. Dust Camel idle call, every few seconds nearby: a dry undead camel groan.
- `mob_camel_husk_hurt` (friendly) [-24 LUFS]: Dust Camel hurt. Dust Camel is hit: a short sharp pained version of its voice (a dry undead camel groan), 0.2-0.6 s.
- `mob_camel_husk_death` (friendly) [-24 LUFS]: Dust Camel death. Dust Camel dies: a longer falling cry of its voice (a dry undead camel groan), then silence; 0.5-2 s.
- `mob_nautilus_ambient` (friendly) [-22 LUFS]: Nautilus idle call. Nautilus idle call, every few seconds nearby: a soft shell knock and bubbles.
- `mob_nautilus_hurt` (friendly) [-18 LUFS]: Nautilus hurt. Nautilus is hit: a short sharp pained version of its voice (a soft shell knock and bubbles), 0.2-0.6 s.
- `mob_nautilus_death` (friendly) [-20 LUFS]: Nautilus death. Nautilus dies: a longer falling cry of its voice (a soft shell knock and bubbles), then silence; 0.5-2 s.
- `mob_zombie_nautilus_ambient` (hostile) [-20 LUFS]: Sunken Nautilus idle call. Sunken Nautilus idle call, every few seconds nearby: a rotten bubbling knock.
- `mob_zombie_nautilus_hurt` (hostile) [-18 LUFS]: Sunken Nautilus hurt. Sunken Nautilus is hit: a short sharp pained version of its voice (a rotten bubbling knock), 0.2-0.6 s.
- `mob_zombie_nautilus_death` (hostile) [-20 LUFS]: Sunken Nautilus death. Sunken Nautilus dies: a longer falling cry of its voice (a rotten bubbling knock), then silence; 0.5-2 s.
- `mob_soldier_recruit_ambient` (hostile) [-28 LUFS]: Steelhold Recruit idle call. Steelhold Recruit idle call, every few seconds nearby: a young soldier's grunt (speech barks are the soldier_* files).
- `mob_soldier_recruit_hurt` (hostile) [-25 LUFS]: Steelhold Recruit hurt. Steelhold Recruit is hit: a short sharp pained version of its voice (a young soldier's grunt (speech barks are the soldier_* files)), 0.2-0.6 s.
- `mob_soldier_recruit_death` (hostile) [-24 LUFS]: Steelhold Recruit death. Steelhold Recruit dies: a longer falling cry of its voice (a young soldier's grunt (speech barks are the soldier_* files)), then silence; 0.5-2 s.
- `mob_soldier_trooper_ambient` (hostile) [-27 LUFS]: Steelhold Trooper idle call. Steelhold Trooper idle call, every few seconds nearby: a soldier's grunt.
- `mob_soldier_trooper_hurt` (hostile) [-26 LUFS]: Steelhold Trooper hurt. Steelhold Trooper is hit: a short sharp pained version of its voice (a soldier's grunt), 0.2-0.6 s.
- `mob_soldier_trooper_death` (hostile) [-26 LUFS]: Steelhold Trooper death. Steelhold Trooper dies: a longer falling cry of its voice (a soldier's grunt), then silence; 0.5-2 s.
- `mob_soldier_marksman_ambient` (hostile) [-29 LUFS]: Steelhold Marksman idle call. Steelhold Marksman idle call, every few seconds nearby: a soldier's grunt.
- `mob_soldier_marksman_hurt` (hostile) [-22 LUFS]: Steelhold Marksman hurt. Steelhold Marksman is hit: a short sharp pained version of its voice (a soldier's grunt), 0.2-0.6 s.
- `mob_soldier_marksman_death` (hostile) [-27 LUFS]: Steelhold Marksman death. Steelhold Marksman dies: a longer falling cry of its voice (a soldier's grunt), then silence; 0.5-2 s.
- `mob_soldier_ironclad_ambient` (hostile) [-27 LUFS]: Steelhold Ironclad idle call. Steelhold Ironclad idle call, every few seconds nearby: a big armoured soldier's deep grunt through a helmet.
- `mob_soldier_ironclad_hurt` (hostile) [-21 LUFS]: Steelhold Ironclad hurt. Steelhold Ironclad is hit: a short sharp pained version of its voice (a big armoured soldier's deep grunt through a helmet), 0.2-0.6 s.
- `mob_soldier_ironclad_death` (hostile) [-25 LUFS]: Steelhold Ironclad death. Steelhold Ironclad dies: a longer falling cry of its voice (a big armoured soldier's deep grunt through a helmet), then silence; 0.5-2 s.
- `mob_deck_gun_ambient` (hostile): Deck Gun idle call. Deck Gun idle call, every few seconds nearby: a mounted gun's mechanical clank/servo (no voice).
- `mob_deck_gun_hurt` (hostile): Deck Gun hurt. Deck Gun is hit: a short sharp pained version of its voice (a mounted gun's mechanical clank/servo (no voice)), 0.2-0.6 s.
- `mob_deck_gun_death` (hostile): Deck Gun death. Deck Gun dies: a longer falling cry of its voice (a mounted gun's mechanical clank/servo (no voice)), then silence; 0.5-2 s.
- `mob_copper_golem_ambient` (friendly) [-28 LUFS]: Copper Golem idle call. Copper Golem idle call, every few seconds nearby: small copper clicks and a tinny chirp.
- `mob_copper_golem_hurt` (friendly) [-27 LUFS]: Copper Golem hurt. Copper Golem is hit: a short sharp pained version of its voice (small copper clicks and a tinny chirp), 0.2-0.6 s.
- `mob_copper_golem_death` (friendly) [-27 LUFS]: Copper Golem death. Copper Golem dies: a longer falling cry of its voice (small copper clicks and a tinny chirp), then silence; 0.5-2 s.
- `mob_soldier_officer_ambient` (hostile) [-30 LUFS]: Capital Officer idle call. Capital Officer idle call, every few seconds nearby: an officer's grunt.
- `mob_soldier_officer_hurt` (hostile) [-26 LUFS]: Capital Officer hurt. Capital Officer is hit: a short sharp pained version of its voice (an officer's grunt), 0.2-0.6 s.
- `mob_soldier_officer_death` (hostile) [-26 LUFS]: Capital Officer death. Capital Officer dies: a longer falling cry of its voice (an officer's grunt), then silence; 0.5-2 s.
- `mob_soldier_crew_ambient` (hostile) [-27 LUFS]: Vehicle Crew idle call. Vehicle Crew idle call, every few seconds nearby: a crewman's grunt.
- `mob_soldier_crew_hurt` (hostile) [-25 LUFS]: Vehicle Crew hurt. Vehicle Crew is hit: a short sharp pained version of its voice (a crewman's grunt), 0.2-0.6 s.
- `mob_soldier_crew_death` (hostile) [-24 LUFS]: Vehicle Crew death. Vehicle Crew dies: a longer falling cry of its voice (a crewman's grunt), then silence; 0.5-2 s.
- `mob_ash_tank_ambient` (hostile): Ashguard Tank idle call. Ashguard Tank idle call, every few seconds nearby: a tank's diesel engine and track squeal.
- `mob_ash_tank_hurt` (hostile): Ashguard Tank hurt. Ashguard Tank is hit: a short sharp pained version of its voice (a tank's diesel engine and track squeal), 0.2-0.6 s.
- `mob_ash_tank_death` (hostile): Ashguard Tank death. Ashguard Tank dies: a longer falling cry of its voice (a tank's diesel engine and track squeal), then silence; 0.5-2 s.
- `mob_ash_halftrack_ambient` (hostile): Ashguard Halftrack idle call. Ashguard Halftrack idle call, every few seconds nearby: a halftrack's engine and track clank.
- `mob_ash_halftrack_hurt` (hostile): Ashguard Halftrack hurt. Ashguard Halftrack is hit: a short sharp pained version of its voice (a halftrack's engine and track clank), 0.2-0.6 s.
- `mob_ash_halftrack_death` (hostile): Ashguard Halftrack death. Ashguard Halftrack dies: a longer falling cry of its voice (a halftrack's engine and track clank), then silence; 0.5-2 s.
- `mob_ash_artillery_ambient` (hostile): Ashguard Artillery idle call. Ashguard Artillery idle call, every few seconds nearby: an artillery piece's mechanical clank.
- `mob_ash_artillery_hurt` (hostile): Ashguard Artillery hurt. Ashguard Artillery is hit: a short sharp pained version of its voice (an artillery piece's mechanical clank), 0.2-0.6 s.
- `mob_ash_artillery_death` (hostile): Ashguard Artillery death. Ashguard Artillery dies: a longer falling cry of its voice (an artillery piece's mechanical clank), then silence; 0.5-2 s.
- `mob_ash_truck_ambient` (hostile): Ashguard Truck idle call. Ashguard Truck idle call, every few seconds nearby: a truck engine.
- `mob_ash_truck_hurt` (hostile): Ashguard Truck hurt. Ashguard Truck is hit: a short sharp pained version of its voice (a truck engine), 0.2-0.6 s.
- `mob_ash_truck_death` (hostile): Ashguard Truck death. Ashguard Truck dies: a longer falling cry of its voice (a truck engine), then silence; 0.5-2 s.
- `mob_ash_marshal_ambient` (hostile) [-27 LUFS]: Ash Marshal idle call. Ash Marshal idle call, every few seconds nearby: a hard commander's grunt.
- `mob_ash_marshal_hurt` (hostile) [-22 LUFS]: Ash Marshal hurt. Ash Marshal is hit: a short sharp pained version of its voice (a hard commander's grunt), 0.2-0.6 s.
- `mob_ash_marshal_death` (hostile) [-24 LUFS]: Ash Marshal death. Ash Marshal dies: a longer falling cry of its voice (a hard commander's grunt), then silence; 0.5-2 s.
- `mob_ash_behemoth_ambient` (hostile): Ash Behemoth (super-heavy tank) idle call. Ash Behemoth (super-heavy tank) idle call, every few seconds nearby: a massive tank engine and grinding tracks.
- `mob_ash_behemoth_hurt` (hostile): Ash Behemoth (super-heavy tank) hurt. Ash Behemoth (super-heavy tank) is hit: a short sharp pained version of its voice (a massive tank engine and grinding tracks), 0.2-0.6 s.
- `mob_ash_behemoth_death` (hostile): Ash Behemoth (super-heavy tank) death. Ash Behemoth (super-heavy tank) dies: a longer falling cry of its voice (a massive tank engine and grinding tracks), then silence; 0.5-2 s.
- `mob_ash_chancellor_ambient` (hostile): Ash Chancellor idle call. Ash Chancellor idle call, every few seconds nearby: a cold commanding voice grunt.
- `mob_ash_chancellor_hurt` (hostile): Ash Chancellor hurt. Ash Chancellor is hit: a short sharp pained version of its voice (a cold commanding voice grunt), 0.2-0.6 s.
- `mob_ash_chancellor_death` (hostile): Ash Chancellor death. Ash Chancellor dies: a longer falling cry of its voice (a cold commanding voice grunt), then silence; 0.5-2 s.
- `mob_brand_squire_ambient` (hostile) [-21 LUFS]: Brand Squire (hell knight) idle call. Brand Squire (hell knight) idle call, every few seconds nearby: a knight's grunt through a visor.
- `mob_brand_squire_hurt` (hostile) [-19 LUFS]: Brand Squire (hell knight) hurt. Brand Squire (hell knight) is hit: a short sharp pained version of its voice (a knight's grunt through a visor), 0.2-0.6 s.
- `mob_brand_squire_death` (hostile) [-22 LUFS]: Brand Squire (hell knight) death. Brand Squire (hell knight) dies: a longer falling cry of its voice (a knight's grunt through a visor), then silence; 0.5-2 s.
- `mob_brand_knight_ambient` (hostile) [-24 LUFS]: Brand Knight idle call. Brand Knight idle call, every few seconds nearby: a heavy knight's grunt through a visor.
- `mob_brand_knight_hurt` (hostile) [-19 LUFS]: Brand Knight hurt. Brand Knight is hit: a short sharp pained version of its voice (a heavy knight's grunt through a visor), 0.2-0.6 s.
- `mob_brand_knight_death` (hostile) [-23 LUFS]: Brand Knight death. Brand Knight dies: a longer falling cry of its voice (a heavy knight's grunt through a visor), then silence; 0.5-2 s.
- `mob_brand_champion_ambient` (hostile) [-21 LUFS]: Brand Champion idle call. Brand Champion idle call, every few seconds nearby: a brutal armoured growl.
- `mob_brand_champion_hurt` (hostile) [-20 LUFS]: Brand Champion hurt. Brand Champion is hit: a short sharp pained version of its voice (a brutal armoured growl), 0.2-0.6 s.
- `mob_brand_champion_death` (hostile) [-21 LUFS]: Brand Champion death. Brand Champion dies: a longer falling cry of its voice (a brutal armoured growl), then silence; 0.5-2 s.
- `mob_brand_commander_ambient` (hostile) [-22 LUFS]: Brand Commander idle call. Brand Commander idle call, every few seconds nearby: a demonic commanding roar.
- `mob_brand_commander_hurt` (hostile) [-19 LUFS]: Brand Commander hurt. Brand Commander is hit: a short sharp pained version of its voice (a demonic commanding roar), 0.2-0.6 s.
- `mob_brand_commander_death` (hostile) [-21 LUFS]: Brand Commander death. Brand Commander dies: a longer falling cry of its voice (a demonic commanding roar), then silence; 0.5-2 s.
- `mob_searwing_ambient` (hostile) [-23 LUFS]: Searwing idle call. Searwing idle call, every few seconds nearby: a fiery bird-like screech.
- `mob_searwing_hurt` (hostile) [-25 LUFS]: Searwing hurt. Searwing is hit: a short sharp pained version of its voice (a fiery bird-like screech), 0.2-0.6 s.
- `mob_searwing_death` (hostile) [-23 LUFS]: Searwing death. Searwing dies: a longer falling cry of its voice (a fiery bird-like screech), then silence; 0.5-2 s.
- `mob_scorchling_ambient` (hostile) [-19 LUFS]: Scorchling idle call. Scorchling idle call, every few seconds nearby: a tiny fiery squeak.
- `mob_scorchling_hurt` (hostile) [-12 LUFS]: Scorchling hurt. Scorchling is hit: a short sharp pained version of its voice (a tiny fiery squeak), 0.2-0.6 s.
- `mob_scorchling_death` (hostile) [-14 LUFS]: Scorchling death. Scorchling dies: a longer falling cry of its voice (a tiny fiery squeak), then silence; 0.5-2 s.
- `mob_slagthrower_ambient` (hostile) [-24 LUFS]: Slagthrower idle call. Slagthrower idle call, every few seconds nearby: a molten heavy rumble.
- `mob_slagthrower_hurt` (hostile) [-26 LUFS]: Slagthrower hurt. Slagthrower is hit: a short sharp pained version of its voice (a molten heavy rumble), 0.2-0.6 s.
- `mob_slagthrower_death` (hostile) [-25 LUFS]: Slagthrower death. Slagthrower dies: a longer falling cry of its voice (a molten heavy rumble), then silence; 0.5-2 s.
- `baby_cow_ambient` (friendly) [-20 LUFS]: Young cow idle call. The same voice higher and lighter (a low, relaxed bovine moo).
- `baby_pig_ambient` (friendly) [-24 LUFS]: Young pig idle call. The same voice higher and lighter (pig grunts and snorts).
- `baby_sheep_ambient` (friendly) [-20 LUFS]: Young sheep idle call. The same voice higher and lighter (a nasal sheep bleat).
- `baby_chicken_ambient` (friendly) [-22 LUFS]: Young chicken idle call. The same voice higher and lighter (chicken clucks and a short cackle).
- `baby_villager_ambient` (friendly) [-19 LUFS]: Young townsperson idle call. The same voice higher and lighter (a short wordless murmur 'hmm' (no real words)).
- `baby_wolf_ambient` (friendly) [-21 LUFS]: Young wolf idle call. The same voice higher and lighter (a dog-like pant and bark).
- `baby_cat_ambient` (friendly) [-21 LUFS]: Young cat idle call. The same voice higher and lighter (a domestic cat's meow).
- `baby_fox_ambient` (friendly) [-16 LUFS]: Young fox idle call. The same voice higher and lighter (a fox's yips and screech).
- `baby_goat_ambient` (friendly) [-17 LUFS]: Young goat idle call. The same voice higher and lighter (a goat's bleat (higher, harsher than sheep)).

## Note blocks

- `note_<instrument>_<pitch>` (blocks): note blocks, made on demand for instrument 0-15 (0 harp, 1 bass drum, 2 snare, 3 hat (clicks), 4 bass, 5 flute, 6 bell, 7 guitar, 8 chime, 9 xylophone, 10 iron xylophone, 11 cow bell, 12 didgeridoo, 13 bit, 14 banjo, 15 pling) and pitch 0-24 (12 = the instrument's base note). An override can be given per exact pitch (`note_0_12.wav`); there is no automatic repitching of one sample across the range yet.

## Recorded only (P457)

Made for Remington's approved recordings (Resources/Sounds/elevenlabs/README.md, wired in Oct 29, 2026); with no file each
plays a close synthesized stand-in (`Snd.synthStandIn`).

- `tankEngineLoop` (blocks): a Cinder tank (or a taken one) idling.
- `tankTracksLoop` (blocks): a tank's tracks and engine on the move (half-tracks too, quieter).
- `truckEngineLoop` (blocks): an Army truck's or half-track's petrol engine driving.
- `motorbikeLoop` (blocks): a taken sidecar motorbike running.
- `rotorLoop` (blocks): a helicopter's rotor (any hull with rotor blocks) running or flying.
- `jetpackLoop` (players): the jetpack thrusting.
- `frigateInsideLoop` (blocks): below decks on a warship in flight.
- `battleLoop` (ambient): the far-off war heard over the Ash Vault.
- `forestDayLoop` (ambient): songbirds in woods by day.
- `townLoop` (ambient): a town's bustle while the player is in one (quieter at night).
- `saloonPianoLoop` (ambient): a saloon's piano heard from the street (10-48 blocks; closer, the pianist's own pieces).
- `planeFlyby` (blocks): a plane roaring past within 40 blocks.
- `sonarPing` (blocks): the navy's sonar finding a submarine; an enemy submarine's contact.
- `shipHorn` (blocks): a ship at sea now and then.
- `airRaidSiren` (hostile): a town's siren while a strike dropship comes at it.
- `tankCannon` (players): a Cinder tank's main gun.
- `flakFire` (players): a flak gun's shot.
- `dartTrap` (blocks): a dispenser loosing an arrow.
- `ladderClimb` (players): a rung climbed on a ladder bolted to metal.
- `armourHit` (players): a sword or axe landing on worn armour.
- `packRustle` (players): opening the pack.

## Ambience per biome

Which beds and stings make up each place (the soundscapes `Blocksmith --sounds` mixes in scapes/). Wind is the one sound the owner praised: keep its character.

| Biome / place | Beds (loops) | Stings |
|---|---|---|
| Forest (day) | windLoop | birdCall |
| Forest (night) | cricketsLoop | owlHoot |
| Jungle | jungleLoop | birdCall |
| Swamp (day) | swampInsectsLoop + swampLoop |  |
| Swamp (night) | swampLoop + cricketsLoop |  |
| Beach / ocean | oceanLoop + windLoop |  |
| Meadow (night) | cricketsLoop + fireflyLoop | owlHoot |
| Badlands | windLoop | dryGrassRustle |
| Pale / ashen grove | windLoop | heartCreak, owlHoot |
| Apiary / flower fields | hiveLoop + windLoop | birdCall, beePollinate |
| Mountains | mountainWindLoop | rockfall, windGust |
| Tundra / frozen | tundraWindLoop | iceCreak |
| Snowstorm | snowWindLoop + tundraWindLoop |  |
| Rain (any) | rain + rainRoof under cover | thunder |
| Rainforest in rain | rain + rainLeavesLoop | thunderFar |
| Rivers and waterfalls | riverLoop / waterfallLoop | birdCall |
| Caves | dripstoneLoop + waterLoop | caveAmbience, caveDrip, caveWind |
| Lush caves | lushLoop | caveDrip |
| Deep Dark | deepDarkLoop | wardenHeartbeat |
| Underwater | underwaterLoop | underwaterMood |
| Lava lakes | lavaLoop + fireLoop | lavaPop |
| Emberdeep Wastes | netherWastesLoop + lavaLoop | netherMood |
| Ghost Valley | soulValleyLoop | netherMood |
| Rustcap Forest | crimsonLoop |  |
| Tealcap Forest | warpedLoop |  |
| Basalt Deltas | basaltLoop |  |
| The Hollow | endLoop | teleport |
| Ash Vault | ashVaultLoop | ashSiren, shellIncoming |
| Boreal Station | stationHumLoop |  |
| Volcano regions | (biome bed) | volcanoRumble |

## Not file-driven

- Music (Music.swift, procedural score) and the player's own music folder (CustomMusic.swift) are separate from this list.
- Legacy names `mobCow`, `mobZombie`, ... are aliases: they use the `mob_<key>_ambient` file.
- `voice_<n>` townsfolk lines come from Resources/voices.bin (already recorded).

