#!/bin/sh
# signal-check.sh — animation signal semantics and frame pacing.
#
# Added at v1.3.0 (the animation slot). Covers the two things
# `animate-smoke.sh` cannot: what happens to the process SIGNAL MASK,
# and whether the frame loop stays responsive when the frame interval
# is user-supplied.
#
# Both matter because animation deliberately BLOCKS SIGHUP / SIGINT /
# SIGTERM and drains them through a signalfd instead. That is the
# right design — it lets the loop restore the cursor before exiting —
# but it means any path that blocks the signals without draining them
# leaves a process that Ctrl-C, `kill` and terminal hangup are all
# inert against. Only SIGKILL works.
#
# Four gates:
#
#   1. SIG_BLOCK rollback when signalfd(2) fails. Closes INFO 8 + 9
#      from the 2026-05-22 audit, which sat unmeasured for three
#      minors because the obvious way to test them does not work —
#      see tests/probes/sigmask-probe.cyr.
#   2. The mask IS blocked on the success path (the probe must be
#      able to tell the two apart, or gate 1 proves nothing).
#   3. Signal responsiveness is bounded by ANUENUE_TICK_MS, not by
#      -i. Before v1.3.0 the loop slept a whole interval before
#      looking; with -i 3600000 the process ignored SIGTERM for an
#      hour and `timeout` could not kill it.
#   4. -d is honoured regardless of -i, and -i actually paces frames.
#
# Usage:
#   sh scripts/signal-check.sh
#   BIN=build/anuenue-dce sh scripts/signal-check.sh

set -eu

BIN="${BIN:-build/anuenue}"
PROBE_SRC="tests/probes/sigmask-probe.cyr"

if [ ! -x "$BIN" ]; then
    echo "signal-check: $BIN not executable — run 'cyrius build src/main.cyr build/anuenue' first" >&2
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

FAIL=0
ok()   { echo "  ok: $1"; }
bad()  { echo "  FAIL: $1"; FAIL=1; }
skip() { echo "  SKIP: $1"; }

printf 'AGNOS\n' > "$WORK/in.txt"

# --- gates 1 + 2: the signal mask -----------------------------------
echo "[signal-check] SIG_BLOCK rollback on signalfd failure"

if ! command -v prlimit >/dev/null 2>&1; then
    skip "prlimit(1) unavailable — cannot force signalfd(2) to fail"
elif [ ! -f "$PROBE_SRC" ]; then
    bad "$PROBE_SRC missing"
elif ! cyrius build "$PROBE_SRC" "$WORK/sigprobe" >/dev/null 2>&1; then
    bad "sigmask probe failed to build"
else
    # Success path: the fd opens, and the three exit signals SHOULD be
    # blocked — the signalfd is what drains them. If this reports 0 the
    # probe is not observing anything and gate 1 below is vacuous.
    okline=$("$WORK/sigprobe" 2>/dev/null || true)
    fd_ok=$(printf '%s' "$okline" | sed -n 's/.*fd=\(-\{0,1\}[0-9]*\).*/\1/p')
    bits_ok=$(printf '%s' "$okline" | sed -n 's/.*exit_bits_blocked=\([0-9]*\).*/\1/p')
    if [ "${fd_ok:-x}" -ge 0 ] 2>/dev/null && [ "${bits_ok:-0}" -eq 16387 ]; then
        ok "success path: signalfd opens (fd=$fd_ok) and HUP|INT|TERM are blocked (0x4003)"
    else
        bad "success path unexpected: $okline"
    fi

    # Forced-failure path: --nofile=3 leaves only the three inherited
    # descriptors, so signalfd(2) is the first thing to ask for fd 3.
    failline=$(prlimit --nofile=3 "$WORK/sigprobe" 2>/dev/null || true)
    fd_bad=$(printf '%s' "$failline" | sed -n 's/.*fd=\(-\{0,1\}[0-9]*\).*/\1/p')
    bits_bad=$(printf '%s' "$failline" | sed -n 's/.*exit_bits_blocked=\([0-9]*\).*/\1/p')
    if [ "${fd_bad:-0}" -ge 0 ] 2>/dev/null; then
        skip "signalfd(2) still succeeded under --nofile=3 — cannot force the failure here"
    elif [ "${bits_bad:-1}" -eq 0 ]; then
        ok "failure path: fd=-1 and the mask is rolled back (no signals left blocked)"
    else
        bad "failure path LEAKED the block: exit_bits_blocked=$bits_bad with fd=$fd_bad — Ctrl-C, kill and hangup would all be inert"
    fi
fi

# --- gate 3: responsiveness is bounded by the tick, not by -i -------
echo "[signal-check] SIGTERM latency does not scale with --interval"

# -d 0 runs until signalled. A one-hour interval must not mean a
# one-hour wait for SIGTERM.
for iv in 16 3600000; do
    start=$(date +%s%N)
    set +e
    timeout 3 "$BIN" -a -d 0 --color=24bit -i "$iv" < "$WORK/in.txt" >/dev/null 2>&1
    set -e
    end=$(date +%s%N)
    ms=$(( (end - start) / 1000000 ))
    # timeout fires at 3000 ms; anything close to that means the signal
    # was acted on. A hang shows up as the harness timeout, not this.
    if [ "$ms" -lt 4000 ]; then
        ok "--interval $iv: process ended ${ms}ms after a 3s SIGTERM"
    else
        bad "--interval $iv: process took ${ms}ms to die after SIGTERM"
    fi
done

# --- gate 4: -d honoured regardless of -i, and -i paces frames ------
echo "[signal-check] --duration is honoured regardless of --interval"
for iv in 16 1000 3600000; do
    start=$(date +%s)
    set +e
    timeout 20 "$BIN" -a -d 1 --color=24bit -i "$iv" < "$WORK/in.txt" >/dev/null 2>&1
    rc=$?
    set -e
    end=$(date +%s)
    el=$((end - start))
    if [ "$rc" -eq 0 ] && [ "$el" -le 3 ]; then
        ok "--interval $iv --duration 1: exited 0 after ${el}s"
    else
        bad "--interval $iv --duration 1: rc=$rc after ${el}s (expected 0 within ~1s)"
    fi
done

echo "[signal-check] --interval actually paces frames"
UP=$(printf '\033[1A')
prev=0
D=0
for iv in 50 200; do
    n=$(timeout 20 "$BIN" -a -d 2 --color=24bit -i "$iv" < "$WORK/in.txt" 2>/dev/null | grep -acF "$UP" || true)
    # ~2000/iv frames, allowing generous slack for render time and load.
    lo=$(( (2000 / iv) / 3 ))
    hi=$(( (2000 / iv) * 2 ))
    if [ "$n" -ge "$lo" ] && [ "$n" -le "$hi" ]; then
        ok "--interval $iv over 2s: $n frames (expected roughly $((2000 / iv)))"
    else
        bad "--interval $iv over 2s: $n frames, outside [$lo, $hi]"
        D=1
    fi
    prev=$n
done
[ "$D" -eq 0 ] || bad "frame pacing did not track --interval"

echo "[signal-check] --interval validation"
for v in 0 -1; do
    set +e
    "$BIN" -a -i "$v" < "$WORK/in.txt" >/dev/null 2>"$WORK/e"
    rc=$?
    set -e
    if [ "$rc" -eq 2 ] && grep -q 'interval must be > 0' "$WORK/e"; then
        ok "--interval $v is a usage error"
    else
        bad "--interval $v exited $rc without the expected message"
    fi
done

# A value large enough to truncate badly inside sleep_ms must be
# clamped, not passed through.
set +e
timeout 20 "$BIN" -a -d 1 --color=24bit -i 4294967296 --log-level=warn \
    < "$WORK/in.txt" >/dev/null 2>"$WORK/c.err"
rc=$?
set -e
if [ "$rc" -eq 0 ] && grep -q 'interval clamped' "$WORK/c.err"; then
    ok "--interval 4294967296 is clamped and says so (would truncate to 0 = busy loop)"
else
    bad "--interval 4294967296: rc=$rc, no clamp warning"
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "signal-check: PASS"
    exit 0
fi
echo "signal-check: FAIL"
exit 1
