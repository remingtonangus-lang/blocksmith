#!/usr/bin/env python3
"""P457: Remington's approved ElevenLabs sound effects (Oct 25, 2026) wired to the game's sounds.

  tools/elevenlabs_wire.py [--dry]

Ran once on Oct 29, 2026: each approved file in Resources/Sounds/elevenlabs/ became a recording in Resources/Sounds/real/
named after the sound it plays as (Snd.name, Resources/Sounds/real/README.md), so the Mac and the Quest pick it up
with no other change. The originals are in git history (the commit before this script's); the elevenlabs README now
lists where each one went. Rules:
  whole    the file as it is. A loop replaces the old loop (a loop plays one take); a one-shot takes the base slot and
           the old recording, if any, moves to the next free take slot, so both are heard in turn.
  trim     the same, cut to [start, end) seconds first.
  slice    a file of several hits (footsteps, pick strikes, bites, hoof falls) cut into single hits; these replace
           every old take of that sound. `tail`: automatic gunfire, where each shot is cut short by the next: the
           burst's own ring-out is joined on after each shot, so a shot alone still rings.
"""
import os
import sys
import wave

import numpy as np

SRC = "Resources/Sounds/elevenlabs"
DST = "Resources/Sounds/real"
SR = 44100

# (source, sound name, mode, options)
MAP = [
    # Vehicles
    ("tank_engine_idle_loop", "tankEngineLoop", "whole", {}),
    ("tank_tracks_drive_loop", "tankTracksLoop", "whole", {}),
    ("truck_engine_drive_loop", "truckEngineLoop", "whole", {}),
    ("motorcycle_sidecar_engine_loop", "motorbikeLoop", "whole", {}),
    ("propeller_plane_flyby", "planeFlyby", "whole", {}),
    ("siege_carriage_engine_loop", "carriageTreadLoop", "whole", {}),
    ("helicopter_rotor_loop", "rotorLoop", "whole", {}),
    ("dropship_engine_loop", "strikeRoarLoop", "whole", {}),
    ("jetpack_thrust_loop", "jetpackLoop", "whole", {}),
    ("rail_cart_rolling_loop", "minecartLoop", "whole", {}),
    ("frigate_interior_hum_loop", "frigateInsideLoop", "whole", {}),
    ("ship_horn_distant", "shipHorn", "whole", {}),
    ("submarine_sonar_ping", "sonarPing", "whole", {}),
    # Guns and blasts
    ("bolt_rifle_shot", "gun_16", "whole", {}),
    ("assault_rifle_burst", "gun_18", "slice", dict(gap=0.035, maxlen=0.2, count=3, tail=True)),
    ("pistol_shot", "gun_13", "whole", {}),
    ("smg_burst", "gun_17", "slice", dict(gap=0.04, maxlen=0.2, count=5, tail=True, rise=5)),
    ("sniper_shot_distant", "gun_distant_3", "whole", {}),
    ("magazine_reload", "gun_reload_18", "whole", {}),
    ("gun_jam_click", "gun_7", "whole", {}),
    ("rocket_launch", "gun_4", "whole", {}),
    ("naval_gun_blast", "gun_9", "whole", {}),
    ("tank_cannon_fire", "tankCannon", "whole", {}),
    ("flak_gun_fire", "flakFire", "slice", dict(gap=0.08, maxlen=0.25, count=3, tail=True)),
    ("large_explosion_debris", "explodeLarge", "whole", {}),
    ("artillery_incoming_explosion", "explodeLarge", "whole", {}),
    ("grenade_explosion", "explodeSmall", "whole", {}),
    ("bombs_falling_whistle", "shellIncoming", "trim", dict(start=0.0, end=2.45)),
    ("base_alarm_klaxon_loop", "gun_10", "whole", {}),
    ("radio_static_chatter", "gun_11", "whole", {}),
    ("air_raid_siren", "airRaidSiren", "whole", {}),
    ("distant_battle_ambience_loop", "battleLoop", "whole", {}),
    # Doors, containers, traps, tools
    ("bulkhead_door_open", "ironDoorOpen", "whole", {}),
    ("metal_door_slam", "ironDoorClose", "whole", {}),
    ("chest_open_wood", "chestOpen", "whole", {}),
    ("arrow_trap_fire", "dartTrap", "whole", {}),
    ("tnt_fuse_hiss", "tntFuse", "whole", {}),
    ("glass_shatter", "break_glass", "whole", {}),
    ("crafting_hammer_anvil", "anvil", "slice", dict(gap=0.25, maxlen=0.4, count=4, skip_first=True)),
    ("inventory_cloth_rustle", "packRustle", "whole", {}),
    ("stone_mining_pick", "hit_stone", "slice", dict(gap=0.4, maxlen=0.45, count=3)),
    ("wood_chop_axe", "hit_wood", "slice", dict(gap=0.4, maxlen=0.45, count=3)),
    ("dirt_dig_shovel", "break_dirt", "whole", {}),
    # Combat
    ("sword_swing_hit", "armourHit", "trim", dict(start=0.66, end=1.4)),
    ("shield_block_metal", "shieldBlock", "whole", {}),
    ("body_hit_thud", "attackWeak", "whole", {}),
    # The player
    ("footsteps_grass", "step_grass", "slice", dict(gap=0.38, maxlen=0.4, count=5)),
    ("footsteps_snow", "step_snow", "slice", dict(gap=0.3, maxlen=0.45, count=5)),
    ("footsteps_gravel", "step_gravel", "slice", dict(gap=0.3, maxlen=0.45, count=5)),
    ("footsteps_wood_floor", "step_wood", "slice", dict(gap=0.3, maxlen=0.45, count=5)),
    ("footsteps_metal_deck", "step_metal", "slice", dict(gap=0.15, maxlen=0.45, count=5)),
    ("ladder_climb_metal", "ladderClimb", "slice", dict(gap=0.35, maxlen=0.5, count=5)),
    ("leaves_rustle_push", "plantBrush", "slice", dict(gap=0.6, maxlen=0.9, count=2, rise=6)),
    ("water_splash_jump", "splash", "whole", {}),
    ("swimming_strokes_loop", "swim", "slice", dict(gap=0.35, maxlen=0.8, count=5)),
    ("eat_food", "eat", "slice", dict(gap=0.3, maxlen=0.6, count=3)),
    ("drink_gulp", "drink", "slice", dict(gap=0.3, maxlen=1.1, count=3)),
    ("fire_ignite_whoosh", "ignite", "whole", {}),
    # Places and weather
    ("hell_lava_ambience_loop", "netherWastesLoop", "whole", {}),
    ("lava_bubble_pop", "lavaPop", "whole", {}),
    ("big_fire_crackle_loop", "campfireLoop", "whole", {}),
    ("snow_wind_loop", "snowWindLoop", "whole", {}),
    ("underwater_ambience_loop", "underwaterLoop", "whole", {}),
    ("river_flow_loop", "riverLoop", "whole", {}),
    ("ocean_waves_loop", "oceanLoop", "whole", {}),
    ("rain_heavy_loop", "rain", "whole", {}),
    ("rain_on_roof_loop", "rainRoof", "whole", {}),
    ("thunder_crack", "thunder", "whole", {}),
    ("cave_drips_ambience_loop", "dripstoneLoop", "whole", {}),
    ("forest_birds_day_loop", "forestDayLoop", "whole", {}),
    ("night_crickets_loop", "cricketsLoop", "whole", {}),
    ("village_ambience_loop", "townLoop", "whole", {}),
    ("saloon_piano_loop", "saloonPianoLoop", "whole", {}),
    # Animals
    ("horse_gallop_loop", "hoof_earth", "slice", dict(gap=0.1, maxlen=0.16, count=5, rise=18)),
    ("horse_neigh", "mob_horse_ambient", "whole", {}),
    ("hell_creature_screech", "mob_searwing_ambient", "whole", {}),
]

# Sounds that loop (Snd.isLoop, plus the new ones above; tools/sfxpack.py pads these by name too).
LOOPS = {"rain", "rainRoof", "ashSiren"}


def is_loop(name):
    return name.endswith("Loop") or name in LOOPS


def load(path):
    w = wave.open(path)
    assert w.getnchannels() == 1 and w.getsampwidth() == 2 and w.getframerate() == SR, path
    return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768


def save(path, x):
    w = wave.open(path, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
    w.close()


def envelope(x, hop):
    n = len(x) // hop
    return 20 * np.log10(np.sqrt(np.mean(x[: n * hop].reshape(n, hop) ** 2, axis=1)) + 1e-6)


def onsets(x, gap, rise=10.0):
    """Starts of hits: the 5 ms envelope climbing `rise` dB over its low of the 60 ms before, gap seconds apart."""
    hop = int(SR * 0.005)
    e = envelope(x, hop)
    top = e.max()
    out, last = [], -1e9
    for i in range(2, len(e)):
        low = e[max(0, i - 12): i].min()
        t = i * hop / SR
        if e[i] > top - 30 and e[i] - low > rise and t - last > gap:
            out.append(i * hop)
            last = t
    return out


def fade(x, fin=0.002, fout=0.02):
    x = x.copy()
    a, b = min(len(x) // 4, int(SR * fin)), min(len(x) // 4, int(SR * fout))
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def slices(x, gap, maxlen, count, tail=False, skip_first=False, rise=10.0):
    on = onsets(x, gap, rise)
    if skip_first and on and on[0] < int(SR * 0.05):
        on = on[1:]
    pre = int(SR * 0.008)
    # Each hit starts just before its own peak (a soft lead-in can set the onset off early).
    on = [max(s, s + int(np.argmax(np.abs(x[s: s + int(SR * 0.08)]))) - int(SR * 0.015)) for s in on]
    # The burst's last real shot (a stray click after it is not one).
    loud = [s for s in on if np.abs(x[s: s + int(SR * 0.05)]).max() > 0.25 * np.abs(x).max()]
    last = loud[-1] if loud else on[-1]
    segs = []
    for k, s in enumerate(on):
        end = on[k + 1] - pre if k + 1 < len(on) else len(x)
        end = min(end, s + int(SR * maxlen)) if not tail else end
        seg = x[max(0, s - pre): end]
        if tail and s < last:
            # The burst's ring-out after its last shot, from the same moment after that shot, joined on in 8 ms.
            ring = x[last + (end - s):]
            xf = min(int(SR * 0.008), len(seg), len(ring))
            if xf > 0:
                w = np.linspace(0, 1, xf)
                seg = np.concatenate([seg[:-xf], seg[-xf:] * (1 - w) + ring[:xf] * w, ring[xf:]])
        segs.append((float(np.abs(seg).max()), k, seg))
    best = sorted(sorted(segs, key=lambda t: -t[0])[:count], key=lambda t: t[1])
    return [fade(s, fout=0.03 if not tail else 0.05) for _, _, s in best]


def main():
    dry = "--dry" in sys.argv
    placed, ours = {}, set()
    for src, name, mode, opt in MAP:
        x = load(f"{SRC}/{src}.wav")
        takes = [f"{name}.wav"] + [f"{name}_{k}.wav" for k in range(1, 6)]
        have = [t for t in takes if os.path.exists(f"{DST}/{t}")]
        if mode == "slice":
            parts = slices(x, **opt)
            if not dry:
                for t in have:
                    os.remove(f"{DST}/{t}")
                for k, p in enumerate(parts):
                    save(f"{DST}/{name}_{k + 1}.wav", p)
            placed[src] = f"{name}_1..{len(parts)} ({len(parts)} hits)"
        else:
            if mode == "trim":
                x = fade(x[int(SR * opt["start"]): int(SR * opt["end"])], fout=0.05)
            if is_loop(name) or f"{name}.wav" not in have:
                slot = f"{name}.wav"
            elif f"{name}.wav" in ours:
                slot = [t for t in takes[1:] if t not in have][0]            # a second approved take
            else:
                # The old one-shot moves aside to the next free take; the approved one takes the base slot.
                free = [t for t in takes[1:] if t not in have][0]
                if not dry:
                    os.rename(f"{DST}/{name}.wav", f"{DST}/{free}")
                slot = f"{name}.wav"
            ours.add(slot)
            if not dry:
                save(f"{DST}/{slot}", x)
            placed[src] = slot[:-4]
        if not dry:
            os.remove(f"{SRC}/{src}.wav")
        print(f"{src:34s} -> {placed[src]}")


if __name__ == "__main__":
    main()
