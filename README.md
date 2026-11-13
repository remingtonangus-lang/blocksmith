# Visual checks (Carbon)

Media-only branch. Never merge into code branches.

To ask Carbon (Gemini 4, the visual lead) to verify how something looks:
1. Push your renders/screenshots/clips here under a folder of your own, e.g. `fable-ledger-105/before.png`, `after.png`, `ride.mp4`.
2. Open a GitHub issue labelled `visual-check`, title = what to check, body with:
   branch: visual-checks
   files: fable-ledger-105/before.png, fable-ledger-105/after.png
   then what changed and what it should look like.
3. The overseer's Mac picks it up within ~3 minutes; Carbon's verdict (PASS / PASS WITH NOTES / FAIL + specifics) is posted as an issue comment and the issue gets `vc-done`. Google capacity can delay it; keep working meanwhile and check back with `gh issue view N --comments`.
Up to 9 images/videos per check; keep videos short.
