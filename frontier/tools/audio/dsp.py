"""Frontier audio DSP toolkit (original, numpy/scipy only).

Everything is deterministic: every generator gets its RNG from `rng_for(name)` (CRC32 of the sound id), so a rebuild
produces bit-identical audio. Signals are float64 numpy arrays at SR, mono (n,) or stereo (n, 2).
"""
from __future__ import annotations

import math
import zlib
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100


# ----------------------------------------------------------------------------------------------- basics
def rng_for(name: str, salt: int = 0) -> np.random.Generator:
    return np.random.default_rng(zlib.crc32(name.encode()) + salt * 7919)


def secs(n: int) -> float:
    return n / SR


def n_of(seconds: float) -> int:
    return max(1, int(round(seconds * SR)))


def t_axis(n: int) -> np.ndarray:
    return np.arange(n) / SR


def db(x: float) -> float:
    return 10 ** (x / 20.0)


def to_db(x: float) -> float:
    return 20 * math.log10(max(x, 1e-12))


def pad_to(x: np.ndarray, n: int) -> np.ndarray:
    if len(x) >= n:
        return x[:n]
    shape = (n - len(x),) + x.shape[1:]
    return np.concatenate([x, np.zeros(shape)])


def mix_at(dst: np.ndarray, src: np.ndarray, at: int, gain: float = 1.0) -> np.ndarray:
    """Adds src into dst starting at sample `at` (clipped to dst), returns dst."""
    if at >= len(dst):
        return dst
    if at < 0:
        src = src[-at:]
        at = 0
    m = min(len(src), len(dst) - at)
    if src.ndim == 1 and dst.ndim == 2:
        dst[at:at + m] += (src[:m] * gain)[:, None]
    else:
        dst[at:at + m] += src[:m] * gain
    return dst


# ----------------------------------------------------------------------------------------------- sources
def white(n: int, rng: np.random.Generator) -> np.ndarray:
    return rng.standard_normal(n)


def pink(n: int, rng: np.random.Generator) -> np.ndarray:
    """1/f noise via FFT shaping (normalised to unit RMS)."""
    nf = n // 2 + 1
    f = np.fft.rfftfreq(n, 1 / SR)
    spec = (rng.standard_normal(nf) + 1j * rng.standard_normal(nf))
    spec[1:] /= np.sqrt(f[1:])
    spec[0] = 0
    x = np.fft.irfft(spec, n)
    return x / (np.std(x) + 1e-12)


def brown(n: int, rng: np.random.Generator) -> np.ndarray:
    nf = n // 2 + 1
    f = np.fft.rfftfreq(n, 1 / SR)
    spec = (rng.standard_normal(nf) + 1j * rng.standard_normal(nf))
    spec[1:] /= np.maximum(f[1:], 8.0)
    spec[0] = 0
    x = np.fft.irfft(spec, n)
    return x / (np.std(x) + 1e-12)


def smooth_noise(n: int, rate_hz: float, rng: np.random.Generator) -> np.ndarray:
    """Slowly varying random control signal in [-1, 1] (cosine-interpolated random points)."""
    pts = max(4, int(n / SR * rate_hz) + 3)
    v = rng.uniform(-1, 1, pts)
    pos = np.arange(n) / SR * rate_hz
    i = np.floor(pos).astype(int)
    fr = pos - i
    fr = (1 - np.cos(fr * np.pi)) * 0.5
    return v[i] * (1 - fr) + v[np.minimum(i + 1, pts - 1)] * fr


def periodic_smooth_noise(n: int, rate_hz: float, rng: np.random.Generator) -> np.ndarray:
    """Like smooth_noise but wraps around exactly (for loops)."""
    pts = max(4, int(round(n / SR * rate_hz)))
    v = rng.uniform(-1, 1, pts)
    pos = np.arange(n) / n * pts
    i = np.floor(pos).astype(int)
    fr = (1 - np.cos((pos - i) * np.pi)) * 0.5
    return v[i % pts] * (1 - fr) + v[(i + 1) % pts] * fr


def sine(freq, n: int, phase: float = 0.0) -> np.ndarray:
    """Sine with constant or per-sample frequency (array)."""
    if np.isscalar(freq):
        return np.sin(2 * np.pi * freq * t_axis(n) + phase)
    ph = np.cumsum(np.asarray(freq)[:n]) / SR * 2 * np.pi
    return np.sin(ph + phase)


def phase_of(freq: np.ndarray) -> np.ndarray:
    return np.cumsum(freq) / SR * 2 * np.pi


def harmonic(freq: np.ndarray, amps, n: int) -> np.ndarray:
    """Additive harmonic tone with per-sample f0; amps = list of harmonic amplitudes (1-based)."""
    ph = phase_of(np.broadcast_to(freq, (n,)).astype(float))
    out = np.zeros(n)
    nyq = SR / 2
    for k, a in enumerate(amps, start=1):
        if a == 0:
            continue
        mask = (np.broadcast_to(freq, (n,)) * k) < nyq * 0.95
        out += a * np.sin(ph * k) * mask
    return out


def glottal(freq: np.ndarray, n: int, rng: np.random.Generator, jitter: float = 0.01, shimmer: float = 0.05,
            tilt: float = 1.0) -> np.ndarray:
    """Band-limited glottal-like source: harmonic series with -12 dB/oct tilt plus jitter (for formant voices)."""
    f = np.broadcast_to(freq, (n,)).astype(float) * (1 + jitter * smooth_noise(n, 30, rng))
    kmax = int(SR / 2 / max(np.min(f), 40))
    kmax = min(kmax, 60)
    amps = [1.0 / (k ** tilt) for k in range(1, kmax + 1)]
    x = harmonic(f, amps, n)
    return x * (1 + shimmer * smooth_noise(n, 20, rng))


# ----------------------------------------------------------------------------------------------- envelopes
def env_exp(n: int, decay_s: float, attack_s: float = 0.0005) -> np.ndarray:
    t = t_axis(n)
    e = np.exp(-t / max(decay_s, 1e-5))
    na = n_of(attack_s)
    if na > 1:
        e[:na] *= np.linspace(0, 1, na)
    return e


def env_ar(n: int, attack_s: float, release_s: float, curve: float = 2.0) -> np.ndarray:
    na = min(n, n_of(attack_s))
    e = np.ones(n)
    e[:na] = np.linspace(0, 1, na) ** curve
    nr = min(n - na, n_of(release_s))
    if nr > 0:
        e[n - nr:] *= np.linspace(1, 0, nr) ** curve
    return e


def env_points(n: int, pts) -> np.ndarray:
    """Piecewise-linear envelope from [(t_seconds, value), ...]."""
    ts = np.array([p[0] for p in pts]) * SR
    vs = np.array([p[1] for p in pts])
    return np.interp(np.arange(n), ts, vs)


def fade(x: np.ndarray, fin_s: float = 0.002, fout_s: float = 0.01) -> np.ndarray:
    x = x.copy()
    a, b = n_of(fin_s), n_of(fout_s)
    a = min(a, len(x))
    b = min(b, len(x))
    ramp_in = np.linspace(0, 1, a)
    ramp_out = np.linspace(1, 0, b)
    if x.ndim == 2:
        ramp_in = ramp_in[:, None]
        ramp_out = ramp_out[:, None]
    x[:a] *= ramp_in
    x[len(x) - b:] *= ramp_out
    return x


# ----------------------------------------------------------------------------------------------- filters
def _sos(kind: str, f, order: int):
    nyq = SR / 2
    if isinstance(f, (list, tuple)):
        w = [min(max(v / nyq, 1e-4), 0.999) for v in f]
    else:
        w = min(max(f / nyq, 1e-4), 0.999)
    return signal.butter(order, w, btype=kind, output="sos")


def lp(x: np.ndarray, fc: float, order: int = 2) -> np.ndarray:
    return signal.sosfilt(_sos("lowpass", fc, order), x, axis=0)


def hp(x: np.ndarray, fc: float, order: int = 2) -> np.ndarray:
    return signal.sosfilt(_sos("highpass", fc, order), x, axis=0)


def bp(x: np.ndarray, lo: float, hi: float, order: int = 2) -> np.ndarray:
    return signal.sosfilt(_sos("bandpass", [lo, hi], order), x, axis=0)


def peak_eq(x: np.ndarray, f0: float, gain_db: float, q: float = 1.0) -> np.ndarray:
    """RBJ peaking EQ biquad."""
    a = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * f0 / SR
    alpha = np.sin(w0) / (2 * q)
    b = [1 + alpha * a, -2 * np.cos(w0), 1 - alpha * a]
    aa = [1 + alpha / a, -2 * np.cos(w0), 1 - alpha / a]
    return signal.lfilter(np.array(b) / aa[0], np.array(aa) / aa[0], x, axis=0)


def shelf(x: np.ndarray, f0: float, gain_db: float, high: bool = True) -> np.ndarray:
    a = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * f0 / SR
    alpha = np.sin(w0) / 2 * np.sqrt(2)
    c = np.cos(w0)
    if high:
        b = [a * ((a + 1) + (a - 1) * c + 2 * np.sqrt(a) * alpha), -2 * a * ((a - 1) + (a + 1) * c),
             a * ((a + 1) + (a - 1) * c - 2 * np.sqrt(a) * alpha)]
        aa = [(a + 1) - (a - 1) * c + 2 * np.sqrt(a) * alpha, 2 * ((a - 1) - (a + 1) * c),
              (a + 1) - (a - 1) * c - 2 * np.sqrt(a) * alpha]
    else:
        b = [a * ((a + 1) - (a - 1) * c + 2 * np.sqrt(a) * alpha), 2 * a * ((a - 1) - (a + 1) * c),
             a * ((a + 1) - (a - 1) * c - 2 * np.sqrt(a) * alpha)]
        aa = [(a + 1) + (a - 1) * c + 2 * np.sqrt(a) * alpha, -2 * ((a - 1) + (a + 1) * c),
              (a + 1) + (a - 1) * c - 2 * np.sqrt(a) * alpha]
    return signal.lfilter(np.array(b) / aa[0], np.array(aa) / aa[0], x, axis=0)


def reson(x: np.ndarray, f0: float, q: float, gain: float = 1.0) -> np.ndarray:
    """Constant-peak-gain two-pole resonator (bandpass)."""
    w0 = 2 * np.pi * f0 / SR
    alpha = np.sin(w0) / (2 * q)
    b = [alpha, 0, -alpha]
    a = [1 + alpha, -2 * np.cos(w0), 1 - alpha]
    return gain * signal.lfilter(np.array(b) / a[0], np.array(a) / a[0], x, axis=0)


def formants(x: np.ndarray, fmts, bw_scale: float = 1.0) -> np.ndarray:
    """Parallel formant filter: fmts = [(freq, bandwidth, gain_db), ...]."""
    out = np.zeros_like(x)
    for f, bw, g in fmts:
        out += reson(x, f, f / (bw * bw_scale), db(g))
    return out


def _rbj(kind: str, f: float, q: float):
    f = min(max(f, 10.0), SR * 0.49)
    w0 = 2 * math.pi * f / SR
    cw, sw = math.cos(w0), math.sin(w0)
    alpha = sw / (2 * q)
    if kind == "lowpass":
        b = ((1 - cw) / 2, 1 - cw, (1 - cw) / 2)
    elif kind == "highpass":
        b = ((1 + cw) / 2, -(1 + cw), (1 + cw) / 2)
    else:  # bandpass, constant 0 dB peak gain
        b = (alpha, 0.0, -alpha)
    a0 = 1 + alpha
    return np.array(b) / a0, np.array((1.0, -2 * cw / a0, (1 - alpha) / a0))


def tv_filter(x: np.ndarray, kind: str, fc: np.ndarray, order: int = 2, block: int = 256, q: float = None) -> np.ndarray:
    """Time-varying biquad cascade (RBJ coefficients recomputed per block, filter state carried across blocks).
    kind: lowpass/highpass/bandpass; order 2 = one biquad, 4 = two; q: resonance (bandpass: centre/bandwidth)."""
    n = len(x)
    stages = max(1, order // 2) if kind != "bandpass" else max(1, order)
    qq = q if q is not None else (0.7071 if kind != "bandpass" else 2.0)
    y = x.astype(float).copy()
    for st in range(stages):
        out = np.empty_like(y)
        zi = np.zeros((2,) + y.shape[1:])
        for s0 in range(0, n, block):
            e = min(n, s0 + block)
            b, a = _rbj(kind, float(fc[min(s0 + block // 2, n - 1)]), qq)
            out[s0:e], zi = signal.lfilter(b, a, y[s0:e], axis=0, zi=zi)
        y = out
    return y


def onepole_lp(x: np.ndarray, fc: float) -> np.ndarray:
    a = math.exp(-2 * math.pi * fc / SR)
    return signal.lfilter([1 - a], [1, -a], x, axis=0)


# ----------------------------------------------------------------------------------------------- synthesis helpers
def modal(n: int, modes, rng: np.random.Generator | None = None, rand_phase: bool = True) -> np.ndarray:
    """Sum of exponentially damped sines: modes = [(freq, decay_s, amp), ...]."""
    t = t_axis(n)
    out = np.zeros(n)
    for f, d, a in modes:
        if f >= SR / 2 * 0.95:
            continue
        ph = rng.uniform(0, 2 * np.pi) if (rng is not None and rand_phase) else 0.0
        out += a * np.exp(-t / d) * np.sin(2 * np.pi * f * t + ph)
    return out


def noise_burst(n: int, rng, decay_s: float, lo: float = None, hi: float = None, attack_s: float = 0.0003) -> np.ndarray:
    x = white(n, rng) * env_exp(n, decay_s, attack_s)
    if lo and hi:
        x = bp(x, lo, hi)
    elif hi:
        x = lp(x, hi)
    elif lo:
        x = hp(x, lo)
    return x


def grains(n: int, rng, rate_hz: float, dur_s=(0.0005, 0.004), lo: float = 1500, hi: float = 7000,
           amp_spread: float = 1.0, env=None) -> np.ndarray:
    """Poisson cloud of tiny noise grains (gravel crunch, crackle, sand, drops). env scales the rate over time."""
    out = np.zeros(n)
    total = rate_hz * n / SR
    k = rng.poisson(total)
    if env is not None:
        # draw positions proportional to env
        cdf = np.cumsum(np.maximum(env, 0) + 1e-9)
        cdf /= cdf[-1]
        pos = np.searchsorted(cdf, rng.uniform(0, 1, k))
    else:
        pos = rng.integers(0, n, k)
    for p in pos:
        d = rng.uniform(*dur_s)
        m = n_of(d)
        g = rng.standard_normal(m) * np.exp(-np.linspace(0, 6, m))
        a = rng.uniform(0.2, 1.0) ** amp_spread
        mix_at(out, g * a, int(p))
    return bp(out, lo, hi) if lo and hi else out


def bubble(n: int, f0: float, decay_s: float, rise: float = 0.1) -> np.ndarray:
    """Minnaert bubble: rising sine chirp with exponential decay."""
    t = t_axis(n)
    f = f0 * (1 + rise * t / max(decay_s, 1e-4))
    return np.exp(-t / decay_s) * np.sin(phase_of(f))


def fm(n: int, fc, fmod, index, amp=None) -> np.ndarray:
    fc = np.broadcast_to(fc, (n,)).astype(float)
    fmod = np.broadcast_to(fmod, (n,)).astype(float)
    index = np.broadcast_to(index, (n,)).astype(float)
    mod = index * fmod * np.sin(phase_of(fmod))
    x = np.sin(phase_of(fc + mod))
    return x if amp is None else x * amp


def saturate(x: np.ndarray, drive: float = 2.0) -> np.ndarray:
    return np.tanh(x * drive) / np.tanh(drive)


def pitch_resample(x: np.ndarray, ratio: float) -> np.ndarray:
    """Pitch/tempo shift by resampling (ratio > 1 = higher and shorter)."""
    n = int(len(x) / ratio)
    idx = np.arange(n) * ratio
    i = np.floor(idx).astype(int)
    fr = idx - i
    i1 = np.minimum(i + 1, len(x) - 1)
    if x.ndim == 2:
        fr = fr[:, None]
    return x[i] * (1 - fr) + x[i1] * fr


# ----------------------------------------------------------------------------------------------- space
def make_ir(seconds: float, rt60_low: float, rt60_high: float, rng, predelay_s: float = 0.0, early=None,
            stereo: bool = True, density_lp: float = 9000.0) -> np.ndarray:
    """Synthetic reverb IR: decaying noise with frequency-dependent RT60 (crossfaded low/high bands) + early taps."""
    n = n_of(seconds)
    t = t_axis(n)
    chans = 2 if stereo else 1
    out = np.zeros((n, chans))
    for c in range(chans):
        nz = rng.standard_normal(n)
        low = lp(nz, 900) * np.exp(-6.91 * t / rt60_low)
        high = hp(nz, 900) * np.exp(-6.91 * t / rt60_high)
        tail = lp(low + high, density_lp)
        # build-up of density
        tail *= 1 - np.exp(-t / 0.012)
        out[:, c] = tail
        if early:
            for (dt, g) in early:
                k = n_of(dt * (1 + rng.uniform(-0.04, 0.04)))
                if k < n:
                    out[k, c] += g * (1 if rng.uniform() > 0.3 else -1)
    pd = n_of(predelay_s) if predelay_s > 0 else 0
    if pd:
        out = np.concatenate([np.zeros((pd, chans)), out])
    out /= np.sqrt(np.sum(out ** 2) / chans) + 1e-12
    return out if stereo else out[:, 0]


def convolve(x: np.ndarray, ir: np.ndarray, wet: float, dry: float = 1.0) -> np.ndarray:
    """Convolve mono or stereo x with mono/stereo IR; output length len(x)+len(ir)-1 (stereo if IR stereo)."""
    if ir.ndim == 1:
        ir = ir[:, None]
    if x.ndim == 1:
        x2 = np.repeat(x[:, None], ir.shape[1], axis=1)
    else:
        x2 = x
    wetsig = np.stack([signal.fftconvolve(x2[:, c % x2.shape[1]], ir[:, c % ir.shape[1]])
                       for c in range(max(ir.shape[1], x2.shape[1]))], axis=1)
    out = wetsig * wet
    out[:len(x2)] += x2 * dry if x2.shape[1] == out.shape[1] else x2[:, :1] * dry
    if x.ndim == 1 and ir.shape[1] == 1:
        return out[:, 0]
    return out


def echoes(x: np.ndarray, taps, lp_fc: float = None) -> np.ndarray:
    """Discrete echoes: taps = [(delay_s, gain), ...]; each echo optionally low-passed. Output extended."""
    end = len(x) + n_of(max(t for t, _ in taps)) + 1
    out = pad_to(x.copy(), end)
    src = lp(x, lp_fc) if lp_fc else x
    for d, g in taps:
        mix_at(out, src, n_of(d), g)
    return out


def to_stereo(x: np.ndarray, pan: float = 0.0, width_delay_s: float = 0.0) -> np.ndarray:
    if x.ndim == 2:
        return x
    l = math.cos((pan + 1) * math.pi / 4)
    r = math.sin((pan + 1) * math.pi / 4)
    out = np.stack([x * l, x * r], axis=1) * math.sqrt(2)
    if width_delay_s:
        d = n_of(width_delay_s)
        out[:, 1] = np.concatenate([np.zeros(d), out[:-d, 1]])
    return out


def pan_stereo(x: np.ndarray, pan: np.ndarray) -> np.ndarray:
    """Per-sample equal-power pan of mono x (pan in -1..1)."""
    a = (pan + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1) * math.sqrt(2)


# ----------------------------------------------------------------------------------------------- dynamics
def compress(x: np.ndarray, thresh_db: float = -18, ratio: float = 3.0, attack_s: float = 0.01,
             release_s: float = 0.15, makeup_db: float = 0.0, knee_db: float = 6.0) -> np.ndarray:
    """Feed-forward RMS-ish compressor on the linked (max) envelope."""
    mono = np.max(np.abs(x), axis=1) if x.ndim == 2 else np.abs(x)
    # envelope follower (vectorised one-pole on squared signal, separate attack/release approximated)
    env = np.sqrt(signal.lfilter([1 - math.exp(-1 / (attack_s * SR))], [1, -math.exp(-1 / (attack_s * SR))], mono ** 2))
    rel = math.exp(-1 / (release_s * SR))
    env = np.maximum(env, signal.lfilter([1 - rel], [1, -rel], env))
    lvl = 20 * np.log10(env + 1e-9)
    over = lvl - thresh_db
    gr = np.where(over <= -knee_db / 2, 0.0,
                  np.where(over >= knee_db / 2, over * (1 - 1 / ratio),
                           (over + knee_db / 2) ** 2 / (2 * knee_db) * (1 - 1 / ratio)))
    g = 10 ** ((makeup_db - gr) / 20)
    return x * (g[:, None] if x.ndim == 2 else g)


def limit(x: np.ndarray, ceiling_db: float = -1.0, lookahead_s: float = 0.003, release_s: float = 0.08) -> np.ndarray:
    """Look-ahead brickwall-ish peak limiter."""
    c = db(ceiling_db)
    mono = np.max(np.abs(x), axis=1) if x.ndim == 2 else np.abs(x)
    la = n_of(lookahead_s)
    # gain needed per sample, then min over look-ahead window, then smooth release
    need = np.minimum(1.0, c / (mono + 1e-12))
    from scipy.ndimage import minimum_filter1d
    need = minimum_filter1d(need, size=2 * la + 1, origin=0)
    rel = math.exp(-1 / (release_s * SR))
    # release smoothing: gain can drop instantly, rise slowly
    g = np.empty_like(need)
    # vectorised approximation: smooth with one-pole then take min with need
    sm = signal.lfilter([1 - rel], [1, -rel], need, zi=[need[0] * rel])[0]
    g = np.minimum(need, sm)
    g = np.minimum(g, minimum_filter1d(g, size=la + 1))
    y = x * (g[:, None] if x.ndim == 2 else g)
    pk = np.max(np.abs(y))
    if pk > c:
        y *= c / pk
    return y


# ----------------------------------------------------------------------------------------------- loudness
def _k_weight(x: np.ndarray) -> np.ndarray:
    # ITU-R BS.1770 pre-filter (high shelf) + RLB high-pass, coefficients for 48k approximated at SR via bilinear
    x = shelf(x, 1681.97, 4.0, high=True)
    return hp(x, 38.0, order=2)


def lufs(x: np.ndarray) -> float:
    """Integrated loudness (BS.1770-4 style, gated). Short sounds (< 0.4 s) are padded."""
    if x.ndim == 1:
        x = x[:, None]
    if len(x) < n_of(0.4):
        x = pad_to(x, n_of(0.4))
    y = _k_weight(x)
    blk = n_of(0.4)
    hop = n_of(0.1)
    zs = []
    for s in range(0, len(y) - blk + 1, hop):
        zs.append(np.sum(np.mean(y[s:s + blk] ** 2, axis=0)))
    zs = np.array(zs)
    if len(zs) == 0:
        return -70.0
    l = -0.691 + 10 * np.log10(zs + 1e-12)
    zs = zs[l > -70]
    if len(zs) == 0:
        return -70.0
    rel = -0.691 + 10 * np.log10(np.mean(zs)) - 10
    l = -0.691 + 10 * np.log10(zs + 1e-12)
    zs = zs[l > rel]
    return float(-0.691 + 10 * np.log10(np.mean(zs) + 1e-12))


def peak_db(x: np.ndarray) -> float:
    return to_db(float(np.max(np.abs(x))) if len(x) else 0.0)


def true_peak_db(x: np.ndarray) -> float:
    """4x oversampled peak estimate."""
    y = signal.resample_poly(x, 4, 1, axis=0)
    return to_db(float(np.max(np.abs(y))))


def normalize(x: np.ndarray, target_lufs: float = None, peak_ceiling_db: float = -1.0, limit_peaks: bool = True) -> np.ndarray:
    """Gain to target LUFS (if given), then keep true peak under the ceiling (limiter if needed, else gain)."""
    x = x - np.mean(x, axis=0) if len(x) > SR else x
    if target_lufs is not None:
        cur = lufs(x)
        x = x * db(target_lufs - cur)
    tp = true_peak_db(x)
    if tp > peak_ceiling_db:
        if limit_peaks:
            x = limit(x, peak_ceiling_db - 0.6)
            tp = true_peak_db(x)
            if tp > peak_ceiling_db:
                x = x * db(peak_ceiling_db - 0.2 - tp)
        else:
            x = x * db(peak_ceiling_db - 0.2 - tp)
    return x


# ----------------------------------------------------------------------------------------------- loops
def make_loop(x: np.ndarray, xfade_s: float = 1.0) -> np.ndarray:
    """Seamless loop: the last xfade_s is crossfaded (equal power) into the start; output is shorter by xfade."""
    nx = n_of(xfade_s)
    body = x[:-nx].copy()
    tail = x[-nx:]
    a = np.linspace(0, np.pi / 2, nx)
    fi, fo = np.sin(a), np.cos(a)
    if x.ndim == 2:
        fi, fo = fi[:, None], fo[:, None]
    body[:nx] = body[:nx] * fi + tail * fo
    return body


def fold_tail(x: np.ndarray, loop_n: int) -> np.ndarray:
    """For rendered music: everything past loop_n (reverb/release tail) is added onto the start, cut to loop_n."""
    out = x[:loop_n].copy()
    rest = x[loop_n:]
    while len(rest):
        m = min(len(rest), loop_n)
        out[:m] += rest[:m]
        rest = rest[m:]
    return out


# ----------------------------------------------------------------------------------------------- io
def write(path: Path, x: np.ndarray, fmt: str = "ogg", quality: float = 0.35) -> Path:
    import soundfile as sf
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    x = np.asarray(x, dtype=np.float64)
    x = np.clip(x, -1.0, 1.0)
    if fmt == "wav":
        path = path.with_suffix(".wav")
        sf.write(str(path), x.astype(np.float32), SR, subtype="PCM_16")
    else:
        path = path.with_suffix(".ogg")
        ch = 1 if x.ndim == 1 else x.shape[1]
        kw = {}
        try:
            sf.SoundFile  # noqa
            kw = {"compression_level": quality}
        except AttributeError:
            pass
        # chunked writes: libsndfile's Vorbis encoder overflows its stack on very large single writes
        try:
            f = sf.SoundFile(str(path), "w", SR, ch, format="OGG", subtype="VORBIS", **kw)
        except TypeError:
            f = sf.SoundFile(str(path), "w", SR, ch, format="OGG", subtype="VORBIS")
        with f:
            xf = x.astype(np.float32)
            for i in range(0, len(xf), 4096):
                f.write(xf[i:i + 4096])
    return path


def read(path: Path) -> np.ndarray:
    import soundfile as sf
    x, sr = sf.read(str(path), always_2d=False)
    if sr != SR:
        x = signal.resample_poly(x, SR, sr, axis=0)
    return x
