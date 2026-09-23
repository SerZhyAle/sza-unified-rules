# CONTRACT_HARNESS-PROFILE - pointer

| Field | Value |
| --- | --- |
| Contract | `HARNESS-PROFILE` |
| Version | 0.9, draft |
| Home | the shared contracts catalog, domain `rule-adoption/` (the path is in [CLAUDE.md](../../CLAUDE.md)) |
| Role | **consumer**, and the schema's owner. Each repository running the harness writes its own profile |

## What this repo must do to stay conformant

- `tools/harness/_profile.ps1` is the only reader and the home of the defaults. A default changed there
  changes what an absent key means in every repository running that harness - which makes it a contract
  change (rule 2), not a tidy-up.
- **The merge rule is binding**: objects merge key by key, arrays and scalars replace. An empty array in a
  profile means "none", never "use the default" (rule 3).
- **Lock domain ranks are acquired in order** and reordering them is a deadlock (rule 5).
- One deviation is recorded in the catalog registry with an `until` date: `version` is declared in the file
  and read by nothing, so rule 3 of the compatibility law is owed here.
