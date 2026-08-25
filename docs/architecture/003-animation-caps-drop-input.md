# 003 — The animation caps drop input; they do not merely uncolour it

Animation is slurp-then-tag, not streaming. Two ceilings apply
(`src/animate.cyr`):

```
ANUENUE_ANIMATE_INPUT_MAX   = 65536   # bytes read from stdin
ANUENUE_ANIMATE_CLUSTER_MAX =  8192   # clusters indexed
```

The comments describe this as graceful degradation — "render what fit; don't
OOM". True, but the *shape* of the degradation is not what a reader assumes,
and it is not visible from the constants.

## The sentinel is the stop offset

`_pretag_clusters` walks the input and finishes with:

```
store64(ctab + n_clusters * 8, i);      # i = where the walk STOPPED
```

`_render_frame` computes each cluster's length as `ctab[n+1] - ctab[n]`, so that
final entry is the end of the last cluster. When the walk stops because it hit
`max_clusters`, `i` is wherever it happened to be — **not** `n_bytes`.

Consequence: every byte past that offset is never rendered. It is not folded
into the last cluster, not emitted uncoloured, not truncated at a line boundary.
It is simply absent from every frame.

Measured: a 200 001-byte input animates as exactly 8 192 characters per frame.

## Both ceilings can bite, in either order

The byte cap trims first (only the first 64 KB is read at all), then the cluster
cap trims what remains. All-ASCII input hits the cluster cap first — 8 192
clusters is 8 192 bytes, well under 64 KB. Wide or combining-heavy input hits
the byte cap first.

Since v1.2.2 (audit A-05) both emit a `SK_WARN` record, so `-v` or
`--log-level=warn` says which one fired. Nothing is printed at default
verbosity — see [ADR 0004](../adr/0004-stderr-only-observability.md).

## Why the filter path has no equivalent

`anuenue_filter` streams: it never holds more than one read chunk plus a partial
UTF-8 sequence, so there is no ceiling to hit and no truncation to report. Only
`-a` slurps, because frame re-anchoring needs to know the total row count before
the first frame is drawn.

Raising or removing the caps is tracked in
[`roadmap.md` § v1.x](../development/roadmap.md#waiting-for-a-second-data-point);
it trades against the slurp design, so it needs a real use case first.
