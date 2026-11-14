---
name: video-review
description: Find what's wrong in a game video (playtest recording, trailer, cinematic) when you can only see frames. Use for any "watch this video / check this footage / review the trailer" task.
---

# Video review

You see frames, not video. What frames lose is time, sound, the player's intent and frame rate, so recover those with
tools and data. A long checklist doesn't help: tested blind against Remington's own notes on 5 videos (Nov 13 2026),
a heavy per-shot worksheet scored the same as plain review. What did help was the event and flicker tools, and above
all the game's state log.

1. **Prepare.**
   ```
   python3 <skill>/tools/prep.py VIDEO OUT --step 0.25
   ```
   Outputs:
   - `shots.txt`: the shots, or one shot per clip in a joined recording
   - `shot_NN*.jpg`: storyboards in time order
   - `full/`: native-resolution frames every 0.25 s
   - `event_*.jpg`: every frame around each sudden visual or sound event. Use these for what came first, how fast
     things form or clear, and strobing.
   - `pops.txt` and `flicker.txt`: one-frame pops and regions flashing back and forth. Camera motion over stripes
     also triggers them, so look before you believe.
   - `audio.txt`: loudness and sudden sounds
2. **Read the state log first, if there is one.** Playtest clips have `rec-*.jsonl` sidecars with fps, held item,
   mount, what the player is looking at, biome, position and recent sounds. Line them up with the video. Use them for:
   - **frame rate:** below 72 is a finding; frames alone never show it
   - **intent:** what the player is trying to do, and whether it works (can't reload, board, drive or use something)
   - **sounds:** a sound with no matching visual (or the reverse) means something happened that shouldn't have, or
     off-camera
   On the holdout this added about a third more real finds.
3. **Look at every frame properly.** For small recordings (under 720 px), open the native frames in `full/` (at least
   one per second) instead of the storyboards, and zoom 2x into structures, vehicles and held items with
   `python3 <skill>/tools/mark.py zoom VIDEO SECONDS x0 y0 x1 y1 OUT.png`. Look for:
   - **behaviour over time:** what something is doing wrong, not only how it looks in one frame (lava that doesn't
     flow, a tree that splits into extra trunks)
   - **wrong shapes and colours, not only floating things:** a black mob, square wheels, mismatched pieces
   - **events with no visible cause, and characters that don't react**
   - **the camera itself:** eye height against people and doors, and anything cut off by the frame edge
   - **held items:** what they read as at a glance
   Name any capture artifact once (for example stale old frames stuck in part of the image), then ignore it.
4. **Report.** Order findings by how noticeable they are, as `[clock time] what's wrong (sure/likely/unsure)`. Mark the
   top findings with `mark.py box VIDEO SECONDS OUT.jpg "label" x0 y0 x1 y1`.

**Limits (measured):** reviewers find roughly 25-45% of what Remington says aloud while playing. They can't know his
design wishes, anything off-camera, or how a control felt. This adds to his notes; it doesn't replace them.
