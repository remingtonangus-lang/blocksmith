#!/bin/bash
# Local Meta Quest 3 build loop on the Mac: no GitHub round trip.
#   tools/quest-local.sh               incremental APK build, adb install -r, launch, follow `adb logcat -s Blocksmith`
#   tools/quest-local.sh --log N       ... follow the log for N seconds only, then exit (scripts, agents)
#   tools/quest-local.sh --no-run      build the APK only (build/quest-out/blocksmith-quest-local.apk)
#   tools/quest-local.sh --install     install + launch the last local APK without building
#   tools/quest-local.sh --fast        per-file incremental compile (no whole-module optimization): quicker rebuilds
#                                      for gameplay/UI iteration; judge frame times on a default build
#   tools/quest-local.sh --store       build the store variant (STORE=1: no voice bug notes)
#   tools/quest-local.sh --check       host questcheck: not on macOS, see check() below
#   tools/quest-local.sh --setup       download/install the toolchain (idempotent; see setup() below)
# Same package, debug keystore and build script as CI (quest/tools/build-apk.sh), so it installs over the quest-dist
# APK and keeps the saves. The versionCode is the one already on the headset (Android allows a same-version
# reinstall), so a later CI build still installs over a local one.
# Everything lives in one place: $QUEST_SDK_HOME (default ~/ClaudeTools/quest-sdk), about 9 GB.
set -euo pipefail
cd "$(dirname "$0")/.."
Q="${QUEST_SDK_HOME:-$HOME/ClaudeTools/quest-sdk}"
ADB="${ADB:-$HOME/ClaudeTools/quest/platform-tools/adb}"
PKGNAME=com.blocksmith.quest
APK=build/quest-out/blocksmith-quest-local.apk
T0=$(date +%s)
stamp() { echo "== [$(( $(date +%s) - T0 ))s] $*"; }

setup() {
  # Swift 6.4.0 (swift.org toolchain: the Android Swift SDK needs the matching open-source compiler, not the
  # Command Line Tools one), the swift-6.4.0-RELEASE Android SDK bundle, NDK r30 (also has glslc), Android
  # build-tools + platform (aapt2/zipalign/apksigner, android.jar) and a Java runtime for apksigner.
  # The OpenXR loader comes from quest/tools/fetch-openxr.sh (build/openxr_loader.aar); adb from ~/ClaudeTools/quest.
  mkdir -p "$Q/dl"
  local dl="$Q/dl"
  get() { [ -s "$dl/$1" ] || curl -fL --retry 3 -o "$dl/$1.part" "$2" && { [ -s "$dl/$1" ] || mv "$dl/$1.part" "$dl/$1"; }; }
  if [ ! -x "$Q/swift/usr/bin/swift" ]; then
    get toolchain.pkg https://download.swift.org/swift-6.4.0-release/xcode/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE-osx.pkg
    rm -rf "$Q/pkgx"; pkgutil --expand-full "$dl/toolchain.pkg" "$Q/pkgx"
    local pay; pay=$(dirname "$(dirname "$(dirname "$(find "$Q/pkgx" -path '*/usr/bin/swift' -print -quit)")")")
    rm -rf "$Q/swift"; mv "$pay" "$Q/swift"; rm -rf "$Q/pkgx" "$dl/toolchain.pkg"
  fi
  if [ ! -d "$Q/ndk/android-ndk-r30" ]; then
    get ndk.zip https://dl.google.com/android/repository/android-ndk-r30-darwin.zip
    mkdir -p "$Q/ndk"; unzip -q "$dl/ndk.zip" -d "$Q/ndk.x"
    # The darwin zip holds an .app bundle; the NDK proper is Contents/NDK.
    local nd; nd=$(dirname "$(find "$Q/ndk.x" -maxdepth 4 -name source.properties -print -quit)")
    mv "$nd" "$Q/ndk/android-ndk-r30"; rm -rf "$Q/ndk.x" "$dl/ndk.zip"
  fi
  if [ ! -d "$Q/android/build-tools" ]; then
    get bt.zip https://dl.google.com/android/repository/build-tools_r36.1_macosx.zip
    get plat.zip https://dl.google.com/android/repository/platform-36_r02.zip
    mkdir -p "$Q/android/build-tools" "$Q/android/platforms" "$Q/android.x"
    unzip -q "$dl/bt.zip" -d "$Q/android.x/bt"; mv "$Q/android.x/bt/"* "$Q/android/build-tools/36.1"
    unzip -q "$dl/plat.zip" -d "$Q/android.x/pl"; mv "$Q/android.x/pl/"* "$Q/android/platforms/android-36"
    rm -rf "$Q/android.x" "$dl/bt.zip" "$dl/plat.zip"
  fi
  if [ ! -x "$Q/jre/bin/java" ]; then
    get jre.tar.gz https://api.adoptium.net/v3/binary/latest/21/ga/mac/aarch64/jre/hotspot/normal/eclipse
    mkdir -p "$Q/jre.x"; tar -xzf "$dl/jre.tar.gz" -C "$Q/jre.x"
    mv "$(dirname "$(dirname "$(find "$Q/jre.x" -path '*/bin/java' -print -quit)")")" "$Q/jre"; rm -rf "$Q/jre.x" "$dl/jre.tar.gz"
  fi
  env_setup
  if ! swift sdk list --swift-sdks-path "$SWIFT_SDKS_PATH" 2>/dev/null | grep -q swift-6.4.0-RELEASE_android; then
    get swiftsdk.tar.gz https://download.swift.org/swift-6.4.0-release/android-sdk/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE_android.artifactbundle.tar.gz
    echo "21fb555122a3d801ad943d48df7ebffdd8824de61c25c180bb792d3edaee0b43  $dl/swiftsdk.tar.gz" | shasum -a 256 -c -
    swift sdk install --swift-sdks-path "$SWIFT_SDKS_PATH" "$dl/swiftsdk.tar.gz"
    rm -f "$dl/swiftsdk.tar.gz"
  fi
  # The bundle's setup script links the NDK sysroot into the SDK (what CI runs after `swift sdk install`).
  local s; s=$(find "$SWIFT_SDKS_PATH" -name setup-android-sdk.sh -print -quit)
  [ -n "$s" ] && bash "$s" >/dev/null
  [ -f build/openxr_loader.aar ] || quest/tools/fetch-openxr.sh
  rmdir "$dl" 2>/dev/null || true
  echo "quest-local setup done: $(du -sh "$Q" | cut -f1) in $Q"
}

env_setup() {
  export PATH="$Q/swift/usr/bin:$Q/jre/bin:$PATH" JAVA_HOME="$Q/jre"
  export SWIFT_SDKS_PATH="$Q/swift-sdks" ANDROID_HOME="$Q/android"
  export ANDROID_NDK_HOME="$Q/ndk/android-ndk-r30"
  export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME" ANDROID_NDK="$ANDROID_NDK_HOME" ANDROID_NDK_LATEST_HOME="$ANDROID_NDK_HOME"
  export OPENXR_AAR=build/openxr_loader.aar QUEST_LOCAL=1
  mkdir -p "$SWIFT_SDKS_PATH"
}

device() { "$ADB" get-state >/dev/null 2>&1; }

build() {
  [ -x "$Q/swift/usr/bin/swift" ] && [ -d "$Q/ndk/android-ndk-r30" ] || setup
  env_setup
  # versionCode: the installed one (same-version reinstall), else the last quest-dist one, else 1.
  local vc=""
  device && vc=$("$ADB" shell dumpsys package $PKGNAME 2>/dev/null | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | head -1)
  [ -n "$vc" ] || vc=$(sed -n 's/.*versionCode \([0-9]*\).*/\1/p' "$HOME/ClaudeTools/quest/quest-dist/BUILD.txt" 2>/dev/null | head -1)
  export VERSION_CODE="${vc:-1}"
  mkdir -p build/quest-out
  stamp "build (versionCode $VERSION_CODE$( [ "${STORE:-0}" = 1 ] && echo ', store')$( [ "${QUEST_FAST:-0}" = 1 ] && echo ', fast'))"
  quest/tools/build-apk.sh "$APK" 2>&1 | grep -vE '^(Verified|  adding|-rw|total|drwx)' | tail -n 25
  stamp "APK ready: $APK ($(du -h "$APK" | cut -f1))"
}

run() {
  device || { echo "quest-local: no headset on adb (plug the Quest in, allow USB debugging); APK is at $APK"; exit 2; }
  stamp "install"
  "$ADB" install -r "$APK" 2>&1 | tail -2 | tee /tmp/quest-local-install.log
  if grep -q INSTALL_FAILED /tmp/quest-local-install.log; then
    echo "quest-local: install failed. INSTALL_FAILED_UPDATE_INCOMPATIBLE = installed with another key:"
    echo "  $ADB uninstall $PKGNAME   (deletes the app's saves), then rerun with --install"
    exit 3
  fi
  "$ADB" shell am force-stop $PKGNAME
  "$ADB" logcat -c
  stamp "launch"
  "$ADB" shell am start -n $PKGNAME/android.app.NativeActivity >/dev/null
  if [ -n "${LOGSECS:-}" ]; then
    "$ADB" logcat -s Blocksmith:V DEBUG:V > build/quest-out/local-logcat.txt 2>&1 & local lp=$!
    local end=$(( $(date +%s) + LOGSECS )) seen=""
    while [ "$(date +%s)" -lt $end ]; do
      if [ -z "$seen" ] && grep -q "xr: refresh rate" build/quest-out/local-logcat.txt 2>/dev/null; then
        seen=1; stamp "running on the headset (XR session up)"
      fi
      sleep 1
    done
    kill $lp 2>/dev/null || true
    grep -E "FATAL|Fatal signal|perf:|load:|xr: refresh" build/quest-out/local-logcat.txt | tail -n 20
    echo "full log: build/quest-out/local-logcat.txt"
  else
    exec "$ADB" logcat -s Blocksmith:V DEBUG:V
  fi
}

check() {
  # questcheck (quest/tools/linux-check.sh) does not build on macOS (tried Oct 9 with the swift.org 6.4.0 toolchain and
  # the NDK's Vulkan headers: 38 errors): the shim modules simd/os/Metal stand in for Apple frameworks on Linux and
  # collide with the real macOS SDK modules (Apple's swiftinterfaces fail on os::OSLogMessage), and the shared code's
  # canImport(AppKit)/GameController paths switch on. --render would also need a Vulkan driver (lavapipe).
  echo "quest-local --check: questcheck is Linux-only (its simd/os/Metal shim modules collide with the macOS SDK)."
  echo "Locally: the Mac harness (./snap.sh, ./smoke.sh) and the APK on the headset; CI's quest host job runs questcheck."
  exit 2
}

LOGSECS=""; mode=all
while [ $# -gt 0 ]; do
  case "$1" in
    --log) LOGSECS="$2"; shift ;;
    --no-run) mode=build ;;
    --install) mode=run ;;
    --store) export STORE=1 ;;
    --fast) export QUEST_FAST=1 ;;
    --check) mode=check ;;
    --setup) mode=setup ;;
    *) sed -n '2,14p' "$0"; exit 1 ;;
  esac
  shift
done
case $mode in
  setup) setup ;;
  check) check ;;
  build) build ;;
  run) run ;;
  all) build; run ;;
esac
