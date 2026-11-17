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
