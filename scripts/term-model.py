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
# SGR and every other CSI / DEC private mode are consumed and ignored.
# Display width: 2 for UAX #11 East Asian Wide / Fullwidth, 0 for
# combining marks and format characters, 1 otherwise (Python's
# unicodedata — the oracle anuenue's generated ADR 0005 table is checked
# against).
#
# Usage: python3 -I scripts/term-model.py ROWS COLS TRANSCRIPT
# Prints: frames=N scrolled_first=A scrolled_total=B
# A correct animation scrolls during its first frame (if the block lands
# low on the screen) and never again: scrolled_total == scrolled_first.
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

    def feed(self, data):
        t = data.decode("utf-8", "replace")
        i, n = 0, len(t)
        while i < n:
            ch = t[i]
            if ch == "\x1b" and i + 1 < n and t[i + 1] == "[":
                j = i + 2
                while j < n and not ("@" <= t[j] <= "~"):
                    j += 1
                if j < n and t[j] == "A":
                    p = t[i + 2:j]
                    k = int(p) if p.isdigit() else 1
                    self.r = max(0, self.r - max(k, 1))
                    self.pending = False
                    self.ups += 1
                i = j + 1
                continue
            if ch == "\r":
                self.c = 0
                self.pending = False
            elif ch == "\n":
                self.c = 0
                self.pending = False
                self.newline()
            elif ord(ch) >= 0x20:
                self.put(ch)
            i += 1
        return self


def main():
    rows, cols, path = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
    data = open(path, "rb").read()
    m = re.search(rb"\x1b\[\d*A", data)
    first = data[:m.start()] if m else data
    t1 = Term(rows, cols).feed(first)
    t = Term(rows, cols).feed(data)
    print("frames=%d scrolled_first=%d scrolled_total=%d" % (t.ups + 1, t1.scrolled, t.scrolled))


main()
