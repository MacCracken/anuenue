# anuenue — Claude Code Instructions

> **Template**: filled from [example_claude.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/example_claude.md). Reference implementation: [cyrius/CLAUDE.md](https://github.com/MacCracken/cyrius/blob/main/CLAUDE.md). Structure per [first-party-documentation § CLAUDE.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md#claudemd).
>
> **Core rule**: this file is **preferences, process, and procedures** — durable rules that change rarely. Volatile state (current version, binary size, test count, in-flight work, consumers, verification hosts) lives in [`docs/development/state.md`](docs/development/state.md), bumped every release.

---

## Project Identity

**anuenue** (Hawaiian: ānuenue — *rainbow*) — Cyrius-native rainbow-tint pipe filter. Stdin → stdout per-character HSV cycling. The AGNOS-side `lolcat`.

- **Type**: Binary (pure pipe filter — composes into any shell pipeline)
- **License**: GPL-3.0-only
- **Language**: Cyrius (toolchain pinned in `cyrius.cyml [package].cyrius` — that field is the only source of truth; the current value and its history live in [`docs/development/state.md`](docs/development/state.md#toolchain), never inlined here)
- **Version**: `VERSION` at the project root is the source of truth — do not inline the number here
- **Genesis repo**: [agnosticos](https://github.com/MacCracken/agnosticos)
- **Family**: founder of the **pipe-decorator family** (stdin → stdout aesthetic / transform filters) — see [shared-crates.md § Pipe-decorator family](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md)
- **Standards**: [First-Party Standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-standards.md) · [First-Party Documentation](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md)
- **Shared crates registry**: [shared-crates.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md)

## Goal

Own the rainbow pipe-filter slot in AGNOS userland. Pure stdin → stdout transform, capability-bounded (no file I/O, no network, no state), composable into MOTD pipelines (`iam | anuenue`, `bnrmr "AGNOS" | anuenue`). darshana owns the ANSI substrate; anuenue owns the HSV phase model and the per-character cycle policy.

## Current State

> Volatile state lives in [`docs/development/state.md`](docs/development/state.md) —
> current version, binary size, test/assertion count, dep pins, in-flight slots,
> consumers, verification hosts. Refreshed every release.
>
> Historical release narrative lives in [`CHANGELOG.md`](CHANGELOG.md).

This file (`CLAUDE.md`) is durable rules.

## Scaffolding

Project was scaffolded with `cyrius init anuenue` on 2026-05-21. **Do not manually create project structure** — use the tools. If a tool is missing something, fix the tool.

## Quick Start

```sh
cyrius deps                              # resolve sibling deps (darshana, sakshi, agnostik)
cyrius build src/main.cyr build/anuenue  # build
cyrius test                              # [build].test + tests/*.tcyr
cyrius bench tests/anuenue.bcyr          # benchmarks
cyrius lint src/*.cyr                    # static checks
CYRIUS_DCE=1 cyrius build ...            # DCE release build

# Usage:
echo "AGNOS" | ./build/anuenue           # one-shot tint
iam | ./build/anuenue                    # MOTD pipeline
./build/anuenue -a < poem.txt            # animated mode
echo "AGNOS" | ./build/anuenue -v        # diagnostics on stderr (stdout unchanged)
```

## Key Principles

- **Correctness over cleverness** — if it's wrong, the bugs own you
- **Pipe-purity** — no buffering beyond a line in non-animated mode; pure byte streaming. No file I/O. No network. No state on disk.
- **Capability-bounded** — anuenue's surface is stdin/stdout/stderr + argv. That's it. No `open()`. No `connect()`. No fork/exec.
- **Own the HSV phase model** — darshana emits the ANSI; anuenue owns the *what color, when* logic
- **UTF-8 awareness** — count grapheme clusters not bytes when cycling color phase (Ruby lolcat had bugs here historically; AGNOS gets it right from day one)
- Test after EVERY change, not after the feature is "done"
- ONE change at a time — never bundle unrelated changes
- Programs call `main()` at top level: `var exit_code = main(); syscall(60, exit_code);`
- Build with `cyrius build`, never raw `cat file | cycc` — the manifest auto-resolves deps and prepends includes
- Every buffer declaration is a contract: `var buf[N]` = N **bytes**, not N entries
- Benchmark before claiming perf — anuenue is in the hot path of every MOTD; per-character overhead matters

## Rules (Hard Constraints)

- **Read the genesis repo's CLAUDE.md first** — [agnosticos/CLAUDE.md](https://github.com/MacCracken/agnosticos/blob/main/CLAUDE.md)
- **Do not commit or push** — the user handles all git operations
- **NEVER use `gh` CLI** — use `curl` to the GitHub API if needed
- Do not add unnecessary dependencies — anuenue's surface is tiny; resist crate creep
- Do not implement ANSI escape generation inline — that belongs in darshana
- Do not implement file I/O paths — anuenue is a pipe filter; `cat file | anuenue` is the file-reading story
- Do not skip tests before claiming changes work
- Do not skip benchmark verification before claiming a perf change
- Do not use `sys_system()` with unsanitized input — command injection risk
- Do not trust external data (stdin bytes, argv) without validation
- Do not use `break` in while loops with `var` declarations — use flag + `continue`
- Do not add Cyrius stdlib includes in individual src files — the manifest resolves them
- Do not hardcode toolchain versions in CI YAML — the `cyrius = "X.Y.Z"` pin in `cyrius.cyml` is the only source of truth
- Do not hand-roll the toolchain install in CI — pipe the pin to the upstream `scripts/install.sh`. Untarring into `$HOME/.cyrius/{bin,lib}` is the pre-6.5 layout and `cyrius deps` hard-fails on it from 6.5.x
- Do not write diagnostics to stdout, ever — anuenue is a pipe filter. See [ADR 0004](docs/adr/0004-stderr-only-observability.md)

## Process

### P(-1): Hardening (before any new features, and at minor / v1.0 cuts)

1. **Cleanliness** — `cyrius build`, `cyrius lint`, `cyrius audit`; all tests pass
2. **Benchmark baseline** — `cyrius bench`, save CSV for comparison
3. **Internal deep review** — gaps, optimizations, correctness, docs
4. **External research** — domain completeness (other lolcat impls — busyloop, lolcat-c, lolcrab), CVE patterns
5. **Security audit** — input handling, syscall usage, buffer sizes, pointer validation. File findings in `docs/audit/YYYY-MM-DD-audit.md`
6. **Additional tests / benchmarks** from findings
7. **Post-review benchmarks** — prove the wins against step 2
8. **Documentation audit** — ADRs for decisions, source citations (HSV→RGB algorithm), guides for the public CLI surface
9. **Repeat if heavy** — keep drilling until clean

### Work Loop (continuous)

1. **Work phase** — features, roadmap items, bug fixes
2. **Build check** — `cyrius build`
3. **Test + benchmark additions** for new code
4. **Internal review** — performance, memory, correctness, edge cases
5. **Security check** — any new syscall usage, user input handling, buffer allocation
6. **Documentation** — update CHANGELOG, roadmap, `docs/development/state.md`, any ADR the change earned
7. **Version check** — `VERSION`, `cyrius.cyml`, CHANGELOG header in sync
8. **Return to step 1**

### Security Hardening (before every release)

Every project runs a security audit pass before release — see [first-party-standards § Security Hardening](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-standards.md#security-hardening-required-before-every-release) for the full list. anuenue-specific minimum:

1. **Input validation** — argv flags validated; stdin bytes treated as untrusted
2. **Buffer safety** — every `var buf[N]` verified; N is **bytes**; line-buffer is bounded
3. **Syscall review** — read/write/exit only; no surprise syscalls
4. **No command injection** — anuenue never `exec()`s anything; verify this stays true
5. **UTF-8 robustness** — invalid byte sequences must not panic, must not over-read

### Closeout Pass (before every minor/major bump)

Run a closeout pass before tagging `X.Y.0` or `X.0.0`. Ship as the last patch of the current minor.

1. **Full test suite** — `cyrius test` passes, zero failures
2. **Benchmark baseline** — `cyrius bench`, save CSV; compare against prior closeout
3. **Dead code audit** — remove unused functions; record remaining floor in CHANGELOG
4. **Refactor pass** — consolidate the minor's additions
5. **Code review pass** — walk diffs end-to-end for missed guards, off-by-ones, silently-ignored errors
6. **Cleanup sweep** — stale comments, dead branches, unused includes, orphaned files
7. **Security re-scan** — quick grep for new `sys_system`, unchecked writes, unsanitized input
8. **Downstream check** — listed consumers in `state.md` still build green against the new version
9. **Doc sync** — CHANGELOG, roadmap, `docs/development/state.md`, CLAUDE.md (if durable content changed)
10. **Version verify** — `VERSION`, `cyrius.cyml`, CHANGELOG header, intended git tag all match
11. **Full build from clean** — `rm -rf build && cyrius deps && CYRIUS_DCE=1 cyrius build` passes

### Task Sizing

- **Low/Medium effort**: batch freely — multiple items per work loop cycle
- **Large effort**: small bites only — break into sub-tasks, verify each before moving to the next
- **If unsure**: treat it as large

### Refactoring Policy

- Refactor when the code tells you to — duplication, unclear boundaries, measured bottlenecks
- Never refactor speculatively. Wait for the third instance
- Every refactor must pass the same test + bench gates as new code
- 3 failed attempts = defer and document — don't burn time in a rabbit hole

## Cyrius Conventions

- All struct fields are 8 bytes (`i64`), accessed via `load64` / `store64` with offset
- Heap allocation via `fl_alloc()` / `fl_free()` (freelist) for data with individual lifetimes
- Bump allocation via `alloc()` for long-lived data
- Enum values for constants — don't consume `gvar_toks` slots (256 initialized globals limit)
- Heap-allocate large buffers — `var buf[256000]` bloats the binary by 256KB
- `break` in while loops with `var` declarations is unreliable — use flag + `continue`
- No negative literals — write `(0 - N)` not `-N`
- No mixed `&&` / `||` in one expression — nest `if` blocks instead
- `match` is reserved — don't use as a variable name
- `return;` without value is invalid — always `return 0;`
- All `var` declarations are function-scoped — no block scoping
- Max limits per compilation unit: 4,096 variables, 1,024 functions, 256 initialized globals
- **`var` is function-scoped, not block-scoped** — two `var x` in different `if`/`while` bodies of the same function is a `duplicate variable` compile error. Prefix helper locals in long functions (e.g. test bodies) to avoid collisions
- **Do not rely on implicit literal→`Str` coercion across a function boundary.** A string literal is coerced at a call site whose parameter is typed `Str`, but *not* in return-expression position (`return f(K, "lit")` does not coerce, `f(K, "lit");` does). Convert explicitly with `str_new(cstr, strlen(cstr))` at the boundary — see [ADR 0004](docs/adr/0004-stderr-only-observability.md)

## Dependencies (durable map; versions in state.md)

| Dep | Role | Notes |
|-----|------|-------|
| `darshana` | ANSI color escape generation (24-bit / 256 / 16-color fallback paths) | Substrate. anuenue should NEVER emit raw `\x1b[...m` — always via darshana. |
| `sakshi` | Errors / tracing / structured logging | Canonical per first-party-standards. No inline error types. Wired at v1.2.1 via `src/observe.cyr`. **stderr only** — never `sakshi_output_file` / `_udp`, which would breach the capability bound. See [ADR 0004](docs/adr/0004-stderr-only-observability.md). |
| `agnostik` | Shared Result / Error type shapes | Used wherever sakshi APIs surface. Every anuenue failure path returns through `anuenue_fail(kind, msg)`; kind → exit code is `STIK_ERR_INVALID_ARGUMENT` → 2, everything else → 1. |
| Cyrius stdlib | string, fmt, alloc, io, vec, str, syscalls, assert, bench, args, flags, chrono | Auto-resolved by `cyrius deps`. `args` + `flags` added at M2; `chrono` at M4 for `sleep_ms` + `clock_now_ns`. |

HSV→RGB math is inline in `src/hsv.cyr` (~30 lines incl. phase-wrap + 6-sector branch table; no `abaco` dep needed). See [ADR 0002](docs/adr/0002-hsv-inline-not-abaco.md) for the design + post-v1.0 revisit triggers.

## CI / Release

- **Toolchain pin**: `cyrius = "X.Y.Z"` field in `cyrius.cyml [package]`. CI and release both read this; no hardcoded version strings in YAML.
- **Dead code elimination**: every `cyrius build` in CI and release runs with `CYRIUS_DCE=1`. Note that from cyrius 6.5.x this NOPs unreachable functions in place rather than removing them, so it no longer changes the output size — it is kept because it is the documented build mode and because CI and the release artifact must be built identically.
- **Binary size is tracked, never capped.** Record it every release in `state.md` and attribute any step change (toolchain? dep? our code?). The 512 KB cap was removed at v1.2.2: the number now measures the first-party dep surface far more than it measures anuenue, and capping the total would mean vetoing darshana / sakshi / agnostik / cmdit's right to grow from downstream. A jump is a fact to explain, not a threshold to fail.
- **Tag filter**: release workflow triggers on `tags: ['[0-9]*']` — semver-only.
- **Version-verify gate**: release asserts `VERSION == cyrius.cyml version == git tag` before building.
- **Workflow layout**:
  - `.github/workflows/ci.yml` — install (upstream `install.sh`), verify-layout, deps, DCE build, lint, test, golden-check, animate-smoke, fuzz, observe-check, distlib-drift, version-consistency
  - `.github/workflows/release.yml` — version gate → CI gate → DCE build → artifacts

## Docs

- [`docs/adr/`](docs/adr/) — architecture decision records (*why X over Y?*)
- [`docs/architecture/`](docs/architecture/) — non-obvious constraints (*what's true about the code?*)
- [`docs/guides/`](docs/guides/) — task-oriented how-tos
- [`docs/examples/`](docs/examples/) — runnable examples
- [`docs/development/roadmap.md`](docs/development/roadmap.md) — milestones through v1.0
- [`docs/development/state.md`](docs/development/state.md) — live state snapshot
- [`CHANGELOG.md`](CHANGELOG.md) — source of truth for all changes

Full doc-tree convention: [first-party-documentation.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md).

## CHANGELOG Format

Follow [Keep a Changelog](https://keepachangelog.com/). Performance claims **must** include benchmark numbers. Breaking changes get a **Breaking** section with migration guide. Security fixes get a **Security** section with CVE references where applicable.
