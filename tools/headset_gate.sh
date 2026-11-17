#!/bin/bash
# Headset frame-rate gate (ledger 281's store job; docs/status/headset-gate.md). Runs on the Mac with the Quest on USB:
#   tools/headset_gate.sh [APK] [--minutes N] [--route LEGS] [--out DIR] [--no-install]
# APK: installed first (adb install -r); without one, the build already on the headset is measured.
# --route all (or a list such as "menu newworld walk jungle"): the on-device route player plays those legs (debug
#   property debug.sunderfall.route, cleared at the end); without it the app is left alone (menu, then the world it
#   loads) for --minutes (default 5).
# Records `adb logcat` VrApi (the source OVR Metrics shows: FPS=a/b, Stale, App/GPU ms, CPU/GPU levels) and the app's
# own lines (tag Blocksmith: perf, load, route, xr), once a second, tagged by leg. Writes DIR/raw.log, DIR/seconds.tsv,
# DIR/summary.txt. PASS = no second under 60 fps anywhere (menus and loading included) and under 2% of seconds below
# 70. Exit 0 pass, 1 fail, 2 setup problem (no headset, install failed).
set -uo pipefail
cd "$(dirname "$0")/.."
PKG=com.blocksmith.quest
ACT=$PKG/android.app.NativeActivity
APK=""; MIN=5; ROUTE=""; OUT=""; INSTALL=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --minutes) MIN="$2"; shift 2 ;;
    --route) ROUTE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --no-install) INSTALL=0; shift ;;
    -h|--help) sed -n 2,12p "$0"; exit 0 ;;
    *) APK="$1"; shift ;;
  esac
done
OUT=${OUT:-headset-gate/$(date +%Y%m%d-%H%M%S)}
mkdir -p "$OUT"
command -v adb >/dev/null || { echo "headset_gate: adb not found (brew install android-platform-tools)"; exit 2; }
n=$(adb devices | awk 'NR>1 && $2=="device"' | wc -l | tr -d ' ')
if [[ "$n" != 1 ]]; then
  adb devices
  echo "headset_gate: need exactly one headset in 'device' state (plug it in, put it on once and allow USB debugging)"
  exit 2
fi
echo "headset_gate: $(adb shell getprop ro.product.model | tr -d '\r'), build $(adb shell getprop ro.build.version.incremental | tr -d '\r')"
# Awake with no head in it (undone at the end).
adb shell am broadcast -a com.oculus.vrpowermanager.prox_close >/dev/null
cleanup() {
  adb shell setprop debug.sunderfall.route '""' >/dev/null 2>&1
  adb shell am broadcast -a com.oculus.vrpowermanager.automation_disable >/dev/null 2>&1
  [[ -n "${LOGPID:-}" ]] && kill "$LOGPID" 2>/dev/null
}
trap cleanup EXIT
if [[ -n "$APK" && "$INSTALL" == 1 ]]; then
  echo "headset_gate: installing $APK"
  adb install -r "$APK" | tail -1 | grep -q Success || { echo "headset_gate: install failed"; exit 2; }
fi
echo "headset_gate: app version $(adb shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r')"
adb shell am force-stop $PKG
sleep 2
adb shell setprop debug.sunderfall.route "${ROUTE:-\"\"}"
adb logcat -c
adb logcat -v epoch -s VrApi:I Blocksmith:I > "$OUT/raw.log" 2>&1 &
LOGPID=$!
adb shell am start -n $ACT >/dev/null
START=$(date +%s)
if [[ -n "$ROUTE" ]]; then
  # The route player prints "route: done" (or "route: failed ...") at its end; 40 minutes at most.
  until grep -q 'route: done\|route: failed' "$OUT/raw.log" || (( $(date +%s) - START > 2400 )); do sleep 5; done
else
  sleep $(( MIN * 60 ))
fi
kill "$LOGPID" 2>/dev/null; LOGPID=""
adb shell am force-stop $PKG
python3 "$(dirname "$0")/headset_gate.py" "$OUT"
