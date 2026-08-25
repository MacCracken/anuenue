#!/bin/sh
# 09-diagnostics.sh — verbose diagnostics, and the guarantee that they
# cannot touch stdout.
#
# anuenue lives in the middle of pipelines, so its diagnostics go to
# stderr and nowhere else. This example demonstrates the invariant
# rather than just describing it: the same command with and without
# -v produces byte-identical stdout.
#
# See ADR 0004 (docs/adr/0004-stderr-only-observability.md).

set -eu
BIN="${BIN:-./build/anuenue}"

echo "1. Default: silent on stderr."
"$BIN" --color=24bit AGNOS 2>/tmp/anuenue-ex9.err >/dev/null
echo "   stderr bytes at default verbosity: $(wc -c < /tmp/anuenue-ex9.err)"
echo

echo "2. -v: structured records on stderr (note 'reason=' — WHY this colour mode)."
"$BIN" --color=24bit -v AGNOS 2>&1 >/dev/null
echo

echo "3. --log-level=warn: silent on a clean run."
"$BIN" --color=24bit --log-level=warn AGNOS 2>/tmp/anuenue-ex9.err >/dev/null
echo "   stderr bytes at warn: $(wc -c < /tmp/anuenue-ex9.err)"
echo "   (debug records filtered by level; spans are gated at debug-or-finer)"
echo

echo "4. The invariant: stdout is byte-identical with and without -v."
a=$("$BIN" --color=24bit -s 42 AGNOS 2>/dev/null | cksum)
b=$("$BIN" --color=24bit -s 42 -v AGNOS 2>/dev/null | cksum)
if [ "$a" = "$b" ]; then
    echo "   OK: stdout unchanged by -v  ($a)"
else
    echo "   FAIL: -v moved stdout!  $a vs $b"
    exit 1
fi
echo

echo "5. Diagnosing a colour-mode surprise — the v1.1.5 bug class."
echo "   Piping to a file drops anuenue to MONO. '-v' says so explicitly:"
"$BIN" -v AGNOS 2>&1 >/dev/null | grep reason= || true

rm -f /tmp/anuenue-ex9.err
