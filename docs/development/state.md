# anuenue — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures
> (durable); this file is **state** (volatile).

## Version

**1.3.5** — cut 2026-08-26. **stdin failure surface.** The surface the
v1.3.3 sweep ranked highest after the allocation probe — and the
**mirror of E-01**: three audits had examined stdin exhaustively for
*content* and never for *failure*. It had the mirror defect.

**F-01 (MEDIUM)** — `file_read` is a bare `sys_read` and all three
stdin call sites (filter, MONO passthrough, animation slurp) classed
**any** negative return as fatal. But `EAGAIN` on a non-blocking stdin
means "no data *yet*", not "broken" — a writer merely slower than the
reader triggers it. Measured: feeding 6 500 bytes through a
non-blocking pipe in 64-byte chunks, every path rendered **64 bytes**
and exited 1 with "read from stdin failed" — 99% of a perfectly good
stream discarded, reporting an I/O error that had not happened.

MEDIUM rather than HIGH because it is *loud*: exit 1 with a message, so
a script can detect it. E-01 was silent at exit 0, which is what put it
a severity higher.

Fixed with `anuenue_read_some`, deliberately symmetric to
`anuenue_write_all` — **the two sides of a filter should not disagree
about what counts as an error.** EAGAIN sleeps 1 ms and retries, no
attempt cap (a writer that is *gone* closes the pipe, which is EOF).
All three paths now render 6 500/6 500 at exit 0, and a real read
failure still exits 1.

⚠ The EINTR branch is **unproven**: anuenue installs no handlers and
default-disposition signals do not interrupt a blocking read — verified
by driving SIGSTOP/SIGCONT/SIGWINCH/SIGCHLD/SIGURG at a process blocked
in `read`.

*Also in this cut, from a CI lint failure:* a comment reading `mean
"not yet", not "broken"` tripped the deferral heuristic — prose, not a
deferral, reworded rather than suppressed. **The local gate reported
success**: `cyrius audit`'s lint section prints "ok: lint clean"
*without* counting untracked deferrals, while `cyrius lint <file>`
counts them. Second time in two cuts a local check passed for a reason
unrelated to what CI enforces (E-03 was the first). Fixed structurally
with `scripts/lint-check.sh` — one implementation, called by both, and
it lints `tests/`/`fuzz/` too, which immediately surfaced an untracked
deferral in `tests/anuenue.bcyr` whose cross-reference sat one line
below the keyword.

Gate 6 in `robustness-check.sh`, mutation-proven: removing the retry
fails all three path checks while the closed-stdin control still
passes, so the gate distinguishes "retries transient errors" from
"ignores errors". Perf flat (mixed signs across corpora), binary
unchanged at **814 488 B**.

**1.3.4** — cut 2026-08-26. **Allocation-failure probe + a CI fix.**

**E-03 — CI failed on v1.3.3, and the bug was in the v1.3.3 fix.**
E-01 made every stdout write checked and classed **EPIPE as fatal**.
Wrong: EPIPE means the consumer closed the pipe (`anuenue | head -1`),
the normal end of a pipeline. It passed locally because SIGPIPE's
default disposition has the kernel kill the process before `write(2)`
returns — so the branch never executed, and the v1.3.3 audit's
"verified" rested on a configuration in which the code under test did
not run. A CI runner sets SIGPIPE to `SIG_IGN`, children inherit it,
and CI executed that branch for the first time. Fixed: EPIPE exits 0
in silence, every other errno still reports and exits 1.

**The gate that should have caught it was wrong twice over.** It ran
only the default disposition — where the branch is unreachable — and
used a 256-byte corpus that fits entirely in a pipe buffer, making
"does a second write happen at all" a race. Both fixed; `trap '' PIPE`
reproduces the CI environment in plain shell. Mutation-proven, and the
proof is pointed: deleting the dispatch leaves the SIGPIPE-default row
**still passing** and fails only the SIGPIPE-ignored row.

*Lesson:* **a passing test proves nothing if the environment makes the
code under test unreachable.** Same family as the v1.2.2 finding about
accepted-but-unmeasured INFO items, and the v1.3.2 one about gates
stated but never executed — three variants of "the check looked green
for a reason unrelated to the thing it names".

**Allocation-failure probe.** Closes the standing "unproven guard"
gap — the surface the v1.3.3 sweep ranked first.

Three audits in a row recorded guards they could not test (A-01 at
v1.2.2, E-01 at v1.3.3, plus eight other `alloc` call sites), all for
one reason: nothing could drive `alloc` to return 0 from outside the
process, so deleting any of them left the suite green.

`tests/probes/allocfail-probe.cyr` + `scripts/allocfail-check.sh` — 15
checks against a genuinely exhausted heap. The mechanism needs a narrow
window: `lib/alloc.cyr` returns 0 only when a *fresh* 256 MiB chunk
cannot be mapped, and `alloc_init` calls `exit(1)` if the *first* one
fails — so `prlimit --as=400MiB` is exactly one chunk's headroom, first
maps, second cannot. The probe drains the first chunk, after which
every allocation returns 0 however small.

**Mutation-proven more sharply than usual:** deleting A-01's guard or
E-01's `str_new` fallback makes the probe **segfault (139)**, not fail
an assertion. The gate script names that case explicitly.

Now tested rather than asserted: `_cp_ext_init` reports failure instead
of writing 42 words through null and `cp_is_extending` degrades so
**output stays byte-correct**; `_phase_esc_init` reports failure;
`anuenue_fail` returns the right exit code with **no heap at all**
(a reporter that allocated could never report an OOM); and all four
driver entry points fail at the allocation rather than proceeding with
a null buffer.

`tests/probes/` is now a pattern rather than a one-off — both probes
exist because anuenue's CLI cannot be driven under a resource limit at
all, since `args_init()` reads `/proc/self/cmdline`
([architecture 006](../architecture/006-argv-costs-a-file-descriptor.md)).

Test infrastructure only; no source change. Binary unchanged at
**814 480 B**.

**1.3.3** — cut 2026-08-26. **P(-1) audit sweep.** 2 findings —
**1 HIGH**, 1 INFO — both fixed in-cut, zero HIGH+ open.
[`docs/audit/2026-08-26-audit.md`](../audit/2026-08-26-audit.md).

**E-01 (HIGH)** — every stdout write was unchecked. `file_write` is a
bare `sys_write` with no short-write loop, and anuenue discarded its
return at all 17 call sites plus two raw syscalls. Measured:
`> /dev/full` lost **100%** of the output at exit 0; a non-blocking
stdout with a slow reader lost **99.3%** (1 000 000 bytes in, 7 290
out) at exit 0. For a filter whose contract is byte preservation, that
is the worst available failure mode — silent, with a success code.
**Shipped in every release since v0.2.0.** Fixed with
`anuenue_write_all`: loops until every byte lands, EINTR retries,
EAGAIN sleeps 1 ms and retries (no attempt cap — a live-but-slow
consumer deserves backpressure, a gone one yields EPIPE), everything
else exits 1 with a named error. `anuenue | head -1` still behaves as
SIGPIPE, asserted.

**E-02 (INFO)** — the escape-table cache was keyed on "built" rather
than on which mode built it, so a mode change silently returned stale
escapes. Unreachable in the shipped binary, but it caught this audit's
own probe. Now mode-keyed.

**Why three audits missed the HIGH:** all three worked the *input*
side. This sweep opened by asking what no audit had ever examined, and
the answer was the output side. Recorded as method in the report —
**pick the surface by asking what has never been looked at**, not by
re-running what worked last time.

Also corrected `docs/architecture/001`, which asserted a 19-byte
maximum escape by arithmetic. Measured maxima are 16-colour **5**,
256 **11**, truecolor **17** — `hsv_rainbow` runs the cube edges at
S=V=1 so one channel is always 0.

*Verification:* **380/380** unit assertions (was 364), 6 fuzz
harnesses, six goldens byte-identical, all seven gate scripts green.
Perf measured back-to-back against a rebuilt v1.3.2 binary: a real but
small **+0.5%** cost from the per-flush check — well inside the
60 ns/byte cap, and not a close trade against silent 99.3% data loss.
Binary 814 448 → **814 480 B**.

**1.3.2** — cut 2026-08-25. **v1.3.x closeout.**

No remaining roadmap item was actionable, so this cut discharged what
the arc *owed*: two gates v1.3.0 stated and never executed.

**Perf, finally measured.** v1.3.0 restructured the animation frame
loop into `_frame_wait` and was marked complete without running its own
perf gate; `docs/benchmarks.md` had no v1.3.x row at all. Head-to-head
against a rebuilt v1.2.2 binary (`RUNS=11`, idle host): filter path
46.22 → **46.61 ns/byte** (+0.8%), animation CPU over three 3-second
runs 5.0 → **5.1 ms**. Both within noise — at the default 16 ms
interval with a 16 ms tick, `_frame_wait` does exactly one slice, the
same single sleep + signal probe + deadline check as before. And the
question slicing raised is answered: at `-i 200` each frame pays 12
extra signal probes and 12 extra clock reads, yet total CPU **falls**
(3.8 → 3.0 ms) because a longer interval renders far fewer frames.
Slicing is free.

**Audit delta** — [`2026-08-25-v13x-delta.md`](../audit/2026-08-25-v13x-delta.md).
One finding, **D-01 (INFO)**: `_frame_wait`'s termination depended on
`ANUENUE_TICK_MS` being positive, an invariant held by a unit test
rather than by the code — a zero tick would spin forever inside
animation with the exit signals blocked. Guarded structurally, and
recorded as **unproven**: no public API can reach it, so deleting the
guard keeps the suite green. Plus the full CLAUDE.md closeout sweep —
capability surface unchanged, 10 allocation sites all guarded, zero
dead functions, zero unused constants, no stack buffer ≥ 1 KB, no stale
deferral language, every doc link resolving.

*The lesson:* **a gate that is stated and not executed reads identically
to one that passed.** Same shape as the v1.2.2 finding that the
2026-05-22 audit's accepted INFO items were claims carried forward as if
they were measurements.

Binary **814 448 B**, unchanged from v1.3.0 — v1.3.1 was tests and docs,
v1.3.2 is one guard line.

**1.3.1** — cut 2026-08-25. **PTY-backed animation.** The one item
carried out of the v1.3.0 slot, on its own cut because everything else
in that slot was reachable from a pipe and this is not.

`scripts/pty-check.sh` (14 checks, CI-wired, skip-clean without
`script(1)` or `/dev/ptmx`) drives anuenue through a real
pseudo-terminal. **The colour auto-detection chain had never been
exercised by any test**: on a pipe, `anuenue_detect_color_mode` exits
at "stdout is not a TTY" and everything below — `COLORTERM`, the
`TERM` heuristics, the 16-colour fallback — is unreachable, and every
existing animation test passes `--color=24bit` to route around it. The
harness covers seven exits of that function under a TTY, asserting
both the resolved mode **and the reason** (v1.2.1's observability is
what makes the branch identifiable). It also covers MONO byte-exactness
on a colour-capable terminal, cursor-lifecycle ordering, and
SIGINT-during-animation — the success path the signalfd was written
for, whose failure mode (B-01) and latency (B-02) were covered at
v1.3.0.

**No new defects.** That is a result, not a null one: "the
auto-detection chain is correct" had been an assumption for eight
minors rather than a measurement.

Two harness facts worth keeping: `pgrep -x`, not `-f` — `script(1)`'s
argv contains the anuenue command line, so `-f` signals the wrapper
and the test hangs; and `script(1)` does not propagate `TERM`, so each
detection case sets it inside the command.

Also corrected an over-promise in the roadmap: an earlier draft said a
PTY would let terminal state be *read back*. It does not —
`script(1)` transcribes bytes and does not emulate a terminal.

**1.3.0** — cut 2026-08-25. The animation slot from
[roadmap.md § v1.3.0](roadmap.md#v130--animation-slot).

*Landed:* `-i` / `--interval <ms>` frame-interval override, and the
re-measurement of the 2026-05-22 audit's INFO 8 + 9 — which turned out
to be a **real defect**, not the accepted non-issue three audits had
recorded.

*Three defects the new flag exposed*, all fixed in-slot:
**B-01 (MEDIUM)** `_open_exit_signalfd` leaked its `SIG_BLOCK` when
`signalfd(2)` failed, leaving HUP/INT/TERM blocked with no fd to drain
them — Ctrl-C inert, `kill` inert, hangup inert, only SIGKILL working
(the same defect darshana fixed at v0.9.3; anuenue's hand-rolled copy
predates it). **B-02 (MEDIUM)** the frame loop slept a whole interval
before checking for signals, so `-i 3600000` made the process
unresponsive to SIGTERM for an hour — `timeout(1)` could not kill it.
**B-03 (LOW)** `--duration` overshot by up to one interval, same cause.
`_frame_wait` now slices the wait at `ANUENUE_TICK_MS` (16 ms), so
signal latency and deadline accuracy no longer depend on `-i`.

*Why the interval is clamped:* `sleep_ms` is `poll(NULL, 0, ms)` and
poll(2)'s timeout is a 32-bit **int**, so a large i64 truncates
**non-monotonically** — `2147483648` → −2³¹ → blocks forever;
`4294967296` → 0 → busy loop; `i64::MAX` → −1 → blocks forever. A big
`-i` therefore gives a hung terminal or a spin, never a slow
animation. Clamped at 3 600 000 ms, warned when clamped.

*Why INFO 8 + 9 went unmeasured for three minors:* the obvious test —
run the CLI under `prlimit --nofile=3` — **cannot work**, because
`args_init()` opens `/proc/self/cmdline` to read argv, so under that
limit the binary never parses a flag and never reaches animation.
`tests/probes/sigmask-probe.cyr` sidesteps it: no `args_init`, no file
reads, and it observes the mask through
`sigprocmask(SIG_BLOCK, <empty>, &oldset)` — a pure query needing no
descriptor. Mutation-proven.

*New gate:* `scripts/signal-check.sh` (12 checks, CI-wired).
**364/364** unit assertions (was 349). Binary 809 984 → **814 448 B**.

*Also in the slot:* `fuzz/flag-value-parsers.fcyr` — the sixth harness
and the first to fuzz strings rather than integers (**+96 091
assertions**; fuzz total 1 354 581 → **1 450 672**), covering totality,
one-byte-mutation exactness, name totality over arbitrary i64, and
`parse(name(p)) == p`. And `docs/architecture/` populated with six
notes, each recording something the v1.2.2 audit or this slot had to
discover. The PTY test moved to v1.3.1.

**1.2.2** — cut 2026-08-25. **P(-1) audit sweep + the size cap is gone.**

Full audit / refactor / hardening / optimization / security pass over
the whole source: **9 findings — 2 MEDIUM, 5 LOW, 2 INFO, all fixed
in-cut, zero HIGH+ open**. Write-up in
[`docs/audit/2026-08-25-audit.md`](../audit/2026-08-25-audit.md).

The two MEDIUMs: `_cp_ext_init` wrote 42 words through an **unchecked
`alloc`** (null-pointer write on OOM; `_phase_esc_init` 200 lines above
already checked — this site never got the same treatment), and
`--duration` **overflowed to a deadline in the past**, so
`-a -d <i64::MAX>` exited after one frame instead of running ~292 years.
Three LOWs were the same defect in different clothes — a silent fallback
where an error belonged (negative `-d` meaning "forever", unknown
`--color` meaning "auto", animation caps dropping input in silence).
A-09 is the compound interest: fixing the `--color` fallback made
`docs/examples/06-no-color.sh` fail, revealing that `--color=mono` had
been **documented since M6 and never implemented** — the fallback had
been hiding our own broken documentation from our own CI-run example
suite.

Method note worth keeping: **A-01 was found by reading; A-02 through
A-05 were found by running.** Each looks correct in isolation. The
adversarial corpora that found them are now permanent as
`scripts/robustness-check.sh` (11 checks, CI-wired): UTF-8 carry across
the 4096-byte read boundary (52 comparisons, chunked vs `dd bs=1`), byte
preservation under malformed UTF-8 (116 comparisons — overlongs,
surrogates, >U+10FFFF, all 256 byte values), argv at both i64 extremes,
and one process-level regression per finding.

**The 512 KB binary cap is removed.** It was set at v0.7.1 when the
binary was ~350 KB and essentially all of it was anuenue. The number no
longer measures that: the first-party dep surface is the floor (agnostik
alone is ~546 KB against ~2 400 lines of anuenue source), `CYRIUS_DCE=1`
stopped removing anything on 6.5.x, and no CI step ever enforced it — so
its only real effect was to make every dep bump read as a regression.
Replaced with **track and attribute**; see [Binary](#binary).

*Verification:* `cyrius audit` clean on all three gates (fmt / lint /
docs — fmt and docs were both failing at the start of the sweep).
**349/349** unit assertions across 46 groups (was 308/42), **1 354 581**
fuzz assertions, six goldens byte-identical, animate-smoke 17,
observe-check 22, robustness-check 11. Perf unchanged head-to-head
(`RUNS=11`, idle host): ASCII no-LF 46.57 → **46.64 ns/byte**, w/ LFs
50.98 → **50.97**, UTF-8 41.66 → **41.71** — all under the 60 ns/byte M5
cap. `hsv_rainbow` holds at 8 ns across the A-07 sector-table refactor.
Binary 809 520 → **809 984 B** (+464).

**1.2.1** — cut 2026-08-25. **Toolchain + deps + observability + CI repair.**

*Toolchain/deps:* cyrius pin `6.4.62` → `6.5.35` (`./lib/` re-synced via
`cyrius lib sync --full`, 108 stdlib files; four new modules —
`async_macos`, `async_win`, `thread_macos`, `yantra`), darshana `0.9.0`
→ **`1.0.0`** (the API freeze), cmdit `1.1.0` → **`1.2.4`** (the P-1
audit cut), sakshi `2.4.6` → **`2.4.11`**, agnostik `1.3.4` →
**`1.5.1`**. Manifest tags had drifted from the vendored bytes; tags and
bytes now agree.

*Observability (`src/observe.cyr`, new):* sakshi and agnostik had been
declared deps since the M0 scaffold with **zero call sites in any
anuenue source file** — linked into every binary and never called. Now
wired: `-v` / `--verbose` and `--log-level=<off|fatal|error|warn|info|
debug|trace>` emit structured sakshi records, and the three real failure
paths (stdin read error, buffer allocation, escape-table allocation)
carry agnostik kinds and codes. Highest-value line is the colour-mode
**reason** — v1.1.5's AGNOS colour collapse was a wrong branch in
`anuenue_detect_color_mode` that no output could distinguish from a
right one; `-v` now names the branch.

*Pipe-purity:* every diagnostic byte goes to fd 2. `sakshi_set_output_fd(2)`
pins the sink (file/UDP targets never selected, so the capability bound
holds and the syscall surface stays read/write/brk/exit), and logging is
off by default (sakshi's own default is `SK_INFO`, which would have put
lines on the stderr of every MOTD). Enforced by
`scripts/observe-check.sh`: stdout byte-identical across 144 corpus ×
colour-mode × verbosity combinations, stderr empty in every
default-verbosity run.

*CI repair:* both workflows hand-rolled the toolchain install into the
**pre-6.5** `$HOME/.cyrius/{bin,lib}` layout. From 6.5.x `cyrius deps`
resolves the stdlib snapshot from `versions/<v>/lib` and hard-fails
without it — so the pin bump would have broken CI on the first push.
Replaced with the upstream installer (darshana's pattern) plus a
layout-verification step. `CYRIUS_DCE=1` — a CLAUDE.md hard rule never
actually set — is now set in both. Lint, observability and distlib-drift
gates added.

*Verification:* v1.2.0 vs v1.2.1 stdout byte-identical across 192
comparisons (16 corpora × 12 flag combinations), exit codes matching on
all 192. Six goldens byte-identical, three MONO checks hold,
animate-smoke green across truecolor / 256 / 16 / long-cluster.
**308/308** unit assertions (was 242, +66), **1 354 581** fuzz
assertions, `cyrius lint` clean on all eight `src/*.cyr`. Perf unchanged
head-to-head on one idle host (`RUNS=11`): ASCII no-LF 47.20 →
**46.63 ns/byte**, w/ LFs 50.98 → **50.99**, UTF-8 42.45 → **41.77** —
all under the 60 ns/byte M5 cap. Diagnostics are O(1) in input size
(exactly 10 records whether the stream is 1 KB or 5 MB).

*Fixed in-cut:* a failing filter previously returned bare `1` with no
message on any fd — it now names the error (exit codes unchanged). A
`Str` coercion trap on cyrius 6.5.35 (literals are **not** coerced in
return-expression position) would have shipped every error message
empty; `anuenue_fail` converts explicitly with `str_new`. One untracked
deferral in `src/filter.cyr` surfaced by the stricter 6.5.35 lint.

**Binary** 389 648 → **809 520 B** (+419 872, +108%) — toolchain and
dep surface, not anuenue code. See [Binary](#binary).

**1.2.0** — cut 2026-07-14. **Library surface.** `dist/anuenue.cyr`
distlib (`[lib] modules = ["src/hsv.cyr"]`) — the pure HSV phase model
becomes consumable in-process (first consumer: thoth's `/theme rainbow`).
Filter / animate / colour / CLI machinery stays app-only.

**1.1.5** — cut 2026-06-26. **Fixed:** rainbow collapsed to 16 colours on
AGNOS (`anuenue_detect_color_mode` fell through env heuristics agnos
doesn't set); agnos now defaults to `ANUENUE_COLOR_TRUE`. Toolchain pin
`6.2.24` → `6.2.44`.

**1.1.4** — cut 2026-06-25. **CLI parsing → cmdit.** Dropped the stdlib `flags`
parser for the `[deps.cmdit]` 1.1.0 distlib (cmdit IS that parser productized +
extended, so byte-compatible): `flags_*` → `cmdit_*`, `cmdit_new` auto-registers
`--help`/`--version`, `cmdit_parse` absorbs the hand-rolled `build_argv_array` bridge
(the 256-arg cap + manual help/version regs gone — `src/main.cyr` −21 lines).
`print_usage` keeps anuenue's intro/Usage/Examples framing and calls
`cmdit_help_flags` (cmdit 1.1.0's table-only renderer) for the flag rows. No
behavioural change: all six goldens byte-identical, three MONO checks hold, **242/242**
unit tests green. anuenue is cmdit's second worked migration (after kii).

**1.1.3** — cut 2026-06-19. **Toolchain + dep refresh.**
Maintenance cut: cyrius pin `6.1.14` → `6.2.24` (`./lib/` re-synced
via `cyrius lib sync`, 98 stdlib files) plus the first-party-dep
sandhi refresh accumulated since GA — darshana `0.5.3` → `0.7.1`,
sakshi `2.2.5` → `2.4.0`, agnostik `1.2.2` → `1.3.1`. No
behavioural change: all six goldens byte-identical, three MONO
equivalence checks hold, animate-smoke (truecolor / 256 / 16 /
long-cluster) green, perf unchanged within noise (ASCII no-LF
**46.59 ns/byte**, under the 60 ns/byte M5 cap). One latent bug
surfaced by the stricter 6.2.24 front-end and fixed in-cut:
`tests/anuenue.bcyr` was missing `include "src/color.cyr"`, so
`filter.cyr`'s `ANUENUE_COLOR_MODE` reference dangled (tolerated
by 6.1.14, errored by 6.2.24); include added before `filter.cyr`.
DCE binary 351 200 → **394 440 B (+43 240)** — the toolchain + dep
bumps; ~115 KB headroom under the 512 KB cap. 245/245 unit
assertions pass; v1.x API contract unchanged.

**1.0.0** — **GA.** Tagged 2026-05-22 on user signal — the
eleventh release, two calendar days after the `cyrius init anuenue`
scaffold. The public API contract (flag set, exit codes, capability
surface, output shape) is frozen for the v1.x line.

8 of 10 v1.0 acceptance criteria met at tag (see
[roadmap.md § v1.0 acceptance scorecard](roadmap.md#v10-acceptance-scorecard)); **Dogfooded**
and **Downstream gate** are deferred to post-1.0 organic adoption.
Both block on external consumer wiring — `agnoshi` MOTD pipeline
composition or `iam`'s default login splash are the anticipated
first consumers. The v1.0 *contract* is frozen; *adoption* is not
a contract property the project can satisfy unilaterally, and
shipping v1.0 is what gives consumers the stable target they need
to build against.

No behavioural changes vs v0.9.0; no dep bumps; DCE binary
**351,200 B unchanged**. The cut is a symbolic crystallisation —
everything that made it into v0.9.0 *is* v1.0, just with the API-
freeze contract attached. Sandhi-bump cadence continues within
v1.x; breaking surface changes earn v2.0.

**0.9.0** — cut 2026-05-22 (tenth release; sixth same-day cut).
**Quality slot — fuzz harness + animation smoke breadth +
structural cleanup.** No behavioural changes, no flag-
surface changes, no dep bumps. Three threads landed together:

1. **`fuzz/` directory populated.** Five harnesses targeting the
   surfaces the M8 audit identified — flag parser, UTF-8,
   `_pretag_clusters`, `_emit_phase_esc`, RGB quantizers — each
   using a Knuth-MMIX LCG for deterministic seed-driven
   exploration and returning `assert_summary()` so failed
   invariants set a non-zero exit code (the `assert` library
   prints-but-doesn't-abort; the exit-code propagation is what
   makes `cyrius fuzz` a real CI gate). Combined **1 354 580
   assertions** per run, zero failures. CI wired (`cyrius fuzz`
   step in `.github/workflows/ci.yml`).
2. **Animation smoke breadth.** `scripts/animate-smoke.sh` now
   covers `--color=256` and `--color=16` under `-a` in addition
   to the M4 truecolor path + M8 long-cluster regression. Each
   per-mode section asserts clean exit, full cursor lifecycle,
   and the per-mode SGR shape (CSI `38;5;Nm` for 256-color, CSI
   `9[1-7]m` for 16-color; explicit no-leak check that truecolor
   `38;2;…` doesn't appear under `--color=256`). Closes the
   carry-forward documented since v0.7.0.
3. **Structural cleanup.** The M0-anticipated `src/hsv.cyr` split
   finally lands — `ANUENUE_PHASE_MOD` + `hsv_rainbow` extracted
   into their own file. Triggered by the fuzz harness's
   `emit-phase-esc` target wanting a clean boundary; ADR 0002
   documents the broader "HSV inline, not abaco" reasoning.
   Plus a column-width pass on `src/main.cyr`'s flag-registration
   lines clearing the 5 pre-existing `cyrius lint` warnings
   flagged during the v0.8.0 closeout. DCE binary unchanged at
   **351 200 B** — the v0.9.0 work didn't touch the production
   surface, only moved code between files + added test/fuzz
   infrastructure.

Bug caught on the harness's own first run: my initial
`fuzz/flag-parser.fcyr` asserted `rc >= 0` but `lib/flags.cyr`
documents `flags_parse` as returning `-1` on error. Without the
exit-code-propagation change (`return assert_summary()`), the
failed assertion would have silently passed CI 12 times per run.
Fixed before the harness landed.

**0.8.0** — cut 2026-05-22 (ninth release; fifth same-day cut).
**M7 (docs) + M8 (security audit) folded into one cycle.** M7 shipped three ADRs (0001 pipe-purity / 0002 HSV-inline /
0003 grapheme-cluster cycling), the
[`docs/guides/integrating-anuenue.md`](../guides/integrating-anuenue.md)
downstream-consumer guide, eight runnable examples under
[`docs/examples/`](../examples/), and a `print_usage` Examples refresh
in `src/main.cyr` covering the M6 flags. M8 audit
([`docs/audit/2026-05-22-audit.md`](../audit/2026-05-22-audit.md))
turned up **one HIGH-severity finding**: `_render_frame` heap
overflow on long-cluster animation input (base char + ~32 500
combiners → 65 KB single cluster overflowing the 32 KB `line_buf`).
**Fixed in-cycle** via a mid-cluster flush guard in
`src/animate.cyr`'s byte-copy loop — flush + re-emit the same
phase escape when the reserve threshold trips mid-cluster. Visible
colour stays consistent; the buffer never overruns. Filter path
(`anuenue_filter`) was not affected because it writes one
codepoint per iteration. Regression coverage: new
`scripts/animate-smoke.sh` long-cluster section (16 000 combiners
after a base char; asserts clean exit + full byte preservation)
and a new tcyr group ("M8 audit — _pretag_clusters long-combiner
chain", 4 assertions; 241 → **245 total**). Zero HIGH+ findings
open at the end of the audit. Capability surface confirmed clean
(see [`docs/audit/2026-05-22-audit.md`](../audit/2026-05-22-audit.md)
§ Finding 2 for the v1.0 baseline). DCE binary 350 488 → **351 200 B
(+712)** — well under the 512 KB cap raised at v0.7.1.

**0.7.1** — cut 2026-05-22 (eighth release; fourth same-day cut).
**Sandhi closeout** for the M6 → darshana 0.5.3 loop. Pin bumped 0.5.2 → 0.5.3; three inline stand-ins
(`_isatty_compat`, `_fg_256_buf_compat`, `_sgr_buf_compat`)
deleted from `src/color.cyr`; call sites rewritten to call
darshana's `tty_isatty` / `tty_sgr_buf` / `tty_fg_256_buf`.
Signature-identical swap — all 6 goldens still byte-identical,
241/241 tests pass, ASCII no-LF perf actually improves ~1 ns/byte
(46.99 → 45.99). Binary 349 832 → **350 488 bytes (+656)** — the
swap pulled in `tty_itoa` and other transitive darshana helpers
the M6 stand-ins had bypassed. **DCE cap raised 350 KB → 512 KB**
in this same slot (the M5-set 350 KB number was a stretch by M6
and broke by 488 B after the swap; the M7-closeout cap-raise note
in this file gets landed here instead of drifting).

**0.7.0** — cut 2026-05-22 (seventh release; third same-day cut).
**M6 closed.** Color-mode negotiation:
TRUECOLOR / 256-color / 16-color / MONO selected at startup from a
priority chain — `--color <mode>` override → `--no-color` →
`NO_COLOR` env → stdout-not-TTY (unless `--force-color`) → COLORTERM
→ TERM. M6 acceptance held: `NO_COLOR=1 echo X | anuenue` is byte-
identical to `echo X`. New module `src/color.cyr` (~200 lines)
with mode detection, RGB quantization (xterm 256-cube + bright-16),
and the MONO passthrough. Truecolor perf is unchanged (the M5
phase-cache shape stays the same; only per-entry bytes vary). 69
new tcyr assertions (172 → 241); two new golden fixtures
(`agnos-rainbow-256-s100.out` 160 B, `agnos-rainbow-16-s100.out`
82 B); three NO_COLOR equivalence checks in golden-check.sh.

**0.6.0** — cut 2026-05-22 (sixth release; second same-day cut
after 0.5.0). **M5 closed.** Performance pass: three layered
optimisations recover the M3 ASCII regression and overshoot the
v0.3.0 floor. ASCII short-circuit + binary-searched
`cp_is_extending` LUT + 1 530-entry phase-cached escape buffer.
End-to-end ASCII no-LF overhead 91.6 → **47.0 ns/byte (−48.7%)**;
UTF-8 mixed 66.3 → 43.0 (−35.1%). DCE binary +1 040 B (the 48 KB
phase table lives on the heap, doesn't bloat the binary). All
four M3 goldens still byte-identical; 26 new tcyr assertions
(146 → 172) lock the cache's per-entry bytes against the runtime
path. New `scripts/perf-bench.sh` is the M5 ratchet — every minor
cut from here forward re-runs it.

**0.5.0** — cut 2026-05-22 (fifth release, first after the four
same-day cuts that landed 0.1.0–0.4.0). **M4 closed.** Animation
mode: `-a` / `-d <secs>` / `-S <speed>`. Buffers stdin once (64 KB
ceiling), pre-tags grapheme clusters with the M3 state machine,
repaints at ~60 fps with phase shifted per frame.
`darshana::tty_cursor_up(n)` (sandhi-bumped 0.5.1 → 0.5.2) re-
anchors the rendered block. Non-blocking signalfd (HUP/INT/TERM)
probed between frames cleans up the cursor on Ctrl-C. Non-animation
invocations byte-identical to v0.4.0 — all four M3 goldens green,
v0.3.0 `-s 100` baseline still green. 42 new tcyr assertions (104
→ 146). New `scripts/animate-smoke.sh` asserts the structural
contract animation can't lock down with a byte-identical golden.

**0.4.0** — cut 2026-05-21 (fourth same-day release). **M3 closed.**
UTF-8 grapheme awareness: filter cycles by cluster, not byte.
Combining marks / ZWJ-extending / regional-indicator pairs all
fold into single clusters. ASCII path stays byte-identical (v0.3.0
`-s 100` golden remains green). Three new corpus goldens (CJK,
combining diacritic, ZWJ + RI flag); 30 new tcyr assertions (74 →
104 total). Invalid UTF-8 → graceful per-byte degradation. Chunk-
boundary carry handles 4 096-byte read splits. vyakarana evaluated
and rejected (wrong domain — source-code tokenizer, not Unicode
database); inline practical-subset classifier ships instead.

**0.3.0** — cut 2026-05-21 (open + close compressed, third same-day
release with 0.1.0 / 0.2.0). **M2 closed.** Five-flag CLI
(`-h`/`-V`/`-p`/`-s`/`-F`) sits between argv and the M1 filter loop;
loop itself byte-identical to 0.2.0. Determinism is now a
CI-asserted property; version literal is auto-generated; capability
surface picked up open/close at startup for /proc/self/cmdline.

**0.2.0** — cut 2026-05-21. **M1 closed.** Pipe-purity proof
shipped: stdin → stdout per-byte 24-bit rainbow via darshana 0.5.1's
new `tty_fg_rgb_buf` + `tty_sgr_reset_buf` helpers. Drove the
darshana truecolor unlock as the sandhi consumer; both repos cut
same-day.

**0.1.0** — scaffolded 2026-05-21 via `cyrius init anuenue`. Empty
filter — pure scaffold release.

## Phase

**v1.0.0 GA — tagged 2026-05-22.** API contract frozen for the
v1.x line. Maintenance + organic-adoption phase opens: patch cuts
fix what consumers find; minor cuts add non-breaking surface;
v2.0 is reserved for breaking changes. Sandhi-bump cadence
continues — darshana / sakshi / agnostik bumps follow the
proposal → swap → goldens-unchanged pattern established
through v0.7.1's three turns of the darshana 0.5.x crank.

The two open v1.0 acceptance items (Dogfooded + Downstream gate)
are anticipated to close as `agnoshi` MOTD chain and `iam` login
splash land their first integrations. Neither blocks the GA tag;
both are organic-adoption work the v1.0 contract makes tractable.

**Quality slot (v0.9.0) — shipped.** Fuzz harness, animation
smoke breadth, structural cleanup. See the v0.9.0 entry under
Version above for the per-thread breakdown.

**M7 (docs) + M8 (audit) — shipped at v0.8.0.** Doc half of the
v1.0 surface lock + the pre-v1.0 security pass, landed in one
cycle. ADRs 0001/0002/0003 record the rule that shapes everything
(pipe-purity), the not-pulling-abaco decision, and the practical-
subset grapheme classifier. `docs/guides/integrating-anuenue.md`
is the downstream-consumer manual; `docs/examples/` exercises every
flag at least once. The M8 audit
([`docs/audit/2026-05-22-audit.md`](../audit/2026-05-22-audit.md))
caught one HIGH-severity heap overflow in
`src/animate.cyr`'s `_render_frame` — adversarial long-cluster
input could overrun the 32 KB `line_buf` via the unbounded-cluster
byte copy. Fixed in-cycle with a mid-cluster flush guard; filter
path was unaffected. Zero HIGH+ findings open at the close of the
audit. Animation regression now covered at both unit-test
(`tests/anuenue.tcyr` M8 group) and integration (`scripts/animate-
smoke.sh` long-cluster section) levels.

**Sandhi closeout (v0.7.1) — shipped.** darshana 0.5.3 landed
(the third turn of the same crank that produced darshana 0.5.1
truecolor for M1 and 0.5.2 cursor-up for M4); anuenue's pin bumped
0.5.2 → 0.5.3 and the three M6-era stand-ins removed. Sandhi loop
closed. M6's behavioural surface is now backed by canonical
darshana helpers per the project rule (CLAUDE.md: *ANSI escape
generation belongs in darshana*).

**M6 (Color-Mode Negotiation) — shipped at v0.7.0.** Four-mode
taxonomy (MONO / COLOR_16 / COLOR_256 / TRUECOLOR) selected by a
priority chain at startup. New `src/color.cyr` owns the mode
enum, override-string parser, RGB → 256-cube quantization, RGB →
bright-16 quantization, `anuenue_detect_color_mode`, and
`anuenue_passthrough` (the MONO bypass). Three new flags wire
into main.cyr: `--no-color`, `--force-color`, `--color <mode>`.
M5's phase-cache becomes mode-aware — the 1 530-entry table holds
per-mode escape bytes; the hot-path emit (`_emit_phase_esc`) is
unchanged because its memcpy is byte-shape-agnostic.

**M5 (Performance Pass) — shipped at v0.6.0.** Three layered
optimisations recover the M3 cluster-classification regression
and beat the v0.3.0 floor on the canonical ASCII no-LF corpus.

1. **ASCII short-circuit** in `anuenue_filter` and
   `_pretag_clusters` — `b < 0x80` skips `utf8_seq_len` +
   `utf8_decode` + `cp_is_extending` + `cp_is_regional_indicator`,
   honouring the `prev_was_zwj` latch for the ZWJ-then-ASCII
   edge case the M3 semantics preserve.
2. **Binary-searched `cp_is_extending` LUT** — sorted `[lo, hi]`
   pair table + log₂(21) ≈ 5 comparisons + cheap reject for
   `cp < 0x0300` and `cp > 0xE01EF`. Replaces the v0.4.0
   21-condition linear chain. Perf-neutral on ASCII (already
   short-circuited); helps UTF-8-heavy non-Latin corpora.
3. **Phase-cached escape buffer** — 1 530-entry table indexed by
   `phase % ANUENUE_PHASE_MOD` holding pre-formatted
   `\x1b[38;2;R;G;Bm` escapes. Replaces `hsv_rainbow +
   tty_fg_rgb_buf` per cluster with a single length-prefixed
   memcpy. 32-byte stride per entry; heap-allocated at first
   filter/animate entry; doesn't bloat the DCE binary.

Animation mode benefits equally: `_render_frame` routes through
the same `_emit_phase_esc` shared with the filter loop.

`scripts/perf-bench.sh` (new) scriptizes the end-to-end ASCII
per-byte measurement docs/benchmarks.md kept describing manually.
It's the M5 ratchet — every minor cut from here forward re-runs
it.

Next slot is **v1.0.0 — GA tag** per
[roadmap.md § Shipped](roadmap.md#shipped). Surface frozen at
v0.8.0; capability baseline recorded by the M8 audit;
documentation set complete. The remaining v1.0 acceptance items
(*Dogfooded* + *Downstream gate*) need at least one external
consumer (likely `agnoshi` MOTD pipeline or `iam`) wiring anuenue
in for a minor-cycle soak window. Tagged on user signal per
[feedback_no_unprompted_version_bumps](https://github.com/MacCracken/agnosticos/blob/main/.claude/projects/-home-macro-Repos-agnosticos/memory/feedback_no_unprompted_version_bumps.md).

## Toolchain

- **Cyrius pin**: `6.5.35` (in `cyrius.cyml [package].cyrius`). History: `6.0.1` (scaffold → v1.0.0) → `6.0.56` (v1.1.0, agnos target) → `6.1.14` (v1.1.2) → `6.2.24` (v1.1.3) → `6.2.44` (v1.1.5) → `6.4.62` (v1.2.0) → `6.5.35` (v1.2.1). `./lib/` re-synced to the pin via `cyrius lib sync --full` at each bump.
- Pin-lag spectrum: aligned with darshana 1.0.0 / cmdit 1.2.4 / sakshi 2.4.11 / agnostik 1.5.1 as of v1.2.1. Re-evaluate at each minor cut; sandhi-bump if a dep ships an upgrade we want.
- **`path`-mode tags are only as good as the lock.** `[deps.X] tag` is honoured when `cyrius.lock` agrees; edit a tag without invalidating the lock and resolution silently keeps the locked commit. v1.2.0 shipped with three tags disagreeing with their vendored bytes for exactly this reason. When changing a tag, `rm cyrius.lock && cyrius deps` and re-check the bundle's `# Version:` header.
- **`CYRIUS_DCE=1` no longer changes output size.** 6.5.35 NOPs unreachable functions in place rather than eliminating them, so DCE and non-DCE binaries are byte-for-byte the same size. "DCE binary size" now measures the whole binary.

## Source

| File | Lines | Surface |
|------|-------|---------|
| `src/hsv.cyr` | ~95 | **NEW at v0.9.0** (the M0-anticipated split). Holds `ANUENUE_PHASE_MOD = 1530` + `hsv_rainbow(phase, out_rgb)` — the integer 6-sector S=V=1 HSV→RGB. Move was triggered by `fuzz/emit-phase-esc.fcyr` wanting a clean target boundary; ADR 0002 (HSV inline) documents the broader "don't pull abaco" decision. `main.cyr` / `filter.cyr` / `animate.cyr` / `tests/anuenue.tcyr` / `tests/anuenue.bcyr` all include this before `filter.cyr` since filter references `ANUENUE_PHASE_MOD`. |
| `src/color.cyr` | ~200 | **NEW at M6 (v0.7.0)**. Color mode enum (`ANUENUE_COLOR_MONO`/`_16`/`_256`/`_TRUE`); override-string parser + enum mapping (`_color_override_from_str` / `_color_mode_from_override`); RGB quantization (`_channel_to_6`, `_rgb_to_256` xterm cube; `_rgb_to_16` bright-palette); `anuenue_detect_color_mode(no_color, force_color, override)` reading getenv + darshana 0.5.3's `tty_isatty`; `anuenue_passthrough()` MONO bypass (read/write loop, no escapes). Sandhi closeout at v0.7.1 removed the three `_*_compat` stand-ins. **v1.2.1** adds the `AnuenueColorReason` enum + `ANUENUE_COLOR_REASON` + `anuenue_color_reason_name` / `anuenue_color_mode_name`: all ten exits of `anuenue_detect_color_mode` now record which branch fired, so `-v` can answer *why* a mode was chosen. `anuenue_passthrough`'s failure paths route through `anuenue_fail`. |
| `src/filter.cyr` | ~480 | `ANUENUE_*` constants + **`ANUENUE_ESC_TABLE_ENTRY_SIZE`** (M5). `hsv_rainbow` + `ANUENUE_PHASE_MOD` extracted at v0.9.0 — now live in `src/hsv.cyr`. M3: `utf8_seq_len` / `utf8_decode` / `cp_is_extending` (M5: binary-searched LUT) / `cp_is_regional_indicator`. M5: `_phase_esc_init()` / `_emit_phase_esc()` / `_PHASE_ESC_TABLE` (1 530 × 32 B heap; idempotent). **M6 (v0.7.0)**: `_phase_esc_init` branches on `ANUENUE_COLOR_MODE` to populate per-mode escapes (TRUECOLOR via `tty_fg_rgb_buf`, 256 via `tty_fg_256_buf`, 16 via `tty_sgr_buf`). `anuenue_filter()` keeps the M5 hot path; ASCII short-circuit unchanged. **Unaffected by the M8 audit fix** — writes one codepoint per iteration with the reserve check between, so the long-cluster overrun doesn't reach the filter path. |
| `src/animate.cyr` | ~290 | M4 surface (animation: slurp + pretag + frame loop + signalfd). M5: ASCII short-circuit in `_pretag_clusters`; `_render_frame` routes through `_emit_phase_esc`; `_phase_esc_init` shared with filter. M6: animation benefits from per-mode escapes via the same path; MONO never reaches animation (main.cyr dispatches to passthrough first). **M8 (v0.8.0) fix**: `_render_frame`'s cluster-bytes copy loop got an inline mid-cluster flush guard — when the reserve threshold trips before all cluster bytes are written, flush + re-emit the same `phase` escape so the next bytes render under the same colour. Closes the long-cluster heap overflow surfaced by the audit. |
| `src/main.cyr` | ~135 | Entrypoint + flag dispatch. args_init / alloc_init / flags context (M6 added `-n` / `-C` / `-c` to the M2/M4 sets) / argv pack / flags_parse / **M6 colour-mode detect step writes `ANUENUE_COLOR_MODE`**; dispatch to print_version / print_usage / **anuenue_passthrough (MONO) or anuenue_animate (-a) or anuenue_filter**. |
| `src/observe.cyr` | ~250 | **NEW at v1.2.1.** The sakshi/agnostik wiring. Holds the `AnuenueExit` exit-code enum + `_eprint` (both moved from `main.cyr`), the `AnuenueLogParse` level scale and `anuenue_log_parse` / `_name`, `anuenue_observe_init` (pins sakshi to fd 2, sets the level, sets `ANUENUE_VERBOSE`), gated span wrappers, `anuenue_log_kv_str` / `_int` / `anuenue_log_version`, and `anuenue_fail` (agnostik kind → stderr line + sakshi record → exit code). **Depends on nothing from anuenue** — only sakshi, agnostik and the stdlib — which is why it is included *first* and every other module can call `anuenue_fail` without a cycle. The colour-reason codes live in `color.cyr` for the mirror-image reason. |
| `src/version_str.cyr` | ~18 | **AUTO-GENERATED** by `scripts/version-bump.sh`. Holds `_VERSION_STR_ANUENUE` + `_VERSION_LEN_ANUENUE`. Never hand-edit; CI's Version consistency step asserts the literal matches `VERSION`. |
| `src/test.cyr` | 12 | top-level test entry stub (referenced by `cyrius.cyml [build].test`). Actual tests live in `tests/anuenue.tcyr`. |

The M0-anticipated `src/hsv.cyr` split landed at v0.9.0 (the fuzz
harness's `emit-phase-esc` target was the second consumer that
finally earned it). Source-file layout is now stable at v1.0;
post-1.0 splits would need new domain pulls (e.g. a sibling
pipe-decorator extracting shared code into the AGNOS shared-crates
registry, post-v1.x).

## Binary

- **Size (1.3.5)**: **814 488 bytes** (~795 KB) — unchanged from v1.3.4.
  Tracked every release; **not capped** — see the policy note.
- **Size policy (v1.2.2+): track, do not cap. The 512 KB cap is
  removed.**

  The cap was set at v0.7.1 (raised 350 KB → 512 KB) when anuenue's
  binary was ~350 KB and essentially all of it was anuenue. That is no
  longer what the number measures. Three things changed underneath it:

  1. **The first-party dep surface is the floor now, not anuenue.**
     agnostik alone is ~546 KB of the binary. anuenue's own source is
     ~2 400 lines. Capping the total means capping darshana, sakshi,
     agnostik and cmdit's right to grow — which is backwards: those
     crates growing is the ecosystem working, and a downstream pipe
     filter is the wrong place to veto it.
  2. **`CYRIUS_DCE=1` stopped removing anything.** From 6.5.x it NOPs
     unreachable functions in place, so the DCE and non-DCE binaries
     are byte-identical in size. "DCE binary size" no longer measures
     dead-code elimination at all; it measures the whole link.
  3. **The cap was never a real gate.** No CI step enforced it. It
     lived only in this file, so its only actual effect was to make
     every dep bump read as a regression in the release notes.

  What replaces it: **record the size every release, and explain any
  step change.** A jump is a fact to attribute (toolchain? dep? our
  code?), not a threshold to fail. The decomposition tables below are
  the format — they are what made the v1.2.1 jump legible, and no cap
  was needed to produce them. If anuenue's *own* contribution ever
  grows sharply, that is the signal worth acting on, and it is visible
  in the per-step deltas without a global ceiling.
- **Size history**: 1.3.5 = 814 488 B, 1.3.4 = 814 488 B, 1.3.3 = 814 480 B, 1.3.2 = 814 448 B, 1.3.1 = 814 448 B, 1.3.0 = 814 448 B, 1.2.2 = 809 984 B, 1.2.1 = 809 520 B, 1.2.0 = 389 648 B, 1.1.3 = 394 440 B, 1.0.0 = 351 200 B, 0.9.0 = 351 200 B, 0.8.0 = 351 200 B, 0.7.1 = 350 488 B, 0.7.0 = 349 832 B, 0.6.0 = 335 160 B, 0.5.0 = 334 120 B, 0.4.0 = 322 368 B, 0.3.0 = 317 216 B, 0.2.0 = 304 368 B. Figures up to 1.0.0 measured genuine DCE elimination; 1.2.0 onward measure the whole binary (see point 2 above) and are not directly comparable to the earlier rows.
- **Output path**: `build/anuenue`

## Tests

| File | Status |
|------|--------|
| `tests/anuenue.tcyr` | **349 assertions across 46 groups** (v1.2.2: +41 across 4 groups, one per audit finding with a testable invariant — A-01 table init, A-02 clamp arithmetic incl. a pin that `i64::MAX * 1e9` really wraps, A-04 colour-value parsing incl. the BAD sentinel, A-05 cap behaviour incl. that the sentinel is the stop offset). v1.2.1 was **308 assertions across 42 groups** (v1.2.1: +66 across 7 new groups covering the sakshi/agnostik wiring — log-level parsing incl. case-sensitivity / empty string / null pointer, the parse-to-`SK_*` scale mapping, verbosity resolution, colour-reason recording, name-function totality, and the agnostik-kind → exit-code mapping). M1: smoke/HSV/geometry/constants (47). M2: flags (24 — was 27; the v1.1.4 `flags_*` → `cmdit_*` migration collapsed three separate parse-then-get checks into single return-code assertions, e.g. `flags_parse`+`flags_get_bool(f_help)` → one `cmdit_parse_argv(...) == CMDIT_HELP`). M3: utf8_seq_len/decode/cp_is_extending/cp_is_regional_indicator (30). M4: animate constants + _pretag_clusters + _count_lf_clusters + _input_ends_with_lf + -a/-d/-S flag parsing (42). M5: phase-cache idempotency, byte-identical round-trip, phase normalization, table layout (26). M6: mode enum + override parser + `_channel_to_6` bucket boundaries + `_rgb_to_256` canonical hues + `_rgb_to_16` bright-palette quantization + 256/16 escape framing + bounds rejection (69). **M8 (v0.8.0): "_pretag_clusters long-combiner chain" (4)** — A + 511 combiners → 1 cluster spanning 1023 bytes; locks the unbounded-cluster invariant the M8 audit fix relies on. End-to-end behaviour owned by golden + animate-smoke (+ M8 long-cluster section) + perf-bench. |
| `tests/anuenue.bcyr` | 2 micro-benchmarks. At v1.2.1: `hsv_rainbow` **8 ns/call**, `tty_fg_rgb_buf` **52 ns/call** — **not comparable to pre-v1.2.1 figures**: 6.5.35's `bench` harness measures and subtracts a timer floor (1.347 µs per clock read on the reference host) that the 6.4.62 harness did not. Pre-M5 the filter loop called both per cluster; M5+ uses `_emit_phase_esc` (~10 ns/call) instead. The micros still measure the table-build path. |
| `fuzz/*.fcyr` (v0.9.0+) | **Five harnesses populated.** `flag-parser.fcyr` (M2), `utf8.fcyr` (M3), `pretag-clusters.fcyr` (M4), `emit-phase-esc.fcyr` (M5), `rgb-quantizers.fcyr` (M6). Each uses a Knuth-MMIX LCG for deterministic seed-driven exploration; each returns `assert_summary()` so failed invariants set a non-zero exit code. Combined: **1 354 581 assertions** as re-measured at v1.2.1 (`emit-phase-esc` 1 013 957, `utf8` 180 088, `pretag-clusters` 100 392, `rgb-quantizers` 60 000, `flag-parser` 144), zero failures. `cyrius fuzz` is the gate; runs in CI. Previous `tests/anuenue.fcyr` stub deleted (wrong path; `cyrius fuzz` looks at `fuzz/*.fcyr`). |
| `tests/golden/*.out` | **Six fixtures**. M2/M3: `agnos-rainbow-s100` (238 B), `cjk-mixed-s0` (125 B), `combining-s0` (155 B), `zwj-flag-s0` (135 B). **M6: `agnos-rainbow-256-s100.out` (160 B), `agnos-rainbow-16-s100.out` (82 B)**. All six byte-identical across the M5/M6/M8 cuts — proves the mode-aware phase cache matches runtime exactly and that the M8 fix is local to the long-cluster path. Plus three MONO equivalence checks in golden-check.sh (`NO_COLOR=1 anuenue` / `--no-color` / `--color=none` all byte-identical to input). |
| `scripts/animate-smoke.sh` | M4 (v0.5.0). Animation structural guard. M6: invokes with `--color=24bit` so the TTY-detection in M6 doesn't drop the test into MONO. **M8 (v0.8.0) extension**: long-cluster section runs the historical attack (base + 16 000 combining acutes), asserts clean exit and full byte preservation (~976 000 combiner bytes over 61 frames) through the mid-cluster flushes. **v0.9.0 extensions**: `--color=256` + `--color=16` per-mode sections — each asserts clean exit, non-empty output, full cursor lifecycle, and the per-mode SGR shape (CSI 38;5;Nm for 256, CSI 9[1-7]m for 16; explicit no-leak check that truecolor 38;2;… doesn't appear under `--color=256`). |
| `scripts/robustness-check.sh` | **NEW at v1.2.2** (P-1 audit). Adversarial byte streams and adversarial argv against the real binary — the surfaces the unit suite and the seeded fuzz harnesses do not reach, and where four of the nine audit findings lived. Eleven checks: UTF-8 carry across the 4096-byte read boundary (52 comparisons, chunked vs `dd bs=1` — the property `carry_len` exists for, previously untested end to end); byte preservation under malformed UTF-8 (116 comparisons across overlong 2/3/4-byte forms, UTF-16 surrogates, >U+10FFFF, the 0xF5–0xFF range, lone continuations, EOF truncation, embedded NULs, all 256 byte values); every integer flag at both i64 extremes terminating with a documented exit code; and one process-level regression per finding. Runs in CI. |
| `scripts/observe-check.sh` | **NEW at v1.2.1.** The observability gate, and the enforcement point for pipe-purity under diagnostics. Four gates: (1) stdout byte-identical across 144 corpus × colour-mode × verbosity combinations — the property a unit test cannot express, and the one that matters because a byte leaked onto fd 1 corrupts every pipeline `-v` is enabled in; (2) stderr empty in every default-verbosity run, including for wholly invalid UTF-8; (3) `-v` carries the fields a bug report needs (version, phase step, colour mode, colour **reason**, route, byte count) and never reports `reason=unset`; (4) the forced read failure (stdin closed → EBADF) prints the agnostik kind, logs `code=1010`, and still exits 1. Runs in CI. |
| `scripts/perf-bench.sh` | M5 (v0.6.0). End-to-end ASCII + UTF-8 per-byte overhead. M6: invokes with `--color=24bit` for the same reason. The M5 ratchet. Latest run at v1.2.1 (`RUNS=11`, idle host, final binary): ASCII no-LF **46.63 ns/byte**, ASCII w/ LFs **50.99**, UTF-8 mixed **41.77** — all under the 60 ns/byte cap. Measured head-to-head against a rebuilt v1.2.0 binary rather than against a historical figure. |

Assertion count history: M1 47 → M2 74 (+27) → M3 104 (+30) → M4 146 (+42) → M5 172 (+26) → M6 241 (+69) → M8 245 (+4) → v1.1.4 **242** (−3, cmdit migration) → v1.2.1 **308** (+66, observability wiring) → v1.2.2 **349** (+41, P-1 audit regressions).

## Dependencies

Direct (declared in `cyrius.cyml`):

| Dep | Tag | Role | Status |
|-----|-----|------|--------|
| `darshana` | **1.0.0** | ANSI color escape generation. Pin history: 0.5.1 (M1 truecolor `tty_fg_rgb_buf` / `tty_sgr_reset_buf`); 0.5.2 (M4 `tty_cursor_up(n)` / `tty_cursor_down(n)`); 0.5.3 (M6 sandhi closeout — `tty_isatty(fd)` / `tty_sgr_buf` / `tty_fg_256_buf`); 0.7.1 (v1.1.3 refresh); 0.9.0 (v1.1.x); **1.0.0 (v1.2.1 — the API freeze)**. | Live. **Nine symbols called**, all inside the frozen 29-fn surface: filter path `tty_fg_rgb_buf` / `tty_fg_256_buf` / `tty_sgr_buf` / `tty_sgr_reset_buf`, colour detect `tty_isatty`, animation `tty_cursor_up` / `_hide` / `_show` / `tty_sgr_reset`. Both 0.9.3 breaks are non-events: `AGNOS_*` → `_AGNOS_*` touches symbols anuenue never named, and `tty_sgr_reset_buf`'s new `-1`-on-negative-`pos` is unreachable — every `pos` at all 15 call sites (11 filter, 4 animate) is a non-negative accumulator. `tty_open_signalfd`'s `-errno` → `-1` is moot: `src/animate.cyr` rolls its own *non-blocking* signalfd. |
| `sakshi` | **2.4.11** | Errors / tracing / structured logging | **Wired at v1.2.1** (`src/observe.cyr`) — was a declared dep with zero call sites from M0 through v1.2.0. Uses `sakshi_set_output_fd` (pinned to fd 2), `sakshi_set_level` / `_get_level`, `sakshi_log_kv`, `sakshi_span_enter` / `_exit`, and the `SK_*` level enum. **Never** `sakshi_output_file` / `_udp` — those would breach the capability bound. Note `span_enter`/`_exit` are NOT level-gated inside sakshi, so anuenue routes them through gated wrappers. |
| `agnostik` | **1.5.1** | Shared Result / Error shapes | **Wired at v1.2.1** (`src/observe.cyr`) — same story. Uses `agnostik_err_new` / `_code` / `_print` and the `STIK_ERR_*` kind enum for the three real failure paths (stdin read, buffer alloc, escape-table alloc). Kind → exit code: `STIK_ERR_INVALID_ARGUMENT` → 2, everything else → 1. **Trap:** `agnostik_err_new(kind, message: Str)` needs a real `Str`; cyrius 6.5.35 does not coerce a literal in return-expression position, so `anuenue_fail` converts explicitly with `str_new`. |
| `cmdit` | **1.2.4** | CLI / argument parsing (getopt-long; the stdlib `flags` parser productized + extended). Local sibling `../cmdit`. | **Adopted at v1.1.4** (the `flags` → cmdit migration; anuenue is cmdit's 2nd worked example after kii). `print_usage` uses `cmdit_help_flags` (the table-only renderer) to keep anuenue's custom help framing. **1.2.4 is the P-1 audit cut** — anuenue is exposed to none of its four findings (literal prog name to `cmdit_new`; never calls `cmdit_completions`), confirmed by a byte-identical CLI-surface diff. |
| Cyrius stdlib | n/a | string, fmt, alloc, io, vec, str, syscalls, assert, bench, args, **chrono (M4)** | Auto-resolved via `cyrius deps`. `args` added at M2; `flags` (added M2) **DROPPED at v1.1.4** when CLI parsing moved to `[deps.cmdit]`; `chrono` added at M4 for frame timing (`sleep_ms`) and deadline math (`clock_now_ns`). |

No pre-release / pre-1.0 deps on the critical path. No external (non-AGNOS) deps.

## Verification Hosts

| Host | Role | Status |
|------|------|--------|
| `archaemenid` (Beelink SER, AMD Zen) | Primary dev box; will be the iron-soak target once AGNOS userland boots there | Not yet (anuenue runs on host Linux for now) |
| Host Linux (CI runner pattern) | Build + test gate via `.github/workflows/ci.yml` | Active from M0 |

## Consumers

_None yet._

Anticipated at v0.7+:
- `agnoshi` — MOTD pipeline composition
- `iam` — default login splash chain (`iam | anuenue`)
- end-user shells — bash / zsh / agnoshi interactive use

## Carry-Forward

**Sequencing moved to [`roadmap.md`](roadmap.md) at v1.2.2.** That file now
holds every open item, arranged into the v1.3.0 slot, the v1.x arc, and what
is explicitly declined — and every entry there traces to a specific deferral in
the code, an ADR, or an audit report. This section keeps only what is *state*
rather than plan: the cadences that run every cut, and one lesson worth not
re-learning.

- **Cadences.** Audit at every minor cut (delta vs the previous report),
  sandhi bumps on the proposal → swap → goldens-unchanged pattern, perf ratchet
  head-to-head against a rebuilt prior binary, and binary size tracked rather
  than capped. Details in
  [roadmap.md § Ongoing cadence](roadmap.md#ongoing-cadence--not-milestones).
  Latest audit: [`docs/audit/2026-08-25-audit.md`](../audit/2026-08-25-audit.md)
  (v1.2.2 P-1 sweep — 9 findings, all fixed in-cut, zero HIGH+ open).
  Baseline: [`docs/audit/2026-05-22-audit.md`](../audit/2026-05-22-audit.md).

- **An accepted INFO finding is a hypothesis about behaviour, not a measurement
  of it.** The 2026-05-22 audit recorded "large `-d` graceful-exit boundary at
  ~292 years" as an accepted INFO, and this file carried that description
  forward for three minors. Re-measuring at v1.2.2 showed the behaviour was the
  **inverse**: `duration_secs * 1000000000` overflows i64 above ~9.22e9 seconds,
  and at `i64::MAX` the product is congruent to exactly −1e9 — so the deadline
  landed one second in the *past* and the animation exited after a **single
  frame**. Not a graceful boundary; an immediate exit. Fixed as A-02.

  Nobody introduced a regression. The original characterisation was simply never
  measured, and three audits' worth of documentation repeated it. The two
  remaining INFO items from that report (signalfd lifecycle on animation exit,
  signal mask not restored after completion) are **also unmeasured**, which is
  why they are scheduled work in
  [roadmap.md § v1.3.0](roadmap.md#v130--animation-slot) rather than a footnote
  here.

## Next

**v1.3.0 — the animation slot.** Everything currently actionable clusters on
one surface: animation is the least exercised path in the tree — the only code
that touches signals, the only code with input caps, and the only code no test
drives through a real terminal. The slot carries the `-i` / `--interval` flag,
a PTY-backed animation test, re-measurement of the two unverified INFO findings
above, a fuzz harness over the two parsers that now reject rather than fall
back, and the first entries in the empty `docs/architecture/`.

See [roadmap.md § v1.3.0](roadmap.md#v130--animation-slot) for the items and
their gates, and [§ v1.x](roadmap.md#v1x--later-minors) for what waits behind
them — including the two v1.0 acceptance items that block on external consumer
wiring rather than on anything anuenue can write.
