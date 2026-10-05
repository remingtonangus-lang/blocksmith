# Frontier — audio (architecture, ids, pipeline, gaps)

All audio is original synthesis, original compositions rendered with an MIT soundfont, Apache-2.0 TTS, or CC0 /
public-domain field recordings checked per file (see `frontier/LICENSES.md`). Bar: `QUALITY_BAR.md` §9.

## Runtime (Godot, `frontier/src/audio/`)
| File | Role |
|---|---|
| `audio_director.gd` (`AudioDirector`, `Game.audio`) | buses, manifest, stream cache, pooled one-shots, occlusion, gunshots + echoes, impacts, Nerve, UI, voice + visemes, settings |
| `audio_locomotion.gd` (`AudioLocomotion`) | player footsteps (stride/gait/landing), NPC footsteps, hoof gaits, tack, horse breathing |
| `audio_surfaces.gd` (`AudioSurfaces`) | ground surface + biome at a point (control map, slope, altitude, water, registered floors) |
| `ambience_mixer.gd` (`AmbienceMixer`) | beds by biome/time/weather/altitude/interior; river/lake/town positional loops; creature calls; town life; thunder; emitters |
| `music_director.gd` (`MusicDirector`) | adaptive stem score: states, intensities, crossfades, exploration episodes, stingers |
| `audio_selftest.gd` | `--audiotest` headless check of every API (prints `AUDIOTEST … PASS/FAIL`) |

Hook-up: `main.gd` adds the director right after the world data loads (marked block; `--noaudio` skips it). It sets
`Game.audio = self` in `_ready`. Existing callers: `GunHandler.fire` → `gunshot()`, `Nerve` → `set_nerve()` /
`ui("nerve_mark")`.

### Buses (built in code)
`Master` (hard limiter −0.5 dB) ← `Music` (low-pass for Nerve) · `UI` · `Voice` · `World` (Nerve low-pass + pitch
shift) ← `SFX` (room reverb, wet when the listener is inside) · `Ambience` (low-pass when inside) · `AmbInside`
(rain on roof, wind through walls, room beds) · `Reverb` (100 % wet send: guns and voices get a second, quieter copy
here). The SFX volume slider drives `World`.

### API
```gdscript
Game.audio.play(id, pos_or_null, {volume_db, pitch, bus, delay, occlude, max_dist, unit_size, no_var}) -> Node
Game.audio.gunshot(sound_id, origin, is_player)          # revolver_heavy/light, rifle_lever/bolt/small/heavy, shotgun
Game.audio.gun_mech("cock"|"lever"|"bolt"|"pump"|"round"|"shell"|"dry"|"break_open"|"draw"|"holster"|..., pos)
Game.audio.impact("dirt"|"wood"|"metal"|"flesh"|"stone"|"water", pos); ricochet(pos); bullet_pass(pos, supersonic)
Game.audio.footstep(pos, surface="", gait="walk"|"run"|"land"|"scuff"); hoof(pos, surface="", "soft"|"hard")
Game.audio.track_horse(node)          # reads node.gait / node.speed if present; else derives from motion
Game.audio.locomotion.track_actor(npc)  # automatic NPC footsteps
Game.audio.surface_at(pos) -> String; register_interior(aabb, floor="wood", reverb); register_surface(aabb, "wood")
Game.audio.ambience.add_emitter("fire_camp", node_or_pos) / remove_emitter(p); ambience.set_room_bed("crowd_saloon")
Game.audio.music.set_mission("mission_ride"|""); music.set_tension(0..1, seconds); music.stinger("stinger_discovery")
Game.audio.set_nerve(on); set_low_health(0..1); ui("tick"|"select"|"back"|"page"|"map"|"notify"|"reward"|id)
Game.audio.play_voice(line_id, actor) -> duration   # signals voice_started, viseme(actor, shape, weight), voice_finished
Game.audio.bark(kind, actor, voice_type="")         # greeting/farewell/insult/alarm/hands_up/threat/shop/lawman/combat...
Game.audio.set_volume("Master"|"Music"|"SFX"|"Ambience"|"Voice"|"UI", 0..1)  # saved to user://audio_settings.cfg
```
Missing manifest/files/ids never crash: they are skipped (logged once each); `play_voice` still returns an estimated
duration so subtitles and scripted scenes keep timing.

### Gunshot model
Speed-of-sound delay (`d / 343 s`) for NPC shots. Variants by distance: close (< 140 m, blended with far from 60 m),
far (< 900 m: low-passed, softened attack, rolling terrain echoes), distant (beyond). Interiors (registered volumes)
use the indoor take (dense room, boomy) and occlude to the outside. The player's own shots play non-positionally.
Echoes: `find_reflectors()` marches the heightfield in 12 directions up to 700 m for faces that rise steeply above the
shooter (cliffs, mesa walls, valley sides) and, inside settlements, adds facade slaps across and along the street;
each reflection plays `gun_echo_<pistol|rifle|shotgun|small>` from the reflector position after
`(|shooter→face| + |face→listener|) / 343 s`, attenuated by path length, boosted by face height (max 5).

### Footsteps / hooves
Player stride lengths 0.72 / 1.05 / 1.45 m (walk / jog / sprint), landing after > 0.35 s airborne, shuffle scuffs at
idle, spur jingle on wood/stone. Surfaces: dirt, grass, gravel, stone, wood, mud, water, sand, snow (`AudioSurfaces`:
registered floors → water → standing above terrain in a settlement = boardwalk wood → snow line ~1150 m → roads
(dirt; gravel above 900 m; mud when wet) → steep = stone → desert sand/gravel/stone by sediment → wet bottoms = mud →
forest floor dirt/grass → grass). Hooves: walk 4-beat (1.05 s stride), trot 2-beat diagonal pairs, canter 3-beat,
gallop 4-beat rotary, positions per foot; saddle creaks / bridle jingle with the stride; breath per gallop stride.

### Ambience
Beds (stereo loops, fade 0.3/s): wind_calm / gusty / mountain / trees / grass / dust, cicadas (midday, warm biomes),
grasshoppers (plains/desert), crickets (night), frogs (night near water or marsh), rain light/heavy, rain on roof and
wind through walls when inside, optional room bed. Biome weights are sampled at the listener and 6 points 70 m out.
Positional: nearest river point (river or creek by width), nearest lake shore (radial search), town crowd at the
town centre. Calls: day birds per biome with a dawn chorus (×2.6 around 6:45) and dusk lift, suppressed by rain and
wind; night: owls, poorwills, coyotes (peak at dusk), wolves, elk bugles (autumn), bullfrogs near water. Town: anvil
and hammering bursts, dogs, horse snorts, church bell at 7/12/18 h, train whistle near rail towns, rooster at
ranches/homesteads at dawn, cattle near ranches. Thunder follows the sky's lightning flashes with distance delay.

### Music
Tracks in the manifest `music` table: stems (equal length, loop-ready OGG), `intensity` {low, mid, high} → stems.
Priority: Nerve (duck + low-pass + `stinger_nerve`) > mission (`set_mission`) > combat (gunfire within 160 m or the
player firing; level 1–3 by shots in the last 8 s; holds 14 s) > tension (`set_tension` or 12 s after combat) >
town (inside a town's ambience radius) > exploration (biome × day/night; episodes of 110–220 s with 50–150 s of
silence; intensity from riding speed). Crossfades 3 s (1.2 s into combat). `--music <state>` forces a state.

Tracks: `main_theme` (D minor, harmonica → fiddle → horns), `explore_plains_day` (G, Travis-picked guitar,
harmonica/fiddle), `explore_plains_night` (E minor, nylon guitar, cello, violin), `explore_desert_day` (A, Spanish
flavour: rasgueado nylon guitar, muted trumpet, whistle, low drone), `explore_mountains_day` (D, guitar + banjo
roll, fiddle, horns), `explore_night` (A minor piano + cello), `town` (C ragtime: stride honky-tonk piano, banjo,
fiddle), `tension` (tremolo strings, pizzicato pulse, high minor-second rub), `combat` (D minor 132 bpm: cello/bass
ostinato + guitar, toms/snare/taiko, trombone/horn stabs, fiddle runs), `mission_ride` (A minor gallop + trumpet
theme), `mission_heist` (B minor walking pizzicato, muted guitar, clarinet), stingers (`stinger_nerve`,
`stinger_mission_complete`, `stinger_death`, `stinger_discovery`), diegetic `saloon_piano` (also a 3D ambience
emitter id).

### Voices
`design/dialogue/voices.json` (casting), `ruth.json` (Ruth's lines), `barks.json` (NPC barks × voice types). Line ids:
Ruth lines by their id (e.g. `ruth_hands_up`), barks as `<bark id>__<voice type>` (e.g. `greet_howdy__man_rough`).
Manifest `voice` entries: `{file, duration, speaker, text, kind, emotion, phonemes, visemes: [[t, shape, weight]],
viseme_source}`. Viseme shapes: sil PP FF TH DD kk CH SS nn RR aa E ih oh ou.

## Build pipeline (`frontier/tools/audio/`)
| Script | Does |
|---|---|
| `dsp.py` | deterministic DSP: noise, filters (static + time-varying biquads), modal/FM/formant synthesis, synthetic IRs + convolution, compressor, look-ahead limiter, BS.1770 loudness, loop crossfade, OGG/WAV writer |
| `registry.py` | `@sound(id, category, variations, loop, max_dist, unit_size, pitch_var, ...)`; category loudness targets |
| `sfx_guns.py` | 7 weapons × close/indoor/far/distant + 4 echo slaps; cocking, lever, bolt, pump, break, loading, dry fire, casings, holster |
| `sfx_foley.py` | footsteps (9 surfaces × walk/run/land), hooves (9 × soft/hard), tack, horse body (synth fallback), bullet impacts, ricochet, whizz, crack-by, body fall, punch, doors, saloon doors, glass, bottles, coins, register |
| `sfx_ambience.py` | wind ×7, rain ×3, thunder (N-wave channel model), river, creek, lake shore, pier laps, fire ×2, crowd babble ×3, anvil, hammer, church bell, wagon, train whistle + chuff, windmill, clock |
| `sfx_creatures.py` | crickets, cicadas, grasshoppers, 10 bird call types, owl, poorwill, frogs, bullfrog, wolf, coyote chorus, elk bugle; synth fallbacks for cattle, dog, rooster |
| `sfx_ui.py` | UI ticks/select/back/error, page turn, map, pencil, notify, reward; Nerve in/out/heartbeat/mark, low-health heartbeat |
| `music.py` | the score (note data + arrangers: Travis picking, arpeggios, strums, stride, banjo rolls, ostinati, pads), MIDI per stem → FluidSynth (FluidR3_GM) → hall IR, glue compression, stem balance, loop fold, LUFS/true-peak master |
| `voices.py` | Kokoro TTS per line with casting + emotion approximations, post (HPF, EQ, compression, loudness), visemes |
| `commons.py` | Wikimedia Commons search → per-file licence check (CC0/PD only) → decode, split events / make loops → `rec_*` ids + `LICENSES_AUDIO.md` |
| `build_all.py` | renders all registered sounds in parallel, family-wise loudness, writes files + `manifest.json` + `report.json`; then the score |
| `verify.py` | checks (exists, decodes, peak < −0.3 dBFS, not silent, loop seams, stem lengths, every voice line has audio) + waveform/spectrogram contact sheets |
| `profile_sound.py` | dev loop: render one id, time + memory |

Local: `python3 frontier/tools/audio/build_all.py` (needs numpy, scipy, soundfile, mido; music needs `fluidsynth`
+ `fluid-soundfont-gm`), `python3 frontier/tools/audio/verify.py --plots /tmp/plots`, voices: `voices.py --model DIR`
(Kokoro ONNX files from the kokoro-onnx GitHub release; run it in a venv since kokoro-onnx wants numpy ≥ 2).
Game: `bash frontier/tools/fetch_assets.sh audio` pulls the CI build into `frontier/assets/ext/audio/`.

### Formats
Measured in Godot 4.7: starting an Ogg Vorbis stream costs ~0.7 ms (decoder setup per playback), a WAV imported as
QOA ~0.002 ms. So one-shots up to 3.2 s ship as 16-bit WAV (Godot imports them QOA-compressed), loops, long calls,
far gunshots, music and voices as Ogg Vorbis (`fmt="auto"` in `registry.py`).

### Loudness
One-shots are matched on maximum momentary loudness, loops on integrated loudness, per family (one gain for all
variations, so natural take-to-take variation survives): guns −11, far guns −18, echoes −20, mechanics −24, impacts
−16, footsteps −23, hooves −19, foley −20, creatures −20, UI −20, beds −24…−34 LUFS; all files true peak ≤ −1 dBFS
(look-ahead limiter on transients). Music mixes −17 LUFS (stingers −16…−18), stems balanced against the mix. Voices
−19 LUFS (shouts −15, whispers −25). The final mix adds per-sound `gain_db`, bus volumes and a master limiter.

### CI (`.github/workflows/frontier-assets.yml`, job `audio`)
Runs on pushes touching `frontier/tools/audio/**` or `frontier/design/dialogue/**` (or dispatch `mode=audio|all`):
apt `fluidsynth fluid-soundfont-gm ffmpeg`, pip `numpy scipy soundfile mido matplotlib kokoro-onnx`, cached Kokoro
model from the kokoro-onnx release, `build_all.py` → `voices.py` → `commons.py` (continue on error) → `verify.py
--plots`, publishes `audio.zip`, `audio_plots.zip`, `audio_build.log`, `verify.log`, `LICENSES_AUDIO.md` to the
`frontier-assets` release. `fetch_assets.sh` (default `ext`) also fetches `audio.zip`; `fetch_assets.sh audio` only audio.

## Adding a sound
1. Write a generator in the right `sfx_*.py`: `@sound("my_id", "foley", variations=4, max_dist=30, unit_size=2.0)`
   `def my_id(rng, v): return mono_or_stereo_array` (use `rng` only, for determinism).
2. `python3 frontier/tools/audio/build_all.py --no-music --only '^my_id$'` then `verify.py --only my_id --plots DIR`
   and look at the sheet.
3. Play it: `Game.audio.play("my_id", position)`. Commit; CI publishes the new `audio.zip`.
Music: add a `Track` in `music.compose_all()` (stems + `intensity`), build with `--music-only --music my_track`.
Dialogue: add lines to `design/dialogue/*.json` (speaker must exist in `voices.json`); CI renders them.

## Gaps / next
- Horse vocalisations, cattle, dogs, crowds, rooster and thunder rely on Commons recordings fetched in CI (first run
  pending); synthesized fallbacks are used until then (horse whinny synthesis is the weakest sound).
- Visemes are aligned heuristically (the public Kokoro ONNX export has no duration output); a timestamped export
  would give exact phoneme timing (voices.py already uses `create_timed` timings when present).
- TTS emotion is approximated (tempo/pitch/level/drive); Ruth's drawl comes from tempo and casting, not true accent.
- No interior volumes or wooden floors are registered yet (settlements are a stub): `register_interior` /
  `register_surface` are ready for the building generator; until then "above terrain in a town" = boardwalk.
- Music transitions are crossfades without bar-quantised entries; no musical transitions/stingers between states yet.
- `frontier.yml` (main CI, not touched here) should fetch audio on asset-cache hits:
  `[ -f frontier/assets/ext/audio/manifest.json ] || bash frontier/tools/fetch_assets.sh audio || true`.
- Quest: pitch-shift effect disabled for Nerve; consider fewer simultaneous beds and lower OGG quality there.
