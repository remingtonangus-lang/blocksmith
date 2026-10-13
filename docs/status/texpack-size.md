# texpack.bin size (AR6, 2026-10-13)

`Resources/texpack.bin` is the Quest's texture pack (`tools/texpack.py`: every PNG in Resources/Textures as 128 px
RGBA8, one zlib stream). Measured on claude/quest-port at 604a4fbc:

| | |
|---|---|
| layers | 1219 (535 opaque, 684 with alpha) |
| file (zlib) | 18.6 MB |
| unpacked RGBA8 | 79.9 MB (GPU memory before mips; about 107 MB with a full mip chain) |
| copies in git history | 17 blobs, 191 MB raw, 88 MB on disk after git's own compression |

## The repo
Every art change commits a fresh 13-19 MB blob that never goes away; 17 versions already cost 88 MB of the clone.
`texpack.py` is deterministic, so the pack could be built from the PNGs at Quest build time (the PNGs are in the repo
anyway: 18 MB) and dropped from git with a `.gitignore` line. That stops the growth; the history already there stays
unless it is rewritten (a force push all lanes would need to re-clone after, so not recommended).

## The Quest download and memory
| format | file | GPU memory (no mips) | notes |
|---|---:|---:|---|
| RGBA8 + zlib (today) | 18.6 MB | 80 MB | lossless |
| ASTC 4x4 (8 bpp) | ~20 MB | 20 MB | near lossless; the file barely changes, memory a quarter |
| ASTC 6x6 (3.56 bpp) | ~9 MB | 9 MB | the usual Quest choice for 128 px art; slight softening of fine detail |
| ASTC 8x8 (2 bpp) | ~5 MB | 5 MB | visible blockiness on cutouts and text-like detail |

ASTC files compress poorly with zlib (about 10 %), so the file is close to the GPU size. The 4x memory saving matters
more on an 8 GB headset than the download. Cutouts (leaves, torches, item sprites: 684 layers) need care: ASTC can
blur the alpha edge, so they would want 4x4 or an alpha threshold after decode.

Recommendation (Remington's call, as AR6 says): build the pack at Quest build time instead of committing it, and try
ASTC 6x6 for opaque layers with 4x4 for cutouts.
