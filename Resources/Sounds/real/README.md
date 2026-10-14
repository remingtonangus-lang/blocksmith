# Recorded sounds (drop-in replacements)

Every sound in Blocksmith is synthesized in code. A WAV file in this folder named after a sound replaces that sound,
on the Mac and on the Quest, with no code change. With no file, the synthesized sound plays exactly as before.

The full list of names, what each event is and what a good recording should sound like is
`docs/audio/sound-list.md` (the 40 weakest synthesized sounds are marked WORST: start there).

## Naming

- The file name is the sound's stable name (`Snd.name` in Sources/Sound.swift) plus `.wav`, case as listed:
  `step_grass.wav`, `gun_0.wav`, `mob_horse_ambient.wav`, `hoof_stone.wav`, `rain.wav`, `doorOpen.wav`.
- Variants (takes) of one event: `<name>.wav` and/or `<name>_1.wav` ... `<name>_5.wav`. Every file found is one take;
  the game cycles through them. Give 3-5 takes for anything that repeats (footsteps, hoof falls, gunshots, impacts,
  mining hits), one file for loops and rare one-shots.
- Names never change: they are the contract between the code and the recordings.

## Format

- WAV (RIFF): 16-bit or 24-bit PCM (8/32-bit integer and 32/64-bit float also work), mono or stereo (mixed to mono:
  the engine places the sound in 3D), any sample rate (resampled to 44.1 kHz). 44.1 kHz mono 24-bit is ideal.
- Dry, close recordings: the game adds distance, panning, occlusion, underwater muffling and cave reverb itself.
- One-shots: trimmed tight (no lead-in silence), natural tail; a 1 ms fade-in and 5 ms fade-out are applied.
- Loops (names ending in `Loop`, plus `rain` and `rainRoof`): must loop seamlessly end-to-start; no fades are applied.
  Engine idle/full loops are cross-faded by throttle, so record both from the same engine.

## Levels

You do not need to match levels by hand. When a recording loads, all its takes get one gain that brings them to the
loudness of the synthesized sound they replace: the per-sound integrated loudness (ITU-R BS.1770 LUFS, the same
measure `tools/audiolevels.py` writes to `docs/status/audio_levels.md`), so the mix balance stays as tuned. The
quieter and louder takes of one event keep their difference. Peaks are then held at or below -1 dBFS. If the
synthesized sound is silent the category level is used instead (medians of audio_levels.md):

| category | target LUFS |
|---|---|
| players (own steps, weapons, actions) | -18 |
| blocks (blocks, mechanisms, vehicles, explosions) | -19 |
| ambient | -20 |
| friendly mobs | -21 |
| weather | -21.5 |
| hostile mobs | -22 |
| interface | -24 |

Still keep sensible headroom in the files (peaks around -3 to -1 dBFS, no clipping).

## Per-play variation

Recordings of repeating events (footsteps, soldier steps, hoof falls, mining hits, melee hits, mob hurt sounds,
gunshots, distant shots, bullet impacts, arrow hits) play with a random pitch of +-4% and a random level of +-2 dB
every time, on top of the take rotation, so a run of steps or a burst of fire never repeats exactly.

## How a file reaches the game

- Mac: `./build.sh` copies `Resources/Sounds/real/*.wav` into `Blocksmith.app/Contents/Resources/Sounds/real/`.
  Harness runs from the repo root also read this folder directly. To try a sound without rebuilding, put it in
  `~/Library/Application Support/Blocksmith/Sounds/` (wins over the bundled copy) and restart the game.
- Quest: `quest/tools/build-apk.sh` packs them into the APK as `assets/sounds/real/`. To try one without rebuilding,
  side-load it (wins over the APK copy) and restart the app:
  `adb push step_grass.wav /sdcard/Android/data/com.blocksmith.quest/files/Sounds/`
- The game logs `sounds: N recorded files override synthesized sounds` at the first sound load, and names any file
  it cannot read (it then keeps the synthesized sound).

Files are decoded once, off the audio thread, when the sound is first loaded (the background prewarm), never while
mixing. Only original or properly licensed recordings: no sounds from other games.

Code: Sources/RealSounds.swift (finder, WAV reader, resampler, loudness), SoundBank.clip (Sources/Sound.swift),
Sources/SoundEngine.swift (Mac) and quest/src/common/QuestSound.swift (Quest) for the per-play variation,
quest/src/android/AndroidMain.swift for the APK and side-load folders.
