#!/bin/bash
# Sets up a cloud/Linux session (Ubuntu 24.04, x86_64) to build the Quest APK and run the Quest host checks locally,
# the same way .github/workflows/quest.yml does, with no GitHub Actions round-trip.
#
#   tools/cloud-setup.sh                 install everything (idempotent; reruns skip what is already there)
#   tools/cloud-setup.sh host            install only what the host checks need (Swift + apt; no Android downloads)
#   tools/cloud-setup.sh check           host checks: quest/tools/linux-check.sh build + questcheck on lavapipe
#   tools/cloud-setup.sh apk [OUT.apk]   build the signed debug APK (default build/quest-out/blocksmith-quest.apk)
#   tools/cloud-setup.sh all             install + check + apk, with timings
#   source <(tools/cloud-setup.sh env)   export PATH / NDK / ANDROID_HOME etc. into your shell
#
# Tools go under $QUEST_TOOLS (default ~/quest-tools). Hosts the downloads use:
#   host checks: archive.ubuntu.com (apt: Vulkan, lavapipe, glslang, OpenXR headers) and the Swift 6.4.0 toolchain from
#                download.swift.org, or, when that host is blocked, the official library/swift:6.4.0-noble image's
#                toolchain layer from Docker Hub (auth.docker.io, registry-1.docker.io + its blob CDN).
#   APK:         download.swift.org (Swift SDK for Android bundle), dl.google.com (NDK r30, Android cmdline-tools,
#                build-tools, platform), repo1.maven.org or Google's Maven Central mirror (OpenXR loader AAR).
#                Also a JDK 17+ on PATH (sdkmanager, apksigner).
# Pinned versions match quest.yml; bump them there and here together.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

T="${QUEST_TOOLS:-$HOME/quest-tools}"
SWIFT_VERSION=6.4.0
SWIFT_URL="https://download.swift.org/swift-6.4.0-release/ubuntu2404/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE-ubuntu24.04.tar.gz"
SWIFT_SDK=swift-6.4.0-RELEASE_android
SWIFT_SDK_URL="https://download.swift.org/swift-6.4.0-release/android-sdk/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE_android.artifactbundle.tar.gz"
SWIFT_SDK_SHA=21fb555122a3d801ad943d48df7ebffdd8824de61c25c180bb792d3edaee0b43
NDK_URL="https://dl.google.com/android/repository/android-ndk-r30-Linux.zip"
CMDLINE_URL="https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip"
BUILD_TOOLS="${QUEST_BUILD_TOOLS:-35.0.0}"
PLATFORM="${QUEST_PLATFORM:-android-35}"

SWIFT_HOME="$T/swift"
NDK_HOME="$T/ndk/android-ndk-r30"
ANDROID_SDK="$T/android-sdk"

env_lines() {
  echo "export PATH=\"$SWIFT_HOME/usr/bin:\$PATH\""
  for v in ANDROID_NDK_HOME ANDROID_NDK_ROOT ANDROID_NDK ANDROID_NDK_LATEST_HOME; do echo "export $v=\"$NDK_HOME\""; done
  echo "export ANDROID_HOME=\"$ANDROID_SDK\" ANDROID_SDK_ROOT=\"$ANDROID_SDK\""
  echo "export SWIFT_SDK=\"$SWIFT_SDK\""
  echo "export OPENXR_AAR=\"$ROOT/build/openxr_loader.aar\""
  echo "export OPENXR_INCLUDE=\"$ROOT/build/openxr/prefab/modules/headers/include\""
  echo "export GLSLC=\"\$(ls \"$NDK_HOME\"/shader-tools/*/glslc 2>/dev/null | sed -n 1p)\""
}
load_env() { eval "$(env_lines)"; }

# Prints "label: Ns" lines into $TIMES so `all` can report where the time went.
TIMES="${TIMES:-$ROOT/build/cloud-setup-times.txt}"
step() {  # step LABEL CMD...
  local label=$1; shift; local t0=$SECONDS
  echo "== $label"
  "$@"
  local dt=$((SECONDS - t0)); echo "== $label: ${dt}s"; mkdir -p "$(dirname "$TIMES")"; echo "$label: ${dt}s" >> "$TIMES"
}

fetch() {  # fetch URL OUT: a clear message (naming the host) when the session's network policy blocks it
  if ! curl -fSL --retry 3 --retry-delay 2 -o "$2" "$1"; then
    echo "cloud-setup.sh: could not download $1"
    echo "  a 403 means the session's network policy blocks host $(echo "$1" | sed -E 's|https?://([^/]+)/.*|\1|'): allow it in the cloud environment's Network access"
    exit 1
  fi
}

SUDO=""; [ "$(id -u)" = 0 ] || SUDO=sudo

install_apt() {
  local pkgs="libvulkan-dev mesa-vulkan-drivers zlib1g-dev libopenxr-dev glslang-tools unzip zip python3 curl rsync"
  local missing=""
  for p in $pkgs; do dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"; done
  [ -z "$missing" ] && { echo "apt packages present"; return; }
  $SUDO apt-get update -q
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends $missing
}

install_swift() {
  if [ -f "$SWIFT_HOME/.complete" ]; then "$SWIFT_HOME/usr/bin/swift" --version | head -1; return; fi
  rm -rf "$SWIFT_HOME"; mkdir -p "$SWIFT_HOME" "$T/dl"
  if curl -fsSL --retry 2 -o "$T/dl/swift.tar.gz" "$SWIFT_URL"; then
    tar -xzf "$T/dl/swift.tar.gz" -C "$SWIFT_HOME" --strip-components=1
    rm -f "$T/dl/swift.tar.gz"
  else
    echo "download.swift.org unreachable: taking the toolchain from Docker Hub's official swift:$SWIFT_VERSION-noble image"
    swift_from_docker_hub
  fi
  touch "$SWIFT_HOME/.complete"      # marks a finished extraction; an interrupted one is redone
  "$SWIFT_HOME/usr/bin/swift" --version | head -1
}

# The official image's largest layer is the toolchain (usr/bin/swift*, usr/lib/swift ...), the same release build as
# the tarball. No docker daemon needed: the registry API hands out the layer as a plain tar.gz.
swift_from_docker_hub() {
  local repo=library/swift tag="$SWIFT_VERSION-noble" reg=https://registry-1.docker.io/v2/library/swift tok idx dig man layer
  tok=$(curl -fsS "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$repo:pull" |
        python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')
  idx=$(curl -fsS -H "Authorization: Bearer $tok" \
        -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json" "$reg/manifests/$tag")
  dig=$(echo "$idx" | python3 -c 'import json,sys
d = json.load(sys.stdin)
print(next(m["digest"] for m in d["manifests"] if m["platform"]["architecture"] == "amd64" and m["platform"]["os"] == "linux"))')
  man=$(curl -fsS -H "Authorization: Bearer $tok" \
        -H "Accept: application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json" "$reg/manifests/$dig")
  layer=$(echo "$man" | python3 -c 'import json,sys; print(max(json.load(sys.stdin)["layers"], key=lambda l: l["size"])["digest"])')
  curl -fsSL --retry 3 -H "Authorization: Bearer $tok" "$reg/blobs/$layer" -o "$T/dl/swift-layer.tar.gz"
  echo "${layer#sha256:}  $T/dl/swift-layer.tar.gz" | sha256sum -c - >/dev/null
  tar -xzf "$T/dl/swift-layer.tar.gz" -C "$SWIFT_HOME" usr
  rm -f "$T/dl/swift-layer.tar.gz"
  [ -x "$SWIFT_HOME/usr/bin/swiftc" ] || { echo "cloud-setup.sh: the Docker Hub layer had no usr/bin/swiftc"; exit 1; }
}

install_ndk() {
  if [ -f "$NDK_HOME/.complete" ]; then echo "NDK r30 present"; return; fi
  rm -rf "$NDK_HOME"; mkdir -p "$T/ndk" "$T/dl"
  fetch "$NDK_URL" "$T/dl/ndk.zip"
  unzip -q -o "$T/dl/ndk.zip" -d "$T/ndk"
  rm -f "$T/dl/ndk.zip"; touch "$NDK_HOME/.complete"
}

install_android_sdk() {
  # build-apk.sh needs aapt2, zipalign and apksigner (build-tools) and a platform android.jar. The GitHub runner image
  # ships these; a cloud session gets them from the Android cmdline-tools' sdkmanager.
  if ls "$ANDROID_SDK"/build-tools/*/aapt2 >/dev/null 2>&1 && ls "$ANDROID_SDK"/platforms/*/android.jar >/dev/null 2>&1; then
    echo "Android build-tools + platform present"; return
  fi
  command -v java >/dev/null || { echo "cloud-setup.sh: sdkmanager and apksigner need a JDK (java) on PATH"; exit 1; }
  mkdir -p "$ANDROID_SDK/cmdline-tools" "$T/dl"
  if [ ! -x "$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
    fetch "$CMDLINE_URL" "$T/dl/cmdline.zip"
    rm -rf "$ANDROID_SDK/cmdline-tools/latest" "$ANDROID_SDK/cmdline-tools/cmdline-tools"
    unzip -q -o "$T/dl/cmdline.zip" -d "$ANDROID_SDK/cmdline-tools"
    mv "$ANDROID_SDK/cmdline-tools/cmdline-tools" "$ANDROID_SDK/cmdline-tools/latest"
    rm -f "$T/dl/cmdline.zip"
  fi
  local sm="$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager"
  yes 2>/dev/null | "$sm" --sdk_root="$ANDROID_SDK" --licenses >/dev/null || true   # yes gets SIGPIPE once licences are accepted
  "$sm" --sdk_root="$ANDROID_SDK" "build-tools;$BUILD_TOOLS" "platforms;$PLATFORM" > "$T/sdkmanager.log" 2>&1 ||
    { tail -20 "$T/sdkmanager.log"; echo "cloud-setup.sh: sdkmanager failed ($T/sdkmanager.log)"; exit 1; }
  ls "$ANDROID_SDK"/build-tools/*/aapt2 "$ANDROID_SDK"/platforms/*/android.jar >/dev/null
}

install_swift_sdk() {
  load_env
  if ! swift sdk list 2>/dev/null | grep -q "$SWIFT_SDK"; then
    mkdir -p "$T/dl"
    fetch "$SWIFT_SDK_URL" "$T/dl/android-sdk.artifactbundle.tar.gz"
    # SwiftPM checks --checksum only for URLs, not local files, so verify the pin here.
    echo "$SWIFT_SDK_SHA  $T/dl/android-sdk.artifactbundle.tar.gz" | sha256sum -c -
    swift sdk install "$T/dl/android-sdk.artifactbundle.tar.gz"
    rm -f "$T/dl/android-sdk.artifactbundle.tar.gz"
  fi
  swift sdk list
  # The bundle's setup script links the NDK sysroot into the SDK (reruns are harmless).
  local s; s=$(find "$HOME/.swiftpm/swift-sdks" "$HOME/.config/swiftpm/swift-sdks" -name 'setup-android-sdk.sh' 2>/dev/null | sed -n 1p || true)
  if [ -n "$s" ]; then echo "running $s"; bash "$s"; fi
}

install_openxr() {
  # Optional for the host checks (do_check falls back to apt's OpenXR headers); build-apk.sh needs it.
  if [ ! -f build/openxr_loader.aar ] && ! quest/tools/fetch-openxr.sh; then
    echo "cloud-setup.sh: OpenXR AAR unavailable; host checks use /usr/include/openxr, the APK build will need it"; return
  fi
  mkdir -p build/openxr && unzip -q -o build/openxr_loader.aar -d build/openxr
}

# Probes every download host first, so a blocked network is reported once, naming all the hosts to allow.
preflight() {
  local blocked=""
  for u in "$SWIFT_SDK_URL" "$NDK_URL"; do
    curl -sSI -o /dev/null --max-time 20 "$u" 2>/dev/null || blocked="$blocked $(echo "$u" | sed -E 's|https?://([^/]+)/.*|\1|')"
  done
  if [ -n "$blocked" ]; then
    echo "cloud-setup.sh: the APK build needs these hosts, which the session's network policy blocks:$blocked"
    echo "  allow them in the cloud environment's Network access (Allowed domains); host checks still work: $0 host"
    exit 1
  fi
}

do_install_host() {
  step "apt packages" install_apt
  step "swift toolchain" install_swift
  step "openxr loader" install_openxr
}

do_install() { do_install_host; do_install_apk; }

apk_tools_present() {
  [ -f "$NDK_HOME/.complete" ] && ls "$ANDROID_SDK"/platforms/*/android.jar >/dev/null 2>&1 &&
    (load_env; swift sdk list 2>/dev/null | grep -q "$SWIFT_SDK")
}

do_install_apk() {
  apk_tools_present || preflight
  step "android ndk r30" install_ndk
  step "android build-tools + platform" install_android_sdk
  step "swift sdk for android" install_swift_sdk
}

do_check() {
  load_env
  # Without the AAR's headers (e.g. Maven unreachable), apt's libopenxr-dev headers in /usr/include do for the host.
  [ -d "$OPENXR_INCLUDE/openxr" ] || export OPENXR_INCLUDE=/usr/include
  [ -n "$GLSLC" ] || unset GLSLC     # no NDK: shaders.py uses glslangValidator (apt glslang-tools)
  mkdir -p build/quest-out
  # linux-check prints the whole compiler output; keep errors only (the full log stays in build/quest-out).
  if ! quest/tools/linux-check.sh build > build/quest-out/linux-check.log 2>&1; then
    { grep -E "error" -A3 build/quest-out/linux-check.log | head -80; } || true; echo "linux-check.sh failed (build/quest-out/linux-check.log)"; exit 1
  fi
  test -x build/quest-linux/questcheck
  BLOCKSMITH_TEXRES=32 ./build/quest-linux/questcheck --render build/quest-out/stereo.png --questsim build/quest-out/vrsim.png \
    2>&1 | tee build/quest-out/questcheck.log | tail -25 || true     # the grep below decides pass/fail
  grep -q "all checks passed" build/quest-out/questcheck.log || { echo "questcheck FAILED (build/quest-out/questcheck.log)"; exit 1; }
  echo "questcheck: all checks passed (renders in build/quest-out/)"
}

do_apk() {
  load_env
  local out="${1:-build/quest-out/blocksmith-quest.apk}"
  # CI uses the run number (small); epoch minutes stay above it, so a cloud APK installs over a CI one on the headset.
  export VERSION_CODE="${VERSION_CODE:-$(( $(date +%s) / 60 ))}"
  mkdir -p "$(dirname "$out")"
  quest/tools/build-apk.sh "$out"
}

case "${1:-install}" in
  env) env_lines ;;
  install) do_install ;;
  host) do_install_host ;;
  check) step "host checks (linux-check + questcheck)" do_check ;;
  apk) step "apk build" do_apk "${2:-}" ;;
  all)
    mkdir -p "$(dirname "$TIMES")"; : > "$TIMES"
    do_install_host
    step "host checks (linux-check + questcheck)" do_check
    do_install_apk
    step "apk build" do_apk "${2:-}"
    echo "== timings"; cat "$TIMES"
    ;;
  *) sed -n 2,20p "$0"; exit 2 ;;
esac
