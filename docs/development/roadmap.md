# anuenue — Roadmap

> **Sequencing, not status.** What ships next, in what order, against what
> gates. Current-state numbers (version, size, counts, pins) live in
> [`state.md`](state.md); per-cut narrative lives in
> [`CHANGELOG.md`](../../CHANGELOG.md).
>
> Slot headings never carry status — a `> **Status:**` line sits under them
> instead, so the anchors other documents link to stay stable as work lands.
>
> Reorganised at v1.2.2. The pre-GA milestone plan (M0–M8) is finished and
> collapsed into [§ Shipped](#shipped); everything below the fold is forward
> work only. **Every open item in this file traces to a specific deferral in the
> code, an ADR, or an audit report** — if it isn't here, it isn't planned.

## What anuenue is

A Cyrius-native `lolcat` equivalent. Pure stdin → stdout pipe filter that tints
each grapheme cluster along an HSV cycle, emitting ANSI escapes via `darshana`.
Capability-bounded: no file I/O, no network, no fork/exec.

Founder of the **pipe-decorator family** in the AGNOS userland (see
[shared-crates.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md)).
Sibling-not-overlap with the terminal-aesthetics quintet: those produce their
own output, pipe-decorators are pure filters on what passes through them.

## Where things stand

**v1.3.1.** The v1.x public API contract — exit codes, output shape, capability
surface — has been frozen since GA and is unbroken; the flag set has only ever
grown. Two P(-1) audits have run with zero HIGH+ findings open, and the v1.3.0
animation slot closed three further defects the audits had not reached.

The v1.0 acceptance scorecard closed **8 of 10** at GA. The two open items are
adoption properties, not code, and are tracked in
[§ Adoption](#adoption--blocked-on-external-consumers) below.

---

## v1.3.0 — Animation slot

> **Status: complete.**

Animation was picked because every open deferral clustered there — the least
exercised path in the tree: the only code that touches signals, the only code
with input caps, and the only code no test drives through a real terminal.

That read paid off immediately. Adding one flag surfaced **three latent
defects**, two of which could leave a terminal unkillable.

| Item | Outcome |
|------|---------|
| **`-i` / `--interval <ms>`** | Shipped. Rejects non-positive (usage error), clamps above `ANUENUE_MAX_INTERVAL_MS` — see [architecture 005](../architecture/005-timing-primitives-truncate.md) for why that clamp is a correctness bound. |
| **Re-measure audit INFO 8 + 9** | Done — and they were a **real defect**, not the accepted non-issue three audits recorded. See B-01. |
| **Fuzz the two rejecting parsers** | `fuzz/flag-value-parsers.fcyr` — totality, one-byte-mutation exactness, name totality over arbitrary i64, and `parse(name(p)) == p` round-trip. **+96 091 assertions.** |
| **Populate `docs/architecture/`** | Six notes, one per invariant the v1.2.2 audit and this slot had to discover. Index at [`docs/architecture/`](../architecture/README.md). |
| ~~PTY-backed animation test~~ | **Moved to [v1.3.1](#v131--pty-backed-animation).** |

**Found by doing the above** — three defects the `-i` flag exposed, all fixed
in-slot, all covered by `scripts/signal-check.sh`:

- **B-01 (MEDIUM)** — `_open_exit_signalfd` leaked its `SIG_BLOCK` when
  `signalfd(2)` failed, leaving HUP/INT/TERM blocked with no fd to drain them:
  Ctrl-C inert, `kill` inert, hangup inert, only SIGKILL working. The same
  defect darshana fixed at v0.9.3; anuenue's hand-rolled copy predates it.
  Mutation-proven via `tests/probes/sigmask-probe.cyr`.
- **B-02 (MEDIUM)** — the frame loop slept a whole interval before checking for
  signals. With `-i 3600000` the process ignored SIGTERM for an hour and
  `timeout(1)` could not kill it. `_frame_wait` now slices at
  `ANUENUE_TICK_MS`.
- **B-03 (LOW)** — `--duration` overshot by up to one interval, same cause.

---

## v1.3.1 — PTY-backed animation

> **Status: complete.**

The one item carried out of the v1.3.0 slot, on its own because it is a
different kind of work: everything else in v1.3.0 was reachable from a pipe,
and this is not.

| Item | Outcome |
|------|---------|
| **Drive animation through a real pseudo-terminal** | Shipped as `scripts/pty-check.sh` — 14 checks via `script(1)`, CI-wired, skip-clean without `/dev/ptmx`. Covers seven exits of `anuenue_detect_color_mode` under a real TTY, MONO byte-exactness on a colour-capable terminal, cursor-lifecycle ordering, and SIGINT-during-animation. |

**Why it is worth its own cut.** Three behaviours are only reachable with a
controlling terminal, and all three are animation's exit path:

1. **`tty_isatty` returns true**, so colour auto-detection takes the branch a
   pipe never takes. Every existing animation test forces `--color=24bit` to
   work around exactly this.
2. **Cursor restore is checkable against the end of the stream**, and on the
   path a terminal actually drives. `tty_cursor_hide` / `tty_cursor_show` and
   the final `tty_sgr_reset` are asserted by ordering — show after hide, reset
   before show — rather than by a grep count.
   *(Corrected: an earlier draft of this entry said the terminal state itself
   could be read back. It cannot — `script(1)` transcribes bytes, it does not
   emulate a terminal, so there is no cursor-visibility to query. Reading real
   terminal state back would need an emulator in the harness.)*
3. **SIGINT arrives as a real terminal signal**, not a delivered one. The
   signalfd path has now been tested for its *failure* mode (B-01) and its
   *latency* (B-02); it has never been tested for the case it was written for.

**Outcome**: no new defects. That is a meaningful result rather than a null one
— the auto-detection chain had never been executed by any test, so "it was
already correct" was an assumption until this cut, not a measurement. The
harness skips clean without `script(1)` or `/dev/ptmx`, so a runner without a
PTY warns rather than fails.

---

## v1.x — later minors

Real, but not scheduled: each is either blocked on something outside the repo or
waiting for a second data point.

### Adoption — blocked on external consumers

The two v1.0 acceptance items still open. Neither is code anuenue can write.

- **Dogfooded** — `iam | anuenue` MOTD or `bnrmr | anuenue` banners running in a
  real AGNOS pipeline for at least one minor-cycle window.
- **Downstream gate** — at least one consumer green against v1.x (`agnoshi`
  MOTD chain or `iam`'s default login chain anticipated).

Both close as retroactive acceptance once an integration lands. The v1.0
*contract* is what makes adoption tractable; shipping it was the deliverable,
and adoption is not a property the project can satisfy unilaterally.

### Waiting for a second data point

| Item | Trigger that unblocks it | Source |
|------|--------------------------|--------|
| **Extract the HSV model to a shared crate** (or pull `abaco`) | A second pipe-decorator wants its own rainbow tint. Until then the inline copy is free. | [ADR 0002 § Revisit triggers](../adr/0002-hsv-inline-not-abaco.md) |
| **`-vvv` repeat-count verbosity** | A consumer asks. `--log-level=trace` is self-documenting in a script and greppable in shell history; `-v` covers the interactive case. cmdit supports repeat counts, so the cost is low if the ask arrives. | [ADR 0004 § Alternatives](../adr/0004-stderr-only-observability.md) |
| **Raise or remove the animation input caps** | Someone animates something that hits them. v1.2.2 (A-05) made the 64 KB / 8 192-cluster caps *announce* themselves; it did not raise them. Raising means more heap; removing means streaming animation, which conflicts with the slurp-then-tag design that makes frame re-anchoring possible. Needs a real use case before trading either away. | `src/animate.cyr` caps + [2026-08-25 audit A-05](../audit/2026-08-25-audit.md) |
| **Fixed input corpus for `tests/anuenue.bcyr`** | Wanting end-to-end numbers *inside* the bench harness. Today `scripts/perf-bench.sh` owns end-to-end measurement and the `.bcyr` file benches two functions. The split works; this only matters if the shell harness becomes the bottleneck. | `tests/anuenue.bcyr` — "once we have a fixed input corpus to bench" |

### Explicitly declined

Recorded so they are not re-raised as findings.

- **Logging parse errors.** Observability is configured *from* parsed flags, so
  a `cmdit` parse failure precedes the level being known. A pre-parse argv scan
  for `-v` would duplicate cmdit's tokenizer — exactly the duplication adopting
  cmdit at v1.1.4 removed. Those paths keep their existing stderr wording.
  ([ADR 0004](../adr/0004-stderr-only-observability.md))
- **Flattening the remaining `} } } }` chains** in `src/main.cyr` and
  `src/filter.cyr`. Both are genuine 4-way dispatches at ≤24 columns and both
  pass `cyrius fmt`. `hsv_rainbow` was flattened at v1.2.2 because the formatter
  cascaded it to 24 columns *and* it is a lookup table whose parallel alignment
  carries meaning. These two are neither. ([2026-08-25 audit § Deferred](../audit/2026-08-25-audit.md))

### Upstream, not anuenue's to fix

- **`-p -9223372036854775808` is rejected while `i64::MAX` is accepted.** cmdit's
  integer parser refuses the most-negative i64 (the negate-MIN case). Rejecting
  is the safe direction and the asymmetry is cmdit's to resolve. Recorded so the
  next audit does not re-derive it.

---

## v2.0 — reserved

**Nothing is queued.** The v1.x contract is frozen and no open item requires
breaking it.

What would earn a major: removing or renaming a flag; changing an exit code;
changing the output byte shape for input that renders today; narrowing the
capability surface a consumer depends on. Anything that only *adds* surface is a
minor.

---

## Ongoing cadence — not milestones

These run every cut and never "complete".

- **Audit cadence.** A P(-1) sweep at every minor cut, recorded as a delta vs the
  previous report. Two have run: the
  [v0.8.0 baseline](../audit/2026-05-22-audit.md) and the
  [v1.2.2 P-1 sweep](../audit/2026-08-25-audit.md). The v1.2.2 lesson is now
  policy: **an accepted INFO finding is a hypothesis about behaviour, not a
  measurement of it** — re-measure accepted items rather than carrying the prior
  description forward. That is why INFO 8 and 9 are scheduled work above and not
  a footnote.
- **Sandhi cadence.** darshana / cmdit / sakshi / agnostik bumps follow
  proposal → swap → goldens-unchanged. Re-evaluate pin lag at each minor cut,
  per [feedback_dep_lockin_sandhi_unlock](https://github.com/MacCracken/agnosticos/blob/main/.claude/projects/-home-macro-Repos-agnosticos/memory/feedback_dep_lockin_sandhi_unlock.md).
  v1.2.1 is the cautionary reference: manifest tags had drifted from the
  vendored bytes because a `path`-mode tag only binds when `cyrius.lock` agrees.
  Invalidate the lock when changing a tag, and check the bundle's `# Version:`
  header.
- **Binary size: track, do not cap.** The 512 KB cap was removed at v1.2.2 —
  the number now measures the first-party dep surface far more than it measures
  anuenue, and `CYRIUS_DCE=1` stopped removing anything on 6.5.x. Record the
  size every release and attribute any step change. See
  [`state.md` § Binary](state.md#binary).
- **Perf ratchet.** `scripts/perf-bench.sh` at every cut, measured head-to-head
  against a rebuilt prior binary on one idle host rather than against a
  historical figure. M5 acceptance: ASCII no-LF ≤ 60 ns/byte.

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

## Shipped

Per-cut narrative in [`CHANGELOG.md`](../../CHANGELOG.md); this is the index.

### v1.x

| Cut | Slot | Headline |
|-----|------|----------|
| v1.2.2 | P(-1) audit sweep | 9 findings (2 MEDIUM, 5 LOW, 2 INFO), all fixed in-cut, zero HIGH+ open. Unchecked `alloc` → null write; `--duration` overflow inverting long animations to a one-frame exit; three silent-fallback defects. `scripts/robustness-check.sh` added (11 checks: UTF-8 carry across the read boundary, byte preservation under malformed input, argv at i64 extremes). **512 KB size cap removed.** 308 → 349 assertions. |
| v1.2.1 | Toolchain + deps + observability + CI repair | cyrius `6.4.62` → `6.5.35`; darshana `1.0.0` (API freeze), cmdit `1.2.4`, sakshi `2.4.11`, agnostik `1.5.1`. **sakshi + agnostik wired** (`src/observe.cyr`) after being declared-but-uncalled since M0 — `-v` / `--log-level`, stderr-only, ADR 0004. CI's hand-rolled pre-6.5 toolchain install replaced with the upstream installer (it would have broken on the pin bump). 242 → 308 assertions. |
| v1.2.0 | Library surface | `dist/anuenue.cyr` distlib — the pure HSV phase model becomes consumable in-process. First consumer: thoth's `/theme rainbow`. |
| v1.1.5 | AGNOS colour fix | Rainbow collapsed to 16 colours on AGNOS (env heuristics on a platform that sets no env); agnos now defaults to truecolor. |
| v1.1.4 | CLI parsing → cmdit | Dropped the stdlib `flags` parser for the cmdit distlib. Byte-compatible; anuenue is cmdit's second worked migration. |
| v1.1.3 | Toolchain + dep refresh | cyrius `6.1.14` → `6.2.24` plus the first sandhi refresh after GA. |
| **v1.0.0** | **GA** | Public API contract frozen for the v1.x line. 8 of 10 acceptance criteria met at tag. |

### Pre-GA — M0 through v0.9.0

Eleven releases across two calendar days (2026-05-21 / 2026-05-22).

| Cut | Slot | Headline |
|-----|------|----------|
| v0.9.0 | Quality slot | `fuzz/` populated with 5 harnesses (1.35 M assertions, CI-gated). `animate-smoke.sh` extended to 256 / 16-colour. `src/hsv.cyr` split landed. |
| v0.8.0 | M7 + M8 — Docs + Audit | Three ADRs, integration guide, 8 examples. Audit found and fixed one HIGH (`_render_frame` long-cluster heap overflow). |
| v0.7.1 | Sandhi closeout | darshana 0.5.3 swap; stand-ins removed. |
| v0.7.0 | M6 — Colour-mode negotiation | TRUECOLOR / 256 / 16 / MONO priority chain; `--no-color` / `--force-color` / `--color`. |
| v0.6.0 | M5 — Performance pass | ASCII short-circuit, binary-searched `cp_is_extending` LUT, 1 530-entry phase-cached escape table. 91.6 → 47.0 ns/byte. |
| v0.5.0 | M4 — Animation mode | `-a` / `-d` / `-S`; cluster pre-tag, 16 ms frame loop, non-blocking signalfd. |
| v0.4.0 | M3 — UTF-8 grapheme awareness | Cycle by cluster, not byte. Practical-subset classifier + ZWJ + RI latches + chunk-boundary carry. |
| v0.3.0 | M2 — Flag surface | `-h` / `-V` / `-p` / `-s` / `-F`; deterministic-seed golden harness. |
| v0.2.0 | M1 — Minimum viable filter | stdin → stdout per-byte 24-bit rainbow. Pipe-pure: read + write + brk + exit. |
| v0.1.0 | M0 — Scaffold | `cyrius init anuenue`; doc tree; deps pinned. |

### v1.0 acceptance scorecard

Eight of ten met at the GA tag. The two open items are in
[§ Adoption](#adoption--blocked-on-external-consumers).

- [x] Public CLI surface frozen — M7 / v0.8.0
- [x] UTF-8 correct by default — M3 / v0.4.0, [ADR 0003](../adr/0003-grapheme-cluster-cycling.md)
- [x] TTY-aware (`NO_COLOR`, stdout-not-a-TTY) — M6 / v0.7.0
- [x] Colour-mode negotiation — M6 / v0.7.0
- [x] Animation parity with `lolcat -a` — M4 / v0.5.0
- [x] Per-character overhead measured — M5 / v0.6.0, `docs/benchmarks.md`
- [x] Security audit pass — M8 / v0.8.0, re-run at v1.2.2
- [x] CHANGELOG complete from v0.1.0 — maintained at every cut
- [ ] **Dogfooded** in real AGNOS pipelines for one minor-cycle window
- [ ] **Downstream gate** — at least one consumer green

---

## Dependency map

Versions live in [`state.md` § Dependencies](state.md#dependencies); this is the
durable shape and the rationale.

| Dep | Provides | Notes |
|-----|----------|-------|
| **darshana** | ANSI escape generation — `tty_fg_rgb_buf`, `tty_fg_256_buf`, `tty_sgr_buf`, `tty_sgr_reset_buf`, `tty_sgr_reset`, `tty_cursor_up` / `_hide` / `_show`, `tty_isatty` | v1.0.0 is the API freeze; anuenue's nine call sites are all inside the frozen 29-function surface. anuenue never emits a raw escape. |
| **cmdit** | CLI / argument parsing (getopt-long) | Adopted at v1.1.4, replacing the stdlib `flags` parser. anuenue is cmdit's second worked migration, after kii. |
| **sakshi** | Errors / tracing / structured logging | Canonical per first-party-standards. Wired at v1.2.1 (`src/observe.cyr`). **stderr only** — the file and UDP output targets would breach the capability bound and are never selected. |
| **agnostik** | Shared Result / Error shapes | Wired at v1.2.1. Every failure returns through `anuenue_fail(kind, msg)`; `STIK_ERR_INVALID_ARGUMENT` → exit 2, everything else → exit 1. |
| **Cyrius stdlib** | string, fmt, alloc, io, vec, str, syscalls, assert, bench, args, chrono | `flags` was dropped at v1.1.4; `chrono` added at M4 for frame timing. |

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

---

## Pipe-decorator family successors

Idea-tier, no commitments. Captured so v1.x architectural decisions leave room
for siblings, and because [ADR 0002](../adr/0002-hsv-inline-not-abaco.md)'s
first revisit trigger fires when the second of these wants a rainbow.

- `boxes`-equivalent — wrap stdin in ASCII borders
- `cowsay`-equivalent — ASCII speech bubble
- `pv`-equivalent — pipe-viewer with throughput indicator

They earn entries in
[shared-crates.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md)
when they become real.
