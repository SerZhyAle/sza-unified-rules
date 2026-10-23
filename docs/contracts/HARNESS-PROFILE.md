# HARNESS-PROFILE - pointer

| Field | Value |
| --- | --- |
| Contract | `HARNESS-PROFILE` |
| Version | 0.13, draft; source reader verified |
| Home | the shared contracts catalog, domain `rule-adoption/` (the path is in [CLAUDE.md](../../CLAUDE.md)) |
| Role | **consumer**, and the schema's owner. Each repository running the harness writes its own profile |

## What this repo must do to stay conformant

- `tools/harness/_profile.ps1` is the only reader and the home of the defaults. A default changed there
  changes what an absent key means in every repository running that harness - which makes it a contract
  change (rule 2), not a tidy-up.
- **The merge rule is binding**: objects merge key by key, arrays and scalars replace. An empty array in a
  profile means "none", never "use the default" (rule 3).
- **Lock domain ranks are acquired in order** and reordering them is a deadlock (rule 5).
- Dev-log defaults, overrides and disabled tools follow rule 2 and the 2026-10-17 amendment;
  `tools/tests/contract-sync.tests.ps1` exercises all ledger shapes without altering user ledgers.
- Version dispatch follows the 2026-10-23 amendment before merge. Legacy absence and `"1"` remain
  readable; higher MINOR and unknown keys are tolerated; unsupported MAJOR, null and malformed carriers
  refuse cleanly. Catalog reader vectors and all existing merge/dev-log regressions are replayed.
  Installed-consumer delivery remains unverified.
