# REPO-LAYOUT - pointer

| Field | Value |
| --- | --- |
| Contract | `REPO-LAYOUT` |
| Version | 0.12, draft |
| Home | the shared contracts catalog, domain `rule-adoption/` (the path is in [CLAUDE.md](../../CLAUDE.md)) |
| Role | **producer and consumer**: this repo states the shape in [rules/REPOSITORY_LAYOUT.md](../../rules/REPOSITORY_LAYOUT.md) and its gate is what addresses the names |

## What this repo must do to stay conformant

- The contract binds the names a **program** addresses (rules 1-7: the three agent-rules filenames,
  `docs/contracts/<ID>.md` as pointers, the uppercase type prefixes, `README.md` and `LICENSE` at the
  root, and the ledger sitting where the stamp says) plus the public-vs-local boundary for public
  repositories (rule 8, added in 0.12). Everything else in the layout page is a target shape a repository
  adapts, and adapting it breaks nothing.
- **Public vs local boundary (rule 8, 0.12):** in public repositories (`role` other than `canon-home` and
  `internal`), root agent rules, agent config/memory, workflow trees and portfolio/harness glue
  (`.sza-canon.json`, `.sza-profile.json`, `docs/contracts/`, `docs/DOCUMENT_REGISTRY.jsonl`,
  `docs/releases/`, `r0..rw.*`, `tools/harness.ps1`) stay local and gitignored; untracking uses
  `git rm --cached` without rewriting history. `tools/check-compliance.ps1` reads local agent rules,
  `.claude/rules/`, memory indexes and `docs/contracts/` from disk and enforces the tracked boundary via
  `SZA-LAY07` (rung 1: `tools/tests/public-repo-contents.tests.ps1`). As `canon-home`, this repository is
  exempt for its own shipped canon deliverables while keeping `PLAN/`, `temp/`, `dev/` and
  `.sza-profile.json` local.
- **Renaming any of those names is a breaking change** to this contract, not a refactor - a second
  implementation is addressing them.
- Adding a fourth agent-rules filename is **additive**; removing one of the three is not.
- Rules 3 and 6 - the type prefix and the frozen archive - are checked by nothing today. That is recorded
  in the adoption row rather than claimed as enforcement.
