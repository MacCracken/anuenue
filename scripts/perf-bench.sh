#!/bin/sh
# perf-bench.sh — end-to-end per-byte overhead measurement.
#
# Times `cat fixture > /dev/null` vs `anuenue < fixture > /dev/null`
# over N runs and reports (anuenue_ns - cat_ns) / corpus_bytes — the
# wall-clock ns/byte anuenue adds on top of the kernel's pipe path.
# This is the M5 ratchet: every minor cut should keep this number
# below the v0.4.0 floor (86 ns/byte) and progress toward the M5
# acceptance (≤ 60 ns/byte) and v0.3.0 ceiling (53 ns/byte).
#
# docs/benchmarks.md captures the trend per release; this script is
# what produces the numbers.
#
# Usage:
#   sh scripts/perf-bench.sh           # default 7 runs, ascii + utf8
#   RUNS=11 sh scripts/perf-bench.sh   # more samples → tighter median
#   FIXTURE_BYTES=2800000 sh ...       # larger corpus for noisier hosts
#   BIN=build/anuenue-old sh ...       # bench a different binary
#   COLOR=256 sh scripts/perf-bench.sh # 256 / 16 instead of truecolor
#
# COLOR (v1.4.0) exists because the phase-cached escape table's value
# differs by mode: deleting it was measured −15% on truecolor and
# +33% / +42% on 256 / 16 (docs/benchmarks.md § v1.4.0). A harness
# that could only measure truecolor would have recommended deleting it.

set -eu

BIN="${BIN:-build/anuenue}"
COLOR="${COLOR:-24bit}"
case "$COLOR" in
    24bit|truecolor|256|16) ;;
    *) echo "perf-bench: COLOR must be 24bit, 256 or 16 (got '$COLOR')" >&2; exit 2 ;;
esac
RUNS="${RUNS:-7}"
FIXTURE_BYTES="${FIXTURE_BYTES:-1400000}"   # ~1.4 MB matches docs/benchmarks.md baseline

if [ ! -x "$BIN" ]; then
    echo "perf-bench: $BIN not executable — run 'cyrius build src/main.cyr build/anuenue' first" >&2
    exit 1
fi

# Coreutils' /usr/bin/date supports %N (ns); BSD date does not. Bail
# loudly if we can't get sub-ms resolution rather than emit garbage.
sample=$(date +%s%N 2>/dev/null || true)
case "$sample" in
    *N|"") echo "perf-bench: date +%s%N unsupported on this host (need GNU coreutils)" >&2; exit 2 ;;
esac
unset sample

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

FX_ASCII="$WORK/ascii.fx"
FX_ASCII_LF="$WORK/ascii_lf.fx"
FX_UTF8="$WORK/utf8.fx"

# --- corpus generation --------------------------------------------
# 1. ASCII no-LF: base64 -w0 of /dev/urandom, padded/trimmed to the
#    target byte count. All bytes are printable ASCII; the filter
#    loop force-flushes when the line buffer fills (no LF in the
#    stream means no line-LF flushes — only ANUENUE_FLUSH_RESERVE-
#    triggered flushes). Worst case for per-byte overhead.
base64 -w0 /dev/urandom 2>/dev/null | head -c "$FIXTURE_BYTES" > "$FX_ASCII" \
    || { echo "perf-bench: ASCII corpus generation failed (no base64 -w0?)" >&2; exit 3; }
ASCII_BYTES=$(wc -c < "$FX_ASCII")

# 2. ASCII with-LF: same but wrapped (default base64 wrap = 76 cols),
#    so the filter exercises its LF-flush path on the typical-MOTD-
#    sized line cadence. ~13 LFs per 1 KB of input.
base64 /dev/urandom 2>/dev/null | head -c "$FIXTURE_BYTES" > "$FX_ASCII_LF" \
    || { echo "perf-bench: ASCII-LF corpus generation failed" >&2; exit 3; }
ASCII_LF_BYTES=$(wc -c < "$FX_ASCII_LF")

# 3. UTF-8: the M3 mixed corpus the v0.4.0 benchmarks doc cites —
#    "AGNOS Привет 日本 🌈 rainbow \n" repeated. ~39 bytes/iter; 1000
#    iters ≈ 39 KB. Bumped to match FIXTURE_BYTES so the per-byte
#    statistics line up with the ASCII runs.
UTF8_LINE="AGNOS Привет 日本 🌈 rainbow "
UTF8_LINE_LEN=$(printf %s "$UTF8_LINE" | wc -c)
UTF8_ITERS=$(( FIXTURE_BYTES / UTF8_LINE_LEN ))
{
    i=0
    while [ "$i" -lt "$UTF8_ITERS" ]; do
        printf %s "$UTF8_LINE"
        i=$((i + 1))
    done
    printf '\n'
} > "$FX_UTF8"
UTF8_BYTES=$(wc -c < "$FX_UTF8")

# --- timer ---------------------------------------------------------
# Time a single pipeline; print elapsed nanoseconds to stdout.
time_ns() {
    cmd="$1"
    before=$(date +%s%N)
    sh -c "$cmd"
    after=$(date +%s%N)
    echo $((after - before))
}

# Run a pipeline RUNS times; print median of the run set.
# Median tolerates outliers (e.g. one slow scheduler hiccup) better
# than the mean does — the M1 baseline used mean-of-3 which is fine
# for a quiet host but jitters by 5-10% on a loaded one.
median_ns() {
    cmd="$1"
    samples="$WORK/samples"
    : > "$samples"
    r=0
    while [ "$r" -lt "$RUNS" ]; do
        time_ns "$cmd" >> "$samples"
        r=$((r + 1))
    done
    sort -n "$samples" | awk -v n="$RUNS" 'NR == int(n/2) + 1 { print; exit }'
}

# --- one corpus block ----------------------------------------------
# Args: corpus_path corpus_label corpus_bytes
bench_corpus() {
    fx="$1"
    label="$2"
    bytes="$3"

    cat_med=$(median_ns "cat '$fx' > /dev/null")
    # --color=$COLOR (24bit by default) forces a colour path regardless
    # of TTY state. Without it, perf-bench's piped stdout triggers M6's
    # auto-detect → MONO and we'd benchmark the passthrough instead of
    # the filter's hot path.
    ane_med=$(median_ns "'$BIN' --color=$COLOR < '$fx' > /dev/null")

    # ns/byte overhead anuenue adds on top of the kernel's bare pipe.
    overhead_ns=$((ane_med - cat_med))
    per_byte_x100=$((overhead_ns * 100 / bytes))   # *100 to print 2dp without bc

    cat_ms=$((cat_med / 1000000))
    ane_ms=$((ane_med / 1000000))

    printf '  %-18s  cat=%4d ms  anuenue=%4d ms  overhead=%4d ms  → %d.%02d ns/byte\n' \
        "$label" "$cat_ms" "$ane_ms" $((overhead_ns / 1000000)) \
        $((per_byte_x100 / 100)) $((per_byte_x100 % 100))
}

# --- driver --------------------------------------------------------
echo "perf-bench: $BIN  (runs=$RUNS  fixture≈${FIXTURE_BYTES} B  --color=$COLOR)"
echo
echo "ASCII corpora ($ASCII_BYTES B / $ASCII_LF_BYTES B), UTF-8 corpus ($UTF8_BYTES B):"
bench_corpus "$FX_ASCII"    "ascii (no LF)"  "$ASCII_BYTES"
bench_corpus "$FX_ASCII_LF" "ascii (w/ LFs)" "$ASCII_LF_BYTES"
bench_corpus "$FX_UTF8"     "utf8 mixed"     "$UTF8_BYTES"
echo
echo "M5 acceptance: ascii (no LF) ≤ 60 ns/byte."
