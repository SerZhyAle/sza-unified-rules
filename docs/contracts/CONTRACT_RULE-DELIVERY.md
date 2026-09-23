# CONTRACT_RULE-DELIVERY - pointer

| Field | Value |
| --- | --- |
| Contract | `RULE-DELIVERY` |
| Version | 0.9, draft |
| Home | the shared contracts catalog, domain `rule-adoption/` (the path is in [CLAUDE.md](../../CLAUDE.md)) |
| Role | **producer**, and the only one. Every adopting repository is the consumer |

## What this repo must do to stay conformant

- **The plugin version is the delivery carrier** (rule 1). A canon change that ships without moving it
  reaches nobody, while `deploy` and `plugin update` both report success. This has happened twice; it is
  why the version pair is written by [deploy.ps1](../../deploy.ps1) through
  [tools/bump-canon-version.ps1](../../tools/bump-canon-version.ps1) and never by hand (rules 2, 7).
- **The digest covers `rules/*.md` only**, minus that tree's own `README.md` and the spread prompt
  (rule 3). Changing what it covers changes when every repository is told it is stale.
- **The ladder is judged from the digest**, never from a commit id, and a stamp ahead of the published
  version is corruption rather than staleness (rules 5, 6).
- One deviation is recorded in the catalog registry with an `until` date: the `adopt-canon` skill promises
  a third rung - a version gap of two or more - that the gate does not implement.
