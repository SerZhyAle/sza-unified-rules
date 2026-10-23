# S0008 - Contract synchronization evidence

Date: 2026-10-23. Scope: the canon working tree; no commit, release, tag, upload or deploy.
Source changes implement accepted clauses. A locally verified reader is not an installed-plugin delivery.

## Inventory and coordination

Read the current catalog governance, contract amendments through 2026-10-23, all six existing own
adoption rows and own exceptions, and every local contract pointer. There were four behind rows,
one partial TASK-FLOW row and one not-applicable INSTALL-TRUST row; none were pending or unreadable.
The four owned interface contracts remain REPO-STAMP, HARNESS-PROFILE, REPO-LAYOUT and RULE-DELIVERY.

S0007 accepted the proposals; S0009 updated the contract core; neither proves this implementation.
S0001-S0006 own earlier UI decisions; S0010 owns product positioning. Their archived records and other
repositories are untouched. S0011 carries remaining compatibility, documentation and artifact work.

No document registry exists in this checkout. Affected records: harness README, contract pointers,
docs index, this evidence record, local S0008/S0011 and own catalog registry rows. The rule corpus,
generated site maps and consuming products' registries are unchanged. This absence is now explicit
DOC-INTERNAL-QUALITY debt; a published index must never enumerate the ignored PLAN corpus.

## Clause-to-surface audit

| Contract and clauses | Surface and outcome |
| --- | --- |
| HARNESS-PROFILE 0.12 section 3 rules 1-3/7; 2026-10-17 amendment | `_profile.ps1` derives shape-2 dev-log paths from the stamp, disables shapes 4/none and keeps a separate engineering log for shapes 1/3. Explicit, empty and null profile values win. Invalid stamp JSON refuses rather than applying defaults. Writer and completion respect a disabled log. |
| HARNESS-PROFILE section 3 rules 4-6 | Unknown dotted lookups and lock ranks are unchanged. Objects merge by name; null now replaces as required. The future-version acceptance hole is retained as a tested limitation and scoped exception, S0011. Whole-contract adoption stays partial. |
| REPO-STAMP 0.12 section 2 rule 4; RULE-DELIVERY 0.12 section 5 rules 4-5 | Compliance reads a parseable reconciliation date, else adoption date. A differing digest with unknown age is an error. Equal digests owe no date finding. Messages name the clock source and reconciliation/full-adoption remedy. |
| REPO-STAMP section 2 rules 1-3/5/7-9 | Root lookup, required-key/JSON checks and unknown-key tolerance are unchanged. Carrier absence and missing unknown-role diagnostic remain excepted in S0011. This run does not rewrite the real stamp, dates or digest. |
| RULE-DELIVERY section 5 rules 1-3/6-7 | Deploy and the sole version writer are unchanged; no real version cut or delivery was performed. Producer Implements remains 0.9; reader Reads is 0.12. Digest coverage and ahead-version check are unchanged. |
| REPO-LAYOUT 0.11 section 4 rules 1-7 | Root agent files, ID pointers, README/LICENSE and declared ledger shape reviewed. Declared ticket/release-file exceptions are recognized. Frozen DONE records are not rewritten; no prefix or archive enforcement is claimed. |
| CHECK-VERDICT 0.13 section 2 rules 1-5/9/11-13; amendments 2026-10-17/18 | Adoption is limited to `tools/tests/contract-sync.tests.ps1`. Final stdout is a verdict with `run=N skipped=M`; unavailable prerequisites return 2, assertion failures return 1, all cases continue. No hidden runner skips or child-check aggregation exists. Rules 6-8/10/14-15 have no advisory/narrowing/aggregator/product-command surface in this test producer. Legacy scripts are outside this adoption. |
| DOC-INTERNAL-QUALITY 0.10 section 2 rules 1-7; 2026-10-17 amendment | Applicable to technical developer/agent documentation. Rule links/references/style have a green scoped canon gate. Corpus-wide registries, reverse coverage, anchor/asset checks, offline safety and generated-derivative synchronization remain partial and excepted until 2026-12-31, remediation S0011. No reference product gates were run here. |
| DOC-EXTERNAL-QUALITY 0.12 section 3 rules 1-7, sections 8-9 and 2026-10-17 amendment | Not bound for the present scope: no end-user manual, hosted help center or product website. Technical forker/plugin documentation is assessed above. No translated URL, search, screenshot, SEO or browser claim. Reassess before introducing such a corpus. |
| RULES section 15; canon CONTRACTS section 4 | Contract-sync instructions distinguish temporary debt from permanent supported variants. Generated synchronization specs retain exception/recommendation rights, responsible project, independent release blockers and an inventory including current/pending/unparsed/ahead/not-applicable rows. No unconditional conformance is required. |
| TASK-FLOW 0.2; INSTALL-TRUST scope | Existing TASK-FLOW partial 0.2 verification date remains 2026-10-07; two completion regressions do not certify the batch runner. INSTALL-TRUST remains not applicable: no installer/elevation/download-warning surface. |

## Seven-point compatibility audit

| Law | Evidence and limit |
| --- | --- |
| Names | Stamp/profile reads and map merges use keys in `_profile.ps1` and `check-compliance.ps1`. Existing registry table parsing by position in check-contracts/contract-lag is excepted; S0011 owns reordered-column negatives. |
| Higher minor | Unknown JSON keys survive/are ignored without affecting recognized values; tests include an unknown stamp/profile key. No new stamp schema is introduced. |
| Higher major | Stamp has no carrier; profile carrier is accepted without dispatch. Both remain explicit exceptions, not a successful refusal claim; S0011 requires owned contract amendments first. |
| Unknown enum | Existing strict product-role fallback is unchanged, but its missing diagnostic remains excepted. New path derivation branches only on documented ledger shapes. |
| Absence and data | Missing configuration never deletes state. Writer tests preserve SHA-256 of existing user ledgers and prove duplicate writes do not change the dev-log. Disabled tools create no log. |
| Bounds | No new indexed artifact is consumed. Generated specification inventory uses a complete finite row list; malformed JSON refuses. Existing positional registry limitations remain visible. |
| Defaults | HARNESS-PROFILE section 3 rule 2 and the accepted amendment define every changed ledger-shape default. REPO-STAMP rule 4 defines date fallback/unknown age. Generated tests exercise omission, explicit, empty and null overrides. |

## Fresh evidence

| Command or replay | Expected / observed | Exit |
| --- | --- | --- |
| `pwsh -NoProfile -File tools/tests/contract-sync.tests.ps1` | PASS / `contract-sync-tests: PASS (run=49 skipped=0)` | 0 |
| Same suite with `-SourceRoot temp/S0008_contract-sync-implementation/baseline` | Old readers must fail / 22 failed cases; `FAIL (run=49 skipped=0)` | 1 |
| Same suite with `-SourceRoot temp/S0008_contract-sync-implementation/missing` | Missing prerequisites must not pass / `COULD NOT VERIFY (run=0 skipped=0)` | 2 |
| `pwsh -NoProfile -File tools/harness/assert-portable.ps1` | No product literals / PASS, 82 scripts | 0 |
| PowerShell parser over the six changed/new scripts | No syntax errors / PASS, 6 files | 0 |
| `python temp/S0008_contract-sync-implementation/verify_records.py` | Consistent records / PASS, 20 local links, 3 artifact hashes, catalog identity/foreign rows, retained TASK-FLOW row, unchanged delivery files and 5 acceptance items | 0 |
| `git diff --check -- docs skills tools` | No whitespace errors / no findings | 0 |
| `pwsh -NoProfile -File tools/check-rules.ps1` | Canon valid / OK, 22 core and 14 contrib docs | 0 |
| `pwsh -NoProfile -File tools/check-contracts.ps1` | No new errors / 0 errors, 2 existing warning classes (unverified adoption and lag) | 0 |
| `pwsh -NoProfile -File tools/contract-lag.ps1 -Product sza-unified-rules` | Honest scoped rows / 2 current, 1 behind, 4 partial, 2 n/a, 0 pending/unparsed | 0 |
| `pwsh -NoProfile -File tools/contract-lag.ps1 -Product sza-unified-rules -EmitSpec -OutFile temp/S0008_contract-sync-implementation/generated-sync.md` | Specification with full inventory and rights / spec written | 0 |

The baseline replay uses HEAD copies of the five changed source scripts and the same current suite.
Its failing count includes diagnostic-provenance checks as well as changed behavior. It proves the
new suite can fail, not that every baseline failure represents a separate product defect.
For native exit evidence from a PowerShell command wrapper, propagate `exit $LASTEXITCODE`.

These are generated throwaway-project regressions, not published catalog conformance artifacts.
The applicable domains provide no independent vector set for these readers. Full catalog artifacts,
live-agent execution, installed-consumer replay and a fresh real delivery remain unverified under S0011.
No UI/browser/clipboard/sealing surface changed; no device or visual acceptance is claimed.
Hook behavior is unchanged, so hook smoke suites were not required.

## Catalog write and remaining scope

Only `_meta/REGISTRY.md` changed in the external catalog: five own adoption rows refreshed, three
scoped rows added, four existing own debt rows given explicit remediation/review details, the local
skill/reader discrepancy closed, and one DOC-INTERNAL-QUALITY exception added. All foreign product
rows and contract-definition rows were compared byte for byte and preserved. No contract text,
proposal decision, credential or anchor changed. Existing 2026-12-31 debt deadlines are unchanged.

No new contract correction is proposed: the observed default/age defects were implementation failures
against already accepted clauses. Existing carrier and table-reader findings are handed to S0011.
The accepted stamp-reader delivery request is implemented in source; publishing it still needs a
separate owner request and consumer replay. Other products' dependency exceptions remain theirs to close.

Registry change SHA-256: before `466827ee4805c275d78fba369aa4edcdaf59421a64dfadd9eeff7fbbc521f809`,
after `8936c307bcdc61162f7eedade8ca8d03bc7c88143e1109843634684c35e16a4e`.
The external write is live; it is not covered by this repository's Git diff.

## Artifact identity

No contract or delivery version was bumped. SHA-256 of the verified implementation artifacts:

| Artifact | SHA-256 |
| --- | --- |
| `tools/tests/contract-sync.tests.ps1` | `b936252b04e8c156cb2a5a253fa685a3eb15538bbf26202a8e7241b19df3d5ed` |
| `tools/check-compliance.ps1` | `3926117dd43b45aeabcdbb839298a393f16099687bd1dbbfa9159c3c86d2b34d` |
| `tools/harness/_profile.ps1` | `866b2332d15eb6c0cd002820ec325b2e64e92d9847aa7c697211bb340f3482ca` |

## Last Audit

2026-10-23, scoped implementation verified with explicit exceptions. Remaining whole-contract claims
are partial or behind as shown above; S0011 carries them. No P0/P1 defect remains in the changed flows.
The complete documentation contract and actual plugin delivery remain unverified.
