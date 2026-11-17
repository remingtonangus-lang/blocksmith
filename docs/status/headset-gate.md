# Headset frame-rate gate

Meta's VRC.Quest.Performance.1 asks for a steady rate above 60 fps for the whole experience. This gate measures the
real headset over adb before a store build goes in.

## Run it (on the Mac, Quest on USB, awake, USB debugging allowed)

adb: `$ADB`, else the one on PATH, else `~/ClaudeTools/quest/platform-tools/adb`. The gate never installs an APK
signed with another key than the installed app (tools/apk_signer.py compares the certificates): such an install needs
an uninstall first, which wipes the saves. The daily debug-signed builds go over each other; the store-signed APKs on
the Desktop do not go over a debug build.

    tools/headset_gate.sh ~/Desktop/Sunderfall-store-0.132.apk            # install, start, 5 minutes as it comes up
    tools/headset_gate.sh --no-install --minutes 10                       # the build already on the headset
    tools/headset_gate.sh APK --route all                                 # the on-device route player (when the build has it)

It keeps the headset awake with no head in it (`prox_close`, `automation_disable` at the end), installs the APK,
force-stops and starts `com.blocksmith.quest`, and records `adb logcat -v epoch -s VrApi:I Blocksmith:I` into
`headset-gate/<time>/raw.log`. `tools/headset_gate.py DIR` turns it into `seconds.tsv` (one row a second: leg, fps,
stale frames, App ms, GPU %, eye resolution, view distance) and `summary.txt`: per leg and overall seconds, min, p1,
p5, median fps, seconds under 70 and under 60, stale frames and worst App ms, every second under 70 listed with the
eye resolution and view distance of the app's latest perf line, the display rate and whether Space Warp was requested.

PASS = no second under 60 anywhere (launch, loading and menus included) and under 2% of seconds below 70. Exit 0 pass,
1 fail, 2 setup problem (no headset in `adb devices`, install failed).

Legs: without the route player, `launch` until the first world is handed over (`adopt:`), then `play`. With it, the
player's `route: leg NAME` lines.

## Route player (ledger 285) and switches (ledger 284)

Builds from ledger 284-285 on read two debug properties (only adb can set `debug.*`; a player's headset never has them):

- `debug.sunderfall.route`: `all` (the reviewer route: menu 20 s, new world, plains, forest, jungle, village, a fight,
  a frigate at the helm, a train, save and load again), `spots` (the A/B route: a new creative world of seed
  3084501862406496736 at noon in clear weather, then six held views, each held until the chunk jobs are 0 and then
  20 s: jungle 718 143 30 yaw 299, taiga 148 302 -3684, savanna 2139 122 827 yaw 229, a beach, the nearest village,
  a forest floor), or leg names. The summary then has a table with one row per spot: fps, the app's GPU ms, eye
  resolution, view distance, quads and clocks.
- `debug.sunderfall.env` ... `env6`: `KEY=VALUE;KEY=VALUE` merged into the game's switches at launch (printed as
  `env: from debug properties:`); `KEY+=more` continues a long value. `--env` packs a list into them:

      tools/headset_gate.sh --no-install --route spots --env "BS_EYEFIX=0.8;BS_DYNRES=0"

## What the report counts (Nov 17, after the first run on his Quest)

logcat carries one VrApi line a second from every VR process, the system shell (com.oculus.vrshell) too: the first
run counted both (476 "seconds" in 240 s, 8 of its 9 dips the shell's). Now only lines from a process that also wrote
the game's own lines (tag Blocksmith) count, which follows a restart; the shell's are one line marked "not counted".
Every second is in a phase: `launch` (nothing loading yet), `loading` (a `load:` or `world: switching` line until the
world is handed over, `adopt:`), `play`; the loading scene must hold the display rate itself (Meta's reviewers see it
first), so its missed seconds are listed on their own. With the route player, a table gives one row per leg or held
spot: seconds, min/median fps, seconds under 70 and 60, the app's GPU and CPU ms, quads, eye resolution, view, the
GPU clock (of 690 MHz) and how busy it was. `python3 tools/headset_gate.py --selftest` checks all this on a sample
with two processes and a restart.

Not in the totals or the verdict: the `launch` seconds (the system splash before the app draws) and the `spotworld`
leg (making the spot world); they get one "not counted" line, and their legs are starred in the table.

The run itself (from the second real run): logcat is started as adb itself and that pid is killed (the old `kill` hit
the shell function's subshell, so each trial's raw.log kept collecting the later trials); any leftover logcat with the
gate's arguments is killed at the start and in cleanup. The proximity override (`prox_close`) is said again every 30 s
and undone at the end. Once the XR session has been focused (state 5), any other state (asleep 6, system menu 4,
quit) or the app's process going away stops the run at once: "headset_gate: STOPPED N s in: ...", the partial report,
exit 2 (not a measurement).

## Space Warp: XR_FB_space_warp now, XR_EXT_frame_synthesis next (notes, no code yet)

Today (quest/src/xr/XRSession.swift, P381 step 9): `XR_FB_space_warp` is requested only when Options' Space Warp is on
(`QuestSettings.spaceWarp`, `BS_SPACEWARP=1` through debug.sunderfall.env; off by default, so his log says "space warp
off (P426): extension not requested"). `createSpaceWarp` reads `XrSystemSpaceWarpPropertiesFB` (recommended motion
vector size), makes an RGBA16F motion-vector swapchain and a depth swapchain (2 layers each), and every projection
view chains an `XrCompositionLayerSpaceWarpInfoFB` (motion vector and depth sub-images, `appSpaceDeltaPose`,
min/max depth 0/1, near/far). The game then draws at half the display rate and the runtime makes the other frames.

`XR_EXT_frame_synthesis` (in our openxr.h, spec version 1) is the cross-vendor version of the same thing. A path for it
needs:
1. Request "XR_EXT_frame_synthesis" when the runtime lists it (prefer it over the FB extension, keep FB as fallback).
2. The recommended motion-vector size from `XrFrameSynthesisConfigViewEXT` chained on `xrEnumerateViewConfigurationViews`
   (per view), instead of `XrSystemSpaceWarpPropertiesFB`.
3. The same two swapchains (motion vectors RGBA16F, depth), the same recording pass (SpaceWarpPass, swmotion.vert).
4. Per projection view, `XrFrameSynthesisInfoEXT` instead of the FB struct: the same sub-images, `appSpaceDeltaPose`,
   min/max depth, near/far, plus `motionVectorScale` / `motionVectorOffset` (vec4; (1,1,1,1) and (0,0,0,0) when the
   vectors are written as the FB extension expects) and `layerFlags` (`USE_2D_MOTION_VECTOR_BIT` if we write 2D vectors;
   `REQUEST_RELAXED_FRAME_INTERVAL_BIT` asks the runtime to let the app run at half rate).
5. Its structure type constants from openxr.h (XR_TYPE_FRAME_SYNTHESIS_INFO_EXT, XR_TYPE_FRAME_SYNTHESIS_CONFIG_VIEW_EXT).
Whether either one is on for the store is Fable's and Remington's call (it was tangled with the Oct 30 jitter).

## The hand-over gate: `--route all` on a reviewer's fresh install (ledger 288)

`tools/headset_gate.sh --route all` is the gate before a store build goes in. Every gate run now plays as Meta's
reviewer does: the script sets BS_REVIEWER=1 (debug property), and the app then keeps all its data in
`<app data>/reviewer`, emptied at each launch: options (UserDefaults, via HOME/XDG), worlds, the mesh cache, crash
notes and voice notes. Remington's options, worlds and notes are neither read nor written, and `quest-settings.txt`
overrides are skipped. `--own-settings` runs on his own data instead (the old behaviour). A build from before ledger
288 ignores the property; the gate sees no "reviewer: fresh data" line within 20 s and stops (exit 2) rather than
play on his worlds.

What the reviewer path covers: first launch with no worlds (the app makes "Quest World" with default options: 72 Hz,
Auto View on and its start view, 128 px textures, dynamic resolution on, Space Warp off, foveation 0); the first-launch
setup panel over the world (shown through the `menu` leg, then closed); the pause menu; making a new world; walking in
plains, forest and jungle; a village; a fight; the frigate; the train; saving and loading the world again.

What it does not cover: installing from the store and the system splash before the app draws (not counted); the
microphone permission dialog (Android keeps his grant per app, so a reviewer may see a dialog this run does not; store
builds compile voice notes out); the headset's own Guardian and account setup; real hands (the route drives the
game's pad, not the Touch controllers' tracking); thermals of a long session off the charger (the headset is on USB
power, at most 40 minutes).

## Combat legs (Nov 17 evening, Fable's store confidence)

`--route combat` (or `battle`, `siege`, `naval` by name) plays the heaviest fights the game has, each in a world the
route makes first (leg `combatworld`: GateCombat<time>, seed 7653607216494784574). No spot or combat leg runs in a
world the route did not make: the route checks the save folder and ends with "route: failed: leg X refused" otherwise
(the first combat build ran in his playtest world). battle: the Ash Vault gate in the Deep at Total War (about 100
mobs, two thirds aggro); siege: the crawler 40 blocks off the nearest military base, main gun into it every 5 s;
naval: two frigates 90 blocks off a stone float at sea (hostile or not by where they are). Set-up frames (a world
loaded on the frame thread, ships built) and 3 s after are "NAME-stage", left out of the totals with "combatworld";
then 90 s of "NAME", with "route: combat ..." every 5 s giving mobs, ships and particles (drawn quads count land only).
Headset, 0.133 base: all three held 72 once running.
