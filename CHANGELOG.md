# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.5.1] — 2026-10-29 (cyrius 6.7.18 + dependency refresh)

The toolchain moves from cyrius 6.7.9 to **6.7.18**, and every dependency moves
to its latest tag: cmdit 1.4.0 → **1.5.0**, darshana 1.3.0 → **1.6.0**,
agnostik 1.12.0 → **2.0.0**, and sakshi 2.5.8 → **2.5.10** through the
toolchain snapshot. Moving to the latest 6.7.x tag at the cut is what the roadmap
slot asked for.

**stdout is byte-identical to v1.5.0**: 301 comparisons against a rebuilt v1.5.0
(stdout and exit code), over twelve corpora × sixteen flag sets, three
environments, one-shot text, eighteen help / error invocations (stderr too) and
18 animation streams (126 frames). One input class changes behaviour: a command
line longer than 2 MiB now parses (below). The binary grows 248 288 →
**532 448 B**, almost all of it data from the toolchain snapshot that no live
code reads (§ Binary).

### Changed — toolchain `6.7.9` → `6.7.18`

- **`lib/` re-vendored** with `rm -rf lib cyrius.lock && cyrius lib sync --full
  && cyrius deps`. It holds the same 116 files as before: 113 stdlib files,
  byte-identical to the 6.7.18 snapshot (69 changed upstream), plus the three
  dep bundles. CI reads the pin from `cyrius.cyml`, so no workflow edit.
- **sakshi 2.5.10** (folded at 6.7.11) declares its four private buffers in
  bytes, not slots. The in-file `.bss` shrinks 82 168 → 23 896 B.
- **`args_init` reads `/proc/self/cmdline` to EOF** (6.7.12), growing a heap
  buffer instead of reading once into 2 MiB. On a failed read it returns a
  negative errno and publishes nothing; anuenue never reads the return value, and
  `argc()` is still 0, which is still `CMDIT_ERR_ARGV` → exit 1. Every route's
  syscall *set* is unchanged (fault-check); `args_init` now makes one more `read`
  (the 0 at EOF).
- **`cyrfmt` checks continuation indents** (6.7.12): 2 spaces per open paren,
  4 accepted. Two continuations were re-indented, and `_find_esc`'s four-word
  test in `src/filter.cyr` gains one pair of parentheses so its 4-space
  continuation is canonical. The binary is byte-identical before and after.
- **cyrlint's array-overrun and write-length rules** (6.7.11, widened at 6.7.12)
  run over `src/`, `tests/` and `fuzz/`. They found three overruns in the unit
  suite (§ Fixed) and nothing in `src/` or `fuzz/`.

### Changed — dependencies

- **cmdit 1.5.0.** No API or error-code change. Every cmdit function anuenue
  calls is body-identical to 1.4.0's; the only change on anuenue's path is the
  private `_cmdit_argv_whole` (1.4.2, below). 1.5.0 fixes the bash and fish
  completion scripts, which anuenue does not emit.
- **darshana 1.6.0.** Additive only. All fourteen Linux functions anuenue calls
  are body-identical to 1.3.0's; `tty_isatty` changed only in its AGNOS arm
  (1.5.0). New and unused here: `tty_sgr_len` / `tty_sgr_strip_buf` (1.4.0,
  built from anuenue's 2026-10-15 proposal and modelled on its stand-in, so
  swapping them in is its own change, roadmap v1.5.3) and
  `tty_isatty_is_per_fd` (1.6.0).
- **agnostik 2.0.0** — a major. One of its renames reaches anuenue: accessors
  take their struct's name, so `agnostik_err_code` is `AgnostikError_code`
  (`src/observe.cyr`, `tests/anuenue.tcyr`). `agnostik_err_new` and
  `agnostik_err_print` keep their names. Two body changes on anuenue's path, both
  from 1.12.3:
  - `agnostik_err_new` never fails. When its 24 bytes cannot be had, it returns a
    static `RESOURCE_EXHAUSTED` "out of memory" error instead of writing through
    address 0. This closes the issue anuenue filed on 2026-10-14.
  - `agnostik_err_print` skips the zero-length `write` it made for an empty
    message.

### Changed — a command line past 2 MiB parses whole

Through v1.5.0 a command line over 2 MiB was refused (exit 1, `could not read
the full command line`), because the stdlib could only read its first 2 MiB.
With 6.7.12's `args_init` and cmdit 1.4.2, which narrowed its check to the one
ambiguous length (exactly 2 097 152 bytes, still refused), a longer one parses
whole. **Robustness gate 7 is inverted to match**: a 2.4 MB command line now
exits 0, and the `--seed 99` at its very end is honoured. The gate checks the
seed by comparing the first cluster's escape with `--seed 99 x`'s. The new check
fails on the v1.5.0 binary (exit 1, seed lost) and passes here. The 1.0 MB
control and the `--nofile=3` check are unchanged.

### Fixed — three stack overruns in the unit suite

`tests/anuenue.tcyr` declared `var argv1[8]`, `var argv2[8]` and `var
argv5[32]`, then stored 2, 2 and 5 pointers into them. A bare `var a[N]` in a fn
is N **bytes**, so each last `store64` overwrote the next local's stack slot.
They are now `[16]`, `[16]` and `[40]`. Test code only: the shipped binary never
had them, and the suite stays 595 / 595.

This was the v1.4.3 crash anuenue filed as a cyrius miscompile ("growing a large
function segfaults an earlier call"). cyrius 6.7.14 closed that issue as **not a
cyrius bug**. `store64(&argv2 + 8, …)` overwrote `fs2`'s slot, which was only
read once `main()` passed 256 local slots and the register allocator stopped
keeping `fs2` in a register. The new lint rule names all three lines.
CLAUDE.md's "large functions are a miscompile risk" rule is corrected.

### Binary

**248 288 → 532 448 B** (+284 160). One change per row, each built from the same
source:

| Step | Size | Δ |
|---|---:|---:|
| v1.5.0 on cyrius 6.7.9 | 248 288 | — |
| cyrius 6.7.18, deps at the v1.5.0 tags | 531 824 | **+283 536** |
| + cmdit 1.5.0 | 531 960 | +136 |
| + darshana 1.6.0 | 531 960 | 0 |
| + agnostik 2.0.0 (and the rename) | 532 448 | +488 |

The toolchain row is data. `.text` grows 125 616 → 126 448 B (+832), the
in-file `.bss` shrinks by 58 424 B (sakshi 2.5.10), and `.rodata` grows 38 790 →
380 751 B (+341 961). agnostik measured the same `.rodata` growth in its own
build at this pin (+341 994 B, its 1.12.1 CHANGELOG). The cause is the `bayan`
fold, which agnostik's `dist/agnostik.deps` pulls in: from 6.7.13 it includes
`lib/unicode/`. All three Unicode tables are in anuenue's binary byte for byte:
`_normalize_data` 154 002 B, `_casefold_data` 95 234 B and `_categories_data`
58 016 B, **307 252 B** of global string literals. DCE drops every function
that reads them but keeps the data. anuenue calls none of them and cannot drop
`bayan` (agnostik requires it), so this is recorded, not capped. Filed as cyrius
`docs/development/issues/2026-10-29-anuenue-dce-keeps-literals-of-dead-code.md`,
with a three-program repro (a 100 000-byte literal read only by a dead fn
survives `CYRIUS_DCE=1`). Non-DCE 997 856 → 1 531 872 B.

### Performance

The rebuilt v1.5.0 against v1.5.1, `RUNS=11`, ten interleaved rounds (the
second five reversed), medians, ns/byte. MONO uses a 14 MB corpus, eight
rounds; at the default 1.4 MB its overhead is below the script's millisecond
resolution.

| Corpus | truecolor | 256 | 16 | MONO |
|---|---:|---:|---:|---:|
| ascii no-LF (M5 metric) | 15.25 → **15.16** | 15.14 → **15.13** | 15.00 → **15.06** | 0.56 → **0.57** |
| ascii w/ LFs | 19.74 → **19.93** | 19.79 → **19.87** | 19.73 → **19.88** | 0.56 → **0.57** |
| utf8 mixed | 20.55 → **20.16** | 20.45 → **20.21** | 20.33 → **20.11** | 0.55 → **0.56** |

Flat: every colour-route median is within ±2% and every pair of ranges
overlaps. Micro rows (`cyrius bench`): `hsv_rainbow` 8 ns, `tty_fg_rgb_buf`
22 ns, the escape-table emit 9 ns in every mode.

### Verification

- Unit **595 / 595**; fuzz **8 harnesses, 1 780 057**; robustness **80**; PTY
  **33**; allocfail **23**; signal **18**; observe **27**; golden **10**;
  animate-smoke **17**; fault-check **17**. Every route's syscall set is identical
  to v1.5.0's.
- `scripts/lint-check.sh`: 22 files, zero warnings. `cyrius audit` clean.
  `cyrius distlib --check` current.
- **Downstream**: `dist/anuenue.cyr` changes only its `# Version:` line, and
  `src/hsv.cyr` is unchanged since 1.3.6, so thoth's vendored copy is unaffected.
- Clean build: `rm -rf build && cyrius deps && CYRIUS_DCE=1 cyrius build
  src/main.cyr build/anuenue` → 532 448 B.

### Docs

- **Roadmap**: the v1.5.1 slot is shipped and removed. **v1.5.3** is new: swap
  the SGR stand-in for darshana's scanner. § Upstream: the `args_init`, the
  "miscompile" and the `agnostik_err_new` items are closed, and the DCE-literal
  issue is added.
- **CLAUDE.md**: the large-function rule now names the real cause (byte-sized
  arrays) and keeps per-group test functions.
- **`state.md`**: darshana's row named twelve symbols and listed
  `tty_sanitize_buf` as unused. anuenue has called it since v1.4.2, and
  `tty_winsize` since v1.4.4, so the row now names fourteen.

## [1.5.0] — 2026-10-15 (no-colour spans)

The counterpart to v1.4.5. With anuenue owning the colour on its colour routes,
a producer had no way to keep part of its output out of the rainbow — a logo
with its own colours, a warning that must stay red, a prompt — short of
splitting its output around anuenue. The user asked for a "no color" code on the
producer's side (2026-10-14) and chose an ECMA-48 **application program
command** pair; the design questions were decided with the user on 2026-10-15
and recorded in [ADR 0006](docs/adr/0006-no-colour-spans.md).

```
ESC _ anuenue:off ESC \      ← from here, untinted
ESC _ anuenue:on  ESC \      ← the rainbow resumes
```

**stdout is byte-identical to v1.4.5 for every input without a marker**: 209
filter and one-shot comparisons and 18 animation streams (144 frames), over
twelve corpora that include SGR, OSC, DCS, kitty-style APCs and near-miss
markers. Audit delta:
[`docs/audit/2026-10-15-v150-delta.md`](docs/audit/2026-10-15-v150-delta.md) —
**12 findings, 1 HIGH + 2 MEDIUM + 5 LOW + 4 INFO, all in this release's own
new code, ten fixed before release and two recorded; zero HIGH+ open.**

### Added — no-colour spans (ADR 0006)

- **Inside a span the producer's bytes pass through intact**, colour codes
  included: the span is the producer's. A span with no codes shows in the
  terminal's default colour.
- **A combining mark straight after a span continues the cluster before it**,
  with its hue, as it would with the span removed. ZWJ and flag joins do not
  reach across a span, empty or not.
- **One SGR reset at each marker**, and nothing else of anuenue's inside the
  span — no reset before an LF either, so a producer's colour may run across
  lines. The end of the input closes a span still open, with one reset.
- **The rainbow pauses**: span bytes take no phase step, so the text after a
  span takes the hue that would have followed the text before it.
- **Lenient**: `off` with no `on` runs to the end of the input; a stray `on`,
  or an `off` inside a span, is a no-op. Markers are always consumed, never
  written, and nothing errors.
- **Exact markers only** — lower case, no whitespace, ST (`ESC \`) as the
  terminator. Every other APC passes as before.
- **Every route consumes the markers, MONO included.** They are commands to
  anuenue, not text. MONO stays byte-exact for every other byte.
- **Streaming**: a marker a 4096-byte read cuts off is carried into the next
  read, like a split UTF-8 sequence or an unfinished SGR, at most 14 bytes. The
  filter tests for the marker only at an ESC, inside the existing `b < 0x20`
  gate, so ordinary text pays nothing.
- **Animation** draws a span raw in every frame while the text around it
  cycles. Escape sequences inside a span reach the terminal intact, so the
  physical-row count (v1.4.4's H-01) parses them as the terminal does: a
  VT500-parser step, `_span_vt`, covering CSI, OSC, DCS / SOS / PM / APC
  strings, escape intermediates, C0 controls executed mid-sequence, and
  CAN / SUB.
- **`-v`** reports `no-colour markers consumed count=N` at debug level.

**Contract**: [ADR 0001](docs/adr/0001-pipe-purity.md) is amended a second
time — markers are removed on every route. MONO is byte-identical to `cat` for
every input without a marker.

### Security — caught before release

**V-06 (HIGH): empty spans overflowed the line buffer.** The first cut wrote
the reset at each marker without the reserve check that follows every other
write ([architecture 001](docs/architecture/001-buffer-geometry.md)). An empty
span (`off` then `on`) writes two resets and no byte, so nothing flushed, and
a run of them grew the write position without bound until the next LF:
- 4 200 empty spans in a one-shot argument: SIGSEGV;
- 5 000 on stdin: a 40 KB line from a 32 KB buffer, overwriting the read
  buffer (markers leaked to stdout);
- 100 000: the phase table overwritten (wrong colours).

Found by the cut's independent code review; it never shipped. Every marker
reset is now `_reset_checked`, and robustness gate 11 `EMPTY` runs 100 000
empty spans through the filter and 4 400 through the one-shot route.

### Review — found and fixed before release

Writing the gates found five defects (V-01 to V-05) and the independent review
four more (V-07 to V-10). In brief:
- **V-02 (MEDIUM)**: animation's row count misread intact sequences inside a
  span — an LF inside an unfinished CSI (a terminal executes it), an ESC
  restarting a CSI, DCS / APC strings and escape intermediates. Each frame
  climbed a row short (scrolling a copy into scrollback) or too far (drawing
  over what is above). Now `_span_vt`.
- **V-07 (MEDIUM)**: a combining mark after a span got its own phase step in
  animation, so every later cluster was a hue behind the filter, and a column
  it does not take.
- **V-01**: a span still open at the end left the producer's colour set into
  the shell prompt. **V-03**: adjacent spans shared attributes in animation.
  **V-08**: animation did not see empty spans (joins survived them).
  **V-09**: a UTF-8 sequence cut by a span was decoded whole in animation.
  **V-10**: after `ESC (`, a `[` or `_` began a sequence in the row count.
- **V-04, V-05 (INFO)**: a reserve flush inside a span wrote a reset; the PTY
  gate could not see a climb that went too far — it now checks that every
  frame climbs back to the same row.

Recorded, not changed here: **V-11**, two phase disagreements between the
routes that predate v1.5.0 (pinned to roadmap v1.5.2), and **V-12**, two
terminal-dependent cases in the span row count (trigger-gated).

### Performance

A rebuilt v1.4.5 against v1.5.0, `RUNS=11`, **ten** interleaved rounds (the
second five reversed), medians, ns/byte:

| Corpus | truecolor | 256 | 16 | MONO |
|---|---:|---:|---:|---:|
| ascii no-LF (M5 metric) | 15.12 → **15.16** (+0.2%) | 15.10 → **15.13** | 14.94 → **14.97** | 0.25 → **0.55** |
| ascii w/ LFs | 19.68 → **19.70** | 19.69 → **19.64** | 19.59 → **19.63** | 0.26 → **0.55** |
| utf8 mixed | 20.08 → **20.43** (+1.7%) | 19.99 → **20.48** (+2.4%) | 19.99 → **20.27** (+1.4%) | 0.24 → **0.55** |

- **ASCII is flat**: the marker test sits inside the existing ESC branch.
- **UTF-8 is +0.3–0.5 ns/byte**, consistently. None of the span code runs on
  that corpus, and the multi-byte path is unchanged. Two variants that took the
  span state's 32 bytes of locals out of the frame recovered under half of it,
  so it stays as shipped: about 1 µs on a 2 KB MOTD. `docs/benchmarks.md` has
  both variants' figures.
- **MONO now scans for the markers**, eight bytes at a time (`_find_esc`): +0.3
  ns/byte, still over 25× cheaper than a colour route. A byte loop measured 2.04.

**Binary** 235 848 → **248 288 B** (+12 440), all anuenue's own source. Non-DCE
997 856.

### Added — tests

- **Unit** (506 → **595** assertions, 60 → **73** groups) in three new
  functions: `test_v150_markers` (recognition, MONO strip, the prepare pass,
  raw clusters, the row count inside a span), `test_v150_vt` (`_span_vt`'s
  transitions, the row count over intact sequences, adjacent spans) and
  `test_v150_review` (V-07 to V-10, one group each, and `_find_esc` at every
  offset of every length to 72).
- **Fuzz** — `fuzz/no-colour-markers.fcyr`, an **eighth harness** (258 175
  assertions). The MONO strip and the animation prepare pass are checked
  against an independently written reference, whole and in two chunks with
  the held tail carried. The pre-tag's clusters are checked for coverage: raw
  clusters hold only span bytes, no span edge falls inside a cluster, and
  `CF_OPEN` / `CF_JOIN` / `CF_CONT` sit exactly where they should. The tokens
  cut UTF-8 sequences and markers. Fuzz total 1 521 882 → **1 780 057**.
- **`scripts/robustness-check.sh` gate 11** (60 → **80** checks): spans on the
  filter, one-shot and animation in all three modes, with the phase pause
  checked by removing the span and comparing. Also: an LF inside a span; the
  end of the input closing a span; adjacent spans; a reserve flush inside a
  span; 100 000 empty spans (V-06); the routes agreeing on hues and bytes at
  span edges; lenient markers; near-misses; either marker split across the
  4096-byte read at every offset; one byte per write; MONO.
- **`scripts/pty-check.sh` gate 5** (25 → **33** checks): eight span cases
  played into the terminal model — producer SGR with wide characters, a
  multi-line span, an APC, an OSC 8 hyperlink, an LF inside a CSI, adjacent
  spans, a mark after a span, an escape intermediate. Two things changed in
  the gate itself: `scripts/term-model.py` now parses OSC, DCS, SOS, PM, APC
  and intermediates as xterm does, and the gate requires every frame to climb
  back to the same row and never past the top.
- **Mutation-checked**: 34 deliberate breaks of the new code, each failing at
  least one of the new tests.
- `scripts/perf-bench.sh` takes `COLOR=none` (MONO).

### Docs

- **ADR 0006** (new): the marker and the seven decisions, with the review's
  refinements (the end of the input closes a span; an extender after a span;
  the VT parser). **ADR 0001** amended. **Architecture 001**: the span write
  paths, and V-06's lesson.
- The integration guide's *No-colour spans* section, the README, getting
  started, and `docs/examples/10-no-colour-span.sh` (new; the examples index
  also gains the missing `09`).
- **Roadmap**: the v1.5.0 slot is shipped and removed. The cyrius 6.7.x slot is
  **v1.5.1** (renumbered from v1.4.6, as the user asked). **v1.5.2** is new,
  for V-11. Adoption and `-vvv` move to v1.6.0. V-12 is added to the trigger
  table.

## [1.4.5] — 2026-10-15 (input colour codes stripped)

The v1.4.4 audit's H-06, decided on 2026-10-14. On the routes where anuenue
colours — the filter, one-shot text, animation — the **input's own SGR colour
codes are now removed**, and the text they wrapped gets the rainbow like
everything else. The rationale: "the effects are anuenue controlled at that
point". Before, they could not survive anyway: anuenue writes an escape before
every cluster, an input ESC is a cluster of its own, and the terminal saw the
input's ESC cancelled by anuenue's. So `ls --color=always | anuenue` printed
`[01;34m` as text.

**stdout is byte-identical to v1.4.4 for every input without a colour code**:
232 filter and one-shot comparisons and 18 animation streams. None of the
corpora contains an SGR.

### Changed — the input's SGR colour codes are stripped on the colour routes

- **Exactly SGR**: ESC, `[`, parameter bytes 0x30–0x3B (digits, `;`, and `:`
  for colon sub-parameters), then `m`, at most 128 bytes in all
  (`ANUENUE_SGR_MAX`). Not stripped:
  - a private marker (`ESC [ ? … m`, `ESC [ > … m`, xterm's
    modifyOtherKeys) or an intermediate byte;
  - any other escape sequence (`ESC [ 2J`, OSC titles);
  - an unfinished or broken SGR;
  - anything over 128 bytes.

  Each of these passes byte for byte, as before. So a hostile `ESC [` followed
  by megabytes of digits costs a bounded look-ahead, never a held buffer.
- **MONO is untouched.** `NO_COLOR`, `--no-color` and `--color=none` still copy
  stdin byte for byte, input colour codes included, because there anuenue adds
  no colour.
- **Streaming**: the filter drops SGRs inline, in its own byte loop. An SGR a
  4096-byte read cuts off is carried into the next read with the same
  mechanism as a split UTF-8 sequence, bounded at 127 bytes. One-shot text and
  animation strip their in-memory buffer first, with `anuenue_sgr_strip`.
- **`-v`** reports `input colour codes stripped count=N` at debug level.
- **Phase**: stripped bytes are not clusters, so they take no phase step. A
  combining mark separated from its base only by a colour code now joins it.

**Contract**: [ADR 0001](docs/adr/0001-pipe-purity.md) is amended. The stream is
preserved byte for byte except the input's own SGR codes on the colour routes.
The held-sequence carry is bounded, so the no-buffering rule holds.

### Performance

The first version was a separate strip pass over every chunk. It measured
**+1.7 ns/byte (+11%)** on ASCII and was rejected. An ESC test on every ASCII
byte measured +0.3 (+2%). The shipped version tests ESC together with LF behind
a single `b < 0x20` comparison, so a printable byte costs the same two
comparisons it did in v1.4.4. A rebuilt v1.4.4 against v1.4.5, `RUNS=11`,
**ten** interleaved rounds (the second five in reversed order), medians, idle
host:

| ascii no-LF, ns/byte | v1.4.4 | v1.4.5 | Δ |
|---|---:|---:|---:|
| truecolor (M5 metric) | 15.30 | **15.43** | +0.8% |
| 256 | 15.24 | **15.30** | +0.4% |
| 16 | 15.19 | **15.20** | +0.0% |

Flat — all nine corpus × mode rows are within ±0.8%, with mixed signs. Micro
rows are unchanged (the table emit is 8–9 ns).

**Binary** 235 800 → **235 848 B** (+48). Non-DCE 985 416.

### Added — tests

- **Unit** (484 → **506** assertions, 59 → **60** groups, in
  `test_v145_sgr`). It covers:
  - every SGR form above;
  - every non-SGR that must pass;
  - the held tail at a chunk end;
  - the 128 / 129-byte bound.
- **Fuzz** — `fuzz/sgr-strip.fcyr`, a **seventh harness** (30 000
  assertions). It compares the stripper with an independently written
  reference, and requires that stripping in two chunks, with the held tail
  carried, equals stripping in one. Mutation-checked: never holding fails it
  54 times; excluding `;` from the parameter range fails it 500+ times. Fuzz
  total 1 491 882 → **1 521 882**.
- **`scripts/robustness-check.sh` gate 10** (46 → **60** checks):
  - stripping on the filter, one-shot and animation routes in all three modes;
  - MONO byte-exact;
  - a 5-, 19- and 128-byte SGR split across the 4096-byte read at every offset;
  - an SGR arriving one byte per write;
  - the bound;
  - non-SGR sequences intact.

  On v1.4.4, the 11 stripping checks fail and the two that should hold on both
  pass. Disabling the inline carry fails the boundary and dribble checks.

### Docs

- **Roadmap**:
  - the cyrius 6.7.x slot is now **v1.4.6**;
  - **v1.5.0** is the producer-side "no colour" marker, the APC pair
    `ESC _ anuenue:off ESC \` … `ESC _ anuenue:on ESC \` (format chosen
    2026-10-14), with the questions it must settle written into the slot;
  - adoption rides along if a consumer has landed;
  - the H-06 trigger row is removed.
- ADR 0001 and 0005, the integration guide (*Colour codes already in the
  input*), the README, the audit delta (H-06 marked resolved) and
  `_block_rows`'s comment are updated.
- **Upstream ask**: darshana owns ANSI grammar but has no input-side SGR
  scanner (`tty_sanitize_buf` neutralises every control, which is the wrong
  tool). Filed as darshana
  `docs/development/proposals/2026-10-15-input-sgr-scanner.md`, with anuenue's
  `_sgr_len` / `anuenue_sgr_strip` as the stand-in, same contract.

## [1.4.4] — 2026-10-14 (v1.4.x closeout + P(-1) sweep)

The v1.4.x arc's closeout and the minor-cut audit sweep. Audit delta:
[`docs/audit/2026-10-14-v14x-delta.md`](docs/audit/2026-10-14-v14x-delta.md) —
**6 findings, 1 MEDIUM + 2 LOW + 3 INFO, zero HIGH+.** Five are fixed in-cut.
H-06 is recorded, not fixed: it changes stdout, so it needs an owner. **Every
guard ever recorded as unproven is now proven by a gate.**

**stdout is byte-identical to v1.4.3 on every pipe route**, the filter and
one-shot text over the 12-corpus × 18-flag matrix and 18 animation streams,
with one exception: H-05, where animation now renders the combining mark it
used to drop. What changed that a user can see, all of it on a terminal:
- animation no longer smears a too-wide or too-tall block;
- a block taller than the terminal is drawn once;
- a stalled non-blocking peer no longer costs CPU.

### Fixed — H-01 (MEDIUM): animation smeared in a terminal too small for the block

Re-anchoring climbed one row per LF, so a line wider than the terminal (it
wraps) or a block taller than it (it scrolls) made every frame scroll a copy of
the block into scrollback, at ~60 frames a second. Measured with a new terminal
model, `scripts/term-model.py`, fed a real pty's transcript: five 162-column
lines at 80 columns scrolled **+8.7 rows per frame**, and a 40-line block on 24
rows **+17**. A single line over 80 columns is enough.

Now, when stdout is a terminal of known size, the climb is counted in
**physical rows**, using a display-width table generated from UAX #11
([ADR 0005](docs/adr/0005-practical-subset-display-width.md)). A block that
still cannot fit is **drawn once**, with a `warn` record. The size comes from
the `TIOCGWINSZ` ioctl `tty_isatty` already issues. On an unknown size (a pipe,
an unsized pty, agnos) the count is the old LF count exactly, so non-terminal
output is unchanged.

The fix's first cut had two errors, both caught by this cut's code review
before release:
- **the width table**: hand-picked, it called ✅ ✨ ⚡ ⭐ ❌ ☕ 1 column wide;
- **input escapes**: they were modelled as zero-width, and an unterminated
  OSC swallowed every LF after it, so the climb fell below v1.4.3's count.

The table is now `scripts/gen-wide-table.py`'s output: Unicode 16.0, 82
ranges, binary-searched. An input ESC counts 0 columns and the bytes after it
count normally, because that is what reaches the screen (H-06).

### Fixed — H-02 (LOW): waiting on a non-blocking descriptor was polling

`anuenue_read_some` / `anuenue_write_all` answered EAGAIN with `sleep_ms(1)`
and a retry. With a non-blocking stdin whose writer stalled, that was **30 ms
of CPU every 4 s**, about 1 000 wakeups a second, for as long as the stall
lasted. A stalled non-blocking stdout did the same. Both now block in `poll(2)`
on the descriptor (`anuenue_wait_fd`, over the stdlib's `fd_wait_ready`): **0
ms**. `poll` is already in the surface, because `sleep_ms` is
`poll(NULL, 0, ms)`. On agnos, where the wait is ENOSYS, it falls back to the
1 ms sleep. A stalled *blocking* stdin was already correct: 0 ms CPU, the line
before the stall rendered, SIGTERM exits in 0.2 ms.

### Fixed — H-05 (LOW): animation dropped an extender with nothing to extend

Present since M4, found by the code review. `printf 'a\n\xcc\x81b\n' | anuenue -a`
rendered `a\nb\n`: the U+0301 had folded into the LF's cluster, which renders as
reset + LF only. A combining mark at the very start of the input was never
tagged at all. The filter path kept both. Such an extender now opens a cluster
of its own.

### Fixed — H-03 / H-04 (INFO): two documented properties that were never measured

- **H-03**: the capability surface, in ADR 0001's table, the guide and five
  comments, named `brk(12)` for the heap. Measured under gdb, **no route issues
  `brk`**: the stdlib heap has used anonymous `mmap` since cyrius 6.1.19. The
  table also omitted animation's `fcntl`, `poll` and `clock_gettime`. All
  corrected from the measurement, which is now a gate (below).
- **H-04**: architecture 001's worst-case table summed four components to
  "≤ 29 — fits in 32". They sum to 33, and two of them never share an
  iteration. The real bound is escape (24) + codepoint (4) + the flush's reset
  (4) = **32: exactly the reserve, zero slack** at the escape budget, 7 at the
  17 bytes anuenue emits. The unit group behind it still described v0.3.0's
  22-byte reserve. Both are rewritten, and the group asserts
  `RESERVE ≥ (ENTRY_SIZE − 8) + 4 + 4`.

### Recorded — H-06 (INFO): escape sequences in the input do not survive

anuenue's own escape before every cluster cancels each input ESC, so the rest
of the sequence prints as text: `ls --color=always | anuenue` shows `[01;34m`.
True on every route since M1; every byte still reaches stdout. Fixing it means
choosing a stdout behaviour: strip input SGR as Ruby lolcat does, or pass whole
input sequences through untinted. It is a trigger-gated item in the roadmap.

### Proven — every guard recorded as unproven

| Guard | Recorded unproven at | Now proven by |
|---|---|---|
| D-01, `_frame_wait`'s zero-tick guard | v1.3.2 | `tests/probes/tick-probe.cyr`: tick 0 and −5 return; without the guard it times out |
| E-01, zero-byte write | v1.3.3 | gdb injection, `write` returning 0: exit 1, reported |
| EINTR, read and write | v1.3.5 | gdb injection, −4 on the first call: retried, output byte-identical, on filter / MONO / animation slurp |
| NOMEM, `cmdit_new`'s OOM | v1.4.1 | `allocfail-probe` under a really exhausted heap: a real 0 handle, exit 1, reported through `anuenue_fail`'s no-allocation fallback |
| the signalfd's `fd_set_nonblocking` failing | v1.4.0 | gdb injection, −EINVAL on the first `fcntl`: warns, falls back, frames byte-identical |

The NOMEM routing moved from `src/main.cyr` into `anuenue_parse_runtime_failure`
(`src/observe.cyr`) so the probe could reach it.

### Added — `scripts/fault-check.sh` (CI-wired) and the gdb harness

- **Layer 1**, the D-01 probe.
- **Layer 2**, `scripts/gdb-inject.py`: it changes exactly one syscall of the
  real binary under gdb — the first match — and lets the rest through:
  - **zero**: the length set to 0, so the kernel returns 0;
  - **eintr** / **fail<errno>**: the call turned into `getpid`, and its
    return value rewritten.
- **Layer 3**, the capability surface: `scripts/gdb-syscalls.py` records every
  syscall of seven routes, and each set must stay inside its allowlist. A
  build that adds one `getpid` fails all seven.

The gdb layers skip cleanly without gdb, without ptrace, or off x86_64. CI
installs gdb. Every case is mutation-checked.

### Changed — closeout

- **The unit suite's `main()` is sixteen per-cut functions.** It held every
  group since M1, about 140 locals, and growing it by one more group at v1.4.3
  crashed the suite (the cyrius issue below). The suite's output is
  line-for-line identical before and after.
- **`scripts/pty-check.sh`** matched the animation process by the literal name
  `anuenue`. So its own documented `BIN=build/anuenue-dce` usage failed gate
  4; it now uses `BIN`'s basename.
- **Dead code**: the floor is one function, `anuenue_log_parse_name`, reached
  only from tests. It is kept as the fuzz round-trip's oracle (DCE drops it).
  Its comment claimed two callers that do not exist, and is corrected.
- **Cleanup**: five stale "unproven" comments now point at their gates, and
  the `brk` claims are gone (H-03). Lint's deferral heuristic flagged
  "deferred autowrap" twice; that is prose, reworded rather than suppressed.
- **Downstream**: thoth vendors `dist/anuenue.cyr` (at 1.3.6) for `/theme
  rainbow`. Its code is identical to 1.4.4's apart from the header, so nothing
  changes for it. `state.md` now lists it as a consumer; it had said "None
  yet" since M0.
- **Docs**: the integration guide and README describe the draw-once
  behaviour. ADR 0005 records the width decision and its in-cut amendment.

### Added — tests

- **Unit** (437 → **484** assertions, 56 → **59** groups):
  - H-01's width and row count (+40);
  - H-05's clustering (+6);
  - H-04's reserve bound (+1).
- **`scripts/pty-check.sh` gate 5** (14 → **25** checks): the width oracle at
  every cluster-starting codepoint to U+3FFFF, then ten sized-pty animation
  cases played into the terminal model.
- **`scripts/robustness-check.sh`** (38 → **46**): H-02's four stall checks and
  H-05's four animation byte-preservation checks.
- **`scripts/allocfail-check.sh`** (17 → **23**): NOMEM under exhaustion.
- **`scripts/observe-check.sh`** unchanged at **27**. **`scripts/fault-check.sh`**
  is new, at **17**.
- **Fuzz** 1 483 587 → **1 491 882**: `pretag-clusters` asserts coverage (the
  first cluster at byte 0, an LF cluster the LF alone) and gains an
  LF / combining / ZWJ / RI token corpus. On v1.4.3's code the new invariants
  fail 584 times.

### Upstream

- **agnostik: `agnostik_err_new` writes through an unchecked `alloc(24)`**
  (`src/error.cyr:32` at 1.12.0). Found by the review, filed as agnostik
  `docs/development/issues/anuenue-agnostik-err-new-unchecked-alloc-2026-10-14.md`.
  It is filed, not patched: agnostik's own agent repairs agnostik. In
  anuenue it is reachable only if `str_new` succeeds and the next small
  allocation fails.

### Performance

The per-cluster path did not change. A rebuilt v1.4.3 binary against v1.4.4,
`RUNS=11`, **five** interleaved rounds per mode, medians. A first, three-round
run on a host at load average ~11 swung ±10% with mixed signs; it was
discarded, and the five rounds ran at load average 5–7:

| ascii no-LF, ns/byte | v1.4.3 | v1.4.4 | Δ |
|---|---:|---:|---:|
| truecolor (M5 metric) | 15.59 | **15.60** | +0.1% |
| 256 | 15.42 | **15.51** | +0.6% |
| 16 | 15.34 | **15.40** | +0.4% |

Flat — all nine corpus × mode rows are within ±0.6%. Micro rows are unchanged
from v1.4.3: the table emit is 9 ns in every mode.

**Binary** 226 624 → **235 800 B** (+9 176; non-DCE 985 368). Measured stepwise, `fd_wait_ready` (H-02)
alone is +4 096. The rest is H-01's table, row count and size query, plus H-05.
The binary grows in what look like page-aligned steps, so finer attribution is
not meaningful.

### Docs

- **The cyrius miscompile found at 1.4.3 is filed** as cyrius
  `docs/development/issues/2026-10-14-anuenue-growing-a-large-fn-segfaults-an-earlier-call.md`.
  The reproduction is pinned to anuenue tag 1.4.2, with the probes that ruled
  out local count, array locals and code size, and no proposed fix.
  Investigating it is the cyrius agent's job; anuenue's part ends at filing.
  The roadmap's *Upstream* entry, CLAUDE.md, `state.md` and `test_word_copy`'s
  comment now name the issue.

### Fixed — CI: the width oracle ran on the wrong Unicode version (in the re-cut tag, `cb47ceb`)

v1.4.4's CI failed in `scripts/pty-check.sh` gate 5: "188 codepoints differ
from UAX #11 (first: U+2630)". The width table is right. The comparison was
not like for like:
- the table was generated by Python 3.14, whose `unicodedata` is Unicode
  16.0.0;
- the runner's stock Python is older, and Unicode 16.0 made U+2630–2637
  (and others) Wide;
- so every difference was version drift between the two.

The fix:
- the generated header now names both versions: `Unicode 16.0.0, Python 3.14`;
- gate 5 compares strictly only when the runner's Unicode equals the
  table's, and otherwise skips with a reason;
- CI reads the Python version from that header, installs it with
  `actions/setup-python`, and runs the gate with
  `ANUENUE_WIDTH_ORACLE_STRICT=1`, so on CI a mismatch fails instead of
  skipping.

Regenerating the table with a newer Python moves CI with it; no version is
hardcoded in the YAML. Test and CI infrastructure only: the binary is
byte-identical to v1.4.4.

## [1.4.3] — 2026-10-14 (escape-table word copy)

The roadmap's v1.4.3 slot: `_emit_phase_esc` copies a table entry as three
8-byte words instead of one byte at a time. **The filter path is 51–68% faster
end to end** — truecolor ASCII 47.72 → **15.40 ns/byte** — and colour mode no
longer changes the cost: all three modes now run at about 15.4. **stdout is
byte-identical to v1.4.2**: 232 filter and one-shot comparisons (12 corpora
× 18 flag sets, plus positional text including a 40 000-byte argument) and 12
full animation streams in three modes. The goldens are unchanged.

### Performance

`_emit_phase_esc` ran once per grapheme cluster, and its byte-copy loop was the
largest cost left on that path. Micro (`tests/anuenue.bcyr`, ns per escape,
three runs each; v1.4.3 read 9 on every run):

| Mode | v1.4.2 | v1.4.3 |
|---|---:|---:|
| truecolor | 39 | **9** |
| 256 | 27–28 | **9** |
| 16 | 16–17 | **9** |

End to end (`scripts/perf-bench.sh`, a rebuilt v1.4.2 binary against v1.4.3,
`RUNS=11`, three interleaved rounds per mode, medians, ns/byte, load average
~2):

| Mode | corpus | v1.4.2 | v1.4.3 | Δ |
|---|---|---:|---:|---:|
| truecolor | ascii no-LF (M5 metric) | 47.72 | **15.40** | −67.7% |
| | ascii w/ LFs | 51.73 | **20.19** | −61.0% |
| | utf8 mixed | 42.10 | **20.53** | −51.2% |
| 256 | ascii no-LF | 34.63 | **15.36** | −55.6% |
| | ascii w/ LFs | 39.37 | **20.08** | −49.0% |
| | utf8 mixed | 33.48 | **20.65** | −38.3% |
| 16 | ascii no-LF | 23.46 | **15.31** | −34.7% |
| | ascii w/ LFs | 28.09 | **20.02** | −28.7% |
| | utf8 mixed | 25.96 | **20.38** | −21.5% |

Cross-checked outside the harness: a 10 MB ASCII file through `--color=24bit`
took 509 → 192 ms (median of five, startup included), same md5 out. The saving
is ~30 ns per escape on truecolor, and ASCII is one escape per byte, so the
ns/byte drop matches the micro number. That puts the M5 acceptance figure (≤ 60)
at a quarter of its bound.

**The table now beats direct composition in every mode** (9 ns against 23–36),
so the truecolor exception v1.4.0 measured is gone.

**Binary** 226 624 B, the same total as v1.4.2 (different content; the change nets to zero bytes).

### Changed — `_emit_phase_esc` writes 24 bytes, advances by `elen`

The write footprint is now `[pos, pos + 24)` whatever the escape's length.
`pos` advances by `elen` as before. The bytes past the escape are scratch, and
that is safe only because of an argument the code did not need before. It is
now [architecture 001 § The escape write footprint](docs/architecture/001-buffer-geometry.md),
call site by call site:

- every caller enters with `pos <= LINE_BUF - FLUSH_RESERVE`: either at the top
  of an iteration, or right after a flush that set `pos = 0`. The footprint (24)
  fits the reserve (32). All eight call sites were checked.
- every flush writes `[0, pos)`, and the next write starts at the advanced
  `pos`, so scratch is overwritten or left past `pos`. It never goes out.
- the three-word read is exactly the entry's payload region, `[entry + 8,
  entry + 32)`.

`_phase_esc_init` now **zero-fills each entry's payload** before writing the
escape, so the scratch is deterministic. Without it, a rebuild in place for a
shorter mode (truecolor → 16, the E-02 path) would leave the longer escape's
tail behind every new one.

### Changed — `fuzz/emit-phase-esc.fcyr` asserts the new footprint

"Writes exactly `elen` bytes" described the byte loop and is no longer true.
It is restated as three properties:

- **the footprint**: the escape bytes equal the table entry's, then zeros to
  `pos + 24`, then nothing.
- **the stream** (new, `fuzz_emit_stream`): 3 000 random clusters per mode go
  through `_emit_phase_esc` and through a byte-copy reference emitter. Every
  prefix flushed at the filter's reserve must be byte-identical. This checks the
  callers' "scratch never flushed" property without a process.
- the old bounds checks, unchanged.

`emit-phase-esc` 1 013 957 → **1 046 876** assertions; fuzz total 1 450 668 →
**1 483 587**.

### Added — tests

- **Unit** (429 → **437** assertions, 55 → **56** groups): the footprint fits
  the reserve; every entry's payload past `elen` is zero after a rebuild in
  place from truecolor to 16-colour; and, at an unaligned `pos`, the escape,
  the zero scratch to `pos + 24`, and the untouched bytes after it.
- **`scripts/robustness-check.sh` gate 9** (37 → **38** checks): NUL-free input
  gives NUL-free stdout, which a leaked scratch byte would break. It covers the
  filter (short lines, a 70 000-byte line, UTF-8 across the 4096-byte
  boundary), one-shot text, and animation (a 32 KB cluster with its mid-cluster
  re-emit, plus plain lines), in all three modes: 18 runs.
- **Mutation-checked**, each caught:

  | Mutation | Caught by |
  |---|---|
  | no zero-fill in `_phase_esc_init` | 2 unit assertions |
  | a fourth word (32-byte footprint) | unit and fuzz |
  | the old byte loop | unit and fuzz, which now assert the new footprint |
  | returning `pos + 24` (scratch leaks) | the fuzz stream check, and all 18 gate-9 runs |

### Decided — no fixed input corpus in `tests/anuenue.bcyr`

The roadmap left this to the word copy's slot, because it was the first change
whose gate wanted per-call and end-to-end numbers side by side. Running
`perf-bench.sh` next to the `.bcyr` rows supplied both. An in-process corpus
bench would need a stdout sink that `anuenue_filter` does not have, since it
writes fd 1 directly — a test-only seam in the hot path. Moved to the roadmap's
*Explicitly declined*.

### Found — a cyrius miscompile (upstream; worked around)

The new unit group, appended to the end of `tests/anuenue.tcyr`'s `main()`,
made the suite die with SIGSEGV in its *third* group, a cmdit parse, long
before the new code runs. It does so on cyrius 6.7.9, 6.7.10 and 6.7.11, and
the same lines pass in a function of their own, which is where they live now
(`test_word_copy`).

It is not:
- the local count: twelve extra integer locals pass;
- an array local: 40 bytes pass;
- code size: forty extra statements pass.

Not minimized — that is past CLAUDE.md's three-attempt rule — so it is filed in
the roadmap's *Upstream* list with exact reproduction steps. The v1.4.4
closeout's refactor pass now includes splitting `main()` into per-cut
functions.

### Docs

- Roadmap: the v1.4.3 slot removed; the corpus decision and the miscompile
  recorded; the v1.4.4 closeout gains the `main()` split.
- Architecture 001 gains the footprint argument and its call-site table, and
  "what breaks" now covers the word copy. `src/filter.cyr`'s table header and
  `tests/anuenue.bcyr`'s comments carry the new numbers and the decision.

## [1.4.2] — 2026-10-14 (stderr hygiene)

The roadmap's stderr-hygiene slot, both items measured at v1.4.1. **Nothing on
stdout and no exit code changes**: 138 stdout + exit-code comparisons against
v1.4.1 (7 corpora × 18 flag sets, positional text in four modes) plus eleven
help and error invocations, all identical. stderr changes in exactly the two
ways below. The roadmap is renumbered to match: the escape-table word copy is
now v1.4.3, the closeout + P(-1) sweep v1.4.4, and the cyrius 6.7.x move v1.4.5.

### Fixed — every failure printed a blank line after its message

`anuenue_fail` wrote `anuenue: `, then `agnostik_err_print` — which ends its own
line, `<kind>[: <msg>]\n`, and has since agnostik 1.5.1 — then a second `\n`.
So every runtime and validation failure since v1.2.1, when `anuenue_fail` was
wired, printed its line and then an empty one; in a log, one record became two.
Measured on v1.4.0 and v1.4.1 alike: `anuenue --log-level=bogus` stderr ended
`…debug trace\n\n`. The second newline is gone; the `str_new`-OOM fallback,
which prints the bare message, keeps its own.

### Changed — parse-error lines name the token that tripped them

`anuenue: unknown flag` did not say which. Each usage line now carries the argv
token as typed, from cmdit's `cmdit_err_token` (and, for a bad integer given as
its own argv word, `cmdit_err_value`):

```
anuenue: unknown flag: --bogus
anuenue: flag missing value: -p
anuenue: bad integer value: -p abc
anuenue: bad integer value: --freq=abc
anuenue: bundled short flags not supported: -an (use -x -y, not -xy)
anuenue: boolean flags take no value: --no-color=0 (use --flag, not --flag=value)
```

### Security — argv echoed to a terminal is sanitized and bounded

The token is argv — attacker-controlled whenever a wrapper passes untrusted text
as arguments — on its way to the user's terminal, so it is never written raw.
`anuenue_eprint_arg` (`src/observe.cyr`) runs it through darshana's
`tty_sanitize_buf` in UTF-8 mode with no control byte kept: ESC, the rest of C0,
DEL, C1 (raw or as UTF-8) and malformed UTF-8 each become one `?`. Without it,
`anuenue $'--\e]0;owned\a'` would have retitled the terminal from inside an error
message; it now prints `unknown flag: --?]0;owned?`. The echo is capped at 64
bytes (`ANUENUE_ERR_ARG_MAX`), stepped back so the cut does not split a UTF-8
character, with `...` after a cut token. Nothing on the path interprets the
bytes.

This is darshana's sanitizer on the *diagnostic* path only. The filter path's
byte-preservation contract is untouched and its decline stays on the roadmap;
`robustness-check.sh` still asserts all 256 byte values pass through.

### Added — tests

- **Unit** (410 → **429** assertions, 54 → **55** groups): the cut (short,
  long, stepping back over a split 2- and 3-byte character, at most three steps
  on malformed input), the render (ESC, BEL, LF and a 2-byte C1 each one `?`;
  the rest of the sequence inert text), and `anuenue_arg_attached`.
  Mutation-checked: keeping C0 controls fails 2, removing the UTF-8 step-back
  fails 3.
- **`scripts/observe-check.sh` gate 5** (22 → **27** checks): a closed-stdin
  read failure, a bad `--log-level`, a negative `--duration`, a zero
  `--interval` and an unreadable command line (`--nofile=3`) are each exactly
  one stderr line ending in one newline. All five fail on v1.4.1.
- **`scripts/robustness-check.sh` gate 8** (29 → **37** checks): the six lines
  above verbatim, an OSC-0 + BEL + CSI token rendered with no `0x1b` / `0x07`
  byte on stderr, and a 302-byte token echoed as 64 bytes + `...`. The injection
  check is mutation-checked: a build that keeps BEL fails it.

### Performance

The change is on the error path, which runs once and only on a failure. A
rebuilt v1.4.1 binary against v1.4.2, `RUNS=11`, three interleaved rounds per
mode, medians:

| ascii no-LF, ns/byte | v1.4.1 | v1.4.2 | Δ |
|---|---:|---:|---:|
| truecolor (M5 metric) | 47.38 | **47.41** | +0.1% |
| 256 | 34.58 | **34.74** | +0.5% |
| 16 | 23.12 | **23.20** | +0.3% |

Flat — all nine corpus × mode rows within ±1%.

**Binary** 222 520 → **226 624 B** (+4 104), all of it this change: DCE now
keeps darshana's `tty_sanitize_buf` and its UTF-8 validator, which the filter
path never called, plus the four helpers.

### Docs

- Roadmap renumbered (above); the stderr-hygiene slot is removed. The
  "declined: `tty_sanitize_buf`" entry is narrowed to the filter path, and the
  "declined: logging parse errors" entry notes the named token.
- ADR 0004 and `src/observe.cyr`'s header note the darshana dependency (a dep,
  not an anuenue module — architecture 004's rule holds).

## [1.4.1] — 2026-10-14 (cmdit 1.4.0 + agnostik 1.12.0; sakshi to the stdlib)

The dependency refresh to every first-party dep's latest tag, and the repairs
the cmdit move called for. cmdit 1.2.4 → 1.4.0 changed what anuenue's parse can
return, and **four input classes that 1.2.4 parsed clean now fail or behave
differently** — each reproduced on the v1.4.0 binary before it was handled (see
*Changed — behaviour*). The toolchain stays at **cyrius 6.7.9**: every latest
dep tag pins 6.7.9; 6.7.10, the latest tag, brings nothing anuenue needs; and the
release worth taking, 6.7.11, is not tagged yet. It is
[roadmap v1.5.1](docs/development/roadmap.md#v151--cyrius-67x--sakshi-2510-through-the-snapshot)
(filed as v1.4.2; renumbered at v1.4.2, v1.4.5 and v1.5.0).

**stdout is byte-identical to v1.4.0** for every input v1.4.0 handled
correctly: 138 stdout + exit-code comparisons (7 corpora × 18 flag sets,
positional text in four modes), the six goldens, and `--help` / `-h` plus seven
usage and validation errors byte-identical on stderr as well.

### Changed — dependency pins

- **cmdit 1.2.4 → 1.4.0** (`bac07a5`). `cmdit_help_flags` output is
  byte-identical; nothing else anuenue calls changed signature. The bundle's
  `.deps` shrank to `args, alloc, string, io`, all already declared.
- **agnostik 1.6.0 → 1.12.0** (`f03f086`). No change to anything anuenue calls:
  the `agnostik_err_new` / `_code` / `_print` bodies, the `STIK_ERR_*` values
  (`CODE_IO` is still 1010, which `observe-check.sh` greps), and the
  `<kind name>[: <msg>]` stderr line are all as at 1.6.0. 1.6.2 replaced the raw
  `syscall(318, …)` behind the aarch64 build warning the roadmap carried as
  upstream; 1.7.0 put every private helper under `_stik_`, so no vendored name
  can silently replace one of agnostik's (zero collisions with anuenue's names
  either way, checked across all 1 568 top-level names).
- **sakshi: `[deps.sakshi]` dropped; sakshi is a `[deps].stdlib` module.** The
  toolchain snapshot folds a sakshi release, and a git tag that disagreed with it
  was a `./lib/ shadows version-pinned` warning on every build — so the pin could
  only ever restate the snapshot's version (v1.4.0 had to move it 2.5.1 → 2.5.8
  for exactly that reason). Now the `cyrius` pin is the single source of truth.
  Same bytes: `lib/sakshi.cyr` is the 6.7.9 snapshot's 2.5.8, unchanged.
- darshana 1.3.0 is already the latest tag.
- `lib/` re-vendored from scratch (`rm -rf lib cyrius.lock && cyrius lib sync
  --full && cyrius deps`); `cyrius.lock` now commit-pins three git deps, not four.
- **`dist/anuenue.deps` is gone.** Its one leaf, `boxed`, was cyrius's
  misattribution of agnostik's need to anuenue's bundle (`src/hsv.cyr` calls
  nothing). agnostik 1.12.0's sidecar names `boxed` itself, so the verify now
  credits it to agnostik and `dist/anuenue.cyr` has no requires block. The cyrius
  bug is still open upstream; it simply no longer reaches this bundle.

### Changed — behaviour (four inputs cmdit 1.2.4 parsed clean)

All four were silent at exit 0 on v1.4.0. Each is now either refused loudly or
honoured, and `scripts/robustness-check.sh` gate 7 asserts the new behaviour.

- **A boolean given `=value` is a usage error.** cmdit 1.2.4 stored 1 and ignored
  the value, so **`--no-color=0` disabled colour** — the opposite of what was
  typed — and `--animate=1`, `--force-color=`, `--help=x` and `--version=x` all
  parsed as the bare flag. Now exit **2**, nothing on stdout,
  `anuenue: boolean flags take no value (use --flag, not --flag=value)` plus
  usage. **Migration:** drop the `=value`. No documented form ever used one, and
  the accepted meaning was the defect, so this ships in a patch — the precedent
  is recorded in [roadmap § v2.0](docs/development/roadmap.md#v20--reserved).
- **A command line over 2 MiB is a runtime failure.** stdlib `args_init` reads
  `/proc/self/cmdline` once into a fixed 2 MiB buffer, and an unprivileged
  `ulimit -s unlimited` raises ARG_MAX past it. v1.4.0 parsed the prefix: 24 ×
  100 KB of text then `--seed 99` exited 0 having rendered 35 MB of positional
  text and dropped `--seed 99`. Now exit **1**, `anuenue: i/o error: could not
  read the full command line`, no usage dump — it is not something the user
  typed wrong. The stdlib cut itself is filed upstream (cyrius,
  2026-10-14).
- **An unreadable command line is the same failure.** Under `prlimit
  --nofile=3` `args_init` cannot open `/proc/self/cmdline` and `argc()` is 0.
  v1.4.0 parsed that as an empty argv: `--color=none --log-level=debug` were both
  dropped and the default path ran (the hazard
  [architecture 006](docs/architecture/006-argv-costs-a-file-descriptor.md)
  documented). Now exit 1 with the message above. 006 is updated.
- **One-shot TEXT mode keeps every positional.** cmdit 1.2.4 stopped storing at
  128 and reported nothing: `anuenue $(seq 1 200)` printed 1–128. 1.4.0 grows the
  array; all 200 render.

And one state that is new but unreachable from outside: **cmdit_new's OOM** is a
0 handle, which 1.2.4 dereferenced and 1.4.0 fails closed on as
`CMDIT_ERR_NOMEM`. anuenue reports it as `resource exhausted: out of memory
parsing the command line` at exit 1. ⚠ **Unproven**: `alloc_init`'s first chunk
always holds the handle (the 16 MiB small-board fallback included), and no
`prlimit --as` value between "`alloc_init` fails" and "everything fits" exists
to drive it. The 0-handle contract it rests on is pinned in the unit suite; a
fault-injection probe is filed under
roadmap v1.4.4 (filed as v1.4.5; renumbered at v1.4.2) — which proved it:
[v1.4.x audit delta](docs/audit/2026-10-14-v14x-delta.md).

### Fixed — `src/main.cyr`'s parse-error switch

- **NOMEM and ARGV** go through `anuenue_fail` as runtime failures (exit 1,
  `STIK_ERR_RESOURCE_EXHAUSTED` / `STIK_ERR_IO`). With the dep bump alone, both
  reached the generic `argument parse error` line plus usage at exit 2 (measured
  for ARGV) — a usage error for a state the user did not cause.
- **UNEXPECTED_VALUE** gets its own line, as BUNDLED does.
- **The if/else chain is now a flat lookup.** It would have been five levels
  deep; the codes are disjoint, so each is one `if`. The roadmap's "declined:
  flatten the `} } } }` chains" entry now covers only `src/filter.cyr`'s.

### Fixed — `fuzz/flag-parser.fcyr`

- **A stack overrun in the harness.** `var solo_tokens[44]` is 44 **bytes** (a
  local `var x[N]` is N bytes) under a comment reading "11 flags × 4 patterns",
  and the code stored 11 eight-byte pointers into it — 44 bytes past the end. Now
  `solo_tokens[112]` for 14 tokens. Harness-only; nothing shipped was affected.
- **The flag set had stopped at v0.7.0** — no `-i` / `--interval`, `-v` /
  `--verbose` or `--log-level`, though the header said it mirrored the live set.
  Added, to both the random pool and the solo walk.
- **The error-code invariant was a range check** (`NONE ..
  TOO_MANY_POSITIONAL`) that cmdit's append-only taxonomy had already outgrown.
  It is now a set check: every code that comes back must be one `src/main.cyr`
  names. A new group asserts every boolean given `=value` — including the auto
  `--help` / `--version` — is `UNEXPECTED_VALUE`.

### Added — tests

- **Unit** (402 → **410** assertions, 53 → **54** groups): `--no-color=0` is
  `UNEXPECTED_VALUE` and leaves the flag unset; `cmdit_parse(0)` /
  `cmdit_error(0)` are `RESULT_ERR` / `NOMEM` (the NOMEM branch's contract); the
  three new codes' values, so a renumbering fails here before it misroutes.
- **`scripts/robustness-check.sh` gate 7** (21 → **29** checks): four booleans
  given a value, 200 positionals, a 2.4 MB command line (with a 1.0 MB control
  that must still parse — skipped if the stack hard limit forbids raising it),
  and `--nofile=3`. Against the v1.4.0 binary, all seven defect checks fail and
  the control passes.
- **Fuzz** 1 450 672 → **1 450 668** assertions: `flag-parser` 144 → 140 (the
  range check's two asserts per call became one set check, −30; three more solo
  flags, +6; ten booleans with values, +20).

### Performance

The per-cluster path is unchanged, so the ratchet measures the dep moves. A
rebuilt v1.4.0 binary against v1.4.1, `RUNS=11`, three interleaved rounds per
mode, medians:

| ascii no-LF, ns/byte | v1.4.0 | v1.4.1 | Δ |
|---|---:|---:|---:|
| truecolor (M5 metric) | 46.68 | **46.74** | +0.1% |
| 256 | 34.33 | **34.52** | +0.6% |
| 16 | 23.22 | **23.56** | +1.5% |

Flat — all nine corpus × mode rows are within ±2% with mixed signs; full table in
[`docs/benchmarks.md`](docs/benchmarks.md) § v1.4.1.

**Binary** 210 696 → **222 520 B** (+11 824): cmdit +9 240 (its bundle grew
1 638 → 2 800 lines), agnostik +2 480, sakshi-as-stdlib 0, anuenue +104. Non-DCE
980 280 B.

### Docs

- **[`roadmap.md`](docs/development/roadmap.md) is forward-facing only.** The
  completed v1.3.0–v1.4.0 slots, the shipped index and the eight closed v1.0
  scorecard items are removed — their history is this file. Every remaining item
  is pinned to a release: v1.4.2 (cyrius 6.7.11 + sakshi 2.5.10 through the
  snapshot, −60 144 B measured in a trial), v1.4.3 (stderr hygiene), v1.4.4 (the
  escape-table word copy), v1.4.5 (the arc's closeout and P(-1) sweep), v1.5.0
  (adoption), v1.6.0 (the pipe-decorator family), and one trigger-gated v1.x item.
  Two items are new from this cut's measurements: every `anuenue_fail` line ends
  in a blank line (`agnostik_err_print` already writes the newline; on v1.4.0
  too), and parse-error lines could name the offending token via cmdit 1.3's
  `cmdit_err_token`.
- **Upstream items**: the agnostik aarch64 warning and the distlib `boxed`
  credit are gone (above). cmdit's negate-MIN refusal is unchanged in 1.4.0 and
  untracked upstream. Two are new: the stdlib `args_init` 2 MiB cut, and
  darshana's `tty_winsize` undefined on non-Linux targets in `cyrius distlib`'s
  verify (a warning, present at v1.4.0 too; none is an anuenue target).
- `CLAUDE.md`'s dependency map gains the cmdit row it never had and records
  sakshi as a stdlib module; README, both guides and architecture 006 updated.

## [1.4.0] — 2026-10-12 (cyrius 6.7.9 + darshana 1.3.0)

The cyrius 6.7 language minor and darshana's 1.2.0 / 1.3.0 additions, plus the
items darshana's consumer survey (2026-10-12) filed in
[`roadmap.md`](docs/development/roadmap.md). The survey's findings were "confirmed
by reading the source; not yet reproduced by running it" — every one was
reproduced on the v1.3.6 code before it was fixed. Audit delta:
[`docs/audit/2026-10-12-v140-delta.md`](docs/audit/2026-10-12-v140-delta.md) — 1 LOW +
3 INFO, all fixed, zero HIGH+ open.

**stdout is byte-identical to v1.3.6**: 276 stdout + exit-code comparisons
(16 corpora × 16 flag sets, positional text, help and usage errors with stderr),
the six goldens, and full animation streams in all three colour modes. What
changed that a user can see is listed under *Behaviour*.

### Changed — toolchain + dependency pins

- **cyrius 6.6.2 → 6.7.9** (`CYRIUS_DCE=1 cyrius build -v` reports
  `compiler: …/versions/6.7.9/bin/cycc`). `lib/` re-vendored from scratch —
  `rm -rf lib cyrius.lock && cyrius lib sync --full && cyrius deps` — so files the
  6.7.9 snapshot no longer ships are gone (`base64`, `bigint`, `csv`, `cyml`,
  `json`, `linalg`, `matrix`, `toml`, `u128`; nothing in anuenue included them)
  and three new ones arrive (`alloc_cx`, `poison`, `tls_hostid`). This supersedes
  a never-committed 2026-09-26 `cyrius deps` output that had been sitting in the
  working tree (see the `path` note below for what it contained).
- **darshana 1.1.1 → 1.3.0, and `path = "../darshana"` dropped.** 1.3.0 is what
  forced the toolchain move: its bundle declares private constants with `const`
  (cyrius 6.7.2), and under the 6.6.2 pin it fails with `expected '=', got
  identifier` (re-checked here against 6.6.2). The `path` made `cyrius deps`
  vendor darshana's working tree rather than the tag — the 2026-09-26 output held
  darshana **1.1.2**, cmdit **1.2.5** and agnostik **1.6.4** under tags 1.1.1,
  1.2.4 and 1.6.0. From cyrius 6.7.6 a `path` beside `git` + `tag` is only a
  `CYRIUS_LOCAL` dev override and the tag builds by default; darshana's entry is
  removed outright, and cmdit / sakshi / agnostik keep theirs as overrides.
- **sakshi 2.5.1 → 2.5.8, because the toolchain moved.** The 6.7.9 stdlib
  snapshot ships sakshi 2.5.8, and a `[deps.sakshi]` tag that disagrees with it is
  a build-time `./lib/ shadows version-pinned … sakshi 2.5.1 (pinned: 2.5.8)`
  warning on every build. 2.5.8 is the one tag that clears it; no API change.
- cmdit 1.2.4 and agnostik 1.6.0 unchanged — the move required neither.

**Language-bump repairs: none were needed in anuenue's own source.** It
compiled with zero errors and zero warnings for x86_64 at the first 6.7.9 build.
Checked rather than assumed: no identifier spelled `const` / `true` / `false` /
`do` / `dyn` / `trait` / `loop`, no `!` other than `!=`, no compound assignment,
no typed narrow pointer, no unary `-` / `~` on a constant. What the move *did*
surface was outside the compiler:

- **`dist/` was stale under 6.7.9.** `cyrius distlib --check` failed — the
  bundle predated 6.6.18's compile-verified requires block. Regenerated with
  `cyrius distlib --all`. The sidecar shrank from the eleven `[deps].stdlib`
  leaves (the pre-6.6.18 leak) to one, `boxed` — which is itself a cyrius
  misattribution, not a need of `src/hsv.cyr` (see the audit delta's *Upstream*).
- **cyrius 6.6.20 fixed `sleep_ms`'s int32 truncation**, which
  `ANUENUE_MAX_INTERVAL_MS`, `--interval`'s warning and
  [architecture 005](docs/architecture/005-timing-primitives-truncate.md) all
  described as current. Re-measured on 6.7.9 and documented as history; the
  one-hour clamp stays as behaviour.
- **`cyrius audit` was failing fmt and docs** — already under 6.6.2, so not new,
  but this is a minor cut and CLAUDE.md's P(-1) step 1 wants it clean. Four
  test/fuzz files run through `cyrius fmt` (its changes are whitespace only) and 18
  test/fuzz functions given docstrings. Now clean on all five stages.

### Fixed — the exit signalfd is darshana's (G-01 LOW, G-02 / G-03 INFO)

`src/animate.cyr`'s `_open_exit_signalfd` hand-rolled `sigprocmask` + `signalfd`
with a private `ANUENUE_SFD_NONBLOCK`, because darshana's `tty_open_signalfd`
returns a blocking fd. Both survey defects reproduced on v1.3.6 with a probe that
pre-blocks SIGHUP and forces `signalfd(2)` to fail under `prlimit --nofile=3`:

- **G-01** — the failure rollback unblocked the **whole** mask, so a signal
  blocked before animation started came back unblocked (`hup_blocked=0`). The
  v1.0.2-class defect darshana fixed in its own open.
- **G-02** — no `SFD_CLOEXEC` (`cloexec=0`). Latent: anuenue never execs.

Now `tty_open_signalfd(TTY_SIGMASK_EXIT)` plus the stdlib's `fd_set_nonblocking`
(the route darshana documents), `tty_read_signal` for the per-slice probe, and —
**G-03**, the 2026-05-22 audit's INFO 8 + 9 — a matching close:
`_close_exit_signalfd` runs as the LAST step of every exit from the frame loop,
after the SGR reset, cursor show and final newline (darshana's teardown order),
and unblocks only the bits the open added, so the mask anuenue leaves is the mask
it inherited.

Closing introduced a hazard of its own, found by mutation and closed in-cut: the
unblock delivers any signal still pending, and the frame loop reads one per
probe. With SIGINT and SIGTERM both pending, a close without a drain turned the
documented exit 0 into death by SIGTERM — **exit 143, 3 of 3 runs**. The close
drains first (bounded at `ANUENUE_SIG_DRAIN_MAX = 8`); v1.3.6 and v1.4.0 both
exit 0, 3 of 3.

⚠ **One branch is unproven**: if `fd_set_nonblocking` failed, the open gives the
fd back and unblocks what it added (a blocking fd would freeze the frame loop).
`F_GETFL` / `F_SETFL` on a signalfd the process just opened has no failure a
test can provoke, so nothing reaches it; the rollback it calls is the one the
close tests cover.

On AGNOS the gate stays: the stdlib's agnos `fd_set_nonblocking` answers
-ENOSYS, so the non-blocking fd cannot be made there. The comment saying the gate
also dodged a "Linux-gated TTY_SIGMASK_EXIT" was wrong — darshana has had the
AGNOS mask and open since 0.9.0 — and is corrected.

### Behaviour

- **Animation's syscall surface grows by two calls**: `fcntl` (F_GETFL + F_SETFL,
  inside `fd_set_nonblocking`) and `close` at teardown. A seccomp allowlist for
  `anuenue -a` needs both. The filter, passthrough and positional-text paths are
  unchanged. [`integrating-anuenue.md`](docs/guides/integrating-anuenue.md)'s
  list is corrected — it also still said `nanosleep`, which `sleep_ms` stopped
  using at cyrius 6.0.65 (it is `poll`), and omitted `clock_gettime`.
- **After animation the signal mask is restored** instead of left blocked until
  exit. Not observable from outside (the process exits immediately), but it is
  why the drain above exists.
- **`--log-level=warn` wording**: `--interval clamped; sleep_ms truncates to a
  32-bit int above this` → `--interval clamped to one hour per frame` (G-04 — the
  stated cause stopped being true at cyrius 6.6.20). stderr only.
- **The `-v` warning for a failed signalfd** carries `open=tty_open_signalfd
  failed` instead of an errno: darshana normalises the failure to -1. A failed
  `fd_set_nonblocking` gets its own warning, with the errno.

### Kept — the phase-cached escape table, re-measured

The survey asked whether the M5 table now costs more than it saves, since
darshana 1.2.0 made the composers 35–49% faster. Measured in anuenue's own
harnesses — `tests/anuenue.bcyr` gains a table-vs-composer pair per colour mode,
and `scripts/perf-bench.sh` gains `COLOR=256|16`, without which it could only
ever have measured the mode where deleting the table wins:

| ns per escape (`anuenue.bcyr`) | table | hsv_rainbow + composer |
|---|---:|---:|
| truecolor | 43–45 | **31–33** |
| 256 | **30–31** | 37–38 |
| 16 | **18** | 24 |

| ascii no-LF, ns/byte (`perf-bench.sh`, `RUNS=11`, ×2 interleaved) | table | no table | Δ |
|---|---:|---:|---:|
| truecolor | 49.6 | 41.9 | −15% |
| 256 | 36.1 | 48.0 | **+33%** |
| 16 | 24.2 | 34.5 | **+42%** |

Deleting it would be a net regression, so it stays. The numbers do locate its
cost: the byte-at-a-time copy, not the lookup — a three-word copy of the same
entry measured 9–10 ns in every mode. That copy writes past the escape's length,
which changes `_emit_phase_esc`'s write footprint and what
`fuzz/emit-phase-esc.fcyr` asserts, so it is filed in the roadmap as its own
item rather than slipped into a measurement. Also corrected: the "≈ 10 ns/call"
figure for the table that `filter.cyr` and `docs/benchmarks.md` carried since
v0.6.0 is not what the loop costs — 41–43 ns measured under cyrius 6.6.2.

### Performance

The per-cluster hot path is unchanged, so the release ratchet measures the
toolchain and darshana moves. A rebuilt v1.3.6 binary against v1.4.0,
`RUNS=11`, three interleaved rounds per mode, medians, on a host shared with
other build jobs (load average ~5.4):

| ascii no-LF, ns/byte | v1.3.6 | v1.4.0 | Δ |
|---|---:|---:|---:|
| truecolor (M5 metric) | 48.53 | **48.56** | +0.1% |
| 256 | 37.17 | **36.32** | −2.3% (noisy) |
| 16 | 24.68 | **24.84** | +0.6% |

Flat. All corpora are in [`docs/benchmarks.md`](docs/benchmarks.md) § v1.4.0;
the shared host puts both binaries ~2 ns/byte above the idle-host v1.3.x rows,
so compare the pair, not the trend. darshana 1.3.0's composer is faster
(`tty_fg_rgb_buf` 37 → 23 ns), but since M5 it runs only while the escape table
is built.

**Binary** 204 312 → **210 696 B** (+6 384): toolchain +6 040, sakshi −32,
darshana +280, anuenue +96. (v1.3.6's 204 312 B, down from v1.3.5's 814 488,
is cyrius 6.6.x compacting DCE'd code again — recorded at this cut because
v1.3.6 did not.)

### Changed — stale comments about darshana (survey)

- `src/filter.cyr` blamed darshana's `_ansi_emit_u8` divides for the composer's
  cost; darshana deleted `_ansi_emit_u8` at 1.1.0 (and measured reciprocal
  multiplication slower). Rewritten around the v1.4.0 measurement.
- `src/color.cyr` called `tty_isatty` "darshana Linux-only"; it has had an AGNOS
  peer since darshana 0.8.2. The skip on AGNOS stays, for the reason that arm
  documents: it reports whether the framebuffer console is up and ignores `fd`.

### Added — tests

- **Unit** (384 → **402** assertions, 52 → **53** groups): the darshana signalfd
  group — fd flags read back with `fcntl` (CLOEXEC, O_NONBLOCK), a real SIGINT
  reported and consumed, SIGINT + SIGTERM pending across the close (without the
  drain the test process is killed), the mask restored, and a pre-blocked SIGHUP
  left blocked. Mutation-checked: dropping the drain kills the run (signal 2);
  dropping `& ~prev` fails 3 assertions. The two `ANUENUE_SFD_NONBLOCK`
  assertions go with the constant.
- **`scripts/signal-check.sh`** 12 → **18** checks: CLOEXEC and non-blocking on
  the success path, the close giving back exactly what the open took, a
  pre-blocked SIGHUP surviving a forced failure (the G-01 shape — a scratch
  build of the same probe against the v1.3.6 code reported it unblocked), and
  gate 5 — two exit signals at once exit 0 (fails without the drain, 3 of 3).
  `tests/probes/sigmask-probe.cyr` reports a `plain` and a `preblocked` case.

## [1.3.6] — 2026-09-10

Ecosystem migration onto the cyrius **6.6.2** repair release.

### Changed — toolchain + dependency pins

- `cyrius` pin **6.5.35 → 6.6.2**. 6.6.0 flipped `Result`/`Option`/`Either`
  declared `: stack` to a two-register value form and deleted the boxed
  accessors; 6.6.2 restores them under their own names in `lib/boxed.cyr`
  (`boxed_new` / `boxed_tag` / `boxed_payload` / `boxed_is`, with
  `tagged_new` keeping its name because its meaning never changed) and
  ships nine further repairs, including a SIMD operand-slot Critical and a
  `map_u64` sentinel-key bug.
- `darshana` 1.0.0 → **1.1.1**
- `sakshi` 2.4.11 → **2.5.1**
- `agnostik` 1.5.1 → **1.6.0**
- `cmdit` 1.2.4 (already current)

anuenue's own sources needed **no** migration edits: the repo has zero calls
to the retired `payload()` / `tag()` / `is_tag()` spellings. The one apparent
hit in an earlier survey (`src/filter.cyr:41`) is the English word "payload"
inside a comment.

### Removed — a stale vendored bundle nothing included

- `lib/agnosys.cyr` — a 335 KB `cyrius distlib` bundle of **agnosys 1.4.3**,
  vendored 2026-06-19, with no `include` anywhere in the repo and no
  `[deps.agnosys]` entry to regenerate it. It was the only file in the tree
  still calling the retired accessors (32 sites). An orphaned bundle is not
  inert: it is exactly what a blanket `--allow-undef` scan would have waved
  through, so it is deleted rather than migrated.


## [1.3.5] — 2026-08-26 (stdin failure surface)

The surface the v1.3.3 sweep ranked highest after the allocation probe, and the
**mirror of E-01**: three audits had examined stdin exhaustively for *content*
and never for *failure*.

It had the mirror defect.

### Fixed — F-01 (MEDIUM): a non-blocking stdin was treated as a broken stream

`lib/io.cyr`'s `file_read` is a bare `sys_read`, and all three stdin call sites
— filter, MONO passthrough, animation slurp — classed **any** negative return as
fatal:

```
if (n < 0) { return anuenue_fail(STIK_ERR_IO, "read from stdin failed"); }
```

But `EAGAIN` on a non-blocking stdin means "no data **yet**", not "broken". A
writer merely slower than the reader triggers it.

Measured before the fix, feeding 6 500 bytes through a non-blocking pipe in
64-byte chunks:

| Path | Rendered | Exit |
|---|---:|---:|
| filter (`--color=24bit`) | **64 / 6 500** | **1** |
| passthrough (`--color=none`) | **64 / 6 500** | **1** |
| animation slurp (`-a`) | — | **1** |

anuenue read one chunk, hit EAGAIN, declared the stream broken and quit —
discarding 99% of a perfectly good input and reporting an I/O error that had not
happened.

**Why MEDIUM and not HIGH, unlike E-01.** The data loss is comparable, but this
one is *loud*: it exits 1 and says so, and a script can detect it. E-01 was
silent with exit 0, which is what put it a severity higher. Both are ordinary
configurations rather than adversarial ones.

**Fix** — `anuenue_read_some` in `src/observe.cyr`, deliberately symmetric to
`anuenue_write_all`: returns the byte count, 0 on clean EOF, `-1` on a real
error, and retries the two transient errnos. EAGAIN sleeps 1 ms and retries with
no attempt cap — a slow writer deserves to be waited for, and a writer that is
*gone* closes the pipe, which is EOF, not EAGAIN. **The two sides of a filter
should not disagree about what counts as an error.**

Verified: all three paths now render 6 500/6 500 at exit 0, and a *real* read
failure (closed stdin) still exits 1 with the message — so the retry narrowed
the error class rather than swallowing it.

⚠ **The EINTR branch is unproven**, in the cmdit 1.2.4 sense. anuenue installs
no signal handlers, and signals at their default disposition do not interrupt a
blocking read — verified by driving SIGSTOP, SIGCONT, SIGWINCH, SIGCHLD and
SIGURG at a process blocked in `read`, none of which produced EINTR. It is one
comparison, it matches the write side, and a consumer that execs anuenue with an
inherited handler would reach it. Recorded rather than implied.

### Fixed — the lint gate, and the reason it did not catch this

CI failed on lint after the F-01 work:

```
deferral line 201: untracked 'not yet'
```

The comment read `mean "not yet", not "broken"` — descriptive prose, not a
deferral. Same false-positive class as the v1.2.2 `# detect not yet run` hit,
and reworded the same way rather than suppressed.

**The gate that should have caught it locally reported success**, and that is
the part worth fixing. `cyrius audit`'s lint section prints `ok: lint clean`
**without counting untracked deferrals**; `cyrius lint <file>` counts them and
reports them on their own line. A local gate built on `cyrius audit` therefore
passes a tree CI rejects. Mine was.

That is the second time in two cuts that a local check passed for a reason
unrelated to what CI enforces — E-03 was the first, where the local test ran a
SIGPIPE disposition in which the code under test could not execute. Different
mechanism, same shape: **the check was green, and it was green about something
else.**

- **`scripts/lint-check.sh`** — the lint gate as one implementation, called by
  both the local gate and CI, so they cannot drift again. Requires *both*
  counters at zero per file. Mutation-tested: reintroducing the reworded comment
  fails it.

- **It lints `tests/` and `fuzz/` too**, which the CI step never did. Sweeping
  them immediately turned up an untracked deferral in `tests/anuenue.bcyr` that
  had been sitting unflagged: the cross-reference it needed was on the line
  *after* the keyword, and the heuristic reads one line. Fixed by moving the
  reference onto the same line — the deferral itself was correctly tracked all
  along, just not in a form the linter could see.

### Added

- **`scripts/robustness-check.sh` gate 6** — all three read paths driven from a
  real `O_NONBLOCK` pipe with a deliberately slow writer, plus the closed-stdin
  control. Runs through python because `sh` cannot set `O_NONBLOCK` on a
  descriptor.

  Mutation-proven: removing the EAGAIN retry fails all three path checks
  (64/6500 each) while the closed-stdin control still passes — so the gate
  distinguishes "retries transient errors" from "ignores errors", which a
  weaker test would not.

  No unit coverage for this one, deliberately: `anuenue_read_some` needs a real
  descriptor in a known state, and a process-level gate driving an actual
  non-blocking pipe is stronger evidence than anything reachable from `.tcyr`.

### Performance

Every `read(2)` now goes through a wrapper — roughly one extra call per 4 KiB,
not per byte. Back-to-back, `RUNS=11`, pre-fix binary rebuilt from HEAD:

| Corpus | v1.3.4 | v1.3.5 | Δ |
|---|---:|---:|---:|
| ascii (no LF) | 46.64 ns/byte | 46.90 ns/byte | +0.6% |
| ascii (w/ LFs) | 51.19 ns/byte | 50.92 ns/byte | −0.5% |
| utf8 mixed | 41.68 ns/byte | 41.76 ns/byte | +0.2% |

Mixed signs across corpora — noise, not a cost. Binary unchanged at
**814 488 B**. All six goldens byte-identical.


## [1.3.4] — 2026-08-26 (allocation-failure probe + CI fix)

### Fixed — E-03 (CI regression from v1.3.3)

**CI failed on v1.3.3, and the bug was in the v1.3.3 fix.**

```
FAIL: a truncated downstream produced stderr output:
      anuenue: i/o error: write to stdout failed
```

E-01 (v1.3.3) made every stdout write checked, and classed **EPIPE as fatal**.
That is wrong: EPIPE means the consumer closed the pipe — `anuenue | head -1` —
which is the normal end of a pipeline, not a failure.

**Why it passed locally and failed in CI.** SIGPIPE's disposition is inherited.
Under the default disposition the kernel kills the process before `write(2)`
returns, so the EPIPE branch never executes and the pipeline is silent — which
is what I observed and asserted on. A CI runner sets SIGPIPE to `SIG_IGN` and
children inherit it; there `write(2)` returns `-EPIPE`, the branch runs, and
anuenue printed an error and exited 1 for a routine truncated pipeline.

So the v1.3.3 audit's claim that this case was "verified" rested on a
configuration in which **the code under test never ran**. CI executed that branch
for the first time.

**Fix** — `anuenue_write_all` records EPIPE in `ANUENUE_STDOUT_EPIPE`, and
`anuenue_write_failed` dispatches on it: EPIPE exits **0 in silence**, matching
what the process does under the default disposition; every other errno still
reports and exits 1. Two functions changed, no call-site changes — all 17 sites
already routed through the reporter.

Verified in both configurations, and that `> /dev/full` **still** exits 1 with a
message under SIGPIPE-ignored, so E-01's actual defect stays fixed.

### Fixed — the gate that should have caught it

`scripts/robustness-check.sh`'s EPIPE check was wrong in two independent ways,
either of which alone would have hidden E-03:

1. **It only ran the default disposition** — the one where the branch under test
   is unreachable. It now runs both, using `trap '' PIPE` to reproduce the CI
   environment in plain shell.
2. **It used a 256-byte corpus.** That fits entirely in a 64 KiB pipe buffer, so
   whether a second write happened at all — and therefore whether EPIPE was ever
   seen — was a race between anuenue finishing and `head` exiting. The corpus is
   now large enough to guarantee many writes after the reader is gone.

Mutation-proven, and the proof is pointed: deleting the EPIPE dispatch leaves the
**SIGPIPE-default row still passing** and fails only the SIGPIPE-ignored row.
That is precisely why the old gate missed it.

Plus 4 unit assertions (380 → **384**) pinning the dispatch itself.

### Added — allocation-failure probe

Closes the standing **"unproven guard"** gap — the item the v1.3.3 sweep ranked
first among unaudited surfaces.

Three audits in a row recorded findings they could not test:

| Finding | Guard | Status before this cut |
|---|---|---|
| A-01 (v1.2.2) | `_cp_ext_init`'s `alloc` check | correct by inspection, tested by nothing |
| E-01 (v1.3.3) | `anuenue_fail`'s own `str_new` fallback | same |
| — | the other eight guarded `alloc` call sites | same |

All for one reason: **nothing could drive `alloc` to return 0 from outside the
process**, so deleting any of those guards left the whole suite green. A guard
with no failing test behind it is a comment that happens to compile.

- **`tests/probes/allocfail-probe.cyr` + `scripts/allocfail-check.sh`** — 15
  checks against a genuinely exhausted heap, wired into CI, skip-clean without
  `prlimit(1)`.

  **The mechanism.** `lib/alloc.cyr` bump-allocates over 256 MiB mmap'd chunks
  and returns 0 only when a fresh chunk cannot be mapped. That needs two things
  at once: the *first* chunk must succeed — `alloc_init` calls `exit(1)` if it
  fails, taking the whole process before any guard runs — and the *second* must
  fail. `prlimit --as=400MiB` is exactly that window: one chunk's headroom over
  `_LINUX_CHUNK`. The probe then drains the first chunk, after which every
  allocation in the process returns 0, however small.

  **Mutation-proven, and the result is stronger than usual.** Deleting A-01's
  guard or E-01's `str_new` fallback does not make the probe fail an assertion —
  it makes the probe **segfault (exit 139)**. That is the correct signature: the
  guards are the only thing between a starved process and a null-pointer write,
  and the gate script names that case explicitly when it sees it.

  What is now tested rather than asserted:

  - `_cp_ext_init` reports failure instead of writing 42 words through null, and
    `cp_is_extending` degrades to "not extending" — so **output stays
    byte-correct** under memory pressure and only cluster grouping suffers,
    which is the documented trade.
  - `_phase_esc_init` reports failure and leaves its table null.
  - `anuenue_fail` still returns the right exit code (1 / 2 by kind) with **no
    heap at all**, falling back to a bare stderr write when it cannot build the
    agnostik `Str`. A reporter that allocated could never report an OOM.
  - All four driver entry points — filter, render-bytes, passthrough, animate —
    fail at the allocation and return exit 1 rather than proceeding with a null
    buffer.

  **The probe may not allocate after the drain, even to report.** Its output
  goes through `strlen` + `write`, and the first draft got this wrong in an
  instructive way: it passed hardcoded byte counts to `syscall(1, 1, ...)` and
  truncated its own section headers mid-word, because the banners contain
  em-dashes and an em-dash is three UTF-8 bytes. That is precisely the mistake
  `_eprint`'s docstring in `src/observe.cyr` was written to prevent. Fixed with
  a local `pout` that uses `strlen`, and the reason is recorded in the probe.

### Notes

`tests/probes/` now holds two standalone probes, and they exist for the same
structural reason: **anuenue's CLI cannot be driven under a resource limit at
all**, because `args_init()` reads `/proc/self/cmdline` and a constrained
process never parses a flag ([architecture note 006](docs/architecture/006-argv-costs-a-file-descriptor.md)).
Anything that needs to test behaviour under `prlimit` needs a binary that
hard-codes its inputs. That is now a pattern rather than a one-off.

No source change: this cut is test infrastructure only. Binary unchanged at
**814 480 B**.


## [1.3.3] — 2026-08-26 (P-1 audit sweep)

Full P(-1) sweep. **2 findings — 1 HIGH, 1 INFO — both fixed in-cut, zero HIGH+
open.** Report: [`docs/audit/2026-08-26-audit.md`](docs/audit/2026-08-26-audit.md).

**The HIGH is the first since the v0.8.0 M8 audit, and it had shipped in every
release since v0.2.0.** Three prior audits missed it because all three worked
the *input* side — malformed UTF-8, chunk boundaries, argv extremes, signals,
terminal detection. This sweep opened by asking what no audit had ever looked at,
and the answer was the **output** side: nobody had asked what happens when the
write fails.

### Fixed

- **E-01 (HIGH) — every stdout write was unchecked; a failed write lost the
  stream and reported success.** `lib/io.cyr`'s `file_write` is a bare
  `sys_write` with no short-write loop, and anuenue discarded its return at all
  **17** call sites plus two raw `syscall(1, 1, ...)` writes.

  Two independent, measured consequences, both **exiting 0**:

  | Scenario | Output lost | Exit code | `cat` |
  |---|---:|---:|---|
  | `anuenue < in > /dev/full` (ENOSPC) | **100%** | **0** | exits 1, says why |
  | `anuenue < in >` non-blocking pipe, slow reader | **99.3%** | **0** | writes everything |

  The second is the sharper one and is not contrived: any consumer that sets
  `O_NONBLOCK` on the pipe it hands anuenue gets a partial write on the first
  flush that fills the buffer, and anuenue drops the remainder and moves on.
  Measured 1 000 000 bytes in, **7 290 out**, exit 0.

  anuenue's entire contract is byte preservation — colour the stream without
  altering it. Losing the stream while reporting success is the worst available
  failure mode for that contract, it is silent on every descriptor, and the
  triggers are ordinary (a full filesystem, a quota, a non-blocking consumer)
  rather than adversarial.

  Fixed with `anuenue_write_all` in `src/observe.cyr` — loops until every byte
  lands, returns `-1` on failure, and every call site now exits 1 with
  `anuenue: i/o error: write to stdout failed`. EINTR retries immediately;
  EAGAIN sleeps 1 ms and retries, with **no attempt cap on purpose**: a consumer
  that is alive but slow deserves backpressure, and one that is *gone* yields
  EPIPE, which exits.

  **`anuenue | head -1` still behaves as SIGPIPE** (exit 141, clean stderr) —
  the default disposition kills the process before `write` returns, so the new
  error path is never reached. Asserted, so a future change to signal handling
  cannot quietly turn a normal truncated pipeline into an error.

- **E-02 (INFO) — the escape-table cache was keyed on "built", not on which mode
  built it.** The 1 530-entry phase→escape table is mode-specific, but the guard
  was `if (_PHASE_ESC_TABLE != 0) { return 0; }`, so a call after
  `ANUENUE_COLOR_MODE` changed returned the stale table and every character
  rendered in the previous mode.

  Not reachable in the shipped binary — `main.cyr` resolves the mode before
  dispatching. It is recorded as a finding rather than a note because **it caught
  this audit's own probe**: measuring per-mode escape lengths required zeroing
  the table by hand, and the first run reported identical lengths for all three
  modes. A cache that requires callers to know its internals is the wrong shape,
  and the next caller will not have an audit watching. Now keyed on the mode;
  same-mode calls stay idempotent, a changed mode rebuilds in place.

- **`docs/architecture/001` asserted a byte count it had not measured.** It
  claimed the longest emitted escape is 19 bytes
  (`\e[38;2;255;255;255m`). That is the worst case for the *format*, not for
  anuenue: `hsv_rainbow` runs the cube edges at S=V=1, so one channel is always
  0 and the widest real form is `\e[38;2;255;254;0m` = **17 bytes**. Measured
  maxima: 16-colour **5**, 256 **11**, truecolor **17**, against a 24-byte
  budget. The bound held either way, but a note in `docs/architecture/` whose
  numbers are derived rather than observed is the kind that directory exists to
  replace.

### Added

- **`scripts/robustness-check.sh` gate 5** — every colour mode, the animation
  path and the positional-text path each write to `/dev/full` and must exit 1
  with the message; plus the EPIPE case.
- **16 new unit assertions** (364 → 380) over the mode-keyed cache and the
  escape-length budget. The budget check scans all 1 530 entries per mode but
  asserts on the **aggregate** min/max — a per-entry loop would have added ~9 000
  assertions and made the suite total incomparable across cuts without covering
  anything more.

### Performance

The fix touches the hot path: 17 write sites gained a comparison and a call.
Measured **back-to-back in one session** against a pre-fix binary rebuilt from
the v1.3.2 tree, `RUNS=11` each:

| Corpus | v1.3.2 | v1.3.3 | Δ |
|---|---:|---:|---:|
| ascii (no LF) | 46.47 ns/byte | 46.46 ns/byte | −0.0% |
| ascii (w/ LFs) | 50.54 ns/byte | 50.91 ns/byte | +0.7% |
| utf8 mixed | 41.52 ns/byte | 41.82 ns/byte | +0.7% |

A repeated single-corpus pass separates the cost from host drift: +0.1% and
+0.6%. So the honest figure is **a real but small cost, around +0.5%** —
consistently positive rather than lost in noise, which is what a per-*flush*
comparison should cost. Well inside the 60 ns/byte M5 acceptance, and the trade
is not close: half a percent of throughput against a defect that silently
discarded 99.3% of the stream and exited 0.

> An earlier draft of the audit reported −0.5%, from a baseline taken at the
> start of the sweep and a post-fix run half an hour later. Those were not
> comparable — a third run of the same binary read 47.13 ns/byte. Only the
> back-to-back pairing measures the change rather than the machine.

All six goldens byte-identical. `hsv_rainbow` 8 ns, `tty_fg_rgb_buf` 51 ns
unchanged. Binary 814 448 → **814 480 B** (+32).


## [1.3.2] — 2026-08-25 (v1.3.x closeout)

**Closes the v1.3.x arc.** No remaining roadmap item was actionable — everything
left in `v1.x` is blocked on an external trigger (a consumer landing, a second
pipe-decorator wanting HSV) or explicitly declined. What *was* left were two
gate obligations the arc incurred and never discharged.

### Fixed — the two undischarged gates

- **Perf was never measured after `_frame_wait` landed.** v1.3.0's gate called
  for "perf within noise of v1.2.2's 46.64 ns/byte"; the slot was marked complete
  without running it, and `docs/benchmarks.md` had **no v1.3.x row at all** —
  even though v1.3.0 restructured the animation frame loop.

  Now measured head-to-head, rebuilt v1.2.2 binary vs v1.3.2, `RUNS=11`, idle
  host. Filter path (untouched by the arc): 46.22 → **46.61 ns/byte**, +0.8%,
  and flat on the other two corpora. Animation path (the one restructured): mean
  CPU over three 3-second runs, 5.0 ms → **5.1 ms**. Both within noise, as
  default-path equivalence predicts — at the default 16 ms interval with a 16 ms
  tick, `_frame_wait` performs exactly one slice, which is the same single
  sleep + signal probe + deadline check the old loop did.

  Also answered the question the slicing raised: **does a long interval cost
  more?** A 200 ms interval slices into ~13 ticks per frame instead of 1, so
  each frame pays 12 extra signal probes and 12 extra clock reads. Total CPU
  *falls* anyway — 3.8 ms at `-i 16` vs 3.0 ms at `-i 200` — because a longer
  interval means far fewer frames to render. Slicing is free; responsiveness is
  not traded for anything.

- **No audit covered the v1.3.x source.** The 2026-08-25 P(-1) sweep predates
  every line of it. Delta recorded in
  [`docs/audit/2026-08-25-v13x-delta.md`](docs/audit/2026-08-25-v13x-delta.md):
  **1 finding, INFO, fixed in-cut, zero HIGH+ open.**

  Recording the miss rather than quietly closing it, because it is the same
  shape as the v1.2.2 lesson: **a gate that is stated and not executed reads
  identically to one that passed.**

### Fixed — D-01 (INFO)

- **`_frame_wait`'s termination depended on a constant no code checked.** The
  slicing loop's only exit is `remaining` decreasing by `slice`. If
  `ANUENUE_TICK_MS` were ever `0`, `slice` clamps to `0`, `remaining` never
  decreases, and the loop spins forever — *inside animation, with the exit
  signals blocked*. A SIGKILL-only hang, the same failure class B-02 fixed from
  the other direction.

  Not reachable today: the tick is a module constant, no flag touches it, and a
  unit test pins it positive. But the invariant was held by a **test**, not by
  the code — and that test would still pass if the tick were later made
  configurable the way `ANUENUE_FRAME_MS` was at v1.3.0. That is this codebase's
  actual history: the frame interval sat as a fixed constant from M4 until a
  flag reached it, and reaching it is what exposed three defects.

  Fixed with a structural guard, `if (slice <= 0) { slice = 1; }`.

  ⚠ **Recorded as unproven**, in the cmdit 1.2.4 style: no failing test stands
  behind this line. No public API can drive the tick to zero, so deleting the
  guard keeps the suite green. The source comment says so rather than implying
  coverage it does not have.

### Closeout pass

Per CLAUDE.md § Closeout Pass, run over the arc's 178 net new `src/` lines:

- **Capability surface unchanged.** Still `write(1)`, `exit`, plus
  `sigprocmask` / `signalfd` on the animation path only. B-01's fix adds a
  `SIG_UNBLOCK` *argument* to a call that already existed — not a new syscall.
  No exec, network or filesystem sink.
- **Allocation sites**: 10, all guarded, none added by the arc. (An automated
  scan flagged three; all three are multi-variable allocations covered by a
  combined `if (a == 0 || b == 0 || c == 0)` below — false positives, verified
  individually rather than trusted.)
- **Dead code**: zero uncalled functions. **Unused constants**: zero.
- **Stack buffers**: none ≥ 1 KB; largest is still 128 bytes.
- **Deferral language**: clean — the single hit is a correct historical citation
  in `src/filter.cyr`'s header.
- **Doc links**: every intra-doc link and anchor resolves.

### Roadmap

The v1.3.x arc is closed. Nothing in `v1.x` is actionable without an external
trigger, so there is no v1.4.0 slot to open yet — the roadmap now says that
plainly rather than inventing work to fill one.


## [1.3.1] — 2026-08-25 (PTY-backed animation)

The one item carried out of the v1.3.0 animation slot, on its own cut because it
is a different kind of work: everything else in v1.3.0 was reachable from a
pipe, and this is not.

### Added

- **`scripts/pty-check.sh`** — drives anuenue through a real pseudo-terminal via
  `script(1)`. 14 checks, wired into CI, skip-clean when `script(1)` or
  `/dev/ptmx` is unavailable.

  **The colour auto-detection chain had never been exercised by CI.** On a pipe,
  `anuenue_detect_color_mode` exits at "stdout is not a TTY" and everything
  below that check — the `COLORTERM` test, the `TERM` heuristics, the 16-colour
  fallback — is unreachable. Every existing animation test passes
  `--color=24bit` specifically to route around it. So the branch that ships to
  actual users, on actual terminals, was the one branch no test ran.

  The harness now covers seven distinct exits of that function under a real TTY:
  `TERM=xterm-256color` → 256, `TERM=xterm-direct` → 24bit,
  `COLORTERM=truecolor` and `COLORTERM=24bit` → 24bit, `TERM=dumb` → the
  16-colour fallback, `NO_COLOR` → MONO, and `--no-color` overriding a
  colour-capable terminal. Each asserts both the resolved mode **and the
  reason** — the v1.2.1 observability is what makes the branch identifiable
  rather than merely inferred from output shape.

  It also covers what a pipe makes trivially true and a TTY makes meaningful:
  MONO passthrough on a colour-capable terminal is byte-identical to the input
  (the M6 acceptance), the cursor lifecycle on clean exit asserted by *ordering*
  against the end of the stream, and **SIGINT during animation while attached to
  a terminal** — the case the signalfd was written for. Its failure mode (B-01)
  and its latency (B-02) were covered at v1.3.0; this is the success path, and
  it confirms the M4 acceptance criterion directly: cursor shown after the
  signal, SGR reset before it.

  Two harness details worth recording, because both cost time:

  - **`pgrep -x`, not `pgrep -f`.** `script(1)`'s own argv contains the anuenue
    command line, so `-f` matches the wrapper first and the signal goes to the
    wrong process — the animation then never sees it and the test hangs.
  - **`script(1)` does not propagate `TERM`** from the parent environment, so
    each detection case sets it inside the command rather than around it.

### Changed

- **`docs/development/roadmap.md` — corrected an over-promise.** The v1.3.1
  entry claimed that on a PTY "the terminal state itself can be read back". It
  cannot: `script(1)` transcribes bytes, it does not emulate a terminal, so
  there is no cursor-visibility to query. The harness asserts byte ordering and
  process behaviour, which is what is actually observable, and both the script
  header and the roadmap now say so. Reading real terminal state back would
  need an emulator in the harness.


## [1.3.0] — 2026-08-25 (animation slot)

The v1.3.0 slot from
[`roadmap.md`](docs/development/roadmap.md). Animation was picked as the theme
because every open deferral clustered there — it is the least exercised path in
the tree: the only code that touches signals, the only code with input caps, and
the only code no test drives through a real terminal.

That turned out to be the right read. Adding one flag surfaced **three latent
defects**, two of which could leave a terminal unkillable.

### Added

- **`-i` / `--interval <ms>` — frame-interval override.** `ANUENUE_FRAME_MS` has
  been documented as "mutable so a future `-i` flag could override" since M4;
  this is that flag. `-i 33` animates at ~30 fps instead of the default ~60.

  Bounded at both ends, for different reasons. **Low** is a usage error: 0 is a
  busy-loop that pins a core and a negative value reaches `poll(2)` as an
  infinite timeout. **High** is clamped, and that bound is a correctness
  requirement rather than taste — see below.

- **`scripts/signal-check.sh`** — 12 checks over animation signal semantics and
  frame pacing, wired into CI. Covers what `animate-smoke.sh` structurally
  cannot: the process signal mask, and whether the frame loop stays responsive
  when the interval is user-supplied.

- **`tests/probes/sigmask-probe.cyr`** — a standalone probe that observes the
  process signal mask under a forced `signalfd(2)` failure. Not a `.tcyr`,
  because it must run as its own binary under `prlimit --nofile=3`.

- **15 new unit assertions** (349 → 364) pinning the tick and interval bounds,
  including assertions that the two motivating values really do misbehave, so
  nobody "simplifies" the clamp away.

### Fixed

- **B-01 (MEDIUM) — `_open_exit_signalfd` leaked its `SIG_BLOCK` when
  `signalfd(2)` failed.** The acquire order is block-then-open. If the open
  failed, the function returned early with SIGHUP/SIGINT/SIGTERM **still blocked
  and no fd to drain them** — so for the rest of the process Ctrl-C was inert,
  `kill` was inert, terminal hangup was inert, and only SIGKILL worked. The
  caller is documented to degrade gracefully on `-1`, and "gracefully" has to
  mean the signals still work.

  This is the same defect darshana fixed in its own `tty_open_signalfd` at
  v0.9.3. anuenue rolls its own — it needs a *non-blocking* fd, where darshana's
  helper is sized for an epoll-driven consumer — and the copy predates that fix.

  **This closes INFO 8 and 9 from the [2026-05-22 audit](docs/audit/2026-05-22-audit.md).**
  Both were accepted on the reasoning "the process exits before the mask
  matters", and both sat unmeasured for three minors. The reason they were never
  measured is itself worth recording: the obvious test — run the CLI under
  `prlimit --nofile=3` — **cannot work**, because `args_init()` opens
  `/proc/self/cmdline` to read argv, so under that limit the real binary never
  parses a flag and never reaches animation at all. The probe sidesteps it by
  calling no `args_init` and reading no file, and observes the mask through
  `sigprocmask(SIG_BLOCK, <empty set>, &oldset)` — a pure query needing no
  descriptor.

  Mutation-proven: deleting the rollback makes the probe report
  `exit_bits_blocked=16387` with `fd=-1`.

- **B-02 (MEDIUM) — a long `--interval` made the process unkillable.** The frame
  loop slept the entire interval in one `sleep_ms` call and checked for signals
  afterwards. With `ANUENUE_FRAME_MS` fixed at 16 that window was invisible;
  `-i` makes it user-supplied. Because the exit signals are *blocked* for the
  duration of the animation, a long sleep does not merely delay the reaction —
  the default disposition never fires either. Measured with `-i 3600000`:
  `timeout(1)` could not kill the process at all.

  `_frame_wait` now sleeps in slices of at most `ANUENUE_TICK_MS` (16 ms),
  checking the signalfd and the deadline between slices. Total sleep per frame
  is unchanged, so the visible frame rate is identical — only the granularity at
  which the loop looks up. Verified: with `-i 3600000` the process now ends
  3007 ms after a 3 s SIGTERM, same as with `-i 16`.

- **B-03 (LOW) — `--duration` overshot by up to one interval.** Same root cause.
  `-i 3600000 -d 1` asked for one second and would have taken an hour. Now
  exits in 1 s at every interval from 16 ms to an hour.

- **A silent signalfd fallback.** When `signalfd(2)` fails, animation degrades to
  no-signal handling — legitimate, but it was silent, so a terminal left
  cursorless after Ctrl-C had no explanation anywhere. Now a `SK_WARN` record
  carrying the errno. Same discoverability lesson as A-05.

### Why the interval clamp is a correctness bound

`sleep_ms(ms)` is `poll(NULL, 0, ms)` on Linux and macOS, and `poll(2)`'s
timeout argument is a 32-bit **int**. An i64 millisecond count is truncated on
the way in, and the result is not merely imprecise — it is **non-monotonic**.
Measured on this toolchain:

| `sleep_ms(ms)` | Truncates to | Behaviour |
|---|---|---|
| `2147483647` | `2147483647` | blocks ~24.8 days (honest) |
| `2147483648` | `-2147483648` | **blocks forever** |
| `4294967296` | `0` | **returns instantly** (busy loop) |
| `4294967396` | `100` | sleeps 100 ms |
| `9223372036854775807` | `-1` | **blocks forever** |

So a large `-i` does not give a slow animation. Depending on which side of a
power of two it lands, it gives either a hung terminal or a busy-loop rendering
as fast as the CPU allows — both the opposite of "wait longer between frames".
Same defect class as A-02, reached through different arithmetic.

`ANUENUE_MAX_INTERVAL_MS = 3600000` (one hour per frame) is far inside int32's
positive range and already past useful, so anything above it is a typo rather
than an intent. Values above are clamped and warned about, matching `-d`.

### Added — parser fuzzing

- **`fuzz/flag-value-parsers.fcyr`** — the sixth harness, and the first that
  fuzzes **strings** rather than integers. **+96 091 assertions** (fuzz total
  1 354 581 → **1 450 672**).

  It targets the two parsers that now *reject* rather than fall back
  (`--log-level` at v1.2.1, `--color` at v1.2.2 / A-04). That swap changed the
  failure mode: a falling-back parser is total by construction, while a
  rejecting one has to get two things right — recognise everything it claims to
  accept, and reject everything else. A-09 proved the first half can rot
  silently, so the harness checks four properties rather than "does it parse
  `256`":

  - **Totality** — arbitrary bytes, arbitrary length and a null pointer all land
    inside the declared enum range. A value outside it slips past `main.cyr`'s
    `== BAD` test and flows on as a colour mode nobody asked for.
  - **Exactness** — flip one byte of an accepted value and it must be rejected.
    A prefix match (`256x` → 256), a substring match (`xx16xx` → 16) or a
    case-insensitive compare would all pass a nine-good-values test and fail
    here.
  - **Name totality** — every `*_name()` returns a non-null, plausibly-short
    cstr for *any* i64, because the result goes straight to `strlen` inside the
    logger. A null there is a deref on a diagnostic path — the worst place for
    one, since the user is already debugging something.
  - **Round-trip** — `parse(name(p)) == p` across the level scale, the contract
    agnostik's F-018 holds its own enums to, plus the negative case: the `BAD`
    sentinel's name must *not* parse back into a real level.

  One assertion in the first draft was wrong and worth recording: it required
  every parse result to map inside sakshi's scale, but `BAD` maps to 6 — one
  above `SK_TRACE`. That is not a defect, it is precisely why `main.cyr` must
  reject `BAD` *before* calling `anuenue_observe_init`; if it ever reached init
  it would set a level no record can exceed, silently turning every level on.
  The harness now asserts that asymmetry explicitly.

### Added — architecture notes

- **`docs/architecture/` populated with six notes.** The directory had said
  "_Empty_" since v0.1.0 while CLAUDE.md listed it as a documentation path. Each
  entry records something the v1.2.2 audit or this slot had to *discover* —
  which is the bar, rather than restating what the code says:

  | Note | Invariant |
  |------|-----------|
  | 001 | The line-buffer geometry is a proof, not three round numbers: `FLUSH_RESERVE` must cover the worst-case iteration, and the bounds check runs *after* the write. |
  | 002 | Phase normalization is a bounds guarantee — the normalized value is an array index, and `-s` / `-F` / `-p` reach it with negative and wrapped i64 straight from argv. |
  | 003 | The animation caps *drop* input rather than uncolouring it, because `_pretag_clusters` writes its sentinel at the stop offset. |
  | 004 | `src/observe.cyr` must depend on nothing from anuenue: every other module calls `anuenue_fail`, and cyrius resolves constants in include order. |
  | 005 | `sleep_ms` takes an i64 and hands it to `poll(2)`'s 32-bit `int`; the truncation is non-monotonic, so a large sleep hangs or spins rather than sleeping long. |
  | 006 | Reading argv costs a file descriptor, so anuenue's CLI cannot be exercised under an fd limit — the reason two audit findings went unmeasured for three minors. |

### Carried to v1.3.1

The PTY-backed animation test moves to its own cut. Everything else in this slot
was reachable from a pipe; that one is not, and it is the only way to test three
behaviours that need a controlling terminal — `tty_isatty` taking the branch a
pipe never takes, cursor restore being *readable back* rather than inferred from
bytes, and SIGINT arriving as a real terminal signal. See
[§ 1.3.1](#131--2026-08-25-pty-backed-animation), which shipped it.


## [1.2.2] — 2026-08-25 (P-1 audit sweep)

A full **P(-1) audit / refactor / hardening / optimization / security sweep**
over the whole source, plus the removal of the binary-size cap.

**9 findings — 2 MEDIUM, 5 LOW, 2 INFO. All fixed in-cut, zero HIGH+ open.**
Every fix carries a regression test that fails if the fix is reverted. Full
write-up: [`docs/audit/2026-08-25-audit.md`](docs/audit/2026-08-25-audit.md).

The method mattered more than any single bug. **A-01 was found by reading;
A-02 through A-05 were found by *running*** — adversarial byte streams and
adversarial argv against the real binary. Each of those four looks correct in
isolation. Three of the nine are the same defect in different clothes: a silent
fallback where an error belonged. A-09 is the compound interest on one of them.

### Fixed

- **A-01 (MEDIUM) — `_cp_ext_init` wrote 42 words through an unchecked
  allocation** (`src/filter.cyr`). `lib/alloc.cyr` returns 0 on OOM rather than
  aborting, so a failed allocation sent 42 `store64` calls to absolute addresses
  `0x000`–`0x148`. `_phase_esc_init`, 200 lines above in the same file, already
  checked — this call site simply never got the same treatment. Worse, the
  failure was unobservable: `_cp_ext_init` returned success unconditionally and
  `cp_is_extending` discarded the result, so had the null write not faulted the
  binary search would have run against a null table. Same class cmdit's own
  1.2.4 audit hardened, reaching anuenue through a different door.

  MEDIUM rather than HIGH because the size is a compile-time constant (336 B),
  so no input can drive the failure — it needs genuine heap exhaustion. Fixed by
  checking, returning `-1`, and having `cp_is_extending` answer "not extending"
  when the table is unavailable. That keeps **output byte-correct** and degrades
  only cluster grouping, which is the right trade for a filter whose contract is
  byte preservation.

- **A-02 (MEDIUM) — a long `--duration` made the animation exit immediately.**
  `deadline_ns = start_ns + duration_secs * 1000000000` overflows i64 above
  ~9.22e9 seconds. At `i64::MAX` the product is congruent to *exactly* −1e9, so
  the deadline landed one second **in the past** and
  `anuenue -a -d 9223372036854775807` exited after a single frame — the precise
  inverse of the request. Clamped to `ANUENUE_MAX_DURATION_S` (4e9 s, ~127
  years) before converting. The bound sits well below the arithmetic maximum on
  purpose: at the tightest valid clamp the constant would silently depend on
  whether `clock_now_ns()` is boot-relative (it is today) or epoch-relative.

- **A-03 (LOW) — a negative `--duration` silently meant "run forever."**
  `if (duration_secs > 0)` left the deadline at 0, which is the *documented
  sentinel* for "until SIGINT". Now a usage error; `0` remains the explicit way
  to say it. Validated unconditionally so the error does not depend on flag order.

- **A-04 (LOW) — an unrecognised `--color` value silently meant `auto`.**
  `--color=trucolor` ran full colour detection while the user believed they had
  forced truecolor, exit 0, nothing on stderr. The old comment defended this as
  "a typo doesn't silently force a colour mode the user didn't intend" — but
  **AUTO is a mode**; the fallback chose a different silent outcome rather than
  avoiding one. v1.2.1 had already made this exact call the other way for
  `--log-level`; the two flags now agree. New `ANUENUE_COLOR_OVERRIDE_BAD`
  sentinel → usage error listing the accepted values. Null and empty still mean
  AUTO — that is "flag absent", not "bad value".

- **A-05 (LOW) — animation dropped input past its caps in silence.** The 64 KB
  byte cap and 8 192 cluster cap are deliberate ("render what fit; don't OOM"),
  but `_pretag_clusters` writes its sentinel at the byte offset where it
  stopped, so text past the cap is **never rendered**, not merely rendered in one
  colour. A 200 001-byte input animated as exactly 8 192 characters per frame
  with nothing said on any fd. Both caps now warn via sakshi, so `-v` /
  `--log-level=warn` explains the missing text. Caps themselves unchanged.

- **A-06 (LOW) — animation's failure paths returned a bare `1`.** v1.2.1 routed
  the filter and passthrough failures through `anuenue_fail` but missed
  `anuenue_animate`: three allocation failures and the stdin read error still
  produced no output on any descriptor. Routed through `anuenue_fail`; exit codes
  unchanged. The animate path now also accumulates `ANUENUE_BYTES_IN`, so `-v`
  reports byte counts for `-a` runs.

- **A-09 (LOW) — `--color=mono` was documented for four months and never
  implemented.** Surfaced *by fixing A-04*, not by the sweep: with unknown values
  rejected, `docs/examples/06-no-color.sh` started failing — it runs
  `--color=mono`, and its header lists it as a valid override. The parser had no
  branch for it, so it fell through to AUTO and the example ran colour detection
  while claiming to demonstrate forced mono, **exiting 0**.

  This is the strongest argument in the audit for A-04's fix: the silent fallback
  did not merely swallow user typos, **it hid our own broken documentation from
  our own example suite**, which CI runs on every push. `mono` is now implemented
  as a synonym for `none` — the documentation was right and the code was wrong.

### Changed

- **The 512 KB binary-size cap is removed.** It was set at v0.7.1 when the binary
  was ~350 KB and essentially all of it was anuenue. That is no longer what the
  number measures. Three things changed underneath it: the first-party dep
  surface is the floor now (agnostik alone is ~546 KB, against ~2 400 lines of
  anuenue source); `CYRIUS_DCE=1` stopped removing anything on 6.5.x, so "DCE
  binary size" measures the whole link; and no CI step ever enforced the cap, so
  its only real effect was to make every dep bump read as a regression.

  Capping the total would mean a downstream pipe filter vetoing darshana,
  sakshi, agnostik and cmdit's right to grow — backwards, since those crates
  growing is the ecosystem working. **Replaced with: track the size every
  release and attribute any step change** (toolchain? dep? our code?). A jump is
  a fact to explain, not a threshold to fail. Recorded in CLAUDE.md and
  `state.md`.

- **A-07 (INFO) — `cyrius fmt` drift in four files, and the formatter's own fix
  made one worse.** Applying it was mostly benign — `animate.cyr` and `main.cyr`
  got *shallower* (max indent 38→16 and 44→24 columns). `hsv.cyr` was the
  exception: `hsv_rainbow`'s six-sector colour table is a `} else { if (...) {`
  chain, which the formatter indents one level deeper per arm, cascading sector 5
  to **24 columns** and destroying the parallel alignment that is the entire
  point of a lookup table. Restructured as a flat run of early returns instead —
  reads as the table it is, is naturally format-stable, and drops the trailing
  `} } } } }` pile. **Emitted bytes unchanged**: all six goldens byte-identical
  and `hsv_rainbow` still benches at 8 ns. Worth noting because `hsv.cyr` is the
  distlib module consumers include.

- **A-08 (INFO) — eight public functions had no docstring.** Several were covered
  by a shared block comment above a group, which the docs checker does not credit
  — correctly, since a reader arriving at the second function in a group sees
  nothing. Per-function docstrings added, each stating the return contract.

- **`--color` accepts nine documented values** — `auto`, `24bit`, `truecolor`,
  `256`, `16`, `none`, `mono`, `off`, `never`. Help text and the A-04 error
  message now list all of them; `truecolor` / `off` / `never` worked before but
  were undocumented, and `mono` was documented but did not work.

- **`--color` override constants converted from five initialized globals to an
  `AnuenueColorOverride` enum**, per the CLAUDE.md convention. Values unchanged;
  `BAD` is additive.

### Documentation — roadmap reorganised

- **[`docs/development/roadmap.md`](docs/development/roadmap.md) rebuilt around
  work arcs instead of a finished milestone plan.** It had been the pre-GA M0–M8
  sequencing document and was three minors stale: the dependency map still read
  darshana `0.5.3` / sakshi `2.2.5` / agnostik `1.2.2` / Cyrius `6.0.1` with no
  cmdit row at all, "Current focus" still said v1.0.0 GA, the shipped table
  stopped at v1.0.0, and it promised an ADR 0003 that shipped at v0.8.0.

  Now: completed milestones collapse into a **Shipped** index, and everything
  above the fold is forward work — a **v1.3.0** slot, a **v1.x** arc, **v2.0**
  reserved, plus **explicitly declined** and **upstream, not ours** sections so
  closed questions are not re-raised as findings.

  **v1.3.0 is the animation slot.** Everything currently actionable clusters
  there, which is not a coincidence: animation is the least exercised path in
  the tree — the only code that touches signals, the only code with input caps,
  and the only code no test drives through a real terminal. It carries the
  `-i` / `--interval` flag, a PTY-backed animation test, re-measurement of two
  unverified INFO findings, a fuzz harness over the two parsers that now reject
  rather than fall back, and the first entries in the empty
  `docs/architecture/`.

- **Every deferral in the codebase now traces to the roadmap, or was retired.**
  A sweep for deferral language across `src/`, `tests/`, `fuzz/` and `scripts/`
  returned 11 hits. Two were live deferrals and are now scheduled with
  cross-references in both directions; the rest were prose. Three were stale and
  are fixed:

  - **`src/hsv.cyr` and `tests/anuenue.tcyr` both called `-F` a "future flag".**
    It shipped at M2 / v0.3.0. Worse, the framing understated the code: the
    comments treated negative phase as hypothetical when `-s` and `-F` take
    arbitrary i64 from argv and are summed into `ANUENUE_PHASE_START`, so
    `-F -1` reaches the normalizer directly — and the result indexes
    `_PHASE_ESC_TABLE`. That normalization is a bounds guarantee, not a nicety,
    and now says so.
  - **`tests/anuenue.bcyr` promised that "M5 (perf pass) will add a per-byte
    aggregate inside this file".** M5 shipped at v0.6.0 and did not — it shipped
    `scripts/perf-bench.sh` instead, which has been the ratchet ever since. The
    comment had outlived the milestone it was waiting on by six releases.

- **`state.md`'s Carry-Forward section stops duplicating the roadmap.** It keeps
  only what is state rather than plan: the cadences that run every cut, and the
  v1.2.2 lesson that an accepted INFO finding is a hypothesis about behaviour
  rather than a measurement of it — the reason the two remaining 2026-05-22 INFO
  items are scheduled work rather than a footnote.

### Added

- **`scripts/robustness-check.sh` — adversarial input and argv, wired into CI.**
  The unit suite covers the parser and classifier functions in isolation; the
  fuzz harnesses cover them under seeded random input. Neither runs the binary
  against adversarial byte streams or adversarial argv, which is where four of
  the nine findings lived. Eleven checks over four gates:

  1. **UTF-8 carry across the 4096-byte read boundary** — a multi-byte sequence
     split 1/3, 2/2 or 3/1 across the chunk boundary must produce byte-identical
     output to the same input delivered one byte at a time (`dd bs=1`). 52
     comparisons. This is the property `carry_len` exists for and nothing else
     tested it end to end.
  2. **Byte preservation under malformed UTF-8** — strip the SGR escapes back
     out and the result must equal the input, byte for byte, across overlong
     2/3/4-byte forms, UTF-16 surrogates, codepoints above U+10FFFF, the
     `0xF5`–`0xFF` range, lone continuations, EOF truncation, embedded NULs and
     all 256 byte values. 116 comparisons.
  3. **Argv extremes** — every integer flag at both i64 extremes must terminate
     with a documented exit code, never a signal, never a hang.
  4. **One process-level regression per audit finding.**

- **41 new unit assertions** (308 → 349) across four groups, one per finding with
  a testable invariant.

- **CI gates**: the robustness check joins lint, observability and distlib-drift.

### Performance

Unchanged. Head-to-head on one idle host, `RUNS=11`, v1.2.1 binary vs v1.2.2
binary:

| Corpus | v1.2.1 | v1.2.2 | Δ |
|---|---:|---:|---:|
| ascii (no LF) | 46.57 ns/byte | 46.64 ns/byte | +0.2% |
| ascii (w/ LFs) | 50.98 ns/byte | 50.97 ns/byte | −0.0% |
| utf8 mixed | 41.66 ns/byte | 41.71 ns/byte | +0.1% |

Within run-to-run noise; all under the 60 ns/byte M5 acceptance. `hsv_rainbow`
holds at 8 ns across the A-07 refactor — flattening the sector table cost
nothing. Binary 809 520 → **809 984 B** (+464), the audit fixes.

### Verified clean

Recorded so the next audit knows what was covered: the capability surface (only
`write`, `exit`, and `sigprocmask`/`signalfd` on the animation path — no `open`,
`connect`, `fork`, `execve`, `socket`, and no `sys_system` anywhere, so command
injection is structurally impossible); UTF-8 robustness across 60 corpus × mode
combinations; chunk-boundary carry across 52; phase arithmetic under i64
extremes (both normalizers correct negatives, so a wrapped phase cannot produce
a negative table index); `FLUSH_RESERVE` geometry; stack buffers (largest is 128
bytes); and the v0.8.0 M8 long-cluster fix, which still holds.


## [1.2.1] — 2026-08-25 (toolchain + deps + observability + CI repair)

Maintenance cut with three threads: the toolchain/dep refresh, the **sakshi +
agnostik wiring that should have existed since M0**, and a **CI repair the pin
bump made urgent**.

The filter itself is untouched. The v1.2.0 and v1.2.1 binaries are byte-identical
on stdout across **192 comparisons** (16 input corpora × 12 flag combinations,
covering invalid UTF-8, truncated sequences, 200 KB of raw binary, a
5 000-combiner cluster and all four colour modes), with matching exit codes on
all 192. All six goldens byte-identical, three MONO checks hold, animate-smoke
green across truecolor / 256 / 16 / long-cluster. **308 unit assertions** (was
242) and **1 354 581** fuzz assertions pass. Per-byte throughput is unchanged
within noise. The v1.x public API contract (exit codes, output shape, capability
surface) is unchanged; the flag set is **additively** extended by two
diagnostics flags.

### Added

- **`-v` / `--verbose` and `--log-level=<level>` — structured diagnostics via
  sakshi, with agnostik-typed errors (`src/observe.cyr`, new).**

  sakshi and agnostik had been declared deps since the M0 scaffold with **zero
  call sites in any anuenue source file**. They were linked into every binary
  and never called. That is not a dependency anuenue doesn't need — it is a
  dependency anuenue never wired up. first-party-standards makes sakshi the
  canonical error/tracing crate and agnostik the shared Result/Error shapes;
  anuenue now uses them like the first-party tool it is.

  `-v` is shorthand for `--log-level=debug`; an explicit `--log-level` wins when
  both are given. Levels are `off` (default) / `fatal` / `error` / `warn` /
  `info` / `debug` / `trace`. An unrecognised level is a usage error (exit 2)
  rather than a silent default, because the failure mode of a silent default is
  a user who asked for output, got none, and concludes the tool is broken.

  What a run reports: version, resolved phase step and start, the resolved
  colour mode **and the branch that chose it**, the dispatch route
  (filter / animate / passthrough / positional-text), bytes read, exit code, and
  an enclosing span with elapsed time.

  Spans are gated at debug-or-finer rather than at "logging is on". sakshi does
  not level-gate `sakshi_span_enter` / `_exit` at all — they emit whenever
  called — so without anuenue's own gate a `--log-level=error` run printed
  ENTER/EXIT around its errors, and no level could suppress it. A clean
  `--log-level=warn` run is now completely silent.

  The colour *reason* is the highest-value line here and the reason the feature
  earns its place. v1.1.5's "rainbow collapsed to 16 colours on AGNOS" was
  `anuenue_detect_color_mode` reaching its env-heuristic tail on a platform that
  sets no env — a wrong branch that no output could distinguish from a right
  one. `anuenue -v` now prints `reason=agnos framebuffer console` or
  `reason=no signal — 16-colour fallback`, and the difference is one line
  instead of a source read.

- **Pipe-purity is enforced, not asserted (`scripts/observe-check.sh`, new).**

  Every byte the diagnostics can emit goes to **fd 2**. stdout carries the
  rainbow and nothing else, at every verbosity. anuenue lives in the middle of
  pipelines (ADR 0001), so a diagnostics feature that leaked one byte onto fd 1
  would silently corrupt every `iam | anuenue | ...` it was enabled in — which
  is a process-level, fd-level property no unit test can express. The new gate
  asserts it directly across 22 checks: stdout is byte-identical over **144 corpus
  × colour-mode × verbosity combinations**, stderr is empty in every
  default-verbosity run, `-v` carries the fields a bug report needs, level
  filtering actually filters, and the failure path emits its agnostik code.
  Wired into CI.

  Two mechanisms hold the property up. sakshi's sink is pinned with
  `sakshi_set_output_fd(2)` — the file and UDP targets are never selected, so
  the capability bound in CLAUDE.md (no file I/O, no network) is intact and the
  syscall surface stays read/write/brk/exit. And logging is **off by default**:
  sakshi's own default is `SK_INFO`, which would have put info lines on the
  stderr of every MOTD, so `anuenue_observe_init` drops the level below
  `SK_FATAL` unless asked. A pipe filter is silent until told otherwise.

- **66 new unit assertions** (242 → 308) over the log-level parser (including
  case-sensitivity, the empty string and a null pointer), the parse-to-sakshi
  scale mapping, verbosity resolution, colour-reason recording, name-function
  totality, and the agnostik-kind → exit-code mapping.

### Fixed

- **CI would have broken on the first push after the pin bump.** Both workflows
  hand-rolled the toolchain install by untarring the release asset into
  `$HOME/.cyrius/{bin,lib}` — the **pre-6.5 layout**. From 6.5.x `cyrius deps`
  resolves the stdlib snapshot from `$HOME/.cyrius/versions/$CYRIUS_VERSION/lib`
  and hard-fails with *"pins version X but it is not installed"* when only the
  flattened directories exist. Replaced with the upstream installer
  (`scripts/install.sh` with `CYRIUS_VERSION`), which lays out
  `versions/<v>/{bin,lib}`, symlinks `bin/` and `lib/` at it, and additionally
  does SHA256 + signature verification the hand-rolled block skipped. Same
  pattern as darshana / patra / libro. A new **Verify toolchain layout** step
  fails loudly at install time rather than letting the next `cyrius` invocation
  die pointing at the manifest.

- **`CYRIUS_DCE=1` was never actually set in CI or release.** CLAUDE.md § CI /
  Release states it as a hard rule for *every* `cyrius build`; neither workflow
  did it, so the release artifact was built differently from the tested binary.
  Both now set it. (On 6.5.x this no longer changes output size — see below —
  but the artifact and the tested binary now match.)

- **A failing filter said nothing.** `anuenue_filter` / `anuenue_passthrough`
  returned bare `1` on a read error or allocation failure, with **no message on
  any fd** — the pipeline just ended short. They now route through
  `anuenue_fail`, which prints e.g. `anuenue: i/o error: read from stdin failed`
  to stderr and, under `-v`, logs the agnostik code (`CODE_IO` = 1010). **Exit
  codes are unchanged** (1 for runtime, 2 for usage) — this adds a diagnostic to
  a path that previously failed silently. It is the one intentional change to
  default-verbosity stderr in this release.

- **`src/filter.cyr` — untracked deferral surfaced by the 6.5.35 lint.** The
  grapheme-cluster comment said Devanagari spacing marks advance "for now" and
  that "ADR 0003 (M7) *will* record this trade-off" — stale future tense since
  v0.8.0, when ADR 0003 shipped and did record it, including both visible misses
  (Hangul L/V/T composition, Devanagari spacing marks). Now cross-referenced.
  A **Lint gate** was added to CI so the next one is caught there rather than by
  the next person to bump the pin.

- **A `Str` coercion trap that would have shipped every error message empty.**
  `agnostik_err_new(kind, message: Str)` stores the value and
  `agnostik_err_print` reads it back through `str_data` / `str_len`. On cyrius
  6.5.35 a string literal is coerced to `Str` at a call site whose parameter is
  typed `Str` — but **not in return-expression position**:

  ```
  anuenue_fail(KIND, "literal");           # statement   -> coerced, prints
  return anuenue_fail(KIND, "literal");    # return expr -> NOT coerced
  ```

  Same function, same literal, same signature. Uncoerced, `str_data` loads the
  first eight characters *as a pointer* and every error prints its kind with an
  empty message (`anuenue: invalid argument:`). Every anuenue call site is a
  `return anuenue_fail(...)`, so all of them were in the broken position.
  `anuenue_fail` now takes an ordinary cstr and converts explicitly with
  `str_new`, which is position-independent. Caught by running the path, not by
  reading it.

### Changed

- **Cyrius toolchain pin `6.4.62` → `6.5.35`** (`cyrius.cyml [package].cyrius`).
  `./lib/` re-synced via `cyrius lib sync --full` (108 stdlib files; four new
  modules — `async_macos`, `async_win`, `thread_macos`, `yantra`). Both
  build-time warnings the old tree carried are gone (the `./lib/` shadow-drift
  and manifest-pin-drift warnings), as are three `lib/bayan.cyr`
  "assigning non-pointer to typed pointer" warnings fixed upstream.

- **`[deps]` tags re-pinned to the versions actually vendored, then advanced to
  current**: darshana `0.9.0` → **`1.0.0`**, cmdit `1.1.0` → **`1.2.4`**,
  sakshi `2.4.6` → **`2.4.11`**, agnostik `1.3.4` → **`1.5.1`**.

  The tags had drifted from the bytes: the committed bundles were already at
  cmdit 1.2.2, sakshi 2.4.11 and agnostik 1.3.5 while the manifest still claimed
  1.1.0 / 2.4.6 / 1.3.4. A `path`-mode tag binds only when `cyrius.lock` agrees,
  so editing a tag without invalidating the lock silently keeps the locked
  commit — and the manifest had quietly become documentation rather than a pin.
  Tags and bytes now agree.

- **darshana 1.0.0 is the API freeze.** The nine darshana symbols anuenue calls
  (`tty_fg_rgb_buf`, `tty_fg_256_buf`, `tty_sgr_buf`, `tty_sgr_reset_buf`,
  `tty_sgr_reset`, `tty_cursor_up`, `tty_cursor_hide`, `tty_cursor_show`,
  `tty_isatty`) all sit inside the frozen 29-function surface. The two v0.9.3
  breaks are non-events here: the `AGNOS_*` → `_AGNOS_*` privatization touches
  symbols anuenue never named, and `tty_sgr_reset_buf`'s new
  `-1`-on-negative-`pos` return is unreachable — every `pos` at all fifteen call
  sites (11 in `src/filter.cyr`, 4 in `src/animate.cyr`) is a non-negative
  accumulator. `tty_open_signalfd`'s `-errno` → `-1` change is likewise moot:
  `src/animate.cyr` deliberately rolls its own *non-blocking* signalfd.

- **cmdit 1.2.4 is the P-1 audit cut** (completion-script program-name injection
  plus three memory-safety / contract fixes). anuenue is exposed to none of them
  — it passes a literal prog name to `cmdit_new` and never calls
  `cmdit_completions` — verified rather than assumed: the full CLI surface
  (`--help`, every error path, every exit code) is byte-identical across the
  bump apart from the version literal.

- **Exit codes moved from three initialized globals to an `AnuenueExit` enum**
  and, with `_eprint`, relocated from `src/main.cyr` to `src/observe.cyr` so the
  error paths in `color.cyr` and `filter.cyr` can reach them. Values unchanged
  (0 / 1 / 2) — this is the v1.x contract. Per the CLAUDE.md convention
  ("Enum values for constants — don't consume `gvar_toks` slots").

- **`main()` dispatch routed through a single `rc` and one exit** so the sakshi
  span always closes and the completion summary always emits. The four routes
  and their conditions are unchanged.

- **`dist/anuenue.deps` is a new committed artifact.** The 6.5.x toolchain emits
  a stdlib-leaf sidecar beside the distlib bundle, and `cyrius distlib --check`
  treats its absence as STALE. A **distlib drift check** step was added to CI.

### Performance

Unchanged. Measured head-to-head on one idle host, same fixture, `RUNS=11`,
v1.2.0 binary vs the final v1.2.1 binary (observability included):

| Corpus | v1.2.0 | v1.2.1 | Δ |
|---|---:|---:|---:|
| ascii (no LF) | 47.20 ns/byte | **46.63 ns/byte** | −1.2% |
| ascii (w/ LFs) | 50.98 ns/byte | **50.99 ns/byte** | +0.0% |
| utf8 mixed | 41.85 ns/byte | **41.77 ns/byte** | −0.2% |

All under the 60 ns/byte M5 acceptance cap. Nothing in `src/observe.cyr` is
called per byte or per cluster — the call sites are startup, dispatch, teardown
and the error paths. The one addition inside the read loop is a single
accumulate of `n_read`, executed once per `read(2)`: a few dozen additions
across a multi-megabyte stream.

Diagnostics output is **O(1) in input size** — exactly 10 records regardless of
stream length:

| Input | stderr under `-v` | records |
|---:|---:|---:|
| 1 KB | 489 B | 10 |
| 100 KB | 492 B | 10 |
| 1.4 MB | 494 B | 10 |
| 5 MB | 494 B | 10 |

Enabling `-v` costs ~11 ms of fixed startup/teardown on this host (clock reads
and unbuffered stderr writes) and nothing per byte.

The microbench moved (`hsv_rainbow` 18 → 8 ns, `tty_fg_rgb_buf` 95 → 52 ns) but
is **not** comparable across this cut: 6.5.35's `bench` harness measures and
subtracts a timer floor (1.347 µs per clock read here) that 6.4.62's did not.

### Binary size

**389 648 B → 809 520 B** (+419 872, +108%), against the 512 KB cap discipline
recorded in [`state.md`](docs/development/state.md). The growth is the toolchain
and dep surface, not anuenue code — the observability module accounts for 5 560 B
of it. Each figure below was measured with an invalidated lock in an isolated
worktree, so the tag actually resolves:

| Step | Binary | Δ |
|---|---:|---:|
| v1.2.0 (cycc 6.4.62 + old dep tags) | 389 648 B | — |
| + dep bump only (cycc 6.4.62) | 524 888 B | +135 240 |
| + toolchain bump (cycc 6.5.35) | 803 960 B | +279 072 |
| + observability wiring | **809 520 B** | +5 560 |

`CYRIUS_DCE=1` no longer changes the output size — 6.5.35 NOPs unreachable
functions in place rather than eliminating them, so the DCE and non-DCE binaries
are byte-for-byte the same size. "DCE binary size" now measures the whole binary,
which is part of why the step change reads so large.

The cap decision is deferred to the next cut rather than resolved here. Note
that the two largest contributors — agnostik (~546 KB) and sakshi (~90 KB) —
are now **called code**, not dead weight: this release is what gave them call
sites. Raising the cap with a rationale is the likely resolution; dropping a
canonical first-party dep is not.

## [1.2.0] — 2026-07-14

### Added
- **Library surface — `dist/anuenue.cyr` distlib (`[lib]` profile).** anuenue is now consumable as a library, not
  only as a pipe-filter binary: `cyrius distlib` bundles the pure HSV phase model (`src/hsv.cyr` —
  `ANUENUE_PHASE_MOD` + `hsv_rainbow(phase, out_rgb)`, integer 6-sector HSV→RGB, zero darshana/sakshi refs) so a
  consumer can `include "lib/anuenue.cyr"` and tint text **in-process** instead of shelling out. First consumer:
  thoth's `/theme rainbow` TUI render mode. The filter / animate / colour-mode / CLI machinery stays app-only.


## [1.1.5] — 2026-06-26

### Fixed
- **Rainbow collapsed to 16 colors on AGNOS — now truecolor (`src/color.cyr`).** `anuenue_detect_color_mode` skips the Linux `tty_isatty` check on agnos, then fell through to the `TERM`/`COLORTERM` env heuristics — but agnos sets no such env (`getenv` returns 0), so it landed on the final **16-color** fallback, where `_rgb_to_16` quantizes the smooth HSV rainbow down to just 6 ANSI colors ("color mixing isn't happening like Linux"). The agnos framebuffer console is **24-bit truecolor-capable** and its kernel SGR parser handles `ESC[38;2;R;G;Bm` directly (`fb_console.cyr` `fb_ansi_sgr`), so agnos now defaults to `ANUENUE_COLOR_TRUE` for the full gradient. `--color` / `--no-color` / `NO_COLOR` and `--color=16` / `=256` still override.

### Changed
- **Bumped the cyrius toolchain pin `6.2.24` → `6.2.44`** (`cyrius.cyml`) — aligns with the current ecosystem toolchain.

## [1.1.4] — 2026-06-25 (CLI parsing → cmdit)

Adopts the **cmdit** distlib for CLI/argument parsing, dropping the stdlib `flags`
parser. cmdit IS that parser productized + extended, so the swap is byte-compatible:
all six golden render fixtures stay byte-identical, the three MONO equivalence checks
hold, and the unit suite is green (242/242). No behavioural change to the filter; the
`--help` flag list is now generated by cmdit (anuenue keeps its brand intro + Usage +
Examples framing around it via `cmdit_help_flags`). anuenue is cmdit's second worked
migration (after kii). The v1.x public API contract (flags / exit codes / output
shape / capability surface) is unchanged.

### Changed

- **CLI parsing migrated from stdlib `flags` to `[deps.cmdit]` 1.1.0** — `flags_new`/
  `flags_add_*`/`flags_parse`/`flags_get_*`/`flags_positional*`/`flags_error` →
  `cmdit_new`/`cmdit_bool|int|str`/`cmdit_parse`/`cmdit_get_*`/`cmdit_positional*`/
  `cmdit_error`. cmdit_new auto-registers `--help`/`-h` + `--version`/`-V`;
  `cmdit_parse` absorbs the hand-rolled `build_argv_array` materialize bridge (the
  256-arg cap and manual help/version registrations are gone — `src/main.cyr` −21 lines).
- **`src/main.cyr` `print_usage`** now calls `cmdit_help_flags` (cmdit 1.1.0's
  table-only renderer) for the flag rows, preserving anuenue's custom help framing.
- **Dropped stdlib dep `"flags"`**; added `[deps.cmdit]` (`../cmdit`, tag `1.1.0`).
  `"args"`/`"io"` retained (cmdit needs them).

## [1.1.3] — 2026-06-19 (toolchain + dep refresh)

Maintenance cut — toolchain pin advance plus the first-party-dep
sandhi refresh that had accumulated since v1.0.0. No behavioural
changes: all six golden fixtures stay byte-identical, the three
MONO equivalence checks hold, animation smoke (truecolor / 256 /
16 / long-cluster) passes, and perf is unchanged within host noise
(ASCII no-LF **46.59 ns/byte**, under the 60 ns/byte M5 cap). The
v1.x public API contract (flags / exit codes / output shape /
capability surface) is unchanged.

### Changed

- **Cyrius pin `6.1.14` → `6.2.24`** (`cyrius.cyml [package].cyrius`).
  `./lib/` re-synced to the new pin via `cyrius lib sync` (98 stdlib
  files updated).
- **`[deps.darshana]` `0.5.3` → `0.7.1`.** ANSI escape primitives.
  Filter + animation output byte-identical against the prior pin —
  the helpers anuenue calls (`tty_fg_rgb_buf`, `tty_sgr_reset_buf`,
  `tty_isatty`, `tty_sgr_buf`, `tty_fg_256_buf`, `tty_cursor_up`,
  cursor hide/show) are unchanged in shape.
- **`[deps.sakshi]` `2.2.5` → `2.4.0`.** Errors / tracing. Standard
  wiring; unreachable surface DCE-eliminated.
- **`[deps.agnostik]` `1.2.2` → `1.3.1`.** Shared Result / Error
  shapes. Standard wiring; unreachable surface DCE-eliminated.

### Fixed

- **`tests/anuenue.bcyr` missing `include "src/color.cyr"`.** The
  benchmark unit included `hsv.cyr` + `filter.cyr` but not
  `color.cyr`, so `filter.cyr`'s `ANUENUE_COLOR_MODE` reference
  resolved to nothing. cyrius 6.1.14 tolerated the dangling
  reference; 6.2.24 is stricter and errored
  (`undefined variable 'ANUENUE_COLOR_MODE'`). Added the include
  before `filter.cyr`, mirroring the test unit's include order.
  Latent since M6 (v0.7.0) added the color-mode dependency to the
  filter hot path; surfaced by the toolchain bump.

### Binary

- DCE size: 351 200 → **394 440 bytes** (+43 240 B) — the new
  toolchain + the three dep bumps. Still ~115 KB under the 512 KB
  cap; the gate's regression-detection role is intact.

### Notes

- `cyrius build`/`bench` now emit two `duplicate symbol`
  warnings from `lib/agnostik.cyr` (`ERR_TIMEOUT`, `ERR_UNKNOWN`,
  "last definition wins") plus several `undefined function`
  warnings for unreachable sakshi/agnostik surface (`map_new`,
  `tagged_new`, `trait_call0`, …). All are upstream-dep artifacts
  on unreachable code that DCE eliminates; anuenue's output and
  capability surface are unaffected. Not anuenue's to fix —
  flagged here for the next dep audit.

## [1.1.2] — 2026-06-08 (agnos argv fix)

### Changed

- cyrius toolchain pin 6.0.56 → 6.1.14.

### Fixed

- **agnos: `anuenue TEXT` positional args weren't seen.** Call `main` from a bare top-level statement (`_agnos_entry();`) instead of `var r = main();`. The latter runs `main` as a module-global initializer, *before* cyrius's init-stack capture, so `argc()`/`argv()` read 0/null. cyrius issue: agnos argv init-rsp capture.

## [1.1.1] — 2026-06-07

**Positional-text mode — usable on AGNOS today.** `anuenue TEXT...` now rainbow-tints its argv (joined by spaces, one trailing newline) and exits, instead of only ever reading stdin. This closes the 1.1.0 "no argv-passing yet — has no EOF to exit cleanly (reboot to leave)" gap: agnos has no shell pipes and no stdin EOF, so the pure pipe filter could never terminate there. Passing text as arguments mirrors `bnrmr TEXT` — `run /bin/anuenue AGNOS` is now a one-shot rainbow. The stdin pipe filter stays the canonical use on a real TTY pipeline; positional args are additive. The v1.x public API contract (flags / exit codes / output shape) is unchanged.

### Added

- **`anuenue TEXT...` positional-text mode** (`src/main.cyr` `anuenue_text_args`, `src/filter.cyr` `anuenue_render_bytes`). Any non-flag argument routes to a one-shot render of the joined args + newline; zero args keeps the existing stdin filter. Checked before the MONO short-circuit, so `--no-color anuenue TEXT` writes plain bytes without ever touching stdin. `anuenue_render_bytes` reuses the filter's exact cluster-coloring rules (per-cluster fg escape, ZWJ/RI grapheme folding, phase advance per non-extending cluster) with no chunk-carry, since the whole buffer is in memory.
- Help text + examples updated with the `anuenue [OPTIONS] TEXT...` usage line.

### Notes

- Pairs with the agnos-side line-discipline EOF (Ctrl-D) added the same day: `read(fd 0)` now returns 0 on Ctrl-D, so the stdin filter path can also terminate on agnos for interactive use. Positional-text mode remains the ergonomic one-shot path (no pipes there yet).

## [1.1.0] — 2026-06-07

**Builds for AGNOS (`--agnos`).** anuenue now compiles for the sovereign target and runs as a static ELF64 on the agnos kernel (staged on the agnos-fs `/bin` alongside agnsh/cmdrs/bnrmr/klug). Pairs with the agnos 1.43.1 FB-console ANSI/SGR interpreter — the kernel framebuffer now renders the per-character 256-colour rainbow anuenue emits (screendump-confirmed). The v1.x public API contract (flags / exit codes / output shape) is unchanged; this is a portability minor, same lane as commandress 1.1.0 / bannermanor 1.1.0.

### Changed

- **Cyrius pin `6.0.1` → `6.0.56`** (`cyrius.cyml`) — the toolchain that carries `CYRIUS_TARGET_AGNOS` (landed cyrius 6.0.55); `./lib/` re-vendored at the new pin. Linux/host build unaffected.

### Added

- **Two `#ifdef CYRIUS_TARGET_AGNOS` gates** for the agnos exec/TTY surface (host behaviour untouched):
  - `_open_exit_signalfd` (`src/animate.cyr`) returns `-1` on agnos — no terminal-signal generation yet (no Ctrl-C → SIGINT), so the signalfd exit-cleanup is a no-op (the function's documented fall-back); also sidesteps darshana's Linux-gated `TTY_SIGMASK_EXIT`.
  - the `tty_isatty` colour-autodetect (`src/color.cyr`) is skipped on agnos (no `isatty`/`ioctl`); output is the FB console with no `> file` redirection yet, so colour is left on (falls through to the 16-colour default).

### Notes

- On agnos, anuenue reads the keyboard (fd 0) — no pipes / argv-passing yet — so it rainbow-tints typed lines live but has no EOF to exit cleanly (reboot to leave). File-arg + pipe support follow the agnos userland-env arc (envp/execwait argv).

## [1.0.0] — 2026-05-22

**GA.** anuenue v1.0.0 — the Cyrius-native rainbow pipe filter,
founder of the AGNOS pipe-decorator family. Tagged on user signal
per [feedback_no_unprompted_version_bumps](https://github.com/MacCracken/agnosticos/blob/main/.claude/projects/-home-macro-Repos-agnosticos/memory/feedback_no_unprompted_version_bumps.md).
The public API contract — flag set, exit codes, capability surface,
output shape — is frozen for the v1.x line. Sandhi bumps within v1.x
will follow the established darshana 0.5.x cadence (proposal → swap →
goldens unchanged → cap re-evaluated).

Scaffolded `cyrius init anuenue` 2026-05-21; ten releases landed
across two calendar days. The v1.0 contract:

| Surface | Shape |
|---------|-------|
| **Input** | stdin only. UTF-8 decoded; invalid sequences degrade per byte ([ADR 0003](docs/adr/0003-grapheme-cluster-cycling.md)). |
| **Output** | stdout: input bytes tinted with ANSI fg escapes. stderr: usage + errors only. ANSI fg only — no bold / italic / underline ([ADR 0001](docs/adr/0001-pipe-purity.md)). |
| **Flags** | `-h` / `-V` / `-p` / `-s` / `-F` / `-a` / `-d` / `-S` / `-n` / `-C` / `-c` (11 total). Every flag documented in `docs/guides/`; every flag exercised in `tests/anuenue.tcyr`; every flag behaviour matches docs (M7 surface freeze). |
| **Exit codes** | 0 success (incl. `--help` / `--version`); 1 runtime error; 2 usage error. |
| **Capability surface** | `read(0)` / `write(1,2)` / `brk` / `exit` / bounded `open` + `close` (for `/proc/self/cmdline` + `/proc/self/environ`) / `ioctl(TIOCGWINSZ)` via darshana / animation-only `rt_sigprocmask` + `signalfd4` + `nanosleep`. No `sys_system`, no `fork`, no `execve`, no `socket`, no `connect`. Documented exhaustively in [`docs/audit/2026-05-22-audit.md`](docs/audit/2026-05-22-audit.md) § Finding 2. |
| **Colour modes** | TRUECOLOR / COLOR_256 / COLOR_16 / MONO selected via the priority chain: `--color <mode>` → `--no-color` → `NO_COLOR` env → stdout-not-TTY (unless `--force-color`) → `COLORTERM` → `TERM`. MONO is a true `cat`-shaped byte-identical passthrough. |
| **HSV phase model** | Integer 6-sector S=V=1 rainbow (`src/hsv.cyr`); 1530-unit phase space; no floating point anywhere ([ADR 0002](docs/adr/0002-hsv-inline-not-abaco.md)). |
| **Grapheme classifier** | Practical-subset extending-codepoint table (21 ranges); ZWJ + RI latches; explicit Hangul/Devanagari/tag-sequence trade-offs documented ([ADR 0003](docs/adr/0003-grapheme-cluster-cycling.md)). |
| **Animation** | `-a` / `-d <s>` / `-S <speed>`; 64 KB input cap; 16 ms frame interval; non-blocking signalfd for clean SIGINT cursor restore. |
| **Performance** | 45–50 ns/byte ASCII no-LF (M5 acceptance ≤60 ns/byte); 41 ns/byte UTF-8 mixed. |

### v1.0 acceptance — final scorecard

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Public CLI surface frozen | ✅ M7 / v0.8.0 |
| 2 | UTF-8 correct by default | ✅ M3 / v0.4.0 |
| 3 | TTY-aware | ✅ M6 / v0.7.0; sandhi closeout v0.7.1 |
| 4 | Color-mode negotiation | ✅ M6 / v0.7.0 |
| 5 | Animation parity with `lolcat -a` | ✅ M4 / v0.5.0 |
| 6 | Per-character overhead measured | ✅ M5 / v0.6.0 |
| 7 | Dogfooded in real AGNOS pipelines | ⏸ deferred to post-1.0 organic adoption |
| 8 | Security audit pass | ✅ M8 / v0.8.0 — 1 HIGH (fixed in-cycle), zero HIGH+ open |
| 9 | CHANGELOG complete | ✅ maintained at every cut |
| 10 | Downstream gate (consumer green) | ⏸ deferred to post-1.0 organic adoption |

8/10 met at tag time. The two open items both block on external
consumer wiring (anticipated: `agnoshi` MOTD pipeline composition or
`iam`'s default login splash). Both are post-1.0 organic-adoption
work — the v1.0 *contract* is frozen, *adoption* is not a contract
property the project itself can satisfy unilaterally. The contract
freeze is what makes adoption tractable; v1.0 ships so consumers can
build against a stable target.

### Quality bar at v1.0.0

| Gate | Number |
|------|--------|
| Unit assertions (`tests/anuenue.tcyr`) | 245 across 36 groups |
| Golden fixtures + equivalence checks | 10 byte-identical fixtures + checks |
| Animation smoke checks | 18 structural assertions |
| Fuzz assertions (`fuzz/*.fcyr`) | 1,354,580 per run across 5 harnesses |
| Security audit HIGH+ findings open | 0 |
| DCE binary size | 351,200 B (~343 KB) |
| Cyrius lint warnings | 0 across all 6 source files |

### Dependencies pinned for v1.x

| Dep | Tag | Note |
|-----|-----|------|
| `darshana` | 0.5.3 | ANSI escape primitives. Sandhi cycle 0.5.1 → 0.5.2 → 0.5.3 established the proposal pattern; v1.x follows same cadence on future bumps. |
| `sakshi` | 2.2.5 | Errors / tracing. AGNOS first-party-standards-required. |
| `agnostik` | 1.2.2 | Result / Error shapes. |
| Cyrius stdlib | 6.0.1 (toolchain pin) | `string`, `fmt`, `alloc`, `io`, `vec`, `str`, `syscalls`, `assert`, `bench`, `args`, `flags`, `chrono`. |

### Post-v1.0 expectations

- **API contract frozen** for v1.x. Breaking changes get a v2.0
  bump; sandhi bumps within v1.x can update internal helpers /
  perf surface but not the user-visible contract above.
- **Sandhi cadence** continues — darshana / sakshi / agnostik
  bumps get the proposal → swap → goldens-unchanged pattern that
  ran three times for darshana through v0.7.1.
- **Adoption is organic.** `agnoshi` MOTD chain and `iam` login
  splash are the anticipated first consumers; v1.x patch cuts will
  fix anything those find. The contract is stable for them to
  build against.
- **Fuzz harness** stays in CI. Each new fuzz target opens a new
  `fuzz/*.fcyr` file; existing harnesses don't change unless
  their target surface changes.

The brand IS the rainbow. ānuenue.

## [0.9.0] — 2026-05-22

Post-v0.8.0 quality slot — no behavioural changes, no flag-surface
changes, no dep bumps. Three threads land together:

1. **Fuzz harness populated.** The carry-forward `tests/anuenue.fcyr`
   stub (deferred since M0) is gone; in its place a real `fuzz/`
   directory with five harnesses targeting every surface the M8
   audit identified. `cyrius fuzz` is now CI-gated.
2. **Animation smoke coverage broadens.** `scripts/animate-smoke.sh`
   used to exercise only `--color=24bit`. The M5 phase cache + the
   M6 colour-mode-aware escape build + the M8 mid-cluster flush
   guard all wire through `_render_frame` — the new `--color=256` /
   `--color=16` smoke sections confirm each per-mode escape path
   completes a frame cycle and emits the right SGR shape.
3. **Structural cleanup.** The M0-anticipated `src/hsv.cyr` split
   finally lands (HSV→RGB integer math + `ANUENUE_PHASE_MOD` now
   live in their own file). `src/main.cyr` flag registrations got
   a column-width pass (closing the 5 pre-existing lint warnings
   flagged during the v0.8.0 closeout).

### Added

- **`fuzz/` directory populated** with five harnesses driving the
  surface the M8 audit identified. Each harness uses a Knuth-MMIX
  LCG (the sankoch pattern) for deterministic seed-driven
  exploration, layers invariant checks via `assert(…)` + `assert_eq(…)`,
  and returns `assert_summary()` from `main()` so any failing
  assertion sets a non-zero exit code (the `assert` library
  prints-but-doesn't-abort; without this, a failing fuzz
  invariant would silently pass CI). Combined assertion count:
  **1 354 580** across the five harnesses, all green at v0.9.0
  candidate.
  - **`fuzz/flag-parser.fcyr`** (M2 target) — drives `flags_parse`
    with random argv arrays built from a 40-token pool (valid
    short/long flags, valid integer values, intentionally bad
    ints, unknown flags, bundled forms, plain strings). Asserts
    `rc ∈ {0, -1}` (the documented lib return shape — *not*
    `rc >= 0`, which was the harness's own original bug caught on
    first run), `flags_error ∈ {NONE, UNKNOWN, MISSING_VALUE,
    BAD_INT, BUNDLED}`, and `rc == 0 ↔ err == NONE`. Includes the
    empty-argv edge case and a per-flag solo-walk catching "long
    form missing" regressions.
  - **`fuzz/utf8.fcyr`** (M3 target) — `utf8_seq_len` over random
    bytes (every result ∈ {0..4}); short-buffer truncation (if
    `seqlen > 0` then `seqlen ≤ n - i` — no over-read);
    `utf8_decode` round-trip (codepoint in `[0, 0x1FFFFF]` for
    any validated sequence); `cp_is_extending` /
    `cp_is_regional_indicator` totality over the full i64 range.
  - **`fuzz/pretag-clusters.fcyr`** (M4 target) — `_pretag_clusters`
    over random / ASCII / long-cluster (M8 attack shape) /
    cap-exhaustion corpora. Asserts the cluster-table invariants
    the M8 audit § Finding 5 listed (`n_clusters ≤ max_clusters`,
    sentinel in `[0, n_bytes]`, offsets non-decreasing, never
    writes past `ctab[max_clusters]`).
  - **`fuzz/emit-phase-esc.fcyr`** (M5 target) — `_emit_phase_esc`
    with extreme phase values (zero, ±MOD, ±MOD-1, i64::MAX,
    near-i64::MIN) + random i64 phases, under all four colour
    modes (TRUECOLOR / 256 / 16 / MONO). Front/back sentinel bytes
    bracket the line buffer; the harness asserts neither sentinel
    is clobbered, no write before `pos` or after `new_pos`, and
    `new_pos - pos ≤ 24` (the entry payload bound).
  - **`fuzz/rgb-quantizers.fcyr`** (M6 target) — `_channel_to_6`,
    `_rgb_to_256`, `_rgb_to_16` over both in-range and full-i64
    inputs. Asserts bucket / palette-index bounds (cube floor =
    16, ceiling = 231; bright-16 floor = 91, ceiling = 97).
- **`scripts/animate-smoke.sh` non-truecolor sections** — new
  `--color=256` and `--color=16` runs under `-a`. Each asserts
  clean exit, non-empty output, full cursor lifecycle (hide /
  cursor-up / show), and the right per-mode SGR shape (CSI
  `38;5;Nm` for 256; CSI `9[1-7]m` for 16; explicit no-leak check
  that truecolor `38;2;…` doesn't appear under `--color=256`).
- **`src/hsv.cyr`** — new file holding `ANUENUE_PHASE_MOD` and
  `hsv_rainbow(phase, out_rgb)`. The M0-anticipated split that
  had been deferred at every cut on the "wait for a second
  consumer" rule; the fuzz harness's `emit-phase-esc` target was
  the second consumer. `main.cyr` / `filter.cyr` / `animate.cyr`
  / `tests/anuenue.tcyr` / `tests/anuenue.bcyr` all updated to
  `include "src/hsv.cyr"` before `filter.cyr` (which references
  `ANUENUE_PHASE_MOD`).

### Changed

- **`src/main.cyr` flag-registration column widths.** The 11
  `flags_add_*` lines were over the 120-column lint threshold by
  varying amounts (the M4 `-d` line ran to 144; the M6
  `--no-color` / `--force-color` / `--color` block to ~150). Each
  now uses a continuation indent for the help-text argument when
  it doesn't fit on the registration line, and the short-flag
  `# 'x'` trailing comment moved into a single block-level comment
  above the registrations (the short-char codes are the
  first-arg integer literals anyway). 5 pre-existing
  `cyrius lint` warnings on `src/main.cyr:118-122` cleared.

### Removed

- **`tests/anuenue.fcyr` stub** — `cyrius fuzz` looks at `fuzz/*.fcyr`
  not `tests/*.fcyr`; the empty stub at the wrong path served no
  purpose and would have confused the next contributor wondering
  why `cyrius fuzz` reported "No fuzz harnesses found in fuzz/".

## [0.8.0] — 2026-05-22

M7 (docs) + M8 (security audit) folded into one cycle — the audit
turned up one HIGH-severity finding small enough to fix in-cycle,
so v0.8.0 ships the doc set + the closing fix in a single cut
rather than splitting M7/M8 across two releases. Zero HIGH+
findings open at the end of the audit (see
[`docs/audit/2026-05-22-audit.md`](docs/audit/2026-05-22-audit.md)).

### Added

- **`docs/adr/0001-pipe-purity.md`** — formal record of the
  stdin → stdout / no-config / no-themes constraint. Documents the
  capability surface (read/write/brk/exit + bounded
  open/close/ioctl for cmdline + environ + isatty), the two
  deliberate relaxations (M4 64 KB animation buffer; M6 MONO
  passthrough), and the alternatives considered (lolcat-shaped
  file-input surface, theme env vars, no-animation-at-all). The
  rule that shapes everything else.
- **`docs/adr/0002-hsv-inline-not-abaco.md`** — formal record of
  the "don't pull abaco for ~30 lines of integer math" decision.
  Notes the two post-v1.0 revisit triggers (a second pipe-
  decorator wanting HSV; user-supplied colour expressions becoming
  a real ask) and the Cyrius-stdlib alternative if stdlib ever
  ships a `color` module.
- **`docs/adr/0003-grapheme-cluster-cycling.md`** — formal record
  of the practical-subset classifier shipped at M3. Documents the
  21 covered ranges, the explicit misses (Hangul L/V/T composition;
  Devanagari spacing marks; tag sequences), and the monotonic
  upgrade path to full UAX #29 if a v2 release wants it. Closes
  out the long-standing carry-forward from
  [`docs/development/state.md`](docs/development/state.md).
- **`docs/guides/integrating-anuenue.md`** — integration guide for
  downstream tool authors (iam, bnrmr, agnoshi, future MOTD
  participants). Covers the contract table (input / output /
  errors / exit codes / state / concurrency), the full capability
  surface, TTY detection + colour-mode chain, the three
  integration patterns (direct compose / opt-in env var /
  programmatic), and a testing harness pattern (determinism +
  NO_COLOR equivalence).
- **`docs/examples/` populated** — eight runnable shell scripts
  exercising the full M2/M3/M4/M6 surface: `01-hello-rainbow.sh`,
  `02-deterministic-seed.sh`, `03-utf8-clusters.sh`,
  `04-motd-pipeline.sh`, `05-color-mode-override.sh`,
  `06-no-color.sh`, `07-animation.sh`, `08-force-color.sh`. Each
  cites the source symbol + ADR it demonstrates. README.md is an
  index. The v1.0 acceptance criterion "every public symbol cited
  from at least one example" lands here.

### Changed

- **`print_usage` Examples section refreshed** in `src/main.cyr`.
  The previous text only covered the M1/M2 flags (`-p`, `-s`);
  now `--help` shows seven canonical invocations covering `-p`,
  `-s`, `-a`, `NO_COLOR`, `--color=256`, `--color=16`, and
  `--force-color | tee`. Closes the M7 carry-forward in
  [`docs/development/state.md`](docs/development/state.md). Stderr-
  only emission, so pipe-purity holds.
- **`docs/adr/README.md`** — index populated; previous "no ADRs
  yet" placeholder replaced by the three-row table above.

### Fixed

- **`scripts/animate-smoke.sh` — POSIX-printf portability.** The
  M8 long-cluster regression initially used `printf '\xcc\x81'`
  to emit the U+0301 combining acute. `\xNN` hex escapes are a
  bash extension; POSIX `printf(1)` requires `\NNN` octal. CI
  runs the smoke test under dash, which ignored the hex form
  silently — the smoke loop sent ASCII `\xcc\x81` text instead
  of the combining-acute bytes, so the byte-preservation
  assertion counted zero combiners and failed the run with a
  misleading "mid-cluster flush dropped bytes?" message.
  Switched to the POSIX octal form (`printf '\314\201'`); bash
  + dash + busybox-sh all interpret it as the two bytes 0xCC
  0x81. Test result unchanged on bash; CI under dash now
  receives the correct adversarial input and exercises the
  mid-cluster flush guard as intended.

### Security

- **HIGH (fixed in this cut)**: `_render_frame` heap overflow on
  long-cluster animation input. The pre-fix code wrote a full
  cluster's bytes into `line_buf` (32 KB) before checking
  `ANUENUE_FLUSH_RESERVE`. Adversarial input shaped as `[base
  char][N × U+0301]` with `N ≈ 32 500` produces a single
  grapheme cluster ~65 KB long (per the practical-subset
  classifier from [ADR 0003](docs/adr/0003-grapheme-cluster-cycling.md));
  the cluster bytes overflowed `line_buf` by ~32 KB, corrupting
  the adjacent `_PHASE_ESC_TABLE` allocation. Fix: mid-cluster
  flush guard in `_render_frame`'s byte-copy loop — flush + re-
  emit the same phase escape whenever the reserve threshold trips
  mid-cluster, so visible colour stays consistent and the buffer
  never overruns. Filter path (`anuenue_filter` in
  `src/filter.cyr`) was *not* affected because it writes one
  codepoint per iteration and checks the reserve between each;
  fix is local to `src/animate.cyr`. Regression coverage:
  `scripts/animate-smoke.sh` now runs the historical attack
  pattern (16 000 combiners after a base char) and asserts both
  clean exit and full byte preservation through the mid-cluster
  flushes; `tests/anuenue.tcyr` group "M8 audit —
  _pretag_clusters long-combiner chain" locks the pre-tag
  invariant at the unit-test level. Full audit findings (HIGH
  +9 INFO/LOW) recorded in
  [`docs/audit/2026-05-22-audit.md`](docs/audit/2026-05-22-audit.md).
- **Audit pass (M8 acceptance)**: zero HIGH+ findings open at
  the end of the audit. Capability surface confirmed clean (no
  `sys_system`, no `fork`/`execve`, no `socket`/`connect`); open/
  close bounded to `/proc/self/cmdline` + `/proc/self/environ`;
  UTF-8 surface degrades gracefully on every adversarial input
  tried; phase arithmetic absorbs any user-supplied seed/offset
  via modulo normalization. Full v1.0 capability baseline
  recorded in the audit doc.

## [0.7.1] — 2026-05-22 — Sandhi closeout (darshana 0.5.3)

The M6 follow-up cut. Closes the sandhi-coordination loop opened
in v0.7.0: anuenue's three inline `_*_compat` stand-ins
(`_isatty_compat`, `_fg_256_buf_compat`, `_sgr_buf_compat`) are
gone, replaced by darshana 0.5.3's `tty_isatty` / `tty_sgr_buf` /
`tty_fg_256_buf`. The swap is signature-identical — all 6 golden
fixtures remain byte-identical against v0.7.0, all 241 unit tests
still pass, and the ASCII no-LF perf figure actually drops ~1 ns/byte
(darshana 0.5.3's helpers are slightly tighter than the stand-ins
were). Binary-cap discipline raised here too — the M5 350 KB cap
was tightened against the M6 surface and broke by 488 bytes after
the swap; per the state.md M7-closeout note, the cap moves to 512 KB
for the rest of the v0.7.x / v0.8.x / v0.9.x line.

### Changed

- **`[deps.darshana]` pinned 0.5.2 → 0.5.3** alongside the
  removal of the M6-era inline stand-ins. Darshana 0.5.3 ships
  `tty_isatty(fd)`, `tty_sgr_buf(buf, pos, code)`, and
  `tty_fg_256_buf(buf, pos, n)` per the sandhi-coordination
  proposal at
  [`sandhi/docs/proposals/2026-05-22-darshana-color-mode-helpers.md`](https://github.com/MacCracken/sandhi/blob/main/docs/proposals/2026-05-22-darshana-color-mode-helpers.md).
- **DCE-binary cap raised 350 KB → 512 KB.** The 350 KB number
  was an M5 acceptance criterion sized against the M5 surface;
  M6's `src/color.cyr` (+ stdlib `streq`/`strstr`/`getenv` pulls)
  put us 168 B under it, and the darshana 0.5.3 swap nudged us
  488 B *over* it. Three responses considered: trim ~500 B of
  dist baggage (fragile), fold into M7's v0.8.0 (mixes
  behavioural + doc cycles), or raise the cap now (chosen). The
  512 KB number gives clear runway through M7 / M8 / v1.0
  without changing the gate's role — every minor cut still
  records DCE size and the gate still fires on regressions
  meaningfully larger than the bumps M3/M4/M5/M6 each cost.
  Already flagged for M7 closeout in `docs/development/state.md`
  — landing the policy shift here, in the same slot as the
  swap that exposed it, instead of letting [Unreleased] drift.

### Removed

- `_isatty_compat`, `_fg_256_buf_compat`, `_sgr_buf_compat` in
  `src/color.cyr` — replaced by darshana 0.5.3's
  `tty_isatty` / `tty_fg_256_buf` / `tty_sgr_buf`. ~50 LOC
  removed. Call sites in `color.cyr` (detect path) and
  `filter.cyr` (`_phase_esc_init` mode branches) rewritten.
  Tests in `tests/anuenue.tcyr` updated to call the darshana
  forms; assertions count unchanged at 241 passing. Golden
  check passes byte-identically (256-color and 16-color
  fixture outputs match the v0.7.0 bytes exactly — the
  signature-identical swap was correct).

### Performance

`scripts/perf-bench.sh` (truecolor, median of 7 runs):

| Corpus           | v0.7.0  | v0.7.1  | Δ       |
|------------------|---------|---------|---------|
| ascii (no LF)    | 46.99   | 45.99   | −1.0    |
| ascii (w/ LFs)   | 50.93   | 49.85   | −1.1    |
| utf8 mixed       | 43.88   | 42.38   | −1.5    |

Small but consistent wins across all three corpora. darshana
0.5.3's helpers are marginally tighter than the inline stand-ins
were (likely fewer redundant bounds checks; the stand-ins each
had an explicit `if (n < 0)` / `if (n > 255)` pair that may now
fold into darshana's existing reject path).

### Binary

DCE size: 349 832 → **350 488 bytes** (+656 B). The swap was
expected to *recover* ~1–2 KB (per the sandhi proposal estimate);
instead it added 656 B as the linker pulled in darshana 0.5.3's
new fn bodies plus their transitive helpers (likely `tty_itoa`,
which `tty_sgr_buf` uses for 3-digit SGR codes — wasn't
reachable from the M6 stand-ins because `_sgr_buf_compat` used
the more limited `_ansi_emit_u8` directly). The proposal
estimate was wrong; the gauntlet caught it. Cap raised to 512 KB
(see above) — leaves ~161 KB headroom for M7 / M8 / v1.0.

### Sandhi closeout

This cut closes the third turn of the same crank — the sandhi
loop opened at v0.7.0 (anuenue M6) ↔ darshana 0.5.3:

| | anuenue side                        | darshana side                  |
|---|-------------------------------------|--------------------------------|
| open | v0.7.0 stand-ins + proposal filed | (work in flight)              |
| close | **v0.7.1 swap (this cut)**       | 0.5.3 (out before this slot)  |

Pattern's prior turns: anuenue 0.2.0 ↔ darshana 0.5.1 (truecolor
unlock); anuenue 0.5.0 ↔ darshana 0.5.2 (relative cursor). Recorded
here so future audits can grep the pattern.

## [0.7.0] — 2026-05-22 — M6: Color-Mode Negotiation

The four-mode cut. anuenue stops assuming 24-bit truecolor and
adapts: TRUECOLOR / 256-color / 16-color / MONO selected at startup
from a priority chain — `--color <mode>` override → `--no-color` →
`NO_COLOR` env → stdout-not-TTY (unless `--force-color`) → COLORTERM
→ TERM. M6 acceptance held: `NO_COLOR=1 echo X | anuenue` is byte-
identical to `echo X`, asserted by golden-check.sh's new MONO checks.
M5 truecolor perf is unchanged (the phase-cache shape stays the same;
only the per-entry bytes vary between modes). New module: `src/color.cyr`.

### Added

- **M6 — Color-Mode Negotiation.** Four-mode taxonomy with
  detection priority:
  1. `--color <auto|24bit|truecolor|256|16|none|off|never>` override
  2. `--no-color` flag → MONO
  3. `NO_COLOR` env (any value, per [no-color.org](https://no-color.org)) → MONO
  4. stdout not a TTY AND `--force-color` not set → MONO
  5. `COLORTERM` is "truecolor" / "24bit" → TRUECOLOR
  6. `TERM` contains "-direct" → TRUECOLOR; "256color" → COLOR_256
  7. Fallback on a TTY → COLOR_16 (safest visible default)
- **`src/color.cyr`** — new module, ~200 lines:
  - Mode enum (`ANUENUE_COLOR_MONO` / `_16` / `_256` / `_TRUE`).
  - `_color_override_from_str` / `_color_mode_from_override` —
    string-flag parsing + enum mapping.
  - `_channel_to_6` / `_rgb_to_256` — 6×6×6 cube quantization
    using xterm's canonical channel midpoints `{48, 115, 155,
    195, 235}`. Skips the 24-step grayscale ramp because the
    HSV rainbow never hits R == G == B at non-vertex phases.
  - `_rgb_to_16` — maps (R≥128, G≥128, B≥128) bright-flag triple
    to one of `{91, 92, 93, 94, 95, 96}` for the six rainbow
    sectors; white (97) as a defensive fallback.
  - `anuenue_detect_color_mode(no_color, force_color, override)`
    — combines all priority rules; reads `getenv` + the
    `_isatty_compat` stand-in.
  - `anuenue_passthrough()` — required MONO bypass; tight read/
    write loop with no escape emission. Capability surface
    matches `cat`: read(0) + write(1) only.
- **Three flags wired in `src/main.cyr`**:
  - `-n` / `--no-color` (bool) — force MONO.
  - `-C` / `--force-color` (bool) — emit colour even when stdout
    isn't a TTY. Useful for `anuenue --force-color | tee out.log`.
  - `-c` / `--color <mode>` (str) — explicit override; the test
    hook the golden suite uses to pin a mode regardless of the
    runner's TTY state.
- **`_phase_esc_init` is mode-aware**. Branches on
  `ANUENUE_COLOR_MODE` to populate the 1 530-entry table with the
  per-mode escape: 13–19 bytes/entry for TRUECOLOR (unchanged),
  8–11 for COLOR_256, 5 for COLOR_16. The hot-path emit
  (`_emit_phase_esc`) is byte-shape-agnostic — same memcpy.
- **69 new tcyr assertions across 6 groups** in
  `tests/anuenue.tcyr`: mode enum + override parser + bright-
  palette quantization across the 6 rainbow corners + 256-cube
  bucket boundaries at every threshold (48 / 115 / 155 / 195 /
  235) + `_rgb_to_256` canonical hues + `_fg_256_buf_compat` /
  `_sgr_buf_compat` escape framing + bounds rejection.
- **`tests/golden/agnos-rainbow-256-s100.out`** (160 B) +
  **`tests/golden/agnos-rainbow-16-s100.out`** (82 B) — new
  fixtures pinning the 256 and 16 mode outputs.
- **MONO acceptance in `scripts/golden-check.sh`** — three
  invariants asserted: `NO_COLOR=1 anuenue` == cat; `--no-color
  anuenue` == cat; `--color=none anuenue` == cat. The
  byte-identical equivalence is the M6 acceptance, derived from
  https://no-color.org.

### Sandhi pending

darshana 0.5.3 (sandhi in flight, third turn of the same crank
that produced 0.5.1 / 0.5.2) ships:

  - `tty_isatty(fd)` — proper isatty primitive
  - `tty_sgr_buf(buf, pos, code)` — buf variant of `tty_sgr`
  - `tty_fg_256_buf(buf, pos, n)` — 256-color fg escape emitter

anuenue M6 implements the bodies inline as `_isatty_compat`,
`_sgr_buf_compat`, `_fg_256_buf_compat` in `src/color.cyr` with
`TODO(sandhi 0.5.3)` markers. When darshana 0.5.3 lands, the bump
is mechanical: pin darshana 0.5.2 → 0.5.3, sed-replace the three
compat call sites, delete the three stand-ins. ~1-2 KB binary
recovered.

### Changed

- `src/filter.cyr` — `_phase_esc_init` reads `ANUENUE_COLOR_MODE`
  and branches between four payload encoders (TRUECOLOR via
  `tty_fg_rgb_buf`, COLOR_256 via `_fg_256_buf_compat`,
  COLOR_16 via `_sgr_buf_compat`, MONO → zero-length entries
  unreached because main.cyr dispatches to passthrough first).
- `src/main.cyr` — three new flags; new dispatch step calls
  `anuenue_detect_color_mode` and writes `ANUENUE_COLOR_MODE`
  before filter/animate run; MONO routes to `anuenue_passthrough`.
- `scripts/golden-check.sh` — fixtures invoke with explicit
  `--color=24bit` so they're deterministic regardless of the
  runner's TTY state. New M6 fixtures + MONO acceptance.
- `scripts/animate-smoke.sh` — invokes with `--color=24bit` for
  the same reason; animation always exercises the truecolor path.
- `scripts/perf-bench.sh` — invokes with `--color=24bit` to bench
  the filter path, not MONO passthrough. Methodology comparable
  with the v0.6.0 figures.
- `tests/anuenue.tcyr` — now also includes `src/color.cyr`.

### Performance

`scripts/perf-bench.sh` (truecolor) is unchanged from v0.6.0
within host noise: ASCII no-LF ≈ 46.5 ns/byte; UTF-8 mixed
≈ 43 ns/byte. MONO is observably as fast as `cat` (perf-bench
without `--color=24bit` shows 0 ns/byte overhead — the
passthrough surface is read(0) + write(1) only).

### Capability surface

Filter path (when colour active): unchanged from v0.6.0 —
read(0) / write(1) / brk(12) / exit(60) / open(2)+read+close on
`/proc/self/cmdline` (args_init) and now on `/proc/self/environ`
(getenv at startup). Animation path keeps its M4 deltas
(rt_sigprocmask, signalfd4, nanosleep). M8 audit will record the
v0.7.0 set as the v1.0 candidate.

### Binary

DCE size: 335 160 → **349 832 bytes** (+14 672 B for the M6
color module + flag wiring + stdlib pulls — `streq`, `strstr`,
`getenv`). 168 B headroom under the M5 cap of 350 KB; the darshana
0.5.3 sandhi will recover ~1-2 KB when the three stand-ins go.
M6-and-beyond cap should be raised in the M7 closeout — 512 KB
gives clear runway through v1.0 without changing the discipline.

## [0.6.0] — 2026-05-22 — M5: Performance Pass

The hot-path-recovery cut. Three layered optimisations against the
M3 ASCII regression: an ASCII short-circuit that skips the UTF-8
decoder + cluster classifier on `b < 0x80`, a binary-searched range
LUT replacing the 21-condition `cp_is_extending` chain, and a
pre-baked 1 530-entry escape table indexed by `phase % MOD` that
collapses `hsv_rainbow + tty_fg_rgb_buf` into a single memcpy on
the hot path. Result on the canonical 1.4 MB base64-ASCII corpus:
**91.6 → 47.0 ns/byte (−48.7%)** — beats the v0.3.0 53 ns/byte
floor that M3 had regressed. All four M3 goldens remain byte-
identical; 26 new tcyr assertions lock the phase-cached escape
table's bytes to the runtime path. Binary stays under the 350 KB
DCE cap.

### Added

- **M5 — Performance Pass.** Three optimisations layered into the
  filter loop and the animation render loop:
  1. **ASCII short-circuit** — `if (b < 0x80)` branch in
     `anuenue_filter`'s inner walk and in `_pretag_clusters`'s
     classify pass. Skips `utf8_seq_len` + `utf8_decode` +
     `cp_is_extending` + `cp_is_regional_indicator` on every ASCII
     byte (which by construction can never be combining, RI, or
     multi-byte). The one edge case — ZWJ followed by ASCII —
     stays correct via the `prev_was_zwj` latch the fast path
     honours. Largest single win on MOTD-shaped traffic.
  2. **Binary-searched `cp_is_extending` LUT** — replaces the
     v0.4.0 21-range linear chain with a sorted `[lo, hi]` pair
     table and `O(log N)` lookup. Cheap reject for the common
     cases (`cp < 0x0300` or `cp > 0xE01EF`) skips the search
     entirely — covers CJK / Latin-1 / most-of-Unicode. Helps
     UTF-8-heavy non-Latin corpora; perf-neutral on ASCII
     (already short-circuited).
  3. **Phase-cached escape buffer** — 1 530-entry table indexed
     by `phase % ANUENUE_PHASE_MOD` holding pre-formatted
     `\x1b[38;2;R;G;Bm` escapes. Replaces `hsv_rainbow + 3×
     _ansi_emit_u8` (~53 ns/call) with one length-prefixed
     memcpy (~10 ns/call). 32-byte stride per entry (8-byte
     length + 19-byte payload + pad) — matches a cache-line
     fill. Heap-allocated at first-use (~80 μs once at startup),
     so the DCE binary doesn't grow.
- **`scripts/perf-bench.sh`** — scriptizes the end-to-end ASCII
  per-byte measurement docs/benchmarks.md kept describing
  manually. Generates a deterministic ASCII corpus + a UTF-8
  corpus, runs `cat fixture > /dev/null` and `anuenue < fixture
  > /dev/null` N times each, reports the median ns/byte
  overhead. Used to capture the M5 baseline AND prove each
  optimisation's win before claiming it.
- **26 new tcyr assertions in `tests/anuenue.tcyr`** under
  `M5 perf — phase-cached escape table`: `_phase_esc_init`
  idempotency, per-entry byte-identical round-trip against
  `hsv_rainbow + tty_fg_rgb_buf` (8 canonical phases including
  the wraparound corner), phase normalization (negative and
  `>MOD` phases hit the same entries as their canonical
  representatives), and table-layout invariants (32-byte
  stride, 13..19-byte entry length envelope).
- **`docs/benchmarks.md` § v0.6.0 — M5**: the three-point trend
  the roadmap acceptance called for (v0.3.0 → v0.4.0 → v0.6.0)
  plus the new perf-bench.sh-produced figures.

### Performance

End-to-end ASCII per-byte overhead, 1.4 MB base64-of-/dev/urandom
corpus, median of 7 runs:

| Path             | v0.5.0  | v0.6.0  | Δ       |
|------------------|---------|---------|---------|
| ascii (no LF)    | 91.6 ns | 47.0 ns | −48.7%  |
| ascii (w/ LFs)   | 95.0 ns | 51.0 ns | −46.3%  |
| utf8 mixed       | 66.3 ns | 43.0 ns | −35.1%  |

v0.6.0's ASCII no-LF figure (47 ns/byte) is **faster than the
v0.3.0 baseline (53 ns/byte)** — the M3 cluster-classification
regression is more than recovered. UTF-8 mixed is faster than
ASCII at v0.3.0 ever was; M3's per-cluster work amortises over
multi-byte payloads and the escape pre-computation skips the
expensive digit-encoding on every cluster.

### Changed

- `src/filter.cyr` — `cp_is_extending` rewritten as binary search
  over `_CP_EXT_TABLE`. New `_phase_esc_init` / `_emit_phase_esc`
  helpers + `_PHASE_ESC_TABLE` module-level pointer. The filter
  loop's hot path replaces the `hsv_rainbow + tty_fg_rgb_buf`
  pair (+ stack-allocated `var rgb[24]`) with a single
  `_emit_phase_esc` call.
- `src/animate.cyr` — same three changes mirrored: ASCII short-
  circuit in `_pretag_clusters`; `_render_frame` routes through
  `_emit_phase_esc`; per-frame stack-allocated `rgb[24]` dropped.
  `anuenue_animate` calls `_phase_esc_init()` at startup like
  the filter does.
- `src/main.cyr` — no behavioural change. `anuenue_filter` and
  `anuenue_animate` now both initialise the phase-cached escape
  table at entry; the cost is paid once per invocation and shared
  across both paths.

### Binary

DCE size: 334 120 → **335 160 bytes** (+1 040 B for the M5 helper
fns + LUT init code; the 48 KB phase-cache table itself is
runtime heap and doesn't bloat the binary). Well under the M5
acceptance cap of 350 KB DCE.

## [0.5.0] — 2026-05-22 — M4: Animation Mode

The lolcat-`-a` cut. Three new flags (`-a` / `-d` / `-S`) sit between
the M2 argv parser and a new `anuenue_animate` driver that buffers
stdin once, pre-tags grapheme clusters with the M3 state machine,
and repaints the buffered block at ~60 fps with the rainbow's phase
shifted per frame. Non-animation invocations are unchanged — the
v0.3.0 `-s 100` golden remains byte-identical, all four M3 fixtures
remain green. SIGINT / SIGTERM / SIGHUP cleanup is wired through a
non-blocking signalfd probe between frames: a Ctrl-C during
animation restores the cursor, resets SGR, and exits 0 instead of
killing the process mid-render.

### Added

- **M4 — Animation Mode.** `-a` / `--animate` enables animation;
  `-d <secs>` / `--duration` sets the run length in seconds (default
  5; `0` means "until SIGINT", mirroring lolcat); `-S <step>` /
  `--speed` sets the per-frame phase advance (default 1). Frame
  interval is hardcoded at 16 ms (~60 fps) — the M5 perf pass may
  expose this as a flag if a consumer asks.
- **`src/animate.cyr`** — new module, ~270 lines. Surface:
  - `_animate_slurp_stdin(buf, cap)` — reads stdin in a loop until
    EOF or capacity (64 KB ceiling); graceful truncation past the
    cap (the tail bytes simply don't animate).
  - `_pretag_clusters(buf, n, ctab, max)` — runs the M3 cluster
    state machine once over the buffered input, recording each
    cluster's start offset into `ctab` (one i64 per cluster + a
    sentinel slot holding the total byte count). 8 192-cluster
    cap; ~64 KB for the index. Cluster length per render is
    derived as `ctab[i+1] - ctab[i]` — no per-frame UTF-8 reparse.
  - `_count_lf_clusters` / `_input_ends_with_lf` — helper math
    for the cursor re-anchor distance and the trailing-CR
    decision.
  - `_render_frame(buf, ctab, n_clusters, phase_base, line_buf,
    ends_lf)` — walks the cluster table emitting fg-escape +
    cluster bytes into the same 32 KB line buffer the filter
    uses; flushes on LF / near-full / EOF. Tail emits SGR reset
    and a CR when input lacks a trailing LF, so the cursor lands
    at column 1 for the next frame's `tty_cursor_up` re-anchor.
  - `_open_exit_signalfd` / `_signal_pending` — non-blocking
    signalfd (SFD_NONBLOCK = O_NONBLOCK = 2048) masking
    HUP/INT/TERM. The frame loop probes the fd between sleep
    intervals and breaks cleanly when any exit signal arrives.
    Bypasses `darshana::tty_open_signalfd` (which creates a
    blocking fd for epoll-driven consumers) — the helper is the
    right shape for cyim/chakshu, wrong for anuenue's
    sleep_ms-driven cadence.
  - `anuenue_animate(duration_secs, speed)` — orchestrator.
    Hides the cursor, runs the frame loop, restores cursor +
    SGR on every exit path (clean / signal / read error / OOM).
- **42 new assertions across 9 groups** in `tests/anuenue.tcyr`:
  M4 constants sanity (defaults positive, SFD_NONBLOCK = 2048);
  `_pretag_clusters` over ASCII / combining diacritic / CJK /
  truncated UTF-8 / overflow cap; `_count_lf_clusters`;
  `_input_ends_with_lf`; M4 flag parsing (`-a` alone /
  `-a -d N -S M` / `--animate --duration=0`).
- **`scripts/animate-smoke.sh`** — structural guard for animation
  mode. Animation can't have a byte-identical golden (frame count
  varies with host load), so this script asserts the contract
  instead: exit 0 on duration-elapsed AND on SIGINT, cursor-hide
  + cursor-show framing present, at least one cursor-up emitted.
  Wired into CI as the **Animation smoke (M4)** step between
  Golden output and Version consistency.
- **`stdlib += chrono`** in `cyrius.cyml [deps].stdlib` — frame
  timing (`sleep_ms`) and deadline math (`clock_now_ns`).
  Standard AGNOS-userland chrono usage; same pin already used by
  every consumer needing wall-clock or monotonic time.

### Changed

- **darshana pin bumped** 0.5.1 → 0.5.2 — the v0.5.2 cut adds
  `tty_cursor_up(n)` (CSI `<n>A`) and `tty_cursor_down(n)` (CSI
  `<n>B`) to round out the cursor surface. Sandhi-unlock pattern,
  second turn of the same crank that produced 0.5.1 — anuenue is
  the consumer asking, darshana exposed the relative-cursor
  primitives, anuenue's pin advances to consume them. Pure
  additions on the darshana surface; M1/M2/M3 paths use only the
  previously-available helpers.

### Capability surface

- **Animation mode adds** three syscalls to anuenue's surface:
  `rt_sigprocmask(14)` (block exit signals), `signalfd4(289)`
  (open the non-blocking probe fd), `nanosleep(35)` (frame
  interval via chrono.sleep_ms). The filter path (no `-a`) keeps
  the M2 surface intact: `read(0)` + `write(1)` + `brk(12)` +
  `exit(60)` + `open(2)` / `close(3)` (one-shot, for
  `/proc/self/cmdline` at argv parsing). The M8 security audit
  will record these as the v1.0-frozen capability set.

### Pipe-purity deviation

Animation mode buffers up to 64 KB of stdin before rendering. This
deviates from the "no buffering beyond a line" rule the filter
loop enforces — animation needs a known-length block to repaint.
The deviation is bounded (input-buffer ceiling, cluster-table
ceiling) and limited to the `-a` invocation. ADR 0001
(pipe-purity, planned at M7) will record the rule and its single
animation-mode exception explicitly.

## [0.4.0] — 2026-05-21 — M3: UTF-8 Grapheme Awareness

The Unicode-correct-by-default cut. Filter cycles by grapheme
*cluster*, not byte: multi-byte CJK / combining marks / emoji-ZWJ
sequences / regional-indicator flag pairs all advance phase once
per visible glyph, not once per UTF-8 byte. ASCII fast-path stays
byte-identical (v0.3.0's `-s 100` golden remains green). Practical-
subset classifier — ships ~18 combining-mark ranges + ZWJ + VS + RI;
Hangul L/V/T and some Brahmic spacing marks misclassify as advancing
(errs on "more rainbow, not less"). ADR 0003 (M7) will record the
trade vs full UAX #29. Invalid UTF-8 → graceful per-byte degradation
(never panics). Chunk-boundary carry handles 4 096-byte read splits.

### Added

- **M3 — UTF-8 Grapheme Awareness.** Filter cycles by Unicode
  *cluster*, not byte. Multi-byte UTF-8 codepoints get one phase
  advance instead of N (`日` doesn't render as three rainbow
  segments); combining marks fold into their base codepoint (`é`
  = e + ◌́ at one phase); emoji ZWJ sequences render as a single
  cluster (👨‍👩‍👧 = one phase advance); regional-indicator pairs
  collapse to one cluster (🇺🇸 = one phase advance). The M1 ASCII
  path stays byte-identical — the v0.3.0 -s 100 golden fixture
  remains green.
- **UTF-8 primitives in `src/filter.cyr`**:
  - `utf8_seq_len(buf, i, n)` — 1/2/3/4-byte sequence detection.
    Returns 1 on invalid leading byte or invalid continuation
    (graceful degradation — the byte gets cycled as a singleton);
    returns 0 when a multi-byte sequence is truncated at the
    chunk boundary (carry signal).
  - `utf8_decode(buf, i, seqlen)` — assembles the codepoint from
    the validated sequence bytes.
  - `cp_is_extending(cp)` — practical-subset combining-mark
    classifier: Latin/Cyrillic/Hebrew/Arabic combiners + ZWJ + VS
    + half marks + math-zone combiners + variation selector
    supplement. Documents the trade vs full UAX #29 inline.
  - `cp_is_regional_indicator(cp)` — flag-pair recognition.
- **Chunk-boundary carry**. A multi-byte sequence that straddles
  the 4 096-byte read boundary is split correctly: the partial
  bytes carry over to the head of `read_buf`, and the next
  `read(2)` appends after them. EOF with carry → graceful
  per-byte cycling (the truncated sequence will never complete).
- **Cluster state machine** in `anuenue_filter`. Three latches:
  `saw_any` (suppress pre-advance on the very first cluster),
  `prev_was_zwj` (the codepoint after ZWJ joins the cluster —
  emoji-ZWJ-sequence rule), `prev_unpaired_ri` (pair regional
  indicators into flag emoji).
- **30 new assertions across 5 new groups** in
  `tests/anuenue.tcyr`: `utf8_seq_len` 1/2/3/4-byte detection,
  invalid + truncated handling, `utf8_decode` canonical codepoints
  (é / 日 / 🌈), `cp_is_extending` coverage (combining marks,
  ZWJ, VS, half marks, math zone, VS supplement, non-extending
  controls), `cp_is_regional_indicator` range bounds.
- **Three new golden fixtures** in `tests/golden/`:
  - `cjk-mixed-s0.out` — `日本AGNOS` at seed 0 (CJK + ASCII)
  - `combining-s0.out` — `é + rainbow` (combining diacritic)
  - `zwj-flag-s0.out` — `👨‍👩‍👧🇺🇸` (ZWJ + RI cluster stress)
  `scripts/golden-check.sh` refactored into a `check_golden`
  helper; all four fixtures asserted by CI's Golden output step.

### Changed

- `ANUENUE_FLUSH_RESERVE` bumped from 22 → 32 to fit a 4-byte
  codepoint's worst-case render envelope (19-byte fg escape + 4
  payload bytes + 4-byte reset). M1/M2's 22 was sized for 1-byte
  payloads only.
- `anuenue_filter` walks UTF-8 sequences instead of bytes; LF
  detection is a fast-path leading-byte check before
  `utf8_seq_len` runs. ASCII branch is preserved (single-byte
  cluster, advance phase).

### Performance

- **ASCII path slower** — ~86 ns/byte vs v0.3.0's 53 ns/byte
  (~62% regression on the M2 baseline) due to per-codepoint
  cluster classification. UTF-8 corpus runs comparable per-byte
  (~77 ns) since multi-byte codepoints amortise the per-cluster
  work over 2–4 payload bytes.
- **DCE binary** — 322 368 bytes (+5 152 vs v0.3.0).
- Both metrics tracked in `docs/benchmarks.md`. M5 (perf pass,
  v0.6.0) targets recovering the ASCII hot-path cost.

### Evaluated and rejected

- **vyakarana dep** — the roadmap M3 entry listed vyakarana as a
  candidate for grapheme-cluster boundary detection. Investigation
  showed vyakarana is a **source-code tokenizer** (token-kind spans
  for syntax highlighting via CYML grammars), not a Unicode
  database. Wrong domain. anuenue ships an inline practical-subset
  classifier instead; ADR 0003 (M7) will record the trade.

## [0.3.0] — 2026-05-21 — M2: Flag Surface

lolcat-equivalent CLI lands. Five flags (`-h`/`-V`/`-p`/`-s`/`-F`)
sit between argv and the M1 filter loop; the loop itself is
byte-identical to v0.2.0. Determinism is now a CI-asserted property
(committed 238-byte golden fixture), and the `anuenue X.Y.Z` literal
is auto-generated from `VERSION` so the cyim-1.2.2-style drift can't
happen here.

### Added

- **M2 — Flag Surface.** lolcat-equivalent CLI with five flags:
  `-h` / `--help`, `-V` / `--version`, `-p` / `--freq <N>` (phase
  step per character; default 7), `-s` / `--seed <N>` (starting
  hue phase — the deterministic-output hook), `-F` / `--offset <N>`
  (additive phase offset; Ruby-lolcat compat). `-s` and `-F` are
  additive (PHASE_START = seed + offset) so they compose without
  precedence surprises. Parse errors surface a specific message
  (unknown flag / missing value / bad int / bundled-short rejection)
  followed by usage, exit 2.
- **Stdlib expansion** — `args` and `flags` added to
  `cyrius.cyml [deps].stdlib`. The flag parser is the AGNOS-
  canonical `lib/flags.cyr` (used by every toolchain binary and
  consumer); the inline-vs-stdlib roadmap note was tightened —
  stdlib doesn't count as "adding a flag-parsing lib." Capability
  surface gained `open(2)` + `close(3)` at startup for
  `/proc/self/cmdline` via `args_init()`; the filter loop itself
  remains read(0) / write(1) / brk(12) / exit(60) only.
- **Version-bump pipeline** (`scripts/version-bump.sh` + auto-
  generated `src/version_str.cyr`) — cyim's drift-prevention
  pattern, adapted. The `anuenue X.Y.Z` literal is regenerated on
  every bump; CI's new **Version consistency** step asserts the
  literal matches `VERSION` (and CHANGELOG has a section for the
  current version, and `cyrius.cyml` still pulls via
  `${file:VERSION}`). Drives `print_version()` in
  `src/main.cyr` — never hand-edit `src/version_str.cyr`.
- **Determinism golden** — `tests/golden/agnos-rainbow-s100.out`
  + `scripts/golden-check.sh`. Asserts `printf "AGNOS rainbow" |
  ./build/anuenue -s 100` produces a byte-identical 238-byte
  output every time. Wired into CI as the **Golden output**
  step. Catches regressions the unit suite can't see (HSV
  geometry, escape framing, line-flush ordering).
- **27 new assertions across 7 new groups** in
  `tests/anuenue.tcyr`: long-form bool dispatch (`--help`); short-
  form bool dispatch (`-V`); int extraction over short forms
  (`-p 13 -s 42 -F 100`); attached long-form value (`--freq=99`);
  additive seed+offset semantics (510+510 lands at phase 1020 →
  blue); error-variant dispatch (UNKNOWN, MISSING_VALUE, BAD_INT);
  `_VERSION_STR_ANUENUE` literal-shape sanity (prefix + LF
  terminator + length match).

### Changed

- `src/filter.cyr` — `ANUENUE_PHASE_STEP` and the new
  `ANUENUE_PHASE_START` are mutable module-level vars; `main.cyr`
  overwrites them from flags before `anuenue_filter()` runs.
  Default behavior unchanged from v0.2.0.
- `.github/workflows/ci.yml` — three new steps: **Golden output**,
  **Version consistency**.

## [0.2.0] — 2026-05-21 — M1: Minimum Viable Filter

The pipe-purity proof. stdin → stdout, per-byte 24-bit-truecolor
rainbow tint, capability surface = read(0) + write(1) + brk(12) +
exit(60). Drove the darshana 0.5.1 truecolor unlock as the sandhi
consumer for the new `tty_fg_rgb_buf` + `tty_sgr_reset_buf`
helpers.

### Added

- **M1 — Minimum Viable Filter.** stdin → stdout per-byte rainbow
  tint via 24-bit ANSI fg, emitted through darshana 0.5.1's new
  `tty_fg_rgb_buf` / `tty_sgr_reset_buf` primitives. Pipe-pure:
  capability surface is `read(0)` + `write(1)` + `brk(12)` +
  `exit(60)` — no `open`, `connect`, `fork`, `exec`, `signal`,
  `ioctl`. Implementation lives in `src/filter.cyr`:
  - **`hsv_rainbow(phase, out_rgb)`** — integer-only HSV → RGB for
    full-saturation full-value rainbow. 6-sector geometry over a
    1530-unit phase space (6 × 255 sub-steps). Canonical pure hues
    fall on exact integer (R,G,B) at sector boundaries with no
    rounding; sub-sector linear ramps go 0→255 / 255→0 deterministically.
  - **`anuenue_filter()`** — reads stdin in 4096-byte chunks; emits
    each byte prefixed by its phase-derived fg escape into a 32KB
    line buffer; flushes on LF (with `\x1b[0m` reset so the terminal
    returns clean for the shell prompt) or when the next worst-case
    escape + payload + reset wouldn't fit (force-flush). 22-byte
    reserve guards against scribbling past the buffer.
- **Module split** (`src/main.cyr` + `src/filter.cyr`). main.cyr is
  the entrypoint shell (alloc_init + `anuenue_filter()` call +
  `syscall(SYS_EXIT, ...)`); filter.cyr is the testable library
  surface — the test suite includes it without triggering the
  top-level `main()` call. Closes the state.md "module split
  planned at M1 — defer until the code earns it" note.
- **47 assertions across 6 groups** in `tests/anuenue.tcyr`:
  smoke; `hsv_rainbow` canonical hues (red / yellow / green / cyan
  / blue / magenta + wraparound at phase=1530); sector-ramp mid-
  points (sectors 0 / 1 / 3 / 5); phase normalization (large + negative
  inputs); filter-geometry flush-reserve sizing (round-trips
  `tty_fg_rgb_buf`'s max-escape envelope); module-constant sanity
  (no per-byte phase wrap, flush amortizes ≥100 chars).
- **`tests/anuenue.bcyr`** — first benchmarks. `hsv_rainbow` 8ns
  avg / `tty_fg_rgb_buf` 45ns avg over 1M iterations each.
  Captured in **`docs/benchmarks.md`** along with the end-to-end
  baseline (≈53 ns/byte over cat; 17.4× output expansion on
  base64 ASCII).
- **darshana pin bumped** `0.5.0 → 0.5.1` — the new pin ships the
  24-bit truecolor SGR helpers anuenue's M1 drove into existence.
  Sandhi-unlock pattern: anuenue is the consumer that asked,
  darshana exposed `tty_fg_rgb` / `tty_bg_rgb` + buf-targeting
  variants, anuenue's pin advances to consume them.

### Notes

- darshana pin bumped 0.5.0 → 0.5.1 as the sandhi-unlock pattern's
  consumer half: anuenue asked for truecolor, darshana shipped the
  surface, anuenue's pin advanced to consume it. Both repos cut
  same-day (2026-05-21).
- DCE binary captured at the cut — see `docs/development/state.md`
  binary row.
- Module split landed (`src/filter.cyr` + `src/main.cyr`); the
  predicted third file `src/hsv.cyr` didn't earn a split at M1 and
  may be revisited at M3 (UTF-8 grapheme awareness).

## [0.1.0] — 2026-05-21

### Added
- Initial project scaffold via `cyrius init anuenue` (cyrius 6.0.1).
- AGNOS first-party dep wiring: `darshana` 0.5.0 (ANSI substrate), `sakshi` 2.2.5 (errors/tracing per standards), `agnostik` 1.2.2 (shared types).
- CLAUDE.md filled from [example_claude.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/example_claude.md) — durable rules, anuenue-specific principles (pipe-purity, capability-boundedness, HSV phase model, UTF-8 grapheme awareness).
- `docs/development/roadmap.md` — M0 → v1.0 plan across 9 milestones with dep gates, acceptance criteria, and explicit out-of-scope list.
- `docs/development/state.md` — initial state snapshot.
- README — anuenue-specific identity, etymology (Hawaiian ānuenue), positioning as founder of the pipe-decorator family.
- Registry entry in agnosticos `docs/development/planning/shared-crates.md` § Pipe-decorator family (new sub-section).

### Notes
- No filter logic yet — `src/main.cyr` is the `cyrius init` hello-world. M1 (v0.2.0) is the pipe-purity proof: stdin → stdout, byte-level cycling, 24-bit ANSI via darshana.
