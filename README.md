# anuenue

> **ānuenue** — Hawaiian for *rainbow*. Stdin → stdout rainbow-tint pipe filter.
> The Cyrius-native `lolcat`.

Pure pipe-filter: no file I/O, no network, no fork/exec. Tints each grapheme cluster along an HSV cycle, emits ANSI escapes via [`darshana`](https://github.com/MacCracken/darshana), and gets out of the way.

## Quick Start

```sh
cyrius deps                                  # resolve sibling deps (darshana, sakshi, agnostik)
cyrius build src/main.cyr build/anuenue      # build (add CYRIUS_DCE=1 for release)
cyrius test                                  # [build].test + tests/*.tcyr
sh scripts/golden-check.sh                   # determinism + NO_COLOR equivalence
sh scripts/animate-smoke.sh                  # animation structural guard
cyrius fuzz                                  # five harnesses, ~1.35M assertions
```

## Usage

```sh
./build/anuenue AGNOS                          # positional-text: rainbow argv + exit (no pipe; agnos-friendly)
echo "AGNOS" | ./build/anuenue                 # one-shot rainbow tint (pipe filter)
echo "AGNOS" | ./build/anuenue -s 100          # deterministic seed (testing / scripts)
echo "AGNOS" | ./build/anuenue -p 13           # bigger phase step per character
echo "日本AGNOS" | ./build/anuenue             # UTF-8 grapheme-aware (one phase per glyph)
iam | ./build/anuenue                          # rainbow system-info splash
bnrmr "AGNOS" | ./build/anuenue                # rainbow banner
cat poem.txt | ./build/anuenue -a              # animated (-d <s> / -S <speed>)
NO_COLOR=1 echo "AGNOS" | ./build/anuenue      # byte-identical passthrough
./build/anuenue --color=256                    # quantize to xterm 256-cube
./build/anuenue --force-color | tee motd.ansi  # keep colour through a non-TTY pipe
./build/anuenue --version                      # anuenue 1.1.1
./build/anuenue --help                         # full flag surface
```

### Flags (v1.0 — frozen)

| Short | Long              | Arg      | Effect |
|-------|-------------------|----------|--------|
| `-h`  | `--help`          | —        | Usage to stderr, exit 0 |
| `-V`  | `--version`       | —        | `anuenue X.Y.Z\n` to stdout, exit 0 |
| `-p`  | `--freq <N>`      | int      | Phase step per cluster (default 7) |
| `-s`  | `--seed <N>`      | int      | Starting hue phase (deterministic) |
| `-F`  | `--offset <N>`    | int      | Additive phase offset (Ruby-lolcat compat) |
| `-a`  | `--animate`       | —        | Buffer input, repaint with phase shift per frame |
| `-d`  | `--duration <N>`  | int      | Animation duration in seconds (0 = until SIGINT) |
| `-S`  | `--speed <N>`     | int      | Animation phase advance per frame (default 1) |
| `-n`  | `--no-color`      | —        | Force MONO passthrough (byte-identical to `cat`) |
| `-C`  | `--force-color`   | —        | Emit colour even when stdout isn't a TTY |
| `-c`  | `--color <mode>`  | str      | `auto` / `24bit` / `256` / `16` / `none` |

**Colour-mode priority chain**: `--color` → `--no-color` → `NO_COLOR` env → stdout-not-TTY (unless `--force-color`) → `COLORTERM` → `TERM`.

### UTF-8 / grapheme behavior

Cycle advances per *cluster*, not per byte. CJK / combining diacritics / ZWJ emoji sequences / regional-indicator flag pairs all get one phase advance each. Invalid UTF-8 → graceful per-byte cycling (never panics, never over-reads). See [ADR 0003](docs/adr/0003-grapheme-cluster-cycling.md) for the practical-subset classifier design + the Hangul / Devanagari / tag-sequence trade-offs.

## Why a Cyrius-native lolcat?

`lolcat` exists in every Linux distro as a `gem install lolcat` / `apt install lolcat` afterthought. In AGNOS, the rainbow filter is **first-party** — sovereign-stack, no Ruby runtime, capability-bounded, UTF-8 grapheme-aware (a thing the Ruby implementation got wrong for years), pinned and dogfooded alongside the rest of the userland.

It's also the founder of the **pipe-decorator family** in AGNOS userland — stdin → stdout aesthetic / transform filters, distinct from the terminal-aesthetics quintet (`cmdrs` / `darshini` / `iam` / `bnrmr` / `hapi`) which produce their own output.

## Project Status

**v1.0.0 — GA.** Public API contract frozen for the v1.x line. The flag surface above, exit codes, capability surface, and output shape are stable; sandhi bumps within v1.x update internal helpers without breaking the contract. See [`docs/development/roadmap.md`](docs/development/roadmap.md) for the v1.0 acceptance scorecard and the post-v1.0 plan, and [`docs/development/state.md`](docs/development/state.md) for the live snapshot.

### Quality bar at v1.3.4

- **380** unit assertions across 51 groups (`cyrius test`)
- **10** golden fixture + equivalence checks (`scripts/golden-check.sh`)
- **17** animation structural assertions (`scripts/animate-smoke.sh`)
- **22** observability + pipe-purity checks (`scripts/observe-check.sh`), including
  stdout byte-equality across 144 corpus × colour-mode × verbosity combinations
- **11** robustness checks (`scripts/robustness-check.sh`): UTF-8 carry across the
  read-chunk boundary, byte preservation under malformed UTF-8 (all 256 byte
  values, overlongs, surrogates), argv at both i64 extremes
- **1,450,672** fuzz assertions per run across 6 harnesses (`cyrius fuzz`)
- **0** HIGH+ security audit findings open — four audits, latest
  [`docs/audit/2026-08-26-audit.md`](docs/audit/2026-08-26-audit.md)
- **14** PTY checks + **12** signal/pacing checks + **15** allocation-failure
  checks (`scripts/pty-check.sh`, `scripts/signal-check.sh`,
  `scripts/allocfail-check.sh` — the last runs every guarded `alloc` site under
  a genuinely exhausted heap)
- **Binary** tracked every release, **not capped** — the first-party dep surface
  sets the floor, and `CYRIUS_DCE=1` no longer removes anything on 6.5.x. See
  [`state.md` § Binary](docs/development/state.md#binary)
- **Perf**: 46.46 ns/byte ASCII no-LF (M5 acceptance ≤60 ns/byte)
- **0** `cyrius lint` warnings, 0 untracked deferrals

### Diagnostics

`-v` / `--verbose` and `--log-level=<off|fatal|error|warn|info|debug|trace>`
emit structured [sakshi](https://github.com/MacCracken/sakshi) records — resolved
config, the colour mode **and the branch that chose it**, the dispatch route,
byte counts, and an enclosing span with elapsed time. Failures carry
[agnostik](https://github.com/MacCracken/agnostik) error kinds and codes.

Everything goes to **stderr**. stdout carries the rainbow and nothing else at
every verbosity, so this holds byte-for-byte:

```sh
diff <(iam | anuenue) <(iam | anuenue -v 2>/dev/null)   # always empty
```

Logging is off by default — a pipe filter is silent until asked.

```
$ echo AGNOS | anuenue --color=24bit -v 2>&1 >/dev/null
[...] [ENTER] anuenue
[...] [DEBUG] anuenue version=anuenue 1.2.1
[...] [DEBUG] config phase-step=7
[...] [DEBUG] colour mode resolved mode=24bit
[...] [DEBUG] colour mode resolved reason=--color override
[...] [DEBUG] dispatch route=filter
[...] [INFO]  complete bytes-in=6
[...] [EXIT]  anuenue (270557ns)
```

### Dependencies (pinned for v1.x)

| Dep | Tag | Role |
|-----|-----|------|
| [`darshana`](https://github.com/MacCracken/darshana) | 1.0.0 | ANSI escape primitives (frozen v1.0 API) |
| [`cmdit`](https://github.com/MacCracken/cmdit) | 1.2.4 | CLI / argument parsing (getopt-long) |
| [`sakshi`](https://github.com/MacCracken/sakshi) | 2.4.11 | Errors / tracing (first-party-standards-required) |
| [`agnostik`](https://github.com/MacCracken/agnostik) | 1.5.1 | Shared Result / Error shapes |
| Cyrius toolchain | 6.5.35 | `cyrius.cyml [package].cyrius` |

## Documentation

- [`CLAUDE.md`](CLAUDE.md) — durable rules for working in this repo (Claude Code or human)
- [`docs/development/roadmap.md`](docs/development/roadmap.md) — milestones M0 → v1.0; post-v1.0 plan
- [`docs/development/state.md`](docs/development/state.md) — current state (volatile)
- [`docs/adr/`](docs/adr/) — architecture decision records (`0001` pipe-purity, `0002` HSV-inline, `0003` grapheme-cluster cycling, `0004` stderr-only observability)
- [`docs/guides/getting-started.md`](docs/guides/getting-started.md) — build / run / develop
- [`docs/guides/integrating-anuenue.md`](docs/guides/integrating-anuenue.md) — downstream-consumer integration manual
- [`docs/examples/`](docs/examples/) — eight runnable shell examples covering the full flag surface
- [`docs/audit/`](docs/audit/) — audit reports (v1.0 baseline 2026-05-22; latest P(-1) sweep 2026-08-25)
- [`docs/benchmarks.md`](docs/benchmarks.md) — per-byte overhead trend across releases
- [`CHANGELOG.md`](CHANGELOG.md) — release log (Keep a Changelog format)

## Standards

This project follows the AGNOS [First-Party Standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-standards.md) and [First-Party Documentation](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md). It is part of the [agnosticos](https://github.com/MacCracken/agnosticos) genesis-repo's userland.

## License

GPL-3.0-only
