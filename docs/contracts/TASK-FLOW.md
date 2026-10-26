# TASK-FLOW - pointer

| Field | Value |
| --- | --- |
| Contract | `TASK-FLOW` |
| Version | 0.4, draft |
| Home | the shared contracts catalog, domain `task-flow/` (the path is in [CLAUDE.md](../../CLAUDE.md)) |
| Role | **shared implementation, partial**: `tools/harness/` is the ticket tool and the full runner every adopting repository uses, and `tools/harness/scaffold/` stands up day 0 of a new project. The owner is `shared`, so this repository edits the contract only through the canon session |

## What this repo must do to stay conformant

- `tools/harness/spec_catalog/` is the writer of the ledger, the archive and the burned list. A change to a
  field, an id rule, a status value or the plan-file line shape is a **contract change** (the catalog moves
  first), not a tidy-up - a second implementation is reading those files.
- `tools/harness/scaffold/init-task-flow.ps1` and `spec_catalog/capture-draft.ps1` implement rules 35-37 and 5.
  The R0 launcher the scaffold renders (`scaffold/templates/r0-runner.ps1.tpl`) has a twin in the contract's
  `reference/r0-runner.ps1`: the rehearsal runs the same checks against both, so a change to rules 21-27 is made
  in both, with the catalog moving first.
- The ticket template (`scaffold/templates/ticket-template.md`) must keep the section the approval gate reads
  (`### 3.3 Owner inputs (Approval gate)` with a bold-field `Related tickets` bullet); the rehearsal approves a
  ticket made from it.
- Gaps are recorded in the contract (section 5). G1, G3 and G6 are closed: the bare `insert.ps1` creates its
  plans directory, `release-queue.ps1 -List` lists a missing plan file as empty, and the launcher's start
  step drops leftover lock files and lock-wait entries (rule 31 no longer asks R0 for the origin's
  shared-history read and journal note). Each closure is a harness change and ships with the plugin version
  bump.
- `batch/run-spec-queue.ps1` is the full-featured form of rules 21-29. Neither it nor the launcher may drift
  from rules 21-27 without the catalog moving first.
- S0011 re-read section 5 and the partial adoption row without advancing its 2026-10-07 verification.
  S0012 (closed 2026-10-26) handed remaining harness/runtime evidence to S0013. Reader and completion tests
  certify no live-agent flow; S0013 recorded one real-agent step of one ticket and nothing more.
- `tools/tests/batch-runner.tests.ps1` drives the full runner, the rendered launcher and (with a catalog)
  the reference R0 with fake children: argument vector, journal row, timeout kill of the whole tree, stop
  files, exit codes, R0's start step. It starts no agent, so it is regression evidence and not the live rung.
  The full runner now offers a ticket that moved again, as rule 24 says (the owner chose to change the
  runner, not the rule, on 2026-10-26), so `-MaxTickets` counts finished picks and not distinct tickets.
  Details: [PROGRESS_CONTRACT-DELIVERY-S0012.md](../PROGRESS_CONTRACT-DELIVERY-S0012.md).
