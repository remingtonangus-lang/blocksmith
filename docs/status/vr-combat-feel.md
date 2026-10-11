# L3 part 2 (Lane C): VR melee and bow feel

Backlog L3's SWING MODE / RECLINED MODE and BOW items (docs/roadmap/backlog.md). Part 1 is in docs/status/ground-l3.md
and part 3 in docs/status/l3-part3.md. The base design (blade contact, the two melee modes, the physical bow) is in
docs/status/vr-melee.md.

## Audit: already met before this part
- Damage scaled by swing speed (`VRMelee.power`, 0.7-1.1).
- Friendly-fire guard. A casual swing hits only hostiles. Villagers, townsfolk, golems, animals, pets and your horse
  need the trigger held during the swing (`Game.bladeFree`), and the mount is never hit.
- The mode switch is reachable in VR: Pause > VR Comfort & Controls > Melee.
- Seated height: in Seated Mode, Recenter View sets the standing eye height.
- The bow:
  - The draw strength sets arrow speed and damage, and a full draw crits.
  - Arrows can be picked up in survival.
  - Left- and right-handed play, with haptic ticks rising with the draw.

## Objectives (listed, then mine)
Listed:
- A first-use tutorial for each mode.
- A blade trail.
- A tiny hit-stop.
- Distinct haptics for flesh, armour and stone.
- Telegraphed enemy wind-ups (pose and sound), so dodging and blocking are fair.
- Sword-on-weapon parry.
- A soft aim-assist cone in Reclined mode.
- Comfort defaults (snap turn, vignette).
- The bow's nock animation, draw creak, and string vibration and sound on release.
- A crossbow that uses the same hand logic.

Expanded (mine):
1. Wind-ups only in VR, where you dodge with your body. On the Mac and pads, combat timing is unchanged.
   - A melee mob in reach rears back for 0.4 s (its whole body leans back) with a grunt.
   - When the wind-up ends, it strikes only if you are still within its reach plus 0.3 blocks. Stepping or leaning
     away dodges it.
   - All the main melee strikes go through one gate (`Game.meleeStrike`): the zombie family, spiders, wither
     skeletons, husks, Boarlings, golems, Voidwalkers, wolves and other animals that bite, the Warden and the
     Barkwraith, plus slimes and magma cubes, Voidmites, Hexlings and Siegebeasts. The Cinderwisp's touch and the hell
     mobs (their own wind-ups) are not.
   - A finished wind-up that the mob's AI doesn't use within 0.1 s is dropped (you died, it lost sight of you), so it
     never lands a later strike without its warning.
   - The grunt is a hostile-mob sound (the Hostile Creatures volume).
2. Parry: a fast blade meeting a winding-up mob at its upper body (its arms or weapon) cancels the strike.
   - No damage is dealt.
   - The mob is pushed back and staggered for 1.3 s.
   - A steel clang, sparks, and a strong pulse in both hands.
   - A low swing still just hits.
3. Hit-stop: a landed blade freezes the mob for 60 ms. Its knockback starts after the freeze, so the hit reads as a
   bite.
4. Hit feel by material:
   - Flesh: a deep 160 Hz thud.
   - Worn armour (4+ points, not the zombie family's natural 2): a sharp 320 Hz ring.
   - Bone, stone, iron and wood mobs (skeletons, golems, shulkers and others): a short 260 Hz knock.
   - A blade swung into a block gives a dull knock. It never breaks the block.
5. The blade trail: a pale ribbon over the last few fast frames, fading in 0.14 s.
   - It shows only while the tip moves at hitting speed, so walking with a sword leaves none.
   - A fixed ring of samples: no allocation per frame. A jump of the hand (teleport, boarding) clears it.
   - Known limits: it draws over the scene without a depth test (it is gone in 0.14 s), and its samples are in world
     space, so on a fast ship it smears behind you for that moment.
6. Reclined aim assist: the nearest hostile within ~14 degrees of the laser and in reach is attacked. It never picks
   a friendly creature (aim straight at one to hit it). Swing melee has no assist.
7. Comfort defaults: turning on Lying Down View also sets snap turning and at least a Medium vignette. Both can be
   changed afterwards.
8. Tutorials: the first time a melee weapon is held in each mode, three short toasts explain it, 3.2 s apart. Each
   fits the Quest HUD on one line.
   - Swing: swing into enemies, faster hits harder, step away to dodge, swing into a wind-up to parry, hold the
     trigger for friendly creatures.
   - Reclined: aim and pull, the assist, and where to switch modes.
   - Each is shown once (saved).
9. The bow:
   - The arrow slides 22 cm back onto the string as it is nocked, with a click.
   - The limbs creak at 35, 65 and 90 % of the draw, louder the further they bend.
   - After the shot, the string's middle shivers (a damped 28 Hz wobble, gone in 0.4 s) and the bow hand feels it buzz
     out.
10. The crossbow shoots from the aiming hand along its laser, the hand Dominant Hand picks. Before, it shot from the
    eyes.

## Checks
- `combat feel:` (Sources/VRCombatFeelTests.swift; questcheck, and the Mac `--swingtest`):
  - Trail segments behind a fast blade, none after 0.2 s, none for a slow blade.
  - Nock slide, creak thresholds, the string shiver and its end.
  - The four new sounds pass the bank's sound check.
  - Tutorial texts, each toast's width, and the help width.
  - An unused wind-up is dropped.
  - Hit feel for a zombie, an armoured zombie, a skeleton and a golem.
  - No wind-up off VR.
  - In VR: the wind-up with its grunt, then the strike after 0.4 s; stepping out of reach dodges it.
  - A high parry (no damage, staggered); low or idle is no parry.
  - The hit-stop freeze.
  - The Reclined assist: a zombie 8 degrees off yes, a villager no, Swing melee no.
  - The crossbow from the hand.
- Quest sim (quest/src/test/QuestSim.swift):
  - The fast swing leaves a blade trail.
  - The same swing into a husk winding up parries it through the real controls.
  - The Reclined posture sets snap turning and the vignette.
