# TASK-FLOW - pointer

| Field | Value |
| --- | --- |
| Contract | `TASK-FLOW` |
| Version | 0.2, draft |
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
- Gaps against 0.2 are recorded in the contract (section 5): the bare `insert.ps1` and `release-queue.ps1 -List`
  still meet a project with no stores (G1, G3; worked around by the scaffold), and R0's start step in the
  launcher is narrower than the origin's (G6). Closing one is a harness change and ships with the plugin
  version bump.
- `batch/run-spec-queue.ps1` is the full-featured form of rules 21-29. Neither it nor the launcher may drift
  from rules 21-27 without the catalog moving first.
- S0011 re-read section 5 and the partial adoption row without advancing its 2026-10-07 verification.
  S0012 owns remaining harness/runtime evidence. Reader and completion tests certify no live-agent flow.
- `tools/tests/batch-runner.tests.ps1` drives the full runner, the rendered launcher and (with a catalog)
  the reference R0 with fake children: argument vector, journal row, timeout kill of the whole tree, stop
  files, exit codes, R0's start step. It starts no agent, so it is regression evidence and not the live rung.
  It records one place where the full runner differs from rule 24 (a ticket that moved is not offered again
  in the same run) as a GAP and a dated exception; whether the runner or the rule moves is the owner's
  decision. Details: [PROGRESS_CONTRACT-DELIVERY-S0012.md](../PROGRESS_CONTRACT-DELIVERY-S0012.md).
