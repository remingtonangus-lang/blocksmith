#!/bin/bash
# Cloud-session setup for Frontier work: Godot 4.7.1 (Linux), software Vulkan (lavapipe) for offscreen screenshots,
# Python packages for worldgen/assets, and the generated world data. Idempotent; safe to rerun.
set -uo pipefail
V=4.7.1
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if ! command -v godot >/dev/null || ! godot --version 2>/dev/null | grep -q "^$V"; then
  mkdir -p /opt/godot && cd /opt/godot
  curl -sSL -o g.zip "https://github.com/godotengine/godot/releases/download/${V}-stable/Godot_v${V}-stable_linux.x86_64.zip" && unzip -o -q g.zip
  ln -sf /opt/godot/Godot_v${V}-stable_linux.x86_64 /usr/local/bin/godot
fi
dpkg -s mesa-vulkan-drivers >/dev/null 2>&1 || apt-get install -y -q mesa-vulkan-drivers >/dev/null 2>&1 || true
python3 -c "import numpy, scipy, PIL, skimage" 2>/dev/null || pip install -q numpy scipy pillow scikit-image >/dev/null 2>&1 || true
cd "$ROOT/frontier"
[ -f data/world/height.r16 ] || python3 tools/worldgen.py >/dev/null 2>&1 || true
[ -d assets/ext ] || bash tools/fetch_assets.sh >/dev/null 2>&1 || true
echo "frontier session ready: $(godot --version 2>/dev/null)"
