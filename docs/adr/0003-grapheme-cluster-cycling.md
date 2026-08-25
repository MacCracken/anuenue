# 0003 — Cycle by grapheme cluster via a practical-subset classifier

**Status**: Accepted
**Date**: 2026-05-22

## Context

A grapheme cluster is what a human reads as "one character" —
distinct from a codepoint, distinct from a byte. `é` may be one
codepoint (U+00E9) or two (U+0065 base + U+0301 combining acute);
🇺🇸 is two Regional Indicator codepoints; 🏳️‍🌈 is white-flag +
VS-16 + ZWJ + rainbow. The shell-level rainbow tools we're competing
with mostly get this wrong:

- **Ruby `lolcat` (Cure53 2014 origin)** cycles per *byte*, so `é`
  in NFD form gets two phase advances and `🇺🇸` gets six (four
  for each of the surrogate-pair UTF-8 bytes plus two for the
  combining marks if any).
- **`lolcat-c` (busyloop)** cycles per *codepoint* — better, but
  emoji ZWJ sequences still light up each component separately.
- **`lolcrab` (Rust)** uses the `unicode-segmentation` crate and gets
  it right, at the cost of pulling a several-thousand-entry static
  table.

anuenue's v1.0 acceptance criterion says *"UTF-8 correct by default
— grapheme-cluster aware cycling (Ruby lolcat got this wrong; AGNOS
ships it right)"*. The question is **how correct, and at what cost**.

### The three classifier options

We considered three:

1. **Full UAX #29 cluster boundary detection.** Ship the complete
   GraphemeBreakProperty table from the Unicode Character Database
   (~30 KB compiled, ~3 000 ranges across CR, LF, Control, Extend,
   ZWJ, Regional_Indicator, Prepend, SpacingMark, L, V, T, LV, LVT,
   Extended_Pictographic) plus the GB1..GB999 rule engine. This is
   what `unicode-segmentation` does.
2. **Depend on `vyakarana`** (the AGNOS siblings-registry tokenizer)
   for cluster detection.
3. **Inline practical-subset classifier.** A small static range
   table covering the categories that matter for the MOTD / banner /
   shell-prompt domain, with explicit graceful degradation for the
   long tail.

vyakarana was evaluated at M3 (v0.4.0 cycle) and rejected on
*domain*: it's a *source-code* tokenizer (CYML-grammar-driven token-
kind spans for syntax highlighting), not a Unicode segmentation
database. Wiring vyakarana would mean shoving Unicode tables through
an API shaped for keyword recognition. Wrong tool.

That leaves full UAX #29 vs the practical subset.

## Decision

**Ship a practical-subset extending-codepoint classifier inline in
`src/filter.cyr`.** Concretely, `cp_is_extending(cp)` (line 398) plus
`cp_is_regional_indicator(cp)` (line 432), backed by a 21-entry sorted
`(lo, hi)` range table searched in O(log n) via the M5 perf pass.

The covered ranges (see `_cp_ext_init`, `src/filter.cyr:295`):

| Range                 | Codepoints       | Source            |
|-----------------------|------------------|-------------------|
| Combining Diacritical Marks | U+0300..036F | Latin / Greek combiners |
| Cyrillic combining    | U+0483..0489     | Cyrillic-script accents |
| Hebrew points / cantillation | U+0591..05BD, 05BF, 05C1-C2, 05C4-C5, 05C7 | Hebrew niqqud |
| Arabic combining      | U+0610-061A, 064B-065F, 0670, 06D6-DC, 06DF-E4, 06E7-E8, 06EA-ED | Arabic diacritics |
| ZWJ                   | U+200D           | Emoji-sequence joiner |
| Variation Selectors   | U+FE00..FE0F     | VS-15 (text), VS-16 (emoji) |
| Combining Half Marks  | U+FE20..FE2F     | Spanning combiners |
| Math-zone combiners   | U+1AB0..1ACE, 1DC0..1DFF, 20D0..20F0 | Math + IPA marks |
| Variation Selectors Supplement | U+E0100..E01EF | Tag sequences |

Plus a separate `cp_is_regional_indicator` predicate (U+1F1E6..1F1FF)
with a *pair latch* in `anuenue_filter` (`src/filter.cyr` ~line 622)
and `_pretag_clusters` (animation, `src/animate.cyr` ~line 657) — two
consecutive RIs cluster into one cycle, matching flag-emoji behaviour.

The stream invariant is **"advance once per cluster"** where a cluster
is the longest maximal run of:

```
base codepoint
  ( extending codepoint | ZWJ | VS ) *
  ( regional-indicator paired with another RI )
```

ZWJ-then-ASCII (the only pattern where the cluster crosses the M5
ASCII short-circuit boundary) gets a `prev_was_zwj` latch so the next
codepoint after ZWJ is treated as extending — matching the most
common emoji ZWJ-sequence shape.

## Consequences

### Positive

- **Tiny on-disk footprint.** 21 ranges × 16 bytes = 336 bytes of
  static data, allocated lazily on first cluster-classification call.
  Compare ~30 KB for a full UAX #29 table.
- **Auditable.** Each range cites the Unicode block it covers; tests
  in `tests/anuenue.tcyr` exercise both endpoints of every range
  (M3's 30 new assertions plus M4/M5/M6 coverage). A reviewer can
  verify the table against unicode.org/charts in an afternoon.
- **No dep pull.** Nothing comes from outside `filter.cyr`. No build-
  step Unicode-table generator; no sandhi-coordination with a
  hypothetical `agnos-unicode` crate.
- **Hot path stays clean.** ASCII (the dominant MOTD case) short-
  circuits before any classifier work (M5). Non-ASCII pays the binary
  search (~5 comparisons average; ~log₂(21) worst case) plus the
  cheap `cp < 0x0300 || cp > 0xE01EF` reject.
- **Graceful for the long tail.** The ranges we don't cover (Hangul
  L/V/T, Devanagari spacing marks, Tibetan subjoiners, tag
  sequences) get *over*-segmented — each codepoint becomes its own
  cluster. The rainbow still cycles, just slightly faster than a
  perfectly correct implementation would. **Never under-segments**,
  so we never collapse what a human would see as two characters into
  one phase.
- **DCE-friendly.** The table is a single `alloc` at first call,
  initialised in-line. No build-time table generator. No `init`
  function the binary has to keep alive even when DCE could prove it
  unused.

### Negative

- **Hangul L/V/T composition is the visible miss.** Korean Hangul
  syllables in the *decomposed* form — `한` written as ᄒ (U+1112) +
  ᅡ (U+1161) + ᆫ (U+11AB) — render as three phase advances rather
  than one. The *composed* form `한` (U+D55C) is a single
  codepoint and cycles correctly. In practice most Korean text is
  composed; the MOTD chain never carries decomposed Hangul in the
  wild. We accept the regression.
- **Devanagari and other Brahmic scripts** with explicit spacing
  marks (Devanagari vowel signs, e.g. U+093E ा) get over-
  segmented for the same reason — UAX #29 classifies them as
  `SpacingMark`, which our subset doesn't model. The visible effect
  is "syllables tinted slightly faster than the visual character
  rate". Acceptable for v1.0; revisit if a Hindi-language MOTD
  consumer surfaces.
- **Tag sequences (subdivision flags, e.g. 🏴󠁧󠁢󠁳󠁣󠁴󠁿 Scotland) over-
  segment.** The U+E0020..E007F tag-character range isn't in the
  table. Per the same reasoning above, accepted.
- **No NFC normalization.** anuenue treats the byte stream as
  authoritative; if upstream sent NFD `é = e + ̀ `, we cycle once for
  the cluster but never compose it. This is correct behaviour for a
  pipe filter (we don't own the canonical form) but worth recording.

### Neutral

- **Tests are the contract.** Each range has a tcyr assertion at
  both endpoints (`tests/anuenue.tcyr` covers `cp_is_extending` and
  `cp_is_regional_indicator` exhaustively for the listed ranges plus
  rejection cases). The four M3+M4 golden fixtures (`cjk-mixed-s0`,
  `combining-s0`, `zwj-flag-s0`, plus the ASCII `agnos-rainbow-s100`)
  lock the end-to-end behaviour byte-identical.
- **Upgrade path is clean.** If a future minor (v2.x?) wants full
  UAX #29 correctness, replace `cp_is_extending` with a generated
  table; the table contract is "predicate: cp → 0/1". The 21 ranges
  are a strict subset of any UAX #29 GraphemeBreakProperty=Extend
  table, so the upgrade is monotonic — clusters can only get bigger,
  never smaller, and the existing tcyr assertions remain valid.

## Alternatives considered

- **Full UAX #29 via a generated Unicode table.** Rejected for v1.0
  on **dep weight + audit cost**. The table is several thousand
  ranges; we'd own the generator, the Unicode-version pinning, and
  the surprise-bump story every Unicode major release. Recommend
  for v2 if a real consumer surfaces a script we don't handle.
- **Depend on `vyakarana`.** Rejected at M3: vyakarana is a source-
  code tokenizer (CYML token-kind spans), not a Unicode database.
  Different domain. The roadmap captures the rejection narrative
  ([roadmap.md § Dependency map, "not wired"](../development/roadmap.md#dependency-map)).
- **Cycle per codepoint, accept the lolcat-c regression.** Rejected:
  the v1.0 acceptance criterion explicitly calls out cluster
  awareness as the differentiator vs the Ruby and C predecessors.
- **Cycle per byte (Ruby lolcat).** Strongly rejected. Multi-byte
  CJK characters would each get 3 phase advances, emoji 4, and
  combining marks would tint independently of their bases. Visually
  *and* semantically wrong for a tool that owns the rainbow on
  every AGNOS login.
- **Inline the full UAX #29 ranges by hand.** Rejected on audit
  surface and Cyrius-limit grounds: the practical-subset table fits
  in 21 entries; a full table would push past anuenue's 256
  initialized-globals limit (CLAUDE.md § Cyrius Conventions) and
  force heap-allocated table construction at startup. We already
  use one heap allocation for the M5 phase cache; doubling that for
  a feature only a fraction of users would notice doesn't earn its
  keep.

## References

- Unicode UAX #29 — Unicode Text Segmentation. https://unicode.org/reports/tr29/
- Practical-subset selection: M3 (v0.4.0) implementation notes in
  [`CHANGELOG.md`](../../CHANGELOG.md) and the carry-forward in
  [`docs/development/state.md`](../development/state.md).
- The M5 perf pass that flattened the original linear chain into the
  sorted-table binary search lives in `src/filter.cyr:295`
  (`_cp_ext_init`) and `src/filter.cyr:331` (`cp_is_extending`).
