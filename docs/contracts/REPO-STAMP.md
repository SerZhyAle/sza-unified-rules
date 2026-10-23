# REPO-STAMP - pointer

| Field | Value |
| --- | --- |
| Contract | `REPO-STAMP` |
| Version | 0.13, draft; source reader verified |
| Home | the shared contracts catalog, domain `rule-adoption/` (the path is in [CLAUDE.md](../../CLAUDE.md)) |
| Role | **consumer**, and the schema's owner. Every adopting repository writes its own stamp; this repo holds the only reader |

## What this repo must do to stay conformant

- `tools/check-compliance.ps1` is that reader. It holds rules 1-4, rule 5's strict fallback and rule 7;
  `templates/.sza-canon.json` and the `adopt-canon` skill are what write a stamp, and they move with the
  reader, never ahead of it.
- Carrier dispatch follows the 2026-10-23 amendment: the template emits the optional wire carrier,
  legacy absence remains readable, higher MINOR is accepted and unsupported MAJOR is refused before use.
- A new optional key arrives with its **absence meaning written into the contract** (rule 4), not decided
  in the reader.
- Rule 4's age fallback and unknown-age behavior are tested in `tools/tests/contract-sync.tests.ps1`:
  a differing digest with neither date parseable is an error; an equal digest owes no age finding.
- Unknown roles produce `SZA-CANON08` and retain strict product checks. Catalog reader vectors are
  generated and replayed by `tools/tests/contract-reader.tests.ps1`; delivery to installed consumers
  remains outside source verification. The real stamp is not rewritten by this ticket.
