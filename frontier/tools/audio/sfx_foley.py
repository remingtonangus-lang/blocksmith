"""Foley: footsteps per surface and gait, hoofbeats per surface, tack, bullet impacts, ricochets and whizz-bys,
doors, glass, coins, bodies (original synthesis).

Surfaces (shared with the game, see audio_director.gd SURFACES): dirt, grass, gravel, stone, wood, mud, water, sand,
snow. Footsteps are leather boots with a heel (heel strike + sole roll); hoofbeats are shod hooves (single hit; the
game schedules the gait rhythm: walk 4-beat, trot 2-beat, canter 3-beat, gallop 4-beat with suspension).
"""
from __future__ import annotations

import numpy as np

from dsp import (SR, n_of, t_axis, white, brown, pink, env_exp, env_points, lp, hp, bp, reson, modal, grains,
                 bubble, mix_at, fade, smooth_noise, tv_filter, saturate, peak_eq, db, make_ir, convolve)
from registry import sound

SURFACES = ["dirt", "grass", "gravel", "stone", "wood", "mud", "water", "sand", "snow"]


# ------------------------------------------------------------------------------------------------ surface layers
def thud(n, rng, fc=500, decay=0.018, amp=1.0):
    return lp(white(n, rng), fc, 2) * env_exp(n, decay, 0.001) * amp


def click(n, rng, fc=2500, decay=0.0015, amp=1.0):
    return hp(white(n, rng), fc, 2) * env_exp(n, decay, 0.00005) * amp


def crunch(n, rng, rate, dur, lo, hi, amp=1.0, grain=(0.0004, 0.003)):
    """Granular crunch: grain density AND level follow a fast-attack, smoothly decaying envelope (no hard stop)."""
    t = np.arange(n) / SR
    env = (1 - np.exp(-t / 0.004)) * np.exp(-t / (dur * 0.38))
    return grains(n, rng, rate, grain, lo, hi, env=env) * env * amp * 1.6


def swish(n, rng, dur, lo=2500, hi=9000, amp=1.0):
    m = min(n, n_of(dur))
    e = np.zeros(n)
    e[:m] = np.sin(np.linspace(0, np.pi, m)) ** 2
    return bp(white(n, rng), lo, hi) * e * amp


def plank(n, rng, base=None, amp=1.0, decay=1.0):
    """Boardwalk plank on joists: a few low modes + a hollow cavity boom."""
    b = base or rng.uniform(140, 210)
    modes = [(b, 0.05 * decay, 1.0), (b * 2.3, 0.035 * decay, 0.7), (b * 4.1, 0.025 * decay, 0.5),
             (b * 6.7, 0.015 * decay, 0.35), (b * 9.6, 0.01 * decay, 0.25), (rng.uniform(80, 105), 0.06 * decay, 0.6)]
    return modal(n, modes, rng) * amp


def squelch(n, rng, amp=1.0):
    t = t_axis(n)
    src = lp(white(n, rng), 1500, 2) * env_exp(n, 0.06, 0.004)
    f = 250 + 500 * (1 - np.exp(-t / 0.05))
    x = tv_filter(src, "bandpass", f, order=1, block=64, q=3.0) * 2.5
    for _ in range(rng.integers(2, 5)):
        bt = rng.uniform(0.02, 0.12)
        mix_at(x, bubble(n_of(0.03), rng.uniform(180, 600), rng.uniform(0.006, 0.015), 0.4) * rng.uniform(0.1, 0.4), n_of(bt))
    return x * amp


def splash(n, rng, amp=1.0, size=1.0):
    x = bp(white(n, rng), 300, 5000) * env_exp(n, 0.06 * size, 0.003) * 0.6
    x += hp(white(n, rng), 3500) * env_points(n, [(0, 0), (0.01, 1), (0.12 * size, 0.2), (0.25 * size, 0)]) * 0.25
    for _ in range(int(rng.integers(10, 25) * size)):
        bt = rng.uniform(0.0, 0.18 * size)
        b = bubble(n_of(0.04), rng.uniform(450, 2600) / size ** 0.3, rng.uniform(0.004, 0.02), rng.uniform(0.05, 0.3))
        mix_at(x, b * rng.uniform(0.05, 0.35), n_of(bt))
    return x * amp


def surface_hit(surface: str, rng, n: int, force: float, foot: str = "boot") -> np.ndarray:
    """One contact on a surface. force 0..1.5 (walk ~0.6, run ~1.0, landing 1.4)."""
    f = force
    hard = 1.0 if foot == "hoof" else 0.6
    if surface == "dirt":
        x = thud(n, rng, 450 + 300 * f, 0.016 + 0.01 * f, 1.0) + crunch(n, rng, 2500 * f, 0.07, 1200, 6000, 0.5)
        x += click(n, rng, 1800, 0.001, 0.15 * hard)
    elif surface == "grass":
        x = thud(n, rng, 350 + 200 * f, 0.02, 0.8) + swish(n, rng, 0.09 + 0.05 * f, 2200, 9000, 0.12)
        x += crunch(n, rng, 800 * f, 0.06, 1500, 6000, 0.25)
    elif surface == "gravel":
        x = thud(n, rng, 500, 0.014, 0.6) + crunch(n, rng, 9000 * f, 0.12 + 0.05 * f, 1200, 7500, 1.0,
                                                    (0.0003, 0.0025))
        x += crunch(n, rng, 2500 * f, 0.18, 600, 2500, 0.4, (0.001, 0.004))
    elif surface == "stone":
        x = click(n, rng, 2200, 0.002, 0.9 * hard) + bp(white(n, rng), 700, 3500) * env_exp(n, 0.006) * 0.6
        x += crunch(n, rng, 1500 * f, 0.04, 2500, 8000, 0.25) + thud(n, rng, 300, 0.01, 0.4)
    elif surface == "wood":
        x = click(n, rng, 2000, 0.0012, 0.8) + plank(n, rng, amp=0.55 * (0.7 + 0.5 * f))
        x += thud(n, rng, 260, 0.025, 0.5)
    elif surface == "mud":
        x = squelch(n, rng, 1.0) + thud(n, rng, 300, 0.03, 0.5)
    elif surface == "water":
        x = splash(n, rng, 1.0, 0.7 + 0.4 * f) + thud(n, rng, 250, 0.02, 0.2)
    elif surface == "sand":
        x = thud(n, rng, 350, 0.02, 0.6) + crunch(n, rng, 14000 * f, 0.1, 3000, 10000, 0.35, (0.0002, 0.001))
        x += swish(n, rng, 0.08, 1500, 6000, 0.08)
    elif surface == "snow":
        x = thud(n, rng, 300, 0.03, 0.5) + crunch(n, rng, 5000 * f, 0.14, 700, 4000, 0.9, (0.001, 0.005))
        # squeak: a few short tonal grains
        for _ in range(rng.integers(2, 6)):
            k = n_of(rng.uniform(0.004, 0.012))
            tt = np.arange(k) / SR
            mix_at(x, np.sin(2 * np.pi * rng.uniform(1100, 2200) * tt) * np.hanning(k) * 0.15, n_of(rng.uniform(0.01, 0.1)))
    else:
        x = thud(n, rng)
    return x


# ------------------------------------------------------------------------------------------------ footsteps
def footstep(surface: str, gait: str, rng) -> np.ndarray:
    n = n_of(0.45 if surface not in ("water", "mud") else 0.6)
    force = {"walk": 0.55, "run": 1.0, "land": 1.4, "scuff": 0.3}[gait]
    gap = {"walk": rng.uniform(0.05, 0.08), "run": rng.uniform(0.022, 0.04), "land": rng.uniform(0.012, 0.02),
           "scuff": 0.03}[gait]
    heel = surface_hit(surface, rng, n, force * rng.uniform(0.85, 1.1))
    toe = surface_hit(surface, rng, n, force * 0.55 * rng.uniform(0.8, 1.1))
    if gait == "scuff":
        x = crunch(n, rng, 4000, 0.18, 800, 6000, 0.6) + 0.3 * heel
    else:
        x = heel.copy()
        mix_at(x, toe, n_of(gap), 0.55 if gait != "land" else 0.8)
    if gait == "land":
        x += lp(brown(n, rng), 200) * env_exp(n, 0.04) * 0.6     # body weight
    return fade(x, 0.0005, 0.05)


for _s in SURFACES:
    for _g, _nv in (("walk", 8), ("run", 8), ("land", 3)):
        def _fs(rng, v, s=_s, g=_g):
            return footstep(s, g, rng)
        sound(f"step_{_s}_{_g}", "foot", variations=_nv, max_dist=30 if _g != "land" else 40, unit_size=1.6,
              pitch_var=0.06, vol_var_db=2.0, gain_db=0.0 if _g == "walk" else 2.5, folder="steps",
              tags={"surface": _s, "gait": _g})(_fs)


@sound("spur_jingle", "foley", variations=6, max_dist=12, unit_size=1.0, gain_db=-8.0, folder="steps")
def spur_jingle(rng, v):
    n = n_of(0.35)
    out = np.zeros(n)
    base = rng.uniform(3800, 5200)
    for k in range(rng.integers(2, 4)):
        modes = [(base * r * rng.uniform(0.98, 1.02), rng.uniform(0.04, 0.12), a)
                 for r, a in ((1, 1), (1.73, .6), (2.62, .45), (3.9, .3))]
        hit = modal(n_of(0.25), modes, rng) * 0.3 + click(n_of(0.25), rng, 4000, 0.0006, 0.4)
        mix_at(out, hit, n_of(k * rng.uniform(0.02, 0.06)), rng.uniform(0.4, 1.0))
    return fade(out, 0.0, 0.05)


@sound("cloth_rustle", "foley", variations=6, max_dist=8, unit_size=1.0, gain_db=-6.0, folder="steps")
def cloth_rustle(rng, v):
    n = n_of(rng.uniform(0.25, 0.5))
    e = np.sin(np.linspace(0, np.pi, n)) ** 1.5 * (1 + 0.5 * smooth_noise(n, 25, rng))
    x = bp(white(n, rng), 800, 6000) * e * 0.3 + grains(n, rng, 1500, (0.001, 0.004), 400, 3000) * e * 0.4
    return fade(x)


# ------------------------------------------------------------------------------------------------ hooves
def hoof(surface: str, rng, force: float) -> np.ndarray:
    n = n_of(0.5 if surface not in ("water", "mud") else 0.7)
    x = surface_hit(surface, rng, n, force, foot="hoof")
    # weight of a 500 kg animal: a low thump into the ground
    t = t_axis(n)
    f = rng.uniform(55, 75) * (1 + 0.6 * np.exp(-t / 0.01))
    weight = np.sin(np.cumsum(f) / SR * 2 * np.pi) * env_exp(n, 0.018 + 0.008 * force, 0.002) * 0.7
    weight += lp(white(n, rng), 180, 2) * env_exp(n, 0.03, 0.002) * 2.0     # the ground itself, not a tone
    soft = {"grass": 0.8, "dirt": 1.0, "sand": 0.7, "mud": 0.6, "water": 0.4, "snow": 0.6}.get(surface, 0.7)
    x += weight * 0.5 * soft * force
    # the hoof wall itself: hollow "clop" (horn + iron shoe), clearest on hard ground
    clear = {"stone": 1.0, "wood": 0.8, "gravel": 0.45, "dirt": 0.3, "sand": 0.1, "grass": 0.12}.get(surface, 0.0)
    if clear > 0:
        b = rng.uniform(700, 1100)
        clop = modal(n, [(b, 0.012, 1.0), (b * 2.4, 0.007, 0.5), (b * 0.55, 0.018, 0.5)], rng)
        clop += bp(white(n, rng), 500, 3000) * env_exp(n, 0.004) * 0.8
        x += clop * 0.6 * clear * force
    if surface in ("stone", "wood", "gravel"):
        shoe = modal(n, [(rng.uniform(3000, 4200) * r, 0.01, a) for r, a in ((1, 1), (1.6, .5), (2.7, .3))], rng)
        x += shoe * 0.12 * force
    return fade(x, 0.0005, 0.06)


for _s in SURFACES:
    for _k, _f in (("soft", 0.65), ("hard", 1.15)):
        def _hf(rng, v, s=_s, f=_f):
            return hoof(s, rng, f * rng.uniform(0.9, 1.1))
        sound(f"hoof_{_s}_{_k}", "hoof", variations=8, max_dist=70, unit_size=3.0, pitch_var=0.07, vol_var_db=2.5,
              folder="hooves", tags={"surface": _s, "force": _k})(_hf)


# ------------------------------------------------------------------------------------------------ tack and horse body
def stick_slip(n, rng, rate_hz, resonances, amp=1.0, irregular=0.6):
    """Leather/wood friction creak: an irregular pulse train exciting a few resonances."""
    out = np.zeros(n)
    t = 0.0
    while t < n / SR:
        i = n_of(t)
        mix_at(out, np.array([1.0, -0.6, 0.2]), i, rng.uniform(0.4, 1.0))
        r = rate_hz[min(i, n - 1)] if hasattr(rate_hz, "__len__") else rate_hz
        t += (1.0 / max(r, 20)) * (1 + irregular * rng.uniform(-1, 1))
    y = np.zeros(n)
    for f, q, g in resonances:
        y += reson(out, f, q, g)
    return y * amp


@sound("saddle_creak", "tack", variations=8, max_dist=15, unit_size=1.5, pitch_var=0.08, folder="horse")
def saddle_creak(rng, v):
    n = n_of(rng.uniform(0.35, 0.8))
    e = np.sin(np.linspace(0, np.pi, n)) ** 1.2
    rate = 90 + 160 * e * rng.uniform(0.6, 1.2)
    res = [(rng.uniform(250, 380), 6, 1.0), (rng.uniform(650, 900), 8, 0.7), (rng.uniform(1400, 1900), 10, 0.4)]
    x = stick_slip(n, rng, rate, res) * e
    return fade(x)


@sound("bridle_jingle", "tack", variations=6, max_dist=15, unit_size=1.5, folder="horse")
def bridle_jingle(rng, v):
    n = n_of(0.5)
    out = np.zeros(n)
    for _ in range(rng.integers(2, 6)):
        b = rng.uniform(2200, 4200)
        hit = modal(n_of(0.3), [(b, rng.uniform(0.05, 0.15), 1), (b * 2.1, 0.06, .5), (b * 3.3, 0.03, .3)], rng)
        mix_at(out, hit * 0.3 + click(n_of(0.3), rng, 3000, 0.0005, 0.3), n_of(rng.uniform(0, 0.25)), rng.uniform(0.3, 1))
    return fade(out, 0.0, 0.05)


@sound("horse_breath", "horse", variations=6, max_dist=20, unit_size=2.0, folder="horse", gain_db=-6.0)
def horse_breath(rng, v):
    """Synthesised fallback (recordings preferred): nostril air through two resonant tubes."""
    n = n_of(rng.uniform(0.9, 1.4))
    e = env_points(n, [(0, 0), (0.15, 1), (n / SR * 0.6, 0.7), (n / SR, 0)])
    x = bp(pink(n, rng), 300, 2500) * e
    x = x + 1.5 * reson(x, rng.uniform(450, 600), 4) + 0.8 * reson(x, rng.uniform(1200, 1500), 5)
    return fade(x * 0.3, 0.02, 0.1)


@sound("horse_snort", "horse", variations=5, max_dist=35, unit_size=2.5, folder="horse")
def horse_snort(rng, v):
    """Synthesised fallback: a sharp nasal blow with lip/nostril flutter."""
    n = n_of(rng.uniform(0.5, 0.8))
    t = t_axis(n)
    e = env_points(n, [(0, 0), (0.02, 1), (0.25, 0.6), (n / SR, 0)])
    flutter = 1 + 0.9 * np.sin(2 * np.pi * rng.uniform(28, 45) * t + 3 * smooth_noise(n, 8, rng))
    x = bp(white(n, rng), 200, 3500) * e * np.maximum(flutter, 0)
    x = x + reson(x, rng.uniform(380, 520), 3) * 1.5 + reson(x, rng.uniform(900, 1200), 4)
    return fade(saturate(x * 0.5, 1.5), 0.002, 0.08)


@sound("horse_whinny_synth", "horse", variations=3, max_dist=150, unit_size=5.0, folder="horse")
def horse_whinny(rng, v):
    """Synthesised fallback whinny: tremulous harmonic call with nasal formants (recordings preferred)."""
    from dsp import glottal, formants
    dur = rng.uniform(1.2, 1.7)
    n = n_of(dur)
    t = t_axis(n)
    f0 = env_points(n, [(0, 500), (0.12, 1150), (0.5, 1000), (dur * 0.8, 650), (dur, 380)])
    trem = 1 + 0.07 * np.sin(2 * np.pi * (11 + 3 * t) * t)
    src = glottal(f0 * trem, n, rng, jitter=0.02, shimmer=0.15, tilt=1.2)
    x = formants(src, [(1100, 250, 0), (2300, 300, -6), (3500, 400, -12)])
    e = env_points(n, [(0, 0), (0.05, 1), (dur * 0.7, 0.8), (dur, 0)]) * (1 + 0.4 * np.sin(2 * np.pi * 9 * t))
    x = x * e + bp(white(n, rng), 1000, 4000) * e * 0.05
    return fade(x, 0.005, 0.15)


# ------------------------------------------------------------------------------------------------ bullets
@sound("bullet_dirt", "impact", variations=6, max_dist=60, unit_size=2.0, folder="impacts")
def bullet_dirt(rng, v):
    n = n_of(0.6)
    x = click(n, rng, 1500, 0.002, 0.8) + thud(n, rng, 700, 0.02, 1.0)
    fall = np.zeros(n)
    env = env_points(n, [(0, 0), (0.02, 1), (0.12, 0.35), (0.3, 0.1), (0.55, 0)])
    fall = grains(n, rng, 2500, (0.0005, 0.003), 1000, 6000, env=env) * env * 0.6     # dirt spray pattering down
    return fade(x + fall, 0.0, 0.05)


@sound("bullet_wood", "impact", variations=6, max_dist=60, unit_size=2.0, folder="impacts")
def bullet_wood(rng, v):
    n = n_of(0.45)
    x = click(n, rng, 2500, 0.0015, 1.0) + plank(n, rng, base=rng.uniform(250, 420), amp=0.6, decay=0.6)
    x += crunch(n, rng, 6000, 0.06, 1500, 7000, 0.6)
    return fade(x, 0.0, 0.05)


@sound("bullet_metal", "impact", variations=6, max_dist=90, unit_size=3.0, folder="impacts")
def bullet_metal(rng, v):
    n = n_of(1.0)
    b = rng.uniform(900, 1800)
    ratios = sorted(rng.uniform(1, 9, 9))
    modes = [(b * r, rng.uniform(0.08, 0.5) / r ** 0.3, rng.uniform(0.2, 1) / r ** 0.5) for r in ratios]
    x = modal(n, modes, rng) * 0.5 + click(n, rng, 3000, 0.001, 1.0) + thud(n, rng, 900, 0.006, 0.3)
    return fade(x, 0.0, 0.1)


@sound("bullet_flesh", "impact", variations=6, max_dist=40, unit_size=1.5, folder="impacts")
def bullet_flesh(rng, v):
    n = n_of(0.3)
    x = thud(n, rng, 280, 0.025, 1.0) + bp(white(n, rng), 400, 2500) * env_exp(n, 0.008) * 0.5
    x += squelch(n, rng, 0.2)
    return fade(x, 0.0, 0.04)


@sound("bullet_stone", "impact", variations=6, max_dist=80, unit_size=2.0, folder="impacts")
def bullet_stone(rng, v):
    n = n_of(0.5)
    x = click(n, rng, 2500, 0.0025, 1.0) + crunch(n, rng, 5000, 0.1, 2500, 9000, 0.7)
    x += modal(n, [(rng.uniform(2200, 3600), 0.03, 0.3), (rng.uniform(4500, 6000), 0.02, 0.2)], rng)
    return fade(x, 0.0, 0.05)


@sound("bullet_water", "impact", variations=5, max_dist=50, unit_size=2.0, folder="impacts")
def bullet_water(rng, v):
    n = n_of(0.6)
    x = click(n, rng, 2000, 0.001, 0.5) + splash(n, rng, 1.0, 0.8)
    return fade(x, 0.0, 0.05)


@sound("ricochet", "bullet", variations=8, max_dist=150, unit_size=4.0, pitch_var=0.08, folder="impacts")
def ricochet(rng, v):
    dur = rng.uniform(0.45, 0.9)
    n = n_of(dur + 0.1)
    t = t_axis(n)
    f0 = rng.uniform(3200, 4600)
    f1 = f0 * rng.uniform(0.3, 0.5)
    f = f1 + (f0 - f1) * np.exp(-t / (dur * 0.45))
    tumble = 1 + 0.5 * np.sin(2 * np.pi * rng.uniform(25, 70) * t)
    e = env_points(n, [(0, 0), (0.01, 1), (dur * 0.3, 0.7), (dur, 0)])
    tone = np.sin(np.cumsum(f * (1 + 0.01 * np.sin(2 * np.pi * 40 * t))) / SR * 2 * np.pi)
    hiss = tv_filter(white(n, rng), "bandpass", f, order=1, block=128, q=4.0)
    x = (tone * 0.35 + hiss * 0.9) * e * tumble
    x += click(n, rng, 2500, 0.002, 0.8)
    return fade(x, 0.0, 0.05)


@sound("whizz", "bullet", variations=8, max_dist=12, unit_size=1.5, pitch_var=0.1, folder="impacts")
def whizz(rng, v):
    n = n_of(0.35)
    t = t_axis(n)
    c = 0.12
    e = np.exp(-((t - c) / 0.04) ** 2)
    f = 1600 * (1 + 0.5 * np.tanh(-(t - c) / 0.02)) + 800
    x = tv_filter(white(n, rng), "bandpass", f, order=1, block=64, q=2.5) * e
    return fade(x, 0.002, 0.05)


@sound("crack_by", "bullet", variations=6, max_dist=12, unit_size=1.5, pitch_var=0.05, folder="impacts")
def crack_by(rng, v):
    """Supersonic rifle bullet passing close: a sharp snap, then the whizz of the wake."""
    n = n_of(0.3)
    tt = t_axis(n) * 1000
    nwave = np.where(tt < 0.5, 1 - 2 * tt / 0.5, 0.0)
    x = lp(nwave, 15000) * 1.0 + click(n, rng, 3000, 0.002, 0.6)
    w = whizz(rng, v)[:n] * 0.4
    mix_at(x, w, n_of(0.005) - n_of(0.12) + n_of(0.03), 1.0)
    return fade(x, 0.0, 0.05)


# ------------------------------------------------------------------------------------------------ bodies and fists
@sound("body_fall", "foley", variations=4, max_dist=40, unit_size=2.0, folder="impacts")
def body_fall(rng, v):
    n = n_of(0.9)
    x = thud(n, rng, 220, 0.06, 1.0) + crunch(n, rng, 2500, 0.15, 800, 4000, 0.4)
    mix_at(x, thud(n_of(0.3), rng, 300, 0.03, 0.5), n_of(rng.uniform(0.12, 0.2)))
    mix_at(x, cloth_rustle(rng, v)[:n_of(0.3)] * 0.5, n_of(0.02))
    return fade(x, 0.0, 0.1)


@sound("punch", "foley", variations=6, max_dist=25, unit_size=1.5, folder="impacts")
def punch(rng, v):
    n = n_of(0.3)
    x = thud(n, rng, 600, 0.02, 1.0) + bp(white(n, rng), 500, 3000) * env_exp(n, 0.006) * 0.6
    x += lp(brown(n, rng), 150) * env_exp(n, 0.04) * 0.5
    return fade(saturate(x, 1.5), 0.0, 0.04)


# ------------------------------------------------------------------------------------------------ doors, glass, coins
@sound("door_open", "foley", variations=4, max_dist=30, unit_size=2.0, folder="foley")
def door_open(rng, v):
    dur = rng.uniform(0.7, 1.3)
    n = n_of(dur + 0.2)
    e = env_points(n, [(0, 0), (0.08, 1), (dur * 0.6, 0.8), (dur, 0)])
    rate = 120 + 500 * env_points(n, [(0, 0.2), (dur * 0.5, 1.0), (dur, 0.4)]) * rng.uniform(0.6, 1.2)
    creak = stick_slip(n, rng, rate, [(rng.uniform(500, 800), 12, 1.0), (rng.uniform(1300, 1800), 14, 0.6),
                                      (rng.uniform(2600, 3200), 16, 0.3)], irregular=0.25) * e
    latch = np.zeros(n)
    mix_at(latch, click(n_of(0.1), rng, 1500, 0.003, 1.0) + plank(n_of(0.1), rng, 300, 0.3, 0.4), 0)
    return fade(creak * 0.7 * rng.uniform(0.3, 1.0) + latch * 0.6, 0.0, 0.05)


@sound("door_close", "foley", variations=4, max_dist=40, unit_size=2.0, folder="foley")
def door_close(rng, v):
    n = n_of(0.7)
    x = plank(n, rng, rng.uniform(90, 140), 1.0, 1.5) + thud(n, rng, 300, 0.05, 0.7) + click(n, rng, 1800, 0.003, 0.5)
    mix_at(x, click(n_of(0.1), rng, 2500, 0.002, 0.4), n_of(0.04))
    ir = make_ir(0.5, 0.4, 0.25, rng, stereo=False)
    return fade(convolve(x, ir, 0.12, 1.0), 0.0, 0.08)


@sound("saloon_doors", "foley", variations=3, max_dist=35, unit_size=2.0, folder="foley")
def saloon_doors(rng, v):
    """Bat-wing doors swinging shut: decaying flaps of light wood + hinge squeaks."""
    n = n_of(1.6)
    out = np.zeros(n)
    t = 0.0
    a = 1.0
    gap = rng.uniform(0.28, 0.36)
    while a > 0.08 and t < 1.4:
        hit = plank(n_of(0.2), rng, rng.uniform(220, 320), 0.6, 0.5) + click(n_of(0.2), rng, 1500, 0.002, 0.4)
        mix_at(out, hit, n_of(t), a)
        mix_at(out, hit * 0.7, n_of(t + rng.uniform(0.01, 0.03)), a * 0.8)   # the second wing
        t += gap
        gap *= 0.82
        a *= 0.55
    sq = stick_slip(n_of(0.4), rng, 300, [(1800, 15, 1.0), (3200, 15, 0.4)], irregular=0.2)
    sq *= np.sin(np.linspace(0, np.pi, len(sq)))
    mix_at(out, sq * 0.25, 0)
    return fade(out, 0.0, 0.1)


@sound("glass_break", "foley", variations=4, max_dist=40, unit_size=2.0, folder="foley")
def glass_break(rng, v):
    n = n_of(1.2)
    x = click(n, rng, 2500, 0.003, 1.0) + bp(white(n, rng), 1500, 9000) * env_exp(n, 0.03) * 0.5
    for _ in range(rng.integers(25, 45)):
        tt = rng.uniform(0, 0.8) ** 1.6
        b = rng.uniform(2500, 9000)
        sh = modal(n_of(0.15), [(b, rng.uniform(0.01, 0.05), 1), (b * rng.uniform(1.4, 2.6), 0.02, 0.5)], rng)
        mix_at(x, sh * rng.uniform(0.05, 0.3) * np.exp(-tt * 2), n_of(tt))
    return fade(x, 0.0, 0.1)


@sound("bottle_clink", "foley", variations=4, max_dist=15, unit_size=1.0, folder="foley")
def bottle_clink(rng, v):
    n = n_of(0.6)
    b = rng.uniform(1800, 2600)
    x = modal(n, [(b, 0.15, 1), (b * 2.32, 0.08, 0.5), (b * 4.1, 0.05, 0.3), (b * 0.5, 0.06, 0.2)], rng) * 0.5
    x += click(n, rng, 3000, 0.0008, 0.6)
    return fade(x, 0.0, 0.05)


@sound("glass_set_down", "foley", variations=4, max_dist=12, unit_size=1.0, folder="foley")
def glass_set_down(rng, v):
    n = n_of(0.4)
    x = plank(n, rng, rng.uniform(300, 400), 0.4, 0.3) + modal(n, [(rng.uniform(2500, 3500), 0.05, 0.3)], rng)
    x += click(n, rng, 2000, 0.0015, 0.5)
    return fade(x, 0.0, 0.05)


def coin_hit(rng, n, amp=1.0):
    b = rng.uniform(4500, 7000)
    return (modal(n, [(b, rng.uniform(0.05, 0.2), 1), (b * 1.83, 0.08, .6), (b * 2.9, 0.05, .3)], rng) * 0.4
            + click(n, rng, 4000, 0.0004, 0.5)) * amp


@sound("coin_drop", "foley", variations=4, max_dist=12, unit_size=1.0, folder="foley")
def coin_drop(rng, v):
    n = n_of(1.0)
    out = np.zeros(n)
    t, gap, a = 0.0, rng.uniform(0.12, 0.18), 1.0
    while t < 0.7 and a > 0.03:
        mix_at(out, coin_hit(rng, n_of(0.25)), n_of(t), a)
        t += gap
        gap *= 0.7
        a *= 0.75
    return fade(out, 0.0, 0.05)


@sound("coins_jingle", "foley", variations=4, max_dist=10, unit_size=1.0, folder="foley")
def coins_jingle(rng, v):
    n = n_of(0.6)
    out = np.zeros(n)
    for _ in range(rng.integers(8, 16)):
        mix_at(out, coin_hit(rng, n_of(0.25), rng.uniform(0.2, 0.8)), n_of(rng.uniform(0, 0.35)))
    out += grains(n, rng, 500, (0.001, 0.003), 400, 2000) * np.sin(np.linspace(0, np.pi, n)) * 0.2  # purse leather
    return fade(out, 0.0, 0.05)


@sound("register_ding", "foley", variations=2, max_dist=25, unit_size=1.5, folder="foley")
def register_ding(rng, v):
    n = n_of(1.4)
    b = rng.uniform(2000, 2300)
    x = modal(n, [(b, 0.6, 1), (b * 2.76, 0.3, .4), (b * 5.4, 0.15, .2)], rng) * 0.6 + click(n, rng, 2000, 0.002, 0.3)
    drawer = np.zeros(n)
    mix_at(drawer, crunch(n_of(0.3), rng, 3000, 0.25, 500, 3000, 0.5) + plank(n_of(0.3), rng, 200, 0.4, 0.4), n_of(0.15))
    return fade(x + drawer, 0.0, 0.1)


@sound("lantern_creak", "foley", variations=3, max_dist=10, unit_size=1.0, folder="foley")
def lantern_creak(rng, v):
    n = n_of(0.6)
    x = stick_slip(n, rng, 200, [(2400, 12, 1.0), (3800, 12, 0.5)], irregular=0.3) * np.sin(np.linspace(0, np.pi, n))
    return fade(x * 0.5)
