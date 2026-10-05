#!/bin/bash
# Frontier Mac monitor (runs on Remington's Mac): watches the rolling GitHub pre-release `frontier-latest`, and when
# a new build appears downloads it, installs it to ~/Applications/Sable River/SableRiver.app, runs the --benchmark
# mode (writes ~/Library/Logs/Frontier/benchmark.json) and sends the numbers back to the repo branch
# `frontier-bench` (as bench/<commit>.json, via `gh` if logged in, else git over the user's existing credentials),
# where the Frontier session reads them.
#
#   bash frontier/tools/mac_monitor.sh install     # LaunchAgent: check every 30 min (and at login)
#   bash frontier/tools/mac_monitor.sh run         # check once now
#   bash frontier/tools/mac_monitor.sh uninstall
#
# The benchmark opens the game window for ~2 minutes; it runs only when the Mac has been idle for > 10 minutes
# (HIDIdleTime) and is on AC power, so it never interrupts work. FRONTIER_FORCE=1 skips those checks.
set -uo pipefail
REPO="remingtonangus-lang/blocksmith"
TAG="frontier-latest"
BASE="$HOME/Library/Application Support/FrontierMonitor"
APPDIR="$HOME/Applications/Sable River"
LOGDIR="$HOME/Library/Logs/Frontier"
PLIST="$HOME/Library/LaunchAgents/com.remingtonangus.frontier-monitor.plist"
mkdir -p "$BASE" "$APPDIR" "$LOGDIR"
log() { echo "$(date '+%F %T') $*" | tee -a "$LOGDIR/monitor.log"; }

cmd="${1:-run}"
if [ "$cmd" = "install" ]; then
  cp "$0" "$BASE/mac_monitor.sh"; chmod +x "$BASE/mac_monitor.sh"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.remingtonangus.frontier-monitor</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$BASE/mac_monitor.sh</string><string>run</string></array>
  <key>StartInterval</key><integer>1800</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$LOGDIR/monitor.out</string>
  <key>StandardErrorPath</key><string>$LOGDIR/monitor.err</string>
</dict></plist>
EOF
  launchctl unload "$PLIST" 2>/dev/null; launchctl load "$PLIST"
  log "installed LaunchAgent ($PLIST)"; exit 0
fi
if [ "$cmd" = "uninstall" ]; then
  launchctl unload "$PLIST" 2>/dev/null; rm -f "$PLIST"; log "uninstalled"; exit 0
fi

# ---- run: is there a new build?
remote=$(curl -fsSL "https://github.com/$REPO/releases/download/$TAG/BUILD_COMMIT.txt" 2>/dev/null | tr -d '[:space:]')
[ -n "$remote" ] || { log "no build published yet"; exit 0; }
last=$(cat "$BASE/last_benchmarked" 2>/dev/null || true)
[ "$remote" = "$last" ] && exit 0

if [ "${FRONTIER_FORCE:-0}" != "1" ]; then
  idle=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
  power=$(pmset -g batt | head -1)
  if [ "${idle:-0}" -lt 600 ] || ! echo "$power" | grep -q "AC Power"; then
    log "new build $remote waiting (idle ${idle}s, $power)"; exit 0
  fi
fi

log "new build $remote: downloading"
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/app.zip" "https://github.com/$REPO/releases/download/$TAG/SableRiver-mac-arm64.zip" || { log "download failed"; exit 1; }
rm -rf "$APPDIR/SableRiver.app"
ditto -x -k "$tmp/app.zip" "$APPDIR" && rm -rf "$tmp"
xattr -dr com.apple.quarantine "$APPDIR/SableRiver.app" 2>/dev/null || true
BIN="$APPDIR/SableRiver.app/Contents/MacOS/$(ls "$APPDIR/SableRiver.app/Contents/MacOS" | head -1)"
log "running benchmark ($BIN)"
rm -f "$LOGDIR/benchmark.json"
"$BIN" -- --benchmark --quality high --commit "$remote" --watchdog 900 > "$LOGDIR/benchmark_run.log" 2>&1
[ -f "$LOGDIR/benchmark.json" ] || { log "benchmark produced no json (see benchmark_run.log)"; exit 1; }
python3 - "$LOGDIR/benchmark.json" <<'EOF' >> "$LOGDIR/monitor.log" 2>/dev/null || true
import json, sys, platform, subprocess
p = sys.argv[1]; d = json.load(open(p))
d["machine"] = {"model": subprocess.run(["sysctl", "-n", "hw.model"], capture_output=True, text=True).stdout.strip(),
                "mem_gb": int(subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True, text=True).stdout) // 2**30,
                "macos": platform.mac_ver()[0]}
json.dump(d, open(p, "w"), indent=1)
o = d["overall"]; print("bench %.0f fps avg, %.0f 1%% low, p99 %.1f ms, rss %.0f MB" % (o["fps"], o["low1"], o["p99"], d["memory"]["rss_mb"]))
EOF
# ---- send it back
name="bench/${remote}.json"
sent=0
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  gh api "repos/$REPO/git/ref/heads/frontier-bench" >/dev/null 2>&1 || {
    main_sha=$(gh api "repos/$REPO/git/ref/heads/claude/frontier-game" -q .object.sha)
    gh api "repos/$REPO/git/refs" -f ref=refs/heads/frontier-bench -f sha="$main_sha" >/dev/null; }
  content=$(base64 < "$LOGDIR/benchmark.json" | tr -d '\n')
  gh api -X PUT "repos/$REPO/contents/$name" -f message="Mac benchmark for $remote" -f content="$content" -f branch=frontier-bench >/dev/null && sent=1
fi
if [ "$sent" = "0" ]; then
  W="$BASE/repo"
  if [ ! -d "$W/.git" ]; then git clone -q --depth 1 --no-checkout "https://github.com/$REPO.git" "$W" || true; fi
  if [ -d "$W/.git" ]; then
    (cd "$W" && (git fetch -q origin frontier-bench && git checkout -q -B frontier-bench FETCH_HEAD || git checkout -q --orphan frontier-bench) \
      && mkdir -p bench && cp "$LOGDIR/benchmark.json" "$name" && git add "$name" \
      && git -c user.name="frontier-monitor" -c user.email="monitor@localhost" commit -qm "Mac benchmark for $remote" \
      && git push -q origin frontier-bench) && sent=1
  fi
fi
log "benchmark for $remote $([ $sent = 1 ] && echo sent to branch frontier-bench || echo saved locally only)"
echo "$remote" > "$BASE/last_benchmarked"
