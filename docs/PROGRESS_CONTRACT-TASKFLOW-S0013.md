# S0013 - TASK-FLOW harness gaps and the first real agent child

Recorded 2026-10-26 with PowerShell 7.6.6 on Windows. Everything below was verified in the canon working
tree before the owner asked for the deploy; the deploy and what the installed plugin then said are recorded
in "Delivery" at the end. The previous record, which carried this work, is
[PROGRESS_CONTRACT-DELIVERY-S0012.md](PROGRESS_CONTRACT-DELIVERY-S0012.md).

## What changed

The catalog moved first: TASK-FLOW went from 0.2 to **0.3, a correction** (section 5 and the second sentence
of rule 35 described harness behaviour that no longer holds) and then to **0.4** (rule 31, below); no ledger
field, status, plan-file shape or run-row field changed. Then the harness:

| Item | Change | Where |
| --- | --- | --- |
| Rule 24, full batch runner | the drop list holds only tickets that came back unmoved; a ticket that moved is ranked again. `-MaxTickets` and the "ticket N of M" line count finished picks through a separate counter, so a moved ticket offered again is a pick | `tools/harness/batch/run-spec-queue.ps1` |
| G1 | the atomic ledger writer creates its directory on the first write, so the bare `insert.ps1` in a project with no `PLAN/` succeeds | `tools/harness/spec_catalog/_lib.ps1` (`Write-JsonlFile`) |
| G3 | `release-queue.ps1 -List` of a missing plan file prints an empty listing and exits 0; `-Validate` and the other actions still exit 2 | `tools/harness/spec_catalog/release-queue.ps1` |
| G6 | R0's start step drops every leftover `<NAME>.LOCK` file and the contents of every `<NAME>.QUEUE` directory in `-LocksDir`, without judging the holder; the scaffold renders the profile's locks directory into the launcher | `tools/harness/scaffold/templates/r0-runner.ps1.tpl`, `scaffold/init-task-flow.ps1`; catalog `task-flow/reference/r0-runner.ps1` |
| Tests | the GAP cases for rule 24, G1, G3 and G6 are ordinary assertions now, plus one new case for `-MaxTickets`; the GAP mechanism stays for the next difference | `tools/tests/batch-runner.tests.ps1` |

Rule 31 also named reading the shared history and writing a journal note. Both are origin practices with no
file shape in the contract, so the rendered launcher and the reference R0 do neither. The owner decided on
2026-10-26 to take them out of the rule rather than define them, so the catalog went on to **0.4** (a
relaxation: rule 31 now asks R0 for the lock, lock-wait and lease cleanup only) and G6 is closed.

## Fresh commands

Run from the repository root; `<catalog>` is `P:\Contracts`.

| Command | Actual output | Exit |
| --- | --- | --- |
| `pwsh -NoProfile -File tools/tests/batch-runner.tests.ps1 -CatalogRoot <catalog>` | `PASS (run=25 skipped=0 gaps=0)` (was run=24, gaps=4) | 0 |
| the same suite, no `-CatalogRoot`, with `-SourceRoot` pointing at a copy of `tools/` whose `run-spec-queue.ps1` is the one from `HEAD` (negative control) | `FAIL batch: a child that failed but moved is offered again ... (rule 24) - S0001 moved (Draft to In Progress) and was not offered again`; `FAIL (run=24 skipped=0 gaps=0)`, the only failing case (run=24 because the reference-R0 case needs the catalog) | 1 |
| `pwsh -NoProfile -File <catalog>/task-flow/reference/day0-rehearsal.ps1 -Harness <absolute-source-root>/tools/harness` | `day0: every check passed`: 30 PASS, 0 GAP, 0 FAIL (was 29 PASS, 1 GAP) | 0 |
| `pwsh -NoProfile -File tools/check-contracts.ps1` | 0 errors, 2 warnings (the existing `CTR-STALE` and `CTR-LAG` classes) | 0 |

The first negative-control attempt could not set up (`COULD NOT VERIFY`, exit 2): the copy held only
`tools/harness` and the harness needs its sibling `tools/lib`. It was repeated with a full copy of `tools/`.

## The first real agent child (rung 3 of TASK-FLOW section 4)

Authorized by the owner on 2026-10-26: one supervised ticket, `-MaxTickets 1`, in a throwaway project.

- **Project.** Scaffolded by `scaffold/init-task-flow.ps1` into a temporary directory (exit 0), one ticket
  created with `capture-draft.ps1` (`S0001`, owner text: create `hello.txt` containing `hello`), `validate`
  exit 0 (9 OK), `r0.ps1 -DryRun` listed the ticket.
- **Command.** `pwsh -NoProfile -File .\r0.ps1 -MaxTickets 1 -TimeoutMinutes 20 -Model haiku`, the launcher's
  default `bypassPermissions` and its default prompt (one lifecycle step, then stop). A cheap model on
  purpose: the run tests the runner and the lifecycle shape, not model quality.
- **Result.** Exit 0 after 49 s. `r0: S0001 Draft -> Approved  ok (exit 0)`. One journal row, every rule-23
  field present: `statusBefore` Draft, `statusAfter` Approved, `moved` true, `outcome` ok, `exitCode` 0,
  `minutes` 1, `finishedAt` `2026-10-26T16:30:08`. The ledger row and the spec file's `**Status:**` header
  both say Approved. `-MaxTickets 1` ended the loop.
- **What the child did.** It ran the owner-inputs check and `validate`, replaced the template placeholders in
  sections 1 and 2 of the ticket with text taken from the owner's request, and moved the status through the
  harness `update` script. It did not create `hello.txt` or start another step, as the prompt says.

What this proves: a real `claude` child receives the prompt as one argument (rule 22), changes the ledger
through the harness, and the rendered launcher records the run and stops at the cap (rules 21, 23, 27, 33)
with no coordination call (rule 30); the day-0 order of rule 39 holds for this project. What it does not:
the timeout kill and the stop file with a real child (rules 25, 26), a failing real child (rule 24 with an
agent), any step after Approved, the lease and identity rules, or a real project.

Observations, not defects claimed:

- The child answered in Russian. The user-level `CLAUDE.md` loads into every child and the launcher passes
  no isolation flag, so a project run inherits the owner's settings.
- The child reported that `spec-to-audit` is not in its list of registered skills, found it in the plugin
  cache by path and followed it by hand. The default prompt names that skill, so a child should not have to
  look for it.

## TASK-FLOW adoption row

Left at **partial 0.2, dated 2026-10-07**. One Draft to Approved step of one cheap-model child touches the
launcher side of rules 21-23, 27 and 30 and rules 33 and 39. Of the rules S0012 listed as unexercised by the
fake-child suite (1, 3, 4, 6, 9, 11, 13, 15-17, 19-20, 28-29, 32-34 and 38-40) it touches only 33 and 39. The
row text gained a dated addendum so it no longer says that no real child ever ran and that G1 and G3 are
open; the row's own sentences stay as written on 2026-10-07 and the addendum says which ones it supersedes.

## Not done

- **No commit, version bump, deploy or plugin update.** Until the owner asks, the installed plugin
  (`2026.1026.1`) still has the old runner and the old tools: the same version carries different content.
  `tools/tests/verify-delivery.ps1` still says DELIVERED (exit 0, 8 of 8 reader files equal, reader replay
  PASS 44) because it judges the reader set, and these changes are outside it; its informational whole-tree
  count shows 7 files that differ, six of them these changes. Read the whole-tree line, not the verdict, to
  see that this release has not arrived. `deploy.ps1 -DryRun` (exit 0) lists 16 changes on `main` and would
  move the pair to `2026.10.26.2` / `2026.1026.2`; `deploy.ps1` stages the whole working tree and pushes
  the current branch.
- Wider layout/writer fixtures of the rule-adoption reader set, and the unexercised TASK-FLOW rules.
