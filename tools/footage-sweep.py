#!/usr/bin/env python3
"""P467: look through all the play the headset recorded for bugs -> docs/playtests/<date>/footage-sweep.md

Remington, Oct 25 20:31-20:34: "the headset records video all the time... AI could review all the footage, and then if
it sees any bugs itself that I hadn't reported, it could grab them"; "we can have it look for things that I said or that
I didn't say".

Playtest builds keep every minute of play as 5-minute rec-<stamp>.mp4 clips (quest/src/android/QuestVoiceNotes.swift,
Record All Play in Options > Interface) with rec-<stamp>.jsonl beside each (the game state every 10 s);
tools/quest-bugnotes.py pulls them to ~/Documents/Blocksmith/QuestVoiceNotes/footage. This takes one frame every 2 s
(ffmpeg, 512 px wide), hands them a minute at a time to a vision model through OpenRouter (key in
~/.config/openrouter/api-key, the same as the notes), together with what he said in that minute (his transcribed
notes), and writes what it saw: when, what, how bad, whether he mentioned it, where he was (from the sidecar) with a
repro line and a small frame. About 1,800 frames an hour of play, roughly 15-30 cents with the default model.

  tools/footage-sweep.py               sweep the clips not swept yet
  tools/footage-sweep.py --all         sweep every clip again
  tools/footage-sweep.py --clip NAME   one clip (rec-YYYYMMDD-HHMMSS)
  tools/footage-sweep.py --model M     another OpenRouter vision model (default google/gemini-2.5-flash)

Clips and the sweep cache stay on this Mac; the list and its frames go to docs/playtests/<date>/.
"""
import argparse, base64, datetime, json, re, shutil, subprocess, sys, tempfile, urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LOCAL = Path.home() / "Documents/Blocksmith/QuestVoiceNotes"
FOOTAGE = LOCAL / "footage"
KEY = Path.home() / ".config/openrouter/api-key"
STEP = 2.0              # seconds between frames
BATCH = 30              # frames per request (a minute)
BUFFER = 10.0           # each clip opens with the 10 s buffered before it started

PROMPT = """You are reviewing gameplay footage from a playtest of Sunderfall, a VR open-world game on Meta Quest 3: a
block-built world with smooth terrain, frontier towns, military bases, soldiers, vehicles, ships and an underground
Ash Vault. These are frames from the player's left eye at a quarter of the headset's resolution, one every 2 seconds
(frame numbers below), HUD and menus included. Low resolution and compression are expected: ignore them.

List every visible BUG: missing or unloaded terrain or blocks (holes to the sky or void), flickering or z-fighting,
things floating in the air or sunk into the ground, objects or people clipping through walls, frozen or T-posed
characters, characters stuck walking into walls, magenta or wrong textures, stretched or exploded geometry, broken
lighting (black faces, glowing where it should not), vehicles or ships in impossible poses, UI text overlapping or cut
off, black or frozen frames, the camera inside geometry. Also note gameplay that looks wrong (an enemy shooting
through a wall, an explosion leaving no mark, a door drawn shut while open). Do not report art style or things that
merely look plain.

What the player said aloud during this minute (his own bug notes; may be empty):
{said}

Answer with JSON only: {{"findings": [{{"frame": <frame number>, "what": "<one plain sentence>", "severity": "low|medium|high",
"mentioned": <true if the player's words above already cover it>}}]}}. An empty list when nothing is wrong."""


def frames(clip: Path, out: Path) -> list:
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(clip), "-vf", f"fps={1 / STEP},scale=512:-2", "-q:v", "7",
                    str(out / "f%05d.jpg")], capture_output=True)
    return sorted(out.glob("f*.jpg"))


def ask(model: str, key: str, imgs: list, first: int, said: str):
    content = [{"type": "text", "text": PROMPT.format(said=said or "(nothing)")}]
    for i, p in enumerate(imgs):
        content.append({"type": "text", "text": f"frame {first + i}"})
        content.append({"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + base64.b64encode(p.read_bytes()).decode()}})
    body = json.dumps({"model": model, "messages": [{"role": "user", "content": content}],
                       "response_format": {"type": "json_object"}, "temperature": 0.1}).encode()
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=body, method="POST",
                                 headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        o = json.load(r)
    text = o["choices"][0]["message"]["content"] or "{}"
    m = re.search(r"\{.*\}", text, re.S)
    found = json.loads(m.group(0)).get("findings", []) if m else []
    return found, o.get("usage", {})


def states(sidecar: Path) -> list:
    out = []
    if sidecar.exists():
        for line in sidecar.read_text(errors="replace").splitlines():
            try:
                o = json.loads(line)
                out.append((datetime.datetime.fromisoformat(o["time"][:19]), dict(o.get("context", {}))))
            except (ValueError, KeyError):
                continue
    return out


def repro(ctx: dict) -> str:
    seed = re.search(r"seed (\d+)", ctx.get("world", ""))
    pos = ctx.get("position", "").split()
    yaw = re.search(r"yaw (-?\d+)", ctx.get("facing", ""))
    if not seed or len(pos) < 3:
        return ""
    return f"`./snap.sh note --seed {seed.group(1)} --x {pos[0]} --z {pos[2]}{' --yaw ' + yaw.group(1) if yaw else ''}`"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--clip")
    ap.add_argument("--model", default="google/gemini-2.5-flash")
    ap.add_argument("--out", default=str(REPO / "docs/playtests"))
    args = ap.parse_args()
    if not shutil.which("ffmpeg"):
        sys.exit("needs ffmpeg (brew install ffmpeg)")
    if not KEY.exists():
        sys.exit(f"no OpenRouter key at {KEY}")
    key = KEY.read_text().strip()
    cache_path = FOOTAGE / "sweep.json"
    cache = json.loads(cache_path.read_text()) if cache_path.exists() else {}
    notes = json.loads((LOCAL / "transcripts.json").read_text()) if (LOCAL / "transcripts.json").exists() else {}
    said_at = []
    for stamp, text in notes.items():
        try:
            said_at.append((datetime.datetime.strptime(stamp[:15], "%Y%m%d-%H%M%S"), text))
        except ValueError:
            pass
    clips = sorted(FOOTAGE.glob("rec-*.mp4"))
    if args.clip:
        clips = [c for c in clips if c.stem == args.clip]
    tokens = 0
    for clip in clips:
        if clip.stem in cache and not (args.all or args.clip):
            continue
        t0 = datetime.datetime.strptime(clip.stem[4:19], "%Y%m%d-%H%M%S") - datetime.timedelta(seconds=BUFFER)
        found = []
        with tempfile.TemporaryDirectory() as tmp:
            imgs = frames(clip, Path(tmp))
            for b in range(0, len(imgs), BATCH):
                lo = t0 + datetime.timedelta(seconds=b * STEP)
                hi = lo + datetime.timedelta(seconds=BATCH * STEP)
                said = "\n".join(f"- {t:%H:%M:%S} {x}" for t, x in sorted(said_at) if lo - datetime.timedelta(seconds=20) <= t <= hi)
                try:
                    f, use = ask(args.model, key, imgs[b:b + BATCH], b, said)
                except Exception as e:                       # keep going; this clip is retried next run
                    print(f"{clip.name}: request failed: {e}")
                    found = None
                    break
                tokens += int(use.get("prompt_tokens", 0)) + int(use.get("completion_tokens", 0))
                for x in f:
                    n = int(x.get("frame", 0))
                    if 0 <= n < len(imgs):
                        x["time"] = (t0 + datetime.timedelta(seconds=n * STEP)).isoformat()
                        x["jpg"] = imgs[n].read_bytes().hex()     # (kept until the list is written)
                        found.append(x)
        if found is None:
            continue
        cache[clip.stem] = found
        cache_path.write_text(json.dumps(cache))
        print(f"{clip.name}: {len(found)} findings")

    # The lists, one per day, from everything swept so far.
    days = {}
    for stem, found in sorted(cache.items()):
        st = states(FOOTAGE / f"{stem}.jsonl")
        for x in found:
            t = datetime.datetime.fromisoformat(x["time"])
            ctx = min(st, key=lambda s: abs((s[0] - t).total_seconds()))[1] if st else {}
            days.setdefault(t.date().isoformat(), []).append((t, x, ctx, stem))
    for day, rows in days.items():
        folder = Path(args.out) / day
        (folder / "footage-shots").mkdir(parents=True, exist_ok=True)
        out = [f"# Footage sweep {day} (Quest)\n",
               f"Bugs a vision model saw in the recorded play that day (`tools/footage-sweep.py`, {len(rows)} findings; "
               "unconfirmed: check each against its frame). \"Mentioned\" means one of his voice notes already covers it.\n"]
        for t, x, ctx, stem in sorted(rows, key=lambda r: r[0]):
            name = f"{stem}-{t:%H%M%S}.jpg"
            jpg = folder / "footage-shots" / name
            if not jpg.exists() and x.get("jpg"):
                jpg.write_bytes(bytes.fromhex(x["jpg"]))
            out.append(f"## {t:%H:%M:%S} - {x.get('what', '')[:90]}\n")
            out.append(f"- **Severity:** {x.get('severity', '?')}")
            out.append(f"- **Mentioned in a note:** {'yes' if x.get('mentioned') else 'no'}")
            for k in ["biome", "position", "facing", "mount", "held"]:
                if k in ctx:
                    out.append(f"- **{k.capitalize()}:** {ctx[k]}")
            r = repro(ctx)
            if r:
                out.append(f"- **Repro (Mac):** {r}")
            out.append(f"- **Clip (this Mac):** {FOOTAGE / (stem + '.mp4')} at {(t - datetime.datetime.strptime(stem[4:19], '%Y%m%d-%H%M%S')).total_seconds() + BUFFER:.0f} s")
            out.append(f"\n![{t:%H:%M:%S}](footage-shots/{name})\n")
        (folder / "footage-sweep.md").write_text("\n".join(out) + "\n")
        print(f"wrote {folder / 'footage-sweep.md'}")
    if tokens:
        print(f"{tokens} tokens used")


if __name__ == "__main__":
    main()
