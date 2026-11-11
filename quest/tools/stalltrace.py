#!/usr/bin/env python3
# Names the stacks BS_STALLTRACE=FILE wrote (quest/src/test/StallTrace.swift) and adds them up by function.
#   quest/tools/stalltrace.py FILE BINARY [--frame F] [--top N]
# Prints, for all slow frames together and then for each one: the functions the most samples were inside (inclusive)
# and the ones the samples were in themselves (self: the nearest function of the executable, a library call counted
# to its caller). Needs llvm-symbolizer and swift-demangle on PATH (the Swift
# toolchain's usr/bin has both).
import collections, subprocess, sys

def main():
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__ or "usage: stalltrace.py FILE BINARY [--frame F] [--top N]"); return 2
    path, binary = args[0], args[1]
    only = int(args[args.index("--frame") + 1]) if "--frame" in args else None
    top = int(args[args.index("--top") + 1]) if "--top" in args else 25
    frames, samples = [], []
    for line in open(path):
        p = line.split()
        if not p: continue
        if p[0] == "frame": frames.append((int(p[1]), p[2], " ".join(p[3:])))
        elif p[0] == "s": samples.append((int(p[1]), [int(x, 16) for x in p[2:]]))
    offs = sorted({o for _, st in samples for o in st})
    # A return address points after its call: look up the byte before it (the leaf's own address is exact, and one
    # byte early is still inside the same function).
    q = "\n".join("0x%x" % max(0, o - 1) for o in offs) + "\n"
    r = subprocess.run(["llvm-symbolizer", "--obj=" + binary, "--functions=linkage", "--no-inlines", "--output-style=GNU"],
                       input=q, capture_output=True, text=True).stdout.split("\n")
    names = [r[i * 2] if i * 2 < len(r) else "??" for i in range(len(offs))]
    dem = subprocess.run(["swift-demangle", "--simplified", "--compact"], input="\n".join(names) + "\n",
                         capture_output=True, text=True).stdout.split("\n")
    name = {o: (dem[i] if i < len(dem) and dem[i] else names[i]) for i, o in enumerate(offs)}
    def clean(st):
        out = []
        for o in st:
            n = name.get(o, "??")
            if n in ("??", "_end") or "StallTrace" in n: continue   # the handler; libc and libraries (outside the executable)
            out.append(n[:160])
        return out
    def report(sel, title):
        incl, selfc = collections.Counter(), collections.Counter()
        for _, st in sel:
            c = clean(st)
            if not c: continue
            selfc[c[0]] += 1
            for n in set(c): incl[n] += 1
        n = max(1, len(sel))
        print("== %s: %d samples" % (title, len(sel)))
        print("  inside (inclusive):")
        for k, v in incl.most_common(top): print("   %5.1f%%  %s" % (100.0 * v / n, k))
        print("  self:")
        for k, v in selfc.most_common(min(top, 12)): print("   %5.1f%%  %s" % (100.0 * v / n, k))
    if only is None:
        report(samples, "all slow frames")
    for f, ms, what in frames:
        if only is not None and f != only: continue
        sel = [s for s in samples if s[0] == f]
        report(sel, "frame %d, %s ms, %s" % (f, ms, what))
    return 0

if __name__ == "__main__":
    sys.exit(main())
