# anuenue — Benchmarks

> Per-character overhead is the hot-path metric. anuenue sits in MOTD
> pipelines (`iam | anuenue`, `bnrmr | anuenue`), so end-users feel
> the wall-clock cost of one character through the filter on every
> shell login. This file captures the baseline at each release.

## Methodology

Two layers of measurement:

1. **Cyrius `bench` micro** — `tests/anuenue.bcyr`. Per-call cost of
   the two M1 primitives (`hsv_rainbow` and `tty_fg_rgb_buf`) and,
   since v1.4.0, of `_emit_phase_esc` (the phase-cached table) against
   `hsv_rainbow` + darshana's composer in each colour mode — measured
   with `lib/bench.cyr`'s batched-clock harness (1M iter per batch —
   keeps total wall-time well past the `clock_gettime` overhead floor).
2. **End-to-end shell** — `cat <fixture> | anuenue > /dev/null` vs
   `cat <fixture> > /dev/null`, measured with shell `time` over
   three runs. The fixture is `base64`-of-1MB-`/dev/urandom` — a
   `~1.4MB` ASCII corpus, no LF compression, all printable bytes.
   *(M1 captures this manually; M5 — perf pass — will scriptize.)*

Host: `archaemenid`-class workstation (AMD Zen, Linux 7.0.x, glibc
n/a — Cyrius bypasses libc).

## v0.2.0 — M1 baseline (2026-05-21)

First end-to-end measurement on the pipe-purity proof. No perf work
yet; the M5 milestone (v0.6.0) will iterate against this baseline.

### Micro

| Primitive             | Avg (ns/call) | Min  | Max  | Iters  |
|-----------------------|---------------|------|------|--------|
| `hsv_rainbow`         |  8            |  8   |  8   | 1M     |
| `tty_fg_rgb_buf`      | 45            | 45   | 45   | 1M     |

Per-character formatting (escape emission) costs ~5.6× the HSV
computation. Not surprising — `_ansi_emit_u8` runs three times per
escape (one per channel) and each invocation does a divide/modulus
chain. M5 candidates: pre-computed 256-entry decimal-byte LUT for
channel encoding; SIMD-batched escape emission once a corpus of
"typical rainbow input" is large enough to justify it.

### End-to-end

Input: `base64 < /dev/urandom` truncated to **1 416 501 bytes** —
pure-ASCII, no embedded LFs at the line-buffer boundary, all bytes
get the truecolor prefix.

| Pipeline                              | Wall (s, mean of 3) | User | Sys  |
|---------------------------------------|---------------------|------|------|
| `cat fixture > /dev/null`             | 0.013               | 0.01 | 0.01 |
| `anuenue < fixture > /dev/null`       | 0.087               | 0.08 | 0.00 |

- **Per-byte overhead**: `(0.087 − 0.013) / 1 416 501 ≈ 53 ns/byte`
- **Output expansion**: `24 660 228 / 1 416 501 ≈ 17.4×` — every
  input byte produces ~17 bytes of fg-escape + the payload byte +
  per-line reset overhead. Matches the worst-case envelope
  `_ansi_emit_u8` + framing (19 max, 13–17 typical) plus a 4-byte
  reset every line.

### Notes

- `hsv_rainbow`'s 8ns is below `clock_gettime`'s per-call overhead;
  the batched harness is the only way to measure it accurately.
- The end-to-end measurement is dominated by `tty_fg_rgb_buf`
  (the 45ns × ~1.4M = ~64ms accounted of the ~74ms anuenue-only
  delta vs cat). The remaining ~10ms is the filter-loop overhead
  (read syscalls, branch dispatch, write syscalls — 32KB flushes,
  so ~43 write(2) calls for 1.4MB input).
- DCE was NOT applied to the M1 binary. Re-measure with
  `CYRIUS_DCE=1 cyrius build ...` at the M5 perf pass.

## v0.4.0 — M3 (UTF-8 grapheme awareness)

Cluster classification adds per-codepoint work even on pure ASCII:
`utf8_seq_len` + `cp_is_extending` (range checks) + RI/ZWJ latch
updates. The ASCII path slows ~55% vs v0.3.0; multi-byte input
benefits from one-fg-per-codepoint amortisation but still pays the
classification cost.

### End-to-end

Same 1 416 501-byte base64-ASCII corpus from v0.2.0:

| Pipeline                              | Wall (s, mean of 3) | vs v0.3.0 |
|---------------------------------------|---------------------|-----------|
| `cat fixture > /dev/null`             | 0.013               | (same)    |
| `anuenue < fixture > /dev/null`       | 0.135               | +55%      |

- **ASCII per-byte overhead**: `(0.135 − 0.013) / 1 416 501 ≈ 86 ns/byte`
  (vs 53 ns at v0.3.0 — 33 ns/byte cluster-classification cost).
- **UTF-8 corpus** (`AGNOS Привет 日本 🌈 rainbow ` × 1000 = 39 000
  bytes): 3 ms / ~77 ns per input byte. Multi-byte codepoints
  amortise the per-cluster work over their 2–4 payload bytes —
  the per-byte cost is comparable to the ASCII path despite the
  cluster overhead, because one fg escape now covers 2–4 bytes of
  payload (vs ASCII's 1 byte / escape).

### Binary

- **0.4.0 DCE size**: **322 368 bytes** (~315 KB). +5 152 bytes
  over v0.3.0 for the UTF-8 + grapheme-classification surface.

## v0.6.0 — M5 (perf pass)

Three layered optimisations against the M3 regression. ASCII
short-circuit skips the UTF-8 + cluster classifier on the common
case. `cp_is_extending` binary-searches a sorted range table.
And — the biggest win — a 1 530-entry phase-cached escape table
collapses `hsv_rainbow + tty_fg_rgb_buf` into a single memcpy.

Result: the ASCII hot path drops below v0.3.0's pre-cluster floor.
UTF-8 mixed comes in even faster, because the cluster work
amortises over multi-byte payloads and the escape pre-computation
skips digit encoding on every cluster.

### End-to-end (scripts/perf-bench.sh, RUNS=7 median)

Three corpora at ~1.4 MB each, on the same host the prior baselines
ran on:

| Corpus           | cat (ms) | anuenue (ms) | Overhead (ns/byte) | Δ vs v0.5.0 |
|------------------|----------|--------------|--------------------|-------------|
| ascii (no LF)    | 3        | 68           | **47.0**           | −48.7%      |
| ascii (w/ LFs)   | 3        | 73           | 51.0               | −46.3%      |
| utf8 mixed       | 3        | 62           | 43.0               | −35.1%      |

### Per-optimisation contribution (ascii no-LF)

| Step                                       | ns/byte | Δ      |
|--------------------------------------------|---------|--------|
| v0.5.0 baseline                            | 91.6    | —      |
| + ASCII short-circuit                      | 59.3    | −32.3  |
| + `cp_is_extending` binary-search LUT      | 60.0    | +0.7*  |
| + phase-cached escape buffer (M5 final)    | 47.0    | −13.0  |

\* The LUT is perf-neutral on the ASCII corpus (already short-
circuited); the +0.7 ns is host noise. UTF-8-heavy corpora with
Arabic / Hebrew / math-zone combiners are where the LUT pays
back — log₂(21) ≈ 5 comparisons replacing a 21-condition linear
chain. Kept regardless: clearer code, future-proof.

### Binary

- **0.6.0 DCE size**: **335 160 bytes** (~327 KB). +1 040 bytes
  over v0.5.0 for the new `_phase_esc_init` / `_emit_phase_esc`
  helpers, the `cp_is_extending` LUT init body, and the
  binary-search loop. The 48 KB phase-cache table is heap-
  allocated at first filter/animate entry and doesn't show
  up in the DCE binary.
- M5 acceptance cap: 350 KB → comfortably under (−14 840 B
  headroom for M6 color-mode work).

### Notes

- `perf-bench.sh` is the M5 ratchet from here forward. Each
  minor cut should re-run it; CHANGELOG records any motion in
  the per-byte figures.
- The phase-cached escape table is a runtime alloc of
  `1530 × 32 = 48 960` bytes (heap); it amortises over the
  filter run — at the M3 baseline of ~13M chars/sec, that's
  3.8 μs of table-fill cost per million bytes filtered, or
  3.8 ns/byte at the limit. Already counted in the median
  ns/byte figures above.

## v0.7.0 — M6 (colour-mode negotiation)

Three new flags (`--no-color` / `--force-color` / `--color`),
mode-aware phase-cache build, four-mode taxonomy (TRUECOLOR /
COLOR_256 / COLOR_16 / MONO) — all behavioural surface, no
hot-path changes. `_emit_phase_esc` stays a memcpy regardless of
mode (the table holds per-mode pre-formatted escapes).

| Corpus           | ns/byte | Δ vs v0.6.0 |
|------------------|---------|-------------|
| ascii (no LF)    | ~47     | flat        |
| ascii (w/ LFs)   | ~51     | flat        |
| utf8 mixed       | ~43     | flat        |

- **0.7.0 DCE size**: **349 832 bytes** (~342 KB; +14 672 B over
  v0.6.0 for `src/color.cyr` + stdlib `getenv` / `strstr` pulls).
- **0.7.1 (sandhi closeout)**: **350 488 bytes** (+656 B from
  darshana 0.5.3's transitive `tty_itoa` linker pulls). Cap
  raised 350 KB → 512 KB in this slot to absorb the bump.

## v0.8.0 — M7 docs + M8 security audit

Documentation cycle + first formal security audit. One HIGH
finding (`_render_frame` long-cluster heap overflow) fixed
in-cycle via mid-cluster flush guard; the filter path was not
affected because it writes one codepoint per iteration. Filter
hot-path unchanged; animation path picks up one additional
per-byte check in the cluster-copy inner loop but the cost is
amortised against the cluster-bytes copy.

| Corpus           | ns/byte | Δ vs v0.7.1 |
|------------------|---------|-------------|
| ascii (no LF)    | ~46     | flat        |
| ascii (w/ LFs)   | ~50     | flat        |
| utf8 mixed       | ~42     | flat        |

- **0.8.0 DCE size**: **351 200 bytes** (+712 B over v0.7.1 for
  the mid-cluster guard + new tcyr M8 audit group).

## v0.9.0 — Quality slot (fuzz + animation smoke + hsv split)

No production-binary changes — quality-slot work landed entirely
in tests, fuzz harnesses, and the `src/hsv.cyr` split (moving
`hsv_rainbow` between files doesn't change linkage). DCE binary
**byte-identical** to v0.8.0.

| Corpus           | ns/byte | Δ vs v0.8.0 |
|------------------|---------|-------------|
| ascii (no LF)    | ~46     | flat        |
| ascii (w/ LFs)   | ~50     | flat        |
| utf8 mixed       | ~42     | flat        |

- **0.9.0 DCE size**: **351 200 bytes** (±0 B vs v0.8.0).

## v1.0.0 — GA

Symbolic crystallisation of the v0.9.0 surface as the v1.x stable
contract. No production code changes; perf and binary size carry
through unchanged.

| Corpus           | ns/byte | Δ vs v0.9.0 |
|------------------|---------|-------------|
| ascii (no LF)    | 45.71   | within noise |
| ascii (w/ LFs)   | 49.75   | within noise |
| utf8 mixed       | 41.47   | within noise |

- **1.0.0 DCE size**: **351 200 bytes** (±0 B vs v0.9.0 / v0.8.0).
- The DCE cap (512 KB) gave ~161 KB headroom for future v1.x
  sandhi-bump-driven growth. *(Historical: the cap was removed at
  v1.2.2.)*

## v1.2.1 — Toolchain + dep refresh

cyrius `6.4.62` → `6.5.35`; darshana `0.9.0` → `1.0.0`, cmdit `1.1.0` →
`1.2.4`, sakshi `2.4.6` → `2.4.11`, agnostik `1.3.4` → `1.5.1`, plus the
sakshi/agnostik observability wiring (`src/observe.cyr`). The filter hot
path is untouched. Measured **head-to-head on one idle host**
(same fixture, `RUNS=11`, v1.2.0 binary vs v1.2.1 binary) rather than
against a historical figure — the two binaries are also byte-identical
across 160 output comparisons.

| Corpus           | v1.2.0 | v1.2.1 | Δ |
|------------------|-------:|-------:|--:|
| ascii (no LF)    | 47.20  | **46.63** | −1.2% |
| ascii (w/ LFs)   | 50.98  | **50.99** | +0.0% |
| utf8 mixed       | 41.85  | **41.77** | −0.2% |

All three under the 60 ns/byte M5 acceptance. Differences are within
run-to-run noise; nothing on the filter hot path changed. The one
addition inside the read loop is a single accumulate of `n_read`,
executed once per `read(2)` — a few dozen additions across a
multi-megabyte stream, not per byte.

**Diagnostics cost.** `-v` output is O(1) in input size — exactly 10
records however long the stream:

| Input | stderr under `-v` | records |
|------:|------------------:|--------:|
| 1 KB    | 489 B | 10 |
| 100 KB  | 492 B | 10 |
| 1.4 MB  | 494 B | 10 |
| 5 MB    | 494 B | 10 |

Enabling `-v` costs ~11 ms of fixed startup/teardown on the reference
host (clock reads plus unbuffered stderr writes) and nothing per byte.
At default verbosity the cost is zero — the level check short-circuits
before any formatting.

- **1.2.1 binary**: **809 520 bytes** (~790 KB), up from 389 648 B at
  v1.2.0 (+419 872, +108%). The 512 KB cap this row originally
  reported against was **removed at v1.2.2** — see
  [`state.md` § Binary](development/state.md#binary) for why (short
  version: the number now measures the first-party dep surface, not
  anuenue, and DCE stopped removing anything).
  Decomposed: dep bump +135 240, toolchain bump +279 072, observability
  wiring +5 560. `agnostik` accounts for ~546 KB and `sakshi` for ~90 KB
  — both are *called* code as of v1.2.1, which is what this release
  changed. Full attribution and the open cap decision:
  [`state.md` § Binary](development/state.md#binary).
- **`CYRIUS_DCE=1` no longer shrinks the file.** 6.5.35 NOPs unreachable
  functions in place instead of eliminating them, so the DCE and non-DCE
  binaries are the same size. Rows below labelled "DCE size" for
  ≤ v1.0.0 measured genuine elimination; the v1.2.1 figure is the whole
  binary. They are not directly comparable.
- **Micro-benchmarks are not comparable across this cut.** 6.5.35's
  `bench` harness measures and subtracts a timer floor (1.347 µs per
  clock read on the reference host) that 6.4.62's did not.
  `hsv_rainbow` reads 8 ns and `tty_fg_rgb_buf` 52 ns under the new
  harness.

## v1.2.2 — P(-1) audit sweep

Nine findings fixed (2 MEDIUM, 5 LOW, 2 INFO), the `hsv_rainbow` sector
table flattened from a nested else-if chain to early returns, and the
512 KB binary cap removed. Measured head-to-head on one idle host, same
fixture, `RUNS=11`, v1.2.1 binary vs v1.2.2 binary.

| Corpus           | v1.2.1 | v1.2.2 | Δ |
|------------------|-------:|-------:|--:|
| ascii (no LF)    | 46.57  | **46.64** | +0.2% |
| ascii (w/ LFs)   | 50.98  | **50.97** | −0.0% |
| utf8 mixed       | 41.66  | **41.71** | +0.1% |

Within run-to-run noise. None of the audit fixes touch the per-byte
path: the allocation guard (A-01) is on a once-per-process lazy init,
the duration clamp (A-02) is a single comparison before the frame loop,
and the flag validations (A-03 / A-04) run once at startup.

`hsv_rainbow` holds at **8 ns** across the A-07 refactor — flattening
the six-sector chain into early returns cost nothing, which was the
open question, since that function runs 1 530 times per process to
build the escape table.

- **1.2.2 binary**: **809 984 bytes**, +464 B over v1.2.1 — the audit
  fixes. **The 512 KB cap is removed at this cut** and replaced with
  track-and-attribute; see
  [`state.md` § Binary](development/state.md#binary) for the reasoning.

## v1.3.x — animation slot + PTY + closeout

The arc that added `-i` / `--interval`, restructured the animation frame loop
into `_frame_wait`, and fixed three signal-path defects (B-01/B-02/B-03).
Measured at the v1.3.2 closeout, head-to-head on one idle host, `RUNS=11`,
rebuilt v1.2.2 binary vs v1.3.2.

**Filter path** — untouched by the arc:

| Corpus           | v1.2.2 | v1.3.2 | Δ |
|------------------|-------:|-------:|--:|
| ascii (no LF)    | 46.22  | **46.61** | +0.8% |
| ascii (w/ LFs)   | 50.58  | **50.88** | +0.6% |
| utf8 mixed       | 41.37  | **41.41** | +0.1% |

**Animation path** — the one that was restructured. Mean CPU over three
3-second runs at the default 16 ms interval:

| | user | sys | total |
|---|---:|---:|---:|
| v1.2.2 | 2.3 ms | 2.7 ms | 5.0 ms |
| v1.3.2 | 2.7 ms | 2.3 ms | **5.1 ms** |

Flat, as expected: at the default interval `_frame_wait` performs exactly one
slice, which is the same single sleep + signal probe + deadline check the
pre-v1.3.0 loop did.

**Slicing at long intervals costs nothing.** A 200 ms interval slices into ~13
ticks per frame instead of 1, so each frame pays 12 extra signal probes and 12
extra clock reads — yet total CPU *falls*, because a longer interval means far
fewer frames to render:

| | user | sys | total |
|---|---:|---:|---:|
| `-i 16` | 1.1 ms | 2.8 ms | 3.8 ms |
| `-i 200` | 0.4 ms | 2.6 ms | **3.0 ms** |
| `-i 1000` | 1.3 ms | 1.8 ms | 3.2 ms |

- **1.3.2 binary**: **814 448 bytes**, +4 464 B over v1.2.2 — the `-i` flag,
  `_frame_wait`, and the signalfd rollback. Unchanged across v1.3.1 (tests and
  docs only) and v1.3.2 (one guard line).

> **Process note.** These numbers should have been recorded at v1.3.0, whose
> gate called for "perf within noise of v1.2.2's 46.64 ns/byte". They were not —
> the slot was marked complete without discharging that gate, and
> `docs/benchmarks.md` had no v1.3.x row until the v1.3.2 closeout. See the
> [v1.3.x audit delta](audit/2026-08-25-v13x-delta.md).

## v1.3.3 — P(-1) sweep (E-01 checked writes)

The E-01 fix routes all 17 stdout writes through `anuenue_write_all`, so the
hot path gained a comparison and a call per **flush** (once per line or per
32 KB — not per byte). Measured back-to-back in one session against a pre-fix
binary rebuilt from the v1.3.2 tree, `RUNS=11` each:

| Corpus           | v1.3.2 | v1.3.3 | Δ |
|------------------|-------:|-------:|--:|
| ascii (no LF)    | 46.47  | **46.46** | −0.0% |
| ascii (w/ LFs)   | 50.54  | **50.91** | +0.7% |
| utf8 mixed       | 41.52  | **41.82** | +0.7% |

A repeated single-corpus pass, to separate the cost from host drift:

| Pass | v1.3.2 | v1.3.3 | Δ |
|---|---:|---:|---:|
| 1 | 46.74 | 46.80 | +0.1% |
| 2 | 46.63 | 46.91 | +0.6% |

**A real but small cost, around +0.5%** — consistently positive across passes
rather than lost in noise. Well inside the 60 ns/byte M5 acceptance, and not a
close trade: half a percent of throughput against a defect that silently
discarded 99.3% of the stream and exited 0.

- **1.3.3 binary**: **814 480 bytes**, +32 B over v1.3.2.

> **Method note.** An earlier draft reported −0.5%, from a baseline taken at the
> start of the sweep and a post-fix run half an hour later. Those two numbers
> were not comparable — a third run of the *same* binary read 47.13 ns/byte.
> Only a back-to-back pairing measures the change rather than the machine. This
> is the same discipline the v1.2.2 and v1.3.2 cuts adopted, applied here after
> nearly getting it wrong.

## v1.4.0 — cyrius 6.7.9 + darshana 1.3.0

### The phase-cached escape table, re-measured

darshana's consumer survey asked whether the M5 table still pays for itself
now that darshana 1.2.0 made its composers 35–49% faster. Two measurements, both
in this repo's harnesses.

**Micro** (`tests/anuenue.bcyr`, three runs, ns per escape; same phase walk
through the table and through `hsv_rainbow` + the mode's composer):

| Mode | table | hsv_rainbow + composer | winner |
|---|---:|---:|---|
| truecolor | 43–45 | 31–33 | composer |
| 256 | 30–31 | 37–38 | table |
| 16 | 18 | 24 | table |

Under cyrius 6.6.2 with darshana 1.1.1 the truecolor pair was 41–43 vs 43–44 —
a tie. darshana 1.3.0's faster composer is what tipped truecolor.

**End to end** — `perf-bench.sh` (now `COLOR=`-selectable), a binary built with
`_emit_phase_esc` replaced by the direct composition (stdout byte-identical
across the same 276 comparisons) against the table binary, `RUNS=11`, two
interleaved rounds each, host load average ~5.7 when the runs began:

| Mode | corpus | table | no table | Δ |
|---|---|---:|---:|---:|
| truecolor | ascii no-LF | 49.6 | 41.9 | −15% |
| | ascii w/ LFs | 53.7 | 47.0 | −13% |
| | utf8 mixed | 44.0 | 39.5 | −10% |
| 256 | ascii no-LF | 36.1 | 48.0 | **+33%** |
| | ascii w/ LFs | 40.6 | 52.6 | **+29%** |
| | utf8 mixed | 34.8 | 43.0 | **+24%** |
| 16 | ascii no-LF | 24.2 | 34.5 | **+42%** |
| | ascii w/ LFs | 29.3 | 39.6 | **+35%** |
| | utf8 mixed | 27.0 | 34.6 | **+28%** |

**Kept.** Deleting the table is a net regression in two of the three modes. A
harness that could only measure truecolor — `perf-bench.sh` before v1.4.0 —
would have recommended the opposite.

What the micro numbers locate is the cost: the byte-at-a-time copy, not the
lookup. A three-word copy of the same entry measured **9–10 ns in every mode**
(a scratch probe; not in the harness). It writes past the escape's length, so it
is filed as its own roadmap item rather than taken here. And the "≈ 10 ns/call"
this file has quoted for `_emit_phase_esc` since v0.6.0 is not what the byte
loop costs: 41–43 ns under cyrius 6.6.2, 43–45 under 6.7.9.

### Release ratchet — v1.3.6 vs v1.4.0

The hot path did not change — `_emit_phase_esc` and the walk around it are the
v1.3.6 code — so this measures the toolchain and darshana moves. A rebuilt v1.3.6
binary (byte-identical to the 2026-09-10 v1.3.6 build left in `build/`) against v1.4.0, `RUNS=11`, three
interleaved rounds per mode, medians of the rounds, ns/byte. The host was shared
with other build jobs: load average 5.3–5.5 for truecolor, 5.6–6.0 for 256 and
16; 16's third round ran at load 7.0–7.5 and read ~48 ns/byte for **both**
binaries, so it is dropped and the 16 rows are the mean of rounds 1–2.

| Mode | corpus | v1.3.6 | v1.4.0 | Δ |
|---|---|---:|---:|---:|
| truecolor | ascii no-LF | 48.53 | **48.56** | +0.1% |
| | ascii w/ LFs | 52.85 | **52.85** | 0.0% |
| | utf8 mixed | 43.42 | **43.46** | +0.1% |
| 256 | ascii no-LF | 37.17 | **36.32** | −2.3% |
| | ascii w/ LFs | 43.91 | **40.77** | −7.2% |
| | utf8 mixed | 36.00 | **34.73** | −3.5% |
| 16 | ascii no-LF | 24.68 | **24.84** | +0.6% |
| | ascii w/ LFs | 29.61 | **29.50** | −0.4% |
| | utf8 mixed | 27.27 | **28.07**¶ | +2.9% |

¶ one clean sample; v1.4.0's round-2 utf8 read 48.50 at load 7.0.

**Flat on truecolor**, where the rounds agree to within ±1.5%. The 256 rows
favour v1.4.0 but its rounds spread up to 13% on the v1.3.6 side (w/ LFs 41.0 –
46.6), so they are not evidence of a speed-up; read them as "no regression".
Truecolor ascii no-LF is the M5 metric: 48.56 ns/byte, under the 60 ns/byte
acceptance.

- **1.4.0 binary**: **210 696 bytes**, +6 384 B over v1.3.6's 204 312 B — almost
  all of it the toolchain (+6 040 B); see [`state.md` § Binary](development/state.md#binary).

## v1.4.1 — cmdit 1.4.0 + agnostik 1.12.0

### Release ratchet — v1.4.0 vs v1.4.1

Nothing on the per-cluster path changed — the source change is
`src/main.cyr`'s parse-error switch, which runs once and only on a failed
parse — so this measures the cmdit and agnostik moves. The v1.4.0 binary
(rebuilt from its tag, 210 696 B, the size `state.md` records) against
v1.4.1, `RUNS=11`, three interleaved rounds per mode, medians of the rounds,
ns/byte. A quieter host than v1.4.0's (load average 1–3 across the rounds), which
is why v1.4.0 reads ~2 ns/byte below its own row in the trend.

| Mode | corpus | v1.4.0 | v1.4.1 | Δ |
|---|---|---:|---:|---:|
| truecolor | ascii no-LF | 46.68 | **46.74** | +0.1% |
| | ascii w/ LFs | 50.88 | **51.03** | +0.3% |
| | utf8 mixed | 41.86 | **41.48** | −0.9% |
| 256 | ascii no-LF | 34.33 | **34.52** | +0.6% |
| | ascii w/ LFs | 38.42 | **38.92** | +1.3% |
| | utf8 mixed | 33.24 | **33.32** | +0.2% |
| 16 | ascii no-LF | 23.22 | **23.56** | +1.5% |
| | ascii w/ LFs | 27.90 | **28.17** | +1.0% |
| | utf8 mixed | 26.40 | **25.87** | −2.0% |

**Flat** — every row within ±2%, mixed signs, at a timer resolution of 1 ms
on ~64 ms runs. Truecolor ascii no-LF is the M5 metric: 46.74 ns/byte.

Micro (`tests/anuenue.bcyr`, same host): `hsv_rainbow` 8 ns, `tty_fg_rgb_buf`
21 ns; table vs composer 39 / 27 (truecolor), 26 / 34 (256), 16 / 21 (16) —
the v1.4.0 ordering, slightly faster on the quieter host.

- **1.4.1 binary**: **222 520 bytes**, +11 824 B over v1.4.0: cmdit +9 240 B,
  agnostik +2 480 B, sakshi-as-stdlib 0 B, anuenue +104 B; see
  [`state.md` § Binary](development/state.md#binary).

## v1.4.2 — stderr hygiene

### Release ratchet — v1.4.1 vs v1.4.2

The change is on the error path — `anuenue_fail`'s newline and the
parse-error token echo — which runs once and only on a failure. A rebuilt
v1.4.1 binary against v1.4.2, `RUNS=11`, three interleaved rounds per mode,
medians of the rounds, ns/byte, same host as § v1.4.1:

| Mode | corpus | v1.4.1 | v1.4.2 | Δ |
|---|---|---:|---:|---:|
| truecolor | ascii no-LF | 47.38 | **47.41** | +0.1% |
| | ascii w/ LFs | 51.64 | **52.14** | +1.0% |
| | utf8 mixed | 41.98 | **42.21** | +0.5% |
| 256 | ascii no-LF | 34.58 | **34.74** | +0.5% |
| | ascii w/ LFs | 39.21 | **39.32** | +0.3% |
| | utf8 mixed | 33.61 | **33.52** | −0.3% |
| 16 | ascii no-LF | 23.12 | **23.20** | +0.3% |
| | ascii w/ LFs | 27.78 | **27.77** | 0.0% |
| | utf8 mixed | 25.67 | **25.83** | +0.6% |

**Flat** — every row within ±1%. v1.4.1 reads 0.7 ns/byte above its own § v1.4.1
row: same host, a different hour; compare the pair.

- **1.4.2 binary**: **226 624 bytes**, +4 104 B over v1.4.1 — DCE now keeps
  darshana's `tty_sanitize_buf` for the argv echo; see
  [`state.md` § Binary](development/state.md#binary).

## v1.4.3 — escape-table word copy

The first change to the per-cluster hot path since M5. `_emit_phase_esc`
copies the table entry's 24-byte payload as three 8-byte words instead of
`elen` single bytes (footprint argument: architecture 001).

### Micro (`tests/anuenue.bcyr`, ns per escape, three runs each)

| Mode | v1.4.2 table | v1.4.3 table | direct composition (hsv + composer) |
|---|---:|---:|---:|
| truecolor | 39 | **9** | 28–30 |
| 256 | 27–28 | **9** | 34–36 |
| 16 | 16–17 | **9** | 22–23 |

The table now beats direct composition in every mode; v1.4.0's truecolor
exception is gone. The cost no longer depends on the escape's length.

### Release ratchet — v1.4.2 vs v1.4.3

A rebuilt v1.4.2 binary against v1.4.3, `RUNS=11`, three interleaved rounds
per mode, medians of the rounds, ns/byte, load average ~2:

| Mode | corpus | v1.4.2 | v1.4.3 | Δ |
|---|---|---:|---:|---:|
| truecolor | ascii no-LF | 47.72 | **15.40** | −67.7% |
| | ascii w/ LFs | 51.73 | **20.19** | −61.0% |
| | utf8 mixed | 42.10 | **20.53** | −51.2% |
| 256 | ascii no-LF | 34.63 | **15.36** | −55.6% |
| | ascii w/ LFs | 39.37 | **20.08** | −49.0% |
| | utf8 mixed | 33.48 | **20.65** | −38.3% |
| 16 | ascii no-LF | 23.46 | **15.31** | −34.7% |
| | ascii w/ LFs | 28.09 | **20.02** | −28.7% |
| | utf8 mixed | 25.96 | **20.38** | −21.5% |

The modes converge: what separated them was the copy's length (17 / 11 / 5
bytes), and the word copy does not have one. The saving tracks the micro
number — ~30 ns per escape on truecolor, one escape per ASCII byte.
Cross-checked outside the harness: 10 MB of ASCII through `--color=24bit`,
509 → 192 ms (median of five, startup included), identical md5.

**M5 metric: 15.40 ns/byte**, a quarter of the 60 ns/byte acceptance bound.

- **1.4.3 binary**: **226 624 bytes**, the same total as v1.4.2.

## v1.4.4 — v1.4.x closeout + P(-1) sweep

### Release ratchet — v1.4.3 vs v1.4.4

The per-cluster path did not change. The cut's work is in animation setup (the
H-01 row count, once per run), the EAGAIN wait (H-02, taken only on a
non-blocking descriptor) and the animation pre-tag (H-05). A rebuilt v1.4.3
binary against v1.4.4, `RUNS=11`, **five** interleaved rounds per mode,
medians of the rounds, ns/byte. A first three-round run at load average ~11
(other compiles on the host) swung ±10% with mixed signs and was discarded;
these ran at load 5–7.

| Mode | corpus | v1.4.3 | v1.4.4 | Δ |
|---|---|---:|---:|---:|
| truecolor | ascii no-LF | 15.59 | **15.60** | +0.1% |
| | ascii w/ LFs | 20.22 | **20.24** | +0.1% |
| | utf8 mixed | 20.73 | **20.70** | −0.1% |
| 256 | ascii no-LF | 15.42 | **15.51** | +0.6% |
| | ascii w/ LFs | 20.20 | **20.27** | +0.3% |
| | utf8 mixed | 20.62 | **20.62** | 0.0% |
| 16 | ascii no-LF | 15.34 | **15.40** | +0.4% |
| | ascii w/ LFs | 20.19 | **20.13** | −0.3% |
| | utf8 mixed | 20.59 | **20.53** | −0.3% |

**Flat** — every row within ±0.6%. Micro (`tests/anuenue.bcyr`): the table emit
is 9 ns in every mode, `hsv_rainbow` 8–9, `tty_fg_rgb_buf` 22, the same as
v1.4.3.

- **1.4.4 binary**: **235 800 bytes**, +9 176 B — `fd_wait_ready` (H-02),
  then H-01's width table, row count and size query, plus H-05; see
  [`state.md` § Binary](development/state.md#binary).

## v1.4.5 — input colour codes stripped

### The design the ratchet chose

v1.4.5 strips the input's SGR colour codes on the colour routes. Three ways of
doing it on the streaming filter path were measured against a rebuilt v1.4.4
(`RUNS=11`, interleaved rounds, medians, ascii no-LF):

| Design | truecolor | 256 | 16 |
|---|---:|---:|---:|
| a separate strip pass over each 4096-byte chunk | +11.5% | +11.3% | +11.4% |
| an ESC test at the top of the ASCII branch | +2.1% | +1.4% | +2.2% |
| **ESC tested with LF behind one `b < 0x20` (shipped)** | **+0.8%** | **+0.4%** | **0.0%** |

The pass cost ~1.7 ns/byte: a load, compare and branch for every byte,
before the filter loads the same byte again. The shipped design gives a
printable byte the same two comparisons v1.4.4 made: `b == 10, b < 0x80`
there, `b < 0x20, b < 0x80` here.

### Release ratchet — v1.4.4 vs v1.4.5

Ten interleaved rounds (the second five in reversed order), medians, ns/byte,
load average 0.2–2:

| Mode | corpus | v1.4.4 | v1.4.5 | Δ |
|---|---|---:|---:|---:|
| truecolor | ascii no-LF | 15.30 | **15.43** | +0.8% |
| | ascii w/ LFs | 19.84 | **19.86** | +0.1% |
| | utf8 mixed | 20.45 | **20.30** | −0.7% |
| 256 | ascii no-LF | 15.24 | **15.30** | +0.4% |
| | ascii w/ LFs | 19.93 | **19.98** | +0.3% |
| | utf8 mixed | 20.37 | **20.38** | +0.1% |
| 16 | ascii no-LF | 15.19 | **15.20** | 0.0% |
| | ascii w/ LFs | 19.97 | **19.93** | −0.2% |
| | utf8 mixed | 20.30 | **20.14** | −0.8% |

**Flat** — every row within ±0.8%, mixed signs. Micro rows are unchanged; the
table emit is 8–9 ns.

- **1.4.5 binary**: **235 848 bytes**, +48 B.

## v1.5.0 — no-colour spans

### MONO: the marker scan

From v1.5.0 MONO consumes the no-colour markers ([ADR 0006](adr/0006-no-colour-spans.md)),
so it is no longer a bare copy: every chunk is scanned for ESC. Three designs
measured against a rebuilt v1.4.5 (`COLOR=none`, which `perf-bench.sh` gains
for this, `RUNS=11`, a 14 MB corpus, three interleaved rounds, ns/byte):

| Design | ascii no-LF | ascii w/ LFs | utf8 mixed |
|---|---:|---:|---:|
| v1.4.5: a bare copy | 0.25 | 0.25 | 0.25 |
| a byte loop looking for ESC | 2.04 | 2.04 | 2.04 |
| `_find_esc`, one word per step | 0.67 | 0.67 | 0.66 |
| **`_find_esc`, four words per step (shipped)** | **0.55** | **0.55** | **0.55** |

`_find_esc` XORs each 8-byte word with ESC in every byte and tests for a zero
byte, as the stdlib's `strlen` does. Until the first marker is removed the
strip moves nothing, so marker-free input is only scanned. MONO stays more than
25 times cheaper than a colour route.

### Release ratchet — v1.4.5 vs v1.5.0

Ten interleaved rounds (the second five in reversed order), `RUNS=11`, medians,
ns/byte; MONO on a 14 MB corpus. The host was shared, with other sessions'
compiler builds starting and stopping, but interleaving keeps both binaries
under the same conditions in each round:

| Mode | corpus | v1.4.5 | v1.5.0 | Δ |
|---|---|---:|---:|---:|
| truecolor | ascii no-LF | 15.12 | **15.16** | +0.2% |
| | ascii w/ LFs | 19.68 | **19.70** | +0.2% |
| | utf8 mixed | 20.08 | **20.43** | +1.7% |
| 256 | ascii no-LF | 15.10 | **15.13** | +0.2% |
| | ascii w/ LFs | 19.69 | **19.64** | −0.2% |
| | utf8 mixed | 19.99 | **20.48** | +2.4% |
| 16 | ascii no-LF | 14.94 | **14.97** | +0.2% |
| | ascii w/ LFs | 19.59 | **19.63** | +0.2% |
| | utf8 mixed | 19.99 | **20.27** | +1.4% |
| MONO | ascii no-LF | 0.25 | **0.55** | +0.30 ns |
| | ascii w/ LFs | 0.26 | **0.55** | +0.29 ns |
| | utf8 mixed | 0.24 | **0.55** | +0.31 ns |

**ASCII is flat** (v1.5.0 is the slower binary in 6 of 10 rounds). The marker test
sits inside the ESC branch of the existing `b < 0x20` gate, so a printable byte
costs what it did.

**UTF-8 mixed is +0.3 to +0.5 ns/byte (+1.4% to +2.4%)**, and v1.5.0 is the
slower binary in all ten rounds in every mode. The corpus contains no ESC, so
none of the span code runs on it, and the filter's multi-byte path is unchanged
line for line. The suspect was the frame layout: Cyrius gives every `var` a
function-wide stack slot in declaration order, and the span state added 32
bytes of locals ahead of every hot-loop variable. Two variants tested that,
interleaved with v1.4.5 and v1.5.0 (24-bit, utf8 mixed):

| Variant | 6 rounds | 10 rounds |
|---|---:|---:|
| v1.4.5 | 20.27 | 20.34 |
| v1.5.0 (shipped) | 20.75 | 20.80 |
| span state in one heap block (one 8-byte local) | 20.40 | 20.62 |
| no new locals at all (a module global; the marker result in `sgr`'s slot) | 20.56 | — |

Neither recovers it reliably, and the variant with no new locals recovers less
than the one with one. So the layout explains part of the cost at most. The rest
is where the compiler placed the larger loop, which Cyrius offers no control
over. Kept as shipped: about 1 µs on a 2 KB MOTD, and the variants complicate
the span state for less than half of it.

**MONO** scans for the markers: 0.25 → 0.55 ns/byte (see above; a byte loop was
2.04). Micro rows are unchanged; the table emit is 8–9 ns.

- **1.5.0 binary**: **248 288 bytes**, +12 440 B, all anuenue's own source.

## Trend

| Release | Per-byte ASCII (ns) | hsv_rainbow (ns) | tty_fg_rgb_buf (ns) | Binary (B) | Notes |
|---------|---------------------|------------------|---------------------|--------------|-------|
| v0.2.0  | 53                  | 8                | 45                  | 304 368      | M1 baseline |
| v0.3.0  | 53*                 | 8                | 45                  | 317 216      | M2 flags |
| v0.4.0  | 86                  | 8                | 45                  | 322 368      | M3 cluster classifier |
| v0.5.0  | 92†                 | 8                | 45                  | 334 120      | M4 animation |
| v0.6.0  | **47**              | 8                | 45                  | 335 160      | M5 perf pass — table cache |
| v0.7.0  | ~47                 | 8                | 45                  | 349 832      | M6 colour-mode neg. |
| v0.7.1  | ~46                 | 8                | 45                  | 350 488      | Sandhi (darshana 0.5.3) |
| v0.8.0  | ~46                 | 8                | 45                  | 351 200      | M7 docs + M8 audit |
| v0.9.0  | ~46                 | 8                | 45                  | 351 200      | Quality slot (fuzz) |
| **v1.0.0** | **45.71**        | 8                | 45                  | 351 200      | **GA** |
| v1.1.3  | 46.59               | —                | —                   | 394 440      | Toolchain + dep refresh (figures from `state.md`; micros not recorded) |
| v1.2.0  | 47.88‡              | —                | —                   | 389 648      | Library surface (`dist/anuenue.cyr`). Both figures re-measured at v1.2.1 from a rebuilt v1.2.0 binary; micros not recorded at the time |
| v1.2.1  | 46.57‡              | 8§               | 50§                 | 809 520      | Toolchain 6.5.35 + dep refresh + observability |
| v1.2.2  | 46.22‡              | 8§               | 50§                 | 809 984      | P(-1) audit sweep; size cap removed |
| v1.3.0  | —                   | —                | —                   | 814 448      | Animation slot: `-i`, `_frame_wait`, B-01/B-02/B-03. Perf not measured at the cut — see the process note above |
| v1.3.1  | —                   | —                | —                   | 814 448      | PTY harness. Tests and docs only, no `src/` change |
| v1.3.2  | 46.47‡              | 9§               | 50§                 | 814 448      | v1.3.x closeout: perf + audit delta discharged |
| v1.3.3  | 46.46‡              | 8§               | 51§                 | 814 480      | P(-1) sweep: E-01 checked writes (1 HIGH fixed) |
| v1.3.4  | 46.64‡              | 8§               | 51§                 | 814 488      | Allocation-failure probe; E-03 EPIPE fix |
| v1.3.5  | 46.90‡              | 8§               | 51§                 | 814 488      | F-01: transient read errors are not failures |
| v1.3.6  | 48.53‖              | 8§               | 37§                 | 204 312      | Toolchain 6.6.2 + dep refresh. Figures measured at v1.4.0 from a rebuilt v1.3.6 binary; binary compacted by 6.6.x DCE |
| v1.4.0  | 48.56‖              | 9§               | 23§                 | 210 696      | cyrius 6.7.9 + darshana 1.3.0; exit signalfd via darshana; escape table re-measured and kept |
| v1.4.1  | 46.74¤              | 8§               | 21§                 | 222 520      | cmdit 1.4.0 + agnostik 1.12.0; sakshi to the stdlib; cmdit's new parse failures routed |
| v1.4.2  | 47.41¤              | 8§               | 22§                 | 226 624      | stderr hygiene: one line per failure; parse errors name a sanitized token |
| v1.4.3  | 15.40¤              | 9§               | 22§                 | 226 624      | escape-table word copy: 9 ns per escape in every mode; −68% end to end |
| v1.4.4  | 15.60¤              | 8§               | 22§                 | 235 800      | v1.4.x closeout + P(-1) sweep: animation fits the terminal; poll, not sleep |
| v1.4.5  | 15.43¤              | 8§               | 22§                 | 235 848      | input colour codes stripped on the colour routes; flat by design |
| **v1.5.0** | **15.16**¤       | 8§               | 22§                 | **248 288**  | **no-colour spans: ASCII flat, utf8 +1.4–2.4%, MONO 0.25 → 0.55** |

\* v0.3.0 added flag-parsing at startup but the filter hot path
was unchanged; per-byte cost stayed flat.

‡ v1.2.0 and v1.2.1 measured back-to-back on the same idle host at
`RUNS=11`. Earlier rows come from their own cut hosts and carry that
host's variance — compare the ‡ pair to each other, not to the rows
above.

§ v1.2.1 micro-benchmarks ran under 6.5.35's `bench` harness, which
subtracts a measured timer floor the older harness did not. Not
comparable to the rows above.

‖ v1.3.6 and v1.4.0 measured back-to-back on a shared host (load average
~5.4), so both read ~2 ns/byte above the v1.3.x rows, which came from idle
hosts — compare the ‖ pair to each other. Their `tty_fg_rgb_buf` figures are
darshana 1.1.1 (37 ns) and 1.3.0 (23 ns), the composer speed-up darshana 1.2.0
shipped; neither touches the per-cluster hot path.

¤ v1.4.1 measured back-to-back with a rebuilt v1.4.0 on a quieter host (load
1–3), where v1.4.0 read 46.68 — compare that pair, not v1.4.1 against the ‖ row.
v1.4.2 likewise against a rebuilt v1.4.1 (47.38 in that run), v1.4.3
against a rebuilt v1.4.2 (47.72), v1.4.4 against a rebuilt v1.4.3 (15.59),
and v1.4.5 against a rebuilt v1.4.4 (15.30).

† v0.5.0 figure captured by perf-bench.sh on the M5 cut host
(slightly slower than the v0.4.0 86 ns/byte doc number — both
numbers are within host-variance bounds of each other; the M5
acceptance was scoped against the v0.4.0 floor as the regression
to recover).

Post-M6 figures are doc-rounded against host-variance jitter
(the underlying `scripts/perf-bench.sh` reports ±0.5 ns/byte
between consecutive runs). The micro-benchmark figures (`hsv_rainbow`,
`tty_fg_rgb_buf`) measure the table-build path — that's now
one-shot at startup rather than per-cluster (the M5 phase cache
replaced both on the hot path with `_emit_phase_esc`, which this note
used to put at ≈ 10 ns/call; v1.4.0 measured 41–45 ns for truecolor —
see § v1.4.0 — and v1.4.3's word copy brought to 9 ns in every mode).
