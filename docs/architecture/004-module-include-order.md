# 004 — `src/observe.cyr` must depend on nothing from anuenue

`src/main.cyr` includes in this order, and the order is not stylistic:

```
include "src/observe.cyr"     # <- first, and it has to be
include "src/hsv.cyr"
include "src/color.cyr"
include "src/filter.cyr"
include "src/animate.cyr"
include "src/version_str.cyr"
```

Cyrius resolves **enum members and module-level `var`s at parse time**, in
include order. A file cannot reference an enum declared in a file included after
it. (Functions are resolved globally at link time, so forward *calls* are fine —
it is the constants that pin the order.)

## The constraint

`observe.cyr` holds `anuenue_fail`, and **every other module calls it** —
`color.cyr` for the passthrough allocation failure, `filter.cyr` for the read
and allocation failures, `animate.cyr` for its three, `main.cyr` for the flag
validations. So `observe.cyr` has to come first.

Which means `observe.cyr` may reference **only** sakshi, agnostik and the
stdlib. The moment it references an `ANUENUE_*` constant from another module,
that module has to be included before it, and whatever in that module calls
`anuenue_fail` now cannot see it.

## Where the seam actually falls

This is why the colour-decision reason codes live in `src/color.cyr` and not in
`observe.cyr` alongside the rest of the diagnostics vocabulary:

- `ANUENUE_CR_*`, `ANUENUE_COLOR_REASON`, `anuenue_color_reason_name`,
  `anuenue_color_mode_name` all need `ANUENUE_COLOR_*` → they live in
  `color.cyr`.
- `AnuenueExit`, `AnuenueLogParse`, `_eprint`, the span and kv helpers, and
  `anuenue_fail` need nothing from anuenue → they live in `observe.cyr`.

The first draft of the v1.2.1 observability work put the colour names in
`observe.cyr` and produced exactly the cycle above.

## Keeping it true

`tests/*.tcyr` and every `fuzz/*.fcyr` repeat the same include order, so a
violation fails the build there too rather than only in `main.cyr`. If you add a
module that needs `anuenue_fail`, include it *after* `observe.cyr` — and if you
are tempted to make `observe.cyr` reach back into anuenue, that is the signal to
put the new symbol in the module that owns its constants instead.
