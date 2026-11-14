#!/usr/bin/env python3
"""Steady a headset clip: keep the intended look, drop the head jitter and the roll wobble.

  stab.py IN.mp4 OUT.mp4 [--sigma 0.6] [--roll-sigma 1.5] [--zoom 1.10] [--crf 18]

Tracks a similarity transform between frames (as motion.py), builds the camera path (x, y, roll), smooths it with a
Gaussian (sigma seconds; roll smoothed harder), and warps each frame by (smoothed - real), clamped to what the zoom
margin hides. Writes H.264 through ffmpeg (video only).
"""
import sys, argparse, subprocess, numpy as np, cv2

def gauss(x, s):
    if s <= 0: return x.copy()
    r = int(3 * s); k = np.exp(-0.5 * (np.arange(-r, r + 1) / s) ** 2); k /= k.sum()
    p = np.pad(x, r, mode="edge"); return np.convolve(p, k, mode="valid")

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("inp"); ap.add_argument("out")
    ap.add_argument("--sigma", type=float, default=0.6); ap.add_argument("--roll-sigma", type=float, default=1.5)
    ap.add_argument("--zoom", type=float, default=1.10); ap.add_argument("--crf", default="18")
    a = ap.parse_args()
    cap = cv2.VideoCapture(a.inp); fps = cap.get(cv2.CAP_PROP_FPS) or 30
    frames, prev, T = [], None, []
    while True:
        ok, f = cap.read()
        if not ok: break
        frames.append(f)
        h, w = f.shape[:2]; W = 480; s = w / W
        g = cv2.cvtColor(cv2.resize(f, (W, int(h / s)), interpolation=cv2.INTER_AREA), cv2.COLOR_BGR2GRAY)
        dx = dy = da = 0.0
        if prev is not None:
            p0 = cv2.goodFeaturesToTrack(prev, 300, 0.01, 8)
            if p0 is not None and len(p0) >= 8:
                p1, st, _ = cv2.calcOpticalFlowPyrLK(prev, g, p0, None, winSize=(21, 21), maxLevel=3)
                A, B = p0[st == 1], p1[st == 1]
                if len(A) >= 8:
                    M, _ = cv2.estimateAffinePartial2D(A, B, method=cv2.RANSAC, ransacReprojThreshold=2.0)
                    if M is not None:
                        dx, dy, da = M[0, 2] * s, M[1, 2] * s, np.arctan2(M[1, 0], M[0, 0])
        T.append((dx, dy, da)); prev = g
    T = np.array(T); path = np.cumsum(T, axis=0)
    sm = np.c_[gauss(path[:, 0], a.sigma * fps), gauss(path[:, 1], a.sigma * fps), gauss(path[:, 2], a.roll_sigma * fps)]
    corr = sm - path
    h, w = frames[0].shape[:2]
    mx, my = w * (a.zoom - 1) / 2 * 0.9, h * (a.zoom - 1) / 2 * 0.9
    corr[:, 0] = np.clip(corr[:, 0], -mx, mx); corr[:, 1] = np.clip(corr[:, 1], -my, my); corr[:, 2] = np.clip(corr[:, 2], -0.06, 0.06)
    enc = subprocess.Popen(["ffmpeg", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", f"{w}x{h}", "-r", str(fps),
                            "-i", "-", "-c:v", "libx264", "-preset", "fast", "-crf", a.crf, "-pix_fmt", "yuv420p", a.out], stdin=subprocess.PIPE)
    c = (w / 2, h / 2)
    for f, (cx, cy, ca) in zip(frames, corr):
        R = cv2.getRotationMatrix2D(c, np.degrees(-ca), a.zoom)   # cv2 angle is CCW in image coords; path angle is +CW
        R[0, 2] += cx; R[1, 2] += cy
        enc.stdin.write(cv2.warpAffine(f, R, (w, h), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REFLECT).tobytes())
    enc.stdin.close(); enc.wait()
    print(f"{a.out}: {len(frames)} frames, max shift {np.abs(corr[:, :2]).max():.0f} px, max roll {np.degrees(np.abs(corr[:, 2]).max()):.1f} deg")

if __name__ == "__main__":
    main()
