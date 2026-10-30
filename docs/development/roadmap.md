# anuenue — Roadmap

> **Sequencing, not status.** What ships next, in what order, against what
> gates. Current-state numbers (version, size, counts, pins) live in
> [`state.md`](state.md); per-cut narrative — including everything this file
> used to index (M0–M8, the v1.0 scorecard, the v1.1–v1.4.0 slots) — lives in
> [`CHANGELOG.md`](../../CHANGELOG.md).
>
> Slot headings never carry status — a `> **Status:**` line sits under them
> instead, so the anchors other documents link to stay stable as work lands.
>
> **Forward-facing only** (reorganised at v1.4.1). A slot leaves this file when
> it ships. **Every open item traces to a deferral in the code, an ADR, an audit
> report, or a measurement, and every one is pinned to a release.** A
> trigger-gated item whose trigger has not fired by its cut moves to the next
> slot, explicitly, at that cut — it does not silently stay put.

## What anuenue is

A Cyrius-native `lolcat` equivalent. Pure stdin → stdout pipe filter that tints
each grapheme cluster along an HSV cycle, emitting ANSI escapes via `darshana`.
Capability-bounded: no file I/O, no network, no fork/exec.

Founder of the **pipe-decorator family** in the AGNOS userland (see
[shared-crates.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md)).
Sibling-not-overlap with the terminal-aesthetics quintet: those produce their
own output, pipe-decorators are pure filters on what passes through them.

## Where things stand

**v1.5.1.** The v1.x contract — exit codes, output shape, capability surface —
has been frozen since GA and is unbroken; the flag set has only ever grown.
v1.4.5 stripped the input's own colour codes on the colour routes (audit H-06);
v1.5.0 added their counterpart, a producer-side no-colour span marked with an APC
pair ([ADR 0006](../adr/0006-no-colour-spans.md)). v1.5.1 moved the toolchain to
cyrius 6.7.18 and every dep to its latest tag, with stdout unchanged. Seven
audits have run, the latest the
[v1.5.0 delta](../audit/2026-10-15-v150-delta.md), all with zero HIGH+ open.
Next: v1.5.2 settles two older phase disagreements between the routes; v1.5.3
swaps anuenue's SGR stand-in for the scanner darshana 1.4.0 ships.

## Release map

| Release | Slot | Gate |
|---------|------|------|
| [v1.5.2](#v152--the-routes-agree-on-the-phase-of-an-extender) | The routes agree on the phase of an extender | none — actionable |
| [v1.5.3](#v153--the-sgr-stand-in-gives-way-to-darshanas-scanner) | The SGR stand-in gives way to darshana's scanner | none — actionable after v1.5.2 |
| [v1.6.0](#v160--pipe-decorator-family) | Pipe-decorator family (+ adoption, if a consumer has landed) | a second pipe-decorator wants a rainbow, or a consumer's ask |
| [v1.x](#v1x--trigger-gated) | Trigger-gated | the first minor after each trigger fires |
| [v2.0](#v20--reserved) | Reserved | nothing queued |

---

## v1.5.2 — The routes agree on the phase of an extender

> **Status:** actionable — the next patch. Recorded as V-11 in the
> [v1.5.0 delta](../audit/2026-10-15-v150-delta.md); both cases predate v1.5.0.

Two rare inputs where the filter and the other routes give a different hue to
what follows. A stdout change on the filter for those inputs only, so it gets
its own patch:

- **An extender straight after an LF.** The filter folds it into the LF with
  no phase step. Animation gives it a cluster of its own with a step (H-05,
  v1.4.4), which is UAX #29's answer (GB4: break after a control). Change the
  filter (and `anuenue_render_bytes`) to match. Animation's row count gives
  such a mark 1 column where terminals give it none; settle that in the same
  slot.
- **The filter's EOF carry ignores the ZWJ and RI latches.** A ZWJ, then a
  carried prefix at the very end of the input (a lone ESC, `ESC _`), steps the
  phase on the filter but not on the one-shot route.

Gates: robustness gate 11's `ROUTES` comparison, widened to inputs with an
extender after an LF, and stdout identity against v1.5.1 for every input
without one.

## v1.5.3 — The SGR stand-in gives way to darshana's scanner

> **Status:** actionable after v1.5.2. Added at v1.5.1, when the pin reached
> darshana 1.6.0; placed after V-11 so each patch moves one thing. The user may
> re-place it.

anuenue proposed an input-side SGR scanner to darshana on 2026-10-15, shaped on
its own stand-in (`_sgr_len` and `anuenue_sgr_strip` in `src/filter.cyr`, v1.4.5).
darshana 1.4.0 shipped it as `tty_sgr_len(buf, s, n, max)` and
`tty_sgr_strip_buf(buf, n, final, out_held)` (darshana ADR 0006), and v1.5.1 pins
1.6.0, so both are in the bundle unused. This is the swap half of the sandhi
pattern: proposal → swap → goldens unchanged.

- **Where darshana differs** (its ADR 0006): `max` is a parameter (anuenue
  passes 128); `tty_sgr_len` checks the byte at `s` is ESC; out-of-contract
  arguments answer 0, never -1; `tty_sgr_strip_buf` rejects a negative `n` or a
  `final` other than 0 / 1 with -1; and there is no strip counter — `-v`'s count
  stays anuenue's, kept around the call.
- **The filter's inline check is the hot path.** v1.4.5 tests for ESC inline
  next to LF behind one `b < 0x20` comparison, and a separate pass measured +1.7
  ns/byte. Swap the length test there only if `scripts/perf-bench.sh` shows it
  flat, head-to-head in all four `COLOR=` modes; otherwise swap one-shot and
  animation's buffer strip alone and record why.
- **Gates:** stdout identity against v1.5.2 across corpora × flags (SGR,
  near-miss SGR, SGR split across the 4096-byte read), `fuzz/sgr-strip.fcyr`
  re-pointed at darshana's functions against its independent reference,
  robustness gate 10 unchanged, the dead-code floor (the stand-in goes).

## v1.6.0 — Pipe-decorator family

> **Status:** gated on a second pipe-decorator wanting a rainbow tint. Adoption
> and any additive surface a consumer asks for ride along with this minor, or
> cut it on their own if they arrive first (moved here from v1.5.0, which
> shipped the no-colour marker).

- **Extract the HSV phase model to a shared crate** (or pull `abaco`). Until a
  second consumer exists the inline copy is free.
  ([ADR 0002 § Revisit triggers](../adr/0002-hsv-inline-not-abaco.md)) The
  seam already exists: `dist/anuenue.cyr` (v1.2.0) exports exactly
  `src/hsv.cyr`, and thoth includes it in-process today.
- The successors that would fire the trigger, idea-tier and uncommitted:
  - `boxes`-equivalent — wrap stdin in ASCII borders
  - `cowsay`-equivalent — ASCII speech bubble
  - `pv`-equivalent — pipe-viewer with throughput indicator

  They earn entries in
  [shared-crates.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md)
  when they become real.

**Adoption rides along if it is ready.** The two v1.0 acceptance items still
open — eight of ten closed at GA — are not code anuenue can write; both close
retroactively once an integration lands.

- **Dogfooded** — `iam | anuenue` MOTD or `bnrmr | anuenue` banners running in a
  real AGNOS pipeline for at least one minor-cycle window.
- **Downstream gate** — at least one consumer green against v1.x (`agnoshi`
  MOTD chain or `iam`'s default login chain anticipated). Listed in
  [`state.md` § Consumers](state.md#consumers) once real. *Noted at v1.4.4:*
  thoth already consumes the **library** surface — it vendors
  `dist/anuenue.cyr` (at 1.3.6, code-identical to 1.5.0's) for `/theme
  rainbow`, and is green. Whether a library consumer closes this item, which
  named pipeline consumers, is the user's call; until then it stays open.
- **A first producer of no-colour spans** (v1.5.0). The marker is only worth its
  grammar if a producer emits it. When `iam`, `bnrmr` or the MOTD chain adopts
  it, add that pipeline to the PTY gate's span cases.

Additive surface an integration asks for lands here. One candidate is on file:

- **`-vvv` repeat-count verbosity** — trigger: a consumer asks.
  `--log-level=trace` is self-documenting in a script and greppable in shell
  history; `-v` covers the interactive case. cmdit supports repeat counts, so
  the cost is low if the ask arrives.
  ([ADR 0004 § Alternatives](../adr/0004-stderr-only-observability.md))

## v1.x — trigger-gated

Pinned to the first minor after the trigger fires.

| Item | Trigger | Source |
|------|---------|--------|
| **Follow a resize mid-animation; animate a block taller than the terminal** | A consumer asks. v1.4.4 (H-01) reads the size once, before the first frame, and draws a block that cannot fit once. Following SIGWINCH means a signalfd mask change and a re-read per frame; animating an oversized block means a clipping policy (which rows?) nobody has specified. | [ADR 0005 § Consequences, § Alternatives](../adr/0005-practical-subset-display-width.md) |
| **The span row count for terminal-dependent sequences** | A producer writes them inside a no-colour span: C1 controls encoded in UTF-8 (U+009B CSI, U+009D OSC), or a non-ASCII byte inside a CSI. Terminals disagree on both, so the count picks one reading. | [v1.5.0 delta V-12](../audit/2026-10-15-v150-delta.md) |
| **Raise or remove the animation input caps** | Someone animates something that hits them. v1.2.2 (A-05) made the 64 KB / 8 192-cluster caps *announce* themselves; it did not raise them. Raising means more heap; removing means streaming animation, which conflicts with the slurp-then-tag design that makes frame re-anchoring possible. A behaviour change, so a minor. | `src/animate.cyr` caps + [2026-08-25 audit A-05](../audit/2026-08-25-audit.md) |

### Explicitly declined

Recorded so they are not re-raised as findings.

- **Logging parse errors.** Observability is configured *from* parsed flags, so
  a `cmdit` parse failure precedes the level being known. A pre-parse argv scan
  for `-v` would duplicate cmdit's tokenizer — exactly the duplication adopting
  cmdit at v1.1.4 removed. Those paths print their own stderr line instead —
  naming the offending token since v1.4.2, via `cmdit_err_token`, without
  re-tokenizing argv. ([ADR 0004](../adr/0004-stderr-only-observability.md))
- **darshana's `TTY_SIGMASK_PIPE`** (1.3.0). It keeps a TUI from being killed by
  SIGPIPE mid-teardown with the terminal raw. anuenue has no terminal state at
  risk when stdout is a pipe — its escapes went down the pipe — and adopting it
  would put a signalfd on the *filter* path, whose capability surface is
  read/write/mmap, and turn the default-disposition `anuenue | head -1` from exit
  141 into exit 0. ([v1.4.0 audit delta](../audit/2026-10-12-v140-delta.md))
- **darshana's `tty_sanitize_buf` on the filter path** (1.2.0). anuenue's
  contract is byte preservation — every byte but the input's own SGR colour
  codes, which v1.4.5 strips on the colour routes; `robustness-check.sh`
  asserts all 256 byte values pass through. Neutralising control bytes in stdin would break the
  contract it exists to keep. (Diagnostics are not the stream: since v1.4.2 it
  sanitizes the argv tokens that parse-error lines echo to stderr.)
- **A fixed input corpus inside `tests/anuenue.bcyr`** (decided at v1.4.3, the
  slot that had to decide it). The word copy was the first change whose gate
  wanted end-to-end and per-call numbers side by side. Running
  `scripts/perf-bench.sh` next to the `.bcyr` rows supplied both. An in-process
  corpus bench would need a stdout sink that `anuenue_filter` does not have — it
  writes fd 1 directly — so it would mean a test-only seam in the hot path, to
  measure what the shell script already measures.
- **Flattening `src/filter.cyr`'s `} } } }` chain.** A genuine 4-way dispatch at
  ≤24 columns that passes `cyrius fmt`. (`src/main.cyr`'s parse-error chain was
  flattened at v1.4.1 because cmdit 1.4.0 pushed it to five levels; this one has
  not grown.) ([2026-08-25 audit § Deferred](../audit/2026-08-25-audit.md))

### Upstream, not anuenue's to fix

Re-checked at every bump of the dep named.

- **cmdit: `-p -9223372036854775808` is rejected while `i64::MAX` is accepted.**
  `_cmdit_parse_int` builds the positive magnitude and refuses the most-negative
  i64 (the negate-MIN case). Unchanged in cmdit 1.5.0 (`_cmdit_parse_int`'s
  body is identical to 1.4.0's), and nothing upstream tracks it — worth filing
  at cmdit. Rejecting is the safe direction.
- **cyrius: `CYRIUS_DCE=1` keeps the string literals of the code it removes.**
  Filed 2026-10-29 as cyrius
  `docs/development/issues/2026-10-29-anuenue-dce-keeps-literals-of-dead-code.md`,
  with a three-program repro. It is most of v1.5.1's size step: bayan's Unicode
  tables (307 252 B, global string literals) reach anuenue through agnostik's
  deps sidecar, and DCE drops every function that reads them but not the data.
  No consumer-side workaround: agnostik requires bayan. Binary size is tracked,
  not capped, so this is recorded, not blocking. Re-check at each toolchain bump.
- **darshana: `cyrius distlib` reports `tty_winsize` undefined on
  x86_64-windows / x86_64-macos / aarch64-macos.** A warning on every
  `cyrius distlib` run, present from v1.4.0 through darshana 1.6.0. None of
  those is an anuenue target, and `dist/anuenue.cyr` exports only
  `src/hsv.cyr`.

Closed at v1.5.1:

- **cyrius `args_init` cut the command line at 2 MiB** — resolved in cyrius
  6.7.12 (it reads to EOF), and cmdit 1.4.2 narrowed its own check to exactly
  2 MiB. A longer command line now parses whole; robustness gate 7 asserts it.
- **"Growing a large function miscompiles"** — not a cyrius bug. cyrius 6.7.14
  closed the issue anuenue filed: it was anuenue's own overrun, `var argv2[8]`
  (and `argv1[8]`, `argv5[32]`) in `tests/anuenue.tcyr` holding more pointers
  than bytes, which `cyrius lint` names from 6.7.11. Fixed at v1.5.1.
- **agnostik `agnostik_err_new` wrote through an unchecked `alloc(24)`** — fixed
  in agnostik 1.12.3: it returns a static `RESOURCE_EXHAUSTED` "out of memory"
  error instead.

---

## v2.0 — reserved

**Nothing is queued.** The v1.x contract is frozen and no open item requires
breaking it.

What would earn a major: removing or renaming a flag; changing an exit code;
changing the output byte shape for input that renders today; narrowing the
capability surface a consumer depends on. Anything that only *adds* surface is a
minor.

**Precedent, v1.4.1:** rejecting input whose accepted meaning was the defect is
a fix, not a break. cmdit 1.4.0 made `--no-color=0` a usage error; v1.4.0
accepted it and turned colour *off* — the opposite of what was typed. No
documented form ever put `=value` on a boolean.

---

## Ongoing cadence — not milestones

These run every cut and never "complete".

- **Audit cadence.** A P(-1) sweep at every minor cut, recorded as a delta vs the
  previous report — the next is at the v1.6.0 cut. Seven have run, latest the
  [v1.5.0 delta](../audit/2026-10-15-v150-delta.md).
  Standing policy from v1.2.2: **an accepted INFO finding is a hypothesis about
  behaviour, not a measurement of it** — re-measure accepted items rather than
  carrying the prior description forward.
- **Sandhi cadence.** darshana / cmdit / agnostik bumps follow proposal → swap →
  goldens-unchanged. Re-evaluate pin lag at each minor cut, per
  [feedback_dep_lockin_sandhi_unlock](https://github.com/MacCracken/agnosticos/blob/main/.claude/projects/-home-macro-Repos-agnosticos/memory/feedback_dep_lockin_sandhi_unlock.md).
  Invalidate the lock when changing a tag (`rm cyrius.lock && cyrius deps`) and
  check the bundle's `# Version:` header. **sakshi is not on this list** from
  v1.4.1: it is a stdlib module and moves with the `cyrius` pin. A dep bump is
  also a behaviour survey — v1.4.1's cmdit move made four input classes reachable
  that 1.2.4 had parsed clean (the CHANGELOG has them).
- **Binary size: track, do not cap.** Record the size every release and
  attribute any step change, one change per row. See
  [`state.md` § Binary](state.md#binary).
- **Perf ratchet.** `scripts/perf-bench.sh` at every cut, measured head-to-head
  against a rebuilt prior binary on one idle host rather than against a
  historical figure, in all three `COLOR=` modes and `COLOR=none` (MONO, from v1.5.0). M5 acceptance: ASCII no-LF
  ≤ 60 ns/byte.

---

## Out of scope

Deliberately not in anuenue, at any version. Keeps contributors from adding
them by accident.

- **File-input mode** (`anuenue file.txt`). `cat file.txt | anuenue` is the
  file story. Pipe purity is the design — [ADR 0001](../adr/0001-pipe-purity.md).
- **Configuration file.** The CLI flags are the surface. No `~/.anuenue.cyml`.
- **Custom palettes / theme system.** The rainbow is the brand.
- **Output styles beyond colour.** No bold, italic or underline injection.
  ANSI foreground only.
- **User-supplied colour expressions** (`-e 'hsv(phase*2)'`). Would need an
  expression evaluator and violates ADR 0001. This is also the second
  [ADR 0002](../adr/0002-hsv-inline-not-abaco.md) revisit trigger — if the rule
  ever relaxes, that ADR reopens first.
- **Image input.** Wrong domain. A different tool consuming `ranga`, if ever.
- **Network features.** There are none. Do not add any.
- **Diagnostics on stdout.** Every diagnostic byte goes to fd 2, at every
  verbosity — [ADR 0004](../adr/0004-stderr-only-observability.md), enforced by
  `scripts/observe-check.sh`.

---

## Dependency map

Versions live in [`state.md` § Dependencies](state.md#dependencies); this is the
durable shape and the rationale.

| Dep | Provides | Notes |
|-----|----------|-------|
| **darshana** | ANSI escape generation — `tty_fg_rgb_buf`, `tty_fg_256_buf`, `tty_sgr_buf`, `tty_sgr_reset_buf`, `tty_sgr_reset`, `tty_cursor_up` / `_hide` / `_show`, `tty_isatty` — and animation's exit-signal fd: `tty_open_signalfd` / `tty_read_signal` / `tty_close_signalfd` | API frozen since 1.0.0; all twelve symbols anuenue calls are frozen. anuenue never emits a raw escape and never touches a signalfd directly. |
| **cmdit** | CLI / argument parsing (getopt-long) | Adopted at v1.1.4, replacing the stdlib `flags` parser. anuenue is cmdit's second worked migration, after kii. Its error taxonomy is append-only; `src/main.cyr` names every code anuenue's flag set can produce, and `fuzz/flag-parser.fcyr` asserts nothing else comes back. |
| **sakshi** | Errors / tracing / structured logging | Canonical per first-party-standards. Wired at v1.2.1 (`src/observe.cyr`). **stderr only** — the file and UDP output targets would breach the capability bound and are never selected. A **stdlib module** from v1.4.1: the toolchain snapshot's version, no git pin. |
| **agnostik** | Shared Result / Error shapes | Wired at v1.2.1. Every failure returns through `anuenue_fail(kind, msg)`; `STIK_ERR_INVALID_ARGUMENT` → exit 2, everything else → exit 1. |
| **Cyrius stdlib** | string, fmt, alloc, io, vec, str, syscalls, assert, bench, args, chrono, sakshi | `flags` was dropped at v1.1.4; `chrono` added at M4 for frame timing; `sakshi` moved here from `[deps.sakshi]` at v1.4.1. |

Evaluated and **not** wired:

- **vyakarana** — a *source-code tokenizer* (token-kind spans for syntax
  highlighting), not a Unicode database. anuenue ships an inline
  practical-subset grapheme-cluster classifier instead;
  [ADR 0003](../adr/0003-grapheme-cluster-cycling.md) records the trade against
  full UAX #29.
- **abaco** — expression evaluation. HSV→RGB is ~30 lines inline;
  [ADR 0002](../adr/0002-hsv-inline-not-abaco.md) records the decision and its
  two revisit triggers.
- **ranga** — image-processing colour conversion. Wrong substrate: anuenue is
  per-character at terminal output, not pixel-buffer manipulation.
- **kashi** — PSF font rendering. Wrong domain: anuenue tints existing glyphs,
  it doesn't draw them.
