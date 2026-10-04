#!/bin/bash
# Downloads the processed asset packs (release frontier-assets, built by .github/workflows/frontier-assets.yml).
# Usage: bash frontier/tools/fetch_assets.sh [ext|catalog|characters|all]
#   ext        -> frontier/assets/ext/            (CC0 textures/models; keeps ext/characters)
#   catalog    -> frontier/assets/catalog/
#   characters -> frontier/assets/ext/characters/ (generated humans + animations.glb, see design/CHARACTERS.md)
set -euo pipefail
REPO="${FRONTIER_REPO:-remingtonangus-lang/blocksmith}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
what="${1:-ext}"
if [ "$what" = "all" ]; then
  for w in ext characters; do bash "$0" "$w"; done
  exit 0
fi
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/$what.zip" "https://github.com/$REPO/releases/download/frontier-assets/$what.zip"
mkdir -p "$DIR/assets"
case "$what" in
  characters)
    mkdir -p "$DIR/assets/ext"
    rm -rf "$DIR/assets/ext/characters"
    unzip -q -o "$tmp/$what.zip" -d "$DIR/assets/ext"
    dest="$DIR/assets/ext/characters";;
  ext)
    [ -d "$DIR/assets/ext/characters" ] && mv "$DIR/assets/ext/characters" "$tmp/characters_keep"
    rm -rf "$DIR/assets/ext"
    unzip -q -o "$tmp/$what.zip" -d "$DIR/assets"
    [ -d "$tmp/characters_keep" ] && mv "$tmp/characters_keep" "$DIR/assets/ext/characters"
    dest="$DIR/assets/ext";;
  *)
    rm -rf "$DIR/assets/$what"
    unzip -q -o "$tmp/$what.zip" -d "$DIR/assets"
    dest="$DIR/assets/$what";;
esac
rm -rf "$tmp"
echo "fetched $what into $dest"
