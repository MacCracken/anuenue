# anuenue — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures
> (durable); this file is **state** (volatile).

## Version

**1.5.2** — cut 2026-10-29. **The routes agree on the phase of an extender**
(the v1.5.0 delta's V-11). The filter and the one-shot route give an extender
after an LF its own cluster and a phase step, as animation has since H-05
(v1.4.4): UAX #29 GB4, nothing extends an LF. It holds across an input SGR, a
span or an empty span between them, and across the read boundary. `saw_any`
gains a third value (2: the last cluster was an LF), so the ASCII hot path
stores nothing new. At the end of the input the byte after a ZWJ joins its
cluster on every route. The filter's EOF carry stepped there (V-11's recorded
case), and so did the one-shot route's truncated UTF-8 tail (a third case the
reproduction found). The row count gives a cluster that starts with an
extender the width of its first non-extender (`_cluster_cols_past_ext`), not
1. stdout byte-identical to v1.5.1 for every other input (301 comparisons).
**608/608** unit in 75 groups, fuzz **1 790 016**, robustness **83** (gate 12,
new), PTY **35**, eight mutations each caught, `cyrius audit` clean, perf flat
(15.42 vs 15.48 ns/byte truecolor ascii no-LF, head to head). Binary
532 448 → **536 544 B** (`.text` +872 B crossed a page). Roadmap: v1.6.0 is
next, on its trigger.

**1.5.1** — cut 2026-10-29. **cyrius 6.7.18 + dependency refresh.** Toolchain
6.7.9 → 6.7.18; cmdit 1.4.0 → 1.5.0, darshana 1.3.0 → 1.6.0, agnostik 1.12.0 →
2.0.0 (one rename reaches anuenue: `agnostik_err_code` → `AgnostikError_code`),
sakshi 2.5.8 → 2.5.10 through the snapshot. stdout byte-identical to v1.5.0
(301 comparisons, 18 animation streams); perf flat in all four modes (15.16
ns/byte truecolor ascii no-LF, was 15.25). One behaviour change: a command line
over 2 MiB parses whole (6.7.12's `args_init` + cmdit 1.4.2), and robustness
gate 7 now asserts it. cyrlint's overrun rule found three byte-sized `argv`
arrays in the unit suite holding more pointers than bytes. They were the real
cause of the v1.4.3 crash filed as a cyrius miscompile, which cyrius 6.7.14
closed as not its bug. Fixed. Binary 248 288 → **532 448 B**, +307 252 B of it
bayan's Unicode tables, which agnostik's sidecar pulls in and DCE keeps though no
live code reads them (filed upstream). **595/595** unit, fuzz **1 780 057**,
robustness **80**, every route's syscall set unchanged, `cyrius audit` clean.
Roadmap: v1.5.2 (V-11) is next; swapping the SGR stand-in for darshana 1.4.0's
scanner rides along with v1.6.0.

**1.5.0** — cut 2026-10-15. **No-colour spans** ([ADR 0006](../adr/0006-no-colour-spans.md)):
a producer brackets text with `ESC _ anuenue:off ESC \` … `ESC _ anuenue:on
ESC \`, and anuenue passes it through as written — its own colour codes
included — with one reset at each marker, the rainbow paused across it, and
lenient matching (an `off` runs to the end, which closes it with a reset).
Markers are consumed on every route, MONO included, and carried across the
4096-byte read (≤ 14 bytes). Animation draws a span raw in every frame, and
its row count parses the span's intact escapes as a VT500 parser does
(`_span_vt`). MONO now scans for ESC, four words per step: 0.25 → 0.55
ns/byte (a byte loop measured 2.04). Colour routes: ASCII flat (15.16 vs
15.12 truecolor no-LF); UTF-8 mixed +1.4–2.4%, none of it span code — two
frame-layout variants recovered under half, so kept as shipped.

Audit delta [`2026-10-15-v150-delta.md`](../audit/2026-10-15-v150-delta.md):
12 findings in the release's own new code, 1 HIGH + 2 MEDIUM + 5 LOW + 4 INFO,
ten fixed before release, two recorded (V-11 → roadmap v1.5.2, V-12
trigger-gated). The HIGH, V-06: empty spans wrote resets with no reserve check,
and 4 200 of them crashed the one-shot route — found by the cut's independent
review. stdout byte-identical to v1.4.5 for every input without a marker (209
+ 18 comparisons). **595/595** unit assertions in 73 groups (was 506 / 60),
fuzz **8 harnesses, 1 780 057** (the new `no-colour-markers`, 258 175), robustness **80**
(was 60; gate 11), PTY **33** (was 25), `cyrius audit` clean. Binary 235 848 →
**248 288 B**. Roadmap: the cyrius slot is v1.5.1, V-11 is v1.5.2, adoption is
in v1.6.0.

**1.4.5** — cut 2026-10-15. **Input colour codes stripped** — the v1.4.4
audit's H-06, decided 2026-10-14. On the colour routes (filter, one-shot,
animation) the input's own SGR codes (`ESC [ <0x30–0x3B> m`, ≤ 128 bytes)
are removed, so `ls --color=always | anuenue` no longer prints `[01;34m` as
text. MONO keeps them byte for byte; every other sequence passes as before.
The filter drops them inline in its byte loop, carrying a sequence a read
cuts off (≤ 127 bytes) like a split UTF-8 sequence; one-shot and animation
strip their buffer with `anuenue_sgr_strip`. A first, separate-pass design
measured +1.7 ns/byte and was replaced; the shipped one is flat (15.43 vs
15.30 ns/byte truecolor ascii no-LF, ten interleaved rounds, ±0.8%).

stdout byte-identical to v1.4.4 for every input without a colour code (232 +
18 comparisons). **506/506** unit assertions in 60 groups (was 484 / 59),
fuzz **7 harnesses, 1 521 882** (the new `sgr-strip`: a reference stripper
and chunked-equals-whole), robustness **60** (was 46; gate 10), `cyrius
audit` clean. Binary 235 800 → **235 848 B**. Roadmap: cyrius moved to
v1.4.6; v1.5.0 is the APC "no colour" marker. darshana asked for an
input-side SGR scanner (proposal filed).

**1.4.4** — cut 2026-10-14. **The v1.4.x closeout + P(-1) sweep.** Audit
delta [`2026-10-14-v14x-delta.md`](../audit/2026-10-14-v14x-delta.md): 6
findings, 1 MEDIUM + 2 LOW + 3 INFO, zero HIGH+ — five fixed in-cut, H-06
recorded (a stdout behaviour choice) — and **every guard ever recorded as
unproven is now proven by a gate**.

*H-01 (MEDIUM)*: animation re-anchored by LF count, so a line wider than
the terminal, or a block taller than it, scrolled a copy of the block into
scrollback every frame (+8.7 rows / frame for five 162-column lines at
80 columns, measured with a new terminal model, `scripts/term-model.py`).
Now physical rows on a terminal of known size, with a display-width table
generated from UAX #11 (ADR 0005), and a block that cannot fit is drawn
once; pipes unchanged. The fix's first cut had two errors (a hand-picked
width table, input escapes modelled as zero-width) — caught by the
closeout's code review. *H-02 (LOW)*: waiting on a non-blocking stdin /
stdout was a 1 ms poll loop (30 ms CPU per 4 s); now `poll(2)`, 0 ms.
*H-05 (LOW, since M4)*: animation dropped a combining mark after an LF or at
the start of the input. *H-03 (INFO)*: the documented syscall surface named
`brk`; measured, no route issues it, and the measurement is now a gate.
*H-04 (INFO)*: architecture 001's worst case was mis-added (29); the real
bound is 32 — exactly the reserve. *H-06 (INFO, recorded)*: escape
sequences in the input print as text — anuenue's own escape cancels each
input ESC; a roadmap item.

*Proven*: D-01 (zero tick) by a probe; E-01's zero-byte write, EINTR on
both sides and the signalfd `fcntl` fallback by gdb syscall injection
(`scripts/fault-check.sh`, new, CI-wired, which also gates the syscall
surface per route); NOMEM under a genuinely exhausted heap. *Closeout*: the
unit suite's `main()` is sixteen per-cut functions (the v1.4.3 miscompile's
workaround); the dead-code floor is one test oracle; thoth (a library
consumer, now listed) is unaffected. *Upstream*: agnostik's unchecked
`alloc(24)` in `agnostik_err_new`, filed.

stdout byte-identical to v1.4.3 on every pipe route (232 + 18
comparisons); perf flat (15.60 ns/byte truecolor ascii no-LF, +0.1%).
**484/484** unit assertions in 59 groups (was 437 / 56), robustness **46**
(was 38), PTY **25** (was 14), allocfail **23** (was 17), fault-check **17**
(new), fuzz **1 491 882** (was 1 483 587), `cyrius audit` clean. Binary
226 624 → **235 800 B**.

**1.4.3** — cut 2026-10-14. **The escape-table word copy.**
`_emit_phase_esc` copies an entry as three 8-byte words, not `elen` bytes:
9 ns per escape in every mode (was 39 / 27–28 / 16–17), and end to end the
filter is **51–68% faster** — truecolor ascii no-LF 47.72 → **15.40
ns/byte**, with all three modes now about equal. stdout byte-identical to
v1.4.2 (232 filter / one-shot comparisons + 12 animation streams).

*The footprint changed*: 24 bytes written, `elen` advanced. Safe because
every one of the eight call sites enters with the 32-byte reserve free (or
straight after a flush), flushes write only `[0, pos)`, and the read is the
entry's own payload — the argument is architecture 001 § The escape write
footprint, now made explicitly. `_phase_esc_init` zero-fills each payload
so the scratch is deterministic across a mode rebuild. The fuzz invariant
"writes exactly elen bytes" is restated (footprint + a stream check against
a byte-copy reference); robustness gate 9 asserts no NUL reaches stdout.
Four mutations, each caught.

*Decided*: no fixed corpus in `tests/anuenue.bcyr` — perf-bench.sh beside
the micro rows gave this cut both numbers, and an in-process corpus would
need a stdout seam in the hot path. *Found*: a cyrius miscompile — growing
the unit suite's `main()` crashed it in an unrelated early group (6.7.9 –
6.7.11); the new group lives in its own function, the bug is filed as a
cyrius issue (reproduction pinned to anuenue 1.4.2), and v1.4.4's refactor
splits `main()`.

**437/437** unit assertions (was 429), robustness **38** (was 37), fuzz
**1 483 587** (was 1 450 668), `cyrius audit` clean. Binary unchanged at
**226 624 B**.

**1.4.2** — cut 2026-10-14. **stderr hygiene** — the roadmap slot, both
items measured at v1.4.1; stdout and exit codes unchanged (138 comparisons
plus eleven help / error invocations against v1.4.1).

*One failure, one line.* `anuenue_fail` wrote a second newline after
`agnostik_err_print`, which already ends its line, so every failure since
v1.2.1 printed a blank line after its message. Gone; observe-check gate 5
pins it (all five cases fail on v1.4.1).

*Parse errors name their token* (`anuenue: unknown flag: --bogus`), from
cmdit's `cmdit_err_token` / `cmdit_err_value`. The token is argv headed for
a terminal, so `anuenue_eprint_arg` sanitizes it with darshana's
`tty_sanitize_buf` (ESC, C0, DEL, C1, malformed UTF-8 → `?`) and caps it at
64 bytes on a character boundary — an OSC title-set in argv now prints as
`--?]0;owned?`. Diagnostic path only; the filter's byte preservation is
untouched. Robustness gate 8 pins the wording, the sanitizing and the cap.

**429/429** unit assertions (was 410), observe-check **27** (was 22),
robustness **37** (was 29), fuzz **1 450 668**, `cyrius audit` clean, perf
flat (47.41 ns/byte truecolor ascii no-LF, +0.1%). Binary 222 520 →
**226 624 B** — DCE now keeps the sanitizer. Roadmap renumbered: word copy
v1.4.3, closeout + sweep v1.4.4, cyrius 6.7.x v1.4.5.

**1.4.1** — cut 2026-10-14. **Dependency refresh to every latest tag:
cmdit 1.4.0 + agnostik 1.12.0, sakshi to the stdlib**, and the repairs the
cmdit move called for.

*Pins*: cmdit 1.2.4 → **1.4.0**; agnostik 1.6.0 → **1.12.0**; darshana
**1.3.0** (already latest). **sakshi has no git pin**: `[deps.sakshi]`
dropped and `sakshi` added to `[deps].stdlib`, so its version is the
toolchain snapshot's — 2.5.8 under cyrius 6.7.9, the same bytes as before.
cyrius stays **6.7.9**: every latest dep tag pins it, 6.7.10 carries nothing
anuenue needs, and 6.7.11 (sakshi 2.5.10, −60 144 B) is untagged — roadmap
v1.4.6 (filed as v1.4.2; renumbered at v1.4.2 and v1.4.5). `lib/` re-vendored from scratch; `dist/anuenue.deps` gone (agnostik
1.12.0's sidecar now names the `boxed` cyrius used to credit to anuenue).

*cmdit 1.4.0 made four argv states visible that 1.2.4 parsed clean at exit 0*,
each reproduced on the v1.4.0 binary first: `--bool=value` stored ON whatever
the value (`--no-color=0` disabled colour); a command line over 2 MiB parsed as
its prefix (a trailing `--seed 99` vanished); `--nofile=3` dropped every flag
(architecture 006's hazard); positionals past 128 vanished. Now a usage error
(exit 2), a runtime failure (exit 1) twice, and all 200 rendered.
`src/main.cyr`'s parse-error switch routes NOMEM / ARGV through
`anuenue_fail` and names UNEXPECTED_VALUE; the chain became a flat lookup.
NOMEM (cmdit_new's OOM) is ⚠ **unproven** — the first alloc chunk always holds
the handle, so no external limit reaches it.

*Found in passing*: `fuzz/flag-parser.fcyr`'s `solo_tokens[44]` held 88 bytes
(a stack overrun in the harness), and its flag set had stopped at v0.7.0. Both
fixed. Measured and filed, not fixed: every `anuenue_fail` line ends in a blank
line (on v1.4.0 too; fixed at v1.4.2).

stdout byte-identical to v1.4.0 for every input v1.4.0 handled correctly (138
comparisons + goldens; `--help` and seven error paths identical on stderr).
**410/410** unit assertions (was 402), robustness **29** checks (was 21), fuzz
**1 450 668**, `cyrius audit` clean on all five stages, perf flat (46.74
ns/byte truecolor ascii no-LF, +0.1%). Binary 210 696 → **222 520 B** (see
[Binary](#binary)). Roadmap reorganised forward-facing, every open item pinned
1.4.2 → 1.6.0.

**1.4.0** — cut 2026-10-12. **cyrius 6.7.9 + darshana 1.3.0**, and the
items darshana's consumer survey filed in the roadmap. Audit delta
[`2026-10-12-v140-delta.md`](../audit/2026-10-12-v140-delta.md): 1 LOW +
3 INFO, all fixed, zero HIGH+ open — the two defects reproduced on the
v1.3.6 code before they were fixed.

*Pins*: cyrius 6.6.2 → **6.7.9**; darshana 1.1.1 → **1.3.0** (its bundle
needs cyrius ≥ 6.7.2, which is what moved the pin), its `path =
"../darshana"` dropped; sakshi 2.5.1 → **2.5.8**, required by the toolchain
move (the 6.7.9 snapshot ships 2.5.8 and any other tag is a `./lib/
shadows version-pinned` build warning). cmdit 1.2.4 and agnostik 1.6.0
unchanged. `lib/` re-vendored from scratch, superseding a never-committed
2026-09-26 `cyrius deps` output that had vendored darshana 1.1.2, cmdit
1.2.5 and agnostik 1.6.4 from the sibling working trees under the 1.1.1 /
1.2.4 / 1.6.0 tags — the `path`-mode drift the survey flagged.

*No language-bump repairs were needed in anuenue's source* — zero errors,
zero warnings at the first 6.7.9 build, and no 6.7 hazard (new reserved
words, lone `!`, compound assignment, narrow `*T`, unary `-`/`~` on a
constant) anywhere in `src/`, `tests/` or `fuzz/`. The move surfaced three
things outside the compiler: a stale `dist/` bundle (regenerated), docs
describing `sleep_ms`'s int32 truncation that cyrius 6.6.20 fixed
(re-measured, now history), and a `cyrius audit` that had been failing fmt
and docs since before the move (cleaned — minor-cut P(-1) step 1).

*The exit signalfd is darshana's.* `_open_exit_signalfd` was a hand-rolled
copy with a whole-mask rollback (**G-01 LOW**: a signal blocked before
animation came back unblocked after a failed open — `hup_blocked=0` on
v1.3.6) and no CLOEXEC (**G-02 INFO**). It is now `tty_open_signalfd` +
the stdlib's `fd_set_nonblocking`, probed with `tty_read_signal`, and —
**G-03 INFO**, the 2026-05-22 audit's INFO 8 + 9 — closed with
`tty_close_signalfd` as the LAST teardown step, unblocking only what it
added. Closing exposed a hazard, closed in-cut: with SIGINT + SIGTERM both
pending, the unblock delivered the second (exit 143); the close drains
first, and exit stays 0. **G-04 INFO**: the `--interval` clamp warning
named a cause that stopped being true at cyrius 6.6.20; reworded.

*The phase-cached escape table is kept*, re-measured in anuenue's own
harnesses: deleting it is −15% on truecolor but +33% on 256 and +42% on
16. Its cost is the byte-copy loop (a word copy measured 9–10 ns in every
mode) — filed as its own roadmap item.

stdout byte-identical to v1.3.6 (276 comparisons, six goldens, full
animation streams in three modes). Animation's syscall surface gains
`fcntl` and `close`. **402/402** unit assertions (was 384), signal gate
**18** checks (was 12), fuzz **1 450 672**, `cyrius audit` clean on all
five stages. Binary 204 312 → **210 696 B** (see [Binary](#binary)).

**1.3.6** — cut 2026-09-10. **Ecosystem migration onto cyrius 6.6.2.**
cyrius 6.5.35 → 6.6.2, darshana 1.0.0 → 1.1.1, sakshi 2.4.11 → 2.5.1,
agnostik 1.5.1 → 1.6.0; the orphaned `lib/agnosys.cyr` deleted. No source
change. *(This file was not refreshed at that cut; the entry and the
1.3.6 binary size — 204 312 B, measured at v1.4.0 by rebuilding the 1.3.6
tree, byte-identical to the 2026-09-10 build left in `build/` — were recorded
at v1.4.0.)*

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
the v1.3.0 roadmap (now in [CHANGELOG § 1.3.0](../../CHANGELOG.md#130--2026-08-25-animation-slot)).

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
[roadmap.md § v1.6.0](roadmap.md#v160--pipe-decorator-family) for the two still open); **Dogfooded**
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
the pre-GA plan (now in [CHANGELOG](../../CHANGELOG.md)). Surface frozen at
v0.8.0; capability baseline recorded by the M8 audit;
documentation set complete. The remaining v1.0 acceptance items
(*Dogfooded* + *Downstream gate*) need at least one external
consumer (likely `agnoshi` MOTD pipeline or `iam`) wiring anuenue
in for a minor-cycle soak window. Tagged on user signal per
[feedback_no_unprompted_version_bumps](https://github.com/MacCracken/agnosticos/blob/main/.claude/projects/-home-macro-Repos-agnosticos/memory/feedback_no_unprompted_version_bumps.md).

## Toolchain

- **Cyrius pin**: `6.7.18` (in `cyrius.cyml [package].cyrius`). History: `6.0.1` (scaffold → v1.0.0) → `6.0.56` (v1.1.0, agnos target) → `6.1.14` (v1.1.2) → `6.2.24` (v1.1.3) → `6.2.44` (v1.1.5) → `6.4.62` (v1.2.0) → `6.5.35` (v1.2.1) → `6.6.2` (v1.3.6) → `6.7.9` (v1.4.0) → `6.7.18` (v1.5.1).
- **Re-vendoring `lib/` at a pin bump**: `rm -rf lib cyrius.lock && cyrius lib sync --full && cyrius deps` (v1.4.0). The `rm` is what drops files the new snapshot no longer ships — `lib sync` alone only adds and overwrites — and the lock is regenerated because it goes stale the moment the pin moves. Then `cyrius distlib --all`.
- Pin-lag spectrum as of v1.5.1: cyrius 6.7.18 / darshana 1.6.0 / cmdit 1.5.0 / agnostik 2.0.0 — each the latest tag on 2026-10-29. sakshi is a stdlib module: 2.5.10, which 6.7.11 folded and 6.7.12–6.7.18 carry unchanged. Re-evaluate at each minor cut.
- **cyrlint from 6.7.11 checks array overruns and write lengths** (widened at 6.7.12 to `const` / enum sizes and top-level arrays). Warnings only, but `cyrius audit` fails on any, and `scripts/lint-check.sh` holds `src/`, `tests/` and `fuzz/` at zero. **`cyrfmt` from 6.7.12 checks continuation indents**: 2 spaces per open paren, 4 accepted, so a continuation needs a paren open across the line break.
- **Tags are what builds (cyrius ≥ 6.7.6).** A `path` beside `git` + `tag` is a dev override read only under `CYRIUS_LOCAL=1` / `--local`; a default `cyrius deps` resolves the tag and checks its commit pin in `cyrius.lock`. Before 6.7.6 the `path` won — that is how the never-committed 2026-09-26 `lib/` came to hold darshana 1.1.2 under `tag = "1.1.1"`. darshana's `path` was removed at v1.4.0; cmdit / agnostik keep theirs as overrides, and sakshi has no git entry at all from v1.4.1. When changing a tag, still `rm cyrius.lock && cyrius deps` and re-check the bundle's `# Version:` header.
- **`CYRIUS_DCE=1` shrinks the binary again on x86_64.** 6.5.35 NOPed unreachable functions in place, so DCE and non-DCE builds were the same size; by 6.6.2 the x86_64 build compacts them out again. Measured at v1.4.1: 980 280 B without, **222 520 B** with (v1.4.0: 898 824 / 210 696). (aarch64 still NOPs in place — "compaction declined on aarch64 ELF".)

## Source

| File | Lines | Surface |
|------|-------|---------|
| `src/hsv.cyr` | ~120 | **NEW at v0.9.0** (the M0-anticipated split). Holds `ANUENUE_PHASE_MOD = 1530` + `hsv_rainbow(phase, out_rgb)` — the integer 6-sector S=V=1 HSV→RGB. Move was triggered by `fuzz/emit-phase-esc.fcyr` wanting a clean target boundary; ADR 0002 (HSV inline) documents the broader "don't pull abaco" decision. `main.cyr` / `filter.cyr` / `animate.cyr` / `tests/anuenue.tcyr` / `tests/anuenue.bcyr` all include this before `filter.cyr` since filter references `ANUENUE_PHASE_MOD`. |
| `src/color.cyr` | ~350 | **NEW at M6 (v0.7.0)**. Color mode enum (`ANUENUE_COLOR_MONO`/`_16`/`_256`/`_TRUE`); override-string parser + enum mapping (`_color_override_from_str` / `_color_mode_from_override`); RGB quantization (`_channel_to_6`, `_rgb_to_256` xterm cube; `_rgb_to_16` bright-palette); `anuenue_detect_color_mode(no_color, force_color, override)` reading getenv + darshana 0.5.3's `tty_isatty`; `anuenue_passthrough()` MONO bypass (read/write loop, no escapes). Sandhi closeout at v0.7.1 removed the three `_*_compat` stand-ins. **v1.2.1** adds the `AnuenueColorReason` enum + `ANUENUE_COLOR_REASON` + `anuenue_color_reason_name` / `anuenue_color_mode_name`: all ten exits of `anuenue_detect_color_mode` now record which branch fired, so `-v` can answer *why* a mode was chosen. `anuenue_passthrough`'s failure paths route through `anuenue_fail`. |
| `src/filter.cyr` | ~1310 | `ANUENUE_*` constants + **`ANUENUE_ESC_TABLE_ENTRY_SIZE`** (M5). `hsv_rainbow` + `ANUENUE_PHASE_MOD` extracted at v0.9.0 — now live in `src/hsv.cyr`. M3: `utf8_seq_len` / `utf8_decode` / `cp_is_extending` (M5: binary-searched LUT) / `cp_is_regional_indicator`. M5: `_phase_esc_init()` / `_emit_phase_esc()` / `_PHASE_ESC_TABLE` (1 530 × 32 B heap; idempotent). **M6 (v0.7.0)**: `_phase_esc_init` branches on `ANUENUE_COLOR_MODE` to populate per-mode escapes (TRUECOLOR via `tty_fg_rgb_buf`, 256 via `tty_fg_256_buf`, 16 via `tty_sgr_buf`). `anuenue_filter()` keeps the M5 hot path; ASCII short-circuit unchanged. **Unaffected by the M8 audit fix** — writes one codepoint per iteration with the reserve check between, so the long-cluster overrun doesn't reach the filter path. **v1.4.0**: the phase-cached escape table re-measured and kept (deleting it: −15% truecolor, +33% 256, +42% 16); comments citing darshana's deleted `_ansi_emit_u8` and a "≈ 10 ns" table cost replaced with the measurement.  **v1.4.3**: `_emit_phase_esc` copies three 8-byte words (24-byte write footprint, advances by `elen`) — 9 ns per escape in every mode; `_phase_esc_init` zero-fills each payload so the scratch past `elen` is deterministic. Footprint argument: architecture 001. **v1.5.0** (ADR 0006): the no-colour marker recogniser (`_marker_cmp` / `_marker_at`), MONO's `anuenue_marker_strip`, `_span_walk` (span bytes raw, the `on` reset), `_reset_checked` (every marker reset followed by the reserve check — V-06), and the span state in `anuenue_filter` / `anuenue_render_bytes`. |
| `src/animate.cyr` | ~1390 | M4 surface (animation: slurp + pretag + frame loop + signalfd). **v1.4.0**: the exit signalfd is darshana's — `_open_exit_signalfd` = `tty_open_signalfd(TTY_SIGMASK_EXIT)` + stdlib `fd_set_nonblocking`, `_signal_pending` = `tty_read_signal`, and the new `_close_exit_signalfd` (drain, then `tty_close_signalfd` of only the bits the open added — `_ANUENUE_SIG_ADDED`) is the last step of every exit from the frame loop. `ANUENUE_SFD_NONBLOCK` removed. M5: ASCII short-circuit in `_pretag_clusters`; `_render_frame` routes through `_emit_phase_esc`; `_phase_esc_init` shared with filter. M6: animation benefits from per-mode escapes via the same path; MONO never reaches animation (main.cyr dispatches to passthrough first). **M8 (v0.8.0) fix**: `_render_frame`'s cluster-bytes copy loop got an inline mid-cluster flush guard — when the reserve threshold trips before all cluster bytes are written, flush + re-emit the same `phase` escape so the next bytes render under the same colour. Closes the long-cluster heap overflow surfaced by the audit. **v1.5.0** (ADR 0006): `_anim_prepare` (markers out, SGR out only outside a span, the span map), `_pretag_spans` with the per-cluster flags RAW / OPEN / JOIN / CONT, `_seq_len_in` (a UTF-8 sequence stops at a span edge), `_span_vt` (the VT500 parser step the row count runs inside a span), and the raw path in `_render_frame`. |
| `src/main.cyr` | ~400 | Entrypoint + flag dispatch. args_init / alloc_init / flags context (M6 added `-n` / `-C` / `-c` to the M2/M4 sets) / argv pack / flags_parse / **M6 colour-mode detect step writes `ANUENUE_COLOR_MODE`**; dispatch to print_version / print_usage / **anuenue_passthrough (MONO) or anuenue_animate (-a) or anuenue_filter**. **v1.4.1**: the parse-error switch is a flat lookup; cmdit 1.4.0's `NOMEM` / `ARGV` route through `anuenue_fail` as runtime failures (exit 1, no usage), `UNEXPECTED_VALUE` gets its own usage line. |
| `src/observe.cyr` | ~610 | **NEW at v1.2.1.** The sakshi/agnostik wiring. Holds the `AnuenueExit` exit-code enum + `_eprint` (both moved from `main.cyr`), the `AnuenueLogParse` level scale and `anuenue_log_parse` / `_name`, `anuenue_observe_init` (pins sakshi to fd 2, sets the level, sets `ANUENUE_VERBOSE`), gated span wrappers, `anuenue_log_kv_str` / `_int` / `anuenue_log_version`, and `anuenue_fail` (agnostik kind → stderr line + sakshi record → exit code). **Depends on nothing from anuenue** — only sakshi, agnostik and the stdlib — which is why it is included *first* and every other module can call `anuenue_fail` without a cycle. The colour-reason codes live in `color.cyr` for the mirror-image reason.  **v1.4.2**: `anuenue_fail` no longer writes a second newline after `agnostik_err_print`; the argv-echo helpers `anuenue_arg_cut` / `_render` / `_attached` / `anuenue_eprint_arg` (`ANUENUE_ERR_ARG_MAX` = 64), which call darshana's `tty_sanitize_buf` — a dep, so observe.cyr still depends on nothing from anuenue. |
| `src/version_str.cyr` | ~18 | **AUTO-GENERATED** by `scripts/version-bump.sh`. Holds `_VERSION_STR_ANUENUE` + `_VERSION_LEN_ANUENUE`. Never hand-edit; CI's Version consistency step asserts the literal matches `VERSION`. |
| `src/test.cyr` | 15 | top-level test entry stub (referenced by `cyrius.cyml [build].test`). Actual tests live in `tests/anuenue.tcyr`. |

The M0-anticipated `src/hsv.cyr` split landed at v0.9.0 (the fuzz
harness's `emit-phase-esc` target was the second consumer that
finally earned it). Source-file layout is now stable at v1.0;
post-1.0 splits would need new domain pulls (e.g. a sibling
pipe-decorator extracting shared code into the AGNOS shared-crates
registry, post-v1.x).

## Binary

- **Size (1.5.2)**: **536 544 bytes**, +4 096 B over v1.5.1, all anuenue's
  own: `.text` grew 872 B (`_cluster_cols_past_ext` and the filter's LF and
  carry branches), which moved the data segment to the next page. `.rodata` and
  the in-file `.bss` are unchanged. Non-DCE 1 531 872 B (unchanged: the growth
  fit the page there).
- **Size (1.5.1)**: **532 448 bytes**, +284 160 B over v1.5.0, and not
  anuenue's code. One change per row: cyrius 6.7.18 with the v1.5.0 dep tags
  **531 824** (+283 536); + cmdit 1.5.0 531 960 (+136); + darshana 1.6.0
  531 960 (0); + agnostik 2.0.0 532 448 (+488). The toolchain row is data:
  `.text` +832 B, in-file `.bss` −58 424 B (sakshi 2.5.10's buffers in bytes),
  `.rodata` 38 790 → 380 751 B (+341 961, the same growth agnostik measured in
  its own build at this pin). That growth is the `bayan` fold agnostik's
  `dist/agnostik.deps` pulls in. From 6.7.13 it includes `lib/unicode/`, and all
  three tables are in the binary byte for byte, **307 252 B** of global string
  literals that DCE keeps although it drops every function that reads them.
  anuenue cannot drop `bayan`, so the step is recorded; filed as cyrius
  `2026-10-29-anuenue-dce-keeps-literals-of-dead-code.md`. Non-DCE 1 531 872 B
  (was 997 856).
- **Size (1.5.0)**: **248 288 bytes**, +12 440 B over v1.4.5, all anuenue's
  own source: no toolchain or dependency change (cyrius 6.7.9, darshana 1.3.0,
  cmdit 1.4.0, agnostik 1.12.0, sakshi 2.5.8 all unchanged). The no-colour span
  code on every route: the marker recogniser and MONO's word-at-a-time strip,
  the span walk, animation's prepare pass, span-aware pre-tag (four cluster
  flags) and the VT500 parser step its row count runs. Like v1.4.4's, the
  growth comes in page-sized steps, so per-function attribution is not
  meaningful. Non-DCE 997 856 B (+12 440, the same delta).
- **Size (1.4.5)**: **235 848 bytes**, +48 B over v1.4.4 — the SGR stripper and its
  inline check. Non-DCE 985 416 B.
- **Size (1.4.4)**: **235 800 bytes**, +9 176 B over v1.4.3, all anuenue's
  own: `fd_wait_ready` for the H-02 poll wait (+4 096 B, measured alone),
  then the H-01 width table (82 ranges), row count and window-size query
  plus H-05's pretag change. The binary grows in what look like page-aligned
  steps, so finer attribution is not meaningful. Non-DCE 985 368 B.
- **Size (1.4.3)**: **226 624 bytes** — the same total as v1.4.2, though the
  binaries differ in content (the copy loop became three words and the init
  gained the zero-fill; the layout nets to zero bytes).
- **Size (1.4.2)**: **226 624 bytes** (~221 KB), +4 104 B over v1.4.1 — all
  anuenue's own change, and all one cause: the argv echo calls darshana's
  `tty_sanitize_buf`, so DCE now keeps it and its UTF-8 validator (the filter
  path never called either), plus four small helpers. The blank-line fix
  changed no byte count.
- **Size (1.4.1)**: **222 520 bytes** (~217 KB), +11 824 B over v1.4.0's
  **210 696 B**. Tracked every release; **not capped** — see the policy note.
  Attributed by building each step on its own (all `CYRIUS_DCE=1`, x86_64,
  cyrius 6.7.9):

  | Step | Binary | Δ |
  |---|---:|---:|
  | v1.4.0 (cmdit 1.2.4, agnostik 1.6.0, `[deps.sakshi]` 2.5.8) | 210 696 | — |
  | cmdit → 1.4.0 | 219 936 | +9 240 |
  | agnostik → 1.12.0 | 222 416 | +2 480 |
  | sakshi → stdlib module (same 2.5.8 bytes) | 222 416 | 0 |
  | anuenue: the parse-error switch | **222 520** | +104 |

  cmdit is most of it — its bundle grew 1 638 → 2 800 lines across ten
  releases (argv read once per process, positional and repeat arrays that
  grow, the OOM guards). agnostik's bundle more than doubled (160 → 346 KB,
  ~82 KB of it doc comments) but DCE keeps nearly all of that out. **Next
  step down is queued**: sakshi 2.5.10's buffer fix measured −60 144 B in a
  6.7.10 trial (223 872 → 163 728 B) and arrives with cyrius 6.7.11 —
  roadmap v1.5.1 (v1.4.6 until v1.5.0).

  v1.4.0's own attribution, against v1.3.6's **204 312 B**:

  | Step | Binary | Δ |
  |---|---:|---:|
  | v1.3.6 (cyrius 6.6.2, darshana 1.1.1, sakshi 2.5.1) | 204 312 | — |
  | cyrius → 6.7.9, `lib/` re-vendored | 210 352 | +6 040 |
  | sakshi → 2.5.8 | 210 320 | −32 |
  | darshana → 1.3.0 | 210 600 | +280 |
  | anuenue: the darshana signalfd lifecycle + drain | **210 696** | +96 |

  The toolchain is nearly all of it. The 814 488 → 204 312 drop between
  v1.3.5 and v1.3.6 is the toolchain too: cyrius 6.6.x compacts DCE'd code out
  of the x86_64 binary again (point 2 below no longer holds).
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
  2. **`CYRIUS_DCE=1` stopped removing anything** — on 6.5.x, where it
     NOPed unreachable functions in place. *(No longer true from 6.6.x on
     x86_64, which compacts them out again: 898 824 B without DCE vs
     210 696 B with, at v1.4.0. The first-party dep surface is still the
     floor — it is just a much lower floor now.)*
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
- **Size history**: 1.5.2 = 536 544 B, 1.5.1 = 532 448 B, 1.5.0 = 248 288 B, 1.4.5 = 235 848 B, 1.4.4 = 235 800 B, 1.4.3 = 226 624 B, 1.4.2 = 226 624 B, 1.4.1 = 222 520 B, 1.4.0 = 210 696 B, 1.3.6 = 204 312 B, 1.3.5 = 814 488 B, 1.3.4 = 814 488 B, 1.3.3 = 814 480 B, 1.3.2 = 814 448 B, 1.3.1 = 814 448 B, 1.3.0 = 814 448 B, 1.2.2 = 809 984 B, 1.2.1 = 809 520 B, 1.2.0 = 389 648 B, 1.1.3 = 394 440 B, 1.0.0 = 351 200 B, 0.9.0 = 351 200 B, 0.8.0 = 351 200 B, 0.7.1 = 350 488 B, 0.7.0 = 349 832 B, 0.6.0 = 335 160 B, 0.5.0 = 334 120 B, 0.4.0 = 322 368 B, 0.3.0 = 317 216 B, 0.2.0 = 304 368 B. Figures up to 1.0.0 measured genuine DCE elimination; 1.2.0 – 1.3.5 measure the whole binary (6.4.x / 6.5.x NOPed dead code in place — point 2 above); 1.3.6 onward are compacted again, so 1.3.6 / 1.4.x compare with each other, not with the 1.2.x–1.3.5 rows.
- **Output path**: `build/anuenue`

## Tests

| File | Status |
|------|--------|
| `tests/anuenue.tcyr` | **608 assertions across 75 groups** at v1.5.2 (+13 / +2 groups, `test_v152_ext_cols`: `_cluster_cols_mb` on clusters that start with an extender, and the climb for lines that start with one). **595 across 73** at v1.5.1 (unchanged; `argv1` / `argv2` / `argv5` in `test_m2_flags` resized to hold their pointers — cyrlint's overrun rule, and the cause of the v1.4.3 crash). At v1.5.0 (+89 / +13 groups, in `test_v150_markers` / `test_v150_vt` / `test_v150_review`: marker recognition, MONO's strip and `_find_esc`, the prepare pass, raw / OPEN / JOIN / CONT clusters, `_span_vt`'s transitions, the row count over intact escapes, and one group per review finding V-07 to V-10). v1.4.5: **506 across 60** (+22, `test_v145_sgr`: every SGR form, every non-SGR that must pass, the held tail, the 128 / 129-byte bound). v1.4.4: **484 across 59**, in sixteen per-cut functions plus `test_word_copy` / `test_v144_rows` (v1.4.4 split `main()`; +47: H-01 width + rows +40, H-05 clustering +6, H-04 reserve bound +1). v1.4.3 was **437 assertions across 56 groups** (+8 / +1 group, in its own function `test_word_copy` — see the miscompile note in the roadmap: the word copy's footprint fits the reserve, the payload past `elen` is zero after a rebuild in place, and the escape / scratch / untouched layout at an unaligned `pos`). v1.4.2 was **429 across 55** (+19 / +1 group: the argv echo — the 64-byte cut and its UTF-8 step-back, the sanitizer's ESC / BEL / LF / C1 replacement, `anuenue_arg_attached`; mutation-checked). v1.4.1 was **410 across 54** (+8 / +1 group: cmdit 1.4.0's parse failures as `src/main.cyr` routes them — `--no-color=0` is `UNEXPECTED_VALUE` and leaves the flag unset, the 0-handle contract the NOMEM branch rests on, and the three new codes' values). v1.4.0 was **402 across 53** (+18 / +1 group: the exit signalfd through darshana — CLOEXEC and O_NONBLOCK read back with `fcntl`, a real SIGINT reported and consumed, SIGINT + SIGTERM pending across the close, the mask restored, a pre-blocked SIGHUP left blocked; dropping the drain kills the test run, dropping `& ~prev` fails 3). v1.2.2 was **349 assertions across 46 groups** (v1.2.2: +41 across 4 groups, one per audit finding with a testable invariant — A-01 table init, A-02 clamp arithmetic incl. a pin that `i64::MAX * 1e9` really wraps, A-04 colour-value parsing incl. the BAD sentinel, A-05 cap behaviour incl. that the sentinel is the stop offset). v1.2.1 was **308 assertions across 42 groups** (v1.2.1: +66 across 7 new groups covering the sakshi/agnostik wiring — log-level parsing incl. case-sensitivity / empty string / null pointer, the parse-to-`SK_*` scale mapping, verbosity resolution, colour-reason recording, name-function totality, and the agnostik-kind → exit-code mapping). M1: smoke/HSV/geometry/constants (47). M2: flags (24 — was 27; the v1.1.4 `flags_*` → `cmdit_*` migration collapsed three separate parse-then-get checks into single return-code assertions, e.g. `flags_parse`+`flags_get_bool(f_help)` → one `cmdit_parse_argv(...) == CMDIT_HELP`). M3: utf8_seq_len/decode/cp_is_extending/cp_is_regional_indicator (30). M4: animate constants + _pretag_clusters + _count_lf_clusters + _input_ends_with_lf + -a/-d/-S flag parsing (42). M5: phase-cache idempotency, byte-identical round-trip, phase normalization, table layout (26). M6: mode enum + override parser + `_channel_to_6` bucket boundaries + `_rgb_to_256` canonical hues + `_rgb_to_16` bright-palette quantization + 256/16 escape framing + bounds rejection (69). **M8 (v0.8.0): "_pretag_clusters long-combiner chain" (4)** — A + 511 combiners → 1 cluster spanning 1023 bytes; locks the unbounded-cluster invariant the M8 audit fix relies on. End-to-end behaviour owned by golden + animate-smoke (+ M8 long-cluster section) + perf-bench. |
| `tests/anuenue.bcyr` | **8 rows at v1.4.0**: the two M1 trend rows plus, per colour mode, `_emit_phase_esc` (the table) vs `hsv_rainbow` + the darshana composer — the comparison behind keeping the table (v1.4.0, loaded host: truecolor 43–45 vs 31–33 ns, 256 30–31 vs 37–38, 16 18 vs 24; `hsv_rainbow` 9, `tty_fg_rgb_buf` 23–28 at darshana 1.3.0, was 37 at 1.1.1). The "~10 ns/call" table figure below is not what the byte-copy loop costs (41–43 ns under cyrius 6.6.2). Previously: 2 micro-benchmarks. At v1.2.1: `hsv_rainbow` **8 ns/call**, `tty_fg_rgb_buf` **52 ns/call** — **not comparable to pre-v1.2.1 figures**: 6.5.35's `bench` harness measures and subtracts a timer floor (1.347 µs per clock read on the reference host) that the 6.4.62 harness did not. Pre-M5 the filter loop called both per cluster; M5+ uses `_emit_phase_esc` (~10 ns/call) instead. The micros still measure the table-build path. |
| `fuzz/*.fcyr` (v0.9.0+) | **Eight harnesses, 1 790 016 assertions per run at v1.5.2** — `pretag-clusters` 108 687 → 118 646: the token corpus gains VS-16 and a wide ideograph, every multi-byte cluster's columns are checked against an independently written reference (V-11), and the climb against the LF count at three widths. **1 780 057 at v1.5.0** — `no-colour-markers` (new, 258 175): MONO's strip and animation's prepare pass against an independent reference, whole and chunked with the held tail carried, plus the pre-tag's coverage and flag invariants over tokens that cut markers and UTF-8 sequences. At v1.4.5: **seven harnesses, 1 521 882 assertions per run** — `sgr-strip` (new, 30 000) checks `anuenue_sgr_strip` against an independent reference and that stripping in two chunks with the held tail carried equals stripping in one. At v1.4.4: **six harnesses, 1 491 882** (`pretag-clusters` 108 687: v1.4.4 added coverage invariants — the first cluster at byte 0, an LF cluster the LF alone — and an LF / combining / ZWJ / RI token corpus; on v1.4.3's code they fail 584 times). At v1.4.3: **1 483 587** (`emit-phase-esc` **1 046 876** — v1.4.3 restated its write invariant for the word copy: the escape, zero scratch to `pos + 24`, nothing after; plus `fuzz_emit_stream`, 3 000 clusters per mode checked against a byte-copy reference over every flushed prefix). At v1.4.1: 1 450 668 (`emit-phase-esc` 1 013 957, `utf8` 180 088, `pretag-clusters` 100 392, `flag-value-parsers` 96 091, `rgb-quantizers` 60 000, `flag-parser` 140), zero failures. v1.4.1's `flag-parser` change: the error-code invariant is a set check (every code must be one `src/main.cyr` names) rather than a range cmdit had outgrown; the flag set gained `-i` / `-v` / `--log-level`; a new group asserts every boolean given `=value` is `UNEXPECTED_VALUE`; and `solo_tokens[44]` (44 bytes holding 88) became `[112]`. v1.4.0 was 1 450 672 (`flag-parser` 144). At v0.9.0: **Five harnesses populated.** `flag-parser.fcyr` (M2), `utf8.fcyr` (M3), `pretag-clusters.fcyr` (M4), `emit-phase-esc.fcyr` (M5), `rgb-quantizers.fcyr` (M6). Each uses a Knuth-MMIX LCG for deterministic seed-driven exploration; each returns `assert_summary()` so failed invariants set a non-zero exit code. Combined: **1 354 581 assertions** as re-measured at v1.2.1 (`emit-phase-esc` 1 013 957, `utf8` 180 088, `pretag-clusters` 100 392, `rgb-quantizers` 60 000, `flag-parser` 144), zero failures. `cyrius fuzz` is the gate; runs in CI. Previous `tests/anuenue.fcyr` stub deleted (wrong path; `cyrius fuzz` looks at `fuzz/*.fcyr`). |
| `tests/golden/*.out` | **Six fixtures**. M2/M3: `agnos-rainbow-s100` (238 B), `cjk-mixed-s0` (125 B), `combining-s0` (155 B), `zwj-flag-s0` (135 B). **M6: `agnos-rainbow-256-s100.out` (160 B), `agnos-rainbow-16-s100.out` (82 B)**. All six byte-identical across the M5/M6/M8 cuts — proves the mode-aware phase cache matches runtime exactly and that the M8 fix is local to the long-cluster path. Plus three MONO equivalence checks in golden-check.sh (`NO_COLOR=1 anuenue` / `--no-color` / `--color=none` all byte-identical to input). |
| `scripts/animate-smoke.sh` | M4 (v0.5.0). Animation structural guard. M6: invokes with `--color=24bit` so the TTY-detection in M6 doesn't drop the test into MONO. **M8 (v0.8.0) extension**: long-cluster section runs the historical attack (base + 16 000 combining acutes), asserts clean exit and full byte preservation (~976 000 combiner bytes over 61 frames) through the mid-cluster flushes. **v0.9.0 extensions**: `--color=256` + `--color=16` per-mode sections — each asserts clean exit, non-empty output, full cursor lifecycle, and the per-mode SGR shape (CSI 38;5;Nm for 256, CSI 9[1-7]m for 16; explicit no-leak check that truecolor 38;2;… doesn't appear under `--color=256`). |
| `scripts/robustness-check.sh` | **83 checks at v1.5.2** — gate 12 (new, V-11): an extender after an LF and a byte carried to the end after a ZWJ, compared across the filter, the one-shot route and animation frame 0 in all three colour modes, each with an oracle independent of the routes agreeing; the LF at the read boundary and one byte per write. Every check fails on v1.5.1. **80 checks at v1.5.1** — gate 7's over-2 MiB check is inverted: on cyrius ≥ 6.7.12 with cmdit ≥ 1.4.2 a 2.4 MB command line parses whole, and the check asserts exit 0 and that the trailing `--seed 99` is honoured (the first cluster's escape equals `--seed 99 x`'s). It fails on the v1.5.0 binary. **80 checks at v1.5.0** (gate 11: no-colour spans on filter / one-shot / animation × 3 modes with the phase pause checked by removing the span; an LF inside a span; the end closing a span; adjacent spans; a reserve flush in a span; 100 000 empty spans (V-06); the routes agreeing on hues and bytes at span edges; lenient markers; near-misses; markers split across the read at every offset; dribble; MONO). **60 checks at v1.4.5** (gate 10: input SGR stripped on filter / one-shot / animation × 3 modes, MONO byte-exact, 5- / 19- / 128-byte SGRs across the 4096-byte read at every offset, a one-byte-per-write dribble, the bound, non-SGR intact). **46 checks at v1.4.4** (gate 6: H-02 — a stalled non-blocking stdin on three routes and a stalled stdout must cost ≤ 5 ms CPU; H-05: animation keeps every byte, four inputs). **38 checks at v1.4.3** (gate 9: no NUL on stdout from NUL-free input — 18 runs across filter / one-shot / animation × 3 modes, catching a leaked word-copy scratch byte). **37 at v1.4.2** (gate 8: the six parse-error lines verbatim, an OSC + BEL + CSI token echoed with no raw control byte, a 302-byte token capped at 64 + `...`). **NEW at v1.2.2** (P-1 audit). Adversarial byte streams and adversarial argv against the real binary — the surfaces the unit suite and the seeded fuzz harnesses do not reach, and where four of the nine audit findings lived. **29 checks at v1.4.1** (21 at v1.4.0; gate 7 added: four booleans given `=value`, 200 positionals, a 2.4 MB command line plus a 1.0 MB control, and `--nofile=3` — the argv states cmdit 1.2.4 parsed clean; all seven defect checks fail on the v1.4.0 binary). Eleven checks at v1.2.2: UTF-8 carry across the 4096-byte read boundary (52 comparisons, chunked vs `dd bs=1` — the property `carry_len` exists for, previously untested end to end); byte preservation under malformed UTF-8 (116 comparisons across overlong 2/3/4-byte forms, UTF-16 surrogates, >U+10FFFF, the 0xF5–0xFF range, lone continuations, EOF truncation, embedded NULs, all 256 byte values); every integer flag at both i64 extremes terminating with a documented exit code; and one process-level regression per finding. Runs in CI. |
| `scripts/observe-check.sh` | **27 checks at v1.4.2** (was 22; gate 5: five failure paths, each exactly one stderr line ending in one newline). **NEW at v1.2.1.** The observability gate, and the enforcement point for pipe-purity under diagnostics. Four gates: (1) stdout byte-identical across 144 corpus × colour-mode × verbosity combinations — the property a unit test cannot express, and the one that matters because a byte leaked onto fd 1 corrupts every pipeline `-v` is enabled in; (2) stderr empty in every default-verbosity run, including for wholly invalid UTF-8; (3) `-v` carries the fields a bug report needs (version, phase step, colour mode, colour **reason**, route, byte count) and never reports `reason=unset`; (4) the forced read failure (stdin closed → EBADF) prints the agnostik kind, logs `code=1010`, and still exits 1. Runs in CI. |
| `scripts/signal-check.sh` | **NEW at v1.3.0**; **18 checks at v1.4.0** (was 12). The process signal mask across the exit signalfd's open and close (via `tests/probes/sigmask-probe.cyr`, `plain` and `preblocked` cases, normal and under `prlimit --nofile=3`), CLOEXEC / non-blocking on the fd, SIGTERM latency independent of `-i`, `-d` honoured at every `-i`, `-i` pacing and validation, and — v1.4.0 — two exit signals at once still exiting 0. |
| `scripts/pty-check.sh` / `scripts/allocfail-check.sh` | **35** PTY checks at v1.5.2 (`mark-starts-line`, `zwj-emoji-starts-line`: lines that start with an extender, each failing on v1.5.1). **33** PTY checks at v1.5.0 (eight span cases; the terminal model parses OSC / DCS / SOS / PM / APC and intermediates as xterm does, and the gate requires every frame to climb back to one row, never past the top). **25** PTY checks at v1.4.4 (gate 5: the UAX #11 width oracle, then ten sized-pty animation cases played into `scripts/term-model.py`) and **23** allocation checks (NOMEM under exhaustion); `scripts/fault-check.sh` **17** (new: D-01 probe, gdb injection of E-01 / EINTR / fcntl failure, the per-route syscall allowlist). Previously **14** PTY checks (v1.3.1) and **15** allocation-failure probe checks (v1.3.4); unchanged at v1.4.0. |
| `scripts/perf-bench.sh` | v1.5.0: `COLOR=none` times MONO, which scans for ESC from v1.5.0. v1.4.0: `COLOR=256` / `COLOR=16` select the mode (default 24bit) — the table's value differs by mode, so a truecolor-only harness would have recommended deleting it. M5 (v0.6.0). End-to-end ASCII + UTF-8 per-byte overhead. M6: invokes with `--color=24bit` for the same reason. The M5 ratchet. Latest run at v1.2.1 (`RUNS=11`, idle host, final binary): ASCII no-LF **46.63 ns/byte**, ASCII w/ LFs **50.99**, UTF-8 mixed **41.77** — all under the 60 ns/byte cap. Measured head-to-head against a rebuilt v1.2.0 binary rather than against a historical figure. |

Assertion count history (to v1.5.0 below; v1.5.2 **608**, +13): M1 47 → M2 74 (+27) → M3 104 (+30) → M4 146 (+42) → M5 172 (+26) → M6 241 (+69) → M8 245 (+4) → v1.1.4 **242** (−3, cmdit migration) → v1.2.1 **308** (+66, observability wiring) → v1.2.2 **349** (+41, P-1 audit regressions) → v1.3.0 **364** (+15) → v1.3.3 **380** (+16) → v1.3.4 **384** (+4, E-03) → v1.4.0 **402** (+18: the darshana-signalfd group +19, the drain-cap pin +1, the two `ANUENUE_SFD_NONBLOCK` pins −2 with the constant) → v1.4.1 **410** (+8, cmdit 1.4.0's parse failures) → v1.4.2 **429** (+19, the argv echo) → v1.4.3 **437** (+8, the word copy) → v1.4.4 **484** (+47, H-01 / H-05 / H-04) → v1.4.5 **506** (+22, input SGR stripping) → v1.5.0 **595** (+89, no-colour spans and the review's findings).

## Dependencies

Direct (declared in `cyrius.cyml`):

| Dep | Tag | Role | Status |
|-----|-----|------|--------|
| `darshana` | **1.6.0** | ANSI escape generation + the animation exit-signal fd. Pin history: 0.5.1 (M1 truecolor `tty_fg_rgb_buf` / `tty_sgr_reset_buf`); 0.5.2 (M4 `tty_cursor_up(n)` / `tty_cursor_down(n)`); 0.5.3 (M6 sandhi closeout — `tty_isatty(fd)` / `tty_sgr_buf` / `tty_fg_256_buf`); 0.7.1 (v1.1.3 refresh); 0.9.0 (v1.1.x); 1.0.0 (v1.2.1 — the API freeze); 1.1.1 (v1.3.6); 1.3.0 (v1.4.0 — needs cyrius ≥ 6.7.2; `path` dropped); **1.6.0 (v1.5.1 — additive; the Linux code anuenue calls is body-identical to 1.3.0's)**. | Live. **Fourteen symbols called**, all inside the frozen surface: filter path `tty_fg_rgb_buf` / `tty_fg_256_buf` / `tty_sgr_buf` / `tty_sgr_reset_buf`, colour detect `tty_isatty`, animation `tty_cursor_up` / `_hide` / `_show` / `tty_sgr_reset`, from v1.4.0 the exit-signal lifecycle `tty_open_signalfd` / `tty_read_signal` / `tty_close_signalfd` (replacing a hand-rolled copy whose rollback unblocked the whole mask and whose fd lacked CLOEXEC), from v1.4.2 `tty_sanitize_buf` (the argv echo on stderr only), and from v1.4.4 `tty_winsize` (animation's row count). Evaluated and not used: `TTY_SIGMASK_PIPE`, `tty_winsize_or`, `tty_sgr_list_buf`, `tty_bg_256_buf` — reasons in the [v1.4.0 audit delta](../audit/2026-10-12-v140-delta.md). In the bundle, not yet called: `tty_sgr_len` / `tty_sgr_strip_buf` (1.4.0, from anuenue's proposal — the swap rides along with roadmap v1.6.0), `tty_isatty_is_per_fd` (1.6.0). |
| `sakshi` | **stdlib** (2.5.10 in cyrius 6.7.18) | Errors / tracing / structured logging | **A `[deps].stdlib` module from v1.4.1** — `[deps.sakshi]` dropped; the version is the toolchain snapshot's, so a `cyrius` bump is a sakshi bump (6.7.10 → 2.5.9, 6.7.11 → 2.5.10). **Wired at v1.2.1** (`src/observe.cyr`) — was a declared dep with zero call sites from M0 through v1.2.0. Uses `sakshi_set_output_fd` (pinned to fd 2), `sakshi_set_level` / `_get_level`, `sakshi_log_kv`, `sakshi_span_enter` / `_exit`, and the `SK_*` level enum. **Never** `sakshi_output_file` / `_udp` — those would breach the capability bound. Note `span_enter`/`_exit` are NOT level-gated inside sakshi, so anuenue routes them through gated wrappers. Pin history: 2.2.5 → 2.4.0 → 2.4.11 (v1.2.1) → 2.5.1 (v1.3.6) → 2.5.8 (v1.4.0, forced by the snapshot — any other tag was a `./lib/ shadows version-pinned` build warning, which is why v1.4.1 stopped pinning it) → 2.5.10 (v1.5.1, the 6.7.18 snapshot: its four buffers in bytes, −58 424 B of static data). |
| `agnostik` | **2.0.0** | Shared Result / Error shapes | **Wired at v1.2.1** (`src/observe.cyr`) — same story. Uses `agnostik_err_new` / `AgnostikError_code` / `agnostik_err_print` and the `STIK_ERR_*` kind enum for the three real failure paths (stdin read, buffer alloc, escape-table alloc). Kind → exit code: `STIK_ERR_INVALID_ARGUMENT` → 2, everything else → 1. **Trap:** `agnostik_err_new(kind, message: Str)` needs a real `Str`; cyrius 6.5.35 does not coerce a literal in return-expression position, so `anuenue_fail` converts explicitly with `str_new`. 1.6.0 → **1.12.0** at v1.4.1: nothing anuenue calls changed (bodies, `STIK_ERR_*` values, `CODE_IO` = 1010, the stderr line); 1.6.2 dropped the raw `syscall(318)`; 1.7.0 put private helpers under `_stik_`. **2.0.0 at v1.5.1** (from 1.12.0): accessors take their struct's name, so `agnostik_err_code` → `AgnostikError_code`; 1.12.3 made `agnostik_err_new` return a static `RESOURCE_EXHAUSTED` error when its 24 bytes cannot be had (anuenue's 2026-10-14 issue) and `agnostik_err_print` skip the empty message's zero-length write. Its `dist/agnostik.deps` lists `bayan`, which from cyrius 6.7.13 carries 307 252 B of Unicode tables into anuenue's binary (§ Binary). |
| `cmdit` | **1.5.0** | CLI / argument parsing (getopt-long; the stdlib `flags` parser productized + extended). Local sibling `../cmdit`. | **Adopted at v1.1.4** (the `flags` → cmdit migration; anuenue is cmdit's 2nd worked example after kii). `print_usage` uses `cmdit_help_flags` (the table-only renderer) to keep anuenue's custom help framing. **1.2.4 is the P-1 audit cut** — anuenue is exposed to none of its four findings (literal prog name to `cmdit_new`; never calls `cmdit_completions`), confirmed by a byte-identical CLI-surface diff. **1.4.0 at v1.4.1** (from 1.2.4): `cmdit_help_flags` byte-identical, but three codes became reachable — `UNEXPECTED_VALUE` (11, `--bool=value`), `NOMEM` (12, a 0 handle), `ARGV` (13, a command line not readable whole) — and positionals past 128 are kept. `src/main.cyr` names all three. **1.5.0 at v1.5.1**: no API or error-code change, every function anuenue calls body-identical; 1.4.2 narrowed `_cmdit_argv_whole` from `len >= 2 MiB` to `len == 2 MiB`, so with cyrius ≥ 6.7.12 a longer command line parses whole. |
| Cyrius stdlib | n/a | string, fmt, alloc, io, vec, str, syscalls, assert, bench, args, **chrono (M4)** | Auto-resolved via `cyrius deps`. `args` added at M2; `flags` (added M2) **DROPPED at v1.1.4** when CLI parsing moved to `[deps.cmdit]`; `chrono` added at M4 for frame timing (`sleep_ms`) and deadline math (`clock_now_ns`). |

No pre-release / pre-1.0 deps on the critical path. No external (non-AGNOS) deps.

## Verification Hosts

| Host | Role | Status |
|------|------|--------|
| `archaemenid` (Beelink SER, AMD Zen) | Primary dev box; will be the iron-soak target once AGNOS userland boots there | Not yet (anuenue runs on host Linux for now) |
| Host Linux (CI runner pattern) | Build + test gate via `.github/workflows/ci.yml` | Active from M0 |

## Consumers

- **thoth** — library consumer (since anuenue v1.2.0). Vendors
  `dist/anuenue.cyr` as `src/vendor/anuenue.cyr` (re-synced by its
  `scripts/sync-anuenue.sh`; at 1.3.6 as of 2026-10-14) for `/theme
  rainbow`, reading `hsv_rainbow`. The bundle's code is unchanged since
  then, so every v1.4.x cut is a no-op for it; re-check at any change to
  `src/hsv.cyr`. *(Listed at v1.4.4; this section said "None yet" since
  M0 — the pipeline consumers below are still to come.)*

Anticipated pipeline consumers:
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
  Latest audit: [`docs/audit/2026-10-15-v150-delta.md`](../audit/2026-10-15-v150-delta.md)
  (v1.5.0 — 12 findings, ten fixed before release, zero HIGH+ open). Before it:
  [`2026-10-14-v14x-delta.md`](../audit/2026-10-14-v14x-delta.md) (v1.4.4),
  [`2026-10-12-v140-delta.md`](../audit/2026-10-12-v140-delta.md) (v1.4.0),
  [`2026-08-26-audit.md`](../audit/2026-08-26-audit.md) (v1.3.3),
  [`2026-08-25-v13x-delta.md`](../audit/2026-08-25-v13x-delta.md) (v1.3.2),
  [`2026-08-25-audit.md`](../audit/2026-08-25-audit.md) (v1.2.2).
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
  signal mask not restored after completion) were measured at v1.3.0 — and
  turned out to be B-01 — and closed for good at v1.4.0, when the exit
  signalfd moved onto darshana's open / read / close (G-03).

## Next

**v1.6.0** is the pipe-decorator family, gated on a second pipe-decorator
wanting a rainbow tint or a consumer's ask. Adoption rides along — including a
first producer of no-colour spans — and so does the swap of anuenue's SGR
stand-in (`_sgr_len` / `anuenue_sgr_strip`) for darshana 1.4.0's
`tty_sgr_len` / `tty_sgr_strip_buf`, gated on stdout identity and a flat
filter. No patch slot is open. Every item and its gate:
[roadmap.md § Release map](roadmap.md#release-map).
