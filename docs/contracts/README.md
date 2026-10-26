# Contract pointers

This repository owns the four `rule-adoption/` contracts. The shared catalog is their source of truth;
these files are concise pointers, not local copies.

| Contract | Version | Home | Role | Pointer |
| --- | --- | --- | --- | --- |
| `REPO-STAMP` | 0.13, draft | `rule-adoption/` | consumer and schema owner | [REPO-STAMP.md](REPO-STAMP.md) |
| `HARNESS-PROFILE` | 0.13, draft | `rule-adoption/` | consumer and schema owner | [HARNESS-PROFILE.md](HARNESS-PROFILE.md) |
| `REPO-LAYOUT` | 0.11, draft | `rule-adoption/` | producer and consumer | [REPO-LAYOUT.md](REPO-LAYOUT.md) |
| `RULE-DELIVERY` | 0.12, draft | `rule-adoption/` | producer and consumer; installed reader delivery verified | [RULE-DELIVERY.md](RULE-DELIVERY.md) |
| `CHECK-VERDICT` | 0.13, draft | `automated-checks/` | scoped test producer | [CHECK-VERDICT.md](CHECK-VERDICT.md) |
| `DOC-INTERNAL-QUALITY` | 0.10, draft | `documentation-quality/` | declared technical corpora | [DOC-INTERNAL-QUALITY.md](DOC-INTERNAL-QUALITY.md) |
| `DOC-EXTERNAL-QUALITY` | 0.12, draft | `documentation-quality/` | not bound; no public end-user corpus | [DOC-EXTERNAL-QUALITY.md](DOC-EXTERNAL-QUALITY.md) |

It also implements one contract it does not own: `TASK-FLOW` (domain `task-flow/`, owner `shared`), through the
harness - see [TASK-FLOW.md](TASK-FLOW.md).

Catalog paths are intentionally not repeated here. Code and documentation cite a contract by id and rule
or section, not by a catalog filesystem path.

Scope and fresh evidence: [S0008 audit](../PROGRESS_CONTRACT-SYNC-S0008.md). Document versions above
identify the text reviewed; they do not advance implementation versions without proof.
S0011 source verification and scoped catalog replay: [reader evidence](../PROGRESS_CONTRACT-READERS-S0011.md).
