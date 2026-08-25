#!/bin/sh
# observe-check.sh — the v1.2.1 observability gate.
#
# tests/anuenue.tcyr covers the pure parts of the sakshi/agnostik
# wiring (level parsing, reason recording, kind → exit-code mapping).
# What a unit test CANNOT cover is the property that actually matters
# for a pipe filter:
#
#   turning logging on must not move a single byte of stdout.
#
# anuenue's whole reason to exist is being safe in the middle of a
# pipeline (ADR 0001, pipe-purity). A diagnostics feature that leaked
# one byte onto fd 1 would silently corrupt every `iam | anuenue |
# ...` it was enabled in. That is a process-level, fd-level property,
# so it gets a process-level test.
#
# Four gates:
#   1. stdout is byte-identical with and without every verbosity flag
#   2. stderr is EMPTY at default verbosity (a filter is silent until
#      asked) — including for input that is entirely invalid UTF-8
#   3. -v actually produces records, and they carry the fields a bug
#      report needs (version, colour mode, colour REASON, route)
#   4. a real failure path emits an agnostik-typed error with its
#      numeric code, and still exits with the v1.x code
#
# Usage:
#   sh scripts/observe-check.sh
#   BIN=build/anuenue-dce sh scripts/observe-check.sh

set -eu

BIN="${BIN:-build/anuenue}"

if [ ! -x "$BIN" ]; then
    echo "observe-check: $BIN not executable — run 'cyrius build src/main.cyr build/anuenue' first" >&2
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

FAIL=0
ok()   { echo "  ok: $1"; }
bad()  { echo "  FAIL: $1"; FAIL=1; }

# --- corpora -------------------------------------------------------
# Deliberately includes input that exercises the paths most likely to
# interleave a stray write: multi-byte clusters, a combining run that
# forces mid-cluster flushes, and raw invalid bytes.
printf 'AGNOS\n'                                        > "$WORK/ascii.in"
printf 'no trailing newline'                            > "$WORK/nolf.in"
printf ''                                               > "$WORK/empty.in"
printf 'caf\xc3\xa9 \xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e\n' > "$WORK/utf8.in"
printf '\xff\xfe \xc0\x80 invalid\n'                    > "$WORK/invalid.in"
awk 'BEGIN{printf "a"; for(i=0;i<4000;i++) printf "\xcc\x81"; printf "\n"}' > "$WORK/cluster.in"

CORPORA="ascii nolf empty utf8 invalid cluster"
MODES="--color=24bit --color=256 --color=16 --color=none"
VERBS="-v --log-level=trace --log-level=debug --log-level=info --log-level=warn --log-level=off"

# --- gate 1: stdout is untouched by verbosity ----------------------
echo "[observe-check] pipe-purity — stdout must not move"
CMP=0
for c in $CORPORA; do
    for m in $MODES; do
        base=$("$BIN" "$m" -s 42 < "$WORK/$c.in" 2>/dev/null | cksum)
        for v in $VERBS; do
            CMP=$((CMP + 1))
            got=$("$BIN" "$m" -s 42 "$v" < "$WORK/$c.in" 2>/dev/null | cksum)
            if [ "$base" != "$got" ]; then
                bad "stdout changed: corpus=$c mode=$m verb=$v"
            fi
        done
    done
done
[ "$FAIL" -eq 0 ] && ok "stdout byte-identical across $CMP verbosity comparisons"

# --- gate 2: silence by default ------------------------------------
echo "[observe-check] default verbosity — stderr must be empty"
NOISE=0
for c in $CORPORA; do
    for m in $MODES; do
        "$BIN" "$m" -s 42 < "$WORK/$c.in" > /dev/null 2> "$WORK/err"
        sz=$(wc -c < "$WORK/err")
        if [ "$sz" -ne 0 ]; then
            bad "stderr not empty at default verbosity: corpus=$c mode=$m ($sz bytes)"
            NOISE=$((NOISE + 1))
        fi
    done
done
[ "$NOISE" -eq 0 ] && ok "stderr empty in every default-verbosity run"

# Explicit --log-level=off must be as silent as no flag at all.
"$BIN" --color=24bit --log-level=off < "$WORK/utf8.in" > /dev/null 2> "$WORK/err"
if [ "$(wc -c < "$WORK/err")" -eq 0 ]; then
    ok "--log-level=off is silent"
else
    bad "--log-level=off wrote to stderr"
fi

# --- gate 3: -v produces the fields a bug report needs -------------
echo "[observe-check] -v content"
"$BIN" --color=24bit -v < "$WORK/ascii.in" > /dev/null 2> "$WORK/v.err"

check_field() {
    if grep -q "$1" "$WORK/v.err"; then ok "-v reports $2"; else bad "-v missing $2"; fi
}
check_field 'ENTER'                 "a span enter"
check_field 'EXIT'                  "a span exit"
check_field 'version='              "the version"
check_field 'phase-step='           "the resolved phase step"
check_field 'mode=24bit'            "the resolved colour mode"
check_field 'reason='               "WHY that colour mode was chosen"
check_field 'route=filter'          "the dispatch route"
check_field 'bytes-in='             "the byte count"

# The reason must be a real branch, not the UNSET placeholder — that
# would mean detect returned without recording which path it took.
if grep -q 'reason=unset' "$WORK/v.err"; then
    bad "-v reports reason=unset (a detect branch failed to record)"
else
    ok "-v reports a concrete colour-mode reason (never 'unset')"
fi

# Colour reason must actually track the input, not be hardcoded.
NO_COLOR=1 "$BIN" -v < "$WORK/ascii.in" > /dev/null 2> "$WORK/v2.err"
if grep -q 'reason=NO_COLOR env present' "$WORK/v2.err"; then
    ok "-v attributes MONO to the NO_COLOR env var"
else
    bad "-v did not attribute MONO to NO_COLOR"
fi
if grep -q 'route=passthrough' "$WORK/v2.err"; then
    ok "-v reports the passthrough route under NO_COLOR"
else
    bad "-v did not report the passthrough route"
fi

# Level filtering has to actually filter: warn must not carry debug lines.
"$BIN" --color=24bit --log-level=warn < "$WORK/ascii.in" > /dev/null 2> "$WORK/w.err"
if grep -q 'DEBUG' "$WORK/w.err"; then
    bad "--log-level=warn leaked DEBUG records"
else
    ok "--log-level=warn suppresses DEBUG records"
fi
# Spans are a debugging aid and sakshi does NOT level-gate them, so
# anuenue gates them at debug-or-finer itself. Without that gate a
# --log-level=error run still printed ENTER/EXIT around its errors.
if grep -qE 'ENTER|EXIT' "$WORK/w.err"; then
    bad "--log-level=warn emitted span records (spans must be debug-or-finer)"
else
    ok "--log-level=warn emits no span records"
fi
# A clean warn run on good input should be completely silent.
if [ "$(wc -c < "$WORK/w.err")" -eq 0 ]; then
    ok "--log-level=warn is silent when nothing warns"
else
    bad "--log-level=warn wrote $(wc -c < "$WORK/w.err") bytes on a clean run"
fi

# --- gate 4: typed failure path ------------------------------------
echo "[observe-check] agnostik-typed failure"
# Closing stdin makes read(2) return EBADF — a real error path, not a
# simulated one.
set +e
"$BIN" --color=24bit -v 0<&- > /dev/null 2> "$WORK/f.err"
RC=$?
set -e
if [ "$RC" -eq 1 ]; then
    ok "read failure exits 1 (v1.x contract)"
else
    bad "read failure exited $RC, expected 1"
fi
if grep -q 'i/o error: read from stdin failed' "$WORK/f.err"; then
    ok "read failure names the agnostik error kind"
else
    bad "read failure did not print the agnostik kind"
fi
if grep -q 'code=1010' "$WORK/f.err"; then
    ok "read failure logs agnostik CODE_IO (1010)"
else
    bad "read failure did not log CODE_IO"
fi

# A bad --log-level is a usage error, and must say so rather than
# silently defaulting to a level the user did not ask for.
set +e
"$BIN" --log-level=loud < "$WORK/ascii.in" > /dev/null 2> "$WORK/l.err"
RC=$?
set -e
if [ "$RC" -eq 2 ]; then
    ok "bad --log-level exits 2 (usage)"
else
    bad "bad --log-level exited $RC, expected 2"
fi
if grep -q 'invalid argument: --log-level must be one of' "$WORK/l.err"; then
    ok "bad --log-level explains the accepted values"
else
    bad "bad --log-level did not explain the accepted values"
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "observe-check: PASS"
    exit 0
fi
echo "observe-check: FAIL"
exit 1
