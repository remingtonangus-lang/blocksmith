#!/bin/bash
# Builds a blind-critic evidence pack (see design/CRITIC.md): screenshots + bot/bench results + a factual feature
# inventory computed from code/data. Usage: bash frontier/tools/critic_pack.sh OUTDIR [SHOTS_DIR...]
set -uo pipefail
OUT="${1:?outdir}"; shift
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$OUT"
for d in "$@"; do cp "$d"/*.png "$OUT"/ 2>/dev/null || true; done
# bots + bench (local run results if present, else CI snaps)
[ -f "$HOME/.local/share/Frontier/bot_report.json" ] && python3 - "$HOME/.local/share/Frontier/bot_report.json" > "$OUT/bots.txt" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
for b in r.get("bots",[]):
    print("%-9s %s  failures=%s" % (b["bot"], "PASS" if b["ok"] else "FAIL", b.get("failures")))
    for k in ("distance","stuck_events","fall_events","frame_spikes","enemies","engaged","used_cover","killed","player_hits_taken","pelt_quality","population","completed","npcs","npc_minutes"):
        if k in b: print("    %s: %s" % (k, b[k]))
PY
for f in /tmp/cisnaps/benchmark.json "$HOME/.local/share/Frontier/benchmark.json"; do
  [ -f "$f" ] && python3 - "$f" > "$OUT/bench.txt" <<'PY' && break
import json,sys
d=json.load(open(sys.argv[1]))
print("hardware:", d.get("adapter"), d.get("driver"), "quality", d.get("quality"), "res", d.get("resolution"), "render_scale", d.get("render_scale"))
for s in d["segments"]: print("%-18s avg %.1f ms (%.0f fps) p95 %.1f p99 %.1f 1%%low %.0f fps spikes>100ms %d" % (s["name"], s["avg"], s["fps"], s["p95"], s["p99"], s["low1"], s["spikes_over_100ms"]))
o=d["overall"]; print("overall avg %.1f ms (%.0f fps) 1%%low %.0f p99 %.1f; memory %s" % (o["avg"], o["fps"], o["low1"], o["p99"], d["memory"]))
PY
done
# factual inventory
python3 - "$ROOT" > "$OUT/features.txt" <<'PY'
import json, os, re, sys, glob
root = sys.argv[1]
def count(pattern, path):
    return len(re.findall(pattern, open(os.path.join(root, path)).read(), re.M))
w = json.load(open(os.path.join(root, "data/world/features.json")))
print("world: %.0f km2, towns %d, points of interest %d, roads %d, rivers %d, railroad yes" % ((w["size_m"]/1000)**2, len(w["towns"]), len(w["pois"]), len(w["roads"]), len(w["rivers"])))
print("terrain material layers:", len(json.load(open(os.path.join(root, "assets/ext/packed/packed.json")))["terrain_layers"]) if os.path.exists(os.path.join(root,"assets/ext/packed/packed.json")) else "?")
print("tree/shrub species:", count(r'^\t"\w+": \{"height"', "src/world/tree_gen.gd"))
print("scatter models (CC0 photogrammetry):", count(r'^\t"\w+": \{"density"', "src/world/scatter.gd"))
print("firearms:", count(r'^\t"\w+": \{"name"', "src/combat/weapons.gd"))
print("wildlife species:", count(r'^\t"\w+": \{"name"', "src/actors/animal.gd"))
print("missions:", len(re.findall(r'"res://src/missions/ch\d+/', open(os.path.join(root, "src/missions/mission_director.gd")).read())))
lines = sum(len(json.load(open(f)).get("lines", [])) for f in glob.glob(os.path.join(root, "design/dialogue/*.json")))
barks = sum(len(json.load(open(f)).get("barks", [])) for f in glob.glob(os.path.join(root, "design/dialogue/*.json")))
print("ambient barks:", barks)
print("dialogue lines written:", lines)
for name, path, alt in (("character models", "assets/ext/characters", "assets/characters_out"), ("animal models", "assets/ext/animals", "assets/animals_out"), ("audio files", "assets/ext/audio", ""), ("weapon models", "assets/ext/weapons", "assets/weapons_out")):
    p = os.path.join(root, path)
    if not os.path.isdir(p) and alt:
        p = os.path.join(root, alt)
    n = sum(len(f) for _, _, f in os.walk(p)) if os.path.isdir(p) else 0
    print("%s: %d files" % (name, n))
sysf = {"shops": "src/ui/shop.gd", "roadside encounters": "src/ai/encounters.gd", "bounty boards": "src/ai/bounties.gd",
        "hold-ups/robbery": "src/systems/robbery.gd", "camp": "src/ai/camp.gd", "poker": "src/minigames/poker.gd",
        "horse riding/care": "src/actors/horse.gd", "save/load": "src/core/world_state.gd", "fishing": "src/systems/fishing.gd"}
print("systems present:", ", ".join(k for k, v in sysf.items() if os.path.exists(os.path.join(root, v))))
print("systems absent:", ", ".join(k for k, v in sysf.items() if not os.path.exists(os.path.join(root, v))) or "-")
print("bots/oracles:", ", ".join(sorted(set(re.findall(r'"(\w+)"', re.search(r'\["road".*?\]', open(os.path.join(root, "src/tests/bot_runner.gd")).read()).group(0))))))
PY
ls "$OUT" | head -40
