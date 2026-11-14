#!/usr/bin/env python3
"""Prepare a video for review by a model that sees images, not video.
Usage: prep.py VIDEO OUTDIR [--step 0.25]
Writes to OUTDIR:
  info.txt         duration, resolution, fps
  shots.txt        detected shots (cuts), start-end seconds
  shot_NN.jpg      storyboard per shot: frames every --step seconds, in order, timestamped (read these in order)
  full/            full-resolution PNG every --step seconds (t_XX.XX.png) for zooming in
  pops.txt         within-shot single-frame pops and brightness jumps (things that last < 1/10 s)
  audio.txt        loudness timeline (dB per 0.1 s) and sudden loud events, so sound can be matched to what's on screen
"""
import sys, os, subprocess, json, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont

vid, out = sys.argv[1], sys.argv[2]
step = float(sys.argv[sys.argv.index('--step') + 1]) if '--step' in sys.argv else 0.25
os.makedirs(os.path.join(out, 'full'), exist_ok=True)
pr = json.loads(subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'stream=codec_type,width,height,r_frame_rate:format=duration',
                                '-of', 'json', vid], capture_output=True, text=True).stdout)
v = next(s for s in pr['streams'] if s['codec_type'] == 'video'); W, H = int(v['width']), int(v['height'])
num, den = map(int, v['r_frame_rate'].split('/')); fps = num / den; dur = float(pr['format']['duration'])
has_audio = any(s['codec_type'] == 'audio' for s in pr['streams'])
open(os.path.join(out, 'info.txt'), 'w').write(f'duration {dur:.2f}s  {W}x{H}  {fps:.2f} fps  audio {has_audio}\n')

# Every frame, small and grey, for cut / pop detection.
w, h = 160, 90
raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', vid, '-vf', f'scale={w}:{h}', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], capture_output=True).stdout
F = np.frombuffer(raw, np.uint8).reshape(-1, h, w, 3); n = len(F)
G = np.concatenate([F[i:i + 500].mean(axis=3, dtype=np.float32) for i in range(0, n, 500)]); del F, raw  # (chunked: long videos ran out of memory)
hist = [np.histogram(G[i], bins=32, range=(0, 255))[0] / (w * h) for i in range(n)]
hd = np.array([np.abs(hist[i] - hist[i - 1]).sum() for i in range(1, n)])
pd = np.array([np.abs(G[i] - G[i - 1]).mean() for i in range(1, n)])
cuts = [0] + [i + 1 for i in range(len(hd)) if hd[i] > 0.5 and pd[i] > 25] + [n]
cuts = [c for k, c in enumerate(cuts) if k == 0 or c - cuts[k - 1] > fps * 0.3 or c == n]
shots = [(cuts[k], cuts[k + 1]) for k in range(len(cuts) - 1)]
with open(os.path.join(out, 'shots.txt'), 'w') as f:
    for k, (a, b) in enumerate(shots): f.write(f'shot {k:02d}: {a / fps:6.2f}s - {b / fps:6.2f}s  ({(b - a) / fps:.2f}s)\n')

# Pops: frame i unlike both neighbours while the neighbours agree (inside a shot).
cutset = set(cuts)
with open(os.path.join(out, 'pops.txt'), 'w') as f:
    f.write('time  score  region(x0,y0,x1,y1 in full-res px)  kind\n')
    B = 10
    def grid(d): return d.reshape(h // B, B, w // B, B).mean(axis=(1, 3))
    for i in range(1, n - 1):
        if i in cutset or i + 1 in cutset: continue
        a, b, c = G[i - 1], G[i], G[i + 1]
        s = np.minimum(grid(np.abs(b - a)), grid(np.abs(b - c))) - grid(np.abs(c - a))
        if s.max() > 14:
            y, x = np.unravel_index(s.argmax(), s.shape); sx, sy = W / w, H / h
            f.write(f'{i / fps:6.2f}  {s.max():5.1f}  ({int(x * B * sx)},{int(y * B * sy)},{int((x + 1) * B * sx)},{int((y + 1) * B * sy)})  one-frame pop\n')
    L = G.mean(axis=(1, 2))
    for i in range(1, n):
        if i in cutset: continue
        if abs(L[i] - L[i - 1]) > 12: f.write(f'{i / fps:6.2f}  {L[i] - L[i - 1]:+5.1f}  (whole frame)  brightness jump\n')

# Flicker / strobe: a region whose brightness flips direction 3+ times within ~1 s (inside a shot).
with open(os.path.join(out, 'flicker.txt'), 'w') as f:
    f.write('start  end  region(full-res px)  flips  (a region alternating bright/dark: strobing, flashing, z-fighting; camera motion over striped textures also triggers it, so look before believing)\n')
    B = 10; gh, gw = h // B, w // B
    R = G.reshape(n, gh, B, gw, B).mean(axis=(2, 4))
    win = max(6, int(fps))
    for y in range(gh):
        for x in range(gw):
            d = np.diff(R[:, y, x]); big = np.abs(d) > 10
            i = 0
            while i < len(d) - win:
                seg = [k for k in range(i, i + win) if big[k] and not ({k, k + 1} & cutset)]
                sg = [np.sign(d[k]) for k in seg]
                flips = sum(1 for a, b in zip(sg, sg[1:]) if a != b)
                if flips >= 3:
                    sx, sy = W / w, H / h
                    f.write(f'{i / fps:6.2f}  {(i + win) / fps:6.2f}  ({int(x * B * sx)},{int(y * B * sy)},{int((x + 1) * B * sx)},{int((y + 1) * B * sy)})  {flips}\n')
                    i += win
                else: i += 1

# Audio loudness.
aud_ev = []
with open(os.path.join(out, 'audio.txt'), 'w') as f:
    if not has_audio: f.write('no audio track\n')
    else:
        pcm = np.frombuffer(subprocess.run(['ffmpeg', '-v', 'error', '-i', vid, '-ac', '1', '-ar', '8000', '-f', 's16le', '-'],
                                           capture_output=True).stdout, np.int16).astype(np.float32) / 32768
        win = 800; m = len(pcm) // win
        db = [20 * math.log10(max(1e-5, float(np.sqrt((pcm[k * win:(k + 1) * win] ** 2).mean())))) for k in range(m)]
        f.write('sudden loud events (rise > 10 dB within 0.2 s):\n')
        for k in range(2, m):
            if db[k] - min(db[k - 2], db[k - 1]) > 10 and db[k] > -35: aud_ev.append(k / 10); f.write(f'  {k / 10:6.1f}s  {db[k]:.0f} dB\n')
        f.write('\nloudness every 0.1 s (dB):\n')
        for k in range(0, m, 10): f.write(f'  {k / 10:5.1f}s ' + ' '.join(f'{x:4.0f}' for x in db[k:k + 10]) + '\n')

# Full-resolution frames and per-shot storyboards.
subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', vid, '-vf', f'fps={1 / step}', os.path.join(out, 'full', 'f_%05d.png')], check=True)
files = sorted(os.listdir(os.path.join(out, 'full')))
times = []
for k, fn in enumerate(files):
    t = k * step + step / 2 if False else k * step
    new = os.path.join(out, 'full', f't_{t:06.2f}.png'); os.rename(os.path.join(out, 'full', fn), new); times.append((t, new))
try: font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 22)
except Exception: font = ImageFont.load_default()
TW, TH, COLS = 640, 360, 3
for k, (a, b) in enumerate(shots):
    fr = [(t, p) for t, p in times if a / fps <= t < b / fps]
    if not fr: continue
    for part in range(0, len(fr), 12):
        chunk = fr[part:part + 12]; rows = math.ceil(len(chunk) / COLS)
        sheet = Image.new('RGB', (TW * COLS, TH * rows), (0, 0, 0))
        for j, (t, p) in enumerate(chunk):
            im = Image.open(p).convert('RGB').resize((TW, TH)); d = ImageDraw.Draw(im)
            d.rectangle([0, 0, 120, 28], fill=(0, 0, 0)); d.text((6, 3), f'{t:.2f}s', fill=(255, 255, 0), font=font)
            sheet.paste(im, ((j % COLS) * TW, (j // COLS) * TH))
        sheet.save(os.path.join(out, f'shot_{k:02d}' + (f'_{part // 12}' if len(fr) > 12 else '') + '.jpg'), quality=88)
# Event strips: every frame (full frame rate) around each sudden visual or audio event, to judge timing, strobing,
# what happens first (cause or effect), and how long effects take to form or clear.
inner = [i for i in range(2, n) if not ({i, i - 1} & cutset)]
thr = np.percentile([pd[i - 1] for i in inner], 97) if inner else 99
rank = sorted(inner, key=lambda i: -pd[i - 1])
ev = list(aud_ev)
for i in rank:
    t = round(i / fps, 1)
    if all(abs(t - e) > 1.5 for e in ev): ev.append(t)
    if len(ev) >= 12: break
ev = sorted(ev)
evs = []
for t in ev:
    if not evs or t - evs[-1] > 1.5: evs.append(t)
for t in evs:
    a = max(0, t - 0.5); fr = []
    tmpd = os.path.join(out, 'tmp_ev'); os.makedirs(tmpd, exist_ok=True)
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', f'{a:.2f}', '-t', '2.0', '-i', vid, '-vf', 'scale=480:270', os.path.join(tmpd, 'e_%03d.png')])
    imgs = sorted(os.listdir(tmpd))[:60]
    if imgs:
        cols = 6; rows = math.ceil(len(imgs) / cols); sheet = Image.new('RGB', (480 * cols, 270 * rows))
        for j, fn in enumerate(imgs):
            im = Image.open(os.path.join(tmpd, fn)).convert('RGB'); d = ImageDraw.Draw(im)
            d.rectangle([0, 0, 96, 24], fill=(0, 0, 0)); d.text((4, 2), f'{a + j / fps:.2f}s', fill=(255, 255, 0), font=font)
            sheet.paste(im, ((j % cols) * 480, (j // cols) * 270))
        sheet.save(os.path.join(out, f'event_{t:05.1f}s.jpg'), quality=85)
    for fn in os.listdir(tmpd): os.remove(os.path.join(tmpd, fn))
print(f'{len(shots)} shots, {len(times)} frames at {step}s, outputs in {out}')
