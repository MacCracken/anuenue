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
#      (E-01) — and EPIPE still behaves as SIGPIPE (E-03).
#   6. Transient READ errors are not failures (F-01) — a non-blocking
#      stdin is backpressure, not a broken stream.
#   7. The parse failures cmdit 1.4.0 made visible (v1.4.1): a boolean
#      given `=value` is a usage error, not ON; a command line the stdlib
#      cannot read whole is a runtime failure, not a silent prefix.
#   8. Parse-error lines name the offending token (v1.4.2) — and since
#      that token is argv headed for a terminal, it is echoed sanitized
#      (no ESC / BEL / C0 / C1 survives) and bounded (64 bytes + "...").
#   9. The escape word copy's scratch never reaches stdout (v1.4.3).
#      _emit_phase_esc writes 24 bytes per escape, zero past the escape;
#      a leaked scratch byte would be a NUL, so NUL-free input must give
#      NUL-free output on every route, in every mode, across flushes.
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

# --- gate 6: transient read errors are not failures -----------------
#
# F-01 (2026-08-26 sweep). The mirror of gate 5. `file_read` is a bare
# `sys_read` and all three stdin call sites classed any negative return
# as fatal — but EAGAIN on a non-blocking stdin means "no data yet",
# not "broken". Measured before the fix: a slow writer on a
# non-blocking pipe made anuenue render 64 of 6 500 bytes and exit 1.
#
# Needs a real O_NONBLOCK pipe, so this runs through python rather than
# the shell — `sh` has no way to set the flag on a descriptor.
echo "[robustness] a non-blocking stdin is not a read failure"

python3 - "$BIN" "$WORK" <<'PYEOF' > "$WORK/nb.out" 2>&1 || true
import os, subprocess, sys, fcntl, time, re, signal
BIN, WORK = sys.argv[1], sys.argv[2]
signal.signal(signal.SIGPIPE, signal.SIG_IGN)
DATA = b"rainbow line\n" * 500

def run(args, capture=True):
    r, w = os.pipe()
    fcntl.fcntl(r, fcntl.F_SETFL, os.O_NONBLOCK)      # anuenue's stdin
    p = subprocess.Popen([BIN] + args, stdin=r,
                         stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
                         stderr=subprocess.PIPE)
    os.close(r)
    try:
        for i in range(0, len(DATA), 64):
            os.write(w, DATA[i:i + 64])
            time.sleep(0.002)                          # slower than the reader
    except OSError:
        pass
    try:
        os.close(w)
    except OSError:
        pass
    out, err = p.communicate()
    n = len(re.sub(rb'\x1b\[[0-9;]*m', b'', out)) if capture and out else -1
    return p.returncode, n, err

rc, n, err = run(["--color=24bit"])
print("FILTER", rc, n, len(DATA))
rc, n, err = run(["--color=none"])
print("PASSTHRU", rc, n, len(DATA))
rc, n, err = run(["-a", "-d", "1", "--color=24bit"], capture=False)
print("ANIMATE", rc)
PYEOF

_f=$(grep '^FILTER' "$WORK/nb.out" || echo "FILTER 99 0 1")
set -- $_f
if [ "$2" -eq 0 ] && [ "$3" -eq "$4" ]; then
    ok "filter renders the whole stream from a non-blocking stdin ($3 bytes)"
else
    bad "filter on a non-blocking stdin: rc=$2, rendered $3 of $4"
fi

_p=$(grep '^PASSTHRU' "$WORK/nb.out" || echo "PASSTHRU 99 0 1")
set -- $_p
if [ "$2" -eq 0 ] && [ "$3" -eq "$4" ]; then
    ok "passthrough renders the whole stream from a non-blocking stdin"
else
    bad "passthrough on a non-blocking stdin: rc=$2, rendered $3 of $4"
fi

_a=$(grep '^ANIMATE' "$WORK/nb.out" || echo "ANIMATE 99")
set -- $_a
if [ "$2" -eq 0 ]; then
    ok "animation slurp survives a non-blocking stdin"
else
    bad "animation on a non-blocking stdin exited $2"
fi

# ...and a REAL read failure must still be reported, or the retry loop
# has simply swallowed the error class it was meant to narrow.
set +e
"$BIN" --color=24bit 0<&- >/dev/null 2>"$WORK/rderr"
rc=$?
set -e
if [ "$rc" -eq 1 ] && grep -q 'read from stdin failed' "$WORK/rderr"; then
    ok "a real read failure (closed stdin) is still reported and exits 1"
else
    bad "closed stdin gave rc=$rc without the expected message"
fi

# --- gate 7: cmdit 1.4.0's parse failures ---------------------------
#
# v1.4.1. Both states parsed CLEAN under cmdit 1.2.4, so neither could
# reach main.cyr's error switch before the bump:
#
#   `--bool=value` stored 1 and ignored the value — `--no-color=0`
#   disabled colour, the opposite of what was typed, at exit 0.
#
#   A command line over 2 MiB was cut at 2 MiB by stdlib args_init (one
#   read of /proc/self/cmdline into a fixed buffer) and the prefix parsed
#   as OK: every token past the cut, flags included, vanished at exit 0.
#   Reaching it needs ARG_MAX above 2 MiB, i.e. an unlimited stack — so
#   the child raises RLIMIT_STACK before exec, and the check skips if the
#   hard limit forbids that.
echo "[robustness] cmdit 1.4.0 parse failures (v1.4.1)"
for _bv in --no-color=0 --animate=1 --force-color= --help=x; do
    set +e
    printf 'hi\n' | "$BIN" "$_bv" > "$WORK/bv.out" 2> "$WORK/bv.err"
    rc=$?
    set -e
    if [ "$rc" -eq 2 ] && [ ! -s "$WORK/bv.out" ] \
        && grep -q 'boolean flags take no value' "$WORK/bv.err"; then
        ok "$_bv is a usage error (exit 2, nothing on stdout)"
    else
        bad "$_bv: rc=$rc, $(wc -c < "$WORK/bv.out") bytes on stdout"
    fi
done

# One-shot TEXT mode renders every positional. cmdit 1.2.4 stopped storing
# at 128 and reported nothing, so `anuenue $(seq 1 200)` printed 1..128 at
# exit 0; 1.4.0 grows the array instead.
set +e
# shellcheck disable=SC2046
"$BIN" --color=none $(seq 1 200) < /dev/null > "$WORK/pos.out" 2>/dev/null
rc=$?
set -e
_pw=$(wc -w < "$WORK/pos.out" | tr -d ' ')
_pl=$(tr ' ' '\n' < "$WORK/pos.out" | tail -1)
if [ "$rc" -eq 0 ] && [ "$_pw" -eq 200 ] && [ "$_pl" = "200" ]; then
    ok "one-shot TEXT keeps all 200 positionals (not the first 128)"
else
    bad "200 positionals: rc=$rc, rendered $_pw words, last '$_pl'"
fi

cat > "$WORK/bigargv.py" <<'PYEOF'
import resource, subprocess, sys
binary, npad = sys.argv[1], int(sys.argv[2])
def unlimit():
    inf = resource.RLIM_INFINITY
    resource.setrlimit(resource.RLIMIT_STACK, (inf, inf))
try:
    resource.setrlimit(resource.RLIMIT_STACK, resource.getrlimit(resource.RLIMIT_STACK))
    hard = resource.getrlimit(resource.RLIMIT_STACK)[1]
    if hard != resource.RLIM_INFINITY:
        print("SKIP stack hard limit is %d" % hard); sys.exit(0)
    argv = [binary, "--color=24bit"] + ["x" * 100000] * npad + ["--seed", "99"]
    r = subprocess.run(argv, input=b"", stdout=subprocess.DEVNULL,
                       stderr=subprocess.PIPE, preexec_fn=unlimit)
except OSError as e:
    print("SKIP exec refused: %s" % e); sys.exit(0)
msg = b"could not read the full command line" in r.stderr
print("RC %d %d" % (r.returncode, 1 if msg else 0))
PYEOF
_r=$(python3 -I "$WORK/bigargv.py" "$BIN" 24)
case "$_r" in
    SKIP*) echo "  skip: argv over 2 MiB — ${_r#SKIP }" ;;
    *)  set -- $_r
        if [ "$2" -eq 1 ] && [ "$3" -eq 1 ]; then
            ok "a 2.4 MB command line is reported and exits 1, not parsed as a prefix"
        else
            bad "2.4 MB command line: rc=$2, message=$3"
        fi
        # Control: the same shape under 2 MiB still parses, so the gate is
        # measuring the cut rather than rejecting long command lines.
        set -- $(python3 -I "$WORK/bigargv.py" "$BIN" 10)
        if [ "$2" -eq 0 ]; then
            ok "a 1.0 MB command line still parses (control)"
        else
            bad "1.0 MB command line: rc=$2 (the control must pass)"
        fi ;;
esac

# The other way to an unreadable command line: no descriptor for
# /proc/self/cmdline. Under --nofile=3 args_init's open fails and argc()
# is 0 — architecture 006. cmdit 1.2.4 parsed that as an empty argv, so
# every flag was dropped and the default path ran at exit 0.
if command -v prlimit >/dev/null 2>&1; then
    set +e
    printf 'hi\n' | prlimit --nofile=3 "$BIN" --color=none --log-level=debug \
        > "$WORK/nf.out" 2> "$WORK/nf.err"
    rc=$?
    set -e
    if [ "$rc" -eq 1 ] && [ ! -s "$WORK/nf.out" ] \
        && grep -q 'could not read the full command line' "$WORK/nf.err"; then
        ok "argv unreadable under --nofile=3 is reported and exits 1, flags not dropped"
    else
        bad "--nofile=3: rc=$rc, $(wc -c < "$WORK/nf.out") bytes on stdout"
    fi
else
    echo "  skip: prlimit(1) unavailable — cannot bound the descriptor table"
fi

# --- gate 8: parse-error lines name the token, safely ---------------
echo "[robustness] parse-error lines name the token (v1.4.2)"
_perr() {   # $1 = expected first stderr line; remaining args = argv
    _want=$1; shift
    set +e
    "$BIN" "$@" < /dev/null > /dev/null 2> "$WORK/pe.err"
    _rc=$?
    set -e
    _got=$(head -n 1 "$WORK/pe.err")
    if [ "$_rc" -eq 2 ] && [ "$_got" = "$_want" ]; then
        ok "$*: '$_got'"
    else
        bad "$*: rc=$_rc, got '$_got', want '$_want'"
    fi
}
_perr "anuenue: unknown flag: --bogus"                --bogus
_perr "anuenue: flag missing value: -p"               -p
_perr "anuenue: bad integer value: -p abc"            -p abc
_perr "anuenue: bad integer value: --freq=abc"        --freq=abc
_perr "anuenue: bundled short flags not supported: -an (use -x -y, not -xy)" -an
_perr "anuenue: boolean flags take no value: --no-color=0 (use --flag, not --flag=value)" --no-color=0

# A terminal escape in argv must not reach the terminal through stderr:
# OSC 0 (set window title) with a BEL terminator, and a CSI colour.
_esc=$(printf '\033')
_bel=$(printf '\007')
set +e
"$BIN" "--${_esc}]0;owned${_bel}${_esc}[31mred" < /dev/null > /dev/null 2> "$WORK/inj.err"
set -e
_first=$(head -n 1 "$WORK/inj.err")
if printf '%s' "$_first" | od -An -tx1 | grep -qE '(^| )(1b|07)( |$)'; then
    bad "ESC or BEL from argv reached stderr: $(printf '%s' "$_first" | od -An -c | head -2)"
elif [ "$_first" = "anuenue: unknown flag: --?]0;owned??[31mred" ]; then
    ok "ESC / BEL in a token are echoed as '?', never raw"
else
    bad "escape-bearing token rendered as '$_first'"
fi

# A long token is bounded: 64 bytes of it, then "...".
_long=$(python3 -I -c 'print("--" + "x" * 300)')
set +e
"$BIN" "$_long" < /dev/null > /dev/null 2> "$WORK/long.err"
set -e
_want="anuenue: unknown flag: $(python3 -I -c 'print("--" + "x" * 62)')..."
if [ "$(head -n 1 "$WORK/long.err")" = "$_want" ]; then
    ok "a 302-byte token is echoed as its first 64 bytes + '...'"
else
    bad "long token: '$(head -c 120 "$WORK/long.err")'"
fi

# --- gate 9: the word copy's scratch never reaches stdout -----------
#
# v1.4.3. Corpora chosen to put flushes everywhere relative to an
# escape: short lines (flush on every LF), one 70 000-byte line (flushes
# at the line-buffer reserve, mid-line), wide UTF-8 across the 4096-byte
# read boundary, no trailing LF (the EOF flush), and for animation one
# 32 KB grapheme cluster (the mid-cluster flush + re-emit). The output
# is checked for NUL by counting what `tr -d` removes.
echo "[robustness] the escape word copy's scratch never reaches stdout (v1.4.3)"
python3 -I - "$WORK" <<'PYEOF'
import sys
w = sys.argv[1]
open(w + "/nul-lines.in", "wb").write(b"AGNOS rainbow pipe\n" * 400)
open(w + "/nul-long.in", "wb").write(b"x" * 70000 + b"\n")
open(w + "/nul-utf8.in", "wb").write(("a" * 4095 + "\u00e9" + "\u65e5\u672c\U0001F308" * 3000).encode())
open(w + "/nul-cluster.in", "wb").write(("a" + "\u0301" * 16000 + "\n").encode())
PYEOF
_nul_ok() {   # $1 = label, $2 = output file
    _all=$(wc -c < "$2" | tr -d ' ')
    _non=$(tr -d '\000' < "$2" | wc -c | tr -d ' ')
    if [ "$_all" -gt 0 ] && [ "$_all" -eq "$_non" ]; then
        _nul_pass=$((_nul_pass + 1))
    else
        bad "$1: $((_all - _non)) NUL byte(s) in $_all bytes of output"
    fi
}
_nul_pass=0
for _m in 24bit 256 16; do
    for _c in lines long utf8; do
        "$BIN" --color=$_m < "$WORK/nul-$_c.in" > "$WORK/nul.out" 2>/dev/null || true
        _nul_ok "filter $_m $_c" "$WORK/nul.out"
    done
    "$BIN" --color=$_m "$(head -c 40000 "$WORK/nul-long.in")" < /dev/null > "$WORK/nul.out" 2>/dev/null || true
    _nul_ok "one-shot $_m" "$WORK/nul.out"
    timeout 20 "$BIN" -a -d 1 -i 400 --color=$_m < "$WORK/nul-cluster.in" > "$WORK/nul.out" 2>/dev/null || true
    _nul_ok "animate $_m 32 KB cluster" "$WORK/nul.out"
    timeout 20 "$BIN" -a -d 1 -i 400 --color=$_m < "$WORK/nul-lines.in" > "$WORK/nul.out" 2>/dev/null || true
    _nul_ok "animate $_m lines" "$WORK/nul.out"
done
if [ "$_nul_pass" -eq 18 ]; then
    ok "no NUL on stdout: filter (3 corpora), one-shot and animation (2), x 3 modes"
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "robustness-check: PASS"
    exit 0
fi
echo "robustness-check: FAIL"
exit 1
