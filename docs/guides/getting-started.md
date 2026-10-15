# Getting started with anuenue

## Build

```sh
cyrius deps                                    # resolve deps (darshana, cmdit, agnostik; sakshi is stdlib)
cyrius build src/main.cyr build/anuenue        # compile (add CYRIUS_DCE=1 for release builds)
cyrius test                                    # run [build].test + tests/*.tcyr
cyrius bench tests/anuenue.bcyr                # hot-path micro-benchmarks
cyrius fuzz                                    # six fuzz harnesses (~1.45M assertions)
sh scripts/golden-check.sh                     # determinism + NO_COLOR equivalence
sh scripts/animate-smoke.sh                    # animation structural guard
sh scripts/robustness-check.sh                 # adversarial bytes / argv / descriptors
sh scripts/pty-check.sh                        # real pty: colour detection, sized-terminal animation
sh scripts/fault-check.sh                      # gdb fault injection + per-route syscall allowlist
sh scripts/perf-bench.sh                       # end-to-end per-byte overhead ratchet
```

## Run

anuenue is a pipe filter: stdin → tinted stdout. No file-input mode (use `cat file | anuenue`), no themes, no config file — pipe-purity is the design ([ADR 0001](../adr/0001-pipe-purity.md)).

```sh
echo "AGNOS" | ./build/anuenue                 # one-shot rainbow tint
echo "AGNOS" | ./build/anuenue -s 100          # deterministic output (-s seeds the hue)
echo "日本AGNOS" | ./build/anuenue              # UTF-8 cluster-aware (one phase per glyph)
echo "AGNOS" | ./build/anuenue --color=256     # quantize to xterm 256-cube
NO_COLOR=1 echo "AGNOS" | ./build/anuenue      # byte-identical passthrough (per no-color.org)
cat poem.txt | ./build/anuenue -a -d 5         # 5-second animation; Ctrl-C cleanly exits
iam | ./build/anuenue                          # MOTD pipeline composition
./build/anuenue --version                      # anuenue 1.0.0
./build/anuenue --help                         # full flag listing
```

### Flag surface (v1.0 — frozen)

| Short | Long              | Arg | Effect | Shipped at |
|-------|-------------------|-----|--------|------------|
| `-h`  | `--help`          | —   | Usage to stderr, exit 0 | M2 (v0.3.0) |
| `-V`  | `--version`       | —   | `anuenue X.Y.Z\n` to stdout, exit 0 | M2 |
| `-p`  | `--freq <N>`      | int | Phase step per cluster (default 7 — bigger = tighter rainbow) | M2 |
| `-s`  | `--seed <N>`      | int | Starting hue phase. Deterministic-output hook used by golden fixtures | M2 |
| `-F`  | `--offset <N>`    | int | Additive phase offset (Ruby-lolcat compat). `PHASE_START = seed + offset` | M2 |
| `-a`  | `--animate`       | —   | Buffer input once, repaint with phase shifted per frame (~60 fps) | M4 (v0.5.0) |
| `-d`  | `--duration <N>`  | int | Animation duration in seconds (default 5; 0 = until SIGINT) | M4 |
| `-S`  | `--speed <N>`     | int | Animation phase advance per frame (default 1) | M4 |
| `-n`  | `--no-color`      | —   | Force MONO passthrough (byte-identical to `cat`) | M6 (v0.7.0) |
| `-C`  | `--force-color`   | —   | Emit colour even when stdout isn't a TTY | M6 |
| `-c`  | `--color <mode>`  | str | `auto` / `24bit` (alias `truecolor`) / `256` / `16` / `none` (alias `off`/`never`) | M6 |

`-s` and `-F` are **additive** so they compose without precedence surprises. Bad / unknown / missing-value flags exit 2 with a specific message followed by usage.

#### Colour-mode priority chain (M6+)

Highest priority first:

1. `--color <mode>` explicit override
2. `--no-color` flag
3. `NO_COLOR` env var (any value — presence is the signal, per [no-color.org](https://no-color.org))
4. stdout-not-a-TTY → MONO, **unless** `--force-color` is set
5. `COLORTERM=truecolor` or `=24bit` → TRUECOLOR
6. `TERM=*-direct` → TRUECOLOR; `TERM=*256color` → COLOR_256
7. Fallback on a TTY: COLOR_16

### Grapheme behavior (M3+)

Phase advances **per grapheme cluster**, not per byte. Practical effect:

- CJK / Cyrillic / Hebrew / Arabic codepoints: one phase advance per glyph
- `é` written as base `e` + combining acute (U+0301): one phase advance
- Emoji ZWJ sequences (`👨‍👩‍👧`): one phase advance for the whole family
- Regional-indicator pairs (`🇺🇸`): one phase advance for the flag
- Invalid UTF-8: graceful per-byte cycling (never panics, never over-reads)

See [ADR 0003](../adr/0003-grapheme-cluster-cycling.md) for the practical-subset classifier and the documented trade vs full UAX #29 (Hangul L/V/T, Devanagari spacing marks, tag sequences accepted as over-segmented).

## Layout

- `src/main.cyr` — entry point. `var r = main(); syscall(SYS_EXIT, r);` at top level. argv → flag parse → colour-mode detect → filter / animate / passthrough dispatch.
- `src/hsv.cyr` — `ANUENUE_PHASE_MOD` + `hsv_rainbow(phase, out_rgb)` — integer 6-sector HSV→RGB ([ADR 0002](../adr/0002-hsv-inline-not-abaco.md)).
- `src/filter.cyr` — the M1/M3/M5 streaming filter: `anuenue_filter()`, UTF-8 primitives (`utf8_seq_len`, `utf8_decode`), cluster classifier (`cp_is_extending` binary-searched LUT, `cp_is_regional_indicator`), the M5 phase-cached escape table (`_phase_esc_init`, `_emit_phase_esc`).
- `src/animate.cyr` — M4 animation: `anuenue_animate()`, cluster pre-tag (`_pretag_clusters`), frame renderer (`_render_frame`), signalfd cursor-restore handling.
- `src/color.cyr` — M6 colour-mode negotiation: enum, override-string parser, RGB quantizers (`_channel_to_6` / `_rgb_to_256` / `_rgb_to_16`), `anuenue_detect_color_mode`, `anuenue_passthrough` (MONO bypass).
- `src/version_str.cyr` — **auto-generated** by `scripts/version-bump.sh`. Never hand-edit.
- `src/test.cyr` — top-level test-entry stub. Real assertions live in `tests/anuenue.tcyr`.
- `tests/anuenue.tcyr` — primary test suite (`cyrius test` auto-discovers).
- `tests/anuenue.bcyr` — benchmarks (`cyrius bench`).
- `tests/golden/*.out` — committed byte-identical fixtures asserted by `scripts/golden-check.sh` + CI.
- `fuzz/*.fcyr` — five harnesses (`cyrius fuzz`): flag parser, UTF-8 surface, `_pretag_clusters`, `_emit_phase_esc`, RGB quantizers.

## Adding a feature

1. Edit the relevant `src/*.cyr` file (filter / animate / color / hsv as appropriate).
2. Add a test case to `tests/anuenue.tcyr`. If the change affects observable output, add a golden fixture under `tests/golden/` and a matching `check_golden` call in `scripts/golden-check.sh`.
3. If the change adds adversarial surface, extend or add a `fuzz/*.fcyr` harness.
4. Run `cyrius test && sh scripts/golden-check.sh && sh scripts/animate-smoke.sh && cyrius fuzz`.
5. If perf-relevant: `sh scripts/perf-bench.sh` and update `docs/benchmarks.md`.
6. CHANGELOG entry in `[Unreleased]`. Version bump (`sh scripts/version-bump.sh X.Y.Z`) happens at cycle close — see CLAUDE.md.

See [`../adr/template.md`](../adr/template.md) when a non-trivial design choice deserves an ADR.

**Post-v1.0 constraint**: the documented flag surface above is frozen for v1.x. Breaking changes earn a v2.0 bump. Sandhi bumps within v1.x can change internal helpers (e.g. swapping a darshana helper) but not the user-visible contract.

## Releasing

Cycle close is user-driven:

1. CHANGELOG `[Unreleased]` body → moved into `[X.Y.Z] — YYYY-MM-DD` section.
2. `sh scripts/version-bump.sh X.Y.Z` (updates VERSION, regenerates `src/version_str.cyr`, inserts CHANGELOG header).
3. `docs/development/state.md` — refresh Version row narrative + Binary row size.
4. Closeout-pass per CLAUDE.md (clean rebuild, tests, lint, goldens, animate-smoke, fuzz, perf-bench, version consistency).
5. User commits + tags `X.Y.Z` + pushes — `.github/workflows/release.yml` runs the version-verify gate and ships artifacts.
