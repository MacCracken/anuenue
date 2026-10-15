# 0001 — Pipe-purity: no file I/O, no config, no themes

**Status**: Accepted
**Date**: 2026-05-22

## Context

`lolcat` (Ruby, 2014) and its C / Rust descendants ship a tool that grew
organically: a stdin → stdout rainbow filter that also reads files
positionally on argv, sources `~/.lolcatrc`, supports custom palettes
through plugins, and (in some forks) auto-detects images. The result is
a tool that's hard to compose, hard to audit, and hard to reason about
under capability-bounded execution.

anuenue is the AGNOS userland's rainbow tool. AGNOS first-party
standards demand a small, auditable capability surface for every binary
on the boot path. anuenue sits in the **MOTD pipeline** — `iam |
anuenue`, `bnrmr "AGNOS" | anuenue` — which is exercised on every
interactive login. The genesis-repo principle, repeated in
[CLAUDE.md](../../CLAUDE.md) under *Key Principles*, is **pipe-purity**:
*no buffering beyond a line in non-animated mode; pure byte streaming.
No file I/O. No network. No state on disk.*

We need an explicit decision record because (a) every lolcat-shaped
predecessor took the opposite path, and (b) anuenue is the **founder of
the pipe-decorator family** (see [shared-crates.md § Pipe-decorator
family](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md)).
What ships here becomes the template for `boxes`-, `cowsay`-, `pv`-
shaped sibling tools that will come later.

## Decision

**anuenue accepts input from stdin only and emits to stdout only.** The
on-disk surface is the binary itself + the auto-generated
`src/version_str.cyr`; the runtime surface is stdin, stdout, stderr, and
argv. There is no file-input mode, no config file, no plugin loader, no
theme system, no palette beyond the integer HSV rainbow, and no output
styles beyond ANSI foreground colour.

Concretely, this means anuenue's capability surface is:

| Syscall                  | Why                                                          |
|--------------------------|--------------------------------------------------------------|
| `read(0, …)`             | stdin — the only input source                                |
| `write(1, …)`            | stdout — the only "real" output                              |
| `write(2, …)`            | stderr — usage / errors (only on `--help` / `--version` / parse failure) |
| `mmap(9)`                | the heap — one anonymous chunk at startup, the stdlib allocator's (backs the read buffer + line buffer) |
| `exit(60)`               | program termination                                          |
| `open(2)` + `close(3)`   | **bounded** — only `/proc/self/cmdline` (argv parse, every run) and `/proc/self/environ` (NO_COLOR / COLORTERM / TERM, only when colour is auto-detected) |
| `ioctl(16, TIOCGWINSZ)`  | TTY probe via darshana's `tty_isatty` (auto-detection only); in animation, the terminal's size (v1.4.4, ADR 0005) |
| `rt_sigprocmask` / `signalfd4` / `fcntl` / `close` / `poll` / `clock_gettime` | animation mode only — the exit signalfd, frame pacing (`sleep_ms` is `poll(NULL, 0, ms)`) and the deadline |
| `poll(7)` on fd 0 / 1    | only when a caller hands anuenue a non-blocking stdin or stdout and the peer stalls — waiting instead of retrying (v1.4.4, H-02) |
| `clock_gettime` / `nanosleep` | `-v` / `--log-level` only — sakshi's timestamps and its one-time clock calibration |

*Re-measured at v1.4.4* by catching every syscall of each route under gdb
(the harness behind `scripts/fault-check.sh`). Until then this table listed
`brk(12)` for the heap — true when it was written, but the stdlib allocator
has used anonymous `mmap` chunks since cyrius 6.1.19, and no route issues
`brk` at all (H-03 in the [v1.4.x audit delta](../audit/2026-10-14-v14x-delta.md)).
It also omitted animation's `fcntl`, `poll` and `clock_gettime`.

No `connect`, no `fork`, no `execve`, no `unlink`, no `mkdir`, no
`socket`, no `mmap` of user-supplied paths. Anything beyond the above
list is a bug — both auditable and easy to grep for.

### Deliberate exceptions (and why they're not violations)

Two features of the v0.5.0–v0.7.0 surface buffer more than a single
line:

1. **Animation mode (M4, v0.5.0)** slurps stdin once into a heap buffer
   capped at `ANUENUE_ANIMATE_INPUT_MAX = 65 536` bytes
   (`src/animate.cyr:35`) before entering the frame loop. The buffer
   ceiling is bounded; the loop doesn't reread stdin between frames;
   nothing touches disk. This is *not* a violation of pipe-purity — the
   stdin → stdout invariant holds — but it is a relaxation of the
   "byte-stream, never buffer the full payload" reading that the M1
   filter loop satisfies. The cap is the contract: input larger than
   64 KB falls back to truncated animation, not unbounded memory growth.

2. **MONO passthrough (M6, v0.7.0)** in `anuenue_passthrough`
   (`src/color.cyr:189`) bypasses the filter loop entirely: a tight
   `read(0) → write(1)` shuttle that emits the exact stdin bytes when
   the colour-mode chain resolves to monochrome (`--no-color`,
   `NO_COLOR=1`, stdout-not-TTY, etc). This is *more* pipe-pure than
   the filter — no escape generation, no per-character work — but it's
   a distinct code path that has to be kept in sync with the filter's
   capability surface (it shares the same `read` / `write` / `mmap` /
   `exit` set).

Both exceptions are caught by `tests/anuenue.tcyr` (animation buffer
bounds; MONO byte-identity goldens) and CI's `scripts/animate-smoke.sh`
+ the three `golden-check.sh` NO_COLOR equivalence assertions.

## Consequences

### Positive

- **Composes into any shell pipeline** without surprises. `cmd |
  anuenue | tee log.txt | less -R` works because anuenue makes no
  assumptions about what's upstream or downstream.
- **Auditable in one afternoon.** The whole capability surface fits in
  a table. Security audit (M8) reduces to "grep for any syscall outside
  the table".
- **Capability-bounded.** anuenue can be sandboxed with the tightest
  possible seccomp filter — no `open` on user-controlled paths, no
  network, no fork/exec. Future AGNOS sandboxing work gets this for
  free.
- **Reproducible.** No `~/.anuenue.cyml` means a user's MOTD looks the
  same on every host. The `-s` seed flag is the *entire* determinism
  story.
- **Sets the template** for sibling pipe-decorators. The next tool in
  the family inherits the same shape: stdin → stdout, no state, small
  capability set.

### Negative

- **No "anuenue file.txt" convenience.** Users have to write `cat
  file.txt | anuenue` instead. This is a documented friction
  point — see [`docs/guides/integrating-anuenue.md`](../guides/integrating-anuenue.md).
- **No themes / palettes.** Users who want a non-rainbow gradient have
  to fork. We consider this part of the brand: anuenue is *the
  rainbow*, not *a recolouriser*.
- **No `~/.anuenue.cyml`.** Users who want persistent flags use shell
  aliases instead (`alias anuenue='anuenue -p 5'`). This is the same
  trade `cat` and `tr` make.
- **64 KB animation cap.** Large inputs (`tail -1000 /var/log/big.log
  | anuenue -a`) truncate the animation frame. The non-animated path
  has no such limit.

### Neutral

- ADRs 0002 (HSV inline) and 0003 (grapheme-cluster cycling) inherit
  the pipe-purity constraint as a hard input. Anything those decisions
  considered that would have required file I/O or config (a generated
  Unicode table loaded from disk; an abaco-dispatched palette pulled
  from a config) was ruled out at this layer.
- Future tools in the pipe-decorator family will inherit this ADR as a
  reference. The boilerplate "we don't do file I/O" section in their
  ADR-0001 can cite this one.

## Alternatives considered

- **lolcat-shaped surface (file arg + ~/.lolcatrc + plugins).**
  Rejected: violates the capability bound, makes MOTD-pipeline auditing
  much harder, and introduces a config-file format we'd then own in
  perpetuity. The MOTD chain is the dominant use case; optimising for
  it means optimising for pipe-purity.
- **File-input mode without config.** Considered (it's the smallest
  step away from pipe-purity). Rejected because `cat file | anuenue`
  is a 4-character ergonomics tax for a fundamental capability-surface
  change. Once we accept `open()` on argv-supplied paths, every
  security review has to argue about path-traversal, symlink races,
  TOCTOU. Better to never accept the first byte.
- **Theme system via env var (`ANUENUE_PALETTE=...`).** Rejected:
  starts a slippery slope toward a config format. The HSV rainbow is
  the brand. If a future palette ships, it ships post-1.0 as a flag
  with bounded enum values, not free-form config.
- **No animation mode, ever.** Considered for M4 in service of
  "strictest pipe-purity". Rejected: animation parity with `lolcat -a`
  is a v1.0 acceptance criterion in the roadmap. The 64 KB cap is the
  compromise that preserves the spirit (bounded, no disk, no state)
  while delivering the user-visible feature.
