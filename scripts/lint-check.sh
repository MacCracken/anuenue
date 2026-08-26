#!/bin/sh
# lint-check.sh — the lint gate, as one implementation.
#
# v1.3.5. This exists because local and CI disagreed twice, and both
# times the local check passed for a reason unrelated to what CI
# actually enforced.
#
# `cyrius audit` has a lint section that prints "ok: lint clean". It
# does NOT count untracked deferrals. `cyrius lint <file>` does, and
# reports them separately from warnings:
#
#     0 untracked deferrals
#     0 warnings
#
# A local gate built on `cyrius audit` therefore reports success on a
# tree that CI rejects. That is what happened at v1.3.5: a comment
# reading `mean "not yet", not "broken"` tripped the deferral heuristic,
# `cyrius audit` said lint clean, and CI failed.
#
# So the rule this file encodes: **the lint gate is per-file, and it
# requires BOTH counters at zero.** CI calls this script rather than
# inlining the loop, so the two cannot drift again.
#
# SCOPE IS WIDER THAN CI USED TO CHECK
#
# CI previously linted `src/*.cyr` only. Sweeping the whole tree while
# fixing the above turned up an untracked deferral in
# tests/anuenue.bcyr that had been sitting there unflagged — the
# reference it needed was on the line *after* the keyword, and the
# heuristic reads one line. Tests and fuzz harnesses are source too;
# they are linted here.
#
# Usage:
#   sh scripts/lint-check.sh

set -eu

FAIL=0
CHECKED=0

lint_one() {
    _f="$1"
    _out=$(cyrius lint "$_f" 2>&1 || true)
    CHECKED=$((CHECKED + 1))

    _bad=0
    if ! printf '%s\n' "$_out" | grep -qE '^0 warnings'; then _bad=1; fi
    if ! printf '%s\n' "$_out" | grep -qE '^0 untracked deferrals'; then _bad=1; fi

    if [ "$_bad" -eq 1 ]; then
        echo "  FAIL: $_f"
        printf '%s\n' "$_out" | grep -E 'deferral|warn' | sed 's/^/        /'
        FAIL=1
    fi
}

echo "[lint-check] src/ — zero warnings, zero untracked deferrals"
for f in src/*.cyr; do lint_one "$f"; done

echo "[lint-check] tests/ and fuzz/ — same bar"
for f in tests/*.tcyr tests/*.bcyr tests/probes/*.cyr fuzz/*.fcyr; do
    [ -e "$f" ] || continue
    lint_one "$f"
done

echo
if [ "$FAIL" -eq 0 ]; then
    echo "  ok: $CHECKED files clean"
    echo "lint-check: PASS"
    exit 0
fi
echo "lint-check: FAIL"
echo
echo "  A deferral is 'untracked' when the line carrying the keyword does not"
echo "  also carry a cross-reference. The heuristic reads ONE line, so a"
echo "  reference on the following line does not count. Either put the"
echo "  CHANGELOG / roadmap / issue reference on the same line, or reword —"
echo "  most hits here have been ordinary prose ('not yet', 'for now')"
echo "  rather than real deferrals."
exit 1
