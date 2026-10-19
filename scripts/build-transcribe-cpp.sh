#!/usr/bin/env bash
set -euo pipefail

# Builds transcribe.cpp as x86_64 static libraries for the Intel slice of the
# app (`Engine/Intel/`), and installs them, the public headers and a
# `TranscribeCpp` Clang module map into VoiceToText/Vendor/transcribe.cpp
# (gitignored). The arm64 slice never links them: the Xcode settings that do
# are all `[arch=x86_64]`.
#
# Run it once before any build that includes x86_64 — a universal Release
# (`scripts/install.sh`, the release workflow) or `ARCHS=x86_64`. A Debug
# build for an Apple Silicon Mac (`scripts/dev.sh`) doesn't need it. It skips
# the build when the installed libraries were already built from this tag
# with these settings.
#
# usage: ./scripts/build-transcribe-cpp.sh

TCPP_TAG="v0.4.0"
# The commit `v0.4.0` points at, so a moved tag fails instead of building
# something else.
TCPP_COMMIT="f1dcd15858c4bbba87ca97862b4e448b2cf15b8f"
TCPP_REPO="https://github.com/handy-computer/transcribe.cpp"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$REPO_ROOT/VoiceToText/Vendor/transcribe.cpp"
STAMP="$OUT_DIR/.build-stamp"

# libggml-metal.a is linked with -force_load (see the Xcode project): its
# Objective-C classes and the embedded Metal library must all reach the app.
LIBS=(libtranscribe.a libggml.a libggml-base.a libggml-cpu.a libggml-metal.a)

# GGML_NATIVE=OFF with an explicit baseline, so the libraries don't target
# whatever CPU builds them. Every Intel Mac that runs macOS 15 has AVX2, FMA,
# F16C and BMI2 (Haswell and later); none of the ones without AVX-512 would run
# an AVX-512 build. Metal is on, with its shader library embedded, so the
# worker can use the Mac's GPU; it falls back to the CPU when that fails. The
# repo forces its own BLAS choice (llamafile's sgemm, Accelerate for the host
# decoder). OpenMP is off (Apple's clang has none), so ggml uses its own
# thread pool.
CMAKE_ARGS=(
    -G "Unix Makefiles"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_OSX_ARCHITECTURES=x86_64
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0
    -DTRANSCRIBE_BUILD_SHARED=OFF
    -DTRANSCRIBE_BUILD_TESTS=OFF
    -DTRANSCRIBE_BUILD_EXAMPLES=OFF
    -DTRANSCRIBE_BUILD_TOOLS=OFF
    -DTRANSCRIBE_INSTALL=ON
    -DTRANSCRIBE_METAL=ON
    -DGGML_METAL=ON
    -DGGML_METAL_EMBED_LIBRARY=ON
    -DTRANSCRIBE_USE_OPENMP=OFF
    -DGGML_OPENMP=OFF
    -DGGML_CCACHE=OFF
    -DGGML_NATIVE=OFF
    -DGGML_SSE42=ON
    -DGGML_AVX=ON
    -DGGML_AVX2=ON
    -DGGML_FMA=ON
    -DGGML_F16C=ON
    -DGGML_BMI2=ON
    -DGGML_AVX_VNNI=OFF
    -DGGML_AVX512=OFF
    -DGGML_AVX512_VBMI=OFF
    -DGGML_AVX512_VNNI=OFF
    -DGGML_AVX512_BF16=OFF
    -DGGML_AMX_TILE=OFF
    -DGGML_AMX_INT8=OFF
    -DGGML_AMX_BF16=OFF
)

STAMP_VALUE="$TCPP_TAG $TCPP_COMMIT $(printf '%s\n' "${CMAKE_ARGS[@]}" | shasum -a 256 | cut -c1-16)"

installed_is_current() {
    [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$STAMP_VALUE" ] || return 1
    for lib in "${LIBS[@]}"; do
        [ -f "$OUT_DIR/lib/$lib" ] || return 1
    done
    [ -f "$OUT_DIR/include/transcribe.h" ] && [ -f "$OUT_DIR/include/module.modulemap" ]
}

if installed_is_current; then
    echo "✓ transcribe.cpp $TCPP_TAG (x86_64) is already built in $OUT_DIR"
    exit 0
fi

for tool in git cmake make; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "✗ $tool not found; building transcribe.cpp needs git, cmake and make" >&2
        echo "  (cmake: brew install cmake)" >&2
        exit 1
    fi
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/transcribe-cpp-build.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "→ cloning transcribe.cpp $TCPP_TAG"
# Its stderr only on failure: a shallow clone of an annotated tag always
# warns that the tag "is not a commit".
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$TCPP_TAG" \
    "$TCPP_REPO" "$WORK_DIR/src" 2>"$WORK_DIR/clone.log" || {
    cat "$WORK_DIR/clone.log" >&2
    exit 1
}
ACTUAL_COMMIT="$(git -C "$WORK_DIR/src" rev-parse HEAD)"
if [ "$ACTUAL_COMMIT" != "$TCPP_COMMIT" ]; then
    echo "✗ $TCPP_TAG is $ACTUAL_COMMIT, expected $TCPP_COMMIT" >&2
    exit 1
fi

echo "→ configuring (x86_64, static, CPU + Metal)"
cmake -S "$WORK_DIR/src" -B "$WORK_DIR/build" "${CMAKE_ARGS[@]}" \
    -DCMAKE_INSTALL_PREFIX="$WORK_DIR/stage" >"$WORK_DIR/configure.log" 2>&1 || {
    cat "$WORK_DIR/configure.log" >&2
    exit 1
}

echo "→ building"
cmake --build "$WORK_DIR/build" --config Release -j "$(sysctl -n hw.ncpu)" >"$WORK_DIR/build.log" 2>&1 || {
    tail -50 "$WORK_DIR/build.log" >&2
    exit 1
}
cmake --install "$WORK_DIR/build" >"$WORK_DIR/install.log" 2>&1 || {
    cat "$WORK_DIR/install.log" >&2
    exit 1
}

STAGE="$WORK_DIR/stage"
for lib in "${LIBS[@]}"; do
    if [ ! -f "$STAGE/lib/$lib" ]; then
        echo "✗ the build produced no $lib" >&2
        exit 1
    fi
    if ! lipo "$STAGE/lib/$lib" -verify_arch x86_64; then
        echo "✗ $lib isn't x86_64" >&2
        exit 1
    fi
done
# Every archive the build installed must be one the app links; one it doesn't
# would leave undefined symbols that only show up in the x86_64 link.
for installed in "$STAGE"/lib/*.a; do
    name="$(basename "$installed")"
    if [[ ! " ${LIBS[*]} " == *" $name "* ]]; then
        echo "✗ the build installed $name, which the app doesn't link; add it to LIBS and the Xcode project" >&2
        exit 1
    fi
done

echo "→ installing into $OUT_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/lib" "$OUT_DIR/include/transcribe"
for lib in "${LIBS[@]}"; do
    cp "$STAGE/lib/$lib" "$OUT_DIR/lib/"
done
# transcribe.h and the Whisper family's extension header, which includes it.
# Neither includes a ggml header.
cp "$STAGE/include/transcribe.h" "$OUT_DIR/include/"
cp "$STAGE/include/transcribe/whisper.h" "$OUT_DIR/include/transcribe/"
cp "$STAGE/lib/transcribe-link.json" "$OUT_DIR/lib/"
cp "$WORK_DIR/src/LICENSE" "$OUT_DIR/LICENSE"
cp "$WORK_DIR/src/THIRD-PARTY-LICENSES.md" "$OUT_DIR/THIRD-PARTY-LICENSES.md"

cat >"$OUT_DIR/include/module.modulemap" <<'EOF'
module TranscribeCpp {
    header "transcribe.h"
    header "transcribe/whisper.h"
    export *
}
EOF

echo "$STAMP_VALUE" >"$STAMP"
echo "✓ transcribe.cpp $TCPP_TAG (x86_64) built into $OUT_DIR"
