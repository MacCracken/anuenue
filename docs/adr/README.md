# Architecture Decision Records

Decisions about anuenue — what we chose, the context, and the consequences we accept. Use these when a future reader would reasonably ask *"why did we do it this way?"*

## Conventions

- **Filename**: `NNNN-kebab-case-title.md`, zero-padded to four digits. Never renumber.
- **One decision per ADR.** If a decision supersedes a prior one, add a new ADR and set the old one's status to `Superseded by NNNN`.
- **Status lifecycle**: `Proposed` → `Accepted` → (optionally) `Superseded` or `Deprecated`.
- Use [`template.md`](template.md) as the starting point.

## ADR vs. architecture note vs. guide

| Kind | Lives in | Answers |
|---|---|---|
| ADR | `docs/adr/` | *Why did we choose X over Y?* |
| Architecture note | `docs/architecture/` | *What non-obvious constraint is true about the code?* |
| Guide | `docs/guides/` | *How do I do X?* |

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-pipe-purity.md) | Pipe-purity: no file I/O, no config, no themes | Accepted |
| [0002](0002-hsv-inline-not-abaco.md) | HSV→RGB stays inline; no abaco dependency | Accepted |
| [0003](0003-grapheme-cluster-cycling.md) | Cycle by grapheme cluster via a practical-subset classifier | Accepted |
| [0004](0004-stderr-only-observability.md) | Diagnostics go to stderr, and are off by default | Accepted |
