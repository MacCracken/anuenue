#!/bin/sh
# fault-check.sh — the branches nothing outside the process can reach.
#
# v1.4.4. Four guards had been recorded as UNPROVEN, each guarded and
# each untested, because no input, flag, signal or resource limit reaches
# them from outside:
#
#   D-01 (v1.3.2) — _frame_wait's zero-tick guard. ANUENUE_TICK_MS is a
#                   module constant; no flag sets it.
#   E-01 (v1.3.3) — anuenue_write_all treating write(2) == 0 for a
#                   non-zero length as fatal rather than looping.
#   EINTR (v1.3.5) — the retry on both the read and the write side.
#                   anuenue installs no handlers, and default-disposition
#                   signals do not interrupt a blocking syscall.
#   NOMEM (v1.4.1) — cmdit_new's OOM. Proven by allocfail-check.sh since
#                   v1.4.4, not here.
#   And one the v1.4.4 sweep found recorded the same way in
#   src/animate.cyr: the exit signalfd's fd_set_nonblocking failing.
#
# Three layers (the third measures rather than injects):
#
#   1. The module layer, for D-01: tests/probes/tick-probe.cyr sets the
#      tick to 0 and to -5 and calls _frame_wait. Without the guard the
#      call never returns, so it runs under a timeout.
#   2. The syscall layer, for E-01 and EINTR: scripts/gdb-inject.py runs
#      the REAL binary under gdb and alters exactly one syscall — the
#      first matching read or write — then lets the rest through. That
#      is the only way to make the kernel return 0 from a write, or EINTR
#      from a read, to a process that never asked for either. Skipped
#      cleanly without gdb, without ptrace permission, or off x86_64.
#   3. The capability surface: every syscall each route makes, caught
#      under gdb by scripts/gdb-syscalls.py, checked against an
#      allowlist (v1.4.4).
#
# Usage:
#   sh scripts/fault-check.sh
#   BIN=build/anuenue-dce sh scripts/fault-check.sh

set -eu

BIN="${BIN:-build/anuenue}"
PROBE_SRC="tests/probes/tick-probe.cyr"
INJECT="scripts/gdb-inject.py"

if [ ! -x "$BIN" ]; then
    echo "fault-check: $BIN not executable — run 'cyrius build src/main.cyr build/anuenue' first" >&2
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

FAIL=0
ok()   { echo "  ok: $1"; }
bad()  { echo "  FAIL: $1"; FAIL=1; }
skip() { echo "  SKIP: $1"; }

# --- layer 1: D-01, the zero-tick guard ------------------------------
echo "[fault-check] D-01 — _frame_wait with a non-positive tick"
if ! cyrius build "$PROBE_SRC" "$WORK/tickprobe" >/dev/null 2>&1; then
    bad "tick probe failed to build"
else
    set +e
    timeout 10 "$WORK/tickprobe" > "$WORK/tick.out" 2>&1
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] && grep -q '^tick 0: returned' "$WORK/tick.out" \
        && grep -q '^tick -5: returned' "$WORK/tick.out"; then
        ok "a zero and a negative tick both return (the guard holds)"
    elif [ "$rc" -eq 124 ]; then
        bad "_frame_wait never returned with a non-positive tick — the guard is gone"
    else
        bad "tick probe exited $rc: $(head -c 200 "$WORK/tick.out")"
    fi
fi

# --- layer 2: E-01 and EINTR, under gdb ------------------------------
echo "[fault-check] E-01 + EINTR — one injected syscall fault each"
GDB_OK=1
if ! command -v gdb >/dev/null 2>&1; then
    skip "gdb(1) unavailable — syscall injection not run"; GDB_OK=0
elif [ "$(uname -m)" != "x86_64" ]; then
    skip "not x86_64 — $INJECT names x86_64 registers"; GDB_OK=0
else
    # Premise: gdb can run and trace a child here (ptrace may be locked down).
    if ! ANUENUE_INJECT="read:0:eintr" ANUENUE_RUN="--version > /dev/null" \
        timeout 60 gdb -q -batch -x "$INJECT" "$BIN" 2>/dev/null | grep -q '^INJECTED [01] EXIT 0'; then
        skip "gdb cannot trace a child here (ptrace restricted?) — injection not run"; GDB_OK=0
    fi
fi

# $1 label, $2 inject spec, $3 expected rc, $4 "same" (stdout must equal the
# reference) or a stderr substring that must appear, $5.. anuenue args.
_inject() {
    _label=$1; _spec=$2; _want_rc=$3; _want=$4; shift 4
    "$BIN" "$@" < "$WORK/in" > "$WORK/ref.out" 2>/dev/null || true
    set +e
    _res=$(ANUENUE_INJECT="$_spec" \
        ANUENUE_RUN="$* < $WORK/in > $WORK/inj.out 2> $WORK/inj.err" \
        timeout 120 gdb -q -batch -x "$INJECT" "$BIN" 2>/dev/null | grep '^INJECTED')
    _grc=$?
    set -e
    set -- $_res
    if [ "$_grc" -ne 0 ] || [ "${2:-0}" != "1" ]; then
        bad "$_label: nothing injected (premise failed) — '$_res'"
        return 0
    fi
    _rc=$4
    if [ "$_want" = "same" ]; then
        if [ "$_rc" = "$_want_rc" ] && cmp -s "$WORK/inj.out" "$WORK/ref.out"; then
            ok "$_label: retried, exit $_rc, stdout identical to an uninjected run"
        else
            bad "$_label: exit $_rc (want $_want_rc), stdout $(wc -c < "$WORK/inj.out") B vs $(wc -c < "$WORK/ref.out") B"
        fi
    else
        if [ "$_rc" = "$_want_rc" ] && grep -q "$_want" "$WORK/inj.err"; then
            ok "$_label: exit $_rc, '$_want'"
        else
            bad "$_label: exit $_rc (want $_want_rc), stderr '$(head -c 120 "$WORK/inj.err")'"
        fi
    fi
}

if [ "$GDB_OK" -eq 1 ]; then
    printf 'AGNOS rainbow\nsecond line \303\251 \346\227\245\n' > "$WORK/in"
    _inject "E-01: write(2) returns 0 (filter)" "write:1:zero" 1 \
        "write to stdout failed" --color=24bit
    _inject "E-01: write(2) returns 0 (MONO passthrough)" "write:1:zero" 1 \
        "write to stdout failed" --color=none
    _inject "EINTR on write (filter)"  "write:1:eintr" 0 same --color=24bit
    _inject "EINTR on read (filter)"   "read:0:eintr"  0 same --color=24bit
    _inject "EINTR on write (MONO)"    "write:1:eintr" 0 same --color=none
    _inject "EINTR on read (MONO)"     "read:0:eintr"  0 same --color=none
    _inject "EINTR on read (animation slurp)" "read:0:eintr" 0 same \
        -a -d 1 -i 400 --color=16
    # The signalfd's fd_set_nonblocking failing (F_GETFL / F_SETFL — the
    # first fcntl(2) the process makes). Animation must give the fd back,
    # unblock exactly what it added, say so at warn level, and still
    # render every frame.
    _inject "signalfd fcntl fails (EINVAL)" "fcntl:*:fail22" 0 \
        "signalfd not made non-blocking" -a -d 1 -i 400 --color=16 --log-level=warn
    if cmp -s "$WORK/inj.out" "$WORK/ref.out"; then
        ok "signalfd fcntl fails: the frames are identical to an uninjected run"
    else
        bad "signalfd fcntl fails: stdout differs from an uninjected run"
    fi
fi

# --- layer 3: the capability surface, measured (v1.4.4) --------------
#
# CLAUDE.md's bound — stdin / stdout / stderr + argv, no surprise
# syscalls — had only ever been checked by reading the source, and the
# documented surface had drifted: it named brk(2), which no route has
# issued since the stdlib heap moved to mmap at cyrius 6.1.19 (H-03).
# Each route's syscalls, caught under gdb, must stay inside its
# allowlist (x86_64 numbers). A new syscall is not necessarily wrong,
# but it must be a decision, recorded in docs/adr/0001's table and here.
#   base   0 read, 1 write, 2 open, 3 close, 9 mmap, 60 exit
#   auto   + 16 ioctl (tty_isatty)
#   anim   + 7 poll, 14 rt_sigprocmask, 16 ioctl, 72 fcntl,
#            228 clock_gettime, 289 signalfd4
#   -v     + 35 nanosleep, 228 clock_gettime
echo "[fault-check] capability surface — every syscall of each route"
if [ "$GDB_OK" -eq 1 ]; then
    _surface() {   # $1 label, $2 allowlist, $3.. gdb run string
        _label=$1; _allow=" $2 "; shift 2
        _got=$(ANUENUE_RUN="$*" timeout 120 gdb -q -batch -x scripts/gdb-syscalls.py "$BIN" 2>/dev/null \
            | sed -n 's/^SYSCALLS //p')
        if [ -z "$_got" ]; then
            bad "$_label: no syscalls recorded (premise failed)"
            return 0
        fi
        _extra=""
        for _n in $_got; do
            case "$_allow" in *" $_n "*) ;; *) _extra="$_extra $_n" ;; esac
        done
        if [ -z "$_extra" ]; then
            ok "$_label: {$(echo $_got | tr ' ' ',')} within the allowlist"
        else
            bad "$_label: syscall(s)$_extra outside the allowlist (saw: $_got)"
        fi
    }
    _base="0 1 2 3 9 60"
    _surface "filter, forced colour" "$_base" "--color=24bit < $WORK/in > /dev/null"
    _surface "filter, auto colour"   "$_base 16" "< $WORK/in > /dev/null"
    _surface "MONO passthrough"      "$_base 16" "--color=none < $WORK/in > /dev/null"
    _surface "one-shot text"         "$_base 16" "--color=24bit hello > /dev/null"
    _surface "usage error"           "$_base" "--bogus > /dev/null 2>/dev/null"
    _surface "animation"             "$_base 7 14 16 72 228 289" \
        "-a -d 1 -i 400 --color=16 < $WORK/in > /dev/null"
    _surface "filter with -v"        "$_base 35 228" "-v --color=24bit < $WORK/in > /dev/null 2>/dev/null"
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "fault-check: PASS"
    exit 0
fi
echo "fault-check: FAIL"
exit 1
