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

## Item and HUD icons (Resources/Textures/item_*.png)
Same art direction (style 3, stylised realism) and source: Google Gemini image generation on gemini.google.com
(Remington's Google AI Pro account), 2026-10-09/10. Sheets: assets/gemini/icons/i01-i19 (4x4 grids, i19 2x2).
- Prompt pattern: "a sheet of 16 item icons for a voxel survival game, STYLISED REALISM style (real-world objects,
  simplified, subtle surface detail, natural muted colours, soft hand-painted look, gentle top-left light, NOT pixel
  art, NOT cartoon). Exact 4x4 grid of equal square cells, each icon centred filling about 80%, three-quarter view, on a
  perfectly flat solid magenta background (#FF00FF), no text, no labels", then one object description per cell. The
  cell -> item map is docs/textures/icons.json.
- Processing: tools/iconslice.py (magenta key, de-spill, fit to 64 px) and tools/iconderive.py (colour families from
  one painted member: dyes, bundles, banners, discs, templates, banner patterns by the item's own colour; boats by
  plank colour and spears by material block colour; suspicious stews and pottery sherds share one icon). All original
  Blocksmith art; guns and gear are generic original designs.
