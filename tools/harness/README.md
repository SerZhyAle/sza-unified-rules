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

The dev-log default follows `HARNESS-PROFILE` rule 2 and its 2026-10-17 amendment. Without an explicit
`paths.changelog`, ledger shape `2` uses the stamp's `ledgerFile` or `dev/CHANGELOG.md`; shapes `4` and
`none` disable the log. Shapes `1` and `3` keep a separate optional `dev/CHANGELOG.md`, never the
stamp's root changelog or structured inventory. An explicit path wins; an empty path disables the
writer and completion's dev-log check, which report `NOT APPLICABLE` and create no log. Invalid stamp
JSON is refused. A repository not using the harness is not bound merely because it has no profile.

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

## Day 0 of a new project

A project with nothing yet runs `scaffold/init-task-flow.ps1 -Root .` once: it creates the stores the ticket
tools write into, the three plan files, `TICKET_TEMPLATE.md`, an **R0 launcher** (`r0.ps1`) rendered from the
project's profile, and the **forwarder** `tools/harness.ps1` - the project's one entry point here, resolved against
the newest installed plugin on every call (`pwsh -NoProfile -File tools/harness.ps1 spec_catalog/validate`; skip it
with `-NoForwarder` when the profile maps entry points of its own). Tickets are then created with `spec_catalog/capture-draft.ps1`, which writes the ledger row and
its spec file in one call - `insert.ps1 -Slug` alone writes the row and leaves the file for something else. The
launcher is standalone: it reads the ledger and the queue file and starts one fresh agent process per ticket, so
it keeps working on a machine that has no harness. The `task-flow-init` skill drives all of this with its
rehearsal; the rules are the `TASK-FLOW` contract in the shared catalog.

## What is deliberately not here

- **The test suites.** A `*.tests/Run-Tests.ps1` exercises the harness through one project's paths,
  statuses and fixtures, so it belongs to that project: run there it proves the shipped layer works
  for that repository, which is exactly what an adopting project's own suite proves for its own.
- **Platform gates.** Anything tied to a build system, a language or a device stays with the project
  that has one.
- **Command bodies.** `.claude/commands/*.md` are a product's pipeline, not a shared mechanism; the
  alias generator ships, the commands it aliases do not.

Portable reader regressions live outside the shipped harness: run
`pwsh -NoProfile -File tools/tests/contract-sync.tests.ps1` from the canon checkout. The suite generates
throwaway projects under `temp/S0008_contract-sync-implementation/`; it is not a catalog vector set or
proof that a cached plugin has received these changes.

The profile's optional `version` carrier and the stamp's optional `schemaVersion` are validated before
use, per the 2026-10-23 owned contract amendment. Absent carriers retain legacy wire 1.0. Unknown
MINOR additions remain readable; unsupported MAJOR values require updated tooling and refuse before
merge. Catalog reader artifacts are generated with `tools/tests/export-contract-vectors.ps1` and
replayed with `tools/tests/contract-reader.tests.ps1 -CatalogRoot <catalog>`.

## Portfolio queue

`portfolio/pq.ps1` runs one terminal worker over the registered repositories. State and logs live in
`SZA_PORTFOLIO_ROOT`, or `%USERPROFILE%\.sza\portfolio`. Register a repository with
`pwsh -NoProfile -File <harness>/portfolio/pq.ps1 register -Path <repository>`; it joins disabled. Review
`dry-run` and the repository's `r0 -DryRun`, then set `enabled: true` and an explicit `permissionMode`
in `repos.json` (per repository, or inherited from its top level). No permission mode is supplied by
default. `PORTFOLIO_QUEUE.md` sets the owner's order; `queue -Init -NoOpen` creates its first copy.

Run `start` in each worker terminal, up to `maxWorkers`. Each pass calls the repository runner for one
ticket with `-ModelPolicy shape`; the ticket's Complexity line chooses the model. A live repository
lock keeps workers apart unless its registration declares `concurrent: true`. A failed or unchanged
ticket is excluded until that worker ends. Usage-limit waits stay inside the existing runner.

`start -Drain` exits when no candidate remains (0 after a pass, 3 when none ran); `-MaxTickets N` caps
passes. Otherwise the worker waits for `pollSeconds` (60 by default), reading registry changes on each
round. `stop` ends workers after their current passes; `stop -Kill` also invokes the runner's stop
command and terminates pass process trees. A retained `STOP` is cleared on the next start after live
workers have exited. Ctrl+C terminates the worker and its pass tree.

`status` prints worker slots, today's UTC pass outcomes, the next ticket and STOP; `log -Last 40`
prints recent events across writers in timestamp order. Both support `-Json`; `log` also accepts
`-Repo <key>` and `-Ev <name>`. One row per pass goes to the portfolio's `runs.jsonl`, alongside the
repository runner's own `runs-pq<slot>.jsonl`. Dispatcher code never writes ticket status directly.

The operator's instruction is [portfolio/README.md](portfolio/README.md). `portfolio/install-shortcuts.ps1`
puts a `PQ ...` shortcut for each everyday command on the Desktop (`-Remove` takes them off).

Check this flow with `pwsh -NoProfile -File tools/tests/smoke-portfolio-runner.ps1` from the canon root.
It uses throwaway repositories and fake children; it starts no agent.
