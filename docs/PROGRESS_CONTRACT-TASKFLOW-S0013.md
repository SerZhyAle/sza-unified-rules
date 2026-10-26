# S0013 - TASK-FLOW harness gaps and the first real agent child

Recorded 2026-10-26 with PowerShell 7.6.6 on Windows. Everything from "What changed" to "The first real
agent child" was verified in the canon working tree before the owner asked for the first deploy; that
deploy and what the installed plugin then said are recorded in "Delivery". The owner then asked to finish the
ticket and deploy again: item 5, the adoption row and the second delivery follow. The previous record, which carried this work, is
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

First left at **partial 0.2, dated 2026-10-07**: one Draft to Approved step of one cheap-model child touches
the launcher side of rules 21-23, 27 and 30 and rules 33 and 39, and of the rules S0012 listed as unexercised
(1, 3, 4, 6, 9, 11, 13, 15-17, 19-20, 28-29, 32-34 and 38-40) it touches only 33 and 39. The row text gained
a dated addendum so it no longer said that no real child ever ran and that G1 and G3 are open.

Advanced the same day, after item 5 below, to **partial 0.5, dated 2026-10-26**, because the condition the
ticket set (the row advances only as far as the new evidence covers its outstanding rules) is now met: every
rule on that list is either exercised by a command or classified as conduct. The row stays *partial* for
what the evidence does not cover, and says what that is. The 2026-10-07 sentences stay in the row as
history, under a lead sentence that supersedes the ones about unexercised rules, G1, G3, G6 and real children.

## Item 5 - the remaining rules and the layout fixtures

Asked for on 2026-10-26 ("finish S0013, and deploy after"). Two new suites, both started from the repository
root with `pwsh -NoProfile -File`:

| Command | Actual output | Exit |
| --- | --- | --- |
| `tools/tests/ledger-rules.tests.ps1` | `ledger-rules-tests: PASS (run=24 skipped=0 gaps=3)`, about five minutes | 0 |
| `tools/tests/layout-gate.tests.ps1` | `layout-gate-tests: PASS (run=15 skipped=0)`, 20 s | 0 |
| `tools/tests/batch-runner.tests.ps1 -CatalogRoot <catalog>` (unchanged, rerun) | `batch-runner-tests: PASS (run=25 skipped=0 gaps=0)` | 0 |
| the ledger suite against a copy of `tools/` with the blocker resolver scraping every id and the evidence relocation step replaced by `exit 0`, `-Case 'rule 9\|rule 19'` (negative control) | `FAIL rule 9 ... ids in prose were read as blockers: S0007,S0008,S0009`; `FAIL rule 19 ... update.ps1 -Id S0001 -Status Implemented exited 1`; `FAIL (run=2 failed=2)` | 1 |

**The ledger suite** drives the shipped tools in throwaway projects: the three files and their paths and an
absent archive (rule 1); five creators started at once (2, 38); spent and burned ids (2, 11); the record and
a writer that keeps a field it does not know (3); header and ledger written together, and a hand-edited
header (4); the closed vocabulary, `Archived` from every status and a revival (6); the blocker tokens read
and prose not (9); ten ways a ledger fails validation and an id gap that the burned list accounts for (10);
the plan files, their order, the move to the ready file and back, the ship step and the soft archive
(14-17); evidence cited from `temp/` and the refusal of what cannot move (19); the step markers and the
refusal to guess (20); a ticket a sibling holds, and the agent id of each child (28, 29); the prompt (32);
and the shape of R0 against the full runner (34). Each rule that forbids something has a command that is
refused.

**Three differences between the text and the tools** came out of it. Each is a `GAP` line that flips to PASS
the day the tool changes, and a row in section 5 of the contract (0.5) and in the catalog's exceptions:

- **G7, rule 4.** `spec-next-preflight.ps1` reports a spec header that differs from the ledger and then calls
  the *file* authoritative; the rule says the reader trusts the ledger.
- **G8, rule 6.** `update.ps1` lets a `Block*` ticket leave to any status (`Draft`, `BlockExternal`,
  `Implemented` was accepted). The ledger records no level to leave from, so the tool cannot enforce "advancing
  exactly one level".
- **G9, rule 29.** The full runner gives a child its own agent id only as `--session-id`, and only when the
  CLI's `--help` lists the flag. For a CLI that does not, an id leaked into the launcher's environment is the
  child's. Against a CLI that lists the flag every child got a distinct id and the leaked one reached none.

Neither the tool nor the rule was changed for these: which side moves is the owner's call, as it was for rules
24 and 31, so they are carried by S0014.

**What no command exercises**, and the contract now says so (0.5, section 4): rule 13 (park, do not fix),
rule 40 (grow a runner against a measurement) and the habit half of rule 20 bind the conduct of an agent or of
the owner. Also not exercised: the in-flight half of rule 28 (a `claim-lost` child killed after launch) and
any lifecycle step past `Approved` with a real agent.

**The layout fixtures** build throwaway repositories and run `tools/check-compliance.ps1` on them: REPO-LAYOUT
rule 4 (README and LICENSE, in three spellings), rule 5 (shapes 1 to 4, each with a passing and a failing
repository, and no shape declared), the docs index, rule 1 (a root agent-rules file in each of the three
names, and a same-named file below the root counting for nothing), rule 2 (a pointer, the older
`CONTRACT_<ID>.md` spelling, a long file with no id, the index exempt) and rule 6 (the harness archive step
moves a spec file with its text unchanged beyond the status line the ledger owns, and a revival leaves it
readable at the path its row names). Rule 3, the type prefix, is checked by nothing and stays unexercised, as
the adoption row says.

**Not part of this change:** the suites do not run in any gate of the deploy. They are replayed against the
installed plugin by `verify-delivery.ps1 -IncludeHarness`, which now takes about eight minutes.

**A catalog incident found on the way.** Between 16:44 and 17:12 the catalog's `_meta/REGISTRY.md` lost its
last 758 lines (the exceptions, the planned and reserved section and the campaign sections), apparently when
another session saved the file after changing one `INPUT-PARITY` row for Tourist Android. A copy this session
had kept at 16:44 held them; they were appended back without changing a byte of what was there, and
`check-contracts.ps1` says 0 errors. What the other session wrote between 16:44 and the cut is not in the
copy, so a change made to those 758 lines in that window would be missing; nobody has been asked.

## Delivery

Requested by the owner on 2026-10-26 after reading `deploy.ps1 -DryRun` (exit 0: 16 changes on `main`, pair
`2026.10.26.1` / `2026.1026.1` to `2026.10.26.2` / `2026.1026.2`).

- Before the deploy `tools/tests/verify-delivery.ps1` said DELIVERED (exit 0, 8 of 8 reader files equal)
  while the installed tree still carried the old runner: the verdict judges the reader set and these
  changes are outside it. Its whole-tree line said 7 files differ, six of them these changes. Read that
  line, not the verdict, to see that a harness change has not arrived.
- `pwsh -NoProfile -File deploy.ps1 -Message <msg> -Yes`: gate OK, `bump-canon-version` wrote the new pair,
  commit `2f1801f` (`Canon update 2026-10-26: TASK-FLOW 0.4, batch runner rule 24, G1/G3/G6 closed`, with the
  co-author trailer), pushed `d4d6922..2f1801f` to `origin/main`, exit 0.
- `claude plugin update sza@sza-unified-rules`: `Plugin "sza" updated from 2026.1026.1 to 2026.1026.2 for
  scope user`, exit 0; the cache directory `2026.1026.2` exists. A session needs a restart to load it.
- `pwsh -NoProfile -File tools/tests/verify-delivery.ps1 -IncludeHarness`: installed and source both
  `2026.10.26.2` / `2026.1026.2`, both pairs derive, digests equal, 8 of 8 reader files equal, whole tree
  0 only in source, 0 only in installed, 0 differ; reader replay PASS (44), batch replay against the
  installed tree PASS (25, gaps=0); `DELIVERED`, exit 0.

This section was written after the commit, so it is the one change not in `2f1801f`.

### Second delivery (item 5)

Requested by the owner on 2026-10-26 with the request to finish the ticket ("and deploy after"). The dry run
(exit 0) showed 7 changes on `main` and the pair `2026.10.26.2` / `2026.1026.2` moving to `2026.10.26.3` /
`2026.1026.3`.

- `pwsh -NoProfile -File deploy.ps1 -Message <msg> -Yes`: `check-rules` OK (22 core docs, 14 contrib docs),
  the catalog check 0 errors, `bump-canon-version` wrote the new pair, commit `a83f3a2`
  (`Canon update 2026-10-26: TASK-FLOW 0.5, ledger and layout suites, S0013 closed`), pushed
  `2f1801f..a83f3a2` to `origin/main`, exit 0.
- `claude plugin update sza@sza-unified-rules`: `Plugin "sza" updated from 2026.1026.2 to 2026.1026.3 for
  scope user`, exit 0. A session needs a restart to load it.
- `pwsh -NoProfile -File tools/tests/verify-delivery.ps1 -IncludeHarness` (474 s): installed and source both
  `2026.10.26.3` / `2026.1026.3`, both pairs derive, digests equal, 8 of 8 reader files equal, whole trees
  0 only in source, 0 only in installed, 0 differ; replays against the installed tree: `contract-reader-tests:
  PASS (run=44 skipped=0)`, `batch-runner-tests: PASS (run=25 skipped=0 gaps=0)`, `ledger-rules-tests: PASS
  (run=24 skipped=0 gaps=3)`, `layout-gate-tests: PASS (run=15 skipped=0)`; `DELIVERED`, exit 0.

This second section is again written after the commit; it went in with a documentation-only commit that
moves no version.

## Not done

All of it is carried by S0014 (review due 2026-12-31, not extended):

- G7, G8 and G9: for each, change the tool or change the rule.
- Whether TASK-FLOW leaves draft. It is `0.5, draft`. `1.0` is the promise that the shape will not change;
  the shape changed four times in 19 days, a second adopter has not run the lifecycle, and three differences
  are open. The owner asked on 2026-10-26; no decision was given.
- REPO-LAYOUT rule 3 (the type prefix), which nothing checks.
- The in-flight half of rule 28, and a real agent past `Approved`.
