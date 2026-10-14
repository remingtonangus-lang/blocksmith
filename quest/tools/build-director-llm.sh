#!/bin/bash
# P266 (d): builds the Director's on-device model runner, libdirectorllm.so (quest/c/llm/directorllm.c with llama.cpp
# linked in statically, CPU only), for the Quest (Android arm64). build-apk.sh calls it and puts the library in the APK;
# the game loads it with dlopen (Sources/DirectorLLM.swift), so a failed build only leaves it out (the rules director
# plays). The model itself is not in the APK: it is an optional download (quest/tools/push-director-model.sh, or the
# store's downloadable asset file), found in the app's files/director/ folder.
#   quest/tools/build-director-llm.sh OUTDIR          (needs ANDROID_NDK_HOME, cmake, git)
# LLAMA_TAG pins the llama.cpp release (the C layer is written against its llama.h); the clone and the static build are
# cached under build/, so later APK builds only relink.
set -euo pipefail
cd "$(dirname "$0")/../.."
NDK="${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME}"
OUT="${1:?usage: build-director-llm.sh OUTDIR}"
TAG="${LLAMA_TAG:-b11600}"
SRC="build/llama.cpp-$TAG"
B="build/llama-android-$TAG"
PREBUILT=$(ls -d "$NDK"/toolchains/llvm/prebuilt/* | sed -n 1p)
CC="$PREBUILT/bin/clang"

if [ ! -f "$SRC/include/llama.h" ]; then
  rm -rf "$SRC"
  git clone -q --depth 1 --branch "$TAG" https://github.com/ggml-org/llama.cpp "$SRC"
fi
if [ ! -f "$B/.built" ]; then
  # Quest 3 (XR2 Gen 2): Armv8.2 with dot product and half floats; no GPU backend (the GPU is the game's).
  cmake -S "$SRC" -B "$B" -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-29 \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=OFF -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_CURL=OFF \
    -DGGML_OPENMP=OFF -DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod+fp16 >/dev/null
  cmake --build "$B" --target llama -j "$(nproc 2>/dev/null || echo 4)" >/dev/null
  touch "$B/.built"
fi
lib() { find "$B" -name "$1" -print -quit; }
LLAMA=$(lib libllama.a); GGML=$(lib libggml.a); BASE=$(lib libggml-base.a); CPU=$(lib libggml-cpu.a)
for f in "$LLAMA" "$GGML" "$BASE" "$CPU"; do [ -n "$f" ] || { echo "build-director-llm: a llama.cpp library is missing"; exit 1; }; done
mkdir -p "$OUT"
"$PREBUILT/bin/clang++" --target=aarch64-linux-android29 -shared -fPIC -O2 -std=c11 -x c quest/c/llm/directorllm.c -x none \
  -I "$SRC/include" -I "$SRC/ggml/include" -I quest/c/llm \
  "$LLAMA" "$GGML" "$CPU" "$BASE" -static-libstdc++ -lm -llog -ldl \
  -Wl,--gc-sections -Wl,-z,max-page-size=16384 -o "$OUT/libdirectorllm.so"
"$PREBUILT/bin/llvm-strip" --strip-unneeded "$OUT/libdirectorllm.so"
ls -la "$OUT/libdirectorllm.so"
