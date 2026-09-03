# SZA harness - the development-process layer, shipped

The executable side of the rules: a ticket journal with closing gates, ticket leases, cross-session
domain locks, the agent chat, the change journal, the document registry, the batch queue runner, the
capability ledger and the command-alias generator. Exported from `FastMediaSorter_mob_v2` (S2402),
where it drove 2 389 tickets before it moved here.

## The one seam

Everything a project owns lives in `<project root>/.sza-profile.json`, read by `_profile.ps1`:
working-directory roots, the ticket-id and spec-file grammars, the status vocabulary, the lock domain
table with its path rules, the probe shape, the runner's model policy, the status -> command map, the
capability ledger's dimension, the site's locales, and the entry-point map used in printed hints.
A key the profile omits keeps the default in `_profile.ps1`, and those defaults are the canon's own
conventions - `PLAN/`, `temp/`, `dev/CHANGELOG.md`, the `SZA_` environment prefix.

Copy `templates/.sza-profile.json` to the project root and edit it. Nothing else is edited: a script
body carrying a project's path, prefix or vocabulary is a value the profile can no longer override,
which is what `assert-portable.ps1` refuses.

## Running it

Every script resolves the project root itself, in this order: `SZA_PROJECT_ROOT`, the first
`.sza-profile.json` above the current directory, the first one above the harness, then the first
`.git` above the current directory. So a call works from anywhere inside the project, and a project
that keeps its own thin entry points can point them here without passing a root.

    pwsh -NoProfile -File <harness>/spec_catalog/select.ps1 -Id S0001 -Format json
    pwsh -NoProfile -File <harness>/locks/enter-code-lock.ps1 -Files "src/a.kt" -Reason "ticket"
    pwsh -NoProfile -File <harness>/assert-portable.ps1        # the layer's own gate

`SZA_PROFILE_PATH` points at an alternate profile file without touching the project's - for a test
harness or a migration.

## What is deliberately not here

- **The test suites.** A `*.tests/Run-Tests.ps1` exercises the harness through one project's paths,
  statuses and fixtures, so it belongs to that project: run there it proves the shipped layer works
  for that repository, which is exactly what an adopting project's own suite proves for its own.
- **Platform gates.** Anything tied to a build system, a language or a device stays with the project
  that has one.
- **Command bodies.** `.claude/commands/*.md` are a product's pipeline, not a shared mechanism; the
  alias generator ships, the commands it aliases do not.
