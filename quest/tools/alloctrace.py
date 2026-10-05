#!/usr/bin/env python3
# Symbolizes an allocation trace from quest/tools/alloccount.c (BS_ALLOC_TRACE) and prints the call sites that allocate
# the most: for each stack, the first frame in Blocksmith code (skipping the Swift runtime and libc), with counts.
#   python3 quest/tools/alloctrace.py /tmp/at/tick1000.trace [frames-to-show]
import sys, subprocess, collections
path = sys.argv[1]; show = int(sys.argv[2]) if len(sys.argv) > 2 else 3
lines = '--lines' in sys.argv
maps, traces = [], []
for l in open(path):
    if l.startswith('M '):
        p = l[2:].split()
        if len(p) >= 6 and 'x' in p[1]:
            a, b = (int(x, 16) for x in p[0].split('-'))
            maps.append((a, b, int(p[2], 16), p[5]))
    elif l.startswith('T'):
        traces.append([int(x, 16) for x in l.split()[1:]])
def locate(addr):
    for a, b, off, f in maps:
        if a <= addr < b: return f, addr - a + off
    return None, addr
addrs = sorted({x for t in traces for x in t})
byfile = collections.defaultdict(list)
for x in addrs:
    f, o = locate(x - 1)
    if f: byfile[f].append((x, o))
name = {}
where = {}
for f, lst in byfile.items():
    inp = '\n'.join(hex(o) for _, o in lst)
    out = subprocess.run(['llvm-symbolizer', '--obj=' + f, '--demangle', '--functions=linkage', '--no-inlines'], input=inp, capture_output=True, text=True).stdout
    blocks = [b for b in out.strip().split('\n\n')]
    for (x, _), b in zip(lst, blocks):
        fn = b.split('\n')[0]
        name[x] = fn
        loc = b.split('\n')[1] if '\n' in b else ''
        where[x] = loc.split('/')[-1]
fns = sorted(set(name.values()))
dem = dict(zip(fns, subprocess.run(['swift-demangle', '--simplified', '--compact'], input='\n'.join(fns), capture_output=True, text=True).stdout.split('\n')))
skip = ('swift_', 'malloc', 'Swift.', 'generic specialization', 'merged ', 'outlined', '__libc', 'Foundation', '_swift', 'specialized Swift.', 'specialized _')
c = collections.Counter()
for t in traces:
    names = [dem.get(name.get(x, '?'), '?') + ('@' + where[x] if lines and where.get(x) else '') for x in t]
    own = [n for n in names if not n.startswith('?') and not any(n.startswith(s) for s in skip) and 'libswift' not in n]
    c[' <- '.join(n[:110] for n in own[:show]) or ' <- '.join(n[:80] for n in names[:4])] += 1
print(f'{len(traces)} allocations')
for k, v in c.most_common(40): print(f'{v:5d}  {k}')
