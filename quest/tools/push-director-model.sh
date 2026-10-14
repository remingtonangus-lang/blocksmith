#!/bin/bash
# P266 (d): puts the Director's on-device model on a connected Quest (the optional download; the APK carries only the
# runner). The model: Qwen2.5 0.5B Instruct, 4-bit (Q4_K_M, about 0.4 GB), Apache 2.0 licence (allows use in a paid
# game; keep its licence notice with the download). MODEL=1.5b takes the 1.5B one (about 1.1 GB, also Apache 2.0):
# better events, slower to plan.
#   quest/tools/push-director-model.sh            download (cached in build/) and adb push to the headset
# The game looks for files/director/model.gguf in the app's external files folder (then its internal one) and loads it
# only after the story is beaten (or with Options > Director > Before the Story Ends on).
set -euo pipefail
cd "$(dirname "$0")/../.."
PKG="${PKG:-com.blocksmith.quest}"
case "${MODEL:-0.5b}" in
  1.5b) URL="https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf" ;;
  *)    URL="https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf" ;;
esac
F="build/director-model/$(basename "$URL")"
mkdir -p build/director-model
[ -s "$F" ] || curl -L --fail -o "$F" "$URL"
adb shell mkdir -p "/sdcard/Android/data/$PKG/files/director"
adb push "$F" "/sdcard/Android/data/$PKG/files/director/model.gguf"
echo "pushed $(basename "$F"): the Director's on-device model is ready (Options > Director shows its state)"
