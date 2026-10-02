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
            # Long interpolated print lines and long chained vector math have timed out the type checker.
            if l.count('\\(') >= 5 and ('*' in l or '+' in l.split('"')[0]):
                warns.append(f'{f}:{k}: {l.count(chr(92) + "(")} interpolations with arithmetic (type-check risk)')
# Dictionary literals with a repeated key trap when first read (Settings help had "wscale" twice after a merge).
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
                errors.append(f'{f}:{src[:j].count(chr(10)) + 1}: dictionary literal repeats key {key} ({c}x): traps when first read')
for e in errors: print('ERROR', e)
for w in warns: print('warn ', w)
print(f'precheck: {len(errors)} errors, {len(warns)} warnings')
sys.exit(1 if errors else 0)
