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
#  10. The input's colour codes are stripped on the colour routes and
#      nothing else is (v1.4.5): SGR gone on filter / one-shot / animation
#      in every mode, MONO byte-exact, the 4096-byte read boundary inside
#      a sequence, the 128-byte bound, and non-SGR sequences intact.
#   9. The escape word copy's scratch never reaches stdout (v1.4.3).
#      _emit_phase_esc writes 24 bytes per escape, zero past the escape;
#      a leaked scratch byte would be a NUL, so NUL-free input must give
#      NUL-free output on every route, in every mode, across flushes.
#  11. No-colour spans (v1.5.0, ADR 0006): bytes between the APC markers
#      go out intact with a reset at each end, the rainbow pauses across
#      them, unmatched markers are lenient, near-misses pass as before,
#      a marker split across the read boundary is still a marker, and
#      MONO consumes the markers and keeps every other byte.
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
# H-05 (v1.4.4): animation must render every byte too. Through v1.4.3 an
# extending codepoint at the very start of the input, or straight after
# an LF, was tagged into no cluster (or into the LF's, which renders as
# reset + LF only) and vanished from every frame. Strip the escapes and
# the frame's CR, and the first frame must be the input.
echo "[robustness] animation renders every byte (H-05)"
python3 -I - "$BIN" <<'PYEOF' > "$WORK/h5.out" 2>&1 || true
import re, subprocess, sys
BIN = sys.argv[1]
for name, data in (("after-LF", b"a\n\xcc\x81b\n"),
                   ("leading", b"\xcc\x81ab\n"),
                   ("leading-no-LF", b"\xcc\x81\xcc\x81x"),
                   ("mixed", "e\u0301\n\u0301\u200d\U0001F308\nok\n".encode())):
    out = subprocess.run([BIN, "-a", "-d", "1", "-i", "400", "--color=16"],
                         input=data, capture_output=True).stdout
    # Frames are separated by the cursor-up climb, or — input without an
    # LF climbs nothing — by the CR that ends each frame.
    frame = re.split(rb"\x1b\[\d+A|\r", out)[0]
    frame = re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]", b"", frame)
    print("H5", name, "ok" if frame == data else "bad", frame[:40])
PYEOF
for _h in after-LF leading leading-no-LF mixed; do
    if grep -q "^H5 $_h ok" "$WORK/h5.out"; then
        ok "H-05: animation keeps every byte ($_h)"
    else
        bad "H-05: animation dropped bytes ($_h): $(grep "^H5 $_h " "$WORK/h5.out")"
    fi
done

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

# H-02 (v1.4.4): waiting is BLOCKING, not polling. A non-blocking
# descriptor whose peer stalls used to cost a 1 ms sleep-and-retry —
# about 1 000 wakeups a second, 30 ms of CPU every 4 s, for as long as
# the stall lasted. Both directions now wait in poll(2). Measured here
# as CPU time over a 3 s stall: stdin on all three routes, then stdout
# (a reader that stops reading until anuenue is blocked, then drains —
# and every byte must still arrive).
python3 - "$BIN" <<'PYEOF' > "$WORK/stall.out" 2>&1 || true
import os, subprocess, sys, fcntl, time, select, signal
BIN = sys.argv[1]
signal.signal(signal.SIGPIPE, signal.SIG_IGN)
def cpu_ms(pid):
    f = open("/proc/%d/stat" % pid).read().rsplit(")", 1)[1].split()
    return (int(f[11]) + int(f[12])) * 1000 // os.sysconf("SC_CLK_TCK")
for name, args in (("filter", ["--color=24bit"]), ("passthru", ["--color=none"]),
                   ("slurp", ["-a", "-d", "1", "--color=24bit"])):
    r, w = os.pipe()
    fcntl.fcntl(r, fcntl.F_SETFL, os.O_NONBLOCK)
    p = subprocess.Popen([BIN] + args, stdin=r, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.close(r); os.write(w, b"one line\n"); time.sleep(0.3)
    c0 = cpu_ms(p.pid); time.sleep(3.0); c1 = cpu_ms(p.pid)
    p.kill(); p.wait(); os.close(w)
    print("STDIN", name, c1 - c0)
# stdout: 2 MB of input, a non-blocking stdout pipe nobody reads at first
data = b"rainbow output backpressure\n" * 75000
r, w = os.pipe()
fcntl.fcntl(w, fcntl.F_SETFL, os.O_NONBLOCK)
p = subprocess.Popen([BIN, "--color=none"], stdin=subprocess.PIPE, stdout=w, stderr=subprocess.DEVNULL)
os.close(w)
def feed():
    try:
        p.stdin.write(data); p.stdin.close()
    except OSError:
        pass
import threading
t = threading.Thread(target=feed); t.start()
time.sleep(0.5)
c0 = cpu_ms(p.pid); time.sleep(3.0); c1 = cpu_ms(p.pid)
got = 0
while True:
    d = os.read(r, 1 << 16)
    if not d: break
    got += len(d)
rc = p.wait(); t.join()
print("STDOUT", c1 - c0, rc, got, len(data))
PYEOF
for _rt in filter passthru slurp; do
    _c=$(grep "^STDIN $_rt " "$WORK/stall.out" | awk '{print $3}')
    if [ -n "$_c" ] && [ "$_c" -le 5 ]; then
        ok "H-02: a stalled non-blocking stdin blocks ($_rt: ${_c} ms CPU in 3 s)"
    else
        bad "H-02: a stalled non-blocking stdin costs CPU ($_rt: '${_c}' ms in 3 s)"
    fi
done
set -- $(grep '^STDOUT' "$WORK/stall.out" || echo "STDOUT 99 99 0 1")
if [ "$2" -le 5 ] && [ "$3" -eq 0 ] && [ "$4" -eq "$5" ]; then
    ok "H-02: a stalled non-blocking stdout blocks (${2} ms CPU in 3 s), then delivers all $4 bytes"
else
    bad "H-02: stalled non-blocking stdout: ${2} ms CPU, rc=$3, delivered $4 of $5"
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
#   v1.4.1 (cmdit 1.4.0) reported it instead, exit 1. v1.5.1 inverts the
#   check: from cyrius 6.7.12 args_init reads to EOF, and cmdit 1.4.2
#   refuses only a read of exactly 2 MiB, so a longer command line parses
#   whole and the `--seed 99` at its very end is honoured.
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
    r = subprocess.run(argv, input=b"", stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, preexec_fn=unlimit)
except OSError as e:
    print("SKIP exec refused: %s" % e); sys.exit(0)
msg = b"could not read the full command line" in r.stderr
# The seed is the last token, so the first cluster's escape shows whether
# the tail was read: it must match `--seed 99 x`, and differ from seed 0.
def first(out):
    return out[:out.find(b"x") + 1]
seeded = subprocess.run([binary, "--color=24bit", "--seed", "99", "x"],
                        stdout=subprocess.PIPE).stdout
unseeded = subprocess.run([binary, "--color=24bit", "x"], stdout=subprocess.PIPE).stdout
seed_ok = first(r.stdout) == first(seeded) and first(seeded) != first(unseeded)
print("RC %d %d %d" % (r.returncode, 1 if msg else 0, 1 if seed_ok else 0))
PYEOF
_r=$(python3 -I "$WORK/bigargv.py" "$BIN" 24)
case "$_r" in
    SKIP*) echo "  skip: argv over 2 MiB — ${_r#SKIP }" ;;
    *)  set -- $_r
        if [ "$2" -eq 0 ] && [ "$3" -eq 0 ] && [ "$4" -eq 1 ]; then
            ok "a 2.4 MB command line parses whole: exit 0, and the trailing --seed 99 is honoured"
        else
            bad "2.4 MB command line: rc=$2, message=$3, seed honoured=$4"
        fi
        # Control: the same shape under 2 MiB parses too and passes the same
        # seed check, so the check itself is shown to work at a size every
        # toolchain reads whole.
        set -- $(python3 -I "$WORK/bigargv.py" "$BIN" 10)
        if [ "$2" -eq 0 ] && [ "$4" -eq 1 ]; then
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

# --- gate 10: input colour codes are stripped (v1.4.5) --------------
#
# anuenue owns the colour on the filter, one-shot and animation routes,
# so an SGR in the input (ESC [ params m) is removed before the rainbow
# goes on. Through v1.4.4 it was kept and broken — anuenue's own escape
# cancelled each input ESC, and `ls --color=always | anuenue` printed
# `[01;34m` as text (audit H-06). Everything that is NOT a complete SGR
# must still pass byte for byte, and MONO is untouched.
echo "[robustness] input colour codes are stripped, nothing else (v1.4.5)"
python3 -I - "$BIN" <<'PYEOF' > "$WORK/sgr.out" 2>&1 || true
import re, subprocess, sys
BIN = sys.argv[1]
OURS = re.compile(rb"\x1b\[(?:0|9[0-7]|38;5;\d+|38;2;\d+;\d+;\d+)m")  # anuenue's own SGRs
def run(args, data, stdin=True):
    return subprocess.run([BIN] + args, input=data if stdin else None,
                          capture_output=True).stdout
def plain(out):
    return OURS.sub(b"", out)
ls_like = b"total 3\n\x1b[0m\x1b[01;34mbin\x1b[0m  \x1b[01;32mrun.sh\x1b[0m  notes.txt\n"
want = b"total 3\nbin  run.sh  notes.txt\n"
for mode in ("24bit", "256", "16"):
    print("FILTER", mode, "ok" if plain(run(["--color=" + mode], ls_like)) == want else "bad")
    one = run(["--color=" + mode, "a\x1b[31mb\x1b[0mc"], b"", stdin=False)
    print("ONESHOT", mode, "ok" if plain(one) == b"abc\n" else "bad")
    an = run(["-a", "-d", "1", "-i", "400", "--color=" + mode], b"a\x1b[1;31mb\x1b[0m\n")
    frame = re.split(rb"\x1b\[\d+A", an)[0]
    frame = re.sub(rb"\x1b\[\?25[lh]", b"", plain(frame))
    print("ANIM", mode, "ok" if frame == b"ab\n" else "bad")
mono = run(["--color=none"], ls_like)
print("MONO", "ok" if mono == ls_like else "bad")
# The read boundary, at every offset of the 5-byte ESC [ 31 m across 4096.
fails = 0
for k in range(0, 6):
    data = b"a" * (4096 - k) + b"\x1b[31mRED\x1b[0m\n"
    if plain(run(["--color=16"], data)) != b"a" * (4096 - k) + b"RED\n":
        fails += 1
# A 19-byte truecolor SGR at every offset across the boundary, and a
# 128-byte one (the largest carry: 127 bytes held into the next read).
tc = b"\x1b[38;2;255;0;10m"
for k in range(0, len(tc) + 1):
    data = b"a" * (4096 - k) + tc + b"RED\n"
    if plain(run(["--color=16"], data)) != b"a" * (4096 - k) + b"RED\n":
        fails += 1
big = b"\x1b[" + b"1;" * 62 + b"1m"                   # 128 bytes
for k in (1, 64, 127):
    data = b"a" * (4096 - k) + big + b"X\n"
    if plain(run(["--color=16"], data)) != b"a" * (4096 - k) + b"X\n":
        fails += 1
print("BOUNDARY", "ok" if fails == 0 else "bad %d" % fails)
# Dribbled: one byte per write, so the open SGR is carried across many
# tiny reads.
import time
p = subprocess.Popen([BIN, "--color=16"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
for byte in b"a\x1b[38;2;1;2;3mb\x1b[0mc\n":
    p.stdin.write(bytes([byte])); p.stdin.flush(); time.sleep(0.002)
p.stdin.close()
dribble = plain(p.stdout.read()); p.wait()
print("DRIBBLE", "ok" if dribble == b"abc\n" else "bad %r" % dribble)
# The bound: 129 bytes is kept whole; 128 is stripped.
over = b"\x1b[" + b"1" * 126 + b"m"
at = b"\x1b[" + b"1" * 125 + b"m"
print("BOUND", "ok" if plain(run(["--color=16"], over + b"x\n")) == over + b"x\n"
      and plain(run(["--color=16"], at + b"x\n")) == b"x\n" else "bad")
# Non-SGR sequences and broken SGRs pass byte for byte.
keep = b"\x1b[2J\x1b[?25l\x1b]0;t\x07\x1b[>4;1m\x1b[31\nz\n"
print("KEEP", "ok" if plain(run(["--color=16"], keep)) == keep else "bad")
PYEOF
for _k in "FILTER 24bit" "FILTER 256" "FILTER 16" "ONESHOT 24bit" "ONESHOT 256" "ONESHOT 16" \
          "ANIM 24bit" "ANIM 256" "ANIM 16"; do
    if grep -q "^$_k ok" "$WORK/sgr.out"; then
        ok "input SGR stripped: $_k"
    else
        bad "input SGR not stripped: $_k ($(grep "^$_k " "$WORK/sgr.out"))"
    fi
done
for _k in MONO BOUNDARY DRIBBLE BOUND KEEP; do
    if grep -q "^$_k ok" "$WORK/sgr.out"; then
        case $_k in
            MONO)     ok "MONO keeps the input's colour codes byte for byte" ;;
            BOUNDARY) ok "an SGR split across the 4096-byte read is stripped, at every offset (5, 19 and 128 bytes)" ;;
            DRIBBLE)  ok "an SGR arriving one byte per write is stripped" ;;
            BOUND)    ok "128 bytes is an SGR, 129 is ordinary text" ;;
            KEEP)     ok "non-SGR sequences and broken SGRs pass byte for byte" ;;
        esac
    else
        bad "$_k: $(grep "^$_k " "$WORK/sgr.out" || head -3 "$WORK/sgr.out")"
    fi
done

# --- gate 11: no-colour spans (v1.5.0, ADR 0006) -------------------
#
# A producer brackets text with ESC _ anuenue:off ESC \ ... ESC _
# anuenue:on ESC \ to keep it out of the rainbow. Inside, its bytes go out
# intact — its own colour codes included — with one reset at each marker
# and nothing else of anuenue's (no reset at an LF either). The phase
# pauses, so removing `reset + span + reset` from the output must leave
# exactly the output for the text without the span.
echo "[robustness] no-colour spans (v1.5.0)"
python3 -I - "$BIN" <<'PYEOF' > "$WORK/span.out" 2>&1 || true
import re, subprocess, sys, time
BIN = sys.argv[1]
OFF = b"\x1b_anuenue:off\x1b\\"
ON = b"\x1b_anuenue:on\x1b\\"
RESET = b"\x1b[0m"
OURS = re.compile(rb"\x1b\[(?:0|9[0-7]|38;5;\d+|38;2;\d+;\d+;\d+)m")
TINT = re.compile(rb"\x1b\[38;2;\d+;\d+;\d+m")
def run(args, data, stdin=True):
    return subprocess.run([BIN] + args, input=data if stdin else None,
                          capture_output=True).stdout
def cut(out, span):
    """out with the first reset+span+reset removed, or None if absent."""
    k = out.find(RESET + span + RESET)
    if k < 0:
        return None
    return out[:k] + out[k + len(RESET + span + RESET):]
def frame0(out):
    f = re.split(rb"\x1b\[\d+A", out)[0]
    return f.replace(b"\x1b[?25l", b"")
SPAN = b"\x1b[31mR\x1b[1m!\x1b[0m"            # the producer's own codes
for mode in ("24bit", "256", "16"):
    m = ["--color=" + mode]
    base = run(m, b"abcd\n")
    # SGR outside the span is stripped; inside it is the producer's.
    got = run(m, b"a\x1b[32mb" + OFF + SPAN + ON + b"c\x1b[0md\n")
    print("FILTER", mode, "ok" if cut(got, SPAN) == base else "bad %r" % got)
    one = run(m + [(b"ab" + OFF + SPAN + ON + b"cd").decode()], b"", stdin=False)
    print("ONESHOT", mode, "ok" if cut(one, SPAN) == run(m + ["abcd"], b"", stdin=False)
          else "bad %r" % one)
    an = run(["-a", "-d", "1", "-i", "300"] + m, b"ab" + OFF + SPAN + ON + b"cd\n")
    abase = run(["-a", "-d", "1", "-i", "300"] + m, b"abcd\n")
    frames = len(re.split(rb"\x1b\[\d+A", an))
    ok = cut(frame0(an), SPAN) == frame0(abase) and an.count(RESET + SPAN + RESET) == frames
    print("ANIM", mode, "ok" if ok else "bad %r" % an[:300])
# An LF inside a span gets no reset of anuenue's: the producer's colour
# may run across lines. Filter and one-shot.
ml = b"\x1b[32mX\nY\x1b[0m"
f = run(["--color=24bit"], b"a" + OFF + ml + ON + b"b\n")
o = run(["--color=24bit", (b"a" + OFF + ml + ON + b"b").decode()], b"", stdin=False)
print("LF", "ok" if cut(f, ml) == run(["--color=24bit"], b"ab\n")
      and cut(o, ml) == run(["--color=24bit", "ab"], b"", stdin=False) else "bad %r %r" % (f, o))
# `off` with no `on` runs to the end, which closes it with one reset —
# with or without a final LF, on the filter and the one-shot route.
m16 = ["--color=16"]
ab = run(m16, b"ab")
eof = (run(m16, b"ab" + OFF + b"\x1b[31mcd\n") == ab + b"\x1b[31mcd\n" + RESET
       and run(m16, b"ab" + OFF + b"cd") == ab + b"cd" + RESET
       and run(m16 + [(b"ab" + OFF + b"\x1b[31mcd").decode()], b"", stdin=False)
           == ab + b"\x1b[31mcd\n" + RESET)
print("EOF", "ok" if eof else "bad")
# Two adjacent spans: a reset between them on every route, so the first
# span's attributes (here an unterminated OSC) cannot run into the second.
adj_in = b"a" + OFF + b"\x1b]0;t" + ON + OFF + b"Y" + ON + b"b\n"
adj = re.compile(re.escape(b"\x1b]0;t") + rb"(?:\x1b\[0m)+" + re.escape(b"Y"))
outs = (run(m16, adj_in), run(m16 + [adj_in[:-1].decode()], b"", stdin=False),
        frame0(run(["-a", "-d", "1", "-i", "300"] + m16, adj_in)))
print("ADJACENT", "ok" if all(adj.search(x) for x in outs) else "bad %r" % (outs,))
# Inside a span nothing of anuenue's — not even at a reserve flush. Span
# bytes fill the 32 KiB line buffer to 6 bytes under the reserve, and an
# unfinished `on` at the very end is carried to EOF, where it is span text:
# writing it crosses the reserve. Two resets in all: at `off`, and the one
# that closes the span at the end.
fill = OFF + b"x" * 32726 + b"\x1b_anuenue:o"
rsv = run(m16, fill)
print("RESERVE", "ok" if rsv.count(RESET) == 2 and rsv.endswith(b"\x1b_anuenue:o" + RESET)
      else "bad %d resets" % rsv.count(RESET))
# Empty spans write resets and no byte (V-06). Every reset is followed by the
# reserve check, so however many there are, the line buffer holds: the
# process exits 0, no marker leaks, and `b` keeps its hue. Before the check,
# 4 200 on the one-shot route crashed with SIGSEGV, and the filter wrote past
# the buffer into the read buffer and the phase table.
pairs = OFF + ON
m24 = ["--color=24bit"]
want = TINT.findall(run(m24, b"ab\n"))
ef = subprocess.run([BIN] + m24, input=b"a" + pairs * 100000 + b"b\n", capture_output=True)
eo = subprocess.run([BIN] + m24 + [b"a" + pairs * 4400 + b"b"], capture_output=True)
eok = all(r.returncode == 0 and b"anuenue:" not in r.stdout and TINT.findall(r.stdout) == want
          for r in (ef, eo))
print("EMPTY", "ok" if eok else "bad rc=%d/%d" % (ef.returncode, eo.returncode))
# The three routes agree on the hue sequence at span edges (V-07 to V-09):
# an extender after a span or an empty span continues the cluster before
# it; an empty span resets the ZWJ / RI joins; a UTF-8 sequence a span
# cuts stays cut. The filter writes an escape per codepoint and animation
# one per cluster, so consecutive repeats are collapsed before comparing.
# The bytes must agree too — span bytes raw between resets on both — once
# the tints are removed and runs of resets collapsed (the filter writes two
# at an empty span, animation one).
def shape(out):
    out = re.sub(rb"(?:\x1b\[0m)+", RESET, TINT.sub(b"", out))
    return re.sub(rb"(?:\x1b\[0m)+\Z", b"", out)
def hues(out):
    seq = []
    for t in TINT.findall(out):
        if not seq or seq[-1] != t:
            seq.append(t)
    return seq
edges = [b"e" + OFF + b"x" + ON + "\u0301b\n".encode(),
         b"e" + OFF + ON + "\u0301b\n".encode(),
         "a\u200d".encode() + OFF + ON + b"b\n",
         "\U0001F1FA".encode() + OFF + ON + "\U0001F1F8b\n".encode(),
         b"a\xe4" + OFF + b"\xb8\xad" + ON + b"x\n",
         b"ab" + OFF + b"\x1b[31mR" + ON + "\u0301\u0302cd\n".encode(),
         "\U0001F468\u200d".encode() + OFF + b"x" + ON + "\U0001F469b\n".encode(),
         b"x" + OFF + b"y" + ON + OFF + b"z" + ON + "\u0301w\n".encode(),
         b"e" + OFF + b"\n" + ON + "\u0301b\n".encode(),
         OFF + b"x" + ON + "\u0301b\n".encode()]
split = []
for d in edges:
    f = hues(run(m24, d))
    o = hues(subprocess.run([BIN] + m24 + [d[:-1]], capture_output=True).stdout)
    an = frame0(run(["-a", "-d", "1", "-i", "300"] + m24, d))
    a = hues(an)
    if not (f == o == a) or shape(run(m24, d)) != shape(an):
        split.append(d)
print("ROUTES", "ok" if not split else "bad %r" % split)
# A stray `on`, a nested `off`, a repeated `on`: no-ops.
lax = (run(m16, b"ab" + ON + b"cd\n") == run(m16, b"abcd\n")
       and run(["--color=24bit"], b"a" + OFF + b"X" + OFF + b"Y" + ON + ON + b"b\n")
           == run(["--color=24bit"], b"a" + OFF + b"XY" + ON + b"b\n"))
print("LENIENT", "ok" if lax else "bad")
# Near-misses are no markers: they pass byte for byte, as before v1.5.0.
miss = (b"\x1b_anuenue:of\x1b\\", b"\x1b_ANUENUE:off\x1b\\", b"\x1b_anuenue:off\x07",
        b"\x1b_anuenue:off \x1b\\", b"\x1b_anuenue:on", b"\x1b_Ga=T\x1b\\", b"\x1b_\x1b\\")
bad = [x for x in miss if OURS.sub(b"", run(m16, b"a" + x + b"b\n")) != b"a" + x + b"b\n"]
print("NEARMISS", "ok" if not bad else "bad %r" % bad)
# Either marker split across the 4096-byte read at every offset: still a
# marker, the span intact, and the tint sequence that of the text alone.
SP = b"\x1b[31mX\x1b[1mY"                     # no reset inside: OURS keeps it
fails = []
for k in range(0, len(OFF) + 1):
    pre = b"a" * (4096 - k)
    out = run(["--color=24bit"], pre + OFF + SP + ON + b"z\n")
    alone = run(["--color=24bit"], pre + b"z\n")
    if OURS.sub(b"", out) != pre + SP + b"z\n" or TINT.findall(out) != TINT.findall(alone) \
            or (RESET + SP + RESET) not in out:
        fails.append("off@%d" % k)
for k in range(0, len(ON) + 1):
    pre = b"a" * (4096 - k - len(OFF) - len(SP))
    out = run(["--color=24bit"], pre + OFF + SP + ON + b"z\n")
    alone = run(["--color=24bit"], pre + b"z\n")
    if OURS.sub(b"", out) != pre + SP + b"z\n" or TINT.findall(out) != TINT.findall(alone) \
            or (RESET + SP + RESET) not in out:
        fails.append("on@%d" % k)
# A span long enough to cross the boundary itself.
long_sp = b"\x1b[31m" + b"s" * 200
pre = b"a" * 4000
out = run(["--color=24bit"], pre + OFF + long_sp + ON + b"z\n")
if OURS.sub(b"", out) != pre + long_sp + b"z\n" \
        or TINT.findall(out) != TINT.findall(run(["--color=24bit"], pre + b"z\n")):
    fails.append("straddle")
print("BOUNDARY", "ok" if not fails else "bad %s" % fails)
# One byte per write: identical to the whole input, colour and MONO.
d = b"a\x1b[32mb" + OFF + b"\x1b[31mR\nS" + ON + b"c\n"
drib = []
for m in (["--color=16"], ["--color=none"]):
    p = subprocess.Popen([BIN] + m, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    for byte in d:
        p.stdin.write(bytes([byte])); p.stdin.flush(); time.sleep(0.002)
    p.stdin.close()
    got = p.stdout.read(); p.wait()
    if got != run(m, d):
        drib.append(m[0])
print("DRIBBLE", "ok" if not drib else "bad %s" % drib)
# MONO: markers consumed, every other byte kept — SGR, other APCs,
# near-misses — and the read boundary inside a marker at every offset.
mono_in = b"\x1b[01;34mbin\x1b[0m " + OFF + b"\x1b[31mx\x1b_G\x1b\\" + ON + b"\x1b_anuenue:of\n"
mono_ok = run(["--color=none"], mono_in) == mono_in.replace(OFF, b"").replace(ON, b"")
for k in range(0, len(OFF) + 1):
    pre = b"a" * (4096 - k)
    if run(["--color=none"], pre + OFF + b"X" + ON + b"\n") != pre + b"X\n":
        mono_ok = False
mono_ok = mono_ok and run(["--color=none", (b"a" + OFF + b"b" + ON + b"c").decode()],
                          b"", stdin=False) == b"abc\n"
print("MONO", "ok" if mono_ok else "bad")
PYEOF
for _k in "FILTER 24bit" "FILTER 256" "FILTER 16" "ONESHOT 24bit" "ONESHOT 256" "ONESHOT 16" \
          "ANIM 24bit" "ANIM 256" "ANIM 16"; do
    if grep -q "^$_k ok" "$WORK/span.out"; then
        ok "no-colour span intact, reset at both ends, phase paused: $_k"
    else
        bad "no-colour span: $_k ($(grep "^$_k " "$WORK/span.out" || head -3 "$WORK/span.out"))"
    fi
done
for _k in LF EOF ADJACENT RESERVE EMPTY ROUTES LENIENT NEARMISS BOUNDARY DRIBBLE MONO; do
    if grep -q "^$_k ok" "$WORK/span.out"; then
        case $_k in
            LF)       ok "an LF inside a span gets no reset (filter, one-shot)" ;;
            EOF)      ok "an unclosed span runs to the end, which closes it with one reset" ;;
            ADJACENT) ok "adjacent spans are reset apart (filter, one-shot, animation)" ;;
            RESERVE)  ok "a reserve flush inside a span writes no reset" ;;
            EMPTY)    ok "100 000 empty spans stay inside the line buffer (filter, one-shot)" ;;
            ROUTES)   ok "filter, one-shot and animation agree on hues and bytes at span edges (10 inputs)" ;;
            LENIENT)  ok "a stray on, a nested off and a repeated on are no-ops" ;;
            NEARMISS) ok "near-miss markers and other APCs pass byte for byte" ;;
            BOUNDARY) ok "a marker split across the 4096-byte read at every offset, and a span across it" ;;
            DRIBBLE)  ok "a span arriving one byte per write equals the whole input (colour, MONO)" ;;
            MONO)     ok "MONO consumes the markers and keeps every other byte, at every read offset" ;;
        esac
    else
        bad "$_k: $(grep "^$_k " "$WORK/span.out" || head -3 "$WORK/span.out")"
    fi
done

echo
if [ "$FAIL" -eq 0 ]; then
    echo "robustness-check: PASS"
    exit 0
fi
echo "robustness-check: FAIL"
exit 1
