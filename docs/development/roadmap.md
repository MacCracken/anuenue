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

**v1.4.4.** The v1.x contract — exit codes, output shape, capability surface —
has been frozen since GA and is unbroken; the flag set has only ever grown. Six
audits have run, the latest the [v1.4.x delta](../audit/2026-10-14-v14x-delta.md),
all with zero HIGH+ open, and since v1.4.4 **no guard is recorded as unproven**.
The one 1.4.x slot left waits on the cyrius 6.7.11 tag; the 1.5+ minors are
gated on things anuenue cannot do itself (a consumer landing, a sibling filter
appearing).

## Release map

| Release | Slot | Gate |
|---------|------|------|
| [v1.4.5](#v145--cyrius-67x--sakshi-2510-through-the-snapshot) | cyrius 6.7.x — sakshi 2.5.10 through the snapshot | cyrius 6.7.11 tagged |
| [v1.5.0](#v150--adoption) | Adoption | a consumer integration lands |
| [v1.6.0](#v160--pipe-decorator-family) | Pipe-decorator family | a second pipe-decorator wants a rainbow |
| [v1.x](#v1x--trigger-gated) | Trigger-gated | the first minor after each trigger fires |
| [v2.0](#v20--reserved) | Reserved | nothing queued |

The 1.4.x order was fixed at v1.4.2: the toolchain move is the arc's last
patch, after the v1.4.4 closeout, so v1.4.5 re-runs the closeout's build-level
gates itself — see that slot.

---

## v1.4.5 — cyrius 6.7.x + sakshi 2.5.10 through the snapshot

> **Status:** waiting on the cyrius 6.7.11 tag (in progress upstream; 6.7.10 is
> the latest tag as of 2026-10-14). Take the latest 6.7.x tag at the time of
> the cut; 6.7.11 is the first that carries sakshi 2.5.10.
>
> **The arc's last patch, after the closeout.** Because it lands after v1.4.4,
> it re-runs the closeout's build-level steps itself: full test suite, benchmark
> baseline, downstream check (thoth's vendored `dist/anuenue.cyr`), version
> verify, and the clean build (`rm -rf build && cyrius deps && CYRIUS_DCE=1
> cyrius build`). Also re-run `scripts/fault-check.sh`'s capability-surface
> layer: a stdlib change is exactly what moves a route's syscall set.

From v1.4.1 sakshi is a stdlib module, so it moves with the toolchain pin and
nothing else ([`cyrius.cyml`](../../cyrius.cyml) `[deps]`). The bump is worth
taking for what the snapshot carries, not for the compiler:

| Toolchain | sakshi in its snapshot | What it changes for anuenue |
|-----------|------------------------|-----------------------------|
| 6.7.9 (current) | 2.5.8 | — |
| 6.7.10 | 2.5.9 | cx-target support only; native output byte-identical. `str.cyr` gains three JSON helpers. **Nothing anuenue needs** — not worth a cut on its own. |
| **6.7.11** | **2.5.10** | sakshi's four private buffers declared in bytes, not slots: **−60 144 B** of static data. Measured at v1.4.1 in a scratch trial (6.7.10 + a shadowing 2.5.10): 223 872 → **163 728 B**, about a quarter of the binary. |

Work:

- `rm -rf lib cyrius.lock && cyrius lib sync --full && cyrius deps`, then
  `cyrius distlib --all`. Confirm `lib/sakshi.cyr`'s `# Version:` reads 2.5.10.
- **6.7.11 adds cyrlint rules for array overrun and write length.**
  `scripts/lint-check.sh` lints `src/`, `tests/` and `fuzz/`, so expect them to
  run over all three. v1.4.1 fixed one overrun of exactly that shape by hand
  (`fuzz/flag-parser.fcyr`'s `solo_tokens[44]` holding 88 bytes); others may
  surface.
- **If cyrius fixes `args_init`'s 2 MiB cut**
  (`docs/development/issues/2026-10-14-args-init-truncates-argv-past-2-mib.md`
  upstream), `robustness-check.sh` gate 7's over-2 MiB check inverts: the command
  line parses whole and `--seed 99` is honoured. Update the check to assert that.
  The `--nofile=3` check is unaffected — no descriptor is no descriptor.
- Gates: stdout identity against the previous release across corpora × flags,
  every `scripts/*-check.sh`, a size-attribution row in `state.md`.

---

## v1.5.0 — Adoption

> **Status:** gated on a consumer integration. The minor is cut when its first
> item is ready; patches continue on 1.4.x until then.

The two v1.0 acceptance items still open — eight of ten closed at GA. Neither is
code anuenue can write; both close retroactively once an integration lands.

- **Dogfooded** — `iam | anuenue` MOTD or `bnrmr | anuenue` banners running in a
  real AGNOS pipeline for at least one minor-cycle window.
- **Downstream gate** — at least one consumer green against v1.x (`agnoshi`
  MOTD chain or `iam`'s default login chain anticipated). Listed in
  [`state.md` § Consumers](state.md#consumers) once real. *Noted at v1.4.4:*
  thoth already consumes the **library** surface — it vendors
  `dist/anuenue.cyr` (at 1.3.6, code-identical to 1.4.4's) for `/theme
  rainbow`, and is green. Whether a library consumer closes this item, which
  named pipeline consumers, is the user's call; until then it stays open.

Additive surface an integration asks for lands here. One candidate is on file:

- **`-vvv` repeat-count verbosity** — trigger: a consumer asks.
  `--log-level=trace` is self-documenting in a script and greppable in shell
  history; `-v` covers the interactive case. cmdit supports repeat counts, so
  the cost is low if the ask arrives.
  ([ADR 0004 § Alternatives](../adr/0004-stderr-only-observability.md))

## v1.6.0 — Pipe-decorator family

> **Status:** gated on a second pipe-decorator wanting a rainbow tint.

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

## v1.x — trigger-gated

Pinned to the first minor after the trigger fires.

| Item | Trigger | Source |
|------|---------|--------|
| **Pass escape sequences in the input through intact** | A consumer pipes coloured text (`ls --color=always \| anuenue`). Today anuenue's own escape before every cluster cancels each input ESC, so `ESC [31m` prints as `[31m`, on every route; v1.4.4's review measured it (audit H-06). Options: strip input SGR (Ruby lolcat's choice), or treat a whole input sequence as one zero-width, untinted cluster. Either changes stdout bytes, so it needs an owner. | [v1.4.x audit delta H-06](../audit/2026-10-14-v14x-delta.md) |
| **Follow a resize mid-animation; animate a block taller than the terminal** | A consumer asks. v1.4.4 (H-01) reads the size once, before the first frame, and draws a block that cannot fit once. Following SIGWINCH means a signalfd mask change and a re-read per frame; animating an oversized block means a clipping policy (which rows?) nobody has specified. | [ADR 0005 § Consequences, § Alternatives](../adr/0005-practical-subset-display-width.md) |
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
  contract is byte preservation; `robustness-check.sh` asserts all 256 byte
  values pass through. Neutralising control bytes in stdin would break the
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
  i64 (the negate-MIN case). Unchanged in cmdit 1.4.0, and nothing upstream
  tracks it — worth filing at cmdit. Rejecting is the safe direction.
- **cyrius: `args_init` cuts the command line at 2 MiB** (one read of
  `/proc/self/cmdline` into a fixed buffer). Filed upstream 2026-10-14. Since
  v1.4.1 anuenue reports it (exit 1, via cmdit's `CMDIT_ERR_ARGV`) instead of
  parsing a prefix; the fix is the stdlib's. See v1.4.5 for what changes here
  when it lands.
- **cyrius: growing a large function miscompiles code far from the growth.**
  At v1.4.3, appending one more group (about forty lines, nine locals, a 40-byte
  array) to the end of `tests/anuenue.tcyr`'s `main()` made the suite die
  with SIGSEGV in its *third* group — a cmdit parse, long before the new code
  runs. Same on cyrius 6.7.9, 6.7.10 and 6.7.11. Not the local count (twelve
  extra int locals pass), not an array local (40 bytes pass), not code size
  (forty extra statements pass). The same lines in their own function pass.
  **Filed** as cyrius `docs/development/issues/2026-10-14-anuenue-growing-a-large-fn-segfaults-an-earlier-call.md` (2026-10-14), with a
  reproduction pinned to anuenue tag 1.4.2. anuenue's part ends at filing; a
  cyrius agent investigates and fixes. Re-check at each toolchain bump.
- **agnostik: `agnostik_err_new` writes through an unchecked `alloc(24)`.**
  Filed 2026-10-14 as agnostik
  `docs/development/issues/anuenue-agnostik-err-new-unchecked-alloc-2026-10-14.md`.
  The window in anuenue is narrow: `anuenue_fail`'s `str_new` would have to
  succeed and the very next small allocation fail. Re-check at each agnostik
  bump.
- **darshana: `cyrius distlib` reports `tty_winsize` undefined on
  x86_64-windows / x86_64-macos / aarch64-macos.** A warning on every
  `cyrius distlib` run, present at v1.4.0 too. None of those is an anuenue
  target, and `dist/anuenue.cyr` exports only `src/hsv.cyr`.

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
  previous report — the next is at the v1.5.0 cut. Six have run, latest the
  [v1.4.x delta](../audit/2026-10-14-v14x-delta.md).
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
  historical figure, in all three `COLOR=` modes. M5 acceptance: ASCII no-LF
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
