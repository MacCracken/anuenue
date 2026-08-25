#!/bin/sh
# allocfail-check.sh — every allocation guard, under a genuinely
# exhausted heap.
#
# v1.3.4. Closes the standing "unproven guard" gap that three audits
# recorded in a row:
#
#   A-01 (v1.2.2) `_cp_ext_init`'s alloc check
#   E-01 (v1.3.3) `anuenue_fail`'s own `str_new` fallback
#   ...plus the eight other guarded `alloc` call sites
#
# All were correct by inspection and tested by nothing, because no
# external mechanism could drive `alloc` to return 0. This does.
#
# MECHANISM
#
# `lib/alloc.cyr` bump-allocates over 256 MiB mmap'd chunks and returns
# 0 only when a fresh chunk cannot be mapped. `prlimit --as=400MiB`
# leaves room for the first chunk (so `alloc_init` does not exit(1) at
# startup and take the whole process with it) but not a second. The
# probe then drains the first chunk, after which every allocation in
# the process returns 0 — however small.
#
# Mutation-proven: deleting either guard makes the probe **segfault**
# (exit 139) rather than merely fail an assertion. That is the whole
# point — the guards are the only thing between a starved process and
# a null-pointer write.
#
# WHY 400 MiB IS NOT ARBITRARY
#
# It is one chunk's worth of headroom over `_LINUX_CHUNK` (256 MiB).
# If the stdlib ever changes that constant this number stops working —
# so the probe asserts the premise first ("alloc(64) returns 0") and
# this script fails loudly on a vacuous run rather than reporting a
# pass for the wrong reason.
#
# Usage:
#   sh scripts/allocfail-check.sh

set -eu

PROBE_SRC="tests/probes/allocfail-probe.cyr"
AS_LIMIT=$((400 * 1024 * 1024))

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

ok()   { echo "  ok: $1"; }
bad()  { echo "  FAIL: $1"; }
skip() { echo "  SKIP: $1"; }

echo "[allocfail-check] allocation guards under heap exhaustion"

if ! command -v prlimit >/dev/null 2>&1; then
    skip "prlimit(1) unavailable — cannot bound the address space"
    echo
    echo "allocfail-check: PASS (skipped)"
    exit 0
fi
if [ ! -f "$PROBE_SRC" ]; then
    bad "$PROBE_SRC missing"
    echo
    echo "allocfail-check: FAIL"
    exit 1
fi
if ! cyrius build "$PROBE_SRC" "$WORK/allocfail" >/dev/null 2>&1; then
    bad "allocation-failure probe failed to build"
    echo
    echo "allocfail-check: FAIL"
    exit 1
fi

set +e
prlimit --as="$AS_LIMIT" "$WORK/allocfail" > "$WORK/out" 2>"$WORK/err"
RC=$?
set -e

# Show the probe's own report — it names each guard it exercised.
sed 's/^/  /' "$WORK/out"

# The premise. A limit too generous to starve the allocator would let
# every check below "pass" without testing anything.
if ! grep -q 'heap is exhausted: alloc(64) returns 0' "$WORK/out"; then
    echo
    bad "the heap was NOT exhausted — this run proved nothing."
    echo "       --as=$AS_LIMIT left room for a second chunk. If lib/alloc.cyr's"
    echo "       _LINUX_CHUNK changed, lower AS_LIMIT in this script to match."
    echo
    echo "allocfail-check: FAIL"
    exit 1
fi

echo
case "$RC" in
    0)
        ok "every allocation guard held with no heap available"
        echo "allocfail-check: PASS"
        exit 0
        ;;
    1)
        bad "a guard did not hold — see the FAIL line(s) above"
        ;;
    139)
        bad "the probe SEGFAULTED (exit 139) — a guard is missing, not merely wrong."
        echo "       This is the signature of an unchecked alloc: the process wrote"
        echo "       through a null pointer instead of reporting the failure."
        ;;
    *)
        bad "probe exited $RC"
        [ -s "$WORK/err" ] && sed 's/^/       stderr: /' "$WORK/err"
        ;;
esac
echo "allocfail-check: FAIL"
exit 1
