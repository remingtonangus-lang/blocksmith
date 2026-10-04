#!/bin/bash
# Downloads the processed CC0 asset pack (release frontier-assets, built by .github/workflows/frontier-assets.yml)
# into frontier/assets/ext/. Usage: bash frontier/tools/fetch_assets.sh [catalog]
set -euo pipefail
REPO="${FRONTIER_REPO:-remingtonangus-lang/blocksmith}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
what="${1:-ext}"
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/$what.zip" "https://github.com/$REPO/releases/download/frontier-assets/$what.zip"
mkdir -p "$DIR/assets"
rm -rf "$DIR/assets/$what"
unzip -q -o "$tmp/$what.zip" -d "$DIR/assets"
rm -rf "$tmp"
echo "fetched $what into $DIR/assets/$what"
