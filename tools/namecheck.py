#!/usr/bin/env python3
"""Two name checks. Stdlib only.

`namecheck.py` (no flag): lists every literal name the code looks up with Items.id("...") / Blocks.id("...") as
`item|block NAME file:line`, for `Blocksmith --namecheck FILE` (an unknown name is a fatalError the first time that line
runs, often in a rare event). A literal the same file also tests with has("NAME") is optional content and is left out.

`namecheck.py --coined [--dump FILE]`: the public-repo naming rule. Fails (exit 1) when a player-facing string uses a term
from tools/coined-terms.txt (the reference game's coined words; renames listed in docs/status/ip-renames.md). Scans every
string literal in Sources/ and quest/src/ (internal keys such as "creeper" or "nether_bricks" are exempt, as are test and
harness files and lines marked `namecheck:ok`), plus a runtime dump of every registered display name when --dump is given:
    ./build/Blocksmith.app/Contents/MacOS/Blocksmith --snapshot /tmp/n.png --rd 2 --questbugs --only pm9d --namedump /tmp/names.txt
    python3 tools/namecheck.py --coined --dump /tmp/names.txt
`--docs` additionally lists (without failing) hits in README.md and the store/marketing docs.
"""
import re, os, sys

here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.normpath(os.path.join(here, '..'))
root = os.path.join(repo, 'Sources')


def lookups():
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


def terms():
    out = []
    for raw in open(os.path.join(here, 'coined-terms.txt'), encoding='utf-8'):
        t = raw.strip()
        if not t or t.startswith('#'): continue
        if t.startswith('*'):
            out.append((t[1:], re.compile(r'\b' + re.escape(t[1:]), re.I)))
        else:
            out.append((t, re.compile(r'\b' + re.escape(t) + r'\b')))
    return out


# Files nobody reads in-game: checks that list the banned words, harness code, audits.
EXEMPT = re.compile(r'(Tests?|Check|Audit|Bench|Matrix)\.swift$|^(main|PadTest|ShipTest|StructScan|AgentRun|AgentBots|Agent|Playthrough)\.swift$')
KEYLIKE = re.compile(r'[a-z0-9_:./\-#%@\[\]=,]*')
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')


def strip_interp(s):
    # Drops Swift interpolations \( ... ) (nested parens included) so "redstone_wire[\\(p)]" reads as a key.
    out, i = [], 0
    while i < len(s):
        if s.startswith('\\(', i):
            depth, i = 1, i + 2
            while i < len(s) and depth:
                depth += {'(': 1, ')': -1}.get(s[i], 0); i += 1
            continue
        out.append(s[i]); i += 1
    return ''.join(out)


def scan_sources(tl):
    hits = []
    for base in ('Sources', os.path.join('quest', 'src')):
        for dp, _, fns in os.walk(os.path.join(repo, base)):
            for fn in sorted(fns):
                if not fn.endswith('.swift') or EXEMPT.search(fn): continue
                path = os.path.join(dp, fn)
                for ln, line in enumerate(open(path, encoding='utf-8', errors='replace'), 1):
                    s = line.lstrip()
                    if s.startswith('//') or 'namecheck:ok' in line: continue
                    code = line.split(' // ')[0]
                    for m in LITERAL.finditer(code):
                        lit = m.group(1)
                        if KEYLIKE.fullmatch(strip_interp(lit)): continue
                        for t, r in tl:
                            if r.search(lit):
                                hits.append(f'{os.path.relpath(path, repo)}:{ln}: "{lit[:80]}" ({t})')
    return hits


def scan_lines(path, tl):
    hits = []
    for ln, line in enumerate(open(path, encoding='utf-8', errors='replace'), 1):
        for t, r in tl:
            if r.search(line):
                hits.append(f'{os.path.relpath(path, repo)}:{ln}: {line.strip()[:100]} ({t})')
    return hits


def coined(args):
    tl = terms()
    hits = scan_sources(tl)
    if '--dump' in args:
        dump = args[args.index('--dump') + 1]
        hits += scan_lines(dump, tl)
    for h in hits: print('coined:', h)
    if '--docs' in args:
        docs = [os.path.join(repo, 'README.md'), os.path.join(repo, 'docs', 'STORE_QUALITY.md'),
                os.path.join(repo, 'docs', 'status', 'store-readiness.md')]
        store = os.path.join(repo, 'quest', 'store')
        if os.path.isdir(store):
            docs += [os.path.join(store, f) for f in sorted(os.listdir(store)) if f.endswith(('.md', '.txt'))]
        n = 0
        for d in docs:
            if os.path.exists(d):
                for h in scan_lines(d, tl): print('docs (not failing):', h); n += 1
        print(f'namecheck.py --docs: {n} doc lines use coined terms (history docs are left as they are)', file=sys.stderr)
    print(f'namecheck.py --coined: {len(tl)} terms, {len(hits)} player-facing hits', file=sys.stderr)
    return 1 if hits else 0


if __name__ == '__main__':
    if '--coined' in sys.argv:
        sys.exit(coined(sys.argv))
    lookups()
