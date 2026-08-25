# ADR 0004 — Diagnostics go to stderr, and are off by default

- **Status**: Accepted
- **Date**: 2026-08-25
- **Cut**: v1.2.1
- **Supersedes / relates to**: [ADR 0001 — pipe-purity](0001-pipe-purity.md)

## Context

sakshi and agnostik have been declared dependencies since the `cyrius init
anuenue` scaffold in May 2026. Through v1.2.0, **no anuenue source file
referenced a single symbol from either**. They were linked into every binary and
never called.

That state is easy to misread as "these are dependencies anuenue doesn't need."
It isn't. [first-party-standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-standards.md)
makes sakshi the canonical error/tracing crate for AGNOS first-party tools and
agnostik the shared Result/Error shapes those APIs surface. anuenue is a
first-party tool. The dependencies were correct; the wiring was missing.

Two concrete costs of the missing wiring:

1. **v1.1.5's AGNOS colour collapse.** `anuenue_detect_color_mode` fell through
   its env heuristics on a platform that sets no env and landed on the 16-colour
   fallback, quantising a smooth HSV gradient down to six ANSI colours. The
   function reported *which* mode it chose; it never reported *why*. The only way
   to diagnose it was to read the source and reason about branch order.
2. **Silent failures.** `anuenue_filter` and `anuenue_passthrough` returned a
   bare `1` on a read error or allocation failure — no message on any file
   descriptor. From the outside, a failing filter and a filter given empty input
   were indistinguishable.

So anuenue needs diagnostics. The hard part is that anuenue is a **pipe filter**
whose entire value proposition is being safe in the middle of someone else's
pipeline.

## Decision

**Every byte of diagnostic output goes to fd 2. Logging is off by default.**

Three mechanisms, none of them optional:

1. **The sink is pinned.** `anuenue_observe_init` calls
   `sakshi_set_output_fd(2)` before setting any level. sakshi offers file
   (`SK_OUT_FILE`), UDP (`SK_OUT_UDP`), ring-buffer and hook targets; anuenue
   selects none of them. File and network targets would breach the capability
   bound in CLAUDE.md ("no file I/O, no network"), and anuenue's syscall surface
   stays read/write/brk/exit.

2. **Silence is the default, and it is anuenue's default, not sakshi's.**
   sakshi's own default level is `SK_INFO` — inheriting it would have put info
   lines on the stderr of every `iam | anuenue` in every MOTD on every login.
   anuenue defines its own level scale one above sakshi's so that "off" has a
   non-negative name (cyrius has no negative literals), and `--log-level=off`
   maps to a sakshi level of `(0 - 1)`, strictly below `SK_FATAL`, so
   `_sk_log`'s `level > _sk_log_level` test suppresses every level including
   fatal.

   Spans are a special case worth writing down: `sakshi_span_enter` and
   `sakshi_span_exit` are **not** level-gated inside sakshi — they emit whenever
   called. anuenue routes both through wrappers that check `ANUENUE_VERBOSE`
   first, or a silent run would still print ENTER/EXIT lines.

3. **The property is tested at the process level.** `scripts/observe-check.sh`
   asserts that stdout is byte-identical with and without every verbosity flag,
   across every corpus and colour mode — 144 comparisons — and that stderr is
   empty in every default-verbosity run. This is a file-descriptor property; no
   unit test can express it, so it gets a process-level gate wired into CI.

## Alternatives considered

**Log to stdout with a marker prefix.** Rejected outright. `anuenue` is
specified as byte-transparent under `NO_COLOR` — the M6 acceptance criterion is
that `NO_COLOR=1 echo X | anuenue` is byte-identical to `echo X`. Anything on
fd 1 breaks that, and breaks every downstream consumer besides.

**Log to a file.** Rejected: breaches the capability bound. anuenue does no file
I/O, and `cat file | anuenue` is deliberately the whole file story. A log file
would also mean a path, which means path handling, which means a class of bugs
anuenue currently cannot have.

**A separate `--log-fd=N` flag.** Rejected as unearned generality. A caller who
wants the diagnostics elsewhere already has the shell: `anuenue -v 2>log`. Adding
a flag to accept an arbitrary descriptor would let a caller point diagnostics at
fd 1 and defeat the invariant this ADR exists to protect.

**Leave sakshi and agnostik unwired and drop them.** Rejected. They are the
canonical first-party crates; dropping them is a standards decision, not a
maintenance one, and "we never called it" is an argument for calling it.

**Verbosity as a repeat count (`-vvv`).** Deferred. cmdit supports repeat
counts, but a named level (`--log-level=trace`) is self-documenting in a script
and greppable in a shell history, and `-v` covers the interactive case. Revisit
if a consumer asks.

## Consequences

- `anuenue -v | anything` is exactly as safe as `anuenue | anything`. The
  guarantee is mechanical and CI-enforced, not a convention.
- Diagnostics are **O(1) in input size**: exactly 10 records whether the stream
  is 1 KB or 5 MB. Nothing in `src/observe.cyr` is called per byte or per
  cluster — the call sites are startup, dispatch, teardown and the error paths.
  The single addition inside the read loop is one accumulate of `n_read` per
  `read(2)`.
- At default verbosity the cost is a level comparison that short-circuits before
  any formatting. Measured: per-byte throughput unchanged across the v1.2.1 cut.
- One intentional change to default-verbosity behaviour: a failing filter now
  prints e.g. `anuenue: i/o error: read from stdin failed` to stderr where it
  previously printed nothing. Exit codes are unchanged. A pipe filter should be
  silent about success and never silent about failure.
- **Parse errors cannot be logged.** Observability is configured *from* parsed
  flags, so a `cmdit` parse failure happens before the level is known. Those
  paths keep their existing stderr wording. Accepted rather than solved: a
  pre-parse argv scan for `-v` would duplicate cmdit's tokenizer, which is
  exactly the duplication adopting cmdit at v1.1.4 removed.
- `src/observe.cyr` must depend on nothing from anuenue — only sakshi, agnostik
  and the stdlib. That is what lets it be included first so every other module
  can call `anuenue_fail` without an include cycle. The colour-reason codes live
  in `src/color.cyr` for the mirror-image reason: they need `ANUENUE_COLOR_*`.
  If a future change makes `observe.cyr` reach back into anuenue, the cycle
  returns.

## Implementation note — a `Str` coercion trap

`agnostik_err_new(kind, message: Str)` stores its message and
`agnostik_err_print` reads it back with `str_data` / `str_len`. On cyrius
6.5.35, a string literal is coerced to `Str` at a call site whose parameter is
typed `Str` — **but not in return-expression position**:

```
anuenue_fail(KIND, "literal");           # statement   -> coerced, prints
return anuenue_fail(KIND, "literal");    # return expr -> NOT coerced
```

Same function, same literal, same signature. Uncoerced, `str_data` loads the
first eight characters *as a pointer*, and every error prints its kind with an
empty message:

```
anuenue: invalid argument:
```

Every anuenue call site is a `return anuenue_fail(...)`, so all of them were in
the broken position — the first build of this feature would have shipped every
error message blank. `anuenue_fail` therefore takes an ordinary null-terminated
cstr and converts explicitly with `str_new`, which behaves the same in every
call position.

The general rule this leaves behind: **do not rely on implicit literal→`Str`
coercion across an anuenue function boundary.** Convert at the boundary.

It was caught by executing the path, not by reading it — which is the argument
for `scripts/observe-check.sh` asserting on the *content* of the error output
rather than only on the exit code.
