# Repository Guidelines

## Project Structure & Module Organization

- `rules/` is the canonical SZA guidance; `rules/contrib/` holds per-project records.
- `skills/` contains plugin skills. Keep a skill's trigger-facing instructions in `SKILL.md` and put larger, on-demand material in its adjacent `references/` directory.
- `hooks/` contains enforcement scripts, `hooks.json`, and their smoke tests.
- `tools/` contains PowerShell validation, deployment, and harness utilities. `docs/contracts/` provides pointers to the external contract catalog; `templates/` holds adoption templates.
- `.claude-plugin/` defines this repository's Claude Code plugin and marketplace metadata. `CANON_VERSION` is the source version for releases.

## Build, Test, and Development Commands

Run commands from the repository root with PowerShell 7:

```powershell
pwsh -File tools/check-rules.ps1
pwsh -NoProfile -File hooks/tests/smoke-hooks.ps1
pwsh -NoProfile -File hooks/tests/smoke-prefilters.ps1
pwsh -File tools/check-contracts.ps1
```

`check-rules.ps1` is required for any `rules/` change and validates links, references, numbering, and house style. The two smoke suites cover hook decisions and the registered Git Bash pre-filters. Run `check-contracts.ps1` when modifying catalog-related guidance or contract pointers; the external catalog normally lives at `P:\Contracts` (or `SZA_CONTRACTS_ROOT`). Use `deploy.ps1` for releases; it performs the version bump. Do not manually edit `CANON_VERSION` or the plugin `version`.

## Coding Style & Naming Conventions

Write code, commit messages, console output, and repository documentation in concise English. Use four-space indentation for PowerShell, `Verb-Noun.ps1` names for scripts where appropriate, and descriptive kebab-case names for Markdown files such as `CONTRACT_REPO-LAYOUT.md`. Comments explain non-obvious reasons, not line-by-line mechanics. Preserve a skill's YAML frontmatter and make its `description` match phrases users would actually request.

## Testing Guidelines

Add or update smoke cases with every hook behavior or pre-filter change. Test both denied and allowed inputs: false positives can cause guards to be disabled. Assert advisory and rewrite hooks by their output, not merely their zero exit status. Do not claim a change is complete without fresh command output.

## Commit & Pull Request Guidelines

Recent commits use short imperative subjects, for example `Canon update 2026-09-22` or `Reorganize the contracts catalog by function`. Keep commits focused. PRs should explain the rule or behavior changed, list validation run, link the relevant issue/spec when one exists, and include before/after output or screenshots for user-visible behavior. Land shared rule fixes here first; consuming repositories should receive them through the plugin release.

## Codex Operating Contract

[`CLAUDE.md`](CLAUDE.md) is the authoritative development contract for this canon repository; read and follow it in full. This section adds only Codex-specific routing.

- Project: SZA Unified Rules. Chat in Russian; repository artifacts, code, logs, and commits are English.
- Start with `README.md`, then `rules/README.md`; the work root is `P:\WEB\sza-unified-rules`.
- Name non-trivial work `S####_<slug>` and, when a ticket is needed, use `PLAN/S####_<slug>.md`.
- Put scratch material in `temp/<ticket>/`. No permanent read-only repository zones are declared; `P:\Contracts` is outside this checkout.
- Default canon check: `pwsh -NoProfile -File tools/check-rules.ps1`. For hook changes, also run `hooks/tests/smoke-hooks.ps1` and `hooks/tests/smoke-prefilters.ps1`.
- Keep files below roughly 1,500 lines unless a documented cohesive exception exists. This tooling repository has no generic app build/run command or unified logger contract.
- Durable, non-obvious memory belongs under `memory/`. Read `memory/MEMORY.md` when relevant; do not duplicate facts already derivable from the repository or `CLAUDE.md`.
