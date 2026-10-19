#!/usr/bin/env bash
# Parakeet TDT 0.6B v3 on the CPU: FluidAudio CoreML vs transcribe.cpp (ggml).
#
# usage: bench.sh <command>
#   hwinfo        print the CPU / OS / toolchain and save it to runs/hardware.txt
#   build-tcpp    clone transcribe.cpp v0.4.0 and build transcribe-bench
#   fetch-gguf    download the Q8_0 and Q4_K_M GGUFs (SHA-256 verified)
#   build-pbench  build the FluidAudio CoreML harness
#   coreml-rev    print the current commit of the CoreML model repo on Hugging Face
#   fetch-coreml  download the CoreML models with FluidAudio
#   run           run the whole matrix sequentially; a failing config is recorded, not fatal
#   report        write runs/summary.md from whatever finished
#   all           every step above in order, continuing past failures
#
# Environment (defaults in brackets):
#   BENCH_ARCH   architecture to build and run [uname -m]; x86_64 on an Apple Silicon Mac runs under Rosetta
#   WORK         scratch directory [bench/intel-parakeet/.work]
#   CM_UNITS     CoreML compute units ["ane cpu"]; ane is FluidAudio's default and what the app uses; empty skips CoreML
#   CM_PROCS     CoreML processes per units setting [3]
#   CM_WARM      warm runs per CoreML process, after one cold run [3]
#   TC_QUANTS    GGUF quants ["Q4_K_M Q8_0"]; empty skips transcribe.cpp
#   TC_THREADS   transcribe.cpp thread counts ["4 8 <hw.physicalcpu>", deduplicated]
#   TC_ITERS     transcribe-bench iterations; the first is the cold run [4]
#   RUN_TIMEOUT  seconds before one config is killed [1200]
#   HF_TOKEN     optional Hugging Face token for the downloads (FluidAudio reads it too)
set -uo pipefail

# An empty token would make FluidAudio send an empty bearer header.
if [ -z "${HF_TOKEN:-}" ]; then
    unset HF_TOKEN
fi

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_ARCH="${BENCH_ARCH:-$(uname -m)}"
WORK="${WORK:-$BENCH_DIR/.work}"
RUNS="$WORK/runs"
AUDIO="$BENCH_DIR/audio/speech.wav"
REF_TEXT="$BENCH_DIR/audio/text.txt"

CM_UNITS="${CM_UNITS-ane cpu}"
CM_PROCS="${CM_PROCS:-3}"
CM_WARM="${CM_WARM:-3}"
TC_QUANTS="${TC_QUANTS-Q4_K_M Q8_0}"
TC_ITERS="${TC_ITERS:-4}"
RUN_TIMEOUT="${RUN_TIMEOUT:-1200}"
if [ -z "${TC_THREADS:-}" ]; then
    TC_THREADS="$(printf '%s\n' 4 8 "$(sysctl -n hw.physicalcpu)" | sort -un | tr '\n' ' ')"
fi

TCPP_REPO="https://github.com/handy-computer/transcribe.cpp"
TCPP_TAG="v0.4.0"
TCPP_COMMIT="f1dcd15858c4bbba87ca97862b4e448b2cf15b8f"
TCPP_SRC="$WORK/transcribe.cpp"
TCPP_BUILD="$WORK/tcpp-build-$BENCH_ARCH"
TCPP_BENCH="$TCPP_BUILD/bin/transcribe-bench"

GGUF_DIR="$WORK/models-gguf"
GGUF_REPO="handy-computer/parakeet-tdt-0.6b-v3-gguf"
GGUF_REV="85ac09ea12fc4b1112fa76810059364bc6adc9de"
gguf_sha() {
    case "$1" in
    Q8_0) echo 5859f77944efcd8eafa23a6350731960b2b55b2203df51f319665c807d802cc7 ;;
    Q4_K_M) echo b68557be1e3c40207fd7c4bd9d63f1d3316b963f15325bfb0cc16a8bb0ffd181 ;;
    esac
}

COREML_REPO="FluidInference/parakeet-tdt-0.6b-v3-coreml"
COREML_DIR="$WORK/models-coreml/parakeet-tdt-0.6b-v3"
COREML_COPY="$WORK/coreml-copy/parakeet-tdt-0.6b-v3"
PBENCH_BUILD="$WORK/pbench-build-$BENCH_ARCH"

# Same posture as scripts/build-whisper-cpp.sh: explicit Haswell-class baseline, no native tuning.
CMAKE_ARGS=(
    -G "Unix Makefiles"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_OSX_ARCHITECTURES="$BENCH_ARCH"
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0
    -DTRANSCRIBE_METAL=OFF
    -DGGML_METAL=OFF
    -DTRANSCRIBE_USE_OPENMP=OFF
    -DGGML_OPENMP=OFF
    -DTRANSCRIBE_BUILD_SHARED=OFF
    -DTRANSCRIBE_BUILD_TOOLS=ON
    -DTRANSCRIBE_BUILD_EXAMPLES=ON
    -DTRANSCRIBE_BUILD_TESTS=OFF
    -DGGML_CCACHE=OFF
    -DGGML_NATIVE=OFF
    -DGGML_SSE42=ON
    -DGGML_AVX=ON
    -DGGML_AVX2=ON
    -DGGML_FMA=ON
    -DGGML_F16C=ON
    -DGGML_BMI2=ON
    -DGGML_AVX512=OFF
    -DGGML_AVX_VNNI=OFF
    -DGGML_AVX512_VBMI=OFF
    -DGGML_AVX512_VNNI=OFF
    -DGGML_AVX512_BF16=OFF
)

mkdir -p "$RUNS"

log() { printf '\n==> %s\n' "$*"; }

# record_error <step> <message> [logfile]: appended to runs/errors.md for the report.
record_error() {
    {
        printf '### %s\n\n%s\n\n' "$1" "$2"
        if [ -n "${3:-}" ] && [ -f "$3" ]; then
            printf '```\n'
            tail -n 30 "$3"
            printf '```\n\n'
        fi
    } >>"$RUNS/errors.md"
    echo "::warning::$1: $2"
}

# Runs "$@" but kills it after <seconds>: the pending SIGALRM survives exec, so the command
# itself dies (exit 142). It is an exec chain rather than a function so /usr/bin/time can wrap it.
ALARM_EXEC=(perl -e 'alarm shift @ARGV; exec @ARGV or die "exec failed: $!\n"')

ncpu() { sysctl -n hw.logicalcpu; }

cmd_hwinfo() {
    {
        echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "bench arch: $BENCH_ARCH (uname -m: $(uname -m))"
        echo "cpu: $(sysctl -n machdep.cpu.brand_string)"
        echo "physical cpus: $(sysctl -n hw.physicalcpu)  logical cpus: $(sysctl -n hw.logicalcpu)"
        echo "memory bytes: $(sysctl -n hw.memsize)"
        echo "cpu features: $(sysctl -n machdep.cpu.features 2>/dev/null || echo n/a)"
        echo "leaf7 features: $(sysctl -n machdep.cpu.leaf7_features 2>/dev/null || echo n/a)"
        echo "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
        echo "xcode: $(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
        echo "swift: $(swift --version 2>&1 | head -1)"
        echo "cmake: $(cmake --version 2>/dev/null | head -1)"
        echo "load average: $(sysctl -n vm.loadavg)"
        echo "thread counts: $TC_THREADS"
    } | tee "$RUNS/hardware.txt"
}

cmd_build_tcpp() {
    local logf="$RUNS/build-tcpp.log"
    : >"$logf"
    if [ ! -d "$TCPP_SRC/.git" ]; then
        log "cloning transcribe.cpp $TCPP_TAG"
        git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$TCPP_TAG" "$TCPP_REPO" "$TCPP_SRC" >>"$logf" 2>&1 || {
            record_error "build-tcpp" "git clone of $TCPP_TAG failed" "$logf"
            return 1
        }
    fi
    local actual
    actual="$(git -C "$TCPP_SRC" rev-parse HEAD)"
    if [ "$actual" != "$TCPP_COMMIT" ]; then
        record_error "build-tcpp" "$TCPP_TAG is $actual, expected $TCPP_COMMIT"
        return 1
    fi
    log "configuring transcribe.cpp ($BENCH_ARCH)"
    printf '%s\n' "${CMAKE_ARGS[@]}" >"$RUNS/tcpp-cmake-args.txt"
    cmake -S "$TCPP_SRC" -B "$TCPP_BUILD" "${CMAKE_ARGS[@]}" >>"$logf" 2>&1 || {
        record_error "build-tcpp" "cmake configure failed" "$logf"
        return 1
    }
    grep -E "GGML_SYSTEM_ARCH|CPU backend variant|transcribe version" "$logf" || true
    log "building transcribe-bench"
    cmake --build "$TCPP_BUILD" --target transcribe-bench -j "$(ncpu)" >>"$logf" 2>&1 || {
        record_error "build-tcpp" "build failed" "$logf"
        return 1
    }
    file "$TCPP_BENCH"
    lipo "$TCPP_BENCH" -verify_arch "$BENCH_ARCH" || {
        record_error "build-tcpp" "transcribe-bench is not $BENCH_ARCH"
        return 1
    }
}

cmd_fetch_gguf() {
    mkdir -p "$GGUF_DIR"
    local status=0 quant sha file
    local auth=()
    if [ -n "${HF_TOKEN:-}" ]; then
        auth=(-H "Authorization: Bearer $HF_TOKEN")
    fi
    for quant in Q4_K_M Q8_0; do
        file="$GGUF_DIR/parakeet-tdt-0.6b-v3-$quant.gguf"
        sha="$(gguf_sha "$quant")"
        if [ -f "$file" ] && [ "$(shasum -a 256 "$file" | cut -d' ' -f1)" = "$sha" ]; then
            echo "✓ $quant already present and verified"
            continue
        fi
        log "downloading $quant"
        if ! curl -fL --retry 3 --retry-delay 5 -sS ${auth[@]+"${auth[@]}"} -o "$file.part" \
            "https://huggingface.co/$GGUF_REPO/resolve/$GGUF_REV/parakeet-tdt-0.6b-v3-$quant.gguf"; then
            record_error "fetch-gguf" "download of $quant failed"
            rm -f "$file.part"
            status=1
            continue
        fi
        if [ "$(shasum -a 256 "$file.part" | cut -d' ' -f1)" != "$sha" ]; then
            record_error "fetch-gguf" "$quant SHA-256 mismatch"
            rm -f "$file.part"
            status=1
            continue
        fi
        mv "$file.part" "$file"
        echo "✓ $quant downloaded and verified"
    done
    ls -l "$GGUF_DIR"
    return $status
}

pbench_bin() { swift build -c release --arch "$BENCH_ARCH" --package-path "$BENCH_DIR/pbench" --scratch-path "$PBENCH_BUILD" --show-bin-path 2>/dev/null; }

cmd_build_pbench() {
    local logf="$RUNS/build-pbench.log"
    log "building pbench ($BENCH_ARCH)"
    swift build -c release --arch "$BENCH_ARCH" --package-path "$BENCH_DIR/pbench" --scratch-path "$PBENCH_BUILD" >"$logf" 2>&1 || {
        record_error "build-pbench" "swift build failed" "$logf"
        return 1
    }
    tail -n 3 "$logf"
    file "$(pbench_bin)/pbench"
}

cmd_coreml_rev() {
    curl -fsS --retry 3 "https://huggingface.co/api/models/$COREML_REPO/revision/main" |
        python3 -I -B -c 'import json, sys; print(json.load(sys.stdin)["sha"])'
}

coreml_complete() {
    local d=$1 f
    for f in Preprocessor.mlmodelc Encoder.mlmodelc Decoder.mlmodelc JointDecision.mlmodelc parakeet_v3_vocab.json; do
        [ -e "$d/$f" ] || return 1
    done
}

cmd_fetch_coreml() {
    local logf="$RUNS/fetch-coreml.log"
    local rev
    rev="$(cmd_coreml_rev 2>/dev/null || echo unknown)"
    echo "$COREML_REPO@$rev" >"$RUNS/coreml-revision.txt"
    echo "CoreML models: $COREML_REPO@$rev (FluidAudio downloads from main)"
    if coreml_complete "$COREML_DIR"; then
        echo "✓ CoreML models already present at $COREML_DIR"
        return 0
    fi
    local bin
    bin="$(pbench_bin)/pbench"
    if [ ! -x "$bin" ]; then
        record_error "fetch-coreml" "pbench is not built"
        return 1
    fi
    log "downloading CoreML models with FluidAudio"
    mkdir -p "$(dirname "$COREML_DIR")"
    "${ALARM_EXEC[@]}" "$RUN_TIMEOUT" arch "-$BENCH_ARCH" "$bin" download "$COREML_DIR" >"$logf" 2>&1 || {
        record_error "fetch-coreml" "FluidAudio download failed" "$logf"
        return 1
    }
    grep DOWNLOADED "$logf" || true
    coreml_complete "$COREML_DIR" || {
        record_error "fetch-coreml" "download finished but files are missing in $COREML_DIR" "$logf"
        return 1
    }
    du -sh "$COREML_DIR"
}

# FluidAudio deletes the model folder when a load fails, so runs use a copy.
refresh_coreml_copy() {
    if coreml_complete "$COREML_COPY"; then
        return 0
    fi
    rm -rf "$COREML_COPY"
    mkdir -p "$(dirname "$COREML_COPY")"
    cp -R -c "$COREML_DIR" "$COREML_COPY" 2>/dev/null || cp -R "$COREML_DIR" "$COREML_COPY"
}

run_coreml() {
    local units=$1 rep=$2 bin=$3
    local name="coreml-$BENCH_ARCH-$units-r$rep"
    log "$name  (load $(sysctl -n vm.loadavg))"
    if ! refresh_coreml_copy; then
        record_error "$name" "could not copy the CoreML models"
        printf '%s\t%s\n' "$name" "copy-failed" >>"$RUNS/status.tsv"
        return
    fi
    /usr/bin/time -l "${ALARM_EXEC[@]}" "$RUN_TIMEOUT" arch "-$BENCH_ARCH" "$bin" run "$COREML_COPY" "$AUDIO" "$units" \
        "$RUNS/$name.txt" "$CM_WARM" >"$RUNS/$name.out" 2>"$RUNS/$name.err"
    local rc=$?
    printf '%s\t%s\n' "$name" "$rc" >>"$RUNS/status.tsv"
    if [ $rc -ne 0 ] || ! grep -q '^RESULT' "$RUNS/$name.out"; then
        record_error "$name" "exit code $rc" "$RUNS/$name.err"
        return
    fi
    grep '^RESULT' "$RUNS/$name.out"
    grep -E ' real ' "$RUNS/$name.err" || true
}

run_tcpp() {
    local quant=$1 threads=$2
    local name="tcpp-$BENCH_ARCH-$quant-t$threads"
    local model="$GGUF_DIR/parakeet-tdt-0.6b-v3-$quant.gguf"
    log "$name  (load $(sysctl -n vm.loadavg))"
    if [ ! -f "$model" ]; then
        record_error "$name" "missing $model"
        printf '%s\t%s\n' "$name" "no-model" >>"$RUNS/status.tsv"
        return
    fi
    /usr/bin/time -l "${ALARM_EXEC[@]}" "$RUN_TIMEOUT" arch "-$BENCH_ARCH" "$TCPP_BENCH" --model "$model" --sample "$AUDIO" \
        --backend cpu --threads "$threads" --warmup 0 --iters "$TC_ITERS" --json-out "$RUNS/$name.json" \
        2>"$RUNS/$name.err"
    local rc=$?
    printf '%s\t%s\n' "$name" "$rc" >>"$RUNS/status.tsv"
    if [ $rc -ne 0 ] || [ ! -s "$RUNS/$name.json" ]; then
        record_error "$name" "exit code $rc" "$RUNS/$name.err"
        rm -f "$RUNS/$name.json"
        return
    fi
    grep -E ' real ' "$RUNS/$name.err" || true
}

cmd_run() {
    local bin units rep quant threads
    bin="$(pbench_bin)/pbench"
    if [ -x "$bin" ] && coreml_complete "$COREML_DIR"; then
        for units in $CM_UNITS; do
            for rep in $(seq 1 "$CM_PROCS"); do
                run_coreml "$units" "$rep" "$bin"
            done
        done
    else
        record_error "coreml" "skipped: pbench or the CoreML models are missing"
    fi
    if [ -x "$TCPP_BENCH" ]; then
        for quant in $TC_QUANTS; do
            for threads in $TC_THREADS; do
                run_tcpp "$quant" "$threads"
            done
        done
    else
        record_error "transcribe.cpp" "skipped: transcribe-bench is not built"
    fi
    return 0
}

cmd_report() {
    python3 -I -B "$BENCH_DIR/scripts/aggregate.py" "$RUNS" "$REF_TEXT" >"$RUNS/summary.md"
    cat "$RUNS/summary.md"
}

cmd_all() {
    cmd_hwinfo
    cmd_build_tcpp || true
    cmd_fetch_gguf || true
    cmd_build_pbench || true
    cmd_fetch_coreml || true
    cmd_run
    cmd_report
}

case "${1:-}" in
hwinfo) cmd_hwinfo ;;
build-tcpp) cmd_build_tcpp ;;
fetch-gguf) cmd_fetch_gguf ;;
build-pbench) cmd_build_pbench ;;
coreml-rev) cmd_coreml_rev ;;
fetch-coreml) cmd_fetch_coreml ;;
run) cmd_run ;;
report) cmd_report ;;
all) cmd_all ;;
*)
    sed -n '2,25p' "$0"
    exit 2
    ;;
esac
