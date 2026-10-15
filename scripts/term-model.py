# scripts/term-model.py — a minimal terminal, for reading back what an
# animation does to the screen (v1.4.4, H-01).
#
# script(1) transcribes bytes; it does not emulate a terminal, so
# pty-check.sh could never ask "did that frame land where the last one
# did?". This models the few operations anuenue's animation emits, with
# xterm semantics:
#
#   printable text    deferred autowrap; a wide character that does not
#                     fit the last column starts the next row
#   LF                the transcript already carries the tty's CR LF
#                     (ONLCR); LF alone also returns to column 0 here
#   CR                column 0
#   CSI n A           cursor up n (0 -> 1), stopping at the top row
#   scrolling         an LF on the bottom row pushes the top row into
#                     scrollback — the count this model exists to report
#
# SGR and every other CSI / DEC private mode are consumed and ignored, and
# OSC / DCS / SOS / PM / APC strings are swallowed (see Term.feed).
# Display width: 2 for UAX #11 East Asian Wide / Fullwidth, 0 for
# combining marks and format characters, 1 otherwise (Python's
# unicodedata — the oracle anuenue's generated ADR 0005 table is checked
# against).
#
# Usage: python3 -I scripts/term-model.py ROWS COLS TRANSCRIPT
# Prints: frames=N scrolled_first=A scrolled_total=B anchors=C overclimb=D
# A correct animation scrolls during its first frame (if the block lands
# low on the screen) and never again: scrolled_total == scrolled_first.
# Every cursor-up aims for the same row (anchors=1), never above the top
# (overclimb=0) — a climb that is too far scrolls nothing (v1.5.0).
import re
import sys
import unicodedata


def width(ch):
    o = ord(ch)
    if unicodedata.category(ch) in ("Mn", "Me", "Cf"):
        return 0
    if 0xFE00 <= o <= 0xFE0F:
        return 0
    if unicodedata.east_asian_width(ch) in ("W", "F"):
        return 2
    return 1


class Term:
    def __init__(self, rows, cols):
        self.R, self.C = rows, cols
        self.r = self.c = 0
        self.pending = False
        self.scrolled = 0
        self.ups = 0
        self.targets = []           # the row each cursor-up aimed for

    def newline(self):
        if self.r == self.R - 1:
            self.scrolled += 1
        else:
            self.r += 1

    def put(self, ch):
        w = width(ch)
        if w == 0:
            return
        if self.pending or self.c + w > self.C:
            self.c = 0
            self.newline()
            self.pending = False
        self.c += w
        if self.c >= self.C:
            self.c = self.C - 1
            self.pending = True

    def control(self, ch):
        if ch == "\r":
            self.c = 0
            self.pending = False
        elif ch == "\n":
            self.c = 0
            self.pending = False
            self.newline()

    def feed(self, data):
        # The VT500 parser's states that decide what prints (xterm): ESC
        # restarts from any state; CAN / SUB abort; C0 controls execute in
        # ground, escape and CSI, and are swallowed in a string; ESC [ is a
        # CSI to its final byte (0x40-0x7E), ESC ] an OSC to BEL or ST, ESC P
        # / X / ^ / _ a DCS / SOS / PM / APC string to ST (ESC \ — an ESC and
        # a final byte); 0x20-0x2F after an ESC are intermediates, after
        # which any byte 0x30-0x7E is the final one ([ and ] included); DEL
        # is ignored; a non-ASCII character ends an escape or CSI and prints.
        # v1.5.0: no-colour spans put the producer's sequences on the wire
        # intact. Before, every input ESC was cancelled by anuenue's own, so
        # only CSI (anuenue's SGRs, and cursor-up) ever arrived whole.
        t = data.decode("utf-8", "replace")
        st, params = "ground", ""
        for ch in t:
            o = ord(ch)
            if ch == "\x1b":
                st = "esc"
                continue
            if o in (0x18, 0x1A):
                st = "ground"
                continue
            if st in ("osc", "str"):
                if st == "osc" and ch == "\x07":
                    st = "ground"
                continue
            if o < 0x20:
                self.control(ch)
                continue
            if o == 0x7F:
                continue
            if st == "esci":            # after an intermediate: a final byte
                if o <= 0x2F:
                    continue
                st = "ground"
                if o < 0x7F:
                    continue
            elif st == "esc":
                if o <= 0x2F:
                    st = "esci"
                    continue
                if o < 0x7F:
                    st = {"[": "csi", "]": "osc", "P": "str", "X": "str",
                          "^": "str", "_": "str"}.get(ch, "ground")
                    params = ""
                    continue
                st = "ground"
            elif st == "csi":
                if o < 0x40:
                    params += ch
                    continue
                if o <= 0x7E:
                    if ch == "A":
                        k = int(params) if params.isdigit() else 1
                        self.targets.append(self.r - max(k, 1))
                        self.r = max(0, self.r - max(k, 1))
                        self.pending = False
                        self.ups += 1
                    st = "ground"
                    continue
                st = "ground"
            self.put(ch)
        return self


def main():
    rows, cols, path = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
    data = open(path, "rb").read()
    m = re.search(rb"\x1b\[\d*A", data)
    first = data[:m.start()] if m else data
    t1 = Term(rows, cols).feed(first)
    t = Term(rows, cols).feed(data)
    # Every frame must climb back to the same row (anchors=1), and never past
    # the top (overclimb=0): a climb that is too far draws each frame higher,
    # over whatever is above the block, without scrolling anything.
    print("frames=%d scrolled_first=%d scrolled_total=%d anchors=%d overclimb=%d" % (
        t.ups + 1, t1.scrolled, t.scrolled, len(set(t.targets)),
        sum(1 for x in t.targets if x < 0)))


main()
