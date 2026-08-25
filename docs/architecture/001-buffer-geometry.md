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

The longest escape actually emitted is truecolor: `\e[38;2;255;255;255m` = 19
bytes, so the 24-byte allowance has slack too.

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
