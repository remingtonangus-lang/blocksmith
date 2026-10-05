#!/bin/bash
# Fetches the (pinned) source data of the character pipeline into $FRONTIER_CHAR_SRC (default frontier/build/charsrc):
#   mpfb2/           MPFB2 (GPL-3.0 code, run as a tool only; its bundled CC0 assets: base mesh, targets, rigs)
#   extra-targets/   CC0 ARKit face units + visemes (makehumancommunity/extra-targets)
#   system_assets/   makehuman_system_assets_cc0.zip (CC0 skins, eyes, brows, lashes, teeth, tongue, hair, clothes)
#   cmu-mocap/       CMU mocap, cgspeed BVH conversion (only the clips listed in retarget.py; sparse checkout)
# Already-present directories are kept. Pre-populated copies can be pointed to with FRONTIER_MPFB, FRONTIER_MH_ASSETS,
# FRONTIER_MH_EXTRA, FRONTIER_CMU instead (see mhenv.py). Needs git, curl, unzip, python3.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FRONTIER="$(cd "$HERE/../.." && pwd)"
SRC="${FRONTIER_CHAR_SRC:-$FRONTIER/build/charsrc}"
MPFB_SHA=d0a32e57a7f915cb2f2b95410e2117648c7bbb7e
EXTRA_SHA=7eaba3453134385bb5ea9811ef0b33b85b4b556d
CMU_SHA=09a07f54f3bbb58797325f009282d0b2048a2871
mkdir -p "$SRC"

pinned_clone() {  # url dir sha [sparse-list-file]
  local url="$1" dir="$2" sha="$3" sparse="${4:-}"
  if [ -d "$dir/.git" ]; then echo "keep $dir"; return; fi
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$url"
  if [ -n "$sparse" ]; then
    git -C "$dir" config core.sparseCheckout true
    git -C "$dir" sparse-checkout set --no-cone --stdin < "$sparse"
    GIT_LFS_SKIP_SMUDGE=1 git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$sha"
  else
    GIT_LFS_SKIP_SMUDGE=1 git -C "$dir" fetch -q --depth 1 origin "$sha"
  fi
  GIT_LFS_SKIP_SMUDGE=1 git -C "$dir" checkout -q FETCH_HEAD
  echo "fetched $dir @ $sha"
}

[ -n "${FRONTIER_MPFB:-}" ] || pinned_clone https://github.com/makehumancommunity/mpfb2 "$SRC/mpfb2" "$MPFB_SHA"
[ -n "${FRONTIER_MH_EXTRA:-}" ] || pinned_clone https://github.com/makehumancommunity/extra-targets "$SRC/extra-targets" "$EXTRA_SHA"

if [ -z "${FRONTIER_CMU:-}" ]; then
  list="$SRC/cmu_files.txt"
  python3 - "$HERE/retarget.py" > "$list" <<'EOF'
import re, sys
src = open(sys.argv[1]).read()
files = sorted(set(re.findall(r'\(\s*"[^"]+",\s*"(\d+_\d+)"', src)))
for f in files:
    print("data/%03d/%s.bvh" % (int(f.split("_")[0]), f))
print("READMEFIRST.txt")
EOF
  pinned_clone https://github.com/una-dinosauria/cmu-mocap "$SRC/cmu-mocap" "$CMU_SHA" "$list"
fi

if [ -z "${FRONTIER_MH_ASSETS:-}" ] && [ ! -d "$SRC/system_assets/skins" ]; then
  tmp=$(mktemp -d)
  ok=""
  for base in https://mirror1.makehuman.net https://files2.makehumancommunity.org; do
    if curl -fsSL --retry 3 -o "$tmp/sa.zip" "$base/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip"; then
      ok="$base"; break
    fi
  done
  [ -n "$ok" ] || { echo "cannot download makehuman_system_assets_cc0.zip"; exit 1; }
  unzip -q "$tmp/sa.zip" -d "$tmp/x"
  root=$(dirname "$(find "$tmp/x" -type d -name skins | head -1)")
  mkdir -p "$SRC/system_assets"
  cp -r "$root"/. "$SRC/system_assets/"
  rm -rf "$tmp"
  echo "fetched system assets from $ok"
  python3 - "$SRC/system_assets" <<'EOF'
import json, glob, sys
lic = set()
for p in glob.glob(sys.argv[1] + "/packs/*.json"):
    for v in json.load(open(p)).values():
        lic.add(v.get("license"))
print("system asset licences:", lic)
if lic - {"CC0"}:
    sys.exit("non-CC0 asset in the system pack: %s" % lic)
EOF
fi
echo "sources ready in $SRC"
