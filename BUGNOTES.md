# Voice bug notes

Remington reports bugs by speaking while he plays (keyboard or Xbox controller). Blocksmith writes each spoken
note to a markdown file that a Claude session can work from.

## Where the notes are
`~/Documents/Blocksmith/BugNotes/`:
- `bug-notes.md`: one `## <date time> - <first words>` section per note, newest at the bottom.
- `note-<yyyy-MM-dd_HH.mm.ss>.png`: screenshot taken the moment he started talking.
- `note-<yyyy-MM-dd_HH.mm.ss>.m4a`: the note's audio. Listen to it if the transcript looks wrong.

Each entry lists:
- the transcript (or "(no transcript - listen to the audio)")
- `Status: open`
- the build commit
- world name and seed
- dimension
- position (displayed y) and facing
- biome
- the targeted block
- a ready `./snap.sh` repro command
- game mode, difficulty and any open screen
- day, time and weather
- frame time
- which input device was in use

## Turning notes into fixes (for a Claude session)
1. Remington pastes or attaches `bug-notes.md` (plus the PNGs and M4As if useful), or commits a copy to the repo.
   The file lives on his Mac, not in the repo.
2. Take the `Status: open` entries one at a time. Read the transcript. When it's garbled, use the screenshot and the
   context lines; the `.m4a` has the exact words.
3. Reproduce headlessly with the harness, not the GUI. Each entry has a **Repro** line: a ready `./snap.sh`
   command with the seed, x/z, yaw/pitch (harness convention), day fraction and dimension. It puts the camera on the
   terrain at that column. Add `--up N` for aerial spots; underground spots need a manual y.
   The entry also says which build he was on: `git log <commit>..` shows what has already changed since then.
4. Fix it on your session branch, commit with the note's timestamp in the message ("Bug note 2026-10-01 14:03: ..."),
   and push. CI's snapshots are the check.
5. Tell Remington which entries are fixed. He can change their `Status` to `fixed (<commit>)`.

## How it works (Sources/BugNotes.swift)
- Options > Interface > Bug Notes: Off / Always Listening / Push-to-Talk. It is greyed out with a hint if
  microphone or speech permission was denied.
  - Push-to-talk: hold F7, or click both sticks together (L3 + R3). Crouching is suppressed during the chord.
  - Always listening: an adaptive level threshold (noise floor × 3.5) opens a note after 0.2 s of voice and closes
    it after 1.2 s of quiet. Notes with under 0.35 s of voice are dropped. About 0.45 s of audio from before the note
    opened is kept.
- The mic runs on its own `AVAudioEngine`, so the game's sound engine is untouched. Voice processing / echo
  cancellation was left off: it can duck and reroute the game's output on macOS. Steady game audio instead raises
  the noise floor.
- Transcription runs on the Mac only: `SFSpeechRecognizer(en-US)` with `requiresOnDeviceRecognition`. Nothing is
  sent over the network. If the Mac can't recognise speech on-device, the note is saved with its audio and no
  transcript.
- In game:
  - A grey dot in the top-left shows the mic is listening; it turns red and pulses with "Note" while recording.
  - "Note saved" appears as a toast.
  - The game never pauses. The screenshot costs one frame.
- Harness: `Blocksmith --snapshot x.png --bugnotetest` runs a synthesized voice through the real segmentation, m4a,
  screenshot and markdown code, using a stub transcriber, in a temp folder. It checks one note → one entry, every
  field, and that the audio and screenshot files exist, then prints the entry. Any failure exits 3, so CI goes red.
