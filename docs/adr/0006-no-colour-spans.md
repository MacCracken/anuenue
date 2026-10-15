# 0006 — Producers mark no-colour spans with an APC marker pair

**Status**: Accepted
**Date**: 2026-10-15

## Context

From v1.4.5 anuenue owns the colour on its colour routes (the filter, one-shot
text, animation). It strips the input's own SGR colour codes and tints
everything. That leaves a producer with no way to keep part of its output out of
the rainbow, short of splitting its output around anuenue. Typical cases are a
logo with its own colours, a warning that must stay red, or a prompt.

The user asked for a "no color" code a producer can put in its output (2026-10-14).
It has to be:

- **inert without anuenue**: the same output piped straight to a terminal must not
  show the marker;
- **unambiguous**: no existing output may trigger it by accident;
- **cheap to recognise**: anuenue's hot path tests one byte for ESC and nothing
  more for ordinary text (v1.4.5 kept that at zero cost).

## Decision

**A producer brackets text with an ECMA-48 application program command pair, and
anuenue passes the bracketed bytes through untinted.**

```
ESC _ anuenue:off ESC \      15 bytes   1B 5F "anuenue:off" 1B 5C
ESC _ anuenue:on  ESC \      14 bytes   1B 5F "anuenue:on"  1B 5C
```

APC (`ESC _` … ST) is the standard's slot for application-specific commands, and
xterm-family terminals ignore it, so a producer's output renders cleanly when
anuenue is not in the pipe. Only these two exact byte strings are markers: no
whitespace, lower case, ST (`ESC \`) as the terminator. Every other APC
(kitty's graphics protocol is one) passes through as before.

Decided with the user, 2026-10-15:

1. **Inside a span the producer's bytes pass through intact**, colour codes
   included: the span is the producer's. A span with no codes shows in the
   terminal's default colour.
2. **anuenue emits an SGR reset at both markers**, so its colour does not bleed
   into the span and the span's attributes do not bleed into the rainbow after
   it. Inside a span anuenue writes nothing of its own. That means no reset
   before an LF either, so a producer's colour may run across lines.
3. **The rainbow pauses across a span.** Span bytes take no phase step. The
   first cluster after the span gets the hue that would have followed the
   cluster before it. A combining mark (any extender) straight after a span
   continues the cluster before it, with its hue, as it would with the span
   removed. The ZWJ and regional-indicator joins do not reach across a span,
   empty or not: the reset at `off` breaks them on screen too.
4. **Lenient matching.** `off` with no `on` runs to the end of the input, and
   the end closes it like an `on`: one reset, so a producer's colour never
   outlives anuenue (found while writing the gates; without it, a span ending
   in LF left the terminal coloured into the shell prompt). A stray `on`, or
   `off` inside a span, is a no-op. Markers are always consumed and never
   written, and nothing errors.
5. **Markers are consumed in every mode, MONO included.** They are commands
   addressed to anuenue, not text. MONO stays byte-exact for every other byte.
   It is no longer a bare copy loop when a chunk contains an ESC.
6. **A marker split across a 4096-byte read is recognised.** The same bounded
   carry as a split UTF-8 sequence or an unfinished SGR (v1.4.5) holds it, at
   most 14 bytes.
7. **Animation**: a span is drawn raw in every frame (it does not cycle) while
   the text around it scrolls, with a reset before each span as on the other
   routes, so two adjacent spans do not share attributes. H-01's row count
   counts the span's text like any other. Inside a span, escape sequences
   reach the terminal intact, so the count parses them as the terminal does:
   one step of the VT500 parser (xterm's) per byte, `_span_vt`. CSI runs to
   its final byte, OSC to BEL or ST, a DCS / SOS / PM / APC string to ST, and
   an escape through its intermediates. An ESC restarts from any state,
   CAN / SUB abort, and a C0 control is executed even mid-sequence (an LF
   inside an unfinished CSI is still a line feed). The first cut modelled
   only CSI and OSC and missed the last two rules; writing the PTY gate found
   it. A combining mark straight after a span joins the span's last cell, so
   it takes no columns either.

## Consequences

- **Positive**: a producer can keep any part of its output out of the rainbow,
  with its own colours, and that output still renders correctly without anuenue.
- **Positive**: ordinary text pays nothing. The marker is only looked for at an
  ESC, and the ESC test already exists (v1.4.5).
- **Negative**: anuenue now has a second input grammar to parse, beside SGR, and
  two rendering modes per route. Every route gains a span state, and the
  animation pre-tag gains a per-cluster flag.
- **Negative**: the Linux text console does not implement APC and may print the
  payload when anuenue is absent. xterm-family terminals, tmux and the common
  emulators ignore it.
- **Neutral**: MONO is byte-exact *except* for markers, which is one more
  exception beside none. Before v1.5.0 MONO was a pure `cat`.

## Alternatives considered

- **A private SGR parameter** (e.g. `ESC [ 2900 m`). Terminals ignore unknown SGR
  numbers too, and anuenue's SGR scanner would find it for free. Rejected because
  it squats on SGR number space, which belongs to the standard and to terminal
  vendors, and because v1.4.5 strips SGR, so the marker would be a special case
  of the thing being stripped.
- **Honouring the producer's own colour codes as the marker** ("a coloured span
  is the producer's"). Rejected: v1.4.5's decision is that anuenue owns the
  colour on its routes. And `ls --color` output, the case v1.4.5 fixed, would
  then never be tinted.
- **OSC with a private number.** OSC is for operating-system commands (titles,
  clipboard, hyperlinks); APC is the slot for application commands, which this
  is.
- **Strict matching with warnings.** Rejected for the rendering (a pipe filter
  should not fail on its input), and the user chose not to warn either.
