#!/usr/bin/env python3
"""Lists every literal name the code looks up with Items.id("...") / Blocks.id("...") as `item|block NAME file:line`, for
`Blocksmith --namecheck FILE` (an unknown name is a fatalError the first time that line runs, often in a rare event).
A literal the same file also tests with has("NAME") is optional content and is left out. Stdlib only."""
import re, os, sys
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Sources')
pat = re.compile(r'\b(Items|Blocks)\.id\("([^"\\]+)"\)')
seen = set()
for fn in sorted(os.listdir(root)):
    if not fn.endswith('.swift'): continue
    text = open(os.path.join(root, fn), encoding='utf-8', errors='replace').read()
    for ln, line in enumerate(text.split('\n'), 1):
        if line.lstrip().startswith('//'): continue
        for m in pat.finditer(line):
            kind = 'item' if m.group(1) == 'Items' else 'block'
            name = m.group(2)
            if f'has("{name}")' in text: continue
            if (kind, name) in seen: continue
            seen.add((kind, name))
            print(f'{kind} {name} {fn}:{ln}')
print(f'namecheck.py: {len(seen)} names', file=sys.stderr)
