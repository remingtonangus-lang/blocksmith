# Trailer hand-off (Nov 12, 12:55 UTC)

## Where things are
- Current cut (53.5 s, 1920x1080, 30 fps, CRF 20): /mnt/project-files/store-media/2026-10-31/sunderfall_trailer_captions.mp4 and
  sunderfall_trailer_clean.mp4. Also on the orphan branch store-media-2026-10-31 (commit bfe9f28), with covers/, screenshots/ and README.md.
  That README lists every fix so far. The cut Remington noted at "08:46" is the one before this. This one already addresses his 13 s, 18 s and 32 s notes.
- Per-shot clips: /mnt/project-files/store-media/2026-10-31/clips/<shot>.mp4 (1920x1080, CRF 20).
- Code (branch claude/project-thread-1q6065, draft PR #646, head 275aad1 + "clear" event commit):
  - quest/src/headless/Cinema.swift: questcheck --cine. Events: build, farm, rider, spawn, vehicle, wreck, clear, frigate, fire, impact, place, time...;
    per-shot `skip` (render layers).
  - docs/store/trailer-shots.json (shots), screenshot-shots.json, cover-shots.json.
  - tools/cine.py: the CUT list (shot, length, caption, ss start, speed, sounds) and `cut`.
- Render commands (Linux cloud, lavapipe; see runall.sh here):
  1. Build: `source <(tools/cloud-setup.sh env) && QUEST_OPT=-Ounchecked quest/tools/linux-check.sh build` (~40 min, ~7 GB; one build at a time). Use a branch merged with claude/quest-port.
  2. Render a shot: `QUEST_SKIP=landmarks questcheck --cine docs/store/trailer-shots.json --out DIR --w 2560 --h 1440 --only SHOT`.
     Encode at 1920 CRF 14 (runall.sh, which keeps every 15th frame for review). Test with --w 640 --h 360 [--still].
     Move an old frame dir aside first (runall.sh skips the shot if it exists). Renders take about 2 min a shot.
  3. Cut: `python3 tools/cine.py cut FULLDIR out_cap.mp4 --captions`, then the same without --captions. Re-encode with
     `ffmpeg -c:v libx264 -crf 20 -preset slow -pix_fmt yuv420p -c:a copy -movflags +faststart` (keep files under 100 MB).
  4. Review: sheet.py DIR OUT.jpg makes a 9-frame contact sheet. Crack probe: QUEST_VOIDPROBE=1 QUEST_SKIP=sky,landmarks paints see-through
     pixels magenta; cracks.py counts them.
- Rules: never commit media to code branches. No real insignia. No other games' names. Story order: surface, then hell, then the Ash Vault.
  No Ashguard on the surface.

## Still wrong / waiting on game fixes ("Fix Nov 1 playtest issues" lane)
1. Snow base: the roof's 42 cm deck_gun is being replaced by a light gun in that lane (next PR to quest-port). Until then station_air,
   station_gate and station_corridor carry a cine `clear` deck_gun event, and station_air carries skip ["ships"] (a parked dropship
   over the roof). When the PR lands, drop both and re-render the three shots.
2. Main-gun strike (frigate_strike, ~32 s): the blast's puffs reshuffle every frame (strobing), a dashed tracer flickers, and grey fragments
   hang in the sky. That lane has frames in ../notes-nov12/strike/. The cut trims it to 2.2 s (ss 0.6). Restore it once fixed.
3. Puffs with "eyes" (holed smoke picture) still show in war_advance (~29 s). Fixed on that lane's branch, not yet on quest-port.
4. Riders stand tall on their horses (the game has no sitting pose). It reads fine at a distance. Not reported as a game bug.
5. train shot: a birch with a root-flare cut-log face. The "Fix repeat store-blocking playtest artifacts" thread owns the stump fix.
6. Gate shot: soldier fights are not deterministic. One render had a blast crater with snow shards in the foreground, so check every render.
