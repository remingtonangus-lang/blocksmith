#!/bin/bash
# Downloads assets from the rolling release frontier-assets (built by .github/workflows/frontier-assets.yml).
# Usage: bash frontier/tools/fetch_assets.sh [ext|catalog|weapons]
#   ext      processed CC0 asset pack -> frontier/assets/ext/ (keeps an existing ext/weapons/)
#   catalog  asset catalogues + contact sheets -> frontier/assets/catalog/
#   weapons  generated firearms (tools/weapons/gun_gen.py) -> frontier/assets/ext/weapons/<id>.glb
set -euo pipefail
REPO="${FRONTIER_REPO:-remingtonangus-lang/blocksmith}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
what="${1:-ext}"
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/$what.zip" "https://github.com/$REPO/releases/download/frontier-assets/$what.zip"
mkdir -p "$DIR/assets"
if [ "$what" = "weapons" ]; then
  mkdir -p "$DIR/assets/ext"
  rm -rf "$DIR/assets/ext/weapons"
  unzip -q -o "$tmp/$what.zip" -d "$DIR/assets/ext"
  echo "fetched weapons into $DIR/assets/ext/weapons"
else
  if [ "$what" = "ext" ] && [ -d "$DIR/assets/ext/weapons" ]; then
    mv "$DIR/assets/ext/weapons" "$tmp/weapons_keep"
  fi
  rm -rf "$DIR/assets/$what"
  unzip -q -o "$tmp/$what.zip" -d "$DIR/assets"
  if [ -d "$tmp/weapons_keep" ]; then
    mv "$tmp/weapons_keep" "$DIR/assets/ext/weapons"
  fi
  echo "fetched $what into $DIR/assets/$what"
fi
rm -rf "$tmp"
