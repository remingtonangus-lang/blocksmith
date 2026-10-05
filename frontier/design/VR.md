# VR (Quest 3 / OpenXR) — design notes

Physical, seated-or-standing VR on the same game: the player's own hands draw, aim, reload and fire the guns, reach
for doors and counters, point at menus and hold the reins. Everything runs through XRController3D nodes, so a
headset and the desktop simulator take the same code paths.

## Files
| File | What |
|---|---|
| `src/xr/vr.gd` (VR) | Starts OpenXR (`--vr`, Android) or the simulator (`--vr_sim`), builds the XROrigin rig, moves the HUD and menus onto sheets (HUD head-locked, menus world-locked), stick locomotion, snap turn, comfort vignette, origin follows the player. |
| `src/xr/vr_sim.gd` (VRSim) | Desktop simulator: registers the `head`, `left_hand`, `right_hand` trackers with XRServer and drives their poses and inputs (mouse/keys or scripted). `--vr_stereo` adds a side-by-side eye pair. |
| `src/xr/vr_hand.gd` (VRHand) | Procedural gloved hand (palm, 4×3 finger segments, 2-segment thumb, cuff, shirt sleeve) with finger curl from grip / trigger / thumb touch. |
| `src/xr/vr_play.gd` (VRPlay) | Physical play: holster draw, gun hold, two-hand snap, trigger + haptics, hand-worked actions, reload gestures, Nerve, reach-to-interact, menu laser, reins. |
| `src/tests/vr_shots.gd` (VRShots) | Scripted VR scenes (poses + inputs) shared by the studio and the in-world feature shots. |
| `src/tests/vr_studio.gd`, `scenes/vr_studio.tscn` | Light studio set (no world streaming) for VR evidence. |
| `shaders/vr_vignette.gdshader` | Comfort vignette. |

Touch points elsewhere (all small and marked): `player.gd` (start VR on `--vr_sim`; no keyboard intent in VR),
`horse.gd` (no keyboard rider input or third-person ride camera in VR), `nerve.gd` (no screen overlay or camera cuts
in VR; execution shots leave the real muzzle), `weapon_holder.gd` (`vr_hold`: the hand places the drawn gun),
`weapon_model.gd` (`manual_cycle` / `needs_cycle` / `cycle_action()`; recoil spring sub-stepped), `game.gd` +
`sky.gd` (quest preset: 2 shadow cascades, no glow).

## Desktop simulator (`--vr_sim`)
No OpenXR runtime is needed. VRSim creates `XRPositionalTracker`/`XRControllerTracker` objects named like the
OpenXR ones and pushes `default`, `grip` and `aim` poses plus `trigger`, `grip`, `primary`, `ax_button`,
`by_button`, `menu_button` inputs every frame, so XRCamera3D, XRController3D and every VR script run unchanged. Only
`viewport.use_xr` stays off: the head camera renders to the window (100° across, about a Quest 3 eye).

Run it:
```
godot --path frontier -- --vr_sim                 # play: mouse = head, keys below
godot --path frontier -- --vr_sim --vr_stereo     # side-by-side stereo pair (IPD 64 mm)
godot --path frontier res://scenes/vr_studio.tscn -- --out DIR [--views hud,menu,hands,gun_aim,fire,two_hand,reload,nerve,riding,door,door_open,stereo]
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

## Hands and body
- Hands are procedural (gloves, so they suit any character): palm box, jointed capsule fingers, thumb, leather cuff
  and a linen sleeve that runs back out of view. Grip curls the middle/ring/little fingers, trigger the index, a
  thumb touch (`primary_touch`/`ax_touch`/`by_touch`) the thumb; holding a gun wraps the hand with the index on
  the trigger. Curl is smoothed (24 /s).
- Hand frame = the aim frame; the fist centre (`VRHand.FIST`) sits on the grip-pose origin, which is where guns,
  rounds and reins are attached (`aim_transform()`).
- The third-person body stays in the scene as **shadows only** (cast shadow mode SHADOWS_ONLY, re-applied every
  second because character models arrive late), so the player sees their shadow and mirrors/shadows read right with
  no face inside the camera. The body turns after the head once it looks more than ~35° away. An IK'd upper body
  (arms to the controllers) is a follow-up: GunHands already solves arms to a gun; it would need targets from the
  controllers instead of `grip_r`/`grip_l`.

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
  bolt knob (`GunHands.BOLT_KNOB`) with the left hand; jerk the fore-end back (> 0.9 m/s) on a pump.
  `cycle_action()` plays the model's own cycle (ejecting the case).
- **Reloads** (rounds come from the hand, not a timer — `GunHandler.reloading` is held open with an infinite timer):
  - loading-gate revolvers: roll the gun onto its left side (right side up) → gate opens and the hammer goes to half
    cock; roll back upright → closes;
  - top-break / break-action / rolling block: flick the muzzle down hard → opens (spent cases fly), flick up → closes;
  - rounds: squeeze the left hand at the belt (left front of the hips) → a cartridge or shell appears in the
    fingers; bring it within 0.11 m of the gate / breech / port → +1 round (`clip`/`ammo`), click, haptic; the
    holder's `_reload_watch` plays the model's per-round animation (`reload_anim`);
  - lever and bolt rifles and the pump load through the port any time (`reload_anim(n)` per round).
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
- **Comfort**: snap turn 30° by default (smooth optional), vignette while moving on foot (with speed) and while
  riding (pace + turn rate), HUD sheet head-locked and slightly low, menus world-locked.

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
- Hands are procedural capsules, not the character's own hands; no finger tracking.
- No IK'd upper body; the body is shadows-only.
- Bolt rifles load through the port without opening the bolt by hand; pump loading port is approximated by the
  ejection port.
- Laser clicks are mouse events pushed into the menu viewport (works with the existing Control menus).
- In-world VR shots need the Mac (memory); CI renders the studio set.
