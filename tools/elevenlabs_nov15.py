#!/usr/bin/env python3
"""The Nov 15, 2026 ElevenLabs batch (78 sounds, 302 takes) into Resources/Sounds/real.

  tools/elevenlabs_nov15.py TAKES_DIR [--measure] [--dry]

TAKES_DIR holds the MP3s from Drive (Sunderfall/sounds-elevenlabs-2026-11-15), named "NN <Sound> - take K.mp3". They
are never committed; only the one chosen take per sound lands in the repo, as a mono 16-bit 44.1 kHz WAV named by the
Snd it plays as (Resources/Sounds/real/README.md), the same path tools/elevenlabs_wire.py used in October.

--measure prints each take's numbers (length, peak, integrated loudness, head silence, clipped samples, the loop join)
in the table docs/status/elevenlabs-takes.md holds. The choice (below, TAKE) follows these rules:
  - drop a take that clips (a sample at or over -0.04 dBFS), has more than 150 ms of quiet before the sound (frames
    quieter than 40 dB under the take's peak), or runs more than 30% off the asked length;
  - a loop keeps the take with the smallest join step: the level step from its last 50 ms to its first 50 ms, plus half
    the mean spectral step (32 bands) across the join;
  - a one-shot keeps the take with the least head silence (20 ms steps), then the loudest;
  - a sound with no take left (every take starts late) is listed for a new take (WAIVED: until it comes, the take with
    the least lead-in whose sound still fills 60% of the asked length is used, trimmed).
Conversion: mono, 44.1 kHz; a one-shot is cut from 10 ms before its sound starts (2 ms fade in) to 60 ms after it ends
(25 ms fade out); a loop is kept whole (its join is the recording's own). Each is then brought to the loudness of a
recorded neighbour of the same kind (NEIGHBOUR; the old take of the same sound where there is one, so the takes of one
event stay level with each other), peaks held at -1 dBFS. The game matches levels again when it loads them.
Slots (elevenlabs_wire.py's rules): a loop replaces the old loop; a one-shot takes the base slot and the old recording,
if any, moves to the next free take slot, so both are heard in turn; `slice` cuts a run of hits into single takes.
"""
import json
import os
import re
import subprocess
import sys
import wave

import numpy as np

SR = 44100
DST = "Resources/Sounds/real"

# (number, sound in the doc, asked seconds, loop, chosen take, waived, slots, mode)
TAKE = [
    ("01", "Train running", 8, True, 3, False, ["trainCoachLoop"], "whole"),
    ("02", "Train running, outside", 8, True, 1, False, ["trainPassLoop"], "whole"),
    ("03", "Train idling at a station", 6, True, 4, False, ["trainIdleLoop"], "whole"),
    ("04", "Train brakes", 4, False, 4, False, ["trainBrakes"], "whole"),
    ("05", "Train pulling away", 5, False, 3, False, ["trainDepart"], "whole"),
    ("06", "Coupler clunk", 1.5, False, 2, False, ["trainCoupler"], "whole"),
    ("07", "Train whistle, long", 3, False, 1, False, ["trainWhistle"], "whole"),
    ("08", "Train whistle, two short", 2, False, 3, False, ["trainWhistleShort"], "whole"),
    ("09", "Station bell", 3, False, 1, False, ["stationBell"], "whole"),
    ("10", "Coach door", 2, False, 6, True, ["coachDoor"], "whole"),
    ("11", "Tree cracking", 2.5, False, 1, True, ["treeCrack"], "whole"),
    ("12", "Tree hitting the ground", 3, False, 3, False, ["treeLand"], "whole"),
    ("13", "Small tree falling", 2, False, 4, True, ["treeFallSmall"], "whole"),
    ("14", "Tree landing in snow", 2.5, False, 4, True, ["treeLandSnow"], "whole"),
    ("15", "Log rolling to rest", 2, False, 2, False, ["logRoll"], "whole"),
    ("16", "Elevator running", 6, True, 4, False, ["elevatorLoop"], "whole"),
    ("17", "Elevator arriving", 2, False, 3, False, ["elevatorArrive"], "whole"),
    ("18", "Elevator doors", 2.5, False, 4, False, ["elevatorDoors"], "whole"),
    ("19", "Garage door", 4, False, 2, False, ["garageDoor"], "whole"),
    ("20", "Radar sweep", 4, True, 2, False, ["radarLoop"], "whole"),
    ("21", "Radar contact", 1, False, 4, False, ["radarContact"], "whole"),
    ("22", "Radar warning", 2, False, 3, False, ["radarWarning"], "whole"),
    ("23", "Crawler engine", 8, True, 1, False, ["crawlerLoop"], "whole"),
    ("24", "Crawler stopping", 4, False, 3, False, ["crawlerStop"], "whole"),
    ("25", "Siege carriage pushing through trees", 4, False, 7, False, ["carriageTrees"], "whole"),
    ("26", "Vehicle hatch", 1.5, False, 1, False, ["vehicleHatch"], "whole"),
    ("27", "Tank machine gun", 6, True, 1, False, ["tankMGLoop"], "whole"),
    ("28", "Tank machine gun, last rounds", 1.5, False, 1, False, ["tankMGTail"], "whole"),
    ("29", "Shell casings on steel", 2, False, 1, False, ["casingsSteel"], "whole"),
    ("30", "Parachute opening", 2.5, False, 1, True, ["chuteOpen"], "whole"),
    ("31", "Parachute descending", 6, True, 2, False, ["chuteLoop"], "whole"),
    ("32", "Parachute landing", 2, False, 4, False, ["chuteLand"], "whole"),
    ("33", "Wall collapsing", 4, False, 6, False, ["wallCollapse"], "whole"),
    ("34", "Concrete breaking", 2, False, 4, False, ["concreteBreak"], "whole"),
    ("35", "Bullet into ice", 1.5, False, 3, False, ["bulletIce"], "whole"),
    ("36", "Bullet into a steel hull", 1.5, False, 1, False, ["bullet_impact_metal"], "whole"),
    ("37", "Bolt rifle reload", 2.5, False, 2, True, ["gun_reload_16"], "whole"),
    ("38", "Pistol reload", 2, False, 0, True, [], "none"),
    ("39", "Shotgun reload", 3, False, 1, True, ["gun_reload_2"], "whole"),
    ("40", "Submachine gun reload", 2, False, 4, True, ["gun_reload_17"], "whole"),
    ("41", "Sniper rifle reload", 2.5, False, 1, False, ["gun_reload_3"], "whole"),
    ("42", "Rocket launcher reload", 3, False, 1, False, ["gun_reload_4"], "whole"),
    ("43", "Machine gun reload", 4, False, 4, True, ["gun_reload_20", "gun_reload_19"], "whole"),
    ("44", "Revolver reload", 3, False, 4, True, ["gun_reload_23"], "whole"),
    ("45", "Distant rifle fire", 3, False, 1, False, ["gun_distant_0"], "whole"),
    ("46", "Distant machine gun", 3, False, 1, False, ["gun_distant_19"], "whole"),
    ("47", "Distant artillery", 4, False, 4, False, ["gun_distant_9"], "whole"),
    ("48", "Distant battle", 8, True, 3, False, ["battleLoop"], "whole"),
    ("49", "Item picked up", 0.5, False, 4, False, ["pickup"], "whole"),
    ("50", "Leather armour on", 1.5, False, 3, False, ["armor_equip_0"], "whole"),
    ("51", "Mail armour on", 1.5, False, 3, True, ["armor_equip_1"], "whole"),
    ("52", "Plate armour on", 2, False, 2, True, ["armor_equip_2", "armor_equip_3", "armor_equip_4", "armor_equip_5"], "whole"),
    ("53", "Coins traded", 1.5, False, 2, False, ["villagerTrade"], "whole"),
    ("54", "Blacksmith at work", 3, False, 3, False, ["villager_work_0", "villager_work_11", "villager_work_12"], "whole"),
    ("55", "Carpenter at work", 3, False, 4, False, ["villager_work_6"], "whole"),
    ("56", "Farmer at work", 2.5, False, 1, False, ["villager_work_4"], "whole"),
    ("57", "Tripwire", 0.7, False, 3, False, ["tripwire"], "whole"),
    ("58", "Sulphur vents", 6, True, 2, False, ["sulfurLoop"], "whole"),
    ("59", "Deep boom", 4, False, 4, False, ["sealBoom"], "whole"),
    ("60", "Falling fast", 5, True, 4, False, ["fallRushLoop"], "whole"),
    ("61", "City square crowd", 10, True, 1, False, ["cityCrowdLoop"], "whole"),
    ("62", "Market street", 8, True, 4, False, ["marketLoop"], "whole"),
    ("63", "Crowd in panic", 6, True, 3, False, ["crowdPanicLoop"], "whole"),
    ("64", "Fighting in a city", 8, True, 4, False, ["cityFightLoop"], "whole"),
    ("65", "Quest accepted", 2, False, 4, False, ["questAccept"], "whole"),
    ("66", "Quest completed", 3, False, 3, False, ["questDone"], "whole"),
    ("67", "Quest failed", 2.5, False, 4, False, ["questFail"], "whole"),
    ("68", "Convoy horse and cart", 6, True, 2, False, ["convoyCartLoop"], "whole"),
    ("69", "Customs gate", 3, False, 1, True, ["customsGate"], "whole"),
    ("70", "Well bucket", 4, False, 1, False, ["wellBucket"], "whole"),
    ("71", "House bought", 2, False, 3, False, ["houseBought"], "whole"),
    ("72", "Far volcano", 8, True, 2, False, ["volcanoLoop"], "whole"),
    ("73", "Sheet ice underfoot", 3, False, 5, False, ["sheetIceStep"], "slice"),
    ("74", "Ice cracking under weight", 2.5, False, 6, False, ["iceCrack"], "whole"),
    ("75", "Snowy bush", 1.5, False, 4, False, ["snowyBush"], "whole"),
    ("76", "Chair", 1, False, 2, False, ["chairSit"], "whole"),
    ("77", "Chest of drawers", 1.5, False, 4, False, ["drawerOpen"], "whole"),
    ("78", "Rocket tube in hand", 2, False, 3, False, ["faustShoulder"], "whole"),
]

# A recorded sound of the same kind each new one is levelled to (when its own slot has no old take).
NEIGHBOUR = {
    "train": "steamChuff", "trainWhistleShort": "trainWhistle", "stationBell": "trainWhistle", "coachDoor": "doorOpen",
    "tree": "break_wood", "logRoll": "break_wood", "elevator": "ironDoorOpen", "garageDoor": "ironDoorOpen",
    "radar": "sonarPing", "crawler": "tankTracksLoop", "carriageTrees": "break_wood", "vehicleHatch": "ironDoorClose",
    "tankMG": "flakFire", "casingsSteel": "step_metal", "chute": "packRustle", "wallCollapse": "explodeLarge",
    "concreteBreak": "break_stone", "bulletIce": "bullet_impact_glass", "gun_reload": "gun_reload_0", "pickup": "packRustle",
    "villagerTrade": "chestOpen", "tripwire": "dartTrap", "sulfurLoop": "netherWastesLoop", "sealBoom": "explodeLarge",
    "fallRushLoop": "snowWindLoop", "cityCrowdLoop": "townLoop", "marketLoop": "townLoop", "crowdPanicLoop": "townLoop",
    "cityFightLoop": "battleLoop", "quest": "airRaidSiren", "convoyCartLoop": "townLoop", "customsGate": "doorOpen",
    "wellBucket": "splash", "houseBought": "doorOpen", "volcanoLoop": "netherWastesLoop", "sheetIceStep": "step_snow",
    "snowyBush": "plantBrush_1", "chairSit": "step_wood", "drawerOpen": "chestOpen", "faustShoulder": "gun_reload_4",
}


def is_loop(name):
    return name.endswith("Loop") or name in ("rain", "rainRoof", "ashSiren")


def decode(path, ch=1):
    r = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", str(ch), "-ar", str(SR), "-f", "f32le", "-"],
                       capture_output=True, check=True)
    return np.frombuffer(r.stdout, dtype=np.float32).reshape(-1, ch)


def lufs_file(path):
    r = subprocess.run(["ffmpeg", "-nostats", "-i", path, "-af", "ebur128", "-f", "null", "-"], capture_output=True, text=True)
    m = re.findall(r"I:\s+(-?[\d.]+) LUFS", r.stderr)
    return float(m[-1]) if m else -70.0


def db(v):
    return float(20 * np.log10(max(float(v), 1e-9)))


def frames(x, ms=5):
    hop = int(SR * ms / 1000)
    n = len(x) // hop
    return np.sqrt((x[: n * hop].reshape(n, hop) ** 2).mean(axis=1)), hop


def measure(path, want):
    st = decode(path, 2)
    x = st.mean(axis=1)
    peak = float(np.abs(st).max())
    env, hop = frames(x)
    thr = max(peak * 10 ** (-40 / 20), 1e-3)
    loud = np.where(env > thr)[0]
    head = loud[0] * hop / SR if len(loud) else len(x) / SR
    w = int(SR * 0.05)
    a, b = x[:w], x[-w:]

    def bands(s):
        S = np.abs(np.fft.rfft(s * np.hanning(len(s))))
        return np.array([db(np.sqrt((q ** 2).mean())) for q in np.array_split(S, 32)])
    return dict(dur=round(len(x) / SR, 2), want=want, peak=round(db(peak), 1), clip=int((np.abs(st) >= 0.995).sum()),
                lufs=lufs_file(path), head=int(round(head * 1000)),
                join=round(abs(db(np.sqrt((b ** 2).mean())) - db(np.sqrt((a ** 2).mean()))), 1),
                spec=round(float(np.abs(bands(a) - bands(b)).mean()), 1))


def load_wav(path):
    w = wave.open(path)
    n, ch, sw, sr = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
    raw = w.readframes(n)
    if sw == 2:
        x = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768
    elif sw == 3:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3)
        x = ((b[:, 0].astype(np.int32) | (b[:, 1].astype(np.int32) << 8) | (b[:, 2].astype(np.int32) << 16)) << 8 >> 8).astype(np.float32) / 8388608
    else:
        raise ValueError(path)
    return x.reshape(-1, ch).mean(axis=1), sr


def save(path, x):
    w = wave.open(path, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
    w.close()


def lufs_of(x):
    tmp = "/tmp/_el_lufs.wav"
    save(tmp, x)
    return lufs_file(tmp)


def trim(x):
    env, hop = frames(x)
    thr = max(env.max() * 10 ** (-40 / 20), 1e-4)
    loud = np.where(env > thr)[0]
    a = max(0, loud[0] * hop - int(SR * 0.01))
    e = min(len(x), (loud[-1] + 1) * hop + int(SR * 0.06))
    x = x[a:e].copy()
    fi, fo = int(SR * 0.002), min(len(x) // 4, int(SR * 0.025))
    x[:fi] *= np.linspace(0, 1, fi)
    x[-fo:] *= np.linspace(1, 0, fo)
    return x


def slices(x, count=5):
    """A run of footfalls cut into single hits: onsets where the 5 ms level climbs 10 dB over the 60 ms before it."""
    env, hop = frames(x)
    e = 20 * np.log10(env + 1e-6)
    top, out, last = e.max(), [], -1e9
    for i in range(2, len(e)):
        t = i * hop / SR
        if e[i] > top - 30 and e[i] - e[max(0, i - 12): i].min() > 10 and t - last > 0.18:
            out.append(i * hop)
            last = t
    segs = []
    for k, s in enumerate(out):
        end = out[k + 1] if k + 1 < len(out) else len(x)
        seg = x[max(0, s - int(SR * 0.008)): min(end, s + int(SR * 0.45))].copy()
        fo = min(len(seg) // 4, int(SR * 0.03))
        seg[-fo:] *= np.linspace(1, 0, fo)
        segs.append((float(np.abs(seg).max()), k, seg))
    return [s for _, _, s in sorted(sorted(segs, key=lambda t: -t[0])[:count], key=lambda t: t[1])]


def neighbour(slot):
    for k in sorted(NEIGHBOUR, key=len, reverse=True):
        if slot == k or slot.startswith(k):
            return NEIGHBOUR[k]
    return None


def takes_of(name):
    return [f"{name}.wav"] + [f"{name}_{k}.wav" for k in range(1, 6)]


def main():
    src = sys.argv[1]
    dry = "--dry" in sys.argv
    if "--measure" in sys.argv:
        for num, title, want, loop, *_ in TAKE:
            for k in range(1, 6):
                p = f"{src}/{num} {title} - take {k}.mp3"
                if os.path.exists(p):
                    print(json.dumps(dict(num=num, name=title, take=k, loop=loop, **measure(p, want))), flush=True)
        return
    for num, title, want, loop, take, waived, slots, mode in TAKE:
        if mode == "none":
            print(f"{num} {title:38s} -> no usable take (listed for a new one)")
            continue
        x = decode(f"{src}/{num} {title} - take {take}.mp3")[:, 0]
        parts = slices(trim(x)) if mode == "slice" else [x if loop else trim(x)]
        placed = []
        for slot in slots:
            have = [t for t in takes_of(slot) if os.path.exists(f"{DST}/{t}")]
            ref = f"{DST}/{slot}.wav" if f"{slot}.wav" in have and not loop else None
            if ref is None and neighbour(slot):
                ref = f"{DST}/{neighbour(slot)}.wav"
            target = lufs_of(load_wav(ref)[0]) if ref and os.path.exists(ref) else -20.0
            outs = []
            for p in parts:
                g = 10 ** ((target - lufs_of(p)) / 20)
                y = p * g
                pk = np.abs(y).max()
                if pk > 10 ** (-1 / 20):
                    y *= 10 ** (-1 / 20) / pk
                outs.append(y)
            if mode == "slice":
                if not dry:
                    for t in have:
                        os.remove(f"{DST}/{t}")
                    for k, y in enumerate(outs):
                        save(f"{DST}/{slot}_{k + 1}.wav", y)
                placed.append(f"{slot}_1..{len(outs)}")
                continue
            y = outs[0]
            if loop or f"{slot}.wav" not in have:
                dest = f"{slot}.wav"
            else:
                free = [t for t in takes_of(slot)[1:] if t not in have][0]
                if not dry:
                    os.rename(f"{DST}/{slot}.wav", f"{DST}/{free}")
                dest = f"{slot}.wav"
                placed.append(f"(old {slot} -> {free[:-4]})")
            if not dry:
                save(f"{DST}/{dest}", y)
            placed.append(dest[:-4])
        print(f"{num} {title:38s} take {take}{' (waived)' if waived else ''} -> {' '.join(placed)}")


if __name__ == "__main__":
    main()
