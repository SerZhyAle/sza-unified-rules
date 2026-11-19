# Repository Guidelines

Read [`CLAUDE.md`](CLAUDE.md) in full; it is the authoritative agent contract and carries the canon pointer; the stricter file wins. This repository is the canon itself: an agent that does not load the plugin reads [`rules/INVARIANTS.md`](rules/INVARIANTS.md) first (`https://github.com/SerZhyAle/sza-unified-rules`). Commands, test tiers, style and commit rules are in `CLAUDE.md` and are not repeated here.

## Codex Operating Contract

[`CLAUDE.md`](CLAUDE.md) is the authoritative development contract for this canon repository; read and follow it in full. This section adds only Codex-specific routing.

- Project: SZA Unified Rules. Chat in Russian; repository artifacts, code, logs, and commits are English.
- Start with `README.md`, then `rules/README.md`; the work root is `P:\WEB\sza-unified-rules`.
- Name non-trivial work `CANONR-####_<slug>` and, when a ticket is needed, use `PLAN/CANONR-####_<slug>.md` (closed tickets keep their old `S####` ids; an old id still resolves through the ledger field `formerIds`).
- Put scratch material in `temp/<ticket>/`. No permanent read-only repository zones are declared; `P:\Contracts` is outside this checkout.
- Checks: after an ordinary edit only what takes 5 seconds or less (`CLAUDE.md`, "Working here"). `pwsh -NoProfile -File tools/tests/run-tier.ps1 -List` shows which gate or suite is fast. A release-tier or unmeasured suite runs only when the owner names it.
- Keep files below roughly 1,500 lines unless a documented cohesive exception exists. This tooling repository has no generic app build/run command or unified logger contract.
- Durable, non-obvious memory belongs under `memory/`. Read `memory/MEMORY.md` when relevant; do not duplicate facts already derivable from the repository or `CLAUDE.md`.
- Commit on the checked-out branch (`main`) and do not create a branch for a commit unless the owner asks: a deploy pushed from another branch reaches no consumer, because the plugin follows `main`. This repository takes no pull requests.
