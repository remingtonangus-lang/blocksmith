#!/usr/bin/env python3
"""Aggregates snaps/imagecheck.log (written by the renderer for every snapshot) into snaps/imagecheck.md and
flags: missing textures (magenta checker), black / blank frames, duplicate frames from different views, flicker
(z-fighting). Night, cave, deep-dark, underwater and menu shots are allowed to be dark. Stdlib only.
Exit 1 with --strict when anything is flagged."""
import re, sys, collections
path = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith('--') else 'snaps/imagecheck.log'
rows = {}
for line in open(path, errors='replace'):
    m = re.match(r'imagecheck (\S+) (.*)', line.strip())
    if not m: continue
    kv = dict(p.split('=') for p in m.group(2).split())
    rows[m.group(1)] = kv          # the last render of a name wins
dark_ok = re.compile(r'night|cave|dark|deep|under|seabed|end|hollow|menu|inventory|death|lava|blind|ancient|torch|nether|ember|stronghold|mineshaft|tunnel|lit|mob_shadows')
flags = []
by_hash = collections.defaultdict(list)
for name, kv in sorted(rows.items()):
    mag, blk, std = float(kv['magenta']), float(kv['black']), float(kv['std'])
    by_hash[kv['hash']].append(name)
    if mag > 0.0005: flags.append(('missing_texture', name, f'{mag*100:.2f}% magenta-checker pixels'))
    if std < 4: flags.append(('blank_frame', name, f'luma spread {std:.1f}'))
    elif blk > 0.6 and not dark_ok.search(name): flags.append(('black_frame', name, f'{blk*100:.0f}% near-black pixels'))
    if 'flicker' in kv and float(kv['flicker']) > 0.002: flags.append(('z_fighting', name, f'{float(kv["flicker"])*100:.2f}% pixels flip on a 1/1000-block nudge'))
# Diagnostic variants of a view are meant to match it (culling / base-pass / flicker probes); the bug-notes self-test
# renders the spawn view unchanged.
def view(n):
    n = n[:-4] if n.endswith('.png') else n
    n = n[8:] if n.startswith('flicker_') else n
    for suf in ('_nocull', '_nobase', '_verify'):
        if n.endswith(suf): n = n[:-len(suf)]
    return {'bugnotes': 'spawn'}.get(n, n)
for h, names in by_hash.items():
    if len(names) > 1 and len({view(n) for n in names}) > 1:
        flags.append(('duplicate_frame', ', '.join(names[:4]), f'{len(names)} views render the same image'))
out = ['# Image check', '', f'{len(rows)} frames checked, {len(flags)} flagged.', '', '| class | frame | detail |', '|---|---|---|']
out += [f'| {c} | {n} | {d} |' for c, n, d in flags]
open('snaps/imagecheck.md', 'w').write('\n'.join(out) + '\n')
cnt = collections.Counter(c for c, _, _ in flags)
print(f'imagecheck: {len(rows)} frames, ' + (', '.join(f'{k} {v}' for k, v in sorted(cnt.items())) or 'no flags'))
sys.exit(1 if '--strict' in sys.argv and flags else 0)
