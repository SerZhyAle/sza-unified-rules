# S0012 - Delivery replay and queue-runner evidence

## Delivery follow-up, 2026-10-26

The already published release was installed with `claude plugin update sza@sza-unified-rules`:
`Plugin "sza" updated from 2026.1021.2 to 2026.1026.1 for scope user`, exit 0. No new deploy,
version cut, commit or push was needed or performed in this follow-up. The installed release is
commit `d4d69229511e2069d7d65ae592f971cd257221da`; the source reader changes first shipped in
`5bc65a5` (`2026.10.23.1` / `2026.1023.1`) and remain in the installed release.

| Observation | CANON_VERSION | Plugin version | Core digest | Reader equality | Replay / verdict |
| --- | --- | --- | --- | --- | --- |
| Installed before update | `2026.10.21.2` | `2026.1021.2` | `sha256:a68993630be3f1748d7d9be44540c2b2301dc5bd737e8ec1e058dfcc1b3c5d35` | 0 of 8 | reader exit 2; NOT DELIVERED, exit 1 |
| Source and installed after update | `2026.10.26.1` | `2026.1026.1` | `sha256:bfa85c0bf9bdb08e8d1d1aa6f2d12904b3ea2a745e9ba05df30aea1014b8a071` | 8 of 8 | reader PASS (44 cases); batch PASS (24 cases, 4 GAP); DELIVERED, exit 0 |

Both observed version pairs derive correctly. Before the update, 11 payload files existed only in
the source and 47 differed. After it, no payload files were missing or extra; one differed (the
historical project contrib record, outside the reader set and digest). The delivery command's
whole-tree count is informational; it does not certify equality of every payload file.

Fresh commands, run from the repository root:

| Command | Actual output | Exit |
| --- | --- | --- |
| `pwsh -NoProfile -File tools/tests/verify-delivery.ps1` before update | NOT DELIVERED; reader replay COULD NOT VERIFY (0 cases) | 1 |
| `claude plugin update sza@sza-unified-rules` | Updated `2026.1021.2` to `2026.1026.1` | 0 |
| `pwsh -NoProfile -File tools/tests/verify-delivery.ps1 -IncludeHarness` after update | DELIVERED; reader PASS (44); batch PASS (24, gaps=4) | 0 |
| `pwsh -NoProfile -File tools/tests/contract-reader.tests.ps1 -CatalogRoot <catalog>` | PASS (run=44 skipped=0) | 0 |
| `pwsh -NoProfile -File tools/tests/verify-delivery.tests.ps1` | PASS (run=7 skipped=0), including missing/changed/older/non-derived copies and missing-tree exit 2 | 0 |
| `pwsh -NoProfile -File <catalog>/task-flow/reference/day0-rehearsal.ps1 -Harness <absolute-source-root>/tools/harness` | Every check passed | 0 |

The first day-0 invocation used relative `-Harness tools/harness`: after changing into its throwaway
project the rehearsal could not locate `update.ps1`, and reported four failures (exit 1). The corrected
absolute-path invocation above passed. Neither the harness nor the catalog reference was changed to
obtain that result.

This closes the real installed-reader delivery observation for this release, including rung 4's
before/after pair and digest. It does not certify a future source change, a real agent child, wider
layout/writer fixtures or full TASK-FLOW conformance. The TASK-FLOW partial 0.2 adoption and its
2026-10-07 date remain unchanged. Rule 24 and the live-agent authorization remain owner decisions;
the original 2026-12-31 review dates remain in force.

## Historical source-side record, 2026-10-23

Verified source-side scope on 2026-10-23 with PowerShell 7.6.6 and Python 3.12.10 (`py -3`). At that time the
delivery itself and a real agent child are NOT claimed: both need a separate owner request, and none
was made. No deploy, version cut, plugin update, consuming-repository edit or live-agent run took place.
The S0011 results stay as recorded in [PROGRESS_CONTRACT-READERS-S0011.md](PROGRESS_CONTRACT-READERS-S0011.md),
except for the artifact hashes, which section "A defect found in the S0011 hash scheme" supersedes.

| Handoff item | Result and limits |
| --- | --- |
| 1. Delivery, rung 4 | `tools/tests/verify-delivery.ps1` judges an installed plugin copy against the source: the version pair and whether it derives (rule 2), the core digest (rule 3), the SHA-256 of every reader file in the catalog manifest, a whole-tree difference count, and the reader tests replayed with the installed tree as `-SourceRoot`. Run against the real installed consumer today it says NOT DELIVERED, exit 1. That is the recorded "before" row below. The "after" row is owed by the next authorized deploy: the same command must then say DELIVERED. Seven stand-in controls pass (section "Delivery controls"). |
| 2. TASK-FLOW section 5 | Catalog day-0 rehearsal re-run before any claim moved: exit 0, 29 PASS, 1 GAP (G1), 0 FAIL. G1 and G3 are re-read by the new suite in a bare project and both still hold (insert exits 1, queue listing exits 2). G6 stays narrowed: the rendered launcher's start step drops stale stop files and the lease directory (PASS) but leaves a leftover lock file in place (GAP). G2, G4 and G5 are not re-opened. No gap claim was changed. |
| 3. Outstanding rules of the TASK-FLOW row | The partial 0.2 adoption row and its 2026-10-07 date are unchanged. `tools/tests/batch-runner.tests.ps1` now drives the full batch runner, the rendered `r0.ps1` and the catalog reference R0 with FAKE children; it adds regression evidence for rules 22, 24, 25, 26, 27, 30 and 31 and a new finding on rule 24 (below). It starts no `claude` process, so it is not the live rung and certifies no lifecycle. Rules 1, 3, 4, 6, 9, 11, 13, 15-17, 19-20, 28-29, 32-34 and 38-40 remain unexercised by it. |
| 4. Scoped artifact set | Unchanged in scope: stamp/profile readers and the age ladder only. Wider layout and writer fixtures, and a real delivery, remain explicit outstanding evidence. A catalog manifest, source hashes or the current reader version still do not equal delivery or portfolio conformance. |

## The "before" row of rung 4 (2026-10-23, real installed consumer)

| Tree | CANON_VERSION | Plugin version | Core digest |
| --- | --- | --- | --- |
| installed (`sza@sza-unified-rules`, cache `2026.1021.2`, commit `87eaf19`) | `2026.10.21.2` | `2026.1021.2` | `sha256:a68993630be3f1748d7d9be44540c2b2301dc5bd737e8ec1e058dfcc1b3c5d35` |
| source working tree | `2026.10.21.2` | `2026.1021.2` | `sha256:a68993630be3f1748d7d9be44540c2b2301dc5bd737e8ec1e058dfcc1b3c5d35` |

Same version and the same digest, yet 0 of 8 reader files equal (5 differ, 3 missing: both
`tools/lib/` files and `tools/tests/contract-reader.tests.ps1`), 23 other files differ and 10 exist
only in the source. The reader tests replayed against the installed tree exit 2, `COULD NOT VERIFY`,
because the installed copy lacks the prerequisites. This is the failure the plugin version exists to
prevent: the change is on disk and unreleased, and the digest cannot see it because it covers
`rules/*.md` alone (RULE-DELIVERY rule 3). The change set is also uncommitted, so a deploy would stage
all of it at once; that is the owner's call, not this ticket's.

## A defect found in the S0011 hash scheme

The S0011 manifest fingerprinted reader source files by raw bytes. The working tree mixes line endings
(five of the eight files are LF only, three CRLF only) while the index holds LF, and an installed plugin
is a git checkout that takes the machine's `autocrlf` setting. Raw hashes therefore could not match an
installed copy of the same source: after a genuine delivery the replay would have failed with `Source
hash mismatch` and the rung-4 evidence could never turn green. A whole-tree comparison by raw bytes
also overstated the difference (119 files against 23 once line endings are normalized).

Fixed in the owner implementation: source files are now hashed with CRLF read as LF, the convention of
the core digest. `contract-reader.tests.ps1` generates and checks the hashes that way, refuses a manifest
without the new `sourceHash` key, and `verify-delivery.ps1` uses the same function. The catalog files
were regenerated with the owner command. Catalog-resident vector files are still hashed as stored.
These values supersede the table in the S0011 record:

| Artifact in `rule-adoption/vectors/` | SHA-256 |
| --- | --- |
| `manifest.json` | `D903BCCCC543E6380C57EC13A6DF44763FDD28311CA65D660EFF625B479A1741` |
| `reader-cases.json` | `FC22D56483242E5A80021F89E3702C313583F327EA6C28FE11D7E9F1A94A6845` |
| `reader-verdicts.json` | `AC68879B9CE6D14D8B0420FAE1F4C4976EB0B38FD6268AEAD7FECBC2AFFF0D29` |

## Finding: the batch runner does not re-offer a ticket that moved (rule 24)

TASK-FLOW rule 24: a ticket whose child failed but moved the status "is not dropped; it is offered
again, because it advanced". The rendered `r0.ps1` and the reference R0 do that. The full
`tools/harness/batch/run-spec-queue.ps1` does not: it adds every finished ticket to its excluded list,
moved or not (only a context handoff and a usage limit are exempt), although its own comment says only
a ticket with its starting status is dropped. Observed: S0001 (ok, Draft to In Progress) and S0002
(child-failed, Draft to In Progress) each ran once, while the ranking script alone still selects S0001.
`-MaxTickets` also counts tickets, not runs, which is the same choice seen from the other side.

This is a difference between a shipped tool and a draft contract. Which one moves is the owner's
decision and is NOT made here: change the runner (a behaviour change for every consumer of the full
runner, and for `-MaxTickets`), or amend rule 24 so the full runner is one pass per ticket per run.
Until then it is recorded as a dated exception in the catalog and the suite reports it as a GAP, which
turns into a PASS on its own the day the runner re-offers a moved ticket.

## Commands

| Command | Expected / actual | Exit |
| --- | --- | --- |
| `pwsh -NoProfile -File <catalog>/task-flow/reference/day0-rehearsal.ps1 -Harness tools/harness` | Baseline before any claim moved / `day0: every check passed`, 29 PASS, 1 GAP (rule 35, G1), 0 FAIL | 0 |
| `pwsh -NoProfile -File tools/tests/batch-runner.tests.ps1 -CatalogRoot <catalog>` | Fake-child suite, about 95 s / `PASS (run=24 skipped=0 gaps=4)`: GAP rule 24, G1, G3, G6 | 0 |
| The same suite against a copy of the harness whose tree kill is broken in both runners (`taskkill` without `/T`, `Process.Kill()` without the tree flag), no `-CatalogRoot` | Negative control: must fail / both "dies with its whole tree" cases `FAIL`, "the grandchild survived the timeout kill", `FAIL (run=23 skipped=0 gaps=4)` | 1 |
| `pwsh -NoProfile -File tools/tests/verify-delivery.tests.ps1` | Delivery controls, about 140 s / `PASS (run=7 skipped=0)` | 0 |
| `pwsh -NoProfile -File tools/tests/verify-delivery.ps1` | Real installed consumer, before any deploy / `NOT DELIVERED`: 8 reader files differ, same version with different content, replay exit 2 | 1 |
| `pwsh -NoProfile -File tools/tests/export-contract-vectors.ps1 -CatalogRoot <catalog>` | Regenerate with the normalized scheme / `Artifacts written`, `PASS (run=43 skipped=0)` | 0 |
| `pwsh -NoProfile -File tools/tests/contract-reader.tests.ps1 -CatalogRoot <catalog>` | Catalog replay / `PASS (run=44 skipped=0)` | 0 |
| `pwsh -NoProfile -File tools/tests/contract-reader.tests.ps1 -SourceRoot <installed cache> -CatalogRoot <catalog>` | Replay against the real installed consumer / `Missing prerequisite: tools/lib/schema-carrier.ps1`, `COULD NOT VERIFY (run=0 skipped=0)` | 2 |

## Delivery controls

`verify-delivery.tests.ps1` builds stand-in installed trees from the source and checks each way a copy
can fail to be a delivery. DELIVERED for an identical copy and for a copy converted entirely to CRLF
(the autocrlf case above). NOT DELIVERED, with the reason named, for a missing reader file, a reader
that differs under the same version ("a change shipped without moving the version reaches nobody"), an
older version, and a plugin version that does not derive from `CANON_VERSION`. Exit 2 for a tree that
does not exist. An installed tree that cannot compute its own core digest is a finding, not a setup
fault: a copy that cannot run its own gate has not been delivered whole.

## What the fake-child suite proves, and what it does not

Per runner, in disposable projects built with the day-0 scaffold: the child's argument vector reaches it
as one argument with spaces and quotes intact (rule 22); each journal row carries the rule-23 field set;
an unmoved ticket is dropped for the rest of the run and a child that failed but moved is journalled
`child-failed` with `moved` true (rule 24, the batch half is the GAP above); a child that overruns is
killed with its whole process tree, journalled `timeout`, its partial work stays on disk and the loop
goes on (rule 25); a stop file ends the loop after the ticket in hand, the shared file stays for the
siblings and is cleared by the next start with no live child, an instance file is consumed, a start
while children still drain is exit 3 and keeps the stop, and `-Stop -Kill` terminates the running child
tree (rule 26); exit codes 0, 2 and 3, a dry run that launches and writes nothing (rule 27); R0's start
step drops stale stop files and leases before the first child and makes no coordination call
(rules 30 and 31).

It does not prove anything a real agent does: no `claude` child ran, so the live rung of TASK-FLOW
section 4 is untouched. It does not exercise the lease reservation and identity of rules 28 and 29, the
pipeline of rule 32, the context handoff or the usage-limit wait of the full runner, or the ledger
rules 1, 3, 4, 6, 9, 11, 13, 15-17, 19-20 and 38-40. The batch cases need Windows (`taskkill`, CIM).

## Still owed, and why

- **Delivery (closed by the 2026-10-26 follow-up above).** `verify-delivery.ps1` must say DELIVERED after an owner-requested deploy, the plugin
  update and a check that the new version directory exists under the plugin cache. Record the real
  version pair and both rows. `deploy.ps1` stages everything with `git add .` and pushes the current
  branch, while the plugin follows `main`; run `deploy.ps1 -DryRun` and read the file list first.
- **A real agent child.** One supervised ticket, `-MaxTickets 1`, in a throwaway project: it spends
  quota and runs with `bypassPermissions`, so it waited for the owner.
- **The rule-24 decision** above, and the open G1, G3 and G6 of the harness.
- **Review before 2026-12-31** of both own exception rows; neither deadline was extended.

## Closed on 2026-10-26, remainder carried

The owner answered on 2026-10-26: change the runner (rule 24 stands as written), close G1, G3 and G6, run
one supervised real child now, and close S0012 with a successor. S0012 is Verified for the delivery of the
rule-adoption readers and moved to `PLAN/DONE`. The four bullets above, the wider layout/writer fixtures and
the unexercised TASK-FLOW rules are carried by S0013 (`PLAN/DONE/S0013_taskflow-harness-gaps-and-live-child.md`);
its evidence is [PROGRESS_CONTRACT-TASKFLOW-S0013.md](PROGRESS_CONTRACT-TASKFLOW-S0013.md). The rule-24
exception row of the catalog registry is closed there, and the 2026-12-31 review of the other one is not
extended.
