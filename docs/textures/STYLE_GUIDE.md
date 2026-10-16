# Blocksmith texture style guide (locked; every generated texture follows it)

Used verbatim by `tools/gemini_textures.py` in every prompt, together with the one approved reference image
`docs/textures/style_reference.png` (once approved; until then the first accepted generation becomes it).

## Look
- Stylised realism, hand-painted feel: crisp readable shapes, not photographic noise.
- One soft light from the top-left baked in as gentle relief; no cast shadows across the tile, no specular glare.
- Moderate saturation, natural earthy palette; colours sit close to the procedural set's means (the `mean` column in
  `tools/texture_prompts.json`), and the importer locks the mean colour afterwards.
- Detail sized for the block: features must read at 128 x 128 px (one block face). Rule of thumb: the main
  elements (stones, planks, bricks, clumps) number about 4-12 across the tile, never hundreds.

## Prompt rules (from the first Gemini samples, 2026-10-02)
1. Ask for block-scale features: "about 6-10 large stones across the tile", not just "cobblestone" (the samples had
   ~150 cobbles, a few pixels each at 128 px).
2. "Uniform density, no large light or dark patches, no vignette" (dark patches repeated as a grid in grass). The
   importer also divides out large-scale luminance before downsampling.
3. Style drift: this guide plus the same approved reference image in every prompt.
4. Gemini sometimes returns a 2x2 internal repeat: the importer detects it and crops one quadrant.
5. Square, straight-on, orthographic, flat face; seamless on all four edges; no text, borders or frames; one tile only.
6. Tinted textures (grass top, leaves): any green is fine, the importer converts to greyscale for biome tinting.
   Cutouts (leaves, plants): on a solid pure magenta (#FF00FF) background, which the importer keys out.

## Pipeline
`tools/gemini_textures.py` (generate, raw PNGs to build/texgen/raw) -> `tools/teximport.py` (square crop, repeat
check, luminance flattening, colour lock, wrap-aware downsample to 128, seam check and cross-fade, tint/overlay/
cutout modes) -> trial set in build/texgen/out -> side-by-side sheet against the procedural and CC0 baselines
(docs/textures/gemini_trial.png) and in-game snapshots (`--texdir build/texgen/out` vs `--procedural`) -> approved
files are copied to Resources/Textures (bundled; each replaces that texture's procedural material).
