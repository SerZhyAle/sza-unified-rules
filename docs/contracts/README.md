# Contract pointers

This repository owns the four `rule-adoption/` contracts. The shared catalog is their source of truth;
these files are concise pointers, not local copies.

| Contract | Version | Home | Role | Pointer |
| --- | --- | --- | --- | --- |
| `REPO-STAMP` | 0.13, draft | `rule-adoption/` | consumer and schema owner | [REPO-STAMP.md](REPO-STAMP.md) |
| `HARNESS-PROFILE` | 0.17, draft | `rule-adoption/` | consumer and schema owner | [HARNESS-PROFILE.md](HARNESS-PROFILE.md) |
| `REPO-LAYOUT` | 0.11, draft | `rule-adoption/` | producer and consumer | [REPO-LAYOUT.md](REPO-LAYOUT.md) |
| `RULE-DELIVERY` | 0.12, draft | `rule-adoption/` | producer and consumer; installed reader delivery verified | [RULE-DELIVERY.md](RULE-DELIVERY.md) |
| `CHECK-VERDICT` | 0.14, draft | `automated-checks/` | scoped test producer | [CHECK-VERDICT.md](CHECK-VERDICT.md) |
| `DOC-INTERNAL-QUALITY` | 0.13, draft | `documentation-quality/` | declared technical corpora | [DOC-INTERNAL-QUALITY.md](DOC-INTERNAL-QUALITY.md) |
| `DOC-EXTERNAL-QUALITY` | 0.14, draft | `documentation-quality/` | not bound; no public end-user corpus | [DOC-EXTERNAL-QUALITY.md](DOC-EXTERNAL-QUALITY.md) |
| `APP-COMMANDS` | 0.2, draft | `app-commands/` | reader of the discovery interface (rules 18 and 20, item R.1) | [APP-COMMANDS.md](APP-COMMANDS.md) |
| `DEVICE-EXCHANGE` | 1.15, active | `device-exchange/` | receiver of the `TICKET` packet kind (section 24, items CN, FC, FD), partial | [DEVICE-EXCHANGE.md](DEVICE-EXCHANGE.md) |

It also implements one contract it does not own: `TASK-FLOW` (domain `task-flow/`, owner `shared`), through the
harness - see [TASK-FLOW.md](TASK-FLOW.md). The last two rows are contracts it reads rather than owns: the harness
lists the command manifests of the portfolio's products (`APP-COMMANDS`) and files the tickets a phone sends
(`DEVICE-EXCHANGE`); each pointer says which rules and items bind here and which products' rules do not.

Catalog paths are intentionally not repeated here. Code and documentation cite a contract by id and rule
or section, not by a catalog filesystem path.

Scope and fresh evidence: [S0008 audit](../PROGRESS_CONTRACT-SYNC-S0008.md). Document versions above
identify the text reviewed; they do not advance implementation versions without proof.
S0011 source verification and scoped catalog replay: [reader evidence](../PROGRESS_CONTRACT-READERS-S0011.md).
