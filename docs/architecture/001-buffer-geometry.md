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

## The escape write footprint (v1.4.3)

From v1.4.3 `_emit_phase_esc` copies a table entry's payload as **three 8-byte
words**, not `elen` single bytes. So it *writes* 24 bytes, `[pos, pos + 24)`,
whatever the escape's length, and *advances* `pos` by `elen` only. The bytes
`[pos + elen, pos + 24)` are scratch: the zeros `_phase_esc_init` puts after
every escape in its entry.

That is safe for three reasons, and all three must keep holding:

1. **The footprint fits the reserve.** Every call to `_emit_phase_esc` is
   either the first write of its iteration, where the invariant above gives
   `pos <= LINE_BUF - FLUSH_RESERVE`, or comes straight after a flush that set
   `pos = 0` (the mid-cluster re-emit in `_render_frame`). 24 ≤ `FLUSH_RESERVE`
   (32), so `[pos, pos + 24)` ends at or before `LINE_BUF - 8`. The call sites,
   all checked at v1.4.3:

   | Function | Call site | Enters with |
   |---|---|---|
   | `anuenue_filter` | ASCII byte, multi-byte codepoint | top of iteration |
   | `anuenue_filter` | EOF carry (truncated sequence) | top of iteration |
   | `anuenue_render_bytes` | ASCII, truncated, multi-byte | top of iteration |
   | `_render_frame` | start of a cluster | top of iteration |
   | `_render_frame` | re-emit after a mid-cluster flush | `pos = 0` |

   The rest of the iteration starts inside the footprint: the codepoint goes
   at `pos + elen`. With the measured `elen ≤ 17` it ends by `pos + 21`, inside
   the 24. With the full 24-byte budget it would end at `pos + 28`, the same
   bound the table above already allows. Either way it fits in 32.

2. **Scratch is never flushed.** Every flush writes `[0, pos)`, and the next
   write after an emit starts at the advanced `pos`. Scratch bytes are either
   overwritten by that write or still past `pos` when the buffer goes out.
   Nothing reads `line_buf` beyond `pos`.

3. **The read stays inside the entry.** The three words are
   `[entry + 8, entry + 32)`, exactly the payload region. The table is one
   allocation of `PHASE_MOD × ENTRY_SIZE`, so the last entry's read ends at the
   allocation's end.

What pins it: `tests/anuenue.tcyr`'s geometry group asserts
`ESC_TABLE_ENTRY_SIZE - 8 <= FLUSH_RESERVE`. `fuzz/emit-phase-esc.fcyr` asserts
the footprint byte for byte: the escape, then zeros to `pos + 24`, then
untouched. It also checks a stream of emits and payload bytes against a
byte-copy reference over `[0, pos)`. `robustness-check.sh` asserts that no NUL
byte reaches stdout from NUL-free input, in every mode and on every route. A
scratch byte that leaked would be a NUL.

## What breaks if you change one

- **Raising `ESC_TABLE_ENTRY_SIZE`** without raising `FLUSH_RESERVE` lets the
  escape alone approach the reserve, and the codepoint written after it goes
  past `LINE_BUF`.
- **Lowering `FLUSH_RESERVE`** below 29 does the same thing directly — and
  below 24 the escape's own word-copy footprint runs past `LINE_BUF`.
- **Changing `ESC_TABLE_ENTRY_SIZE` at all** means changing `_emit_phase_esc`:
  it copies exactly three payload words, which is `ENTRY_SIZE - 8` only while
  the entry is 32 bytes. The unit suite pins the 32.
- **Lowering `LINE_BUF`** is safe for the filter path but *not* for animation —
  see [003](003-animation-caps-drop-input.md), where a single grapheme cluster
  can exceed the whole buffer and is handled by a mid-cluster flush instead.

`tests/anuenue.tcyr`'s "filter geometry — flush reserve sizing" group pins the
relationship. If you change any of the three, that group is the thing that
should fail.
