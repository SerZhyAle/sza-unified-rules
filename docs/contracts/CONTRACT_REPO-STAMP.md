# CONTRACT_REPO-STAMP - pointer

| Field | Value |
| --- | --- |
| Contract | `REPO-STAMP` |
| Version | 0.9, draft |
| Home | the shared contracts catalog, domain `rule-adoption/` (the path is in [CLAUDE.md](../../CLAUDE.md)) |
| Role | **consumer**, and the schema's owner. Every adopting repository writes its own stamp; this repo holds the only reader |

## What this repo must do to stay conformant

- `tools/check-compliance.ps1` is that reader. It holds rules 1-4, rule 5's strict fallback and rule 7;
  `templates/.sza-canon.json` and the `adopt-canon` skill are what write a stamp, and they move with the
  reader, never ahead of it.
- **Every change to the stamp is additive** until the file has a version carrier - `REPO-STAMP` rule 9.
  A key may be added; none may be removed, renamed or given a new meaning.
- A new optional key arrives with its **absence meaning written into the contract** (rule 4), not decided
  in the reader.
- Three deviations are recorded in the catalog registry with an `until` date: the missing version carrier,
  an unknown `role` never being reported, and this repository's own stamp standing stale.
