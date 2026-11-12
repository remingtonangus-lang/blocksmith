# Store covers for Meta (Nov 12)

Five covers at Meta's exact sizes. All are 24-bit RGB PNGs.

| File | Size |
| --- | --- |
| hero_cover_3000x900.png | 3000x900 |
| cover_landscape_2560x1440.png | 2560x1440 |
| cover_square_1440x1440.png | 1440x1440 |
| cover_portrait_1008x1440.png | 1008x1440 |
| mini_landscape_1080x360.png | 1080x360 |

All five use the same midday shot: the frigate over the frontier village, with the Capital on the left. Each aspect is
rendered at its own shape (drawn at 2x, then scaled down), not cropped from the 16:9.

The title "SUNDERFALL" is in the trailer end card's serif, in warm ivory with a soft shadow. It sits centred in the
lower safe area over a soft dark band at the foot. There are no taglines, badges or text in the corners.

To redo them, from branch claude/project-thread-1q6065:
1. Render: `QUEST_SKIP=landmarks questcheck --cine docs/store/cover-v2.json --out DIR --w W --h H --still --only cov_<aspect>`.
   The 2x sizes are: landscape 5120x2880, square 2880x2880, portrait 2016x2880, hero 6000x1800, mini 2160x720.
2. Then `python3 tools/covers.py DIR OUT`.

The older candidates in covers/ have no title and are the wrong sizes. Don't upload them.
