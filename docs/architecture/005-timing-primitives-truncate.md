# 005 — `sleep_ms` takes an i64 and hands it to a 32-bit int

`lib/chrono.cyr`'s `sleep_ms(ms)` is `poll(NULL, 0, ms)` on Linux and macOS.
`poll(2)`'s timeout argument is a **32-bit `int`**. The Cyrius signature takes
an i64, so anything above int32 range is silently truncated on the way into the
kernel — and the truncation is **non-monotonic**.

Measured on cyrius 6.5.35, x86-64 Linux:

| `sleep_ms(ms)` | Truncates to | Observed |
|---|---|---|
| `100` | `100` | sleeps 102 ms |
| `2147483647` | `2147483647` | blocks ~24.8 days (honest) |
| `2147483648` | `-2147483648` | **blocks forever** (negative = infinite timeout) |
| `4294967296` | `0` | **returns instantly** (busy loop) |
| `4294967396` | `100` | sleeps 100 ms |
| `9223372036854775807` | `-1` | **blocks forever** |

So "a bigger number sleeps longer" is false above 2³¹. Passing a large i64 gives
either a hung process or a spin, depending on which side of a power of two the
value lands — never a long sleep.

## Why this is an architecture note and not a bug report

It is not anuenue's bug to fix; it is a property of the primitive anuenue is
built on. Any anuenue code that turns a user-supplied number into a sleep has to
bound it *before* the call. Two do today:

- **`-i` / `--interval`** is rejected at `<= 0` and clamped at
  `ANUENUE_MAX_INTERVAL_MS` (3 600 000 ms), chosen to sit far inside int32's
  positive range.
- **`_frame_wait`** never passes more than `ANUENUE_TICK_MS` (16) to a single
  `sleep_ms` call regardless of the interval, slicing a long wait instead. That
  is primarily for signal responsiveness (see
  [006](006-argv-costs-a-file-descriptor.md)'s sibling discussion in the v1.3.0
  CHANGELOG entry), but it also means the truncation range is unreachable from
  the frame loop even if the clamp were removed.

A negative sleep is worse than a wrong one here, because animation **blocks
SIGHUP/SIGINT/SIGTERM** and drains them through a signalfd — so a process stuck
in an infinite `poll` does not respond to Ctrl-C or `kill` either. Only SIGKILL
ends it.

## The general rule

**Bound any duration before it reaches a timing primitive.** The same reasoning
produced `ANUENUE_MAX_DURATION_S` for `-d`, for a different arithmetic reason
(i64 overflow in the nanosecond conversion — see the 2026-08-25 audit, A-02).
Two flags, two different overflow mechanisms, one habit.
