---
paths:
  - "tools/check-contracts.ps1"
  - "tools/contract-lag.ps1"
  - "docs/contracts/**"
  - "rules/CONTRACTS.md"
  - "skills/contract-sync/**"
  - ".sza-canon.json"
  - ".sza-profile.json"
  - "templates/**"
---

# Contracts this repo owns

Moved verbatim from [CLAUDE.md](../../CLAUDE.md) on 2026-11-25. The always-on rules stay there, the catalog path and its commit flow included ("Working here").

- **This repo owns five contracts.** `REPO-STAMP`, `HARNESS-PROFILE`,
  `REPO-LAYOUT` and `RULE-DELIVERY`, in the catalog's `rule-adoption/` domain, bind the machine-readable
  interface between the canon and a repository - the stamp, the harness profile, the names tools address,
  the version pair that decides whether a rule change arrives. `RELEASE-LEDGER` (domain `release-ledger/`, from
  2026-11-17) binds the release ledger every application keeps and `tools/harness/releases/` writes. The rules' own
  text is **not** a contract and never becomes one. Pointers are in [docs/contracts/](../../docs/contracts/), beside the pointers for six
  contracts outside that domain - `TASK-FLOW` (owner `shared`, implemented by the harness), `CHECK-VERDICT`,
  `DOC-INTERNAL-QUALITY`, `DOC-EXTERNAL-QUALITY`, and the two the harness reads - `APP-COMMANDS` (the command
  manifests it lists) and `DEVICE-EXCHANGE` (the phone-ticket packet it files) - whose roles are in that folder's README. Changing `.sza-canon.json`,
  `.sza-profile.json`, the three agent-rules filenames or the digest's coverage is a contract change, so
  the catalog moves first and the code follows.
- **Touching the catalog?** `pwsh -File tools/check-contracts.ps1` (exit 0 required) validates it: the
  governance pages, every domain's header block, the registry agreeing with it, the status line of every proposal, and
  links. The catalog is outside this repo, so nothing here can catch a broken edit there - the deploy runs this
  advisory, never as a blocker, because a machine without the drive must still be able to ship a rule fix.
