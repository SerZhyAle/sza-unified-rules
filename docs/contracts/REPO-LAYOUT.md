# REPO-LAYOUT - pointer

| Field | Value |
| --- | --- |
| Contract | `REPO-LAYOUT` |
| Version | 0.9, draft |
| Home | the shared contracts catalog, domain `rule-adoption/` (the path is in [CLAUDE.md](../../CLAUDE.md)) |
| Role | **producer and consumer**: this repo states the shape in [rules/REPOSITORY_LAYOUT.md](../../rules/REPOSITORY_LAYOUT.md) and its gate is what addresses the names |

## What this repo must do to stay conformant

- The contract binds only the names a **program** addresses: the three agent-rules filenames,
  `docs/contracts/<ID>.md` as pointers, the uppercase type prefixes, `README.md` and `LICENSE` at the
  root, and the ledger sitting where the stamp says. Everything else in the layout page is a target shape
  a repository adapts, and adapting it breaks nothing.
- **Renaming any of those names is a breaking change** to this contract, not a refactor - a second
  implementation is addressing them.
- Adding a fourth agent-rules filename is **additive**; removing one of the three is not.
- Rules 3 and 6 - the type prefix and the frozen archive - are checked by nothing today. That is recorded
  in the adoption row rather than claimed as enforcement.
