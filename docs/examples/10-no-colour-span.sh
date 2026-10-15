#!/bin/sh
# 10-no-colour-span.sh — keep part of your output out of the rainbow.
#
# From v1.5.0 a producer can bracket text with an APC marker pair:
#
#     ESC _ anuenue:off ESC \   ...text...   ESC _ anuenue:on ESC \
#
# anuenue passes the bracketed bytes through untinted, with the producer's
# own colour codes intact, and resets the colour at both markers. The
# rainbow pauses across the span. Terminals ignore an APC, so the same
# output renders cleanly when anuenue is not in the pipe.
#
# See ADR 0006 (docs/adr/0006-no-colour-spans.md).

set -eu
BIN="${BIN:-./build/anuenue}"

# A producer-side helper: print $1 as a no-colour span.
nocolour() { printf '\033_anuenue:off\033\\%s\033_anuenue:on\033\\' "$1"; }

echo "1. A span in the default colour, between rainbow text."
{ printf 'rainbow '; nocolour "plain"; printf ' rainbow\n'; } | "$BIN" --color=24bit
echo

echo "2. The span keeps the producer's own colour — a warning that must stay red."
{ printf 'status: '; nocolour "$(printf '\033[1;31mDISK FULL\033[0m')"; printf ' (see df -h)\n'; } \
    | "$BIN" --color=24bit
echo

echo "3. The rainbow pauses across a span: remove the span, and the colours are"
echo "   exactly those of the text without it."
a=$(printf 'abcdef\n' | "$BIN" --color=24bit | cksum)
b=$({ printf 'abc'; nocolour "SPAN"; printf 'def\n'; } | "$BIN" --color=24bit \
        | sed "s/$(printf '\033')\[0mSPAN$(printf '\033')\[0m//" | cksum)
if [ "$a" = "$b" ]; then
    echo "   OK: same colours with and without the span  ($a)"
else
    echo "   FAIL: the span moved the rainbow  $a vs $b"
    exit 1
fi
echo

echo "4. MONO (NO_COLOR, --no-color, a pipe) consumes the markers: plain text out."
out=$({ printf 'abc'; nocolour "SPAN"; printf 'def\n'; } | NO_COLOR=1 "$BIN")
if [ "$out" = "abcSPANdef" ]; then
    echo "   OK: '$out'"
else
    echo "   FAIL: markers leaked: $(printf '%s' "$out" | od -c | head -2)"
    exit 1
fi
echo

echo "5. -v counts the markers (stderr only; stdout is unchanged)."
{ printf 'a'; nocolour "b"; printf 'c\n'; } | "$BIN" --color=24bit -v 2>&1 >/dev/null \
    | grep 'no-colour markers' || true
