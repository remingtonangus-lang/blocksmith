#!/bin/bash
# Builds build/Blocksmith.app with the Command Line Tools (no Xcode needed).
#   ./build.sh            optimized build
#   ./build.sh debug      debug build (faster compile, asserts on)
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:-release}"
APP=build/Blocksmith.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [ "$MODE" = "debug" ]; then OPT="-Onone -g"; else OPT="-Ounchecked -wmo"; fi
xcrun swiftc $OPT -swift-version 5 -target arm64-apple-macos13.0 -module-name Blocksmith \
  -framework Metal -framework MetalKit -framework AppKit -framework GameController \
  Sources/*.swift -o "$APP/Contents/MacOS/Blocksmith"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP ($MODE)"
