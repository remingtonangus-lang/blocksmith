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

## Block textures, batch 2 (2026-10-10)
Same style and source (Gemini on gemini.google.com, Remington's Google AI Pro account).
- assets/gemini/sheets/s14_world2.png: 4x4 tileable swatches (emberslate, moss, podzol, mycelium, rooted dirt, packed
  mud, mud bricks, ice, packed ice, snow, chiseled/cracked stone bricks, cut sandstone, basalt, tuff bricks), sliced by
  tools/sheetslice.py.
- assets/gemini/sheets/s15_metal.jpg: limestone, panels, paving, riveted/bolted plate, hull plating, vents, charred
  plate, concrete, hazard stripes, grating, aged iron, teak deck. Sliced to assets/gemini/tiles and recoloured by
  tools/texderive.py (TILES) into the original Blocksmith blocks' own colours (capital/frigate/warship/Ash/ship blocks).
- assets/gemini/plants/p01_plants.png: 16 plant sprites on magenta (grass, fern, flowers, saplings, cane, kelp,
  seagrass), sliced by tools/iconslice.py with docs/textures/plants.json (bottom-anchored hard cutouts; grass and fern
  greyscale for the biome tint).
- assets/gemini/sheets/s16_organic.jpg (8 of 16 cells used: honeycomb, sponge, crying obsidian, sculk, wart, shroomlight,
  sea lantern, barrel side; the rest were objects, not tiles).
- texderive.py RELATIVES/copper/stained glass: nether and pale woods, copper weathering stages and others carry an
  imported base's detail in the procedural colour. All original Blocksmith art.

## Block textures, batch 4 (2026-10-10)
Same style, source and prompt pattern (Gemini Pro on gemini.google.com, Remington's Google AI Pro account; ask for a
"SQUARE 1:1 image" or Gemini Pro returns a 16:9 sheet with merged cells).
- assets/gemini/sheets/s17_building3.jpg: cut copper, polished deepslate/tuff, quartz and purpur pillars, red nether
  bricks, dark prismarine, chiseled sandstone, red sandstone top, bamboo, mushroom stem/caps, bone, blue ice, melon.
- assets/gemini/sheets/s18_workshop.jpg: TNT, smithing/fletching/cartography table and loom sides, note block, jukebox,
  piston, observer face, dispenser, target, beehive, bee nest, lamp (unlit lamp derived darker), honey.
- assets/gemini/sheets/s19_tops.jpg: the matching tops/fronts and two glazed terracotta patterns.
  Cell maps in docs/textures/sheets.json; sliced by tools/sheetslice.py. All original Blocksmith art.
- assets/gemini/plants/p02_plants.jpg: tulips, blue orchid, acacia/cherry/dark oak/jungle saplings, mushrooms, ladder
  (tools/iconslice.py with docs/textures/plants.json).
- assets/gemini/sheets/s20_ores4.jpg (re-roll after the independent style review): natural coal, emerald and deepslate
  lapis/emerald/coal grains composited onto the shared stone, and all eight plank woods. The first s20 attempt came back
  as pixel art and was discarded. Emberslate muted toward dark stone with faint ember cracks.

## Block textures, final fill (2026-10-10)
No new sheets: tools/texderive.py carries the imported detail to 41 more layers (weathered/oxidized copper, coral
blocks from sponge, froglights from shroomlight, nether stem and stripped log ends, resin and chiseled tuff bricks,
reinforced deepslate, slime, bamboo planks/mosaic, dropper fronts, smoker/blast furnace/target tops, sideways stripped
stems). What stays procedural is listed in docs/status/art-style-remaining.md.
