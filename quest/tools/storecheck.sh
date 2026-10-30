#!/bin/bash
# Proves a Quest APK does (playtest) or does not (store) contain the voice bug notes recorder:
#   quest/tools/storecheck.sh STORE.apk                  every check must find nothing
#   quest/tools/storecheck.sh --expect-voice DEV.apk     every check must find it (shows the checks can see it)
# Checks: the RECORD_AUDIO permission in the manifest, the mic/encoder symbols (bs_mic_*, bs_aac_*, bs_venc_*, an
# encoder made with AMediaCodec_createEncoderByType, AMediaMuxer_*, AAudioStreamBuilder_setInputPreset) and the
# recorder's strings. (libmediandk and AMediaCodec's decoder calls stay in every build since P359: the soundtrack's
# decoder, MediaTrackDecoder.swift.)
# Needs AAPT2 and READELF (build-apk.sh exports them) or finds them on PATH.
set -uo pipefail
EXPECT=0
[ "${1:-}" = "--expect-voice" ] && { EXPECT=1; shift; }
APK="${1:?usage: storecheck.sh [--expect-voice] APK}"
AAPT2="${AAPT2:-aapt2}"; READELF="${READELF:-llvm-readelf}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
unzip -q -o "$APK" lib/arm64-v8a/libblocksmith.so -d "$TMP" || { echo "storecheck: no libblocksmith.so in $APK"; exit 1; }
SO="$TMP/lib/arm64-v8a/libblocksmith.so"
fails=0
check() {   # name, count found
  local found=$2 want="absent"; [ "$EXPECT" = 1 ] && want="present"
  if { [ "$EXPECT" = 1 ] && [ "$found" -gt 0 ]; } || { [ "$EXPECT" = 0 ] && [ "$found" -eq 0 ]; }; then
    echo "storecheck: ok   $1 $want ($found)"
  else echo "storecheck: FAIL $1 should be $want ($found found)"; fails=$((fails + 1)); fi
}
check "RECORD_AUDIO permission" "$("$AAPT2" dump xmltree --file AndroidManifest.xml "$APK" 2>/dev/null | grep -c RECORD_AUDIO)"
check "mic/encoder symbols" "$("$READELF" --dyn-syms "$SO" | grep -cE 'bs_mic_|bs_aac_|bs_venc_|AMediaCodec_createEncoderByType|AMediaMuxer_|AAudioStreamBuilder_setInputPreset')"
check "recorder strings" "$(strings -a "$SO" | grep -cE 'voicenotes|voicevideo|RECORD_AUDIO')"
check "playtest checklist asset (P399)" "$(unzip -l "$APK" 2>/dev/null | grep -c 'assets/device-checklist.md')"
# P360 (c): Meta store packaging (hz-store-submit's VRC packaging rows), on store builds only.
if [ "$EXPECT" = 0 ]; then
  pk() { if [ "$2" = 1 ]; then echo "storecheck: ok   $1"; else echo "storecheck: FAIL $1"; fails=$((fails + 1)); fi; }
  MAN=$("$AAPT2" dump badging "$APK" 2>/dev/null)
  sdk=$(echo "$MAN" | sed -n "s/^\(min\)\{0,1\}[sS]dkVersion:'\([0-9]*\)'.*/\2/p" | head -1); tsdk=$(echo "$MAN" | sed -n "s/^targetSdkVersion:'\([0-9]*\)'.*/\1/p")
  pk "minSdk >= 29 ($sdk)" "$([ "${sdk:-0}" -ge 29 ] && echo 1)"
  pk "targetSdk >= 32 ($tsdk)" "$([ "${tsdk:-0}" -ge 32 ] && echo 1)"
  other=$(unzip -Z1 "$APK" | grep '^lib/' | grep -vc '^lib/arm64-v8a/')
  pk "arm64-v8a libraries only ($other others)" "$([ "$other" -eq 0 ] && echo 1)"
  pk "VR intent category" "$("$AAPT2" dump xmltree --file AndroidManifest.xml "$APK" 2>/dev/null | grep -c 'com.oculus.intent.category.VR' | grep -qv '^0$' && echo 1)"
  bad=$(echo "$MAN" | grep -cE "uses-permission: name='android.permission.(CALL_PHONE|SEND_SMS|READ_SMS|READ_CONTACTS|ACCESS_FINE_LOCATION|ACCESS_COARSE_LOCATION|READ_EXTERNAL_STORAGE|CAMERA|READ_PHONE_STATE)'")
  pk "no prohibited permissions ($bad)" "$([ "$bad" -eq 0 ] && echo 1)"
  if [ -n "${APKSIGNER:-}" ]; then
    SIG=$("$APKSIGNER" verify --verbose --print-certs "$APK" 2>/dev/null)
    # (v2 or later: with minSdk 29 apksigner signs v3 only, which Quest OS verifies and which supersedes v2)
    pk "APK Signature Scheme v2 or later" "$(echo "$SIG" | grep -qE 'v[23] scheme \(APK Signature Scheme v[23]\): true' && echo 1)"
    if echo "$SIG" | grep -qiE 'DN: CN=[^,]*Debug'; then
      if [ -n "${STORE_KEYSTORE:-}" ]; then pk "release key (debug-signed)" 0; else echo "storecheck: note debug-signed (set STORE_KEYSTORE for the upload)"; fi
    else pk "release key" 1; fi
  fi
fi
echo "storecheck: $([ "$EXPECT" = 1 ] && echo playtest || echo store) APK $(basename "$APK"): $fails failures"
exit $((fails > 0))
