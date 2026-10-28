# TASK-FLOW - pointer

| Field | Value |
| --- | --- |
| Contract | `TASK-FLOW` |
| Version | 0.9, draft |
| Home | the shared contracts catalog, domain `task-flow/` (the path is in [CLAUDE.md](../../CLAUDE.md)) |
| Role | **shared implementation, partial**: `tools/harness/` supplies the ticket tools, repository runner and day-0 scaffold; `tools/harness/portfolio/` supplies the S0015 dispatcher, registry, queue, rank and event log. Remaining portfolio features belong to S0016. The owner is `shared`, so this repository edits the contract only through the canon session |

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
  bump. G7, G8 and G9 are closed by ticket S0014 (0.6): the picker calls the catalog authoritative (rule 4),
  rule 6 is relaxed to permit leaving `Block*` to any active status matching `update.ps1`, and the batch runner
  sets `SZA_AGENT_ID` and isolates the child environment regardless of CLI `--session-id` support (rule 29).
  The GAP lines in `tools/tests/ledger-rules.tests.ps1` became ordinary assertions (PASS, run=24 skipped=0
  gaps=0). REPO-LAYOUT rule 3, in-flight rule 28 and real agent past Approved are accepted conduct boundaries.
- `batch/run-spec-queue.ps1` is the full-featured form of rules 21-29. Neither it nor the launcher may drift
  from rules 21-27 without the catalog moving first. It is also the runner every portfolio pass invokes and
  whose dry run decides a joining repository's readiness (rules 42 and 49). Gap G10 (0.7) is open: the
  rendered launcher and the contract's reference R0 exit 3 on a ledger with no open ticket before they reach
  `-DryRun`, where rule 27 says a dry run exits 0.
- S0011 re-read section 5 and the partial adoption row without advancing its 2026-10-07 verification.
  S0012 (closed 2026-10-26) handed remaining harness/runtime evidence to S0013. Reader and completion tests
  certify no live-agent flow; S0013 recorded one real-agent step of one ticket and nothing more.
- `tools/tests/batch-runner.tests.ps1` drives the full runner, the rendered launcher and (with a catalog)
  the reference R0 with fake children: argument vector, journal row, timeout kill of the whole tree, stop
  files, exit codes, R0's start step. It starts no agent, so it is regression evidence and not the live rung.
  The full runner now offers a ticket that moved again, as rule 24 says (the owner chose to change the
  runner, not the rule, on 2026-10-26), so `-MaxTickets` counts finished picks and not distinct tickets.
  Details: [PROGRESS_CONTRACT-DELIVERY-S0012.md](../PROGRESS_CONTRACT-DELIVERY-S0012.md).
- `tools/tests/ledger-rules.tests.ps1` drives the shipped ledger, plan-file, evidence and runner-coordination
  tools in throwaway projects (rules 1-4, 6, 9-11, 14-17, 19-20, 28-29, 32, 34, 38) and
  `tools/tests/layout-gate.tests.ps1` builds fixture repositories for REPO-LAYOUT rules 1, 2, 4, 5 and 6; both
  replay against the installed plugin under `verify-delivery.ps1 -IncludeHarness`. Rules 13 and 40 and the
  habit half of rule 20 bind conduct, and no command exercises them (the contract's section 4 says so).
  Details: [PROGRESS_CONTRACT-TASKFLOW-S0013.md](../PROGRESS_CONTRACT-TASKFLOW-S0013.md).
- The portfolio dispatcher in `tools/harness/portfolio/` implements S0015's scoped first version:
  terminal workers, repository locks, the registry and queue rank, one repository-runner pass at a time,
  stop, status and log. Registry, queue and event readers are covered by `portfolio-queue.tests.ps1` and
  `portfolio-events.tests.ps1`; `smoke-portfolio-runner.ps1` exercises the dispatcher with fake children.
  Its event names come from the contract's companion `EVENTS.md` and are forever (rule 57).
  Account-wide limits, multiple agent providers, cross-repository blockers, occupancy and resource
  tokens are deferred to S0016; no full adoption of rules 41-64 is claimed. The dispatcher never writes a ticket record or a status
  directly (rule 43; a status moves only through the repository's own tool, rule 4; a `Draft` its analysis
  files goes through the capture tool, rule 5) and never releases, tags or publishes anything (S0015 R20).
- `spec_catalog/capture-draft.ps1` and the ticket template write `**Complexity:**`; `validate.ps1` warns
  on a missing or unassessed line (rule 51). The `adopt-canon` and `task-flow-init` skills end day 0 with
  registering the repository (rule 50). The `**Verify:**` resource classification of rule 62 belongs to
  S0016. The attended real-agent portfolio pass remains the S0015 phase-06 evidence gate.
- A change to the registry file and its agent records (rules 41-42), the queue-file grammar (rule 44), the
  run row (rule 46), the stop files (rule 47), the hold file (rule 48) or the event envelope (rule 53) is a
  **contract change**: the catalog moves first.
- `pq rank` writes the registry's `rank` and `pq arrange` sorts each scheduled package of the queue file by it
  (0.8, rule 44's writer table). `pq arrange` moves only row lines and only inside their own package; `--` and
  `hold` are not touched. Covered by `portfolio-queue.tests.ps1` (cases `registry: Set-PqRepoRank ..` and
  `queue-write: arrange ..`).
- Rule 52, the qualified token `Blocker: <repoKey>:<id>`, is enforced by the dispatcher only. The local
  picker, the closing gate and a manual session ignore it; the ledger suite case `rule 9 and 52` in
  `tools/tests/ledger-rules.tests.ps1` is what proves the local readers ignore it and never read it as a
  local id.
