# REPO-STAMP - pointer

| Field | Value |
| --- | --- |
| Contract | `REPO-STAMP` |
| Version | 0.14, draft; source reader verified |
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
- 0.14: the reader names the changed rule docs from `canon.docDigests` (unknown without the map), owes
  `canon-home` no staleness finding and reads no `until` of an exemption; a differing digest is a warning at any
  age (`RULE-DELIVERY` 0.13). The adoption run writes the map. Checked on 2026-11-25 (CANONR-0187) by direct calls
  on throwaway stamps; `tools/tests/contract-sync.tests.ps1` holds the release-tier cases.
- Unknown roles produce `SZA-CANON08` and retain strict product checks. Catalog reader vectors are
  generated and replayed by `tools/tests/contract-reader.tests.ps1`; delivery to installed consumers
  remains outside source verification. The real stamp is not rewritten by this ticket.
