"""Frontier's original adaptive score: compositions written as note data and arrangement rules in this file, rendered
per stem with FluidSynth + the FluidR3 GM soundfont (MIT, Frank Wen), then mixed and mastered here (convolution hall,
gentle compression, loudness match across stems, seamless loop by folding the reverb tail onto the start).

Every track is a set of equal-length stems that the game layers for intensity (manifest "intensity"). All melodies,
progressions and arrangements are original to Frontier.

Notation for melodies: "D5:1 F#5:0.5 r:0.5 ..." = pitch:beats (r = rest), bars separated by "|" (ignored).
Chords: one symbol per bar ("Dm", "G7", "F#dim", "Bb", "Em7", "Asus4"), "/" splits a bar in two halves.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np

import dsp

SF2_CANDIDATES = [os.environ.get("FRONTIER_SF2", ""), "/usr/share/sounds/sf2/FluidR3_GM.sf2",
                  "/usr/share/soundfonts/FluidR3_GM.sf2", "/usr/share/sounds/sf2/default-GM.sf2"]

# GM programs (0-based)
P = {"piano": 0, "honky": 3, "harmonica": 22, "accordion": 21, "nylon": 24, "steel": 25, "bass": 32, "violin": 40,
     "viola": 41, "cello": 42, "contrabass": 43, "trem": 44, "pizz": 45, "harp": 46, "timpani": 47, "strings": 48,
     "slowstr": 49, "trumpet": 56, "trombone": 57, "tuba": 58, "horn": 60, "brass": 61, "oboe": 68, "clarinet": 71,
     "flute": 73, "whistle": 78, "banjo": 105, "fiddle": 110, "taiko": 116, "tom": 117, "revcym": 119}
DRUM = {"kick": 36, "snare": 38, "rim": 37, "hh": 42, "hho": 46, "crash": 49, "ride": 51, "tamb": 54, "cabasa": 69,
        "shaker": 70, "claves": 75, "wood_hi": 76, "wood_lo": 77, "tom_lo": 45, "tom_hi": 48, "tom_floor": 41,
        "brush": 40}

NOTE_RE = re.compile(r"^([A-G])([#b]?)(-?\d)$")
SEMI = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name: str) -> int:
    m = NOTE_RE.match(name)
    if not m:
        raise ValueError(name)
    n = SEMI[m.group(1)] + {"#": 1, "b": -1, "": 0}[m.group(2)]
    return 12 * (int(m.group(3)) + 1) + n


def parse_melody(s: str, start: float = 0.0):
    """-> [(beat, dur, pitch)]"""
    out, t = [], start
    for tok in s.replace("|", " ").split():
        p, d = tok.split(":")
        d = float(d)
        if p != "r":
            out.append((t, d, midi(p)))
        t += d
    return out


QUAL = {"": (0, 4, 7), "m": (0, 3, 7), "7": (0, 4, 7, 10), "m7": (0, 3, 7, 10), "maj7": (0, 4, 7, 11),
        "dim": (0, 3, 6, 9), "aug": (0, 4, 8), "sus4": (0, 5, 7), "5": (0, 7), "6": (0, 4, 7, 9), "m6": (0, 3, 7, 9),
        "9": (0, 4, 7, 10, 14)}
CH_RE = re.compile(r"^([A-G])([#b]?)(maj7|m7|m6|dim|aug|sus4|m|7|5|6|9)?$")


def chord(sym: str):
    """-> (root pitch class, intervals)"""
    m = CH_RE.match(sym)
    if not m:
        raise ValueError(sym)
    root = (SEMI[m.group(1)] + {"#": 1, "b": -1, "": 0}[m.group(2)]) % 12
    return root, QUAL[m.group(3) or ""]


def parse_prog(s: str, beats_per_bar: int = 4):
    """-> [(beat, dur, root_pc, intervals)] one entry per chord span."""
    out, t = [], 0.0
    for bar in s.split("|"):
        bar = bar.strip()
        if not bar:
            continue
        parts = bar.split("/") if "/" in bar else [bar]
        d = beats_per_bar / len(parts)
        for p in parts:
            r, iv = chord(p.strip())
            out.append((t, d, r, iv))
            t += d
    return out


def nearest(pc: int, target: int) -> int:
    """MIDI pitch with pitch class pc closest to target."""
    base = target - ((target - pc) % 12)
    return base if target - base <= 6 else base + 12


def voicing(root: int, iv, center: int, n: int = 4, prev=None):
    """Close voicing of the chord around `center`; with prev, choose the inversion closest to the previous chord."""
    pcs = [(root + i) % 12 for i in iv]
    best, bestcost = None, 1e9
    for inv in range(len(pcs)):
        order = pcs[inv:] + pcs[:inv]
        v = [nearest(order[0], center - 5)]
        for pc in order[1:]:
            p = nearest(pc, v[-1] + 3)
            while p <= v[-1]:
                p += 12
            v.append(p)
        while len(v) < n:
            v.append(v[len(v) - len(pcs)] + 12)
        v = v[:n]
        cost = abs(np.mean(v) - center) + (sum(min(abs(a - b) for b in prev) for a in v) * 0.5 if prev else 0)
        if cost < bestcost:
            best, bestcost = v, cost
    return best


class Part:
    def __init__(self, program: int, vol: int = 100, pan: int = 64, drums: bool = False):
        self.program = program
        self.vol = vol
        self.pan = pan
        self.drums = drums
        self.notes = []     # (beat, dur, pitch, vel)

    def add(self, beat, dur, pitch, vel=90):
        self.notes.append((beat, dur, int(pitch), int(np.clip(vel, 1, 127))))


class Track:
    def __init__(self, tid: str, bpm: float, bars: int, kind: str, beats_per_bar: int = 4, loop: bool = True,
                 tail: float = 4.0, wet: float = 0.22, tags=None, intensity=None, gain_db: float = 0.0, lufs=-17.0):
        self.id, self.bpm, self.bars, self.kind = tid, bpm, bars, kind
        self.bpb, self.loop, self.tail, self.wet = beats_per_bar, loop, tail, wet
        self.stems: dict[str, list[Part]] = {}
        self.stem_wet: dict[str, float] = {}
        self.tags = tags or {}
        self.intensity = intensity
        self.gain_db = gain_db
        self.lufs = lufs
        self.stem_level: dict[str, float] = {}

    def stem(self, name: str, wet: float = None) -> list:
        self.stems.setdefault(name, [])
        if wet is not None:
            self.stem_wet[name] = wet
        return self.stems[name]

    @property
    def beats(self):
        return self.bars * self.bpb

    @property
    def length_s(self):
        return self.beats * 60.0 / self.bpm


# relative stem loudness (LU vs the track target) used when balancing stems
STEM_LEVEL = {"base": -3.0, "melody": -4.5, "pad": -9.0, "rhythm": -8.0, "perc": -6.0, "ostinato": -3.0, "brass": -7.0,
              "pulse": -6.0, "high": -10.0, "fiddle": -7.0, "main": 0.0, "piano": 0.0}


# ------------------------------------------------------------------------------------------------ arranging helpers
def humanize(part: Part, rng, t_ms=8.0, vel=6):
    out = []
    for (b, d, p, v) in part.notes:
        out.append((max(0.0, b + rng.normal(0, t_ms / 1000.0)), d, p, v + int(rng.integers(-vel, vel + 1))))
    part.notes = out


def travis(part: Part, prog, rng, bass_center=45, treble_center=62, vel=78, eighths=True):
    """Fingerpicked guitar: alternating bass on the beats (root / fifth), treble pinches on the off-beats."""
    for (t, d, r, iv) in prog:
        root = nearest(r, bass_center)
        fifth = nearest((r + 7) % 12, bass_center + 5)
        v = voicing(r, iv[:3], treble_center, 3)
        k = 0
        b = 0.0
        while b < d - 1e-6:
            bass = root if k % 2 == 0 else fifth
            part.add(t + b, 0.9, bass, vel + 6 if k % 2 == 0 else vel)
            if eighths:
                tn = v[(k + 1) % 3]
                part.add(t + b + 0.5, 0.45, tn, vel - 10 + rng.integers(-6, 6))
                if k % 2 == 1:
                    part.add(t + b + 0.5, 0.45, v[(k + 2) % 3], vel - 14)
            k += 1
            b += 1.0


def arpeggio(part: Part, prog, rng, center=60, step=0.5, pattern=(0, 1, 2, 3, 2, 1), vel=70, n=4, bass=True,
             bass_center=40, sustain=1.6):
    prev = None
    for (t, d, r, iv) in prog:
        v = voicing(r, iv, center, n, prev)
        prev = v
        if bass:
            part.add(t, d * 0.95, nearest(r, bass_center), vel + 8)
        k = 0
        b = 0.0
        while b < d - 1e-6:
            part.add(t + b, sustain * step * 2, v[pattern[k % len(pattern)] % n], vel - 4 + rng.integers(-5, 5))
            k += 1
            b += step


def pad(part: Part, prog, center=60, vel=60, n=4, low=None):
    prev = None
    for (t, d, r, iv) in prog:
        v = voicing(r, iv, center, n, prev)
        prev = v
        for p in v:
            part.add(t, d, p, vel)
        if low is not None:
            part.add(t, d, nearest(r, low), vel + 5)


def bassline(part: Part, prog, rng, center=40, pattern="root5", vel=88):
    for (t, d, r, iv) in prog:
        root = nearest(r, center)
        fifth = root + 7 if root + 7 <= center + 9 else root - 5
        if pattern == "root":
            part.add(t, d * 0.9, root, vel)
        elif pattern == "root5":
            b = 0.0
            k = 0
            while b < d - 1e-6:
                part.add(t + b, 0.9, root if k % 2 == 0 else fifth, vel if k % 2 == 0 else vel - 8)
                b += 2.0 if d >= 4 else 1.0
                k += 1
        elif pattern == "walk":
            third = root + iv[1]
            seq = [root, third, fifth, root + 12 - 1 if False else fifth + 2]
            for k in range(int(d)):
                part.add(t + k, 0.85, seq[k % 4], vel - (0 if k == 0 else 8))


def strum(part: Part, prog, rng, center=58, pattern=(0, 1.5, 2, 3, 3.5), vel=72, n=5, spread=0.012, dur=0.4,
          bass_first=True, bass_center=43):
    prev = None
    for (t, d, r, iv) in prog:
        v = voicing(r, iv, center, n, prev)
        prev = v
        for b in pattern:
            if b >= d:
                continue
            down = (b % 1.0) < 0.25
            notes = v if down else list(reversed(v[1:]))
            for i, p in enumerate(notes):
                part.add(t + b + i * spread, dur, p, vel - (0 if down else 12) - i * 2)
        if bass_first:
            part.add(t, 0.9, nearest(r, bass_center), vel + 4)


def stride(part: Part, prog, rng, vel=80):
    """Ragtime/stride left hand: bass (1), chord (2), bass fifth/octave (3), chord (4)."""
    prev = None
    for (t, d, r, iv) in prog:
        root = nearest(r, 38)
        fifth = nearest((r + 7) % 12, 40)
        v = voicing(r, iv, 55, 3, prev)
        prev = v
        for k in range(int(d)):
            if k % 2 == 0:
                part.add(t + k, 0.45, root if k % 4 == 0 else fifth, vel + 6)
                part.add(t + k, 0.45, (root if k % 4 == 0 else fifth) - 12, vel - 10)
            else:
                for p in v:
                    part.add(t + k, 0.35, p, vel - 12)


def banjo_roll(part: Part, prog, rng, vel=68):
    """Forward roll in 8ths over the chord (thumb on the high fifth string drone)."""
    prev = None
    for (t, d, r, iv) in prog:
        v = voicing(r, iv, 64, 3, prev)
        prev = v
        roll = [v[0], v[1], 67, v[2], v[0], 67, v[1], v[2]]
        for k in range(int(d * 2)):
            part.add(t + k * 0.5, 0.4, roll[k % 8], vel - 6 * (k % 2) + rng.integers(-5, 5))


def melody(part: Part, s: str, start=0.0, vel=88, transpose=0, legato=1.0, accent_first=True):
    for (b, d, p) in parse_melody(s, start):
        part.add(b, d * legato, p + transpose, vel + (8 if accent_first and b % 4 == 0 else 0))


def drums(part: Part, beats, pattern: dict, vel=80, rng=None, start=0.0):
    """pattern: {drum: [beats within a bar...]} repeated every bar for `beats` beats."""
    bar = 4
    for t0 in np.arange(start, beats, bar):
        for name, hits in pattern.items():
            for h in hits:
                v = vel if isinstance(h, (int, float)) else h[1]
                b = h if isinstance(h, (int, float)) else h[0]
                vv = v + (int(rng.integers(-8, 8)) if rng is not None else 0)
                part.add(t0 + b, 0.2, DRUM[name], vv)


def ostinato(part: Part, prog, rng, center=38, pat=(0, 0, 12, 0, 7, 0, 10, 0), step=0.5, vel=92, dur=0.35):
    for (t, d, r, iv) in prog:
        root = nearest(r, center)
        k = 0
        b = 0.0
        while b < d - 1e-6:
            off = pat[k % len(pat)]
            if off == 10 and 10 not in iv and 11 not in iv:
                off = iv[2] if len(iv) > 2 else 7
            part.add(t + b, dur, root + off, vel + (10 if k % 4 == 0 else 0) + rng.integers(-5, 5))
            b += step
            k += 1


# ------------------------------------------------------------------------------------------------ the score
def compose_all():
    T = {}
    R = np.random.default_rng(1899)

    # ---- main theme: D minor, 72 bpm, 24 bars
    t = Track("main_theme", 72, 24, "theme", intensity={"low": ["base", "pad"], "mid": ["base", "pad", "melody"],
                                                        "high": ["base", "pad", "melody", "perc"]})
    prog = parse_prog("Dm|Dm|Bb|F|Gm|Dm|A|A|Dm|Dm|Bb|F|Gm|A|Dm|Dm|F|C|Bb|F|Gm|A7|Dm|Dm")
    g = Part(P["nylon"], 100, 50); arpeggio(g, prog, R, 57, 0.5, (0, 1, 2, 3, 2, 1, 2, 1), 66, 4, True, 40)
    b = Part(P["contrabass"], 80, 64); bassline(b, prog, R, 38, "root", 70)
    t.stem("base", 0.18).extend([g, b])
    s = Part(P["slowstr"], 85, 70); pad(s, prog, 62, 52, 4)
    vc = Part(P["cello"], 80, 40); pad(vc, prog, 46, 55, 1)
    t.stem("pad", 0.3).extend([s, vc])
    h = Part(P["harmonica"], 98, 60)
    melody(h, "r:2 A4:1 D5:1 | F5:3 E5:0.5 D5:0.5 | D5:2 C5:1 Bb4:1 | A4:4 | r:1 G4:1 A4:1 Bb4:1 | A4:2 F4:1 D4:1 |"
              " E4:2 F4:1 G4:1 | A4:4", 0, 86)
    f = Part(P["fiddle"], 96, 72)
    melody(f, "r:2 A4:1 D5:1 | F5:2 G5:1 A5:1 | Bb5:2 A5:1 G5:1 | F5:3 r:1 | G5:1.5 F5:0.5 E5:1 D5:1 | E5:2 C#5:2 |"
              " D5:4 | r:4", 32, 84)
    hn = Part(P["horn"], 100, 58)
    theme_b = ("A4:3 G4:1 | E4:2 C4:2 | D4:2 F4:1 D4:1 | C4:4 | Bb3:2 D4:1 G4:1 | E4:2 C#4:1 A3:1 | D4:4 | r:4")
    melody(hn, theme_b, 64, 86)
    v1 = Part(P["violin"], 90, 80); melody(v1, theme_b, 64, 76, transpose=12)
    t.stem("melody", 0.32).extend([h, f, hn, v1])
    ti = Part(P["timpani"], 90, 64)
    for bar in (0, 8, 16, 23):
        for k in range(8):
            ti.add(bar * 4 + 2 + k * 0.25, 0.25, 38, 40 + k * 8)
        ti.add(bar * 4 + 4, 1.0, 38, 105)
    hp_ = Part(P["harp"], 80, 30); arpeggio(hp_, parse_prog("F|C|Bb|F|Gm|A7|Dm|Dm"), R, 72, 0.25, (0, 1, 2, 3), 50, 4, False)
    hp_.notes = [(b + 64, d, p, v) for (b, d, p, v) in hp_.notes]
    t.stem("perc", 0.3).extend([ti, hp_])
    T[t.id] = t

    # ---- exploration, plains, day: G major, 92 bpm, 32 bars
    t = Track("explore_plains_day", 92, 32, "explore", tags={"biome": "plains", "time": "day"},
              intensity={"low": ["base", "pad"], "mid": ["base", "pad", "rhythm", "melody"],
                         "high": ["base", "pad", "rhythm", "melody"]})
    prog = parse_prog("G|G|C|G|G|Em|A7|D|G|G|C|Am|G|D|G|G|C|C|G|G|Am|D|G|Em|C|D|Bm|Em|C|D|G|G")
    g = Part(P["steel"], 100, 54); travis(g, prog, R, 43, 62, 74); humanize(g, R, 6)
    t.stem("base", 0.16).append(g)
    bs = Part(P["bass"], 90, 64); bassline(bs, prog, R, 40, "root5", 80)
    sh = Part(0, 70, 80, drums=True); drums(sh, t.beats, {"cabasa": [0.5, 1.5, 2.5, 3.5], "brush": [(1, 40), (3, 45)]}, 48, R)
    t.stem("rhythm", 0.14).extend([bs, sh])
    st = Part(P["strings"], 70, 70); pad(st, prog, 64, 44, 3)
    t.stem("pad", 0.32).append(st)
    h = Part(P["harmonica"], 100, 60)
    melody(h, "r:2 D4:1 G4:1 | B4:2 A4:1 G4:1 | E4:2 G4:2 | D4:4 | r:1 D4:1 G4:1 B4:1 | D5:2 B4:1 G4:1 | A4:3 E4:1 |"
              " F#4:4 | r:1 B4:1 B4:1 C5:1 | D5:2 B4:2 | C5:1 E5:1 D5:1 C5:1 | A4:4 | B4:1.5 A4:0.5 G4:1 B4:1 |"
              " A4:2 F#4:2 | G4:4 | r:4", 0, 84)
    f = Part(P["fiddle"], 90, 74)
    melody(f, "E5:2 D5:1 C5:1 | E5:2 G5:2 | D5:3 B4:1 | G4:4 | A4:1 C5:1 E5:1 D5:1 | C5:2 A4:1 F#4:1 |"
              " G4:1 B4:1 D5:1 G5:1 | E5:4 | E5:2 G4:2 | F#4:1 A4:1 D5:2 | D5:1 C#5:1 B4:2 | G4:2 B4:2 |"
              " C5:1 B4:1 A4:1 G4:1 | A4:2 D4:2 | G4:4 | r:4", 64, 80)
    t.stem("melody", 0.26).extend([h, f])
    T[t.id] = t

    # ---- exploration, plains, night: E minor, 66 bpm, 24 bars
    t = Track("explore_plains_night", 66, 24, "explore", tags={"biome": "plains", "time": "night"},
              intensity={"low": ["base", "pad"], "mid": ["base", "pad", "melody"], "high": ["base", "pad", "melody"]})
    prog = parse_prog("Em|Em|C|C|Am|Am|B7|B7|Em|Em|G|D|C|Am|B7|Em|C|G|Am|Em|C|B7|Em|Em")
    g = Part(P["nylon"], 100, 50); arpeggio(g, prog, R, 59, 0.5, (0, 2, 1, 3, 2, 1, 0, 2), 58, 4, True, 40, 2.0)
    humanize(g, R, 10)
    t.stem("base", 0.24).append(g)
    c = Part(P["cello"], 85, 40); pad(c, prog, 48, 50, 1)
    s = Part(P["slowstr"], 70, 80); pad(s, prog, 64, 40, 3)
    t.stem("pad", 0.36).extend([c, s])
    v = Part(P["violin"], 95, 70)
    melody(v, "r:4 | r:2 B4:2 | G4:3 E4:1 | E4:4 | A4:2 C5:2 | B4:2 A4:1 G4:1 | F#4:4 | D#4:2 B3:2 |"
              " E4:2 G4:1 B4:1 | E5:4 | D5:2 B4:2 | A4:2 F#4:2 | G4:2 E4:2 | C5:3 A4:1 | B4:2 D#5:2 | E5:4 |"
              " r:4 | r:2 D5:1 B4:1 | C5:2 A4:2 | B4:4 | G4:2 E4:2 | F#4:2 D#4:2 | E4:4 | r:4", 0, 74)
    t.stem("melody", 0.38).append(v)
    T[t.id] = t

    # ---- exploration, desert, day: A (Spanish flavour), 80 bpm, 32 bars
    t = Track("explore_desert_day", 80, 32, "explore", tags={"biome": "desert", "time": "day"},
              intensity={"low": ["base", "pad"], "mid": ["base", "pad", "rhythm", "melody"],
                         "high": ["base", "pad", "rhythm", "melody"]})
    prog = parse_prog("Am|Am|Dm|Am|G|F|E|E|Am|Am|Dm|Dm|F|E|Am|Am|F|G|Am|Am|Dm|E|Am|Am|F|E|Dm|E|F|E|Am|Am")
    g = Part(P["nylon"], 100, 50)
    strum(g, prog, R, 57, (0, 0.75, 1.5, 2, 2.75, 3.5), 70, 5, 0.018, 0.5, True, 40); humanize(g, R, 6)
    t.stem("base", 0.2).append(g)
    tk = Part(0, 80, 64, drums=True)
    drums(tk, t.beats, {"tom_floor": [(0, 70), (1.5, 50), (2.5, 55)], "shaker": [0.5, 1, 1.5, 2, 2.5, 3, 3.5],
                         "claves": [(0, 50), (1.5, 40), (3, 45)]}, 40, R)
    bs = Part(P["contrabass"], 85, 64); bassline(bs, prog, R, 38, "root5", 74)
    t.stem("rhythm", 0.18).extend([tk, bs])
    dr = Part(P["strings"], 70, 64)
    for k in range(0, t.beats, 16):
        dr.add(k, 16, midi("A2"), 50); dr.add(k, 16, midi("E3"), 44)
    t.stem("pad", 0.35).append(dr)
    tp = Part(P["trumpet"], 90, 60)
    melody(tp, "r:2 E4:1 A4:1 | C5:3 B4:0.5 A4:0.5 | D5:2 F5:1 E5:1 | E5:4 | D5:1 C5:1 B4:1 D5:1 | C5:2 A4:2 |"
               " G#4:1.5 A4:0.5 B4:1 G#4:1 | E4:4 | A4:1 C5:1 E5:1 A5:1 | G#5:2 E5:2 | F5:2 D5:1 A4:1 | D5:4 |"
               " C5:1 A4:1 F4:1 A4:1 | Bb4:1 A4:1 G#4:2 | A4:4 | r:4", 0, 70)
    fl = Part(P["whistle"], 85, 70)
    melody(fl, "C5:2 A4:2 | D5:2 B4:2 | E5:3 D5:0.5 C5:0.5 | A4:4 | F5:2 E5:1 D5:1 | E5:2 G#4:2 | A4:4 | r:4 |"
               " A5:2 F5:2 | G#5:2 E5:2 | F5:2 D5:2 | E5:2 B4:1 G#4:1 | A4:1 C5:1 F5:1 A5:1 | G#5:2 E5:2 | A5:4 |"
               " r:4", 64, 68)
    t.stem("melody", 0.34).extend([tp, fl])
    T[t.id] = t

    # ---- exploration, mountains, day: D major, 84 bpm, 32 bars
    t = Track("explore_mountains_day", 84, 32, "explore", tags={"biome": "mountains", "time": "day"},
              intensity={"low": ["base", "pad"], "mid": ["base", "pad", "rhythm", "melody"],
                         "high": ["base", "pad", "rhythm", "melody"]})
    prog = parse_prog("D|D|G|D|D|C|G|A|D|D|G|D|Bm|G|A|D|G|G|D|D|G|A|D|D|Bm|G|D|A|G|A|D|D")
    g = Part(P["steel"], 95, 50); strum(g, prog, R, 60, (0, 1, 1.5, 2, 3, 3.5), 64, 5, 0.012, 0.45, True, 43)
    humanize(g, R, 6)
    bj = Part(P["banjo"], 75, 84); banjo_roll(bj, prog, R, 60)
    t.stem("base", 0.18).extend([g, bj])
    bs = Part(P["bass"], 85, 64); bassline(bs, prog, R, 40, "root5", 78)
    t.stem("rhythm", 0.15).append(bs)
    hn = Part(P["horn"], 80, 50); pad(hn, prog, 57, 48, 3)
    st = Part(P["strings"], 75, 78); pad(st, prog, 66, 44, 3)
    t.stem("pad", 0.34).extend([hn, st])
    f = Part(P["fiddle"], 95, 70)
    melody(f, "r:2 A4:1 B4:1 | D5:2 F#5:1 E5:1 | D5:1 B4:1 G4:1 B4:1 | A4:4 | A4:1 D5:1 F#5:1 A5:1 | G5:2 E5:1 C5:1 |"
              " D5:1 B4:1 G4:2 | E4:2 C#5:2 | D5:2 F#5:2 | A5:3 F#5:1 | G5:1 F#5:1 E5:1 D5:1 | F#5:2 D5:2 |"
              " D5:1 C#5:1 B4:1 D5:1 | B4:2 G4:2 | A4:1 B4:1 C#5:1 E5:1 | D5:4", 0, 82)
    hm = Part(P["horn"], 100, 60)
    melody(hm, "B4:3 D5:1 | G5:4 | F#5:2 D5:2 | A4:4 | B4:2 D5:2 | C#5:2 E5:2 | D5:4 | r:4 | D5:3 B4:1 | B4:4 |"
               " A4:2 F#4:1 A4:1 | E4:4 | D5:2 B4:2 | C#5:2 E5:2 | D5:4 | r:4", 64, 84, transpose=-12)
    t.stem("melody", 0.3).extend([f, hm])
    T[t.id] = t

    # ---- night (generic, mountains/desert/forest): A minor, 58 bpm, 16 bars
    t = Track("explore_night", 58, 16, "explore", tags={"time": "night"},
              intensity={"low": ["base", "pad"], "mid": ["base", "pad", "melody"], "high": ["base", "pad", "melody"]})
    prog = parse_prog("Am|F|C|G|Am|F|Dm|E|F|G|Em|Am|Dm|Em|F/E|Am")
    pn = Part(P["piano"], 90, 60); arpeggio(pn, prog, R, 55, 1.0, (0, 1, 2, 1), 50, 3, True, 36, 2.0)
    t.stem("base", 0.3).append(pn)
    c = Part(P["cello"], 85, 40); pad(c, prog, 45, 50, 1)
    t.stem("pad", 0.36).append(c)
    m = Part(P["piano"], 90, 70)
    melody(m, "E5:3 D5:1 | C5:4 | E5:2 G5:2 | D5:4 | E5:2 A5:2 | C5:4 | D5:2 F5:2 | E5:2 G#4:2 | A4:2 C5:2 |"
              " D5:2 B4:2 | G4:2 B4:2 | A4:4 | F4:2 A4:2 | G4:2 B4:2 | C5:2 B4:2 | A4:4", 0, 62)
    t.stem("melody", 0.4).append(m)
    T[t.id] = t

    # ---- town: C major ragtime, 104 bpm, 32 bars
    t = Track("town", 104, 32, "town", intensity={"low": ["base"], "mid": ["base", "rhythm", "melody"],
                                                  "high": ["base", "rhythm", "melody", "fiddle"]})
    prog = parse_prog("C|C|G7|C|F|C|D7|G7|C|C|G7|C|F|F#dim|C|G7|C|C7|F|F|C|A7|D7|G7|C|E7|Am|C7|F|G7|C|G7")
    rag = ("E5:0.5 G5:1 E5:0.5 C5:1 G4:1 | A4:0.5 C5:1 A4:0.5 G4:2 | F5:0.5 D5:1 B4:0.5 G4:1 F4:1 | E4:1 G4:1 C5:2 |"
           " A4:0.5 C5:1 F5:0.5 A5:1 F5:1 | E5:0.5 G5:1 E5:0.5 C5:2 | F#5:0.5 A5:1 F#5:0.5 D5:1 C5:1 | B4:1 D5:1 G5:2 |"
           " E5:0.5 G5:1 E5:0.5 C5:1 G4:1 | A4:0.5 C5:1 A4:0.5 G4:2 | D5:0.5 F5:1 D5:0.5 B4:1 G4:1 | C5:2 E5:2 |"
           " F5:1 A5:1 C6:1 A5:1 | A5:0.5 F#5:1 D#5:0.5 C5:2 | G5:1 E5:1 C5:1 E5:1 | D5:2 G4:2 |"
           " C5:1 E5:1 G5:1 C6:1 | Bb5:0.5 G5:1 E5:0.5 C5:2 | A5:0.5 F5:1 C5:0.5 A4:1 C5:1 | F5:4 |"
           " E5:0.5 G5:1 E5:0.5 C5:1 G4:1 | C#5:0.5 E5:1 G5:0.5 A5:2 | F#5:0.5 A5:1 F#5:0.5 D5:1 C5:1 | B4:1 D5:1 F5:2 |"
           " E5:0.5 G5:1 E5:0.5 C5:1 G4:1 | G#4:0.5 B4:1 D5:0.5 E5:2 | A4:0.5 C5:1 E5:0.5 A5:2 | Bb5:0.5 G5:1 E5:0.5 C5:2 |"
           " A5:0.5 F5:1 A5:0.5 C6:2 | B5:0.5 G5:1 F5:0.5 D5:2 | C5:1 G4:1 E4:1 G4:1 | C5:2 r:2")
    lh = Part(P["honky"], 95, 56); stride(lh, prog, R, 76); humanize(lh, R, 5)
    t.stem("base", 0.14).append(lh)
    bs = Part(P["bass"], 85, 64); bassline(bs, prog, R, 40, "root5", 76)
    sn = Part(0, 60, 70, drums=True); drums(sn, t.beats, {"brush": [(1, 42), (3, 48)], "rim": [(3.5, 30)]}, 40, R)
    t.stem("rhythm", 0.12).extend([bs, sn])
    rh = Part(P["honky"], 92, 70); melody(rh, rag, 0, 80, legato=0.85); humanize(rh, R, 5)
    bj = Part(P["banjo"], 70, 90); banjo_roll(bj, prog, R, 54)
    t.stem("melody", 0.14).extend([rh, bj])
    fd = Part(P["fiddle"], 85, 40); melody(fd, " ".join(rag.split("|")[16:]), 64, 70, transpose=-12, legato=0.9)
    t.stem("fiddle", 0.2).append(fd)
    T[t.id] = t

    # ---- tension: D minor, 76 bpm, 16 bars
    t = Track("tension", 76, 16, "tension", intensity={"low": ["base", "pulse"], "mid": ["base", "pulse"],
                                                      "high": ["base", "pulse", "high"]})
    tr = Part(P["trem"], 90, 64)
    for (b0, d, pitches) in [(0, 8, ["D2", "A2", "D3"]), (8, 8, ["D2", "Bb2", "F3"]), (16, 8, ["D2", "G2", "D3"]),
                             (24, 8, ["C#2", "A2", "E3"]), (32, 8, ["D2", "A2", "D3"]), (40, 8, ["Eb2", "Bb2", "G3"]),
                             (48, 8, ["D2", "Bb2", "F3"]), (56, 8, ["C#2", "G2", "E3"])]:
        for p in pitches:
            tr.add(b0, d, midi(p), 58)
    t.stem("base", 0.32).append(tr)
    pz = Part(P["pizz"], 95, 50)
    pulse_roots = ["D2", "D2", "D2", "C#2", "D2", "Eb2", "D2", "C#2"]
    for i, r in enumerate(pulse_roots):
        for k in range(8):
            pz.add(i * 8 + k, 0.3, midi(r), 72 if k % 2 == 0 else 58)
            if k % 4 == 3:
                pz.add(i * 8 + k + 0.5, 0.3, midi(r) + 12, 60)
    hb = Part(0, 80, 64, drums=True); drums(hb, t.beats, {"kick": [(0, 70), (0.4, 55)]}, 60, R)
    t.stem("pulse", 0.2).extend([pz, hb])
    hv = Part(P["violin"], 70, 80)
    for k in range(0, t.beats, 8):
        hv.add(k, 8, midi("A5"), 40); hv.add(k + 4, 4, midi("Bb5"), 34)
    hpp = Part(P["harp"], 80, 30)
    for k in range(0, t.beats, 4):
        hpp.add(k + 2.5, 2, midi("F5") if (k // 4) % 2 else midi("E5"), 40)
    t.stem("high", 0.45).extend([hv, hpp])
    T[t.id] = t

    # ---- combat: D minor, 132 bpm, 16 bars
    t = Track("combat", 132, 16, "combat", intensity={"low": ["ostinato"], "mid": ["ostinato", "perc", "brass"],
                                                     "high": ["ostinato", "perc", "brass", "melody"]})
    prog = parse_prog("Dm|Dm|Bb|C|Dm|Dm|Bb|A|Gm|Bb|C|Dm|Bb|C|A|A")
    vc = Part(P["cello"], 100, 50); ostinato(vc, prog, R, 38, (0, 0, 12, 0, 7, 0, 10, 0), 0.5, 90)
    cb = Part(P["contrabass"], 95, 64); ostinato(cb, prog, R, 33, (0, 0, 0, 0, 0, 0, 0, 0), 0.5, 84)
    gs = Part(P["steel"], 80, 80); strum(gs, prog, R, 52, (0, 0.5, 1.5, 2, 2.5, 3.5), 66, 4, 0.006, 0.15, False)
    t.stem("ostinato", 0.14).extend([vc, cb, gs])
    dr = Part(0, 95, 64, drums=True)
    drums(dr, t.beats, {"tom_floor": [(0, 100), (1.5, 80), (2, 90), (3.5, 85)],
                         "snare": [(1, 70), (3, 80), (3.75, 50)], "hh": [0.5, 1.5, 2.5, 3.5]}, 60, R)
    for k in range(0, t.beats, 16):
        dr.add(k, 1, DRUM["crash"], 90)
    tk = Part(P["taiko"], 90, 64)
    for k in range(0, t.beats, 2):
        tk.add(k, 1, 36, 96 if k % 4 == 0 else 72)
    t.stem("perc", 0.16).extend([dr, tk])
    br = Part(P["trombone"], 100, 50); hrn = Part(P["horn"], 95, 78)
    prev = None
    for (b0, d, r, iv) in prog:
        v = voicing(r, iv[:3], 52, 3, prev); prev = v
        for p in v:
            br.add(b0, 0.6, p, 92); br.add(b0 + 1.5, 0.4, p, 84)
            hrn.add(b0 + 2.5, 1.2, p + 12, 80)
    t.stem("brass", 0.22).extend([br, hrn])
    fd = Part(P["fiddle"], 95, 70)
    for (b0, d, r, iv) in prog:
        v = voicing(r, iv[:3], 74, 3)
        run = [v[0], v[1], v[2], v[1] + 12 if False else v[2] + 2, v[2], v[1], v[0], v[1]]
        for k in range(16):
            fd.add(b0 + k * 0.25, 0.22, run[k % 8], 78 + (12 if k % 4 == 0 else 0))
    t.stem("melody", 0.22).append(fd)
    T[t.id] = t

    # ---- mission: the ride (chase), A minor, 144 bpm, 16 bars
    t = Track("mission_ride", 144, 16, "mission", intensity={"low": ["base", "perc"], "mid": ["base", "perc", "melody"],
                                                            "high": ["base", "perc", "melody"]})
    prog = parse_prog("Am|G|Am|G|F|E|Am|Am|Am|G|Am|G|F|E|Am|Am")
    gal = Part(P["strings"], 95, 64); g2 = Part(P["steel"], 85, 40)
    prev = None
    for (b0, d, r, iv) in prog:
        v = voicing(r, iv[:3], 57, 3, prev); prev = v
        for k in range(int(d)):
            for (o, ln, vv) in ((0, 0.4, 92), (0.5, 0.2, 70), (0.75, 0.2, 76)):
                for p in v:
                    gal.add(b0 + k + o, ln, p, vv - 10)
                g2.add(b0 + k + o, ln, v[0] - 12, vv)
    t.stem("base", 0.16).extend([gal, g2])
    dr = Part(0, 95, 64, drums=True)
    drums(dr, t.beats, {"snare": [(0.5, 60), (0.75, 66), (1.5, 60), (1.75, 66), (2.5, 60), (2.75, 66), (3.5, 60), (3.75, 70)],
                         "kick": [(0, 90), (2, 85)]}, 60, R)
    ti = Part(P["timpani"], 90, 64)
    for (b0, d, r, iv) in prog:
        ti.add(b0, 1, nearest(r, 40), 96)
    t.stem("perc", 0.18).extend([dr, ti])
    tp = Part(P["trumpet"], 100, 60); hn = Part(P["horn"], 95, 70)
    ride = ("A4:1.5 E5:0.5 E5:2 | D5:1 C5:1 B4:1 G4:1 | A4:1.5 C5:0.5 E5:1 A5:1 | G5:4 | F5:1.5 E5:0.5 D5:1 C5:1 |"
            " B4:1 G#4:1 E5:2 | A4:1.5 B4:0.5 C5:1 E5:1 | A4:4")
    melody(tp, ride, 0, 92); melody(tp, ride, 32, 96)
    melody(hn, ride, 32, 88, transpose=-12)
    t.stem("melody", 0.24).extend([tp, hn])
    T[t.id] = t

    # ---- mission: the job (heist), B minor, 92 bpm, 16 bars
    t = Track("mission_heist", 92, 16, "mission", intensity={"low": ["base"], "mid": ["base", "rhythm"],
                                                            "high": ["base", "rhythm", "melody"]})
    prog = parse_prog("Bm|Bm|G|F#7|Bm|Bm|Em|F#7|G|A|F#m|Bm|Em|F#7|Bm|Bm")
    pz = Part(P["pizz"], 95, 54); bassline(pz, prog, R, 40, "walk", 80)
    mg = Part(P["nylon"], 85, 74); strum(mg, prog, R, 56, (0.5, 1.5, 2.5, 3.5), 60, 3, 0.004, 0.12, False)
    t.stem("base", 0.18).extend([pz, mg])
    dr = Part(0, 70, 64, drums=True)
    drums(dr, t.beats, {"shaker": [0.5, 1.5, 2.5, 3.5], "rim": [(1, 46), (3, 50), (3.75, 30)], "kick": [(0, 50)]}, 44, R)
    t.stem("rhythm", 0.14).append(dr)
    cl = Part(P["clarinet"], 95, 66)
    melody(cl, "r:1 F#4:0.5 B4:0.5 D5:1 C#5:1 | B4:2 r:2 | r:1 G4:0.5 B4:0.5 D5:1 B4:1 | A#4:4 |"
               " r:1 F#4:0.5 B4:0.5 D5:1 F#5:1 | E5:1 D5:1 C#5:2 | B4:1 G4:1 E4:1 G4:1 | F#4:4 |"
               " G4:1 B4:1 D5:1 E5:1 | C#5:2 A4:2 | A4:1 C#5:1 F#5:2 | D5:4 | E5:1 G5:1 B4:1 E5:1 |"
               " C#5:2 A#4:2 | B4:4 | r:4", 0, 74, transpose=-12)
    t.stem("melody", 0.3).append(cl)
    T[t.id] = t

    # ---- stingers (one-shots)
    t = Track("stinger_nerve", 60, 2, "stinger", loop=False, tail=3.0, lufs=-16.0)
    rc = Part(P["revcym"], 100, 64); rc.add(0, 1.6, 60, 90)
    ti = Part(P["timpani"], 100, 64)
    for k in range(10):
        ti.add(0.4 + k * 0.12, 0.12, 38, 40 + k * 7)
    ti.add(1.7, 2.0, 38, 120)
    lo = Part(P["strings"], 100, 64)
    for p in ("D2", "A2", "D3", "F3", "Eb4"):
        lo.add(1.7, 3.0, midi(p), 96)
    t.stem("main", 0.35).extend([rc, ti, lo])
    T[t.id] = t

    t = Track("stinger_mission_complete", 76, 3, "stinger", loop=False, tail=3.0, lufs=-16.0)
    g = Part(P["steel"], 95, 50); strum(g, parse_prog("A7|D|D"), R, 60, (0, 2), 74, 5, 0.03, 3.0, True)
    h = Part(P["harmonica"], 95, 66); melody(h, "E5:1 C#5:1 A4:1 G4:1 | F#4:4 | r:4", 0, 86)
    st = Part(P["strings"], 85, 70); pad(st, parse_prog("A7|D|D"), 64, 60, 4)
    t.stem("main", 0.3).extend([g, h, st])
    T[t.id] = t

    t = Track("stinger_death", 54, 3, "stinger", loop=False, tail=4.0, lufs=-18.0)
    lo = Part(P["slowstr"], 100, 64); melody(lo, "D3:4 | C3:2 Bb2:2 | A2:4", 0, 80)
    lo2 = Part(P["contrabass"], 90, 64); melody(lo2, "D2:4 | C2:2 Bb1:2 | A1:4", 0, 76)
    bell = Part(14, 80, 64)  # GM tubular bells
    for k in (0, 4, 8):
        bell.add(k, 3.5, midi("D4"), 70)
    t.stem("main", 0.4).extend([lo, lo2, bell])
    T[t.id] = t

    t = Track("stinger_discovery", 66, 3, "stinger", loop=False, tail=3.0, lufs=-17.0)
    hp_ = Part(P["harp"], 90, 50)
    for i, p in enumerate(["D4", "F#4", "A4", "D5", "F#5", "A5", "D6"]):
        hp_.add(i * 0.12, 3, midi(p), 70)
    hn = Part(P["horn"], 90, 64)
    for p in ("D3", "A3", "F#4"):
        hn.add(0.8, 6, midi(p), 70)
    st = Part(P["slowstr"], 80, 70); pad(st, parse_prog("D|G|D"), 66, 50, 4)
    t.stem("main", 0.4).extend([hp_, hn, st])
    T[t.id] = t

    # ---- diegetic saloon piano (played by the ambience mixer from inside/near saloons)
    t = Track("saloon_piano", 112, 32, "diegetic", wet=0.1, lufs=-20.0)
    prog = parse_prog("C|C|G7|C|F|C|D7|G7|C|C|G7|C|F|F#dim|C|G7|C|C7|F|F|C|A7|D7|G7|C|E7|Am|C7|F|G7|C|G7")
    lh = Part(P["honky"], 100, 54); stride(lh, prog, R, 84); humanize(lh, R, 9, 10)
    rh = Part(P["honky"], 100, 72); melody(rh, rag, 0, 88, legato=0.8); humanize(rh, R, 9, 10)
    t.stem("piano", 0.1).extend([lh, rh])
    T[t.id] = t
    return T


# ------------------------------------------------------------------------------------------------ rendering
def find_sf2() -> str | None:
    for c in SF2_CANDIDATES:
        if c and Path(c).exists():
            return c
    return None


def write_midi(path: Path, track: Track, parts: list[Part]):
    import mido
    mf = mido.MidiFile(ticks_per_beat=480)
    tpb = 480
    meta = mido.MidiTrack()
    meta.append(mido.MetaMessage("set_tempo", tempo=mido.bpm2tempo(track.bpm), time=0))
    end_tick = int((track.beats + track.tail * track.bpm / 60.0) * tpb)
    meta.append(mido.MetaMessage("end_of_track", time=end_tick))
    mf.tracks.append(meta)
    ch_next = 0
    for part in parts:
        ch = 9 if part.drums else ch_next
        if not part.drums:
            ch_next += 1
            if ch_next == 9:
                ch_next = 10
        mt = mido.MidiTrack()
        ev = []
        ev.append((0, 0, mido.Message("control_change", channel=ch, control=91, value=0)))
        ev.append((0, 0, mido.Message("control_change", channel=ch, control=93, value=0)))
        ev.append((0, 0, mido.Message("control_change", channel=ch, control=7, value=int(part.vol))))
        ev.append((0, 0, mido.Message("control_change", channel=ch, control=10, value=int(part.pan))))
        if not part.drums:
            ev.append((0, 0, mido.Message("program_change", channel=ch, program=int(part.program))))
        for (b, d, p, v) in part.notes:
            if b >= track.beats:
                continue
            on = int(round(b * tpb))
            off = int(round((b + max(d, 0.05)) * tpb))
            ev.append((on, 2, mido.Message("note_on", channel=ch, note=int(np.clip(p, 0, 127)), velocity=int(v))))
            ev.append((off, 1, mido.Message("note_off", channel=ch, note=int(np.clip(p, 0, 127)), velocity=0)))
        ev.sort(key=lambda e: (e[0], e[1]))
        last = 0
        for tick, _, msg in ev:
            msg.time = tick - last
            last = tick
            mt.append(msg)
        mt.append(mido.MetaMessage("end_of_track", time=max(0, end_tick - last)))
        mf.tracks.append(mt)
    mf.save(str(path))


def render_stem(track: Track, parts: list[Part], sf2: str, tmp: Path) -> np.ndarray:
    mid = tmp / f"{track.id}.mid"
    wav = tmp / f"{track.id}.wav"
    write_midi(mid, track, parts)
    cmd = ["fluidsynth", "-ni", "-q", "-R", "0", "-C", "0", "-g", "0.4", "-r", str(dsp.SR), "-F", str(wav), sf2, str(mid)]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    x = dsp.read(wav)
    if x.ndim == 1:
        x = np.stack([x, x], axis=1)
    want = int(round((track.length_s + track.tail) * dsp.SR))
    return dsp.pad_to(x, want)


def master_track(track: Track, raw: dict[str, np.ndarray], rng) -> dict[str, np.ndarray]:
    """Hall reverb per stem (shared IR), gentle glue compression, one gain for all stems (mix hits the LUFS target,
    true peak of the full mix < -1 dBFS), loop folding."""
    ir = dsp.make_ir(3.2, 2.4, 1.3, rng, predelay_s=0.018,
                     early=[(0.011, 0.5), (0.019, 0.4), (0.027, 0.35), (0.041, 0.3), (0.053, 0.2)], stereo=True)
    proc = {}
    for name, x in raw.items():
        wet = track.stem_wet.get(name, track.wet)
        y = dsp.convolve(x, ir, wet, 1.0)[:len(x)]
        y = dsp.hp(y, 30, 2)
        y = dsp.compress(y, -22, 1.8, 0.02, 0.25)
        proc[name] = y
    loop_n = int(round(track.length_s * dsp.SR))
    if track.loop:
        proc = {k: dsp.fold_tail(v, loop_n) for k, v in proc.items()}
    # stem balance: each stem sits at a fixed loudness relative to the track target (arranger's mix)
    if len(proc) > 1:
        for k in proc:
            off = track.stem_level.get(k, STEM_LEVEL.get(k, -6.0))
            cur = dsp.lufs(proc[k])
            if cur > -60:
                proc[k] = proc[k] * dsp.db(track.lufs + off - cur)
    mix = sum(proc.values())
    g = dsp.db(track.lufs - dsp.lufs(mix))
    tp = dsp.true_peak_db(mix * g)
    if tp > -1.5:
        g *= dsp.db(-1.5 - tp)
    out = {}
    for k, v in proc.items():
        y = v * g
        if dsp.true_peak_db(y) > -1.2:
            y = dsp.limit(y, -1.6)
        out[k] = dsp.fade(y, 0.0, 0.0) if track.loop else dsp.fade(y, 0.0, 0.5)
    return out


def build(out: Path, report: dict, manifest: dict | None = None, only: str | None = None) -> dict:
    sf2 = find_sf2()
    if not shutil.which("fluidsynth") or sf2 is None:
        print("music: fluidsynth or GM soundfont missing (apt install fluidsynth fluid-soundfont-gm) -> skipped")
        return (manifest or {}).get("music", {})
    tracks = compose_all()
    result = dict((manifest or {}).get("music", {}))
    tmp = Path(tempfile.mkdtemp(prefix="frontier_music_"))
    for tid, tr in tracks.items():
        if only and not re.search(only, tid):
            continue
        rng = dsp.rng_for("music_" + tid)
        raw = {name: render_stem(tr, parts, sf2, tmp) for name, parts in tr.stems.items()}
        stems = master_track(tr, raw, rng)
        files = {}
        stat = []
        for name, y in stems.items():
            p = dsp.write(out / "music" / tid / name, y, "ogg", 0.3)
            files[name] = str(p.relative_to(out))
            stat.append({"file": files[name], "dur": round(len(y) / dsp.SR, 2), "true_peak_db": round(dsp.true_peak_db(y), 2),
                         "lufs": round(dsp.lufs(y), 2)})
        mix = sum(stems.values())
        report["music:" + tid] = stat + [{"mix_lufs": round(dsp.lufs(mix), 2), "mix_tp": round(dsp.true_peak_db(mix), 2)}]
        entry = {"kind": tr.kind, "bpm": tr.bpm, "bars": tr.bars, "beats_per_bar": tr.bpb, "length": round(tr.length_s, 3),
                 "loop": tr.loop, "stems": files, "gain_db": tr.gain_db}
        if tr.intensity:
            entry["intensity"] = tr.intensity
        if tr.tags:
            entry["tags"] = tr.tags
        result[tid] = entry
        print(f"  music {tid:28s} {len(files)} stems  {tr.length_s:6.1f}s  mix {dsp.lufs(mix):6.1f} LUFS"
              f"  tp {dsp.true_peak_db(mix):5.1f}", flush=True)
        if manifest is not None and tr.kind == "diegetic":
            # also a mono 3D ambience emitter (room-coloured, a little lo-fi)
            mono = mix.mean(axis=1)
            mono = dsp.peak_eq(dsp.lp(mono, 6500, 2), 900, 2.5, 1.0)
            sp = dsp.write(out / "sfx" / "town" / tid, dsp.normalize(mono, -24.0), "ogg", 0.3)
            manifest["sounds"][tid] = {"category": "amb_loop", "bus": "Ambience", "files": [str(sp.relative_to(out))],
                                       "loop": True, "gain_db": 0.0, "pitch_var": 0.0, "vol_var_db": 0.0,
                                       "max_dist": 45.0, "unit_size": 3.0, "stereo": False, "source": "music"}
    shutil.rmtree(tmp, ignore_errors=True)
    return result
