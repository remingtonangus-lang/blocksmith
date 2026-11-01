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

# (shot, seconds used, caption or None, [(seconds into the used part, sound file, gain)], options)
# options: ss = start this far into the clip, speed = play faster (1.5 = 50 % faster), xf = the cross-fade into this
# shot (0 = a hard cut). Sections fade into each other; shots inside a section cut hard.
CUT = [
    ("frigate_strike", 2.4, None, [(0.3, "explodeLarge.wav", 1.0), (0.35, "explodeLarge_1.wav", 1.0)], {"ss": 0.7}),
    ("town_crane", 3.5, "A frontier with towns full of people", [], {"xf": 0.6}),
    ("town_street", 2.8, None, [], {"xf": 0, "ss": 1.0}),
    ("capital", 3.0, None, [], {"xf": 0, "ss": 0.5}),
    ("train", 3.5, "Ride the rails", [], {"xf": 0.4}),
    ("build_cabin", 4.5, "Build anything, block by block", [], {"xf": 0.4, "speed": 1.6}),
    ("cave", 3.0, "Explore the caves below", [], {"xf": 0.4}),
    ("station_air", 3.2, "Slip into a secret base in the snow", [], {"xf": 0.4, "ss": 2.0}),
    ("station_gate", 2.4, None, [], {"xf": 0, "ss": 1.3}),
    ("station_corridor", 1.5, None, [], {"xf": 0}),
    ("ash_vault", 3.2, "Fight through the last war", [], {"xf": 0.4, "ss": 1.6}),
    ("war_advance", 2.6, None, [(0.9, "explodeLarge.wav", 1.0), (2.2, "explodeLarge_1.wav", 0.9)], {"xf": 0, "ss": 0.1}),
    ("tank_breakup", 3.0, None, [(0.6, "explodeLarge_2.wav", 1.0)], {"xf": 0, "ss": 1.0}),
    ("frigate_fire", 3.0, "Command a warship", [], {"xf": 0.4, "ss": 0.5}),
    ("frigate_strike", 3.6, "and bring its main gun to bear", [(1.0, "explodeLarge.wav", 1.0), (1.05, "explodeLarge_1.wav", 1.0)], {"xf": 0}),
    ("hell", 3.0, "Then go deeper", [], {"xf": 0.4, "speed": 1.3}),
    ("finale", 4.0, None, [], {"xf": 0.6}),
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
    for i, (name, secs, cap, _, o) in enumerate(shots):
        sp = o.get("speed", 1.0)
        inputs += ["-ss", f"{o.get('ss', 0):.3f}", "-t", f"{secs * sp + 0.1:.3f}", "-i", os.path.join(d, name + ".mp4")]
        f = f"[{i}:v]setpts=(PTS-STARTPTS)/{sp},fps={FPS},trim=duration={secs:.3f},setpts=PTS-STARTPTS,format=yuv420p"
        if captions and cap:
            f += (f",drawtext=fontfile={FONT}:text='{esc(cap)}':fontsize=54:fontcolor=white:borderw=3:bordercolor=black@0.6"
                  f":x=(w-text_w)/2:y=h-150:alpha='if(lt(t,0.3),0,if(lt(t,0.6),(t-0.3)/0.3,if(lt(t,{secs - 0.5:.2f}),1,max(0,({secs - 0.2:.2f}-t)/0.3))))'")
        parts.append(f + f"[v{i}]")
    # The end card: the last sunset frame, blurred and darkened, under the name.
    n = len(shots)
    bg = os.path.join(d, "_endcard.png")
    fin = os.path.join(d, "finale.mp4")
    run(["ffmpeg", "-loglevel", "error", "-y", "-sseof", "-0.2", "-i", fin, "-frames:v", "1",
         "-vf", "scale=1920:1080,boxblur=18:2,eq=brightness=-0.18:saturation=0.8", bg])
    inputs += ["-loop", "1", "-t", f"{TITLE}", "-framerate", str(FPS), "-i", bg]
    parts.append(f"[{n}:v]format=yuv420p,drawtext=fontfile={FONT}:text='S U N D E R F A L L':fontsize=128:fontcolor=white"
                 f":borderw=2:bordercolor=black@0.4:x=(w-text_w)/2:y=(h-text_h)/2-50:alpha='min(1,t/0.8)',"
                 f"drawbox=x=(iw-760)/2:y=ih/2+48:w=760:h=3:color=white@0.7:t=fill:enable='gte(t,0.6)',"
                 f"drawtext=fontfile={FONT2}:text='EARLY ACCESS ON META QUEST':fontsize=40:fontcolor=white@0.9"
                 f":x=(w-text_w)/2:y=(h/2)+80:alpha='max(0,min(1,(t-0.8)/0.6))'[v{n}]")
    # The chain: a fade where a section changes, a hard cut inside one.
    chain, last, off = [], "[v0]", 0.0
    starts = [0.0]
    for i in range(1, n + 1):
        xf = (shots[i][4].get("xf", 0.4) if i < n else 0.6) or 0.04
        off += shots[i - 1][1] - xf
        starts.append(off)
        lab = f"[x{i}]"
        chain.append(f"{last}[v{i}]xfade=transition=fade:duration={xf}:offset={off:.3f}{lab}")
        last = lab
    total = off + TITLE
    # Sound: the frontier theme, the battle theme from the snow base on, the blasts on top.
    ai = n + 1
    calm = os.path.join(MUSIC, "main_title.m4a")
    war = os.path.join(MUSIC, "ash_vault_battle.m4a")
    names = [s[0] for s in shots]
    switch = starts[names.index("station_air")] if "station_air" in names else total / 2
    inputs += ["-i", calm, "-i", war]
    a = [f"[{ai}:a]atrim=0:{switch + 2:.3f},asetpts=PTS-STARTPTS,afade=t=in:d=0.8,afade=t=out:st={switch:.3f}:d=1.5,volume=0.75[m0]",
         f"[{ai + 1}:a]atrim=0:{total - switch + 1:.3f},asetpts=PTS-STARTPTS,afade=t=in:d=1.0,afade=t=out:st={total - switch - 3:.3f}:d=3,"
         f"adelay={int(switch * 1000)}|{int(switch * 1000)},volume=0.75[m1]"]
    mix = ["[m0]", "[m1]"]
    k = ai + 2
    for (name, secs, cap, sfx, o), st in zip(shots, starts):
        for (ts, f, gain) in sfx:
            inputs += ["-i", os.path.join(SOUNDS, f)]
            ms = int((st + ts) * 1000)
            a.append(f"[{k}:a]volume={gain * 0.7:.2f},adelay={ms}|{ms}[s{k}]")
            mix.append(f"[s{k}]")
            k += 1
    # Peaks held to -3 dBFS before the AAC encoder (whose rounding adds a little) so nothing reaches 0 dBFS.
    a.append("".join(mix) + f"amix=inputs={len(mix)}:normalize=0,atrim=0:{total:.3f},alimiter=limit=0.70:level=false,"
             f"aresample=48000[aout]")
    graph = ";".join(parts + chain + a)
    run(["ffmpeg", "-loglevel", "error", "-y"] + inputs + ["-filter_complex", graph, "-map", last, "-map", "[aout]",
         "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p", "-r", str(FPS),
         "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-movflags", "+faststart", out])
    print(f"cut: {out}: {total:.1f} s, {n} shots")


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "clips":
        clips(sys.argv[2])
    elif len(sys.argv) >= 4 and sys.argv[1] == "cut":
        cut(sys.argv[2], sys.argv[3], "--captions" in sys.argv)
    else:
        print(__doc__)
        sys.exit(1)
