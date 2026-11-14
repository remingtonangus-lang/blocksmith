# Trailer v3 cut list (tools/cine.py cut DIR OUT.mp4 --cutlist docs/store/trailer-v3/cine_cut.v3.py [--captions]).
# One thread: you ride into a frontier town, build, farm, ride the rails and explore; outlaws come for the town and
# you shoot back; you take the frigate and its main gun ends the fight; then the Deep and the last war; sunset.
# Each sound is synced to its event in shots.json (the hand's blocks and rounds, the main gun), so what you hear is
# what the game did on screen.
import json, os
_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))) if "__file__" in globals() else "."
_shots = {s["name"]: s for s in json.load(open(os.path.join("docs/store/trailer-v3/shots.json")))}

def _sfx(name, ss, secs, speed=1.0):
    """Sounds at the shot's own events, as seconds into the used part of the clip."""
    out = []
    s = _shots[name]
    hold = s.get("hold", "")
    gun = {"gun_revolver": "gun_13.wav", "gun_sidearm": "gun_13_1.wav", "gun_faust": "gun_4.wav", "gun_rifle": "gun_0_1.wav"}.get(hold)
    for e in s.get("events", []):
        t = e["t"]
        if e["do"] in ("lay", "reap"):
            snd = "break_plant.wav" if e["do"] == "reap" else ("place_stone.wav" if "stone" in e.get("block", "") else "place_wood.wav")
            for i, _ in enumerate(e.get("cells", [[0, 0, 0]])):
                out.append((t + i * e.get("dur", 0.3) + 0.18, snd, 0.8))
        elif e["do"] == "shoot" and gun:
            for i in range(e.get("n", 1)):
                out.append((t + 0.35 + i * e.get("dur", 0.45), gun, 0.9))
        elif e["do"] == "fire":
            out.append((t, "mainGunCharge.wav", 0.8))
            out.append((t + 2.6, "mainGunFire.wav", 1.0))
            out.append((t + 2.6 + e.get("flight", 0.2), "explodeLarge.wav", 1.0))
            out.append((t + 2.62 + e.get("flight", 0.2), "explodeLarge_1.wav", 0.9))
        elif e["do"] in ("wreck", "explode", "impact"):
            out.append((t, "explodeLarge.wav", 1.0))
    if s.get("playerMount") == "horse":
        k = 0.0
        while k < secs * speed + ss:
            out.append((k, f"hoof_earth_{1 + int(k * 3) % 5}.wav", 0.55)); k += 0.36
    return [((tt - ss) / speed, f, g) for (tt, f, g) in out if ss <= tt < ss + secs * speed]

def _shot(name, secs, cap, ss, extra=(), speed=1.0):
    return (name, secs, cap, _sfx(name, ss, secs, speed) + list(extra), {"xf": 0, "ss": ss, "speed": speed})

CUT = [
    # ACT I: your frontier (main_title.m4a)
    _shot("v3_hook", 3.5, "A frontier world, built for VR", 0.3),
    _shot("v3_ride", 3.4, "Ride out on your own horse", 0.6),
    _shot("v3_build", 3.4, "Build your home, block by block", 0.6),
    _shot("v3_farm", 2.8, "Work the land", 0.5),
    _shot("v3_train", 3.2, "Ride the rails", 2.5, [(0.3, "trainWhistle.wav", 0.7), (0.9, "steamChuff.wav", 0.6)]),
    _shot("v3_cave", 2.8, "Explore the caves below", 1.0),
    # ACT II: trouble comes (ash_vault_battle.m4a drops here)
    _shot("v3_outlaws", 4.6, "Defend your town from outlaws", 1.2),
    _shot("v3_frigate", 3.0, "Take command of a sky frigate", 0.6),
    _shot("v3_strike", 4.2, "and bring its main gun to bear", 1.6),
    _shot("v3_base", 2.6, "Infiltrate a base in the snow", 0.8),
    # ACT III: deeper
    _shot("v3_vault", 4.0, "Then go deeper, into the last war", 0.8),
    _shot("v3_finale", 3.6, None, 0.8),
]
TITLE = 4.5
SWITCH = "v3_outlaws"
FINALE = "v3_finale"
CARD = ("EARLY ACCESS ON META QUEST", "Play it now")
