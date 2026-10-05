# VR (Quest 3 / OpenXR) — design notes

Physical, seated-or-standing VR on the same game: the player's own hands draw, aim, reload and fire the guns, reach
for doors and counters, point at menus and hold the reins. Everything runs through XRController3D nodes, so a
headset and the desktop simulator take the same code paths.

## Files
| File | What |
|---|---|
| `src/xr/vr.gd` (VR) | Starts OpenXR (`--vr`, Android) or the simulator (`--vr_sim`), builds the XROrigin rig, moves the HUD and menus onto sheets (HUD head-locked, menus world-locked), stick locomotion, snap turn, comfort vignette, origin follows the player. |
| `src/xr/vr_sim.gd` (VRSim) | Desktop simulator: registers the `head`, `left_hand`, `right_hand` trackers with XRServer and drives their poses and inputs (mouse/keys or scripted). `--vr_stereo` adds a side-by-side eye pair. |
| `src/xr/vr_body.gd` (VRBody) | The player's own FrontierCharacter as the VR body: a SkeletonModifier3D (extends GunHands) — head/neck follow the HMD, two-bone arm IK to the controllers, finger curl, head meshes shadow-only. |
| `src/xr/vr_hand.gd` (VRHand) | Pose source for each hand (grip→aim frame, fist centre, finger inputs). Its procedural low-poly glove is drawn only when there is no character skeleton. |
| `src/xr/vr_play.gd` (VRPlay) | Physical play: holster draw, gun hold, two-hand snap, trigger + haptics, hand-worked actions, reload gestures, Nerve, reach-to-interact, menu laser, reins. |
| `src/tests/vr_shots.gd` (VRShots) | Scripted VR scenes (poses + inputs) shared by the studio and the in-world feature shots. |
| `src/tests/vr_studio.gd`, `scenes/vr_studio.tscn` | Light studio set (no world streaming) for VR evidence; spectator views (`*_ext`) show the IK'd body from outside; `--dump` lists every mesh with its triangle count; `--flat` runs it without VR. |
| `shaders/vr_vignette.gdshader` | Comfort vignette. |

Touch points elsewhere (all small and marked): `player.gd` (start VR on `--vr_sim`; no keyboard intent in VR),
`horse.gd` (no keyboard rider input or third-person ride camera in VR), `nerve.gd` (no screen overlay or camera cuts
in VR; execution shots leave the real muzzle), `weapon_holder.gd` (`vr_hold`: the hand places the drawn gun),
`weapon_model.gd` (`manual_cycle` / `needs_cycle` / `cycle_action()`; recoil spring sub-stepped), `game.gd` +
`sky.gd` (quest preset: 2 shadow cascades, no glow, no water refraction, mounted horse shadows from LOD1; Mobile shadow filter),
`settlements.gd` (Mobile: commit on the main thread), `horse_visual.gd` (Mobile hair variant),
`water.gd` + `water.gdshader` (`WATER_OPAQUE` variant), `menus.gd` (Accessibility > VR comfort rows),
`weapon_holder.gd` (`mount_offset()`, see Riding).

## Desktop simulator (`--vr_sim`)
No OpenXR runtime is needed. VRSim creates `XRPositionalTracker`/`XRControllerTracker` objects named like the
OpenXR ones and pushes `default`, `grip` and `aim` poses plus `trigger`, `grip`, `primary`, `ax_button`,
`by_button`, `menu_button` inputs every frame, so XRCamera3D, XRController3D and every VR script run unchanged. Only
`viewport.use_xr` stays off: the head camera renders to the window (100° across, about a Quest 3 eye).

Run it:
```
godot --path frontier -- --vr_sim                 # play: mouse = head, keys below
godot --path frontier -- --vr_sim --vr_stereo     # side-by-side stereo pair (IPD 64 mm)
godot --path frontier res://scenes/vr_studio.tscn -- --out DIR [--views hud,menu,comfort,hands,body,body_ext,gun_aim,fire,two_hand,two_hand_ext,reload,bolt,pump,nerve,riding,riding_ext,door,door_open,stereo]
godot --path frontier -- --features DIR --vr_sim [--only vr_hud,vr_gun_aim,...]   # in-world VR evidence
```
Interactive keys: mouse looks (head); LMB right trigger, RMB right grip, Q left grip, F left trigger, E A,
R B, X left Y-button (Nerve), Tab menu, WASD left stick (move), arrows right stick (snap turn / menu focus),
1/2 roll the right hand onto its side and back (revolver gate), V flicks the right hand down (lever throw,
break-open). Scripted: `VRSim.set_pose(head, left_aim, right_aim)` (origin-relative; hands as aim frames),
`set_input(side, name, value)`, `clear_inputs()`, `VRSim.look(from, to)`.

The simulator generates grip poses tilted `GRIP_TO_AIM` (35°) below the aim ray, as Quest controllers report them.
VRHand reads the real grip→aim rotation from each tracker every frame, so held things follow the runtime's own
aim pose on a headset.

CI: the "VR shots" step of `.github/workflows/frontier.yml` renders the studio views at 1080p into `snaps/vr/`
(published to `ci-snaps-claude-frontier-game`). The in-world `--vr_sim` feature run needs the full world in memory
(> 5 GB), so it is not part of CI; run it on the Mac.

## Body and hands (the player's own character)
- **VRBody** (`vr_body.gd`) is added as the last SkeletonModifier3D on the player's FrontierCharacter skeleton
  (after the animation, GunHands and the look-at) as soon as the character model exists. It reuses GunHands' rig
  measurements, `_arm()` two-bone IK and `_orient()`:
  - head bone onto the HMD orientation, neck halfway, a little chest lean with the head pitch;
  - each arm reaches its controller: the wrist sits behind the fist (GunHands' `pistol_r` offset, mirrored for the
    left) and the hand's anatomical frame matches the controller's aim frame, so the character's own hand closes
    round the held gun, the fore-end, the reins or a door handle; elbows point down and out;
  - fingers curl from the controller (grip: middle/ring/little, trigger: index, thumb touch: thumb), or wrap a held
    gun with GunHands' grip tables (index squeezes with the trigger).
- **Visible from the neck down**: head, hair, hat, beard, eyes and face meshes cast shadows only (so shadows and
  mirrors keep the whole person); everything else draws. The camera sits at the character's animated eyes, low-passed
  in the player's frame so walk bob never moves the view (the gameplay clips stand ~10 cm taller than the rest pose:
  a rest-pose camera sat inside the neck and the arms came up past the eyes), 5 cm forward so the collar stays
  behind and below when looking down. In VR the third-person aim clip is not played (it leaned the torso into the
  camera); the arms come from the controllers.
- A held gun puts the hands where GunHands puts them in third person (grip_r, and the fore-end grip_l for long guns,
  with the tuned wrist offsets and hand frames in gun space), so the hold reads the same from both cameras.
- **Room-scale lean**: leaning moves the view up to 35 cm from where the head "belongs"; that rest point follows the
  head over a couple of seconds (the body catches up), so positional tracking is never cancelled.
- **Body yaw** follows the head once it looks more than ~35° away (like shifting your feet).
- The capsule glove (VRHand) is only drawn if there is no character skeleton (stand-in body); it is now 8-segment
  low-poly (the old 64-segment capsules were 3.5 k triangles each, ~200 k for two hands).

## Guns (WeaponModel + WeaponHolder)
- **Draw**: grip the right hand within 0.32 m of the holstered sidearm's grip, or within 0.48 m of the long gun (or
  reach back over the right shoulder) → that weapon is selected and drawn into the hand. Release the grip → it goes
  back to its holster/sling with the holder's normal holster animation. In VR a gun is out only while a hand holds
  it.
- **Hold**: the model's `grip_r` marker sits on the fist with the gun on the aim frame, so the rear and front sights
  line up when the controller is brought to the eye: aiming down the real sights, no crosshair.
- **Two hands** (long guns): squeeze the left hand within 0.2 m of `grip_l` → the support hand snaps on and the gun
  points from the right hand through the left; release to let go.
- **Fire**: right trigger (edge) fires from the muzzle marker along the barrel (`GunHandler.fire`, aimed spread
  ×0.5), muzzle flash, smoke, recoil spring, and a haptic pulse (right 0.9 / 90 ms, left 0.6 when two-handed).
  Empty or uncycled → dry click and a light tick.
- **Actions by hand** (`WeaponModel.manual_cycle`): after a shot the lever/bolt/pump stays closed
  (`needs_cycle`) until worked: flick the gun down (> 1.3 m/s along the gun's down axis) to throw a lever; grab the
  bolt knob (`GunHands.BOLT_KNOB`) with the left hand and work it back and forward (below); jerk the fore-end back
  (> 0.9 m/s) on a pump.
  `cycle_action()` plays the model's own cycle (ejecting the case).
- **Reloads** (rounds come from the hand, not a timer — `GunHandler.reloading` is held open with an infinite timer):
  - loading-gate revolvers: roll the gun onto its left side (right side up) → gate opens and the hammer goes to half
    cock; roll back upright → closes;
  - top-break / break-action / rolling block: flick the muzzle down hard → opens (spent cases fly), flick up → closes;
  - rounds: squeeze the left hand at the belt (left front of the hips) → a cartridge or shell appears in the
    fingers; bring it within 0.11 m of the gate / breech / port → +1 round (`clip`/`ammo`), click, haptic; the
    holder's `_reload_watch` plays the model's per-round animation (`reload_anim`);
  - bolt rifles: grab the bolt knob with the left hand, draw it back along the gun (the spent case flies at the end
    of the stroke) and let go: it stays open (`bolt_v`, posed with `WeaponModel.pose()`); rounds go in through the
    open action only; grab it again and push it home to chamber. The gun will not fire with the bolt open;
  - the pump loads through its loading gate under the receiver, ahead of the trigger guard (`VRPlay.LOAD_GATE`);
    roll the gun belly-up and push shells in;
  - lever guns load through the side gate (`reload_anim(n)` animates the gate per round).
- **Nerve**: left Y with a gun out → slow time and a world grade (the screen overlay would land on the HUD sheet, so
  VR desaturates the Environment instead); the trigger marks where the muzzle points (`Nerve.mark` from the muzzle);
  Y again or letting go of the gun fires the marks; execution shots leave the real muzzle and the camera never cuts.

## Interactions, menus, riding
- **Reach**: a free hand within 0.75 m (flat distance, plus height slack) of anything in group `interactable`
  (people, horses, shops, the bounty board, campfires, camp fire) shows `[Grip] <prompt>` on the HUD sheet; a
  squeeze calls `interact(player)`. Doors: `settlements.nearest_door(hand, 0.6)` (and loose doors in group `door`
  for test sets) → "Open door"/"Close door"; squeeze → `TownDoor.interact(player)` (swings away from you). A stays a
  fallback interact for whatever the HUD prompts.
- **Menus**: the menu sheet is world-locked 1.4 m ahead when it opens. The right hand is a laser pointer: the ray
  from its aim pose hits the sheet, a beam and dot show where, mouse motion goes to the menu viewport (hover) and the
  trigger clicks. Right stick / A / B still navigate focus; left menu button opens and backs out.
- **Riding**: squeeze both hands (no gun in them) to take the reins: two straps run from the fists to the bit. The
  grab sets the neutral; move the hands left/right to steer (±14 cm = full), push both forward (> 7 cm) to urge the
  horse up a pace (each push is a tap of the pace system), pull back (> 6 cm) to stop. Holding the reins walks on;
  let go to ride on the left stick instead. Rider input and the ride camera are off in VR; the head is the camera.
  Mounted, the long gun draws only from the scabbard mouth itself (0.16 m), so rein hands by the pommel never pull it.
  Note: while riding, the skeleton's readable bone poses keep the hips about a metre above (and behind) the drawn,
  seated body (the ride clips seat the body at draw time; root motion is on `Skeleton:Root`). The third-person gun
  belt and holster floated above the rider because of it. `WeaponHolder.mount_offset()` (seat point minus the read
  hips) now maps read bone positions onto the drawn body for the belt/holster and the VR arm IK targets; the mounted
  camera sits straight above the saddle seat by the character's hips-to-eyes height.
- **Comfort** (Settings > Accessibility > VR comfort, shown in VR; saved with the other settings):
  - Turning: Snap 30° (default), Snap 45° or Smooth, with a smooth turn speed (45–180°/s, default 100);
  - Comfort vignette strength (0 = off … 1.5; default 1): darkens the periphery while moving on foot (with speed)
    and while riding (pace + turn rate);
  - Play position: Standing or Seated, and **Calibrate height**: stand or sit naturally and press it; the measured
    eye height maps your real eyes onto the character's (standing and not calibrated: the head height one second
    into the session is taken as your eye height; seated defaults to 1.2 m), so crouching in the room still lowers
    the view;
  - HUD sheet head-locked and slightly low, menus world-locked.

## Quest performance (Mobile renderer)
The Quest export switches to the Mobile renderer (`rendering_method.mobile="mobile"`, `tools/setup_quest.sh`) and
the `quest` preset (`game.gd`). Everything below was checked here with `--rendering-method mobile --quality quest`
on lavapipe (software Vulkan), which runs the same Mobile renderer code paths; nothing has been profiled on a Quest.

| Feature | Mobile | quest preset |
|---|---|---|
| SSAO, SSIL, SSR, SDFGI, volumetric fog | not available (Forward+ only) | all off |
| Subsurface scattering (skin) | not available; Godot warns once and draws skin without SSS | — |
| Screen/depth textures (water refraction, Nerve overlay) | supported, but a copy per view | **water uses the `WATER_OPAQUE` variant** (no refraction) |
| Glow | supported, but a full-screen chain per eye | off |
| Directional shadows | supported | 60 m, 2048, 2 cascades; **soft filter Very Low** (see below) |
| Hair cards with alpha-to-coverage (horse mane/tail) | — | Mobile uses a plain alpha-scissor variant |
| MSAA | supported (cheap on tile GPUs) | 2× |
| Environment adjustments (Nerve grade) | supported | used by VR Nerve |
| Cloud shadows, moon shadows, TAA, upscalers | — | off |

### Bugs found and fixed on the Mobile renderer
- **Boot deadlock with towns**: building a settlement on a worker thread (ArrayMesh/MultiMesh creation and
  material assignment in `settlements._prepare`) deadlocked the boot under Mobile (gdb: main thread and a worker
  each waiting on a condition variable inside the engine, the other workers blocked on that worker's mutex; never
  happens on Forward+). With `--disable settlements` the world rendered. Fix: on Mobile the worker only runs the
  kits (`_build_kits`) and the meshes are committed on the main thread (`_commit_kits`, ~0.35–0.7 s per town here);
  Forward+ keeps the all-in-worker path.
- **StandardMaterial3D surfaces got no sunlight**: with the project's soft shadow filter (quality 3; 2 also
  fails), every StandardMaterial3D surface lost all direct light whenever the sun cast shadows: the ground,
  imported props and guns read dark grey (that was the "dark-grey studio ground", not a texture problem). Custom
  shaders (terrain, foliage, grass, characters, buildings) were unaffected. Fix: Mobile uses filter quality 1 (Soft
  Very Low), via `soft_shadow_filter_quality.mobile=1` in project.godot and at start-up in `game.gd` when the
  current rendering method is mobile. Measured: studio ground (68,66,60) → (151,127,96), the same as Forward+.
- The terrain, grass, trees (incl. impostors), roads, river water and sky render correctly on Mobile after these
  fixes (in-world town shot, quest preset, 480×270: 62 draws / 1.09 M primitives). In-world VR shots with characters
  were OOM-killed in this shared sandbox; the VR numbers below come from the studio set.

### Draw calls and primitives (mono, `--vr_sim`, studio, Mobile + quest)
| View | before (start of round) | after |
|---|---|---|
| HUD only | 22 / 138 k | 65 / 126 k |
| hands in front of the face | 141 / 1.03 M | 108 / 291 k |
| revolver aimed, 3 figures | 65 / 308 k | 88 / 176 k |
| mounted, reins, horse in view | **161 / 1.16 M** | **123 / 344 k** |

Where the mounted 1.16 M went: the procedural gloves (two hands of 64-segment capsules, ~200 k triangles, drawn
again in every shadow cascade) are replaced by the character's own hands (gloves stay as an 8-segment fallback);
the mounted horse casts its shadows with its 8 k LOD1 body instead of the 26 k hero mesh; and the studio sun now
follows the preset's 2 cascades (the game's quest sky already did; with 4 cascades the after-figure is 579 k).
More draw calls than before in some views come from the character body now being drawn (body, belt, holster) and
from the merged character/town-life changes; all stay well within a Quest budget (~200-300 per eye pass with
multiview).
The studio and feature-shot logs print `draws / objects / prims` per shot; `vr_studio.tscn --dump` lists every mesh
with its triangle count, visibility range and shadow mode.

Knobs still open for the device pass:
- character LOD0 budgets (24 k) are fine for a few people; the quest crowd budget is 6 full-detail characters;
- the HUD sheet (1600×900) and menu sheet (1920×1080) are extra 2D viewports; only the visible one renders;
- holstered and slung guns switch to their LOD1 mesh beyond 9 m (`WeaponModel.set_detail`);
- settlement commits on the main thread on Mobile could be spread over several frames if the hitch shows on device.

## Known gaps
- Not run on a headset yet; thresholds (flick speeds, reach radii, rein offsets) are first guesses tuned in the
  simulator.
- No finger tracking (controller curls only); no elbow tracking (poles are fixed per side).
- The head follows the HMD by orientation only: crouching in the room lowers the view but not the body.
- Mounted, the rider's head turns from the read pose; seen from outside it can look a little high/back.
- The Accessibility colour filter lives in the menu canvas, so in VR it only filters the menu sheet.
- Laser clicks are mouse events pushed into the menu viewport (works with the existing Control menus).
- In-world VR shots need the Mac (memory); CI renders the studio set.
- The Mobile fixes were found on lavapipe; the shadow-filter and alpha-to-coverage problems may be driver-specific,
  but the workarounds are cheap and correct on any GPU.
