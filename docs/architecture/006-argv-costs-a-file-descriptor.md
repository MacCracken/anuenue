# 006 — Reading argv costs a file descriptor, and that shapes what is testable

`args_init()` (stdlib `lib/args.cyr`) reads `/proc/self/cmdline` to materialise
argv: `open(2)`, `read(2)`, `close(2)`. `main()` calls it before anything else,
and `cmdit_parse` depends on it.

This is already noted in `src/main.cyr`'s header as a capability-surface fact —
it is the one open/close in a program that is otherwise read/write/brk/exit.
What is *not* obvious is the consequence for testing.

## The consequence

**anuenue's CLI cannot be exercised under a file-descriptor limit.** Under
`prlimit --nofile=3` only the three inherited descriptors exist, so
`args_init()`'s `open` fails, argv comes back empty, no flag is parsed, and the
binary silently takes the default path. Observed: `--log-level=debug` produced
*no output at all*, because the flag was never seen.

That is why the 2026-05-22 audit's INFO 8 and 9 — the signalfd lifecycle and the
signal mask — sat unmeasured from v0.8.0 through v1.2.2. The obvious experiment
("run it under an fd limit so `signalfd(2)` fails") cannot reach the code under
test. And there is no limit that works: at `--nofile=4`, `args_init` opens fd 3,
closes it, and `signalfd` then gets fd 3 successfully.

## The way around it

`tests/probes/sigmask-probe.cyr` is a standalone binary that:

- calls **no** `args_init` and reads **no** file, so it needs only the three
  inherited descriptors — which leaves `signalfd(2)` as the first thing to ask
  for fd 3, and therefore the thing that fails; and
- observes the signal mask with `sigprocmask(SIG_BLOCK, <empty set>, &oldset)` —
  a pure query that changes nothing and needs no descriptor, where reading
  `/proc/self/status` would have needed a fourth.

`scripts/signal-check.sh` drives it under `prlimit --nofile=3`. That combination
is what finally measured INFO 8 and 9, and found B-01.

## The general rule

**Anything reachable only after argv parsing is unreachable under fd pressure.**
If a future invariant needs testing at the fd boundary, it needs a probe binary
that hard-codes its inputs rather than a CLI invocation — and the probe must
avoid `/proc` for the same reason.
