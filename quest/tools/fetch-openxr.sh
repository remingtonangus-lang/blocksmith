#!/bin/bash
# Downloads the Khronos OpenXR loader for Android (AAR from Maven Central) to build/openxr_loader.aar.
# Maven Central (Cloudflare) rate-limits shared egress IPs with 429s, so Google's official Maven Central mirror is the
# fallback; the pinned version's checksum is verified either way.
set -euo pipefail
cd "$(dirname "$0")/../.."
V="${OPENXR_VERSION:-1.1.63}"
SHA="622419d2f6741c3443a3beb4779af0764318edd01830de967f24c741ebcded73"
P="org/khronos/openxr/openxr_loader_for_android/$V/openxr_loader_for_android-$V.aar"
mkdir -p build
curl -fsSL --retry 2 --retry-delay 3 -o build/openxr_loader.aar "https://repo1.maven.org/maven2/$P" ||
  curl -fsSL --retry 3 --retry-delay 3 -o build/openxr_loader.aar "https://maven-central.storage-download.googleapis.com/maven2/$P"
if [ "$V" = 1.1.63 ]; then echo "$SHA  build/openxr_loader.aar" | sha256sum -c -; fi
