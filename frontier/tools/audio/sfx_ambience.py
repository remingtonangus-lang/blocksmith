"""Ambience beds and weather (original synthesis): wind (several characters, all loopable and gusty), rain, rain on a
roof, thunder (physically modelled: N-waves from a tortuous lightning channel), river/creek/lake shore, fire,
crowd murmur (formant babble), town one-shots (anvil, church bell, wagon, train whistle).
Loops are stereo, seamless (periodic modulators + equal-power crossfade at the seam).
"""
from __future__ import annotations

import math

import numpy as np

from dsp import (SR, n_of, t_axis, white, pink, brown, env_exp, env_points, lp, hp, bp, reson, tv_filter, modal,
                 grains, bubble, mix_at, fade, smooth_noise, periodic_smooth_noise, make_loop, make_ir, convolve,
                 glottal, formants, pan_stereo, to_stereo, saturate, peak_eq, shelf, onepole_lp)
from registry import sound

LOOP_S = 48.0   # default loop length (plus crossfade)
XF = 2.0


def _stereo_pair(fn, n, rng):
    """Two decorrelated renders of the same recipe -> stereo."""
    return np.stack([fn(n, np.random.default_rng(rng.integers(1 << 30))),
                     fn(n, np.random.default_rng(rng.integers(1 << 30)))], axis=1)


# ------------------------------------------------------------------------------------------------ wind
def wind_layer(n, rng, gust, lo, hi, q=1.2, base=0.35):
    """Noise through a band-pass whose centre and level follow the gust envelope."""
    src = pink(n, rng)
    g = np.clip(gust, 0, 1)
    fc = lo + (hi - lo) * g
    x = tv_filter(src, "bandpass", fc, order=1, block=256, q=q)
    return x * (base + (1 - base) * g ** 1.5)


def gust_env(n, rng, rate, depth, bias):
    slow = periodic_smooth_noise(n, rate, rng)
    fast = periodic_smooth_noise(n, rate * 4, rng) * 0.3
    return np.clip(bias + depth * (slow + fast) * 0.5, 0, 1)


def wind(rng, strength: float, whistle: float = 0.0, rumble: float = 0.4, rate: float = 0.12, hiss: float = 0.0,
         seconds: float = LOOP_S) -> np.ndarray:
    n = n_of(seconds + XF)
    out = np.zeros((n, 2))
    gust_common = gust_env(n, rng, rate, 1.4 * strength, 0.25 + 0.35 * strength)
    for c in range(2):
        r = np.random.default_rng(rng.integers(1 << 30))
        g = np.clip(gust_common * 0.75 + 0.25 * gust_env(n, r, rate * 1.7, 1.0, 0.4), 0, 1)
        x = wind_layer(n, r, g, 180, 900 + 900 * strength, q=0.9) * 1.0
        x += lp(brown(n, r), 160) * (0.3 + g) * rumble
        if whistle > 0:
            wf = 650 + 700 * g + 80 * periodic_smooth_noise(n, 1.5, r)
            w = tv_filter(white(n, r), "bandpass", wf, order=2, block=128, q=28.0)
            w2 = tv_filter(white(n, r), "bandpass", wf * 1.52, order=2, block=128, q=34.0)
            x += (w * 4 + w2 * 2) * np.clip(g - 0.45, 0, 1) ** 1.5 * whistle
        if hiss > 0:
            x += hp(white(n, r), 3000) * g ** 2 * hiss * 0.25
        out[:, c] = x
    return make_loop(out, XF)


@sound("wind_calm", "amb_loop", loop=True, stereo=True, folder="amb", target=-30.0)
def wind_calm(rng, v):
    return wind(rng, 0.25, rumble=0.25, rate=0.08)


@sound("wind_gusty", "amb_loop", loop=True, stereo=True, folder="amb", target=-23.0)
def wind_gusty(rng, v):
    return wind(rng, 0.85, whistle=0.15, rumble=0.6, rate=0.15)


@sound("wind_mountain", "amb_loop", loop=True, stereo=True, folder="amb", target=-24.0)
def wind_mountain(rng, v):
    return wind(rng, 0.7, whistle=0.8, rumble=0.5, rate=0.1)


@sound("wind_dust", "amb_loop", loop=True, stereo=True, folder="amb", target=-21.0)
def wind_dust(rng, v):
    """Dust storm: strong wind + sand hiss + grit pelting."""
    x = wind(rng, 1.0, whistle=0.2, rumble=0.7, rate=0.2, hiss=1.0)
    n = len(x)
    for c in range(2):
        r = np.random.default_rng(rng.integers(1 << 30))
        x[:, c] += grains(n, r, 3000, (0.0002, 0.001), 3000, 11000) * 0.25
    return x


@sound("wind_trees", "amb_loop", loop=True, stereo=True, folder="amb", target=-28.0)
def wind_trees(rng, v):
    """Foliage rustle (pine needles hiss + aspen leaf flutter), modulated by gusts."""
    n = n_of(LOOP_S + XF)
    out = np.zeros((n, 2))
    gust = gust_env(n, rng, 0.12, 1.2, 0.35)
    for c in range(2):
        r = np.random.default_rng(rng.integers(1 << 30))
        g = np.clip(gust * 0.7 + 0.3 * gust_env(n, r, 0.3, 1.0, 0.4), 0, 1)
        pine = bp(white(n, r), 2500, 9000) * (0.15 + g ** 1.5) * 0.35
        flutter = grains(n, r, 1800, (0.002, 0.008), 1200, 6000, env=0.2 + g ** 2) * 0.5
        out[:, c] = pine + flutter * (0.3 + g)
    return make_loop(out, XF)


@sound("wind_grass", "amb_loop", loop=True, stereo=True, folder="amb", target=-30.0)
def wind_grass(rng, v):
    """Prairie: dry grass hiss in waves."""
    n = n_of(LOOP_S + XF)
    out = np.zeros((n, 2))
    gust = gust_env(n, rng, 0.1, 1.2, 0.3)
    for c in range(2):
        r = np.random.default_rng(rng.integers(1 << 30))
        g = np.clip(np.roll(gust, c * n_of(0.6)), 0, 1)
        out[:, c] = bp(white(n, r), 1800, 8000) * (0.1 + g ** 1.8) * 0.5 + grains(n, r, 900, (0.001, 0.004), 2000, 7000,
                                                                                 env=0.1 + g ** 2) * 0.3
    return make_loop(out, XF)


@sound("wind_interior", "amb_loop", loop=True, stereo=True, folder="amb", target=-34.0)
def wind_interior(rng, v):
    """Wind heard from inside a timber building: muffled moan + occasional board rattles."""
    x = wind(rng, 0.7, whistle=0.4, rumble=0.8, rate=0.12)
    x = lp(x, 700, 2)
    n = len(x)
    for _ in range(int(rng.integers(6, 12))):
        at = rng.integers(0, n - n_of(0.3))
        k = n_of(0.25)
        rat = grains(k, rng, 120, (0.002, 0.006), 300, 2500) * 2
        x[at:at + k, int(rng.integers(0, 2))] += rat * 0.3
    return x


# ------------------------------------------------------------------------------------------------ rain and thunder
def drops(n, rng, rate, lo, hi, size=(0.0003, 0.0015)):
    return grains(n, rng, rate, size, lo, hi)


@sound("rain_light", "amb_loop", loop=True, stereo=True, folder="weather", target=-28.0)
def rain_light(rng, v):
    n = n_of(LOOP_S + XF)
    out = np.zeros((n, 2))
    for c in range(2):
        r = np.random.default_rng(rng.integers(1 << 30))
        sheet = bp(pink(n, r), 1500, 9000) * 0.08
        d = drops(n, r, 1800, 1500, 9000) * 0.6
        big = np.zeros(n)
        for _ in range(int(LOOP_S * 25)):
            at = int(r.integers(0, n - 2000))
            big[at:at + 600] += bubble(600, r.uniform(1500, 4000), r.uniform(0.002, 0.006), 0.3) * r.uniform(0.05, 0.25)
        out[:, c] = sheet + d + big
    return make_loop(out, XF)


@sound("rain_heavy", "amb_loop", loop=True, stereo=True, folder="weather", target=-21.0)
def rain_heavy(rng, v):
    n = n_of(LOOP_S + XF)
    out = np.zeros((n, 2))
    surge = periodic_smooth_noise(n, 0.08, rng) * 0.25 + 1.0
    for c in range(2):
        r = np.random.default_rng(rng.integers(1 << 30))
        sheet = bp(pink(n, r), 600, 10000) * 0.35
        d = drops(n, r, 9000, 1000, 9000) * 0.7
        low = lp(brown(n, r), 300) * 0.15
        out[:, c] = (sheet + d + low) * surge
    return make_loop(out, XF)


@sound("rain_roof", "amb_loop", loop=True, stereo=True, folder="weather", target=-26.0)
def rain_roof(rng, v):
    """Rain on a shingle roof heard from inside: dull ticks with board resonance + gutter dripping."""
    n = n_of(LOOP_S + XF)
    out = np.zeros((n, 2))
    for c in range(2):
        r = np.random.default_rng(rng.integers(1 << 30))
        ticks = drops(n, r, 4000, 300, 3500, (0.0008, 0.003))
        board = reson(ticks, r.uniform(180, 260), 4) * 1.5 + reson(ticks, r.uniform(500, 700), 6)
        drip = np.zeros(n)
        per = r.uniform(0.35, 0.6)
        t = 0.0
        while t < n / SR - 0.1:
            mix_at(drip, bubble(n_of(0.05), r.uniform(900, 1400), 0.012, 0.6) * r.uniform(0.1, 0.3), n_of(t))
            t += per * r.uniform(0.7, 1.3)
        out[:, c] = lp(ticks * 0.6 + board * 0.5, 4000) + drip * 0.5 + lp(pink(n, r), 500) * 0.05
    return make_loop(out, XF)


def thunder(rng, dist_m: float, seconds: float) -> np.ndarray:
    """Superposition of N-waves from a random-walk lightning channel; arrival time and darkness from distance."""
    n = n_of(seconds)
    out = np.zeros(n)
    # channel: 400 segments from ~2.5 km altitude down to the ground near (dist_m, 0)
    segs = 400
    p = np.array([dist_m + rng.uniform(-300, 300), 2500.0, rng.uniform(-300, 300)])
    pts = []
    for i in range(segs):
        step = np.array([rng.normal(0, 18), -2500.0 / segs, rng.normal(0, 18)])
        p = p + step
        pts.append(p.copy())
        if rng.uniform() < 0.02:   # branches
            q = p.copy()
            for _ in range(int(rng.integers(10, 40))):
                q = q + np.array([rng.normal(0, 20), -rng.uniform(2, 8), rng.normal(0, 20)])
                pts.append(q.copy())
    pts = np.array(pts)
    d = np.linalg.norm(pts, axis=1)
    t0 = d.min() / 343.0
    for di in d:
        at = di / 343.0 - t0 + 0.05
        if at > seconds - 0.2:
            continue
        width = 0.002 + di / 343.0 * 0.0012          # longer, softer N-waves from farther segments
        m = n_of(width)
        nw = np.linspace(1, -1, m) * rng.uniform(0.5, 1.0) / (di / 1000.0)
        mix_at(out, nw, n_of(at))
    out = lp(out, 4000 * math.exp(-dist_m / 2500.0) + 150, 2)
    # atmospheric reverberation
    ir = make_ir(3.0, 3.5, 1.5, rng, stereo=True, density_lp=2500)
    y = convolve(out, ir, 0.5, 1.0)[:n]
    y = hp(y, 25, 2)
    return fade(y, 0.0, 0.8)


@sound("thunder_close", "weather", variations=3, max_dist=8000, unit_size=1000, stereo=True, folder="weather")
def thunder_close(rng, v):
    return thunder(rng, rng.uniform(400, 900), 9.0)


@sound("thunder_far", "weather", variations=4, max_dist=8000, unit_size=1000, stereo=True, folder="weather",
       target=-22.0)
def thunder_far(rng, v):
    return thunder(rng, rng.uniform(2500, 5000), 12.0)


# ------------------------------------------------------------------------------------------------ water
def babble(n, rng, rate, flo, fhi, dlo=0.004, dhi=0.03, amp=(0.02, 0.2)):
    out = np.zeros(n)
    k = int(rate * n / SR)
    pos = rng.integers(0, n - n_of(0.08), k)
    for p in pos:
        f = math.exp(rng.uniform(math.log(flo), math.log(fhi)))
        d = rng.uniform(dlo, dhi) * (600 / f) ** 0.5
        m = n_of(min(0.08, d * 5))
        out[p:p + m] += bubble(m, f, d, rng.uniform(0.05, 0.4)) * rng.uniform(*amp)
    return out


@sound("river", "amb_loop", loop=True, stereo=True, folder="water", target=-24.0)
def river(rng, v):
    n = n_of(LOOP_S + XF)
    out = np.zeros((n, 2))
    for c in range(2):
        r = np.random.default_rng(rng.integers(1 << 30))
        mod = 1 + 0.15 * periodic_smooth_noise(n, 0.3, r)
        roar = lp(pink(n, r), 1600, 2) * 0.5 * mod + lp(brown(n, r), 250) * 0.25
        out[:, c] = roar + babble(n, r, 220, 250, 1800) * 1.2 + hp(white(n, r), 4000) * 0.02
    return make_loop(out, XF)


@sound("creek", "amb_loop", loop=True, stereo=True, folder="water", target=-26.0)
def creek(rng, v):
    n = n_of(LOOP_S + XF)
    out = np.zeros((n, 2))
    for c in range(2):
        r = np.random.default_rng(rng.integers(1 << 30))
        trickle = babble(n, r, 450, 600, 4000, 0.002, 0.012, (0.03, 0.25))
        out[:, c] = trickle + bp(pink(n, r), 500, 5000) * 0.06 + babble(n, r, 40, 200, 600) * 0.5
    return make_loop(out, XF)


@sound("lake_shore", "amb_loop", loop=True, stereo=True, folder="water", target=-27.0)
def lake_shore(rng, v):
    """Gentle laps every 4-7 s: swell, wash with bubbles over pebbles, receding hiss."""
    n = n_of(LOOP_S + XF)
    out = np.zeros((n, 2))
    t = 0.0
    while t < LOOP_S + XF - 1:
        dur = rng.uniform(2.5, 4.0)
        m = n_of(dur)
        e = env_points(m, [(0, 0), (dur * 0.25, 0.4), (dur * 0.35, 1.0), (dur * 0.6, 0.5), (dur, 0)])
        for c in range(2):
            r = np.random.default_rng(rng.integers(1 << 30))
            wash = bp(pink(m, r), 300, 6000) * e * 0.3
            peb = grains(m, r, 2500, (0.0005, 0.002), 2000, 8000, env=e * np.linspace(0.3, 1, m)) * 0.25
            bub = babble(m, r, 150, 500, 3000) * e * 0.8
            mix_at(out[:, c], wash + peb + bub, n_of(t + c * 0.05), rng.uniform(0.6, 1.0))
        t += rng.uniform(4.0, 7.0)
    for c in range(2):
        r = np.random.default_rng(rng.integers(1 << 30))
        out[:, c] += lp(pink(n, r), 600) * 0.02
    return make_loop(out, XF)


@sound("water_lap_boat", "amb_loop", loop=True, stereo=True, folder="water", target=-30.0)
def water_lap_boat(rng, v):
    """Small slaps against a pier/hull (Port Linden docks)."""
    n = n_of(LOOP_S + XF)
    out = np.zeros((n, 2))
    t = 0.0
    while t < LOOP_S + XF - 0.5:
        r = np.random.default_rng(rng.integers(1 << 30))
        m = n_of(0.4)
        slap = bp(white(m, r), 200, 2500) * env_exp(m, 0.03) + reson(white(m, r) * env_exp(m, 0.01), 180, 5) * 0.5
        slap += babble(m, r, 80, 400, 2000) * 0.5
        mix_at(out[:, int(r.integers(0, 2))], slap, n_of(t), r.uniform(0.3, 1.0))
        t += r.uniform(0.4, 1.6)
    return make_loop(out, XF)


# ------------------------------------------------------------------------------------------------ fire
def fire(rng, size: float) -> np.ndarray:
    n = n_of(LOOP_S + XF)
    out = np.zeros((n, 2))
    for c in range(2):
        r = np.random.default_rng(rng.integers(1 << 30))
        roar = lp(brown(n, r), 220 * size + 60) * (1 + 0.3 * periodic_smooth_noise(n, 0.8, r)) * 0.5 * size
        hiss = bp(white(n, r), 2000, 6000) * (0.4 + 0.6 * np.clip(periodic_smooth_noise(n, 0.3, r), 0, 1)) * 0.03
        pops = np.zeros(n)
        k = int(LOOP_S * 9 * size)
        for _ in range(k):
            at = int(r.integers(0, n - 2000))
            a = r.pareto(2.5) * 0.08 + 0.02
            m = n_of(r.uniform(0.0005, 0.004))
            pop = r.standard_normal(m) * np.exp(-np.linspace(0, 5, m))
            pops[at:at + m] += pop * min(a, 1.0)
            if a > 0.25:   # a resonant snap of a splitting stick
                mm = n_of(0.03)
                pops[at:at + mm] += reson(r.standard_normal(mm) * np.exp(-np.linspace(0, 8, mm)), r.uniform(800, 2500), 6) * a
        out[:, c] = roar + hiss + hp(pops, 700) * 0.8
    return make_loop(out, XF)


@sound("fire_camp", "amb_loop", loop=True, stereo=True, folder="amb", max_dist=25, unit_size=2.0, target=-24.0)
def fire_camp(rng, v):
    return fire(rng, 1.0)


@sound("fire_stove", "amb_loop", loop=True, stereo=True, folder="amb", max_dist=10, unit_size=1.0, target=-30.0)
def fire_stove(rng, v):
    x = fire(rng, 0.5)
    return lp(x, 2500) + reson(x, 120, 3) * 0.3


# ------------------------------------------------------------------------------------------------ voices (babble)
VOWELS = {  # F1, F2, F3 (Hz), adult male; scaled for women
    "a": (730, 1090, 2440), "e": (530, 1840, 2480), "i": (270, 2290, 3010), "o": (570, 840, 2410),
    "u": (300, 870, 2240), "ae": (660, 1720, 2410), "uh": (520, 1190, 2390), "er": (490, 1350, 1690),
}


def talker(n, rng, female: bool, rate: float = 4.5, talk_frac: float = 0.65) -> np.ndarray:
    """One murmuring voice: glottal source with intonation, syllable AM, vowel formants per syllable, consonant noise."""
    t = t_axis(n)
    base = rng.uniform(175, 235) if female else rng.uniform(95, 135)
    # phrases: speak / pause
    gate = np.zeros(n)
    pos = 0.0
    phrase_starts = []
    while pos < n / SR:
        ln = rng.uniform(1.0, 3.5)
        if rng.uniform() < talk_frac:
            a, b = n_of(pos), min(n, n_of(pos + ln))
            gate[a:b] = 1
            phrase_starts.append((pos, ln))
        pos += ln + rng.uniform(0.2, 1.2)
    gate = onepole_lp(gate, 8)
    f0 = np.full(n, base)
    for (p0, ln) in phrase_starts:
        a, b = n_of(p0), min(n, n_of(p0 + ln))
        f0[a:b] *= np.linspace(1.12, 0.9, b - a)    # declination
    f0 *= 1 + 0.08 * smooth_noise(n, 2.5, rng)
    src = glottal(f0, n, rng, jitter=0.015, shimmer=0.1, tilt=1.4)
    # syllables: vowels change at syllable rate, AM envelope
    syl = rate * (1 + 0.2 * smooth_noise(n, 0.5, rng))
    ph = np.cumsum(syl) / SR
    am = (0.5 - 0.5 * np.cos(2 * np.pi * ph)) ** 1.5
    idx = np.floor(ph).astype(int)
    keys = list(VOWELS)
    seq = rng.integers(0, len(keys), idx.max() + 2)
    out = np.zeros(n)
    scale = 1.17 if female else 1.0
    # render per vowel with masks (cheap: 8 filters, crossfaded masks)
    for k, key in enumerate(keys):
        mask = (seq[idx] == k).astype(float)
        mask = onepole_lp(mask, 30)
        if mask.max() < 0.01:
            continue
        f1, f2, f3 = (f * scale for f in VOWELS[key])
        out += formants(src * mask, [(f1, 90, 0), (f2, 120, -6), (f3, 180, -12)])
    cons = hp(white(n, rng), 2500) * np.maximum(0, np.cos(2 * np.pi * ph)) ** 8 * 0.15
    return (out * am + cons) * gate


def laugh(n, rng, female: bool) -> np.ndarray:
    dur = n / SR
    base = rng.uniform(220, 300) if female else rng.uniform(130, 170)
    k = int(rng.integers(4, 8))
    rate = rng.uniform(4.5, 6.0)
    t = t_axis(n)
    f0 = base * (1.3 - 0.3 * t / dur)
    src = glottal(f0, n, rng, 0.03, 0.2, 1.2) + white(n, rng) * 0.3
    am = np.maximum(0, np.sin(2 * np.pi * rate * t)) ** 2 * (t < k / rate)
    x = formants(src, [(800, 120, 0), (1300, 150, -4), (2600, 200, -10)]) * am
    return x * np.exp(-t / (k / rate))


def crowd(rng, talkers: int, female_frac: float, laughs: int, room_rt: float, muffle: float) -> np.ndarray:
    n = n_of(LOOP_S + XF)
    out = np.zeros((n, 2))
    for i in range(talkers):
        r = np.random.default_rng(rng.integers(1 << 30))
        fem = r.uniform() < female_frac
        x = talker(n, r, fem) * r.uniform(0.4, 1.0)
        pan = r.uniform(-0.8, 0.8)
        out += pan_stereo(x, np.full(n, pan)) * 0.5
    for _ in range(laughs):
        r = np.random.default_rng(rng.integers(1 << 30))
        m = n_of(r.uniform(1.0, 2.0))
        lx = laugh(m, r, r.uniform() < female_frac)
        at = int(r.integers(0, n - m))
        out[at:at + m] += pan_stereo(lx, np.full(m, r.uniform(-0.7, 0.7))) * r.uniform(0.4, 0.9)
    ir = make_ir(room_rt * 1.5, room_rt, room_rt * 0.6, rng, stereo=True)
    out = convolve(out, ir, 0.35, 1.0)[:n]
    out = lp(out, muffle, 2)
    return make_loop(out, XF)


@sound("crowd_saloon", "amb_loop", loop=True, stereo=True, folder="town", target=-26.0)
def crowd_saloon(rng, v):
    return crowd(rng, 18, 0.2, 10, 0.7, 6000)


@sound("crowd_street", "amb_bed", loop=True, stereo=True, folder="town", target=-32.0)
def crowd_street(rng, v):
    return crowd(rng, 8, 0.4, 2, 0.3, 3500)


@sound("crowd_church", "amb_bed", loop=True, stereo=True, folder="town", target=-34.0)
def crowd_church(rng, v):
    return crowd(rng, 10, 0.5, 0, 1.6, 2500)


# ------------------------------------------------------------------------------------------------ town one-shots
@sound("anvil", "foley", variations=4, max_dist=150, unit_size=4.0, folder="town")
def anvil(rng, v):
    n = n_of(2.0)
    b = rng.uniform(900, 1300)
    ratios = [1.0, 2.04, 2.71, 3.95, 5.2, 6.8]
    x = modal(n, [(b * r * rng.uniform(0.99, 1.01), rng.uniform(0.3, 1.2) / r ** 0.4, 1 / r ** 0.6) for r in ratios], rng)
    x = x * 0.4 + hp(white(n, rng), 2000) * env_exp(n, 0.002) * 0.8
    return fade(x, 0.0, 0.2)


@sound("hammer_wood", "foley", variations=4, max_dist=120, unit_size=3.0, folder="town")
def hammer_wood(rng, v):
    n = n_of(0.5)
    from sfx_foley import plank, click
    x = click(n, rng, 2000, 0.0015, 1.0) + plank(n, rng, rng.uniform(250, 380), 0.7, 0.8)
    x += modal(n, [(rng.uniform(3500, 4500), 0.02, 0.15)], rng)
    return fade(x, 0.0, 0.05)


@sound("church_bell", "foley", variations=2, max_dist=2500, unit_size=60.0, folder="town")
def church_bell(rng, v):
    """Bronze bell partials (hum, prime, tierce, quint, nominal...) with slow beating."""
    n = n_of(7.0)
    f = rng.uniform(310, 360)
    parts = [(0.5, 4.5, 0.5), (1.0, 3.5, 0.8), (1.2, 2.6, 0.6), (1.5, 2.0, 0.35), (2.0, 2.2, 0.9), (2.5, 1.2, 0.3),
             (2.67, 1.0, 0.25), (3.0, 0.8, 0.2), (4.0, 0.6, 0.15)]
    x = np.zeros(n)
    t = t_axis(n)
    for r, d, a in parts:
        x += a * np.exp(-t / d) * (np.sin(2 * np.pi * f * r * t) + 0.3 * np.sin(2 * np.pi * (f * r + rng.uniform(0.5, 2)) * t))
    x += hp(white(n, rng), 1500) * env_exp(n, 0.004) * 0.5
    return fade(x * 0.3, 0.0, 0.5)


@sound("wagon_roll", "amb_loop", loop=True, stereo=False, folder="town", max_dist=60, unit_size=3.0, target=-26.0)
def wagon_roll(rng, v):
    """Iron-tyred wooden wheels on a dirt road: rumble, crunch, axle squeak, box rattle."""
    s = 16.0
    n = n_of(s + XF)
    x = lp(brown(n, rng), 180) * 0.6 + grains(n, rng, 1500, (0.0005, 0.003), 800, 4000) * 0.4
    t = t_axis(n)
    rot = 0.9  # wheel revolutions per second
    sq = np.maximum(0, np.sin(2 * np.pi * rot * t)) ** 6
    from sfx_foley import stick_slip
    x += stick_slip(n, rng, 400 * (0.2 + sq), [(900, 10, 1.0), (1700, 12, 0.5)], irregular=0.3) * sq * 0.3
    for k in range(int(s * 3)):
        at = int(rng.integers(0, n - 2000))
        x[at:at + n_of(0.03)] += hp(rng.standard_normal(n_of(0.03)), 300) * np.exp(-np.linspace(0, 6, n_of(0.03))) * rng.uniform(0.1, 0.4)
    return make_loop(x, XF)


@sound("train_whistle", "foley", variations=2, max_dist=4000, unit_size=80.0, folder="town")
def train_whistle(rng, v):
    """Steam chime whistle: 3-5 pipes (a chord) with breathy onset, long and a short blast."""
    n = n_of(5.0)
    t = t_axis(n)
    base = rng.uniform(310, 360)
    chord = [1.0, 1.26, 1.5, 1.68] if v == 0 else [1.0, 1.19, 1.5]
    x = np.zeros(n)
    blasts = [(0.0, 2.2), (2.6, 0.5), (3.3, 1.3)]
    gate = np.zeros(n)
    for a, d in blasts:
        gate += env_points(n, [(a, 0), (a + 0.15, 1), (a + d - 0.2, 0.9), (a + d, 0), (5.0, 0)]) * (t >= a) * (t <= a + d + 0.01)
    bend = 1 - 0.03 * np.exp(-((t % 2.6) / 0.1))
    for r in chord:
        f = base * r * bend
        x += np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.5 + 0.15 * np.sin(4 * np.pi * np.cumsum(f) / SR)
    x = x * gate + bp(white(n, rng), 800, 4000) * gate * 0.08
    ir = make_ir(3.0, 2.5, 1.2, rng, stereo=False)
    return fade(convolve(x, ir, 0.25, 1.0)[:n], 0.0, 0.3)


@sound("train_chuff", "amb_loop", loop=True, stereo=False, folder="town", max_dist=500, unit_size=12.0, target=-22.0)
def train_chuff(rng, v):
    """Locomotive at running speed: exhaust chuffs (4 per wheel revolution) + rod clank + rail clicks."""
    s = 12.0
    n = n_of(s + XF)
    x = lp(brown(n, rng), 250) * 0.2
    rate = 4.0
    t = 0.0
    while t < s + XF - 0.3:
        m = n_of(0.22)
        ch = bp(white(m, rng), 300, 3000) * env_exp(m, 0.06, 0.01)
        mix_at(x, ch, n_of(t), rng.uniform(0.6, 1.0) * (1.2 if int(t * rate) % 4 == 0 else 0.9))
        t += 1.0 / rate
    t = 0.0
    while t < s + XF - 0.2:
        mix_at(x, modal(n_of(0.1), [(rng.uniform(600, 900), 0.02, 1.0), (1700, 0.01, 0.4)], rng) * 0.2, n_of(t))
        t += 0.62
    return make_loop(x, XF)


@sound("windmill_creak", "foley", variations=3, max_dist=60, unit_size=3.0, folder="town")
def windmill_creak(rng, v):
    n = n_of(1.5)
    from sfx_foley import stick_slip
    e = np.sin(np.linspace(0, np.pi, n)) ** 2
    x = stick_slip(n, rng, 60 + 140 * e, [(rng.uniform(400, 600), 10, 1.0), (1100, 12, 0.5), (2300, 14, 0.2)]) * e
    return fade(x * 0.6)


@sound("clock_tick", "foley", variations=2, max_dist=8, unit_size=1.0, folder="town")
def clock_tick(rng, v):
    from sfx_foley import click
    n = n_of(0.08)
    return fade(click(n, rng, 2500, 0.002, 1.0) + modal(n, [(rng.uniform(1800, 2500), 0.01, 0.3)], rng))
