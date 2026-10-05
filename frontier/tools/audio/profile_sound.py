#!/usr/bin/env python3
"""Renders single sounds (variation 0) without writing files and prints time + peak memory: a quick dev loop.
  python3 frontier/tools/audio/profile_sound.py ID [ID ...]   (ID may be a regex)"""
import re
import resource
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_all  # noqa: E402
import dsp  # noqa: E402
from registry import SOUNDS  # noqa: E402

build_all.load_modules()
for pat in sys.argv[1:]:
    for sid in [s for s in SOUNDS if re.fullmatch(pat, s)]:
        t = time.time()
        x = SOUNDS[sid].fn(dsp.rng_for(sid, 0), 0)
        print(f"{sid:28s} {str(x.shape):14s} {time.time() - t:6.1f} s  maxrss "
              f"{resource.getrusage(resource.RUSAGE_SELF).ru_maxrss // 1024} MB", flush=True)
