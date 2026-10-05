#!/bin/bash
# Downloads the processed CC0 asset pack (release frontier-assets, built by .github/workflows/frontier-assets.yml)
# into frontier/assets/ext/. Usage: bash frontier/tools/fetch_assets.sh [catalog|animals]
#   animals: procedurally generated animals (horse.glb + gait metadata) into frontier/assets/ext/animals/
set -euo pipefail
REPO="${FRONTIER_REPO:-remingtonangus-lang/blocksmith}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
what="${1:-ext}"
tmp=$(mktemp -d)
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
rm -rf "$tmp"
