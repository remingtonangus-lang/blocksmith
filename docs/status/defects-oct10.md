# Visual defect hunt, Oct 10 (store quality: Defects, docs/STORE_QUALITY.md section 4)

Checked after the 128 px art / sharp-bilinear / Lanczos-mip / aniso 8 change (docs/status/texture-sharpness.md).
Mac renders through the snapshot harness (release build of eef484c4 + this branch), Quest shaders compiled with the NDK
glslc (`quest/tools/shaders.py`) and a full `tools/quest-local.sh --no-run --fast` APK build.

## Found and fixed

### 1. Thin dark lines across the plains ground (Mac snapshots): not a texture seam
`./snap.sh t --seed 12345 --find plains --time 0.3 --pitch -30` shows long thin dark lines converging downwards.
They are the **crosshair target's selection outline**: the harness spawns the camera 0.6 m from a short grass plant on
the step ahead (`target: short_grass at -88 135 103`), whose box reaches above eye level, so only its vertical edges are
on screen. Same view at `--pitch 0 --up 3` (no target): no lines. The ground itself has no seams at full resolution
(crop of `--yaw 120 --pitch -30`), as expected: the Mac magnifies NEAREST (`Shaders.swift` texSampler), and the
mips wrap like the tiles do (Lanczos/box both `% n`).
- Fix: none to the outline (it is correct game feedback, the same in the Quest renderer). The harness now prints a
  `target: <block> at x y z, boxes ...` line so a shot's outline is identified at a glance (Sources/main.swift).
- Evidence: `docs/status/evidence/2026-10-10/defects-plains-outline-lines.jpg`.

### 1b. Quest: face edges blended in the opposite edge of the art (same family, found while checking lead 1)
The Quest's sharp-bilinear `sharpUV` (common.glsl, hud.frag) puts the blend at every texel seam, including the seam at
a block face's edge (uv 0 / 1). The sampler is REPEAT, so pixels whose centre lies within half a pixel of a face edge
mixed in up to 50 % of the art's *opposite* edge: a 1-px line along the edges of every non-tiling face that crawls as
the head moves. 65 of the 376 opaque textures have opposite edges more than 20 levels apart on average, 31 more than
40 (diamond block top/bottom 105, piston side 98, crafting table front 91, observer, furnace, jukebox, iron/gold/copper
blocks 74-82); the HUD's block icons had the same wrap.
- Fix: at a seam on a tile boundary, magnified texels sample their own texel (nearest at the face edge, as the Mac
  does everywhere); interior seams keep the sharp-bilinear blend, minified uv is untouched. Both copies
  (`quest/shaders/common.glsl`, `quest/shaders/hud.frag`). All 24 shader modules compile; APK builds.
- Not measurable on the Mac (it doesn't use sharpUV); needs a headset look at a crafting table / diamond block edge.

### 2. Pink fringes and stems on plant sprites (and item icons)
Root cause is in the sprite art, not the texture pipeline: `tools/iconslice.py` keyed the Gemini sheets off magenta but
removed only **half** the magenta spill from texels it kept opaque (`k = min(m, m*(1-al) + m*0.5)` with `al = 1` for
any texel under 50 % key mix). Thin stems, leaf rims and the background gaps between needles are mostly such mixed
texels, so they shipped pink: poppy and tulip stems `(163, 97, 122)`, spruce/oak saplings with magenta specks, dead bush
fringe `(226, 137, 173)`, seagrass, apple rim. texpack.py / TextureImport / mipChain were checked and are fine
(premultiplied box downscale, transparent texels zeroed, cutout colour bleed, coverage-preserving mips).
- Fix: texels within 3 px (sheet resolution) of background lose all their magenta (min(r, b) brought down to g);
  texels deeper inside keep their colour, so allium, pink tulip, cherry, amethyst and chorus stay purple/pink.
  Regenerated all 29 plant sprites and 292 icons (both sets were byte-identical reproductions of the shipped PNGs with
  the old code, so nothing hand-edited was lost) and `Resources/texpack.bin`.
- Measured (opaque texels with min(r, b) - g > 20): icons 21694 -> 7920 (the rest are genuinely purple items);
  dead bush 149 -> 3, spruce sapling 76 -> 2, cornflower 87 -> 16, azure bluet 65 -> 1, poppy 11 -> 0.
- Evidence: `docs/status/evidence/2026-10-10/defects-sprite-despill.jpg` (old row above, new below).

## Checked, nothing wrong
- Golden shots (`tools/golden.sh`, 17 shots, all render): flicker spawn 0, forest 2, cave_torch 0, the_deep 0,
  dusk 0, night 0 ppm. ash_vault 22 ppm "warn" is not geometry: three renders of the *same* camera differ by 0-18 ppm
  (a moving speck at the left edge and ember particles), i.e. animation between frames, not z-fighting.
- Golden look-over (downscaled): no seams, light leaks, T-poses or floating geometry. Night's "leaning" trunk is
  perspective at pitch +10; the horse shot's 1-block grass pillars are the `--stage` set.
- Playtest repros (docs/playtests/2026-10-10/voice-notes.md, notes 09:21:33-09:24:16, 8 views): the swamp view's large
  dark arc is the canopy's shadow (moves with --time 0.3 / 0.4); the spruce views put the Mac camera inside the leaves
  (Quest head height differs), so they say nothing about defects.

## Left
- Headset check of 1b (block edges at arm's length) and of the sprites on the Quest.
- `tools/texsharp.py` models interior texels only; it doesn't model the face-edge case of 1b.
- ash_vault's per-frame particle difference makes the flicker check noisy there; seeding particles in the harness
  would make it exact.
