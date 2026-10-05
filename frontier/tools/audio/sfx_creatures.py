"""Creatures (original synthesis): insects (cricket chorus, cicadas, grasshoppers), birds (FM/whistle/formant call
types, species-like but invented), frogs (chorus trills, bullfrog), owls and poorwill at night, coyotes and wolves
(formant howls, distance-processed), elk bugle; synthesised fallbacks for cattle and dog (recordings preferred).
"""
from __future__ import annotations

import math

import numpy as np

from dsp import (SR, n_of, t_axis, white, pink, brown, env_exp, env_points, lp, hp, bp, reson, modal, grains, mix_at,
                 fade, smooth_noise, periodic_smooth_noise, make_loop, make_ir, convolve, glottal, formants,
                 pan_stereo, harmonic, phase_of, fm, saturate)
from registry import sound

LOOP_S = 40.0
XF = 2.0


def distant(x, rng, dist=1.0, rt=1.6):
    """Air absorption + outdoor reverb for faraway animals (dist 0..1.5)."""
    y = lp(x, 6000 * math.exp(-dist * 1.2) + 600, 2)
    ir = make_ir(rt * 1.3, rt, rt * 0.5, rng, stereo=False, density_lp=3000)
    return convolve(y, ir, 0.25 + 0.3 * dist, 1.0 - 0.3 * dist)


# ------------------------------------------------------------------------------------------------ insects
def cricket(n, rng, f, chirp_rate, pulses, pulse_rate, offset):
    t = t_axis(n)
    out = np.zeros(n)
    carrier = np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28))
    per = 1.0 / chirp_rate
    pl = 0.6 / pulse_rate
    tt = offset
    while tt < n / SR:
        for k in range(pulses):
            a = n_of(tt + k / pulse_rate)
            m = n_of(pl)
            if a + m < n:
                out[a:a + m] += np.hanning(m) * rng.uniform(0.7, 1.0)
        tt += per * rng.uniform(0.97, 1.03)
    return carrier * out


@sound("crickets_night", "amb_loop", loop=True, stereo=True, folder="creatures", target=-28.0)
def crickets_night(rng, v):
    n = n_of(LOOP_S + XF)
    out = np.zeros((n, 2))
    for i in range(22):
        r = np.random.default_rng(rng.integers(1 << 30))
        f = r.uniform(3900, 5200)
        x = cricket(n, r, f, r.uniform(1.3, 2.6), int(r.integers(2, 5)), r.uniform(22, 34), r.uniform(0, 1))
        d = r.uniform(0.3, 1.0)        # distance factor
        x = lp(x, 9000 - 4000 * d) * (1.1 - d) ** 1.5
        out += pan_stereo(x, np.full(n, r.uniform(-1, 1))) * 0.3
    # a far, continuous trilling layer (tree crickets)
    for c in range(2):
        r = np.random.default_rng(rng.integers(1 << 30))
        tr = np.sin(2 * np.pi * r.uniform(2700, 3100) * t_axis(n)) * (0.5 + 0.5 * np.sin(2 * np.pi * 45 * t_axis(n)))
        out[:, c] += tr * 0.03 * (1 + 0.3 * periodic_smooth_noise(n, 0.2, r))
    return make_loop(out, XF)


@sound("cicadas_day", "amb_loop", loop=True, stereo=True, folder="creatures", target=-30.0)
def cicadas_day(rng, v):
    """Buzzing swells (several insects, 3-8 s calls rising and falling) over a soft bed."""
    n = n_of(LOOP_S + XF)
    out = np.zeros((n, 2))
    t = 0.0
    while t < LOOP_S + XF - 1:
        r = np.random.default_rng(rng.integers(1 << 30))
        dur = r.uniform(3, 8)
        m = n_of(dur)
        tt = t_axis(m)
        am = 0.5 + 0.5 * np.sin(2 * np.pi * r.uniform(90, 170) * tt)
        e = env_points(m, [(0, 0), (dur * 0.3, 1), (dur * 0.8, 0.9), (dur, 0)])
        x = bp(white(m, r), r.uniform(4000, 5000), r.uniform(6500, 8500)) * am * e
        x = lp(x, r.uniform(7000, 10000))
        pan = r.uniform(-0.9, 0.9)
        mix_at(out, pan_stereo(x, np.full(m, pan)) * r.uniform(0.2, 0.6), n_of(t))
        t += r.uniform(2, 6)
    for c in range(2):
        r = np.random.default_rng(rng.integers(1 << 30))
        out[:, c] += bp(white(n, r), 4500, 7000) * 0.02
    return make_loop(out, XF)


@sound("grasshoppers", "amb_loop", loop=True, stereo=True, folder="creatures", target=-34.0)
def grasshoppers(rng, v):
    """Dry ticking/stridulating in the prairie grass at midday."""
    n = n_of(LOOP_S + XF)
    out = np.zeros((n, 2))
    for i in range(10):
        r = np.random.default_rng(rng.integers(1 << 30))
        x = np.zeros(n)
        t = r.uniform(0, 3)
        while t < LOOP_S + XF - 1:
            burst = r.uniform(0.3, 1.5)
            rate = r.uniform(15, 40)
            k = 0.0
            while k < burst:
                m = n_of(0.004)
                mix_at(x, r.standard_normal(m) * np.hanning(m), n_of(t + k), r.uniform(0.5, 1))
                k += 1 / rate
            t += burst + r.uniform(1, 6)
        x = bp(x, 5000, 12000)
        out += pan_stereo(x, np.full(n, r.uniform(-1, 1))) * r.uniform(0.2, 0.5)
    return make_loop(out, XF)


# ------------------------------------------------------------------------------------------------ birds
def whistle(f_contour, amp_env, rng, h2=0.08, h3=0.02, breath=0.01):
    n = len(f_contour)
    ph = phase_of(f_contour)
    x = np.sin(ph) + h2 * np.sin(2 * ph) + h3 * np.sin(3 * ph)
    x += bp(white(n, rng), 2000, 9000) * breath
    return x * amp_env


def note(f0, f1, dur, rng, shape="lin", vib=0.0, vib_rate=0.0, attack=0.01, release=0.02, h2=0.08):
    n = n_of(dur)
    t = t_axis(n)
    if shape == "lin":
        f = np.linspace(f0, f1, n)
    elif shape == "exp":
        f = f0 * (f1 / f0) ** (t / dur)
    else:  # arch
        f = f0 + (f1 - f0) * np.sin(np.pi * t / dur)
    if vib:
        f = f * (1 + vib * np.sin(2 * np.pi * vib_rate * t))
    e = np.minimum(1, np.minimum(t / max(attack, 1e-4), (dur - t) / max(release, 1e-4)))
    e = np.clip(e, 0, 1) ** 1.5
    return whistle(f, e, rng, h2=h2)


def phrase(parts, rng):
    """parts: [(start_s, signal)] -> mono."""
    end = max(s + len(x) / SR for s, x in parts) + 0.05
    out = np.zeros(n_of(end))
    for s, x in parts:
        mix_at(out, x, n_of(s))
    return out


def bird_out(x, rng, dist):
    return fade(distant(x, rng, dist, rt=1.2), 0.002, 0.1)


@sound("bird_meadow", "creature", variations=5, max_dist=250, unit_size=8.0, folder="birds", pitch_var=0.03)
def bird_meadow(rng, v):
    """Flute-like descending song of 6-9 slurred notes (open grassland)."""
    parts, t = [], 0.0
    f = rng.uniform(3200, 3900)
    for k in range(int(rng.integers(6, 10))):
        dur = rng.uniform(0.06, 0.16) if k > 0 else 0.25
        f2 = f * rng.uniform(0.8, 1.05)
        parts.append((t, note(f, f2, dur, rng, "lin", 0.01, 30, 0.01, 0.03)))
        t += dur + rng.uniform(0.01, 0.05)
        f = f2 if rng.uniform() > 0.3 else f * rng.uniform(1.05, 1.25)
    return bird_out(phrase(parts, rng) * 0.6, rng, rng.uniform(0.2, 0.7))


@sound("bird_feebee", "creature", variations=4, max_dist=200, unit_size=6.0, folder="birds", pitch_var=0.03)
def bird_feebee(rng, v):
    """Two clear whistled notes, the second lower (woodland)."""
    f = rng.uniform(3600, 4100)
    a = note(f, f * 0.99, rng.uniform(0.3, 0.4), rng, attack=0.04, release=0.05, h2=0.02)
    b = note(f * 0.84, f * 0.8, rng.uniform(0.3, 0.4), rng, attack=0.03, release=0.08, h2=0.02)
    return bird_out(phrase([(0, a), (len(a) / SR + 0.06, b)], rng) * 0.5, rng, rng.uniform(0.3, 0.8))


@sound("bird_trill", "creature", variations=5, max_dist=150, unit_size=5.0, folder="birds", pitch_var=0.04)
def bird_trill(rng, v):
    """Rapid trill of short down-slurred syllables, slowing and dropping (wren/junco-like)."""
    parts, t = [], 0.0
    f = rng.uniform(4500, 6000)
    rate = rng.uniform(14, 22)
    for k in range(int(rng.integers(10, 22))):
        dur = 0.6 / rate
        parts.append((t, note(f, f * 0.7, dur, rng, attack=0.003, release=0.01, h2=0.15)))
        t += 1 / rate
        f *= rng.uniform(0.985, 1.0)
        rate *= 0.99
    return bird_out(phrase(parts, rng) * 0.5, rng, rng.uniform(0.2, 0.7))


@sound("bird_warble", "creature", variations=5, max_dist=180, unit_size=6.0, folder="birds", pitch_var=0.03)
def bird_warble(rng, v):
    """Caroling phrases of 2-3 rising/falling syllables (robin-like)."""
    parts, t = [], 0.0
    for p in range(int(rng.integers(3, 6))):
        base = rng.uniform(2200, 3200)
        for s in range(int(rng.integers(2, 4))):
            dur = rng.uniform(0.07, 0.14)
            shape = rng.choice(["lin", "arch"])
            f1 = base * rng.uniform(1.1, 1.4)
            parts.append((t, note(base, f1, dur, rng, shape, attack=0.006, release=0.02, h2=0.12)))
            t += dur + 0.02
        t += rng.uniform(0.2, 0.45)
    return bird_out(phrase(parts, rng) * 0.5, rng, rng.uniform(0.2, 0.7))


@sound("bird_chip", "creature", variations=4, max_dist=80, unit_size=3.0, folder="birds", pitch_var=0.05)
def bird_chip(rng, v):
    parts, t = [], 0.0
    for k in range(int(rng.integers(2, 6))):
        f = rng.uniform(5000, 7000)
        parts.append((t, note(f, f * 0.75, 0.02, rng, attack=0.002, release=0.008, h2=0.2)))
        t += rng.uniform(0.15, 0.6)
    return bird_out(phrase(parts, rng) * 0.5, rng, 0.3)


def harsh(f0, dur, rng, fmts, rough=0.4, noise=0.3):
    n = n_of(dur)
    t = t_axis(n)
    src = glottal(f0, n, rng, jitter=0.05, shimmer=0.3, tilt=0.7)
    src *= 1 + rough * np.sin(2 * np.pi * rng.uniform(50, 80) * t)
    src += white(n, rng) * noise
    return formants(src, fmts)


@sound("bird_caw", "creature", variations=5, max_dist=400, unit_size=10.0, folder="birds", pitch_var=0.04)
def bird_caw(rng, v):
    """Corvid: 2-4 harsh 'kraa' calls."""
    parts, t = [], 0.0
    for k in range(int(rng.integers(2, 5))):
        dur = rng.uniform(0.25, 0.4)
        n = n_of(dur)
        f0 = env_points(n, [(0, rng.uniform(380, 450)), (dur * 0.3, rng.uniform(480, 560)), (dur, rng.uniform(300, 380))])
        x = harsh(f0, dur, rng, [(1250, 250, 0), (1800, 300, -2), (3000, 500, -10)])
        x *= env_points(n, [(0, 0), (0.02, 1), (dur * 0.7, 0.8), (dur, 0)])
        parts.append((t, x))
        t += dur + rng.uniform(0.15, 0.35)
    return bird_out(phrase(parts, rng) * 0.4, rng, rng.uniform(0.3, 0.9))


@sound("bird_hawk", "creature", variations=4, max_dist=600, unit_size=15.0, folder="birds", pitch_var=0.03)
def bird_hawk(rng, v):
    """Raptor scream: a long hoarse descending 'kee-eeerr'."""
    dur = rng.uniform(1.3, 2.0)
    n = n_of(dur)
    f0 = env_points(n, [(0, 2400), (0.12, 3100), (dur * 0.5, 2700), (dur, 1700)]) * rng.uniform(0.9, 1.1)
    x = harsh(f0, dur, rng, [(3000, 600, 0), (5200, 900, -8)], rough=0.6, noise=0.5)
    x *= env_points(n, [(0, 0), (0.08, 1), (dur * 0.6, 0.8), (dur, 0)])
    return bird_out(x * 0.4, rng, rng.uniform(0.5, 1.0))


@sound("bird_dove", "creature", variations=4, max_dist=150, unit_size=5.0, folder="birds", pitch_var=0.02)
def bird_dove(rng, v):
    """Soft mournful cooing: 'coo-OOO-oo  oo  oo'."""
    f = rng.uniform(430, 520)
    seq = [(0.0, 0.45, 1.0, 1.25), (0.55, 0.6, 1.25, 1.1), (1.35, 0.35, 1.0, 0.97), (1.85, 0.35, 1.0, 0.97),
           (2.35, 0.35, 1.0, 0.96)]
    parts = []
    for s, d, a, b in seq:
        x = note(f * a, f * b, d, rng, "arch", attack=0.08, release=0.15, h2=0.25)
        x = lp(x + bp(white(len(x), rng), 300, 1200) * 0.03, 1800)
        parts.append((s, x))
    return bird_out(phrase(parts, rng) * 0.7, rng, rng.uniform(0.2, 0.5))


@sound("bird_quail", "creature", variations=4, max_dist=150, unit_size=5.0, folder="birds", pitch_var=0.03)
def bird_quail(rng, v):
    """Three-note call 'chi-CA-go' (desert scrub)."""
    f = rng.uniform(1500, 1900)
    a = note(f, f * 1.1, 0.09, rng, attack=0.01, release=0.02, h2=0.3)
    b = note(f * 1.35, f * 1.6, 0.16, rng, "arch", attack=0.01, release=0.03, h2=0.3)
    c = note(f * 1.3, f * 1.05, 0.12, rng, attack=0.01, release=0.04, h2=0.3)
    return bird_out(phrase([(0, a), (0.13, b), (0.33, c)], rng) * 0.5, rng, rng.uniform(0.2, 0.6))


@sound("bird_woodpecker", "creature", variations=4, max_dist=200, unit_size=6.0, folder="birds", pitch_var=0.05)
def bird_woodpecker(rng, v):
    """Drumming on dead wood: a fast roll of knocks."""
    out = np.zeros(n_of(1.2))
    rate = rng.uniform(16, 24)
    k = int(rng.integers(12, 24))
    f = rng.uniform(700, 1100)
    for i in range(k):
        m = n_of(0.05)
        knock = modal(m, [(f, 0.01, 1), (f * 2.3, 0.006, 0.4)], rng) + hp(white(m, rng), 2000) * env_exp(m, 0.001)
        mix_at(out, knock, n_of(i / rate), 1 - 0.3 * i / k)
    return bird_out(out * 0.6, rng, rng.uniform(0.3, 0.8))


@sound("owl_hoot", "creature", variations=4, max_dist=400, unit_size=10.0, folder="birds", pitch_var=0.02)
def owl_hoot(rng, v):
    """Deep rhythmic hoots 'hoo-h'HOO--hoo-hoo' at night."""
    f = rng.uniform(330, 400)
    seq = [(0.0, 0.18), (0.3, 0.12), (0.5, 0.5), (1.25, 0.25), (1.6, 0.25)]
    parts = []
    for s, d in seq:
        x = note(f, f * 0.95, d, rng, attack=0.04, release=0.08, h2=0.35)
        parts.append((s, lp(x, 1500)))
    return bird_out(phrase(parts, rng) * 0.8, rng, rng.uniform(0.4, 1.0))


@sound("poorwill", "creature", variations=3, max_dist=250, unit_size=8.0, folder="birds", pitch_var=0.02)
def poorwill(rng, v):
    """Night bird of the dry country: repeated two-part whistle 'poor-WILL'."""
    parts, t = [], 0.0
    for k in range(int(rng.integers(3, 6))):
        f = rng.uniform(1700, 1900)
        parts.append((t, note(f, f * 1.02, 0.12, rng, attack=0.02, release=0.03, h2=0.1)))
        parts.append((t + 0.2, note(f * 1.15, f * 0.95, 0.22, rng, "arch", attack=0.02, release=0.06, h2=0.1)))
        t += rng.uniform(0.9, 1.3)
    return bird_out(phrase(parts, rng) * 0.6, rng, rng.uniform(0.4, 1.0))


# ------------------------------------------------------------------------------------------------ frogs
def chorus_trill(n, rng, start, dur, f, rate0, rate1):
    """One chorus-frog 'crreeeek': pulses accelerating, carrier with formant."""
    out = np.zeros(n)
    t = 0.0
    while t < dur:
        rate = rate0 + (rate1 - rate0) * t / dur
        m = n_of(0.006)
        a = n_of(start + t)
        if a + m < n:
            out[a:a + m] += np.hanning(m)
        t += 1 / rate
    car = np.sin(2 * np.pi * f * t_axis(n) + rng.uniform(0, 6))
    return out * car


@sound("frogs_night", "amb_loop", loop=True, stereo=True, folder="creatures", target=-27.0)
def frogs_night(rng, v):
    n = n_of(LOOP_S + XF)
    out = np.zeros((n, 2))
    for i in range(14):
        r = np.random.default_rng(rng.integers(1 << 30))
        x = np.zeros(n)
        f = r.uniform(2300, 3200)
        t = r.uniform(0, 2)
        per = r.uniform(0.8, 1.6)
        while t < LOOP_S + XF - 1:
            if r.uniform() < 0.85:
                x += chorus_trill(n, r, t, r.uniform(0.35, 0.6), f, 25, 60)
            t += per * r.uniform(0.85, 1.15)
            if r.uniform() < 0.05:
                t += r.uniform(3, 8)
        d = r.uniform(0.2, 1.0)
        x = lp(x, 8000 - 4000 * d) * (1.1 - d)
        out += pan_stereo(x, np.full(n, r.uniform(-1, 1))) * 0.35
    ir = make_ir(1.5, 1.2, 0.6, rng, stereo=True)
    out = convolve(out, ir, 0.2, 1.0)[:n]
    return make_loop(out, XF)


@sound("bullfrog", "creature", variations=4, max_dist=200, unit_size=6.0, folder="creatures", pitch_var=0.04)
def bullfrog(rng, v):
    """Deep 'jug-o-rum': 2-4 low resonant croaks."""
    parts, t = [], 0.0
    for k in range(int(rng.integers(2, 5))):
        dur = rng.uniform(0.4, 0.7)
        n = n_of(dur)
        f0 = np.full(n, rng.uniform(95, 130)) * (1 + 0.05 * np.sin(np.linspace(0, np.pi, n)))
        src = glottal(f0, n, rng, 0.03, 0.2, 0.9)
        src *= 1 + 0.6 * np.sin(2 * np.pi * rng.uniform(18, 26) * t_axis(n))
        x = formants(src, [(220, 60, 0), (480, 120, -3), (1200, 200, -12)])
        x *= env_points(n, [(0, 0), (0.04, 1), (dur * 0.7, 0.8), (dur, 0)])
        parts.append((t, x))
        t += dur + rng.uniform(0.15, 0.3)
    return fade(distant(phrase(parts, rng), rng, 0.4, 1.0) * 0.6, 0.005, 0.1)


# ------------------------------------------------------------------------------------------------ canids, elk
def howl(rng, dur, f_lo, f_hi, voice="wolf"):
    n = n_of(dur)
    t = t_axis(n)
    rise = rng.uniform(0.2, 0.5)
    f0 = env_points(n, [(0, f_lo), (rise, f_hi), (dur * 0.75, f_hi * rng.uniform(0.9, 1.0)), (dur, f_lo * 0.8)])
    f0 *= 1 + 0.012 * np.sin(2 * np.pi * rng.uniform(4.5, 6) * t) + 0.01 * smooth_noise(n, 3, rng)
    src = glottal(f0, n, rng, jitter=0.006, shimmer=0.05, tilt=1.6)
    # vowel moves oo -> ah -> oo
    o = env_points(n, [(0, 0), (rise, 1), (dur * 0.7, 0.8), (dur, 0)])
    oo = formants(src, [(350, 100, 0), (800, 150, -8), (2400, 250, -18)])
    ah = formants(src, [(750, 120, 0), (1200, 150, -5), (2600, 250, -15)])
    x = oo * (1 - o) + ah * o
    e = env_points(n, [(0, 0), (0.15, 0.6), (rise, 1), (dur * 0.85, 0.85), (dur, 0)])
    return x * e + bp(white(n, rng), 800, 3000) * e * 0.01


@sound("wolf_howl", "creature", variations=4, max_dist=3000, unit_size=60.0, folder="creatures", pitch_var=0.03)
def wolf_howl(rng, v):
    parts = [(0.0, howl(rng, rng.uniform(3.0, 4.5), rng.uniform(280, 340), rng.uniform(430, 520)))]
    if rng.uniform() < 0.7:
        parts.append((rng.uniform(1.5, 3.0), howl(rng, rng.uniform(2.5, 3.5), 320, rng.uniform(520, 600)) * 0.7))
    x = phrase(parts, rng)
    return fade(distant(x, rng, rng.uniform(0.8, 1.3), 2.5) * 0.5, 0.01, 0.4)


@sound("coyote_chorus", "creature", variations=4, max_dist=3000, unit_size=60.0, folder="creatures", pitch_var=0.04)
def coyote_chorus(rng, v):
    """Yip-howl group: quavering short howls breaking into yips and barks, several animals."""
    parts = []
    for a in range(int(rng.integers(2, 5))):
        t = rng.uniform(0, 1.5)
        base = rng.uniform(600, 850)
        for k in range(int(rng.integers(3, 8))):
            kind = rng.uniform()
            if kind < 0.35:
                d = rng.uniform(0.6, 1.4)
                x = howl(rng, d, base * 0.8, base * rng.uniform(1.25, 1.5), "coyote")
                n = len(x)
                x *= 1 + 0.5 * np.sin(2 * np.pi * rng.uniform(7, 12) * t_axis(n))   # quaver
            else:
                d = rng.uniform(0.06, 0.15)
                n = n_of(d)
                f0 = env_points(n, [(0, base * 1.3), (d, base * rng.uniform(0.8, 1.0))])
                x = formants(glottal(f0, n, rng, 0.02, 0.2, 1.0), [(900, 200, 0), (1700, 250, -6)])
                x *= np.hanning(n)
            parts.append((t, x * rng.uniform(0.5, 1.0)))
            t += d + rng.uniform(0.05, 0.3)
    x = phrase(parts, rng)
    return fade(distant(x, rng, rng.uniform(0.8, 1.3), 2.0) * 0.45, 0.01, 0.4)


@sound("elk_bugle", "creature", variations=3, max_dist=3000, unit_size=60.0, folder="creatures", pitch_var=0.03)
def elk_bugle(rng, v):
    """Autumn rut bugle in the high meadows: low growl rising to a pure high whistle, then grunts."""
    dur = rng.uniform(2.2, 3.2)
    n = n_of(dur)
    t = t_axis(n)
    f = env_points(n, [(0, 250), (0.4, 700), (0.7, 1500), (dur * 0.7, 1700), (dur * 0.85, 1100), (dur, 300)])
    whistle_part = np.sin(phase_of(f)) * env_points(n, [(0, 0), (0.5, 0.3), (0.8, 1), (dur * 0.8, 0.9), (dur, 0)])
    growl = formants(glottal(np.full(n, 90.0), n, rng, 0.05, 0.3, 0.8), [(400, 100, 0), (900, 150, -5)])
    growl *= env_points(n, [(0, 0), (0.1, 1), (0.6, 0.2), (dur * 0.85, 0.1), (dur, 0.8)])
    x = whistle_part * 0.6 + growl * 0.3 + bp(white(n, rng), 1000, 3000) * whistle_part * 0.05
    grunts = []
    for k in range(int(rng.integers(2, 5))):
        m = n_of(0.15)
        g = formants(glottal(np.full(m, 110.0), m, rng, 0.05, 0.3, 0.8), [(500, 120, 0)]) * np.hanning(m)
        grunts.append((dur + 0.1 + k * 0.28, g * 0.5))
    x = phrase([(0, x)] + grunts, rng)
    return fade(distant(x, rng, rng.uniform(0.7, 1.2), 2.5) * 0.5, 0.01, 0.4)


# ------------------------------------------------------------------------------------------------ farm (synth fallbacks)
@sound("cattle_moo_synth", "creature", variations=4, max_dist=500, unit_size=12.0, folder="creatures")
def cattle_moo(rng, v):
    dur = rng.uniform(1.2, 2.2)
    n = n_of(dur)
    f0 = env_points(n, [(0, rng.uniform(95, 115)), (0.3, rng.uniform(130, 160)), (dur * 0.8, 140), (dur, 100)])
    src = glottal(f0, n, rng, 0.02, 0.15, 1.0)
    o = env_points(n, [(0, 0), (0.35, 1), (dur * 0.7, 1), (dur, 0.2)])
    mm = formants(src, [(300, 80, 0), (900, 120, -12)])
    ah = formants(src, [(650, 110, 0), (1100, 130, -4), (2400, 200, -12)])
    x = mm * (1 - o) + ah * o
    x *= env_points(n, [(0, 0), (0.1, 0.8), (dur * 0.8, 1), (dur, 0)])
    return fade(distant(x, rng, 0.4, 1.2) * 0.5, 0.01, 0.2)


@sound("dog_bark_synth", "creature", variations=4, max_dist=500, unit_size=10.0, folder="creatures")
def dog_bark(rng, v):
    parts, t = [], 0.0
    for k in range(int(rng.integers(1, 4))):
        d = rng.uniform(0.12, 0.2)
        n = n_of(d)
        f0 = env_points(n, [(0, rng.uniform(450, 600)), (d * 0.3, rng.uniform(600, 750)), (d, 350)])
        src = glottal(f0, n, rng, 0.05, 0.3, 0.8) + white(n, rng) * 0.4
        x = formants(src, [(700, 200, 0), (1500, 300, -3), (2800, 400, -10)])
        x *= env_points(n, [(0, 0), (0.008, 1), (d * 0.5, 0.6), (d, 0)])
        parts.append((t, saturate(x, 2.0)))
        t += d + rng.uniform(0.15, 0.4)
    return fade(distant(phrase(parts, rng), rng, 0.5, 1.0) * 0.5, 0.002, 0.1)


@sound("rooster", "creature", variations=2, max_dist=800, unit_size=15.0, folder="creatures")
def rooster(rng, v):
    """Homestead morning crow 'cock-a-doodle-doo' (harsh harmonic, four syllables)."""
    segs = [(0.0, 0.15, 650, 750), (0.2, 0.15, 800, 850), (0.42, 0.2, 900, 950), (0.7, 0.9, 1000, 700)]
    parts = []
    for s, d, a, b in segs:
        n = n_of(d)
        f0 = env_points(n, [(0, a), (d * 0.3, (a + b) / 2 * 1.08), (d, b)])
        x = harsh(f0, d, rng, [(1400, 300, 0), (2600, 400, -4), (3800, 500, -10)], rough=0.5, noise=0.2)
        x *= env_points(n, [(0, 0), (0.02, 1), (d * 0.8, 0.8), (d, 0)])
        parts.append((s, x))
    return fade(distant(phrase(parts, rng), rng, 0.5, 1.4) * 0.4, 0.005, 0.2)
