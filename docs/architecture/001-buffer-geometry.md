# 001 — The line-buffer geometry is a proof, not three round numbers

Three constants in `src/filter.cyr` size the output path:

```
ANUENUE_LINE_BUF             = 32768   # the flush buffer
ANUENUE_FLUSH_RESERVE        =    32   # headroom kept free at all times
ANUENUE_ESC_TABLE_ENTRY_SIZE =    32   # 8-byte length + up to 24 escape bytes
```

They look independent. They are not — `FLUSH_RESERVE` has to be at least as
large as the worst-case single iteration, or the write loop runs off the end of
`line_buf`.

## The invariant

Every write path checks **after** writing, not before:

```
...write this cluster...
if (pos + ANUENUE_FLUSH_RESERVE > ANUENUE_LINE_BUF) { flush; pos = 0; }
```

So at the *top* of any iteration, `pos <= LINE_BUF - FLUSH_RESERVE` (32 736).
An iteration must therefore never write more than `FLUSH_RESERVE` bytes.

Worst case for one iteration:

| Component | Bytes | Source |
|---|---:|---|
| Phase escape | ≤ 24 | `ESC_TABLE_ENTRY_SIZE` − 8-byte length prefix |
| One codepoint | ≤ 4 | UTF-8 maximum |
| SGR reset (LF path) | 4 | `\e[0m` |
| LF | 1 | |
| **Total** | **≤ 29** | fits in 32 |

The longest escape *actually* emitted is 17 bytes, not the 19 of a worst-case
`\e[38;2;255;255;255m`. `hsv_rainbow` runs the cube edges at S=V=1, so one
channel is always 0 and the widest form is `\e[38;2;255;254;0m`. Measured
maxima across the 1 530-entry table: 16-colour **5**, 256 **11**, truecolor
**17** — seven bytes of slack against the 24-byte allowance.

*(Corrected at v1.3.3. An earlier draft of this note asserted 19 by arithmetic
rather than measurement; the v1.3.3 sweep measured it. The bound still holds
either way, but a note whose numbers are derived rather than observed is the
kind this directory exists to replace.)*

## What breaks if you change one

- **Raising `ESC_TABLE_ENTRY_SIZE`** without raising `FLUSH_RESERVE` lets the
  escape alone approach the reserve, and the codepoint written after it goes
  past `LINE_BUF`.
- **Lowering `FLUSH_RESERVE`** below 29 does the same thing directly.
- **Lowering `LINE_BUF`** is safe for the filter path but *not* for animation —
  see [003](003-animation-caps-drop-input.md), where a single grapheme cluster
  can exceed the whole buffer and is handled by a mid-cluster flush instead.

`tests/anuenue.tcyr`'s "filter geometry — flush reserve sizing" group pins the
relationship. If you change any of the three, that group is the thing that
should fail.
