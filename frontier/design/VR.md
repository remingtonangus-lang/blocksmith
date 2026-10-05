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
`sky.gd` (quest preset: 2 shadow cascades, no glow, no water refraction, mounted horse LOD1; Mobile shadow filter),
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
  mirrors keep the whole person); everything else draws. The camera sits at the character's eyes (rest pose, so walk
  bob never moves the view; 1 cm forward so the collar stays behind and below when looking down).
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
  hips) now maps read bone positions onto the drawn body for the belt/holster, the VR arm IK targets and the
  mounted camera.
- **Comfort** (Settings > Accessibility > VR comfort, shown in VR; saved with the other settings):
  - Turning: Snap 30° (default), Snap 45° or Smooth, with a smooth turn speed (45–180°/s, default 100);
  - Comfort vignette strength (0 = off … 1.5; default 1): darkens the periphery while moving on foot (with speed)
    and while riding (pace + turn rate);
  - Play position: Standing or Seated, and **Calibrate height**: stand or sit naturally and press it; the measured
    eye height maps your real eyes onto the character's (standing uncalibrated = 1:1 real height; seated defaults to
    1.2 m and is raised to the character's eye height);
  - HUD sheet head-locked and slightly low, menus world-locked.

## Quest performance (Mobile renderer)
The Quest export switches to the Mobile renderer (`rendering_method.mobile="mobile"`, `tools/setup_quest.sh`) and
the `quest` preset (`game.gd`). What that means:

| Feature | Mobile | quest preset |
|---|---|---|
| SSAO, SSIL, SSR, SDFGI, volumetric fog | not available (Forward+ only) | all off |
| Subsurface scattering (skin) | not available; Godot warns once and renders the skin without SSS | — |
| Screen/depth textures (water refraction, Nerve overlay) | supported, but cost a copy per view | water still uses them (see knobs) |
| Glow | supported, but a full-screen chain per eye | **off** (new) |
| Directional shadows | supported | 60 m, 2048, **2 cascades** (new; was 4) |
| MSAA | supported (cheap on tile GPUs) | 2× |
| Environment adjustments (Nerve grade) | supported (verified) | used by VR Nerve |
| Cloud shadows, moon shadows, TAA, upscalers | — | off |

Verified here by rendering the VR studio with `--rendering-method mobile --quality quest` (lavapipe): hands, guns,
characters, horse, reins, HUD sheet, the Nerve grade and the vignette all render; the only engine warning is the
skin SSS. One studio-only difference: the studio ground (StandardMaterial with a triplanar packed albedo) renders
dark grey on Mobile; the game terrain uses its own shader and wasn't checked on Mobile here.

Draw calls and primitives per frame (mono, the simulator; multiview renders both eyes in one pass on Quest) in
the studio on Mobile + quest preset: HUD-only view 22 draws / 138 k primitives; gun scene with three figures
65 draws / 320 k; mounted with the horse in view 161 draws / 1.16 M. The same views on Forward+ with the desktop
preset cost 65 / 242 / 448 draws (4 shadow cascades, depth prepass), so the quest preset roughly thirds the draw count. The feature-shot and studio logs now print
`draws / objects / prims` per shot, so the CI logs (High preset on the Mac runner) carry the same numbers for the
in-world scenes.

Knobs and recommendations for the device pass (not profiled on a Quest yet):
- the horse at close range is the heaviest single item (LOD0 body 26 k tris plus mane/tail cards; most of the
  1.16 M primitives above come with it, shadow pass included): drop to Body_LOD1 and fewer hair cards in VR when
  mounted (the rider never sees the horse's body from more than a metre or two);
- character LOD0 budgets (24 k) are fine for a few people; the quest crowd budget is 6 full-detail characters
  (`character_factory.gd`);
- water: a no-refraction variant for the quest preset would remove the per-eye screen copy;
- keep the HUD sheet at 1600×900 and the menu sheet at 1920×1080 (each is one extra 2D viewport, updated every frame;
  only the visible sheet renders: the menu sheet while a menu is open, the HUD sheet otherwise);
- holstered and slung guns switch to their LOD1 merged mesh beyond 9 m (`WeaponModel.set_detail`), so the player's
  own guns are the only LOD0 guns in a normal scene.

## Known gaps
- Not run on a headset yet; thresholds (flick speeds, reach radii, rein offsets) are first guesses tuned in the
  simulator.
- No finger tracking (controller curls only); no elbow tracking (poles are fixed per side).
- The head follows the HMD by orientation only: crouching in the room lowers the view but not the body.
- Mounted, the rider's head turns from the read pose; seen from outside it can look a little high/back.
- The Accessibility colour filter lives in the menu canvas, so in VR it only filters the menu sheet.
- Laser clicks are mouse events pushed into the menu viewport (works with the existing Control menus).
- In-world VR shots need the Mac (memory); CI renders the studio set.
