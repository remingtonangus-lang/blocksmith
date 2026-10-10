# Texture sharpness on the Quest (playtest 2026-10-10)

Remington, 09:24: "Everything looks good, it's just everything's blurry. It's not sharp ... I'm looking at the stone
and the chest ... It looks too compressed." Also 09:21-09:22: "Grass sucks", "ground's very obviously not detailed
enough", "the little bushes with the little yellow things on top are not detailed enough" (the firefly bush).
Kept as praised: trees, water, lily pads, bed, crafting table, gold block (no art change there).

## Cause (with evidence)
1. **The art reached the headset at half resolution.** The imported art is 128 px (stone, cobblestone, chest, planks,
   grass: all 128 px PNGs), but commit 25168558 (Oct 10, 02:45) packed it at 64 px (`tools/texpack.py --size 64`,
   a 2x2 box average) and made 64 px the Quest default (`quest.textureRes`, a saved 128 was even moved to 64). The
   "High" option could not bring it back: the pack itself held 64 px tiles, so `TexPack.image` only nearest-upscaled
   them. Every 0.95 build showed 64 px textures.
2. **At headset distance every texel is magnified.** The Quest 3 eye buffer is the runtime-recommended size
   (`resolutionScale` 1.0; about 1680 px wide per eye over a tangent span of about 2.2, so ~760 px per unit tangent,
   ~13 px per degree at the centre). A 1 m block at d metres covers ~760/d px: with 64 px textures one texel is
   12 px at 1 m, 6 px at 2 m, 3 px at 4 m. Mips play no part inside ~12 m; what you see is the 64 px tile blown up.
3. **Nearest magnification** (`magFilter = NEAREST`) drew those averaged 2x2 blocks as hard 6-12 px squares, which the
   lens/compositor resample then smears: low-detail blocks with soft stair-step edges, i.e. a heavily compressed JPEG.
   The same stair-steps crawl when the head moves.
4. **Distance**: box-filter mips plus anisotropy 4 made the ground a few metres out softer than the art needs.
Not the cause: there is no lossy compression on the Quest (RGBA8, no ASTC/ETC2; the pack is lossless; only the Mac
uses BC3), no LOD bias, no MSAA resolve (sample count 1), foveation off by default. The texture array is UNORM holding
sRGB values (filtering happens in gamma space): slightly darker mixed texels, not blur; left alone because every
shader's colour maths assumes it.

## Fix
- **128 px again** (`QuestSettings.textureRes` 128 by default; the 64 that the one-day default left in saved
  settings moves to 128 once, `quest.tex128`; an explicit Medium pick afterwards sticks) and **the pack at 128 px**:
  `tools/texpack.py` format v2 = zlib-packed body (57 MB of tiles -> 12.6 MB file, smaller than the old 13.9 MB
  64 px pack; v1 still loads; `Sources/TexPack.swift` unpacks with Apple's Compression on the Mac, zlib on the Quest).
  The unpacked pixels are released once the layers are painted or read from the cache (`TextureImport.release`).
- **Sharp-bilinear magnification** for every texture-array lookup on the Quest (`quest/shaders/common.glsl`
  `texSharp`/`sharpUV`, sampler `magFilter = LINEAR`): a texel's interior samples flat and only its edge blends, over
  about one screen pixel, so texels stay crisp without nearest's crawl. Once a texel is a pixel or smaller the uv is
  untouched (trilinear + anisotropic as before), and the moved uv never has more than one texel per pixel of
  derivative, so the hardware LOD stays at the top mip up close (no seams/sparkles at texel edges). Used by chunks
  (solid, cutout, water), ships (solid, cutout, translucent), held/dropped items (entity.frag: replaces the
  "texel-exact under 4 m" path), block cracks and the HUD (hud.frag has its own copy). Mobs are untextured.
- **Lanczos-2 mips** for opaque layers (`TextureGen.mipChain`, shared with the Mac; cutouts/translucent keep the
  alpha-weighted box with coverage preservation) and **anisotropy 8** (was 4).
- **Ground art**: new grass top (dense fine blades, no big tufts), new grass side (continuous fringe over the dirt
  block's own soil; the old side had stray grass patches mid-face), firefly bush as a painted 128 px leafy bush with
  fireflies (it was a procedural 16 px sprite). Sources and prompts in assets/CREDITS.md.

## Measurements
`tools/texsharp.py` renders, in numpy, exactly what the Quest samples (pack tile size, mip filter, sampler, aniso,
sharpUV) into a Quest-3-like eye buffer (760 px per unit tangent): walls at 1, 2, 4 m and the ground 4-12 m away, for
stone, cobblestone, chest front, oak planks and the grass top, against the 128 px art (4x4 supersampled).

| config | wall texel PSNR vs art | wall texel detail | wall edge pop (1 = art) | far ground PSNR | far ground detail (1 = ideal) |
|---|---|---|---|---|---|
| 0.95: 64 px, nearest, box mips, aniso 4 | 30.0 dB | 0.74 | 4.83 | 31.2 dB | 1.61 (aliasing) |
| 128 px, nearest, box, aniso 4 | lossless | 1.00 | 6.27 | 34.6 dB | 1.57 |
| 128 px, plain linear, Lanczos, aniso 8 | 38.2 dB | 0.45 (soft) | 1.04 | 39.6 dB | 1.27 |
| **now: 128 px, sharp-bilinear, Lanczos, aniso 8** | **44.8 dB** | **0.78** | **2.46** | **39.5 dB** | **1.27** |

Texel detail = Laplacian variance of the render averaged back onto the art's texel grid / the art's own (the
Laplacian variance of the raw screen image rewards nearest's stair-steps, so it is not used up close). Edge pop =
99.5th-percentile frame-to-frame change under a quarter-pixel head drift: the new filter halves nearest's crawl
while keeping 78% of the texel detail (plain linear keeps 45%). Per texture rows: `python3 tools/texsharp.py`.

Ground noise (`tools/texsharp.py --noise old.png,new.png`, scorecard "grass calm"): grass top close detail
0.077 -> 0.092 (+19%, what reads at 1-2 m), far pattern 0.090 -> 0.051 (-43%, the tuft grid that repeated every block
at 8+ m). Mac flicker check on the new grass + bushes: 4 ppm (`tools/flicker.py`, ok < 20).

Evidence (docs/status/evidence/2026-10-10/): `texsharp-quest-model.jpg` (art | 0.95 | 128 nearest | 128 linear |
now, per texture), `tex-gallery-64-vs-128.jpg` (Mac render, 7 m), `grass-bush-before-after.jpg` (Mac, plains:
64 px + old art above, 128 px + new art below).

## Cost
- GPU memory: 1712 layers x 128 px RGBA8 + mips = 146 MB (64 px: 37 MB). The headset ran 128 px until Oct 10
  (Oct 9 logs: resident 341-628 MB against the 3 GB gate). The first launch after an update paints 4x the texels
  (then cached, as before); the pack file is 12.6 MB.
- Shader: `sharpUV` is ~14 ALU ops + `textureSize` per textured fragment, bilinear magnification is full rate on
  Adreno like nearest, and anisotropy 8 only adds taps where the footprint is stretched more than 4:1 (ground far
  out at a slant). Estimated well under 0.2 ms at 72 Hz; this needs the device to confirm.

## Device-only (not measurable on the Mac)
- The real swapchain size and field of view (`xr: swapchain WxH (recommended ...)` log line) behind the 760 px figure.
- Lens + compositor resampling, and how much sharper it reads in the headset (Remington's eyes are the judge).
- Frame time with the new sampler/shader on the six bench routes (`perf:` lines; p99 <= 13.9 ms at 72 Hz) and the
  memory peak during the first launch's painting.
- Remaining softness sources not changed here: the HUD panel (1024 px over ~53 degrees, ~19 panel px per degree
  against ~13 eye px, minified without mips: slight aliasing of small text, not blur) and the eye-buffer scale
  (`resolutionScale` 1.0; raising it costs fill rate, owned by the performance work).
- Pink fringes on some 64 px plant sprites (dandelion stem) from the p01 sheet's magenta key: unchanged.
