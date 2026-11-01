#!/usr/bin/env python3
"""Store trailer from questcheck --cine footage (docs/store/trailer.md).

  tools/cine.py clips DIR            encode each DIR/<shot>/f*.png sequence to DIR/<shot>.mp4 (1920x1080, 30 fps)
  tools/cine.py cut DIR OUT.mp4 [--captions]
                                     the trailer: the clips in CUT order with short crossfades, the game's own music
                                     (Resources/Music/sunderfall) and its blast sounds, a title card at the end

Needs ffmpeg. Nothing it makes goes into the repo (videos are binaries): deliver them in the project files.
"""
import json, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MUSIC = os.path.join(ROOT, "Resources/Music/sunderfall")
SOUNDS = os.path.join(ROOT, "Resources/Sounds/real")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
FONT2 = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FPS = 30
XF = 0.5          # crossfade seconds

# (shot, seconds used from its start, caption or None, [(seconds into the shot, sound file, gain)])
CUT = [
    ("town_crane", 5.0, "A frontier with towns full of people", []),
    ("town_street", 5.0, None, []),
    ("capital", 4.5, None, []),
    ("train", 5.0, "Ride the rails", []),
    ("build_cabin", 7.0, "Build anything, block by block", []),
    ("cave", 4.5, "Explore the caves below", []),
    ("station_air", 5.5, "Slip into a secret base in the snow", []),
    ("station_gate", 4.0, None, []),
    ("station_corridor", 2.0, None, []),
    ("ash_vault", 5.5, "Fight through the last war", [(1.5, "explodeLarge.wav", 0.9), (3.6, "explodeLarge_1.wav", 0.9)]),
    ("war_advance", 2.4, None, [(1.0, "explodeLarge.wav", 1.0)]),
    ("tank_breakup", 4.0, None, [(1.6, "explodeLarge_2.wav", 1.0)]),
    ("frigate_fire", 4.5, "Take the helm of a warship", []),
    ("frigate_strike", 5.0, "and bring its main gun to bear", [(1.0, "explodeLarge.wav", 1.0), (1.05, "explodeLarge_1.wav", 1.0)]),
    ("hell", 4.5, "Then go deeper", []),
    ("finale", 6.5, None, []),
]
TITLE = 4.0       # the closing title card


def run(cmd):
    print("+", " ".join(cmd[:6]), "...", flush=True)
    subprocess.run(cmd, check=True)


def clips(d):
    for name in sorted(os.listdir(d)):
        p = os.path.join(d, name)
        if not os.path.isdir(p) or not os.path.exists(os.path.join(p, "f00000.png")):
            continue
        run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(FPS), "-i", os.path.join(p, "f%05d.png"),
             "-vf", "scale=1920:1080:flags=lanczos", "-c:v", "libx264", "-preset", "slow", "-crf", "14",
             "-pix_fmt", "yuv420p", os.path.join(d, name + ".mp4")])


def esc(t):
    return t.replace("\\", "\\\\").replace(":", "\\:").replace("'", "’")


def cut(d, out, captions):
    shots = [c for c in CUT if os.path.exists(os.path.join(d, c[0] + ".mp4"))]
    missing = [c[0] for c in CUT if c not in shots]
    if missing:
        print("cut: missing clips:", ", ".join(missing))
    inputs, parts, starts = [], [], []
    t = 0.0
    for i, (name, secs, cap, _) in enumerate(shots):
        inputs += ["-t", f"{secs:.3f}", "-i", os.path.join(d, name + ".mp4")]
        f = f"[{i}:v]setpts=PTS-STARTPTS,fps={FPS},format=yuv420p"
        if captions and cap:
            f += (f",drawtext=fontfile={FONT}:text='{esc(cap)}':fontsize=54:fontcolor=white:borderw=3:bordercolor=black@0.6"
                  f":x=(w-text_w)/2:y=h-150:alpha='if(lt(t,0.5),0,if(lt(t,1.0),(t-0.5)/0.5,if(lt(t,{secs - 1.0:.2f}),1,max(0,({secs - 0.5:.2f}-t)/0.5))))'")
        parts.append(f + f"[v{i}]")
        starts.append(t)
        t += secs - XF
    total = t + XF
    # The title card: black, the name fading in.
    n = len(shots)
    inputs += ["-f", "lavfi", "-t", f"{TITLE}", "-i", f"color=c=black:s=1920x1080:r={FPS}"]
    parts.append(f"[{n}:v]format=yuv420p,drawtext=fontfile={FONT}:text='SUNDERFALL':fontsize=150:fontcolor=white"
                 f":x=(w-text_w)/2:y=(h-text_h)/2-40:alpha='min(1,t/1.0)',"
                 f"drawtext=fontfile={FONT2}:text='Early Access on Meta Quest':fontsize=44:fontcolor=white@0.85"
                 f":x=(w-text_w)/2:y=(h/2)+90:alpha='max(0,min(1,(t-0.8)/0.8))'[v{n}]")
    # Crossfade chain.
    chain, last, off = [], "[v0]", 0.0
    for i in range(1, n + 1):
        off += (shots[i - 1][1] if i - 1 < n else 0) - XF
        lab = f"[x{i}]"
        chain.append(f"{last}[v{i}]xfade=transition=fade:duration={XF}:offset={off:.3f}{lab}")
        last = lab
    total = off + TITLE
    # Sound: the music bed (frontier first, the battle theme from the base on), then each shot's blasts.
    ai = n + 1
    calm = os.path.join(MUSIC, "main_title.m4a")
    war = os.path.join(MUSIC, "ash_vault_battle.m4a")
    switch = starts[[s[0] for s in shots].index("station_air")] if any(s[0] == "station_air" for s in shots) else total / 2
    inputs += ["-i", calm, "-i", war]
    a = [f"[{ai}:a]atrim=0:{switch + 2:.3f},asetpts=PTS-STARTPTS,afade=t=in:d=1.5,afade=t=out:st={switch:.3f}:d=2,volume=0.9[m0]",
         f"[{ai + 1}:a]atrim=0:{total - switch + 1:.3f},asetpts=PTS-STARTPTS,afade=t=in:d=1.5,afade=t=out:st={total - switch - 3:.3f}:d=3,"
         f"adelay={int(switch * 1000)}|{int(switch * 1000)},volume=0.9[m1]"]
    mix = ["[m0]", "[m1]"]
    k = ai + 2
    for (name, secs, cap, sfx), st in zip(shots, starts):
        for (ts, f, gain) in sfx:
            inputs += ["-i", os.path.join(SOUNDS, f)]
            ms = int((st + ts) * 1000)
            a.append(f"[{k}:a]volume={gain},adelay={ms}|{ms}[s{k}]")
            mix.append(f"[s{k}]")
            k += 1
    a.append("".join(mix) + f"amix=inputs={len(mix)}:normalize=0,atrim=0:{total:.3f},alimiter=limit=0.9[aout]")
    graph = ";".join(parts + chain + a)
    run(["ffmpeg", "-loglevel", "error", "-y"] + inputs + ["-filter_complex", graph, "-map", last, "-map", "[aout]",
         "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p", "-r", str(FPS),
         "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", out])
    print(f"cut: {out}: {total:.1f} s, {n} shots")


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "clips":
        clips(sys.argv[2])
    elif len(sys.argv) >= 4 and sys.argv[1] == "cut":
        cut(sys.argv[2], sys.argv[3], "--captions" in sys.argv)
    else:
        print(__doc__)
        sys.exit(1)
