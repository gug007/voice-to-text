#!/usr/bin/env bash
set -euo pipefail

# Smoke test for the Intel slice's local transcription (transcribe.cpp in a
# worker process, `Engine/Intel/`), run natively on an Intel Mac by
# .github/workflows/intel-smoke.yml. On an Apple Silicon Mac the x86_64 steps
# run under Rosetta instead, which is how it is checked locally.
#
# usage: scripts/ci/intel-smoke.sh <step>
#   hardware       CPU, GPU, OS and toolchain
#   build-release  Release universal app, as release.yml builds it, unsigned
#   symbol-gate    arm64 slice free of ggml/transcribe.cpp/whisper symbols,
#                  x86_64 slice linking transcribe.cpp
#   build-debug    Debug x86_64 app, for the self-test
#   audio          speak the reference text into a 16 kHz mono WAV
#   models         fetch Parakeet and Whisper Base through the app's own
#                  pinned URL, size and SHA-256, or re-verify cached copies
#   smoke          the transcription cases; fails if any of them fails
#   summary        the results as a Markdown table
#
# Everything it writes goes under $SMOKE_DIR (default build/intel-smoke).
# Needs bash 3.2 (macOS's own), python3, perl, say and afconvert.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_DIR="$REPO_ROOT/VoiceToText"
SMOKE_DIR="${SMOKE_DIR:-$REPO_ROOT/build/intel-smoke}"
REFERENCE="$SCRIPT_DIR/intel-smoke-reference.txt"

# Its own preferences domain, so the GPU flag the cases set never reaches a
# real install, and each case starts from a known state.
DOMAIN="voice-to-text-ai.VoiceToText.intel-smoke"
RELEASE_APP="${RELEASE_APP:-$PROJECT_DIR/build/Build/Products/Release/VoiceToText.app}"
DEBUG_APP="$SMOKE_DIR/DerivedData/Build/Products/Debug/VoiceToText.app"
DEBUG_BIN="$DEBUG_APP/Contents/MacOS/VoiceToText"
AUDIO="$SMOKE_DIR/audio/speech.wav"
MODELS="$SMOKE_DIR/models"
LOGS="$SMOKE_DIR/logs"
RESULTS="$SMOKE_DIR/results.tsv"

# A transcript of synthesized speech, against the text it was synthesized
# from: the voice differs between macOS versions, so allow some slack.
MAX_WER_PERCENT="${SMOKE_MAX_WER_PERCENT:-10}"
# One self-test run may take this long before it counts as hung.
CASE_TIMEOUT_SECONDS=900

mkdir -p "$SMOKE_DIR" "$LOGS"

log() { printf '→ %s\n' "$*"; }
fail() { printf '✗ %s\n' "$*" >&2; exit 1; }

# Runs an x86_64 command: natively on Intel, under Rosetta on Apple Silicon.
run_x86() {
    if [ "$(uname -m)" = "arm64" ]; then
        arch -x86_64 "$@"
    else
        "$@"
    fi
}

now() { python3 -c 'import time; print(time.time())'; }
elapsed() { python3 -c "import sys; print(round(float(sys.argv[2]) - float(sys.argv[1]), 1))" "$1" "$2"; }

step_hardware() {
    sysctl -n machdep.cpu.brand_string
    echo "physical cores: $(sysctl -n hw.physicalcpu), logical: $(sysctl -n hw.logicalcpu), memory: $(sysctl -n hw.memsize)"
    echo "leaf 7: $(sysctl -n machdep.cpu.leaf7_features 2>/dev/null | tr ' ' '\n' | grep -E '^(AVX2|BMI2|AVX512F)$' | tr '\n' ' ' || true); features: $(sysctl -n machdep.cpu.features 2>/dev/null | tr ' ' '\n' | grep -E '^(FMA|F16C|AVX1.0)$' | tr '\n' ' ' || true)"
    echo "uname -m: $(uname -m)"
    sw_vers
    xcodebuild -version
    cmake --version | head -1
    python3 --version
    echo "--- GPU (system_profiler SPDisplaysDataType)"
    system_profiler SPDisplaysDataType 2>/dev/null || echo "(none reported)"
}

step_build_release() {
    log "building Release (universal, unsigned) as release.yml does"
    cd "$PROJECT_DIR"
    set +e
    xcodebuild \
        -project VoiceToText.xcodeproj \
        -scheme VoiceToText \
        -configuration Release \
        -derivedDataPath build \
        -destination 'generic/platform=macOS' \
        clean build \
        CODE_SIGNING_ALLOWED=NO \
        >"$LOGS/build-release.log" 2>&1
    local status=$?
    set -e
    tail -3 "$LOGS/build-release.log"
    if [ "$status" -ne 0 ]; then
        grep -E "error:" "$LOGS/build-release.log" | tail -30 || true
        fail "Release build failed ($status)"
    fi
}

# Defined symbols whose name starts with `prefix` in one slice.
count_symbols() {
    local slice=$1 binary=$2 prefix=$3
    nm -arch "$slice" "$binary" | awk -v p="$prefix" 'index($NF, p) == 1 { n++ } END { print n + 0 }'
}

step_symbol_gate() {
    local binary="$RELEASE_APP/Contents/MacOS/VoiceToText"
    [ -f "$binary" ] || fail "no Release binary at $binary; run build-release first"
    lipo -archs "$binary"
    local problems=0 prefix count
    for prefix in _ggml_ _transcribe_ _whisper_; do
        count="$(count_symbols arm64 "$binary" "$prefix")"
        echo "arm64  $prefix: $count"
        if [ "$count" -ne 0 ]; then
            echo "::error::the arm64 slice has $count $prefix symbols; Intel-only code leaked into the Apple Silicon build"
            problems=$((problems + 1))
        fi
    done
    for prefix in _transcribe_ _ggml_ _whisper_; do
        echo "x86_64 $prefix: $(count_symbols x86_64 "$binary" "$prefix")"
    done
    if [ "$(count_symbols x86_64 "$binary" _transcribe_)" -eq 0 ]; then
        echo "::error::the x86_64 slice doesn't link transcribe.cpp"
        problems=$((problems + 1))
    fi
    lipo -detailed_info "$binary" | grep -E '^architecture|^    size'
    [ "$problems" -eq 0 ] || fail "symbol gate failed"
    log "symbol gate passed"
}

step_build_debug() {
    log "building Debug (x86_64) for the self-test"
    cd "$PROJECT_DIR"
    set +e
    xcodebuild \
        -project VoiceToText.xcodeproj \
        -scheme VoiceToText \
        -configuration Debug \
        -derivedDataPath "$SMOKE_DIR/DerivedData" \
        -destination 'generic/platform=macOS' \
        build \
        ARCHS=x86_64 \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGNING_ALLOWED=NO \
        PRODUCT_BUNDLE_IDENTIFIER="$DOMAIN" \
        >"$LOGS/build-debug.log" 2>&1
    local status=$?
    set -e
    tail -3 "$LOGS/build-debug.log"
    if [ "$status" -ne 0 ]; then
        grep -E "error:" "$LOGS/build-debug.log" | tail -30 || true
        fail "Debug build failed ($status)"
    fi
    lipo -archs "$DEBUG_BIN"
}

step_audio() {
    mkdir -p "$SMOKE_DIR/audio"
    log "speaking the reference text ($(wc -w <"$REFERENCE" | tr -d ' ') words, voice: $(defaults read com.apple.speech.voice.prefs SelectedVoiceName 2>/dev/null || echo "system default"))"
    say -f "$REFERENCE" -o "$SMOKE_DIR/audio/speech.aiff"
    afconvert -f WAVE -d LEF32@16000 -c 1 "$SMOKE_DIR/audio/speech.aiff" "$AUDIO"
    afinfo "$AUDIO" | grep -E 'Data format|estimated duration'
}

step_models() {
    [ -x "$DEBUG_BIN" ] || fail "no Debug app at $DEBUG_BIN; run build-debug first"
    mkdir -p "$MODELS"
    VTT_TRANSCRIBE_MODELS_DIR="$MODELS" run_x86 "$DEBUG_BIN" --transcribe-fetch parakeet-tdt-v3 whisper-base
}

# Word error rate of `hypothesis` against the reference, in percent. Numbers
# are spelled out the way the reference spells them ("2.7" is "two point
# seven"), and case and punctuation are ignored.
wer_percent() {
    python3 - "$REFERENCE" "$1" <<'PY'
import re
import sys

ONES = "zero one two three four five six seven eight nine".split()
TEENS = "ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen".split()
TENS = "_ _ twenty thirty forty fifty sixty seventy eighty ninety".split()

def spell_int(s):
    n = int(s)
    if n < 10:
        return ONES[n]
    if n < 20:
        return TEENS[n - 10]
    if n < 100:
        return TENS[n // 10] + ("" if n % 10 == 0 else " " + ONES[n % 10])
    return s

def spell(match):
    s = match.group(0)
    if "." in s:
        whole, fraction = s.split(".", 1)
        return " ".join([spell_int(whole), "point"] + [ONES[int(c)] for c in fraction])
    return spell_int(s)

def words(text):
    text = re.sub(r"\d+(\.\d+)?", spell, text.lower())
    return re.sub(r"[^a-z0-9' ]+", " ", text).replace("'", "").split()

ref = words(open(sys.argv[1]).read())
hyp = words(sys.argv[2])
row = list(range(len(hyp) + 1))
for i in range(1, len(ref) + 1):
    previous, row[0] = row[0], i
    for j in range(1, len(hyp) + 1):
        current = row[j]
        row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (ref[i - 1] != hyp[j - 1]))
        previous = current
print(round(100.0 * row[len(hyp)] / max(len(ref), 1), 2))
PY
}

# Lines of the last self-test output.
field() { grep -m1 "$1" "$CASE_OUT" || true; }
last_run() { grep '^run ' "$CASE_OUT" | tail -1 || true; }

# One self-test run: `name model [VAR=value…]`. Sets CASE_STATUS, CASE_SECONDS,
# CASE_OUT, CASE_WER, CASE_TEXT.
selftest() {
    local name=$1 model=$2
    shift 2
    CASE_OUT="$LOGS/$name.out"
    local start end
    start="$(now)"
    set +e
    # perl's alarm stands in for `timeout`, which macOS doesn't ship.
    env VTT_TRANSCRIBE_MODELS_DIR="$MODELS" "$@" \
        perl -e 'alarm shift @ARGV; exec @ARGV or die "exec: $!\n"' "$CASE_TIMEOUT_SECONDS" \
        "$0" __x86 "$DEBUG_BIN" --transcribe-selftest "$model" "$AUDIO" \
        >"$CASE_OUT" 2>"$LOGS/$name.err"
    CASE_STATUS=$?
    set -e
    end="$(now)"
    CASE_SECONDS="$(elapsed "$start" "$end")"
    CASE_TEXT="$(grep '^text: ' "$CASE_OUT" | tail -1 | sed 's/^text: //' || true)"
    if [ -n "$CASE_TEXT" ]; then
        CASE_WER="$(wer_percent "$CASE_TEXT")"
    else
        CASE_WER="-"
    fi
    echo "=== $name: exit $CASE_STATUS, $CASE_SECONDS s, WER $CASE_WER%"
    grep -v '^text: ' "$CASE_OUT" | sed 's/^/    /' || true
}

# Records the case and its problems (none means it passed).
FAILED_CASES=0
record() {
    local name=$1 problems=$2
    local device worker registered timings=""
    # Where the transcription finished, which after a fallback isn't where
    # the model first loaded.
    device="$(last_run | sed -n 's/.* device=\(.*\) backend=\([^ ]*\) worker=.*/\1 (\2)/p')"
    worker="$(last_run | sed -n 's/.* worker=\([a-z-]*\).*/\1/p')"
    registered="$(grep '^registered: ' "$CASE_OUT" | awk '{ print $2 }' | tr '\n' ' ' | sed 's/ $//' || true)"
    if [ -n "$(last_run)" ]; then
        timings="$(field '^load: ' | sed -e 's/^load: //' -e 's/ (library.*//') load, $(last_run | sed -e 's/^run [0-9]*: //' -e 's/ (mel.*//') run"
    fi
    local result="pass"
    if [ -n "$problems" ]; then
        result="FAIL"
        FAILED_CASES=$((FAILED_CASES + 1))
        echo "::error::$name: $problems"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$name" "$result" "$CASE_SECONDS" "${timings:--}" "${registered:--}" "${device:--}" "${worker:--}" "$CASE_WER" "${problems:--}" >>"$RESULTS"
}

# The problems every case shares: it must exit cleanly with a transcript
# close to the reference.
common_problems() {
    local problems=""
    [ "$CASE_STATUS" -eq 0 ] || problems="exited $CASE_STATUS ($(grep -m1 '^FAILED' "$CASE_OUT" || tail -1 "$LOGS/$1.err"))"
    if [ "$CASE_WER" = "-" ]; then
        problems="${problems:+$problems; }no transcript"
    elif python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) <= float(sys.argv[2]) else 1)" "$CASE_WER" "$MAX_WER_PERCENT"; then
        :
    else
        problems="${problems:+$problems; }WER $CASE_WER% over $MAX_WER_PERCENT%"
    fi
    printf '%s' "$problems"
}

reset_preferences() {
    defaults delete "$DOMAIN" >/dev/null 2>&1 || true
}

# Worker processes of this build still running.
leftover_workers() {
    local pid count=0
    for pid in $(pgrep -f -- '--transcribe-worker' || true); do
        # Not the full path: the app names itself by its resolved path.
        if ps -o command= -p "$pid" | grep -qF "Products/Debug/VoiceToText.app/Contents/MacOS/VoiceToText"; then
            count=$((count + 1))
        fi
    done
    echo "$count"
}

step_smoke() {
    [ -x "$DEBUG_BIN" ] || fail "no Debug app at $DEBUG_BIN; run build-debug first"
    [ -f "$AUDIO" ] || fail "no audio at $AUDIO; run audio first"
    : >"$RESULTS"
    local parakeet=parakeet-tdt-v3 whisper=whisper-base problems

    # (a) Parakeet as installed: GPU allowed. The runner may have no usable
    # Metal device, a paravirtual one, or one that fails; any of those is fine
    # as long as the transcript is right.
    reset_preferences
    selftest a-parakeet-default "$parakeet"
    problems="$(common_problems a-parakeet-default)"
    record a-parakeet-default "$problems"

    # (b) Parakeet with the GPU switched off.
    reset_preferences
    defaults write "$DOMAIN" transcribeCpp.useGPU -bool false
    selftest b-parakeet-cpu "$parakeet"
    problems="$(common_problems b-parakeet-cpu)"
    grep -q 'worker=cpu-only' "$CASE_OUT" || problems="${problems:+$problems; }worker wasn't CPU-only"
    grep '^registered: ' "$CASE_OUT" | grep -qv '^registered: cpu ' && problems="${problems:+$problems; }a CPU-only worker registered a non-CPU device"
    record b-parakeet-cpu "$problems"

    # (c) A GPU-capable worker that crashes in the transcription: recovered
    # on the CPU, and the GPU marked failed.
    reset_preferences
    selftest c-parakeet-crash-on-run "$parakeet" VTT_WORKER_FAULT=crash-on-run
    problems="$(common_problems c-parakeet-crash-on-run)"
    last_run | grep -q 'worker=cpu-only' || problems="${problems:+$problems; }didn't finish in a CPU-only worker"
    grep -q '^gpu preference after: .*gpuFailed=true' "$CASE_OUT" || problems="${problems:+$problems; }GPU not marked failed"
    record c-parakeet-crash-on-run "$problems"

    # (d) The next run, with the flag (c) left: CPU-only from the start.
    selftest d-parakeet-after-failure "$parakeet"
    problems="$(common_problems d-parakeet-after-failure)"
    grep -q '^gpu preference: .*gpuFailed=true' "$CASE_OUT" || problems="${problems:+$problems; }the GPU failure didn't persist"
    grep -q '^load: .*worker=cpu-only' "$CASE_OUT" || problems="${problems:+$problems; }didn't start CPU-only"
    record d-parakeet-after-failure "$problems"

    # (e) Whisper Base as installed.
    reset_preferences
    selftest e-whisper-base-default "$whisper"
    problems="$(common_problems e-whisper-base-default)"
    record e-whisper-base-default "$problems"
    reset_preferences

    # (f) Every worker gone once its app has.
    local left waited=0
    left="$(leftover_workers)"
    while [ "$left" -ne 0 ] && [ "$waited" -lt 10 ]; do
        sleep 1
        waited=$((waited + 1))
        left="$(leftover_workers)"
    done
    CASE_OUT=/dev/null CASE_SECONDS="$waited" CASE_WER="-"
    if [ "$left" -eq 0 ]; then
        record f-no-leftover-workers ""
    else
        record f-no-leftover-workers "$left worker processes still running"
    fi

    step_summary
    [ "$FAILED_CASES" -eq 0 ] || fail "$FAILED_CASES case(s) failed"
    log "all cases passed"
}

step_summary() {
    [ -f "$RESULTS" ] || fail "no results at $RESULTS"
    {
        local how="native x86_64"
        [ "$(uname -m)" = "arm64" ] && how="x86_64 under Rosetta"
        echo "### Intel smoke: $(sysctl -n machdep.cpu.brand_string), $how"
        echo
        echo "| Case | Result | Total s | Load, last run | Registered | Ran on | Worker | WER % | Problems |"
        echo "|---|---|---|---|---|---|---|---|---|"
        awk -F '\t' '{ printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6, $7, $8, $9 }' "$RESULTS"
    } >"$SMOKE_DIR/summary.md"
    cat "$SMOKE_DIR/summary.md"
}

case "${1:-}" in
    hardware) step_hardware ;;
    build-release) step_build_release ;;
    symbol-gate) step_symbol_gate ;;
    build-debug) step_build_debug ;;
    audio) step_audio ;;
    models) step_models ;;
    smoke) step_smoke ;;
    summary) step_summary ;;
    # Internal: `perl`'s exec can't call a shell function.
    __x86)
        shift
        run_x86 "$@"
        ;;
    *)
        sed -n '/^# usage:/,/^#   summary/p' "$0" >&2
        exit 64
        ;;
esac
