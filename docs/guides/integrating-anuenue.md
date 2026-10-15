# Integrating anuenue into AGNOS pipelines

This guide is for developers wiring anuenue into something else —
the MOTD chain, a banner tool, a TUI splash, a CI log decorator.
For "how do I run anuenue at the shell", see
[`getting-started.md`](getting-started.md).

anuenue is a **pure pipe filter**: stdin → tinted stdout. The
contract is small, which makes it easy to compose but also means
every integrator needs to know the same handful of invariants. This
guide lists them.

> Audience: AGNOS userland tool authors (iam, bnrmr, agnoshi, etc).
> Outside-AGNOS users see the same surface; the MOTD-pipeline
> examples just happen to be the dominant use case.

## The contract

| Surface | Behaviour |
|---------|-----------|
| **Input** | Single stdin stream. Treated as untrusted bytes. UTF-8 is decoded, invalid sequences degrade gracefully per byte. |
| **Output** | Single stdout stream. ANSI SGR foreground codes interspersed with the original bytes — *no* bold / italic / underline injection (per [ADR 0001](../adr/0001-pipe-purity.md)). |
| **Errors** | All diagnostic text (usage, error messages) goes to stderr. The stdout stream is colourised input only — never polluted. |
| **Exit codes** | `0` normal exit (incl. `--help` / `--version`); `1` runtime error (read error, alloc fail, and from v1.4.1 a command line that could not be read whole — over 2 MiB, or no descriptor for `/proc/self/cmdline`); `2` usage error (unknown flag, bad int value, and from v1.4.1 a boolean given `=value`). |
| **State** | None on disk. No config file, no cache, no log. Re-running with the same flags + stdin produces byte-identical output (deterministic with `-s`). |
| **Concurrency** | Safe to invoke from any number of pipelines simultaneously. No shared state, no lockfile, no inter-process coordination. |

## Capability surface

If you're wiring anuenue into a sandboxed context, here is the
exact set of syscalls it makes (see [ADR 0001](../adr/0001-pipe-purity.md)
for the full reasoning):

```
read(0,  …)        # stdin
write(1, …)        # stdout
write(2, …)        # stderr  (only on --help / --version / errors)
brk(12, …)         # bump allocator (read buffer + line buffer)
open / close       # bounded — /proc/self/cmdline + /proc/self/environ
ioctl(TIOCGWINSZ)  # via darshana's tty_isatty
exit(60, …)
```

Animation mode (`-a`) additionally uses `rt_sigprocmask`, `signalfd4`,
`fcntl` (to make that signalfd non-blocking) and `close` for the
SIGINT cursor-restore, plus `poll` (`sleep_ms`) and `clock_gettime`
for the frame loop. `fcntl` and `close` are new at v1.4.0, when the
signalfd moved onto darshana's `tty_open_signalfd` /
`tty_close_signalfd` — a seccomp allowlist written for v1.3.x needs
both added. (Earlier versions of this list said `nanosleep`; the
stdlib's `sleep_ms` has been `poll(NULL, 0, ms)` since cyrius 6.0.65.)
The non-animation path is the smaller set above.

No `connect`, no `fork`, no `execve`, no `unlink`. anuenue cannot
escape its pipe.

## TTY detection and the colour-mode chain

anuenue auto-detects the right colour mode at startup. The
priority chain (M6 / v0.7.0; see
[`src/color.cyr`](../../src/color.cyr) `anuenue_detect_color_mode`):

1. **`--color <mode>`** explicit override wins. Modes: `auto` (the
   default), `24bit` (or `truecolor`), `256`, `16`, `none` (alias
   for `mono`).
2. **`--no-color`** forces MONO. Highest-priority disable; beats
   environment.
3. **`NO_COLOR` env var** (per [no-color.org](https://no-color.org))
   forces MONO. Honoured even when stdout is a TTY.
4. **stdout-not-a-TTY** → MONO, unless `--force-color` is set. This
   is what makes `anuenue | tee` and `anuenue | less -R` work
   correctly: `tee` gets clean text, `less -R` (if explicit) gets
   colour via `--force-color`.
5. **`COLORTERM=truecolor` or `=24bit`** → TRUECOLOR.
6. **`TERM` heuristics** → COLOR_256 (for `*-256color`) or COLOR_16
   (default fallback).

### MONO is a passthrough

`ANUENUE_COLOR_MODE == MONO` short-circuits the entire filter
pipeline. anuenue copies stdin to stdout unchanged — *byte-
identical* to `cat`. This is asserted by three goldens in
`scripts/golden-check.sh` (`NO_COLOR=1`, `--no-color`,
`--color=none`).

Practical consequence for integrators: **always invoke anuenue with
`NO_COLOR` already in the environment if you want guaranteed plain
output**. Don't rely on argv parsing to "win" against env-var
detection — they're both correct exits; just pick one.

## Composing into MOTD pipelines

The dominant use case. Pattern:

```sh
iam | anuenue              # default rainbow on user identity banner
bnrmr "AGNOS" | anuenue    # ascii-art banner, rainbow-tinted
agnoshi-motd | anuenue     # full MOTD chain
```

anuenue is **the last stage**. Putting it earlier means downstream
tools see SGR escapes mixed into their input, which most banner /
boxes / cowsay-shaped tools don't handle. If your tool wants to
*read* a banner *then* tint it, you're the producer and anuenue is
your consumer.

### Determinism

Pass `-s <int>` for byte-identical output across runs. Used by the
golden test harness; also useful for any consumer that wants a
*specific* colour rotation rather than a randomised one.

```sh
echo "AGNOS" | anuenue -s 100   # always emits the same bytes
```

If you don't pass `-s`, the starting phase is `0` (deterministic by
default — no randomness anywhere in anuenue). The roadmap considered
auto-seeding from `time(2)` and rejected it: pipe-purity rules out
the syscall, and a tool that owns the rainbow on every login should
behave reproducibly.

### Phase step (`-p`)

Higher values = tighter rainbow (more hue advance per character).
Default is 7, which is calibrated so a typical MOTD line covers ~1/3
of the rainbow. Boost to `-p 20` for very short banners; drop to
`-p 3` for long ASCII art where the default would loop multiple
times.

### Animation (`-a`)

`-a` buffers stdin once (cap: 65 536 bytes — see
[ADR 0001](../adr/0001-pipe-purity.md) for why), then redraws the
buffered frame with a phase shift every 16 ms (~60 fps) for the
duration window. `-d N` sets the duration in seconds (default 5,
`0` for "until Ctrl-C"); `-S N` sets the phase advance per frame
(default 1).

```sh
cat poem.txt | anuenue -a -d 10           # 10 s animation
fortune | anuenue -a -d 0                 # until Ctrl-C
```

Integrators wiring this into a MOTD chain should be aware:

- **Animation requires a TTY.** If stdout isn't a TTY, the M6 chain
  routes to MONO (passthrough) — no animation, no escapes. Override
  with `--force-color` if needed (rare).
- **64 KB input cap.** Inputs larger than the cap truncate. The non-
  animated path has no cap.
- **SIGINT is signal-safe.** Ctrl-C unwinds via the signalfd probe
  between frames and emits the cursor-show / SGR-reset epilogue.
  Don't wrap `anuenue -a` in a shell loop that traps SIGINT
  expecting to "catch" it before anuenue does — while it animates,
  anuenue blocks HUP/INT/TERM and reads them from a signalfd (no
  handler is installed), then restores the signal mask it started
  with on the way out.

## What anuenue does NOT do

These are not bugs — they're scope decisions ([ADR 0001](../adr/0001-pipe-purity.md)):

- **No file-input mode.** `anuenue file.txt` is *not* supported.
  Use `cat file.txt | anuenue`.
- **No config file.** No `~/.anuenue.cyml`, no `$XDG_CONFIG_HOME/anuenue/`.
  Persistent flags belong in shell aliases.
- **No theme system.** The rainbow is the brand. If post-1.0 we add
  alternate palettes, it'll be a flag with a bounded enum, not a
  user-editable palette file.
- **No bold / italic / underline.** ANSI fg only.
- **No image input.** Wrong domain — anuenue is for terminal text.

## End-to-end example: wiring a new tool

Say you're writing `awesomesplash` and want it to participate in
the rainbow-tinted MOTD chain. Three integration patterns:

### Pattern A — emit plain, pipe through anuenue

```sh
# Your tool emits plain UTF-8 to stdout
awesomesplash | anuenue -p 5
```

This is the recommended pattern. Your tool stays simple and
pipe-pure itself; the rainbow is composed downstream.

### Pattern B — let the user choose

```sh
# In your tool's wrapper script:
awesomesplash | ${RAINBOW:-cat}
```

User exports `RAINBOW=anuenue` to opt in. Default is `cat`
(passthrough). Works in any shell that supports `${VAR:-default}`.

### Pattern C — direct invocation from a Cyrius program

If you're calling anuenue programmatically rather than from a
shell, the pattern is `fork` + `execve` of the anuenue binary with
the desired argv, piping your output into its stdin via the
standard `pipe(2)` + `dup2(2)` dance. anuenue itself never forks
(see Capability surface above); your tool owns the lifecycle.

## Testing your integration

Two patterns from anuenue's own test harness that integrators can
copy:

### Determinism golden

```sh
echo "your-banner-text" | anuenue -s 100 > expected.out
# … in CI:
echo "your-banner-text" | anuenue -s 100 | diff - expected.out
```

The `-s 100` seed locks the colour rotation; the diff catches any
regression in your producer.

### NO_COLOR equivalence

```sh
# Your tool's output should pass through NO_COLOR unchanged:
diff <(yourtool) <(yourtool | NO_COLOR=1 anuenue)
```

If the diff has anything, something in the chain is emitting
escapes despite NO_COLOR — and it isn't anuenue.

## See also

- [`getting-started.md`](getting-started.md) — build, run, test, basic flags.
- [ADR 0001 — Pipe-purity](../adr/0001-pipe-purity.md) — full reasoning.
- [ADR 0002 — HSV inline](../adr/0002-hsv-inline-not-abaco.md) — why no abaco dep.
- [ADR 0003 — Grapheme-cluster cycling](../adr/0003-grapheme-cluster-cycling.md) — UTF-8 correctness model.
- [`docs/examples/`](../examples/) — runnable invocations.
- [`docs/development/roadmap.md`](../development/roadmap.md) — v1.0 acceptance criteria.
