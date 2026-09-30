#!/usr/bin/env python3
"""Compares a bench.json against perf/baseline.json.

Writes a markdown table (metric, baseline, now, ratio) and exits 1 when a gated metric regressed past
its failure threshold. CI runners are noisy VMs, so only metrics that are stable there fail the build;
everything else is reported (and flagged when it moved more than 30 %).

Direction: most metrics are costs (lower is better); names listed in HIGHER_IS_BETTER are rates.
"""
import json, sys

HIGHER_IS_BETTER = ("per_s", "coverage", "realtime")
# Metric-name prefixes whose regressions fail CI, with the ratio that fails. Single-thread CPU work is
# stable enough on CI to gate; frame/GPU times on the virtualised GPU are reported only.
GATES = {
    "gen.chunk_ms_mean": 1.6,
    "mesh.chunk_ms_mean": 1.6,
    "mesh_lod1.chunk_ms_mean": 1.6,
    "save.chunk_ms": 2.0,
    "save.load_chunk_ms": 2.0,
    "edit.break_ms_mean": 2.0,
    "edit.place_ms_mean": 2.0,
    "flight16.coverage_min": 1.6,
    "flight16.resident_peak_mb": 1.4,
    "flight24.resident_peak_mb": 1.4,
}
IGNORE = ("total_s", "since_launch_s", "worlds_alive")


def worse_ratio(name, base, now):
    """>1 means worse."""
    if base == 0 and now == 0:
        return 1.0
    if any(h in name for h in HIGHER_IS_BETTER):
        return base / now if now > 0 else float("inf")
    return now / base if base > 0 else float("inf")


def main():
    cur_path, base_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    cur = json.load(open(cur_path))
    try:
        base = json.load(open(base_path))
    except (OSError, ValueError):
        base = {}
    rows, failed = [], []
    for k in sorted(cur):
        if k.startswith(IGNORE):
            continue
        v = cur[k]
        b = base.get(k)
        if b is None:
            rows.append(f"| {k} | – | {v:g} | new |")
            continue
        if k.endswith("_hash"):
            # Identity checks (e.g. generated terrain): report a change, never gate on it.
            rows.append(f"| {k} | {b:.0f} | {v:.0f} | {'same' if b == v else '⚠️ changed'} |")
            continue
        r = worse_ratio(k, b, v)
        flag = ""
        if r > 1.3:
            flag = " ⚠️ worse"
        elif r < 0.77:
            flag = " ✅ better"
        gate = GATES.get(k)
        # Tiny absolute values (sub-0.2 ms) are timer noise.
        noise = not any(h in k for h in HIGHER_IS_BETTER) and max(v, b) < 0.2 and k.endswith(("_ms", "_mean", "_p50", "_p95", "_max"))
        if gate and r > gate and not noise:
            failed.append(f"{k}: {b:g} -> {v:g} ({r:.2f}x worse, gate {gate}x)")
            flag = " ❌ regression"
        rows.append(f"| {k} | {b:g} | {v:g} | {r:.2f}x{flag} |")
    with open(out_path, "w") as f:
        f.write("| metric | baseline | now | worse by |\n|---|---|---|---|\n")
        f.write("\n".join(rows) + "\n")
        if failed:
            f.write("\n**Regressions past the CI gate:**\n\n" + "\n".join("- " + x for x in failed) + "\n")
    for x in failed:
        print(f"::error::perf regression {x}")
    print(f"compare: {len(rows)} metrics, {len(failed)} gated regressions (table in {out_path})")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
