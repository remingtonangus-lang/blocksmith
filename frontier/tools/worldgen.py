#!/usr/bin/env python3
"""Frontier world generator: the Sable River country.

Deterministic. Writes into frontier/data/world/:
  height.r16    4096x4096 little-endian uint16, metres = v / 65535 * H_RANGE  (2 m cells, row = +Z)
  control.bin   2048x2048 RGBA8: R road/trail, G moisture, B biome (0 desert .. 0.5 grass .. 1 forest), A sediment/flow
  features.json towns, roads, rail, rivers, lake, POIs (map coords in metres, origin at map centre)
  preview.png   hillshaded colour preview (for eyes and the critic)

Usage: python3 frontier/tools/worldgen.py [--out DIR] [--fast]
"""
import argparse, json, math, os, sys, time, heapq
import numpy as np
from scipy import ndimage

SIZE_M = 8192.0
N = 4096                 # heightmap resolution (2 m)
NC = 2048                # control map resolution (4 m)
H_RANGE = 1600.0         # metres represented by uint16
LAKE_LEVEL = 120.0
SEED = 1899

rng = np.random.default_rng(SEED)


# ---------------------------------------------------------------- noise
def value_noise(n, cells, seed):
    """Smooth value noise on an n x n grid with `cells` lattice cells (bicubic upsample of random lattice)."""
    r = np.random.default_rng(seed)
    lat = r.random((cells + 3, cells + 3)).astype(np.float32)
    z = ndimage.zoom(lat, (n + 3 * n / cells) / (cells + 3), order=3, mode='wrap')
    off = int(n / cells)
    return z[off:off + n, off:off + n][:n, :n]


def fbm(n, base_cells, octaves, seed, gain=0.5, lac=2.0):
    total = np.zeros((n, n), np.float32)
    amp, cells, norm = 1.0, base_cells, 0.0
    for o in range(octaves):
        c = int(round(cells))
        if c >= n // 2:
            break
        total += amp * (value_noise(n, c, seed + o * 101) * 2 - 1)
        norm += amp
        amp *= gain
        cells *= lac
    return total / norm


def ridged(n, base_cells, octaves, seed):
    total = np.zeros((n, n), np.float32)
    amp, cells, norm, w = 1.0, base_cells, 0.0, np.ones((n, n), np.float32)
    for o in range(octaves):
        c = int(round(cells))
        if c >= n // 2:
            break
        v = 1.0 - np.abs(value_noise(n, c, seed + o * 37) * 2 - 1)
        v = v * v
        total += amp * v * w
        w = np.clip(v * 1.6, 0, 1)
        norm += amp
        amp *= 0.5
        cells *= 2.0
    return total / norm


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- geometry helpers (normalized u,v in [0,1])
def catmull(points, samples_per_seg=24):
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = (np.array(pts[i + k], float) for k in (-1, 0, 1, 2))
        for s in range(samples_per_seg):
            t = s / samples_per_seg
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(np.array(points[-1], float))
    return np.array(out)


def resample(poly, step):
    """Resample a polyline (in metres) at a fixed spacing."""
    seg = np.linalg.norm(np.diff(poly, axis=0), axis=1)
    d = np.concatenate([[0], np.cumsum(seg)])
    L = d[-1]
    t = np.arange(0, L, step)
    t = np.append(t, L)
    x = np.interp(t, d, poly[:, 0])
    y = np.interp(t, d, poly[:, 1])
    return np.stack([x, y], 1)


def dist_to_polyline(n, poly_px, maxd):
    """Distance (in pixels) from each cell of an n x n grid to a polyline given in pixel coords; capped at maxd.
    Also returns the parameter index (nearest sample) for each cell."""
    img = np.ones((n, n), bool)
    pts = resample(poly_px, 0.5)
    ix = np.clip(np.round(pts[:, 0]).astype(int), 0, n - 1)
    iy = np.clip(np.round(pts[:, 1]).astype(int), 0, n - 1)
    img[iy, ix] = False
    d, inds = ndimage.distance_transform_edt(img, return_indices=True)
    return np.minimum(d, maxd), inds


def m2px(p, n):
    """metres (origin centre) -> pixel coords for an n grid"""
    return (np.asarray(p, float) + SIZE_M / 2) / SIZE_M * n


def uv2m(u, v):
    return np.array([u * SIZE_M - SIZE_M / 2, v * SIZE_M - SIZE_M / 2])


# ---------------------------------------------------------------- the authored layout
TOWNS = [
    # name, u, v, radius m, street angle deg (0 = street runs east-west), kind
    dict(id="bitter_spring", name="Bitter Spring", u=0.455, v=0.475, r=230, angle=18, kind="rail_town"),
    dict(id="coldwater", name="Coldwater", u=0.285, v=0.235, r=160, angle=-35, kind="mining_camp"),
    dict(id="mesquite_wells", name="Mesquite Wells", u=0.235, v=0.640, r=170, angle=5, kind="desert_stop"),
    dict(id="port_linden", name="Port Linden", u=0.835, v=0.505, r=260, angle=82, kind="port_town"),
]

POIS = [
    dict(id="caddell_camp", name="Outfit camp, Willow Bend", u=0.405, v=0.405, kind="camp", r=40),
    dict(id="halvorsen_ranch", name="Halvorsen Ranch", u=0.540, v=0.640, kind="ranch", r=70),
    dict(id="dunmore_homestead", name="Dunmore homestead", u=0.660, v=0.300, kind="homestead", r=35),
    dict(id="thornwood_logging", name="Thornwood logging camp", u=0.700, v=0.170, kind="logging", r=60),
    dict(id="san_lazaro", name="San Lazaro mission ruin", u=0.130, v=0.830, kind="ruin", r=50),
    dict(id="greer_post", name="Greer's trading post", u=0.610, v=0.520, kind="trading_post", r=35),
    dict(id="trapper_cabin_n", name="Trapper's cabin", u=0.170, v=0.300, kind="cabin", r=20),
    dict(id="windmill_flats", name="Windmill flats", u=0.420, v=0.760, kind="homestead", r=30),
]

RIVER_MAIN = [(0.250, 0.080), (0.290, 0.170), (0.335, 0.280), (0.380, 0.360), (0.430, 0.440), (0.470, 0.470),
              (0.530, 0.520), (0.610, 0.560), (0.690, 0.585), (0.760, 0.600), (0.810, 0.625), (0.860, 0.650),
              (0.930, 0.660)]
CREEKS = [
    [(0.620, 0.060), (0.630, 0.200), (0.600, 0.330), (0.570, 0.430), (0.540, 0.520)],   # Thornwood Creek
    [(0.100, 0.420), (0.200, 0.470), (0.300, 0.470), (0.400, 0.450), (0.437, 0.452)],   # Dry Fork (seasonal)
]
LAKE = dict(u=0.95, v=0.62, ru=0.12, rv=0.30)   # ellipse on the east edge

RAIL = [(0.000, 0.600), (0.120, 0.630), (0.235, 0.625), (0.340, 0.560), (0.440, 0.488), (0.520, 0.500),
        (0.640, 0.480), (0.760, 0.495), (0.835, 0.490)]

ROADS = [  # pairs routed with A* over slope cost
    ("bitter_spring", "coldwater"), ("bitter_spring", "mesquite_wells"), ("bitter_spring", "port_linden"),
    ("bitter_spring", "caddell_camp"), ("bitter_spring", "halvorsen_ranch"), ("port_linden", "dunmore_homestead"),
    ("dunmore_homestead", "thornwood_logging"), ("mesquite_wells", "san_lazaro"), ("bitter_spring", "greer_post"),
    ("coldwater", "trapper_cabin_n"), ("halvorsen_ranch", "windmill_flats"), ("windmill_flats", "mesquite_wells"),
]


def place(id_):
    for t in TOWNS + POIS:
        if t["id"] == id_:
            return t
    raise KeyError(id_)


# ---------------------------------------------------------------- terrain synthesis
def macro_height(n):
    """Large-scale landforms at resolution n (metres)."""
    t0 = time.time()
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32) / n          # v (south), u (east)
    warp_u = fbm(n, 4, 4, SEED + 1) * 0.06
    warp_v = fbm(n, 4, 4, SEED + 2) * 0.06
    u = xs + warp_u
    v = ys + warp_v

    # Kestrel Range: a ridge line NW, falloff by distance to ridge
    ridge = catmull([(-0.05, 0.42), (0.08, 0.30), (0.18, 0.18), (0.30, 0.08), (0.45, -0.04)])
    rp = ridge * n
    dr, _ = dist_to_polyline(n, rp, n)
    dr = dr / n
    # use warped distance approx
    mount = smoothstep(0.30, 0.02, dr + (warp_u + warp_v) * 0.6)
    peaks = ridged(n, 6, 7, SEED + 3)
    h = 210 + fbm(n, 3, 6, SEED + 4) * 35                       # rolling base
    h += mount * (380 + peaks * 1050)
    h += smoothstep(0.42, 0.10, dr) * 160                       # foothill skirt

    # Thornwood hills NE
    hills = smoothstep(0.55, 0.15, np.hypot((u - 0.68) * 1.2, (v - 0.22) * 1.0))
    h += hills * (120 + ridged(n, 10, 6, SEED + 5) * 260)

    # Ocotillo Breaks SW: raised plateau cut by canyons, terraced mesas
    desert = smoothstep(0.38, 0.12, np.hypot((u - 0.17) * 1.0, (v - 0.78) * 1.1))
    mesa_n = fbm(n, 9, 5, SEED + 6)
    plateau = smoothstep(-0.05, 0.12, mesa_n)                   # mesa tops where noise high
    canyon = 1 - smoothstep(0.0, 0.06, np.abs(fbm(n, 5, 4, SEED + 7)))   # winding canyon network
    desert_h = 70 + plateau * 150 - canyon * 90
    h += desert * desert_h

    # east: land falls to the lake
    h -= smoothstep(0.55, 1.0, u) * 70
    # plains south-centre flatter
    plains = smoothstep(0.35, 0.05, np.hypot((u - 0.52) * 1.0, (v - 0.70) * 1.3))
    h = h * (1 - plains * 0.35) + plains * 0.35 * (215 + fbm(n, 6, 4, SEED + 8) * 12)
    print(f"  macro {n}: {time.time()-t0:.1f}s", flush=True)
    return h.astype(np.float32), dict(mount=mount, desert=desert, hills=hills, plains=plains)


D8 = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]


def flow_accumulation(h):
    """D8 flow accumulation (cells draining through each cell)."""
    n = h.shape[0]
    pad = np.pad(h, 1, mode='edge')
    best = np.zeros_like(h)
    rec = np.full(h.shape, -1, np.int64)
    idx = np.arange(n * n).reshape(n, n)
    for (dy, dx) in D8:
        nb = pad[1 + dy:1 + dy + n, 1 + dx:1 + dx + n]
        drop = (h - nb) / math.hypot(dy, dx)
        better = drop > best
        best = np.where(better, drop, best)
        ny = np.clip(np.arange(n)[:, None] + dy, 0, n - 1)
        nx = np.clip(np.arange(n)[None, :] + dx, 0, n - 1)
        rec = np.where(better, ny * n + nx, rec)
    order = np.argsort(-h, axis=None)
    acc = np.ones(n * n, np.float64)
    recf = rec.ravel()
    # sequential pass (fine at 512-1024)
    accl = acc.tolist()
    recl = recf.tolist()
    for i in order.tolist():
        r = recl[i]
        if r >= 0:
            accl[r] += accl[i]
    return np.array(accl).reshape(n, n), best, rec


def stream_power_erosion(h, iters, cell_m, k=0.0035, m=0.5, n_exp=1.0, uplift=None):
    """Implicit-ish stream power erosion steps + thermal smoothing."""
    t0 = time.time()
    for it in range(iters):
        acc, slope, rec = flow_accumulation(h)
        area = acc * cell_m * cell_m
        e = k * np.power(area, m) * np.power(np.maximum(slope / cell_m, 0), n_exp)
        e = np.minimum(e, 18.0)
        h = h - e
        # thermal: limit slope (talus) ~ 38 deg
        lap = ndimage.uniform_filter(h, 3) - h
        h = h + 0.15 * lap
        if uplift is not None:
            h = h + uplift
    print(f"  stream power x{iters}: {time.time()-t0:.1f}s", flush=True)
    return h, acc


def droplet_erosion(h, drops, steps, cell_m, seed):
    """Vectorised particle hydraulic erosion (all droplets advance together)."""
    t0 = time.time()
    n = h.shape[0]
    r = np.random.default_rng(seed)
    hf = h.astype(np.float64).copy()
    sed_map = np.zeros_like(hf)
    batch = 32768
    inertia, cap_k, dep_k, ero_k, evap, g = 0.08, 6.0, 0.25, 0.25, 0.03, 9.0
    min_slope = 0.002
    for b0 in range(0, drops, batch):
        nb = min(batch, drops - b0)
        px = r.random(nb) * (n - 2) + 0.5
        py = r.random(nb) * (n - 2) + 0.5
        dx = np.zeros(nb); dy = np.zeros(nb)
        vel = np.ones(nb); water = np.ones(nb); sed = np.zeros(nb)
        alive = np.ones(nb, bool)
        for s in range(steps):
            ix = px.astype(np.int64); iy = py.astype(np.int64)
            fx = px - ix; fy = py - iy
            h00 = hf[iy, ix]; h10 = hf[iy, ix + 1]; h01 = hf[iy + 1, ix]; h11 = hf[iy + 1, ix + 1]
            gx = (h10 - h00) * (1 - fy) + (h11 - h01) * fy
            gy = (h01 - h00) * (1 - fx) + (h11 - h10) * fx
            hold = h00 * (1 - fx) * (1 - fy) + h10 * fx * (1 - fy) + h01 * (1 - fx) * fy + h11 * fx * fy
            dx = dx * inertia - gx * (1 - inertia)
            dy = dy * inertia - gy * (1 - inertia)
            ln = np.hypot(dx, dy) + 1e-9
            dx /= ln; dy /= ln
            npx = px + dx; npy = py + dy
            alive &= (npx > 1) & (npx < n - 2) & (npy > 1) & (npy < n - 2) & (ln > 1e-6)
            npx = np.clip(npx, 1, n - 2.001); npy = np.clip(npy, 1, n - 2.001)
            jx = npx.astype(np.int64); jy = npy.astype(np.int64)
            gfx = npx - jx; gfy = npy - jy
            hnew = (hf[jy, jx] * (1 - gfx) * (1 - gfy) + hf[jy, jx + 1] * gfx * (1 - gfy)
                    + hf[jy + 1, jx] * (1 - gfx) * gfy + hf[jy + 1, jx + 1] * gfx * gfy)
            dh = hnew - hold
            cap = np.maximum(-dh, min_slope) * vel * water * cap_k
            deposit = np.where((sed > cap) | (dh > 0),
                               np.where(dh > 0, np.minimum(dh, sed), (sed - cap) * dep_k), 0.0)
            erode = np.where((sed <= cap) & (dh <= 0), np.minimum(np.minimum((cap - sed) * ero_k, -dh * 0.35), 0.6), 0.0)
            amt = (deposit - erode) * alive
            sed = sed - amt
            # bilinear splat onto the four corners
            w00 = (1 - fx) * (1 - fy); w10 = fx * (1 - fy); w01 = (1 - fx) * fy; w11 = fx * fy
            for (oy, ox, w) in ((0, 0, w00), (0, 1, w10), (1, 0, w01), (1, 1, w11)):
                np.add.at(hf, (iy + oy, ix + ox), amt * w)
                np.add.at(sed_map, (iy + oy, ix + ox), np.maximum(amt, 0) * w)
            vel = np.minimum(np.sqrt(np.maximum(vel * vel + (-dh) * g, 0.01)), 6.0)
            water *= (1 - evap)
            px, py = npx, npy
    print(f"  droplets {drops} x{steps}: {time.time()-t0:.1f}s", flush=True)
    return hf.astype(np.float32), sed_map.astype(np.float32)


# ---------------------------------------------------------------- rivers, lake, towns, roads
def meander(pts, width_m):
    """Displace a resampled polyline sideways with two superposed meander waves (amplitude grows with width)."""
    d = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))])
    tang = np.gradient(pts, axis=0)
    tang /= np.linalg.norm(tang, axis=1, keepdims=True) + 1e-9
    nrm = np.stack([-tang[:, 1], tang[:, 0]], 1)
    r = np.random.default_rng(int(width_m * 1000) + SEED)
    ph1, ph2 = r.random() * 6.28, r.random() * 6.28
    a = width_m * 2.2
    off = a * np.sin(d / (width_m * 14) + ph1 + 0.8 * np.sin(d / (width_m * 41) + ph2)) + a * 0.5 * np.sin(d / (width_m * 5.5) + ph2)
    taper = np.minimum(1, np.minimum(d, d[-1] - d) / (width_m * 10))
    out = pts + nrm * (off * taper)[:, None]
    return resample(out, 8.0)


def carve_river(h, poly_uv, width_m, depth_m, valley_m, n, name, min_drop=0.0004, keep=None):
    """Carve a river channel with monotone bed. Returns the feature dict (polyline with bed and surface heights).
    keep (0..1 per cell, optional): settlement cores where only the channel is cut and the floodplain is left alone."""
    cell = SIZE_M / n
    pts_m = catmull([uv2m(*p) for p in poly_uv], 20)
    pts_m = meander(resample(pts_m, 8.0), width_m)
    px = m2px(pts_m, n)
    # sample smoothed terrain along the path
    hs = ndimage.gaussian_filter(h, 6)
    samp = ndimage.map_coordinates(hs, [px[:, 1], px[:, 0]], order=1)
    # monotone non-increasing bank height with minimum gradient
    bank = np.empty_like(samp)
    cur = samp[0]
    seglen = np.concatenate([[0], np.linalg.norm(np.diff(pts_m, axis=0), axis=1)])
    for i in range(len(samp)):
        cur = min(cur - seglen[i] * min_drop, samp[i])
        bank[i] = cur
    widths = width_m * (0.55 + 0.45 * np.linspace(0, 1, len(bank)))   # widens downstream
    surface = bank - 0.6
    bed = bank - depth_m * (0.6 + 0.4 * np.linspace(0, 1, len(bank)))
    d_px, inds = dist_to_polyline(n, px, valley_m / cell * 1.2)
    d_m = d_px * cell
    # nearest sample index for each cell
    near = np.zeros((n, n), np.int64)
    # map nearest pixel back to polyline sample via KD-ish lookup: rasterize sample indices
    lab = np.full((n, n), -1, np.int64)
    rs = resample(px, 0.5)
    tpar = np.linspace(0, len(px) - 1, len(rs))
    rx = np.clip(np.round(rs[:, 0]).astype(int), 0, n - 1)
    ry = np.clip(np.round(rs[:, 1]).astype(int), 0, n - 1)
    lab[ry, rx] = np.round(tpar).astype(np.int64)
    near = lab[inds[0], inds[1]]
    near = np.clip(near, 0, len(px) - 1)
    w_half = widths[near] * 0.5
    bed_c = bed[near]; bank_c = bank[near]
    # channel profile: smooth U shape
    t = np.clip(d_m / np.maximum(w_half, 1), 0, 1)
    chan = bed_c + (bank_c - bed_c) * (t * t * (3 - 2 * t))
    inside = d_m < w_half
    floodplain = smoothstep(valley_m, w_half * 1.2, d_m)          # 1 near channel
    target = np.where(inside, chan, np.minimum(h, bank_c + (h - bank_c) * (1 - floodplain * 0.85)))
    if keep is not None:
        target = target * (1 - keep) + h * keep
    hn = np.where(d_m < valley_m * 1.2, np.where(inside, chan, np.minimum(h, target)), h)
    # never raise terrain except inside channel (handled) — banks may only be cut down
    feature = dict(name=name, points=[[round(float(p[0]), 2), round(float(p[1]), 2)] for p in pts_m],
                   surface=[round(float(s), 2) for s in surface], width=[round(float(w), 2) for w in widths],
                   bed=[round(float(b), 2) for b in bed])
    return hn.astype(np.float32), feature, d_m


def flatten_disc(h, n, center_m, r_m, target=None, blend_m=60.0):
    cell = SIZE_M / n
    c = m2px(center_m, n)
    ys, xs = np.ogrid[0:n, 0:n]
    d = np.hypot(xs - c[0], ys - c[1]) * cell
    if target is None:
        ci = (int(round(c[1])), int(round(c[0])))
        target = float(ndimage.gaussian_filter(h[max(0, ci[0]-40):ci[0]+40, max(0, ci[1]-40):ci[1]+40], 8).mean())
    w = smoothstep(r_m + blend_m, r_m * 0.85, d)
    return (h * (1 - w) + target * w).astype(np.float32), target


def astar_road(cost_h, start_px, goal_px, cell_m, slope_w=900.0, water=None):
    """A* on a coarse grid; cost penalises slope heavily. Returns list of (x,y) pixel coords on that grid."""
    n = cost_h.shape[0]
    sx, sy = int(start_px[0]), int(start_px[1])
    gx, gy = int(goal_px[0]), int(goal_px[1])
    INF = 1e18
    gscore = np.full((n, n), INF)
    came = np.full((n, n), -1, np.int64)
    gscore[sy, sx] = 0
    openq = [(0.0, sx, sy)]
    nbrs = [(dx, dy, math.hypot(dx, dy)) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
    nbrs += [(dx, dy, math.hypot(dx, dy)) for dx, dy in ((2, 1), (1, 2), (-1, 2), (-2, 1), (-2, -1), (-1, -2), (1, -2), (2, -1))]
    hl = cost_h.tolist()
    wl = water.tolist() if water is not None else None
    gl = gscore  # numpy for speed of reset
    while openq:
        f, x, y = heapq.heappop(openq)
        if x == gx and y == gy:
            break
        g0 = gl[y, x]
        if f - math.hypot(gx - x, gy - y) * cell_m > g0 + 1e-6:
            continue
        h0 = hl[y][x]
        for dx, dy, dl in nbrs:
            nx, ny = x + dx, y + dy
            if nx < 0 or ny < 0 or nx >= n or ny >= n:
                continue
            dz = abs(hl[ny][nx] - h0)
            run = dl * cell_m
            grade = dz / run
            c = run * (1 + slope_w * grade * grade) + (run * 40 if wl is not None and wl[ny][nx] else 0)
            ng = g0 + c
            if ng < gl[ny, nx]:
                gl[ny, nx] = ng
                came[ny, nx] = y * n + x
                heapq.heappush(openq, (ng + math.hypot(gx - nx, gy - ny) * cell_m, nx, ny))
    path = []
    cur = gy * n + gx
    while cur >= 0:
        y, x = divmod(int(cur), n)
        path.append((x, y))
        if x == sx and y == sy:
            break
        cur = came[y, x]
    return path[::-1]


def smooth_path(pts, it=6):
    p = np.array(pts, float)
    for _ in range(it):
        q = p.copy()
        q[1:-1] = 0.25 * p[:-2] + 0.5 * p[1:-1] + 0.25 * p[2:]
        p = q
    return p


def grade_corridor(h, n, poly_m, half_w, blend, max_grade, cut=8.0, fill=5.0, smooth_profile=40, pins=None):
    """Grade a road/rail corridor: smooth longitudinal profile (grade-limited, then held within cut/fill of the
    ground), flat cross-section, side slopes ~1:2 down/up to the natural terrain."""
    cell = SIZE_M / n
    pts = resample(poly_m, 4.0)
    px = m2px(pts, n)
    ground = ndimage.map_coordinates(ndimage.gaussian_filter(h, 2), [px[:, 1], px[:, 0]], order=1)
    prof = ndimage.gaussian_filter1d(ground, smooth_profile / 4.0, mode='nearest')
    core = np.zeros(len(prof), bool)
    level = np.zeros(len(prof), np.float32)
    if pins:
        # settlements: the line runs at the settlement's ground level through its disc (no embankment through
        # town); the grade limit then shapes the approaches (cuttings/fills) away from the pinned core
        for (cx, cz, r, lv) in pins:
            dd = np.hypot(pts[:, 0] - cx, pts[:, 1] - cz)
            m = dd < r * 0.9
            core |= m
            level[m] = lv
        prof = np.where(core, level, prof)
    for _ in range(4 if pins else 2):
        for i in range(1, len(prof)):
            prof[i] = np.clip(prof[i], prof[i - 1] - max_grade * 4.0, prof[i - 1] + max_grade * 4.0)
        for i in range(len(prof) - 2, -1, -1):
            prof[i] = np.clip(prof[i], prof[i + 1] - max_grade * 4.0, prof[i + 1] + max_grade * 4.0)
        prof = np.where(core, level, prof)
    prof = np.clip(prof, ground - cut, ground + fill)
    prof = np.where(core, level, prof)
    prof = ndimage.gaussian_filter1d(prof, 3.0, mode='nearest')
    reach = half_w + blend + max(cut, fill) * 2.0
    d_px, inds = dist_to_polyline(n, px, reach / cell + 4)
    d = d_px * cell
    lab = np.full((n, n), -1, np.int64)
    rs = resample(px, 0.5)
    tpar = np.linspace(0, len(px) - 1, len(rs))
    rx = np.clip(np.round(rs[:, 0]).astype(int), 0, n - 1)
    ry = np.clip(np.round(rs[:, 1]).astype(int), 0, n - 1)
    lab[ry, rx] = np.round(tpar).astype(np.int64)
    near = np.clip(lab[inds[0], inds[1]], 0, len(prof) - 1)
    target = prof[near]
    side = np.minimum(np.abs(target - h) * 2.0 + blend, reach - half_w - 1.0)   # 1:2 embankment / cutting slope
    w = smoothstep(half_w + side, half_w, d) * (d < reach - 0.5)
    hn = h * (1 - w) + target * w
    return hn.astype(np.float32), pts, prof


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=os.path.join(os.path.dirname(__file__), '..', 'data', 'world'))
    ap.add_argument('--fast', action='store_true', help='skip droplet erosion (quick preview)')
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    T = time.time()
    print("worldgen: Sable River country, seed", SEED, flush=True)

    # 1. macro terrain at 512 (16 m) + stream-power erosion
    n0 = 512
    h0, masks0 = macro_height(n0)
    h0, acc0 = stream_power_erosion(h0, 24, SIZE_M / n0)

    # 2. upsample to 2048 (4 m), add mid detail, droplet erosion
    n1 = 2048
    h1 = ndimage.zoom(h0, n1 / n0, order=3).astype(np.float32)
    masks1 = {k: ndimage.zoom(v, n1 / n0, order=1) for k, v in masks0.items()}
    mount1 = masks1['mount']
    detail = ridged(n1, 64, 4, SEED + 20) - 0.35
    h1 += detail * (4 + mount1 * 45 + masks1['hills'] * 10)
    h1 += fbm(n1, 96, 3, SEED + 21) * 2.5
    if not args.fast:
        h1, sed1 = droplet_erosion(h1, 600000, 80, SIZE_M / n1, SEED + 22)
    else:
        sed1 = np.zeros_like(h1)

    # mesa terracing in the desert (after erosion so the steps stay crisp)
    desert1 = masks1['desert']
    terr = np.floor(h1 / 18.0) * 18.0 + smoothstep(0.0, 1.0, (h1 % 18.0) / 18.0) ** 3 * 18.0
    h1 = h1 * (1 - desert1 * 0.7) + terr * desert1 * 0.7

    # 3. lake on the east edge
    ys, xs = np.mgrid[0:n1, 0:n1].astype(np.float32) / n1
    lake_n = fbm(n1, 12, 4, SEED + 30) * 0.035
    ld = np.hypot((xs - LAKE['u']) / LAKE['ru'], (ys - LAKE['v']) / LAKE['rv']) + lake_n * 4
    lake_w = smoothstep(1.15, 0.85, ld)
    lake_bed = LAKE_LEVEL - 4 - smoothstep(0.95, 0.2, ld) * 26
    shore = LAKE_LEVEL + 2 + (h1 - LAKE_LEVEL) * smoothstep(0.85, 1.6, ld)
    h1 = np.where(ld < 1.6, np.minimum(h1, np.where(ld < 0.95, lake_bed, shore)), h1)
    h1 = np.maximum(h1, LAKE_LEVEL - 30)

    feats = dict(size_m=SIZE_M, height_res=N, control_res=NC, h_range=H_RANGE, lake_level=LAKE_LEVEL,
                 seed=SEED, towns=[], pois=[], roads=[], rivers=[], rail=None,
                 lake=dict(u=LAKE['u'], v=LAKE['v'], ru=LAKE['ru'], rv=LAKE['rv'], level=LAKE_LEVEL))
    # 4. towns and POIs: flatten plots (before the rivers, so a river through a town is carved at town level
    #    instead of being filled in by the flattening)
    for t in TOWNS:
        c = uv2m(t['u'], t['v'])
        h1, th = flatten_disc(h1, n1, c, t['r'], blend_m=90)
        feats['towns'].append(dict(id=t['id'], name=t['name'], x=round(float(c[0]), 1), z=round(float(c[1]), 1),
                                   y=round(th, 2), r=t['r'], angle=t['angle'], kind=t['kind']))
    for p in POIS:
        c = uv2m(p['u'], p['v'])
        h1, th = flatten_disc(h1, n1, c, p['r'], blend_m=40)
        feats['pois'].append(dict(id=p['id'], name=p['name'], x=round(float(c[0]), 1), z=round(float(c[1]), 1),
                                  y=round(th, 2), r=p['r'], kind=p['kind']))

    # 5. rivers (settlement cores keep their flattened ground outside the channel)
    keep = np.zeros((n1, n1), np.float32)
    ys_c, xs_c = np.ogrid[0:n1, 0:n1]
    for t in feats['towns'] + feats['pois']:
        cp = m2px((t['x'], t['z']), n1)
        dd = np.hypot(xs_c - cp[0], ys_c - cp[1]) * (SIZE_M / n1)
        keep = np.maximum(keep, smoothstep(t['r'] + 20.0, t['r'] * 0.85, dd))
    river_dist = np.full((n1, n1), 1e9, np.float32)
    h1, rf, d_m = carve_river(h1, RIVER_MAIN, 46, 4.5, 420, n1, "Sable River", keep=keep)
    feats['rivers'].append(rf); river_dist = np.minimum(river_dist, np.where(d_m < d_m.max() - 1.0, d_m, 1e9))
    h1, rf, d_m = carve_river(h1, CREEKS[0], 14, 2.2, 160, n1, "Thornwood Creek", min_drop=0.0008, keep=keep)
    feats['rivers'].append(rf); river_dist = np.minimum(river_dist, np.where(d_m < d_m.max() - 1.0, d_m, 1e9))
    h1, rf, d_m = carve_river(h1, CREEKS[1], 10, 1.6, 120, n1, "Dry Fork", min_drop=0.0008, keep=keep)
    feats['rivers'].append(rf); river_dist = np.minimum(river_dist, np.where(d_m < d_m.max() - 1.0, d_m, 1e9))

    # 6. rail: smooth spline, graded at <= 1.5 %
    rail_m = catmull([uv2m(*p) for p in RAIL], 24)
    pins = [(t['x'], t['z'], t['r'], t['y']) for t in feats['towns']]
    h1, rail_pts, rail_prof = grade_corridor(h1, n1, rail_m, 4.0, 6.0, 0.015, cut=9.0, fill=6.0, smooth_profile=120, pins=pins)
    feats['rail'] = dict(points=[[round(float(p[0]), 2), round(float(p[1]), 2), round(float(z), 2)]
                                 for p, z in zip(rail_pts, rail_prof)])

    # 7. roads: A* on 256 grid (32 m), avoid water, then grade
    nr = 256
    hc = ndimage.zoom(ndimage.gaussian_filter(h1, 4), nr / n1, order=1)
    water_c = ndimage.zoom((river_dist < 30).astype(np.float32), nr / n1, order=0) > 0.5
    water_c |= ndimage.zoom((h1 < LAKE_LEVEL + 0.5).astype(np.float32), nr / n1, order=0) > 0.5
    road_mask = np.zeros((n1, n1), np.float32)
    for a, b in ROADS:
        pa, pb = place(a), place(b)
        ca = m2px(uv2m(pa['u'], pa['v']), nr); cb = m2px(uv2m(pb['u'], pb['v']), nr)
        wc = water_c.copy()
        for c in (ca, cb):
            wc[max(0, int(c[1]) - 3):int(c[1]) + 4, max(0, int(c[0]) - 3):int(c[0]) + 4] = False
        path = astar_road(hc, ca, cb, SIZE_M / nr, water=wc)
        pm = smooth_path(path, 10) / nr * SIZE_M - SIZE_M / 2
        pm = catmull(list(pm[::2]) + [pm[-1]], 6)
        h1, rpts, rprof = grade_corridor(h1, n1, pm, 3.0, 4.0, 0.09, cut=3.0, fill=2.0, smooth_profile=16)
        d_px, _ = dist_to_polyline(n1, m2px(rpts, n1), 20)
        road_mask = np.maximum(road_mask, smoothstep(4.5, 1.5, d_px * SIZE_M / n1))
        feats['roads'].append(dict(a=a, b=b, points=[[round(float(p[0]), 2), round(float(p[1]), 2), round(float(z), 2)]
                                                     for p, z in zip(rpts[::2], rprof[::2])]))
    print(f"  roads: {len(ROADS)} routed", flush=True)

    # 8. final 4096 height: upsample + fine detail
    h = ndimage.zoom(h1, N / n1, order=3).astype(np.float32)
    road_hi = ndimage.zoom(road_mask, N / n1, order=1)
    fine = fbm(N, 512, 2, SEED + 40) * 0.35
    mount_hi = ndimage.zoom(mount1, N / n1, order=1)
    rock = (ridged(N, 384, 2, SEED + 41) - 0.4) * (0.4 + mount_hi * 2.5)
    keep_hi = ndimage.zoom(keep, N / n1, order=1)          # settlement cores stay smooth for building plots
    h += (fine + rock) * (1 - road_hi) * (1 - keep_hi * 0.9)
    h = np.clip(h, 0, H_RANGE - 1)

    # 9. control map (2048)
    gy, gx = np.gradient(h1, SIZE_M / n1)
    slope = np.hypot(gx, gy)
    moist = np.clip(1.0 - river_dist / 450.0, 0, 1) ** 1.5 * 0.75
    moist += np.clip(1.0 - (np.abs(h1 - LAKE_LEVEL) / 25.0), 0, 1) * 0.3
    moist += (fbm(n1, 16, 4, SEED + 50) * 0.5 + 0.5) * 0.3 - 0.05
    moist -= desert1 * 0.6
    moist += mount1 * 0.3 + masks1['hills'] * 0.25
    moist = np.clip(moist, 0, 1)
    biome = 0.5 - desert1 * 0.5 + (mount1 * 0.5 + masks1['hills'] * 0.45) * smoothstep(1500, 1100, h1)
    biome = np.clip(biome + (moist - 0.4) * 0.25, 0, 1)
    sed_n = np.clip(ndimage.gaussian_filter(sed1, 1.5) * 1.5, 0, 1)
    ctrl = np.stack([road_mask, moist, biome, sed_n], -1)
    ctrl8 = (np.clip(ctrl, 0, 1) * 255 + 0.5).astype(np.uint8)

    # 10. write
    h16 = np.clip(h / H_RANGE * 65535 + 0.5, 0, 65535).astype('<u2')
    h16.tofile(os.path.join(args.out, 'height.r16'))
    ctrl8.tofile(os.path.join(args.out, 'control.bin'))
    # min/max per 64x64-sample leaf (128 m) for terrain LOD culling: float32 [64][64][2]
    hl = h.reshape(64, 64, 64, 64)
    mm = np.stack([hl.min(axis=(1, 3)), hl.max(axis=(1, 3))], -1).astype('<f4')
    mm.tofile(os.path.join(args.out, 'minmax.bin'))
    stats = dict(min=float(h.min()), max=float(h.max()), mean=float(h.mean()),
                 max_slope_deg=float(np.degrees(np.arctan(slope.max()))))
    feats['stats'] = stats
    with open(os.path.join(args.out, 'features.json'), 'w') as f:
        json.dump(feats, f, separators=(',', ':'))
    write_preview(h1, ctrl, feats, os.path.join(args.out, 'preview.png'))
    write_paper_map(h1, ctrl, feats, os.path.join(args.out, 'map.png'))
    print(f"worldgen done in {time.time()-T:.1f}s  stats={stats}", flush=True)


def write_preview(h, ctrl, feats, path, size=1024):
    from PIL import Image, ImageDraw
    hs = ndimage.zoom(h, size / h.shape[0], order=1)
    c = ndimage.zoom(ctrl, (size / ctrl.shape[0], size / ctrl.shape[1], 1), order=1)
    gy, gx = np.gradient(hs, SIZE_M / size)
    light = np.clip(0.5 + (-gx * 0.7 - gy * 0.7) * 1.2, 0, 1)
    biome = c[..., 2]; moist = c[..., 1]
    desert = np.array([0.72, 0.52, 0.36]); grass = np.array([0.58, 0.58, 0.34]); forest = np.array([0.22, 0.32, 0.20])
    col = np.where(biome[..., None] < 0.5, desert + (grass - desert) * (biome[..., None] * 2),
                   grass + (forest - grass) * ((biome[..., None] - 0.5) * 2))
    snow = smoothstep(1100, 1250, hs)[..., None]
    col = col * (1 - snow) + np.array([0.95, 0.95, 0.97]) * snow
    rocky = smoothstep(0.6, 1.0, np.hypot(gx, gy))[..., None]
    col = col * (1 - rocky) + np.array([0.45, 0.42, 0.40]) * rocky
    col = col * (0.35 + 0.85 * light[..., None])
    road = c[..., 0][..., None]
    col = col * (1 - road * 0.8) + np.array([0.80, 0.70, 0.55]) * road * 0.8
    water = (hs < LAKE_LEVEL + 0.2)[..., None]
    col = np.where(water, np.array([0.18, 0.32, 0.42]), col)
    img = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    s = size / SIZE_M
    for r in feats['rivers']:
        pts = [((p[0] + SIZE_M / 2) * s, (p[1] + SIZE_M / 2) * s) for p in r['points']]
        d.line(pts, fill=(40, 80, 120), width=3 if r['name'] == 'Sable River' else 2)
    rp = [((p[0] + SIZE_M / 2) * s, (p[1] + SIZE_M / 2) * s) for p in feats['rail']['points']]
    d.line(rp, fill=(30, 30, 30), width=2)
    for t in feats['towns'] + feats['pois']:
        x, y = (t['x'] + SIZE_M / 2) * s, (t['z'] + SIZE_M / 2) * s
        rr = 6 if 'angle' in t else 3
        d.ellipse([x - rr, y - rr, x + rr, y + rr], outline=(0, 0, 0), fill=(200, 40, 30) if rr > 3 else (240, 220, 80))
        d.text((x + 8, y - 6), t['name'], fill=(0, 0, 0))
    img.save(path)


def write_paper_map(h, ctrl, feats, path, size=2048):
    """In-game map: aged paper, ink hillshade + contour lines, blue-ink water, dashed trails, rail, lettering."""
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
    fdir = os.path.join(os.path.dirname(__file__), '..', 'assets', 'fonts')
    def font(name, sz):
        try:
            return ImageFont.truetype(os.path.join(fdir, name), sz)
        except Exception:
            return ImageFont.load_default()
    hs = ndimage.zoom(h, size / h.shape[0], order=1)
    c = ndimage.zoom(ctrl, (size / ctrl.shape[0], size / ctrl.shape[1], 1), order=1)
    rng2 = np.random.default_rng(5)
    paper = np.array([0.88, 0.80, 0.64])
    stain = ndimage.gaussian_filter(rng2.random((size, size)), 40)
    stain = (stain - stain.min()) / (stain.max() - stain.min())
    fib = ndimage.gaussian_filter(rng2.random((size, size)), 1.2)
    base = paper[None, None, :] * (0.9 + 0.12 * stain[..., None]) * (0.96 + 0.06 * fib[..., None])
    gy, gx = np.gradient(hs, SIZE_M / size)
    shade = np.clip(0.5 + (-gx * 0.6 - gy * 0.6) * 1.4, 0, 1)
    ink = np.array([0.30, 0.22, 0.15])
    hill = (1 - shade) * 0.55 * smoothstep(0.02, 0.5, np.hypot(gx, gy))
    col = base * (1 - hill[..., None]) + ink * hill[..., None]
    # contour lines every 50 m, heavier every 250 m
    for step, wgt in ((50.0, 0.25), (250.0, 0.5)):
        f = np.abs(((hs / step) + 0.5) % 1.0 - 0.5) * step
        line = smoothstep(1.4 * step / 50.0, 0.0, f / np.maximum(np.hypot(gx, gy) * SIZE_M / size, 0.05)) * wgt
        col = col * (1 - line[..., None]) + ink * line[..., None]
    forest = smoothstep(0.7, 0.9, c[..., 2]) * (hs < 1150)
    col = col * (1 - forest[..., None] * 0.12) + np.array([0.33, 0.38, 0.22]) * forest[..., None] * 0.12
    desert = smoothstep(0.3, 0.1, c[..., 2])
    col = col * (1 - desert[..., None] * 0.12) + np.array([0.78, 0.5, 0.32]) * desert[..., None] * 0.12
    water = (hs < LAKE_LEVEL + 0.2)
    col = np.where(water[..., None], base * 0.7 + np.array([0.25, 0.38, 0.48]) * 0.3, col)
    img = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    s = size / SIZE_M
    blue = (48, 78, 104)
    for r in feats['rivers']:
        pts = [((p[0] + SIZE_M / 2) * s, (p[1] + SIZE_M / 2) * s) for p in r['points']]
        d.line(pts, fill=blue, width=5 if r['name'] == 'Sable River' else 3, joint='curve')
    for rd in feats['roads']:
        pts = [((p[0] + SIZE_M / 2) * s, (p[1] + SIZE_M / 2) * s) for p in rd['points']]
        for i in range(0, len(pts) - 1, 2):
            d.line([pts[i], pts[i + 1]], fill=(92, 60, 36), width=3)
    rp = [((p[0] + SIZE_M / 2) * s, (p[1] + SIZE_M / 2) * s) for p in feats['rail']['points']]
    d.line(rp, fill=(40, 30, 24), width=4)
    for i in range(0, len(rp) - 1, 3):
        x0, y0 = rp[i]; x1, y1 = rp[i + 1]
        dx, dy = y1 - y0, -(x1 - x0); n = max(np.hypot(dx, dy), 1e-3) / 6.0
        d.line([(x0 - dx / n, y0 - dy / n), (x0 + dx / n, y0 + dy / n)], fill=(40, 30, 24), width=2)
    big = font('Rye-Regular.ttf', 34); small = font('IMFeENrm28P.ttf', 26); tiny = font('IMFeENit28P.ttf', 22)
    region = font('IMFeENsc28P.ttf', 46)
    for t in feats['towns']:
        x, y = (t['x'] + SIZE_M / 2) * s, (t['z'] + SIZE_M / 2) * s
        d.rectangle([x - 9, y - 9, x + 9, y + 9], outline=(40, 26, 18), width=3, fill=(120, 40, 30))
        d.text((x + 16, y - 20), t['name'], fill=(40, 26, 18), font=big)
    for p in feats['pois']:
        x, y = (p['x'] + SIZE_M / 2) * s, (p['z'] + SIZE_M / 2) * s
        d.ellipse([x - 5, y - 5, x + 5, y + 5], outline=(40, 26, 18), width=2)
        d.text((x + 10, y - 12), p['name'], fill=(52, 36, 26), font=small)
    for name, u, v in (("KESTREL RANGE", 0.12, 0.10), ("THORNWOOD", 0.68, 0.10), ("CORRIGAN PLAINS", 0.48, 0.80),
                       ("OCOTILLO BREAKS", 0.06, 0.92), ("LAKE AGNES", 0.835, 0.74), ("SABLE RIVER", 0.56, 0.585)):
        d.text((u * size, v * size), name, fill=(70, 50, 36), font=region if name != "SABLE RIVER" else tiny)
    # compass rose
    cx, cy = size - 170, 170
    d.ellipse([cx - 90, cy - 90, cx + 90, cy + 90], outline=(60, 40, 28), width=3)
    d.polygon([(cx, cy - 110), (cx - 14, cy), (cx + 14, cy)], fill=(60, 40, 28))
    d.polygon([(cx, cy + 90), (cx - 10, cy), (cx + 10, cy)], outline=(60, 40, 28))
    d.text((cx - 10, cy - 150), "N", fill=(60, 40, 28), font=big)
    img = img.filter(ImageFilter.SMOOTH)
    img.save(path)


if __name__ == '__main__':
    main()
