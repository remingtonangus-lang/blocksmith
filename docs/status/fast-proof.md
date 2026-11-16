# Fast proof: one named check in about a minute

**The rule:** `tools/prove.sh` is for iterating. The final proof before a merge is still the full suite, alone, on the
whole-module `-Ounchecked` build (`QUEST_OPT=-Ounchecked quest/tools/linux-check.sh build`, then the whole questcheck run).
Every timing and frame-rate number also comes from that build, never from the incremental one.

## The three commands

```
tools/prove.sh NAME                      # build what changed (-O, incremental), run questcheck's NAME check, terse output
tools/prove.sh --both BS_SWITCH NAME     # the same check twice: BS_SWITCH unset, then BS_SWITCH=1; both results
build/quest-inc-o/questcheck --list-checks   # every named run with its one-line comment
```

- `NAME` is `rail` for `--rail-only`; a run without `-only` works too (`placerow` -> `--placerow`), or give the whole flag.
- `ENV=VAL` arguments go to the check's environment (`tools/prove.sh rail BS_OLDWETROW=1`); arguments after `--` go to
  questcheck (`tools/prove.sh oct14 -- P251`).
- It runs from the repo dir at `BLOCKSMITH_TEXRES=32` and prints only `FAIL` lines, lines that mention NAME, the final
  pass/fail line and the times. `PROVE_ALL=1` prints everything. Exit code = failures (100 = build failed).
- `PROVE_OPT=onone` builds unoptimized (faster to build, checks run ~9x slower); `PROVE_BIN=path` uses a binary you
  already have (e.g. the WMO build) and builds nothing.
- `tools/qbuild.sh [onone|o|ounchecked]` is the build alone. It keeps its objects in `build/quest-inc-<mode>/` (one per
  worktree): delete that dir to start clean. It writes generated files only when they change, so they stay built.
- `quest/tools/listchecks.py` prints the same list from the source, without a build; `linux-check.sh` and `qbuild.sh`
  generate `CheckList.swift` from it.

## Measured (cloud box, 4 cores, 15 GB; Nov 16, quest-port 26ceac53)

| Build | Full | One-file body edit | New member on `World` |
|---|---|---|---|
| WMO `-Ounchecked` (`linux-check.sh build`, the merge gate) | 1,929 s (32 min) | everything again | everything again |
| incremental `-O`, file by file (`qbuild.sh o`, prove's default) | 455 s | 18-22 s | 367 s |
| incremental `-Onone` (`qbuild.sh onone`) | 134 s | 12-15 s | 106 s |

Running a check: `--throw-only` takes 28 s on the `-O` build and 250 s on `-Onone`, so prove defaults to `-O`.
`tools/prove.sh throw` after a one-file body edit: about 1 minute wall. Most of a small check's time is the shared
world load main.swift does before the `--X-only` runs, not the check itself.

Why it is fast: the old host build is one `swiftc` call with no incremental state, so every build compiles all 813
files (257k lines) again; whole-module optimization can't split the work. `qbuild.sh` passes `-incremental
-enable-batch-mode -j N -output-file-map`, so the driver recompiles only the changed files and the files that use
what changed, four at a time. Splitting the test harness was not needed: the harness is 13k of the 257k lines.

Things to know:
- An interface change (a new or changed member, type or global) in a widely used file recompiles most of the tree:
  about 6 minutes at `-O`. Body-only edits are seconds.
- Non-WMO `-O` code is not the shipped code (nothing inlines across files): fine for logic, never for timings.
- Don't run two builds at once on 4 cores with a WMO build (memory: ~7 GB each).
