"""Sound registry: generator modules declare sounds with @sound(...); build_all.py renders them, normalises loudness per
category, writes OGG/WAV files and the manifest the Godot AudioDirector reads (assets/ext/audio/manifest.json).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable

# Loudness targets per category. One-shots are matched on their *maximum momentary* loudness (400 ms window), loops
# on integrated loudness. The game applies per-bus and per-sound gain on top (manifest gain_db), so these targets keep
# each family internally consistent rather than defining the final mix.
CATEGORIES = {
    #  name        bus         target  measure   peak ceiling (dBFS true peak)
    "gun":       ("SFX",      -11.0,  "max", -1.0),
    "gun_far":   ("SFX",      -18.0,  "max", -1.0),
    "gun_echo":  ("SFX",      -20.0,  "max", -1.0),
    "gun_mech":  ("SFX",      -24.0,  "max", -1.0),
    "impact":    ("SFX",      -16.0,  "max", -1.0),
    "bullet":    ("SFX",      -18.0,  "max", -1.0),
    "foot":      ("SFX",      -23.0,  "max", -1.0),
    "hoof":      ("SFX",      -19.0,  "max", -1.0),
    "tack":      ("SFX",      -26.0,  "max", -1.0),
    "foley":     ("SFX",      -20.0,  "max", -1.0),
    "creature":  ("Ambience", -20.0,  "max", -1.0),
    "horse":     ("SFX",      -18.0,  "max", -1.0),
    "ui":        ("UI",       -20.0,  "max", -1.0),
    "nerve":     ("UI",       -18.0,  "max", -1.0),
    "weather":   ("Ambience", -16.0,  "max", -1.0),
    "amb_loop":  ("Ambience", -24.0,  "int", -1.0),
    "amb_bed":   ("Ambience", -28.0,  "int", -1.0),
    "voice":     ("Voice",    -18.0,  "int", -1.0),
    "music":     ("Music",    -18.0,  "int", -1.0),
}


@dataclass
class SoundDef:
    id: str
    category: str
    fn: Callable                # fn(rng, variant_index) -> np.ndarray (mono or stereo)
    variations: int = 1
    loop: bool = False
    gain_db: float = 0.0        # applied in game (not baked)
    pitch_var: float = 0.04     # +- fraction, applied in game per play
    vol_var_db: float = 1.5
    max_dist: float = 60.0      # metres, for 3D one-shots (AudioStreamPlayer3D.max_distance)
    unit_size: float = 4.0      # AudioStreamPlayer3D.unit_size (distance of 0 dB attenuation)
    fmt: str = "auto"           # auto: WAV (QOA-imported, ~free to start) for one-shots <= 3.2 s, else Ogg Vorbis
    stereo: bool = False
    target: float | None = None  # override category loudness target
    tags: dict = field(default_factory=dict)
    folder: str = "sfx"


SOUNDS: dict[str, SoundDef] = {}


def sound(id: str, category: str, variations: int = 1, **kw):
    def deco(fn):
        if id in SOUNDS:
            raise ValueError("duplicate sound id " + id)
        SOUNDS[id] = SoundDef(id=id, category=category, fn=fn, variations=variations, **kw)
        return fn
    return deco


def family(ids_and_args, category: str, fn_factory, **kw):
    """Register many sounds from one parametrised generator: ids_and_args = {id: params}."""
    for sid, p in ids_and_args.items():
        SOUNDS[sid] = SoundDef(id=sid, category=category, fn=fn_factory(sid, p), **kw)
