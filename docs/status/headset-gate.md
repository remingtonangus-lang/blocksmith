# Headset frame-rate gate

Meta's VRC.Quest.Performance.1 asks for a steady rate above 60 fps for the whole experience. This gate measures the
real headset over adb before a store build goes in.

## Run it (on the Mac, Quest on USB, awake, USB debugging allowed)

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
