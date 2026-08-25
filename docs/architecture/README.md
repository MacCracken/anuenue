# Architecture notes

Non-obvious constraints, quirks, and invariants that a reader cannot derive from the code alone. Numbered chronologically — never renumber.

Not decisions (those live in [`../adr/`](../adr/)) and not guides (those live in [`../guides/`](../guides/)). An item here describes *how the world is*, not *what we chose* or *how to do something*.

## Items

Populated at v1.3.0. Every entry below records something the v1.2.2 P(-1) audit
or the v1.3.0 animation slot had to *discover* — each one cost real time to
work out from the code, which is the bar for an entry here.

| Note | Invariant |
|------|-----------|
| [001](001-buffer-geometry.md) | The line-buffer geometry is a proof, not three round numbers — `FLUSH_RESERVE` must cover the worst-case single iteration, and the check runs *after* the write. |
| [002](002-phase-normalization-is-a-bounds-guarantee.md) | Phase normalization is a bounds guarantee: the normalized value is an array index, and `-s` / `-F` / `-p` reach it with negative and wrapped i64 from argv. |
| [003](003-animation-caps-drop-input.md) | The animation caps *drop* input rather than uncolouring it — `_pretag_clusters` writes its sentinel at the stop offset. |
| [004](004-module-include-order.md) | `src/observe.cyr` must depend on nothing from anuenue, because every other module calls `anuenue_fail` and cyrius resolves constants in include order. |
| [005](005-timing-primitives-truncate.md) | `sleep_ms` takes an i64 and hands it to `poll(2)`'s 32-bit `int` — the truncation is non-monotonic, so a large sleep either hangs or spins. |
| [006](006-argv-costs-a-file-descriptor.md) | Reading argv costs a file descriptor, so anuenue's CLI cannot be exercised under an fd limit — which is why two audit findings went unmeasured for three minors. |

Add a numbered entry (`NNN-kebab-case-title.md`) the next time the code has a
non-obvious invariant a reader can't derive. Do not write entries for decisions
— those are ADRs.
