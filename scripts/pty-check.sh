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
# Gates 0-4 do not read terminal state back. `script` transcribes bytes;
# it does not emulate a terminal, so there is no "is the cursor visible"
# to query, and those assertions are about the byte stream and the
# process. Gate 5 (v1.4.4) adds the one piece of terminal state that
# matters to animation — where the cursor lands and how much scrolls —
# by feeding the transcript to scripts/term-model.py, a model of the few
# operations animation emits. It still does not read cursor visibility.
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
# The process name pgrep / pkill match: BIN's basename, cut to the 15
# characters the kernel keeps in comm. Through v1.4.3 this was the literal
# `anuenue`, so `BIN=build/anuenue-dce sh scripts/pty-check.sh` — the
# usage above — failed gate 4 with "animation process never appeared".
BIN_NAME=$(basename "$BIN" | cut -c1-15)
trap 'rm -rf "$WORK"; pkill -9 -x "$BIN_NAME" >/dev/null 2>&1 || true' EXIT INT TERM

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
    APID=$(pgrep -x "$BIN_NAME" 2>/dev/null | head -1 || true)
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
        pkill -9 -x "$BIN_NAME" >/dev/null 2>&1 || true
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

# --- gate 5: animation on a terminal it must fit (H-01, v1.4.4) -----
#
# Re-anchoring used to climb one row per LF. A line wider than the
# terminal wraps into several rows, and a block taller than it scrolls,
# so the climb fell short and every frame scrolled a copy of the block
# into scrollback — ~60 times a second. anuenue now reads the terminal's
# size and climbs PHYSICAL rows, and draws a block that cannot fit once.
#
# Each case sizes the pty with stty(1), records the animation, and plays
# the transcript into scripts/term-model.py at the same size. Correct:
# no scrolling after the first frame, and an animation (several frames)
# exactly when the block fits.
echo "[pty-check] animation on a sized terminal re-anchors exactly"
if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 unavailable — no terminal model"
else
    # The width table first: anuenue_cp_cols for every codepoint, against
    # UAX #11 in Python's unicodedata. Only codepoints that can start a
    # cluster are compared (assigned, not combining / format), and the
    # regional indicators are 2 by decision (ADR 0005).
    if cyrius build tests/probes/width-probe.cyr "$WORK/widthprobe" >/dev/null 2>&1; then
        "$WORK/widthprobe" > "$WORK/widths.bin"
        _wres=$(python3 -I - "$WORK/widths.bin" <<'PYEOF'
import sys, unicodedata as u
got = open(sys.argv[1], "rb").read()
bad = []
for cp in range(0x40000):
    cat = u.category(chr(cp))
    if cat in ("Cn", "Cs", "Co", "Mn", "Me", "Cf"):
        continue
    want = 2 if (u.east_asian_width(chr(cp)) in ("W", "F") or 0x1F1E6 <= cp <= 0x1F1FF) else 1
    if cp < 0x1100:
        want = 1
    if got[cp] - 48 != want:
        bad.append(cp)
print("%d %d %s" % (len(got), len(bad), " ".join("U+%04X" % c for c in bad[:8])))
PYEOF
)
        set -- $_wres
        if [ "$1" = "262144" ] && [ "$2" = "0" ]; then
            ok "width table: anuenue_cp_cols matches UAX #11 at every cluster-starting codepoint to U+3FFFF"
        else
            bad "width table: $2 codepoints differ from UAX #11 (first: ${3:-}) — regenerate with scripts/gen-wide-table.py"
        fi
    else
        bad "width probe failed to build"
    fi

    python3 -I - "$WORK" <<'PYEOF'
import sys
w = sys.argv[1]
open(w + "/fit3.in", "w").write("AGNOS rainbow\nline two\nline three\n")
open(w + "/wide.in", "w").write("".join(("wide line %d " % i) + "x" * 150 + "\n" for i in range(5)))
open(w + "/cjk.in", "w").write("".join(("\u65e5\u672c %d " % i) + "\u3042" * 50 + "\n" for i in range(4)))
open(w + "/tall.in", "w").write("".join("row %02d of a tall block\n" % i for i in range(40)))
open(w + "/partial.in", "w").write("x" * 130)
# Escapes in the INPUT: anuenue's own escape cancels each input ESC, so
# the parameters print. v1.4.4's first cut counted them as zero-width and
# lost the LFs inside an unterminated sequence; these are the review's
# reproductions.
open(w + "/csi.in", "w").write(("\x1b[31m" + "x" * 80 + "\x1b[0m\n") * 3)
open(w + "/osc.in", "w").write("\x1b]0;title\n" + "".join("line %d\n" % i for i in range(5)))
open(w + "/bare-esc.in", "w").write("line\x1b\n" * 5)
# UAX #11 wide symbols at the end of an 80-column line (the review's MOTD
# case): 76 + 4 x 2 = 84 columns, so each line is 2 rows.
open(w + "/emoji.in", "w").write(("x" * 76 + "\u2705\u2728\u26a1\u2b50\n") * 3)
PYEOF
    # name input rows cols expect(anim|once)
    for _case in "fits fit3 24 80 anim" "wraps-but-fits wide 24 80 anim" \
                 "wide-cjk cjk 24 40 anim" "partial-line-wraps partial 10 40 anim" \
                 "taller-than-terminal tall 24 80 once" "wraps-too-tall wide 10 80 once" \
                 "input-csi csi 24 80 anim" "input-osc-unterminated osc 24 80 anim" \
                 "input-bare-esc bare-esc 24 80 anim" "wide-symbols emoji 24 80 anim"; do
        set -- $_case
        in_pty "stty rows $3 cols $4; $BIN -a -d 1 -i 150 --color=24bit < $WORK/$2.in" > "$WORK/sized.out"
        _m=$(python3 -I scripts/term-model.py "$3" "$4" "$WORK/sized.out")
        _fr=$(printf '%s' "$_m" | sed -n 's/.*frames=\([0-9]*\).*/\1/p')
        _s1=$(printf '%s' "$_m" | sed -n 's/.*scrolled_first=\([0-9]*\).*/\1/p')
        _st=$(printf '%s' "$_m" | sed -n 's/.*scrolled_total=\([0-9]*\).*/\1/p')
        if [ -z "$_fr" ]; then
            bad "$1 ($3x$4): the model read nothing — '$_m'"
        elif [ "$_st" -ne "$_s1" ]; then
            bad "$1 ($3x$4): $((_st - _s1)) rows scrolled after the first frame ($_fr frames)"
        elif [ "$5" = "anim" ] && [ "$_fr" -gt 1 ]; then
            ok "$1 ($3x$4): $_fr frames, nothing scrolled after the first"
        elif [ "$5" = "once" ] && [ "$_fr" -eq 1 ]; then
            ok "$1 ($3x$4): drawn once, nothing smeared"
        else
            bad "$1 ($3x$4): $_fr frames, expected $5"
        fi
    done
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "pty-check: PASS"
    exit 0
fi
echo "pty-check: FAIL"
exit 1
