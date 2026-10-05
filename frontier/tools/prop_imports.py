#!/usr/bin/env python3
"""Import settings for the Poly Haven prop textures (assets/ext/props/*/textures/*).

The props arrive without .import files, so a headless `godot --import` imports their 227 1k textures lossless and
without mipmaps: ~4 MB of RGBA8 each in video memory (~0.9 GB, unified memory on the M1 / Quest) and slow to load.
This writes .import files for VRAM-compressed textures with mipmaps, 512 px max (props are small on screen; the
building kit's own textures are packed separately by pack_textures.py), normal maps flagged as such. Existing uids
are kept so the imported glTF scenes keep resolving their textures.

Usage: python3 frontier/tools/prop_imports.py [props_dir]   (fetch_assets.sh runs it after unpacking ext)
Then `godot --headless --import` re-imports the changed textures.
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PROPS = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "assets", "ext", "props")
SIZE_LIMIT = 512

TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"
{uid}
[params]

compress/mode=2
compress/high_quality=false
compress/normal_map={normal}
mipmaps/generate=true
process/size_limit={limit}
detect_3d/compress_to=0
"""


def res_path(p: str) -> str:
    rel = os.path.relpath(os.path.abspath(p), os.path.abspath(ROOT)).replace(os.sep, "/")
    return "res://" + rel


def main() -> None:
    n = 0
    for dirpath, _dirs, files in os.walk(PROPS):
        for f in files:
            if not f.lower().endswith((".jpg", ".jpeg", ".png")):
                continue
            p = os.path.join(dirpath, f)
            imp = p + ".import"
            uid = ""
            if os.path.exists(imp):
                txt = open(imp).read()
                m = re.search(r'^uid="([^"]+)"', txt, re.M)
                if m:
                    uid = 'uid="%s"\n' % m.group(1)
            normal = 1 if ("_nor" in f or "normal" in f.lower()) else 0
            open(imp, "w").write(TEMPLATE.format(uid=uid, normal=normal, limit=SIZE_LIMIT))
            n += 1
    print("prop_imports: wrote %d texture imports (VRAM compressed, mipmaps, max %d px) under %s" % (n, SIZE_LIMIT, PROPS))


if __name__ == "__main__":
    main()
