# Asset credits

## Block textures (Resources/Textures)
Art direction: "stylised realism" (docs/art/style-options/3-stylised-realism.png, picked by Remington 2026-10-09).

- Source sheets: assets/gemini/sheets/s01-s13 (s13: ores, 2026-10-10), generated 2026-10-09/10 with Google Gemini (gemini.google.com, image
  generation, Remington's Google AI Pro account). Prompt pattern: "a texture sheet for a voxel survival game in a
  STYLISED REALISM style (real-world materials, simplified, subtle surface detail, natural muted colours, soft
  hand-painted look, NOT pixel art, NOT cartoon); NxN grid of square seamless tiles with thin dark gaps, flat
  orthographic, even light, no text or labels", followed by a per-row list of materials (the tile map with each cell's
  layer name is docs/textures/sheets.json).
- Processing: tools/sheetslice.py (cut, soften, seam blend, saturation cap, contrast floor, ore compositing onto the
  shared stone) -> tools/teximport.py; tools/texderive.py carries each family's look to its relatives (rotated logs,
  dyed wool/concrete/terracotta/powder, stripped log ends, dry farmland, unlit furnace). All original Blocksmith art.
