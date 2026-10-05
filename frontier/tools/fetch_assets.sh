#!/bin/bash
# Downloads processed asset packs (release frontier-assets, built by .github/workflows/frontier-assets.yml).
# Usage: bash frontier/tools/fetch_assets.sh [ext|catalog|audio|animals]
#   ext (default)  CC0 textures/models into frontier/assets/ext/ (then also fetches audio, best effort)
#   catalog        catalogues/contact sheets into frontier/assets/catalog/
#   audio          game audio (SFX, ambience, score stems, voices, recordings + manifest) into frontier/assets/ext/audio/
#   animals        procedurally generated animals (horse.glb + gait metadata) into frontier/assets/ext/animals/
#   characters     generated humans + animations.glb into frontier/assets/ext/characters/ (design/CHARACTERS.md)
set -euo pipefail
REPO="${FRONTIER_REPO:-remingtonangus-lang/blocksmith}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
what="${1:-ext}"
if [ "$what" = "all" ]; then
  for w in ext characters; do bash "$0" "$w"; done
  exit 0
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fetch_audio() {
  if curl -fsSL -o "$tmp/audio.zip" "https://github.com/$REPO/releases/download/frontier-assets/audio.zip"; then
    mkdir -p "$DIR/assets/ext"
    rm -rf "$DIR/assets/ext/audio"
    unzip -q -o "$tmp/audio.zip" -d "$DIR/assets/ext"
    echo "fetched audio into $DIR/assets/ext/audio"
  else
    echo "audio.zip not published yet (run the frontier-assets workflow with mode=audio); the game runs silent"
    return 1
  fi
}

if [ "$what" = "audio" ]; then
  fetch_audio
  exit $?
fi
curl -fsSL -o "$tmp/$what.zip" "https://github.com/$REPO/releases/download/frontier-assets/$what.zip"
mkdir -p "$DIR/assets"
case "$what" in
  animals)
    rm -rf "$DIR/assets/ext/animals"          # the zip holds ext/animals/...
    unzip -q -o "$tmp/$what.zip" -d "$DIR/assets"
    dest="$DIR/assets/ext/animals";;
  characters)
    mkdir -p "$DIR/assets/ext"
    rm -rf "$DIR/assets/ext/characters"       # the zip holds characters/...
    unzip -q -o "$tmp/$what.zip" -d "$DIR/assets/ext"
    dest="$DIR/assets/ext/characters";;
  ext)
    # keep the packs fetched separately (audio, animals, characters) across an ext refresh
    mkdir -p "$tmp/keep"
    for k in audio animals characters; do if [ -d "$DIR/assets/ext/$k" ]; then mv "$DIR/assets/ext/$k" "$tmp/keep/$k"; fi; done
    rm -rf "$DIR/assets/ext"
    unzip -q -o "$tmp/$what.zip" -d "$DIR/assets"
    for k in audio animals characters; do if [ -d "$tmp/keep/$k" ]; then mv "$tmp/keep/$k" "$DIR/assets/ext/$k"; fi; done
    dest="$DIR/assets/ext";;
  *)
    rm -rf "$DIR/assets/$what"
    unzip -q -o "$tmp/$what.zip" -d "$DIR/assets"
    dest="$DIR/assets/$what";;
esac
echo "fetched $what into $dest"
if [ "$what" = "ext" ] && [ ! -d "$DIR/assets/ext/audio" ]; then
  fetch_audio || true
fi
