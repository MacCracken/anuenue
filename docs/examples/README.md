# anuenue — runnable examples

Each script in this directory is a self-contained invocation of
anuenue exercising one slice of the public surface. They're
referenced from [`docs/guides/integrating-anuenue.md`](../guides/integrating-anuenue.md)
and from the v1.0 acceptance criterion *"every public symbol cited
from at least one example"*.

All scripts assume `anuenue` is on `$PATH`, or are run from the repo
root with `./build/anuenue` substituted (a one-line `ANUENUE=`
prefix at the top of each script makes this easy).

## Index

| Script | Surface exercised |
|--------|-------------------|
| [`01-hello-rainbow.sh`](01-hello-rainbow.sh) | Default invocation; the one-line first-touch |
| [`02-deterministic-seed.sh`](02-deterministic-seed.sh) | `-s` seed for byte-identical output (golden-test pattern) |
| [`03-utf8-clusters.sh`](03-utf8-clusters.sh) | UTF-8 cluster-aware cycling — `é`, CJK, ZWJ emoji, RI flags |
| [`04-motd-pipeline.sh`](04-motd-pipeline.sh) | Compose with banner / identity tools (`iam | anuenue` pattern) |
| [`05-color-mode-override.sh`](05-color-mode-override.sh) | `--color=24bit / 256 / 16 / none` palette quantisation |
| [`06-no-color.sh`](06-no-color.sh) | `NO_COLOR=1`, `--no-color`, `--color=none` → byte-identical passthrough |
| [`07-animation.sh`](07-animation.sh) | `-a` animation with duration + speed flags |
| [`08-force-color.sh`](08-force-color.sh) | `--force-color` keeps colour across a non-TTY pipe |
| [`09-diagnostics.sh`](09-diagnostics.sh) | `-v` / `--log-level` diagnostics on stderr; stdout byte-identical with and without |
| [`10-no-colour-span.sh`](10-no-colour-span.sh) | v1.5.0 no-colour spans: the APC marker pair, the producer's own colour kept, the phase pause, MONO consuming the markers |

## Conventions

- **Bourne-compatible shell.** Scripts use `#!/bin/sh` and POSIX
  constructs; they run under bash / zsh / agnoshi without
  modification.
- **No side effects.** Every script reads from `echo` / heredoc /
  built-in test fixture text — never from a file the user has to
  provide, never writes to a file the user has to clean up.
- **Self-documenting.** Each script's header comment cites the flag
  surface it touches and the expected visible behaviour.

## See also

- [`../guides/integrating-anuenue.md`](../guides/integrating-anuenue.md) — integration patterns.
- [`../adr/0001-pipe-purity.md`](../adr/0001-pipe-purity.md) — why the surface looks this way.
- [`../development/roadmap.md`](../development/roadmap.md) — v1.0 acceptance criteria.
