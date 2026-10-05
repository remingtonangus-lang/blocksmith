"""Gunshots and firearm mechanics (original synthesis).

A shot is layered from physical components:
  blast   the muzzle pressure pulse (asymmetric pulse with negative lobe, width tau): the punch
  crack   supersonic bullet N-wave for rifle calibres: a bright snap
  body    the expanding gas: noise through a falling low-pass, exponential decay
  thump   the low resonant chest hit: a gliding sine
  rumble  long low gas/ground rumble
  mech    the action's metal (hammer, bolt): small inharmonic ring
  space   close outdoor (ground reflection + rolling terrain tail), indoor (dense room), far (muffled, long
          rolling echoes) and an `echo` slap used by the game for geometry-timed reflections off cliffs/buildings.
Mechanics: cocking, lever/bolt/pump cycles, loading, dry fire, casings, holster.
"""
from __future__ import annotations

import numpy as np

from dsp import (SR, n_of, t_axis, white, brown, env_exp, lp, hp, bp, tv_filter, modal, saturate, mix_at, pad_to,
                 make_ir, convolve, echoes, fade, smooth_noise, peak_eq, shelf, grains, db)
from registry import sound

# calibre/character per weapon sound id (see src/combat/weapons.gd)
GUNS = {
    "revolver_heavy": dict(tau=0.85, crack=0.0, body_decay=0.075, body_lp=7500, thump_f=78, thump_d=0.13, rumble=0.30,
                           mech=0.10, drive=2.6, tail=1.0, mid=1.0, size="pistol"),
    "revolver_light": dict(tau=0.55, crack=0.0, body_decay=0.052, body_lp=8500, thump_f=98, thump_d=0.085, rumble=0.17,
                           mech=0.12, drive=2.2, tail=0.85, mid=1.1, size="pistol"),
    "rifle_lever":    dict(tau=0.75, crack=0.45, body_decay=0.085, body_lp=8000, thump_f=72, thump_d=0.15, rumble=0.32,
                           mech=0.08, drive=2.6, tail=1.15, mid=1.0, size="rifle"),
    "rifle_bolt":     dict(tau=0.62, crack=1.0, body_decay=0.075, body_lp=9500, thump_f=66, thump_d=0.16, rumble=0.36,
                           mech=0.07, drive=2.8, tail=1.35, mid=0.9, size="rifle"),
    "rifle_small":    dict(tau=0.26, crack=0.35, body_decay=0.024, body_lp=9500, thump_f=150, thump_d=0.035, rumble=0.05,
                           mech=0.10, drive=1.6, tail=0.5, mid=1.2, size="small"),
    "rifle_heavy":    dict(tau=1.1, crack=0.9, body_decay=0.105, body_lp=7000, thump_f=55, thump_d=0.21, rumble=0.45,
                           mech=0.06, drive=3.0, tail=1.5, mid=0.95, size="rifle"),
    "shotgun":        dict(tau=1.25, crack=0.0, body_decay=0.115, body_lp=6500, thump_f=60, thump_d=0.2, rumble=0.5,
                           mech=0.06, drive=3.0, tail=1.3, mid=1.25, size="shotgun"),
}


def _jit(rng, v, amt):
    return v * (1 + rng.uniform(-amt, amt))


def blast_pulse(n: int, tau_ms: float, rng) -> np.ndarray:
    """Friedlander-like muzzle pulse: fast rise, positive phase ~tau, negative phase ~3 tau, plus broadband grit."""
    t = t_axis(n) * 1000.0  # ms
    tau = tau_ms
    pos = (t / tau) * np.exp(1 - t / tau)                  # alpha function peak 1 at tau
    neg = -0.45 * ((t / (3 * tau)) ** 2) * np.exp(2 - 2 * t / (3 * tau)) * (t > 0)
    p = pos + neg
    p = lp(p, 14000, 2)
    grit = white(n, rng) * np.exp(-t / (tau * 0.9)) * 0.5
    grit = hp(grit, 1500)
    return p + grit


def crack_wave(n: int, rng) -> np.ndarray:
    """Supersonic N-wave (~0.35 ms) + a bright noise snap."""
    t = t_axis(n) * 1000.0
    w = 0.35
    nwave = np.where(t < w, 1 - 2 * t / w, 0.0)
    snap = hp(white(n, rng), 3000, 2) * np.exp(-t / 1.6)
    return lp(nwave, 16000, 2) * 0.9 + snap * 0.6


def gun_dry(gid: str, p: dict, rng) -> np.ndarray:
    """The source shot without the environment (approx 0.6 s)."""
    n = n_of(0.7)
    t = t_axis(n)
    tau = _jit(rng, p["tau"], 0.1)
    x = blast_pulse(n, tau, rng) * 1.0
    # body: noise through a falling low-pass
    bd = _jit(rng, p["body_decay"], 0.12)
    fc = 300 + (p["body_lp"] - 300) * np.exp(-t / (bd * 0.7))
    body = tv_filter(white(n, rng), "lowpass", fc, order=2, block=128) * env_exp(n, bd, 0.0008)
    body = peak_eq(body, 1400, 3.0 * p["mid"], 0.8)
    x += body * 0.55
    # thump
    f0 = _jit(rng, p["thump_f"], 0.08)
    f = f0 * (1 + 1.2 * np.exp(-t / 0.012))
    thump = np.sin(np.cumsum(f) / SR * 2 * np.pi) * env_exp(n, _jit(rng, p["thump_d"], 0.1) * 0.7, 0.0015)
    x += thump * 0.55
    # rumble
    rum = lp(brown(n, rng), 260, 2) * env_exp(n, 0.22 + p["rumble"] * 0.25, 0.01) * p["rumble"]
    x += rum * 0.6
    # crack
    if p["crack"] > 0:
        x += crack_wave(n, rng) * p["crack"] * 0.9
    # mechanism ring (hammer/action)
    if p["mech"] > 0:
        base = rng.uniform(2200, 3200)
        modes = [(base * r, rng.uniform(0.02, 0.06), a) for r, a in ((1, 1), (1.57, .7), (2.31, .5), (3.43, .35), (4.1, .2))]
        m = modal(n, modes, rng) * p["mech"] * 0.25
        x += np.concatenate([np.zeros(n_of(0.004)), m])[:n]
    x = saturate(x * 1.6, p["drive"])
    x = hp(x, 38, 2)
    return fade(x, 0.0, 0.08)


def terrain_ir(rng, length_s: float, first_s: float, decay_s: float, bright_fc: float, dark_fc: float,
               density: float = 1.0) -> np.ndarray:
    """Sparse outdoor impulse response: reflections off ground, trees and terrain arrive ever denser and darker.
    Each tap is a short smeared burst (diffuse surfaces); the whole IR is low-passed more as time goes on."""
    n = n_of(length_s)
    ir = np.zeros(n)
    t = t_axis(n)
    # tap times: Poisson with rate growing with time (more scatterers at larger radius), first_s onward
    k = int(60 * density * length_s)
    u = rng.uniform(0, 1, k)
    times = first_s + (length_s - first_s) * u ** 0.75
    for tt in times:
        i = n_of(tt)
        if i >= n - 10:
            continue
        g = np.exp(-(tt - first_s) / decay_s) * rng.uniform(0.15, 1.0) * (1 if rng.uniform() > 0.5 else -1)
        m = n_of(rng.uniform(0.004, 0.025))
        burst = rng.standard_normal(m) * np.hanning(m)
        mix_at(ir, burst, i, g / np.sqrt(m))
    # diffuse bed (very distant scattering)
    bed = rng.standard_normal(n) * np.exp(-(np.maximum(t - first_s, 0)) / (decay_s * 1.1)) * (t > first_s * 0.8)
    ir += bed * 0.012
    fc = dark_fc + (bright_fc - dark_fc) * np.exp(-np.maximum(t - first_s, 0) / (decay_s * 0.6))
    ir = tv_filter(ir, "lowpass", fc, order=4, block=512)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
    return ir


def outdoor_tail(src: np.ndarray, p: dict, rng, length_s: float, lp_fc: float = 1800, level: float = 0.5,
                 first_echo: float = 0.09) -> np.ndarray:
    """Rolling terrain tail: the source convolved with a sparse terrain IR (diffuse, darkening, slowly decaying)."""
    ir = terrain_ir(rng, length_s, first_echo, 0.45 * p["tail"] + 0.15, lp_fc, max(250.0, lp_fc * 0.25))
    wet = signal_fftconv(src, ir)[:n_of(length_s)]
    return wet * level


def signal_fftconv(a, b):
    from scipy.signal import fftconvolve
    return fftconvolve(a, b)


def place_close(dry: np.ndarray, p: dict, rng) -> np.ndarray:
    """Close outdoor: ground reflection comb + short rolling tail (game adds geometry echoes on top)."""
    gr = n_of(rng.uniform(0.0035, 0.006))
    x = dry.copy()
    x[gr:] += 0.45 * lp(dry, 6000, 1)[:-gr]
    tail = outdoor_tail(dry, p, rng, 1.6 * p["tail"] + 0.5, lp_fc=1900, level=0.13)
    out = pad_to(x, len(tail))
    out += tail
    return fade(out, 0.0, 0.25)


def place_indoor(dry: np.ndarray, p: dict, rng) -> np.ndarray:
    """Inside a timber/brick room: dense early reflections, boomy, ~0.9 s decay."""
    early = [(rng.uniform(0.003, 0.03), rng.uniform(0.2, 0.6)) for _ in range(14)]
    ir = make_ir(1.4, rt60_low=0.8, rt60_high=0.5, rng=rng, early=early, stereo=False, density_lp=7000)
    wet = convolve(dry, ir, wet=0.16, dry=1.0)
    wet = shelf(wet, 180, 2.0, high=False)
    wet = peak_eq(wet, 450, 2.5, 0.9)
    wet = hp(wet, 70, 2)
    return fade(saturate(wet * 1.1, 1.4), 0.0, 0.2)


def place_far(dry: np.ndarray, p: dict, rng, dist: float) -> np.ndarray:
    """Distant shot: air absorption (strong low-pass), softened attack, long rolling echoes dominate."""
    fc = 2200 if dist < 400 else 1100
    d = lp(dry, fc, 4)
    d = lp(d, fc * 1.5, 1)
    # attack softening (the blast spreads over a few ms at range)
    soft = np.convolve(d, np.hanning(n_of(0.004)) / np.sum(np.hanning(n_of(0.004))), mode="full")[:len(d)]
    length = 2.8 + p["tail"] * 1.5 + (1.0 if dist > 400 else 0)
    tail = outdoor_tail(soft, p, rng, length, lp_fc=fc * 0.7, level=0.9 if dist < 400 else 1.3, first_echo=0.25)
    out = pad_to(soft * (1.0 if dist < 400 else 0.6), len(tail)) + tail
    out = hp(out, 45, 2)
    return fade(out, 0.0, 0.6)


def echo_slap(dry: np.ndarray, p: dict, rng) -> np.ndarray:
    """One reflection off a cliff/building face: darker, smeared, with a short diffuse tail."""
    e = lp(dry, rng.uniform(1600, 2600), 2)
    smear = make_ir(0.35, 0.3, 0.18, rng, stereo=False, density_lp=4000)
    e = convolve(e, smear, wet=0.25, dry=0.6)
    return fade(e, 0.0, 0.2)


def _gun_family(gid: str, p: dict):
    @sound(f"gun_{gid}", "gun", variations=4, max_dist=900.0, unit_size=18.0, pitch_var=0.035, vol_var_db=1.0,
           tags={"weapon": gid, "variant": "close"}, folder="guns")
    def close(rng, v, gid=gid, p=p):
        return place_close(gun_dry(gid, p, rng), p, rng)

    @sound(f"gun_{gid}_indoor", "gun", variations=3, max_dist=200.0, unit_size=16.0, pitch_var=0.03,
           tags={"weapon": gid, "variant": "indoor"}, folder="guns")
    def indoor(rng, v, gid=gid, p=p):
        return place_indoor(gun_dry(gid, p, rng), p, rng)

    @sound(f"gun_{gid}_far", "gun_far", variations=3, max_dist=3000.0, unit_size=200.0, pitch_var=0.04,
           tags={"weapon": gid, "variant": "far"}, folder="guns")
    def far(rng, v, gid=gid, p=p):
        return place_far(gun_dry(gid, p, rng), p, rng, 250.0)

    @sound(f"gun_{gid}_distant", "gun_far", variations=2, max_dist=6000.0, unit_size=500.0, pitch_var=0.05,
           tags={"weapon": gid, "variant": "distant"}, folder="guns")
    def distant(rng, v, gid=gid, p=p):
        return place_far(gun_dry(gid, p, rng), p, rng, 900.0)


for _gid, _p in GUNS.items():
    _gun_family(_gid, _p)

for _size, _gid in (("pistol", "revolver_heavy"), ("rifle", "rifle_bolt"), ("shotgun", "shotgun"), ("small", "rifle_small")):
    def _echo(rng, v, gid=_gid):
        return echo_slap(gun_dry(gid, GUNS[gid], rng), GUNS[gid], rng)
    sound(f"gun_echo_{_size}", "gun_echo", variations=3, max_dist=2000.0, unit_size=60.0, pitch_var=0.05,
          folder="guns")(_echo)


# ------------------------------------------------------------------------------------------------ mechanics
def metal_click(rng, size: float = 1.0, bright: float = 1.0, dur: float = 0.08) -> np.ndarray:
    """A small steel part striking steel inside a wooden-stocked gun: broadband tick, a short damped inharmonic
    ring (parts are held tight, so they barely sing) and the frame/stock thunk."""
    n = n_of(dur)
    tick = hp(white(n, rng), 1800 * bright, 2) * env_exp(n, 0.0009 * size, 0.00005)
    base = rng.uniform(2600, 4200) * bright / size
    ratios = (1.0, 1.48, 2.17, 2.96, 3.81, 5.2)
    modes = [(base * r * rng.uniform(0.97, 1.03), rng.uniform(0.003, 0.010) * size, rng.uniform(0.3, 1.0) / (i + 1))
             for i, r in enumerate(ratios)]
    thunk = bp(white(n, rng), 350 / size ** 0.5, 2600, 2) * env_exp(n, 0.005 * size) * 0.7
    return tick * 1.0 + modal(n, modes, rng) * 0.3 + thunk


def slide_scrape(rng, dur: float, lo=1500, hi=7000, level=0.3) -> np.ndarray:
    n = n_of(dur)
    env = np.sin(np.linspace(0, np.pi, n)) ** 0.7
    g = grains(n, rng, 2500, (0.0003, 0.0015), lo, hi)
    return (g * 0.8 + bp(white(n, rng), lo, hi) * 0.15) * env * level


def spring(rng, dur=0.12, f=900) -> np.ndarray:
    n = n_of(dur)
    t = t_axis(n)
    return np.sin(2 * np.pi * f * t * (1 + 0.15 * np.exp(-t / 0.02))) * env_exp(n, 0.012) * 0.025


def seq(parts, total_s: float) -> np.ndarray:
    out = np.zeros(n_of(total_s))
    for at, x, g in parts:
        mix_at(out, x, n_of(at), g)
    return out


@sound("revolver_cock", "gun_mech", variations=4, max_dist=25, unit_size=2.0, folder="guns")
def revolver_cock(rng, v):
    # hammer back: soft sear click, ratchet of the cylinder hand, full-cock click
    a = metal_click(rng, 1.0, 0.9) * 0.5
    r = slide_scrape(rng, 0.05, 2500, 8000, 0.25)
    b = metal_click(rng, 0.8, 1.1)
    d2 = rng.uniform(0.09, 0.13)
    return fade(seq([(0.0, a, 1.0), (0.015, r, 1.0), (d2, b, 1.0)], d2 + 0.12), 0.0005, 0.02)


@sound("revolver_dryfire", "gun_mech", variations=3, max_dist=20, unit_size=2.0, folder="guns")
def revolver_dryfire(rng, v):
    return fade(seq([(0, metal_click(rng, 1.4, 0.8), 1.0)], 0.12), 0.0005, 0.02)


@sound("revolver_gate", "gun_mech", variations=2, max_dist=15, unit_size=1.5, folder="guns")
def revolver_gate(rng, v):
    return fade(seq([(0, metal_click(rng, 0.7, 1.2), 0.6), (0.03, slide_scrape(rng, 0.04), 0.6)], 0.12))


@sound("revolver_round_in", "gun_mech", variations=4, max_dist=15, unit_size=1.5, folder="guns")
def revolver_round_in(rng, v):
    # brass into the chamber (soft slide + seat) then the cylinder clicks round one chamber
    seat = metal_click(rng, 1.2, 0.7) * 0.5
    ratchet = metal_click(rng, 0.6, 1.3)
    return fade(seq([(0, slide_scrape(rng, 0.05, 1200, 5000, 0.4), 1), (0.045, seat, 1), (0.12, ratchet, 0.7)], 0.22))


@sound("revolver_eject", "gun_mech", variations=2, max_dist=15, unit_size=1.5, folder="guns")
def revolver_eject(rng, v):
    return fade(seq([(0, slide_scrape(rng, 0.08, 1500, 6000, 0.5), 1), (0.07, metal_click(rng, 0.9, 1.0), 0.6)], 0.2))


@sound("lever_cycle", "gun_mech", variations=4, max_dist=30, unit_size=2.0, folder="guns")
def lever_cycle(rng, v):
    # lever down: bolt unlocks + slides back (scrape), casing kicks; lever up: chambers + locks (heavy clack)
    down = metal_click(rng, 1.3, 0.75)
    scrape1 = slide_scrape(rng, 0.07, 1200, 6000, 0.6)
    up = metal_click(rng, 1.5, 0.7) * 1.1
    scrape2 = slide_scrape(rng, 0.06, 1200, 6000, 0.5)
    gap = rng.uniform(0.17, 0.22)
    return fade(seq([(0, down, 1), (0.01, scrape1, 1), (0.04, spring(rng, 0.1, 700), 1),
                     (gap - 0.05, scrape2, 1), (gap, up, 1)], gap + 0.15), 0.0005, 0.03)


@sound("bolt_cycle", "gun_mech", variations=3, max_dist=30, unit_size=2.0, folder="guns")
def bolt_cycle(rng, v):
    lift = metal_click(rng, 1.1, 0.8)
    back = slide_scrape(rng, 0.12, 1000, 5000, 0.7)
    stop = metal_click(rng, 1.2, 0.7) * 0.7
    fwd = slide_scrape(rng, 0.1, 1000, 5000, 0.6)
    lock = metal_click(rng, 1.6, 0.65)
    return fade(seq([(0, lift, 1), (0.06, back, 1), (0.18, stop, 1), (0.3, fwd, 1), (0.41, lock, 1.1)], 0.6), 0.0005, 0.03)


@sound("pump_cycle", "gun_mech", variations=3, max_dist=35, unit_size=2.0, folder="guns")
def pump_cycle(rng, v):
    back = slide_scrape(rng, 0.09, 700, 4500, 0.9)
    clunk1 = metal_click(rng, 2.0, 0.5) * 1.1
    fwd = slide_scrape(rng, 0.08, 700, 4500, 0.8)
    clunk2 = metal_click(rng, 2.2, 0.5) * 1.2
    return fade(seq([(0, back, 1), (0.08, clunk1, 1), (0.16, fwd, 1), (0.24, clunk2, 1)], 0.42), 0.0005, 0.03)


@sound("break_open", "gun_mech", variations=2, max_dist=25, unit_size=2.0, folder="guns")
def break_open(rng, v):
    return fade(seq([(0, metal_click(rng, 1.8, 0.55), 1), (0.03, slide_scrape(rng, 0.06, 800, 4000, 0.5), 1),
                     (0.09, metal_click(rng, 1.0, 1.0), 0.4)], 0.3))


@sound("break_close", "gun_mech", variations=2, max_dist=25, unit_size=2.0, folder="guns")
def break_close(rng, v):
    return fade(seq([(0, slide_scrape(rng, 0.03, 800, 4000, 0.5), 1), (0.025, metal_click(rng, 2.2, 0.5), 1.3)], 0.25))


@sound("shell_insert", "gun_mech", variations=4, max_dist=15, unit_size=1.5, folder="guns")
def shell_insert(rng, v):
    return fade(seq([(0, slide_scrape(rng, 0.05, 900, 4000, 0.5), 1), (0.04, metal_click(rng, 1.3, 0.6), 0.8),
                     (0.05, spring(rng, 0.08, 520), 1)], 0.18))


@sound("casing_drop", "foley", variations=6, max_dist=12, unit_size=1.0, folder="guns")
def casing_drop(rng, v):
    # brass casing: 2-4 bounces with bright inharmonic ring, decreasing gaps
    out = np.zeros(n_of(0.7))
    t = 0.0
    gap = rng.uniform(0.09, 0.15)
    amp = 1.0
    base = rng.uniform(3500, 5200)
    for _ in range(rng.integers(3, 6)):
        n = n_of(0.15)
        modes = [(base * r * rng.uniform(0.99, 1.01), rng.uniform(0.02, 0.06), a) for r, a in
                 ((1, 1), (2.76, .6), (5.4, .4), (8.9, .2))]
        hit = modal(n, modes, rng) * 0.4 + hp(white(n, rng), 3000) * env_exp(n, 0.0005) * 0.6
        mix_at(out, hit, n_of(t), amp)
        t += gap
        gap *= rng.uniform(0.45, 0.7)
        amp *= rng.uniform(0.4, 0.7)
    return fade(out, 0.0, 0.05)


@sound("gun_draw", "foley", variations=3, max_dist=15, unit_size=1.5, folder="guns")
def gun_draw(rng, v):
    n = n_of(0.35)
    swish = bp(white(n, rng), 600, 3500) * np.sin(np.linspace(0, np.pi, n)) ** 2 * 0.25
    leather = grains(n, rng, 600, (0.001, 0.004), 300, 1500) * np.sin(np.linspace(0, np.pi, n)) * 0.5
    return fade(seq([(0, swish + leather, 1), (0.22, metal_click(rng, 1.0, 0.9), 0.35)], 0.4))


@sound("gun_holster", "foley", variations=3, max_dist=15, unit_size=1.5, folder="guns")
def gun_holster(rng, v):
    n = n_of(0.3)
    leather = grains(n, rng, 900, (0.001, 0.005), 250, 1400) * np.sin(np.linspace(0, np.pi, n)) * 0.6
    thud = lp(white(n, rng), 400) * env_exp(n, 0.02) * 0.6
    return fade(seq([(0, leather, 1), (0.2, thud, 1)], 0.45))
