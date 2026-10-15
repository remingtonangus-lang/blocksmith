# Alabaster visual reference spec (for the blind critic)

Alabaster is a realistic modern-military sandbox. Its look, judged against current AAA open-world games:

- **The Capital**: an opulent, authoritarian city of sleek white architecture (towers, terraces, skyways,
  plazas), clean and monumental. White surfaces must read as white with form (shading, ambient occlusion,
  facade detail), never as flat paper or blown-out glare.
- **Landscape**: realistic terrain at kilometre scale: mountains, river valleys, forests, coast. Believable
  scale cues, atmospheric perspective (haze grows with distance), no visible tiling or grid repetition, no
  stretched textures on slopes, no terraces, walls or seams that nature would not make.
- **Sky and weather**: physically based sky; clouds with volume, soft light, correct colour for the time of day
  (noon, dusk, night, overcast, rain, fog).
- **Vegetation**: forests read as forests from the ground and the air; no floating or buried trees, no visible
  pop-in bands, grass that sits on the ground.
- **Military**: soldiers, crawlers (six-wheeled), gunships, dropships, a frigate, naval ships, artillery; readable
  silhouettes, grounded (no floating or sinking), plausible proportions.
- **Defects to report**: floating or buried objects, z-fighting/flicker, holes or seams in terrain, objects
  intersecting, black or missing textures, exposure problems (blown highlights, crushed blacks), harsh aliasing,
  shadow artifacts (acne, peter-panning, missing contact shadows), unreadable UI, anything that looks broken.

Axes (score 0-10 each, only those the image lets you judge): composition and readability; lighting and sky;
materials and surfaces; terrain and vegetation; scale and atmosphere; technical artifacts (10 = none).
