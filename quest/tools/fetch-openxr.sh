#!/bin/bash
# Downloads the Khronos OpenXR loader for Android (AAR from Maven Central) to build/openxr_loader.aar.
set -euo pipefail
cd "$(dirname "$0")/../.."
V="${OPENXR_VERSION:-1.1.63}"
SHA="622419d2f6741c3443a3beb4779af0764318edd01830de967f24c741ebcded73"
mkdir -p build
curl -fsSL -o build/openxr_loader.aar "https://repo1.maven.org/maven2/org/khronos/openxr/openxr_loader_for_android/$V/openxr_loader_for_android-$V.aar"
if [ "$V" = 1.1.63 ]; then echo "$SHA  build/openxr_loader.aar" | sha256sum -c -; fi
