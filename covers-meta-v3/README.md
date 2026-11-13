# Meta store covers v3 (Nov 13)

Replaces covers-meta/ (v1, failed Carbon review #720). Re-check: issue #721.

- cover_landscape_2560x1440.png, cover_square_1440x1440.png, cover_portrait_1008x1440.png,
  hero_cover_3000x900.png, mini_landscape_1080x360.png (24-bit RGB PNG, exact Meta sizes)
- Golden-hour key art from a low angle: the frigate at 3/4 view over the treeline, the Capital on the left. Each size is rendered natively at 2x.
- New chiselled gold serif "Sunderfall" logo inside Meta's safe zones (the inner 70%; on the hero, inside 780..2220 x 135..765), checked by tools/covers.py.
- Source: docs/store/cover-v3.json, tools/logo.py, tools/covers.py on claude/project-thread-1q6065.
