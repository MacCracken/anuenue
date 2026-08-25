# anuenue — Benchmarks

> Per-character overhead is the hot-path metric. anuenue sits in MOTD
> pipelines (`iam | anuenue`, `bnrmr | anuenue`), so end-users feel
> the wall-clock cost of one character through the filter on every
> shell login. This file captures the baseline at each release.

## Methodology

Two layers of measurement:

1. **Cyrius `bench` micro** — `tests/anuenue.bcyr`. Per-call cost of
   the two hot-path primitives (`hsv_rainbow` and `tty_fg_rgb_buf`)
   measured with `lib/bench.cyr`'s batched-clock harness (1M iter
   per batch — keeps total wall-time well past the ~120ns
   `clock_gettime` overhead floor).
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
- The DCE cap (512 KB) gives ~161 KB headroom for future v1.x
  sandhi-bump-driven growth.

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

- **1.2.1 binary**: **809 520 bytes** (~790 KB) — **over the 512 KB
  cap by ~278 KB**, up from 389 648 B at v1.2.0 (+419 872, +108%).
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
| **v1.2.1** | **46.63**‡       | 8§               | 52§                 | **809 520**  | **Toolchain 6.5.35 + dep refresh + observability; over the 512 KB cap** |

\* v0.3.0 added flag-parsing at startup but the filter hot path
was unchanged; per-byte cost stayed flat.

‡ v1.2.0 and v1.2.1 measured back-to-back on the same idle host at
`RUNS=11`. Earlier rows come from their own cut hosts and carry that
host's variance — compare the ‡ pair to each other, not to the rows
above.

§ v1.2.1 micro-benchmarks ran under 6.5.35's `bench` harness, which
subtracts a measured timer floor the older harness did not. Not
comparable to the rows above.

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
replaced both on the hot path with `_emit_phase_esc` ≈ 10 ns/call).
