#!/usr/bin/env python3
"""Every String(format:) in the game checked against the compiler's own types (Nov 11, bug hunt).

On Linux and the headset (swift-corelibs-foundation) a format's arguments are read by the specifiers alone: a whole
number under %f shows a stale register's value, under %@ it crashes, and too few arguments read past the end.
`quest/tools/fmtcheck.sh` type-checks the sources with `swift-frontend -dump-ast` and streams the tree in here; each
call's literal format is paired with its arguments' CVarArg types. A ternary like `n > 0 ? total / Double(n) : 0` is
one of the traps: each side is boxed on its own, and the 0 stays an Int.
Prints "mixed(A|B)" where one argument can be either type, "mixed()" where its type was not found (`a ?? 0` and the
like, which the compiler types as one), and non-literal formats for reading by hand. Exit 1 on a mismatch.
"""
import sys, re
INTS = {'Int','Int8','Int16','Int32','Int64','UInt','UInt8','UInt16','UInt32','UInt64'}
FLOATS = {'Double','Float','CGFloat','Float80'}
spec_re = re.compile(r'%(?:\d+\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(hh|h|ll|l|q|L|z|t|j)?([diouxXeEfgGcsSp@aAF%])')
seen = set(); out = []
def indent(l): return len(l) - len(l.lstrip(' '))
def check(block):
    loc = re.search(r'location=(\S+)', block[0]).group(1)
    if loc in seen: return
    seen.add(loc)
    fmt = None; nonlit = False; args = []
    for i, l in enumerate(block):
        if 'argument label="format"' in l:
            nxt = block[i + 1]
            m = re.search(r'string_literal_expr .*? value="((?:[^"\\]|\\.)*)"', nxt)
            if m and nxt.lstrip().startswith('(string_literal_expr'): fmt = m.group(1)
            else: nonlit = True
            break
    ai = None
    for i, l in enumerate(block):
        if '(array_expr implicit type="any CVarArg..."' in l: ai = i; break
    if ai is not None:
        A = indent(block[ai])
        for i in range(ai + 1, len(block)):
            l = block[i]
            if indent(l) <= A: break
            if indent(l) == A + 2:
                if l.lstrip().startswith('(erasure_expr'):
                    m = re.search(r'conformance type="([^"]+)"', block[i + 1])
                    args.append(m.group(1) if m else '?' + block[i + 1].strip()[:60])
                else:
                    ts = set()
                    for k in range(i + 1, len(block)):
                        if indent(block[k]) <= A + 2: break
                        m = re.search(r'conformance type="([^"]+)" protocol="CVarArg"', block[k])
                        if m and indent(block[k]) <= A + 8: ts.add(m.group(1))
                    args.append(ts.pop() if len(ts) == 1 else 'mixed(' + '|'.join(sorted(ts)) + ')')
    if fmt is None:
        out.append(f'{loc}: non-literal format, {len(args)} args {args}' if nonlit else f'{loc}: no format found')
        return
    specs = [m for m in spec_re.finditer(fmt.replace('%%', '')) ]
    probs = []
    if len(specs) != len(args): probs.append(f'{len(specs)} specifiers, {len(args)} args')
    for k, (m, t) in enumerate(zip(specs, args)):
        c = m.group(2)
        if t.startswith('mixed(') and t != 'mixed()':
            ts = set(t[6:-1].split('|'))
            if ts <= FLOATS: t = 'Double'
            elif ts <= INTS: t = 'Int'
        if c in 'feEgGaAF' and t not in FLOATS: probs.append(f'arg {k+1} %{c} gets {t}')
        elif c in 'diouxXc' and t not in INTS and t != 'Character': probs.append(f'arg {k+1} %{c} gets {t}')
        elif c in 'sS' : probs.append(f'arg {k+1} %{c} gets {t} (C string)')
        elif c == '@' and (t in INTS or t in FLOATS): probs.append(f'arg {k+1} %@ gets {t}')
        elif c == 'p': pass
    if probs: out.append(f'{loc}: "{fmt}" {args}: ' + '; '.join(probs))
buf = None; bi = 0; pending = []
calls = 0
for line in sys.stdin:
    line = line.rstrip('\n')
    if buf is not None:
        if indent(line) <= bi and line.strip():
            check(buf); calls += 1; buf = None
        else:
            buf.append(line); continue
    # a call whose callee is String.init(format:...)
    pending.append(line)
    if len(pending) > 4: pending.pop(0)
    if 'extension.init(format:' in line or 'appendingFormat' in line and 'decl=' in line:
        # the call_expr is the nearest earlier line starting with (call_expr / original_init=call_expr
        for p in reversed(pending[:-1]):
            if 'call_expr' in p and 'constructor_ref_call_expr' not in p:
                buf = [p, line]; bi = indent(p); break
if buf: check(buf); calls += 1
print(f'{calls} calls, {len(seen)} distinct')
bad = 0
for o in sorted(set(out)):
    print(o)
    if 'non-literal' not in o and 'mixed()' not in o: bad += 1
sys.exit(1 if bad else 0)
