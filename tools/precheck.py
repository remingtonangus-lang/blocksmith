#!/usr/bin/env python3
"""Pre-push sanity checks for Sources/*.swift when no Swift compiler is at hand (cloud sessions): brace /
paren / bracket balance (string- and comment-aware, incl. string interpolation), unseeded randomness
(must go through Rand), and patterns that have blown the CI type-check gate. Exit 1 on errors."""
import os, re, sys

root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Sources')
errors, warns = [], []
for f in sorted(os.listdir(root)):
    if not f.endswith('.swift'):
        continue
    src = open(os.path.join(root, f)).read()
    # Balance: walk characters, skipping comments and string contents (but entering \( ... ) interpolations).
    stack = []           # (char, line)
    i, line, n = 0, 1, len(src)
    mode = ['code']      # code | str | mstr ; interpolation pushes 'code' with a marker
    interp = []          # paren depth at which each interpolation started
    while i < n:
        c = src[i]
        if c == '\n':
            line += 1
        m = mode[-1]
        if m == 'code':
            if src.startswith('//', i):
                j = src.find('\n', i); i = n if j < 0 else j; continue
            if src.startswith('/*', i):
                j = src.find('*/', i + 2); line += src[i:j].count('\n'); i = n if j < 0 else j + 2; continue
            if src.startswith('"""', i):
                mode.append('mstr'); i += 3; continue
            if c == '"':
                mode.append('str'); i += 1; continue
            if c in '{([':
                stack.append((c, line))
            elif c in '})]':
                if interp and c == ')' and len(stack) == interp[-1]:
                    interp.pop(); mode.pop(); i += 1; continue
                if not stack:
                    errors.append(f'{f}:{line}: unmatched {c}')
                else:
                    o, ol = stack.pop()
                    if '{([' .index(o) != '})]'.index(c):
                        errors.append(f'{f}:{line}: {c} closes {o} from line {ol}')
            i += 1; continue
        # inside a string
        if c == '\\':
            if i + 1 < n and src[i + 1] == '(':
                interp.append(len(stack)); mode.append('code'); i += 2; continue
            i += 2; continue
        if m == 'str' and c == '"':
            mode.pop(); i += 1; continue
        if m == 'mstr' and src.startswith('"""', i):
            mode.pop(); i += 3; continue
        if m == 'str' and c == '\n':
            errors.append(f'{f}:{line}: newline inside a string literal'); mode.pop()
        i += 1
    for o, ol in stack:
        errors.append(f'{f}:{ol}: {o} never closed')
    if f != 'Rand.swift':
        for k, l in enumerate(src.split('\n'), 1):
            if re.search(r'\b(Float|Int|Double|UInt64|Bool)\.random\(|\.randomElement\(\)|\.shuffled\(\)', l):
                errors.append(f'{f}:{k}: unseeded randomness (use Rand.* / .pick() / .shuffledRand())')
            # A unary minus on the implicit member .pi (`-.pi / 2 + side * x` took 2 s in run 354): write -Float.pi.
            # .pi as a ternary branch is the next slowest form.
            code = l.split('//')[0]
            if re.search(r'(?<![A-Za-z0-9_)\]\s])\s*-\.pi\b|[(=,]\s*-\.pi\b', code):
                warns.append(f'{f}:{k}: -.pi (type-check risk in longer arithmetic: write -Float.pi)')
            elif re.search(r'[?:]\s*\.pi\b', code):
                warns.append(f'{f}:{k}: .pi in a ternary (type-check risk: write Float.pi)')
            # `(x?.y ?? .none) == .none` reads both as Optional.none (nil), not the enum's own case: the test never
            # matches the case (CapitalBasesWork formPatrol skipped every soldier at StationPose.none).
            if re.search(r'\?\?\s*\.none\s*\)\s*[!=]=\s*\.none\b', code):
                errors.append(f'{f}:{k}: `(x ?? .none) == .none` compares with nil; name the enum (Type.none)')
            # Code swallowed by a comment: a scripted edit appended a comment mid-declaration ("..., trousers   // note =
            # V3(...), boots = V3(...)": run 505). A trailing comment holding "name = Type(" is almost always that.
            if '//' in l and not l.lstrip().startswith('//') and '"' not in l:
                tail = l.split('//', 1)[1]
                if re.search(r'\b[a-z][A-Za-z0-9]*\s*=\s*[A-Z][A-Za-z0-9]*\(', tail) and re.search(r',\s*[a-z][A-Za-z0-9]*\s*$', l.split('//', 1)[0]):
                    errors.append(f'{f}:{k}: a comment swallowed code (the declaration continues after //)')
            # Long interpolated print lines and long chained vector math have timed out the type checker.
            if l.count('\\(') >= 5 and ('*' in l or '+' in l.split('"')[0]):
                warns.append(f'{f}:{k}: {l.count(chr(92) + "(")} interpolations with arithmetic (type-check risk)')
# Dictionary literals with a repeated key: a merge leftover where one entry silently wins (or a trap when first read;
# Settings help had "wscale" twice after a merge).
# Every multi-line literal opened after `=`, `return` or `??` whose lines start with "key": or .case: is checked.
import collections
for f in sorted(os.listdir(root)):
    if not f.endswith('.swift'):
        continue
    src = open(os.path.join(root, f)).read()
    for m in re.finditer(r'(?:=|return|\?\?)\s*\[\s*\n', src):
        j = src.rfind('[', 0, m.end())
        depth, k = 0, j
        while k < len(src):
            if src[k] == '[':
                depth += 1
            elif src[k] == ']':
                depth -= 1
                if depth == 0:
                    break
            k += 1
        keys = re.findall(r'^\s*("[^"\n]+"|\.[a-zA-Z_]\w*)\s*:', src[j + 1:k], re.M)
        for key, c in collections.Counter(keys).items():
            if c > 1:
                errors.append(f'{f}:{src[:j].count(chr(10)) + 1}: dictionary literal repeats key {key} ({c}x)')
# File-private top-level functions called from another file (no compiler here: MobRenderCheck called Mob.swift's
# private parts(), a build break only CI saw). Names also defined non-private anywhere, or as methods, are skipped.
import collections as _c
srcs = {f: open(os.path.join(root, f)).read() for f in sorted(os.listdir(root)) if f.endswith('.swift')}
private_top = _c.defaultdict(set)      # name -> files defining it privately at top level
public_any = set()
for f, src in srcs.items():
    for m in re.finditer(r'^(private |fileprivate )?func ([A-Za-z_]\w*)\s*[(<]', src, re.M):
        (private_top[m.group(2)].add(f) if m.group(1) else public_any.add(m.group(2)))
    for m in re.finditer(r'^[ \t]+(?:@\w+\s+)*(?:(?:public|internal|private|fileprivate|static|class|final|override|mutating|@inline\(__always\))\s+)*func ([A-Za-z_]\w*)\s*[(<]', src, re.M):
        public_any.add(m.group(1))
for name, files in private_top.items():
    if name in public_any:
        continue
    pat = re.compile(r'(?<![\w.])' + re.escape(name) + r'\(')
    for f, src in srcs.items():
        if f in files:
            continue
        code = re.sub(r'//[^\n]*', '', src)
        for m in pat.finditer(code):
            errors.append(f'{f}:{code[:m.start()].count(chr(10)) + 1}: calls {name}(), private to {", ".join(sorted(files))}')
            break
# The same top-level function signature defined twice (an edit applied twice: mobModelParts in Mob.swift).
sigs = _c.defaultdict(list)
for f, src in srcs.items():
    for m in re.finditer(r'^((?:private |fileprivate )?func [^\n{]*)', src, re.M):
        sigs[(m.group(1).strip(), f if m.group(1).startswith(('private', 'fileprivate')) else '')].append(f'{f}:{src[:m.start()].count(chr(10)) + 1}')
for (sig, _), where in sigs.items():
    if len(where) > 1:
        errors.append(f'{where[1]}: {sig.split("(")[0]} defined twice ({", ".join(where)})')
# The same attribute twice on one declaration (only comments or other attributes between): an edit leftover that
# fails the build ("duplicate attribute", run cad609a).
for f in sorted(os.listdir(root)):
    if not f.endswith('.swift'):
        continue
    seen = {}
    for k, l in enumerate(open(os.path.join(root, f)).read().split('\n'), 1):
        t = l.strip()
        if t.startswith('//') or not t:
            continue
        m = re.match(r'@(\w+)\s*$', t)
        if m:
            if m.group(1) in seen:
                errors.append(f'{f}:{k}: duplicate attribute @{m.group(1)} (also line {seen[m.group(1)]})')
            seen[m.group(1)] = k
        else:
            seen = {}
for e in errors: print('ERROR', e)
for w in warns: print('warn ', w)
print(f'precheck: {len(errors)} errors, {len(warns)} warnings')
sys.exit(1 if errors else 0)
