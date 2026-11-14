#!/usr/bin/env python3
"""Camera motion of a video, as numbers (for picking calm trailer windows from headset footage).

  motion.py CLIP.mp4 [--fov 100] [--win SECS]   per-second table + calmest windows
  motion.py --csv OUT.csv CLIP.mp4              also writes the per-frame track

Per frame (OpenCV, frames scaled to 480 px wide): sparse corners tracked with Lucas-Kanade, a similarity transform
(estimateAffinePartial2D, RANSAC) between frames -> pan (x), tilt (y), roll, zoom. Pixels -> degrees with the
horizontal field of view of the clip (--fov, Quest 3 eye crop ~100). Then:
  turn  = smoothed angular speed, deg/s (0.5 s window): how fast the view swings
  roll  = |roll speed| deg/s, smoothed
  shake = RMS of (raw - smoothed) angular speed, deg/s: the jitter on top of the intended move
  jerk  = how fast the turn speed itself changes, deg/s^2 (sudden starts/stops/whips)
Rough comfort read for a flat trailer: turn < 30, shake < 8, roll < 10, jerk < 150 calm; double that busy; more = jarring.
"""
import sys, argparse, numpy as np, cv2

def track(path, fov):
    cap = cv2.VideoCapture(path)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30
    prev, rows, ts = None, [], []
    while True:
        ok, f = cap.read()
        if not ok: break
        ts.append(cap.get(cv2.CAP_PROP_POS_MSEC) / 1000.0)
        h, w = f.shape[:2]; W = 480; H = int(h * W / w)
        g = cv2.cvtColor(cv2.resize(f, (W, H), interpolation=cv2.INTER_AREA), cv2.COLOR_BGR2GRAY)
        if prev is None:
            prev = g; rows.append((0, 0, 0, 1, 0)); continue
        p0 = cv2.goodFeaturesToTrack(prev, 300, 0.01, 8)
        dx = dy = rot = 0.0; sc = 1.0; n = 0
        if p0 is not None and len(p0) >= 8:
            p1, st, _ = cv2.calcOpticalFlowPyrLK(prev, g, p0, None, winSize=(21, 21), maxLevel=3)
            a, b = p0[st == 1], p1[st == 1]
            if len(a) >= 8:
                M, inl = cv2.estimateAffinePartial2D(a, b, method=cv2.RANSAC, ransacReprojThreshold=2.0)
                if M is not None:
                    dx, dy = M[0, 2], M[1, 2]; sc = float(np.hypot(M[0, 0], M[1, 0])); rot = float(np.degrees(np.arctan2(M[1, 0], M[0, 0])))
                    n = int(inl.sum()) if inl is not None else 0
        rows.append((dx, dy, rot, sc, n)); prev = g
    a = np.array(rows, dtype=float)
    dpp = fov / 480.0
    t = np.array(ts); dt = np.diff(t, prepend=t[0] - 1 / fps); dt[dt <= 0.004] = 1 / fps
    k = (1 / fps) / dt                                    # per-frame motion -> per nominal frame (VFR sources)
    return fps, a[:, 0] * dpp * k, a[:, 1] * dpp * k, a[:, 2] * k, a[:, 3], a[:, 4], dt

def smooth(x, k):
    k = max(1, int(k)); return np.convolve(x, np.ones(k) / k, mode="same")

def metrics(fps, px, py, rot):
    ang = np.hypot(px, py) * fps                 # deg/s per frame
    vx, vy = smooth(px, fps / 2) * fps, smooth(py, fps / 2) * fps
    turn = np.hypot(vx, vy)
    shake = np.hypot(px * fps - vx, py * fps - vy)
    roll = np.abs(smooth(rot, fps / 2) * fps)
    jerk = np.abs(np.gradient(smooth(turn, fps / 4))) * fps
    return turn, shake, roll, jerk

def score(turn, shake, roll, jerk, s, e):
    sl = slice(s, e)
    t, sh, r, j = np.percentile(turn[sl], 90), np.sqrt(np.mean(shake[sl] ** 2)), np.percentile(roll[sl], 90), np.percentile(jerk[sl], 90)
    return t / 30 + sh / 8 + r / 10 + j / 150, (t, sh, r, j)

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("clip"); ap.add_argument("--fov", type=float, default=100)
    ap.add_argument("--win", type=float, default=3.0); ap.add_argument("--csv"); ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    fps, px, py, rot, sc, n, dt = track(a.clip, a.fov)
    bad = n < 20                                   # a cut, a black/dark frame, a menu: no trustworthy motion
    bad[0] = False
    for arr in (px, py, rot):
        good = ~bad
        if good.sum() > 2: arr[bad] = np.interp(np.flatnonzero(bad), np.flatnonzero(good), arr[good])
    print(f"  untracked frames (cuts, dark): {int(bad.sum())}")
    dups = int(((np.abs(px) + np.abs(py)) < 1e-6).sum())
    turn, shake, roll, jerk = metrics(fps, px, py, rot)
    if a.csv:
        np.savetxt(a.csv, np.c_[np.arange(len(px)) / fps, px, py, rot, sc, n, turn, shake, roll, jerk], delimiter=",", fmt="%.3f",
                   header="t,pan_deg,tilt_deg,roll_deg,zoom,inliers,turn,shake,roll_speed,jerk", comments="")
    N = len(px); dur = N / fps
    tot, (t, sh, r, j) = score(turn, shake, roll, jerk, 0, N)
    print(f"{a.clip}: {dur:.1f} s  frames {N}  repeated {dups}  frame gap ms min/med/max {dt[1:].min()*1000:.0f}/{np.median(dt[1:])*1000:.0f}/{dt[1:].max()*1000:.0f}  whole: score {tot:.2f}  turn {t:.0f}  shake {sh:.1f}  roll {r:.0f}  jerk {j:.0f}")
    if not a.quiet:
        for s in range(int(dur)):
            i0, i1 = int(s * fps), min(N, int((s + 1) * fps))
            tt, (t, sh, r, j) = score(turn, shake, roll, jerk, i0, i1)
            print(f"  {s:3d}-{s+1:<3d} score {tt:5.2f}  turn {t:5.0f}  shake {sh:5.1f}  roll {r:4.0f}  jerk {j:5.0f}  {'#' * min(40, int(tt * 4))}")
    w = int(a.win * fps); best = []
    for i0 in range(0, max(1, N - w), max(1, int(fps / 4))):
        best.append((score(turn, shake, roll, jerk, i0, i0 + w)[0], i0 / fps))
    best.sort()
    print("  calmest", a.win, "s windows:", ", ".join(f"{t:.2f}s ({s:.2f})" for s, t in best[:3]))

if __name__ == "__main__":
    main()
