# 006 — Reading argv costs a file descriptor, and that shapes what is testable

`args_init()` (stdlib `lib/args.cyr`) reads `/proc/self/cmdline` to materialise
argv: `open(2)`, `read(2)`, `close(2)`. `main()` calls it before anything else,
and `cmdit_parse` depends on it.

This is already noted in `src/main.cyr`'s header as a capability-surface fact —
it is the one open/close in a program that is otherwise read/write/mmap/exit
(the colour auto-detection's `/proc/self/environ` read aside — see ADR 0001's
table).
What is *not* obvious is the consequence for testing.

## The consequence

**anuenue's CLI cannot be exercised under a file-descriptor limit.** Under
`prlimit --nofile=3` only the three inherited descriptors exist, so
`args_init()`'s `open` fails and `argc()` is 0.

Through v1.4.0 (cmdit 1.2.4) that parsed as an empty argv: no flag was seen and
the binary silently took the default path. Observed: `--log-level=debug` produced
*no output at all*. From v1.4.1 (cmdit 1.4.0) an `argc()` of 0 is
`CMDIT_ERR_ARGV`, and anuenue exits **1** with `could not read the full command
line` — loud, but still before anything after argv parsing runs. The same code
covers a command line over 2 MiB, which `args_init` cuts at its fixed buffer.
Both are gate 7 of `scripts/robustness-check.sh`.

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
