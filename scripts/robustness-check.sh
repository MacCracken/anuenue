#!/bin/sh
# robustness-check.sh — end-to-end input and flag robustness.
#
# Added by the 2026-08-25 P-1 audit. The unit suite covers the
# classifier and parser functions in isolation; the fuzz harnesses
# cover them under seeded random input. Neither runs the actual
# binary against adversarial BYTE STREAMS or adversarial ARGV, which
# is where three of the audit's findings lived.
#
# Four gates:
#
#   1. Chunk-boundary carry. anuenue reads stdin in 4096-byte chunks
#      and carries a partial UTF-8 sequence across the boundary. A
#      sequence split 1/3, 2/2 or 3/1 across that boundary must
#      produce byte-identical output to the same input delivered one
#      byte at a time. This is the property the carry_len logic
#      exists for, and nothing else tests it end to end.
#
#   2. Byte preservation under malformed UTF-8. anuenue's contract is
#      that it colours a stream without altering it. Strip the SGR
#      escapes back out and the result must equal the input, byte for
#      byte, for overlong encodings, surrogates, codepoints above
#      U+10FFFF, lone continuations, truncation at EOF, embedded NULs
#      and every one of the 256 byte values.
#
#   3. Argv extremes. Integer flags take i64 from argv. Every value
#      from i64::MIN to i64::MAX must terminate with a documented
#      exit code (0, 1 or 2) — never a signal, never a hang.
#
#   4. One process-level regression per audit finding
#      (A-02 / A-03 / A-04 / A-05 / A-09).
#   5. Stdout write failures are reported rather than swallowed
#      (E-01) — and EPIPE still behaves as SIGPIPE.
#
# Usage:
#   sh scripts/robustness-check.sh
#   BIN=build/anuenue-dce sh scripts/robustness-check.sh

set -eu

BIN="${BIN:-build/anuenue}"

if [ ! -x "$BIN" ]; then
    echo "robustness-check: $BIN not executable — run 'cyrius build src/main.cyr build/anuenue' first" >&2
    exit 1
fi

command -v python3 >/dev/null 2>&1 || {
    echo "robustness-check: python3 required to build the byte corpora" >&2; exit 2; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

FAIL=0
ok()  { echo "  ok: $1"; }
bad() { echo "  FAIL: $1"; FAIL=1; }

# Strip SGR escapes without needing perl.
strip_sgr() { python3 -c '
import sys,re
d=sys.stdin.buffer.read()
sys.stdout.buffer.write(re.sub(rb"\x1b\[[0-9;]*m", b"", d))
'; }

# --- corpora -------------------------------------------------------
python3 - "$WORK" <<'PY'
import sys, os
w = sys.argv[1]
os.makedirs(w + "/carry", exist_ok=True)
os.makedirs(w + "/mal", exist_ok=True)

CHUNK = 4096                      # must match ANUENUE_READ_CHUNK
for name, seq in (("emoji4", "\U0001F600".encode()),
                  ("cjk3",   "日".encode()),
                  ("acc2",   "é".encode())):
    for split in range(len(seq) + 1):
        # `split` bytes of the sequence land in the first chunk.
        open(f"{w}/carry/{name}-s{split}.in", "wb").write(
            b"a" * (CHUNK - split) + seq + b"z\n")
# A grapheme cluster (base + combining marks) straddling the boundary.
open(f"{w}/carry/cluster-straddle.in", "wb").write(
    b"a" * (CHUNK - 3) + b"e" + "́".encode() * 40 + b"\n")

mal = {
    "overlong-2":      b"\xc0\xaf\n",
    "overlong-3":      b"\xe0\x80\xaf\n",
    "overlong-4":      b"\xf0\x80\x80\xaf\n",
    "surrogate-d800":  b"\xed\xa0\x80\n",
    "surrogate-dfff":  b"\xed\xbf\xbf\n",
    "above-10ffff":    b"\xf4\x90\x80\x80\n",
    "f5-ff":           bytes(range(0xf5, 0x100)) + b"\n",
    "lone-cont":       b"\x80\x81\x82\xbf\n",
    "c0-c1":           b"\xc0\xc1\n",
    "trunc-2":         b"\xc3\n",
    "trunc-3":         b"\xe6\x97\n",
    "trunc-4":         b"\xf0\x9f\x98\n",
    "eof-trunc-4":     b"\xf0\x9f\x98",
    "all-256":         bytes(range(256)),
    "nul-embedded":    b"a\x00b\x00c\n",
    "empty":           b"",
}
for k, v in mal.items():
    open(f"{w}/mal/{k}.in", "wb").write(v)
PY

MODES="--color=24bit --color=256 --color=16 --color=none"

# --- gate 1: chunk-boundary carry ----------------------------------
echo "[robustness] UTF-8 carry across the 4096-byte read boundary"
N=0; D=0
for f in "$WORK"/carry/*.in; do
    for m in $MODES; do
        N=$((N + 1))
        a=$("$BIN" "$m" -s 7 < "$f" 2>/dev/null | cksum)
        # dd bs=1 forces one read(2) per byte, so every sequence is
        # split at every possible offset rather than just the one the
        # 4096 boundary happens to produce.
        b=$(dd if="$f" bs=1 2>/dev/null | "$BIN" "$m" -s 7 2>/dev/null | cksum)
        [ "$a" = "$b" ] || { bad "carry mismatch: $(basename "$f") $m"; D=$((D + 1)); }
    done
done
[ "$D" -eq 0 ] && ok "chunked and byte-at-a-time reads agree ($N comparisons)"

# --- gate 2: byte preservation under malformed UTF-8 ---------------
echo "[robustness] byte preservation under malformed UTF-8"
N=0; D=0
for f in "$WORK"/mal/*.in "$WORK"/carry/*.in; do
    raw=$(cksum < "$f")
    for m in $MODES; do
        N=$((N + 1))
        got=$("$BIN" "$m" < "$f" 2>/dev/null | strip_sgr | cksum)
        [ "$got" = "$raw" ] || { bad "byte loss: $(basename "$f") $m"; D=$((D + 1)); }
    done
done
[ "$D" -eq 0 ] && ok "escape-stripped output equals input ($N comparisons)"

# Animation must survive the same corpus structurally.
echo "[robustness] animation survives the malformed corpus"
D=0
for f in "$WORK"/mal/*.in; do
    if ! timeout 10 "$BIN" -a -d 1 --color=24bit < "$f" >/dev/null 2>&1; then
        bad "animate failed on $(basename "$f")"; D=$((D + 1))
    fi
done
[ "$D" -eq 0 ] && ok "animate exits clean on every malformed input"

# --- gate 3: argv extremes -----------------------------------------
echo "[robustness] integer flags at the i64 extremes"
D=0
EXTREMES="0 1 -1 255 1530 -1530 2147483647 -2147483648 9223372036854775807 -9223372036854775808"
for flag in -p -s -F; do
    for v in $EXTREMES; do
        set +e
        printf 'AGNOS\n' | timeout 10 "$BIN" --color=24bit "$flag" "$v" >/dev/null 2>&1
        rc=$?
        set -e
        case "$rc" in
            0|1|2) : ;;
            124)   bad "$flag $v HUNG"; D=$((D + 1)) ;;
            *)     bad "$flag $v died with rc=$rc (signal $((rc - 128)))"; D=$((D + 1)) ;;
        esac
    done
done
[ "$D" -eq 0 ] && ok "-p / -s / -F terminate with a documented code at every extreme"

# --- gate 4: audit regressions at the process level ----------------
echo "[robustness] 2026-08-25 audit regressions"

# A-02: a duration too large to convert to ns must still RUN, not
# exit after one frame. Before the clamp, i64::MAX put the deadline
# one second in the past.
set +e
printf 'AGNOS\n' | timeout 3 "$BIN" -a --color=24bit -d 9223372036854775807 >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 124 ]; then
    ok "A-02: huge --duration keeps running (was: exited after one frame)"
else
    bad "A-02: huge --duration exited rc=$rc instead of continuing"
fi

# ...while an ordinary duration still expires on time.
set +e
printf 'AGNOS\n' | timeout 10 "$BIN" -a --color=24bit -d 1 >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] && ok "A-02: --duration 1 still exits 0 on time" \
                || bad "A-02: --duration 1 exited rc=$rc"

# A-03: a negative duration used to mean "run forever" by falling
# through to the 0 sentinel.
set +e
printf 'AGNOS\n' | timeout 10 "$BIN" -a --color=24bit -d -1 >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ] && ok "A-03: negative --duration is a usage error" \
                || bad "A-03: negative --duration exited rc=$rc, expected 2"

# A-04: an unknown --color value used to silently mean auto.
set +e
printf 'AGNOS\n' | timeout 10 "$BIN" --color=trucolor >/dev/null 2>"$WORK/c.err"
rc=$?
set -e
if [ "$rc" -eq 2 ] && grep -q 'invalid argument: --color must be one of' "$WORK/c.err"; then
    ok "A-04: typo'd --color is a usage error that lists the valid values"
else
    bad "A-04: --color=trucolor exited rc=$rc without a usable message"
fi

# A-09: `mono` was documented from M6 (docs/examples/06-no-color.sh
# runs it) but the parser never had a branch for it — the silent
# AUTO fallback made the broken example exit 0. Implemented at
# v1.2.2; assert it forces MONO rather than merely being accepted.
out=$(printf 'AGNOS\n' | "$BIN" --color=mono 2>/dev/null | cksum)
raw=$(printf 'AGNOS\n' | cksum)
[ "$out" = "$raw" ] && ok "A-09: --color=mono passes bytes through unchanged" \
                    || bad "A-09: --color=mono did not force MONO"

# ...and every documented value still works.
D=0
for c in auto 24bit truecolor 256 16 none mono off never; do
    printf 'AGNOS\n' | "$BIN" --color="$c" >/dev/null 2>&1 \
        || { bad "A-04: --color=$c wrongly rejected"; D=$((D + 1)); }
done
[ "$D" -eq 0 ] && ok "A-04/A-09: all nine documented --color values accepted"

# A-05: the animation caps drop input, so they must be announced.
python3 -c 'import sys; sys.stdout.write("x" * 200000 + "\n")' > "$WORK/big.in"
timeout 20 "$BIN" -a -d 1 --color=24bit --log-level=warn < "$WORK/big.in" \
    >/dev/null 2>"$WORK/t.err" || true
if grep -q 'truncated' "$WORK/t.err"; then
    ok "A-05: over-cap animation input warns that text was dropped"
else
    bad "A-05: 200 KB animation input was truncated silently"
fi

# --- gate 5: the write path must not lose bytes in silence ---------
#
# E-01 (2026-08-25 P-1 sweep). `file_write` is a bare `sys_write` with
# no short-write loop, and every stdout write discarded its return.
# Measured before the fix: `> /dev/full` lost 100% of the output and
# `> <nonblocking pipe>` lost 99.3%, both with exit 0. For a filter
# whose contract is byte preservation, that is the worst available
# failure mode.
echo "[robustness] stdout write failures are reported, not swallowed"

if [ ! -c /dev/full ]; then
    echo "  SKIP: /dev/full unavailable — cannot force a write failure"
else
    D=0
    for m in "--color=24bit" "--color=256" "--color=16" "--color=none"; do
        set +e
        "$BIN" "$m" < "$WORK/mal/all-256.in" > /dev/full 2>"$WORK/full.err"
        rc=$?
        set -e
        if [ "$rc" -ne 1 ]; then
            bad "write to /dev/full with $m exited $rc, expected 1"; D=$((D + 1))
        elif ! grep -q 'write to stdout failed' "$WORK/full.err"; then
            bad "write to /dev/full with $m exited 1 but said nothing"; D=$((D + 1))
        fi
    done
    [ "$D" -eq 0 ] && ok "every colour mode reports a failed write and exits 1"

    # The animation and positional-text paths write through different
    # call sites and were equally silent.
    set +e
    timeout 20 "$BIN" -a -d 1 --color=24bit < "$WORK/mal/nul-embedded.in" > /dev/full 2>"$WORK/f2.err"
    rc=$?
    set -e
    if [ "$rc" -eq 1 ] && grep -q 'write to stdout failed' "$WORK/f2.err"; then
        ok "animation reports a failed write and exits 1"
    else
        bad "animation to /dev/full: rc=$rc, message missing"
    fi

    set +e
    "$BIN" --color=24bit AGNOS > /dev/full 2>"$WORK/f3.err"
    rc=$?
    set -e
    if [ "$rc" -eq 1 ] && grep -q 'write to stdout failed' "$WORK/f3.err"; then
        ok "positional-text mode reports a failed write and exits 1"
    else
        bad "positional text to /dev/full: rc=$rc, message missing"
    fi
fi

# A truncated downstream (`anuenue | head -1`) must stay silent, and it
# must do so under BOTH SIGPIPE dispositions — E-03.
#
# This is the case CI caught and this script previously missed, in two
# separate ways:
#
#   1. It only exercised the DEFAULT disposition, where the kernel
#      kills the process before write(2) returns and anuenue's EPIPE
#      branch never runs at all. A CI runner sets SIGPIPE to SIG_IGN
#      and children inherit it, so there write(2) returns -EPIPE and
#      the branch is live. `trap '' PIPE` reproduces that in a shell.
#   2. It used a 256-byte corpus. That fits entirely in a 64 KiB pipe
#      buffer, so whether a second write happens at all — and therefore
#      whether EPIPE is ever seen — was a race between anuenue
#      finishing and `head` exiting. The corpus below is large enough
#      that many writes are guaranteed after the reader is gone.
python3 -c 'import sys; sys.stdout.write("rainbow line\n" * 200000)' > "$WORK/pipe.in" 2>/dev/null \
    || awk 'BEGIN { for (i = 0; i < 200000; i++) print "rainbow line" }' > "$WORK/pipe.in"

check_truncated_downstream() {
    _label="$1"; _pre="$2"
    set +e
    sh -c "$_pre \"\$1\" --color=24bit < \"\$2\" 2>\"\$3\" | head -c 1 >/dev/null" \
        _ "$BIN" "$WORK/pipe.in" "$WORK/pipe.err"
    set -e
    if [ -s "$WORK/pipe.err" ]; then
        bad "truncated downstream ($_label) wrote to stderr: $(head -1 "$WORK/pipe.err")"
    else
        ok "truncated downstream ($_label) stays silent"
    fi
}

check_truncated_downstream "SIGPIPE default" ""
check_truncated_downstream "SIGPIPE ignored — the CI configuration" "trap '' PIPE;"

# ...and the distinction has to hold: EPIPE is quiet, a REAL write
# failure is not. Both run with SIGPIPE ignored so the EPIPE branch is
# the one under test.
if [ -c /dev/full ]; then
    set +e
    sh -c "trap '' PIPE; \"\$1\" --color=24bit AGNOS > /dev/full 2>\"\$2\"" _ "$BIN" "$WORK/full2.err"
    rc=$?
    set -e
    if [ "$rc" -eq 1 ] && grep -q 'write to stdout failed' "$WORK/full2.err"; then
        ok "with SIGPIPE ignored, a real write failure is still reported and exits 1"
    else
        bad "with SIGPIPE ignored, /dev/full gave rc=$rc without the message"
    fi
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "robustness-check: PASS"
    exit 0
fi
echo "robustness-check: FAIL"
exit 1
