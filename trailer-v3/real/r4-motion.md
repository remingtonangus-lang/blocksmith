# Sunderfall trailer r4: steadier cut, and how the motion was measured

The cut is `Sunderfall trailer r4 Nov 14 (steady cut).mp4` on Drive > Sunderfall: 36.7 s, 60 fps, 9 shots plus the end card, all from your Nov 14 headset clips.

## How I measure motion now

`motion.py` (in project files, store-media/footage-tools) tracks the picture from frame to frame with OpenCV. It uses the recorder's real frame times and works out:

- **turn:** how fast the view swings, in degrees per second
- **shake:** the jitter on top of the intended move
- **roll:** how fast the horizon tilts
- **jerk:** sudden starts and whips

These combine into one busy score: under about 4 is calm, and over about 8 is jarring.

I ran it on all 185 clips, so every second of today's footage has numbers.

## What it found in r2

- **Flyovers were the worst shots.** The village scored 19.5 (swinging about 115°/s, with roll near 60°/s). The cave scored 15.7, the build 12.8 and the coast 10.0.
- **The recorder runs at about 24 fps with uneven gaps** (30 to 50 ms, and an occasional hitch up to 170 ms). Converting that to 30 fps repeated frames, which added stutter.
- **Stabilising doesn't fix it.** The head moves too far for a small crop to remove.

## What r4 does

- **Calm windows only.** Each shot is the calmest stretch of a clip that still shows the subject.
- **Slow motion on the busy-but-good shots.** The stilt village, flowers, build, cave and lava play at 0.6 to 0.7 speed, with in-between frames made by motion interpolation.
- **60 fps output from the recorder's own frame times,** so no frames are repeated at random.
- **Clean hard cuts.** r3 had a half-blended frame at every cut; r4 doesn't.
- **The build shot avoids a recorder hitch** (the jump and freeze in r3).
- **True captions:** "Track game in the wild", "Roll out in a tank", "Take the fight to the Ash Vault" and "Blow it all up".

## Busy score per shot

| Shot | r2 | r4 |
|---|---|---|
| Stilt village | 5.9 | 4.2 |
| Flowers | 6.8 | 1.9 |
| Village flyover | 19.5 | cut |
| Coast flyover | 10.0 | cut |
| Build | 12.8 | about 4 |
| Cave | 15.7 | 4.7 |
| Lava | 9.7 | 3.0 |
| Tank | 7.3 | 3.3 |
| Ash Vault | 5.2 | 4.1 |
| House blast | 3.5 | 2.8 |
| Sunset | 2.5 | 2.9 |
| **Whole trailer** | **9.9** | **3.3** |

The wolf shot is new in r4 and scores 2.8.

## Still open (blind review of r3)

- **The HUD in every shot is the top issue.** That's the minimap, coordinates, "Your things", world notes, the hotbar and the hunting tooltip on the wolf. It needs a recording with Hide HUD on.
- **The tank shot is the third-person chase view.**
- **There's a smudge in the sunset sky** (the back of a HUD panel).
