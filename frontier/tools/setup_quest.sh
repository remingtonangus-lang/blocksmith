#!/bin/bash
# CI-only preparation of the checkout for the Quest (Android/OpenXR) export: Godot >= 4.6 bundles the Khronos
# OpenXR loader, so a plain (non-gradle) export works; this just switches OpenXR on and the mobile renderer.
set -euo pipefail
cd "$(dirname "$0")/.."
sed -i 's/^openxr\/enabled=false/openxr\/enabled=true/' project.godot
grep -n "openxr/enabled" project.godot
# raw source folders are not needed once packed (keeps the APK small)
rm -rf assets/ext/terrain assets/ext/build assets/ext/cloth assets/catalog
