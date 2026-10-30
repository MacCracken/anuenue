# 0005 — Animation counts physical rows with an inline UAX #11 display-width table

**Status**: Accepted
**Date**: 2026-10-14

## Context

`-a` animates a block in place. After each frame the renderer climbs back to
the block's first row with `CSI n A` and draws the next frame over it.
Through v1.4.3 `n` was the number of LFs, one row per line.

That count is only the number of rows on screen when every line fits the
terminal's width and the whole block fits its height. The v1.4.4 sweep
measured both failures against a terminal model (finding **H-01**,
[audit delta](../audit/2026-10-14-v14x-delta.md)):

- **A line wider than the terminal** wraps into several rows, so the climb
  falls short. Five 162-column lines in an 80-column terminal scrolled
  **8.7 rows into scrollback every frame**, even though the block fit
  vertically. A single line over 80 columns is enough.
- **A block taller than the terminal** cannot be re-anchored at all:
  cursor-up stops at the top row. A 40-line block on a 24-row screen
  scrolled 17 rows per frame.

At ~60 frames a second, either one floods the user's scrollback for the length
of the animation. Fixing the climb needs two things anuenue never had: the
terminal's size, and the **display width** of each character. Width is not
byte count, and not codepoint or cluster count either. CJK ideographs and most
emoji take two columns, and combining marks take none.

Nothing in the stack provides a width function. The stdlib's `lib/unicode`
has general categories but no East Asian Width data. darshana has the window
size (`tty_winsize`) but no widths.

## Decision

**When stdout is a terminal of known size, count the climb in physical rows,
using an inline width table generated from UAX #11. Draw a block that still
cannot fit the terminal once, and do not animate it.**

- **Size**: darshana's `tty_winsize(STDOUT)`. It is the same `TIOCGWINSZ`
  ioctl `tty_isatty` already issues, so the syscall surface does not grow. An
  unknown size (a pipe, a pty answering 0 × 0, agnos) falls back to the LF
  count. So output that is not going to a terminal is byte-identical to
  v1.4.3, and every pipe-based test and golden is unaffected.
- **Width** (`anuenue_cp_cols`, `src/animate.cyr`) is the width of a cluster's
  *base* codepoint:
  - 2 if UAX #11 calls it East Asian **Wide** or **Fullwidth**. That is every
    W / F range up to U+3FFFF in Unicode 16.0: 82 ranges after merging
    across unassigned and zero-width gaps. They include the CJK and Hangul
    blocks, the fullwidth forms, the emoji blocks, and the BMP symbols with
    emoji presentation (✅ ✨ ⚡ ⭐ ❌ ☕ …).
  - 2 for the regional indicators, by decision. UAX #11 calls them Neutral,
    but one only ever starts a cluster as half of a flag, which terminals
    draw 2 columns wide.
  - 1 for everything else, including East Asian *Ambiguous* (the Western
    default).

  The table is **generated**: `scripts/gen-wide-table.py` writes it from
  Python's `unicodedata`. `scripts/pty-check.sh` gate 5 compares
  `anuenue_cp_cols` with that same oracle at every cluster-starting
  codepoint up to U+3FFFF. The comparison only holds on the same Unicode
  version, because East Asian Width changes between versions. So the header
  names the Unicode and Python versions, and CI installs that Python. (On
  v1.4.4's first CI run the runner's older Python reported 188
  codepoints of drift.)

  Combining marks take no columns *because they almost never start a
  cluster*: the ADR 0003 classifier folds them into their base.

  *Amended at v1.5.2 (V-11):* where there is no base to fold into — at the
  start of the input, or after an LF (H-05) — an extender does start a
  cluster. Such a cluster is as wide as its first codepoint that is not an
  extender (`ZWJ x` is 1, ZWJ + 👩 is 2), and 0 if it has none (a lone mark),
  which is what a terminal shows. Through v1.5.1 the mark itself was taken as
  the base and counted 1 column, so a line of exactly the terminal's width
  that began with one counted a row too many and the block climbed a row too
  far. `_cluster_cols_past_ext`; PTY cases `mark-starts-line` and
  `zwj-emoji-starts-line`.
- **Byte-level cases** (`_block_rows`):
  - controls take no columns;
  - an ESC in the input takes none, but **the bytes after it do**. The
    renderer writes its own escape before every cluster, and an input ESC
    is a cluster of its own. So the terminal sees the input's ESC
    immediately followed by anuenue's, which cancels it, and the input
    sequence's parameters print as text. From v1.4.5 the input's SGR colour
    codes are stripped before animation runs, so this rule covers every
    *other* sequence;
  - TAB moves to the next multiple of 8 without wrapping;
  - CR returns to column 0;
  - a malformed sequence shows as one U+FFFD.
- **Wrapping** follows deferred autowrap. A line of exactly `cols` columns is
  one row, and a wide character that does not fit the last column starts the
  next row.
- **Fit**: if the climb plus the cursor's own row exceeds the terminal's
  height, the block is drawn once and the animation ends, with a `warn`
  record saying why.

## Consequences

- **Positive** — the smear is gone in every case the v1.4.4 gate covers: wide
  ASCII lines, wide CJK, a wrapping partial line, and blocks too tall in rows
  or after wrapping. `scripts/pty-check.sh` gate 5 plays a real pty's
  transcript into a terminal model at the same size and asserts that nothing
  scrolls after the first frame.
- **Positive** — pipes are untouched. The width logic only runs when the size
  is known, and the fallback is the old count exactly.
- **Negative** — anuenue now owns a width table, and a wrong entry is a
  wrong climb:
  - an undercount smears, as before;
  - an overcount climbs too far and redraws over the line above the block.

  The table is UAX #11's W / F set, generated and checked at every
  cluster-starting codepoint (above). Where it can still be wrong is where
  the standard and the terminal disagree, and that case comes next.
- **Negative** — terminals disagree where Unicode is ambiguous, and anuenue
  picks one answer per case:
  - emoji ZWJ sequences: one 2-column glyph in current terminals, several in
    older ones; anuenue counts 2;
  - flags: counted as 2;
  - East Asian *Ambiguous* characters such as `☃`: counted as 1, the
    Western default.

  A terminal configured otherwise drifts on those characters only.
- **Negative** — a block that does not fit is no longer animated. That is a
  visible change for input that "worked" before, but what it did before was
  the defect. It follows the v1.4.1 precedent in the roadmap's § v2.0.
- **Neutral** — a mid-animation resize is not handled. The size is read once,
  before the first frame, as `tty_winsize` consumers that do not watch
  SIGWINCH do. Watching SIGWINCH would mean a signalfd mask change and
  re-reading the size each frame. Nobody has asked, and the v1.4.4 gate
  does not cover it.

## Amended in-cut (v1.4.4 code review)

The first cut of this decision had two errors, both caught by the closeout's
code review before release, with reproductions.

1. **The width table was a hand-written practical subset of 17 ranges.** It
   called the BMP emoji that UAX #11 marks W 1 column wide. A line of 76
   columns followed by ✅✨⚡⭐ climbed a row short and scrolled 100 rows over
   40 frames. The "practical subset" framing could not be kept honest by
   hand, so the table became generated, and gate-checked against the full
   W / F data.
2. **Input escape sequences were skipped as zero-width** (CSI to its final
   byte, OSC to BEL / ST). That models what a terminal does with an intact
   sequence, but anuenue never delivers one intact (above). Worse, an
   unterminated OSC swallowed every LF after it, so the climb was **less**
   than v1.4.3's LF count — a regression on terminals.

## Alternatives considered

- **A hand-picked practical subset** (ADR 0003's trade for grapheme clusters)
  — tried first and withdrawn in-cut, see *Amended*. Unlike cluster rules,
  width is a single property per codepoint. So the whole W / F set is 82
  ranges, a 10-line generated table. A subset saves almost nothing and is
  wrong for exactly the symbols MOTDs use.
- **A wcwidth port, or a stdlib module** — not needed for one property. If a
  second consumer wants display width, the stdlib is the right home: file it
  upstream as an ask, rather than copy this table into the consumer.
- **Save / restore cursor (`ESC 7` / `ESC 8`) instead of climbing** — rejected.
  The saved position is a screen coordinate, and it does not move when the
  first frame scrolls the screen, which it does whenever the prompt is near
  the bottom. Climbing relative to the cursor is correct in that case.
- **Ask the terminal where the cursor is (DSR `CSI 6n`)** — rejected. The reply
  arrives on the terminal's input. anuenue's stdin is the pipe it is
  animating, so reading the reply would mean opening `/dev/tty`, which is
  file I/O that [ADR 0001](0001-pipe-purity.md) rules out.
- **Clip to the rows that fit and animate those** — rejected for now. It
  changes *what* is shown, not just how often, and needs a policy (top
  rows? bottom rows?) nobody has asked for. Drawing once is the
  conservative correct answer.
- **Document it as a limitation** — rejected. It floods scrollback at 60 Hz
  for a common input, a single line over 80 columns.
