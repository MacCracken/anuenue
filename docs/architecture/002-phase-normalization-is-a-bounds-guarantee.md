# 002 — Phase normalization is a bounds guarantee, not a nicety

`hsv_rainbow` and `_emit_phase_esc` both begin the same way:

```
phase = phase % ANUENUE_PHASE_MOD;
if (phase < 0) { phase = phase + ANUENUE_PHASE_MOD; }
```

That reads like defensive tidiness. It is load-bearing: the normalized value is
used as an **array index**.

```
var entry = _PHASE_ESC_TABLE + p * ANUENUE_ESC_TABLE_ENTRY_SIZE;
var elen  = load64(entry);
```

A negative `p` reads before the table; a `p >= ANUENUE_PHASE_MOD` reads past it.
Either is an out-of-bounds read whose result is then used as a **length** for a
copy loop.

## Negative and out-of-range phases are reachable, not hypothetical

Three user-controlled routes:

- **`-s` / `--seed` and `-F` / `--offset`** take arbitrary i64 from argv and are
  *summed* into `ANUENUE_PHASE_START`. `anuenue -F -1` reaches the normalizer
  with a negative phase directly, and `-s <large> -F <large>` reaches it with a
  wrapped one.
- **`-p` / `--freq`** is added per cluster (`phase = phase + ANUENUE_PHASE_STEP`).
  With a large step the accumulator wraps at i64 partway through a long stream.
- **Animation `-S` / `--speed`** does the same per frame against `phase_base`.

Cyrius `%` follows C semantics: the remainder takes the sign of the dividend. So
`(-1) % 1530` is `-1`, not `1529` — which is exactly why the second line exists.
Dropping it turns every negative seed into an out-of-bounds read.

## Why it is duplicated in two places

`hsv_rainbow` lives in `src/hsv.cyr`, which is the **distlib** module
(`[lib] modules = ["src/hsv.cyr"]`) — consumers include it standalone and call
it with phases anuenue never sees. `_emit_phase_esc` lives in `src/filter.cyr`
and indexes the cached escape table. Neither can rely on the other having run.
The duplication is deliberate; do not "factor it out" into one call site.

Covered by the `hsv_rainbow — phase normalization` unit group and by the i64
extreme sweep in `scripts/robustness-check.sh`.
