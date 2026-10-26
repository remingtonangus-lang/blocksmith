#!/usr/bin/env python3
"""Quest voice bug notes -> docs/playtests/<date>/voice-notes.md

Pulls the headset's recordings (playtest builds record speech while you play: quest/src/android/QuestVoiceNotes.swift),
transcribes new ones with ElevenLabs Scribe through OpenRouter, drops the ones with no words, and writes one dated list
per day: time, transcript, where you were and what you were doing, four frames from the note's video clip (P368: the
10 s before he spoke, then until 2 s after; the single screenshot when there is no clip).

  tools/quest-bugnotes.py                  pull over adb, transcribe, write the notes, delete the pulled files from
                                           the headset
  tools/quest-bugnotes.py --keep           ...but leave them on the headset
  tools/quest-bugnotes.py --source DIR     use a local folder of vn-* files instead of adb (tests)

Audio, video clips and the transcript cache stay on this Mac (~/Documents/Blocksmith/QuestVoiceNotes, not in the
public repo); the notes and small JPG frames go to docs/playtests/<date>/. Key: ~/.config/openrouter/api-key.
Frames need ffmpeg and ffprobe (brew install ffmpeg).
"""
import argparse, datetime, json, os, re, shutil, subprocess, sys, urllib.request, uuid
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
REMOTE = "/sdcard/Android/data/com.blocksmith.quest/files/voicenotes"
LOCAL = Path.home() / "Documents/Blocksmith/QuestVoiceNotes"
FOOTAGE = LOCAL / "footage"                     # P467: all play, 5-minute clips
KEY = Path.home() / ".config/openrouter/api-key"
MODEL = "elevenlabs/scribe-v2"


def adb():
    for p in [Path.home() / "ClaudeTools/quest/platform-tools/adb", shutil.which("adb")]:
        if p and Path(p).exists():
            return str(p)
    sys.exit("adb not found (expected ~/ClaudeTools/quest/platform-tools/adb)")


def pull(raw: Path):
    a = adb()
    devs = [l for l in subprocess.run([a, "devices"], capture_output=True, text=True).stdout.splitlines()[1:] if l.strip().endswith("device")]
    if not devs:
        sys.exit("No Quest on adb: plug it in (USB debugging on) and run again.")
    ls = subprocess.run([a, "shell", "ls", REMOTE], capture_output=True, text=True)
    names = [n.strip() for n in ls.stdout.split() if n.strip().startswith("vn-")]
    if not names:
        print("No recordings on the headset (is Bug Notes on? Options > Interface).")
    # A note still being recorded has no end line yet: its files are pulled again next time.
    def finished(n):
        return bool(sidecar(raw / (n.rsplit(".", 1)[0] + ".jsonl"))[2])
    new = [n for n in names if not (raw / n).exists() or not finished(n)]
    for n in new:
        subprocess.run([a, "pull", f"{REMOTE}/{n}", str(raw / n)], capture_output=True)
    print(f"pulled {len(new)} new files ({len(names)} on the headset)")
    pull_footage(a, ls.stdout.split())
    return names


def pull_footage(a, listing):
    """P467: the headset's rec-* clips (all play, 5 minutes each, with a state sidecar) go to FOOTAGE on this Mac and are
    deleted from the headset; the newest pair is still being written and waits for the next run. tools/footage-sweep.py
    looks through them."""
    recs = sorted(n.strip() for n in listing if n.strip().startswith("rec-"))
    stamps = sorted({n.rsplit(".", 1)[0] for n in recs})
    if len(stamps) < 2:
        return
    done = [n for n in recs if n.rsplit(".", 1)[0] != stamps[-1]]
    FOOTAGE.mkdir(parents=True, exist_ok=True)
    got = []
    for n in done:
        if subprocess.run([a, "pull", f"{REMOTE}/{n}", str(FOOTAGE / n)], capture_output=True).returncode == 0:
            got.append(n)
    for i in range(0, len(got), 50):
        subprocess.run([a, "shell", "rm", "-f"] + [f"{REMOTE}/{n}" for n in got[i:i + 50]])
    print(f"footage: pulled {len(got)} files to {FOOTAGE} (run tools/footage-sweep.py to look through them)")


def transcribe(audio: Path, key: str) -> str:
    boundary = uuid.uuid4().hex
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n{MODEL}\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{audio.name}\"\r\n"
            f"Content-Type: audio/aac\r\n\r\n").encode() + audio.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request("https://openrouter.ai/api/v1/audio/transcriptions", data=body, method="POST",
                                 headers={"Authorization": f"Bearer {key}",
                                          "Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r).get("text", "").strip()


def has_words(text: str) -> bool:
    # Scribe tags sounds like (music) or [explosion]; a note needs real words.
    bare = re.sub(r"\([^)]*\)|\[[^\]]*\]", " ", text)
    return len(re.findall(r"[A-Za-z0-9']{2,}", bare)) >= 2


def sidecar(path: Path):
    start, states, end = {}, [], {}
    if path.exists():
        for line in path.read_text(errors="replace").splitlines():
            try:
                o = json.loads(line)
            except ValueError:
                continue
            {"start": lambda: start.update(o), "end": lambda: end.update(o)}.get(o.get("event"), lambda: states.append(o))()
    return start, states, end


def repro(ctx: dict) -> str:
    seed = re.search(r"seed (\d+)", ctx.get("world", ""))
    pos = ctx.get("position", "").split()
    yaw = re.search(r"yaw (-?\d+)", ctx.get("facing", ""))
    if not seed or len(pos) < 3:
        return ""
    return f"`./snap.sh note --seed {seed.group(1)} --x {pos[0]} --z {pos[2]}{' --yaw ' + yaw.group(1) if yaw else ''}`"


def clip_frames(clip: Path, folder: Path, start: dict, end: dict, clock: str) -> list:
    """Four small JPGs from a note's clip: the start of the buffer, when he started talking, the middle of the note and
    its end. Returns the markdown image links (empty without ffmpeg or a readable clip)."""
    if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        return []
    try:
        dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(clip)],
                                   capture_output=True, text=True).stdout.strip() or 0)
    except ValueError:
        return []
    if dur <= 0:
        return []
    # The clip is the buffered seconds, the note, then 2 s of tail.
    note = float(end.get("length", 0) or 0)
    talk = max(0.0, min(dur, dur - note - 2.0)) if note > 0 else min(dur, 10.0)
    times = [("buffer", 0.0), ("talk", talk), ("middle", talk + (dur - talk) / 2), ("end", max(0.0, dur - 0.2))]
    (folder / "voice-shots").mkdir(parents=True, exist_ok=True)
    links = []
    for name, t in times:
        jpg = folder / "voice-shots" / f"{clip.stem}-{name}.jpg"
        if not jpg.exists():
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{t:.2f}", "-i", str(clip), "-frames:v", "1",
                            "-vf", "scale=480:-2", "-q:v", "6", str(jpg)], capture_output=True)
        if jpg.exists():
            links.append(f"![{clock} {name}](voice-shots/{jpg.name})")
    return links


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", help="local folder of vn-* files instead of adb")
    ap.add_argument("--keep", action="store_true", help="leave the pulled recordings on the headset")
    ap.add_argument("--clean", action="store_true", help=argparse.SUPPRESS)      # (the default now)
    ap.add_argument("--out", default=str(REPO / "docs/playtests"), help="where the dated folders go")
    ap.add_argument("--local", default=str(LOCAL), help="audio + transcript cache folder on this Mac")
    args = ap.parse_args()

    local = Path(args.local)
    raw = local / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    if args.source:
        for f in Path(args.source).glob("vn-*"):
            if not (raw / f.name).exists():
                shutil.copy2(f, raw / f.name)
        remote = []
    else:
        remote = pull(raw)

    cache_path = local / "transcripts.json"
    cache = json.loads(cache_path.read_text()) if cache_path.exists() else {}
    key = KEY.read_text().strip() if KEY.exists() else None
    if not key:
        print(f"No OpenRouter key at {KEY}: notes are listed without transcripts.")

    notes = {}
    for audio in sorted(raw.glob("vn-*.aac")):
        stamp = audio.stem[3:]
        start, states, end = sidecar(audio.with_suffix(".jsonl"))
        if not end and audio.stat().st_size == 0:
            continue
        # Transcribe once a note is finished (or clearly abandoned, e.g. the game crashed mid-note).
        age = datetime.datetime.now() - datetime.datetime.strptime(stamp[:15], "%Y%m%d-%H%M%S")
        if not end and age.total_seconds() < 300:
            continue
        if stamp not in cache and key:
            try:
                cache[stamp] = transcribe(audio, key)
                print(f"transcribed {audio.name}: {cache[stamp][:70]!r}")
            except Exception as e:  # keep going; it is retried next run
                print(f"transcription failed for {audio.name}: {e}")
            cache_path.write_text(json.dumps(cache, indent=1))
        text = cache.get(stamp)
        if text is not None and not has_words(text):
            continue                    # silence or only game sound
        notes[stamp] = (text, start, states, end, audio)

    written = {}
    for stamp, (text, start, states, end, audio) in sorted(notes.items()):
        day = f"{stamp[0:4]}-{stamp[4:6]}-{stamp[6:8]}"
        clock = f"{stamp[9:11]}:{stamp[11:13]}:{stamp[13:15]}"
        folder = Path(args.out) / day
        ctx = dict(start.get("context", {}))
        lines = [f"## {clock} - {(text or 'untranscribed note')[:70]}", "",
                 f"- **Transcript:** {text if text else '(not transcribed yet: run again with the OpenRouter key)'}",
                 "- **Status:** open"]
        for k in ["build", "world", "dimension", "biome", "position", "facing", "held", "mount", "looking at", "mode",
                  "time", "fps", "levels", "checklist"]:
            if k in ctx:
                lines.append(f"- **{k.capitalize()}:** {ctx[k]}")
        if end:
            lines.append(f"- **Length:** {end.get('length', 0):.1f} s (voice {end.get('voiced', 0):.1f} s)")
        ev = start.get("events", [])
        if ev:
            lines.append("- **Just before:** " + "; ".join(ev))
        moved = [s.get("context", {}).get("position") for s in states]
        later = [s for s in states if s.get("events")]
        if later:
            lines.append("- **While talking:** " + "; ".join(e for s in later for e in s["events"]))
        if moved:
            lines.append(f"- **Position at the end:** {moved[-1]}")
        r = f"`{ctx['repro']}`" if ctx.get("repro") else repro(ctx)
        if r:
            lines.append(f"- **Repro (Mac):** {r}")
        lines.append(f"- **Audio (this Mac):** {audio}")
        clip = raw / start["video"] if start.get("video") else None
        frames = clip_frames(clip, folder, start, end, clock) if clip and clip.exists() else []
        if frames:
            lines.append(f"- **Video (this Mac):** {clip}")
            lines += ["", " ".join(frames)]
        shot = raw / start.get("screenshot", "") if start.get("screenshot") and not frames else None
        if shot and shot.exists():
            (folder / "voice-shots").mkdir(parents=True, exist_ok=True)
            jpg = folder / "voice-shots" / (shot.stem + ".jpg")
            if not jpg.exists():
                subprocess.run(["sips", "-Z", "640", "-s", "format", "jpeg", "-s", "formatOptions", "70", str(shot),
                                "--out", str(jpg)], capture_output=True)
            if jpg.exists():
                lines += ["", f"![{clock}](voice-shots/{jpg.name})"]
        written.setdefault(day, []).append("\n".join(lines) + "\n")

    for day, entries in written.items():
        folder = Path(args.out) / day
        folder.mkdir(parents=True, exist_ok=True)
        md = folder / "voice-notes.md"
        head = (f"# Voice bug notes {day} (Quest)\n\nSpoken while playing; transcribed by {MODEL}. Written by "
                f"`tools/quest-bugnotes.py` (rewritten each run; edit Status lines in a copy). {len(entries)} notes.\n\n")
        md.write_text(head + "\n".join(entries))
        print(f"wrote {md} ({len(entries)} notes)")
    if not written:
        print("No spoken notes found.")
    # P399: the in-game checklist's tick log (vn-checklist-log.md, kept on the headset and pulled whole each run).
    log = raw / "vn-checklist-log.md"
    if log.exists():
        day = datetime.date.today().isoformat()
        folder = Path(args.out) / day
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "checklist-log.md").write_text("# Checklist ticks (Quest, in-game page)\n\n" + log.read_text(errors="replace"))
        print(f"wrote {folder / 'checklist-log.md'}")

    if not args.keep and remote:
        a = adb()
        # Only finished notes (an end line in the pulled sidecar): one still being recorded stays for next time.
        done = [n for n in remote if (raw / n).exists() and sidecar(raw / (n.rsplit(".", 1)[0] + ".jsonl"))[2]]
        for i in range(0, len(done), 50):
            subprocess.run([a, "shell", "rm", "-f"] + [f"{REMOTE}/{n}" for n in done[i:i + 50]])
        print(f"deleted {len(done)} pulled files from the headset")


if __name__ == "__main__":
    main()
