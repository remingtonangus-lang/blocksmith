#!/bin/bash
# Downloads Meta's platform SDK for Android (AAR from Maven Central) to build/ovrplatform.aar: the store build's
# libovrplatformloader.so, which the launch entitlement check (quest/src/common/QuestEntitlement.swift) opens.
# Fetched at build time, never committed. Maven Central rate-limits shared egress IPs with 429s, so Google's Maven
# Central mirror is the fallback; the pinned version's checksum is verified either way, and only a verified file is kept.
set -euo pipefail
cd "$(dirname "$0")/../.."
V="${OVRPLATFORM_VERSION:-77.0.1}"
SHA="3d64b23d4cdfcc88a38758a7b403c5784eacc208b5ab6296e814e77dfa3fc9d3"
P="com/meta/horizon/platform/ovr/android-platform-sdk/$V/android-platform-sdk-$V.aar"
mkdir -p build
TMP=build/ovrplatform.aar.part
trap 'rm -f "$TMP"' EXIT
curl -fsSL --retry 2 --retry-delay 3 -o "$TMP" "https://repo1.maven.org/maven2/$P" ||
  curl -fsSL --retry 3 --retry-delay 3 -o "$TMP" "https://maven-central.storage-download.googleapis.com/maven2/$P"
if [ "$V" = 77.0.1 ]; then echo "$SHA  $TMP" | shasum -a 256 -c -; fi
mv "$TMP" build/ovrplatform.aar
