# RELEASE-LEDGER - pointer

| Field | Value |
| --- | --- |
| Contract | `RELEASE-LEDGER` |
| Version | 0.2, draft |
| Home | the shared contracts catalog, domain `release-ledger/` (the path is in [CLAUDE.md](../../CLAUDE.md)) |
| Role | **owner, writer and reader**: the canon ships the one writer, the probes, `pq releases` and the PQShell Releases tab; every application repository keeps a ledger |

## What this repo must do to stay conformant

- `tools/harness/releases/release-ledger.ps1` is the only writer of the three data files (rules 2, 4, 5) and renders
  `RELEASES.md` after every write (rule 10); `build` keeps one row per package, flavor and kind, `history.jsonl` is only
  ever appended to, and a field the writer does not own is kept (rule 11).
- The fold of rule 7 lives in `tools/harness/releases/_lib.ps1` and is the one used by the writer, `pq releases`
  (`tools/harness/portfolio/lib/releases.ps1`) and, through `pq releases -Json`, PQShell. It leaves out the legacy Play
  rows that rule 12 names, counts them as `legacyApi` and never edits them; the render marks them.
- Every probe in `tools/harness/releases/_probes.ps1` only reads (rule 8): `gh` read verbs, `msstore submission get`
  behind an allow-list, a transient Play edit that is deleted, public endpoints. A missing tool or credential is
  `unverified` on the output and never an event.
- The Play probe writes no event (rule 12): the track configuration and the release lifecycle of its one track are
  printed as readings scoped to that track and its version codes, and a Play version is `live` only by a `confirm`
  with the public store page.
- Nothing the writer records names a secret, an absolute local path or a machine (rule 9): an artifact outside the
  repository is recorded by its file name only.
- A change to the file shapes, the state vocabulary or the fold is a catalog change first, then the code.

## Evidence

`tools/tests/release-ledger.tests.ps1`: sixteen cases, 3.5 s, exit 0 on 2026-11-21 (CANONR-0165): the Play track and
lifecycle readings, the schema-1 fold with legacy Play rows read through the fold, the render, `show` and the portfolio
reader, and `probe` and `import` over a Play channel. On 2026-11-17 (S0092) a direct read-only run of the probes against
doc-html-translate's public identities returned the live versions of GitHub, winget, the Microsoft Store, Chrome and
Edge, and one public VS Code extension. The Play API itself was not called for 0.2. Generated vectors are owed
(section 4 of the contract).
