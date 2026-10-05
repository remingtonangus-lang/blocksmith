"""UI and Nerve sounds (original synthesis): paper/wood ticks in an 1899 print idiom (no electronic bleeps), page turns,
map unfolding, pencil, notification chime; Nerve slow-time whoosh in/out, heartbeat loop and the mark tick.
"""
from __future__ import annotations

import numpy as np

from dsp import (SR, n_of, t_axis, white, pink, brown, env_exp, env_points, lp, hp, bp, reson, modal, grains, mix_at,
                 fade, smooth_noise, make_ir, convolve, tv_filter, saturate)
from registry import sound


def wood_tick(rng, f=None, dur=0.06, amp=1.0):
    n = n_of(dur)
    f = f or rng.uniform(1600, 2100)
    x = modal(n, [(f, 0.012, 1.0), (f * 2.7, 0.006, 0.4), (f * 0.5, 0.01, 0.3)], rng) * 0.6
    x += hp(white(n, rng), 2500) * env_exp(n, 0.0007) * 0.5
    return x * amp


@sound("ui_tick", "ui", variations=4, fmt="wav", pitch_var=0.03, vol_var_db=0.5, folder="ui")
def ui_tick(rng, v):
    return fade(wood_tick(rng, dur=0.05, amp=0.7), 0.0, 0.01)


@sound("ui_select", "ui", variations=2, fmt="wav", pitch_var=0.0, vol_var_db=0.0, folder="ui")
def ui_select(rng, v):
    n = n_of(0.5)
    x = np.zeros(n)
    mix_at(x, wood_tick(rng, 1500, 0.08), 0)
    f = rng.uniform(1300, 1400)
    bell = modal(n_of(0.45), [(f, 0.25, 1.0), (f * 2.76, 0.1, 0.25), (f * 5.4, 0.05, 0.1)], rng) * 0.25
    mix_at(x, bell, n_of(0.01))
    return fade(x, 0.0, 0.05)


@sound("ui_back", "ui", variations=2, fmt="wav", pitch_var=0.0, vol_var_db=0.0, folder="ui")
def ui_back(rng, v):
    return fade(wood_tick(rng, 1000, 0.08, 0.9) + lp(white(n_of(0.08), rng), 600) * env_exp(n_of(0.08), 0.01) * 0.3)


@sound("ui_error", "ui", variations=1, fmt="wav", pitch_var=0.0, vol_var_db=0.0, folder="ui")
def ui_error(rng, v):
    x = np.zeros(n_of(0.25))
    mix_at(x, wood_tick(rng, 700, 0.1), 0)
    mix_at(x, wood_tick(rng, 650, 0.1), n_of(0.09))
    return fade(x)


def paper(rng, dur, crinkle=1.0, swish=1.0):
    n = n_of(dur)
    e = env_points(n, [(0, 0), (dur * 0.3, 1), (dur * 0.7, 0.7), (dur, 0)])
    x = bp(white(n, rng), 1500, 9000) * e * 0.25 * swish
    x += grains(n, rng, 1500 * crinkle, (0.0008, 0.004), 1500, 8000, env=e) * 0.6
    return x


@sound("ui_page", "ui", variations=4, fmt="wav", folder="ui")
def ui_page(rng, v):
    n = n_of(0.5)
    x = paper(rng, 0.42, 0.6, 1.0)
    flap = lp(white(n_of(0.1), rng), 900) * env_exp(n_of(0.1), 0.015) * 0.4
    out = np.zeros(n)
    mix_at(out, x, 0)
    mix_at(out, flap, n_of(0.36))
    return fade(out)


@sound("ui_map_open", "ui", variations=2, fmt="wav", folder="ui")
def ui_map_open(rng, v):
    out = np.zeros(n_of(1.0))
    for k in range(3):
        mix_at(out, paper(rng, rng.uniform(0.2, 0.35), 1.5, 0.7), n_of(k * rng.uniform(0.2, 0.28)), rng.uniform(0.6, 1))
    return fade(out)


@sound("ui_pencil", "ui", variations=3, fmt="wav", folder="ui")
def ui_pencil(rng, v):
    n = n_of(0.6)
    strokes = np.clip(np.sin(2 * np.pi * rng.uniform(5, 8) * t_axis(n)), 0, 1)
    x = bp(white(n, rng), 2500, 8000) * strokes * 0.25 + grains(n, rng, 2500, (0.0003, 0.001), 3000, 9000, env=strokes) * 0.3
    return fade(x)


@sound("ui_notify", "ui", variations=1, fmt="wav", folder="ui")
def ui_notify(rng, v):
    n = n_of(1.2)
    out = np.zeros(n)
    for k, f in enumerate((1046.5, 1318.5)):
        b = modal(n_of(1.0), [(f, 0.4, 1.0), (f * 2.0, 0.2, 0.2), (f * 3.0, 0.1, 0.08)], rng) * 0.3
        mix_at(out, b, n_of(k * 0.12))
    return fade(out, 0.0, 0.1)


@sound("ui_reward", "ui", variations=1, fmt="wav", folder="ui")
def ui_reward(rng, v):
    """Money/honour gained: coins into a palm + a warm chime."""
    from sfx_foley import coin_hit
    n = n_of(1.0)
    out = np.zeros(n)
    for k in range(5):
        mix_at(out, coin_hit(rng, n_of(0.3), rng.uniform(0.3, 0.7)), n_of(rng.uniform(0, 0.15)))
    b = modal(n_of(0.9), [(784, 0.4, 1.0), (1568, 0.2, 0.2)], rng) * 0.25
    mix_at(out, b, n_of(0.12))
    return fade(out, 0.0, 0.1)


# ------------------------------------------------------------------------------------------------ Nerve
@sound("nerve_in", "nerve", variations=1, folder="ui", stereo=True)
def nerve_in(rng, v):
    """Time slows: a reversed rushing swell sinking in pitch, ending in a deep soft boom."""
    dur = 1.2
    n = n_of(dur)
    t = t_axis(n)
    swell = env_points(n, [(0, 0), (0.35, 1.0), (0.45, 0.4), (dur, 0)])
    fc = 4000 * np.exp(-t / 0.25) + 200
    air = tv_filter(pink(n, rng), "lowpass", fc, order=2, block=128) * swell
    f = 90 * np.exp(-t / 0.5) + 38
    boom = np.sin(np.cumsum(f) / SR * 2 * np.pi) * env_points(n, [(0, 0), (0.33, 0), (0.36, 1), (dur, 0)]) ** 1.5
    x = air * 0.5 + boom * 0.7
    st = np.stack([x, np.concatenate([np.zeros(n_of(0.012)), x[:-n_of(0.012)]])], axis=1)
    ir = make_ir(2.0, 2.0, 1.0, rng, stereo=True)
    return fade(convolve(st, ir, 0.25, 1.0)[:n_of(2.2)], 0.0, 0.3)


@sound("nerve_out", "nerve", variations=1, folder="ui", stereo=True)
def nerve_out(rng, v):
    """Time snaps back: rising rush, short."""
    dur = 0.7
    n = n_of(dur)
    t = t_axis(n)
    e = env_points(n, [(0, 0), (0.45, 1.0), (dur, 0)]) ** 2
    fc = 200 + 5000 * (t / dur) ** 2
    x = tv_filter(pink(n, rng), "lowpass", fc, order=2, block=128) * e
    st = np.stack([x, np.concatenate([np.zeros(n_of(0.01)), x[:-n_of(0.01)]])], axis=1)
    return fade(st * 0.6, 0.0, 0.05)


@sound("nerve_heartbeat", "nerve", loop=True, folder="ui", target=-20.0)
def nerve_heartbeat(rng, v):
    """One heartbeat period (1.0 s at pitch 1.0 = 60 bpm), lub-dub; the director loops it and speeds it up."""
    n = n_of(1.0)
    out = np.zeros(n)

    def beat(f, d, a):
        m = n_of(0.25)
        tt = t_axis(m)
        ff = f * (1 + 0.5 * np.exp(-tt / 0.01))
        return np.sin(np.cumsum(ff) / SR * 2 * np.pi) * env_exp(m, d, 0.006) * a + lp(white(m, rng), 120) * env_exp(m, 0.02) * a * 0.3

    mix_at(out, beat(52, 0.06, 1.0), n_of(0.02))
    mix_at(out, beat(62, 0.045, 0.7), n_of(0.30))
    out = lp(out, 300, 2)
    # make the seam silent (it is: beats end well before 1.0 s)
    return out


@sound("nerve_mark", "nerve", variations=3, folder="ui", pitch_var=0.02)
def nerve_mark(rng, v):
    """A target marked: dull muffled tock with a dark metallic tail (heard through slowed time)."""
    n = n_of(0.7)
    x = lp(white(n, rng), 1200) * env_exp(n, 0.008) * 0.8
    f = rng.uniform(420, 470)
    x += modal(n, [(f, 0.25, 0.5), (f * 2.4, 0.12, 0.25), (f * 3.9, 0.06, 0.1)], rng)
    x += np.sin(2 * np.pi * 70 * t_axis(n)) * env_exp(n, 0.06) * 0.5
    return fade(x * 0.6, 0.0, 0.1)


@sound("low_health_heartbeat", "nerve", loop=True, folder="ui", target=-24.0)
def low_health(rng, v):
    return nerve_heartbeat(rng, v)
