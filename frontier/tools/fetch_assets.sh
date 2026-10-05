#!/bin/bash
# Downloads processed asset packs (release frontier-assets, built by .github/workflows/frontier-assets.yml).
# Usage: bash frontier/tools/fetch_assets.sh [ext|catalog|audio|animals]
#   ext (default)  CC0 textures/models into frontier/assets/ext/ (then also fetches audio, best effort)
#   catalog        catalogues/contact sheets into frontier/assets/catalog/
#   audio          game audio (SFX, ambience, score stems, voices, recordings + manifest) into frontier/assets/ext/audio/
#   animals        procedurally generated animals (horse.glb + gait metadata) into frontier/assets/ext/animals/
set -euo pipefail
REPO="${FRONTIER_REPO:-remingtonangus-lang/blocksmith}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
what="${1:-ext}"
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
if [ "$what" = "animals" ]; then
  rm -rf "$DIR/assets/ext/animals"          # the zip holds ext/animals/...
  unzip -q -o "$tmp/$what.zip" -d "$DIR/assets"
  echo "fetched animals into $DIR/assets/ext/animals"
else
  rm -rf "$DIR/assets/$what"
  unzip -q -o "$tmp/$what.zip" -d "$DIR/assets"
  echo "fetched $what into $DIR/assets/$what"
fi
if [ "$what" = "ext" ]; then
  fetch_audio || true
fi
rm -rf "$tmp"
