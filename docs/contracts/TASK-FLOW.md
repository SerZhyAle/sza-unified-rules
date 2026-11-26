# TASK-FLOW - pointer

| Field | Value |
| --- | --- |
| Contract | `TASK-FLOW` |
| Version | 0.53, draft |
| Home | the shared contracts catalog, domain `task-flow/` (the path is in [CLAUDE.md](../../CLAUDE.md)) |
| Role | **shared implementation, partial**: `tools/harness/` supplies the ticket tools, repository runner and day-0 scaffold; `tools/harness/portfolio/` supplies the dispatcher, registry, queue, rank and event log. The open differences are the dated exceptions of the registry. The owner is `shared`, so this repository edits the contract only through the canon session |

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
  whose dry run decides a joining repository's readiness (rules 42 and 49). Gap G10 (0.7) closed on
  2026-11-23 (CANONR-0172): a dry run of the rendered launcher and of the contract's reference R0 prints the order
  of an empty ledger and exits 0 (rule 27).
- The registry row is `partial 0.44`. The amendments 0.29 to 0.43 and the one code item 0.28 left owed were read
  clause by clause on 2026-11-25 (CANONR-0190, static, nothing above 5 seconds run): 36 differences. Those in code are
  tickets CANONR-0194 (0.32, 0.33), CANONR-0195 (0.37, 0.39), CANONR-0196 (0.35, 0.38, 0.40, 0.41) and CANONR-0197
  (0.29, 0.30, 0.31, 0.42), and each stands as a dated exception in the registry until its ticket closes it. Those in
  the text, with the reference R0, were accepted the same day as 0.44 (CANONR-0198). The release-tier suites that cover
  the amendments have not run. No rule asks the plan tool to re-lay a repository's own queue file in the portfolio
  order (rule 15 forbids a script to reorder its rows), so that is no gap.
- 0.46 (2026-11-26, CANONR-0203, section 22): repeat parks count toward the idle hold. A finished
  `Implemented` blocker releases a dependent that names it in `**Accepts Implemented:**`, and a local blocker
  unchanged since the park holds the dependent until a status move or an explicit dependency check. The
  status writer checks current question and action marks when leaving `BlockQuestions`. Covered by
  `idle-hold`, `picker-eligibility` and `taskflow-ledger-conformance`. The PQShell build and the full
  back-link suite are release checks.
- 0.47 (2026-11-26, CANONR-0204, section 23: a per-launch ceiling of the repository runner and its context handoff,
  rules 25 and 46) is implemented by the repository runner. The `pass-ceiling` suite exercises the threshold decision.
- 0.48 (2026-11-26, CANONR-0202, section 24, rules 6 and 8): a new entry into `Verified` needs an executed-check line
  in the `## Last Audit` block and no open `RELEASE` item. `check-audit-recorded.ps1 -NewStatus Verified` applies it
  from `Assert-ClosingGates` (patterns in `_audit-evidence.ps1`), and `list-thin-verified.ps1` reports the rows that
  predate it. Covered by `verified-evidence`.
- 0.49 (2026-11-26, CANONR-0214, section 25, rule 7): a quiz may close a `Q:` by the recommendation, recorded as
  applied by recommendation, never a `DO:`. The `spec-quiz` skill and the spec-to-audit quiz reference carry it; the
  exceptions have one home, `rules/AI_USAGE.md` section 1. `quiz-list.ps1` prints the lines several tickets share
  (`quiz-shared`).
- 0.50 (2026-11-26, CANONR-0206, section 26, rules 42 and 48, `EVENTS.md` section 13): a text detector reads the last
  40 lines of a pass that exited non-zero, and the reset time comes from the same lines (`batch/_limit-tail.ps1`, read
  by `_limit-hold.ps1` and `portfolio/lib/agents.ps1`); `Resolve-RunOutcome` never names a pass that moved the ticket
  `limit-hit`; the hold and `agent.hold` carry `resetSource`, a guessed `until` is cut to six hours, and a hold
  written before 0.50 reads by its `until`; `agent.fallback` for a limit is written when the hold starts and ends,
  never per ranking; `PQ-LIMIT01` reports a guessed hold longer than six hours. Covered by `limit-detector`.
- 0.51 (2026-11-26, CANONR-0208, section 27, `EVENTS.md` section 14): a runner writes `no-progress` where it wrote
  `no-progress-or-claim-lost`, and the idle walk (`batch/_idle-runs.ps1`, PQShell's copy) counts either spelling; the
  portfolio row drops `priceAsOf`; `Reclaim-PqDeadWorker` ends an `orphaned` row at the pass's last `pass.beat` or the
  repository lock's write time, with `detectedAfterMinutes`, from facts `Set-PqWorkerPass` records at the launch;
  `portfolio/lib/offer-limit.ps1` holds a ticket whose newest three offers of 24 hours advanced nothing (it replaces
  the drop-lift thrash and feeds `PQ-THRASH01`); `pass.beat` is written once per five minutes and an unchanged blocker
  result once (`run/xrepo-said.json`); `Invoke-PqLogArchive` zips day files older than 14 days and every log reader
  reads the zips; the live-log path kinds and the findings `PQ-STALL01` and `PQ-SAFE01` are gone. Covered by
  `pq-records` (fast, run); the edited release-tier suites (`portfolio-s0016`, `portfolio-events`,
  `portfolio-conformance`, `portfolio-usage`) were not run, and PQShell was not built.
- The CANONR-0197 exception and gap G11 are closed (2026-11-26): the rendered R0 launcher
  (`scaffold/templates/r0-runner.ps1.tpl`, filled by `init-task-flow.ps1`) and this repository's `r0.ps1` no longer
  rank `Implemented`; the campaign form of `portfolio/spec-draft.ps1` records `campaign` or the inherited `robot`
  (it holds the projection back by `SZA_PQ_NO_PROJECTION`, and `SZA_PQ_IN_SYNC` stays the queue sync's mark alone);
  `portfolio/lib/loop.ps1` looks at every enabled repository around a pass, and the first worker to see a robot-filed
  row announces it (`run/intake-announced.json`); PQShell's idle walk applies the lift (source edit, built with the
  next panel build). Covered by `ticket-source`, `idle-hold`, `portfolio-limit-reset` and `catalog-lock-order`
  (fast, run); `batch-runner.tests.ps1` and the day-0 rehearsal were not run.
- 0.52 (2026-11-26, CANONR-0211, section 28, rules 3, 4, 14-17 and 35): `spec_catalog/_plan-ledger.ps1` keeps the
  package, order and shipment history of finished work on the ledger row; `release-queue.ps1 -Show Ready|Done` renders
  them, and the ready and done files an older tool wrote are imported and never written. `_archive-reason.ps1` is the
  one reason gate of every archiving path; `ship-package.ps1` archives with `archive.ps1 -FromShipment`. The runner
  rewrites a differing spec header from the ledger. The unused plan-form pilot recorder is deleted and `closed_at` is
  no longer written. Covered by `release-plan-ledger`, `archive-reason`, `header-mirror`, `catalog-lock-order` and
  `release-queue-seed` (fast, run); the edited release-tier suites and the day-0 rehearsal were not run.
- 0.53 (2026-11-26, CANONR-0210, section 29, rules 6, 8 and 19): a new entry into `Implemented`, `Verified` or
  `BlockNeedUserTest` of a spec file above 40960 bytes needs a relative evidence link into the ticket's `evidence/`
  folder. `check-spec-size.ps1` applies it from `Assert-ClosingGates` (the link test is `Find-SpecEvidenceLink` in
  `_spec-size.ps1`). Covered by `spec-size`.
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
  Rules 41-64 were read on 2026-11-15 and the gaps of that read closed (S0080, S0082 to S0084); the amendments made
  since are in the list below. The dispatcher never writes a ticket record or a status
  directly (rule 43; a status moves only through the repository's own tool, rule 4; a `Draft` its analysis
  files goes through the capture tool, rule 5) and never releases, tags or publishes anything (S0015 R20).
- `spec_catalog/capture-draft.ps1` and the ticket template write `**Complexity:**`; `validate.ps1` warns
  on a missing or unassessed line (rule 51). The `adopt-canon` and `task-flow-init` skills end day 0 with
  registering the repository (rule 50). `portfolio/lib/resources.ps1` reads the `**Verify:**` line of rule 62.
  The attended real-agent portfolio pass remains the S0015 phase-06 evidence gate.
- A change to the registry file and its agent records (rules 41-42), the queue-file grammar (rule 44), the
  run row (rule 46), the stop files (rule 47), the hold file (rule 48) or the event envelope (rule 53) is a
  **contract change**: the catalog moves first.
- `pq rank` writes the registry's `rank` and `pq arrange` sorts each scheduled package of the queue file by it
  (0.8, rule 44's writer table). `pq arrange` moves only row lines and only inside their own package; `--` and
  `hold` are not touched. Covered by `portfolio-queue.tests.ps1` (cases `registry: Set-PqRepoRank ..` and
  `queue-write: arrange ..`).
- Rule 52 (amended in 0.19, S0042): a ticket whose only blocker is a qualified token `Blocker: <repoKey>:<id>` (or
  `Блокер: <repoKey>:<id>`) may stand in `BlockByOtherTask`. The closing gate (`check-block-note.ps1`) accepts the
  qualified token when entering `BlockByOtherTask`; `Get-BlockerLinks` remains local-only so a reader that does not
  know the qualified form ignores it and never mistakes `<id>` for a local id (the ledger suite case `rule 9 and 52`);
  the local picker (`preview.ps1`) holds a `BlockByOtherTask` ticket whose only unverified blocker is a qualified token
  (`blocker-cross-repo`) so it is never released early by a local run; and the portfolio dispatcher (`picker.ps1`,
  `xrepo.ps1`) resolves the qualified token from both the spec file and `statusNote` against `<repoKey>`'s ledger and
  archive and releases the ticket by the blocker's status (`Test-BlockerReleased`).
- S0035 (0.17): provider limit holds carry parsed reset times and do not persist detector matched text (rule 48,
  EVENTS 3.4/3.6); dispatcher waits for primary provider reset when <= 15 min for `In Progress` tickets
  (`dispatch.skip` reason `limitResetNear`, rules 42 and 48).
- S0039 (0.18): a `BlockQuestions` note is the question itself - `check-block-note.ps1` refuses a transition into
  `BlockQuestions` whose `statusNote` carries no literal `Q: ..?` token (rule 7), naming where a non-question
  impediment belongs instead. Rolled out contract-first: catalog rule, `reference/day0-rehearsal.ps1`, the vectors
  and the repository tests moved in the same pass; rows standing in `BlockQuestions` without the token are
  unaffected. The canon's unattended-answer policy moved with it: a researched, ticket-reversible recommendation is
  taken and recorded under `### Assumed (unattended, <date>)` (skills `spec-to-audit`, `spec-quiz --assumed`).
- S0042 (0.19): `BlockByOtherTask` accepts `Blocker: <repoKey>:<id>` (rule 52, above), and `BlockQuestions` accepts a
  literal `DO:` token in `statusNote` (paired with a `- **DO:** <action>` bullet in `### 3.3 Owner inputs (Approval gate)`)
  for an owner action that precedes implementation (device, desk, or an account in an outside console), while
  `BlockNeedUserTest` (rule 8) stays strictly for post-implementation verification of completed, audited work.
- 0.25 (2026-11-13): the queue sync heals a ledger row whose spec file was moved by hand between `paths.specsDir`
  and `paths.specArchiveDir` (rule 68): `Repair-PqTicketFileRefs` in `portfolio/lib/queue-file.ps1`, called by
  `Sync-PqRegisteredQueues` right after the rule 65 registration, rewrites `file` through `update.ps1 -File` only when
  exactly one file of the same name exists in the other directory, and records `ticket.relinked` or `queue.row` kind
  `unrelinked` (EVENTS 3.5 and 3.3). Checked by a direct call on a scratch project; no fast fixture yet.
- 0.26 (2026-11-13): a blocker carries a back-link to every ticket it holds and its status moves release them
  (rule 69). `spec_catalog/block-links.ps1` (`-Link`, `-Release`, `-Check`, `-Sweep [-AllRepos]`, `-DryRun`) is
  called after the write by `update.ps1`, `bulk-update.ps1`, `close.ps1` and `archive.ps1` through
  `_block-links-hook.ps1` (`SZA_BLOCK_LINKS=0` switches the call off); a cross-repository release runs `-Check` in
  the other repository, whose own `update.ps1` moves the ticket. The same edit makes `_blocker-links.ps1` read
  `**Depends on:**` as its line (rule 9). Covered by `tools/tests/block-links.tests.ps1` (6 cases, release tier).
- Read rule by rule against 0.27 on 2026-11-15 (canon ticket S0077, static reading, nothing run): rules 43-45, 52, 54,
  55, 57, 60, 62 (tokens), 63-70 and the amendments to rules 7, 8, 9, 23 and 26 are implemented; rules 41, 42, 46
  (row format), 47, 48, 49, 51, 53, 58, 59 (library only, not wired), 61 and 62 (event data) diverge in part, and
  30 of the 83 catalogued event names have no emitter. The registry row stays `partial 0.27`; each gap is a dated
  exception there with a ticket (S0080 the `$stopPath` defect in the dispatch loop, S0082 rules 41-64 and `EVENTS.md`,
  S0083 the ledger side, S0084 the readers broken by rule 70). Rule 61's concurrent-repository sentence contradicts the
  owner's S0034 decision and the code and is filed as a proposal in the catalog, not changed here.
- 0.27 (2026-11-15): a finished ticket's spec file leaves the working folder with its status (rule 70).
  `Move-SpecToStatusHome` in `spec_catalog/_lib.ps1` moves the spec file and its folder into `paths.specArchiveDir` on
  entry into `Implemented`, `Verified` or `BlockNeedUserTest` and back on reopen; `update.ps1`, `close.ps1` and
  `bulk-update.ps1` call it after the gates, under the ledger lock, and write the new `file` in the same write.
  `archive.ps1` now moves into `paths.specArchiveDir` and leaves a file already there alone. Equal directories, an
  alternate catalog, a collision or a pattern the profile does not admit leave the file in place. Covered by
  `tools/tests/spec-home-move.tests.ps1` (4.97 s, at the 5-second line: run by name).
- 0.28 (2026-11-15): the contract text was brought to what the harness does (README section 9, `EVENTS.md` section 5):
  reserved keys, path kinds, halt modes and 26 event names, the `concurrent` sentence of rule 61, `seconds`,
  `status-drift` -> `statusDrift` in rule 46's outcome table (`ConvertTo-PqPassEndOutcome` in `portfolio/lib/loop.ps1`
  maps it from 2026-11-16, checked by a direct call), and eight readings of the ledger rules. The row stays
  `partial`; its exceptions of 2026-11-15 are closed or narrowed in the registry as the evidence allows.
- 0.29 (2026-11-18): rule 24 states the idle hold. `Test-IdleRunHeld` in `batch/_idle-runs.ps1` is the one test the
  picker (`spec_catalog/spec-next-preflight.ps1`) and the plan-file marker (`spec_catalog/_lib.ps1`) ask: two counted
  unmoved runs hold a ticket, `limit-hit`, `claim-lost-before-launch` and `launch-failed` are stepped over, and a spec
  file written more than 60 seconds after the newest counted run lifts the hold for one pass.
  `spec_catalog/block-links.ps1` keeps a blocker's spec file time when it writes a back-link. Covered by
  `tools/tests/idle-hold.tests.ps1` (8 cases, fast); PQShell's own copy of the walk applies the lift too
  (`portfolio/gui/src/PortfolioState.vb`, CANONR-0197).
- 0.30 (2026-11-18, S0108): a ledger row records how the ticket was born (README section 10, `EVENTS.md` section 6).
  `spec_catalog/insert.ps1` writes the optional field `source` (`owner`, `robot`, `import`, `inbox`, `campaign`), resolved
  by `spec_catalog/_ticket-source.ps1`: its `-Source`, else `import` for the queue sync's own child, else the variable
  `SZA_TICKET_SOURCE` (`batch/run-spec-queue.ps1` sets `robot` for the child of a pass, `portfolio/lib/inbox-ingest.ps1`
  sets `inbox`, the campaign form of `portfolio/spec-draft.ps1` sets `campaign` when none is set), else `owner`.
  `validate.ps1` warns on a value outside the list. The dispatcher does not read the field
  for `ticket.created` yet. Covered by `tools/tests/ticket-source.tests.ps1` and one assertion in
  `taskflow-ledger-conformance.tests.ps1`.
- 0.31 (2026-11-18): the cap on robot-filed tickets (rule 41, `robotDraftCap`) is counted per repository per local day
  from the ledger (README section 11, canon ticket S0109). `Get-PqRobotFiled` in `portfolio/lib/ledger-watch.ps1`
  reads the rows with `source` `robot` created on the day; `Get-PqIntakeCapped` in `portfolio/lib/loop.ps1` gives the
  `Draft` rows past the cap to every rank as excluded, so no worker keeps a count. The notice looks at every enabled
  repository around a pass (`Get-PqRobotLook`, `Request-PqIntakeAnnounce` of the same file, CANONR-0197). Covered by
  the two robot-filed cases of `tools/tests/portfolio-limit-reset.tests.ps1` (fast).
- 0.32 (2026-11-18, S0139): the grade 0-9 and the routes by grade (README section 12, `EVENTS.md` section 8). One parser
  of the line, `spec_catalog/lib/complexity-grade.ps1`, serves the runner (`Get-TicketComplexity`), the dispatcher
  (`Get-PqTicketLevelInfo`) and the regex of both capture tools. `portfolio/lib/agents.ps1` reads `routes`
  (`Get-PqAgentRoute`, `aboveCeiling` in `Select-PqAgent`, the route's model and effort in the pass arguments, claude
  included); `portfolio/lib/rater.ps1` is rule 71 - the raters before the pick and the escalation after a failed pass,
  both writing the header line and `ticket.complexity`, `rater.fail` when no record answers; `registry.ps1` checks
  `routes`, `raters` and `escalateBy`. `portfolio/rate-ticket.ps1` runs the rater by hand and the anchor report. Covered
  by `tools/tests/complexity-grade.tests.ps1` (fast). The live registry carries the routes, the Haiku rater
  and `escalateBy` 2 from 2026-11-18.
- 0.33 (2026-11-18, S0140): the parallel axis (README section 13, `EVENTS.md` section 9). `Get-SzaParallelFlag` reads
  the `**Parallel:**` line; `Get-PqAgentRoute` carries the row's `parallel`; `Get-PqClaudeParallel` applies it to a
  flagged ticket at a build stage and `Get-PqClaudePassArgs` hands the runner `-Parallel`; `run-spec-queue.ps1` appends
  the opt-in with `--append-system-prompt` (`Get-ParallelOptIn`) and keeps Workflow allowed under the context trial;
  `pass.launch` carries `parallel`; `registry.ps1` refuses another value or another agent. Case 10 of
  `complexity-grade.tests.ps1`. The live registry names no `parallel` yet.
- 0.34 (2026-11-18, S0123): `rank.result` `excluded` carries nine counts (README section 14, `EVENTS.md` section 10).
  `dropped`, `settling`, `levelNotAllowed`, `resource` and `deviceLevel` had no writer and are no longer written,
  `Get-PqRank` lost its `-TicketBlocked` parameter (no caller), and `awaits-release` is counted under `awaitsRelease`
  instead of `idleHold` (`portfolio/lib/rank.ps1`). Checked by a direct call of `Get-PqRank`; the three suites that
  assert the count list (`portfolio-queue`, `portfolio-named-start`, `release-wait`) are release tier and were not run.
- 0.35 (2026-11-18, S0130): inside a registered repository the order of tickets is the line order of its rows in
  the portfolio queue file (rules 18 and 44). `spec_catalog/_portfolio-order.ps1` reads those rows without loading a
  portfolio library, and `spec-next-preflight.ps1` ranks them first unless it runs as the dispatcher's picker
  (`SZA_PQ_PICKER=1`), which walks the rows itself; the payload's `order_source` names the file. The repository's
  plan files keep package, status and time, and their line order ranks only the tickets the queue file does not
  name. Covered by `tools/tests/portfolio-order.tests.ps1` (4 cases, fast). The rows of the repository's own file
  stay where they are (rule 15).
- 0.36 (2026-11-18, S0135): the run row no longer carries `built` (rules 23 and 46). The runner no longer reads the
  disclosure sentence; `pq report` counts "closed without a build" from the ticket ledgers against each repository's
  release ledger (`Get-RlClosedSinceBuild`, `Get-PqClosedUnbuilt`; case 11 of `tools/tests/release-ledger.tests.ps1`).
- 0.38 (2026-11-19, owner order): the dispatcher works the root of a blocker chain (rule 52 amended, section 16).
  `Get-PqRank -HeadLift` offers the root in the refused ticket's place through the repository's own picker, so every gate
  of a queue row still applies; `Get-PqLiftTarget` (`portfolio/lib/inbox.ps1`) finds the root with the walk of `pq inbox`;
  the loop, `pq dry-run` and `pq status -Next` pass it, and the printed line, `xrepo.resolve` and `dispatch.pick` name the
  root and the outcome. Checked by `tools/tests/portfolio-blocker-lift.tests.ps1` (7 cases, fast) and a live `pq dry-run`;
  the release-tier rank suites (`portfolio-queue`, `pq-rank-cost`, `portfolio-named-start`) were not run.
- 0.37 (2026-11-19, S0152): one prefix migration per repository (rule 2, section 15). `spec_catalog/rename-prefix.ps1
  -Prefix <SIX> [-DryRun] [-AllRepos]` renames the open tickets inside the ledger lock and lists each old id in
  `formerIds`; the status tool, `close.ps1`, `complete.ps1`, `bulk-update.ps1`, `block-links.ps1` and the dispatcher's
  ledger reader resolve an old id (the resolvers that do not are listed in CANONR-0195). Covered by
  `tools/tests/rename-prefix.tests.ps1` (4 cases, fast). Each repository runs the tool in its own adoption ticket.
- Rule 16 steps 2 and 3 have a caller from 2026-11-18 (canon ticket S0131): `spec_catalog/ship-package.ps1` runs
  `release-queue.ps1 -Ship` for every numbered ready block up to the marker, puts the marker on the next package
  and then runs `archive.ps1` for the `Verified` rows in neither plan file. The release skill calls it in Phase 8
  and `deploy.ps1` calls it for the canon after `publish -State live`. Rows under `--` are not shipped. Covered by
  the `ship-package` case of `tools/tests/ledger-rules.tests.ps1` (release tier, not yet run) and by case 9 of
  `tools/tests/deploy-release-ledger.tests.ps1`.
- 0.42 (2026-11-24, CANONR-0175): rule 18 fixes the eligible set of the ranking - the seven queued statuses, never
  `Implemented`, in every run mode. `spec_catalog/spec-next-preflight.ps1` no longer adds `Implemented` unless it runs as
  the dispatcher's picker, so `/spec-next`, a repository's own runner and `pq` rank one set and agree with the queue
  file. An explicit id (`/spec-all <id>`, an id list given to the runner) does not rank and still works an
  `Implemented` ticket, while `pq start -Ticket` keeps the picker's gates (rule 66) and refuses it; the `Implemented`
  entry of `commands.statusCommands` is read by the explicit path and by `release-plan.ps1` only. The PQShell panel's list of runnable statuses drops `Implemented` too (source edit, not
  compiled). Covered by `tools/tests/picker-eligibility.tests.ps1` (5 cases, fast).
- 0.43 (2026-11-24, CANONR-0176): rule 67, the hold of a ticket that waits for the release, is withdrawn and keeps its
  number - after 0.42 no ranking offers an `Implemented` ticket, so nothing was left to hold. `batch/_release-wait.ps1`
  and its suite `tools/tests/release-wait.tests.ps1` are deleted; `spec-next-preflight.ps1` no longer names the reason
  `awaits-release`; `run-spec-queue.ps1` no longer writes the run-row field `awaitsRelease` and takes no code-tree stamp
  after a pass; `_idle-runs.ps1` no longer reads it; `portfolio/lib/rank.ps1` no longer writes the `excluded` count
  `awaitsRelease` (eight counts, `EVENTS.md` section 11). The idle hold of rule 24 is unchanged. Checked by
  `picker-eligibility.tests.ps1` and `idle-hold.tests.ps1` (fast), a dry run of the runner and a direct call of
  `Get-PqRank` (8 checks, 4 of them fail against the previous `rank.ps1`); `portfolio-queue.tests.ps1` was edited and
  not run (release tier).
- 0.44 (2026-11-25, CANONR-0198): the canon's proposal accepted as filed - ten places of the text brought to the shipped
  harness, a neutral end of a pass escalates nothing (the code gap is CANONR-0194), and the reference R0 drops
  `Implemented`; no harness code moved. The catalog's day-0 rehearsal ran against this tree (exit 0, one GAP, G11).
