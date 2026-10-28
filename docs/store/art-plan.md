# Store art and screenshot plan

All images are captured in the headset from the store build (the store rejects editor views and mock-ups). No words,
logos, rating badges or prices are drawn on any image: the store adds the name. Nothing from another game appears
in a frame (check the namecheck and the ember-mark insignia before capturing).

## Cover art
| Asset | Size | Shot |
|---|---|---|
| Hero (landscape) | 2560 x 1440 | Golden hour on a ridge above a frontier town: the rider on a horse in the left third, the town's main street and church below, a frigate on the sea at the horizon. Keep the subject inside the middle 80 %. |
| Small landscape | 1280 x 720 | The same scene cropped to the rider and the town. |
| Square icon | 1024 x 1024 | A close shot of a gloved hand holding a revolver against a dusk sky, no background clutter. |
| Portrait (if asked) | 1440 x 2560 | The bell tower of the Dust Mission against a starry desert night. |

## Screenshots (2560 x 1440, at least 3; plan 7)
1. Digging: both hands on a pickaxe striking a hillside, chips flying, smooth ground (shows the world is not cubes).
2. Town: main street at noon with shopkeepers, the bank, the saloon and the sheriff's office.
3. Gunplay: a hands-on reload (magazine at the hip) behind cover at a Greywall base.
4. Riding: galloping beside a train at sunset.
5. Sailing: at the helm of the frigate in a sea battle, cannon smoke.
6. Hunting: following a blood trail through a pine forest at dawn with the bow.
7. The last war: the Ashguard's Cinder Tank breaking through a fence at an Ash Vault base (ember-mark flags only).

Capture each with the in-game photo mode off (no HUD), the comfort vignette off, and the default render settings.

## Trailer (optional)
45 s, 2560 x 1440 MP4: the eight shots in motion in the same order, recorded on the headset.

## How the pictures are made (P482)
Two ways, both the real game:

1. **Scenery from the game's own renderer** (no headset needed). `questcheck --view` draws a frame through the same
   Vulkan renderer, shaders and meshes the headset runs (on the host's software Vulkan), at any size. It renders both
   eyes side by side; keep the left half. Store sizes: `--w 2560 --h 1440` per eye for a screenshot or the hero,
   `--w 1280 --h 720` for the small landscape. About 4 min a shot at 1280 x 720 and view 10 on the cloud host, roughly
   four times that at 2560 x 1440.
   `questcheck --view OUT.png --field --questlod --seed SEED --at X,Y,Z --rd 10 --w W --h H --fov 80 --time T`
   plus `--up N` (eye height over the ground), `--look YAW,PITCH`, `--near village|capital_city|military_base --off N`
   (framed on the nearest one), `--rail N --train passenger|cargo|troop` (a train on the nearest line).
   It shows no hands, guns, people or HUD: those shots come from the headset.
   First candidates (1280 x 720, his world's seed 7639458412018979794): `store-candidates/` in the project files
   (village, Capital city at noon, a Greywall base, a passenger train in the pines, a snowy taiga). The overseer picks;
   none is final.
2. **On the headset**, for the shots with hands, guns, horses, crews and the trailer. The headset plugged into his Mac;
   the overseer runs, over adb (the action names below are the commonly used ones; confirm them on his headset's
   firmware the first time):
   - keep it awake with nobody wearing it: `adb shell am broadcast -a com.oculus.vrpowermanager.prox_close`
     (undo: `...automation_disable`);
   - capture size: `adb shell setprop debug.oculus.capture.width 2560` and `debug.oculus.capture.height 1440`
     (video also `debug.oculus.capture.bitrate 20000000`);
   - a still: `adb shell am startservice -n com.oculus.metacam/.capture.CaptureService -a TAKE_SCREENSHOT`, then pull
     the newest file from `/sdcard/Oculus/Screenshots/`;
   - video: the same service with `-a START_CAPTURE` / `-a STOP_CAPTURE`, files in `/sdcard/Oculus/VideoShots/`.
   In the game: Photo Mode off the HUD, comfort vignette off, default render settings, a store build (no bug-note or
   playtest overlays).

Nothing captured goes into the repo (pictures and clips are binaries): they live in the project files until uploaded.
