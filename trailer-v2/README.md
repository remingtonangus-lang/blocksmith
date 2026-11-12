# Trailer v2: first render for Carbon's review (Nov 12)

This is Carbon's DIRECTION.md, trailer-shots.v2.json and cine_cut.v2.py, rendered on quest-port with PR #710. That PR
has the strike fixes and the light gun on the snow base roof. The cut runs 48.3 s, in two versions:
sunderfall_trailer_v2_captions.mp4 and _clean.mp4. Each shot is also in clips/ (1920x1080). review/ has a contact
sheet at one frame per second.

## Engine work done for it (Cinema.swift, branch claude/project-thread-1q6065)
- The block outline is never drawn in cine shots.
- `"hold": "<item key>"` on a shot draws the headset's own VR hands (the game's controller grips) at rest below the
  view, with the item held in the right hand. The shots use these items: fp_build oak_planks, fp_farm iron_hoe,
  fp_cave_lush lantern, station_breach gun_sidearm, outlaw_fight gun_rifle, fp_ride lead.
- `"playerMount": "horse"`: the player rides a saddled horse that canters along the camera's heading. The camera is the
  rider's eye, and the keys only set the look. No NPC riders.
- tools/cine.py cut ... --cutlist docs/store/trailer-v2/cine_cut.v2.py (SWITCH and FINALE are added there).

## Changes to the spec, with reasons
- hook_frigate_bow: the anchor's third "frigate" number is a heading in degrees, not a height. The spec's
  [-45, 95, 155] spawned her flying away from the camera. She now heads -25 deg toward the village, and the camera
  stands on the ground at the village edge. She passes over bow first, with the Capital tower behind.
- train_pass: 7 s and ss 3.6, so the engine fills the frame early.
- fp_ride: the look is pitched down about 15 deg, so the horse's head and ears show at the bottom.
- "Key.cut" already exists. Shots that use "station": "boreal_corridor" render the corridor.

## Known issues
1. VR hands are the game's own grips (dark controller blocks), not skinned hands. Items are drawn at the headset's
   held scale, which looks big on a flat screen. The hand pose is fixed in code at about (0.2, -0.27, -0.4) m from the
   eye; it can be tuned.
2. fp_ride: the lead reads as a coil of rope, and only the horse's ears and the top of its head show. I can look down
   more, or hold nothing.
3. fp_build: the cut shows the cabin's walls rising seen from close up, so it reads as a large wall. A wider stance
   would read better.
4. outlaw_fight: the blasts leave a crater that opens into a cave (black hole), and treetops fly.
5. frigate_strike: much cleaner with #710 (no strobing). A few orange and grey bits still fly above the crater.
6. station_approach: a burnt crater lies along the fence on the right, from the base's own fight.
7. ash_vault_war: a trooper walks right up to the lens near the end.
