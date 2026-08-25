#!/bin/sh
# pty-check.sh — drive anuenue through a real pseudo-terminal.
#
# v1.3.1. Every other anuenue test runs the binary on a pipe. That
# leaves three behaviours untested, and all three are on the paths a
# user actually meets:
#
#   1. `tty_isatty` returning TRUE. On a pipe, colour detection exits
#      at "stdout is not a TTY" and the whole TERM / COLORTERM chain
#      below it is dead code. Every existing animation test passes
#      `--color=24bit` specifically to route around this — so the
#      auto-detection branch that ships to real users has never been
#      exercised by CI.
#   2. Cursor lifecycle as a terminal receives it, with ordering
#      asserted against the END of the stream rather than against a
#      grep count.
#   3. SIGINT during animation while attached to a terminal — the
#      case the signalfd was written for. Its failure mode (B-01) and
#      its latency (B-02) are covered by signal-check.sh; this is the
#      success path.
#
# HOW THE PTY IS OBTAINED
#
# `script -qec CMD /dev/null` runs CMD with its stdio on a fresh pty
# and writes the session transcript to the given file (here /dev/null,
# because we capture the transcript on our own stdout instead).
# util-linux `script` is the portable-enough way to get a controlling
# terminal from a shell script; darshana reaches for /dev/ptmx
# directly because it is testing the termios primitives themselves,
# which is not what anuenue needs.
#
# WHAT THIS DELIBERATELY DOES NOT CLAIM
#
# It does not read terminal state back. `script` transcribes bytes; it
# does not emulate a terminal, so there is no "is the cursor visible"
# to query. The assertions here are about the byte stream and the
# process, which is what is actually observable. Reading back real
# terminal state would need a terminal emulator in the harness.
#
# Usage:
#   sh scripts/pty-check.sh
#   BIN=build/anuenue-dce sh scripts/pty-check.sh

set -eu

BIN="${BIN:-build/anuenue}"

if [ ! -x "$BIN" ]; then
    echo "pty-check: $BIN not executable — run 'cyrius build src/main.cyr build/anuenue' first" >&2
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"; pkill -9 -x anuenue >/dev/null 2>&1 || true' EXIT INT TERM

FAIL=0
ok()   { echo "  ok: $1"; }
bad()  { echo "  FAIL: $1"; FAIL=1; }
skip() { echo "  SKIP: $1"; }

# --- availability ---------------------------------------------------
if ! command -v script >/dev/null 2>&1; then
    echo "[pty-check] no script(1) on this host"
    skip "script(1) unavailable — cannot obtain a pty"
    echo
    echo "pty-check: PASS (skipped)"
    exit 0
fi
if [ ! -c /dev/ptmx ]; then
    echo "[pty-check] no /dev/ptmx on this host"
    skip "/dev/ptmx unavailable — cannot obtain a pty"
    echo
    echo "pty-check: PASS (skipped)"
    exit 0
fi

printf 'AGNOS\n' > "$WORK/in.txt"

# Run CMD under a pty, transcript on stdout.
in_pty() {
    script -qec "$1" /dev/null 2>&1
}

# --- gate 0: the pty is real ----------------------------------------
echo "[pty-check] the harness actually provides a terminal"
"$BIN" -v --color=auto < "$WORK/in.txt" > /dev/null 2> "$WORK/pipe.err"
in_pty "$BIN -v --color=auto < $WORK/in.txt" > "$WORK/pty.out"

if grep -q 'reason=stdout is not a TTY' "$WORK/pipe.err"; then
    ok "control: on a pipe, detection stops at 'stdout is not a TTY'"
else
    bad "control: pipe run did not report the not-a-TTY reason"
fi
if grep -aq 'reason=stdout is not a TTY' "$WORK/pty.out"; then
    bad "under script(1), anuenue still saw a non-TTY — the harness is not providing a pty"
else
    ok "under a pty, detection passes the isatty gate (the branch pipes never reach)"
fi

# --- gate 1: the auto-detection chain -------------------------------
#
# Each row exercises a different exit of anuenue_detect_color_mode.
# Only reachable with a TTY, because the isatty check sits above all
# of them. TERM is set INSIDE the pty command: script(1) does not
# reliably propagate it from the parent environment.
echo "[pty-check] colour auto-detection, TTY branch"

check_detect() {
    _desc="$1"; _pre="$2"; _mode="$3"; _reason="$4"
    _out=$(in_pty "$_pre $BIN -v --color=auto < $WORK/in.txt")
    if printf '%s' "$_out" | grep -aq "mode=$_mode"; then
        if printf '%s' "$_out" | grep -aq "reason=$_reason"; then
            ok "$_desc -> mode=$_mode ($_reason)"
        else
            bad "$_desc -> mode=$_mode but reason was not '$_reason': $(printf '%s' "$_out" | grep -ao 'reason=[^\r]*' | head -1)"
        fi
    else
        bad "$_desc -> expected mode=$_mode, got: $(printf '%s' "$_out" | grep -ao 'mode=[a-z0-9]*' | head -1)"
    fi
}

check_detect "TERM=xterm-256color"      "TERM=xterm-256color"      "256"   "TERM 256color"
check_detect "TERM=xterm-direct"        "TERM=xterm-direct"        "24bit" "TERM -direct suffix"
check_detect "COLORTERM=truecolor"      "COLORTERM=truecolor TERM=xterm" "24bit" "COLORTERM truecolor"
check_detect "COLORTERM=24bit"          "COLORTERM=24bit TERM=xterm"     "24bit" "COLORTERM truecolor"
check_detect "TERM=dumb (no signal)"    "TERM=dumb"                "16"    "no signal"
check_detect "NO_COLOR wins over TERM"  "NO_COLOR=1 TERM=xterm-256color" "none" "NO_COLOR env present"
# --no-color is a flag, not an env var, so it does not fit check_detect's
# "prefix the command with assignments" shape — assert it directly.
_out=$(in_pty "TERM=xterm-256color $BIN -v --no-color < $WORK/in.txt")
if printf '%s' "$_out" | grep -aq 'reason=--no-color flag'; then
    ok "--no-color overrides a colour-capable TTY"
else
    bad "--no-color did not override on a TTY"
fi

# --- gate 2: MONO passthrough is byte-exact on a TTY ----------------
#
# The M6 acceptance is that MONO output equals the input byte for
# byte. On a pipe that is trivially true because MONO is what a pipe
# gets anyway. On a TTY it means the passthrough path really did
# suppress every escape.
echo "[pty-check] MONO on a TTY is byte-identical to the input"
_out=$(in_pty "TERM=xterm-256color NO_COLOR=1 $BIN < $WORK/in.txt" | tr -d '\r')
if [ "$_out" = "AGNOS" ]; then
    ok "NO_COLOR on a colour-capable TTY emits the input unchanged"
else
    bad "NO_COLOR on a TTY emitted: $(printf '%s' "$_out" | od -c | head -2 | tr '\n' ' ')"
fi

# --- gate 3: cursor lifecycle on a clean animation exit -------------
echo "[pty-check] cursor lifecycle, clean exit"
in_pty "TERM=xterm-256color $BIN -a -d 1 < $WORK/in.txt" > "$WORK/clean.out"
python3 - "$WORK/clean.out" > "$WORK/clean.res" 2>/dev/null <<'PY' || true
import sys
d = open(sys.argv[1], 'rb').read()
hide = d.rfind(b'\x1b[?25l')
show = d.rfind(b'\x1b[?25h')
print(f"hide={hide} show={show} tail={len(d) - show - 6 if show >= 0 else -1}")
PY
read_res=$(cat "$WORK/clean.res" 2>/dev/null || echo "")
hide=$(printf '%s' "$read_res" | sed -n 's/.*hide=\(-\{0,1\}[0-9]*\).*/\1/p')
show=$(printf '%s' "$read_res" | sed -n 's/.*show=\(-\{0,1\}[0-9]*\).*/\1/p')
if [ "${hide:--1}" -ge 0 ] && [ "${show:--1}" -ge 0 ] && [ "$show" -gt "$hide" ]; then
    ok "cursor hidden then shown, show last (hide@$hide show@$show)"
else
    bad "cursor lifecycle wrong on clean exit: $read_res"
fi

# --- gate 4: SIGINT during animation, on a terminal -----------------
#
# The case the signalfd exists for. Note pgrep -x, not -f: script(1)'s
# own argv contains the anuenue command line, so -f matches the
# wrapper first and the signal goes to the wrong process.
echo "[pty-check] SIGINT during animation restores the cursor"
in_pty "TERM=xterm-256color $BIN -a -d 30 < $WORK/in.txt" > "$WORK/sig.out" 2>&1 &
PTY_JOB=$!

APID=""
i=0
while [ "$i" -lt 40 ]; do
    APID=$(pgrep -x anuenue 2>/dev/null | head -1 || true)
    [ -n "$APID" ] && break
    i=$((i + 1))
    sleep 0.1
done

if [ -z "$APID" ]; then
    bad "animation process never appeared under the pty"
    kill -9 "$PTY_JOB" >/dev/null 2>&1 || true
else
    sleep 1
    kill -INT "$APID" >/dev/null 2>&1 || true
    # Wait for the wrapper to finish; if it does not, the SIGINT path
    # failed to exit and that is the finding.
    i=0
    while [ "$i" -lt 60 ]; do
        kill -0 "$PTY_JOB" >/dev/null 2>&1 || break
        i=$((i + 1))
        sleep 0.1
    done
    if kill -0 "$PTY_JOB" >/dev/null 2>&1; then
        bad "animation did not exit within 6s of SIGINT"
        kill -9 "$PTY_JOB" >/dev/null 2>&1 || true
        pkill -9 -x anuenue >/dev/null 2>&1 || true
    else
        ok "animation exited after SIGINT"
        python3 - "$WORK/sig.out" > "$WORK/sig.res" 2>/dev/null <<'PY' || true
import sys
d = open(sys.argv[1], 'rb').read()
hide = d.rfind(b'\x1b[?25l')
show = d.rfind(b'\x1b[?25h')
reset = d.rfind(b'\x1b[0m')
print(f"hide={hide} show={show} reset={reset}")
PY
        sres=$(cat "$WORK/sig.res" 2>/dev/null || echo "")
        shide=$(printf '%s' "$sres" | sed -n 's/.*hide=\(-\{0,1\}[0-9]*\).*/\1/p')
        sshow=$(printf '%s' "$sres" | sed -n 's/.*show=\(-\{0,1\}[0-9]*\).*/\1/p')
        sreset=$(printf '%s' "$sres" | sed -n 's/.*reset=\(-\{0,1\}[0-9]*\).*/\1/p')
        if [ "${sshow:--1}" -ge 0 ] && [ "${sshow:--1}" -gt "${shide:--1}" ]; then
            ok "cursor restored after SIGINT (the M4 acceptance criterion)"
        else
            bad "cursor NOT restored after SIGINT: $sres"
        fi
        if [ "${sreset:--1}" -ge 0 ] && [ "${sreset:--1}" -lt "${sshow:--1}" ]; then
            ok "SGR reset emitted before the cursor was shown"
        else
            bad "SGR reset missing or out of order after SIGINT: $sres"
        fi
    fi
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "pty-check: PASS"
    exit 0
fi
echo "pty-check: FAIL"
exit 1
