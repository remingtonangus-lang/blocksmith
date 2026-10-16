#!/usr/bin/env python3
"""UI text overflow detector (docs/STORE_QUALITY.md objective 8). Reads --uilog JSON files (Sources/UILog.swift).
  tools/uioverflow.py snaps/ui/*.json [--out snaps/ui_overflow.md]
Per screen: text off screen, text running past the right edge of the panel it starts in, overlapping text runs, and
the smallest text height (px). Prints one line per screen and a total.
"""
import json, sys, os

def inside(px, py, r): return r[0] <= px <= r[0] + r[2] and r[1] <= py <= r[1] + r[3]

def check(path):
    d = json.load(open(path)); W, H = d["w"], d["h"]
    T = [t for t in d["texts"] if t["s"].strip()]
    R = [r for r in d["rects"] if r[2] * r[3] < 0.8 * W * H]
    issues = []
    for t in T:
        x, y, w, h, s = t["x"], t["y"], t["w"], t["h"], t["s"]
        if x < -0.5 or y < -0.5 or x + w > W + 0.5 or y + h > H + 0.5:
            issues.append(f"off screen: '{s[:40]}' at {x:.0f},{y:.0f} w {w:.0f}")
            continue
        if s.strip().isdigit(): continue      # stack counts overhang their slot's corner by design
        home = [r for r in R if inside(x + 1, y + 1, r) and r[3] > 2 * h]   # panels, not key caps
        if home:
            r = min(home, key=lambda r: r[2] * r[3])
            if x + w > r[0] + r[2] + 1 and r[2] > w * 0.3:
                issues.append(f"past its panel by {x + w - r[0] - r[2]:.0f} px: '{s[:40]}'")
    seen = set()
    for i, a in enumerate(T):
        for b in T[i + 1:]:
            if a["s"] == b["s"] or len(a["s"].strip()) <= 2 or len(b["s"].strip()) <= 2: continue   # glyph letters drawn inside hint lines
            ox = min(a["x"] + a["w"], b["x"] + b["w"]) - max(a["x"], b["x"])
            oy = min(a["y"] + a["h"], b["y"] + b["h"]) - max(a["y"], b["y"])
            if ox > 2 and oy > 2:
                k = (a["s"][:30], b["s"][:30])
                if k not in seen: seen.add(k); issues.append(f"overlap: '{a['s'][:30]}' / '{b['s'][:30]}'")
    minh = min((t["h"] for t in T), default=0)
    return W, H, len(T), minh, issues

def main():
    files = [a for a in sys.argv[1:] if a.endswith(".json")]
    out = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else None
    md, total = ["| screen | size | texts | min text px | issues |", "|---|---|---|---|---|"], 0
    details = []
    for f in sorted(files):
        W, H, n, minh, iss = check(f)
        name = os.path.basename(f)[:-5]; total += len(iss)
        print(f"{name}: {n} texts, min {minh:.0f} px, {len(iss)} issues")
        md.append(f"| {name} | {W:.0f}x{H:.0f} | {n} | {minh:.0f} | {len(iss)} |")
        details += [f"- {name}: {i}" for i in iss[:15]] + ([f"- {name}: ... {len(iss) - 15} more"] if len(iss) > 15 else [])
    print(f"uioverflow: {total} issues over {len(files)} screens")
    if out:
        open(out, "w").write("# UI text overflow (tools/uioverflow.py)\n\n" + "\n".join(md) + "\n\n## Issues\n\n" + ("\n".join(details) or "none") + "\n")
    return 0

if __name__ == "__main__":
    sys.exit(main())
