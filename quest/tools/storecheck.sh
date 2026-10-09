#!/bin/bash
# Proves a Quest APK does (playtest) or does not (store) contain the voice bug notes recorder:
#   quest/tools/storecheck.sh STORE.apk                  every check must find nothing
#   quest/tools/storecheck.sh --expect-voice DEV.apk     every check must find it (shows the checks can see it)
# Checks: the RECORD_AUDIO permission in the manifest, libmediandk among the library's dependencies, the mic/encoder
# symbols (bs_mic_*, bs_aac_*, AMediaCodec_*, AAudioStreamBuilder_setInputPreset) and the recorder's strings.
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
check "libmediandk dependency" "$("$READELF" -d "$SO" | grep -c 'libmediandk')"
check "mic/encoder symbols" "$("$READELF" --dyn-syms "$SO" | grep -cE 'bs_mic_|bs_aac_|AMediaCodec_|AAudioStreamBuilder_setInputPreset')"
check "recorder strings" "$(strings -a "$SO" | grep -cE 'voicenotes|RECORD_AUDIO')"
echo "storecheck: $([ "$EXPECT" = 1 ] && echo playtest || echo store) APK $(basename "$APK"): $fails failures"
exit $((fails > 0))
