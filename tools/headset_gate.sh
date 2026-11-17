#!/bin/bash
# Headset frame-rate gate (ledger 285, the store job; docs/status/headset-gate.md). Runs on the Mac with the Quest on USB:
#   tools/headset_gate.sh [APK] [--minutes N] [--route LEGS] [--out DIR] [--no-install]
# APK: installed first (adb install -r); without one, the build already on the headset is measured.
# --route all (or a list such as "menu newworld plains jungle"): the on-device route player plays those legs (debug
#   property debug.sunderfall.route, cleared at the end); without it the app is left alone (menu, then the world it
#   loads) for --minutes (default 5).
# --env "BS_A=1;BS_B=0;QUEST_SKIP=sky,clouds": before/after switches for this run (read at launch by builds with
#   ledger 284). Split over debug.sunderfall.env ... env6 here (a property holds 91 characters; a long value goes on
#   as KEY+=more); all cleared at the end.
# Records `adb logcat` VrApi (the source OVR Metrics shows: FPS=a/b, Stale, App/GPU ms, CPU/GPU levels) and the app's
# own lines (tag Blocksmith: perf, load, route, xr), once a second, tagged by leg. Writes DIR/raw.log, DIR/seconds.tsv,
# DIR/summary.txt. PASS = no second under 60 fps anywhere (menus and loading included) and under 2% of seconds below
# 70. Exit 0 pass, 1 fail, 2 setup problem (no headset, install failed).
set -uo pipefail
cd "$(dirname "$0")/.."
PKG=com.blocksmith.quest
ACT=$PKG/android.app.NativeActivity
APK=""; MIN=5; ROUTE=""; OUT=""; INSTALL=1; ENVS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --minutes) MIN="$2"; shift 2 ;;
    --route) ROUTE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --no-install) INSTALL=0; shift ;;
    --env) ENVS="$2"; shift 2 ;;
    -h|--help) sed -n 2,13p "$0"; exit 0 ;;
    *) APK="$1"; shift ;;
  esac
done
OUT=${OUT:-headset-gate/$(date +%Y%m%d-%H%M%S)}
mkdir -p "$OUT"
# adb: $ADB, else on PATH, else ~/ClaudeTools/quest/platform-tools/adb (where the Mac keeps it).
ADB=${ADB:-$(command -v adb || echo "$HOME/ClaudeTools/quest/platform-tools/adb")}
[[ -x "$ADB" ]] || { echo "headset_gate: adb not found (set ADB=/path/to/adb)"; exit 2; }
adb() { "$ADB" "$@"; }
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
  for p in env env2 env3 env4 env5 env6; do adb shell setprop debug.sunderfall.$p '""' >/dev/null 2>&1; done
  adb shell am broadcast -a com.oculus.vrpowermanager.automation_disable >/dev/null 2>&1
  [[ -n "${LOGPID:-}" ]] && kill "$LOGPID" 2>/dev/null
}
trap cleanup EXIT
if [[ -n "$APK" && "$INSTALL" == 1 ]]; then
  # Never over an app signed with another key: that install fails and only an uninstall (which wipes the saves) gets
  # past it. The new APK's certificate must match the installed one's, or nothing is installed.
  have=$(adb shell pm path $PKG | tr -d '\r' | sed -n 's/^package://p' | head -1)
  if [[ -n "$have" ]]; then
    adb pull "$have" "$OUT/installed.apk" >/dev/null || { echo "headset_gate: could not read the installed app to compare signers"; exit 2; }
    a=$(python3 "$(dirname "$0")/apk_signer.py" "$OUT/installed.apk"); b=$(python3 "$(dirname "$0")/apk_signer.py" "$APK")
    rm -f "$OUT/installed.apk"
    if [[ "$a" == unknown || "$a" != "$b" ]]; then
      echo "headset_gate: REFUSED: $APK is signed with another key than the installed app (installed $a, new $b)."
      echo "  Installing it would need an uninstall, which wipes the saves. Measure a build signed like the installed one."
      exit 2
    fi
  fi
  echo "headset_gate: installing $APK"
  adb install -r "$APK" | tail -1 | grep -q Success || { echo "headset_gate: install failed"; exit 2; }
fi
echo "headset_gate: app version $(adb shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r')"
adb shell am force-stop $PKG
sleep 2
adb shell setprop debug.sunderfall.route "${ROUTE:-\"\"}"
# (pairs packed into properties of at most 90 characters; a value too long is cut at commas into KEY+= pieces)
i=0
for chunk in $(python3 - "$ENVS" <<'PY'
import sys
pairs = []
for p in filter(None, sys.argv[1].split(";")):
    k, _, v = p.partition("=")
    parts, cur = [], ""
    for item in v.split(","):
        if cur and len(k) + len(cur) + len(item) + 4 > 88: parts.append(cur); cur = item
        else: cur = item if not cur else cur + "," + item
    parts.append(cur)
    pairs += [f"{k}={parts[0]}"] + [f"{k}+={q}" for q in parts[1:]]
props, cur = [], ""
for p in pairs:
    if cur and len(cur) + len(p) + 1 > 90: props.append(cur); cur = p
    else: cur = p if not cur else cur + ";" + p
if cur: props.append(cur)
print("\n".join(props))
PY
); do
  i=$((i + 1)); suf=$([[ $i == 1 ]] && echo "" || echo $i)
  (( i <= 6 )) || { echo "headset_gate: --env too long (6 properties)"; exit 2; }
  adb shell setprop debug.sunderfall.env$suf "'$chunk'"
done
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
