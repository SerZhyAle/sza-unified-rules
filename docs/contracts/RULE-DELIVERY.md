# RULE-DELIVERY - pointer

| Field | Value |
| --- | --- |
| Contract | `RULE-DELIVERY` |
| Version | 0.12, draft; installed reader delivery verified on 2026-10-26 |
| Home | the shared contracts catalog, domain `rule-adoption/` (the path is in [CLAUDE.md](../../CLAUDE.md)) |
| Role | **producer and consumer**: this repository ships the version pair and implements the stamp reader |

## What this repo must do to stay conformant

- **The plugin version is the delivery carrier** (rule 1). A canon change that ships without moving it
  reaches nobody, while `deploy` and `plugin update` both report success. This has happened twice; it is
  why the version pair is written by [deploy.ps1](../../deploy.ps1) through
  [tools/bump-canon-version.ps1](../../tools/bump-canon-version.ps1) and never by hand (rules 2, 7).
- **The digest covers `rules/*.md` only**, minus that tree's own `README.md` and the spread prompt
  (rule 3). Changing what it covers changes when every repository is told it is stale.
- **The ladder is judged from the digest**, never from a commit id, and a stamp ahead of the published
  version is corruption rather than staleness (rules 5, 6).
- Rule 5 uses a parseable reconciliation date, else adoption date; unknown age with a differing digest
  is past the window. The skill now follows the same ladder. Local reader tests do not prove delivery
  to another repository's installed plugin; deploy remains a separate owner request.
- `pwsh -NoProfile -File tools/tests/verify-delivery.ps1` judges the installed plugin copy against the source
  and replays the reader tests with the installed tree as `-SourceRoot`. It reads, never writes. It says
  DELIVERED only for the same version, a pair that derives, equal reader files and a passing replay; a
  change under an unchanged version is reported as such (rule 1). Run it before a deploy and after
  `claude plugin update` to get the two rows rung 4 asks for. Reader file hashes read CRLF as LF, because an
  installed copy takes the machine's `autocrlf` setting. Record and limits:
  [PROGRESS_CONTRACT-DELIVERY-S0012.md](../PROGRESS_CONTRACT-DELIVERY-S0012.md).
- The published `2026.1026.1` release was installed and replayed on 2026-10-26: DELIVERED, exit 0,
  all 8 reader files equal, reader PASS (44 cases), harness PASS (24 cases, 4 known gaps). This is
  evidence for that installed release; wider layout/writer fixtures and full harness conformance
  remain outside the delivery claim.
