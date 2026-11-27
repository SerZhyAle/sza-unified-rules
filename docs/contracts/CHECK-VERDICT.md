# CHECK-VERDICT - pointer

| Field | Value |
| --- | --- |
| Contract | `CHECK-VERDICT` |
| Version | 0.16, draft |
| Home | Shared catalog, `automated-checks/`; resolution is in CLAUDE.md |
| Role | Scoped producer: `tools/tests/contract-sync.tests.ps1` and `tools/tests/contract-reader.tests.ps1` only |

The suites report one final verdict with executed test counts, run remaining cases after a failure,
and refuse unavailable prerequisites with exit 2. Follow section 2, the 2026-10-17 amendment, the
2026-10-18 clarification and the 2026-10-29 count grammar (0.14, item A): each suite is a self-test of its own
assertions, so it prints a test verdict line `<name>: PASS|FAIL|COULD NOT VERIFY (run=N skipped=M)` in which
every executed case counts once and `skipped` counts the selected cases that did not execute. Neither suite
has groups or subtests, so the `FAIL (n)` form and the `only <groups>` suffix are not produced. Other scripts
retain their documented exit vocabularies; this scoped adoption does not certify them. Catalog vectors are not
available for the verdict grammar itself; see the S0008 audit for local evidence.

0.16 (2026-11-27, items F and G) pairs `PASS WITH ADVISORIES` with exit `3`, a closing run excepted, and lets a further
count token follow a space or a comma. Neither suite prints that word and the canon ships no script that does, so no
code moved.
