#!/usr/bin/env python3
# The headset gate's report (tools/headset_gate.sh): reads DIR/raw.log (adb logcat -v epoch, tags VrApi and
# Blocksmith) and writes DIR/seconds.tsv and DIR/summary.txt; prints the summary. Exit 0 PASS, 1 FAIL.
#   python3 tools/headset_gate.py DIR
#   python3 tools/headset_gate.py --selftest       (the unit checks: two processes, windows, spots)
#
# Only the game's own frames count. logcat carries a VrApi line a second from every VR process (the system shell,
# com.oculus.vrshell, too); the game's are those from a process id that also wrote the game's own lines (tag
# Blocksmith), which follows a restart. The others are summed on one line marked "not counted".
# Every second is in a phase: "launch" (process up, nothing loading yet), "loading" (from a "load:" or "world:
# switching" line to the world handed over, "adopt:"), "play". With the route player, its legs ("route: leg NAME")
# split play further; a table gives one row per leg (and per held spot of --route spots).
# Not in the totals or the verdict (Fable, Nov 17, from the first real runs): the "launch" seconds (process up, the
# system's splash, before the app draws its menu) and the "spotworld" leg (making the spot world); they get a line of
# their own.
import re, sys, os

T = re.compile(r"^\s*(\d+\.\d+)\s+(\d+)\s+(\d+)\s+\w\s+(\S+?)\s*:\s?(.*)$")


def parse(lines):
    game_pids = set()
    for l in lines:
        m = T.match(l)
        if m and m.group(4) == "Blocksmith":
            game_pids.add(m.group(2))
    leg, phase, routed = "launch", "launch", False
    perf, view, warp, rate = "", "", "unknown", ""
    rows, other = [], []
    for l in lines:
        m = T.match(l)
        if not m:
            continue
        t, pid, tag, msg = float(m.group(1)), m.group(2), m.group(4), m.group(5)
        if tag == "Blocksmith":
            if msg.startswith("route: leg "):
                leg = msg[len("route: leg "):].split()[0]; routed = True
            elif msg.startswith("load:") or msg.startswith("world: switching"):
                if phase != "loading" and not msg.startswith("load: first ticks"):
                    phase = "loading"
            elif msg.startswith("adopt:"):
                phase = "play"
                if not routed and leg == "launch": leg = "play"
            elif msg.startswith("xr: space warp"):
                warp = msg
            elif msg.startswith("perf: ") and " fps (display" in msg:
                perf = msg
                r = re.search(r"display (\d+) Hz", msg)
                if r: rate = r.group(1)
            elif "distance" in msg and msg.startswith("perf:"):
                view = msg
            continue
        if tag != "VrApi" or "FPS=" not in msg:
            continue
        f = re.search(r"FPS=(\d+)/(\d+)", msg)
        if not f:
            continue
        def num(k, src=msg):
            r = re.search(k + r"=([\d.]+)", src)
            return float(r.group(1)) if r else -1
        if pid not in game_pids:
            other.append(int(f.group(1)))
            continue
        eye = re.search(r"eye resolution (\d+)%", perf)
        vd = re.search(r"\| view (\d+)", perf) or (re.search(r"(?:view|active) distance (\d+)", view) if view else None)
        pg = re.search(r"\| gpu ([\d.]+) ms \|", perf); pcpu = re.search(r"\| cpu ([\d.]+) ms \(", perf)
        pq = re.search(r"quads (\d+)", perf)
        mhz = re.search(r"/(\d+)MHz", msg)
        rows.append(dict(t=t, leg=leg, phase=phase, fps=int(f.group(1)), target=int(f.group(2)), stale=num("Stale"),
                         app=num("App"), gpuraw=num("GPU%"), mhz=int(mhz.group(1)) if mhz else -1,
                         pgpu=float(pg.group(1)) if pg else -1, pcpu=float(pcpu.group(1)) if pcpu else -1,
                         quads=int(pq.group(1)) if pq else -1, eye=eye.group(1) if eye else "", vd=vd.group(1) if vd else ""))
    return rows, other, dict(warp=warp, rate=rate, pids=sorted(game_pids))


def pct(v, p):
    v = sorted(v)
    return v[min(len(v) - 1, int(p / 100 * len(v)))] if v else 0


GPU_MAX_MHZ = 690          # Quest 3: 285 ... 690 MHz


UNCOUNTED_LEGS = ("launch", "spotworld", "combatworld")


def uncounted_leg(g):
    # (making the route's own worlds, and a combat leg's staging: a world loaded on the frame thread, ships built)
    return g in UNCOUNTED_LEGS or g.endswith("-stage")


def counted(r):
    return r["phase"] != "launch" and not uncounted_leg(r["leg"])


def report(rows, other, info):
    out = []
    every = rows
    aside = [r for r in rows if not counted(r)]
    rows = [r for r in rows if counted(r)]
    def stats(name, rs):
        f = [r["fps"] for r in rs]
        if not f:
            return
        out.append(f"{name:<14} {len(f):>5} s  min {min(f):>3}  p1 {pct(f,1):>3}  p5 {pct(f,5):>3}  median {pct(f,50):>3}  "
                   f"under 70: {sum(x < 70 for x in f):>4}  under 60: {sum(x < 60 for x in f):>4}  "
                   f"stale {sum(max(0, r['stale']) for r in rs):>5.0f}  worst app ms {max(r['app'] for r in rs):.1f}")
    out.append(f"headset gate: {len(rows)} seconds of the game's VrApi (pid {', '.join(info['pids']) or '?'}), display {info['rate'] or '?'} Hz, {info['warp']}")
    if other:
        out.append(f"(not counted: {len(other)} VrApi lines from other processes, the system shell; min {min(other)}, median {pct(other, 50)})")
    stats("not counted", aside)
    if aside:
        out.append("  (launch, spotworld/combatworld and -stage legs: the system splash, making the route's worlds, staging a fight; not in the totals)")
    for ph in ("loading", "play"):
        stats(ph, [r for r in rows if r["phase"] == ph])
    load = [r for r in rows if r["phase"] == "loading" and r["fps"] < r["target"]]
    if load:
        out.append("loading-screen seconds that missed frames (the loading scene must hold the display rate itself):")
        for r in load[:40]:
            out.append(f"  {r['t']:.0f} {r['leg']} {r['fps']}/{r['target']} stale {r['stale']:.0f} app {r['app']:.1f} ms")
    legs = []
    for r in every:
        if r["leg"] not in legs: legs.append(r["leg"])
    if len(legs) > 1 or (legs and legs[0] not in ("launch", "play")):
        out.append("legs (* not counted): name | s | fps min/median | s under 70 / 60 | gpu ms median (app perf) | cpu ms median | quads median | eye % | view | gpu MHz (of 690) | gpu busy %")
        for g in legs:
            rs = [r for r in every if r["leg"] == g]
            f = [r["fps"] for r in rs]
            def med(k):
                v = [r[k] for r in rs if r[k] >= 0]
                return pct(v, 50) if v else None
            gp, cp, q, mz, busy = med("pgpu"), med("pcpu"), med("quads"), med("mhz"), med("gpuraw")
            out.append(f"  {g + ('' if not uncounted_leg(g) else ' *'):<20} | {len(f):>4} | {min(f):>3}/{pct(f,50):>3} | {sum(x < 70 for x in f):>3} / {sum(x < 60 for x in f):>3} | "
                       f"{'?' if gp is None else f'{gp:.2f}'} | {'?' if cp is None else f'{cp:.2f}'} | {'?' if q is None else q} | "
                       f"{rs[-1]['eye'] or '?'} | {rs[-1]['vd'] or '?'} | {'?' if mz is None else f'{mz} ({mz * 100 // GPU_MAX_MHZ}%)'} | "
                       f"{'?' if busy is None else f'{busy * 100:.0f}'}")
    f = [r["fps"] for r in rows]
    under60 = sum(x < 60 for x in f); under70 = sum(x < 70 for x in f)
    ok = bool(f) and under60 == 0 and under70 < 0.02 * len(f)
    bad = [r for r in rows if r["fps"] < 70]
    if bad:
        out.append("seconds under 70 (t, phase, leg, fps, stale, app ms, eye %, view):")
        for r in bad[:80]:
            out.append(f"  {r['t']:.0f} {r['phase']} {r['leg']} {r['fps']} stale {r['stale']:.0f} app {r['app']:.1f} eye {r['eye'] or '?'} view {r['vd'] or '?'}")
        if len(bad) > 80: out.append(f"  ... {len(bad) - 80} more in seconds.tsv")
    out.append(f"headset gate: {'PASS' if ok else 'FAIL'} ({under60} s under 60, {under70} s under 70 of {len(f)}; pass = 0 under 60 and under 2% under 70)")
    return "\n".join(out), ok


def selftest():
    log = """\
1731849999.500  4000  4020 I VrApi   : FPS=30/72,Stale=0,App=5.00ms,GPU%=0.10
1731849999.900  4000  4010 I Blocksmith: route: leg spotworld
1731849999.950  4000  4020 I VrApi   : FPS=45/72,Stale=0,App=5.00ms,GPU%=0.10
1731849999.990  4000  4010 I Blocksmith: route: leg plains
1731850000.100  4000  4010 I Blocksmith: xr: space warp off (P426): extension not requested
1731850000.200  4000  4010 I Blocksmith: load: Starting (0.0 s)
1731850000.500  4000  4020 I VrApi   : FPS=72/72,Stale=0,CPU4/GPU=4/4,1785/492MHz,App=5.10ms,GPU%=0.40
1731850000.600  3000  3010 I VrApi   : FPS=40/72,Stale=0,App=5.00ms,GPU%=0.20
1731850001.500  4000  4020 I VrApi   : FPS=55/72,Stale=17,App=14.10ms,GPU%=0.99
1731850001.600  3000  3010 I VrApi   : FPS=50/72,Stale=0,App=5.00ms,GPU%=0.20
1731850002.000  4000  4010 I Blocksmith: adopt: total 30.1 ms
1731850003.000  4000  4010 I Blocksmith: perf: 71.0 fps (display 72 Hz), missed 3 | cpu 7.10 ms (tick 2.00, record 3.00) | gpu 11.20 ms | sections 9, draws 5, quads 500000, cull 0.1 ms | view 12 | eye resolution 90%
1731850003.500  4000  4020 I VrApi   : FPS=72/72,Stale=0,CPU4/GPU=4/4,1785/545MHz,App=12.00ms,GPU%=0.95
1731850004.000  4000  4010 I Blocksmith: route: leg spot-jungle
1731850004.500  4000  4020 I VrApi   : FPS=68/72,Stale=4,CPU4/GPU=4/4,1785/545MHz,App=13.00ms,GPU%=0.97
1731850005.500  5000  5020 I VrApi   : FPS=72/72,Stale=0,App=9.00ms,GPU%=0.70
1731850005.600  5000  5010 I Blocksmith: load: Starting (0.0 s)
"""
    rows, other, info = parse(log.splitlines())
    fails = []
    def check(c, what):
        if not c: fails.append(what)
    check(len(rows) == 7, f"the game's seconds only (two pids + a restart): {len(rows)} rows, want 7")
    check(rows[0]["phase"] == "launch" and rows[1]["leg"] == "spotworld", f"launch and spotworld rows: {rows[:2]}")
    rows = rows[2:]
    check(sorted(other) == [40, 50], f"the shell's lines kept apart: {other}")
    check(info["pids"] == ["4000", "5000"], f"game pids followed through a restart: {info['pids']}")
    check([r["phase"] for r in rows[:3]] == ["loading", "loading", "play"], f"phases: {[r['phase'] for r in rows[:3]]}")
    check(rows[3]["leg"] == "spot-jungle" and rows[3]["pgpu"] == 11.2 and rows[3]["pcpu"] == 7.1 and rows[3]["quads"] == 500000
          and rows[3]["vd"] == "12" and rows[3]["eye"] == "90" and rows[3]["mhz"] == 545, f"spot row fields: {rows[3]}")
    txt, ok = report(rows, other, info)
    check("of 5;" in txt, "verdict leaves out launch and spotworld")
    txt, ok = report(parse(log.splitlines())[0], other, info)
    check("of 5;" in txt and "not counted       2 s" in txt.replace("not counted        ", "not counted       "), f"launch + spotworld counted apart:\n{txt}")
    check(not ok and "1 s under 60" in txt, "verdict counts the game's 55 only")
    check("loading-screen seconds" in txt and "55/72" in txt, "loading-screen misses listed")
    check("spot-jungle" in txt and "545 (78%)" in txt, "leg table with gpu MHz")
    print("\n".join(["headset_gate selftest: " + ("ok" if not fails else "FAILED")] + ["  " + f for f in fails]))
    return 0 if not fails else 1


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(selftest())
    d = sys.argv[1]
    rows, other, info = parse(open(os.path.join(d, "raw.log"), errors="replace").read().splitlines())
    with open(os.path.join(d, "seconds.tsv"), "w") as o:
        o.write("t\tphase\tleg\tfps\ttarget\tstale\tapp_ms\tgpu_busy\tgpu_mhz\tperf_gpu_ms\tperf_cpu_ms\tquads\teye_pct\tview\n")
        for r in rows:
            o.write(f"{r['t']:.0f}\t{r['phase']}\t{r['leg']}\t{r['fps']}\t{r['target']}\t{r['stale']:.0f}\t{r['app']:.2f}\t{r['gpuraw']:.2f}\t"
                    f"{r['mhz']}\t{r['pgpu']:.2f}\t{r['pcpu']:.2f}\t{r['quads']}\t{r['eye']}\t{r['vd']}\n")
    txt, ok = report(rows, other, info)
    open(os.path.join(d, "summary.txt"), "w").write(txt + "\n")
    print(txt)
    sys.exit(0 if ok else 1)
