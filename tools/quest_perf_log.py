#!/usr/bin/env python3
"""Summarise the Quest `perf:` lines (one every 5 s) of a device log, split by world load / render distance.
   python3 tools/quest_perf_log.py blocksmith.log [more.log ...] [--windows]
--windows also lists every window with a frame over 25 ms (time, worst, its cpu/tick/record/gpu split, chunks, jobs, mobs)."""
import re, sys, statistics as st

PAT = re.compile(r'perf: ([\d.]+) fps \(display (\d+) Hz\), missed (\d+), worst ([\d.]+) ms \(cpu ([\d.]+): tick ([\d.]+) incl\. world ([\d.]+), record ([\d.]+); gpu ([\d.]+)\) \| cpu ([\d.]+) ms \(tick ([\d.]+), record ([\d.]+)\) \| gpu ([\d.]+) ms \| sections (\d+), draws (\d+), quads (\d+), cull ([\d.]+) ms \| chunks (\d+), jobs (\d+), mobs (\d+) \| mesh slabs (\d+) MB, resident (\d+) MB')
KEYS = "fps hz missed worst wcpu wtick wworld wrec wgpu cpu tick rec gpu sec draws quads cull chunks jobs mobs slabs res".split()


def pct(v, p):
    v = sorted(v)
    return v[min(len(v) - 1, int(p * (len(v) - 1) + 0.5))]


def cause(d):
    w = d['worst']
    if d['wtick'] > 0.5 * w: return 'tick'
    if d['wgpu'] > 0.5 * w: return 'gpu'
    if d['wrec'] > 0.5 * w: return 'record'
    if d['wcpu'] < 0.5 * w and d['wgpu'] < 0.5 * w: return 'neither (wait/compositor)'
    return 'cpu other'


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    windows = '--windows' in sys.argv
    allsegs = []
    for f in args:
        rd, seg, segs, n_line = None, [], [], 0
        for line in open(f, errors='replace'):
            n_line += 1
            m = re.search(r'render distance (?:lowered to )?(\d+)', line)
            if m:
                if seg: segs.append((rd, seg))
                rd, seg = int(m.group(1)), []
                continue
            if 'android: paused' in line and seg: seg[-1]['pause_after'] = True
            m = PAT.search(line)
            if m:
                d = dict(zip(KEYS, map(float, m.groups()))); d['line'] = n_line
                t = re.search(r'slowest tick ([\\d.]+) ms: (.+)$', line)
                if t: d['stage'] = f'slowest tick {t.group(1)} ms: {t.group(2)}'
                seg.append(d)
        if seg: segs.append((rd, seg))
        allsegs += segs
    # One row per render distance (the guard's step-downs and menu changes are logged; windows merge by distance).
    groups = {}
    for rd, s in allsegs: groups.setdefault(rd, []).extend(s)
    print("| rd | minutes | fps p50 / p10 | missed/min | windows with a >25 ms frame /min | cpu ms p50/p90 | tick p50 | record p50 | gpu ms p50/p90 | sections p50 | quads p50 | chunks p50 | mobs p50/max | slabs MB | resident MB max | >25 ms cause |")
    print("|" + "---|" * 16)
    for rd in sorted(groups, key=lambda x: -1 if x is None else x):
        s = groups[rd]; n = len(s); mins = n * 5 / 60
        g = lambda k, p: pct([d[k] for d in s], p)
        c = {}
        for d in s:
            if d['worst'] > 25: c[cause(d)] = c.get(cause(d), 0) + 1
        hit = sum(d['worst'] > 25 for d in s)
        print(f"| {rd} | {mins:.1f} | {g('fps', .5):.1f} / {g('fps', .1):.1f} | {sum(d['missed'] for d in s) / mins:.0f} | {hit / mins:.1f} | {g('cpu', .5):.1f}/{g('cpu', .9):.1f} | {g('tick', .5):.1f} | {g('rec', .5):.1f} | {g('gpu', .5):.1f}/{g('gpu', .9):.1f} | {g('sec', .5):.0f} | {g('quads', .5) / 1000:.0f}k | {g('chunks', .5):.0f} | {g('mobs', .5):.0f}/{g('mobs', 1):.0f} | {g('slabs', 1):.0f} | {g('res', 1):.0f} | {', '.join(f'{k} {v}' for k, v in c.items())} |")
        if windows:
            for d in s:
                if d['worst'] > 25:
                    print(f"     L{d['line']} fps {d['fps']:.0f} missed {d['missed']:.0f} worst {d['worst']:.0f} (cpu {d['wcpu']:.0f} tick {d['wtick']:.0f} world {d['wworld']:.0f} rec {d['wrec']:.0f} gpu {d['wgpu']:.0f}) avg cpu {d['cpu']:.1f} gpu {d['gpu']:.1f} sec {d['sec']:.0f} chunks {d['chunks']:.0f} jobs {d['jobs']:.0f} mobs {d['mobs']:.0f}{' ' + d['stage'] if d.get('stage') else ''}{' [pause next]' if d.get('pause_after') else ''}")

main()
