#!/usr/bin/env python3
# The headset gate's report (tools/headset_gate.sh): reads DIR/raw.log (adb logcat -v epoch, tags VrApi and
# Blocksmith) and writes DIR/seconds.tsv and DIR/summary.txt; prints the summary. Exit 0 PASS, 1 FAIL.
#   python3 tools/headset_gate.py DIR
import re, sys, os

d = sys.argv[1]
lines = open(os.path.join(d, "raw.log"), errors="replace").read().splitlines()
T = re.compile(r"^\s*(\d+\.\d+)\s")
leg = "launch"            # until the first world is handed over; then "play" (or the route player's legs)
routed = False
perf = ""                 # the app's latest perf line (every 5 s)
view = ""                 # latest view / active distance note
warp = "unknown"
rate = ""
rows = []
for l in lines:
    m = T.match(l)
    if not m:
        continue
    t = float(m.group(1))
    if " Blocksmith" in l or "Blocksmith:" in l:
        msg = l.split(": ", 1)[-1]
        if msg.startswith("route: leg "):
            leg = msg[len("route: leg "):].split()[0]; routed = True
        elif msg.startswith("adopt:") and not routed and leg == "launch":
            leg = "play"
        elif msg.startswith("xr: space warp"):
            warp = msg
        elif msg.startswith("perf: ") and " fps (display" in msg:
            perf = msg
            r = re.search(r"display (\d+) Hz", msg)
            if r: rate = r.group(1)
        elif "distance" in msg and msg.startswith("perf:"):
            view = msg
        continue
    if "VrApi" not in l or "FPS=" not in l:
        continue
    f = re.search(r"FPS=(\d+)/(\d+)", l)
    if not f:
        continue
    def num(k):
        r = re.search(k + r"=([\d.]+)", l)
        return float(r.group(1)) if r else -1
    eye = re.search(r"eye resolution (\d+)%", perf)
    vd = re.search(r"\| view (\d+)", perf) or (re.search(r"(?:view|active) distance (\d+)", view) if view else None)
    rows.append(dict(t=t, leg=leg, fps=int(f.group(1)), target=int(f.group(2)), stale=num("Stale"), app=num("App"),
                     gpuraw=num("GPU%"), tear=num("Tear"),
                     eye=eye.group(1) if eye else "", vd=vd.group(1) if vd else "", rate=rate))

with open(os.path.join(d, "seconds.tsv"), "w") as o:
    o.write("t\tleg\tfps\ttarget\tstale\tapp_ms\tgpu_pct\teye_pct\tview\n")
    for r in rows:
        o.write(f"{r['t']:.0f}\t{r['leg']}\t{r['fps']}\t{r['target']}\t{r['stale']:.0f}\t{r['app']:.2f}\t{r['gpuraw']:.2f}\t{r['eye']}\t{r['vd']}\n")

def pct(v, p):
    v = sorted(v)
    return v[min(len(v) - 1, int(p / 100 * len(v)))] if v else 0

out = []
def stats(name, rs):
    f = [r["fps"] for r in rs]
    if not f:
        return
    out.append(f"{name:<10} {len(f):>5} s  min {min(f):>3}  p1 {pct(f,1):>3}  p5 {pct(f,5):>3}  median {pct(f,50):>3}  "
               f"under 70: {sum(x < 70 for x in f):>4}  under 60: {sum(x < 60 for x in f):>4}  "
               f"stale {sum(max(0, r['stale']) for r in rs):>5.0f}  worst app ms {max(r['app'] for r in rs):.1f}")

legs = []
for r in rows:
    if r["leg"] not in legs: legs.append(r["leg"])
out.append(f"headset gate: {len(rows)} seconds of VrApi, display {rate or '?'} Hz, {warp}")
for g in legs:
    stats(g, [r for r in rows if r["leg"] == g])
stats("ALL", rows)
f = [r["fps"] for r in rows]
under60 = sum(x < 60 for x in f); under70 = sum(x < 70 for x in f)
ok = bool(f) and under60 == 0 and under70 < 0.02 * len(f)
bad = [r for r in rows if r["fps"] < 70]
if bad:
    out.append("seconds under 70 (t, leg, fps, stale, app ms, eye %, view):")
    for r in bad[:80]:
        out.append(f"  {r['t']:.0f} {r['leg']} {r['fps']} stale {r['stale']:.0f} app {r['app']:.1f} eye {r['eye'] or '?'} view {r['vd'] or '?'}")
    if len(bad) > 80: out.append(f"  ... {len(bad) - 80} more in seconds.tsv")
out.append(f"headset gate: {'PASS' if ok else 'FAIL'} ({under60} s under 60, {under70} s under 70 of {len(f)}; pass = 0 under 60 and under 2% under 70)")
txt = "\n".join(out)
open(os.path.join(d, "summary.txt"), "w").write(txt + "\n")
print(txt)
sys.exit(0 if ok else 1)
