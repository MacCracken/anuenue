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
# Five gates:
#
#   1. SIG_BLOCK rollback when signalfd(2) fails. Closes INFO 8 + 9
#      from the 2026-05-22 audit, which sat unmeasured for three
#      minors because the obvious way to test them does not work —
#      see tests/probes/sigmask-probe.cyr. v1.4.0: a signal blocked
#      BEFORE animation (SIGHUP, in the probe's `preblocked` case)
#      must still be blocked after the rollback — the v1.3.6
#      hand-rolled open unblocked the whole mask.
#   2. The success path: the mask IS blocked (the probe must be able
#      to tell the two apart, or gate 1 proves nothing), the fd is
#      close-on-exec and non-blocking (v1.4.0), and the close gives
#      back exactly what the open took — a pre-blocked SIGHUP stays
#      blocked.
#   3. Signal responsiveness is bounded by ANUENUE_TICK_MS, not by
#      -i. Before v1.3.0 the loop slept a whole interval before
#      looking; with -i 3600000 the process ignored SIGTERM for an
#      hour and `timeout` could not kill it.
#   4. -d is honoured regardless of -i, and -i actually paces frames.
#   5. Two exit signals at once still exit 0 (v1.4.0): the frame loop
#      reads one, and the teardown must drain the other before its
#      unblock, or the second is delivered with its default action.
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
echo "[signal-check] signal mask across the exit signalfd's open and close"

# Pull `key=value` out of the probe line for case $2. Prints the value,
# or nothing if the line or the key is missing.
probe_field() {
    printf '%s\n' "$1" | grep "^case=$2 " | sed -n "s/.* $3=\(-\{0,1\}[0-9]*\).*/\1/p"
}

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
    okout=$("$WORK/sigprobe" 2>/dev/null || true)
    fd_ok=$(probe_field "$okout" plain fd)
    bits_ok=$(probe_field "$okout" plain exit_bits_blocked)
    if [ "${fd_ok:-x}" -ge 0 ] 2>/dev/null && [ "${bits_ok:-0}" -eq 16387 ]; then
        ok "success path: signalfd opens (fd=$fd_ok) and HUP|INT|TERM are blocked (0x4003)"
    else
        bad "success path unexpected: $okout"
    fi
    if [ "$(probe_field "$okout" plain cloexec)" = "1" ]; then
        ok "the exit signalfd is close-on-exec (v1.3.6's was not)"
    else
        bad "the exit signalfd is not close-on-exec: $okout"
    fi
    if [ "$(probe_field "$okout" plain nonblock)" = "1" ]; then
        ok "the exit signalfd is non-blocking — the frame loop probes it, never waits on it"
    else
        bad "the exit signalfd is BLOCKING — the frame loop would stall in read(2): $okout"
    fi
    if [ "$(probe_field "$okout" plain after_close_exit_bits)" = "0" ]; then
        ok "the close unblocks HUP|INT|TERM again"
    else
        bad "signals still blocked after the close: $okout"
    fi
    if [ "$(probe_field "$okout" preblocked after_close_exit_bits)" = "1" ]; then
        ok "the close gives back only what the open took: a pre-blocked SIGHUP stays blocked"
    else
        bad "the close unblocked a signal anuenue did not block: $okout"
    fi

    # Forced-failure path: --nofile=3 leaves only the three inherited
    # descriptors, so signalfd(2) is the first thing to ask for fd 3.
    failout=$(prlimit --nofile=3 "$WORK/sigprobe" 2>/dev/null || true)
    fd_bad=$(probe_field "$failout" plain fd)
    bits_bad=$(probe_field "$failout" plain exit_bits_blocked)
    if [ "${fd_bad:-0}" -ge 0 ] 2>/dev/null; then
        skip "signalfd(2) still succeeded under --nofile=3 — cannot force the failure here"
    else
        if [ "${bits_bad:-1}" -eq 0 ]; then
            ok "failure path: fd=-1 and the mask is rolled back (no signals left blocked)"
        else
            bad "failure path LEAKED the block: exit_bits_blocked=$bits_bad with fd=$fd_bad — Ctrl-C, kill and hangup would all be inert"
        fi
        # The v1.0.2-class defect the darshana consumer survey found in
        # the hand-rolled copy: a rollback that unblocks the WHOLE mask
        # also unblocks a signal that was blocked before animation began.
        # Measured on v1.3.6 with a scratch build of this case: SIGHUP
        # came back unblocked.
        bits_pre=$(probe_field "$failout" preblocked exit_bits_blocked)
        if [ "${bits_pre:-x}" = "1" ]; then
            ok "failure path: a pre-blocked SIGHUP is still blocked after the rollback"
        else
            bad "failure path unblocked a signal it never blocked: exit_bits_blocked=${bits_pre:-?} (want 1) — $failout"
        fi
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

# A value above the one-hour cap is clamped, not passed through, and
# says so. (Through cyrius 6.6.19 this exact value truncated to 0 inside
# sleep_ms — a busy loop; the stdlib clamps since 6.6.20, and anuenue's
# own cap stays as user-visible behaviour.)
set +e
timeout 20 "$BIN" -a -d 1 --color=24bit -i 4294967296 --log-level=warn \
    < "$WORK/in.txt" >/dev/null 2>"$WORK/c.err"
rc=$?
set -e
if [ "$rc" -eq 0 ] && grep -q 'interval clamped' "$WORK/c.err"; then
    ok "--interval 4294967296 is clamped to one hour and says so"
else
    bad "--interval 4294967296: rc=$rc, no clamp warning"
fi

# --- gate 5: two exit signals at once still exit 0 -------------------
#
# The frame loop reads ONE signal per probe and stops. If a second exit
# signal is already pending, the teardown's unblock (darshana's
# tty_close_signalfd, the LAST step) delivers it with its default action
# unless it was drained first — and death-by-SIGTERM is exit 143, not
# the documented 0. Through v1.3.6 nothing was ever unblocked, so the
# second signal simply died with the process; v1.4.0 restores the mask,
# so it has to drain. Mutation-proven: without the drain this exits 143.
echo "[signal-check] two exit signals at once still exit 0"
set +e
"$BIN" -a -d 0 --color=24bit < "$WORK/in.txt" > /dev/null 2>&1 &
APID=$!
sleep 0.5
kill -INT "$APID" 2>/dev/null
kill -TERM "$APID" 2>/dev/null
wait "$APID"
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
    ok "SIGINT + SIGTERM together: exit 0 (the teardown drained the second)"
else
    bad "SIGINT + SIGTERM together: exit $rc (want 0) — a signal was delivered by the teardown's unblock"
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "signal-check: PASS"
    exit 0
fi
echo "signal-check: FAIL"
exit 1
